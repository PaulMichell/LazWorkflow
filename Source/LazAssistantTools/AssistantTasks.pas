Unit AssistantTasks;

{ Named assistant tasks: catalog, settings section, and prompt expansion (c) 2026 Michell Computing.

  No forms and no IDE units. The section is assistant_tasks, not a field of TAssistantConfig.
  A missing section returns the catalog and is not written. A bad file keeps the catalog in memory,
  sets an error, and is not replaced. Format unit has no prompt.

  Size note: exceeds the 1000 line preference. The catalog, JSON section, and expansion are one
  settings unit. Splitting the prompt text out would hide the catalog from its loader.
  Reviewed 2026-10: no hidden sibling service identified. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Const
  AssistantTasksSection = 'assistant_tasks';
  AssistantTaskSelectionMaxChars = 16000;
  AssistantTaskMessagesMaxChars = 48000;
  AssistantTaskGitDiffMaxChars = 48000;
  AssistantTaskNoneText = '(none)';

Type
  TAssistantTaskMode = (tmInspect, tmDocument, tmPlan, tmBuild, tmChat);
  TAssistantTaskKind = (tkPrompt, tkFormat);
  TAssistantTaskScope = (tsNone, tsActiveEditor, tsSelection, tsChangedFiles, tsMessages, tsUserNote);
  TAssistantTaskMessageFilter = (mfNone, mfErrors, mfWarnings, mfHints, mfAll);

  TAssistantTask = Record
    Id: String;
    Title: String;
    Summary: String;
    Mode: TAssistantTaskMode;
    Kind: TAssistantTaskKind;
    Scope: TAssistantTaskScope;
    MessageFilter: TAssistantTaskMessageFilter;
    CompileFirst: Boolean;
    FreshConversation: Boolean;
    Enabled: Boolean;
    Hidden: Boolean;
    DocumentPath: String;
    BuiltinId: String;
    Prompt: String;
  End;
  TAssistantTaskArray = Array Of TAssistantTask;

  TAssistantTaskRequestKind = (trkNone, trkRun, trkInsert);

  { Returned when Run or Insert has a prepared request. The list does not send or format. }
  TAssistantTaskRequest = Record
    Kind: TAssistantTaskRequestKind;
    Task: TAssistantTask;
    Mode: TAssistantTaskMode;
    DisplayLabel: String;
    ApiText: String;
    FreshConversation: Boolean;
    DocumentPath: String;
  End;

  { When assigned, the Tasks list calls this instead of expanding with empty evidence.
    Return false and set ErrorText to leave the list open. }
  TPrepareAssistantTaskRequest = Function(Const Task: TAssistantTask; Kind: TAssistantTaskRequestKind;
    Out Request: TAssistantTaskRequest; Out ErrorText: String): Boolean;

  { Evidence the host already collected. There is no full-unit field: the model reads files itself. }
  TAssistantTaskEvidence = Record
    ProjectName: String;
    ActiveFile: String;
    Cursor: String;
    Selection: String;
    Messages: String;
    GitStatus: String;
    GitDiff: String;
    UserNote: String;
  End;

/// Same character rules as SkillNameIsSafe. Not a skill name.
Function TaskIdIsSafe(Const TaskId: String): Boolean;
Function TaskModeToStr(Mode: TAssistantTaskMode): String;
Function TryTaskModeFromStr(Const Text: String; Out Mode: TAssistantTaskMode): Boolean;
Function TaskKindToStr(Kind: TAssistantTaskKind): String;
Function TryTaskKindFromStr(Const Text: String; Out Kind: TAssistantTaskKind): Boolean;
Function TaskScopeToStr(Scope: TAssistantTaskScope): String;
Function TryTaskScopeFromStr(Const Text: String; Out Scope: TAssistantTaskScope): Boolean;
Function TaskFilterToStr(Filter: TAssistantTaskMessageFilter): String;
Function TryTaskFilterFromStr(Const Text: String; Out Filter: TAssistantTaskMessageFilter): Boolean;
Function CopyAssistantTaskCatalog: TAssistantTaskArray;
Function FindAssistantTask(Const Tasks: TAssistantTaskArray; Const TaskId: String): Integer;
/// Empty is valid. A non-empty path is relative, under Documents/, ends in .md, and has no .. segment.
/// Does not register the path as a plan. ActivePlanPath is compared after slash normalization.
Function TaskDocumentPathIsValid(Const DocumentPath, ActivePlanPath: String; Out ErrorText: String): Boolean;
Function ValidateAssistantTask(Const Task: TAssistantTask; Const ActivePlanPath: String; Out ErrorText: String): Boolean;
/// Appends catalog ids that are not already stored as Id or BuiltinId. Does not write. Returns how many were added.
Function MergeMissingCatalogTasks(Var Tasks: TAssistantTaskArray): Integer;
/// Missing section: catalog, FromCatalog true, no write.
/// A bad file or invalid section: catalog in memory, Result false, ErrorText set, no write.
/// A present section keeps saved order. A hidden built-in is not appended again.
Function LoadAssistantTasks(Out Tasks: TAssistantTaskArray; Out FromCatalog: Boolean; Out ErrorText: String): Boolean;
/// Replaces only the assistant_tasks section. Does not call TAssistantConfig.Save.
Function SaveAssistantTasks(Const Tasks: TAssistantTaskArray; Out ErrorText: String): Boolean;
/// Copies the catalog row onto that id and clears Hidden. Does not move the row.
Function ResetBuiltinAssistantTask(Var Tasks: TAssistantTaskArray; Const TaskId: String; Out ErrorText: String): Boolean;
/// Unknown {token} fails. A required empty value fails. An optional empty value becomes (none).
Function ExpandAssistantTaskPrompt(Const Task: TAssistantTask; Const Evidence: TAssistantTaskEvidence;
  Out Expanded, ErrorText: String): Boolean;
Procedure ClearAssistantTaskRequest(Out Request: TAssistantTaskRequest);

Var
  { Nil until the run unit assigns it. The list then uses that preparer. }
  PrepareAssistantTaskRequest: TPrepareAssistantTaskRequest;

Implementation

Uses
  fpjson, jsonparser, WorkflowSettings, AssistantSessionObserve;

Function TaskIdIsSafe(Const TaskId: String): Boolean;
Var
  I: Integer;
  C: Char;
Begin
  Result := False;
  If (TaskId = '') Or (Length(TaskId) > 64) Or (TaskId = '.') Or (TaskId = '..') Then
    Exit;
  For I := 1 To Length(TaskId) Do
    Begin
      C := TaskId[I];
      If Not (((C >= 'A') And (C <= 'Z')) Or ((C >= 'a') And (C <= 'z')) Or
         ((C >= '0') And (C <= '9')) Or (C = '.') Or (C = '_') Or (C = '-')) Then
        Exit;
    End;
  Result := True;
End;

Function TaskModeToStr(Mode: TAssistantTaskMode): String;
Begin
  Case Mode Of
    tmInspect: Result := 'inspect';
    tmDocument: Result := 'document';
    tmPlan: Result := 'plan';
    tmBuild: Result := 'build';
    tmChat: Result := 'chat';
  Else
    Result := 'inspect';
  End;
End;

Function TryTaskModeFromStr(Const Text: String; Out Mode: TAssistantTaskMode): Boolean;
Var
  Name: String;
Begin
  Name := LowerCase(Trim(Text));
  Result := True;
  If Name = 'inspect' Then
    Mode := tmInspect
  Else If Name = 'document' Then
    Mode := tmDocument
  Else If Name = 'plan' Then
    Mode := tmPlan
  Else If Name = 'build' Then
    Mode := tmBuild
  Else If Name = 'chat' Then
    Mode := tmChat
  Else
    Begin
      Mode := tmInspect;
      Result := False;
    End;
End;

Function TaskKindToStr(Kind: TAssistantTaskKind): String;
Begin
  Case Kind Of
    tkPrompt: Result := 'prompt';
    tkFormat: Result := 'format';
  Else
    Result := 'prompt';
  End;
End;

Function TryTaskKindFromStr(Const Text: String; Out Kind: TAssistantTaskKind): Boolean;
Var
  Name: String;
Begin
  Name := LowerCase(Trim(Text));
  Result := True;
  If Name = 'prompt' Then
    Kind := tkPrompt
  Else If Name = 'format' Then
    Kind := tkFormat
  Else
    Begin
      Kind := tkPrompt;
      Result := False;
    End;
End;

Function TaskScopeToStr(Scope: TAssistantTaskScope): String;
Begin
  Case Scope Of
    tsNone: Result := 'none';
    tsActiveEditor: Result := 'active_editor';
    tsSelection: Result := 'selection';
    tsChangedFiles: Result := 'changed_files';
    tsMessages: Result := 'messages';
    tsUserNote: Result := 'user_note';
  Else
    Result := 'none';
  End;
End;

Function TryTaskScopeFromStr(Const Text: String; Out Scope: TAssistantTaskScope): Boolean;
Var
  Name: String;
Begin
  Name := LowerCase(Trim(Text));
  Result := True;
  If Name = 'none' Then
    Scope := tsNone
  Else If Name = 'active_editor' Then
    Scope := tsActiveEditor
  Else If Name = 'selection' Then
    Scope := tsSelection
  Else If Name = 'changed_files' Then
    Scope := tsChangedFiles
  Else If Name = 'messages' Then
    Scope := tsMessages
  Else If Name = 'user_note' Then
    Scope := tsUserNote
  Else
    Begin
      Scope := tsNone;
      Result := False;
    End;
End;

Function TaskFilterToStr(Filter: TAssistantTaskMessageFilter): String;
Begin
  Case Filter Of
    mfErrors: Result := 'errors';
    mfWarnings: Result := 'warnings';
    mfHints: Result := 'hints';
    mfAll: Result := 'all';
  Else
    Result := '';
  End;
End;

Function TryTaskFilterFromStr(Const Text: String; Out Filter: TAssistantTaskMessageFilter): Boolean;
Var
  Name: String;
Begin
  Name := LowerCase(Trim(Text));
  Result := True;
  If Name = '' Then
    Filter := mfNone
  Else If Name = 'errors' Then
    Filter := mfErrors
  Else If Name = 'warnings' Then
    Filter := mfWarnings
  Else If Name = 'hints' Then
    Filter := mfHints
  Else If Name = 'all' Then
    Filter := mfAll
  Else
    Begin
      Filter := mfNone;
      Result := False;
    End;
End;

Function StayInTask: String;
Begin
  Result := 'Do not leave this mode. Do not edit the active plan. Do not change a Status line. Do not widen the scope.';
End;

Function BuildClosing: String;
Begin
  Result := 'Make the smallest change that does the job.' + LineEnding +
    'Do not reformat the file.' + LineEnding +
    'Do not delete unused code.' + LineEnding +
    'Update the matching .lfm when a form change needs it.' + LineEnding +
    'run_compile after edits.' + LineEnding +
    'The visible reply is the cause and what changed.';
End;

Function CodeReviewPrompt: String;
Begin
  Result := 'Review only the attached saved diff. Do not edit.' + LineEnding +
    'Do not claim a truncated region was reviewed. Name the omitted paths.' + LineEnding +
    'Do not treat unsaved editor text as part of the diff.' + LineEnding +
    'Group findings by severity. No per-line essays.' + LineEnding +
    'If there is nothing to report, say so in one line.' + LineEnding +
    StayInTask + LineEnding + LineEnding +
    'Saved status:' + LineEnding + '{git_status}' + LineEnding + LineEnding +
    'Saved diff:' + LineEnding + '{git_diff}';
End;

Function ExplainSelectionPrompt: String;
Begin
  Result := 'Explain the selection to a maintainer. Do not edit.' + LineEnding +
    'Do not propose a rewrite unless asked.' + LineEnding +
    'Explain only the selection. The file and cursor locate it; they are not a wider task.' + LineEnding +
    StayInTask + LineEnding + LineEnding +
    'Active file: {active_file}' + LineEnding +
    'Cursor: {cursor}' + LineEnding + LineEnding +
    '{selection}';
End;

Function BugFixPrompt: String;
Begin
  Result := 'The note is the bug. Do not invent a second bug.' + LineEnding +
    'If the note does not match the active file, read before editing and say which file you changed.' + LineEnding +
    StayInTask + LineEnding + LineEnding +
    'Active file: {active_file}' + LineEnding + LineEnding +
    '{user_note}' + LineEnding + LineEnding +
    BuildClosing;
End;

Function FixCompilerErrorsPrompt: String;
Begin
  Result := 'Fix error, fatal, and panic lines only.' + LineEnding +
    'Do not clean warnings, hints, or style in this turn.' + LineEnding +
    'Stop when run_compile reports no errors, or when a fix would be a guess. Name any error left.' + LineEnding +
    StayInTask + LineEnding + LineEnding +
    '{messages}' + LineEnding + LineEnding +
    BuildClosing;
End;

Function FixCompilerHintsPrompt: String;
Begin
  Result := 'The host has already refused this task if errors remain.' + LineEnding +
    'Fix hint and note lines that are real code issues.' + LineEnding +
    'Do not delete a method because a hint says it looks unused.' + LineEnding +
    'Do not start an error fix in the same turn.' + LineEnding +
    StayInTask + LineEnding + LineEnding +
    '{messages}' + LineEnding + LineEnding +
    BuildClosing;
End;

Function SimplifyCodePrompt: String;
Begin
  Result := 'Keep the behaviour. Prefer the active selection when one was attached. Otherwise use the active unit.' + LineEnding +
    'Do not optimise. Do not format.' + LineEnding +
    'If the selection is (none), there is no attached selection.' + LineEnding +
    'If the code is already direct, say so and do not edit.' + LineEnding +
    StayInTask + LineEnding + LineEnding +
    'Active file: {active_file}' + LineEnding + LineEnding +
    'Selection:' + LineEnding + '{selection}' + LineEnding + LineEnding +
    BuildClosing;
End;

Function ReportDeadCodePrompt: String;
Begin
  Result := 'Report only. Do not edit.' + LineEnding +
    'A text search is not a reference search.' + LineEnding +
    'Do not recommend deletion of published methods, .lfm event handlers, overrides, ' +
    'initialization or finalization references, or registered classes.' + LineEnding +
    'List candidates separately from confident findings.' + LineEnding +
    StayInTask + LineEnding + LineEnding +
    'Active file: {active_file}';
End;

Function OptimiseSelectionPrompt: String;
Begin
  Result := 'The selection is the only edit region.' + LineEnding +
    'Name the cost before editing: allocation in a loop, repeated string growth, or repeated work.' + LineEnding +
    'If there is no such cost, do not edit.' + LineEnding +
    StayInTask + LineEnding + LineEnding +
    '{selection}' + LineEnding + LineEnding +
    BuildClosing;
End;

Function TechnicalDocumentationPrompt: String;
Begin
  Result := 'Write or update Documents/Technical.md for a maintainer.' + LineEnding +
    'Do not edit source. Do not use the plan format or Status lines.' + LineEnding +
    'The visible reply is a short summary.' + LineEnding +
    StayInTask + LineEnding + LineEnding +
    'Active file: {active_file}';
End;

Function RemoveDeadCodePrompt: String;
Begin
  Result := 'Remove dead code from the active unit only.' + LineEnding +
    'Delete a declaration only when find_references was called with every project Pascal file, ' +
    'the tool did not truncate, and the result has no references.' + LineEnding +
    'If the project has more than 32 Pascal files, or the search did not cover them, report and do not delete.' + LineEnding +
    'Do not delete published methods, .lfm event handlers, overrides, initialization or finalization references, ' +
    'or registered classes.' + LineEnding +
    'A text search is not a reference search. Do not raise the 32-file cap.' + LineEnding +
    'run_compile after any deletion. If the compile fails, revert that deletion with the editor Undo path ' +
    'or a reversing edit in the same turn, and stop.' + LineEnding +
    StayInTask + LineEnding + LineEnding +
    'Active file: {active_file}' + LineEnding + LineEnding +
    BuildClosing;
End;

Function UserManualPrompt: String;
Begin
  Result := 'Write or update Documents/UserManual.md for an operator.' + LineEnding +
    'The note is the topic.' + LineEnding +
    'No implementation detail unless it changes what the user does.' + LineEnding +
    'Do not edit source. Do not use the plan format or Status lines.' + LineEnding +
    'The visible reply is a short summary.' + LineEnding +
    StayInTask + LineEnding + LineEnding +
    '{user_note}';
End;

Function MakeTask(Const TaskId, Title, Summary: String; Mode: TAssistantTaskMode; Kind: TAssistantTaskKind;
  Scope: TAssistantTaskScope; Filter: TAssistantTaskMessageFilter; Const DocumentPath, Prompt: String;
  CompileFirst, FreshConversation: Boolean): TAssistantTask;
Begin
  Result.Id := TaskId;
  Result.Title := Title;
  Result.Summary := Summary;
  Result.Mode := Mode;
  Result.Kind := Kind;
  Result.Scope := Scope;
  Result.MessageFilter := Filter;
  Result.CompileFirst := CompileFirst;
  Result.FreshConversation := FreshConversation;
  Result.Enabled := True;
  Result.Hidden := False;
  Result.DocumentPath := DocumentPath;
  Result.BuiltinId := TaskId;
  Result.Prompt := Prompt;
End;

Function CopyAssistantTaskCatalog: TAssistantTaskArray;
Begin
  SetLength(Result, 12);
  Result[0] := MakeTask('code-review', 'Code review', 'Review the saved diff. No edits.',
    tmInspect, tkPrompt, tsChangedFiles, mfNone, '', CodeReviewPrompt, False, True);
  Result[1] := MakeTask('explain-selection', 'Explain selection', 'Explain the selection. No edits.',
    tmInspect, tkPrompt, tsSelection, mfNone, '', ExplainSelectionPrompt, False, False);
  Result[2] := MakeTask('bug-fix', 'Bug fix', 'Fix the bug described in the note.',
    tmBuild, tkPrompt, tsUserNote, mfNone, '', BugFixPrompt, False, False);
  Result[3] := MakeTask('fix-compiler-errors', 'Fix compiler errors', 'Fix compiler errors only.',
    tmBuild, tkPrompt, tsMessages, mfErrors, '', FixCompilerErrorsPrompt, True, False);
  Result[4] := MakeTask('fix-compiler-hints', 'Fix compiler hints', 'Fix hints when the compile has no errors.',
    tmBuild, tkPrompt, tsMessages, mfHints, '', FixCompilerHintsPrompt, True, False);
  Result[5] := MakeTask('simplify-code', 'Simplify code', 'Simplify the active unit without changing behaviour.',
    tmBuild, tkPrompt, tsActiveEditor, mfNone, '', SimplifyCodePrompt, False, False);
  Result[6] := MakeTask('report-dead-code', 'Report dead code', 'Report unused-looking declarations. No edits.',
    tmInspect, tkPrompt, tsActiveEditor, mfNone, '', ReportDeadCodePrompt, False, False);
  Result[7] := MakeTask('optimise-selection', 'Optimise selection', 'Optimise the selection when a cost is clear.',
    tmBuild, tkPrompt, tsSelection, mfNone, '', OptimiseSelectionPrompt, False, False);
  { Format does not call the model. Mode stays a skill-grid word and is not sent. }
  Result[8] := MakeTask('format-unit', 'Format unit', 'Format the active Pascal unit. No model call.',
    tmInspect, tkFormat, tsActiveEditor, mfNone, '', '', False, False);
  Result[9] := MakeTask('technical-documentation', 'Technical documentation',
    'Update Documents/Technical.md for maintainers.',
    tmDocument, tkPrompt, tsActiveEditor, mfNone, 'Documents/Technical.md',
    TechnicalDocumentationPrompt, False, False);
  Result[10] := MakeTask('user-manual', 'User manual', 'Update Documents/UserManual.md for operators.',
    tmDocument, tkPrompt, tsUserNote, mfNone, 'Documents/UserManual.md',
    UserManualPrompt, False, False);
  Result[11] := MakeTask('remove-dead-code', 'Remove dead code',
    'Delete an unreferenced declaration only after a complete reference search.',
    tmBuild, tkPrompt, tsActiveEditor, mfNone, '', RemoveDeadCodePrompt, False, False);
  Result[11].Enabled := False;
End;

Function FindAssistantTask(Const Tasks: TAssistantTaskArray; Const TaskId: String): Integer;
Var
  I: Integer;
Begin
  Result := -1;
  For I := 0 To High(Tasks) Do
    If SameText(Tasks[I].Id, TaskId) Then
      Begin
        Result := I;
        Exit;
      End;
End;

Function NormalizeSlashes(Const Path: String): String;
Begin
  Result := StringReplace(Trim(Path), '\', '/', [rfReplaceAll]);
End;

Function TaskDocumentPathIsValid(Const DocumentPath, ActivePlanPath: String; Out ErrorText: String): Boolean;
Var
  Path, Plan, Segment: String;
  Index, StartAt: Integer;
Begin
  Result := False;
  ErrorText := '';
  Path := NormalizeSlashes(DocumentPath);
  If Path = '' Then
    Begin
      Result := True;
      Exit;
    End;
  Plan := NormalizeSlashes(ActivePlanPath);
  If (Path[1] = '/') Or ((Length(Path) >= 2) And (Path[2] = ':')) Then
    Begin
      ErrorText := 'Document path must be relative to the project.';
      Exit;
    End;
  If Copy(Path, 1, Length('Documents/')) <> 'Documents/' Then
    Begin
      ErrorText := 'Document path must start with Documents/.';
      Exit;
    End;
  If (Length(Path) < 3) Or (Copy(Path, Length(Path) - 2, 3) <> '.md') Then
    Begin
      ErrorText := 'Document path must end in .md.';
      Exit;
    End;
  StartAt := 1;
  While StartAt <= Length(Path) Do
    Begin
      Index := StartAt;
      While (Index <= Length(Path)) And (Path[Index] <> '/') Do
        Inc(Index);
      Segment := Copy(Path, StartAt, Index - StartAt);
      If (Segment = '') Or (Segment = '.') Or (Segment = '..') Then
        Begin
          ErrorText := 'Document path must not contain .. or an empty segment.';
          Exit;
        End;
      StartAt := Index + 1;
    End;
  If (Plan <> '') And (CompareText(Path, Plan) = 0) Then
    Begin
      ErrorText := 'Document path must not be the active plan.';
      Exit;
    End;
  Result := True;
End;

Function ValidateAssistantTask(Const Task: TAssistantTask; Const ActivePlanPath: String; Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := '';
  If Not TaskIdIsSafe(Task.Id) Then
    Begin
      ErrorText := 'Task id is not a safe name.';
      Exit;
    End;
  If Trim(Task.Title) = '' Then
    Begin
      ErrorText := 'Task title is required.';
      Exit;
    End;
  If (Task.BuiltinId <> '') And (Not TaskIdIsSafe(Task.BuiltinId)) Then
    Begin
      ErrorText := 'Built-in id is not a safe name.';
      Exit;
    End;
  If Task.Kind = tkFormat Then
    Begin
      If Trim(Task.Prompt) <> '' Then
        Begin
          ErrorText := 'A format task has no prompt.';
          Exit;
        End;
    End
  Else If Trim(Task.Prompt) = '' Then
    Begin
      ErrorText := 'Prompt is required.';
      Exit;
    End;
  If (Task.Scope = tsMessages) And (Task.MessageFilter = mfNone) Then
    Begin
      ErrorText := 'A messages task needs a message filter.';
      Exit;
    End;
  If Not TaskDocumentPathIsValid(Task.DocumentPath, ActivePlanPath, ErrorText) Then
    Exit;
  Result := True;
End;

Function StoresCatalogId(Const Tasks: TAssistantTaskArray; Const CatalogId: String): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  For I := 0 To High(Tasks) Do
    If SameText(Tasks[I].Id, CatalogId) Or SameText(Tasks[I].BuiltinId, CatalogId) Then
      Exit(True);
End;

Function MergeMissingCatalogTasks(Var Tasks: TAssistantTaskArray): Integer;
Var
  Catalog: TAssistantTaskArray;
  I, Before: Integer;
Begin
  Before := Length(Tasks);
  Catalog := CopyAssistantTaskCatalog;
  For I := 0 To High(Catalog) Do
    If Not StoresCatalogId(Tasks, Catalog[I].Id) Then
      Begin
        SetLength(Tasks, Length(Tasks) + 1);
        Tasks[High(Tasks)] := Catalog[I];
      End;
  Result := Length(Tasks) - Before;
End;

Function TaskIdsAreUnique(Const Tasks: TAssistantTaskArray; Out ErrorText: String): Boolean;
Var
  I, J: Integer;
Begin
  Result := False;
  ErrorText := '';
  For I := 0 To High(Tasks) Do
    For J := I + 1 To High(Tasks) Do
      If SameText(Tasks[I].Id, Tasks[J].Id) Then
        Begin
          ErrorText := 'Duplicate task id ' + Tasks[I].Id + '.';
          Exit;
        End;
  Result := True;
End;

Function ReadBoolean(Obj: TJSONObject; Const Key: String; Default: Boolean; Out Value: Boolean;
  Out ErrorText: String): Boolean;
Var
  Node: TJSONData;
Begin
  Result := False;
  Value := Default;
  ErrorText := '';
  Node := Obj.Find(Key);
  If Node = Nil Then
    Begin
      Result := True;
      Exit;
    End;
  If Node.JSONType <> jtBoolean Then
    Begin
      ErrorText := Key + ' must be a boolean.';
      Exit;
    End;
  Value := Node.AsBoolean;
  Result := True;
End;

Function ReadText(Obj: TJSONObject; Const Key: String; Out Value, ErrorText: String): Boolean;
Var
  Node: TJSONData;
Begin
  Result := False;
  Value := '';
  ErrorText := '';
  Node := Obj.Find(Key);
  If Node = Nil Then
    Begin
      Result := True;
      Exit;
    End;
  If Node.JSONType <> jtString Then
    Begin
      ErrorText := Key + ' must be a string.';
      Exit;
    End;
  Value := Node.AsString;
  Result := True;
End;

Function PrefixTaskError(Const TaskId, Detail: String): String;
Begin
  If TaskId = '' Then
    Result := Detail
  Else
    Result := 'Task ' + TaskId + ': ' + Detail;
End;

Function ReadTask(Obj: TJSONObject; Out Task: TAssistantTask; Out ErrorText: String): Boolean;
Var
  ModeText, KindText, ScopeText, FilterText: String;
Begin
  Result := False;
  ErrorText := '';
  Task.Id := '';
  Task.Title := '';
  Task.Summary := '';
  Task.Mode := tmInspect;
  Task.Kind := tkPrompt;
  Task.Scope := tsNone;
  Task.MessageFilter := mfNone;
  Task.CompileFirst := False;
  Task.FreshConversation := False;
  Task.Enabled := True;
  Task.Hidden := False;
  Task.DocumentPath := '';
  Task.BuiltinId := '';
  Task.Prompt := '';
  If Not ReadText(Obj, 'id', Task.Id, ErrorText) Then
    Exit;
  If Not ReadText(Obj, 'title', Task.Title, ErrorText) Then
    Begin
      ErrorText := PrefixTaskError(Task.Id, ErrorText);
      Exit;
    End;
  If Not ReadText(Obj, 'summary', Task.Summary, ErrorText) Then
    Begin
      ErrorText := PrefixTaskError(Task.Id, ErrorText);
      Exit;
    End;
  If Not ReadText(Obj, 'mode', ModeText, ErrorText) Then
    Begin
      ErrorText := PrefixTaskError(Task.Id, ErrorText);
      Exit;
    End;
  If Not TryTaskModeFromStr(ModeText, Task.Mode) Then
    Begin
      ErrorText := PrefixTaskError(Task.Id, 'Mode is not a known name.');
      Exit;
    End;
  If Not ReadText(Obj, 'kind', KindText, ErrorText) Then
    Begin
      ErrorText := PrefixTaskError(Task.Id, ErrorText);
      Exit;
    End;
  If Not TryTaskKindFromStr(KindText, Task.Kind) Then
    Begin
      ErrorText := PrefixTaskError(Task.Id, 'Kind is not a known name.');
      Exit;
    End;
  If Not ReadText(Obj, 'scope', ScopeText, ErrorText) Then
    Begin
      ErrorText := PrefixTaskError(Task.Id, ErrorText);
      Exit;
    End;
  If Not TryTaskScopeFromStr(ScopeText, Task.Scope) Then
    Begin
      ErrorText := PrefixTaskError(Task.Id, 'Scope is not a known name.');
      Exit;
    End;
  If Not ReadText(Obj, 'message_filter', FilterText, ErrorText) Then
    Begin
      ErrorText := PrefixTaskError(Task.Id, ErrorText);
      Exit;
    End;
  If Not TryTaskFilterFromStr(FilterText, Task.MessageFilter) Then
    Begin
      ErrorText := PrefixTaskError(Task.Id, 'Message filter is not a known name.');
      Exit;
    End;
  If Not ReadBoolean(Obj, 'compile_first', False, Task.CompileFirst, ErrorText) Then
    Begin
      ErrorText := PrefixTaskError(Task.Id, ErrorText);
      Exit;
    End;
  If Not ReadBoolean(Obj, 'fresh_conversation', False, Task.FreshConversation, ErrorText) Then
    Begin
      ErrorText := PrefixTaskError(Task.Id, ErrorText);
      Exit;
    End;
  If Not ReadBoolean(Obj, 'enabled', True, Task.Enabled, ErrorText) Then
    Begin
      ErrorText := PrefixTaskError(Task.Id, ErrorText);
      Exit;
    End;
  If Not ReadBoolean(Obj, 'hidden', False, Task.Hidden, ErrorText) Then
    Begin
      ErrorText := PrefixTaskError(Task.Id, ErrorText);
      Exit;
    End;
  If Not ReadText(Obj, 'document_path', Task.DocumentPath, ErrorText) Then
    Begin
      ErrorText := PrefixTaskError(Task.Id, ErrorText);
      Exit;
    End;
  If Not ReadText(Obj, 'builtin_id', Task.BuiltinId, ErrorText) Then
    Begin
      ErrorText := PrefixTaskError(Task.Id, ErrorText);
      Exit;
    End;
  If Not ReadText(Obj, 'prompt', Task.Prompt, ErrorText) Then
    Begin
      ErrorText := PrefixTaskError(Task.Id, ErrorText);
      Exit;
    End;
  If Not ValidateAssistantTask(Task, '', ErrorText) Then
    Begin
      ErrorText := PrefixTaskError(Task.Id, ErrorText);
      Exit;
    End;
  Result := True;
End;

Function ParseSection(Section: TJSONObject; Out Tasks: TAssistantTaskArray; Out ErrorText: String): Boolean;
Var
  Node: TJSONData;
  Arr: TJSONArray;
  I: Integer;
  Task: TAssistantTask;
Begin
  Result := False;
  SetLength(Tasks, 0);
  ErrorText := '';
  If Not Assigned(Section) Then
    Begin
      ErrorText := 'Task settings have no tasks array.';
      Exit;
    End;
  Node := Section.Find('tasks');
  If Not (Node Is TJSONArray) Then
    Begin
      ErrorText := 'Task settings have no tasks array.';
      Exit;
    End;
  Arr := TJSONArray(Node);
  For I := 0 To Arr.Count - 1 Do
    Begin
      If Not (Arr.Items[I] Is TJSONObject) Then
        Begin
          ErrorText := 'Task settings contain a row that is not an object.';
          SetLength(Tasks, 0);
          Exit;
        End;
      If Not ReadTask(TJSONObject(Arr.Items[I]), Task, ErrorText) Then
        Begin
          SetLength(Tasks, 0);
          Exit;
        End;
      SetLength(Tasks, Length(Tasks) + 1);
      Tasks[High(Tasks)] := Task;
    End;
  If Not TaskIdsAreUnique(Tasks, ErrorText) Then
    Begin
      SetLength(Tasks, 0);
      Exit;
    End;
  Result := True;
End;

Function TaskSettingsFileIsBad(Out ErrorText: String): Boolean;
Var
  Path: String;
  Lines: TStringList;
  Data, Node: TJSONData;
Begin
  Result := False;
  ErrorText := '';
  Path := WorkflowSettingsPath;
  If (Path = '') Or (Not FileExists(Path)) Then
    Exit;
  Lines := TStringList.Create;
  Data := Nil;
  Try
    Try
      Lines.LoadFromFile(Path);
    Except
      On E: Exception Do
        Begin
          ErrorText := 'Task settings file could not be read.';
          Result := True;
          Exit;
        End;
    End;
    Try
      Data := GetJSON(Lines.Text);
    Except
      Data := Nil;
    End;
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'Task settings file is not valid JSON.';
        Result := True;
        Exit;
      End;
    { ReadWorkflowSection only returns an object. A present value of another type must not look missing. }
    Node := TJSONObject(Data).Find(AssistantTasksSection);
    If (Node <> Nil) And (Not (Node Is TJSONObject)) Then
      Begin
        ErrorText := 'Task settings section is not an object.';
        Result := True;
      End;
  Finally
    Data.Free;
    Lines.Free;
  End;
End;

Function LoadAssistantTasks(Out Tasks: TAssistantTaskArray; Out FromCatalog: Boolean; Out ErrorText: String): Boolean;
Var
  Section: TJSONObject;
Begin
  Result := False;
  SetLength(Tasks, 0);
  FromCatalog := False;
  ErrorText := '';
  If WorkflowSettingsDirectory = '' Then
    Begin
      ErrorText := 'Workflow settings directory is not set.';
      Exit;
    End;
  If TaskSettingsFileIsBad(ErrorText) Then
    Begin
      Tasks := CopyAssistantTaskCatalog;
      FromCatalog := False;
      Exit;
    End;
  Section := ReadWorkflowSection(AssistantTasksSection);
  If Section = Nil Then
    Begin
      Tasks := CopyAssistantTaskCatalog;
      FromCatalog := True;
      Result := True;
      Exit;
    End;
  Try
    If Not ParseSection(Section, Tasks, ErrorText) Then
      Begin
        Tasks := CopyAssistantTaskCatalog;
        FromCatalog := False;
        Exit;
      End;
    MergeMissingCatalogTasks(Tasks);
    FromCatalog := False;
    Result := True;
  Finally
    Section.Free;
  End;
End;

Procedure AddText(Obj: TJSONObject; Const Key, Value: String);
Begin
  If Value <> '' Then
    Obj.Add(Key, Value);
End;

Function TaskToJson(Const Task: TAssistantTask): TJSONObject;
Begin
  Result := TJSONObject.Create;
  Result.Add('id', Task.Id);
  Result.Add('title', Task.Title);
  AddText(Result, 'summary', Task.Summary);
  Result.Add('mode', TaskModeToStr(Task.Mode));
  Result.Add('kind', TaskKindToStr(Task.Kind));
  Result.Add('scope', TaskScopeToStr(Task.Scope));
  AddText(Result, 'message_filter', TaskFilterToStr(Task.MessageFilter));
  Result.Add('compile_first', Task.CompileFirst);
  Result.Add('fresh_conversation', Task.FreshConversation);
  Result.Add('enabled', Task.Enabled);
  Result.Add('hidden', Task.Hidden);
  AddText(Result, 'builtin_id', Task.BuiltinId);
  AddText(Result, 'document_path', Task.DocumentPath);
  AddText(Result, 'prompt', Task.Prompt);
End;

Function TasksToSection(Const Tasks: TAssistantTaskArray): TJSONObject;
Var
  Arr: TJSONArray;
  I: Integer;
Begin
  Result := TJSONObject.Create;
  Arr := TJSONArray.Create;
  Result.Add('tasks', Arr);
  For I := 0 To High(Tasks) Do
    Arr.Add(TaskToJson(Tasks[I]));
End;

Function SaveAssistantTasks(Const Tasks: TAssistantTaskArray; Out ErrorText: String): Boolean;
Var
  I: Integer;
  Section: TJSONObject;
Begin
  Result := False;
  ErrorText := '';
  If Not TaskIdsAreUnique(Tasks, ErrorText) Then
    Exit;
  For I := 0 To High(Tasks) Do
    If Not ValidateAssistantTask(Tasks[I], '', ErrorText) Then
      Begin
        ErrorText := PrefixTaskError(Tasks[I].Id, ErrorText);
        Exit;
      End;
  Section := TasksToSection(Tasks);
  Try
    Result := WriteWorkflowSection(AssistantTasksSection, Section, ErrorText);
  Finally
    Section.Free;
  End;
  If Result Then
    AssistantSessionObserve.AssistantSessionObserve(asnTasks);
End;

Function ResetBuiltinAssistantTask(Var Tasks: TAssistantTaskArray; Const TaskId: String; Out ErrorText: String): Boolean;
Var
  Index, CatalogIndex, Other: Integer;
  Catalog: TAssistantTaskArray;
  CatalogId: String;
Begin
  Result := False;
  ErrorText := '';
  Index := FindAssistantTask(Tasks, TaskId);
  If Index < 0 Then
    Begin
      ErrorText := 'Task was not found.';
      Exit;
    End;
  CatalogId := Tasks[Index].BuiltinId;
  If CatalogId = '' Then
    CatalogId := Tasks[Index].Id;
  Catalog := CopyAssistantTaskCatalog;
  CatalogIndex := FindAssistantTask(Catalog, CatalogId);
  If CatalogIndex < 0 Then
    Begin
      ErrorText := 'Only a built-in task can be reset.';
      Exit;
    End;
  If Not SameText(Tasks[Index].Id, Catalog[CatalogIndex].Id) Then
    Begin
      Other := FindAssistantTask(Tasks, Catalog[CatalogIndex].Id);
      If (Other >= 0) And (Other <> Index) Then
        Begin
          ErrorText := 'Task id ' + Catalog[CatalogIndex].Id + ' is already in the list.';
          Exit;
        End;
    End;
  Tasks[Index] := Catalog[CatalogIndex];
  Tasks[Index].Hidden := False;
  Result := True;
End;

Function CapTaskText(Const Value: String; MaxChars: Integer): String;
Begin
  If Length(Value) <= MaxChars Then
    Result := Value
  Else
    Result := Copy(Value, 1, MaxChars) + LineEnding +
      '[… truncated at ' + IntToStr(MaxChars) + ' characters …]';
End;

Function RawPlaceholder(Const Name: String; Const Evidence: TAssistantTaskEvidence): String;
Begin
  If Name = 'project_name' Then
    Result := Evidence.ProjectName
  Else If Name = 'active_file' Then
    Result := Evidence.ActiveFile
  Else If Name = 'cursor' Then
    Result := Evidence.Cursor
  Else If Name = 'selection' Then
    Result := Evidence.Selection
  Else If Name = 'messages' Then
    Result := Evidence.Messages
  Else If Name = 'git_status' Then
    Result := Evidence.GitStatus
  Else If Name = 'git_diff' Then
    Result := Evidence.GitDiff
  Else If Name = 'user_note' Then
    Result := Evidence.UserNote
  Else
    Result := '';
End;

Function KnownPlaceholder(Const Name: String): Boolean;
Begin
  Result := (Name = 'project_name') Or (Name = 'active_file') Or (Name = 'cursor') Or (Name = 'selection') Or
    (Name = 'messages') Or (Name = 'git_status') Or (Name = 'git_diff') Or (Name = 'user_note');
End;

Function MissingRequiredEvidence(Const Task: TAssistantTask; Const Evidence: TAssistantTaskEvidence;
  Out ErrorText: String): Boolean;
Begin
  ErrorText := '';
  Case Task.Scope Of
    tsActiveEditor:
      If Trim(Evidence.ActiveFile) = '' Then
        ErrorText := 'Active editor is required.';
    tsSelection:
      If Trim(Evidence.Selection) = '' Then
        ErrorText := 'Selection is required.';
    tsChangedFiles:
      If (Trim(Evidence.GitStatus) = '') And (Trim(Evidence.GitDiff) = '') Then
        ErrorText := 'Git status or diff is required.';
    tsMessages:
      If Trim(Evidence.Messages) = '' Then
        ErrorText := 'Compiler messages are required.';
    tsUserNote:
      If Trim(Evidence.UserNote) = '' Then
        ErrorText := 'A note is required.';
  Else
    ErrorText := '';
  End;
  Result := ErrorText <> '';
End;

Function SubstitutedPlaceholder(Const Name: String; Const Evidence: TAssistantTaskEvidence): String;
Var
  Raw: String;
Begin
  Raw := RawPlaceholder(Name, Evidence);
  If Trim(Raw) = '' Then
    Result := AssistantTaskNoneText
  Else If Name = 'selection' Then
    Result := CapTaskText(Raw, AssistantTaskSelectionMaxChars)
  Else If Name = 'messages' Then
    Result := CapTaskText(Raw, AssistantTaskMessagesMaxChars)
  Else If Name = 'git_diff' Then
    Result := CapTaskText(Raw, AssistantTaskGitDiffMaxChars)
  Else
    Result := Raw;
End;

Procedure ClearAssistantTaskRequest(Out Request: TAssistantTaskRequest);
Begin
  Request.Kind := trkNone;
  Request.Mode := tmInspect;
  Request.DisplayLabel := '';
  Request.ApiText := '';
  Request.FreshConversation := False;
  Request.DocumentPath := '';
  Request.Task.Id := '';
  Request.Task.Title := '';
  Request.Task.Summary := '';
  Request.Task.Mode := tmInspect;
  Request.Task.Kind := tkPrompt;
  Request.Task.Scope := tsNone;
  Request.Task.MessageFilter := mfNone;
  Request.Task.CompileFirst := False;
  Request.Task.FreshConversation := False;
  Request.Task.Enabled := False;
  Request.Task.Hidden := False;
  Request.Task.DocumentPath := '';
  Request.Task.BuiltinId := '';
  Request.Task.Prompt := '';
End;

Function ExpandAssistantTaskPrompt(Const Task: TAssistantTask; Const Evidence: TAssistantTaskEvidence;
  Out Expanded, ErrorText: String): Boolean;
Var
  Index, CloseAt: Integer;
  Name: String;
Begin
  Result := False;
  Expanded := '';
  ErrorText := '';
  If Task.Kind = tkFormat Then
    Begin
      ErrorText := 'Format tasks have no prompt.';
      Exit;
    End;
  If MissingRequiredEvidence(Task, Evidence, ErrorText) Then
    Exit;
  Index := 1;
  While Index <= Length(Task.Prompt) Do
    Begin
      If Task.Prompt[Index] <> '{' Then
        Begin
          Expanded := Expanded + Task.Prompt[Index];
          Inc(Index);
          Continue;
        End;
      CloseAt := Index + 1;
      While (CloseAt <= Length(Task.Prompt)) And (Task.Prompt[CloseAt] <> '}') Do
        Inc(CloseAt);
      If CloseAt > Length(Task.Prompt) Then
        Begin
          ErrorText := 'Unclosed placeholder.';
          Expanded := '';
          Exit;
        End;
      Name := Copy(Task.Prompt, Index + 1, CloseAt - Index - 1);
      If Not KnownPlaceholder(Name) Then
        Begin
          ErrorText := 'Unknown placeholder {' + Name + '}.';
          Expanded := '';
          Exit;
        End;
      Expanded := Expanded + SubstitutedPlaceholder(Name, Evidence);
      Index := CloseAt + 1;
    End;
  Result := True;
End;

End.
