Program AssistantMCPBridgeTest;

{ MCP tool calls from listener threads run on the main thread through a real broker. No claude. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, fpjson, jsonparser, fphttpclient, AssistantToolBroker, AssistantClaudeClient, AssistantMCPListener,
  AssistantMCPBridge;

Const
  BufferText = 'unit Main; unsaved IDE contents';
  ReadBody = '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"read_buffer","arguments":{"path":"Main.pas"}}}';
  WaitMs = 10000;

Type
  TMemoryWorkspace = Class(TAssistantWorkspaceAdapter)
  Public
    Reads: Integer;
    ReadThread: TThreadID;
    Function Identity: String; Override;
    Function ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean; Override;
    Function ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean; Override;
    Function SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean; Override;
    Function Describe: String; Override;
  End;

  TClientThread = Class(TThread)
  Protected
    Procedure Execute; Override;
  Public
    EndpointURL: String;
    BearerToken: String;
    Status: Integer;
    Body: String;
    Done: Boolean;
    Constructor Create(Const NewURL, NewToken: String);
  End;

Var
  Workspace: TMemoryWorkspace;
  Broker: TAssistantToolBroker;
  Bridge: TMCPBrokerBridge;
  Listener: TMCPListener;

Function TMemoryWorkspace.Identity: String;
Begin
  Result := 'project-test';
End;

Function TMemoryWorkspace.ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean;
Begin
  Inc(Reads);
  ReadThread := GetCurrentThreadId;
  CanonicalPath := Path;
  Text := BufferText;
  ErrorText := '';
  Result := True;
End;

Function TMemoryWorkspace.ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean;
Begin
  ErrorText := 'Read-only test workspace.';
  Result := False;
End;

Function TMemoryWorkspace.SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean;
Begin
  ErrorText := 'Read-only test workspace.';
  Result := False;
End;

Function TMemoryWorkspace.Describe: String;
Begin
  Result := 'Test project';
End;

Constructor TClientThread.Create(Const NewURL, NewToken: String);
Begin
  EndpointURL := NewURL;
  BearerToken := NewToken;
  Status := 0;
  Body := '';
  Done := False;
  FreeOnTerminate := False;
  Inherited Create(False);
End;

Procedure TClientThread.Execute;
Var
  Client: TFPHTTPClient;
  Response: TStringStream;
Begin
  Client := TFPHTTPClient.Create(Nil);
  Response := TStringStream.Create('');
  Try
    Client.KeepConnection := False;
    Client.IOTimeout := 15000;
    Client.AddHeader('Authorization', 'Bearer ' + BearerToken);
    Client.AddHeader('Content-Type', 'application/json');
    Client.RequestBody := TStringStream.Create(ReadBody);
    Try
      Client.HTTPMethod('POST', EndpointURL, Response, []);
      Status := Client.ResponseStatusCode;
      Body := Response.DataString;
    Except
      On E: Exception Do
        Body := E.ClassName + ': ' + E.Message;
    End;
  Finally
    Client.RequestBody.Free;
    Client.RequestBody := Nil;
    Response.Free;
    Client.Free;
  End;
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

{ The first content text of a tools/call answer, prefixed "isError: " when the tool failed. }
Function CallText(Const ResponseBody: String): String;
Var
  Data, Content: TJSONData;
Begin
  Result := '';
  Try
    Data := GetJSON(ResponseBody);
  Except
    Exit;
  End;
  Try
    Content := Data.FindPath('result.content[0].text');
    If Assigned(Content) Then
      Result := Content.AsString;
    If Assigned(Data.FindPath('result.isError')) And Data.FindPath('result.isError').AsBoolean Then
      Result := 'isError: ' + Result;
  Finally
    Data.Free;
  End;
End;

Function StartListener: Boolean;
Var
  Error: String;
Begin
  FreeAndNil(Listener);
  Listener := TMCPListener.Create(Bridge.ToolsJSON, @Bridge.Execute);
  Result := Listener.Start(Error);
End;

{ Serves the main thread's queue, as the IDE's message loop would, until the client has its answer. }
Function PumpUntilDone(Client: TClientThread): Boolean;
Var
  Started: QWord;
Begin
  Started := GetTickCount64;
  While Not Client.Done And (GetTickCount64 - Started < WaitMs) Do
    CheckSynchronize(10);
  Result := Client.Done;
End;

Procedure CheckScopes;
Begin
  Check('ctsNone maps to awsNone', ClaudeBrokerWriteScope(ctsNone) = awsNone);
  Check('ctsRead maps to awsReadOnly', ClaudeBrokerWriteScope(ctsRead) = awsReadOnly);
  Check('ctsMarkdown maps to awsMarkdown', ClaudeBrokerWriteScope(ctsMarkdown) = awsMarkdown);
  Check('ctsProject maps to awsProject', ClaudeBrokerWriteScope(ctsProject) = awsProject);
  Bridge.BeginRun(ctsNone);
  Check('a Chat run lists no broker tools', Bridge.ToolsJSON = '[]');
  Bridge.BeginRun(ctsRead);
  Check('a read run lists read_buffer', Pos('"lazarus_read_buffer"', Bridge.ToolsJSON) > 0);
  Check('a read run lists no replace_buffer', Pos('"lazarus_replace_buffer"', Bridge.ToolsJSON) = 0);
  Bridge.BeginRun(ctsMarkdown);
  Check('a Markdown run lists replace_buffer for Markdown only',
    (Pos('"lazarus_replace_buffer"', Bridge.ToolsJSON) > 0) And (Pos('Only .md', Bridge.ToolsJSON) > 0));
  Bridge.BeginRun(ctsProject);
  Check('a project run lists replace_buffer for any file',
    (Pos('"lazarus_replace_buffer"', Bridge.ToolsJSON) > 0) And (Pos('Only .md', Bridge.ToolsJSON) = 0));
  Check('the bridge run is the broker run', (Bridge.RunId <> '') And (Bridge.RunId = Broker.RunId));
End;

Procedure CheckSummaries;
Const
  Before = 'unit Main;' + LineEnding + 'var' + LineEnding + '  X: Integer;' + LineEnding + 'end.';
  After = 'unit Main;' + LineEnding + 'var' + LineEnding + '  Y: Integer;' + LineEnding + '  Z: Integer;' + LineEnding +
    'end.';
Var
  Summary: String;
  Data: TJSONData;
Begin
  Summary := MCPApprovalSummary('Main.pas', Before, After);
  Check('a summary names the replaced lines', Pos('"change":"lines 3-3 of 4 replaced by 2"', Summary) > 0);
  Check('a summary shows the start of the new lines', Pos('"new":"Y: Integer; / Z: Integer;"', Summary) > 0);
  Check('an insertion is named as one', Pos('2 lines inserted after line 2 of 4',
    MCPApprovalSummary('Main.pas', Before, 'unit Main;' + LineEnding + 'var' + LineEnding + 'a' + LineEnding + 'b' +
    LineEnding + '  X: Integer;' + LineEnding + 'end.')) > 0);
  Check('new text is named as new', Pos('"change":"new text, 4 lines"', MCPApprovalSummary('New.md', '', Before)) > 0);
  Check('no change is named as none', Pos('"change":"no change"', MCPApprovalSummary('Main.pas', Before, Before)) > 0);
  Check('without a path the start of the text is shown', MCPApprovalSummary('', '', '["status"]') = '["status"]');
  Summary := MCPApprovalSummary('Odd "name".pas', '', StringOfChar('x', 500));
  Check('a long change fits the confirmation', Length(Summary) <= 240);
  Data := Nil;
  Try
    Data := GetJSON(Summary);
  Except
    Data := Nil;
  End;
  Check('a summary with quotes in the path is valid JSON',
    Assigned(Data) And (Data.FindPath('path').AsString = 'Odd "name".pas'));
  Data.Free;
End;

Procedure CheckCall;
Var
  Client: TClientThread;
  Reads: Integer;
Begin
  Bridge.BeginRun(ctsRead);
  Check('the listener starts with the run''s catalogue', StartListener);
  Reads := Workspace.Reads;
  Client := TClientThread.Create(Listener.URL, Listener.Token);
  Try
    Check('the call is answered once the main thread serves its queue', PumpUntilDone(Client));
    Check('the call gets 200', Client.Status = 200);
    Check('the broker result comes back to the client', Pos(BufferText, CallText(Client.Body)) > 0);
    Check('the result is not an error', Pos('isError: ', CallText(Client.Body)) = 0);
    Check('the adapter ran once', Workspace.Reads = Reads + 1);
    Check('the adapter ran on the main thread', Workspace.ReadThread = MainThreadID);
    Check('no call is left waiting', Bridge.PendingCount = 0);
  Finally
    Client.Free;
  End;
End;

Procedure CheckDirectCall;
Var
  ResultText, ErrorText: String;
Begin
  Check('a call on the main thread runs at once',
    Bridge.Execute('lazarus_read_buffer', '{"path":"Main.pas"}', ResultText, ErrorText) And (Pos(BufferText, ResultText) > 0));
End;

Procedure CheckCancel;
Var
  Client: TClientThread;
  Reads: Integer;
  Started: QWord;
  ResultText, ErrorText: String;
Begin
  Reads := Workspace.Reads;
  { The main thread does not serve its queue here, as when the IDE is busy, so the call stays waiting. }
  Client := TClientThread.Create(Listener.URL, Listener.Token);
  Try
    Started := GetTickCount64;
    While (Bridge.PendingCount = 0) And (GetTickCount64 - Started < WaitMs) Do
      Sleep(10);
    Check('the call waits for the main thread', (Bridge.PendingCount = 1) And Not Client.Done);
    Bridge.Cancel;
    Started := GetTickCount64;
    While Not Client.Done And (GetTickCount64 - Started < WaitMs) Do
      Sleep(10);
    Check('Cancel releases the waiting call without the main thread', Client.Done);
    Check('the released call is answered with the cancel error', CallText(Client.Body) = 'isError: ' + MCPRunCancelledText);
    Check('the released call leaves the pending list', Bridge.PendingCount = 0);
    CheckSynchronize(0);
    Check('the queued call is skipped when the main thread reaches it', Workspace.Reads = Reads);
    Check('Cancel ends the broker run', Not Broker.Execute(Bridge.RunId, 'lazarus_read_buffer', '{"path":"Main.pas"}', ResultText, ErrorText));
  Finally
    Client.Free;
  End;
  Client := TClientThread.Create(Listener.URL, Listener.Token);
  Try
    Started := GetTickCount64;
    While Not Client.Done And (GetTickCount64 - Started < WaitMs) Do
      Sleep(10);
    Check('a call after Cancel is refused without waiting', Client.Done And (CallText(Client.Body) = 'isError: ' + MCPRunCancelledText));
    Check('a refused call is never queued', (Bridge.PendingCount = 0) And (Workspace.Reads = Reads));
  Finally
    Client.Free;
  End;
  Check('a main-thread call after Cancel is refused',
    Not Bridge.Execute('lazarus_read_buffer', '{"path":"Main.pas"}', ResultText, ErrorText) And (ErrorText = MCPRunCancelledText));
End;

Procedure CheckNextRun;
Var
  Client: TClientThread;
  OldRun: String;
Begin
  OldRun := Bridge.RunId;
  Bridge.BeginRun(ctsRead);
  Check('the next run has a new run id', (Bridge.RunId <> '') And (Bridge.RunId <> OldRun));
  Client := TClientThread.Create(Listener.URL, Listener.Token);
  Try
    Check('calls run again in the next run', PumpUntilDone(Client) And (Pos(BufferText, CallText(Client.Body)) > 0));
  Finally
    Client.Free;
  End;
  { The run ends in the order the form will use: release waiting calls, then stop the listener. }
  Bridge.Cancel;
  Listener.Stop;
  Check('the listener stops after Cancel', Not Listener.Running);
End;

Begin
  Workspace := TMemoryWorkspace.Create;
  Broker := TAssistantToolBroker.Create(Workspace);
  Bridge := TMCPBrokerBridge.Create(Broker);
  Listener := Nil;
  Try
    CheckScopes;
    CheckSummaries;
    CheckCall;
    CheckDirectCall;
    CheckCancel;
    CheckNextRun;
  Finally
    Listener.Free;
    Bridge.Free;
    Broker.Free;
    Workspace.Free;
  End;
  CheckSynchronize(0);
  WriteLn('AssistantMCPBridgeTest passed');
End.
