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
  ManageRepositoryWindowCreator: TIDEWindowCreator;

Implementation

Uses
  Dialogs, WorkflowLog, WorkflowEvents, GitGraphForm, GitService, GitConfig, GitSettingsForm;

Type
  TGitManagerIDEHooks = Class
  Public
    Function ProjectOpened(Sender: TObject; AProject: TLazProject): TModalResult;
    Function ProjectClose(Sender: TObject; AProject: TLazProject): TModalResult;
  End;

Var
  CmdRepoInit: TIDECommand;
  CmdRepoManage: TIDECommand;
  CmdRepoSettings: TIDECommand;
  GitManagerIDEHooks: TGitManagerIDEHooks;

Function ProjectStartPath(AProject: TLazProject): String;
Begin
  Result := '';
  If Not Assigned(AProject) Or AProject.IsVirtual Then
    Exit;
  If AProject.ProjectInfoFile <> '' Then
    Result := ExtractFilePath(ExpandFileName(AProject.ProjectInfoFile))
  Else If Assigned(AProject.MainFile) And (AProject.MainFile.Filename <> '') Then
    Result := ExtractFilePath(ExpandFileName(AProject.MainFile.Filename));
End;

Function TGitManagerIDEHooks.ProjectOpened(Sender: TObject; AProject: TLazProject): TModalResult;
Var
  StartPath, RepoPath: String;
Begin
  Result := mrOk;
  StartPath := ProjectStartPath(AProject);
  If StartPath = '' Then
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

Procedure ShowManageRepository(Sender: TObject);
Begin
  IDEWindowCreators.ShowForm(ManageRepositoryWindowCreator.FormName, True);
End;

Procedure DoInitialiseRepository(Sender: TObject);
Var
  StartPath, RepoPath: String;
  Project: TLazProject;
Begin
  If Not Assigned(LazarusIDE) Or Not Assigned(GitClient) Then
    Exit;
  Project := LazarusIDE.ActiveProject;
  StartPath := ProjectStartPath(Project);
  If StartPath = '' Then
    Begin
      MessageDlg('Open a saved project before initialising a repository.', mtInformation, [mbOK], 0);
      Exit;
    End;

  RepoPath := GitClient.DetectRepository(StartPath);
  If RepoPath <> '' Then
    Begin
      MessageDlg('This project is already inside a Git repository:' + LineEnding + RepoPath,
        mtInformation, [mbOK], 0);
      GitClient.RepoPath := RepoPath;
      ShowManageRepository(Sender);
      Exit;
    End;

  If MessageDlg('Initialise a new Git repository in:' + LineEnding + StartPath + LineEnding + LineEnding +
    'Continue?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes Then
    Exit;

  If GitClient.InitRepository(StartPath) Then
    Begin
      MessageDlg('Repository initialised at:' + LineEnding + StartPath, mtInformation, [mbOK], 0);
      ShowManageRepository(Sender);
      RefreshOpenGitGraphForms;
    End
  Else
    MessageDlg('Failed to initialise repository. See the log for details.', mtError, [mbOK], 0);
End;

Procedure DoRepositorySettings(Sender: TObject);
Begin
  ShowGitSettingsForm;
  ApplyGitConfigToOpenForms;
End;

Procedure CreateManageRepositoryForm(Sender: TObject; AFormName: String;
  Var AForm: TCustomForm; DoDisableAutoSizing: Boolean);
Begin
  IDEWindowCreators.CreateForm(AForm, TGitGraphForm, DoDisableAutoSizing, LazarusIDE.OwningComponent);
  AForm.Name := AFormName;
  If AForm Is TGitGraphForm Then
    Begin
      TGitGraphForm(AForm).BindRepository;
      TGitGraphForm(AForm).ApplyConfig;
    End;
End;

Procedure RegisterGitManager;
Var
  RepoMenu: TIDEMenuSection;
  Key: TIDEShortCut;
  Cat: TIDECommandCategory;
Begin
  WorkflowLogger.Info('GitManager', 'Registering LazGitManager');

  If GitManagerIDEHooks = Nil Then
    GitManagerIDEHooks := TGitManagerIDEHooks.Create;

  If Assigned(GitManagerConfig) Then
    GitManagerConfig.Load;

  Cat := IDECommandList.FindCategoryByName(CommandCategoryViewName);
  If Cat = Nil Then
    Cat := IDECommandList.CreateCategory(Nil, 'Repository', 'Repository');

  Key := IDEShortCut(VK_UNKNOWN, []);
  CmdRepoInit := RegisterIDECommand(Cat, 'RepoInitialise', 'Initialise Repository', Key, Nil, @DoInitialiseRepository);
  CmdRepoManage := RegisterIDECommand(Cat, 'RepoManage', 'Manage Repository',
    IDEShortCut(VK_G, [ssCtrl, ssShift], VK_UNKNOWN, []), Nil, @ShowManageRepository);
  CmdRepoSettings := RegisterIDECommand(Cat, 'RepoSettings', 'Repository Settings', Key, Nil, @DoRepositorySettings);

  { Top-level Repository menu on the IDE main menu bar. }
  RepoMenu := RegisterIDESubMenu(mnuMain, 'Repository', 'Repository');
  RegisterIDEMenuCommand(RepoMenu, 'RepoInitialise', 'Initialise Repository', Nil, Nil, CmdRepoInit);
  RegisterIDEMenuCommand(RepoMenu, 'RepoManage', 'Manage Repository', Nil, Nil, CmdRepoManage);
  RegisterIDEMenuSection(RepoMenu, 'RepoSep1');
  RegisterIDEMenuCommand(RepoMenu, 'RepoSettings', 'Settings...', Nil, Nil, CmdRepoSettings);

  ManageRepositoryWindowCreator := IDEWindowCreators.Add('ManageRepository', @CreateManageRepositoryForm, Nil,
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
