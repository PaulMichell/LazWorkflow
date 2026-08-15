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
  GitGraphModel, GitDiffView, GitJobRunner, GitService;

Type
  { Background Fetch / Pull / Push (History toolbar). }
  TGitRemoteOpKind = (rokNone, rokFetch, rokPull, rokPush);

  TManageRepositoryForm = Class(TForm, IWorkflowListener, IGitRepositoryChanged)
    { Designer-managed controls and event methods (before first Private, as for other forms). }
    ActionList: TActionList;
    PushAction: TAction;
    PullAction: TAction;
    FetchAction: TAction;
    RemotesAction: TAction;
    SettingsAction: TAction;
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
    SettingsButton: TButton;
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
    SuggestButton: TButton;
    CommitButton: TButton;
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
    Procedure SettingsActionExecute(Sender: TObject);
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
    FJobBusy: Boolean;
    FPushAfterCommit: Boolean;
    { Generation tokens invalidate Queue callbacks after cancel; never Synchronize+WaitFor. }
    FIndexGen: Integer;
    FDetailGen: Integer;
    FRemoteGen: Integer;
    FIndexThread: TThread;
    FDetailThread: TThread;
    FRemoteOpThread: TThread;
    FVisibleFirst: Integer;
    FVisibleLast: Integer;
    FLaneColors: Array[0..9] Of TColor;
    FFilesPaths: TStringList;
    FStagedPaths: TStringList;
    FInListSelChange: Boolean;
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
    Procedure ApplyIndexResult(Ok: Boolean; Const Payload: String);
    Procedure ApplyDetailsResult(Ok: Boolean; Const Payload: String);
    Procedure ApplyRemoteOpResult(Ok: Boolean; Const ResultMessage: String; Kind: TGitRemoteOpKind;
      IndexOk: Boolean; Const IndexPayload: String; DetailsOk: Boolean; Const DetailsPayload: String);
    Procedure StartIndexLoad;
    Procedure StartRemoteOp(Kind: TGitRemoteOpKind);
    Procedure SetRemoteActionsEnabled(ActionsEnabled: Boolean);
    Procedure SetJobUiBusy(IsBusy: Boolean; Const StatusCaption: String);
    Procedure GitJobBusyChanged(Sender: TObject; IsBusy: Boolean; Const StatusCaption: String);
    Procedure GitJobFinished(Job: TGitJob);
    Function SubmitGitJob(Job: TGitJob): Boolean;
    Procedure ApplyFilesFromStatus(Const Entries: TGitStatusEntryArray);
    Procedure RefreshFilesListAsync;
    Procedure ScheduleVisibleDetails;
    Procedure StartDetailLoadIfNeeded;
    { Soft cancel: Terminate + bump gen (no WaitFor). Hard dispose used on form Destroy only. }
    Procedure StopIndexThread;
    Procedure StopDetailThread;
    Procedure StopRemoteOpThread;
    Procedure DisposeWorker(Var Worker: TThread; Var Generation: Integer; HardWait: Boolean);
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
  End;

Procedure RefreshOpenManageRepositoryForms;
Procedure ClearOpenManageRepositoryForms;
Procedure ApplyRepositoryConfigToOpenForms;

Implementation

{$R *.lfm}

Uses
  WorkflowLog, GitConfig, GitRemotesForm, GitSettingsForm, GitIgnoreForm, LazIDEIntf, ProjectIntf,
  DateUtils, Math, FileUtil, LazFileUtils, StrUtils, Process
  {$IFDEF WINDOWS}, ShellApi{$ENDIF};

Type
  { Workers deliver via Queue (not Synchronize) so the form may Terminate+WaitFor on
    the main thread without deadlock. Results live on the worker; generation tokens
    drop stale Queue callbacks after cancel. }

  TGitIndexThread = Class(TThread)
  Private
    FForm: TManageRepositoryForm;
    FRepoPath: String;
    FGeneration: Integer;
    FResultOk: Boolean;
    FResultText: String;
    Procedure Deliver;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(AForm: TManageRepositoryForm; Const ARepoPath: String; AGeneration: Integer);
    Procedure DetachForm;
    Property Generation: Integer Read FGeneration;
  End;

  TGitDetailThread = Class(TThread)
  Private
    FForm: TManageRepositoryForm;
    FRepoPath: String;
    FGeneration: Integer;
    FShas: TStringList;
    FResultOk: Boolean;
    FResultText: String;
    Procedure Deliver;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(AForm: TManageRepositoryForm; Const ARepoPath: String; AShas: TStringList;
      AGeneration: Integer);
    Destructor Destroy; Override;
    Procedure DetachForm;
    Property Generation: Integer Read FGeneration;
  End;

  { Fetch/Pull/Push then loads index + first detail batch off-thread.
    History UI is updated only in ApplyRemoteOpResult after a successful transfer. }
  TGitRemoteOpThread = Class(TThread)
  Private
    FForm: TManageRepositoryForm;
    FRepoPath: String;
    FGeneration: Integer;
    FKind: TGitRemoteOpKind;
    FResultOk: Boolean;
    FResultMessage: String;
    FIndexOk: Boolean;
    FIndexText: String;
    FDetailsOk: Boolean;
    FDetailsText: String;
    Procedure Deliver;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(AForm: TManageRepositoryForm; Const ARepoPath: String; Kind: TGitRemoteOpKind;
      AGeneration: Integer);
    Procedure DetachForm;
    Property Generation: Integer Read FGeneration;
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

