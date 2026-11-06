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
  AssistantMCPBridge, AssistantSearchUtil, AssistantTestSettings, AssistantLfm;

Const
  BufferText = 'unit Main; unsaved IDE contents';
  ReadBody = '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"read_buffer","arguments":{"path":"Main.pas"}}}';
  WaitMs = 10000;

Type
  TMemoryWorkspace = Class(TAssistantWorkspaceAdapter)
  Public
    Reads: Integer;
    ReadThread: TThreadID;
    StoredText, DiskText, OpenPath: String;
    ReplaceCount, SaveCount, EditorStamp: Integer;
    AllowInspect, AllowChanges, AllowBuild: Boolean;
    ProjectRoot, BaseCommand, LastCommand: String;
    LaunchCount, FormCalls: Integer;
    PasText, LfmText: String;
    ApprovedTool, ApprovedPath, ApprovedOld, ApprovedNew: String;
    Function Identity: String; Override;
    Function ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean; Override;
    Function ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean; Override;
    Function SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean; Override;
    Function Describe: String; Override;
    Function CanInspectFiles: Boolean; Override;
    Function CanChangeSets: Boolean; Override;
    Function OpenBuffer(Const Path: String; Out ErrorText: String): Boolean; Override;
    Function SearchInProject(Const Arguments: String; Out ResultText, ErrorText: String): Boolean; Override;
    Function CanBuild: Boolean; Override;
    Function CanTest: Boolean; Override;
    Function TestCommand(Const BuildId, OnlyJSON: String; Out Command, ErrorText: String): Boolean; Override;
    Function StartTests(Const BuildId, ExpectedCommand, OnlyJSON: String; Out ResultText, ErrorText: String): Boolean; Override;
    Function EnsureFormComponent(Const Arguments: String; Out ResultText, ErrorText: String): Boolean; Override;
    Function ReadChangeBuffer(Const Path: String; Out CanonicalPath, Text, Stamp, ErrorText: String): Boolean; Override;
    Function ApproveReplace(Const Tool, Path, OldText, NewText: String): Boolean;
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
  Text := StoredText;
  ErrorText := '';
  Result := True;
End;

Function TMemoryWorkspace.ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean;
Begin
  Inc(ReplaceCount);
  If ExpectedText <> StoredText Then
    Begin
      ErrorText := 'Buffer text did not match.';
      Result := False;
      Exit;
    End;
  StoredText := NewText;
  Inc(EditorStamp);
  ErrorText := '';
  Result := True;
End;

Function TMemoryWorkspace.CanInspectFiles: Boolean;
Begin
  Result := AllowInspect;
End;

Function TMemoryWorkspace.CanChangeSets: Boolean;
Begin
  Result := AllowChanges;
End;

Function TMemoryWorkspace.OpenBuffer(Const Path: String; Out ErrorText: String): Boolean;
Begin
  ErrorText := '';
  Result := AllowInspect;
End;

Function TMemoryWorkspace.SearchInProject(Const Arguments: String; Out ResultText, ErrorText: String): Boolean;
Var
  Data: TJSONData;
  Query, Path, Body, Rel: String;
  MaxResults: Integer;
  FilesOnly: Boolean;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Data := GetJSON(Arguments);
  Try
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'Expected object arguments.';
        Exit;
      End;
    Query := TJSONObject(Data).Get('query', '');
    If Query = '' Then
      Query := TJSONObject(Data).Get('pattern', '');
    Path := TJSONObject(Data).Get('path', '');
    MaxResults := TJSONObject(Data).Get('max_results', 0);
    FilesOnly := False;
    If Assigned(TJSONObject(Data).Find('files_only')) And (TJSONObject(Data).Find('files_only').JSONType = jtBoolean) Then
      FilesOnly := TJSONObject(Data).Find('files_only').AsBoolean;
  Finally
    Data.Free;
  End;
  If (Path = '') Or (Path = OpenPath) Then
    Begin
      Body := StoredText;
      Rel := OpenPath;
    End
  Else
    Begin
      Body := DiskText;
      Rel := Path;
    End;
  Result := SearchTextMatches(Query, Rel, Body, FilesOnly, MaxResults, ResultText, ErrorText);
End;

Function TMemoryWorkspace.CanBuild: Boolean;
Begin
  Result := AllowBuild;
End;

Function TMemoryWorkspace.CanTest: Boolean;
Begin
  Result := AllowBuild;
