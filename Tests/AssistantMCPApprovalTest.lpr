Program AssistantMCPApprovalTest;

{ An MCP tool call held open by an approval past Claude Code's default 60 s, and a decline. No claude.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Classes, SysUtils, fpjson, jsonparser, fphttpclient, AssistantToolBroker, AssistantClaudeClient,
  AssistantMCPListener, AssistantMCPBridge, AssistantConfig, AssistantTools;

Const
  OriginalText = 'unit Main;';
  ApprovedText = 'unit Main; { approved }';
  DeclinedText = 'unit Main; { declined }';
  { Longer than Claude Code's default tool-call limit, which is what MCP_TOOL_TIMEOUT lifts. }
  HoldMs = 61000;
  ListBody = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}';

Type
  TMemoryWorkspace = Class(TAssistantWorkspaceAdapter)
  Public
    Text: String;
    Replaces: Integer;
    Function Identity: String; Override;
    Function ReadBuffer(Const Path: String; Out CanonicalPath, BufferText, ErrorText: String): Boolean; Override;
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
    RequestBody: String;
    Status: Integer;
    Body: String;
    Done: Boolean;
    Constructor Create(Const NewURL, NewToken, NewBody: String);
  End;

  { Stands in for the IDE's approval dialog. Runs on the main thread, as OnApproval does. }
  TApprover = Class
  Public
    Answer: Boolean;
    Hold: Boolean;
    Asked: Integer;
    AskedOnMain: Boolean;
    ListedDuringHold: Boolean;
    ReadDuringHold: Boolean;
    HeldMs: QWord;
    Function Decide(Const Tool, Path, OldText, NewText: String): Boolean;
  End;

  { The form's ApproveClaudeTool: the approval setting through ApproveToolIfNeeded, as for the assistant's own tools.
    Ask would show a modal confirmation, which this console test cannot answer, so only Auto and Always run here. }
  TSettingApprover = Class
  Public
    Asked: Integer;
    Summary: String;
    Function Decide(Const Tool, Path, OldText, NewText: String): Boolean;
  End;

Var
  Workspace: TMemoryWorkspace;
  Broker: TAssistantToolBroker;
  Bridge: TMCPBrokerBridge;
  Listener: TMCPListener;
  Approver: TApprover;

Function TMemoryWorkspace.Identity: String;
Begin
  Result := 'project-test';
End;

Function TMemoryWorkspace.ReadBuffer(Const Path: String; Out CanonicalPath, BufferText, ErrorText: String): Boolean;
Begin
  CanonicalPath := Path;
  BufferText := Text;
  ErrorText := '';
  Result := True;
End;

Function TMemoryWorkspace.ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean;
Begin
  ErrorText := '';
  Result := ExpectedText = Text;
  If Not Result Then
    Begin
      ErrorText := 'The buffer changed.';
      Exit;
    End;
  Text := NewText;
  Inc(Replaces);
End;

Function TMemoryWorkspace.SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean;
Begin
  ErrorText := 'Not saved in this test.';
  Result := False;
End;

Function TMemoryWorkspace.Describe: String;
Begin
  Result := 'Test project';
End;

Constructor TClientThread.Create(Const NewURL, NewToken, NewBody: String);
Begin
  EndpointURL := NewURL;
  BearerToken := NewToken;
  RequestBody := NewBody;
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
    { Claude Code with MCP_TOOL_TIMEOUT set: the client waits well past the hold. }
    Client.IOTimeout := 120000;
    Client.AddHeader('Authorization', 'Bearer ' + BearerToken);
    Client.AddHeader('Content-Type', 'application/json');
    Client.RequestBody := TStringStream.Create(RequestBody);
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

Function CallBody(Id: Integer; Const Tool, Arguments: String): String;
Begin
  Result := '{"jsonrpc":"2.0","id":' + IntToStr(Id) + ',"method":"tools/call","params":{"name":"' + Tool +
    '","arguments":' + Arguments + '}}';
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

{ Serves the main thread's queue, as the IDE's message loop would, until the client has its answer. }
Function PumpUntilDone(Client: TClientThread; WaitMs: QWord): Boolean;
Var
  Started: QWord;
Begin
  Started := GetTickCount64;
  While Not Client.Done And (GetTickCount64 - Started < WaitMs) Do
    CheckSynchronize(10);
  Result := Client.Done;
End;

{ A tools/call answered through the listener, with the main thread serving the queue. }
Function Call(Const Tool, Arguments: String; WaitMs: QWord; Out Status: Integer): String;
Var
  Client: TClientThread;
Begin
  Client := TClientThread.Create(Listener.URL, Listener.Token, CallBody(5, Tool, Arguments));
  Try
    PumpUntilDone(Client, WaitMs);
    Status := Client.Status;
    Result := Client.Body;
  Finally
    Client.Free;
  End;
End;

Function Revision: String;
Var
  Status: Integer;
  Data: TJSONData;
Begin
  Result := '';
  Data := Nil;
  Try
    Data := GetJSON(CallText(Call('read_buffer', '{"path":"Main.pas"}', 10000, Status)));
    Result := Data.FindPath('revision').AsString;
  Except
    Result := '';
  End;
  Data.Free;
End;

Function TApprover.Decide(Const Tool, Path, OldText, NewText: String): Boolean;
Var
  Started: QWord;
  Lister, Reader: TClientThread;
Begin
  Inc(Asked);
  AskedOnMain := GetCurrentThreadId = MainThreadID;
  Started := GetTickCount64;
  If Hold Then
    Begin
      { A modal dialog's message loop keeps serving queued calls, so the read can run while this one waits. }
      Lister := TClientThread.Create(Listener.URL, Listener.Token, ListBody);
      Reader := TClientThread.Create(Listener.URL, Listener.Token, CallBody(7, 'read_buffer', '{"path":"Main.pas"}'));
      Try
        While GetTickCount64 - Started < HoldMs Do
          CheckSynchronize(10);
        ListedDuringHold := Lister.Done And (Lister.Status = 200) And (Pos('replace_buffer', Lister.Body) > 0);
        ReadDuringHold := Reader.Done And (Pos(OriginalText, CallText(Reader.Body)) > 0);
      Finally
        Lister.WaitFor;
        Reader.WaitFor;
        Lister.Free;
        Reader.Free;
      End;
    End;
  HeldMs := GetTickCount64 - Started;
  Result := Answer;
End;

Function TSettingApprover.Decide(Const Tool, Path, OldText, NewText: String): Boolean;
Var
  ErrorText: String;
Begin
  Inc(Asked);
  Summary := MCPApprovalSummary(Path, OldText, NewText);
  Result := ApproveToolIfNeeded(Tool, '', Summary, ErrorText);
End;

Procedure CheckApprovalSetting;
Var
  Setting: TSettingApprover;
  Body, SavedMode: String;
  Status, Replaces: Integer;
Begin
  Check('the chat config exists', Assigned(AssistantChatConfig));
  Setting := TSettingApprover.Create;
  SavedMode := AssistantChatConfig.ApprovalMode;
  Try
    Broker.OnApproval := @Setting.Decide;
    AssistantChatConfig.ApprovalMode := 'auto';
    Replaces := Workspace.Replaces;
    Body := Call('replace_buffer', '{"path":"Main.pas","revision":"' + Revision + '","text":"unit Main; { auto }"}',
      10000, Status);
    Check('Auto still passes the edit through the approval hook', Setting.Asked = 1);
    Check('Auto applies a project edit without asking', (Status = 200) And (Pos('isError: ', CallText(Body)) = 0) And
      (Workspace.Text = 'unit Main; { auto }') And (Workspace.Replaces = Replaces + 1));
    Check('the approval names the path and the changed lines',
      (Pos('"path":"Main.pas"', Setting.Summary) > 0) And (Pos('lines 1-1 of 1 replaced by 1', Setting.Summary) > 0));
    AssistantChatConfig.ApprovalMode := 'always';
    Body := Call('replace_buffer', '{"path":"Main.pas","revision":"' + Revision + '","text":"unit Main; { always }"}',
      10000, Status);
    Check('Always applies a project edit without asking', (Status = 200) And (Workspace.Text = 'unit Main; { always }'));
  Finally
    AssistantChatConfig.ApprovalMode := SavedMode;
    Broker.OnApproval := @Approver.Decide;
    Setting.Free;
  End;
End;

Procedure CheckLongApproval;
Var
  Body, Error: String;
  Status: Integer;
Begin
  Approver.Answer := True;
  Approver.Hold := True;
  Body := Call('replace_buffer', '{"path":"Main.pas","revision":"' + Revision + '","text":"' + ApprovedText + '"}',
    HoldMs + 30000, Status);
  Error := CallText(Body);
  Check('the approval is asked once', Approver.Asked = 1);
  Check('the approval is asked on the main thread', Approver.AskedOnMain);
  Check('the approval stays open past 60 s', Approver.HeldMs >= HoldMs);
  Check('tools/list is answered while the approval is open', Approver.ListedDuringHold);
  Check('another tool call runs while the approval is open', Approver.ReadDuringHold);
  Check('the held call is still answered with 200', Status = 200);
  Check('the held call completes', (Pos('isError: ', Error) = 0) And (Pos('bufferUpdated', Error) > 0));
  Check('the approved edit reaches the buffer', (Workspace.Text = ApprovedText) And (Workspace.Replaces = 1));
End;

Procedure CheckDecline;
Var
  Body: String;
  Status: Integer;
Begin
  Approver.Answer := False;
  Approver.Hold := False;
  Approver.Asked := 0;
  Body := Call('replace_buffer', '{"path":"Main.pas","revision":"' + Revision + '","text":"' + DeclinedText + '"}',
    10000, Status);
  Check('the decline is asked', Approver.Asked = 1);
  Check('a decline is answered with 200, not a dropped connection', Status = 200);
  Check('a decline is a tool error', Pos('"isError" : true', Body) > 0);
  Check('the tool error tells Claude the user declined', Pos('declined', CallText(Body)) > 0);
  Check('a declined edit does not reach the buffer', (Workspace.Text = ApprovedText) And (Workspace.Replaces = 1));
  Check('no call is left waiting', Bridge.PendingCount = 0);
End;

Var
  Error: String;

Begin
  Workspace := TMemoryWorkspace.Create;
  Workspace.Text := OriginalText;
  Broker := TAssistantToolBroker.Create(Workspace);
  Approver := TApprover.Create;
  Broker.OnApproval := @Approver.Decide;
  Bridge := TMCPBrokerBridge.Create(Broker);
  Listener := Nil;
  Try
    Bridge.BeginRun(ctsProject);
    Listener := TMCPListener.Create(Bridge.ToolsJSON, @Bridge.Execute);
    Check('the listener starts', Listener.Start(Error));
    CheckLongApproval;
    CheckDecline;
    CheckApprovalSetting;
    Bridge.Cancel;
    Listener.Stop;
  Finally
    Listener.Free;
    Bridge.Free;
    Broker.Free;
    Approver.Free;
    Workspace.Free;
  End;
  CheckSynchronize(0);
  WriteLn('AssistantMCPApprovalTest passed');
End.
