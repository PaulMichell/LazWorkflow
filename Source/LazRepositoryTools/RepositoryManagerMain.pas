Unit RepositoryManagerMain;

{ Core registration, menus, commands and window creation for LazRepositoryTools (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, LCLType, MenuIntf, IDECommands, IDEWindowIntf,
  LazIDEIntf, ProjectIntf;

Procedure RegisterGitManager;
Procedure UpdateRepositoryMenuState;

Var
  ManageRepositoryWindowCreator: TIDEWindowCreator;

Implementation

Uses
  Dialogs, LazFileUtils, WorkflowLog, ManageRepositoryForm, GitService, GitConfig,
  GitSettingsForm, GitInitForm, GitCloneForm, GitJobRunner, GitPathUtils, WorkflowSettings;

Type
  TGitManagerIDEHooks = Class
  Public
    Function ProjectOpened(Sender: TObject; AProject: TLazProject): TModalResult;
    Function ProjectClose(Sender: TObject; AProject: TLazProject): TModalResult;
    Procedure RepositoryMenuShow(Sender: TObject);
    Procedure OpenRecentClicked(Sender: TObject);
  End;

  { Hosts OnFinished for IDE-level clone/init jobs (no form required). }
  TGitIdeJobHost = Class
  Public
    Procedure JobFinished(Job: TGitJob);
  End;

Var
  CmdRepoInit: TIDECommand;
  CmdRepoManage: TIDECommand;
  CmdRepoClone: TIDECommand;
  CmdRepoOpen: TIDECommand;
  CmdRepoSettings: TIDECommand;
  GitManagerIDEHooks: TGitManagerIDEHooks;
  GitIdeJobHost: TGitIdeJobHost;
  RepoMenuSection: TIDEMenuSection;
  RepoOpenRecentMenu: TIDEMenuSection;

Function MenuCaptionFromPath(Const Path: String): String;
Begin
  Result := StringReplace(Path, '&', '&&', [rfReplaceAll]);
End;

Procedure RebuildOpenRecentMenu;
Var
  Paths: TStringList;
  Index, Needed: Integer;
  Item: TIDEMenuItem;
Begin
  If Not Assigned(RepoOpenRecentMenu) Or Not Assigned(GitManagerIDEHooks) Then Exit;
  Paths := TStringList.Create;
  Try
    If Assigned(GitManagerConfig) Then
      GitManagerConfig.CopyRecentPaths(Paths);
    Needed := Paths.Count;
    If Needed = 0 Then Needed := 1;
    While RepoOpenRecentMenu.Count < Needed Do
      RegisterIDEMenuCommand(RepoOpenRecentMenu, 'RepoRecent' + IntToStr(RepoOpenRecentMenu.Count), '');
    While RepoOpenRecentMenu.Count > Needed Do
      RepoOpenRecentMenu.Items[RepoOpenRecentMenu.Count - 1].Free;
    If Paths.Count = 0 Then
      Begin
        Item := RepoOpenRecentMenu.Items[0];
        Item.Caption := '(No recent repositories)';
        Item.Hint := '';
        Item.Enabled := False;
        Item.OnClick := Nil;
      End
    Else
      For Index := 0 To Paths.Count - 1 Do
        Begin
          Item := RepoOpenRecentMenu.Items[Index];
          Item.Caption := MenuCaptionFromPath(Paths[Index]);
          Item.Hint := Paths[Index];
          Item.Enabled := True;
          Item.OnClick := @GitManagerIDEHooks.OpenRecentClicked;
        End;
    RepoOpenRecentMenu.Enabled := True;
  Finally
    Paths.Free;
  End;
End;

Procedure RememberOpenedRepository(Const RepoPath: String);
Begin
  If Assigned(GitManagerConfig) Then
    GitManagerConfig.RememberRepository(RepoPath);
  RebuildOpenRecentMenu;
End;

Function CurrentProjectHasRepository: Boolean;
Var
  StartPath: String;
Begin
  Result := False;
  Try
    If Not Assigned(LazarusIDE) Or Not Assigned(GitClient) Then
      Exit;
    StartPath := GitProjectStartPath(LazarusIDE.ActiveProject);
    If StartPath = '' Then
      Exit;
    Result := GitClient.DetectRepository(StartPath) <> '';
  Except
    Result := False;
  End;
End;

Procedure UpdateRepositoryMenuState;
Var
  HasRepo: Boolean;
Begin
  HasRepo := CurrentProjectHasRepository;
  If Assigned(CmdRepoManage) Then
    CmdRepoManage.Enabled := HasRepo;
End;

Function TGitManagerIDEHooks.ProjectOpened(Sender: TObject; AProject: TLazProject): TModalResult;
Var
  StartPath, RepoPath: String;
Begin
  Result := mrOk;
  Try
    StartPath := GitProjectStartPath(AProject);
    If StartPath = '' Then
      Begin
        UpdateRepositoryMenuState;
        Exit;
      End;
    If Assigned(GitClient) Then
      Begin
        RepoPath := GitClient.DetectRepository(StartPath);
        If RepoPath <> '' Then
          Begin
            GitClient.RepoPath := RepoPath;
            WorkflowLogger.Info('GitManager', 'Project opened – repository: ' + RepoPath);
            RememberOpenedRepository(RepoPath);
          End
        Else
          Begin
            GitClient.RepoPath := '';
            WorkflowLogger.Warning('GitManager', 'Project opened – no Git repository above ' + StartPath);
          End;
      End;
    RefreshOpenManageRepositoryForms;
    UpdateRepositoryMenuState;
  Except
    On E: Exception Do
      Begin
        WorkflowLogger.Error('PluginBoundary', 'TGitManagerIDEHooks.ProjectOpened: ' + E.Message);
      End;
  End;
End;

Function TGitManagerIDEHooks.ProjectClose(Sender: TObject; AProject: TLazProject): TModalResult;
Begin
  Result := mrOk;
  Try
    { Do not rebind from ActiveProject here – it is half-torn-down during close and
      was a source of access violations after browsing the Manage window. }
    If Assigned(GitClient) Then
      GitClient.RepoPath := '';
    ClearOpenManageRepositoryForms;
    { ActiveProject is being destroyed; do not query it from the close hook. }
    If Assigned(CmdRepoManage) Then CmdRepoManage.Enabled := False;
  Except
    On E: Exception Do
      Begin
        WorkflowLogger.Error('PluginBoundary', 'TGitManagerIDEHooks.ProjectClose: ' + E.Message);
      End;
  End;
End;

Procedure ShowManageRepositoryAt(Const RepoPath: String);
Var
  I: Integer;
  Form: TCustomForm;
Begin
  Try
    If RepoPath = '' Then
      Exit;
    RememberOpenedRepository(RepoPath);
    If Assigned(GitClient) Then
      GitClient.RepoPath := RepoPath;
    If Assigned(IDEWindowCreators) And Assigned(ManageRepositoryWindowCreator) Then
      IDEWindowCreators.ShowForm(ManageRepositoryWindowCreator.FormName, True);
    For I := Screen.CustomFormCount - 1 DownTo 0 Do
      Begin
        Form := Screen.CustomForms[I];
        If (Form Is TManageRepositoryForm) And Not (csDestroying in Form.ComponentState) Then
          TManageRepositoryForm(Form).SetRepository(RepoPath);
      End;
  Except
    On E: Exception Do
      Begin
        WorkflowLogger.Error('PluginBoundary', 'ShowManageRepositoryAt: ' + E.Message);
      End;
  End;
End;

Procedure ShowManageRepository(Sender: TObject);
Begin
  Try
    If Not CurrentProjectHasRepository Then
      Begin
        MessageDlg('No Git repository found for the current project.' + LineEnding +
          'Use Initialise Repository, Clone Repository, Open Repository or Open Recent.',
          mtInformation, [mbOK], 0);
        UpdateRepositoryMenuState;
        Exit;
      End;
    If Not Assigned(IDEWindowCreators) Or Not Assigned(ManageRepositoryWindowCreator) Then Exit;
    IDEWindowCreators.ShowForm(ManageRepositoryWindowCreator.FormName, True);
    RefreshOpenManageRepositoryForms;
    If Assigned(GitClient) And (GitClient.RepoPath <> '') Then
      RememberOpenedRepository(GitClient.RepoPath);
  Except
    On E: Exception Do
      Begin
        WorkflowLogger.Error('PluginBoundary', 'ShowManageRepository: ' + E.Message);
      End;
  End;
End;

Procedure DoOpenRepository(Sender: TObject);
Var
  Dialog: TSelectDirectoryDialog;
  DefaultPath, ChosenPath, RepoPath: String;
Begin
  If Not Assigned(GitClient) Then
    Exit;
  DefaultPath := GitIdeStartPath;
  If (DefaultPath = '') And (GitClient.RepoPath <> '') Then
    DefaultPath := GitClient.RepoPath;
  If DefaultPath = '' Then
    DefaultPath := GetCurrentDir;

  Dialog := TSelectDirectoryDialog.Create(Nil);
  Try
    Dialog.Title := 'Open Repository';
    Dialog.InitialDir := DefaultPath;
    If Not Dialog.Execute Then
      Exit;
    ChosenPath := Trim(Dialog.FileName);
  Finally
    Dialog.Free;
  End;

  If ChosenPath = '' Then
    Exit;
  RepoPath := GitClient.DetectRepository(ChosenPath);
  If RepoPath = '' Then
    Begin
      MessageDlg('No Git repository found in or above:' + LineEnding + ChosenPath,
        mtInformation, [mbOK], 0);
      Exit;
    End;
  ShowManageRepositoryAt(RepoPath);
End;

Procedure DoInitialiseRepository(Sender: TObject);
Var
  DefaultPath, ChosenPath, RepoPath: String;
  Project: TLazProject;
  Job: TGitJob;
Begin
  If Not Assigned(LazarusIDE) Or Not Assigned(GitClient) Then
    Exit;
  Project := LazarusIDE.ActiveProject;
  DefaultPath := GitProjectStartPath(Project);
  If DefaultPath = '' Then
    DefaultPath := GetCurrentDir;

  If Not ShowGitInitForm(DefaultPath, ChosenPath) Then
    Exit;

  RepoPath := GitClient.DetectRepository(ChosenPath);
  If RepoPath <> '' Then
    Begin
      MessageDlg('This folder is already inside a Git repository:' + LineEnding + RepoPath,
        mtInformation, [mbOK], 0);
      GitClient.RepoPath := RepoPath;
      UpdateRepositoryMenuState;
      ShowManageRepository(Sender);
      RememberOpenedRepository(RepoPath);
      Exit;
    End;

  If Not Assigned(GitJobs) Or Not Assigned(GitIdeJobHost) Then
    Begin
      If GitClient.InitRepository(ChosenPath) Then
        Begin
          MessageDlg('Repository initialised at:' + LineEnding + ChosenPath, mtInformation, [mbOK], 0);
          UpdateRepositoryMenuState;
          ShowManageRepository(Sender);
          RefreshOpenManageRepositoryForms;
          RememberOpenedRepository(ChosenPath);
        End
      Else
        MessageDlg('Failed to initialise repository: ' + GitClient.LastError, mtError, [mbOK], 0);
      Exit;
    End;
  Job := TGitJob.Create(gjkInit);
  Job.TargetDir := ChosenPath;
  Job.OnFinished := @GitIdeJobHost.JobFinished;
  Screen.Cursor := crHourGlass;
  If Not GitJobs.Submit(Job) Then
    Begin
      Screen.Cursor := crDefault;
      MessageDlg('Could not queue initialise repository.', mtWarning, [mbOK], 0);
    End;
End;

Procedure DoCloneRepository(Sender: TObject);
Var
  DefaultPath, Url, Target: String;
  Job: TGitJob;
Begin
  If Not Assigned(GitClient) Then
    Exit;
  If Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject) Then
    DefaultPath := GitProjectStartPath(LazarusIDE.ActiveProject)
  Else
    DefaultPath := GetCurrentDir;
  If DefaultPath = '' Then
    DefaultPath := GetCurrentDir;

  If Not ShowGitCloneForm(DefaultPath, Url, Target) Then
    Exit;

  If Not Assigned(GitJobs) Or Not Assigned(GitIdeJobHost) Then
    Begin
      Screen.Cursor := crHourGlass;
      Try
        If GitClient.CloneRepository(Url, Target) Then
          Begin
            MessageDlg('Cloned successfully into:' + LineEnding + Target, mtInformation, [mbOK], 0);
            UpdateRepositoryMenuState;
            If CurrentProjectHasRepository Then
              ShowManageRepository(Sender);
            RememberOpenedRepository(Target);
          End
        Else
          MessageDlg('Clone failed: ' + GitClient.LastError, mtError, [mbOK], 0);
      Finally
        Screen.Cursor := crDefault;
      End;
      Exit;
    End;

  Job := TGitJob.Create(gjkClone);
  Job.Url := Url;
  Job.TargetDir := Target;
  Job.OnFinished := @GitIdeJobHost.JobFinished;
  Screen.Cursor := crHourGlass;
  If Not GitJobs.Submit(Job) Then
    Begin
      Screen.Cursor := crDefault;
      MessageDlg('Could not queue clone.', mtWarning, [mbOK], 0);
    End;
End;

Procedure TGitIdeJobHost.JobFinished(Job: TGitJob);
Begin
  Screen.Cursor := crDefault;
  If Not Assigned(Job) Then
    Exit;
  If Job.Cancelled Then
    Begin
      MessageDlg('Operation cancelled.', mtInformation, [mbOK], 0);
      Exit;
    End;
  Case Job.Kind Of
    gjkInit:
      If Job.Ok Then
        Begin
          MessageDlg('Repository initialised at:' + LineEnding + Job.TargetDir, mtInformation, [mbOK], 0);
          UpdateRepositoryMenuState;
          ShowManageRepository(Nil);
          RefreshOpenManageRepositoryForms;
          RememberOpenedRepository(Job.TargetDir);
        End
      Else
        MessageDlg('Failed to initialise repository: ' + Job.ErrorText, mtError, [mbOK], 0);
    gjkClone:
      If Job.Ok Then
        Begin
          MessageDlg('Cloned successfully into:' + LineEnding + Job.TargetDir, mtInformation, [mbOK], 0);
          UpdateRepositoryMenuState;
          If CurrentProjectHasRepository Then
            ShowManageRepository(Nil);
          RememberOpenedRepository(Job.TargetDir);
        End
      Else
        MessageDlg('Clone failed: ' + Job.ErrorText, mtError, [mbOK], 0);
  Else
    { ignore }
  End;
End;

Procedure TGitManagerIDEHooks.RepositoryMenuShow(Sender: TObject);
Begin
  If Not Assigned(Sender) Then Exit;
  RebuildOpenRecentMenu;
End;

Procedure TGitManagerIDEHooks.OpenRecentClicked(Sender: TObject);
Var
  Path, RepoPath: String;
Begin
  If Not (Sender Is TIDEMenuItem) Then Exit;
  Path := Trim(TIDEMenuItem(Sender).Hint);
  If Path = '' Then Exit;
  If Not DirectoryExistsUTF8(Path) Then
    Begin
      MessageDlg('The repository folder no longer exists:' + LineEnding + Path,
        mtInformation, [mbOK], 0);
      If Assigned(GitManagerConfig) Then GitManagerConfig.ForgetRepository(Path);
      RebuildOpenRecentMenu;
      Exit;
    End;
  If Not Assigned(GitClient) Then Exit;
  RepoPath := GitClient.DetectRepository(Path);
  If RepoPath = '' Then
    Begin
      MessageDlg('No Git repository found in or above:' + LineEnding + Path,
        mtInformation, [mbOK], 0);
      If Assigned(GitManagerConfig) Then GitManagerConfig.ForgetRepository(Path);
      RebuildOpenRecentMenu;
      Exit;
    End;
  If (CompareFilenames(Path, RepoPath) <> 0) And Assigned(GitManagerConfig) Then
    GitManagerConfig.ForgetRepository(Path);
  ShowManageRepositoryAt(RepoPath);
End;

Procedure DoRepositorySettings(Sender: TObject);
Begin
  ShowGitSettingsForm;
  ApplyRepositoryConfigToOpenForms;
  RebuildOpenRecentMenu;
End;

Procedure CreateManageRepositoryForm(Sender: TObject; AFormName: String;
  Var AForm: TCustomForm; DoDisableAutoSizing: Boolean);
Begin
  AForm := Nil;
  If Not Assigned(LazarusIDE) Then Exit;
  Try
    { Assign only after construction succeeds. The IDE helper publishes a raw
      instance before Create, which can leave a dangling pointer on failure. }
    AForm := TManageRepositoryForm.Create(LazarusIDE.OwningComponent);
    AForm.Name := AFormName;
    If DoDisableAutoSizing Then
      AForm.DisableAutoSizing{$IFDEF DebugDisableAutoSizing}('TAnchorDockMaster Delayed'){$ENDIF};
    If Assigned(GitClient) And (GitClient.RepoPath <> '') Then
      TManageRepositoryForm(AForm).SetRepository(GitClient.RepoPath)
    Else
      TManageRepositoryForm(AForm).BindRepository;
    TManageRepositoryForm(AForm).ApplyConfig;
  Except
    On E: Exception Do
      Begin
        WorkflowLogger.Error('GitManager', 'CreateManageRepositoryForm: ' + E.Message);
        FreeAndNil(AForm);
      End;
  End;
End;

Procedure RegisterGitManager;
Var
  RepoMenu, ManageSec, SetupSec, SetSec: TIDEMenuSection;
  Key: TIDEShortCut;
  Cat: TIDECommandCategory;
Begin
  Try
    WorkflowLogger.Info('GitManager', 'Registering LazRepositoryTools');

    If GitManagerIDEHooks = Nil Then
      GitManagerIDEHooks := TGitManagerIDEHooks.Create;

    If Assigned(LazarusIDE) Then
      SetWorkflowSettingsDirectory(LazarusIDE.GetPrimaryConfigPath);
    If Assigned(GitManagerConfig) Then
      Try
        GitManagerConfig.Load;
      Except
        On E: Exception Do
          WorkflowLogger.Warning('GitManager', 'Config load failed: ' + E.Message);
      End;

    Cat := IDECommandList.FindCategoryByName(CommandCategoryViewName);
    If Cat = Nil Then
      Cat := IDECommandList.CreateCategory(Nil, 'Repository', 'Repository');

    Key := IDEShortCut(VK_UNKNOWN, []);
    CmdRepoManage := RegisterIDECommand(Cat, 'RepoManage', 'Manage Project Repository',
      IDEShortCut(VK_G, [ssCtrl, ssShift], VK_UNKNOWN, []), Nil, @ShowManageRepository);
    CmdRepoInit := RegisterIDECommand(Cat, 'RepoInitialise', 'Initialise Repository',
      IDEShortCut(VK_I, [ssCtrl, ssShift], VK_UNKNOWN, []), Nil, @DoInitialiseRepository);
    CmdRepoClone := RegisterIDECommand(Cat, 'RepoClone', 'Clone Repository',
      IDEShortCut(VK_C, [ssCtrl, ssShift], VK_UNKNOWN, []), Nil, @DoCloneRepository);
    CmdRepoOpen := RegisterIDECommand(Cat, 'RepoOpen', 'Open Repository',
      IDEShortCut(VK_O, [ssCtrl, ssShift], VK_UNKNOWN, []), Nil, @DoOpenRepository);
    CmdRepoSettings := RegisterIDECommand(Cat, 'RepoSettings', 'Repository Settings', Key, Nil, @DoRepositorySettings);

    { Top-level Repository menu, placed immediately after Run.
      Three sections: Manage; Initialise / Clone / Open / Open Recent; Settings. }
    RepoMenu := RegisterIDESubMenu(mnuMain, 'Repository', 'Repository');
    If Assigned(mnuMain) And Assigned(mnuRun) And Assigned(RepoMenu) Then
      Begin
        mnuMain.Remove(RepoMenu);
        mnuMain.Insert(mnuRun.SectionIndex + 1, RepoMenu);
      End;
    ManageSec := RegisterIDEMenuSection(RepoMenu, 'RepoManageCmds');
    RegisterIDEMenuCommand(ManageSec, 'RepoManage', 'Manage Project Repository', Nil, Nil, CmdRepoManage);
    SetupSec := RegisterIDEMenuSection(RepoMenu, 'RepoSetupCmds');
    RegisterIDEMenuCommand(SetupSec, 'RepoInitialise', 'Initialise Repository', Nil, Nil, CmdRepoInit);
    RegisterIDEMenuCommand(SetupSec, 'RepoClone', 'Clone Repository', Nil, Nil, CmdRepoClone);
    RegisterIDEMenuCommand(SetupSec, 'RepoOpen', 'Open Repository...', Nil, Nil, CmdRepoOpen);
    RepoOpenRecentMenu := RegisterIDESubMenu(SetupSec, 'RepoOpenRecent', 'Open Recent');
    RepoMenuSection := RepoMenu;
    If Assigned(GitManagerIDEHooks) Then
      RepoMenu.AddHandlerOnShow(@GitManagerIDEHooks.RepositoryMenuShow);
    RebuildOpenRecentMenu;
    SetSec := RegisterIDEMenuSection(RepoMenu, 'RepoSettingsCmds');
    RegisterIDEMenuCommand(SetSec, 'RepoSettings', 'Settings...', Nil, Nil, CmdRepoSettings);

    ManageRepositoryWindowCreator := IDEWindowCreators.Add('ManageRepository', @CreateManageRepositoryForm, Nil,
      '100', '100', '900', '600');

    If Assigned(LazarusIDE) Then
      Begin
        LazarusIDE.AddHandlerOnProjectOpened(@GitManagerIDEHooks.ProjectOpened);
        LazarusIDE.AddHandlerOnProjectClose(@GitManagerIDEHooks.ProjectClose);
      End;

    { Do not probe git / ActiveProject during Register — IDE is still starting. }
    WorkflowLogger.Info('GitManager', 'LazRepositoryTools registered successfully');
  Except
    On E: Exception Do
      Begin
        WorkflowLogger.Error('GitManager', 'RegisterGitManager failed: ' + E.Message);
        { Swallow so a registration fault does not prevent the IDE from starting. }
      End;
  End;
End;

Initialization

GitManagerIDEHooks := Nil;
GitIdeJobHost := TGitIdeJobHost.Create;

Finalization

Try
  If Assigned(RepoMenuSection) And Assigned(GitManagerIDEHooks) Then
    RepoMenuSection.RemoveHandlerOnShow(@GitManagerIDEHooks.RepositoryMenuShow);
  If Assigned(LazarusIDE) And Assigned(GitManagerIDEHooks) Then
    Begin
      LazarusIDE.RemoveHandlerOnProjectOpened(@GitManagerIDEHooks.ProjectOpened);
      LazarusIDE.RemoveHandlerOnProjectClose(@GitManagerIDEHooks.ProjectClose);
    End;
Except
End;
FreeAndNil(GitManagerIDEHooks);
If Assigned(GitJobs) And Assigned(GitIdeJobHost) Then
  Begin
    GitJobs.CancelIfHandler(@GitIdeJobHost.JobFinished);
    GitJobs.DetachFinishedHandler(@GitIdeJobHost.JobFinished);
  End;
FreeAndNil(GitIdeJobHost);

End.