Constructor TGitIndexThread.Create(AForm: TManageRepositoryForm; Const ARepoPath: String;
  AGeneration: Integer);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  FForm := AForm;
  FRepoPath := ARepoPath;
  FGeneration := AGeneration;
  FResultOk := False;
  FResultText := '';
End;

Procedure TGitIndexThread.DetachForm;
Begin
  FForm := Nil;
End;

Procedure TGitIndexThread.Deliver;
Var
  Form: TManageRepositoryForm;
  Gen: Integer;
  Ok: Boolean;
  Text: String;
Begin
  { Main thread after Execute. Free Self here on soft-cancel / success paths.
    Hard dispose removes this Queue and frees the thread itself. }
  Form := FForm;
  Gen := FGeneration;
  Ok := FResultOk;
  Text := FResultText;
  If Not Assigned(Form) Then
    Begin
      Free;
      Exit;
    End;
  If Form.FIndexThread = Self Then
    Form.FIndexThread := Nil;
  If (Gen = Form.FIndexGen) And Not (csDestroying in Form.ComponentState) And
     Not Application.Terminated Then
    Form.ApplyIndexResult(Ok, Text)
  Else If Not Assigned(Form.FIndexThread) Then
    Form.FIndexing := False;
  Free;
End;

Procedure TGitIndexThread.Execute;
Var
  Client: TGitService;
Begin
  Client := TGitService.Create;
  Try
    Client.PublishEvents := False;
    If Not Terminated Then
      FResultOk := Client.FetchRevListParents(FRepoPath, FResultText);
  Finally
    Client.Free;
  End;
  { Queue even after DetachForm so soft-cancel can Free Self on the main thread.
    Hard dispose RemoveQueuedEvents this before WaitFor+Free. }
  Queue(@Deliver);
End;

Constructor TGitDetailThread.Create(AForm: TManageRepositoryForm; Const ARepoPath: String;
  AShas: TStringList; AGeneration: Integer);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  FForm := AForm;
  FRepoPath := ARepoPath;
  FGeneration := AGeneration;
  FShas := AShas; { takes ownership }
  FResultOk := False;
  FResultText := '';
End;

Destructor TGitDetailThread.Destroy;
Begin
  FreeAndNil(FShas);
  Inherited Destroy;
End;

Procedure TGitDetailThread.DetachForm;
Begin
  FForm := Nil;
End;

Procedure TGitDetailThread.Deliver;
Var
  Form: TManageRepositoryForm;
  Gen: Integer;
  Ok: Boolean;
  Text: String;
Begin
  Form := FForm;
  Gen := FGeneration;
  Ok := FResultOk;
  Text := FResultText;
  If Not Assigned(Form) Then
    Begin
      Free;
      Exit;
    End;
  If Form.FDetailThread = Self Then
    Form.FDetailThread := Nil;
  If (Gen = Form.FDetailGen) And Not (csDestroying in Form.ComponentState) And
     Not Application.Terminated Then
    Form.ApplyDetailsResult(Ok, Text)
  Else If Not Assigned(Form.FDetailThread) Then
    Form.FDetailLoading := False;
  Free;
End;

Procedure TGitDetailThread.Execute;
Var
  Client: TGitService;
Begin
  Client := TGitService.Create;
  Try
    Client.PublishEvents := False;
    If Not Terminated Then
      FResultOk := Client.FetchCommitDetails(FRepoPath, FShas, FResultText);
  Finally
    Client.Free;
  End;
  Queue(@Deliver);
End;

