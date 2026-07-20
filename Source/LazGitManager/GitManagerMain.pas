Unit GitManagerMain;

{ Core registration, menus, commands and window creation for LazGitManager (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, LCLType, MenuIntf, IDECommands, IDEWindowIntf,
  LazIDEIntf;

Procedure RegisterGitManager;

Var
  GitGraphWindowCreator: TIDEWindowCreator;

Implementation

Uses
  WorkflowLog, WorkflowEvents, GitGraphForm, GitService;

Var
  CmdGitGraph: TIDECommand;
  CmdGitStatus: TIDECommand;
  CmdGitCommit: TIDECommand;
  CmdGitPush: TIDECommand;
  CmdGitPull: TIDECommand;
  CmdGitFetch: TIDECommand;

Procedure ShowGitGraphWindow(Sender: TObject);
Begin
  IDEWindowCreators.ShowForm(GitGraphWindowCreator.FormName, True);
End;

Procedure DoGitStatus(Sender: TObject);
Begin
  WorkflowLogger.Info('GitManager', 'Git Status requested');
  { TODO: open status window or refresh graph }
End;

Procedure DoGitCommit(Sender: TObject);
Begin
  WorkflowLogger.Info('GitManager', 'Git Commit requested');
  { TODO: show commit dialog }
End;

Procedure DoGitPush(Sender: TObject);
Begin
  WorkflowLogger.Info('GitManager', 'Git Push requested');
  { TODO: push via GitClient }
End;

Procedure DoGitPull(Sender: TObject);
Begin
  WorkflowLogger.Info('GitManager', 'Git Pull requested');
  { TODO: pull via GitClient }
End;

Procedure DoGitFetch(Sender: TObject);
Begin
  WorkflowLogger.Info('GitManager', 'Git Fetch requested');
  { TODO: fetch via GitClient }
End;

Procedure CreateGitGraphForm(Sender: TObject; AFormName: String;
  Var AForm: TCustomForm; DoDisableAutoSizing: Boolean);
Begin
  IDEWindowCreators.CreateForm(AForm, TGitGraphForm, DoDisableAutoSizing, LazarusIDE.OwningComponent);
  AForm.Name := AFormName;
End;

Procedure RegisterGitManager;
Var
  Parent: TIDEMenuSection;
  Key: TIDEShortCut;
  Cat: TIDECommandCategory;
Begin
  WorkflowLogger.Info('GitManager', 'Registering LazGitManager');

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

  WorkflowLogger.Info('GitManager', 'LazGitManager registered successfully');
End;

End.
