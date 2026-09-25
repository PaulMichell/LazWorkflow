Unit AssistantIDEWorkspace;

{ Main-thread adapter for the shared tool broker. Project inspection prefers
  live buffers; opening tabs and saving content are separate explicit tools. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, AssistantToolBroker, AssistantBuildJob;

Type
  TAssistantIDEWorkspace = Class(TAssistantWorkspaceAdapter)
  Private
    FBuild, FTests: IAssistantBuildJob;
    FTestBuildId, FTestCommand, FTestExecutable: String;
    FBuildInputs, FBuildRoots: TBuildInputs;
    FDependencyEvidence: String;
    FDefineStep: Integer;
    FBuildGeneration: QWord;
    FBuildIdentity, FBuildMode: String;
    Function EditorAffectsBuild(Editor: TObject): Boolean;
  Protected
    Function BuildExecutable: String; Virtual;
  Public
    Destructor Destroy; Override;
    Function IsMarkdownPath(Const Path: String): Boolean; Override;
    Function CanInspectFiles: Boolean; Override;
    Function CanChangeSets: Boolean; Override;
    Function ReadChangeBuffer(Const Path: String; Out CanonicalPath, Text, Stamp, ErrorText: String): Boolean; Override;
    Function ReadFile(Const Arguments: String; Out ResultText, ErrorText: String): Boolean; Override;
    Function ListDirectory(Const Arguments: String; Out ResultText, ErrorText: String): Boolean; Override;
    Function OpenBuffer(Const Path: String; Out ErrorText: String): Boolean; Override;
    Function CanCreateFiles: Boolean; Override;
    Function CheckNewFile(Const Path: String; Out CanonicalPath, ErrorText: String): Boolean; Override;
    Function CreateFile(Const Path, Text: String; Out ResultText, ErrorText: String): Boolean; Override;
    Function CanFindDeclaration: Boolean; Override;
    Function CanInspectSymbols: Boolean; Override;
    Function CanPreviewRename: Boolean; Override;
    Function PreviewLocalRename(Const Path: String; Line, Column: Integer; Const NewName: String;
      Out NewText, PreviewText, ErrorText: String): Boolean; Override;
    Function SymbolContext(Const Path: String; Line, Column: Integer; Out ResultText, ErrorText: String): Boolean; Override;
    Function FindReferences(Const Path: String; Line, Column: Integer; SearchPaths: TStrings; MaxResults: Integer; Out ResultText, ErrorText: String): Boolean; Override;
    Function FindDeclaration(Const Path: String; Line, Column: Integer; Out ResultText, ErrorText: String): Boolean; Override;
    Function CanTest: Boolean; Override;
    Function TestCommand(Const BuildId: String; Out Command, ErrorText: String): Boolean; Override;
    Function StartTests(Const BuildId, ExpectedCommand: String; Out ResultText, ErrorText: String): Boolean; Override;
    Function TestStatus(Out ResultText, ErrorText: String): Boolean; Override;
    Function CanGit: Boolean; Override;
    Function RunGit(Const Arguments: String; Out ResultText, ErrorText: String): Boolean; Override;
    Function CanBuild: Boolean; Override;
    Function StartBuild(Out ResultText, ErrorText: String): Boolean; Override;
    Function BuildStatus(Out ResultText, ErrorText: String): Boolean; Override;
    Procedure CancelBuild; Override;
    Function Identity: String; Override;
    Function ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean; Override;
    Function ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean; Override;
    Function SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean; Override;
    Function Describe: String; Override;
  End;

Implementation

Uses
  SysUtils, Forms, Controls, LazFileUtils, FileUtil, LazIDEIntf, ProjectIntf, SrcEditorIntf, AssistantTools,
  SynEdit, CodeToolManager, AssistantWorkTarget, InterfaceBase, AssistantTestSettings, AssistantBuildDependencies, AssistantSymbolTools, AssistantFileCreation, AssistantEditorEdits, AssistantIDEContext, AssistantProtocol, fpjson, jsonparser
    {$IFDEF UNIX}, BaseUnix{$ENDIF};

Type
  { Owned by the editor control, so reopening a file cannot reuse a receipt's
    identity even when the allocator reuses the same object address. }
  TAssistantChangeIdentity = Class(TComponent)
  Public
    ID: String;
  End;

Function TAssistantIDEWorkspace.EditorAffectsBuild(Editor: TObject): Boolean;
Var
  I: Integer;
  Ed: TSourceEditorInterface;
Begin
  Result := False;
  If Not Assigned(Editor) Then Exit;
  If AssistantTarget.Kind = atkProject Then Exit(True);
  Ed := TSourceEditorInterface(Editor);
  If AssistantTarget.ContainsFile(Ed.FileName) Then Exit(True);
  For I := 0 To High(FBuildInputs) Do
    If CompareFilenames(Ed.FileName, FBuildInputs[I].Path) = 0 Then Exit(True);
End;

Function TAssistantIDEWorkspace.CanGit: Boolean;
Begin
  Result := AssistantTarget.Available And (ProjectRootPath <> '');
End;

Function TAssistantIDEWorkspace.RunGit(Const Arguments: String; Out ResultText, ErrorText: String): Boolean;
Begin
  Result := ToolRunGit(Arguments, ResultText, ErrorText);
End;

Destructor TAssistantIDEWorkspace.Destroy;
Begin
  CancelBuild;
  Inherited Destroy;
End;

Procedure TAssistantIDEWorkspace.CancelBuild;
Begin
  Inc(FBuildGeneration);
  If Assigned(FTests) Then FTests.Cancel;
  FTests := Nil;
  If Assigned(FBuild) Then FBuild.Cancel;
  FBuild := Nil;
  SetLength(FBuildInputs, 0);
  SetLength(FBuildRoots, 0);
  FDependencyEvidence := '';
End;

Function TAssistantIDEWorkspace.IsMarkdownPath(Const Path: String): Boolean;
Var
  PhysicalPath, Resolved, ErrorText: String;
Begin
  Result := False;
  If Not Inherited IsMarkdownPath(Path) Then Exit;
  { A Markdown-named symlink must not permit changing a source file. Check
    again after approval, since a link may have changed while the dialog ran. }
  If Not ResolveProjectPath(Path, Resolved, ErrorText) Then Exit;
  PhysicalPath := GetPhysicalFilename(Resolved, pfeOriginal);
  If PhysicalPath = '' Then Exit;
  Result := Inherited IsMarkdownPath(PhysicalPath);
End;

Function TAssistantIDEWorkspace.CanChangeSets: Boolean;
Begin
  Result := Assigned(SourceEditorManagerIntf);
End;

Function TAssistantIDEWorkspace.ReadChangeBuffer(Const Path: String; Out CanonicalPath, Text, Stamp, ErrorText: String): Boolean;
Var
  Editor: TSourceEditorInterface;
  Physical: String;
  Control: TCustomSynEdit;
  Token: TAssistantChangeIdentity;
  I: Integer;
  Guid: TGuid;
  Function Supported(Const Name: String): Boolean;
  Var
    Ext: String;
  Begin
    Ext := LowerCase(ExtractFileExt(Name));
    Result := (Ext = '.pas') Or (Ext = '.pp') Or (Ext = '.lpr') Or (Ext = '.dpr') Or (Ext = '.inc') Or
      (Ext = '.md') Or (Ext = '.markdown') Or (Ext = '.mdown') Or (Ext = '.txt');
  End;
Begin
  Result := False;
  Stamp := '';
  If Not ReadBuffer(Path, CanonicalPath, Text, ErrorText) Then Exit;
  If Not AssistantTarget.AllowsWrite(CanonicalPath) Then
    Begin
      ErrorText := 'Path is outside the selected target write scope.';
      Exit;
    End;
  Physical := GetPhysicalFilename(CanonicalPath, pfeOriginal);
  If (Physical = '') Or Not Supported(Path) Or Not Supported(CanonicalPath) Or Not Supported(Physical) Then
    Begin
      ErrorText := 'Change sets support Pascal, Markdown and .txt buffers; project/designer metadata is excluded.';
      Exit;
    End;
  Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(CanonicalPath);
  If Not Assigned(Editor) Or Editor.ReadOnly Or Not (Editor.EditorControl Is TCustomSynEdit) Then
    Begin
      ErrorText := 'Change set requires a writable SynEdit buffer.';
      Exit;
    End;
  Control := TCustomSynEdit(Editor.EditorControl);
  Token := Nil;
  For I := 0 To Control.ComponentCount - 1 Do
    If Control.Components[I] Is TAssistantChangeIdentity Then Token := TAssistantChangeIdentity(Control.Components[I]);
  If Not Assigned(Token) Then
    Begin
      If CreateGUID(Guid) <> 0 Then
        Begin
          ErrorText := 'Cannot create editor identity.';
          Exit;
        End;
      Token := TAssistantChangeIdentity.Create(Control);
      Token.ID := GUIDToString(Guid);
    End;
  Stamp := Token.ID + ':' + IntToStr(Control.ChangeStamp);
  Result := True;
End;

Function TAssistantIDEWorkspace.CanInspectFiles: Boolean;
Begin
  Result := True;
End;

Function CheckInspectableFile(Const Path: String; Out ErrorText: String): Boolean;
Var
  Stream: TFileStream;
  Buffer: Array[0..8191] Of Byte;
  I, Count, Remaining: Integer;
  {$IFDEF UNIX}Info: Stat; {$ENDIF}
Begin
  Result := False;
  ErrorText := '';
  {$IFDEF UNIX}
  If (fpStat(Path, Info) <> 0) Or Not FPS_ISREG(Info.st_mode) Then
    Begin
      ErrorText := 'An existing regular project file is required.';
      Exit;
    End;
  If Info.st_size > 1048576 Then
    Begin
      ErrorText := 'Project file exceeds the 1 MiB inspection limit.';
      Exit;
    End;
  {$ELSE}
  If Not FileExistsUTF8(Path) Then
    Begin
      ErrorText := 'An existing project file is required.';
      Exit;
    End;
  {$ENDIF}
  Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyNone);
  Try
    If Stream.Size > 1048576 Then
      Begin
        ErrorText := 'Project file exceeds the 1 MiB inspection limit.';
        Exit;
      End;
    Remaining := 1048576;
    Repeat
      Count := Stream.Read(Buffer, SizeOf(Buffer));
      Dec(Remaining, Count);
      For I := 0 To Count - 1 Do
        If Buffer[I] = 0 Then
          Begin
            ErrorText := 'Binary or UTF-16 files are not supported by the text inspection tools.';
            Exit;
          End;
    Until (Count = 0) Or (Remaining <= 0);
  Finally
    Stream.Free;
  End;
  Result := True;
