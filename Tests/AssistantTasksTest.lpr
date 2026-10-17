Program AssistantTasksTest;

{ Catalog, settings section, and placeholder expansion for assistant tasks.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, fpjson, jsonparser, WorkflowSettings, AssistantTasks;

Var
  FailCount, TempSerial: Integer;
  SavedSettingsDir: String;

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

Function SettingsFile: String;
Begin
  Result := WorkflowSettingsPath;
End;

Function ReadSettings: String;
Var
  Lines: TStringList;
Begin
  Result := '';
  If Not FileExists(SettingsFile) Then
    Exit;
  Lines := TStringList.Create;
  Try
    Lines.LoadFromFile(SettingsFile);
    Result := Lines.Text;
  Finally
    Lines.Free;
  End;
End;

Procedure WriteSettings(Const Body: String);
Var
  Lines: TStringList;
Begin
  ForceDirectories(ExcludeTrailingPathDelimiter(WorkflowSettingsDirectory));
  Lines := TStringList.Create;
  Try
    Lines.Text := Body;
    Lines.SaveToFile(SettingsFile);
  Finally
    Lines.Free;
  End;
End;

Procedure UseTempSettings;
Var
  Dir: String;
Begin
  Inc(TempSerial);
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-tasks-' + IntToStr(TempSerial) + '-' +
    FormatDateTime('hhnnsszzz', Now);
  ForceDirectories(Dir);
  SetWorkflowSettingsDirectory(Dir);
End;

Function CatalogIndex(Const Tasks: TAssistantTaskArray; Const TaskId: String): Integer;
Begin
  Result := FindAssistantTask(Tasks, TaskId);
End;

Procedure CheckHas(Const Task: TAssistantTask; Const Needle: String);
Begin
  Check(Task.Id + ' has ' + Needle, Pos(Needle, Task.Prompt) > 0);
End;

Procedure CheckLacks(Const Task: TAssistantTask; Const Needle: String);
Begin
  Check(Task.Id + ' lacks ' + Needle, Pos(Needle, Task.Prompt) = 0);
End;

Procedure CheckPrompts(Const Tasks: TAssistantTaskArray);
Const
  BuildIds: Array[0..4] Of String = (
    'bug-fix', 'fix-compiler-errors', 'fix-compiler-hints', 'simplify-code', 'optimise-selection');
  InspectIds: Array[0..2] Of String = ('code-review', 'explain-selection', 'report-dead-code');
  DocumentIds: Array[0..1] Of String = ('technical-documentation', 'user-manual');
  BuildClosing = 'Make the smallest change that does the job.' + LineEnding +
    'Do not reformat the file.' + LineEnding +
    'Do not delete unused code.' + LineEnding +
    'Update the matching .lfm when a form change needs it.' + LineEnding +
    'run_compile after edits.' + LineEnding +
    'The visible reply is the cause and what changed.';
Var
  I: Integer;
  Task: TAssistantTask;
Begin
  Task := Tasks[CatalogIndex(Tasks, 'format-unit')];
  Check('format prompt empty', Task.Prompt = '');
  For I := 0 To High(BuildIds) Do
    Begin
      Task := Tasks[CatalogIndex(Tasks, BuildIds[I])];
      Check(BuildIds[I] + ' closing', Pos(BuildClosing, Task.Prompt) > 0);
      CheckLacks(Task, 'set_active_plan');
      CheckLacks(Task, 'switch to');
    End;
  For I := 0 To High(InspectIds) Do
    Begin
      Task := Tasks[CatalogIndex(Tasks, InspectIds[I])];
      CheckLacks(Task, 'run_compile');
      CheckLacks(Task, 'replace_in_file');
      CheckLacks(Task, 'write_file');
      CheckLacks(Task, 'write_markdown');
      CheckLacks(Task, 'set_active_plan');
    End;
  For I := 0 To High(DocumentIds) Do
    Begin
      Task := Tasks[CatalogIndex(Tasks, DocumentIds[I])];
      CheckLacks(Task, 'run_compile');
      CheckLacks(Task, 'replace_in_file');
      CheckLacks(Task, 'write_file');
      CheckLacks(Task, 'set_active_plan');
      CheckHas(Task, 'Do not edit source.');
      CheckHas(Task, 'The visible reply is a short summary.');
      CheckHas(Task, 'Do not use the plan format or Status lines.');
    End;
  For I := 0 To High(Tasks) Do
    Begin
      If Tasks[I].Kind = tkFormat Then
        Continue;
      CheckLacks(Tasks[I], 'Placeholder prompt');
      CheckHas(Tasks[I], 'Do not leave this mode.');
      CheckHas(Tasks[I], 'Do not edit the active plan.');
      CheckHas(Tasks[I], 'Do not change a Status line.');
      CheckHas(Tasks[I], 'Do not widen the scope.');
    End;
  Task := Tasks[CatalogIndex(Tasks, 'code-review')];
  CheckHas(Task, '{git_diff}');
  CheckHas(Task, '{git_status}');
  CheckHas(Task, 'Do not claim a truncated region was reviewed.');
  CheckHas(Task, 'Do not treat unsaved editor text as part of the diff.');
  Task := Tasks[CatalogIndex(Tasks, 'explain-selection')];
  CheckHas(Task, '{selection}');
  CheckHas(Task, 'Do not propose a rewrite unless asked.');
  Task := Tasks[CatalogIndex(Tasks, 'bug-fix')];
  CheckHas(Task, '{user_note}');
  CheckHas(Task, 'Do not invent a second bug.');
  Task := Tasks[CatalogIndex(Tasks, 'fix-compiler-errors')];
  CheckHas(Task, '{messages}');
  CheckHas(Task, 'Fix error, fatal, and panic lines only.');
  Task := Tasks[CatalogIndex(Tasks, 'fix-compiler-hints')];
  CheckHas(Task, 'Do not delete a method because a hint says it looks unused.');
  CheckHas(Task, 'Do not start an error fix in the same turn.');
  Task := Tasks[CatalogIndex(Tasks, 'simplify-code')];
  CheckHas(Task, '{selection}');
  CheckHas(Task, 'Do not optimise.');
  Task := Tasks[CatalogIndex(Tasks, 'report-dead-code')];
  CheckHas(Task, 'A text search is not a reference search.');
  CheckLacks(Task, 'find_references');
  Task := Tasks[CatalogIndex(Tasks, 'optimise-selection')];
  CheckHas(Task, 'The selection is the only edit region.');
  Task := Tasks[CatalogIndex(Tasks, 'technical-documentation')];
  CheckHas(Task, 'Documents/Technical.md');
  Task := Tasks[CatalogIndex(Tasks, 'user-manual')];
  CheckHas(Task, '{user_note}');
  CheckHas(Task, 'Documents/UserManual.md');
End;

Procedure CheckCatalog;
Var
  Tasks: TAssistantTaskArray;
  I, J: Integer;
Begin
  Tasks := CopyAssistantTaskCatalog;
  Check('catalog count', Length(Tasks) = 11);
  Check('code-review id', Tasks[0].Id = 'code-review');
  Check('explain-selection id', Tasks[1].Id = 'explain-selection');
  Check('bug-fix id', Tasks[2].Id = 'bug-fix');
  Check('fix-compiler-errors id', Tasks[3].Id = 'fix-compiler-errors');
  Check('fix-compiler-hints id', Tasks[4].Id = 'fix-compiler-hints');
  Check('simplify-code id', Tasks[5].Id = 'simplify-code');
  Check('report-dead-code id', Tasks[6].Id = 'report-dead-code');
  Check('optimise-selection id', Tasks[7].Id = 'optimise-selection');
  Check('format-unit id', Tasks[8].Id = 'format-unit');
  Check('technical-documentation id', Tasks[9].Id = 'technical-documentation');
  Check('user-manual id', Tasks[10].Id = 'user-manual');
  Check('code-review mode', TaskModeToStr(Tasks[0].Mode) = 'inspect');
  Check('explain-selection mode', TaskModeToStr(Tasks[1].Mode) = 'inspect');
  Check('bug-fix mode', TaskModeToStr(Tasks[2].Mode) = 'build');
  Check('fix-compiler-errors mode', TaskModeToStr(Tasks[3].Mode) = 'build');
  Check('fix-compiler-hints mode', TaskModeToStr(Tasks[4].Mode) = 'build');
  Check('simplify-code mode', TaskModeToStr(Tasks[5].Mode) = 'build');
  Check('report-dead-code mode', TaskModeToStr(Tasks[6].Mode) = 'inspect');
  Check('optimise-selection mode', TaskModeToStr(Tasks[7].Mode) = 'build');
  Check('format-unit kind', Tasks[8].Kind = tkFormat);
  Check('technical-documentation mode', TaskModeToStr(Tasks[9].Mode) = 'document');
  Check('user-manual mode', TaskModeToStr(Tasks[10].Mode) = 'document');
  Check('code-review scope', TaskScopeToStr(Tasks[0].Scope) = 'changed_files');
  Check('explain-selection scope', TaskScopeToStr(Tasks[1].Scope) = 'selection');
  Check('bug-fix scope', TaskScopeToStr(Tasks[2].Scope) = 'user_note');
  Check('fix-compiler-errors scope', TaskScopeToStr(Tasks[3].Scope) = 'messages');
  Check('fix-compiler-errors filter', TaskFilterToStr(Tasks[3].MessageFilter) = 'errors');
  Check('fix-compiler-hints filter', TaskFilterToStr(Tasks[4].MessageFilter) = 'hints');
  Check('simplify-code scope', TaskScopeToStr(Tasks[5].Scope) = 'active_editor');
  Check('report-dead-code scope', TaskScopeToStr(Tasks[6].Scope) = 'active_editor');
  Check('optimise-selection scope', TaskScopeToStr(Tasks[7].Scope) = 'selection');
  Check('format-unit scope', TaskScopeToStr(Tasks[8].Scope) = 'active_editor');
  Check('technical-documentation scope', TaskScopeToStr(Tasks[9].Scope) = 'active_editor');
  Check('user-manual scope', TaskScopeToStr(Tasks[10].Scope) = 'user_note');
  Check('code-review fresh', Tasks[0].FreshConversation);
  Check('code-review compile', Not Tasks[0].CompileFirst);
  Check('errors compile first', Tasks[3].CompileFirst And Not Tasks[3].FreshConversation);
  Check('hints compile first', Tasks[4].CompileFirst);
  For I := 0 To High(Tasks) Do
    Begin
      If I <> 0 Then
        Check('fresh only on code-review ' + Tasks[I].Id, Not Tasks[I].FreshConversation);
      If (I <> 3) And (I <> 4) Then
        Check('compile first only on compiler tasks ' + Tasks[I].Id, Not Tasks[I].CompileFirst);
      Check('enabled ' + Tasks[I].Id, Tasks[I].Enabled And Not Tasks[I].Hidden);
      Check('builtin id ' + Tasks[I].Id, Tasks[I].BuiltinId = Tasks[I].Id);
      Check('title ' + Tasks[I].Id, Trim(Tasks[I].Title) <> '');
      If Tasks[I].Kind = tkFormat Then
        Check('format prompt empty ' + Tasks[I].Id, Tasks[I].Prompt = '')
      Else
        Check('prompt present ' + Tasks[I].Id, Trim(Tasks[I].Prompt) <> '');
    End;
  Check('technical path', Tasks[9].DocumentPath = 'Documents/Technical.md');
  Check('manual path', Tasks[10].DocumentPath = 'Documents/UserManual.md');
  CheckPrompts(Tasks);
  For I := 0 To High(Tasks) Do
    For J := I + 1 To High(Tasks) Do
      Check('unique ' + Tasks[I].Id, Not SameText(Tasks[I].Id, Tasks[J].Id));
End;

Procedure CheckPaths;
Var
  ErrorText: String;
Begin
  Check('empty path', TaskDocumentPathIsValid('', 'Documents/Plan.md', ErrorText));
  Check('technical path', TaskDocumentPathIsValid('Documents/Technical.md',
    'Documents/Plan-20261017-023326.md', ErrorText));
  Check('reject parent', Not TaskDocumentPathIsValid('Documents/../Secret.md', '', ErrorText));
  Check('reject absolute', Not TaskDocumentPathIsValid('/Documents/Secret.md', '', ErrorText));
  Check('reject extension', Not TaskDocumentPathIsValid('Documents/Technical.txt', '', ErrorText));
  Check('reject active plan', Not TaskDocumentPathIsValid('Documents/Plan.md', 'Documents\Plan.md', ErrorText));
  Check('active plan message', ErrorText = 'Document path must not be the active plan.');
End;

Procedure CheckExpansion;
Var
  Tasks: TAssistantTaskArray;
  Task: TAssistantTask;
  Evidence: TAssistantTaskEvidence;
  Expanded, ErrorText, Note: String;
Begin
  Tasks := CopyAssistantTaskCatalog;
  Evidence.ProjectName := '';
  Evidence.ActiveFile := '';
  Evidence.Cursor := '';
  Evidence.Selection := '';
  Evidence.Messages := '';
  Evidence.GitStatus := '';
  Evidence.GitDiff := '';
  Evidence.UserNote := '';
  Task := Tasks[CatalogIndex(Tasks, 'explain-selection')];
  Check('missing selection', Not ExpandAssistantTaskPrompt(Task, Evidence, Expanded, ErrorText));
  Check('selection message', ErrorText = 'Selection is required.');
  Task := Tasks[CatalogIndex(Tasks, 'user-manual')];
  Check('missing note', Not ExpandAssistantTaskPrompt(Task, Evidence, Expanded, ErrorText));
  Check('note message', ErrorText = 'A note is required.');
  Task := Tasks[CatalogIndex(Tasks, 'format-unit')];
  Check('format has no prompt', Not ExpandAssistantTaskPrompt(Task, Evidence, Expanded, ErrorText));
  Check('format message', ErrorText = 'Format tasks have no prompt.');
  Task := Tasks[CatalogIndex(Tasks, 'simplify-code')];
  Task.Prompt := 'Status {git_status} diff {git_diff}.';
  Evidence.ActiveFile := 'Source/Foo.pas';
  Check('optional git outside changed_files', ExpandAssistantTaskPrompt(Task, Evidence, Expanded, ErrorText));
  Check('optional git text', Expanded = 'Status (none) diff (none).');
  Task.Prompt := 'See {not_a_field}.';
  Check('unknown placeholder', Not ExpandAssistantTaskPrompt(Task, Evidence, Expanded, ErrorText));
  Check('unknown message', ErrorText = 'Unknown placeholder {not_a_field}.');
  Task.Scope := tsNone;
  Task.Prompt := 'Sel {selection}';
  Evidence.Selection := StringOfChar('x', AssistantTaskSelectionMaxChars + 1);
  Check('cap selection', ExpandAssistantTaskPrompt(Task, Evidence, Expanded, ErrorText));
  Note := '[… truncated at ' + IntToStr(AssistantTaskSelectionMaxChars) + ' characters …]';
  Check('cap note', Pos(Note, Expanded) > 0);
  Check('cap length', Pos(StringOfChar('x', AssistantTaskSelectionMaxChars + 1), Expanded) = 0);
End;

Procedure CheckLoadAndReset;
Var
  Tasks, Again: TAssistantTaskArray;
  FromCatalog: Boolean;
  ErrorText, Before, Saved: String;
  ExplainIndex: Integer;
  Document, Section, Row: TJSONObject;
  Arr: TJSONArray;
Begin
  UseTempSettings;
  Check('missing section', LoadAssistantTasks(Tasks, FromCatalog, ErrorText));
  Check('from catalog', FromCatalog And (Length(Tasks) = 11));
  Check('missing does not write', Not FileExists(SettingsFile));

  WriteSettings('{"assistant":{"include_ide_context":true}}');
  Before := ReadSettings;
  Check('section absent', LoadAssistantTasks(Tasks, FromCatalog, ErrorText) And FromCatalog);
  Check('absent does not write', ReadSettings = Before);

  Row := TJSONObject.Create;
  Arr := TJSONArray.Create;
  Section := TJSONObject.Create;
  Document := TJSONObject.Create;
  Try
    Row.Add('id', 'code-review');
    Row.Add('title', 'Changed');
    Row.Add('mode', 'inspect');
    Row.Add('kind', 'prompt');
    Row.Add('scope', 'changed_files');
    Row.Add('fresh_conversation', True);
    Row.Add('enabled', True);
    Row.Add('hidden', True);
    Row.Add('builtin_id', 'code-review');
    Row.Add('prompt', 'Old prompt.');
    Arr.Add(Row);
    Row := TJSONObject.Create;
    Row.Add('id', 'my-task');
    Row.Add('title', 'Mine');
    Row.Add('mode', 'chat');
    Row.Add('kind', 'prompt');
    Row.Add('scope', 'none');
    Row.Add('enabled', True);
    Row.Add('hidden', False);
    Row.Add('prompt', 'Hello.');
    Arr.Add(Row);
    Section.Add('tasks', Arr);
    Row := TJSONObject.Create;
    Row.Add('keep', True);
    Document.Add('assistant', Row);
    Document.Add('assistant_tasks', Section);
    WriteSettings(Document.AsJSON);
  Finally
    Document.Free;
  End;
  Before := ReadSettings;
  Check('load saved', LoadAssistantTasks(Tasks, FromCatalog, ErrorText));
  Check('not from catalog', Not FromCatalog);
  Check('load does not write', ReadSettings = Before);
  Check('saved order', (Tasks[0].Id = 'code-review') And (Tasks[1].Id = 'my-task'));
  Check('hidden stays', Tasks[0].Hidden And (Tasks[0].Title = 'Changed'));
  Check('appended count', Length(Tasks) = 12);
  ExplainIndex := FindAssistantTask(Tasks, 'explain-selection');
  Check('explain appended', ExplainIndex > 1);
  Check('explain not hidden', Not Tasks[ExplainIndex].Hidden);
  Check('reset', ResetBuiltinAssistantTask(Tasks, 'code-review', ErrorText));
  Check('reset title', Tasks[0].Title = 'Code review');
  Check('reset clears hidden', Not Tasks[0].Hidden);
  Check('reset keeps place', (Tasks[0].Id = 'code-review') And (FindAssistantTask(Tasks, 'explain-selection') = ExplainIndex));
  Check('reset prompt', Tasks[0].Prompt = CopyAssistantTaskCatalog()[0].Prompt);
  Check('user reset refused', Not ResetBuiltinAssistantTask(Tasks, 'my-task', ErrorText));
  Check('user title kept', Tasks[1].Title = 'Mine');

  WriteSettings('{"assistant":{"keep":true},"assistant_tasks":{"tasks":"nope"}}');
  Before := ReadSettings;
  Check('invalid section', Not LoadAssistantTasks(Again, FromCatalog, ErrorText));
  Check('invalid keeps catalog', (Not FromCatalog) And (Length(Again) = 11));
  Check('invalid does not write', ReadSettings = Before);
  Check('invalid error', ErrorText <> '');

  UseTempSettings;
  Tasks := CopyAssistantTaskCatalog;
  Check('save catalog', SaveAssistantTasks(Tasks, ErrorText));
  Saved := ReadSettings;
  Document := TJSONObject(GetJSON(Saved));
  Try
    Check('assistant key absent on fresh save', Document.Find('assistant') = Nil);
    Section := TJSONObject(Document.Find('assistant_tasks'));
    Arr := TJSONArray(Section.Find('tasks'));
    Check('saved count', Arr.Count = 11);
    Row := TJSONObject(Arr.Items[8]);
    Check('format omits prompt', Row.Find('prompt') = Nil);
    Check('format kind', Row.Get('kind', '') = 'format');
    Row := TJSONObject(Arr.Items[0]);
    Check('review omits document path', Row.Find('document_path') = Nil);
    Check('review fresh', Row.Get('fresh_conversation', False));
    Row := TJSONObject(Arr.Items[9]);
    Check('technical path saved', Row.Get('document_path', '') = 'Documents/Technical.md');
  Finally
    Document.Free;
  End;

  WriteSettings('{"assistant":{"keep":true}}');
  Check('save keeps other section', SaveAssistantTasks(CopyAssistantTaskCatalog, ErrorText));
  Document := TJSONObject(GetJSON(ReadSettings));
  Try
    Check('assistant section kept', Document.Find('assistant') <> Nil);
  Finally
    Document.Free;
  End;
End;

Procedure ExpectReject(Const Title, TasksJson, Fragment: String);
Var
  Before: String;
  Loaded: TAssistantTaskArray;
  FromCatalog: Boolean;
  ErrorText: String;
Begin
  UseTempSettings;
  WriteSettings('{"assistant":{"keep":true},"assistant_tasks":{"tasks":[' + TasksJson + ']}}');
  Before := ReadSettings;
  Check(Title, Not LoadAssistantTasks(Loaded, FromCatalog, ErrorText));
  Check(Title + ' catalog', (Not FromCatalog) And (Length(Loaded) = 11));
  Check(Title + ' unchanged', ReadSettings = Before);
  Check(Title + ' error', Pos(Fragment, ErrorText) > 0);
End;

Function TaskJson(Const Id, ModeName, KindName, ScopeName, Prompt: String): String;
Begin
  Result := '{"id":"' + Id + '","title":"T","mode":"' + ModeName + '","kind":"' + KindName +
    '","scope":"' + ScopeName + '","prompt":"' + Prompt + '"}';
End;

Procedure CheckRejections;
Var
  Before, ErrorText: String;
  Loaded: TAssistantTaskArray;
  FromCatalog: Boolean;
Begin
  UseTempSettings;
  WriteSettings('{not json');
  Before := ReadSettings;
  Check('bad file', Not LoadAssistantTasks(Loaded, FromCatalog, ErrorText));
  Check('bad file catalog', (Not FromCatalog) And (Length(Loaded) = 11));
  Check('bad file unchanged', ReadSettings = Before);
  Check('bad file error', ErrorText = 'Task settings file is not valid JSON.');

  UseTempSettings;
  WriteSettings('{"assistant":{"keep":true},"assistant_tasks":[]}');
  Before := ReadSettings;
  Check('section type', Not LoadAssistantTasks(Loaded, FromCatalog, ErrorText));
  Check('section type unchanged', ReadSettings = Before);
  Check('section type error', ErrorText = 'Task settings section is not an object.');

  ExpectReject('duplicate id',
    TaskJson('code-review', 'inspect', 'prompt', 'none', 'A.') + ',' +
    TaskJson('code-review', 'inspect', 'prompt', 'none', 'B.'),
    'Duplicate task id');
  ExpectReject('unsafe id', TaskJson('bad id', 'inspect', 'prompt', 'none', 'A.'),
    'Task id is not a safe name.');
  ExpectReject('unknown mode', TaskJson('mine', 'fly', 'prompt', 'none', 'A.'),
    'Mode is not a known name.');
  ExpectReject('unknown kind', TaskJson('mine', 'inspect', 'dance', 'none', 'A.'),
    'Kind is not a known name.');
  ExpectReject('unknown scope', TaskJson('mine', 'inspect', 'prompt', 'world', 'A.'),
    'Scope is not a known name.');
  ExpectReject('empty prompt', TaskJson('mine', 'inspect', 'prompt', 'none', ''),
    'Prompt is required.');

  UseTempSettings;
  WriteSettings('{"assistant":{"keep":true}}');
  Before := ReadSettings;
  Loaded := CopyAssistantTaskCatalog;
  Loaded[0].Kind := tkPrompt;
  Loaded[0].Prompt := '';
  Check('save rejects empty prompt', Not SaveAssistantTasks(Loaded, ErrorText));
  Check('rejected save does not write', ReadSettings = Before);
  Check('temp dir is not the saved dir', WorkflowSettingsDirectory <> SavedSettingsDir);
End;

Procedure CheckRoundTrip;
Var
  Catalog, Saved, Loaded: TAssistantTaskArray;
  FromCatalog: Boolean;
  ErrorText: String;
  UserIndex, ReviewIndex, ExplainIndex: Integer;
  Document, Section: TJSONObject;
  Arr: TJSONArray;
Begin
  UseTempSettings;
  Check('round-trip uses temp dir', (WorkflowSettingsDirectory <> SavedSettingsDir) And
    (Pos('laz-tasks-', WorkflowSettingsDirectory) > 0));
  Catalog := CopyAssistantTaskCatalog;
  SetLength(Saved, 2);
  Saved[0] := Catalog[0];
  Saved[0].Title := 'Hidden review';
  Saved[0].Prompt := 'Hidden prompt.';
  Saved[0].Hidden := True;
  Saved[1].Id := 'my-task';
  Saved[1].Title := 'Mine';
  Saved[1].Summary := 'A user task.';
  Saved[1].Mode := tmChat;
  Saved[1].Kind := tkPrompt;
  Saved[1].Scope := tsNone;
  Saved[1].MessageFilter := mfNone;
  Saved[1].CompileFirst := False;
  Saved[1].FreshConversation := False;
  Saved[1].Enabled := True;
  Saved[1].Hidden := False;
  Saved[1].DocumentPath := '';
  Saved[1].BuiltinId := '';
  Saved[1].Prompt := 'Hello from the user.';
  Check('round-trip save', SaveAssistantTasks(Saved, ErrorText));
  Document := TJSONObject(GetJSON(ReadSettings));
  Try
    Section := TJSONObject(Document.Find('assistant_tasks'));
    Arr := TJSONArray(Section.Find('tasks'));
    Check('round-trip file count', Arr.Count = 2);
    Check('round-trip file hidden', TJSONObject(Arr.Items[0]).Get('hidden', False));
    Check('round-trip file user', TJSONObject(Arr.Items[1]).Get('id', '') = 'my-task');
  Finally
    Document.Free;
  End;
  Check('round-trip load', LoadAssistantTasks(Loaded, FromCatalog, ErrorText) And (Not FromCatalog));
  Document := TJSONObject(GetJSON(ReadSettings));
  Try
    Section := TJSONObject(Document.Find('assistant_tasks'));
    Arr := TJSONArray(Section.Find('tasks'));
    Check('round-trip load does not write merge', Arr.Count = 2);
  Finally
    Document.Free;
  End;
  ReviewIndex := FindAssistantTask(Loaded, 'code-review');
  UserIndex := FindAssistantTask(Loaded, 'my-task');
  ExplainIndex := FindAssistantTask(Loaded, 'explain-selection');
  Check('round-trip order', (ReviewIndex = 0) And (UserIndex = 1) And (ExplainIndex > 1));
  Check('round-trip hidden stays', Loaded[ReviewIndex].Hidden And (Loaded[ReviewIndex].Title = 'Hidden review'));
  Check('round-trip hidden prompt', Loaded[ReviewIndex].Prompt = 'Hidden prompt.');
  Check('round-trip user prompt', Loaded[UserIndex].Prompt = 'Hello from the user.');
  Check('round-trip user is not builtin', (Loaded[UserIndex].BuiltinId = '') And (Loaded[UserIndex].Title = 'Mine') And
    (Not Loaded[UserIndex].Hidden));
  Check('round-trip gains catalog id', (ExplainIndex >= 0) And (Not Loaded[ExplainIndex].Hidden));
  Check('round-trip length', Length(Loaded) = 12);
End;

Begin
  FailCount := 0;
  TempSerial := 0;
  SavedSettingsDir := WorkflowSettingsDirectory;
  Try
    CheckCatalog;
    CheckPaths;
    CheckExpansion;
    CheckLoadAndReset;
    CheckRejections;
    CheckRoundTrip;
  Finally
    SetWorkflowSettingsDirectory(SavedSettingsDir);
  End;
  Check('settings directory restored', WorkflowSettingsDirectory = SavedSettingsDir);
  If FailCount = 0 Then
    WriteLn('All assistant task checks passed.')
  Else
    WriteLn(FailCount, ' assistant task check(s) failed.');
  If FailCount <> 0 Then
    Halt(1);
End.
