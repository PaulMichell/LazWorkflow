Unit GitGraphForm;

{ Manage Repository window – virtual commit graph and git tools (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Menus, ActnList, Clipbrd, LCLIntf, LCLType, WorkflowEvents, StatusFooterFrame,
  GitGraphModel, GitDiffView;

Type
  TGitGraphForm = Class(TForm, IWorkflowListener, IGitRepositoryChanged)
    FPages: TPageControl;
    FTabHistory: TTabSheet;
    FTabFiles: TTabSheet;
    FMainPanel: TPanel;
    FGraphHost: TPanel;
    FPaintBox: TPaintBox;
    FScrollBar: TScrollBar;
    FStatusFooter: TStatusFooterFrame;
    FSplitter: TSplitter;
    FDetailPanel: TPanel;
    FHistoryButtons: TPanel;
    FDiffView: TGitDiffView;
    FFilesLeftPanel: TPanel;
    FFilesList: TListBox;
    FFilesBottomBar: TPanel;
    FFilterGroup: TGroupBox;
    FShowUntrackedCheck: TCheckBox;
    FShowCleanCheck: TCheckBox;
    FShowIgnoredCheck: TCheckBox;
    FBtnIgnoreFiles: TButton;
    FFilesSplitter: TSplitter;
    FFilesRightPanel: TPanel;
    FStageButtonsBar: TPanel;
    FBtnStage: TButton;
    FBtnUnstage: TButton;
    FBtnStageAll: TButton;
    FStagedSplitter: TSplitter;
    FStagedPanel: TPanel;
    FStagedLabel: TLabel;
    FStagedList: TListBox;
    FFilesDiffView: TGitDiffView;
    FCommitPanel: TPanel;
    FMessageLabel: TLabel;
    FMessageMemo: TMemo;
    FCommitActions: TPanel;
    FPushCheck: TCheckBox;
    FBtnCommit: TButton;
    FBtnRefreshFiles: TButton;
    FActionList: TActionList;
    FRemotesAction: TAction;
    FFetchAction: TAction;
    FPullAction: TAction;
    FPushAction: TAction;
    FBtnPush: TButton;
    FBtnPull: TButton;
    FBtnFetch: TButton;
    FBtnRemotes: TButton;
    FPopup: TPopupMenu;
    FMiShowCommit: TMenuItem;
    FMiCopySha: TMenuItem;
    FMiSep: TMenuItem;
    FMiCheckout: TMenuItem;
    FMiCreateBranch: TMenuItem;
    Procedure FormCreate(Sender: TObject);
    Procedure FormDestroy(Sender: TObject);
    Procedure FormShow(Sender: TObject);
    Procedure FormKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
    Procedure PaintBoxPaint(Sender: TObject);
    Procedure PaintBoxMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    Procedure PaintBoxMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; Var Handled: Boolean);
    Procedure ScrollBarChange(Sender: TObject);
    Procedure GraphHostResize(Sender: TObject);
    Procedure PagesChange(Sender: TObject);
    Procedure RemotesActionExecute(Sender: TObject);
    Procedure FetchActionExecute(Sender: TObject);
    Procedure PullActionExecute(Sender: TObject);
    Procedure PushActionExecute(Sender: TObject);
    Procedure PopupCopySha(Sender: TObject);
    Procedure PopupCheckout(Sender: TObject);
    Procedure PopupCreateBranch(Sender: TObject);
    Procedure PopupShowCommit(Sender: TObject);
    Procedure FilesListSelectionChange(Sender: TObject; User: Boolean);
    Procedure FilesListDblClick(Sender: TObject);
    Procedure StagedListSelectionChange(Sender: TObject; User: Boolean);
    Procedure StagedListDblClick(Sender: TObject);
    Procedure FileFilterChange(Sender: TObject);
    Procedure BtnIgnoreFilesClick(Sender: TObject);
    Procedure BtnStageClick(Sender: TObject);
    Procedure BtnUnstageClick(Sender: TObject);
    Procedure BtnStageAllClick(Sender: TObject);
    Procedure BtnRefreshFilesClick(Sender: TObject);
    Procedure BtnCommitClick(Sender: TObject);
    Procedure MessageChange(Sender: TObject);
    Procedure FilesDiffStatusChanged(Sender: TObject);
  Private
    FDetailTimer: TTimer;
    FAutoRefreshTimer: TTimer;
    FRepoPath: String;
    FBranch: String;
    FHeadSha: String;
    FClean: Boolean;
    FModel: TGitGraphModel;
    FSelectedIndex: Integer;
    FIndexing: Boolean;
    FDetailLoading: Boolean;
    FIndexThread: TThread;
    FDetailThread: TThread;
    FPendingIndexText: String;
    FPendingIndexOk: Boolean;
    FPendingDetailsText: String;
    FPendingDetailsOk: Boolean;
    FVisibleFirst: Integer;
    FVisibleLast: Integer;
    FLaneColors: Array[0..9] Of TColor;
    FFilesPaths: TStringList;
    FStagedPaths: TStringList;
    Procedure InitLaneColors;
    Procedure DetailTimerTimer(Sender: TObject);
    Procedure AutoRefreshTimerTimer(Sender: TObject);
    Procedure UpdateStatus;
    Procedure RefreshRepositoryInfo;
    Procedure RefreshFilesList;
    Procedure UpdateCommitEnabled;
    Procedure UpdateStageButtonsEnabled;
    Function ListHasSelection(List: TListBox): Boolean;
    Function CollectSelectedPaths(List: TListBox; Paths: TStringList): TStringList;
    Procedure ShowFilesDiff(List: TListBox; Paths: TStringList; StagedSide: Boolean);
    Procedure ApplyIndexLoaded;
    Procedure ApplyDetailsLoaded;
    Procedure StartIndexLoad;
    Procedure ScheduleVisibleDetails;
    Procedure StartDetailLoadIfNeeded;
    Procedure StopIndexThread;
    Procedure StopDetailThread;
    Procedure UpdateScrollRange;
    Procedure GetVisibleRange(Out FirstRow, LastRow: Integer);
    Procedure ShowCommitDetails(Index: Integer);
    Procedure SelectRow(Index: Integer; ScrollIntoView: Boolean);
    Procedure MoveSelection(Delta: Integer);
    Function SelectedSha: String;
    Function ScrollOffset: Integer;
    Function RowAtY(Y: Integer): Integer;
    Function LaneX(Lane: Integer): Integer;
    Function RowMidY(Row: Integer): Integer;
    Function FormatCommitDate(Const CommitTime: Int64): String;
    Function DescribeFileStatus(IndexStatus, WorkTreeStatus: Char): String;
    Function FileStatusPassesFilter(Const StatusText: String): Boolean;
    Procedure QuietRefreshIfChanged;
    Procedure DrawRefCards(Const Refs: String; Var TextX: Integer; RowTop: Integer);
    { IGitRepositoryChanged }
    Procedure RepositoryStateChanged(Const RepoPath: String; NewState: TGitRepositoryState);
    Procedure WorkingTreeChanged(Const RepoPath: String);
    Procedure HeadChanged(Const RepoPath: String; Const NewHeadSha: String);
    Procedure RemoteUpdated(Const RepoPath: String; Const RemoteName: String);
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure BindRepository(Const StartPath: String = '');
    Procedure SetRepository(Const ARepoPath: String);
    Procedure ApplyConfig;
    Procedure ManualRefresh;
    Property RepoPath: String Read FRepoPath;
  End;

Procedure RefreshOpenGitGraphForms;
Procedure ClearOpenGitGraphForms;
Procedure ApplyGitConfigToOpenForms;

Implementation

{$R *.lfm}

Uses
  WorkflowLog, GitService, GitConfig, GitRemotesForm, GitIgnoreForm, LazIDEIntf, ProjectIntf,
  DateUtils, Math, FileUtil, LazFileUtils, StrUtils;

Type
  TGitIndexThread = Class(TThread)
  Private
    FForm: TGitGraphForm;
    FRepoPath: String;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(AForm: TGitGraphForm; Const ARepoPath: String);
  End;

  TGitDetailThread = Class(TThread)
  Private
    FForm: TGitGraphForm;
    FRepoPath: String;
    FShas: TStringList;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(AForm: TGitGraphForm; Const ARepoPath: String; AShas: TStringList);
    Destructor Destroy; Override;
  End;

Constructor TGitIndexThread.Create(AForm: TGitGraphForm; Const ARepoPath: String);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  FForm := AForm;
  FRepoPath := ARepoPath;
End;

Procedure TGitIndexThread.Execute;
Var
  Text: String;
  Ok: Boolean;
  Client: TGitService;
Begin
  Client := TGitService.Create;
  Try
    Ok := Client.FetchRevListParents(FRepoPath, Text);
    If Terminated Or Not Assigned(FForm) Then
      Exit;
    FForm.FPendingIndexOk := Ok;
    FForm.FPendingIndexText := Text;
    If Terminated Or Not Assigned(FForm) Then
      Exit;
    If csDestroying in FForm.ComponentState Then
      Exit;
    Synchronize(@FForm.ApplyIndexLoaded);
  Finally
    Client.Free;
  End;
End;

Constructor TGitDetailThread.Create(AForm: TGitGraphForm; Const ARepoPath: String;
  AShas: TStringList);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  FForm := AForm;
  FRepoPath := ARepoPath;
  FShas := AShas; { takes ownership }
End;

Destructor TGitDetailThread.Destroy;
Begin
  FreeAndNil(FShas);
  Inherited Destroy;
End;

Procedure TGitDetailThread.Execute;
Var
  Text: String;
  Ok: Boolean;
  Client: TGitService;
Begin
  Client := TGitService.Create;
  Try
    Ok := Client.FetchCommitDetails(FRepoPath, FShas, Text);
    If Terminated Or Not Assigned(FForm) Then
      Exit;
    FForm.FPendingDetailsOk := Ok;
    FForm.FPendingDetailsText := Text;
    If Terminated Or Not Assigned(FForm) Then
      Exit;
    If csDestroying in FForm.ComponentState Then
      Exit;
    Synchronize(@FForm.ApplyDetailsLoaded);
  Finally
    Client.Free;
  End;
End;

Function DetectStartPathFromIDE: String;
Var
  Project: TLazProject;
Begin
  Result := '';
  Try
    If Not Assigned(LazarusIDE) Then
      Exit;
    Project := LazarusIDE.ActiveProject;
    If Not Assigned(Project) Or Project.IsVirtual Then
      Exit;
    If Project.ProjectInfoFile <> '' Then
      Result := ExtractFilePath(ExpandFileName(Project.ProjectInfoFile));
    If (Result = '') And Assigned(Project.MainFile) And (Project.MainFile.Filename <> '') Then
      Result := ExtractFilePath(ExpandFileName(Project.MainFile.Filename));
  Except
    { Active project can be half-destroyed during IDE project switch. }
    Result := '';
  End;
End;

Procedure RefreshOpenGitGraphForms;
Var
  I: Integer;
  Form: TCustomForm;
Begin
  For I := Screen.CustomFormCount - 1 DownTo 0 Do
    Begin
      Form := Screen.CustomForms[I];
      If (Form Is TGitGraphForm) And Not (csDestroying in Form.ComponentState) Then
        TGitGraphForm(Form).BindRepository;
    End;
End;

Procedure ClearOpenGitGraphForms;
Var
  I: Integer;
  Form: TCustomForm;
Begin
  For I := Screen.CustomFormCount - 1 DownTo 0 Do
    Begin
      Form := Screen.CustomForms[I];
      If (Form Is TGitGraphForm) And Not (csDestroying in Form.ComponentState) Then
        TGitGraphForm(Form).SetRepository('');
    End;
End;

Procedure ApplyGitConfigToOpenForms;
Var
  I: Integer;
  Form: TCustomForm;
Begin
  For I := Screen.CustomFormCount - 1 DownTo 0 Do
    Begin
      Form := Screen.CustomForms[I];
      If (Form Is TGitGraphForm) And Not (csDestroying in Form.ComponentState) Then
        TGitGraphForm(Form).ApplyConfig;
    End;
End;

Constructor TGitGraphForm.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FClean := True;
  FSelectedIndex := -1;
  FIndexing := False;
  FDetailLoading := False;
  FIndexThread := Nil;
  FDetailThread := Nil;
  FVisibleFirst := 0;
  FVisibleLast := 0;
  FFilesPaths := TStringList.Create;
  FStagedPaths := TStringList.Create;
  FModel := TGitGraphModel.Create;
  InitLaneColors;
  ApplyConfig;
  WorkflowEventBus.AddListener(Self);
End;

Destructor TGitGraphForm.Destroy;
Begin
  If Assigned(FDetailTimer) Then
    FDetailTimer.Enabled := False;
  If Assigned(FAutoRefreshTimer) Then
    FAutoRefreshTimer.Enabled := False;
  { Stop workers before children (diff view async callbacks) are freed. }
  StopDetailThread;
  StopIndexThread;
  If Assigned(FDiffView) Then
    FDiffView.Clear;
  If Assigned(FFilesDiffView) Then
    FFilesDiffView.Clear;
  WorkflowEventBus.RemoveListener(Self);
  FreeAndNil(FFilesPaths);
  FreeAndNil(FStagedPaths);
  FreeAndNil(FModel);
  Inherited Destroy;
End;

Procedure TGitGraphForm.InitLaneColors;
Begin
  FLaneColors[0] := RGBToColor(33, 150, 243);
  FLaneColors[1] := RGBToColor(76, 175, 80);
  FLaneColors[2] := RGBToColor(255, 152, 0);
  FLaneColors[3] := RGBToColor(156, 39, 176);
  FLaneColors[4] := RGBToColor(244, 67, 54);
  FLaneColors[5] := RGBToColor(0, 150, 136);
  FLaneColors[6] := RGBToColor(63, 81, 181);
  FLaneColors[7] := RGBToColor(233, 30, 99);
  FLaneColors[8] := RGBToColor(121, 85, 72);
  FLaneColors[9] := RGBToColor(96, 125, 139);
End;

Procedure TGitGraphForm.FormCreate(Sender: TObject);
Begin
  { Timers stay runtime-created (not useful in the designer). }
  FDetailTimer := TTimer.Create(Self);
  FDetailTimer.Enabled := False;
  FDetailTimer.Interval := 40;
  FDetailTimer.OnTimer := @DetailTimerTimer;

  FAutoRefreshTimer := TTimer.Create(Self);
  FAutoRefreshTimer.Enabled := False;
  FAutoRefreshTimer.OnTimer := @AutoRefreshTimerTimer;

  { ResizeControl is public but not published – cannot stream from the .lfm. }
  If Assigned(FSplitter) And Assigned(FDetailPanel) Then
    FSplitter.ResizeControl := FDetailPanel;

  If Assigned(FDiffView) Then
    FDiffView.SetViewMode(dvmBrowse);
  If Assigned(FFilesDiffView) Then
    Begin
      FFilesDiffView.SetViewMode(dvmEditorOnly);
      FFilesDiffView.OnStatusChanged := @FilesDiffStatusChanged;
    End;
  If Assigned(FShowUntrackedCheck) Then
    FShowUntrackedCheck.Checked := False;
  If Assigned(FShowCleanCheck) Then
    FShowCleanCheck.Checked := False;
  If Assigned(FShowIgnoredCheck) Then
    FShowIgnoredCheck.Checked := False;
  If Assigned(FFilesList) Then
    FFilesList.MultiSelect := True;
  If Assigned(FStagedList) Then
    FStagedList.MultiSelect := True;
  UpdateCommitEnabled;
  UpdateStageButtonsEnabled;

  WorkflowLogger.Info('GitGraph', 'Manage Repository window created');
End;

Procedure TGitGraphForm.FormDestroy(Sender: TObject);
Begin
  WorkflowLogger.Info('GitGraph', 'Manage Repository window destroyed');
End;

Procedure TGitGraphForm.FormShow(Sender: TObject);
Begin
  BindRepository;
  ApplyConfig;
End;

Procedure TGitGraphForm.ApplyConfig;
Begin
  If Not Assigned(GitManagerConfig) Or Not Assigned(FAutoRefreshTimer) Then
    Exit;
  FAutoRefreshTimer.Enabled := False;
  FAutoRefreshTimer.Interval := GitManagerConfig.AutoRefreshSeconds * 1000;
  FAutoRefreshTimer.Enabled := GitManagerConfig.AutoRefresh And (FRepoPath <> '');
End;

Procedure TGitGraphForm.ManualRefresh;
Begin
  WorkflowLogger.Info('GitGraph', 'Manual refresh (F5)');
  BindRepository;
  If Assigned(FPages) And (FPages.ActivePage = FTabFiles) Then
    RefreshFilesList;
End;

Procedure TGitGraphForm.FormKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
Begin
  Case Key Of
    VK_F5:
      Begin
        ManualRefresh;
        Key := 0;
      End;
    VK_UP:
      Begin
        MoveSelection(-1);
        Key := 0;
      End;
    VK_DOWN:
      Begin
        MoveSelection(1);
        Key := 0;
      End;
    VK_RETURN:
      Begin
        If FSelectedIndex >= 0 Then
          ShowCommitDetails(FSelectedIndex);
        Key := 0;
      End;
    VK_PRIOR:
      Begin
        MoveSelection(-(FPaintBox.ClientHeight Div GitGraphRowHeight));
        Key := 0;
      End;
    VK_NEXT:
      Begin
        MoveSelection(FPaintBox.ClientHeight Div GitGraphRowHeight);
        Key := 0;
      End;
  End;
End;

Procedure TGitGraphForm.MoveSelection(Delta: Integer);
Var
  NewIndex: Integer;
Begin
  If FModel.Count = 0 Then
    Exit;
  If FSelectedIndex < 0 Then
    NewIndex := 0
  Else
    NewIndex := FSelectedIndex + Delta;
  If NewIndex < 0 Then
    NewIndex := 0;
  If NewIndex >= FModel.Count Then
    NewIndex := FModel.Count - 1;
  SelectRow(NewIndex, True);
End;

Procedure TGitGraphForm.SelectRow(Index: Integer; ScrollIntoView: Boolean);
Var
  RowTop, RowBottom, ViewH, NewPos: Integer;
Begin
  If (Index < 0) Or (Index >= FModel.Count) Then
    Exit;
  FSelectedIndex := Index;
  If ScrollIntoView Then
    Begin
      ViewH := FPaintBox.ClientHeight;
      RowTop := Index * GitGraphRowHeight;
      RowBottom := RowTop + GitGraphRowHeight;
      If RowTop < ScrollOffset Then
        FScrollBar.Position := RowTop
      Else If RowBottom > ScrollOffset + ViewH Then
        Begin
          NewPos := RowBottom - ViewH;
          If NewPos < 0 Then
            NewPos := 0;
          FScrollBar.Position := NewPos;
        End;
    End;
  ShowCommitDetails(Index);
  FPaintBox.Invalidate;
  If Not FModel.Commit(Index).DetailsLoaded Then
    ScheduleVisibleDetails;
End;

Function TGitGraphForm.SelectedSha: String;
Begin
  Result := '';
  If (FSelectedIndex >= 0) And (FSelectedIndex < FModel.Count) Then
    Result := FModel.Commit(FSelectedIndex).Sha;
End;

Function TGitGraphForm.ScrollOffset: Integer;
Begin
  Result := FScrollBar.Position;
End;

Procedure TGitGraphForm.StopIndexThread;
Begin
  If Assigned(FIndexThread) Then
    Begin
      FIndexThread.Terminate;
      FIndexThread.WaitFor;
      FreeAndNil(FIndexThread);
    End;
  FIndexing := False;
End;

Procedure TGitGraphForm.StopDetailThread;
Begin
  If Assigned(FDetailThread) Then
    Begin
      FDetailThread.Terminate;
      FDetailThread.WaitFor;
      FreeAndNil(FDetailThread);
    End;
  FDetailLoading := False;
End;

Procedure TGitGraphForm.StartIndexLoad;
Begin
  If FRepoPath = '' Then
    Exit;
  StopDetailThread;
  StopIndexThread;
  FIndexing := True;
  FStatusFooter.SetRightText('Indexing…');
  FIndexThread := TGitIndexThread.Create(Self, FRepoPath);
  FIndexThread.Start;
End;

Procedure TGitGraphForm.ApplyIndexLoaded;
Var
  Parsed: Integer;
Begin
  FIndexing := False;
  If (csDestroying in ComponentState) Or Not Assigned(FModel) Or Not Assigned(FDiffView) Then
    Exit;
  If Not FPendingIndexOk Then
    Begin
      If Assigned(FStatusFooter) Then
        FStatusFooter.SetRightText('Index failed');
      WorkflowLogger.Warning('GitGraph', 'rev-list failed for ' + FRepoPath);
      Exit;
    End;

  Parsed := FModel.ParseRevListParents(FPendingIndexText);
  FPendingIndexText := '';
  FSelectedIndex := -1;
  If Parsed > 0 Then
    FSelectedIndex := 0;

  UpdateScrollRange;
  If FSelectedIndex >= 0 Then
    ShowCommitDetails(FSelectedIndex)
  Else
    FDiffView.Clear;

  UpdateStatus;
  If Assigned(FPaintBox) Then
    FPaintBox.Invalidate;
  ScheduleVisibleDetails;
  WorkflowLogger.Info('GitGraph', Format('Indexed %d commits', [Parsed]));
End;

Procedure TGitGraphForm.ApplyDetailsLoaded;
Begin
  FDetailLoading := False;
  If (csDestroying in ComponentState) Or Not Assigned(FModel) Then
    Exit;
  If FPendingDetailsOk Then
    FModel.ApplyDetailsText(FPendingDetailsText);
  FPendingDetailsText := '';
  If (FSelectedIndex >= 0) And (FSelectedIndex < FModel.Count) And
     FModel.Commit(FSelectedIndex).DetailsLoaded Then
    ShowCommitDetails(FSelectedIndex);
  If Assigned(FPaintBox) Then
    FPaintBox.Invalidate;
  { More rows may still be missing after scrolling. }
  ScheduleVisibleDetails;
End;

Procedure TGitGraphForm.GetVisibleRange(Out FirstRow, LastRow: Integer);
Var
  ViewH: Integer;
Begin
  FirstRow := 0;
  LastRow := -1;
  If FModel.Count = 0 Then
    Exit;
  ViewH := FPaintBox.ClientHeight;
  If ViewH < 1 Then
    ViewH := 1;
  FirstRow := ScrollOffset Div GitGraphRowHeight;
  LastRow := (ScrollOffset + ViewH) Div GitGraphRowHeight;
  If FirstRow < 0 Then
    FirstRow := 0;
  If LastRow >= FModel.Count Then
    LastRow := FModel.Count - 1;
End;

Procedure TGitGraphForm.ScheduleVisibleDetails;
Begin
  If FIndexing Or (FRepoPath = '') Or (FModel.Count = 0) Then
    Exit;
  GetVisibleRange(FVisibleFirst, FVisibleLast);
  FDetailTimer.Enabled := False;
  FDetailTimer.Enabled := True;
End;

Procedure TGitGraphForm.DetailTimerTimer(Sender: TObject);
Begin
  FDetailTimer.Enabled := False;
  StartDetailLoadIfNeeded;
End;

Procedure TGitGraphForm.StartDetailLoadIfNeeded;
Var
  First, Last: Integer;
  Shas: TStringList;
  Missing: Integer;
Begin
  If FDetailLoading Or FIndexing Or (FRepoPath = '') Then
    Exit;

  GetVisibleRange(First, Last);
  First := Max(0, First - GitGraphPrefetchRows);
  Last := Min(FModel.Count - 1, Last + GitGraphPrefetchRows);
  Missing := FModel.CollectMissingShas(First, Last, Shas);
  If Missing = 0 Then
    Begin
      Shas.Free;
      Exit;
    End;

  FDetailLoading := True;
  FDetailThread := TGitDetailThread.Create(Self, FRepoPath, Shas);
  FDetailThread.Start;
End;

Procedure TGitGraphForm.UpdateScrollRange;
Var
  ViewH, ContentH, MaxPos: Integer;
Begin
  ViewH := FPaintBox.ClientHeight;
  If ViewH < 1 Then
    ViewH := 1;
  ContentH := FModel.TotalHeight;
  MaxPos := ContentH - ViewH;
  If MaxPos < 0 Then
    MaxPos := 0;
  FScrollBar.Min := 0;
  FScrollBar.SmallChange := GitGraphRowHeight;
  FScrollBar.LargeChange := ViewH;
  { Position runs 0..Max; PageSize 0 avoids platform-specific range quirks. }
  FScrollBar.PageSize := 0;
  FScrollBar.Max := MaxPos;
  If FScrollBar.Position > MaxPos Then
    FScrollBar.Position := MaxPos;
  FScrollBar.Enabled := MaxPos > 0;
End;

Procedure TGitGraphForm.GraphHostResize(Sender: TObject);
Begin
  UpdateScrollRange;
  ScheduleVisibleDetails;
  FPaintBox.Invalidate;
End;

Procedure TGitGraphForm.ScrollBarChange(Sender: TObject);
Begin
  ScheduleVisibleDetails;
  FPaintBox.Invalidate;
End;

Procedure TGitGraphForm.PaintBoxMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; Var Handled: Boolean);
Var
  NewPos, MaxPos, ViewH: Integer;
