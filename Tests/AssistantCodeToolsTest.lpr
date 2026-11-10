Program AssistantCodeToolsTest;
{$mode objfpc}{$H+}
Uses cthreads, Interfaces, Forms, Classes, SysUtils, fpjson, jsonparser,
  LazIDEIntf, ProjectIntf, SrcEditorIntf, SynEdit, Types, CodeToolManager, CodeCache, DefineTemplates, BasicCodeTools,
  AssistantTestIDEHost, AssistantIDEWorkspace, AssistantToolBroker, AssistantProtocol;
Type
  TProject = Class(TLazProject)
  Public
    Path: String;
    Function GetProjectInfoFile: String; Override;
    Function GetMainFile: TLazProjectFile; Override;
  End;
  TEditor = Class(TSourceEditorInterface)
  Public
    Path, Text: String;
    Code: TCodeBuffer;
    Syn: TSynEdit;
    Function GetReadOnly: Boolean; Override;
    Procedure SelectText(Const StartPos, EndPos: TPoint); Override;
    Procedure SetCursorTextXY(Const Value: TPoint); Override;
    Procedure SetSelection(Const Value: String); Override;
    Procedure BeginUndoBlock; Override;
    Procedure EndUndoBlock; Override;
    Procedure BeginUpdate; Override;
    Procedure EndUpdate; Override;
    Function GetSourceText: String; Override;
    Function GetCodeToolsBuffer: TObject; Override;
  End;
  TManager = Class(TSourceEditorManagerInterface)
  Public
    Editor: TEditor;
    Function SourceEditorIntfWithFilename(Const Filename: String): TSourceEditorInterface; Override;
  End;
  TIDE = Class(TLazIDEInterface)
  Public
    Project: TProject;
    Editor: TEditor;
    PrepareCalls: Integer;
    Ready, ReentryBlocked: Boolean;
    ReentrantWorkspace: TAssistantIDEWorkspace;
    Function GetActiveProject: TLazProject; Override;
    Function BeginCodeTools: Boolean; Override;
  End;
  TObservedWorkspace = Class(TAssistantIDEWorkspace)
  Public
    Editor: TEditor;
    Project: TProject;
    Broker: TAssistantToolBroker;
    AfterLookup: Integer;
    ApprovalAction, ApprovalCalls, Saves: Integer;
    DefineOnApproval: TDefineTemplate;
    { The fake IDE cannot save. Counting the request is what the edit tools owe the IDE. }
    Function SaveEditor(Editor: TObject; Out ErrorText: String): Boolean; Override;
    Function Approve(Const Tool, Path, OldText, NewText: String): Boolean;
    Procedure ApplyLookupChange;
    Function SymbolContext(Const Path: String; Line, Column: Integer; Out ResultText, ErrorText: String): Boolean; Override;
    Function FindReferences(Const Path: String; Line, Column: Integer; SearchPaths: TStrings; MaxResults: Integer; Out ResultText, ErrorText: String): Boolean; Override;
    Function FindDeclaration(Const Path: String; Line, Column: Integer; Out ResultText, ErrorText: String): Boolean; Override;
  End;
Function TObservedWorkspace.SaveEditor(Editor: TObject; Out ErrorText: String): Boolean;
Begin
  ErrorText := '';
  Inc(Saves);
  Result := True;
End;
Function TObservedWorkspace.Approve(Const Tool, Path, OldText, NewText: String): Boolean;
Begin
  Inc(ApprovalCalls); Result := ApprovalAction <> 0;
  Case ApprovalAction Of
    2: Editor.Syn.Text := Editor.Syn.Text + '// approval edit';
    3: Broker.Cancel;
    4: Project.Path := Project.Path + '.changed';
    5: CodeToolBoss.DefineTree.Add(DefineOnApproval);
  End;
End;
Function TObservedWorkspace.FindDeclaration(Const Path: String; Line, Column: Integer; Out ResultText, ErrorText: String): Boolean;
Begin
  Result := Inherited FindDeclaration(Path, Line, Column, ResultText, ErrorText);
  If Result Then ApplyLookupChange;
End;
Procedure TObservedWorkspace.ApplyLookupChange;
Begin
  Case AfterLookup Of
    1: Editor.Text := Editor.Text + LineEnding + '// user edit';
    2: Project.Path := Project.Path + '.changed';
    3: Broker.Cancel;
  End;
End;
Function TObservedWorkspace.SymbolContext(Const Path: String; Line, Column: Integer; Out ResultText, ErrorText: String): Boolean;
Begin
  Result := Inherited SymbolContext(Path, Line, Column, ResultText, ErrorText);
  If Result Then ApplyLookupChange;
End;
Function TObservedWorkspace.FindReferences(Const Path: String; Line, Column: Integer; SearchPaths: TStrings; MaxResults: Integer; Out ResultText, ErrorText: String): Boolean;
Begin
  Result := Inherited FindReferences(Path, Line, Column, SearchPaths, MaxResults, ResultText, ErrorText);
  If Result Then ApplyLookupChange;
End;
Function TProject.GetProjectInfoFile: String;
Begin Result := Path; End;
Function TProject.GetMainFile: TLazProjectFile;
Begin Result := Nil; End;
Function TEditor.GetSourceText: String;
Begin If Assigned(Syn) Then Result := Syn.Text Else Result := Text; End;
Function TEditor.GetReadOnly: Boolean;
Begin Result := Assigned(Syn) And Syn.ReadOnly; End;
Procedure TEditor.SelectText(Const StartPos, EndPos: TPoint);
Begin Syn.BlockBegin := StartPos; Syn.BlockEnd := EndPos; End;
Procedure TEditor.SetCursorTextXY(Const Value: TPoint);
Begin Syn.LogicalCaretXY := Value; End;
Procedure TEditor.SetSelection(Const Value: String);
Begin Syn.SelText := Value; End;
Procedure TEditor.BeginUndoBlock;
Begin Syn.BeginUndoBlock; End;
Procedure TEditor.EndUndoBlock;
Begin Syn.EndUndoBlock; End;
Procedure TEditor.BeginUpdate;
Begin Syn.BeginUpdate; End;
Procedure TEditor.EndUpdate;
Begin Syn.EndUpdate; End;
Function TEditor.GetCodeToolsBuffer: TObject;
Begin Result := Code; End;
Function TManager.SourceEditorIntfWithFilename(Const Filename: String): TSourceEditorInterface;
Begin Result := Nil; If Filename = Editor.Path Then Result := Editor; End;
Function TIDE.GetActiveProject: TLazProject;
Begin Result := Project; End;
Function TIDE.BeginCodeTools: Boolean;
Var Reply, Err: String;
Begin
  If Assigned(ReentrantWorkspace) Then
    ReentryBlocked := Not ReentrantWorkspace.FindDeclaration(Editor.Path, 7, 6, Reply, Err) And (Pos('busy', Err) > 0);
  Inc(PrepareCalls); Result := Ready;
  If Result Then Editor.Code.Source := Editor.SourceText;
