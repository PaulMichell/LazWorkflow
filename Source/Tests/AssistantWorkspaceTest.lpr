Program AssistantWorkspaceTest;
{$mode objfpc}{$H+}
Uses cthreads, Interfaces, Forms, Controls, Classes, SysUtils, BaseUnix,
  LazIDEIntf, ProjectIntf, SrcEditorIntf, AssistantTestIDEHost, AssistantIDEWorkspace, AssistantToolBroker;
Type
  TProject = Class(TLazProject)
  Public
    ProjectFile: String;
    Function GetProjectInfoFile: String; Override;
    Function GetMainFile: TLazProjectFile; Override;
  End;
  TEditor = Class(TSourceEditorInterface)
  Public
    Path, Body: String;
    Function GetSourceText: String; Override;
  End;
  TManager = Class(TSourceEditorManagerInterface)
  Public
    Editor: TEditor;
    Function SourceEditorIntfWithFilename(Const Filename: String): TSourceEditorInterface; Override;
  End;
  TIDE = Class(TLazIDEInterface)
  Public
    Project: TProject;
    Manager: TManager;
    Opens: Integer;
    Function GetActiveProject: TLazProject; Override;
    Function DoOpenEditorFile(AFileName: String; PageIndex, WindowIndex: Integer;
      Flags: TOpenFlags): TModalResult; Override;
  End;
Function TProject.GetProjectInfoFile: String;
Begin Result := ProjectFile; End;
Function TProject.GetMainFile: TLazProjectFile;
Begin Result := Nil; End;
Function TEditor.GetSourceText: String;
Begin Result := Body; End;
Function TManager.SourceEditorIntfWithFilename(Const Filename: String): TSourceEditorInterface;
Begin
  Result := Nil;
  If Assigned(Editor) And (Editor.Path = Filename) Then Result := Editor;
End;
Function TIDE.GetActiveProject: TLazProject;
Begin Result := Project; End;
Procedure Check(Const Name: String; Value: Boolean);
Begin
  If Not Value Then Begin WriteLn('FAIL ', Name); Halt(1); End;
  WriteLn('ok   ', Name);
End;
Function TIDE.DoOpenEditorFile(AFileName: String; PageIndex, WindowIndex: Integer;
  Flags: TOpenFlags): TModalResult;
Var Lines: TStringList;
Begin
  Check('open neither creates files nor activates editor',
    (ofOnlyIfExists In Flags) And (ofDoNotActivateSourceEditor In Flags) And (ofDoNotLoadResource In Flags));
  Inc(Opens);
  Manager.Editor := TEditor.Create;
  Manager.Editor.Path := AFileName;
  Lines := TStringList.Create;
  Try Lines.LoadFromFile(AFileName); Manager.Editor.Body := Lines.Text; Finally Lines.Free; End;
  Result := mrOK;
End;
Procedure WriteFile(Const Path, Body: String);
Var Stream: TFileStream;
Begin
  Stream := TFileStream.Create(Path, fmCreate);
  Try If Body <> '' Then Stream.WriteBuffer(Body[1], Length(Body)); Finally Stream.Free; End;
End;
Var IDE: TIDE; Project: TProject; Manager: TManager; Workspace: TAssistantIDEWorkspace;
  Broker: TAssistantToolBroker; Root, Run, Reply, Err: String; Id: TGuid; Stream: TFileStream;
