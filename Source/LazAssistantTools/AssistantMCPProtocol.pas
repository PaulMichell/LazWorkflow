Unit AssistantMCPProtocol;

{ MCP requests from Claude Code, answered from the tool broker's catalogue (c) 2026 Michell Computing.

  Pure text and JSON: no sockets and no IDE units. The listener hands each request body here and sends back what
  comes out; a tools/call is passed to the caller's executor, which runs it wherever the broker lives.

  Claude Code names MCP tools mcp__<server>__<tool>. The server is called lazarus and the broker's lazarus_ prefix
  is dropped from the listing, so lazarus_read_buffer reaches Claude as mcp__lazarus__read_buffer. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Type
  { Runs one broker tool with its arguments as a JSON object. False is a tool failure, explained in ErrorText. }
  TMCPToolExecutor = Function(Const Tool, Arguments: String; Out ResultText, ErrorText: String): Boolean Of Object;

Const
  MCPServerName = 'lazarus';
  MCPServerVersion = '1.0';
  { Used when initialize names no version. }
  MCPDefaultProtocolVersion = '2025-06-18';
  MCPBrokerToolPrefix = 'lazarus_';

  MCPParseError = -32700;
  MCPInvalidRequest = -32600;
  MCPMethodNotFound = -32601;
  MCPInvalidParams = -32602;
  MCPInternalError = -32603;

/// The MCP name for a broker tool: the broker prefix is dropped.
Function MCPToolName(Const BrokerName: String): String;
/// The broker's tools as an MCP tools/list result, from TAssistantToolBroker.ToolsJson.
Function MCPToolsListResult(Const ToolsJSON: String): String;
/// Answers one JSON-RPC message. False when no response body is due (a notification or a client response):
/// the listener answers HTTP 202. Never raises; malformed text gets a JSON-RPC error.
Function MCPHandleMessage(Const RequestText, ToolsJSON: String; Executor: TMCPToolExecutor; Out ResponseText: String): Boolean;

Implementation

Uses
  SysUtils, fpjson, jsonparser;

Function MCPToolName(Const BrokerName: String): String;
Begin
  If Copy(BrokerName, 1, Length(MCPBrokerToolPrefix)) = MCPBrokerToolPrefix Then
    Result := Copy(BrokerName, Length(MCPBrokerToolPrefix) + 1, MaxInt)
  Else
    Result := BrokerName;
End;

Function ParseJSON(Const Text: String): TJSONData;
Begin
  Try
    Result := GetJSON(Text);
  Except
    Result := Nil;
  End;
End;

{ The MCP tool objects, or Nil when the catalogue is not a JSON array. }
Function MCPTools(Const ToolsJSON: String): TJSONArray;
Var
  Data, Schema: TJSONData;
  Item, Tool: TJSONObject;
  I: Integer;
Begin
  Result := Nil;
  Data := ParseJSON(ToolsJSON);
  Try
    If Not (Data Is TJSONArray) Then
      Exit;
    Result := TJSONArray.Create;
    For I := 0 To TJSONArray(Data).Count - 1 Do
      Begin
        If Not (TJSONArray(Data)[I] Is TJSONObject) Then
          Continue;
        Item := TJSONObject(TJSONArray(Data)[I]);
        If Item.Get('name', '') = '' Then
          Continue;
        Tool := TJSONObject.Create;
        Tool.Add('name', MCPToolName(Item.Get('name', '')));
        Tool.Add('description', Item.Get('description', ''));
        Schema := Item.Find('inputSchema');
        If Schema Is TJSONObject Then
          Tool.Add('inputSchema', Schema.Clone)
        Else
          Tool.Add('inputSchema', TJSONObject.Create(['type', 'object', 'properties', TJSONObject.Create]));
        Result.Add(Tool);
      End;
  Finally
    Data.Free;
  End;
End;

{ The broker name of a listed tool, or '' when Claude names a tool the catalogue does not offer. }
Function BrokerToolName(Const ToolsJSON, MCPName: String): String;
Var
  Data: TJSONData;
  Name: String;
  I: Integer;
Begin
  Result := '';
  If MCPName = '' Then
    Exit;
  Data := ParseJSON(ToolsJSON);
  Try
    If Not (Data Is TJSONArray) Then
      Exit;
    For I := 0 To TJSONArray(Data).Count - 1 Do
      If TJSONArray(Data)[I] Is TJSONObject Then
        Begin
          Name := TJSONObject(TJSONArray(Data)[I]).Get('name', '');
          If (Name <> '') And (MCPToolName(Name) = MCPName) Then
            Begin
              Result := Name;
              Exit;
            End;
        End;
  Finally
    Data.Free;
  End;
End;

Function MCPToolsListResult(Const ToolsJSON: String): String;
Var
  Tools: TJSONArray;
  Body: TJSONObject;
Begin
  Tools := MCPTools(ToolsJSON);
  If Not Assigned(Tools) Then
    Tools := TJSONArray.Create;
  Body := TJSONObject.Create(['tools', Tools]);
  Try
    Result := Body.AsJSON;
  Finally
    Body.Free;
  End;
End;

{ Id is the request's id node or Nil for null; Payload is owned and freed here. }
Function Envelope(Id: TJSONData; Const Member: String; Payload: TJSONData): String;
Var
  Message: TJSONObject;
Begin
  Message := TJSONObject.Create(['jsonrpc', '2.0']);
  Try
    If Assigned(Id) Then
      Message.Add('id', Id.Clone)
    Else
      Message.Add('id', TJSONNull.Create);
    Message.Add(Member, Payload);
    Result := Message.AsJSON;
  Finally
    Message.Free;
  End;
End;

Function ErrorResponse(Id: TJSONData; Code: Integer; Const MessageText: String): String;
Begin
  Result := Envelope(Id, 'error', TJSONObject.Create(['code', Code, 'message', MessageText]));
End;

Function InitializeResult(Params: TJSONObject): TJSONObject;
Var
  Version: String;
Begin
  Version := MCPDefaultProtocolVersion;
  If Assigned(Params) And (Params.Find('protocolVersion') Is TJSONString) And (Params.Get('protocolVersion', '') <> '') Then
    Version := Params.Get('protocolVersion', '');
  Result := TJSONObject.Create(['protocolVersion', Version,
    'capabilities', TJSONObject.Create(['tools', TJSONObject.Create]),
    'serverInfo', TJSONObject.Create(['name', MCPServerName, 'version', MCPServerVersion])]);
End;

Function CallTool(Id: TJSONData; Params: TJSONObject; Const ToolsJSON: String; Executor: TMCPToolExecutor): String;
Var
  Arguments: TJSONData;
  ArgumentText, Tool, ResultText, ErrorText, Shown: String;
  Succeeded: Boolean;
Begin
  If Not Assigned(Params) Or Not (Params.Find('name') Is TJSONString) Then
    Begin
      Result := ErrorResponse(Id, MCPInvalidParams, 'tools/call needs a tool name.');
      Exit;
    End;
  Arguments := Params.Find('arguments');
  If Not Assigned(Arguments) Or (Arguments Is TJSONNull) Then
    ArgumentText := '{}'
  Else If Arguments Is TJSONObject Then
    ArgumentText := Arguments.AsJSON
  Else
    Begin
      Result := ErrorResponse(Id, MCPInvalidParams, 'tools/call arguments must be an object.');
      Exit;
    End;
  Tool := BrokerToolName(ToolsJSON, Params.Get('name', ''));
  If Tool = '' Then
    Begin
      Result := ErrorResponse(Id, MCPInvalidParams, 'Unknown tool: ' + Params.Get('name', ''));
      Exit;
    End;
  If Not Assigned(Executor) Then
    Begin
      Result := ErrorResponse(Id, MCPInternalError, 'No tool executor is attached.');
      Exit;
    End;
  ResultText := '';
  ErrorText := '';
  Try
    Succeeded := Executor(Tool, ArgumentText, ResultText, ErrorText);
  Except
    On E: Exception Do
      Begin
        Result := ErrorResponse(Id, MCPInternalError, 'The tool raised ' + E.ClassName + ': ' + E.Message);
        Exit;
      End;
  End;
  If Succeeded Then
    Shown := ResultText
  Else If ErrorText <> '' Then
    Shown := ErrorText
  Else If ResultText <> '' Then
    Shown := ResultText
  Else
    Shown := 'The tool failed.';
  Result := Envelope(Id, 'result', TJSONObject.Create([
    'content', TJSONArray.Create([TJSONObject.Create(['type', 'text', 'text', Shown])]),
    'isError', Not Succeeded]));
End;

Function MCPHandleMessage(Const RequestText, ToolsJSON: String; Executor: TMCPToolExecutor; Out ResponseText: String): Boolean;
Var
  Data, Id, ParamsNode: TJSONData;
  Request, Params: TJSONObject;
  Method: String;
  Tools: TJSONArray;
Begin
  ResponseText := '';
  Result := True;
  Data := ParseJSON(RequestText);
  If Not Assigned(Data) Then
    Begin
      ResponseText := ErrorResponse(Nil, MCPParseError, 'Parse error');
      Exit;
    End;
  Try
    { Batches were dropped from MCP in 2025-06-18; Claude Code sends one message per request. }
    If Not (Data Is TJSONObject) Then
      Begin
        ResponseText := ErrorResponse(Nil, MCPInvalidRequest, 'Invalid Request: expected one JSON-RPC object.');
        Exit;
      End;
    Request := TJSONObject(Data);
    Id := Request.Find('id');
    If Assigned(Id) And Not ((Id Is TJSONString) Or (Id Is TJSONNumber)) Then
      Begin
        ResponseText := ErrorResponse(Nil, MCPInvalidRequest, 'Invalid Request: id must be a string or a number.');
        Exit;
      End;
    If Request.Get('jsonrpc', '') <> '2.0' Then
      Begin
        ResponseText := ErrorResponse(Id, MCPInvalidRequest, 'Invalid Request: jsonrpc must be "2.0".');
        Exit;
      End;
    If Not Assigned(Request.Find('method')) Then
      Begin
        { A client's response to a server request. This server sends none, so there is nothing to match. }
        If Assigned(Id) And (Assigned(Request.Find('result')) Or Assigned(Request.Find('error'))) Then
          Result := False
        Else
          ResponseText := ErrorResponse(Id, MCPInvalidRequest, 'Invalid Request: no method.');
        Exit;
      End;
    If Not (Request.Find('method') Is TJSONString) Then
      Begin
        ResponseText := ErrorResponse(Id, MCPInvalidRequest, 'Invalid Request: method must be a string.');
        Exit;
      End;
    Method := Request.Get('method', '');
    If Not Assigned(Id) Then
      Begin
        { notifications/initialized, notifications/cancelled and the rest need no answer. }
        Result := False;
        Exit;
      End;
    ParamsNode := Request.Find('params');
    Params := Nil;
    If ParamsNode Is TJSONObject Then
      Params := TJSONObject(ParamsNode)
    Else If Assigned(ParamsNode) And Not (ParamsNode Is TJSONNull) Then
      Begin
        ResponseText := ErrorResponse(Id, MCPInvalidParams, 'params must be an object.');
        Exit;
      End;
    If Method = 'initialize' Then
      ResponseText := Envelope(Id, 'result', InitializeResult(Params))
    Else If Method = 'ping' Then
      ResponseText := Envelope(Id, 'result', TJSONObject.Create)
    Else If Method = 'tools/list' Then
      Begin
        Tools := MCPTools(ToolsJSON);
        If Assigned(Tools) Then
          ResponseText := Envelope(Id, 'result', TJSONObject.Create(['tools', Tools]))
        Else
          ResponseText := ErrorResponse(Id, MCPInternalError, 'The tool catalogue is not a JSON array.');
      End
    Else If Method = 'tools/call' Then
      ResponseText := CallTool(Id, Params, ToolsJSON, Executor)
    Else
      { server/discover and anything else. Claude Code carries on without them. }
      ResponseText := ErrorResponse(Id, MCPMethodNotFound, 'Method not found: ' + Method);
  Finally
    Data.Free;
  End;
End;

End.
