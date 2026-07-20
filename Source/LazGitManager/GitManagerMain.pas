Unit GitManagerMain;

{ Core registration, menus, commands and window creation for LazGitManager (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, LCLType, MenuIntf, IDECommands, IDEWindowIntf,
  LazIDEIntf, ProjectIntf;

Procedure RegisterGitManager;

Var
  GitGraphWindowCreator: TIDEWindowCreator;

Implementation

Uses
  WorkflowLog, WorkflowEvents, GitGraphForm, GitService;

Type
  { Holds IDE project handlers (must be methods of a class for TLazProjectChangedFunction). }
  TGitManagerIDEHooks = Class
  Public
    Function ProjectOpened(Sender: TObject; AProject: TLazProject): TModalResult;
    Function ProjectClose(Sender: TObject; AProject: TLazProject): TModalResult;
  End;

Var
  CmdGitGraph: TIDECommand;
  CmdGitStatus: TIDECommand;
  CmdGitCommit: TIDECommand;
  CmdGitPush: TIDECommand;
  CmdGitPull: TIDECommand;
  CmdGitFetch: TIDECommand;
  GitManagerIDEHooks: TGitManagerIDEHooks;

Function TGitManagerIDEHooks.ProjectOpened(Sender: TObject; AProject: TLazProject): TModalResult;
Var
  StartPath, RepoPath: String;
Begin
  Result := mrOk;
  If Not Assigned(AProject) Or AProject.IsVirtual Then
    Exit;
  If AProject.ProjectInfoFile <> '' Then
    StartPath := ExtractFilePath(ExpandFileName(AProject.ProjectInfoFile))
  Else If Assigned(AProject.MainFile) Then
    StartPath := ExtractFilePath(ExpandFileName(AProject.MainFile.Filename))
  Else
    Exit;
  If Assigned(GitClient) Then
    Begin
      RepoPath := GitClient.DetectRepository(StartPath);
      If RepoPath <> '' Then
        Begin
          GitClient.RepoPath := RepoPath;
          WorkflowLogger.Info('GitManager', 'Project opened – repository: ' + RepoPath);
          WorkflowEventBus.NotifyRepositoryStateChanged(RepoPath, grsUnknown);
        End
      Else
        WorkflowLogger.Warning('GitManager', 'Project opened – no Git repository above ' + StartPath);
    End;
  RefreshOpenGitGraphForms;
End;

Function TGitManagerIDEHooks.ProjectClose(Sender: TObject; AProject: TLazProject): TModalResult;
Begin
  Result := mrOk;
  If Assigned(GitClient) Then
    GitClient.RepoPath := '';
  RefreshOpenGitGraphForms;
End;

Procedure ShowGitGraphWindow(Sender: TObject);
Begin
  IDEWindowCreators.ShowForm(GitGraphWindowCreator.FormName, True);
End;

Procedure DoGitStatus(Sender: TObject);
Begin
  WorkflowLogger.Info('GitManager', 'Git Status requested');
  ShowGitGraphWindow(Sender);
  RefreshOpenGitGraphForms;
End;

Procedure DoGitCommit(Sender: TObject);
Begin
  WorkflowLogger.Info('GitManager', 'Git Commit requested');
  { TODO: show commit dialog }
End;

Procedure DoGitPush(Sender: TObject);
Begin
  WorkflowLogger.Info('GitManager', 'Git Push requested');
  If Assigned(GitClient) And (GitClient.RepoPath <> '') Then
    GitClient.Push
  Else
    WorkflowLogger.Warning('GitManager', 'Push skipped – no repository');
End;

Procedure DoGitPull(Sender: TObject);
Begin
  WorkflowLogger.Info('GitManager', 'Git Pull requested');
  If Assigned(GitClient) And (GitClient.RepoPath <> '') Then
    GitClient.Pull
  Else
    WorkflowLogger.Warning('GitManager', 'Pull skipped – no repository');
End;

Procedure DoGitFetch(Sender: TObject);
Begin
  WorkflowLogger.Info('GitManager', 'Git Fetch requested');
  If Assigned(GitClient) And (GitClient.RepoPath <> '') Then
    GitClient.Fetch
  Else
    WorkflowLogger.Warning('GitManager', 'Fetch skipped – no repository');
End;

Procedure CreateGitGraphForm(Sender: TObject; AFormName: String;
  Var AForm: TCustomForm; DoDisableAutoSizing: Boolean);
Begin
  IDEWindowCreators.CreateForm(AForm, TGitGraphForm, DoDisableAutoSizing, LazarusIDE.OwningComponent);
  AForm.Name := AFormName;
  If AForm Is TGitGraphForm Then
    TGitGraphForm(AForm).BindRepository;
End;

Procedure RegisterGitManager;
Var
  Parent: TIDEMenuSection;
  Key: TIDEShortCut;
  Cat: TIDECommandCategory;
Begin
  WorkflowLogger.Info('GitManager', 'Registering LazGitManager');

  If GitManagerIDEHooks = Nil Then
    GitManagerIDEHooks := TGitManagerIDEHooks.Create;

  Cat := IDECommandList.FindCategoryByName(CommandCategoryViewName);
  If Cat = Nil Then
    Cat := IDECommandList.CreateCategory(Nil, 'Git', 'Git');

  Key := IDEShortCut(VK_UNKNOWN, []);
  CmdGitGraph := RegisterIDECommand(Cat, 'GitGraph', 'Show Git Graph', Key, Nil, @ShowGitGraphWindow);
  CmdGitStatus := RegisterIDECommand(Cat, 'GitStatus', 'Git Status', Key, Nil, @DoGitStatus);
  CmdGitCommit := RegisterIDECommand(Cat, 'GitCommit', 'Git Commit', Key, Nil, @DoGitCommit);
  CmdGitPush := RegisterIDECommand(Cat, 'GitPush', 'Git Push', Key, Nil, @DoGitPush);
  CmdGitPull := RegisterIDECommand(Cat, 'GitPull', 'Git Pull', Key, Nil, @DoGitPull);
  CmdGitFetch := RegisterIDECommand(Cat, 'GitFetch', 'Git Fetch', Key, Nil, @DoGitFetch);

  Parent := RegisterIDEMenuSection(itmSecondaryTools, 'GitSection');
  Parent.Caption := 'Git';
  RegisterIDEMenuCommand(Parent, 'GitGraph', 'Git Graph', Nil, Nil, CmdGitGraph);
  RegisterIDEMenuCommand(Parent, 'GitStatus', 'Status', Nil, Nil, CmdGitStatus);
  RegisterIDEMenuCommand(Parent, 'GitCommit', 'Commit...', Nil, Nil, CmdGitCommit);
  RegisterIDEMenuSection(Parent, 'GitSep1');
  RegisterIDEMenuCommand(Parent, 'GitFetch', 'Fetch', Nil, Nil, CmdGitFetch);
  RegisterIDEMenuCommand(Parent, 'GitPull', 'Pull', Nil, Nil, CmdGitPull);
  RegisterIDEMenuCommand(Parent, 'GitPush', 'Push', Nil, Nil, CmdGitPush);

  GitGraphWindowCreator := IDEWindowCreators.Add('GitGraph', @CreateGitGraphForm, Nil,
    '100', '100', '900', '600');

  If Assigned(LazarusIDE) Then
    Begin
      LazarusIDE.AddHandlerOnProjectOpened(@GitManagerIDEHooks.ProjectOpened);
      LazarusIDE.AddHandlerOnProjectClose(@GitManagerIDEHooks.ProjectClose);
    End;

  WorkflowLogger.Info('GitManager', 'LazGitManager registered successfully');
End;

Initialization

GitManagerIDEHooks := Nil;

Finalization

If Assigned(LazarusIDE) And Assigned(GitManagerIDEHooks) Then
  Begin
    LazarusIDE.RemoveHandlerOnProjectOpened(@GitManagerIDEHooks.ProjectOpened);
    LazarusIDE.RemoveHandlerOnProjectClose(@GitManagerIDEHooks.ProjectClose);
  End;
FreeAndNil(GitManagerIDEHooks);

End.