Constructor TGitRemoteOpThread.Create(AForm: TManageRepositoryForm; Const ARepoPath: String;
  Kind: TGitRemoteOpKind; AGeneration: Integer);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  FForm := AForm;
  FRepoPath := ARepoPath;
  FGeneration := AGeneration;
  FKind := Kind;
  FResultOk := False;
  FResultMessage := '';
  FIndexOk := False;
  FIndexText := '';
  FDetailsOk := False;
  FDetailsText := '';
End;

Procedure TGitRemoteOpThread.DetachForm;
Begin
  FForm := Nil;
End;

Procedure TGitRemoteOpThread.Deliver;
Var
  Form: TManageRepositoryForm;
  Gen: Integer;
  Ok, IndexOk, DetailsOk: Boolean;
  ResultMessage, IndexText, DetailsText: String;
  Kind: TGitRemoteOpKind;
Begin
  Form := FForm;
  Gen := FGeneration;
  Ok := FResultOk;
  ResultMessage := FResultMessage;
  Kind := FKind;
  IndexOk := FIndexOk;
  IndexText := FIndexText;
  DetailsOk := FDetailsOk;
  DetailsText := FDetailsText;
  If Not Assigned(Form) Then
    Begin
      Free;
      Exit;
    End;
  If Form.FRemoteOpThread = Self Then
    Form.FRemoteOpThread := Nil;
  If (Gen = Form.FRemoteGen) And Not Form.FRemoteOpSuppressResult And
     Not (csDestroying in Form.ComponentState) And Not Application.Terminated Then
    Form.ApplyRemoteOpResult(Ok, ResultMessage, Kind, IndexOk, IndexText, DetailsOk, DetailsText)
  Else If Form.FRemoteOpBusy And Not Assigned(Form.FRemoteOpThread) Then
    Begin
      Form.FRemoteOpBusy := False;
      Screen.Cursor := crDefault;
      Form.SetRemoteActionsEnabled(True);
    End;
  Free;
End;

Procedure TGitRemoteOpThread.Execute;
Var
  Client: TGitService;
  Summary: TGitTransferSummary;
  Shas: TStringList;
Begin
  Client := TGitService.Create;
  Try
    { This worker is leftover; if it is started again it must not publish UI events. }
    Client.PublishEvents := False;
    Client.RepoPath := FRepoPath;
    Summary := Default(TGitTransferSummary);
    If Not Terminated Then
      Begin
        Case FKind Of
          rokFetch: FResultOk := Client.Fetch(Summary);
          rokPull: FResultOk := Client.Pull(Summary);
          rokPush: FResultOk := Client.Push(Summary);
        Else
          FResultOk := False;
          Summary.Message := 'Unknown remote operation.';
        End;
        FResultMessage := Summary.Message;
      End;

    { After a successful transfer, load index + first detail batch before any UI update. }
    If FResultOk And Assigned(FForm) And Not Terminated Then
      Begin
        FIndexOk := Client.FetchRevListParents(FRepoPath, FIndexText);
        If FIndexOk And Assigned(FForm) And Not Terminated Then
          Begin
            Shas := TStringList.Create;
            Try
              CollectLeadingShas(FIndexText, GitGraphDetailBatch, Shas);
              If (Shas.Count > 0) And Not Terminated Then
                FDetailsOk := Client.FetchCommitDetails(FRepoPath, Shas, FDetailsText);
            Finally
              Shas.Free;
            End;
          End;
      End;
  Finally
    Client.Free;
  End;
  Queue(@Deliver);
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
  FJobBusy := False;
  FPushAfterCommit := False;
  FIndexGen := 0;
  FDetailGen := 0;
  FRemoteGen := 0;
  FIndexThread := Nil;
  FDetailThread := Nil;
  FRemoteOpThread := Nil;
  FVisibleFirst := 0;
  FVisibleLast := 0;
  FFilesPaths := TStringList.Create;
  FStagedPaths := TStringList.Create;
  FInListSelChange := False;
  FModel := TGitGraphModel.Create;
  InitLaneColors;
  ApplyConfig;
  WorkflowEventBus.AddListener(Self);
  If Assigned(GitJobs) Then
    GitJobs.OnBusyChanged := @GitJobBusyChanged;
End;