Begin
  ViewH := FPaintBox.ClientHeight;
  MaxPos := FModel.TotalHeight - ViewH;
  If MaxPos < 0 Then
    MaxPos := 0;
  NewPos := FScrollBar.Position - (WheelDelta Div 120) * GitGraphRowHeight * 3;
  If NewPos < 0 Then
    NewPos := 0;
  If NewPos > MaxPos Then
    NewPos := MaxPos;
  If NewPos <> FScrollBar.Position Then
    FScrollBar.Position := NewPos;
  Handled := True;
End;

Function TGitGraphForm.LaneX(Lane: Integer): Integer;
Begin
  Result := GitGraphLeftMargin + Lane * GitGraphLaneWidth + GitGraphLaneWidth Div 2;
End;

Function TGitGraphForm.RowMidY(Row: Integer): Integer;
Begin
  Result := Row * GitGraphRowHeight + GitGraphRowHeight Div 2 - ScrollOffset;
End;

Function TGitGraphForm.RowAtY(Y: Integer): Integer;
Begin
  If FModel.Count = 0 Then
    Result := -1
  Else
    Begin
      Result := (Y + ScrollOffset) Div GitGraphRowHeight;
      If (Result < 0) Or (Result >= FModel.Count) Then
        Result := -1;
    End;