End;

Function TMemoryWorkspace.TestCommand(Const BuildId, OnlyJSON: String; Out Command, ErrorText: String): Boolean;
Begin
  Result := ApplyTestOnly(BaseCommand, ProjectRoot, OnlyJSON, Command, ErrorText);
End;

Function TMemoryWorkspace.StartTests(Const BuildId, ExpectedCommand, OnlyJSON: String; Out ResultText, ErrorText: String): Boolean;
Var
  Command: String;
Begin
  Result := False;
  ResultText := '';
  If Not TestCommand(BuildId, OnlyJSON, Command, ErrorText) Then Exit;
  If Command <> ExpectedCommand Then
    Begin
      ErrorText := 'Test configuration, executable or build changed during approval.';
      Exit;
    End;
  LastCommand := Command;
  Inc(LaunchCount);
  ResultText := '{"started":true,"job_id":"test-job"}';
  Result := True;
End;

Function TMemoryWorkspace.EnsureFormComponent(Const Arguments: String; Out ResultText, ErrorText: String): Boolean;
Var
  Data: TJSONData;
  CompName, ComponentClass, PropsJson, PropLines, Detected: String;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Inc(FormCalls);
  Data := GetJSON(Arguments);
  Try
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'Expected object arguments.';
        Exit;
      End;
    CompName := Trim(TJSONObject(Data).Get('name', ''));
    ComponentClass := Trim(TJSONObject(Data).Get('class_name', ''));
    PropsJson := TJSONObject(Data).Get('properties', '');
  Finally
    Data.Free;
  End;
  If (CompName = '') Or (ComponentClass = '') Then
    Begin
      ErrorText := 'ensure_form_component requires path, name, and class_name.';
      Exit;
    End;
  If ComponentClass[1] <> 'T' Then
    ComponentClass := 'T' + ComponentClass;
  If Not BuildLfmPropertyLines(PropsJson, PropLines, Detected) Then
    Begin
      ErrorText := 'properties must be a JSON object string when provided.';
      Exit;
    End;
  If Pos(LowerCase(CompName + ':'), LowerCase(PasText)) = 0 Then
    PasText := PasText + LineEnding + '    ' + CompName + ': ' + ComponentClass + ';';
  UpsertLfmComponent(LfmText, CompName, ComponentClass, PropLines);
  ResultText := 'ensured ' + CompName;
  Result := True;
End;

Function TMemoryWorkspace.ReadChangeBuffer(Const Path: String; Out CanonicalPath, Text, Stamp, ErrorText: String): Boolean;
Begin
  Stamp := '';
  Result := ReadBuffer(Path, CanonicalPath, Text, ErrorText);
  If Result Then Stamp := 'stamp:' + IntToStr(EditorStamp);
End;

Function TMemoryWorkspace.ApproveReplace(Const Tool, Path, OldText, NewText: String): Boolean;
Begin
  ApprovedTool := Tool;
  ApprovedPath := Path;
  ApprovedOld := OldText;
  ApprovedNew := NewText;
  Result := True;
End;

Function TMemoryWorkspace.SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean;
Begin
  Inc(SaveCount);
  If ExpectedText <> StoredText Then
    Begin
      ErrorText := 'Buffer text did not match.';
      Result := False;
      Exit;
    End;
  ErrorText := '';
  Result := True;
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
  Check('a read run lists no replace_in_buffer', Pos('"lazarus_replace_in_buffer"', Bridge.ToolsJSON) = 0);
  Check('a read run hides the form tool', Pos('lazarus_ensure_form_component', Bridge.ToolsJSON) = 0);
  Bridge.BeginRun(ctsMarkdown);
  Check('a Markdown run lists replace_buffer for Markdown only',
    (Pos('"lazarus_replace_buffer"', Bridge.ToolsJSON) > 0) And (Pos('Only .md', Bridge.ToolsJSON) > 0));
  Check('a Markdown run lists replace_in_buffer', Pos('"lazarus_replace_in_buffer"', Bridge.ToolsJSON) > 0);
  Bridge.BeginRun(ctsProject);
  Check('a project run lists replace_buffer for any file',
    (Pos('"lazarus_replace_buffer"', Bridge.ToolsJSON) > 0) And (Pos('Only .md', Bridge.ToolsJSON) = 0));
  Check('a project run lists replace_in_buffer', Pos('"lazarus_replace_in_buffer"', Bridge.ToolsJSON) > 0);
  Check('a project run lists the form tool', Pos('"lazarus_ensure_form_component"', Bridge.ToolsJSON) > 0);
  Bridge.BeginRun(ctsMarkdown);
  Check('a Markdown run hides the form tool', Pos('lazarus_ensure_form_component', Bridge.ToolsJSON) = 0);
  Bridge.BeginRun(ctsProject);
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

