Unit GitManagerMain;

{ Core registration, menus, commands and window creation for LazGitManager (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, LCLType, MenuIntf, IDECommands, IDEWindowIntf,
  SrcEditorIntf, ProjectIntf, LazIDEIntf;

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
  WorkflowLog.Info('GitManager', 'Git Status requested');
  { TODO: open status window or refresh graph }
End;

Procedure DoGitCommit(Sender: TObject);
Begin
  WorkflowLog.Info('GitManager', 'Git Commit requested');
  { TODO: show commit dialog }
End;

Procedure DoGitPush(Sender: TObject);
Begin
  WorkflowLog.Info('GitManager', 'Git Push requested');
  { TODO: push via GitService }
End;

Procedure DoGitPull(Sender: TObject);
Begin
  WorkflowLog.Info('GitManager', 'Git Pull requested');
  { TODO: pull via GitService }
End;

Procedure DoGitFetch(Sender: TObject);
Begin
  WorkflowLog.Info('GitManager', 'Git Fetch requested');
  { TODO: fetch via GitService }
End;

Procedure CreateGitGraphForm(Sender: TObject; AFormName: String;
  Var AForm: TCustomForm; DoDisableAutoSizing: Boolean);
Begin
  If DoDisableAutoSizing Then
    Begin
      AForm := TGitGraphForm.Create(Nil);
      AForm.DisableAutoSizing;
    End
  Else
    AForm := TGitGraphForm.Create(Nil);
End;

Procedure RegisterGitManager;
Var
  Parent, Item: TIDEMenuSection;
  Key: TIDEShortCut;
  Cat: TIDECommandCategory;
Begin
  WorkflowLog.Info('GitManager', 'Registering LazGitManager');

  { Command category }
  Cat := IDECommandList.CreateCategory(Nil, 'Git', 'Git', IDEListEditorCategory);

  { Commands }
  Key := IDEShortCut(VK_UNKNOWN, []);
  CmdGitGraph := RegisterIDECommand(Cat, 'GitGraph', 'Show Git Graph', Key, Nil, @ShowGitGraphWindow);
  CmdGitStatus := RegisterIDECommand(Cat, 'GitStatus', 'Git Status', Key, Nil, @DoGitStatus);
  CmdGitCommit := RegisterIDECommand(Cat, 'GitCommit', 'Git Commit', Key, Nil, @DoGitCommit);
  CmdGitPush := RegisterIDECommand(Cat, 'GitPush', 'Git Push', Key, Nil, @DoGitPush);
  CmdGitPull := RegisterIDECommand(Cat, 'GitPull', 'Git Pull', Key, Nil, @DoGitPull);
  CmdGitFetch := RegisterIDECommand(Cat, 'GitFetch', 'Git Fetch', Key, Nil, @DoGitFetch);

  { Main menu – attach under Tools for maximum compatibility }
  Parent := RegisterIDEMenuSection(itmTools, 'GitSection');
  Parent.Caption := 'Git';
  Item := RegisterIDEMenuCommand(Parent, 'GitGraph', 'Git Graph', Nil, Nil, CmdGitGraph);
  Item := RegisterIDEMenuCommand(Parent, 'GitStatus', 'Status', Nil, Nil, CmdGitStatus);
  Item := RegisterIDEMenuCommand(Parent, 'GitCommit', 'Commit...', Nil, Nil, CmdGitCommit);
  RegisterIDEMenuSection(Parent, 'GitSep1');
  Item := RegisterIDEMenuCommand(Parent, 'GitFetch', 'Fetch', Nil, Nil, CmdGitFetch);
  Item := RegisterIDEMenuCommand(Parent, 'GitPull', 'Pull', Nil, Nil, CmdGitPull);
  Item := RegisterIDEMenuCommand(Parent, 'GitPush', 'Push', Nil, Nil, CmdGitPush);

  { Dockable window }
  GitGraphWindowCreator := IDEWindowCreators.Add('GitGraph', @CreateGitGraphForm, Nil,
    '100', '100', '900', '600');
  GitGraphWindowCreator.CreateLayout := True;

  WorkflowLog.Info('GitManager', 'LazGitManager registered successfully');
End;

Initialization

Finalization

End.
