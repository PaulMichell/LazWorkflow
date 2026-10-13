Unit ManageRepositoryForm;

{ Manage Repository window – virtual commit graph and git tools (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. The .lfm remains the shell;
  History graph paint, Changes lists, and Files inspection live in coordinator units.
  Reviewed 2026-08: job/window orchestration stays on the form. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Menus, ActnList, Clipbrd, LCLIntf, LCLType, SynEdit, SpellMemo, WorkflowEvents, StatusFooterFrame,
  GitGraphModel, GitDiffView, GitJobRunner, GitService, ManageRepositoryHistory, ManageRepositoryChanges,
  ManageRepositoryFiles;

Type
  { Background Fetch / Pull / Push (History toolbar). }
  TGitRemoteOpKind = (rokNone, rokFetch, rokPull, rokPush);

  TManageRepositoryForm = Class(TForm, IGitRepositoryChanged)
    { Designer-managed controls and event methods (before first Private, as for other forms). }
    ActionList: TActionList;
    RemovedFilesCheckBox: TCheckBox;
    FilesPanel: TPanel;
    PushAction: TAction;
    PullAction: TAction;
    FetchAction: TAction;
    AmendAction: TAction;
    RemoveAction: TAction;
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
    ChangesTab: TTabSheet;
    MainPanel: TPanel;
    DetailPanel: TPanel;
    HistoryButtons: TPanel;
    PushButton: TButton;
    PullButton: TButton;
    FetchButton: TButton;
    AmendButton: TButton;
    RemoveButton: TButton;
    RemotesButton: TButton;
    SettingsButton: TButton;
    DiffView: TGitDiffView;
    HistorySplitter: TSplitter;
    GraphHost: TPanel;
    GraphScrollBar: TScrollBar;
    GraphPaintBox: TPaintBox;
    ChangesLeftPanel: TPanel;
    ChangesList: TListBox;
    ChangesBottomPanel: TPanel;
    FilterGroupBox: TGroupBox;
    FilesTabSheet: TTabSheet;
    FilesLeftPanel: TPanel;
    FileCommitPanel: TPanel;
    FileCommitList: TListBox;
    FileCommitLabel: TLabel;
    FileCommitSplitter: TSplitter;
    FileTree: TTreeView;
    FilesSplitter: TSplitter;
    FilesRightPanel: TPanel;
    FileRevisionEditor: TSynEdit;
    FilePreviewPanel: TPanel;
    FilePreviewLabel: TLabel;
    FileImagePaintBox: TPaintBox;
    UntrackedCheck: TCheckBox;
    CleanCheck: TCheckBox;
    IgnoredCheck: TCheckBox;
    ChangesSplitter: TSplitter;
    ChangesRightPanel: TPanel;
    CommitPanel: TPanel;
    MessageLabel: TLabel;
    MessageEditor: TSpellMemo;
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
    ChangesDiffView: TGitDiffView;
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
    Procedure AmendActionExecute(Sender: TObject);
    Procedure RemoveActionExecute(Sender: TObject);
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
    Procedure ChangesListSelectionChange(Sender: TObject; User: Boolean);
    Procedure ChangesListDblClick(Sender: TObject);
    Procedure StagedListSelectionChange(Sender: TObject; User: Boolean);
    Procedure StagedListDblClick(Sender: TObject);
    Procedure FileFilterChange(Sender: TObject);
    Procedure ChangesDiffStatusChanged(Sender: TObject);
    Procedure RemoteActionUpdate(Sender: TObject);
    Procedure StageAllActionUpdate(Sender: TObject);
    Procedure StageActionUpdate(Sender: TObject);
    Procedure StageSelectionActionUpdate(Sender: TObject);
    Procedure PathActionUpdate(Sender: TObject);
    Procedure IgnoredFilesActionUpdate(Sender: TObject);
    Procedure SuggestMessageActionUpdate(Sender: TObject);
    Procedure CommitActionUpdate(Sender: TObject);
    Procedure HistoryViewActionUpdate(Sender: TObject);
    Procedure HistoryMutateActionUpdate(Sender: TObject);
    Procedure RewriteHeadActionUpdate(Sender: TObject);
    Procedure FileTreeChange(Sender: TObject; Node: TTreeNode);
    Procedure FileTreeMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    Procedure FileCommitListSelectionChange(Sender: TObject; User: Boolean);
    Procedure FileImagePaintBoxPaint(Sender: TObject);
  Private
    FDetailTimer: TTimer;
    FAutoRefreshTimer: TTimer;
    FRepoPath: String;
    FBranch: String;
    FHeadSha: String;
    FHeadPushed: Boolean;
    FHeadPushedKnown: Boolean;
    FAmendHead: Boolean;
    FClean: Boolean;
    FModel: TGitGraphModel;
    FHistory: TManageHistoryGraph;
    FChanges: TManageChangesPane;
    FFiles: TManageFilesPane;
    FFilesNeedReload: Boolean;
    FSelectedIndex: Integer;
    FIndexing: Boolean;
    FDetailLoading: Boolean;
    FRemoteOpBusy: Boolean;
    FJobBusy: Boolean;
    FRepoGeneration: QWord;
    { Generation tokens drop stale index/detail jobs after a rebind or cancel. }
    FIndexGen: Integer;
    FDetailGen: Integer;

    { Path lists live on FChanges. }
    FInListSelChange: Boolean;
    FStatusGen: Integer;
    FStatusJobPending: Boolean;
    FProbePending: Boolean;
    FCachedGitDir, FRefsDigest: String;
    FLastPorcelain: String;
    FLastHeadAge: LongInt;
    FLastIndexAge: LongInt;
    FLastProbeAt: TDateTime;
    FProbeIntervalSec: Integer;
    Procedure DetailTimerTimer(Sender: TObject);
    Procedure AutoRefreshTimerTimer(Sender: TObject);
    Function GitDirStampChanged: Boolean;
    Procedure UpdateStatus;
    Procedure RefreshRepositoryInfo;
    Procedure RefreshChanges;
    Procedure RefreshFiles;
    Procedure SubmitFileList;
    Procedure SubmitFileHistory(Sender: TObject);
    Procedure SubmitFileContent(Sender: TObject);
    Procedure ConfigureCommitMessageEditor;
    Function CanMutate: Boolean;
    Function CanRewriteLastCommit: Boolean;
    Procedure ActivateChangesTab;
    Procedure ApplyCommitMessage(Const MessageText: String);
    Procedure ApplyIndexResult(Ok: Boolean; Const Payload: String);
    Procedure ApplyDetailsResult(Ok: Boolean; Const Payload: String);
    Procedure ApplyFetchedHistory(Const IndexText, DetailsText: String; DetailsOk: Boolean);
    Procedure StartIndexLoad;
    Procedure StartRemoteOp(Kind: TGitRemoteOpKind);
    Procedure SetJobUiBusy(IsBusy: Boolean; Const StatusCaption: String);
    Procedure GitJobBusyChanged(Sender: TObject; IsBusy: Boolean; Const StatusCaption: String);
    Procedure GitJobFinished(Job: TGitJob);
    Function SubmitGitJob(Job: TGitJob): Boolean;
    Procedure SubmitChangesStatus;
    Procedure ScheduleVisibleDetails;
    Procedure StartDetailLoadIfNeeded;
    Procedure StopIndexLoad;
    Procedure StopDetailLoad;
    Procedure ShowCommitDetails(Index: Integer);
    Procedure SelectRow(Index: Integer; ScrollIntoView: Boolean);
    Procedure MoveSelection(Delta: Integer);
    Function SelectedSha: String;
    Procedure QuietRefreshIfChanged;
    { IGitRepositoryChanged }
    Procedure RepositoryStateChanged(Const RepoPath: String; NewState: TGitRepositoryState);
    Procedure WorkingTreeChanged(Const RepoPath: String);
    Procedure HeadChanged(Const RepoPath: String; Const NewHeadSha: String);
    Procedure RemoteUpdated(Const RepoPath: String; Const RemoteName: String);
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure BindRepository(Const StartPath: String = '');
    Procedure SetRepository(Const ARepoPath: String; ForceReload: Boolean = False);
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
  WorkflowLog, GitConfig, GitRemotesForm, GitSettingsForm, GitIgnoreForm, GitPathUtils,
  DateUtils, Math, LazFileUtils, SpellCheckerConfig;

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
  FHeadPushed := True;
  FHeadPushedKnown := False;
  FAmendHead := False;
  FSelectedIndex := -1;
  FIndexing := False;
  FDetailLoading := False;
  FRemoteOpBusy := False;
  FJobBusy := False;
  FRepoGeneration := 0;
  FIndexGen := 0;
  FDetailGen := 0;
  FInListSelChange := False;
  FStatusGen := 0;
  FStatusJobPending := False;
  FProbePending := False;
  FLastPorcelain := '';
  FLastHeadAge := -1;
  FLastIndexAge := -1;
  FLastProbeAt := 0;
  FProbeIntervalSec := 5;
  FModel := TGitGraphModel.Create;
  FHistory := TManageHistoryGraph.Create(Self);
  FChanges := TManageChangesPane.Create;
  FFiles := TManageFilesPane.Create;
  FFilesNeedReload := True;
  FFiles.OnRequestHistory := @SubmitFileHistory;
  FFiles.OnRequestContent := @SubmitFileContent;
  ApplyConfig;
  WorkflowEventBus.AddListener(Self);
  If Assigned(GitJobs) Then
    GitJobs.OnBusyChanged := @GitJobBusyChanged;
End;

Destructor TManageRepositoryForm.Destroy;
Begin
  Destroying;
  Application.RemoveAsyncCalls(Self);
  If Assigned(WorkflowEventBus) Then WorkflowEventBus.RemoveListener(Self);
  If Assigned(ChangesDiffView) Then ChangesDiffView.OnStatusChanged := Nil;
  If Assigned(FDetailTimer) Then
    FDetailTimer.Enabled := False;
  If Assigned(FAutoRefreshTimer) Then
    FAutoRefreshTimer.Enabled := False;
  If Assigned(GitJobs) Then
    Begin
      If (TMethod(GitJobs.OnBusyChanged).Code = TMethod(@GitJobBusyChanged).Code) And
         (TMethod(GitJobs.OnBusyChanged).Data = Pointer(Self)) Then
        GitJobs.OnBusyChanged := Nil;
      GitJobs.CancelIfHandler(@GitJobFinished);
      GitJobs.DetachFinishedHandler(@GitJobFinished);
    End;
  Screen.Cursor := crDefault;
  Inc(FIndexGen);
  Inc(FDetailGen);
  FRemoteOpBusy := False;
  FIndexing := False;
  FDetailLoading := False;
  FreeAndNil(FFiles);
  FreeAndNil(FChanges);
  FreeAndNil(FHistory);
  FreeAndNil(FModel);
  Inherited Destroy;
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
    If Assigned(FilesSplitter) And Assigned(FilesLeftPanel) Then
      FilesSplitter.ResizeControl := FilesLeftPanel;
    If Assigned(FileCommitSplitter) And Assigned(FileCommitPanel) Then
      FileCommitSplitter.ResizeControl := FileCommitPanel;
    { Themed expander glyphs are often invisible on GTK, and without ShowRoot the
      top-level folders have no hit target. Plus/minus is always drawn. KeepCollapsedNodes
      must stay on, or collapse deletes the children and the folder cannot open again. }
    If Assigned(FileTree) Then
      Begin
        FileTree.Options := [tvoShowButtons, tvoShowLines, tvoShowRoot, tvoKeepCollapsedNodes, tvoReadOnly,
          tvoToolTips, tvoRowSelect, tvoAutoItemHeight, tvoNoDoubleClickExpand];
        FileTree.ExpandSignType := tvestPlusMinus;
        FileTree.HideSelection := False;
      End;

    If Assigned(DiffView) Then
      DiffView.SetViewMode(dvmBrowse);
    If Assigned(ChangesDiffView) Then
      Begin
        ChangesDiffView.SetViewMode(dvmEditorOnly);
        ChangesDiffView.OnStatusChanged := @ChangesDiffStatusChanged;
      End;
    If Assigned(GraphHost) Then
      Begin
        GraphHost.DoubleBuffered := True;
        GraphHost.ParentBackground := False;
      End;
    If Assigned(GraphPaintBox) Then
      GraphPaintBox.ControlStyle := GraphPaintBox.ControlStyle + [csOpaque];
    If Assigned(FHistory) Then
      FHistory.Bind(GraphPaintBox, GraphScrollBar, FModel);
    If Assigned(FChanges) Then
      FChanges.Bind(ChangesList, StagedList, ChangesDiffView, UntrackedCheck, CleanCheck, IgnoredCheck,
        StagedLabel);
    If Assigned(FFiles) Then
      FFiles.Bind(FileTree, FileCommitList, FileRevisionEditor, FilePreviewPanel, FileImagePaintBox, FilePreviewLabel);
    If Assigned(UntrackedCheck) Then
      UntrackedCheck.Checked := False;
    If Assigned(CleanCheck) Then
      CleanCheck.Checked := False;
    If Assigned(IgnoredCheck) Then
      IgnoredCheck.Checked := False;
    If Assigned(ChangesList) Then
      ChangesList.MultiSelect := True;
    If Assigned(StagedList) Then
      StagedList.MultiSelect := True;
    ConfigureCommitMessageEditor;
    WorkflowLogger.Info('ManageRepository', 'Manage Repository window created');
  Except
    On E: Exception Do
      WorkflowLogger.Error('ManageRepository', 'FormCreate: ' + E.Message);
  End;
End;

Procedure TManageRepositoryForm.ConfigureCommitMessageEditor;
Begin
  If Not Assigned(MessageEditor) Then
    Exit;
  MessageEditor.WantTabs := False;
  MessageEditor.WordWrap := True;
  MessageEditor.ParentFont := True;
  MessageEditor.UseSharedConfig := True;
  If Assigned(WorkflowSpellConfig) Then
    WorkflowSpellConfig.EnsurePreloaded;
  If Assigned(MessageLabel) Then
    MessageLabel.Caption := 'Commit message';
  MessageEditor.Rescan;
End;

Procedure TManageRepositoryForm.FormDestroy(Sender: TObject);
Begin
  WorkflowLogger.Info('ManageRepository', 'Manage Repository window destroyed');
End;

Procedure TManageRepositoryForm.FormShow(Sender: TObject);
Begin
  Try
    { Do not rediscover from the IDE project when Open already bound a path. }
    If FRepoPath = '' Then
      BindRepository;
    ApplyConfig;
    If Assigned(MessageEditor) Then
      MessageEditor.Rescan;
    { Remeasure scroll range once the paintbox parent has a handle. }
    FHistory.UpdateScrollRange;
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
      { Tick often to notice .git/HEAD and index; the configured seconds is the
        fallback probe for worktree-only edits that do not touch those files. }
      FProbeIntervalSec := GitManagerConfig.AutoRefreshSeconds;
      If FProbeIntervalSec < 2 Then
        FProbeIntervalSec := 2;
      FAutoRefreshTimer.Interval := 1000;
      FAutoRefreshTimer.Enabled := GitManagerConfig.AutoRefresh And (FRepoPath <> '');
    End;
  { Graph font changes affect row metrics and painted text. }
  FHistory.UpdateScrollRange;
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
    SetRepository(FRepoPath, True)
  Else
    BindRepository;
End;

Procedure TManageRepositoryForm.FormKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
Var
  FocusedControl: TWinControl;
Begin
  FocusedControl := ActiveControl;
  { Graph keys must not steal arrows/Enter from the commit message or Changes lists. }
  If (Key <> VK_F5) And Assigned(FocusedControl) Then
    If (FocusedControl = MessageEditor) Or (FocusedControl = ChangesList) Or
       (FocusedControl = StagedList) Or (FocusedControl Is TCustomEdit) Or
       (FocusedControl Is TCustomSynEdit) Or (FocusedControl Is TCustomListBox) Then
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
        MoveSelection(-(GraphPaintBox.ClientHeight Div FHistory.RowHeight));
        Key := 0;
      End;
    VK_NEXT:
      Begin
        MoveSelection(GraphPaintBox.ClientHeight Div FHistory.RowHeight);
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
      RH := FHistory.RowHeight;
      ViewH := GraphPaintBox.ClientHeight;
      RowTop := Index * RH;
      RowBottom := RowTop + RH;
      If RowTop < FHistory.ScrollOffset Then
        GraphScrollBar.Position := RowTop
      Else If RowBottom > FHistory.ScrollOffset + ViewH Then
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

Procedure TManageRepositoryForm.StopIndexLoad;
Begin
  Inc(FIndexGen);
  FIndexing := False;
End;

Procedure TManageRepositoryForm.StopDetailLoad;
Begin
  Inc(FDetailGen);
  FDetailLoading := False;
End;

Procedure TManageRepositoryForm.SetJobUiBusy(IsBusy: Boolean; Const StatusCaption: String);
Begin
  FJobBusy := IsBusy;
  If IsBusy Then
    Begin
      Screen.Cursor := crHourGlass;
      If Assigned(StatusFooter) And (StatusCaption <> '') Then
        StatusFooter.SetRightText(StatusCaption);
    End
  Else
    Begin
      Screen.Cursor := crDefault;
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
Var
  QuietJob: Boolean;
Begin
  Result := False;
  If Not Assigned(Job) Then
    Exit;
  QuietJob := Job.Quiet;
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
  Job.RepoGeneration := FRepoGeneration;
  Job.OnFinished := @GitJobFinished;
  Result := GitJobs.Submit(Job);
  { Submit frees Job on failure; do not read it afterwards. }
  If Result Then
    Begin
      If Not QuietJob Then
        FJobBusy := True;
    End
  Else If Not QuietJob Then
    MessageDlg('Could not queue Git operation (queue full or runner stopped).', mtWarning, [mbOK], 0);
End;

Function StatusDigestIsClean(Const Digest: String): Boolean; Forward;

Procedure TManageRepositoryForm.GitJobFinished(Job: TGitJob);
Var
  Msg: String;
  Followup: TGitJob;
  PushQueued: Boolean;
Begin
  If (csDestroying in ComponentState) Or Not Assigned(Job) Then
    Exit;

  { Follow-up intent belongs to the completed job, even if this window now
    displays another repository. Submit directly to preserve its context. }
  PushQueued := False;
  Followup := Job.CreatePushFollowup;
  If Assigned(Followup) Then
    Begin
      If Assigned(GitJobs) Then
        PushQueued := GitJobs.Submit(Followup)
      Else
        Followup.Free;
      If PushQueued And Job.MatchesRepository(FRepoPath, FRepoGeneration) Then
        FRemoteOpBusy := True;
      If Not PushQueued Then
        WorkflowLogger.Warning('ManageRepository', 'Could not queue push for ' + Job.RepoPath);
    End;
  If Not Job.MatchesRepository(FRepoPath, FRepoGeneration) Then
    Exit;

  Case Job.Kind Of
    gjkFetch, gjkPull, gjkPush:
      Begin
        { Busy-notify often runs before this handler while FRemoteOpBusy is still True,
          so re-enable must happen here after clearing the remote-op flag. }
        FRemoteOpBusy := False;
        FJobBusy := False;
        Screen.Cursor := crDefault;
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
            If Not Job.MatchesRepository(FRepoPath, FRepoGeneration) Then
              Exit;
            If Job.IndexOk Then
              Begin
                ApplyFetchedHistory(Job.IndexText, Job.DetailsText, Job.DetailsOk);
                RefreshRepositoryInfo;
                If Assigned(Pages) And (Pages.ActivePage = ChangesTab) Then
                  RefreshChanges;
              End
            Else
              ManualRefresh;
            If Assigned(StatusFooter) Then
              If Job.Kind = gjkPush Then
                StatusFooter.SetRightText('Push complete')
              Else If Job.Kind = gjkPull Then
                StatusFooter.SetRightText('Pull complete')
              Else
                StatusFooter.SetRightText('Fetch complete');
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
            If Job.MatchesRepository(FRepoPath, FRepoGeneration) Then
              RefreshChanges;
            Exit;
          End;
        WorkflowLogger.Info('ManageRepository', 'Created commit ' + Job.ResultSha);
        FAmendHead := False;
        If Assigned(MessageEditor) Then
          MessageEditor.Clear;
        MessageDlg('Committed ' + Copy(Job.ResultSha, 1, 7) + '.', mtInformation, [mbOK], 0);
        If Not Job.MatchesRepository(FRepoPath, FRepoGeneration) Then
          Exit;
        If Not PushQueued Then
          ManualRefresh;
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
            MessageDlg('Created branch "' + Job.BranchName + '" at ' + Copy(Job.RefName, 1, 7),
              mtInformation, [mbOK], 0);
            If Job.MatchesRepository(FRepoPath, FRepoGeneration) Then
              ManualRefresh;
          End
        Else
          MessageDlg('Create branch failed: ' + Job.ErrorText, mtError, [mbOK], 0);
      End;
    gjkStagePaths, gjkUnstagePaths, gjkRevertPaths, gjkAppendIgnore:
      Begin
        If Job.Cancelled Then
          Exit;
        If Not Job.Ok Then
          MessageDlg(Job.Caption + ' failed: ' + Job.ErrorText, mtError, [mbOK], 0)
        Else If Assigned(Job.Paths) Then
          Case Job.Kind Of
            gjkRevertPaths:
              WorkflowLogger.Info('ManageRepository', Format('Reverted %d path(s)', [Job.Paths.Count]));
            gjkAppendIgnore:
              WorkflowLogger.Info('ManageRepository', Format('Ignored %d path(s)', [Job.Paths.Count]));
          Else
            { stage / unstage already logged by GitService when events publish }
          End;
        If Job.MatchesRepository(FRepoPath, FRepoGeneration) Then
          RefreshChanges;
      End;
    gjkListStatus:
      Begin
        FStatusJobPending := False;
        If Job.Cancelled Then
          Exit;
        If (Job.Tag <> FStatusGen) Or (CompareFilenames(Job.RepoPath, FRepoPath) <> 0) Then
          Begin
            If (FRepoPath <> '') And DirectoryExists(FRepoPath) Then
              SubmitChangesStatus;
            Exit;
          End;
        If Job.Ok Then
          FChanges.ApplyFromStatus(Job.StatusEntries, Job.TrackedFiles)
        Else
          Begin
            If Assigned(ChangesList) Then
              Begin
                ChangesList.Items.Clear;
                ChangesList.Items.Add('(status failed)');
              End;
            WorkflowLogger.Warning('ManageRepository', 'ListStatus: ' + Job.ErrorText);
          End;
      End;
    gjkRepositoryFiles:
      Begin
        If Job.Cancelled Or Not Assigned(FFiles) Then
          Exit;
        FFiles.ApplyFileList(Job.Tag, Job.TrackedFiles, Job.Ok);
        If Not Job.Ok Then
          WorkflowLogger.Warning('ManageRepository', 'List files: ' + Job.ErrorText);
      End;
    gjkPathCommits:
      Begin
        If Job.Cancelled Or Not Assigned(FFiles) Then
          Exit;
        FFiles.ApplyHistory(Job.Tag, Job.PreviewPath, Job.IndexText, Job.Ok);
        If Not Job.Ok Then
          WorkflowLogger.Warning('ManageRepository', 'File history: ' + Job.ErrorText);
      End;
    gjkCommitFile:
      Begin
        If Job.Cancelled Or Not Assigned(FFiles) Then
          Exit;
        If Job.PreviewReadBytes Then
          FFiles.ApplyImage(Job.Tag, Job.PreviewPath, Job.PreviewSha, Job.PreviewBytes, Job.Ok, Job.ErrorText)
        Else
          FFiles.ApplyContent(Job.Tag, Job.PreviewPath, Job.PreviewSha, Job.PreviewText, Job.PreviewBinary, Job.Ok);
        If Not Job.Ok Then
          WorkflowLogger.Warning('ManageRepository', 'File revision: ' + Job.ErrorText);
      End;
    gjkSuggestMessage:
      Begin
        If Job.Cancelled Then
          Exit;
        If Not Job.Ok Then
          Begin
            MessageDlg(Job.ErrorText, mtWarning, [mbOK], 0);
            Exit;
          End;
        If Assigned(MessageEditor) Then
          Begin
            MessageEditor.Text := Job.CommitMessage;
          End;
        WorkflowLogger.Info('ManageRepository', 'Suggested commit message (' +
          IntToStr(Length(Job.CommitMessage)) + ' chars)');
      End;
    gjkRepoProbe:
      Begin
        FProbePending := False;
        If Job.Cancelled Or Not Job.Ok Then Exit;
        FCachedGitDir := Job.GitDir;
        FHeadPushed := Job.HeadPushed;
        FHeadPushedKnown := Job.HeadPushedKnown;
        FClean := StatusDigestIsClean(Job.ProbeDigest);
        If (Job.ResultSha <> FHeadSha) Or (Job.ProbeBranch <> FBranch) Or
          (Job.RefsDigest <> FRefsDigest) Then
          Begin
            FRefsDigest := Job.RefsDigest;
            FHeadSha := Job.ResultSha; FBranch := Job.ProbeBranch;
            FLastPorcelain := Job.ProbeDigest;
            ManualRefresh;
          End
        Else
          Begin
            If Job.ProbeDigest <> FLastPorcelain Then
              Begin
                FLastPorcelain := Job.ProbeDigest;
                RefreshChanges;
              End
            Else If Assigned(Pages) And (Pages.ActivePage = ChangesTab) Then
              FChanges.RefreshSelectedDiff;
            UpdateStatus;
          End;
      End;
    gjkIndexHistory:
      Begin
        If (Job.Tag <> FIndexGen) Or (CompareFilenames(Job.RepoPath, FRepoPath) <> 0) Then
          Exit;
        If Job.Cancelled Then
          Begin
            FIndexing := False;
            Exit;
          End;
        ApplyIndexResult(Job.Ok, Job.IndexText);
      End;
    gjkFetchDetails:
      Begin
        If (Job.Tag <> FDetailGen) Or (CompareFilenames(Job.RepoPath, FRepoPath) <> 0) Then
          Exit;
        If Job.Cancelled Then
          Begin
            FDetailLoading := False;
            Exit;
          End;
        ApplyDetailsResult(Job.Ok, Job.DetailsText);
      End;
    gjkPrepareAmend:
      Begin
        If Job.Cancelled Then
          Exit;
        If Not Job.Ok Then
          Begin
            MessageDlg('Amend failed: ' + Job.ErrorText, mtError, [mbOK], 0);
            Exit;
          End;
        FAmendHead := Job.AmendCommit;
        ApplyCommitMessage(Job.CommitMessage);
        ActivateChangesTab;
        WorkflowLogger.Info('ManageRepository', 'Last commit opened for amend');
        ManualRefresh;
        If Assigned(StatusFooter) Then
          StatusFooter.SetRightText('Editing last commit');
        If Assigned(MessageEditor) And MessageEditor.CanFocus Then
          MessageEditor.SetFocus;
      End;
    gjkRemoveLastCommit:
      Begin
        If Job.Cancelled Then
          Exit;
        If Not Job.Ok Then
          Begin
            MessageDlg('Remove failed: ' + Job.ErrorText, mtError, [mbOK], 0);
            Exit;
          End;
        FAmendHead := False;
        If Assigned(MessageEditor) Then
          MessageEditor.Clear;
        If Assigned(UntrackedCheck) Then
          UntrackedCheck.Checked := True;
        ActivateChangesTab;
        WorkflowLogger.Info('ManageRepository', 'Removed last commit');
        ManualRefresh;
        If Assigned(StatusFooter) Then
          StatusFooter.SetRightText('Last commit removed');
        If Assigned(ChangesList) And ChangesList.CanFocus Then
          ChangesList.SetFocus;
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
  If (FRepoPath = '') Or FRemoteOpBusy Then
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
  StopDetailLoad;
  StopIndexLoad;
  FRemoteOpBusy := True;
  Job := TGitJob.Create(JobKind);
  Job.RepoPath := FRepoPath;
  If Not SubmitGitJob(Job) Then
    FRemoteOpBusy := False;
End;

Procedure TManageRepositoryForm.ApplyFetchedHistory(Const IndexText, DetailsText: String;
  DetailsOk: Boolean);
Var
  Parsed: Integer;
Begin
  If (csDestroying in ComponentState) Or Not Assigned(FModel) Then
    Exit;
  FIndexing := False;
  Parsed := FModel.ParseRevListParents(IndexText);
  If DetailsOk And (DetailsText <> '') Then
    FModel.ApplyDetailsText(DetailsText);
  FSelectedIndex := -1;
  If Parsed > 0 Then
    FSelectedIndex := 0;
  FHistory.UpdateScrollRange;
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
  UpdateStatus;
End;

Procedure TManageRepositoryForm.StartIndexLoad;
Var
  Job: TGitJob;
Begin
  If FRepoPath = '' Then
    Exit;
  StopDetailLoad;
  StopIndexLoad;
  FIndexing := True;
  If Assigned(StatusFooter) Then
    StatusFooter.SetRightText('Indexing…');
  Job := TGitJob.Create(gjkIndexHistory);
  Job.RepoPath := FRepoPath;
  Job.Quiet := True;
  Job.Tag := FIndexGen;
  If Not SubmitGitJob(Job) Then
    FIndexing := False;
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

  FHistory.UpdateScrollRange;
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
  { Do not reload the commit SynEdit here. Scrolling fetches details for newly
    visible rows; rewriting the selected diff on every batch is the flicker. }
  If Assigned(GraphPaintBox) Then
    GraphPaintBox.Invalidate;
  { More rows may still be missing after scrolling. }
  ScheduleVisibleDetails;
End;

Procedure TManageRepositoryForm.ScheduleVisibleDetails;
Begin
  If (csDestroying In ComponentState) Or Not Assigned(FHistory) Or
    Not Assigned(FModel) Then Exit;
  If FIndexing Or (FRepoPath = '') Or (FModel.Count = 0) Then
    Exit;
  FDetailTimer.Enabled := False;
  FDetailTimer.Enabled := True;
End;

Procedure TManageRepositoryForm.DetailTimerTimer(Sender: TObject);
Begin
  If csDestroying In ComponentState Then Exit;
  Try
    FDetailTimer.Enabled := False;
    StartDetailLoadIfNeeded;
  Except
    On E: Exception Do
      Begin
        FDetailTimer.Enabled := False;
        WorkflowLogger.Error('PluginBoundary', 'TManageRepositoryForm.DetailTimerTimer: ' + E.Message);
      End;
  End;
End;

Procedure TManageRepositoryForm.StartDetailLoadIfNeeded;
Var
  First, Last: Integer;
  Shas: TStringList;
  Missing: Integer;
  Job: TGitJob;
Begin
  If FDetailLoading Or FIndexing Or (FRepoPath = '') Then
    Exit;

  FHistory.GetVisibleRange(First, Last);
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
  Job := TGitJob.Create(gjkFetchDetails);
  Job.RepoPath := FRepoPath;
  Job.Quiet := True;
  Job.Tag := FDetailGen;
  Job.TakePaths(Shas);
  If Not SubmitGitJob(Job) Then
    FDetailLoading := False;
End;

Procedure TManageRepositoryForm.GraphHostResize(Sender: TObject);
Begin
  If (csDestroying In ComponentState) Or Not Assigned(FHistory) Or
    Not Assigned(FModel) Then Exit;
  FHistory.UpdateScrollRange;
  ScheduleVisibleDetails;
  GraphPaintBox.Invalidate;
End;

Procedure TManageRepositoryForm.ScrollBarChange(Sender: TObject);
Begin
  If (csDestroying In ComponentState) Or Not Assigned(FHistory) Or
    Not Assigned(FModel) Then Exit;
  ScheduleVisibleDetails;
  GraphPaintBox.Invalidate;
End;

Procedure TManageRepositoryForm.PaintBoxMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; Var Handled: Boolean);
Var
  NewPos, MaxPos, ViewH: Integer;
Begin
  If (csDestroying In ComponentState) Or Not Assigned(FHistory) Or
    Not Assigned(FModel) Then Exit;
  ViewH := GraphPaintBox.ClientHeight;
  MaxPos := FHistory.ContentHeight - ViewH;
  If MaxPos < 0 Then
    MaxPos := 0;
  NewPos := GraphScrollBar.Position - (WheelDelta Div 120) * FHistory.RowHeight * 3;
  If NewPos < 0 Then
    NewPos := 0;
  If NewPos > MaxPos Then
    NewPos := MaxPos;
  If NewPos <> GraphScrollBar.Position Then
    GraphScrollBar.Position := NewPos;
  Handled := True;
End;

Procedure TManageRepositoryForm.PaintBoxPaint(Sender: TObject);
Begin
  If (csDestroying In ComponentState) Or Not Assigned(FHistory) Or
    Not Assigned(FModel) Then Exit;
  FHistory.Indexing := FIndexing;
  FHistory.RepoPath := FRepoPath;
  FHistory.SelectedIndex := FSelectedIndex;
  FHistory.Paint;
End;

Procedure TManageRepositoryForm.PaintBoxMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
Var
  Row: Integer;
Begin
  If (csDestroying In ComponentState) Or Not Assigned(FHistory) Or
    Not Assigned(FModel) Then Exit;
  Row := FHistory.RowAtY(Y);
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
  If Pages.ActivePage = ChangesTab Then
    Begin
      RefreshChanges;
      { Overview paints on a child window that only sizes after the page is shown. }
      If Assigned(ChangesDiffView) Then
        ChangesDiffView.RefreshOverviewGutter;
    End
  Else If Pages.ActivePage = HistoryTab Then
    Begin
      If Assigned(DiffView) Then
        DiffView.RefreshOverviewGutter;
    End
  Else If Pages.ActivePage = FilesTabSheet Then
    Begin
      If Assigned(FileRevisionEditor) Then
        ApplySynEditIDEFont(FileRevisionEditor, True);
      If Assigned(FileImagePaintBox) And FileImagePaintBox.Visible Then
        FileImagePaintBox.Invalidate;
      If FFilesNeedReload Then
        RefreshFiles;
    End;
End;

Procedure TManageRepositoryForm.RefreshChanges;
Begin
  If Assigned(FChanges) Then
    FChanges.RepoPath := FRepoPath;
  If Not Assigned(ChangesList) Or Not Assigned(StagedList) Then
    Exit;
  If (FRepoPath = '') Or Not DirectoryExists(FRepoPath) Then
    Begin
      If Assigned(FChanges) Then
        FChanges.ClearForNoRepo;
      Exit;
    End;
  Inc(FStatusGen);
  If FStatusJobPending Then
    Exit;
  SubmitChangesStatus;
End;

Procedure TManageRepositoryForm.RefreshFiles;
Begin
  If Assigned(FFiles) Then
    FFiles.RepoPath := FRepoPath;
  If Not Assigned(FileTree) Then
    Exit;
  If (FRepoPath = '') Or Not DirectoryExists(FRepoPath) Then
    Begin
      FFilesNeedReload := False;
      If Assigned(FFiles) Then
        FFiles.ClearForNoRepo;
      If Assigned(FileTree) And (FileTree.Items.Count = 0) Then
        FileTree.Items.Add(Nil, '(no repository)');
      Exit;
    End;
  FFilesNeedReload := False;
  SubmitFileList;
End;

Procedure TManageRepositoryForm.SubmitFileList;
Var
  Job: TGitJob;
  Token: Integer;
Begin
  If Not Assigned(FFiles) Or (FRepoPath = '') Then
    Exit;
  Token := FFiles.BeginFileList;
  Job := TGitJob.Create(gjkRepositoryFiles);
  Job.RepoPath := FRepoPath;
  Job.Quiet := True;
  Job.Tag := Token;
  If Not SubmitGitJob(Job) Then
    FFiles.ApplyFileList(Token, Nil, False);
End;

Procedure TManageRepositoryForm.SubmitFileHistory(Sender: TObject);
Var
  Job: TGitJob;
  Token: Integer;
  Path: String;
Begin
  If Not Assigned(FFiles) Or (FFiles.SelectedPath = '') Or (FRepoPath = '') Then
    Exit;
  Path := FFiles.SelectedPath;
  Token := FFiles.BeginHistory;
  Job := TGitJob.Create(gjkPathCommits);
  Job.RepoPath := FRepoPath;
  Job.Quiet := True;
  Job.PreviewPath := Path;
  Job.Tag := Token;
  If Not SubmitGitJob(Job) Then
    FFiles.ApplyHistory(Token, Path, '', False);
End;

Procedure TManageRepositoryForm.SubmitFileContent(Sender: TObject);
Var
  Job: TGitJob;
  Token: Integer;
  Path, Sha: String;
  ReadBytes: Boolean;
Begin
  If Not Assigned(FFiles) Or (FFiles.SelectedSha = '') Or (FFiles.ContentPath = '') Then
    Exit;
  Path := FFiles.ContentPath;
  Sha := FFiles.SelectedSha;
  ReadBytes := FFiles.ContentIsImage;
  Token := FFiles.BeginContent;
  Job := TGitJob.Create(gjkCommitFile);
  Job.RepoPath := FRepoPath;
  Job.Quiet := True;
  Job.PreviewPath := Path;
  Job.PreviewSha := Sha;
  Job.PreviewReadBytes := ReadBytes;
  Job.Tag := Token;
  If Not SubmitGitJob(Job) Then
    Begin
      If ReadBytes Then
        FFiles.ApplyImage(Token, Path, Sha, Nil, False, '')
      Else
        FFiles.ApplyContent(Token, Path, Sha, '', False, False);
    End;
End;

Procedure TManageRepositoryForm.FileImagePaintBoxPaint(Sender: TObject);
Begin
  If Assigned(FFiles) Then
    FFiles.PaintPreview;
End;

Procedure TManageRepositoryForm.FileTreeChange(Sender: TObject; Node: TTreeNode);
Begin
  If Assigned(FFiles) Then
    FFiles.TreeSelectionChanged;
End;

Procedure TManageRepositoryForm.FileTreeMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
Var
  Node: TTreeNode;
Begin
  If (Button <> mbLeft) Or (ssDouble in Shift) Or Not Assigned(FileTree) Then
    Exit;
  Node := FileTree.GetNodeAt(X, Y);
  If Not Assigned(Node) Or Not Node.HasChildren Then
    Exit;
  { The tree toggles the expander itself. A click on the folder name must collapse too. }
  If (X >= Node.DisplayExpandSignLeft) And (X < Node.DisplayExpandSignRight) Then
    Exit;
  Node.Expanded := Not Node.Expanded;
End;

Procedure TManageRepositoryForm.FileCommitListSelectionChange(Sender: TObject; User: Boolean);
Begin
  If Assigned(FFiles) Then
    FFiles.CommitSelectionChanged;
End;

Procedure TManageRepositoryForm.SubmitChangesStatus;
Var
  Job: TGitJob;
Begin
  Job := TGitJob.Create(gjkListStatus);
  Job.RepoPath := FRepoPath;
  Job.Caption := 'Refreshing changes…';
  Job.Tag := FStatusGen;
  Job.IncludeClean := Assigned(CleanCheck) And CleanCheck.Checked;
  Job.IncludeUntracked := Assigned(UntrackedCheck) And UntrackedCheck.Checked;
  Job.IncludeIgnored := Assigned(IgnoredCheck) And IgnoredCheck.Checked;
  FStatusJobPending := True;
  If Not SubmitGitJob(Job) Then
    FStatusJobPending := False;
End;

Function TManageRepositoryForm.CanMutate: Boolean;
Begin
  Result := (FRepoPath <> '') And (Not FJobBusy) And (Not FRemoteOpBusy);
End;

Function TManageRepositoryForm.CanRewriteLastCommit: Boolean;
Begin
  Result := CanMutate And FHeadPushedKnown And (Not FHeadPushed) And (FHeadSha <> '') And
    SameText(SelectedSha, FHeadSha);
End;

Procedure TManageRepositoryForm.ActivateChangesTab;
Begin
  If Assigned(Pages) And Assigned(ChangesTab) Then
    Pages.ActivePage := ChangesTab;
  RefreshChanges;
End;

Procedure TManageRepositoryForm.ApplyCommitMessage(Const MessageText: String);
Begin
  If Assigned(MessageEditor) Then
    MessageEditor.Text := AdjustLineBreaks(TrimRight(MessageText));
End;

Procedure TManageRepositoryForm.RemoteActionUpdate(Sender: TObject);
Begin
  (Sender As TAction).Enabled := CanMutate;
End;

Procedure TManageRepositoryForm.StageAllActionUpdate(Sender: TObject);
Var
  CurrentAction: TAction;
Begin
  CurrentAction := Sender As TAction;
  If FChanges.HasStaged And (Not FChanges.HasUnstaged) Then
    Begin
      CurrentAction.Caption := 'Unstage All';
      CurrentAction.Enabled := CanMutate;
    End
  Else
    Begin
      CurrentAction.Caption := 'Stage All';
      CurrentAction.Enabled := CanMutate And FChanges.HasUnstaged;
    End;
End;

Procedure TManageRepositoryForm.StageActionUpdate(Sender: TObject);
Var
  CurrentAction: TAction;
  UnstageMode: Boolean;
Begin
  CurrentAction := Sender As TAction;
  UnstageMode := FChanges.HasStaged And ((Not FChanges.HasUnstaged) Or FChanges.ListHasSelection(StagedList));
  If UnstageMode Then
    Begin
      CurrentAction.Caption := 'Unstage';
      CurrentAction.Enabled := CanMutate And FChanges.ListHasSelection(StagedList);
    End
  Else
    Begin
      CurrentAction.Caption := 'Stage';
      CurrentAction.Enabled := CanMutate And FChanges.ListHasSelection(ChangesList) And FChanges.HasUnstaged;
    End;
End;

Procedure TManageRepositoryForm.StageSelectionActionUpdate(Sender: TObject);
Var
  CurrentAction: TAction;
Begin
  CurrentAction := Sender As TAction;
  If Assigned(ChangesDiffView) And ChangesDiffView.StagedSide Then
    CurrentAction.Caption := 'Unstage Selection'
  Else
    CurrentAction.Caption := 'Stage Selection';
  CurrentAction.Enabled := CanMutate And Assigned(ChangesDiffView) And ChangesDiffView.HasActiveSelection;
End;

Procedure TManageRepositoryForm.PathActionUpdate(Sender: TObject);
Begin
  (Sender As TAction).Enabled := CanMutate And
    (FChanges.ListHasSelection(ChangesList) Or FChanges.ListHasSelection(StagedList));
End;

Procedure TManageRepositoryForm.IgnoredFilesActionUpdate(Sender: TObject);
Begin
  (Sender As TAction).Enabled := FRepoPath <> '';
End;

Procedure TManageRepositoryForm.SuggestMessageActionUpdate(Sender: TObject);
Var
  CurrentAction: TAction;
  AssistantAvailable: Boolean;
Begin
  CurrentAction := Sender As TAction;
  AssistantAvailable := SuggestCommitMessageAvailable;
  CurrentAction.Enabled := SuggestCommitActionEnabled(CanMutate, FChanges.HasStaged);
  If Not AssistantAvailable Then
    CurrentAction.Hint :=
      'Install LazAssistantTools to suggest commit messages from the Project Assistant.'
  Else
    CurrentAction.Hint := 'Suggest a commit message from the staged diff';
End;

Procedure TManageRepositoryForm.CommitActionUpdate(Sender: TObject);
Begin
  (Sender As TAction).Enabled := CanMutate And Assigned(MessageEditor) And
    (Trim(MessageEditor.Text) <> '') And (FChanges.HasStaged Or FAmendHead);
End;

Procedure TManageRepositoryForm.RewriteHeadActionUpdate(Sender: TObject);
Begin
  (Sender As TAction).Enabled := CanRewriteLastCommit;
End;

Procedure TManageRepositoryForm.HistoryViewActionUpdate(Sender: TObject);
Begin
  (Sender As TAction).Enabled := SelectedSha <> '';
End;

Procedure TManageRepositoryForm.HistoryMutateActionUpdate(Sender: TObject);
Begin
  (Sender As TAction).Enabled := CanMutate And (SelectedSha <> '');
End;

Procedure TManageRepositoryForm.ChangesListSelectionChange(Sender: TObject; User: Boolean);
Begin
  If (csDestroying In ComponentState) Or Not Assigned(FChanges) Then Exit;
  If FInListSelChange Then
    Exit;
  FInListSelChange := True;
  Try
    { Keep multi-select on this list; only clear the other list's selection. }
    If Assigned(StagedList) And FChanges.ListHasSelection(StagedList) Then
      StagedList.ClearSelection;
    FChanges.ShowSelectedDiff(False);
  Finally
    FInListSelChange := False;
  End;
End;

Procedure TManageRepositoryForm.ChangesListDblClick(Sender: TObject);
Begin
  StageActionExecute(Sender);
End;

Procedure TManageRepositoryForm.StagedListSelectionChange(Sender: TObject; User: Boolean);
Begin
  If (csDestroying In ComponentState) Or Not Assigned(FChanges) Then Exit;
  If FInListSelChange Then
    Exit;
  FInListSelChange := True;
  Try
    If Assigned(ChangesList) And FChanges.ListHasSelection(ChangesList) Then
      ChangesList.ClearSelection;
    FChanges.ShowSelectedDiff(True);
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
  RefreshChanges;
End;

Procedure TManageRepositoryForm.IgnoredFilesActionExecute(Sender: TObject);
Begin
  If FRepoPath = '' Then
    Begin
      MessageDlg('No repository is bound to this window.', mtInformation, [mbOK], 0);
      Exit;
    End;
  If ShowGitIgnoreForm(FRepoPath) Then
    RefreshChanges;
End;

Procedure TManageRepositoryForm.RevertActionExecute(Sender: TObject);
Var
  Paths: TStringList;
  Job: TGitJob;
Begin
  If (FRepoPath = '') Or FJobBusy Then
    Exit;
  Paths := FChanges.CollectActiveSelected;
  If Paths.Count = 0 Then
    Begin
      Paths.Free;
      MessageDlg('Select one or more files to revert.', mtInformation, [mbOK], 0);
      Exit;
    End;
  If Not ConfirmGitPathAction('Revert files',
    'Restore from the last commit (discard local changes for)', Paths) Then
    Begin
      Paths.Free;
      Exit;
    End;
  Job := TGitJob.Create(gjkRevertPaths);
  Job.RepoPath := FRepoPath;
  Job.TakePaths(Paths);
  SubmitGitJob(Job);
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
  Paths := FChanges.CollectActiveSelected;
  Try
    If Paths.Count = 0 Then
      Begin
        MessageDlg('Select one or more files to delete.', mtInformation, [mbOK], 0);
        Exit;
      End;
    If Not ConfirmGitPathAction('Delete files',
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
    RefreshChanges;
  Finally
    Paths.Free;
  End;
End;

Procedure TManageRepositoryForm.IgnoreActionExecute(Sender: TObject);
Var
  Paths: TStringList;
  Job: TGitJob;
Begin
  If (FRepoPath = '') Or FJobBusy Then
    Exit;
  Paths := FChanges.CollectActiveSelected;
  If Paths.Count = 0 Then
    Begin
      Paths.Free;
      MessageDlg('Select one or more files to ignore.', mtInformation, [mbOK], 0);
      Exit;
    End;
  If Not ConfirmGitPathAction('Ignore files',
    'Add to .gitignore', Paths) Then
    Begin
      Paths.Free;
      Exit;
    End;
  Job := TGitJob.Create(gjkAppendIgnore);
  Job.RepoPath := FRepoPath;
  Job.TakePaths(Paths);
  SubmitGitJob(Job);
End;

Procedure TManageRepositoryForm.StageActionExecute(Sender: TObject);
Var
  Paths: TStringList;
  ChangesEmpty, UnstageMode: Boolean;
  Job: TGitJob;
Begin
  If (FRepoPath = '') Or FJobBusy Then
    Exit;
  ChangesEmpty := (Not Assigned(FChanges.ChangesPaths)) Or (FChanges.ChangesPaths.Count = 0);
  UnstageMode := Assigned(FChanges.StagedPaths) And (FChanges.StagedPaths.Count > 0) And
    (ChangesEmpty Or FChanges.ListHasSelection(StagedList));

  If UnstageMode Then
    Begin
      Paths := FChanges.CollectSelected(StagedList, FChanges.StagedPaths);
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
      Paths := FChanges.CollectSelected(ChangesList, FChanges.ChangesPaths);
      If Paths.Count = 0 Then
        Begin
          Paths.Free;
          MessageDlg('Select one or more paths in the Changes list to stage.', mtInformation, [mbOK], 0);
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
  ChangesEmpty, StagedEmpty: Boolean;
  Job: TGitJob;
Begin
  If (FRepoPath = '') Or FJobBusy Then
    Exit;
  ChangesEmpty := (Not Assigned(FChanges.ChangesPaths)) Or (FChanges.ChangesPaths.Count = 0);
  StagedEmpty := (Not Assigned(FChanges.StagedPaths)) Or (FChanges.StagedPaths.Count = 0);
  If (Not StagedEmpty) And ChangesEmpty Then
    Begin
      Job := TGitJob.Create(gjkUnstagePaths);
      Job.RepoPath := FRepoPath;
      Job.CopyPathsFrom(FChanges.StagedPaths);
      SubmitGitJob(Job);
    End
  Else
    Begin
      If ChangesEmpty Then
        Exit;
      Job := TGitJob.Create(gjkStagePaths);
      Job.RepoPath := FRepoPath;
      Job.CopyPathsFrom(FChanges.ChangesPaths);
      SubmitGitJob(Job);
    End;
End;

Procedure TManageRepositoryForm.StageSelectionActionExecute(Sender: TObject);
Begin
  If Not Assigned(ChangesDiffView) Then
    Exit;
  If Not ChangesDiffView.HasActiveSelection Then
    Begin
      MessageDlg('Select lines in the diff preview first.', mtInformation, [mbOK], 0);
      Exit;
    End;
  If ChangesDiffView.StagedSide Then
    ChangesDiffView.UnstageSelection
  Else
    ChangesDiffView.StageSelection;
End;

Procedure TManageRepositoryForm.SuggestMessageActionExecute(Sender: TObject);
Var
  Job: TGitJob;
Begin
  If (FRepoPath = '') Or FJobBusy Then
    Exit;
  If Not SuggestCommitMessageAvailable Then
    Exit;
  If FChanges.StagedPaths.Count = 0 Then
    Begin
      MessageDlg('Stage at least one change before suggesting a commit message.',
        mtInformation, [mbOK], 0);
      Exit;
    End;
  Job := TGitJob.Create(gjkSuggestMessage);
  Job.RepoPath := FRepoPath;
  SubmitGitJob(Job);
End;

Procedure TManageRepositoryForm.ChangesDiffStatusChanged(Sender: TObject);
Begin
  If (csDestroying In ComponentState) Or Not Assigned(FChanges) Then Exit;
  RefreshChanges;
End;

Procedure TManageRepositoryForm.CommitActionExecute(Sender: TObject);
Var
  Msg: String;
  Job: TGitJob;
Begin
  If FRepoPath = '' Then
    Exit;
  Msg := '';
  If Assigned(MessageEditor) Then
    Msg := Trim(MessageEditor.Text);
  If Msg = '' Then
    Begin
      MessageDlg('Enter a commit message.', mtWarning, [mbOK], 0);
      Exit;
    End;
  If (FChanges.StagedPaths.Count = 0) And Not FAmendHead Then
    Begin
      MessageDlg('Stage at least one change before committing.', mtWarning, [mbOK], 0);
      Exit;
    End;
  If FJobBusy Then
    Exit;

  Job := TGitJob.Create(gjkCommit);
  Job.PushAfterCommit := Assigned(PushCheckBox) And PushCheckBox.Checked;
  Job.RepoPath := FRepoPath;
  Job.CommitMessage := Msg;
  Job.AmendCommit := FAmendHead;
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

Procedure TManageRepositoryForm.AmendActionExecute(Sender: TObject);
Var
  Job: TGitJob;
Begin
  If Not CanRewriteLastCommit Then
    Exit;
  Job := TGitJob.Create(gjkPrepareAmend);
  Job.RepoPath := FRepoPath;
  SubmitGitJob(Job);
End;

Procedure TManageRepositoryForm.RemoveActionExecute(Sender: TObject);
Var
  Job: TGitJob;
Begin
  If Not CanRewriteLastCommit Then
    Exit;
  If MessageDlg('Remove the last commit from the history?' + LineEnding + LineEnding +
    'The commit is deleted. Its changes return to the Changes list.',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes Then
    Exit;
  Job := TGitJob.Create(gjkRemoveLastCommit);
  Job.RepoPath := FRepoPath;
  SubmitGitJob(Job);
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
  Sha, Porcelain: String;
  Job: TGitJob;
  Clean: Boolean;
Begin
  Sha := SelectedSha;
  If (Sha = '') Or (FRepoPath = '') Or FJobBusy Then
    Exit;
  Clean := True;
  If Assigned(GitClient) Then
    Begin
      GitClient.RepoPath := FRepoPath;
      GitClient.GetStatus(Clean, Porcelain);
    End;
  If Clean Then
    Begin
      If MessageDlg('Check out commit ' + Copy(Sha, 1, 7) + '?' + LineEnding +
        'This may detach HEAD.', mtConfirmation, [mbYes, mbNo], 0) <> mrYes Then
        Exit;
    End
  Else If MessageDlg('The working tree has uncommitted changes.' + LineEnding + LineEnding +
    'Check out ' + Copy(Sha, 1, 7) + ' anyway? This may detach HEAD, and Git may refuse or you may lose work.',
    mtWarning, [mbYes, mbNo], 0) <> mrYes Then
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
  Job.BranchName := BranchName;
  Job.RefName := Sha;
  SubmitGitJob(Job);
End;

Function TManageRepositoryForm.GitDirStampChanged: Boolean;
Var
  GitDir: String;
  HeadAge, IndexAge: LongInt;
Begin
  Result := False;
  If FCachedGitDir = '' Then
    Exit;
  GitDir := IncludeTrailingPathDelimiter(FCachedGitDir);
  HeadAge := FileAge(GitDir + 'HEAD');
  IndexAge := FileAge(GitDir + 'index');
  If (HeadAge <> FLastHeadAge) Or (IndexAge <> FLastIndexAge) Then
    Begin
      FLastHeadAge := HeadAge;
      FLastIndexAge := IndexAge;
      Result := True;
    End;
End;

Procedure TManageRepositoryForm.AutoRefreshTimerTimer(Sender: TObject);
Begin
  Try
    If (csDestroying in ComponentState) Or FIndexing Or FDetailLoading Or FRemoteOpBusy Or FJobBusy Or
       Not Visible Then
      Exit;
    If GitDirStampChanged Then
      QuietRefreshIfChanged
    Else If (FLastProbeAt = 0) Or (SecondsBetween(Now, FLastProbeAt) >= FProbeIntervalSec) Then
      QuietRefreshIfChanged;
  Except
    On E: Exception Do
      Begin
        FAutoRefreshTimer.Enabled := False;
        WorkflowLogger.Error('PluginBoundary', 'TManageRepositoryForm.AutoRefreshTimerTimer: ' + E.Message);
      End;
  End;
End;

Procedure TManageRepositoryForm.QuietRefreshIfChanged;
Var
  Job: TGitJob;
Begin
  If (FRepoPath = '') Or FProbePending Or Not Assigned(GitJobs) Then
    Exit;
  FLastProbeAt := Now;
  Job := TGitJob.Create(gjkRepoProbe);
  Job.RepoPath := FRepoPath;
  Job.Quiet := True;
  FProbePending := True;
  If Not SubmitGitJob(Job) Then
    FProbePending := False;
End;

Procedure TManageRepositoryForm.UpdateStatus;
Var
  LeftText, CentreText, RightText: String;
  ShortSha: String;
Begin
  If FRepoPath = '' Then
    Begin
      Caption := 'Manage Repository';
      If Assigned(StatusFooter) Then
        StatusFooter.SetAll('No repository', '', 'Ready');
      Exit;
    End;
  Caption := 'Manage Repository: ' + FRepoPath;

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

Function StatusDigestIsClean(Const Digest: String): Boolean;
Var
  Lines: TStringList;
  I: Integer;
  Line: String;
Begin
  Result := True;
  Lines := TStringList.Create;
  Try
    Lines.Text := Digest;
    For I := 0 To Lines.Count - 1 Do
      Begin
        Line := Lines[I];
        If (Line <> '') And (Line[1] <> '#') Then
          Begin
            Result := False;
            Exit;
          End;
      End;
  Finally
    Lines.Free;
  End;
End;

Procedure TManageRepositoryForm.RefreshRepositoryInfo;
Begin
  QuietRefreshIfChanged;
End;

Procedure TManageRepositoryForm.BindRepository(Const StartPath: String);
Var
  SearchPath, Found: String;
Begin
  SearchPath := StartPath;
  If SearchPath = '' Then
    SearchPath := GitIdeStartPath;
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

Procedure TManageRepositoryForm.SetRepository(Const ARepoPath: String; ForceReload: Boolean);
Var
  NewPath: String;
Begin
  If csDestroying in ComponentState Then
    Exit;
  NewPath := ARepoPath;
  If NewPath <> '' Then
    NewPath := ExcludeTrailingPathDelimiter(ExpandFileName(NewPath));
  If (Not ForceReload) And (FRepoPath <> '') And (CompareFilenames(NewPath, FRepoPath) = 0) Then
    Begin
      RefreshRepositoryInfo;
      UpdateStatus;
      If Assigned(Pages) And (Pages.ActivePage = ChangesTab) Then
        RefreshChanges;
      If Assigned(Pages) And (Pages.ActivePage = FilesTabSheet) Then
        RefreshFiles
      Else
        FFilesNeedReload := True;
      Exit;
    End;
  If CompareFilenames(NewPath, FRepoPath) <> 0 Then
    Begin
      Inc(FRepoGeneration);
      FCachedGitDir := ''; FRefsDigest := '';
      FHeadSha := ''; FBranch := ''; FLastPorcelain := ''; FClean := True;
      FHeadPushed := True; FHeadPushedKnown := False; FAmendHead := False;
      FStatusJobPending := False;
      FProbePending := False;
      FRemoteOpBusy := False;
    End;
  { Tear down workers and pending UI work before swapping repo identity. }
  If Assigned(FDetailTimer) Then
    FDetailTimer.Enabled := False;
  StopDetailLoad;
  StopIndexLoad;
  If Assigned(DiffView) Then
    DiffView.Clear;
  FRepoPath := NewPath;
  If Assigned(FHistory) Then
    Begin
      FHistory.RepoPath := NewPath;
      FHistory.SelectedIndex := -1;
      FHistory.Indexing := False;
    End;
  If Assigned(FChanges) Then
    FChanges.RepoPath := NewPath;
  If Assigned(FFiles) Then
    Begin
      FFiles.RepoPath := NewPath;
      FFiles.ClearForNoRepo;
    End;
  FFilesNeedReload := True;
  FLastHeadAge := -1;
  FLastIndexAge := -1;
  FLastProbeAt := 0;
  FSelectedIndex := -1;
  If Assigned(FModel) Then
    FModel.Clear;
  If Assigned(GraphScrollBar) Then
    GraphScrollBar.Position := 0;
  If Assigned(GitClient) Then
    GitClient.RepoPath := NewPath;
  RefreshRepositoryInfo;
  FHistory.UpdateScrollRange;
  UpdateStatus;
  If Assigned(GraphPaintBox) Then
    GraphPaintBox.Invalidate;
  If FRepoPath <> '' Then
    StartIndexLoad
  Else If Assigned(ChangesList) Then
    ChangesList.Items.Clear;
  If Assigned(Pages) And (Pages.ActivePage = ChangesTab) Then
    RefreshChanges;
  If Assigned(Pages) And (Pages.ActivePage = FilesTabSheet) Then
    RefreshFiles;
  ApplyConfig;
End;

Procedure TManageRepositoryForm.RepositoryStateChanged(Const RepoPath: String; NewState: TGitRepositoryState);
Begin
  { Remote ops / jobs apply their own UI update; ignore bus noise mid-op. }
  If FRemoteOpBusy Or FJobBusy Then
    Exit;
  If SameText(RepoPath, FRepoPath) Then
    Begin
      RefreshRepositoryInfo;
      If Assigned(Pages) And (Pages.ActivePage = ChangesTab) Then
        RefreshChanges;
      If Assigned(Pages) And (Pages.ActivePage = FilesTabSheet) Then
        RefreshFiles
      Else
        FFilesNeedReload := True;
    End;
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
      If Assigned(Pages) And (Pages.ActivePage = ChangesTab) Then
        RefreshChanges;
      FFilesNeedReload := True;
      If Assigned(Pages) And (Pages.ActivePage = FilesTabSheet) Then
        RefreshFiles;
    End;
End;

Procedure TManageRepositoryForm.HeadChanged(Const RepoPath: String; Const NewHeadSha: String);
Begin
  If FRemoteOpBusy Or FJobBusy Then
    Exit;
  If SameText(RepoPath, FRepoPath) Then
    SetRepository(FRepoPath, True);
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