End;
Procedure Check(Const Name: String; OK: Boolean);
Begin If Not OK Then Begin WriteLn('FAIL ', Name); Halt(1); End; WriteLn('ok   ', Name); End;
Function Field(Const Value, Name: String): String;
Var Data: TJSONData;
Begin Data := GetJSON(Value); Try Result := Data.FindPath(Name).AsString; Finally Data.Free; End; End;
Function CountField(Const Value, Name: String): Integer;
Var Data: TJSONData;
Begin Data := GetJSON(Value); Try Result := Data.FindPath(Name).Count; Finally Data.Free; End; End;
Function BoolField(Const Value, Name: String): Boolean;
Var Data: TJSONData;
Begin Data := GetJSON(Value); Try Result := Data.FindPath(Name).AsBoolean; Finally Data.Free; End; End;
Var Root, Reply, Err, Run, Revision, Args, RefArgs, ReferenceLine, DiskDependency, RenameSource, ApplyArgs, ExpectedText: String; Define: TDefineTemplate; Id: TGuid;
  IDE: TIDE; Project: TProject; Editor: TEditor; Manager: TManager;
  Workspace: TObservedWorkspace; OtherWorkspace: TAssistantIDEWorkspace; Dependency: TCodeBuffer; Broker: TAssistantToolBroker; Calls: Integer; Stream: TFileStream;
Function PreviewFixture(Const Source, Identifier: String): Boolean;
Var FixtureLine, FixtureColumn: Integer;
Begin
  Editor.Syn.Text := Source;
  Run := Broker.BeginRun(awsProject);
  If Not Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"example.pas"}', Reply, Err) Then Exit(False);
  If Not SrcPosToLineCol(Source, Pos(Identifier, Source), FixtureLine, FixtureColumn) Then Exit(False);
  Args := '{"path":"example.pas","revision":"' + JsonEscapeText(Field(Reply, 'revision')) +
    '","line":' + IntToStr(FixtureLine) + ',"column":' + IntToStr(FixtureColumn) + ',"new_name":"LocalCount"}';
  Result := Broker.Execute(Run, 'lazarus_preview_local_rename', Args, Reply, Err);