Function JsonPath(Const Json, Path: String): String;
Var
  Data, Node: TJSONData;
Begin
  Result := '';
  Try
    Data := GetJSON(Json);
  Except
    Exit;
  End;
  Try
    Node := Data.FindPath(Path);
    If Assigned(Node) Then Result := Node.AsString;
  Finally
    Data.Free;
  End;
End;

Function ObjectArguments(Const Path, Revision, TextName, TextValue: String; IncludeFlag, Flag: Boolean;
  Const FlagName: String): String;
Var
  Obj: TJSONObject;
Begin
  Obj := TJSONObject.Create;
  Try
    If Path <> '' Then Obj.Add('path', Path);
    If Revision <> '' Then Obj.Add('revision', Revision);
    If TextName <> '' Then Obj.Add(TextName, TextValue);
    If IncludeFlag Then Obj.Add(FlagName, Flag);
    Result := Obj.AsJSON;
  Finally
    Obj.Free;
  End;
End;

Function JsonField(Const Json, Name: String): String;
Var
  Data: TJSONData;
Begin
  Result := '';
  Try
    Data := GetJSON(Json);
  Except
    Exit;
  End;
  Try
    If Data Is TJSONObject Then
      Result := TJSONObject(Data).Get(Name, '');
  Finally
    Data.Free;
  End;
End;

Function ReplaceArguments(Const Path, Revision, OldText, NewText: String; IncludeReplaceAll, ReplaceAll: Boolean): String;
Var
  Obj: TJSONObject;
Begin
  Obj := TJSONObject.Create;
  Try
    Obj.Add('path', Path);
    Obj.Add('revision', Revision);
    Obj.Add('old_text', OldText);
    Obj.Add('new_text', NewText);
    If IncludeReplaceAll Then
      Obj.Add('replace_all', ReplaceAll);
    Result := Obj.AsJSON;
  Finally
    Obj.Free;
  End;
End;

Function ReadRevision(Const Path: String): String;
Var
  ResultText, ErrorText: String;
Begin
  Check('read ' + Path,
    Broker.Execute(Bridge.RunId, 'lazarus_read_buffer', '{"path":"' + Path + '"}', ResultText, ErrorText));
  Result := JsonField(ResultText, 'revision');
  Check('read ' + Path + ' returned a revision', Result <> '');
End;

Procedure CheckReplaceInBuffer;
Const
  Secret = 'SecretTokenValue';
  Edited = 'EditedTokenValue';
Var
  Before, After, Revision, NextRevision, ResultText, ErrorText, Summary: String;
  Calls: Integer;
