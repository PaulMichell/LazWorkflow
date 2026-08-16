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
  Dialogs, WorkflowLog, ManageRepositoryForm, GitService, GitConfig,
  GitSettingsForm, GitInitForm, GitCloneForm, GitJobRunner, GitPathUtils;

Type
  TGitManagerIDEHooks = Class
  Public
    Function ProjectOpened(Sender: TObject; AProject: TLazProject): TModalResult;
    Function ProjectClose(Sender: TObject; AProject: TLazProject): TModalResult;
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
  CmdRepoSettings: TIDECommand;
  GitManagerIDEHooks: TGitManagerIDEHooks;
  GitIdeJobHost: TGitIdeJobHost;

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
        End
      Else
        Begin
          GitClient.RepoPath := '';
          WorkflowLogger.Warning('GitManager', 'Project opened – no Git repository above ' + StartPath);
        End;
    End;
  RefreshOpenManageRepositoryForms;
  UpdateRepositoryMenuState;
End;

Function TGitManagerIDEHooks.ProjectClose(Sender: TObject; AProject: TLazProject): TModalResult;
Begin
  Result := mrOk;
  { Do not rebind from ActiveProject here – it is half-torn-down during close and
    was a source of access violations after browsing the Manage window. }
  If Assigned(GitClient) Then
    GitClient.RepoPath := '';
  ClearOpenManageRepositoryForms;
  UpdateRepositoryMenuState;
End;

Procedure ShowManageRepository(Sender: TObject);
Begin
  If Not CurrentProjectHasRepository Then
    Begin
      MessageDlg('No Git repository found for the current project.' + LineEnding +
        'Use Initialise Repository or Clone Repository first.', mtInformation, [mbOK], 0);
      UpdateRepositoryMenuState;
      Exit;
    End;
  IDEWindowCreators.ShowForm(ManageRepositoryWindowCreator.FormName, True);
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
        End
      Else
        MessageDlg('Clone failed: ' + Job.ErrorText, mtError, [mbOK], 0);
  Else
    { ignore }
  End;
End;

Procedure DoRepositorySettings(Sender: TObject);
Begin
  ShowGitSettingsForm;
  ApplyRepositoryConfigToOpenForms;
End;

Procedure CreateManageRepositoryForm(Sender: TObject; AFormName: String;
  Var AForm: TCustomForm; DoDisableAutoSizing: Boolean);
Begin
  AForm := Nil;
  Try
    IDEWindowCreators.CreateForm(AForm, TManageRepositoryForm, DoDisableAutoSizing,
      LazarusIDE.OwningComponent);
  Except
    On E: Exception Do
      Begin
        WorkflowLogger.Error('GitManager', 'CreateManageRepositoryForm CreateForm: ' + E.Message);
        { Fallback shell so IDE desktop restore does not leave a nil form. }
        FreeAndNil(AForm);
        AForm := TForm.Create(LazarusIDE.OwningComponent);
        AForm.Caption := 'Manage Repository';
      End;
  End;
  If Not Assigned(AForm) Then
    Exit;
  AForm.Name := AFormName;
  { Never let restore/bind failures kill the IDE process. }
  If AForm Is TManageRepositoryForm Then
    Try
      TManageRepositoryForm(AForm).BindRepository;
      TManageRepositoryForm(AForm).ApplyConfig;
    Except
      On E: Exception Do
        WorkflowLogger.Error('GitManager', 'CreateManageRepositoryForm bind: ' + E.Message);
    End;
End;

Procedure RegisterGitManager;
Var
  RepoMenu, MainSec, SetSec: TIDEMenuSection;
  Key: TIDEShortCut;
  Cat: TIDECommandCategory;
Begin
  Try
    WorkflowLogger.Info('GitManager', 'Registering LazRepositoryTools');

    If GitManagerIDEHooks = Nil Then
      GitManagerIDEHooks := TGitManagerIDEHooks.Create;

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
    CmdRepoInit := RegisterIDECommand(Cat, 'RepoInitialise', 'Initialise Repository',
      IDEShortCut(VK_I, [ssCtrl, ssShift], VK_UNKNOWN, []), Nil, @DoInitialiseRepository);
    CmdRepoManage := RegisterIDECommand(Cat, 'RepoManage', 'Manage Repository',
      IDEShortCut(VK_G, [ssCtrl, ssShift], VK_UNKNOWN, []), Nil, @ShowManageRepository);
    CmdRepoClone := RegisterIDECommand(Cat, 'RepoClone', 'Clone Repository',
      IDEShortCut(VK_C, [ssCtrl, ssShift], VK_UNKNOWN, []), Nil, @DoCloneRepository);
    CmdRepoSettings := RegisterIDECommand(Cat, 'RepoSettings', 'Repository Settings', Key, Nil, @DoRepositorySettings);

    { Top-level Repository menu, placed immediately after Run.
      Two logical sections so Lazarus draws a separator before Settings. }
    RepoMenu := RegisterIDESubMenu(mnuMain, 'Repository', 'Repository');
    If Assigned(mnuMain) And Assigned(mnuRun) And Assigned(RepoMenu) Then
      Begin
        mnuMain.Remove(RepoMenu);
        mnuMain.Insert(mnuRun.SectionIndex + 1, RepoMenu);
      End;
    MainSec := RegisterIDEMenuSection(RepoMenu, 'RepoMainCmds');
    RegisterIDEMenuCommand(MainSec, 'RepoInitialise', 'Initialise Repository', Nil, Nil, CmdRepoInit);
    RegisterIDEMenuCommand(MainSec, 'RepoManage', 'Manage Repository', Nil, Nil, CmdRepoManage);
    RegisterIDEMenuCommand(MainSec, 'RepoClone', 'Clone Repository', Nil, Nil, CmdRepoClone);
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
  If Assigned(LazarusIDE) And Assigned(GitManagerIDEHooks) Then
    Begin
      LazarusIDE.RemoveHandlerOnProjectOpened(@GitManagerIDEHooks.ProjectOpened);
      LazarusIDE.RemoveHandlerOnProjectClose(@GitManagerIDEHooks.ProjectClose);
    End;
Except
End;
FreeAndNil(GitManagerIDEHooks);
FreeAndNil(GitIdeJobHost);

End.
