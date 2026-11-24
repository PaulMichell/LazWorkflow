Unit ProjectAssistantForm;

{ Project Assistant main window (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. Reviewed 2026-11-06: a plan item writes a usage
  line; the run summary adds those lines. Reviewed 2026-11-10: the save check before a turn lives in
  AssistantSaveBeforeTurn; the form only asks the question and routes the phone's answer. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Contnrs, Forms, Controls, Graphics, GraphType, Dialogs, ExtCtrls, StdCtrls, ComCtrls,
  LCLType, Menus, ActnList, Clipbrd, WorkflowEvents, StatusFooterFrame, SpellMemo, CompOptsIntf,
  IDEExternToolIntf, AssistantConversation, AssistantImages, AssistantPlan, AssistantEvents, AssistantTrace,
  AssistantTraceView, AssistantAcceptance, AssistantBuildJob, AssistantCodexRun, AssistantClaudeClient, AssistantClaudeInput,
  AssistantToolBroker, AssistantMCPBridge, AssistantMCPListener,
  AssistantIDEWorkspace, AssistantGit, AssistantAccountUsage, AssistantRecovery, AssistantTurnFinish,
  AssistantPlanRun, AssistantSessionObserve, AssistantCodexContext;

Type
  TAssistantMonitorPlanRows = Array Of TAssistantMonitorPlanRow;
  TAssistantMonitorTaskRows = Array Of TAssistantMonitorTaskRow;

  TProjectAssistantForm = Class(TForm, ICompilerFinished, IMarkdownDocumentChanged)
    ActionList: TActionList;
    ModeCombo: TComboBox;
    ModeLabel: TLabel;
    ModelStatusLabel: TLabel;
    NewConversationAction: TAction;
    NewPlanAction: TAction;
    RunPlanAction: TAction;
    AttachImageAction: TAction;
    RemoveAttachmentAction: TAction;
    SaveAttachmentAction: TAction;
    PreviewAttachmentAction: TAction;
    SendAction: TAction;
    SendButton: TButton;
    SettingsButton: TButton;
    TasksButton: TButton;
    StopAction: TAction;
    TasksAction: TAction;
    SettingsAction: TAction;
    StopButton: TButton;
    TargetBrowseButton: TButton;
    TargetCombo: TComboBox;
    TargetLabel: TLabel;
    ExportHistoryAction: TAction;
    DeleteHistoryAction: TAction;
    ContextBreakdownAction: TAction;
    SessionInfoAction: TAction;
    ModelPickerAction: TAction;
    SkillsPickerAction: TAction;
    OpenPlanSheetAction: TAction;
    ClosePlanAction: TAction;
    ClientPanel: TPanel;
    ModeSidePanel: TPanel;
    SidebarPages: TPageControl;
    HistorySheet: TTabSheet;
    PlanSheet: TTabSheet;
    ModeSplitter: TSplitter;
    ConversationColumn: TPanel;
    ConversationHeader: TPanel;
    PromptHost: TPanel;
    ConversationLabel: TLabel;
    ConversationList: TListBox;
    HistoryLabel: TLabel;
    HistoryCombo: TComboBox;
    ExportHistoryButton: TButton;
    DeleteHistoryButton: TButton;
    ChatHost: TPanel;
    { Plan sheet. Streamed in the form resource, not created at runtime. }
    ActivePlanRow: TPanel;
    ActivePlanLabel: TLabel;
    ActivePlanBrowseButton: TButton;
    ActivePlanCombo: TComboBox;
    BuildStatusLabel: TLabel;
    BuildTodoList: TListBox;
    PlanListPopup: TPopupMenu;
    ReviewItemMenu: TMenuItem;
    PlanListSeparator: TMenuItem;
    ReviewPlanMenu: TMenuItem;
    ClosePlanMenu: TMenuItem;
    OpenPlanSheetButton: TButton;
    ClosePlanButton: TButton;
    ComposerStack: TPanel;
    BottomBar: TPanel;
    NewConversationButton: TButton;
    NewPlanButton: TButton;
    RunPlanButton: TButton;
    StatusFooter: TStatusFooterFrame;
    InputPanel: TPanel;
    AttachmentStrip: TPanel;
    InputMemo: TSpellMemo;
    InputPopup: TPopupMenu;
    InputUndoItem: TMenuItem;
    InputRedoItem: TMenuItem;
    InputCutItem: TMenuItem;
    InputCopyItem: TMenuItem;
    InputPasteItem: TMenuItem;
    InputAttachImageItem: TMenuItem;
    InputSelectAllItem: TMenuItem;
    AttachmentPopup: TPopupMenu;
    AttachmentAttachItem: TMenuItem;
    AttachmentRemoveItem: TMenuItem;
    AttachmentSaveItem: TMenuItem;
    AttachmentPreviewItem: TMenuItem;
    PromptSplitter: TSplitter;
    Procedure FormCreate(Sender: TObject);
    Procedure FormDestroy(Sender: TObject);
    Procedure FormShow(Sender: TObject);
    Procedure HistoryPanelResize(Sender: TObject);
    Procedure PlanSheetResize(Sender: TObject);
    Procedure ModeComboChange(Sender: TObject);
    Procedure TargetBrowseClick(Sender: TObject);
    Procedure TargetChoiceChanged(Sender: TObject);
    Procedure RefreshTargetChoices(Sender: TObject);
    Procedure ActivePlanBrowseClick(Sender: TObject);
    Procedure ActivePlanChoiceChanged(Sender: TObject);
    Procedure RefreshActivePlanChoices(Sender: TObject);
    Procedure UpdateTargetComboHint(Sender: TObject);
    Procedure ConversationListClick(Sender: TObject);
    Procedure ConversationListSelectionChange(Sender: TObject; User: Boolean);
    Procedure BuildTodoListClick(Sender: TObject);
    Procedure BuildTodoListDblClick(Sender: TObject);
    Procedure BuildTodoListMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    Procedure BuildTodoListContextPopup(Sender: TObject; MousePos: TPoint; Var Handled: Boolean);
    Procedure BuildTodoListDrawItem(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
    Procedure PlanListPopupPopup(Sender: TObject);
    Procedure ReviewPlanItemClick(Sender: TObject);
    Procedure BuildTodoListSelectionChange(Sender: TObject; User: Boolean);
    Procedure HistoryComboChange(Sender: TObject);
    Procedure SendActionExecute(Sender: TObject);
    Procedure StopActionExecute(Sender: TObject);
    Procedure NewConversationActionExecute(Sender: TObject);
    Procedure NewPlanActionExecute(Sender: TObject);
    Procedure RunPlanActionExecute(Sender: TObject);
    Procedure TasksActionExecute(Sender: TObject);
    Procedure SettingsActionExecute(Sender: TObject);
    Procedure ExportHistoryActionExecute(Sender: TObject);
    Procedure DeleteHistoryActionExecute(Sender: TObject);
    Procedure InputPopupPopup(Sender: TObject);
    Procedure InputCutClick(Sender: TObject);
    Procedure InputCopyClick(Sender: TObject);
    Procedure InputPasteClick(Sender: TObject);
    Procedure AttachImageActionExecute(Sender: TObject);
    Procedure AttachmentPopupPopup(Sender: TObject);
    Procedure RemoveAttachmentActionExecute(Sender: TObject);
    Procedure SaveAttachmentActionExecute(Sender: TObject);
    Procedure PreviewAttachmentActionExecute(Sender: TObject);
    Procedure AttachmentImageMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    Procedure AttachmentImageDblClick(Sender: TObject);
    Procedure InputPanelDropFiles(Sender: TObject; Const FileNames: Array Of String);
    Procedure InputSelectAllClick(Sender: TObject);
    Procedure InputUndoClick(Sender: TObject);
    Procedure InputRedoClick(Sender: TObject);
    Procedure InputMemoChange(Sender: TObject);
    Procedure ContextBreakdownActionExecute(Sender: TObject);
    Procedure SessionInfoActionExecute(Sender: TObject);
    Procedure ModelPickerActionExecute(Sender: TObject);
    Procedure SkillsPickerActionExecute(Sender: TObject);
    Procedure ClosePlanActionExecute(Sender: TObject);
    Procedure OpenPlanActionExecute(Sender: TObject);
    Procedure ComposerStackResize(Sender: TObject);
    Procedure StatusFooterResize(Sender: TObject);
    Procedure PromptHostResize(Sender: TObject);
    Procedure InputMemoPaste(Sender: TObject);
    Procedure InputMemoKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
    Procedure StatusFooterLeftClick(Sender: TObject);
    Procedure StatusFooterEffortClick(Sender: TObject);
    Procedure StatusFooterPermissionsClick(Sender: TObject);
    Procedure StatusFooterSkillClick(Sender: TObject);
    Procedure StatusFooterCentreClick(Sender: TObject);
    Procedure StatusFooterUsageClick(Sender: TObject);
    Procedure StatusFooterRightClick(Sender: TObject);
    Procedure FooterMenuClick(Sender: TObject);
  Public
    FRefreshingTargets: Boolean;
    FRefreshingPlans: Boolean;
    FTargetPaths: TStringList;
    FTargetRestored: Boolean;
    Function TryApplyTarget(Const Directory: String; Out Note: String): Boolean;
    Procedure ApplyTarget(Const Directory: String);
  Public

    FCanCompactContext: Boolean;
    FActiveConnectionId: String;
    FAccountUsageSlot: TAccountUsageSlot;
    FAccountUsageTimer: TTimer;
    FAccountUsageWorker: TThread;
    FAccountUsageWanted: Boolean;
    FAccountUsageAttemptAt: TDateTime;
    FAccountUsageAttemptId: String;
    FContextStatusText: String;
    FContextStatusHint: String;
    FPlanStatusCaption: String;
    FPlanStatusHint: String;
    FAccountApiBase, FAccountKeySource, FAccountKeyEnv, FAccountKeyValue, FAccountPreset, FAccountWire: String;
    FActiveBackend: String;
    FActiveModel: String;
    FReloadConnectionAfterSend: Boolean;
    FPublishModelList: Boolean;
    FPublishReasoningList: Boolean;
    FPublishPermissionsList: Boolean;
    FCodexRuntime, FCodexModel, FCodexProfile, FCodexIdentity, FCodexEffort, FCodexApproval, FCodexModelsJson: String;
    FActiveEffort, FActiveApproval: String;
    FCodexRun: TAssistantCodexRun;
    FClaudeRun: TAssistantClaudeRun;
    FPollingTurn: Boolean;
    { Absolute events JSONL for the turn in flight. Codex and Claude reuse it on a transport retry. }
    FTurnEventsFile: String;
    FClaudeRuntime, FClaudeModel, FClaudeDirectory, FClaudeLaunchPrompt, FClaudeConnectionId: String;
    FClaudeEffort: String;
    FClaudeLaunchReady: Boolean;
    FClaudeRetries: Integer;
    { Claude Code's session for this conversation. The key is connection, project and first turn. }
    FClaudeSessionId, FClaudeSessionKey, FClaudeSubmitText: String;
    FClaudeResume, FClaudeFreshRetried: Boolean;
    { This turn's picture refs. A relaunch of the same turn sends them again; a later turn does not. }
    FClaudeLaunchImages: String;
    { Plan-run session for the current item. A new item does not resume the conversation session. }
    FClaudePlanItem: TClaudePlanItemSession;
    { Last rate-limit report applied to the footer, and the finished turn's usage for the usage log. }
    FClaudeRateLimitJson: String;
    FClaudeUsageReported: Boolean;
    FClaudeInputTokens, FClaudeOutputTokens, FClaudeCachedInputTokens: Int64;
    FClaudeHasCached: Boolean;
    FPlanItemUsage: String;
    FTransportWait: Boolean;
    FTransportWaitStart, FTransportWaitMs: QWord;
    FTransportBackend, FTransportConnectionId: String;
    FReconnectIntervalMs, FCreditIntervalMs: QWord;
    FCodexLaunchPrompt, FCodexLaunchTools, FCodexLaunchInstructions, FCodexLaunchWire: String;
    FCodexLaunchReady: Boolean;
    { Shared by ChatGPT and Claude. }
    FIDEWorkspace: TAssistantIDEWorkspace;
    FToolBroker: TAssistantToolBroker;
    { The running Claude turn's Lazarus tools: its broker run on FToolBroker and its loopback MCP server. }
    ClaudeBridge: TMCPBrokerBridge;
    ClaudeListener: TMCPListener;
    Procedure LoadConnectionSettings;
    Procedure RecordCompletedUsage;
    Function StartCodexReply(Const DisplayText, ApiText: String): Boolean;
    Function StartClaudeReply(Const DisplayText, ApiText: String): Boolean;
    Function BeginTurnEventsFile: String;
    Procedure PollTurn;
    Procedure ApplyTurnEvents(Const Events: TAssistantEventArray);
    Procedure ApplyClaudeRateLimit(Const RateLimitJson: String);
    Function ClaudeSessionKey: String;
    Function ClaudeRecapPrompt(Const SubmitText: String): String;
    Procedure NoteClaudeKeySource(Const KeySource: String);
    Procedure ReleaseCodexProcess;
    Procedure ReleaseCodexRun;
    Procedure ReleaseClaudeProcess;
    Function StartClaudeTools(Scope: TAssistantWriteScope; Out ConfigFile, ErrorText: String): Boolean;
    Procedure ReleaseClaudeTools;
    Function ApproveClaudeTool(Const Tool, Path, OldText, NewText: String): Boolean;
    Function TryDeferDroppedTransport(Const Answer, ErrorText, Body: String): Boolean;
    Procedure ClearTransportWait;
    Procedure AdoptRecoverySentence(Const Sentence: String);
    Procedure PostRecoverySentence(Const Sentence: String);
    Function LaunchStoredCodexRun: Boolean;
    Function LaunchStoredClaudeRun: Boolean;
    Function LaunchStoredTransportRun: Boolean;
    Procedure ResumeDroppedTransport;
    Procedure PollTransportWait;
  Public
    ElapsedTimer: TTimer;
    FDisplayUser: String; { Current-turn user text shown in the Chat tab. }
    FComposerImagesJson: String; { Unsent attachment refs. Not cleared when a model rejects an image. }
    FComposerSelectedIndex: Integer; { Outlined thumbnail. -1 when the strip is empty. }
    FComposerImagesHeld: String; { Cleared from the strip at send, restored if the model rejects the image. }
    FComposerImagesSent: Boolean;
    FPendingTurnAttachments: String; { Refs recorded with the turn when the service history has none. }
    FPasteComposerBusy: Boolean;
    FInputDropArmed: Boolean;
    FInputHeight: Integer;
    FComposerLayoutLock: Boolean;
    FDisplaySystemNote: String; { Optional system/error note for the current surface. }
    FDisplayDurationMs: Integer; { Stored turn wall time when browsing history. }
    FDisplayThinkingMs: Integer; { Stored thinking time when browsing history. }
    FShowThinking: Boolean;
    FShowToolUse: Boolean;
    FEditorFontHooked: Boolean;
    ActiveMode: TAssistantMode;
    FModelName: String;
    FContextUsed: Integer;
    FCodexContextUsage: TCodexContextUsage;
    FContextLimit: Integer;
    FSending: Boolean;
    FStreamingActive: Boolean; { True while assistant reply is streaming. }
    FTurnRecorded: Boolean; { True after this in-flight turn is written to conversation.jsonl. }
    { Id the in-flight turn is stored under, so the phone sees one turn from first token to stored row. }
    LiveTurnId: String;
    { Id of the last row RecordCurrentTurn wrote. A new turn never reuses it. }
    StoredTurnId: String;
    FUserCancelled: Boolean;
    FAssistantContent: String; { Content shown in the chat pane (may be a past turn). }
    FAssistantThinking: String;
    FLiveUser: String; { In-flight turn buffers (updated even when browsing past turns). }
    FLiveContent: String;
    FLiveThinking: String;
    FViewingLive: Boolean; { True when chat pane follows the in-flight turn. }
    FReviewInProgress: Boolean;
    StreamStart: TDateTime;
    FTurnStartTick: QWord;
    FPlanRunStartTick: QWord; { Set when Run Plan starts, 0 when no run is timed. }
    FTurnStartedAt: String;
    FStatusPhase: String; { One of the six progress words while FSending. }
    { Text already on screen when Connecting… began. A repeated snapshot is not new stream text. }
    FConnectHoldContent: String;
    FConnectHoldThinking: String;
    FLastChatPaintTick: QWord;
    FTrace: TAssistantTrace;
    FTraceView: TAssistantTraceView;
    FRefreshingChat: Boolean;
    FIgnoreConversationListChange: Boolean;
    FThinkingSliceStart: Integer;
    FDisplayTraceJson: String;
    FDisplayEventsFile: String;
    FAnswerSliceStart: Integer; { 1-based offset of the current answer block in FLiveContent. }
    FSessionProjectKey: String; { ProjectInfoFile used for last save/load. }
    FSelectedTurnIndex: Integer; { Conversation list selection; -2 = live in-flight row. }
    HistoryIds: TStringList; { Parallel to HistoryCombo; '' = current conversation. }
    FHistoryUpdating: Boolean;
    FApplyingShellConfig: Boolean; { True while restoring mode tab from config.json. }
    FSkipModePersist: Boolean; { True while restoring a saved mode, so SelectMode does not rewrite config. }
    FModeLocked: Boolean; { True while a send freezes the active mode (tools/prompt). }
    FModeSticky: Boolean; { Keep forced Build/Plan mode after send until user changes mode. }
    BuildSections: TObjectList; { of TPlanSection for the Build progress list (not published). }
    ActivePlanPaths: TStringList; { Parallel to ActivePlanCombo; relative paths. }
    FBuildSelectedIndex: Integer; { Survives button clicks that clear ListBox.ItemIndex. }
    FBuildWorkSectionIndex: Integer; { Plan section for active Work-on-this (-1 = none). }
    FBuildWorkSectionTitle: String;
    FBuildWorkPlanPath, FBuildWorkPlanText, FBuildWorkBody, FBuildWorkIdentity: String;
    FCompletionBuildJSON, FCompletionTestJSON: String;
    FPendingReviewErrorOffer: Boolean; { After Review with errors, offer Fix Error. }
    FReviewErrorCount: Integer;
    FContextWarnShown: Boolean; { One-shot warning / auto-rollover when context ≥ 95%. }
    FAutoRolloverInProgress: Boolean; { Guard re-entry while starting a context New Chat. }
    FPlanAgentRunning: Boolean;
    FPlanAgentPackagesDone: Integer;
    FPlanAgentMaxPackages: Integer;
    FPlanAgentResumeIndex: Integer; { Same in-progress item after a turn with no machine validation. }
    FPlanStallTimer: TTimer; { Create(Nil). Not streamed. Lost continuations retry on this. }
    FPlanFileTimer: TTimer; { Create(Nil). Not streamed. Notices a desktop save of the active plan. }
    FPlanDiskAge: LongInt;
    FPlanDiskPendingAge: LongInt;
    FPlanDiskBytes: Int64;
    FPlanDiskPendingBytes: Int64;
    FPlanDocumentRevision: String;
    FPlanHashTick: QWord;
    FPlanStallArmedTick: QWord;
    FPlanStallNoted: Boolean;
    FPlanStallRestarting: Boolean;
    FPlanNewChatThisStep: Boolean;
    FLastTurnHadError: Boolean;
    FLastTurnFinish: TAssistantTurnFinish;
    FContinuationCap: Integer;
    FContinuationCount: Integer;
    FHeldAnswer: String;
    FHoldingContinuation: Boolean;
    FFooterMenu: TPopupMenu;
    FPlanWriteThisTurn: Boolean;
    FOpenBindPending: Boolean; { True until the first BindToActiveProject after Show. }
    FMonitorBound: Boolean; { True after that bind has loaded or cleared the open conversation. }
    FDeferLastTurn: Boolean; { First open: paint empty chrome, then last-turn markdown. }
    FOpenBusy: Boolean; { Busy cursor while first-open conversation markdown runs. }
    Function ComposerHasImages: Boolean;
    Procedure StashComposerImages;
    Procedure RestoreHeldComposerImages;
    Procedure ApplyInputPanelHeight;
    Procedure LayoutComposer;
    Function ComposerChromeHeight: Integer;
    Procedure PlaceComposerChildren;
    Procedure PlacePromptChildren;
    Procedure RefreshComposerImages;
    Procedure PlaceComposerThumbnails;
    Procedure ApplyComposerImageSelection;
    Procedure SelectComposerImage(Index: Integer);
    Function AttachmentStripHeight: Integer;
    Function ComposerImageIndexUnder(Const ScreenPoint: TPoint): Integer;
    Procedure RemoveComposerImageAt(Index: Integer);
    Procedure SaveComposerImage(Index: Integer);
    Procedure PreviewComposerImage(Index: Integer);
    Procedure RefreshAttachAction;
    Function ComposerAttachAllowed(Out Reason: String): Boolean;
    Function ComposerStoreReady(Out Root, StoreDir, ErrorText: String): Boolean;
    Function AttachImageStream(Const OriginalName: String; Stream: TStream; Out ErrorText: String): Boolean;
    Function AttachImageFile(Const SourcePath: String; Out ErrorText: String): Boolean;
    Procedure PasteComposer;
    Procedure QueueComposerPaste;
    Function TryAttachClipboardImage(Reader: TClipboard; Out ErrorText: String): Boolean;
    Procedure ClearUnsentComposerImages;
    Procedure ClearCurrentTurnDisplay;
    Procedure ResetTraceCards;
    Procedure SetCurrentUserDisplay(Const UserText: String; Const WithIdeContext: Boolean);
    Procedure SetCurrentSystemNote(Const NoteText: String);
    Procedure NoteRecovery(RecoveryAction: TAssistantRecoveryAction; Const Fault: TAssistantFault);
    Procedure EnsureConversationStore;
    Procedure RefreshConversationList;
    Procedure RefreshHistoryCombo;
    Procedure UpdateHistoryActions;
    Procedure RebuildClientFromConversation;
    Procedure ApplyLoadedConversationToUi(Const StatusNote: String);
    Function BuildConversationMarkdownExport: String;
    Function DefaultExportFileName: String;
    Procedure ShowConversationTurn(TurnIndex: Integer; Navigate: Boolean = True);
    Procedure ShowLastConversationTurn;
    Procedure RecordCurrentTurn(Const ErrorText: String);
    { The stored id of the turn in flight. Made on first use; a turn that starts after a recorded one gets a new id. }
    Function InFlightTurnId: String;
    { InFlightTurnId while a turn is sending or the live trace has blocks; otherwise the idle id 'live'. }
    Function MonitorLiveTurnId: String;
    Function CurrentStreamDurationMs: Integer;
    Procedure FinishLiveTrace(Const SystemNote: String; DurationMs: Integer);
    Function CurrentModeFromUi: TAssistantMode;
    Procedure EnsureModeComboItems;
    Function ModeOfLoadedConversation: TAssistantMode;
    Procedure SelectMode(Mode: TAssistantMode);
    Procedure SyncModeUi;
    Procedure UpdateModeBadge;
    Function ModeStatusText: String;
    Procedure ApplyModelStatus;
    Procedure ApplySkillStatus;
    Procedure ApplyActiveMode;
    Procedure ShowChatSurfaceKeepMode;
    Procedure LockModeForSend;
    Procedure ForceModeAndLock(Mode: TAssistantMode);
    Procedure UnlockModeAfterSend;
    Function ResolveMessageLineForFix(PreferTopError: Boolean = False): TMessageLine;
    Function CollectRelatedMessages(Primary: TMessageLine; MaxLines: Integer): String;
    Procedure PersistPlanReplyIfNeeded(Const ErrorText: String);
    Function LooksLikePlanMarkdown(Const Body: String): Boolean;
    Procedure PersistShellConfig;
    Procedure ApplyShellConfigFromStore;
    Procedure NewPlan;
    Procedure RefreshBuildTodos;
    Function SelectedBuildSectionIndex: Integer;
    Function SelectedBuildRowIsContext: Boolean;
    Function BuildSelectionMessage: String;
    Procedure SetBuildStatusFeedback(Const MessageText: String);
    Procedure ClearBuildWorkTracking;
    Procedure BeginBuildWorkTracking(SectionIndex: Integer; Const SectionTitle: String);
    Procedure TryAutoCompleteBuildWork(Const StreamErrorText: String);
    Function BuildWorkSectionIsComplete: Boolean;
    Procedure PrepareTopErrorAfterReview(ErrorCount: Integer);
    Procedure OfferFixTopErrorAfterReview;
    Procedure BuildWorkOnSelectedPackage;
    Procedure RunPlan;
    Function CollectPlanRunReportFacts(Kind: TPlanRunEndKind; Const Detail: String): TPlanRunReportFacts;
    Function EndRunPlan(Kind: TPlanRunEndKind; Const Detail: String): String;
    Procedure PostPlanRunReport(Const Report: String);
    Procedure StopRunPlan(Kind: TPlanRunEndKind; Const Detail: String);
    Procedure AppendPlanItemUsage;
    Procedure ContinueRunPlan(Data: PtrInt);
    Procedure EnablePlanStallTimer;
    Procedure MarkPlanAgentAlive;
    Procedure ReleasePlanStallWatch;
    Procedure PlanStallTimerTimer(Sender: TObject);
    Procedure NotePlanDiskAge;
    Procedure EnsurePlanFileTimer;
    Procedure PlanFileTimerTimer(Sender: TObject);
    Procedure ContinuePlanInNewChat(UsagePercent: Integer);
    Function PlanContextThreshold: Integer;
    Function PlanHasOpenItems: Boolean;
    Procedure ContinueCodexAfterFinish(Data: PtrInt);
    Function QueryContinuation(Truncated, ToolRoundCap, HadToolRound: Boolean; Const AssistantText: String): Boolean;
    Function ContinuationToolRecap: String;
    Function FindNextIncompleteBuildSection: Integer;
    Function ClaudeBuildToolsJson: String;
    Function BuildWorkPrompt(Const PlanRel, SectionTitle, StatusText, SectionBody, ParentTitle: String;
      ContinueSameItem: Boolean): String;
    Procedure MaybeWarnHighContextUsage;
    Function AutoCompactAtLimitEnabled: Boolean;
    Function CompactOpenChat: Integer;
    Procedure ApplyDisplayPreferences;
    Procedure ApplyConversationFont;
    Procedure HookEditorFont;
    Procedure UnhookEditorFont;
    Procedure EditorOptionsChanged(Sender: TObject);
    Function ConversationListTurnIndex(ListIndex: Integer): Integer;
    Procedure UpdateStatusFooter;
    Procedure ApplyAccountUsageLabel;
    Procedure RefreshCentreStatus;
    Procedure SyncCodexUsageIdle;
    Procedure NoteAccountConnectionChanged;
    Procedure StartAccountUsageWorker;
    Procedure AccountUsageTimerTimer(Sender: TObject);
    Procedure ReleaseAccountUsageRefresh;
    Function FormatElapsedStatus(Const Phase: String): String;
    Function PlanRunElapsedSuffix: String;
    Function StatusActivityReserve(Const Shown: String): String;
    Procedure SetStreamPhase(Const Phase: String);
    Procedure SetSending(IsSending: Boolean);
    Procedure ElapsedTimerTimer(Sender: TObject);
    Procedure DeferredBind(Data: PtrInt);
    Procedure DeferredShowLastTurn(Data: PtrInt);
    Procedure EnsureChatView;
    Procedure ApplyLiveThinkingAndAnswer;
    Procedure ApplyLiveAnswerSlice;
    Procedure HandleTraceEvent(Const Event: TAssistantEvent);
    Procedure EnsureInputPopup;
    Procedure UpdateInputUndoItems;
    Procedure RefreshChatDisplay(Force: Boolean; ScrollToBottom: Boolean = True);
    Procedure SetBusyCursor(IsBusy: Boolean);
    Procedure SetOpenBusy(IsBusy: Boolean);
    Procedure AppendMessage(Const Role, Content: String);
    Procedure BeginAssistantReply;
    Procedure RevealSubmittedPrompt;
    Procedure ApplyAssistantSnapshots(Const ContentSnapshot, ThinkingSnapshot: String);
    Procedure EnsureFinalAssistantSummary;
    Procedure FinishAssistantReply(Const ErrorText: String);
    Function CurrentTurnFinishFacts(Truncated, ToolRoundCap, ServiceHadTools: Boolean): TAssistantTurnFinishFacts;
    Procedure StreamToken(Const ContentSnapshot, ThinkingSnapshot: String;
      IsFinished: Boolean; Const ErrorText: String);
    Procedure RefreshFromConfig;
    Procedure PersistSession;
    Procedure RestoreSessionIfNeeded;
    Function CollectIDEMessagesText(Out ErrorCount, WarningCount, HintCount: Integer): String;
    Procedure ReviewProject(Reason: TCompileReason; Const KindLabel: String);
    Function BuildReviewPrompt(Const KindLabel, OutputText: String;
      ErrorCount, WarningCount, HintCount: Integer; BuildOk: Boolean): String;
    Function BuildReviewDisplayLabel(Const KindLabel: String;
      ErrorCount, WarningCount, HintCount: Integer; BuildOk: Boolean): String;
    Function BuildFixErrorPromptForLine(Line: TMessageLine): String;
  Public
    { Set while a phone command starts a turn: unsaved work is then saved only when the phone asked for it, and
      the desktop never shows the question. RemoteRefusal says why the turn did not start. }
    RemoteTurnStarting, RemoteSaveFirst: Boolean;
    RemoteRefusal: String;
    { Before a turn in Mode: asks to save unsaved work it could edit. Yes runs Save All; No, or a failed save, gives
      the unsaved work the focus. False means do not start the turn. }
    Function ConfirmSavedBeforeTurn(Mode: TAssistantMode): Boolean;
    Procedure BeginRemoteTurn(SaveFirst: Boolean);
    { Ends BeginRemoteTurn. When the turn did not start for unsaved work, ErrorText becomes that reason. }
    Procedure EndRemoteTurn(Var ErrorText: String);
    Function RemoteSubmitText(Const MessageText: String; Out ErrorText: String): Boolean;
    Function StartRemoteRunPlan(Out ErrorText: String): Boolean;
    Function StartRemoteTask(Const TaskId, Note: String; Out ErrorText: String): Boolean;
    Function SubmitUserText(Const UserText: String; AutoSend: Boolean): Boolean;
    { DisplayText is shown/stored; ApiText is what the model receives (may include extra directives). }
    Function SubmitUserTextEx(Const DisplayText, ApiText: String; AutoSend: Boolean): Boolean;
    { Plan or Document directive, then the user text, then the IDE context block. Chat is the user text only. }
    Function BuildSubmitApiText(Const ModelText: String; Out WithContext: Boolean): String;
    Procedure SteerQueuedText(Const UserText: String);
    Function ModeChipCaption(Mode: TAssistantMode): String;
    Function TurnEngineReady: Boolean;
    Function RunPlanIsAvailable: Boolean;
    Procedure UpdateWorkActions;
    Procedure PopupAboveControl(Host: TControl; Popup: TPopupMenu);
    Procedure ShowSamplingMenu(Kind: Integer);
    Procedure FillModelFooterMenu;
    Function TryApplySamplingChange(Const NewModel, NewEffort, NewApproval: String;
      UpdateModel, UpdateEffort, UpdateApproval: Boolean; Out Note: String; Out DialogKind: TMsgDlgType): Boolean;
    Procedure FillEffortFooterMenu;
    Procedure FillPermissionsFooterMenu;
    Function ApplySamplingChange(Const NewModel, NewEffort, NewApproval: String;
      UpdateModel, UpdateEffort, UpdateApproval: Boolean): Boolean;
    Procedure ApplyConfigAndRefresh;
    Procedure ToggleSkillForMode(Const SkillName: String);
    Function ModeSkillCaption: String;
    Procedure FillSkillFooterMenu;
    Procedure ReviewSelectedPlanItem;
    Procedure SelectPlanListRowAt(Const LocalPos: TPoint);
    Function SelectedPlanListIndex: Integer;
    { DisplayLabel is shown/stored; ApiText is sent to the model. No IDE context; tools off. }
    Procedure SubmitReviewRequest(Const DisplayLabel, ApiText: String);
    { ICompilerFinished – reserved for external bus notifications; review uses IDE API directly. }
    Procedure CompilerFinished(Const ProjectFile: String; Result: TCompilerResult;
      Const OutputText: String; ErrorCount, WarningCount: Integer);
    { IMarkdownDocumentChanged }
    Procedure DocumentChanged(Const FileName: String; Const NewContent: String);
    Procedure DocumentSaved(Const FileName: String);
  Protected
    Procedure Resize; Override;
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
    Function StartNewChat(KeepPlanAgent: Boolean = False; UseChatDefault: Boolean = True): Boolean;
    Procedure ReviewCompile;
    Procedure ReviewBuild;
    Procedure FixTopError;
    Procedure StopStream;
    { Rebind conversation store, session and UI to LazarusIDE.ActiveProject. }
    Procedure BindToActiveProject;
    { Drop project binding without reading ActiveProject (safe during project close). }
    Procedure UnbindFromProject;
    { Read the saved active connection and refresh the status bar. }
    Procedure ReloadActiveConnection;
    /// Copies the current desktop state. Does not write JSON or read provider tokens.
    Procedure FillMonitorView(Out View: TAssistantMonitorView);
    Procedure FillMonitorIdentity(Out ConversationId, ProjectRoot, Title: String);
    /// Reads a stored turn, or the live turn when TurnIndex is LiveConversationMarker. Does not change the selection.
    Function FillMonitorTurn(TurnIndex: Integer; Out Turn: TAssistantMonitorTurn; Out ErrorText: String): Boolean;
    { Live turn only. Copies a block body when its length or running flag differs from SentBlocks.
      A known image keeps its missing flag. A new image is checked once. }
    Function FillMonitorLiveChanges(Const SentBlocks: Array Of TAssistantMonitorBlock; Out Turn: TAssistantMonitorTurn;
      Out ErrorText: String): Boolean;
    /// False until the open conversation has been loaded. A phone resume waits for this.
    Function MonitorScreenReady: Boolean;
    /// Copies BuildSections. Does not write the plan file.
    Procedure FillMonitorPlan(Out Rows: TAssistantMonitorPlanRows);
    /// Whole active-plan Markdown for the phone cache. Empty when none is loaded or the file cannot be read.
    Function ReadMonitorPlanPreview: String;
    { Reads the active plan file into the monitor revision. Does not scan rows. }
    Procedure NoteMonitorPlanRevision;
    { Cached hash of the document last read for the phone. Empty until that read. }
    Function PlanDocumentRevision: String;
    /// Copies the visible plan combobox captions and their registered paths without scanning files.
    Procedure FillMonitorPlanChoices(Paths, Captions: TStrings);
    /// Same rows and limit as RefreshTargetChoices. No package row and no browse action.
    Procedure FillMonitorTargetChoices(Paths, Captions: TStrings; Out Current: String);
    /// ListHistory titles, current row first, then newest archives. At most 40 rows.
    Procedure FillMonitorConversationChoices(Ids, Titles: TStrings; Out Current: String; Out Truncated: Boolean);
    /// Copies LoadAssistantTasks. NeedsNote uses AssistantTaskNeedsUserNote.
    Procedure FillMonitorTasks(Out Rows: TAssistantMonitorTaskRows);
    { SaveFirst is the phone's Yes to the save question. Without it, unsaved work that the turn could edit refuses
      the prompt with AssistantUnsavedEditsRefusal, and nothing is saved or started. }
    Function RemoteSubmit(Const MessageText: String; SaveFirst: Boolean; Out ErrorText: String): Boolean;
    Function RemoteSteer(Const MessageText: String; Out ErrorText: String): Boolean;
    Function RemoteStop(Out ErrorText: String): Boolean;
    Function RemoteSelectMode(Const ModeText: String; Out ErrorText: String): Boolean;
    Function RemoteNewConversation(Out ErrorText: String): Boolean;
    Function RemoteSelectPlan(Const RelativePath: String; Out ErrorText: String): Boolean;
    /// Empty Directory is Current Project. Does not open a folder dialog.
    Function RemoteSelectTarget(Const Directory: String; Out ErrorText: String): Boolean;
    /// Empty ArchiveId is the open conversation and does not call ActivateArchive. Does not open a dialog.
    Function RemoteSelectConversation(Const ArchiveId: String; Out ErrorText: String): Boolean;
    /// Same ids as FillModelFooterMenu. Does not refresh a provider catalogue.
    Procedure FillMonitorModelChoices(Ids, Captions: TStrings; Out Current, Backend, Note: String);
    /// Same rows as FillEffortFooterMenu. Does not refresh a provider catalogue.
    Procedure FillMonitorReasoningChoices(Ids, Captions: TStrings; Out Current, Note: String);
    /// Same rows as FillPermissionsFooterMenu. An empty stored approval is ask.
    Procedure FillMonitorPermissionsChoices(Ids, Captions: TStrings; Out Current, Backend, Note: String);
    /// True once after a connection reload. The monitor pushes the requested lists after status.
    Function TakeSamplingListPublish(Out PublishModels, PublishReasoning, PublishPermissions: Boolean): Boolean;
    /// Does not open a dialog. A matching model id is a success no-op.
    Function RemoteSelectModel(Const ModelId: String; Out ErrorText: String): Boolean;
    /// Does not open a dialog. A matching stored effort id is a success no-op.
    Function RemoteSelectReasoning(Const Level: String; Out ErrorText: String): Boolean;
    /// Does not open a dialog. An empty stored approval counts as ask.
    Function RemoteSelectPermissions(Const Approval: String; Out ErrorText: String): Boolean;
    Function RemoteNewPlan(Const Title: String; Out ErrorText: String): Boolean;
    /// Clears the active plan view. The file and the available list are kept.
    Function CloseActivePlan(Out ErrorText: String): Boolean;
    Function RemoteClosePlan(Out ErrorText: String): Boolean;
    Function RemoteWorkOnPlan(SectionIndex: Integer; Out ErrorText: String): Boolean;
    Function RemoteRunPlan(SaveFirst: Boolean; Out ErrorText: String): Boolean;
    Function RemoteStopPlan(Out ErrorText: String): Boolean;
    Function RemoteRunTask(Const TaskId, Note: String; SaveFirst: Boolean; Out ErrorText: String): Boolean;
    Function RemoteInsertTask(Const TaskId, Note: String; Out ApiText, ErrorText: String): Boolean;
    Function RemoteTurn(TurnIndex: Integer; Out Turn: TAssistantMonitorTurn; Out ErrorText: String): Boolean;
    Function RemoteImage(TurnIndex: Integer; Const ImageId: String; Out Data: TBytes; Out Mime: String;
      Out ImageWidth, ImageHeight: Integer; Out ErrorText: String): Boolean;
    /// Raises the modal depth around a dialog. A nil listener does not skip the counter.
    Function RunAssistantModal(Const Msg: String; DlgType: TMsgDlgType; Buttons: TMsgDlgButtons; HelpCtx: Longint): Integer;
    Function RunAssistantModal(Const QueryCaption, Prompt: String; Var Value: String): Boolean;
  End;

Function ClassifyFormFault(Form: TProjectAssistantForm; Origin: TAssistantFaultOrigin; Const Area: String;
  E: Exception; OwnsTurn: Boolean): TAssistantRecoveryAction;
Function OpenClipboardReader: TClipboard;
Function ClipboardOffersImage(Reader: TClipboard): Boolean;
Function ClipboardTextIsImageFile(Const Text: String; Out LocalPath: String): Boolean;
Function ReadClipboardFormat(Reader: TClipboard; FormatID: TClipboardFormat; Stream: TMemoryStream): Boolean;
Function ClipboardImageName(Const Mime: String): String;
Function GraphicToPngStream(Graphic: TGraphic; Stream: TMemoryStream): Boolean;
Function DroppedLocalPath(Const Name: String): String;
Function StillImageExtension(Const Path: String): Boolean;
Function MimeLooksLikeStillImage(Const Mime: String): Boolean;
Function ComposerSaveFilterIndex(Const FileName: String): Integer;
Function ComposerRefAt(Form: TProjectAssistantForm; Index: Integer; Out Ref: TAssistantImageRef): Boolean;
Function TurnReferencesImage(Const ImageId: String): Boolean;
Procedure AppendComposerStored(Form: TProjectAssistantForm; Const Stored: TAssistantStoredImage);
Procedure AssignThumbImage(Target: TImage; Const ProjectRoot: String; Const Ref: TAssistantImageRef);
Function ComposerImageHint(Const OriginalName: String): String;

Const
  { List Objects store TurnIndex+1. This marker is the in-flight turn. }
  LiveConversationMarker = -2;

Procedure NotifyOpenProjectAssistantFormsProjectChanged;
Procedure NotifyOpenProjectAssistantFormsProjectCleared;
Procedure NotifyOpenProjectAssistantFormsPreferencesChanged;
Procedure NotifyOpenProjectAssistantFormsConnectionChanged;
Procedure NotifyOpenProjectAssistantFormsAccountUsage;
/// True when Tasks… should be shown. An open window wins; otherwise the streamed action.
Function AssistantTasksActionVisible: Boolean;
/// The open Project Assistant window, or nil. Does not create one.
Function OpenProjectAssistantForm: TProjectAssistantForm;

Var
  { AssistantMain assigns this so the IDE Tasks item follows TasksAction.Visible. }
  OnAssistantTasksVisibilityChanged: TProcedure;

Implementation

{$R *.lfm}

Uses AssistantWorkTarget, PackageIntf,
  WorkflowLog, CanvasUtils, AssistantService, AssistantConfig, AssistantSettingsForm, AssistantIDEContext,
  AssistantPlanDocument, AssistantSaveBeforeTurn,
  AssistantTools, AssistantMarkdownForm, AssistantSubagents, GrokOAuth, AssistantAccountWorker, LazFileUtils,
  FileUtil, LCLIntf, LazIDEIntf, IDEMsgIntf, SrcEditorIntf, fpimage, fpwritepng,
  ProjectIntf, AssistantSkills, AssistantConnections, AssistantCapabilities, AssistantUsage, AssistantCodexSettings, AssistantCodexClient,
  AssistantCodexUsage, AssistantHarness, AssistantClaudeStream,
  AssistantRecap, AssistantAccountStatus, AssistantHistoryTrace, AssistantPlanRunHost, AssistantComposerSend,
  AssistantImageView, AssistantXaiProvider, AssistantTasks, AssistantTasksForm, AssistantTaskRun,
  AssistantFileDrop, AssistantTaskNoteForm, LResources;

Var
  RegisteredAssistantForm: TProjectAssistantForm;

Function OpenProjectAssistantForm: TProjectAssistantForm;
Var
  I: Integer;
  Form: TCustomForm;
Begin
  Result := RegisteredAssistantForm;
  If Assigned(Result) And (Not (csDestroying In Result.ComponentState)) Then
    Exit;
  Result := Nil;
  { Scan here, not in the monitor package. A second copy of this class makes Is fail there. }
  For I := 0 To Screen.CustomFormCount - 1 Do
    Begin
      Form := Screen.CustomForms[I];
      If (Form Is TProjectAssistantForm) And (Not (csDestroying In Form.ComponentState)) Then
        Exit(TProjectAssistantForm(Form));
    End;
  For I := 0 To Screen.FormCount - 1 Do
    Begin
      Form := Screen.Forms[I];
      If (Form Is TProjectAssistantForm) And (Not (csDestroying In Form.ComponentState)) Then
        Exit(TProjectAssistantForm(Form));
    End;
End;

Function EffortBarCaption(Const Value: String): String; Forward;
Function ListHasText(List: TStrings; Const Value: String): Boolean; Forward;

Const
  ChatPaintMinIntervalMs = 80;
  { One image_get decoded budget. Larger display files are too_large. The 8 MiB store limit is separate. }
  MonitorImageGetMaxBytes = 1048576;
  FooterTagSkill = 4;
  FooterTagSettings = 5;
  FooterTagModel = 6;
  FooterTagEffort = 7;
  FooterTagApproval = 8;
  { One Claude Code turn may build and run the test suite several times. A turn that reaches this limit is
    stopped and, having run tools, is not replayed, so the limit sits well above a full build-and-test cycle. }
  ClaudeRunTimeoutMs = 3600000;

Var
  TasksActionVisibleKnown: Boolean = False;
  TasksActionVisibleValue: Boolean = True;

Procedure PublishTasksActionVisible(Value: Boolean);
Begin
  TasksActionVisibleValue := Value;
  TasksActionVisibleKnown := True;
  If Assigned(OnAssistantTasksVisibilityChanged) Then
    OnAssistantTasksVisibilityChanged;
End;

Function VisibleInTasksActionText(Const Body: String): Boolean;
Var
  Lines: TStringList;
  Index: Integer;
  Line: String;
  InAction: Boolean;
Begin
  Result := True;
  Lines := TStringList.Create;
  Try
    Lines.Text := Body;
    InAction := False;
    For Index := 0 To Lines.Count - 1 Do
      Begin
        Line := Trim(Lines[Index]);
        If Not InAction Then
          Begin
            If Copy(Line, 1, 19) = 'object TasksAction:' Then
              InAction := True;
          End
        Else If (Line = 'end') Or (Copy(Line, 1, 7) = 'object ') Then
          Exit
        Else If SameText(Line, 'Visible = False') Then
          Exit(False)
        Else If SameText(Line, 'Visible = True') Then
          Exit(True);
      End;
  Finally
    Lines.Free;
  End;
End;

Function OpenStreamedFormResource: TStream;
Var
  Found: TLResource;
Begin
  Result := Nil;
  If Assigned(LazarusResources) Then
    Begin
      Found := LazarusResources.Find('TProjectAssistantForm');
      If Assigned(Found) Then
        Exit(TLazarusResourceStream.CreateFromHandle(Found));
    End;
  Try
    Result := TResourceStream.Create(HInstance, 'TProjectAssistantForm', RT_RCDATA);
  Except
    On EResNotFound Do
      Result := Nil;
  End;
End;

Function ReadStreamedTasksActionVisible: Boolean;
Var
  Source: TStream;
  Text: TMemoryStream;
  Body: String;
Begin
  { The Assistant menu exists before the window. Visible is still the streamed action. }
  Result := True;
  Source := Nil;
  Text := Nil;
  Try
    Try
      Source := OpenStreamedFormResource;
      If Not Assigned(Source) Then
        Exit;
      Text := TMemoryStream.Create;
      FormDataToText(Source, Text);
      If (Text.Size > 0) And Assigned(Text.Memory) Then
        Begin
          SetString(Body, PAnsiChar(Text.Memory), Text.Size);
          Result := VisibleInTasksActionText(Body);
        End;
    Except
      Result := True;
    End;
  Finally
    Text.Free;
    Source.Free;
  End;
End;

Function AssistantTasksActionVisible: Boolean;
Var
  Index: Integer;
  Form: TCustomForm;
Begin
  For Index := 0 To Screen.CustomFormCount - 1 Do
    Begin
      Form := Screen.CustomForms[Index];
      If (Form Is TProjectAssistantForm) And Not (csDestroying In Form.ComponentState) And
        Assigned(TProjectAssistantForm(Form).TasksAction) Then
        Exit(TProjectAssistantForm(Form).TasksAction.Visible);
    End;
  If Not TasksActionVisibleKnown Then
    Begin
      TasksActionVisibleValue := ReadStreamedTasksActionVisible;
      TasksActionVisibleKnown := True;
    End;
  Result := TasksActionVisibleValue;
End;

Constructor TProjectAssistantForm.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FModelName := AssistantConfigDefaultModel;
  FContextUsed := 0;
  FCodexContextUsage := EmptyCodexContextUsage;
  FAccountUsageSlot := TAccountUsageSlot.Create;
  { Soft display budget; Grok/xAI models often allow ~500k tokens. }
  FContextLimit := 500000;
  FSending := False;
  FStreamingActive := False;
  FTurnRecorded := False;
  FUserCancelled := False;
  FAssistantContent := '';
  FAssistantThinking := '';
  FLiveUser := '';
  FLiveContent := '';
  FLiveThinking := '';
  FViewingLive := True;
  FSelectedTurnIndex := -1;
  FDisplayUser := '';
  FDisplaySystemNote := '';
  FDisplayDurationMs := 0;
  FDisplayThinkingMs := 0;
  FShowThinking := True;
  FShowToolUse := True;
  ActiveMode := amChat;
  FApplyingShellConfig := False;
  FModeLocked := False;
  FModeSticky := False;
  FReviewInProgress := False;
  StreamStart := 0;
  FTurnStartTick := 0;
  FPlanRunStartTick := 0;
  FTurnStartedAt := '';
  FStatusPhase := '';
  FLastChatPaintTick := 0;
  FSessionProjectKey := '';
  FTrace := TAssistantTrace.Create;
  FTraceView := Nil;
  FThinkingSliceStart := 1;
  FAnswerSliceStart := 1;
  FDisplayTraceJson := '';
  FDisplayEventsFile := '';
  FHistoryUpdating := False;
  HistoryIds := TStringList.Create;
  ActivePlanPaths := TStringList.Create;
  BuildSections := TObjectList.Create(True);
  FBuildSelectedIndex := -1;
  FBuildWorkSectionIndex := -1;
  FBuildWorkSectionTitle := '';
  FPendingReviewErrorOffer := False;
  FReviewErrorCount := 0;
  FContextWarnShown := False;
  FAutoRolloverInProgress := False;
  FPlanAgentRunning := False;
  FPlanAgentPackagesDone := 0;
  FPlanAgentMaxPackages := 25;
  FPlanAgentResumeIndex := -1;
  FClaudePlanItem := Default(TClaudePlanItemSession);
  FPlanStallTimer := Nil;
  FPlanFileTimer := Nil;
  FPlanDiskAge := -1;
  FPlanDiskPendingAge := -1;
  FPlanDiskBytes := -1;
  FPlanDiskPendingBytes := -1;
  FPlanDocumentRevision := '';
  FPlanHashTick := 0;
  FPlanStallArmedTick := 0;
  FPlanStallNoted := False;
  FPlanStallRestarting := False;
  FPlanNewChatThisStep := False;
  FLastTurnHadError := False;
  FOpenBindPending := True;
  FDeferLastTurn := True;
  FOpenBusy := False;
  FPlanWriteThisTurn := False;
  LoadConnectionSettings;
  WorkflowEventBus.AddListener(Self);
  SyncModeUi;
  EnsurePlanFileTimer;
End;

Procedure TProjectAssistantForm.Resize;
Var
  Available, SideBudget, ChatReserve: Integer;
Begin
  Inherited Resize;
  If (csLoading In ComponentState) Or (csDestroying In ComponentState) Or
    Not Assigned(ClientPanel) Or Not Assigned(ModeSidePanel) Or Not Assigned(ModeSplitter) Then
    Exit;
  Available := ClientPanel.ClientWidth - ModeSplitter.Width;
  If Available <= 0 Then
    Exit;
  ChatReserve := Scale96ToForm(360);
  If ChatReserve > Available Div 2 Then
    ChatReserve := Available Div 2;
  SideBudget := Available - ChatReserve;
  If SideBudget < 1 Then
    SideBudget := 1;
  If ModeSidePanel.Width <= SideBudget Then
    Exit;
  { Shrink only the right-hand sidebar when a saved or small window would squeeze out
    the conversation. Ordinary splitter choices remain untouched until the form
    becomes too narrow. No large minimum window size is imposed. }
  ClientPanel.DisableAlign;
  Try
    ModeSidePanel.Width := SideBudget;
  Finally
    ClientPanel.EnableAlign;
  End;
End;

Destructor TProjectAssistantForm.Destroy;
Var
  OwnWrite: Boolean;
Begin
  { A failed constructor skips BeforeDestruction, so take the write lock here or Destroy loses the error. }
  OwnWrite := Not (csDestroying In ComponentState);
  If OwnWrite Then
    GlobalNameSpace.BeginWrite;
  Destroying;
  UnhookEditorFont;
  If Assigned(ElapsedTimer) Then ElapsedTimer.Enabled := False;
  ReleasePlanStallWatch;
  If Assigned(FPlanStallTimer) Then
    Begin
      FPlanStallTimer.OnTimer := Nil;
      FreeAndNil(FPlanStallTimer);
    End;
  If Assigned(FPlanFileTimer) Then
    Begin
      FPlanFileTimer.Enabled := False;
      FPlanFileTimer.OnTimer := Nil;
      FreeAndNil(FPlanFileTimer);
    End;
  ReleaseAccountUsageRefresh;
  Application.RemoveAsyncCalls(Self);
  If Assigned(WorkflowEventBus) Then WorkflowEventBus.RemoveListener(Self);
  SetAssistantPlanViewerQuiet(False);
  If Assigned(AssistantClient) Then AssistantClient.DetachStreamCallbacks;
  ReleaseCodexRun;
  ReleaseClaudeProcess;
  FreeAndNil(FToolBroker);
  FreeAndNil(FIDEWorkspace);
  If Assigned(AssistantClient) Then
    AssistantClient.CancelStream;
  FSending := False;
  AssistantResetQuietIdeSession;
  Try
    PersistSession;
  Except
    On E: Exception Do
      WorkflowLogger.Error('ProjectAssistant', 'Saving session on close: ' + E.Message);
  End;
  If Assigned(AssistantClient) Then
    AssistantClient.OnTrace := Nil;
  FreeAndNil(HistoryIds);
  FreeAndNil(ActivePlanPaths);
  FreeAndNil(BuildSections);
  FreeAndNil(FTrace);
  FreeAndNil(FTargetPaths);
  FreeAndNil(FFooterMenu);
  Inherited Destroy;
End;

Procedure TProjectAssistantForm.FormCreate(Sender: TObject);
Begin
  If Assigned(TasksAction) Then
    PublishTasksActionVisible(TasksAction.Visible);
  FTargetPaths := TStringList.Create;
  RefreshTargetChoices(Nil);
  Caption := 'Project Assistant';
  { LCL facility: AllowDropFiles and OnDropFiles. Child controls are armed in AssistantFileDrop. }
  AllowDropFiles := True;
  OnDropFiles := @InputPanelDropFiles;
  HistoryPanelResize(HistorySheet);
  PlanSheetResize(PlanSheet);
  If Assigned(InputMemo) Then
    Begin
      InputMemo.BorderSpacing.Around := 0;
      InputMemo.OnKeyDown := @InputMemoKeyDown;
      InputMemo.OnPaste := @InputMemoPaste;
      InputMemo.OnChange := @InputMemoChange;
    End;
  ApplyInputPanelHeight;
  If Assigned(ComposerStack) Then
    ComposerStack.OnResize := @ComposerStackResize;
  If Assigned(PromptHost) Then
    PromptHost.OnResize := @PromptHostResize;
  If Assigned(PromptSplitter) Then
    PromptSplitter.MinSize := Scale96ToForm(48);
  If Assigned(BuildTodoList) Then
    Begin
      BuildTodoList.Style := lbOwnerDrawFixed;
      BuildTodoList.ItemHeight := Scale96ToForm(28);
      BuildTodoList.OnDrawItem := @BuildTodoListDrawItem;
    End;
  EnsureChatView;
  If Assigned(FTraceView) And Assigned(FTrace) Then
    FTraceView.Sync(FTrace, False);
  EnsureInputPopup;
  If Assigned(StatusFooter) Then
    Begin
      StatusFooter.OnLeftClick := @StatusFooterLeftClick;
      StatusFooter.OnEffortClick := @StatusFooterEffortClick;
      StatusFooter.OnPermissionsClick := @StatusFooterPermissionsClick;
      StatusFooter.OnSkillClick := @StatusFooterSkillClick;
      StatusFooter.OnCentreClick := @StatusFooterCentreClick;
      StatusFooter.OnUsageClick := @StatusFooterUsageClick;
      StatusFooter.OnRightClick := @StatusFooterRightClick;
    End;
  ApplyDisplayPreferences;
  HookEditorFont;
  If Not Assigned(ElapsedTimer) Then
    Begin
      ElapsedTimer := TTimer.Create(Self);
      ElapsedTimer.Enabled := False;
      ElapsedTimer.Interval := 250;
      ElapsedTimer.OnTimer := @ElapsedTimerTimer;
    End;
  If Not Assigned(FAccountUsageTimer) Then
    Begin
      { Not owned by the form, so the designer does not stream it. }
      FAccountUsageTimer := TTimer.Create(Nil);
      FAccountUsageTimer.Enabled := True;
      FAccountUsageTimer.Interval := 1000;
      FAccountUsageTimer.OnTimer := @AccountUsageTimerTimer;
    End;
  If Assigned(AssistantClient) Then
    Begin
      AssistantClient.OnTrace := @HandleTraceEvent;
      AssistantClient.OnContinuationQuery := @QueryContinuation;
    End;
  WorkflowLogger.Info('ProjectAssistant', 'Project Assistant window created');
  RegisteredAssistantForm := Self;
  AssistantSessionObserve.AssistantSessionObserve(asnSession);
End;

Function TargetFolderCaption(Const Path: String): String;
Var
  Trimmed: String;
Begin
  Trimmed := ExcludeTrailingPathDelimiter(Path);
  Result := ExtractFileName(Trimmed);
  If Result = '' Then
    Result := Path;
End;

Function TargetFolderHint(Const Path: String): String;
Begin
  If Trim(Path) = '' Then
    Result := ''
  Else
    Result := IncludeTrailingPathDelimiter(ExcludeTrailingPathDelimiter(Path));
End;

Procedure TProjectAssistantForm.UpdateTargetComboHint(Sender: TObject);
Var
  Path: String;
Begin
  If Not Assigned(TargetCombo) Then
    Exit;
  Path := '';
  If Assigned(FTargetPaths) And (TargetCombo.ItemIndex >= 0) And
    (TargetCombo.ItemIndex < FTargetPaths.Count) Then
    Path := FTargetPaths[TargetCombo.ItemIndex];
  TargetCombo.ParentShowHint := False;
  TargetCombo.ShowHint := Path <> '';
  TargetCombo.Hint := TargetFolderHint(Path);
  If Not Assigned(Sender) Then
    Exit;
End;

Procedure TProjectAssistantForm.RefreshTargetChoices(Sender: TObject);
Var
  Recent: TStringList;
  Index, Selected: Integer;
  Path: String;
Begin
  If Not Assigned(TargetCombo) Or Not Assigned(FTargetPaths) Then Exit;
  Recent := TStringList.Create;
  FRefreshingTargets := True;
  TargetCombo.Items.BeginUpdate;
  Try
    TargetCombo.Items.Clear;
    FTargetPaths.Clear;
    TargetCombo.Items.Add(AssistantCurrentProjectCaption);
    FTargetPaths.Add('');
    LoadAssistantRecentTargets(Recent);
    For Index := 0 To Recent.Count - 1 Do
      Begin
        If FTargetPaths.Count > AssistantRecentTargetLimit Then Break;
        Path := Recent[Index];
        If FTargetPaths.IndexOf(Path) >= 0 Then Continue;
        TargetCombo.Items.Add(TargetFolderCaption(Path));
        FTargetPaths.Add(Path);
      End;
    Selected := 0;
    If AssistantTarget.Kind = atkFolder Then
      Begin
        Selected := FTargetPaths.IndexOf(ExcludeTrailingPathDelimiter(AssistantTarget.Root));
        If Selected < 0 Then
          Begin
            Path := ExcludeTrailingPathDelimiter(AssistantTarget.Root);
            TargetCombo.Items.Add(TargetFolderCaption(Path));
            FTargetPaths.Add(Path);
            Selected := FTargetPaths.Count - 1;
          End;
      End
    Else If AssistantTarget.Kind <> atkProject Then
      Selected := -1;
    TargetCombo.ItemIndex := Selected;
  Finally
    TargetCombo.Items.EndUpdate;
    FRefreshingTargets := False;
    Recent.Free;
  End;
  UpdateTargetComboHint(Nil);
End;

Function TProjectAssistantForm.TryApplyTarget(Const Directory: String; Out Note: String): Boolean;
Var
  KeptPlan, Resolved, Err: String;
Begin
  Result := False;
  Note := '';
  KeptPlan := GetActivePlanRelativePath;
  PersistSession;
  If Assigned(FToolBroker) Then FToolBroker.Cancel;
  If Assigned(FIDEWorkspace) Then FIDEWorkspace.CancelBuild;
  If Not AssistantTarget.SelectFolder(Directory, Note) Then
    Exit;
  If AssistantTarget.Kind = atkFolder Then
    RememberAssistantTarget(AssistantTarget.Root)
  Else
    SaveAssistantTarget('');
  BindToActiveProject;
  If (KeptPlan <> '') And (Not SameText(GetActivePlanRelativePath, KeptPlan)) And
    ResolvePlanPath(KeptPlan, Resolved, Err) And FileExistsUTF8(Resolved) Then
    Begin
      SetActivePlanRelativePath(KeptPlan);
      PersistShellConfig;
      RefreshActivePlanChoices(Nil);
      RefreshBuildTodos;
      UpdateWorkActions;
    End;
  RefreshTargetChoices(Nil);
  Result := True;
End;

Procedure TProjectAssistantForm.ApplyTarget(Const Directory: String);
Var
  Note: String;
Begin
  If Not TryApplyTarget(Directory, Note) Then
    Begin
      RunAssistantModal(Note, mtError, [mbOK], 0);
      RefreshTargetChoices(Nil);
      AssistantSessionObserve.AssistantSessionObserve(asnTarget);
      Exit;
    End;
  AssistantSessionObserve.AssistantSessionObserve(asnTarget);
End;

Procedure TProjectAssistantForm.FillMonitorTargetChoices(Paths, Captions: TStrings; Out Current: String);
Var
  Index: Integer;
Begin
  Current := '';
  If Assigned(Paths) Then
    Paths.Clear;
  If Assigned(Captions) Then
    Captions.Clear;
  If Not Assigned(Paths) Or Not Assigned(Captions) Then
    Exit;
  RefreshTargetChoices(Nil);
  If AssistantTarget.Kind = atkProject Then
    Current := ''
  Else
    Current := ExcludeTrailingPathDelimiter(AssistantTarget.Root);
  If Not Assigned(FTargetPaths) Or Not Assigned(TargetCombo) Then
    Exit;
  For Index := 0 To FTargetPaths.Count - 1 Do
    Begin
      Paths.Add(FTargetPaths[Index]);
      If Index < TargetCombo.Items.Count Then
        Captions.Add(TargetCombo.Items[Index])
      Else
        Captions.Add('');
    End;
End;

Function TProjectAssistantForm.RemoteSelectTarget(Const Directory: String; Out ErrorText: String): Boolean;
Var
  Path, Note: String;
  Index: Integer;
  Listed: Boolean;
Begin
  Result := False;
  ErrorText := '';
  { Before any call that can stop a stream. BindToActiveProject stops one. }
  If FReviewInProgress Then
    Begin
      ErrorText := 'Wait for the current review to finish.';
      Exit;
    End;
  If FSending Then
    Begin
      ErrorText := 'Wait for the current reply to finish.';
      Exit;
    End;
  If FPlanAgentRunning Then
    Begin
      ErrorText := 'A plan run is already active.';
      Exit;
    End;
  Path := Trim(Directory);
  If Path <> '' Then
    Path := ExcludeTrailingPathDelimiter(Path);
  RefreshTargetChoices(Nil);
  If (Path = '') And (AssistantTarget.Kind = atkProject) Then
    Begin
      Result := True;
      Exit;
    End;
  If (Path <> '') And (AssistantTarget.Kind = atkFolder) And
    (CompareFilenames(Path, ExcludeTrailingPathDelimiter(AssistantTarget.Root)) = 0) Then
    Begin
      Result := True;
      Exit;
    End;
  Listed := False;
  If Assigned(FTargetPaths) Then
    For Index := 0 To FTargetPaths.Count - 1 Do
      If CompareFilenames(FTargetPaths[Index], Path) = 0 Then
        Begin
          Listed := True;
          Break;
        End;
  If Not Listed Then
    Begin
      ErrorText := 'That target is no longer in the desktop list.';
      Exit;
    End;
  If Not TryApplyTarget(Path, Note) Then
    Begin
      ErrorText := Note;
      Exit;
    End;
  { BindToActiveProject reloads the store and does not publish a snapshot. }
  AssistantSessionObserve.AssistantSessionObserve(asnSnapshot);
  AssistantSessionObserve.AssistantSessionObserve(asnTarget);
  Result := True;
End;

Procedure TProjectAssistantForm.FillMonitorConversationChoices(Ids, Titles: TStrings; Out Current: String; Out Truncated: Boolean);
Const
  ChoiceLimit = 40;
Var
  Items: TObjectList;
  Hist: TConversationHistoryItem;
  Index, Added, CurrentIndex: Integer;
Begin
  Current := '';
  Truncated := False;
  If Assigned(Ids) Then
    Ids.Clear;
  If Assigned(Titles) Then
    Titles.Clear;
  If Not Assigned(Ids) Or Not Assigned(Titles) Then
    Exit;
  EnsureConversationStore;
  Items := TObjectList.Create(True);
  Try
    If Assigned(ProjectAssistantConversation) And (ProjectAssistantConversation.ProjectRoot <> '') Then
      ProjectAssistantConversation.ListHistory(Items);
    CurrentIndex := -1;
    For Index := 0 To Items.Count - 1 Do
      Begin
        Hist := TConversationHistoryItem(Items[Index]);
        If Assigned(Hist) And Hist.IsCurrent Then
          Begin
            CurrentIndex := Index;
            Current := Hist.ArchiveId;
            Break;
          End;
      End;
    Added := 0;
    If CurrentIndex >= 0 Then
      Begin
        Hist := TConversationHistoryItem(Items[CurrentIndex]);
        Ids.Add(Hist.ArchiveId);
        Titles.Add(Hist.Title);
        Inc(Added);
      End;
    For Index := 0 To Items.Count - 1 Do
      Begin
        If Index = CurrentIndex Then
          Continue;
        Hist := TConversationHistoryItem(Items[Index]);
        If Not Assigned(Hist) Then
          Continue;
        If Added >= ChoiceLimit Then
          Begin
            Truncated := True;
            Break;
          End;
        Ids.Add(Hist.ArchiveId);
        Titles.Add(Hist.Title);
        Inc(Added);
      End;
  Finally
    Items.Free;
  End;
End;

Function TProjectAssistantForm.RemoteSelectConversation(Const ArchiveId: String; Out ErrorText: String): Boolean;
Var
  Items: TObjectList;
  Hist: TConversationHistoryItem;
  Index: Integer;
  Listed: Boolean;
Begin
  Result := False;
  ErrorText := '';
  If FSending Then
    Begin
      ErrorText := 'Stop the current reply before switching History.';
      Exit;
    End;
  { The open conversation. Do not park and restore the same files. }
  If ArchiveId = '' Then
    Begin
      Result := True;
      Exit;
    End;
  EnsureConversationStore;
  If Not Assigned(ProjectAssistantConversation) Then
    Begin
      ErrorText := 'That conversation is no longer in History.';
      Exit;
    End;
  Items := TObjectList.Create(True);
  Try
    Listed := False;
    If ProjectAssistantConversation.ProjectRoot <> '' Then
      ProjectAssistantConversation.ListHistory(Items);
    For Index := 0 To Items.Count - 1 Do
      Begin
        Hist := TConversationHistoryItem(Items[Index]);
        If Assigned(Hist) And SameText(Hist.ArchiveId, ArchiveId) Then
          Begin
            Listed := True;
            Break;
          End;
      End;
  Finally
    Items.Free;
  End;
  If Not Listed Then
    Begin
      ErrorText := 'That conversation is no longer in History.';
      Exit;
    End;
  If Not ProjectAssistantConversation.ActivateArchive(ArchiveId) Then
    Begin
      ErrorText := ProjectAssistantConversation.LastError;
      If ErrorText = '' Then
        ErrorText := 'Could not open conversation.';
      Exit;
    End;
  SelectMode(ModeOfLoadedConversation);
  AssistantSessionObserve.AssistantSessionObserve(asnIdentity);
  ApplyLoadedConversationToUi('Loaded conversation from History. Model context restored from its turns.');
  PersistSession;
  WorkflowLogger.Info('ProjectAssistant', 'History activated: ' + ArchiveId);
  { ApplyLoadedConversationToUi does not publish a snapshot. The phone must replace the transcript. }
  AssistantSessionObserve.AssistantSessionObserve(asnSnapshot);
  Result := True;
End;

Procedure TProjectAssistantForm.FillMonitorModelChoices(Ids, Captions: TStrings; Out Current, Backend, Note: String);
Var
  Models: TStringList;
  Index: Integer;
  ModelId, DisplayText: String;
  Beyond: Boolean;
  Procedure AddModel(Const Value: String);
  Begin
    If (Trim(Value) <> '') And Not ListHasText(Models, Value) Then
      Models.Add(Trim(Value));
  End;
Begin
  Current := '';
  Backend := '';
  Note := '';
  If Assigned(Ids) Then
    Ids.Clear;
  If Assigned(Captions) Then
    Captions.Clear;
  If Not Assigned(Ids) Or Not Assigned(Captions) Then
    Exit;
  If FActiveConnectionId = '' Then
    Begin
      Note := 'No connection is selected.';
      Exit;
    End;
  Backend := FActiveBackend;
  Current := Trim(FActiveModel);
  Models := TStringList.Create;
  Try
    If FActiveBackend = 'grok' Then
      Begin
        CollectXaiKnownModelIds(Models);
        AddModel(AssistantConfigDefaultModel);
        AddModel('grok-4');
        AddModel('grok-3');
      End
    Else If (FActiveBackend = 'codex') Then
      CollectCodexModelIds(FCodexModelsJson, Models);
    AddModel(FActiveModel);
    Beyond := False;
    For Index := 0 To Models.Count - 1 Do
      Begin
        ModelId := Models[Index];
        If Not SameText(ModelId, Current) Then
          Beyond := True;
        If FActiveBackend = 'grok' Then
          DisplayText := XaiModelDisplayText(ModelId)
        Else
          DisplayText := ModelId;
        Ids.Add(ModelId);
        Captions.Add(DisplayText);
      End;
    If Not Beyond Then
      Note := 'The rest of this list is in desktop Settings.';
  Finally
    Models.Free;
  End;
End;

Procedure TProjectAssistantForm.FillMonitorReasoningChoices(Ids, Captions: TStrings; Out Current, Note: String);
Var
  Efforts: TStringList;
  Index: Integer;
  Level: String;
  Procedure AddLevel(Const Value, LevelCaption: String);
  Begin
    Ids.Add(Value);
    Captions.Add(LevelCaption);
  End;
Begin
  Current := '';
  Note := '';
  If Assigned(Ids) Then
    Ids.Clear;
  If Assigned(Captions) Then
    Captions.Clear;
  If Not Assigned(Ids) Or Not Assigned(Captions) Then
    Exit;
  If FActiveConnectionId = '' Then
    Begin
      Note := 'No connection is selected.';
      Exit;
    End;
  Current := FActiveEffort;
  If FActiveBackend = 'grok' Then
    Begin
      If XaiModelAllowsEffort(FActiveModel, 'low') Then
        AddLevel('low', 'Low');
      If XaiModelAllowsEffort(FActiveModel, 'medium') Then
        AddLevel('medium', 'Medium');
      If XaiModelAllowsEffort(FActiveModel, 'high') Then
        AddLevel('high', 'High');
      If XaiModelAllowsEffort(FActiveModel, 'xhigh') Then
        AddLevel('xhigh', 'XHigh');
      If Ids.Count = 0 Then
        Begin
          AddLevel('low', 'Low');
          AddLevel('medium', 'Medium');
          AddLevel('high', 'High');
          AddLevel('xhigh', 'XHigh');
        End;
      Exit;
    End;
  If (FActiveBackend = 'codex') Then
    Begin
      AddLevel('', 'Model default');
      Efforts := TStringList.Create;
      Try
        If CollectCodexEffortIds(FCodexModelsJson, FActiveModel, Efforts) Then
          Begin
            If (FActiveEffort <> '') And (Not ListHasText(Efforts, FActiveEffort)) Then
              Efforts.Add(FActiveEffort);
            For Index := 0 To Efforts.Count - 1 Do
              Begin
                Level := Efforts[Index];
                AddLevel(Level, EffortBarCaption(Level));
              End;
          End
        Else If FActiveEffort <> '' Then
          AddLevel(FActiveEffort, EffortBarCaption(FActiveEffort));
      Finally
        Efforts.Free;
      End;
      Exit;
    End;
  Note := 'This connection does not set an effort level.';
End;

Function TProjectAssistantForm.TakeSamplingListPublish(Out PublishModels, PublishReasoning, PublishPermissions: Boolean): Boolean;
Begin
  PublishModels := FPublishModelList;
  PublishReasoning := FPublishReasoningList;
  PublishPermissions := FPublishPermissionsList;
  Result := PublishModels Or PublishReasoning Or PublishPermissions;
  FPublishModelList := False;
  FPublishReasoningList := False;
  FPublishPermissionsList := False;
End;

Function TProjectAssistantForm.RemoteSelectModel(Const ModelId: String; Out ErrorText: String): Boolean;
Var
  Ids, Captions: TStringList;
  Current, Backend, Note, Wanted: String;
  Index: Integer;
  Listed: Boolean;
  DialogKind: TMsgDlgType;
Begin
  Result := False;
  ErrorText := '';
  If FSending Or FPlanAgentRunning Or FReviewInProgress Then
    Begin
      ErrorText := 'Wait until the current work finishes before changing the model, effort, or permissions.';
      Exit;
    End;
  Wanted := Trim(ModelId);
  Ids := TStringList.Create;
  Captions := TStringList.Create;
  Try
    FillMonitorModelChoices(Ids, Captions, Current, Backend, Note);
    If FActiveConnectionId <> '' Then
      Begin
        If SameText(Wanted, Trim(FActiveModel)) Then
          Begin
            Result := True;
            Exit;
          End;
        Listed := False;
        For Index := 0 To Ids.Count - 1 Do
          If SameText(Ids[Index], Wanted) Then
            Begin
              Listed := True;
              Break;
            End;
        If Not Listed Then
          Begin
            ErrorText := 'That model is not in the list.';
            Exit;
          End;
      End;
  Finally
    Captions.Free;
    Ids.Free;
  End;
  If Not TryApplySamplingChange(Wanted, '', '', True, False, False, Note, DialogKind) Then
    Begin
      ErrorText := Note;
      Exit;
    End;
  { The reload asked for every sampling list. This save publishes models and reasoning after status. }
  If FPublishModelList Or FPublishReasoningList Or FPublishPermissionsList Then
    Begin
      FPublishPermissionsList := False;
      FPublishModelList := True;
      FPublishReasoningList := True;
    End;
  Result := True;
End;

Function TProjectAssistantForm.RemoteSelectReasoning(Const Level: String; Out ErrorText: String): Boolean;
Var
  Ids, Captions: TStringList;
  Current, Note: String;
  Index: Integer;
  Listed: Boolean;
  DialogKind: TMsgDlgType;
Begin
  Result := False;
  ErrorText := '';
  If FSending Or FPlanAgentRunning Or FReviewInProgress Then
    Begin
      ErrorText := 'Wait until the current work finishes before changing the model, effort, or permissions.';
      Exit;
    End;
  Ids := TStringList.Create;
  Captions := TStringList.Create;
  Try
    FillMonitorReasoningChoices(Ids, Captions, Current, Note);
    Listed := False;
    For Index := 0 To Ids.Count - 1 Do
      If Ids[Index] = Level Then
        Begin
          Listed := True;
          Break;
        End;
    If Not Listed Then
      Begin
        ErrorText := 'That reasoning level is not in the list.';
        Exit;
      End;
    { Compare the stored id. EffortBarCaption('') is Default, not this empty id. }
    If Level = FActiveEffort Then
      Begin
        Result := True;
        Exit;
      End;
  Finally
    Captions.Free;
    Ids.Free;
  End;
  If Not TryApplySamplingChange('', Level, '', False, True, False, Note, DialogKind) Then
    Begin
      ErrorText := Note;
      Exit;
    End;
  { The reload asked for the sampling lists. This save publishes reasoning after status. }
  If FPublishModelList Or FPublishReasoningList Or FPublishPermissionsList Then
    Begin
      FPublishModelList := False;
      FPublishPermissionsList := False;
      FPublishReasoningList := True;
    End;
  Result := True;
End;

Procedure TProjectAssistantForm.FillMonitorPermissionsChoices(Ids, Captions: TStrings; Out Current, Backend, Note: String);
  Procedure AddMode(Const Value, ModeCaption: String);
  Begin
    Ids.Add(Value);
    Captions.Add(ModeCaption);
  End;
Begin
  Current := 'ask';
  Backend := '';
  Note := '';
  If Assigned(Ids) Then
    Ids.Clear;
  If Assigned(Captions) Then
    Captions.Clear;
  If Not Assigned(Ids) Or Not Assigned(Captions) Then
    Exit;
  If FActiveConnectionId = '' Then
    Begin
      Note := 'No connection is selected.';
      Exit;
    End;
  Backend := FActiveBackend;
  Current := LowerCase(Trim(FActiveApproval));
  Current := ApprovalModeToStr(StrToApprovalMode(Current));
  If (FActiveBackend = 'codex') Then
    Begin
      AddMode('ask', 'Ask before file changes and builds');
      AddMode('always', 'Always: allow registered tools');
    End
  Else
    Begin
      AddMode('ask', 'Ask — confirm each write/compile');
      AddMode('always', 'Always — never prompt (like Build always-approve)');
    End;
End;

Function TProjectAssistantForm.RemoteSelectPermissions(Const Approval: String; Out ErrorText: String): Boolean;
Var
  Ids, Captions: TStringList;
  Current, Backend, Note: String;
  Index: Integer;
  Listed: Boolean;
  DialogKind: TMsgDlgType;
Begin
  Result := False;
  ErrorText := '';
  If FSending Or FPlanAgentRunning Or FReviewInProgress Then
    Begin
      ErrorText := 'Wait until the current work finishes before changing the model, effort, or permissions.';
      Exit;
    End;
  Ids := TStringList.Create;
  Captions := TStringList.Create;
  Try
    FillMonitorPermissionsChoices(Ids, Captions, Current, Backend, Note);
    Listed := False;
    For Index := 0 To Ids.Count - 1 Do
      If Ids[Index] = Approval Then
        Begin
          Listed := True;
          Break;
        End;
    If Not Listed Then
      Begin
        ErrorText := 'That permission is not in the list.';
        Exit;
      End;
    { Empty stored approval is ask. Choosing that value must not write. }
    If SameText(Trim(FActiveApproval), Approval) Or ((Trim(FActiveApproval) = '') And (Approval = 'ask')) Then
      Begin
        Result := True;
        Exit;
      End;
  Finally
    Captions.Free;
    Ids.Free;
  End;
  If Not TryApplySamplingChange('', '', Approval, False, False, True, Note, DialogKind) Then
    Begin
      ErrorText := Note;
      Exit;
    End;
  { The reload asked for the sampling lists. This save publishes permissions after status. }
  If FPublishModelList Or FPublishReasoningList Or FPublishPermissionsList Then
    Begin
      FPublishModelList := False;
      FPublishReasoningList := False;
      FPublishPermissionsList := True;
    End;
  Result := True;
End;

Procedure TProjectAssistantForm.TargetChoiceChanged(Sender: TObject);
Var
  Path: String;
Begin
  If FRefreshingTargets Then Exit;
  If FSending Or FReviewInProgress Then
    Begin
      RefreshTargetChoices(Nil);
      Exit;
    End;
  If (TargetCombo.ItemIndex < 0) Or (TargetCombo.ItemIndex >= FTargetPaths.Count) Then Exit;
  Path := FTargetPaths[TargetCombo.ItemIndex];
  If (Path = '') And (AssistantTarget.Kind = atkProject) Then Exit;
  If (Path <> '') And (AssistantTarget.Kind = atkFolder) And
    (CompareFilenames(ExcludeTrailingPathDelimiter(Path), ExcludeTrailingPathDelimiter(AssistantTarget.Root)) = 0) Then
    Exit;
  ApplyTarget(Path);
End;

Procedure TProjectAssistantForm.TargetBrowseClick(Sender: TObject);
Var
  Dialog: TSelectDirectoryDialog;
Begin
  If FSending Or FReviewInProgress Then Exit;
  Dialog := TSelectDirectoryDialog.Create(Self);
  Try
    Dialog.Title := 'Select target folder';
    Dialog.InitialDir := ExcludeTrailingPathDelimiter(AssistantTarget.Root);
    If Not Dialog.Execute Then Exit;
    ApplyTarget(Dialog.FileName);
  Finally
    Dialog.Free;
  End;
End;

Procedure SizeSheetBottomButtons(Host: TWinControl; LeftButton, RightButton: TButton; Gap: Integer);
Var
  ButtonWidth: Integer;
Begin
  If Not Assigned(Host) Or Not Assigned(LeftButton) Or Not Assigned(RightButton) Then Exit;
  ButtonWidth := (Host.ClientWidth - LeftButton.BorderSpacing.Left - RightButton.BorderSpacing.Right - Gap) Div 2;
  If ButtonWidth < 1 Then ButtonWidth := 1;
  LeftButton.Width := ButtonWidth;
  RightButton.Width := ButtonWidth;
End;

Procedure TProjectAssistantForm.HistoryPanelResize(Sender: TObject);
Begin
  SizeSheetBottomButtons(HistorySheet, ExportHistoryButton, DeleteHistoryButton, Scale96ToForm(4));
End;

Procedure TProjectAssistantForm.PlanSheetResize(Sender: TObject);
Begin
  SizeSheetBottomButtons(PlanSheet, OpenPlanSheetButton, ClosePlanButton, Scale96ToForm(4));
End;

Procedure TProjectAssistantForm.FormShow(Sender: TObject);
Begin
  ApplyConversationFont;
  If Not FInputDropArmed Then
    Begin
      ArmControlFileDrop(InputPanel, Self);
      ArmControlFileDrop(AttachmentStrip, Self);
      ArmControlFileDrop(InputMemo, Self);
      FInputDropArmed := InputMemo.HandleAllocated;
    End;
  { QueueAsyncCall from FormCreate races the first Qt paint and flashes black.
    Show empty chrome, flush it, then bind on a later idle. }
  If Not FOpenBindPending Then
    Exit;
  { Deferred bind is after the first paint. The footer and a connected phone need the model now. }
  LoadConnectionSettings;
  FPublishModelList := True;
  RefreshFromConfig;
  If HandleAllocated Then
    Begin
      Invalidate;
      Update;
    End;
  SetOpenBusy(True);
  Application.QueueAsyncCall(@DeferredBind, 0);
End;

Procedure TProjectAssistantForm.FormDestroy(Sender: TObject);
Begin
  If RegisteredAssistantForm = Self Then
    RegisteredAssistantForm := Nil;
  Try
    AssistantSessionObserve.AssistantSessionObserve(asnSession);
  Except
    On E: Exception Do
      ClassifyFormFault(Self, afoCallbackAfterDetach, 'TProjectAssistantForm.FormDestroy', E, False);
  End;
  Try
    ReleaseInputFileDrop(Self);
    FreeAndNil(FTargetPaths);
    If Assigned(AttachmentStrip) Then
      While AttachmentStrip.ControlCount > 0 Do
        Begin
          AttachmentStrip.Controls[0].Parent := Nil;
          AttachmentStrip.Controls[0].Free;
        End;
    If Assigned(ElapsedTimer) Then
      ElapsedTimer.Enabled := False;
    If Assigned(FFooterMenu) Then
      FFooterMenu.Items.Clear;
    FOpenBusy := False;
    SetBusyCursor(False);
    { Persist OAuth tokens once on close (not on every prompt). }
    If Assigned(AssistantChatConfig) And Assigned(GrokOAuthClient) Then
      Begin
        AssistantChatConfig.ApplyOAuthTokens(GrokOAuthClient.Tokens);
        AssistantChatConfig.Save;
      End;
    WorkflowLogger.Info('ProjectAssistant', 'Project Assistant window destroyed');
  Except
    On E: Exception Do
      Begin
        ClassifyFormFault(Self, afoCallbackAfterDetach, 'TProjectAssistantForm.FormDestroy', E, False);
      End;
  End;
End;

Procedure TProjectAssistantForm.ClearCurrentTurnDisplay;
Begin
  FDisplayUser := '';
  FDisplaySystemNote := '';
  FDisplayDurationMs := 0;
  FDisplayThinkingMs := 0;
  FAssistantContent := '';
  FAssistantThinking := '';
  FLiveUser := '';
  FLiveContent := '';
  FLiveThinking := '';
  FStreamingActive := False;
  FViewingLive := True;
  FSelectedTurnIndex := -1;
  LiveTurnId := '';
  ResetTraceCards;
  If Assigned(FTrace) Then
    FTrace.Clear;
End;

Procedure TProjectAssistantForm.ResetTraceCards;
Begin
  If Assigned(FTraceView) Then
    FTraceView.ResetContent;
End;

Procedure TProjectAssistantForm.SetCurrentUserDisplay(Const UserText: String; Const WithIdeContext: Boolean);
Begin
  FDisplaySystemNote := '';
  If WithIdeContext Then
    FDisplayUser := UserText + LineEnding + LineEnding +
      '*(IDE context attached for the model: selected target + relevant editor.)*'
  Else
    FDisplayUser := UserText;
End;

Procedure TProjectAssistantForm.SetCurrentSystemNote(Const NoteText: String);
Begin
  FDisplaySystemNote := NoteText;
  RefreshChatDisplay(True, False);
End;

Procedure TProjectAssistantForm.AdoptRecoverySentence(Const Sentence: String);
Var
  Last: TTraceBlock;
  Phase: String;
Begin
  If (Sentence = '') Or (csDestroying In ComponentState) Then
    Exit;
  If Assigned(FTrace) Then
    Begin
      Last := Nil;
      If FTrace.Count > 0 Then
        Last := FTrace[FTrace.Count - 1];
      If (Not Assigned(Last)) Or (Last.Kind <> tbkNote) Or (Last.Body <> Sentence) Then
        Begin
          FTrace.AddNote(Sentence);
          If FViewingLive And Assigned(FTraceView) Then
            FTraceView.Sync(FTrace, True);
        End;
    End
  Else
    SetCurrentSystemNote(Sentence);
  If FSending And AssistantRecoveryStatusPhase(Sentence, Phase) Then
    SetStreamPhase(Phase);
End;

Procedure TProjectAssistantForm.NoteRecovery(RecoveryAction: TAssistantRecoveryAction; Const Fault: TAssistantFault);
Var
  Sentence: String;
Begin
  If csDestroying In ComponentState Then
    Exit;
  Sentence := AssistantRecoveryProgressNote(RecoveryAction, Fault.Origin, Fault.Area, Fault.ErrorClass,
    Fault.ErrorText);
  AdoptRecoverySentence(Sentence);
End;

Procedure TProjectAssistantForm.SetBusyCursor(IsBusy: Boolean);
Begin
  { crAppStart is the classic pointer+hourglass "busy but usable" cursor. }
  If IsBusy Then
    Screen.Cursor := crAppStart
  Else If Not FOpenBusy Then
    Screen.Cursor := crDefault;
End;

Procedure TProjectAssistantForm.SetOpenBusy(IsBusy: Boolean);
Begin
  FOpenBusy := IsBusy;
  If IsBusy Then
    SetBusyCursor(True)
  Else If Not FSending Then
    SetBusyCursor(False);
End;

Function ModeComboIndex(Mode: TAssistantMode): Integer;
Begin
  { Visual order: Chat, Inspect, Document, Plan, Build. }
  Case Mode Of
    amInspect: Result := 1;
    amDocument: Result := 2;
    amPlan: Result := 3;
    amBuild: Result := 4;
  Else
    Result := 0;
  End;
End;

Function TProjectAssistantForm.CurrentModeFromUi: TAssistantMode;
Begin
  Result := amChat;
  If Not Assigned(ModeCombo) Then
    Exit;
  Case ModeCombo.ItemIndex Of
    1: Result := amInspect;
    2: Result := amDocument;
    3: Result := amPlan;
    4: Result := amBuild;
  Else
    Result := amChat;
  End;
End;

Procedure TProjectAssistantForm.EnsureModeComboItems;
Begin
  If Not Assigned(ModeCombo) Then
    Exit;
  If (ModeCombo.Items.Count = 5) And (ModeCombo.Items[2] = 'Document') Then
    Exit;
  ModeCombo.Items.BeginUpdate;
  Try
    ModeCombo.Items.Clear;
    ModeCombo.Items.Add('Chat');
    ModeCombo.Items.Add('Inspect');
    ModeCombo.Items.Add('Document');
    ModeCombo.Items.Add('Plan');
    ModeCombo.Items.Add('Build');
  Finally
    ModeCombo.Items.EndUpdate;
  End;
  ModeCombo.Style := csDropDownList;
End;

Function TProjectAssistantForm.ModeOfLoadedConversation: TAssistantMode;
Var
  Turn: TConversationTurn;
Begin
  Result := amChat;
  If Not Assigned(ProjectAssistantConversation) Then
    Exit;
  If ProjectAssistantConversation.TurnCount < 1 Then
    Exit;
  If Not ProjectAssistantConversation.GetTurn(ProjectAssistantConversation.TurnCount - 1, Turn) Then
    Exit;
  If Trim(Turn.Mode) = '' Then
    Exit;
  Result := StrToAssistantMode(Turn.Mode);
End;

Procedure TProjectAssistantForm.SelectMode(Mode: TAssistantMode);
Begin
  ActiveMode := Mode;
  { Keep Document, Plan, and Build until the user picks another mode.
    Clearing sticky here let ApplyActiveMode snap a programmatic Build switch back to the combo. }
  FModeSticky := Mode In [amDocument, amPlan, amBuild];
  SyncModeUi;
  ApplyActiveMode;
  If Not FSkipModePersist Then
    PersistShellConfig;
  AssistantSessionObserve.AssistantSessionObserve(asnMode);
End;

Procedure TProjectAssistantForm.SyncModeUi;
Var
  Wanted: Integer;
Begin
  EnsureModeComboItems;
  FApplyingShellConfig := True;
  Try
    Wanted := ModeComboIndex(ActiveMode);
    If Assigned(ModeCombo) And (ModeCombo.ItemIndex <> Wanted) Then
      ModeCombo.ItemIndex := Wanted;
  Finally
    FApplyingShellConfig := False;
  End;
  UpdateModeBadge;
End;

Function TProjectAssistantForm.ModeChipCaption(Mode: TAssistantMode): String;
Begin
  Case Mode Of
    amChat: Result := 'Chat';
    amInspect: Result := 'Inspect';
    amDocument: Result := 'Document';
    amPlan: Result := 'Plan';
    amBuild: Result := 'Build';
  Else
    Result := 'Chat';
  End;
End;

Function TProjectAssistantForm.ModeStatusText: String;
Var
  ToolsHint: String;
Begin
  Case ActiveMode Of
    amChat: ToolsHint := 'general chat · no project tools or skill';
    amDocument: ToolsHint := 'writes free-form Markdown · will not edit sources or the plan';
    amPlan: ToolsHint := 'creates and edits Markdown · will not edit sources';
    amBuild: ToolsHint := 'edits target files and compiles';
  Else
    ToolsHint := 'explains and inspects · will not write files';
  End;
  If FModeLocked Or FSending Then
    Result := ToolsHint + ' · reply in progress'
  Else If FModeSticky Then
    Result := ToolsHint + ' · sticky'
  Else
    Result := ToolsHint;
End;

Procedure TProjectAssistantForm.ApplyModelStatus;
Begin
  If Assigned(ModelStatusLabel) Then
    Begin
      ModelStatusLabel.Caption := ModeStatusText;
      ModelStatusLabel.Hint := ModeStatusText;
      ModelStatusLabel.ShowHint := ModelStatusLabel.Caption <> '';
    End;
  If Assigned(StatusFooter) Then
    Begin
      StatusFooter.SetLeftText('');
      StatusFooter.SetLeftHint('');
    End;
End;

Procedure TProjectAssistantForm.ApplySkillStatus;
Begin
  If Not Assigned(StatusFooter) Then
    Exit;
  If (FActiveBackend = 'claude') Then
    Begin
      { Claude Code keeps its own tools. Do not describe this assistant's skill list. }
      StatusFooter.SetSkillText('Claude Code');
      StatusFooter.SetSkillHint('Claude Code keeps the session. This assistant does not send its skill list.');
    End
  Else
    Begin
      StatusFooter.SetSkillText(ModeSkillCaption);
      StatusFooter.SetSkillHint('Click to toggle skills for this mode');
    End;
End;

Procedure TProjectAssistantForm.UpdateModeBadge;
Begin
  ApplyModelStatus;
  ApplySkillStatus;
  If Assigned(ModeCombo) Then
    ModeCombo.Enabled := Not (FSending Or FModeLocked);
  UpdateWorkActions;
End;

Function TProjectAssistantForm.TurnEngineReady: Boolean;
Var
  Runtime, Model: String;
  SignedIn: Boolean;
Begin
  Runtime := '';
  Model := '';
  SignedIn := False;
  If (FActiveBackend = 'codex') Then
    Begin
      Runtime := FCodexRuntime;
      Model := FCodexModel;
    End
  Else If (FActiveBackend = 'claude') Then
    Begin
      Runtime := FClaudeRuntime;
      Model := FClaudeModel;
    End
  Else
    SignedIn := Assigned(AssistantChatConfig) And AssistantChatConfig.IsSignedIn;
  Result := AssistantTurnEngineReady(FActiveBackend, Runtime, Model, SignedIn);
End;

Function TProjectAssistantForm.RunPlanIsAvailable: Boolean;
Begin
  { Not limited to Plan or Build. Run Plan switches to Build itself. }
  Result := TurnEngineReady And (Not FSending) And (GetActivePlanRelativePath <> '');
End;

Procedure TProjectAssistantForm.UpdateWorkActions;
Var
  HasPlan, Running: Boolean;
Begin
  HasPlan := GetActivePlanRelativePath <> '';
  Running := FPlanAgentRunning;
  { Stop stays on Run Plan. The other plan-view controls wait until the run ends. }
  If Assigned(OpenPlanSheetAction) Then
    OpenPlanSheetAction.Enabled := HasPlan And (Not Running);
  If Assigned(ClosePlanAction) Then
    ClosePlanAction.Enabled := HasPlan And (Not FSending) And (Not Running);
  If Assigned(NewPlanAction) Then
    NewPlanAction.Enabled := (Not FSending) And (Not Running);
  If Assigned(RunPlanAction) Then
    RunPlanAction.Enabled := RunPlanIsAvailable;
  If Assigned(TasksAction) Then
    TasksAction.Enabled := TurnEngineReady And (Not FSending) And (Not FPlanAgentRunning);
  If Assigned(ActivePlanCombo) Then
    ActivePlanCombo.Enabled := (Not FSending) And (Not Running);
  If Assigned(ActivePlanBrowseButton) Then
    ActivePlanBrowseButton.Enabled := (Not FSending) And (Not Running);
End;

Procedure TProjectAssistantForm.ShowChatSurfaceKeepMode;
Begin
  { Shared turn view is always visible; keep mode UI in sync without tab swaps. }
  SyncModeUi;
  If Assigned(AssistantClient) Then
    Begin
      AssistantClient.SetActiveMode(ActiveMode);
      AssistantClient.ToolsEnabled := ActiveMode <> amChat;
    End;
End;

Procedure TProjectAssistantForm.LockModeForSend;
Begin
  { Capture mode from the mode control, then freeze it for the turn. }
  ActiveMode := CurrentModeFromUi;
  FModeLocked := True;
  FModeSticky := ActiveMode In [amDocument, amPlan, amBuild];
  If Assigned(AssistantClient) Then
    Begin
      AssistantClient.SetActiveMode(ActiveMode);
      AssistantClient.ToolsEnabled := ActiveMode <> amChat;
    End;
  UpdateModeBadge;
  WorkflowLogger.Info('ProjectAssistant',
    'Mode locked for send: ' + AssistantModeToStr(ActiveMode));
End;

Procedure TProjectAssistantForm.ForceModeAndLock(Mode: TAssistantMode);
Begin
  { Enter a specific mode for this turn (e.g. Fix Error / Work-on-this → Build). }
  ActiveMode := Mode;
  FModeLocked := True;
  FModeSticky := Mode In [amDocument, amPlan, amBuild];
  If Assigned(AssistantClient) Then
    Begin
      AssistantClient.SetActiveMode(Mode);
      AssistantClient.ToolsEnabled := Mode <> amChat;
    End;
  SyncModeUi;
  If Not FSkipModePersist Then
    PersistShellConfig;
  WorkflowLogger.Info('ProjectAssistant',
    'Mode forced for send: ' + AssistantModeToStr(Mode));
End;

Procedure TProjectAssistantForm.UnlockModeAfterSend;
Begin
  FModeLocked := False;
  { FModeSticky keeps Plan/Build tools until the user picks another mode. }
  If Assigned(AssistantClient) Then
    Begin
      AssistantClient.SetActiveMode(ActiveMode);
      AssistantClient.ToolsEnabled := ActiveMode <> amChat;
    End;
  UpdateModeBadge;
End;

Function TProjectAssistantForm.LooksLikePlanMarkdown(Const Body: String): Boolean;
Begin
  Result := TextIsAssistantPlan(Body);
End;

Procedure TProjectAssistantForm.PersistPlanReplyIfNeeded(Const ErrorText: String);
Var
  PlanRel, Resolved, Err, Body: String;
  Existing: TStringList;
  NeedWrite: Boolean;
Begin
  { Safety net: if Plan mode completed without write_markdown, save chat plan body. }
  If ActiveMode <> amPlan Then
    Exit;
  If ErrorText <> '' Then
    Exit;
  Body := Trim(FLiveContent);
  If Not LooksLikePlanMarkdown(Body) Then
    Exit;
  PlanRel := GetActivePlanRelativePath;
  If PlanRel = '' Then
    PlanRel := DefaultPlanRelativePath;
  NeedWrite := True;
  Existing := TStringList.Create;
  Try
    If ResolvePlanPath(PlanRel, Resolved, Err) And FileExistsUTF8(Resolved) Then
      Begin
        Try
          Existing.LoadFromFile(Resolved);
          { Skip if disk already holds this content (tool wrote successfully). }
          If Trim(Existing.Text) = Body Then
            NeedWrite := False
          Else If Length(Trim(Existing.Text)) >= Length(Body) Then
            { Disk already as long as the reply — assume tools wrote it. }
            NeedWrite := False;
        Except
          NeedWrite := True;
        End;
      End;
  Finally
    Existing.Free;
  End;
  If Not NeedWrite Then
    Begin
      FPlanWriteThisTurn := True;
      Exit;
    End;
  If Not WriteMarkdownFile(PlanRel, Body + LineEnding, Resolved, Err) Then
    Begin
      WorkflowLogger.Warning('ProjectAssistant', 'Auto-save plan failed: ' + Err);
      If FDisplaySystemNote <> '' Then
        FDisplaySystemNote := FDisplaySystemNote + LineEnding + LineEnding + Err
      Else
        FDisplaySystemNote := Err;
      Exit;
    End;
  SetActivePlanRelativePath(ProjectRelativePath(Resolved));
  PersistShellConfig;
  RefreshActivePlanChoices(Nil);
  RefreshBuildTodos;
  UpdateWorkActions;
  FPlanWriteThisTurn := True;
  If FViewingLive Then
    FDisplaySystemNote := '**Plan saved** to `' + GetActivePlanRelativePath +
      '` (auto-saved because the model did not call write_markdown).';
  WorkflowLogger.Info('ProjectAssistant', 'Auto-saved plan reply to ' + GetActivePlanRelativePath);
End;

Procedure TProjectAssistantForm.ApplyActiveMode;
Begin
  { When mode is locked or sticky, keep ActiveMode; otherwise follow the mode control. }
  If (Not FModeLocked) And (Not FModeSticky) Then
    ActiveMode := CurrentModeFromUi;
  If Assigned(AssistantClient) Then
    Begin
      AssistantClient.SetActiveMode(ActiveMode);
      AssistantClient.ToolsEnabled := ActiveMode <> amChat;
    End;
  If ActiveMode = amPlan Then
    RefreshActivePlanChoices(Nil);
  RefreshBuildTodos;
  UpdateWorkActions;
  SyncModeUi;
End;

Procedure TProjectAssistantForm.PersistShellConfig;
Var
  DocumentPath: String;
Begin
  If Not Assigned(ProjectAssistantConversation) Then
    Exit;
  If ProjectAssistantConversation.ProjectRoot = '' Then
    Exit;
  DocumentPath := GetDocumentRelativePath;
  If Not ProjectAssistantConversation.SaveShellConfig(FShowThinking, ActiveMode,
    GetActivePlanRelativePath, @FShowToolUse, @DocumentPath) Then
    WorkflowLogger.Warning('ProjectAssistant',
      'config.json save failed: ' + ProjectAssistantConversation.LastError);
End;

Procedure TProjectAssistantForm.ApplyShellConfigFromStore;
Var
  ShowThinking, ShowToolUse: Boolean;
  Mode: TAssistantMode;
  PlanFile, DocumentFile: String;
Begin
  If Not Assigned(ProjectAssistantConversation) Then
    Exit;
  DocumentFile := '';
  If Not ProjectAssistantConversation.LoadShellConfig(ShowThinking, Mode, PlanFile, @ShowToolUse, @DocumentFile) Then
    Begin
      { No saved shell mode. A project conversation keeps the mode of its last turn.
        Display flags come from Settings, not this file. }
      ApplyDisplayPreferences;
      If ProjectAssistantConversation.TurnCount > 0 Then
        SelectMode(ModeOfLoadedConversation)
      Else
        SelectMode(amChat);
      Exit;
    End;
  { The project file may still store older display flags. Settings owns them now. }
  If Assigned(AssistantChatConfig) And
    ((ShowThinking <> AssistantChatConfig.ShowThinking) Or (ShowToolUse <> AssistantChatConfig.ShowToolCalls)) Then
    WorkflowLogger.Debug('ProjectAssistant', 'Display flags follow Settings, not the project shell file.');
  ApplyDisplayPreferences;
  SetActivePlanRelativePath(PlanFile);
  SetDocumentRelativePath(DocumentFile);
  FSkipModePersist := True;
  Try
    SelectMode(Mode);
  Finally
    FSkipModePersist := False;
  End;
  RefreshActivePlanChoices(Nil);
End;

Procedure TProjectAssistantForm.RefreshActivePlanChoices(Sender: TObject);
Begin
  Seam_RefreshActivePlanChoices(Self, Sender);
End;

Procedure TProjectAssistantForm.ActivePlanChoiceChanged(Sender: TObject);
Begin
  Seam_ActivePlanChoiceChanged(Self, Sender);
End;

Procedure TProjectAssistantForm.ActivePlanBrowseClick(Sender: TObject);
Begin
  Seam_ActivePlanBrowseClick(Self, Sender);
End;

Procedure TProjectAssistantForm.NewPlan;
Begin
  Seam_NewPlan(Self);
End;

Procedure TProjectAssistantForm.RefreshBuildTodos;
Begin
  Seam_RefreshBuildTodos(Self);
End;

Procedure TProjectAssistantForm.NotePlanDiskAge;
Begin
  Seam_NotePlanDiskAge(Self);
End;

Procedure TProjectAssistantForm.NoteMonitorPlanRevision;
Begin
  Seam_NoteMonitorPlanRevision(Self);
End;

Function TProjectAssistantForm.PlanDocumentRevision: String;
Begin
  Result := Seam_PlanDocumentRevision(Self);
End;

Procedure TProjectAssistantForm.EnsurePlanFileTimer;
Begin
  Seam_EnsurePlanFileTimer(Self);
End;

Procedure TProjectAssistantForm.PlanFileTimerTimer(Sender: TObject);
Begin
  Seam_PlanFileTimerTimer(Self, Sender);
End;

Function TProjectAssistantForm.SelectedBuildSectionIndex: Integer;
Begin
  Result := Seam_SelectedBuildSectionIndex(Self);
End;

Function TProjectAssistantForm.SelectedBuildRowIsContext: Boolean;
Begin
  Result := Seam_SelectedBuildRowIsContext(Self);
End;

Function TProjectAssistantForm.BuildSelectionMessage: String;
Begin
  Result := Seam_BuildSelectionMessage(Self);
End;

Procedure TProjectAssistantForm.SetBuildStatusFeedback(Const MessageText: String);
Begin
  Seam_SetBuildStatusFeedback(Self, MessageText);
End;

Procedure TProjectAssistantForm.ClearBuildWorkTracking;
Begin
  Seam_ClearBuildWorkTracking(Self);
End;

Procedure TProjectAssistantForm.BeginBuildWorkTracking(SectionIndex: Integer; Const SectionTitle: String);
Begin
  Seam_BeginBuildWorkTracking(Self, SectionIndex, SectionTitle);
End;

Procedure TProjectAssistantForm.TryAutoCompleteBuildWork(Const StreamErrorText: String);
Begin
  Seam_TryAutoCompleteBuildWork(Self, StreamErrorText);
End;

Function TProjectAssistantForm.BuildWorkSectionIsComplete: Boolean;
Begin
  Result := Seam_BuildWorkSectionIsComplete(Self);
End;

Procedure TProjectAssistantForm.PrepareTopErrorAfterReview(ErrorCount: Integer);
Begin
  Seam_PrepareTopErrorAfterReview(Self, ErrorCount);
End;

Procedure TProjectAssistantForm.OfferFixTopErrorAfterReview;
Begin
  Seam_OfferFixTopErrorAfterReview(Self);
End;

Function TProjectAssistantForm.ClaudeBuildToolsJson: String;
Begin
  Result := Seam_ClaudeBuildToolsJson(Self);
End;

Function TProjectAssistantForm.BuildWorkPrompt(Const PlanRel, SectionTitle, StatusText,
  SectionBody, ParentTitle: String; ContinueSameItem: Boolean): String;
Begin
  Result := Seam_BuildWorkPrompt(Self, PlanRel, SectionTitle, StatusText, SectionBody, ParentTitle, ContinueSameItem);
End;

Procedure TProjectAssistantForm.BuildWorkOnSelectedPackage;
Begin
  Seam_BuildWorkOnSelectedPackage(Self);
End;

Function TProjectAssistantForm.FindNextIncompleteBuildSection: Integer;
Begin
  Result := Seam_FindNextIncompleteBuildSection(Self);
End;

Function TProjectAssistantForm.CollectPlanRunReportFacts(Kind: TPlanRunEndKind; Const Detail: String): TPlanRunReportFacts;
Begin
  Result := Seam_CollectPlanRunReportFacts(Self, Kind, Detail);
End;

Function TProjectAssistantForm.EndRunPlan(Kind: TPlanRunEndKind; Const Detail: String): String;
Begin
  Result := Seam_EndRunPlan(Self, Kind, Detail);
End;

Procedure TProjectAssistantForm.PostPlanRunReport(Const Report: String);
Begin
  Seam_PostPlanRunReport(Self, Report);
End;

Procedure TProjectAssistantForm.StopRunPlan(Kind: TPlanRunEndKind; Const Detail: String);
Begin
  Seam_StopRunPlan(Self, Kind, Detail);
End;

Procedure TProjectAssistantForm.RunPlan;
Begin
  Seam_RunPlan(Self);
End;

Procedure TProjectAssistantForm.EnablePlanStallTimer;
Begin
  Seam_EnablePlanStallTimer(Self);
End;

Procedure TProjectAssistantForm.MarkPlanAgentAlive;
Begin
  Seam_MarkPlanAgentAlive(Self);
End;

Procedure TProjectAssistantForm.ReleasePlanStallWatch;
Begin
  Seam_ReleasePlanStallWatch(Self);
End;

Function TProjectAssistantForm.PlanContextThreshold: Integer;
Begin
  Result := Seam_PlanContextThreshold(Self);
End;

Function TProjectAssistantForm.PlanHasOpenItems: Boolean;
Begin
  Result := Seam_PlanHasOpenItems(Self);
End;

Procedure TProjectAssistantForm.ContinuePlanInNewChat(UsagePercent: Integer);
Begin
  Seam_ContinuePlanInNewChat(Self, UsagePercent);
End;

Procedure TProjectAssistantForm.PlanStallTimerTimer(Sender: TObject);
Begin
  Seam_PlanStallTimerTimer(Self, Sender);
End;

Procedure TProjectAssistantForm.ContinueRunPlan(Data: PtrInt);
Begin
  Seam_ContinueRunPlan(Self, Data);
End;

Procedure TProjectAssistantForm.RunPlanActionExecute(Sender: TObject);
Begin
  Seam_RunPlanActionExecute(Self, Sender);
End;

Procedure TProjectAssistantForm.BuildTodoListClick(Sender: TObject);
Begin
  Seam_BuildTodoListClick(Self, Sender);
End;

Procedure TProjectAssistantForm.BuildTodoListSelectionChange(Sender: TObject; User: Boolean);
Begin
  Seam_BuildTodoListSelectionChange(Self, Sender, User);
End;

Procedure TProjectAssistantForm.BuildTodoListDrawItem(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
Begin
  Seam_BuildTodoListDrawItem(Self, Control, Index, ARect, State);
End;

Procedure TProjectAssistantForm.BuildTodoListDblClick(Sender: TObject);
Begin
  Seam_BuildTodoListDblClick(Self, Sender);
End;

Procedure TProjectAssistantForm.SelectPlanListRowAt(Const LocalPos: TPoint);
Begin
  Seam_SelectPlanListRowAt(Self, LocalPos);
End;

Procedure TProjectAssistantForm.BuildTodoListMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
Begin
  Seam_BuildTodoListMouseDown(Self, Sender, Button, Shift, X, Y);
End;

Procedure TProjectAssistantForm.BuildTodoListContextPopup(Sender: TObject; MousePos: TPoint; Var Handled: Boolean);
Begin
  Seam_BuildTodoListContextPopup(Self, Sender, MousePos, Handled);
End;

Function TProjectAssistantForm.SelectedPlanListIndex: Integer;
Begin
  Result := Seam_SelectedPlanListIndex(Self);
End;

Procedure TProjectAssistantForm.ReviewSelectedPlanItem;
Begin
  Seam_ReviewSelectedPlanItem(Self);
End;

Procedure TProjectAssistantForm.PlanListPopupPopup(Sender: TObject);
Begin
  Seam_PlanListPopupPopup(Self, Sender);
End;

Procedure TProjectAssistantForm.ReviewPlanItemClick(Sender: TObject);
Begin
  Seam_ReviewPlanItemClick(Self, Sender);
End;

Procedure TProjectAssistantForm.ModeComboChange(Sender: TObject);
Begin
  If FApplyingShellConfig Then
    Exit;
  If FSending Or FModeLocked Then
    Begin
      { Freeze mode UI during a send; restore the combobox to ActiveMode. }
      SyncModeUi;
      Exit;
    End;
  { Explicit mode change ends sticky Plan/Build behaviour. }
  SelectMode(CurrentModeFromUi);
  WorkflowLogger.Info('ProjectAssistant', 'Mode: ' + AssistantModeToStr(ActiveMode));
  RefreshConversationList;
End;

Procedure TProjectAssistantForm.EnsureConversationStore;
Begin
  Seam_EnsureConversationStore(Self);
End;

Function TProjectAssistantForm.ConversationListTurnIndex(ListIndex: Integer): Integer;
Begin
  Result := Seam_ConversationListTurnIndex(Self, ListIndex);
End;

Procedure TProjectAssistantForm.ShowConversationTurn(TurnIndex: Integer; Navigate: Boolean);
Begin
  Seam_ShowConversationTurn(Self, TurnIndex, Navigate);
End;

Procedure TProjectAssistantForm.ShowLastConversationTurn;
Begin
  Seam_ShowLastConversationTurn(Self);
End;

Procedure TProjectAssistantForm.RefreshConversationList;
Begin
  Seam_RefreshConversationList(Self);
End;

Procedure TProjectAssistantForm.RefreshHistoryCombo;
Begin
  Seam_RefreshHistoryCombo(Self);
End;

Procedure TProjectAssistantForm.UpdateHistoryActions;
Begin
  Seam_UpdateHistoryActions(Self);
End;

Function TProjectAssistantForm.DefaultExportFileName: String;
Begin
  Result := Seam_DefaultExportFileName(Self);
End;

Function TProjectAssistantForm.BuildConversationMarkdownExport: String;
Begin
  Result := Seam_BuildConversationMarkdownExport(Self);
End;

Procedure TProjectAssistantForm.RebuildClientFromConversation;
Begin
  Seam_RebuildClientFromConversation(Self);
End;

Procedure TProjectAssistantForm.ApplyLoadedConversationToUi(Const StatusNote: String);
Begin
  Seam_ApplyLoadedConversationToUi(Self, StatusNote);
End;

Procedure TProjectAssistantForm.ConversationListClick(Sender: TObject);
Begin
  Seam_ConversationListClick(Self, Sender);
End;

Procedure TProjectAssistantForm.ConversationListSelectionChange(Sender: TObject; User: Boolean);
Begin
  Seam_ConversationListSelectionChange(Self, Sender, User);
End;

Procedure ApplyTurnAttachmentsToTrace(Trace: TAssistantTrace; Const AttachmentsJson: String);
Var
  Refs: TAssistantImageRefArray;
  TraceRefs: TTraceImageRefArray;
  I: Integer;
Begin
  If Not Assigned(Trace) Then Exit;
  If Not ParseAssistantImageRefs(AttachmentsJson, Refs) Or (Length(Refs) = 0) Then Exit;
  SetLength(TraceRefs, Length(Refs));
  For I := 0 To High(Refs) Do
    Begin
      TraceRefs[I].Id := Refs[I].Id;
      TraceRefs[I].Name := Refs[I].Name;
      TraceRefs[I].DisplayPath := Refs[I].DisplayPath;
      TraceRefs[I].Width := Refs[I].Width;
      TraceRefs[I].Height := Refs[I].Height;
      TraceRefs[I].Missing := False;
    End;
  Trace.SetUserImageRefs(TraceRefs);
End;

Procedure TProjectAssistantForm.EnsureFinalAssistantSummary;
Begin
  Seam_EnsureFinalAssistantSummary(Self);
End;

Procedure TProjectAssistantForm.RecordCurrentTurn(Const ErrorText: String);
Begin
  Seam_RecordCurrentTurn(Self, ErrorText);
End;

Function TProjectAssistantForm.InFlightTurnId: String;
Begin
  Result := Seam_InFlightTurnId(Self);
End;

Function TProjectAssistantForm.MonitorLiveTurnId: String;
Begin
  Result := Seam_MonitorLiveTurnId(Self);
End;

Function TProjectAssistantForm.CurrentStreamDurationMs: Integer;
Begin
  Result := Seam_CurrentStreamDurationMs(Self);
End;

Procedure TProjectAssistantForm.FinishLiveTrace(Const SystemNote: String; DurationMs: Integer);
Begin
  Seam_FinishLiveTrace(Self, SystemNote, DurationMs);
End;

Function TProjectAssistantForm.FormatElapsedStatus(Const Phase: String): String;
Var
  Secs, Mins, Rem: Integer;
  Shown: String;
Begin
  { Always the turn clock. A sentence is not a phase, so it cannot reach this format. }
  Shown := AssistantProgressPhase(Phase);
  Secs := 0;
  If FTurnStartTick <> 0 Then
    Begin
      Secs := Integer((GetTickCount64 - FTurnStartTick) Div 1000);
      If Secs < 0 Then
        Secs := 0;
    End;
  Mins := Secs Div 60;
  Rem := Secs Mod 60;
  Result := Format('%s %d:%2.2d', [Shown, Mins, Rem]) + PlanRunElapsedSuffix;
End;

Function TProjectAssistantForm.PlanRunElapsedSuffix: String;
Begin
  { The whole run's time, in brackets after the turn clock. Empty outside Run Plan. }
  Result := '';
  If FPlanAgentRunning And (FPlanRunStartTick <> 0) Then
    Result := ' (' + FormatPlanRunElapsed(GetTickCount64 - FPlanRunStartTick) + ')';
End;

Function TProjectAssistantForm.StatusActivityReserve(Const Shown: String): String;
Begin
  { The footer reserves the phase plus seven digits and two colons, and uses the phase for nothing else.
    During Run Plan, widen it for ' (h:mm:ss)' as well, so the centre cards do not move on each tick. }
  Result := Shown;
  If PlanRunElapsedSuffix <> '' Then
    Result := Shown + ' (00:)';
End;

Procedure TProjectAssistantForm.SetStreamPhase(Const Phase: String);
Var
  PhaseChanged: Boolean;
  Shown: String;
Begin
  PhaseChanged := Phase <> FStatusPhase;
  If (Phase = AssistantPhaseConnecting) And (FStatusPhase <> AssistantPhaseConnecting) Then
    Begin
      FConnectHoldContent := FLiveContent;
      FConnectHoldThinking := FLiveThinking;
    End;
  FStatusPhase := Phase;
  Shown := AssistantProgressPhase(Phase);
  StatusFooter.SetRightActivityText(FormatElapsedStatus(Shown), StatusActivityReserve(Shown));
  If PhaseChanged Then
    AssistantSessionObserve.AssistantSessionObserve(asnStatus);
End;

Procedure TProjectAssistantForm.LoadConnectionSettings;
Var
  Connections: TAssistantConnections;
  Item: TAssistantConnection;
  PreviousId: String;
Begin
  PreviousId := FActiveConnectionId;
  Try
    FCanCompactContext := False;
    FActiveConnectionId := '';
    FActiveBackend := '';
    FActiveModel := '';
    FAccountApiBase := '';
    FAccountKeySource := '';
    FAccountKeyEnv := '';
    FAccountKeyValue := '';
    FAccountPreset := '';
    FAccountWire := '';
    FCodexRuntime := '';
    FCodexProfile := '';
    FCodexModelsJson := '';
    FClaudeRuntime := '';
    FClaudeModel := '';
    FClaudeEffort := '';
    FActiveEffort := '';
    FActiveApproval := '';
    If Not Assigned(LazarusIDE) Then Exit;
    Connections := TAssistantConnections.Create(LazarusIDE.GetPrimaryConfigPath);
    Try
      Connections.Load; Item := Connections.Active;
      FCanCompactContext := Assigned(Item) And Item.CanCompactContext;
      If Assigned(Item) Then
        Begin
          FActiveConnectionId := Item.Id;
          FActiveBackend := Item.Backend;
          FActiveModel := Item.Model;
          FAccountApiBase := Item.ApiBase;
          FAccountKeySource := Item.KeySource;
          FAccountKeyEnv := Item.KeyEnv;
          FAccountKeyValue := Item.KeyValue;
          FAccountPreset := Item.Preset;
          FAccountWire := Item.WireApi;
          FActiveEffort := Item.ReasoningEffort;
          FActiveApproval := Item.ApprovalMode;
          If (Item.Backend = 'grok') And Assigned(AssistantChatConfig) Then
            Begin
              { The request uses the config. Switching accounts must not keep the previous model's sampling. }
              AssistantChatConfig.AdoptGrokSampling(Item);
              If FActiveEffort = '' Then
                FActiveEffort := AssistantChatConfig.ThinkingLevel;
              If FActiveApproval = '' Then
                FActiveApproval := AssistantChatConfig.ApprovalMode;
            End;
        End;
      If (FActiveBackend = 'codex') Then
        Begin
          FCodexRuntime := Item.Runtime; FCodexModel := Item.Model;
          FCodexProfile := Connections.ProfileDir(Item);
          { Model, effort and approval stay on the connection and apply to this turn, not the profile. }
          FCodexEffort := Item.ReasoningEffort; FCodexApproval := Item.ApprovalMode;
          FCodexModelsJson := Item.CachedModelsJson;
        End
      Else If (FActiveBackend = 'claude') Then
        Begin
          FClaudeRuntime := Item.Runtime;
          FClaudeModel := Item.Model;
          { The approval setting reaches Claude turns through AssistantChatConfig, as for every backend. }
          FClaudeEffort := Item.ReasoningEffort;
        End;
    Finally Connections.Free; End;
  Except
    On E: Exception Do
      Begin
        FCanCompactContext := False;
        FActiveConnectionId := '';
        FActiveBackend := '';
        FActiveModel := '';
        FAccountApiBase := '';
        FAccountKeySource := '';
        FAccountKeyEnv := '';
        FAccountKeyValue := '';
        FAccountPreset := '';
        FAccountWire := '';
        FCodexRuntime := '';
        FCodexProfile := '';
        FCodexModelsJson := '';
        FClaudeRuntime := '';
        FClaudeModel := '';
    FClaudeEffort := '';
        FActiveEffort := '';
        FActiveApproval := '';
        WorkflowLogger.Error('PluginBoundary', 'TProjectAssistantForm.LoadConnectionSettings: ' + E.Message);
      End;
  End;
  If FActiveConnectionId <> PreviousId Then
    NoteAccountConnectionChanged
  Else
    SyncCodexUsageIdle;
End;

Procedure TProjectAssistantForm.ReleaseCodexProcess;
Begin
  If Assigned(FCodexRun) Then
    Begin
      FCodexRun.Cancel;
      ReapCodexWorker(FCodexRun);
      FCodexRun := Nil;
    End;
End;

Procedure TProjectAssistantForm.ReleaseCodexRun;
Begin
  If Assigned(FToolBroker) Then FToolBroker.Cancel;
  ReleaseCodexProcess;
End;

Procedure TProjectAssistantForm.ReleaseClaudeProcess;
Begin
  If Assigned(FClaudeRun) Then
    Begin
      FClaudeRun.Cancel;
      { Same off-thread join as a Codex worker. Do not WaitFor on the IDE thread. }
      ReapCodexWorker(FClaudeRun);
      FClaudeRun := Nil;
    End;
  ReleaseClaudeTools;
End;

{ The Lazarus tools for one Claude turn: a broker run in the turn's scope, served on a loopback port with a new
  token. ConfigFile is the owner-only --mcp-config file, deleted again by ReleaseClaudeTools. }
Function TProjectAssistantForm.StartClaudeTools(Scope: TAssistantWriteScope; Out ConfigFile, ErrorText: String): Boolean;
Begin
  Result := False;
  ConfigFile := '';
  ErrorText := '';
  ReleaseClaudeTools;
  If Not Assigned(FIDEWorkspace) Then FIDEWorkspace := TAssistantIDEWorkspace.Create;
  If Not Assigned(FToolBroker) Then FToolBroker := TAssistantToolBroker.Create(FIDEWorkspace);
  { A Codex launch sets this back to Nil; only one backend runs a turn at a time. }
  FToolBroker.OnApproval := @ApproveClaudeTool;
  ClaudeBridge := TMCPBrokerBridge.Create(FToolBroker);
  { The run carries ActiveMode. Plan and Document share a Markdown scope, so the scope alone is not enough. }
  ClaudeBridge.BeginRun(Scope, ActiveMode);
  ClaudeListener := TMCPListener.Create(ClaudeBridge.ToolsJSON, @ClaudeBridge.Execute);
  If Not ClaudeListener.Start(ErrorText) Then
    Begin
      ReleaseClaudeTools;
      Exit;
    End;
  ConfigFile := ClaudeListener.ConfigFileName;
  Result := True;
End;

{ Finish, cancel and failure all come here through ReleaseClaudeProcess. Waiting calls are released before the
  listener stops, so Stop does not wait on a call the IDE thread will never run. }
Procedure TProjectAssistantForm.ReleaseClaudeTools;
Begin
  If Assigned(ClaudeBridge) Then
    ClaudeBridge.Cancel;
  FreeAndNil(ClaudeListener);
  FreeAndNil(ClaudeBridge);
End;

{ The broker asks before a write, build or git command. The approval setting decides, as for the assistant's own
  tools: Ask shows the confirmation, Auto and Always allow. }
Function TProjectAssistantForm.ApproveClaudeTool(Const Tool, Path, OldText, NewText: String): Boolean;
Var
  ErrorText, CallId: String;
Begin
  CallId := '';
  If Assigned(FToolBroker) Then
    CallId := FToolBroker.ApprovalCallId;
  Result := ApproveBrokerToolCall(Tool, CallId, Path, OldText, NewText, ErrorText);
End;

Function ClaudeWorkDirectory: String;
Begin
  Result := ExcludeTrailingPathDelimiter(ProjectRootPath);
  If Assigned(ProjectAssistantConversation) And (ProjectAssistantConversation.ProjectRoot <> '') Then
    Result := ExcludeTrailingPathDelimiter(ProjectAssistantConversation.ProjectRoot);
  If Result = '' Then
    Result := ExcludeTrailingPathDelimiter(ProjectAssistantRoot);
End;

Procedure TProjectAssistantForm.ClearTransportWait;
Begin
  FTransportWait := False;
  FTransportWaitMs := 0;
End;

Procedure TProjectAssistantForm.PostRecoverySentence(Const Sentence: String);
Begin
  If (Sentence = '') Or (csDestroying In ComponentState) Then
    Exit;
  AdoptRecoverySentence(Sentence);
  WorkflowLogger.Info('ProjectAssistant', Sentence);
End;

Function TProjectAssistantForm.TryDeferDroppedTransport(Const Answer, ErrorText, Body: String): Boolean;
Var
  Decision: TAssistantRecovery;
  RetryAt: TDateTime;
  Note: String;
  Usage, SlotItem: TAccountUsageSnapshot;
  TransportUsageHasReset: Boolean;
  TransportUsageResetsAt: TDateTime;
Begin
  Result := False;
  TransportUsageHasReset := False;
  TransportUsageResetsAt := 0;
  If FTransportWait Then
    Exit(True);
  If (Not FSending) Or FUserCancelled Or (csDestroying In ComponentState) Then
    Exit;
  If (FActiveBackend <> 'codex') And (FActiveBackend <> 'claude') Then
    Exit;
  If (FActiveBackend = 'claude') Then
    Begin
      If Not FClaudeLaunchReady Then
        Exit;
    End
  Else If Not FCodexLaunchReady Then
    Exit;
  If Trim(Answer) <> '' Then
    Exit;
  ClearAccountUsageSnapshot(SlotItem);
  If Assigned(FAccountUsageSlot) Then
    SlotItem := FAccountUsageSlot.ReadSnapshot;
  Usage := AccountUsageForFooter(FActiveConnectionId, SlotItem);
  If (Usage.ConnectionId <> FActiveConnectionId) Or (Not Usage.HasReset) Then
    Begin
      If Not LastAccountUsageSnapshot(Usage) Or (Usage.ConnectionId <> FActiveConnectionId) Then
        ClearAccountUsageSnapshot(Usage);
    End;
  TransportUsageHasReset := Usage.HasReset And (Usage.ConnectionId = FActiveConnectionId);
  TransportUsageResetsAt := Usage.ResetsAt;
  Decision := ClassifyDroppedTransport(ErrorText, Body, FUserCancelled);
  If Decision.Action <> araRetryLastAction Then
    Exit;
  { Same rule for every backend: a tool already ran, so the stored prompt is not started again. }
  If (Assigned(FCodexRun) And (Not AssistantMayReplayTurn(FCodexRun.TurnSnapshot.ReplaySafe))) Or
    (Assigned(FClaudeRun) And (Not AssistantMayReplayTurn(FClaudeRun.TurnSnapshot.ReplaySafe))) Then
    Begin
      PostRecoverySentence(AssistantTurnNotReplayed);
      Exit;
    End;
  Note := '';
  RetryAt := 0;
  FTransportWaitMs := AssistantDroppedTransportWaitMs(Decision.HttpWait, ErrorText, Body, '',
    TransportUsageHasReset, TransportUsageResetsAt, FReconnectIntervalMs, FCreditIntervalMs, Now, RetryAt);
  Note := AssistantDroppedTransportWaitNote(Decision.HttpWait, ErrorText, RetryAt);
  If FTransportWaitMs = 0 Then
    FTransportWaitMs := FReconnectIntervalMs;
  If FTransportWaitMs = 0 Then
    FTransportWaitMs := AssistantReconnectIntervalMs;
  If (FActiveBackend = 'claude') Then
    FTransportBackend := 'claude'
  Else
    FTransportBackend := 'codex';
  FTransportConnectionId := FActiveConnectionId;
  FTransportWaitStart := GetTickCount64;
  FTransportWait := True;
  PostRecoverySentence(Note);
  Result := True;
End;

Function TProjectAssistantForm.LaunchStoredCodexRun: Boolean;
Begin
  Result := False;
  If (Not FCodexLaunchReady) Or (Not Assigned(FToolBroker)) Or (Not Assigned(FIDEWorkspace)) Then
    Exit;
  If FIDEWorkspace.Identity <> FCodexIdentity Then
    Exit;
  FToolBroker.BeginRun(AssistantWriteScopeForMode(ActiveMode), ActiveMode);
  Try
    FCodexRun := TAssistantCodexRun.Create(FCodexRuntime, FCodexProfile, FCodexModel, FCodexLaunchPrompt,
      FCodexLaunchTools, FToolBroker.RunId, 600000, FCodexProfile,
      PlanRunTurnEffort(FPlanAgentRunning, FCodexEffort, AssistantChatConfig.PlanRunEffort), FCodexLaunchInstructions,
      ActiveMode, ProjectAssistantRoot, FCodexLaunchWire, FTurnEventsFile);
    FCodexRun.Start;
    SetStreamPhase(AssistantPhaseWaiting);
    Result := True;
  Except
    On E: Exception Do
      Begin
        ReleaseCodexProcess;
        If E.Message <> '' Then
          FinishAssistantReply(E.Message)
        Else
          FinishAssistantReply(E.ClassName);
      End;
  End;
End;

Function TProjectAssistantForm.LaunchStoredClaudeRun: Boolean;
Var
  TurnSettings: TClaudeTurnSettings;
  ConfigFile, ToolsError, LaunchText: String;
  Images: TClaudeImageArray;
Begin
  Result := False;
  If (Not FClaudeLaunchReady) Or (FClaudeRuntime = '') Or (FClaudeModel = '') Or (FClaudeLaunchPrompt = '') Then
    Exit;
  TurnSettings := Default(TClaudeTurnSettings);
  TurnSettings.Executable := FClaudeRuntime;
  TurnSettings.Model := FClaudeModel;
  TurnSettings.ToolScope := ClaudeToolScopeForMode(ActiveMode);
  TurnSettings.Effort := PlanRunTurnEffort(FPlanAgentRunning, FClaudeEffort, AssistantChatConfig.PlanRunEffort);
  TurnSettings.WorkingDirectory := FClaudeDirectory;
  TurnSettings.TimeoutMs := ClaudeRunTimeoutMs;
  TurnSettings.SessionId := FClaudeSessionId;
  TurnSettings.Resume := FClaudeResume;
  If FTurnEventsFile = '' Then
    BeginTurnEventsFile;
  TurnSettings.EventsFile := FTurnEventsFile;
  LaunchText := FClaudeLaunchPrompt;
  Try
    { A picture that cannot be read fails the send before anything starts. It is not replaced by a text note. }
    If Not ClaudeImagesFromRefs(ProjectAssistantRoot, FClaudeLaunchImages, Images, ToolsError) Then
      Raise Exception.Create(ToolsError);
    If Length(Images) > 0 Then
      Begin
        TurnSettings.StreamInput := True;
        LaunchText := ClaudeUserMessageLine(FClaudeLaunchPrompt, Images);
        SetLength(Images, 0);
      End;
    { Chat has no tools. Every other mode acts only through the Lazarus tools, so a turn without them is refused
      rather than run with reading alone. }
    If ClaudeTurnUsesMCP(ActiveMode) Then
      Begin
        If Not StartClaudeTools(TurnSettings.ToolScope, ConfigFile, ToolsError) Then
          Raise Exception.Create('The Lazarus tools could not start: ' + ToolsError);
        TurnSettings.MCPConfigFile := ConfigFile;
      End;
    If FClaudeResume Then
      Begin
        TurnSettings.SystemPrompt := '';
        If (FClaudeSessionId <> '') And (Not ClaudeHarnessWasDelivered(FClaudeSessionId)) Then
          Begin
            SetCurrentSystemNote('This Claude session was started before the work policy was sent. ' +
              'Claude Code keeps that recorded prompt, so this turn does not pick up the new one. Start a new chat to send it.');
            NoteClaudeHarnessDelivered(FClaudeSessionId);
          End;
      End
    Else
      Begin
        TurnSettings.SystemPrompt := ClaudeHarnessPrompt(ActiveMode);
        If TurnSettings.MCPConfigFile <> '' Then
          TurnSettings.SystemPrompt := TurnSettings.SystemPrompt + LineEnding + LineEnding + ClaudeReadImageNote;
        NoteClaudeHarnessDelivered(FClaudeSessionId);
        WorkflowLogger.Info('ProjectAssistant',
          'Claude Code stores the system prompt on the session''s first request. A later prompt change will not reach a resumed session.');
        If Length(TurnSettings.SystemPrompt) > ClaudeFixtureAcceptedTextChars Then
          WorkflowLogger.Info('ProjectAssistant',
            'Claude append-system-prompt is ' + IntToStr(Length(TurnSettings.SystemPrompt)) +
            ' characters. Fixtures in Tests/Fixtures/Claude show the program accepting up to ' +
            IntToStr(ClaudeFixtureAcceptedTextChars) + ' characters. Project rules stay within ' +
            IntToStr(AssistantAgentsMaxChars) + ' characters. The work policy is kept.');
      End;
    FClaudeRun := TAssistantClaudeRun.Create(TurnSettings, LaunchText);
    SetStreamPhase(AssistantPhaseWaiting);
    Result := True;
  Except
    On E: Exception Do
      Begin
        ReleaseClaudeProcess;
        If E.Message <> '' Then
          FinishAssistantReply(E.Message)
        Else
          FinishAssistantReply(E.ClassName);
      End;
  End;
End;

Function TProjectAssistantForm.LaunchStoredTransportRun: Boolean;
Begin
  If FTransportBackend = 'claude' Then
    Result := LaunchStoredClaudeRun
  Else
    Result := LaunchStoredCodexRun;
End;

Procedure TProjectAssistantForm.ResumeDroppedTransport;
Begin
  If Not FTransportWait Then
    Exit;
  ClearTransportWait;
  PostRecoverySentence(AssistantReconnectResumeNote);
  If LaunchStoredTransportRun Or FTransportWait Or (Not FSending) Then
    Exit;
  FinishAssistantReply('The run could not be restarted.');
End;

Procedure TProjectAssistantForm.PollTransportWait;
Begin
  If FUserCancelled Or (Not FSending) Or (csDestroying In ComponentState) Then
    Begin
      ClearTransportWait;
      Exit;
    End;
  If (FTransportConnectionId <> '') And (FActiveConnectionId <> FTransportConnectionId) Then
    Begin
      StopStream;
      Exit;
    End;
  If (FTransportBackend = 'codex') And Assigned(FIDEWorkspace) And (FIDEWorkspace.Identity <> FCodexIdentity) Then
    Begin
      StopStream;
      Exit;
    End;
  If (FTransportBackend = 'claude') And (FClaudeDirectory <> '') And (ClaudeWorkDirectory <> FClaudeDirectory) Then
    Begin
      StopStream;
      Exit;
    End;
  If GetTickCount64 - FTransportWaitStart < FTransportWaitMs Then
    Begin
      If (FStatusPhase <> '') And Assigned(StatusFooter) Then
        Begin
          StatusFooter.SetRightActivityText(FormatElapsedStatus(AssistantProgressPhase(FStatusPhase)),
            StatusActivityReserve(AssistantProgressPhase(FStatusPhase)));
          AssistantSessionObserve.AssistantSessionObserve(asnStatus);
        End;
      Exit;
    End;
  ResumeDroppedTransport;
End;

Function TProjectAssistantForm.StartCodexReply(Const DisplayText, ApiText: String): Boolean;
Var
  Prompt, Recap, SubmitText, ToolsJson, Instructions, ImageError, InputJson, WireJson: String;
  WithContext: Boolean;
  Refs, WireRefs: TAssistantImageRefArray;
Begin
  Result := False;
  If (FCodexRuntime = '') Or (FCodexModel = '') Then
    Begin
      SettingsActionExecute(Nil);
      If FActiveBackend <> 'codex' Then Exit;
      If (FCodexRuntime = '') Or (FCodexModel = '') Then Exit;
    End;
  If Not Assigned(FIDEWorkspace) Then FIDEWorkspace := TAssistantIDEWorkspace.Create;
  If Not Assigned(FToolBroker) Then FToolBroker := TAssistantToolBroker.Create(FIDEWorkspace);
  FCodexIdentity := FIDEWorkspace.Identity;
  { Turns use ApproveToolIfNeeded. Do not hook the lazarus_* review dialog. }
  FToolBroker.OnApproval := Nil;
  RefreshFromConfig;
  If Not FModeLocked Then LockModeForSend;
  FToolBroker.BeginRun(AssistantWriteScopeForMode(ActiveMode), ActiveMode);
  ShowChatSurfaceKeepMode;
  { Same user text as SubmitUserTextEx. The harness prompt owns the mode essay, including chat's no-tools sentence.
    Pictures are the same stored refs. The Codex wire maps them to localImage; it does not invent a note. }
  SetLength(Refs, 0);
  ParseAssistantImageRefs(FComposerImagesJson, Refs);
  Refs := LimitAssistantImageRefs(Refs);
  SubmitText := BuildSubmitApiText(AssistantImageModelText(ApiText, Length(Refs)), WithContext);
  FPendingTurnAttachments := AssistantImageRefsToJson(Refs);
  { Recap-only. The shared builder owns the limits and the image re-attachment rule. }
  AssistantBuildRecap(ProjectAssistantConversation, ProjectAssistantRoot, FModelName, Refs,
    AssistantContinuityReattachesImages(AssistantBackendContinuity('codex')), AssistantImageMaxAttachments,
    Recap, WireRefs);
  WireJson := AssistantImageRefsToJson(WireRefs);
  { Recap is transport history, not an instruction essay. A missing old file is skipped, not described. }
  Prompt := AssistantRecapPrompt(Recap, SubmitText);
  If Not CodexUserInputJson(ProjectAssistantRoot, Prompt, WireJson, InputJson, ImageError) Then
    Begin
      FPendingTurnAttachments := '';
      UnlockModeAfterSend;
      SetCurrentSystemNote(ImageError);
      RunAssistantModal(ImageError, mtInformation, [mbOK], 0);
      Exit;
    End;
  If Assigned(AssistantClient) Then
    AssistantClient.AddUserMessage(SubmitText, Refs);
  SetCurrentUserDisplay(DisplayText, WithContext);
  FLiveUser := FDisplayUser; FLiveContent := ''; FLiveThinking := '';
  FAssistantContent := ''; FAssistantThinking := '';
  AppendMessage('user', FDisplayUser);
  FContextUsed := Length(Prompt) Div 4;
  FCodexContextUsage := EmptyCodexContextUsage;
  SetSending(True);
  BeginAssistantReply;
  RevealSubmittedPrompt;
  Try
    ToolsJson := BuildAssistantToolsJsonForMode(ActiveMode);
    Instructions := CodexDeveloperInstructions(ActiveMode);
    FCodexLaunchPrompt := Prompt;
    FCodexLaunchTools := ToolsJson;
    FCodexLaunchInstructions := Instructions;
    FCodexLaunchWire := WireJson;
    FCodexLaunchReady := True;
    BeginTurnEventsFile;
    FCodexRun := TAssistantCodexRun.Create(FCodexRuntime, FCodexProfile, FCodexModel,
      Prompt, ToolsJson, FToolBroker.RunId, 600000, FCodexProfile,
      PlanRunTurnEffort(FPlanAgentRunning, FCodexEffort, AssistantChatConfig.PlanRunEffort), Instructions, ActiveMode,
      ProjectAssistantRoot, WireJson, FTurnEventsFile);
    BeginWriteImageTurn;
    FCodexRun.Start;
    FComposerImagesSent := Length(Refs) > 0;
    Result := True;
  Except
    On E: Exception Do
      Begin
        { Finish defers a transport or credit failure. Do not cancel the broker first. }
        If ClassifyFormFault(Self, afoTurn, 'TProjectAssistantForm.StartCodexReply', E, True) = araIgnore Then
          FinishAssistantReply('')
        Else
          FinishAssistantReply(E.Message);
        Result := FSending;
      End;
  End;
End;

Function TProjectAssistantForm.ClaudeSessionKey: String;
Var
  Turn: TConversationTurn;
Begin
  { A new chat has no first turn and a History conversation has another one, so both start a new session. }
  Result := FActiveConnectionId + '|' + ClaudeWorkDirectory + '|';
  If Assigned(ProjectAssistantConversation) And (ProjectAssistantConversation.TurnCount > 0) And
    ProjectAssistantConversation.GetTurn(0, Turn) Then
    Result := Result + Turn.Id;
End;

Function TProjectAssistantForm.ClaudeRecapPrompt(Const SubmitText: String): String;
Begin
  { Only for a new Claude Code session. A resumed session keeps its own history and its pictures.
    This path does not re-attach older images, and it does not give Grok a session id. }
  Result := AssistantRecapPrompt(AssistantBoundedRecap(ProjectAssistantConversation, FModelName), SubmitText);
End;

Function TProjectAssistantForm.StartClaudeReply(Const DisplayText, ApiText: String): Boolean;
Var
  Prompt, SubmitText, RefsJson, ImageError: String;
  WithContext: Boolean;
  Refs: TAssistantImageRefArray;
  Images: TClaudeImageArray;
Begin
  Result := False;
  If (FClaudeRuntime = '') Or (FClaudeModel = '') Then
    Begin
      SettingsActionExecute(Nil);
      If FActiveBackend <> 'claude' Then Exit;
      If (FClaudeRuntime = '') Or (FClaudeModel = '') Then Exit;
    End;
  { This turn's pictures only. A resumed session already holds earlier ones, so they are not sent again. }
  SetLength(Refs, 0);
  ParseAssistantImageRefs(FComposerImagesJson, Refs);
  Refs := LimitAssistantImageRefs(Refs);
  RefsJson := '';
  If Length(Refs) > 0 Then
    RefsJson := AssistantImageRefsToJson(Refs);
  { A stored picture that cannot be read stops the send here, before anything is shown as sent. }
  If Not ClaudeImagesFromRefs(ProjectAssistantRoot, RefsJson, Images, ImageError) Then
    Begin
      SetCurrentSystemNote(ImageError);
      RunAssistantModal(ImageError, mtInformation, [mbOK], 0);
      Exit;
    End;
  SetLength(Images, 0);
  RefreshFromConfig;
  If Not FModeLocked Then LockModeForSend;
  ShowChatSurfaceKeepMode;
  SubmitText := BuildSubmitApiText(AssistantImageModelText(ApiText, Length(Refs)), WithContext);
  FPendingTurnAttachments := RefsJson;
  FClaudeLaunchImages := RefsJson;
  FClaudeSubmitText := SubmitText;
  FClaudeFreshRetried := False;
  If Not ApplyClaudePlanItemSession(FClaudePlanItem, FClaudeSessionId, FClaudeSessionKey, FClaudeResume,
    FPlanAgentRunning, SubmitText, Prompt) Then
    If (FClaudeSessionId <> '') And (FClaudeSessionKey = ClaudeSessionKey) Then
      Begin
        FClaudeResume := True;
        Prompt := SubmitText;
      End
    Else
      Begin
        FClaudeSessionId := NewClaudeSessionId;
        FClaudeResume := False;
        Prompt := ClaudeRecapPrompt(SubmitText);
      End;
  { Do not copy this turn into the HTTP client. Claude Code keeps its own session. }
  SetCurrentUserDisplay(DisplayText, WithContext);
  FLiveUser := FDisplayUser;
  FLiveContent := '';
  FLiveThinking := '';
  FAssistantContent := '';
  FAssistantThinking := '';
  AppendMessage('user', FDisplayUser);
  FContextUsed := Length(Prompt) Div 4;
  FClaudeDirectory := ClaudeWorkDirectory;
  FClaudeConnectionId := FActiveConnectionId;
  FClaudeLaunchPrompt := Prompt;
  FClaudeLaunchReady := True;
  BeginTurnEventsFile;
  FClaudeRetries := 0;
  FClaudeUsageReported := False;
  SetSending(True);
  BeginAssistantReply;
  If FClaudePlanItem.Active And Assigned(FTrace) Then
    Begin
      FTrace.AddNote(ClaudePlanItemSessionNote(FBuildWorkSectionTitle, FClaudeSessionId, FClaudeResume));
      If FViewingLive And Assigned(FTraceView) Then
        FTraceView.Sync(FTrace, True);
      WorkflowLogger.Info('ProjectAssistant', FTrace[FTrace.Count - 1].Body);
    End;
  { The Lazarus tools and the Claude Code process start on this thread. The prompt is on screen first. }
  RevealSubmittedPrompt;
  Result := LaunchStoredClaudeRun;
  { The composer keeps its pictures until the turn ends; a send failure puts them back. }
  If Result Then
    FComposerImagesSent := Length(Refs) > 0;
  If (Not Result) And FSending And (Not FTransportWait) Then
    FinishAssistantReply('The run could not be restarted.');
  If FClaudePlanItem.Active And (Not FSending) Then
    ReleaseClaudePlanItemSession(FClaudePlanItem, FClaudeSessionId, FClaudeSessionKey);
  Result := FSending;
End;

Procedure TProjectAssistantForm.ApplyClaudeRateLimit(Const RateLimitJson: String);
Var
  Item: TAccountUsageSnapshot;
  ErrorText: String;
Begin
  { The subscription's own windows, as Claude Code reported them during the turn. }
  If (RateLimitJson = '') Or (RateLimitJson = FClaudeRateLimitJson) Then
    Exit;
  FClaudeRateLimitJson := RateLimitJson;
  If Not ParseClaudeAccountUsage(RateLimitJson, FActiveConnectionId, Item, ErrorText) Then
    Exit;
  If Assigned(FAccountUsageSlot) Then
    FAccountUsageSlot.StoreResult(Item, True);
  ApplyAccountUsageLabel;
End;

Procedure TProjectAssistantForm.NoteClaudeKeySource(Const KeySource: String);
Begin
  { Checked once per session before the first turn, then trusted. This line is the evidence if that changes. }
  If (KeySource <> '') And (KeySource <> 'none') Then
    WorkflowLogger.Warning('ProjectAssistant', 'Claude Code reported billing source ' + KeySource +
      ' instead of the Claude subscription.');
End;

{ True for a successful Claude Code file edit whose path ends with the active plan's relative path. }
Function ClaudeStepWritesPlan(Const ToolName, InputText: String): Boolean;
Var
  PlanRel, Input: String;
Begin
  Result := False;
  If SameText(ToolName, 'write_markdown') Or SameText(ToolName, 'update_markdown') Or
    (ToolName = 'mcp__lazarus__write_markdown') Or (ToolName = 'mcp__lazarus__update_markdown') Then
    Exit(True);
  If Not (SameText(ToolName, 'Edit') Or SameText(ToolName, 'Write') Or SameText(ToolName, 'MultiEdit')) Then
    Exit;
  PlanRel := StringReplace(GetActivePlanRelativePath, '\', '/', [rfReplaceAll]);
  If PlanRel = '' Then
    Exit;
  Input := StringReplace(StringReplace(InputText, '\/', '/', [rfReplaceAll]), '\\', '/', [rfReplaceAll]);
  Result := Pos(PlanRel + '"', Input) > 0;
End;

Function TProjectAssistantForm.BeginTurnEventsFile: String;
Var
  Root: String;
Begin
  Root := '';
  If Assigned(ProjectAssistantConversation) Then
    Root := ProjectAssistantConversation.ProjectRoot;
  If Root = '' Then
    Root := ProjectAssistantRoot;
  Result := CreateAssistantEventsFilePath(Root);
  FTurnEventsFile := Result;
End;

Procedure TProjectAssistantForm.ApplyTurnEvents(Const Events: TAssistantEventArray);
Var
  I: Integer;
  Event: TAssistantEvent;
  Block: TTraceBlock;
  ImagesJson: String;
Begin
  If (Length(Events) = 0) Or (Not Assigned(FTrace)) Or (Not FSending) Then
    Exit;
  For I := 0 To High(Events) Do
    Begin
      Event := Events[I];
      If (Event.Kind = aekToolCompleted) And Event.Ok And
        (SameText(Event.ToolName, 'write_markdown') Or SameText(Event.ToolName, 'update_markdown')) Then
        FPlanWriteThisTurn := True;
      If (Event.Kind = aekRecovery) And (Trim(Event.Text) <> '') Then
        Begin
          AdoptRecoverySentence(Event.Text);
          Continue;
        End;
      Case Event.Kind Of
        aekToolStarted:
          Begin
            ApplyLiveThinkingAndAnswer;
            FTrace.AddTool(Event.ToolId, Event.ToolName, Event.Text);
            FAnswerSliceStart := High(Integer);
            FThinkingSliceStart := High(Integer);
            SetStreamPhase(AssistantPhaseRunning);
          End;
        aekToolCompleted:
          Begin
            Block := FTrace.FindTool(Event.ToolId);
            If Not Assigned(Block) Then
              Block := FTrace.AddTool(Event.ToolId, Event.ToolName, '');
            Block.Running := False;
            Block.Ok := Event.Ok;
            If Event.DurationMs > 0 Then
              Block.DurationMs := Event.DurationMs;
            If Event.Text <> '' Then
              Block.Body := Event.Text;
            If Event.AttachmentsJson <> '' Then
              FTrace.AttachBlockImages(Block, Event.AttachmentsJson)
            Else If Event.Ok And SameText(Event.ToolName, 'read_image') And Assigned(FToolBroker) Then
              Begin
                ImagesJson := FToolBroker.ReadImagesJson(Event.Text);
                If ImagesJson <> '' Then
                  FTrace.AttachBlockImages(Block, ImagesJson);
              End;
            If Not Event.Ok Then
              Begin
                Block.Collapsed := False;
                If Pos('failed', LowerCase(Block.Title)) < 1 Then
                  Block.Title := Block.Title + '  failed';
              End;
            If Event.Ok And ClaudeStepWritesPlan(Event.ToolName, Block.ToolArgs) Then
              FPlanWriteThisTurn := True;
            FAnswerSliceStart := Length(FLiveContent) + 1;
            FThinkingSliceStart := Length(FLiveThinking) + 1;
            FTrace.StartThinking(0);
          End;
      Else
        { Content and phase come from the turn snapshot. }
      End;
    End;
  If FViewingLive And Assigned(FTraceView) Then
    FTraceView.Sync(FTrace, True);
  AssistantSessionObserve.TouchAssistantMirror;
End;

Procedure TProjectAssistantForm.PollTurn;
Var
  CodexRun: TAssistantCodexRun;
  ClaudeRun: TAssistantClaudeRun;
  Turn: TAssistantTurnSnapshot;
  Usage: TCodexContextUsage;
  Tool: TCodexToolRequest;
  ToolText, EvidenceError: String;
  OK: Boolean;
Begin
  If FPollingTurn Then
    Exit;
  FPollingTurn := True;
  Try
    If ToolsShouldStop Then
      Begin
        StopStream;
        Exit;
      End;
    CodexRun := FCodexRun;
    ClaudeRun := FClaudeRun;
    If Assigned(CodexRun) Then
      Begin
        If FIDEWorkspace.Identity <> FCodexIdentity Then
          Begin
            StopStream;
            Exit;
          End;
        Turn := CodexRun.TurnSnapshot;
        Usage := CodexRun.ContextUsage;
        If Usage.Reported And
          ((Not FCodexContextUsage.Reported) Or (Usage.Last.TotalTokens <> FCodexContextUsage.Last.TotalTokens) Or
           (Usage.Total.TotalTokens <> FCodexContextUsage.Total.TotalTokens) Or
           (Usage.ModelContextWindow <> FCodexContextUsage.ModelContextWindow)) Then
          Begin
            FCodexContextUsage := Usage;
            UpdateStatusFooter;
          End;
        ApplyAssistantSnapshots(Turn.Content, Turn.Thinking);
        ApplyTurnEvents(CodexRun.TakeEvents);
        If FCodexRun <> CodexRun Then
          Exit;
        CodexRun.ServiceOneTool(Tool, ToolText, OK);
        If FCodexRun <> CodexRun Then
          Exit;
        If ToolsShouldStop Then
          Begin
            StopStream;
            Exit;
          End;
        ApplyTurnEvents(CodexRun.TakeEvents);
        Turn := CodexRun.TurnSnapshot;
        If Turn.Done Then
          Begin
            If FCodexRun <> CodexRun Then
              Exit;
            If TryDeferDroppedTransport(FLiveContent, Turn.ErrorText, Turn.ErrorText) Then
              Begin
                ReleaseCodexProcess;
                Exit;
              End;
            FCompletionBuildJSON := '';
            FCompletionTestJSON := '';
            If (FBuildWorkSectionIndex >= 0) And (ActiveMode = amBuild) And (Turn.ErrorText = '') Then
              Begin
                FIDEWorkspace.BuildStatus(FCompletionBuildJSON, EvidenceError);
                If FCodexRun <> CodexRun Then
                  Exit;
                FIDEWorkspace.TestStatus(FCompletionTestJSON, EvidenceError);
                If FCodexRun <> CodexRun Then
                  Exit;
              End;
            FinishAssistantReply(Turn.ErrorText);
          End
        Else If FSending Then
          Begin
            SetStreamPhase(Turn.Phase);
            If FViewingLive And Assigned(FTraceView) And Assigned(FTrace) Then
              FTraceView.RefreshElapsed(FTrace);
          End;
        Exit;
      End;
    If Not Assigned(ClaudeRun) Then
      Exit;
    If (FClaudeConnectionId <> '') And (FActiveConnectionId <> FClaudeConnectionId) Then
      Begin
        StopStream;
        Exit;
      End;
    If (FClaudeDirectory <> '') And (ClaudeWorkDirectory <> FClaudeDirectory) Then
      Begin
        StopStream;
        Exit;
      End;
    Turn := ClaudeRun.TurnSnapshot;
    If FClaudeRun <> ClaudeRun Then
      Exit;
    If (Turn.Content <> '') Or (Turn.Thinking <> '') Then
      ApplyAssistantSnapshots(Turn.Content, Turn.Thinking);
    ApplyTurnEvents(ClaudeRun.TakeEvents);
    If FSending And (Turn.Phase = AssistantPhaseRunning) Then
      SetStreamPhase(AssistantPhaseRunning);
    If (Turn.Usage.ContextTokens > 0) And (Turn.Usage.ContextTokens < High(Integer)) Then
      FContextUsed := Turn.Usage.ContextTokens;
    ApplyClaudeRateLimit(Turn.Usage.RateLimitJson);
    If Turn.Done Then
      Begin
        If FClaudeRun <> ClaudeRun Then
          Exit;
        NoteClaudeKeySource(ClaudeRun.KeySource);
        FClaudeUsageReported := Turn.Usage.Reported;
        FClaudeInputTokens := Turn.Usage.InputTokens;
        FClaudeOutputTokens := Turn.Usage.OutputTokens;
        FClaudeCachedInputTokens := Turn.Usage.CachedInputTokens;
        FClaudeHasCached := Turn.Usage.HasCached;
        If AssistantMayReplayTurn(Turn.ReplaySafe) And ClaudeSessionMissing(Turn.ErrorText) And
          (Not FClaudeFreshRetried) Then
          Begin
            FClaudeFreshRetried := True;
            FClaudeSessionId := NewClaudeSessionId;
            FClaudeResume := False;
            If FClaudePlanItem.Active Then
              Begin
                FClaudePlanItem.Resume := False;
                FClaudePlanItem.SessionId := FClaudeSessionId;
                FClaudeLaunchPrompt := FClaudeSubmitText;
                If Assigned(FTrace) Then
                  FTrace.AddNote(ClaudePlanItemSessionNote(FBuildWorkSectionTitle, FClaudeSessionId, False));
              End
            Else
              FClaudeLaunchPrompt := ClaudeRecapPrompt(FClaudeSubmitText);
            ReleaseClaudeProcess;
            If Not LaunchStoredClaudeRun Then
              FinishAssistantReply('The run could not be restarted.');
            Exit;
          End;
        If (FClaudeRetries < AssistantFaultRetryCap(-1)) And
          TryDeferDroppedTransport(FLiveContent, Turn.ErrorText, Turn.ErrorText) Then
          Begin
            Inc(FClaudeRetries);
            If Not FClaudeResume Then
              Begin
                FClaudeSessionId := NewClaudeSessionId;
                If FClaudePlanItem.Active Then
                  FClaudePlanItem.SessionId := FClaudeSessionId;
              End;
            ReleaseClaudeProcess;
            Exit;
          End;
        FinishAssistantReply(Turn.ErrorText);
        If Turn.ErrorText = '' Then
          FClaudeSessionKey := ClaudeSessionKey
        Else If (Not FClaudeResume) And (Not (FClaudePlanItem.Active And (Not Turn.ReplaySafe))) Then
          FClaudeSessionId := '';
        ReleaseClaudePlanItemSession(FClaudePlanItem, FClaudeSessionId, FClaudeSessionKey);
      End
    Else If FSending And (FStatusPhase = '') Then
      SetStreamPhase(AssistantPhaseWaiting);
    If FViewingLive And Assigned(FTraceView) And Assigned(FTrace) And FSending Then
      FTraceView.RefreshElapsed(FTrace);
  Finally
    FPollingTurn := False;
  End;
End;

Procedure TProjectAssistantForm.ElapsedTimerTimer(Sender: TObject);
Begin
  Try
    If csDestroying In ComponentState Then Exit;
      If FTransportWait And (Not Assigned(FCodexRun)) And (Not Assigned(FClaudeRun)) Then
        Begin
          If FSending And (FStatusPhase <> '') Then
            StatusFooter.SetRightActivityText(FormatElapsedStatus(AssistantProgressPhase(FStatusPhase)),
              StatusActivityReserve(AssistantProgressPhase(FStatusPhase)));
          PollTransportWait;
          Exit;
        End;
      If FSending And (FStatusPhase <> '') Then
        StatusFooter.SetRightActivityText(FormatElapsedStatus(AssistantProgressPhase(FStatusPhase)),
          StatusActivityReserve(AssistantProgressPhase(FStatusPhase)));
      If AssistantIdeToolBusy Then
        Exit;
      If Assigned(FCodexRun) Or Assigned(FClaudeRun) Then
        Begin
          PollTurn;
          Exit;
        End;
      If FSending And Assigned(FTraceView) And Assigned(FTrace) And FViewingLive Then
        FTraceView.RefreshElapsed(FTrace);
      If FSending And Assigned(AssistantClient) Then
        Begin
          AssistantClient.AbandonTimedOutSubagents;
          ReapAbandonedAssistantWorkers;
          If Assigned(FTrace) And FViewingLive And
            FTrace.HasRunningSubagentOlderThan(MaxSubagentRuntimeMs + 15000) Then
            StopStream;
        End;
    Except
      On E: Exception Do
        Begin
          If Assigned(ElapsedTimer) Then ElapsedTimer.Enabled := False;
          ClassifyFormFault(Self, afoPaintLayout, 'TProjectAssistantForm.ElapsedTimerTimer', E, False);
        End;
  End;
End;

Procedure TProjectAssistantForm.RefreshFromConfig;
Begin
  If Assigned(AssistantChatConfig) And Assigned(AssistantClient) Then
    Begin
      AssistantClient.ApplyConfig(AssistantChatConfig);
      If FPlanAgentRunning Then
        AssistantClient.ReasoningEffort := PlanRunTurnEffort(True, AssistantClient.ReasoningEffort,
          AssistantChatConfig.PlanRunEffort);
      FModelName := AssistantChatConfig.Model;
    End
  Else If Assigned(AssistantClient) Then
    FModelName := AssistantClient.Model;
  If (FActiveBackend = 'codex') Then FModelName := 'ChatGPT / ' + FCodexModel;
  If (FActiveBackend = 'claude') Then FModelName := 'Claude / ' + FClaudeModel;
  ApplyDisplayPreferences;
  UpdateStatusFooter;
End;

Function TProjectAssistantForm.AutoCompactAtLimitEnabled: Boolean;
Begin
  Result := FCanCompactContext And Assigned(AssistantChatConfig) And AssistantChatConfig.AutoCompactContext;
End;

Function TProjectAssistantForm.CompactOpenChat: Integer;
Begin
  Result := 0;
  If Not Assigned(AssistantClient) Then
    Exit;
  Result := AssistantClient.CompactOlderHistory;
  FContextUsed := AssistantClient.EstimatedPromptTokens;
  If Result < 1 Then
    SetCurrentSystemNote('Context is already compact enough for the current budget.')
  Else
    SetCurrentSystemNote(Format('Compacted context — about %d tokens removed. Re-read files if an older turn was trimmed.',
      [Result]));
End;

Function ConversationTextSize: Integer;
Begin
  Result := 10;
  If Assigned(AssistantChatConfig) And (AssistantChatConfig.ConversationFontSize > 0) Then
    Exit(AssistantChatConfig.ConversationFontSize);
  If IDEEditorTextSize > 0 Then
    Result := IDEEditorTextSize;
End;

Procedure TProjectAssistantForm.ApplyConversationFont;
Var
  TextSize: Integer;
Begin
  If Not Assigned(FTraceView) Or Not Assigned(FTraceView.Surface) Then
    Exit;
  TextSize := ConversationTextSize;
  If TextSize < 1 Then
    TextSize := 10;
  If FTraceView.Surface.Font.Size <> TextSize Then
    FTraceView.Surface.Font.Size := TextSize;
End;

Procedure TProjectAssistantForm.HookEditorFont;
Begin
  If FEditorFontHooked Or Not Assigned(SourceEditorManagerIntf) Then
    Exit;
  Try
    SourceEditorManagerIntf.RegisterChangeEvent(semEditorOptsChanged, @EditorOptionsChanged);
    FEditorFontHooked := True;
  Except
    On E: Exception Do
      WorkflowLogger.Warning('ProjectAssistant', 'HookEditorFont: ' + E.Message);
  End;
End;

Procedure TProjectAssistantForm.UnhookEditorFont;
Begin
  If Not FEditorFontHooked Then
    Exit;
  FEditorFontHooked := False;
  If Not Assigned(SourceEditorManagerIntf) Then
    Exit;
  Try
    SourceEditorManagerIntf.UnRegisterChangeEvent(semEditorOptsChanged, @EditorOptionsChanged);
  Except
    On E: Exception Do
      WorkflowLogger.Warning('ProjectAssistant', 'UnhookEditorFont: ' + E.Message);
  End;
End;

Procedure TProjectAssistantForm.EditorOptionsChanged(Sender: TObject);
Begin
  ApplyConversationFont;
End;

Procedure TProjectAssistantForm.ApplyDisplayPreferences;
Var
  ShowThinking, ShowTools: Boolean;
Begin
  ApplyConversationFont;
  ShowThinking := True;
  ShowTools := True;
  If Assigned(AssistantChatConfig) Then
    Begin
      ShowThinking := AssistantChatConfig.ShowThinking;
      ShowTools := AssistantChatConfig.ShowToolCalls;
    End;
  If (FShowThinking = ShowThinking) And (FShowToolUse = ShowTools) Then
    Begin
      If Assigned(FTraceView) Then
        Begin
          FTraceView.ShowThinking := FShowThinking;
          FTraceView.ShowToolUse := FShowToolUse;
        End;
      Exit;
    End;
  FShowThinking := ShowThinking;
  FShowToolUse := ShowTools;
  If Assigned(FTraceView) Then
    Begin
      FTraceView.ShowThinking := FShowThinking;
      FTraceView.ShowToolUse := FShowToolUse;
      RefreshChatDisplay(True, False);
    End;
End;


Procedure TProjectAssistantForm.RefreshCentreStatus;
Begin
  Seam_RefreshCentreStatus(Self);
End;

Procedure TProjectAssistantForm.ApplyAccountUsageLabel;
Begin
  Seam_ApplyAccountUsageLabel(Self);
End;

Procedure TProjectAssistantForm.SyncCodexUsageIdle;
Begin
  Seam_SyncCodexUsageIdle(Self);
End;

Procedure TProjectAssistantForm.NoteAccountConnectionChanged;
Begin
  Seam_NoteAccountConnectionChanged(Self);
End;

Procedure TProjectAssistantForm.StartAccountUsageWorker;
Begin
  Seam_StartAccountUsageWorker(Self);
End;

Procedure TProjectAssistantForm.AccountUsageTimerTimer(Sender: TObject);
Begin
  Seam_AccountUsageTimerTimer(Self, Sender);
End;

Procedure TProjectAssistantForm.ReleaseAccountUsageRefresh;
Begin
  Seam_ReleaseAccountUsageRefresh(Self);
End;

Function EffortBarCaption(Const Value: String): String;
Var
  Level: String;
Begin
  Level := LowerCase(Trim(Value));
  If Level = '' Then
    Result := 'Default'
  Else If Level = 'low' Then
    Result := 'Low'
  Else If Level = 'medium' Then
    Result := 'Medium'
  Else If Level = 'high' Then
    Result := 'High'
  Else If (Level = 'xhigh') Or (Level = 'extrahigh') Then
    Result := 'XHigh'
  Else
    Result := Value;
End;

Procedure TProjectAssistantForm.UpdateStatusFooter;
Var
  Pct: Integer;
  StatusText, CentreText, ModelText, EffortText, PermissionText, ModelHint, EffortHint, BlockReason: String;
Begin
  If (FActiveBackend <> 'codex') And (FActiveBackend <> 'claude') And Assigned(AssistantClient) And (Not FSending) Then
    Begin
      FContextUsed := AssistantClient.EstimatedPromptTokens;
      If AssistantClient.MaxPromptTokens > 0 Then
        FContextLimit := AssistantClient.MaxPromptTokens;
    End;
  If FContextLimit > 0 Then
    Pct := (FContextUsed * 100) Div FContextLimit
  Else
    Pct := 0;
  If Pct > 999 Then
    Pct := 999;
  If FSending Then
    Begin
      If FStatusPhase = '' Then
        FStatusPhase := AssistantPhaseWaiting;
      StatusText := FormatElapsedStatus(AssistantProgressPhase(FStatusPhase));
    End
  Else If ((FActiveBackend = 'codex') And (FCodexRuntime <> '') And (FCodexModel <> '')) Or
    ((FActiveBackend = 'claude') And (FClaudeRuntime <> '') And (FClaudeModel <> '')) Or
    ((FActiveBackend <> 'codex') And (FActiveBackend <> 'claude') And Assigned(AssistantChatConfig) And AssistantChatConfig.IsSignedIn) Then
    StatusText := AssistantStatusReady + PlanRunElapsedSuffix { Between plan items the run total stays in view. }
  Else
    StatusText := AssistantStatusOffline;
  ModelText := Trim(FActiveModel);
  If ModelText = '' Then
    ModelText := Trim(FModelName);
  If ModelText = '' Then
    ModelText := 'Model';
  If AssistantShowsEffort(FActiveBackend) Then
    Begin
      EffortText := EffortBarCaption(FActiveEffort);
      EffortHint := 'Click to choose an effort level';
    End
  Else
    Begin
      EffortText := '—';
      EffortHint := 'This connection does not set an effort level';
    End;
  PermissionText := ApprovalModeCaption(StrToApprovalMode(FActiveApproval));
  CentreText := Format('Context %d%%', [Pct]);
  If Pct >= 95 Then
    CentreText := CentreText + ' ⚠';
  If (FActiveBackend = 'codex') Then
    CentreText := CodexContextCaption(FCodexContextUsage, FContextUsed)
  Else If (FActiveBackend = 'claude') Then
    CentreText := Format('Context ~%d tokens', [FContextUsed]);
  ApplyModelStatus;
  StatusFooter.SetModelText(ModelText);
  StatusFooter.SetEffortText(EffortText);
  StatusFooter.SetPermissionsText(PermissionText);
  FContextStatusText := CentreText;
  ApplyAccountUsageLabel;
  If FSending Then
    StatusFooter.SetRightActivityText(StatusText, StatusActivityReserve(AssistantProgressPhase(FStatusPhase)))
  Else
    StatusFooter.SetRightText(StatusText);
  StatusFooter.SetLeftHint('');
  ModelHint := 'Click to choose a model';
  If Not ComposerAttachAllowed(BlockReason) And (BlockReason <> '') Then
    ModelHint := ModelHint + '. ' + BlockReason;
  StatusFooter.SetModelHint(ModelHint);
  StatusFooter.SetEffortHint(EffortHint);
  StatusFooter.SetPermissionsHint('Click to choose permissions');
  FContextStatusHint := Format('About %d of %d tokens. Click for a breakdown.', [FContextUsed, FContextLimit]);
  StatusFooter.SetRightHint('Click for session info');
  { A disabled Send hint is the refusal. Do not wipe it on a footer refresh. }
  If Assigned(SendAction) And SendAction.Enabled Then
    SendAction.Hint := '';
  RefreshAttachAction;
  If (FActiveBackend = 'codex') Then
    FContextStatusHint := CodexContextDetails(FCodexContextUsage, FContextUsed) + LineEnding + 'Click for details.'
  Else If (FActiveBackend = 'claude') Then
    FContextStatusHint := 'Estimated context. Click for the estimate. Provider allowance is on Credits.';
  RefreshCentreStatus;
  ApplySkillStatus;
  If (FActiveBackend <> 'codex') And (FActiveBackend <> 'claude') And (Not FSending) And (Pct >= PlanContextThreshold) Then
    MaybeWarnHighContextUsage;
  AssistantSessionObserve.AssistantSessionObserve(asnStatus);
End;

Procedure TProjectAssistantForm.MaybeWarnHighContextUsage;
Var
  Pct: Integer;
Begin
  If FContextWarnShown Or FAutoRolloverInProgress Then
    Exit;
  If FContextLimit <= 0 Then
    Exit;
  Pct := (FContextUsed * 100) Div FContextLimit;
  If Pct < PlanContextThreshold Then
    Exit;
  FContextWarnShown := True;
  { Compact first. A plan that continues in a new chat must not also raise the warning dialog. }
  If Assigned(AssistantChatConfig) And AssistantChatConfig.AutoCompactContext Then
    Begin
      If Not FCanCompactContext Then
        Exit;
      FAutoRolloverInProgress := True;
      Try
        CompactOpenChat;
        UpdateStatusFooter;
        WorkflowLogger.Info('ProjectAssistant',
          Format('Auto compact at %d%% context', [Pct]));
      Finally
        FAutoRolloverInProgress := False;
      End;
      Exit;
    End;
  If FPlanAgentRunning And Assigned(AssistantChatConfig) And AssistantChatConfig.AutoNewChatAtContextLimit Then
    Exit;
  SetCurrentSystemNote(
    Format('**Context usage is high (%d%%).** Start a **New Chat** before continuing long Build/Plan work ' +
      'so the model stays within its token limit.',
      [Pct]));
  RunAssistantModal(
    Format('Context usage is at about %d%% of the budget.%s%s' +
      'Start a New Chat before continuing large Plan/Build sessions.',
      [Pct, LineEnding, LineEnding]),
    mtWarning, [mbOK], 0);
End;

Procedure TProjectAssistantForm.SetSending(IsSending: Boolean);
Var
  WasSending: Boolean;
Begin
  WasSending := FSending;
  If (FActiveBackend <> 'codex') And IsSending And (Not FSending) Then
    AssistantBeginQuietIdeSession
  Else If (FActiveBackend <> 'codex') And (Not IsSending) And FSending Then
    AssistantEndQuietIdeSession;
  FSending := IsSending;
  If WasSending And (Not IsSending) Then
    FAccountUsageWanted := AccountUsageRegistered(FActiveBackend);
  SyncCodexUsageIdle;
  If Assigned(TargetCombo) Then TargetCombo.Enabled := Not IsSending;
  If Assigned(TargetBrowseButton) Then TargetBrowseButton.Enabled := Not IsSending;
  If IsSending And (Not WasSending) Then
    Begin
      ClearAssistantToolStop;
      FPlanNewChatThisStep := False;
      If FPlanAgentRunning Then
        MarkPlanAgentAlive;
      FContinuationCap := AssistantAutomaticContinuationCap;
      FReconnectIntervalMs := AssistantReconnectIntervalMs;
      FCreditIntervalMs := AssistantCreditIntervalMs;
      FContinuationCount := 0;
      FHeldAnswer := '';
      FHoldingContinuation := False;
    End;
  If IsSending Then
    Begin
      FPlanWriteThisTurn := False;
      ResetAssistantGitTurn;
      ResetAssistantPlanTurn;
    End;
  If Not IsSending Then
    Begin
      FReviewInProgress := False;
      FHoldingContinuation := False;
      FHeldAnswer := '';
    End;
  { Absent steer stays Send and disabled until the turn ends. Steer is the capability, not the running state. }
  If IsSending And AssistantCanSteer(FActiveBackend) Then
    SendAction.Caption := 'Steer'
  Else
    SendAction.Caption := 'Send';
  If IsSending Then
    SendAction.Enabled := AssistantCanSteer(FActiveBackend)
  Else
    SendAction.Enabled := TurnEngineReady;
  If SendAction.Enabled Then
    SendAction.Hint := ''
  Else If IsSending Then
    SendAction.Hint := AssistantCapabilitySentence(FActiveBackend, acSteer)
  Else
    SendAction.Hint := AssistantTurnUnavailableSentence(FActiveBackend);
  If Assigned(SendButton) Then
    SendButton.ShowHint := Not SendAction.Enabled;
  StopAction.Enabled := IsSending;
  NewConversationAction.Enabled := Not IsSending;
  UpdateWorkActions;
  { Prompt stays live so the user can Steer without aborting the turn. }
  If Assigned(InputMemo) Then
    InputMemo.ReadOnly := False;
  SetBusyCursor(IsSending);
  If IsSending Then
    Begin
      { A later SetSending must not restart the clock. That was the status lag. }
      If (Not WasSending) Or (FTurnStartTick = 0) Then
        Begin
          FTurnStartTick := GetTickCount64;
          StreamStart := Now;
        End;
      If FStatusPhase = '' Then
        FStatusPhase := AssistantPhaseWaiting;
      If Assigned(ElapsedTimer) Then
        ElapsedTimer.Enabled := True;
    End
  Else
    Begin
      If Assigned(ElapsedTimer) Then
        ElapsedTimer.Enabled := False;
      FStatusPhase := '';
      StreamStart := 0;
      FTurnStartTick := 0;
    End;
  If (Not FSending) And FReloadConnectionAfterSend Then
    Begin
      FReloadConnectionAfterSend := False;
      ReloadActiveConnection;
    End;
  ApplyActiveMode;
  UpdateHistoryActions;
  UpdateStatusFooter;
  AssistantSessionObserve.TouchAssistantMirror;
End;

Procedure TProjectAssistantForm.PersistSession;
Var
  Key: String;
Begin
  { Model messages are stored on the conversation turn. Do not write .lazgrokchat-session. }
  If FSending Then
    Exit;
  Key := AssistantTarget.Manifest;
  If Key = '' Then
    Exit;
  FSessionProjectKey := Key;
End;

Procedure TProjectAssistantForm.RestoreSessionIfNeeded;
Var
  Key: String;
Begin
  Key := AssistantTarget.Manifest;
  If Key = '' Then
    Exit;
  If SameText(Key, FSessionProjectKey) And Assigned(AssistantClient) And
    (AssistantClient.MessageCount > 0) Then
    Exit;
  FSessionProjectKey := Key;
  { Model context comes from conversation.jsonl turns, not .lazgrokchat-session. }
  RebuildClientFromConversation;
  UpdateStatusFooter;
End;

Procedure TProjectAssistantForm.DeferredBind(Data: PtrInt);
Begin
  Try
    If csDestroying In ComponentState Then
      Exit;
    If Not FOpenBindPending Then
      Begin
        If Not FDeferLastTurn Then
          SetOpenBusy(False);
        Exit;
      End;
    If Data = 0 Then
      Begin
        If HandleAllocated Then
          Begin
            Invalidate;
            Update;
          End;
        SetOpenBusy(True);
        Application.QueueAsyncCall(@DeferredBind, 1);
        Exit;
      End;
    BindToActiveProject;
  Except
    On E: Exception Do
      Begin
        FOpenBindPending := False;
        SetOpenBusy(False);
        ClassifyFormFault(Self, afoPaintLayout, 'TProjectAssistantForm.DeferredBind', E, False);
      End;
  End;
End;

Procedure TProjectAssistantForm.DeferredShowLastTurn(Data: PtrInt);
Begin
  Try
    If csDestroying In ComponentState Then
      Begin
        SetOpenBusy(False);
        Exit;
      End;
    Try
      ShowLastConversationTurn;
    Finally
      SetOpenBusy(False);
    End;
  Except
    On E: Exception Do
      Begin
        ClassifyFormFault(Self, afoPaintLayout, 'TProjectAssistantForm.DeferredShowLastTurn', E, False);
      End;
  End;
End;

Procedure TProjectAssistantForm.EnsureChatView;
Begin
  Seam_EnsureChatView(Self);
End;

Procedure TProjectAssistantForm.EnsureInputPopup;
Begin
  Seam_EnsureInputPopup(Self);
End;

Procedure TProjectAssistantForm.UpdateInputUndoItems;
Begin
  Seam_UpdateInputUndoItems(Self);
End;

Procedure TProjectAssistantForm.InputPopupPopup(Sender: TObject);
Begin
  Seam_InputPopupPopup(Self, Sender);
End;

Procedure TProjectAssistantForm.InputCutClick(Sender: TObject);
Begin
  Seam_InputCutClick(Self, Sender);
End;

Procedure TProjectAssistantForm.InputCopyClick(Sender: TObject);
Begin
  Seam_InputCopyClick(Self, Sender);
End;

Function StillImageExtension(Const Path: String): Boolean;
Var
  Ext: String;
Begin
  Ext := LowerCase(ExtractFileExt(Path));
  Result := (Ext <> '') And (Pos(Ext + ',', AssistantStillImageExtensions + ',') > 0);
End;

Function MimeLooksLikeStillImage(Const Mime: String): Boolean;
Var
  Lowered: String;
Begin
  Lowered := LowerCase(Trim(Mime));
  Result := (Copy(Lowered, 1, 6) = 'image/') And (Pos('svg', Lowered) = 0);
End;

Var
  PngClipboardReady: Boolean = False;

Procedure EnsurePngClipboardFormat;
Begin
  If PngClipboardReady Then Exit;
  { LCL registers image/bmp and image/xpm only. A screenshot is image/png. }
  TPicture.RegisterClipboardFormat(RegisterClipboardFormat('image/png'), TPortableNetworkGraphic);
  TPicture.RegisterClipboardFormat(RegisterClipboardFormat('image/x-png'), TPortableNetworkGraphic);
  PngClipboardReady := True;
End;

Function OpenClipboardReader: TClipboard;
Begin
  EnsurePngClipboardFormat;
  { TClipboard reads the widgetset unless it still owns the selection. On Qt,
    copying a picture does not drop that ownership, so the global Clipboard
    keeps returning the previous text. A second object does not own it, and
    HasFormat, GetFormat, and AsText then use the LCL widgetset path. }
  Result := TClipboard.Create(ctClipboard);
End;

Function ClipboardOffersImage(Reader: TClipboard): Boolean;
Var
  Names: TStringList;
  I: Integer;
  MimeName: String;
Begin
  Result := False;
  If Reader = Nil Then Exit;
  EnsurePngClipboardFormat;
  Result := Reader.HasPictureFormat;
  If Result Then Exit;
  Names := TStringList.Create;
  Try
    Reader.SupportedFormats(Names);
    For I := 0 To Names.Count - 1 Do
      Begin
        MimeName := Names[I];
        If MimeLooksLikeStillImage(MimeName) Or (Pos('qt-image', LowerCase(MimeName)) > 0) Then Exit(True);
      End;
  Finally
    Names.Free;
  End;
End;

Function ReadClipboardFormat(Reader: TClipboard; FormatID: TClipboardFormat; Stream: TMemoryStream): Boolean;
Begin
  Result := False;
  Stream.Clear;
  If (Reader = Nil) Or (FormatID = 0) Then Exit;
  Try
    Result := Reader.GetFormat(FormatID, Stream) And (Stream.Size > 8);
  Except
    Result := False;
    Stream.Clear;
  End;
  Stream.Position := 0;
End;

Function ClipboardImageName(Const Mime: String): String;
Var
  Lowered: String;
Begin
  Lowered := LowerCase(Mime);
  If (Pos('jpeg', Lowered) > 0) Or (Pos('jpg', Lowered) > 0) Then Result := 'Clipboard.jpg'
  Else If Pos('gif', Lowered) > 0 Then Result := 'Clipboard.gif'
  Else If Pos('tif', Lowered) > 0 Then Result := 'Clipboard.tif'
  Else If Pos('bmp', Lowered) > 0 Then Result := 'Clipboard.bmp'
  Else If Pos('xpm', Lowered) > 0 Then Result := 'Clipboard.xpm'
  Else Result := 'Clipboard.png';
End;

Function GraphicToPngStream(Graphic: TGraphic; Stream: TMemoryStream): Boolean;
Var
  Png: TPortableNetworkGraphic;
Begin
  Result := False;
  Stream.Clear;
  If (Graphic = Nil) Or (Graphic.Width < 1) Or (Graphic.Height < 1) Then Exit;
  Png := TPortableNetworkGraphic.Create;
  Try
    Png.Assign(Graphic);
    Png.SaveToStream(Stream);
    Result := Stream.Size > 0;
    Stream.Position := 0;
  Finally
    Png.Free;
  End;
End;

Function TurnReferencesImage(Const ImageId: String): Boolean;
Var
  I, J: Integer;
  Turn: TConversationTurn;
  Refs: TAssistantImageRefArray;
Begin
  Result := False;
  If (ImageId = '') Or Not Assigned(ProjectAssistantConversation) Then Exit;
  For I := 0 To ProjectAssistantConversation.TurnCount - 1 Do
    Begin
      If Not ProjectAssistantConversation.GetTurn(I, Turn) Then Continue;
      If Not ParseAssistantImageRefs(Turn.AttachmentsJson, Refs) Then Continue;
      For J := 0 To High(Refs) Do
        If Refs[J].Id = ImageId Then Exit(True);
    End;
End;

Procedure AppendComposerStored(Form: TProjectAssistantForm; Const Stored: TAssistantStoredImage);
Var
  Refs: TAssistantImageRefArray;
  N: Integer;
Begin
  ParseAssistantImageRefs(Form.FComposerImagesJson, Refs);
  N := Length(Refs);
  SetLength(Refs, N + 1);
  Refs[N] := ImageRefFromStored(Stored);
  Form.FComposerImagesJson := AssistantImageRefsToJson(Refs);
  Form.RefreshComposerImages;
End;

Procedure AssignThumbImage(Target: TImage; Const ProjectRoot: String; Const Ref: TAssistantImageRef);
Var
  Img: TFPMemoryImage;
  Writer: TFPWriterPNG;
  Png: TPortableNetworkGraphic;
  Stream: TMemoryStream;
  ErrorText: String;
Begin
  Target.Picture.Clear;
  Target.Stretch := False;
  Target.Proportional := True;
  Target.Center := True;
  If Not LoadStoredAssistantImage(ProjectRoot, Ref.DisplayPath, Img, ErrorText) Then Exit;
  Try
    If (Img.Width < 1) Or (Img.Height < 1) Then Exit;
    Target.Stretch := (Img.Width > Target.Width) Or (Img.Height > Target.Height);
    Stream := TMemoryStream.Create;
    Writer := TFPWriterPNG.Create;
    Png := TPortableNetworkGraphic.Create;
    Try
      Img.SaveToStream(Stream, Writer);
      Stream.Position := 0;
      Png.LoadFromStream(Stream);
      Target.Picture.Assign(Png);
    Finally
      Png.Free;
      Writer.Free;
      Stream.Free;
    End;
  Finally
    Img.Free;
  End;
End;

Function TProjectAssistantForm.ComposerChromeHeight: Integer;
Begin
  Result := Seam_ComposerChromeHeight(Self);
End;

Procedure TProjectAssistantForm.PlaceComposerChildren;
Begin
  Seam_PlaceComposerChildren(Self);
End;

Procedure TProjectAssistantForm.PlacePromptChildren;
Begin
  Seam_PlacePromptChildren(Self);
End;

Function ClassifyFormFault(Form: TProjectAssistantForm; Origin: TAssistantFaultOrigin; Const Area: String;
  E: Exception; OwnsTurn: Boolean): TAssistantRecoveryAction;
Var
  Fault: TAssistantFault;
Begin
  Result := araIgnore;
  If Not Assigned(Form) Then
    Exit;
  If Assigned(E) Then
    ReportPluginException(Area, E);
  Fault := DefaultAssistantFault;
  Fault.Origin := Origin;
  Fault.Area := Area;
  Fault.OwnsTurn := OwnsTurn;
  Fault.UserStopped := Form.FUserCancelled;
  Fault.Detached := csDestroying In Form.ComponentState;
  If Fault.Detached Then
    Fault.Origin := afoCallbackAfterDetach;
  If Assigned(E) Then
    Begin
      Fault.ErrorClass := E.ClassName;
      Fault.ErrorText := E.Message;
    End;
  Result := ClassifyAssistantFault(Fault).Action;
  { Paint and detach ignores continue. Do not note a destroying form, and do not note on a poll repeat. }
  If (Result In [araIgnore, araRetryLastAction, araContinueTurn]) And Assigned(Form) And
    (Not Fault.Detached) And (Not (csDestroying In Form.ComponentState)) And
    (Fault.Origin In [afoPaintLayout, afoCallbackAfterDetach]) Then
    Form.NoteRecovery(Result, Fault);
End;

Procedure TProjectAssistantForm.LayoutComposer;
Begin
  Seam_LayoutComposer(Self);
End;

Procedure TProjectAssistantForm.StatusFooterResize(Sender: TObject);
Begin
  Seam_StatusFooterResize(Self, Sender);
End;

Procedure TProjectAssistantForm.ComposerStackResize(Sender: TObject);
Begin
  Seam_ComposerStackResize(Self, Sender);
End;

Procedure TProjectAssistantForm.PromptHostResize(Sender: TObject);
Begin
  Seam_PromptHostResize(Self, Sender);
End;

Procedure TProjectAssistantForm.ApplyInputPanelHeight;
Begin
  Seam_ApplyInputPanelHeight(Self);
End;

Procedure TProjectAssistantForm.RefreshAttachAction;
Begin
  Seam_RefreshAttachAction(Self);
End;

Function TProjectAssistantForm.ComposerAttachAllowed(Out Reason: String): Boolean;
Begin
  Result := Seam_ComposerAttachAllowed(Self, Reason);
End;

Function TProjectAssistantForm.ComposerStoreReady(Out Root, StoreDir, ErrorText: String): Boolean;
Begin
  Result := Seam_ComposerStoreReady(Self, Root, StoreDir, ErrorText);
End;

Function TProjectAssistantForm.AttachImageStream(Const OriginalName: String; Stream: TStream; Out ErrorText: String): Boolean;
Begin
  Result := Seam_AttachImageStream(Self, OriginalName, Stream, ErrorText);
End;

Function TProjectAssistantForm.AttachImageFile(Const SourcePath: String; Out ErrorText: String): Boolean;
Begin
  Result := Seam_AttachImageFile(Self, SourcePath, ErrorText);
End;

Function ComposerImageHint(Const OriginalName: String): String;
Var
  FileName, Stem: String;
Begin
  FileName := Trim(OriginalName);
  FileName := StringReplace(FileName, '\', '/', [rfReplaceAll]);
  FileName := Trim(ExtractFileName(FileName));
  Stem := ChangeFileExt(FileName, '');
  If SameText(Stem, 'Clipboard') Then
    Result := 'Clipboard'
  Else If FileName <> '' Then
    Result := FileName
  Else
    Result := 'Image';
End;

Function ComposerSaveFilterIndex(Const FileName: String): Integer;
Var
  Ext: String;
Begin
  Ext := LowerCase(ExtractFileExt(FileName));
  If (Ext = '.jpg') Or (Ext = '.jpeg') Then Result := 2
  Else If Ext = '.gif' Then Result := 3
  Else If Ext = '.bmp' Then Result := 4
  Else If (Ext = '.tif') Or (Ext = '.tiff') Then Result := 5
  Else If Ext = '.xpm' Then Result := 6
  Else If (Ext = '.pbm') Or (Ext = '.pgm') Or (Ext = '.ppm') Then Result := 7
  Else If Ext = '.ico' Then Result := 8
  Else Result := 1;
End;

Function TProjectAssistantForm.AttachmentStripHeight: Integer;
Begin
  Result := Seam_AttachmentStripHeight(Self);
End;

Procedure TProjectAssistantForm.PlaceComposerThumbnails;
Begin
  Seam_PlaceComposerThumbnails(Self);
End;

Procedure TProjectAssistantForm.ApplyComposerImageSelection;
Begin
  Seam_ApplyComposerImageSelection(Self);
End;

Procedure TProjectAssistantForm.SelectComposerImage(Index: Integer);
Begin
  Seam_SelectComposerImage(Self, Index);
End;

Function TProjectAssistantForm.ComposerImageIndexUnder(Const ScreenPoint: TPoint): Integer;
Begin
  Result := Seam_ComposerImageIndexUnder(Self, ScreenPoint);
End;

Function ComposerRefAt(Form: TProjectAssistantForm; Index: Integer; Out Ref: TAssistantImageRef): Boolean;
Var
  Refs: TAssistantImageRefArray;
Begin
  Result := False;
  Ref := Default(TAssistantImageRef);
  If Not Assigned(Form) Then Exit;
  ParseAssistantImageRefs(Form.FComposerImagesJson, Refs);
  If (Index < 0) Or (Index > High(Refs)) Then Exit;
  Ref := Refs[Index];
  Result := True;
End;

Procedure TProjectAssistantForm.RefreshComposerImages;
Begin
  Seam_RefreshComposerImages(Self);
End;

Procedure TProjectAssistantForm.ClearUnsentComposerImages;
Begin
  Seam_ClearUnsentComposerImages(Self);
End;

Procedure TProjectAssistantForm.RemoveComposerImageAt(Index: Integer);
Begin
  Seam_RemoveComposerImageAt(Self, Index);
End;

Procedure TProjectAssistantForm.SaveComposerImage(Index: Integer);
Begin
  Seam_SaveComposerImage(Self, Index);
End;

Procedure TProjectAssistantForm.PreviewComposerImage(Index: Integer);
Begin
  Seam_PreviewComposerImage(Self, Index);
End;

Procedure TProjectAssistantForm.AttachmentPopupPopup(Sender: TObject);
Begin
  Seam_AttachmentPopupPopup(Self, Sender);
End;

Procedure TProjectAssistantForm.RemoveAttachmentActionExecute(Sender: TObject);
Begin
  Seam_RemoveAttachmentActionExecute(Self, Sender);
End;

Procedure TProjectAssistantForm.SaveAttachmentActionExecute(Sender: TObject);
Begin
  Seam_SaveAttachmentActionExecute(Self, Sender);
End;

Procedure TProjectAssistantForm.PreviewAttachmentActionExecute(Sender: TObject);
Begin
  Seam_PreviewAttachmentActionExecute(Self, Sender);
End;

Procedure TProjectAssistantForm.AttachmentImageMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
Begin
  Seam_AttachmentImageMouseDown(Self, Sender, Button, Shift, X, Y);
End;

Procedure TProjectAssistantForm.AttachmentImageDblClick(Sender: TObject);
Begin
  Seam_AttachmentImageDblClick(Self, Sender);
End;

Procedure TProjectAssistantForm.AttachImageActionExecute(Sender: TObject);
Begin
  Seam_AttachImageActionExecute(Self, Sender);
End;

Function PercentDecode(Const Text: String): String;
Var
  I, Code, N, Value: Integer;
  Bytes: Array Of Byte;
Begin
  SetLength(Bytes, Length(Text));
  N := 0;
  I := 1;
  While I <= Length(Text) Do
    Begin
      If (Text[I] = '%') And (I + 2 <= Length(Text)) Then
        Begin
          Val('$' + Copy(Text, I + 1, 2), Value, Code);
          If (Code = 0) And (Value >= 0) And (Value <= 255) Then
            Begin
              Bytes[N] := Byte(Value);
              Inc(N);
              Inc(I, 3);
              Continue;
            End;
        End;
      Bytes[N] := Ord(Text[I]);
      Inc(N);
      Inc(I);
    End;
  SetLength(Result, N);
  If N > 0 Then Move(Bytes[0], Result[1], N);
End;

Function DroppedLocalPath(Const Name: String): String;
Var
  QueryAt: Integer;
Begin
  Result := Trim(Name);
  If Copy(LowerCase(Result), 1, 7) <> 'file://' Then Exit;
  Delete(Result, 1, 7);
  If Copy(LowerCase(Result), 1, 9) = 'localhost' Then Delete(Result, 1, 9);
  QueryAt := Pos('?', Result);
  If QueryAt > 0 Then Result := Copy(Result, 1, QueryAt - 1);
  Result := PercentDecode(Result);
  If (Result <> '') And (Result[1] <> '/') Then Result := '/' + Result;
End;

Procedure TProjectAssistantForm.InputPanelDropFiles(Sender: TObject; Const FileNames: Array Of String);
Begin
  Seam_InputPanelDropFiles(Self, Sender, FileNames);
End;

Function TProjectAssistantForm.TryAttachClipboardImage(Reader: TClipboard; Out ErrorText: String): Boolean;
Begin
  Result := Seam_TryAttachClipboardImage(Self, Reader, ErrorText);
End;

Function ClipboardTextIsImageFile(Const Text: String; Out LocalPath: String): Boolean;
Begin
  LocalPath := DroppedLocalPath(Trim(Text));
  Result := (Pos(#10, Text) = 0) And (Pos(#13, Text) = 0) And StillImageExtension(LocalPath) And
    FileExistsUTF8(LocalPath);
End;

Procedure TProjectAssistantForm.PasteComposer;
Begin
  Seam_PasteComposer(Self);
End;

Procedure TProjectAssistantForm.QueueComposerPaste;
Begin
  Seam_QueueComposerPaste(Self);
End;

Procedure TProjectAssistantForm.InputPasteClick(Sender: TObject);
Begin
  Seam_InputPasteClick(Self, Sender);
End;

Procedure TProjectAssistantForm.InputMemoPaste(Sender: TObject);
Begin
  Seam_InputMemoPaste(Self, Sender);
End;

Procedure TProjectAssistantForm.InputSelectAllClick(Sender: TObject);
Begin
  Seam_InputSelectAllClick(Self, Sender);
End;

Procedure TProjectAssistantForm.InputUndoClick(Sender: TObject);
Begin
  Seam_InputUndoClick(Self, Sender);
End;

Procedure TProjectAssistantForm.InputRedoClick(Sender: TObject);
Begin
  Seam_InputRedoClick(Self, Sender);
End;

Procedure TProjectAssistantForm.InputMemoChange(Sender: TObject);
Begin
  Seam_InputMemoChange(Self, Sender);
End;

Procedure TProjectAssistantForm.ApplyLiveThinkingAndAnswer;
Var
  Block: TTraceBlock;
  Slice: String;
Begin
  If Not Assigned(FTrace) Then
    Exit;
  If FLiveUser <> '' Then
    FTrace.EnsureUser(FLiveUser)
  Else If FDisplayUser <> '' Then
    FTrace.EnsureUser(FDisplayUser);
  If FThinkingSliceStart < 1 Then
    FThinkingSliceStart := 1;
  If Length(FLiveThinking) >= FThinkingSliceStart Then
    Slice := Copy(FLiveThinking, FThinkingSliceStart, MaxInt)
  Else
    Slice := '';
  { One thinking card per sample. After a tool the last card is the tool, so do
    not open a new thought from the cumulative snapshot — wait for LoopStarted. }
  Block := FTrace.CurrentRunningThinking;
  If Not Assigned(Block) Then
    Block := FTrace.LatestBlockSinceLastTool(tbkThinking);
  If Assigned(Block) And (Slice <> '') Then
    Block.Body := Slice;
  ApplyLiveAnswerSlice;
  AssistantSessionObserve.TouchAssistantMirror;
End;

Procedure TProjectAssistantForm.ApplyLiveAnswerSlice;
Var
  Block: TTraceBlock;
  Slice: String;
Begin
  If Not Assigned(FTrace) Then
    Exit;
  Slice := SliceLiveChannel(FLiveContent, FAnswerSliceStart);
  If (Slice = '') Or (Not SliceLooksLikeAnswer(Slice)) Then
    Exit;
  { A build-work note at the live head must not freeze the answer already on screen. }
  Block := FTrace.LatestBlockSinceLastTool(tbkAnswer);
  If Assigned(Block) Then
    Block.Body := Slice
  Else
    FTrace.EnsureAnswer.Body := Slice;
End;

Procedure TProjectAssistantForm.HandleTraceEvent(Const Event: TAssistantEvent);
Var
  Block: TTraceBlock;
Begin
  If csDestroying In ComponentState Then Exit;
  Try
  If (Event.Kind = aekToolCompleted) And Event.Ok Then
    If SameText(Event.ToolName, 'write_markdown') Or SameText(Event.ToolName, 'update_markdown') Then
      FPlanWriteThisTurn := True;
  If (Event.Kind = aekTurnEnded) And (Pos('plan_write', Event.Text) > 0) Then
    FPlanWriteThisTurn := True;
  { One note per recovery event, including when the pane is not showing the live turn. }
  If (Event.Kind = aekRecovery) And (Trim(Event.Text) <> '') Then
    Begin
      AdoptRecoverySentence(Event.Text);
      Exit;
    End;
  If Not FViewingLive Then
    Exit;
  If Not Assigned(FTrace) Then
    Exit;
  Try
    Case Event.Kind Of
    aekLoopStarted:
      Begin
        { A new HTTP sample. Close the previous thinking/answer and open a new thought. }
        FTrace.FinishCurrentThinking;
        FTrace.FinishCurrentAnswer;
        FAnswerSliceStart := 1;
        FThinkingSliceStart := Length(FLiveThinking) + 1;
        FTrace.StartThinking(Event.LoopIndex);
      End;
    aekToolStarted:
      Begin
        FTrace.AddTool(Event.ToolId, Event.ToolName, Event.Text);
        { Ignore further snapshots of this loop, including a trailing ".".
          Length+1 is not enough: one more delta would open a new answer card.
          Freeze thinking too — the actor still sends the full CoT on each tool. }
        FAnswerSliceStart := High(Integer);
        FThinkingSliceStart := High(Integer);
      End;
    aekToolCompleted:
      Begin
        Block := FTrace.FindTool(Event.ToolId);
        If Not Assigned(Block) Then
          Block := FTrace.AddTool(Event.ToolId, Event.ToolName, '');
        Block.Running := False;
        Block.Ok := Event.Ok;
        If Event.DurationMs > 0 Then
          Block.DurationMs := Event.DurationMs;
        If Event.Text <> '' Then
          Block.Body := Event.Text;
        If Event.AttachmentsJson <> '' Then
          FTrace.AttachBlockImages(Block, Event.AttachmentsJson);
        If Not Event.Ok Then
          Begin
            Block.Collapsed := False;
            If Pos('failed', LowerCase(Block.Title)) < 1 Then
              Block.Title := Block.Title + '  failed';
          End;
      End;
    aekSubagentStarted:
      Begin
        FTrace.FinishCurrentThinking;
        Block := FTrace.AddSubagent(Event.ToolId, Event.ToolName, Event.Text);
        Block.Running := True;
        Block.Ok := Event.Ok;
        Block.Title := SubagentRunningTitle(SubagentKindCaption(ParseSubagentKind(Event.ToolName)),
          'Starting');
        FAnswerSliceStart := High(Integer);
        FThinkingSliceStart := High(Integer);
      End;
    aekSubagentProgress:
      Begin
        Block := FTrace.FindSubagent(Event.ToolId);
        If Not Assigned(Block) Then
          Block := FTrace.FindRunningSubagentByKind(Event.ToolName);
        If Not Assigned(Block) Then
          Begin
            If Event.ToolId = '' Then
              Exit;
            Block := FTrace.AddSubagent(Event.ToolId, Event.ToolName, Event.Text);
          End;
        Block.Running := True;
        If Event.Text <> '' Then
          Block.Title := SubagentRunningTitle(SubagentKindCaption(ParseSubagentKind(Event.ToolName)),
            Event.Text);
      End;
    aekSubagentCompleted:
      Begin
        Block := FTrace.FindSubagent(Event.ToolId);
        If Not Assigned(Block) Then
          Block := FTrace.FindRunningSubagentByKind(Event.ToolName);
        If Not Assigned(Block) Then
          Begin
            If Event.ToolId = '' Then
              Exit;
            Block := FTrace.AddSubagent(Event.ToolId, Event.ToolName, Event.Text);
          End;
        Block.Running := False;
        Block.Ok := Event.Ok;
        If Event.DurationMs > 0 Then
          Block.DurationMs := Event.DurationMs;
        If Event.Text <> '' Then
          Block.Body := Event.Text;
        Block.Title := SubagentFinishedTitle(SubagentKindCaption(ParseSubagentKind(Event.ToolName)), '');
        If Not Event.Ok Then
          Block.Footer := 'failed'
        Else If Event.DurationMs > 0 Then
          Block.Footer := FormatThoughtElapsed(Event.DurationMs);
      End;
    aekSteerQueued:
      Begin
        FTrace.AddSteer(Event.Text);
        { Pictures travel as a user block, not as a sentence that names the file. }
        If Event.AttachmentsJson <> '' Then
          FTrace.AppendUserImages(Event.AttachmentsJson);
      End;
    aekInterjected:
      Begin
        Block := FTrace.FindLatestSteer;
        If Assigned(Block) Then
          Begin
            Block.Running := False;
            Block.Title := 'Steer · applied';
            If Event.Text <> '' Then
              Block.Body := Event.Text;
          End
        Else
          Begin
            Block := FTrace.AddSteer(Event.Text);
            Block.Running := False;
            Block.Title := 'Steer · applied';
          End;
      End;
    Else
      Exit;
    End;
    If Assigned(FTraceView) Then
      FTraceView.Sync(FTrace, True);
  Except
    On E: Exception Do
      ClassifyFormFault(Self, afoPaintLayout, 'TProjectAssistantForm.HandleTraceEvent', E, False);
  End;
  Finally
    AssistantSessionObserve.TouchAssistantMirror;
  End;
End;

Procedure TProjectAssistantForm.RefreshChatDisplay(Force: Boolean; ScrollToBottom: Boolean);
Var
  NowTick: QWord;
Begin
  If FRefreshingChat Then
    Exit;
  EnsureChatView;
  NowTick := GetTickCount64;
  If (Not Force) And FStreamingActive And (FLastChatPaintTick > 0) And
    (NowTick - FLastChatPaintTick < ChatPaintMinIntervalMs) Then
    Exit;
  FLastChatPaintTick := NowTick;
  If Not Assigned(FTrace) Then
    Exit;
  FRefreshingChat := True;
  Try
    Try
      If FViewingLive Or FStreamingActive Then ApplyLiveThinkingAndAnswer;
      If Assigned(FTraceView) Then
        Begin
          FTraceView.ShowThinking := FShowThinking;
          FTraceView.ShowToolUse := FShowToolUse;
          FTraceView.SyncConversation(ProjectAssistantConversation, FTrace,
            ((FSending Or FStreamingActive) And Not FTurnRecorded) Or
            (Not Assigned(ProjectAssistantConversation)) Or (ProjectAssistantConversation.TurnCount = 0));
        End;
    Except
      On E: Exception Do
        ClassifyFormFault(Self, afoPaintLayout, 'TProjectAssistantForm.RefreshChatDisplay', E, False);
    End;
  Finally
    FRefreshingChat := False;
  End;
End;

Procedure TProjectAssistantForm.AppendMessage(Const Role, Content: String);
Var
  R: String;
Begin
  R := LowerCase(Trim(Role));
  If R = 'user' Then
    SetCurrentUserDisplay(Content, False)
  Else If R = 'system' Then
    SetCurrentSystemNote(Content)
  Else If R = 'assistant' Then
    Begin
      FAssistantContent := Content;
      FAssistantThinking := '';
      FDisplaySystemNote := '';
      RefreshChatDisplay(True);
    End
  Else
    RefreshChatDisplay(True);
End;

Procedure TProjectAssistantForm.BeginAssistantReply;
Begin
  FLiveContent := '';
  FLiveThinking := '';
  FUserCancelled := False;
  FTurnRecorded := False;
  LiveTurnId := '';
  FStreamingActive := True;
  FViewingLive := True;
  FSelectedTurnIndex := LiveConversationMarker;
  FLastChatPaintTick := 0;
  FTurnStartedAt := IsoNowUtc;
  FDisplayUser := FLiveUser;
  FAssistantContent := '';
  FAssistantThinking := '';
  FDisplayTraceJson := '';
  FDisplayEventsFile := '';
  FDisplaySystemNote := '';
  FThinkingSliceStart := 1;
  FAnswerSliceStart := 1;
  If Assigned(FTrace) Then
    Begin
      FTrace.Clear;
      FTrace.EnsureUser(FDisplayUser);
      ApplyTurnAttachmentsToTrace(FTrace, FComposerImagesJson);
      FTrace.StartThinking(0);
    End;
  RefreshConversationList;
  RefreshChatDisplay(True, True);
  { The phone draws this user block from the snapshot. Do not wait for the first token. }
  AssistantSessionObserve.AssistantSessionObserve(asnSnapshot);
End;

Procedure TProjectAssistantForm.RevealSubmittedPrompt;
Begin
  { A new prompt, typed here or sent from the phone, brings the reader to the head wherever they had scrolled. It is
    painted now, with the busy footer, because starting the backend can hold this thread before the next paint. }
  If Assigned(FTraceView) Then
    Begin
      FTraceView.ScrollToEnd;
      FTraceView.Surface.Update;
    End;
  If Assigned(StatusFooter) Then
    StatusFooter.Update;
End;

Procedure TProjectAssistantForm.ApplyAssistantSnapshots(Const ContentSnapshot, ThinkingSnapshot: String);
Begin
  { Ignore late Queue packets after the turn has finished (prevents a second Begin/Finish cycle). }
  If Not FSending Then
    Exit;
  Try
    If Not FStreamingActive Then
      BeginAssistantReply;
    { Always keep live buffers for the background stream. A continuation round
      starts empty; keep the answer already shown until the new text arrives. }
    If FHoldingContinuation And (FHeldAnswer <> '') Then
      Begin
        If Trim(ContentSnapshot) = '' Then
          FLiveContent := FHeldAnswer
        Else If Copy(ContentSnapshot, 1, Length(FHeldAnswer)) = FHeldAnswer Then
          FLiveContent := ContentSnapshot
        Else
          FLiveContent := FHeldAnswer + LineEnding + LineEnding + ContentSnapshot;
      End
    Else
      FLiveContent := ContentSnapshot;
    FLiveThinking := ThinkingSnapshot;
    { Connecting… stays until new stream text arrives. Text already on screen is not that. }
    If FStatusPhase = AssistantPhaseConnecting Then
      Begin
        If (FLiveContent <> FConnectHoldContent) Or (FLiveThinking <> FConnectHoldThinking) Then
          If FLiveContent <> '' Then
            SetStreamPhase(AssistantPhaseStreaming)
          Else If FLiveThinking <> '' Then
            SetStreamPhase(AssistantPhaseThinking);
      End
    Else If Not IsAssistantRecoveryProgress(FStatusPhase) Then
      Begin
        If FLiveContent <> '' Then
          SetStreamPhase(AssistantPhaseStreaming)
        Else If FLiveThinking <> '' Then
          SetStreamPhase(AssistantPhaseThinking)
        Else If FStatusPhase = '' Then
          SetStreamPhase(AssistantPhaseWaiting);
      End;
    { Only repaint the chat pane when the user is watching the live turn. }
    If FViewingLive Then
      Begin
        FDisplayUser := FLiveUser;
        FAssistantContent := FLiveContent;
        FAssistantThinking := FLiveThinking;
        RefreshChatDisplay(False, True);
      End;
  Except
    On E: Exception Do
      ClassifyFormFault(Self, afoPaintLayout, 'TProjectAssistantForm.ApplyAssistantSnapshots', E, False);
  End;
End;

Procedure TProjectAssistantForm.RecordCompletedUsage;
Var
  Root, ErrorText: String;
  InputTokens, OutputTokens, ReasoningTokens: Integer;
  HasReasoning, HasUsage: Boolean;
  Item: TAssistantUsageRecord;
Begin
  { Codex has no usage parser. A Claude turn reports its own usage in the stream. }
  If (FActiveBackend = 'codex') Or (FActiveConnectionId = '') Then
    Exit;
  If (FActiveBackend = 'claude') Then
    Begin
      HasUsage := FClaudeUsageReported;
      FClaudeUsageReported := False;
      InputTokens := High(Integer);
      If FClaudeInputTokens < High(Integer) Then
        InputTokens := FClaudeInputTokens;
      OutputTokens := High(Integer);
      If FClaudeOutputTokens < High(Integer) Then
        OutputTokens := FClaudeOutputTokens;
      ReasoningTokens := 0;
      HasReasoning := False;
    End
  Else If Assigned(AssistantClient) Then
    HasUsage := AssistantClient.TakeReportedUsage(InputTokens, OutputTokens, ReasoningTokens, HasReasoning)
  Else
    HasUsage := False;
  If Not HasUsage Then
    Exit;
  Root := '';
  If Assigned(ProjectAssistantConversation) Then
    Root := ProjectAssistantConversation.ProjectRoot;
  If Root = '' Then
    Root := ProjectRootPath;
  If Root = '' Then
    Exit;
  Item := ReportedUsageRecord(FActiveConnectionId, FActiveBackend, FActiveModel, InputTokens, OutputTokens,
    HasReasoning, ReasoningTokens, False, 0, '');
  If Not AppendUsageRecord(Root, Item, ErrorText) And (ErrorText <> '') Then
    WorkflowLogger.Warning('ProjectAssistant', 'Could not record usage: ' + ErrorText);
End;

Function TProjectAssistantForm.ContinuationToolRecap: String;
Var
  I: Integer;
  Block: TTraceBlock;
  Piece: String;
Begin
  Result := '';
  If Not Assigned(FTrace) Then
    Exit;
  For I := 0 To FTrace.Count - 1 Do
    Begin
      Block := FTrace[I];
      If (Not Assigned(Block)) Or (Block.Kind <> tbkTool) Then
        Continue;
      Piece := Block.ToolName;
      If Trim(Block.Body) <> '' Then
        Piece := Piece + ': ' + Copy(Trim(Block.Body), 1, 500);
      If Result <> '' Then
        Result := Result + LineEnding;
      Result := Result + Piece;
      If Length(Result) >= 12000 Then
        Begin
          Result := Copy(Result, 1, 12000);
          Break;
        End;
    End;
End;

Function TProjectAssistantForm.QueryContinuation(Truncated, ToolRoundCap, HadToolRound: Boolean;
  Const AssistantText: String): Boolean;
Var
  Facts: TAssistantTurnFinishFacts;
  Answer: TAssistantContinuation;
Begin
  Facts := CurrentTurnFinishFacts(Truncated, ToolRoundCap, HadToolRound);
  Facts.AssistantText := AssistantText;
  Answer := AssistantDecideContinuation(Facts, FUserCancelled, False, FContinuationCount, FContinuationCap,
    FBuildWorkSectionTitle);
  Result := Answer.ContinueTurn And (Not FUserCancelled);
  If Answer.Note <> '' Then
    PostRecoverySentence(Answer.Note);
  If Not Result Then
    Exit;
  Inc(FContinuationCount);
  If Length(AssistantText) > Length(FLiveContent) Then
    FHeldAnswer := AssistantText
  Else
    FHeldAnswer := FLiveContent;
  FHoldingContinuation := FHeldAnswer <> '';
End;

Procedure TProjectAssistantForm.ContinueCodexAfterFinish(Data: PtrInt);
Begin
  If csDestroying In ComponentState Then
    Exit;
  If (Not FSending) Or FUserCancelled Or (FActiveBackend <> 'codex') Then
    Exit;
  If LaunchStoredCodexRun Or (Not FSending) Then
    Exit;
  FinishAssistantReply('The continuation could not be started.');
End;

Function TProjectAssistantForm.CurrentTurnFinishFacts(Truncated, ToolRoundCap, ServiceHadTools: Boolean): TAssistantTurnFinishFacts;
Var
  I: Integer;
  Sections: TObjectList;
  Err, Body: String;
  Section: TPlanSection;
Begin
  Result := DefaultAssistantTurnFinishFacts;
  Result.Truncated := Truncated;
  Result.ToolRoundCap := ToolRoundCap;
  Result.AssistantText := FLiveContent;
  Result.HadToolRound := ServiceHadTools;
  If Assigned(FTrace) Then
    For I := 0 To FTrace.Count - 1 Do
      If FTrace[I].Kind = tbkTool Then
        Begin
          Result.HadToolRound := True;
          Break;
        End;
  { The saved plan is authoritative. A missing snapshot is not treated as in progress. }
  If (FBuildWorkSectionIndex < 0) Or (FBuildWorkPlanPath = '') Then
    Exit;
  Sections := TObjectList.Create(True);
  Try
    If Not ScanPlanSections(FBuildWorkPlanPath, Sections, Err) Then
      Exit;
    If FBuildWorkSectionIndex >= Sections.Count Then
      Exit;
    Section := TPlanSection(Sections[FBuildWorkSectionIndex]);
    If Not Section.Actionable Then
      Exit;
    Result.PlanItemInProgress := Section.Status = pssInProgress;
    If Section.Status <> pssBlocked Then
      Exit;
    If Not GetPlanSectionBody(FBuildWorkPlanPath, FBuildWorkSectionIndex, Body, Err) Then
      Exit;
    Result.PlanItemBlockedWithUserAction := PlanBodyHasUserAction(Body);
  Finally
    Sections.Free;
  End;
End;

Procedure TProjectAssistantForm.AppendPlanItemUsage;
Var
  InN, OutN, ReasonN: Integer;
  HasReasoning, Native: Boolean;
Begin
  If (Not FPlanAgentRunning) Or (FBuildWorkSectionTitle = '') Then
    Exit;
  InN := 0;
  OutN := 0;
  ReasonN := 0;
  HasReasoning := False;
  Native := False;
  If (FActiveBackend <> 'claude') And (FActiveBackend <> 'codex') And Assigned(AssistantClient) Then
    Native := AssistantClient.TakeReportedUsage(InN, OutN, ReasonN, HasReasoning);
  If Native Then
    AssistantClient.NoteReportedUsage(InN, OutN, ReasonN, HasReasoning);
  RememberPlanItemUsage(FPlanItemUsage, FTrace, FBuildWorkSectionTitle, (FActiveBackend = 'claude'), (FActiveBackend = 'codex'), FClaudeUsageReported,
    FClaudeHasCached, Native, FClaudeInputTokens, FClaudeOutputTokens, FClaudeCachedInputTokens, InN, OutN,
    CurrentStreamDurationMs);
End;

Procedure TProjectAssistantForm.FinishAssistantReply(Const ErrorText: String);
Var
  ResolvedError, TraceNote, Settlement, AskedNote: String;
  WorkedMs: Integer;
  Truncated, ToolRoundCap, HadTools: Boolean;
  FinishFacts: TAssistantTurnFinishFacts;
  Answer: TAssistantContinuation;
Begin
  { Notice on every return. A nil listener stops at the assigned check. }
  Try
  If FSending And (Not FUserCancelled) And TryDeferDroppedTransport(FLiveContent, ErrorText, ErrorText) Then
    Begin
      { Keep the broker. The process is dead; the same prompt is started again after the wait. }
      ReleaseCodexProcess;
      ReleaseClaudeProcess;
      Exit;
    End;
  { Only a live process finish cancels its broker. A late HTTP finish must not. }
  If FSending And (FActiveBackend = 'codex') And (Assigned(FCodexRun) Or FCodexLaunchReady) Then
    ReleaseCodexRun;
  If FSending And (FActiveBackend = 'claude') And (Assigned(FClaudeRun) Or FClaudeLaunchReady) Then
    ReleaseClaudeProcess;
  ClearTransportWait;
  FCodexLaunchReady := False;
  FClaudeLaunchReady := False;
  ResolvedError := ErrorText;
  If IsAssistantProgressStatus(ResolvedError) Then
    ResolvedError := '';
  If (FActiveBackend <> 'codex') And (FActiveBackend <> 'claude') And Assigned(AssistantClient) Then
    AssistantClient.ToolsEnabled := ActiveMode <> amChat;
  { Second IsFinished (or Stop after finish) must not append another conversation row. }
  If Not FSending Then
    Begin
      If (FActiveBackend <> 'codex') And (FActiveBackend <> 'claude') And Assigned(AssistantClient) Then
        AssistantClient.MarkStreamComplete;
      Exit;
    End;
  If FUserCancelled Then
    Begin
      FUserCancelled := False;
      FStreamingActive := False;
      If (FActiveBackend <> 'codex') And (FActiveBackend <> 'claude') And Assigned(AssistantClient) Then
        AssistantClient.MarkStreamComplete;
      If FBuildWorkSectionIndex >= 0 Then
        SetBuildStatusFeedback(Format('"%s" cancelled — still in progress.',
          [FBuildWorkSectionTitle]));
      FPendingReviewErrorOffer := False;
      UnlockModeAfterSend;
      SetSending(False);
      Exit;
    End;
  Truncated := False;
  ToolRoundCap := False;
  HadTools := False;
  If Assigned(AssistantClient) Then
    AssistantClient.TakeTurnFinishFacts(Truncated, ToolRoundCap, HadTools);
  FLastTurnFinish.Reason := atfFinished;
  FLastTurnFinish.Unfinished := False;
  { FLive* are authoritative for the completed stream (pane may be browsing elsewhere). }
  If ResolvedError <> '' Then
    Begin
      If FViewingLive Then
        FDisplaySystemNote := '**Error:** ' + ResolvedError;
      StatusFooter.SetRightText('Error');
    End
  Else
    Begin
      { Full conversation for the API lives on AssistantClient (all prior turns). }
      FinishFacts := CurrentTurnFinishFacts(Truncated, ToolRoundCap, HadTools);
      FLastTurnFinish := ClassifyAssistantTurnFinish(FinishFacts);
      If (FActiveBackend = 'codex') And FLastTurnFinish.Unfinished And (Not FinishFacts.PlanItemBlockedWithUserAction) Then
        Begin
          Answer := AssistantDecideContinuation(FinishFacts, False, False, FContinuationCount, FContinuationCap,
            FBuildWorkSectionTitle);
          If Answer.ContinueTurn Then
            Begin
              Inc(FContinuationCount);
              If Answer.Note <> '' Then
                PostRecoverySentence(Answer.Note);
              If Length(FLiveContent) > Length(FHeldAnswer) Then
                FHeldAnswer := FLiveContent;
              FHoldingContinuation := FHeldAnswer <> '';
              If ContinuationToolRecap <> '' Then
                FCodexLaunchPrompt := FCodexLaunchPrompt + LineEnding + LineEnding +
                  'Last tool results:' + LineEnding + ContinuationToolRecap;
              If Trim(FLiveContent) <> '' Then
                FCodexLaunchPrompt := FCodexLaunchPrompt + LineEnding + LineEnding +
                  'Assistant so far:' + LineEnding + Copy(FLiveContent, 1, 8000);
              FCodexLaunchPrompt := FCodexLaunchPrompt + LineEnding + LineEnding + AssistantContinuationInstruction;
              FCodexLaunchReady := True;
              Application.QueueAsyncCall(@ContinueCodexAfterFinish, 0);
              Exit;
            End
          Else If Answer.Note <> '' Then
            PostRecoverySentence(Answer.Note);
        End;
      { Item 3.3: an empty finished reply becomes one trace summary before Ready. Existing text is kept. }
      EnsureFinalAssistantSummary;
      If (FActiveBackend <> 'claude') And Assigned(AssistantClient) And (FLiveContent <> '') Then
        AssistantClient.AddMessage(amrAssistant, FLiveContent);
      FContextUsed := FContextUsed + Length(FLiveContent) Div 4 + 20;
      If FLiveThinking <> '' Then
        FContextUsed := FContextUsed + Length(FLiveThinking) Div 4;
      { Item 3.2 continues an unfinished decision instead of stopping here. }
      StatusFooter.SetRightText(AssistantStatusReady + PlanRunElapsedSuffix);
    End;
  FStreamingActive := False;
  FLastTurnHadError := ResolvedError <> '';
  FDisplayUser := FLiveUser;
  FAssistantContent := FLiveContent;
  FAssistantThinking := FLiveThinking;
  TraceNote := '';
  If ResolvedError <> '' Then
    Begin
      FDisplaySystemNote := '**Error:** ' + ResolvedError;
      TraceNote := FDisplaySystemNote;
    End;
  WorkedMs := CurrentStreamDurationMs;
  PersistPlanReplyIfNeeded(ResolvedError);
  If RevertUncommittedPlanCompletion(Settlement) And (Settlement <> '') Then
    Begin
      If TraceNote <> '' Then
        TraceNote := TraceNote + LineEnding + LineEnding + Settlement
      Else
        TraceNote := Settlement;
    End;
  AskedNote := AssistantTurnSettlementNote(FLiveUser, FPlanWriteThisTurn);
  If AskedNote <> '' Then
    Begin
      If TraceNote <> '' Then
        TraceNote := TraceNote + LineEnding + LineEnding + AskedNote
      Else
        TraceNote := AskedNote;
    End;
  If TraceNote <> '' Then
    FDisplaySystemNote := TraceNote;
  FinishLiveTrace(TraceNote, WorkedMs);
  AppendPlanItemUsage;
  RecordCurrentTurn(ResolvedError);
  If ResolvedError = '' Then
    RecordCompletedUsage;
  If AssistantRequestRejectedImage(ResolvedError) Or AssistantImageSendFailed(ResolvedError) Then
    Begin
      { The pictures stay in the composer. Do not resend the rejected refs on the next request. }
      If Assigned(AssistantClient) Then
        AssistantClient.DropLastUserImageRefs;
      RestoreHeldComposerImages;
    End
  Else If FComposerImagesSent Then
    Begin
      FComposerImagesJson := '';
      FComposerImagesHeld := '';
      RefreshComposerImages;
    End;
  FComposerImagesSent := False;
  If (FActiveBackend <> 'codex') And (FActiveBackend <> 'claude') And Assigned(AssistantClient) Then
    AssistantClient.MarkStreamComplete;
  { Validation evidence can auto-complete when the root is not a Git repository.
    In a repository the model sets Status, and that plan file is committed before the item counts as complete.
    An item that is already complete does not stop the plan agent. }
  If FPlanAgentRunning And (ResolvedError <> '') And (FBuildWorkSectionIndex >= 0) Then
    FPlanAgentResumeIndex := FBuildWorkSectionIndex;
  If ActiveMode = amBuild Then
    Begin
      Try
        TryAutoCompleteBuildWork(ResolvedError);
      Finally
        ClearBuildWorkTracking;
      End;
    End
  Else If FBuildWorkSectionIndex >= 0 Then
    ClearBuildWorkTracking;
  { Review with errors: select top error and prompt Fix Error. }
  If FPendingReviewErrorOffer And (ResolvedError = '') Then
    OfferFixTopErrorAfterReview
  Else If ResolvedError <> '' Then
    FPendingReviewErrorOffer := False;
  UnlockModeAfterSend;
  { Reset the stall clock before FSending drops, so a timer tick cannot see a stale gap. }
  If FPlanAgentRunning Then
    MarkPlanAgentAlive;
  { End send before list refresh so the in-flight row is not kept alongside the stored turn. }
  SetSending(False);
  If FPlanWriteThisTurn And (ResolvedError = '') Then
    Begin
      RefreshActivePlanChoices(Nil);
      RefreshBuildTodos;
      UpdateWorkActions;
    End
  Else If ActiveMode = amBuild Then
    RefreshBuildTodos;
  If FPlanAgentRunning Then
    Begin
      If FLastTurnHadError And IsTransientNetworkError(ResolvedError) And PlanHasOpenItems Then
        Begin
          { Same wait as a lost connection. Stop still clears the agent and the timer. }
          FLastTurnHadError := False;
          FPlanStallNoted := True;
          FPlanStallArmedTick := GetTickCount64;
          EnablePlanStallTimer;
          PostRecoverySentence(AssistantReconnectWaitNote(ResolvedError));
          SetBuildStatusFeedback(AssistantReconnectWaitNote(ResolvedError));
        End
      Else If FLastTurnHadError Then
        StopRunPlan(preError, ResolvedError)
      Else
        Begin
          Inc(FPlanAgentPackagesDone);
          SetBuildStatusFeedback(Format('Plan agent… %d done', [FPlanAgentPackagesDone]));
          Application.QueueAsyncCall(@ContinueRunPlan, 0);
        End;
    End;
  FViewingLive := True;
  If Assigned(ProjectAssistantConversation) Then
    FSelectedTurnIndex := ProjectAssistantConversation.TurnCount - 1;
  RefreshConversationList;
  RefreshChatDisplay(True, True);
  PersistSession;
  Finally
    AssistantSessionObserve.TouchAssistantMirror;
    AssistantSessionObserve.AssistantSessionObserve(asnError);
    AssistantSessionObserve.AssistantSessionObserve(asnStatus);
  End;
End;

Procedure TProjectAssistantForm.StreamToken(Const ContentSnapshot, ThinkingSnapshot: String;
  IsFinished: Boolean; Const ErrorText: String);
Var
  FinishErr: String;
Begin
  If csDestroying In ComponentState Then
    Begin
      ClassifyFormFault(Self, afoCallbackAfterDetach, 'TProjectAssistantForm.StreamToken', Nil, False);
      Exit;
    End;
  { Invoked on the main thread (Queue) from the stream worker. }
  If FUserCancelled Then
    Begin
      If IsFinished Then
        Begin
          FUserCancelled := False;
          FStreamingActive := False;
          If Assigned(AssistantClient) Then
            AssistantClient.MarkStreamComplete;
          UnlockModeAfterSend;
          SetSending(False);
        End;
      Exit;
    End;
  If Not IsFinished Then
    Begin
      ApplyAssistantSnapshots(ContentSnapshot, ThinkingSnapshot);
      If ErrorText <> '' Then
        If AssistantProgressPhase(ErrorText) = ErrorText Then
          SetStreamPhase(ErrorText)
        Else
          AdoptRecoverySentence(ErrorText);
      Exit;
    End;
  FinishErr := ErrorText;
  If IsAssistantProgressStatus(FinishErr) Then
    FinishErr := '';
  { Apply final snapshot only while still the active send (not a duplicate finish). }
  If FSending And ((ContentSnapshot <> '') Or (ThinkingSnapshot <> '')) Then
    ApplyAssistantSnapshots(ContentSnapshot, ThinkingSnapshot);
  FinishAssistantReply(FinishErr);
End;

Procedure TProjectAssistantForm.StopStream;
Var
  WorkedMs: Integer;
Begin
  If Not FSending Then
    Exit;
  { First, before any free or wait. A tool already on this thread sees the flag and kills its child. }
  RequestAssistantToolStop;
  FUserCancelled := True;
  If AssistantIdeToolBusy Then
    Begin
      If Assigned(FCodexRun) Then
        FCodexRun.Cancel;
      If Assigned(FClaudeRun) Then
        FClaudeRun.Cancel;
      If Assigned(FToolBroker) Then
        FToolBroker.Cancel;
      If Assigned(AssistantClient) Then
        AssistantClient.RequestCancel;
      Exit;
    End;
  ClearTransportWait;
  FCodexLaunchReady := False;
  FClaudeLaunchReady := False;
  ReleaseCodexRun;
  ReleaseClaudeProcess;
  { CancelStream pumps CheckSynchronize so Queue/Synchronize cannot deadlock. }
  If (FActiveBackend <> 'codex') And (FActiveBackend <> 'claude') And Assigned(AssistantClient) Then
    Begin
      AssistantClient.CancelStream;
      AssistantClient.ToolsEnabled := ActiveMode <> amChat;
    End;
  If FStreamingActive Or (FLiveUser <> '') Then
    Begin
      If (FLiveContent <> '') Or (FLiveThinking <> '') Then
        Begin
          If (FActiveBackend <> 'claude') And Assigned(AssistantClient) And (FLiveContent <> '') Then
            AssistantClient.AddMessage(amrAssistant, FLiveContent);
          FContextUsed := FContextUsed + Length(FLiveContent) Div 4 + 20;
        End;
      FDisplayUser := FLiveUser;
      FAssistantContent := FLiveContent;
      FAssistantThinking := FLiveThinking;
      If FViewingLive Then
        Begin
          If (FLiveContent = '') And (FLiveThinking = '') Then
            FDisplaySystemNote := '*Stream cancelled before the first token.*'
          Else
            FDisplaySystemNote := '*Stream cancelled.*';
        End;
    End
  Else If FViewingLive Then
    FDisplaySystemNote := '*Stream cancelled.*';
  FStreamingActive := False;
  WorkedMs := CurrentStreamDurationMs;
  FinishLiveTrace(FDisplaySystemNote, WorkedMs);
  RecordCurrentTurn('cancelled');
  FViewingLive := True;
  UnlockModeAfterSend;
  SetSending(False);
  FSelectedTurnIndex := ProjectAssistantConversation.TurnCount - 1;
  RefreshConversationList;
  RefreshChatDisplay(True, True);
  PersistSession;
  ReleaseClaudePlanItemSession(FClaudePlanItem, FClaudeSessionId, FClaudeSessionKey);
  If FPlanAgentRunning Then
    StopRunPlan(preUserStop, 'stream cancelled by user');
  WorkflowLogger.Info('ProjectAssistant', 'Stream cancelled by user');
  AssistantSessionObserve.AssistantSessionObserve(asnTranscript);
  AssistantSessionObserve.AssistantSessionObserve(asnError);
  AssistantSessionObserve.AssistantSessionObserve(asnStatus);
End;

Function TProjectAssistantForm.BuildSubmitApiText(Const ModelText: String; Out WithContext: Boolean): String;
Var
  PlanRel, ContextBlock: String;
Begin
  Result := ModelText;
  If ActiveMode = amPlan Then
    Begin
      PlanRel := GetActivePlanRelativePath;
      If PlanRel = '' Then
        PlanRel := DefaultPlanRelativePath;
      Result := AssistantPlanDirective(PlanRel, AssistantTurnOffersImageOutput(amPlan)) + LineEnding + LineEnding +
        ModelText;
    End
  Else If ActiveMode = amDocument Then
    Result := AssistantDocumentDirective(DocumentPathForTurn, AssistantTurnOffersImageOutput(amDocument)) +
      LineEnding + LineEnding + ModelText;
  { Chat keeps the harness no-tools sentence. Do not paraphrase it into the user text. }
  WithContext := (ActiveMode <> amChat) And Assigned(AssistantChatConfig) And
    AssistantChatConfig.IncludeIDEContext;
  If WithContext Then
    Begin
      { Stored turns, not AssistantClient.MessageCount. Claude never fills that array.
        Codex fills it as side history the app-server does not receive. }
      If Assigned(ProjectAssistantConversation) And
        AssistantUseLightIDEContext(ProjectAssistantConversation.TurnCount) Then
        ContextBlock := BuildIDEContextBlockLight
      Else
        ContextBlock := BuildIDEContextBlock;
      Result := Result + LineEnding + LineEnding + ContextBlock;
    End;
End;

Function TProjectAssistantForm.ConfirmSavedBeforeTurn(Mode: TAssistantMode): Boolean;
Var
  Work: TAssistantUnsavedWork;
  ErrorText: String;
Begin
  Result := True;
  Work := AssistantUnsavedWork(Mode);
  If Work = auwNone Then
    Exit;
  If RemoteTurnStarting Then
    Begin
      { The phone has asked its own question. A desktop dialog would wait for someone who may not be there. }
      If RemoteSaveFirst And SaveAssistantUnsavedWork(Mode, ErrorText) Then
        Exit;
      If RemoteSaveFirst Then
        RemoteRefusal := 'The desktop could not save: ' + ErrorText
      Else
        RemoteRefusal := AssistantUnsavedEditsRefusal;
      Exit(False);
    End;
  If RunAssistantModal(AssistantSaveBeforeTurnQuestion, mtConfirmation, [mbYes, mbNo], 0) = mrYes Then
    Begin
      If SaveAssistantUnsavedWork(Mode, ErrorText) Then
        Exit;
      SetCurrentSystemNote('Not sent: ' + ErrorText);
    End;
  Result := False;
  { The prompt stays in the composer. The unsaved work, or what is left of it, gets the focus. }
  Work := AssistantUnsavedWork(Mode);
  ShowAssistantUnsavedWork(Work);
  WorkflowLogger.Info('ProjectAssistant', 'Turn not started: unsaved work was not saved.');
End;

Procedure TProjectAssistantForm.BeginRemoteTurn(SaveFirst: Boolean);
Begin
  RemoteTurnStarting := True;
  RemoteSaveFirst := SaveFirst;
  RemoteRefusal := '';
End;

Procedure TProjectAssistantForm.EndRemoteTurn(Var ErrorText: String);
Begin
  If RemoteRefusal <> '' Then
    ErrorText := RemoteRefusal;
  RemoteTurnStarting := False;
  RemoteSaveFirst := False;
  RemoteRefusal := '';
End;

Function TProjectAssistantForm.SubmitUserText(Const UserText: String; AutoSend: Boolean): Boolean;
Begin
  Result := SubmitUserTextEx(UserText, UserText, AutoSend);
End;

Function TProjectAssistantForm.SubmitUserTextEx(Const DisplayText, ApiText: String; AutoSend: Boolean): Boolean;
Var
  FinalApi, ModelText, BlockReason: String;
  WithContext: Boolean;
  Refs: TAssistantImageRefArray;
Begin
  Result := False;
  FPendingTurnAttachments := '';
  SetLength(Refs, 0);
  ParseAssistantImageRefs(FComposerImagesJson, Refs);
  Refs := LimitAssistantImageRefs(Refs);
  If (Trim(ApiText) = '') And (Length(Refs) = 0) Then
    Exit;
  If FSending Then
    Exit;
  { Every backend and every way a turn starts: typed, Run Plan, Fix Error, tasks and the phone. }
  If AutoSend And (Not ConfirmSavedBeforeTurn(ActiveMode)) Then
    Exit;
  If AutoSend And (Not TurnEngineReady) Then
    Exit;
  If AutoSend And (FActiveBackend = 'grok') Then
    Begin
      If (Not Assigned(AssistantChatConfig)) Or (Not AssistantChatConfig.IsSignedIn) Then
        Begin
          AppendMessage('user', DisplayText);
          AppendMessage('system', 'Sign in under Settings to send this request to the Assistant.');
          Exit;
        End;
      If Not Assigned(AssistantClient) Then
        Exit;
      RefreshFromConfig;
    End;
  { One capability check for every backend. A missing modality list allows attach. }
  If AutoSend And (Length(Refs) > 0) And (Not ComposerAttachAllowed(BlockReason)) Then
    Begin
      If BlockReason = '' Then
        BlockReason := AssistantImageAttachRefusal;
      SetCurrentSystemNote(BlockReason);
      RunAssistantModal(BlockReason, mtInformation, [mbOK], 0);
      If Assigned(InputMemo) Then
        InputMemo.Text := DisplayText;
      Exit;
    End;
  If AutoSend And (FActiveBackend = 'claude') Then
    Begin
      Result := StartClaudeReply(DisplayText, ApiText);
      Exit;
    End;
  If AutoSend And (FActiveBackend = 'codex') Then
    Begin
      Result := StartCodexReply(DisplayText, ApiText);
      Exit;
    End;
  If AutoSend Then
    Begin
      MaybeWarnHighContextUsage;
      { Callers like Fix Error / Work-on-this may already ForceModeAndLock. }
      If Not FModeLocked Then
        LockModeForSend; { freeze Plan/Build before chat surface / SetSending }
      ShowChatSurfaceKeepMode; { shared turn view already visible; sync mode chrome }
      { Visible words stay DisplayText. The look sentence is model text only. }
      ModelText := AssistantImageModelText(ApiText, Length(Refs));
      FinalApi := BuildSubmitApiText(ModelText, WithContext);
      SetCurrentUserDisplay(DisplayText, WithContext);
      FLiveUser := FDisplayUser;
      FLiveContent := '';
      FLiveThinking := '';
      FAssistantContent := '';
      FAssistantThinking := '';
      AppendMessage('user', FDisplayUser);
      { Prior turns already on AssistantClient are sent with this request (trimmed if huge).
        IDE context is already a text suffix on FinalApi. It is not an image part. }
      AssistantClient.AddUserMessage(FinalApi, Refs);
      FContextUsed := AssistantClient.EstimatedPromptTokens;
      If FContextUsed < Length(FinalApi) Div 4 Then
        FContextUsed := Length(FinalApi) Div 4 + 8;
      FStatusPhase := AssistantPhaseWaiting;
      AssistantClient.ToolsEnabled := ActiveMode <> amChat;
      SetSending(True);
      BeginAssistantReply;
      RevealSubmittedPrompt;
      { Large skill + IDE context means a noticeable wait before the first token.
        That gap is model/server time-to-first-token, not local UI hang. }
      FTurnEventsFile := '';
      If AssistantClient.StartStream(@StreamToken) Then
        Begin
          FComposerImagesSent := Length(Refs) > 0;
          Result := True;
        End
      Else
        Begin
          FinishAssistantReply(AssistantClient.LastError);
          If Assigned(GrokOAuthClient) And (Not GrokOAuthClient.IsAuthenticated) Then
            SettingsActionExecute(Nil);
          Result := False;
        End;
    End
  Else
    AppendMessage('user', DisplayText);
End;

Procedure TProjectAssistantForm.SteerQueuedText(Const UserText: String);
Begin
  If Trim(UserText) = '' Then
    Exit;
  If Assigned(FCodexRun) Then
    Begin
      If FCodexRun.Steer(UserText) Then SetStreamPhase(AssistantPhaseSteering)
      Else InputMemo.Text := UserText;
      Exit;
    End;
  If (Not AssistantCanSteer(FActiveBackend)) Or Assigned(FClaudeRun) Or FTransportWait Then
    Begin
      If Assigned(InputMemo) Then
        InputMemo.Text := UserText;
      Exit;
    End;
  If Assigned(AssistantClient) Then
    AssistantClient.EnqueueSteer(UserText);
  SetStreamPhase(AssistantPhaseSteering);
  WorkflowLogger.Info('ProjectAssistant', 'Steer queued (' + IntToStr(Length(Trim(UserText))) + ' chars)');
End;

Procedure TProjectAssistantForm.PopupAboveControl(Host: TControl; Popup: TPopupMenu);
Var
  Origin: TPoint;
  ItemHeight, MenuHeight, Index, VisibleCount: Integer;
  ScreenMonitor: TMonitor;
Begin
  If Not Assigned(Host) Or Not Assigned(Popup) Then
    Exit;
  VisibleCount := 0;
  For Index := 0 To Popup.Items.Count - 1 Do
    If Popup.Items[Index].Visible Then
      Inc(VisibleCount);
  ItemHeight := Scale96ToForm(28);
  MenuHeight := VisibleCount * ItemHeight + Scale96ToForm(8);
  Origin := Host.ClientToScreen(Point(0, 0));
  Dec(Origin.Y, MenuHeight);
  ScreenMonitor := Screen.MonitorFromPoint(Host.ClientToScreen(Point(0, Host.Height Div 2)));
  If Assigned(ScreenMonitor) And (Origin.Y < ScreenMonitor.WorkareaRect.Top) Then
    Origin.Y := ScreenMonitor.WorkareaRect.Top;
  Popup.PopUp(Origin.X, Origin.Y);
End;

Procedure TProjectAssistantForm.ApplyConfigAndRefresh;
Begin
  If Assigned(AssistantChatConfig) Then
    AssistantChatConfig.Save;
  RefreshFromConfig;
  PersistShellConfig;
End;

Function TProjectAssistantForm.ModeSkillCaption: String;
Var
  Names: TStringList;
  I: Integer;
Begin
  Result := 'Skill: not sent';
  If Not Assigned(AssistantChatConfig) Then
    Exit;
  Names := TStringList.Create;
  Try
    AssistantChatConfig.CollectSkillsForMode(AssistantModeToStr(ActiveMode), Names);
    If Names.Count = 0 Then
      Exit;
    Result := Names[0];
    For I := 1 To Names.Count - 1 Do
      Result := Result + ', ' + Names[I];
  Finally
    Names.Free;
  End;
End;

Procedure TProjectAssistantForm.ToggleSkillForMode(Const SkillName: String);
Var
  Modes: TStringList;
  ModeName: String;
  Index: Integer;
Begin
  If (Not Assigned(AssistantChatConfig)) Or (Trim(SkillName) = '') Then
    Exit;
  ModeName := AssistantModeToStr(ActiveMode);
  Modes := TStringList.Create;
  Try
    AssistantChatConfig.CollectModesForSkill(SkillName, Modes);
    Index := Modes.IndexOf(ModeName);
    If Index >= 0 Then
      Modes.Delete(Index)
    Else
      Modes.Add(ModeName);
    AssistantChatConfig.SetSkillModes(SkillName, Modes);
  Finally
    Modes.Free;
  End;
  ApplyConfigAndRefresh;
  If AssistantChatConfig.SkillHasMode(SkillName, ModeName) Then
    SetCurrentSystemNote('**' + SkillName + '** is sent in ' + ModeName + '.')
  Else
    SetCurrentSystemNote('**' + SkillName + '** is not sent in ' + ModeName + '.');
End;

Procedure EnsureFooterMenu(Var Menu: TPopupMenu); Forward;

Function MenuText(Const Value: String): String;
Begin
  Result := StringReplace(Value, '&', '&&', [rfReplaceAll]);
End;

Function ListHasText(List: TStrings; Const Value: String): Boolean;
Var
  Index: Integer;
Begin
  Result := False;
  If Not Assigned(List) Then
    Exit;
  For Index := 0 To List.Count - 1 Do
    If SameText(List[Index], Value) Then
      Exit(True);
End;

Procedure AddFooterItem(Menu: TPopupMenu; Const Caption: String; TagValue: Integer;
  Const ValueText: String; Checked, Radio: Boolean; Handler: TNotifyEvent; IsEnabled: Boolean = True);
Var
  Item: TMenuItem;
Begin
  Item := TMenuItem.Create(Menu);
  Item.Caption := Caption;
  Item.Enabled := IsEnabled;
  If Caption <> '-' Then
    Begin
      Item.Tag := TagValue;
      Item.Hint := ValueText;
      Item.Checked := Checked;
      Item.RadioItem := Radio;
      Item.GroupIndex := TagValue;
      If IsEnabled Then
        Item.OnClick := Handler;
    End;
  Menu.Items.Add(Item);
End;

Procedure TProjectAssistantForm.FillModelFooterMenu;
Var
  Models: TStringList;
  I: Integer;
  ModelId, DisplayText: String;
  Procedure AddModel(Const Value: String);
  Begin
    If (Trim(Value) <> '') And Not ListHasText(Models, Value) Then
      Models.Add(Trim(Value));
  End;
Begin
  If FActiveConnectionId = '' Then
    Begin
      AddFooterItem(FFooterMenu, 'No connection is selected', 0, '', False, False, Nil, False);
      Exit;
    End;
  Models := TStringList.Create;
  Try
    If FActiveBackend = 'grok' Then
      Begin
        CollectXaiKnownModelIds(Models);
        AddModel(AssistantConfigDefaultModel);
        AddModel('grok-4');
        AddModel('grok-3');
      End
    Else If (FActiveBackend = 'codex') Then
      CollectCodexModelIds(FCodexModelsJson, Models);
    AddModel(FActiveModel);
    If Models.Count = 0 Then
      Begin
        AddFooterItem(FFooterMenu, 'No model is set', 0, '', False, False, Nil, False);
        Exit;
      End;
    For I := 0 To Models.Count - 1 Do
      Begin
        ModelId := Models[I];
        If FActiveBackend = 'grok' Then
          DisplayText := XaiModelDisplayText(ModelId)
        Else
          DisplayText := ModelId;
        AddFooterItem(FFooterMenu, MenuText(DisplayText), FooterTagModel, ModelId, SameText(ModelId, FActiveModel),
          True, @FooterMenuClick);
      End;
  Finally
    Models.Free;
  End;
End;

Procedure TProjectAssistantForm.FillEffortFooterMenu;
Var
  Efforts: TStringList;
  I: Integer;
  Level: String;
  Procedure AddLevel(Const Value, LevelCaption: String);
  Begin
    AddFooterItem(FFooterMenu, LevelCaption, FooterTagEffort, Value, SameText(FActiveEffort, Value), True, @FooterMenuClick);
  End;
Begin
  If FActiveConnectionId = '' Then
    Begin
      AddFooterItem(FFooterMenu, 'No connection is selected', 0, '', False, False, Nil, False);
      Exit;
    End;
  If FActiveBackend = 'grok' Then
    Begin
      If XaiModelAllowsEffort(FActiveModel, 'low') Then
        AddLevel('low', 'Low');
      If XaiModelAllowsEffort(FActiveModel, 'medium') Then
        AddLevel('medium', 'Medium');
      If XaiModelAllowsEffort(FActiveModel, 'high') Then
        AddLevel('high', 'High');
      If XaiModelAllowsEffort(FActiveModel, 'xhigh') Then
        AddLevel('xhigh', 'XHigh');
      If FFooterMenu.Items.Count = 0 Then
        Begin
          AddLevel('low', 'Low');
          AddLevel('medium', 'Medium');
          AddLevel('high', 'High');
          AddLevel('xhigh', 'XHigh');
        End;
      Exit;
    End;
  If (FActiveBackend = 'codex') Then
    Begin
      AddLevel('', 'Model default');
      Efforts := TStringList.Create;
      Try
        If CollectCodexEffortIds(FCodexModelsJson, FActiveModel, Efforts) Then
          Begin
            If (FActiveEffort <> '') And Not ListHasText(Efforts, FActiveEffort) Then
              Efforts.Add(FActiveEffort);
            For I := 0 To Efforts.Count - 1 Do
              Begin
                Level := Efforts[I];
                AddLevel(Level, EffortBarCaption(Level));
              End;
          End
        Else If FActiveEffort <> '' Then
          AddLevel(FActiveEffort, EffortBarCaption(FActiveEffort));
      Finally
        Efforts.Free;
      End;
      Exit;
    End;
  AddFooterItem(FFooterMenu, 'This connection does not set an effort level', 0, '', False, False, Nil, False);
End;

Procedure TProjectAssistantForm.FillPermissionsFooterMenu;
  Procedure AddMode(Const Value, ModeCaption: String);
  Var
    Current: Boolean;
  Begin
    Current := SameText(FActiveApproval, Value) Or ((Trim(FActiveApproval) = '') And (Value = 'ask'));
    AddFooterItem(FFooterMenu, ModeCaption, FooterTagApproval, Value, Current, True, @FooterMenuClick);
  End;
Begin
  If FActiveConnectionId = '' Then
    Begin
      AddFooterItem(FFooterMenu, 'No connection is selected', 0, '', False, False, Nil, False);
      Exit;
    End;
  If (FActiveBackend = 'codex') Then
    Begin
      AddMode('ask', 'Ask before file changes and builds');
      AddMode('always', 'Always: allow registered tools');
    End
  Else
    Begin
      AddMode('ask', 'Ask — confirm each write/compile');
      AddMode('always', 'Always — never prompt (like Build always-approve)');
    End;
End;

Procedure TProjectAssistantForm.ShowSamplingMenu(Kind: Integer);
Var
  Host: TControl;
Begin
  If Not Assigned(StatusFooter) Then
    Exit;
  EnsureFooterMenu(FFooterMenu);
  Case Kind Of
    FooterTagEffort:
      Begin
        FillEffortFooterMenu;
        Host := StatusFooter.EffortLabel;
      End;
    FooterTagApproval:
      Begin
        FillPermissionsFooterMenu;
        Host := StatusFooter.PermissionsLabel;
      End;
  Else
    FillModelFooterMenu;
    Host := StatusFooter.ModelLabel;
  End;
  If Not Assigned(Host) Then
    Host := StatusFooter;
  PopupAboveControl(Host, FFooterMenu);
End;

Function TProjectAssistantForm.ApplySamplingChange(Const NewModel, NewEffort, NewApproval: String;
  UpdateModel, UpdateEffort, UpdateApproval: Boolean): Boolean;
Var
  Note: String;
  DialogKind: TMsgDlgType;
Begin
  Result := TryApplySamplingChange(NewModel, NewEffort, NewApproval, UpdateModel, UpdateEffort, UpdateApproval, Note, DialogKind);
  If (Not Result) And (Note <> '') Then
    RunAssistantModal(Note, DialogKind, [mbOK], 0);
End;

Function TProjectAssistantForm.TryApplySamplingChange(Const NewModel, NewEffort, NewApproval: String;
  UpdateModel, UpdateEffort, UpdateApproval: Boolean; Out Note: String; Out DialogKind: TMsgDlgType): Boolean;
Var
  Connections: TAssistantConnections;
  Item: TAssistantConnection;
  Efforts: TStringList;
  ModelId, ApprovalStored: String;
  Failed: Boolean;
Begin
  Result := False;
  Note := '';
  DialogKind := mtInformation;
  Failed := False;
  If Not Assigned(LazarusIDE) Then
    Begin
      Note := 'The IDE configuration path is not available.';
      Exit;
    End;
  Connections := TAssistantConnections.Create(LazarusIDE.GetPrimaryConfigPath);
  Try
    Try
      Connections.Load;
      Item := Connections.Active;
      If (Not Assigned(Item)) Or (Item.Id <> FActiveConnectionId) Then
        Begin
          Note := 'No connection is selected. Choose one with the Settings button.';
          Exit;
        End;
      If UpdateModel Then
        Begin
          ModelId := Trim(NewModel);
          If (ModelId = '') Or SameText(Item.Model, ModelId) Then
            UpdateModel := False
          Else
            Item.Model := ModelId;
        End;
      If UpdateEffort And (Item.ReasoningEffort = NewEffort) Then
        UpdateEffort := False
      Else If UpdateEffort Then
        Item.ReasoningEffort := NewEffort;
      If UpdateApproval Then
        Begin
          ApprovalStored := ApprovalModeToStr(StrToApprovalMode(NewApproval));
          If (LowerCase(Trim(NewApproval)) <> 'ask') And (ApprovalStored = 'ask') Then
            UpdateApproval := False
          Else If Item.ApprovalMode = ApprovalStored Then
            UpdateApproval := False
          Else
            Item.ApprovalMode := ApprovalStored;
        End;
      If UpdateModel And (Item.Backend = 'grok') And Not XaiModelAllowsEffort(Item.Model, Item.ReasoningEffort) Then
        Begin
          If XaiModelAllowsEffort(Item.Model, 'high') Then
            Item.ReasoningEffort := 'high'
          Else If XaiModelAllowsEffort(Item.Model, 'medium') Then
            Item.ReasoningEffort := 'medium'
          Else If XaiModelAllowsEffort(Item.Model, 'low') Then
            Item.ReasoningEffort := 'low'
          Else
            Item.ReasoningEffort := 'xhigh';
          UpdateEffort := True;
        End;
      If UpdateModel And (Item.Backend = 'codex') And (Item.ReasoningEffort <> '') Then
        Begin
          Efforts := TStringList.Create;
          Try
            If CollectCodexEffortIds(Item.CachedModelsJson, Item.Model, Efforts) And
              Not ListHasText(Efforts, Item.ReasoningEffort) Then
              Begin
                Item.ReasoningEffort := '';
                UpdateEffort := True;
              End;
          Finally
            Efforts.Free;
          End;
        End;
      If Not (UpdateModel Or UpdateEffort Or UpdateApproval) Then
        Begin
          Result := True;
          Exit;
        End;
      If FSending Or FPlanAgentRunning Or FReviewInProgress Then
        Begin
          Note := 'Wait until the current work finishes before changing the model, effort, or permissions.';
          Exit;
        End;
      If Item.Backend = 'grok' Then
        Begin
          If Not Assigned(AssistantChatConfig) Then
            Begin
              Failed := True;
              Exit;
            End;
          If UpdateModel Then
            AssistantChatConfig.Model := Item.Model;
          If UpdateEffort Then
            AssistantChatConfig.ThinkingLevel := Item.ReasoningEffort;
          If UpdateApproval Then
            AssistantChatConfig.ApprovalMode := Item.ApprovalMode;
        End;
      If Connections.Save Then
        Result := True
      Else
        Failed := True;
    Except
      On E: Exception Do
        Begin
          Failed := True;
          WorkflowLogger.Error('ProjectAssistant', 'Could not save the footer choice: ' + E.Message);
        End;
    End;
  Finally
    Connections.Free;
  End;
  If Result Then
    Begin
      WorkflowLogger.Info('ProjectAssistant', 'Footer choice saved for ' + FActiveBackend);
      NotifyOpenProjectAssistantFormsConnectionChanged;
    End
  Else If Failed Then
    Begin
      Note := 'Could not save that choice.';
      DialogKind := mtError;
    End;
End;

Procedure TProjectAssistantForm.FillSkillFooterMenu;
Var
  Skills: TAssistantSkillList;
  I: Integer;
  Root, ModeName: String;
  Tagged: Boolean;
Begin
  ModeName := AssistantModeToStr(ActiveMode);
  Root := '';
  If Assigned(ProjectAssistantConversation) Then
    Root := ProjectAssistantConversation.ProjectRoot;
  Skills := ListGuidanceDocuments(Root);
  If Length(Skills) = 0 Then
    Begin
      AddFooterItem(FFooterMenu, 'No skills are listed', 0, '', False, False, Nil, False);
      Exit;
    End;
  For I := 0 To High(Skills) Do
    Begin
      Tagged := Assigned(AssistantChatConfig) And AssistantChatConfig.SkillHasMode(Skills[I].Name, ModeName);
      AddFooterItem(FFooterMenu, Skills[I].Name, FooterTagSkill, Skills[I].Name, Tagged, False, @FooterMenuClick);
    End;
End;

Procedure TProjectAssistantForm.FooterMenuClick(Sender: TObject);
Var
  Item: TMenuItem;
Begin
  If Not (Sender Is TMenuItem) Then
    Exit;
  Item := TMenuItem(Sender);
  Case Item.Tag Of
    FooterTagSkill:
      If Assigned(AssistantChatConfig) Then
        ToggleSkillForMode(Item.Hint);
    FooterTagSettings:
      SettingsActionExecute(Sender);
    FooterTagModel:
      ApplySamplingChange(Item.Hint, '', '', True, False, False);
    FooterTagEffort:
      ApplySamplingChange('', Item.Hint, '', False, True, False);
    FooterTagApproval:
      ApplySamplingChange('', '', Item.Hint, False, False, True);
  Else
    { }
  End;
End;

Procedure TProjectAssistantForm.InputMemoKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
Var
  EnterIsNewline: Boolean;
Begin
  If (Key = VK_V) And (ssCtrl In Shift) Then
    Begin
      Key := 0;
      QueueComposerPaste;
      Exit;
    End;
  If Key <> VK_RETURN Then
    Exit;
  { Shift+Enter is always a newline. Leaving the key lets the memo insert it.
    Ctrl+Shift+Enter does not produce a character, so insert that one here. }
  If ssShift In Shift Then
    Begin
      If ssCtrl In Shift Then
        Begin
          Key := 0;
          InputMemo.SelText := LineEnding;
        End;
      Exit;
    End;
  EnterIsNewline := True;
  If Assigned(AssistantChatConfig) Then
    EnterIsNewline := AssistantChatConfig.EnterInsertsNewline;
  If EnterIsNewline Then
    Begin
      { Plain Enter stays a newline. Ctrl+Enter sends. }
      If ssCtrl In Shift Then
        Begin
          Key := 0;
          SendActionExecute(Sender);
        End;
    End
  Else If ssCtrl In Shift Then
    Begin
      Key := 0;
      InputMemo.SelText := LineEnding;
    End
  Else
    Begin
      Key := 0;
      SendActionExecute(Sender);
    End;
End;

Procedure TProjectAssistantForm.StatusFooterLeftClick(Sender: TObject);
Begin
  ShowSamplingMenu(FooterTagModel);
End;

Procedure TProjectAssistantForm.StatusFooterEffortClick(Sender: TObject);
Begin
  ShowSamplingMenu(FooterTagEffort);
End;

Procedure TProjectAssistantForm.StatusFooterPermissionsClick(Sender: TObject);
Begin
  ShowSamplingMenu(FooterTagApproval);
End;

Procedure TProjectAssistantForm.StatusFooterSkillClick(Sender: TObject);
Begin
  SkillsPickerActionExecute(Sender);
End;

Procedure TProjectAssistantForm.StatusFooterCentreClick(Sender: TObject);
Begin
  ContextBreakdownActionExecute(Sender);
End;

Procedure TProjectAssistantForm.StatusFooterUsageClick(Sender: TObject);
Var
  Body: String;
Begin
  Body := FPlanStatusCaption;
  If FPlanStatusHint <> '' Then
    Begin
      If Body <> '' Then
        Body := Body + LineEnding + LineEnding;
      Body := Body + FPlanStatusHint;
    End;
  If Trim(Body) = '' Then
    Body := 'Plan usage has not been reported for this connection yet.';
  RunAssistantModal(Body, mtInformation, [mbOK], 0);
End;

Procedure TProjectAssistantForm.StatusFooterRightClick(Sender: TObject);
Begin
  SessionInfoActionExecute(Sender);
End;

Procedure TProjectAssistantForm.ContextBreakdownActionExecute(Sender: TObject);
Var
  Info: TAssistantContextBreakdown;
  Pct: Integer;
  Body: String;
Begin
  If (FActiveBackend = 'codex') Then
    Begin
      RunAssistantModal(CodexContextDetails(FCodexContextUsage, FContextUsed), mtInformation, [mbOK], 0);
      Exit;
    End;
  If (FActiveBackend = 'claude') Then
    Begin
      RunAssistantModal('Claude Code keeps the session. This assistant does not send its tool list or compact the transcript.',
        mtInformation, [mbOK], 0);
      Exit;
    End;
  If Assigned(AssistantClient) Then
    Info := AssistantClient.GetContextBreakdown
  Else
    Begin
      Info := Default(TAssistantContextBreakdown);
      Info.TotalTokens := FContextUsed;
      Info.LimitTokens := FContextLimit;
    End;
  If Info.LimitTokens > 0 Then
    Pct := (Info.TotalTokens * 100) Div Info.LimitTokens
  Else
    Pct := 0;
  Body :=
    Format('Context is about %d%% of the budget.', [Pct]) + LineEnding + LineEnding +
    Format('  System prompt   ~%d tokens', [Info.SystemTokens]) + LineEnding +
    Format('  Tool schemas    ~%d tokens', [Info.ToolsTokens]) + LineEnding +
    Format('  History         ~%d tokens  (%d messages)', [Info.HistoryTokens, Info.MessageCount]) +
    LineEnding +
    Format('  Images          ~%d tokens  (%d still on the next request)', [Info.ImageTokens, Info.ImageCount]) +
    LineEnding +
    Format('  Total           ~%d / %d', [Info.TotalTokens, Info.LimitTokens]);
  If Assigned(AssistantClient) And (AssistantClient.LastTrimNotice <> '') Then
    Body := Body + LineEnding + LineEnding + AssistantClient.LastTrimNotice;
  RunAssistantModal(Body, mtInformation, [mbOK], 0);
End;

Procedure TProjectAssistantForm.SessionInfoActionExecute(Sender: TObject);
Var
  Body, PlanRel, Root, SkillName: String;
  Turns: Integer;
  SignedIn: String;
Begin
  If (FActiveBackend = 'codex') Then
    Begin
      RunAssistantModal('ChatGPT preview uses a separate subscription sign-in profile. Open Settings → Connections to check the account and available models.', mtInformation, [mbOK], 0);
      Exit;
    End;
  If (FActiveBackend = 'claude') Then
    Begin
      RunAssistantModal(ClaudeKeepsSessionText + LineEnding + LineEnding +
        'This assistant does not send its tool list or skill list.', mtInformation, [mbOK], 0);
      Exit;
    End;
  PlanRel := GetActivePlanRelativePath;
  If PlanRel = '' Then
    PlanRel := '(none)';
  Root := '(no project)';
  Turns := 0;
  If Assigned(ProjectAssistantConversation) Then
    Begin
      If ProjectAssistantConversation.ProjectRoot <> '' Then
        Root := ProjectAssistantConversation.ProjectRoot;
      Turns := ProjectAssistantConversation.TurnCount;
    End;
  SkillName := ModeSkillCaption;
  SignedIn := 'no';
  If Assigned(AssistantChatConfig) And AssistantChatConfig.IsSignedIn Then
    SignedIn := 'yes';
  Body :=
    'Project Assistant session' + LineEnding + LineEnding +
    'Mode: ' + ModeChipCaption(ActiveMode) + LineEnding +
    'Model: ' + FActiveModel + LineEnding +
    'Effort: ' + EffortBarCaption(FActiveEffort) + LineEnding +
    'Permissions: ' + ApprovalModeCaption(StrToApprovalMode(FActiveApproval)) + LineEnding;
  Body := Body +
    SkillName + LineEnding +
    Format('Context: ~%d / %d tokens', [FContextUsed, FContextLimit]) + LineEnding +
    'Turns: ' + IntToStr(Turns) + LineEnding +
    'Active plan: ' + PlanRel + LineEnding +
    'Project: ' + Root + LineEnding +
    'Signed in: ' + SignedIn;
  RunAssistantModal(Body, mtInformation, [mbOK], 0);
End;

Procedure EnsureFooterMenu(Var Menu: TPopupMenu);
Begin
  If Assigned(Menu) Then
    Menu.Items.Clear
  Else
    Menu := TPopupMenu.Create(Nil);
End;

Procedure TProjectAssistantForm.ModelPickerActionExecute(Sender: TObject);
Begin
  ShowSamplingMenu(FooterTagModel);
End;

Procedure TProjectAssistantForm.SkillsPickerActionExecute(Sender: TObject);
Var
  Host: TControl;
  Item: TMenuItem;
Begin
  If (FActiveBackend = 'claude') Then
    Begin
      RunAssistantModal('Claude Code keeps the session. This assistant does not send its skill list.', mtInformation, [mbOK], 0);
      Exit;
    End;
  EnsureFooterMenu(FFooterMenu);
  FillSkillFooterMenu;
  AddFooterItem(FFooterMenu, '-', 0, '', False, False, Nil);
  { Action link copies Visible, so hiding TasksAction hides this item too. }
  If Assigned(TasksAction) Then
    Begin
      Item := TMenuItem.Create(FFooterMenu);
      Item.Action := TasksAction;
      FFooterMenu.Items.Add(Item);
    End;
  AddFooterItem(FFooterMenu, 'Settings…', FooterTagSettings, '', False, False, @FooterMenuClick);
  Host := StatusFooter.SkillLabel;
  If Not Assigned(Host) Then
    Host := StatusFooter;
  PopupAboveControl(Host, FFooterMenu);
End;

Procedure TProjectAssistantForm.OpenPlanActionExecute(Sender: TObject);
Var
  PlanRel, Resolved, Err: String;
Begin
  PlanRel := GetActivePlanRelativePath;
  If PlanRel = '' Then
    Begin
      RunAssistantModal('No active plan. Use the Plan tab to create or set one.', mtInformation, [mbOK], 0);
      Exit;
    End;
  If Not ResolvePlanPath(PlanRel, Resolved, Err) Then
    Begin
      RunAssistantModal(Err, mtError, [mbOK], 0);
      Exit;
    End;
  OpenMarkdownDocument(Resolved);
End;

Function TProjectAssistantForm.CloseActivePlan(Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := '';
  If GetActivePlanRelativePath = '' Then
    Begin
      ErrorText := 'No active plan to close.';
      Exit;
    End;
  SetActivePlanRelativePath('');
  PersistShellConfig;
  RefreshActivePlanChoices(Nil);
  RefreshBuildTodos;
  UpdateWorkActions;
  SetBuildStatusFeedback('Closed. The plan stays in the available list.');
  Result := True;
End;

Procedure TProjectAssistantForm.ClosePlanActionExecute(Sender: TObject);
Var
  Err: String;
Begin
  If FSending Or FReviewInProgress Or FPlanAgentRunning Then
    Exit;
  If Not CloseActivePlan(Err) And (Err <> '') Then
    RunAssistantModal(Err, mtInformation, [mbOK], 0);
End;

Function TProjectAssistantForm.ComposerHasImages: Boolean;
Var
  Refs: TAssistantImageRefArray;
Begin
  ParseAssistantImageRefs(FComposerImagesJson, Refs);
  Result := Length(Refs) > 0;
End;

Procedure TProjectAssistantForm.StashComposerImages;
Begin
  FComposerImagesHeld := FComposerImagesJson;
  FComposerImagesJson := '';
  RefreshComposerImages;
End;

Procedure TProjectAssistantForm.RestoreHeldComposerImages;
Var
  Held, Current, Merged: TAssistantImageRefArray;
  I, J, N: Integer;
  Found: Boolean;
Begin
  If FComposerImagesHeld = '' Then Exit;
  ParseAssistantImageRefs(FComposerImagesHeld, Held);
  ParseAssistantImageRefs(FComposerImagesJson, Current);
  SetLength(Merged, Length(Held) + Length(Current));
  N := 0;
  For I := 0 To High(Held) Do
    Begin
      Merged[N] := Held[I];
      Inc(N);
    End;
  For I := 0 To High(Current) Do
    Begin
      Found := False;
      For J := 0 To N - 1 Do
        If Merged[J].Id = Current[I].Id Then Found := True;
      If Not Found Then
        Begin
          Merged[N] := Current[I];
          Inc(N);
        End;
    End;
  SetLength(Merged, N);
  Merged := LimitAssistantImageRefs(Merged);
  FComposerImagesJson := AssistantImageRefsToJson(Merged);
  FComposerImagesHeld := '';
  RefreshComposerImages;
End;

Procedure TProjectAssistantForm.SendActionExecute(Sender: TObject);
Var
  UserText, Reason: String;
  HasImages, AcceptImages: Boolean;
  Refs: TAssistantImageRefArray;
  Procedure PicturesStay;
  Begin
    SetCurrentSystemNote('The pictures stay in the composer for the next message.');
    RunAssistantModal('The pictures stay in the composer for the next message.', mtInformation, [mbOK], 0);
  End;
Begin
  If Not Assigned(InputMemo) Then Exit;
  { Enter and Ctrl+Enter call this directly. A disabled Send must not submit or steer. }
  If Not SendAction.Enabled Then
    Exit;
  UserText := Trim(InputMemo.Text);
  HasImages := ComposerHasImages;
  If (UserText = '') And (Not HasImages) Then
    Exit;
  If FSending Then
    Begin
      Reason := '';
      AcceptImages := HasImages And ComposerAttachAllowed(Reason);
      If (UserText = '') And (Not AcceptImages) Then
        Begin
          If HasImages Then
            Begin
              If Reason <> '' Then
                WorkflowLogger.Info('ProjectAssistant', 'Steer kept pictures: ' + Reason);
              PicturesStay;
            End;
          Exit;
        End;
      If AcceptImages Then
        Begin
          ParseAssistantImageRefs(FComposerImagesJson, Refs);
          Refs := LimitAssistantImageRefs(Refs);
          If (FActiveBackend = 'codex') Then
            Begin
              If (Not Assigned(FCodexRun)) Or
                (Not FCodexRun.Steer(AssistantImageModelText(UserText, Length(Refs)), AssistantImageRefsToJson(Refs))) Then
                Begin
                  If Assigned(FCodexRun) And (FCodexRun.LastSteerError <> '') Then
                    Begin
                      SetCurrentSystemNote(FCodexRun.LastSteerError);
                      RunAssistantModal(FCodexRun.LastSteerError, mtInformation, [mbOK], 0);
                    End
                  Else
                    PicturesStay;
                  Exit;
                End;
            End
          Else If (Not AssistantCanSteer(FActiveBackend)) Or FTransportWait Then
            Begin
              PicturesStay;
              Exit;
            End
          Else If (Not Assigned(AssistantClient)) Or (Not AssistantClient.EnqueueSteer(UserText, Refs)) Then
            Exit;
          InputMemo.Clear;
          FComposerImagesJson := '';
          RefreshComposerImages;
          SetStreamPhase(AssistantPhaseSteering);
          WorkflowLogger.Info('ProjectAssistant', 'Steer queued (' + IntToStr(Length(UserText)) + ' chars, ' +
            IntToStr(Length(Refs)) + ' images)');
          Exit;
        End;
      If UserText <> '' Then
        Begin
          InputMemo.Clear;
          SteerQueuedText(UserText);
        End;
      If HasImages Then
        Begin
          If Reason <> '' Then
            WorkflowLogger.Info('ProjectAssistant', 'Steer kept pictures: ' + Reason);
          PicturesStay;
        End;
      Exit;
    End;
  If Not TurnEngineReady Then
    Exit;
  If (FActiveBackend = 'grok') And
    ((Not Assigned(AssistantChatConfig)) Or (Not AssistantChatConfig.IsSignedIn)) Then
    Begin
      RunAssistantModal('Sign in with SuperGrok / X Premium in Settings before sending.', mtInformation, [mbOK], 0);
      SettingsActionExecute(Nil);
      Exit;
    End;
  If Not SubmitUserText(UserText, True) Then Exit;
  InputMemo.Clear;
  StashComposerImages;
End;

Procedure TProjectAssistantForm.StopActionExecute(Sender: TObject);
Begin
  StopStream;
End;

Function FormatMessageLine(Line: TMessageLine): String;
Var
  Loc: String;
Begin
  Result := '';
  If Not Assigned(Line) Then
    Exit;
  If Trim(Line.OriginalLine) <> '' Then
    Begin
      Result := Line.OriginalLine;
      Exit;
    End;
  Loc := '';
  If Line.Filename <> '' Then
    Begin
      Loc := Line.GetFullFilename;
      If Line.Line > 0 Then
        Begin
          Loc := Loc + '(' + IntToStr(Line.Line);
          If Line.Column > 0 Then
            Loc := Loc + ',' + IntToStr(Line.Column);
          Loc := Loc + ')';
        End;
    End;
  If Loc <> '' Then
    Result := Loc + ' '
  Else
    Result := '';
  If Line.Urgency In [mluHint..mluPanic] Then
    Result := Result + MessageLineUrgencyNames[Line.Urgency] + ': ';
  If Line.TranslatedMsg <> '' Then
    Result := Result + Line.TranslatedMsg
  Else
    Result := Result + Line.Msg;
  Result := Trim(Result);
End;

Function TProjectAssistantForm.CollectIDEMessagesText(Out ErrorCount, WarningCount, HintCount: Integer): String;
Var
  ViewIndex, LineIndex: Integer;
  View: TExtToolView;
  Line: TMessageLine;
  Parts: TStringList;
  Formatted: String;
Begin
  Result := '';
  ErrorCount := 0;
  WarningCount := 0;
  HintCount := 0;
  If Not Assigned(IDEMessagesWindow) Then
    Begin
      Result := '(IDE Messages window is not available.)';
      Exit;
    End;
  Parts := TStringList.Create;
  Try
    For ViewIndex := 0 To IDEMessagesWindow.ViewCount - 1 Do
      Begin
        View := IDEMessagesWindow.Views[ViewIndex];
        If Not Assigned(View) Then
          Continue;
        If View.Caption <> '' Then
          Parts.Add('--- ' + View.Caption + ' ---');
        View.Lines.EnterCriticalSection;
        Try
          For LineIndex := 0 To View.Lines.Count - 1 Do
            Begin
              Line := View.Lines.Items[LineIndex];
              If Not Assigned(Line) Then
                Continue;
              Case Line.Urgency Of
                mluError, mluFatal, mluPanic: Inc(ErrorCount);
                mluWarning: Inc(WarningCount);
                mluHint, mluNote: Inc(HintCount);
              Else
                { }
              End;
              Formatted := FormatMessageLine(Line);
              If Formatted <> '' Then
                Parts.Add(Formatted);
            End;
        Finally
          View.Lines.LeaveCriticalSection;
        End;
        If View.SummaryMsg <> '' Then
          Parts.Add(View.SummaryMsg);
      End;
    If Parts.Count = 0 Then
      Parts.Add('(No messages were recorded in the IDE Messages window.)');
    Result := TrimRight(Parts.Text);
  Finally
    Parts.Free;
  End;
End;

Function TProjectAssistantForm.BuildReviewDisplayLabel(Const KindLabel: String;
  ErrorCount, WarningCount, HintCount: Integer; BuildOk: Boolean): String;
Begin
  If BuildOk And (ErrorCount = 0) And (WarningCount = 0) And (HintCount = 0) Then
    Result := Format('Review %s — clean', [KindLabel])
  Else If ErrorCount > 0 Then
    Result := Format('Review %s — %d error(s), %d warning(s), %d hint(s)',
      [KindLabel, ErrorCount, WarningCount, HintCount])
  Else
    Result := Format('Review %s — %d warning(s), %d hint(s)',
      [KindLabel, WarningCount, HintCount]);
End;

Function TProjectAssistantForm.BuildReviewPrompt(Const KindLabel, OutputText: String;
  ErrorCount, WarningCount, HintCount: Integer; BuildOk: Boolean): String;
Var
  Outcome, ProjectName: String;
Begin
  If BuildOk And (ErrorCount = 0) Then
    Outcome := 'clean (no errors)'
  Else If ErrorCount > 0 Then
    Outcome := Format('failed with %d error(s)', [ErrorCount])
  Else
    Outcome := 'completed with warnings/notes';
  ProjectName := AssistantTarget.DisplayName;
  Result :=
    'Task: review Free Pascal / Lazarus IDE ' + LowerCase(KindLabel) +
    ' messages from my local machine (same text as the Messages window).' + LineEnding +
    LineEnding +
    'Project: ' + ProjectName + LineEnding +
    'Outcome: ' + Outcome +
      Format(' — errors=%d, warnings=%d, hints/notes=%d', [ErrorCount, WarningCount, HintCount]) +
      LineEnding +
    LineEnding +
    '## Response format (mandatory — one reply only)' + LineEnding +
    LineEnding +
    '1. Put ALL detailed analysis in your thinking/reasoning channel: group related diagnostics, ' +
    'explain causes, note risks, and keep any longer discussion there.' + LineEnding +
    '2. The visible answer (content) must be ONLY:' + LineEnding +
    '   - One short status line (e.g. "Clean compile" or "9 warnings, 15 hints — no errors")' + LineEnding +
    '   - Then a prioritized action list (highest priority first)' + LineEnding +
    '   - Nothing else in content: no per-message essays, no full code dumps, no long preamble' + LineEnding +
    LineEnding +
    '### Action list rules' + LineEnding +
    '- Priority order: (1) errors that block the build, (2) actionable warnings that indicate real bugs ' +
    'or API misuse, (3) deprecations worth fixing soon, (4) optional cleanup (unused params, notes).' + LineEnding +
    '- Merge related messages into one action when they share a root cause.' + LineEnding +
    '- Each action: one short bullet — file, location if known, what to change.' + LineEnding +
    '- Skip pure noise (orphan/duplicate PPU notes that are environmental, pure informational notes with no code change).' + LineEnding +
    '- If nothing actionable: content is a single line confirming clean / no action required.' + LineEnding +
    LineEnding +
    'If there are errors, end with one short line: the user can click **Fix Error** to start Build mode on the top error.' + LineEnding +
    LineEnding +
    'Do not call tools. Do not ask follow-up questions. Work only from the output below and answer once.' + LineEnding +
    LineEnding +
    '----- begin compiler/messages output -----' + LineEnding +
    OutputText + LineEnding +
    '----- end compiler/messages output -----';
End;

Procedure TProjectAssistantForm.SubmitReviewRequest(Const DisplayLabel, ApiText: String);
Begin
  If Trim(ApiText) = '' Then
    Exit;
  If FSending Then
    Exit;
  If (FActiveBackend = 'claude') Then
    Begin
      StartClaudeReply(DisplayLabel, ApiText);
      Exit;
    End;
  If (FActiveBackend = 'codex') Then
    Begin
      StartCodexReply(DisplayLabel, ApiText);
      Exit;
    End;
  If (Not Assigned(AssistantChatConfig)) Or (Not AssistantChatConfig.IsSignedIn) Then
    Begin
      AppendMessage('user', DisplayLabel);
      AppendMessage('system', 'Sign in under Settings to send this review to the Assistant.');
      Exit;
    End;
  If Not Assigned(AssistantClient) Then
    Exit;
  RefreshFromConfig;
  ApplyActiveMode;
  { Reviews: short list label, full messages only in the API body, no IDE file dump, no tools. }
  SetCurrentUserDisplay(DisplayLabel, False);
  FLiveUser := FDisplayUser;
  FLiveContent := '';
  FLiveThinking := '';
  FAssistantContent := '';
  FAssistantThinking := '';
  AppendMessage('user', FDisplayUser);
  AssistantClient.AddMessage(amrUser, ApiText);
  FContextUsed := FContextUsed + Length(ApiText) Div 4 + 8;
  FStatusPhase := AssistantPhaseWaiting;
  AssistantClient.ToolsEnabled := False;
  SetSending(True);
  BeginAssistantReply;
  RevealSubmittedPrompt;
  FTurnEventsFile := '';
  If Not AssistantClient.StartStream(@StreamToken) Then
    Begin
      AssistantClient.ToolsEnabled := ActiveMode <> amChat;
      FinishAssistantReply(AssistantClient.LastError);
    End;
End;

Procedure TProjectAssistantForm.ReviewProject(Reason: TCompileReason; Const KindLabel: String);
Var
  BuildResult: TModalResult;
  OutputText, PromptText, DisplayLabel: String;
  ErrorCount, WarningCount, HintCount: Integer;
  BuildOk: Boolean;
Begin
  If FSending Or FReviewInProgress Then
    Exit;
  If Not Assigned(LazarusIDE) Then
    Begin
      AppendMessage('system', 'LazarusIDE not available – cannot run ' + KindLabel + '.');
      Exit;
    End;
  If Not AssistantTarget.Available Then
    Begin
      RunAssistantModal('Select a project or package before using Review ' + KindLabel + '.', mtInformation, [mbOK], 0);
      Exit;
    End;

  FReviewInProgress := True;
  SyncCodexUsageIdle;
  UpdateStatusFooter;
  WorkflowLogger.Info('ProjectAssistant', 'Review ' + KindLabel + ' started');

  Try
    If AssistantTarget.Kind=atkPackage Then
      Begin
        If Reason = crBuild Then BuildResult := PackageEditingInterface.DoCompilePackage(AssistantTarget.Package, [pcfCleanCompile, pcfDoNotSaveEditorFiles], False)
        Else BuildResult := PackageEditingInterface.DoCompilePackage(AssistantTarget.Package, [pcfDoNotSaveEditorFiles], False);
      End
    Else BuildResult := LazarusIDE.DoBuildProject(Reason, []);
    BuildOk := BuildResult = mrOk;
    OutputText := CollectIDEMessagesText(ErrorCount, WarningCount, HintCount);
    DisplayLabel := BuildReviewDisplayLabel(KindLabel, ErrorCount, WarningCount, HintCount, BuildOk);
    PromptText := BuildReviewPrompt(KindLabel, OutputText, ErrorCount, WarningCount, HintCount, BuildOk);

    If BuildOk And (ErrorCount = 0) Then
      Begin
        FPendingReviewErrorOffer := False;
        FReviewErrorCount := 0;
      End
    Else If ErrorCount > 0 Then
      PrepareTopErrorAfterReview(ErrorCount)
    Else
      Begin
        FPendingReviewErrorOffer := False;
        FReviewErrorCount := 0;
      End;
    UpdateStatusFooter;

    { Reviews start a fresh conversation (own model context); prior chat is archived. }
    If Assigned(ProjectAssistantConversation) And (ProjectAssistantConversation.ProjectRoot <> '') Then
      Begin
        If Not ProjectAssistantConversation.StartNewConversation Then
          WorkflowLogger.Warning('ProjectAssistant', 'Review archive: ' + ProjectAssistantConversation.LastError)
        Else
          Begin
            { Clear before the notice so a catchup of the new epoch cannot copy the old live trace. }
            ClearCurrentTurnDisplay;
            AssistantSessionObserve.AssistantSessionObserve(asnIdentity);
          End;
      End;
    FContextUsed := 0;
    FCodexContextUsage := EmptyCodexContextUsage;
    FTurnRecorded := False;
    FSelectedTurnIndex := -1;
    If Assigned(AssistantClient) Then
      AssistantClient.ClearHistory;
    RefreshHistoryCombo;
    RefreshConversationList;

    SubmitReviewRequest(DisplayLabel, PromptText);
  Finally
    { Keep FReviewInProgress True while the review stream runs so a second click
      cannot start a duplicate review with the same Messages dump. }
    If Not FSending Then
      Begin
        FReviewInProgress := False;
        UpdateStatusFooter;
      End;
  End;
End;

Procedure TProjectAssistantForm.ReviewCompile;
Begin
  ReviewProject(crCompile, 'Compile');
End;

Procedure TProjectAssistantForm.ReviewBuild;
Begin
  ReviewProject(crBuild, 'Build');
End;

Function TProjectAssistantForm.StartNewChat(KeepPlanAgent: Boolean; UseChatDefault: Boolean): Boolean;
Var
  Report, Note: String;
Begin
  Result := False;
  FPlanAgentResumeIndex := -1;
  Report := '';
  { End the run before the old conversation is archived, then post into the new one. }
  If FPlanAgentRunning And (Not KeepPlanAgent) Then
    Report := EndRunPlan(preNewChat, 'new chat');
  If FSending Then
    StopStream;
  SetSending(False);
  ClearUnsentComposerImages;
  EnsureConversationStore;
  If (Not Assigned(ProjectAssistantConversation)) Or (ProjectAssistantConversation.ProjectRoot = '') Then
    Begin
      SetCurrentSystemNote('No project is open.');
      Exit;
    End;
  If Not ProjectAssistantConversation.StartNewConversation Then
    Begin
      WorkflowLogger.Warning('ProjectAssistant', 'StartNewConversation: ' + ProjectAssistantConversation.LastError);
      If ProjectAssistantConversation.LastError <> '' Then
        SetCurrentSystemNote(ProjectAssistantConversation.LastError)
      Else
        SetCurrentSystemNote('Could not start a new conversation.');
      Exit;
    End;
  { Clear before the notice so a catchup of the new epoch cannot copy the old live trace. }
  ClearCurrentTurnDisplay;
  AssistantSessionObserve.AssistantSessionObserve(asnIdentity);
  FContextUsed := 0;
  FCodexContextUsage := EmptyCodexContextUsage;
  FContextWarnShown := False;
  FUserCancelled := False;
  FTurnRecorded := False;
  FLastChatPaintTick := 0;
  If Assigned(AssistantClient) Then
    AssistantClient.ClearHistory;
  RefreshHistoryCombo;
  RefreshConversationList;
  RefreshChatDisplay(True, False);
  If UseChatDefault Then
    SelectMode(amChat);
  Note := '';
  If Report <> '' Then
    PostPlanRunReport(Report)
  Else If Not FAutoRolloverInProgress Then
    Begin
      If UseChatDefault Then
        Note := 'New conversation started in **Chat**. Previous chat moved to History.'
      Else
        Note := Format('New conversation started in **%s**. Previous conversation moved to History.',
          [ModeChipCaption(ActiveMode)]);
    End;
  If (Note <> '') And Assigned(FTrace) Then
    FTrace.AddNote(Note);
  If Note <> '' Then
    SetCurrentSystemNote(Note);
  PersistSession;
  UpdateStatusFooter;
  { History is already archived. Publish the empty conversation before the phone asks again. }
  AssistantSessionObserve.AssistantSessionObserve(asnSnapshot);
  Result := True;
End;

Procedure TProjectAssistantForm.UnbindFromProject;
Begin
  { Do not call PersistSession here: ActiveProject is half-torn during close.
    Conversation turns are already on disk via AppendTurn. }
  If FSending Then
    StopStream;
  ClearUnsentComposerImages;
  Caption := 'Project Assistant';
  FSessionProjectKey := '';
  ClearCurrentTurnDisplay;
  FContextUsed := 0;
  FCodexContextUsage := EmptyCodexContextUsage;
  FUserCancelled := False;
  FLastChatPaintTick := 0;
  FSelectedTurnIndex := -1;
  If Assigned(AssistantClient) Then
    AssistantClient.ClearHistory;
  If Assigned(ProjectAssistantConversation) Then
    ProjectAssistantConversation.SetProjectRoot('');
  { Do not write Chat into the project config: the root is already cleared. }
  SelectMode(amChat);
  SetActivePlanRelativePath('');
  UpdateWorkActions;
  RefreshHistoryCombo;
  RefreshConversationList;
  ClearCurrentTurnDisplay;
  RefreshChatDisplay(True, False);
  RefreshActivePlanChoices(Nil);
  UpdateStatusFooter;
  WorkflowLogger.Info('ProjectAssistant', 'Unbound from project');
End;

Procedure TProjectAssistantForm.BindToActiveProject;
Var
  Key, Title, Root, Saved, Note: String;
Begin
  { A phone resume must not copy this window until Load has finished. }
  FMonitorBound := False;
  If Not FTargetRestored Then
    Begin
      FTargetRestored := True;
      Saved := SavedAssistantTarget;
      If Saved <> '' Then
        AssistantTarget.SelectFolder(Saved, Note);
    End;
  { Cancel any in-flight stream for the previous project before rebinding.
    Do not PersistSession first: when ProjectOpened fires, ActiveProject is already
    the new project, so a save would write the old transcript under the new path.
    Turns for the previous project were already flushed by AppendTurn. }
  If FSending Then
    StopStream;
  FOpenBindPending := False;

  Key := AssistantTarget.Manifest;
  Root := AssistantTarget.Root;
  If Not AssistantTarget.Available Then Root := '';
  Title := 'Assistant — ' + AssistantTarget.DisplayName;
  RefreshTargetChoices(Nil);
  If Assigned(FToolBroker) Then FToolBroker.Cancel;
  If Assigned(FIDEWorkspace) Then FIDEWorkspace.CancelBuild;
  SetActivePlanRelativePath('');

  Caption := Title;
  FSessionProjectKey := '';
  ClearCurrentTurnDisplay;
  FContextUsed := 0;
  FCodexContextUsage := EmptyCodexContextUsage;
  FUserCancelled := False;
  FLastChatPaintTick := 0;
  FSelectedTurnIndex := -1;
  If Assigned(AssistantClient) Then
    AssistantClient.ClearHistory;

  If Assigned(ProjectAssistantConversation) Then
    Begin
      If Root = '' Then
        Begin
          ProjectAssistantConversation.SetProjectRoot('');
          { No project: Chat, and do not write that into the previous project's config. }
          SelectMode(amChat);
        End
      Else
        Begin
          ProjectAssistantConversation.SetProjectRoot(Root, AssistantTarget.StoreKey);
          ProjectAssistantConversation.Load;
          { Must run after Load: restore mode tab + thinking from config.json.
            EnsureConversationStore alone is not enough — Bind always reloads
            the store and used to skip ApplyShellConfigFromStore. }
          ApplyShellConfigFromStore;
        End;
    End;

  RefreshFromConfig;
  If Assigned(AssistantClient) Then
    Begin
      AssistantClient.OnTrace := @HandleTraceEvent;
      AssistantClient.OnContinuationQuery := @QueryContinuation;
    End;
  { Re-sync client tools/mode after shell prefs (and after default tab if no config). }
  ApplyActiveMode;
  If Root <> '' Then
    Begin
      FSessionProjectKey := Key;
      RestoreSessionIfNeeded;
      RefreshHistoryCombo;
      RefreshConversationList;
      RefreshActivePlanChoices(Nil);
      If FDeferLastTurn Then
        Begin
          FDeferLastTurn := False;
          SetOpenBusy(True);
          Application.QueueAsyncCall(@DeferredShowLastTurn, 0);
        End
      Else
        Begin
          ShowLastConversationTurn;
          SetOpenBusy(False);
        End;
    End
  Else
    Begin
      FDeferLastTurn := False;
      SetOpenBusy(False);
      SetActivePlanRelativePath('');
      UpdateWorkActions;
      RefreshHistoryCombo;
      RefreshConversationList;
      ClearCurrentTurnDisplay;
      RefreshChatDisplay(True, False);
      RefreshActivePlanChoices(Nil);
    End;
  UpdateStatusFooter;
  FMonitorBound := True;
  If Root <> '' Then
    WorkflowLogger.Info('ProjectAssistant', 'Bound to project: ' + Title + ' root=' + Root)
  Else
    WorkflowLogger.Info('ProjectAssistant', 'Bound to project: ' + Title);
  AssistantSessionObserve.AssistantSessionObserve(asnIdentity);
End;

Procedure NotifyOpenProjectAssistantFormsProjectChanged;
Var
  I: Integer;
  Form: TCustomForm;
Begin
  If AssistantTarget.Kind<>atkProject Then Exit;
  { Do not auto-create the window — only refresh forms that already exist. }
  For I := Screen.CustomFormCount - 1 DownTo 0 Do
    Begin
      Form := Screen.CustomForms[I];
      If (Form Is TProjectAssistantForm) And Not (csDestroying In Form.ComponentState) Then
        TProjectAssistantForm(Form).BindToActiveProject;
    End;
End;

Procedure NotifyOpenProjectAssistantFormsProjectCleared;
Var
  I: Integer;
  Form: TCustomForm;
Begin
  If AssistantTarget.Kind<>atkProject Then Exit;
  For I := Screen.CustomFormCount - 1 DownTo 0 Do
    Begin
      Form := Screen.CustomForms[I];
      If (Form Is TProjectAssistantForm) And Not (csDestroying In Form.ComponentState) Then
        TProjectAssistantForm(Form).UnbindFromProject;
    End;
End;

Procedure NotifyOpenProjectAssistantFormsPreferencesChanged;
Var
  I: Integer;
  Form: TCustomForm;
Begin
  For I := Screen.CustomFormCount - 1 DownTo 0 Do
    Begin
      Form := Screen.CustomForms[I];
      If (Form Is TProjectAssistantForm) And Not (csDestroying In Form.ComponentState) Then
        TProjectAssistantForm(Form).ApplyDisplayPreferences;
    End;
End;

Procedure TProjectAssistantForm.ReloadActiveConnection;
Begin
  If csDestroying In ComponentState Then Exit;
  If FSending Then
    Begin
      FReloadConnectionAfterSend := True;
      Exit;
    End;
  FPublishModelList := True;
  FPublishReasoningList := True;
  FPublishPermissionsList := True;
  LoadConnectionSettings;
  RefreshFromConfig;
  ApplyActiveMode;
  WorkflowLogger.Info('ProjectAssistant', 'Active connection applied: ' + FModelName);
End;

Procedure NotifyOpenProjectAssistantFormsConnectionChanged;
Var
  I: Integer;
  Form: TCustomForm;
Begin
  For I := Screen.CustomFormCount - 1 DownTo 0 Do
    Begin
      Form := Screen.CustomForms[I];
      If (Form Is TProjectAssistantForm) And Not (csDestroying In Form.ComponentState) Then
        TProjectAssistantForm(Form).ReloadActiveConnection;
    End;
End;

Procedure NotifyOpenProjectAssistantFormsAccountUsage;
Var
  I: Integer;
  Form: TCustomForm;
Begin
  For I := Screen.CustomFormCount - 1 DownTo 0 Do
    Begin
      Form := Screen.CustomForms[I];
      If (Form Is TProjectAssistantForm) And Not (csDestroying In Form.ComponentState) Then
        TProjectAssistantForm(Form).ApplyAccountUsageLabel;
    End;
End;

Function ExtractSourceSnippet(Const FileName: String; LineNo, Radius: Integer): String;
Var
  SL: TStringList;
  First, Last, I: Integer;
  Path: String;
Begin
  Result := '';
  Path := Trim(FileName);
  If (Path = '') Or (Not FileExists(Path)) Then
    Exit;
  SL := TStringList.Create;
  Try
    Try
      SL.LoadFromFile(Path);
    Except
      Exit;
    End;
    If SL.Count = 0 Then
      Exit;
    If LineNo < 1 Then
      LineNo := 1;
    First := LineNo - Radius;
    If First < 1 Then
      First := 1;
    Last := LineNo + Radius;
    If Last > SL.Count Then
      Last := SL.Count;
    Result := Format('Source context (%s lines %d–%d):', [ExtractFileName(Path), First, Last]) +
      LineEnding + '```pascal' + LineEnding;
    For I := First To Last Do
      Begin
        If I = LineNo Then
          Result := Result + Format('%5d > %s', [I, SL[I - 1]]) + LineEnding
        Else
          Result := Result + Format('%5d | %s', [I, SL[I - 1]]) + LineEnding;
      End;
    Result := Result + '```';
  Finally
    SL.Free;
  End;
End;

Function TProjectAssistantForm.ResolveMessageLineForFix(PreferTopError: Boolean): TMessageLine;
Var
  ViewIndex, LineIndex: Integer;
  View: TExtToolView;
  Line, FirstError, FirstWarn, FirstAny, Selected: TMessageLine;
Begin
  Result := Nil;
  FirstError := Nil;
  FirstWarn := Nil;
  FirstAny := Nil;
  Selected := Nil;
  If Not Assigned(IDEMessagesWindow) Then
    Exit;
  Selected := IDEMessagesWindow.GetSelectedLine;
  For ViewIndex := 0 To IDEMessagesWindow.ViewCount - 1 Do
    Begin
      View := IDEMessagesWindow.Views[ViewIndex];
      If Not Assigned(View) Then
        Continue;
      View.Lines.EnterCriticalSection;
      Try
        For LineIndex := 0 To View.Lines.Count - 1 Do
          Begin
            Line := View.Lines.Items[LineIndex];
            If Not Assigned(Line) Then
              Continue;
            If (Line.Msg = '') And (Line.TranslatedMsg = '') Then
              Continue;
            If FirstAny = Nil Then
              FirstAny := Line;
            If (FirstError = Nil) And (Line.Urgency In [mluError, mluFatal, mluPanic]) Then
              FirstError := Line;
            If (FirstWarn = Nil) And (Line.Urgency = mluWarning) Then
              FirstWarn := Line;
          End;
      Finally
        View.Lines.LeaveCriticalSection;
      End;
    End;
  { Prefer top error when requested, or whenever errors exist (selection is a hint only). }
  If PreferTopError Or Assigned(FirstError) Then
    Begin
      If Assigned(FirstError) Then
        Result := FirstError
      Else If Assigned(Selected) Then
        Result := Selected
      Else If Assigned(FirstWarn) Then
        Result := FirstWarn
      Else
        Result := FirstAny;
    End
  Else If Assigned(Selected) Then
    Result := Selected
  Else If Assigned(FirstWarn) Then
    Result := FirstWarn
  Else
    Result := FirstAny;
  If Assigned(Result) And Assigned(IDEMessagesWindow) Then
    IDEMessagesWindow.SelectMsgLine(Result);
End;

Function TProjectAssistantForm.CollectRelatedMessages(Primary: TMessageLine; MaxLines: Integer): String;
Var
  ViewIndex, LineIndex, Taken: Integer;
  View: TExtToolView;
  Line: TMessageLine;
  PrimaryFile, Formatted: String;
  Parts: TStringList;
Begin
  Result := '';
  If Not Assigned(Primary) Or Not Assigned(IDEMessagesWindow) Then
    Exit;
  If MaxLines < 1 Then
    MaxLines := 8;
  PrimaryFile := '';
  If Primary.Filename <> '' Then
    PrimaryFile := Primary.GetFullFilename;
  Parts := TStringList.Create;
  Try
    Taken := 0;
    For ViewIndex := 0 To IDEMessagesWindow.ViewCount - 1 Do
      Begin
        View := IDEMessagesWindow.Views[ViewIndex];
        If Not Assigned(View) Then
          Continue;
        View.Lines.EnterCriticalSection;
        Try
          For LineIndex := 0 To View.Lines.Count - 1 Do
            Begin
              Line := View.Lines.Items[LineIndex];
              If Not Assigned(Line) Then
                Continue;
              If Line = Primary Then
                Continue;
              If Not (Line.Urgency In [mluHint..mluPanic]) Then
                Continue;
              If PrimaryFile <> '' Then
                Begin
                  If Line.Filename = '' Then
                    Continue;
                  If Not SameText(Line.GetFullFilename, PrimaryFile) Then
                    Continue;
                End
              Else If Not (Line.Urgency In [mluError, mluFatal, mluPanic, mluWarning]) Then
                Continue;
              Formatted := FormatMessageLine(Line);
              If Formatted = '' Then
                Continue;
              Parts.Add(Formatted);
              Inc(Taken);
              If Taken >= MaxLines Then
                Break;
            End;
        Finally
          View.Lines.LeaveCriticalSection;
        End;
        If Taken >= MaxLines Then
          Break;
      End;
    Result := TrimRight(Parts.Text);
  Finally
    Parts.Free;
  End;
End;

Function TProjectAssistantForm.BuildFixErrorPromptForLine(Line: TMessageLine): String;
Var
  MsgText, FileName, Snippet, Related: String;
  LineNo, Col: Integer;
Begin
  Result := '';
  If Not Assigned(Line) Then
    Exit;
  MsgText := FormatMessageLine(Line);
  FileName := '';
  LineNo := Line.Line;
  Col := Line.Column;
  If Line.Filename <> '' Then
    FileName := Line.GetFullFilename;
  Snippet := '';
  If (FileName <> '') And (LineNo > 0) Then
    Snippet := ExtractSourceSnippet(FileName, LineNo, 18);
  Related := CollectRelatedMessages(Line, 10);
  Result :=
    'You are in **Build mode**. Fix this Free Pascal / Lazarus compiler message by **editing sources with tools**.' +
    LineEnding + LineEnding +
    '**Primary message:**' + LineEnding +
    MsgText + LineEnding;
  If FileName <> '' Then
    Result := Result + 'File: ' + FileName + LineEnding;
  If LineNo > 0 Then
    Result := Result + Format('Location: line %d, column %d', [LineNo, Col]) + LineEnding;
  Result := Result + LineEnding;
  If Snippet <> '' Then
    Result := Result + Snippet + LineEnding + LineEnding;
  If Related <> '' Then
    Result := Result +
      '**Related messages (same file or nearby):**' + LineEnding +
      Related + LineEnding + LineEnding;
  Result := Result +
    '**Instructions:**' + LineEnding +
    '1. Prefer `read_file` / `search_in_project` only if the snippet is insufficient.' + LineEnding +
    '2. Apply the fix with `replace_in_file` (or `write_file` / `ensure_form_component` when appropriate).' + LineEnding +
    '3. Prefer the smallest correct change; do not rewrite unrelated code.' + LineEnding +
    '4. If the unit is a form and the fix needs components/events, update the matching `.lfm` too.' + LineEnding +
    '5. Call `run_compile` after edits and fix any new errors you introduced.' + LineEnding +
    '6. Visible reply: short explanation of the cause + what you changed (no long patch dumps if tools already applied).' + LineEnding +
    '7. Do not only describe the fix — **apply it with tools** in this turn.';
End;

Procedure TProjectAssistantForm.FixTopError;
Var
  Line: TMessageLine;
  Prompt: String;
  Col, TopLine: Integer;
Begin
  If Not TurnEngineReady Then
    Exit;
  If FSending Then
    Begin
      RunAssistantModal('Wait for the current reply to finish (or Stop) before Fix Error.',
        mtInformation, [mbOK], 0);
      Exit;
    End;
  If Not Assigned(IDEMessagesWindow) Then
    Begin
      RunAssistantModal('The IDE Messages window is not available.', mtInformation, [mbOK], 0);
      Exit;
    End;
  FPendingReviewErrorOffer := False;
  Line := ResolveMessageLineForFix(True);
  If Not Assigned(Line) Then
    Begin
      RunAssistantModal('No compiler messages found. Run Compile/Build (or Review Compile) first, ' +
        'or select a message in the Messages window, then choose Fix Error.',
        mtInformation, [mbOK], 0);
      Exit;
    End;
  Prompt := BuildFixErrorPromptForLine(Line);
  If Prompt = '' Then
    Exit;
  { Before jumping to the error, so No leaves the editor where it was. }
  If Not ConfirmSavedBeforeTurn(amBuild) Then
    Exit;
  If (Line.Filename <> '') And (Line.Line > 0) And Assigned(LazarusIDE) Then
    Begin
      Col := Line.Column;
      If Col < 1 Then
        Col := 1;
      TopLine := Line.Line - 8;
      If TopLine < 1 Then
        TopLine := 1;
      LazarusIDE.DoOpenFileAndJumpToPos(Line.GetFullFilename,
        Point(Col, Line.Line), TopLine, -1, -1, [ofOnlyIfExists, ofRegularFile]);
    End;
  ForceModeAndLock(amBuild);
  ShowChatSurfaceKeepMode;
  SubmitUserTextEx(
    'Fix Error: ' + FormatMessageLine(Line),
    Prompt,
    True);
  If Not FSending Then
    UnlockModeAfterSend;
End;

Procedure TProjectAssistantForm.NewConversationActionExecute(Sender: TObject);
Begin
  StartNewChat(False, False);
  If InputMemo.CanFocus Then InputMemo.SetFocus;
End;

Procedure TProjectAssistantForm.NewPlanActionExecute(Sender: TObject);
Begin
  NewPlan;
End;

Procedure TProjectAssistantForm.HistoryComboChange(Sender: TObject);
Var
  ArchiveId: String;
Begin
  If FHistoryUpdating Then
    Exit;
  If FSending Then
    Begin
      RunAssistantModal('Stop the current reply before switching History.', mtInformation, [mbOK], 0);
      RefreshHistoryCombo;
      Exit;
    End;
  If Not Assigned(HistoryCombo) Or Not Assigned(HistoryIds) Then
    Exit;
  If (HistoryCombo.ItemIndex < 0) Or (HistoryCombo.ItemIndex >= HistoryIds.Count) Then
    Exit;
  ArchiveId := HistoryIds[HistoryCombo.ItemIndex];
  If ArchiveId = '' Then
    Exit; { already current }
  EnsureConversationStore;
  If Not Assigned(ProjectAssistantConversation) Then
    Exit;
  If Not ProjectAssistantConversation.ActivateArchive(ArchiveId) Then
    Begin
      RunAssistantModal('Could not open conversation:' + LineEnding + ProjectAssistantConversation.LastError,
        mtError, [mbOK], 0);
      RefreshHistoryCombo;
      Exit;
    End;
  SelectMode(ModeOfLoadedConversation);
  AssistantSessionObserve.AssistantSessionObserve(asnIdentity);
  ApplyLoadedConversationToUi('Loaded conversation from History. Model context restored from its turns.');
  PersistSession;
  WorkflowLogger.Info('ProjectAssistant', 'History activated: ' + ArchiveId);
End;

Procedure TProjectAssistantForm.ExportHistoryActionExecute(Sender: TObject);
Var
  Dlg: TSaveDialog;
  Path, Body: String;
  SL: TStringList;
Begin
  If FSending Then
    Begin
      RunAssistantModal('Stop the current reply before exporting.', mtInformation, [mbOK], 0);
      Exit;
    End;
  EnsureConversationStore;
  If (Not Assigned(ProjectAssistantConversation)) Or (Not ProjectAssistantConversation.HasTurns) Then
    Begin
      RunAssistantModal('There is nothing to export in the current conversation.', mtInformation, [mbOK], 0);
      Exit;
    End;
  Body := BuildConversationMarkdownExport;
  Dlg := TSaveDialog.Create(Nil);
  Try
    Dlg.Title := 'Export conversation';
    Dlg.Filter := 'Markdown (*.md)|*.md|All files (*.*)|*.*';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := DefaultExportFileName;
    Dlg.Options := Dlg.Options + [ofOverwritePrompt, ofPathMustExist];
    Dlg.InitialDir := AssistantTarget.Root;
    If Not Dlg.Execute Then
      Exit;
    Path := Dlg.FileName;
  Finally
    Dlg.Free;
  End;
  SL := TStringList.Create;
  Try
    Try
      SL.Text := Body;
      SL.SaveToFile(Path);
      SetCurrentSystemNote('Exported conversation to `' + Path + '`.');
      WorkflowLogger.Info('ProjectAssistant', 'Exported conversation to ' + Path);
    Except
      On E: Exception Do
        RunAssistantModal('Could not write export file:' + LineEnding + E.Message, mtError, [mbOK], 0);
    End;
  Finally
    SL.Free;
  End;
End;

Procedure TProjectAssistantForm.DeleteHistoryActionExecute(Sender: TObject);
Var
  ArchiveId, LabelText: String;
  IsCurrent: Boolean;
Begin
  If FSending Then
    Begin
      RunAssistantModal('Stop the current reply before deleting a conversation.', mtInformation, [mbOK], 0);
      Exit;
    End;
  If Not Assigned(HistoryCombo) Or Not Assigned(HistoryIds) Then
    Exit;
  If (HistoryCombo.ItemIndex < 0) Or (HistoryCombo.ItemIndex >= HistoryIds.Count) Then
    Exit;
  ArchiveId := HistoryIds[HistoryCombo.ItemIndex];
  LabelText := HistoryCombo.Items[HistoryCombo.ItemIndex];
  IsCurrent := ArchiveId = '';
  If RunAssistantModal(
    'Delete this conversation permanently?' + LineEnding + LineEnding +
    LabelText + LineEnding + LineEnding +
    'This cannot be undone.',
    mtWarning, [mbYes, mbNo], 0) <> mrYes Then
    Exit;
  EnsureConversationStore;
  If Not Assigned(ProjectAssistantConversation) Then
    Exit;
  If Not ProjectAssistantConversation.DeleteConversation(ArchiveId) Then
    Begin
      RunAssistantModal('Could not delete conversation:' + LineEnding + ProjectAssistantConversation.LastError,
        mtError, [mbOK], 0);
      Exit;
    End;
  If IsCurrent Then
    Begin
      FContextUsed := 0;
      FCodexContextUsage := EmptyCodexContextUsage;
      FTurnRecorded := False;
      FSelectedTurnIndex := -1;
      ClearCurrentTurnDisplay;
      If Assigned(AssistantClient) Then
        AssistantClient.ClearHistory;
      RefreshHistoryCombo;
      RefreshConversationList;
      RefreshChatDisplay(True, False);
      SetCurrentSystemNote('Conversation deleted.');
      PersistSession;
      UpdateStatusFooter;
    End
  Else
    RefreshHistoryCombo;
  WorkflowLogger.Info('ProjectAssistant', 'Deleted conversation id=' + ArchiveId);
End;

Procedure TProjectAssistantForm.SettingsActionExecute(Sender: TObject);
Begin
  If FSending Then Exit;
  ShowAssistantSettingsForm;
  LoadConnectionSettings;
  RefreshFromConfig;
End;

Procedure TProjectAssistantForm.CompilerFinished(Const ProjectFile: String; Result: TCompilerResult;
  Const OutputText: String; ErrorCount, WarningCount: Integer);
Begin
  { Review Compile/Build captures Messages via the IDE API after DoBuildProject.
    This bus hook remains for future external publishers. }
  If FReviewInProgress Then
    Exit;
  If OutputText <> '' Then
    WorkflowLogger.Debug('ProjectAssistant', 'CompilerFinished for ' + ProjectFile);
  UpdateStatusFooter;
End;

Procedure TProjectAssistantForm.DocumentChanged(Const FileName: String; Const NewContent: String);
Var
  PlanRel, Resolved, Err: String;
Begin
  WorkflowLogger.Debug('ProjectAssistant', 'Document changed: ' + FileName);
  PlanRel := GetActivePlanRelativePath;
  If PlanRel = '' Then
    Exit;
  If Not ResolvePlanPath(PlanRel, Resolved, Err) Then
    Exit;
  If SameFileName(ExpandFileName(FileName), ExpandFileName(Resolved)) Then
    RefreshBuildTodos;
End;

Procedure TProjectAssistantForm.DocumentSaved(Const FileName: String);
Var
  PlanRel, Resolved, Err: String;
Begin
  WorkflowLogger.Debug('ProjectAssistant', 'Document saved: ' + FileName);
  PlanRel := GetActivePlanRelativePath;
  If PlanRel = '' Then
    Exit;
  If Not ResolvePlanPath(PlanRel, Resolved, Err) Then
    Exit;
  If SameFileName(ExpandFileName(FileName), ExpandFileName(Resolved)) Then
    Begin
      RefreshActivePlanChoices(Nil);
      RefreshBuildTodos;
    End;
End;

Function AssistantModeForTask(Mode: TAssistantTaskMode): TAssistantMode;
Begin
  Case Mode Of
    tmDocument: Result := amDocument;
    tmPlan: Result := amPlan;
    tmBuild: Result := amBuild;
    tmChat: Result := amChat;
  Else
    Result := amInspect;
  End;
End;

Procedure ApplyPreparedTaskRequest(Form: TProjectAssistantForm; Const Request: TAssistantTaskRequest);
Var
  TaskMode: TAssistantMode;
  Started: Boolean;
Begin
  { Format does not call the model. The runner applies that kind itself.
    This is the existing turn path: no second send, no CompleteOnce, and no active-plan write. }
  If (Request.Kind = trkNone) Or (Request.Task.Kind = tkFormat) Then
    Exit;
  TaskMode := AssistantModeForTask(Request.Mode);
  If Request.Kind = trkInsert Then
    Begin
      If Not Assigned(Form.InputMemo) Then
        Exit;
      If (Trim(Form.InputMemo.Text) <> '') And
        (Form.RunAssistantModal('Replace the composer text with this task?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes) Then
        Exit;
      Form.SelectMode(TaskMode);
      Form.InputMemo.Text := Request.ApiText;
      Exit;
    End;
  { A plan run is already refused. Do not archive that run or send into it. }
  If Form.FSending Or Form.FPlanAgentRunning Then
    Exit;
  { Before a fresh conversation archives the open one. }
  If Not Form.ConfirmSavedBeforeTurn(TaskMode) Then
    Exit;
  If Request.FreshConversation And (Not Form.StartNewChat(False, False)) Then
    Exit;
  If Request.DocumentPath <> '' Then
    RememberDocumentRelativePath(Request.DocumentPath);
  Form.ClearBuildWorkTracking;
  Form.ForceModeAndLock(TaskMode);
  Form.ShowChatSurfaceKeepMode;
  Started := Form.SubmitUserTextEx(Request.DisplayLabel, Request.ApiText, True);
  If Not Started Then
    Form.UnlockModeAfterSend;
End;

Procedure TProjectAssistantForm.TasksActionExecute(Sender: TObject);
Var
  Request: TAssistantTaskRequest;
Begin
  If Not ShowAssistantTasksForm(Not (FSending Or FPlanAgentRunning), Request) Then
    Exit;
  ApplyPreparedTaskRequest(Self, Request);
End;

Function AssistantHostTurnOrPlanActive(Out Reason: String): Boolean;
Var
  I: Integer;
  Form: TCustomForm;
Begin
  Result := False;
  Reason := '';
  For I := Screen.CustomFormCount - 1 DownTo 0 Do
    Begin
      Form := Screen.CustomForms[I];
      If (Not (Form Is TProjectAssistantForm)) Or (csDestroying In Form.ComponentState) Then
        Continue;
      If TProjectAssistantForm(Form).FPlanAgentRunning Then
        Begin
          Reason := 'A plan run is already active.';
          Exit(True);
        End;
      If TProjectAssistantForm(Form).FSending Then
        Begin
          Reason := 'Wait for the current reply to finish.';
          Exit(True);
        End;
    End;
End;

Procedure PostAssistantFormatNote(Const NoteText: String);
Var
  Turn: TConversationTurn;
  Entry: TConversationIndexEntry;
  Trace: TAssistantTrace;
  Host: TProjectAssistantForm;
  Form: TCustomForm;
  I: Integer;
  Stored: Boolean;
Begin
  If Trim(NoteText) = '' Then
    Exit;
  Host := Nil;
  For I := Screen.CustomFormCount - 1 DownTo 0 Do
    Begin
      Form := Screen.CustomForms[I];
      If (Form Is TProjectAssistantForm) And Not (csDestroying In Form.ComponentState) Then
        Begin
          Host := TProjectAssistantForm(Form);
          Break;
        End;
    End;
  Stored := False;
  If Assigned(Host) Then
    Host.EnsureConversationStore;
  If Assigned(ProjectAssistantConversation) And (ProjectAssistantConversation.ProjectRoot <> '') Then
    Begin
      Turn.Id := NewConversationTurnId;
      If Assigned(Host) Then
        Turn.Mode := AssistantModeToStr(Host.ActiveMode)
      Else
        Turn.Mode := AssistantModeToStr(amInspect);
      Turn.Prompt := '';
      Turn.Thinking := '';
      Turn.Response := NoteText;
      Turn.CreatedAt := IsoNowUtc;
      Turn.StartedAt := Turn.CreatedAt;
      Turn.FinishedAt := Turn.CreatedAt;
      Turn.DurationMs := 0;
      Turn.ThinkingMs := 0;
      Turn.Model := '';
      Turn.Skill := '';
      Turn.TokenEstimate := Length(NoteText) Div 4;
      Turn.ErrorText := '';
      Turn.PlanFile := '';
      Turn.TodoId := '';
      Turn.EventsFile := '';
      Turn.MessagesJson := '[]';
      Turn.AttachmentsJson := '';
      Trace := TAssistantTrace.Create;
      Try
        Trace.AddNote(NoteText);
        Turn.TraceJson := Trace.SaveToJson;
      Finally
        Trace.Free;
      End;
      Stored := ProjectAssistantConversation.AppendTurn(Turn, Entry);
    End;
  If Not Assigned(Host) Then
    Exit;
  If Stored Then
    Begin
      If Not Host.FSending Then
        Begin
          Host.FViewingLive := False;
          Host.FSelectedTurnIndex := ProjectAssistantConversation.TurnCount - 1;
        End;
      Host.RefreshConversationList;
      Host.RefreshChatDisplay(True, True);
    End
  Else
    Host.SetCurrentSystemNote(NoteText);
End;

Function TraceKindName(Kind: TTraceBlockKind): String;
Begin
  Case Kind Of
    tbkThinking: Result := 'thinking';
    tbkTool: Result := 'tool';
    tbkAnswer: Result := 'answer';
    tbkNote: Result := 'note';
    tbkSteer: Result := 'steer';
    tbkSubagent: Result := 'subagent';
    tbkWorked: Result := 'worked';
  Else
    Result := 'user';
  End;
End;

Function ShortPreview(Const Text: String): String;
Var
  Flat: String;
Begin
  Flat := StringReplace(Trim(Text), LineEnding, ' ', [rfReplaceAll]);
  Flat := StringReplace(Flat, #10, ' ', [rfReplaceAll]);
  If Length(Flat) > 160 Then
    Result := Copy(Flat, 1, 160)
  Else
    Result := Flat;
End;

Function TargetKindName: String;
Begin
  Case AssistantTarget.Kind Of
    atkPackage: Result := 'package';
    atkFolder: Result := 'folder';
  Else
    Result := 'project';
  End;
End;

Function KnownMonitorMode(Const ModeText: String; Out Mode: TAssistantMode): Boolean;
Var
  Name: String;
Begin
  Name := LowerCase(Trim(ModeText));
  Result := True;
  If Name = 'inspect' Then
    Mode := amInspect
  Else If Name = 'document' Then
    Mode := amDocument
  Else If Name = 'plan' Then
    Mode := amPlan
  Else If Name = 'build' Then
    Mode := amBuild
  Else If Name = 'chat' Then
    Mode := amChat
  Else
    Result := False;
End;

Function ThisFormBusy(Form: TProjectAssistantForm; Out ErrorText: String): Boolean;
Begin
  ErrorText := '';
  Result := False;
  If Not Assigned(Form) Then
    Exit;
  If Form.FPlanAgentRunning Then
    Begin
      ErrorText := 'A plan run is already active.';
      Exit(True);
    End;
  If Form.FSending Then
    Begin
      ErrorText := 'Wait for the current reply to finish.';
      Exit(True);
    End;
End;

Function PlanIsAvailable(Const RelativePath: String): Boolean;
Var
  Paths, Titles: TStringList;
  Missing: Boolean;
  Err, Wanted, Item: String;
  I: Integer;
Begin
  Result := False;
  Paths := Nil;
  Titles := Nil;
  Wanted := StringReplace(RelativePath, '\', '/', [rfReplaceAll]);
  If Wanted = '' Then
    Exit;
  If Not ListAvailableAssistantPlans(GetActivePlanRelativePath, Paths, Titles, Missing, Err) Then
    Begin
      Paths.Free;
      Titles.Free;
      Exit;
    End;
  Try
    For I := 0 To Paths.Count - 1 Do
      Begin
        Item := StringReplace(Paths[I], '\', '/', [rfReplaceAll]);
        If SameText(Item, Wanted) Then
          Exit(True);
      End;
  Finally
    Paths.Free;
    Titles.Free;
  End;
End;

Function FindMonitorTask(Const TaskId: String; Out Task: TAssistantTask; Out ErrorText: String): Boolean;
Var
  Tasks: TAssistantTaskArray;
  FromCatalog: Boolean;
  Index: Integer;
Begin
  Result := False;
  ErrorText := '';
  If Trim(TaskId) = '' Then
    Begin
      ErrorText := 'This task is not in the list.';
      Exit;
    End;
  If Not LoadAssistantTasks(Tasks, FromCatalog, ErrorText) Then
    Exit;
  Index := FindAssistantTask(Tasks, TaskId);
  If Index < 0 Then
    Begin
      ErrorText := 'This task is not in the list.';
      Exit;
    End;
  Task := Tasks[Index];
  Result := True;
End;

Function RefuseDesktopTask(Const Task: TAssistantTask; Out ErrorText: String): Boolean;
Begin
  Result := True;
  If Task.Kind = tkFormat Then
    ErrorText := 'Format tasks run on the desktop editor.'
  Else If Task.CompileFirst Then
    ErrorText := 'Tasks that compile first run on the desktop.'
  Else If Task.Hidden Then
    ErrorText := 'This task is hidden.'
  Else If Not Task.Enabled Then
    ErrorText := 'This task is disabled.'
  Else
    Result := False;
End;

Function TProjectAssistantForm.MonitorScreenReady: Boolean;
Begin
  Result := FMonitorBound And (Not (csDestroying In ComponentState));
End;

Procedure TProjectAssistantForm.FillMonitorIdentity(Out ConversationId, ProjectRoot, Title: String);
Begin
  ConversationId := '';
  ProjectRoot := '';
  Title := '';
  If Not Assigned(ProjectAssistantConversation) Then
    Exit;
  ProjectRoot := ProjectAssistantConversation.ProjectRoot;
  ConversationId := ProjectAssistantConversation.MonitorConversationId;
  Title := ProjectAssistantConversation.MonitorTitle;
End;

Procedure TProjectAssistantForm.FillMonitorView(Out View: TAssistantMonitorView);
Var
  Pct: Integer;
  Title, Err: String;
  SlotItem, UsageItem: TAccountUsageSnapshot;
Begin
  View.Available := True;
  View.Busy := FSending Or FPlanAgentRunning;
  View.Sending := FSending;
  View.ModeLocked := FModeLocked;
  View.PlanRunning := FPlanAgentRunning;
  View.Mode := AssistantModeToStr(ActiveMode);
  View.ElapsedMs := 0;
  View.StartedAt := '';
  View.Phase := '';
  If FSending Then
    Begin
      View.Phase := AssistantProgressPhase(FStatusPhase);
      View.ElapsedMs := CurrentStreamDurationMs;
      View.StartedAt := FTurnStartedAt;
      View.StatusText := FormatElapsedStatus(View.Phase);
    End
  Else If ((FActiveBackend = 'codex') And (FCodexRuntime <> '') And (FCodexModel <> '')) Or
    ((FActiveBackend = 'claude') And (FClaudeRuntime <> '') And (FClaudeModel <> '')) Or
    ((FActiveBackend <> 'codex') And (FActiveBackend <> 'claude') And Assigned(AssistantChatConfig) And AssistantChatConfig.IsSignedIn) Then
    View.StatusText := AssistantStatusReady
  Else
    View.StatusText := AssistantStatusOffline;
  View.Model := Trim(FActiveModel);
  If View.Model = '' Then
    View.Model := Trim(FModelName);
  If View.Model = '' Then
    View.Model := 'Model';
  View.Backend := FActiveBackend;
  View.SignedIn := ((FActiveBackend = 'codex') And (FCodexRuntime <> '') And (FCodexModel <> '')) Or
    ((FActiveBackend = 'claude') And (FClaudeRuntime <> '') And (FClaudeModel <> '')) Or
    ((FActiveBackend <> 'codex') And (FActiveBackend <> 'claude') And Assigned(AssistantChatConfig) And AssistantChatConfig.IsSignedIn);
  View.ApprovalCaption := ApprovalModeCaption(StrToApprovalMode(FActiveApproval));
  If AssistantShowsEffort(FActiveBackend) Then
    View.Effort := EffortBarCaption(FActiveEffort)
  Else
    View.Effort := '—';
  View.Skill := ModeSkillCaption;
  If FContextLimit > 0 Then
    Pct := (FContextUsed * 100) Div FContextLimit
  Else
    Pct := 0;
  If Pct > 999 Then
    Pct := 999;
  If (FActiveBackend = 'codex') Then
    View.ContextText := CodexContextCaption(FCodexContextUsage, FContextUsed)
  Else If (FActiveBackend = 'claude') Then
    View.ContextText := Format('Context ~%d tokens', [FContextUsed])
  Else
    Begin
      View.ContextText := Format('Context %d%%', [Pct]);
      If Pct >= 95 Then
        View.ContextText := View.ContextText + ' ⚠';
    End;
  { Same caption and hint the desktop Credits click shows. Empty when this connection has no figure. }
  ClearAccountUsageSnapshot(SlotItem);
  If Assigned(FAccountUsageSlot) Then
    SlotItem := FAccountUsageSlot.ReadSnapshot;
  UsageItem := AccountUsageForFooter(FActiveConnectionId, SlotItem);
  View.UsageCaption := AccountUsageCaption(UsageItem, FActiveConnectionId);
  View.UsageHint := AccountUsageHint(UsageItem, FActiveConnectionId);
  View.TargetKind := TargetKindName;
  View.TargetDisplay := AssistantTarget.DisplayName;
  View.TargetRoot := AssistantTarget.Root;
  View.PlanPath := GetActivePlanRelativePath;
  View.PlanTitle := '';
  If (View.PlanPath <> '') And TryReadAssistantPlanIdentity(View.PlanPath, Title, Err) Then
    View.PlanTitle := Title;
  View.CanSend := TurnEngineReady And (Not FSending) And (Not FPlanAgentRunning);
  View.UnavailableSentence := AssistantTurnUnavailableSentence(FActiveBackend);
  View.CanSteer := FSending And AssistantCanSteer(FActiveBackend) And (Not FTransportWait);
  View.CanStop := FSending;
  View.CanChangeMode := Not (FSending Or FModeLocked);
  View.RemoteApproval := False;
  View.ErrorText := '';
End;

Function TProjectAssistantForm.FillMonitorTurn(TurnIndex: Integer; Out Turn: TAssistantMonitorTurn;
  Out ErrorText: String): Boolean;
Var
  Stored: TConversationTurn;
  Trace: TAssistantTrace;
  StoreDir: String;
  Entry: TConversationIndexEntry;
  Seen: TStringList;
  StoredIndex: Integer;

  Procedure ClearTurn;
  Begin
    Turn.TurnIndex := TurnIndex;
    Turn.Id := '';
    Turn.Mode := '';
    Turn.Prompt := '';
    Turn.Thinking := '';
    Turn.Response := '';
    Turn.ErrorText := '';
    Turn.CreatedAt := '';
    Turn.DurationMs := 0;
    Turn.PromptPreview := '';
    Turn.Live := False;
    SetLength(Turn.Blocks, 0);
    SetLength(Turn.Images, 0);
  End;

  Function ImageSeen(Const ImageId: String): Boolean;
  Begin
    Result := (ImageId <> '') And (Seen.IndexOf(ImageId) >= 0);
  End;

  Procedure AddTurnImage(Const Id, Name, Mime, DisplayPath: String; ImageWidth, ImageHeight: Integer);
  Var
    N: Integer;
  Begin
    If (Id = '') Or ImageSeen(Id) Then
      Exit;
    Seen.Add(Id);
    N := Length(Turn.Images);
    SetLength(Turn.Images, N + 1);
    Turn.Images[N].Id := Id;
    Turn.Images[N].Name := Name;
    Turn.Images[N].Mime := Mime;
    Turn.Images[N].Width := ImageWidth;
    Turn.Images[N].Height := ImageHeight;
    Turn.Images[N].DisplayPath := DisplayPath;
    Turn.Images[N].Missing := Not AssistantImageDisplayPresent(StoreDir, Id, DisplayPath);
  End;

  Procedure CopyTrace(Source: TAssistantTrace);
  Var
    I, J, N: Integer;
    Block: TTraceBlock;
    Refs: TAssistantImageRefArray;
  Begin
    If Not Assigned(Source) Then
      Exit;
    SetLength(Turn.Blocks, Source.Count);
    For I := 0 To Source.Count - 1 Do
      Begin
        Block := Source[I];
        Turn.Blocks[I].Kind := TraceKindName(Block.Kind);
        Turn.Blocks[I].BlockId := Block.ID;
        Turn.Blocks[I].Title := Block.Title;
        Turn.Blocks[I].ToolName := Block.ToolName;
        Turn.Blocks[I].ToolId := Block.ToolId;
        Turn.Blocks[I].Body := Block.Body;
        Turn.Blocks[I].Running := Block.Running;
        Turn.Blocks[I].Ok := Block.Ok;
        Turn.Blocks[I].DurationMs := Block.DurationMs;
        Turn.Blocks[I].Revision := Block.Revision;
        SetLength(Turn.Blocks[I].Images, Length(Block.ImageRefs));
        For J := 0 To High(Block.ImageRefs) Do
          Begin
            Turn.Blocks[I].Images[J].Id := Block.ImageRefs[J].Id;
            Turn.Blocks[I].Images[J].Name := Block.ImageRefs[J].Name;
            Turn.Blocks[I].Images[J].Mime := '';
            Turn.Blocks[I].Images[J].Width := Block.ImageRefs[J].Width;
            Turn.Blocks[I].Images[J].Height := Block.ImageRefs[J].Height;
            Turn.Blocks[I].Images[J].DisplayPath := Block.ImageRefs[J].DisplayPath;
            Turn.Blocks[I].Images[J].Missing := Not AssistantImageDisplayPresent(StoreDir, Block.ImageRefs[J].Id,
              Block.ImageRefs[J].DisplayPath);
            AddTurnImage(Block.ImageRefs[J].Id, Block.ImageRefs[J].Name, '', Block.ImageRefs[J].DisplayPath,
              Block.ImageRefs[J].Width, Block.ImageRefs[J].Height);
          End;
      End;
    SetLength(Refs, 0);
    If ParseAssistantImageRefs(Stored.AttachmentsJson, Refs) Then
      For N := 0 To High(Refs) Do
        AddTurnImage(Refs[N].Id, Refs[N].Name, Refs[N].Mime, Refs[N].DisplayPath, Refs[N].Width, Refs[N].Height);
  End;

Begin
  Result := False;
  ErrorText := '';
  Stored := Default(TConversationTurn);
  ClearTurn;
  StoreDir := '';
  If Assigned(ProjectAssistantConversation) Then
    StoreDir := ProjectAssistantConversation.AssistantDirectory;
  Seen := TStringList.Create;
  Trace := Nil;
  Try
    Seen.CaseSensitive := True;
    If TurnIndex = LiveConversationMarker Then
      Begin
        { The window shows the stored conversation while idle. The in-flight trace is empty until the next send.
          A plan run keeps notes on that trace between turns. The stored row does not have them yet. }
        If (Not FSending) And (Not (FStreamingActive And (Not FTurnRecorded))) And (Not FPlanAgentRunning) And
          Assigned(ProjectAssistantConversation) And (ProjectAssistantConversation.TurnCount > 0) Then
          Begin
            StoredIndex := FSelectedTurnIndex;
            If (StoredIndex < 0) Or (StoredIndex >= ProjectAssistantConversation.TurnCount) Then
              StoredIndex := ProjectAssistantConversation.TurnCount - 1;
            If FillMonitorTurn(StoredIndex, Turn, ErrorText) Then
              Begin
                Turn.Live := True;
                ErrorText := '';
                Result := True;
                Exit;
              End;
          End;
        Turn.Live := True;
        Turn.Id := MonitorLiveTurnId;
        Turn.Mode := AssistantModeToStr(ActiveMode);
        Turn.Prompt := FLiveUser;
        If Turn.Prompt = '' Then
          Turn.Prompt := FDisplayUser;
        Turn.Thinking := FLiveThinking;
        If Turn.Thinking = '' Then
          Turn.Thinking := FAssistantThinking;
        Turn.Response := FLiveContent;
        If Turn.Response = '' Then
          Turn.Response := FAssistantContent;
        If FSending Then
          Turn.DurationMs := CurrentStreamDurationMs;
        Turn.PromptPreview := ShortPreview(Turn.Prompt);
        CopyTrace(FTrace);
        Result := True;
        Exit;
      End;
    If Not Assigned(ProjectAssistantConversation) Or Not ProjectAssistantConversation.GetTurn(TurnIndex, Stored) Then
      Begin
        ErrorText := 'That turn is not in this conversation.';
        Exit;
      End;
    Turn.Id := Stored.Id;
    Turn.Mode := Stored.Mode;
    Turn.Prompt := Stored.Prompt;
    Turn.Thinking := Stored.Thinking;
    Turn.Response := Stored.Response;
    Turn.ErrorText := Stored.ErrorText;
    Turn.CreatedAt := Stored.CreatedAt;
    Turn.DurationMs := Stored.DurationMs;
    Turn.Live := False;
    If (TurnIndex >= 0) And (TurnIndex < ProjectAssistantConversation.IndexCount) Then
      Begin
        Entry := ProjectAssistantConversation.IndexEntry(TurnIndex);
        If Assigned(Entry) Then
          Turn.PromptPreview := Entry.PromptPreview;
      End;
    If Turn.PromptPreview = '' Then
      Turn.PromptPreview := ShortPreview(Stored.Prompt);
    Trace := TAssistantTrace.Create;
    If Stored.TraceJson <> '' Then
      Trace.LoadFromJson(Stored.TraceJson);
    If (Trace.Count = 0) And (Stored.EventsFile <> '') Then
      Trace.ReplayFromEventsFile(IncludeTrailingPathDelimiter(ProjectAssistantConversation.ProjectRoot) + Stored.EventsFile,
        Stored.Prompt, Stored.Thinking, Stored.Response);
    If Trace.Count = 0 Then
      Begin
        Trace.EnsureUser(Stored.Prompt);
        If Trim(Stored.Thinking) <> '' Then
          Begin
            Trace.StartThinking(0).Body := Stored.Thinking;
            Trace.FinishCurrentThinking;
          End;
        If Stored.Response <> '' Then
          Trace.EnsureAnswer.Body := Stored.Response;
        If Stored.ErrorText <> '' Then
          Trace.AddNote('**Error:** ' + Stored.ErrorText);
      End;
    CopyTrace(Trace);
    Result := True;
  Finally
    Trace.Free;
    Seen.Free;
  End;
End;

Function TProjectAssistantForm.FillMonitorLiveChanges(Const SentBlocks: Array Of TAssistantMonitorBlock;
  Out Turn: TAssistantMonitorTurn; Out ErrorText: String): Boolean;
Var
  I, J, ImageCount: Integer;
  Block: TTraceBlock;
  Found: Boolean;
  StoreDir: String;
  Seen: TStringList;
  Known: TAssistantMonitorImage;

  Function SameFace(Const Left: TAssistantMonitorBlock; Const Right: TTraceBlock): Boolean;
  Begin
    Result := (Length(Left.Body) = Length(Right.Body)) And (Left.Running = Right.Running);
  End;

  Function KnownImage(Const ImageId: String; Out Image: TAssistantMonitorImage): Boolean;
  Var
    BlockIndex, ImageIndex: Integer;
  Begin
    Result := False;
    Image := Default(TAssistantMonitorImage);
    If ImageId = '' Then
      Exit;
    For BlockIndex := 0 To High(SentBlocks) Do
      For ImageIndex := 0 To High(SentBlocks[BlockIndex].Images) Do
        If SentBlocks[BlockIndex].Images[ImageIndex].Id = ImageId Then
          Begin
            Image := SentBlocks[BlockIndex].Images[ImageIndex];
            Exit(True);
          End;
  End;

  Procedure AddTurnImage(Const Image: TAssistantMonitorImage);
  Begin
    If (Image.Id = '') Or (Seen.IndexOf(Image.Id) >= 0) Then
      Exit;
    Seen.Add(Image.Id);
    ImageCount := Length(Turn.Images);
    SetLength(Turn.Images, ImageCount + 1);
    Turn.Images[ImageCount] := Image;
  End;

Begin
  Result := False;
  ErrorText := '';
  { Idle and stored turns are not the streaming path. The full copy is cheap there. }
  If (Not FSending) And (Not (FStreamingActive And (Not FTurnRecorded))) And (Not FPlanAgentRunning) Then
    Begin
      Result := FillMonitorTurn(LiveConversationMarker, Turn, ErrorText);
      Exit;
    End;
  Turn.TurnIndex := LiveConversationMarker;
  Turn.Live := True;
  Turn.Id := MonitorLiveTurnId;
  Turn.Mode := AssistantModeToStr(ActiveMode);
  Turn.Prompt := FLiveUser;
  If Turn.Prompt = '' Then
    Turn.Prompt := FDisplayUser;
  Turn.Thinking := FLiveThinking;
  If Turn.Thinking = '' Then
    Turn.Thinking := FAssistantThinking;
  Turn.Response := FLiveContent;
  If Turn.Response = '' Then
    Turn.Response := FAssistantContent;
  Turn.ErrorText := '';
  Turn.CreatedAt := FTurnStartedAt;
  Turn.DurationMs := 0;
  If FSending Then
    Turn.DurationMs := CurrentStreamDurationMs;
  Turn.PromptPreview := ShortPreview(Turn.Prompt);
  SetLength(Turn.Images, 0);
  If Not Assigned(FTrace) Then
    Begin
      SetLength(Turn.Blocks, 0);
      Result := True;
      Exit;
    End;
  StoreDir := '';
  If Assigned(ProjectAssistantConversation) Then
    StoreDir := ProjectAssistantConversation.AssistantDirectory;
  Seen := TStringList.Create;
  Try
    Seen.CaseSensitive := True;
    SetLength(Turn.Blocks, FTrace.Count);
    For I := 0 To FTrace.Count - 1 Do
      Begin
        Block := FTrace[I];
        Turn.Blocks[I].Kind := TraceKindName(Block.Kind);
        Turn.Blocks[I].BlockId := Block.ID;
        Turn.Blocks[I].Title := Block.Title;
        Turn.Blocks[I].ToolName := Block.ToolName;
        Turn.Blocks[I].ToolId := Block.ToolId;
        Turn.Blocks[I].Running := Block.Running;
        Turn.Blocks[I].Ok := Block.Ok;
        Turn.Blocks[I].DurationMs := Block.DurationMs;
        Turn.Blocks[I].Revision := Block.Revision;
        SetLength(Turn.Blocks[I].Images, Length(Block.ImageRefs));
        For J := 0 To High(Block.ImageRefs) Do
          Begin
            Turn.Blocks[I].Images[J].Id := Block.ImageRefs[J].Id;
            Turn.Blocks[I].Images[J].Name := Block.ImageRefs[J].Name;
            Turn.Blocks[I].Images[J].Mime := '';
            Turn.Blocks[I].Images[J].Width := Block.ImageRefs[J].Width;
            Turn.Blocks[I].Images[J].Height := Block.ImageRefs[J].Height;
            Turn.Blocks[I].Images[J].DisplayPath := Block.ImageRefs[J].DisplayPath;
            If KnownImage(Block.ImageRefs[J].Id, Known) Then
              Turn.Blocks[I].Images[J].Missing := Known.Missing
            Else
              Turn.Blocks[I].Images[J].Missing := Not AssistantImageDisplayPresent(StoreDir, Block.ImageRefs[J].Id,
                Block.ImageRefs[J].DisplayPath);
            AddTurnImage(Turn.Blocks[I].Images[J]);
          End;
        Found := False;
        For J := 0 To High(SentBlocks) Do
          If SentBlocks[J].BlockId = Block.ID Then
            Begin
              Found := True;
              If SameFace(SentBlocks[J], Block) Then
                Turn.Blocks[I].Body := SentBlocks[J].Body
              Else
                Turn.Blocks[I].Body := Block.Body;
              Break;
            End;
        If Not Found Then
          Turn.Blocks[I].Body := Block.Body;
      End;
    Result := True;
  Finally
    Seen.Free;
  End;
End;

Procedure TProjectAssistantForm.FillMonitorPlanChoices(Paths, Captions: TStrings);
Begin
  Paths.Clear;
  Captions.Clear;
  If Not Assigned(ActivePlanCombo) Or Not Assigned(ActivePlanPaths) Then
    Exit;
  Paths.Assign(ActivePlanPaths);
  Captions.Assign(ActivePlanCombo.Items);
End;

Procedure TProjectAssistantForm.FillMonitorPlan(Out Rows: TAssistantMonitorPlanRows);
Var
  I: Integer;
  Section: TPlanSection;
Begin
  SetLength(Rows, 0);
  If Not Assigned(BuildSections) Then
    Exit;
  SetLength(Rows, BuildSections.Count);
  For I := 0 To BuildSections.Count - 1 Do
    Begin
      Section := TPlanSection(BuildSections[I]);
      Rows[I].Index := I;
      Rows[I].Level := Section.HeadingLevel;
      Rows[I].Title := Section.Title;
      Rows[I].ParentTitle := Section.ParentTitle;
      If Section.Status = pssUnknown Then
        Rows[I].Status := 'unknown'
      Else
        Rows[I].Status := PlanSectionStatusToStr(Section.Status);
      Rows[I].Actionable := Section.Actionable;
    End;
End;

Function TProjectAssistantForm.ReadMonitorPlanPreview: String;
Var
  Truncated: Boolean;
Begin
  Result := ReadAssistantPlanDocument(GetActivePlanRelativePath, Truncated);
  If Truncated And (Result <> '') Then
    Result := Result + LineEnding + LineEnding + 'The rest of the plan is on the desktop.';
End;

Procedure TProjectAssistantForm.FillMonitorTasks(Out Rows: TAssistantMonitorTaskRows);
Var
  Tasks: TAssistantTaskArray;
  FromCatalog: Boolean;
  ErrorText: String;
  I: Integer;
Begin
  SetLength(Rows, 0);
  If Not LoadAssistantTasks(Tasks, FromCatalog, ErrorText) Then
    Exit;
  SetLength(Rows, Length(Tasks));
  For I := 0 To High(Tasks) Do
    Begin
      Rows[I].Id := Tasks[I].Id;
      Rows[I].Title := Tasks[I].Title;
      Rows[I].Summary := Tasks[I].Summary;
      Rows[I].Mode := TaskModeToStr(Tasks[I].Mode);
      Rows[I].Kind := TaskKindToStr(Tasks[I].Kind);
      Rows[I].Scope := TaskScopeToStr(Tasks[I].Scope);
      Rows[I].CompileFirst := Tasks[I].CompileFirst;
      Rows[I].Enabled := Tasks[I].Enabled;
      Rows[I].NeedsNote := AssistantTaskNeedsUserNote(Tasks[I]);
    End;
End;

Function TProjectAssistantForm.RemoteSubmit(Const MessageText: String; SaveFirst: Boolean; Out ErrorText: String): Boolean;
Begin
  BeginRemoteTurn(SaveFirst);
  Try
    Result := RemoteSubmitText(MessageText, ErrorText);
  Finally
    EndRemoteTurn(ErrorText);
  End;
End;

Function TProjectAssistantForm.RemoteSubmitText(Const MessageText: String; Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := '';
  If Trim(MessageText) = '' Then
    Begin
      ErrorText := 'The message is empty.';
      Exit;
    End;
  If ThisFormBusy(Self, ErrorText) Then
    Exit;
  If Not TurnEngineReady Then
    Begin
      ErrorText := AssistantTurnUnavailableSentence(FActiveBackend);
      Exit;
    End;
  If Not SubmitUserTextEx(Trim(MessageText), Trim(MessageText), True) Then
    Begin
      If Assigned(AssistantClient) And (AssistantClient.LastError <> '') Then
        ErrorText := AssistantClient.LastError
      Else
        ErrorText := 'The message was not sent.';
      Exit;
    End;
  Result := True;
End;

Function TProjectAssistantForm.RemoteSteer(Const MessageText: String; Out ErrorText: String): Boolean;
Var
  Refs: TAssistantImageRefArray;
Begin
  Result := False;
  ErrorText := '';
  SetLength(Refs, 0);
  If Trim(MessageText) = '' Then
    Begin
      ErrorText := 'The message is empty.';
      Exit;
    End;
  If Not FSending Then
    Begin
      ErrorText := 'Nothing is running to steer.';
      Exit;
    End;
  If Not AssistantCanSteer(FActiveBackend) Then
    Begin
      ErrorText := AssistantCapabilitySentence(FActiveBackend, acSteer);
      Exit;
    End;
  If FTransportWait Then
    Begin
      ErrorText := 'This connection cannot steer.';
      Exit;
    End;
  If (FActiveBackend = 'codex') Then
    Begin
      If Not Assigned(FCodexRun) Or Not FCodexRun.Steer(Trim(MessageText)) Then
        Begin
          If Assigned(FCodexRun) And (FCodexRun.LastSteerError <> '') Then
            ErrorText := FCodexRun.LastSteerError
          Else
            ErrorText := 'This connection cannot steer.';
          Exit;
        End;
    End
  Else If (Not Assigned(AssistantClient)) Or (Not AssistantClient.EnqueueSteer(Trim(MessageText), Refs)) Then
    Begin
      ErrorText := 'The steer could not be queued.';
      Exit;
    End;
  SetStreamPhase(AssistantPhaseSteering);
  WorkflowLogger.Info('ProjectAssistant', 'Steer queued (' + IntToStr(Length(Trim(MessageText))) + ' chars)');
  Result := True;
End;

Function TProjectAssistantForm.RemoteStop(Out ErrorText: String): Boolean;
Begin
  ErrorText := '';
  If FSending Then
    StopStream;
  Result := True;
End;

Function TProjectAssistantForm.RemoteSelectMode(Const ModeText: String; Out ErrorText: String): Boolean;
Var
  Mode: TAssistantMode;
Begin
  Result := False;
  ErrorText := '';
  If FSending Or FModeLocked Then
    Begin
      ErrorText := 'Wait for the current reply to finish.';
      Exit;
    End;
  If Not KnownMonitorMode(ModeText, Mode) Then
    Begin
      ErrorText := 'Unknown mode.';
      Exit;
    End;
  SelectMode(Mode);
  Result := True;
End;

Function TProjectAssistantForm.RemoteNewConversation(Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := '';
  If ThisFormBusy(Self, ErrorText) Then
    Exit;
  If (Not Assigned(ProjectAssistantConversation)) Or (ProjectAssistantConversation.ProjectRoot = '') Then
    Begin
      ErrorText := 'No project is open.';
      Exit;
    End;
  { Keep the mode already selected. Phone New must not drop Build back to Chat. }
  Result := StartNewChat(False, False);
  If Result Then
    Exit;
  If ProjectAssistantConversation.LastError <> '' Then
    ErrorText := ProjectAssistantConversation.LastError
  Else
    ErrorText := 'Could not start a new conversation.';
End;

Function TProjectAssistantForm.RemoteSelectPlan(Const RelativePath: String; Out ErrorText: String): Boolean;
Var
  Index: Integer;
Begin
  Result := False;
  ErrorText := '';
  If ThisFormBusy(Self, ErrorText) Then
    Exit;
  If FReviewInProgress Then
    Begin
      ErrorText := 'Wait for the current review to finish.';
      Exit;
    End;
  RefreshActivePlanChoices(Nil);
  If Not Assigned(ActivePlanCombo) Or Not Assigned(ActivePlanPaths) Then
    Exit;
  Index := ActivePlanPaths.IndexOf(RelativePath);
  If Index < 0 Then
    Begin
      ErrorText := 'That plan is no longer in the desktop plan selector.';
      Exit;
    End;
  ActivePlanCombo.ItemIndex := Index;
  ActivePlanChoiceChanged(ActivePlanCombo);
  RefreshActivePlanChoices(Nil);
  Result := True;
End;

Function TProjectAssistantForm.RemoteNewPlan(Const Title: String; Out ErrorText: String): Boolean;
Var
  PlanTitle, Rel, Resolved, Err, Content: String;
Begin
  Result := False;
  ErrorText := '';
  If FSending Then
    Begin
      ErrorText := 'Wait for the current reply to finish.';
      Exit;
    End;
  PlanTitle := Trim(Title);
  If PlanTitle = '' Then
    PlanTitle := 'Project Plan';
  Rel := DefaultPlanRelativePath;
  If FileExistsUTF8(ExpandFileName(ProjectRootPath + Rel)) Or
    FileExistsUTF8(ExpandFileName(ProjectRootPath + StringReplace(Rel, '/', PathDelim, [rfReplaceAll]))) Then
    Rel := AssistantDocumentsDirName + PathDelim + 'Plan-' + FormatDateTime('yyyymmdd-hhnnss', Now) + '.md';
  Content := DefaultNewPlanMarkdown(PlanTitle);
  If Not WriteMarkdownFile(Rel, Content, Resolved, Err) Then
    Begin
      ErrorText := Err;
      Exit;
    End;
  SetActivePlanRelativePath(ProjectRelativePath(Resolved));
  PersistShellConfig;
  RefreshActivePlanChoices(Nil);
  RefreshBuildTodos;
  UpdateWorkActions;
  If Not AddAvailableAssistantPlan(Resolved, Err) Then
    Begin
      ErrorText := Err;
      Exit;
    End;
  SelectMode(amPlan);
  SetCurrentSystemNote('Created plan **' + GetActivePlanRelativePath +
    '**. Stay in **Plan** mode and send a message to refine it with the model.');
  Result := True;
End;

Function TProjectAssistantForm.RemoteClosePlan(Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := '';
  If ThisFormBusy(Self, ErrorText) Then
    Exit;
  Result := CloseActivePlan(ErrorText);
End;

Function TProjectAssistantForm.RemoteWorkOnPlan(SectionIndex: Integer; Out ErrorText: String): Boolean;
Var
  PlanRel, Err, Body, Prompt, Title, StatusText, ParentTitle: String;
  Section: TPlanSection;
Begin
  Result := False;
  ErrorText := '';
  If FSending Then
    Begin
      ErrorText := 'Wait for the current reply to finish (or Stop) before starting work.';
      Exit;
    End;
  PlanRel := GetActivePlanRelativePath;
  If PlanRel = '' Then
    Begin
      ErrorText := 'Set an active plan on the Plan tab first.';
      Exit;
    End;
  If Not Assigned(BuildSections) Or (SectionIndex < 0) Or (SectionIndex >= BuildSections.Count) Or
    (Not TPlanSection(BuildSections[SectionIndex]).Actionable) Then
    Begin
      If Assigned(BuildSections) And (SectionIndex >= 0) And (SectionIndex < BuildSections.Count) And
        (Not TPlanSection(BuildSections[SectionIndex]).Actionable) Then
        ErrorText := 'Select an actionable item (### with Status), not a section heading.'
      Else
        ErrorText := 'Select an actionable item in the list.';
      Exit;
    End;
  Section := TPlanSection(BuildSections[SectionIndex]);
  Title := Section.Title;
  ParentTitle := Section.ParentTitle;
  StatusText := PlanSectionStatusToStr(Section.Status);
  If Section.Status = pssUnknown Then
    StatusText := 'unknown';
  If Section.Status In [pssNotStarted, pssUnknown, pssBlocked] Then
    Begin
      If Not SetPlanSectionStatus(PlanRel, SectionIndex, pssInProgress, Err) Then
        SetCurrentSystemNote('Could not set status to in progress:' + LineEnding + Err)
      Else
        Begin
          StatusText := PlanSectionStatusToStr(pssInProgress);
          FBuildSelectedIndex := SectionIndex;
          RefreshBuildTodos;
          If Assigned(BuildTodoList) And (SectionIndex < BuildTodoList.Items.Count) Then
            BuildTodoList.ItemIndex := SectionIndex;
        End;
    End;
  If Not GetPlanSectionBody(PlanRel, SectionIndex, Body, Err) Then
    Begin
      ErrorText := 'Could not load plan section:' + LineEnding + Err;
      Exit;
    End;
  Prompt := BuildWorkPrompt(PlanRel, Title, StatusText, Body, ParentTitle,
    FPlanAgentRunning And (SectionIndex = FPlanAgentResumeIndex));
  FPlanAgentResumeIndex := -1;
  BeginBuildWorkTracking(SectionIndex, Title);
  ForceModeAndLock(amBuild);
  ShowChatSurfaceKeepMode;
  SetBuildStatusFeedback('Working on: ' + Title);
  If Not SubmitUserText(Prompt, True) Then
    Begin
      UnlockModeAfterSend;
      ClearBuildWorkTracking;
      ErrorText := 'The message was not sent.';
      Exit;
    End;
  Result := True;
End;

Function TProjectAssistantForm.RemoteRunPlan(SaveFirst: Boolean; Out ErrorText: String): Boolean;
Begin
  BeginRemoteTurn(SaveFirst);
  Try
    Result := StartRemoteRunPlan(ErrorText);
  Finally
    EndRemoteTurn(ErrorText);
  End;
End;

Function TProjectAssistantForm.StartRemoteRunPlan(Out ErrorText: String): Boolean;
Var
  Idx: Integer;
Begin
  Result := False;
  ErrorText := '';
  If FSending Or FPlanAgentRunning Then
    Begin
      ErrorText := 'Wait for the current reply to finish before starting Run Plan.';
      Exit;
    End;
  If Not TurnEngineReady Then
    Begin
      UpdateWorkActions;
      ErrorText := AssistantTurnUnavailableSentence(FActiveBackend);
      Exit;
    End;
  If Not RunPlanIsAvailable Then
    Begin
      UpdateWorkActions;
      ErrorText := 'Set an active plan first.';
      Exit;
    End;
  SelectMode(amBuild);
  RefreshBuildTodos;
  Idx := FindNextIncompleteBuildSection;
  If Idx < 0 Then
    Begin
      ErrorText := AssistantPlanRunStartMessage(CollectPlanRunReportFacts(preCleanFinish, ''));
      Exit;
    End;
  { Before the run starts. A refusal leaves its reason for EndRemoteTurn. }
  If Not ConfirmSavedBeforeTurn(amBuild) Then
    Exit;
  FPlanAgentRunning := True;
  FPlanRunStartTick := GetTickCount64;
  AssistantSessionObserve.AssistantSessionObserve(asnPlan);
  SyncCodexUsageIdle;
  SetAssistantPlanViewerQuiet(True);
  FPlanAgentPackagesDone := 0;
  FPlanAgentResumeIndex := -1;
  FLastTurnHadError := False;
  FPlanNewChatThisStep := False;
  MarkPlanAgentAlive;
  FBuildSelectedIndex := Idx;
  If Assigned(BuildTodoList) And (Idx < BuildTodoList.Items.Count) Then
    BuildTodoList.ItemIndex := Idx;
  SetBuildStatusFeedback('Plan agent: starting…');
  SetCurrentSystemNote(
    '**Plan agent** started — will work through incomplete packages until complete, error, ' +
    'context ≥ 95%, or max packages.');
  If Not RemoteWorkOnPlan(Idx, ErrorText) Then
    Begin
      StopRunPlan(preError, 'Could not start the first package.');
      If ErrorText = '' Then
        ErrorText := 'Could not start the first package.';
      Exit;
    End;
  Result := True;
End;

Function TProjectAssistantForm.RemoteStopPlan(Out ErrorText: String): Boolean;
Begin
  ErrorText := '';
  If FPlanAgentRunning Then
    StopRunPlan(preUserStop, 'stopped by user');
  Result := True;
End;

Function TProjectAssistantForm.RemoteRunTask(Const TaskId, Note: String; SaveFirst: Boolean; Out ErrorText: String): Boolean;
Begin
  BeginRemoteTurn(SaveFirst);
  Try
    Result := StartRemoteTask(TaskId, Note, ErrorText);
  Finally
    EndRemoteTurn(ErrorText);
  End;
End;

Function TProjectAssistantForm.StartRemoteTask(Const TaskId, Note: String; Out ErrorText: String): Boolean;
Var
  Task: TAssistantTask;
  Request: TAssistantTaskRequest;
Begin
  Result := False;
  ErrorText := '';
  If Not TurnEngineReady Then
    Begin
      ErrorText := AssistantTurnUnavailableSentence(FActiveBackend);
      Exit;
    End;
  If Not FindMonitorTask(TaskId, Task, ErrorText) Then
    Exit;
  If RefuseDesktopTask(Task, ErrorText) Then
    Exit;
  If HostIsBusy(ErrorText) Then
    Begin
      If ErrorText = '' Then
        ErrorText := 'Wait for the current reply to finish.';
      Exit;
    End;
  If PrepareAssistantTaskRunWithNote(Task, trkRun, Note, Request, ErrorText) <> tpReady Then
    Exit;
  ApplyPreparedTaskRequest(Self, Request);
  Result := FSending;
  If Not Result Then
    ErrorText := 'The task did not start.';
End;

Function TProjectAssistantForm.RemoteInsertTask(Const TaskId, Note: String; Out ApiText, ErrorText: String): Boolean;
Var
  Task: TAssistantTask;
  Request: TAssistantTaskRequest;
Begin
  Result := False;
  ApiText := '';
  ErrorText := '';
  If Not FindMonitorTask(TaskId, Task, ErrorText) Then
    Exit;
  If RefuseDesktopTask(Task, ErrorText) Then
    Exit;
  If HostIsBusy(ErrorText) Then
    Begin
      If ErrorText = '' Then
        ErrorText := 'Wait for the current reply to finish.';
      Exit;
    End;
  If PrepareAssistantTaskRunWithNote(Task, trkInsert, Note, Request, ErrorText) <> tpReady Then
    Exit;
  ApiText := Request.ApiText;
  Result := ApiText <> '';
  If Not Result Then
    ErrorText := 'The task did not expand.';
End;

Function TProjectAssistantForm.RemoteTurn(TurnIndex: Integer; Out Turn: TAssistantMonitorTurn;
  Out ErrorText: String): Boolean;
Begin
  Result := FillMonitorTurn(TurnIndex, Turn, ErrorText);
End;

Function TProjectAssistantForm.RemoteImage(TurnIndex: Integer; Const ImageId: String; Out Data: TBytes;
  Out Mime: String; Out ImageWidth, ImageHeight: Integer; Out ErrorText: String): Boolean;
Const
  { Newest stored turns searched when the picture is not on the turn the phone named. }
  StoredTurnsSearched = 16;
Var
  Image: TAssistantMonitorImage;
  Refs: TAssistantImageRefArray;
  I, Searched: Integer;
  Found: Boolean;
  StoreDir, ReadError: String;

  Function Usable(Const Candidate: TAssistantMonitorImage): Boolean;
  Begin
    Result := (Candidate.Id = ImageId) And (Not Candidate.Missing) And (Candidate.DisplayPath <> '');
  End;

  Function FindInTurn(Index: Integer): Boolean;
  Var
    Turn: TAssistantMonitorTurn;
    TurnError: String;
    K, J: Integer;
  Begin
    Result := False;
    If Not FillMonitorTurn(Index, Turn, TurnError) Then
      Exit;
    For K := 0 To High(Turn.Images) Do
      If Usable(Turn.Images[K]) Then
        Begin
          Image := Turn.Images[K];
          Exit(True);
        End;
    For K := 0 To High(Turn.Blocks) Do
      For J := 0 To High(Turn.Blocks[K].Images) Do
        If Usable(Turn.Blocks[K].Images[J]) Then
          Begin
            Image := Turn.Blocks[K].Images[J];
            Exit(True);
          End;
  End;

  Function FindInPendingAttachments: Boolean;
  Var
    K: Integer;
  Begin
    Result := False;
    SetLength(Refs, 0);
    If Not ParseAssistantImageRefs(FPendingTurnAttachments, Refs) Then
      Exit;
    For K := 0 To High(Refs) Do
      If (Refs[K].Id = ImageId) And (Refs[K].DisplayPath <> '') And
        AssistantImageDisplayPresent(StoreDir, Refs[K].Id, Refs[K].DisplayPath) Then
        Begin
          Image := Default(TAssistantMonitorImage);
          Image.Id := Refs[K].Id;
          Image.Name := Refs[K].Name;
          Image.Mime := Refs[K].Mime;
          Image.Width := Refs[K].Width;
          Image.Height := Refs[K].Height;
          Image.DisplayPath := Refs[K].DisplayPath;
          Exit(True);
        End;
  End;

Begin
  Result := False;
  SetLength(Data, 0);
  Mime := '';
  ImageWidth := 0;
  ImageHeight := 0;
  ErrorText := 'missing';
  If ImageId = '' Then
    Exit;
  StoreDir := '';
  If Assigned(ProjectAssistantConversation) Then
    StoreDir := ProjectAssistantConversation.AssistantDirectory;
  Image := Default(TAssistantMonitorImage);
  Found := FindInTurn(TurnIndex);
  { The live turn's rows can change between the image notice and this request. Its own pictures are still in the
    pending attachments, and a turn that has just been recorded holds them under its stored index. }
  If (Not Found) And (TurnIndex < 0) Then
    Found := FindInPendingAttachments;
  If (Not Found) And Assigned(ProjectAssistantConversation) Then
    Begin
      Searched := 0;
      I := ProjectAssistantConversation.TurnCount - 1;
      While (Not Found) And (I >= 0) And (Searched < StoredTurnsSearched) Do
        Begin
          If I <> TurnIndex Then
            Begin
              Found := FindInTurn(I);
              Inc(Searched);
            End;
          Dec(I);
        End;
    End;
  If Not Found Then
    Exit;
  ErrorText := '';
  Mime := Image.Mime;
  ImageWidth := Image.Width;
  ImageHeight := Image.Height;
  If Not ReadStoredAssistantImage(ProjectRootPath, Image.DisplayPath, Data, ReadError) Then
    Begin
      SetLength(Data, 0);
      If Pos('larger than', ReadError) > 0 Then
        ErrorText := 'too_large'
      Else If Pos('missing', LowerCase(ReadError)) > 0 Then
        ErrorText := 'missing'
      Else
        ErrorText := 'refused';
      Exit;
    End;
  If Length(Data) > MonitorImageGetMaxBytes Then
    Begin
      SetLength(Data, 0);
      ErrorText := 'too_large';
      Exit;
    End;
  If Mime = '' Then
    MeasureStillImage(Data, Mime, ImageWidth, ImageHeight);
  Result := True;
End;

Function TProjectAssistantForm.RunAssistantModal(Const Msg: String; DlgType: TMsgDlgType; Buttons: TMsgDlgButtons;
  HelpCtx: Longint): Integer;
Begin
  BeginAssistantModal;
  Try
    Result := Dialogs.MessageDlg(Msg, DlgType, Buttons, HelpCtx);
  Finally
    EndAssistantModal;
  End;
End;

Function TProjectAssistantForm.RunAssistantModal(Const QueryCaption, Prompt: String; Var Value: String): Boolean;
Begin
  BeginAssistantModal;
  Try
    Result := Dialogs.InputQuery(QueryCaption, Prompt, Value);
  Finally
    EndAssistantModal;
  End;
End;

Initialization

QueryAssistantTaskHostBusy := @AssistantHostTurnOrPlanActive;
PostAssistantTaskSystemNote := @PostAssistantFormatNote;

End.
