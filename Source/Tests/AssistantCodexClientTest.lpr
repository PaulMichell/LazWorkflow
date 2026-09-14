Program AssistantCodexClientTest;
{$mode objfpc}{$H+}
Uses cthreads, Classes, SysUtils, fpjson, jsonparser,
  AssistantCodexClient, AssistantCodexHandshake, AssistantCodexRun, AssistantToolBroker,
  AssistantCodexAccount, AssistantCodexProfile;
Type
  TRunReaper = Class(TThread)
    Run: TAssistantCodexRun;
    Started, Reaped: LongInt;
    Procedure Execute; Override;
  End;
  TMemoryWorkspace = Class(TAssistantWorkspaceAdapter)
  Public
    Reads: Integer;
    Reaper: TRunReaper;
    ReaperWaited, WorkerStopped: Boolean;
    Function Identity: String; Override;
    Function ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean; Override;
    Function ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean; Override;
    Function SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean; Override;
    Function Describe: String; Override;
  End;
Procedure TRunReaper.Execute;
Begin InterlockedExchange(Started, 1); Run.Free; InterlockedExchange(Reaped, 1); End;
Function TMemoryWorkspace.Identity: String;
Begin Result := 'project-test'; End;
Function TMemoryWorkspace.ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean;
Var Deadline: QWord;
Begin
  Inc(Reads); CanonicalPath := Path; Text := 'unsaved IDE contents'; ErrorText := ''; Result := True;
  If Assigned(Reaper) Then
    Begin
      Reaper.Run.Cancel; Deadline := GetTickCount64 + 5000;
      While Not Reaper.Run.Snapshot.Done And (GetTickCount64 < Deadline) Do Sleep(1);
      WorkerStopped := Reaper.Run.Snapshot.Done;
      Reaper.Start;
      While (InterlockedCompareExchange(Reaper.Started, 0, 0) = 0) And (GetTickCount64 < Deadline) Do Sleep(1);
      Sleep(30);
      ReaperWaited := InterlockedCompareExchange(Reaper.Reaped, 0, 0) = 0;
    End;
End;
Function TMemoryWorkspace.ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean;
Begin ErrorText := 'Test is read-only'; Result := False; End;
Function TMemoryWorkspace.SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean;
Begin ErrorText := 'Test is read-only'; Result := False; End;
Function TMemoryWorkspace.Describe: String;
Begin Result := 'test project'; End;
Procedure Check(Const Name: String; OK: Boolean);
Begin
  If Not OK Then Begin WriteLn('FAIL ', Name); Halt(1); End;
  WriteLn('ok   ', Name);
End;
Procedure Send(Const Line: String);
Begin WriteLn(Line); Flush(Output); End;
Procedure FakeRuntime;
Var Line, Method, Id, Prompt: String; Data: TJSONData; Obj, Params: TJSONObject;
  I: Integer; AppsDisabled: Boolean;
