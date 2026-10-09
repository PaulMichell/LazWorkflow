Program AssistantCodexClientTest;
{$mode objfpc}{$H+}
Uses cthreads, Classes, SysUtils, fpjson, jsonparser,
  {$IFDEF UNIX}BaseUnix, {$ENDIF}
  AssistantCodexClient, AssistantCodexHandshake, AssistantCodexRun, AssistantToolBroker,
  AssistantCodexAccount, AssistantCodexProfile, AssistantCodexQualification;
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
Procedure TestDynamicTools;
Var
  Catalogue, Dynamic, Params: String;
  Data: TJSONData;
  Tool: TJSONObject;
Begin
  Catalogue := '[{"type":"function","function":{"name":"write_markdown","description":"Write the plan.",' +
    '"parameters":{"type":"object","properties":{"content":{"type":"string"}},"required":["content"]}}},' +
    '{"type":"function","function":{"name":"open_markdown","description":"Open the viewer.","parameters":{"type":"object"}}}]';
  Dynamic := CodexDynamicToolsFromCatalogue(Catalogue);
  Data := GetJSON(Dynamic);
  Try
    Check('converted two tools', TJSONArray(Data).Count = 2);
    Tool := TJSONObject(TJSONArray(Data)[0]);
    Check('name lifted', Tool.Get('name', '') = 'write_markdown');
    Check('description kept', Tool.Get('description', '') = 'Write the plan.');
    Check('parameters become inputSchema', Tool.Find('inputSchema').FindPath('properties.content.type').AsString = 'string');
    Check('no nested function wrapper', Tool.Find('function') = Nil);
  Finally
    Data.Free;
  End;
  Check('empty catalogue is an empty array', CodexDynamicToolsFromCatalogue('') = '[]');
  Check('empty array stays empty', CodexDynamicToolsFromCatalogue('[]') = '[]');
  Params := CodexThreadStartParams('/tmp', 'model', Dynamic, 'Use write_markdown.');
  Check('thread/start embeds write_markdown', Pos('"name":"write_markdown"', Params) > 0);
  Check('thread/start embeds open_markdown', Pos('"name":"open_markdown"', Params) > 0);
  Check('thread/start uses the passed instructions', Pos('Use write_markdown.', Params) > 0);
  Check('thread/start has no lazarus tool essay', Pos('use the lazarus tools', LowerCase(Params)) = 0);
  Check('chat thread/start has an empty tool array', Pos('"dynamicTools":[]', CodexThreadStartParams('/tmp', 'model', '[]', 'chat')) > 0);
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
      Run.ServiceTool;
      Snapshot := Run.Snapshot;
      Sleep(1);
    Until Snapshot.Done Or (GetTickCount64 >= Deadline);
    Check('worker run completes', Snapshot.Done And (Snapshot.State = crsCompleted));
    Check('first run creates its managed profile', FileExists(Profile + '/config.toml'));
    Check('worker does not dispatch broker tools', Workspace.Reads = 0);
    Check('worker streams answer snapshot', Snapshot.Content = '**text**');
    Check('worker publishes reasoning for the UI', Pos('Final-only summary', Snapshot.Thinking) > 0);
    Run.Free; Run := Nil;
    RunId := Broker.BeginRun(awsReadOnly);
    Run := TAssistantCodexRun.Create(ParamStr(0), GetTempDir, 'test-model',
      'normal', Broker.ToolsJson, RunId, 3000, '', 'high');
    Run.Start; Run.Cancel; Broker.Cancel;
    Deadline := GetTickCount64 + 7000;
    Repeat Run.ServiceTool; Snapshot := Run.Snapshot; Sleep(1);
    Until Snapshot.Done Or (GetTickCount64 >= Deadline);
    Check('cancelled worker finishes', Snapshot.Done);
    Check('cancelled worker executes no IDE tools', Workspace.Reads = 0);
  Finally
    Run.Free; Broker.Free; Workspace.Free;
    DeleteFile(Profile + '/config.toml');
    RemoveDir(Profile);
  End;
End;
Procedure TestCancellationDuringTool;
Var Workspace: TMemoryWorkspace; Broker: TAssistantToolBroker; Run: TAssistantCodexRun;
  Snapshot: TCodexRunSnapshot; Deadline: QWord;