End;

Function TAssistantIDEWorkspace.ReadFile(Const Arguments: String;
    Out ResultText, ErrorText: String): Boolean;
Var
  Data: TJSONData;
  Path: String;
  Editor: TSourceEditorInterface;
Begin
  Result := False;
  ResultText := '';
  Data := GetJSON(Arguments);
  Try
    If Not ResolveProjectPath(TJSONObject(Data).Get('path', ''), Path, ErrorText) Then Exit;
    Editor := Nil;
    If Assigned(SourceEditorManagerIntf) Then Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(Path);
    If Assigned(Editor) Then
      Begin
        If Length(Editor.SourceText) > 1048576 Then
          Begin
            ErrorText := 'Buffer exceeds the 1 MiB inspection limit.';
            Exit;
          End;
      End
        Else If Not CheckInspectableFile(Path, ErrorText) Then Exit;
    Result := ToolReadFile(Arguments, ResultText, ErrorText);
  Finally
    Data.Free;
  End;
End;

Function TAssistantIDEWorkspace.ListDirectory(Const Arguments: String;
    Out ResultText, ErrorText: String): Boolean;
Begin
  Result := ToolListDirectory(Arguments, ResultText, ErrorText);
End;

Function TAssistantIDEWorkspace.OpenBuffer(Const Path: String; Out ErrorText: String): Boolean;
Var
  Resolved: String;
  Editor: TSourceEditorInterface;
  Note: String;