Begin
  Broker.OnApproval := @Workspace.ApproveReplace;
  Before := 'keep' + LineEnding + Secret + LineEnding + 'tail';
  After := 'keep' + LineEnding + Edited + LineEnding + 'tail';
  Workspace.StoredText := Before;
  Workspace.ReplaceCount := 0;
  Bridge.BeginRun(ctsProject);
  Revision := ReadRevision('Main.pas');
  Workspace.ApprovedOld := '';
  Workspace.ApprovedNew := '';
  Check('a unique match is replaced', Broker.Execute(Bridge.RunId, 'lazarus_replace_in_buffer',
    ReplaceArguments('Main.pas', Revision, Secret, Edited, False, False), ResultText, ErrorText));
  NextRevision := JsonField(ResultText, 'revision');
  Check('the new revision is returned', (NextRevision <> '') And (NextRevision <> Revision));
  Check('the reply names the changed lines', JsonField(ResultText, 'lines') = '2-2');
  Check('the reply contains no buffer text', (Pos(Secret, ResultText) = 0) And (Pos(Edited, ResultText) = 0) And
    (Pos(Before, ResultText) = 0) And (Pos(After, ResultText) = 0) And (Pos('"text"', ResultText) = 0));
  Check('the buffer holds the replacement', Workspace.StoredText = After);
  Check('the unique match was one editor edit', Workspace.ReplaceCount = 1);
  Summary := MCPApprovalSummary(Workspace.ApprovedPath, Workspace.ApprovedOld, Workspace.ApprovedNew);
  Check('approval receives the old and new buffer text', (Workspace.ApprovedTool = 'lazarus_replace_in_buffer') And
    (Workspace.ApprovedOld = Before) And (Workspace.ApprovedNew = After));
  Check('the approval summary names the changed lines', Pos('lines 2-2 of 3 replaced by 1', Summary) > 0);
  Check('the returned revision accepts the next edit', Broker.Execute(Bridge.RunId, 'lazarus_replace_in_buffer',
    ReplaceArguments('Main.pas', NextRevision, Edited, 'EditedAgain', False, False), ResultText, ErrorText) And
    (Workspace.StoredText = 'keep' + LineEnding + 'EditedAgain' + LineEnding + 'tail'));

  Before := Workspace.StoredText;
  Calls := Workspace.ReplaceCount;
  Revision := ReadRevision('Main.pas');
  Check('a missing match fails', Not Broker.Execute(Bridge.RunId, 'lazarus_replace_in_buffer',
    ReplaceArguments('Main.pas', Revision, 'missing-token', Edited, False, False), ResultText, ErrorText));
  Check('a missing match leaves the buffer unchanged', (Workspace.StoredText = Before) And (Workspace.ReplaceCount = Calls));

  Workspace.StoredText := 'one' + LineEnding + 'two' + LineEnding + 'one';
  Bridge.BeginRun(ctsProject);
  Revision := ReadRevision('Main.pas');
  Calls := Workspace.ReplaceCount;
  Before := Workspace.StoredText;
  Check('two matches without replace_all fail', Not Broker.Execute(Bridge.RunId, 'lazarus_replace_in_buffer',
    ReplaceArguments('Main.pas', Revision, 'one', 'ONE', False, False), ResultText, ErrorText));
  Check('two matches leave the buffer unchanged', (Workspace.StoredText = Before) And (Workspace.ReplaceCount = Calls));
  Check('replace_all replaces both', Broker.Execute(Bridge.RunId, 'lazarus_replace_in_buffer',
    ReplaceArguments('Main.pas', Revision, 'one', 'ONE', True, True), ResultText, ErrorText));
  Check('both matches were replaced', Workspace.StoredText = 'ONE' + LineEnding + 'two' + LineEnding + 'ONE');
  Check('replace_all was one editor edit', Workspace.ReplaceCount = Calls + 1);
  Check('the replace_all reply contains no buffer text', (Pos('ONE', ResultText) = 0) And (Pos('one', ResultText) = 0));

  Workspace.StoredText := 'keep' + LineEnding + 'only-once' + LineEnding + 'tail';
  Bridge.BeginRun(ctsProject);
  Revision := ReadRevision('Main.pas');
  Workspace.StoredText := 'keep' + LineEnding + 'moved-once' + LineEnding + 'tail';
  Calls := Workspace.ReplaceCount;
  Before := Workspace.StoredText;
  Check('a stale revision fails', Not Broker.Execute(Bridge.RunId, 'lazarus_replace_in_buffer',
    ReplaceArguments('Main.pas', Revision, 'moved-once', 'changed', False, False), ResultText, ErrorText));
  Check('a stale revision leaves the buffer unchanged', (Workspace.StoredText = Before) And (Workspace.ReplaceCount = Calls));

  Workspace.StoredText := 'keep' + LineEnding + 'edit me' + LineEnding;
  Bridge.BeginRun(ctsMarkdown);
  Revision := ReadRevision('Main.pas');
  Calls := Workspace.ReplaceCount;
  Before := Workspace.StoredText;
  Check('the Markdown scope refuses a pas path', Not Broker.Execute(Bridge.RunId, 'lazarus_replace_in_buffer',
    ReplaceArguments('Main.pas', Revision, 'edit me', 'edited', False, False), ResultText, ErrorText) And
    (Pos('Markdown', ErrorText) > 0));
  Check('a refused pas path leaves the buffer unchanged', (Workspace.StoredText = Before) And (Workspace.ReplaceCount = Calls));
  Revision := ReadRevision('Notes.md');
  Check('the Markdown scope accepts a markdown path', Broker.Execute(Bridge.RunId, 'lazarus_replace_in_buffer',
    ReplaceArguments('Notes.md', Revision, 'edit me', 'edited', False, False), ResultText, ErrorText));
  Check('the markdown buffer was edited', Workspace.StoredText = 'keep' + LineEnding + 'edited' + LineEnding);
  Check('the markdown reply contains no buffer text', (Pos('edited', ResultText) = 0) And (Pos('edit me', ResultText) = 0));

  Broker.OnApproval := Nil;
  Workspace.StoredText := BufferText;
