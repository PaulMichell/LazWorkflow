Program AssistantBuildWorkspaceTest;
{$mode objfpc}{$H+}
Uses cthreads, Interfaces, Forms, Classes, SysUtils, fpjson, jsonparser,
  LazIDEIntf, ProjectIntf, SrcEditorIntf, CodeToolManager, AssistantTestIDEHost, AssistantIDEWorkspace, AssistantToolBroker, AssistantTestSettings;
Type
  TProjectFile = Class(TLazProjectFile)
  Public
    Path: String;
    Function GetFilename: String; Override;
  End;
  TProject = Class(TLazProject)
  Public
    Path, Mode: String; Dirty: Boolean; Member: TProjectFile;
    Function GetProjectInfoFile: String; Override;
    Function GetMainFile: TLazProjectFile; Override;
    Function GetFiles(Index: Integer): TLazProjectFile; Override;
    Function GetFileCount: Integer; Override;
    Function GetModified: Boolean; Override;
    Function GetActiveBuildModeID: String; Override;
  End;
  TEditor = Class(TSourceEditorInterface)
  Public
    Path, Text: String; Dirty, DirtyDesign: Boolean;
    Function GetFileName: String; Override;
    Function GetModifiedDesign: Boolean; Override;
    Function GetSourceText: String; Override;
    Function GetModified: Boolean; Override;
  End;
  TManager = Class(TSourceEditorManagerInterface)
  Public
    Editor: TEditor;
    Function SourceEditorCount: Integer; Override;
    Function GetSourceEditors(Index: Integer): TSourceEditorInterface; Override;
    Function SourceEditorIntfWithFilename(Const Filename: String): TSourceEditorInterface; Override;
  End;
  TIDE = Class(TLazIDEInterface)
  Public
    Project: TProject;
    CancelWorkspace: TAssistantIDEWorkspace;
    Function BeginCodeTools: Boolean; Override;
    Function GetActiveProject: TLazProject; Override;
    Class Function GetPrimaryConfigPath: String; Override;
  End;
  TWorkspace = Class(TAssistantIDEWorkspace)
  Public
    ApprovalAction: Integer;
    Function Approve(Const Tool, Path, OldText, NewText: String): Boolean;
  Protected
    Function BuildExecutable: String; Override;
  End;
Function TIDE.BeginCodeTools: Boolean;
Begin
  If Assigned(CancelWorkspace) Then CancelWorkspace.CancelBuild;
  Result := True;
End;
Class Function TIDE.GetPrimaryConfigPath: String;
Begin Result := ExtractFilePath(LazarusIDE.ActiveProject.ProjectInfoFile); End;
Function TWorkspace.Approve(Const Tool, Path, OldText, NewText: String): Boolean;
Var Settings: TAssistantTestSettings;
Begin
  Result := ApprovalAction <> 1;
  If (Tool = 'lazarus_start_tests') And (ApprovalAction = 2) Then
    Begin
      Settings := TAssistantTestSettings.Create(LazarusIDE.GetPrimaryConfigPath, LazarusIDE.ActiveProject.ProjectInfoFile);
      Try Settings.Load; Inc(Settings.TimeoutSeconds); Settings.Save; Finally Settings.Free; End;
    End;
