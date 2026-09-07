Unit GitRemotesForm;

{ Manage Git remotes via a select-then-edit grid (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Grids;

Type
  TGitRemotesForm = Class(TForm)
    RemotesGrid: TStringGrid;
    BottomBar: TPanel;
    LeftButtonsPanel: TPanel;
    SeparatorBevel: TBevel;
    AddButton: TButton;
    RemoveButton: TButton;
    EditButton: TButton;
    OKButton: TButton;
    CancelButton: TButton;
    Procedure AddButtonClick(Sender: TObject);
    Procedure RemoveButtonClick(Sender: TObject);
    Procedure EditButtonClick(Sender: TObject);
    Procedure GridSelectCell(Sender: TObject; aCol, aRow: Integer; Var CanSelect: Boolean);
    Procedure GridMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
    Procedure FormCreate(Sender: TObject);
  Private
    FRepoPath: String;
    OriginalNames: TStringList;
    OriginalUrls: TStringList;
    FEditing: Boolean;
    FEditRow: Integer;
    Procedure LoadFromGit;
    Procedure SetGridEditable(Editable: Boolean);
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

{$R *.lfm}

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
  Inherited Create(TheOwner);
  OriginalNames := TStringList.Create;
  OriginalNames.CaseSensitive := True;
  OriginalUrls := TStringList.Create;
  FEditing := False;
  FEditRow := -1;
End;

Destructor TGitRemotesForm.Destroy;
Begin
  FreeAndNil(OriginalNames);
  FreeAndNil(OriginalUrls);
  Inherited Destroy;
End;

Procedure TGitRemotesForm.FormCreate(Sender: TObject);
Begin
  RemotesGrid.Cells[0, 0] := 'Name';
  RemotesGrid.Cells[1, 0] := 'URL';
  RemotesGrid.ColWidths[0] := 120;
  RemotesGrid.ColWidths[1] := 460;
  SetGridEditable(False);
End;

Procedure TGitRemotesForm.SetGridEditable(Editable: Boolean);
Begin
  If Editable = FEditing Then
    Begin
      If Editable Then
        FEditRow := RemotesGrid.Row;
      Exit;
    End;

  RemotesGrid.EditorMode := False;
  FEditing := Editable;
  If Editable Then
    Begin
      FEditRow := RemotesGrid.Row;
      RemotesGrid.Options := RemotesGrid.Options - [goRowSelect] + [goEditing, goAlwaysShowEditor];
    End
  Else
    Begin
      FEditRow := -1;
      RemotesGrid.Options := RemotesGrid.Options + [goRowSelect] - [goEditing, goAlwaysShowEditor];
    End;
End;

Function TGitRemotesForm.DataRowCount: Integer;
Begin
  Result := RemotesGrid.RowCount - RemotesGrid.FixedRows;
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
  SetGridEditable(False);
  RemotesGrid.RowCount := 1;
  OriginalNames.Clear;
  OriginalUrls.Clear;
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
    RemotesGrid.RowCount := Names.Count + 1;
    For I := 0 To Names.Count - 1 Do
      Begin
        RemotesGrid.Cells[0, I + 1] := Names[I];
        RemotesGrid.Objects[0, I + 1] := TObject(PtrInt(I + 1));
        If I < Urls.Count Then
          RemotesGrid.Cells[1, I + 1] := Urls[I]
        Else
          RemotesGrid.Cells[1, I + 1] := '';
        OriginalNames.Add(Names[I]);
        If I < Urls.Count Then
          OriginalUrls.Add(Urls[I])
        Else
          OriginalUrls.Add('');
      End;
    If Names.Count > 0 Then
      RemotesGrid.Row := 1;
  Finally
    Names.Free;
    Urls.Free;
  End;
End;

Procedure TGitRemotesForm.GridSelectCell(Sender: TObject; aCol, aRow: Integer; Var CanSelect: Boolean);
Begin
  CanSelect := True;
  If FEditing And (aRow <> FEditRow) Then
    SetGridEditable(False);
End;

Procedure TGitRemotesForm.GridMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
Var
  ACol, ARow: Integer;
  LastCell: TRect;
Begin
  If Not FEditing Then
    Exit;
  RemotesGrid.MouseToCell(X, Y, ACol, ARow);
  If (ACol < 0) Or (ARow < RemotesGrid.FixedRows) Or (ARow >= RemotesGrid.RowCount) Then
    Begin
      SetGridEditable(False);
      Exit;
    End;
  If RemotesGrid.RowCount > RemotesGrid.FixedRows Then
    Begin
      LastCell := RemotesGrid.CellRect(0, RemotesGrid.RowCount - 1);
      If (LastCell.Bottom > 0) And (Y > LastCell.Bottom) Then
        SetGridEditable(False);
    End;
End;

Procedure TGitRemotesForm.AddButtonClick(Sender: TObject);
Var
  NewRow: Integer;
Begin
  NewRow := RemotesGrid.RowCount;
  RemotesGrid.RowCount := NewRow + 1;
  RemotesGrid.Cells[0, NewRow] := '';
  RemotesGrid.Objects[0, NewRow] := Nil;
  RemotesGrid.Cells[1, NewRow] := '';
  RemotesGrid.Row := NewRow;
  RemotesGrid.Col := 0;
  SetGridEditable(True);
  If RemotesGrid.CanFocus Then
    RemotesGrid.SetFocus;
  RemotesGrid.EditorMode := True;
End;

Procedure TGitRemotesForm.EditButtonClick(Sender: TObject);
Begin
  If RemotesGrid.Row < RemotesGrid.FixedRows Then
    Begin
      MessageDlg('Select a remote row to edit.', mtWarning, [mbOK], 0);
      Exit;
    End;
  If DataRowCount = 0 Then
    Begin
      MessageDlg('No remotes to edit. Use Add to create one.', mtWarning, [mbOK], 0);
      Exit;
    End;
  SetGridEditable(True);
  RemotesGrid.Col := 0;
  If RemotesGrid.CanFocus Then
    RemotesGrid.SetFocus;
  RemotesGrid.EditorMode := True;
End;

Procedure TGitRemotesForm.RemoveButtonClick(Sender: TObject);
Var
  Row: Integer;
  RemoteName: String;
Begin
  Row := RemotesGrid.Row;
  If Row < RemotesGrid.FixedRows Then
    Begin
      MessageDlg('Select a remote row to remove.', mtWarning, [mbOK], 0);
      Exit;
    End;
  RemoteName := Trim(RemotesGrid.Cells[0, Row]);
  If RemoteName = '' Then
    RemoteName := 'this empty row';
  If MessageDlg('Remove remote "' + RemoteName + '" from the list?', mtWarning, [mbYes, mbNo], 0) <> mrYes Then
    Exit;
  SetGridEditable(False);
  RemotesGrid.DeleteColRow(False, Row);
  If RemotesGrid.RowCount <= RemotesGrid.FixedRows Then
    RemotesGrid.RowCount := RemotesGrid.FixedRows;
End;

Function TGitRemotesForm.ValidateGrid(Out ErrorMessage: String): Boolean;
Var
  I, J: Integer;
  RemoteName, Url: String;
Begin
  Result := False;
  ErrorMessage := '';
  For I := RemotesGrid.FixedRows To RemotesGrid.RowCount - 1 Do
    Begin
      RemoteName := Trim(RemotesGrid.Cells[0, I]);
      Url := Trim(RemotesGrid.Cells[1, I]);
      If (RemoteName = '') And (Url = '') Then
        Continue;
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
      For J := RemotesGrid.FixedRows To I - 1 Do
        If SameText(Trim(RemotesGrid.Cells[0, J]), RemoteName) Then
          Begin
            ErrorMessage := Format('Duplicate remote name "%s".', [RemoteName]);
            Exit;
          End;
    End;
  Result := True;
End;

Function TGitRemotesForm.SaveToGit(Out ErrorMessage: String): Boolean;
Var
  Snapshot: TGitRemoteSnapshot;
  Names, Urls, Originals, TempNames: TStringList;
  I, Row, Identity, N: Integer;
  RemoteName, Url, TempName: String;
  Mutated: Boolean;
  Function FailSave(Const Message: String): Boolean;
  Begin
    ErrorMessage := Message;
    If Mutated And Not GitClient.RestoreRemotes(Snapshot) Then
      ErrorMessage := ErrorMessage + LineEnding + 'Remote rollback failed: ' + GitClient.LastError;
    Result := False;
  End;
Begin
  Result := False; ErrorMessage := ''; Mutated := False;
  If Not Assigned(GitClient) Then Begin ErrorMessage := 'Git client is not available.'; Exit; End;
  GitClient.RepoPath := FRepoPath;
  Names := TStringList.Create; Names.CaseSensitive := True;
  Urls := TStringList.Create; Originals := TStringList.Create; Originals.CaseSensitive := True;
  TempNames := TStringList.Create;
  Try
    For Row := RemotesGrid.FixedRows To RemotesGrid.RowCount - 1 Do
      Begin
        RemoteName := Trim(RemotesGrid.Cells[0, Row]); Url := Trim(RemotesGrid.Cells[1, Row]);
        If (RemoteName = '') And (Url = '') Then Continue;
        Names.Add(RemoteName); Urls.Add(Url);
        Identity := PtrInt(RemotesGrid.Objects[0, Row]) - 1;
        If (Identity >= 0) And (Identity < OriginalNames.Count) Then Originals.Add(OriginalNames[Identity])
        Else Originals.Add('');
        TempNames.Add('');
      End;
    If Not GitClient.SnapshotRemotes(Snapshot) Then Exit(FailSave(GitClient.LastError));
    { Move renamed rows out of the way first, so swaps and rename cycles work. }
    N := 0;
    For I := 0 To Names.Count - 1 Do
      If (Originals[I] <> '') And (Originals[I] <> Names[I]) Then
        Begin
          Repeat
            Inc(N); TempName := 'lazworkflow-rename-' + IntToStr(GetProcessID) + '-' + IntToStr(N);
          Until (OriginalNames.IndexOf(TempName) < 0) And (Names.IndexOf(TempName) < 0);
          Mutated := True;
          If Not GitClient.RenameRemote(Originals[I], TempName) Then Exit(FailSave(GitClient.LastError));
          TempNames[I] := TempName;
        End;
    For I := 0 To OriginalNames.Count - 1 Do
      If Originals.IndexOf(OriginalNames[I]) < 0 Then
        Begin
          Mutated := True;
          If Not GitClient.RemoveRemote(OriginalNames[I]) Then Exit(FailSave(GitClient.LastError));
        End;
    For I := 0 To Names.Count - 1 Do
      Begin
        If TempNames[I] <> '' Then
          Begin
            If Not GitClient.RenameRemote(TempNames[I], Names[I]) Then Exit(FailSave(GitClient.LastError));
          End;
        Mutated := True;
        If Originals[I] = '' Then
          Begin
            If Not GitClient.AddRemote(Names[I], Urls[I]) Then Exit(FailSave(GitClient.LastError));
          End
        Else If OriginalUrls[OriginalNames.IndexOf(Originals[I])] <> Urls[I] Then
          If Not GitClient.SetRemoteUrl(Names[I], Urls[I]) Then Exit(FailSave(GitClient.LastError));
      End;
    WorkflowLogger.Info('GitRemotes', 'Saved remotes for ' + FRepoPath); Result := True;
  Finally TempNames.Free; Originals.Free; Urls.Free; Names.Free; End;
End;

Procedure TGitRemotesForm.FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
Var
  ErrorMessage: String;
Begin
  CanClose := True;
  If ModalResult <> mrOk Then
    Exit;

  SetGridEditable(False);
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