Begin
  AppsDisabled := False;
  For I := 2 To ParamCount Do
    If (ParamStr(I - 1) = '-c') And (ParamStr(I) = 'features.apps=false') Then AppsDisabled := True;
  While Not EOF(Input) Do
    Begin
      ReadLn(Line); Data := GetJSON(Line);
      Try
        Obj := TJSONObject(Data); Method := Obj.Get('method', '');
        If Not Assigned(Obj.Find('id')) Then Continue;
        Id := Obj.Find('id').AsJSON;
        If Method = 'initialize' Then Send('{"id":' + Id + ',"result":{"userAgent":"codex/0.153.0"}}')
        Else If Method = 'account/read' Then Send('{"id":' + Id + ',"result":{"account":{"type":"chatgpt"},"requiresOpenaiAuth":true}}')
        Else If Method = 'thread/start' Then
          Begin
            Params := TJSONObject(Obj.Find('params'));
            If (Params.Get('permissions', '') <> 'lazarus_ide') Or
              Assigned(Params.Find('sandbox')) Or
              (Params.Get('modelProvider', '') <> 'openai') Then Halt(2);
            Send('{"id":' + Id + ',"result":{"modelProvider":"openai","approvalPolicy":"on-request","sandbox":{"type":"readOnly"},"thread":{"id":"thread-1"}}}');
          End
        Else If Method = 'mcpServerStatus/list' Then
          Begin
            If GetEnvironmentVariable('LAZ_TEST_EXTERNAL_MCP') = '1' Then
              Send('{"id":' + Id + ',"result":{"data":[{"name":"external"}],"nextCursor":null}}')
            Else If Not AppsDisabled Then
              { Real signed-in runtimes expose this server by default. }
              Send('{"id":' + Id + ',"result":{"data":[{"name":"codex_apps","tools":{"connector_tool":{}}}],"nextCursor":null}}')
            Else Send('{"id":' + Id + ',"result":{"data":[],"nextCursor":null}}');
          End
        Else If Method = 'model/list' Then Send('{"id":' + Id + ',"result":{"data":[{"id":"test-model"}],"nextCursor":null}}')
        Else If Method = 'turn/start' Then
          Begin
            Params := TJSONObject(Obj.Find('params'));
            If (Params.Get('permissions', '') <> 'lazarus_ide') Or
              Assigned(Params.Find('sandboxPolicy')) Then
              Begin
                Send('{"id":' + Id + ',"error":{"code":-32600,"message":"Use named permissions for restricted reads"}}');
                Continue;
              End;
            If Params.Get('summary', '') <> 'auto' Then Halt(3);
            Prompt := Params.FindPath('input[0].text').AsString;
            If (Prompt = 'normal') And (Params.Get('effort', '') <> 'high') Then Halt(4);
            If (Prompt <> 'normal') And Assigned(Params.Find('effort')) Then Halt(5);
            Send('{"id":' + Id + ',"result":{"turn":{"id":"turn-1","status":"inProgress"}}}');
            If Prompt = 'authchange' Then
              Begin Send('{"method":"account/updated","params":{"authMode":"apikey"}}'); Continue; End;
            If Prompt = 'hang' Then Continue;
            If Prompt = 'finalonly' Then
              Begin
                Send('{"method":"item/completed","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"answer-1","type":"agentMessage","text":"Final answer"}}}');
                Send('{"method":"item/completed","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"answer-1","type":"agentMessage","text":"Final answer"}}}');
                Send('{"method":"item/completed","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"answer-2","type":"agentMessage","text":"Second paragraph"}}}');
                Send('{"method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}');
                Continue;
              End;
            Send('{"method":"item/reasoning/summaryTextDelta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"reason-1","summaryIndex":0,"delta":"Checking **"}}');
            Send('{"method":"item/reasoning/summaryTextDelta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"reason-1","summaryIndex":0,"delta":"buffers**"}}');
            Send('{"method":"item/reasoning/summaryTextDelta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"reason-1","summaryIndex":1,"delta":"Then dependencies"}}');
            Send('{"method":"item/completed","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"reason-1","type":"reasoning","summary":["Checking **buffers**","Then dependencies"],"content":[]}}}');
            Send('{"method":"item/completed","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"reason-2","type":"reasoning","summary":["Final-only summary"],"content":[]}}}');
            Send('{"method":"item/completed","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"reason-2","type":"reasoning","summary":["Final-only summary"],"content":[]}}}');
            Send('{"method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","delta":"**"}}');
            Send('{"method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","delta":"text"}}');
            Send('{"method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","delta":"**"}}');
            Send('{"id":"tool-request","method":"item/tool/call","params":{"threadId":"thread-1","turnId":"turn-1","callId":"call-1","tool":"lazarus_read_buffer","arguments":{"path":"test.pas"}}}');
            If Prompt = 'duplicate' Then
              Send('{"id":"tool-request-2","method":"item/tool/call","params":{"threadId":"thread-1","turnId":"turn-1","callId":"call-1","tool":"lazarus_read_buffer","arguments":{}}}');
          End
        Else If Method = 'turn/interrupt' Then
          Begin
            Send('{"id":' + Id + ',"result":{}}');
            Send('{"method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"interrupted"}}}');
          End
        Else If (Method = '') And Assigned(Obj.Find('result')) Then
          Send('{"method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}');
      Finally Data.Free; End;
    End;
End;
Procedure TestWorkerBridge;
Var Workspace: TMemoryWorkspace; Broker: TAssistantToolBroker; Run: TAssistantCodexRun;
  RunId, Profile: String; Snapshot: TCodexRunSnapshot; Deadline: QWord;