Begin
  Result := False;
  If Not ResolveProjectPath(Path, Resolved, ErrorText) Then Exit;
  If Not Assigned(SourceEditorManagerIntf) Then
    Begin
      ErrorText := 'Source editor manager is unavailable.';
      Exit;
    End;
  Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(Resolved);
  If Assigned(Editor) Then Exit(True);
  If Not CheckInspectableFile(Resolved, ErrorText) Then Exit;
  Result := OpenEditorReuse(Resolved, Note);
  If Not Result Then ErrorText := Note;
End;

Function TAssistantIDEWorkspace.CanCreateFiles: Boolean;
Begin
  Result := {$IFDEF LINUX}True{$ELSE}False{$ENDIF};
End;

Function TAssistantIDEWorkspace.CheckNewFile(Const Path: String; Out CanonicalPath, ErrorText: String): Boolean;
{$IFDEF UNIX}Var
  Info: Stat; {$ENDIF}
Begin
  Result := False;
  CanonicalPath := '';
  ErrorText := '';
  If (Trim(Path) = '') Or (Pos(#0, Path) > 0) Or (Length(Path) > 4096) Then
    Begin
      ErrorText := 'A new project file path is required.';
      Exit;
    End;
  If Not ResolveProjectPath(Path, CanonicalPath, ErrorText) Then Exit;
  If Not AssistantTarget.AllowsWrite(CanonicalPath) Then
    Begin
      ErrorText := 'Path is outside the selected target write scope.';
      Exit;
    End;
  If Not Assigned(SourceEditorManagerIntf) Then
    Begin
      ErrorText := 'Source editor manager is unavailable.';
      Exit;
    End;
  If Assigned(SourceEditorManagerIntf.SourceEditorIntfWithFilename(CanonicalPath)) Then
    Begin
      ErrorText := 'An editor buffer already owns this path; use its revision tools.';
      Exit;
    End;
  {$IFDEF UNIX}
  If fpLStat(CanonicalPath, Info) = 0 Then
  {$ELSE}
    If FileExistsUTF8(CanonicalPath) Or DirectoryExistsUTF8(CanonicalPath) Then
  {$ENDIF}
      Begin
        ErrorText := 'Destination already exists; new-file creation never overwrites.';
        Exit;
      End;
  Result := True;
End;

Function TAssistantIDEWorkspace.CreateFile(Const Path, Text: String; Out ResultText, ErrorText: String): Boolean;
Var
  Resolved, Root, RelativePath: String;
Begin
  Result := False;
  ResultText := '';
  { Repeat all IDE checks after approval: an unsaved editor or a disk file may
    have appeared while the review dialog was open. }
  If Not CheckNewFile(Path, Resolved, ErrorText) Then Exit;
  Root := IncludeTrailingPathDelimiter(ExpandFileName(ProjectRootPath));
  RelativePath := Copy(Resolved, Length(Root) + 1, MaxInt);
  If Not CreateNewProjectText(Root, RelativePath, Text, ErrorText) Then Exit;
  ResultText := '{"created":true,"saved":true,"opened":false,"addedToProject":false,"path":"' +
    JsonEscapeText(Resolved) + '","bytes":' + IntToStr(Length(Text)) + '}';
  Result := True;
End;

Function TAssistantIDEWorkspace.CanFindDeclaration: Boolean;
Begin
  Result := Assigned(LazarusIDE) And Assigned(CodeToolBoss) And Assigned(SourceEditorManagerIntf);
End;

Function TAssistantIDEWorkspace.CanInspectSymbols: Boolean;
Begin
  Result := CanFindDeclaration;
End;

Function TAssistantIDEWorkspace.CanPreviewRename: Boolean;
Begin
  Result := CanInspectSymbols;
End;

Function TAssistantIDEWorkspace.PreviewLocalRename(Const Path: String; Line, Column: Integer;
    Const NewName: String; Out NewText, PreviewText, ErrorText: String): Boolean;
Var
  Resolved, Text, Reply: String;
  Data: TJSONData;
Begin
  Result := False;
  NewText := '';
  PreviewText := '';
  If Not ReadBuffer(Path, Resolved, Text, ErrorText) Then Exit;
  If Not QueryAssistantSymbol(Resolved, Text, Line, Column, sqLocalRename, Nil, 0, Reply, ErrorText, NewName) Then Exit;
  Data := GetJSON(Reply);
  Try
    NewText := TJSONObject(Data).Get('text', '');
    TJSONObject(Data).Delete('text');
    PreviewText := Data.AsJSON;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function TAssistantIDEWorkspace.FindDeclaration(Const Path: String; Line, Column: Integer;
    Out ResultText, ErrorText: String): Boolean;
Var
  Resolved, Text: String;
Begin
  Result := False;
  ResultText := '';
  If Not ReadBuffer(Path, Resolved, Text, ErrorText) Then Exit;
  Result := QueryAssistantSymbol(Resolved, Text, Line, Column, sqDeclaration, Nil, 0, ResultText, ErrorText);
End;

Function TAssistantIDEWorkspace.SymbolContext(Const Path: String; Line, Column: Integer;
    Out ResultText, ErrorText: String): Boolean;
Var
  Resolved, Text: String;
Begin
  Result := False;
  ResultText := '';
  If Not ReadBuffer(Path, Resolved, Text, ErrorText) Then Exit;
  Result := QueryAssistantSymbol(Resolved, Text, Line, Column, sqContext, Nil, 0, ResultText, ErrorText);
End;

Function TAssistantIDEWorkspace.FindReferences(Const Path: String; Line, Column: Integer;
    SearchPaths: TStrings; MaxResults: Integer; Out ResultText, ErrorText: String): Boolean;
Var
  Resolved, Text: String;
Begin
  Result := False;
  ResultText := '';
  If Not ReadBuffer(Path, Resolved, Text, ErrorText) Then Exit;
  Result := QueryAssistantSymbol(Resolved, Text, Line, Column, sqReferences, SearchPaths, MaxResults, ResultText, ErrorText);
End;

Function TAssistantIDEWorkspace.CanTest: Boolean;
Begin
  Result := True;
End;

Function TAssistantIDEWorkspace.TestCommand(Const BuildId: String; Out Command, ErrorText: String): Boolean;
Var
  Status: String;
  Data: TJSONData;
  Settings: TAssistantTestSettings;
  Fingerprint: String;
Begin
  Result := False;
  Command := '';
  ErrorText := '';
  If Assigned(FTests) And Not FTests.Snapshot.Done Then
    Begin
      ErrorText := 'A test command is already running.';
      Exit;
    End;
  If Not BuildStatus(Status, ErrorText) Then Exit;
  Data := GetJSON(Status);
  Try
    If (BuildId = '') Or (Data.FindPath('job_id').AsString <> BuildId) Or
      (Data.FindPath('outcome').AsString <> 'compile_passed') Then
        Begin
          ErrorText := 'Tests require a successful current build with unchanged observed inputs.';
          Exit;
        End;
  Finally
    Data.Free;
  End;
  Settings := TAssistantTestSettings.Create(AssistantTarget.StoreDirectory, AssistantTarget.Manifest);
  Try
    Settings.Load;
    If Not Settings.Enabled Then
      Begin
        ErrorText := 'Configure and enable the runner in Settings > Target tests.';
        Exit;
      End;
    If Not Settings.Validate(ErrorText) Then Exit;
    If Not ExecutableFingerprint(Settings.ResolvedExecutable, Fingerprint, ErrorText) Then Exit;
    { Include the reviewed binary identity, so changing it during approval also
      invalidates this command even when its path and arguments stay the same. }
    Data := GetJSON(Settings.CommandJSON);
    Try
      TJSONObject(Data).Add('executableFingerprint', Fingerprint);
      TJSONObject(Data).Add('build_job_id', BuildId);
      Command := Data.AsJSON;
    Finally
      Data.Free;
    End;
    Result := True;
  Finally
    Settings.Free;
  End;
End;

Function TAssistantIDEWorkspace.StartTests(Const BuildId, ExpectedCommand: String; Out ResultText, ErrorText: String): Boolean;
Var
  Command: String;
  Data: TJSONData;
  Args: TStringList;
  I: Integer;
  Value: TBuildJobSnapshot;
  Job: IAssistantBuildJob;
Begin
  Result := False;
  ResultText := '';
  If Not TestCommand(BuildId, Command, ErrorText) Then Exit;
  If Command <> ExpectedCommand Then
    Begin
      ErrorText := 'Test configuration, executable or build changed during approval.';
      Exit;
    End;
  Data := GetJSON(Command);
  Args := TStringList.Create;
  Try
    For I := 0 To Data.FindPath('arguments').Count - 1 Do Args.Add(Data.FindPath('arguments').Items[I].AsString);
    Job := StartAssistantTest(Data.FindPath('executable').AsString, Data.FindPath('workingDirectory').AsString,
      BuildId, Args, FBuildInputs, Data.FindPath('timeoutSeconds').AsInteger * 1000, Data.FindPath('executableFingerprint').AsString, Data.FindPath('reportFormat').AsString, Data.FindPath('minimumTests').AsInteger);
    FTests := Job;
    FTestBuildId := BuildId;
    FTestCommand := Command;
    FTestExecutable := Data.FindPath('executable').AsString;
    Value := FTests.Snapshot;
    ResultText := '{"started":true,"job_id":"' + JsonEscapeText(Value.JobId) + '","build_job_id":"' + JsonEscapeText(BuildId) + '"}';
    Result := True;
  Finally
    Args.Free;
    Data.Free;
  End;
End;

Function TAssistantIDEWorkspace.TestStatus(Out ResultText, ErrorText: String): Boolean;
Var
  Value: TBuildJobSnapshot;
  Status, Note, Fingerprint: String;
  Data: TJSONData;
  Stale: Boolean;
  Settings: TAssistantTestSettings;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  If Not Assigned(FTests) Then
    Begin
      ErrorText := 'No test command has been started.';
      Exit;
    End;
  Value := FTests.Snapshot;
  Stale := Value.Done And Not Value.InputsUnchanged;
  If Not BuildStatus(Status, Note) Then Stale := True
  Else
    Begin
      Data := GetJSON(Status);
      Try
        Stale := Stale Or (Data.FindPath('job_id').AsString <> FTestBuildId) Or
          (Data.FindPath('outcome').AsString <> 'compile_passed');
      Finally
        Data.Free;
      End;
    End;
  If Not Stale Then
    Begin
      If Not ExecutableFingerprint(FTestExecutable, Fingerprint, Note) Or (Fingerprint <> Value.ExecutableFingerprint) Then Stale := True;
      Settings := TAssistantTestSettings.Create(AssistantTarget.StoreDirectory, AssistantTarget.Manifest);
      Try
        Settings.Load;
        Data := GetJSON(Settings.CommandJSON);
        Try
          TJSONObject(Data).Add('executableFingerprint', Fingerprint);
          TJSONObject(Data).Add('build_job_id', FTestBuildId);
          If Data.AsJSON <> FTestCommand Then Stale := True;
        Finally
          Data.Free;
        End;
      Finally
        Settings.Free;
      End;
    End;
  ResultText := AssistantBuildStatusJSON(Value, Stale);
  Result := True;
End;

Function TAssistantIDEWorkspace.CanBuild: Boolean;
Begin
  Result := True;
End;

Function TAssistantIDEWorkspace.BuildExecutable: String;
Begin
  Result := FindLazbuildExecutable;
End;

Function TAssistantIDEWorkspace.StartBuild(Out ResultText, ErrorText: String): Boolean;
Var
  Editor: TSourceEditorInterface;
  I: Integer;
  Exe, ProjectFile, Path, Resource: String;
  Inputs, Roots: TBuildInputs;
  Evidence, ProjectIdentity, RequestedMode: String;
  Generation: QWord;
  DefineStep: Integer;
  Files: TStringList;
  Value: TBuildJobSnapshot;
  Job: IAssistantBuildJob;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  If Assigned(FTests) And Not FTests.Snapshot.Done Then
    Begin
      ErrorText := 'A test command is already running.';
      Exit;
    End;
  If Assigned(FBuild) And Not FBuild.Snapshot.Done Then
    Begin
      ErrorText := 'A build is already running.';
      Exit;
    End;
  If Not Assigned(LazarusIDE) Or Not AssistantTarget.Available Or
    Not Assigned(SourceEditorManagerIntf) Then
      Begin
        ErrorText := 'No available Assistant work target.';
        Exit;
      End;
  Generation := FBuildGeneration;
  ProjectIdentity := Identity;
  RequestedMode := AssistantTarget.ConfigurationStamp;
  If AssistantTarget.Modified Then
    Begin
      ErrorText := 'Save target and dependency settings explicitly before building.';
      Exit;
    End;
  ProjectFile := AssistantTarget.Manifest;
  Exe := BuildExecutable;
  If Not FileExistsUTF8(Exe) Then
    Begin
      ErrorText := 'lazbuild was not found.';
      Exit;
    End;
  Inputs := Nil;
  If Not AddBuildInput(Inputs, ProjectFile, ErrorText) Then Exit;
  { Target members seed the CodeTools closure; dependency manifests also form
    saved evidence, without granting write access to dependency source trees. }
  Files := TStringList.Create;
  Try
    AssistantTarget.Members(Files);
    For I := 0 To Files.Count - 1 Do
      Begin
        Path := Files[I];
        If Not AddBuildInput(Inputs, Path, ErrorText) Then Exit;
        Resource := ChangeFileExt(Path, '.lfm');
        If FileExistsUTF8(Resource) And Not AddBuildInput(Inputs, Resource, ErrorText) Then Exit;
        Resource := ChangeFileExt(Path, '.lrs');
        If FileExistsUTF8(Resource) And Not AddBuildInput(Inputs, Resource, ErrorText) Then Exit;
      End;
    AssistantTarget.Dependencies(Files);
    For I := 0 To Files.Count - 1 Do If Not AddBuildInput(Inputs, Files[I], ErrorText) Then Exit;
  Finally
    Files.Free;
  End;
  For I := 0 To SourceEditorManagerIntf.SourceEditorCount - 1 Do
    Begin
      Editor := SourceEditorManagerIntf.SourceEditors[I];
      If Not Assigned(Editor) Then Continue;
      If (AssistantTarget.Kind <> atkProject) And Not AssistantTarget.ContainsFile(Editor.FileName) Then Continue;
      If Editor.Modified Or Editor.ModifiedDesign Then
        Begin
          ErrorText := 'Save changed editor buffers and designer resources explicitly before building.';
          Exit;
        End;
      If Editor.FileName = '' Then Continue;
      If Not AddBuildInput(Inputs, Editor.FileName, ErrorText) Then Exit;
    End;
  Roots := Copy(Inputs);
  CaptureAssistantDependencies(Inputs, Evidence, DefineStep);
  If (FBuildGeneration <> Generation) Or (Identity <> ProjectIdentity) Then
    Begin
      ErrorText := 'Build cancelled or project changed during dependency discovery.';
      Exit;
    End;
  If AssistantTarget.Modified Or (AssistantTarget.ConfigurationStamp <> RequestedMode) Or Not Assigned(SourceEditorManagerIntf) Then
    Begin
      ErrorText := 'Target settings changed during dependency discovery.';
      Exit;
    End;
  For I := 0 To SourceEditorManagerIntf.SourceEditorCount - 1 Do
    Begin
      Editor := SourceEditorManagerIntf.SourceEditors[I];
      If Assigned(Editor) And EditorAffectsBuild(Editor) And (Editor.Modified Or Editor.ModifiedDesign) Then
        Begin
          ErrorText := 'Editor changed during dependency discovery.';
          Exit;
        End;
    End;
  { Check actual buffer text too: Modified=False alone is not evidence that
    editor bytes match what the external compiler will read. }
  For I := 0 To High(Inputs) Do
    Begin
      Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(Inputs[I].Path);
      If Assigned(Editor) And (Editor.SourceText <> Inputs[I].Text) Then
        Begin
          ErrorText := 'Editor text differs from saved build input: ' + Inputs[I].Path;
          Exit;
        End;
    End;
  If AssistantTarget.Kind = atkPackage Then
    Job := StartAssistantBuild(Exe, ProjectFile, '', Inputs, 600000, LazarusIDE.GetPrimaryConfigPath, GetLCLWidgetTypeName)
  Else Job := StartAssistantBuild(Exe, ProjectFile, AssistantTarget.BuildMode, Inputs);
  FBuildIdentity := Identity;
  FBuildMode := AssistantTarget.ConfigurationStamp;
  Inc(FBuildGeneration);
  FBuildInputs := Inputs;
  FBuildRoots := Roots;
  FDependencyEvidence := Evidence;
  FDefineStep := DefineStep;
  FBuild := Job;
  Value := FBuild.Snapshot;
  ResultText := '{"started":true,"job_id":"' + JsonEscapeText(Value.JobId) + '","savedBuffers":false}';
  Result := True;
End;

Function TAssistantIDEWorkspace.BuildStatus(Out ResultText, ErrorText: String): Boolean;
Var
  Value: TBuildJobSnapshot;
  I, J, DefineStep: Integer;
  Editor: TSourceEditorInterface;
  Stale, Found: Boolean;
  Note, Evidence: String;
  CurrentInputs: TBuildInputs;
  Root, Dependency: TJSONObject;
  Generation: QWord;
Begin
  Result := False;
  ResultText := '';
  ErrorText := '';
  If Not Assigned(FBuild) Then
    Begin
      ErrorText := 'No build has been started.';
      Exit;
    End;
  Value := FBuild.Snapshot;
  Stale := (Identity <> FBuildIdentity) Or (Value.Done And Not Value.InputsUnchanged);
  If Not Stale Then
    Begin
      Stale := Not Assigned(LazarusIDE) Or Not AssistantTarget.Available Or Not Assigned(SourceEditorManagerIntf);
      If Not Stale Then
        Begin
          Stale := AssistantTarget.Modified Or (AssistantTarget.ConfigurationStamp <> FBuildMode);
          { Recheck disk at observation time as well as worker completion: an
            earlier successful build must not validate subsequent saved edits. }
          If Value.Done And Not BuildInputsMatch(FBuildInputs, Note) Then Stale := True;
          For I := 0 To SourceEditorManagerIntf.SourceEditorCount - 1 Do
            Begin
              Editor := SourceEditorManagerIntf.SourceEditors[I];
              If Assigned(Editor) And EditorAffectsBuild(Editor) And (Editor.Modified Or Editor.ModifiedDesign) Then Stale := True;
            End;
          For I := 0 To High(FBuildInputs) Do
            Begin
              Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(FBuildInputs[I].Path);
              If Assigned(Editor) And (Editor.SourceText <> FBuildInputs[I].Text) Then Stale := True;
            End;
        End;
    End;
  { Rediscover when observing a completed build: a new higher-priority unit or
    newly created paired resource must also invalidate previous evidence. }
  Evidence := FDependencyEvidence;
  Generation := FBuildGeneration;
  If Value.Done And Not Stale Then
    Begin
      CurrentInputs := Copy(FBuildRoots);
      CaptureAssistantDependencies(CurrentInputs, Evidence, DefineStep);
      If Generation <> FBuildGeneration Then
        Begin
          ErrorText := 'Build changed during dependency discovery.';
          Exit;
        End;
      Stale := (DefineStep <> FDefineStep) Or (Length(CurrentInputs) <> Length(FBuildInputs));
      For I := 0 To High(CurrentInputs) Do
        Begin
          Found := False;
          For J := 0 To High(FBuildInputs) Do
            If (CurrentInputs[I].Path = FBuildInputs[J].Path) And (CurrentInputs[I].Text = FBuildInputs[J].Text) Then
              Begin
                Found := True;
                Break;
              End;
          If Not Found Then Stale := True;
        End;
      Stale := Stale Or (Identity <> FBuildIdentity) Or Not Assigned(SourceEditorManagerIntf);
      If Not Stale Then
        Begin
          Stale := AssistantTarget.Modified Or (AssistantTarget.ConfigurationStamp <> FBuildMode);
          For I := 0 To SourceEditorManagerIntf.SourceEditorCount - 1 Do
            Begin
              Editor := SourceEditorManagerIntf.SourceEditors[I];
              If Assigned(Editor) And EditorAffectsBuild(Editor) And (Editor.Modified Or Editor.ModifiedDesign) Then Stale := True;
            End;
          For I := 0 To High(FBuildInputs) Do
            Begin
              Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(FBuildInputs[I].Path);
              If Assigned(Editor) And (Editor.SourceText <> FBuildInputs[I].Text) Then Stale := True;
            End;
        End;
      { A previously complete scan becoming incomplete cannot retain validity. }
      Root := TJSONObject(GetJSON(FDependencyEvidence));
      Dependency := TJSONObject(GetJSON(Evidence));
      Try
        If Not Root.Get('sourceClosureComplete', False) Then
          Begin
            Dependency.Booleans['sourceClosureComplete'] := False;
            Dependency.Add('initialScanIncomplete', True);
            Evidence := Dependency.AsJSON;
          End
        Else If Not Dependency.Get('sourceClosureComplete', False) Then Stale := True;
      Finally
        Root.Free;
        Dependency.Free;
      End;
    End;
  Root := TJSONObject(GetJSON(AssistantBuildStatusJSON(Value, Stale)));
  Try
    Root.Add('dependencies', GetJSON(Evidence));
    ResultText := Root.AsJSON;
  Finally
    Root.Free;
  End;
  Result := True;
End;

Function TAssistantIDEWorkspace.Identity: String;
Begin
  Result := AssistantTarget.Identity;
End;

Function TAssistantIDEWorkspace.ReadBuffer(Const Path: String;
    Out CanonicalPath, Text, ErrorText: String): Boolean;
Var
  Editor: TSourceEditorInterface;
Begin
  Result := False;
  Text := '';
  CanonicalPath := '';
  ErrorText := '';
  If Not ResolveProjectPath(Path, CanonicalPath, ErrorText) Then Exit;
  If Not Assigned(SourceEditorManagerIntf) Then
    Begin
      ErrorText := 'Source editor manager is unavailable.';
      Exit;
    End;
  Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(CanonicalPath);
  If Not Assigned(Editor) Then
    Begin
      ErrorText := 'Open this project file in the Lazarus editor before using buffer tools.';
      Exit;
    End;
  Text := Editor.SourceText;
  Result := True;
End;

Function TAssistantIDEWorkspace.ReplaceBuffer(Const Path, ExpectedText, NewText: String;
    Out ErrorText: String): Boolean;
Begin
  Result := False;
  If Not AssistantTarget.AllowsWrite(Path) Then
    Begin
      ErrorText := 'Path is outside the selected target write scope.';
      Exit;
    End;
  If Not Assigned(SourceEditorManagerIntf) Then
    Begin
      ErrorText := 'Source editor manager is unavailable.';
      Exit;
    End;
  Result := ApplyAssistantEditorText(SourceEditorManagerIntf.SourceEditorIntfWithFilename(Path),
    ExpectedText, NewText, ErrorText);
End;

Function TAssistantIDEWorkspace.SaveBuffer(Const Path, ExpectedText: String;
    Out ErrorText: String): Boolean;
Var
  Editor: TSourceEditorInterface;
Begin
  Result := False;
  If Not AssistantTarget.AllowsWrite(Path) Then
    Begin
      ErrorText := 'Path is outside the selected target write scope.';
      Exit;
    End;
  ErrorText := '';
  If Not Assigned(LazarusIDE) Or Not Assigned(SourceEditorManagerIntf) Then
    Begin
      ErrorText := 'Lazarus editor is unavailable.';
      Exit;
    End;
  Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(Path);
  If Not Assigned(Editor) Or Editor.ReadOnly Or (Editor.SourceText <> ExpectedText) Then
    Begin
      ErrorText := 'Buffer changed, closed, or became read-only before save.';
      Exit;
    End;
  Result := LazarusIDE.DoSaveEditorFile(Editor, [sfQuietUnitCheck]) = mrOk;
  If Not Result Then ErrorText := 'Buffer remains edited but could not be saved.';
End;

Function TAssistantIDEWorkspace.Describe: String;
Begin
  Result := BuildIDEContextBlockLight;
End;
End.