End;

Function TGitGraphForm.FormatCommitDate(Const CommitTime: Int64): String;
Begin
  If CommitTime <= 0 Then
    Result := '…'
  Else
    Result := FormatDateTime('yyyy-mm-dd hh:nn', UnixToDateTime(CommitTime));
End;

Procedure TGitGraphForm.DrawRefCards(Const Refs: String; Var TextX: Integer; RowTop: Integer);
Type
  TRefKind = (rkLocal, rkRemote, rkTag, rkOther);
Var
  Parts: TStringList;
  I, ArrowPos, CardW, CardH, CardY, PadX: Integer;
  Token, RefName: String;
  Kind: TRefKind;
  Bg, Fg, Border: TColor;
Begin
  If Trim(Refs) = '' Then
    Exit;

  Parts := TStringList.Create;
  Try
    { Manual split – DelimitedText mishandles spaces around commas. }
    Token := Refs;
    While Token <> '' Do
      Begin
        I := Pos(',', Token);
        If I = 0 Then
          Begin
            Parts.Add(Trim(Token));
            Break;
          End;
        Parts.Add(Trim(Copy(Token, 1, I - 1)));
        Token := Copy(Token, I + 1, MaxInt);
      End;

    CardH := 16;
    PadX := 6;
    CardY := RowTop + (GitGraphRowHeight - CardH) Div 2;

    For I := 0 To Parts.Count - 1 Do
      Begin
        Token := Trim(Parts[I]);
        If Token = '' Then
          Continue;

        { HEAD -> main  →  show "main" as local branch }
        ArrowPos := Pos(' -> ', Token);
        If ArrowPos > 0 Then
          Begin
            RefName := Trim(Copy(Token, ArrowPos + 4, MaxInt));
            Kind := rkLocal;
          End
        Else If SameText(Copy(Token, 1, 5), 'tag: ') Then
          Begin
            RefName := Trim(Copy(Token, 6, MaxInt));
            Kind := rkTag;
          End
        Else If SameText(Token, 'HEAD') Then
          Continue { HEAD alone is implied by the tip branch card }
        Else
          Begin
            RefName := Token;
            If Pos('/', RefName) > 0 Then
              Kind := rkRemote
            Else
              Kind := rkLocal;
          End;

        If RefName = '' Then
          Continue;

        Case Kind Of
          rkLocal:
            Begin
              { Gitg-like cool blue local branch chip }
              Bg := RGBToColor(227, 242, 253);
              Fg := RGBToColor(13, 71, 161);
              Border := RGBToColor(66, 165, 245);
            End;
          rkRemote:
            Begin
              { Warm amber remote chip }
              Bg := RGBToColor(255, 243, 224);
              Fg := RGBToColor(230, 81, 0);
              Border := RGBToColor(255, 167, 38);
            End;
          rkTag:
            Begin
              Bg := RGBToColor(243, 229, 245);
              Fg := RGBToColor(106, 27, 154);
              Border := RGBToColor(186, 104, 200);
            End;
        Else
          Begin
            Bg := RGBToColor(245, 245, 245);
            Fg := RGBToColor(66, 66, 66);
            Border := RGBToColor(189, 189, 189);
          End;
        End;

        With FPaintBox.Canvas Do
          Begin
            Font.Size := 8;
            Font.Style := [];
            Font.Color := Fg;
            CardW := TextWidth(RefName) + PadX * 2;
            If CardW < 28 Then
              CardW := 28;

            Brush.Style := bsSolid;
            Brush.Color := Bg;
            Pen.Color := Border;
            Pen.Width := 1;
            { Clean bordered rectangles – RoundRect is jagged on many widgetsets. }
            Rectangle(TextX, CardY, TextX + CardW, CardY + CardH);

            Brush.Style := bsClear;
            TextOut(TextX + PadX, CardY + (CardH - TextHeight(RefName)) Div 2, RefName);
            Brush.Style := bsSolid;
          End;

        TextX := TextX + CardW + 5;
      End;
  Finally
    Parts.Free;
  End;
