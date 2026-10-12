Unit AssistantHarness;

{ Templated system prompt, skill catalog, AGENTS.md, and ephemeral todos (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantConversation, AssistantSkills;

Const
  AssistantAgentsFileName = 'AGENTS.md';
  AssistantAgentsMaxChars = 32000;

Type
  TAssistantTodoItem = Record
    Id: String;
    Content: String;
    Status: String;
  End;
  TAssistantTodoArray = Array Of TAssistantTodoItem;

  TAssistantHarness = Class
  Private
    FTodos: TAssistantTodoArray;
    Function ModeCaption(Mode: TAssistantMode): String;
    Function BuildWorkPolicy: String;
    Function BuildToolCalling: String;
    Function BuildIdeFusion: String;
    Function BuildCommunication: String;
    Function BuildFormatting: String;
    Function BuildModeOverlay(Mode: TAssistantMode; Const ActivePlanRel: String): String;
    Function AttachTaggedSkills(SkillNames: TStrings; Const ProjectRoot: String): String;
    Function BuildSkillsSection(Const ProjectRoot: String; SkillNames: TStrings): String;
    Function BuildProjectRules(Const ProjectRoot: String): String;
    Function BuildUserInfo(Const ProjectRoot: String): String;
    Function AttachSkillBody(Const SkillName, ProjectRoot, Reason: String): String;
    Function NormalizeTodoStatus(Const Value: String): String;
    Function FindTodoIndex(Const TodoId: String): Integer;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Function BuildSystemPrompt(Mode: TAssistantMode; SkillNames: TStrings; Const ProjectRoot, ActivePlanRel: String): String;
    Procedure ClearTurnTodos;
    Function TodoCount: Integer;
    Function TodoItem(Index: Integer): TAssistantTodoItem;
    Function ApplyTodoWrite(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
    Function ReadSkill(Const SkillName, ProjectRoot: String; Out ResultText, ErrorText: String): Boolean;
    Function FormatTodos: String;
  End;

Var
  WorkflowAssistantHarness: TAssistantHarness;

/// Short image-output section. Callers add it only when the turn offers write_image.
Function AssistantImageOutputPromptSection: String;

Implementation

Uses
  LazFileUtils, fpjson, jsonparser, WorkflowLog, LazIDEIntf, SrcEditorIntf, LCLVersion, AssistantPlan,
  AssistantConnections;

Constructor TAssistantHarness.Create;
Begin
  Inherited Create;
  FTodos := Nil;
End;

Destructor TAssistantHarness.Destroy;
Begin
  FTodos := Nil;
  Inherited Destroy;
End;

Function TAssistantHarness.ModeCaption(Mode: TAssistantMode): String;
Begin
  Case Mode Of
    amChat: Result := 'Chat';
    amDocument: Result := 'Document';
    amPlan: Result := 'Plan';
    amBuild: Result := 'Build';
  Else
    Result := 'Inspect';
  End;
End;

Function TAssistantHarness.BuildWorkPolicy: String;
Begin
  Result :=
    '<work_policy>' + LineEnding +
    'Finish the user''s request. Do not stop at a plan or a description when the mode allows the work.' + LineEnding +
    'Do not claim a compile, edit, or file write succeeded unless a tool result in this turn shows it.' + LineEnding +
    'Stay in the current mode''s tool gates. If the work needs a write you cannot do, say so and name Inspect / Document / Plan / Build.' + LineEnding +
    'Keep changes scoped to what was asked. Do not leave placeholders for unrelated work.' + LineEnding +
    '</work_policy>';
End;

Function TAssistantHarness.BuildToolCalling: String;
Begin
  Result :=
    '<tool_calling>' + LineEnding +
    'Prefer named tools over guessing file contents. Do not echo tool JSON to the user.' + LineEnding +
    'Use `grep` / `search_in_project` before a stack of `read_file` calls. Page large files with start_line/end_line.' + LineEnding +
    '`replace_in_file` needs an exact unique old_text match. Prefer small surgical hunks.' + LineEnding +
    '`run_compile` is quiet lazbuild by default; set ui=true only for a final IDE Messages check.' + LineEnding +
    'Use `read_skill` to load a catalogued SKILL.md. Use `todo_write` for the current Build turn''s short checklist.' + LineEnding +
    'Use `spawn_subagent` for parallel explore or Pascal review lenses (depth 1, at most 3 live at once; extras wait). ' +
    'Do not spawn for syntax (use `run_compile`) or every edit. Children cannot spawn children.' + LineEnding +
    '</tool_calling>';
End;

Function TAssistantHarness.BuildIdeFusion: String;
Begin
  Result :=
    '<ide_fusion>' + LineEnding +
    'Edits go through IDE buffers when the file is open (Undoable). Pair .pas and .lfm for forms.' + LineEnding +
    'Declaring a field in .pas does not create or wire the component. Events fire only when the matching .lfm has ' +
    '`object Name: TClass` and `OnEvent = MethodName`.' + LineEnding +
    'Prefer `ensure_form_component` for timers, buttons, actions. Never create ApiProbe/scratch/temp units.' + LineEnding +
    'TTimer.Interval is milliseconds (1000 = once per second).' + LineEnding +
    '</ide_fusion>';
End;

Function TAssistantHarness.BuildCommunication: String;
Begin
  Result :=
    '<communication>' + LineEnding +
    'Lead with the answer. The user did not see tool traces as a separate transcript; do not recap every call.' + LineEnding +
    'Keep chat short in Plan and Document mode: the Markdown file is the source of truth. Summarise what changed and where.' + LineEnding +
    '</communication>';
End;

Function TAssistantHarness.BuildFormatting: String;
Begin
  Result :=
    '<formatting>' + LineEnding +
    'Use Markdown only on the answer channel. Do not put the full plan or document body only in chat.' + LineEnding +
    '</formatting>';
End;

Function TAssistantHarness.BuildModeOverlay(Mode: TAssistantMode; Const ActivePlanRel: String): String;
Var
  PlanPath: String;
Begin
  PlanPath := Trim(ActivePlanRel);
  If PlanPath = '' Then
    PlanPath := 'Documents/Plan.md';
  Result := '<mode_overlay>' + LineEnding;
  Case Mode Of
    amChat:
      Result := Result +
        'You are in **Chat**. This is a general conversation with no project tools and no skill.' + LineEnding +
        'Do not claim you can read, search, or edit files.';
    amDocument:
      Result := Result +
        'You are the Project Assistant in **Document mode** for Free Pascal / Lazarus.' + LineEnding +
        'Write free-form Markdown with `write_markdown` / `update_markdown`. The user prompt decides the layout.' + LineEnding +
        'Do not use the assistant plan format, the plan identity line, or Status lines.' + LineEnding +
        'Do not call `set_active_plan`. Do not edit source (.pas/.lfm). Do not write the active plan.' + LineEnding +
        'Current document: **' + GetDocumentRelativePath + '**. ' +
        'If that is empty, the turn directive names a new Documents/Report file.' + LineEnding +
        'Chat is a short summary. The Markdown file is the source of truth when you produce or revise a document.';
    amPlan:
      Result := Result +
        'You are the Project Assistant in **Plan mode** for Free Pascal / Lazarus.' + LineEnding +
        'Write durable plan Markdown via `write_markdown` / `update_markdown`. Do not only paste the plan in chat.' + LineEnding +
        'Default / active plan path: **' + PlanPath + '**.' + LineEnding +
        AssistantPlanAuthoringRules + LineEnding +
        'Prefer `update_markdown` for Status: lines or a single section. Never edit source (.pas/.lfm) in Plan mode.';
    amBuild:
      Result := Result +
        'You are the Project Assistant in **Build mode** for Free Pascal / Lazarus.' + LineEnding +
        'Implement by calling tools. Workflow: grep/search → read → edit (.pas and .lfm) → run_compile → fix.' + LineEnding +
        AssistantPlanCompletionRules + LineEnding +
        'Behaviour and UI checks stay for manual review. Auto-complete does not run when the working root is a Git repository.' + LineEnding +
        'Use run_project to start the built executable with no debugger and no shell. Use run_tests for the enabled project test command. ' +
        'delete_path and rename_path stay inside the project root. Do not use a shell.' + LineEnding +
        'Use run_git for repository inspection, explicit staging and commits. Save authorized edits first; inspect status and staged diff, and exclude unrelated changes.' + LineEnding +
        'When the user instructs you in a conversation or active plan to commit changes automatically, carry out those commits after completing and validating the requested work. Do not ask again for already-authorized commits; tool approval settings still apply. Report the commit hash only after Git confirms success.' + LineEnding +
        'Read the active plan, including its overall instructions, before implementing a work package. Preserve automatic-commit instructions when writing or updating plans.' + LineEnding +
        'Stay on the active work package. Actionable plan items are `###` headings with a `Status:` line; ' +
        '`##` headings are context and must not receive a Status line.' + LineEnding +
        'Prefer Michell Free Pascal conventions.' + LineEnding +
        'On Review, fan out pascal-naming, pascal-structure, and pascal-review via spawn_subagent over changed files.';
  Else
    Result := Result +
      'You are the Project Assistant in **Inspect mode** for Free Pascal / Lazarus.' + LineEnding +
      'Read-only project tools. You may open a source file with `open_file` and search with `search_in_project` or `grep`.' + LineEnding +
      'You cannot call `write_file`, `replace_in_file`, `write_markdown`, `run_compile`, or `run_git`. ' +
      'Ask the user to switch to Document for a report or other Markdown, Plan for a build plan, or Build for source edits.' + LineEnding +
      'A skill body is attached only when that skill is tagged for this mode. Use `read_skill` for catalog entries that are not tagged.' + LineEnding +
      'Prefer the active editor context already in the user message when it includes the code under discussion.';
  End;
  Result := Result + LineEnding + '</mode_overlay>';
End;

Function TAssistantHarness.AttachSkillBody(Const SkillName, ProjectRoot, Reason: String): String;
Var
  Body, Err: String;
Begin
  Result := '';
  If Trim(SkillName) = '' Then
    Exit;
  If Not LoadSkillBody(SkillName, ProjectRoot, Body, Err) Then
    Begin
      Result := '(Skill "' + SkillName + '" could not be loaded: ' + Err + ')';
      Exit;
    End;
  Result :=
    '----- begin skill: ' + SkillName + ' -----' + LineEnding +
    Reason + LineEnding + LineEnding +
    Body + LineEnding +
    '----- end skill: ' + SkillName + ' -----';
End;

Function TAssistantHarness.AttachTaggedSkills(SkillNames: TStrings; Const ProjectRoot: String): String;
Var
  Bodies, Seen: TStringList;
  I: Integer;
  Name, Body: String;
Begin
  Result := '';
  If Not Assigned(SkillNames) Then
    Exit;
  Bodies := TStringList.Create;
  Seen := TStringList.Create;
  Try
    Seen.CaseSensitive := False;
    For I := 0 To SkillNames.Count - 1 Do
      Begin
        Name := Trim(SkillNames[I]);
        If (Name = '') Or (Seen.IndexOf(Name) >= 0) Then
          Continue;
        Seen.Add(Name);
        Body := AttachSkillBody(Name, ProjectRoot,
          'Tagged for this mode. Follow it when the work matches this skill.');
        If Body <> '' Then
          Bodies.Add(Body);
      End;
    Result := Trim(Bodies.Text);
  Finally
    Seen.Free;
    Bodies.Free;
  End;
End;

Function TAssistantHarness.BuildSkillsSection(Const ProjectRoot: String; SkillNames: TStrings): String;
Var
  Skills: TAssistantSkillList;
  Bodies: TStringList;
  Tagged: String;
Begin
  Skills := ListGuidanceDocuments(ProjectRoot);
  Bodies := TStringList.Create;
  Try
    Bodies.Add('<skills>');
    Bodies.Add('Catalog (name + description + when-to-use). Load a body with `read_skill` when you need it.');
    Bodies.Add(FormatSkillCatalog(Skills));
    Tagged := AttachTaggedSkills(SkillNames, ProjectRoot);
    If Tagged <> '' Then
      Bodies.Add(Tagged);
    Bodies.Add('</skills>');
    Result := Trim(Bodies.Text);
  Finally
    Bodies.Free;
  End;
End;

Function TAssistantHarness.BuildProjectRules(Const ProjectRoot: String): String;
Var
  Path, Body: String;
  SL: TStringList;
Begin
  Result := '<project_rules>' + LineEnding;
  Path := '';
  If Trim(ProjectRoot) <> '' Then
    Path := IncludeTrailingPathDelimiter(ProjectRoot) + AssistantAgentsFileName;
  If (Path = '') Or (Not FileExistsUTF8(Path)) Then
    Result := Result + '(No AGENTS.md in the project root. The plan Markdown remains the work-package source of truth.)'
  Else
    Begin
      SL := TStringList.Create;
      Try
        Try
          SL.LoadFromFile(Path);
          Body := Trim(SL.Text);
        Except
          Body := '';
        End;
      Finally
        SL.Free;
      End;
      If Body = '' Then
        Result := Result + '(AGENTS.md was empty or unreadable.)'
      Else
        Begin
          If Length(Body) > AssistantAgentsMaxChars Then
            Body := Copy(Body, 1, AssistantAgentsMaxChars) + LineEnding +
              '[AGENTS.md truncated at ' + IntToStr(AssistantAgentsMaxChars) + ' characters.]';
          Result := Result + 'From `' + AssistantAgentsFileName + '`:' + LineEnding + LineEnding + Body;
        End;
    End;
  Result := Result + LineEnding + '</project_rules>';
End;

Function TAssistantHarness.BuildUserInfo(Const ProjectRoot: String): String;
Var
  OSName, ActiveFile, Ver: String;
Begin
  {$IFDEF WINDOWS}
  OSName := 'Windows';
  {$ELSE}
    {$IFDEF DARWIN}
    OSName := 'macOS';
    {$ELSE}
    OSName := 'Linux';
    {$ENDIF}
  {$ENDIF}
  ActiveFile := '(none)';
  Ver := 'FPC ' + {$I %FPCVERSION%} + '; LCL ' + lcl_version;
  If Assigned(SourceEditorManagerIntf) And Assigned(SourceEditorManagerIntf.ActiveEditor) Then
    ActiveFile := SourceEditorManagerIntf.ActiveEditor.FileName;
  Result :=
    '<user_info>' + LineEnding +
    'OS: ' + OSName + LineEnding +
    'Project root: ' + Trim(ProjectRoot) + LineEnding +
    'Active file: ' + ActiveFile + LineEnding +
    'Compiler: ' + Ver + LineEnding +
    '</user_info>';
End;

Function AssistantImageOutputPromptSection: String;
Begin
  Result :=
    '<image_output>' + LineEnding +
    'Create still images only with `write_image`. Do not use `write_file` or `replace_in_file` for images. ' +
    'Prefer PNG for icons and UI art unless the user names another format. ' +
    'Pass the generated image through rather than describing a file that was not written.' + LineEnding +
    '</image_output>';
End;

Function TAssistantHarness.BuildSystemPrompt(Mode: TAssistantMode; SkillNames: TStrings; Const ProjectRoot, ActivePlanRel: String): String;
Var
  Parts: TStringList;
  Tagged: String;
Begin
  { Chat has no catalog, project rules, or tool policy. A tagged body is the only extra. }
  If Mode = amChat Then
    Begin
      Tagged := AttachTaggedSkills(SkillNames, ProjectRoot);
      If Tagged = '' Then
        Result :=
          'You are a helpful assistant in a general chat.' + LineEnding +
          'You have no project tools, no IDE access, and no attached skill.' + LineEnding +
          'Answer the user directly. Do not claim you can read, search, or edit files.' + LineEnding +
          'If the question needs the Lazarus project, say they can switch to Inspect, Plan, or Build.'
      Else
        Result :=
          'You are a helpful assistant in a general chat.' + LineEnding +
          'You have no project tools and no IDE access.' + LineEnding +
          'Answer the user directly. Do not claim you can read, search, or edit files.' + LineEnding +
          'If the question needs the Lazarus project, say they can switch to Inspect, Plan, or Build.' +
          LineEnding + LineEnding + Tagged;
      Exit;
    End;
  Parts := TStringList.Create;
  Try
    Parts.Add('You are the Lazarus Project Assistant (' + ModeCaption(Mode) + ' mode).');
    Parts.Add(BuildWorkPolicy);
    Parts.Add(BuildToolCalling);
    Parts.Add(BuildIdeFusion);
    Parts.Add(BuildCommunication);
    Parts.Add(BuildFormatting);
    Parts.Add(BuildModeOverlay(Mode, ActivePlanRel));
    If AssistantTurnOffersImageOutput(Mode) Then
      Parts.Add(AssistantImageOutputPromptSection);
    Parts.Add(BuildSkillsSection(ProjectRoot, SkillNames));
    Parts.Add(BuildProjectRules(ProjectRoot));
    Parts.Add(BuildUserInfo(ProjectRoot));
    Result := Trim(Parts.Text);
  Finally
    Parts.Free;
  End;
End;

Procedure TAssistantHarness.ClearTurnTodos;
Begin
  FTodos := Nil;
End;

Function TAssistantHarness.TodoCount: Integer;
Begin
  Result := Length(FTodos);
End;

Function TAssistantHarness.TodoItem(Index: Integer): TAssistantTodoItem;
Begin
  If (Index < 0) Or (Index > High(FTodos)) Then
    Begin
      Result.Id := '';
      Result.Content := '';
      Result.Status := '';
    End
  Else
    Result := FTodos[Index];
End;

Function TAssistantHarness.NormalizeTodoStatus(Const Value: String): String;
Var
  S: String;
Begin
  S := LowerCase(Trim(Value));
  S := StringReplace(S, ' ', '_', [rfReplaceAll]);
  If (S = 'in_progress') Or (S = 'in-progress') Then
    Result := 'in_progress'
  Else If (S = 'completed') Or (S = 'complete') Or (S = 'done') Then
    Result := 'completed'
  Else If (S = 'cancelled') Or (S = 'canceled') Then
    Result := 'cancelled'
  Else
    Result := 'pending';
End;

Function TAssistantHarness.FindTodoIndex(Const TodoId: String): Integer;
Var
  I: Integer;
Begin
  Result := -1;
  For I := 0 To High(FTodos) Do
    If SameText(FTodos[I].Id, TodoId) Then
      Begin
        Result := I;
        Exit;
      End;
End;

Function TAssistantHarness.FormatTodos: String;
Var
  I: Integer;
  Mark, Line: String;
Begin
  If Length(FTodos) = 0 Then
    Begin
      Result := '(No in-turn todos.)';
      Exit;
    End;
  Result := 'In-turn todos:' + LineEnding;
  For I := 0 To High(FTodos) Do
    Begin
      If FTodos[I].Status = 'completed' Then
        Mark := 'x'
      Else If FTodos[I].Status = 'cancelled' Then
        Mark := '-'
      Else If FTodos[I].Status = 'in_progress' Then
        Mark := '>'
      Else
        Mark := ' ';
      Line := '- [' + Mark + '] ' + FTodos[I].Id + ': ' + FTodos[I].Content + ' (' + FTodos[I].Status + ')';
      Result := Result + Line + LineEnding;
    End;
  Result := TrimRight(Result);
End;

Function TAssistantHarness.ApplyTodoWrite(Const ArgumentsJson: String; Out ResultText, ErrorText: String): Boolean;
Var
  Data, Node, ItemData: TJSONData;
  Obj: TJSONObject;
  Arr: TJSONArray;
  Merge: Boolean;
  I, Idx: Integer;
  Item: TAssistantTodoItem;
  Incoming: TAssistantTodoArray;
Begin
  Incoming := Nil;
  Result := False;
  ResultText := '';
  ErrorText := '';
  If Trim(ArgumentsJson) = '' Then
    Begin
      ErrorText := 'todo_write requires a JSON object with todos.';
      Exit;
    End;
  Data := Nil;
  Try
    Try
      Data := GetJSON(ArgumentsJson);
    Except
      On E: Exception Do
        Begin
          ErrorText := 'todo_write JSON is invalid: ' + E.Message;
          Exit;
        End;
    End;
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'todo_write requires a JSON object.';
        Exit;
      End;
    Obj := TJSONObject(Data);
    Merge := False;
    Node := Obj.Find('merge');
    If Assigned(Node) And (Node.JSONType = jtBoolean) Then
      Merge := Node.AsBoolean;
    Node := Obj.Find('todos');
    If Not Assigned(Node) Or (Not (Node Is TJSONArray)) Then
      Begin
        ErrorText := 'todo_write requires a todos array.';
        Exit;
      End;
    Arr := TJSONArray(Node);
    SetLength(Incoming, Arr.Count);
    For I := 0 To Arr.Count - 1 Do
      Begin
        Item.Id := '';
        Item.Content := '';
        Item.Status := 'pending';
        ItemData := Arr[I];
        If ItemData Is TJSONObject Then
          Begin
            Item.Id := Trim(TJSONObject(ItemData).Get('id', ''));
            Item.Content := Trim(TJSONObject(ItemData).Get('content', ''));
            Item.Status := NormalizeTodoStatus(TJSONObject(ItemData).Get('status', 'pending'));
          End;
        If Item.Id = '' Then
          Item.Id := IntToStr(I + 1);
        Incoming[I] := Item;
      End;
  Finally
    Data.Free;
  End;
  If Not Merge Then
    FTodos := Incoming
  Else
    For I := 0 To High(Incoming) Do
      Begin
        Idx := FindTodoIndex(Incoming[I].Id);
        If Idx >= 0 Then
          Begin
            If Incoming[I].Content <> '' Then
              FTodos[Idx].Content := Incoming[I].Content;
            FTodos[Idx].Status := Incoming[I].Status;
          End
        Else
          Begin
            SetLength(FTodos, Length(FTodos) + 1);
            FTodos[High(FTodos)] := Incoming[I];
          End;
      End;
  ResultText := FormatTodos;
  Result := True;
End;

Function TAssistantHarness.ReadSkill(Const SkillName, ProjectRoot: String; Out ResultText, ErrorText: String): Boolean;
Var
  Body: String;
Begin
  Result := LoadSkillBody(SkillName, ProjectRoot, Body, ErrorText);
  If Result Then
    ResultText := Body
  Else
    ResultText := '';
End;

Initialization

WorkflowAssistantHarness := TAssistantHarness.Create;

Finalization

FreeAndNil(WorkflowAssistantHarness);

End.
