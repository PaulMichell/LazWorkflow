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
    Function FindDeclaration(Const Path: String; Line, Column: Integer; Out ResultText, ErrorText: String): Boolean; Override;
  End;
Function TObservedWorkspace.FindDeclaration(Const Path: String; Line, Column: Integer; Out ResultText, ErrorText: String): Boolean;
Begin
  Result := Inherited FindDeclaration(Path, Line, Column, ResultText, ErrorText);
  If Result Then Case AfterLookup Of
    1: Editor.Text := Editor.Text + LineEnding + '// user edit';
    2: Project.Path := Project.Path + '.changed';
    3: Broker.Cancel;
  End;
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
Var Root, Reply, Err, Run, Revision, Args, ReferenceLine, DiskDependency: String; Define: TDefineTemplate; Id: TGuid;
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
    Check('Plan also advertises semantic lookup', Pos('lazarus_find_declaration', Broker.ToolsJson) > 0);
    Run := Broker.BeginRun(awsProject);
    Check('Build also advertises semantic lookup', Pos('lazarus_find_declaration', Broker.ToolsJson) > 0);
  Finally
    If Assigned(Dependency) Then Dependency.UnlockAutoDiskRevert;
    Broker.Free; Workspace.Free; OtherWorkspace.Free; LazarusIDE := Nil; SourceEditorManagerIntf := Nil;
    IDE.Free; Manager.Free; Editor.Free; Project.Free; DeleteFile(Root + '/project.lpi'); DeleteFile(Root + '/dependency.pas'); DeleteFile(Root + '/system.pp'); RemoveDir(Root);
  End;
End.
