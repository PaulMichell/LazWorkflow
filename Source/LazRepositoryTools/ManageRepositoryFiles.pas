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
    FLastFromStaged: Boolean;
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
    Procedure ApplyFromStatus(Const Entries: TGitStatusEntryArray; Tracked: TStrings);
    Procedure RefreshSelectedDiff;
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
  FFilesPaths.CaseSensitive := FileNameCaseSensitive;
  FStagedPaths := TStringList.Create;
  FStagedPaths.CaseSensitive := FileNameCaseSensitive;
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
  Result.CaseSensitive := FileNameCaseSensitive;
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

Procedure TManageFilesPane.ApplyFromStatus(Const Entries: TGitStatusEntryArray; Tracked: TStrings);
Var
  AllEntries: TGitStatusEntryArray;
  SavedFiles, SavedStaged: TStringList;
  I: Integer;
  StatusText: String;
Begin
  If Not Assigned(FilesList) Or Not Assigned(StagedList) Then Exit;
  SavedFiles := CollectSelected(FilesList, FFilesPaths);
  SavedStaged := CollectSelected(StagedList, FStagedPaths);
  FilesList.Items.BeginUpdate; StagedList.Items.BeginUpdate;
  Try
    FilesList.Items.Clear; StagedList.Items.Clear;
    FFilesPaths.Clear; FStagedPaths.Clear;
    AllEntries := MergeGitFileEntries(RepoPath, Entries, Tracked);
    For I := 0 To High(AllEntries) Do
      Begin
        If GitStatusEntryIsStaged(AllEntries[I]) Then
          Begin
            StagedList.Items.Add(GitStatusEntryLabel(AllEntries[I], True));
            FStagedPaths.Add(AllEntries[I].Path);
          End;
        If GitStatusEntryIsStaged(AllEntries[I]) And Not GitStatusEntryIsUnstaged(AllEntries[I]) Then Continue;
        StatusText := DescribeFileStatus(AllEntries[I].IndexStatus, AllEntries[I].WorkTreeStatus);
        If Not FileStatusPassesFilter(StatusText) Then Continue;
        FilesList.Items.Add(AllEntries[I].Path + '  ' + StatusText);
        FFilesPaths.Add(AllEntries[I].Path);
      End;
    For I := 0 To FFilesPaths.Count - 1 Do FilesList.Selected[I] := SavedFiles.IndexOf(FFilesPaths[I]) >= 0;
    For I := 0 To FStagedPaths.Count - 1 Do StagedList.Selected[I] := SavedStaged.IndexOf(FStagedPaths[I]) >= 0;
    If FilesList.Items.Count = 0 Then FilesList.Items.Add('(no files)');
  Finally
    StagedList.Items.EndUpdate; FilesList.Items.EndUpdate;
    SavedFiles.Free; SavedStaged.Free;
  End;
  If Assigned(StagedLabel) Then StagedLabel.Caption := Format('Staged for commit (%d)', [FStagedPaths.Count]);
  RefreshSelectedDiff;
End;

Procedure TManageFilesPane.RefreshSelectedDiff;
Begin
  ShowSelectedDiff(FLastFromStaged);
End;

Procedure TManageFilesPane.ShowSelectedDiff(FromStaged: Boolean);
Var
  List: TListBox;
  Paths: TStringList;
  I: Integer;
  Path: String;
Begin
  FLastFromStaged := FromStaged;
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
  FilesDiffView.SetViewMode(dvmEditorOnly);
  FilesDiffView.SetStagingContext(RepoPath, FromStaged);
  If (List = Nil) Or (Paths = Nil) Or Not Assigned(FilesDiffView) Then
    Exit;
  For I := 0 To List.Count - 1 Do
    If List.Selected[I] And (I < Paths.Count) Then
      Begin
        Path := Paths[I];
        FilesDiffView.LoadWorkingFile(RepoPath, Path, FromStaged);
        Exit;
      End;
  FilesDiffView.Clear;
End;

End.