Begin
  Workspace := TMemoryWorkspace.Create; Broker := TAssistantToolBroker.Create(Workspace);
  Broker.BeginRun(awsReadOnly);
  Run := TAssistantCodexRun.Create(ParamStr(0), GetTempDir, 'test-model',
    'normal', Broker.ToolsJson, Broker.RunId, 3000, '', 'high');
  Try
    Run.Start; Deadline := GetTickCount64 + 5000;
    Repeat
      Run.ServiceTool;
      Snapshot := Run.Snapshot;
      Sleep(1);
    Until Snapshot.Done Or (GetTickCount64 >= Deadline);
    Check('rejected broker tool does not touch the workspace', Workspace.Reads = 0);
    Check('rejected tool run still finishes', Snapshot.Done);
  Finally Run.Free; Broker.Free; Workspace.Free; End;
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
Function CodexFixturePath: String;
Var Dir, Probe: String;
Begin
  Dir := IncludeTrailingPathDelimiter(GetCurrentDir);
  Probe := Dir + 'Source/Tests/Fixtures/CodexTurnStartParams.json';
  If FileExists(Probe) Then Exit(Probe);
  Dir := ExtractFilePath(ParamStr(0));
  While (Dir <> '') And (ExcludeTrailingPathDelimiter(Dir) <> Dir) Do
    Begin
      Probe := IncludeTrailingPathDelimiter(Dir) + 'Source/Tests/Fixtures/CodexTurnStartParams.json';
      If FileExists(Probe) Then Exit(Probe);
      Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    End;
  Result := '';
End;
Procedure AssertTextOnly(Const Name, Body: String);
Var Data: TJSONData; Input: TJSONData;
Begin
  Check(Name + ' has no local_image', (Pos('local_image', Body) = 0) And (Pos('localImage', Body) = 0));
  Check(Name + ' has no image item', Pos('"type":"image"', Body) = 0);
  Data := GetJSON(Body);
  Try
    Check(Name + ' is an object', Data Is TJSONObject);
    Input := TJSONObject(Data).Find('input');
    Check(Name + ' has one text item', (Input Is TJSONArray) And (TJSONArray(Input).Count = 1) And
      (TJSONObject(TJSONArray(Input).Items[0]).Get('type', '') = 'text'));
  Finally Data.Free; End;
End;
Procedure TestTurnStartBody;
Var Lines: TStringList; Data: TJSONData; Obj: TJSONObject; Built: String; SteerClient: TAssistantCodexClient;
Begin
  Check('codex image support stays off', Not CodexImagesSupported);
  Lines := TStringList.Create;
  Data := Nil;
  Try
    Check('turn/start fixture found', CodexFixturePath <> '');
    Lines.LoadFromFile(CodexFixturePath);
    Data := GetJSON(Lines.Text);
    Check('turn/start fixture is an object', Data Is TJSONObject);
    Obj := TJSONObject(Data);
    Built := CodexTurnStartParams(Obj.Get('threadId', ''), Obj.Get('prompt', ''), Obj.Get('effort', ''));
    Check('turn/start body matches fixture', Built = Obj.Get('withEffort', ''));
    AssertTextOnly('with effort', Built);
    Built := CodexTurnStartParams(Obj.Get('threadId', ''), Obj.Get('prompt', ''), '');
    Check('turn/start without effort matches fixture', Built = Obj.Get('withoutEffort', ''));
    AssertTextOnly('without effort', Built);
    Built := CodexTurnStartParams('thread-1', 'data:image/png;base64,AAAA', '');
    AssertTextOnly('data uri stays text', Built);
    Built := CodexTurnSteerParams('thread-1', 'turn-9', 'look at this');
    AssertTextOnly('turn/steer', Built);
    Check('turn/steer names the turn', Pos('"expectedTurnId":"turn-9"', Built) > 0);
    SteerClient := TAssistantCodexClient.Create(500);
    Try
      Check('steer refuses image refs', Not SteerClient.Steer('look', '[{"id":"img1"}]'));
      Check('codex image item is unsupported', Not CodexImagesSupported And
        (Pos('"type":"image"', CodexTurnSteerParams('thread-1', 'turn-9', 'look')) = 0) And
        (Pos('"type":"image"', CodexTurnStartParams('thread-1', 'look', '')) = 0));
    Finally SteerClient.Free; End;
  Finally Data.Free; Lines.Free; End;
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
Procedure WriteSchemaFile(Const Directory, Relative: String; Const Fields: Array Of String; Const Omit: String);
Var
  Lines: TStringList;
  I: Integer;
  Path, Body: String;
  First: Boolean;