End;
Begin
  Application.Initialize; Dependency := Nil;
  CreateGUID(Id); Root := GetTempDir + 'laz-codetools-' + GUIDToString(Id); ForceDirectories(Root);
  Project := TProject.Create(Nil); Project.Path := Root + '/project.lpi';
  Stream := TFileStream.Create(Project.Path, fmCreate); Stream.Free;
  Editor := TEditor.Create; Editor.Path := Root + '/example.pas';
  Editor.Code := CodeToolBoss.CreateFile(Editor.Path);
  Editor.Code.Source := 'unit Example; interface implementation end.';
  Editor.Text := 'unit Example;' + LineEnding + 'interface' + LineEnding +
    'const Answer = 42;' + LineEnding + 'implementation' + LineEnding +
    'procedure Test;' + LineEnding + 'begin' + LineEnding + '  if Answer = 42 then;' + LineEnding + 'end;' + LineEnding + 'end.';
  Manager := TManager.Create(Nil); Manager.Editor := Editor;
  IDE := TIDE.Create(Nil); IDE.Project := Project; IDE.Editor := Editor; IDE.Ready := True;
  LazarusIDE := IDE; SourceEditorManagerIntf := Manager;
  Workspace := TObservedWorkspace.Create; Broker := TAssistantToolBroker.Create(Workspace);
  OtherWorkspace := TAssistantIDEWorkspace.Create; IDE.ReentrantWorkspace := OtherWorkspace;
  Workspace.Editor := Editor; Workspace.Project := Project; Workspace.Broker := Broker;
  Try
    Run := Broker.BeginRun(awsReadOnly);
    Check('Ask advertises CodeTools lookup', Pos('lazarus_find_declaration', Broker.ToolsJson) > 0);
    If Not Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"example.pas"}', Reply, Err) Then
      Begin WriteLn(Err); Check('read unsaved source revision', False); End;
    Revision := Field(Reply, 'revision');
    Args := '{"path":"example.pas","revision":"' + JsonEscapeText(Revision) + '","line":7,"column":6}';
    If Not Broker.Execute(Run, 'lazarus_find_declaration', Args, Reply, Err) Then
      Begin WriteLn(Err); Check('real CodeTools resolves unsaved declaration', False); End;
    Check('real CodeTools resolves unsaved declaration', (Field(Reply, 'declaration.path') = Editor.Path)
      And (Field(Reply, 'declaration.line') = '3') And (Field(Reply, 'declaration.column') = '7'));
    Check('CodeTools reentry through another adapter is rejected', IDE.ReentryBlocked);
    IDE.ReentrantWorkspace := Nil;
    Check('result carries source revision and bounded context', (Field(Reply, 'sourceRevision') = Revision)
      And (Field(Reply, 'declaration.lineText') = 'const Answer = 42;'));
    Check('lookup synchronizes IDE cache without creating or saving a file', (IDE.PrepareCalls = 1) And Not FileExists(Editor.Path));
    Calls := IDE.PrepareCalls;
    Check('zero coordinate refused before CodeTools', Not Broker.Execute(Run, 'lazarus_find_declaration', StringReplace(Args, '"line":7', '"line":0', []), Reply, Err) And (IDE.PrepareCalls = Calls));
    Check('fractional coordinate refused', Not Broker.Execute(Run, 'lazarus_find_declaration', StringReplace(Args, '"column":6', '"column":6.5', []), Reply, Err) And (IDE.PrepareCalls = Calls));
    Check('out-of-range line refused', Not Broker.Execute(Run, 'lazarus_find_declaration', StringReplace(Args, '"line":7', '"line":700', []), Reply, Err) And (Pos('outside', Err) > 0));
    Editor.Text := StringReplace(Editor.Text, 'Answer', 'Changed', [rfReplaceAll]);
    Calls := IDE.PrepareCalls;
    Check('stale revision rejected before CodeTools', Not Broker.Execute(Run, 'lazarus_find_declaration', Args, Reply, Err) And (IDE.PrepareCalls = Calls));
    Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"example.pas"}', Reply, Err);
    Revision := Field(Reply, 'revision');
    Args := '{"path":"example.pas","revision":"' + JsonEscapeText(Revision) + '","line":7,"column":6}';
    Check('fresh revision resolves renamed unsaved identifier', Broker.Execute(Run, 'lazarus_find_declaration', Args, Reply, Err)
      And (Field(Reply, 'declaration.lineText') = 'const Changed = 42;'));
    ReferenceLine := #9 + '{café} if Choice > 0 then;';
    Editor.Text := 'unit Example;' + LineEnding + 'interface' + LineEnding +
      '{$ifdef ASSISTANT_TEST_SPECIAL}' + LineEnding + 'const Choice = 1;' + LineEnding +
      '{$else}' + LineEnding + 'const Choice = 2;' + LineEnding + '{$endif}' + LineEnding +
      'implementation' + LineEnding + 'procedure Test;' + LineEnding + 'begin' + LineEnding +
      ReferenceLine + LineEnding + 'end;' + LineEnding + 'end.';
    Define := TDefineTemplate.Create('assistant-test-special', '', 'ASSISTANT_TEST_SPECIAL', '1', da_Define);
    CodeToolBoss.DefineTree.Add(Define);
    Try
      Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"example.pas"}', Reply, Err);
      Revision := Field(Reply, 'revision');
      Args := '{"path":"example.pas","revision":"' + JsonEscapeText(Revision) + '","line":11,"column":' + IntToStr(Pos('Choice', ReferenceLine)) + '}';
      Check('lookup uses active CodeTools defines and byte columns after UTF-8/tab', Broker.Execute(Run, 'lazarus_find_declaration', Args, Reply, Err)
        And (Field(Reply, 'declaration.line') = '4'));
      Check('column inside UTF-8 character rejected', Not Broker.Execute(Run, 'lazarus_find_declaration',
        '{"path":"example.pas","revision":"' + JsonEscapeText(Revision) + '","line":11,"column":' + IntToStr(Pos('é', ReferenceLine) + 1) + '}', Reply, Err)
        And (Pos('UTF-8', Err) > 0));
    Finally CodeToolBoss.DefineTree.RemoveDefineTemplate(Define); End;
    Check('changed CodeTools defines select the other declaration', Broker.Execute(Run, 'lazarus_find_declaration', Args, Reply, Err)
      And (Field(Reply, 'declaration.line') = '6'));
    DiskDependency := 'unit System; interface implementation end.';
    Stream := TFileStream.Create(Root + '/system.pp', fmCreate);
    Try Stream.WriteBuffer(DiskDependency[1], Length(DiskDependency)); Finally Stream.Free; End;
    DiskDependency := 'unit Dependency; interface const Saved = 0; implementation end.';
    Stream := TFileStream.Create(Root + '/dependency.pas', fmCreate);
    Try Stream.WriteBuffer(DiskDependency[1], Length(DiskDependency)); Finally Stream.Free; End;
    Dependency := CodeToolBoss.LoadFile(Root + '/dependency.pas', True, False);
    Dependency.LockAutoDiskRevert; { as for an open unsaved IDE buffer }
    Dependency.Source := 'unit Dependency;' + LineEnding + 'interface' + LineEnding +
      'const Imported = 17;' + LineEnding + 'implementation' + LineEnding + 'end.';
    Editor.Text := 'unit Example;' + LineEnding + 'interface' + LineEnding + 'uses Dependency;' + LineEnding +
      'implementation' + LineEnding + 'procedure Test;' + LineEnding + 'begin' + LineEnding +
      '  if Imported > 0 then;' + LineEnding + 'end;' + LineEnding + 'end.';
    Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"example.pas"}', Reply, Err);
    Revision := Field(Reply, 'revision');
    Args := '{"path":"example.pas","revision":"' + JsonEscapeText(Revision) + '","line":7,"column":6}';
    If Not Broker.Execute(Run, 'lazarus_find_declaration', Args, Reply, Err) Then
      Begin WriteLn(Err); Check('lookup resolves declaration in another cached unit', False); End;
    Check('lookup resolves declaration in another cached unit', (Field(Reply, 'declaration.path') = Dependency.Filename)
      And (Field(Reply, 'declaration.lineText') = 'const Imported = 17;'));
    Check('Ask advertises reference and context tools', (Pos('lazarus_find_references', Broker.ToolsJson) > 0)
      And (Pos('lazarus_symbol_context', Broker.ToolsJson) > 0));
    Editor.Text := 'unit Example;' + LineEnding + 'interface' + LineEnding + 'uses Dependency;' + LineEnding +
      'implementation' + LineEnding + 'procedure Shadow;' + LineEnding + 'const Imported = 99;' + LineEnding +
      'begin' + LineEnding + '  if Imported > 0 then;' + LineEnding + 'end;' + LineEnding +
      'procedure Test;' + LineEnding + 'begin' + LineEnding + '  if Imported > 0 then;' + LineEnding +
      '  if Dependency.Imported > 0 then;' + LineEnding + '// Imported is mentioned in a comment' + LineEnding +
      '  if ''Imported'' = '''' then;' + LineEnding + '{$ifdef NEVER_DEFINED}' + LineEnding +
      '  if Imported > 0 then;' + LineEnding + '{$endif}' + LineEnding + 'end;' + LineEnding + 'end.';
    Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"example.pas"}', Reply, Err);
    Revision := Field(Reply, 'revision');
    Args := '{"path":"example.pas","revision":"' + JsonEscapeText(Revision) + '","line":12,"column":6}';
    RefArgs := Copy(Args, 1, Length(Args) - 1) + ',"search_paths":["example.pas","dependency.pas","example.pas"]}';
    If Not Broker.Execute(Run, 'lazarus_find_references', RefArgs, Reply, Err) Then
      Begin WriteLn(Err); Check('real CodeTools reference query succeeds', False); End;
    Check('semantic references exclude shadowed names, comments, strings, inactive code and declaration',
      (CountField(Reply, 'references.items') = 2) And (Field(Reply, 'references.items[0].line') = '12')
      And (Field(Reply, 'references.items[1].line') = '13'));
    Check('reference coverage deduplicates requested files', (CountField(Reply, 'references.requestedFiles') = 2)
      And (CountField(Reply, 'references.searchedFiles') = 2) And BoolField(Reply, 'references.completeForRequestedFiles')
      And Not BoolField(Reply, 'references.truncated'));
    Check('reference result limit explicitly marks incomplete coverage', Broker.Execute(Run, 'lazarus_find_references',
      Copy(RefArgs, 1, Length(RefArgs) - 1) + ',"max_results":1}', Reply, Err)
      And (CountField(Reply, 'references.items') = 1) And BoolField(Reply, 'references.truncated')
      And Not BoolField(Reply, 'references.completeForRequestedFiles'));
    DiskDependency := 'unit Extra;' + LineEnding + 'interface' + LineEnding + 'uses Dependency;' + LineEnding +
      'implementation' + LineEnding + 'procedure Test;' + LineEnding + 'begin' + LineEnding +
      '  if Imported > 0 then;' + LineEnding + 'end;' + LineEnding + 'end.';
    Stream := TFileStream.Create(Root + '/extra.pas', fmCreate);
    Try Stream.WriteBuffer(DiskDependency[1], Length(DiskDependency)); Finally Stream.Free; End;
    If Not Broker.Execute(Run, 'lazarus_find_references',
      Copy(Args, 1, Length(Args) - 1) + ',"search_paths":["extra.pas"]}', Reply, Err) Then
      Begin WriteLn(Err); Check('finds semantic usage in a closed project unit', False); End;
    Check('finds semantic usage in a closed project unit',
      (CountField(Reply, 'references.items') = 1) And (Field(Reply, 'references.items[0].path') = Root + '/extra.pas'));
    DiskDependency := 'unit Broken; interface uses Dependency; implementation procedure Test; begin if Imported > 0 then; { unterminated comment';
    Stream := TFileStream.Create(Root + '/broken.pas', fmCreate);
    Try Stream.WriteBuffer(DiskDependency[1], Length(DiskDependency)); Finally Stream.Free; End;
    If Not Broker.Execute(Run, 'lazarus_find_references',
      Copy(Args, 1, Length(Args) - 1) + ',"search_paths":["broken.pas","example.pas"]}', Reply, Err) Then
      Begin WriteLn(Err); Check('reference search reports parse failures', False); End;
    Check('parse failures cannot be reported as complete coverage',
      (CountField(Reply, 'references.failedFiles') = 1) And (CountField(Reply, 'references.searchedFiles') = 1)
      And (CountField(Reply, 'references.items') = 2) And Not BoolField(Reply, 'references.completeForRequestedFiles'));
    Check('missing search file returns failure', Not Broker.Execute(Run, 'lazarus_find_references',
      Copy(Args, 1, Length(Args) - 1) + ',"search_paths":["missing.pas"]}', Reply, Err) And (Reply = ''));
    Calls := IDE.PrepareCalls;
    Check('missing search scope is rejected before CodeTools', Not Broker.Execute(Run, 'lazarus_find_references', Args, Reply, Err) And (IDE.PrepareCalls = Calls));
    Check('invalid reference limit is rejected before CodeTools', Not Broker.Execute(Run, 'lazarus_find_references',
      Copy(RefArgs, 1, Length(RefArgs) - 1) + ',"max_results":0}', Reply, Err) And (IDE.PrepareCalls = Calls));
    Check('search path traversal refused', Not Broker.Execute(Run, 'lazarus_find_references',
      Copy(Args, 1, Length(Args) - 1) + ',"search_paths":["../outside.pas"]}', Reply, Err));
    If Not Broker.Execute(Run, 'lazarus_symbol_context', Args, Reply, Err) Then
      Begin WriteLn(Err); Check('symbol context query succeeds', False); End;
    Check('context uses unsaved source and declaration snippets',
      (Pos('Dependency.Imported', Field(Reply, 'symbol.sourceContext.text')) > 0)
      And (Pos('const Imported = 17;', Field(Reply, 'symbol.declarationContext.text')) > 0)
      And (Field(Reply, 'symbol.hint') <> ''));
    Editor.Text := Editor.Text + LineEnding + '// change'; Calls := IDE.PrepareCalls;
    Check('stale references and context rejected before CodeTools',
      Not Broker.Execute(Run, 'lazarus_find_references', RefArgs, Reply, Err)
      And Not Broker.Execute(Run, 'lazarus_symbol_context', Args, Reply, Err) And (IDE.PrepareCalls = Calls));
    Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"example.pas"}', Reply, Err);
    Revision := Field(Reply, 'revision');
    Args := '{"path":"example.pas","revision":"' + JsonEscapeText(Revision) + '","line":12,"column":6}';
    Workspace.AfterLookup := 1;
    Check('context source change discards result', Not Broker.Execute(Run, 'lazarus_symbol_context', Args, Reply, Err)
      And (Reply = '') And (Pos('Source changed', Err) > 0));
    Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"example.pas"}', Reply, Err);
    Revision := Field(Reply, 'revision');
    Args := '{"path":"example.pas","revision":"' + JsonEscapeText(Revision) + '","line":12,"column":6,"search_paths":["example.pas"]}';
    Workspace.AfterLookup := 3;
    Check('reference cancellation discards result', Not Broker.Execute(Run, 'lazarus_find_references', Args, Reply, Err)
      And (Reply = '') And (Pos('Workspace/run changed', Err) > 0));
    Workspace.AfterLookup := 0; Run := Broker.BeginRun(awsReadOnly);
    { Restore the simple query used by the declaration lifecycle regressions. }
    Editor.Text := 'unit Example;' + LineEnding + 'interface' + LineEnding + 'uses Dependency;' + LineEnding +
      'implementation' + LineEnding + 'procedure Test;' + LineEnding + 'begin' + LineEnding +
      '  if Imported > 0 then;' + LineEnding + 'end;' + LineEnding + 'end.';
    Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"example.pas"}', Reply, Err);
    Revision := Field(Reply, 'revision');
    Args := '{"path":"example.pas","revision":"' + JsonEscapeText(Revision) + '","line":7,"column":6}';
    IDE.Ready := False;
    Check('busy IDE produces explicit failure', Not Broker.Execute(Run, 'lazarus_find_declaration', Args, Reply, Err) And (Pos('prepare CodeTools', Err) > 0));
    IDE.Ready := True;
    Broker.Cancel; Calls := IDE.PrepareCalls;
    Check('cancel prevents semantic work', Not Broker.Execute(Run, 'lazarus_find_declaration', Args, Reply, Err) And (IDE.PrepareCalls = Calls));
    Run := Broker.BeginRun(awsReadOnly);
    Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"example.pas"}', Reply, Err);
    Revision := Field(Reply, 'revision');
    Args := '{"path":"example.pas","revision":"' + JsonEscapeText(Revision) + '","line":7,"column":6}';
    Workspace.AfterLookup := 1;
    Check('source change during lookup discards result', Not Broker.Execute(Run, 'lazarus_find_declaration', Args, Reply, Err)
      And (Reply = '') And (Pos('Source changed', Err) > 0));
    Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"example.pas"}', Reply, Err);
    Revision := Field(Reply, 'revision');
    Args := '{"path":"example.pas","revision":"' + JsonEscapeText(Revision) + '","line":7,"column":6}';
    Workspace.AfterLookup := 2;
    Check('project change during lookup discards result', Not Broker.Execute(Run, 'lazarus_find_declaration', Args, Reply, Err)
      And (Reply = '') And (Pos('Workspace/run changed', Err) > 0));
    Project.Path := Root + '/project.lpi'; Run := Broker.BeginRun(awsReadOnly);
    Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"example.pas"}', Reply, Err);
    Revision := Field(Reply, 'revision');
    Args := '{"path":"example.pas","revision":"' + JsonEscapeText(Revision) + '","line":7,"column":6}';
    Workspace.AfterLookup := 3;
    Check('cancellation during lookup discards result', Not Broker.Execute(Run, 'lazarus_find_declaration', Args, Reply, Err)
      And (Reply = '') And (Pos('Workspace/run changed', Err) > 0));
    Run := Broker.BeginRun(awsMarkdown);
    Check('Plan also advertises all semantic tools', (Pos('lazarus_find_declaration', Broker.ToolsJson) > 0)
      And (Pos('lazarus_find_references', Broker.ToolsJson) > 0) And (Pos('lazarus_symbol_context', Broker.ToolsJson) > 0));
    Run := Broker.BeginRun(awsProject);
    Check('Build also advertises all semantic tools', (Pos('lazarus_find_declaration', Broker.ToolsJson) > 0)
      And (Pos('lazarus_find_references', Broker.ToolsJson) > 0) And (Pos('lazarus_symbol_context', Broker.ToolsJson) > 0));
    Workspace.AfterLookup := 0;
    Editor.Syn := TSynEdit.Create(Nil);
    Try
      RenameSource := 'unit Example;' + LineEnding + '{$mode objfpc}{$H+}' + LineEnding +
        'interface' + LineEnding + 'implementation' + LineEnding +
        'procedure Other;' + LineEnding + 'var Counter: Integer;' + LineEnding +
        'begin Counter := 1; end;' + LineEnding +
        'procedure Test;' + LineEnding + 'var Counter: Integer;' + LineEnding +
        'begin' + LineEnding + '  Counter := 1;' + LineEnding +
        '  Counter := Counter + 1; // Counter stays in this comment' + LineEnding +
        '  if ''Counter'' = '''' then;' + LineEnding + 'end;' + LineEnding + 'end.' + LineEnding;
      Editor.Syn.Text := RenameSource; RenameSource := Editor.Syn.Text;
      Run := Broker.BeginRun(awsReadOnly);
      Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"example.pas"}', Reply, Err);
      Revision := Field(Reply, 'revision');
      Args := '{"path":"example.pas","revision":"' + JsonEscapeText(Revision) + '","line":11,"column":3,"new_name":"LocalCount"}';
      If Not Broker.Execute(Run, 'lazarus_preview_local_rename', Args, Reply, Err) Then
        Begin WriteLn(Err); Check('real CodeTools local rename preview', False); End;
      Check('local preview includes declaration and only matching semantic usages',
        (CountField(Reply, 'rename.changes') = 4) And (Field(Reply, 'rename.oldName') = 'Counter')
        And (Field(Reply, 'rename.changes[0].line') = '9') And (Editor.Syn.Text = RenameSource)
        And Not FileExists(Editor.Path));
      ApplyArgs := '{"preview_id":"' + JsonEscapeText(Field(Reply, 'preview_id')) + '"}';
      Check('Ask previews but cannot apply', (Pos('lazarus_preview_local_rename', Broker.ToolsJson) > 0)
        And (Pos('lazarus_apply_local_rename', Broker.ToolsJson) = 0)
        And Not Broker.Execute(Run, 'lazarus_apply_local_rename', ApplyArgs, Reply, Err));
      Run := Broker.BeginRun(awsMarkdown);
      Check('Plan previews but cannot apply', (Pos('lazarus_preview_local_rename', Broker.ToolsJson) > 0)
        And (Pos('lazarus_apply_local_rename', Broker.ToolsJson) = 0)
        And Not Broker.Execute(Run, 'lazarus_apply_local_rename', ApplyArgs, Reply, Err));
      Run := Broker.BeginRun(awsProject);
      Check('preview from previous run expires', Not Broker.Execute(Run, 'lazarus_apply_local_rename', ApplyArgs, Reply, Err));
      Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"example.pas"}', Reply, Err);
      Revision := Field(Reply, 'revision');
      Args := '{"path":"example.pas","revision":"' + JsonEscapeText(Revision) + '","line":11,"column":3,"new_name":"LocalCount"}';
      Check('Build produces local rename preview', Broker.Execute(Run, 'lazarus_preview_local_rename', Args, Reply, Err));
      ApplyArgs := '{"preview_id":"' + JsonEscapeText(Field(Reply, 'preview_id')) + '"}';
      Broker.OnApproval := @Workspace.Approve; Workspace.ApprovalAction := 1; Workspace.Saves := 0;
      If Not Broker.Execute(Run, 'lazarus_apply_local_rename', ApplyArgs, Reply, Err) Then
        Begin WriteLn(Err); Check('apply local rename', False); End;
      ExpectedText := StringReplace(RenameSource, 'var Counter: Integer;' + LineEnding + 'begin' + LineEnding,
        'var LocalCount: Integer;' + LineEnding + 'begin' + LineEnding, []);
      ExpectedText := StringReplace(ExpectedText, '  Counter := 1;', '  LocalCount := 1;', []);
      ExpectedText := StringReplace(ExpectedText, '  Counter := Counter + 1;', '  LocalCount := LocalCount + 1;', []);
      Check('apply changes only previewed positions and saves the open editor', (Editor.Syn.Text = ExpectedText)
        And BoolField(Reply, 'saved') And (Workspace.Saves = 1) And (Field(Reply, 'revision') <> Revision));
      Check('preview cannot be replayed', Not Broker.Execute(Run, 'lazarus_apply_local_rename', ApplyArgs, Reply, Err));
      Editor.Syn.Undo;
      Check('one native Undo restores entire local rename', Editor.Syn.Text = RenameSource);
      Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"example.pas"}', Reply, Err);
      Revision := Field(Reply, 'revision');
      Args := '{"path":"example.pas","revision":"' + JsonEscapeText(Revision) + '","line":11,"column":3,"new_name":"LocalCount"}';
      Check('implicit Result identifier rejected', Not Broker.Execute(Run, 'lazarus_preview_local_rename', StringReplace(Args, 'LocalCount', 'Result', []), Reply, Err));
      Check('implicit Self identifier rejected', Not Broker.Execute(Run, 'lazarus_preview_local_rename', StringReplace(Args, 'LocalCount', 'Self', []), Reply, Err));
      Check('keyword rejected', Not Broker.Execute(Run, 'lazarus_preview_local_rename', StringReplace(Args, 'LocalCount', 'begin', []), Reply, Err));
      Check('collision rejected', Not Broker.Execute(Run, 'lazarus_preview_local_rename', StringReplace(Args, 'LocalCount', 'Other', []), Reply, Err));
      Check('case-only rename rejected', Not Broker.Execute(Run, 'lazarus_preview_local_rename', StringReplace(Args, 'LocalCount', 'counter', []), Reply, Err));
      Check('invalid identifier rejected', Not Broker.Execute(Run, 'lazarus_preview_local_rename', StringReplace(Args, 'LocalCount', 'two words', []), Reply, Err));
      Check('procedure rename rejected', Not Broker.Execute(Run, 'lazarus_preview_local_rename', StringReplace(Args, '"line":11,"column":3', '"line":8,"column":11', []), Reply, Err));
      For Calls := 0 To 4 Do
        Begin
          Project.Path := Root + '/project.lpi'; Editor.Syn.Text := RenameSource;
          Run := Broker.BeginRun(awsProject);
          Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"example.pas"}', Reply, Err);
          Revision := Field(Reply, 'revision');
          Args := '{"path":"example.pas","revision":"' + JsonEscapeText(Revision) + '","line":11,"column":3,"new_name":"LocalCount"}';
          Check('prepare approval lifecycle preview', Broker.Execute(Run, 'lazarus_preview_local_rename', Args, Reply, Err));
          ApplyArgs := '{"preview_id":"' + JsonEscapeText(Field(Reply, 'preview_id')) + '"}';
          Workspace.ApprovalAction := Calls;
          If Calls = 1 Then Editor.Syn.Text := Editor.Syn.Text + '// edit before apply';
          Check('denial/stale source/cancel/project change rejects rename ' + IntToStr(Calls),
            Not Broker.Execute(Run, 'lazarus_apply_local_rename', ApplyArgs, Reply, Err)
            And (Pos('LocalCount', Editor.Syn.Text) = 0));
        End;
      Project.Path := Root + '/project.lpi'; Broker.OnApproval := Nil;
      Editor.Syn.Text := StringReplace(RenameSource, '  Counter := 1;', '{$ifdef TEST}  Counter := 1;{$endif}', []);
      Run := Broker.BeginRun(awsProject);
      Broker.Execute(Run, 'lazarus_read_buffer', '{"path":"example.pas"}', Reply, Err);
      Args := '{"path":"example.pas","revision":"' + JsonEscapeText(Field(Reply, 'revision')) + '","line":9,"column":5,"new_name":"LocalCount"}';
      Check('conditional source cannot produce a partial rename', Not Broker.Execute(Run, 'lazarus_preview_local_rename', Args, Reply, Err));
      Check('local constant declaration and semantic uses are renamed', PreviewFixture(
        'unit Example; interface implementation procedure Test; const Counter = 42; ' +
        'begin if Counter = 42 then; end; end.', 'Counter')
        And (CountField(Reply, 'rename.changes') = 2) And (Field(Reply, 'rename.symbolKind') = 'constant'));
      ExpectedText := Editor.Syn.Text;
      ApplyArgs := '{"preview_id":"' + JsonEscapeText(Field(Reply, 'preview_id')) + '"}';
      Check('constant rename applies exact preview', Broker.Execute(Run, 'lazarus_apply_local_rename', ApplyArgs, Reply, Err)
        And (Editor.Syn.Text = StringReplace(ExpectedText, 'Counter', 'LocalCount', [rfReplaceAll])));
      Editor.Syn.Undo; Check('constant rename preserves one native Undo', Editor.Syn.Text = ExpectedText);
      Check('typed local constant is supported', PreviewFixture(
        'unit Example; interface implementation procedure Test; const Counter: Integer = 42; ' +
        'begin if Counter = 42 then; end; end.', 'Counter') And (CountField(Reply, 'rename.changes') = 2));
      Check('local constant nested captures and shadowing are resolved', PreviewFixture(
        'unit Example; interface implementation procedure Outer; const Counter = 42; ' +
        'procedure Inner; begin if Counter = 42 then; end; ' +
        'procedure Shadow; const Counter = 7; begin if Counter = 7 then; end; ' +
        'begin if Counter = 42 then; Inner; Shadow; end; end.', 'Counter')
        And (CountField(Reply, 'rename.changes') = 3));
      Check('constant use resolves its local declaration', PreviewFixture(
        'unit Example; interface implementation procedure Test; const Counter = 42; ' +
        'begin if COUNTER = 42 then; end; end.', 'COUNTER') And (CountField(Reply, 'rename.changes') = 2));
      Check('global constant remains outside local rename scope', Not PreviewFixture(
        'unit Example; interface const Counter = 42; implementation end.', 'Counter'));
      Check('constant collision rejects preview', Not PreviewFixture(
        'unit Example; interface implementation procedure Test; const Counter = 42; LocalCount = 7; ' +
        'begin if Counter = LocalCount then; end; end.', 'Counter'));
      Check('conditional constant references cannot be omitted', Not PreviewFixture(
        'unit Example; interface implementation procedure Test; const Counter = 42; ' +
        'begin {$ifdef NEVER} if Counter = 42 then; {$endif} end; end.', 'Counter'));
      Check('global var cannot be renamed by local tool', Not PreviewFixture(
        'unit Example; interface var Counter: Integer; implementation end.', 'Counter'));
      Check('parameter cannot be renamed by local tool', Not PreviewFixture(
        'unit Example; interface implementation procedure Test(Counter: Integer); begin Counter := 1; end; end.', 'Counter'));
      Check('field cannot be renamed by local tool', Not PreviewFixture(
        'unit Example; interface type TRec = record Counter: Integer; end; implementation end.', 'Counter'));
      Check('escaped local identifier rejected', Not PreviewFixture(
        'unit Example; interface implementation procedure Test; var &Counter: Integer; begin &Counter := 1; end; end.', '&Counter'));
      Check('nested capture retained and nested shadow excluded', PreviewFixture(
        'unit Example; interface implementation procedure Outer; var Counter: Integer; ' +
        'procedure Inner; begin Counter := 1; end; procedure Shadow; var Counter: Integer; begin Counter := 2; end; ' +
        'begin Counter := 0; Inner; Shadow; end; end.', 'Counter') And (CountField(Reply, 'rename.changes') = 3));
      Check('ordinary resource and mode directives are supported', PreviewFixture(
        'unit Example; (*$mode objfpc*) {$R *.lfm} interface implementation procedure Test; var Counter: Integer; begin Counter := 1; end; end.', 'Counter')
        And (CountField(Reply, 'rename.changes') = 2));
      Check('multiple variable declaration renames one symbol', PreviewFixture(
        'unit Example; interface implementation procedure Test; var Other, Counter: Integer; begin Counter := Other; end; end.', 'Counter')
        And (CountField(Reply, 'rename.changes') = 2));
      Check('UTF8 and tabs preserve byte locations', PreviewFixture(
        'unit Example; interface implementation procedure Test; var Counter: Integer; begin ' + #9 + '{é} Counter := Counter + 1; end; end.', 'Counter')
        And (CountField(Reply, 'rename.changes') = 3));
      ApplyArgs := '{"preview_id":"' + JsonEscapeText(Field(Reply, 'preview_id')) + '"}';
      Check('UTF8 rename applies', Broker.Execute(Run, 'lazarus_apply_local_rename', ApplyArgs, Reply, Err)
        And (Pos(#9 + '{é} LocalCount := LocalCount + 1;', Editor.Syn.Text) > 0));
      Check('comment and string words do not cause false collisions or assembly rejection', PreviewFixture(
        'unit Example; {$mode objfpc} interface implementation procedure Test; var Counter: Integer; begin ' +
        '{ LocalCount asm } (* LocalCount asm {$include fake.inc} *) Counter := 1; ' +
        'if ''LocalCount asm {$ifdef FAKE}'' = '''' then; end; end.', 'Counter')
        And (CountField(Reply, 'rename.changes') = 2));
      Check('nested comments do not create fake directives or identifiers', PreviewFixture(
        'unit Example; {$mode objfpc} interface implementation procedure Test; var Counter: Integer; begin ' +
        '{ outer { LocalCount asm {$ifdef FAKE} } } Counter := 1; end; end.', 'Counter'));
      Check('inactive includes remain rejected outside routine', Not PreviewFixture(
        'unit Example; interface implementation {$ifdef ASSISTANT_RENAME_NEVER} {$include fake.inc} {$endif} ' +
        'procedure Test; var Counter: Integer; begin Counter := 1; end; end.', 'Counter')
        And (Pos('Unsupported rename directive', Err) > 0));
      Check('multiline conditional wrapper respects raw routine boundaries', PreviewFixture(
        'unit Example;' + LineEnding + 'interface' + LineEnding + 'implementation' + LineEnding +
        '{$ifndef ASSISTANT_RENAME_NEVER}' + LineEnding + 'procedure Test;' + LineEnding +
        'var Counter: Integer;' + LineEnding + 'begin' + LineEnding +
        '  Counter := 1;' + LineEnding + 'end;' + LineEnding + '{$endif}' + LineEnding + 'end.', 'Counter')
        And (Field(Reply, 'rename.changes[0].line') = '6') And (Field(Reply, 'rename.changes[1].line') = '8'));
      Check('line-comment directive text is ignored', PreviewFixture(
        'unit Example; interface implementation procedure Test; var Counter: Integer; begin Counter := 1; end; end. // LocalCount asm {$ifdef FAKE}', 'Counter'));
      Check('common checking and diagnostic directives are supported', PreviewFixture(
        'unit Example; {$mode' + #9 + 'objfpc} {$H+} {$R+} {$Q-} {$BOOLEVAL OFF} {$RANGECHECKS ON} ' +
        '{$OVERFLOWCHECKS OFF} {$WARNINGS ON} {$HINTS OFF} {$NOTES ON} interface implementation ' +
        'procedure Test; var Counter: Integer; begin Counter := 1; end; end.', 'Counter'));
      Check('escaped code collision remains rejected', Not PreviewFixture(
        'unit Example; interface implementation procedure Test; var Counter, &LocalCount: Integer; begin Counter := 1; end; end.', 'Counter')
        And (Pos('active Pascal code', Err) > 0));
      Check('actual assembly remains rejected', Not PreviewFixture(
        'unit Example; interface implementation procedure Test; var Counter: Integer; begin Counter := 1; asm nop end; end; end.', 'Counter')
        And (Pos('Assembly', Err) > 0));
      Check('macro directives remain rejected', Not PreviewFixture(
        'unit Example; {$macro on} interface implementation procedure Test; var Counter: Integer; begin Counter := 1; end; end.', 'Counter')
        And (Pos('Unsupported rename directive', Err) > 0));
      Check('inactive directives inside routine remain rejected', Not PreviewFixture(
        'unit Example; interface implementation procedure Test; var Counter: Integer; begin ' +
        '{$ifdef ASSISTANT_RENAME_NEVER} Counter := 1; {$else} Counter := 2; {$endif} end; end.', 'Counter')
        And (Pos('inside the selected routine', Err) > 0));
      Check('conditional sections in other routines are allowed', PreviewFixture(
        'unit Example; interface implementation procedure Test; var Counter: Integer; begin Counter := 1; end; ' +
        'procedure Other; begin {$ifdef ASSISTANT_RENAME_NEVER} {$ifdef SECOND} {$endif} {$else} {$endif} end; end.', 'Counter'));
      DiskDependency := 'unit Example; interface implementation {$ifdef ASSISTANT_RENAME_ALTERNATE} ' +
        'procedure Test; var LocalCount: Integer; begin LocalCount := 0; end; {$else} ' +
        'procedure Test; var Counter: Integer; begin Counter := 1; end; {$endif} end.';
      Check('inactive declarations outside selected routine do not conflict', PreviewFixture(DiskDependency, 'Counter')
        And (CountField(Reply, 'rename.changes') = 2));
      ApplyArgs := '{"preview_id":"' + JsonEscapeText(Field(Reply, 'preview_id')) + '"}';
      Check('conditional routine rename applies only selected declaration and uses', Broker.Execute(Run, 'lazarus_apply_local_rename', ApplyArgs, Reply, Err)
        And (Editor.Syn.Text = StringReplace(DiskDependency, 'Counter', 'LocalCount', [rfReplaceAll]) + LineEnding));
      Editor.Syn.Undo;
      Check('conditional routine rename has one Undo', Editor.Syn.Text = DiskDependency + LineEnding);
      Check('prepare configuration-change preview', PreviewFixture(DiskDependency, 'Counter'));
      ApplyArgs := '{"preview_id":"' + JsonEscapeText(Field(Reply, 'preview_id')) + '"}';
      Workspace.DefineOnApproval := TDefineTemplate.Create('rename-alternate', '', 'ASSISTANT_RENAME_ALTERNATE', '1', da_Define);
      Workspace.ApprovalAction := 5; Broker.OnApproval := @Workspace.Approve;
      Try
        Check('changed defines during approval discard rename without editing',
          Not Broker.Execute(Run, 'lazarus_apply_local_rename', ApplyArgs, Reply, Err)
          And (Editor.Syn.Text = DiskDependency + LineEnding) And (Reply = ''));
      Finally
        CodeToolBoss.DefineTree.RemoveDefineTemplate(Workspace.DefineOnApproval);
        Workspace.DefineOnApproval := Nil; Broker.OnApproval := Nil;
      End;
      DiskDependency := 'unit Example; interface implementation procedure Test; var Counter: Integer; begin ';
      For Calls := 1 To 201 Do DiskDependency := DiskDependency + 'Counter := 1; ';
      DiskDependency := DiskDependency + 'end; end.';
      Check('too many occurrences reject whole preview', Not PreviewFixture(DiskDependency, 'Counter')
        And (Pos('200 occurrences', Err) > 0) And (Pos('LocalCount', Editor.Syn.Text) = 0));
    Finally Editor.Syn.Free; Editor.Syn := Nil; End;
  Finally
    If Assigned(Dependency) Then Dependency.UnlockAutoDiskRevert;
    Broker.Free; Workspace.Free; OtherWorkspace.Free; LazarusIDE := Nil; SourceEditorManagerIntf := Nil;
    IDE.Free; Manager.Free; Editor.Free; Project.Free; DeleteFile(Root + '/project.lpi'); DeleteFile(Root + '/dependency.pas'); DeleteFile(Root + '/system.pp'); DeleteFile(Root + '/extra.pas'); DeleteFile(Root + '/broken.pas'); RemoveDir(Root);
  End;
End.
