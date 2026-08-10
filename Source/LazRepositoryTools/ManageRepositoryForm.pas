Unit ManageRepositoryForm;

{ Manage Repository window – virtual commit graph and git tools (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Menus, ActnList, Clipbrd, LCLIntf, LCLType, SynEdit, WorkflowEvents, StatusFooterFrame,
  GitGraphModel, GitDiffView;

Type
  { Background Fetch / Pull / Push (History toolbar). }
  TGitRemoteOpKind = (rokFetch, rokPull, rokPush);

  TManageRepositoryForm = Class(TForm, IWorkflowListener, IGitRepositoryChanged)
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
    FRemoteOpBusy: Boolean;
    FRemoteOpSuppressResult: Boolean;
    FIndexThread: TThread;
    FDetailThread: TThread;
    FRemoteOpThread: TThread;
    FPendingIndexText: String;
    FPendingIndexOk: Boolean;
    FPendingDetailsText: String;
    FPendingDetailsOk: Boolean;
    FPendingRemoteOk: Boolean;
    FPendingRemoteMessage: String;
    FPendingRemoteKind: TGitRemoteOpKind;
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
    Function CollectActiveSelectedPaths: TStringList;
    Function FormatPathActionSummary(Const ActionVerb: String; Paths: TStrings): String;
    Function ConfirmPathAction(Const ActionTitle, ActionVerb: String; Paths: TStrings): Boolean;
    Function MovePathToWasteBin(Const FullPath: String; Out ErrorText: String): Boolean;
    Procedure ShowFilesDiff(List: TListBox; Paths: TStringList; StagedSide: Boolean);
    Procedure ApplyIndexLoaded;
    Procedure ApplyDetailsLoaded;
    Procedure ApplyRemoteOpFinished;
    Procedure StartIndexLoad;
    Procedure StartRemoteOp(Kind: TGitRemoteOpKind);
    Procedure SetRemoteActionsEnabled(ActionsEnabled: Boolean);
    Procedure ScheduleVisibleDetails;
    Procedure StartDetailLoadIfNeeded;
    Procedure StopIndexThread;
    Procedure StopDetailThread;
    Procedure StopRemoteOpThread;
    Procedure UpdateScrollRange;
    Procedure GetVisibleRange(Out FirstRow, LastRow: Integer);
    Procedure ShowCommitDetails(Index: Integer);
    Procedure SelectRow(Index: Integer; ScrollIntoView: Boolean);
    Procedure MoveSelection(Delta: Integer);
    Function SelectedSha: String;
    Function ScrollOffset: Integer;
    Function GraphScale(DesignPx: Integer): Integer;
    Function GraphCanMeasureFont: Boolean;
    Function GraphRowHeight: Integer;
    Function GraphLaneWidth: Integer;
    Function GraphLeftMargin: Integer;
    Function GraphNodeRadius: Integer;
    Function GraphTextGap: Integer;
    Function GraphDateColumnWidth: Integer;
    Function GraphContentWidth: Integer;
    Function GraphContentHeight: Integer;
    Procedure PrepareGraphTextFont(ACanvas: TCanvas; IsDate: Boolean);
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
  Published
    { Streamed components — no F prefix; private fields keep F. }
    ActionList: TActionList;
    PushAction: TAction;
    PullAction: TAction;
    FetchAction: TAction;
    RemotesAction: TAction;
    StageAllAction: TAction;
    StageAction: TAction;
    StageSelectionAction: TAction;
    RevertAction: TAction;
    DeleteAction: TAction;
    IgnoreAction: TAction;
    IgnoredFilesAction: TAction;
    SuggestMessageAction: TAction;
    CommitAction: TAction;
    ShowCommitAction: TAction;
    CopyShaAction: TAction;
    CheckoutAction: TAction;
    CreateBranchAction: TAction;
    StatusFooter: TStatusFooterFrame;
    Pages: TPageControl;
    HistoryTab: TTabSheet;
    FilesTab: TTabSheet;
    MainPanel: TPanel;
    DetailPanel: TPanel;
    HistoryButtons: TPanel;
    PushButton: TButton;
    PullButton: TButton;
    FetchButton: TButton;
    RemotesButton: TButton;
    DiffView: TGitDiffView;
    HistorySplitter: TSplitter;
    GraphHost: TPanel;
    GraphScrollBar: TScrollBar;
    GraphPaintBox: TPaintBox;
    FilesLeftPanel: TPanel;
    FilesList: TListBox;
    FilesBottomPanel: TPanel;
    FilterGroupBox: TGroupBox;
    UntrackedCheck: TCheckBox;
    CleanCheck: TCheckBox;
    IgnoredCheck: TCheckBox;
    FilesSplitter: TSplitter;
    FilesRightPanel: TPanel;
    CommitPanel: TPanel;
    MessageLabel: TLabel;
    MessageMemo: TMemo;
    CommitActionsPanel: TPanel;
    CommitButton: TButton;
    SuggestButton: TButton;
    PushCheckBox: TCheckBox;
    CommitSplitter: TSplitter;
    StagedPanel: TPanel;
    StagedLabel: TLabel;
    StagedList: TListBox;
    StagedSplitter: TSplitter;
    StageButtonsPanel: TPanel;
    StageAllButton: TButton;
    StageButton: TButton;
    StageSelectionButton: TButton;
    RevertButton: TButton;
    DeleteButton: TButton;
    IgnoreButton: TButton;
    IgnoredFilesButton: TButton;
    FilesDiffView: TGitDiffView;
    Popup: TPopupMenu;
    ShowCommitMenuItem: TMenuItem;
    CopyShaMenuItem: TMenuItem;
    CopySeparator: TMenuItem;
    CheckoutMenuItem: TMenuItem;
    CreateBranchMenuItem: TMenuItem;
    Procedure FormCreate(Sender: TObject);
    Procedure FormDestroy(Sender: TObject);
    Procedure FormShow(Sender: TObject);
    Procedure FormKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
    Procedure PaintBoxPaint(Sender: TObject);
    Procedure PaintBoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    Procedure PaintBoxMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; Var Handled: Boolean);
    Procedure ScrollBarChange(Sender: TObject);
    Procedure GraphHostResize(Sender: TObject);
    Procedure PagesChange(Sender: TObject);
    Procedure PushActionExecute(Sender: TObject);
    Procedure PullActionExecute(Sender: TObject);
    Procedure FetchActionExecute(Sender: TObject);
    Procedure RemotesActionExecute(Sender: TObject);
    Procedure StageAllActionExecute(Sender: TObject);
    Procedure StageActionExecute(Sender: TObject);
    Procedure StageSelectionActionExecute(Sender: TObject);
    Procedure RevertActionExecute(Sender: TObject);
    Procedure DeleteActionExecute(Sender: TObject);
    Procedure IgnoreActionExecute(Sender: TObject);
    Procedure IgnoredFilesActionExecute(Sender: TObject);
    Procedure SuggestMessageActionExecute(Sender: TObject);
    Procedure CommitActionExecute(Sender: TObject);
    Procedure ShowCommitActionExecute(Sender: TObject);
    Procedure CopyShaActionExecute(Sender: TObject);
    Procedure CheckoutActionExecute(Sender: TObject);
    Procedure CreateBranchActionExecute(Sender: TObject);
    Procedure FilesListSelectionChange(Sender: TObject; User: Boolean);
    Procedure FilesListDblClick(Sender: TObject);
    Procedure StagedListSelectionChange(Sender: TObject; User: Boolean);
    Procedure StagedListDblClick(Sender: TObject);
    Procedure FileFilterChange(Sender: TObject);
    Procedure MessageChange(Sender: TObject);
    Procedure FilesDiffStatusChanged(Sender: TObject);
    Procedure FilesDiffSelectionChanged(Sender: TObject);
  End;

Procedure RefreshOpenManageRepositoryForms;
Procedure ClearOpenManageRepositoryForms;
Procedure ApplyRepositoryConfigToOpenForms;

Implementation

{$R *.lfm}

Uses
  WorkflowLog, GitService, GitConfig, GitRemotesForm, GitIgnoreForm, LazIDEIntf, ProjectIntf,
  DateUtils, Math, FileUtil, LazFileUtils, StrUtils, Process
  {$IFDEF WINDOWS}, ShellApi{$ENDIF};

Type
  TGitIndexThread = Class(TThread)
  Private
    FForm: TManageRepositoryForm;
    FRepoPath: String;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(AForm: TManageRepositoryForm; Const ARepoPath: String);
  End;

  TGitDetailThread = Class(TThread)
  Private
    FForm: TManageRepositoryForm;
    FRepoPath: String;
    FShas: TStringList;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(AForm: TManageRepositoryForm; Const ARepoPath: String; AShas: TStringList);
    Destructor Destroy; Override;
  End;

  { Runs Fetch/Pull/Push then loads the graph index + first detail batch off-thread.
    The History tree is left unchanged until ApplyRemoteOpFinished swaps in complete data. }
  TGitRemoteOpThread = Class(TThread)
  Private
    FForm: TManageRepositoryForm;
    FRepoPath: String;
    FKind: TGitRemoteOpKind;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(AForm: TManageRepositoryForm; Const ARepoPath: String; Kind: TGitRemoteOpKind);
  End;

Procedure CollectLeadingShas(Const RevListText: String; MaxCount: Integer; Shas: TStrings);
Var
  Lines: TStringList;
  I, SpacePos: Integer;
  Line, Sha: String;
Begin
  If (Shas = Nil) Or (MaxCount < 1) Then
    Exit;
  Lines := TStringList.Create;
  Try
    Lines.Text := RevListText;
    For I := 0 To Lines.Count - 1 Do
      Begin
        If Shas.Count >= MaxCount Then
          Break;
        Line := Trim(Lines[I]);
        If Line = '' Then
          Continue;
        SpacePos := Pos(' ', Line);
        If SpacePos > 0 Then
          Sha := Copy(Line, 1, SpacePos - 1)
        Else
          Sha := Line;
        If Sha <> '' Then
          Shas.Add(Sha);
      End;
  Finally
    Lines.Free;
  End;
End;

Constructor TGitIndexThread.Create(AForm: TManageRepositoryForm; Const ARepoPath: String);
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

Constructor TGitDetailThread.Create(AForm: TManageRepositoryForm; Const ARepoPath: String;
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

Constructor TGitRemoteOpThread.Create(AForm: TManageRepositoryForm; Const ARepoPath: String;
  Kind: TGitRemoteOpKind);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  FForm := AForm;
  FRepoPath := ARepoPath;
  FKind := Kind;
End;

Procedure TGitRemoteOpThread.Execute;
Var
  Client: TGitService;
  Summary: TGitTransferSummary;
  Ok, IndexOk, DetailsOk: Boolean;
  IndexText, DetailsText: String;
  Shas: TStringList;
Begin
  Client := TGitService.Create;
  Try
    Client.RepoPath := FRepoPath;
    Case FKind Of
      rokFetch: Ok := Client.Fetch(Summary);
      rokPull: Ok := Client.Pull(Summary);
      rokPush: Ok := Client.Push(Summary);
    Else
      Ok := False;
      Summary.Message := 'Unknown remote operation.';
    End;

    If Not Assigned(FForm) Or Terminated Then
      Exit;

    FForm.FPendingRemoteOk := Ok;
    FForm.FPendingRemoteMessage := Summary.Message;
    FForm.FPendingRemoteKind := FKind;
    FForm.FPendingIndexOk := False;
    FForm.FPendingIndexText := '';
    FForm.FPendingDetailsOk := False;
    FForm.FPendingDetailsText := '';

    { After a successful transfer, load index + first detail batch before any UI update. }
    If Ok And Not Terminated Then
      Begin
        IndexOk := Client.FetchRevListParents(FRepoPath, IndexText);
        If Not Assigned(FForm) Or Terminated Then
          Exit;
        FForm.FPendingIndexOk := IndexOk;
        FForm.FPendingIndexText := IndexText;
        If IndexOk Then
          Begin
            Shas := TStringList.Create;
            Try
              CollectLeadingShas(IndexText, GitGraphDetailBatch, Shas);
              If Shas.Count > 0 Then
                Begin
                  DetailsOk := Client.FetchCommitDetails(FRepoPath, Shas, DetailsText);
                  If Not Assigned(FForm) Or Terminated Then
                    Exit;
                  FForm.FPendingDetailsOk := DetailsOk;
                  FForm.FPendingDetailsText := DetailsText;
                End;
            Finally
              Shas.Free;
            End;
          End;
      End;

    If Terminated Or Not Assigned(FForm) Then
      Exit;
    If csDestroying in FForm.ComponentState Then
      Exit;
    Synchronize(@FForm.ApplyRemoteOpFinished);
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

Procedure RefreshOpenManageRepositoryForms;
Var
  I: Integer;
  Form: TCustomForm;
Begin
  For I := Screen.CustomFormCount - 1 DownTo 0 Do
    Begin
      Form := Screen.CustomForms[I];
      If (Form Is TManageRepositoryForm) And Not (csDestroying in Form.ComponentState) Then
        TManageRepositoryForm(Form).BindRepository;
    End;
End;

Procedure ClearOpenManageRepositoryForms;
Var
  I: Integer;
  Form: TCustomForm;
Begin
  For I := Screen.CustomFormCount - 1 DownTo 0 Do
    Begin
      Form := Screen.CustomForms[I];
      If (Form Is TManageRepositoryForm) And Not (csDestroying in Form.ComponentState) Then
        TManageRepositoryForm(Form).SetRepository('');
    End;
End;

Procedure ApplyRepositoryConfigToOpenForms;
Var
  I: Integer;
  Form: TCustomForm;
Begin
  For I := Screen.CustomFormCount - 1 DownTo 0 Do
    Begin
      Form := Screen.CustomForms[I];
      If (Form Is TManageRepositoryForm) And Not (csDestroying in Form.ComponentState) Then
        TManageRepositoryForm(Form).ApplyConfig;
    End;
End;

Constructor TManageRepositoryForm.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FClean := True;
  FSelectedIndex := -1;
  FIndexing := False;
  FDetailLoading := False;
  FRemoteOpBusy := False;
  FRemoteOpSuppressResult := False;
  FIndexThread := Nil;
  FDetailThread := Nil;
  FRemoteOpThread := Nil;
  FVisibleFirst := 0;
  FVisibleLast := 0;
  FFilesPaths := TStringList.Create;
  FStagedPaths := TStringList.Create;
  FModel := TGitGraphModel.Create;
  InitLaneColors;
  ApplyConfig;
  WorkflowEventBus.AddListener(Self);
End;

Destructor TManageRepositoryForm.Destroy;
Begin
  If Assigned(FDetailTimer) Then
    FDetailTimer.Enabled := False;
  If Assigned(FAutoRefreshTimer) Then
    FAutoRefreshTimer.Enabled := False;
  { Stop workers before children (diff view async callbacks) are freed. }
  StopRemoteOpThread;
  StopDetailThread;
  StopIndexThread;
  If Assigned(DiffView) Then
    DiffView.Clear;
  If Assigned(FilesDiffView) Then
    FilesDiffView.Clear;
  WorkflowEventBus.RemoveListener(Self);
  FreeAndNil(FFilesPaths);
  FreeAndNil(FStagedPaths);
  FreeAndNil(FModel);
  Inherited Destroy;
End;

Procedure TManageRepositoryForm.InitLaneColors;
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

Procedure TManageRepositoryForm.FormCreate(Sender: TObject);
Begin
  Try
    { Timers stay runtime-created (not useful in the designer). }
    FDetailTimer := TTimer.Create(Self);
    FDetailTimer.Enabled := False;
    FDetailTimer.Interval := 40;
    FDetailTimer.OnTimer := @DetailTimerTimer;

    FAutoRefreshTimer := TTimer.Create(Self);
    FAutoRefreshTimer.Enabled := False;
    FAutoRefreshTimer.OnTimer := @AutoRefreshTimerTimer;

    { ResizeControl is public but not published – cannot stream from the .lfm. }
    If Assigned(HistorySplitter) And Assigned(DetailPanel) Then
      HistorySplitter.ResizeControl := DetailPanel;
    If Assigned(CommitSplitter) And Assigned(CommitPanel) Then
      CommitSplitter.ResizeControl := CommitPanel;
    If Assigned(StagedSplitter) And Assigned(StagedPanel) Then
      StagedSplitter.ResizeControl := StagedPanel;

    If Assigned(DiffView) Then
      DiffView.SetViewMode(dvmBrowse);
    If Assigned(FilesDiffView) Then
      Begin
        FilesDiffView.SetViewMode(dvmEditorOnly);
        FilesDiffView.OnStatusChanged := @FilesDiffStatusChanged;
        FilesDiffView.OnSelectionChanged := @FilesDiffSelectionChanged;
      End;
    If Assigned(UntrackedCheck) Then
      UntrackedCheck.Checked := False;
    If Assigned(CleanCheck) Then
      CleanCheck.Checked := False;
    If Assigned(IgnoredCheck) Then
      IgnoredCheck.Checked := False;
    If Assigned(FilesList) Then
      FilesList.MultiSelect := True;
    If Assigned(StagedList) Then
      StagedList.MultiSelect := True;
    UpdateCommitEnabled;
    UpdateStageButtonsEnabled;

    WorkflowLogger.Info('ManageRepository', 'Manage Repository window created');
  Except
    On E: Exception Do
      WorkflowLogger.Error('ManageRepository', 'FormCreate: ' + E.Message);
  End;
End;

Procedure TManageRepositoryForm.FormDestroy(Sender: TObject);
Begin
  WorkflowLogger.Info('ManageRepository', 'Manage Repository window destroyed');
End;

Procedure TManageRepositoryForm.FormShow(Sender: TObject);
Begin
  Try
    BindRepository;
    ApplyConfig;
    { Remeasure scroll range once the paintbox parent has a handle. }
    UpdateScrollRange;
    If Assigned(GraphPaintBox) Then
      GraphPaintBox.Invalidate;
  Except
    On E: Exception Do
      WorkflowLogger.Error('ManageRepository', 'FormShow: ' + E.Message);
  End;
End;

Procedure TManageRepositoryForm.ApplyConfig;
Begin
  If Not Assigned(GitManagerConfig) Or Not Assigned(FAutoRefreshTimer) Then
    Exit;
  FAutoRefreshTimer.Enabled := False;
  FAutoRefreshTimer.Interval := GitManagerConfig.AutoRefreshSeconds * 1000;
  FAutoRefreshTimer.Enabled := GitManagerConfig.AutoRefresh And (FRepoPath <> '');
End;

Procedure TManageRepositoryForm.ManualRefresh;
Begin
  { Prefer the path already bound to this window so Fetch/Pull/Push always
    re-index the same repository instead of rediscovering from the IDE. }
  If FRemoteOpBusy Then
    Exit;
  WorkflowLogger.Info('ManageRepository', 'Manual refresh');
  If FRepoPath <> '' Then
    SetRepository(FRepoPath)
  Else
    BindRepository;
  If Assigned(Pages) And (Pages.ActivePage = FilesTab) Then
    RefreshFilesList;
End;

Procedure TManageRepositoryForm.FormKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
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
        MoveSelection(-(GraphPaintBox.ClientHeight Div GraphRowHeight));
        Key := 0;
      End;
    VK_NEXT:
      Begin
        MoveSelection(GraphPaintBox.ClientHeight Div GraphRowHeight);
        Key := 0;
      End;
  End;
End;

Procedure TManageRepositoryForm.MoveSelection(Delta: Integer);
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

Procedure TManageRepositoryForm.SelectRow(Index: Integer; ScrollIntoView: Boolean);
Var
  RowTop, RowBottom, ViewH, NewPos, RH: Integer;
Begin
  If (Index < 0) Or (Index >= FModel.Count) Then
    Exit;
  FSelectedIndex := Index;
  If ScrollIntoView Then
    Begin
      RH := GraphRowHeight;
      ViewH := GraphPaintBox.ClientHeight;
      RowTop := Index * RH;
      RowBottom := RowTop + RH;
      If RowTop < ScrollOffset Then
        GraphScrollBar.Position := RowTop
      Else If RowBottom > ScrollOffset + ViewH Then
        Begin
          NewPos := RowBottom - ViewH;
          If NewPos < 0 Then
            NewPos := 0;
          GraphScrollBar.Position := NewPos;
        End;
    End;
  ShowCommitDetails(Index);
  GraphPaintBox.Invalidate;
  If Not FModel.Commit(Index).DetailsLoaded Then
    ScheduleVisibleDetails;
End;

Function TManageRepositoryForm.SelectedSha: String;
Begin
  Result := '';
  If (FSelectedIndex >= 0) And (FSelectedIndex < FModel.Count) Then
    Result := FModel.Commit(FSelectedIndex).Sha;
End;

Function TManageRepositoryForm.ScrollOffset: Integer;
Begin
  Result := GraphScrollBar.Position;
End;

Procedure TManageRepositoryForm.StopIndexThread;
Begin
  If Assigned(FIndexThread) Then
    Begin
      FIndexThread.Terminate;
      FIndexThread.WaitFor;
      FreeAndNil(FIndexThread);
    End;
  FIndexing := False;
End;

Procedure TManageRepositoryForm.StopDetailThread;
Begin
  If Assigned(FDetailThread) Then
    Begin
      FDetailThread.Terminate;
      FDetailThread.WaitFor;
      FreeAndNil(FDetailThread);
    End;
  FDetailLoading := False;
End;

Procedure TManageRepositoryForm.StopRemoteOpThread;
Begin
  FRemoteOpSuppressResult := True;
  If Assigned(FRemoteOpThread) Then
    Begin
      FRemoteOpThread.Terminate;
      FRemoteOpThread.WaitFor;
      FreeAndNil(FRemoteOpThread);
    End;
  If FRemoteOpBusy Then
    Begin
      FRemoteOpBusy := False;
      Screen.Cursor := crDefault;
      SetRemoteActionsEnabled(True);
    End;
End;

Procedure TManageRepositoryForm.SetRemoteActionsEnabled(ActionsEnabled: Boolean);
Begin
  If Assigned(FetchAction) Then
    FetchAction.Enabled := ActionsEnabled;
  If Assigned(PullAction) Then
    PullAction.Enabled := ActionsEnabled;
  If Assigned(PushAction) Then
    PushAction.Enabled := ActionsEnabled;
  If Assigned(RemotesAction) Then
    RemotesAction.Enabled := ActionsEnabled;
End;

Procedure TManageRepositoryForm.StartRemoteOp(Kind: TGitRemoteOpKind);
Begin
  If (FRepoPath = '') Or FRemoteOpBusy Then
    Exit;
  { Halt independent graph workers on the main thread before starting the remote
    worker, so ApplyRemoteOpFinished need not WaitFor them inside Synchronize. }
  If Assigned(FDetailTimer) Then
    FDetailTimer.Enabled := False;
  StopRemoteOpThread;
  StopDetailThread;
  StopIndexThread;
  FIndexing := False;
  FRemoteOpSuppressResult := False;
  FRemoteOpBusy := True;
  Screen.Cursor := crHourGlass;
  SetRemoteActionsEnabled(False);
  FRemoteOpThread := TGitRemoteOpThread.Create(Self, FRepoPath, Kind);
  FRemoteOpThread.Start;
End;

Procedure TManageRepositoryForm.ApplyRemoteOpFinished;
Var
  Parsed: Integer;
  Ok: Boolean;
  ResultMessage: String;
  Kind: TGitRemoteOpKind;
Begin
  Ok := FPendingRemoteOk;
  ResultMessage := FPendingRemoteMessage;
  Kind := FPendingRemoteKind;

  If FRemoteOpSuppressResult Or (csDestroying in ComponentState) Or Application.Terminated Then
    Begin
      FRemoteOpBusy := False;
      Screen.Cursor := crDefault;
      Exit;
    End;

  If Ok Then
    Begin
      { Single UI transition: previous graph stays visible until this apply runs. }
      FIndexing := False;
      If Assigned(DiffView) Then
        DiffView.Clear;
      FSelectedIndex := -1;
      If Assigned(GraphScrollBar) Then
        GraphScrollBar.Position := 0;

      If FPendingIndexOk And Assigned(FModel) Then
        Begin
          Parsed := FModel.ParseRevListParents(FPendingIndexText);
          FPendingIndexText := '';
          If FPendingDetailsOk And (FPendingDetailsText <> '') Then
            Begin
              FModel.ApplyDetailsText(FPendingDetailsText);
              FPendingDetailsText := '';
              FPendingDetailsOk := False;
            End;
          If Parsed > 0 Then
            FSelectedIndex := 0;
          UpdateScrollRange;
          If FSelectedIndex >= 0 Then
            ShowCommitDetails(FSelectedIndex)
          Else If Assigned(DiffView) Then
            DiffView.Clear;
          If Assigned(GraphPaintBox) Then
            Begin
              GraphPaintBox.Invalidate;
              GraphPaintBox.Update;
            End;
          ScheduleVisibleDetails;
        End
      Else
        Begin
          { Transfer succeeded but rev-list failed — fall back to the normal re-index path. }
          FRemoteOpBusy := False;
          Screen.Cursor := crDefault;
          SetRemoteActionsEnabled(True);
          ManualRefresh;
          MessageDlg(ResultMessage + LineEnding + LineEnding +
            'History re-index failed; a full refresh was started.', mtWarning, [mbOK], 0);
          Exit;
        End;

      RefreshRepositoryInfo;
      UpdateStatus;
      If Kind = rokPush Then
        If Assigned(StatusFooter) Then
          StatusFooter.SetRightText('Push complete');
      If Assigned(Pages) And (Pages.ActivePage = FilesTab) Then
        RefreshFilesList;
    End;

  FRemoteOpBusy := False;
  Screen.Cursor := crDefault;
  SetRemoteActionsEnabled(True);

  If Ok Then
    MessageDlg(ResultMessage, mtInformation, [mbOK], 0)
  Else
    MessageDlg(ResultMessage, mtError, [mbOK], 0);
End;

Procedure TManageRepositoryForm.StartIndexLoad;
Begin
  If FRepoPath = '' Then
    Exit;
  StopDetailThread;
  StopIndexThread;
  FIndexing := True;
  If Assigned(StatusFooter) Then
    StatusFooter.SetRightText('Indexing…');
  FIndexThread := TGitIndexThread.Create(Self, FRepoPath);
  FIndexThread.Start;
End;

Procedure TManageRepositoryForm.ApplyIndexLoaded;
Var
  Parsed: Integer;
Begin
  FIndexing := False;
  If (csDestroying in ComponentState) Or Not Assigned(FModel) Or Not Assigned(DiffView) Then
    Exit;
  If Not FPendingIndexOk Then
    Begin
      If Assigned(StatusFooter) Then
        If Assigned(StatusFooter) Then
          StatusFooter.SetRightText('Index failed');
      WorkflowLogger.Warning('ManageRepository', 'rev-list failed for ' + FRepoPath);
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
    DiffView.Clear;

  UpdateStatus;
  If Assigned(GraphPaintBox) Then
    GraphPaintBox.Invalidate;
  ScheduleVisibleDetails;
  WorkflowLogger.Info('ManageRepository', Format('Indexed %d commits', [Parsed]));
End;

Procedure TManageRepositoryForm.ApplyDetailsLoaded;
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
  If Assigned(GraphPaintBox) Then
    GraphPaintBox.Invalidate;
  { More rows may still be missing after scrolling. }
  ScheduleVisibleDetails;
End;

Procedure TManageRepositoryForm.GetVisibleRange(Out FirstRow, LastRow: Integer);
Var
  ViewH, RH: Integer;
Begin
  FirstRow := 0;
  LastRow := -1;
  If FModel.Count = 0 Then
    Exit;
  RH := GraphRowHeight;
  If RH < 1 Then
    RH := 1;
  ViewH := GraphPaintBox.ClientHeight;
  If ViewH < 1 Then
    ViewH := 1;
  FirstRow := ScrollOffset Div RH;
  LastRow := (ScrollOffset + ViewH) Div RH;
  If FirstRow < 0 Then
    FirstRow := 0;
  If LastRow >= FModel.Count Then
    LastRow := FModel.Count - 1;
End;

Procedure TManageRepositoryForm.ScheduleVisibleDetails;
Begin
  If FIndexing Or (FRepoPath = '') Or (FModel.Count = 0) Then
    Exit;
  GetVisibleRange(FVisibleFirst, FVisibleLast);
  FDetailTimer.Enabled := False;
  FDetailTimer.Enabled := True;
End;

Procedure TManageRepositoryForm.DetailTimerTimer(Sender: TObject);
Begin
  FDetailTimer.Enabled := False;
  StartDetailLoadIfNeeded;
End;

Procedure TManageRepositoryForm.StartDetailLoadIfNeeded;
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

Procedure TManageRepositoryForm.UpdateScrollRange;
Var
  ViewH, ContentH, MaxPos, RH: Integer;
Begin
  If (Not Assigned(GraphPaintBox)) Or (Not Assigned(GraphScrollBar)) Or (Not Assigned(FModel)) Then
    Exit;
  ViewH := GraphPaintBox.ClientHeight;
  If ViewH < 1 Then
    ViewH := 1;
  RH := GraphRowHeight;
  ContentH := GraphContentHeight;
  MaxPos := ContentH - ViewH;
  If MaxPos < 0 Then
    MaxPos := 0;
  GraphScrollBar.Min := 0;
  GraphScrollBar.SmallChange := RH;
  GraphScrollBar.LargeChange := ViewH;
  { Position runs 0..Max; PageSize 0 avoids platform-specific range quirks. }
  GraphScrollBar.PageSize := 0;
  GraphScrollBar.Max := MaxPos;
  If GraphScrollBar.Position > MaxPos Then
    GraphScrollBar.Position := MaxPos;
  GraphScrollBar.Enabled := MaxPos > 0;
End;

Procedure TManageRepositoryForm.GraphHostResize(Sender: TObject);
Begin
  UpdateScrollRange;
  ScheduleVisibleDetails;
  GraphPaintBox.Invalidate;
End;

Procedure TManageRepositoryForm.ScrollBarChange(Sender: TObject);
Begin
  ScheduleVisibleDetails;
  GraphPaintBox.Invalidate;
End;

Procedure TManageRepositoryForm.PaintBoxMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; Var Handled: Boolean);
Var
  NewPos, MaxPos, ViewH: Integer;
Begin
  ViewH := GraphPaintBox.ClientHeight;
  MaxPos := GraphContentHeight - ViewH;
  If MaxPos < 0 Then
    MaxPos := 0;
  NewPos := GraphScrollBar.Position - (WheelDelta Div 120) * GraphRowHeight * 3;
  If NewPos < 0 Then
    NewPos := 0;
  If NewPos > MaxPos Then
    NewPos := MaxPos;
  If NewPos <> GraphScrollBar.Position Then
    GraphScrollBar.Position := NewPos;
  Handled := True;
End;

Function TManageRepositoryForm.GraphScale(DesignPx: Integer): Integer;
Var
  PPI: Integer;
Begin
  { Scale design (96 DPI) pixels via form/screen PPI.
    Do NOT use Scale96ToForm here: it calls NeedParentDesignControl and raises
    EInvalidOperation when the control chain is not yet parented (IDE desktop
    restore / early BindRepository during package load). }
  PPI := PixelsPerInch;
  If PPI <= 0 Then
    PPI := Screen.PixelsPerInch;
  If PPI <= 0 Then
    PPI := 96;
  Result := Integer((Int64(DesignPx) * PPI) Div 96);
  If (DesignPx > 0) And (Result < 1) Then
    Result := 1;
End;

Function TManageRepositoryForm.GraphCanMeasureFont: Boolean;
Begin
  { TPaintBox has no handle; its Canvas needs a parent TWinControl with a DC. }
  Result := Assigned(GraphPaintBox) And Assigned(GraphPaintBox.Parent) And
    GraphPaintBox.Parent.HandleAllocated;
End;

Function TManageRepositoryForm.GraphRowHeight: Integer;
Var
  TextH, Base, Pad: Integer;
Begin
  Base := GraphScale(GitGraphRowHeight);
  Pad := GraphScale(6);
  Result := Base;
  { Prefer live font metrics so row height tracks painted text on HiDPI. }
  If GraphCanMeasureFont Then
    Begin
      Try
        PrepareGraphTextFont(GraphPaintBox.Canvas, False);
        TextH := GraphPaintBox.Canvas.TextHeight('Ag');
        Result := Max(Base, TextH + Pad);
      Except
        Result := Base;
      End;
    End;
End;

Function TManageRepositoryForm.GraphLaneWidth: Integer;
Begin
  Result := GraphScale(GitGraphLaneWidth);
End;

Function TManageRepositoryForm.GraphLeftMargin: Integer;
Begin
  Result := GraphScale(GitGraphLeftMargin);
End;

Function TManageRepositoryForm.GraphNodeRadius: Integer;
Begin
  Result := GraphScale(GitGraphNodeRadius);
End;

Function TManageRepositoryForm.GraphTextGap: Integer;
Begin
  Result := GraphScale(GitGraphTextGap);
End;

Function TManageRepositoryForm.GraphDateColumnWidth: Integer;
Var
  SampleW: Integer;
Begin
  { Measure the fixed date format so the subject never underlaps the date. }
  SampleW := GraphScale(110);
  If GraphCanMeasureFont Then
    Begin
      Try
        PrepareGraphTextFont(GraphPaintBox.Canvas, True);
        SampleW := GraphPaintBox.Canvas.TextWidth('0000-00-00 00:00');
      Except
        SampleW := GraphScale(110);
      End;
    End;
  Result := SampleW + GraphScale(GitGraphDateGap);
End;

Function TManageRepositoryForm.GraphContentWidth: Integer;
Begin
  Result := FModel.GraphWidth(GraphLeftMargin, GraphLaneWidth);
End;

Function TManageRepositoryForm.GraphContentHeight: Integer;
Begin
  Result := FModel.TotalHeight(GraphRowHeight);
End;

Procedure TManageRepositoryForm.PrepareGraphTextFont(ACanvas: TCanvas; IsDate: Boolean);
Begin
  If Not Assigned(ACanvas) Then
    Exit;
  { Point sizes only — never assign Font.Height := 0 (forces Size 0 intermediate). }
  ACanvas.Font.Name := Font.Name;
  ACanvas.Font.Style := [];
  ACanvas.Font.Quality := fqCleartypeNatural;
  ACanvas.Font.Size := 9;
  If IsDate Then
    ACanvas.Font.Color := clGrayText
  Else
    ACanvas.Font.Color := clWindowText;
End;

Function TManageRepositoryForm.LaneX(Lane: Integer): Integer;
Var
  LW: Integer;
Begin
  LW := GraphLaneWidth;
  Result := GraphLeftMargin + Lane * LW + LW Div 2;
End;

Function TManageRepositoryForm.RowMidY(Row: Integer): Integer;
Var
  RH: Integer;
Begin
  RH := GraphRowHeight;
  Result := Row * RH + RH Div 2 - ScrollOffset;
End;

Function TManageRepositoryForm.RowAtY(Y: Integer): Integer;
Var
  RH: Integer;
Begin
  If FModel.Count = 0 Then
    Result := -1
  Else
    Begin
      RH := GraphRowHeight;
      If RH < 1 Then
        RH := 1;
      Result := (Y + ScrollOffset) Div RH;
      If (Result < 0) Or (Result >= FModel.Count) Then
        Result := -1;
    End;
End;

Function TManageRepositoryForm.FormatCommitDate(Const CommitTime: Int64): String;
Begin
  If CommitTime <= 0 Then
    Result := '…'
  Else
    Result := FormatDateTime('yyyy-mm-dd hh:nn', UnixToDateTime(CommitTime));
End;

Procedure TManageRepositoryForm.DrawRefCards(Const Refs: String; Var TextX: Integer; RowTop: Integer);
Type
  TRefKind = (rkLocal, rkRemote, rkTag, rkOther);
Var
  Parts: TStringList;
  I, ArrowPos, CardW, CardH, CardY, PadX, Gap, MinW, RH, TextH: Integer;
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

    RH := GraphRowHeight;
    CardH := GraphScale(16);
    PadX := GraphScale(6);
    Gap := GraphScale(5);
    MinW := GraphScale(28);
    { Chip height tracks row metrics so text stays centered at high DPI. }
    With GraphPaintBox.Canvas Do
      Begin
        Font.Name := Self.Font.Name;
        Font.Size := 8;
        Font.Style := [];
        Font.Quality := fqCleartypeNatural;
        TextH := TextHeight('Ag');
      End;
    If CardH < TextH + GraphScale(4) Then
      CardH := TextH + GraphScale(4);
    If CardH > RH - GraphScale(2) Then
      CardH := Max(TextH, RH - GraphScale(2));
    CardY := RowTop + (RH - CardH) Div 2;

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

        With GraphPaintBox.Canvas Do
          Begin
            Font.Name := Self.Font.Name;
            Font.Size := 8;
            Font.Style := [];
            Font.Quality := fqCleartypeNatural;
            Font.Color := Fg;
            CardW := TextWidth(RefName) + PadX * 2;
            If CardW < MinW Then
              CardW := MinW;

            Brush.Style := bsSolid;
            Brush.Color := Bg;
            Pen.Color := Border;
            Pen.Width := Max(1, GraphScale(1));
            { Clean bordered rectangles – RoundRect is jagged on many widgetsets. }
            Rectangle(TextX, CardY, TextX + CardW, CardY + CardH);

            Brush.Style := bsClear;
            TextOut(TextX + PadX, CardY + (CardH - TextHeight(RefName)) Div 2, RefName);
            Brush.Style := bsSolid;
          End;

        TextX := TextX + CardW + Gap;
      End;
  Finally
    Parts.Free;
  End;
End;

Procedure TManageRepositoryForm.PaintBoxPaint(Sender: TObject);
Var
  FirstRow, LastRow, I, TextX, Y, X, Off, SubjectW, RH, DateColW, NodeR: Integer;
  TextH, TextY, EdgePenW, MsgPad: Integer;
  C: TGitCommitRec;
  E: TGitGraphEdge;
  Col: TColor;
  LabelText, DateText: String;
Begin
  Off := ScrollOffset;
  RH := GraphRowHeight;
  DateColW := GraphDateColumnWidth;
  NodeR := GraphNodeRadius;
  EdgePenW := Max(1, GraphScale(2));
  MsgPad := GraphScale(16);
  With GraphPaintBox.Canvas Do
    Begin
      Brush.Color := clWindow;
      FillRect(GraphPaintBox.ClientRect);

      If FIndexing And (FModel.Count = 0) Then
        Begin
          PrepareGraphTextFont(GraphPaintBox.Canvas, False);
          Font.Color := clGrayText;
          Font.Size := 11;
          TextOut(MsgPad, MsgPad, 'Indexing commit history…');
          Exit;
        End;

      If FModel.Count = 0 Then
        Begin
          PrepareGraphTextFont(GraphPaintBox.Canvas, False);
          Font.Color := clGrayText;
          Font.Size := 11;
          If FRepoPath = '' Then
            TextOut(MsgPad, MsgPad, 'No Git repository detected for the active project')
          Else
            TextOut(MsgPad, MsgPad, 'No commits to display');
          Exit;
        End;

      GetVisibleRange(FirstRow, LastRow);
      If LastRow < FirstRow Then
        Exit;

      { Selection under graph geometry so lane edges still show on the active row. }
      If (FSelectedIndex >= FirstRow) And (FSelectedIndex <= LastRow) Then
        Begin
          Y := FSelectedIndex * RH - Off;
          Brush.Color := RGBToColor(227, 242, 253);
          FillRect(Bounds(0, Y, GraphPaintBox.ClientWidth, RH));
        End;

      Pen.Width := EdgePenW;
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
          Y := I * RH - Off;

          Col := FLaneColors[FModel.LaneColorIndex(C.Lane)];
          X := LaneX(C.Lane);
          Brush.Color := Col;
          Pen.Color := Col;
          Pen.Width := Max(1, GraphScale(1));
          Ellipse(X - NodeR, RowMidY(I) - NodeR, X + NodeR, RowMidY(I) + NodeR);

          TextX := GraphContentWidth + GraphTextGap;
          Brush.Style := bsClear;
          PrepareGraphTextFont(GraphPaintBox.Canvas, True);
          DateText := FormatCommitDate(C.CommitTime);
          TextH := TextHeight(DateText);
          TextY := Y + (RH - TextH) Div 2;
          TextOut(TextX, TextY, DateText);

          TextX := TextX + DateColW;
          PrepareGraphTextFont(GraphPaintBox.Canvas, False);
          If C.DetailsLoaded Then
            LabelText := C.Subject
          Else
            LabelText := '…';
          TextH := TextHeight(LabelText);
          TextY := Y + (RH - TextH) Div 2;
          TextOut(TextX, TextY, LabelText);
          SubjectW := TextWidth(LabelText);
          TextX := TextX + SubjectW + GraphScale(8);
          Brush.Style := bsSolid;

          { Branch/tag cards after the subject (Gitg-style chips). }
          If C.DetailsLoaded And (C.Refs <> '') Then
            DrawRefCards(C.Refs, TextX, Y);
        End;
    End;
End;

Procedure TManageRepositoryForm.PaintBoxMouseDown(Sender: TObject; Button: TMouseButton;
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

Procedure TManageRepositoryForm.ShowCommitDetails(Index: Integer);
Var
  C: TGitCommitRec;
  When: TDateTime;
  I: Integer;
  ParentLine, Header: String;
Begin
  If Not Assigned(DiffView) Or (csDestroying in ComponentState) Then
    Exit;
  If (Index < 0) Or Not Assigned(FModel) Or (Index >= FModel.Count) Then
    Begin
      DiffView.Clear;
      Exit;
    End;
  C := FModel.Commit(Index);

  { File list + full-file embedded red/green diff for the selected path. }
  If Assigned(GitClient) And (FRepoPath <> '') And (C.Sha <> '') Then
    Begin
      DiffView.LoadCommit(FRepoPath, C.Sha, Copy(C.Sha, 1, 7) + '  ' + C.Subject);
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
  DiffView.LoadPlainText(Copy(C.Sha, 1, 7), Header);
End;

Procedure TManageRepositoryForm.PagesChange(Sender: TObject);
Begin
  If Not Assigned(Pages) Then
    Exit;
  If Pages.ActivePage = FilesTab Then
    Begin
      RefreshFilesList;
      { Overview paints on a child window that only sizes after the page is shown. }
      If Assigned(FilesDiffView) Then
        FilesDiffView.RefreshOverviewGutter;
    End
  Else If Pages.ActivePage = HistoryTab Then
    Begin
      If Assigned(DiffView) Then
        DiffView.RefreshOverviewGutter;
    End;
End;

Function TManageRepositoryForm.DescribeFileStatus(IndexStatus, WorkTreeStatus: Char): String;
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

Function TManageRepositoryForm.FileStatusPassesFilter(Const StatusText: String): Boolean;
Begin
  { Optional categories are hidden unless their filter checkbox is checked. }
  If StatusText = 'untracked' Then
    Result := Assigned(UntrackedCheck) And UntrackedCheck.Checked
  Else If StatusText = 'clean' Then
    Result := Assigned(CleanCheck) And CleanCheck.Checked
  Else If StatusText = 'ignored' Then
    Result := Assigned(IgnoredCheck) And IgnoredCheck.Checked
  Else
    Result := True;
End;

Procedure TManageRepositoryForm.RefreshFilesList;
Var
  AllFiles, StatusMap, FullyStaged: TStringList;
  Entries: TGitStatusEntryArray;
  I: Integer;
  FullPath, Rel, Root, StatusText: String;
  Idx: Integer;
  EntryStatus: String;
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

    If (FRepoPath = '') Or Not DirectoryExists(FRepoPath) Then
      Begin
        FilesList.Items.Add('(no repository)');
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
                    { GitStatusEntryLabel already includes the path (and rename old->new). }
                    StagedList.Items.Add(GitStatusEntryLabel(Entries[I], True));
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
  UpdateCommitEnabled;
  UpdateStageButtonsEnabled;
End;

Function TManageRepositoryForm.ListHasSelection(List: TListBox): Boolean;
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

Procedure TManageRepositoryForm.UpdateStageButtonsEnabled;
Var
  CanPreview, CanPathAction: Boolean;
  FilesEmpty, StagedEmpty, UnstageMode: Boolean;
Begin
  FilesEmpty := (Not Assigned(FFilesPaths)) Or (FFilesPaths.Count = 0);
  StagedEmpty := (Not Assigned(FStagedPaths)) Or (FStagedPaths.Count = 0);
  { Prefer unstage when the working-tree list is empty but staged entries remain,
    or when the staged list currently holds the selection. }
  UnstageMode := (Not StagedEmpty) And (FilesEmpty Or ListHasSelection(StagedList));

  If Assigned(StageAllAction) Then
    Begin
      If (Not StagedEmpty) And FilesEmpty Then
        Begin
          StageAllAction.Caption := 'Unstage All';
          StageAllAction.Enabled := FRepoPath <> '';
        End
      Else
        Begin
          StageAllAction.Caption := 'Stage All';
          StageAllAction.Enabled := (Not FilesEmpty) And (FRepoPath <> '');
        End;
    End;

  If Assigned(StageAction) Then
    Begin
      If UnstageMode Then
        Begin
          StageAction.Caption := 'Unstage';
          StageAction.Enabled := ListHasSelection(StagedList) And (FRepoPath <> '');
        End
      Else
        Begin
          StageAction.Caption := 'Stage';
          StageAction.Enabled := ListHasSelection(FilesList) And (Not FilesEmpty) And (FRepoPath <> '');
        End;
    End;

  If Assigned(StageSelectionAction) And Assigned(FilesDiffView) Then
    Begin
      CanPreview := FilesDiffView.HasActiveSelection And (FRepoPath <> '');
      If FilesDiffView.StagedSide Then
        Begin
          StageSelectionAction.Caption := 'Unstage Selection';
          StageSelectionAction.Enabled := CanPreview;
        End
      Else
        Begin
          StageSelectionAction.Caption := 'Stage Selection';
          StageSelectionAction.Enabled := CanPreview;
        End;
    End;

  CanPathAction := (FRepoPath <> '') And
    (ListHasSelection(FilesList) Or ListHasSelection(StagedList));
  If Assigned(RevertAction) Then
    RevertAction.Enabled := CanPathAction;
  If Assigned(DeleteAction) Then
    DeleteAction.Enabled := CanPathAction;
  If Assigned(IgnoreAction) Then
    IgnoreAction.Enabled := CanPathAction;
  If Assigned(IgnoredFilesAction) Then
    IgnoredFilesAction.Enabled := FRepoPath <> '';
End;

Procedure TManageRepositoryForm.UpdateCommitEnabled;
Var
  HasStaged, CanCommit: Boolean;
Begin
  HasStaged := Assigned(FStagedPaths) And (FStagedPaths.Count > 0);
  CanCommit := HasStaged And Assigned(MessageMemo) And (Trim(MessageMemo.Text) <> '');
  If Assigned(SuggestMessageAction) Then
    SuggestMessageAction.Enabled := HasStaged;
  If Assigned(CommitAction) Then
    CommitAction.Enabled := CanCommit;
End;

Function TManageRepositoryForm.CollectSelectedPaths(List: TListBox; Paths: TStringList): TStringList;
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

Function TManageRepositoryForm.CollectActiveSelectedPaths: TStringList;
Begin
  { Selections are mutually exclusive between the two lists. }
  Result := CollectSelectedPaths(FilesList, FFilesPaths);
  If Result.Count = 0 Then
    Begin
      Result.Free;
      Result := CollectSelectedPaths(StagedList, FStagedPaths);
    End;
End;

Function TManageRepositoryForm.FormatPathActionSummary(Const ActionVerb: String; Paths: TStrings): String;
Var
  I, Shown: Integer;
  Body: String;
Const
  MaxListed = 15;
Begin
  Body := '';
  Shown := 0;
  If Assigned(Paths) Then
    For I := 0 To Paths.Count - 1 Do
      Begin
        If Shown >= MaxListed Then
          Begin
            Body := Body + LineEnding + Format('…and %d more', [Paths.Count - MaxListed]);
            Break;
          End;
        If Body <> '' Then
          Body := Body + LineEnding;
        Body := Body + Paths[I];
        Inc(Shown);
      End;
  If Paths = Nil Then
    Result := ActionVerb
  Else
    Result := Format('%s the following %d file(s)?' + LineEnding + LineEnding + '%s',
      [ActionVerb, Paths.Count, Body]);
End;

Function TManageRepositoryForm.ConfirmPathAction(Const ActionTitle, ActionVerb: String;
  Paths: TStrings): Boolean;
Begin
  Result := False;
  If (Paths = Nil) Or (Paths.Count = 0) Then
    Exit;
  Result := MessageDlg(ActionTitle, FormatPathActionSummary(ActionVerb, Paths),
    mtConfirmation, [mbYes, mbNo], 0) = mrYes;
End;

Function TManageRepositoryForm.MovePathToWasteBin(Const FullPath: String; Out ErrorText: String): Boolean;
{$IFDEF WINDOWS}
Var
  Op: TSHFileOpStructW;
  FromBuf: UnicodeString;
{$ELSE}
Var
  Proc: TProcess;
  Cmd: String;
{$ENDIF}
Begin
  Result := False;
  ErrorText := '';
  If FullPath = '' Then
    Begin
      ErrorText := 'Empty path';
      Exit;
    End;
  If (Not FileExists(FullPath)) And (Not DirectoryExists(FullPath)) Then
    Begin
      ErrorText := 'Path does not exist: ' + FullPath;
      Exit;
    End;

{$IFDEF WINDOWS}
  FromBuf := UTF8Decode(FullPath) + #0#0;
  FillChar(Op, SizeOf(Op), 0);
  Op.Wnd := 0;
  Op.wFunc := FO_DELETE;
  Op.pFrom := PWideChar(FromBuf);
  Op.fFlags := FOF_ALLOWUNDO Or FOF_NOCONFIRMATION Or FOF_SILENT Or FOF_NOERRORUI;
  If SHFileOperationW(@Op) = 0 Then
    Result := Not (FileExists(FullPath) Or DirectoryExists(FullPath))
  Else
    ErrorText := 'Windows could not move the item to the Recycle Bin';
{$ELSE}
  { Prefer desktop trash tools; fall back to a home Trash folder move. }
  Proc := TProcess.Create(Nil);
  Try
    Proc.Options := [poWaitOnExit, poNoConsole];
    Cmd := FindDefaultExecutablePath('gio');
    If Cmd <> '' Then
      Begin
        Proc.Executable := Cmd;
        Proc.Parameters.Add('trash');
        Proc.Parameters.Add(FullPath);
        Try
          Proc.Execute;
          Result := Proc.ExitStatus = 0;
        Except
          Result := False;
        End;
      End;
    If Not Result Then
      Begin
        Proc.Parameters.Clear;
        Cmd := FindDefaultExecutablePath('trash-put');
        If Cmd = '' Then
          Cmd := FindDefaultExecutablePath('trash');
        If Cmd <> '' Then
          Begin
            Proc.Executable := Cmd;
            Proc.Parameters.Add(FullPath);
            Try
              Proc.Execute;
              Result := Proc.ExitStatus = 0;
            Except
              Result := False;
            End;
          End;
      End;
    If Not Result Then
      Begin
        {$IFDEF DARWIN}
        Proc.Parameters.Clear;
        Proc.Executable := '/usr/bin/osascript';
        Proc.Parameters.Add('-e');
        Proc.Parameters.Add('tell application "Finder" to delete POSIX file "' +
          StringReplace(FullPath, '"', '\"', [rfReplaceAll]) + '"');
        Try
          Proc.Execute;
          Result := Proc.ExitStatus = 0;
        Except
          Result := False;
        End;
        {$ENDIF}
      End;
    If Not Result Then
      ErrorText := 'Could not move to the waste bin: ' + FullPath;
  Finally
    Proc.Free;
  End;
{$ENDIF}
End;

Procedure TManageRepositoryForm.ShowFilesDiff(List: TListBox; Paths: TStringList; StagedSide: Boolean);
Var
  I: Integer;
  DiffText, Path, Title, Content: String;
Begin
  If Not Assigned(FilesDiffView) Then
    Exit;
  FilesDiffView.Clear;
  FilesDiffView.SetViewMode(dvmEditorOnly);
  FilesDiffView.SetStagingContext(FRepoPath, StagedSide);
  FilesDiffView.SetViewMode(dvmEditorOnly);
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
        { Images/binary: never dump bytes into SynEdit. }
        If FilesDiffView.LoadBinaryOrImagePreview(Title, Path, '', StagedSide) Then
          Exit;
        If GitClient.DiffPath(Path, StagedSide, DiffText) Then
          Begin
            If Trim(DiffText) = '' Then
              Begin
                { Clean tracked file (or no staged delta): show plain content, not a green "new file" diff. }
                If (Not StagedSide) And GitClient.ReadWorkingTreeFile(Path, Content) Then
                  FilesDiffView.LoadPlainText(Title + ' (clean)', Content, Path)
                Else If StagedSide Then
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

Procedure TManageRepositoryForm.FilesListSelectionChange(Sender: TObject; User: Boolean);
Begin
  { Keep multi-select on this list; only clear the other list's selection. }
  If Assigned(StagedList) And ListHasSelection(StagedList) Then
    StagedList.ClearSelection;
  ShowFilesDiff(FilesList, FFilesPaths, False);
  UpdateStageButtonsEnabled;
End;

Procedure TManageRepositoryForm.FilesListDblClick(Sender: TObject);
Begin
  StageActionExecute(Sender);
End;

Procedure TManageRepositoryForm.StagedListSelectionChange(Sender: TObject; User: Boolean);
Begin
  If Assigned(FilesList) And ListHasSelection(FilesList) Then
    FilesList.ClearSelection;
  ShowFilesDiff(StagedList, FStagedPaths, True);
  UpdateStageButtonsEnabled;
End;

Procedure TManageRepositoryForm.StagedListDblClick(Sender: TObject);
Begin
  StageActionExecute(Sender);
End;

Procedure TManageRepositoryForm.FileFilterChange(Sender: TObject);
Begin
  RefreshFilesList;
End;

Procedure TManageRepositoryForm.IgnoredFilesActionExecute(Sender: TObject);
Begin
  If FRepoPath = '' Then
    Begin
      MessageDlg('No repository is bound to this window.', mtInformation, [mbOK], 0);
      Exit;
    End;
  If ShowGitIgnoreForm(FRepoPath) Then
    RefreshFilesList;
End;

Procedure TManageRepositoryForm.RevertActionExecute(Sender: TObject);
Var
  Paths: TStringList;
Begin
  If Not Assigned(GitClient) Or (FRepoPath = '') Then
    Exit;
  Paths := CollectActiveSelectedPaths;
  Try
    If Paths.Count = 0 Then
      Begin
        MessageDlg('Select one or more files to revert.', mtInformation, [mbOK], 0);
        Exit;
      End;
    If Not ConfirmPathAction('Revert files',
      'Restore from the last commit (discard local changes for)', Paths) Then
      Exit;
    GitClient.RepoPath := FRepoPath;
    If Not GitClient.RevertPaths(Paths) Then
      MessageDlg('Revert failed: ' + GitClient.LastError, mtError, [mbOK], 0)
    Else
      WorkflowLogger.Info('ManageRepository', Format('Reverted %d path(s)', [Paths.Count]));
    RefreshFilesList;
  Finally
    Paths.Free;
  End;
End;

Procedure TManageRepositoryForm.DeleteActionExecute(Sender: TObject);
Var
  Paths: TStringList;
  I: Integer;
  FullPath, ErrorText, Failures: String;
  OkCount: Integer;
Begin
  If (FRepoPath = '') Or Not Assigned(GitClient) Then
    Exit;
  Paths := CollectActiveSelectedPaths;
  Try
    If Paths.Count = 0 Then
      Begin
        MessageDlg('Select one or more files to delete.', mtInformation, [mbOK], 0);
        Exit;
      End;
    If Not ConfirmPathAction('Delete files',
      'Move to the waste bin', Paths) Then
      Exit;
    GitClient.RepoPath := FRepoPath;
    OkCount := 0;
    Failures := '';
    For I := 0 To Paths.Count - 1 Do
      Begin
        FullPath := GitClient.WorkingTreeFullPath(Paths[I]);
        If MovePathToWasteBin(FullPath, ErrorText) Then
          Inc(OkCount)
        Else
          Begin
            If Failures <> '' Then
              Failures := Failures + LineEnding;
            If ErrorText <> '' Then
              Failures := Failures + ErrorText
            Else
              Failures := Failures + Paths[I];
          End;
      End;
    If Failures <> '' Then
      MessageDlg(Format('Moved %d of %d item(s) to the waste bin.' + LineEnding + LineEnding +
        'Failed:' + LineEnding + '%s', [OkCount, Paths.Count, Failures]),
        mtWarning, [mbOK], 0)
    Else
      WorkflowLogger.Info('ManageRepository', Format('Moved %d path(s) to waste bin', [OkCount]));
    RefreshFilesList;
  Finally
    Paths.Free;
  End;
End;

Procedure TManageRepositoryForm.IgnoreActionExecute(Sender: TObject);
Var
  Paths: TStringList;
Begin
  If Not Assigned(GitClient) Or (FRepoPath = '') Then
    Exit;
  Paths := CollectActiveSelectedPaths;
  Try
    If Paths.Count = 0 Then
      Begin
        MessageDlg('Select one or more files to ignore.', mtInformation, [mbOK], 0);
        Exit;
      End;
    If Not ConfirmPathAction('Ignore files',
      'Add to .gitignore', Paths) Then
      Exit;
    GitClient.RepoPath := FRepoPath;
    If Not GitClient.AppendIgnorePatterns(Paths) Then
      MessageDlg('Could not update .gitignore: ' + GitClient.LastError, mtError, [mbOK], 0)
    Else
      WorkflowLogger.Info('ManageRepository', Format('Ignored %d path(s)', [Paths.Count]));
    RefreshFilesList;
  Finally
    Paths.Free;
  End;
End;

Procedure TManageRepositoryForm.StageActionExecute(Sender: TObject);
Var
  Paths: TStringList;
  FilesEmpty, UnstageMode: Boolean;
Begin
  If Not Assigned(GitClient) Or (FRepoPath = '') Then
    Exit;
  FilesEmpty := (Not Assigned(FFilesPaths)) Or (FFilesPaths.Count = 0);
  UnstageMode := Assigned(FStagedPaths) And (FStagedPaths.Count > 0) And
    (FilesEmpty Or ListHasSelection(StagedList));

  If UnstageMode Then
    Begin
      Paths := CollectSelectedPaths(StagedList, FStagedPaths);
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
    End
  Else
    Begin
      Paths := CollectSelectedPaths(FilesList, FFilesPaths);
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
End;

Procedure TManageRepositoryForm.StageAllActionExecute(Sender: TObject);
Var
  FilesEmpty, StagedEmpty: Boolean;
Begin
  If Not Assigned(GitClient) Or (FRepoPath = '') Then
    Exit;
  FilesEmpty := (Not Assigned(FFilesPaths)) Or (FFilesPaths.Count = 0);
  StagedEmpty := (Not Assigned(FStagedPaths)) Or (FStagedPaths.Count = 0);
  GitClient.RepoPath := FRepoPath;
  If (Not StagedEmpty) And FilesEmpty Then
    Begin
      { Unstage only what is listed in the staged panel (all currently staged paths). }
      If Not GitClient.UnstagePaths(FStagedPaths) Then
        MessageDlg('Unstage all failed: ' + GitClient.LastError, mtError, [mbOK], 0);
    End
  Else
    Begin
      { Stage only paths visible in the filtered files list — not git add -A. }
      If FilesEmpty Then
        Exit;
      If Not GitClient.StagePaths(FFilesPaths) Then
        MessageDlg('Stage all failed: ' + GitClient.LastError, mtError, [mbOK], 0);
    End;
  RefreshFilesList;
End;

Procedure TManageRepositoryForm.StageSelectionActionExecute(Sender: TObject);
Begin
  If Not Assigned(FilesDiffView) Then
    Exit;
  If Not FilesDiffView.HasActiveSelection Then
    Begin
      MessageDlg('Select lines in the file preview first.', mtInformation, [mbOK], 0);
      Exit;
    End;
  If FilesDiffView.StagedSide Then
    FilesDiffView.UnstageSelection
  Else
    FilesDiffView.StageSelection;
End;

Procedure TManageRepositoryForm.SuggestMessageActionExecute(Sender: TObject);
Var
  DiffText, StatusText, MessageText, ErrorText: String;
Begin
  If Not Assigned(GitClient) Or (FRepoPath = '') Then
    Exit;
  If Not Assigned(SuggestCommitMessageFunc) Then
    Begin
      MessageDlg(
        'Project Assistant is not available for commit messages.' + LineEnding +
        'Install and enable the LazAssistantTools package, sign in under Assistant Settings, then try again.',
        mtInformation, [mbOK], 0);
      Exit;
    End;
  If FStagedPaths.Count = 0 Then
    Begin
      MessageDlg('Stage at least one change before suggesting a commit message.',
        mtInformation, [mbOK], 0);
      Exit;
    End;
  GitClient.RepoPath := FRepoPath;
  Screen.Cursor := crHourGlass;
  Try
    If Not GitClient.DiffStaged(DiffText) Then
      Begin
        MessageDlg('Could not read staged diff: ' + GitClient.LastError, mtError, [mbOK], 0);
        Exit;
      End;
    If Trim(DiffText) = '' Then
      Begin
        MessageDlg('Staged diff is empty. Stage file contents (not only renames without content) and try again.',
          mtInformation, [mbOK], 0);
        Exit;
      End;
    StatusText := '';
    GitClient.StatusSummaryForCommit(StatusText);
    If Not SuggestCommitMessageFunc(DiffText, StatusText, MessageText, ErrorText) Then
      Begin
        If ErrorText = '' Then
          ErrorText := 'Could not generate a commit message.';
        MessageDlg(ErrorText, mtWarning, [mbOK], 0);
        Exit;
      End;
  Finally
    Screen.Cursor := crDefault;
  End;
  If Assigned(MessageMemo) Then
    Begin
      MessageMemo.Text := MessageText;
      UpdateCommitEnabled;
    End;
  WorkflowLogger.Info('ManageRepository', 'Suggested commit message (' +
    IntToStr(Length(MessageText)) + ' chars)');
End;

Procedure TManageRepositoryForm.MessageChange(Sender: TObject);
Begin
  UpdateCommitEnabled;
End;

Procedure TManageRepositoryForm.FilesDiffStatusChanged(Sender: TObject);
Begin
  RefreshFilesList;
End;

Procedure TManageRepositoryForm.FilesDiffSelectionChanged(Sender: TObject);
Begin
  UpdateStageButtonsEnabled;
End;

Procedure TManageRepositoryForm.CommitActionExecute(Sender: TObject);
Var
  NewSha, Msg: String;
  Summary: TGitTransferSummary;
Begin
  If Not Assigned(GitClient) Or (FRepoPath = '') Then
    Exit;
  Msg := '';
  If Assigned(MessageMemo) Then
    Msg := Trim(MessageMemo.Text);
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

  WorkflowLogger.Info('ManageRepository', 'Created commit ' + NewSha);
  If Assigned(MessageMemo) Then
    MessageMemo.Clear;
  MessageDlg('Committed ' + Copy(NewSha, 1, 7) + '.', mtInformation, [mbOK], 0);

  If Assigned(PushCheckBox) And PushCheckBox.Checked Then
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

Procedure TManageRepositoryForm.RemotesActionExecute(Sender: TObject);
Begin
  If FRepoPath = '' Then
    Begin
      MessageDlg('No repository is bound to this window.', mtInformation, [mbOK], 0);
      Exit;
    End;
  ShowGitRemotesForm(FRepoPath);
  ManualRefresh;
End;

Procedure TManageRepositoryForm.FetchActionExecute(Sender: TObject);
Begin
  If FRepoPath = '' Then
    Exit;
  StartRemoteOp(rokFetch);
End;

Procedure TManageRepositoryForm.PullActionExecute(Sender: TObject);
Begin
  If FRepoPath = '' Then
    Exit;
  StartRemoteOp(rokPull);
End;

Procedure TManageRepositoryForm.PushActionExecute(Sender: TObject);
Begin
  If FRepoPath = '' Then
    Exit;
  StartRemoteOp(rokPush);
End;

Procedure TManageRepositoryForm.CopyShaActionExecute(Sender: TObject);
Var
  Sha: String;
Begin
  Sha := SelectedSha;
  If Sha <> '' Then
    Clipboard.AsText := Sha;
End;

Procedure TManageRepositoryForm.ShowCommitActionExecute(Sender: TObject);
Begin
  If FSelectedIndex >= 0 Then
    ShowCommitDetails(FSelectedIndex);
End;

Procedure TManageRepositoryForm.CheckoutActionExecute(Sender: TObject);
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

Procedure TManageRepositoryForm.CreateBranchActionExecute(Sender: TObject);
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

Procedure TManageRepositoryForm.AutoRefreshTimerTimer(Sender: TObject);
Begin
  If (csDestroying in ComponentState) Or FIndexing Or FDetailLoading Or FRemoteOpBusy Or Not Visible Then
    Exit;
  QuietRefreshIfChanged;
End;

Procedure TManageRepositoryForm.QuietRefreshIfChanged;
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
      WorkflowLogger.Debug('ManageRepository', 'Auto-refresh: repository changed');
      ManualRefresh;
    End
  Else
    Begin
      { Keep dirty flag in sync even when HEAD unchanged. }
      RefreshRepositoryInfo;
      UpdateStatus;
    End;
End;

Procedure TManageRepositoryForm.UpdateStatus;
Var
  LeftText, CentreText, RightText: String;
  ShortSha: String;
Begin
  If FRepoPath = '' Then
    Begin
      If Assigned(StatusFooter) Then
        StatusFooter.SetAll('No repository', '', 'Ready');
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

  If Assigned(StatusFooter) Then
    StatusFooter.SetAll(LeftText, CentreText, RightText);
End;

Procedure TManageRepositoryForm.RefreshRepositoryInfo;
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

Procedure TManageRepositoryForm.BindRepository(Const StartPath: String);
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
    WorkflowLogger.Info('ManageRepository', 'Bound repository: ' + Found)
  Else
    WorkflowLogger.Warning('ManageRepository', 'No repository found from: ' + SearchPath);

  SetRepository(Found);
End;

Procedure TManageRepositoryForm.SetRepository(Const ARepoPath: String);
Begin
  If csDestroying in ComponentState Then
    Exit;
  { Tear down workers and pending UI work before swapping repo identity. }
  If Assigned(FDetailTimer) Then
    FDetailTimer.Enabled := False;
  StopDetailThread;
  StopIndexThread;
  If Assigned(DiffView) Then
    DiffView.Clear;
  FRepoPath := ARepoPath;
  FSelectedIndex := -1;
  If Assigned(FModel) Then
    FModel.Clear;
  If Assigned(GraphScrollBar) Then
    GraphScrollBar.Position := 0;
  If Assigned(GitClient) Then
    GitClient.RepoPath := ARepoPath;
  RefreshRepositoryInfo;
  UpdateScrollRange;
  UpdateStatus;
  If Assigned(GraphPaintBox) Then
    GraphPaintBox.Invalidate;
  If FRepoPath <> '' Then
    StartIndexLoad
  Else If Assigned(FilesList) Then
    FilesList.Items.Clear;
  If Assigned(Pages) And (Pages.ActivePage = FilesTab) Then
    RefreshFilesList;
  ApplyConfig;
End;

Procedure TManageRepositoryForm.RepositoryStateChanged(Const RepoPath: String; NewState: TGitRepositoryState);
Begin
  { Remote ops apply their own single-shot graph update; ignore bus noise mid-op. }
  If FRemoteOpBusy Then
    Exit;
  If SameText(RepoPath, FRepoPath) Then
    BindRepository(FRepoPath);
End;

Procedure TManageRepositoryForm.WorkingTreeChanged(Const RepoPath: String);
Begin
  If FRemoteOpBusy Then
    Exit;
  If SameText(RepoPath, FRepoPath) Then
    Begin
      RefreshRepositoryInfo;
      UpdateStatus;
      If Assigned(Pages) And (Pages.ActivePage = FilesTab) Then
        RefreshFilesList;
    End;
End;

Procedure TManageRepositoryForm.HeadChanged(Const RepoPath: String; Const NewHeadSha: String);
Begin
  If FRemoteOpBusy Then
    Exit;
  If SameText(RepoPath, FRepoPath) Then
    BindRepository(FRepoPath);
End;

Procedure TManageRepositoryForm.RemoteUpdated(Const RepoPath: String; Const RemoteName: String);
Begin
  If FRemoteOpBusy Then
    Exit;
  If SameText(RepoPath, FRepoPath) Then
    If Assigned(StatusFooter) Then
      StatusFooter.SetRightText('Remote ' + RemoteName + ' updated');
End;

End.
