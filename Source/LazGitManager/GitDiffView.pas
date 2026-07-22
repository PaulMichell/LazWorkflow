Unit GitDiffView;

{ SynEdit-based diff viewer: staging tree mode, commit browse, Files tab preview
  with mixed Diff+language highlighting, and image/binary previews
  (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. Diff staging, browse, mixed
  highlighter, overview gutter, and binary/image preview form one UI surface.
  Reviewed 2026-07: no clean sibling-unit split without splitting the frame. }

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
    FPreviewPanel: TPanel;
    FBinaryLabel: TLabel;
    FImagePaintBox: TPaintBox;
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
    Procedure ImagePaintBoxPaint(Sender: TObject);
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
    FOwnedLangHigh: TObject; { TLazEditCustomHighlighter, private instance }
    FMixedHigh: TObject; { TGitMixedDiffHighlighter, owned by Self }
    FPreviewPicture: TPicture;
    FAppearanceReady: Boolean;
    FSelectedLines: TFPList; { 1-based line numbers (PtrInt) for Files multi-select }
    Procedure ApplyIDEEditorAppearance;
    Procedure ApplyEditorSelectionPolicy;
    Procedure ConfigureDiffColors(DiffHL: TSynDiffSyn);
    Procedure SetupDiffOverviewGutter;
    Procedure EnsureDiffOverviewGutter;
    Procedure ScheduleOverviewRefresh;
    Procedure DoRefreshOverviewAsync(Data: PtrInt);
    Procedure ApplyViewMode;
    Procedure ClearLineSelection(NotifyChange: Boolean = True);
    Function IsLineSelected(LineNo: Integer): Boolean;
    Function SelectedLineCount: Integer;
    Function SelectedLineBounds(Out FirstLine, LastLine: Integer): Boolean;
    Procedure ToggleLineSelection(LineNo: Integer);
    Procedure SelectChangeLinesInRange(StartLine, EndLine: Integer);
    Procedure FreeOwnedLanguageHighlighter;
    Procedure ApplyLanguageHighlighter(Const SourceFileName: String);
    Procedure ApplyDiffHighlighter;
    Procedure ApplyMixedDiffHighlighter(Const SourceFileName: String);
    Function CreateOwnedLanguageHighlighter(Const SourceFileName: String): TObject;
    Procedure ShowEditorPane;
    Procedure ShowBinaryMessage(Const TitleText: String);
    Function TryShowImageFromStream(Const TitleText: String; Stream: TStream): Boolean;
    Function TryShowBinaryOrImage(Const TitleText, RelPath: String; Const Sha: String;
      StagedSide: Boolean): Boolean;
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
    Procedure EditMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
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
    { Full-file embedded red/green diff; SourceFileName enables language HL on context lines. }
    Procedure LoadEmbeddedDiff(Const Title, DiffText: String; Const SourceFileName: String = '');
    { Image preview or binary notice; returns True when handled (no text editor content). }
    Function LoadBinaryOrImagePreview(Const Title, RelPath: String; Const Sha: String = '';
      StagedSide: Boolean = False): Boolean;
    { Manage form: list files in the commit; editor shows full-file embedded diff. }
    Procedure LoadCommit(Const ARepoPath, Sha, Title: String);
    { RepoPath + StagedSide control partial stage/unstage against the index. }
    Procedure SetStagingContext(Const ARepoPath: String; StagedSide: Boolean);
    Function SelectedPath: String;
    Function StageSelection: Boolean;
    Function UnstageSelection: Boolean;
    Function HasActiveSelection: Boolean;
    { Reassert right overview gutter size/visibility (e.g. after notebook page show). }
    Procedure RefreshOverviewGutter;
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
  LazEditTextAttributes, SynHighlighterPas, SynHighlighterXML, SynHighlighterLFM,
  GitService, Dialogs, WorkflowLog;

Type
  PGitDiffRange = ^TGitDiffRange;

  { Real TSynDiffSyn so SynEdit fold/markup stay valid; language HL only on context lines. }
  TGitMixedDiffHighlighter = Class(TSynDiffSyn)
  Private
    FLang: TLazEditCustomHighlighter; { not owned }
    FContextMode: Boolean;
    FPrefixDone: Boolean;
    FAtEol: Boolean;
    FPrefixLen: Integer;
    FPrefixStr: String;
  Public
    Procedure SetLanguageBackend(ALang: TLazEditCustomHighlighter);
    Procedure InitForScanningLine; Override;
    Procedure Next; Override;
    Function GetEol: Boolean; Override;
    Function GetToken: String; Override;
    Function GetTokenPos: Integer; Override;
    Function GetTokenKind: Integer; Override;
    Procedure GetTokenEx(Out TokenStart: PChar; Out TokenLength: Integer); Override;
    Function GetTokenAttribute: TLazEditTextAttribute; Override;
  End;

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

Function LineIsDiffContext(Const Line: String): Boolean;
Begin
  Result := (Line = '') Or ((Length(Line) > 0) And (Line[1] = ' '));
End;

Function NormalizeExt(Const Ext: String): String;
Begin
  Result := LowerCase(Ext);
  If (Result <> '') And (Result[1] <> '.') Then
    Result := '.' + Result;
End;

Function FileExtensionIsImage(Const Ext: String): Boolean;
Var
  E: String;
Begin
  E := NormalizeExt(Ext);
  Result := (E = '.png') Or (E = '.jpg') Or (E = '.jpeg') Or (E = '.gif') Or
    (E = '.bmp') Or (E = '.ico') Or (E = '.xpm') Or (E = '.tif') Or (E = '.tiff') Or
    (E = '.pbm') Or (E = '.pgm') Or (E = '.ppm');
End;

Function FileExtensionIsLikelyBinary(Const Ext: String): Boolean;
Var
  E: String;
Begin
  E := NormalizeExt(Ext);
  If FileExtensionIsImage(E) Then
    Exit(True);
  Result := (E = '.exe') Or (E = '.dll') Or (E = '.so') Or (E = '.o') Or (E = '.a') Or
    (E = '.obj') Or (E = '.lib') Or (E = '.zip') Or (E = '.gz') Or (E = '.7z') Or
    (E = '.rar') Or (E = '.pdf') Or (E = '.woff') Or (E = '.woff2') Or (E = '.ttf') Or
    (E = '.otf') Or (E = '.eot') Or (E = '.class') Or (E = '.pyc') Or (E = '.pyo') Or
    (E = '.db') Or (E = '.sqlite') Or (E = '.bin') Or (E = '.dat') Or (E = '.wasm') Or
    (E = '.res') Or (E = '.rsm') Or (E = '.ppu') Or (E = '.compiled');
End;

Function DiffTextLooksBinary(Const DiffText: String): Boolean;
Var
  S: String;
Begin
  S := LowerCase(DiffText);
  Result := (Pos('binary files', S) > 0) And (Pos('differ', S) > 0);
End;

Procedure TGitMixedDiffHighlighter.SetLanguageBackend(ALang: TLazEditCustomHighlighter);
Begin
  FLang := ALang;
  FContextMode := False;
End;

Procedure TGitMixedDiffHighlighter.InitForScanningLine;
Var
  LineText, Body: String;
Begin
  { Always run Diff init first so fold/range state stays consistent. Skipping this
    left fRange stale and caused access violations on subsequent lines. }
  FContextMode := False;
  FPrefixDone := True;
  FPrefixLen := 0;
  FPrefixStr := '';
  FAtEol := False;
  Inherited;

  If Not Assigned(FLang) Then
    Exit;
  LineText := CurrentLineText;
  If Not LineIsDiffContext(LineText) Then
    Exit;

  Try
    If (Length(LineText) > 0) And (LineText[1] = ' ') Then
      Begin
        FPrefixLen := 1;
        FPrefixStr := ' ';
        FPrefixDone := False;
        Body := Copy(LineText, 2, MaxInt);
      End
    Else
      Body := LineText;
    { Private language instance only: line index 0 => ResetRange, no CurrentRanges. }
    FLang.SetAlternativeLineTextForGetTokens(Body, 0);
    FContextMode := True;
    FAtEol := False;
    If FPrefixDone And FLang.GetEol Then
      FAtEol := True;
  Except
    { Fall back to Diff tokens already set up by Inherited (this line only). }
    FContextMode := False;
  End;
End;

Procedure TGitMixedDiffHighlighter.Next;
Begin
  If Not FContextMode Then
    Begin
      Inherited;
      Exit;
    End;
  If FAtEol Then
    Exit;
  Try
    If Not FPrefixDone Then
      Begin
        FPrefixDone := True;
        If (Not Assigned(FLang)) Or FLang.GetEol Then
          FAtEol := True;
        Exit;
      End;
    If Not Assigned(FLang) Then
      Begin
        FAtEol := True;
        Exit;
      End;
    FLang.Next;
    If FLang.GetEol Then
      FAtEol := True;
  Except
    FAtEol := True;
    FContextMode := False;
  End;
End;

Function TGitMixedDiffHighlighter.GetEol: Boolean;
Begin
  If FContextMode Then
    Result := FAtEol
  Else
    Result := Inherited GetEol;
End;

Function TGitMixedDiffHighlighter.GetToken: String;
Begin
  If Not FContextMode Then
    Exit(Inherited GetToken);
  Try
    If Not FPrefixDone Then
      Result := FPrefixStr
    Else If Assigned(FLang) Then
      Result := FLang.GetToken
    Else
      Result := Inherited GetToken;
  Except
    Result := Inherited GetToken;
  End;
End;

Function TGitMixedDiffHighlighter.GetTokenPos: Integer;
Begin
  If Not FContextMode Then
    Exit(Inherited GetTokenPos);
  Try
    If Not FPrefixDone Then
      Result := 0
    Else If Assigned(FLang) Then
      Result := FLang.GetTokenPos + FPrefixLen
    Else
      Result := Inherited GetTokenPos;
  Except
    Result := Inherited GetTokenPos;
  End;
End;

Function TGitMixedDiffHighlighter.GetTokenKind: Integer;
Begin
  If Not FContextMode Then
    Exit(Inherited GetTokenKind);
  Try
    If Not FPrefixDone Then
      Result := 0
    Else If Assigned(FLang) Then
      Result := FLang.GetTokenKind
    Else
      Result := Inherited GetTokenKind;
  Except
    Result := Inherited GetTokenKind;
  End;
End;

Procedure TGitMixedDiffHighlighter.GetTokenEx(Out TokenStart: PChar; Out TokenLength: Integer);
Begin
  If Not FContextMode Then
    Begin
      Inherited GetTokenEx(TokenStart, TokenLength);
      Exit;
    End;
  Try
    If Not FPrefixDone Then
      Begin
        TokenStart := PChar(FPrefixStr);
        TokenLength := FPrefixLen;
      End
    Else If Assigned(FLang) Then
      FLang.GetTokenEx(TokenStart, TokenLength)
    Else
      Inherited GetTokenEx(TokenStart, TokenLength);
  Except
    Inherited GetTokenEx(TokenStart, TokenLength);
  End;
End;

Function TGitMixedDiffHighlighter.GetTokenAttribute: TLazEditTextAttribute;
Begin
  If Not FContextMode Then
    Exit(Inherited GetTokenAttribute);
  Try
    If Not FPrefixDone Then
      Result := LineContextAttri
    Else If Assigned(FLang) Then
      Begin
        Result := FLang.GetTokenAttribute;
        If Result = Nil Then
          Result := LineContextAttri;
      End
    Else
      Result := Inherited GetTokenAttribute;
  Except
    Result := LineContextAttri;
  End;
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
  FOwnedLangHigh := Nil;
  FAppearanceReady := False;
  FSelectedLines := TFPList.Create;
  FPreviewPicture := TPicture.Create;
  FMixedHigh := TGitMixedDiffHighlighter.Create(Self);
  ApplyIDEEditorAppearance;
  ApplyViewMode;
  ShowEditorPane;
  UpdateActionEnabled;
End;

Destructor TGitDiffView.Destroy;
Begin
  CancelPendingScroll;
  FreeOwnedLanguageHighlighter;
  FreeAndNil(FPreviewPicture);
  FreeAndNil(FSelectedLines);
  FMixedHigh := Nil; { owned by Self }
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

Procedure TGitDiffView.ConfigureDiffColors(DiffHL: TSynDiffSyn);
Begin
  If Not Assigned(DiffHL) Then
    Exit;
  DiffHL.LineAddedAttri.Foreground := RGBToColor(27, 94, 32);
  { Token backgrounds kept none so SpecialLineColors can paint full row width. }
  DiffHL.LineAddedAttri.Background := clNone;
  DiffHL.LineRemovedAttri.Foreground := RGBToColor(183, 28, 28);
  DiffHL.LineRemovedAttri.Background := clNone;
  DiffHL.ChunkMarkerAttri.Foreground := RGBToColor(69, 90, 100);
  DiffHL.ChunkMarkerAttri.Background := RGBToColor(236, 239, 241);
  DiffHL.ChunkNewAttri.Foreground := RGBToColor(46, 125, 50);
  DiffHL.ChunkOldAttri.Foreground := RGBToColor(198, 40, 40);
  DiffHL.NewFileAttri.Foreground := RGBToColor(27, 94, 32);
  DiffHL.NewFileAttri.Background := clNone;
  DiffHL.OrigFileAttri.Foreground := RGBToColor(183, 28, 28);
  DiffHL.OrigFileAttri.Background := clNone;
  DiffHL.LineContextAttri.Foreground := clWindowText;
  DiffHL.LineContextAttri.Background := clNone;
  DiffHL.SpaceAttri.Background := clNone;
  DiffHL.UnknownAttri.Background := clNone;
End;

Procedure TGitDiffView.SetupDiffOverviewGutter;
Var
  I: Integer;
  PageProvider: TSynGutterLOvProviderCurrentPage;
  DiffProvider: TGitDiffOverviewProvider;
Begin
  If Not Assigned(FEdit) Then
    Exit;

  FDiffOverviewProvider := Nil;
  FOverviewGutter := Nil;
  For I := FEdit.RightGutter.Parts.Count - 1 DownTo 0 Do
    FEdit.RightGutter.Parts[I].Free;

  { Fixed width — AutoSize on the right gutter often collapses to 0 for frames
    that first layout while their notebook page is hidden (Files tab). }
  FEdit.RightGutter.AutoSize := False;
  FEdit.RightGutter.Width := 16;
  FEdit.RightGutter.Visible := True;

  FOverviewGutter := TSynGutterLineOverview.Create(FEdit.RightGutter.Parts);
  FOverviewGutter.AutoSize := False;
  FOverviewGutter.Width := 16;
  FOverviewGutter.Visible := True;
  FOverviewGutter.MarkupInfo.Background := RGBToColor(236, 239, 241);

  PageProvider := TSynGutterLOvProviderCurrentPage.Create(FOverviewGutter.Providers);
  PageProvider.Color := RGBToColor(176, 190, 197);
  PageProvider.Priority := 1;

  DiffProvider := TGitDiffOverviewProvider.Create(FOverviewGutter.Providers);
  DiffProvider.ColorAdded := RGBToColor(76, 175, 80);
  DiffProvider.ColorRemoved := RGBToColor(229, 57, 53);
  DiffProvider.Priority := 20;
  FDiffOverviewProvider := DiffProvider;
End;

Procedure TGitDiffView.EnsureDiffOverviewGutter;
Var
  I: Integer;
  StillInstalled: Boolean;
Begin
  { Overview paints on a child TWinControl (not Gutter.Paint). That child only
    gets BoundsRect when the part is Visible and SynEdit has a handle — so we
    reassert size/visibility after every load and after notebook tab shows. }
  If Not Assigned(FEdit) Then
    Exit;

  StillInstalled := False;
  If Assigned(FOverviewGutter) Then
    For I := 0 To FEdit.RightGutter.Parts.Count - 1 Do
      If FEdit.RightGutter.Parts[I] = FOverviewGutter Then
        Begin
          StillInstalled := True;
          Break;
        End;

  If Not StillInstalled Then
    SetupDiffOverviewGutter;

  FEdit.RightGutter.AutoSize := False;
  FEdit.RightGutter.Width := 16;
  FEdit.RightGutter.Visible := True;
  If Assigned(FOverviewGutter) Then
    Begin
      FOverviewGutter.AutoSize := False;
      FOverviewGutter.Width := 16;
      { Toggle visibility so GutterVisibilityChanged / DoResize repositions FWinControl. }
      FOverviewGutter.Visible := False;
      FOverviewGutter.Visible := True;
    End;

  If FEdit.HandleAllocated Then
    Begin
      FEdit.RightGutter.RecalcBounds;
      FEdit.Invalidate;
    End;
End;

Procedure TGitDiffView.ScheduleOverviewRefresh;
Begin
  If Not Assigned(FEdit) Then
    Exit;
  { Do not RemoveAsyncCalls — that would cancel scroll-to-change. }
  Application.QueueAsyncCall(@DoRefreshOverviewAsync, 0);
End;

Procedure TGitDiffView.DoRefreshOverviewAsync(Data: PtrInt);
Begin
  If Not IsAlive Then
    Exit;
  EnsureDiffOverviewGutter;
  If Assigned(FEdit) And FEdit.HandleAllocated Then
    FEdit.Invalidate;
End;

Procedure TGitDiffView.RefreshOverviewGutter;
Begin
  EnsureDiffOverviewGutter;
  ScheduleOverviewRefresh;
End;

Procedure TGitDiffView.ApplyIDEEditorAppearance;
Begin
  If Not Assigned(FEdit) Then
    Exit;

  { Full IDE options only once: repeated GetSynEditorSettings can touch gutter parts
    and beautifier state that are unsafe to re-apply while the editor is live. }
  If Not FAppearanceReady Then
    Begin
      If Assigned(IDEEditorOptions) Then
        Begin
          Try
            IDEEditorOptions.GetSynEditorSettings(FEdit);
          Except
            On E: Exception Do
              WorkflowLogger.Warning('GitDiffView', 'GetSynEditorSettings: ' + E.Message);
          End;
          If Assigned(FHigh) Then
            Try
              IDEEditorOptions.GetHighlighterSettings(FHigh);
            Except
              On E: Exception Do
                WorkflowLogger.Warning('GitDiffView', 'GetHighlighterSettings: ' + E.Message);
            End;
          If Assigned(FMixedHigh) Then
            Try
              IDEEditorOptions.GetHighlighterSettings(TSynDiffSyn(FMixedHigh));
            Except
            End;
        End
      Else
        Begin
          FEdit.Font.Size := 10;
          FEdit.Font.Name := 'Courier New';
          FEdit.Font.Pitch := fpFixed;
          FEdit.Font.Quality := fqCleartypeNatural;
        End;
      { Install after IDE settings so ApplyTo cannot hide/replace our overview. }
      SetupDiffOverviewGutter;
      FAppearanceReady := True;
    End;

  FEdit.ReadOnly := True;
  FEdit.WantTabs := True;
  FEdit.Options := FEdit.Options - [eoShowSpecialChars];
  FEdit.OnDblClick := @EditDblClick;
  FEdit.OnMouseDown := @EditMouseDown;
  FEdit.OnSpecialLineColors := @EditSpecialLineColors;
  FEdit.UnRegisterStatusChangedHandler(@EditStatusChange);
  FEdit.RegisterStatusChangedHandler(@EditStatusChange, [scSelection, scCaretX, scCaretY]);
  ApplyEditorSelectionPolicy;
  { Keep overview visible even if earlier setup ran while the Files tab was hidden. }
  EnsureDiffOverviewGutter;
End;

Procedure TGitDiffView.ApplyEditorSelectionPolicy;
Begin
  If Not Assigned(FEdit) Then
    Exit;
  Case FMode Of
    dvmBrowse:
      Begin
        { History: scroll-only preview — no text selection. }
        FEdit.Options := FEdit.Options + [eoNoSelection];
        FEdit.BlockBegin := Point(1, 1);
        FEdit.BlockEnd := Point(1, 1);
        ClearLineSelection(False);
      End;
    dvmEditorOnly:
      Begin
        { Files: no free-range selection; whole change-lines only via click. }
        FEdit.Options := FEdit.Options + [eoNoSelection];
        FEdit.BlockBegin := Point(1, 1);
        FEdit.BlockEnd := Point(1, 1);
      End;
  Else
    { Staging tree mode: normal selection for hunk/line stage. }
    FEdit.Options := FEdit.Options - [eoNoSelection];
  End;
End;

Procedure TGitDiffView.ClearLineSelection(NotifyChange: Boolean);
Begin
  If Assigned(FSelectedLines) And (FSelectedLines.Count > 0) Then
    Begin
      FSelectedLines.Clear;
      If Assigned(FEdit) Then
        FEdit.Invalidate;
      If NotifyChange Then
        Begin
          UpdateActionEnabled;
          DoSelectionChanged;
        End;
    End
  Else If Assigned(FSelectedLines) Then
    FSelectedLines.Clear;
End;

Function TGitDiffView.IsLineSelected(LineNo: Integer): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  If Not Assigned(FSelectedLines) Then
    Exit;
  For I := 0 To FSelectedLines.Count - 1 Do
    If PtrInt(FSelectedLines[I]) = LineNo Then
      Exit(True);
End;

Function TGitDiffView.SelectedLineCount: Integer;
Begin
  If Assigned(FSelectedLines) Then
    Result := FSelectedLines.Count
  Else
    Result := 0;
End;

Function TGitDiffView.SelectedLineBounds(Out FirstLine, LastLine: Integer): Boolean;
Var
  I, LineNo: Integer;
Begin
  Result := False;
  FirstLine := 0;
  LastLine := 0;
  If SelectedLineCount < 1 Then
    Exit;
  FirstLine := MaxInt;
  LastLine := 0;
  For I := 0 To FSelectedLines.Count - 1 Do
    Begin
      LineNo := Integer(PtrInt(FSelectedLines[I]));
      If LineNo < FirstLine Then
        FirstLine := LineNo;
      If LineNo > LastLine Then
        LastLine := LineNo;
    End;
  Result := (FirstLine >= 1) And (LastLine >= FirstLine);
End;

Procedure TGitDiffView.ToggleLineSelection(LineNo: Integer);
Var
  I: Integer;
Begin
  If Not Assigned(FSelectedLines) Then
    Exit;
  For I := 0 To FSelectedLines.Count - 1 Do
    If PtrInt(FSelectedLines[I]) = LineNo Then
      Begin
        FSelectedLines.Delete(I);
        If Assigned(FEdit) Then
          FEdit.Invalidate;
        UpdateActionEnabled;
        DoSelectionChanged;
        Exit;
      End;
  FSelectedLines.Add(Pointer(PtrInt(LineNo)));
  If Assigned(FEdit) Then
    FEdit.Invalidate;
  UpdateActionEnabled;
  DoSelectionChanged;
End;

Procedure TGitDiffView.SelectChangeLinesInRange(StartLine, EndLine: Integer);
Var
  LineNo: Integer;
  LineText: String;
Begin
  ClearLineSelection(False);
  If (Not Assigned(FEdit)) Or (Not Assigned(FSelectedLines)) Then
    Exit;
  If StartLine < 1 Then
    StartLine := 1;
  If EndLine > FEdit.Lines.Count Then
    EndLine := FEdit.Lines.Count;
  For LineNo := StartLine To EndLine Do
    Begin
      LineText := FEdit.Lines[LineNo - 1];
      If IsDiffChangeLine(LineText) Then
        FSelectedLines.Add(Pointer(PtrInt(LineNo)));
    End;
  FEdit.Invalidate;
  UpdateActionEnabled;
  DoSelectionChanged;
End;

Procedure TGitDiffView.FreeOwnedLanguageHighlighter;
Begin
  If Assigned(FMixedHigh) Then
    TGitMixedDiffHighlighter(FMixedHigh).SetLanguageBackend(Nil);
  If Assigned(FEdit) And Assigned(FOwnedLangHigh) And (FEdit.Highlighter = FOwnedLangHigh) Then
    FEdit.Highlighter := Nil;
  FreeAndNil(FOwnedLangHigh);
End;

Procedure TGitDiffView.ApplyDiffHighlighter;
Var
  DiffHL: TSynDiffSyn;
Begin
  If Not Assigned(FEdit) Then
    Exit;
  ShowEditorPane;
  FreeOwnedLanguageHighlighter;
  DiffHL := FHigh;
  If Assigned(FMixedHigh) Then
    Begin
      TGitMixedDiffHighlighter(FMixedHigh).SetLanguageBackend(Nil);
      DiffHL := TSynDiffSyn(FMixedHigh);
    End;
  If Assigned(DiffHL) Then
    Begin
      If Assigned(IDEEditorOptions) Then
        Try
          IDEEditorOptions.GetHighlighterSettings(DiffHL);
        Except
        End;
      FEdit.Highlighter := DiffHL;
      ConfigureDiffColors(DiffHL);
    End
  Else
    FEdit.Highlighter := Nil;
End;

Function TGitDiffView.CreateOwnedLanguageHighlighter(Const SourceFileName: String): TObject;
Var
  Ext: String;
  Id: TIdeSyntaxHighlighterID;
  Cls: TLazEditCustomHighlighterClass;
  HL: TLazEditCustomHighlighter;
Begin
  { Private stock SynEdit highlighters — avoid TIDESyn* subclasses that expect a full
    source-editor host (those caused access violations when used only for tokens). }
  Result := Nil;
  Ext := NormalizeExt(ExtractFileExt(SourceFileName));
  If Ext = '' Then
    Exit;
  HL := Nil;
  Try
    If (Ext = '.pas') Or (Ext = '.pp') Or (Ext = '.inc') Or (Ext = '.lpr') Or
       (Ext = '.dpk') Or (Ext = '.dpr') Or (Ext = '.lpk') Then
      HL := TSynPasSyn.Create(Nil)
    Else If (Ext = '.lfm') Or (Ext = '.dfm') Then
      HL := TSynLFMSyn.Create(Nil)
    Else If (Ext = '.xml') Or (Ext = '.lpi') Or (Ext = '.lps') Or (Ext = '.xlf') Or
            (Ext = '.xsl') Or (Ext = '.xsd') Then
      HL := TSynXMLSyn.Create(Nil)
    Else If IdeSyntaxHighlighters <> Nil Then
      Begin
        Id := IdeSyntaxHighlighters.GetIdForFileExtension(Ext);
        If (Id >= IdeHighlighterStartId) And (Id <> IdeHighlighterUnknownId) Then
          Begin
            Cls := IdeSyntaxHighlighters.SynHlClasses[Id];
            { Skip IDE-specialised classes (name contains 'IDE'). }
            If Assigned(Cls) And (Pos('IDE', Cls.ClassName) = 0) Then
              HL := Cls.Create(Nil);
          End;
      End;
  Except
    HL := Nil;
  End;
  If Not Assigned(HL) Then
    Exit;
  If Assigned(IDEEditorOptions) Then
    Try
      IDEEditorOptions.GetHighlighterSettings(HL);
    Except
    End;
  Result := HL;
End;

Procedure TGitDiffView.ApplyLanguageHighlighter(Const SourceFileName: String);
Var
  HL: TLazEditCustomHighlighter;
Begin
  If Not Assigned(FEdit) Then
    Exit;
  ShowEditorPane;
  FreeOwnedLanguageHighlighter;
  HL := TLazEditCustomHighlighter(CreateOwnedLanguageHighlighter(SourceFileName));
  If Assigned(HL) Then
    Begin
      FOwnedLangHigh := HL;
      FEdit.Highlighter := HL;
    End
  Else
    FEdit.Highlighter := Nil;
End;

Procedure TGitDiffView.ApplyMixedDiffHighlighter(Const SourceFileName: String);
Var
  Lang: TLazEditCustomHighlighter;
  Mixed: TGitMixedDiffHighlighter;
Begin
  If Not Assigned(FEdit) Then
    Exit;
  ShowEditorPane;
  FreeOwnedLanguageHighlighter;
  If Not Assigned(FMixedHigh) Then
    Begin
      ApplyDiffHighlighter;
      Exit;
    End;
  Mixed := TGitMixedDiffHighlighter(FMixedHigh);
  Mixed.SetLanguageBackend(Nil);
  If Assigned(IDEEditorOptions) Then
    Try
      IDEEditorOptions.GetHighlighterSettings(Mixed);
    Except
    End;
  ConfigureDiffColors(Mixed);
  Lang := Nil;
  If SourceFileName <> '' Then
    Lang := TLazEditCustomHighlighter(CreateOwnedLanguageHighlighter(SourceFileName));
  If Assigned(Lang) Then
    Begin
      FOwnedLangHigh := Lang;
      Mixed.SetLanguageBackend(Lang);
    End;
  Try
    FEdit.Highlighter := Mixed;
  Except
    On E: Exception Do
      Begin
        WorkflowLogger.Warning('GitDiffView', 'Mixed highlighter failed: ' + E.Message);
        Mixed.SetLanguageBackend(Nil);
        FreeAndNil(FOwnedLangHigh);
        ApplyDiffHighlighter;
      End;
  End;
End;

Procedure TGitDiffView.ShowEditorPane;
Begin
  If Assigned(FPreviewPicture) Then
    FPreviewPicture.Clear;
  If Assigned(FBinaryLabel) Then
    FBinaryLabel.Visible := False;
  If Assigned(FImagePaintBox) Then
    FImagePaintBox.Visible := False;
  If Assigned(FPreviewPanel) Then
    Begin
      FPreviewPanel.Visible := False;
      FPreviewPanel.SendToBack;
    End;
  If Assigned(FEdit) Then
    Begin
      FEdit.Visible := True;
      FEdit.BringToFront;
    End;
End;

Procedure TGitDiffView.ShowBinaryMessage(Const TitleText: String);
Begin
  CancelPendingScroll;
  FDiffText := '';
  FreeOwnedLanguageHighlighter;
  If Assigned(FEdit) Then
    Begin
      FEdit.Highlighter := Nil;
      FEdit.Lines.Clear;
      FEdit.Visible := False;
    End;
  If Assigned(FPreviewPicture) Then
    FPreviewPicture.Clear;
  If TitleText <> '' Then
    FCaption.Caption := TitleText;
  If Assigned(FImagePaintBox) Then
    FImagePaintBox.Visible := False;
  If Assigned(FBinaryLabel) Then
    Begin
      FBinaryLabel.Caption := 'Non-text binary file contents.';
      FBinaryLabel.Visible := True;
    End;
  If Assigned(FPreviewPanel) Then
    FPreviewPanel.Visible := True;
  UpdateActionEnabled;
End;

Function TGitDiffView.TryShowImageFromStream(Const TitleText: String; Stream: TStream): Boolean;
Begin
  Result := False;
  If (Stream = Nil) Or (Stream.Size = 0) Or (Not Assigned(FPreviewPicture)) Then
    Exit;
  Stream.Position := 0;
  Try
    FPreviewPicture.LoadFromStream(Stream);
  Except
    FPreviewPicture.Clear;
    Exit;
  End;
  If (FPreviewPicture.Width < 1) Or (FPreviewPicture.Height < 1) Then
    Begin
      FPreviewPicture.Clear;
      Exit;
    End;
  CancelPendingScroll;
  FDiffText := '';
  FreeOwnedLanguageHighlighter;
  If Assigned(FEdit) Then
    Begin
      FEdit.Highlighter := Nil;
      FEdit.Lines.Clear;
      FEdit.Visible := False;
    End;
  If TitleText <> '' Then
    FCaption.Caption := TitleText;
  If Assigned(FBinaryLabel) Then
    FBinaryLabel.Visible := False;
  If Assigned(FImagePaintBox) Then
    Begin
      FImagePaintBox.Visible := True;
      FImagePaintBox.Invalidate;
    End;
  If Assigned(FPreviewPanel) Then
    FPreviewPanel.Visible := True;
  Result := True;
  UpdateActionEnabled;
End;

Function TGitDiffView.TryShowBinaryOrImage(Const TitleText, RelPath: String; Const Sha: String;
  StagedSide: Boolean): Boolean;
Var
  Mem: TMemoryStream;
  Ext: String;
Begin
  Result := False;
  Ext := ExtractFileExt(RelPath);
  If Not (FileExtensionIsImage(Ext) Or FileExtensionIsLikelyBinary(Ext)) Then
    Exit;
  If Not Assigned(GitClient) Or (FRepoPath = '') Then
    Begin
      ShowBinaryMessage(TitleText);
      Result := True;
      Exit;
    End;
  GitClient.RepoPath := FRepoPath;
  If FileExtensionIsImage(Ext) Then
    Begin
      Mem := TMemoryStream.Create;
      Try
        If GitClient.ReadBlobBytes(Sha, RelPath, StagedSide, Mem) And
           TryShowImageFromStream(TitleText, Mem) Then
          Begin
            Result := True;
            Exit;
          End;
      Finally
        Mem.Free;
      End;
    End;
  { Binary extension, or image that LCL could not decode. }
  ShowBinaryMessage(TitleText);
  Result := True;
End;

Function TGitDiffView.LoadBinaryOrImagePreview(Const Title, RelPath: String; Const Sha: String;
  StagedSide: Boolean): Boolean;
Begin
  Result := False;
  If Not IsAlive Then
    Exit;
  If FMode = dvmEditorOnly Then
    ApplyViewMode
  Else If FMode = dvmBrowse Then
    ApplyViewMode;
  Result := TryShowBinaryOrImage(Title, RelPath, Sha, StagedSide);
End;

Procedure TGitDiffView.ImagePaintBoxPaint(Sender: TObject);
Var
  Dest: TRect;
  BoxW, BoxH, ImgW, ImgH: Integer;
  Scale, ScaleX, ScaleY: Double;
  DrawW, DrawH: Integer;
Begin
  If Not Assigned(FImagePaintBox) Then
    Exit;
  With FImagePaintBox.Canvas Do
    Begin
      Brush.Color := clWindow;
      FillRect(FImagePaintBox.ClientRect);
    End;
  If (Not Assigned(FPreviewPicture)) Or (FPreviewPicture.Width < 1) Or (FPreviewPicture.Height < 1) Then
    Exit;
  BoxW := FImagePaintBox.ClientWidth;
  BoxH := FImagePaintBox.ClientHeight;
  ImgW := FPreviewPicture.Width;
  ImgH := FPreviewPicture.Height;
  If (BoxW < 1) Or (BoxH < 1) Then
    Exit;
  ScaleX := BoxW / ImgW;
  ScaleY := BoxH / ImgH;
  If ScaleX < ScaleY Then
    Scale := ScaleX
  Else
    Scale := ScaleY;
  If Scale > 1 Then
    Scale := 1; { do not upscale small images past 1:1 }
  DrawW := Max(1, Round(ImgW * Scale));
  DrawH := Max(1, Round(ImgH * Scale));
  Dest.Left := (BoxW - DrawW) Div 2;
  Dest.Top := (BoxH - DrawH) Div 2;
  Dest.Right := Dest.Left + DrawW;
  Dest.Bottom := Dest.Top + DrawH;
  FImagePaintBox.Canvas.StretchDraw(Dest, FPreviewPicture.Graphic);
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
  ApplyEditorSelectionPolicy;
  If FMode <> dvmEditorOnly Then
    ClearLineSelection(False);
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
  If FMode = dvmBrowse Then
    Result := False
  Else If FMode = dvmEditorOnly Then
    Result := SelectedLineCount > 0
  Else
    Result := Assigned(FEdit) And FEdit.SelAvail;
End;

Procedure TGitDiffView.EditSpecialLineColors(Sender: TObject; Line: Integer;
  Var Special: Boolean; Var FG, BG: TColor);
Var
  LineText: String;
  LineSelected: Boolean;
Begin
  Special := False;
  If (Not Assigned(FEdit)) Or (Line < 1) Or (Line > FEdit.Lines.Count) Then
    Exit;
  LineText := FEdit.Lines[Line - 1];
  LineSelected := (FMode = dvmEditorOnly) And IsLineSelected(Line);

  If LineIsDiffAdded(LineText) Then
    Begin
      Special := True;
      FG := RGBToColor(27, 94, 32);
      If LineSelected Then
        BG := RGBToColor(129, 199, 132) { stronger green when selected }
      Else
        BG := RGBToColor(232, 245, 233);
    End
  Else If LineIsDiffRemoved(LineText) Then
    Begin
      Special := True;
      FG := RGBToColor(183, 28, 28);
      If LineSelected Then
        BG := RGBToColor(239, 154, 154)
      Else
        BG := RGBToColor(255, 235, 238);
    End
  Else If Copy(LineText, 1, 2) = '@@' Then
    Begin
      Special := True;
      FG := RGBToColor(69, 90, 100);
      BG := RGBToColor(236, 239, 241);
    End
  Else If LineSelected Then
    Begin
      { Should not happen (only change lines are selectable) — keep visible. }
      Special := True;
      FG := clWindowText;
      BG := RGBToColor(187, 222, 251);
    End;
End;

Procedure TGitDiffView.EditMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
Var
  Pt: TPoint;
  LineNo: Integer;
  LineText: String;
Begin
  If FMode = dvmBrowse Then
    Begin
      { Keep caret free for scrolling; never create a selection. }
      If Assigned(FEdit) Then
        Begin
          FEdit.BlockBegin := Point(1, FEdit.CaretY);
          FEdit.BlockEnd := Point(1, FEdit.CaretY);
        End;
      Exit;
    End;

  If FMode <> dvmEditorOnly Then
    Exit;
  If Button <> mbLeft Then
    Exit;
  If Not Assigned(FEdit) Then
    Exit;

  Pt := FEdit.PixelsToRowColumn(Point(X, Y));
  LineNo := Pt.Y;
  If (LineNo < 1) Or (LineNo > FEdit.Lines.Count) Then
    Exit;
  LineText := FEdit.Lines[LineNo - 1];
  If Not IsDiffChangeLine(LineText) Then
    Exit; { ignore clicks on context / headers }

  FEdit.CaretY := LineNo;
  FEdit.CaretX := 1;

  If ssCtrl in Shift Then
    ToggleLineSelection(LineNo)
  Else If IsLineSelected(LineNo) And (SelectedLineCount = 1) Then
    ClearLineSelection(True) { second click on sole selection unselects }
  Else If IsLineSelected(LineNo) Then
    ToggleLineSelection(LineNo) { remove this line from a multi-selection }
  Else
    Begin
      ClearLineSelection(False);
      FSelectedLines.Add(Pointer(PtrInt(LineNo)));
      FEdit.Invalidate;
      UpdateActionEnabled;
      DoSelectionChanged;
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
  ClearLineSelection(False);
  ShowEditorPane;
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
  EnsureDiffOverviewGutter;
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
  If FMode = dvmEditorOnly Then
    Begin
      If SelectedLineBounds(FirstLine, LastLine) Then
        Exit;
      FirstLine := 0;
      LastLine := 0;
      Exit;
    End;
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
  UseLineSet: Boolean;

  Function LineSelected(ALineNo: Integer): Boolean;
  Begin
    If UseLineSet Then
      Result := IsLineSelected(ALineNo)
    Else
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
  UseLineSet := (FMode = dvmEditorOnly) And (SelectedLineCount > 0);
  If UseLineSet Then
    Begin
      If Not SelectedLineBounds(FirstLine, LastLine) Then
        Exit;
    End
  Else If (FirstLine < 1) Or (LastLine < FirstLine) Or (FEdit.Lines.Count = 0) Then
    Exit;
  If FEdit.Lines.Count = 0 Then
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
  If Not Result Then
    Exit;
  If FMode = dvmEditorOnly Then
    SelectChangeLinesInRange(FirstLine, LastLine)
  Else
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
  If FMode = dvmEditorOnly Then
    Begin
      If SelectedLineCount < 1 Then
        Begin
          MessageDlg('Click changed (red/green) lines to select them for staging. Ctrl+click adds more; click again to unselect.',
            mtInformation, [mbOK], 0);
          Exit;
        End;
      If Not SelectedLineBounds(FirstLine, LastLine) Then
        Exit;
    End
  Else
    Begin
      GetSelectionLines(FirstLine, LastLine);
      If FirstLine < 1 Then
        Begin
          If Not FindHunkBounds(FEdit.CaretY, FirstLine, LastLine) Then
            Begin
              MessageDlg('Select lines to stage, or place the caret in a change hunk.',
                mtInformation, [mbOK], 0);
              Exit;
            End;
          SelectLineRange(FirstLine, LastLine);
        End;
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
      ClearLineSelection(False);
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
  If FMode = dvmEditorOnly Then
    Begin
      If SelectedLineCount < 1 Then
        Begin
          MessageDlg('Click changed (red/green) lines to select them for unstaging. Ctrl+click adds more; click again to unselect.',
            mtInformation, [mbOK], 0);
          Exit;
        End;
      If Not SelectedLineBounds(FirstLine, LastLine) Then
        Exit;
    End
  Else
    Begin
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
      ClearLineSelection(False);
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
  { Double-click a change line to select all change lines in its hunk. }
  If (FMode = dvmEditorOnly) Or (FMode = dvmStaging) Then
    SelectHunkAtLine(FEdit.CaretY);
End;

Procedure TGitDiffView.EditStatusChange(Sender: TObject; Changes: TSynStatusChanges);
Begin
  If FMode = dvmBrowse Then
    Exit;
  If FMode = dvmEditorOnly Then
    Begin
      { Line multi-select is driven by mouse handlers, not SynEdit selection. }
      If scCaretY in Changes Then
        UpdateActionEnabled;
      Exit;
    End;
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
  ShowEditorPane;
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
  If TryShowBinaryOrImage(Path, Path, FBrowseSha, False) Then
    Exit;
  If Not IsAlive Or (FBrowseSha <> ExpectedSha) Or (FMode <> dvmBrowse) Then
    Exit;

  GitClient.RepoPath := FRepoPath;
  If Not GitClient.ShowCommitPathDiff(FBrowseSha, Path, DiffText) Then
    Begin
      If Not IsAlive Or (FBrowseSha <> ExpectedSha) Then
        Exit;
      ShowEditorPane;
      FEdit.Highlighter := Nil;
      FEdit.Lines.Text := 'Could not load diff for ' + Path + LineEnding + GitClient.LastError;
      UpdateActionEnabled;
      Exit;
    End;

  If Not IsAlive Or (FBrowseSha <> ExpectedSha) Or (FMode <> dvmBrowse) Then
    Exit;

  If DiffTextLooksBinary(DiffText) Then
    Begin
      If TryShowBinaryOrImage(Path, Path, FBrowseSha, False) Then
        Exit;
      ShowBinaryMessage(Path);
      Exit;
    End;

  ApplyIDEEditorAppearance;
  ShowEditorPane;
  FDiffText := DiffText;
  If Trim(DiffText) = '' Then
    Begin
      FreeOwnedLanguageHighlighter;
      FEdit.Highlighter := Nil;
      FEdit.Lines.Text := '(no textual diff for ' + Path + ')';
    End
  Else
    Begin
      { Load text under plain Diff first so a highlighter failure cannot leave a blank pane. }
      ApplyDiffHighlighter;
      FEdit.Lines.Text := DiffText;
      ApplyMixedDiffHighlighter(Path);
      EnsureDiffOverviewGutter;
      ScheduleOverviewRefresh;
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

Procedure TGitDiffView.LoadEmbeddedDiff(Const Title, DiffText: String; Const SourceFileName: String);
Begin
  If Not IsAlive Then
    Exit;
  SetViewMode(dvmEditorOnly);
  CancelPendingScroll;
  If Title <> '' Then
    FCaption.Caption := Title;
  ApplyIDEEditorAppearance;
  If DiffTextLooksBinary(DiffText) And (SourceFileName <> '') Then
    Begin
      If TryShowBinaryOrImage(Title, SourceFileName, '', FStagedSide) Then
        Exit;
      ShowBinaryMessage(Title);
      Exit;
    End;
  ShowEditorPane;
  FDiffText := DiffText;
  If Trim(DiffText) = '' Then
    Begin
      FreeOwnedLanguageHighlighter;
      FEdit.Highlighter := Nil;
      FEdit.Lines.Text := '(no textual diff)';
      UpdateActionEnabled;
      Exit;
    End;
  ClearLineSelection(False);
  ApplyEditorSelectionPolicy;
  { Text under Diff first, then upgrade to mixed language highlighting. }
  ApplyDiffHighlighter;
  FEdit.Lines.Text := DiffText;
  ApplyMixedDiffHighlighter(SourceFileName);
  EnsureDiffOverviewGutter;
  ScheduleOverviewRefresh;
  Inc(FScrollGeneration);
  Application.QueueAsyncCall(@DoScrollToFirstChangeAsync, FScrollGeneration);
  UpdateActionEnabled;
End;

Procedure TGitDiffView.LoadDiff(Const Title, DiffText: String);
Begin
  SetViewMode(dvmStaging);
  ShowEditorPane;
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
  EnsureDiffOverviewGutter;
  ScheduleOverviewRefresh;
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
  ShowEditorPane;
  FDiffText := '';
  If (SourceFileName <> '') And FileExtensionIsLikelyBinary(ExtractFileExt(SourceFileName)) Then
    Begin
      If TryShowBinaryOrImage(Title, SourceFileName, '', FStagedSide) Then
        Exit;
      ShowBinaryMessage(Title);
      Exit;
    End;
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