End;

Procedure CheckNoEcho;
Const
  Secret = 'SecretTokenValue';
  Edited = 'EditedTokenValue';
Var
  Before, After, Revision, ResultText, ErrorText, PrepareArgs, ApplyArgs: String;
  Saves: Integer;
  Root, Change, Apply: TJSONObject;
  Changes: TJSONArray;
  Data, Node: TJSONData;
Begin
  Before := 'keep' + LineEnding + Secret + LineEnding + 'tail';
  After := 'keep' + LineEnding + Edited + LineEnding + 'tail';
  Workspace.StoredText := Before;
  Workspace.EditorStamp := 1;
  Workspace.AllowInspect := True;
  Workspace.AllowChanges := True;
  Workspace.SaveCount := 0;
  Bridge.BeginRun(ctsProject);
  Check('read_buffer still returns text by default',
    Broker.Execute(Bridge.RunId, 'lazarus_read_buffer', '{"path":"Main.pas"}', ResultText, ErrorText) And
    (Pos(Secret, ResultText) > 0));
  Revision := JsonField(ResultText, 'revision');
  Saves := Workspace.SaveCount;
  Check('replace_buffer applies', Broker.Execute(Bridge.RunId, 'lazarus_replace_buffer',
    ObjectArguments('Main.pas', Revision, 'text', After, False, False, ''), ResultText, ErrorText));
  Check('replace_buffer reply contains no buffer text', (Pos(Secret, ResultText) = 0) And (Pos(Edited, ResultText) = 0) And
    (Pos(Before, ResultText) = 0) And (Pos(After, ResultText) = 0) And (Pos('"text"', ResultText) = 0));
  Check('replace_buffer names the changed lines', JsonField(ResultText, 'lines') = '2-2');
  Revision := JsonField(ResultText, 'revision');
  Check('save accepts the replace_buffer revision', (Revision <> '') And Broker.Execute(Bridge.RunId, 'lazarus_save_buffer',
    ObjectArguments('Main.pas', Revision, '', '', False, False, ''), ResultText, ErrorText) And (Workspace.SaveCount = Saves + 1));

  Workspace.StoredText := Before;
  Workspace.EditorStamp := 1;
  Bridge.BeginRun(ctsProject);
  Revision := ReadRevision('Main.pas');
  Root := TJSONObject.Create;
  Changes := TJSONArray.Create;
  Change := TJSONObject.Create;
  Root.Add('changes', Changes);
  Changes.Add(Change);
  Change.Add('path', 'Main.pas');
  Change.Add('revision', Revision);
  Change.Add('text', After);
  PrepareArgs := Root.AsJSON;
  Root.Free;
  Check('prepare the change set', Broker.Execute(Bridge.RunId, 'lazarus_prepare_changes', PrepareArgs, ResultText, ErrorText));
  Apply := TJSONObject.Create;
  Try
    Apply.Add('change_set_id', JsonPath(ResultText, 'change_set_id'));
    ApplyArgs := Apply.AsJSON;
  Finally
    Apply.Free;
  End;
  Saves := Workspace.SaveCount;
  Check('apply_changes applies', Broker.Execute(Bridge.RunId, 'lazarus_apply_changes', ApplyArgs, ResultText, ErrorText));
  Check('apply_changes reply contains no buffer text', (Pos(Secret, ResultText) = 0) And (Pos(Edited, ResultText) = 0) And
    (Pos(Before, ResultText) = 0) And (Pos(After, ResultText) = 0));
  Check('apply_changes names the changed lines', JsonPath(ResultText, 'files[0].lines') = '2-2');
  Revision := JsonPath(ResultText, 'files[0].revision');
  Check('save accepts the apply_changes revision', (Revision <> '') And Broker.Execute(Bridge.RunId, 'lazarus_save_buffer',
    ObjectArguments('Main.pas', Revision, '', '', False, False, ''), ResultText, ErrorText) And (Workspace.SaveCount = Saves + 1));

  Workspace.StoredText := Before;
  Bridge.BeginRun(ctsProject);
  Check('open_buffer can omit the text', Broker.Execute(Bridge.RunId, 'lazarus_open_buffer',
    ObjectArguments('Main.pas', '', '', '', True, False, 'include_text'), ResultText, ErrorText));
  Check('open_buffer reply contains no buffer text', (Pos(Secret, ResultText) = 0) And (Pos('"text"', ResultText) = 0));
  Revision := JsonField(ResultText, 'revision');
  Data := Nil;
  Try
    Data := GetJSON(ResultText);
    Node := Data.FindPath('line_count');
    Check('open_buffer reports the line count', Assigned(Node) And (Node.AsInteger = 3));
  Finally
    Data.Free;
  End;
  Check('replace_in_buffer accepts the open_buffer revision', (Revision <> '') And
    Broker.Execute(Bridge.RunId, 'lazarus_replace_in_buffer',
    ReplaceArguments('Main.pas', Revision, Secret, Edited, False, False), ResultText, ErrorText) And
    (Workspace.StoredText = After));

  Workspace.AllowInspect := False;
  Workspace.AllowChanges := False;
  Workspace.StoredText := BufferText;
