Program AssistantTraceTest;

{ Console checks for the current-turn trace model (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils, AssistantTrace, AssistantEvents;

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

Procedure TestImageRowTallerThanText;
Var
  None, Refs: TTraceImageRefArray;
  W, H: Integer;
Begin
  SetLength(None, 0);
  SetLength(Refs, 1);
  Refs[0].Id := 'img100';
  Refs[0].Name := 'wide.png';
  Refs[0].Width := 100;
  Refs[0].Height := 50;
  Refs[0].Missing := False;
  Check('100 by 50 image row is taller than the same text',
    UserImageRowHeight(Refs, 400, 96) > UserImageRowHeight(None, 400, 96));
  Check('100 by 50 stays 1:1 in a wide bubble', ScaledImageExtent(100, 50, 400, 96, W, H) And (W = 100) And (H = 50));
End;

Procedure TestBlocks;
Var
  Trace: TAssistantTrace;
  Think, Tool, Answer: TTraceBlock;
Begin
  Trace := TAssistantTrace.Create;
  Try
    Trace.AddUser('please review');
    Think := Trace.StartThinking(0);
    Think.Body := 'Looking at Foo.pas';
    Check('user first', (Trace.Count >= 1) And (Trace[0].Kind = tbkUser));
    Check('thinking running', Assigned(Think) And Think.Running);
    Tool := Trace.AddTool('call_1', 'read_file', '{"path":"Source/Foo.pas"}');
    Check('thinking finished for tool', Not Think.Running);
    Check('tool caption has file', Pos('Foo.pas', Tool.Title) > 0);
    Check('new tool starts collapsed', Tool.Collapsed);
    Trace.CollapseThinking;
    Check('thinking collapsed', Think.Collapsed And (Not Think.Running));
    Check('thinking title', Pos('Thinking', Think.Title) > 0);
    Answer := Trace.EnsureAnswer;
    Answer.Body := 'Looks fine.';
    Check('same answer', Trace.EnsureAnswer = Answer);
    Tool := Trace.FindTool('call_1');
    Check('find tool', Assigned(Tool) And (Tool.ToolName = 'read_file'));
    Trace.AddTool('call_1', 'read_file', '{"path":"Source/Foo.pas"}');
    Check('reuse tool id', Trace.Count = 4);
  Finally
    Trace.Free;
  End;
End;

Procedure TestEnsureUser;
Var
  Trace: TAssistantTrace;
  User: TTraceBlock;
Begin
  Trace := TAssistantTrace.Create;
  Try
    Check('empty ensure skips', Trace.EnsureUser('') = Nil);
    Trace.StartThinking(0);
    User := Trace.EnsureUser('please review');
    Check('ensure user first', (Trace.Count >= 1) And (Trace[0].Kind = tbkUser));
    Check('ensure user body', User.Body = 'please review');
    Check('ensure user reuse', Trace.EnsureUser('please review') = User);
    Check('stable block identity', Trace[0].ID <> '');
  Finally
    Trace.Free;
  End;
End;

Procedure TestEventOrder;
Var
  Trace: TAssistantTrace;
  FirstAnswer, FinalAnswer: TTraceBlock;
Begin
  Trace := TAssistantTrace.Create;
  Try
    Trace.AddUser('what does this project do?');
    Trace.StartThinking(0);
    FirstAnswer := Trace.EnsureAnswer;
    FirstAnswer.Body := 'early content';
    Trace.AddTool('call_1', 'get_project_info', '{}');
    Trace.StartThinking(1);
    Trace.AddTool('call_2', 'read_file', '{"path":"Main.pas"}');
    FinalAnswer := Trace.EnsureAnswer;
    FinalAnswer.Body := 'final answer';
    Check('user first', Trace[0].Kind = tbkUser);
    Check('think then answer', (Trace[1].Kind = tbkThinking) And (Trace[2].Kind = tbkAnswer));
    Check('intermediate stays put', Trace[2] = FirstAnswer);
    Check('tool after intermediate', Trace[3].Kind = tbkTool);
    Check('new answer after later tools', FinalAnswer <> FirstAnswer);
    Check('final answer last', Trace[Trace.Count - 1] = FinalAnswer);
    Check('reuse last answer', Trace.EnsureAnswer = FinalAnswer);
    Check('thinking finished before tool', Not Trace[1].Running);
  Finally
    Trace.Free;
  End;
End;

Procedure TestToolCaptionsAndResults;
Var
  Trace: TAssistantTrace;
  Tool: TTraceBlock;
  Event: TAssistantEvent;
Begin
  Check('replace caption is path only',
    Pos('Selectable', ToolCardCaption('replace_in_file',
      '{"path":"Planner.pas","old_text":"Selectable: Boolean; { False = no highlight}"}')) < 1);
  Check('replace caption has file',
    Pos('Planner.pas', ToolCardCaption('replace_in_file',
      '{"path":"Planner.pas","old_text":"Selectable: Boolean;"}')) > 0);
  Check('grep caption keeps query',
    Pos('CalendarSubject', ToolCardCaption('grep',
      '{"pattern":"CalendarSubject","path":"Source"}')) > 0);
  Trace := TAssistantTrace.Create;
  Try
    Tool := Trace.AddTool('call_9', 'replace_in_file', '{"path":"Main.pas","old_text":"Foo"}');
    Check('replace row collapsed', Tool.Collapsed);
    Event := Default(TAssistantEvent);
    Event.Kind := aekToolCompleted;
    Event.ToolId := 'call_9';
    Event.ToolName := 'replace_in_file';
    Event.Ok := True;
    Event.Text := 'Replaced 1 occurrence(s) in Main.pas. Updated open editor buffer and saved to disk.';
    Event.DurationMs := 12;
    Trace.ApplyEvent(Event);
    Check('ok result stored on body', Pos('Replaced 1', Tool.Body) > 0);
    Check('ok result stays collapsed', Tool.Collapsed);
    Tool := Trace.AddTool('call_10', 'replace_in_file', '{"path":"Main.pas","old_text":"Bar"}');
    Event.ToolId := 'call_10';
    Event.Ok := False;
    Event.Text := 'Error: old_text not found in open editor buffer: Main.pas';
    Trace.ApplyEvent(Event);
    Check('failed result stored', Pos('old_text not found', Tool.Body) > 0);
    Check('failed result expands', Not Tool.Collapsed);
    Check('failed title marks failed', Pos('failed', LowerCase(Tool.Title)) > 0);
  Finally
    Trace.Free;
  End;
End;

Procedure TestElapsed;
Begin
  Check('short content follows', ScrollShouldFollowTail(0, 100, 200, 24));
  Check('at max follows', ScrollShouldFollowTail(400, 500, 100, 24));
  Check('within slop follows', ScrollShouldFollowTail(380, 500, 100, 24));
  Check('scrolled up stays', Not ScrollShouldFollowTail(0, 500, 100, 24));
  Check('mid view stays', Not ScrollShouldFollowTail(100, 500, 100, 24));
  Check('subsecond', Pos('s', FormatThoughtElapsed(4200)) > 0);
  Check('zero', FormatThoughtElapsed(0) = '0.0s');
  Check('clock under a minute', FormatThinkingClock(12000) = '0:12');
  Check('clock one minute', FormatThinkingClock(60000) = '1:00');
  Check('thought footer', FormatThoughtFooter(12000) = 'Thought for 0:12');
  Check('worked under an hour', FormatWorkedFooter(125000) = 'Worked for 2:05');
  Check('worked over an hour', FormatWorkedFooter(3723000) = 'Worked for 1:02:03');
End;

Procedure TestFooters;
Var
  Trace: TAssistantTrace;
  Think, Answer, Note: TTraceBlock;
Begin
  Trace := TAssistantTrace.Create;
  Try
    Trace.AddUser('please review');
    Think := Trace.StartThinking(0);
    Think.Body := 'Looking at Foo.pas';
    Think.DurationMs := 45000;
    Trace.FinishCurrentThinking;
    Check('completed title has no clock', Think.Title = 'Thinking');
    Check('thought footer on completed think', Think.Footer = 'Thought for 0:45');
    Check('thinking not running', Not Think.Running);
    Check('running title still clocks', Pos('Thinking…', ThinkingCardTitle(12000, True)) = 1);
    Answer := Trace.EnsureAnswer;
    Answer.Body := 'Looks fine.';
    Trace.ApplyWorkedFooter(125000);
    Check('worked is last card', Trace[Trace.Count - 1].Kind = tbkWorked);
    Check('worked card text', Trace[Trace.Count - 1].Body = 'Worked for 2:05');
    Check('answer has no worked footer', Answer.Footer = '');
    Note := Trace.AddNote('*Stream cancelled.*');
    Check('note inserts before worked', (Note.Kind = tbkNote) And (Trace[Trace.Count - 2] = Note));
    Trace.ApplyWorkedFooter(3661000);
    Check('worked stays last after note', Trace[Trace.Count - 1].Kind = tbkWorked);
    Check('worked card updates', Trace[Trace.Count - 1].Body = 'Worked for 1:01:01');
    Check('thinking duration sum', Trace.ThinkingDurationMs = 45000);
  Finally
    Trace.Free;
  End;
End;

Procedure TestGrowingSnapshotReusesCards;
Var
  Trace: TAssistantTrace;
  Think, Answer, Think2, Answer2: TTraceBlock;
Begin
  Trace := TAssistantTrace.Create;
  Try
    Trace.AddUser('Please review this project for bugs?');
    Think := Trace.StartThinking(0);
    Think.Body := 'The user wants me to review the project for bugs. Looking at the IDE context:';
    Answer := Trace.EnsureAnswer;
    Answer.Body := 'I''ll start from';
    Check('ensure answer reuses', Trace.EnsureAnswer = Answer);
    Check('thinking stays this sample', Trace.LatestBlockSinceLastTool(tbkThinking) = Think);
    Answer.Body := 'I''ll start from the active project tree and walk';
    Check('second snapshot still one answer', Trace.EnsureAnswer = Answer);
    Check('user+think+answer only', Trace.Count = 3);
    Check('thinking stays open while message grows', Think.Running);
    Trace.AddTool('call_1', 'read_file', '{"path":"A.pas"}');
    Check('thinking closed on tool', Not Think.Running);
    Check('answer closed on tool', Not Answer.Running);
    Check('no thinking card after last tool', Trace.LatestBlockSinceLastTool(tbkThinking) = Nil);
    Check('no answer card after last tool', Trace.LatestBlockSinceLastTool(tbkAnswer) = Nil);
    Think2 := Trace.StartThinking(1);
    Answer2 := Trace.EnsureAnswer;
    Answer2.Body := 'Here is the review.';
    Check('new thinking after tool', Think2 <> Think);
    Check('new answer after tool', Answer2 <> Answer);
    Check('six cards after next sample', Trace.Count = 6);
  Finally
    Trace.Free;
  End;
End;

Procedure TestLiveChannelSlice;
Var
  StartAt: Integer;
Begin
  StartAt := 1;
  Check('first loop whole', SliceLiveChannel('hello', StartAt) = 'hello');
  StartAt := Length('I will review this project.') + 1;
  Check('same loop after tool is empty', SliceLiveChannel('I will review this project.', StartAt) = '');
  Check('start stays past end when empty', StartAt > Length('I will review this project.'));
  { New loop must reset StartAt; slicing alone must not reopen the previous body. }
  Check('stale start does not steal a shorter loop', SliceLiveChannel('Here is the review.', StartAt) = '');
  StartAt := 1;
  Check('new loop after reset', SliceLiveChannel('Here is the review.', StartAt) = 'Here is the review.');
  StartAt := 0;
  Check('zero start', SliceLiveChannel('ab', StartAt) = 'ab');
  StartAt := High(Integer);
  Check('frozen after tool ignores period', SliceLiveChannel('hello.', StartAt) = '');
  Check('period is not an answer', Not SliceLooksLikeAnswer('.'));
  Check('real answer', SliceLooksLikeAnswer('Gathering the main sources'));
End;

Procedure TestTraceJsonRoundTrip;
Var
  Trace: TAssistantTrace;
  Json: String;
Begin
  Trace := TAssistantTrace.Create;
  Try
    Trace.AddUser('please review');
    Trace.StartThinking(0).Body := 'Looking at Foo.pas';
    Trace.FinishCurrentThinking;
    Trace.AddTool('call_1', 'get_project_info', '{}');
    Trace.StartThinking(1).Body := 'Now read the units.';
    Trace.FinishCurrentThinking;
    Trace.EnsureAnswer.Body := 'Looks fine.';
    Json := Trace.SaveToJson;
    Check('json is array', (Length(Json) > 0) And (Json[1] = '['));
    Check('json one line', Pos(#10, Json) < 1);
    Trace.LoadFromJson(Json);
    Check('roundtrip count', Trace.Count = 5);
    Check('roundtrip user', Trace[0].Kind = tbkUser);
    Check('roundtrip think 0', (Trace[1].Kind = tbkThinking) And (Pos('Foo.pas', Trace[1].Body) > 0));
    Check('roundtrip tool', (Trace[2].Kind = tbkTool) And (Trace[2].ToolName = 'get_project_info'));
    Check('roundtrip think 1', (Trace[3].Kind = tbkThinking) And (Pos('units', Trace[3].Body) > 0));
    Check('roundtrip answer', (Trace[4].Kind = tbkAnswer) And (Pos('Looks fine', Trace[4].Body) > 0));
    Check('joined answers', Pos('Looks fine', Trace.JoinedAnswers) > 0);
  Finally
    Trace.Free;
  End;
End;

Procedure TestReplayEvents;
Var
  Trace: TAssistantTrace;
  Events: TAssistantEventArray;
  Event: TAssistantEvent;
Begin
  SetLength(Events, 3);
  Event := Default(TAssistantEvent);
  Event.Kind := aekToolStarted;
  Event.ToolName := 'read_file';
  Event.ToolId := 'call_1';
  Event.Text := '{"path":"Foo.pas"}';
  Events[0] := Event;
  Event := Default(TAssistantEvent);
  Event.Kind := aekToolCompleted;
  Event.ToolName := 'read_file';
  Event.ToolId := 'call_1';
  Event.Ok := True;
  Event.DurationMs := 30;
  Event.Text := 'File: Foo.pas (12 lines total); lines 1–12';
  Events[1] := Event;
  Event := Default(TAssistantEvent);
  Event.Kind := aekTurnEnded;
  Events[2] := Event;
  Trace := TAssistantTrace.Create;
  Try
    Check('replay ok', Trace.ReplayEvents('please review', Events, 'Looking at Foo.pas', 'Looks fine.'));
    Check('replay user', (Trace.Count >= 1) And (Trace[0].Kind = tbkUser));
    Check('replay thinking filled', Pos('Foo.pas', Trace.JoinedThinking) > 0);
    Check('replay has tool', Assigned(Trace.FindTool('call_1')));
    Check('replay tool not running', Assigned(Trace.FindTool('call_1')) And (Not Trace.FindTool('call_1').Running));
    Check('replay tool body', Pos('Foo.pas', Trace.FindTool('call_1').Body) > 0);
    Check('replay answer', Pos('Looks fine', Trace.JoinedAnswers) > 0);
  Finally
    Trace.Free;
  End;
End;

Procedure TestTraceMarkdownExport;
Var
  Trace: TAssistantTrace;
  Md: String;
  Block: TTraceBlock;
Begin
  Trace := TAssistantTrace.Create;
  Try
    Trace.AddUser('please review');
    Block := Trace.AddSubagent('sub_1', 'pascal-review', 'Subagent · Review');
    Block.Running := False;
    Block.Body := 'No F-prefix issues.';
    Block.Footer := '24.9s';
    Trace.EnsureAnswer.Body := 'Merged findings.';
    Trace.FinishCurrentAnswer;
    Md := Trace.FormatMarkdown(False);
    Check('export skips user', Pos('### User', Md) < 1);
    Check('export has subagent heading', Pos('### Subagent · Review', Md) > 0);
    Check('export has subagent body', Pos('No F-prefix issues', Md) > 0);
    Check('export has assistant', Pos('### Assistant', Md) > 0);
    Check('export has answer', Pos('Merged findings', Md) > 0);
    Trace.ApplyWorkedFooter(125000);
    Md := Trace.FormatMarkdown(False);
    Check('export has worked footer', Pos('*Worked for 2:05*', Md) > 0);
    Md := Trace.FormatMarkdown(True);
    Check('export can include user', Pos('### User', Md) > 0);
  Finally
    Trace.Free;
  End;
End;

Procedure TestSteerImages;
Var
  Trace: TAssistantTrace;
  Event: TAssistantEvent;
  I, UserImages: Integer;
  Steer: TTraceBlock;
Begin
  Trace := TAssistantTrace.Create;
  Try
    Event := Default(TAssistantEvent);
    Event.Kind := aekSteerQueued;
    Event.Text := 'use this instead';
    Event.AttachmentsJson := '[{"id":"img1","name":"shot.png","display":".assistant/images/img1.png","width":100,"height":50}]';
    Trace.ApplyEvent(Event);
    Steer := Trace.FindLatestSteer;
    Check('steer block queued', Assigned(Steer) And (Steer.Body = 'use this instead'));
    Check('steer text is not a file note', Pos('shot.png', Steer.Body) = 0);
    UserImages := 0;
    For I := 0 To Trace.Count - 1 Do
      If (Trace[I].Kind = tbkUser) And (Length(Trace[I].ImageRefs) = 1) And (Trace[I].ImageRefs[0].Id = 'img1') Then
        Inc(UserImages);
    Check('steer image is a user block', UserImages = 1);
    Event := Default(TAssistantEvent);
    Event.Kind := aekInterjected;
    Event.Text := 'use this instead';
    Trace.ApplyEvent(Event);
    Check('steer applied after image block', Assigned(Steer) And (Steer.Title = 'Steer · applied') And (Not Steer.Running));
    UserImages := 0;
    For I := 0 To Trace.Count - 1 Do
      If (Trace[I].Kind = tbkUser) And (Length(Trace[I].ImageRefs) > 0) Then
        Inc(UserImages);
    Check('applied steer did not duplicate the image', UserImages = 1);
  Finally
    Trace.Free;
  End;
End;

Begin
  FailCount := 0;
  TestBlocks;
  TestImageRowTallerThanText;
  TestSteerImages;
  TestEnsureUser;
  TestEventOrder;
  TestToolCaptionsAndResults;
  TestElapsed;
  TestFooters;
  TestGrowingSnapshotReusesCards;
  TestLiveChannelSlice;
  TestTraceJsonRoundTrip;
  TestReplayEvents;
  TestTraceMarkdownExport;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantTrace tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantTrace test(s) failed.');
      Halt(1);
    End;
End.