Destructor TManageRepositoryForm.Destroy;
Begin
  If Assigned(FDetailTimer) Then
    FDetailTimer.Enabled := False;
  If Assigned(FAutoRefreshTimer) Then
    FAutoRefreshTimer.Enabled := False;
  If Assigned(GitJobs) Then
    Begin
      GitJobs.OnBusyChanged := Nil;
      GitJobs.CancelCurrent;
    End;
  { Hard dispose: Queue (not Synchronize) so WaitFor cannot deadlock the UI thread. }
  DisposeWorker(FRemoteOpThread, FRemoteGen, True);
  DisposeWorker(FDetailThread, FDetailGen, True);
  DisposeWorker(FIndexThread, FIndexGen, True);
  FRemoteOpBusy := False;
  FIndexing := False;
  FDetailLoading := False;
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
  If Not Assigned(GitManagerConfig) Then
    Exit;
  If Assigned(FAutoRefreshTimer) Then
    Begin
      FAutoRefreshTimer.Enabled := False;
      FAutoRefreshTimer.Interval := GitManagerConfig.AutoRefreshSeconds * 1000;
      FAutoRefreshTimer.Enabled := GitManagerConfig.AutoRefresh And (FRepoPath <> '');
    End;
  { Graph font changes affect row metrics and painted text. }
  UpdateScrollRange;
  If Assigned(GraphPaintBox) Then
    GraphPaintBox.Invalidate;
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
Var
  FocusedControl: TWinControl;
Begin
  FocusedControl := ActiveControl;
  { Graph keys must not steal arrows/Enter from the commit message or file lists. }
  If (Key <> VK_F5) And Assigned(FocusedControl) Then
    If (FocusedControl = MessageMemo) Or (FocusedControl = FilesList) Or
       (FocusedControl = StagedList) Or (FocusedControl Is TCustomEdit) Or
       (FocusedControl Is TCustomListBox) Then
      Exit;
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

Procedure TManageRepositoryForm.DisposeWorker(Var Worker: TThread; Var Generation: Integer;
  HardWait: Boolean);
Var
  Pending: TThread;
Begin
  { Bump generation first so any already-queued Deliver is ignored. }
  Inc(Generation);
  If Not Assigned(Worker) Then
    Exit;
  Pending := Worker;
  Worker := Nil;
  Pending.Terminate;
  { Always detach so a later Deliver cannot touch this form after it is freed. }
  If Pending Is TGitIndexThread Then
    TGitIndexThread(Pending).DetachForm
  Else If Pending Is TGitDetailThread Then
    TGitDetailThread(Pending).DetachForm
  Else If Pending Is TGitRemoteOpThread Then
    TGitRemoteOpThread(Pending).DetachForm;
  If HardWait Then
    Begin
      TThread.RemoveQueuedEvents(Pending);
      Pending.WaitFor;
      { Catch a Queue posted in the race between Detach and thread exit. }
      TThread.RemoveQueuedEvents(Pending);
      Pending.Free;
    End;
  { Soft cancel: abandon the pointer. Execute still Queue's Deliver, which
    sees FForm = Nil and Frees the worker on the main thread. }
End;

Procedure TManageRepositoryForm.StopIndexThread;
Begin
  DisposeWorker(FIndexThread, FIndexGen, False);
  FIndexing := False;
End;

Procedure TManageRepositoryForm.StopDetailThread;
Begin
  DisposeWorker(FDetailThread, FDetailGen, False);
  FDetailLoading := False;
End;

Procedure TManageRepositoryForm.StopRemoteOpThread;
Begin
  FRemoteOpSuppressResult := True;
  DisposeWorker(FRemoteOpThread, FRemoteGen, False);
  If FRemoteOpBusy Then
    Begin
      FRemoteOpBusy := False;
      Screen.Cursor := crDefault;
      SetRemoteActionsEnabled(True);
    End;
End;

Procedure TManageRepositoryForm.SetRemoteActionsEnabled(ActionsEnabled: Boolean);
Var
  Allow: Boolean;
Begin
  { Job busy and remote-op busy both gate History toolbar actions. }
  Allow := ActionsEnabled And (Not FJobBusy) And (Not FRemoteOpBusy);
  If Assigned(FetchAction) Then
    FetchAction.Enabled := Allow;
  If Assigned(PullAction) Then
    PullAction.Enabled := Allow;
  If Assigned(PushAction) Then
    PushAction.Enabled := Allow;
  If Assigned(RemotesAction) Then
    RemotesAction.Enabled := Allow;
  { Settings is always available (local identity / refresh options). }
  If Assigned(SettingsAction) Then
    SettingsAction.Enabled := True;
End;

Procedure TManageRepositoryForm.SetJobUiBusy(IsBusy: Boolean; Const StatusCaption: String);
Begin
  FJobBusy := IsBusy;
  If IsBusy Then
    Begin
      Screen.Cursor := crHourGlass;
      SetRemoteActionsEnabled(False);
      If Assigned(StatusFooter) And (StatusCaption <> '') Then
        StatusFooter.SetRightText(StatusCaption);
    End
  Else
    Begin
      Screen.Cursor := crDefault;
      { Re-evaluate gates; FRemoteOpBusy may still be true until GitJobFinished. }
      SetRemoteActionsEnabled(True);
      UpdateStatus;
    End;