End;

Procedure CheckSearch;
Const
  Unsaved = 'OnlyUnsavedToken';
  Disk = 'OnlyDiskToken';
Var
  ResultText, ErrorText: String;
  Obj: TJSONObject;
Begin
  Workspace.AllowInspect := True;
  Workspace.OpenPath := 'Main.pas';
  Workspace.DiskText := 'alpha' + LineEnding + Disk + LineEnding + 'omega';
  Workspace.StoredText := Unsaved + '-one' + LineEnding + Unsaved + '-two' + LineEnding + Unsaved + '-three';
  Bridge.BeginRun(ctsRead);
  Check('a read run lists search_in_project', Pos('"lazarus_search_in_project"', Bridge.ToolsJSON) > 0);
  Obj := TJSONObject.Create;
  Try
    Obj.Add('query', Unsaved);
    Obj.Add('path', 'Main.pas');
    Obj.Add('max_results', 1);
    Check('an unsaved buffer match is found', Broker.Execute(Bridge.RunId, 'lazarus_search_in_project', Obj.AsJSON,
      ResultText, ErrorText) And (Pos(Unsaved + '-one', ResultText) > 0) And (Pos(Disk, ResultText) = 0));
    Check('max_results caps the output', (Pos(Unsaved + '-two', ResultText) = 0) And (Pos('capped at 1', ResultText) > 0));
    Obj.Free;
    Obj := Nil;
    Obj := TJSONObject.Create;
    Obj.Add('query', Unsaved);
    Obj.Add('path', 'Main.pas');
    Obj.Add('max_results', 5);
    Obj.Add('files_only', True);
    Check('files_only returns the path without the line', Broker.Execute(Bridge.RunId, 'lazarus_search_in_project',
      Obj.AsJSON, ResultText, ErrorText) And (Pos('Main.pas', ResultText) > 0) And (Pos(Unsaved, ResultText) = 0));
    Obj.Free;
    Obj := Nil;
    Obj := TJSONObject.Create;
    Obj.Add('query', Disk);
    Obj.Add('path', 'Other.pas');
    Obj.Add('max_results', 5);
    Check('a different path searches the disk stand-in', Broker.Execute(Bridge.RunId, 'lazarus_search_in_project',
      Obj.AsJSON, ResultText, ErrorText) And (Pos(Disk, ResultText) > 0) And (Pos(Unsaved, ResultText) = 0));
    Obj.Free;
    Obj := Nil;
    Obj := TJSONObject.Create;
    Obj.Add('query', Unsaved);
    Obj.Add('path', 'Main.pas');
    Check('max_results is required', Not Broker.Execute(Bridge.RunId, 'lazarus_search_in_project', Obj.AsJSON,
      ResultText, ErrorText) And (Pos('max_results', ErrorText) > 0));
  Finally
    Obj.Free;
  End;
  Workspace.AllowInspect := False;
  Workspace.StoredText := BufferText;
  Workspace.DiskText := '';
  Workspace.OpenPath := '';
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

Function ArgumentAt(Const Command: String; Index: Integer): String;
Var
  Data, Args: TJSONData;
