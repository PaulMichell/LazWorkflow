Program AssistantOfferSnapshotTest;

{ Golden snapshots of the tool names and prompt text each turn sends (c) 2026 Michell Computing.

  Plan item 8.1. For Grok, ChatGPT and Claude, and for each conversation mode, the names actually
  offered and the system or developer text actually attached are compared with Tests/Fixtures/Grok,
  Tests/Fixtures/ChatGPT and Tests/Fixtures/Claude. A catalogue or prompt change fails until that
  file is updated on purpose. OpenAI-compatible has no turn, so it has no snapshot.

  The fixture project is empty of a saved profile, so image output is off. One skill is tagged for
  every mode, and AGENTS.md is one fixed line. OS, project root, active file and compiler lines are
  replaced with placeholders so a machine change is not a prompt change.

  Claude's catalogue is the running IDE with a project open. lazarus_create_file follows
  CanCreateNewText, so the golden marks that name and both gates are checked on every machine.
}

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Classes, SysUtils, FileUtil, LazFileUtils, fpjson, jsonparser, AssistantConversation,
  AssistantTools, AssistantService, AssistantHarness, AssistantConfig, AssistantSkills, AssistantClaudeClient,
  AssistantCodexClient, AssistantToolBroker, AssistantMCPBridge, AssistantMCPProtocol, AssistantWorkTarget,
  AssistantPlan, WorkflowSettings;

Const
  OfferSkillName = 'offer-snapshot';
  CreateFileMarker = '<if-can-create-file>';
  CreateFileOfferedName = 'mcp__lazarus__create_file';
  AgentsBody = 'Offer snapshot project rules.';
  SkillBody = '---' + LineEnding + 'name: offer-snapshot' + LineEnding +
    'description: Snapshot skill for the offer golden.' + LineEnding +
    'when-to-use: recording the attached skill body' + LineEnding + '---' + LineEnding +
    'OFFER SNAPSHOT SKILL BODY' + LineEnding;

Type
  TOfferWorkspace = Class(TAssistantWorkspaceAdapter)
    CreateFiles: Boolean;
    Function Identity: String; Override;
    Function ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean; Override;
    Function ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean; Override;
    Function SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean; Override;
    Function Describe: String; Override;
    Function SavesEdits: Boolean; Override;
    Function CanInspectFiles: Boolean; Override;
    Function CanChangeSets: Boolean; Override;
    Function CanCreateFiles: Boolean; Override;
    Function CanWriteMarkdown: Boolean; Override;
    Function CanFindDeclaration: Boolean; Override;
    Function CanInspectSymbols: Boolean; Override;
    Function CanPreviewRename: Boolean; Override;
    Function CanTest: Boolean; Override;
    Function CanGit: Boolean; Override;
    Function CanBuild: Boolean; Override;
    Function CanRunCommands: Boolean; Override;
    Function CanRunProject: Boolean; Override;
    Function CanOpenEditors: Boolean; Override;
  End;

Var
  FailCount: Integer;
  FixtureSkillPath: String;
  Repository: String;

Function TOfferWorkspace.Identity: String;
Begin
  Result := 'offer-snapshot';
End;

{$PUSH}{$HINTS OFF}
Function TOfferWorkspace.ReadBuffer(Const Path: String; Out CanonicalPath, Text, ErrorText: String): Boolean;
Begin
  CanonicalPath := '';
  Text := '';
  ErrorText := '';
  Result := False;
End;

Function TOfferWorkspace.ReplaceBuffer(Const Path, ExpectedText, NewText: String; Out ErrorText: String): Boolean;
Begin
  ErrorText := '';
  Result := False;
End;

Function TOfferWorkspace.SaveBuffer(Const Path, ExpectedText: String; Out ErrorText: String): Boolean;
Begin
  ErrorText := '';
  Result := False;
End;
{$POP}

Function TOfferWorkspace.Describe: String;
Begin
  Result := '{}';
End;

Function TOfferWorkspace.SavesEdits: Boolean;
Begin
  Result := True;
End;

Function TOfferWorkspace.CanInspectFiles: Boolean;
Begin
  Result := True;
