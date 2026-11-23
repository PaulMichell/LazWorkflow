Program AssistantMCPBridgeTest;

{ MCP tool calls from listener threads run on the main thread through a real broker. No claude. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads, BaseUnix,
  {$ENDIF}
  Interfaces, Classes, SysUtils, fpjson, jsonparser, fphttpclient, base64, fpimage, fpwritepng, FileUtil,
  AssistantToolBroker, AssistantClaudeClient, AssistantMCPListener, AssistantMCPProtocol, AssistantImages,
  AssistantMCPBridge, AssistantSearchUtil, AssistantTestSettings, AssistantLfm, AssistantWorkTarget, AssistantBuildJob,
  AssistantConversation, AssistantHarness;

Const
  BufferText = 'unit Main; unsaved IDE contents';
  ReadBody = '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"read_file","arguments":{"path":"Main.pas"}}}';
  WaitMs = 10000;

Type
  TMemoryWorkspace = Class(TAssistantWorkspaceAdapter)
  Public
    Reads: Integer;
    ReadThread: TThreadID;
    StoredText, DiskText, OpenPath: String;
    ReplaceCount, SaveCount, EditorStamp: Integer;
    AllowInspect, AllowChanges, AllowBuild: Boolean;
    ProjectRoot, BaseCommand, LastCommand, LastOptions: String;
    LaunchCount, FormCalls, DeleteCalls, RenameCalls, AddUnitCalls: Integer;
    PasText, LfmText, AddedUnit: String;
    AddedUses: Boolean;
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
    Function TestCommand(Const BuildId, OptionsJSON: String; Out Command, ErrorText: String): Boolean; Override;
    Function StartTests(Const BuildId, ExpectedCommand, OptionsJSON: String; Out ResultText, ErrorText: String): Boolean; Override;
    Function TestStatus(Out ResultText, ErrorText: String): Boolean; Override;
    Function EnsureFormComponent(Const Arguments: String; Out ResultText, ErrorText: String): Boolean; Override;
    Function DeletePath(Const Arguments, ResolvedPath: String; Out ResultText, ErrorText: String): Boolean; Override;
    Function RenamePath(Const Arguments, ResolvedFrom, ResolvedTo: String; Out ResultText, ErrorText: String): Boolean; Override;
    Function AddUnitToProject(Const Arguments, ResolvedPath: String; AddToUses: Boolean; Out ResultText, ErrorText: String): Boolean; Override;
    Function ReadChangeBuffer(Const Path: String; Out CanonicalPath, Text, Stamp, ErrorText: String): Boolean; Override;
    Function ApproveReplace(Const Tool, Path, OldText, NewText: String): Boolean;
  Public
    { A fake run_command job: done after DoneAfterPolls status calls, or never when it is zero. }
    AllowCommands: Boolean;
    CommandStarts, StatusPolls, DoneAfterPolls, CommandCancels: Integer;
    StatusThread: TThreadID;
    Function CanRunCommands: Boolean; Override;
    Function CheckRunCommand(Const Arguments: String; MaxTimeoutSeconds: Integer; Out Command, ErrorText: String): Boolean; Override;
    Function StartRunCommand(Const Arguments, ExpectedCommand: String; MaxTimeoutSeconds: Integer;
      Out ResultText, ErrorText: String): Boolean; Override;
    Function RunCommandStatus(Const JobId: String; Out ResultText, ErrorText: String): Boolean; Override;
    Procedure CancelRunCommand; Override;
  End;

  { Calls the bridge as a listener thread would, so the call is queued to the main thread. }
  TBridgeCallThread = Class(TThread)
  Protected
    Procedure Execute; Override;
  Public
    Tool, Arguments, ResultText, ErrorText: String;
    Succeeded, Done: Boolean;
    Constructor Create(Const NewTool, NewArguments: String);
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

Function TMemoryWorkspace.TestCommand(Const BuildId, OptionsJSON: String; Out Command, ErrorText: String): Boolean;
Begin
  Result := ApplyTestOptions(BaseCommand, ProjectRoot, OptionsJSON, Command, ErrorText);
End;

Function TMemoryWorkspace.StartTests(Const BuildId, ExpectedCommand, OptionsJSON: String; Out ResultText, ErrorText: String): Boolean;
Var
  Command: String;
Begin
  Result := False;
  ResultText := '';
  If Not TestCommand(BuildId, OptionsJSON, Command, ErrorText) Then Exit;
  If Command <> ExpectedCommand Then
    Begin
      ErrorText := 'Test configuration, executable or build changed during approval.';
      Exit;
    End;
  LastCommand := Command;
  LastOptions := OptionsJSON;
  Inc(LaunchCount);
  ResultText := '{"started":true,"job_id":"test-job"}';
  Result := True;
End;

{ Same comparison as TAssistantIDEWorkspace.TestStatus: reapply the options from the start. A different command is stale. }
Function TMemoryWorkspace.TestStatus(Out ResultText, ErrorText: String): Boolean;
Var
  Current, Note: String;
  Stale: Boolean;
  Root: TJSONObject;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  If LastCommand = '' Then
    Begin
      ErrorText := 'No test command has been started.';
      Exit;
    End;
  Stale := Not ApplyTestOptions(BaseCommand, ProjectRoot, LastOptions, Current, Note) Or (Current <> LastCommand);
  Root := TJSONObject.Create;
  Try
    Root.Add('job_id', 'test-job');
    Root.Add('stale', Stale);
    ResultText := Root.AsJSON;
    Result := True;
  Finally
    Root.Free;
  End;
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

Function TMemoryWorkspace.DeletePath(Const Arguments, ResolvedPath: String; Out ResultText, ErrorText: String): Boolean;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Inc(DeleteCalls);
  If Not DeleteFile(ResolvedPath) Then
    Begin
      ErrorText := 'Could not delete the file: ' + ResolvedPath;
      Exit;
    End;
  ResultText := 'Deleted ' + ResolvedPath;
  Result := True;
End;

Function TMemoryWorkspace.RenamePath(Const Arguments, ResolvedFrom, ResolvedTo: String;
  Out ResultText, ErrorText: String): Boolean;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  Inc(RenameCalls);
  If Not RenameFile(ResolvedFrom, ResolvedTo) Then
    Begin
      ErrorText := 'Could not rename the path.';
      Exit;
    End;
  ResultText := 'Renamed ' + ResolvedFrom + ' to ' + ResolvedTo;
  Result := True;
End;

Function TMemoryWorkspace.AddUnitToProject(Const Arguments, ResolvedPath: String; AddToUses: Boolean;
  Out ResultText, ErrorText: String): Boolean;
Begin
  Inc(AddUnitCalls);
  AddedUnit := ResolvedPath;
  AddedUses := AddToUses;
  ResultText := 'Added ' + ResolvedPath;
  ErrorText := '';
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

Function TMemoryWorkspace.CanRunCommands: Boolean;
Begin
  Result := AllowCommands;
End;

Function TMemoryWorkspace.CheckRunCommand(Const Arguments: String; MaxTimeoutSeconds: Integer;
  Out Command, ErrorText: String): Boolean;
Begin
  ErrorText := '';
  Command := '{"checked":' + Arguments + ',"max":' + IntToStr(MaxTimeoutSeconds) + '}';
  Result := Pos('"refuse"', Arguments) = 0;
  If Not Result Then
    ErrorText := 'Refused by the check.';
End;

Function TMemoryWorkspace.StartRunCommand(Const Arguments, ExpectedCommand: String; MaxTimeoutSeconds: Integer;
  Out ResultText, ErrorText: String): Boolean;
Begin
  ErrorText := '';
  Inc(CommandStarts);
  StatusPolls := 0;
  ResultText := '{"started":true,"job_id":"job-' + IntToStr(CommandStarts) + '"}';
  Result := True;
End;

Function TMemoryWorkspace.RunCommandStatus(Const JobId: String; Out ResultText, ErrorText: String): Boolean;
Var
  Finished: Boolean;
Begin
  ErrorText := '';
  Inc(StatusPolls);
  StatusThread := GetCurrentThreadId;
  Finished := (DoneAfterPolls > 0) And (StatusPolls >= DoneAfterPolls);
  If Finished Then
    ResultText := '{"job_id":"' + JobId + '","done":true,"outcome":"exited","exit_code":0,"output":"hello"}'
  Else
    ResultText := '{"job_id":"' + JobId + '","done":false,"outcome":"running","exit_code":0,"output":""}';
  Result := True;
End;

Procedure TMemoryWorkspace.CancelRunCommand;
Begin
  Inc(CommandCancels);
End;

Constructor TBridgeCallThread.Create(Const NewTool, NewArguments: String);
Begin
  Tool := NewTool;
  Arguments := NewArguments;
  ResultText := '';
  ErrorText := '';
  Succeeded := False;
  Done := False;
  FreeOnTerminate := False;
  Inherited Create(False);
End;

Procedure TBridgeCallThread.Execute;
Var
  Images: TMCPToolImages;
Begin
  Succeeded := Bridge.Execute(Tool, Arguments, ResultText, ErrorText, Images);
  Done := True;
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
  Check('chat has no write scope', AssistantWriteScopeForMode(amChat) = awsNone);
  Check('inspect is read-only', AssistantWriteScopeForMode(amInspect) = awsReadOnly);
  Check('document edits markdown', AssistantWriteScopeForMode(amDocument) = awsMarkdown);
  Check('plan edits markdown', AssistantWriteScopeForMode(amPlan) = awsMarkdown);
  Check('build edits the project', AssistantWriteScopeForMode(amBuild) = awsProject);
  Bridge.BeginRun(awsNone);
  Check('a Chat run lists no broker tools', Bridge.ToolsJSON = '[]');
  Bridge.BeginRun(awsReadOnly);
  Check('a read run lists read_file', Pos('"read_file"', Bridge.ToolsJSON) > 0);
  Check('a read run lists no write_file', Pos('"write_file"', Bridge.ToolsJSON) = 0);
  Check('a read run lists no replace_in_file', Pos('"replace_in_file"', Bridge.ToolsJSON) = 0);
  Check('a read run hides the form tool', Pos('ensure_form_component', Bridge.ToolsJSON) = 0);
  Bridge.BeginRun(awsMarkdown);
  Check('a Markdown run lists write_file for documents, not every file',
    (Pos('"write_file"', Bridge.ToolsJSON) > 0) And (Pos('other document files', Bridge.ToolsJSON) > 0));
  Check('a Markdown run lists replace_in_file', Pos('"replace_in_file"', Bridge.ToolsJSON) > 0);
  Bridge.BeginRun(awsProject);
  Check('a project run lists write_file for any file',
    (Pos('"write_file"', Bridge.ToolsJSON) > 0) And (Pos('other document files', Bridge.ToolsJSON) = 0));
  Check('a project run lists replace_in_file', Pos('"replace_in_file"', Bridge.ToolsJSON) > 0);
  Check('a project run lists the form tool', Pos('"ensure_form_component"', Bridge.ToolsJSON) > 0);
  Check('a project run lists delete, rename and add-unit',
    (Pos('"delete_path"', Bridge.ToolsJSON) > 0) And (Pos('"rename_path"', Bridge.ToolsJSON) > 0) And
    (Pos('"add_unit_to_project"', Bridge.ToolsJSON) > 0));
  Check('a project run lists plans and section read',
    (Pos('"list_plans"', Bridge.ToolsJSON) > 0) And (Pos('"get_active_plan"', Bridge.ToolsJSON) > 0) And
    (Pos('"read_markdown_section"', Bridge.ToolsJSON) > 0));
  Check('a project run hides set_active_plan', Pos('set_active_plan', Bridge.ToolsJSON) = 0);
  Bridge.BeginRun(awsMarkdown);
  Check('a Markdown run hides the form tool', Pos('ensure_form_component', Bridge.ToolsJSON) = 0);
  Check('a Markdown run hides delete, rename and add-unit',
    (Pos('delete_path', Bridge.ToolsJSON) = 0) And (Pos('rename_path', Bridge.ToolsJSON) = 0) And
    (Pos('add_unit_to_project', Bridge.ToolsJSON) = 0));
  Check('a Markdown run lists plans, section read and set_active_plan',
    (Pos('"list_plans"', Bridge.ToolsJSON) > 0) And (Pos('"get_active_plan"', Bridge.ToolsJSON) > 0) And
    (Pos('"read_markdown_section"', Bridge.ToolsJSON) > 0) And
    (Pos('"set_active_plan"', Bridge.ToolsJSON) > 0));
  Bridge.BeginRun(awsProject);
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
  Bridge.BeginRun(awsReadOnly);
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
    Broker.Execute(Bridge.RunId, 'read_file', '{"path":"' + Path + '"}', ResultText, ErrorText));
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
  Bridge.BeginRun(awsProject);
  Revision := ReadRevision('Main.pas');
  Workspace.ApprovedOld := '';
  Workspace.ApprovedNew := '';
  Check('a unique match is replaced', Broker.Execute(Bridge.RunId, 'replace_in_file',
    ReplaceArguments('Main.pas', Revision, Secret, Edited, False, False), ResultText, ErrorText));
  NextRevision := JsonField(ResultText, 'revision');
  Check('the new revision is returned', (NextRevision <> '') And (NextRevision <> Revision));
  Check('the reply names the changed lines', JsonField(ResultText, 'lines') = '2-2');
  Check('the reply contains no buffer text', (Pos(Secret, ResultText) = 0) And (Pos(Edited, ResultText) = 0) And
    (Pos(Before, ResultText) = 0) And (Pos(After, ResultText) = 0) And (Pos('"text"', ResultText) = 0));
  Check('the buffer holds the replacement', Workspace.StoredText = After);
  Check('the unique match was one editor edit', Workspace.ReplaceCount = 1);
  Summary := MCPApprovalSummary(Workspace.ApprovedPath, Workspace.ApprovedOld, Workspace.ApprovedNew);
  Check('approval receives the old and new buffer text', (Workspace.ApprovedTool = 'replace_in_file') And
    (Workspace.ApprovedOld = Before) And (Workspace.ApprovedNew = After));
  Check('the approval summary names the changed lines', Pos('lines 2-2 of 3 replaced by 1', Summary) > 0);
  Check('the returned revision accepts the next edit', Broker.Execute(Bridge.RunId, 'replace_in_file',
    ReplaceArguments('Main.pas', NextRevision, Edited, 'EditedAgain', False, False), ResultText, ErrorText) And
    (Workspace.StoredText = 'keep' + LineEnding + 'EditedAgain' + LineEnding + 'tail'));

  Before := Workspace.StoredText;
  Calls := Workspace.ReplaceCount;
  Revision := ReadRevision('Main.pas');
  Check('a missing match fails', Not Broker.Execute(Bridge.RunId, 'replace_in_file',
    ReplaceArguments('Main.pas', Revision, 'missing-token', Edited, False, False), ResultText, ErrorText));
  Check('a missing match leaves the buffer unchanged', (Workspace.StoredText = Before) And (Workspace.ReplaceCount = Calls));

  Workspace.StoredText := 'one' + LineEnding + 'two' + LineEnding + 'one';
  Bridge.BeginRun(awsProject);
  Revision := ReadRevision('Main.pas');
  Calls := Workspace.ReplaceCount;
  Before := Workspace.StoredText;
  Check('two matches without replace_all fail', Not Broker.Execute(Bridge.RunId, 'replace_in_file',
    ReplaceArguments('Main.pas', Revision, 'one', 'ONE', False, False), ResultText, ErrorText));
  Check('two matches leave the buffer unchanged', (Workspace.StoredText = Before) And (Workspace.ReplaceCount = Calls));
  Check('replace_all replaces both', Broker.Execute(Bridge.RunId, 'replace_in_file',
    ReplaceArguments('Main.pas', Revision, 'one', 'ONE', True, True), ResultText, ErrorText));
  Check('both matches were replaced', Workspace.StoredText = 'ONE' + LineEnding + 'two' + LineEnding + 'ONE');
  Check('replace_all was one editor edit', Workspace.ReplaceCount = Calls + 1);
  Check('the replace_all reply contains no buffer text', (Pos('ONE', ResultText) = 0) And (Pos('one', ResultText) = 0));

  Workspace.StoredText := 'keep' + LineEnding + 'only-once' + LineEnding + 'tail';
  Bridge.BeginRun(awsProject);
  Revision := ReadRevision('Main.pas');
  Workspace.StoredText := 'keep' + LineEnding + 'moved-once' + LineEnding + 'tail';
  Calls := Workspace.ReplaceCount;
  Before := Workspace.StoredText;
  Check('a stale revision fails', Not Broker.Execute(Bridge.RunId, 'replace_in_file',
    ReplaceArguments('Main.pas', Revision, 'moved-once', 'changed', False, False), ResultText, ErrorText));
  Check('a stale revision leaves the buffer unchanged', (Workspace.StoredText = Before) And (Workspace.ReplaceCount = Calls));

  Workspace.StoredText := 'keep' + LineEnding + 'edit me' + LineEnding;
  Bridge.BeginRun(awsMarkdown);
  Revision := ReadRevision('Main.pas');
  Calls := Workspace.ReplaceCount;
  Before := Workspace.StoredText;
  Check('the Markdown scope refuses a pas path', Not Broker.Execute(Bridge.RunId, 'replace_in_file',
    ReplaceArguments('Main.pas', Revision, 'edit me', 'edited', False, False), ResultText, ErrorText) And
    (Pos('Markdown', ErrorText) > 0));
  Check('a refused pas path leaves the buffer unchanged', (Workspace.StoredText = Before) And (Workspace.ReplaceCount = Calls));
  Revision := ReadRevision('Notes.md');
  Check('the Markdown scope accepts a markdown path', Broker.Execute(Bridge.RunId, 'replace_in_file',
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
  Bridge.BeginRun(awsProject);
  Check('read_file still returns text by default',
    Broker.Execute(Bridge.RunId, 'read_file', '{"path":"Main.pas"}', ResultText, ErrorText) And
    (Pos(Secret, ResultText) > 0));
  Revision := JsonField(ResultText, 'revision');
  Saves := Workspace.SaveCount;
  Check('write_file applies', Broker.Execute(Bridge.RunId, 'write_file',
    ObjectArguments('Main.pas', Revision, 'text', After, False, False, ''), ResultText, ErrorText));
  Check('write_file reply contains no buffer text', (Pos(Secret, ResultText) = 0) And (Pos(Edited, ResultText) = 0) And
    (Pos(Before, ResultText) = 0) And (Pos(After, ResultText) = 0) And (Pos('"text"', ResultText) = 0));
  Check('write_file names the changed lines', JsonField(ResultText, 'lines') = '2-2');
  Revision := JsonField(ResultText, 'revision');
  Check('save accepts the write_file revision', (Revision <> '') And Broker.Execute(Bridge.RunId, 'save_file',
    ObjectArguments('Main.pas', Revision, '', '', False, False, ''), ResultText, ErrorText) And (Workspace.SaveCount = Saves + 1));

  Workspace.StoredText := Before;
  Workspace.EditorStamp := 1;
  Bridge.BeginRun(awsProject);
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
  Check('prepare the change set', Broker.Execute(Bridge.RunId, 'prepare_changes', PrepareArgs, ResultText, ErrorText));
  Apply := TJSONObject.Create;
  Try
    Apply.Add('change_set_id', JsonPath(ResultText, 'change_set_id'));
    ApplyArgs := Apply.AsJSON;
  Finally
    Apply.Free;
  End;
  Saves := Workspace.SaveCount;
  Check('apply_changes applies', Broker.Execute(Bridge.RunId, 'apply_changes', ApplyArgs, ResultText, ErrorText));
  Check('apply_changes reply contains no buffer text', (Pos(Secret, ResultText) = 0) And (Pos(Edited, ResultText) = 0) And
    (Pos(Before, ResultText) = 0) And (Pos(After, ResultText) = 0));
  Check('apply_changes names the changed lines', JsonPath(ResultText, 'files[0].lines') = '2-2');
  Revision := JsonPath(ResultText, 'files[0].revision');
  Check('save accepts the apply_changes revision', (Revision <> '') And Broker.Execute(Bridge.RunId, 'save_file',
    ObjectArguments('Main.pas', Revision, '', '', False, False, ''), ResultText, ErrorText) And (Workspace.SaveCount = Saves + 1));

  Workspace.StoredText := Before;
  Bridge.BeginRun(awsProject);
  Check('open_buffer can omit the text', Broker.Execute(Bridge.RunId, 'open_buffer',
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
  Check('replace_in_file accepts the open_buffer revision', (Revision <> '') And
    Broker.Execute(Bridge.RunId, 'replace_in_file',
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
  Bridge.BeginRun(awsReadOnly);
  Check('a read run lists search_in_project', Pos('"search_in_project"', Bridge.ToolsJSON) > 0);
  Obj := TJSONObject.Create;
  Try
    Obj.Add('query', Unsaved);
    Obj.Add('path', 'Main.pas');
    Obj.Add('max_results', 1);
    Check('an unsaved buffer match is found', Broker.Execute(Bridge.RunId, 'search_in_project', Obj.AsJSON,
      ResultText, ErrorText) And (Pos(Unsaved + '-one', ResultText) > 0) And (Pos(Disk, ResultText) = 0));
    Check('max_results caps the output', (Pos(Unsaved + '-two', ResultText) = 0) And (Pos('capped at 1', ResultText) > 0));
    Obj.Free;
    Obj := Nil;
    Obj := TJSONObject.Create;
    Obj.Add('query', Unsaved);
    Obj.Add('path', 'Main.pas');
    Obj.Add('max_results', 5);
    Obj.Add('files_only', True);
    Check('files_only returns the path without the line', Broker.Execute(Bridge.RunId, 'search_in_project',
      Obj.AsJSON, ResultText, ErrorText) And (Pos('Main.pas', ResultText) > 0) And (Pos(Unsaved, ResultText) = 0));
    Obj.Free;
    Obj := Nil;
    Obj := TJSONObject.Create;
    Obj.Add('query', Disk);
    Obj.Add('path', 'Other.pas');
    Obj.Add('max_results', 5);
    Check('a different path searches the disk stand-in', Broker.Execute(Bridge.RunId, 'search_in_project',
      Obj.AsJSON, ResultText, ErrorText) And (Pos(Disk, ResultText) > 0) And (Pos(Unsaved, ResultText) = 0));
    Obj.Free;
    Obj := Nil;
    Obj := TJSONObject.Create;
    Obj.Add('query', Unsaved);
    Obj.Add('path', 'Main.pas');
    Check('max_results is required', Not Broker.Execute(Bridge.RunId, 'search_in_project', Obj.AsJSON,
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
  Images: TMCPToolImages;
Begin
  Check('a call on the main thread runs at once',
    Bridge.Execute('read_file', '{"path":"Main.pas"}', ResultText, ErrorText, Images) And
    (Pos(BufferText, ResultText) > 0) And (Length(Images) = 0));
End;

Procedure CheckCancel;
Var
  Client: TClientThread;
  Reads: Integer;
  Started: QWord;
  ResultText, ErrorText: String;
  Images: TMCPToolImages;
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
    Check('Cancel ends the broker run', Not Broker.Execute(Bridge.RunId, 'read_file', '{"path":"Main.pas"}', ResultText, ErrorText));
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
    Not Bridge.Execute('read_file', '{"path":"Main.pas"}', ResultText, ErrorText, Images) And
    (ErrorText = MCPRunCancelledText));
End;

Procedure CheckNextRun;
Var
  Client: TClientThread;
  OldRun: String;
Begin
  OldRun := Bridge.RunId;
  Bridge.BeginRun(awsReadOnly);
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

Function ArgumentIndex(Const Command, Name: String): Integer;
Var
  Data, Args: TJSONData;
  I: Integer;
Begin
  Result := -1;
  Data := GetJSON(Command);
  Try
    Args := Data.FindPath('arguments');
    If Not (Args Is TJSONArray) Then Exit;
    For I := 0 To Args.Count - 1 Do
      If Args.Items[I].AsString = Name Then
        Exit(I);
  Finally
    Data.Free;
  End;
End;

Function OutputDirectory(Const Command: String): String;
Var
  Index: Integer;
Begin
  Index := ArgumentIndex(Command, '--output-dir');
  If Index < 0 Then
    Result := ''
  Else
    Result := ArgumentAt(Command, Index + 1);
End;

Function JsonBoolean(Const Text, Name: String; Out Value: Boolean): Boolean;
Var
  Data, Node: TJSONData;
Begin
  Result := False;
  Value := False;
  Try
    Data := GetJSON(Text);
  Except
    Exit;
  End;
  Try
    Node := Data.FindPath(Name);
    If (Node = Nil) Or (Node.JSONType <> jtBoolean) Then Exit;
    Value := Node.AsBoolean;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function CommandWithScript(Const Root, Script: String): String;
Var
  Obj: TJSONObject;
  Args: TJSONArray;
Begin
  Obj := TJSONObject.Create;
  Args := TJSONArray.Create;
  Try
    Obj.Add('executable', '/usr/bin/instantfpc');
    Obj.Add('workingDirectory', Root);
    Obj.Add('build_job_id', 'job-1');
    Obj.Add('executableFingerprint', 'fingerprint');
    Obj.Add('arguments', Args);
    Args.Add(Script);
    Result := Obj.AsJSON;
  Finally
    Obj.Free;
  End;
End;

Function WithExtraArgument(Const Command, Value: String): String;
Var
  Data, Args: TJSONData;
Begin
  Result := '';
  Data := GetJSON(Command);
  Try
    Args := Data.FindPath('arguments');
    If Args Is TJSONArray Then
      TJSONArray(Args).Add(Value);
    Result := Data.AsJSON;
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

Procedure CheckPathTools;
Var
  Root, Outside, ResultText, ErrorText: String;
  Deletes, Renames, Adds: Integer;
Begin
  Root := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-broker-paths-' + IntToStr(GetProcessID);
  ForceDirectories(Root);
  Outside := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-broker-outside-' + IntToStr(GetProcessID) + '.txt';
  WriteTextFile(Outside, 'outside');
  Check('select the path-tool target', AssistantTarget.SelectFolder(Root, ErrorText));
  Root := AssistantTarget.Root;
  WriteTextFile(Root + 'inside.txt', 'inside');
  WriteTextFile(Root + 'move-me.txt', 'move');
  WriteTextFile(Root + 'UnitOne.pas', 'unit UnitOne;');
  Workspace.DeleteCalls := 0;
  Workspace.RenameCalls := 0;
  Workspace.AddUnitCalls := 0;
  Bridge.BeginRun(awsProject);
  Deletes := Workspace.DeleteCalls;
  Check('delete outside the target is refused', Not Broker.Execute(Bridge.RunId, 'delete_path',
    '{"path":"' + Outside + '"}', ResultText, ErrorText) And (Pos('outside', ErrorText) > 0) And
    (Workspace.DeleteCalls = Deletes) And FileExists(Outside));
  Check('delete inside the target works', Broker.Execute(Bridge.RunId, 'delete_path',
    '{"path":"inside.txt"}', ResultText, ErrorText) And (Workspace.DeleteCalls = Deletes + 1) And
    (Not FileExists(Root + 'inside.txt')));
  Renames := Workspace.RenameCalls;
  Check('rename outside the target is refused', Not Broker.Execute(Bridge.RunId, 'rename_path',
    '{"path":"' + Outside + '","new_path":"stolen.txt"}', ResultText, ErrorText) And (Pos('outside', ErrorText) > 0) And
    (Workspace.RenameCalls = Renames) And FileExists(Outside));
  Check('rename inside the target works', Broker.Execute(Bridge.RunId, 'rename_path',
    '{"path":"move-me.txt","new_path":"moved.txt"}', ResultText, ErrorText) And (Workspace.RenameCalls = Renames + 1) And
    (Not FileExists(Root + 'move-me.txt')) And FileExists(Root + 'moved.txt'));
  Adds := Workspace.AddUnitCalls;
  Check('add-unit outside the target is refused', Not Broker.Execute(Bridge.RunId, 'add_unit_to_project',
    '{"path":"' + Outside + '"}', ResultText, ErrorText) And (Pos('outside', ErrorText) > 0) And
    (Workspace.AddUnitCalls = Adds));
  Check('add-unit inside the target works', Broker.Execute(Bridge.RunId, 'add_unit_to_project',
    '{"path":"UnitOne.pas","add_to_uses":true}', ResultText, ErrorText) And (Workspace.AddUnitCalls = Adds + 1) And
    (Pos('UnitOne.pas', Workspace.AddedUnit) > 0) And Workspace.AddedUses);
  DeleteFile(Outside);
  DeleteFile(Root + 'moved.txt');
  DeleteFile(Root + 'UnitOne.pas');
  RemoveDir(ExcludeTrailingPathDelimiter(Root));
  AssistantTarget.SelectProject;
End;

Procedure WritePng(Const Path: String; Width, Height: Integer);
Var
  Img: TFPMemoryImage;
  Writer: TFPWriterPNG;
  X, Y: Integer;
Begin
  Img := TFPMemoryImage.Create(Width, Height);
  Writer := TFPWriterPNG.Create;
  Try
    For Y := 0 To Height - 1 Do
      For X := 0 To Width - 1 Do
        Img.Colors[X, Y] := FPColor((X * 37) And $FFFF, (Y * 101) And $FFFF, ((X + Y) * 53) And $FFFF);
    Img.SaveToFile(Path, Writer);
  Finally
    Writer.Free;
    Img.Free;
  End;
End;

{ The pixel size of a returned upload copy, or 0 x 0 when the data is not a still image. }
Procedure MeasureReturned(Const Image: TMCPToolImage; Out Width, Height: Integer);
Var
  Decoded: String;
  Data: TBytes;
  Mime: String;
Begin
  Width := 0;
  Height := 0;
  Decoded := DecodeStringBase64(Image.Data);
  SetLength(Data, Length(Decoded));
  If Decoded <> '' Then
    Move(Decoded[1], Data[0], Length(Decoded));
  If Not MeasureStillImage(Data, Mime, Width, Height) Then
    Begin
      Width := 0;
      Height := 0;
    End;
End;

Procedure CheckReadImage;
Var
  Root, Outside, ResultText, ErrorText, Json: String;
  Images: TMCPToolImages;
  Stream: TFileStream;
  Width, Height: Integer;
Begin
  Workspace.AllowInspect := True;
  Bridge.BeginRun(awsNone);
  Check('a Chat run does not list read_image', Pos('read_image', Bridge.ToolsJSON) = 0);
  Check('a Chat run refuses read_image', Not Broker.Execute(Bridge.RunId, 'read_image', '{"path":"dot.png"}',
    ResultText, ErrorText, Images) And (Length(Images) = 0));
  Bridge.BeginRun(awsReadOnly);
  Check('a read run lists read_image', Pos('"read_image"', Bridge.ToolsJSON) > 0);
  Bridge.BeginRun(awsMarkdown);
  Check('a Markdown run lists read_image', Pos('"read_image"', Bridge.ToolsJSON) > 0);
  Bridge.BeginRun(awsProject);
  Check('a project run lists read_image', Pos('"read_image"', Bridge.ToolsJSON) > 0);

  Root := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-broker-image-' + IntToStr(GetProcessID);
  ForceDirectories(Root);
  Outside := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-broker-image-outside-' + IntToStr(GetProcessID) + '.png';
  Check('select the read_image target', AssistantTarget.SelectFolder(Root, ErrorText));
  Root := AssistantTarget.Root;
  WritePng(Root + 'dot.png', 4, 3);
  WritePng(Outside, 4, 3);
  WritePng(Root + 'wide.png', 3000, 4);
  Bridge.BeginRun(awsReadOnly);

  Check('read_image returns one picture', Broker.Execute(Bridge.RunId, 'read_image', '{"path":"dot.png"}',
    ResultText, ErrorText, Images) And (Length(Images) = 1));
  Check('the picture is a PNG upload copy', (Images[0].MimeType = 'image/png') And (Images[0].Data <> ''));
  MeasureReturned(Images[0], Width, Height);
  Check('the returned data is the picture', (Width = 4) And (Height = 3));
  Check('the text line names the picture and its size', (Pos('dot.png', ResultText) = 1) And (Pos('4 x 3', ResultText) > 0));
  Json := Broker.ReadImagesJson(ResultText);
  Check('the run keeps the picture for the trace', (Json <> '') And (Pos('dot.png', Json) > 0));
  Check('a result naming no stored picture shows none', Broker.ReadImagesJson('Unit Main;') = '');

  Check('a path outside the project is refused', Not Broker.Execute(Bridge.RunId, 'read_image',
    '{"path":"' + StringToJSONString(Outside) + '"}', ResultText, ErrorText, Images) And (ErrorText <> '') And
    (Length(Images) = 0));
  Check('a parent path is refused', Not Broker.Execute(Bridge.RunId, 'read_image',
    '{"path":"../' + ExtractFileName(Outside) + '"}', ResultText, ErrorText, Images) And (Length(Images) = 0));
  Check('an empty path is refused', Not Broker.Execute(Bridge.RunId, 'read_image', '{"path":""}',
    ResultText, ErrorText, Images) And (Length(Images) = 0));
  Check('a missing file is refused', Not Broker.Execute(Bridge.RunId, 'read_image', '{"path":"none.png"}',
    ResultText, ErrorText, Images) And (Length(Images) = 0));
  {$IFDEF UNIX}
  Check('make a link that leaves the project', FpSymlink(PChar(Outside), PChar(Root + 'link.png')) = 0);
  Check('a symbolic link that leaves the project is refused', Not Broker.Execute(Bridge.RunId, 'read_image',
    '{"path":"link.png"}', ResultText, ErrorText, Images) And (Length(Images) = 0) And
    ((Pos('symbolic link', LowerCase(ErrorText)) > 0) Or (Pos('outside the active project', LowerCase(ErrorText)) > 0)));
  {$ENDIF}

  Stream := TFileStream.Create(Root + 'huge.png', fmCreate);
  Try
    Stream.Size := AssistantImageMaxFileBytes + 1;
  Finally
    Stream.Free;
  End;
  Check('a file over 8 MiB is refused', Not Broker.Execute(Bridge.RunId, 'read_image', '{"path":"huge.png"}',
    ResultText, ErrorText, Images) And (ErrorText <> '') And (Length(Images) = 0));

  Check('a picture wider than the upload ceiling is read', Broker.Execute(Bridge.RunId, 'read_image',
    '{"path":"wide.png"}', ResultText, ErrorText, Images) And (Length(Images) = 1));
  MeasureReturned(Images[0], Width, Height);
  Check('the returned copy is at most 2048 pixels a side', (Width > 0) And (Width <= AssistantImageUploadMaxSide) And
    (Height <= AssistantImageUploadMaxSide));
  Check('the returned copy is at most 4 MiB', Length(DecodeStringBase64(Images[0].Data)) <= AssistantImageUploadMaxBytes);

  Check('the bridge hands the picture back', Bridge.Execute('read_image', '{"path":"dot.png"}', ResultText,
    ErrorText, Images) And (Length(Images) = 1) And (Images[0].MimeType = 'image/png'));
  Bridge.BeginRun(awsReadOnly);
  Check('a new run forgets the last run''s pictures', Broker.ReadImagesJson(ResultText) = '');

  DeleteFile(Outside);
  DeleteDirectory(ExcludeTrailingPathDelimiter(Root), False);
  AssistantTarget.SelectProject;
  Workspace.AllowInspect := False;
End;

Procedure CheckMarkdownSection;
Var
  Root, PlanPath, ResultText, ErrorText, Section: String;
  Args: TJSONObject;
Begin
  Root := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-broker-section-' + IntToStr(GetProcessID) + PathDelim;
  ForceDirectories(Root + 'Documents');
  PlanPath := Root + 'Documents' + PathDelim + 'Plan.md';
  WriteTextFile(PlanPath,
    '# Title' + LineEnding +
    LineEnding +
    '## 1. First package' + LineEnding +
    'package intro' + LineEnding +
    LineEnding +
    '### 1.1 Alpha' + LineEnding +
    'Status: not started' + LineEnding +
    'alpha only' + LineEnding +
    LineEnding +
    '### 1.2 Beta' + LineEnding +
    'Status: not started' + LineEnding +
    'beta only' + LineEnding +
    LineEnding +
    '## 2. Second package' + LineEnding +
    'second only' + LineEnding);
  Check('select the section-read target', AssistantTarget.SelectFolder(Root, ErrorText));
  Bridge.BeginRun(awsProject);
  Args := TJSONObject.Create;
  Try
    Args.Add('path', 'Documents/Plan.md');
    Args.Add('heading', '### 1.1');
    Check('a ### heading returns one item', Broker.Execute(Bridge.RunId, 'read_markdown_section', Args.AsJSON,
      ResultText, ErrorText));
    Section := ResultText;
  Finally
    Args.Free;
  End;
  Check('the item block contains its own heading and body', (Pos('### 1.1 Alpha', Section) > 0) And (Pos('alpha only', Section) > 0));
  Check('the item block is exactly one ### section', (Pos('### 1.2', Section) = 0) And (Pos('beta only', Section) = 0) And
    (Pos('### ', Copy(Section, Pos('### ', Section) + 4, MaxInt)) = 0));
  Args := TJSONObject.Create;
  Try
    Args.Add('path', 'Documents/Plan.md');
    Args.Add('heading', '### 9.9');
    Check('a missing heading is an error', Not Broker.Execute(Bridge.RunId, 'read_markdown_section', Args.AsJSON,
      ResultText, ErrorText) And (Pos('not found', ErrorText) > 0));
  Finally
    Args.Free;
  End;
  Args := TJSONObject.Create;
  Try
    Args.Add('path', 'Documents/Plan.md');
    Args.Add('heading', '## 1. First package');
    Check('a ## heading returns the whole package', Broker.Execute(Bridge.RunId, 'read_markdown_section',
      Args.AsJSON, ResultText, ErrorText));
    Section := ResultText;
  Finally
    Args.Free;
  End;
  Check('the package contains both items', (Pos('### 1.1 Alpha', Section) > 0) And (Pos('### 1.2 Beta', Section) > 0) And
    (Pos('alpha only', Section) > 0) And (Pos('beta only', Section) > 0) And (Pos('package intro', Section) > 0));
  Check('the package stops before the next ## heading', (Pos('## 2. Second package', Section) = 0) And
    (Pos('second only', Section) = 0));
  Check('Build refuses set_active_plan', Not Broker.Execute(Bridge.RunId, 'set_active_plan',
    '{"path":"Documents/Plan.md"}', ResultText, ErrorText) And (Pos('Plan mode', ErrorText) > 0));
  DeleteFile(PlanPath);
  RemoveDir(Root + 'Documents');
  RemoveDir(ExcludeTrailingPathDelimiter(Root));
  AssistantTarget.SelectProject;
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
  Root, ResultText, ErrorText, Command, Saved, DefineDir, HeapDir, ValDir, DebugDir, TraceDir, GuiDir, GuiOnlyDir: String;
  Obj: TJSONObject;
  Args: TJSONArray;
  Launches: Integer;
  Stale: Boolean;
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
  Workspace.LastOptions := '';
  Bridge.BeginRun(awsProject);
  Check('valid names are passed as only pairs', Broker.Execute(Bridge.RunId, 'start_tests',
    OnlyRequest(['GoodTest', 'OtherTest']), ResultText, ErrorText) And (Workspace.LaunchCount = 1));
  Command := Workspace.LastCommand;
  Check('only pairs follow the configured arguments', (ArgumentCount(Command) = 9) And
    (ArgumentAt(Command, 0) = 'Tests/RunAssistantTests.pas') And (ArgumentAt(Command, 1) = '--lazarus-root') And
    (ArgumentAt(Command, 2) = '/lazarus') And (ArgumentAt(Command, 3) = '--only') And (ArgumentAt(Command, 4) = 'GoodTest') And
    (ArgumentAt(Command, 5) = '--only') And (ArgumentAt(Command, 6) = 'OtherTest') And (ArgumentAt(Command, 7) = '--output-dir'));
  Check('output-dir is under Temporary in the project',
    (Pos(IncludeTrailingPathDelimiter(Root) + 'Temporary' + PathDelim + 'Tests-', ArgumentAt(Command, 8)) = 1) And
    DirectoryExists(ArgumentAt(Command, 8)));
  Check('the project Temporary folder ignores its own contents',
    FileExists(IncludeTrailingPathDelimiter(Root) + 'Temporary' + PathDelim + '.gitignore'));
  Check('a name with a space is refused', Not Broker.Execute(Bridge.RunId, 'start_tests',
    OnlyRequest(['Good Test']), ResultText, ErrorText) And (Workspace.LaunchCount = 1));
  Check('a name with a slash is refused', Not Broker.Execute(Bridge.RunId, 'start_tests',
    OnlyRequest(['Good/Test']), ResultText, ErrorText) And (Workspace.LaunchCount = 1));
  Check('a name with a quote is refused', Not Broker.Execute(Bridge.RunId, 'start_tests',
    OnlyRequest(['Good"Test']), ResultText, ErrorText) And (Workspace.LaunchCount = 1));
  Check('a name with no lpr file is refused', Not Broker.Execute(Bridge.RunId, 'start_tests',
    OnlyRequest(['MissingTest']), ResultText, ErrorText) And (Workspace.LaunchCount = 1));
  Check('without only the command is unchanged', Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1"}', ResultText, ErrorText) And (Workspace.LastCommand = Workspace.BaseCommand));
  Launches := Workspace.LaunchCount;
  Check('defines are passed as --define', Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","defines":["DEBUG"]}', ResultText, ErrorText) And (Workspace.LaunchCount = Launches + 1));
  Command := Workspace.LastCommand;
  Check('define arguments follow the configured arguments', (ArgumentCount(Command) = 7) And
    (ArgumentAt(Command, 3) = '--define') And (ArgumentAt(Command, 4) = 'DEBUG') And (ArgumentAt(Command, 5) = '--output-dir') And
    (Pos(IncludeTrailingPathDelimiter(Root) + 'Temporary' + PathDelim, ArgumentAt(Command, 6)) = 1));
  DefineDir := ArgumentAt(Command, 6);
  Check('heaptrc is passed with only', Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","only":["GoodTest"],"memory_check":"heaptrc"}', ResultText, ErrorText) And
    (Workspace.LaunchCount = Launches + 2));
  Command := Workspace.LastCommand;
  Check('heaptrc follows the only pair', (ArgumentCount(Command) = 8) And (ArgumentAt(Command, 3) = '--only') And
    (ArgumentAt(Command, 4) = 'GoodTest') And (ArgumentAt(Command, 5) = '--heaptrc') And (ArgumentAt(Command, 6) = '--output-dir'));
  HeapDir := ArgumentAt(Command, 7);
  Check('valgrind with the same only uses another output directory', Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","only":["GoodTest"],"memory_check":"valgrind"}', ResultText, ErrorText));
  ValDir := OutputDirectory(Workspace.LastCommand);
  Check('memory-check modes do not share an output directory', (HeapDir <> ValDir) And (Pos('-heaptrc-', HeapDir) > 0) And
    (Pos('-valgrind-', ValDir) > 0) And DirectoryExists(HeapDir) And DirectoryExists(ValDir));
  Check('gui with only is passed as --gui', Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","only":["GoodTest"],"gui":true}', ResultText, ErrorText) And
    (Workspace.LaunchCount = Launches + 4));
  Command := Workspace.LastCommand;
  Check('gui follows the only pair', (ArgumentCount(Command) = 8) And (ArgumentAt(Command, 3) = '--only') And
    (ArgumentAt(Command, 4) = 'GoodTest') And (ArgumentAt(Command, 5) = '--gui') And (ArgumentAt(Command, 6) = '--output-dir'));
  GuiOnlyDir := ArgumentAt(Command, 7);
  Check('a gui run uses its own output directory', (Pos('-gui-', GuiOnlyDir) > 0) And DirectoryExists(GuiOnlyDir));
  Check('gui alone is passed', Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","gui":true}', ResultText, ErrorText) And (ArgumentCount(Workspace.LastCommand) = 6) And
    (ArgumentAt(Workspace.LastCommand, 3) = '--gui'));
  GuiDir := OutputDirectory(Workspace.LastCommand);
  Check('gui false leaves the command unchanged', Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","gui":false}', ResultText, ErrorText) And (Workspace.LastCommand = Workspace.BaseCommand));
  Launches := Workspace.LaunchCount;
  Check('gui with a memory check is refused', Not Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","only":["GoodTest"],"memory_check":"heaptrc","gui":true}', ResultText, ErrorText) And
    (Pos('gui cannot be used with memory_check heaptrc', ErrorText) > 0) And (Workspace.LaunchCount = Launches));
  Check('a non-boolean gui is refused', Not Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","gui":"yes"}', ResultText, ErrorText) And
    (Pos('gui must be true or false', ErrorText) > 0) And (Workspace.LaunchCount = Launches));
  Check('a define with only is passed', Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","only":["GoodTest"],"defines":["DEBUG"]}', ResultText, ErrorText));
  DebugDir := OutputDirectory(Workspace.LastCommand);
  Check('another define with the same only uses another output directory', Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","only":["GoodTest"],"defines":["TRACE"]}', ResultText, ErrorText));
  TraceDir := OutputDirectory(Workspace.LastCommand);
  Check('define sets do not share an output directory', (DebugDir <> TraceDir) And (Pos('-dDEBUG-', DebugDir) > 0) And
    (Pos('-dTRACE-', TraceDir) > 0));
  Check('the same options stay current', Broker.Execute(Bridge.RunId, 'test_status', '{"job_id":"test-job"}',
    ResultText, ErrorText) And JsonBoolean(ResultText, 'stale', Stale) And Not Stale);
  Saved := Workspace.BaseCommand;
  Workspace.BaseCommand := WithExtraArgument(Saved, '--marker');
  Check('reapplying options after a command change is stale', Broker.Execute(Bridge.RunId, 'test_status',
    '{"job_id":"test-job"}', ResultText, ErrorText) And JsonBoolean(ResultText, 'stale', Stale) And Stale);
  Workspace.BaseCommand := Saved;
  Launches := Workspace.LaunchCount;
  Check('valgrind without only is refused', Not Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","memory_check":"valgrind"}', ResultText, ErrorText) And
    (Pos('needs at least one only name', ErrorText) > 0) And (Workspace.LaunchCount = Launches));
  Check('a bad define name is refused', Not Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","defines":["bad-name"]}', ResultText, ErrorText) And
    (Pos('Define name must match', ErrorText) > 0) And (Workspace.LaunchCount = Launches));
  Check('more than 8 defines are refused', Not Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","defines":["A","B","C","D","E","F","G","H","I"]}', ResultText, ErrorText) And
    (Pos('at most 8', ErrorText) > 0) And (Workspace.LaunchCount = Launches));
  Check('an unknown memory check is refused', Not Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","memory_check":"asan"}', ResultText, ErrorText) And
    (Pos('memory_check must be', ErrorText) > 0) And (Workspace.LaunchCount = Launches));
  Workspace.BaseCommand := CommandWithScript(Root, 'echo');
  Check('only on another command is refused', Not Broker.Execute(Bridge.RunId, 'start_tests',
    OnlyRequest(['GoodTest']), ResultText, ErrorText) And
    (Pos('applies only when the configured command is Tests/RunAssistantTests.pas', ErrorText) > 0) And
    (Workspace.LaunchCount = Launches));
  Check('defines on another command are refused', Not Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","defines":["DEBUG"]}', ResultText, ErrorText) And
    (Pos('applies only when the configured command is Tests/RunAssistantTests.pas', ErrorText) > 0) And
    (Workspace.LaunchCount = Launches));
  Check('heaptrc on another command is refused', Not Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","only":["GoodTest"],"memory_check":"heaptrc"}', ResultText, ErrorText) And
    (Pos('applies only when the configured command is Tests/RunAssistantTests.pas', ErrorText) > 0) And
    (Workspace.LaunchCount = Launches));
  Check('gui on another command is refused', Not Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","gui":true}', ResultText, ErrorText) And
    (Pos('gui applies only when the configured command is Tests/RunAssistantTests.pas', ErrorText) > 0) And
    (Workspace.LaunchCount = Launches));
  Workspace.BaseCommand := Saved;
  Check('memory_check none leaves the command unchanged', Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","memory_check":"none"}', ResultText, ErrorText) And (Workspace.LastCommand = Workspace.BaseCommand));
  Check('empty defines leave the command unchanged', Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","defines":[]}', ResultText, ErrorText) And (Workspace.LastCommand = Workspace.BaseCommand));
  Check('an empty only list leaves the command unchanged', Broker.Execute(Bridge.RunId, 'start_tests',
    '{"build_job_id":"job-1","only":[]}', ResultText, ErrorText) And (Workspace.LastCommand = Workspace.BaseCommand));
  RemoveDir(DefineDir);
  RemoveDir(HeapDir);
  RemoveDir(ValDir);
  RemoveDir(DebugDir);
  RemoveDir(TraceDir);
  RemoveDir(GuiOnlyDir);
  RemoveDir(GuiDir);
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
    Bridge.BeginRun(awsProject);
    Check('the broker adds the component to both buffers', Broker.Execute(Bridge.RunId, 'ensure_form_component',
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
  Bridge.BeginRun(awsMarkdown);
  Check('a Markdown scope refuses the form tool', Not Broker.Execute(Bridge.RunId, 'ensure_form_component',
    '{"path":"Main.pas","name":"OtherTimer","class_name":"TTimer"}', ResultText, ErrorText) And
    (Pos('Build mode', ErrorText) > 0) And (Workspace.FormCalls = Calls));
  Check('a refused form edit leaves both buffers unchanged', (Workspace.PasText = BeforePas) And (Workspace.LfmText = BeforeLfm));
End;

Function WaitForCall(Call: TBridgeCallThread): Boolean;
Var
  Started: QWord;
Begin
  Started := GetTickCount64;
  While Not Call.Done And (GetTickCount64 - Started < WaitMs) Do
    CheckSynchronize(10);
  Result := Call.Done;
End;

{ Grok's todo_write through the broker: Plan and Build only, the harness list, and a new run starts empty. }
Procedure CheckTodoWrite;
Const
  Two = '{"todos":[{"id":"read","content":"Read the unit","status":"in_progress"},' +
    '{"id":"fix","content":"Fix the call"}]}';
Var
  ResultText, ErrorText: String;
  Images: TMCPToolImages;
Begin
  Bridge.BeginRun(awsReadOnly);
  Check('a read run hides todo_write', Pos('todo_write', Bridge.ToolsJSON) = 0);
  Check('a read run refuses todo_write',
    Not Bridge.Execute('todo_write', Two, ResultText, ErrorText, Images) And
    (ErrorText = 'todo_write requires Plan or Build mode.'));
  Bridge.BeginRun(awsMarkdown, amDocument);
  Check('a Document run hides todo_write', Pos('todo_write', Bridge.ToolsJSON) = 0);
  Check('a Document run refuses todo_write',
    Not Bridge.Execute('todo_write', Two, ResultText, ErrorText, Images) And
    (ErrorText = 'todo_write requires Plan or Build mode.'));
  Bridge.BeginRun(awsMarkdown, amPlan);
  Check('a Plan run lists todo_write', Pos('"todo_write"', Bridge.ToolsJSON) > 0);
  Bridge.BeginRun(awsProject);
  Check('a project run lists todo_write with its statuses',
    (Pos('"todo_write"', Bridge.ToolsJSON) > 0) And
    (Pos('"enum":["pending","in_progress","completed","cancelled"]', Bridge.ToolsJSON) > 0));
  Check('todo_write returns the whole list',
    Bridge.Execute('todo_write', Two, ResultText, ErrorText, Images) And
    (Pos('- [>] read: Read the unit (in_progress)', ResultText) > 0) And
    (Pos('- [ ] fix: Fix the call (pending)', ResultText) > 0));
  Check('a merge updates one item by id and keeps the other',
    Bridge.Execute('todo_write', '{"merge":true,"todos":[{"id":"read","status":"completed"}]}',
    ResultText, ErrorText, Images) And
    (Pos('- [x] read: Read the unit (completed)', ResultText) > 0) And
    (Pos('- [ ] fix: Fix the call (pending)', ResultText) > 0));
  Check('todo_write without todos is refused',
    Not Bridge.Execute('todo_write', '{}', ResultText, ErrorText, Images) And
    (ErrorText = 'todo_write requires a todos array.'));
  Check('the list is the one Grok''s todo_write keeps', WorkflowAssistantHarness.TodoCount = 2);
  Bridge.BeginRun(awsProject);
  Check('a new run starts with no checklist', WorkflowAssistantHarness.TodoCount = 0);
End;

Procedure CheckCommands;
Const
  Echo = '{"program":"echo","arguments":["hello"]}';
Var
  Call: TBridgeCallThread;
  Started: QWord;
  ResultText, ErrorText: String;
  Images: TMCPToolImages;
  Cancels: Integer;
Begin
  Workspace.AllowCommands := True;
  Try
    Bridge.BeginRun(awsReadOnly);
    Check('a read run hides run_command', Pos('run_command', Bridge.ToolsJSON) = 0);
    Check('a read run refuses run_command',
      Not Bridge.Execute('run_command', Echo, ResultText, ErrorText, Images) And
      (ErrorText = 'Running a command requires Build mode.'));
    Bridge.BeginRun(awsMarkdown);
    Check('a Markdown run hides run_command', Pos('run_command', Bridge.ToolsJSON) = 0);
    Bridge.BeginRun(awsProject);
    Check('a project run lists run_command and command_status',
      (Pos('"run_command"', Bridge.ToolsJSON) > 0) And (Pos('"command_status"', Bridge.ToolsJSON) > 0));
    Check('run_command states the broker''s timeout ceiling',
      Pos('"maximum":' + IntToStr(BrokerCommandMaxSeconds), Bridge.ToolsJSON) > 0);
    Check('run_project and the open tools stay hidden when the workspace has none',
      (Pos('run_project', Bridge.ToolsJSON) = 0) And (Pos('open_file', Bridge.ToolsJSON) = 0));

    Broker.OnApproval := @Workspace.ApproveReplace;
    Workspace.DoneAfterPolls := 3;
    Check('a main-thread run_command returns the started job',
      Bridge.Execute('run_command', Echo, ResultText, ErrorText, Images) And
      (Pos('"job_id":"job-1"', ResultText) > 0));
    Check('the approval names the checked command and its ceiling',
      (Workspace.ApprovedTool = 'run_command') And (Workspace.ApprovedPath = '') And
      (Pos('"checked":', Workspace.ApprovedNew) > 0) And
      (Pos('"max":' + IntToStr(BrokerCommandMaxSeconds), Workspace.ApprovedNew) > 0));
    Check('a refused check starts nothing',
      Not Bridge.Execute('run_command', '{"program":"refuse"}', ResultText, ErrorText, Images) And
      (ErrorText = 'Refused by the check.') And (Workspace.CommandStarts = 1));
    Check('command_status needs a job_id',
      Not Bridge.Execute('command_status', '{}', ResultText, ErrorText, Images) And
      (ErrorText = 'job_id must be a nonempty string.'));

    Call := TBridgeCallThread.Create('run_command', Echo);
    Try
      Check('a listener-thread run_command returns when the program ends', WaitForCall(Call) And Call.Succeeded);
      Check('it returns the final status with the output',
        (Pos('"done":true', Call.ResultText) > 0) And (Pos('"output":"hello"', Call.ResultText) > 0));
      Check('it polled command_status until the job was done', Workspace.StatusPolls = 3);
      Check('command_status ran on the main thread', Workspace.StatusThread = MainThreadID);
      Check('no call is left waiting after run_command', Bridge.PendingCount = 0);
    Finally
      Call.WaitFor;
      Call.Free;
    End;

    Workspace.DoneAfterPolls := 0;
    Call := TBridgeCallThread.Create('run_command', Echo);
    Try
      Started := GetTickCount64;
      While (Workspace.StatusPolls < 2) And (GetTickCount64 - Started < WaitMs) Do
        CheckSynchronize(10);
      Check('a running command keeps the call open', (Workspace.StatusPolls >= 2) And Not Call.Done);
      Cancels := Workspace.CommandCancels;
      Bridge.Cancel;
      Check('Cancel ends a waiting run_command with the cancel error',
        WaitForCall(Call) And Not Call.Succeeded And (Call.ErrorText = MCPRunCancelledText));
      Check('Cancel stops the command', Workspace.CommandCancels > Cancels);
    Finally
      Call.WaitFor;
      Call.Free;
    End;
  Finally
    Broker.OnApproval := Nil;
    Workspace.AllowCommands := False;
    CheckSynchronize(0);
  End;
End;

Function WaitForJob(Const Job: IAssistantBuildJob): TBuildJobSnapshot;
Var
  Started: QWord;
Begin
  Started := GetTickCount64;
  Result := Job.Snapshot;
  While Not Result.Done And (GetTickCount64 - Started < WaitMs) Do
    Begin
      Sleep(20);
      Result := Job.Snapshot;
    End;
End;

Procedure CheckCommandJob;
Var
  Arguments: TStringList;
  Job: IAssistantBuildJob;
  Value: TBuildJobSnapshot;
  Status: String;
Begin
  Arguments := TStringList.Create;
  Try
    Arguments.Add('hello');
    Arguments.Add('world');
    Job := StartAssistantCommand('/bin/echo', GetTempDir(False), Arguments, 10000);
    Value := WaitForJob(Job);
    Status := AssistantCommandStatusJSON(Value);
    Check('a command job finishes', Value.Done And (Value.Kind = 'command'));
    Check('a command job reports it exited with code 0',
      (JsonPath(Status, 'outcome') = 'exited') And (JsonPath(Status, 'exit_code') = '0'));
    Check('a command job returns its output', Pos('hello world', JsonPath(Status, 'output')) > 0);
    Check('a command job names the program', JsonPath(Status, 'command.executable') = '/bin/echo');

    Arguments.Clear;
    Arguments.Add('5');
    Job := StartAssistantCommand('/bin/sleep', GetTempDir(False), Arguments, 200);
    Value := WaitForJob(Job);
    Status := AssistantCommandStatusJSON(Value);
    Check('a command past its timeout fails as timed out',
      Value.Done And (JsonPath(Status, 'outcome') = 'failed') And (JsonPath(Status, 'error') = 'The command timed out.'));

    Job := StartAssistantCommand('/bin/sleep', GetTempDir(False), Arguments, 10000);
    Sleep(100);
    Job.Cancel;
    Value := WaitForJob(Job);
    Check('a cancelled command job reports cancelled',
      Value.Done And (JsonPath(AssistantCommandStatusJSON(Value), 'outcome') = 'cancelled'));
    Check('a running command job reports running',
      JsonPath(AssistantCommandStatusJSON(Default(TBuildJobSnapshot)), 'outcome') = 'running');
  Finally
    Arguments.Free;
  End;
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
    CheckPathTools;
    CheckReadImage;
    CheckMarkdownSection;
    CheckTodoWrite;
    CheckCommands;
    CheckCommandJob;
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
