Program AssistantHarnessTest;

{ Console checks for installed skills, harness prompt, and todo_write (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Classes, SysUtils, FileUtil, LazFileUtils, AssistantConversation, AssistantConnections,
  AssistantSkills, AssistantHarness, AssistantConfig, WorkflowSettings;

Var
  FailCount: Integer;
  GuidanceNames, GuidancePaths: TStringList;

Procedure EnumGuidanceFiles(Names, Paths: TStrings);
Begin
  If Assigned(GuidanceNames) Then
    Names.AddStrings(GuidanceNames);
  If Assigned(GuidancePaths) Then
    Paths.AddStrings(GuidancePaths);
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

Procedure WriteTextFile(Const FileName, Body: String);
Var
  SL: TStringList;
  Dir: String;
Begin
  Dir := ExtractFilePath(FileName);
  If (Dir <> '') And (Not DirectoryExistsUTF8(Dir)) Then
    ForceDirectories(Dir);
  SL := TStringList.Create;
  Try
    SL.Text := Body;
    SL.SaveToFile(FileName);
  Finally
    SL.Free;
  End;
End;

Function MakeTempRoot: String;
Begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'lazworkflow-harness-' + FormatDateTime('hhnnsszzz', Now);
  Result := IncludeTrailingPathDelimiter(Result);
  If DirectoryExistsUTF8(ExcludeTrailingPathDelimiter(Result)) Then
    DeleteDirectory(ExcludeTrailingPathDelimiter(Result), False);
  ForceDirectories(Result);
End;

Procedure TestProjectSkillsAreNotDiscovered;
Var
  Root: String;
  Skills: TAssistantSkillList;
  I: Integer;
  Found: Boolean;
Begin
  Root := MakeTempRoot;
  Try
    WriteTextFile(Root + '.assistant' + PathDelim + 'skills' + PathDelim + 'alpha' + PathDelim + 'SKILL.md',
      '---' + LineEnding + 'name: alpha' + LineEnding + 'description: from assistant' + LineEnding +
      '---' + LineEnding + 'BODY-ASSISTANT' + LineEnding);
    WriteTextFile(Root + '.assistant' + PathDelim + 'skills' + PathDelim + 'beta' + PathDelim + 'SKILL.md',
      '---' + LineEnding + 'name: beta' + LineEnding + 'description: second skill' + LineEnding +
      '---' + LineEnding + 'BODY-BETA' + LineEnding);
    Check('a project root does not resolve a skill file', ResolveSkillFile('alpha', Root) = '');
    Check('a project root does not resolve a second skill file', ResolveSkillFile('beta', Root) = '');
    Skills := ListGuidanceDocuments(Root);
    Found := False;
    For I := 0 To High(Skills) Do
      If SameText(Skills[I].Name, 'alpha') Or SameText(Skills[I].Name, 'beta') Then
        Found := True;
    Check('an uninstalled project skill is not in the guidance list', Not Found);
  Finally
    DeleteDirectory(ExcludeTrailingPathDelimiter(Root), False);
  End;
End;

Procedure TestHarnessPrompt;
Var
  Root, Prompt, Body, Err: String;
  Harness: TAssistantHarness;
  Names: TStringList;
Begin
  Root := MakeTempRoot;
  Harness := TAssistantHarness.Create;
  Names := TStringList.Create;
  Try
    WriteTextFile(Root + 'AGENTS.md', 'Use PascalCase keywords in this repo.');
    WriteTextFile(Root + '.grok' + PathDelim + 'skills' + PathDelim + 'free-pascal-engineer' + PathDelim + 'SKILL.md',
      '---' + LineEnding + 'name: free-pascal-engineer' + LineEnding +
      'description: ignored project grok' + LineEnding + '---' + LineEnding +
      'DO NOT USE PROJECT GROK SKILL' + LineEnding);
    WriteTextFile(Root + '.assistant' + PathDelim + 'skills' + PathDelim + 'free-pascal-engineer' + PathDelim + 'SKILL.md',
      '---' + LineEnding + 'name: free-pascal-engineer' + LineEnding +
      'description: Michell Pascal style' + LineEnding + '---' + LineEnding +
      'ALWAYS USE PASCALCASE KEYWORDS.' + LineEnding);
    WriteTextFile(Root + '.assistant' + PathDelim + 'skills' + PathDelim + 'imagine' + PathDelim + 'SKILL.md',
      '---' + LineEnding + 'name: imagine' + LineEnding + 'description: image prompts' + LineEnding +
      'when-to-use: generating images' + LineEnding + '---' + LineEnding + 'IMAGINE BODY' + LineEnding);
    WriteTextFile(Root + '.assistant' + PathDelim + 'skills' + PathDelim + 'left-behind' + PathDelim + 'SKILL.md',
      '---' + LineEnding + 'name: left-behind' + LineEnding + 'description: not installed' + LineEnding +
      '---' + LineEnding + 'LEFT BEHIND' + LineEnding);
    AssistantChatConfig.SetSkillFile('free-pascal-engineer',
      Root + '.assistant' + PathDelim + 'skills' + PathDelim + 'free-pascal-engineer' + PathDelim + 'SKILL.md');
    AssistantChatConfig.SetSkillFile('imagine',
      Root + '.assistant' + PathDelim + 'skills' + PathDelim + 'imagine' + PathDelim + 'SKILL.md');
    Prompt := Harness.BuildSystemPrompt(amBuild, Names, Root, 'Documents/Plan.md');
    Check('build prompt names Build mode', Pos('Build mode', Prompt) > 0);
    Check('build prompt does not offer image files without a capable profile',
      (Pos('write_image', Prompt) = 0) And (Pos('<image_output>', Prompt) = 0) And
      (Pos('Create still images', Prompt) = 0) And
      (Pos('Prefer PNG for icons and UI art', Prompt) = 0) And
      (Pos('describing a file that was not written', Prompt) = 0) And
      (Pos('This model cannot write image files; say so, and do not invent a path or a PNG.', Prompt) > 0));
    Check('catalog lists imagine', Pos('imagine', Prompt) > 0);
    Check('catalog has when-to-use', Pos('generating images', Prompt) > 0);
    Check('an uninstalled project skill is not listed', Pos('LEFT BEHIND', Prompt) = 0);
    Check('an uninstalled project skill is not named', Pos('left-behind', Prompt) = 0);
    Check('build with no tags catalogs fpe and does not attach the body',
      (Pos('free-pascal-engineer', Prompt) > 0) And (Pos('ALWAYS USE PASCALCASE KEYWORDS', Prompt) = 0));
    Check('project .grok/skills is not loaded', Pos('DO NOT USE PROJECT GROK SKILL', Prompt) = 0);
    Check('AGENTS.md inlined', Pos('Use PascalCase keywords in this repo', Prompt) > 0);
    Check('work_policy section', Pos('<work_policy>', Prompt) > 0);
    Check('ide_fusion section', Pos('<ide_fusion>', Prompt) > 0);
    Names.Add('free-pascal-engineer');
    Prompt := Harness.BuildSystemPrompt(amBuild, Names, Root, 'Documents/Plan.md');
    Check('build with free-pascal-engineer tagged attaches its body', Pos('ALWAYS USE PASCALCASE KEYWORDS', Prompt) > 0);
    Names.Clear;
    Prompt := Harness.BuildSystemPrompt(amChat, Names, Root, '');
    Check('chat names general chat', Pos('general chat', Prompt) > 0);
    Check('chat with no tags contains neither the body nor the catalog',
      (Pos('ALWAYS USE PASCALCASE KEYWORDS', Prompt) = 0) And (Pos('IMAGINE BODY', Prompt) = 0) And
      (Pos('free-pascal-engineer', Prompt) = 0) And (Pos('<skills>', Prompt) = 0));
    Check('chat does not inline AGENTS.md', Pos('AGENTS.md', Prompt) = 0);
    Check('chat has no tool policy', Pos('<work_policy>', Prompt) = 0);
    Check('chat says this model cannot write image files',
      Pos('This model cannot write image files; say so, and do not invent a path or a PNG.', Prompt) > 0);
    Names.Add('imagine');
    Prompt := Harness.BuildSystemPrompt(amChat, Names, Root, '');
    Check('chat with imagine tagged contains IMAGINE BODY', Pos('IMAGINE BODY', Prompt) > 0);
    Check('chat with imagine has no work policy', Pos('<work_policy>', Prompt) = 0);
    Names.Clear;
    Prompt := Harness.BuildSystemPrompt(amInspect, Names, Root, '');
    Check('inspect does not dump fpe body', Pos('ALWAYS USE PASCALCASE KEYWORDS', Prompt) = 0);
    Check('inspect still catalogs fpe', Pos('free-pascal-engineer', Prompt) > 0);
    Check('inspect may open and search', (Pos('open_file', Prompt) > 0) And (Pos('search_in_project', Prompt) > 0));
    Check('inspect overlay refuses writes', Pos('write_file', Prompt) > 0);
    Names.Add('free-pascal-engineer');
    Prompt := Harness.BuildSystemPrompt(amInspect, Names, Root, '');
    Check('inspect tag attaches house skill', Pos('ALWAYS USE PASCALCASE KEYWORDS', Prompt) > 0);
    Names.Clear;
    Names.Add('imagine');
    Prompt := Harness.BuildSystemPrompt(amInspect, Names, Root, '');
    Check('inspect tag injects imagine body', Pos('IMAGINE BODY', Prompt) > 0);
    Check('read_skill loads imagine', Harness.ReadSkill('imagine', Root, Body, Err) And (Pos('IMAGINE BODY', Body) > 0));
    Check('read_skill ignores a file that is not installed',
      (Not Harness.ReadSkill('left-behind', Root, Body, Err)) And (Pos('LEFT BEHIND', Body) = 0));
  Finally
    If Assigned(AssistantChatConfig) Then
      Begin
        AssistantChatConfig.SetSkillFile('free-pascal-engineer', '');
        AssistantChatConfig.SetSkillFile('imagine', '');
      End;
    Names.Free;
    Harness.Free;
    DeleteDirectory(ExcludeTrailingPathDelimiter(Root), False);
  End;
End;

Procedure TestImageOutputPrompt;
Var
  Root, Settings, Prompt, Previous: String;
  Store: TAssistantConnections;
  Item: TAssistantConnection;
  Harness: TAssistantHarness;
  Names: TStringList;
Begin
  Root := MakeTempRoot;
  Settings := IncludeTrailingPathDelimiter(GetTempDir) + 'lazworkflow-harness-settings-' + FormatDateTime('hhnnsszzz', Now);
  ForceDirectories(Settings);
  Previous := WorkflowSettingsDirectory;
  SetWorkflowSettingsDirectory(Settings);
  Store := TAssistantConnections.Create(Settings);
  Harness := TAssistantHarness.Create;
  Names := TStringList.Create;
  Try
    Item := Store.AddStored('grok-prompt', 'Grok prompt', 'grok');
    Item.Model := 'kept-chat-model';
    Item.ImageOutput := False;
    Store.ActiveId := Item.Id;
    Check('flag-off prompt profile saved', Store.Save);
    Prompt := Harness.BuildSystemPrompt(amBuild, Names, Root, '');
    Check('flag off prompt does not offer write_image',
      (Pos('write_image', Prompt) = 0) And (Pos('<image_output>', Prompt) = 0) And
      (Pos('cannot write image files', Prompt) > 0));
    Item.ImageOutput := True;
    Item.ImageModel := AssistantGrokImageModel;
    Check('flag-on prompt profile saved', Store.Save);
    Prompt := Harness.BuildSystemPrompt(amBuild, Names, Root, '');
    Check('flag on prompt tells the model to call write_image once',
      (Pos('<image_output>', Prompt) > 0) And
      (Pos('Call `write_image` once with a short prompt and a project path.', Prompt) > 0) And
      (Pos('Do not pick or name an image model in the call.', Prompt) > 0) And
      (Pos('Do not spawn a subagent to draw.', Prompt) > 0) And
      (Pos('unless the result starts with Wrote.', Prompt) > 0) And
      (Pos('Exact pixels may differ across models.', Prompt) > 0) And
      (Pos('image_id', Prompt) = 0) And (Pos('cannot write image files', Prompt) = 0) And
      (Pos(AssistantGrokImageModel, Prompt) = 0) And (Pos('kept-chat-model', Prompt) = 0));
    Prompt := Harness.BuildSystemPrompt(amBuild, Names, Root, '', False);
    Check('a subagent prompt does not receive write_image',
      (Pos('<image_output>', Prompt) = 0) And (Pos('write_image', Prompt) = 0));
  Finally
    Names.Free;
    Harness.Free;
    Store.Free;
    SetWorkflowSettingsDirectory(Previous);
    DeleteDirectory(ExcludeTrailingPathDelimiter(Settings), False);
    DeleteDirectory(ExcludeTrailingPathDelimiter(Root), False);
  End;
End;

Procedure TestTodoWrite;
Var
  Harness: TAssistantHarness;
  OutText, Err: String;
  Ok: Boolean;
Begin
  Harness := TAssistantHarness.Create;
  Try
    Ok := Harness.ApplyTodoWrite(
      '{"todos":[{"id":"1","content":"read Foo","status":"pending"},{"id":"2","content":"patch Bar","status":"in_progress"}]}',
      OutText, Err);
    Check('todo replace ok', Ok And (Harness.TodoCount = 2));
    Check('todo lists in_progress', Pos('in_progress', OutText) > 0);
    Ok := Harness.ApplyTodoWrite('{"merge":true,"todos":[{"id":"1","status":"completed"}]}', OutText, Err);
    Check('todo merge ok', Ok And (Harness.TodoCount = 2) And (Harness.TodoItem(0).Status = 'completed'));
    Check('todo keeps other item', Harness.TodoItem(1).Content = 'patch Bar');
    Harness.ClearTurnTodos;
    Check('todo clear', Harness.TodoCount = 0);
  Finally
    Harness.Free;
  End;
End;

Procedure TestTurnMessages;
Var
  Root, Line: String;
  Store: TAssistantConversationStore;
  Turn: TConversationTurn;
  Entry: TConversationIndexEntry;
  Lines: TStringList;
Begin
  Root := MakeTempRoot;
  Store := TAssistantConversationStore.Create;
  Lines := TStringList.Create;
  Try
    Store.SetProjectRoot(ExcludeTrailingPathDelimiter(Root));
    Turn.Id := 'turn-1';
    Turn.Mode := 'build';
    Turn.Prompt := 'display prompt';
    Turn.Response := 'display answer';
    Turn.CreatedAt := '2026-09-23T12:00:00Z';
    Turn.MessagesJson := '[{"role":"assistant","content":"","toolCallId":"","toolCallsJson":"call-1"},' +
      '{"role":"tool","content":"tool body","toolCallId":"call-1","toolCallsJson":""}]';
    Check('turn stores model messages', Store.AppendTurn(Turn, Entry));
    Check('session file is not created', Not FileExistsUTF8(Root + '.lazgrokchat-session'));
    Check('readme is not generated', Not FileExistsUTF8(Root + '.assistant' + PathDelim + 'README.txt'));
    Lines.LoadFromFile(Root + '.assistant' + PathDelim + 'conversation.jsonl');
    Line := Lines.Text;
    Check('jsonl keeps the message list on the turn', (Pos('"messages":', Line) > 0) And (Pos('call-1', Line) > 0) And
      (Pos('tool body', Line) > 0));
    Store.Load;
    Check('reload restores message list', Store.GetTurn(0, Turn) And (Pos('call-1', Turn.MessagesJson) > 0) And
      (Pos('tool body', Turn.MessagesJson) > 0));
    Check('reload keeps display fields', (Turn.Prompt = 'display prompt') And (Turn.Response = 'display answer'));
  Finally
    Lines.Free;
    Store.Free;
    DeleteDirectory(ExcludeTrailingPathDelimiter(Root), False);
  End;
End;

Procedure TestGuidanceNames;
Var
  Root, SkillFile: String;
  Skills: TAssistantSkillList;
  I: Integer;
  Found: Boolean;
Begin
  Check('file stem keeps letters digits and hyphen', SkillNameFromFile('/tmp/My Notes (2).md') = 'My-Notes-2');
  Check('safe stem is unchanged', SkillNameFromFile('/tmp/free-pascal-engineer.md') = 'free-pascal-engineer');
  Check('unsafe stem falls back to guidance', SkillNameFromFile('/tmp/???.md') = 'guidance');
  Check('long stem is capped', Length(SkillNameFromFile('/tmp/' + StringOfChar('a', 80) + '.md')) = 64);
  Root := MakeTempRoot;
  Try
    SkillFile := Root + '.assistant' + PathDelim + 'skills' + PathDelim + 'alpha' + PathDelim + 'SKILL.md';
    WriteTextFile(SkillFile, '---' + LineEnding + 'name: alpha' + LineEnding + '---' + LineEnding + 'BODY' + LineEnding);
    Check('catalog name from SKILL.md', CatalogNameForSkillFile(SkillFile, Root) = 'alpha');
    Check('plain markdown is not a catalog skill', CatalogNameForSkillFile(Root + 'notes.md', Root) = '');
    Skills := ListGuidanceDocuments(Root);
    Found := False;
    For I := 0 To High(Skills) Do
      If SameText(Skills[I].Name, 'alpha') Then
        Found := True;
    Check('a project catalog file is not installed by itself', Not Found);
    WriteTextFile(Root + 'renamed-skill.md',
      '---' + LineEnding + 'name: alpha' + LineEnding + '---' + LineEnding + 'FILE BODY' + LineEnding);
    WriteTextFile(Root + 'plain-notes.md', 'No front matter.' + LineEnding);
    Check('document name is the front matter name', SkillDocumentName(Root + 'renamed-skill.md') = 'alpha');
    Check('missing name uses the file stem', SkillDocumentName(Root + 'plain-notes.md') = 'plain-notes');
    Check('missing file has no document name', SkillDocumentName(Root + 'absent.md') = '');
  Finally
    DeleteDirectory(ExcludeTrailingPathDelimiter(Root), False);
  End;
End;

Procedure TestAdoptedSkillName;
Var
  Root, NoteFile: String;
  Config: TAssistantConfig;
  Modes, Names: TStringList;
  PreviousEnum: TSkillFileEnumerator;
  Skills: TAssistantSkillList;
  I: Integer;
  FoundAlpha, FoundSuffix: Boolean;
Begin
  Root := MakeTempRoot;
  Config := TAssistantConfig.Create;
  Modes := TStringList.Create;
  Names := TStringList.Create;
  PreviousEnum := SkillFileEnumerator;
  Try
    NoteFile := Root + 'renamed-skill.md';
    WriteTextFile(Root + '.assistant' + PathDelim + 'skills' + PathDelim + 'alpha' + PathDelim + 'SKILL.md',
      '---' + LineEnding + 'name: alpha' + LineEnding + '---' + LineEnding + 'CATALOG' + LineEnding);
    WriteTextFile(NoteFile, '---' + LineEnding + 'name: alpha' + LineEnding + '---' + LineEnding + 'FILE' + LineEnding);
    Config.SetSkillFile('alpha-2', NoteFile);
    Modes.Add('chat');
    Config.SetSkillModes('alpha-2', Modes);
    Config.AdoptSkillDocumentNames;
    Names.Clear;
    Config.CollectSkillModeNames(Names);
    Check('suffixed skill key is forgotten', Names.IndexOf('alpha-2') < 0);
    Check('modes follow the document name', Names.IndexOf('alpha') >= 0);
    Check('file is stored under the document name', SameFileName(Config.SkillFilePath('alpha'), ExpandFileName(NoteFile)));
    GuidanceNames := TStringList.Create;
    GuidancePaths := TStringList.Create;
    Try
      GuidanceNames.Add('alpha-2');
      GuidancePaths.Add(NoteFile);
      SkillFileEnumerator := @EnumGuidanceFiles;
      Skills := ListGuidanceDocuments(Root);
      FoundAlpha := False;
      FoundSuffix := False;
      For I := 0 To High(Skills) Do
        Begin
          If SameText(Skills[I].Name, 'alpha') Then
            FoundAlpha := True;
          If SameText(Skills[I].Name, 'alpha-2') Then
            FoundSuffix := True;
        End;
      Check('guidance list uses the document name once', FoundAlpha And (Not FoundSuffix));
    Finally
      SkillFileEnumerator := PreviousEnum;
      GuidancePaths.Free;
      GuidanceNames.Free;
      GuidanceNames := Nil;
      GuidancePaths := Nil;
    End;
  Finally
    Modes.Free;
    Names.Free;
    Config.Free;
    DeleteDirectory(ExcludeTrailingPathDelimiter(Root), False);
  End;
End;

Function RepositoryRoot: String;
Var
  Dir, Parent: String;
  Pass: Integer;
Begin
  Result := '';
  For Pass := 1 To 2 Do
    Begin
      If Pass = 1 Then
        Dir := ExcludeTrailingPathDelimiter(GetCurrentDir)
      Else
        Dir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
      While Dir <> '' Do
        Begin
          If FileExistsUTF8(IncludeTrailingPathDelimiter(Dir) + 'Documents' + PathDelim + 'Plan.md') And
            FileExistsUTF8(IncludeTrailingPathDelimiter(Dir) + '.assistant' + PathDelim + 'skills' + PathDelim +
            AssistantMethodologySkillName + PathDelim + 'SKILL.md') Then
            Exit(IncludeTrailingPathDelimiter(Dir));
          Parent := ExcludeTrailingPathDelimiter(ExtractFilePath(Dir));
          If (Parent = '') Or (Parent = Dir) Then
            Break;
          Dir := Parent;
        End;
    End;
End;

Procedure TestDeclaredSkillModes;
Var
  Root, Prompt: String;
  Harness: TAssistantHarness;
  Names, Modes: TStringList;
Begin
  Root := MakeTempRoot;
  Harness := TAssistantHarness.Create;
  Names := TStringList.Create;
  Modes := TStringList.Create;
  Try
    WriteTextFile(Root + '.assistant' + PathDelim + 'skills' + PathDelim + 'declared-skill' + PathDelim + 'SKILL.md',
      '---' + LineEnding + 'name: declared-skill' + LineEnding + 'description: declared process' + LineEnding +
      'modes: plan, build' + LineEnding + '---' + LineEnding + 'DECLARED BODY' + LineEnding);
    WriteTextFile(Root + '.assistant' + PathDelim + 'skills' + PathDelim + 'secret-skill' + PathDelim + 'SKILL.md',
      '---' + LineEnding + 'name: secret-skill' + LineEnding + 'description: hidden process' + LineEnding +
      'modes: plan, build' + LineEnding + '---' + LineEnding + 'SECRET BODY' + LineEnding);
    WriteTextFile(Root + '.assistant' + PathDelim + 'skills' + PathDelim + AssistantRetiredBehaviourSkillName +
      PathDelim + 'SKILL.md',
      '---' + LineEnding + 'name: ' + AssistantRetiredBehaviourSkillName + LineEnding +
      'modes: plan, build' + LineEnding + '---' + LineEnding + 'BEHAVE BODY' + LineEnding);
    WriteTextFile(Root + '.assistant' + PathDelim + 'skills' + PathDelim + AssistantMethodologySkillName +
      PathDelim + 'SKILL.md',
      '---' + LineEnding + 'name: ' + AssistantMethodologySkillName + LineEnding +
      'modes: plan, build' + LineEnding + '---' + LineEnding + 'METHOD BODY' + LineEnding);
    Prompt := Harness.BuildSystemPrompt(amBuild, Names, Root, '');
    Check('a project skill file is not attached by itself', Pos('DECLARED BODY', Prompt) = 0);
    Check('a project root does not resolve a declared skill file', ResolveSkillFile('declared-skill', Root) = '');
    AssistantChatConfig.CollectSkillModeNames(Modes);
    Check('a project skill file is not written into settings', Modes.IndexOf('declared-skill') < 0);
    Check('build does not attach a chat-only absence error', Pos('could not be loaded', Prompt) = 0);
    Names.Add('missing-skill');
    Prompt := Harness.BuildSystemPrompt(amBuild, Names, Root, '');
    Check('absent skill is not injected', (Pos('could not be loaded', Prompt) = 0) And
      (Pos('missing-skill', Prompt) = 0));
    Names.Clear;
    Names.Add('secret-skill');
    Prompt := Harness.BuildSystemPrompt(amBuild, Names, Root, '');
    Check('naming an uninstalled file does not attach it', Pos('SECRET BODY', Prompt) = 0);
    AssistantChatConfig.SetSkillFile('declared-skill',
      Root + '.assistant' + PathDelim + 'skills' + PathDelim + 'declared-skill' + PathDelim + 'SKILL.md');
    AssistantChatConfig.SetSkillFile(AssistantRetiredBehaviourSkillName,
      Root + '.assistant' + PathDelim + 'skills' + PathDelim + AssistantRetiredBehaviourSkillName + PathDelim + 'SKILL.md');
    AssistantChatConfig.SetSkillFile(AssistantMethodologySkillName,
      Root + '.assistant' + PathDelim + 'skills' + PathDelim + AssistantMethodologySkillName + PathDelim + 'SKILL.md');
    Modes.Clear;
    Modes.Add('plan');
    Modes.Add('build');
    AssistantChatConfig.SetSkillModes('declared-skill', Modes);
    Names.Clear;
    AssistantChatConfig.CollectSkillsForMode('build', Names);
    Prompt := Harness.BuildSystemPrompt(amBuild, Names, Root, '');
    Check('an installed build tag attaches the file', Pos('DECLARED BODY', Prompt) > 0);
    Names.Clear;
    AssistantChatConfig.CollectSkillsForMode('chat', Names);
    Prompt := Harness.BuildSystemPrompt(amChat, Names, Root, '');
    Check('an installed skill is not attached on an untagged mode', Pos('DECLARED BODY', Prompt) = 0);
    Names.Clear;
    Names.Add(AssistantRetiredBehaviourSkillName);
    Names.Add(AssistantMethodologySkillName);
    Prompt := Harness.BuildSystemPrompt(amBuild, Names, Root, '');
    Check('replacement is attached beside the engineer tag list', Pos('METHOD BODY', Prompt) > 0);
    Check('retired BEHAVE is not attached with the replacement', Pos('BEHAVE BODY', Prompt) = 0);
    Names.Clear;
    Names.Add(AssistantRetiredBehaviourSkillName);
    Prompt := Harness.BuildSystemPrompt(amInspect, Names, Root, '');
    Check('retired BEHAVE still attaches when it is the only tag', Pos('BEHAVE BODY', Prompt) > 0);
  Finally
    Modes.Clear;
    If Assigned(AssistantChatConfig) Then
      Begin
        AssistantChatConfig.SetSkillModes('declared-skill', Modes);
        AssistantChatConfig.SetSkillFile('declared-skill', '');
        AssistantChatConfig.SetSkillFile(AssistantRetiredBehaviourSkillName, '');
        AssistantChatConfig.SetSkillFile(AssistantMethodologySkillName, '');
      End;
    Modes.Free;
    Names.Free;
    Harness.Free;
    DeleteDirectory(ExcludeTrailingPathDelimiter(Root), False);
  End;
End;

Procedure TestMethodologySkillResolves;
Var
  Root, Prompt, Body, Err: String;
  Harness: TAssistantHarness;
  Names: TStringList;
Begin
  Root := RepositoryRoot;
  Check('methodology skill is in this repository', Root <> '');
  If Root = '' Then
    Exit;
  Harness := TAssistantHarness.Create;
  Names := TStringList.Create;
  Try
    Check('methodology file is in this repository',
      FileExistsUTF8(Root + '.assistant' + PathDelim + 'skills' + PathDelim + AssistantMethodologySkillName +
      PathDelim + 'SKILL.md'));
    Check('an uninstalled project skill does not load',
      Not LoadSkillBody(AssistantMethodologySkillName, Root, Body, Err));
    Check('AGENTS.md was not written', Not FileExistsUTF8(Root + 'AGENTS.md'));
    Names.Add(AssistantDefaultSkillName);
    Prompt := Harness.BuildSystemPrompt(amBuild, Names, Root, 'Documents/Plan.md');
    Check('build does not attach an uninstalled project skill',
      Pos('----- begin skill: ' + AssistantMethodologySkillName + ' -----', Prompt) = 0);
    Check('build prompt does not attach a missing-skill error', Pos('could not be loaded', Prompt) = 0);
  Finally
    Names.Free;
    Harness.Free;
  End;
End;

Begin
  FailCount := 0;
  TestProjectSkillsAreNotDiscovered;
  TestHarnessPrompt;
  TestImageOutputPrompt;
  TestGuidanceNames;
  TestAdoptedSkillName;
  TestDeclaredSkillModes;
  TestMethodologySkillResolves;
  TestTodoWrite;
  TestTurnMessages;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantHarness tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantHarness test(s) failed.');
      Halt(1);
    End;
End.