End;

Function TOfferWorkspace.CanChangeSets: Boolean;
Begin
  Result := True;
End;

Function TOfferWorkspace.CanCreateFiles: Boolean;
Begin
  Result := CreateFiles;
End;

Function TOfferWorkspace.CanWriteMarkdown: Boolean;
Begin
  Result := True;
End;

Function TOfferWorkspace.CanFindDeclaration: Boolean;
Begin
  Result := True;
End;

Function TOfferWorkspace.CanInspectSymbols: Boolean;
Begin
  Result := True;
End;

Function TOfferWorkspace.CanPreviewRename: Boolean;
Begin
  Result := True;
End;

Function TOfferWorkspace.CanTest: Boolean;
Begin
  Result := True;
End;

Function TOfferWorkspace.CanGit: Boolean;
Begin
  Result := True;
End;

Function TOfferWorkspace.CanBuild: Boolean;
Begin
  Result := True;
End;

Function TOfferWorkspace.CanRunCommands: Boolean;
Begin
  Result := True;
End;

Function TOfferWorkspace.CanRunProject: Boolean;
Begin
  Result := True;
End;

Function TOfferWorkspace.CanOpenEditors: Boolean;
Begin
  Result := True;
End;

Procedure Check(Const Title: String; Condition: Boolean);
Begin
  If Condition Then
    WriteLn('ok   ', Title)
  Else
    Begin
      WriteLn('FAIL ', Title);
      Inc(FailCount);
    End;
End;

Procedure EnumOfferSkill(Names, Paths: TStrings);
Begin
  If Not Assigned(Names) Or Not Assigned(Paths) Then
    Exit;
  Names.Add(OfferSkillName);
  Paths.Add(FixtureSkillPath);
End;

Function RepositoryRoot: String;
Var
  I: Integer;
  Probe, Dir: String;
Begin
  Result := '';
  Dir := GetCurrentDir;
  For I := 1 To 8 Do
    Begin
      If FileExists(IncludeTrailingPathDelimiter(Dir) + 'Tests' + PathDelim + 'RunAssistantTests.pas') And
        DirectoryExists(IncludeTrailingPathDelimiter(Dir) + 'Source') Then
        Exit(ExcludeTrailingPathDelimiter(Dir));
      Probe := ExpandFileName(IncludeTrailingPathDelimiter(Dir) + '..');
      If Probe = Dir Then
        Break;
      Dir := Probe;
    End;
End;