Begin
  Body := '{"properties":{';
  First := True;
  For I := Low(Fields) To High(Fields) Do
    Begin
      If Fields[I] = Omit Then Continue;
      If Not First Then Body := Body + ',';
      First := False;
      Body := Body + '"' + Fields[I] + '":{"type":"string"}';
    End;
  Body := Body + '}}';
  Lines := TStringList.Create;
  Try
    Lines.Text := Body;
    Path := IncludeTrailingPathDelimiter(Directory) + Relative;
    If Not ForceDirectories(ExtractFilePath(Path)) Then Halt(1);
    Lines.SaveToFile(Path);
  Finally
    Lines.Free;
  End;
End;
Procedure WriteSchemaFixture;
Var
  Directory, Omit: String;
  I: Integer;
Begin
  Directory := '';
  For I := 1 To ParamCount - 1 Do
    If ParamStr(I) = '--out' Then Directory := ParamStr(I + 1);
  If Directory = '' Then Halt(1);
  If GetEnvironmentVariable('LAZ_TEST_CODEX_SCHEMA') = 'fail' Then Halt(1);
  Omit := '';
  If GetEnvironmentVariable('LAZ_TEST_CODEX_SCHEMA') = 'missing' Then Omit := 'authUrl';
  WriteSchemaFile(Directory, 'v2/LoginAccountParams.json', ['type'], Omit);
  WriteSchemaFile(Directory, 'v2/LoginAccountResponse.json', ['type', 'loginId', 'authUrl'], Omit);
  WriteSchemaFile(Directory, 'v2/GetAccountResponse.json', ['account', 'requiresOpenaiAuth'], Omit);
  WriteSchemaFile(Directory, 'v2/ThreadStartParams.json', ['dynamicTools', 'modelProvider', 'permissions', 'approvalPolicy'], Omit);
  WriteSchemaFile(Directory, 'v2/ThreadStartResponse.json', ['modelProvider', 'sandbox', 'approvalPolicy', 'thread'], Omit);
  WriteSchemaFile(Directory, 'v2/TurnStartParams.json', ['threadId', 'input', 'permissions', 'summary'], Omit);
  WriteSchemaFile(Directory, 'v2/TurnInterruptParams.json', ['threadId', 'turnId'], Omit);
  WriteSchemaFile(Directory, 'v2/TurnSteerParams.json', ['threadId', 'expectedTurnId', 'input'], Omit);
  WriteSchemaFile(Directory, 'DynamicToolCallParams.json', ['threadId', 'turnId', 'callId', 'tool', 'arguments'], Omit);
  WriteSchemaFile(Directory, 'DynamicToolCallResponse.json', ['contentItems', 'success'], Omit);
  WriteSchemaFile(Directory, 'v2/AgentMessageDeltaNotification.json', ['threadId', 'turnId', 'itemId', 'delta'], Omit);
End;
{$IFDEF UNIX}
Function PaddedCodexRuntime: String;
Const
  PadBytes = 268435457;
Var
  Source, Dest: TFileStream;
  Buffer: Array[0..65535] Of Byte;
  Count: Integer;
  Marker: Byte;
Begin
  Result := '';
  Try
    Result := IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(ParamStr(0)))) + 'laz-codex-large-' + IntToStr(GetProcessID);
    Source := TFileStream.Create(ParamStr(0), fmOpenRead Or fmShareDenyNone);
    Try
      Dest := TFileStream.Create(Result, fmCreate);
      Try
        Repeat
          Count := Source.Read(Buffer, SizeOf(Buffer));
          If Count > 0 Then Dest.WriteBuffer(Buffer, Count);
        Until Count < SizeOf(Buffer);
        If Dest.Size < PadBytes Then
          Begin
            Dest.Seek(PadBytes - 1, soBeginning);
            Marker := 0;
            Dest.WriteBuffer(Marker, 1);
          End;
      Finally
        Dest.Free;
      End;
    Finally
      Source.Free;
    End;
    If fpChmod(Result, &755) <> 0 Then
      Begin
        DeleteFile(Result);
        Result := '';
      End;
  Except
    If Result <> '' Then DeleteFile(Result);
    Result := '';
  End;