End;
Function TProjectFile.GetFilename: String;
Begin Result := Path; End;
Function TProject.GetProjectInfoFile: String;
Begin Result := Path; End;
Function TProject.GetMainFile: TLazProjectFile;
Begin Result := Member; End;
Function TProject.GetFiles(Index: Integer): TLazProjectFile;
Begin Result := Member; End;
Function TProject.GetFileCount: Integer;
Begin Result := 1; End;
Function TProject.GetModified: Boolean;
Begin Result := Dirty; End;
Function TProject.GetActiveBuildModeID: String;
Begin Result := Mode; End;
Function TEditor.GetModifiedDesign: Boolean;
Begin Result := DirtyDesign; End;
Function TEditor.GetFileName: String;
Begin Result := Path; End;
Function TEditor.GetSourceText: String;
Begin Result := Text; End;
Function TEditor.GetModified: Boolean;
Begin Result := Dirty; End;
Function TManager.SourceEditorCount: Integer;
Begin If Assigned(Editor) Then Result := 1 Else Result := 0; End;
Function TManager.GetSourceEditors(Index: Integer): TSourceEditorInterface;
Begin Result := Editor; End;
Function TManager.SourceEditorIntfWithFilename(Const Filename: String): TSourceEditorInterface;
Begin Result := Nil; If Assigned(Editor) And (Editor.Path = Filename) Then Result := Editor; End;
Function TIDE.GetActiveProject: TLazProject;
Begin Result := Project; End;
Function TWorkspace.BuildExecutable: String;
Begin Result := ParamStr(0); End;
Procedure Check(Const Name: String; OK: Boolean);
Begin If Not OK Then Begin WriteLn('FAIL ', Name); Halt(1); End; WriteLn('ok ', Name); End;
Procedure WriteFile(Const Path, Text: String);
Var Stream: TFileStream;
Begin Stream := TFileStream.Create(Path, fmCreate); Try If Text <> '' Then Stream.WriteBuffer(Text[1], Length(Text)); Finally Stream.Free; End; End;
Function Field(Const Text, Name: String): String;
Var Data: TJSONData;
Begin Data := GetJSON(Text); Try Result := Data.FindPath(Name).AsString; Finally Data.Free; End; End;
Var Workspace: TWorkspace; IDE: TIDE; Project: TProject; Manager: TManager; Editor: TEditor; Broker: TAssistantToolBroker;
  Root, Run, Reply, Err, JobArgs, FirstID, BuildID, TestArgs: String; Settings: TAssistantTestSettings; ID: TGuid; Deadline: QWord;
Procedure StartAndWait;
Begin
  If Not Broker.Execute(Run, 'lazarus_start_build', '{}', Reply, Err) Then Begin WriteLn(Err); Check('build starts', False); End;
  JobArgs := '{"job_id":"' + Field(Reply, 'job_id') + '"}';
  Deadline := GetTickCount64 + 4000;
  Repeat
    Check('poll owned job', Broker.Execute(Run, 'lazarus_build_status', JobArgs, Reply, Err));
    If Field(Reply, 'done') = 'true' Then Break;
    Sleep(50);
  Until GetTickCount64 > Deadline;
  Check('job finishes', Field(Reply, 'done') = 'true');
