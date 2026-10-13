Unit ManageRepositoryFiles;

{ Files-tab tree, commit list, revision text, image preview, and save (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. Tree building, commit parsing,
  and preview/save state share one token set, so they stay in this coordinator.
  Reviewed 2026-08: no hidden foundation or sibling service material. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, ComCtrls, StdCtrls, ExtCtrls, Graphics, SynEdit, GitDiffView;

Type
  TRepositorySaveKind = (skNone, skText, skBytes);

  TManageFilesPane = Class
  Private
    FApplying: Boolean;
    FFileListToken: Integer;
    FHistoryToken: Integer;
    FContentToken: Integer;
    FDiffToken: Integer;
    FSelectedPath: String;
    FSelectedSha: String;
    FContentPath: String;
    FRevisionHighlighter: TObject;
    FPreviewPicture: TPicture;
    FShowChanges: Boolean;
    FTextReady: Boolean;
    FContentSettled: Boolean;
    FRemovedRevision: Boolean;
    FDiffPending: Boolean;
    FDiffReady: Boolean;
    FDiffOk: Boolean;
    FSaveKind: TRepositorySaveKind;
    FSaveText: String;
    FSaveBytes: TMemoryStream;
    FSaveBlockReason: String;
    FDiffText: String;
    FDiffPath: String;
    FDiffSha: String;
    Procedure ClearCommitObjects;
    Procedure ClearRevisionHighlighter;
    Procedure ApplyRevisionHighlighter(Const FileName: String);
    Procedure ClearSavePayload;
    Procedure KeepSaveBytes(Bytes: TStream);
    Procedure NotifyCommands;
    Procedure ShowBlankPane;
    Procedure ShowMessagePane(Const MessageText: String);
    Procedure ShowImageContent;
    Procedure ShowTextPane;
    Procedure ShowChangesEditor;
    Procedure ShowStoredText;
    Procedure ShowStoredDiff;
    Procedure ShowChangesLoading;
    Procedure HideEditors;
    Procedure ClearEditor;
    Procedure FreeTreeEntries;
    Procedure TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    Function SelectedEntryPath(Out RelativePath: String): Boolean;
    Function PathLooksText(Const RelativePath: String): Boolean;
  Public
    FileTree: TTreeView;
    FileCommitList: TListBox;
    FileRevisionEditor: TSynEdit;
    FilePreviewPanel: TPanel;
    FileImagePaintBox: TPaintBox;
    FilePreviewLabel: TLabel;
    FileChangesView: TGitDiffView;
    RepoPath: String;
    OnRequestHistory: TNotifyEvent;
    OnRequestContent: TNotifyEvent;
    OnRequestDiff: TNotifyEvent;
    OnCommandsChanged: TNotifyEvent;
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Bind(AFileTree: TTreeView; ACommitList: TListBox; AEditor: TSynEdit; APreviewPanel: TPanel;
      AImagePaint: TPaintBox; APreviewLabel: TLabel; AChangesView: TGitDiffView);
    Procedure ClearForNoRepo;
    Function BeginFileList: Integer;
    Procedure ApplyFileList(Token: Integer; Paths, RemovedPaths: TStrings; Ok: Boolean);
    Function BeginHistory: Integer;
    Procedure ApplyHistory(Token: Integer; Const Path, CommitLines: String; Ok: Boolean);
    Function BeginContent: Integer;
    Procedure ApplyContent(Token: Integer; Const HistoricalPath, Sha, Content: String; IsBinary, Ok: Boolean);
    Procedure ApplyImage(Token: Integer; Const HistoricalPath, Sha: String; Bytes: TStream; Ok: Boolean;
      Const ErrorText: String);
    Procedure ApplyBinary(Token: Integer; Const HistoricalPath, Sha: String; Bytes: TStream; Ok: Boolean;
      Const ErrorText: String);
    Function BeginDiff: Integer;
    Procedure ApplyDiff(Token: Integer; Const HistoricalPath, Sha, DiffText: String; Ok: Boolean);
    Procedure PaintPreview;
    Function ContentIsImage: Boolean;
    Function ContentReadsBytes: Boolean;
    Function FileSelected: Boolean;
    Function TextPreviewActive: Boolean;
    Function CanWriteDisplayedFile: Boolean;
    Function DisplayedFileStatus: String;
    Function SuggestedSaveName: String;
    Function SuggestedSaveDirectory: String;
    /// Writes the commit blob, not the red/green diff markup.
    Function WriteDisplayedFile(Const TargetPath: String; Out ErrorText: String): Boolean;
    Procedure SetShowChanges(Value: Boolean);
    Procedure TreeSelectionChanged;
    Procedure CommitSelectionChanged;
    Property SelectedPath: String Read FSelectedPath;
    Property SelectedSha: String Read FSelectedSha;
    Property ContentPath: String Read FContentPath;
  End;

Implementation

Uses
  SysUtils, LazEditHighlighter, RepositorySyntax, RepositoryImagePreview;

Type
  TRepositoryTreeEntry = Class
    RelativePath: String;
    IsFile: Boolean;
    Removed: Boolean;
  End;

  TRepositoryFileCommit = Class
    Sha: String;
    WhenText: String;
    Subject: String;
    HistoricalPath: String;
    Removed: Boolean;
  End;

Const
  FileRemovedCaption = 'File Removed';
  BinaryFileCaption = 'Non-text binary file contents.';
  LoadingCaption = '(loading…)';

Function DisplayFileName(Const RelativePath: String): String;
Begin
  Result := ExtractFileName(StringReplace(RelativePath, '/', PathDelim, [rfReplaceAll]));
  If Result = '' Then
    Result := 'file';
End;

Constructor TManageFilesPane.Create;
Begin
  Inherited Create;
  FFileListToken := 0;
  FHistoryToken := 0;
  FContentToken := 0;
  FDiffToken := 0;
  RepoPath := '';
  FPreviewPicture := TPicture.Create;
  FSaveBytes := TMemoryStream.Create;
  FSaveKind := skNone;
  FSaveBlockReason := 'Select a file to save.';
End;

Destructor TManageFilesPane.Destroy;
Begin
  ClearForNoRepo;
  FreeAndNil(FSaveBytes);
  FreeAndNil(FPreviewPicture);
  Inherited Destroy;
End;

Procedure TManageFilesPane.Bind(AFileTree: TTreeView; ACommitList: TListBox; AEditor: TSynEdit; APreviewPanel: TPanel;
  AImagePaint: TPaintBox; APreviewLabel: TLabel; AChangesView: TGitDiffView);
Begin
  FileTree := AFileTree;
  FileCommitList := ACommitList;
  FileRevisionEditor := AEditor;
  FilePreviewPanel := APreviewPanel;
  FileImagePaintBox := AImagePaint;
  FilePreviewLabel := APreviewLabel;
  FileChangesView := AChangesView;
  If Assigned(FileTree) Then
    FileTree.OnCustomDrawItem := @TreeCustomDrawItem;
  If Assigned(FileChangesView) Then
    FileChangesView.SetViewMode(dvmEditorOnly);
  ShowBlankPane;
  NotifyCommands;
End;

Procedure TManageFilesPane.ClearCommitObjects;
Var
  I: Integer;
Begin
  If Not Assigned(FileCommitList) Then
    Exit;
  For I := 0 To FileCommitList.Items.Count - 1 Do
    FileCommitList.Items.Objects[I].Free;
  FileCommitList.Items.Clear;
End;

Procedure TManageFilesPane.ClearRevisionHighlighter;
Begin
  If Assigned(FileRevisionEditor) And Assigned(FRevisionHighlighter) And
     (FileRevisionEditor.Highlighter = TLazEditCustomHighlighter(FRevisionHighlighter)) Then
    FileRevisionEditor.Highlighter := Nil;
  FreeAndNil(FRevisionHighlighter);
End;

Procedure TManageFilesPane.ApplyRevisionHighlighter(Const FileName: String);
Var
  HL: TLazEditCustomHighlighter;
Begin
  ClearRevisionHighlighter;
  If Not Assigned(FileRevisionEditor) Or (FileName = '') Then
    Exit;
  HL := CreateRepositoryLanguageHighlighter(FileName);
  If Not Assigned(HL) Then
    Exit;
  FRevisionHighlighter := HL;
  FileRevisionEditor.Highlighter := HL;
End;

Procedure TManageFilesPane.ClearSavePayload;
Begin
  FSaveKind := skNone;
  FSaveText := '';
  If Assigned(FSaveBytes) Then
    FSaveBytes.Clear;
End;

Procedure TManageFilesPane.KeepSaveBytes(Bytes: TStream);
Begin
  ClearSavePayload;
  If Not Assigned(FSaveBytes) Then
    FSaveBytes := TMemoryStream.Create;
  If Assigned(Bytes) And (Bytes.Size > 0) Then
    Begin
      Bytes.Position := 0;
      FSaveBytes.CopyFrom(Bytes, Bytes.Size);
    End;
  FSaveKind := skBytes;
  FSaveBlockReason := '';
End;

Procedure TManageFilesPane.NotifyCommands;
Begin
  If Assigned(OnCommandsChanged) Then
    OnCommandsChanged(Self);
End;

Procedure TManageFilesPane.HideEditors;
Begin
  ClearRevisionHighlighter;
  If Assigned(FileRevisionEditor) Then
    Begin
      FileRevisionEditor.Highlighter := Nil;
      FileRevisionEditor.Visible := False;
    End;
  If Assigned(FileChangesView) Then
    FileChangesView.Visible := False;
End;

Procedure TManageFilesPane.ShowBlankPane;
Begin
  HideEditors;
  If Assigned(FPreviewPicture) Then
    FPreviewPicture.Clear;
  If Assigned(FileImagePaintBox) Then
    FileImagePaintBox.Visible := False;
  If Assigned(FilePreviewLabel) Then
    FilePreviewLabel.Visible := False;
  If Assigned(FilePreviewPanel) Then
    Begin
      FilePreviewPanel.ParentColor := True;
      FilePreviewPanel.ParentBackground := False;
      FilePreviewPanel.Visible := True;
      FilePreviewPanel.BringToFront;
    End;
End;

Procedure TManageFilesPane.ShowMessagePane(Const MessageText: String);
Begin
  HideEditors;
  If Assigned(FPreviewPicture) Then
    FPreviewPicture.Clear;
  If Assigned(FileImagePaintBox) Then
    FileImagePaintBox.Visible := False;
  If Assigned(FilePreviewLabel) Then
    Begin
      FilePreviewLabel.ParentColor := True;
      If MessageText <> '' Then
        FilePreviewLabel.Caption := MessageText;
      FilePreviewLabel.Visible := True;
    End;
  If Assigned(FilePreviewPanel) Then
    Begin
      FilePreviewPanel.ParentColor := True;
      FilePreviewPanel.ParentBackground := False;
      FilePreviewPanel.Visible := True;
      FilePreviewPanel.BringToFront;
    End;
End;

Procedure TManageFilesPane.ShowImageContent;
Begin
  HideEditors;
  If Assigned(FilePreviewLabel) Then
    FilePreviewLabel.Visible := False;
  If Assigned(FileImagePaintBox) Then
    Begin
      FileImagePaintBox.Visible := True;
      FileImagePaintBox.Invalidate;
    End;
  If Assigned(FilePreviewPanel) Then
    Begin
      FilePreviewPanel.Visible := True;
      FilePreviewPanel.BringToFront;
    End;
End;

Procedure TManageFilesPane.ShowTextPane;
Begin
  If Assigned(FPreviewPicture) Then
    FPreviewPicture.Clear;
  If Assigned(FileImagePaintBox) Then
    FileImagePaintBox.Visible := False;
  If Assigned(FilePreviewLabel) Then
    FilePreviewLabel.Visible := False;
  If Assigned(FilePreviewPanel) Then
    FilePreviewPanel.Visible := False;
  If Assigned(FileChangesView) Then
    FileChangesView.Visible := False;
  If Assigned(FileRevisionEditor) Then
    Begin
      FileRevisionEditor.Visible := True;
      FileRevisionEditor.BringToFront;
    End;
End;

Procedure TManageFilesPane.ShowChangesEditor;
Begin
  If Assigned(FPreviewPicture) Then
    FPreviewPicture.Clear;
  If Assigned(FileImagePaintBox) Then
    FileImagePaintBox.Visible := False;
  If Assigned(FilePreviewLabel) Then
    FilePreviewLabel.Visible := False;
  If Assigned(FilePreviewPanel) Then
    FilePreviewPanel.Visible := False;
  If Assigned(FileRevisionEditor) Then
    FileRevisionEditor.Visible := False;
  If Assigned(FileChangesView) Then
    Begin
      FileChangesView.Visible := True;
      FileChangesView.BringToFront;
    End
  Else
    ShowTextPane;
End;

Procedure TManageFilesPane.ShowStoredText;
Begin
  ShowTextPane;
  If Not Assigned(FileRevisionEditor) Then
    Exit;
  ApplyRevisionHighlighter(FContentPath);
  FileRevisionEditor.Text := FSaveText;
  FileRevisionEditor.CaretY := 1;
  FileRevisionEditor.CaretX := 1;
End;

Procedure TManageFilesPane.ShowStoredDiff;
Begin
  If Not Assigned(FileChangesView) Then
    Begin
      ShowTextPane;
      If Assigned(FileRevisionEditor) Then
        FileRevisionEditor.Text := FDiffText;
      Exit;
    End;
  ShowChangesEditor;
  FileChangesView.SetViewMode(dvmEditorOnly);
  If Not FDiffOk Then
    FileChangesView.LoadPlainText('', '(could not load changes)')
  Else
    FileChangesView.LoadEmbeddedDiff(DisplayFileName(FContentPath), FDiffText, FContentPath);
  FileChangesView.RefreshOverviewGutter;
End;

Procedure TManageFilesPane.ShowChangesLoading;
Begin
  If Not Assigned(FileChangesView) Then
    Begin
      ShowTextPane;
      If Assigned(FileRevisionEditor) Then
        Begin
          ClearRevisionHighlighter;
          FileRevisionEditor.Text := LoadingCaption;
        End;
      Exit;
    End;
  ShowChangesEditor;
  FileChangesView.SetViewMode(dvmEditorOnly);
  FileChangesView.LoadPlainText('', LoadingCaption);
End;

Procedure TManageFilesPane.ClearEditor;
Begin
  ClearRevisionHighlighter;
  ClearSavePayload;
  FTextReady := False;
  FContentSettled := False;
  FRemovedRevision := False;
  FDiffReady := False;
  FDiffPending := False;
  FDiffOk := False;
  FDiffText := '';
  FSaveBlockReason := 'Select a file to save.';
  ShowBlankPane;
  NotifyCommands;
End;

Procedure TManageFilesPane.PaintPreview;
Begin
  If Not Assigned(FileImagePaintBox) Then
    Exit;
  PaintFittedRepositoryImage(FileImagePaintBox.Canvas, FileImagePaintBox.ClientRect, FPreviewPicture);
End;

Function TManageFilesPane.ContentIsImage: Boolean;
Begin
  Result := FileExtensionIsImage(ExtractFileExt(FContentPath));
End;

Function TManageFilesPane.ContentReadsBytes: Boolean;
Begin
  Result := FileExtensionIsLikelyBinary(ExtractFileExt(FContentPath));
End;

Function TManageFilesPane.PathLooksText(Const RelativePath: String): Boolean;
Begin
  Result := Not FileExtensionIsLikelyBinary(ExtractFileExt(RelativePath));
End;

Function TManageFilesPane.FileSelected: Boolean;
Var
  RelativePath: String;
Begin
  Result := SelectedEntryPath(RelativePath);
End;

Function TManageFilesPane.TextPreviewActive: Boolean;
Begin
  Result := FTextReady And (Not FRemovedRevision);
End;

Function TManageFilesPane.CanWriteDisplayedFile: Boolean;
Begin
  Result := (FSaveKind = skText) Or ((FSaveKind = skBytes) And Assigned(FSaveBytes));
End;

Function TManageFilesPane.DisplayedFileStatus: String;
Begin
  If CanWriteDisplayedFile Then
    Result := ''
  Else If FSaveBlockReason <> '' Then
    Result := FSaveBlockReason
  Else
    Result := 'This revision has no file contents to save.';
End;

Function TManageFilesPane.SuggestedSaveName: String;
Begin
  If FContentPath <> '' Then
    Result := DisplayFileName(FContentPath)
  Else
    Result := DisplayFileName(FSelectedPath);
End;

Function TManageFilesPane.SuggestedSaveDirectory: String;
Var
  RelDir, FullDir: String;
Begin
  Result := RepoPath;
  RelDir := ExtractFilePath(StringReplace(FContentPath, '/', PathDelim, [rfReplaceAll]));
  If (RepoPath = '') Or (RelDir = '') Then
    Exit;
  FullDir := IncludeTrailingPathDelimiter(RepoPath) + ExcludeTrailingPathDelimiter(RelDir);
  If DirectoryExists(FullDir) Then
    Result := FullDir;
End;

Function TManageFilesPane.WriteDisplayedFile(Const TargetPath: String; Out ErrorText: String): Boolean;
Var
  Stream: TFileStream;
  Count: Integer;
Begin
  Result := False;
  ErrorText := '';
  If Not CanWriteDisplayedFile Then
    Begin
      ErrorText := DisplayedFileStatus;
      Exit;
    End;
  If TargetPath = '' Then
    Begin
      ErrorText := 'The file name is empty.';
      Exit;
    End;
  Try
    Stream := TFileStream.Create(TargetPath, fmCreate);
    Try
      If FSaveKind = skBytes Then
        Begin
          FSaveBytes.Position := 0;
          If FSaveBytes.Size > 0 Then
            Stream.CopyFrom(FSaveBytes, FSaveBytes.Size);
        End
      Else
        Begin
          Count := Length(FSaveText);
          If Count > 0 Then
            Stream.WriteBuffer(FSaveText[1], Count);
        End;
      Result := True;
    Finally
      Stream.Free;
    End;
  Except
    On E: Exception Do
      ErrorText := E.Message;
  End;
End;

Procedure TManageFilesPane.SetShowChanges(Value: Boolean);
Begin
  FShowChanges := Value;
  If Not TextPreviewActive Then
    Exit;
  If FShowChanges Then
    Begin
      If FDiffReady And (FDiffSha = FSelectedSha) And (FDiffPath = FContentPath) Then
        ShowStoredDiff
      Else If Assigned(OnRequestDiff) Then
        OnRequestDiff(Self)
      Else
        ShowChangesLoading;
    End
  Else
    ShowStoredText;
End;

Procedure TManageFilesPane.FreeTreeEntries;
Var
  Node: TTreeNode;
  Entry: TRepositoryTreeEntry;
Begin
  If Not Assigned(FileTree) Then
    Exit;
  Node := FileTree.Items.GetFirstNode;
  While Assigned(Node) Do
    Begin
      Entry := TRepositoryTreeEntry(Node.Data);
      Node.Data := Nil;
      Entry.Free;
      Node := Node.GetNext;
    End;
  FileTree.Items.Clear;
End;

Procedure TManageFilesPane.ClearForNoRepo;
Begin
  Inc(FFileListToken);
  Inc(FHistoryToken);
  Inc(FContentToken);
  Inc(FDiffToken);
  FSelectedPath := '';
  FSelectedSha := '';
  FContentPath := '';
  ClearCommitObjects;
  ClearEditor;
  FApplying := True;
  Try
    FreeTreeEntries;
  Finally
    FApplying := False;
  End;
End;

Function TManageFilesPane.SelectedEntryPath(Out RelativePath: String): Boolean;
Var
  Entry: TRepositoryTreeEntry;
Begin
  RelativePath := '';
  Result := False;
  If Not Assigned(FileTree) Or Not Assigned(FileTree.Selected) Or (FileTree.Selected.Data = Nil) Then
    Exit;
  Entry := TRepositoryTreeEntry(FileTree.Selected.Data);
  Result := Entry.IsFile And (Entry.RelativePath <> '');
  If Result Then
    RelativePath := Entry.RelativePath;
End;

Function ChildNamed(ParentNode: TTreeNode; Tree: TTreeView; Const Name: String): TTreeNode;
Var
  Node: TTreeNode;
Begin
  If Assigned(ParentNode) Then
    Node := ParentNode.GetFirstChild
  Else
    Node := Tree.Items.GetFirstNode;
  While Assigned(Node) Do
    Begin
      If Node.Text = Name Then
        Exit(Node);
      Node := Node.GetNextSibling;
    End;
  Result := Nil;
End;

Function AddSorted(Tree: TTreeView; ParentNode: TTreeNode; Const Name: String; IsFile, Removed: Boolean;
  Const RelativePath: String): TTreeNode;
Var
  Entry: TRepositoryTreeEntry;
  Sibling, InsertAfter: TTreeNode;
Begin
  Result := ChildNamed(ParentNode, Tree, Name);
  If Assigned(Result) Then
    Begin
      If IsFile And Assigned(Result.Data) Then
        Begin
          TRepositoryTreeEntry(Result.Data).IsFile := True;
          If Not Removed Then
            TRepositoryTreeEntry(Result.Data).Removed := False;
        End;
      Exit;
    End;
  Entry := TRepositoryTreeEntry.Create;
  Entry.RelativePath := RelativePath;
  Entry.IsFile := IsFile;
  Entry.Removed := Removed And IsFile;
  InsertAfter := Nil;
  If Assigned(ParentNode) Then
    Sibling := ParentNode.GetFirstChild
  Else
    Sibling := Tree.Items.GetFirstNode;
  While Assigned(Sibling) Do
    Begin
      If (Not IsFile) And TRepositoryTreeEntry(Sibling.Data).IsFile Then
        Break;
      If (IsFile = TRepositoryTreeEntry(Sibling.Data).IsFile) And (CompareText(Name, Sibling.Text) < 0) Then
        Break;
      InsertAfter := Sibling;
      Sibling := Sibling.GetNextSibling;
    End;
  If Assigned(InsertAfter) Then
    Result := Tree.Items.InsertBehind(InsertAfter, Name)
  Else If Assigned(ParentNode) Then
    Result := Tree.Items.AddChildFirst(ParentNode, Name)
  Else
    Result := Tree.Items.AddFirst(Nil, Name);
  Result.Data := Entry;
End;

Function TManageFilesPane.BeginFileList: Integer;
Begin
  Inc(FFileListToken);
  Inc(FHistoryToken);
  Inc(FContentToken);
  Inc(FDiffToken);
  Result := FFileListToken;
  FSelectedPath := '';
  FSelectedSha := '';
  FContentPath := '';
  ClearCommitObjects;
  ClearEditor;
  If Assigned(FileTree) Then
    Begin
      FApplying := True;
      Try
        FreeTreeEntries;
        FileTree.Items.Add(Nil, '(loading…)');
      Finally
        FApplying := False;
      End;
    End;
End;

Procedure AddTreePath(Tree: TTreeView; Const RelativePath: String; Removed: Boolean);
Var
  PartAt, StartAt: Integer;
  Part, Built: String;
  ParentNode: TTreeNode;
Begin
  ParentNode := Nil;
  Built := '';
  StartAt := 1;
  While StartAt <= Length(RelativePath) Do
    Begin
      PartAt := Pos('/', Copy(RelativePath, StartAt, MaxInt));
      If PartAt = 0 Then
        Begin
          Part := Copy(RelativePath, StartAt, MaxInt);
          AddSorted(Tree, ParentNode, Part, True, Removed, RelativePath);
          Break;
        End;
      Part := Copy(RelativePath, StartAt, PartAt - 1);
      If Built <> '' Then
        Built := Built + '/';
      Built := Built + Part;
      ParentNode := AddSorted(Tree, ParentNode, Part, False, False, Built);
      StartAt := StartAt + PartAt;
    End;
End;

Procedure TManageFilesPane.ApplyFileList(Token: Integer; Paths, RemovedPaths: TStrings; Ok: Boolean);
Var
  I: Integer;
  SavedPath, RelativePath: String;
  Match: TTreeNode;
  Entry: TRepositoryTreeEntry;
  HasTracked, HasRemoved: Boolean;
Begin
  If Token <> FFileListToken Then
    Exit;
  SavedPath := FSelectedPath;
  Inc(FHistoryToken);
  Inc(FContentToken);
  Inc(FDiffToken);
  FSelectedPath := '';
  FSelectedSha := '';
  FContentPath := '';
  ClearCommitObjects;
  ClearEditor;
  FreeTreeEntries;
  If Not Assigned(FileTree) Then
    Exit;
  FApplying := True;
  Try
    FileTree.Items.BeginUpdate;
    Try
      HasTracked := Assigned(Paths) And (Paths.Count > 0);
      HasRemoved := Assigned(RemovedPaths) And (RemovedPaths.Count > 0);
      If Not Ok Then
        FileTree.Items.Add(Nil, '(could not list files)')
      Else If Not HasTracked And Not HasRemoved Then
        FileTree.Items.Add(Nil, '(no files)')
      Else
        Begin
          If HasTracked Then
            For I := 0 To Paths.Count - 1 Do
              Begin
                RelativePath := StringReplace(Paths[I], '\', '/', [rfReplaceAll]);
                AddTreePath(FileTree, RelativePath, False);
              End;
          If HasRemoved Then
            For I := 0 To RemovedPaths.Count - 1 Do
              Begin
                RelativePath := StringReplace(RemovedPaths[I], '\', '/', [rfReplaceAll]);
                AddTreePath(FileTree, RelativePath, True);
              End;
        End;
    Finally
      FileTree.Items.EndUpdate;
    End;
    Match := Nil;
    If SavedPath <> '' Then
      Begin
        Match := FileTree.Items.GetFirstNode;
        While Assigned(Match) Do
          Begin
            Entry := TRepositoryTreeEntry(Match.Data);
            If Assigned(Entry) And Entry.IsFile And (Entry.RelativePath = SavedPath) Then
              Break;
            Match := Match.GetNext;
          End;
      End;
    If Assigned(Match) Then
      Begin
        Match.Selected := True;
        Match.MakeVisible;
      End
    Else
      Begin
        Match := FileTree.Items.GetFirstNode;
        While Assigned(Match) Do
          Begin
            Match.Expand(False);
            Match := Match.GetNextSibling;
          End;
      End;
  Finally
    FApplying := False;
  End;
  If Assigned(Match) Then
    TreeSelectionChanged
  Else
    NotifyCommands;
End;

Function TManageFilesPane.BeginHistory: Integer;
Begin
  Inc(FHistoryToken);
  Inc(FContentToken);
  Inc(FDiffToken);
  Result := FHistoryToken;
  FSelectedSha := '';
  FContentPath := '';
  ClearCommitObjects;
  ClearEditor;
  FSaveBlockReason := 'The file revision is still loading.';
  If FileSelected Then
    ShowMessagePane(LoadingCaption);
  NotifyCommands;
  If Assigned(FileCommitList) Then
    FileCommitList.Items.Add('(loading…)');
End;

Procedure TManageFilesPane.ApplyHistory(Token: Integer; Const Path, CommitLines: String; Ok: Boolean);
Var
  Lines: TStringList;
  I, TabAt, SecondTab, ThirdTab: Integer;
  Line, Sha, WhenText, Subject, HistoricalPath, Rest, DisplayText: String;
  FourthTab: Integer;
  Commit: TRepositoryFileCommit;
Begin
  If (Token <> FHistoryToken) Or (Path <> FSelectedPath) Then
    Exit;
  ClearCommitObjects;
  ClearEditor;
  If Not Assigned(FileCommitList) Then
    Exit;
  If Not Ok Then
    Begin
      FContentSettled := True;
      FSaveBlockReason := 'The commit list could not be loaded.';
      ShowMessagePane('(could not list commits)');
      FileCommitList.Items.Add('(could not list commits)');
      NotifyCommands;
      Exit;
    End;
  Lines := TStringList.Create;
  FApplying := True;
  Try
    Lines.Text := CommitLines;
    For I := 0 To Lines.Count - 1 Do
      Begin
        Line := Lines[I];
        If Line = '' Then
          Continue;
        TabAt := Pos(#9, Line);
        If TabAt <= 1 Then
          Continue;
        Sha := Copy(Line, 1, TabAt - 1);
        SecondTab := Pos(#9, Copy(Line, TabAt + 1, MaxInt));
        If SecondTab = 0 Then
          Continue;
        WhenText := Copy(Line, TabAt + 1, SecondTab - 1);
        ThirdTab := Pos(#9, Copy(Line, TabAt + SecondTab + 1, MaxInt));
        FourthTab := 0;
        Rest := '';
        If ThirdTab = 0 Then
          Begin
            Subject := Copy(Line, TabAt + SecondTab + 1, MaxInt);
            HistoricalPath := Path;
          End
        Else
          Begin
            Subject := Copy(Line, TabAt + SecondTab + 1, ThirdTab - 1);
            Rest := Copy(Line, TabAt + SecondTab + ThirdTab + 1, MaxInt);
            FourthTab := Pos(#9, Rest);
            If FourthTab = 0 Then
              HistoricalPath := Rest
            Else
              HistoricalPath := Copy(Rest, 1, FourthTab - 1);
          End;
        If HistoricalPath = '' Then
          HistoricalPath := Path;
        Commit := TRepositoryFileCommit.Create;
        Commit.Sha := Sha;
        Commit.WhenText := WhenText;
        Commit.Subject := Subject;
        Commit.HistoricalPath := HistoricalPath;
        Commit.Removed := (FourthTab > 0) And (Copy(Rest, FourthTab + 1, MaxInt) = 'D');
        DisplayText := WhenText;
        If Subject <> '' Then
          DisplayText := DisplayText + '  ' + Subject;
        DisplayText := DisplayText + ' (' + Copy(Sha, 1, 7) + ')';
        FileCommitList.Items.AddObject(DisplayText, Commit);
      End;
    If FileCommitList.Items.Count = 0 Then
      Begin
        FContentSettled := True;
        FSaveBlockReason := 'This file has no commits.';
        ShowBlankPane;
        FileCommitList.Items.Add('(no commits)');
      End
    Else
      FileCommitList.ItemIndex := 0;
  Finally
    Lines.Free;
    FApplying := False;
  End;
  If (FileCommitList.ItemIndex >= 0) And Assigned(FileCommitList.Items.Objects[FileCommitList.ItemIndex]) Then
    CommitSelectionChanged
  Else
    NotifyCommands;
End;

Function TManageFilesPane.BeginContent: Integer;
Begin
  Inc(FContentToken);
  Inc(FDiffToken);
  Result := FContentToken;
  FContentSettled := False;
  FTextReady := False;
  FRemovedRevision := False;
  FDiffReady := False;
  FDiffPending := False;
  FDiffOk := False;
  FDiffText := '';
  ClearSavePayload;
  FSaveBlockReason := 'The file revision is still loading.';
  If ContentReadsBytes Then
    ShowMessagePane(LoadingCaption)
  Else If FShowChanges Then
    ShowChangesLoading
  Else
    Begin
      ShowTextPane;
      If Assigned(FileRevisionEditor) Then
        Begin
          ClearRevisionHighlighter;
          FileRevisionEditor.Text := LoadingCaption;
        End;
    End;
  NotifyCommands;
End;

Procedure TManageFilesPane.ApplyContent(Token: Integer; Const HistoricalPath, Sha, Content: String;
  IsBinary, Ok: Boolean);
Begin
  If (Token <> FContentToken) Or (HistoricalPath <> FContentPath) Or (Sha <> FSelectedSha) Then
    Exit;
  FContentSettled := True;
  FTextReady := False;
  FRemovedRevision := False;
  If Not Ok Then
    Begin
      ClearSavePayload;
      FSaveBlockReason := 'This revision could not be loaded.';
      ShowMessagePane('(could not load this revision)');
      NotifyCommands;
      Exit;
    End;
  If IsBinary Then
    Begin
      ClearSavePayload;
      FSaveBlockReason := 'This revision has no file contents to save.';
      ShowMessagePane(BinaryFileCaption);
      NotifyCommands;
      Exit;
    End;
  ClearSavePayload;
  FSaveKind := skText;
  FSaveText := Content;
  FTextReady := True;
  FSaveBlockReason := '';
  If FShowChanges Then
    Begin
      If FDiffReady And (FDiffSha = Sha) And (FDiffPath = HistoricalPath) Then
        ShowStoredDiff
      Else If (Not FDiffPending) And Assigned(OnRequestDiff) Then
        OnRequestDiff(Self)
      Else
        ShowChangesLoading;
    End
  Else
    ShowStoredText;
  NotifyCommands;
End;

Procedure TManageFilesPane.ApplyImage(Token: Integer; Const HistoricalPath, Sha: String; Bytes: TStream; Ok: Boolean;
  Const ErrorText: String);
Begin
  If (Token <> FContentToken) Or (HistoricalPath <> FContentPath) Or (Sha <> FSelectedSha) Then
    Exit;
  FContentSettled := True;
  FTextReady := False;
  FRemovedRevision := False;
  If Assigned(FPreviewPicture) Then
    FPreviewPicture.Clear;
  If Not Ok Then
    Begin
      ClearSavePayload;
      FSaveBlockReason := 'This revision could not be loaded.';
      If ErrorText <> '' Then
        ShowMessagePane(ErrorText)
      Else
        ShowMessagePane('(could not load this revision)');
      NotifyCommands;
      Exit;
    End;
  KeepSaveBytes(Bytes);
  If Not TryLoadRepositoryImage(Bytes, FPreviewPicture) Then
    ShowMessagePane(RepositoryImageUnavailable)
  Else
    ShowImageContent;
  NotifyCommands;
End;

Procedure TManageFilesPane.ApplyBinary(Token: Integer; Const HistoricalPath, Sha: String; Bytes: TStream; Ok: Boolean;
  Const ErrorText: String);
Begin
  If (Token <> FContentToken) Or (HistoricalPath <> FContentPath) Or (Sha <> FSelectedSha) Then
    Exit;
  FContentSettled := True;
  FTextReady := False;
  FRemovedRevision := False;
  If Assigned(FPreviewPicture) Then
    FPreviewPicture.Clear;
  If Not Ok Then
    Begin
      ClearSavePayload;
      FSaveBlockReason := 'This revision could not be loaded.';
      If ErrorText <> '' Then
        ShowMessagePane(ErrorText)
      Else
        ShowMessagePane('(could not load this revision)');
      NotifyCommands;
      Exit;
    End;
  KeepSaveBytes(Bytes);
  ShowMessagePane(BinaryFileCaption);
  NotifyCommands;
End;

Function TManageFilesPane.BeginDiff: Integer;
Begin
  Inc(FDiffToken);
  Result := FDiffToken;
  FDiffPending := True;
  FDiffReady := False;
  FDiffOk := False;
  FDiffText := '';
  FDiffSha := FSelectedSha;
  FDiffPath := FContentPath;
  If FShowChanges And PathLooksText(FContentPath) And ((Not FContentSettled) Or FTextReady) Then
    ShowChangesLoading;
End;

Procedure TManageFilesPane.ApplyDiff(Token: Integer; Const HistoricalPath, Sha, DiffText: String; Ok: Boolean);
Begin
  If (Token <> FDiffToken) Or (HistoricalPath <> FDiffPath) Or (Sha <> FDiffSha) Then
    Exit;
  If (HistoricalPath <> FContentPath) Or (Sha <> FSelectedSha) Then
    Exit;
  FDiffPending := False;
  FDiffText := DiffText;
  FDiffReady := True;
  FDiffOk := Ok;
  If Not FShowChanges Then
    Exit;
  If FContentSettled And (Not FTextReady) Then
    Exit;
  ShowStoredDiff;
End;

Procedure TManageFilesPane.TreeSelectionChanged;
Var
  RelativePath: String;
Begin
  If FApplying Then
    Exit;
  If Not SelectedEntryPath(RelativePath) Then
    Begin
      Inc(FHistoryToken);
      Inc(FContentToken);
      Inc(FDiffToken);
      FSelectedPath := '';
      FSelectedSha := '';
      FContentPath := '';
      ClearCommitObjects;
      ClearEditor;
      Exit;
    End;
  If RelativePath = FSelectedPath Then
    Exit;
  FSelectedPath := RelativePath;
  FSaveBlockReason := 'The file revision is still loading.';
  NotifyCommands;
  If Assigned(OnRequestHistory) Then
    OnRequestHistory(Self);
End;

Procedure TManageFilesPane.CommitSelectionChanged;
Var
  Commit: TRepositoryFileCommit;
Begin
  If FApplying Or Not Assigned(FileCommitList) Then
    Exit;
  If (FileCommitList.ItemIndex < 0) Or (FileCommitList.Items.Objects[FileCommitList.ItemIndex] = Nil) Then
    Begin
      FSelectedSha := '';
      FContentPath := '';
      ClearEditor;
      If FileSelected Then
        Begin
          FContentSettled := True;
          FSaveBlockReason := 'Select a commit to save that version of the file.';
          ShowBlankPane;
          NotifyCommands;
        End;
      Exit;
    End;
  Commit := TRepositoryFileCommit(FileCommitList.Items.Objects[FileCommitList.ItemIndex]);
  FSelectedSha := Commit.Sha;
  FContentPath := Commit.HistoricalPath;
  If Commit.Removed Then
    Begin
      Inc(FContentToken);
      Inc(FDiffToken);
      FContentSettled := True;
      FTextReady := False;
      FRemovedRevision := True;
      FDiffPending := False;
      ClearSavePayload;
      FSaveBlockReason := 'This file was removed in the selected commit.';
      ShowMessagePane(FileRemovedCaption);
      NotifyCommands;
      Exit;
    End;
  If Assigned(OnRequestContent) Then
    OnRequestContent(Self);
  If FShowChanges And PathLooksText(FContentPath) And Assigned(OnRequestDiff) Then
    OnRequestDiff(Self);
End;

Procedure TManageFilesPane.TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
  var DefaultDraw: Boolean);
Begin
  DefaultDraw := True;
  If Not Assigned(Sender) Or Not Assigned(Node) Or Not Assigned(Node.Data) Then
    Exit;
  If Not TRepositoryTreeEntry(Node.Data).Removed Then
    Exit;
  Sender.Canvas.Font.Color := clRed;
  If cdsSelected in State Then
    Sender.Canvas.Font.Color := clRed;
End;

End.