End;
Procedure CheckLargeRuntime;
Var
  Runtime: String;
  Connected: Boolean;
Begin
  Runtime := PaddedCodexRuntime;
  Try
    If Runtime = '' Then
      Check('release larger than 256 MiB connects: could not prepare runtime', False)
    Else
      Begin
        Connected := Client.Connect(Runtime, GetTempDir, VersionEnv);
        Check('release larger than 256 MiB connects: ' + Client.LastError, Connected);
        Client.Disconnect;
      End;
  Finally
    If Runtime <> '' Then DeleteFile(Runtime);
  End;
End;
{$ENDIF}
Begin
  If ParamStr(1) = '--version' Then
    Begin
      If GetEnvironmentVariable('LAZ_TEST_CODEX_VERSION') <> '' Then WriteLn(GetEnvironmentVariable('LAZ_TEST_CODEX_VERSION'))
      Else WriteLn('codex-cli 0.160.0');
      Halt;
    End;
  If (ParamCount > 0) And (ParamStr(1) = 'app-server') Then
    Begin
      WriteSchemaFixture;
      Halt;
    End;
  If ParamCount > 0 Then Begin FakeRuntime; Halt; End;
  TestDynamicTools;
  TestTurnStartBody;
  Client := TAssistantCodexClient.Create(500);
  Try
    VersionEnv := TStringList.Create;
    Try
      ClearCodexQualificationCache;
      Check('release version shape accepted', CodexVersionIsRelease('codex-cli 0.160.0') And
        CodexVersionIsRelease('codex-cli 0.153.99'));
      Check('alpha and short versions rejected', (Not CodexVersionIsRelease('codex-cli 0.154.0-alpha.6.1')) And
        (Not CodexVersionIsRelease('codex-cli 0.160')) And (Not CodexVersionIsRelease('codex-cli 0.160.0 ')));
      CodexProfileEnvironment(GetTempDir, VersionEnv);
      VersionEnv.Values['LAZ_TEST_CODEX_VERSION'] := 'codex-cli 0.154.0-alpha.6.1';
      Check('alpha runtime remains rejected', Not Client.Connect(ParamStr(0), GetTempDir, VersionEnv)
        And (Pos('not a release build', Client.LastError) > 0) And (Pos('0.154.0-alpha.6.1', Client.LastError) > 0));
      ClearCodexQualificationCache;
      VersionEnv.Values['LAZ_TEST_CODEX_SCHEMA'] := 'missing';
      VersionEnv.Values['LAZ_TEST_CODEX_VERSION'] := 'codex-cli 0.160.0';
      Check('schema missing authUrl rejected', Not Client.Connect(ParamStr(0), GetTempDir, VersionEnv)
        And (Pos('authUrl', Client.LastError) > 0) And (Pos('LoginAccountResponse.json', Client.LastError) > 0));
      ClearCodexQualificationCache;
      VersionEnv.Values['LAZ_TEST_CODEX_SCHEMA'] := '';
      VersionEnv.Values['LAZ_TEST_CODEX_VERSION'] := 'codex-cli 0.160.0';
      Check('current release connects', Client.Connect(ParamStr(0), GetTempDir, VersionEnv));
      Client.Disconnect;
      {$IFDEF UNIX}
      ClearCodexQualificationCache;
      CheckLargeRuntime;
      {$ENDIF}
      VersionEnv.Values['LAZ_TEST_CODEX_VERSION'] := 'codex-cli 0.153.4';
      Check('older release connects', Client.Connect(ParamStr(0), GetTempDir, VersionEnv));
      Client.Disconnect;
      VersionEnv.Values['LAZ_TEST_CODEX_VERSION'] := 'codex-cli 0.153.99';
      Check('unlisted release connects when schema matches', Client.Connect(ParamStr(0), GetTempDir, VersionEnv));
      Client.Disconnect;
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