Begin
  Application.Initialize;
  CreateGUID(Id); Root := GetTempDir + 'laz-workspace-' + GUIDToString(Id);
  ForceDirectories(Root);
  WriteFile(Root + '/project.lpi', '<project/>');
  WriteFile(Root + '/closed.pas', 'unit Closed;' + LineEnding + 'interface' + LineEnding + 'implementation' + LineEnding + 'end.');
  IDE := TIDE.Create(Nil); Project := TProject.Create(Nil); Manager := TManager.Create(Nil);
  Project.ProjectFile := Root + '/project.lpi'; IDE.Project := Project; IDE.Manager := Manager;
  LazarusIDE := IDE; SourceEditorManagerIntf := Manager;
  Workspace := TAssistantIDEWorkspace.Create; Broker := TAssistantToolBroker.Create(Workspace);
  Try
    Run := Broker.BeginRun(False);
    Check('inspection tools advertised in Ask', Pos('lazarus_read_file', Broker.ToolsJson) > 0);
    Check('Ask has no save tool', Pos('lazarus_save_buffer', Broker.ToolsJson) = 0);
    Check('list project root', Broker.Execute(Run, 'lazarus_list_directory', '{"path":"."}', Reply, Err));
    Check('list includes closed file', Pos('closed.pas', Reply) > 0);
    Check('read closed disk file', Broker.Execute(Run, 'lazarus_read_file', '{"path":"closed.pas","start_line":2,"end_line":2}', Reply, Err));
    Check('read honors line range without opening editor', (Pos('interface', Reply) > 0) And (Pos('unit Closed;', Reply) = 0) And (IDE.Opens = 0));
    Check('open closed buffer in Ask', Broker.Execute(Run, 'lazarus_open_buffer', '{"path":"closed.pas"}', Reply, Err));
    Check('open returns edit revision', Pos('"revision"', Reply) > 0);
    Manager.Editor.Body := 'unsaved IDE text';
    Check('read prefers unsaved buffer', Broker.Execute(Run, 'lazarus_read_file', '{"path":"closed.pas"}', Reply, Err) And (Pos('unsaved IDE text', Reply) > 0));
    Check('open reuses unsaved tab', Broker.Execute(Run, 'lazarus_open_buffer', '{"path":"closed.pas"}', Reply, Err) And (IDE.Opens = 1) And (Pos('unsaved IDE text', Reply) > 0));
    Check('Ask still refuses edits', Not Broker.Execute(Run, 'lazarus_replace_buffer', '{"path":"closed.pas","text":"changed","revision":"invalid"}', Reply, Err));
    Check('missing file not created', Not Broker.Execute(Run, 'lazarus_open_buffer', '{"path":"missing.pas"}', Reply, Err) And Not FileExists(Root + '/missing.pas'));
    Check('path traversal refused', Not Broker.Execute(Run, 'lazarus_read_file', '{"path":"../outside.txt"}', Reply, Err));
    fpSymlink('/etc/passwd', PChar(Root + '/escape'));
    Check('symlink escape refused', Not Broker.Execute(Run, 'lazarus_read_file', '{"path":"escape"}', Reply, Err));
    WriteFile(Root + '/binary', 'abc' + #0 + 'def');
    Check('binary file refused', Not Broker.Execute(Run, 'lazarus_read_file', '{"path":"binary"}', Reply, Err));
    fpMkFifo(Root + '/pipe', &600);
    Check('FIFO refused without blocking', Not Broker.Execute(Run, 'lazarus_read_file', '{"path":"pipe"}', Reply, Err));
    Stream := TFileStream.Create(Root + '/large.pas', fmCreate);
    Try Stream.Size := 1048577; Finally Stream.Free; End;
    Check('oversized file refused', Not Broker.Execute(Run, 'lazarus_open_buffer', '{"path":"large.pas"}', Reply, Err));
    Broker.Cancel;
    Check('cancel blocks file inspection', Not Broker.Execute(Run, 'lazarus_list_directory', '{"path":"."}', Reply, Err));
    Run := Broker.BeginRun(False); Project.ProjectFile := Root + '/other.lpi';
    Check('project switch blocks file inspection', Not Broker.Execute(Run, 'lazarus_read_file', '{"path":"closed.pas"}', Reply, Err));
  Finally
    Broker.Free; Workspace.Free;
    LazarusIDE := Nil; SourceEditorManagerIntf := Nil;
    Manager.Editor.Free; Manager.Free; IDE.Free; Project.Free;
    DeleteFile(Root + '/binary');
    DeleteFile(Root + '/large.pas'); DeleteFile(Root + '/pipe'); DeleteFile(Root + '/escape');
    DeleteFile(Root + '/closed.pas'); DeleteFile(Root + '/project.lpi'); RemoveDir(Root);
  End;
End.
