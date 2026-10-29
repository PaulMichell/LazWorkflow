Program AssistantMCPProtocolTest;

{ MCP message layer checks from Claude Code's request text. No sockets and no claude. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, fpjson, jsonparser, AssistantMCPProtocol;

Const
  { Two entries in the shape TAssistantToolBroker.ToolsJson publishes. }
  BrokerTools = '[{"type":"function","name":"lazarus_project_info","description":"Describe the selected Lazarus project.",' +
    '"inputSchema":{"type":"object","properties":{},"additionalProperties":false}},' +
    '{"type":"function","name":"lazarus_read_buffer","description":"Read current IDE text.","inputSchema":' +
    '{"type":"object","properties":{"path":{"type":"string"}},"required":["path"],"additionalProperties":false}}]';

Type
  TCallOutcome = (coSucceed, coFail, coRaise);

  TToolProbe = Class
  Public
    Outcome: TCallOutcome;
    Calls: Integer;
    LastTool: String;
    LastArguments: String;
    Function Run(Const Tool, Arguments: String; Out ResultText, ErrorText: String): Boolean;
  End;

Var
  Requests: TStringList;
  Probe: TToolProbe;

Function TToolProbe.Run(Const Tool, Arguments: String; Out ResultText, ErrorText: String): Boolean;
Begin
  Inc(Calls);
  LastTool := Tool;
  LastArguments := Arguments;
  ResultText := '';
  ErrorText := '';
  Case Outcome Of
    coSucceed:
      Begin
        ResultText := 'Unit Main;' + LineEnding + 'revision r1';
        Result := True;
      End;
    coFail:
      Begin
        ErrorText := 'No open buffer for Main.pas.';
        Result := False;
      End;
  Else
    Raise EInOutError.Create('editor went away');
  End;
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

Procedure LoadRequests;
Var
  Candidates: Array[0..2] Of String;
  I: Integer;
Begin
  Candidates[0] := ExpandFileName('Tests/Fixtures/Claude/mcp-requests.jsonl');
  Candidates[1] := ExpandFileName('../Tests/Fixtures/Claude/mcp-requests.jsonl');
  Candidates[2] := ExpandFileName(ExtractFilePath(ParamStr(0)) + '../Tests/Fixtures/Claude/mcp-requests.jsonl');
  For I := 0 To High(Candidates) Do
    If FileExists(Candidates[I]) Then
      Begin
        Requests.LoadFromFile(Candidates[I]);
        Exit;
      End;
End;

{ The recorded request for Method. }
Function Recorded(Const Method: String): String;
Var
  Data: TJSONData;
  I: Integer;
Begin
  Result := '';
  For I := 0 To Requests.Count - 1 Do
    Begin
      If Trim(Requests[I]) = '' Then
        Continue;
      Data := GetJSON(Requests[I]);
      Try
        If (Data Is TJSONObject) And (TJSONObject(Data).Get('method', '') = Method) Then
          Begin
            Result := Requests[I];
            Exit;
          End;
      Finally
        Data.Free;
      End;
    End;
End;

{ Answers Request and parses the response, or Nil when there is no body. }
Function Answer(Const Request: String; Out HasBody: Boolean): TJSONObject;
Var
  ResponseText: String;
  Data: TJSONData;
Begin
  Result := Nil;
  HasBody := MCPHandleMessage(Request, BrokerTools, @Probe.Run, ResponseText);
  If Not HasBody Then
    Exit;
  Data := GetJSON(ResponseText);
  If Data Is TJSONObject Then
    Result := TJSONObject(Data)
  Else
    Data.Free;
End;

Function SameId(Response: TJSONObject; Const Request: String): Boolean;
Var
  Data: TJSONData;
Begin
  Data := GetJSON(Request);
  Try
    Result := Assigned(Response.Find('id')) And (Response.Find('id').AsJSON = TJSONObject(Data).Find('id').AsJSON);
  Finally
    Data.Free;
  End;
End;

Function ErrorCode(Response: TJSONObject): Integer;
Begin
  Result := 0;
  If Assigned(Response) And (Response.Find('error') Is TJSONObject) Then
    Result := TJSONObject(Response.Find('error')).Get('code', 0);
End;

Procedure CheckRecordedRequests;
Var
  Request: String;
  Response, Body, Tool: TJSONObject;
  Tools, Content: TJSONArray;
  HasBody: Boolean;
Begin
  Check('fixture has all five requests', (Recorded('server/discover') <> '') And (Recorded('initialize') <> '') And
    (Recorded('notifications/initialized') <> '') And (Recorded('tools/list') <> '') And (Recorded('tools/call') <> ''));

  Request := Recorded('server/discover');
  Response := Answer(Request, HasBody);
  Try
    Check('server/discover gets a body', HasBody And Assigned(Response));
    Check('server/discover is method not found', ErrorCode(Response) = MCPMethodNotFound);
    Check('server/discover keeps its id', SameId(Response, Request));
    Check('server/discover has no result', Not Assigned(Response.Find('result')));
  Finally
    Response.Free;
  End;

  Request := Recorded('initialize');
  Response := Answer(Request, HasBody);
  Try
    Check('initialize gets a body', HasBody And Assigned(Response));
    Check('initialize is JSON-RPC 2.0', Response.Get('jsonrpc', '') = '2.0');
    Check('initialize keeps its id', SameId(Response, Request));
    Body := TJSONObject(Response.Find('result'));
    Check('initialize has a result', Body Is TJSONObject);
    Check('initialize echoes the protocol version', Body.Get('protocolVersion', '') = '2025-06-18');
    Check('initialize offers tools', Body.FindPath('capabilities.tools') Is TJSONObject);
    Check('initialize offers nothing else', TJSONObject(Body.Find('capabilities')).Count = 1);
    Check('initialize names the server lazarus', Body.FindPath('serverInfo.name').AsString = MCPServerName);
    Check('initialize gives a server version', Body.FindPath('serverInfo.version').AsString <> '');
  Finally
    Response.Free;
  End;

  Response := Answer(Recorded('notifications/initialized'), HasBody);
  Check('notifications/initialized gets no body', Not HasBody And Not Assigned(Response));

  Request := Recorded('tools/list');
  Response := Answer(Request, HasBody);
  Try
    Check('tools/list gets a body', HasBody And Assigned(Response));
    Check('tools/list keeps its id', SameId(Response, Request));
    Tools := TJSONArray(Response.FindPath('result.tools'));
    Check('tools/list lists both tools', (Tools Is TJSONArray) And (Tools.Count = 2));
    Tool := Tools.Objects[1];
    Check('tools/list drops the lazarus_ prefix', (Tools.Objects[0].Get('name', '') = 'project_info') And
      (Tool.Get('name', '') = 'read_buffer'));
    Check('tools/list keeps the description', Tool.Get('description', '') = 'Read current IDE text.');
    Check('tools/list keeps the input schema', (Tool.Find('inputSchema') Is TJSONObject) And
      (TJSONObject(Tool.Find('inputSchema')).Get('type', '') = 'object') And
      (Tool.FindPath('inputSchema.required[0]').AsString = 'path'));
    Check('tools/list drops the function wrapper', Not Assigned(Tool.Find('type')) And (Tool.Count = 3));
  Finally
    Response.Free;
  End;

  Request := Recorded('tools/call');
  Probe.Outcome := coSucceed;
  Probe.Calls := 0;
  Response := Answer(Request, HasBody);
  Try
    Check('tools/call gets a body', HasBody And Assigned(Response));
    Check('tools/call keeps its id', SameId(Response, Request));
    Check('tools/call runs the executor once', Probe.Calls = 1);
    Check('tools/call restores the broker name', Probe.LastTool = 'lazarus_read_buffer');
    Check('tools/call passes the arguments object', StringReplace(Probe.LastArguments, ' ', '', [rfReplaceAll]) = '{"path":"Main.pas"}');
    Content := TJSONArray(Response.FindPath('result.content'));
    Check('tools/call returns one content item', (Content Is TJSONArray) And (Content.Count = 1));
    Check('tools/call content is text', Content.Objects[0].Get('type', '') = 'text');
    Check('tools/call returns the tool text', Content.Objects[0].Get('text', '') = 'Unit Main;' + LineEnding + 'revision r1');
    Check('tools/call success is not an error', Response.FindPath('result.isError').AsBoolean = False);
  Finally
    Response.Free;
  End;

  Probe.Outcome := coFail;
  Response := Answer(Request, HasBody);
  Try
    Check('a tool failure is a result, not a JSON-RPC error', HasBody And Assigned(Response.Find('result')) And
      Not Assigned(Response.Find('error')));
    Check('a tool failure sets isError', Response.FindPath('result.isError').AsBoolean);
    Check('a tool failure carries its reason', TJSONArray(Response.FindPath('result.content')).Objects[0].Get('text', '') =
      'No open buffer for Main.pas.');
  Finally
    Response.Free;
  End;

  Probe.Outcome := coRaise;
  Response := Answer(Request, HasBody);
  Try
    Check('a raising executor becomes an internal error', ErrorCode(Response) = MCPInternalError);
    Check('the internal error keeps the id', SameId(Response, Request));
    Check('the internal error says what was raised',
      Pos('editor went away', TJSONObject(Response.Find('error')).Get('message', '')) > 0);
  Finally
    Response.Free;
  End;
  Probe.Outcome := coSucceed;
End;

Procedure CheckVariants;
Var
  Response: TJSONObject;
  HasBody: Boolean;
  ResponseText: String;
Begin
  Response := Answer('{"jsonrpc":"2.0","id":"init-1","method":"initialize","params":{"protocolVersion":"2024-11-05"}}', HasBody);
  Try
    Check('initialize echoes an older protocol version', Response.FindPath('result.protocolVersion').AsString = '2024-11-05');
    Check('a string id stays a string', (Response.Find('id') Is TJSONString) And (Response.Get('id', '') = 'init-1'));
  Finally
    Response.Free;
  End;

  Response := Answer('{"jsonrpc":"2.0","id":7,"method":"initialize"}', HasBody);
  Try
    Check('initialize without params gets the default version',
      Response.FindPath('result.protocolVersion').AsString = MCPDefaultProtocolVersion);
  Finally
    Response.Free;
  End;

  Response := Answer('{"jsonrpc":"2.0","id":8,"method":"ping"}', HasBody);
  Try
    Check('ping gets an empty result', (Response.Find('result') Is TJSONObject) And (TJSONObject(Response.Find('result')).Count = 0));
  Finally
    Response.Free;
  End;

  Response := Answer('{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":3,"reason":"aborted"}}', HasBody);
  Check('other notifications get no body', Not HasBody And Not Assigned(Response));

  Response := Answer('{"jsonrpc":"2.0","id":4,"result":{}}', HasBody);
  Check('a client response gets no body', Not HasBody And Not Assigned(Response));

  Response := Answer('{"jsonrpc":"2.0","id":9,"method":"resources/list"}', HasBody);
  Try
    Check('an unknown method is method not found', ErrorCode(Response) = MCPMethodNotFound);
  Finally
    Response.Free;
  End;

  Probe.Calls := 0;
  Response := Answer('{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"lazarus_read_buffer","arguments":{"path":"Main.pas"}}}',
    HasBody);
  Try
    Check('the broker name is not an MCP name', ErrorCode(Response) = MCPInvalidParams);
    Check('an unknown tool never reaches the executor', Probe.Calls = 0);
  Finally
    Response.Free;
  End;

  Response := Answer('{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"project_info"}}', HasBody);
  Try
    Check('missing arguments become an empty object', Assigned(Response.Find('result')) And (Probe.LastTool = 'lazarus_project_info') And
      (StringReplace(Probe.LastArguments, ' ', '', [rfReplaceAll]) = '{}'));
  Finally
    Response.Free;
  End;

  Response := Answer('{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"read_buffer","arguments":["Main.pas"]}}', HasBody);
  Try
    Check('array arguments are invalid params', ErrorCode(Response) = MCPInvalidParams);
  Finally
    Response.Free;
  End;

  Response := Answer('{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{}}', HasBody);
  Try
    Check('a call without a name is invalid params', ErrorCode(Response) = MCPInvalidParams);
  Finally
    Response.Free;
  End;

  Check('no executor is an internal error, not a crash',
    MCPHandleMessage('{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"read_buffer"}}', BrokerTools, Nil, ResponseText) And
    (Pos(IntToStr(MCPInternalError), ResponseText) > 0));

  Check('an empty catalogue lists no tools',
    MCPHandleMessage(Recorded('tools/list'), '[]', @Probe.Run, ResponseText) And
    (StringReplace(ResponseText, ' ', '', [rfReplaceAll]) = '{"jsonrpc":"2.0","id":2,"result":{"tools":[]}}'));
  Response := Answer(Recorded('tools/list'), HasBody);
  Try
    Check('MCPToolsListResult matches tools/list', MCPToolsListResult(BrokerTools) = Response.Find('result').AsJSON);
  Finally
    Response.Free;
  End;
  Check('MCPToolName keeps an unprefixed name', MCPToolName('read') = 'read');
End;

Procedure CheckMalformed(Const Name, Request: String; Code: Integer);
Var
  Response: TJSONObject;
  HasBody: Boolean;
Begin
  Response := Nil;
  Try
    Try
      Response := Answer(Request, HasBody);
    Except
      On E: Exception Do
        Check(Name + ' does not raise (' + E.Message + ')', False);
    End;
    Check(Name + ' gets an error body', HasBody And Assigned(Response));
    Check(Name + ' is error ' + IntToStr(Code), ErrorCode(Response) = Code);
    Check(Name + ' is JSON-RPC 2.0', Response.Get('jsonrpc', '') = '2.0');
  Finally
    Response.Free;
  End;
End;

Procedure CheckMalformedRequests;
Var
  Response: TJSONObject;
  HasBody: Boolean;
  ResponseText: String;
Begin
  CheckMalformed('truncated JSON', '{"jsonrpc":"2.0","id":1,"method":', MCPParseError);
  CheckMalformed('empty text', '', MCPParseError);
  CheckMalformed('plain text', 'GET / HTTP/1.1', MCPParseError);
  CheckMalformed('a batch', '[{"jsonrpc":"2.0","id":1,"method":"ping"}]', MCPInvalidRequest);
  CheckMalformed('a bare string', '"initialize"', MCPInvalidRequest);
  CheckMalformed('no jsonrpc member', '{"id":1,"method":"ping"}', MCPInvalidRequest);
  CheckMalformed('a numeric method', '{"jsonrpc":"2.0","id":1,"method":5}', MCPInvalidRequest);
  CheckMalformed('an object id', '{"jsonrpc":"2.0","id":{},"method":"ping"}', MCPInvalidRequest);
  CheckMalformed('neither method nor result', '{"jsonrpc":"2.0","id":1}', MCPInvalidRequest);
  CheckMalformed('array params', '{"jsonrpc":"2.0","id":1,"method":"initialize","params":[1]}', MCPInvalidParams);

  Response := Answer('{"jsonrpc":"2.0","id":1,"method":', HasBody);
  Try
    Check('a parse error has a null id', Response.Find('id') Is TJSONNull);
  Finally
    Response.Free;
  End;
  Response := Answer('{"id":"abc","method":"ping"}', HasBody);
  Try
    Check('an invalid request keeps a readable id', Response.Get('id', '') = 'abc');
  Finally
    Response.Free;
  End;
  Check('a bad catalogue is an internal error, not a crash',
    MCPHandleMessage(Recorded('tools/list'), '{not json', @Probe.Run, ResponseText) And
    (Pos(IntToStr(MCPInternalError), ResponseText) > 0));
End;

Begin
  Requests := TStringList.Create;
  Probe := TToolProbe.Create;
  Try
    LoadRequests;
    CheckRecordedRequests;
    CheckVariants;
    CheckMalformedRequests;
    WriteLn('All MCP protocol checks passed.');
  Finally
    Probe.Free;
    Requests.Free;
  End;
End.
