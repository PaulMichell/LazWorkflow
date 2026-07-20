Unit GitCommitForm;

{ Stage / unstage / commit dialog for LazGitManager (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ButtonPanel, GitDiffView;

Type
  TGitCommitForm = Class(TForm)
  Private
    FRepoPath: String;
    FUnstagedList: TListBox;
    FStagedList: TListBox;
    FUnstagedPaths: TStringList;
    FStagedPaths: TStringList;
    FMessageMemo: TMemo;
    FDiffView: TGitDiffView;
    FPushCheck: TCheckBox;
    FStatusLabel: TLabel;
    FButtonPanel: TButtonPanel;
    FUnstagedLabel: TLabel;
    FStagedLabel: TLabel;
    FMessageLabel: TLabel;
    FBtnStage: TButton;
    FBtnUnstage: TButton;
    FBtnStageAll: TButton;
    FBtnUnstageAll: TButton;
    FBtnRefresh: TButton;
    FMidPanel: TPanel;
    FTopPanel: TPanel;
    FListsPanel: TPanel;
    FUnstagedPanel: TPanel;
    FStagedPanel: TPanel;
    FMessagePanel: TPanel;
    FButtonColumn: TPanel;
    Procedure CreateUI;
    Procedure ReloadStatus;
    Procedure FillLists;
    Procedure UpdateCommitEnabled;
    Function CollectSelectedPaths(List: TListBox; Paths: TStringList): TStringList;
    Procedure ShowDiffForList(List: TListBox; Paths: TStringList; Staged: Boolean);
    Procedure BtnStageClick(Sender: TObject);
    Procedure BtnUnstageClick(Sender: TObject);
    Procedure BtnStageAllClick(Sender: TObject);
    Procedure BtnUnstageAllClick(Sender: TObject);
    Procedure BtnRefreshClick(Sender: TObject);
    Procedure ListSelectionChange(Sender: TObject; User: Boolean);
    Procedure ListDblClick(Sender: TObject);
    Procedure MessageChange(Sender: TObject);
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure SetRepository(Const ARepoPath: String);
    Function PushAfterCommit: Boolean;
  End;

Function ShowGitCommitForm(Const RepoPath: String; Out DidPush: Boolean): Boolean;

Implementation

Uses
  GitService, WorkflowLog;

Function ShowGitCommitForm(Const RepoPath: String; Out DidPush: Boolean): Boolean;
Var
  Form: TGitCommitForm;
Begin
  Result := False;
  DidPush := False;
  Form := TGitCommitForm.Create(Application.MainForm);
  Try
    Form.SetRepository(RepoPath);
    If Form.ShowModal = mrOk Then
      Begin
        Result := True;
        DidPush := Form.PushAfterCommit;
      End;
  Finally
    Form.Free;
  End;
End;

Constructor TGitCommitForm.Create(TheOwner: TComponent);
Begin
  Inherited CreateNew(TheOwner);
  FUnstagedPaths := TStringList.Create;
  FStagedPaths := TStringList.Create;
  CreateUI;
End;

Destructor TGitCommitForm.Destroy;
Begin
  FreeAndNil(FUnstagedPaths);
  FreeAndNil(FStagedPaths);
  Inherited Destroy;
End;

Function TGitCommitForm.PushAfterCommit: Boolean;
Begin
  Result := FPushCheck.Checked;
End;

Procedure TGitCommitForm.CreateUI;
Begin
  Caption := 'Commit';
  Position := poScreenCenter;
  Width := 820;
  Height := 580;
  BorderStyle := bsSizeable;
  Constraints.MinWidth := 600;
  Constraints.MinHeight := 440;
  OnCloseQuery := @FormCloseQuery;

  FButtonPanel := TButtonPanel.Create(Self);
  With FButtonPanel Do
    Begin
      Parent := Self;
      Align := alBottom;
      ShowButtons := [pbOK, pbCancel];
      OKButton.Caption := 'Commit';
      CancelButton.Caption := 'Cancel';
      OKButton.Enabled := False;
    End;

  FPushCheck := TCheckBox.Create(Self);
  With FPushCheck Do
    Begin
      Parent := Self;
      Align := alBottom;
      BorderSpacing.Around := 8;
      Caption := 'Push to remote after successful commit';
    End;

  FStatusLabel := TLabel.Create(Self);
  With FStatusLabel Do
    Begin
      Parent := Self;
      Align := alBottom;
      BorderSpacing.Left := 8;
      BorderSpacing.Right := 8;
      BorderSpacing.Bottom := 4;
      Caption := '';
    End;

  FTopPanel := TPanel.Create(Self);
  With FTopPanel Do
    Begin
      Parent := Self;
      Align := alClient;
      BevelOuter := bvNone;
      Caption := '';
    End;

  FMessagePanel := TPanel.Create(Self);
  With FMessagePanel Do
    Begin
      Parent := FTopPanel;
      Align := alBottom;
      Height := 120;
      BevelOuter := bvNone;
      Caption := '';
    End;

  FMessageLabel := TLabel.Create(Self);
  With FMessageLabel Do
    Begin
      Parent := FMessagePanel;
      Align := alTop;
      Caption := 'Commit message';
      BorderSpacing.Left := 8;
      BorderSpacing.Top := 4;
    End;

  FMessageMemo := TMemo.Create(Self);
  With FMessageMemo Do
    Begin
      Parent := FMessagePanel;
      Align := alClient;
      BorderSpacing.Around := 8;
      ScrollBars := ssAutoBoth;
      WantTabs := False;
      OnChange := @MessageChange;
    End;

  FListsPanel := TPanel.Create(Self);
  With FListsPanel Do
    Begin
      Parent := FTopPanel;
      Align := alClient;
      BevelOuter := bvNone;
      Caption := '';
    End;

  FDiffView := TGitDiffView.Create(Self);
  With FDiffView Do
    Begin
      Parent := FListsPanel;
      Align := alBottom;
      Height := 220;
      BorderSpacing.Around := 4;
    End;

  FMidPanel := TPanel.Create(Self);
  With FMidPanel Do
    Begin
      Parent := FListsPanel;
      Align := alClient;
      BevelOuter := bvNone;
      Caption := '';
    End;

  FUnstagedPanel := TPanel.Create(Self);
  With FUnstagedPanel Do
    Begin
      Parent := FMidPanel;
      Align := alLeft;
      Width := 320;
      BevelOuter := bvNone;
      Caption := '';
    End;

  FUnstagedLabel := TLabel.Create(Self);
  With FUnstagedLabel Do
    Begin
      Parent := FUnstagedPanel;
      Align := alTop;
      Caption := 'Changes';
      BorderSpacing.Left := 8;
      BorderSpacing.Top := 4;
    End;

  FUnstagedList := TListBox.Create(Self);
  With FUnstagedList Do
    Begin
      Parent := FUnstagedPanel;
      Align := alClient;
      BorderSpacing.Around := 8;
      MultiSelect := True;
      OnSelectionChange := @ListSelectionChange;
      OnDblClick := @ListDblClick;
    End;

  FButtonColumn := TPanel.Create(Self);
  With FButtonColumn Do
    Begin
      Parent := FMidPanel;
      Align := alLeft;
      Width := 110;
      BevelOuter := bvNone;
      Caption := '';
    End;

  FBtnStage := TButton.Create(Self);
  With FBtnStage Do
    Begin
      Parent := FButtonColumn;
      SetBounds(10, 36, 90, 28);
      Caption := 'Stage >';
      OnClick := @BtnStageClick;
    End;

  FBtnUnstage := TButton.Create(Self);
  With FBtnUnstage Do
    Begin
      Parent := FButtonColumn;
      SetBounds(10, 72, 90, 28);
      Caption := '< Unstage';
      OnClick := @BtnUnstageClick;
    End;

  FBtnStageAll := TButton.Create(Self);
  With FBtnStageAll Do
    Begin
      Parent := FButtonColumn;
      SetBounds(10, 116, 90, 28);
      Caption := 'Stage all';
      OnClick := @BtnStageAllClick;
    End;

  FBtnUnstageAll := TButton.Create(Self);
  With FBtnUnstageAll Do
    Begin
      Parent := FButtonColumn;
      SetBounds(10, 152, 90, 28);
      Caption := 'Unstage all';
      OnClick := @BtnUnstageAllClick;
    End;

  FBtnRefresh := TButton.Create(Self);
  With FBtnRefresh Do
    Begin
      Parent := FButtonColumn;
      SetBounds(10, 196, 90, 28);
      Caption := 'Refresh';
      OnClick := @BtnRefreshClick;
    End;

  FStagedPanel := TPanel.Create(Self);
  With FStagedPanel Do
    Begin
      Parent := FMidPanel;
      Align := alClient;
      BevelOuter := bvNone;
      Caption := '';
    End;

  FStagedLabel := TLabel.Create(Self);
  With FStagedLabel Do
    Begin
      Parent := FStagedPanel;
      Align := alTop;
      Caption := 'Staged for commit';
      BorderSpacing.Left := 8;
      BorderSpacing.Top := 4;
    End;

  FStagedList := TListBox.Create(Self);
  With FStagedList Do
    Begin
      Parent := FStagedPanel;
      Align := alClient;
      BorderSpacing.Around := 8;
      MultiSelect := True;
      OnSelectionChange := @ListSelectionChange;
      OnDblClick := @ListDblClick;
    End;
End;

Procedure TGitCommitForm.SetRepository(Const ARepoPath: String);
Begin
  FRepoPath := ARepoPath;
  If Assigned(GitClient) Then
    GitClient.RepoPath := ARepoPath;
  ReloadStatus;
End;

Procedure TGitCommitForm.ReloadStatus;
Begin
  FillLists;
  UpdateCommitEnabled;
  FDiffView.Clear;
  If FRepoPath = '' Then
    FStatusLabel.Caption := 'No repository'
  Else
    FStatusLabel.Caption := FRepoPath;
End;

Procedure TGitCommitForm.FillLists;
Var
  Entries: TGitStatusEntryArray;
  I: Integer;
Begin
  FUnstagedList.Items.BeginUpdate;
  FStagedList.Items.BeginUpdate;
  Try
    FUnstagedList.Clear;
    FStagedList.Clear;
    FUnstagedPaths.Clear;
    FStagedPaths.Clear;

    If (FRepoPath = '') Or Not Assigned(GitClient) Then
      Exit;

    GitClient.RepoPath := FRepoPath;
    If Not GitClient.ListStatus(Entries) Then
      Begin
        FStatusLabel.Caption := 'Failed to read status: ' + GitClient.LastError;
        Exit;
      End;

    For I := 0 To High(Entries) Do
      Begin
        If GitStatusEntryIsUnstaged(Entries[I]) Then
          Begin
            FUnstagedList.Items.Add(GitStatusEntryLabel(Entries[I], False));
            FUnstagedPaths.Add(Entries[I].Path);
          End;
        If GitStatusEntryIsStaged(Entries[I]) Then
          Begin
            FStagedList.Items.Add(GitStatusEntryLabel(Entries[I], True));
            FStagedPaths.Add(Entries[I].Path);
          End;
      End;
  Finally
    FUnstagedList.Items.EndUpdate;
    FStagedList.Items.EndUpdate;
  End;

  FUnstagedLabel.Caption := Format('Changes (%d)', [FUnstagedList.Count]);
  FStagedLabel.Caption := Format('Staged for commit (%d)', [FStagedList.Count]);
End;

Function TGitCommitForm.CollectSelectedPaths(List: TListBox; Paths: TStringList): TStringList;
Var
  I: Integer;
Begin
  Result := TStringList.Create;
  Result.Duplicates := dupIgnore;
  Result.Sorted := False;
  If (List = Nil) Or (Paths = Nil) Then
    Exit;
  For I := 0 To List.Count - 1 Do
    If List.Selected[I] And (I < Paths.Count) Then
      Result.Add(Paths[I]);
End;

Procedure TGitCommitForm.ShowDiffForList(List: TListBox; Paths: TStringList; Staged: Boolean);
Var
  I: Integer;
  DiffText, Path, Title: String;
Begin
  FDiffView.Clear;
  If (List = Nil) Or (Paths = Nil) Or Not Assigned(GitClient) Then
    Exit;
  For I := 0 To List.Count - 1 Do
    If List.Selected[I] And (I < Paths.Count) Then
      Begin
        Path := Paths[I];
        If Staged Then
          Title := 'Staged: ' + Path
        Else
          Title := 'Working tree: ' + Path;
        GitClient.RepoPath := FRepoPath;
        If GitClient.DiffPath(Path, Staged, DiffText) Then
          Begin
            If Trim(DiffText) = '' Then
              FDiffView.LoadPlainText(Title, '(no textual diff for ' + Path + ')')
            Else
              FDiffView.LoadDiff(Title, DiffText);
          End
        Else
          FDiffView.LoadPlainText(Title, 'Diff failed: ' + GitClient.LastError);
        Exit; { show first selected only }
      End;
End;

Procedure TGitCommitForm.UpdateCommitEnabled;
Var
  CanCommit: Boolean;
Begin
  CanCommit := (FStagedList.Count > 0) And (Trim(FMessageMemo.Text) <> '');
  FButtonPanel.OKButton.Enabled := CanCommit;
End;

Procedure TGitCommitForm.BtnStageClick(Sender: TObject);
Var
  Paths: TStringList;
Begin
  Paths := CollectSelectedPaths(FUnstagedList, FUnstagedPaths);
  Try
    If Paths.Count = 0 Then
      Exit;
    GitClient.RepoPath := FRepoPath;
    If Not GitClient.StagePaths(Paths) Then
      MessageDlg('Stage failed: ' + GitClient.LastError, mtError, [mbOK], 0);
    ReloadStatus;
  Finally
    Paths.Free;
  End;
End;

Procedure TGitCommitForm.BtnUnstageClick(Sender: TObject);
Var
  Paths: TStringList;
Begin
  Paths := CollectSelectedPaths(FStagedList, FStagedPaths);
  Try
    If Paths.Count = 0 Then
      Exit;
    GitClient.RepoPath := FRepoPath;
    If Not GitClient.UnstagePaths(Paths) Then
      MessageDlg('Unstage failed: ' + GitClient.LastError, mtError, [mbOK], 0);
    ReloadStatus;
  Finally
    Paths.Free;
  End;
End;

Procedure TGitCommitForm.BtnStageAllClick(Sender: TObject);
Begin
  GitClient.RepoPath := FRepoPath;
  If Not GitClient.StageAll Then
    MessageDlg('Stage all failed: ' + GitClient.LastError, mtError, [mbOK], 0);
  ReloadStatus;
End;

Procedure TGitCommitForm.BtnUnstageAllClick(Sender: TObject);
Begin
  GitClient.RepoPath := FRepoPath;
  If Not GitClient.UnstageAll Then
    MessageDlg('Unstage all failed: ' + GitClient.LastError, mtError, [mbOK], 0);
  ReloadStatus;
End;

Procedure TGitCommitForm.BtnRefreshClick(Sender: TObject);
Begin
  ReloadStatus;
End;

Procedure TGitCommitForm.ListSelectionChange(Sender: TObject; User: Boolean);
Begin
  If Sender = FUnstagedList Then
    Begin
      FStagedList.ClearSelection;
      ShowDiffForList(FUnstagedList, FUnstagedPaths, False);
    End
  Else If Sender = FStagedList Then
    Begin
      FUnstagedList.ClearSelection;
      ShowDiffForList(FStagedList, FStagedPaths, True);
    End;
End;

Procedure TGitCommitForm.ListDblClick(Sender: TObject);
Begin
  If Sender = FUnstagedList Then
    BtnStageClick(Sender)
  Else If Sender = FStagedList Then
    BtnUnstageClick(Sender);
End;

Procedure TGitCommitForm.MessageChange(Sender: TObject);
Begin
  UpdateCommitEnabled;
End;

Procedure TGitCommitForm.FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
Var
  NewSha: String;
  Msg: String;
Begin
  CanClose := True;
  If ModalResult <> mrOk Then
    Exit;

  Msg := Trim(FMessageMemo.Text);
  If Msg = '' Then
    Begin
      MessageDlg('Enter a commit message.', mtError, [mbOK], 0);
      CanClose := False;
      Exit;
    End;
  If FStagedList.Count = 0 Then
    Begin
      MessageDlg('Stage at least one change before committing.', mtError, [mbOK], 0);
      CanClose := False;
      Exit;
    End;

  GitClient.RepoPath := FRepoPath;
  If Not GitClient.Commit(Msg, NewSha) Then
    Begin
      MessageDlg('Commit failed: ' + GitClient.LastError, mtError, [mbOK], 0);
      CanClose := False;
      ReloadStatus;
      Exit;
    End;

  WorkflowLogger.Info('GitCommit', 'Created commit ' + NewSha);
  FStatusLabel.Caption := 'Committed ' + Copy(NewSha, 1, 7);

  If FPushCheck.Checked Then
    Begin
      If GitClient.Push Then
        WorkflowLogger.Info('GitCommit', 'Pushed after commit')
      Else
        MessageDlg('Commit succeeded, but push failed: ' + GitClient.LastError,
          mtWarning, [mbOK], 0);
    End;
End;

End.
