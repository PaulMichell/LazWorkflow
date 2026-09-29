Unit ProjectAssistantForm;

{ Project Assistant main window — shared turn view, mode side panel, status footer (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. The IDE dock shell owns mode chips,
  history, plan/build tiles, send/steer, and catalog wiring as one form.
  Reviewed 2026-08: slash matching lives in AssistantCommands; trace paint in
  AssistantTraceView. Reviewed 2026-09-27: Chat is a fourth mode with no project
  tools or skill; the mode bar is a label and combobox. Composer attach, paste, and drop
  stay here because they are streamed controls. The image list holds pictures only;
  attach, remove, save, and preview are its popup. Decode stays in AssistantImages.
  The composer stack is positioned explicitly so showing the image list cannot
  reorder the text, buttons, or status bar. Paste reads pictures through the
  LCL clipboard, including PredefinedClipboardFormat(pcfBitmap), so Qt and GTK
  share one path. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Contnrs, Forms, Controls, Graphics, GraphType, Dialogs, ExtCtrls, StdCtrls,
  LCLType, Menus, ActnList, Clipbrd, WorkflowEvents, StatusFooterFrame, SpellMemo, CompOptsIntf,
  IDEExternToolIntf, AssistantConversation, AssistantPlan, AssistantEvents, AssistantTrace,
  AssistantTraceView, AssistantCommands, AssistantAcceptance, AssistantBuildJob, AssistantCodexRun, AssistantToolBroker,
  AssistantIDEWorkspace, AssistantGit;

Type
  TProjectAssistantForm = Class(TForm, ICompilerFinished, IMarkdownDocumentChanged)
    ActionList: TActionList;
    NewChatAction: TAction;
    AttachImageAction: TAction;
    RemoveAttachmentAction: TAction;
    SaveAttachmentAction: TAction;
    PreviewAttachmentAction: TAction;
    SendAction: TAction;
    SendButton: TButton;
    StopAction: TAction;
    ReviewCompileAction: TAction;
    ReviewBuildAction: TAction;
    ReviewChangesAction: TAction;
    FixErrorAction: TAction;
    SettingsAction: TAction;
    StopButton: TButton;
    ToggleThinkingAction: TAction;
    ToggleToolUseAction: TAction;
    ExportHistoryAction: TAction;
    DeleteHistoryAction: TAction;
    CommandsAction: TAction;
    ContextBreakdownAction: TAction;
    SessionInfoAction: TAction;
    ModelPickerAction: TAction;
    ThinkingPickerAction: TAction;
    SkillsPickerAction: TAction;
    CompactContextAction: TAction;
    CopyLastAnswerAction: TAction;
    OpenPlanAction: TAction;
    BuildThisAction: TAction;
    RevisePlanAction: TAction;
    ChatModeAction: TAction;
    InspectModeAction: TAction;
    PlanModeAction: TAction;
    BuildModeAction: TAction;
    ReviewButton: TButton;
    CommandsButton: TButton;
    ReviewMenu: TPopupMenu;
    ReviewCompileItem: TMenuItem;
    ReviewBuildItem: TMenuItem;
    ReviewChangesItem: TMenuItem;
    AssistantMenu: TMainMenu;
    SessionMenuItem: TMenuItem;
    NewChatMenuItem: TMenuItem;
    AttachImageMenuItem: TMenuItem;
    SendMenuItem: TMenuItem;
    StopMenuItem: TMenuItem;
    CompactMenuItem: TMenuItem;
    CopyLastMenuItem: TMenuItem;
    SessionSepItem: TMenuItem;
    ExportMenuItem: TMenuItem;
    DeleteMenuItem: TMenuItem;
    SessionSep2Item: TMenuItem;
    SettingsMenuItem: TMenuItem;
    WorkMenuItem: TMenuItem;
    OpenPlanMenuItem: TMenuItem;
    BuildThisMenuItem: TMenuItem;
    RevisePlanMenuItem: TMenuItem;
    ReviewMenuItem: TMenuItem;
    ReviewCompileMenuItem: TMenuItem;
    ReviewBuildMenuItem: TMenuItem;
    ReviewChangesMenuItem: TMenuItem;
    FixErrorMenuItem: TMenuItem;
    ViewMenuItem: TMenuItem;
    ToggleThinkingMenuItem: TMenuItem;
    ToggleToolUseMenuItem: TMenuItem;
    SkillsMenuItem: TMenuItem;
    ModelMenuItem: TMenuItem;
    ThinkingLevelMenuItem: TMenuItem;
    ContextBreakdownMenuItem: TMenuItem;
    SessionInfoMenuItem: TMenuItem;
    ClientPanel: TPanel;
    ModeSidePanel: TPanel;
    SidebarHeader: TPanel;
    ModePicker: TPanel;
    ModeLabel: TLabel;
    ModeCombo: TComboBox;
    ModeSplitter: TSplitter;
    ConversationPanel: TPanel;
    HistoryLabel: TLabel;
    HistoryCombo: TComboBox;
    ExportHistoryButton: TButton;
    DeleteHistoryButton: TButton;
    ConversationLabel: TLabel;
    ConversationSearch: TEdit;
    ConversationList: TListBox;
    ChatSplitter: TSplitter;
    ChatHost: TPanel;
    { Plan workspace (runtime, left mode panel). }
    PlanPanel: TPanel;
    PlanActiveLabel: TLabel;
    PlanList: TListBox;
    PlanNewButton: TButton;
    PlanOpenButton: TButton;
    PlanSetActiveButton: TButton;
    PlanRefreshButton: TButton;
    PlanOpenDocsButton: TButton;
    { Build work-package tiles (runtime, left panel; visible in every mode). }
    BuildPanel: TPanel;
    BuildActiveLabel: TLabel;
    BuildTodoList: TListBox;
    BuildRefreshButton: TButton;
    BuildOpenPlanButton: TButton;
    BuildStartButton: TButton;
    BuildDoneButton: TButton;
    BuildResetButton: TButton;
    BuildWorkButton: TButton;
    BuildWorkPlanButton: TButton;
    BuildStatusLabel: TLabel;
    ComposerStack: TPanel;
    BottomBar: TPanel;
    NewChatButton: TButton;
    ToggleThinkingButton: TButton;
    ReviewCompileButton: TButton;
    ReviewBuildButton: TButton;
    FixErrorButton: TButton;
    SettingsButton: TButton;
    AutoNewChatCheck: TCheckBox;
    StatusFooter: TStatusFooterFrame;
    InputPanel: TPanel;
    AttachmentStrip: TPanel;
    PlanOfferBar: TPanel;
    PlanOfferLabel: TLabel;
    BuildThisButton: TButton;
    RevisePlanButton: TButton;
    InputMemo: TSpellMemo;
    InputPopup: TPopupMenu;
    InputCutItem: TMenuItem;
    InputCopyItem: TMenuItem;
    InputPasteItem: TMenuItem;
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
    Procedure ModeComboChange(Sender: TObject);
    Procedure ConversationSearchChange(Sender: TObject);
    Procedure ConversationListClick(Sender: TObject);
    Procedure ConversationListSelectionChange(Sender: TObject; User: Boolean);
    Procedure HistoryComboChange(Sender: TObject);
    Procedure SendActionExecute(Sender: TObject);
    Procedure StopActionExecute(Sender: TObject);
    Procedure NewChatActionExecute(Sender: TObject);
    Procedure ReviewCompileActionExecute(Sender: TObject);
    Procedure ReviewBuildActionExecute(Sender: TObject);
    Procedure ReviewChangesActionExecute(Sender: TObject);
    Procedure FixErrorActionExecute(Sender: TObject);
    Procedure SettingsActionExecute(Sender: TObject);
    Procedure ToggleThinkingActionExecute(Sender: TObject);
    Procedure ToggleToolUseActionExecute(Sender: TObject);
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
    Procedure AutoNewChatCheckClick(Sender: TObject);
    Procedure ReviewButtonClick(Sender: TObject);
    Procedure CommandsActionExecute(Sender: TObject);
    Procedure ContextBreakdownActionExecute(Sender: TObject);
    Procedure SessionInfoActionExecute(Sender: TObject);
    Procedure ModelPickerActionExecute(Sender: TObject);
    Procedure ThinkingPickerActionExecute(Sender: TObject);
    Procedure SkillsPickerActionExecute(Sender: TObject);
    Procedure CompactContextActionExecute(Sender: TObject);
    Procedure CopyLastAnswerActionExecute(Sender: TObject);
    Procedure OpenPlanActionExecute(Sender: TObject);
    Procedure BuildThisActionExecute(Sender: TObject);
    Procedure RevisePlanActionExecute(Sender: TObject);
    Procedure ChatModeActionExecute(Sender: TObject);
    Procedure InspectModeActionExecute(Sender: TObject);
    Procedure PlanModeActionExecute(Sender: TObject);
    Procedure BuildModeActionExecute(Sender: TObject);
    Procedure ComposerStackResize(Sender: TObject);
    Procedure InputMemoPaste(Sender: TObject);
    Procedure InputMemoKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
    Procedure InputMemoUTF8KeyPress(Sender: TObject; Var UTF8Key: TUTF8Char);
    Procedure InputMemoChange(Sender: TObject);
    Procedure InputMemoExit(Sender: TObject);
    Procedure SlashListDrawItem(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
    Procedure SlashListClick(Sender: TObject);
    Procedure StatusFooterLeftClick(Sender: TObject);
    Procedure StatusFooterSkillClick(Sender: TObject);
    Procedure StatusFooterCentreClick(Sender: TObject);
    Procedure StatusFooterRightClick(Sender: TObject);
    Procedure FooterMenuClick(Sender: TObject);
  Private
    FTargetCombo: TComboBox;
    FRefreshingTargets: Boolean;
    FTargetBrowseButton: TButton;
    FTargetPaths: TStringList;
    FTargetRestored: Boolean;
    Procedure RefreshTargetChoices(Sender: TObject);
    Procedure TargetChoiceChanged(Sender: TObject);
    Procedure TargetBrowseClick(Sender: TObject);
    Procedure ApplyTarget(Const Directory: String);
  Private

    FUseCodex: Boolean;
    FCodexRuntime, FCodexModel, FCodexProfile, FCodexIdentity, FCodexEffort, FCodexApproval: String;
    FCodexRun: TAssistantCodexRun;
    FPollingCodex: Boolean;
    FCodexWorkspace: TAssistantIDEWorkspace;
    FCodexBroker: TAssistantToolBroker;
    Procedure LoadConnectionSettings;
    Function ApproveCodexTool(Const Tool, Path, OldText, NewText: String): Boolean;
    Function StartCodexReply(Const DisplayText, ApiText: String): Boolean;
    Procedure PollCodex;
    Procedure ReleaseCodexRun;
  Private
    ElapsedTimer: TTimer;
    ChatView: TControl; { unused; centre is FTraceView }
    Transcript: TStringList; { Session export / legacy; not the main UI surface. }
    FDisplayUser: String; { Current-turn user text shown in the Chat tab. }
    FComposerImagesJson: String; { Unsent attachment refs. Not cleared when a model rejects an image. }
    FComposerSelectedIndex: Integer; { Outlined thumbnail. -1 when the strip is empty. }
    FComposerImagesHeld: String; { Cleared from the strip at send, restored if the model rejects the image. }
    FComposerImagesSent: Boolean;
    FPasteComposerBusy: Boolean;
    FInputDropArmed: Boolean;
    FInputHeight: Integer;
    FComposerLayoutLock: Boolean;
    FDisplaySystemNote: String; { Optional system/error note for the current surface. }
    FDisplayDurationMs: Integer; { Stored turn wall time when browsing history. }
    FDisplayThinkingMs: Integer; { Stored thinking time when browsing history. }
    FShowThinking: Boolean;
    FShowToolUse: Boolean;
    ActiveMode: TAssistantMode;
    FModelName: String;
    FContextUsed: Integer;
    FContextLimit: Integer;
    FSending: Boolean;
    FStreamingActive: Boolean; { True while assistant reply is streaming. }
    FTurnRecorded: Boolean; { True after this in-flight turn is written to conversation.jsonl. }
    FUserCancelled: Boolean;
    FAssistantContent: String; { Content shown in the chat pane (may be a past turn). }
    FAssistantThinking: String;
    FLiveUser: String; { In-flight turn buffers (updated even when browsing past turns). }
    FLiveContent: String;
    FLiveThinking: String;
    FViewingLive: Boolean; { True when chat pane follows the in-flight turn. }
    FReviewInProgress: Boolean;
    StreamStart: TDateTime;
    FTurnStartedAt: String;
    FReconnectStartTick: QWord;
    FStatusPhase: String; { e.g. Thinking… / Streaming… while FSending. }
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
    PlanListPaths: TStringList; { Parallel to PlanList captions; relative paths. }
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
    FLastTurnHadError: Boolean;
    FCommandsPopup: TPopupMenu;
    FCatalog: TAssistantCatalog;
    FSlashList: TListBox;
    FSlashHits: TCatalogIndexArray;
    FFooterMenu: TPopupMenu;
    FPlanWriteThisTurn: Boolean;
    FShowPlanOffer: Boolean;
    FOpenBindPending: Boolean; { True until the first BindToActiveProject after Show. }
    FDeferLastTurn: Boolean; { First open: paint empty chrome, then last-turn markdown. }
    FOpenBusy: Boolean; { Busy cursor while first-open conversation markdown runs. }
    Function ComposerHasImages: Boolean;
    Procedure StashComposerImages;
    Procedure RestoreHeldComposerImages;
    Procedure ApplyInputPanelHeight;
    Procedure LayoutComposer;
    Function ComposerChromeHeight: Integer;
    Procedure PlaceComposerChildren;
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
    Function TryAttachClipboardImage(Out ErrorText: String): Boolean;
    Procedure ClearUnsentComposerImages;
    Procedure UpdateViewActionCaptions;
    Procedure ClearCurrentTurnDisplay;
    Procedure ResetTraceCards;
    Procedure SetCurrentUserDisplay(Const UserText: String; Const WithIdeContext: Boolean);
    Procedure SetCurrentSystemNote(Const NoteText: String);
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
    Function CurrentStreamDurationMs: Integer;
    Procedure FinishLiveTrace(Const SystemNote: String; DurationMs: Integer);
    Function CurrentModeFromUi: TAssistantMode;
    Procedure EnsureModeComboItems;
    Function ModeOfLoadedConversation: TAssistantMode;
    Procedure SelectMode(Mode: TAssistantMode);
    Procedure SyncModeUi;
    Procedure UpdateModeBadge;
    Function ModeStatusText: String;
    Procedure PinSidebarHeader;
    Procedure UpdateModeSidePanels;
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
    Procedure EnsurePlanTabUi;
    Procedure RefreshPlanList;
    Function ActivePlanCaption(Const ActivePlan: String): String;
    Procedure PlanNewButtonClick(Sender: TObject);
    Procedure PlanOpenButtonClick(Sender: TObject);
    Procedure PlanSetActiveButtonClick(Sender: TObject);
    Procedure PlanRefreshButtonClick(Sender: TObject);
    Procedure PlanOpenDocsButtonClick(Sender: TObject);
    Procedure PlanListDblClick(Sender: TObject);
    Function SelectedPlanRelativePath: String;
    Procedure EnsureBuildTabUi;
    Procedure RefreshBuildTodos;
    Function SelectedBuildSectionIndex: Integer;
    Function SelectedBuildRowIsContext: Boolean;
    Function BuildSelectionMessage: String;
    Procedure SetBuildStatusFeedback(Const MessageText: String);
    Procedure SetSelectedBuildSectionStatus(NewStatus: TPlanSectionStatus);
    Procedure ClearBuildWorkTracking;
    Procedure BeginBuildWorkTracking(SectionIndex: Integer; Const SectionTitle: String);
    Procedure TryAutoCompleteBuildWork(Const StreamErrorText: String);
    Function BuildWorkSectionIsComplete: Boolean;
    Procedure PrepareTopErrorAfterReview(ErrorCount: Integer);
    Procedure OfferFixTopErrorAfterReview;
    Procedure BuildRefreshButtonClick(Sender: TObject);
    Procedure BuildOpenPlanButtonClick(Sender: TObject);
    Procedure BuildStartButtonClick(Sender: TObject);
    Procedure BuildDoneButtonClick(Sender: TObject);
    Procedure BuildResetButtonClick(Sender: TObject);
    Procedure BuildWorkButtonClick(Sender: TObject);
    Procedure BuildWorkPlanButtonClick(Sender: TObject);
    Procedure BuildWorkOnSelectedPackage;
    Procedure StartWorkOnPlanAgent;
    Procedure StopWorkOnPlanAgent(Const Reason: String);
    Procedure ContinueWorkOnPlanAgent(Data: PtrInt);
    Function FindNextIncompleteBuildSection: Integer;
    Function BuildWorkPrompt(Const PlanRel, SectionTitle, StatusText, SectionBody, ParentTitle: String;
      ContinueSameItem: Boolean): String;
    Procedure MaybeWarnHighContextUsage;
    Function AutoNewChatAtLimitEnabled: Boolean;
    Procedure SyncAutoNewChatCheckFromConfig;
    Procedure BuildTodoListDblClick(Sender: TObject);
    Procedure BuildTodoListClick(Sender: TObject);
    Procedure BuildTodoListSelectionChange(Sender: TObject; User: Boolean);
    Function ConversationListTurnIndex(ListIndex: Integer): Integer;
    Procedure UpdateStatusFooter;
    Function FormatElapsedStatus(Const Phase: String): String;
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
    Procedure ScrollChatToEnd;
    Procedure ScrollChatToTop;
    Procedure RefreshChatDisplay(Force: Boolean; ScrollToBottom: Boolean = True);
    Procedure SetBusyCursor(IsBusy: Boolean);
    Procedure SetOpenBusy(IsBusy: Boolean);
    Function RoleHeading(Const Role: String): String;
    Function QuoteMarkdownLines(Const TextValue: String): String;
    Function FormatAssistantMarkdown(Const Thinking, Content: String): String;
    Procedure AppendMessage(Const Role, Content: String);
    Procedure BeginAssistantReply;
    Procedure ApplyAssistantSnapshots(Const ContentSnapshot, ThinkingSnapshot: String);
    Procedure FinishAssistantReply(Const ErrorText: String);
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
    Function SubmitUserText(Const UserText: String; AutoSend: Boolean): Boolean;
    { DisplayText is shown/stored; ApiText is what the model receives (may include extra directives). }
    Function SubmitUserTextEx(Const DisplayText, ApiText: String; AutoSend: Boolean): Boolean;
    Procedure SteerQueuedText(Const UserText: String);
    Function ModeChipCaption(Mode: TAssistantMode): String;
    Procedure UpdateWorkActions;
    Procedure EnsureCommandsMenu;
    Procedure RebuildCommandCatalog;
    Procedure EnsureSlashPopup;
    Procedure HideSlashPopup;
    Procedure PositionSlashPopup;
    Procedure UpdateSlashPopup;
    Function SlashPopupVisible: Boolean;
    Procedure ExecuteCatalogItem(Const Item: TAssistantCatalogItem);
    Procedure ExecuteSlashSelection;
    Procedure RemovePromptSlashToken;
    Procedure PopupUnderControl(Host: TControl; Popup: TPopupMenu);
    Procedure ApplyConfigAndRefresh;
    Procedure PinActiveSkill(Const SkillName: String);
    Procedure FillModelFooterMenu;
    Procedure FillThinkingFooterMenu;
    Procedure FillApprovalFooterMenu;
    Procedure FillSkillFooterMenu;
    Procedure ShowPlanOfferBar(OfferVisible: Boolean);
    Procedure DeferredHideSlash(Data: PtrInt);
    Procedure SeedPromptFromSelectedWork;
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
    Procedure StartNewChat(KeepPlanAgent: Boolean = False; UseChatDefault: Boolean = True);
    Procedure ReviewCompile;
    Procedure ReviewBuild;
    Procedure FixSelectedError;
    Procedure FixTopError;
    Procedure StopStream;
    { Rebind conversation store, session and UI to LazarusIDE.ActiveProject. }
    Procedure BindToActiveProject;
    { Drop project binding without reading ActiveProject (safe during project close). }
    Procedure UnbindFromProject;
  End;

Procedure NotifyOpenProjectAssistantFormsProjectChanged;
Procedure NotifyOpenProjectAssistantFormsProjectCleared;

Implementation

{$R *.lfm}

Uses AssistantWorkTarget, PackageIntf,
  WorkflowLog, AssistantService, AssistantConfig, AssistantSettingsForm, AssistantIDEContext,
  AssistantSession, AssistantTools, AssistantMarkdownForm, AssistantSubagents, GrokOAuth, LazFileUtils,
  FileUtil, LazUTF8, LCLIntf, LazIDEIntf, IDEMsgIntf, SrcEditorIntf, fpimage, fpwritepng,
  ProjectIntf, AssistantSkills, AssistantConnections, AssistantCodexSettings, AssistantCodexClient, AssistantImages,
  AssistantImageView
  {$IFDEF LCLGTK3}, gtk3widgets, LazGtk3, LazGdk3, LazGLib2, LazGObject2{$ENDIF};

Const
  ChatViewMargin = 4;
  ChatPaintMinIntervalMs = 80;
  { List Objects store TurnIndex+1; this marker is the in-flight (not yet recorded) turn. }
  LiveConversationMarker = -2;
  FooterTagModel = 1;
  FooterTagThinking = 2;
  FooterTagApproval = 3;
  FooterTagSkill = 4;
  FooterTagSettings = 5;

Constructor TProjectAssistantForm.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FModelName := AssistantConfigDefaultModel;
  FContextUsed := 0;
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
  FTurnStartedAt := '';
  FStatusPhase := '';
  FLastChatPaintTick := 0;
  FSessionProjectKey := '';
  ChatView := Nil;
  FTrace := TAssistantTrace.Create;
  FTraceView := Nil;
  FThinkingSliceStart := 1;
  FAnswerSliceStart := 1;
  FDisplayTraceJson := '';
  FDisplayEventsFile := '';
  FHistoryUpdating := False;
  HistoryIds := TStringList.Create;
  PlanListPaths := TStringList.Create;
  Transcript := TStringList.Create;
  BuildSections := TObjectList.Create(True);
  BuildPanel := Nil;
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
  FLastTurnHadError := False;
  FOpenBindPending := True;
  FDeferLastTurn := True;
  FOpenBusy := False;
  FPlanWriteThisTurn := False;
  FShowPlanOffer := False;
  LoadConnectionSettings;
  FCatalog := TAssistantCatalog.Create;
  WorkflowEventBus.AddListener(Self);
  SyncModeUi;
End;

Procedure TProjectAssistantForm.Resize;
Var
  Available, SideWidth, SideBudget, ChatReserve, LeftWidth: Integer;
Begin
  Inherited Resize;
  If (csLoading In ComponentState) Or (csDestroying In ComponentState) Or
    Not Assigned(ClientPanel) Or Not Assigned(ModeSidePanel) Or
    Not Assigned(ConversationPanel) Or Not Assigned(ModeSplitter) Or
    Not Assigned(ChatSplitter) Then Exit;
  Available := ClientPanel.ClientWidth - ModeSplitter.Width - ChatSplitter.Width;
  If Available <= 0 Then Exit;
  ChatReserve := Scale96ToForm(360);
  If ChatReserve > Available Div 2 Then ChatReserve := Available Div 2;
  SideBudget := Available - ChatReserve;
  SideWidth := ModeSidePanel.Width + ConversationPanel.Width;
  If (SideWidth <= SideBudget) Or (SideWidth = 0) Then Exit;
  { Preserve the side-pane ratio when a saved/small window would squeeze out
    the conversation. Ordinary splitter choices remain untouched until the
    form becomes too narrow. No large minimum window size is imposed. }
  LeftWidth := Integer(Int64(ModeSidePanel.Width) * SideBudget Div SideWidth);
  ClientPanel.DisableAlign;
  Try
    ModeSidePanel.Width := LeftWidth;
    ConversationPanel.Width := SideBudget - LeftWidth;
  Finally
    ClientPanel.EnableAlign;
  End;
End;

Destructor TProjectAssistantForm.Destroy;
Var
  OwnWrite: Boolean;
Begin
  { BeforeDestruction takes the write lock and sets csDestroying. A failed
    constructor skips BeforeDestruction, so take the lock here or TCustomForm.Destroy
    calls EndWrite with no matching BeginWrite and the real error is lost. }
  OwnWrite := Not (csDestroying In ComponentState);
  If OwnWrite Then
    GlobalNameSpace.BeginWrite;
  Destroying;
  If Assigned(ElapsedTimer) Then ElapsedTimer.Enabled := False;
  Application.RemoveAsyncCalls(Self);
  If Assigned(WorkflowEventBus) Then WorkflowEventBus.RemoveListener(Self);
  If Assigned(AssistantClient) Then AssistantClient.DetachStreamCallbacks;
  ReleaseCodexRun;
  FreeAndNil(FCodexBroker);
  FreeAndNil(FCodexWorkspace);
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
  FreeAndNil(Transcript);
  FreeAndNil(HistoryIds);
  FreeAndNil(PlanListPaths);
  FreeAndNil(BuildSections);
  FreeAndNil(FTrace);
  FreeAndNil(FTargetPaths);
  If Assigned(FSlashList) Then
    Begin
      FSlashList.OnDrawItem := Nil;
      FSlashList.OnClick := Nil;
      FSlashList.Parent := Nil;
    End;
  FreeAndNil(FSlashList);
  FreeAndNil(FFooterMenu);
  FreeAndNil(FCatalog);
  Inherited Destroy;
End;

Procedure TProjectAssistantForm.FormCreate(Sender: TObject);
Var
  TargetRow: TPanel;
  TargetLabel: TLabel;
Begin
  TargetRow := TPanel.Create(Self);
  TargetRow.Name := 'TargetRow';
  TargetRow.Parent := SidebarHeader;
  TargetRow.Align := alTop;
  TargetRow.Height := Scale96ToForm(32);
  TargetRow.BevelOuter := bvNone;
  FTargetBrowseButton := TButton.Create(Self);
  FTargetBrowseButton.Name := 'TargetBrowseButton';
  FTargetBrowseButton.Parent := TargetRow;
  FTargetBrowseButton.Align := alRight;
  FTargetBrowseButton.Caption := '...';
  FTargetBrowseButton.Width := Scale96ToForm(36);
  FTargetBrowseButton.BorderSpacing.Top := 2;
  FTargetBrowseButton.BorderSpacing.Right := 0;
  FTargetBrowseButton.BorderSpacing.Bottom := 2;
  FTargetBrowseButton.Hint := 'Choose a target folder';
  FTargetBrowseButton.ShowHint := True;
  FTargetBrowseButton.OnClick := @TargetBrowseClick;
  TargetLabel := TLabel.Create(Self);
  TargetLabel.Parent := TargetRow;
  TargetLabel.Caption := '&Target:';
  TargetLabel.Align := alLeft;
  TargetLabel.AutoSize := True;
  TargetLabel.Layout := tlCenter;
  TargetLabel.BorderSpacing.Right := 6;
  FTargetPaths := TStringList.Create;
  FTargetCombo := TComboBox.Create(Self);
  FTargetCombo.Name := 'TargetCombo';
  FTargetCombo.Parent := TargetRow;
  FTargetCombo.Align := alClient;
  FTargetCombo.BorderSpacing.Top := 2;
  FTargetCombo.BorderSpacing.Left := 0;
  FTargetCombo.BorderSpacing.Right := 4;
  FTargetCombo.BorderSpacing.Bottom := 2;
  FTargetCombo.Style := csDropDownList;
  TargetLabel.FocusControl := FTargetCombo;
  FTargetCombo.OnDropDown := @RefreshTargetChoices;
  FTargetCombo.OnChange := @TargetChoiceChanged;
  RefreshTargetChoices(Nil);
  Caption := 'Project Assistant';
  { AllowDropFiles exists only on the form in this LCL. GTK still delivers the
    drop to the widget under the pointer, so the input controls are armed after
    their handles exist. Names arrive through OnDropFiles. }
  AllowDropFiles := True;
  OnDropFiles := @InputPanelDropFiles;
  ConversationPanel.OnResize := @HistoryPanelResize;
  HistoryPanelResize(ConversationPanel);
  If Assigned(InputMemo) Then
    Begin
      InputMemo.OnKeyDown := @InputMemoKeyDown;
      InputMemo.OnUTF8KeyPress := @InputMemoUTF8KeyPress;
      InputMemo.OnChange := @InputMemoChange;
      InputMemo.OnExit := @InputMemoExit;
      InputMemo.OnPaste := @InputMemoPaste;
    End;
  ApplyInputPanelHeight;
  If Assigned(ComposerStack) Then
    ComposerStack.OnResize := @ComposerStackResize;
  EnsureChatView;
  If Assigned(FTraceView) And Assigned(FTrace) Then
    FTraceView.Sync(FTrace, False);
  EnsureInputPopup;
  EnsurePlanTabUi;
  EnsureBuildTabUi;
  PinSidebarHeader;
  EnsureSlashPopup;
  RebuildCommandCatalog;
  EnsureCommandsMenu;
  If Assigned(StatusFooter) Then
    Begin
      StatusFooter.OnLeftClick := @StatusFooterLeftClick;
      StatusFooter.OnSkillClick := @StatusFooterSkillClick;
      StatusFooter.OnCentreClick := @StatusFooterCentreClick;
      StatusFooter.OnRightClick := @StatusFooterRightClick;
    End;
  If Assigned(PlanOfferBar) Then
    Begin
      PlanOfferBar.Height := Scale96ToForm(28);
      PlanOfferBar.Visible := False;
    End;
  UpdateViewActionCaptions;
  SyncAutoNewChatCheckFromConfig;
  If Not Assigned(ElapsedTimer) Then
    Begin
      ElapsedTimer := TTimer.Create(Self);
      ElapsedTimer.Enabled := False;
      ElapsedTimer.Interval := 250;
      ElapsedTimer.OnTimer := @ElapsedTimerTimer;
    End;
  If Assigned(AssistantClient) Then
    AssistantClient.OnTrace := @HandleTraceEvent;
  WorkflowLogger.Info('ProjectAssistant', 'Project Assistant window created');
End;

Procedure TProjectAssistantForm.RefreshTargetChoices(Sender: TObject);
Var
  Recent: TStringList;
  Index, Selected: Integer;
  Path: String;
Begin
  If Not Assigned(FTargetCombo) Or Not Assigned(FTargetPaths) Then Exit;
  Recent := TStringList.Create;
  FRefreshingTargets := True;
  FTargetCombo.Items.BeginUpdate;
  Try
    FTargetCombo.Items.Clear;
    FTargetPaths.Clear;
    FTargetCombo.Items.Add(AssistantCurrentProjectCaption);
    FTargetPaths.Add('');
    LoadAssistantRecentTargets(Recent);
    For Index := 0 To Recent.Count - 1 Do
      Begin
        If FTargetPaths.Count > AssistantRecentTargetLimit Then Break;
        Path := Recent[Index];
        If FTargetPaths.IndexOf(Path) >= 0 Then Continue;
        FTargetCombo.Items.Add(Path);
        FTargetPaths.Add(Path);
      End;
    Selected := 0;
    If AssistantTarget.Kind = atkFolder Then
      Begin
        Selected := FTargetPaths.IndexOf(ExcludeTrailingPathDelimiter(AssistantTarget.Root));
        If Selected < 0 Then
          Begin
            FTargetCombo.Items.Add(ExcludeTrailingPathDelimiter(AssistantTarget.Root));
            FTargetPaths.Add(ExcludeTrailingPathDelimiter(AssistantTarget.Root));
            Selected := FTargetPaths.Count - 1;
          End;
      End
    Else If AssistantTarget.Kind <> atkProject Then
      Selected := -1;
    FTargetCombo.ItemIndex := Selected;
  Finally
    FTargetCombo.Items.EndUpdate;
    FRefreshingTargets := False;
    Recent.Free;
  End;
End;

Procedure TProjectAssistantForm.ApplyTarget(Const Directory: String);
Var
  Note, KeptPlan, Resolved, Err: String;
Begin
  KeptPlan := GetActivePlanRelativePath;
  PersistSession;
  If Assigned(FCodexBroker) Then FCodexBroker.Cancel;
  If Assigned(FCodexWorkspace) Then FCodexWorkspace.CancelBuild;
  If Not AssistantTarget.SelectFolder(Directory, Note) Then
    Begin
      MessageDlg(Note, mtError, [mbOK], 0);
      RefreshTargetChoices(Nil);
      Exit;
    End;
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
      RefreshPlanList;
      RefreshBuildTodos;
    End;
  RefreshTargetChoices(Nil);
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
  If (FTargetCombo.ItemIndex < 0) Or (FTargetCombo.ItemIndex >= FTargetPaths.Count) Then Exit;
  Path := FTargetPaths[FTargetCombo.ItemIndex];
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

Procedure TProjectAssistantForm.HistoryPanelResize(Sender: TObject);
Var ButtonWidth: Integer;
Begin
  If Not Assigned(ExportHistoryButton) Or Not Assigned(DeleteHistoryButton) Then Exit;
  ButtonWidth := (ConversationPanel.ClientWidth - ExportHistoryButton.BorderSpacing.Left -
    DeleteHistoryButton.BorderSpacing.Right - Scale96ToForm(4)) Div 2;
  If ButtonWidth < 1 Then ButtonWidth := 1;
  ExportHistoryButton.Width := ButtonWidth;
  DeleteHistoryButton.Width := ButtonWidth;
End;

{$IFDEF LCLGTK3}
Var
  ArmedDropControls: TList;

Procedure GtkFileDropReceived(Widget: PGtkWidget; Context: PGdkDragContext; X, Y: LongInt; Data: PGtkSelectionData;
  Info: LongWord; Time: LongWord; UserData: Pointer); cdecl;
Var
  Uris: PPChar;
  I: Integer;
  Names: Array Of String;
  Form: TProjectAssistantForm;
Begin
  If Not (TObject(UserData) Is TProjectAssistantForm) Then Exit;
  Form := TProjectAssistantForm(UserData);
  Names := Nil;
  If Not Assigned(Data) Then Exit;
  SetLength(Names, 0);
  Uris := PPChar(gtk_selection_data_get_uris(Data));
  If Uris = Nil Then Exit;
  I := 0;
  While Uris[I] <> Nil Do
    Begin
      SetLength(Names, Length(Names) + 1);
      Names[High(Names)] := Uris[I];
      Inc(I);
    End;
  g_strfreev(Uris);
  If (Length(Names) > 0) And Assigned(Form.OnDropFiles) Then Form.OnDropFiles(Form, Names);
  gtk_drag_finish(Context, True, False, Time);
End;

Procedure ArmControlFileDrop(Control: TWinControl; Form: TProjectAssistantForm);
Var
  Target: TGtkTargetEntry;
  Native: PGtkWidget;
  ConnectFlags: TGConnectFlags;
Begin
  If Not Assigned(Control) Or Not Control.HandleAllocated Or Not (TObject(Control.Handle) Is TGtk3Widget) Then Exit;
  If Not Assigned(ArmedDropControls) Then ArmedDropControls := TList.Create;
  If ArmedDropControls.IndexOf(Control) >= 0 Then Exit;
  Native := TGtk3Widget(Control.Handle).Widget;
  If Native = Nil Then Exit;
  Target.target := 'text/uri-list';
  Target.flags := 0;
  Target.info := 0;
  ConnectFlags := Default(TGConnectFlags);
  gtk_drag_dest_set(Native, GTK_DEST_DEFAULT_ALL, @Target, 1, [GDK_ACTION_COPY]);
  g_signal_connect_data(Native, 'drag-data-received', TGCallback(@GtkFileDropReceived), Form, Nil, ConnectFlags);
  ArmedDropControls.Add(Control);
End;
{$ELSE}
Procedure ArmControlFileDrop(Control: TWinControl; Form: TProjectAssistantForm);
Begin
  If Assigned(Control) And Assigned(Form) Then Exit;
End;
{$ENDIF}

Procedure TProjectAssistantForm.FormShow(Sender: TObject);
Begin
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
  Try
    FreeAndNil(FTargetPaths);
    If Assigned(AttachmentStrip) Then
      While AttachmentStrip.ControlCount > 0 Do
        Begin
          AttachmentStrip.Controls[0].Parent := Nil;
          AttachmentStrip.Controls[0].Free;
        End;
    If Assigned(ElapsedTimer) Then
      ElapsedTimer.Enabled := False;
    If Assigned(FCommandsPopup) Then
      FreeAndNil(FCommandsPopup);
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
        WorkflowLogger.Error('PluginBoundary', 'TProjectAssistantForm.FormDestroy: ' + E.Message);
      End;
  End;
End;

Procedure TProjectAssistantForm.UpdateViewActionCaptions;
Begin
  If Not Assigned(ToggleThinkingAction) Then
    Exit;
  If FShowThinking Then
    ToggleThinkingAction.Caption := 'Hide Thinking'
  Else
    ToggleThinkingAction.Caption := 'Show Thinking';
  If FShowToolUse Then
    ToggleToolUseAction.Caption := 'Hide Tool Use'
  Else
    ToggleToolUseAction.Caption := 'Show Tool Use';
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
  { Visual order: Chat, Inspect, Plan, Build. }
  Case Mode Of
    amInspect: Result := 1;
    amPlan: Result := 2;
    amBuild: Result := 3;
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
    2: Result := amPlan;
    3: Result := amBuild;
  Else
    Result := amChat;
  End;
End;

Procedure TProjectAssistantForm.EnsureModeComboItems;
Begin
  If Not Assigned(ModeCombo) Then
    Exit;
  If ModeCombo.Items.Count = 4 Then
    Exit;
  ModeCombo.Items.BeginUpdate;
  Try
    ModeCombo.Items.Clear;
    ModeCombo.Items.Add('Chat');
    ModeCombo.Items.Add('Inspect');
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
  FModeSticky := False;
  If Mode <> amPlan Then
    ShowPlanOfferBar(False);
  SyncModeUi;
  ApplyActiveMode;
  If Not FSkipModePersist Then
    PersistShellConfig;
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
  UpdateModeSidePanels;
  UpdateModeBadge;
End;

Function TProjectAssistantForm.ModeChipCaption(Mode: TAssistantMode): String;
Begin
  Case Mode Of
    amChat: Result := 'Chat';
    amInspect: Result := 'Inspect';
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
    amPlan: ToolsHint := 'creates and edits Markdown · will not edit sources';
    amBuild: ToolsHint := 'edits target files and compiles';
  Else
    ToolsHint := 'explains and inspects · will not write files';
  End;
  If FModeLocked Or FSending Then
    Result := Format('%s · %s · reply in progress', [ModeChipCaption(ActiveMode), ToolsHint])
  Else If FModeSticky Then
    Result := Format('%s · %s · sticky', [ModeChipCaption(ActiveMode), ToolsHint])
  Else
    Result := Format('%s · %s', [ModeChipCaption(ActiveMode), ToolsHint]);
End;

Procedure TProjectAssistantForm.PinSidebarHeader;
Begin
  { Plan panel is also alTop. Re-dock the header so Target and Mode stay above it. }
  If Not Assigned(SidebarHeader) Then
    Exit;
  SidebarHeader.Align := alTop;
  SidebarHeader.Top := 0;
End;

Procedure TProjectAssistantForm.UpdateModeBadge;
Begin
  If Assigned(StatusFooter) Then
    StatusFooter.SetLeftText(ModeStatusText);
  If Assigned(ModeCombo) Then
    ModeCombo.Enabled := Not (FSending Or FModeLocked);
  UpdateWorkActions;
End;

Procedure TProjectAssistantForm.UpdateWorkActions;
Var
  CanWork: Boolean;
Begin
  CanWork := (ActiveMode = amBuild) And (Not FSending);
  If Assigned(BuildWorkButton) Then
    BuildWorkButton.Enabled := CanWork;
  If Assigned(BuildWorkPlanButton) Then
    BuildWorkPlanButton.Enabled := CanWork;
  If Assigned(BuildStartButton) Then
    BuildStartButton.Enabled := CanWork;
  If Assigned(BuildDoneButton) Then
    BuildDoneButton.Enabled := (ActiveMode = amBuild) And (Not FSending);
  If Assigned(BuildResetButton) Then
    BuildResetButton.Enabled := (ActiveMode = amBuild) And (Not FSending);
  If Assigned(BuildThisAction) Then
    BuildThisAction.Enabled := (Not FSending) And (GetActivePlanRelativePath <> '');
  If Assigned(RevisePlanAction) Then
    RevisePlanAction.Enabled := (Not FSending) And (GetActivePlanRelativePath <> '');
  If Assigned(OpenPlanAction) Then
    OpenPlanAction.Enabled := GetActivePlanRelativePath <> '';
  If Assigned(CompactContextAction) Then
    CompactContextAction.Enabled := (Not FSending) And Assigned(AssistantClient);
  If Assigned(ChatModeAction) Then
    ChatModeAction.Enabled := Not FSending;
  If Assigned(InspectModeAction) Then
    InspectModeAction.Enabled := Not FSending;
  If Assigned(PlanModeAction) Then
    PlanModeAction.Enabled := Not FSending;
  If Assigned(BuildModeAction) Then
    BuildModeAction.Enabled := Not FSending;
End;

Procedure TProjectAssistantForm.UpdateModeSidePanels;
Begin
  { Work tiles stay on the left in every mode. Plan file list is a top strip in Plan. }
  If Assigned(PlanPanel) Then
    Begin
      PlanPanel.Align := alTop;
      If PlanPanel.Height < 160 Then
        PlanPanel.Height := 200;
      PlanPanel.Visible := ActiveMode = amPlan;
    End;
  If Assigned(BuildPanel) Then
    Begin
      BuildPanel.Align := alClient;
      BuildPanel.Visible := True;
    End;
  PinSidebarHeader;
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
  FModeSticky := ActiveMode In [amPlan, amBuild];
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
  FModeSticky := Mode In [amPlan, amBuild];
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
  If Not WriteMarkdownFile(PlanRel, Body + LineEnding, True, Resolved, Err) Then
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
  RefreshPlanList;
  If Assigned(BuildPanel) Then
    RefreshBuildTodos;
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
  { Fix Error always switches into Build tools, so keep it available in every mode. }
  FixErrorAction.Enabled := Not FSending;
  ReviewCompileAction.Enabled := (Not FSending) And (Not FReviewInProgress);
  ReviewBuildAction.Enabled := (Not FSending) And (Not FReviewInProgress);
  ReviewChangesAction.Enabled := (Not FSending) And (Not FReviewInProgress);
  EnsurePlanTabUi;
  EnsureBuildTabUi;
  If ActiveMode = amPlan Then
    RefreshPlanList;
  RefreshBuildTodos;
  UpdateWorkActions;
  SyncModeUi;
End;

Procedure TProjectAssistantForm.PersistShellConfig;
Begin
  If Not Assigned(ProjectAssistantConversation) Then
    Exit;
  If ProjectAssistantConversation.ProjectRoot = '' Then
    Exit;
  If Not ProjectAssistantConversation.SaveShellConfig(FShowThinking, ActiveMode,
    GetActivePlanRelativePath, @FShowToolUse) Then
    WorkflowLogger.Warning('ProjectAssistant',
      'config.json save failed: ' + ProjectAssistantConversation.LastError);
End;

Procedure TProjectAssistantForm.ApplyShellConfigFromStore;
Var
  ShowThinking, ShowToolUse: Boolean;
  Mode: TAssistantMode;
  PlanFile: String;
Begin
  If Not Assigned(ProjectAssistantConversation) Then
    Exit;
  If Not ProjectAssistantConversation.LoadShellConfig(ShowThinking, Mode, PlanFile, @ShowToolUse) Then
    Begin
      { No saved shell mode. A project conversation keeps the mode of its last turn. }
      If ProjectAssistantConversation.TurnCount > 0 Then
        SelectMode(ModeOfLoadedConversation)
      Else
        SelectMode(amChat);
      Exit;
    End;
  FShowThinking := ShowThinking;
  FShowToolUse := ShowToolUse;
  UpdateViewActionCaptions;
  SetActivePlanRelativePath(PlanFile);
  FSkipModePersist := True;
  Try
    SelectMode(Mode);
  Finally
    FSkipModePersist := False;
  End;
  RefreshPlanList;
End;

Procedure TProjectAssistantForm.EnsurePlanTabUi;
Var
  Bar: TPanel;
Begin
  If Assigned(PlanPanel) Or (Not Assigned(ModeSidePanel)) Then
    Exit;

  PlanPanel := TPanel.Create(Self);
  PlanPanel.Parent := ModeSidePanel;
  PlanPanel.Align := alTop;
  PlanPanel.Height := 200;
  PlanPanel.BevelOuter := bvNone;
  PlanPanel.BorderSpacing.Around := 8;
  PlanPanel.Visible := ActiveMode = amPlan;

  PlanActiveLabel := TLabel.Create(Self);
  PlanActiveLabel.Parent := PlanPanel;
  PlanActiveLabel.Align := alTop;
  PlanActiveLabel.Caption := 'Active plan: (none)';
  PlanActiveLabel.BorderSpacing.Bottom := 6;

  Bar := TPanel.Create(Self);
  Bar.Parent := PlanPanel;
  Bar.Align := alTop;
  Bar.Height := 36;
  Bar.BevelOuter := bvNone;
  Bar.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  Bar.ChildSizing.ControlsPerLine := 8;
  Bar.ChildSizing.HorizontalSpacing := 6;
  Bar.ChildSizing.LeftRightSpacing := 0;
  Bar.ChildSizing.TopBottomSpacing := 2;
  Bar.BorderSpacing.Bottom := 6;

  PlanNewButton := TButton.Create(Self);
  PlanNewButton.Parent := Bar;
  PlanNewButton.Caption := 'New Plan…';
  PlanNewButton.AutoSize := True;
  PlanNewButton.OnClick := @PlanNewButtonClick;

  PlanOpenButton := TButton.Create(Self);
  PlanOpenButton.Parent := Bar;
  PlanOpenButton.Caption := 'Open';
  PlanOpenButton.AutoSize := True;
  PlanOpenButton.OnClick := @PlanOpenButtonClick;

  PlanSetActiveButton := TButton.Create(Self);
  PlanSetActiveButton.Parent := Bar;
  PlanSetActiveButton.Caption := 'Set Active';
  PlanSetActiveButton.AutoSize := True;
  PlanSetActiveButton.OnClick := @PlanSetActiveButtonClick;

  PlanRefreshButton := TButton.Create(Self);
  PlanRefreshButton.Parent := Bar;
  PlanRefreshButton.Caption := 'Refresh';
  PlanRefreshButton.AutoSize := True;
  PlanRefreshButton.OnClick := @PlanRefreshButtonClick;

  PlanOpenDocsButton := TButton.Create(Self);
  PlanOpenDocsButton.Parent := Bar;
  PlanOpenDocsButton.Caption := 'Open Documents/';
  PlanOpenDocsButton.AutoSize := True;
  PlanOpenDocsButton.OnClick := @PlanOpenDocsButtonClick;

  PlanList := TListBox.Create(Self);
  PlanList.Parent := PlanPanel;
  PlanList.Align := alClient;
  PlanList.OnDblClick := @PlanListDblClick;
End;

Function TProjectAssistantForm.SelectedPlanRelativePath: String;
Begin
  Result := '';
  If Not Assigned(PlanList) Or Not Assigned(PlanListPaths) Then
    Exit;
  If (PlanList.ItemIndex < 0) Or (PlanList.ItemIndex >= PlanListPaths.Count) Then
    Exit;
  Result := PlanListPaths[PlanList.ItemIndex];
End;

Function TProjectAssistantForm.ActivePlanCaption(Const ActivePlan: String): String;
Var
  Resolved, Title, Err: String;
Begin
  If ActivePlan = '' Then
    Result := 'Active plan: (none) — create one under Documents/ or Set active'
  Else If (Not ResolvePlanPath(ActivePlan, Resolved, Err)) Or (Not FileExistsUTF8(Resolved)) Then
    Result := 'Active plan: ' + ActivePlan
  Else If TryReadAssistantPlanIdentity(Resolved, Title, Err) Then
    Result := 'Active plan: ' + FormatPlanListCaption(Title, ActivePlan)
  Else
    Result := 'Active plan: ' + ActivePlan + ' — not a recognised assistant plan';
End;

Procedure TProjectAssistantForm.RefreshPlanList;
Var
  Paths, Titles: TStringList;
  Err, ActivePlan, CaptionText: String;
  I, Sel: Integer;
Begin
  If Not Assigned(PlanList) Then
    Exit;
  If Not Assigned(PlanListPaths) Then
    PlanListPaths := TStringList.Create;
  ActivePlan := GetActivePlanRelativePath;
  If Assigned(PlanActiveLabel) Then
    PlanActiveLabel.Caption := ActivePlanCaption(ActivePlan);

  Paths := Nil;
  Titles := Nil;
  Sel := -1;
  PlanList.Items.BeginUpdate;
  Try
    PlanList.Items.Clear;
    PlanListPaths.Clear;
    If Not ListProjectMarkdownPlans(Paths, Titles, Err) Then
      Begin
        If Err <> '' Then
          PlanList.Items.Add('(' + Err + ')');
        Exit;
      End;
    For I := 0 To Paths.Count - 1 Do
      Begin
        If I < Titles.Count Then
          CaptionText := FormatPlanListCaption(Titles[I], Paths[I])
        Else
          CaptionText := Paths[I];
        PlanList.Items.Add(CaptionText);
        PlanListPaths.Add(Paths[I]);
        If SameText(Paths[I], ActivePlan) Then
          Sel := I;
      End;
    If Sel >= 0 Then
      PlanList.ItemIndex := Sel
    Else If PlanList.Items.Count > 0 Then
      PlanList.ItemIndex := 0;
  Finally
    PlanList.Items.EndUpdate;
    Paths.Free;
    Titles.Free;
  End;
End;

Procedure TProjectAssistantForm.PlanNewButtonClick(Sender: TObject);
Var
  Title, Rel, Resolved, Err, Content: String;
Begin
  Title := 'Project Plan';
  If Not InputQuery('New plan', 'Plan title:', Title) Then
    Exit;
  If Trim(Title) = '' Then
    Title := 'Project Plan';
  Rel := DefaultPlanRelativePath;
  If FileExistsUTF8(ExpandFileName(ProjectRootPath + Rel)) Or
    FileExistsUTF8(ExpandFileName(ProjectRootPath + StringReplace(Rel, '/', PathDelim, [rfReplaceAll]))) Then
    Rel := AssistantDocumentsDirName + PathDelim +
      'Plan-' + FormatDateTime('yyyymmdd-hhnnss', Now) + '.md';
  Content := DefaultNewPlanMarkdown(Title);
  If Not WriteMarkdownFile(Rel, Content, True, Resolved, Err) Then
    Begin
      MessageDlg(Err, mtError, [mbOK], 0);
      Exit;
    End;
  SetActivePlanRelativePath(ProjectRelativePath(Resolved));
  PersistShellConfig;
  RefreshPlanList;
  SetCurrentSystemNote('Created plan **' + GetActivePlanRelativePath +
    '**. Stay in **Plan** mode and send a message to refine it with the model.');
End;

Procedure TProjectAssistantForm.PlanOpenButtonClick(Sender: TObject);
Var
  Rel, Resolved, Err: String;
Begin
  Rel := SelectedPlanRelativePath;
  If Rel = '' Then
    Rel := GetActivePlanRelativePath;
  If Rel = '' Then
    Begin
      MessageDlg('Select a plan in the list, or create a new one.', mtInformation, [mbOK], 0);
      Exit;
    End;
  If Not ResolvePlanPath(Rel, Resolved, Err) Then
    Begin
      MessageDlg(Err, mtError, [mbOK], 0);
      Exit;
    End;
  If Not FileExistsUTF8(Resolved) Then
    Begin
      MessageDlg('File not found: ' + Resolved, mtError, [mbOK], 0);
      Exit;
    End;
  OpenMarkdownDocument(Resolved);
End;

Procedure TProjectAssistantForm.PlanSetActiveButtonClick(Sender: TObject);
Var
  Rel, Resolved, Err: String;
Begin
  Rel := SelectedPlanRelativePath;
  If Rel = '' Then
    Begin
      MessageDlg('Select a Markdown file in the list.', mtInformation, [mbOK], 0);
      Exit;
    End;
  If Not ResolvePlanPath(Rel, Resolved, Err) Then
    Begin
      MessageDlg(Err, mtError, [mbOK], 0);
      Exit;
    End;
  If Not FileExistsUTF8(Resolved) Then
    Begin
      MessageDlg('File not found: ' + Resolved, mtError, [mbOK], 0);
      Exit;
    End;
  SetActivePlanRelativePath(ProjectRelativePath(Resolved));
  PersistShellConfig;
  RefreshPlanList;
End;

Procedure TProjectAssistantForm.PlanRefreshButtonClick(Sender: TObject);
Begin
  RefreshPlanList;
End;

Procedure TProjectAssistantForm.PlanOpenDocsButtonClick(Sender: TObject);
Var
  Err, Dir: String;
Begin
  If Not EnsureProjectDocumentsDir(Err) Then
    Begin
      MessageDlg(Err, mtError, [mbOK], 0);
      Exit;
    End;
  Dir := ExcludeTrailingPathDelimiter(ProjectDocumentsDir);
  If Not OpenDocument(Dir) Then
    MessageDlg('Could not open folder: ' + Dir, mtWarning, [mbOK], 0);
End;

Procedure TProjectAssistantForm.PlanListDblClick(Sender: TObject);
Begin
  PlanOpenButtonClick(Sender);
End;

Procedure TProjectAssistantForm.EnsureBuildTabUi;
Var
  Bar: TPanel;
Begin
  If Assigned(BuildPanel) Or (Not Assigned(ModeSidePanel)) Then
    Exit;

  BuildPanel := TPanel.Create(Self);
  BuildPanel.Parent := ModeSidePanel;
  BuildPanel.Align := alClient;
  BuildPanel.BevelOuter := bvNone;
  BuildPanel.BorderSpacing.Around := 8;
  BuildPanel.Visible := True;

  BuildActiveLabel := TLabel.Create(Self);
  BuildActiveLabel.Parent := BuildPanel;
  BuildActiveLabel.Align := alTop;
  BuildActiveLabel.Caption := 'Active plan: (none)';
  BuildActiveLabel.WordWrap := True;
  BuildActiveLabel.BorderSpacing.Bottom := 6;

  Bar := TPanel.Create(Self);
  Bar.Parent := BuildPanel;
  Bar.Align := alTop;
  Bar.Height := 36;
  Bar.BevelOuter := bvNone;
  Bar.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  Bar.ChildSizing.ControlsPerLine := 10;
  Bar.ChildSizing.HorizontalSpacing := 6;
  Bar.ChildSizing.LeftRightSpacing := 0;
  Bar.ChildSizing.TopBottomSpacing := 2;
  Bar.BorderSpacing.Bottom := 6;

  BuildRefreshButton := TButton.Create(Self);
  BuildRefreshButton.Parent := Bar;
  BuildRefreshButton.Caption := 'Refresh';
  BuildRefreshButton.AutoSize := True;
  BuildRefreshButton.OnClick := @BuildRefreshButtonClick;

  BuildOpenPlanButton := TButton.Create(Self);
  BuildOpenPlanButton.Parent := Bar;
  BuildOpenPlanButton.Caption := 'Open Plan';
  BuildOpenPlanButton.AutoSize := True;
  BuildOpenPlanButton.OnClick := @BuildOpenPlanButtonClick;

  BuildStartButton := TButton.Create(Self);
  BuildStartButton.Parent := Bar;
  BuildStartButton.Caption := 'Start';
  BuildStartButton.AutoSize := True;
  BuildStartButton.OnClick := @BuildStartButtonClick;

  BuildDoneButton := TButton.Create(Self);
  BuildDoneButton.Parent := Bar;
  BuildDoneButton.Caption := 'Done';
  BuildDoneButton.AutoSize := True;
  BuildDoneButton.OnClick := @BuildDoneButtonClick;

  BuildResetButton := TButton.Create(Self);
  BuildResetButton.Parent := Bar;
  BuildResetButton.Caption := 'Reset';
  BuildResetButton.AutoSize := True;
  BuildResetButton.OnClick := @BuildResetButtonClick;

  BuildWorkButton := TButton.Create(Self);
  BuildWorkButton.Parent := Bar;
  BuildWorkButton.Caption := 'Work On This';
  BuildWorkButton.AutoSize := True;
  BuildWorkButton.OnClick := @BuildWorkButtonClick;

  BuildWorkPlanButton := TButton.Create(Self);
  BuildWorkPlanButton.Parent := Bar;
  BuildWorkPlanButton.Caption := 'Work On Plan';
  BuildWorkPlanButton.AutoSize := True;
  BuildWorkPlanButton.Hint := 'Agentically work through incomplete plan packages until done, error, or context limit';
  BuildWorkPlanButton.ShowHint := True;
  BuildWorkPlanButton.OnClick := @BuildWorkPlanButtonClick;

  BuildStatusLabel := TLabel.Create(Self);
  BuildStatusLabel.Parent := BuildPanel;
  BuildStatusLabel.Align := alBottom;
  BuildStatusLabel.Caption := 'Select an actionable item, then Start / Done / Reset.';
  BuildStatusLabel.WordWrap := True;
  BuildStatusLabel.BorderSpacing.Top := 6;

  BuildTodoList := TListBox.Create(Self);
  BuildTodoList.Parent := BuildPanel;
  BuildTodoList.Align := alClient;
  BuildTodoList.OnClick := @BuildTodoListClick;
  BuildTodoList.OnDblClick := @BuildTodoListDblClick;
  BuildTodoList.OnSelectionChange := @BuildTodoListSelectionChange;
End;

Procedure TProjectAssistantForm.RefreshBuildTodos;
Var
  PlanRel, Err, Summary: String;
  I, KeepHeading, SelectIndex: Integer;
  Section: TPlanSection;
  NotStarted, InProgress, Complete: Integer;
Begin
  If Not Assigned(BuildTodoList) Then
    Exit;
  PlanRel := GetActivePlanRelativePath;
  KeepHeading := -1;
  If Assigned(BuildSections) And (FBuildSelectedIndex >= 0) And
    (FBuildSelectedIndex < BuildSections.Count) Then
    KeepHeading := TPlanSection(BuildSections[FBuildSelectedIndex]).HeadingLineIndex
  Else If Assigned(BuildTodoList) And Assigned(BuildSections) And
    (BuildTodoList.ItemIndex >= 0) And (BuildTodoList.ItemIndex < BuildSections.Count) Then
    KeepHeading := TPlanSection(BuildSections[BuildTodoList.ItemIndex]).HeadingLineIndex;
  If Assigned(BuildActiveLabel) Then
    If PlanRel = '' Then
      BuildActiveLabel.Caption := 'No active plan — switch to Plan to create one.'
    Else
      BuildActiveLabel.Caption := ActivePlanCaption(PlanRel);
  BuildTodoList.Items.BeginUpdate;
  Try
    BuildTodoList.Items.Clear;
    If Assigned(BuildSections) Then
      BuildSections.Clear;
    If PlanRel = '' Then
      Begin
        BuildTodoList.Items.Add('(No active plan — switch to Plan to create one.)');
        FBuildSelectedIndex := -1;
        Exit;
      End;
    If Not ScanPlanSections(PlanRel, BuildSections, Err) Then
      Begin
        BuildTodoList.Items.Add('(' + Err + ')');
        FBuildSelectedIndex := -1;
        Exit;
      End;
    If BuildSections.Count = 0 Then
      Begin
        BuildTodoList.Items.Add(
          '(No plan sections. Add ## context headings, and ### items whose next non-empty line is ' +
          'Status: not started | in progress | complete.)');
        FBuildSelectedIndex := -1;
        Exit;
      End;
    NotStarted := 0;
    InProgress := 0;
    Complete := 0;
    For I := 0 To BuildSections.Count - 1 Do
      Begin
        Section := TPlanSection(BuildSections[I]);
        BuildTodoList.Items.Add(FormatPlanSectionTile(Section));
        If Not Section.Actionable Then
          Continue;
        Case Section.Status Of
          pssNotStarted: Inc(NotStarted);
          pssInProgress: Inc(InProgress);
          pssComplete: Inc(Complete);
        Else
          { }
        End;
      End;
    Summary := Format('%s  ·  %d not started · %d in progress · %d complete',
      [ActivePlanCaption(PlanRel), NotStarted, InProgress, Complete]);
    If (NotStarted + InProgress + Complete) = 0 Then
      Summary := Summary + '  ·  no actionable items';
    If Assigned(BuildActiveLabel) Then
      BuildActiveLabel.Caption := Summary;
    SelectIndex := -1;
    If KeepHeading >= 0 Then
      For I := 0 To BuildSections.Count - 1 Do
        If TPlanSection(BuildSections[I]).HeadingLineIndex = KeepHeading Then
          Begin
            SelectIndex := I;
            Break;
          End;
    If SelectIndex < 0 Then
      Begin
        For I := 0 To BuildSections.Count - 1 Do
          If TPlanSection(BuildSections[I]).Actionable And
            (TPlanSection(BuildSections[I]).Status = pssInProgress) Then
            Begin
              SelectIndex := I;
              Break;
            End;
        If SelectIndex < 0 Then
          For I := 0 To BuildSections.Count - 1 Do
            If TPlanSection(BuildSections[I]).Actionable And
              (TPlanSection(BuildSections[I]).Status = pssNotStarted) Then
              Begin
                SelectIndex := I;
                Break;
              End;
      End;
    If SelectIndex >= 0 Then
      BuildTodoList.ItemIndex := SelectIndex
    Else If BuildTodoList.Items.Count > 0 Then
      BuildTodoList.ItemIndex := 0;
    FBuildSelectedIndex := BuildTodoList.ItemIndex;
  Finally
    BuildTodoList.Items.EndUpdate;
  End;
End;

Function TProjectAssistantForm.SelectedBuildSectionIndex: Integer;
Begin
  Result := -1;
  If Not Assigned(BuildSections) Or (BuildSections.Count = 0) Then
    Exit;
  { Prefer the remembered index: button clicks often clear ListBox.ItemIndex on GTK. }
  If (FBuildSelectedIndex >= 0) And (FBuildSelectedIndex < BuildSections.Count) Then
    Result := FBuildSelectedIndex
  Else If Assigned(BuildTodoList) And (BuildTodoList.ItemIndex >= 0) And
    (BuildTodoList.ItemIndex < BuildSections.Count) Then
    Result := BuildTodoList.ItemIndex;
  If (Result >= 0) And (Not TPlanSection(BuildSections[Result]).Actionable) Then
    Result := -1;
End;

Function TProjectAssistantForm.SelectedBuildRowIsContext: Boolean;
Var
  Idx: Integer;
Begin
  Result := False;
  If Not Assigned(BuildSections) Or (BuildSections.Count = 0) Then
    Exit;
  Idx := -1;
  If (FBuildSelectedIndex >= 0) And (FBuildSelectedIndex < BuildSections.Count) Then
    Idx := FBuildSelectedIndex
  Else If Assigned(BuildTodoList) And (BuildTodoList.ItemIndex >= 0) And
    (BuildTodoList.ItemIndex < BuildSections.Count) Then
    Idx := BuildTodoList.ItemIndex;
  Result := (Idx >= 0) And (Not TPlanSection(BuildSections[Idx]).Actionable);
End;

Function TProjectAssistantForm.BuildSelectionMessage: String;
Begin
  If SelectedBuildRowIsContext Then
    Result := 'Select an actionable item (### with Status), not a section heading.'
  Else
    Result := 'Select an actionable item in the list.';
End;

Procedure TProjectAssistantForm.SetBuildStatusFeedback(Const MessageText: String);
Begin
  If Assigned(BuildStatusLabel) Then
    BuildStatusLabel.Caption := MessageText;
  StatusFooter.SetRightText(MessageText);
  WorkflowLogger.Info('ProjectAssistant', 'Build work: ' + MessageText);
End;

Procedure TProjectAssistantForm.SetSelectedBuildSectionStatus(NewStatus: TPlanSectionStatus);
Var
  PlanRel, Err, SectionTitle, Feedback: String;
  Idx: Integer;
  OldStatus: TPlanSectionStatus;
Begin
  PlanRel := GetActivePlanRelativePath;
  If PlanRel = '' Then
    Begin
      SetBuildStatusFeedback('Set an active plan on the Plan tab first.');
      MessageDlg('Set an active plan on the Plan tab first.', mtInformation, [mbOK], 0);
      Exit;
    End;
  Idx := SelectedBuildSectionIndex;
  If Idx < 0 Then
    Begin
      SetBuildStatusFeedback(BuildSelectionMessage);
      MessageDlg(BuildSelectionMessage, mtInformation, [mbOK], 0);
      Exit;
    End;
  { Copy title/status before RefreshBuildTodos frees BuildSections entries. }
  SectionTitle := TPlanSection(BuildSections[Idx]).Title;
  OldStatus := TPlanSection(BuildSections[Idx]).Status;
  If OldStatus = NewStatus Then
    Begin
      Feedback := Format('"%s" is already %s.',
        [SectionTitle, PlanSectionStatusToStr(NewStatus)]);
      SetBuildStatusFeedback(Feedback);
      Exit;
    End;
  If Not SetPlanSectionStatus(PlanRel, Idx, NewStatus, Err) Then
    Begin
      SetBuildStatusFeedback('Failed: ' + Err);
      MessageDlg(Err, mtError, [mbOK], 0);
      Exit;
    End;
  FBuildSelectedIndex := Idx;
  RefreshBuildTodos;
  If Assigned(BuildTodoList) And (Idx >= 0) And (Idx < BuildTodoList.Items.Count) Then
    Begin
      BuildTodoList.ItemIndex := Idx;
      FBuildSelectedIndex := Idx;
    End;
  Feedback := Format('%s → %s', [SectionTitle, PlanSectionStatusToStr(NewStatus)]);
  SetBuildStatusFeedback(Feedback);
  SetCurrentSystemNote(Format('Plan status updated: **%s** → `%s`.',
    [SectionTitle, PlanSectionStatusToStr(NewStatus)]));
  If NewStatus = pssComplete Then
    Begin
      ClearBuildWorkTracking;
      If WorkingRootHasGitRepository(ProjectAssistantRoot) Then
        SetCurrentSystemNote(Format(
          'Plan status updated: **%s** → complete. This working root is a Git repository. Commit the plan file if that completion should be in history.',
          [SectionTitle]));
    End;
End;

Procedure TProjectAssistantForm.ClearBuildWorkTracking;
Begin
  FBuildWorkSectionIndex := -1;
  FBuildWorkSectionTitle := '';
  FBuildWorkPlanPath := ''; FBuildWorkPlanText := ''; FBuildWorkBody := ''; FBuildWorkIdentity := '';
  FCompletionBuildJSON := ''; FCompletionTestJSON := '';
End;

Procedure TProjectAssistantForm.BeginBuildWorkTracking(SectionIndex: Integer; Const SectionTitle: String);
Var Note: String;
Begin
  ClearBuildWorkTracking;
  FBuildWorkSectionIndex := SectionIndex; FBuildWorkSectionTitle := SectionTitle;
  If Not Assigned(FCodexWorkspace) Then FCodexWorkspace := TAssistantIDEWorkspace.Create;
  FBuildWorkIdentity := FCodexWorkspace.Identity;
  If Not ResolvePlanPath(GetActivePlanRelativePath, FBuildWorkPlanPath, Note) Or
    Not ReadBuildInput(FBuildWorkPlanPath, FBuildWorkPlanText, Note) Or
    Not GetPlanSectionBody(FBuildWorkPlanPath, SectionIndex, FBuildWorkBody, Note) Then
    FBuildWorkPlanPath := '';
End;

Procedure TProjectAssistantForm.TryAutoCompleteBuildWork(Const StreamErrorText: String);
Var
  PlanRel, Err, Note, CurrentPlan: String;
  Idx: Integer; Editor: TSourceEditorInterface;
Begin
  Idx := FBuildWorkSectionIndex;
  If Idx < 0 Then Exit;
  If StreamErrorText <> '' Then
    Begin
      SetBuildStatusFeedback('Work interrupted — item still in progress.');
      RefreshBuildTodos;
      Exit;
    End;
  { The saved plan is authoritative. The pre-turn text has no Validation line on most items,
    and stopping on that text ended the run after a completion had already been written. }
  If FPlanAgentRunning And BuildWorkSectionIsComplete Then
    Begin
      FPlanAgentResumeIndex := -1;
      SetBuildStatusFeedback(Format('%s → complete', [FBuildWorkSectionTitle]));
      Exit;
    End;
  { A clean compile is not enough. Only Validation: build or Validation: tests with matching evidence.
    An item with no machine criterion stays in progress and the plan agent continues it. }
  If Not CheckAssistantAcceptance(FBuildWorkBody, FCompletionBuildJSON, FCompletionTestJSON, Note) Then
    Begin
      If FPlanAgentRunning And AssistantAcceptanceIsHumanReview(Note) Then
        Begin
          FPlanAgentResumeIndex := FBuildWorkSectionIndex;
          SetBuildStatusFeedback(Format('%s stays in progress. The plan agent continues this item.',
            [FBuildWorkSectionTitle]));
        End
      Else
        Begin
          FPlanAgentResumeIndex := -1;
          SetBuildStatusFeedback(Note);
          If FPlanAgentRunning Then
            StopWorkOnPlanAgent(Note);
        End;
      Exit;
    End;
  If WorkingRootHasGitRepository(ProjectAssistantRoot) Then
    Begin
      Note := Note + ' This working root is a Git repository, so the item stays in progress until a commit contains the completion.';
      SetBuildStatusFeedback(Note);
      If FPlanAgentRunning Then
        StopWorkOnPlanAgent(Note);
      Exit;
    End;
  If (FBuildWorkPlanPath = '') Or Not Assigned(FCodexWorkspace) Or
    (FCodexWorkspace.Identity <> FBuildWorkIdentity) Or
    Not ResolvePlanPath(GetActivePlanRelativePath, PlanRel, Err) Or (PlanRel <> FBuildWorkPlanPath) Or
    Not ReadBuildInput(PlanRel, CurrentPlan, Err) Or (CurrentPlan <> FBuildWorkPlanText) Then
    Begin
      SetBuildStatusFeedback('Project or plan changed during work; review before using Done.');
      Exit;
    End;
  If Not Assigned(SourceEditorManagerIntf) Then Exit;
  Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(PlanRel);
  If Assigned(Editor) And (Editor.Modified Or (Editor.SourceText <> CurrentPlan)) Then
    Begin
      SetBuildStatusFeedback('Plan has unsaved edits; review before using Done.');
      Exit;
    End;
  { The full saved plan still matches the selected section snapshot. }
  FBuildSelectedIndex := Idx;
  If Not SetPlanSectionStatus(PlanRel, Idx, pssComplete, Err) Then
    Begin
      SetBuildStatusFeedback('Auto-complete failed: ' + Err);
      WorkflowLogger.Warning('ProjectAssistant', 'Auto Status complete failed: ' + Err);
      Exit;
    End;
  RefreshBuildTodos;
  If Assigned(BuildTodoList) And (Idx >= 0) And (Idx < BuildTodoList.Items.Count) Then
    Begin
      BuildTodoList.ItemIndex := Idx;
      FBuildSelectedIndex := Idx;
    End;
  Note := Format('Auto-marked **%s** complete. %s', [FBuildWorkSectionTitle, Note]);
  SetBuildStatusFeedback(Format('%s → complete (auto)', [FBuildWorkSectionTitle]));
  If FViewingLive Then
    Begin
      If FDisplaySystemNote <> '' Then
        FDisplaySystemNote := FDisplaySystemNote + LineEnding + LineEnding + Note
      Else
        FDisplaySystemNote := Note;
    End
  Else
    SetCurrentSystemNote(Note);
  WorkflowLogger.Info('ProjectAssistant', 'Auto Status complete: ' + FBuildWorkSectionTitle);
  ClearBuildWorkTracking;
End;

Function TProjectAssistantForm.BuildWorkSectionIsComplete: Boolean;
Var
  Sections: TObjectList;
  Err: String;
Begin
  Result := False;
  If (FBuildWorkPlanPath = '') Or (FBuildWorkSectionIndex < 0) Then
    Exit;
  Sections := TObjectList.Create(True);
  Try
    If Not ScanPlanSections(FBuildWorkPlanPath, Sections, Err) Then
      Exit;
    If FBuildWorkSectionIndex >= Sections.Count Then
      Exit;
    Result := TPlanSection(Sections[FBuildWorkSectionIndex]).Status = pssComplete;
  Finally
    Sections.Free;
  End;
End;

Procedure TProjectAssistantForm.PrepareTopErrorAfterReview(ErrorCount: Integer);
Var
  Line: TMessageLine;
Begin
  FReviewErrorCount := ErrorCount;
  FPendingReviewErrorOffer := ErrorCount > 0;
  If Not FPendingReviewErrorOffer Then
    Exit;
  Line := ResolveMessageLineForFix(True);
  If Assigned(Line) And Assigned(IDEMessagesWindow) Then
    IDEMessagesWindow.SelectMsgLine(Line);
End;

Procedure TProjectAssistantForm.OfferFixTopErrorAfterReview;
Var
  Line: TMessageLine;
  Note, MsgText: String;
Begin
  If Not FPendingReviewErrorOffer Then
    Exit;
  FPendingReviewErrorOffer := False;
  Line := ResolveMessageLineForFix(True);
  If Not Assigned(Line) Then
    Begin
      Note := Format('Review found **%d error(s)**. Open Messages, then click **Fix Error**.',
        [FReviewErrorCount]);
      If FViewingLive Then
        FDisplaySystemNote := Note
      Else
        SetCurrentSystemNote(Note);
      Exit;
    End;
  If Assigned(IDEMessagesWindow) Then
    IDEMessagesWindow.SelectMsgLine(Line);
  If Line.TranslatedMsg <> '' Then
    MsgText := Line.TranslatedMsg
  Else
    MsgText := Line.Msg;
  If Line.Filename <> '' Then
    MsgText := ExtractFileName(Line.GetFullFilename) + ': ' + MsgText;
  Note :=
    Format('Review found **%d error(s)**. Top error is selected in Messages.', [FReviewErrorCount]) +
    LineEnding + LineEnding +
    '**' + Trim(MsgText) + '**' + LineEnding + LineEnding +
    'Click **Fix Error** (or Assistant → Fix Error in Build mode) to apply a Build-mode fix with tools.';
  If FViewingLive Then
    Begin
      If FDisplaySystemNote <> '' Then
        FDisplaySystemNote := FDisplaySystemNote + LineEnding + LineEnding + Note
      Else
        FDisplaySystemNote := Note;
    End
  Else
    SetCurrentSystemNote(Note);
  StatusFooter.SetRightText('Review: Fix Error ready');
End;

Procedure TProjectAssistantForm.BuildRefreshButtonClick(Sender: TObject);
Begin
  RefreshBuildTodos;
  SetBuildStatusFeedback('TODO list refreshed from plan file.');
End;

Procedure TProjectAssistantForm.BuildOpenPlanButtonClick(Sender: TObject);
Var
  PlanRel, Resolved, Err: String;
Begin
  PlanRel := GetActivePlanRelativePath;
  If PlanRel = '' Then
    Begin
      MessageDlg('No active plan. Use the Plan tab to create or set one.', mtInformation, [mbOK], 0);
      Exit;
    End;
  If Not ResolvePlanPath(PlanRel, Resolved, Err) Then
    Begin
      MessageDlg(Err, mtError, [mbOK], 0);
      Exit;
    End;
  OpenMarkdownDocument(Resolved);
End;

Procedure TProjectAssistantForm.BuildStartButtonClick(Sender: TObject);
Begin
  SetSelectedBuildSectionStatus(pssInProgress);
End;

Procedure TProjectAssistantForm.BuildDoneButtonClick(Sender: TObject);
Begin
  SetSelectedBuildSectionStatus(pssComplete);
End;

Procedure TProjectAssistantForm.BuildResetButtonClick(Sender: TObject);
Begin
  SetSelectedBuildSectionStatus(pssNotStarted);
End;

Function TProjectAssistantForm.BuildWorkPrompt(Const PlanRel, SectionTitle, StatusText,
  SectionBody, ParentTitle: String; ContinueSameItem: Boolean): String;
Const MaxBodyChars = 6000;
Var Body, ToolInstructions, Heading: String;
Begin
  Body := Trim(SectionBody);
  If Length(Body) > MaxBodyChars Then
    Body := Copy(Body, 1, MaxBodyChars) + LineEnding + LineEnding +
      '… *(section truncated for the prompt; open the plan file for the full text.)*';
  If FUseCodex Then
    ToolInstructions :=
      '2. Inspect with lazarus_project_info, lazarus_list_directory and lazarus_read_file. Open buffers before editing; use fresh revisions. ' +
      'Apply authorized changes with the advertised Lazarus edit tools and save explicitly.' + LineEnding +
      '3. Start a build and poll lazarus_build_status with its job_id until done. Repair introduced errors and rebuild. ' +
      'For Validation: tests, run the configured test command with that build_job_id and poll its test job. ' +
      'Report source coverage gaps, stale evidence and missing/failed test reports.'
  Else
    ToolInstructions :=
      '2. Discover with search_in_project, get_project_info, list_directory and read_file. Apply authorized edits using the available project tools. ' +
      'Use ensure_form_component for coordinated Pascal/LFM changes; do not create temporary probe units.' + LineEnding +
      '3. Run run_compile after edits, repair introduced errors and compile again. ' +
      'A clean compile does not mark this item complete.';
  Heading := '**Active plan:** `' + PlanRel + '`' + LineEnding;
  If Trim(ParentTitle) <> '' Then
    Heading := Heading + '**Section:** ' + ParentTitle + LineEnding;
  Heading := Heading + '**Item:** ' + SectionTitle + LineEnding + '**Status:** ' + StatusText + LineEnding + LineEnding;
  If ContinueSameItem Then
    Result := 'Continue this same plan item in **Build mode**. The previous turn left it in progress.' +
      LineEnding + LineEnding +
      'Edits already applied are in the project. Do not re-read a file you already have unless a later replace_in_file failed.' +
      LineEnding +
      'Run run_compile. A folder target compiles the Lazarus packages under that folder, not the project open in the IDE.' +
      LineEnding +
      'When the written acceptance criteria are met, commit the finished files, set Status to complete, then commit the plan file. ' +
      'A missing Validation line does not block that status change. A clean compile alone does not complete the item.' +
      LineEnding + LineEnding + Heading
  Else
    Result := 'Work on this plan item in **Build mode**.' + LineEnding + LineEnding + Heading;
  Result := Result +
    'Instructions:' + LineEnding + '1. Focus only on this actionable item unless blocked.' + LineEnding +
    ToolInstructions + LineEnding +
    '4. ' + AssistantPlanCompletionRules + LineEnding +
    '5. Follow the acceptance criteria in the section. Do not change validation requirements to make work pass. ' +
    'Unchecked acceptance items require manual review. A clean compile alone does not prove correct behavior.' +
    LineEnding + LineEnding + '----- begin plan section -----' + LineEnding + Body + LineEnding + '----- end plan section -----';
End;

Procedure TProjectAssistantForm.BuildWorkOnSelectedPackage;
Var
  PlanRel, Err, Body, Prompt, Title, StatusText, ParentTitle: String;
  Idx: Integer;
  Section: TPlanSection;
Begin
  If FSending Then
    Begin
      MessageDlg('Wait for the current reply to finish (or Stop) before starting work.',
        mtInformation, [mbOK], 0);
      Exit;
    End;
  PlanRel := GetActivePlanRelativePath;
  If PlanRel = '' Then
    Begin
      MessageDlg('Set an active plan on the Plan tab first.', mtInformation, [mbOK], 0);
      Exit;
    End;
  Idx := SelectedBuildSectionIndex;
  If Idx < 0 Then
    Begin
      MessageDlg(BuildSelectionMessage, mtInformation, [mbOK], 0);
      Exit;
    End;
  Section := TPlanSection(BuildSections[Idx]);
  Title := Section.Title;
  ParentTitle := Section.ParentTitle;
  StatusText := PlanSectionStatusToStr(Section.Status);
  If Section.Status = pssUnknown Then
    StatusText := 'unknown';
  { Mark in progress when starting work from a not-started package. }
  If Section.Status In [pssNotStarted, pssUnknown] Then
    Begin
      If Not SetPlanSectionStatus(PlanRel, Idx, pssInProgress, Err) Then
        Begin
          MessageDlg('Could not set status to in progress:' + LineEnding + Err, mtWarning, [mbOK], 0);
          { Continue with the prompt anyway. }
        End
      Else
        Begin
          StatusText := PlanSectionStatusToStr(pssInProgress);
          FBuildSelectedIndex := Idx;
          RefreshBuildTodos;
          If Assigned(BuildTodoList) And (Idx < BuildTodoList.Items.Count) Then
            BuildTodoList.ItemIndex := Idx;
        End;
    End;
  If Not GetPlanSectionBody(PlanRel, Idx, Body, Err) Then
    Begin
      MessageDlg('Could not load plan section:' + LineEnding + Err, mtError, [mbOK], 0);
      Exit;
    End;
  Prompt := BuildWorkPrompt(PlanRel, Title, StatusText, Body, ParentTitle,
    FPlanAgentRunning And (Idx = FPlanAgentResumeIndex));
  FPlanAgentResumeIndex := -1;
  { Stay in Build mode (tools + prompt) while showing the chat turn surface. }
  BeginBuildWorkTracking(Idx, Title);
  ForceModeAndLock(amBuild);
  ShowChatSurfaceKeepMode;
  SetBuildStatusFeedback('Working on: ' + Title);
  SubmitUserText(Prompt, True);
  If Not FSending Then
    Begin
      UnlockModeAfterSend;
      ClearBuildWorkTracking;
    End;
End;

Procedure TProjectAssistantForm.BuildWorkButtonClick(Sender: TObject);
Begin
  If FPlanAgentRunning Then
    Begin
      MessageDlg('Plan agent is already running. Use Stop to cancel the current reply, then try again.',
        mtInformation, [mbOK], 0);
      Exit;
    End;
  BuildWorkOnSelectedPackage;
End;

Function TProjectAssistantForm.FindNextIncompleteBuildSection: Integer;
Var
  I: Integer;
  Section: TPlanSection;
  FirstNotStarted: Integer;
Begin
  Result := -1;
  FirstNotStarted := -1;
  If Not Assigned(BuildSections) Then
    Exit;
  For I := 0 To BuildSections.Count - 1 Do
    Begin
      Section := TPlanSection(BuildSections[I]);
      If Not Section.Actionable Then
        Continue;
      If Section.Status = pssInProgress Then
        Begin
          Result := I;
          Exit;
        End;
      If (FirstNotStarted < 0) And (Section.Status = pssNotStarted) Then
        FirstNotStarted := I;
    End;
  Result := FirstNotStarted;
End;

Procedure TProjectAssistantForm.StopWorkOnPlanAgent(Const Reason: String);
Begin
  If Not FPlanAgentRunning Then
    Exit;
  FPlanAgentRunning := False;
  Application.RemoveAsyncCalls(Self);
  SetBuildStatusFeedback('Plan agent stopped: ' + Reason);
  SetCurrentSystemNote('**Plan agent stopped:** ' + Reason);
  UpdateStatusFooter;
  WorkflowLogger.Info('ProjectAssistant', 'Plan agent stopped: ' + Reason);
End;

Procedure TProjectAssistantForm.StartWorkOnPlanAgent;
Var
  Idx: Integer;
Begin
  If FSending Or FPlanAgentRunning Then
    Begin
      MessageDlg('Wait for the current reply to finish before starting Work on plan.',
        mtInformation, [mbOK], 0);
      Exit;
    End;
  If GetActivePlanRelativePath = '' Then
    Begin
      MessageDlg('Set an active plan on the Plan mode panel first.', mtInformation, [mbOK], 0);
      Exit;
    End;
  EnsureBuildTabUi;
  RefreshBuildTodos;
  Idx := FindNextIncompleteBuildSection;
  If Idx < 0 Then
    Begin
      MessageDlg('All plan packages are already complete (or none found).', mtInformation, [mbOK], 0);
      Exit;
    End;
  FPlanAgentRunning := True;
  FPlanAgentPackagesDone := 0;
  FPlanAgentResumeIndex := -1;
  FLastTurnHadError := False;
  FBuildSelectedIndex := Idx;
  If Assigned(BuildTodoList) And (Idx < BuildTodoList.Items.Count) Then
    BuildTodoList.ItemIndex := Idx;
  SetBuildStatusFeedback('Plan agent: starting…');
  SetCurrentSystemNote(
    '**Plan agent** started — will work through incomplete packages until complete, error, ' +
    'context ≥ 95%, or max packages.');
  SelectMode(amBuild);
  BuildWorkOnSelectedPackage;
  If Not FSending Then
    StopWorkOnPlanAgent('could not start first package');
End;

Procedure TProjectAssistantForm.ContinueWorkOnPlanAgent(Data: PtrInt);
Var
  Idx, Pct: Integer;
Begin
  If csDestroying In ComponentState Then Exit;
  If Not FPlanAgentRunning Then
    Exit;
  If FSending Then
    Begin
      Application.QueueAsyncCall(@ContinueWorkOnPlanAgent, 0);
      Exit;
    End;
  If FLastTurnHadError Then
    Begin
      StopWorkOnPlanAgent('last package ended with an error');
      Exit;
    End;
  If FContextLimit > 0 Then
    Begin
      FContextUsed := AssistantClient.EstimatedPromptTokens;
      Pct := (FContextUsed * 100) Div FContextLimit;
      If Pct >= 95 Then
        Begin
          If AutoNewChatAtLimitEnabled Then
            Begin
              { Rollover into a fresh conversation and keep walking packages. }
              FContextWarnShown := False;
              MaybeWarnHighContextUsage;
              { Fall through to next package with cleared history. }
            End
          Else
            Begin
              MaybeWarnHighContextUsage;
              StopWorkOnPlanAgent(Format('context usage %d%% — start a New Chat', [Pct]));
              Exit;
            End;
        End;
    End;
  If FPlanAgentPackagesDone >= FPlanAgentMaxPackages Then
    Begin
      StopWorkOnPlanAgent(Format('reached max packages (%d)', [FPlanAgentMaxPackages]));
      Exit;
    End;
  EnsureBuildTabUi;
  RefreshBuildTodos;
  Idx := FindNextIncompleteBuildSection;
  If Idx < 0 Then
    Begin
      StopWorkOnPlanAgent(Format('all packages complete (%d worked this run)',
        [FPlanAgentPackagesDone]));
      Exit;
    End;
  FBuildSelectedIndex := Idx;
  If Assigned(BuildTodoList) And (Idx < BuildTodoList.Items.Count) Then
    BuildTodoList.ItemIndex := Idx;
  SetBuildStatusFeedback(Format('Plan agent: package %d…', [FPlanAgentPackagesDone + 1]));
  BuildWorkOnSelectedPackage;
  If Not FSending Then
    StopWorkOnPlanAgent('failed to start next package');
End;

Procedure TProjectAssistantForm.BuildWorkPlanButtonClick(Sender: TObject);
Begin
  If FPlanAgentRunning Then
    Begin
      If MessageDlg('Stop the plan agent after the current reply finishes?',
        mtConfirmation, [mbYes, mbNo], 0) = mrYes Then
        StopWorkOnPlanAgent('stopped by user');
      Exit;
    End;
  StartWorkOnPlanAgent;
End;

Procedure TProjectAssistantForm.BuildTodoListClick(Sender: TObject);
Begin
  If Assigned(BuildTodoList) And Assigned(BuildSections) And
    (BuildTodoList.ItemIndex >= 0) And
    (BuildTodoList.ItemIndex < BuildSections.Count) Then
    FBuildSelectedIndex := BuildTodoList.ItemIndex;
End;

Procedure TProjectAssistantForm.BuildTodoListSelectionChange(Sender: TObject; User: Boolean);
Begin
  If Assigned(BuildTodoList) And Assigned(BuildSections) And
    (BuildTodoList.ItemIndex >= 0) And
    (BuildTodoList.ItemIndex < BuildSections.Count) Then
    FBuildSelectedIndex := BuildTodoList.ItemIndex;
End;

Procedure TProjectAssistantForm.BuildTodoListDblClick(Sender: TObject);
Begin
  BuildTodoListClick(Sender);
  If ActiveMode <> amBuild Then
    Begin
      SeedPromptFromSelectedWork;
      If ActiveMode In [amChat, amInspect] Then
        SetCurrentSystemNote('Switch to **Build** to apply source edits for this package.');
      Exit;
    End;
  BuildWorkOnSelectedPackage;
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
Var
  Root: String;
  RootChanged: Boolean;
Begin
  If Not Assigned(ProjectAssistantConversation) Then
    Exit;
  Root := ProjectAssistantRoot;
  If Root = '' Then
    Exit;
  RootChanged := Not SameFileName(ExcludeTrailingPathDelimiter(ProjectAssistantConversation.ProjectRoot),
    ExcludeTrailingPathDelimiter(Root)) Or (ProjectAssistantConversation.TargetStoreKey <> AssistantTarget.StoreKey);
  If RootChanged Then
    Begin
      ProjectAssistantConversation.SetProjectRoot(Root, AssistantTarget.StoreKey);
      ProjectAssistantConversation.Load; { one bulk parse into memory }
      ApplyShellConfigFromStore;
    End
  Else If Not ProjectAssistantConversation.Loaded Then
    Begin
      ProjectAssistantConversation.Load;
      ApplyShellConfigFromStore;
    End;
End;

Function TProjectAssistantForm.ConversationListTurnIndex(ListIndex: Integer): Integer;
Var
  Encoded: Integer;
Begin
  { Objects store TurnIndex+1 so index 0 is never stored as Nil.
    Live in-flight row uses LiveConversationMarker+1. }
  Result := -1;
  If Not Assigned(ConversationList) Or (ListIndex < 0) Or (ListIndex >= ConversationList.Items.Count) Then
    Exit;
  Encoded := Integer(PtrUInt(ConversationList.Items.Objects[ListIndex]));
  If Encoded = 0 Then
    Exit;
  Result := Encoded - 1; { may be LiveConversationMarker (-2) }
End;

Procedure TProjectAssistantForm.ShowConversationTurn(TurnIndex: Integer; Navigate: Boolean);
Var
  Turn: TConversationTurn;
Begin
  FSelectedTurnIndex := TurnIndex;
  If TurnIndex = LiveConversationMarker Then
    Begin
      { Follow the in-flight turn (background stream may still be running). }
      FViewingLive := True;
      FDisplayUser := FLiveUser;
      FAssistantContent := FLiveContent;
      FAssistantThinking := FLiveThinking;
      FDisplayTraceJson := '';
      FDisplayEventsFile := '';
      FDisplaySystemNote := '';
      FDisplayDurationMs := 0;
      FDisplayThinkingMs := 0;
      RefreshChatDisplay(True, FSending);
      If Assigned(FTraceView) Then FTraceView.ScrollToEnd;
      Exit;
    End;
  FViewingLive := False;
  If Not Assigned(ProjectAssistantConversation) Then
    Exit;
  If Not ProjectAssistantConversation.GetTurn(TurnIndex, Turn) Then
    Begin
      WorkflowLogger.Warning('ProjectAssistant', 'ShowConversationTurn failed idx=' + IntToStr(TurnIndex) +
        ' ' + ProjectAssistantConversation.LastError);
      Exit;
    End;
  FDisplayUser := Turn.Prompt;
  FAssistantContent := Turn.Response;
  FAssistantThinking := Turn.Thinking;
  FDisplayTraceJson := Turn.TraceJson;
  FDisplayEventsFile := Turn.EventsFile;
  FDisplayDurationMs := Turn.DurationMs;
  FDisplayThinkingMs := Turn.ThinkingMs;
  If Turn.ErrorText <> '' Then
    FDisplaySystemNote := '**Error:** ' + Turn.ErrorText
  Else
    FDisplaySystemNote := '';
  RefreshChatDisplay(True, False);
  If Navigate And Assigned(FTraceView) Then FTraceView.NavigateTurn(Turn.Id);
End;

Procedure TProjectAssistantForm.ShowLastConversationTurn;
Var
  N: Integer;
Begin
  If Not Assigned(ProjectAssistantConversation) Then
    Begin
      RefreshChatDisplay(True, False);
      Exit;
    End;
  N := ProjectAssistantConversation.TurnCount;
  If N > 0 Then
    ShowConversationTurn(N - 1, False)
  Else
    Begin
      ClearCurrentTurnDisplay;
      RefreshChatDisplay(True, False);
    End;
End;

Procedure TProjectAssistantForm.RefreshConversationList;
Var
  I, SeqNo, KeepTurnIndex: Integer;
  Entry: TConversationIndexEntry;
  Filter, Line, Preview: String;
  ShowItem: Boolean;
  SelectIdx: Integer;
Begin
  If Not Assigned(ConversationList) Or Not Assigned(ProjectAssistantConversation) Then
    Exit;
  EnsureConversationStore;
  Filter := '';
  If Assigned(ConversationSearch) Then
    Filter := LowerCase(Trim(ConversationSearch.Text));
  KeepTurnIndex := FSelectedTurnIndex;
  If KeepTurnIndex < 0 Then
    KeepTurnIndex := ConversationListTurnIndex(ConversationList.ItemIndex);
  SelectIdx := -1;
  FIgnoreConversationListChange := True;
  ConversationList.Items.BeginUpdate;
  Try
    ConversationList.Clear;
    { Oldest first so new turns append at the bottom (grow down).
      Objects store TurnIndex+1 (never 0/Nil) for O(1) memory retrieval. }
    For I := 0 To ProjectAssistantConversation.IndexCount - 1 Do
      Begin
        Entry := ProjectAssistantConversation.IndexEntry(I);
        If Not Assigned(Entry) Then
          Continue;
        SeqNo := I + 1;
        Line := IntToStr(SeqNo) + ' - ' + Entry.PromptPreview;
        If Entry.ErrorText <> '' Then
          Line := Line + ' [err]';
        ShowItem := True;
        If Filter <> '' Then
          ShowItem := (Pos(Filter, LowerCase(Entry.PromptPreview)) > 0) Or
            (Pos(Filter, LowerCase(Entry.ResponsePreview)) > 0) Or
            (Pos(Filter, LowerCase(Entry.Mode)) > 0);
        If ShowItem Then
          Begin
            ConversationList.Items.AddObject(Line, TObject(PtrUInt(Entry.TurnIndex + 1)));
            If Entry.TurnIndex = KeepTurnIndex Then
              SelectIdx := ConversationList.Items.Count - 1;
          End;
      End;
    { In-flight prompt at the bottom while the model runs — omit once the turn
      is recorded so the list never shows live + completed duplicates. }
    If FSending And (Not FTurnRecorded) And (FLiveUser <> '') Then
      Begin
        Preview := FLiveUser;
        Preview := StringReplace(Preview, #13#10, ' ', [rfReplaceAll]);
        Preview := StringReplace(Preview, #10, ' ', [rfReplaceAll]);
        If Length(Preview) > 120 Then
          Preview := Copy(Preview, 1, 119) + '…';
        SeqNo := ProjectAssistantConversation.IndexCount + 1;
        Line := IntToStr(SeqNo) + ' - ' + Preview + ' …';
        ShowItem := True;
        If Filter <> '' Then
          ShowItem := Pos(Filter, LowerCase(Preview)) > 0;
        If ShowItem Then
          Begin
            ConversationList.Items.AddObject(Line, TObject(PtrUInt(LiveConversationMarker + 1)));
            If (KeepTurnIndex = LiveConversationMarker) Or FViewingLive Then
              SelectIdx := ConversationList.Items.Count - 1;
          End;
      End;
  Finally
    ConversationList.Items.EndUpdate;
    FIgnoreConversationListChange := False;
  End;
  If ConversationList.Items.Count > 0 Then
    Begin
      If SelectIdx < 0 Then
        SelectIdx := ConversationList.Items.Count - 1;
      FIgnoreConversationListChange := True;
      Try
        ConversationList.ItemIndex := SelectIdx;
        ConversationList.TopIndex := SelectIdx;
      Finally
        FIgnoreConversationListChange := False;
      End;
      FSelectedTurnIndex := ConversationListTurnIndex(SelectIdx);
    End;
End;

Procedure TProjectAssistantForm.ConversationSearchChange(Sender: TObject);
Begin
  RefreshConversationList;
End;

Procedure TProjectAssistantForm.RefreshHistoryCombo;
Var
  Items: TObjectList;
  I, SelectIdx: Integer;
  Hist: TConversationHistoryItem;
  PrevId: String;
Begin
  If Not Assigned(HistoryCombo) Or Not Assigned(HistoryIds) Then
    Exit;
  PrevId := '';
  If (HistoryCombo.ItemIndex >= 0) And (HistoryCombo.ItemIndex < HistoryIds.Count) Then
    PrevId := HistoryIds[HistoryCombo.ItemIndex];
  FHistoryUpdating := True;
  Items := TObjectList.Create(True);
  Try
    HistoryCombo.Items.BeginUpdate;
    Try
      HistoryCombo.Items.Clear;
      HistoryIds.Clear;
      If Assigned(ProjectAssistantConversation) And (ProjectAssistantConversation.ProjectRoot <> '') Then
        ProjectAssistantConversation.ListHistory(Items);
      SelectIdx := 0;
      For I := 0 To Items.Count - 1 Do
        Begin
          Hist := TConversationHistoryItem(Items[I]);
          If Not Assigned(Hist) Then
            Continue;
          HistoryCombo.Items.Add(Hist.Title);
          HistoryIds.Add(Hist.ArchiveId);
          If SameText(Hist.ArchiveId, PrevId) Then
            SelectIdx := HistoryCombo.Items.Count - 1;
          If Hist.IsCurrent Then
            SelectIdx := HistoryCombo.Items.Count - 1;
        End;
      If HistoryCombo.Items.Count = 0 Then
        Begin
          HistoryCombo.Items.Add('Current (empty)');
          HistoryIds.Add('');
          SelectIdx := 0;
        End;
      If SelectIdx >= HistoryCombo.Items.Count Then
        SelectIdx := 0;
      HistoryCombo.ItemIndex := SelectIdx;
    Finally
      HistoryCombo.Items.EndUpdate;
    End;
  Finally
    Items.Free;
    FHistoryUpdating := False;
  End;
  UpdateHistoryActions;
End;

Procedure TProjectAssistantForm.UpdateHistoryActions;
Begin
  If Assigned(ExportHistoryAction) Then
    ExportHistoryAction.Enabled := (Not FSending) And Assigned(ProjectAssistantConversation) And
      ProjectAssistantConversation.HasTurns;
  If Assigned(DeleteHistoryAction) Then
    DeleteHistoryAction.Enabled := (Not FSending) And Assigned(ProjectAssistantConversation) And
      (ProjectAssistantConversation.ProjectRoot <> '');
End;

Function TProjectAssistantForm.DefaultExportFileName: String;
Var
  Stamp, Title: String;
  I: Integer;
Begin
  Stamp := FormatDateTime('yyyymmdd"-"hhnnss', Now);
  Title := 'conversation';
  If Assigned(HistoryCombo) And (HistoryCombo.ItemIndex >= 0) Then
    Title := HistoryCombo.Items[HistoryCombo.ItemIndex];
  If SameText(Copy(Title, 1, 7), 'Current') Then
    Begin
      Title := Trim(Copy(Title, 8, MaxInt));
      If (Title <> '') And (Title[1] = '—') Then
        Title := Trim(Copy(Title, 2, MaxInt));
      If (Title = '') Or SameText(Title, '(empty)') Then
        Title := 'conversation';
    End;
  For I := 1 To Length(Title) Do
    If Title[I] In ['/', '\', ':', '*', '?', '"', '<', '>', '|'] Then
      Title[I] := '-';
  If Length(Title) > 48 Then
    Title := Copy(Title, 1, 48);
  Result := Title + '-' + Stamp + '.md';
End;

Function TProjectAssistantForm.BuildConversationMarkdownExport: String;
Var
  SL: TStringList;
  I: Integer;
  Turn: TConversationTurn;
  ProjectName, MetaLine, TraceMd: String;
  Trace: TAssistantTrace;
Begin
  SL := TStringList.Create;
  Try
    ProjectName := AssistantTarget.DisplayName;
    SL.Add('# Project Assistant conversation');
    SL.Add('');
    SL.Add('- **Exported:** ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
    SL.Add('- **Project:** ' + ProjectName);
    If Assigned(AssistantChatConfig) Then
      SL.Add('- **Model:** ' + AssistantChatConfig.Model)
    Else
      SL.Add('- **Model:** ' + FModelName);
    SL.Add('- **Turns:** ' + IntToStr(ProjectAssistantConversation.TurnCount));
    SL.Add('');
    SL.Add('---');
    SL.Add('');
    For I := 0 To ProjectAssistantConversation.TurnCount - 1 Do
      Begin
        If Not ProjectAssistantConversation.GetTurn(I, Turn) Then
          Continue;
        SL.Add('## Turn ' + IntToStr(I + 1));
        If Turn.CreatedAt <> '' Then
          Begin
            SL.Add('');
            MetaLine := '*' + Turn.CreatedAt;
            If Turn.Mode <> '' Then
              MetaLine := MetaLine + ' · mode ' + Turn.Mode;
            If Turn.Model <> '' Then
              MetaLine := MetaLine + ' · ' + Turn.Model;
            SL.Add(MetaLine + '*');
          End;
        SL.Add('');
        SL.Add('### User');
        SL.Add('');
        If Trim(Turn.Prompt) <> '' Then
          SL.Add(Turn.Prompt)
        Else If Trim(Turn.AttachmentsJson) = '' Then
          SL.Add('*(empty)*');
        If Trim(Turn.AttachmentsJson) <> '' Then
          AppendAssistantImageFileNames(Turn.AttachmentsJson, SL);
        SL.Add('');
        If Trim(Turn.TraceJson) <> '' Then
          Begin
            Trace := TAssistantTrace.Create;
            Try
              Trace.LoadFromJson(Turn.TraceJson);
              TraceMd := Trace.FormatMarkdown(False);
              If Trim(TraceMd) <> '' Then
                SL.Add(TraceMd)
              Else
                Begin
                  SL.Add('### Assistant');
                  SL.Add('');
                  If Trim(Turn.Response) <> '' Then
                    SL.Add(Turn.Response)
                  Else
                    SL.Add('*(empty)*');
                End;
            Finally
              Trace.Free;
            End;
          End
        Else
          Begin
            If Trim(Turn.Thinking) <> '' Then
              Begin
                SL.Add('### Thinking');
                SL.Add('');
                SL.Add(Turn.Thinking);
                SL.Add('');
              End;
            SL.Add('### Assistant');
            SL.Add('');
            If Trim(Turn.Response) <> '' Then
              SL.Add(Turn.Response)
            Else If Trim(Turn.ErrorText) <> '' Then
              SL.Add('*(no response)*')
            Else
              SL.Add('*(empty)*');
          End;
        If Trim(Turn.ErrorText) <> '' Then
          Begin
            SL.Add('');
            SL.Add('**Error:** ' + Turn.ErrorText);
          End;
        SL.Add('');
        SL.Add('---');
        SL.Add('');
      End;
    Result := SL.Text;
  Finally
    SL.Free;
  End;
End;

Procedure TProjectAssistantForm.RebuildClientFromConversation;
Var
  I, Before: Integer;
  Turn: TConversationTurn;
  Refs: TAssistantImageRefArray;
Begin
  If Assigned(AssistantClient) Then
    AssistantClient.ClearHistory;
  FContextUsed := 0;
  If Not Assigned(ProjectAssistantConversation) Or Not Assigned(AssistantClient) Then
    Exit;
  For I := 0 To ProjectAssistantConversation.TurnCount - 1 Do
    Begin
      If Not ProjectAssistantConversation.GetTurn(I, Turn) Then
        Continue;
      Before := AssistantClient.MessageCount;
      If Trim(Turn.MessagesJson) <> '' Then
        AssistantClient.RestoreMessagesJson(Turn.MessagesJson)
      Else
        Begin
          { AddMessage would keep an empty prompt and drop the look sentence.
            An image-only turn must still send that sentence with the picture. }
          SetLength(Refs, 0);
          ParseAssistantImageRefs(Turn.AttachmentsJson, Refs);
          If Length(Refs) > 0 Then
            AssistantClient.AddUserMessage(Turn.Prompt, Refs)
          Else If Trim(Turn.Prompt) <> '' Then
            AssistantClient.AddMessage(amrUser, Turn.Prompt);
          If Trim(Turn.Response) <> '' Then
            AssistantClient.AddMessage(amrAssistant, Turn.Response);
        End;
      If Trim(Turn.AttachmentsJson) <> '' Then
        AssistantClient.EnsureUserImageRefsFrom(Before, Turn.AttachmentsJson);
      FContextUsed := FContextUsed + Length(Turn.Prompt) Div 4 + Length(Turn.Response) Div 4 + 8;
    End;
  AssistantClient.NoteMessagesStored;
  FContextUsed := AssistantClient.EstimatedPromptTokens;
End;

Procedure TProjectAssistantForm.ApplyLoadedConversationToUi(Const StatusNote: String);
Begin
  Transcript.Clear;
  FUserCancelled := False;
  FTurnRecorded := False;
  FLastChatPaintTick := 0;
  ClearCurrentTurnDisplay;
  RebuildClientFromConversation;
  RefreshHistoryCombo;
  RefreshConversationList;
  ShowLastConversationTurn;
  If StatusNote <> '' Then
    SetCurrentSystemNote(StatusNote);
  UpdateStatusFooter;
End;

Procedure TProjectAssistantForm.ConversationListClick(Sender: TObject);
Begin
  ConversationListSelectionChange(Sender, True);
End;

Procedure TProjectAssistantForm.ConversationListSelectionChange(Sender: TObject; User: Boolean);
Var
  TurnIndex: Integer;
Begin
  If FIgnoreConversationListChange Then
    Exit;
  { Allow browsing past turns while a stream continues in the background. }
  If Not Assigned(ConversationList) Or (ConversationList.ItemIndex < 0) Then
    Exit;
  TurnIndex := ConversationListTurnIndex(ConversationList.ItemIndex);
  If TurnIndex < LiveConversationMarker Then
    Exit;
  { Marker is -2; completed turns are >= 0. Decode already applied +1 offset. }
  If (TurnIndex < 0) And (TurnIndex <> LiveConversationMarker) Then
    Exit;
  ShowConversationTurn(TurnIndex);
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

Procedure TProjectAssistantForm.RecordCurrentTurn(Const ErrorText: String);
Var
  Turn: TConversationTurn;
  Entry: TConversationIndexEntry;
  DurationMs: Integer;
Begin
  { One stream → one conversation row (guard against double IsFinished / Stop+Finish). }
  If FTurnRecorded Then
    Exit;
  If Not Assigned(ProjectAssistantConversation) Then
    Exit;
  EnsureConversationStore;
  If ProjectAssistantConversation.ProjectRoot = '' Then
    Exit;
  If Assigned(AssistantClient) Then
    Begin
      Turn.MessagesJson := AssistantClient.ExportUnstoredMessagesJson;
      Turn.AttachmentsJson := AssistantClient.OpeningUserAttachmentsJson;
    End;
  If (Trim(FLiveUser) = '') And (Trim(FDisplayUser) = '') And
    (Trim(FLiveContent) = '') And (Trim(FAssistantContent) = '') And (Trim(ErrorText) = '') And
    (Trim(Turn.AttachmentsJson) = '') Then
    Exit;
  DurationMs := CurrentStreamDurationMs;
  Turn.Id := NewConversationTurnId;
  Turn.Mode := AssistantModeToStr(ActiveMode);
  If FLiveUser <> '' Then
    Turn.Prompt := FLiveUser
  Else
    Turn.Prompt := FDisplayUser;
  If Assigned(FTrace) And (Trim(Turn.AttachmentsJson) <> '') Then
    ApplyTurnAttachmentsToTrace(FTrace, Turn.AttachmentsJson);
  If Assigned(FTrace) And (FTrace.Count > 0) Then
    Begin
      Turn.TraceJson := FTrace.SaveToJson;
      Turn.Thinking := FTrace.JoinedThinking;
      Turn.Response := FTrace.JoinedAnswers;
      If Turn.Response = '' Then
        If FLiveContent <> '' Then
          Turn.Response := FLiveContent
        Else
          Turn.Response := FAssistantContent;
    End
  Else
    Begin
      Turn.TraceJson := '';
      If FLiveThinking <> '' Then
        Turn.Thinking := FLiveThinking
      Else
        Turn.Thinking := FAssistantThinking;
      If FLiveContent <> '' Then
        Turn.Response := FLiveContent
      Else
        Turn.Response := FAssistantContent;
    End;
  Turn.CreatedAt := IsoNowUtc;
  Turn.StartedAt := FTurnStartedAt;
  If Turn.StartedAt = '' Then
    Turn.StartedAt := Turn.CreatedAt;
  Turn.FinishedAt := IsoNowUtc;
  Turn.DurationMs := DurationMs;
  If Assigned(FTrace) Then
    Turn.ThinkingMs := FTrace.ThinkingDurationMs
  Else
    Turn.ThinkingMs := 0;
  Turn.Model := FModelName;
  If (Not FUseCodex) And Assigned(AssistantClient) Then
    Turn.Skill := AssistantClient.ActiveSkill
  Else
    Turn.Skill := '';
  Turn.TokenEstimate := Length(Turn.Prompt + Turn.Response + Turn.Thinking) Div 4;
  Turn.ErrorText := ErrorText;
  Turn.PlanFile := GetActivePlanRelativePath;
  Turn.TodoId := '';
  Turn.EventsFile := '';
  If (Not FUseCodex) And Assigned(AssistantClient) And (AssistantClient.LastEventsFile <> '') Then
    Turn.EventsFile := AssistantEventsRelativePath(AssistantClient.LastEventsFile,
      ProjectAssistantConversation.ProjectRoot);
  If ProjectAssistantConversation.AppendTurn(Turn, Entry) Then
    Begin
      FTurnRecorded := True;
      If Assigned(AssistantClient) Then
        AssistantClient.NoteMessagesStored;
      RefreshHistoryCombo;
    End
  Else
    WorkflowLogger.Warning('ProjectAssistant', 'Conversation append failed: ' + ProjectAssistantConversation.LastError);
End;

Function TProjectAssistantForm.CurrentStreamDurationMs: Integer;
Begin
  Result := 0;
  If StreamStart > 0 Then
    Result := Round((Now - StreamStart) * 24 * 60 * 60 * 1000);
  If Result < 0 Then
    Result := 0;
End;

Procedure TProjectAssistantForm.FinishLiveTrace(Const SystemNote: String; DurationMs: Integer);
Var
  Last: TTraceBlock;
Begin
  If Not Assigned(FTrace) Then
    Exit;
  FTrace.EnsureUser(FDisplayUser);
  ApplyLiveAnswerSlice;
  FTrace.FinishCurrentThinking;
  FTrace.FinishCurrentAnswer;
  If SystemNote <> '' Then
    Begin
      Last := Nil;
      If FTrace.Count > 0 Then
        Last := FTrace[FTrace.Count - 1];
      If (Not Assigned(Last)) Or (Last.Kind <> tbkNote) Or (Last.Body <> SystemNote) Then
        FTrace.AddNote(SystemNote);
    End;
  FTrace.ApplyWorkedFooter(DurationMs);
End;

Procedure TProjectAssistantForm.ToggleThinkingActionExecute(Sender: TObject);
Begin
  FShowThinking := Not FShowThinking;
  UpdateViewActionCaptions;
  PersistShellConfig;
  RefreshChatDisplay(True, False);
End;

Procedure TProjectAssistantForm.ToggleToolUseActionExecute(Sender: TObject);
Begin
  FShowToolUse := Not FShowToolUse;
  UpdateViewActionCaptions;
  PersistShellConfig;
  RefreshChatDisplay(True, False);
End;

Function TProjectAssistantForm.FormatElapsedStatus(Const Phase: String): String;
Var
  Secs, Mins, Rem: Integer;
  ReconnectSecs: QWord;
Begin
  If Phase = 'Re-establishing Connection' Then
    Begin
      ReconnectSecs := (GetTickCount64 - FReconnectStartTick) Div 1000;
      If ReconnectSecs >= 3600 Then
        Result := Format('%s %d:%2.2d:%2.2d', [Phase, ReconnectSecs Div 3600,
          (ReconnectSecs Div 60) Mod 60, ReconnectSecs Mod 60])
      Else
        Result := Format('%s %2.2d:%2.2d', [Phase, ReconnectSecs Div 60,
          ReconnectSecs Mod 60]);
      Exit;
    End;
  If StreamStart <= 0 Then
    Begin
      Result := Phase;
      Exit;
    End;
  Secs := Round((Now - StreamStart) * 24 * 60 * 60);
  If Secs < 0 Then
    Secs := 0;
  Mins := Secs Div 60;
  Rem := Secs Mod 60;
  Result := Format('%s %d:%2.2d', [Phase, Mins, Rem]);
End;

Procedure TProjectAssistantForm.SetStreamPhase(Const Phase: String);
Begin
  If (Phase = 'Re-establishing Connection') And (FStatusPhase <> Phase) Then
    FReconnectStartTick := GetTickCount64;
  FStatusPhase := Phase;
  StatusFooter.SetRightText(FormatElapsedStatus(Phase));
End;

Function TProjectAssistantForm.ApproveCodexTool(Const Tool, Path, OldText, NewText: String): Boolean;
Var Dialog: TForm; Description: TLabel; BeforeMemo, AfterMemo: TMemo;
  AllowButton, DeclineButton: TButton; WasEnabled: Boolean;
Begin
  WasEnabled := ElapsedTimer.Enabled; ElapsedTimer.Enabled := False;
  Dialog := TForm.CreateNew(Self);
  Try
    Dialog.Caption := 'Review ChatGPT tool request'; Dialog.Position := poOwnerFormCenter;
    Dialog.SetBounds(0, 0, 800, 600); Dialog.BorderStyle := bsDialog;
    Description := TLabel.Create(Dialog); Description.Parent := Dialog;
    Description.AutoSize := False; Description.WordWrap := True; Description.SetBounds(16, 16, 768, 64);
    If Tool = 'lazarus_start_tests' Then
      Description.Caption := 'Run the configured project test executable and arguments shown below. The working directory is the project directory; no files will be saved automatically.'
    Else If Tool = 'lazarus_start_build' Then
      Description.Caption := 'Allow a build of the active project using its saved files and configured build commands?'
    Else If Tool = 'lazarus_save_buffer' Then
      Description.Caption := 'Save this exact buffer to disk: ' + Path
    Else If Tool = 'lazarus_create_file' Then
      Description.Caption := 'Create this new file and any missing parent directories (proposed text below): ' + Path
    Else If (Tool = 'lazarus_apply_changes') Or (Tool = 'lazarus_revert_changes') Then
      Description.Caption := 'Review all listed editor changes (current/expected text above, proposed text below). No files will be saved. Recovery skips editors changed since application.'
    Else If Tool = 'lazarus_apply_local_rename' Then
      Description.Caption := 'Apply this local variable/constant rename without saving (current text above, proposed text below): ' + Path
    Else Description.Caption := 'Replace this buffer (current text above, proposed text below): ' + Path;
    BeforeMemo := TMemo.Create(Dialog); BeforeMemo.Parent := Dialog;
    BeforeMemo.SetBounds(16, 88, 768, 200); BeforeMemo.ReadOnly := True;
    BeforeMemo.ScrollBars := ssBoth; BeforeMemo.WordWrap := False; BeforeMemo.Text := OldText;
    AfterMemo := TMemo.Create(Dialog); AfterMemo.Parent := Dialog;
    AfterMemo.SetBounds(16, 304, 768, 230); AfterMemo.ReadOnly := True;
    AfterMemo.ScrollBars := ssBoth; AfterMemo.WordWrap := False; AfterMemo.Text := NewText;
    AfterMemo.Visible := (Tool = 'lazarus_replace_buffer') Or (Tool = 'lazarus_create_file') Or (Tool = 'lazarus_apply_local_rename') Or (Tool = 'lazarus_apply_changes') Or (Tool = 'lazarus_revert_changes');
    BeforeMemo.Visible := (Tool <> 'lazarus_start_build') And (Tool <> 'lazarus_create_file');
    If Tool = 'lazarus_create_file' Then AfterMemo.SetBounds(16, 88, 768, 446);
    If Tool = 'lazarus_save_buffer' Then BeforeMemo.Height := 446;
    AllowButton := TButton.Create(Dialog); AllowButton.Parent := Dialog; AllowButton.Caption := 'Allow once';
    AllowButton.SetBounds(550, 552, 110, 32); AllowButton.ModalResult := mrYes;
    DeclineButton := TButton.Create(Dialog); DeclineButton.Parent := Dialog; DeclineButton.Caption := 'Decline';
    DeclineButton.SetBounds(674, 552, 110, 32); DeclineButton.ModalResult := mrCancel;
    DeclineButton.Cancel := True; DeclineButton.Default := True;
    Result := Dialog.ShowModal = mrYes;
    If Result Then Result := Assigned(FCodexRun) And Not FCodexRun.Snapshot.Done;
  Finally Dialog.Free; ElapsedTimer.Enabled := WasEnabled And Assigned(FCodexRun); End;
End;

Procedure TProjectAssistantForm.LoadConnectionSettings;
Var Connections: TAssistantConnections; Item: TAssistantConnection;
Begin
  Try
    FUseCodex := False;
    If Not Assigned(LazarusIDE) Then Exit;
    Connections := TAssistantConnections.Create(LazarusIDE.GetPrimaryConfigPath);
    Try
      Connections.Load; Item := Connections.Active;
      FUseCodex := Assigned(Item) And (Item.Backend = 'codex');
      If FUseCodex Then
        Begin
          FCodexRuntime := Item.Runtime; FCodexModel := Item.Model;
          FCodexProfile := Connections.ProfileDir(Item);
          { Model, effort and approval stay on the connection and apply to this turn, not the profile. }
          FCodexEffort := Item.ReasoningEffort; FCodexApproval := Item.ApprovalMode;
        End;
    Finally Connections.Free; End;
  Except
    On E: Exception Do
      Begin
        FUseCodex := False;
        WorkflowLogger.Error('PluginBoundary', 'TProjectAssistantForm.LoadConnectionSettings: ' + E.Message);
      End;
  End;
End;

Procedure TProjectAssistantForm.ReleaseCodexRun;
Begin
  If Assigned(FCodexBroker) Then FCodexBroker.Cancel;
  If Assigned(FCodexRun) Then
    Begin
      FCodexRun.Cancel;
      ReapCodexWorker(FCodexRun);
      FCodexRun := Nil;
    End;
End;

Function TProjectAssistantForm.StartCodexReply(Const DisplayText, ApiText: String): Boolean;
Var
  Prompt, Recap, ContextText, ModelText: String;
  I: Integer;
  Turn: TConversationTurn;
  WithContext: Boolean;
  Refs: TAssistantImageRefArray;
Begin
  Result := False;
  If (FCodexRuntime = '') Or (FCodexModel = '') Then
    Begin
      SettingsActionExecute(Nil);
      If Not FUseCodex Then Exit;
      If (FCodexRuntime = '') Or (FCodexModel = '') Then Exit;
    End;
  If FPlanAgentRunning Then
    Begin
      StopWorkOnPlanAgent('ChatGPT preview supports individual turns; automatic plan execution is not enabled.');
      Exit;
    End;
  SetLength(Refs, 0);
  ParseAssistantImageRefs(FComposerImagesJson, Refs);
  Refs := LimitAssistantImageRefs(Refs);
  ModelText := AssistantImageModelText(ApiText, Length(Refs));
  If Length(Refs) > 0 Then
    Begin
      { ChatGPT does not receive the picture. Leave the composer intact. }
      SetCurrentSystemNote(AssistantCodexImageAttachReason);
      MessageDlg(AssistantCodexImageAttachReason, mtInformation, [mbOK], 0);
      If Assigned(InputMemo) Then
        InputMemo.Text := DisplayText;
      Exit;
    End;
  If Assigned(AssistantClient) Then
    AssistantClient.AddUserMessage(ModelText, Refs);
  If Not Assigned(FCodexWorkspace) Then FCodexWorkspace := TAssistantIDEWorkspace.Create;
  If Not Assigned(FCodexBroker) Then FCodexBroker := TAssistantToolBroker.Create(FCodexWorkspace);
  FCodexIdentity := FCodexWorkspace.Identity;
  FCodexBroker.OnApproval := Nil;
  If FCodexApproval = 'ask' Then FCodexBroker.OnApproval := @ApproveCodexTool;
  Case ActiveMode Of
    amChat: FCodexBroker.BeginRun(awsNone);
    amBuild: FCodexBroker.BeginRun(awsProject);
    amPlan: FCodexBroker.BeginRun(awsMarkdown);
  Else FCodexBroker.BeginRun(awsReadOnly); End;
  RefreshFromConfig;
  Recap := '';
  If Assigned(ProjectAssistantConversation) Then
    For I := ProjectAssistantConversation.TurnCount - 1 DownTo 0 Do
      Begin
        If Length(Recap) >= 24000 Then Break;
        If ProjectAssistantConversation.GetTurn(I, Turn) And (Turn.Model = FModelName) Then
          Recap := 'User: ' + Copy(Turn.Prompt, 1, 4000) + LineEnding +
            'Assistant: ' + Copy(Turn.Response, 1, 8000) + LineEnding + Recap;
      End;
  WithContext := (ActiveMode <> amChat) And Assigned(AssistantChatConfig) And AssistantChatConfig.IncludeIDEContext;
  ContextText := '';
  If WithContext Then ContextText := BuildIDEContextBlockLight;
  If ActiveMode = amChat Then
    Prompt := 'You are a helpful assistant in a general chat. You have no project tools, no IDE access, and no attached skill. ' +
      'Answer directly. Do not claim you can read or edit files.' + LineEnding +
      'Previous conversation (bounded recap):' + LineEnding +
      Recap + LineEnding + 'Current user request:' + LineEnding + ModelText
  Else
    Prompt := 'You are assisting inside the Lazarus IDE. Use the lazarus_* tools for project work. ' +
    'Discover target files with lazarus_list_directory and lazarus_read_file, which prefers unsaved buffers. ' +
    'Before editing a closed file, use lazarus_open_buffer; read buffers before editing and use returned revisions. ' +
    'Use lazarus_find_declaration or lazarus_symbol_context with a current buffer revision for Pascal symbol lookup; columns are UTF-8 byte offsets. ' +
    'For build/repair work, save only authorized changes, start a build and poll its job_id until done. Use diagnostic items to locate failures, reread before repair, then rebuild. Report stale or incomplete evidence and distinguish compilation from tests. After a successful current build, use lazarus_start_tests with its build_job_id and poll lazarus_test_status with the test job_id. If no runner is configured, report missing test evidence. ' +
    'For coordinated edits, read every buffer and use lazarus_prepare_changes then lazarus_apply_changes in Build. Inspect per-file outcomes; lazarus_change_status and lazarus_revert_changes provide retained recovery. Reread before saving. ' +
    'For a routine-local variable or constant rename, use lazarus_preview_local_rename, review its changes, then lazarus_apply_local_rename in Build; save separately. ' +
    'Use lazarus_find_references with an explicit list of project search_paths; check searchedFiles, failedFiles and truncation before claiming coverage. ' +
    'Ask is read-only. Plan can create, edit and save project Markdown (.md, .markdown, .mdown), but cannot change sources or build. ' +
    'Build allows new project text files, explicit buffer edits, saves, saved-input builds and Git via lazarus_run_git. ' +
    'For Git, save authorized edits first, inspect status and the staged diff, stage explicit files and exclude unrelated changes. ' +
    'Read the active plan including its overall instructions. Honor explicit conversation or plan instructions to commit automatically after completing and validating changes, without asking again; tool approval settings still apply. Preserve these instructions in plans and report the commit hash only after successful Git evidence. ' +
    AssistantPlanCompletionRules + ' ' +
    'Use lazarus_create_file to save a new report or other text file; it never overwrites existing content. ' +
    'Do not use shell, external tools or filesystem fallbacks. Explain unavailable capabilities. ' +
    'A successful build is not proof that all dependencies were frozen or verified.' + LineEnding +
    'Mode: ' + AssistantModeToStr(ActiveMode) + LineEnding +
    'Active plan: ' + GetActivePlanRelativePath + LineEnding +
    ContextText + LineEnding + 'Previous conversation (bounded recap):' + LineEnding +
    Recap + LineEnding + 'Current user request:' + LineEnding + ModelText;
  If ActiveMode = amPlan Then
    Prompt := Prompt + LineEnding + AssistantPlanAuthoringRules + LineEnding;
  If Not FModeLocked Then LockModeForSend;
  ShowChatSurfaceKeepMode;
  SetCurrentUserDisplay(DisplayText, WithContext);
  FLiveUser := FDisplayUser; FLiveContent := ''; FLiveThinking := '';
  FAssistantContent := ''; FAssistantThinking := '';
  AppendMessage('user', FDisplayUser);
  FContextUsed := Length(Prompt) Div 4;
  FStatusPhase := 'Connecting to ChatGPT…';
  SetSending(True);
  BeginAssistantReply;
  Try
    FCodexRun := TAssistantCodexRun.Create(FCodexRuntime, FCodexProfile, FCodexModel,
      Prompt, FCodexBroker.ToolsJson, FCodexBroker.RunId, 600000, FCodexProfile, FCodexEffort);
    FCodexRun.Start;
    Result := True;
  Except
    On E: Exception Do
      Begin
        ReleaseCodexRun;
        FinishAssistantReply(E.Message);
        Result := False;
      End;
  End;
End;

Procedure TProjectAssistantForm.PollCodex;
Var Snapshot: TCodexRunSnapshot; Tool: TCodexToolRequest;
  ToolText, EvidenceError: String; OK, Serviced: Boolean; Block: TTraceBlock; Run: TAssistantCodexRun;
Begin
  If FPollingCodex Then Exit;
  FPollingCodex := True;
  Try
    Run := FCodexRun;
    If FCodexWorkspace.Identity <> FCodexIdentity Then
      Begin
        StopStream;
        Exit;
      End;
    Snapshot := FCodexRun.Snapshot;
    ApplyAssistantSnapshots(Snapshot.Content, Snapshot.Thinking);
    Serviced := Run.ServiceOneTool(FCodexBroker, Tool, ToolText, OK);
    If FCodexRun <> Run Then Exit; { cancelled/replaced during an IDE callback }
    If Serviced Then
      Begin
        { Use the text captured at the tool request, even if the worker advanced
          between the timer snapshot and the IDE handoff. }
        ApplyAssistantSnapshots(Tool.ContentBefore, Tool.ThinkingBefore);
        ApplyLiveThinkingAndAnswer;
        Block := FTrace.AddTool(Tool.CallId, Tool.Tool, Tool.Arguments);
        Block.Body := ToolText; Block.Ok := OK; Block.Running := False;
        FAnswerSliceStart := Length(FLiveContent) + 1;
        FThinkingSliceStart := Length(FLiveThinking) + 1;
        FTrace.StartThinking(0);
        RefreshChatDisplay(False, True);
      End;
    If Snapshot.Done Then
      Begin
        { Capture current evidence before releasing the broker cancels its jobs. }
        FCompletionBuildJSON := ''; FCompletionTestJSON := '';
        If (FBuildWorkSectionIndex >= 0) And (ActiveMode = amBuild) And (Snapshot.ErrorText = '') Then
          Begin
            FCodexWorkspace.BuildStatus(FCompletionBuildJSON, EvidenceError);
            If FCodexRun <> Run Then Exit;
            FCodexWorkspace.TestStatus(FCompletionTestJSON, EvidenceError);
            If FCodexRun <> Run Then Exit;
          End;
        ReleaseCodexRun;
        FinishAssistantReply(Snapshot.ErrorText);
      End
    Else
      Begin
        StatusFooter.SetRightText(FormatElapsedStatus('ChatGPT'));
        If FViewingLive Then FTraceView.RefreshElapsed(FTrace);
      End;
  Finally FPollingCodex := False; End;
End;

Procedure TProjectAssistantForm.ElapsedTimerTimer(Sender: TObject);
Begin
  Try
    If csDestroying In ComponentState Then Exit;
    If Assigned(FCodexRun) Then
      Begin
        PollCodex;
        Exit;
      End;
    If FSending And (FStatusPhase <> '') Then
      StatusFooter.SetRightText(FormatElapsedStatus(FStatusPhase));
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
        WorkflowLogger.Error('PluginBoundary', 'TProjectAssistantForm.ElapsedTimerTimer: ' + E.Message);
      End;
  End;
End;

Procedure TProjectAssistantForm.RefreshFromConfig;
Begin
  If Assigned(AssistantChatConfig) And Assigned(AssistantClient) Then
    Begin
      AssistantClient.ApplyConfig(AssistantChatConfig);
      FModelName := AssistantChatConfig.Model;
    End
  Else If Assigned(AssistantClient) Then
    FModelName := AssistantClient.Model;
  If FUseCodex Then FModelName := 'ChatGPT / ' + FCodexModel;
  SyncAutoNewChatCheckFromConfig;
  UpdateStatusFooter;
End;

Function TProjectAssistantForm.AutoNewChatAtLimitEnabled: Boolean;
Begin
  If Assigned(AutoNewChatCheck) Then
    Result := AutoNewChatCheck.Checked
  Else If Assigned(AssistantChatConfig) Then
    Result := AssistantChatConfig.AutoNewChatAtContextLimit
  Else
    Result := False;
End;

Procedure TProjectAssistantForm.SyncAutoNewChatCheckFromConfig;
Begin
  If Not Assigned(AutoNewChatCheck) Then
    Exit;
  AutoNewChatCheck.OnClick := Nil;
  Try
    If Assigned(AssistantChatConfig) Then
      AutoNewChatCheck.Checked := AssistantChatConfig.AutoNewChatAtContextLimit
    Else
      AutoNewChatCheck.Checked := False;
  Finally
    AutoNewChatCheck.OnClick := @AutoNewChatCheckClick;
  End;
End;

Procedure TProjectAssistantForm.AutoNewChatCheckClick(Sender: TObject);
Begin
  If Not Assigned(AutoNewChatCheck) Or Not Assigned(AssistantChatConfig) Then
    Exit;
  AssistantChatConfig.AutoNewChatAtContextLimit := AutoNewChatCheck.Checked;
  AssistantChatConfig.Save;
  WorkflowLogger.Info('ProjectAssistant',
    'Auto New Chat at 95%: ' + BoolToStr(AutoNewChatCheck.Checked, True));
End;

Procedure TProjectAssistantForm.UpdateStatusFooter;
Var
  Pct: Integer;
  StatusText, LeftText, CentreText, ThinkCap, ApprCap, BlockReason: String;
Begin
  If (Not FUseCodex) And Assigned(AssistantClient) And (Not FSending) Then
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
        FStatusPhase := 'Waiting for first token…';
      StatusText := FormatElapsedStatus(FStatusPhase);
    End
  Else If FPlanAgentRunning Then
    StatusText := Format('Plan agent… %d done', [FPlanAgentPackagesDone])
  Else If FReviewInProgress Then
    StatusText := 'Reviewing…'
  Else If FUseCodex Then
    StatusText := 'ChatGPT preview'
  Else If Assigned(AssistantChatConfig) And AssistantChatConfig.IsSignedIn Then
    StatusText := 'Ready'
  Else
    StatusText := 'Not signed in';
  ThinkCap := 'High';
  ApprCap := 'Always';
  If Assigned(AssistantChatConfig) Then
    Begin
      ThinkCap := ThinkingLevelCaption(AssistantChatConfig.GetThinkingLevel);
      ApprCap := ApprovalModeCaption(AssistantChatConfig.GetApprovalMode);
    End;
  LeftText := Format('%s · Think %s · %s', [FModelName, ThinkCap, ApprCap]);
  CentreText := Format('Context %d%%', [Pct]);
  If Pct >= 95 Then
    CentreText := CentreText + ' ⚠';
  If FUseCodex Then
    Begin
      ThinkCap := FCodexEffort; If ThinkCap = '' Then ThinkCap := 'model default';
      LeftText := Format('%s · Think %s · %s', [FModelName, ThinkCap, FCodexApproval]);
      CentreText := Format('Context ~%d tokens', [FContextUsed]);
    End;
  StatusFooter.SetLeftText(ModeStatusText);
  StatusFooter.SetModelText(LeftText);
  StatusFooter.SetCentreText(CentreText);
  StatusFooter.SetRightText(StatusText);
  StatusFooter.SetLeftHint(ModeStatusText);
  StatusFooter.SetModelHint('Click to change model, thinking level, or approval');
  If (Not FUseCodex) And Assigned(AssistantClient) And (Not AssistantClient.ImagesAttachAllowed(BlockReason)) And
    (BlockReason <> '') Then
    StatusFooter.SetModelHint('Click to change model, thinking level, or approval. ' + BlockReason);
  StatusFooter.SetCentreHint(Format('About %d of %d tokens. Click for a breakdown.',
    [FContextUsed, FContextLimit]));
  StatusFooter.SetRightHint('Click for session info');
  If FUseCodex Then
    Begin
      StatusFooter.SetModelHint('Click for ChatGPT connection and model. ' + AssistantCodexImageAttachReason);
      If Assigned(SendAction) Then SendAction.Hint := AssistantCodexImageAttachReason;
      RefreshAttachAction;
      StatusFooter.SetCentreHint('Estimated context; provider allowance is checked on each request');
      If ActiveMode = amChat Then
        Begin
          StatusFooter.SetSkillText('Skill: not sent');
          StatusFooter.SetSkillHint('Chat does not send a skill or Lazarus tools');
        End
      Else
        Begin
          StatusFooter.SetSkillText('Lazarus tools');
          StatusFooter.SetSkillHint('ChatGPT preview uses the Lazarus tool broker');
        End;
    End
  Else
    Begin
      If Assigned(SendAction) Then SendAction.Hint := '';
      RefreshAttachAction;
      If ActiveMode = amChat Then
        Begin
          StatusFooter.SetSkillText('Skill: not sent');
          StatusFooter.SetSkillHint('Chat does not send a skill');
        End
      Else If Assigned(AssistantChatConfig) And (AssistantChatConfig.ActiveSkill <> '') Then
        Begin
          StatusFooter.SetSkillText(AssistantChatConfig.ActiveSkill);
          StatusFooter.SetSkillHint('Click to pin a different skill');
        End
      Else
        Begin
          StatusFooter.SetSkillText('Skill: none');
          StatusFooter.SetSkillHint('Click to pin a skill');
        End;
    End;
  If (Not FUseCodex) And (Not FSending) And (Pct >= 95) Then
    MaybeWarnHighContextUsage;
End;

Procedure TProjectAssistantForm.MaybeWarnHighContextUsage;
Var
  Pct: Integer;
  KeepAgent: Boolean;
Begin
  If FContextWarnShown Or FAutoRolloverInProgress Then
    Exit;
  If FContextLimit <= 0 Then
    Exit;
  Pct := (FContextUsed * 100) Div FContextLimit;
  If Pct < 95 Then
    Exit;
  FContextWarnShown := True;
  If AutoNewChatAtLimitEnabled Then
    Begin
      KeepAgent := FPlanAgentRunning;
      FAutoRolloverInProgress := True;
      Try
        SetCurrentSystemNote(
          Format('**Context usage at %d%%** — automatically starting a **New Chat** to free the token budget.',
            [Pct]));
        StartNewChat(KeepAgent, False);
        SetCurrentSystemNote(
          Format('**New Chat** started automatically at %d%% context use. Previous conversation is in History.',
            [Pct]));
        WorkflowLogger.Info('ProjectAssistant',
          Format('Auto New Chat at %d%% context (keep plan agent=%s)',
            [Pct, BoolToStr(KeepAgent, True)]));
      Finally
        FAutoRolloverInProgress := False;
      End;
      Exit;
    End;
  SetCurrentSystemNote(
    Format('**Context usage is high (%d%%).** Start a **New Chat** before continuing long Build/Plan work ' +
      'so the model stays within its token limit. Or enable **Auto New Chat at 95%%** on this form.',
      [Pct]));
  MessageDlg(
    Format('Context usage is at about %d%% of the budget.%s%s' +
      'Start a New Chat before continuing large Plan/Build sessions, or enable "Auto New Chat at 95%%" ' +
      'on the assistant form (default is set in Settings).',
      [Pct, LineEnding, LineEnding]),
    mtWarning, [mbOK], 0);
End;

Procedure TProjectAssistantForm.SetSending(IsSending: Boolean);
Begin
  If (Not FUseCodex) And IsSending And (Not FSending) Then
    AssistantBeginQuietIdeSession
  Else If (Not FUseCodex) And (Not IsSending) And FSending Then
    AssistantEndQuietIdeSession;
  FSending := IsSending;
  If Assigned(FTargetCombo) Then FTargetCombo.Enabled := Not IsSending;
  If Assigned(FTargetBrowseButton) Then FTargetBrowseButton.Enabled := Not IsSending;
  If IsSending Then
    Begin
      FPlanWriteThisTurn := False;
      ResetAssistantGitTurn;
      ResetAssistantPlanTurn;
      ShowPlanOfferBar(False);
    End;
  If Not IsSending Then
    FReviewInProgress := False;
  SendAction.Enabled := True;
  If IsSending Then
    SendAction.Caption := 'Steer'
  Else
    SendAction.Caption := 'Send';
  StopAction.Enabled := IsSending;
  NewChatAction.Enabled := Not IsSending;
  ReviewCompileAction.Enabled := (Not IsSending) And (Not FReviewInProgress);
  ReviewBuildAction.Enabled := (Not IsSending) And (Not FReviewInProgress);
  ReviewChangesAction.Enabled := (Not IsSending) And (Not FReviewInProgress);
  FixErrorAction.Enabled := Not IsSending;
  { Prompt stays live so the user can Steer without aborting the turn. }
  If Assigned(InputMemo) Then
    InputMemo.ReadOnly := False;
  SetBusyCursor(IsSending);
  If IsSending Then
    Begin
      StreamStart := Now;
      If FStatusPhase = '' Then
        FStatusPhase := 'Waiting for first token…';
      If Assigned(ElapsedTimer) Then
        ElapsedTimer.Enabled := True;
    End
  Else
    Begin
      If Assigned(ElapsedTimer) Then
        ElapsedTimer.Enabled := False;
      FStatusPhase := '';
      StreamStart := 0;
    End;
  ApplyActiveMode;
  UpdateHistoryActions;
  UpdateStatusFooter;
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
        WorkflowLogger.Error('PluginBoundary', 'TProjectAssistantForm.DeferredBind: ' + E.Message);
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
        WorkflowLogger.Error('PluginBoundary', 'TProjectAssistantForm.DeferredShowLastTurn: ' + E.Message);
      End;
  End;
End;

Procedure TProjectAssistantForm.EnsureChatView;
Begin
  If Assigned(FTraceView) Then
    Exit;
  If Not Assigned(ChatHost) Then
    Exit;
  ChatHost.Color := clWindow;
  ChatHost.ParentColor := False;
  ChatHost.ParentBackground := False;
  FTraceView := TAssistantTraceView.Create(Self);
  FTraceView.Parent := ChatHost;
  FTraceView.Align := alClient;
  FTraceView.BorderSpacing.Around := ChatViewMargin;
  FTraceView.ShowThinking := FShowThinking;
  FTraceView.ShowToolUse := FShowToolUse;
  ChatView := FTraceView;
  If Not Assigned(FTrace) Then
    FTrace := TAssistantTrace.Create;
End;

Procedure TProjectAssistantForm.EnsureInputPopup;
Var
  Sep: TMenuItem;
Begin
  If Assigned(InputPopup) Or (Not Assigned(InputMemo)) Then
    Exit;
  InputPopup := TPopupMenu.Create(Self);
  InputPopup.OnPopup := @InputPopupPopup;
  InputCutItem := TMenuItem.Create(InputPopup);
  InputCutItem.Caption := 'Cut';
  InputCutItem.ShortCut := ShortCut(Ord('X'), [ssCtrl]);
  InputCutItem.OnClick := @InputCutClick;
  InputPopup.Items.Add(InputCutItem);
  InputCopyItem := TMenuItem.Create(InputPopup);
  InputCopyItem.Caption := 'Copy';
  InputCopyItem.ShortCut := ShortCut(Ord('C'), [ssCtrl]);
  InputCopyItem.OnClick := @InputCopyClick;
  InputPopup.Items.Add(InputCopyItem);
  InputPasteItem := TMenuItem.Create(InputPopup);
  InputPasteItem.Caption := 'Paste';
  { No shortcut. Ctrl+V is handled by the memo so a disabled item cannot eat the key. }
  InputPasteItem.OnClick := @InputPasteClick;
  InputPopup.Items.Add(InputPasteItem);
  Sep := TMenuItem.Create(InputPopup);
  Sep.Caption := '-';
  InputPopup.Items.Add(Sep);
  InputSelectAllItem := TMenuItem.Create(InputPopup);
  InputSelectAllItem.Caption := 'Select All';
  InputSelectAllItem.ShortCut := ShortCut(Ord('A'), [ssCtrl]);
  InputSelectAllItem.OnClick := @InputSelectAllClick;
  InputPopup.Items.Add(InputSelectAllItem);
  InputMemo.PopupMenu := InputPopup;
  InputMemo.WantTabs := False;
End;

Function ClipboardHasImage: Boolean; Forward;

Procedure TProjectAssistantForm.InputPopupPopup(Sender: TObject);
Var
  HasSel: Boolean;
  CanEdit: Boolean;
Begin
  HasSel := Assigned(InputMemo) And (InputMemo.SelLength > 0);
  CanEdit := Assigned(InputMemo) And (Not InputMemo.ReadOnly);
  If Assigned(InputCutItem) Then
    InputCutItem.Enabled := HasSel And CanEdit;
  If Assigned(InputCopyItem) Then
    InputCopyItem.Enabled := HasSel;
  If Assigned(InputPasteItem) Then
    { Always offer Paste while the memo can edit. A disabled Ctrl+V shortcut
      swallows the key before the composer can read an image. }
    InputPasteItem.Enabled := CanEdit;
  If Assigned(InputSelectAllItem) Then
    InputSelectAllItem.Enabled := Assigned(InputMemo) And (InputMemo.GetTextLen > 0);
End;

Procedure TProjectAssistantForm.InputCutClick(Sender: TObject);
Begin
  If Assigned(InputMemo) And (Not InputMemo.ReadOnly) Then
    InputMemo.CutToClipboard;
End;

Procedure TProjectAssistantForm.InputCopyClick(Sender: TObject);
Begin
  If Assigned(InputMemo) Then
    InputMemo.CopyToClipboard;
End;

Function DroppedLocalPath(Const Name: String): String; Forward;

Function StillImageExtension(Const Path: String): Boolean;
Var
  Ext: String;
Begin
  Ext := LowerCase(ExtractFileExt(Path));
  Result := (Ext <> '') And (Pos(Ext + ',', AssistantStillImageExtensions + ',') > 0);
End;

Function ClipboardMime(Const Mime: String): TClipboardFormat;
Begin
  Result := RegisterClipboardFormat(Mime);
End;

Function MimeLooksLikeStillImage(Const Mime: String): Boolean;
Var
  Lowered: String;
Begin
  Lowered := LowerCase(Trim(Mime));
  Result := (Copy(Lowered, 1, 6) = 'image/') And (Pos('svg', Lowered) = 0);
End;

Function ClipboardFormatMime(FormatId: TClipboardFormat): String;
Begin
  Result := '';
  Try
    Result := ClipboardFormatToMimeType(FormatId);
  Except
    Result := '';
  End;
End;

Function MimeMeansClipboardImage(Const Mime: String): Boolean;
Var
  Lowered: String;
Begin
  Lowered := LowerCase(Mime);
  { Qt offers application/x-qt-image rather than image/png. The bytes are not a
    file; PredefinedClipboardFormat(pcfBitmap) is the LCL conversion. }
  Result := MimeLooksLikeStillImage(Lowered) Or (Pos('qt-image', Lowered) > 0) Or (Pos('bitmap', Lowered) > 0) Or
    (Pos('pixmap', Lowered) > 0);
End;

Function ClipboardHasImage: Boolean;
Var
  I: Integer;
Begin
  Clipboard.Open;
  Try
    Result := Clipboard.HasFormat(PredefinedClipboardFormat(pcfBitmap)) Or
      Clipboard.HasFormat(PredefinedClipboardFormat(pcfPicture)) Or
      Clipboard.HasFormat(PredefinedClipboardFormat(pcfPixmap)) Or
      Clipboard.HasFormat(CF_BITMAP) Or Clipboard.HasFormat(CF_PICTURE);
    If Result Then Exit;
    For I := 0 To Clipboard.FormatCount - 1 Do
      If MimeMeansClipboardImage(ClipboardFormatMime(Clipboard.Formats[I])) Then Exit(True);
    Result := Clipboard.HasFormat(ClipboardMime('image/png')) Or Clipboard.HasFormat(ClipboardMime('image/jpeg')) Or
      Clipboard.HasFormat(ClipboardMime('image/bmp')) Or Clipboard.HasFormat(ClipboardMime('image/gif')) Or
      Clipboard.HasFormat(ClipboardMime('application/x-qt-image'));
  Finally
    Clipboard.Close;
  End;
End;

Function ReadClipboardBytes(FormatId: TClipboardFormat; Stream: TMemoryStream): Boolean;
Begin
  Result := False;
  Stream.Clear;
  If Not Clipboard.HasFormat(FormatId) Then Exit;
  Try
    Result := Clipboard.GetFormat(FormatId, Stream) And (Stream.Size > 0);
  Except
    Result := False;
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

Function LoadClipboardPicture(FormatId: TClipboardFormat; Stream: TMemoryStream): Boolean;
Var
  Pic: TPicture;
Begin
  { Do not require HasFormat. On Qt, CF_BITMAP is false while pcfBitmap still
    returns the native picture. }
  Result := False;
  Stream.Clear;
  Pic := TPicture.Create;
  Try
    Try
      Pic.LoadFromClipboardFormat(FormatId);
    Except
      Exit;
    End;
    Result := GraphicToPngStream(Pic.Graphic, Stream);
  Finally
    Pic.Free;
  End;
End;

Function TryLclClipboardPictures(Stream: TMemoryStream): Boolean;
Var
  I: Integer;
  Formats: Array[0..4] Of TClipboardFormat;
Begin
  Result := False;
  Formats[0] := PredefinedClipboardFormat(pcfBitmap);
  Formats[1] := PredefinedClipboardFormat(pcfPicture);
  Formats[2] := PredefinedClipboardFormat(pcfPixmap);
  Formats[3] := CF_BITMAP;
  Formats[4] := CF_PICTURE;
  For I := 0 To High(Formats) Do
    If LoadClipboardPicture(Formats[I], Stream) Then Exit(True);
End;

Function ForceClipboardBytes(FormatId: TClipboardFormat; Stream: TMemoryStream): Boolean;
Begin
  Result := False;
  Stream.Clear;
  Try
    Result := Clipboard.GetFormat(FormatId, Stream) And (Stream.Size > 8);
  Except
    Result := False;
  End;
  Stream.Position := 0;
End;

{$IF FALSE}
{ Widgetset paste lives in the LCL clipboard. This block is unused. }
Function GtkPixbufToPng(Pixbuf: PGdkPixbuf; Stream: TMemoryStream): Boolean;
Var
  Img: TFPMemoryImage;
  Writer: TFPWriterPNG;
  X, Y, Width, Height, Stride, Channels, Sample: Integer;
  Pixels, Row: PByte;
  Red, Green, Blue, Alpha: Byte;
Begin
  Result := False;
  Stream.Clear;
  If Pixbuf = Nil Then Exit;
  Width := gdk_pixbuf_get_width(Pixbuf);
  Height := gdk_pixbuf_get_height(Pixbuf);
  Stride := gdk_pixbuf_get_rowstride(Pixbuf);
  Channels := gdk_pixbuf_get_n_channels(Pixbuf);
  Sample := gdk_pixbuf_get_bits_per_sample(Pixbuf);
  If (Width < 1) Or (Height < 1) Or (Channels < 3) Or (Sample <> 8) Or (Stride < Width * Channels) Then Exit;
  Pixels := PByte(gdk_pixbuf_get_pixels(Pixbuf));
  If Pixels = Nil Then Exit;
  Img := TFPMemoryImage.Create(Width, Height);
  Writer := TFPWriterPNG.Create;
  Try
    For Y := 0 To Height - 1 Do
      Begin
        Row := Pixels + Y * Stride;
        For X := 0 To Width - 1 Do
          Begin
            Red := Row[X * Channels];
            Green := Row[X * Channels + 1];
            Blue := Row[X * Channels + 2];
            If Channels >= 4 Then Alpha := Row[X * Channels + 3]
            Else Alpha := 255;
            Img.Colors[X, Y] := FPColor(Red shl 8, Green shl 8, Blue shl 8, Alpha shl 8);
          End;
      End;
    Img.SaveToStream(Stream, Writer);
    Result := Stream.Size > 0;
    Stream.Position := 0;
  Finally
    Writer.Free;
    Img.Free;
  End;
End;

Function GtkClipboardImageToPng(Stream: TMemoryStream): Boolean;
Var
  GtkClip: PGtkClipboard;
  Pixbuf: PGdkPixbuf;
Begin
  Result := False;
  { Do not call this while TClipboard is open. GTK waits on the selection and
    a nested LCL clipboard lock returns nothing. }
  GtkClip := gtk_clipboard_get(gdk_atom_intern('CLIPBOARD', False));
  If GtkClip = Nil Then Exit;
  Pixbuf := gtk_clipboard_wait_for_image(GtkClip);
  If Pixbuf = Nil Then Exit;
  Try
    Result := GtkPixbufToPng(Pixbuf, Stream);
  Finally
    g_object_unref(Pixbuf);
  End;
End;

Function DroppedLocalPath(Const Name: String): String; Forward;
Function AtomText(Atom: TGdkAtom): String; Forward;
Function SelectionBytes(Data: PGtkSelectionData; Stream: TMemoryStream): Boolean; Forward;

Function GtkPasteAlive: TProjectAssistantForm;
Begin
  Result := Nil;
  If Not (GtkPasteForm Is TProjectAssistantForm) Then Exit;
  If csDestroying In GtkPasteForm.ComponentState Then Exit;
  Result := GtkPasteForm;
End;

Procedure NotePasteImageFailure(Form: TProjectAssistantForm; Const ErrorText: String);
Begin
  If (ErrorText = '') Or Not Assigned(Form.StatusFooter) Then Exit;
  Form.StatusFooter.SetRightText(ErrorText);
End;

Procedure GtkImageReceived(Clipboard: PGtkClipboard; Pixbuf: PGdkPixbuf; Data: Pointer); cdecl;
Var
  Form: TProjectAssistantForm;
  Stream: TMemoryStream;
  ErrorText: String;
Begin
  If Data <> Pointer(GtkPasteForm) Then Exit;
  Form := GtkPasteAlive;
  If (Form = Nil) Or (Pixbuf = Nil) Or Form.FPasteGotImage Then Exit;
  If Not Form.ComposerAttachAllowed(ErrorText) Then
    Begin
      Form.FPasteGotImage := True;
      NotePasteImageFailure(Form, ErrorText);
      Exit;
    End;
  { GTK owns this pixbuf for the callback. Do not unref it. }
  Stream := TMemoryStream.Create;
  Try
    If Not GtkPixbufToPng(Pixbuf, Stream) Then Exit;
    Form.FPasteGotImage := True;
    ErrorText := '';
    If Not Form.AttachImageStream('Clipboard.png', Stream, ErrorText) Then
      Begin
        Form.FPasteGotImage := False;
        NotePasteImageFailure(Form, ErrorText);
      End;
  Finally
    Stream.Free;
  End;
End;

Function SelectionText(Data: PGtkSelectionData): String;
Var
  Bytes: PChar;
  Len: Integer;
Begin
  Result := '';
  If Data = Nil Then Exit;
  Len := gtk_selection_data_get_length(Data);
  If Len < 1 Then Exit;
  Bytes := PChar(gtk_selection_data_get_data(Data));
  If Bytes = Nil Then Exit;
  SetLength(Result, Len);
  Move(Bytes^, Result[1], Len);
  While (Result <> '') And (Result[Length(Result)] In [#0, #10, #13]) Do
    Delete(Result, Length(Result), 1);
End;

Procedure AttachClipboardPaths(Form: TProjectAssistantForm; Const Body: String);
Var
  Lines: TStringList;
  I: Integer;
  LocalName, ErrorText: String;
Begin
  Lines := TStringList.Create;
  Try
    Lines.Text := StringReplace(Body, #13, #10, [rfReplaceAll]);
    For I := 0 To Lines.Count - 1 Do
      Begin
        LocalName := Trim(Lines[I]);
        If (LocalName = '') Or SameText(LocalName, 'copy') Or SameText(LocalName, 'cut') Then Continue;
        LocalName := DroppedLocalPath(LocalName);
        If Not StillImageExtension(LocalName) Or Not FileExistsUTF8(LocalName) Then Continue;
        If Form.FPasteGotImage Then Exit;
        Form.FPasteGotImage := True;
        ErrorText := '';
        If Not Form.AttachImageFile(LocalName, ErrorText) Then
          Begin
            Form.FPasteGotImage := False;
            NotePasteImageFailure(Form, ErrorText);
          End;
      End;
  Finally
    Lines.Free;
  End;
End;

Procedure GtkContentsReceived(Clipboard: PGtkClipboard; SelectionData: PGtkSelectionData; Data: Pointer); cdecl;
Var
  Form: TProjectAssistantForm;
  Stream: TMemoryStream;
  Mime, ErrorText: String;
Begin
  If Data <> Pointer(GtkPasteForm) Then Exit;
  Form := GtkPasteAlive;
  If (Form = Nil) Or (SelectionData = Nil) Or Form.FPasteGotImage Then Exit;
  If Not Form.ComposerAttachAllowed(ErrorText) Then
    Begin
      Form.FPasteGotImage := True;
      NotePasteImageFailure(Form, ErrorText);
      Exit;
    End;
  If gtk_selection_data_get_target(SelectionData) = Nil Then Exit;
  Mime := LowerCase(AtomText(gtk_selection_data_get_target(SelectionData)^));
  If (Mime = 'text/uri-list') Or (Mime = 'x-special/gnome-copied-files') Or (Mime = 'text/plain') Or
    (Mime = 'text/plain;charset=utf-8') Then
    Begin
      AttachClipboardPaths(Form, SelectionText(SelectionData));
      Exit;
    End;
  If Not MimeLooksLikeStillImage(Mime) Then Exit;
  Stream := TMemoryStream.Create;
  Try
    If Not SelectionBytes(SelectionData, Stream) Then Exit;
    Form.FPasteGotImage := True;
    ErrorText := '';
    If Not Form.AttachImageStream(ClipboardImageName(Mime), Stream, ErrorText) Then
      Begin
        Form.FPasteGotImage := False;
        NotePasteImageFailure(Form, ErrorText);
      End;
  Finally
    Stream.Free;
  End;
End;

Procedure GtkTextReceived(Clipboard: PGtkClipboard; Text: Pgchar; Data: Pointer); cdecl;
Var
  Form: TProjectAssistantForm;
  Body, LocalName, Reason: String;
Begin
  If Data <> Pointer(GtkPasteForm) Then Exit;
  Form := GtkPasteAlive;
  If (Form = Nil) Or (Text = Nil) Or (Text^ = #0) Or Not Assigned(Form.InputMemo) Then Exit;
  Body := Text;
  LocalName := DroppedLocalPath(Trim(Body));
  { A copied image file is the attachment, not a path typed into the prompt. }
  If (Pos(#10, Body) = 0) And StillImageExtension(LocalName) And FileExistsUTF8(LocalName) And
    Form.ComposerAttachAllowed(Reason) Then
    Begin
      AttachClipboardPaths(Form, Body);
      Exit;
    End;
  Form.InputMemo.SelText := Body;
End;

Function AtomText(Atom: TGdkAtom): String;
Var
  Name: Pgchar;
Begin
  Result := '';
  Name := gdk_atom_name(Atom);
  If Name = Nil Then Exit;
  Result := Name;
  g_free(Name);
End;

Function SelectionBytes(Data: PGtkSelectionData; Stream: TMemoryStream): Boolean;
Var
  Bytes: PByte;
  Len: Integer;
Begin
  Result := False;
  Stream.Clear;
  If Data = Nil Then Exit;
  Len := gtk_selection_data_get_length(Data);
  Bytes := PByte(gtk_selection_data_get_data(Data));
  If (Len < 8) Or (Bytes = Nil) Then Exit;
  Stream.WriteBuffer(Bytes^, Len);
  Stream.Position := 0;
  Result := True;
End;

Procedure RequestGtkTarget(Clip: PGtkClipboard; Const Mime: String);
Begin
  gtk_clipboard_request_contents(Clip, gdk_atom_intern(PChar(Mime), False), @GtkContentsReceived, GtkPasteForm);
End;

Procedure RequestGtkClipboardPaste(Form: TProjectAssistantForm);
Var
  Clip: PGtkClipboard;
Begin
  If (Form.FPasteRequestTick <> 0) And (GetTickCount64 - Form.FPasteRequestTick < 250) Then Exit;
  Form.FPasteRequestTick := GetTickCount64;
  Form.FPasteGotImage := False;
  GtkPasteForm := Form;
  { Started from the key or menu event. Wayland grants the clipboard only for
    that gesture, and a synchronous wait inside the handler returns nothing. }
  Clip := gtk_clipboard_get(gdk_atom_intern('CLIPBOARD', False));
  If Clip = Nil Then Exit;
  gtk_clipboard_request_image(Clip, @GtkImageReceived, Form);
  gtk_clipboard_request_text(Clip, @GtkTextReceived, Form);
  RequestGtkTarget(Clip, 'image/png');
  RequestGtkTarget(Clip, 'image/jpeg');
  RequestGtkTarget(Clip, 'image/gif');
  RequestGtkTarget(Clip, 'image/bmp');
  RequestGtkTarget(Clip, 'image/webp');
  RequestGtkTarget(Clip, 'image/tiff');
  RequestGtkTarget(Clip, 'text/uri-list');
  RequestGtkTarget(Clip, 'x-special/gnome-copied-files');
End;
{$ENDIF}

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
  Result := 0;
  If Assigned(BottomBar) And (BottomBar.Height > 0) Then
    Inc(Result, BottomBar.Height)
  Else
    Inc(Result, Scale96ToForm(36));
  If Assigned(StatusFooter) And (StatusFooter.Height > 0) Then
    Inc(Result, StatusFooter.Height)
  Else
    Inc(Result, Scale96ToForm(22));
  If Assigned(AttachmentStrip) And AttachmentStrip.Visible Then
    Inc(Result, AttachmentStripHeight);
End;

Procedure TProjectAssistantForm.PlaceComposerChildren;
Var
  Y, StripHeight, BandWidth: Integer;
Begin
  { Align stays alNone. LCL sorts alBottom siblings by the current bottom edge,
    so growing one of them docks the text under the status bar. }
  If Not Assigned(ComposerStack) Then Exit;
  BandWidth := ComposerStack.ClientWidth;
  If BandWidth < 1 Then BandWidth := ComposerStack.Width;
  Y := ComposerStack.ClientHeight;
  If Assigned(StatusFooter) Then
    Begin
      StatusFooter.Align := alNone;
      StatusFooter.SetBounds(0, Y - StatusFooter.Height, BandWidth, StatusFooter.Height);
      Y := StatusFooter.Top;
    End;
  If Assigned(BottomBar) Then
    Begin
      BottomBar.Align := alNone;
      BottomBar.SetBounds(0, Y - BottomBar.Height, BandWidth, BottomBar.Height);
      Y := BottomBar.Top;
    End;
  StripHeight := 0;
  If Assigned(AttachmentStrip) And AttachmentStrip.Visible Then
    StripHeight := AttachmentStripHeight;
  If Assigned(AttachmentStrip) Then
    Begin
      AttachmentStrip.Align := alNone;
      If StripHeight > 0 Then
        AttachmentStrip.SetBounds(0, Y - StripHeight, BandWidth, StripHeight)
      Else
        AttachmentStrip.SetBounds(0, Y, BandWidth, 0);
      If StripHeight > 0 Then Y := AttachmentStrip.Top;
      PlaceComposerThumbnails;
    End;
  If Assigned(InputPanel) Then
    Begin
      InputPanel.Align := alNone;
      If Y < 1 Then Y := 1;
      InputPanel.SetBounds(0, 0, BandWidth, Y);
    End;
End;

Procedure TProjectAssistantForm.LayoutComposer;
Var
  StackHeight: Integer;
Begin
  If Not Assigned(ComposerStack) Or FComposerLayoutLock Then Exit;
  If csDestroying In ComponentState Then Exit;
  FComposerLayoutLock := True;
  DisableAlign;
  Try
    If FInputHeight < Scale96ToForm(48) Then FInputHeight := Scale96ToForm(75);
    If Assigned(AttachmentStrip) And AttachmentStrip.Visible Then
      AttachmentStrip.Height := AttachmentStripHeight;
    StackHeight := FInputHeight + ComposerChromeHeight;
    ComposerStack.Align := alBottom;
    ComposerStack.SetBounds(0, ClientHeight - StackHeight, ClientWidth, StackHeight);
    PlaceComposerChildren;
  Finally
    EnableAlign;
    FComposerLayoutLock := False;
  End;
End;

Procedure TProjectAssistantForm.ComposerStackResize(Sender: TObject);
Var
  Available, Minimum: Integer;
Begin
  If FComposerLayoutLock Or (csLoading In ComponentState) Or (csDestroying In ComponentState) Then Exit;
  If Not Assigned(ComposerStack) Then Exit;
  Minimum := Scale96ToForm(48);
  If FShowPlanOffer Then Inc(Minimum, Scale96ToForm(28));
  Available := ComposerStack.ClientHeight - ComposerChromeHeight;
  If Available < Minimum Then Available := Minimum;
  FInputHeight := Available;
  FComposerLayoutLock := True;
  Try
    PlaceComposerChildren;
  Finally
    FComposerLayoutLock := False;
  End;
End;

Procedure TProjectAssistantForm.ApplyInputPanelHeight;
Begin
  If Not Assigned(InputPanel) Then Exit;
  FInputHeight := Scale96ToForm(75);
  If FShowPlanOffer Then Inc(FInputHeight, Scale96ToForm(28));
  LayoutComposer;
End;

Procedure TProjectAssistantForm.RefreshAttachAction;
Var
  Reason: String;
Begin
  If Not Assigned(AttachImageAction) Then Exit;
  AttachImageAction.Enabled := ComposerAttachAllowed(Reason);
  If AttachImageAction.Enabled Then
    AttachImageAction.Hint := 'Attach an image to the next message'
  Else If Reason <> '' Then
    AttachImageAction.Hint := Reason
  Else
    AttachImageAction.Hint := 'Attach is disabled.';
End;

Function TProjectAssistantForm.ComposerAttachAllowed(Out Reason: String): Boolean;
Begin
  Reason := '';
  If FUseCodex Then
    Begin
      Reason := AssistantCodexImageAttachReason;
      Result := False;
      Exit;
    End;
  If Assigned(AssistantClient) And (Not AssistantClient.ImagesAttachAllowed(Reason)) Then
    Begin
      If Reason = '' Then Reason := 'This model lists no image input. Attach is disabled.';
      Result := False;
      Exit;
    End;
  Result := True;
End;

Function TProjectAssistantForm.ComposerStoreReady(Out Root, StoreDir, ErrorText: String): Boolean;
Begin
  Result := False;
  Root := '';
  StoreDir := '';
  ErrorText := '';
  EnsureConversationStore;
  Root := ProjectAssistantRoot;
  If Assigned(ProjectAssistantConversation) Then StoreDir := ProjectAssistantConversation.AssistantDirectory;
  If (Root = '') Or (StoreDir = '') Then
    Begin
      ErrorText := 'Open a project before attaching an image.';
      Exit;
    End;
  If Not ForceDirectoriesUTF8(ExcludeTrailingPathDelimiter(StoreDir)) Then
    Begin
      ErrorText := 'The image store could not be created.';
      Exit;
    End;
  Result := True;
End;

Function TProjectAssistantForm.AttachImageStream(Const OriginalName: String; Stream: TStream; Out ErrorText: String): Boolean;
Var
  Root, StoreDir: String;
  Stored: TAssistantStoredImage;
  Refs: TAssistantImageRefArray;
Begin
  Result := False;
  ErrorText := '';
  ParseAssistantImageRefs(FComposerImagesJson, Refs);
  If Length(Refs) >= AssistantImageMaxAttachments Then
    Begin
      ErrorText := 'At most 8 images can be attached.';
      Exit;
    End;
  If Not ComposerStoreReady(Root, StoreDir, ErrorText) Then Exit;
  Stream.Position := 0;
  If Not StoreAssistantImageStreamInStore(Root, StoreDir, OriginalName, Stream, Stored, ErrorText) Then Exit;
  AppendComposerStored(Self, Stored);
  Result := True;
End;

Function TProjectAssistantForm.AttachImageFile(Const SourcePath: String; Out ErrorText: String): Boolean;
Var
  Root, StoreDir: String;
  Stored: TAssistantStoredImage;
  Refs: TAssistantImageRefArray;
Begin
  Result := False;
  ErrorText := '';
  ParseAssistantImageRefs(FComposerImagesJson, Refs);
  If Length(Refs) >= AssistantImageMaxAttachments Then
    Begin
      ErrorText := 'At most 8 images can be attached.';
      Exit;
    End;
  If Not ComposerStoreReady(Root, StoreDir, ErrorText) Then Exit;
  If Not StoreAssistantImageInStore(Root, StoreDir, SourcePath, Stored, ErrorText) Then Exit;
  AppendComposerStored(Self, Stored);
  Result := True;
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
  { 4px padding, a 72px thumbnail, 4px padding. }
  Result := Scale96ToForm(80);
End;

Procedure TProjectAssistantForm.PlaceComposerThumbnails;
Var
  I, Gap, Side, X: Integer;
  Control: TControl;
Begin
  If Not Assigned(AttachmentStrip) Then Exit;
  { ChildSizing would give the only picture the whole strip. Keep a fixed tile. }
  AttachmentStrip.ChildSizing.Layout := cclNone;
  Gap := Scale96ToForm(4);
  Side := Scale96ToForm(72);
  X := Gap;
  For I := 0 To AttachmentStrip.ControlCount - 1 Do
    Begin
      Control := AttachmentStrip.Controls[I];
      Control.Align := alNone;
      Control.Anchors := [akLeft, akTop];
      Control.Constraints.MinWidth := Side;
      Control.Constraints.MaxWidth := Side;
      Control.Constraints.MinHeight := Side;
      Control.Constraints.MaxHeight := Side;
      Control.SetBounds(X, Gap, Side, Side);
      X := X + Side + Gap;
    End;
  ApplyComposerImageSelection;
End;

Procedure TProjectAssistantForm.ApplyComposerImageSelection;
Var
  I: Integer;
  Frame: TPanel;
  Selected: Boolean;
Begin
  If Not Assigned(AttachmentStrip) Then Exit;
  For I := 0 To AttachmentStrip.ControlCount - 1 Do
    Begin
      If Not (AttachmentStrip.Controls[I] Is TPanel) Then Continue;
      Frame := TPanel(AttachmentStrip.Controls[I]);
      Selected := (FComposerSelectedIndex >= 0) And (Frame.Tag = FComposerSelectedIndex);
      Frame.ParentBackground := Not Selected;
      Frame.ParentColor := Not Selected;
      If Selected Then
        Begin
          Frame.ParentBackground := False;
          Frame.ParentColor := False;
          Frame.Color := clHighlight;
        End;
      Frame.Invalidate;
    End;
End;

Procedure TProjectAssistantForm.SelectComposerImage(Index: Integer);
Var
  Refs: TAssistantImageRefArray;
Begin
  ParseAssistantImageRefs(FComposerImagesJson, Refs);
  If Length(Refs) < 1 Then
    FComposerSelectedIndex := -1
  Else If (Index >= 0) And (Index <= High(Refs)) Then
    FComposerSelectedIndex := Index
  Else If (FComposerSelectedIndex < 0) Or (FComposerSelectedIndex > High(Refs)) Then
    FComposerSelectedIndex := 0;
  ApplyComposerImageSelection;
End;

Function TProjectAssistantForm.ComposerImageIndexUnder(Const ScreenPoint: TPoint): Integer;
Var
  Local: TPoint;
  Control: TControl;
  I: Integer;
Begin
  Result := -1;
  If Not Assigned(AttachmentStrip) Then Exit;
  Local := AttachmentStrip.ScreenToClient(ScreenPoint);
  Control := AttachmentStrip.ControlAtPos(Local, True, True);
  If Not Assigned(Control) Or (Control = AttachmentStrip) Then
    For I := AttachmentStrip.ControlCount - 1 DownTo 0 Do
      If PtInRect(AttachmentStrip.Controls[I].BoundsRect, Local) Then
        Begin
          Control := AttachmentStrip.Controls[I];
          Break;
        End;
  If Assigned(Control) And (Control <> AttachmentStrip) Then Result := Control.Tag;
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
Var
  Refs: TAssistantImageRefArray;
  I, Side, Border, Inner: Integer;
  Root, HintText: String;
  Frame: TPanel;
  Thumb: TImage;
  Control: TControl;
Begin
  If Not Assigned(AttachmentStrip) Then Exit;
  { A visibility change realigns the stack. Ignore that until the height below
    includes the strip, or the text row is shrunk by the strip height. }
  FComposerLayoutLock := True;
  AttachmentStrip.DisableAlign;
  Try
    For I := AttachmentStrip.ControlCount - 1 DownTo 0 Do
      Begin
        Control := AttachmentStrip.Controls[I];
        Control.Parent := Nil;
        Control.Free;
      End;
    ParseAssistantImageRefs(FComposerImagesJson, Refs);
    If Length(Refs) < 1 Then
      FComposerSelectedIndex := -1
    Else If (FComposerSelectedIndex < 0) Or (FComposerSelectedIndex > High(Refs)) Then
      FComposerSelectedIndex := 0;
    AttachmentStrip.Visible := Length(Refs) > 0;
    AttachmentStrip.PopupMenu := AttachmentPopup;
    AttachmentStrip.ChildSizing.Layout := cclNone;
    If AttachmentStrip.Visible Then
      AttachmentStrip.Height := AttachmentStripHeight;
    If AttachmentStrip.Visible Then
      Begin
        Root := '';
        Side := Scale96ToForm(72);
        Border := Scale96ToForm(2);
        If Border < 1 Then Border := 1;
        Inner := Side - (Border * 2);
        If Inner < 8 Then Inner := Side;
        If Assigned(ProjectAssistantConversation) Then Root := ProjectAssistantConversation.ProjectRoot;
        For I := 0 To High(Refs) Do
          Begin
            HintText := ComposerImageHint(Refs[I].Name);
            Frame := TPanel.Create(Nil);
            Frame.Parent := AttachmentStrip;
            Frame.BevelOuter := bvNone;
            Frame.Caption := '';
            Frame.Align := alNone;
            Frame.Anchors := [akLeft, akTop];
            Frame.Tag := I;
            Frame.ParentShowHint := False;
            Frame.ShowHint := True;
            Frame.Hint := HintText;
            Frame.PopupMenu := AttachmentPopup;
            Frame.OnMouseDown := @AttachmentImageMouseDown;
            Frame.OnDblClick := @AttachmentImageDblClick;
            Thumb := TImage.Create(Frame);
            Thumb.Parent := Frame;
            Thumb.Align := alNone;
            Thumb.Anchors := [akLeft, akTop];
            Thumb.AutoSize := False;
            Thumb.SetBounds(Border, Border, Inner, Inner);
            Thumb.Constraints.MinWidth := Inner;
            Thumb.Constraints.MaxWidth := Inner;
            Thumb.Constraints.MinHeight := Inner;
            Thumb.Constraints.MaxHeight := Inner;
            Thumb.Tag := I;
            Thumb.ParentShowHint := False;
            Thumb.ShowHint := True;
            Thumb.Hint := HintText;
            Thumb.PopupMenu := AttachmentPopup;
            Thumb.OnMouseDown := @AttachmentImageMouseDown;
            Thumb.OnDblClick := @AttachmentImageDblClick;
            AssignThumbImage(Thumb, Root, Refs[I]);
          End;
        ApplyComposerImageSelection;
      End;
  Finally
    AttachmentStrip.EnableAlign;
    FComposerLayoutLock := False;
  End;
  LayoutComposer;
End;

Procedure TProjectAssistantForm.ClearUnsentComposerImages;
Var
  Refs: TAssistantImageRefArray;
  I: Integer;
  Root, ErrorText: String;
Begin
  ParseAssistantImageRefs(FComposerImagesJson, Refs);
  Root := '';
  If Assigned(ProjectAssistantConversation) Then Root := ProjectAssistantConversation.ProjectRoot;
  If (Root <> '') And (Not FSending) Then
    For I := 0 To High(Refs) Do
      If Not TurnReferencesImage(Refs[I].Id) Then
        If Not DeleteStoredAssistantImage(Root, Refs[I], ErrorText) And (ErrorText <> '') Then
          WorkflowLogger.Warning('ProjectAssistant', 'Unsent image: ' + ErrorText);
  FComposerImagesJson := '';
  RefreshComposerImages;
End;

Procedure TProjectAssistantForm.RemoveComposerImageAt(Index: Integer);
Var
  I, N: Integer;
  Refs, Kept: TAssistantImageRefArray;
  Root, ErrorText: String;
Begin
  ParseAssistantImageRefs(FComposerImagesJson, Refs);
  If (Index < 0) Or (Index > High(Refs)) Then Exit;
  If Index < FComposerSelectedIndex Then
    Dec(FComposerSelectedIndex)
  Else If Index = FComposerSelectedIndex Then
    If FComposerSelectedIndex > High(Refs) - 1 Then FComposerSelectedIndex := High(Refs) - 1;
  Root := '';
  If Assigned(ProjectAssistantConversation) Then Root := ProjectAssistantConversation.ProjectRoot;
  If (Root <> '') And (Not FSending) And (Not TurnReferencesImage(Refs[Index].Id)) Then
    DeleteStoredAssistantImage(Root, Refs[Index], ErrorText);
  SetLength(Kept, Length(Refs) - 1);
  N := 0;
  For I := 0 To High(Refs) Do
    If I <> Index Then
      Begin
        Kept[N] := Refs[I];
        Inc(N);
      End;
  FComposerImagesJson := AssistantImageRefsToJson(Kept);
  RefreshComposerImages;
End;

Procedure TProjectAssistantForm.SaveComposerImage(Index: Integer);
Var
  Ref: TAssistantImageRef;
  Dialog: TSaveDialog;
  Root, ErrorText, FileName, Ext: String;
Begin
  If Not ComposerRefAt(Self, Index, Ref) Then Exit;
  Root := '';
  If Assigned(ProjectAssistantConversation) Then Root := ProjectAssistantConversation.ProjectRoot;
  If (Root = '') Or (Trim(Ref.DisplayPath) = '') Then
    Begin
      MessageDlg('The image is unavailable.', mtInformation, [mbOK], 0);
      Exit;
    End;
  FileName := AttachmentSaveName(Ref.Name, Ref.Id);
  Dialog := TSaveDialog.Create(Nil);
  Try
    Dialog.Title := 'Save As';
    Dialog.Filter := 'PNG image|*.png|JPEG image|*.jpg;*.jpeg|GIF image|*.gif|Bitmap image|*.bmp|' +
      'TIFF image|*.tif;*.tiff|XPM image|*.xpm|PNM image|*.pbm;*.pgm;*.ppm|Icon|*.ico|All files|*.*';
    Dialog.FilterIndex := ComposerSaveFilterIndex(FileName);
    Dialog.FileName := FileName;
    Ext := ExtractFileExt(FileName);
    If Ext <> '' Then Dialog.DefaultExt := Copy(Ext, 2, MaxInt);
    Dialog.Options := [ofOverwritePrompt, ofPathMustExist, ofEnableSizing, ofHideReadOnly];
    If DirectoryExists(Root) Then Dialog.InitialDir := Root;
    If Not Dialog.Execute Then Exit;
    If Not WriteStoredImageFile(Root, Ref.DisplayPath, Dialog.FileName, ErrorText) Then
      Begin
        If ErrorText = '' Then ErrorText := 'The image could not be saved.';
        MessageDlg(ErrorText, mtInformation, [mbOK], 0);
      End;
  Finally
    Dialog.Free;
  End;
End;

Procedure TProjectAssistantForm.PreviewComposerImage(Index: Integer);
Var
  Ref: TAssistantImageRef;
  TraceRef: TTraceImageRef;
  Root: String;
Begin
  If Not ComposerRefAt(Self, Index, Ref) Then Exit;
  Root := '';
  If Assigned(ProjectAssistantConversation) Then Root := ProjectAssistantConversation.ProjectRoot;
  TraceRef := Default(TTraceImageRef);
  TraceRef.Id := Ref.Id;
  TraceRef.Name := Ref.Name;
  TraceRef.DisplayPath := Ref.DisplayPath;
  TraceRef.Width := Ref.Width;
  TraceRef.Height := Ref.Height;
  TraceRef.Missing := False;
  ShowAssistantImage(Root, TraceRef);
End;

Procedure TProjectAssistantForm.AttachmentPopupPopup(Sender: TObject);
Var
  Index: Integer;
  Refs: TAssistantImageRefArray;
  HasImage: Boolean;
Begin
  Index := ComposerImageIndexUnder(Mouse.CursorPos);
  ParseAssistantImageRefs(FComposerImagesJson, Refs);
  HasImage := (Index >= 0) And (Index <= High(Refs));
  If HasImage Then SelectComposerImage(Index);
  If Assigned(RemoveAttachmentAction) Then
    Begin
      RemoveAttachmentAction.Tag := Index;
      RemoveAttachmentAction.Enabled := HasImage;
    End;
  If Assigned(SaveAttachmentAction) Then
    Begin
      SaveAttachmentAction.Tag := Index;
      SaveAttachmentAction.Enabled := HasImage;
    End;
  If Assigned(PreviewAttachmentAction) Then
    Begin
      PreviewAttachmentAction.Tag := Index;
      PreviewAttachmentAction.Enabled := HasImage;
    End;
End;

Procedure TProjectAssistantForm.RemoveAttachmentActionExecute(Sender: TObject);
Begin
  If Sender Is TComponent Then RemoveComposerImageAt(TComponent(Sender).Tag);
End;

Procedure TProjectAssistantForm.SaveAttachmentActionExecute(Sender: TObject);
Begin
  If Sender Is TComponent Then SaveComposerImage(TComponent(Sender).Tag);
End;

Procedure TProjectAssistantForm.PreviewAttachmentActionExecute(Sender: TObject);
Begin
  If Sender Is TComponent Then PreviewComposerImage(TComponent(Sender).Tag);
End;

Procedure TProjectAssistantForm.AttachmentImageMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
Begin
  If Sender Is TControl Then SelectComposerImage(TControl(Sender).Tag);
End;

Procedure TProjectAssistantForm.AttachmentImageDblClick(Sender: TObject);
Begin
  If Sender Is TControl Then
    Begin
      SelectComposerImage(TControl(Sender).Tag);
      PreviewComposerImage(TControl(Sender).Tag);
    End;
End;

Procedure TProjectAssistantForm.AttachImageActionExecute(Sender: TObject);
Var
  Dialog: TOpenDialog;
  Reason, ErrorText: String;
  I: Integer;
Begin
  If Not ComposerAttachAllowed(Reason) Then
    Begin
      If Reason = '' Then Reason := 'Attach is disabled.';
      MessageDlg(Reason, mtInformation, [mbOK], 0);
      Exit;
    End;
  EnsureConversationStore;
  If ProjectAssistantRoot = '' Then
    Begin
      MessageDlg('Open a project before attaching an image.', mtInformation, [mbOK], 0);
      Exit;
    End;
  Dialog := TOpenDialog.Create(Nil);
  Try
    Dialog.Title := 'Attach image';
    Dialog.InitialDir := ProjectAssistantRoot;
    Dialog.Options := [ofAllowMultiSelect, ofFileMustExist, ofEnableSizing];
    Dialog.Filter := 'Images|*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.ico;*.xpm;*.tif;*.tiff;*.pbm;*.pgm;*.ppm';
    If Not Dialog.Execute Then Exit;
    For I := 0 To Dialog.Files.Count - 1 Do
      If Not AttachImageFile(Dialog.Files[I], ErrorText) Then
        Begin
          If ErrorText = '' Then ErrorText := 'That file is not an image.';
          MessageDlg(ErrorText, mtInformation, [mbOK], 0);
        End;
  Finally
    Dialog.Free;
  End;
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
Var
  I: Integer;
  Reason, ErrorText, LocalName: String;
  SawImage: Boolean;
Begin
  SawImage := False;
  For I := 0 To High(FileNames) Do
    If StillImageExtension(DroppedLocalPath(FileNames[I])) Then SawImage := True;
  If Not SawImage Then Exit;
  If Not ComposerAttachAllowed(Reason) Then
    Begin
      If Reason = '' Then Reason := 'Attach is disabled.';
      MessageDlg(Reason, mtInformation, [mbOK], 0);
      Exit;
    End;
  For I := 0 To High(FileNames) Do
    Begin
      LocalName := DroppedLocalPath(FileNames[I]);
      If Not StillImageExtension(LocalName) Then Continue;
      If AttachImageFile(LocalName, ErrorText) Then Continue;
      If ErrorText = '' Then ErrorText := 'That file is not an image.';
      MessageDlg(ErrorText, mtInformation, [mbOK], 0);
    End;
End;

Function TProjectAssistantForm.TryAttachClipboardImage(Out ErrorText: String): Boolean;
Var
  Stream: TMemoryStream;
  Reason, Mime: String;
  Tried: Array Of String;
  I, J: Integer;
  Known: Boolean;
  SawImage: Boolean;

  Function AlreadyTried(Const Name: String): Boolean;
  Var
    K: Integer;
  Begin
    Result := False;
    For K := 0 To High(Tried) Do
      If SameText(Tried[K], Name) Then Exit(True);
  End;

  Procedure NoteTried(Const Name: String);
  Begin
    If AlreadyTried(Name) Then Exit;
    SetLength(Tried, Length(Tried) + 1);
    Tried[High(Tried)] := Name;
  End;

  Function TryBytes(Const Name: String): Boolean;
  Begin
    Result := False;
    Stream.Position := 0;
    If Stream.Size < 8 Then Exit;
    ErrorText := '';
    Result := AttachImageStream(Name, Stream, ErrorText);
  End;

Begin
  Result := False;
  ErrorText := '';
  SawImage := ClipboardHasImage;
  If Not ComposerAttachAllowed(Reason) Then
    Begin
      If SawImage Then
        Begin
          ErrorText := Reason;
          If ErrorText = '' Then ErrorText := 'Attach is disabled.';
        End;
      Exit;
    End;
  Tried := Nil;
  SetLength(Tried, 0);
  Stream := TMemoryStream.Create;
  Try
    { Widgetset picture formats first. Qt screenshots are application/x-qt-image;
      LCL turns that into a picture. Do this before asking for text. }
    If TryLclClipboardPictures(Stream) And TryBytes('Clipboard.png') Then Exit(True);
    If ForceClipboardBytes(ClipboardMime('image/png'), Stream) And TryBytes('Clipboard.png') Then Exit(True);
    If ForceClipboardBytes(ClipboardMime('image/jpeg'), Stream) And TryBytes('Clipboard.jpg') Then Exit(True);
    If ForceClipboardBytes(ClipboardMime('image/bmp'), Stream) And TryBytes('Clipboard.bmp') Then Exit(True);
    If ForceClipboardBytes(ClipboardMime('image/gif'), Stream) And TryBytes('Clipboard.gif') Then Exit(True);
    If Not SawImage Then Exit;
    Clipboard.Open;
    Try
      For I := 0 To Clipboard.FormatCount - 1 Do
        Begin
          Mime := ClipboardFormatMime(Clipboard.Formats[I]);
          If Not MimeLooksLikeStillImage(Mime) Then Continue;
          NoteTried(Mime);
          If ReadClipboardBytes(Clipboard.Formats[I], Stream) And TryBytes(ClipboardImageName(Mime)) Then Exit(True);
          If ReadClipboardBytes(ClipboardMime(Mime), Stream) And TryBytes(ClipboardImageName(Mime)) Then Exit(True);
        End;
      NoteTried('image/png');
      NoteTried('image/x-png');
      NoteTried('image/jpeg');
      NoteTried('image/jpg');
      NoteTried('image/gif');
      NoteTried('image/bmp');
      NoteTried('image/x-bmp');
      NoteTried('image/x-MS-bmp');
      NoteTried('image/x-win-bmp');
      NoteTried('image/tiff');
      NoteTried('image/tif');
      NoteTried('image/webp');
      NoteTried('image/x-icon');
      NoteTried('image/x-xpixmap');
      For J := 0 To High(Tried) Do
        Begin
          Known := MimeLooksLikeStillImage(Tried[J]);
          If Not Known Then Continue;
          If ReadClipboardBytes(ClipboardMime(Tried[J]), Stream) And TryBytes(ClipboardImageName(Tried[J])) Then Exit(True);
        End;
      If LoadClipboardPicture(CF_BITMAP, Stream) And TryBytes('Clipboard.png') Then Exit(True);
      If LoadClipboardPicture(CF_PICTURE, Stream) And TryBytes('Clipboard.png') Then Exit(True);
      If ForceClipboardBytes(ClipboardMime('image/png'), Stream) And TryBytes('Clipboard.png') Then Exit(True);
      If ForceClipboardBytes(ClipboardMime('image/jpeg'), Stream) And TryBytes('Clipboard.jpg') Then Exit(True);
      If ForceClipboardBytes(ClipboardMime('image/bmp'), Stream) And TryBytes('Clipboard.bmp') Then Exit(True);
      If ForceClipboardBytes(ClipboardMime('image/gif'), Stream) And TryBytes('Clipboard.gif') Then Exit(True);
    Finally
      Clipboard.Close;
    End;
    If ErrorText = '' Then ErrorText := 'The clipboard image could not be read.';
  Finally
    Stream.Free;
  End;
End;

Function ClipboardTextIsImageFile(Const Text: String; Out LocalPath: String): Boolean;
Begin
  LocalPath := DroppedLocalPath(Trim(Text));
  Result := (Pos(#10, Text) = 0) And (Pos(#13, Text) = 0) And StillImageExtension(LocalPath) And
    FileExistsUTF8(LocalPath);
End;

Procedure TProjectAssistantForm.PasteComposer;
Var
  Attached: Boolean;
  PastedText, ImageError, LocalPath: String;
Begin
  If Not Assigned(InputMemo) Or InputMemo.ReadOnly Then Exit;
  { Ctrl+V can arrive both as the memo key and as the popup shortcut. }
  If FPasteComposerBusy Then Exit;
  FPasteComposerBusy := True;
  Try
    Attached := False;
    ImageError := '';
    Try
      { Picture before text. Some widgetsets only return the mime that was asked for first. }
      Attached := TryAttachClipboardImage(ImageError);
    Except
      Attached := False;
      If ImageError = '' Then ImageError := 'The clipboard image could not be read.';
    End;
    PastedText := '';
    If Clipboard.HasFormat(CF_TEXT) Then PastedText := Clipboard.AsText;
    If (Not Attached) And ClipboardTextIsImageFile(PastedText, LocalPath) Then
      Attached := AttachImageFile(LocalPath, ImageError);
    { A copied image file is the attachment, not a path typed into the prompt. }
    If Attached And ClipboardTextIsImageFile(PastedText, LocalPath) Then PastedText := '';
    { SelText, not PasteFromClipboard: OnPaste calls back into this method. }
    If PastedText <> '' Then
      InputMemo.SelText := PastedText;
    If (Not Attached) And (ImageError <> '') Then
      MessageDlg(ImageError, mtInformation, [mbOK], 0);
  Finally
    FPasteComposerBusy := False;
  End;
End;

Procedure TProjectAssistantForm.QueueComposerPaste;
Begin
  PasteComposer;
End;

Procedure TProjectAssistantForm.InputPasteClick(Sender: TObject);
Begin
  QueueComposerPaste;
End;

Procedure TProjectAssistantForm.InputMemoPaste(Sender: TObject);
Begin
  QueueComposerPaste;
End;

Procedure TProjectAssistantForm.InputSelectAllClick(Sender: TObject);
Begin
  If Assigned(InputMemo) Then
    InputMemo.SelectAll;
End;

Procedure TProjectAssistantForm.ScrollChatToEnd;
Begin
  If Assigned(FTraceView) Then
    FTraceView.ScrollToEnd;
End;

Procedure TProjectAssistantForm.ScrollChatToTop;
Begin
  If Assigned(FTraceView) Then
    FTraceView.ScrollToStart;
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
End;

Procedure TProjectAssistantForm.ApplyLiveAnswerSlice;
Var
  Last, Block: TTraceBlock;
  Slice: String;
Begin
  If Not Assigned(FTrace) Then
    Exit;
  Slice := SliceLiveChannel(FLiveContent, FAnswerSliceStart);
  If (Slice = '') Or (Not SliceLooksLikeAnswer(Slice)) Then
    Exit;
  Last := Nil;
  If FTrace.Count > 0 Then
    Last := FTrace[FTrace.Count - 1];
  If Assigned(Last) And (Last.Kind = tbkNote) Then
    Exit;
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
  If (Event.Kind = aekToolCompleted) And Event.Ok Then
    If SameText(Event.ToolName, 'write_markdown') Or SameText(Event.ToolName, 'update_markdown') Then
      FPlanWriteThisTurn := True;
  If (Event.Kind = aekTurnEnded) And (Pos('plan_write', Event.Text) > 0) Then
    FPlanWriteThisTurn := True;
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
          FTrace.AppendUserImages(Event.AttachmentsJson);
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
      WorkflowLogger.Warning('ProjectAssistant', 'HandleTraceEvent: ' + E.Message);
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
        WorkflowLogger.Warning('ProjectAssistant', 'RefreshChatDisplay: ' + E.Message);
    End;
  Finally
    FRefreshingChat := False;
  End;
End;

Function TProjectAssistantForm.RoleHeading(Const Role: String): String;
Var
  R: String;
Begin
  R := LowerCase(Trim(Role));
  If R = 'user' Then
    Result := 'User'
  Else If R = 'assistant' Then
    Result := 'Assistant'
  Else If R = 'system' Then
    Result := 'System'
  Else If R = 'tool' Then
    Result := 'Tool'
  Else
    Result := Role;
End;

Function TProjectAssistantForm.QuoteMarkdownLines(Const TextValue: String): String;
Var
  SL: TStringList;
  I: Integer;
  Line: String;
Begin
  { Blockquote each line so thinking reads as a secondary section. }
  SL := TStringList.Create;
  Try
    SL.Text := StringReplace(TextValue, #13#10, #10, [rfReplaceAll]);
    SL.Text := StringReplace(SL.Text, #13, #10, [rfReplaceAll]);
    Result := '';
    For I := 0 To SL.Count - 1 Do
      Begin
        Line := SL[I];
        If Result <> '' Then
          Result := Result + LineEnding;
        If Line = '' Then
          Result := Result + '>'
        Else
          Result := Result + '> ' + Line;
      End;
    If Result = '' Then
      Result := '>';
  Finally
    SL.Free;
  End;
End;

Function TProjectAssistantForm.FormatAssistantMarkdown(Const Thinking, Content: String): String;
Begin
  { Thinking is display-only; Content is the final answer (API history). }
  If (Thinking = '') And (Content = '') Then
    Begin
      Result := '*Waiting for model…*';
      Exit;
    End;
  If FShowThinking And (Thinking <> '') Then
    Begin
      Result := '> **Thinking**' + LineEnding + '>' + LineEnding + QuoteMarkdownLines(Thinking);
      If Content <> '' Then
        Result := Result + LineEnding + LineEnding + Content
      Else
        Result := Result + LineEnding + LineEnding + '*Waiting for answer…*';
    End
  Else If Content <> '' Then
    Result := Content
  Else If FStreamingActive Then
    Result := '*Waiting for answer…*'
  Else
    Result := '';
End;

Procedure TProjectAssistantForm.AppendMessage(Const Role, Content: String);
Var
  R: String;
Begin
  { Keep a thin legacy transcript for session export; UI uses current-turn fields. }
  If Transcript.Count > 0 Then
    Transcript.Add('');
  Transcript.Add('### ' + RoleHeading(Role));
  Transcript.Add('');
  If Content <> '' Then
    Transcript.Add(Content)
  Else
    Transcript.Add('');
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
End;

Procedure TProjectAssistantForm.ApplyAssistantSnapshots(Const ContentSnapshot, ThinkingSnapshot: String);
Begin
  { Ignore late Queue packets after the turn has finished (prevents a second Begin/Finish cycle). }
  If Not FSending Then
    Exit;
  Try
    If Not FStreamingActive Then
      BeginAssistantReply;
    { Always keep live buffers for the background stream. }
    FLiveContent := ContentSnapshot;
    FLiveThinking := ThinkingSnapshot;
    { Keep the reconnect clock until the actor reports new stream progress. }
    If FStatusPhase <> 'Re-establishing Connection' Then
      Begin
        If FLiveContent <> '' Then
          SetStreamPhase('Streaming…')
        Else If FLiveThinking <> '' Then
          SetStreamPhase('Thinking…')
        Else If FStatusPhase = '' Then
          SetStreamPhase('Waiting for first token…');
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
      WorkflowLogger.Warning('ProjectAssistant', 'ApplyAssistantSnapshots: ' + E.Message);
  End;
End;

Procedure TProjectAssistantForm.FinishAssistantReply(Const ErrorText: String);
Var
  DisplayBody, ResolvedError, TraceNote, Settlement, AskedNote: String;
  WorkedMs: Integer;
Begin
  ResolvedError := ErrorText;
  If IsAssistantProgressStatus(ResolvedError) Then
    ResolvedError := '';
  If (Not FUseCodex) And Assigned(AssistantClient) Then
    AssistantClient.ToolsEnabled := ActiveMode <> amChat;
  { Second IsFinished (or Stop after finish) must not append another conversation row. }
  If Not FSending Then
    Begin
      If (Not FUseCodex) And Assigned(AssistantClient) Then
        AssistantClient.MarkStreamComplete;
      Exit;
    End;
  If FUserCancelled Then
    Begin
      FUserCancelled := False;
      FStreamingActive := False;
      If (Not FUseCodex) And Assigned(AssistantClient) Then
        AssistantClient.MarkStreamComplete;
      If FBuildWorkSectionIndex >= 0 Then
        SetBuildStatusFeedback(Format('"%s" cancelled — still in progress.',
          [FBuildWorkSectionTitle]));
      FPendingReviewErrorOffer := False;
      UnlockModeAfterSend;
      SetSending(False);
      Exit;
    End;
  { FLive* are authoritative for the completed stream (pane may be browsing elsewhere). }
  If FStreamingActive Then
    Begin
      If (ResolvedError <> '') And (FLiveContent = '') And (FLiveThinking = '') Then
        DisplayBody := '*(error)*'
      Else
        DisplayBody := FormatAssistantMarkdown(FLiveThinking, FLiveContent);
      If Transcript.Count > 0 Then
        Transcript.Add('');
      Transcript.Add('### Assistant');
      Transcript.Add('');
      Transcript.Add(DisplayBody);
    End;

  If ResolvedError <> '' Then
    Begin
      If FViewingLive Then
        FDisplaySystemNote := '**Error:** ' + ResolvedError;
      StatusFooter.SetRightText('Error');
    End
  Else
    Begin
      { Full conversation for the API lives on AssistantClient (all prior turns). }
      If Assigned(AssistantClient) And (FLiveContent <> '') Then
        AssistantClient.AddMessage(amrAssistant, FLiveContent);
      FContextUsed := FContextUsed + Length(FLiveContent) Div 4 + 20;
      If FLiveThinking <> '' Then
        FContextUsed := FContextUsed + Length(FLiveThinking) Div 4;
      StatusFooter.SetRightText('Ready');
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
  If Not FUseCodex Then PersistPlanReplyIfNeeded(ResolvedError);
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
  { Record from live buffers so a browsed-away pane still saves the real answer. }
  RecordCurrentTurn(ResolvedError);
  If AssistantRequestRejectedImage(ResolvedError) Then
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
  If (Not FUseCodex) And Assigned(AssistantClient) Then
    AssistantClient.MarkStreamComplete;
  { Validation evidence can auto-complete when the root is not a Git repository.
    In a repository the model sets Status, and that plan file is committed before the item counts as complete.
    An item that is already complete does not stop the plan agent. }
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
  { End send before list refresh so the in-flight row is not kept alongside the stored turn. }
  SetSending(False);
  If FPlanWriteThisTurn And (ResolvedError = '') Then
    Begin
      RefreshPlanList;
      RefreshBuildTodos;
      ShowPlanOfferBar(ActiveMode = amPlan);
    End
  Else
    Begin
      If ActiveMode = amBuild Then
        RefreshBuildTodos;
      ShowPlanOfferBar(False);
    End;
  If (Not FUseCodex) And FPlanAgentRunning Then
    Begin
      If FLastTurnHadError Then
        Begin
          If (Pos('host name resolution', LowerCase(ResolvedError)) > 0) Or
            (Pos('network', LowerCase(ResolvedError)) > 0) Or
            (Pos('timed out', LowerCase(ResolvedError)) > 0) Then
            StopWorkOnPlanAgent(
              'network error talking to api.x.ai. Check connectivity, then click ' +
              '**Work on plan** again to resume remaining packages. ' + ResolvedError)
          Else
            StopWorkOnPlanAgent('error: ' + ResolvedError);
        End
      Else
        Begin
          Inc(FPlanAgentPackagesDone);
          Application.QueueAsyncCall(@ContinueWorkOnPlanAgent, 0);
        End;
    End;
  FViewingLive := True;
  If Assigned(ProjectAssistantConversation) Then
    FSelectedTurnIndex := ProjectAssistantConversation.TurnCount - 1;
  RefreshConversationList;
  RefreshChatDisplay(True, True);
  PersistSession;
End;

Procedure TProjectAssistantForm.StreamToken(Const ContentSnapshot, ThinkingSnapshot: String;
  IsFinished: Boolean; Const ErrorText: String);
Var
  FinishErr: String;
Begin
  If csDestroying In ComponentState Then Exit;
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
        SetStreamPhase(ErrorText);
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
  FUserCancelled := True;
  ReleaseCodexRun;
  { CancelStream pumps CheckSynchronize so Queue/Synchronize cannot deadlock. }
  If (Not FUseCodex) And Assigned(AssistantClient) Then
    Begin
      AssistantClient.CancelStream;
      AssistantClient.ToolsEnabled := ActiveMode <> amChat;
    End;
  If FStreamingActive Or (FLiveUser <> '') Then
    Begin
      If (FLiveContent <> '') Or (FLiveThinking <> '') Then
        Begin
          If Assigned(AssistantClient) And (FLiveContent <> '') Then
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
  StatusFooter.SetRightText('Cancelled');
  PersistSession;
  If (Not FUseCodex) And FPlanAgentRunning Then
    StopWorkOnPlanAgent('stream cancelled by user');
  WorkflowLogger.Info('ProjectAssistant', 'Stream cancelled by user');
End;

Function TProjectAssistantForm.SubmitUserText(Const UserText: String; AutoSend: Boolean): Boolean;
Begin
  Result := SubmitUserTextEx(UserText, UserText, AutoSend);
End;

Function TProjectAssistantForm.SubmitUserTextEx(Const DisplayText, ApiText: String; AutoSend: Boolean): Boolean;
Var
  FinalApi, ContextBlock, PlanRel, ModelText, BlockReason: String;
  WithContext: Boolean;
  Refs: TAssistantImageRefArray;
Begin
  Result := False;
  SetLength(Refs, 0);
  ParseAssistantImageRefs(FComposerImagesJson, Refs);
  Refs := LimitAssistantImageRefs(Refs);
  If (Trim(ApiText) = '') And (Length(Refs) = 0) Then
    Exit;
  If FSending Then
    Exit;
  HideSlashPopup;
  If AutoSend And FUseCodex Then
    Begin
      Result := StartCodexReply(DisplayText, ApiText);
      Exit;
    End;
  If AutoSend Then
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
      If (Length(Refs) > 0) And (Not AssistantClient.ImagesAttachAllowed(BlockReason)) Then
        Begin
          If BlockReason = '' Then
            BlockReason := 'This model lists no image input. Attach is disabled.';
          SetCurrentSystemNote(BlockReason);
          MessageDlg(BlockReason, mtInformation, [mbOK], 0);
          If Assigned(InputMemo) Then
            InputMemo.Text := DisplayText;
          Exit;
        End;
      MaybeWarnHighContextUsage;
      { Callers like Fix Error / Work-on-this may already ForceModeAndLock. }
      If Not FModeLocked Then
        LockModeForSend; { freeze Plan/Build before chat surface / SetSending }
      ShowChatSurfaceKeepMode; { shared turn view already visible; sync mode chrome }
      { Visible words stay DisplayText. The look sentence is model text only. }
      ModelText := AssistantImageModelText(ApiText, Length(Refs));
      FinalApi := ModelText;
      If ActiveMode = amPlan Then
        Begin
          PlanRel := GetActivePlanRelativePath;
          If PlanRel = '' Then
            PlanRel := DefaultPlanRelativePath;
          FinalApi :=
            '[SYSTEM DIRECTIVE — Plan mode] Write the plan into the project Markdown file ' +
            'using the write_markdown tool (path: "' + PlanRel +
            '"). Chat reply must be a short summary only, not the full plan body. ' +
            'Use the assistant plan format: an H1 title, then `' + AssistantPlanGeneratedLine +
            '`, numbered ## sections without Status, and ### items with Status.' +
            LineEnding + LineEnding + ModelText;
        End;
      WithContext := (ActiveMode <> amChat) And Assigned(AssistantChatConfig) And
        AssistantChatConfig.IncludeIDEContext;
      SetCurrentUserDisplay(DisplayText, WithContext);
      FLiveUser := FDisplayUser;
      FLiveContent := '';
      FLiveThinking := '';
      FAssistantContent := '';
      FAssistantThinking := '';
      If WithContext Then
        Begin
          { After several turns, full editor dumps explode the prompt; use light context. }
          If Assigned(AssistantClient) And (AssistantClient.MessageCount >= 8) Then
            ContextBlock := BuildIDEContextBlockLight
          Else
            ContextBlock := BuildIDEContextBlock;
          FinalApi := FinalApi + LineEnding + LineEnding + ContextBlock;
        End;
      AppendMessage('user', FDisplayUser);
      { Prior turns already on AssistantClient are sent with this request (trimmed if huge).
        IDE context is already a text suffix on FinalApi. It is not an image part. }
      AssistantClient.AddUserMessage(FinalApi, Refs);
      FContextUsed := AssistantClient.EstimatedPromptTokens;
      If FContextUsed < Length(FinalApi) Div 4 Then
        FContextUsed := Length(FinalApi) Div 4 + 8;
      FStatusPhase := 'Waiting for first token…';
      AssistantClient.ToolsEnabled := ActiveMode <> amChat;
      SetSending(True);
      BeginAssistantReply;
      { Large skill + IDE context means a noticeable wait before the first token.
        That gap is model/server time-to-first-token, not local UI hang. }
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
      If FCodexRun.Steer(UserText) Then SetStreamPhase('Steer queued…')
      Else InputMemo.Text := UserText;
      Exit;
    End;
  If Assigned(AssistantClient) Then
    AssistantClient.EnqueueSteer(UserText);
  SetStreamPhase('Steering at next tool gap…');
  WorkflowLogger.Info('ProjectAssistant', 'Steer queued (' + IntToStr(Length(Trim(UserText))) + ' chars)');
End;

Procedure TProjectAssistantForm.SeedPromptFromSelectedWork;
Var
  Idx: Integer;
  Section: TPlanSection;
Begin
  If Not Assigned(InputMemo) Or Not Assigned(BuildSections) Then
    Exit;
  Idx := SelectedBuildSectionIndex;
  If (Idx < 0) Or (Idx >= BuildSections.Count) Then
    Exit;
  Section := TPlanSection(BuildSections[Idx]);
  If Not Assigned(Section) Then
    Exit;
  InputMemo.Text := 'Work on this package: ' + Section.Title;
  InputMemo.SetFocus;
End;

Procedure TProjectAssistantForm.RebuildCommandCatalog;
Var
  Skills: TAssistantSkillList;
  I: Integer;
  Root, SlashName: String;

  Procedure AddAct(Act: TAction; Const Category, Slash, Aliases, Hint: String);
  Begin
    If Not Assigned(Act) Then
      Exit;
    FCatalog.Add(Act.Caption, Category, Slash, Aliases, Hint, Act, '');
    If Trim(Act.Hint) = '' Then
      Act.Hint := Hint;
    If Trim(Act.Category) = '' Then
      Act.Category := Category;
  End;

Begin
  If Not Assigned(FCatalog) Then
    Exit;
  FCatalog.Clear;
  AddAct(NewChatAction, 'Session', 'new', 'clear', 'Start a new conversation');
  AddAct(CompactContextAction, 'Session', 'compact', '', 'Shrink older turns to free context');
  AddAct(CopyLastAnswerAction, 'Session', 'copy', '', 'Copy the current answer');
  AddAct(ExportHistoryAction, 'Session', 'export', '', 'Export this conversation');
  AddAct(DeleteHistoryAction, 'Session', 'delete', '', 'Delete the current conversation');
  AddAct(SettingsAction, 'Session', 'settings', 'login,logout', 'Sign in, model, and skill');
  AddAct(StopAction, 'Session', 'stop', '', 'Stop the current reply');
  AddAct(OpenPlanAction, 'Work', 'view-plan', 'plan-file', 'Open the active plan Markdown');
  AddAct(BuildThisAction, 'Work', 'build-this', '', 'Switch to Build and seed the next package');
  AddAct(RevisePlanAction, 'Work', 'revise', '', 'Stay in Plan and revise the file');
  AddAct(ChatModeAction, 'Work', 'chat', '', 'Chat mode — general chat, no project tools or skill');
  AddAct(InspectModeAction, 'Work', 'inspect', '', 'Inspect mode — read-only, no writes');
  AddAct(PlanModeAction, 'Work', 'plan', '', 'Plan mode — write the plan file');
  AddAct(BuildModeAction, 'Work', 'build', 'code', 'Build mode — edit sources and compile');
  AddAct(ReviewChangesAction, 'Review', 'review', '', 'Pascal naming, structure, and review lenses');
  AddAct(ReviewCompileAction, 'Review', 'review-compile', '', 'Review the last compile');
  AddAct(ReviewBuildAction, 'Review', 'review-build', '', 'Review the last build');
  AddAct(FixErrorAction, 'Review', 'fix', 'fix-error', 'Fix the selected Messages error');
  AddAct(ToggleThinkingAction, 'View', 'thinking', '', 'Show or hide thinking blocks');
  AddAct(ToggleToolUseAction, 'View', 'tools', '', 'Show or hide tool use');
  AddAct(ModelPickerAction, 'Model', 'model', '', 'Choose model, thinking, and approval');
  AddAct(ThinkingPickerAction, 'Model', 'effort', 'thinking-level', 'Set reasoning effort');
  AddAct(ContextBreakdownAction, 'Help', 'context', '', 'Token estimate for the next request');
  AddAct(SessionInfoAction, 'Help', 'session-info', 'session,docs,help', 'Mode, model, plan, and conversation');
  AddAct(SkillsPickerAction, 'Skills', 'skills', '', 'Pin a skill for the session');
  Root := '';
  If Assigned(ProjectAssistantConversation) Then
    Root := ProjectAssistantConversation.ProjectRoot;
  Skills := ListDiscoveredSkills(Root);
  For I := 0 To High(Skills) Do
    Begin
      If Not Skills[I].UserInvocable Then
        Continue;
      SlashName := Skills[I].Name;
      If FCatalog.HasSlash(SlashName) Then
        SlashName := 'skill-' + Skills[I].Name;
      FCatalog.Add('Run skill: ' + Skills[I].Name, 'Skills', SlashName, '',
        Skills[I].Description, Nil, 'skill:' + Skills[I].Name);
    End;
End;

Function CloneMenuItem(Source: TMenuItem; OwnerMenu: TPopupMenu): TMenuItem;
Var
  I: Integer;
  Child: TMenuItem;
  ActCaption: String;
Begin
  Result := Nil;
  If Not Assigned(Source) Then
    Exit;
  ActCaption := Source.Caption;
  If Assigned(Source.Action) And (Source.Action Is TAction) Then
    ActCaption := TAction(Source.Action).Caption;
  If SameText(Trim(ActCaption), 'Commands…') Then
    Exit;
  Result := TMenuItem.Create(OwnerMenu);
  If Assigned(Source.Action) Then
    Result.Action := Source.Action
  Else
    Result.Caption := Source.Caption;
  For I := 0 To Source.Count - 1 Do
    Begin
      Child := CloneMenuItem(Source.Items[I], OwnerMenu);
      If Assigned(Child) Then
        Result.Add(Child);
    End;
End;

Procedure TProjectAssistantForm.EnsureCommandsMenu;
Var
  I, J, AddedInGroup: Integer;
  Cloned, Sep: TMenuItem;
  Group: TMenuItem;
Begin
  If Assigned(FCommandsPopup) Then
    FCommandsPopup.Items.Clear
  Else
    FCommandsPopup := TPopupMenu.Create(Nil);
  If Not Assigned(AssistantMenu) Then
    Exit;
  For I := 0 To AssistantMenu.Items.Count - 1 Do
    Begin
      Group := AssistantMenu.Items[I];
      AddedInGroup := 0;
      For J := 0 To Group.Count - 1 Do
        Begin
          Cloned := CloneMenuItem(Group.Items[J], FCommandsPopup);
          If Not Assigned(Cloned) Then
            Continue;
          FCommandsPopup.Items.Add(Cloned);
          Inc(AddedInGroup);
        End;
      If (AddedInGroup > 0) And (I < AssistantMenu.Items.Count - 1) Then
        Begin
          Sep := TMenuItem.Create(FCommandsPopup);
          Sep.Caption := '-';
          FCommandsPopup.Items.Add(Sep);
        End;
    End;
End;

Procedure TProjectAssistantForm.EnsureSlashPopup;
Begin
  If Assigned(FSlashList) Then
    Exit;
  FSlashList := TListBox.Create(Nil);
  FSlashList.Visible := False;
  FSlashList.Style := lbOwnerDrawFixed;
  FSlashList.ItemHeight := Scale96ToForm(22);
  FSlashList.Height := Scale96ToForm(88);
  FSlashList.TabStop := True;
  FSlashList.Color := clWindow;
  FSlashList.OnDrawItem := @SlashListDrawItem;
  FSlashList.OnClick := @SlashListClick;
End;

Function TProjectAssistantForm.SlashPopupVisible: Boolean;
Begin
  Result := Assigned(FSlashList) And FSlashList.Visible;
End;

Procedure TProjectAssistantForm.HideSlashPopup;
Begin
  If Assigned(FSlashList) Then
    Begin
      FSlashList.Visible := False;
      FSlashList.Parent := Nil;
    End;
End;

Procedure TProjectAssistantForm.PositionSlashPopup;
Var
  P: TPoint;
  Count, H, MaxH: Integer;
Begin
  If Not Assigned(FSlashList) Or Not Assigned(InputMemo) Then
    Exit;
  Count := FSlashList.Items.Count;
  If Count < 1 Then
    Count := 1;
  If Count > 8 Then
    Count := 8;
  H := Count * FSlashList.ItemHeight + 4;
  MaxH := Scale96ToForm(220);
  If H > MaxH Then
    H := MaxH;
  FSlashList.Height := H;
  FSlashList.Width := InputMemo.Width;
  If FSlashList.Width < Scale96ToForm(280) Then
    FSlashList.Width := Scale96ToForm(280);
  P := InputMemo.ClientToScreen(Point(0, 0));
  P := ScreenToClient(P);
  FSlashList.Parent := Self;
  FSlashList.Left := P.X;
  FSlashList.Top := P.Y - FSlashList.Height;
  If FSlashList.Top < 0 Then
    FSlashList.Top := P.Y + InputMemo.Height;
  FSlashList.BringToFront;
End;

Function PromptCaretByte(Memo: TSpellMemo): Integer;
Begin
  Result := 0;
  If Not Assigned(Memo) Then
    Exit;
  Result := Length(UTF8Copy(Memo.Text, 1, Memo.SelStart));
End;

Procedure TProjectAssistantForm.UpdateSlashPopup;
Var
  Token, Filter: String;
  TokenStart, I, Hit: Integer;
  Entry: TAssistantCatalogItem;
Begin
  If Not Assigned(InputMemo) Then
    Exit;
  EnsureSlashPopup;
  RebuildCommandCatalog;
  Token := ExtractSlashToken(InputMemo.Text, PromptCaretByte(InputMemo), TokenStart);
  If (Token = '') Or (Token[1] <> '/') Then
    Begin
      HideSlashPopup;
      Exit;
    End;
  Filter := NormalizeSlashName(Token);
  FCatalog.Filter(Filter, FSlashHits);
  FSlashList.Items.BeginUpdate;
  Try
    FSlashList.Items.Clear;
    If Length(FSlashHits) = 0 Then
      FSlashList.Items.Add('No matching commands')
    Else
      For I := 0 To High(FSlashHits) Do
        Begin
          Hit := FSlashHits[I];
          Entry := FCatalog.GetItem(Hit);
          FSlashList.Items.AddObject(Entry.Caption, TObject(PtrInt(Hit + 1)));
        End;
  Finally
    FSlashList.Items.EndUpdate;
  End;
  If FSlashList.Items.Count > 0 Then
    FSlashList.ItemIndex := 0;
  PositionSlashPopup;
  FSlashList.Visible := True;
End;

Procedure TProjectAssistantForm.RemovePromptSlashToken;
Var
  TextValue: String;
  Caret: Integer;
Begin
  If Not Assigned(InputMemo) Then
    Exit;
  TextValue := InputMemo.Text;
  Caret := RemoveSlashToken(TextValue, PromptCaretByte(InputMemo));
  InputMemo.Text := TextValue;
  InputMemo.SelStart := UTF8Length(Copy(TextValue, 1, Caret));
End;

Procedure TProjectAssistantForm.ExecuteCatalogItem(Const Item: TAssistantCatalogItem);
Var
  SkillName: String;
Begin
  HideSlashPopup;
  If Assigned(Item.Action) And (Item.Action Is TAction) Then
    Begin
      If TAction(Item.Action).Enabled Then
        TAction(Item.Action).Execute;
      Exit;
    End;
  If Copy(Item.UserData, 1, 6) = 'skill:' Then
    Begin
      SkillName := Copy(Item.UserData, 7, MaxInt);
      PinActiveSkill(SkillName);
    End;
End;

Procedure TProjectAssistantForm.ExecuteSlashSelection;
Var
  Hit: Integer;
Begin
  If Not SlashPopupVisible Then
    Exit;
  If (FSlashList.ItemIndex < 0) Or (FSlashList.ItemIndex >= FSlashList.Items.Count) Then
    Exit;
  If Not Assigned(FSlashList.Items.Objects[FSlashList.ItemIndex]) Then
    Exit;
  Hit := Integer(PtrInt(FSlashList.Items.Objects[FSlashList.ItemIndex])) - 1;
  RemovePromptSlashToken;
  If (Hit >= 0) And (Hit < FCatalog.Count) Then
    ExecuteCatalogItem(FCatalog.GetItem(Hit));
End;

Procedure TProjectAssistantForm.SlashListDrawItem(Control: TWinControl; Index: Integer; ARect: TRect;
  State: TOwnerDrawState);
Var
  Box: TListBox;
  Hit: Integer;
  Entry: TAssistantCatalogItem;
  AliasText: String;
  CaptionR, AliasR: TRect;
Begin
  If Not (Control Is TListBox) Then
    Exit;
  Box := TListBox(Control);
  If odSelected In State Then
    Begin
      Box.Canvas.Brush.Color := clHighlight;
      Box.Canvas.Font.Color := clHighlightText;
    End
  Else
    Begin
      Box.Canvas.Brush.Color := clWindow;
      Box.Canvas.Font.Color := clWindowText;
    End;
  Box.Canvas.FillRect(ARect);
  If (Index < 0) Or (Index >= Box.Items.Count) Then
    Exit;
  CaptionR := ARect;
  CaptionR.Right := ARect.Left + ((ARect.Right - ARect.Left) * 2) Div 3;
  AliasR := ARect;
  AliasR.Left := CaptionR.Right;
  Box.Canvas.TextRect(CaptionR, CaptionR.Left + 6, CaptionR.Top + 2, Box.Items[Index]);
  If Assigned(Box.Items.Objects[Index]) Then
    Begin
      Hit := Integer(PtrInt(Box.Items.Objects[Index])) - 1;
      Entry := FCatalog.GetItem(Hit);
      AliasText := FormatSlashAlias(Entry.Slash);
      If odSelected In State Then
        Box.Canvas.Font.Color := clHighlightText
      Else
        Box.Canvas.Font.Color := clGrayText;
      If AliasText <> '' Then
        Box.Canvas.TextRect(AliasR, AliasR.Left, AliasR.Top + 2, AliasText);
    End;
End;

Procedure TProjectAssistantForm.SlashListClick(Sender: TObject);
Begin
  ExecuteSlashSelection;
End;

Procedure TProjectAssistantForm.PopupUnderControl(Host: TControl; Popup: TPopupMenu);
Var
  P: TPoint;
Begin
  If Not Assigned(Host) Or Not Assigned(Popup) Then
    Exit;
  P := Host.ClientToScreen(Point(0, Host.Height));
  Popup.PopUp(P.X, P.Y);
End;

Procedure TProjectAssistantForm.ApplyConfigAndRefresh;
Begin
  If Assigned(AssistantChatConfig) Then
    AssistantChatConfig.Save;
  RefreshFromConfig;
  PersistShellConfig;
End;

Procedure TProjectAssistantForm.PinActiveSkill(Const SkillName: String);
Begin
  If Not Assigned(AssistantChatConfig) Then
    Exit;
  AssistantChatConfig.ActiveSkill := SkillName;
  ApplyConfigAndRefresh;
  If SkillName = '' Then
    SetCurrentSystemNote('Pinned skill cleared. Plan and Build still attach free-pascal-engineer when it is installed.')
  Else
    SetCurrentSystemNote('Pinned skill **' + SkillName + '**. It is included in the next turn.');
End;

Procedure AddFooterItem(Menu: TPopupMenu; Const Caption: String; TagValue: Integer;
  Const ValueText: String; Checked, Radio: Boolean; Handler: TNotifyEvent);
Var
  Item: TMenuItem;
Begin
  Item := TMenuItem.Create(Menu);
  Item.Caption := Caption;
  If Caption <> '-' Then
    Begin
      Item.Tag := TagValue;
      Item.Hint := ValueText;
      Item.Checked := Checked;
      Item.RadioItem := Radio;
      Item.GroupIndex := TagValue;
      Item.OnClick := Handler;
    End;
  Menu.Items.Add(Item);
End;

Procedure TProjectAssistantForm.FillModelFooterMenu;
Var
  Models: TStringList;
  I: Integer;
  ModelName: String;
Begin
  Models := TStringList.Create;
  Try
    Models.Sorted := True;
    Models.Duplicates := dupIgnore;
    If FModelName <> '' Then
      Models.Add(FModelName);
    Models.Add(AssistantConfigDefaultModel);
    Models.Add('grok-4');
    Models.Add('grok-3');
    For I := 0 To Models.Count - 1 Do
      Begin
        ModelName := Models[I];
        AddFooterItem(FFooterMenu, ModelName, FooterTagModel, ModelName, SameText(ModelName, FModelName), True,
          @FooterMenuClick);
      End;
  Finally
    Models.Free;
  End;
End;

Procedure TProjectAssistantForm.FillThinkingFooterMenu;
Var
  Current: TAssistantThinkingLevel;
Begin
  Current := atlHigh;
  If Assigned(AssistantChatConfig) Then
    Current := AssistantChatConfig.GetThinkingLevel;
  AddFooterItem(FFooterMenu, 'Low thinking', FooterTagThinking, 'low', Current = atlLow, True,
    @FooterMenuClick);
  AddFooterItem(FFooterMenu, 'Medium thinking', FooterTagThinking, 'medium', Current = atlMedium, True,
    @FooterMenuClick);
  AddFooterItem(FFooterMenu, 'High thinking', FooterTagThinking, 'high', Current = atlHigh, True,
    @FooterMenuClick);
  AddFooterItem(FFooterMenu, 'XHigh thinking', FooterTagThinking, 'xhigh', Current = atlXHigh, True,
    @FooterMenuClick);
End;

Procedure TProjectAssistantForm.FillApprovalFooterMenu;
Var
  Current: TAssistantApprovalMode;
Begin
  Current := aamAsk;
  If Assigned(AssistantChatConfig) Then
    Current := AssistantChatConfig.GetApprovalMode;
  AddFooterItem(FFooterMenu, 'Approval: Ask', FooterTagApproval, 'ask', Current = aamAsk, True,
    @FooterMenuClick);
  AddFooterItem(FFooterMenu, 'Approval: Auto', FooterTagApproval, 'auto', Current = aamAuto, True,
    @FooterMenuClick);
  AddFooterItem(FFooterMenu, 'Approval: Always', FooterTagApproval, 'always', Current = aamAlways, True,
    @FooterMenuClick);
End;

Procedure TProjectAssistantForm.FillSkillFooterMenu;
Var
  Skills: TAssistantSkillList;
  I: Integer;
  Root, PinnedSkill: String;
Begin
  PinnedSkill := '';
  If Assigned(AssistantChatConfig) Then
    PinnedSkill := AssistantChatConfig.ActiveSkill;
  AddFooterItem(FFooterMenu, '(None)', FooterTagSkill, '', PinnedSkill = '', True, @FooterMenuClick);
  Root := '';
  If Assigned(ProjectAssistantConversation) Then
    Root := ProjectAssistantConversation.ProjectRoot;
  Skills := ListDiscoveredSkills(Root);
  For I := 0 To High(Skills) Do
    AddFooterItem(FFooterMenu, Skills[I].Name, FooterTagSkill, Skills[I].Name,
      SameText(Skills[I].Name, PinnedSkill), True, @FooterMenuClick);
End;

Procedure TProjectAssistantForm.FooterMenuClick(Sender: TObject);
Var
  Item: TMenuItem;
Begin
  If Not (Sender Is TMenuItem) Then
    Exit;
  Item := TMenuItem(Sender);
  If Not Assigned(AssistantChatConfig) Then
    Exit;
  Case Item.Tag Of
    FooterTagModel:
      If Trim(Item.Hint) <> '' Then
        Begin
          AssistantChatConfig.Model := Trim(Item.Hint);
          ApplyConfigAndRefresh;
        End;
    FooterTagThinking:
      Begin
        AssistantChatConfig.SetThinkingLevelEnum(StrToThinkingLevel(Item.Hint));
        ApplyConfigAndRefresh;
      End;
    FooterTagApproval:
      Begin
        AssistantChatConfig.SetApprovalModeEnum(StrToApprovalMode(Item.Hint));
        ApplyConfigAndRefresh;
      End;
    FooterTagSkill:
      PinActiveSkill(Item.Hint);
    FooterTagSettings:
      SettingsActionExecute(Sender);
  Else
    { }
  End;
End;

Procedure TProjectAssistantForm.ShowPlanOfferBar(OfferVisible: Boolean);
Begin
  FShowPlanOffer := OfferVisible And (GetActivePlanRelativePath <> '');
  If Assigned(PlanOfferBar) Then
    PlanOfferBar.Visible := FShowPlanOffer;
  ApplyInputPanelHeight;
  If Assigned(PlanOfferLabel) Then
    PlanOfferLabel.Caption := 'Plan written.';
End;

Procedure TProjectAssistantForm.ReviewButtonClick(Sender: TObject);
Var
  ScreenPt: TPoint;
Begin
  If Not Assigned(ReviewMenu) Or Not Assigned(ReviewButton) Then
    Exit;
  ScreenPt := ReviewButton.ClientToScreen(Point(0, ReviewButton.Height));
  ReviewMenu.PopUp(ScreenPt.X, ScreenPt.Y);
End;

Procedure TProjectAssistantForm.CommandsActionExecute(Sender: TObject);
Var
  ScreenPt: TPoint;
Begin
  HideSlashPopup;
  EnsureCommandsMenu;
  If Not Assigned(FCommandsPopup) Then
    Exit;
  If Assigned(SettingsButton) Then
    ScreenPt := SettingsButton.ClientToScreen(Point(0, SettingsButton.Height))
  Else If Assigned(SendButton) Then
    ScreenPt := SendButton.ClientToScreen(Point(0, SendButton.Height))
  Else
    ScreenPt := ClientToScreen(Point(8, 8));
  FCommandsPopup.PopUp(ScreenPt.X, ScreenPt.Y);
End;

Procedure TProjectAssistantForm.InputMemoKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
Begin
  If (Key = VK_V) And (ssCtrl In Shift) Then
    Begin
      Key := 0;
      QueueComposerPaste;
      Exit;
    End;
  If SlashPopupVisible Then
    Begin
      Case Key Of
        VK_ESCAPE:
          Begin
            Key := 0;
            HideSlashPopup;
            Exit;
          End;
        VK_UP:
          Begin
            Key := 0;
            If FSlashList.ItemIndex > 0 Then
              FSlashList.ItemIndex := FSlashList.ItemIndex - 1;
            Exit;
          End;
        VK_DOWN:
          Begin
            Key := 0;
            If FSlashList.ItemIndex < FSlashList.Items.Count - 1 Then
              FSlashList.ItemIndex := FSlashList.ItemIndex + 1;
            Exit;
          End;
        VK_RETURN, VK_TAB:
          Begin
            Key := 0;
            ExecuteSlashSelection;
            Exit;
          End;
      Else
        { }
      End;
    End;
  If (Key = VK_RETURN) And (ssCtrl In Shift) Then
    Begin
      Key := 0;
      SendActionExecute(Sender);
    End;
End;

Procedure TProjectAssistantForm.InputMemoUTF8KeyPress(Sender: TObject; Var UTF8Key: TUTF8Char);
Begin
  If SlashPopupVisible And ((UTF8Key = #13) Or (UTF8Key = #10) Or (UTF8Key = #9)) Then
    UTF8Key := '';
End;

Procedure TProjectAssistantForm.InputMemoChange(Sender: TObject);
Begin
  UpdateSlashPopup;
End;

Procedure TProjectAssistantForm.DeferredHideSlash(Data: PtrInt);
Begin
  If Assigned(FSlashList) And FSlashList.Focused Then
    Exit;
  HideSlashPopup;
End;

Procedure TProjectAssistantForm.InputMemoExit(Sender: TObject);
Begin
  Application.QueueAsyncCall(@DeferredHideSlash, 0);
End;

Procedure TProjectAssistantForm.StatusFooterLeftClick(Sender: TObject);
Begin
  ModelPickerActionExecute(Sender);
End;

Procedure TProjectAssistantForm.StatusFooterSkillClick(Sender: TObject);
Begin
  SkillsPickerActionExecute(Sender);
End;

Procedure TProjectAssistantForm.StatusFooterCentreClick(Sender: TObject);
Begin
  ContextBreakdownActionExecute(Sender);
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
  If FUseCodex Then
    Begin
      MessageDlg('ChatGPT preview sends the current prompt, light IDE context and a bounded conversation recap.', mtInformation, [mbOK], 0);
      Exit;
    End;
  HideSlashPopup;
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
  MessageDlg(Body, mtInformation, [mbOK], 0);
End;

Procedure TProjectAssistantForm.SessionInfoActionExecute(Sender: TObject);
Var
  Body, PlanRel, Root, SkillName: String;
  Turns: Integer;
  SignedIn: String;
Begin
  If FUseCodex Then
    Begin
      MessageDlg('ChatGPT preview uses a separate subscription sign-in profile. Open Settings → Connections to check the account and available models.', mtInformation, [mbOK], 0);
      Exit;
    End;
  HideSlashPopup;
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
  SkillName := '(none)';
  SignedIn := 'no';
  If Assigned(AssistantChatConfig) Then
    Begin
      If AssistantChatConfig.ActiveSkill <> '' Then
        SkillName := AssistantChatConfig.ActiveSkill;
      If AssistantChatConfig.IsSignedIn Then
        SignedIn := 'yes';
    End;
  Body :=
    'Project Assistant session' + LineEnding + LineEnding +
    'Mode: ' + ModeChipCaption(ActiveMode) + LineEnding +
    'Model: ' + FModelName + LineEnding;
  If Assigned(AssistantChatConfig) Then
    Body := Body +
      'Thinking: ' + ThinkingLevelCaption(AssistantChatConfig.GetThinkingLevel) + LineEnding +
      'Approval: ' + ApprovalModeCaption(AssistantChatConfig.GetApprovalMode) + LineEnding;
  Body := Body +
    'Skill: ' + SkillName + LineEnding +
    Format('Context: ~%d / %d tokens', [FContextUsed, FContextLimit]) + LineEnding +
    'Turns: ' + IntToStr(Turns) + LineEnding +
    'Active plan: ' + PlanRel + LineEnding +
    'Project: ' + Root + LineEnding +
    'Signed in: ' + SignedIn;
  MessageDlg(Body, mtInformation, [mbOK], 0);
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
  SettingsActionExecute(Sender);
End;

Procedure TProjectAssistantForm.ThinkingPickerActionExecute(Sender: TObject);
Begin
  If FUseCodex Then
    Begin
      SettingsActionExecute(Sender);
      Exit;
    End;
  HideSlashPopup;
  EnsureFooterMenu(FFooterMenu);
  FillThinkingFooterMenu;
  PopupUnderControl(StatusFooter, FFooterMenu);
End;

Procedure TProjectAssistantForm.SkillsPickerActionExecute(Sender: TObject);
Var
  Host: TControl;
Begin
  If FUseCodex Then
    Begin
      MessageDlg('ChatGPT preview uses Lazarus project and editor tools. Pinned Grok skills are not sent.', mtInformation, [mbOK], 0);
      Exit;
    End;
  HideSlashPopup;
  EnsureFooterMenu(FFooterMenu);
  FillSkillFooterMenu;
  AddFooterItem(FFooterMenu, '-', 0, '', False, False, Nil);
  AddFooterItem(FFooterMenu, 'Settings…', FooterTagSettings, '', False, False, @FooterMenuClick);
  Host := StatusFooter.SkillLabel;
  If Not Assigned(Host) Then
    Host := StatusFooter;
  PopupUnderControl(Host, FFooterMenu);
End;

Procedure TProjectAssistantForm.CompactContextActionExecute(Sender: TObject);
Var
  Saved: Integer;
Begin
  If FUseCodex Then
    Begin
      MessageDlg('ChatGPT preview sends a bounded recap of previous ChatGPT turns automatically.', mtInformation, [mbOK], 0);
      Exit;
    End;
  HideSlashPopup;
  If FSending Then
    Begin
      MessageDlg('Wait for the current reply to finish (or Stop) before compacting context.',
        mtInformation, [mbOK], 0);
      Exit;
    End;
  If Not Assigned(AssistantClient) Then
    Exit;
  Saved := AssistantClient.CompactOlderHistory;
  FContextUsed := AssistantClient.EstimatedPromptTokens;
  UpdateStatusFooter;
  If Saved < 1 Then
    SetCurrentSystemNote('Context is already compact enough for the current budget.')
  Else
    SetCurrentSystemNote(Format('Compacted context — about %d tokens removed. Re-read files if an older turn was trimmed.',
      [Saved]));
End;

Procedure TProjectAssistantForm.CopyLastAnswerActionExecute(Sender: TObject);
Var
  Body: String;
  Turn: TConversationTurn;
Begin
  HideSlashPopup;
  Body := Trim(FAssistantContent);
  If (Body = '') And Assigned(ProjectAssistantConversation) And
    (ProjectAssistantConversation.TurnCount > 0) Then
    If ProjectAssistantConversation.GetTurn(ProjectAssistantConversation.TurnCount - 1, Turn) Then
      Body := Trim(Turn.Response);
  If Body = '' Then
    Begin
      MessageDlg('No answer to copy yet.', mtInformation, [mbOK], 0);
      Exit;
    End;
  Clipboard.AsText := Body;
  StatusFooter.SetRightText('Copied answer');
End;

Procedure TProjectAssistantForm.OpenPlanActionExecute(Sender: TObject);
Begin
  HideSlashPopup;
  BuildOpenPlanButtonClick(Sender);
End;

Procedure TProjectAssistantForm.BuildThisActionExecute(Sender: TObject);
Var
  Idx: Integer;
  Title: String;
Begin
  HideSlashPopup;
  ShowPlanOfferBar(False);
  If GetActivePlanRelativePath = '' Then
    Begin
      MessageDlg('Set an active plan on the Plan panel first.', mtInformation, [mbOK], 0);
      Exit;
    End;
  SelectMode(amBuild);
  RefreshBuildTodos;
  Idx := FindNextIncompleteBuildSection;
  Title := '';
  If (Idx >= 0) And Assigned(BuildSections) And (Idx < BuildSections.Count) Then
    Begin
      FBuildSelectedIndex := Idx;
      If Assigned(BuildTodoList) And (Idx < BuildTodoList.Items.Count) Then
        BuildTodoList.ItemIndex := Idx;
      Title := TPlanSection(BuildSections[Idx]).Title;
    End;
  If Assigned(InputMemo) Then
    Begin
      If Title <> '' Then
        InputMemo.Text := 'Implement the next incomplete section: ' + Title
      Else
        InputMemo.Text := 'Implement the next incomplete section of the active plan.';
      InputMemo.SelStart := Length(InputMemo.Text);
      InputMemo.SetFocus;
    End;
End;

Procedure TProjectAssistantForm.RevisePlanActionExecute(Sender: TObject);
Begin
  HideSlashPopup;
  ShowPlanOfferBar(False);
  SelectMode(amPlan);
  If Assigned(InputMemo) Then
    Begin
      InputMemo.Text := 'Revise the active plan: ';
      InputMemo.SelStart := Length(InputMemo.Text);
      InputMemo.SetFocus;
    End;
End;

Procedure TProjectAssistantForm.ChatModeActionExecute(Sender: TObject);
Begin
  HideSlashPopup;
  If Not FSending Then
    SelectMode(amChat);
End;

Procedure TProjectAssistantForm.InspectModeActionExecute(Sender: TObject);
Begin
  HideSlashPopup;
  If Not FSending Then
    SelectMode(amInspect);
End;

Procedure TProjectAssistantForm.PlanModeActionExecute(Sender: TObject);
Begin
  HideSlashPopup;
  If Not FSending Then
    SelectMode(amPlan);
End;

Procedure TProjectAssistantForm.BuildModeActionExecute(Sender: TObject);
Begin
  HideSlashPopup;
  If Not FSending Then
    SelectMode(amBuild);
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
    MessageDlg('The pictures stay in the composer for the next message.', mtInformation, [mbOK], 0);
  End;
Begin
  If SlashPopupVisible Then
    Begin
      ExecuteSlashSelection;
      Exit;
    End;
  If Not Assigned(InputMemo) Then Exit;
  UserText := Trim(InputMemo.Text);
  HasImages := ComposerHasImages;
  If (UserText = '') And (Not HasImages) Then
    Exit;
  If FSending Then
    Begin
      Reason := '';
      { Codex has no turn/steer image item. Keep the 3.2 warning and do not clear the strip. }
      AcceptImages := HasImages And ComposerAttachAllowed(Reason) And (Not FUseCodex) And (Not Assigned(FCodexRun));
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
          If (Not Assigned(AssistantClient)) Or (Not AssistantClient.EnqueueSteer(UserText, Refs)) Then Exit;
          InputMemo.Clear;
          FComposerImagesJson := '';
          RefreshComposerImages;
          SetStreamPhase('Steering at next tool gap…');
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
  If (Not FUseCodex) And ((Not Assigned(AssistantChatConfig)) Or (Not AssistantChatConfig.IsSignedIn)) Then
    Begin
      MessageDlg('Sign in with SuperGrok / X Premium in Settings before sending.', mtInformation, [mbOK], 0);
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
  If FUseCodex Then
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
  FStatusPhase := 'Waiting for first token…';
  AssistantClient.ToolsEnabled := False;
  SetSending(True);
  BeginAssistantReply;
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
      MessageDlg('Select a project or package before using Review ' + KindLabel + '.', mtInformation, [mbOK], 0);
      Exit;
    End;

  FReviewInProgress := True;
  ReviewCompileAction.Enabled := False;
  ReviewBuildAction.Enabled := False;
  ReviewChangesAction.Enabled := False;
  StatusFooter.SetRightText(KindLabel + '…');
  StatusFooter.Update;
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
        StatusFooter.SetRightText(KindLabel + ' OK');
        FPendingReviewErrorOffer := False;
        FReviewErrorCount := 0;
      End
    Else If ErrorCount > 0 Then
      Begin
        StatusFooter.SetRightText(KindLabel + ' failed');
        PrepareTopErrorAfterReview(ErrorCount);
      End
    Else
      Begin
        StatusFooter.SetRightText(KindLabel + ' done');
        FPendingReviewErrorOffer := False;
        FReviewErrorCount := 0;
      End;

    { Reviews start a fresh conversation (own model context); prior chat is archived. }
    If Assigned(ProjectAssistantConversation) And (ProjectAssistantConversation.ProjectRoot <> '') Then
      Begin
        If Not ProjectAssistantConversation.StartNewConversation Then
          WorkflowLogger.Warning('ProjectAssistant', 'Review archive: ' + ProjectAssistantConversation.LastError);
      End;
    Transcript.Clear;
    FContextUsed := 0;
    FTurnRecorded := False;
    FSelectedTurnIndex := -1;
    If Assigned(AssistantClient) Then
      AssistantClient.ClearHistory;
    ClearProjectChatSession;
    RefreshHistoryCombo;
    RefreshConversationList;

    SubmitReviewRequest(DisplayLabel, PromptText);
  Finally
    { Keep FReviewInProgress True while the review stream runs so a second click
      cannot start a duplicate review with the same Messages dump. }
    If Not FSending Then
      Begin
        FReviewInProgress := False;
        ReviewCompileAction.Enabled := True;
        ReviewBuildAction.Enabled := True;
        ReviewChangesAction.Enabled := True;
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

Procedure TProjectAssistantForm.StartNewChat(KeepPlanAgent: Boolean; UseChatDefault: Boolean);
Begin
  FPlanAgentResumeIndex := -1;
  ShowPlanOfferBar(False);
  If FPlanAgentRunning And (Not KeepPlanAgent) Then
    StopWorkOnPlanAgent('new chat');
  If FSending Then
    StopStream;
  SetSending(False);
  ClearUnsentComposerImages;
  EnsureConversationStore;
  If Assigned(ProjectAssistantConversation) And (ProjectAssistantConversation.ProjectRoot <> '') Then
    Begin
      If Not ProjectAssistantConversation.StartNewConversation Then
        WorkflowLogger.Warning('ProjectAssistant', 'StartNewConversation: ' + ProjectAssistantConversation.LastError);
    End;
  Transcript.Clear;
  FContextUsed := 0;
  FContextWarnShown := False;
  FUserCancelled := False;
  FTurnRecorded := False;
  FLastChatPaintTick := 0;
  FSelectedTurnIndex := -1;
  ClearCurrentTurnDisplay;
  If Assigned(AssistantClient) Then
    AssistantClient.ClearHistory;
  ClearProjectChatSession;
  RefreshHistoryCombo;
  RefreshConversationList;
  RefreshChatDisplay(True, False);
  If UseChatDefault Then
    SelectMode(amChat);
  If Not FAutoRolloverInProgress Then
    Begin
      If UseChatDefault Then
        SetCurrentSystemNote('New conversation started in **Chat**. Previous chat moved to History.')
      Else
        SetCurrentSystemNote('New conversation started. Previous chat moved to History.');
    End;
  PersistSession;
  UpdateStatusFooter;
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
  Transcript.Clear;
  FContextUsed := 0;
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
  RefreshHistoryCombo;
  RefreshConversationList;
  ClearCurrentTurnDisplay;
  RefreshChatDisplay(True, False);
  RefreshPlanList;
  UpdateStatusFooter;
  WorkflowLogger.Info('ProjectAssistant', 'Unbound from project');
End;

Procedure TProjectAssistantForm.BindToActiveProject;
Var
  Key, Title, Root, Saved, Note: String;
Begin
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
  If Assigned(FCodexBroker) Then FCodexBroker.Cancel;
  If Assigned(FCodexWorkspace) Then FCodexWorkspace.CancelBuild;
  SetActivePlanRelativePath('');

  Caption := Title;
  FSessionProjectKey := '';
  ClearCurrentTurnDisplay;
  Transcript.Clear;
  FContextUsed := 0;
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
    AssistantClient.OnTrace := @HandleTraceEvent;
  { Re-sync client tools/mode after shell prefs (and after default tab if no config). }
  ApplyActiveMode;
  If Root <> '' Then
    Begin
      FSessionProjectKey := Key;
      RestoreSessionIfNeeded;
      RefreshHistoryCombo;
      RefreshConversationList;
      RefreshPlanList;
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
      RefreshHistoryCombo;
      RefreshConversationList;
      ClearCurrentTurnDisplay;
      RefreshChatDisplay(True, False);
      RefreshPlanList;
    End;
  UpdateStatusFooter;
  If Root <> '' Then
    WorkflowLogger.Info('ProjectAssistant', 'Bound to project: ' + Title + ' root=' + Root)
  Else
    WorkflowLogger.Info('ProjectAssistant', 'Bound to project: ' + Title);
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

Procedure TProjectAssistantForm.FixSelectedError;
Begin
  { Prefer the top error when Messages has errors (e.g. after Review). }
  FixTopError;
End;

Procedure TProjectAssistantForm.FixTopError;
Var
  Line: TMessageLine;
  Prompt: String;
  Col, TopLine: Integer;
Begin
  If FSending Then
    Begin
      MessageDlg('Wait for the current reply to finish (or Stop) before Fix Error.',
        mtInformation, [mbOK], 0);
      Exit;
    End;
  If Not Assigned(IDEMessagesWindow) Then
    Begin
      MessageDlg('The IDE Messages window is not available.', mtInformation, [mbOK], 0);
      Exit;
    End;
  FPendingReviewErrorOffer := False;
  Line := ResolveMessageLineForFix(True);
  If Not Assigned(Line) Then
    Begin
      MessageDlg('No compiler messages found. Run Compile/Build (or Review Compile) first, ' +
        'or select a message in the Messages window, then choose Fix Error.',
        mtInformation, [mbOK], 0);
      Exit;
    End;
  Prompt := BuildFixErrorPromptForLine(Line);
  If Prompt = '' Then
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

Procedure TProjectAssistantForm.NewChatActionExecute(Sender: TObject);
Begin
  StartNewChat;
  If InputMemo.CanFocus Then InputMemo.SetFocus;
End;

Procedure TProjectAssistantForm.HistoryComboChange(Sender: TObject);
Var
  ArchiveId: String;
Begin
  If FHistoryUpdating Then
    Exit;
  If FSending Then
    Begin
      MessageDlg('Stop the current reply before switching History.', mtInformation, [mbOK], 0);
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
      MessageDlg('Could not open conversation:' + LineEnding + ProjectAssistantConversation.LastError,
        mtError, [mbOK], 0);
      RefreshHistoryCombo;
      Exit;
    End;
  ClearProjectChatSession;
  SelectMode(ModeOfLoadedConversation);
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
      MessageDlg('Stop the current reply before exporting.', mtInformation, [mbOK], 0);
      Exit;
    End;
  EnsureConversationStore;
  If (Not Assigned(ProjectAssistantConversation)) Or (Not ProjectAssistantConversation.HasTurns) Then
    Begin
      MessageDlg('There is nothing to export in the current conversation.', mtInformation, [mbOK], 0);
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
        MessageDlg('Could not write export file:' + LineEnding + E.Message, mtError, [mbOK], 0);
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
      MessageDlg('Stop the current reply before deleting a conversation.', mtInformation, [mbOK], 0);
      Exit;
    End;
  If Not Assigned(HistoryCombo) Or Not Assigned(HistoryIds) Then
    Exit;
  If (HistoryCombo.ItemIndex < 0) Or (HistoryCombo.ItemIndex >= HistoryIds.Count) Then
    Exit;
  ArchiveId := HistoryIds[HistoryCombo.ItemIndex];
  LabelText := HistoryCombo.Items[HistoryCombo.ItemIndex];
  IsCurrent := ArchiveId = '';
  If MessageDlg(
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
      MessageDlg('Could not delete conversation:' + LineEnding + ProjectAssistantConversation.LastError,
        mtError, [mbOK], 0);
      Exit;
    End;
  If IsCurrent Then
    Begin
      Transcript.Clear;
      FContextUsed := 0;
      FTurnRecorded := False;
      FSelectedTurnIndex := -1;
      ClearCurrentTurnDisplay;
      If Assigned(AssistantClient) Then
        AssistantClient.ClearHistory;
      ClearProjectChatSession;
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

Procedure TProjectAssistantForm.ReviewCompileActionExecute(Sender: TObject);
Begin
  ReviewCompile;
End;

Procedure TProjectAssistantForm.ReviewBuildActionExecute(Sender: TObject);
Begin
  ReviewBuild;
End;

Procedure TProjectAssistantForm.ReviewChangesActionExecute(Sender: TObject);
Var
  Prompt: String;
Begin
  If FSending Or FReviewInProgress Then
    Exit;
  If Not Assigned(LazarusIDE) Or Not AssistantTarget.Available Then
    Begin
      MessageDlg('Select a project or package before reviewing changes.', mtInformation, [mbOK], 0);
      Exit;
    End;
  Prompt := BuildReviewLensesPrompt(FormatChangedProjectFiles);
  ForceModeAndLock(amBuild);
  ShowChatSurfaceKeepMode;
  SubmitUserTextEx('Review Changes (naming · structure · review)', Prompt, True);
  If Not FSending Then
    UnlockModeAfterSend;
End;

Procedure TProjectAssistantForm.FixErrorActionExecute(Sender: TObject);
Begin
  FixSelectedError;
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
  Case Result Of
    crSuccess:
      StatusFooter.SetRightText(Format('Compile OK (%d warn)', [WarningCount]));
    crFailed:
      StatusFooter.SetRightText(Format('Compile failed (%d err)', [ErrorCount]));
    crCancelled:
      StatusFooter.SetRightText('Cancelled');
  Else
    { }
  End;
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
  If (PlanRel = '') Or (Not Assigned(BuildPanel)) Then
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
      RefreshPlanList;
      If Assigned(BuildPanel) Then
        RefreshBuildTodos;
    End;
End;

End.
