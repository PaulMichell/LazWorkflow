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
    FUnstagedList: TListBox;
    FStagedList: TListBox;
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
    Procedure FormCreate(Sender: TObject);
    Procedure BtnStageClick(Sender: TObject);
    Procedure BtnUnstageClick(Sender: TObject);
    Procedure BtnStageAllClick(Sender: TObject);
    Procedure BtnUnstageAllClick(Sender: TObject);
    Procedure BtnRefreshClick(Sender: TObject);
    Procedure ListSelectionChange(Sender: TObject; User: Boolean);
    Procedure ListDblClick(Sender: TObject);
    Procedure MessageChange(Sender: TObject);
    Procedure DiffStatusChanged(Sender: TObject);
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
  Private
    FRepoPath: String;
    FUnstagedPaths: TStringList;
    FStagedPaths: TStringList;
    Procedure ReloadStatus;
    Procedure FillLists;
    Procedure UpdateCommitEnabled;
    Function CollectSelectedPaths(List: TListBox; Paths: TStringList): TStringList;
    Procedure ShowDiffForList(List: TListBox; Paths: TStringList; Staged: Boolean);
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure SetRepository(Const ARepoPath: String);
    Function PushAfterCommit: Boolean;
  End;

Function ShowGitCommitForm(Const RepoPath: String; Out DidPush: Boolean): Boolean;

Implementation

{$R *.lfm}

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
  Inherited Create(TheOwner);
  FUnstagedPaths := TStringList.Create;
  FStagedPaths := TStringList.Create;
End;

Destructor TGitCommitForm.Destroy;
Begin
  FreeAndNil(FUnstagedPaths);
  FreeAndNil(FStagedPaths);
  Inherited Destroy;
End;

Procedure TGitCommitForm.FormCreate(Sender: TObject);
Begin
  FButtonPanel.OKButton.Caption := 'Commit';
  FButtonPanel.CancelButton.Caption := 'Cancel';
  FButtonPanel.OKButton.Enabled := False;
  If Assigned(FDiffView) Then
    FDiffView.OnStatusChanged := @DiffStatusChanged;
End;

Function TGitCommitForm.PushAfterCommit: Boolean;
Begin
  Result := FPushCheck.Checked;
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
  FDiffView.SetStagingContext(FRepoPath, Staged);
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

Procedure TGitCommitForm.DiffStatusChanged(Sender: TObject);
Begin
  { Partial stage/unstage changed the index – refresh file lists and current diff. }
  ReloadStatus;
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
  Summary: TGitTransferSummary;
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
      If GitClient.Push(Summary) Then
        Begin
          WorkflowLogger.Info('GitCommit', 'Pushed after commit');
          MessageDlg(Summary.Message, mtInformation, [mbOK], 0);
        End
      Else
        MessageDlg('Commit succeeded, but push failed:' + LineEnding + Summary.Message,
          mtWarning, [mbOK], 0);
    End;
End;

End.