Begin
  Result := '';
  Data := GetJSON(Command);
  Try
    Args := Data.FindPath('arguments');
    If (Args Is TJSONArray) And (Index >= 0) And (Index < Args.Count) Then
      Result := Args.Items[Index].AsString;
  Finally
    Data.Free;
  End;
End;

Function ArgumentCount(Const Command: String): Integer;
Var
  Data, Args: TJSONData;
Begin
  Result := -1;
  Data := GetJSON(Command);
  Try
    Args := Data.FindPath('arguments');
    If Args Is TJSONArray Then
      Result := Args.Count;
  Finally
    Data.Free;
  End;
End;

Procedure WriteTextFile(Const Path, Text: String);
Var
  Stream: TFileStream;
Begin
  Stream := TFileStream.Create(Path, fmCreate);
  Try
    If Text <> '' Then
      Stream.WriteBuffer(Text[1], Length(Text));
  Finally
    Stream.Free;
  End;
End;

Function OnlyRequest(Const Names: Array Of String): String;
Var
  Obj: TJSONObject;
  Only: TJSONArray;
  I: Integer;
Begin
  Obj := TJSONObject.Create;
  Only := TJSONArray.Create;
  Try
    Obj.Add('build_job_id', 'job-1');
    Obj.Add('only', Only);
    For I := 0 To High(Names) Do
      Only.Add(Names[I]);
    Result := Obj.AsJSON;
  Finally
    Obj.Free;
  End;
End;

Procedure CheckNamedTests;
Var
  Root, ResultText, ErrorText, Command: String;
  Obj: TJSONObject;
  Args: TJSONArray;
Begin
  Root := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-only-' + IntToStr(GetProcessID);
  ForceDirectories(IncludeTrailingPathDelimiter(Root) + 'Tests');
  WriteTextFile(IncludeTrailingPathDelimiter(Root) + 'Tests' + PathDelim + 'GoodTest.lpr', 'program GoodTest;');
  WriteTextFile(IncludeTrailingPathDelimiter(Root) + 'Tests' + PathDelim + 'OtherTest.lpr', 'program OtherTest;');
  Obj := TJSONObject.Create;
  Args := TJSONArray.Create;
  Try
    Obj.Add('executable', '/usr/bin/instantfpc');
    Obj.Add('workingDirectory', Root);
    Obj.Add('build_job_id', 'job-1');
    Obj.Add('executableFingerprint', 'fingerprint');
    Obj.Add('arguments', Args);
    Args.Add('Tests/RunAssistantTests.pas');
    Args.Add('--lazarus-root');
    Args.Add('/lazarus');
    Workspace.BaseCommand := Obj.AsJSON;
  Finally
    Obj.Free;
  End;
  Workspace.ProjectRoot := Root;
  Workspace.AllowBuild := True;
  Workspace.LaunchCount := 0;
  Workspace.LastCommand := '';
  Bridge.BeginRun(ctsProject);
  Check('valid names are passed as only pairs', Broker.Execute(Bridge.RunId, 'lazarus_start_tests',
    OnlyRequest(['GoodTest', 'OtherTest']), ResultText, ErrorText) And (Workspace.LaunchCount = 1));
  Command := Workspace.LastCommand;
  Check('only pairs follow the configured arguments', (ArgumentCount(Command) = 9) And
    (ArgumentAt(Command, 0) = 'Tests/RunAssistantTests.pas') And (ArgumentAt(Command, 1) = '--lazarus-root') And
    (ArgumentAt(Command, 2) = '/lazarus') And (ArgumentAt(Command, 3) = '--only') And (ArgumentAt(Command, 4) = 'GoodTest') And
    (ArgumentAt(Command, 5) = '--only') And (ArgumentAt(Command, 6) = 'OtherTest') And (ArgumentAt(Command, 7) = '--output-dir'));
  Check('output-dir is a temporary directory', (Pos(IncludeTrailingPathDelimiter(GetTempDir), ArgumentAt(Command, 8)) = 1) And
    DirectoryExists(ArgumentAt(Command, 8)));
  Check('a name with a space is refused', Not Broker.Execute(Bridge.RunId, 'lazarus_start_tests',
    OnlyRequest(['Good Test']), ResultText, ErrorText) And (Workspace.LaunchCount = 1));
  Check('a name with a slash is refused', Not Broker.Execute(Bridge.RunId, 'lazarus_start_tests',
    OnlyRequest(['Good/Test']), ResultText, ErrorText) And (Workspace.LaunchCount = 1));
  Check('a name with a quote is refused', Not Broker.Execute(Bridge.RunId, 'lazarus_start_tests',
    OnlyRequest(['Good"Test']), ResultText, ErrorText) And (Workspace.LaunchCount = 1));
  Check('a name with no lpr file is refused', Not Broker.Execute(Bridge.RunId, 'lazarus_start_tests',
    OnlyRequest(['MissingTest']), ResultText, ErrorText) And (Workspace.LaunchCount = 1));
  Check('without only the command is unchanged', Broker.Execute(Bridge.RunId, 'lazarus_start_tests',
    '{"build_job_id":"job-1"}', ResultText, ErrorText) And (Workspace.LastCommand = Workspace.BaseCommand));
  Workspace.AllowBuild := False;
  Workspace.BaseCommand := '';
  Workspace.ProjectRoot := '';
  DeleteFile(IncludeTrailingPathDelimiter(Root) + 'Tests' + PathDelim + 'GoodTest.lpr');
  DeleteFile(IncludeTrailingPathDelimiter(Root) + 'Tests' + PathDelim + 'OtherTest.lpr');
  RemoveDir(IncludeTrailingPathDelimiter(Root) + 'Tests');
  RemoveDir(ExcludeTrailingPathDelimiter(Root));
