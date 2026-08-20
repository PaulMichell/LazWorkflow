Unit ManageRepositoryFiles;

{ Files-tab lists and status apply for Manage Repository (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, StdCtrls, GitService, GitDiffView;

Type
  TManageFilesPane = Class
  Private
    FFilesPaths: TStringList;
    FStagedPaths: TStringList;
    Function DescribeFileStatus(IndexStatus, WorkTreeStatus: Char): String;
    Function FileStatusPassesFilter(Const StatusText: String): Boolean;
  Public
    FilesList: TListBox;
    StagedList: TListBox;
    FilesDiffView: TGitDiffView;
    UntrackedCheck: TCheckBox;
    CleanCheck: TCheckBox;
    IgnoredCheck: TCheckBox;
    StagedLabel: TLabel;
    RepoPath: String;
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Bind(AFilesList, AStagedList: TListBox; ADiffView: TGitDiffView;
      AUntrackedCheck, ACleanCheck, AIgnoredCheck: TCheckBox; AStagedLabel: TLabel);
    Function HasStaged: Boolean;
    Function HasUnstaged: Boolean;
    Function ListHasSelection(List: TListBox): Boolean;
    Function CollectSelected(List: TListBox; Paths: TStringList): TStringList;
    Function CollectActiveSelected: TStringList;
    Procedure ClearForNoRepo;
    Procedure ApplyFromStatus(Const Entries: TGitStatusEntryArray);
    Procedure ShowSelectedDiff(FromStaged: Boolean);
    Property FilesPaths: TStringList Read FFilesPaths;
    Property StagedPaths: TStringList Read FStagedPaths;
  End;

Implementation

Uses
  LazFileUtils;

Constructor TManageFilesPane.Create;
Begin
  Inherited Create;
  FFilesPaths := TStringList.Create;
  FStagedPaths := TStringList.Create;
  RepoPath := '';
End;

Destructor TManageFilesPane.Destroy;
Begin
  FreeAndNil(FFilesPaths);
  FreeAndNil(FStagedPaths);
  Inherited Destroy;
End;

Procedure TManageFilesPane.Bind(AFilesList, AStagedList: TListBox; ADiffView: TGitDiffView;
  AUntrackedCheck, ACleanCheck, AIgnoredCheck: TCheckBox; AStagedLabel: TLabel);
Begin
  FilesList := AFilesList;
  StagedList := AStagedList;
  FilesDiffView := ADiffView;
  UntrackedCheck := AUntrackedCheck;
  CleanCheck := ACleanCheck;
  IgnoredCheck := AIgnoredCheck;
  StagedLabel := AStagedLabel;
End;

Function TManageFilesPane.HasStaged: Boolean;
Begin
  Result := Assigned(FStagedPaths) And (FStagedPaths.Count > 0);
End;

Function TManageFilesPane.HasUnstaged: Boolean;
Begin
  Result := Assigned(FFilesPaths) And (FFilesPaths.Count > 0);
End;

Function TManageFilesPane.ListHasSelection(List: TListBox): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  If List = Nil Then
    Exit;
  For I := 0 To List.Count - 1 Do
    If List.Selected[I] Then
      Begin
        Result := True;
        Exit;
      End;
End;

Function TManageFilesPane.CollectSelected(List: TListBox; Paths: TStringList): TStringList;
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

Function TManageFilesPane.CollectActiveSelected: TStringList;
Begin
  Result := CollectSelected(FilesList, FFilesPaths);
  If Result.Count = 0 Then
    Begin
      Result.Free;
      Result := CollectSelected(StagedList, FStagedPaths);
    End;
End;

Procedure TManageFilesPane.ClearForNoRepo;
Begin
  If Not Assigned(FilesList) Or Not Assigned(StagedList) Then
    Exit;
  FilesList.Items.BeginUpdate;
  StagedList.Items.BeginUpdate;
  Try
    FilesList.Items.Clear;
    StagedList.Items.Clear;
    FFilesPaths.Clear;
    FStagedPaths.Clear;
    FilesList.Items.Add('(no repository)');
  Finally
    StagedList.Items.EndUpdate;
    FilesList.Items.EndUpdate;
  End;
  If Assigned(StagedLabel) Then
    StagedLabel.Caption := 'Staged for commit (0)';
  If Assigned(FilesDiffView) Then
    FilesDiffView.Clear;
End;

Function TManageFilesPane.DescribeFileStatus(IndexStatus, WorkTreeStatus: Char): String;
Var
  X, Y: Char;
Begin
  X := IndexStatus;
  Y := WorkTreeStatus;
  If (X = '?') And (Y = '?') Then
    Result := 'untracked'
  Else If (X = '!') Or (Y = '!') Then
    Result := 'ignored'
  Else If (X = 'A') Or (Y = 'A') Then
    Result := 'added'
  Else If (X = 'D') Or (Y = 'D') Then
    Result := 'deleted'
  Else If (X = 'R') Or (Y = 'R') Then
    Result := 'renamed'
  Else If (X = 'C') Or (Y = 'C') Then
    Result := 'copied'
  Else If (X = 'U') Or (Y = 'U') Then
    Result := 'unmerged'
  Else If (X = 'M') Or (Y = 'M') Then
    Result := 'modified'
  Else If (X <> ' ') Or (Y <> ' ') Then
    Result := Trim(X + Y)
  Else
    Result := 'clean';
End;

Function TManageFilesPane.FileStatusPassesFilter(Const StatusText: String): Boolean;
Begin
  If StatusText = 'untracked' Then
    Result := Assigned(UntrackedCheck) And UntrackedCheck.Checked
  Else If StatusText = 'clean' Then
    Result := Assigned(CleanCheck) And CleanCheck.Checked
  Else If StatusText = 'ignored' Then
    Result := Assigned(IgnoredCheck) And IgnoredCheck.Checked
  Else
    Result := True;
End;

Procedure TManageFilesPane.ApplyFromStatus(Const Entries: TGitStatusEntryArray);
Var
  AllFiles, StatusMap, FullyStaged, Tracked: TStringList;
  I: Integer;
  FullPath, Rel, Root, StatusText: String;
  Idx: Integer;
  EntryStatus: String;
  WantClean: Boolean;
Begin
  Tracked := Nil;
  If Not Assigned(FilesList) Or Not Assigned(StagedList) Then
    Exit;

  FilesList.Items.BeginUpdate;
  StagedList.Items.BeginUpdate;
  Try
    FilesList.Items.Clear;
    StagedList.Items.Clear;
    FFilesPaths.Clear;
    FStagedPaths.Clear;

    If (RepoPath = '') Or Not DirectoryExists(RepoPath) Then
      Begin
        FilesList.Items.Add('(no repository)');
        Exit;
      End;

    Root := IncludeTrailingPathDelimiter(ExpandFileName(RepoPath));
    StatusMap := TStringList.Create;
    FullyStaged := TStringList.Create;
    AllFiles := TStringList.Create;
    Try
      { Filenames may contain '='. Git rejects ASCII control characters in paths. }
      StatusMap.NameValueSeparator := #1;
      StatusMap.Sorted := True;
      StatusMap.Duplicates := dupIgnore;
      StatusMap.CaseSensitive := FileNameCaseSensitive;
      FullyStaged.Sorted := True;
      FullyStaged.Duplicates := dupIgnore;
      FullyStaged.CaseSensitive := FileNameCaseSensitive;

      For I := 0 To High(Entries) Do
        Begin
          Rel := StringReplace(Entries[I].Path, '\', '/', [rfReplaceAll]);
          EntryStatus := DescribeFileStatus(Entries[I].IndexStatus, Entries[I].WorkTreeStatus);
          StatusMap.Values[Rel] := EntryStatus;
          If GitStatusEntryIsStaged(Entries[I]) Then
            Begin
              StagedList.Items.Add(GitStatusEntryLabel(Entries[I], True));
              FStagedPaths.Add(Rel);
              If Not GitStatusEntryIsUnstaged(Entries[I]) Then
                FullyStaged.Add(Rel);
            End;
        End;

      WantClean := Assigned(CleanCheck) And CleanCheck.Checked;
      AllFiles.Sorted := True;
      AllFiles.Duplicates := dupIgnore;
      If WantClean And Assigned(GitClient) Then
        Begin
          GitClient.RepoPath := RepoPath;
          If GitClient.ListTrackedFiles(Tracked) Then
            AllFiles.AddStrings(Tracked);
          Tracked.Free;
        End
      Else
        For I := 0 To StatusMap.Count - 1 Do
          AllFiles.Add(Root + StringReplace(StatusMap.Names[I], '/', DirectorySeparator, [rfReplaceAll]));
      For I := 0 To AllFiles.Count - 1 Do
        Begin
          FullPath := ExpandFileName(AllFiles[I]);
          Rel := StringReplace(FullPath, '\', '/', [rfReplaceAll]);
          If Pos('/.git/', Rel + '/') > 0 Then
            Continue;
          If CompareFilenames(Copy(FullPath, 1, Length(Root)), Root) = 0 Then
            Delete(FullPath, 1, Length(Root))
          Else
            Continue;
          Rel := StringReplace(FullPath, '\', '/', [rfReplaceAll]);
          If Rel = '' Then
            Continue;
          If FullyStaged.IndexOf(Rel) >= 0 Then
            Continue;
          Idx := StatusMap.IndexOfName(Rel);
          If Idx >= 0 Then
            StatusText := StatusMap.ValueFromIndex[Idx]
          Else
            StatusText := 'clean';
          If Not FileStatusPassesFilter(StatusText) Then
            Continue;
          FilesList.Items.Add(Rel + '  ' + StatusText);
          FFilesPaths.Add(Rel);
        End;

      For I := 0 To StatusMap.Count - 1 Do
        Begin
          Rel := StatusMap.Names[I];
          If Rel = '' Then
            Continue;
          If FullyStaged.IndexOf(Rel) >= 0 Then
            Continue;
          StatusText := StatusMap.ValueFromIndex[I];
          If Not FileStatusPassesFilter(StatusText) Then
            Continue;
          FullPath := Root + StringReplace(Rel, '/', DirectorySeparator, [rfReplaceAll]);
          If FileExists(FullPath) Then
            Continue;
          If FFilesPaths.IndexOf(Rel) < 0 Then
            Begin
              FilesList.Items.Add(Rel + '  ' + StatusText);
              FFilesPaths.Add(Rel);
            End;
        End;

      If FilesList.Items.Count = 0 Then
        FilesList.Items.Add('(no files)');
    Finally
      AllFiles.Free;
      FullyStaged.Free;
      StatusMap.Free;
    End;
  Finally
    FilesList.Items.EndUpdate;
    StagedList.Items.EndUpdate;
  End;

  If Assigned(StagedLabel) Then
    StagedLabel.Caption := Format('Staged for commit (%d)', [FStagedPaths.Count]);
  If Assigned(FilesDiffView) Then
    FilesDiffView.Clear;
End;

Procedure TManageFilesPane.ShowSelectedDiff(FromStaged: Boolean);
Var
  List: TListBox;
  Paths: TStringList;
  I: Integer;
  DiffText, Path, Title, Content: String;
Begin
  If Not Assigned(FilesDiffView) Then
    Exit;
  If FromStaged Then
    Begin
      List := StagedList;
      Paths := FStagedPaths;
    End
  Else
    Begin
      List := FilesList;
      Paths := FFilesPaths;
    End;
  FilesDiffView.Clear;
  FilesDiffView.SetViewMode(dvmEditorOnly);
  FilesDiffView.SetStagingContext(RepoPath, FromStaged);
  If (List = Nil) Or (Paths = Nil) Or Not Assigned(GitClient) Then
    Exit;
  For I := 0 To List.Count - 1 Do
    If List.Selected[I] And (I < Paths.Count) Then
      Begin
        Path := Paths[I];
        If FromStaged Then
          Title := 'Staged: ' + Path
        Else
          Title := 'Working tree: ' + Path;
        GitClient.RepoPath := RepoPath;
        If FilesDiffView.LoadBinaryOrImagePreview(Title, Path, '', FromStaged) Then
          Exit;
        If GitClient.DiffPath(Path, FromStaged, DiffText) Then
          Begin
            If Trim(DiffText) = '' Then
              Begin
                If (Not FromStaged) And GitClient.ReadWorkingTreeFile(Path, Content) Then
                  FilesDiffView.LoadPlainText(Title + ' (clean)', Content, Path)
                Else If FromStaged Then
                  FilesDiffView.LoadPlainText(Title, '(no staged changes for this file)', Path)
                Else
                  FilesDiffView.LoadPlainText(Title, '(no textual content)', Path);
              End
            Else
              FilesDiffView.LoadEmbeddedDiff(Title, DiffText, Path);
          End
        Else
          FilesDiffView.LoadPlainText(Title, 'Diff failed: ' + GitClient.LastError);
        Exit;
      End;
End;

End.