Begin
  Workspace := TMemoryWorkspace.Create;
  Broker := TAssistantToolBroker.Create(Workspace);
  Run := Nil;
  Profile := GetTempFileName;
  DeleteFile(Profile);
  Try
    RunId := Broker.BeginRun(awsReadOnly);
    Run := TAssistantCodexRun.Create(ParamStr(0), GetTempDir, 'test-model',
      'normal', Broker.ToolsJson, RunId, 3000, Profile, 'high');
    Run.Start;
    Deadline := GetTickCount64 + 5000;
    Repeat
      Run.ServiceTool(Broker);
      Snapshot := Run.Snapshot;
      Sleep(1);
    Until Snapshot.Done Or (GetTickCount64 >= Deadline);
    Check('worker run completes', Snapshot.Done And (Snapshot.State = crsCompleted));
    Check('first run creates its managed profile', FileExists(Profile + '/config.toml'));
    Check('worker dispatches one IDE read through broker', Workspace.Reads = 1);
    Check('worker streams answer snapshot', Snapshot.Content = '**text**');
    Check('worker publishes reasoning for the UI', Pos('Final-only summary', Snapshot.Thinking) > 0);
    Run.Free; Run := Nil;
    RunId := Broker.BeginRun(awsReadOnly);
    Run := TAssistantCodexRun.Create(ParamStr(0), GetTempDir, 'test-model',
      'normal', Broker.ToolsJson, RunId, 3000, '', 'high');
    Run.Start; Run.Cancel; Broker.Cancel;
    Deadline := GetTickCount64 + 7000;
    Repeat Run.ServiceTool(Broker); Snapshot := Run.Snapshot; Sleep(1);
    Until Snapshot.Done Or (GetTickCount64 >= Deadline);
    Check('cancelled worker finishes', Snapshot.Done);
    Check('cancelled worker executes no IDE tools', Workspace.Reads = 1);
  Finally
    Run.Free; Broker.Free; Workspace.Free;
    DeleteFile(Profile + '/config.toml');
    RemoveDir(Profile);
  End;
End;
Procedure TestCancellationDuringTool;
Var Workspace: TMemoryWorkspace; Broker: TAssistantToolBroker; Run: TAssistantCodexRun;
  Reaper: TRunReaper; Deadline: QWord;
Begin
  Workspace := TMemoryWorkspace.Create; Broker := TAssistantToolBroker.Create(Workspace);
  Broker.BeginRun(awsReadOnly);
  Run := TAssistantCodexRun.Create(ParamStr(0), GetTempDir, 'test-model',
    'normal', Broker.ToolsJson, Broker.RunId, 3000, '', 'high');
  Reaper := TRunReaper.Create(True); Reaper.Run := Run; Workspace.Reaper := Reaper;
  Try
    Run.Start; Deadline := GetTickCount64 + 5000;
    Repeat
      Run.ServiceTool(Broker);
      If Workspace.Reads > 0 Then Break; { the reaper now owns Run; never dereference it again }
      Sleep(1);
    Until GetTickCount64 >= Deadline;
    Check('tool callback cancels a completed worker', (Workspace.Reads = 1) And Workspace.WorkerStopped);
    Run := Nil;
    Reaper.WaitFor;
    Check('reaper waits until IDE tool handoff returns', Workspace.ReaperWaited And (Reaper.Reaped = 1));
  Finally Reaper.Free; Run.Free; Broker.Free; Workspace.Free; End;
End;
Procedure TestAccount;
Var Job: TAssistantCodexAccount; Value: TCodexAccountSnapshot;
  Profile: String; Deadline: QWord; Env: TStringList; Client: TAssistantCodexClient; Id: TGuid;
Begin
  CreateGUID(Id); Profile := GetTempDir + 'laz-codex-account-' + GUIDToString(Id);
  Job := TAssistantCodexAccount.Create(ParamStr(0), Profile, False);
  Try
    Job.Start; Deadline := GetTickCount64 + 5000;
    Repeat Value := Job.Snapshot; Sleep(1); Until Value.Done Or (GetTickCount64 >= Deadline);
    Check('account worker completes discovery without a model turn', Value.Done And
      (Value.State = ccsSubscriptionAuthenticated) And (Pos('test-model', Value.ModelsJson) > 0));
  Finally Job.Cancel; Job.Free; End;
  Env := TStringList.Create; Client := TAssistantCodexClient.Create(500);
  Try
    CodexProfileEnvironment(Profile, Env);
    Check('isolated home set', Env.Values['CODEX_HOME'] = Profile);
    Check('metered API keys absent', (Env.Values['OPENAI_API_KEY'] = '') And (Env.Values['CODEX_API_KEY'] = ''));
    Env.Values['LAZ_TEST_EXTERNAL_MCP'] := '1';
    Check('external tools test connects', Client.Connect(ParamStr(0), Profile, Env));
    Deadline := GetTickCount64 + 3000;
    Repeat Client.Pump; Sleep(1); Until (Client.State = crsReady) Or (GetTickCount64 >= Deadline);
    Check('thread blocked before isolation check', Not Client.StartThread(Profile, 'test-model', '[]'));
    Client.CheckToolIsolation;
    Deadline := GetTickCount64 + 3000;
    Repeat Client.Pump; Sleep(1); Until (Client.State = crsFailed) Or (GetTickCount64 >= Deadline);
    Check('external MCP configuration rejected', (Client.State = crsFailed) And Not Client.ToolIsolationChecked);
  Finally Client.Free; Env.Free; DeleteFile(Profile + '/config.toml'); RemoveDir(Profile); End;