End;

Procedure CheckFormComponent;
Var
  ResultText, ErrorText, BeforePas, BeforeLfm: String;
  Args, Props: TJSONObject;
  Calls: Integer;
Begin
  Workspace.PasText :=
    'unit Main;' + LineEnding +
    'type' + LineEnding +
    '  TMainForm = class(TForm)' + LineEnding +
    '  private' + LineEnding +
    '  end;' + LineEnding;
  Workspace.LfmText :=
    'object MainForm: TMainForm' + LineEnding +
    'end' + LineEnding;
  Workspace.FormCalls := 0;
  Args := TJSONObject.Create;
  Props := TJSONObject.Create;
  Try
    Props.Add('Interval', 1000);
    Props.Add('Enabled', True);
    Props.Add('OnTimer', 'ColorTimerTimer');
    Args.Add('path', 'Main.pas');
    Args.Add('name', 'ColorTimer');
    Args.Add('class_name', 'TTimer');
    Args.Add('properties', Props.AsJSON);
    Args.Add('event_method', 'ColorTimerTimer');
    Args.Add('uses_unit', 'ExtCtrls');
    Bridge.BeginRun(ctsProject);
    Check('the broker adds the component to both buffers', Broker.Execute(Bridge.RunId, 'lazarus_ensure_form_component',
      Args.AsJSON, ResultText, ErrorText) And (Workspace.FormCalls = 1));
  Finally
    Props.Free;
    Args.Free;
  End;
  Check('the component is in the pas buffer', Pos('ColorTimer: TTimer', Workspace.PasText) > 0);
  Check('the component is in the lfm buffer', Pos('object ColorTimer: TTimer', Workspace.LfmText) > 0);
  Check('the timer interval is in the lfm buffer', Pos('Interval = 1000', Workspace.LfmText) > 0);
  BeforePas := Workspace.PasText;
  BeforeLfm := Workspace.LfmText;
  Calls := Workspace.FormCalls;
  Bridge.BeginRun(ctsMarkdown);
  Check('a Markdown scope refuses the form tool', Not Broker.Execute(Bridge.RunId, 'lazarus_ensure_form_component',
    '{"path":"Main.pas","name":"OtherTimer","class_name":"TTimer"}', ResultText, ErrorText) And
    (Pos('Build mode', ErrorText) > 0) And (Workspace.FormCalls = Calls));
  Check('a refused form edit leaves both buffers unchanged', (Workspace.PasText = BeforePas) And (Workspace.LfmText = BeforeLfm));
End;

Begin
  Workspace := TMemoryWorkspace.Create;
  Broker := TAssistantToolBroker.Create(Workspace);
  Bridge := TMCPBrokerBridge.Create(Broker);
  Listener := Nil;
  Try
    Workspace.StoredText := BufferText;
    CheckScopes;
    CheckSummaries;
    CheckReplaceInBuffer;
    CheckNoEcho;
    CheckSearch;
    CheckNamedTests;
    CheckFormComponent;
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