End;

Procedure TManageRepositoryForm.GitJobBusyChanged(Sender: TObject; IsBusy: Boolean; Const StatusCaption: String);
Begin
  If csDestroying in ComponentState Then
    Exit;
  SetJobUiBusy(IsBusy, StatusCaption);
End;

Function TManageRepositoryForm.SubmitGitJob(Job: TGitJob): Boolean;
Begin
  Result := False;
  If Not Assigned(Job) Then
    Exit;
  If Not Assigned(GitJobs) Then
    Begin
      FreeAndNil(Job);
      MessageDlg('Git job runner is not available.', mtError, [mbOK], 0);
      Exit;
    End;
  If (FRepoPath = '') And (Job.Kind <> gjkClone) And (Job.Kind <> gjkInit) Then
    Begin
      FreeAndNil(Job);
      Exit;
    End;
  If Job.RepoPath = '' Then
    Job.RepoPath := FRepoPath;
  Job.OnFinished := @GitJobFinished;
  Result := GitJobs.Submit(Job);
  If Not Result Then
    MessageDlg('Could not queue Git operation (queue full or runner stopped).', mtWarning, [mbOK], 0);
End;

Procedure TManageRepositoryForm.GitJobFinished(Job: TGitJob);
Var
  Msg: String;
Begin
  If (csDestroying in ComponentState) Or Not Assigned(Job) Then
    Exit;

  Case Job.Kind Of
    gjkFetch, gjkPull, gjkPush:
      Begin
        { Busy-notify often runs before this handler while FRemoteOpBusy is still True,
          so re-enable must happen here after clearing the remote-op flag. }
        FRemoteOpBusy := False;
        FJobBusy := False;
        Screen.Cursor := crDefault;
        SetRemoteActionsEnabled(True);
        If Job.Cancelled Then
          Begin
            If Assigned(StatusFooter) Then
              StatusFooter.SetRightText('Cancelled');
            UpdateStatus;
            Exit;
          End;
        Msg := Job.ErrorText;
        If Msg = '' Then
          If Job.Ok Then
            Msg := 'Done.'
          Else
            Msg := 'Operation failed.';
        If Job.Ok Then
          Begin
            MessageDlg(Msg, mtInformation, [mbOK], 0);
            ManualRefresh;
            If Assigned(Pages) And (Pages.ActivePage = FilesTab) Then
              RefreshFilesListAsync;
          End
        Else
          MessageDlg(Msg, mtError, [mbOK], 0);
        UpdateStatus;
      End;
    gjkCommit:
      Begin
        If Job.Cancelled Then
          Exit;
        If Not Job.Ok Then
          Begin
            MessageDlg('Commit failed: ' + Job.ErrorText, mtError, [mbOK], 0);
            RefreshFilesListAsync;
            Exit;
          End;
        WorkflowLogger.Info('ManageRepository', 'Created commit ' + Job.ResultSha);
        If Assigned(MessageMemo) Then
          MessageMemo.Clear;
        MessageDlg('Committed ' + Copy(Job.ResultSha, 1, 7) + '.', mtInformation, [mbOK], 0);
        If FPushAfterCommit Then
          Begin
            FPushAfterCommit := False;
            StartRemoteOp(rokPush);
          End
        Else
          Begin
            RefreshFilesListAsync;
            ManualRefresh;
          End;
      End;
    gjkCheckout:
      Begin
        If Job.Cancelled Then
          Exit;
        If Job.Ok Then
          ManualRefresh
        Else
          MessageDlg('Checkout failed: ' + Job.ErrorText, mtError, [mbOK], 0);
      End;
    gjkCreateBranch:
      Begin
        If Job.Cancelled Then
          Exit;
        If Job.Ok Then
          Begin
            MessageDlg('Created branch "' + Job.MessageText + '" at ' + Copy(Job.RefName, 1, 7),
              mtInformation, [mbOK], 0);
            ManualRefresh;
          End
        Else
          MessageDlg('Create branch failed: ' + Job.ErrorText, mtError, [mbOK], 0);
      End;
    gjkStagePaths, gjkUnstagePaths:
      Begin
        If Job.Cancelled Then
          Exit;
        If Not Job.Ok Then
          MessageDlg(Job.Caption + ' failed: ' + Job.ErrorText, mtError, [mbOK], 0);
        RefreshFilesListAsync;
      End;
    gjkListStatus:
      Begin
        If Job.Cancelled Then
          Exit;
        If Job.Ok Then
          ApplyFilesFromStatus(Job.StatusEntries)
        Else
          Begin
            If Assigned(FilesList) Then
              Begin
                FilesList.Items.Clear;
                FilesList.Items.Add('(status failed)');
              End;
            WorkflowLogger.Warning('ManageRepository', 'ListStatus: ' + Job.ErrorText);
            UpdateCommitEnabled;
            UpdateStageButtonsEnabled;
          End;
      End;
  Else
    { ignore }
  End;
