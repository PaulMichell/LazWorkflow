Unit ManageRepositoryChanges;

{ Changes-tab lists and status apply for Manage Repository (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, StdCtrls, GitService, GitDiffView;

Type
  TManageChangesPane = Class
  Private
    FLastFromStaged: Boolean;
    FChangesPaths: TStringList;
    FStagedPaths: TStringList;
    Function DescribeFileStatus(IndexStatus, WorkTreeStatus: Char): String;
    Function FileStatusPassesFilter(Const StatusText: String): Boolean;
  Public
    ChangesList: TListBox;
    StagedList: TListBox;
    ChangesDiffView: TGitDiffView;
    UntrackedCheck: TCheckBox;
    CleanCheck: TCheckBox;
    IgnoredCheck: TCheckBox;
    StagedLabel: TLabel;
    RepoPath: String;
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Bind(AChangesList, AStagedList: TListBox; ADiffView: TGitDiffView;
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
    Property ChangesPaths: TStringList Read FChangesPaths;
    Property StagedPaths: TStringList Read FStagedPaths;
  End;

Implementation

Uses
  LazFileUtils;

Constructor TManageChangesPane.Create;
Begin
  Inherited Create;
  FChangesPaths := TStringList.Create;
  FChangesPaths.CaseSensitive := FileNameCaseSensitive;
  FStagedPaths := TStringList.Create;
  FStagedPaths.CaseSensitive := FileNameCaseSensitive;
  RepoPath := '';
End;

Destructor TManageChangesPane.Destroy;
Begin
  FreeAndNil(FChangesPaths);
  FreeAndNil(FStagedPaths);
  Inherited Destroy;
End;

Procedure TManageChangesPane.Bind(AChangesList, AStagedList: TListBox; ADiffView: TGitDiffView;
  AUntrackedCheck, ACleanCheck, AIgnoredCheck: TCheckBox; AStagedLabel: TLabel);
Begin
  ChangesList := AChangesList;
  StagedList := AStagedList;
  ChangesDiffView := ADiffView;
  UntrackedCheck := AUntrackedCheck;
  CleanCheck := ACleanCheck;
  IgnoredCheck := AIgnoredCheck;
  StagedLabel := AStagedLabel;
End;

Function TManageChangesPane.HasStaged: Boolean;
Begin
  Result := Assigned(FStagedPaths) And (FStagedPaths.Count > 0);
End;

Function TManageChangesPane.HasUnstaged: Boolean;
Begin
  Result := Assigned(FChangesPaths) And (FChangesPaths.Count > 0);
End;

Function TManageChangesPane.ListHasSelection(List: TListBox): Boolean;
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

Function TManageChangesPane.CollectSelected(List: TListBox; Paths: TStringList): TStringList;
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

Function TManageChangesPane.CollectActiveSelected: TStringList;
Begin
  Result := CollectSelected(ChangesList, FChangesPaths);
  If Result.Count = 0 Then
    Begin
      Result.Free;
      Result := CollectSelected(StagedList, FStagedPaths);
    End;
End;

Procedure TManageChangesPane.ClearForNoRepo;
Begin
  If Not Assigned(ChangesList) Or Not Assigned(StagedList) Then
    Exit;
  ChangesList.Items.BeginUpdate;
  StagedList.Items.BeginUpdate;
  Try
    ChangesList.Items.Clear;
    StagedList.Items.Clear;
    FChangesPaths.Clear;
    FStagedPaths.Clear;
    ChangesList.Items.Add('(no repository)');
  Finally
    StagedList.Items.EndUpdate;
    ChangesList.Items.EndUpdate;
  End;
  If Assigned(StagedLabel) Then
    StagedLabel.Caption := 'Staged for commit (0)';
  If Assigned(ChangesDiffView) Then
    ChangesDiffView.Clear;
End;

Function TManageChangesPane.DescribeFileStatus(IndexStatus, WorkTreeStatus: Char): String;
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

Function TManageChangesPane.FileStatusPassesFilter(Const StatusText: String): Boolean;
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

Procedure TManageChangesPane.ApplyFromStatus(Const Entries: TGitStatusEntryArray; Tracked: TStrings);
Var
  AllEntries: TGitStatusEntryArray;
  SavedChanges, SavedStaged: TStringList;
  I: Integer;
  StatusText: String;
Begin
  If Not Assigned(ChangesList) Or Not Assigned(StagedList) Then Exit;
  SavedChanges := CollectSelected(ChangesList, FChangesPaths);
  SavedStaged := CollectSelected(StagedList, FStagedPaths);
  ChangesList.Items.BeginUpdate; StagedList.Items.BeginUpdate;
  Try
    ChangesList.Items.Clear; StagedList.Items.Clear;
    FChangesPaths.Clear; FStagedPaths.Clear;
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
        ChangesList.Items.Add(AllEntries[I].Path + '  ' + StatusText);
        FChangesPaths.Add(AllEntries[I].Path);
      End;
    For I := 0 To FChangesPaths.Count - 1 Do ChangesList.Selected[I] := SavedChanges.IndexOf(FChangesPaths[I]) >= 0;
    For I := 0 To FStagedPaths.Count - 1 Do StagedList.Selected[I] := SavedStaged.IndexOf(FStagedPaths[I]) >= 0;
    If ChangesList.Items.Count = 0 Then ChangesList.Items.Add('(no changes)');
  Finally
    StagedList.Items.EndUpdate; ChangesList.Items.EndUpdate;
    SavedChanges.Free; SavedStaged.Free;
  End;
  If Assigned(StagedLabel) Then StagedLabel.Caption := Format('Staged for commit (%d)', [FStagedPaths.Count]);
  RefreshSelectedDiff;
End;

Procedure TManageChangesPane.RefreshSelectedDiff;
Begin
  ShowSelectedDiff(FLastFromStaged);
End;

Procedure TManageChangesPane.ShowSelectedDiff(FromStaged: Boolean);
Var
  List: TListBox;
  Paths: TStringList;
  I: Integer;
  Path: String;
Begin
  FLastFromStaged := FromStaged;
  If Not Assigned(ChangesDiffView) Then
    Exit;
  If FromStaged Then
    Begin
      List := StagedList;
      Paths := FStagedPaths;
    End
  Else
    Begin
      List := ChangesList;
      Paths := FChangesPaths;
    End;
  ChangesDiffView.SetViewMode(dvmEditorOnly);
  ChangesDiffView.SetStagingContext(RepoPath, FromStaged);
  If (List = Nil) Or (Paths = Nil) Or Not Assigned(ChangesDiffView) Then
    Exit;
  For I := 0 To List.Count - 1 Do
    If List.Selected[I] And (I < Paths.Count) Then
      Begin
        Path := Paths[I];
        ChangesDiffView.LoadWorkingFile(RepoPath, Path, FromStaged);
        Exit;
      End;
  ChangesDiffView.Clear;
End;

End.