End;

Procedure TGitGraphForm.PaintBoxPaint(Sender: TObject);
Var
  FirstRow, LastRow, I, TextX, Y, X, Off, SubjectW: Integer;
  C: TGitCommitRec;
  E: TGitGraphEdge;
  Col: TColor;
  LabelText, DateText: String;
Begin
  Off := ScrollOffset;
  With FPaintBox.Canvas Do
    Begin
      Brush.Color := clWindow;
      FillRect(FPaintBox.ClientRect);

      If FIndexing And (FModel.Count = 0) Then
        Begin
          Font.Color := clGrayText;
          Font.Size := 11;
          TextOut(16, 16, 'Indexing commit history…');
          Exit;
        End;

      If FModel.Count = 0 Then
        Begin
          Font.Color := clGrayText;
          Font.Size := 11;
          If FRepoPath = '' Then
            TextOut(16, 16, 'No Git repository detected for the active project')
          Else
            TextOut(16, 16, 'No commits to display');
          Exit;
        End;

      GetVisibleRange(FirstRow, LastRow);
      If LastRow < FirstRow Then
        Exit;

      Pen.Width := 2;
      For I := 0 To FModel.EdgeCount - 1 Do
        Begin
          E := FModel.Edge(I);
          If (E.ChildIndex > LastRow) Or (E.ParentIndex < FirstRow) Then
            Continue;
          Col := FLaneColors[FModel.LaneColorIndex(E.ChildLane)];
          Pen.Color := Col;
          X := LaneX(E.ChildLane);
          If E.ChildLane = E.ParentLane Then
            Line(X, RowMidY(E.ChildIndex), LaneX(E.ParentLane), RowMidY(E.ParentIndex))
          Else
            Begin
              Line(X, RowMidY(E.ChildIndex), X, RowMidY(E.ParentIndex));
              Line(X, RowMidY(E.ParentIndex), LaneX(E.ParentLane), RowMidY(E.ParentIndex));
            End;
        End;

      For I := FirstRow To LastRow Do
        Begin
          C := FModel.Commit(I);
          Y := I * GitGraphRowHeight - Off;

          If I = FSelectedIndex Then
            Begin
              Brush.Color := RGBToColor(227, 242, 253);
              FillRect(Bounds(0, Y, FPaintBox.Width, GitGraphRowHeight));
            End;

          Col := FLaneColors[FModel.LaneColorIndex(C.Lane)];
          X := LaneX(C.Lane);
          Brush.Color := Col;
          Pen.Color := Col;
          Pen.Width := 1;
          Ellipse(X - GitGraphNodeRadius, RowMidY(I) - GitGraphNodeRadius,
            X + GitGraphNodeRadius, RowMidY(I) + GitGraphNodeRadius);

          TextX := FModel.GraphWidth + GitGraphTextGap;
          Brush.Style := bsClear;
          Font.Size := 9;
          Font.Style := [];
          Font.Color := clGrayText;
          DateText := FormatCommitDate(C.CommitTime);
          TextOut(TextX, Y + 3, DateText);

          TextX := TextX + 130;
          Font.Color := clWindowText;
          If C.DetailsLoaded Then
            LabelText := C.Subject
          Else
            LabelText := '…';
          TextOut(TextX, Y + 3, LabelText);
          SubjectW := TextWidth(LabelText);
          TextX := TextX + SubjectW + 8;
          Brush.Style := bsSolid;

          { Branch/tag cards after the subject (Gitg-style chips). }
          If C.DetailsLoaded And (C.Refs <> '') Then
            DrawRefCards(C.Refs, TextX, Y);
        End;
    End;