End;

Procedure TManageRepositoryForm.StartRemoteOp(Kind: TGitRemoteOpKind);
Var
  Job: TGitJob;
  JobKind: TGitJobKind;
Begin
  If (FRepoPath = '') Or FRemoteOpBusy Or FJobBusy Then
    Exit;
  Case Kind Of
    rokFetch: JobKind := gjkFetch;
    rokPull: JobKind := gjkPull;
    rokPush: JobKind := gjkPush;
  Else
    Exit;
  End;
  If Assigned(FDetailTimer) Then
    FDetailTimer.Enabled := False;
  StopDetailThread;
  StopIndexThread;
  FIndexing := False;
  FRemoteOpSuppressResult := False;
  FRemoteOpBusy := True;
  Job := TGitJob.Create(JobKind);
  Job.RepoPath := FRepoPath;
  If Not SubmitGitJob(Job) Then
    FRemoteOpBusy := False;
End;

Procedure TManageRepositoryForm.ApplyRemoteOpResult(Ok: Boolean; Const ResultMessage: String;
  Kind: TGitRemoteOpKind; IndexOk: Boolean; Const IndexPayload: String; DetailsOk: Boolean;
  Const DetailsPayload: String);
Var
  Parsed: Integer;
Begin
  If (csDestroying in ComponentState) Or Application.Terminated Then
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

      If IndexOk And Assigned(FModel) Then
        Begin
          Parsed := FModel.ParseRevListParents(IndexPayload);
          If DetailsOk And (DetailsPayload <> '') Then
            FModel.ApplyDetailsText(DetailsPayload);
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
  StopIndexThread; { bumps FIndexGen and soft-cancels any prior worker }
  FIndexing := True;
  If Assigned(StatusFooter) Then
    StatusFooter.SetRightText('Indexing…');
  FIndexThread := TGitIndexThread.Create(Self, FRepoPath, FIndexGen);
  FIndexThread.Start;
End;

Procedure TManageRepositoryForm.ApplyIndexResult(Ok: Boolean; Const Payload: String);
Var
  Parsed: Integer;
Begin
  FIndexing := False;
  If (csDestroying in ComponentState) Or Not Assigned(FModel) Or Not Assigned(DiffView) Then
    Exit;
  If Not Ok Then
    Begin
      If Assigned(StatusFooter) Then
        StatusFooter.SetRightText('Index failed');
      WorkflowLogger.Warning('ManageRepository', 'rev-list failed for ' + FRepoPath);
      Exit;
    End;

  Parsed := FModel.ParseRevListParents(Payload);
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

Procedure TManageRepositoryForm.ApplyDetailsResult(Ok: Boolean; Const Payload: String);
Begin
  FDetailLoading := False;
  If (csDestroying in ComponentState) Or Not Assigned(FModel) Then
    Exit;
  If Ok Then
    FModel.ApplyDetailsText(Payload);
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
  Inc(FDetailGen);
  FDetailThread := TGitDetailThread.Create(Self, FRepoPath, Shas, FDetailGen);
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
Var
  FontName: String;
  FontSize: Integer;
Begin
  If Not Assigned(ACanvas) Then
    Exit;
  FontName := Font.Name;
  FontSize := GitConfigDefaultGraphFontSize;
  If Assigned(GitManagerConfig) Then
    Begin
      If Trim(GitManagerConfig.GraphFontName) <> '' Then
        FontName := GitManagerConfig.GraphFontName;
      FontSize := GitManagerConfig.GraphFontSize;
    End;
  { Point sizes only — never assign Font.Height := 0 (forces Size 0 intermediate). }
  ACanvas.Font.Name := FontName;
  ACanvas.Font.Style := [];
  ACanvas.Font.Quality := fqCleartypeNatural;
  ACanvas.Font.Size := FontSize;
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
Begin
  RefreshFilesListAsync;
End;

Procedure TManageRepositoryForm.RefreshFilesListAsync;
Var
  Job: TGitJob;