Function ToLf(Const Text: String): String;
Begin
  Result := StringReplace(Text, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
End;

Function NormalizeAttached(Const Text: String): String;
Var
  Lines: TStringList;
  I: Integer;
  Line: String;
Begin
  Lines := TStringList.Create;
  Try
    Lines.Text := ToLf(Text);
    For I := 0 To Lines.Count - 1 Do
      Begin
        Line := Lines[I];
        If Copy(Line, 1, 4) = 'OS: ' Then
          Lines[I] := 'OS: <os>'
        Else If Copy(Line, 1, 14) = 'Project root: ' Then
          Lines[I] := 'Project root: <project-root>'
        Else If Copy(Line, 1, 13) = 'Active file: ' Then
          Lines[I] := 'Active file: <active-file>'
        Else If Copy(Line, 1, 10) = 'Compiler: ' Then
          Lines[I] := 'Compiler: <compiler>';
      End;
    Result := ToLf(Lines.Text);
    While (Result <> '') And (Result[Length(Result)] = #10) Do
      Delete(Result, Length(Result), 1);
  Finally
    Lines.Free;
  End;
End;

Procedure WriteUtf8(Const Path, Text: String);
Var
  Stream: TFileStream;
  Dir, Body: RawByteString;
Begin
  Dir := ExtractFilePath(Path);
  If (Dir <> '') And (Not DirectoryExists(Dir)) Then
    ForceDirectories(Dir);
  Body := ToLf(Text);
  If (Body = '') Or (Body[Length(Body)] <> #10) Then
    Body := Body + #10;
  SetCodePage(Body, CP_UTF8, False);
  Stream := TFileStream.Create(Path, fmCreate);
  Try
    If Body <> '' Then
      Stream.WriteBuffer(Body[1], Length(Body));
  Finally
    Stream.Free;
  End;
End;

Function ReadUtf8(Const Path: String): String;
Var
  Stream: TFileStream;
  Body: RawByteString;
Begin
  Result := '';
  Body := '';
  Stream := TFileStream.Create(Path, fmOpenRead Or fmShareDenyWrite);
  Try
    SetLength(Body, Stream.Size);
    If Stream.Size > 0 Then
      Stream.ReadBuffer(Body[1], Stream.Size);
  Finally
    Stream.Free;
  End;
  SetCodePage(Body, CP_UTF8, False);
  Result := ToLf(Body);
End;

Function FixturePath(Const Backend, ModeName: String): String;
Begin
  Result := IncludeTrailingPathDelimiter(Repository) + 'Tests' + PathDelim + 'Fixtures' + PathDelim + Backend +
    PathDelim + ModeName + '.txt';
End;

Function DumpPath(Const Backend, ModeName: String): String;
Begin
  Result := IncludeTrailingPathDelimiter(Repository) + 'Temporary' + PathDelim + 'OfferSnapshots' + PathDelim +
    Backend + PathDelim + ModeName + '.txt';
End;

Procedure AddNamesFromJson(Const JsonText: String; Names: TStrings);
Var
  Data, Fn: TJSONData;
  Item: TJSONObject;
  I: Integer;
  Name: String;
Begin
  If Trim(JsonText) = '' Then
    Exit;
  Data := Nil;
  Try
    Data := GetJSON(JsonText);
  Except
    Data := Nil;
  End;
  If Not (Data Is TJSONArray) Then
    Begin
      Data.Free;
      Check('tool catalogue is a JSON array', False);
      Exit;
    End;
  Try
    For I := 0 To TJSONArray(Data).Count - 1 Do
      Begin
        If Not (TJSONArray(Data).Items[I] Is TJSONObject) Then
          Begin
            Check('tool catalogue item is an object', False);
            Continue;
          End;
        Item := TJSONObject(TJSONArray(Data).Items[I]);
        Fn := Item.Find('function');
        If Fn Is TJSONObject Then
          Name := TJSONObject(Fn).Get('name', '')
        Else
          Name := Item.Get('name', '');
        Check('offered tool has a name', Name <> '');
        If Name <> '' Then
          Names.Add(Name);
      End;
  Finally
    Data.Free;
  End;
End;

Procedure RefuseWriteImage(Const Title: String; Names: TStrings);
Begin
  Check(Title + ' does not offer write_image without a drawing profile', Names.IndexOf('write_image') < 0);
End;

Function ArgumentValue(Args: TStrings; Const Prefix: String): String;
Var
  I: Integer;
Begin
  Result := '';
  If Not Assigned(Args) Then
    Exit;
  For I := 0 To Args.Count - 1 Do
    If Copy(Args[I], 1, Length(Prefix)) = Prefix Then
      Begin
        If Result <> '' Then
          Result := Result + #10;
        Result := Result + Copy(Args[I], Length(Prefix) + 1, MaxInt);
      End;
End;

Procedure AddCommaNames(Const List: String; Names: TStrings);
Var
  Rest, Name: String;
  At: Integer;
Begin
  Rest := List;
  While Rest <> '' Do
    Begin
      At := Pos(',', Rest);
      If At = 0 Then
        Begin
          Name := Trim(Rest);
          Rest := '';
        End
      Else
        Begin
          Name := Trim(Copy(Rest, 1, At - 1));
          Delete(Rest, 1, At);
        End;
      If Name <> '' Then
        Names.Add(Name);
    End;
End;

Procedure AddClaudeMcpNames(Mode: TAssistantMode; CreateFiles: Boolean; Const Prefix: String; Names: TStrings);
Var
  Workspace: TOfferWorkspace;
  Broker: TAssistantToolBroker;
  Listed, Name: String;
  Data, Tools: TJSONData;
  I: Integer;
Begin
  Workspace := TOfferWorkspace.Create;
  Broker := TAssistantToolBroker.Create(Workspace);
  Try
    Workspace.CreateFiles := CreateFiles;
    Broker.BeginRun(AssistantWriteScopeForMode(Mode), Mode);
    Listed := MCPToolsListResult(Broker.ToolsJson);
    Data := Nil;
    Try
      Data := GetJSON(Listed);
    Except
      Data := Nil;
    End;
    If Not (Data Is TJSONObject) Then
      Begin
        Data.Free;
        Check('Claude tools/list is an object', False);
        Exit;
      End;
    Try
      Tools := TJSONObject(Data).Find('tools');
      If Not (Tools Is TJSONArray) Then
        Begin
          Check('Claude tools/list has a tools array', False);
          Exit;
        End;
      For I := 0 To TJSONArray(Tools).Count - 1 Do
        Begin
          If Not (TJSONArray(Tools).Items[I] Is TJSONObject) Then
            Continue;
          Name := TJSONObject(TJSONArray(Tools).Items[I]).Get('name', '');
          Check('Claude listed tool has a name', Name <> '');
          If Name <> '' Then
            Names.Add(Prefix + Name);
        End;
    Finally
      Data.Free;
    End;
  Finally
    Broker.Free;
    Workspace.Free;
  End;
End;

Procedure CaptureClaude(Mode: TAssistantMode; CreateFiles: Boolean; Names: TStrings; Out Attached: String);
Var
  Args: TStringList;
  ConfigFile, Allowed, Prefix: String;
Begin
  Attached := '';
  Args := TStringList.Create;
  Try
    If ClaudeTurnUsesMCP(Mode) Then
      ConfigFile := 'mcp-config.json'
    Else
      ConfigFile := '';
    If ConfigFile <> '' Then
      Attached := ClaudeHarnessPrompt(Mode) + LineEnding + LineEnding + ClaudeReadImageNote
    Else
      Attached := ClaudeHarnessPrompt(Mode);
    AppendClaudeModeArguments(AssistantWriteScopeForMode(Mode), ConfigFile, Attached, Args);
    AddCommaNames(ArgumentValue(Args, '--tools='), Names);
    Attached := ArgumentValue(Args, '--append-system-prompt=');
    If Not ClaudeTurnUsesMCP(Mode) Then
      Exit;
    Allowed := ArgumentValue(Args, '--allowedTools=');
    Check('Claude allowed-tools pattern ends with a star', (Allowed <> '') And (Allowed[Length(Allowed)] = '*') And
      (Pos(#10, Allowed) = 0));
    If (Allowed = '') Or (Allowed[Length(Allowed)] <> '*') Then
      Exit;
    Prefix := Copy(Allowed, 1, Length(Allowed) - 1);
    AddClaudeMcpNames(Mode, CreateFiles, Prefix, Names);
  Finally
    Args.Free;
  End;
End;

Function FormatSnapshot(Names: TStrings; Const Kind, Attached: String): String;
Var
  Lines: TStringList;
  I: Integer;
Begin
  Lines := TStringList.Create;
  Try
    Lines.Add('tools:');
    If Assigned(Names) Then
      For I := 0 To Names.Count - 1 Do
        Lines.Add(Names[I]);
    Lines.Add('');
    Lines.Add('attached: ' + Kind);
    If Attached <> '' Then
      Lines.Add(Attached);
    Result := ToLf(Lines.Text);
    While (Result <> '') And (Result[Length(Result)] = #10) Do
      Delete(Result, Length(Result), 1);
  Finally
    Lines.Free;
  End;
End;

Procedure ExpandMarker(Source, Dest: TStrings; CreateFiles: Boolean);
Var
  I: Integer;
Begin
  Dest.Clear;
  For I := 0 To Source.Count - 1 Do
    If Source[I] = CreateFileMarker Then
      Begin
        If CreateFiles Then
          Dest.Add(CreateFileOfferedName);
      End
    Else
      Dest.Add(Source[I]);
End;

Procedure MarkerLines(WithCreate, WithoutCreate, Dest: TStrings);
Var
  I, J: Integer;
Begin
  Dest.Clear;
  J := 0;
  For I := 0 To WithCreate.Count - 1 Do
    If (J < WithoutCreate.Count) And (WithCreate[I] = WithoutCreate[J]) Then
      Begin
        Dest.Add(WithCreate[I]);
        Inc(J);
      End
    Else If WithCreate[I] = CreateFileOfferedName Then
      Dest.Add(CreateFileMarker)
    Else
      Dest.Add('UNEXPECTED ' + WithCreate[I]);
  While J < WithoutCreate.Count Do
    Begin
      Dest.Add('MISSING ' + WithoutCreate[J]);
      Inc(J);
    End;
End;

Function FirstDifference(Const Expected, Actual: String): String;
Var
  Left, Right: TStringList;
  I, Limit: Integer;
Begin
  Left := TStringList.Create;
  Right := TStringList.Create;
  Try
    Left.Text := Expected;
    Right.Text := Actual;
    Limit := Left.Count;
    If Right.Count < Limit Then
      Limit := Right.Count;
    For I := 0 To Limit - 1 Do
      If Left[I] <> Right[I] Then
        Exit('line ' + IntToStr(I + 1) + ' expected [' + Left[I] + '] actual [' + Right[I] + ']');
    If Left.Count <> Right.Count Then
      Result := 'length expected ' + IntToStr(Left.Count) + ' actual ' + IntToStr(Right.Count)
    Else
      Result := '';
  Finally
    Right.Free;
    Left.Free;
  End;
End;

Procedure CompareFormatted(Const Title, GoldenFile, Expected, Actual: String);
Var
  Diff: String;
Begin
  Diff := FirstDifference(Expected, Actual);
  Check(Title, Diff = '');
  If Diff = '' Then
    Exit;
  WriteLn('     ', Diff);
  WriteLn('     golden: ', GoldenFile);
  WriteUtf8(DumpPath(ExtractFileName(ExtractFileDir(GoldenFile)), ChangeFileExt(ExtractFileName(GoldenFile), '')), Actual);
  WriteLn('     captured: ', DumpPath(ExtractFileName(ExtractFileDir(GoldenFile)),
    ChangeFileExt(ExtractFileName(GoldenFile), '')));
End;

Procedure LoadGolden(Const Path: String; ToolLines: TStrings; Out Kind, Attached: String);
Var
  Lines: TStringList;
  I, AttachedAt: Integer;
  Header: String;
Begin
  Kind := '';
  Attached := '';
  ToolLines.Clear;
  If Not FileExists(Path) Then
    Exit;
  Lines := TStringList.Create;
  Try
    Lines.Text := ReadUtf8(Path);
    If (Lines.Count = 0) Or (Lines[0] <> 'tools:') Then
      Exit;
    I := 1;
    While (I < Lines.Count) And (Lines[I] <> '') Do
      Begin
        ToolLines.Add(Lines[I]);
        Inc(I);
      End;
    If (I >= Lines.Count) Or (Lines[I] <> '') Then
      Exit;
    Inc(I);
    If I >= Lines.Count Then
      Exit;
    Header := Lines[I];
    If Copy(Header, 1, 10) <> 'attached: ' Then
      Exit;
    Kind := Copy(Header, 11, MaxInt);
    AttachedAt := I + 1;
    Attached := '';
    For I := AttachedAt To Lines.Count - 1 Do
      Begin
        If Attached <> '' Then
          Attached := Attached + #10;
        Attached := Attached + Lines[I];
      End;
  Finally
    Lines.Free;
  End;
End;

Procedure CompareOne(Const Backend, ModeName, Kind, Attached: String; Names: TStrings);
Var
  Path, GoldenKind, GoldenAttached, Expected: String;
  ToolLines, Expanded: TStringList;
Begin
  Path := FixturePath(Backend, ModeName);
  ToolLines := TStringList.Create;
  Expanded := TStringList.Create;
  Try
    If Not FileExists(Path) Then
      Begin
        WriteUtf8(DumpPath(Backend, ModeName), FormatSnapshot(Names, Kind, Attached));
        Check(Backend + ' ' + ModeName + ' golden exists', False);
        WriteLn('     missing ', Path);
        WriteLn('     captured ', DumpPath(Backend, ModeName));
        Exit;
      End;
    LoadGolden(Path, ToolLines, GoldenKind, GoldenAttached);
    Check(Backend + ' ' + ModeName + ' golden has an attached label', GoldenKind <> '');
    ExpandMarker(ToolLines, Expanded, False);
    Expected := FormatSnapshot(Expanded, GoldenKind, GoldenAttached);
    CompareFormatted(Backend + ' ' + ModeName + ' matches the golden', Path, Expected,
      FormatSnapshot(Names, Kind, Attached));
  Finally
    Expanded.Free;
    ToolLines.Free;
  End;
End;

Function ClaudeAttachedKind(Const Attached: String): String;
Begin
  If Attached = '' Then
    Result := 'none'
  Else
    Result := 'append-system-prompt';
End;

Procedure CompareClaude(Const ModeName, Attached: String; WithCreate, WithoutCreate: TStrings);
Var
  Path, GoldenKind, GoldenAttached, Expected, Kind: String;
  ToolLines, Expanded, Merged: TStringList;
Begin
  Path := FixturePath('Claude', ModeName);
  Kind := ClaudeAttachedKind(Attached);
  ToolLines := TStringList.Create;
  Expanded := TStringList.Create;
  Merged := TStringList.Create;
  Try
    If Not FileExists(Path) Then
      Begin
        MarkerLines(WithCreate, WithoutCreate, Merged);
        WriteUtf8(DumpPath('Claude', ModeName), FormatSnapshot(Merged, Kind, Attached));
        Check('Claude ' + ModeName + ' golden exists', False);
        WriteLn('     missing ', Path);
        WriteLn('     captured ', DumpPath('Claude', ModeName));
        Exit;
      End;
    LoadGolden(Path, ToolLines, GoldenKind, GoldenAttached);
    Check('Claude ' + ModeName + ' golden has an attached label', GoldenKind <> '');
    ExpandMarker(ToolLines, Expanded, True);
    Expected := FormatSnapshot(Expanded, GoldenKind, GoldenAttached);
    CompareFormatted('Claude ' + ModeName + ' with create-file matches the golden', Path, Expected,
      FormatSnapshot(WithCreate, Kind, Attached));
    ExpandMarker(ToolLines, Expanded, False);
    Expected := FormatSnapshot(Expanded, GoldenKind, GoldenAttached);
    CompareFormatted('Claude ' + ModeName + ' without create-file matches the golden', Path, Expected,
      FormatSnapshot(WithoutCreate, Kind, Attached));
  Finally
    Merged.Free;
    Expanded.Free;
    ToolLines.Free;
  End;
End;

Function GrokPrompt(Service: TAssistantService; Mode: TAssistantMode): String;
Begin
  Service.SetActiveMode(amInspect);
  If Mode <> amInspect Then
    Service.SetActiveMode(Mode);
  Result := NormalizeAttached(Service.SystemPrompt);
End;

Procedure WriteTextFile(Const FileName, Body: String);
Var
  SL: TStringList;
  Dir: String;
Begin
  Dir := ExtractFilePath(FileName);
  If (Dir <> '') And (Not DirectoryExists(Dir)) Then
    ForceDirectories(Dir);
  SL := TStringList.Create;
  Try
    SL.Text := Body;
    SL.SaveToFile(FileName);
  Finally
    SL.Free;
  End;
End;

Function MakeTempRoot(Const Stem: String): String;
Begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'lazworkflow-offer-' + Stem + '-' +
    FormatDateTime('hhnnsszzz', Now);
  ForceDirectories(Result);
  Result := IncludeTrailingPathDelimiter(Result);
End;

Procedure CaptureMode(Service: TAssistantService; Mode: TAssistantMode);
Var
  ModeName, GrokText, CodexText, ClaudeText, ErrorText: String;
  GrokNames, CodexNames, ClaudeWith, ClaudeWithout: TStringList;
  Catalogue: String;
Begin
  ModeName := AssistantModeToStr(Mode);
  GrokNames := TStringList.Create;
  CodexNames := TStringList.Create;
  ClaudeWith := TStringList.Create;
  ClaudeWithout := TStringList.Create;
  Try
    Catalogue := AssistantParentToolsJson(Mode);
    AddNamesFromJson(Catalogue, GrokNames);
    RefuseWriteImage('Grok ' + ModeName, GrokNames);
    GrokText := GrokPrompt(Service, Mode);
    CompareOne('Grok', ModeName, 'system', GrokText, GrokNames);

    Catalogue := CodexDynamicToolsFromCatalogue(BuildAssistantToolsJsonForMode(Mode));
    AddNamesFromJson(Catalogue, CodexNames);
    RefuseWriteImage('ChatGPT ' + ModeName, CodexNames);
    CodexText := NormalizeAttached(CodexDeveloperInstructions(Mode));
    CompareOne('ChatGPT', ModeName, 'developer', CodexText, CodexNames);

    CaptureClaude(Mode, True, ClaudeWith, ClaudeText);
    CaptureClaude(Mode, False, ClaudeWithout, ErrorText);
    Check('Claude ' + ModeName + ' attaches the same text either way', ClaudeText = ErrorText);
    ClaudeText := NormalizeAttached(ClaudeText);
    CompareClaude(ModeName, ClaudeText, ClaudeWith, ClaudeWithout);
  Finally
    ClaudeWithout.Free;
    ClaudeWith.Free;
    CodexNames.Free;
    GrokNames.Free;
  End;
End;

Var
  SettingsDir, ProjectDir, SelectError: String;
  PreviousEnum: TSkillFileEnumerator;
  Modes: TStringList;
  Service: TAssistantService;
  Mode: TAssistantMode;
Begin
  FailCount := 0;
  Repository := RepositoryRoot;
  Check('repository root found', Repository <> '');
  If Repository = '' Then
    Halt(1);
  SettingsDir := MakeTempRoot('settings');
  ProjectDir := MakeTempRoot('project');
  PreviousEnum := SkillFileEnumerator;
  Service := Nil;
  Modes := Nil;
  Try
    SetWorkflowSettingsDirectory(SettingsDir);
    WriteTextFile(ProjectDir + 'AGENTS.md', AgentsBody + LineEnding);
    FixtureSkillPath := ProjectDir + 'skills' + PathDelim + OfferSkillName + PathDelim + 'SKILL.md';
    WriteTextFile(FixtureSkillPath, SkillBody);
    Check('fixture project selected', AssistantTarget.SelectFolder(ExcludeTrailingPathDelimiter(ProjectDir), SelectError));
    If SelectError <> '' Then
      WriteLn('     ', SelectError);
    SetActivePlanRelativePath('Documents/Plan.md');
    SetDocumentRelativePath('Documents/Report.md');
    If Assigned(AssistantChatConfig) Then
      Begin
        AssistantChatConfig.RetainSkillModes(Nil);
        AssistantChatConfig.RetainSkillFiles(Nil);
        AssistantChatConfig.SetSkillFile(OfferSkillName, FixtureSkillPath);
        Modes := TStringList.Create;
        Modes.Add('inspect');
        Modes.Add('document');
        Modes.Add('plan');
        Modes.Add('build');
        Modes.Add('chat');
        AssistantChatConfig.SetSkillModes(OfferSkillName, Modes);
      End;
    SkillFileEnumerator := @EnumOfferSkill;
    Service := TAssistantService.Create;
    For Mode := Low(TAssistantMode) To High(TAssistantMode) Do
      CaptureMode(Service, Mode);
  Finally
    Service.Free;
    Modes.Free;
    SkillFileEnumerator := PreviousEnum;
    DeleteDirectory(ExcludeTrailingPathDelimiter(ProjectDir), False, False);
    DeleteDirectory(ExcludeTrailingPathDelimiter(SettingsDir), False, False);
  End;
  If FailCount = 0 Then
    WriteLn('All offer snapshots matched.')
  Else
    Begin
      WriteLn(FailCount, ' offer snapshot check(s) failed.');
      Halt(1);
    End;
End.