End;
Begin
  If (ParamCount > 0) And (ParamStr(1) = 'test-failure') Then Begin WriteLn('test failed'); Halt(2); End;
  If ParamCount > 0 Then Begin WriteLn('closed.pas(1,1) Hint: fixture compiled'); Halt(0); End;
  Application.Initialize; CreateGUID(ID); Root := GetTempDir + 'laz-build-workspace-' + GUIDToString(ID); ForceDirectories(Root);
  Project := TProject.Create(Nil); Project.Path := Root + '/project.lpi'; Project.Mode := 'Debug';
  Project.Member := TProjectFile.Create; Project.Member.Path := Root + '/closed.pas';
  WriteFile(Project.Path, '<project/>'); WriteFile(Project.Member.Path, 'unit Closed;'); WriteFile(Root + '/closed.lfm', 'object Form1: TForm1 end');
  Editor := TEditor.Create; Editor.Path := Root + '/open.pas'; Editor.Text := 'unit Open;'; WriteFile(Editor.Path, Editor.Text);
  Manager := TManager.Create(Nil); IDE := TIDE.Create(Nil); IDE.Project := Project;
  LazarusIDE := IDE; SourceEditorManagerIntf := Manager;
  Workspace := TWorkspace.Create; Broker := TAssistantToolBroker.Create(Workspace);
  Try
    Run := Broker.BeginRun(awsProject); StartAndWait; FirstID := Field(Reply, 'job_id');
    Check('closed project file and paired resource are observed', (Pos('closed.pas', Reply) > 0) And (Pos('closed.lfm', Reply) > 0)
      And (Field(Reply, 'outcome') = 'compile_passed') And (Field(Reply, 'verified') = 'false'));
    WriteFile(Project.Member.Path, 'later saved edit');
    Check('saved closed-file edit invalidates completed evidence', Broker.Execute(Run, 'lazarus_build_status', JobArgs, Reply, Err)
      And (Field(Reply, 'outcome') = 'stale'));
    StartAndWait;
    Check('fresh build observes repaired source', Field(Reply, 'outcome') = 'compile_passed');
    Check('earlier job cannot be confused with replacement build', Not Broker.Execute(Run, 'lazarus_build_status',
      '{"job_id":"' + FirstID + '"}', Reply, Err) And (Reply = ''));
    WriteFile(Root + '/closed.lfm', 'later resource edit');
    Check('resource edit invalidates completed evidence', Broker.Execute(Run, 'lazarus_build_status', JobArgs, Reply, Err)
      And (Field(Reply, 'outcome') = 'stale'));
    StartAndWait; Manager.Editor := Editor; Editor.Dirty := True;
    Check('new dirty editor invalidates completed evidence', Broker.Execute(Run, 'lazarus_build_status', JobArgs, Reply, Err)
      And (Field(Reply, 'stale') = 'true'));
    Check('dirty editor prevents another build', Not Broker.Execute(Run, 'lazarus_start_build', '{}', Reply, Err));
    Editor.Dirty := False; Editor.DirtyDesign := True;
    Check('unsaved designer changes invalidate build evidence', Broker.Execute(Run, 'lazarus_build_status', JobArgs, Reply, Err)
      And (Field(Reply, 'stale') = 'true'));
    Check('unsaved designer changes prevent build', Not Broker.Execute(Run, 'lazarus_start_build', '{}', Reply, Err));
    Editor.DirtyDesign := False; Editor.Text := 'different bytes';
    Check('unsaved text is refused even if modified flag is false', Not Broker.Execute(Run, 'lazarus_start_build', '{}', Reply, Err));
    Editor.Text := 'unit Open;'; StartAndWait;
    BuildID := Field(Reply, 'job_id');
    TestArgs := '{"build_job_id":"' + BuildID + '"}';
    Check('disabled test runner cannot execute', Not Broker.Execute(Run, 'lazarus_start_tests', TestArgs, Reply, Err));
    Settings := TAssistantTestSettings.Create(Root, Project.Path);
    Try
      Settings.Enabled := True; Settings.Executable := ParamStr(0); Settings.Arguments.Add('configured-tests'); Settings.Save;
      Workspace.ApprovalAction := 1; Broker.OnApproval := @Workspace.Approve;
      Check('test approval denial prevents launch', Not Broker.Execute(Run, 'lazarus_start_tests', TestArgs, Reply, Err));
      Workspace.ApprovalAction := 2;
      Check('changed configuration during approval prevents launch', Not Broker.Execute(Run, 'lazarus_start_tests', TestArgs, Reply, Err)
        And (Pos('changed during approval', Err) > 0));
      Workspace.ApprovalAction := 0;
      Check('configured test command starts for current build', Broker.Execute(Run, 'lazarus_start_tests', TestArgs, Reply, Err));
      JobArgs := '{"job_id":"' + Field(Reply, 'job_id') + '"}'; Deadline := GetTickCount64 + 4000;
      Repeat
        Check('poll configured tests', Broker.Execute(Run, 'lazarus_test_status', JobArgs, Reply, Err));
        If Field(Reply, 'done') = 'true' Then Break;
        Sleep(50);
      Until GetTickCount64 > Deadline;
      Check('successful configured tests remain linked to build', (Field(Reply, 'outcome') = 'test_command_passed')
        And (Field(Reply, 'build_job_id') = BuildID) And (Field(Reply, 'testsRun') = 'true'));
      Settings.Arguments[0] := 'test-failure'; Settings.Save;
      Check('changing configuration invalidates old test evidence', Broker.Execute(Run, 'lazarus_test_status', JobArgs, Reply, Err)
        And (Field(Reply, 'stale') = 'true'));
      Check('failing test runner starts', Broker.Execute(Run, 'lazarus_start_tests', TestArgs, Reply, Err));
      JobArgs := '{"job_id":"' + Field(Reply, 'job_id') + '"}'; Deadline := GetTickCount64 + 4000;
      Repeat
        Check('poll failing tests', Broker.Execute(Run, 'lazarus_test_status', JobArgs, Reply, Err));
        If Field(Reply, 'done') = 'true' Then Break;
        Sleep(50);
      Until GetTickCount64 > Deadline;
      Check('test failure cannot become compile success', Field(Reply, 'outcome') = 'test_command_failed');
      FirstID := JobArgs; StartAndWait;
      Check('replacement build invalidates earlier test evidence', Broker.Execute(Run, 'lazarus_test_status', FirstID, Reply, Err)
        And (Field(Reply, 'stale') = 'true'));
    Finally DeleteFile(Settings.StorageFilename); Settings.Free; RemoveDir(Root + '/assistant-tests'); End;
    Broker.OnApproval := Nil;
    Project.Mode := 'Release';
    Check('build-mode switch invalidates evidence', Broker.Execute(Run, 'lazarus_build_status', JobArgs, Reply, Err)
      And (Field(Reply, 'stale') = 'true'));
    Project.Mode := 'Debug'; Project.Dirty := True;
    Check('project settings must be explicitly saved', Not Broker.Execute(Run, 'lazarus_start_build', '{}', Reply, Err));
    Project.Dirty := False; Manager.Editor := Nil;
    WriteFile(Project.Member.Path, 'unit Closed; interface uses Indirect; implementation end.');
    CodeToolBoss.LoadFile(Project.Member.Path, True, True);
    WriteFile(Root + '/indirect.pas', 'unit Indirect; interface implementation end.');
    WriteFile(Root + '/system.pp', 'unit System; interface implementation end.');
    StartAndWait;
    Check('workspace reports complete CodeTools source closure', Field(Reply, 'dependencies.sourceClosureComplete') = 'true');
    WriteFile(Root + '/indirect.pas', 'unit Indirect; interface const Later = 1; implementation end.');
    Check('closed transitive dependency invalidates completed build', Broker.Execute(Run, 'lazarus_build_status', JobArgs, Reply, Err)
      And (Field(Reply, 'stale') = 'true'));
    CodeToolBoss.LoadFile(Root + '/indirect.pas', True, True); StartAndWait;
    WriteFile(Root + '/indirect.lfm', 'new resource');
    Check('new dependency resource invalidates completed build', Broker.Execute(Run, 'lazarus_build_status', JobArgs, Reply, Err)
      And (Field(Reply, 'stale') = 'true'));
    IDE.CancelWorkspace := Workspace;
    Check('cancellation in CodeTools callback prevents compiler launch', Not Broker.Execute(Run, 'lazarus_start_build', '{}', Reply, Err));
    Check('cancelled discovery leaves no job', Not Workspace.BuildStatus(Reply, Err));
    IDE.CancelWorkspace := Nil;
    DeleteFile(Project.Member.Path);
    Check('missing project source prevents launch', Not Broker.Execute(Run, 'lazarus_start_build', '{}', Reply, Err));
    Run := Broker.BeginRun(awsMarkdown);
    Check('Plan cannot launch compiler', Not Broker.Execute(Run, 'lazarus_start_build', '{}', Reply, Err));
  Finally
    Broker.Free; Workspace.Free; LazarusIDE := Nil; SourceEditorManagerIntf := Nil;
    IDE.Free; Manager.Free; Editor.Free; Project.Member.Free; Project.Free;
    DeleteFile(Root + '/indirect.pas'); DeleteFile(Root + '/indirect.lfm'); DeleteFile(Root + '/system.pp');
    DeleteFile(Root + '/open.pas'); DeleteFile(Root + '/closed.pas'); DeleteFile(Root + '/closed.lfm'); DeleteFile(Root + '/project.lpi'); RemoveDir(Root);
  End;
End.
