Program AssistantMonitorFixtureTest;

{ Golden version 4 fixtures. The host encoders must produce these files.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, AssistantMonitorSnapshot, AssistantMonitorCodec;

Var
  FailCount: Integer;
  WriteMode: Boolean;

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

Function RepositoryRoot: String;
Var
  Index: Integer;
  Dir: String;
Begin
  Dir := GetCurrentDir;
  For Index := 1 To 8 Do
    Begin
      If DirectoryExists(IncludeTrailingPathDelimiter(Dir) + 'Tests') And
        DirectoryExists(IncludeTrailingPathDelimiter(Dir) + 'Source') Then
        Exit(ExcludeTrailingPathDelimiter(Dir));
      Dir := ExpandFileName(IncludeTrailingPathDelimiter(Dir) + '..');
    End;
  Result := GetCurrentDir;
End;

Function FixtureDir: String;
Begin
  Result := IncludeTrailingPathDelimiter(RepositoryRoot) + 'Tests' + PathDelim + 'Fixtures' + PathDelim + 'Monitor' +
    PathDelim + 'v4';
End;

Function LoadText(Const Path: String): String;
Var
  Lines: TStringList;
Begin
  Lines := TStringList.Create;
  Try
    Lines.LoadFromFile(Path);
    Result := Trim(Lines.Text);
  Finally
    Lines.Free;
  End;
End;

Procedure Keep(Const Name, Body: String);
Var
  Path: String;
  Lines: TStringList;
Begin
  Path := IncludeTrailingPathDelimiter(FixtureDir) + Name;
  If WriteMode Or (Not FileExists(Path)) Then
    Begin
      ForceDirectories(FixtureDir);
      Lines := TStringList.Create;
      Try
        Lines.Text := Body + LineEnding;
        Lines.SaveToFile(Path);
      Finally
        Lines.Free;
      End;
    End;
  If Not FileExists(Path) Then
    Begin
      Check(Name + ' exists', False);
      WriteLn(Body);
      Exit;
    End;
  Check(Name, LoadText(Path) = Body);
  If LoadText(Path) <> Body Then
    WriteLn(Body);
End;

Function Capabilities: TStringList;
Const
  Names: Array[0..14] Of String = (
    'send', 'steer', 'stop', 'approval', 'set_mode', 'new_conversation', 'select_conversation', 'select_plan',
    'new_plan', 'close_plan', 'run_plan', 'stop_plan', 'work_on_plan', 'run_task', 'insert_task');
Var
  Index: Integer;
Begin
  Result := TStringList.Create;
  For Index := 0 To High(Names) Do
    Result.Add(Names[Index]);
End;

Function LivePulse: String;
Var
  Snap: TMonitorSnapshot;
Begin
  Snap := TMonitorSnapshot.Create;
  Snap.Rev := 18234;
  Snap.Available := True;
  Snap.Busy := True;
  Snap.Sending := True;
  Snap.PlanRunning := True;
  Snap.Mode := 'build';
  Snap.Phase := 'tool';
  Snap.StatusText := 'Running';
  Snap.Activity := 'Running build';
  Snap.ActivitySince := '2026-11-24T10:11:36.004Z';
  Snap.TurnStartedAt := '2026-11-24T10:11:36.004Z';
  Snap.CanSteer := True;
  Snap.CanStop := True;
  Snap.RemoteApproval := True;
  Snap.ConversationId := '11111111-1111-1111-1111-111111111111';
  Snap.ConversationTitle := 'Plan work';
  Snap.ConversationEtag := 'etag-conv';
  Snap.TurnCount := 37;
  Snap.HasLive := True;
  Snap.LiveTurnId := 'turn-live';
  Snap.LiveTurnIndex := 37;
  Snap.LiveRev := 96;
  SetLength(Snap.Items, 1);
  Snap.Items[0].Id := 'item-live';
  Snap.Items[0].Kind := 'thinking';
  Snap.Items[0].State := 'running';
  Snap.Items[0].Revision := 95;
  Snap.Items[0].Body := 'hello';
  Snap.PlanPath := 'Documents/Plan.md';
  Snap.PlanEtag := 'etag-plan';
  Snap.PlanItemRunning := True;
  Snap.PlanItem := '3.2';
  Snap.ListConversations := 'list-c';
  Snap.ListPlans := 'list-p';
  Snap.ListTasks := 'list-t';
  Snap.ApprovalActive := True;
  Snap.ApprovalId := 'tool-1';
  Snap.ApprovalTool := 'run_build';
  Result := MonitorPulseJson(Snap, 'epoch-1', '2026-11-24T10:15:02.120Z');
  Snap.Release;
End;

Function IdlePulse: String;
Var
  Snap: TMonitorSnapshot;
Begin
  Snap := TMonitorSnapshot.Create;
  Snap.Rev := 10;
  Snap.Available := True;
  Snap.CanSend := True;
  Snap.CanChangeMode := True;
  Snap.Mode := 'agent';
  Snap.Phase := 'idle';
  Snap.StatusText := 'Ready';
  Snap.ConversationId := '11111111-1111-1111-1111-111111111111';
  Snap.ConversationTitle := 'Plan work';
  Snap.ConversationEtag := 'etag-conv';
  Snap.TurnCount := 4;
  Result := MonitorPulseJson(Snap, 'epoch-1', '2026-11-24T10:15:02.120Z');
  Snap.Release;
End;

Procedure CheckAll;
Var
  Names: TStringList;
  Turn, Item, Rows, Args: String;
Begin
  Keep('pulse-live.json', LivePulse);
  Keep('pulse-idle.json', IdlePulse);
  Keep('pulse-sending.json', MonitorPulseJson(Nil, 'epoch-1', '2026-11-24T10:15:02.120Z', True));
  Keep('error-protocol.json', MonitorErrorJson('protocol', 'That request is not valid.'));
  Keep('error-auth.json', MonitorErrorJson('auth', 'The token was not accepted.'));
  Keep('error-revoked.json', MonitorErrorJson('revoked', 'This phone was revoked.'));
  Keep('error-not-found.json', MonitorErrorJson('not_found', 'That monitor path is not available.'));
  Keep('error-busy.json', MonitorErrorJson('busy', 'The assistant is busy.'));
  Keep('error-unsaved-edits.json', MonitorErrorJson('unsaved_edits', 'Save the editor changes first.'));
  Keep('error-too-large.json', MonitorErrorJson('too_large', 'That image is too large.'));
  Keep('error-no-session.json', MonitorErrorJson('no_session', 'The assistant window is closed.'));
  Keep('command-done.json', MonitorDoneJson('done', ''));
  Keep('command-done-turn.json', MonitorDoneJson('done', 'turn-1'));
  Keep('command-accepted.json', MonitorDoneJson('accepted', ''));
  Keep('pair.json', MonitorPairJson('token-1', 'desk', 'fingerprint-1'));
  Names := Capabilities;
  Try
    Keep('hello.json', MonitorHelloJson('epoch-1', 0, Names));
  Finally
    Names.Free;
  End;
  Keep('approval.json', MonitorApprovalBody('tool-1', 'run_build', 'Run the build', 'Ask', True));
  Rows := '[{"index":1,"level":2,"title":"Review","parent_title":"","status":"not started","actionable":true}]';
  Keep('plan.json', MonitorPlanJson('Documents/Plan.md', 'Plan', 'etag-plan', True, Rows));
  Keep('plan-document.json', '{"content_type":"text/markdown; charset=utf-8","body":"# Plan\n"}');
  Keep('plans.json', MonitorChoiceListJson('plans', '[{"path":"Documents/Plan.md","title":"Plan"}]'));
  Keep('tasks.json', MonitorChoiceListJson('tasks', '[{"id":"task-1","title":"Review","needs_note":false}]'));
  Keep('image-meta.json', MonitorImageMetaJson('image/png', 'immutable', 1048576));
  Keep('conversations.json', '[' + MonitorConversationJson('11111111-1111-1111-1111-111111111111', 'Plan work',
    '2026-11-24T10:00:00Z', 'etag-conv', 1, True) + ']');
  Item := '{"id":"item-1","kind":"answer","state":"done","rev":3,"bytes":5,"body":"hello"}';
  Turn := MonitorTurnJson('turn-1', 'etag-turn', 'build', 'ask', '2026-11-24T10:00:00Z', '', '[' + Item + ']', False);
  Keep('turn-bodies.json', Turn);
  Keep('turn-outline.json', MonitorTurnJson('turn-1', 'etag-turn', 'build', 'ask', '2026-11-24T10:00:00Z', '',
    '[{"id":"item-1","kind":"answer","state":"done","rev":3,"bytes":5}]', False));
  Keep('turns.json', MonitorTurnsPageJson('11111111-1111-1111-1111-111111111111', 'etag-conv', 0, 1, 1, '[' + Turn + ']'));
  Keep('item-full.json', MonitorItemJson('item-1', 'done', 'hello', 3, 5, 0));
  Keep('item-tail.json', MonitorItemJson('item-1', 'running', 'lo', 4, 5, 3));
  Args := '{"text":"Hello","save_first":false}';
  Keep('request-send.json', MonitorCommandRequestJson('cmd-send', 'send', Args));
  Keep('request-steer.json', MonitorCommandRequestJson('cmd-steer', 'steer', '{"text":"Stop there"}'));
  Keep('request-stop.json', MonitorCommandRequestJson('cmd-stop', 'stop', '{}'));
  Keep('request-approval.json', MonitorCommandRequestJson('cmd-approval', 'approval',
    '{"tool_id":"tool-1","decision":"allow"}'));
  Keep('request-set-mode.json', MonitorCommandRequestJson('cmd-mode', 'set_mode', '{"mode":"build"}'));
  Keep('request-new-conversation.json', MonitorCommandRequestJson('cmd-new', 'new_conversation', '{}'));
  Keep('request-select-conversation.json', MonitorCommandRequestJson('cmd-select', 'select_conversation',
    '{"id":"11111111-1111-1111-1111-111111111111"}'));
  Keep('request-select-plan.json', MonitorCommandRequestJson('cmd-plan', 'select_plan', '{"path":"Documents/Plan.md"}'));
  Keep('request-new-plan.json', MonitorCommandRequestJson('cmd-new-plan', 'new_plan', '{"title":"Plan"}'));
  Keep('request-close-plan.json', MonitorCommandRequestJson('cmd-close', 'close_plan', '{}'));
  Keep('request-run-plan.json', MonitorCommandRequestJson('cmd-run', 'run_plan', '{"save_first":true}'));
  Keep('request-stop-plan.json', MonitorCommandRequestJson('cmd-stop-plan', 'stop_plan', '{}'));
  Keep('request-work-on-plan.json', MonitorCommandRequestJson('cmd-work', 'work_on_plan', '{"section":2}'));
  Keep('request-run-task.json', MonitorCommandRequestJson('cmd-task', 'run_task',
    '{"task_id":"task-1","note":"","save_first":false}'));
  Keep('request-insert-task.json', MonitorCommandRequestJson('cmd-insert', 'insert_task',
    '{"task_id":"task-1","note":"Do this"}'));
End;

Begin
  FailCount := 0;
  WriteMode := (ParamCount >= 1) And (ParamStr(1) = '--write');
  CheckAll;
  If FailCount = 0 Then
    WriteLn('All monitor fixture checks passed.')
  Else
    Begin
      WriteLn(FailCount, ' monitor fixture check(s) failed.');
      Halt(1);
    End;
End.
