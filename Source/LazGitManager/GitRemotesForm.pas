Unit GitRemotesForm;

{ Manage Git remotes (name + URL) for the current repository (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ButtonPanel, Grids;

Type
  TGitRemotesForm = Class(TForm)
  Private
    FRepoPath: String;
    FGrid: TStringGrid;
    FNameEdit: TEdit;
    FUrlEdit: TEdit;
    FNameLabel: TLabel;
    FUrlLabel: TLabel;
    FBtnAdd: TButton;
    FBtnUpdate: TButton;
    FBtnRemove: TButton;
    FBtnRefresh: TButton;
    FButtonPanel: TButtonPanel;
    FBottomPanel: TPanel;
    Procedure CreateUI;
    Procedure ReloadRemotes;
    Procedure GridSelectCell(Sender: TObject; ACol, ARow: Integer; Var CanSelect: Boolean);
    Procedure BtnAddClick(Sender: TObject);
    Procedure BtnUpdateClick(Sender: TObject);
    Procedure BtnRemoveClick(Sender: TObject);
    Procedure BtnRefreshClick(Sender: TObject);
    Function SelectedRemoteName: String;
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Procedure SetRepository(Const ARepoPath: String);
  End;

Procedure ShowGitRemotesForm(Const RepoPath: String);

Implementation

Uses
  GitService, WorkflowLog;

Procedure ShowGitRemotesForm(Const RepoPath: String);
Var
  Form: TGitRemotesForm;
Begin
  Form := TGitRemotesForm.Create(Application.MainForm);
  Try
    Form.SetRepository(RepoPath);
    Form.ShowModal;
  Finally
    Form.Free;
  End;
End;

Constructor TGitRemotesForm.Create(TheOwner: TComponent);
Begin
  Inherited CreateNew(TheOwner);
  CreateUI;
End;

Procedure TGitRemotesForm.CreateUI;
Begin
  Caption := 'Remotes';
  Position := poScreenCenter;
  Width := 640;
  Height := 360;
  BorderStyle := bsSizeable;

  FButtonPanel := TButtonPanel.Create(Self);
  With FButtonPanel Do
    Begin
      Parent := Self;
      Align := alBottom;
      ShowButtons := [pbClose];
      CloseButton.Caption := 'Close';
    End;

  FBottomPanel := TPanel.Create(Self);
  With FBottomPanel Do
    Begin
      Parent := Self;
      Align := alBottom;
      Height := 110;
      BevelOuter := bvNone;
      Caption := '';
    End;

  FNameLabel := TLabel.Create(Self);
  With FNameLabel Do
    Begin
      Parent := FBottomPanel;
      Left := 12;
      Top := 12;
      Caption := 'Name:';
    End;

  FNameEdit := TEdit.Create(Self);
  With FNameEdit Do
    Begin
      Parent := FBottomPanel;
      Left := 70;
      Top := 8;
      Width := 140;
      Text := 'origin';
    End;

  FUrlLabel := TLabel.Create(Self);
  With FUrlLabel Do
    Begin
      Parent := FBottomPanel;
      Left := 12;
      Top := 48;
      Caption := 'URL:';
    End;

  FUrlEdit := TEdit.Create(Self);
  With FUrlEdit Do
    Begin
      Parent := FBottomPanel;
      Left := 70;
      Top := 44;
      Width := 420;
      Text := '';
    End;

  FBtnAdd := TButton.Create(Self);
  With FBtnAdd Do
    Begin
      Parent := FBottomPanel;
      Left := 500;
      Top := 8;
      Width := 110;
      Caption := 'Add';
      OnClick := @BtnAddClick;
    End;

  FBtnUpdate := TButton.Create(Self);
  With FBtnUpdate Do
    Begin
      Parent := FBottomPanel;
      Left := 500;
      Top := 40;
      Width := 110;
      Caption := 'Update URL';
      OnClick := @BtnUpdateClick;
    End;

  FBtnRemove := TButton.Create(Self);
  With FBtnRemove Do
    Begin
      Parent := FBottomPanel;
      Left := 500;
      Top := 72;
      Width := 110;
      Caption := 'Remove';
      OnClick := @BtnRemoveClick;
    End;

  FBtnRefresh := TButton.Create(Self);
  With FBtnRefresh Do
    Begin
      Parent := FBottomPanel;
      Left := 70;
      Top := 76;
      Width := 100;
      Caption := 'Refresh';
      OnClick := @BtnRefreshClick;
    End;

  FGrid := TStringGrid.Create(Self);
  With FGrid Do
    Begin
      Parent := Self;
      Align := alClient;
      BorderSpacing.Around := 8;
      ColCount := 2;
      RowCount := 1;
      FixedRows := 1;
      FixedCols := 0;
      Options := Options + [goRowSelect, goThumbTracking, goColSizing];
      Cells[0, 0] := 'Name';
      Cells[1, 0] := 'URL';
      ColWidths[0] := 100;
      ColWidths[1] := 480;
      OnSelectCell := @GridSelectCell;
    End;
End;

Procedure TGitRemotesForm.SetRepository(Const ARepoPath: String);
Begin
  FRepoPath := ARepoPath;
  Caption := 'Remotes – ' + ARepoPath;
  If Assigned(GitClient) Then
    GitClient.RepoPath := ARepoPath;
  ReloadRemotes;
End;

Procedure TGitRemotesForm.ReloadRemotes;
Var
  Names, Urls: TStringList;
  I: Integer;
Begin
  FGrid.RowCount := 1;
  If (FRepoPath = '') Or Not Assigned(GitClient) Then
    Exit;
  GitClient.RepoPath := FRepoPath;
  Names := Nil;
  Urls := Nil;
  Try
    If Not GitClient.ListRemotes(Names, Urls) Then
      Begin
        MessageDlg('Could not list remotes: ' + GitClient.LastError, mtError, [mbOK], 0);
        Exit;
      End;
    FGrid.RowCount := Names.Count + 1;
    For I := 0 To Names.Count - 1 Do
      Begin
        FGrid.Cells[0, I + 1] := Names[I];
        If I < Urls.Count Then
          FGrid.Cells[1, I + 1] := Urls[I]
        Else
          FGrid.Cells[1, I + 1] := '';
      End;
    If Names.Count > 0 Then
      Begin
        FGrid.Row := 1;
        FNameEdit.Text := FGrid.Cells[0, 1];
        FUrlEdit.Text := FGrid.Cells[1, 1];
      End;
  Finally
    Names.Free;
    Urls.Free;
  End;
End;

Function TGitRemotesForm.SelectedRemoteName: String;
Begin
  Result := '';
  If FGrid.Row >= 1 Then
    Result := Trim(FGrid.Cells[0, FGrid.Row]);
End;

Procedure TGitRemotesForm.GridSelectCell(Sender: TObject; ACol, ARow: Integer; Var CanSelect: Boolean);
Begin
  CanSelect := True;
  If ARow >= 1 Then
    Begin
      FNameEdit.Text := FGrid.Cells[0, ARow];
      FUrlEdit.Text := FGrid.Cells[1, ARow];
    End;
End;

Procedure TGitRemotesForm.BtnAddClick(Sender: TObject);
Begin
  GitClient.RepoPath := FRepoPath;
  If Not GitClient.AddRemote(FNameEdit.Text, FUrlEdit.Text) Then
    MessageDlg('Add remote failed: ' + GitClient.LastError, mtError, [mbOK], 0)
  Else
    Begin
      WorkflowLogger.Info('GitRemotes', 'Added remote ' + Trim(FNameEdit.Text));
      ReloadRemotes;
    End;
End;

Procedure TGitRemotesForm.BtnUpdateClick(Sender: TObject);
Var
  RemoteName: String;
Begin
  RemoteName := SelectedRemoteName;
  If RemoteName = '' Then
    RemoteName := Trim(FNameEdit.Text);
  GitClient.RepoPath := FRepoPath;
  If Not GitClient.SetRemoteUrl(RemoteName, FUrlEdit.Text) Then
    MessageDlg('Update remote failed: ' + GitClient.LastError, mtError, [mbOK], 0)
  Else
    Begin
      WorkflowLogger.Info('GitRemotes', 'Updated remote ' + RemoteName);
      ReloadRemotes;
    End;
End;

Procedure TGitRemotesForm.BtnRemoveClick(Sender: TObject);
Var
  RemoteName: String;
Begin
  RemoteName := SelectedRemoteName;
  If RemoteName = '' Then
    Exit;
  If MessageDlg('Remove remote "' + RemoteName + '"?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes Then
    Exit;
  GitClient.RepoPath := FRepoPath;
  If Not GitClient.RemoveRemote(RemoteName) Then
    MessageDlg('Remove remote failed: ' + GitClient.LastError, mtError, [mbOK], 0)
  Else
    Begin
      WorkflowLogger.Info('GitRemotes', 'Removed remote ' + RemoteName);
      ReloadRemotes;
    End;
End;

Procedure TGitRemotesForm.BtnRefreshClick(Sender: TObject);
Begin
  ReloadRemotes;
End;

End.
