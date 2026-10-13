Unit ManageRepositoryFiles;

{ Files-tab tree, commit list, revision text, and image preview (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, ComCtrls, StdCtrls, ExtCtrls, Graphics, SynEdit;

Type
  TManageFilesPane = Class
  Private
    FApplying: Boolean;
    FFileListToken: Integer;
    FHistoryToken: Integer;
    FContentToken: Integer;
    FSelectedPath: String;
    FSelectedSha: String;
    FContentPath: String;
    FRevisionHighlighter: TObject;
    FPreviewPicture: TPicture;
    Procedure ClearCommitObjects;
    Procedure ClearRevisionHighlighter;
    Procedure ApplyRevisionHighlighter(Const FileName: String);
    Procedure ShowTextPane;
    Procedure ShowImagePane(ShowImage: Boolean; Const MessageText: String);
    Procedure ClearEditor;
    Procedure FreeTreeEntries;
    Function SelectedEntryPath(Out RelativePath: String): Boolean;
  Public
    FileTree: TTreeView;
    FileCommitList: TListBox;
    FileRevisionEditor: TSynEdit;
    FilePreviewPanel: TPanel;
    FileImagePaintBox: TPaintBox;
    FilePreviewLabel: TLabel;
    RepoPath: String;
    OnRequestHistory: TNotifyEvent;
    OnRequestContent: TNotifyEvent;
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Bind(AFileTree: TTreeView; ACommitList: TListBox; AEditor: TSynEdit; APreviewPanel: TPanel;
      AImagePaint: TPaintBox; APreviewLabel: TLabel);
    Procedure ClearForNoRepo;
    Function BeginFileList: Integer;
    Procedure ApplyFileList(Token: Integer; Paths: TStrings; Ok: Boolean);
    Function BeginHistory: Integer;
    Procedure ApplyHistory(Token: Integer; Const Path, CommitLines: String; Ok: Boolean);
    Function BeginContent: Integer;
    Procedure ApplyContent(Token: Integer; Const HistoricalPath, Sha, Content: String; IsBinary, Ok: Boolean);
    Procedure ApplyImage(Token: Integer; Const HistoricalPath, Sha: String; Bytes: TStream; Ok: Boolean;
      Const ErrorText: String);
    Procedure PaintPreview;
    Function ContentIsImage: Boolean;
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
  End;

  TRepositoryFileCommit = Class
    Sha: String;
    WhenText: String;
    Subject: String;
    HistoricalPath: String;
  End;

Constructor TManageFilesPane.Create;
Begin
  Inherited Create;
  FFileListToken := 0;
  FHistoryToken := 0;
  FContentToken := 0;
  RepoPath := '';
  FPreviewPicture := TPicture.Create;
End;

Destructor TManageFilesPane.Destroy;
Begin
  ClearForNoRepo;
  FreeAndNil(FPreviewPicture);
  Inherited Destroy;
End;

Procedure TManageFilesPane.Bind(AFileTree: TTreeView; ACommitList: TListBox; AEditor: TSynEdit; APreviewPanel: TPanel;
  AImagePaint: TPaintBox; APreviewLabel: TLabel);
Begin
  FileTree := AFileTree;
  FileCommitList := ACommitList;
  FileRevisionEditor := AEditor;
  FilePreviewPanel := APreviewPanel;
  FileImagePaintBox := AImagePaint;
  FilePreviewLabel := APreviewLabel;
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
  If Assigned(FileRevisionEditor) Then
    Begin
      FileRevisionEditor.Visible := True;
      FileRevisionEditor.BringToFront;
    End;
End;

Procedure TManageFilesPane.ShowImagePane(ShowImage: Boolean; Const MessageText: String);
Begin
  ClearRevisionHighlighter;
  If Assigned(FileRevisionEditor) Then
    Begin
      FileRevisionEditor.Highlighter := Nil;
      FileRevisionEditor.Lines.Clear;
      FileRevisionEditor.Visible := False;
    End;
  If Assigned(FilePreviewLabel) Then
    Begin
      If MessageText <> '' Then
        FilePreviewLabel.Caption := MessageText;
      FilePreviewLabel.Visible := Not ShowImage;
    End;
  If Assigned(FileImagePaintBox) Then
    Begin
      FileImagePaintBox.Visible := ShowImage;
      If ShowImage Then
        FileImagePaintBox.Invalidate;
    End;
  If Assigned(FilePreviewPanel) Then
    Begin
      FilePreviewPanel.Visible := True;
      FilePreviewPanel.BringToFront;
    End;
End;

Procedure TManageFilesPane.ClearEditor;
Begin
  ClearRevisionHighlighter;
  ShowTextPane;
  If Assigned(FileRevisionEditor) Then
    FileRevisionEditor.Clear;
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

Function AddSorted(Tree: TTreeView; ParentNode: TTreeNode; Const Name: String; IsFile: Boolean;
  Const RelativePath: String): TTreeNode;
Var
  Entry: TRepositoryTreeEntry;
  Sibling, InsertAfter: TTreeNode;
Begin
  Result := ChildNamed(ParentNode, Tree, Name);
  If Assigned(Result) Then
    Begin
      If IsFile And Assigned(Result.Data) Then
        TRepositoryTreeEntry(Result.Data).IsFile := True;
      Exit;
    End;
  Entry := TRepositoryTreeEntry.Create;
  Entry.RelativePath := RelativePath;
  Entry.IsFile := IsFile;
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
  Result := FFileListToken;
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

Procedure TManageFilesPane.ApplyFileList(Token: Integer; Paths: TStrings; Ok: Boolean);
Var
  I, PartAt, StartAt: Integer;
  SavedPath, RelativePath, Part, Built: String;
  ParentNode, Match: TTreeNode;
  Entry: TRepositoryTreeEntry;
Begin
  If Token <> FFileListToken Then
    Exit;
  SavedPath := FSelectedPath;
  Inc(FHistoryToken);
  Inc(FContentToken);
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
      If Not Ok Then
        FileTree.Items.Add(Nil, '(could not list files)')
      Else If Not Assigned(Paths) Or (Paths.Count = 0) Then
        FileTree.Items.Add(Nil, '(no files)')
      Else
        For I := 0 To Paths.Count - 1 Do
          Begin
            RelativePath := Paths[I];
            ParentNode := Nil;
            Built := '';
            StartAt := 1;
            While StartAt <= Length(RelativePath) Do
              Begin
                PartAt := Pos('/', Copy(RelativePath, StartAt, MaxInt));
                If PartAt = 0 Then
                  Begin
                    Part := Copy(RelativePath, StartAt, MaxInt);
                    AddSorted(FileTree, ParentNode, Part, True, RelativePath);
                    Break;
                  End;
                Part := Copy(RelativePath, StartAt, PartAt - 1);
                If Built <> '' Then
                  Built := Built + '/';
                Built := Built + Part;
                ParentNode := AddSorted(FileTree, ParentNode, Part, False, Built);
                StartAt := StartAt + PartAt;
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
    TreeSelectionChanged;
End;

Function TManageFilesPane.BeginHistory: Integer;
Begin
  Inc(FHistoryToken);
  Inc(FContentToken);
  Result := FHistoryToken;
  FSelectedSha := '';
  FContentPath := '';
  ClearCommitObjects;
  ClearEditor;
  If Assigned(FileCommitList) Then
    FileCommitList.Items.Add('(loading…)');
End;

Procedure TManageFilesPane.ApplyHistory(Token: Integer; Const Path, CommitLines: String; Ok: Boolean);
Var
  Lines: TStringList;
  I, TabAt, SecondTab, ThirdTab: Integer;
  Line, Sha, WhenText, Subject, HistoricalPath, DisplayText: String;
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
      FileCommitList.Items.Add('(could not list commits)');
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
        If ThirdTab = 0 Then
          Begin
            Subject := Copy(Line, TabAt + SecondTab + 1, MaxInt);
            HistoricalPath := Path;
          End
        Else
          Begin
            Subject := Copy(Line, TabAt + SecondTab + 1, ThirdTab - 1);
            HistoricalPath := Copy(Line, TabAt + SecondTab + ThirdTab + 1, MaxInt);
          End;
        If HistoricalPath = '' Then
          HistoricalPath := Path;
        Commit := TRepositoryFileCommit.Create;
        Commit.Sha := Sha;
        Commit.WhenText := WhenText;
        Commit.Subject := Subject;
        Commit.HistoricalPath := HistoricalPath;
        DisplayText := WhenText + '  ' + Copy(Sha, 1, 7);
        If Subject <> '' Then
          DisplayText := DisplayText + '  ' + Subject;
        FileCommitList.Items.AddObject(DisplayText, Commit);
      End;
    If FileCommitList.Items.Count = 0 Then
      FileCommitList.Items.Add('(no commits)')
    Else
      FileCommitList.ItemIndex := 0;
  Finally
    Lines.Free;
    FApplying := False;
  End;
  If (FileCommitList.ItemIndex >= 0) And Assigned(FileCommitList.Items.Objects[FileCommitList.ItemIndex]) Then
    CommitSelectionChanged;
End;

Function TManageFilesPane.BeginContent: Integer;
Begin
  Inc(FContentToken);
  Result := FContentToken;
  ShowTextPane;
  If Assigned(FileRevisionEditor) Then
    Begin
      ClearRevisionHighlighter;
      FileRevisionEditor.Text := '(loading…)';
    End;
End;

Procedure TManageFilesPane.ApplyContent(Token: Integer; Const HistoricalPath, Sha, Content: String;
  IsBinary, Ok: Boolean);
Begin
  If (Token <> FContentToken) Or (HistoricalPath <> FContentPath) Or (Sha <> FSelectedSha) Then
    Exit;
  If Not Assigned(FileRevisionEditor) Then
    Exit;
  ShowTextPane;
  If Not Ok Then
    Begin
      ClearRevisionHighlighter;
      FileRevisionEditor.Text := '(could not load this revision)';
    End
  Else If IsBinary Then
    Begin
      ClearRevisionHighlighter;
      FileRevisionEditor.Text := '(binary file)';
    End
  Else
    Begin
      ApplyRevisionHighlighter(HistoricalPath);
      FileRevisionEditor.Text := Content;
    End;
  FileRevisionEditor.CaretY := 1;
  FileRevisionEditor.CaretX := 1;
End;

Procedure TManageFilesPane.ApplyImage(Token: Integer; Const HistoricalPath, Sha: String; Bytes: TStream; Ok: Boolean;
  Const ErrorText: String);
Begin
  If (Token <> FContentToken) Or (HistoricalPath <> FContentPath) Or (Sha <> FSelectedSha) Then
    Exit;
  If Assigned(FPreviewPicture) Then
    FPreviewPicture.Clear;
  If Not Ok Or Not TryLoadRepositoryImage(Bytes, FPreviewPicture) Then
    Begin
      If Ok Then
        ShowImagePane(False, RepositoryImageUnavailable)
      Else If ErrorText <> '' Then
        ShowImagePane(False, ErrorText)
      Else
        ShowImagePane(False, '(could not load this revision)');
      Exit;
    End;
  ShowImagePane(True, '');
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
      Exit;
    End;
  Commit := TRepositoryFileCommit(FileCommitList.Items.Objects[FileCommitList.ItemIndex]);
  FSelectedSha := Commit.Sha;
  FContentPath := Commit.HistoricalPath;
  If Assigned(OnRequestContent) Then
    OnRequestContent(Self);
End;

End.
