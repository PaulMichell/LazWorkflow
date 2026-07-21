Unit GitRemotesForm;

{ Manage Git remotes via an editable grid (c) 2026 Michell Computing. }

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
    FOriginalNames: TStringList;
    FOriginalUrls: TStringList;
    FBtnAdd: TButton;
    FBtnRemove: TButton;
    FButtonPanel: TButtonPanel;
    Procedure CreateUI;
    Procedure LoadFromGit;
    Procedure BtnAddClick(Sender: TObject);
    Procedure BtnRemoveClick(Sender: TObject);
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
    Function ValidateGrid(Out ErrorMessage: String): Boolean;
    Function SaveToGit(Out ErrorMessage: String): Boolean;
    Function DataRowCount: Integer;
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
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
  FOriginalNames := TStringList.Create;
  FOriginalUrls := TStringList.Create;
  CreateUI;
End;

Destructor TGitRemotesForm.Destroy;
Begin
  FreeAndNil(FOriginalNames);
  FreeAndNil(FOriginalUrls);
  Inherited Destroy;
End;

Procedure TGitRemotesForm.CreateUI;
Begin
  Caption := 'Remotes';
  Position := poScreenCenter;
  Width := 640;
  Height := 360;
  BorderStyle := bsSizeable;
  OnCloseQuery := @FormCloseQuery;

  FButtonPanel := TButtonPanel.Create(Self);
  With FButtonPanel Do
    Begin
      Parent := Self;
      Align := alBottom;
      ShowButtons := [pbOK, pbCancel];
      OKButton.Caption := 'OK';
      CancelButton.Caption := 'Cancel';
    End;

  { Left-aligned on the bottom button bar (same row as OK/Cancel). }
  FBtnAdd := TButton.Create(Self);
  With FBtnAdd Do
    Begin
      Parent := FButtonPanel;
      Align := alLeft;
      Width := 90;
      AutoSize := False;
      BorderSpacing.Around := 6;
      BorderSpacing.Left := 8;
      Caption := 'Add';
      OnClick := @BtnAddClick;
    End;

  FBtnRemove := TButton.Create(Self);
  With FBtnRemove Do
    Begin
      Parent := FButtonPanel;
      Align := alLeft;
      Width := 90;
      AutoSize := False;
      BorderSpacing.Around := 6;
      Caption := 'Remove';
      OnClick := @BtnRemoveClick;
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
      Options := Options + [goEditing, goThumbTracking, goColSizing, goAlwaysShowEditor, goTabs];
      Options := Options - [goRowSelect];
      Cells[0, 0] := 'Name';
      Cells[1, 0] := 'URL';
      ColWidths[0] := 120;
      ColWidths[1] := 460;
    End;
End;

Function TGitRemotesForm.DataRowCount: Integer;
Begin
  Result := FGrid.RowCount - FGrid.FixedRows;
  If Result < 0 Then
    Result := 0;
End;

Procedure TGitRemotesForm.SetRepository(Const ARepoPath: String);
Begin
  FRepoPath := ARepoPath;
  Caption := 'Remotes – ' + ARepoPath;
  If Assigned(GitClient) Then
    GitClient.RepoPath := ARepoPath;
  LoadFromGit;
End;

Procedure TGitRemotesForm.LoadFromGit;
Var
  Names, Urls: TStringList;
  I: Integer;
Begin
  FGrid.RowCount := 1;
  FOriginalNames.Clear;
  FOriginalUrls.Clear;
  If (FRepoPath = '') Or Not Assigned(GitClient) Then
    Exit;
  GitClient.RepoPath := FRepoPath;
  Names := Nil;
  Urls := Nil;
  Try
    If Not GitClient.ListRemotes(Names, Urls) Then
      Begin
        MessageDlg('Could not list remotes: ' + GitClient.LastError, mtWarning, [mbOK], 0);
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
        FOriginalNames.Add(Names[I]);
        If I < Urls.Count Then
          FOriginalUrls.Add(Urls[I])
        Else
          FOriginalUrls.Add('');
      End;
    If Names.Count > 0 Then
      FGrid.Row := 1;
  Finally
    Names.Free;
    Urls.Free;
  End;
End;

Procedure TGitRemotesForm.BtnAddClick(Sender: TObject);
Var
  NewRow: Integer;
Begin
  NewRow := FGrid.RowCount;
  FGrid.RowCount := NewRow + 1;
  FGrid.Cells[0, NewRow] := '';
  FGrid.Cells[1, NewRow] := '';
  FGrid.Row := NewRow;
  FGrid.Col := 0;
  FGrid.EditorMode := True;
End;

Procedure TGitRemotesForm.BtnRemoveClick(Sender: TObject);
Var
  Row: Integer;
  RemoteName: String;
