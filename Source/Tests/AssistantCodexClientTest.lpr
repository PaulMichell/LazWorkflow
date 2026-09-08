Program AssistantCodexClientTest;
{$mode objfpc}{$H+}
Uses cthreads, Classes, SysUtils, fpjson, jsonparser,
  AssistantCodexClient, AssistantCodexHandshake, AssistantCodexRun, AssistantToolBroker;
Type
  TMemoryWorkspace = Class(TAssistantWorkspaceAdapter)
  Public
    Reads: Integer;
    Function Identity: String; Override;
    Function ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean; Override;
    Function ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean; Override;
    Function SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean; Override;
    Function Describe: String; Override;
  End;
Function TMemoryWorkspace.Identity: String;
Begin Result := 'project-test'; End;
Function TMemoryWorkspace.ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean;
Begin Inc(Reads); CanonicalPath := Path; Text := 'unsaved IDE contents'; ErrorText := ''; Result := True; End;
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
Begin
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
            If (Params.Get('sandbox', '') <> 'read-only') Or
              (Params.Get('modelProvider', '') <> 'openai') Then Halt(2);
            Send('{"id":' + Id + ',"result":{"modelProvider":"openai","approvalPolicy":"untrusted","sandbox":{"type":"readOnly"},"thread":{"id":"thread-1"}}}');
          End
        Else If Method = 'model/list' Then Send('{"id":' + Id + ',"result":{"data":[{"id":"test-model"}],"nextCursor":null}}')
        Else If Method = 'turn/start' Then
          Begin
            Params := TJSONObject(Obj.Find('params'));
            Prompt := Params.FindPath('input[0].text').AsString;
            Send('{"id":' + Id + ',"result":{"turn":{"id":"turn-1","status":"inProgress"}}}');
            If Prompt = 'authchange' Then
              Begin Send('{"method":"account/updated","params":{"authMode":"apikey"}}'); Continue; End;
            If Prompt = 'hang' Then Continue;
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
  RunId: String; Snapshot: TCodexRunSnapshot; Deadline: QWord;
Begin
  Workspace := TMemoryWorkspace.Create;
  Broker := TAssistantToolBroker.Create(Workspace);
  Run := Nil;
  Try
    RunId := Broker.BeginRun(False);
    Run := TAssistantCodexRun.Create(ParamStr(0), GetTempDir, 'test-model',
      'normal', Broker.ToolsJson, RunId, 3000);
    Run.Start;
    Deadline := GetTickCount64 + 5000;
    Repeat
      Run.ServiceTool(Broker);
      Snapshot := Run.Snapshot;
      Sleep(1);
    Until Snapshot.Done Or (GetTickCount64 >= Deadline);
    Check('worker run completes', Snapshot.Done And (Snapshot.State = crsCompleted));
    Check('worker dispatches one IDE read through broker', Workspace.Reads = 1);
    Check('worker streams answer snapshot', Snapshot.Content = '**text**');
    Run.Free; Run := Nil;
    RunId := Broker.BeginRun(False);
    Run := TAssistantCodexRun.Create(ParamStr(0), GetTempDir, 'test-model',
      'normal', Broker.ToolsJson, RunId, 3000);
    Run.Start; Run.Cancel; Broker.Cancel;
    Deadline := GetTickCount64 + 7000;
    Repeat Run.ServiceTool(Broker); Snapshot := Run.Snapshot; Sleep(1);
    Until Snapshot.Done Or (GetTickCount64 >= Deadline);
    Check('cancelled worker finishes', Snapshot.Done);
    Check('cancelled worker executes no IDE tools', Workspace.Reads = 1);
  Finally
    Run.Free; Broker.Free; Workspace.Free;
  End;
End;
Var Client: TAssistantCodexClient; Tool: TCodexToolRequest; Deadline: QWord;
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
  Check('thread queued', Client.StartThread(GetTempDir, 'test-model', '[]'));
  WaitState(crsReady);
End;
Begin
  If ParamStr(1) = '--version' Then Begin WriteLn(QualifiedCodexVersion); Halt; End;
  If ParamCount > 0 Then Begin FakeRuntime; Halt; End;
  Client := TAssistantCodexClient.Create(500);
  Try
    Check('unauthenticated turn rejected', Not Client.StartTurn('test'));
    Start;
    Check('model discovery queued', Client.ListModels);
    Deadline := GetTickCount64 + 3000;
    Repeat Client.Pump; Sleep(1); Until (Client.ModelsJson <> '') Or (GetTickCount64 > Deadline);
    Check('model discovery received', Pos('test-model', Client.ModelsJson) > 0);
    Check('turn queued', Client.StartTurn('normal'));
    WaitState(crsRunning);
    Deadline := GetTickCount64 + 3000;
    Repeat Client.Pump; Sleep(1); Until Client.TakeTool(Tool) Or (GetTickCount64 > Deadline);
    Check('tool correlated', (Tool.CallId = 'call-1') And (Tool.TurnId = 'turn-1'));
    Check('streamed formatting intact', Client.Content = '**text**');
    Check('wrong tool completion refused', Not Client.CompleteTool('wrong', 'result', True));
    Check('tool result sent', Client.CompleteTool('call-1', 'result', True));
    Check('tool cannot complete twice', Not Client.CompleteTool('call-1', 'result', True));
    WaitState(crsCompleted);
    Start; Client.StartTurn('duplicate'); WaitState(crsFailed);
    Check('duplicate call rejected', Pos('duplicate', Client.LastError) > 0);
    Start; Client.StartTurn('authchange'); WaitState(crsFailed);
    Check('authentication change stops run', Pos('authentication changed', Client.LastError) > 0);
    Start; Client.StartTurn('hang'); WaitState(crsRunning);
    Client.Interrupt; WaitState(crsCompleted);
    Check('cancelled tool cannot execute', Not Client.TakeTool(Tool));
  Finally Client.Free; End;
  TestWorkerBridge;
  WriteLn('All Codex client tests passed.');
End.