End;

Procedure TGitGraphForm.PaintBoxMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
Var
  Row: Integer;
Begin
  Row := RowAtY(Y);
  If Row < 0 Then
    Exit;
  SelectRow(Row, False);
  If Button = mbRight Then
    { PopupMenu on the paintbox will show automatically when assigned. };
End;

Procedure TGitGraphForm.ShowCommitDetails(Index: Integer);
Var
  C: TGitCommitRec;
  When: TDateTime;
  I: Integer;
  ParentLine, Header: String;
Begin
  If Not Assigned(FDiffView) Or (csDestroying in ComponentState) Then
    Exit;
  If (Index < 0) Or Not Assigned(FModel) Or (Index >= FModel.Count) Then
    Begin
      FDiffView.Clear;
      Exit;
    End;
  C := FModel.Commit(Index);

  { File list + full-file embedded red/green diff for the selected path. }
  If Assigned(GitClient) And (FRepoPath <> '') And (C.Sha <> '') Then
    Begin
      FDiffView.LoadCommit(FRepoPath, C.Sha, Copy(C.Sha, 1, 7) + '  ' + C.Subject);
      Exit;
    End;

  Header := 'Commit:  ' + C.Sha + LineEnding;
  If C.DetailsLoaded Then
    Begin
      Header := Header + 'Author:  ' + C.Author + LineEnding;
      If C.CommitTime > 0 Then
        Begin
          When := UnixToDateTime(C.CommitTime);
          Header := Header + 'Date:    ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', When) + LineEnding;
        End;
    End
  Else
    Header := Header + '(loading details…)' + LineEnding;
  If C.ParentCount > 0 Then
    Begin
      ParentLine := C.Parents[0];
      For I := 1 To C.ParentCount - 1 Do
        ParentLine := ParentLine + ' ' + C.Parents[I];
      Header := Header + 'Parents: ' + ParentLine + LineEnding;
    End;
  If C.DetailsLoaded And (C.Refs <> '') Then
    Header := Header + 'Refs:    ' + C.Refs + LineEnding;
  If C.DetailsLoaded Then
    Header := Header + LineEnding + C.Subject;
  FDiffView.LoadPlainText(Copy(C.Sha, 1, 7), Header);
End;

Procedure TGitGraphForm.PagesChange(Sender: TObject);
Begin
  If Assigned(FPages) And (FPages.ActivePage = FTabFiles) Then
    RefreshFilesList;
End;

Function TGitGraphForm.DescribeFileStatus(IndexStatus, WorkTreeStatus: Char): String;
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

Function TGitGraphForm.FileStatusPassesFilter(Const StatusText: String): Boolean;
Begin
  { Optional categories are hidden unless their filter checkbox is checked. }
  If StatusText = 'untracked' Then
    Result := Assigned(FShowUntrackedCheck) And FShowUntrackedCheck.Checked
  Else If StatusText = 'clean' Then
    Result := Assigned(FShowCleanCheck) And FShowCleanCheck.Checked
  Else If StatusText = 'ignored' Then
    Result := Assigned(FShowIgnoredCheck) And FShowIgnoredCheck.Checked
  Else
    Result := True;
