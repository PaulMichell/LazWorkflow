Unit GitManagerMain;

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
  Dialogs, WorkflowLog, WorkflowEvents, GitGraphForm, GitService, GitConfig,
  GitSettingsForm, GitInitForm, GitCloneForm;

Type
  TGitManagerIDEHooks = Class
  Public
    Function ProjectOpened(Sender: TObject; AProject: TLazProject): TModalResult;
    Function ProjectClose(Sender: TObject; AProject: TLazProject): TModalResult;
  End;

Var
  CmdRepoInit: TIDECommand;
  CmdRepoManage: TIDECommand;
  CmdRepoClone: TIDECommand;
  CmdRepoSettings: TIDECommand;
  GitManagerIDEHooks: TGitManagerIDEHooks;

Function ProjectStartPath(AProject: TLazProject): String;
Begin
  Result := '';
  Try
    If Not Assigned(AProject) Or AProject.IsVirtual Then
      Exit;
    If AProject.ProjectInfoFile <> '' Then
      Result := ExtractFilePath(ExpandFileName(AProject.ProjectInfoFile))
    Else If Assigned(AProject.MainFile) And (AProject.MainFile.Filename <> '') Then
      Result := ExtractFilePath(ExpandFileName(AProject.MainFile.Filename));
  Except
    Result := '';
  End;
End;

Function CurrentProjectHasRepository: Boolean;
Var
  StartPath: String;
Begin
  Result := False;
  Try
    If Not Assigned(LazarusIDE) Or Not Assigned(GitClient) Then
      Exit;
    StartPath := ProjectStartPath(LazarusIDE.ActiveProject);
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
  StartPath := ProjectStartPath(AProject);
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
          WorkflowEventBus.NotifyRepositoryStateChanged(RepoPath, grsUnknown);
        End
      Else
        Begin
          GitClient.RepoPath := '';
          WorkflowLogger.Warning('GitManager', 'Project opened – no Git repository above ' + StartPath);
        End;
    End;
  RefreshOpenGitGraphForms;
  UpdateRepositoryMenuState;
End;

Function TGitManagerIDEHooks.ProjectClose(Sender: TObject; AProject: TLazProject): TModalResult;
Begin
  Result := mrOk;
  { Do not rebind from ActiveProject here – it is half-torn-down during close and
    was a source of access violations after browsing the Manage window. }
  If Assigned(GitClient) Then
    GitClient.RepoPath := '';
  ClearOpenGitGraphForms;
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
Begin
  If Not Assigned(LazarusIDE) Or Not Assigned(GitClient) Then
    Exit;
  Project := LazarusIDE.ActiveProject;
  DefaultPath := ProjectStartPath(Project);
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

  If GitClient.InitRepository(ChosenPath) Then
    Begin
      MessageDlg('Repository initialised at:' + LineEnding + ChosenPath, mtInformation, [mbOK], 0);
      UpdateRepositoryMenuState;
      ShowManageRepository(Sender);
      RefreshOpenGitGraphForms;
    End
  Else
    MessageDlg('Failed to initialise repository: ' + GitClient.LastError, mtError, [mbOK], 0);
End;

Procedure DoCloneRepository(Sender: TObject);
Var
  DefaultPath, Url, Target: String;
Begin
  If Not Assigned(GitClient) Then
    Exit;
  If Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject) Then
    DefaultPath := ProjectStartPath(LazarusIDE.ActiveProject)
  Else
    DefaultPath := GetCurrentDir;
  If DefaultPath = '' Then
    DefaultPath := GetCurrentDir;

  If Not ShowGitCloneForm(DefaultPath, Url, Target) Then
    Exit;

  Screen.Cursor := crHourGlass;
  Try
    If GitClient.CloneRepository(Url, Target) Then
      Begin
        MessageDlg('Cloned successfully into:' + LineEnding + Target, mtInformation, [mbOK], 0);
        UpdateRepositoryMenuState;
        { Open manage if the active project is under the clone; otherwise just notify. }
        If CurrentProjectHasRepository Then
          ShowManageRepository(Sender);
      End
    Else
      MessageDlg('Clone failed: ' + GitClient.LastError, mtError, [mbOK], 0);
  Finally
    Screen.Cursor := crDefault;
  End;
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
  RepoMenu, MainSec, SetSec: TIDEMenuSection;
  Key: TIDEShortCut;
  Cat: TIDECommandCategory;
Begin
  WorkflowLogger.Info('GitManager', 'Registering LazRepositoryTools');

  If GitManagerIDEHooks = Nil Then
    GitManagerIDEHooks := TGitManagerIDEHooks.Create;

  If Assigned(GitManagerConfig) Then
    GitManagerConfig.Load;

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

  UpdateRepositoryMenuState;
  WorkflowLogger.Info('GitManager', 'LazRepositoryTools registered successfully');
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
