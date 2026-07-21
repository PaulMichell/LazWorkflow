Unit GitDiffView;

{ SynEdit-based diff viewer: staging tree mode (commit dialog) and commit browse
  mode (manage form file list + full-file embedded red/green diffs)
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Types, Controls, Graphics, ExtCtrls, ComCtrls, StdCtrls, Forms,
  Menus, SynEdit, SynEditTypes, SynHighlighterDiff, SynGutter, SynGutterBase,
  SynGutterLineOverview;

Type
  { dvmEditorOnly: full-file red/green SynEdit only (Files tab). }
  TGitDiffViewMode = (dvmStaging, dvmBrowse, dvmEditorOnly);

  TGitDiffRange = Record
    StartLine: Integer; { 1-based inclusive }
    EndLine: Integer;
    Path: String;
    Caption: String;
  End;

  TGitDiffView = Class(TFrame)
    FCaption: TLabel;
    FToolBar: TPanel;
    FBtnStageSel: TButton;
    FBtnUnstageSel: TButton;
    FTreePanel: TPanel;
    FTree: TTreeView;
    FFileList: TListBox;
    FSplitter: TSplitter;
    FEditPanel: TPanel;
    FEdit: TSynEdit;
    FHigh: TSynDiffSyn;
    FPopup: TPopupMenu;
    FMiStage: TMenuItem;
    FMiStageHunk: TMenuItem;
    FMiUnstage: TMenuItem;
    FMiUnstageHunk: TMenuItem;
    FMiSep: TMenuItem;
    FMiSelectHunk: TMenuItem;
    Procedure TreeChange(Sender: TObject; Node: TTreeNode);
    Procedure FileListSelectionChange(Sender: TObject; User: Boolean);
    Procedure BtnStageSelClick(Sender: TObject);
    Procedure BtnUnstageSelClick(Sender: TObject);
    Procedure PopupStageClick(Sender: TObject);
    Procedure PopupUnstageClick(Sender: TObject);
    Procedure PopupStageHunkClick(Sender: TObject);
    Procedure PopupUnstageHunkClick(Sender: TObject);
    Procedure PopupSelectHunkClick(Sender: TObject);
    Procedure EditDblClick(Sender: TObject);
    Procedure EditStatusChange(Sender: TObject; Changes: TSynStatusChanges);
  Private
    FDiffText: String;
    FRepoPath: String;
    FStagedSide: Boolean;
    FMode: TGitDiffViewMode;
    FBrowseSha: String;
    FUpdatingList: Boolean;
    FScrollGeneration: PtrInt;
    FOnStatusChanged: TNotifyEvent;
    FOnSelectionChanged: TNotifyEvent;
    FOverviewGutter: TSynGutterLineOverview;
    FDiffOverviewProvider: TObject; { TGitDiffOverviewProvider – avoid circular iface }
    Procedure ApplyIDEEditorAppearance;
    Procedure ConfigureDiffColors;
    Procedure SetupDiffOverviewGutter;
    Procedure ApplyViewMode;
    Procedure ApplyLanguageHighlighter(Const SourceFileName: String);
    Procedure ApplyDiffHighlighter;
    Procedure CancelPendingScroll;
    Procedure ParseDiffIntoTree(Const DiffText: String);
    Procedure SelectLineRange(StartLine, EndLine: Integer);
    Function NodeRange(Node: TTreeNode): TGitDiffRange;
    Procedure GetSelectionLines(Out FirstLine, LastLine: Integer);
    Function BuildPartialPatch(FirstLine, LastLine: Integer): String;
    Function FindHunkBounds(AtLine: Integer; Out FirstLine, LastLine: Integer): Boolean;
    Function SelectHunkAtLine(AtLine: Integer): Boolean;
    Function CanStageFromPreview: Boolean;
    Function CanUnstageFromPreview: Boolean;
    Procedure UpdateActionEnabled;
    Procedure DoStatusChanged;
    Procedure DoSelectionChanged;
    Procedure EditSpecialLineColors(Sender: TObject; Line: Integer; Var Special: Boolean;
      Var FG, BG: TColor);
    Procedure ClearTreeData;
    Procedure ShowSelectedBrowseFile;
    Procedure ScrollToFirstChangeCentered;
    Procedure DoScrollToFirstChangeAsync(Data: PtrInt);
    Function IsDiffChangeLine(Const Line: String): Boolean;
    Function IsAlive: Boolean;
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure Clear;
    Procedure SetViewMode(Mode: TGitDiffViewMode);
    Procedure LoadDiff(Const Title, DiffText: String);
    { SourceFileName selects an IDE language highlighter when known (e.g. .pas). }
    Procedure LoadPlainText(Const Title, Content: String; Const SourceFileName: String = '');
    { Full-file embedded red/green diff (History / Files tab style). }
    Procedure LoadEmbeddedDiff(Const Title, DiffText: String);
    { Manage form: list files in the commit; editor shows full-file embedded diff. }
    Procedure LoadCommit(Const ARepoPath, Sha, Title: String);
    { RepoPath + StagedSide control partial stage/unstage against the index. }
    Procedure SetStagingContext(Const ARepoPath: String; StagedSide: Boolean);
    Function SelectedPath: String;
    Function StageSelection: Boolean;
    Function UnstageSelection: Boolean;
    Function HasActiveSelection: Boolean;
    Property Tree: TTreeView Read FTree;
    Property FileList: TListBox Read FFileList;
    Property Editor: TSynEdit Read FEdit;
    Property Mode: TGitDiffViewMode Read FMode;
    Property StagedSide: Boolean Read FStagedSide;
    Property OnStatusChanged: TNotifyEvent Read FOnStatusChanged Write FOnStatusChanged;
    Property OnSelectionChanged: TNotifyEvent Read FOnSelectionChanged Write FOnSelectionChanged;
  End;

Implementation

{$R *.lfm}

Uses
  Math, EditorOptionsIntf, EditorSyntaxHighlighterDef, LazEditHighlighter,
  GitService, Dialogs, WorkflowLog;

Type
  PGitDiffRange = ^TGitDiffRange;

  { Right-gutter overview markers: green for added lines, red for removed. }
  TGitDiffOverviewProvider = Class(TSynGutterLineOverviewProvider)
  Private
    FColorAdded: TColor;
    FColorRemoved: TColor;
    FRGBAdded: TColor;
    FRGBRemoved: TColor;
    Procedure SetColorAdded(Const NewColor: TColor);
    Procedure SetColorRemoved(Const NewColor: TColor);
  Protected
    Procedure Paint(Canvas: TCanvas; AClip: TRect; TopOffset: Integer); Override;
  Public
    Constructor Create(AOwner: TComponent); Override;
    Property ColorAdded: TColor Read FColorAdded Write SetColorAdded;
    Property ColorRemoved: TColor Read FColorRemoved Write SetColorRemoved;
  End;

Function LineIsDiffAdded(Const Line: String): Boolean;
Begin
  Result := (Length(Line) > 0) And (Line[1] = '+') And (Copy(Line, 1, 3) <> '+++');
End;

Function LineIsDiffRemoved(Const Line: String): Boolean;
Begin
  Result := (Length(Line) > 0) And (Line[1] = '-') And (Copy(Line, 1, 3) <> '---');
End;

Constructor TGitDiffOverviewProvider.Create(AOwner: TComponent);
Begin
  Inherited Create(AOwner);
  ColorAdded := RGBToColor(76, 175, 80);
  ColorRemoved := RGBToColor(229, 57, 53);
  Priority := 10;
End;

Procedure TGitDiffOverviewProvider.SetColorAdded(Const NewColor: TColor);
Begin
  If FColorAdded = NewColor Then
    Exit;
  FColorAdded := NewColor;
  FRGBAdded := TColor(ColorToRGB(NewColor));
  DoChange(Self);
End;

Procedure TGitDiffOverviewProvider.SetColorRemoved(Const NewColor: TColor);
Begin
  If FColorRemoved = NewColor Then
    Exit;
  FColorRemoved := NewColor;
  FRGBRemoved := TColor(ColorToRGB(NewColor));
  DoChange(Self);
End;

Procedure TGitDiffOverviewProvider.Paint(Canvas: TCanvas; AClip: TRect; TopOffset: Integer);
Var
  LineNo, Y1, Y2, Count, ClipTop, ClipBottom: Integer;
  LineText: String;
  R: TRect;
  IsAdd, IsDel: Boolean;
Begin
  If (SynEdit = Nil) Or (SynEdit.Lines = Nil) Then
    Exit;
  Count := SynEdit.Lines.Count;
  If Count < 1 Then
    Exit;

  ClipTop := AClip.Top - TopOffset;
  ClipBottom := AClip.Bottom - TopOffset;
  { Use the middle third of the overview strip for change markers (IDE-like). }
  R := AClip;
  R.Left := AClip.Left + Max(1, (AClip.Right - AClip.Left) Div 4);
  R.Right := AClip.Right - Max(1, (AClip.Right - AClip.Left) Div 4);

  For LineNo := 1 To Count Do
    Begin
      LineText := SynEdit.Lines[LineNo - 1];
      IsAdd := LineIsDiffAdded(LineText);
      IsDel := LineIsDiffRemoved(LineText);
      If Not (IsAdd Or IsDel) Then
        Continue;

      Y1 := TextLineToPixel(LineNo);
      Y2 := TextLineToPixelEnd(LineNo);
      If Y2 < Y1 Then
        Y2 := Y1;
      If (Y2 < ClipTop) Or (Y1 > ClipBottom) Then
        Continue;

      R.Top := Y1 + TopOffset;
      R.Bottom := Max(Y1 + 1, Y2) + TopOffset + 1;
      If IsAdd And IsDel Then
        Canvas.Brush.Color := FRGBAdded
      Else If IsAdd Then
        Canvas.Brush.Color := FRGBAdded
      Else
        Canvas.Brush.Color := FRGBRemoved;
      Canvas.FillRect(R);
    End;
End;

Constructor TGitDiffView.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FRepoPath := '';
  FBrowseSha := '';
  FStagedSide := False;
  FMode := dvmStaging;
  FUpdatingList := False;
  FScrollGeneration := 0;
  FOverviewGutter := Nil;
  FDiffOverviewProvider := Nil;
  ApplyIDEEditorAppearance;
  ApplyViewMode;
  UpdateActionEnabled;
End;

Destructor TGitDiffView.Destroy;
Begin
  CancelPendingScroll;
  Inherited Destroy;
End;

Function TGitDiffView.IsAlive: Boolean;
Begin
  Result := Not (csDestroying in ComponentState) And Assigned(FEdit) And Assigned(FFileList);
End;

Procedure TGitDiffView.CancelPendingScroll;
Begin
  Inc(FScrollGeneration);
  Application.RemoveAsyncCalls(Self);
End;

Procedure TGitDiffView.ConfigureDiffColors;
Begin
  FHigh.LineAddedAttri.Foreground := RGBToColor(27, 94, 32);
  { Token backgrounds kept none so SpecialLineColors can paint full row width. }
  FHigh.LineAddedAttri.Background := clNone;
  FHigh.LineRemovedAttri.Foreground := RGBToColor(183, 28, 28);
  FHigh.LineRemovedAttri.Background := clNone;
  FHigh.ChunkMarkerAttri.Foreground := RGBToColor(69, 90, 100);
  FHigh.ChunkMarkerAttri.Background := RGBToColor(236, 239, 241);
  FHigh.ChunkNewAttri.Foreground := RGBToColor(46, 125, 50);
  FHigh.ChunkOldAttri.Foreground := RGBToColor(198, 40, 40);
  FHigh.NewFileAttri.Foreground := RGBToColor(27, 94, 32);
  FHigh.NewFileAttri.Background := clNone;
  FHigh.OrigFileAttri.Foreground := RGBToColor(183, 28, 28);
  FHigh.OrigFileAttri.Background := clNone;
  FHigh.LineContextAttri.Foreground := clWindowText;
  FHigh.LineContextAttri.Background := clNone;
  FHigh.SpaceAttri.Background := clNone;
  FHigh.UnknownAttri.Background := clNone;
End;

Procedure TGitDiffView.SetupDiffOverviewGutter;
Var
  I: Integer;
  PageProvider: TSynGutterLOvProviderCurrentPage;
  DiffProvider: TGitDiffOverviewProvider;
Begin
  If Not Assigned(FEdit) Then
    Exit;

  FEdit.RightGutter.Visible := True;
  FOverviewGutter := Nil;
  FDiffOverviewProvider := Nil;
  { Drop any IDE-installed right-gutter parts so we own the overview. }
  For I := FEdit.RightGutter.Parts.Count - 1 DownTo 0 Do
    FEdit.RightGutter.Parts[I].Free;

  FOverviewGutter := TSynGutterLineOverview.Create(FEdit.RightGutter.Parts);
  FOverviewGutter.AutoSize := False;
  FOverviewGutter.Width := 12;
  FOverviewGutter.MarkupInfo.Background := RGBToColor(236, 239, 241);

  { Viewport band (grey); change markers paint above it. }
  PageProvider := TSynGutterLOvProviderCurrentPage.Create(FOverviewGutter.Providers);
  PageProvider.Color := RGBToColor(176, 190, 197);
  PageProvider.Priority := 1;

  DiffProvider := TGitDiffOverviewProvider.Create(FOverviewGutter.Providers);
  DiffProvider.ColorAdded := RGBToColor(76, 175, 80);
  DiffProvider.ColorRemoved := RGBToColor(229, 57, 53);
  DiffProvider.Priority := 20;
  FDiffOverviewProvider := DiffProvider;
End;

Procedure TGitDiffView.ApplyIDEEditorAppearance;
Begin
  If Assigned(IDEEditorOptions) Then
    Begin
      IDEEditorOptions.GetSynEditorSettings(FEdit);
      If Assigned(FHigh) Then
        IDEEditorOptions.GetHighlighterSettings(FHigh);
    End
  Else
    Begin
      FEdit.Font.Size := 10;
      FEdit.Font.Name := 'Courier New';
      FEdit.Font.Pitch := fpFixed;
      FEdit.Font.Quality := fqCleartypeNatural;
    End;

  FEdit.ReadOnly := True;
  FEdit.WantTabs := True;
  FEdit.Options := FEdit.Options - [eoShowSpecialChars];
  FEdit.OnDblClick := @EditDblClick;
  FEdit.OnSpecialLineColors := @EditSpecialLineColors;
  FEdit.UnRegisterStatusChangedHandler(@EditStatusChange);
  FEdit.RegisterStatusChangedHandler(@EditStatusChange, [scSelection, scCaretX, scCaretY]);
  { Overview gutter with red/green change markers (VS Code-style scroll map). }
  SetupDiffOverviewGutter;
End;

Procedure TGitDiffView.ApplyDiffHighlighter;
Begin
  If Not Assigned(FEdit) Then
    Exit;
  If Assigned(FHigh) Then
    Begin
      If Assigned(IDEEditorOptions) Then
        IDEEditorOptions.GetHighlighterSettings(FHigh);
      FEdit.Highlighter := FHigh;
      ConfigureDiffColors;
    End
  Else
    FEdit.Highlighter := Nil;
End;

Procedure TGitDiffView.ApplyLanguageHighlighter(Const SourceFileName: String);
Var
  Ext: String;
  Id: TIdeSyntaxHighlighterID;
  HL: TLazEditCustomHighlighter;
Begin
  If Not Assigned(FEdit) Then
    Exit;
  FEdit.Highlighter := Nil;
  Ext := ExtractFileExt(SourceFileName);
  If (Ext = '') Or (IdeSyntaxHighlighters = Nil) Then
    Exit;
  Id := IdeSyntaxHighlighters.GetIdForFileExtension(Ext);
  If (Id < IdeHighlighterStartId) Or (Id = IdeHighlighterUnknownId) Then
    Exit;
  HL := IdeSyntaxHighlighters.SharedInstances[Id];
  If Not Assigned(HL) Then
    Exit;
  { Shared IDE instance – apply current colour scheme, do not free. }
  If Assigned(IDEEditorOptions) Then
    IDEEditorOptions.GetHighlighterSettings(HL);
  FEdit.Highlighter := HL;
End;

Procedure TGitDiffView.ApplyViewMode;
Begin
  { Files tab hosts Stage Selection on its own button bar below the editor. }
  FToolBar.Visible := FMode = dvmStaging;
  FTree.Visible := FMode = dvmStaging;
  FFileList.Visible := FMode = dvmBrowse;
  FCaption.Visible := FMode = dvmStaging;
  FTreePanel.Visible := FMode <> dvmEditorOnly;
  FSplitter.Visible := FMode <> dvmEditorOnly;
  If FMode = dvmBrowse Then
    FTreePanel.Width := 240
  Else If FMode = dvmStaging Then
    FTreePanel.Width := 220;
  UpdateActionEnabled;
End;

Procedure TGitDiffView.SetViewMode(Mode: TGitDiffViewMode);
Begin
  If FMode = Mode Then
    Begin
      ApplyViewMode;
      Exit;
    End;
  FMode := Mode;
  ApplyViewMode;
End;

Procedure TGitDiffView.SetStagingContext(Const ARepoPath: String; StagedSide: Boolean);
Begin
  FRepoPath := ARepoPath;
  FStagedSide := StagedSide;
  { Do not force dvmStaging – Files tab uses dvmEditorOnly with the same context. }
  UpdateActionEnabled;
End;

Function TGitDiffView.CanStageFromPreview: Boolean;
Begin
  Result := (FRepoPath <> '') And (Trim(FDiffText) <> '') And (Not FStagedSide) And
    ((FMode = dvmStaging) Or (FMode = dvmEditorOnly));
End;

Function TGitDiffView.CanUnstageFromPreview: Boolean;
Begin
  Result := (FRepoPath <> '') And (Trim(FDiffText) <> '') And FStagedSide And
    ((FMode = dvmStaging) Or (FMode = dvmEditorOnly));
End;

Procedure TGitDiffView.UpdateActionEnabled;
Var
  CanStage, CanUnstage, HasSel: Boolean;
Begin
  CanStage := CanStageFromPreview;
  CanUnstage := CanUnstageFromPreview;
  HasSel := HasActiveSelection;
  { Internal toolbar only for classic staging tree mode. }
  FBtnStageSel.Enabled := CanStage And HasSel;
  FBtnUnstageSel.Enabled := CanUnstage And HasSel;
  FBtnStageSel.Visible := FMode = dvmStaging;
  FBtnUnstageSel.Visible := FMode = dvmStaging;
  If Assigned(FMiStage) Then
    Begin
      FMiStage.Enabled := CanStage And HasSel;
      FMiStage.Visible := CanStage Or (FMode = dvmEditorOnly);
    End;
  If Assigned(FMiStageHunk) Then
    Begin
      FMiStageHunk.Enabled := CanStage;
      FMiStageHunk.Visible := CanStage Or (FMode = dvmEditorOnly);
    End;
  If Assigned(FMiUnstage) Then
    Begin
      FMiUnstage.Enabled := CanUnstage And HasSel;
      FMiUnstage.Visible := CanUnstage Or (FMode = dvmEditorOnly);
    End;
  If Assigned(FMiUnstageHunk) Then
    Begin
      FMiUnstageHunk.Enabled := CanUnstage;
      FMiUnstageHunk.Visible := CanUnstage Or (FMode = dvmEditorOnly);
    End;
  If Assigned(FMiSelectHunk) Then
    FMiSelectHunk.Visible := (FMode = dvmStaging) Or (FMode = dvmEditorOnly);
End;

Procedure TGitDiffView.DoStatusChanged;
Begin
  If Assigned(FOnStatusChanged) Then
    FOnStatusChanged(Self);
End;

Procedure TGitDiffView.DoSelectionChanged;
Begin
  If Assigned(FOnSelectionChanged) Then
    FOnSelectionChanged(Self);
End;

Function TGitDiffView.HasActiveSelection: Boolean;
Begin
  Result := Assigned(FEdit) And FEdit.SelAvail;
End;

Procedure TGitDiffView.EditSpecialLineColors(Sender: TObject; Line: Integer;
  Var Special: Boolean; Var FG, BG: TColor);
Var
  LineText: String;
Begin
  Special := False;
  If (Not Assigned(FEdit)) Or (Line < 1) Or (Line > FEdit.Lines.Count) Then
    Exit;
  LineText := FEdit.Lines[Line - 1];
  If LineIsDiffAdded(LineText) Then
    Begin
      Special := True;
      FG := RGBToColor(27, 94, 32);
      BG := RGBToColor(232, 245, 233);
    End
  Else If LineIsDiffRemoved(LineText) Then
    Begin
      Special := True;
      FG := RGBToColor(183, 28, 28);
      BG := RGBToColor(255, 235, 238);
    End
  Else If Copy(LineText, 1, 2) = '@@' Then
    Begin
      Special := True;
      FG := RGBToColor(69, 90, 100);
      BG := RGBToColor(236, 239, 241);
    End;
End;

Procedure TGitDiffView.ClearTreeData;
Var
  Node: TTreeNode;
  Data: PGitDiffRange;
Begin
  Node := FTree.Items.GetFirstNode;
  While Assigned(Node) Do
    Begin
      If Assigned(Node.Data) Then
        Begin
          Data := PGitDiffRange(Node.Data);
          Dispose(Data);
          Node.Data := Nil;
        End;
      Node := Node.GetNext;
    End;
  FTree.Items.Clear;
End;

Procedure TGitDiffView.Clear;
Begin
  CancelPendingScroll;
  FDiffText := '';
  FBrowseSha := '';
  If Assigned(FEdit) Then
    FEdit.Lines.Clear;
  If Assigned(FCaption) Then
    FCaption.Caption := 'Diff';
  ClearTreeData;
  FUpdatingList := True;
  Try
    If Assigned(FFileList) Then
      FFileList.Items.Clear;
  Finally
    FUpdatingList := False;
  End;
  If IsAlive Then
    UpdateActionEnabled;
End;

Function TGitDiffView.NodeRange(Node: TTreeNode): TGitDiffRange;
Begin
  Result.StartLine := 1;
  Result.EndLine := 1;
  Result.Path := '';
  Result.Caption := '';
  If Assigned(Node) And Assigned(Node.Data) Then
    Result := PGitDiffRange(Node.Data)^;
End;

Procedure TGitDiffView.SelectLineRange(StartLine, EndLine: Integer);
Var
  Y1, Y2: Integer;
Begin
  If StartLine < 1 Then
    StartLine := 1;
  If EndLine < StartLine Then
    EndLine := StartLine;
  If EndLine > FEdit.Lines.Count Then
    EndLine := FEdit.Lines.Count;
  If FEdit.Lines.Count = 0 Then
    Exit;

  FEdit.CaretY := StartLine;
  FEdit.TopLine := StartLine;
  Y1 := StartLine;
  Y2 := EndLine;
  FEdit.BlockBegin := Point(1, Y1);
  If Y2 >= FEdit.Lines.Count Then
    FEdit.BlockEnd := Point(Length(FEdit.Lines[Y2 - 1]) + 1, Y2)
  Else
    FEdit.BlockEnd := Point(1, Y2 + 1);
  Try
    FEdit.SetFocus;
  Except
  End;
  UpdateActionEnabled;
End;

Function TGitDiffView.IsDiffChangeLine(Const Line: String): Boolean;
Begin
  Result := LineIsDiffAdded(Line) Or LineIsDiffRemoved(Line);
End;

Procedure TGitDiffView.ScrollToFirstChangeCentered;
Var
  I, Line, Half: Integer;
Begin
  If Not IsAlive Then
    Exit;
  Line := 0;
  For I := 0 To FEdit.Lines.Count - 1 Do
    If IsDiffChangeLine(FEdit.Lines[I]) Then
      Begin
        Line := I + 1;
        Break;
      End;
  If Line < 1 Then
    Begin
      FEdit.TopLine := 1;
      Exit;
    End;
  Half := FEdit.LinesInWindow Div 2;
  If Half < 1 Then
    Half := 12;
  FEdit.CaretY := Line;
  FEdit.TopLine := Max(1, Line - Half);
End;

Procedure TGitDiffView.DoScrollToFirstChangeAsync(Data: PtrInt);
Begin
  { Ignore stale or post-destroy callbacks (project switch / form free). }
  If (Data <> FScrollGeneration) Or Not IsAlive Then
    Exit;
  ScrollToFirstChangeCentered;
End;

Procedure TGitDiffView.GetSelectionLines(Out FirstLine, LastLine: Integer);
Var
  B, E: TPoint;
  R: TGitDiffRange;
Begin
  FirstLine := 0;
  LastLine := 0;
  If FEdit.SelAvail Then
    Begin
      B := FEdit.BlockBegin;
      E := FEdit.BlockEnd;
      FirstLine := B.Y;
      LastLine := E.Y;
      { BlockEnd at col 1 of next line means exclusive end. }
      If (E.X <= 1) And (E.Y > B.Y) Then
        Dec(LastLine);
      If FirstLine > LastLine Then
        Begin
          FirstLine := E.Y;
          LastLine := B.Y;
        End;
    End
  Else If (FMode = dvmStaging) And Assigned(FTree.Selected) Then
    Begin
      R := NodeRange(FTree.Selected);
      FirstLine := R.StartLine;
      LastLine := R.EndLine;
    End
  Else
    Begin
      FirstLine := FEdit.CaretY;
      LastLine := FEdit.CaretY;
    End;
  If FirstLine < 1 Then
    FirstLine := 1;
  If LastLine > FEdit.Lines.Count Then
    LastLine := FEdit.Lines.Count;
End;

Function TGitDiffView.BuildPartialPatch(FirstLine, LastLine: Integer): String;
Var
  Lines, OutLines, FileHeader, HunkBody: TStringList;
  I, LineNo, OldCount, NewCount, OldStart, NewStart: Integer;
  Line, HeaderRest, FilePath: String;
  InHunk, HunkHasChange, FileHasChange: Boolean;
  Selected: Boolean;
  SpacePos: Integer;

  Function LineSelected(ALineNo: Integer): Boolean;
  Begin
    Result := (ALineNo >= FirstLine) And (ALineNo <= LastLine);
  End;

  Procedure FlushHunk;
  Var
    J: Integer;
    NewHeader: String;
  Begin
    If Not InHunk Then
      Exit;
    InHunk := False;
    If Not HunkHasChange Or (HunkBody.Count = 0) Then
      Begin
        HunkBody.Clear;
        Exit;
      End;
    NewHeader := Format('@@ -%d,%d +%d,%d @@', [OldStart, OldCount, NewStart, NewCount]);
    If HeaderRest <> '' Then
      NewHeader := NewHeader + HeaderRest;
    If Not FileHasChange Then
      Begin
        For J := 0 To FileHeader.Count - 1 Do
          OutLines.Add(FileHeader[J]);
        FileHasChange := True;
      End;
    OutLines.Add(NewHeader);
    For J := 0 To HunkBody.Count - 1 Do
      OutLines.Add(HunkBody[J]);
    HunkBody.Clear;
  End;

  Procedure StartHunk(Const HeaderLine: String);
  Var
    S, Part: String;
    C: Integer;
  Begin
    FlushHunk;
    InHunk := True;
    HunkHasChange := False;
    HunkBody.Clear;
    OldCount := 0;
    NewCount := 0;
    OldStart := 1;
    NewStart := 1;
    HeaderRest := '';
    { @@ -oldStart,oldCount +newStart,newCount @@ optional }
    S := HeaderLine;
    If Copy(S, 1, 3) = '@@ ' Then
      Delete(S, 1, 3);
    SpacePos := Pos('@@', S);
    If SpacePos > 0 Then
      Begin
        HeaderRest := Copy(S, SpacePos + 2, MaxInt);
        S := Trim(Copy(S, 1, SpacePos - 1));
      End;
    { S like "-12,3 +14,5" or "-12 +14" }
    C := Pos('+', S);
    If C > 0 Then
      Begin
        Part := Trim(Copy(S, 1, C - 1)); { -12,3 }
        If (Length(Part) > 0) And (Part[1] = '-') Then
          Delete(Part, 1, 1);
        SpacePos := Pos(',', Part);
        If SpacePos > 0 Then
          OldStart := StrToIntDef(Copy(Part, 1, SpacePos - 1), 1)
        Else
          OldStart := StrToIntDef(Part, 1);
        Part := Trim(Copy(S, C + 1, MaxInt));
        SpacePos := Pos(',', Part);
        If SpacePos > 0 Then
          NewStart := StrToIntDef(Copy(Part, 1, SpacePos - 1), 1)
        Else
          NewStart := StrToIntDef(Part, 1);
      End;
  End;

Begin
  Result := '';
  If (FirstLine < 1) Or (LastLine < FirstLine) Or (FEdit.Lines.Count = 0) Then
    Exit;

  Lines := TStringList.Create;
  OutLines := TStringList.Create;
  FileHeader := TStringList.Create;
  HunkBody := TStringList.Create;
  Try
    Lines.Assign(FEdit.Lines);
    InHunk := False;
    HunkHasChange := False;
    FileHasChange := False;
    FilePath := '';

    For I := 0 To Lines.Count - 1 Do
      Begin
        LineNo := I + 1;
        Line := Lines[I];

        If Copy(Line, 1, 11) = 'diff --git ' Then
          Begin
            FlushHunk;
            FileHeader.Clear;
            FileHeader.Add(Line);
            FileHasChange := False;
            FilePath := Trim(Copy(Line, 12, MaxInt));
            If Pos(' b/', FilePath) > 0 Then
              FilePath := Copy(FilePath, Pos(' b/', FilePath) + 3, MaxInt);
          End
        Else If (Copy(Line, 1, 6) = 'index ') Or (Copy(Line, 1, 4) = '--- ') Or
                (Copy(Line, 1, 4) = '+++ ') Or (Copy(Line, 1, 8) = 'new file') Or
                (Copy(Line, 1, 12) = 'deleted file') Or (Copy(Line, 1, 8) = 'old mode') Or
                (Copy(Line, 1, 8) = 'new mode') Or (Copy(Line, 1, 10) = 'similarity') Or
                (Copy(Line, 1, 7) = 'rename ') Then
          Begin
            FlushHunk;
            FileHeader.Add(Line);
          End
        Else If Copy(Line, 1, 2) = '@@' Then
          StartHunk(Line)
        Else If InHunk Then
          Begin
            Selected := LineSelected(LineNo);
            If (Length(Line) = 0) Or (Line[1] = ' ') Then
              Begin
                HunkBody.Add(Line);
                Inc(OldCount);
                Inc(NewCount);
              End
            Else If (Line[1] = '-') And (Copy(Line, 1, 3) <> '---') Then
              Begin
                If Selected Then
                  Begin
                    HunkBody.Add(Line);
                    Inc(OldCount);
                    HunkHasChange := True;
                  End
                Else
                  Begin
                    { Unselected deletion stays in both sides as context. }
                    HunkBody.Add(' ' + Copy(Line, 2, MaxInt));
                    Inc(OldCount);
                    Inc(NewCount);
                  End;
              End
            Else If (Line[1] = '+') And (Copy(Line, 1, 3) <> '+++') Then
              Begin
                If Selected Then
                  Begin
                    HunkBody.Add(Line);
                    Inc(NewCount);
                    HunkHasChange := True;
                  End;
                { Unselected addition omitted from index-side patch. }
              End
            Else If Line[1] = '\' Then
              HunkBody.Add(Line) { \ No newline at end of file }
            Else
              Begin
                HunkBody.Add(Line);
                Inc(OldCount);
                Inc(NewCount);
              End;
          End;
      End;
    FlushHunk;

    If OutLines.Count = 0 Then
      Exit;
    Result := OutLines.Text;
  Finally
    HunkBody.Free;
    FileHeader.Free;
    OutLines.Free;
    Lines.Free;
  End;
End;

Function TGitDiffView.FindHunkBounds(AtLine: Integer; Out FirstLine, LastLine: Integer): Boolean;
Var
  I, Count: Integer;
  Line: String;
Begin
  Result := False;
  FirstLine := 0;
  LastLine := 0;
  If Not Assigned(FEdit) Then
    Exit;
  Count := FEdit.Lines.Count;
  If (AtLine < 1) Or (AtLine > Count) Then
    Exit;
  { Walk up to the hunk header (@@). }
  I := AtLine;
  While I >= 1 Do
    Begin
      Line := FEdit.Lines[I - 1];
      If Copy(Line, 1, 2) = '@@' Then
        Begin
          FirstLine := I;
          Break;
        End;
      If Copy(Line, 1, 11) = 'diff --git ' Then
        Exit; { left the current file section without a hunk }
      Dec(I);
    End;
  If FirstLine < 1 Then
    Exit;
  { Walk down to the next hunk or file header. }
  LastLine := Count;
  For I := FirstLine + 1 To Count Do
    Begin
      Line := FEdit.Lines[I - 1];
      If (Copy(Line, 1, 2) = '@@') Or (Copy(Line, 1, 11) = 'diff --git ') Then
        Begin
          LastLine := I - 1;
          Break;
        End;
    End;
  Result := LastLine >= FirstLine;
End;

Function TGitDiffView.SelectHunkAtLine(AtLine: Integer): Boolean;
Var
  FirstLine, LastLine: Integer;
Begin
  Result := FindHunkBounds(AtLine, FirstLine, LastLine);
  If Result Then
    SelectLineRange(FirstLine, LastLine);
End;

Function TGitDiffView.StageSelection: Boolean;
Var
  FirstLine, LastLine: Integer;
  Patch: String;
Begin
  Result := False;
  If Not CanStageFromPreview Or Not Assigned(GitClient) Then
    Exit;
  GetSelectionLines(FirstLine, LastLine);
  If FirstLine < 1 Then
    Begin
      { No selection – stage the hunk under the caret. }
      If Not FindHunkBounds(FEdit.CaretY, FirstLine, LastLine) Then
        Begin
          MessageDlg('Select lines to stage, or place the caret in a change hunk.',
            mtInformation, [mbOK], 0);
          Exit;
        End;
      SelectLineRange(FirstLine, LastLine);
    End;
  Patch := BuildPartialPatch(FirstLine, LastLine);
  If Trim(Patch) = '' Then
    Begin
      MessageDlg('Nothing to stage in the current selection. Select added/removed lines (red/green), or a whole hunk.',
        mtInformation, [mbOK], 0);
      Exit;
    End;
  GitClient.RepoPath := FRepoPath;
  Result := GitClient.ApplyPatchToIndex(Patch, False);
  If Result Then
    Begin
      WorkflowLogger.Info('GitDiff', 'Staged selection in ' + FRepoPath);
      DoStatusChanged;
    End
  Else
    MessageDlg('Stage selection failed: ' + GitClient.LastError, mtError, [mbOK], 0);
End;

Function TGitDiffView.UnstageSelection: Boolean;
Var
  FirstLine, LastLine: Integer;
  Patch: String;
Begin
  Result := False;
  If Not CanUnstageFromPreview Or Not Assigned(GitClient) Then
    Exit;
  GetSelectionLines(FirstLine, LastLine);
  If FirstLine < 1 Then
    Begin
      If Not FindHunkBounds(FEdit.CaretY, FirstLine, LastLine) Then
        Begin
          MessageDlg('Select lines to unstage, or place the caret in a change hunk.',
            mtInformation, [mbOK], 0);
          Exit;
        End;
      SelectLineRange(FirstLine, LastLine);
    End;
  Patch := BuildPartialPatch(FirstLine, LastLine);
  If Trim(Patch) = '' Then
    Begin
      MessageDlg('Nothing to unstage in the current selection. Select added/removed lines (red/green), or a whole hunk.',
        mtInformation, [mbOK], 0);
      Exit;
    End;
  GitClient.RepoPath := FRepoPath;
  Result := GitClient.ApplyPatchToIndex(Patch, True);
  If Result Then
    Begin
      WorkflowLogger.Info('GitDiff', 'Unstaged selection in ' + FRepoPath);
      DoStatusChanged;
    End
  Else
    MessageDlg('Unstage selection failed: ' + GitClient.LastError, mtError, [mbOK], 0);
End;

Procedure TGitDiffView.BtnStageSelClick(Sender: TObject);
Begin
  StageSelection;
End;

Procedure TGitDiffView.BtnUnstageSelClick(Sender: TObject);
Begin
  UnstageSelection;
End;

Procedure TGitDiffView.PopupStageClick(Sender: TObject);
Begin
  StageSelection;
End;

Procedure TGitDiffView.PopupUnstageClick(Sender: TObject);
Begin
  UnstageSelection;
End;

Procedure TGitDiffView.PopupStageHunkClick(Sender: TObject);
Begin
  If SelectHunkAtLine(FEdit.CaretY) Then
    StageSelection
  Else
    MessageDlg('Place the caret inside a change hunk (between @@ markers).', mtInformation, [mbOK], 0);
End;

Procedure TGitDiffView.PopupUnstageHunkClick(Sender: TObject);
Begin
  If SelectHunkAtLine(FEdit.CaretY) Then
    UnstageSelection
  Else
    MessageDlg('Place the caret inside a change hunk (between @@ markers).', mtInformation, [mbOK], 0);
End;

Procedure TGitDiffView.PopupSelectHunkClick(Sender: TObject);
Begin
  If Not SelectHunkAtLine(FEdit.CaretY) Then
    MessageDlg('Place the caret inside a change hunk (between @@ markers).', mtInformation, [mbOK], 0);
End;

Procedure TGitDiffView.EditDblClick(Sender: TObject);
Begin
  { Double-click a change line to select its whole hunk for stage/unstage. }
  If (FMode = dvmEditorOnly) Or (FMode = dvmStaging) Then
    SelectHunkAtLine(FEdit.CaretY);
End;

Procedure TGitDiffView.EditStatusChange(Sender: TObject; Changes: TSynStatusChanges);
Begin
  If (scSelection in Changes) Or (scCaretY in Changes) Then
    Begin
      UpdateActionEnabled;
      If scSelection in Changes Then
        DoSelectionChanged;
    End;
End;

Procedure TGitDiffView.ParseDiffIntoTree(Const DiffText: String);
Var
  Lines: TStringList;
  I, LineNo: Integer;
  Line, Path: String;
  Root, FileNode, HunkNode, LineNode: TTreeNode;
  FileRange, HunkRange, LineRange: PGitDiffRange;
  InFile: Boolean;

  Procedure CloseHunk;
  Begin
    If Assigned(HunkNode) And Assigned(HunkNode.Data) Then
      PGitDiffRange(HunkNode.Data)^.EndLine := LineNo - 1;
    HunkNode := Nil;
  End;

  Procedure CloseFile;
  Begin
    CloseHunk;
    If Assigned(FileNode) And Assigned(FileNode.Data) Then
      PGitDiffRange(FileNode.Data)^.EndLine := LineNo - 1;
    FileNode := Nil;
  End;

  Function NewRange(AStart: Integer; Const APath, ACaption: String): PGitDiffRange;
  Begin
    New(Result);
    Result^.StartLine := AStart;
    Result^.EndLine := AStart;
    Result^.Path := APath;
    Result^.Caption := ACaption;
  End;

Begin
  FTree.Items.BeginUpdate;
  Try
    ClearTreeData;
    FDiffText := DiffText;
    FEdit.Lines.Text := DiffText;

    Lines := TStringList.Create;
    Try
      Lines.Text := DiffText;
      Root := FTree.Items.Add(Nil, 'Diff');
      FileRange := NewRange(1, '', 'All');
      FileRange^.EndLine := Lines.Count;
      Root.Data := FileRange;

      FileNode := Nil;
      HunkNode := Nil;
      Path := '';
      InFile := False;

      For I := 0 To Lines.Count - 1 Do
        Begin
          LineNo := I + 1;
          Line := Lines[I];

          If (Copy(Line, 1, 11) = 'diff --git ') Or (Copy(Line, 1, 4) = '--- ') Or
             ((Copy(Line, 1, 4) = '+++ ') And Not InFile) Then
            Begin
              If Copy(Line, 1, 11) = 'diff --git ' Then
                Begin
                  CloseFile;
                  Path := Trim(Copy(Line, 12, MaxInt));
                  If Pos(' b/', Path) > 0 Then
                    Path := Copy(Path, Pos(' b/', Path) + 3, MaxInt)
                  Else If Pos(' ', Path) > 0 Then
                    Path := Copy(Path, Pos(' ', Path) + 1, MaxInt);
                  If (Length(Path) > 2) And (Copy(Path, 1, 2) = 'a/') Then
                    Path := Copy(Path, 3, MaxInt);
                  FileRange := NewRange(LineNo, Path, Path);
                  FileNode := FTree.Items.AddChild(Root, Path);
                  FileNode.Data := FileRange;
                  InFile := True;
                  HunkNode := Nil;
                End
              Else If Copy(Line, 1, 6) = '+++ b/' Then
                Begin
                  Path := Copy(Line, 7, MaxInt);
                  If Assigned(FileNode) Then
                    Begin
                      FileNode.Text := Path;
                      If Assigned(FileNode.Data) Then
                        PGitDiffRange(FileNode.Data)^.Path := Path;
                    End
                  Else
                    Begin
                      FileRange := NewRange(LineNo, Path, Path);
                      FileNode := FTree.Items.AddChild(Root, Path);
                      FileNode.Data := FileRange;
                      InFile := True;
                    End;
                End;
            End
          Else If Copy(Line, 1, 2) = '@@' Then
            Begin
              CloseHunk;
              If Not Assigned(FileNode) Then
                Begin
                  FileRange := NewRange(1, '', 'Changes');
                  FileNode := FTree.Items.AddChild(Root, 'Changes');
                  FileNode.Data := FileRange;
                End;
              HunkRange := NewRange(LineNo, Path, Line);
              HunkNode := FTree.Items.AddChild(FileNode, Line);
              HunkNode.Data := HunkRange;
            End
          Else If Assigned(HunkNode) And ((Copy(Line, 1, 1) = '+') Or (Copy(Line, 1, 1) = '-')) And
                  (Copy(Line, 1, 3) <> '+++') And (Copy(Line, 1, 3) <> '---') Then
            Begin
              LineRange := NewRange(LineNo, Path, Line);
              LineRange^.EndLine := LineNo;
              If Line[1] = '+' Then
                LineNode := FTree.Items.AddChild(HunkNode, '  + ' + Copy(Line, 2, MaxInt))
              Else
                LineNode := FTree.Items.AddChild(HunkNode, '  − ' + Copy(Line, 2, MaxInt));
              LineNode.Data := LineRange;
            End;
        End;

      CloseFile;
      If Assigned(Root.Data) Then
        PGitDiffRange(Root.Data)^.EndLine := Lines.Count;
      Root.Expand(False);
      If Assigned(Root.GetFirstChild) Then
        Root.GetFirstChild.Expand(False);
    Finally
      Lines.Free;
    End;
  Finally
    FTree.Items.EndUpdate;
  End;
  UpdateActionEnabled;
End;

Procedure TGitDiffView.TreeChange(Sender: TObject; Node: TTreeNode);
Var
  R: TGitDiffRange;
Begin
  If Not Assigned(Node) Then
    Exit;
  R := NodeRange(Node);
  If R.StartLine > 0 Then
    SelectLineRange(R.StartLine, R.EndLine);
End;

Procedure TGitDiffView.ShowSelectedBrowseFile;
Var
  Path, DiffText: String;
  ExpectedSha: String;
Begin
  If (FMode <> dvmBrowse) Or Not IsAlive Then
    Exit;
  CancelPendingScroll;
  FEdit.Lines.Clear;
  FDiffText := '';
  If (FFileList.ItemIndex < 0) Or (FFileList.ItemIndex >= FFileList.Items.Count) Then
    Begin
      FEdit.Lines.Text := '(select a file)';
      UpdateActionEnabled;
      Exit;
    End;
  Path := FFileList.Items[FFileList.ItemIndex];
  If (FRepoPath = '') Or (FBrowseSha = '') Or Not Assigned(GitClient) Then
    Begin
      FEdit.Lines.Text := '(no repository)';
      UpdateActionEnabled;
      Exit;
    End;

  ExpectedSha := FBrowseSha;
  GitClient.RepoPath := FRepoPath;
  If Not GitClient.ShowCommitPathDiff(FBrowseSha, Path, DiffText) Then
    Begin
      If Not IsAlive Or (FBrowseSha <> ExpectedSha) Then
        Exit;
      FEdit.Highlighter := Nil;
      FEdit.Lines.Text := 'Could not load diff for ' + Path + LineEnding + GitClient.LastError;
      UpdateActionEnabled;
      Exit;
    End;

  { Repo/form may have been rebound while git ran (project switch). }
  If Not IsAlive Or (FBrowseSha <> ExpectedSha) Or (FMode <> dvmBrowse) Then
    Exit;

  ApplyIDEEditorAppearance;
  FDiffText := DiffText;
  If Trim(DiffText) = '' Then
    Begin
      FEdit.Highlighter := Nil;
      FEdit.Lines.Text := '(no textual diff for ' + Path + ')';
    End
  Else
    Begin
      FEdit.Highlighter := FHigh;
      ConfigureDiffColors;
      FEdit.Lines.Text := DiffText;
      { Defer centre scroll until layout knows LinesInWindow. }
      Inc(FScrollGeneration);
      Application.QueueAsyncCall(@DoScrollToFirstChangeAsync, FScrollGeneration);
    End;
  UpdateActionEnabled;
End;

Procedure TGitDiffView.FileListSelectionChange(Sender: TObject; User: Boolean);
Begin
  If FUpdatingList Or Not IsAlive Then
    Exit;
  ShowSelectedBrowseFile;
End;

Procedure TGitDiffView.LoadEmbeddedDiff(Const Title, DiffText: String);
Begin
  If Not IsAlive Then
    Exit;
  SetViewMode(dvmEditorOnly);
  CancelPendingScroll;
  If Title <> '' Then
    FCaption.Caption := Title;
  ApplyIDEEditorAppearance;
  ApplyDiffHighlighter;
  FDiffText := DiffText;
  If Trim(DiffText) = '' Then
    Begin
      FEdit.Highlighter := Nil;
      FEdit.Lines.Text := '(no textual diff)';
      UpdateActionEnabled;
      Exit;
    End;
  FEdit.Lines.Text := DiffText;
  Inc(FScrollGeneration);
  Application.QueueAsyncCall(@DoScrollToFirstChangeAsync, FScrollGeneration);
  UpdateActionEnabled;
End;

Procedure TGitDiffView.LoadDiff(Const Title, DiffText: String);
Begin
  SetViewMode(dvmStaging);
  If Title <> '' Then
    FCaption.Caption := Title
  Else
    FCaption.Caption := 'Diff';
  ApplyIDEEditorAppearance;
  If Trim(DiffText) = '' Then
    Begin
      Clear;
      FEdit.Lines.Text := '(no textual diff)';
      UpdateActionEnabled;
      Exit;
    End;
  ParseDiffIntoTree(DiffText);
  ApplyDiffHighlighter;
  UpdateActionEnabled;
End;

Procedure TGitDiffView.LoadPlainText(Const Title, Content: String; Const SourceFileName: String);
Begin
  Clear;
  If Title <> '' Then
    FCaption.Caption := Title;
  { Preserve editor-only mode when used from the Files tab. }
  If FMode = dvmEditorOnly Then
    ApplyViewMode;
  ApplyIDEEditorAppearance;
  FDiffText := '';
  { Prefer IDE language highlighter for known types (e.g. FreePascal for .pas). }
  If SourceFileName <> '' Then
    ApplyLanguageHighlighter(SourceFileName)
  Else
    FEdit.Highlighter := Nil;
  FEdit.Lines.Text := Content;
  UpdateActionEnabled;
End;

Procedure TGitDiffView.LoadCommit(Const ARepoPath, Sha, Title: String);
Var
  Paths: TStringList;
  I: Integer;
  ExpectedSha: String;
Begin
  If Not IsAlive Then
    Exit;
  SetViewMode(dvmBrowse);
  Clear;
  FRepoPath := ARepoPath;
  FBrowseSha := Sha;
  ExpectedSha := Sha;
  If Title <> '' Then
    FCaption.Caption := Title
  Else
    FCaption.Caption := 'Commit ' + Copy(Sha, 1, 7);
  ApplyIDEEditorAppearance;

  If (ARepoPath = '') Or (Sha = '') Or Not Assigned(GitClient) Then
    Begin
      FEdit.Highlighter := Nil;
      FEdit.Lines.Text := '(no commit selected)';
      Exit;
    End;

  GitClient.RepoPath := ARepoPath;
  Paths := Nil;
  If Not GitClient.ListCommitPaths(Sha, Paths) Then
    Begin
      If IsAlive And (FBrowseSha = ExpectedSha) Then
        Begin
          FEdit.Highlighter := Nil;
          FEdit.Lines.Text := 'Could not list commit files: ' + GitClient.LastError;
        End;
      Paths.Free;
      Exit;
    End;

  If Not IsAlive Or (FBrowseSha <> ExpectedSha) Then
    Begin
      Paths.Free;
      Exit;
    End;

  FUpdatingList := True;
  Try
    For I := 0 To Paths.Count - 1 Do
      FFileList.Items.Add(Paths[I]);
    If FFileList.Items.Count > 0 Then
      FFileList.ItemIndex := 0;
  Finally
    FUpdatingList := False;
    Paths.Free;
  End;

  If Not IsAlive Or (FBrowseSha <> ExpectedSha) Then
    Exit;

  If FFileList.Items.Count = 0 Then
    Begin
      FEdit.Highlighter := Nil;
      FEdit.Lines.Text := '(no files changed in this commit)';
      Exit;
    End;

  ShowSelectedBrowseFile;
End;

Function TGitDiffView.SelectedPath: String;
Var
  Node: TTreeNode;
  R: TGitDiffRange;
Begin
  Result := '';
  If FMode = dvmBrowse Then
    Begin
      If (FFileList.ItemIndex >= 0) And (FFileList.ItemIndex < FFileList.Items.Count) Then
        Result := FFileList.Items[FFileList.ItemIndex];
      Exit;
    End;
  Node := FTree.Selected;
  While Assigned(Node) Do
    Begin
      R := NodeRange(Node);
      If R.Path <> '' Then
        Begin
          Result := R.Path;
          Exit;
        End;
      Node := Node.Parent;
    End;
End;

Initialization
  RegisterClass(TGitDiffView);

End.