Begin
  Row := FGrid.Row;
  If Row < FGrid.FixedRows Then
    Begin
      MessageDlg('Select a remote row to remove.', mtWarning, [mbOK], 0);
      Exit;
    End;
  RemoteName := Trim(FGrid.Cells[0, Row]);
  If RemoteName = '' Then
    RemoteName := 'this empty row';
  If MessageDlg('Remove remote "' + RemoteName + '" from the list?', mtWarning, [mbYes, mbNo], 0) <> mrYes Then
    Exit;
  FGrid.DeleteColRow(False, Row);
  If FGrid.RowCount <= FGrid.FixedRows Then
    FGrid.RowCount := FGrid.FixedRows + 0;
End;

Function TGitRemotesForm.ValidateGrid(Out ErrorMessage: String): Boolean;
Var
  I, J: Integer;
  RemoteName, Url: String;
Begin
  Result := False;
  ErrorMessage := '';
  For I := FGrid.FixedRows To FGrid.RowCount - 1 Do
    Begin
      RemoteName := Trim(FGrid.Cells[0, I]);
      Url := Trim(FGrid.Cells[1, I]);
      If (RemoteName = '') And (Url = '') Then
        Continue; { ignore fully blank rows }
      If RemoteName = '' Then
        Begin
          ErrorMessage := Format('Row %d: remote name is required.', [I]);
          Exit;
        End;
      If Url = '' Then
        Begin
          ErrorMessage := Format('Row %d (%s): URL is required.', [I, RemoteName]);
          Exit;
        End;
      For J := FGrid.FixedRows To I - 1 Do
        If SameText(Trim(FGrid.Cells[0, J]), RemoteName) Then
          Begin
            ErrorMessage := Format('Duplicate remote name "%s".', [RemoteName]);
            Exit;
          End;
    End;
  Result := True;
End;

Function TGitRemotesForm.SaveToGit(Out ErrorMessage: String): Boolean;
Var
  I, Idx: Integer;
  RemoteName, Url: String;
  DesiredNames, DesiredUrls: TStringList;
  Keep: Boolean;
Begin
  Result := False;
  ErrorMessage := '';
  If Not Assigned(GitClient) Then
    Begin
      ErrorMessage := 'Git client is not available.';
      Exit;
    End;
  GitClient.RepoPath := FRepoPath;

  DesiredNames := TStringList.Create;
  DesiredUrls := TStringList.Create;
  Try
    For I := FGrid.FixedRows To FGrid.RowCount - 1 Do
      Begin
        RemoteName := Trim(FGrid.Cells[0, I]);
        Url := Trim(FGrid.Cells[1, I]);
        If (RemoteName = '') And (Url = '') Then
          Continue;
        DesiredNames.Add(RemoteName);
        DesiredUrls.Add(Url);
      End;

    { Remove remotes that no longer appear in the grid. }
    For I := 0 To FOriginalNames.Count - 1 Do
      Begin
        Keep := DesiredNames.IndexOf(FOriginalNames[I]) >= 0;
        If Not Keep Then
          If Not GitClient.RemoveRemote(FOriginalNames[I]) Then
            Begin
              ErrorMessage := 'Failed to remove remote "' + FOriginalNames[I] + '": ' + GitClient.LastError;
              Exit;
            End;
      End;

    { Add new remotes or update URLs. }
    For I := 0 To DesiredNames.Count - 1 Do
      Begin
        RemoteName := DesiredNames[I];
        Url := DesiredUrls[I];
        Idx := FOriginalNames.IndexOf(RemoteName);
        If Idx < 0 Then
          Begin
            If Not GitClient.AddRemote(RemoteName, Url) Then
              Begin
                ErrorMessage := 'Failed to add remote "' + RemoteName + '": ' + GitClient.LastError;
                Exit;
              End;
          End
        Else If FOriginalUrls[Idx] <> Url Then
          Begin
            If Not GitClient.SetRemoteUrl(RemoteName, Url) Then
              Begin
                ErrorMessage := 'Failed to update remote "' + RemoteName + '": ' + GitClient.LastError;
                Exit;
              End;
          End;
      End;

    WorkflowLogger.Info('GitRemotes', 'Saved remotes for ' + FRepoPath);
    Result := True;
  Finally
    DesiredNames.Free;
    DesiredUrls.Free;
  End;
End;

Procedure TGitRemotesForm.FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
Var
  ErrorMessage: String;
Begin
  CanClose := True;
  If ModalResult <> mrOk Then
    Exit; { Cancel – abandon grid edits }

  FGrid.EditorMode := False;
  If Not ValidateGrid(ErrorMessage) Then
    Begin
      MessageDlg(ErrorMessage, mtWarning, [mbOK], 0);
      CanClose := False;
      Exit;
    End;
  If Not SaveToGit(ErrorMessage) Then
    Begin
      MessageDlg(ErrorMessage, mtWarning, [mbOK], 0);
      CanClose := False;
    End;
End;

End.