End;

Procedure TGitGraphForm.RefreshFilesList;
Var
  AllFiles, StatusMap, FullyStaged: TStringList;
  Entries: TGitStatusEntryArray;
  I: Integer;
  FullPath, Rel, Root, StatusText: String;
  Idx: Integer;
  EntryStatus: String;
Begin
  If Not Assigned(FFilesList) Or Not Assigned(FStagedList) Then
    Exit;

  FFilesList.Items.BeginUpdate;
  FStagedList.Items.BeginUpdate;
  Try
    FFilesList.Items.Clear;
    FStagedList.Items.Clear;
    FFilesPaths.Clear;
    FStagedPaths.Clear;

    If (FRepoPath = '') Or Not DirectoryExists(FRepoPath) Then
      Begin
        FFilesList.Items.Add('(no repository)');
        UpdateCommitEnabled;
        UpdateStageButtonsEnabled;
        Exit;
      End;

    Root := IncludeTrailingPathDelimiter(ExpandFileName(FRepoPath));
    StatusMap := TStringList.Create;
    FullyStaged := TStringList.Create;
    AllFiles := TStringList.Create;
    Try
      StatusMap.Sorted := True;
      StatusMap.Duplicates := dupIgnore;
      StatusMap.CaseSensitive := FileNameCaseSensitive;
      FullyStaged.Sorted := True;
      FullyStaged.Duplicates := dupIgnore;
      FullyStaged.CaseSensitive := FileNameCaseSensitive;

      If Assigned(GitClient) Then
        Begin
          GitClient.RepoPath := FRepoPath;
          { Include ignored paths so the Ignored filter can show them. }
          If GitClient.ListStatus(Entries) Then
            For I := 0 To High(Entries) Do
              Begin
                Rel := StringReplace(Entries[I].Path, '\', '/', [rfReplaceAll]);
                EntryStatus := DescribeFileStatus(Entries[I].IndexStatus, Entries[I].WorkTreeStatus);
                StatusMap.Values[Rel] := EntryStatus;
                If GitStatusEntryIsStaged(Entries[I]) Then
                  Begin
                    FStagedList.Items.Add(GitStatusEntryLabel(Entries[I], True) + Rel);
                    FStagedPaths.Add(Rel);
                    { Fully staged (no remaining worktree change) leave the left list. }
                    If Not GitStatusEntryIsUnstaged(Entries[I]) Then
                      FullyStaged.Add(Rel);
                  End;
              End;
        End;

      AllFiles.Sorted := True;
      AllFiles.Duplicates := dupIgnore;
      FindAllFiles(AllFiles, FRepoPath, '*', True);
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
          FFilesList.Items.Add(Rel + '  ' + StatusText);
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
              FFilesList.Items.Add(Rel + '  ' + StatusText);
              FFilesPaths.Add(Rel);
            End;
        End;

      If FFilesList.Items.Count = 0 Then
        FFilesList.Items.Add('(no files)');
    Finally
      AllFiles.Free;
      FullyStaged.Free;
      StatusMap.Free;
    End;
  Finally
    FFilesList.Items.EndUpdate;
    FStagedList.Items.EndUpdate;
  End;

  If Assigned(FStagedLabel) Then
    FStagedLabel.Caption := Format('Staged for commit (%d)', [FStagedPaths.Count]);
  If Assigned(FFilesDiffView) Then
    FFilesDiffView.Clear;
  UpdateCommitEnabled;
  UpdateStageButtonsEnabled;
End;

Function TGitGraphForm.ListHasSelection(List: TListBox): Boolean;
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

Procedure TGitGraphForm.UpdateStageButtonsEnabled;
Begin
  If Assigned(FBtnStage) Then
    FBtnStage.Enabled := ListHasSelection(FFilesList) And (FFilesPaths.Count > 0);
  If Assigned(FBtnUnstage) Then
    FBtnUnstage.Enabled := ListHasSelection(FStagedList) And (FStagedPaths.Count > 0);
End;

Procedure TGitGraphForm.UpdateCommitEnabled;
Var
  CanCommit: Boolean;
Begin
  CanCommit := Assigned(FStagedPaths) And (FStagedPaths.Count > 0) And
    Assigned(FMessageMemo) And (Trim(FMessageMemo.Text) <> '');
  If Assigned(FBtnCommit) Then
    FBtnCommit.Enabled := CanCommit;
End;

Function TGitGraphForm.CollectSelectedPaths(List: TListBox; Paths: TStringList): TStringList;
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

Procedure TGitGraphForm.ShowFilesDiff(List: TListBox; Paths: TStringList; StagedSide: Boolean);
Var
  I: Integer;
  DiffText, Path, Title: String;
Begin
  If Not Assigned(FFilesDiffView) Then
    Exit;
  FFilesDiffView.Clear;
  FFilesDiffView.SetViewMode(dvmEditorOnly);
  FFilesDiffView.SetStagingContext(FRepoPath, StagedSide);
  { Keep editor-only layout after SetStagingContext (which selects staging mode). }
  FFilesDiffView.SetViewMode(dvmEditorOnly);
  If (List = Nil) Or (Paths = Nil) Or Not Assigned(GitClient) Then
    Exit;
  For I := 0 To List.Count - 1 Do
    If List.Selected[I] And (I < Paths.Count) Then
      Begin
        Path := Paths[I];
        If StagedSide Then
          Title := 'Staged: ' + Path
        Else
          Title := 'Working tree: ' + Path;
        GitClient.RepoPath := FRepoPath;
        If GitClient.DiffPath(Path, StagedSide, DiffText) Then
          Begin
            If Trim(DiffText) = '' Then
              FFilesDiffView.LoadPlainText(Title, '(no textual diff for ' + Path + ')')
            Else
              FFilesDiffView.LoadEmbeddedDiff(Title, DiffText);
          End
        Else
          FFilesDiffView.LoadPlainText(Title, 'Diff failed: ' + GitClient.LastError);
        Exit;
      End;
End;

Procedure TGitGraphForm.FilesListSelectionChange(Sender: TObject; User: Boolean);
Begin
  { Keep multi-select on this list; only clear the other list's selection. }
  If Assigned(FStagedList) And ListHasSelection(FStagedList) Then
    FStagedList.ClearSelection;
  ShowFilesDiff(FFilesList, FFilesPaths, False);
  UpdateStageButtonsEnabled;
End;

Procedure TGitGraphForm.FilesListDblClick(Sender: TObject);
Begin
  BtnStageClick(Sender);
End;

Procedure TGitGraphForm.StagedListSelectionChange(Sender: TObject; User: Boolean);
Begin
  If Assigned(FFilesList) And ListHasSelection(FFilesList) Then
    FFilesList.ClearSelection;
  ShowFilesDiff(FStagedList, FStagedPaths, True);
  UpdateStageButtonsEnabled;
End;

Procedure TGitGraphForm.StagedListDblClick(Sender: TObject);
Begin
  BtnUnstageClick(Sender);
End;

Procedure TGitGraphForm.FileFilterChange(Sender: TObject);
Begin
  RefreshFilesList;
End;

Procedure TGitGraphForm.BtnIgnoreFilesClick(Sender: TObject);
Begin
  If FRepoPath = '' Then
    Begin
      MessageDlg('No repository is bound to this window.', mtInformation, [mbOK], 0);
      Exit;
    End;
  If ShowGitIgnoreForm(FRepoPath) Then
    RefreshFilesList;
End;

Procedure TGitGraphForm.BtnStageClick(Sender: TObject);
Var
  Paths: TStringList;
Begin
  If Not Assigned(GitClient) Or (FRepoPath = '') Then
    Exit;
  Paths := CollectSelectedPaths(FFilesList, FFilesPaths);
  Try
    If Paths.Count = 0 Then
      Begin
        MessageDlg('Select one or more files in the file list to stage.', mtInformation, [mbOK], 0);
        Exit;
      End;
    GitClient.RepoPath := FRepoPath;
    If Not GitClient.StagePaths(Paths) Then
      MessageDlg('Stage failed: ' + GitClient.LastError, mtError, [mbOK], 0);
    RefreshFilesList;
  Finally
    Paths.Free;
  End;
End;

Procedure TGitGraphForm.BtnUnstageClick(Sender: TObject);
Var
  Paths: TStringList;
Begin
  If Not Assigned(GitClient) Or (FRepoPath = '') Then
    Exit;
  Paths := CollectSelectedPaths(FStagedList, FStagedPaths);
  Try
    If Paths.Count = 0 Then
      Begin
        MessageDlg('Select one or more files in the staged list to unstage.', mtInformation, [mbOK], 0);
        Exit;
      End;
    GitClient.RepoPath := FRepoPath;
    If Not GitClient.UnstagePaths(Paths) Then
      MessageDlg('Unstage failed: ' + GitClient.LastError, mtError, [mbOK], 0);
    RefreshFilesList;
  Finally
    Paths.Free;
  End;
End;

Procedure TGitGraphForm.BtnStageAllClick(Sender: TObject);
Begin
  If Not Assigned(GitClient) Or (FRepoPath = '') Then
    Exit;
  GitClient.RepoPath := FRepoPath;
  If Not GitClient.StageAll Then
    MessageDlg('Stage all failed: ' + GitClient.LastError, mtError, [mbOK], 0);
  RefreshFilesList;
End;

Procedure TGitGraphForm.BtnRefreshFilesClick(Sender: TObject);
Begin
  RefreshFilesList;
End;

Procedure TGitGraphForm.MessageChange(Sender: TObject);
Begin
  UpdateCommitEnabled;
End;

Procedure TGitGraphForm.FilesDiffStatusChanged(Sender: TObject);
Begin
  RefreshFilesList;
End;

Procedure TGitGraphForm.BtnCommitClick(Sender: TObject);
Var
  NewSha, Msg: String;
  Summary: TGitTransferSummary;
Begin
  If Not Assigned(GitClient) Or (FRepoPath = '') Then
    Exit;
  Msg := '';
  If Assigned(FMessageMemo) Then
    Msg := Trim(FMessageMemo.Text);
  If Msg = '' Then
    Begin
      MessageDlg('Enter a commit message.', mtWarning, [mbOK], 0);
      Exit;
    End;
  If FStagedPaths.Count = 0 Then
    Begin
      MessageDlg('Stage at least one change before committing.', mtWarning, [mbOK], 0);
      Exit;
    End;

  GitClient.RepoPath := FRepoPath;
  Screen.Cursor := crHourGlass;
  Try
    If Not GitClient.Commit(Msg, NewSha) Then
      Begin
        Screen.Cursor := crDefault;
        MessageDlg('Commit failed: ' + GitClient.LastError, mtError, [mbOK], 0);
        RefreshFilesList;
        Exit;
      End;
  Finally
    Screen.Cursor := crDefault;
  End;

  WorkflowLogger.Info('GitGraph', 'Created commit ' + NewSha);
  If Assigned(FMessageMemo) Then
    FMessageMemo.Clear;
  MessageDlg('Committed ' + Copy(NewSha, 1, 7) + '.', mtInformation, [mbOK], 0);

  If Assigned(FPushCheck) And FPushCheck.Checked Then
    Begin
      Screen.Cursor := crHourGlass;
      Try
        If GitClient.Push(Summary) Then
          Begin
            Screen.Cursor := crDefault;
            MessageDlg(Summary.Message, mtInformation, [mbOK], 0);
          End
        Else
          Begin
            Screen.Cursor := crDefault;
            MessageDlg('Commit succeeded, but push failed:' + LineEnding + Summary.Message,
              mtWarning, [mbOK], 0);
          End;
      Finally
        Screen.Cursor := crDefault;
      End;
    End;

  RefreshFilesList;
  ManualRefresh;
End;

Procedure TGitGraphForm.RemotesActionExecute(Sender: TObject);
Begin
  If FRepoPath = '' Then
    Begin
      MessageDlg('No repository is bound to this window.', mtInformation, [mbOK], 0);
      Exit;
    End;
  ShowGitRemotesForm(FRepoPath);
  ManualRefresh;
End;

Procedure TGitGraphForm.FetchActionExecute(Sender: TObject);
Var
  Summary: TGitTransferSummary;
  Ok: Boolean;
Begin
  If (FRepoPath = '') Or Not Assigned(GitClient) Then
    Exit;
  GitClient.RepoPath := FRepoPath;
  Screen.Cursor := crHourGlass;
  Try
    Ok := GitClient.Fetch(Summary);
  Finally
    Screen.Cursor := crDefault;
  End;
  If Ok Then
    Begin
      MessageDlg(Summary.Message, mtInformation, [mbOK], 0);
      ManualRefresh;
    End
  Else
    MessageDlg(Summary.Message, mtError, [mbOK], 0);
End;

Procedure TGitGraphForm.PullActionExecute(Sender: TObject);
Var
  Summary: TGitTransferSummary;
  Ok: Boolean;
Begin
  If (FRepoPath = '') Or Not Assigned(GitClient) Then
    Exit;
  GitClient.RepoPath := FRepoPath;
  Screen.Cursor := crHourGlass;
  Try
    Ok := GitClient.Pull(Summary);
  Finally
    Screen.Cursor := crDefault;
  End;
  If Ok Then
    Begin
      MessageDlg(Summary.Message, mtInformation, [mbOK], 0);
      ManualRefresh;
    End
  Else
    MessageDlg(Summary.Message, mtError, [mbOK], 0);
End;

Procedure TGitGraphForm.PushActionExecute(Sender: TObject);
Var
  Summary: TGitTransferSummary;
  Ok: Boolean;
Begin
  If (FRepoPath = '') Or Not Assigned(GitClient) Then
    Exit;
  GitClient.RepoPath := FRepoPath;
  Screen.Cursor := crHourGlass;
  Try
    Ok := GitClient.Push(Summary);
  Finally
    Screen.Cursor := crDefault;
  End;
  If Ok Then
    Begin
      MessageDlg(Summary.Message, mtInformation, [mbOK], 0);
      FStatusFooter.SetRightText('Push complete');
    End
  Else
    MessageDlg(Summary.Message, mtError, [mbOK], 0);
End;

Procedure TGitGraphForm.PopupCopySha(Sender: TObject);
Var
  Sha: String;
Begin
  Sha := SelectedSha;
  If Sha <> '' Then
    Clipboard.AsText := Sha;
End;

Procedure TGitGraphForm.PopupShowCommit(Sender: TObject);
Begin
  If FSelectedIndex >= 0 Then
    ShowCommitDetails(FSelectedIndex);
End;

Procedure TGitGraphForm.PopupCheckout(Sender: TObject);
Var
  Sha: String;
Begin
  Sha := SelectedSha;
  If (Sha = '') Or Not Assigned(GitClient) Then
    Exit;
  If MessageDlg('Check out commit ' + Copy(Sha, 1, 7) + '?' + LineEnding +
    'This may detach HEAD.', mtConfirmation, [mbYes, mbNo], 0) <> mrYes Then
    Exit;
  GitClient.RepoPath := FRepoPath;
  If GitClient.Checkout(Sha) Then
    ManualRefresh
  Else
    MessageDlg('Checkout failed. See the log for details.', mtError, [mbOK], 0);
End;

Procedure TGitGraphForm.PopupCreateBranch(Sender: TObject);
Var
  Sha, BranchName: String;
Begin
  Sha := SelectedSha;
  If (Sha = '') Or Not Assigned(GitClient) Then
    Exit;
  BranchName := '';
  If Not InputQuery('Create branch', 'Branch name:', BranchName) Then
    Exit;
  BranchName := Trim(BranchName);
  If BranchName = '' Then
    Exit;
  GitClient.RepoPath := FRepoPath;
  If GitClient.CreateBranch(BranchName, Sha) Then
    Begin
      MessageDlg('Created branch "' + BranchName + '" at ' + Copy(Sha, 1, 7), mtInformation, [mbOK], 0);
      ManualRefresh;
    End
  Else
    MessageDlg('Create branch failed. See the log for details.', mtError, [mbOK], 0);
End;

Procedure TGitGraphForm.AutoRefreshTimerTimer(Sender: TObject);
Begin
  If (csDestroying in ComponentState) Or FIndexing Or FDetailLoading Or Not Visible Then
    Exit;
  QuietRefreshIfChanged;
End;

Procedure TGitGraphForm.QuietRefreshIfChanged;
Var
  Branch, Sha, Porcelain: String;
  Clean: Boolean;
  NeedReload: Boolean;
Begin
  If (FRepoPath = '') Or Not Assigned(GitClient) Then
    Exit;
  GitClient.RepoPath := FRepoPath;
  NeedReload := False;
  If GitClient.GetHeadSha(Sha) Then
    If Sha <> FHeadSha Then
      NeedReload := True;
  If GitClient.GetCurrentBranch(Branch) Then
    If Branch <> FBranch Then
      NeedReload := True;
  If GitClient.GetStatus(Clean, Porcelain) Then
    If Clean <> FClean Then
      NeedReload := True;

  If NeedReload Then
    Begin
      WorkflowLogger.Debug('GitGraph', 'Auto-refresh: repository changed');
      ManualRefresh;
    End
  Else
    Begin
      { Keep dirty flag in sync even when HEAD unchanged. }
      RefreshRepositoryInfo;
      UpdateStatus;
    End;
End;

Procedure TGitGraphForm.UpdateStatus;
Var
  LeftText, CentreText, RightText: String;
  ShortSha: String;
Begin
  If FRepoPath = '' Then
    Begin
      FStatusFooter.SetAll('No repository', '', 'Ready');
      Exit;
    End;

  If FBranch <> '' Then
    LeftText := FBranch
  Else
    LeftText := ExtractFileName(ExcludeTrailingPathDelimiter(FRepoPath));

  ShortSha := FHeadSha;
  If Length(ShortSha) > 7 Then
    ShortSha := Copy(ShortSha, 1, 7);
  If ShortSha <> '' Then
    CentreText := ShortSha + '  ·  ' + FRepoPath
  Else
    CentreText := FRepoPath;

  If FIndexing Then
    RightText := 'Indexing…'
  Else If FModel.Count > 0 Then
    Begin
      RightText := Format('%d commits', [FModel.Count]);
      If FClean Then
        RightText := RightText + ' · Clean'
      Else
        RightText := RightText + ' · Dirty';
    End
  Else If FClean Then
    RightText := 'Clean'
  Else
    RightText := 'Dirty';

  FStatusFooter.SetAll(LeftText, CentreText, RightText);
End;

Procedure TGitGraphForm.RefreshRepositoryInfo;
Var
  Branch, Sha, Porcelain: String;
  Clean: Boolean;
Begin
  FBranch := '';
  FHeadSha := '';
  FClean := True;
  If (FRepoPath = '') Or Not Assigned(GitClient) Then
    Exit;

  GitClient.RepoPath := FRepoPath;
  If GitClient.GetCurrentBranch(Branch) Then
    FBranch := Branch;
  If GitClient.GetHeadSha(Sha) Then
    FHeadSha := Sha;
  If GitClient.GetStatus(Clean, Porcelain) Then
    FClean := Clean;
End;

Procedure TGitGraphForm.BindRepository(Const StartPath: String);
Var
  SearchPath, Found: String;
Begin
  SearchPath := StartPath;
  If SearchPath = '' Then
    SearchPath := DetectStartPathFromIDE;
  If SearchPath = '' Then
    SearchPath := GetCurrentDir;

  Found := '';
  If Assigned(GitClient) And (SearchPath <> '') Then
    Found := GitClient.DetectRepository(SearchPath);

  If Found <> '' Then
    WorkflowLogger.Info('GitGraph', 'Bound repository: ' + Found)
  Else
    WorkflowLogger.Warning('GitGraph', 'No repository found from: ' + SearchPath);

  SetRepository(Found);
End;

Procedure TGitGraphForm.SetRepository(Const ARepoPath: String);
Begin
  If csDestroying in ComponentState Then
    Exit;
  { Tear down workers and pending UI work before swapping repo identity. }
  If Assigned(FDetailTimer) Then
    FDetailTimer.Enabled := False;
  StopDetailThread;
  StopIndexThread;
  If Assigned(FDiffView) Then
    FDiffView.Clear;
  FRepoPath := ARepoPath;
  FSelectedIndex := -1;
  If Assigned(FModel) Then
    FModel.Clear;
  If Assigned(FScrollBar) Then
    FScrollBar.Position := 0;
  If Assigned(GitClient) Then
    GitClient.RepoPath := ARepoPath;
  RefreshRepositoryInfo;
  UpdateScrollRange;
  UpdateStatus;
  If Assigned(FPaintBox) Then
    FPaintBox.Invalidate;
  If FRepoPath <> '' Then
    StartIndexLoad
  Else If Assigned(FFilesList) Then
    FFilesList.Items.Clear;
  If Assigned(FPages) And (FPages.ActivePage = FTabFiles) Then
    RefreshFilesList;
  ApplyConfig;
End;

Procedure TGitGraphForm.RepositoryStateChanged(Const RepoPath: String; NewState: TGitRepositoryState);
Begin
  If SameText(RepoPath, FRepoPath) Then
    BindRepository(FRepoPath);
End;

Procedure TGitGraphForm.WorkingTreeChanged(Const RepoPath: String);
Begin
  If SameText(RepoPath, FRepoPath) Then
    Begin
      RefreshRepositoryInfo;
      UpdateStatus;
      If Assigned(FPages) And (FPages.ActivePage = FTabFiles) Then
        RefreshFilesList;
    End;
End;

Procedure TGitGraphForm.HeadChanged(Const RepoPath: String; Const NewHeadSha: String);
Begin
  If SameText(RepoPath, FRepoPath) Then
    BindRepository(FRepoPath);
End;

Procedure TGitGraphForm.RemoteUpdated(Const RepoPath: String; Const RemoteName: String);
Begin
  If SameText(RepoPath, FRepoPath) Then
    FStatusFooter.SetRightText('Remote ' + RemoteName + ' updated');
End;

End.
