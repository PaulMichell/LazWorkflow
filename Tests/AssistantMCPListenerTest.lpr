Program AssistantMCPListenerTest;

{ MCP loopback listener checks with a scripted HTTP client. No claude and no IDE. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads, BaseUnix,
  {$ENDIF}
  Classes, SysUtils, fpjson, jsonparser, fphttpclient, ssockets, AssistantMCPProtocol, AssistantMCPListener;

Const
  { Two entries in the shape TAssistantToolBroker.ToolsJson publishes. }
  BrokerTools = '[{"type":"function","name":"lazarus_project_info","description":"Describe the selected Lazarus project.",' +
    '"inputSchema":{"type":"object","properties":{},"additionalProperties":false}},' +
    '{"type":"function","name":"lazarus_read_buffer","description":"Read current IDE text.","inputSchema":' +
    '{"type":"object","properties":{"path":{"type":"string"}},"required":["path"],"additionalProperties":false}}]';
  InitializeBody = '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18",' +
    '"capabilities":{},"clientInfo":{"name":"claude-code","version":"2.1"}}}';
  InitializedBody = '{"jsonrpc":"2.0","method":"notifications/initialized"}';
  ListBody = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}';
  ReadBody = '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"read_buffer","arguments":{"path":"Main.pas"}}}';
  { project_info is the deliberately slow tool: the probe holds it until the test lets it go. }
  SlowBody = '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"project_info","arguments":{}}}';
  SlowWaitMs = 10000;