Begin
  If Not Assigned(FilesList) Or Not Assigned(StagedList) Then
    Exit;
  If (FRepoPath = '') Or Not DirectoryExists(FRepoPath) Then
    Begin
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
      UpdateCommitEnabled;
      UpdateStageButtonsEnabled;
      Exit;
    End;
  Job := TGitJob.Create(gjkListStatus);
  Job.RepoPath := FRepoPath;
  Job.Caption := 'Refreshing files…';
  Job.IncludeUntracked := Assigned(UntrackedCheck) And UntrackedCheck.Checked;
  Job.IncludeIgnored := Assigned(IgnoredCheck) And IgnoredCheck.Checked;
  SubmitGitJob(Job);
End;

Procedure TManageRepositoryForm.ApplyFilesFromStatus(Const Entries: TGitStatusEntryArray);
Var
  AllFiles, StatusMap, FullyStaged: TStringList;
  I: Integer;
  FullPath, Rel, Root, StatusText: String;
  Idx: Integer;
  EntryStatus: String;
  WantClean: Boolean;
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

      { Full-tree scan only when the user asked to show clean files (item 6 still open). }
      WantClean := Assigned(CleanCheck) And CleanCheck.Checked;
      AllFiles.Sorted := True;
      AllFiles.Duplicates := dupIgnore;
      If WantClean Then
        FindAllFiles(AllFiles, FRepoPath, '*', True)
      Else
        { Still walk status paths so deleted/untracked/modified appear without FindAllFiles. }
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
  HasStaged, CanCommit, AssistantAvailable: Boolean;