End;
Var Client: TAssistantCodexClient; Tool: TCodexToolRequest; Deadline: QWord; VersionEnv: TStringList;
Procedure WaitState(State: TCodexRunState);
Begin
  Deadline := GetTickCount64 + 3000;
  Repeat Client.Pump; Sleep(1);
  Until (Client.State In [State, crsFailed]) Or (GetTickCount64 > Deadline);
  Check('state ' + IntToStr(Ord(State)) + ': ' + Client.LastError, Client.State = State);
End;
Procedure Start;
Begin
  Check('start client process', Client.Connect(ParamStr(0), GetTempDir));
  WaitState(crsReady);
  Check('subscription account required', Client.Authentication.State = ccsSubscriptionAuthenticated);
  Check('isolation check queued', Client.CheckToolIsolation);
  Deadline := GetTickCount64 + 3000;
  Repeat Client.Pump; Sleep(1); Until Client.ToolIsolationChecked Or (GetTickCount64 >= Deadline);
  Check('isolation verified', Client.ToolIsolationChecked);
  Check('thread queued', Client.StartThread(GetTempDir, 'test-model', '[]'));
  WaitState(crsReady);
End;
Begin
  If ParamStr(1) = '--version' Then
    Begin
      If GetEnvironmentVariable('LAZ_TEST_CODEX_VERSION') <> '' Then WriteLn(GetEnvironmentVariable('LAZ_TEST_CODEX_VERSION'))
      Else WriteLn(QualifiedCodexVersion);
      Halt;
    End;
  If ParamCount > 0 Then Begin FakeRuntime; Halt; End;
  Client := TAssistantCodexClient.Create(500);
  Try
    VersionEnv := TStringList.Create;
    Try
      CodexProfileEnvironment(GetTempDir, VersionEnv);
      VersionEnv.Values['LAZ_TEST_CODEX_VERSION'] := PreviousQualifiedCodexVersion;
      Check('previous qualified runtime still connects', Client.Connect(ParamStr(0), GetTempDir, VersionEnv));
      Client.Disconnect;
      VersionEnv.Values['LAZ_TEST_CODEX_VERSION'] := 'codex-cli 0.153.99';
      Check('unqualified runtime remains rejected', Not Client.Connect(ParamStr(0), GetTempDir, VersionEnv)
        And (Pos('not qualified', Client.LastError) > 0));
    Finally VersionEnv.Free; End;
    Check('unauthenticated turn rejected', Not Client.StartTurn('test'));
    Start;
    Check('model discovery queued', Client.ListModels);
    Deadline := GetTickCount64 + 3000;
    Repeat Client.Pump; Sleep(1); Until (Client.ModelsJson <> '') Or (GetTickCount64 > Deadline);
    Check('model discovery received', Pos('test-model', Client.ModelsJson) > 0);
    Check('turn queued', Client.StartTurn('normal', 'high'));
    WaitState(crsRunning);
    Deadline := GetTickCount64 + 3000;
    Repeat Client.Pump; Sleep(1); Until Client.TakeTool(Tool) Or (GetTickCount64 > Deadline);
    Check('tool correlated', (Tool.CallId = 'call-1') And (Tool.TurnId = 'turn-1'));
    Check('streamed formatting intact', Client.Content = '**text**');
    Check('tool carries its exact preceding text', Tool.ContentBefore = '**text**');
    Check('reasoning sections and final-only summaries retained once', Client.Thinking =
      'Checking **buffers**' + LineEnding + LineEnding + 'Then dependencies' +
      LineEnding + LineEnding + 'Final-only summary');
    Check('tool preserves preceding reasoning', Tool.ThinkingBefore = Client.Thinking);
    Check('wrong tool completion refused', Not Client.CompleteTool('wrong', 'result', True));
    Check('tool result sent', Client.CompleteTool('call-1', 'result', True));
    Check('tool cannot complete twice', Not Client.CompleteTool('call-1', 'result', True));
    WaitState(crsCompleted);
    Start; Client.StartTurn('finalonly'); WaitState(crsCompleted);
    Check('final-only messages retained once with paragraph separation',
      Client.Content = 'Final answer' + LineEnding + LineEnding + 'Second paragraph');
    Start; Client.StartTurn('duplicate'); WaitState(crsFailed);
    Check('duplicate call rejected', Pos('duplicate', Client.LastError) > 0);
    Start; Client.StartTurn('authchange'); WaitState(crsFailed);
    Check('authentication change stops run', Pos('authentication changed', Client.LastError) > 0);
    Start; Client.StartTurn('hang'); WaitState(crsRunning);
    Client.Interrupt; WaitState(crsCompleted);
    Check('cancelled tool cannot execute', Not Client.TakeTool(Tool));
  Finally Client.Free; End;
  TestWorkerBridge;
  TestCancellationDuringTool;
  TestAccount;
  WriteLn('All Codex client tests passed.');
End.