Type
  { Called on the listener's connection threads, so its counters are guarded. }
  TToolProbe = Class
  Public
    Lock: TRTLCriticalSection;
    Calls: Integer;
    SlowEntered: PRTLEvent;
    SlowRelease: PRTLEvent;
    Constructor Create;
    Destructor Destroy; Override;
    Function CallCount: Integer;
    Function Run(Const Tool, Arguments: String; Out ResultText, ErrorText: String): Boolean;
  End;

  TReply = Record
    Status: Integer;
    ContentType: String;
    Body: String;
  End;

  { A second client with its own connection, so one call can be left waiting on another thread. }
  TClientThread = Class(TThread)
  Protected
    Procedure Execute; Override;
  Public
    EndpointURL: String;
    BearerToken: String;
    RequestBody: String;
    Reply: TReply;
    Done: Boolean;
    Constructor Create(Const NewURL, NewToken, NewBody: String);
  End;

Var
  Probe: TToolProbe;
  Listener: TMCPListener;

Constructor TToolProbe.Create;
Begin
  Inherited Create;
  InitCriticalSection(Lock);
  Calls := 0;
  SlowEntered := RTLEventCreate;
  SlowRelease := RTLEventCreate;
End;

Destructor TToolProbe.Destroy;
Begin
  RTLEventDestroy(SlowEntered);
  RTLEventDestroy(SlowRelease);
  DoneCriticalSection(Lock);
  Inherited Destroy;
End;

Function TToolProbe.CallCount: Integer;
Begin
  EnterCriticalSection(Lock);
  Try
    Result := Calls;
  Finally
    LeaveCriticalSection(Lock);
  End;
End;

Function TToolProbe.Run(Const Tool, Arguments: String; Out ResultText, ErrorText: String): Boolean;
Begin
  EnterCriticalSection(Lock);
  Try
    Inc(Calls);
  Finally
    LeaveCriticalSection(Lock);
  End;
  ErrorText := '';
  If Tool = 'lazarus_project_info' Then
    Begin
      RTLEventSetEvent(SlowEntered);
      RTLEventWaitFor(SlowRelease, SlowWaitMs);
      ResultText := 'Project: Slow.lpi';
    End
  Else
    ResultText := 'Unit Main;' + LineEnding + Arguments;
  Result := True;
End;

Function Post(Const EndpointURL, BearerToken, Method, RequestBody: String): TReply;
Var
  Client: TFPHTTPClient;
  Response: TStringStream;
Begin
  Result.Status := 0;
  Result.ContentType := '';
  Result.Body := '';
  Client := TFPHTTPClient.Create(Nil);
  Response := TStringStream.Create('');
  Try
    Client.KeepConnection := False;
    Client.IOTimeout := 15000;
    If BearerToken <> '' Then
      Client.AddHeader('Authorization', 'Bearer ' + BearerToken);
    Client.AddHeader('Accept', 'application/json, text/event-stream');
    If RequestBody <> '' Then
      Begin
        Client.AddHeader('Content-Type', 'application/json');
        Client.RequestBody := TStringStream.Create(RequestBody);
      End;
    Try
      Client.HTTPMethod(Method, EndpointURL, Response, []);
      Result.Status := Client.ResponseStatusCode;
      Result.ContentType := Client.GetHeader(Client.ResponseHeaders, 'Content-Type');
      Result.Body := Response.DataString;
    Except
      On E: Exception Do
        Result.Body := E.ClassName + ': ' + E.Message;
    End;
  Finally
    Client.RequestBody.Free;
    Client.RequestBody := Nil;
    Response.Free;
    Client.Free;
  End;
End;

Constructor TClientThread.Create(Const NewURL, NewToken, NewBody: String);
Begin
  EndpointURL := NewURL;
  BearerToken := NewToken;
  RequestBody := NewBody;
  Done := False;
  FreeOnTerminate := False;
  Inherited Create(False);
End;

Procedure TClientThread.Execute;
Begin
  Reply := Post(EndpointURL, BearerToken, 'POST', RequestBody);
  Done := True;
End;

Procedure Check(Const Name: String; OK: Boolean);
Begin
  If Not OK Then
    Begin
      WriteLn('FAIL ', Name);
      Halt(1);
    End;
  WriteLn('ok   ', Name);
End;

Function ResultOf(Const Body: String): TJSONObject;
Var
  Data: TJSONData;
Begin
  Result := Nil;
  Try
    Data := GetJSON(Body);
  Except
    Exit;
  End;
  If (Data Is TJSONObject) And (TJSONObject(Data).Find('result') Is TJSONObject) Then
    Result := TJSONObject(TJSONObject(Data).Find('result').Clone);
  Data.Free;
End;

Function FirstText(Const Body: String): String;
Var
  CallResult: TJSONObject;
  Content: TJSONData;
Begin
  Result := '';
  CallResult := ResultOf(Body);
  If Not Assigned(CallResult) Then
    Exit;
  Try
    Content := CallResult.Find('content');
    If (Content Is TJSONArray) And (TJSONArray(Content).Count > 0) And (TJSONArray(Content)[0] Is TJSONObject) Then
      Result := TJSONObject(TJSONArray(Content)[0]).Get('text', '');
    If CallResult.Get('isError', True) Then
      Result := 'isError: ' + Result;
  Finally
    CallResult.Free;
  End;
End;

Function ReadText(Const FileName: String): String;
Var
  Lines: TStringList;
Begin
  Lines := TStringList.Create;
  Try
    Lines.LoadFromFile(FileName);
    Result := Trim(Lines.Text);
  Finally
    Lines.Free;
  End;
End;

Function CanConnect(PortNumber: Word): Boolean;
Var
  Socket: TInetSocket;
Begin
  Result := False;
  Try
    Socket := TInetSocket.Create(MCPListenHost, PortNumber);
    Socket.Free;
    Result := True;
  Except
    On E: Exception Do
      Result := False;
  End;
End;

Procedure CheckConfigFile;
Var
  Data, Server: TJSONData;
  {$IFDEF UNIX}
  Info: Stat;
  {$ENDIF}
Begin
  Check('the config file exists while the listener runs', (Listener.ConfigFileName <> '') And FileExists(Listener.ConfigFileName));
  Check('the config file is in the temporary directory',
    Pos(IncludeTrailingPathDelimiter(GetTempDir(False)), Listener.ConfigFileName) = 1);
  {$IFDEF UNIX}
  Check('the config file can be read only by its owner',
    (FpStat(Listener.ConfigFileName, Info) = 0) And ((Info.st_mode And &777) = &600));
  {$ENDIF}
  Check('the config file holds MCPConfigJSON for this run',
    ReadText(Listener.ConfigFileName) = MCPConfigJSON(Listener.URL, Listener.Token));
  Data := GetJSON(ReadText(Listener.ConfigFileName));
  Try
    Server := Data.FindPath('mcpServers.lazarus');
    Check('the config names the http server lazarus', Assigned(Server) And (Server.FindPath('type').AsString = 'http'));
    Check('the config url is the loopback endpoint',
      Server.FindPath('url').AsString = 'http://127.0.0.1:' + IntToStr(Listener.Port) + '/mcp');
    Check('the config sends the bearer token', Server.FindPath('headers.Authorization').AsString = 'Bearer ' + Listener.Token);
  Finally
    Data.Free;
  End;
End;

Procedure CheckSession;
Var
  Reply: TReply;
  ListResult: TJSONObject;
  Calls: Integer;
Begin
  Reply := Post(Listener.URL, Listener.Token, 'POST', InitializeBody);
  Check('initialize gets 200', Reply.Status = 200);
  Check('initialize is answered as JSON', Pos('application/json', Reply.ContentType) = 1);
  ListResult := ResultOf(Reply.Body);
  Check('initialize returns the server info', Assigned(ListResult) And (ListResult.FindPath('serverInfo.name').AsString = 'lazarus'));
  ListResult.Free;

  Reply := Post(Listener.URL, Listener.Token, 'POST', InitializedBody);
  Check('notifications/initialized gets 202 with no body', (Reply.Status = 202) And (Reply.Body = ''));

  Reply := Post(Listener.URL, Listener.Token, 'POST', ListBody);
  ListResult := ResultOf(Reply.Body);
  Check('tools/list gets 200 with a result', (Reply.Status = 200) And Assigned(ListResult));
  Check('tools/list offers read_buffer', Pos('"name" : "read_buffer"', ListResult.AsJSON) > 0);
  ListResult.Free;

  Calls := Probe.CallCount;
  Reply := Post(Listener.URL, Listener.Token, 'POST', ReadBody);
  Check('tools/call gets 200', Reply.Status = 200);
  Check('tools/call reaches the executor with its arguments', FirstText(Reply.Body) = 'Unit Main;' + LineEnding + '{ "path" : "Main.pas" }');
  Check('tools/call runs the tool once', Probe.CallCount = Calls + 1);

  Reply := Post(Listener.URL, Listener.Token, 'POST', '{"jsonrpc":"2.0","id":9,');
  Check('a malformed body gets a JSON-RPC parse error', (Reply.Status = 200) And (Pos('-32700', Reply.Body) > 0));
End;

Procedure CheckRefusals;
Var
  Reply: TReply;
  Calls: Integer;
  WrongToken: String;
Begin
  Calls := Probe.CallCount;
  Reply := Post(Listener.URL, '', 'POST', ReadBody);
  Check('a request without a token gets 401', Reply.Status = 401);
  WrongToken := Listener.Token;
  If WrongToken[1] = 'a' Then
    WrongToken[1] := 'b'
  Else
    WrongToken[1] := 'a';
  Reply := Post(Listener.URL, WrongToken, 'POST', ReadBody);
  Check('a request with a wrong token gets 401', Reply.Status = 401);
  Reply := Post(Listener.URL, Copy(Listener.Token, 1, 10), 'POST', ReadBody);
  Check('a request with part of the token gets 401', Reply.Status = 401);
  Reply := Post('http://127.0.0.1:' + IntToStr(Listener.Port) + '/other', '', 'POST', ReadBody);
  Check('a wrong path without the token gets 401, not 404', Reply.Status = 401);
  Check('a refused request never reaches the executor', Probe.CallCount = Calls);
  Reply := Post('http://127.0.0.1:' + IntToStr(Listener.Port) + '/other', Listener.Token, 'POST', ReadBody);
  Check('a wrong path with the token gets 404', Reply.Status = 404);
  Reply := Post(Listener.URL, Listener.Token, 'GET', '');
  Check('GET for an event stream gets 405', Reply.Status = 405);
End;

Procedure CheckSlowCall;
Var
  Slow: TClientThread;
  Reply: TReply;
  Started: QWord;
  Entered: Boolean;
Begin
  RTLEventResetEvent(Probe.SlowEntered);
  RTLEventResetEvent(Probe.SlowRelease);
  Slow := TClientThread.Create(Listener.URL, Listener.Token, SlowBody);
  Try
    Started := GetTickCount64;
    RTLEventWaitFor(Probe.SlowEntered, SlowWaitMs);
    Entered := GetTickCount64 - Started < SlowWaitMs;
    Check('the slow call reaches the executor', Entered);
    Started := GetTickCount64;
    Reply := Post(Listener.URL, Listener.Token, 'POST', InitializeBody);
    Check('a second client initializes while the slow call is pending', Reply.Status = 200);
    Reply := Post(Listener.URL, Listener.Token, 'POST', ListBody);
    Check('a second client lists tools while the slow call is pending', (Reply.Status = 200) And (Pos('read_buffer', Reply.Body) > 0));
    Reply := Post(Listener.URL, Listener.Token, 'POST', ReadBody);
    Check('a second client calls a tool while the slow call is pending', Pos('Unit Main;', FirstText(Reply.Body)) = 1);
    Check('the second client was not held up', GetTickCount64 - Started < 3000);
    Check('the slow call is still pending', Not Slow.Done);
    RTLEventSetEvent(Probe.SlowRelease);
    Slow.WaitFor;
    Check('the slow call answers once released', (Slow.Reply.Status = 200) And (FirstText(Slow.Reply.Body) = 'Project: Slow.lpi'));
  Finally
    RTLEventSetEvent(Probe.SlowRelease);
    Slow.Free;
  End;
End;

Procedure CheckStop;
Var
  Idle: TInetSocket;
  OldToken, OldConfig, Error: String;
  OldPort: Word;
  Started: QWord;
  Reply: TReply;
Begin
  OldToken := Listener.Token;
  OldPort := Listener.Port;
  OldConfig := Listener.ConfigFileName;
  { A client that connects and sends nothing must not keep Stop waiting. }
  Idle := TInetSocket.Create(MCPListenHost, OldPort);
  Try
    Sleep(100);
    Started := GetTickCount64;
    Listener.Stop;
    Check('Stop does not wait for an idle connection', GetTickCount64 - Started < 3000);
  Finally
    Idle.Free;
  End;
  Check('Stop deletes the config file', Not FileExists(OldConfig));
  Check('Stop clears the config file name and token', (Listener.ConfigFileName = '') And (Listener.Token = '') And Not Listener.Running);
  Check('nothing listens on the port after Stop', Not CanConnect(OldPort));
  Listener.Stop;
  Check('a second Stop is harmless', Not Listener.Running);

  Check('the next run starts', Listener.Start(Error));
  Check('the next run has a new token', (Listener.Token <> '') And (Listener.Token <> OldToken));
  Check('the next run has a new config file', (Listener.ConfigFileName <> OldConfig) And FileExists(Listener.ConfigFileName));
  Reply := Post(Listener.URL, OldToken, 'POST', InitializeBody);
  Check('the last run''s token is refused', Reply.Status = 401);
  Reply := Post(Listener.URL, Listener.Token, 'POST', InitializeBody);
  Check('the new token is accepted', Reply.Status = 200);
  OldConfig := Listener.ConfigFileName;
  FreeAndNil(Listener);
  Check('freeing the listener deletes the config file', Not FileExists(OldConfig));
End;

Var
  Error: String;

Begin
  Probe := TToolProbe.Create;
  Listener := TMCPListener.Create(BrokerTools, @Probe.Run);
  Try
    Check('the listener starts', Listener.Start(Error) And Listener.Running);
    Check('the listener has a kernel-chosen port', Listener.Port <> 0);
    Check('the token is 64 hex characters', (Length(Listener.Token) = 64) And (LowerCase(Listener.Token) = Listener.Token));
    Check('the url is the loopback endpoint', Listener.URL = 'http://127.0.0.1:' + IntToStr(Listener.Port) + '/mcp');
    CheckConfigFile;
    CheckSession;
    CheckRefusals;
    CheckSlowCall;
    CheckStop;
  Finally
    Listener.Free;
    Probe.Free;
  End;
  WriteLn('AssistantMCPListenerTest passed');
End.