Begin
  HasStaged := Assigned(FStagedPaths) And (FStagedPaths.Count > 0);
  CanCommit := HasStaged And Assigned(MessageMemo) And (Trim(MessageMemo.Text) <> '');
  { Suggest is permanently off unless LazAssistantTools registered the commit-message hook. }
  AssistantAvailable := Assigned(SuggestCommitMessageFunc);
  If Assigned(SuggestMessageAction) Then
    Begin
      SuggestMessageAction.Enabled := HasStaged And AssistantAvailable;
      If Not AssistantAvailable Then
        SuggestMessageAction.Hint :=
          'Install LazAssistantTools to suggest commit messages from the Project Assistant.'
      Else
        SuggestMessageAction.Hint := 'Suggest a commit message from the staged diff';
    End;
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
  If FInListSelChange Then
    Exit;
  FInListSelChange := True;
  Try
    { Keep multi-select on this list; only clear the other list's selection. }
    If Assigned(StagedList) And ListHasSelection(StagedList) Then
      StagedList.ClearSelection;
    ShowFilesDiff(FilesList, FFilesPaths, False);
    UpdateStageButtonsEnabled;
  Finally
    FInListSelChange := False;
  End;
End;

Procedure TManageRepositoryForm.FilesListDblClick(Sender: TObject);
Begin
  StageActionExecute(Sender);
End;

Procedure TManageRepositoryForm.StagedListSelectionChange(Sender: TObject; User: Boolean);
Begin
  If FInListSelChange Then
    Exit;
  FInListSelChange := True;
  Try
    If Assigned(FilesList) And ListHasSelection(FilesList) Then
      FilesList.ClearSelection;
    ShowFilesDiff(StagedList, FStagedPaths, True);
    UpdateStageButtonsEnabled;
  Finally
    FInListSelChange := False;
  End;
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
  Job: TGitJob;
Begin
  If (FRepoPath = '') Or FJobBusy Then
    Exit;
  FilesEmpty := (Not Assigned(FFilesPaths)) Or (FFilesPaths.Count = 0);
  UnstageMode := Assigned(FStagedPaths) And (FStagedPaths.Count > 0) And
    (FilesEmpty Or ListHasSelection(StagedList));

  If UnstageMode Then
    Begin
      Paths := CollectSelectedPaths(StagedList, FStagedPaths);
      If Paths.Count = 0 Then
        Begin
          Paths.Free;
          MessageDlg('Select one or more files in the staged list to unstage.', mtInformation, [mbOK], 0);
          Exit;
        End;
      Job := TGitJob.Create(gjkUnstagePaths);
      Job.RepoPath := FRepoPath;
      Job.TakePaths(Paths);
      SubmitGitJob(Job);
    End
  Else
    Begin
      Paths := CollectSelectedPaths(FilesList, FFilesPaths);
      If Paths.Count = 0 Then
        Begin
          Paths.Free;
          MessageDlg('Select one or more files in the file list to stage.', mtInformation, [mbOK], 0);
          Exit;
        End;
      Job := TGitJob.Create(gjkStagePaths);
      Job.RepoPath := FRepoPath;
      Job.TakePaths(Paths);
      SubmitGitJob(Job);
    End;
End;

Procedure TManageRepositoryForm.StageAllActionExecute(Sender: TObject);
Var
  FilesEmpty, StagedEmpty: Boolean;
  Job: TGitJob;
Begin
  If (FRepoPath = '') Or FJobBusy Then
    Exit;
  FilesEmpty := (Not Assigned(FFilesPaths)) Or (FFilesPaths.Count = 0);
  StagedEmpty := (Not Assigned(FStagedPaths)) Or (FStagedPaths.Count = 0);
  If (Not StagedEmpty) And FilesEmpty Then
    Begin
      Job := TGitJob.Create(gjkUnstagePaths);
      Job.RepoPath := FRepoPath;
      Job.CopyPathsFrom(FStagedPaths);
      SubmitGitJob(Job);
    End
  Else
    Begin
      If FilesEmpty Then
        Exit;
      Job := TGitJob.Create(gjkStagePaths);
      Job.RepoPath := FRepoPath;
      Job.CopyPathsFrom(FFilesPaths);
      SubmitGitJob(Job);
    End;
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
  { Button stays disabled when the assistant package is not installed. }
  If Not Assigned(SuggestCommitMessageFunc) Then
    Exit;
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
  Msg: String;
  Job: TGitJob;
Begin
  If FRepoPath = '' Then
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
  If FJobBusy Then
    Exit;

  FPushAfterCommit := Assigned(PushCheckBox) And PushCheckBox.Checked;
  Job := TGitJob.Create(gjkCommit);
  Job.RepoPath := FRepoPath;
  Job.MessageText := Msg;
  SubmitGitJob(Job);
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

Procedure TManageRepositoryForm.SettingsActionExecute(Sender: TObject);
Begin
  ShowGitSettingsForm;
  ApplyConfig;
  ApplyRepositoryConfigToOpenForms;
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
  Job: TGitJob;
Begin
  Sha := SelectedSha;
  If (Sha = '') Or (FRepoPath = '') Or FJobBusy Then
    Exit;
  If MessageDlg('Check out commit ' + Copy(Sha, 1, 7) + '?' + LineEnding +
    'This may detach HEAD.', mtConfirmation, [mbYes, mbNo], 0) <> mrYes Then
    Exit;
  Job := TGitJob.Create(gjkCheckout);
  Job.RepoPath := FRepoPath;
  Job.RefName := Sha;
  SubmitGitJob(Job);
End;

Procedure TManageRepositoryForm.CreateBranchActionExecute(Sender: TObject);
Var
  Sha, BranchName: String;
  Job: TGitJob;
Begin
  Sha := SelectedSha;
  If (Sha = '') Or (FRepoPath = '') Or FJobBusy Then
    Exit;
  BranchName := '';
  If Not InputQuery('Create branch', 'Branch name:', BranchName) Then
    Exit;
  BranchName := Trim(BranchName);
  If BranchName = '' Then
    Exit;
  Job := TGitJob.Create(gjkCreateBranch);
  Job.RepoPath := FRepoPath;
  Job.MessageText := BranchName;
  Job.RefName := Sha;
  SubmitGitJob(Job);
End;

Procedure TManageRepositoryForm.AutoRefreshTimerTimer(Sender: TObject);
Begin
  If (csDestroying in ComponentState) Or FIndexing Or FDetailLoading Or FRemoteOpBusy Or FJobBusy Or
     Not Visible Then
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
  { Remote ops / jobs apply their own UI update; ignore bus noise mid-op. }
  If FRemoteOpBusy Or FJobBusy Then
    Exit;
  If SameText(RepoPath, FRepoPath) Then
    BindRepository(FRepoPath);
End;

Procedure TManageRepositoryForm.WorkingTreeChanged(Const RepoPath: String);
Begin
  { Job completions refresh UI themselves; ignore bus noise mid-job. }
  If FRemoteOpBusy Or FJobBusy Then
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
  If FRemoteOpBusy Or FJobBusy Then
    Exit;
  If SameText(RepoPath, FRepoPath) Then
    BindRepository(FRepoPath);
End;

Procedure TManageRepositoryForm.RemoteUpdated(Const RepoPath: String; Const RemoteName: String);
Begin
  If FRemoteOpBusy Or FJobBusy Then
    Exit;
  If SameText(RepoPath, FRepoPath) Then
    If Assigned(StatusFooter) Then
      StatusFooter.SetRightText('Remote ' + RemoteName + ' updated');
End;

End.
