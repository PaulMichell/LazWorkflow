Unit GitGraphForm;

{ High-quality commit history graph window (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Menus, ActnList, LCLIntf, LCLType, WorkflowEvents, StatusFooterFrame;

Type
  TGitGraphForm = Class(TForm, IWorkflowListener, IGitRepositoryChanged)
  Private
    FToolBar: TToolBar;
    FGraphPanel: TScrollBox;
    FPaintBox: TPaintBox;
    FStatusFooter: TStatusFooterFrame;
    FSplitter: TSplitter;
    FDetailPanel: TPanel;
    FDetailMemo: TMemo;
    FActionList: TActionList;
    FRefreshAction: TAction;
    FRepoPath: String;
    Procedure CreateUI;
    Procedure FormCreate(Sender: TObject);
    Procedure FormDestroy(Sender: TObject);
    Procedure PaintBoxPaint(Sender: TObject);
    Procedure RefreshActionExecute(Sender: TObject);
    Procedure UpdateStatus;
    { IGitRepositoryChanged }
    Procedure RepositoryStateChanged(Const RepoPath: String; NewState: TGitRepositoryState);
    Procedure WorkingTreeChanged(Const RepoPath: String);
    Procedure HeadChanged(Const RepoPath: String; Const NewHeadSha: String);
    Procedure RemoteUpdated(Const RepoPath: String; Const RemoteName: String);
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure SetRepository(Const ARepoPath: String);
  End;

Implementation

{$R *.lfm}

Uses
  WorkflowLog, GitService;

Constructor TGitGraphForm.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  CreateUI;
  WorkflowEventBus.AddListener(Self);
End;

Destructor TGitGraphForm.Destroy;
Begin
  WorkflowEventBus.RemoveListener(Self);
  Inherited Destroy;
End;

Procedure TGitGraphForm.CreateUI;
Begin
  Caption := 'Git Graph';
  Width := 900;
  Height := 600;
  Position := poDefaultPosOnly;

  FActionList := TActionList.Create(Self);

  FRefreshAction := TAction.Create(Self);
  FRefreshAction.Caption := 'Refresh';
  FRefreshAction.OnExecute := @RefreshActionExecute;
  FRefreshAction.ActionList := FActionList;

  FToolBar := TToolBar.Create(Self);
  With FToolBar Do
    Begin
      Parent := Self;
      Align := alTop;
      Height := 28;
      EdgeBorders := [];
      ShowCaptions := True;
    End;

  With TToolButton.Create(FToolBar) Do
    Begin
      Parent := FToolBar;
      Action := FRefreshAction;
      Style := tbsButton;
    End;

  FStatusFooter := TStatusFooterFrame.Create(Self);
  FStatusFooter.Parent := Self;
  FStatusFooter.Align := alBottom;

  FDetailPanel := TPanel.Create(Self);
  With FDetailPanel Do
    Begin
      Parent := Self;
      Align := alBottom;
      Height := 140;
      BevelOuter := bvNone;
      Caption := '';
    End;

  FDetailMemo := TMemo.Create(Self);
  With FDetailMemo Do
    Begin
      Parent := FDetailPanel;
      Align := alClient;
      ReadOnly := True;
      ScrollBars := ssAutoBoth;
      BorderSpacing.Around := 4;
      Font.Name := 'Monospace';
    End;

  FSplitter := TSplitter.Create(Self);
  With FSplitter Do
    Begin
      Parent := Self;
      Align := alBottom;
      Height := 5;
    End;

  FGraphPanel := TScrollBox.Create(Self);
  With FGraphPanel Do
    Begin
      Parent := Self;
      Align := alClient;
      BorderStyle := bsNone;
      HorzScrollBar.Tracking := True;
      VertScrollBar.Tracking := True;
    End;

  FPaintBox := TPaintBox.Create(Self);
  With FPaintBox Do
    Begin
      Parent := FGraphPanel;
      Align := alClient;
      OnPaint := @PaintBoxPaint;
    End;

  OnCreate := @FormCreate;
  OnDestroy := @FormDestroy;
End;

Procedure TGitGraphForm.FormCreate(Sender: TObject);
Begin
  UpdateStatus;
  WorkflowLogger.Info('GitGraph', 'Git Graph window created');
End;

Procedure TGitGraphForm.FormDestroy(Sender: TObject);
Begin
  WorkflowLogger.Info('GitGraph', 'Git Graph window destroyed');
End;

Procedure TGitGraphForm.PaintBoxPaint(Sender: TObject);
Var
  R: TRect;
Begin
  { Placeholder graph rendering – Phase 1 will implement full lane-based drawing. }
  With FPaintBox.Canvas Do
    Begin
      Brush.Color := clWindow;
      FillRect(FPaintBox.ClientRect);
      Font.Color := clGrayText;
      Font.Size := 12;
      R := FPaintBox.ClientRect;
      DrawText(Handle, PChar('Git Graph – commit history tree will be rendered here'),
        -1, R, DT_CENTER Or DT_VCENTER Or DT_SINGLELINE);
    End;
End;

Procedure TGitGraphForm.RefreshActionExecute(Sender: TObject);
Begin
  WorkflowLogger.Info('GitGraph', 'Manual refresh requested');
  If FRepoPath <> '' Then
    Begin
      { TODO: call GitClient.Refresh }
      FPaintBox.Invalidate;
    End;
  UpdateStatus;
End;

Procedure TGitGraphForm.UpdateStatus;
Begin
  If FRepoPath = '' Then
    FStatusFooter.SetAll('No repository', '', 'Ready')
  Else
    FStatusFooter.SetAll(ExtractFileName(FRepoPath), FRepoPath, 'Ready');
End;

Procedure TGitGraphForm.SetRepository(Const ARepoPath: String);
Begin
  FRepoPath := ARepoPath;
  UpdateStatus;
  FPaintBox.Invalidate;
End;

Procedure TGitGraphForm.RepositoryStateChanged(Const RepoPath: String; NewState: TGitRepositoryState);
Begin
  If SameText(RepoPath, FRepoPath) Then
    Begin
      UpdateStatus;
      FPaintBox.Invalidate;
    End;
End;

Procedure TGitGraphForm.WorkingTreeChanged(Const RepoPath: String);
Begin
  If SameText(RepoPath, FRepoPath) Then
    FPaintBox.Invalidate;
End;

Procedure TGitGraphForm.HeadChanged(Const RepoPath: String; Const NewHeadSha: String);
Begin
  If SameText(RepoPath, FRepoPath) Then
    Begin
      FDetailMemo.Lines.Text := 'HEAD now at ' + NewHeadSha;
      FPaintBox.Invalidate;
    End;
End;

Procedure TGitGraphForm.RemoteUpdated(Const RepoPath: String; Const RemoteName: String);
Begin
  If SameText(RepoPath, FRepoPath) Then
    FStatusFooter.SetRightText('Remote ' + RemoteName + ' updated');
End;

End.
