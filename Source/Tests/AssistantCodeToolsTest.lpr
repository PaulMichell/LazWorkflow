Program AssistantCodeToolsTest;
{$mode objfpc}{$H+}
Uses cthreads, Interfaces, Forms, Classes, SysUtils, fpjson, jsonparser,
  LazIDEIntf, ProjectIntf, SrcEditorIntf, CodeToolManager, CodeCache, DefineTemplates,
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
    Procedure ApplyLookupChange;
    Function SymbolContext(Const Path: String; Line, Column: Integer; Out ResultText, ErrorText: String): Boolean; Override;
    Function FindReferences(Const Path: String; Line, Column: Integer; SearchPaths: TStrings; MaxResults: Integer; Out ResultText, ErrorText: String): Boolean; Override;
    Function FindDeclaration(Const Path: String; Line, Column: Integer; Out ResultText, ErrorText: String): Boolean; Override;
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
Begin Result := Text; End;
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
  If Result Then Editor.Code.Source := Editor.Text;
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
Var Root, Reply, Err, Run, Revision, Args, RefArgs, ReferenceLine, DiskDependency: String; Define: TDefineTemplate; Id: TGuid;
  IDE: TIDE; Project: TProject; Editor: TEditor; Manager: TManager;
  Workspace: TObservedWorkspace; OtherWorkspace: TAssistantIDEWorkspace; Dependency: TCodeBuffer; Broker: TAssistantToolBroker; Calls: Integer; Stream: TFileStream;
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
  Finally
    If Assigned(Dependency) Then Dependency.UnlockAutoDiskRevert;
    Broker.Free; Workspace.Free; OtherWorkspace.Free; LazarusIDE := Nil; SourceEditorManagerIntf := Nil;
    IDE.Free; Manager.Free; Editor.Free; Project.Free; DeleteFile(Root + '/project.lpi'); DeleteFile(Root + '/dependency.pas'); DeleteFile(Root + '/system.pp'); DeleteFile(Root + '/extra.pas'); DeleteFile(Root + '/broken.pas'); RemoveDir(Root);
  End;
End.
