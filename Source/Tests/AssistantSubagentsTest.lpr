Program AssistantSubagentsTest;

{ Console checks for subagent kinds, depth gate, spawn JSON, and review prompts (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, SysUtils, AssistantConversation, AssistantEvents, AssistantTrace, AssistantSubagents;

Var
  FailCount: Integer;

Procedure Check(Const Title: String; Condition: Boolean);
Begin
  If Condition Then
    WriteLn('ok   ', Title)
  Else
    Begin
      WriteLn('FAIL ', Title);
      Inc(FailCount);
    End;
End;

Procedure TestKinds;
Begin
  Check('explore name', SubagentKindName(sakExplore) = 'explore');
  Check('naming name', SubagentKindName(sakPascalNaming) = 'pascal-naming');
  Check('parse general underscore', ParseSubagentKind('general_purpose') = sakGeneralPurpose);
  Check('parse naming alias', ParseSubagentKind('naming') = sakPascalNaming);
  Check('parse review', ParseSubagentKind('pascal-review') = sakPascalReview);
  Check('unknown falls to explore', ParseSubagentKind('syntax-bot') = sakExplore);
  Check('explore is inspect tools', SubagentModeForKind(sakExplore, amBuild) = amInspect);
  Check('plan kind is plan tools', SubagentModeForKind(sakPlan, amBuild) = amPlan);
  Check('general inherits parent', SubagentModeForKind(sakGeneralPurpose, amBuild) = amBuild);
  Check('general inspect stays inspect', SubagentModeForKind(sakGeneralPurpose, amInspect) = amInspect);
  Check('naming is read-only', SubagentModeForKind(sakPascalNaming, amBuild) = amInspect);
End;

Procedure TestCanSpawn;
Var
  Err: String;
Begin
  Check('parent with room', CanSpawnSubagent(True, 0, Err));
  Check('parent at two', CanSpawnSubagent(True, 2, Err));
  Check('parent at cap fails', (Not CanSpawnSubagent(True, MaxLiveSubagents, Err)) And (Pos('Too many', Err) > 0));
  Check('child rejected', (Not CanSpawnSubagent(False, 0, Err)) And (Pos('parent-only', Err) > 0));
  Check('max is 3', MaxLiveSubagents = 3);
  Check('naming is a review lens', IsReviewLensKind(sakPascalNaming));
  Check('explore is not a review lens', Not IsReviewLensKind(sakExplore));
  Check('runtime budget is 3 minutes', MaxSubagentRuntimeMs = 180000);
  Check('child tool rounds capped', MaxSubagentToolRounds = 8);
  Check('not timed out at start', Not SubagentRunTimedOut(1000, 1000));
  Check('timed out at budget', SubagentRunTimedOut(1000, 1000 + MaxSubagentRuntimeMs));
  Check('not timed out just under', Not SubagentRunTimedOut(1000, 1000 + MaxSubagentRuntimeMs - 1));
  Check('xhigh is capped', SubagentReasoningEffort('xhigh') = 'high');
  Check('high stays high', SubagentReasoningEffort('high') = 'high');
  Check('medium stays', SubagentReasoningEffort('medium') = 'medium');
End;

Procedure TestParseSpawn;
Var
  Request: TSubagentRequest;
  Err: String;
  Ok: Boolean;
Begin
  Ok := ParseSpawnSubagentArguments(
    '{"kind":"pascal-naming","title":"Foo names","prompt":"Review Foo.pas","files":"Source/Foo.pas"}',
    Request, Err);
  Check('parse ok', Ok);
  Check('parse kind', Request.Kind = sakPascalNaming);
  Check('parse title', Request.Title = 'Foo names');
  Check('parse prompt', Pos('Foo.pas', Request.Prompt) > 0);
  Check('parse files', Pos('Foo.pas', Request.Files) > 0);
  Ok := ParseSpawnSubagentArguments('{"subagent_type":"explore","prompt":"Where is TMainForm?"}', Request, Err);
  Check('alias kind', Ok And (Request.Kind = sakExplore));
  Ok := ParseSpawnSubagentArguments('{"kind":"naming"}', Request, Err);
  Check('missing prompt fails', (Not Ok) And (Pos('prompt', Err) > 0));
  Ok := ParseSpawnSubagentArguments('{"kind":"syntax","prompt":"x"}', Request, Err);
  Check('unknown kind fails', (Not Ok) And (Pos('Unknown', Err) > 0));
End;

Procedure TestPersonasAndReviewPrompt;
Var
  Request: TSubagentRequest;
  Prompt, User: String;
Begin
  Check('naming persona', Pos('pascal-naming', SubagentPersonaPrompt(sakPascalNaming)) > 0);
  Check('naming F prefix', Pos('property storage', SubagentPersonaPrompt(sakPascalNaming)) > 0);
  Check('review persona compiler', Pos('lazbuild', SubagentPersonaPrompt(sakPascalReview)) > 0);
  Check('persona bans nit slang', Pos('never "Nit"', SubagentPersonaPrompt(sakPascalReview)) > 0);
  Check('explore no edit', Pos('Do not edit', SubagentPersonaPrompt(sakExplore)) > 0);
  Prompt := BuildReviewLensesPrompt('- Source/Foo.pas');
  Check('review prompt spawn', Pos('spawn_subagent', Prompt) > 0);
  Check('review prompt naming', Pos('pascal-naming', Prompt) > 0);
  Check('review prompt structure', Pos('pascal-structure', Prompt) > 0);
  Check('review prompt review', Pos('pascal-review', Prompt) > 0);
  Check('review prompt files', Pos('Source/Foo.pas', Prompt) > 0);
  Prompt := BuildReviewLensesPrompt('');
  Check('empty files still instructs', Pos('No dirty editor', Prompt) > 0);
  Request.Kind := sakPascalReview;
  Request.Title := 'Review';
  Request.Prompt := 'Check Foo.pas';
  Request.Files := 'Source/Foo.pas';
  User := BuildSubagentUserPrompt(Request, 'Foo.pas(10,1) Error: identifier not found');
  Check('user has task', Pos('Check Foo.pas', User) > 0);
  Check('user has files', Pos('Source/Foo.pas', User) > 0);
  Check('user has compile log', Pos('identifier not found', User) > 0);
End;

Procedure TestTitlesAndResult;
Var
  ResultText: String;
Begin
  Check('running title', Pos('Subagent running: Naming', SubagentRunningTitle('Naming', 'Thinking…')) > 0);
  Check('finished title', SubagentFinishedTitle('Naming', 'Naming') = 'Subagent · Naming');
  Check('finished with extra', Pos('Foo', SubagentFinishedTitle('Naming', 'Foo')) > 0);
  ResultText := FormatSubagentToolResult('pascal-naming', 'Foo', 'No F-prefix issues.', True, 1200);
  Check('result kind', Pos('pascal-naming', ResultText) > 0);
  Check('result body', Pos('No F-prefix issues', ResultText) > 0);
  Check('spawn name', IsSpawnSubagentName('spawn_subagent'));
  Check('spawn name reject', Not IsSpawnSubagentName('run_compile'));
End;

Procedure TestEventsAndTrace;
Var
  Event: TAssistantEvent;
  Line: String;
  Trace: TAssistantTrace;
  Block: TTraceBlock;
Begin
  Event := Default(TAssistantEvent);
  Event.Kind := aekSubagentStarted;
  Event.ToolName := 'pascal-naming';
  Event.ToolId := 'sub_1';
  Event.Text := 'Naming';
  Line := AssistantEventToJson(Event);
  Check('event type', Pos('"type":"subagent_started"', Line) > 0);
  Check('event kind field', Pos('pascal-naming', Line) > 0);
  Event.Kind := aekSubagentCompleted;
  Line := AssistantEventToJson(Event);
  Check('event completed', Pos('subagent_completed', Line) > 0);
  Trace := TAssistantTrace.Create;
  Try
    Block := Trace.AddSubagent('sub_1', 'pascal-naming', 'Subagent running: Naming — Starting');
    Check('subagent kind', Block.Kind = tbkSubagent);
    Check('subagent find', Trace.FindSubagent('sub_1') = Block);
    Check('running by kind', Trace.FindRunningSubagentByKind('pascal-naming') = Block);
    Event.Kind := aekSubagentProgress;
    Event.ToolId := 'other_id';
    Event.ToolName := 'pascal-naming';
    Event.Text := 'Waiting for model…';
    Trace.ApplyEvent(Event);
    Check('progress does not add a fourth card', Trace.Count = 1);
    Block.DurationMs := MaxSubagentRuntimeMs;
    Check('expired running lens', Trace.HasRunningSubagentOlderThan(MaxSubagentRuntimeMs));
    Block.DurationMs := 10;
    Check('fresh lens not expired', Not Trace.HasRunningSubagentOlderThan(MaxSubagentRuntimeMs));
    Check('names listed', ReviewLensAlreadyListed(sakPascalNaming, ['pascal-naming', 'pascal-structure'], 1));
    Check('names not listed', Not ReviewLensAlreadyListed(sakPascalReview, ['pascal-naming', 'pascal-structure'], 1));
    Block.Running := False;
    Block.Body := 'Looks fine.';
    Check('json has subagent', Pos('subagent', Trace.SaveToJson) > 0);
    Trace.LoadFromJson(Trace.SaveToJson);
    Check('roundtrip subagent', (Trace.Count = 1) And (Trace[0].Kind = tbkSubagent) And
      (Trace[0].ToolName = 'pascal-naming'));
  Finally
    Trace.Free;
  End;
End;

Begin
  FailCount := 0;
  TestKinds;
  TestCanSpawn;
  TestParseSpawn;
  TestPersonasAndReviewPrompt;
  TestTitlesAndResult;
  TestEventsAndTrace;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantSubagents tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantSubagents test(s) failed.');
      Halt(1);
    End;
End.
