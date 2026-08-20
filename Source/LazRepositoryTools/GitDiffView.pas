Unit GitDiffView;

{ SynEdit-based diff viewer: staging tree mode, commit browse, Files tab preview
  with mixed Diff+language highlighting, and image/binary previews
  (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. The frame still owns selection,
  preview, and load paths after GitDiffPatch / GitDiffHighlighter were split out.
  Reviewed 2026-08: remaining growth is UI surface, not another sibling unit. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Types, Controls, Graphics, ExtCtrls, ComCtrls, StdCtrls, Forms,
  Menus, SynEdit, SynEditTypes, SynHighlighterDiff, SynGutter, SynGutterBase,
  SynGutterLineOverview, GitJobRunner, GitDiffPatch;

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
  Published
    { Streamed frame children must be published (ObjFPC default section is public). }
    TitleLabel: TLabel;
    ToolBar: TPanel;
    StageSelectionButton: TButton;
    UnstageSelectionButton: TButton;
    TreePanel: TPanel;
    Tree: TTreeView;
    FileList: TListBox;
    Splitter: TSplitter;
    EditPanel: TPanel;
    DiffEditor: TSynEdit;
    PreviewPanel: TPanel;
    BinaryLabel: TLabel;
    ImagePaintBox: TPaintBox;
    DiffHighlighter: TSynDiffSyn;
    Popup: TPopupMenu;
    CopyMenuItem: TMenuItem;
    CopySeparator: TMenuItem;
    StageMenuItem: TMenuItem;
    StageHunkMenuItem: TMenuItem;
    UnstageMenuItem: TMenuItem;
    UnstageHunkMenuItem: TMenuItem;
    MenuSeparator: TMenuItem;
    SelectHunkMenuItem: TMenuItem;
    Procedure TreeChange(Sender: TObject; Node: TTreeNode);
    Procedure FileListSelectionChange(Sender: TObject; User: Boolean);
    Procedure StageSelectionButtonClick(Sender: TObject);
    Procedure UnstageSelectionButtonClick(Sender: TObject);
    Procedure PopupStageClick(Sender: TObject);
    Procedure PopupUnstageClick(Sender: TObject);
    Procedure PopupStageHunkClick(Sender: TObject);
    Procedure PopupUnstageHunkClick(Sender: TObject);
    Procedure PopupSelectHunkClick(Sender: TObject);
    Procedure PopupCopyClick(Sender: TObject);
    Procedure PopupPopup(Sender: TObject);
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
    OverviewGutter: TSynGutterLineOverview;
    DiffOverviewProvider: TObject; { TGitDiffOverviewProvider – avoid circular iface }
    OwnedLangHigh: TObject; { TLazEditCustomHighlighter, private instance }
    MixedHigh: TObject; { TGitMixedDiffHighlighter; Create(Nil) — never Self-owned (would stream into host LFM) }
    PreviewPicture: TPicture;
    FAppearanceReady: Boolean;
    FEditorOptsHooked: Boolean;
    SelectedLines: TGitLineNumberList; { 1-based display line numbers for Files multi-select }
    FLineDragActive: Boolean;
    FLineDragMoved: Boolean;
    FLineDragCtrl: Boolean;
    FLineDragAnchor: Integer; { 1-based }
    FLineDragWasSelected: Boolean;
    LineDragSnapshot: TGitLineNumberList; { selection at mouse-down for Ctrl+drag }
    FUseDisplayMap: Boolean; { Files tab: editor lines omit file meta / @@ headers }
    FDisplayToFull: Array Of Integer; { display 0-based -> full 1-based line in FDiffText }
    HunkStartLines: TGitLineNumberList; { 1-based display lines: first change line of each visual hunk }
    Procedure ApplyIDEEditorAppearance;
    Procedure ApplyCompactEditorFont;
    Procedure ApplyIDEEditorFont;
    Procedure HookEditorOptionsChanged;
    Procedure UnhookEditorOptionsChanged;
    Procedure EditorOptionsChanged(Sender: TObject);
    Procedure EnsureAppearanceReady;
    Procedure DoDeferredInitAsync(Data: PtrInt);
    Function ScaleDesign(DesignPx: Integer): Integer;
    Function OverviewGutterWidth: Integer;
    Procedure ApplyEditorSelectionPolicy;
    Procedure EnsureEditorKeystrokes;
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
    Procedure AddLineToSelection(LineNo: Integer);
    Procedure ToggleLineSelection(LineNo: Integer);
    Procedure SelectChangeLinesInRange(StartLine, EndLine: Integer; MergeWithSnapshot: Boolean = False);
    Procedure ApplyDragLineRange(ToLine: Integer);
    Function LineAtMouse(X, Y: Integer): Integer;
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
    Function ToggleHunkSelectionAtLine(AtLine: Integer): Boolean;
    Function CanStageFromPreview: Boolean;
    Function CanUnstageFromPreview: Boolean;
    Procedure UpdateActionEnabled;
    Procedure DoStatusChanged;
    Procedure DoSelectionChanged;
    Procedure ApplyPatchFinished(Job: TGitJob);
    Function SubmitApplyPatch(Const Patch: String; Reverse: Boolean): Boolean;
    Procedure EditSpecialLineColors(Sender: TObject; Line: Integer; Var Special: Boolean;
      Var FG, BG: TColor);
    Procedure EditMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    Procedure EditMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    Procedure EditMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    Procedure EditPaintEvent(Sender: TObject; EventType: TSynPaintEvent; Const rcClip: TRect);
    Procedure ClearDisplayMap;
    Procedure RebuildVisualHunkStarts;
    Function IsVisualHunkStart(LineNo: Integer): Boolean;
    Procedure SetEditorDiffText(Const DiffText: String; HideFileHeaders: Boolean);
    Function FullLineIsSelected(FullLineNo: Integer): Boolean;
    Function IsHunkHeaderLine(Const Line: String): Boolean;
    Function IsDiffFileMetaLine(Const Line: String): Boolean;
    Function LinePixelTop(LineNo: Integer; Out Y: Integer): Boolean;
    Function HunkMarkerRect(LineNo: Integer): TRect;
    Function PointInHunkMarker(X, Y, LineNo: Integer): Boolean;
    Procedure PaintHunkDecorations(PaintCanvas: TCanvas);
    Procedure ClearTreeData;
    Procedure ShowSelectedBrowseFile;
    Procedure ScrollToFirstChangeCentered;
    Procedure DoScrollToFirstChangeAsync(Data: PtrInt);
    Function IsDiffChangeLine(Const Line: String): Boolean;
    Function IsAlive: Boolean;
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure Loaded; Override;
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
    Property Mode: TGitDiffViewMode Read FMode;
    Property StagedSide: Boolean Read FStagedSide;
    Property OnStatusChanged: TNotifyEvent Read FOnStatusChanged Write FOnStatusChanged;
    Property OnSelectionChanged: TNotifyEvent Read FOnSelectionChanged Write FOnSelectionChanged;
  End;

/// Copy Source Editor font, pitch, and cell spacing onto Editor. True when a font was applied.
Function ApplySynEditIDEFont(Editor: TSynEdit; IncludeColors: Boolean): Boolean;

Implementation

{$R *.lfm}

Uses
  Math, EditorOptionsIntf, SrcEditorIntf, EditorSyntaxHighlighterDef, LazEditHighlighter,
  LazEditTextAttributes, SynHighlighterPas, SynHighlighterXML, SynHighlighterLFM,
  GitService, Dialogs, WorkflowLog, GitDiffHighlighter;

Type
  PGitDiffRange = ^TGitDiffRange;

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

Constructor TGitDiffView.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FRepoPath := '';
  FBrowseSha := '';
  FStagedSide := False;
  FMode := dvmStaging;
  FUpdatingList := False;
  FScrollGeneration := 0;
  OverviewGutter := Nil;
  DiffOverviewProvider := Nil;
  OwnedLangHigh := Nil;
  FAppearanceReady := False;
  FEditorOptsHooked := False;
  SelectedLines := TGitLineNumberList.Create;
  LineDragSnapshot := TGitLineNumberList.Create;
  FLineDragActive := False;
  FLineDragMoved := False;
  FLineDragCtrl := False;
  FLineDragAnchor := 0;
  FLineDragWasSelected := False;
  FUseDisplayMap := False;
  SetLength(FDisplayToFull, 0);
  HunkStartLines := TGitLineNumberList.Create;
  PreviewPicture := TPicture.Create;
  { Owner must be Nil. Create(Self) puts the highlighter in the frame's
    Components list; when TGitDiffView is inlined on a host form the designer
    streams it into the host .lfm as a nameless object TGitMixedDiffHighlighter
    and opening the form AVs. Manual FreeAndNil in Destroy. }
  MixedHigh := TGitMixedDiffHighlighter.Create(Nil);
  { Do not touch SynEdit/IDE options here. Frame construction runs while the
    Manage Repository window is restored at IDE startup; GetSynEditorSettings
    and right-gutter surgery have taken Lazarus down hard. }
End;

Destructor TGitDiffView.Destroy;
Begin
  If Assigned(GitJobs) Then
    Begin
      GitJobs.CancelIfHandler(@ApplyPatchFinished);
      GitJobs.DetachFinishedHandler(@ApplyPatchFinished);
    End;
  CancelPendingScroll;
  Application.RemoveAsyncCalls(Self);
  UnhookEditorOptionsChanged;
  If Assigned(DiffEditor) Then
    Begin
      Try
        DiffEditor.UnRegisterPaintEventHandler(@EditPaintEvent);
      Except
      End;
      Try
        DiffEditor.UnRegisterStatusChangedHandler(@EditStatusChange);
      Except
      End;
      { Detach before freeing private highlighters (not owned by Self). }
      If Assigned(MixedHigh) And (DiffEditor.Highlighter = MixedHigh) Then
        DiffEditor.Highlighter := Nil;
    End;
  FreeOwnedLanguageHighlighter;
  FreeAndNil(MixedHigh);
  FreeAndNil(PreviewPicture);
  FreeAndNil(LineDragSnapshot);
  FreeAndNil(SelectedLines);
  FreeAndNil(HunkStartLines);
  Inherited Destroy;
End;

Procedure TGitDiffView.DoDeferredInitAsync(Data: PtrInt);
Begin
  If Not IsAlive Then
    Exit;
  Try
    EnsureAppearanceReady;
    ApplyViewMode;
    ShowEditorPane;
    UpdateActionEnabled;
  Except
    On E: Exception Do
      WorkflowLogger.Error('GitDiffView', 'DoDeferredInitAsync: ' + E.Message);
  End;
End;

Procedure TGitDiffView.Loaded;
Begin
  Inherited Loaded;
  { After LFM children exist, schedule init on the next app idle — not during
    the streaming stack that IDE desktop restore uses. }
  If Assigned(Application) Then
    Application.QueueAsyncCall(@DoDeferredInitAsync, 0)
  Else
    DoDeferredInitAsync(0);
End;

Procedure TGitDiffView.EnsureAppearanceReady;
Begin
  If FAppearanceReady Or (Not Assigned(DiffEditor)) Then
    Exit;
  If csLoading in ComponentState Then
    Exit;
  If csDestroying in ComponentState Then
    Exit;
  Try
    ApplyIDEEditorAppearance;
  Except
    On E: Exception Do
      WorkflowLogger.Warning('GitDiffView', 'EnsureAppearanceReady: ' + E.Message);
  End;
End;

Function TGitDiffView.IsAlive: Boolean;
Begin
  Result := Not (csDestroying in ComponentState) And Assigned(DiffEditor) And Assigned(FileList);
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
  If Not Assigned(DiffEditor) Then
    Exit;
  Try
    DiffOverviewProvider := Nil;
    OverviewGutter := Nil;
    For I := DiffEditor.RightGutter.Parts.Count - 1 DownTo 0 Do
      DiffEditor.RightGutter.Parts[I].Free;

    { Fixed width — AutoSize on the right gutter often collapses to 0 for frames
      that first layout while their notebook page is hidden (Files tab). }
    DiffEditor.RightGutter.AutoSize := False;
    DiffEditor.RightGutter.Width := OverviewGutterWidth;
    DiffEditor.RightGutter.Visible := True;

    OverviewGutter := TSynGutterLineOverview.Create(DiffEditor.RightGutter.Parts);
    OverviewGutter.AutoSize := False;
    OverviewGutter.Width := OverviewGutterWidth;
    OverviewGutter.Visible := True;
    OverviewGutter.MarkupInfo.Background := RGBToColor(236, 239, 241);

    PageProvider := TSynGutterLOvProviderCurrentPage.Create(OverviewGutter.Providers);
    PageProvider.Color := RGBToColor(176, 190, 197);
    PageProvider.Priority := 1;

    DiffProvider := TGitDiffOverviewProvider.Create(OverviewGutter.Providers);
    DiffProvider.ColorAdded := RGBToColor(76, 175, 80);
    DiffProvider.ColorRemoved := RGBToColor(229, 57, 53);
    DiffProvider.Priority := 20;
    DiffOverviewProvider := DiffProvider;
  Except
    On E: Exception Do
      Begin
        OverviewGutter := Nil;
        DiffOverviewProvider := Nil;
        WorkflowLogger.Warning('GitDiffView', 'SetupDiffOverviewGutter: ' + E.Message);
      End;
  End;
End;

Procedure TGitDiffView.EnsureDiffOverviewGutter;
Var
  I: Integer;
  StillInstalled: Boolean;
Begin
  { Overview paints on a child TWinControl (not Gutter.Paint). That child only
    gets BoundsRect when the part is Visible and SynEdit has a handle — so we
    reassert size/visibility after every load and after notebook tab shows. }
  If Not Assigned(DiffEditor) Then
    Exit;

  StillInstalled := False;
  If Assigned(OverviewGutter) Then
    For I := 0 To DiffEditor.RightGutter.Parts.Count - 1 Do
      If DiffEditor.RightGutter.Parts[I] = OverviewGutter Then
        Begin
          StillInstalled := True;
          Break;
        End;

  If Not StillInstalled Then
    SetupDiffOverviewGutter;

  DiffEditor.RightGutter.AutoSize := False;
  DiffEditor.RightGutter.Width := OverviewGutterWidth;
  DiffEditor.RightGutter.Visible := True;
  If Assigned(OverviewGutter) Then
    Begin
      OverviewGutter.AutoSize := False;
      OverviewGutter.Width := OverviewGutterWidth;
      { Toggle visibility so GutterVisibilityChanged / DoResize repositions FWinControl. }
      OverviewGutter.Visible := False;
      OverviewGutter.Visible := True;
    End;

  If DiffEditor.HandleAllocated Then
    Begin
      DiffEditor.RightGutter.RecalcBounds;
      DiffEditor.Invalidate;
    End;
End;

Procedure TGitDiffView.ScheduleOverviewRefresh;
Begin
  If Not Assigned(DiffEditor) Then
    Exit;
  { Do not RemoveAsyncCalls — that would cancel scroll-to-change. }
  Application.QueueAsyncCall(@DoRefreshOverviewAsync, 0);
End;

Procedure TGitDiffView.DoRefreshOverviewAsync(Data: PtrInt);
Begin
  If Not IsAlive Then
    Exit;
  EnsureDiffOverviewGutter;
  If Assigned(DiffEditor) And DiffEditor.HandleAllocated Then
    DiffEditor.Invalidate;
End;

Procedure TGitDiffView.RefreshOverviewGutter;
Begin
  EnsureDiffOverviewGutter;
  ScheduleOverviewRefresh;
End;

Function TGitDiffView.ScaleDesign(DesignPx: Integer): Integer;
Var
  PPI: Integer;
Begin
  { Use frame/screen PPI — avoid Scale96ToForm (NeedParentDesignControl can raise
    during frame construction when the IDE restores docked windows at startup). }
  PPI := PixelsPerInch;
  If PPI <= 0 Then
    PPI := Screen.PixelsPerInch;
  If PPI <= 0 Then
    PPI := 96;
  Result := Integer((Int64(DesignPx) * PPI) Div 96);
  If (DesignPx > 0) And (Result < 1) Then
    Result := 1;
End;

Function TGitDiffView.OverviewGutterWidth: Integer;
Begin
  Result := ScaleDesign(16);
End;

Procedure TGitDiffView.ApplyCompactEditorFont;
Begin
  If Not Assigned(DiffEditor) Then
    Exit;
  { Prefer Font.Size (points) over Font.Height (device px). Never assign Height := 0
    (TFont.SetHeight(0) forces Size 0 and can break SynEdit line metrics). }
  Try
    DiffEditor.Font.Size := 9;
    DiffEditor.Font.Pitch := fpFixed;
    DiffEditor.Font.Quality := fqCleartypeNatural;
    {$IFDEF Windows}
    DiffEditor.Font.Name := 'Consolas';
    {$ELSE}
    DiffEditor.Font.Name := 'Courier New';
    {$ENDIF}
    DiffEditor.ExtraLineSpacing := 0;
  Except
    On E: Exception Do
      WorkflowLogger.Warning('GitDiffView', 'ApplyCompactEditorFont: ' + E.Message);
  End;
End;

Function ApplySynEditIDEFont(Editor: TSynEdit; IncludeColors: Boolean): Boolean;
Var
  SourceEdit: TSourceEditorInterface;
  SrcCtl: TWinControl;
  Probe: TSynEdit;
  FontName: String;
  FontSize: Integer;
  FontQuality: TFontQuality;
  FontPitch: TFontPitch;
  FontColor, BgColor: TColor;
  ExtraLine, ExtraChar, TabW: Integer;
Begin
  { Match Lazarus Source Editor font/spacing without calling GetSynEditorSettings
    on Editor (that rewires gutters, mouse actions, and beautifier). Pitch is
    copied so a proportional editor font is not forced onto SynEdit's fpFixed. }
  Result := False;
  If Not Assigned(Editor) Then
    Exit;
  FontName := '';
  FontSize := 0;
  FontQuality := fqDefault;
  FontPitch := fpDefault;
  FontColor := clWindowText;
  BgColor := clWindow;
  ExtraLine := 0;
  ExtraChar := 0;
  TabW := 4;

  { 1) Live source editor — exact attributes the user currently sees. }
  If Assigned(SourceEditorManagerIntf) Then
    Begin
      SourceEdit := SourceEditorManagerIntf.ActiveEditor;
      If Not Assigned(SourceEdit) And (SourceEditorManagerIntf.SourceEditorCount > 0) Then
        SourceEdit := SourceEditorManagerIntf.SourceEditors[0];
      If Assigned(SourceEdit) Then
        Begin
          SrcCtl := SourceEdit.EditorControl;
          If SrcCtl Is TSynEdit Then
            Begin
              FontName := TSynEdit(SrcCtl).Font.Name;
              FontSize := TSynEdit(SrcCtl).Font.Size;
              FontQuality := TSynEdit(SrcCtl).Font.Quality;
              FontPitch := TSynEdit(SrcCtl).Font.Pitch;
              FontColor := TSynEdit(SrcCtl).Font.Color;
              BgColor := TSynEdit(SrcCtl).Color;
              ExtraLine := TSynEdit(SrcCtl).ExtraLineSpacing;
              ExtraChar := TSynEdit(SrcCtl).ExtraCharSpacing;
              TabW := TSynEdit(SrcCtl).TabWidth;
              Result := (Trim(FontName) <> '') And (FontSize <> 0);
            End;
        End;
    End;

  { 2) Probe IDE options on a throwaway SynEdit, then copy font metrics only. }
  If (Not Result) And Assigned(IDEEditorOptions) Then
    Begin
      Probe := TSynEdit.Create(Nil);
      Try
        Try
          IDEEditorOptions.GetSynEditorSettings(Probe);
          FontName := Probe.Font.Name;
          FontSize := Probe.Font.Size;
          FontQuality := Probe.Font.Quality;
          FontPitch := Probe.Font.Pitch;
          FontColor := Probe.Font.Color;
          BgColor := Probe.Color;
          ExtraLine := Probe.ExtraLineSpacing;
          ExtraChar := Probe.ExtraCharSpacing;
          TabW := Probe.TabWidth;
          Result := (Trim(FontName) <> '') And (FontSize <> 0);
        Except
          On E: Exception Do
            WorkflowLogger.Warning('EditorFont', 'IDE font probe failed: ' + E.Message);
        End;
      Finally
        Probe.Free;
      End;
    End;

  If Not Result Then
    Exit;

  Try
    Editor.Font.BeginUpdate;
    Try
      { Size before Name — same order as TEditorOptions.ApplyFontSettingsTo. }
      Editor.Font.Size := FontSize;
      Editor.Font.Name := FontName;
      Editor.Font.Quality := FontQuality;
      Editor.Font.Pitch := FontPitch;
      Editor.Font.Style := [];
      If IncludeColors Then
        Editor.Font.Color := FontColor;
    Finally
      Editor.Font.EndUpdate;
    End;
    If IncludeColors Then
      Editor.Color := BgColor;
    Editor.ExtraLineSpacing := ExtraLine;
    Editor.ExtraCharSpacing := ExtraChar;
    If TabW > 0 Then
      Editor.TabWidth := TabW;
  Except
    On E: Exception Do
      Begin
        Result := False;
        WorkflowLogger.Warning('EditorFont', 'ApplySynEditIDEFont: ' + E.Message);
      End;
  End;
End;

Procedure TGitDiffView.ApplyIDEEditorFont;
Begin
  If Not Assigned(DiffEditor) Then
    Exit;
  If Not ApplySynEditIDEFont(DiffEditor, True) Then
    ApplyCompactEditorFont;
End;

Procedure TGitDiffView.HookEditorOptionsChanged;
Begin
  If FEditorOptsHooked Then
    Exit;
  If Not Assigned(SourceEditorManagerIntf) Then
    Exit;
  Try
    SourceEditorManagerIntf.RegisterChangeEvent(semEditorOptsChanged, @EditorOptionsChanged);
    FEditorOptsHooked := True;
  Except
    On E: Exception Do
      WorkflowLogger.Warning('GitDiffView', 'HookEditorOptionsChanged: ' + E.Message);
  End;
End;

Procedure TGitDiffView.UnhookEditorOptionsChanged;
Begin
  If Not FEditorOptsHooked Then
    Exit;
  FEditorOptsHooked := False;
  If Not Assigned(SourceEditorManagerIntf) Then
    Exit;
  Try
    SourceEditorManagerIntf.UnRegisterChangeEvent(semEditorOptsChanged, @EditorOptionsChanged);
  Except
  End;
End;

Procedure TGitDiffView.EditorOptionsChanged(Sender: TObject);
Begin
  If Not IsAlive Then
    Exit;
  Try
    ApplyIDEEditorFont;
    EnsureDiffOverviewGutter;
    If Assigned(DiffEditor) And DiffEditor.HandleAllocated Then
      DiffEditor.Invalidate;
  Except
    On E: Exception Do
      WorkflowLogger.Warning('GitDiffView', 'EditorOptionsChanged: ' + E.Message);
  End;
End;

Procedure TGitDiffView.ApplyIDEEditorAppearance;
Begin
  If Not Assigned(DiffEditor) Then
    Exit;

  { Font/spacing from IDE (or live Source Editor). Do not call
    GetSynEditorSettings on DiffEditor itself — it rewires gutters/mouse/beautifier
    and has crashed IDE desktop restore when applied too early. }
  ApplyIDEEditorFont;
  If Not FAppearanceReady Then
    Begin
      If Assigned(DiffHighlighter) Then
        Try
          ConfigureDiffColors(DiffHighlighter);
        Except
        End;
      If Assigned(MixedHigh) Then
        Try
          ConfigureDiffColors(TSynDiffSyn(MixedHigh));
        Except
        End;
      SetupDiffOverviewGutter;
      HookEditorOptionsChanged;
      FAppearanceReady := True;
    End;

  Try
    DiffEditor.ReadOnly := True;
    DiffEditor.WantTabs := True;
    DiffEditor.Options := DiffEditor.Options - [eoShowSpecialChars];
    EnsureEditorKeystrokes;
    DiffEditor.OnDblClick := @EditDblClick;
    DiffEditor.OnMouseDown := @EditMouseDown;
    DiffEditor.OnMouseMove := @EditMouseMove;
    DiffEditor.OnMouseUp := @EditMouseUp;
    DiffEditor.OnSpecialLineColors := @EditSpecialLineColors;
    DiffEditor.UnRegisterStatusChangedHandler(@EditStatusChange);
    DiffEditor.RegisterStatusChangedHandler(@EditStatusChange, [scSelection, scCaretX, scCaretY]);
    DiffEditor.UnRegisterPaintEventHandler(@EditPaintEvent);
    DiffEditor.RegisterPaintEventHandler(@EditPaintEvent, [peAfterPaint]);
    ApplyEditorSelectionPolicy;
    EnsureDiffOverviewGutter;
  Except
    On E: Exception Do
      WorkflowLogger.Warning('GitDiffView', 'ApplyIDEEditorAppearance wire: ' + E.Message);
  End;
End;

Procedure TGitDiffView.ClearDisplayMap;
Begin
  FUseDisplayMap := False;
  SetLength(FDisplayToFull, 0);
  If Assigned(HunkStartLines) Then
    HunkStartLines.Clear;
End;

Procedure TGitDiffView.RebuildVisualHunkStarts;
Const
  HunkContextGap = 6; { unchanged context lines that separate visual hunks }
Var
  LineNo, ContextRun: Integer;
  LineText: String;
  NeedNewHunk: Boolean;
Begin
  If Assigned(HunkStartLines) Then
    HunkStartLines.Clear;
  If (Not Assigned(DiffEditor)) Or (Not Assigned(HunkStartLines)) Or (DiffEditor.Lines.Count = 0) Then
    Exit;

  ContextRun := HunkContextGap; { first change always starts a hunk }
  NeedNewHunk := True;
  For LineNo := 1 To DiffEditor.Lines.Count Do
    Begin
      LineText := DiffEditor.Lines[LineNo - 1];
      If IsDiffChangeLine(LineText) Then
        Begin
          If NeedNewHunk Or (ContextRun >= HunkContextGap) Then
            HunkStartLines.Add(LineNo);
          ContextRun := 0;
          NeedNewHunk := False;
        End
      Else
        Inc(ContextRun);
    End;
End;

Function TGitDiffView.IsVisualHunkStart(LineNo: Integer): Boolean;
Begin
  Result := Assigned(HunkStartLines) And (HunkStartLines.IndexOf(LineNo) >= 0);
End;

Procedure TGitDiffView.SetEditorDiffText(Const DiffText: String; HideFileHeaders: Boolean);
Var
  Full, Display: TStringList;
  I, FullLineNo: Integer;
  Line: String;
Begin
  ClearDisplayMap;
  If Not Assigned(DiffEditor) Then
    Exit;
  If Not HideFileHeaders Then
    Begin
      DiffEditor.Lines.Text := DiffText;
      RebuildVisualHunkStarts;
      Exit;
    End;

  Full := TStringList.Create;
  Display := TStringList.Create;
  Try
    Full.Text := DiffText;
    SetLength(FDisplayToFull, Full.Count);
    For I := 0 To Full.Count - 1 Do
      Begin
        Line := Full[I];
        FullLineNo := I + 1;
        { Drop file meta and git @@ headers — visual rules mark hunks instead. }
        If LineIsDiffFileMeta(Line) Or LineIsHunkHeader(Line) Then
          Continue;
        Display.Add(Line);
        FDisplayToFull[Display.Count - 1] := FullLineNo;
      End;
    SetLength(FDisplayToFull, Display.Count);
    FUseDisplayMap := True;
    DiffEditor.Lines.Assign(Display);
    RebuildVisualHunkStarts;
  Finally
    Display.Free;
    Full.Free;
  End;
End;

Function TGitDiffView.FullLineIsSelected(FullLineNo: Integer): Boolean;
Var
  I, Disp: Integer;
Begin
  Result := False;
  If Not FUseDisplayMap Then
    Exit(IsLineSelected(FullLineNo));
  For I := 0 To SelectedLines.Count - 1 Do
    Begin
      Disp := SelectedLines[I];
      If (Disp >= 1) And (Disp <= Length(FDisplayToFull)) And
         (FDisplayToFull[Disp - 1] = FullLineNo) Then
        Exit(True);
    End;
End;

Function TGitDiffView.IsHunkHeaderLine(Const Line: String): Boolean;
Begin
  Result := LineIsHunkHeader(Line);
End;

Function TGitDiffView.IsDiffFileMetaLine(Const Line: String): Boolean;
Begin
  Result := LineIsDiffFileMeta(Line);
End;

Function TGitDiffView.LinePixelTop(LineNo: Integer; Out Y: Integer): Boolean;
Var
  Scr: TPoint;
Begin
  Result := False;
  Y := 0;
  If (Not Assigned(DiffEditor)) Or (LineNo < 1) Or (LineNo > DiffEditor.Lines.Count) Then
    Exit;
  Scr := DiffEditor.TextXYToScreenXY(Point(1, LineNo));
  If Scr.Y < 1 Then
    Exit;
  Y := DiffEditor.ScreenXYToPixels(Scr).Y;
  If (Y + DiffEditor.LineHeight < 0) Or (Y > DiffEditor.ClientHeight) Then
    Exit;
  Result := True;
End;

Function TGitDiffView.HunkMarkerRect(LineNo: Integer): TRect;
Var
  Y, GutterW, MarkerW, RectH, TriH, LeftPad: Integer;
Begin
  { Marker sits at the left of the gutter (before line numbers). Base on the rule line.
    Triangle height = half width so the sides are true 45° (smooth staircase pixels). }
  Result := Rect(0, 0, 0, 0);
  MarkerW := ScaleDesign(12);
  If (MarkerW And 1) <> 0 Then
    Inc(MarkerW); { even width keeps a 1px tip on the centre }
  RectH := ScaleDesign(5);
  TriH := MarkerW Div 2;
  LeftPad := ScaleDesign(2);
  If Not LinePixelTop(LineNo, Y) Then
    Exit;
  GutterW := 0;
  If Assigned(DiffEditor) And DiffEditor.Gutter.Visible Then
    GutterW := DiffEditor.Gutter.Width;
  If GutterW < MarkerW + ScaleDesign(4) Then
    Exit;
  Result.Left := LeftPad;
  Result.Right := Result.Left + MarkerW;
  Result.Top := Y; { base of silhouette on the ruled line }
  Result.Bottom := Y + RectH + TriH;
End;

Function TGitDiffView.PointInHunkMarker(X, Y, LineNo: Integer): Boolean;
Var
  R: TRect;
Begin
  R := HunkMarkerRect(LineNo);
  Result := (R.Right > R.Left) And (X >= R.Left) And (X < R.Right) And
    (Y >= R.Top) And (Y < R.Bottom);
End;

Procedure TGitDiffView.PaintHunkDecorations(PaintCanvas: TCanvas);
Var
  I, LineNo, Y, X1, X2, LeftX, RightX, Row, SpanL, SpanR: Integer;
  MarkerW, RectH, TriH: Integer;
  FillCol, EdgeCol: TColor;
Begin
  If (FMode <> dvmEditorOnly) Or (Not Assigned(DiffEditor)) Or (Not Assigned(HunkStartLines)) Then
    Exit;

  MarkerW := ScaleDesign(12);
  If (MarkerW And 1) <> 0 Then
    Inc(MarkerW);
  RectH := ScaleDesign(5);
  TriH := MarkerW Div 2; { 45° sides: one horizontal pixel in per vertical pixel }
  X1 := 0;
  X2 := DiffEditor.ClientWidth;
  If DiffEditor.RightGutter.Visible Then
    X2 := X2 - DiffEditor.RightGutter.Width;

  FillCol := RGBToColor(66, 165, 245);
  EdgeCol := RGBToColor(13, 71, 161);
  PaintCanvas.Pen.Mode := pmCopy;
  PaintCanvas.Pen.Width := 1;
  PaintCanvas.Pen.Style := psSolid;
  PaintCanvas.Brush.Style := bsSolid;

  For I := 0 To HunkStartLines.Count - 1 Do
    Begin
      LineNo := HunkStartLines[I];
      If Not LinePixelTop(LineNo, Y) Then
        Continue;

      { 1px black rule across gutter + text at the visual hunk start. }
      PaintCanvas.Pen.Color := clBlack;
      PaintCanvas.MoveTo(X1, Y);
      PaintCanvas.LineTo(X2, Y);

      { Silhouette drawn as horizontal spans: base rectangle + 45° staircase tip.
        Equal in/out steps avoid the jagged anti-aliased Polygon edges. }
      LeftX := ScaleDesign(2);
      RightX := LeftX + MarkerW;
      PaintCanvas.Brush.Color := FillCol;
      PaintCanvas.Pen.Color := FillCol;
      If RectH > 0 Then
        PaintCanvas.FillRect(Rect(LeftX, Y, RightX, Y + RectH));
      For Row := 0 To TriH - 1 Do
        Begin
          SpanL := LeftX + Row;
          SpanR := RightX - Row;
          If SpanR <= SpanL Then
            Break;
          PaintCanvas.FillRect(Rect(SpanL, Y + RectH + Row, SpanR, Y + RectH + Row + 1));
        End;
      { Crisp 1px outline along the stepped silhouette. }
      PaintCanvas.Pen.Color := EdgeCol;
      PaintCanvas.MoveTo(LeftX, Y);
      PaintCanvas.LineTo(RightX - 1, Y);
      PaintCanvas.LineTo(RightX - 1, Y + RectH - 1);
      For Row := 0 To TriH - 1 Do
        PaintCanvas.Pixels[RightX - 1 - Row, Y + RectH + Row] := EdgeCol;
      For Row := TriH - 1 DownTo 0 Do
        PaintCanvas.Pixels[LeftX + Row, Y + RectH + Row] := EdgeCol;
      PaintCanvas.MoveTo(LeftX, Y + RectH - 1);
      PaintCanvas.LineTo(LeftX, Y);
    End;
End;

Procedure TGitDiffView.EditPaintEvent(Sender: TObject; EventType: TSynPaintEvent;
  Const rcClip: TRect);
Begin
  If EventType <> peAfterPaint Then
    Exit;
  If FMode <> dvmEditorOnly Then
    Exit;
  If Assigned(DiffEditor) Then
    PaintHunkDecorations(DiffEditor.Canvas);
End;

Procedure TGitDiffView.EnsureEditorKeystrokes;
Begin
  If Not Assigned(DiffEditor) Then
    Exit;
  { The .lfm streams Keystrokes = <> and wipes the constructor defaults,
    so Ctrl+C (and the rest) never reach the editor. }
  If DiffEditor.Keystrokes.Count = 0 Then
    DiffEditor.Keystrokes.ResetDefaults;
End;

Procedure TGitDiffView.ApplyEditorSelectionPolicy;
Begin
  If Not Assigned(DiffEditor) Then
    Exit;
  Case FMode Of
    dvmBrowse:
      Begin
        { History: allow drag-select and Ctrl+C of the commit text. }
        DiffEditor.Options := DiffEditor.Options - [eoNoSelection];
        ClearLineSelection(False);
      End;
    dvmEditorOnly:
      Begin
        { Files: no free-range selection; whole change-lines only via click. }
        DiffEditor.Options := DiffEditor.Options + [eoNoSelection];
        DiffEditor.BlockBegin := Point(1, 1);
        DiffEditor.BlockEnd := Point(1, 1);
      End;
  Else
    { Staging tree mode: normal selection for hunk/line stage. }
    DiffEditor.Options := DiffEditor.Options - [eoNoSelection];
  End;
End;

Procedure TGitDiffView.ClearLineSelection(NotifyChange: Boolean);
Begin
  If Assigned(SelectedLines) And (SelectedLines.Count > 0) Then
    Begin
      SelectedLines.Clear;
      If Assigned(DiffEditor) Then
        DiffEditor.Invalidate;
      If NotifyChange Then
        Begin
          UpdateActionEnabled;
          DoSelectionChanged;
        End;
    End
  Else If Assigned(SelectedLines) Then
    SelectedLines.Clear;
End;

Function TGitDiffView.IsLineSelected(LineNo: Integer): Boolean;
Begin
  Result := Assigned(SelectedLines) And (SelectedLines.IndexOf(LineNo) >= 0);
End;

Function TGitDiffView.SelectedLineCount: Integer;
Begin
  If Assigned(SelectedLines) Then
    Result := SelectedLines.Count
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
  For I := 0 To SelectedLines.Count - 1 Do
    Begin
      LineNo := SelectedLines[I];
      If LineNo < FirstLine Then
        FirstLine := LineNo;
      If LineNo > LastLine Then
        LastLine := LineNo;
    End;
  Result := (FirstLine >= 1) And (LastLine >= FirstLine);
End;

Procedure TGitDiffView.AddLineToSelection(LineNo: Integer);
Begin
  If (Not Assigned(SelectedLines)) Or (LineNo < 1) Then
    Exit;
  If IsLineSelected(LineNo) Then
    Exit;
  SelectedLines.Add(LineNo);
End;

Procedure TGitDiffView.ToggleLineSelection(LineNo: Integer);
Var
  Idx: Integer;
Begin
  If Not Assigned(SelectedLines) Then
    Exit;
  Idx := SelectedLines.IndexOf(LineNo);
  If Idx >= 0 Then
    SelectedLines.Delete(Idx)
  Else
    SelectedLines.Add(LineNo);
  If Assigned(DiffEditor) Then
    DiffEditor.Invalidate;
  UpdateActionEnabled;
  DoSelectionChanged;
End;

Procedure TGitDiffView.SelectChangeLinesInRange(StartLine, EndLine: Integer;
  MergeWithSnapshot: Boolean);
Var
  LineNo, Lo, Hi, I: Integer;
  LineText: String;
Begin
  If (Not Assigned(DiffEditor)) Or (Not Assigned(SelectedLines)) Then
    Exit;
  Lo := StartLine;
  Hi := EndLine;
  If Lo > Hi Then
    Begin
      Lo := EndLine;
      Hi := StartLine;
    End;
  If Lo < 1 Then
    Lo := 1;
  If Hi > DiffEditor.Lines.Count Then
    Hi := DiffEditor.Lines.Count;

  SelectedLines.Clear;
  If MergeWithSnapshot And Assigned(LineDragSnapshot) Then
    For I := 0 To LineDragSnapshot.Count - 1 Do
      SelectedLines.Add(LineDragSnapshot[I]);

  For LineNo := Lo To Hi Do
    Begin
      LineText := DiffEditor.Lines[LineNo - 1];
      If IsDiffChangeLine(LineText) Then
        AddLineToSelection(LineNo);
    End;
  DiffEditor.Invalidate;
  UpdateActionEnabled;
  DoSelectionChanged;
End;

Function TGitDiffView.LineAtMouse(X, Y: Integer): Integer;
Var
  Pt: TPoint;
Begin
  Result := 0;
  If Not Assigned(DiffEditor) Then
    Exit;
  Pt := DiffEditor.PixelsToRowColumn(Point(X, Y));
  Result := Pt.Y;
  If (Result < 1) Or (Result > DiffEditor.Lines.Count) Then
    Result := 0;
End;

Procedure TGitDiffView.ApplyDragLineRange(ToLine: Integer);
Begin
  If (Not FLineDragActive) Or (FLineDragAnchor < 1) Or (ToLine < 1) Then
    Exit;
  SelectChangeLinesInRange(FLineDragAnchor, ToLine, FLineDragCtrl);
End;

Procedure TGitDiffView.FreeOwnedLanguageHighlighter;
Begin
  If Assigned(MixedHigh) Then
    TGitMixedDiffHighlighter(MixedHigh).SetLanguageBackend(Nil);
  If Assigned(DiffEditor) And Assigned(OwnedLangHigh) And (DiffEditor.Highlighter = OwnedLangHigh) Then
    DiffEditor.Highlighter := Nil;
  FreeAndNil(OwnedLangHigh);
End;

Procedure TGitDiffView.ApplyDiffHighlighter;
Var
  DiffHL: TSynDiffSyn;
Begin
  If Not Assigned(DiffEditor) Then
    Exit;
  ShowEditorPane;
  FreeOwnedLanguageHighlighter;
  DiffHL := DiffHighlighter;
  If Assigned(MixedHigh) Then
    Begin
      TGitMixedDiffHighlighter(MixedHigh).SetLanguageBackend(Nil);
      DiffHL := TSynDiffSyn(MixedHigh);
    End;
  If Assigned(DiffHL) Then
    Begin
      If Assigned(IDEEditorOptions) Then
        Try
          IDEEditorOptions.GetHighlighterSettings(DiffHL);
        Except
        End;
      DiffEditor.Highlighter := DiffHL;
      ConfigureDiffColors(DiffHL);
    End
  Else
    DiffEditor.Highlighter := Nil;
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
  If Not Assigned(DiffEditor) Then
    Exit;
  ShowEditorPane;
  FreeOwnedLanguageHighlighter;
  HL := TLazEditCustomHighlighter(CreateOwnedLanguageHighlighter(SourceFileName));
  If Assigned(HL) Then
    Begin
      OwnedLangHigh := HL;
      DiffEditor.Highlighter := HL;
    End
  Else
    DiffEditor.Highlighter := Nil;
End;

Procedure TGitDiffView.ApplyMixedDiffHighlighter(Const SourceFileName: String);
Var
  Lang: TLazEditCustomHighlighter;
  Mixed: TGitMixedDiffHighlighter;
Begin
  If Not Assigned(DiffEditor) Then
    Exit;
  ShowEditorPane;
  FreeOwnedLanguageHighlighter;
  If Not Assigned(MixedHigh) Then
    Begin
      ApplyDiffHighlighter;
      Exit;
    End;
  Mixed := TGitMixedDiffHighlighter(MixedHigh);
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
      OwnedLangHigh := Lang;
      Mixed.SetLanguageBackend(Lang);
    End;
  Try
    DiffEditor.Highlighter := Mixed;
  Except
    On E: Exception Do
      Begin
        WorkflowLogger.Warning('GitDiffView', 'Mixed highlighter failed: ' + E.Message);
        Mixed.SetLanguageBackend(Nil);
        FreeAndNil(OwnedLangHigh);
        ApplyDiffHighlighter;
      End;
  End;
End;

Procedure TGitDiffView.ShowEditorPane;
Begin
  If Assigned(PreviewPicture) Then
    PreviewPicture.Clear;
  If Assigned(BinaryLabel) Then
    BinaryLabel.Visible := False;
  If Assigned(ImagePaintBox) Then
    ImagePaintBox.Visible := False;
  If Assigned(PreviewPanel) Then
    Begin
      PreviewPanel.Visible := False;
      PreviewPanel.SendToBack;
    End;
  If Assigned(DiffEditor) Then
    Begin
      DiffEditor.Visible := True;
      DiffEditor.BringToFront;
    End;
End;

Procedure TGitDiffView.ShowBinaryMessage(Const TitleText: String);
Begin
  CancelPendingScroll;
  FDiffText := '';
  FreeOwnedLanguageHighlighter;
  If Assigned(DiffEditor) Then
    Begin
      DiffEditor.Highlighter := Nil;
      DiffEditor.Lines.Clear;
      DiffEditor.Visible := False;
    End;
  If Assigned(PreviewPicture) Then
    PreviewPicture.Clear;
  If TitleText <> '' Then
    TitleLabel.Caption := TitleText;
  If Assigned(ImagePaintBox) Then
    ImagePaintBox.Visible := False;
  If Assigned(BinaryLabel) Then
    Begin
      BinaryLabel.Caption := 'Non-text binary file contents.';
      BinaryLabel.Visible := True;
    End;
  If Assigned(PreviewPanel) Then
    PreviewPanel.Visible := True;
  UpdateActionEnabled;
End;

Function TGitDiffView.TryShowImageFromStream(Const TitleText: String; Stream: TStream): Boolean;
Begin
  Result := False;
  If (Stream = Nil) Or (Stream.Size = 0) Or (Not Assigned(PreviewPicture)) Then
    Exit;
  Stream.Position := 0;
  Try
    PreviewPicture.LoadFromStream(Stream);
  Except
    PreviewPicture.Clear;
    Exit;
  End;
  If (PreviewPicture.Width < 1) Or (PreviewPicture.Height < 1) Then
    Begin
      PreviewPicture.Clear;
      Exit;
    End;
  CancelPendingScroll;
  FDiffText := '';
  FreeOwnedLanguageHighlighter;
  If Assigned(DiffEditor) Then
    Begin
      DiffEditor.Highlighter := Nil;
      DiffEditor.Lines.Clear;
      DiffEditor.Visible := False;
    End;
  If TitleText <> '' Then
    TitleLabel.Caption := TitleText;
  If Assigned(BinaryLabel) Then
    BinaryLabel.Visible := False;
  If Assigned(ImagePaintBox) Then
    Begin
      ImagePaintBox.Visible := True;
      ImagePaintBox.Invalidate;
    End;
  If Assigned(PreviewPanel) Then
    PreviewPanel.Visible := True;
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
  If Not Assigned(ImagePaintBox) Then
    Exit;
  With ImagePaintBox.Canvas Do
    Begin
      Brush.Color := clWindow;
      FillRect(ImagePaintBox.ClientRect);
    End;
  If (Not Assigned(PreviewPicture)) Or (PreviewPicture.Width < 1) Or (PreviewPicture.Height < 1) Then
    Exit;
  BoxW := ImagePaintBox.ClientWidth;
  BoxH := ImagePaintBox.ClientHeight;
  ImgW := PreviewPicture.Width;
  ImgH := PreviewPicture.Height;
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
  ImagePaintBox.Canvas.StretchDraw(Dest, PreviewPicture.Graphic);
End;

Procedure TGitDiffView.ApplyViewMode;
Begin
  If (csLoading in ComponentState) Or (csDestroying in ComponentState) Then
    Exit;
  Try
    { Files tab hosts Stage Selection on its own button bar below the editor. }
    If Assigned(ToolBar) Then
      ToolBar.Visible := FMode = dvmStaging;
    If Assigned(Tree) Then
      Tree.Visible := FMode = dvmStaging;
    If Assigned(FileList) Then
      FileList.Visible := FMode = dvmBrowse;
    If Assigned(TitleLabel) Then
      TitleLabel.Visible := FMode = dvmStaging;
    If Assigned(TreePanel) Then
      TreePanel.Visible := FMode <> dvmEditorOnly;
    If Assigned(Splitter) Then
      Splitter.Visible := FMode <> dvmEditorOnly;
    If Assigned(TreePanel) Then
      Begin
        If FMode = dvmBrowse Then
          TreePanel.Width := ScaleDesign(240)
        Else If FMode = dvmStaging Then
          TreePanel.Width := ScaleDesign(220);
      End;
    ApplyEditorSelectionPolicy;
    If FMode <> dvmEditorOnly Then
      ClearLineSelection(False);
    UpdateActionEnabled;
  Except
    On E: Exception Do
      WorkflowLogger.Warning('GitDiffView', 'ApplyViewMode: ' + E.Message);
  End;
End;

Procedure TGitDiffView.SetViewMode(Mode: TGitDiffViewMode);
Begin
  { Mode/layout only — appearance is deferred via Loaded → DoDeferredInitAsync. }
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
  If Assigned(StageSelectionButton) Then
    Begin
      StageSelectionButton.Enabled := CanStage And HasSel;
      StageSelectionButton.Visible := FMode = dvmStaging;
    End;
  If Assigned(UnstageSelectionButton) Then
    Begin
      UnstageSelectionButton.Enabled := CanUnstage And HasSel;
      UnstageSelectionButton.Visible := FMode = dvmStaging;
    End;
  If Assigned(StageMenuItem) Then
    Begin
      StageMenuItem.Enabled := CanStage And HasSel;
      StageMenuItem.Visible := CanStage Or (FMode = dvmEditorOnly);
    End;
  If Assigned(StageHunkMenuItem) Then
    Begin
      StageHunkMenuItem.Enabled := CanStage;
      StageHunkMenuItem.Visible := CanStage Or (FMode = dvmEditorOnly);
    End;
  If Assigned(UnstageMenuItem) Then
    Begin
      UnstageMenuItem.Enabled := CanUnstage And HasSel;
      UnstageMenuItem.Visible := CanUnstage Or (FMode = dvmEditorOnly);
    End;
  If Assigned(UnstageHunkMenuItem) Then
    Begin
      UnstageHunkMenuItem.Enabled := CanUnstage;
      UnstageHunkMenuItem.Visible := CanUnstage Or (FMode = dvmEditorOnly);
    End;
  If Assigned(SelectHunkMenuItem) Then
    SelectHunkMenuItem.Visible := (FMode = dvmStaging) Or (FMode = dvmEditorOnly);
  If Assigned(CopyMenuItem) Then
    Begin
      CopyMenuItem.Visible := True;
      CopyMenuItem.Enabled := Assigned(DiffEditor) And DiffEditor.SelAvail;
    End;
  If Assigned(CopySeparator) Then
    CopySeparator.Visible := (FMode = dvmStaging) Or (FMode = dvmEditorOnly);
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
    Result := Assigned(DiffEditor) And DiffEditor.SelAvail;
End;

Procedure TGitDiffView.EditSpecialLineColors(Sender: TObject; Line: Integer;
  Var Special: Boolean; Var FG, BG: TColor);
Var
  LineText: String;
  LineSelected: Boolean;
Begin
  Special := False;
  If (Not Assigned(DiffEditor)) Or (Line < 1) Or (Line > DiffEditor.Lines.Count) Then
    Exit;
  LineText := DiffEditor.Lines[Line - 1];
  LineSelected := (FMode = dvmEditorOnly) And IsLineSelected(Line);

  { Selected change lines: classic selection look (blue + white) so they read clearly. }
  If LineSelected And IsDiffChangeLine(LineText) Then
    Begin
      Special := True;
      FG := clWhite;
      BG := RGBToColor(25, 118, 210);
      Exit;
    End;

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

Procedure TGitDiffView.EditMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
Var
  LineNo: Integer;
  LineText: String;
  I: Integer;
Begin
  If FMode = dvmBrowse Then
    Exit;

  If FMode <> dvmEditorOnly Then
    Exit;
  If Button <> mbLeft Then
    Exit;
  If Not Assigned(DiffEditor) Then
    Exit;

  LineNo := LineAtMouse(X, Y);
  If LineNo < 1 Then
    Exit;
  LineText := DiffEditor.Lines[LineNo - 1];

  DiffEditor.CaretY := LineNo;
  DiffEditor.CaretX := 1;

  { Second click of a double-click: select the hunk now and skip drag/toggle
    so MouseUp does not clear the line under the caret. }
  If (ssDouble in Shift) And (FMode = dvmEditorOnly) Then
    Begin
      FLineDragActive := False;
      If Not (ssCtrl in Shift) Then
        SelectHunkAtLine(LineNo)
      Else
        ToggleHunkSelectionAtLine(LineNo);
      Exit;
    End;

  { Hunk marker: click selects hunk; Ctrl+click toggles hunk selection. }
  If FMode = dvmEditorOnly Then
    Begin
      If Assigned(HunkStartLines) Then
        For I := 0 To HunkStartLines.Count - 1 Do
          If PointInHunkMarker(X, Y, HunkStartLines[I]) Then
            Begin
              FLineDragActive := False;
              If ssCtrl in Shift Then
                ToggleHunkSelectionAtLine(HunkStartLines[I])
              Else
                SelectHunkAtLine(HunkStartLines[I]);
              Exit;
            End;
      If IsVisualHunkStart(LineNo) And (X < DiffEditor.Gutter.Width) Then
        Begin
          FLineDragActive := False;
          If ssCtrl in Shift Then
            ToggleHunkSelectionAtLine(LineNo)
          Else
            SelectHunkAtLine(LineNo);
          Exit;
        End;
    End;

  { Drag may start on a context line and still sweep change lines; only change
    lines become the anchor when the press lands on one. }
  FLineDragActive := True;
  FLineDragMoved := False;
  FLineDragCtrl := ssCtrl in Shift;
  FLineDragAnchor := LineNo;
  FLineDragWasSelected := IsDiffChangeLine(LineText) And IsLineSelected(LineNo);
  LineDragSnapshot.Clear;
  If FLineDragCtrl And Assigned(SelectedLines) Then
    For I := 0 To SelectedLines.Count - 1 Do
      LineDragSnapshot.Add(SelectedLines[I]);

  If IsDiffChangeLine(LineText) Then
    Begin
      If Not FLineDragCtrl Then
        Begin
          { Provisional single-line selection; MouseUp may clear if it was a re-click. }
          ClearLineSelection(False);
          AddLineToSelection(LineNo);
          DiffEditor.Invalidate;
          UpdateActionEnabled;
          DoSelectionChanged;
        End;
      { Ctrl: wait for move/up so a plain Ctrl+click can toggle. }
    End
  Else If Not FLineDragCtrl Then
    Begin
      { Press on non-change line without Ctrl: clear selection (drag may re-select). }
      ClearLineSelection(True);
    End;

  If Assigned(DiffEditor) Then
    TControl(DiffEditor).MouseCapture := True;
End;

Procedure TGitDiffView.EditMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
Var
  LineNo: Integer;
Begin
  If (FMode <> dvmEditorOnly) Or (Not FLineDragActive) Then
    Exit;
  If Not (ssLeft in Shift) Then
    Exit;
  LineNo := LineAtMouse(X, Y);
  If LineNo < 1 Then
    Exit;
  If LineNo <> FLineDragAnchor Then
    FLineDragMoved := True;
  If FLineDragMoved Then
    Begin
      DiffEditor.CaretY := LineNo;
      ApplyDragLineRange(LineNo);
    End;
End;

Procedure TGitDiffView.EditMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
Var
  LineNo: Integer;
  LineText: String;
Begin
  If Assigned(DiffEditor) Then
    TControl(DiffEditor).MouseCapture := False;

  If (FMode <> dvmEditorOnly) Or (Not FLineDragActive) Then
    Begin
      FLineDragActive := False;
      Exit;
    End;
  If Button <> mbLeft Then
    Exit;

  LineNo := LineAtMouse(X, Y);
  If LineNo < 1 Then
    LineNo := FLineDragAnchor;

  If FLineDragMoved Then
    Begin
      { Range of change lines already applied during move. }
      ApplyDragLineRange(LineNo);
    End
  Else
    Begin
      { Click without drag. }
      If (LineNo >= 1) And (LineNo <= DiffEditor.Lines.Count) Then
        Begin
          LineText := DiffEditor.Lines[LineNo - 1];
          If IsDiffChangeLine(LineText) Then
            Begin
              If FLineDragCtrl Then
                ToggleLineSelection(LineNo)
              Else If FLineDragWasSelected And (SelectedLineCount <= 1) Then
                ClearLineSelection(True) { plain re-click of a single selected line }
              Else
                Begin
                  { Provisional MouseDown selection, or multi-line from double-click
                    hunk select — leave the selection intact. }
                  UpdateActionEnabled;
                  DoSelectionChanged;
                End;
            End;
        End;
    End;

  FLineDragActive := False;
  FLineDragMoved := False;
  FLineDragAnchor := 0;
  If Assigned(LineDragSnapshot) Then
    LineDragSnapshot.Clear;
End;

Procedure TGitDiffView.ClearTreeData;
Var
  Node: TTreeNode;
  Data: PGitDiffRange;
Begin
  Node := Tree.Items.GetFirstNode;
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
  Tree.Items.Clear;
End;

Procedure TGitDiffView.Clear;
Begin
  CancelPendingScroll;
  FDiffText := '';
  FBrowseSha := '';
  ClearDisplayMap;
  ClearLineSelection(False);
  ShowEditorPane;
  If Assigned(DiffEditor) Then
    DiffEditor.Lines.Clear;
  If Assigned(TitleLabel) Then
    TitleLabel.Caption := 'Diff';
  ClearTreeData;
  FUpdatingList := True;
  Try
    If Assigned(FileList) Then
      FileList.Items.Clear;
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
  If EndLine > DiffEditor.Lines.Count Then
    EndLine := DiffEditor.Lines.Count;
  If DiffEditor.Lines.Count = 0 Then
    Exit;

  DiffEditor.CaretY := StartLine;
  DiffEditor.TopLine := StartLine;
  Y1 := StartLine;
  Y2 := EndLine;
  DiffEditor.BlockBegin := Point(1, Y1);
  If Y2 >= DiffEditor.Lines.Count Then
    DiffEditor.BlockEnd := Point(Length(DiffEditor.Lines[Y2 - 1]) + 1, Y2)
  Else
    DiffEditor.BlockEnd := Point(1, Y2 + 1);
  Try
    DiffEditor.SetFocus;
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
  For I := 0 To DiffEditor.Lines.Count - 1 Do
    If IsDiffChangeLine(DiffEditor.Lines[I]) Then
      Begin
        Line := I + 1;
        Break;
      End;
  If Line < 1 Then
    Begin
      DiffEditor.TopLine := 1;
      Exit;
    End;
  Half := DiffEditor.LinesInWindow Div 2;
  If Half < 1 Then
    Half := 12;
  DiffEditor.CaretY := Line;
  DiffEditor.TopLine := Max(1, Line - Half);
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
  If DiffEditor.SelAvail Then
    Begin
      B := DiffEditor.BlockBegin;
      E := DiffEditor.BlockEnd;
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
  Else If (FMode = dvmStaging) And Assigned(Tree.Selected) Then
    Begin
      R := NodeRange(Tree.Selected);
      FirstLine := R.StartLine;
      LastLine := R.EndLine;
    End
  Else
    Begin
      FirstLine := DiffEditor.CaretY;
      LastLine := DiffEditor.CaretY;
    End;
  If FirstLine < 1 Then
    FirstLine := 1;
  If LastLine > DiffEditor.Lines.Count Then
    LastLine := DiffEditor.Lines.Count;
End;

Function TGitDiffView.BuildPartialPatch(FirstLine, LastLine: Integer): String;
Var
  Lines: TStringList;
  SelectedFull: TGitLineNumberList;
  I, Disp: Integer;
  UseLineSet: Boolean;
Begin
  Result := '';
  UseLineSet := (FMode = dvmEditorOnly) And (SelectedLineCount > 0);
  If UseLineSet Then
    Begin
      If Not SelectedLineBounds(FirstLine, LastLine) Then
        Exit;
    End
  Else If (FirstLine < 1) Or (LastLine < FirstLine) Then
    Exit;
  If (Not Assigned(DiffEditor)) Or ((Not FUseDisplayMap) And (DiffEditor.Lines.Count = 0)) Then
    Exit;
  If FUseDisplayMap And (Trim(FDiffText) = '') Then
    Exit;

  Lines := TStringList.Create;
  SelectedFull := Nil;
  Try
    If FUseDisplayMap Then
      Lines.Text := FDiffText
    Else
      Lines.Assign(DiffEditor.Lines);
    If UseLineSet Then
      Begin
        SelectedFull := TGitLineNumberList.Create;
        If FUseDisplayMap Then
          Begin
            For I := 0 To SelectedLines.Count - 1 Do
              Begin
                Disp := SelectedLines[I];
                If (Disp >= 1) And (Disp <= Length(FDisplayToFull)) Then
                  SelectedFull.Add(FDisplayToFull[Disp - 1]);
              End;
          End
        Else
          For I := 0 To SelectedLines.Count - 1 Do
            SelectedFull.Add(SelectedLines[I]);
      End;
    Result := BuildGitPartialPatch(Lines, FirstLine, LastLine, SelectedFull);
  Finally
    SelectedFull.Free;
    Lines.Free;
  End;
End;

Function TGitDiffView.FindHunkBounds(AtLine: Integer; Out FirstLine, LastLine: Integer): Boolean;
Var
  I, Count, StartLine, NextStart: Integer;
  Line: String;
Begin
  Result := False;
  FirstLine := 0;
  LastLine := 0;
  If Not Assigned(DiffEditor) Then
    Exit;
  Count := DiffEditor.Lines.Count;
  If (AtLine < 1) Or (AtLine > Count) Then
    Exit;

  { Files tab: visual hunks = change groups separated by 6+ context lines. }
  If (FMode = dvmEditorOnly) And Assigned(HunkStartLines) And (HunkStartLines.Count > 0) Then
    Begin
      FirstLine := 0;
      For I := 0 To HunkStartLines.Count - 1 Do
        Begin
          StartLine := HunkStartLines[I];
          If StartLine <= AtLine Then
            FirstLine := StartLine
          Else
            Break;
        End;
      If FirstLine < 1 Then
        Exit;
      LastLine := Count;
      For I := 0 To HunkStartLines.Count - 1 Do
        Begin
          NextStart := HunkStartLines[I];
          If NextStart > FirstLine Then
            Begin
              LastLine := NextStart - 1;
              Break;
            End;
        End;
      Result := LastLine >= FirstLine;
      Exit;
    End;

  { Staging / History-style: git @@ headers. }
  I := AtLine;
  While I >= 1 Do
    Begin
      Line := DiffEditor.Lines[I - 1];
      If Copy(Line, 1, 2) = '@@' Then
        Begin
          FirstLine := I;
          Break;
        End;
      If Copy(Line, 1, 11) = 'diff --git ' Then
        Exit;
      Dec(I);
    End;
  If FirstLine < 1 Then
    Exit;
  LastLine := Count;
  For I := FirstLine + 1 To Count Do
    Begin
      Line := DiffEditor.Lines[I - 1];
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

Function TGitDiffView.ToggleHunkSelectionAtLine(AtLine: Integer): Boolean;
Var
  FirstLine, LastLine, LineNo, I, Idx: Integer;
  LineText: String;
  AllSelected: Boolean;
  ChangeLines: TGitLineNumberList;
Begin
  { Ctrl+click on a hunk marker: if every change line in the hunk is selected,
    remove them; otherwise add all of them without clearing other selection. }
  Result := FindHunkBounds(AtLine, FirstLine, LastLine);
  If Not Result Then
    Exit;
  If FMode <> dvmEditorOnly Then
    Begin
      SelectHunkAtLine(AtLine);
      Exit;
    End;
  If (Not Assigned(DiffEditor)) Or (Not Assigned(SelectedLines)) Then
    Exit(False);

  ChangeLines := TGitLineNumberList.Create;
  Try
    For LineNo := FirstLine To LastLine Do
      Begin
        If (LineNo < 1) Or (LineNo > DiffEditor.Lines.Count) Then
          Continue;
        LineText := DiffEditor.Lines[LineNo - 1];
        If IsDiffChangeLine(LineText) Then
          ChangeLines.Add(LineNo);
      End;
    If ChangeLines.Count = 0 Then
      Exit(False);

    AllSelected := True;
    For I := 0 To ChangeLines.Count - 1 Do
      If Not IsLineSelected(ChangeLines[I]) Then
        Begin
          AllSelected := False;
          Break;
        End;

    If AllSelected Then
      Begin
        For I := 0 To ChangeLines.Count - 1 Do
          Begin
            Idx := SelectedLines.IndexOf(ChangeLines[I]);
            If Idx >= 0 Then
              SelectedLines.Delete(Idx);
          End;
      End
    Else
      For I := 0 To ChangeLines.Count - 1 Do
        AddLineToSelection(ChangeLines[I]);

    DiffEditor.Invalidate;
    UpdateActionEnabled;
    DoSelectionChanged;
    Result := True;
  Finally
    ChangeLines.Free;
  End;
End;

Function TGitDiffView.SubmitApplyPatch(Const Patch: String; Reverse: Boolean): Boolean;
Var
  Job: TGitJob;
Begin
  Result := False;
  If (FRepoPath = '') Or (Trim(Patch) = '') Then
    Exit;
  If Not Assigned(GitJobs) Then
    Begin
      MessageDlg('Git job runner is not available.', mtError, [mbOK], 0);
      Exit;
    End;
  If GitJobs.Busy Then
    Begin
      MessageDlg('A Git operation is already running.', mtInformation, [mbOK], 0);
      Exit;
    End;
  Job := TGitJob.Create(gjkApplyPatch);
  Job.RepoPath := FRepoPath;
  Job.PatchText := Patch;
  Job.ReversePatch := Reverse;
  If Reverse Then
    Job.Caption := 'Unstaging selection…'
  Else
    Job.Caption := 'Staging selection…';
  Job.OnFinished := @ApplyPatchFinished;
  Result := GitJobs.Submit(Job);
  If Not Result Then
    MessageDlg('Could not queue Git operation (queue full or runner stopped).', mtWarning, [mbOK], 0);
End;

Procedure TGitDiffView.ApplyPatchFinished(Job: TGitJob);
Begin
  If Not IsAlive Or Not Assigned(Job) Then
    Exit;
  If Job.Cancelled Then
    Exit;
  If Not Job.Ok Then
    Begin
      If Job.ReversePatch Then
        MessageDlg('Unstage selection failed: ' + Job.ErrorText, mtError, [mbOK], 0)
      Else
        MessageDlg('Stage selection failed: ' + Job.ErrorText, mtError, [mbOK], 0);
      Exit;
    End;
  If Job.ReversePatch Then
    WorkflowLogger.Info('GitDiff', 'Unstaged selection in ' + FRepoPath)
  Else
    WorkflowLogger.Info('GitDiff', 'Staged selection in ' + FRepoPath);
  ClearLineSelection(False);
  DoStatusChanged;
End;

Function TGitDiffView.StageSelection: Boolean;
Var
  FirstLine, LastLine: Integer;
  Patch: String;
Begin
  Result := False;
  If Not CanStageFromPreview Then
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
          If Not FindHunkBounds(DiffEditor.CaretY, FirstLine, LastLine) Then
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
  Result := SubmitApplyPatch(Patch, False);
End;

Function TGitDiffView.UnstageSelection: Boolean;
Var
  FirstLine, LastLine: Integer;
  Patch: String;
Begin
  Result := False;
  If Not CanUnstageFromPreview Then
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
          If Not FindHunkBounds(DiffEditor.CaretY, FirstLine, LastLine) Then
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
  Result := SubmitApplyPatch(Patch, True);
End;

Procedure TGitDiffView.StageSelectionButtonClick(Sender: TObject);
Begin
  StageSelection;
End;

Procedure TGitDiffView.UnstageSelectionButtonClick(Sender: TObject);
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
  If SelectHunkAtLine(DiffEditor.CaretY) Then
    StageSelection
  Else
    MessageDlg('Place the caret inside a change hunk (between @@ markers).', mtInformation, [mbOK], 0);
End;

Procedure TGitDiffView.PopupUnstageHunkClick(Sender: TObject);
Begin
  If SelectHunkAtLine(DiffEditor.CaretY) Then
    UnstageSelection
  Else
    MessageDlg('Place the caret inside a change hunk (between @@ markers).', mtInformation, [mbOK], 0);
End;

Procedure TGitDiffView.PopupSelectHunkClick(Sender: TObject);
Begin
  If Not SelectHunkAtLine(DiffEditor.CaretY) Then
    MessageDlg('Place the caret inside a change hunk (between @@ markers).', mtInformation, [mbOK], 0);
End;

Procedure TGitDiffView.PopupCopyClick(Sender: TObject);
Begin
  If Assigned(DiffEditor) And DiffEditor.SelAvail Then
    DiffEditor.CopyToClipboard;
End;

Procedure TGitDiffView.PopupPopup(Sender: TObject);
Begin
  UpdateActionEnabled;
End;

Procedure TGitDiffView.EditDblClick(Sender: TObject);
Begin
  { Backup for hosts that do not set ssDouble on the second MouseDown.
    Primary path is EditMouseDown with ssDouble so MouseUp cannot unselect. }
  If (FMode = dvmEditorOnly) Or (FMode = dvmStaging) Then
    Begin
      FLineDragActive := False;
      SelectHunkAtLine(DiffEditor.CaretY);
    End;
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

  Procedure CloseHunkAt(EndLine: Integer);
  Begin
    If Assigned(HunkNode) And Assigned(HunkNode.Data) Then
      PGitDiffRange(HunkNode.Data)^.EndLine := EndLine;
    HunkNode := Nil;
  End;

  Procedure CloseFileAt(EndLine: Integer);
  Begin
    CloseHunkAt(EndLine);
    If Assigned(FileNode) And Assigned(FileNode.Data) Then
      PGitDiffRange(FileNode.Data)^.EndLine := EndLine;
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
  Tree.Items.BeginUpdate;
  Try
    ClearTreeData;
    FDiffText := DiffText;
    DiffEditor.Lines.Text := DiffText;

    Lines := TStringList.Create;
    Try
      Lines.Text := DiffText;
      Root := Tree.Items.Add(Nil, 'Diff');
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
                  CloseFileAt(LineNo - 1);
                  Path := Trim(Copy(Line, 12, MaxInt));
                  If Pos(' b/', Path) > 0 Then
                    Path := Copy(Path, Pos(' b/', Path) + 3, MaxInt)
                  Else If Pos(' ', Path) > 0 Then
                    Path := Copy(Path, Pos(' ', Path) + 1, MaxInt);
                  If (Length(Path) > 2) And (Copy(Path, 1, 2) = 'a/') Then
                    Path := Copy(Path, 3, MaxInt);
                  FileRange := NewRange(LineNo, Path, Path);
                  FileNode := Tree.Items.AddChild(Root, Path);
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
                      FileNode := Tree.Items.AddChild(Root, Path);
                      FileNode.Data := FileRange;
                      InFile := True;
                    End;
                End;
            End
          Else If Copy(Line, 1, 2) = '@@' Then
            Begin
              CloseHunkAt(LineNo - 1);
              If Not Assigned(FileNode) Then
                Begin
                  FileRange := NewRange(1, '', 'Changes');
                  FileNode := Tree.Items.AddChild(Root, 'Changes');
                  FileNode.Data := FileRange;
                End;
              HunkRange := NewRange(LineNo, Path, Line);
              HunkNode := Tree.Items.AddChild(FileNode, Line);
              HunkNode.Data := HunkRange;
            End
          Else If Assigned(HunkNode) And ((Copy(Line, 1, 1) = '+') Or (Copy(Line, 1, 1) = '-')) And
                  (Copy(Line, 1, 3) <> '+++') And (Copy(Line, 1, 3) <> '---') Then
            Begin
              LineRange := NewRange(LineNo, Path, Line);
              LineRange^.EndLine := LineNo;
              If Line[1] = '+' Then
                LineNode := Tree.Items.AddChild(HunkNode, '  + ' + Copy(Line, 2, MaxInt))
              Else
                LineNode := Tree.Items.AddChild(HunkNode, '  − ' + Copy(Line, 2, MaxInt));
              LineNode.Data := LineRange;
            End;
        End;

      If Lines.Count > 0 Then
        CloseFileAt(Lines.Count)
      Else
        CloseFileAt(0);
      If Assigned(Root.Data) Then
        PGitDiffRange(Root.Data)^.EndLine := Lines.Count;
      Root.Expand(False);
      If Assigned(Root.GetFirstChild) Then
        Root.GetFirstChild.Expand(False);
    Finally
      Lines.Free;
    End;
  Finally
    Tree.Items.EndUpdate;
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
  DiffEditor.Lines.Clear;
  FDiffText := '';
  If (FileList.ItemIndex < 0) Or (FileList.ItemIndex >= FileList.Items.Count) Then
    Begin
      DiffEditor.Lines.Text := '(select a file)';
      UpdateActionEnabled;
      Exit;
    End;
  Path := FileList.Items[FileList.ItemIndex];
  If (FRepoPath = '') Or (FBrowseSha = '') Or Not Assigned(GitClient) Then
    Begin
      DiffEditor.Lines.Text := '(no repository)';
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
      DiffEditor.Highlighter := Nil;
      DiffEditor.Lines.Text := 'Could not load diff for ' + Path + LineEnding + GitClient.LastError;
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
      DiffEditor.Highlighter := Nil;
      DiffEditor.Lines.Text := '(no textual diff for ' + Path + ')';
    End
  Else
    Begin
      { History shows code lines only — drop diff --git / +++ / --- / @@ headers. }
      ApplyDiffHighlighter;
      SetEditorDiffText(DiffText, True);
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
  EnsureAppearanceReady;
  SetViewMode(dvmEditorOnly);
  CancelPendingScroll;
  If Title <> '' Then
    TitleLabel.Caption := Title;
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
      DiffEditor.Highlighter := Nil;
      DiffEditor.Lines.Text := '(no textual diff)';
      UpdateActionEnabled;
      Exit;
    End;
  ClearLineSelection(False);
  ApplyEditorSelectionPolicy;
  { Text under Diff first, then upgrade to mixed language highlighting.
    Files tab omits file-level meta headers (diff --git / +++ / --- / index). }
  ApplyDiffHighlighter;
  SetEditorDiffText(DiffText, True);
  ApplyMixedDiffHighlighter(SourceFileName);
  EnsureDiffOverviewGutter;
  ScheduleOverviewRefresh;
  Inc(FScrollGeneration);
  Application.QueueAsyncCall(@DoScrollToFirstChangeAsync, FScrollGeneration);
  UpdateActionEnabled;
End;

Procedure TGitDiffView.LoadDiff(Const Title, DiffText: String);
Begin
  EnsureAppearanceReady;
  SetViewMode(dvmStaging);
  ShowEditorPane;
  If Title <> '' Then
    TitleLabel.Caption := Title
  Else
    TitleLabel.Caption := 'Diff';
  ApplyIDEEditorAppearance;
  If Trim(DiffText) = '' Then
    Begin
      Clear;
      DiffEditor.Lines.Text := '(no textual diff)';
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
  EnsureAppearanceReady;
  Clear;
  If Title <> '' Then
    TitleLabel.Caption := Title;
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
    DiffEditor.Highlighter := Nil;
  DiffEditor.Lines.Text := Content;
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
  If (FMode = dvmBrowse) And (FBrowseSha = Sha) And (FRepoPath = ARepoPath) And
     (Sha <> '') And Assigned(FileList) And (FileList.Items.Count > 0) Then
    Begin
      If Title <> '' Then
        TitleLabel.Caption := Title;
      Exit;
    End;
  SetViewMode(dvmBrowse);
  Clear;
  FRepoPath := ARepoPath;
  FBrowseSha := Sha;
  ExpectedSha := Sha;
  If Title <> '' Then
    TitleLabel.Caption := Title
  Else
    TitleLabel.Caption := 'Commit ' + Copy(Sha, 1, 7);
  ApplyIDEEditorAppearance;

  If (ARepoPath = '') Or (Sha = '') Or Not Assigned(GitClient) Then
    Begin
      DiffEditor.Highlighter := Nil;
      DiffEditor.Lines.Text := '(no commit selected)';
      Exit;
    End;

  GitClient.RepoPath := ARepoPath;
  Paths := Nil;
  If Not GitClient.ListCommitPaths(Sha, Paths) Then
    Begin
      If IsAlive And (FBrowseSha = ExpectedSha) Then
        Begin
          DiffEditor.Highlighter := Nil;
          DiffEditor.Lines.Text := 'Could not list commit files: ' + GitClient.LastError;
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
      FileList.Items.Add(Paths[I]);
    If FileList.Items.Count > 0 Then
      FileList.ItemIndex := 0;
  Finally
    FUpdatingList := False;
    Paths.Free;
  End;

  If Not IsAlive Or (FBrowseSha <> ExpectedSha) Then
    Exit;

  If FileList.Items.Count = 0 Then
    Begin
      DiffEditor.Highlighter := Nil;
      DiffEditor.Lines.Text := '(no files changed in this commit)';
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
      If (FileList.ItemIndex >= 0) And (FileList.ItemIndex < FileList.Items.Count) Then
        Result := FileList.Items[FileList.ItemIndex];
      Exit;
    End;
  Node := Tree.Selected;
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
