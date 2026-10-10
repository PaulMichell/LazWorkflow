Unit ProjectAssistantForm;

{ Project Assistant main window — conversation and prompt on the left, sidebar on the right (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. The IDE dock shell owns mode chips,
  history, plan/build tiles, and send/steer as one form. Trace paint lives in
  AssistantTraceView. The prompt is ordinary text. Reviewed 2026-09-27: Chat is a
  fourth mode with no project tools or skill; the mode bar is a label and combobox.
  Composer paste and drop stay here. Attach Image is on the memo popup, after Paste.
  The image list holds pictures only;
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
  Classes, SysUtils, Contnrs, Forms, Controls, Graphics, GraphType, Dialogs, ExtCtrls, StdCtrls, ComCtrls,
  LCLType, Menus, ActnList, Clipbrd, WorkflowEvents, StatusFooterFrame, SpellMemo, CompOptsIntf,
  IDEExternToolIntf, AssistantConversation, AssistantPlan, AssistantEvents, AssistantTrace,
  AssistantTraceView, AssistantAcceptance, AssistantBuildJob, AssistantCodexRun, AssistantToolBroker,
  AssistantIDEWorkspace, AssistantGit, AssistantAccountUsage;

Type
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
    StopAction: TAction;
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
    RemovePlanAction: TAction;
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
    OpenPlanSheetButton: TButton;
    RemovePlanButton: TButton;
    ComposerStack: TPanel;
    BottomBar: TPanel;
    NewConversationButton: TButton;
    NewPlanButton: TButton;
    RunPlanButton: TButton;
    SettingsButton: TButton;
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
    Procedure SidebarPagesChanging(Sender: TObject; Var AllowChange: Boolean);
    Procedure SidebarPagesChange(Sender: TObject);
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
    Procedure BuildTodoListSelectionChange(Sender: TObject; User: Boolean);
    Procedure HistoryComboChange(Sender: TObject);
    Procedure SendActionExecute(Sender: TObject);
    Procedure StopActionExecute(Sender: TObject);
    Procedure NewConversationActionExecute(Sender: TObject);
    Procedure NewPlanActionExecute(Sender: TObject);
    Procedure RunPlanActionExecute(Sender: TObject);
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
    Procedure RemovePlanActionExecute(Sender: TObject);
    Procedure OpenPlanActionExecute(Sender: TObject);
    Procedure ComposerStackResize(Sender: TObject);
    Procedure StatusFooterResize(Sender: TObject);
    Procedure PromptHostResize(Sender: TObject);
    Procedure InputMemoPaste(Sender: TObject);
    Procedure InputMemoKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
    Procedure StatusFooterLeftClick(Sender: TObject);
    Procedure StatusFooterSkillClick(Sender: TObject);
    Procedure StatusFooterCentreClick(Sender: TObject);
    Procedure StatusFooterRightClick(Sender: TObject);
    Procedure FooterMenuClick(Sender: TObject);
  Private
    FRefreshingTargets: Boolean;
    FRefreshingPlans: Boolean;
    FTargetPaths: TStringList;
    FTargetRestored: Boolean;
    Procedure ApplyTarget(Const Directory: String);
  Private

    FUseCodex: Boolean;
    FUseClaude: Boolean;
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
    FCodexRuntime, FCodexModel, FCodexProfile, FCodexIdentity, FCodexEffort, FCodexApproval: String;
    FCodexRun: TAssistantCodexRun;
    FPollingCodex: Boolean;
    FCodexWorkspace: TAssistantIDEWorkspace;
    FCodexBroker: TAssistantToolBroker;
    Procedure LoadConnectionSettings;
    Procedure RecordCompletedUsage;
    Function ApproveCodexTool(Const Tool, Path, OldText, NewText: String): Boolean;
    Function StartCodexReply(Const DisplayText, ApiText: String): Boolean;
    Procedure PollCodex;
    Procedure ReleaseCodexRun;
  Private
    ElapsedTimer: TTimer;
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
    FAdjustingSidebarPage: Boolean; { True while bouncing a disabled Plan sheet back to History. }
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
    FLastTurnHadError: Boolean;
    FFooterMenu: TPopupMenu;
    FPlanWriteThisTurn: Boolean;
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
    Function TryAttachClipboardImage(Out ErrorText: String): Boolean;
    Procedure ClearUnsentComposerImages;
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
    Procedure ApplyModelStatus;
    Procedure ApplySkillStatus;
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
    Procedure StopRunPlan(Const Reason: String);
    Procedure ContinueRunPlan(Data: PtrInt);
    Function FindNextIncompleteBuildSection: Integer;
    Function BuildWorkPrompt(Const PlanRel, SectionTitle, StatusText, SectionBody, ParentTitle: String;
      ContinueSameItem: Boolean): String;
    Procedure MaybeWarnHighContextUsage;
    Function AutoCompactAtLimitEnabled: Boolean;
    Function CompactOpenChat: Integer;
    Procedure ApplyDisplayPreferences;
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
    Procedure ScrollChatToEnd;
    Procedure ScrollChatToTop;
    Procedure RefreshChatDisplay(Force: Boolean; ScrollToBottom: Boolean = True);
    Procedure SetBusyCursor(IsBusy: Boolean);
    Procedure SetOpenBusy(IsBusy: Boolean);
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
    { Plan or Document directive, then the user text, then the IDE context block. Chat is the user text only. }
    Function BuildSubmitApiText(Const ModelText: String; Out WithContext: Boolean): String;
    Procedure SteerQueuedText(Const UserText: String);
    Function ModeChipCaption(Mode: TAssistantMode): String;
    Function RunPlanIsAvailable: Boolean;
    Procedure UpdateWorkActions;
    Procedure PopupUnderControl(Host: TControl; Popup: TPopupMenu);
    Procedure ApplyConfigAndRefresh;
    Procedure ToggleSkillForMode(Const SkillName: String);
    Function ModeSkillCaption: String;
    Procedure FillSkillFooterMenu;
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
    { Read the saved active connection and refresh the status bar. }
    Procedure ReloadActiveConnection;
  End;

Procedure NotifyOpenProjectAssistantFormsProjectChanged;
Procedure NotifyOpenProjectAssistantFormsProjectCleared;
Procedure NotifyOpenProjectAssistantFormsPreferencesChanged;
Procedure NotifyOpenProjectAssistantFormsConnectionChanged;
Procedure NotifyOpenProjectAssistantFormsAccountUsage;

Implementation

{$R *.lfm}

Uses AssistantWorkTarget, PackageIntf,
  WorkflowLog, AssistantService, AssistantConfig, AssistantSettingsForm, AssistantIDEContext,
  AssistantTools, AssistantMarkdownForm, AssistantSubagents, GrokOAuth, LazFileUtils,
  FileUtil, LCLIntf, LazIDEIntf, IDEMsgIntf, SrcEditorIntf, fpimage, fpwritepng,
  ProjectIntf, AssistantSkills, AssistantConnections, AssistantUsage, AssistantCodexSettings, AssistantCodexClient,
  AssistantCodexUsage, AssistantHarness,
  AssistantImages,
  AssistantImageView
  {$IFDEF LCLGTK3}, gtk3widgets, LazGtk3, LazGdk3, LazGLib2, LazGObject2{$ENDIF};

Const
  ChatPaintMinIntervalMs = 80;
  { List Objects store TurnIndex+1; this marker is the in-flight (not yet recorded) turn. }
  LiveConversationMarker = -2;
  FooterTagSkill = 4;
  FooterTagSettings = 5;

Constructor TProjectAssistantForm.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FModelName := AssistantConfigDefaultModel;
  FContextUsed := 0;
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
  FLastTurnHadError := False;
  FOpenBindPending := True;
  FDeferLastTurn := True;
  FOpenBusy := False;
  FPlanWriteThisTurn := False;
  LoadConnectionSettings;
  WorkflowEventBus.AddListener(Self);
  SyncModeUi;
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
  { BeforeDestruction takes the write lock and sets csDestroying. A failed
    constructor skips BeforeDestruction, so take the lock here or TCustomForm.Destroy
    calls EndWrite with no matching BeginWrite and the real error is lost. }
  OwnWrite := Not (csDestroying In ComponentState);
  If OwnWrite Then
    GlobalNameSpace.BeginWrite;
  Destroying;
  If Assigned(ElapsedTimer) Then ElapsedTimer.Enabled := False;
  ReleaseAccountUsageRefresh;
  Application.RemoveAsyncCalls(Self);
  If Assigned(WorkflowEventBus) Then WorkflowEventBus.RemoveListener(Self);
  SetAssistantPlanViewerQuiet(False);
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
  FTargetPaths := TStringList.Create;
  RefreshTargetChoices(Nil);
  Caption := 'Project Assistant';
  { AllowDropFiles exists only on the form in this LCL. GTK still delivers the
    drop to the widget under the pointer, so the input controls are armed after
    their handles exist. Names arrive through OnDropFiles. }
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
  EnsureChatView;
  If Assigned(FTraceView) And Assigned(FTrace) Then
    FTraceView.Sync(FTrace, False);
  EnsureInputPopup;
  If Assigned(StatusFooter) Then
    Begin
      StatusFooter.OnLeftClick := @StatusFooterLeftClick;
      StatusFooter.OnSkillClick := @StatusFooterSkillClick;
      StatusFooter.OnCentreClick := @StatusFooterCentreClick;
      StatusFooter.OnRightClick := @StatusFooterRightClick;
    End;
  ApplyDisplayPreferences;
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
    AssistantClient.OnTrace := @HandleTraceEvent;
  WorkflowLogger.Info('ProjectAssistant', 'Project Assistant window created');
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
      RefreshActivePlanChoices(Nil);
      RefreshBuildTodos;
      UpdateWorkActions;
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
  SizeSheetBottomButtons(PlanSheet, OpenPlanSheetButton, RemovePlanButton, Scale96ToForm(4));
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
  If FUseClaude Then
    Begin
      { No Claude turn is wired. Do not describe a private tool set. }
      StatusFooter.SetSkillText('Not wired');
      StatusFooter.SetSkillHint('The Claude turn is not wired.');
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

Function TProjectAssistantForm.RunPlanIsAvailable: Boolean;
Begin
  { Not limited to Plan or Build. Run Plan switches to Build itself. }
  Result := (Not FSending) And (GetActivePlanRelativePath <> '');
End;

Procedure TProjectAssistantForm.UpdateWorkActions;
Begin
  If Assigned(OpenPlanSheetAction) Then
    OpenPlanSheetAction.Enabled := GetActivePlanRelativePath <> '';
  If Assigned(RemovePlanAction) Then
    RemovePlanAction.Enabled := (Not FSending) And (GetActivePlanRelativePath <> '');
  If Assigned(NewPlanAction) Then
    NewPlanAction.Enabled := Not FSending;
  If Assigned(RunPlanAction) Then
    RunPlanAction.Enabled := RunPlanIsAvailable;
End;

Procedure TProjectAssistantForm.SidebarPagesChanging(Sender: TObject; Var AllowChange: Boolean);
Begin
  { Only a move onto the disabled Plan sheet is refused. Leaving it must stay possible. }
  If Not Assigned(PlanSheet) Or PlanSheet.Enabled Then
    Exit;
  If Assigned(SidebarPages) And (SidebarPages.ActivePage = PlanSheet) Then
    Exit;
  AllowChange := False;
  If Sender <> SidebarPages Then
    Exit;
End;

Procedure TProjectAssistantForm.SidebarPagesChange(Sender: TObject);
Begin
  If FAdjustingSidebarPage Or Not Assigned(SidebarPages) Or Not Assigned(PlanSheet) Or
    Not Assigned(HistorySheet) Then
    Exit;
  If (SidebarPages.ActivePage <> PlanSheet) Or PlanSheet.Enabled Then
    Exit;
  FAdjustingSidebarPage := True;
  Try
    SidebarPages.ActivePage := HistorySheet;
  Finally
    FAdjustingSidebarPage := False;
  End;
  If Sender <> SidebarPages Then
    Exit;
End;

Procedure TProjectAssistantForm.UpdateModeSidePanels;
Var
  PlanAllowed: Boolean;
Begin
  { Chat and Inspect cannot open Plan. Do not select that page when it becomes allowed. }
  PlanAllowed := ActiveMode In [amPlan, amBuild];
  If Assigned(PlanSheet) Then
    Begin
      If Not PlanAllowed Then
        Begin
          If Assigned(SidebarPages) And Assigned(HistorySheet) And (SidebarPages.ActivePage = PlanSheet) Then
            SidebarPages.ActivePage := HistorySheet;
          PlanSheet.Enabled := False;
        End
      Else
        PlanSheet.Enabled := True;
    End;
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
Var
  Paths, Titles: TStringList;
  Err, ActivePlan, CaptionText: String;
  I, Selected: Integer;
  ActiveMissing: Boolean;
Begin
  If Not Assigned(ActivePlanCombo) Or Not Assigned(ActivePlanPaths) Then
    Exit;
  { OnDropDown passes the combo. Other callers pass Nil. Both refill from the settings. }
  If (Sender <> Nil) And (Sender <> ActivePlanCombo) Then
    Exit;
  FRefreshingPlans := True;
  ActivePlanCombo.Items.BeginUpdate;
  Try
    ActivePlanCombo.Items.Clear;
    ActivePlanPaths.Clear;
    ActivePlan := GetActivePlanRelativePath;
    Selected := -1;
    Paths := Nil;
    Titles := Nil;
    ActiveMissing := False;
    If ListAvailableAssistantPlans(ActivePlan, Paths, Titles, ActiveMissing, Err) Then
      Begin
        If ActiveMissing Then
          Begin
            SetActivePlanRelativePath('');
            PersistShellConfig;
            ActivePlan := '';
            WorkflowLogger.Info('ProjectAssistant', 'Removed missing active plan from the available list.');
          End;
        For I := 0 To Paths.Count - 1 Do
          Begin
            If I < Titles.Count Then
              CaptionText := Titles[I]
            Else
              CaptionText := PlanComboCaption('', Paths[I]);
            ActivePlanCombo.Items.Add(CaptionText);
            ActivePlanPaths.Add(Paths[I]);
            If SameText(Paths[I], ActivePlan) Then
              Selected := I;
          End;
      End
    Else If Err <> '' Then
      WorkflowLogger.Warning('ProjectAssistant', 'Available plan list: ' + Err);
    ActivePlanCombo.ItemIndex := Selected;
    ActivePlanCombo.ParentShowHint := False;
    ActivePlanCombo.ShowHint := Selected >= 0;
    If Selected >= 0 Then
      ActivePlanCombo.Hint := ActivePlanPaths[Selected]
    Else
      ActivePlanCombo.Hint := '';
  Finally
    ActivePlanCombo.Items.EndUpdate;
    FRefreshingPlans := False;
    Paths.Free;
    Titles.Free;
  End;
  If ActiveMissing Then
    RefreshBuildTodos;
  UpdateWorkActions;
End;

Procedure TProjectAssistantForm.ActivePlanChoiceChanged(Sender: TObject);
Var
  Rel: String;
Begin
  If FRefreshingPlans Then
    Exit;
  If FSending Or FReviewInProgress Then
    Begin
      RefreshActivePlanChoices(Nil);
      Exit;
    End;
  If Not Assigned(ActivePlanCombo) Or Not Assigned(ActivePlanPaths) Then
    Exit;
  If (ActivePlanCombo.ItemIndex < 0) Or (ActivePlanCombo.ItemIndex >= ActivePlanPaths.Count) Then
    Exit;
  Rel := ActivePlanPaths[ActivePlanCombo.ItemIndex];
  If SameText(Rel, GetActivePlanRelativePath) Then
    Exit;
  SetActivePlanRelativePath(Rel);
  PersistShellConfig;
  RefreshBuildTodos;
  UpdateWorkActions;
  If Sender <> ActivePlanCombo Then
    Exit;
End;

Procedure TProjectAssistantForm.ActivePlanBrowseClick(Sender: TObject);
Var
  Dialog: TOpenDialog;
  InitialDir, Resolved, Title, Err, Rel, Rejected, ChosenPath: String;
  I: Integer;
  Added: Boolean;
Begin
  If FSending Or FReviewInProgress Then
    Exit;
  Dialog := TOpenDialog.Create(Nil);
  Try
    Dialog.Title := 'Add plans';
    Dialog.Filter := 'Markdown (*.md)|*.md';
    Dialog.Options := Dialog.Options + [ofFileMustExist, ofAllowMultiSelect];
    InitialDir := ExcludeTrailingPathDelimiter(ProjectDocumentsDir);
    If (InitialDir = '') Or (Not DirectoryExistsUTF8(InitialDir)) Then
      InitialDir := ExcludeTrailingPathDelimiter(ProjectRootPath);
    Dialog.InitialDir := InitialDir;
    If Not Dialog.Execute Then
      Exit;
    Added := False;
    Rejected := '';
    Rel := '';
    For I := 0 To Dialog.Files.Count - 1 Do
      Begin
        ChosenPath := Dialog.Files[I];
        If Not ResolvePlanPath(ChosenPath, Resolved, Err) Then
          Begin
            Rejected := Rejected + ChosenPath + ': ' + Err + LineEnding;
            Continue;
          End;
        If Not TryReadAssistantPlanIdentity(Resolved, Title, Err) Then
          Begin
            Rejected := Rejected + ExtractFileName(Resolved) + ': ' + Err + LineEnding;
            Continue;
          End;
        If Not AddAvailableAssistantPlan(Resolved, Err) Then
          Begin
            Rejected := Rejected + ExtractFileName(Resolved) + ': ' + Err + LineEnding;
            Continue;
          End;
        Rel := ProjectRelativePath(Resolved);
        Added := True;
      End;
    If Added Then
      Begin
        SetActivePlanRelativePath(Rel);
        PersistShellConfig;
        RefreshActivePlanChoices(Nil);
        RefreshBuildTodos;
        UpdateWorkActions;
      End;
    If Rejected <> '' Then
      MessageDlg('Some files were not added:' + LineEnding + Rejected, mtError, [mbOK], 0);
  Finally
    Dialog.Free;
  End;
  If Sender <> ActivePlanBrowseButton Then
    Exit;
End;

Procedure TProjectAssistantForm.NewPlan;
Var
  Title, Rel, Resolved, Err, Content: String;
Begin
  SelectMode(amPlan);
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
  If Not AddAvailableAssistantPlan(Resolved, Err) Then
    MessageDlg(Err, mtWarning, [mbOK], 0);
  RefreshActivePlanChoices(Nil);
  RefreshBuildTodos;
  UpdateWorkActions;
  SetCurrentSystemNote('Created plan **' + GetActivePlanRelativePath +
    '**. Stay in **Plan** mode and send a message to refine it with the model.');
End;

Procedure TProjectAssistantForm.RefreshBuildTodos;
Var
  PlanRel, Err, Summary: String;
  I, KeepHeading, SelectIndex, NotStarted, InProgress, Complete: Integer;
  Section: TPlanSection;

  Procedure ShowPlanCounts;
  Begin
    If Not Assigned(BuildStatusLabel) Then
      Exit;
    Summary := Format('%d not started · %d in progress · %d complete', [NotStarted, InProgress, Complete]);
    If (NotStarted + InProgress + Complete) = 0 Then
      Summary := Summary + '  ·  no actionable items';
    BuildStatusLabel.Caption := Summary;
  End;

Begin
  If Assigned(BuildStatusLabel) Then
    BuildStatusLabel.Caption := '';
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
  BuildTodoList.Items.BeginUpdate;
  Try
    BuildTodoList.Items.Clear;
    If Assigned(BuildSections) Then
      BuildSections.Clear;
    If PlanRel = '' Then
      Begin
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
        NotStarted := 0;
        InProgress := 0;
        Complete := 0;
        ShowPlanCounts;
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
    ShowPlanCounts;
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
  { The status label is the plan count line. Selection and agent notes stay on the footer. }
  StatusFooter.SetRightText(MessageText);
  WorkflowLogger.Info('ProjectAssistant', 'Build work: ' + MessageText);
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
            StopRunPlan(Note);
        End;
      Exit;
    End;
  If WorkingRootHasGitRepository(ProjectAssistantRoot) Then
    Begin
      Note := Note + ' This working root is a Git repository, so the item stays in progress until a commit contains the completion.';
      SetBuildStatusFeedback(Note);
      If FPlanAgentRunning Then
        StopRunPlan(Note);
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

Function TProjectAssistantForm.BuildWorkPrompt(Const PlanRel, SectionTitle, StatusText,
  SectionBody, ParentTitle: String; ContinueSameItem: Boolean): String;
Const MaxBodyChars = 6000;
Var Body, ToolInstructions, Heading: String;
Begin
  Body := Trim(SectionBody);
  If Length(Body) > MaxBodyChars Then
    Body := Copy(Body, 1, MaxBodyChars) + LineEnding + LineEnding +
      '… *(section truncated for the prompt; open the plan file for the full text.)*';
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

Procedure TProjectAssistantForm.StopRunPlan(Const Reason: String);
Begin
  If Not FPlanAgentRunning Then
    Exit;
  FPlanAgentRunning := False;
  SetAssistantPlanViewerQuiet(False);
  Application.RemoveAsyncCalls(Self);
  SetBuildStatusFeedback('Plan agent stopped: ' + Reason);
  SetCurrentSystemNote('**Plan agent stopped:** ' + Reason);
  UpdateStatusFooter;
  WorkflowLogger.Info('ProjectAssistant', 'Plan agent stopped: ' + Reason);
End;

Procedure TProjectAssistantForm.RunPlan;
Var
  Idx: Integer;
Begin
  If FSending Or FPlanAgentRunning Then
    Begin
      MessageDlg('Wait for the current reply to finish before starting Run Plan.',
        mtInformation, [mbOK], 0);
      Exit;
    End;
  If Not RunPlanIsAvailable Then
    Begin
      UpdateWorkActions;
      MessageDlg('Set an active plan first.', mtInformation, [mbOK], 0);
      Exit;
    End;
  { Available from Chat, Inspect, Document, Plan, or Build. Switch before any package work. }
  SelectMode(amBuild);
  RefreshBuildTodos;
  Idx := FindNextIncompleteBuildSection;
  If Idx < 0 Then
    Begin
      MessageDlg('All plan packages are already complete (or none found).', mtInformation, [mbOK], 0);
      Exit;
    End;
  FPlanAgentRunning := True;
  SyncCodexUsageIdle;
  SetAssistantPlanViewerQuiet(True);
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
  BuildWorkOnSelectedPackage;
  If Not FSending Then
    StopRunPlan('could not start first package');
End;

Procedure TProjectAssistantForm.ContinueRunPlan(Data: PtrInt);
Var
  Idx, Pct: Integer;
Begin
  If csDestroying In ComponentState Then Exit;
  If Not FPlanAgentRunning Then
    Exit;
  If FSending Then
    Begin
      Application.QueueAsyncCall(@ContinueRunPlan, 0);
      Exit;
    End;
  If FLastTurnHadError Then
    Begin
      StopRunPlan('last package ended with an error');
      Exit;
    End;
  If FContextLimit > 0 Then
    Begin
      If (Not FUseCodex) And Assigned(AssistantClient) Then
        FContextUsed := AssistantClient.EstimatedPromptTokens;
      Pct := (FContextUsed * 100) Div FContextLimit;
      If Pct >= 95 Then
        Begin
          If AutoCompactAtLimitEnabled Then
            Begin
              { Compact this conversation and keep walking packages. Do not start a new chat. }
              FContextWarnShown := False;
              MaybeWarnHighContextUsage;
              If (Not FUseCodex) And Assigned(AssistantClient) Then
                FContextUsed := AssistantClient.EstimatedPromptTokens;
              Pct := (FContextUsed * 100) Div FContextLimit;
              If Pct >= 95 Then
                Begin
                  StopRunPlan(Format('context usage %d%% after compact — start a New Chat', [Pct]));
                  Exit;
                End;
            End
          Else
            Begin
              MaybeWarnHighContextUsage;
              StopRunPlan(Format('context usage %d%% — start a New Chat', [Pct]));
              Exit;
            End;
        End;
    End;
  If FPlanAgentPackagesDone >= FPlanAgentMaxPackages Then
    Begin
      StopRunPlan(Format('reached max packages (%d)', [FPlanAgentMaxPackages]));
      Exit;
    End;
  RefreshBuildTodos;
  Idx := FindNextIncompleteBuildSection;
  If Idx < 0 Then
    Begin
      StopRunPlan(Format('all packages complete (%d worked this run)',
        [FPlanAgentPackagesDone]));
      Exit;
    End;
  FBuildSelectedIndex := Idx;
  If Assigned(BuildTodoList) And (Idx < BuildTodoList.Items.Count) Then
    BuildTodoList.ItemIndex := Idx;
  SetBuildStatusFeedback(Format('Plan agent: package %d…', [FPlanAgentPackagesDone + 1]));
  BuildWorkOnSelectedPackage;
  If Not FSending Then
    StopRunPlan('failed to start next package');
End;

Procedure TProjectAssistantForm.RunPlanActionExecute(Sender: TObject);
Begin
  If FPlanAgentRunning Then
    Begin
      If MessageDlg('Stop the plan agent after the current reply finishes?',
        mtConfirmation, [mbYes, mbNo], 0) = mrYes Then
        StopRunPlan('stopped by user');
      Exit;
    End;
  RunPlan;
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
  Line, Preview: String;
  SelectIdx: Integer;
Begin
  If Not Assigned(ConversationList) Or Not Assigned(ProjectAssistantConversation) Then
    Exit;
  EnsureConversationStore;
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
        ConversationList.Items.AddObject(Line, TObject(PtrUInt(Entry.TurnIndex + 1)));
        If Entry.TurnIndex = KeepTurnIndex Then
          SelectIdx := ConversationList.Items.Count - 1;
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
        ConversationList.Items.AddObject(Line, TObject(PtrUInt(LiveConversationMarker + 1)));
        If (KeepTurnIndex = LiveConversationMarker) Or FViewingLive Then
          SelectIdx := ConversationList.Items.Count - 1;
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
Begin
  Result := 'Conversation ' + FormatDateTime('yyyymmdd"-"hhnnss', Now) + '.md';
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
  StatusFooter.SetRightActivityText(FormatElapsedStatus(Phase), Phase);
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
Var
  Connections: TAssistantConnections;
  Item: TAssistantConnection;
  PreviousId: String;
Begin
  PreviousId := FActiveConnectionId;
  Try
    FUseCodex := False;
    FUseClaude := False;
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
    If Not Assigned(LazarusIDE) Then Exit;
    Connections := TAssistantConnections.Create(LazarusIDE.GetPrimaryConfigPath);
    Try
      Connections.Load; Item := Connections.Active;
      FUseCodex := Assigned(Item) And (Item.Backend = 'codex');
      FUseClaude := Assigned(Item) And (Item.Backend = 'claude');
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
        End;
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
        FUseClaude := False;
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
        WorkflowLogger.Error('PluginBoundary', 'TProjectAssistantForm.LoadConnectionSettings: ' + E.Message);
      End;
  End;
  If FActiveConnectionId <> PreviousId Then
    NoteAccountConnectionChanged
  Else
    SyncCodexUsageIdle;
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

Function CodexDeveloperInstructions(Mode: TAssistantMode): String;
Var
  Names: TStringList;
  Root, PlanRel: String;
Begin
  Result := '';
  Names := TStringList.Create;
  Try
    If Assigned(AssistantChatConfig) Then
      AssistantChatConfig.CollectSkillsForMode(AssistantModeToStr(Mode), Names);
    Root := ProjectRootPath;
    If Assigned(ProjectAssistantConversation) And (ProjectAssistantConversation.ProjectRoot <> '') Then
      Root := ProjectAssistantConversation.ProjectRoot;
    PlanRel := GetActivePlanRelativePath;
    If Assigned(WorkflowAssistantHarness) Then
      Result := WorkflowAssistantHarness.BuildSystemPrompt(Mode, Names, Root, PlanRel);
  Finally
    Names.Free;
  End;
End;

Function TProjectAssistantForm.StartCodexReply(Const DisplayText, ApiText: String): Boolean;
Var
  Prompt, Recap, SubmitText, ToolsJson, Instructions: String;
  I: Integer;
  Turn: TConversationTurn;
  WithContext: Boolean;
Begin
  Result := False;
  If (FCodexRuntime = '') Or (FCodexModel = '') Then
    Begin
      SettingsActionExecute(Nil);
      If Not FUseCodex Then Exit;
      If (FCodexRuntime = '') Or (FCodexModel = '') Then Exit;
    End;
  If Not Assigned(FCodexWorkspace) Then FCodexWorkspace := TAssistantIDEWorkspace.Create;
  If Not Assigned(FCodexBroker) Then FCodexBroker := TAssistantToolBroker.Create(FCodexWorkspace);
  FCodexIdentity := FCodexWorkspace.Identity;
  { Turns use ApproveToolIfNeeded. Do not hook the lazarus_* review dialog. }
  FCodexBroker.OnApproval := Nil;
  RefreshFromConfig;
  If Not FModeLocked Then LockModeForSend;
  Case ActiveMode Of
    amChat: FCodexBroker.BeginRun(awsNone);
    amBuild: FCodexBroker.BeginRun(awsProject);
    amDocument: FCodexBroker.BeginRun(awsMarkdown);
    amPlan: FCodexBroker.BeginRun(awsMarkdown);
  Else FCodexBroker.BeginRun(awsReadOnly); End;
  ShowChatSurfaceKeepMode;
  { Same user text as SubmitUserTextEx. The harness prompt owns the mode essay, including chat's no-tools sentence.
    Pictures are refused by ComposerAttachAllowed before this call. Do not record image refs. }
  SubmitText := BuildSubmitApiText(ApiText, WithContext);
  If Assigned(AssistantClient) Then
    AssistantClient.AddMessage(amrUser, SubmitText);
  Recap := '';
  If Assigned(ProjectAssistantConversation) Then
    For I := ProjectAssistantConversation.TurnCount - 1 DownTo 0 Do
      Begin
        If Length(Recap) >= 24000 Then Break;
        If ProjectAssistantConversation.GetTurn(I, Turn) And (Turn.Model = FModelName) Then
          Recap := 'User: ' + Copy(Turn.Prompt, 1, 4000) + LineEnding +
            'Assistant: ' + Copy(Turn.Response, 1, 8000) + LineEnding + Recap;
      End;
  { Ephemeral threads have no message array. Recap is transport history, not an instruction essay. }
  Prompt := SubmitText;
  If Recap <> '' Then
    Prompt := 'Previous conversation (bounded recap):' + LineEnding + Recap + LineEnding + LineEnding + SubmitText;
  SetCurrentUserDisplay(DisplayText, WithContext);
  FLiveUser := FDisplayUser; FLiveContent := ''; FLiveThinking := '';
  FAssistantContent := ''; FAssistantThinking := '';
  AppendMessage('user', FDisplayUser);
  FContextUsed := Length(Prompt) Div 4;
  SetSending(True);
  BeginAssistantReply;
  Try
    ToolsJson := BuildAssistantToolsJsonForMode(ActiveMode);
    Instructions := CodexDeveloperInstructions(ActiveMode);
    FCodexRun := TAssistantCodexRun.Create(FCodexRuntime, FCodexProfile, FCodexModel,
      Prompt, ToolsJson, FCodexBroker.RunId, 600000, FCodexProfile, FCodexEffort, Instructions, ActiveMode);
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
  ToolText, EvidenceError, Phase: String; OK, Serviced, ToolPending: Boolean; Block: TTraceBlock; Run: TAssistantCodexRun;

  Function PhaseForSnapshot(Const RunSnapshot: TCodexRunSnapshot; PendingTool: Boolean): String;
  Begin
    { Same right-hand phases as the Grok stream, for every backend. }
    If PendingTool Then
      Result := 'Running tools…'
    Else If RunSnapshot.State In [crsConnecting, crsReady, crsStartingThread, crsStartingTurn] Then
      Result := 'Waiting for model…'
    Else If RunSnapshot.Content <> '' Then
      Result := 'Streaming…'
    Else If RunSnapshot.Thinking <> '' Then
      Result := 'Thinking…'
    Else
      Result := 'Waiting for first token…';
  End;

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
    ToolPending := FCodexRun.HasPendingTool;
    If ToolPending And FSending Then
      Begin
        SetStreamPhase('Running tools…');
        If Assigned(StatusFooter) Then
          StatusFooter.Update;
      End;
    Serviced := Run.ServiceOneTool(Tool, ToolText, OK);
    If FCodexRun <> Run Then Exit; { cancelled/replaced during an IDE callback }
    If Serviced Then
      Begin
        { Use the text captured at the tool request, even if the worker advanced
          between the timer snapshot and the IDE handoff. }
        ApplyAssistantSnapshots(Tool.ContentBefore, Tool.ThinkingBefore);
        ApplyLiveThinkingAndAnswer;
        Block := FTrace.AddTool(Tool.CallId, Tool.Tool, Tool.Arguments);
        Block.Body := ToolText; Block.Ok := OK; Block.Running := False;
        If OK And (SameText(Tool.Tool, 'write_markdown') Or SameText(Tool.Tool, 'update_markdown')) Then
          FPlanWriteThisTurn := True;
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
        If FSending Then
          Begin
            Phase := PhaseForSnapshot(Snapshot, ToolPending And Not Serviced);
            SetStreamPhase(Phase);
          End;
        If FViewingLive And Assigned(FTraceView) And Assigned(FTrace) Then
          FTraceView.RefreshElapsed(FTrace);
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
      StatusFooter.SetRightActivityText(FormatElapsedStatus(FStatusPhase), FStatusPhase);
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

Procedure TProjectAssistantForm.ApplyDisplayPreferences;
Var
  ShowThinking, ShowTools: Boolean;
Begin
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

Type
  TAccountUsageWorker = Class(TThread)
    Slot: TAccountUsageSlot;
    Connection: TAssistantConnection;
    RuntimePath, ProfileDir: String;
    Procedure Execute; Override;
  End;

Procedure TAccountUsageWorker.Execute;
Var
  Item: TAccountUsageSnapshot;
  ErrorText: String;
  QueryOk: Boolean;
Begin
  ErrorText := '';
  QueryOk := False;
  ClearAccountUsageSnapshot(Item);
  Try
    Try
      If Slot.IsClosed Then
        Exit;
      QueryOk := QueryAccountUsage(Connection, RuntimePath, ProfileDir, Item, ErrorText);
      If CodexAccountUsageCancelled Or Slot.IsClosed Then
        Exit;
      If Slot.StoreResult(Item, QueryOk) Then
        WorkflowLogger.Warning('ProjectAssistant', 'Account usage query failed.');
    Except
      On E: Exception Do
        WorkflowLogger.Warning('ProjectAssistant', 'Account usage query failed.');
    End;
  Finally
    Connection.Free;
    Slot.Release;
  End;
End;

Procedure TProjectAssistantForm.RefreshCentreStatus;
Var
  CentreText, HintText: String;
Begin
  If Not Assigned(StatusFooter) Then
    Exit;
  CentreText := FContextStatusText;
  If FPlanStatusCaption <> '' Then
    Begin
      If CentreText <> '' Then
        CentreText := CentreText + ' · ';
      CentreText := CentreText + FPlanStatusCaption;
    End;
  { The context line is the status text already on screen. The separate usage chip stays hidden so the figure is not shown twice. }
  StatusFooter.SetCentreText(CentreText);
  StatusFooter.SetUsageText('');
  StatusFooter.SetUsageHint('');
  HintText := FContextStatusHint;
  If FPlanStatusHint <> '' Then
    Begin
      If HintText <> '' Then
        HintText := HintText + LineEnding;
      HintText := HintText + FPlanStatusHint;
    End;
  StatusFooter.SetCentreHint(HintText);
End;

Procedure TProjectAssistantForm.ApplyAccountUsageLabel;
Var
  SlotItem, Item: TAccountUsageSnapshot;
Begin
  If Not Assigned(StatusFooter) Then
    Exit;
  ClearAccountUsageSnapshot(SlotItem);
  If Assigned(FAccountUsageSlot) Then
    SlotItem := FAccountUsageSlot.ReadSnapshot;
  Item := AccountUsageForFooter(FActiveConnectionId, SlotItem);
  If AccountUsageApplies(Item, FActiveConnectionId) Then
    PublishAccountUsageSnapshot(Item);
  FPlanStatusCaption := AccountUsageCaption(Item, FActiveConnectionId);
  FPlanStatusHint := AccountUsageHint(Item, FActiveConnectionId);
  RefreshCentreStatus;
End;

Procedure TProjectAssistantForm.SyncCodexUsageIdle;
Begin
  SetCodexAccountUsageIdle(FUseCodex And (Not FSending) And (Not FPlanAgentRunning) And (Not FReviewInProgress));
End;

Procedure TProjectAssistantForm.NoteAccountConnectionChanged;
Begin
  CancelCodexAccountUsage;
  SyncCodexUsageIdle;
  If Assigned(FAccountUsageSlot) Then
    FAccountUsageSlot.SetActive(FActiveConnectionId);
  FAccountUsageAttemptId := '';
  FAccountUsageAttemptAt := 0;
  FAccountUsageWanted := AccountUsageRegistered(FActiveBackend);
  ApplyAccountUsageLabel;
End;

Procedure TProjectAssistantForm.StartAccountUsageWorker;
Var
  Worker: TAccountUsageWorker;
  Copy: TAssistantConnection;
Begin
  If (Not Assigned(FAccountUsageSlot)) Or FAccountUsageSlot.IsClosed Then
    Exit;
  If Assigned(FAccountUsageWorker) And (Not FAccountUsageWorker.Finished) Then
    Exit;
  If Assigned(FAccountUsageWorker) Then
    Begin
      FAccountUsageWorker.WaitFor;
      FreeAndNil(FAccountUsageWorker);
    End;
  If (FActiveConnectionId = '') Or (Not AccountUsageRegistered(FActiveBackend)) Then
    Exit;
  SyncCodexUsageIdle;
  If FUseCodex And ((FSending) Or FPlanAgentRunning Or FReviewInProgress) Then
    Exit;
  Copy := TAssistantConnection.Create;
  Copy.Id := FActiveConnectionId;
  Copy.Backend := FActiveBackend;
  Copy.Model := FActiveModel;
  Copy.ApiBase := FAccountApiBase;
  Copy.KeySource := FAccountKeySource;
  Copy.KeyEnv := FAccountKeyEnv;
  Copy.KeyValue := FAccountKeyValue;
  { Grok Build reads the weekly pool with this same OAuth token. Do not log it. }
  If FActiveBackend = 'grok' Then
    Begin
      Copy.KeySource := 'stored';
      Copy.KeyValue := '';
      If Assigned(GrokOAuthClient) Then
        Copy.KeyValue := GrokOAuthClient.GetValidAccessToken;
    End;
  Copy.Preset := FAccountPreset;
  Copy.WireApi := FAccountWire;
  Worker := TAccountUsageWorker.Create(True);
  Worker.FreeOnTerminate := False;
  Worker.Slot := FAccountUsageSlot;
  Worker.Connection := Copy;
  Worker.RuntimePath := FCodexRuntime;
  Worker.ProfileDir := FCodexProfile;
  FAccountUsageSlot.Retain;
  FAccountUsageWorker := Worker;
  FAccountUsageWanted := False;
  FAccountUsageAttemptId := FActiveConnectionId;
  FAccountUsageAttemptAt := Now;
  Worker.Start;
End;

Procedure TProjectAssistantForm.AccountUsageTimerTimer(Sender: TObject);
Var
  Due: Boolean;
Begin
  Try
    If csDestroying In ComponentState Then
      Exit;
    ApplyAccountUsageLabel;
    SyncCodexUsageIdle;
    If Not Assigned(FAccountUsageSlot) Or FAccountUsageSlot.IsClosed Then
      Exit;
    If Assigned(FAccountUsageWorker) And (Not FAccountUsageWorker.Finished) Then
      Exit;
    If (FActiveConnectionId = '') Or (Not AccountUsageRegistered(FActiveBackend)) Then
      Exit;
    If FUseCodex And ((FSending) Or FPlanAgentRunning Or FReviewInProgress) Then
      Exit;
    Due := FAccountUsageWanted;
    If Not Due Then
      Due := Showing And ((FAccountUsageAttemptId <> FActiveConnectionId) Or
        ((Now - FAccountUsageAttemptAt) >= EncodeTime(0, 3, 0, 0)));
    If Not Due Then
      Exit;
    StartAccountUsageWorker;
  Except
    On E: Exception Do
      WorkflowLogger.Warning('ProjectAssistant', 'Account usage refresh failed.');
  End;
End;

Procedure TProjectAssistantForm.ReleaseAccountUsageRefresh;
Begin
  If Assigned(FAccountUsageTimer) Then
    Begin
      FAccountUsageTimer.Enabled := False;
      FAccountUsageTimer.OnTimer := Nil;
      FreeAndNil(FAccountUsageTimer);
    End;
  CancelCodexAccountUsage;
  If Assigned(FAccountUsageSlot) Then
    FAccountUsageSlot.Close;
  If Assigned(FAccountUsageWorker) Then
    Begin
      ReapCodexWorker(FAccountUsageWorker);
      FAccountUsageWorker := Nil;
    End;
  If Assigned(FAccountUsageSlot) Then
    Begin
      FAccountUsageSlot.Release;
      FAccountUsageSlot := Nil;
    End;
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
  Else If (FUseCodex And (FCodexRuntime <> '') And (FCodexModel <> '')) Or
    ((Not FUseCodex) And Assigned(AssistantChatConfig) And AssistantChatConfig.IsSignedIn) Then
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
  ApplyModelStatus;
  StatusFooter.SetModelText(LeftText);
  FContextStatusText := CentreText;
  ApplyAccountUsageLabel;
  If FSending Then
    StatusFooter.SetRightActivityText(StatusText, FStatusPhase)
  Else
    StatusFooter.SetRightText(StatusText);
  StatusFooter.SetLeftHint('');
  StatusFooter.SetModelHint('Click to change model, thinking level, or approval');
  If (Not FUseCodex) And Assigned(AssistantClient) And (Not AssistantClient.ImagesAttachAllowed(BlockReason)) And
    (BlockReason <> '') Then
    StatusFooter.SetModelHint('Click to change model, thinking level, or approval. ' + BlockReason);
  FContextStatusHint := Format('About %d of %d tokens. Click for a breakdown.', [FContextUsed, FContextLimit]);
  StatusFooter.SetRightHint('Click for session info');
  If FUseCodex Then
    Begin
      StatusFooter.SetModelHint('Click for ChatGPT connection and model. ' + AssistantCodexImageAttachReason);
      If Assigned(SendAction) Then SendAction.Hint := AssistantCodexImageAttachReason;
      RefreshAttachAction;
      FContextStatusHint := 'Estimated context; provider allowance is checked on each request';
    End
  Else
    Begin
      If Assigned(SendAction) Then SendAction.Hint := '';
      RefreshAttachAction;
    End;
  RefreshCentreStatus;
  ApplySkillStatus;
  If (Not FUseCodex) And (Not FSending) And (Pct >= 95) Then
    MaybeWarnHighContextUsage;
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
  If Pct < 95 Then
    Exit;
  FContextWarnShown := True;
  { The saved flag does not start a new chat. Compact only when this connection can. }
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
  SetCurrentSystemNote(
    Format('**Context usage is high (%d%%).** Start a **New Chat** before continuing long Build/Plan work ' +
      'so the model stays within its token limit.',
      [Pct]));
  MessageDlg(
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
  If (Not FUseCodex) And IsSending And (Not FSending) Then
    AssistantBeginQuietIdeSession
  Else If (Not FUseCodex) And (Not IsSending) And FSending Then
    AssistantEndQuietIdeSession;
  FSending := IsSending;
  If WasSending And (Not IsSending) Then
    FAccountUsageWanted := AccountUsageRegistered(FActiveBackend);
  SyncCodexUsageIdle;
  If Assigned(TargetCombo) Then TargetCombo.Enabled := Not IsSending;
  If Assigned(TargetBrowseButton) Then TargetBrowseButton.Enabled := Not IsSending;
  If Assigned(ActivePlanCombo) Then ActivePlanCombo.Enabled := Not IsSending;
  If Assigned(ActivePlanBrowseButton) Then ActivePlanBrowseButton.Enabled := Not IsSending;
  If Assigned(RemovePlanAction) Then
    RemovePlanAction.Enabled := (Not IsSending) And (GetActivePlanRelativePath <> '');
  If Assigned(OpenPlanSheetAction) Then
    OpenPlanSheetAction.Enabled := GetActivePlanRelativePath <> '';
  If IsSending Then
    Begin
      FPlanWriteThisTurn := False;
      ResetAssistantGitTurn;
      ResetAssistantPlanTurn;
    End;
  If Not IsSending Then
    FReviewInProgress := False;
  SendAction.Enabled := True;
  If IsSending Then
    SendAction.Caption := 'Steer'
  Else
    SendAction.Caption := 'Send';
  StopAction.Enabled := IsSending;
  NewConversationAction.Enabled := Not IsSending;
  If Assigned(NewPlanAction) Then
    NewPlanAction.Enabled := Not IsSending;
  If Assigned(RunPlanAction) Then
    RunPlanAction.Enabled := RunPlanIsAvailable;
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
  If (Not FSending) And FReloadConnectionAfterSend Then
    Begin
      FReloadConnectionAfterSend := False;
      ReloadActiveConnection;
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
  ChatHost.BorderSpacing.Around := 0;
  ChatHost.Color := clWindow;
  ChatHost.ParentColor := False;
  ChatHost.ParentBackground := False;
  FTraceView := TAssistantTraceView.Create(Self);
  FTraceView.Parent := ChatHost;
  FTraceView.Align := alClient;
  FTraceView.BorderSpacing.Around := 0;
  FTraceView.ShowThinking := FShowThinking;
  FTraceView.ShowToolUse := FShowToolUse;
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
  InputUndoItem := TMenuItem.Create(InputPopup);
  InputUndoItem.Caption := 'Undo';
  InputUndoItem.ShortCut := ShortCut(Ord('Z'), [ssCtrl]);
  InputUndoItem.OnClick := @InputUndoClick;
  InputPopup.Items.Add(InputUndoItem);
  InputRedoItem := TMenuItem.Create(InputPopup);
  InputRedoItem.Caption := 'Redo';
  InputRedoItem.ShortCut := ShortCut(Ord('Z'), [ssCtrl, ssShift]);
  InputRedoItem.OnClick := @InputRedoClick;
  InputPopup.Items.Add(InputRedoItem);
  Sep := TMenuItem.Create(InputPopup);
  Sep.Caption := '-';
  InputPopup.Items.Add(Sep);
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
  InputAttachImageItem := TMenuItem.Create(InputPopup);
  InputAttachImageItem.Action := AttachImageAction;
  InputPopup.Items.Add(InputAttachImageItem);
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
  UpdateInputUndoItems;
End;

Procedure TProjectAssistantForm.UpdateInputUndoItems;
Begin
  If Assigned(InputUndoItem) Then
    InputUndoItem.Enabled := Assigned(InputMemo) And InputMemo.CanUndo;
  If Assigned(InputRedoItem) Then
    InputRedoItem.Enabled := Assigned(InputMemo) And InputMemo.CanRedo;
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
  RefreshAttachAction;
  If Assigned(InputSelectAllItem) Then
    InputSelectAllItem.Enabled := Assigned(InputMemo) And (InputMemo.GetTextLen > 0);
  UpdateInputUndoItems;
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
End;

Procedure TProjectAssistantForm.PlaceComposerChildren;
Var
  Y, BandWidth: Integer;
Begin
  { Align stays alNone. LCL sorts alBottom siblings by the current bottom edge,
    so growing one of them docks the buttons under the status bar. }
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
      BottomBar.SetBounds(0, 0, BandWidth, Y);
    End;
End;

Procedure TProjectAssistantForm.PlacePromptChildren;
Var
  Y, StripHeight, BandWidth: Integer;
Begin
  { The memo and its pictures stay in the left column. Align is not used here:
    showing the picture strip must not push the memo out of the column. }
  If Not Assigned(PromptHost) Then Exit;
  BandWidth := PromptHost.ClientWidth;
  If BandWidth < 1 Then BandWidth := PromptHost.Width;
  Y := PromptHost.ClientHeight;
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
  StackHeight, PromptHeight: Integer;
Begin
  If Not Assigned(ComposerStack) Or FComposerLayoutLock Then Exit;
  If csDestroying In ComponentState Then Exit;
  FComposerLayoutLock := True;
  DisableAlign;
  Try
    If FInputHeight < Scale96ToForm(48) Then FInputHeight := Scale96ToForm(75);
    If Assigned(AttachmentStrip) And AttachmentStrip.Visible Then
      AttachmentStrip.Height := AttachmentStripHeight;
    StackHeight := ComposerChromeHeight;
    ComposerStack.Height := StackHeight;
    PlaceComposerChildren;
    If Assigned(PromptHost) Then
      Begin
        PromptHeight := FInputHeight;
        If Assigned(AttachmentStrip) And AttachmentStrip.Visible Then
          Inc(PromptHeight, AttachmentStripHeight);
        PromptHost.Height := PromptHeight;
        PlacePromptChildren;
      End;
  Finally
    EnableAlign;
    FComposerLayoutLock := False;
  End;
End;

Procedure TProjectAssistantForm.StatusFooterResize(Sender: TObject);
Begin
  If (Sender <> StatusFooter) Or FComposerLayoutLock Or (csLoading In ComponentState) Or
    (csDestroying In ComponentState) Then
    Exit;
  { Growing the footer must grow the stack before children are placed, preserving
    the command row's height when the inherited font or display scale changes. }
  LayoutComposer;
End;

Procedure TProjectAssistantForm.ComposerStackResize(Sender: TObject);
Begin
  If FComposerLayoutLock Or (csLoading In ComponentState) Or (csDestroying In ComponentState) Then Exit;
  FComposerLayoutLock := True;
  Try
    PlaceComposerChildren;
  Finally
    FComposerLayoutLock := False;
  End;
End;

Procedure TProjectAssistantForm.PromptHostResize(Sender: TObject);
Var
  Available, Minimum, Strip: Integer;
Begin
  If FComposerLayoutLock Or (csLoading In ComponentState) Or (csDestroying In ComponentState) Then Exit;
  If Not Assigned(PromptHost) Then Exit;
  Minimum := Scale96ToForm(48);
  Strip := 0;
  If Assigned(AttachmentStrip) And AttachmentStrip.Visible Then
    Strip := AttachmentStripHeight;
  Available := PromptHost.ClientHeight - Strip;
  If Available < Minimum Then Available := Minimum;
  FInputHeight := Available;
  FComposerLayoutLock := True;
  Try
    PlacePromptChildren;
  Finally
    FComposerLayoutLock := False;
  End;
End;

Procedure TProjectAssistantForm.ApplyInputPanelHeight;
Begin
  If Not Assigned(InputPanel) Then Exit;
  FInputHeight := Scale96ToForm(75);
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

Procedure TProjectAssistantForm.InputUndoClick(Sender: TObject);
Begin
  If Assigned(InputMemo) Then
    Begin
      InputMemo.NoteMenuShortcut;
      InputMemo.Undo;
    End;
End;

Procedure TProjectAssistantForm.InputRedoClick(Sender: TObject);
Begin
  If Assigned(InputMemo) Then
    Begin
      InputMemo.NoteMenuShortcut;
      InputMemo.Redo;
    End;
End;

Procedure TProjectAssistantForm.InputMemoChange(Sender: TObject);
Begin
  UpdateInputUndoItems;
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

Procedure TProjectAssistantForm.RecordCompletedUsage;
Var
  Root, ErrorText: String;
  InputTokens, OutputTokens, ReasoningTokens: Integer;
  HasReasoning, HasUsage: Boolean;
  Item: TAssistantUsageRecord;
Begin
  { Codex has no usage parser. A Claude turn is not this stream. }
  If FUseCodex Or FUseClaude Or (FActiveConnectionId = '') Or (Not Assigned(AssistantClient)) Then
    Exit;
  HasUsage := AssistantClient.TakeReportedUsage(InputTokens, OutputTokens, ReasoningTokens, HasReasoning);
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

Procedure TProjectAssistantForm.FinishAssistantReply(Const ErrorText: String);
Var
  ResolvedError, TraceNote, Settlement, AskedNote: String;
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
  { Record from live buffers so a browsed-away pane still saves the real answer. }
  RecordCurrentTurn(ResolvedError);
  If ResolvedError = '' Then
    RecordCompletedUsage;
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
      RefreshActivePlanChoices(Nil);
      RefreshBuildTodos;
      UpdateWorkActions;
    End
  Else If ActiveMode = amBuild Then
    RefreshBuildTodos;
  If FPlanAgentRunning Then
    Begin
      If FLastTurnHadError Then
        Begin
          If (Pos('host name resolution', LowerCase(ResolvedError)) > 0) Or
            (Pos('network', LowerCase(ResolvedError)) > 0) Or
            (Pos('timed out', LowerCase(ResolvedError)) > 0) Then
            StopRunPlan(
              'network error. Check connectivity, then click ' +
              '**Run Plan** again to resume remaining packages. ' + ResolvedError)
          Else
            StopRunPlan('error: ' + ResolvedError);
        End
      Else
        Begin
          Inc(FPlanAgentPackagesDone);
          Application.QueueAsyncCall(@ContinueRunPlan, 0);
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
  If FPlanAgentRunning Then
    StopRunPlan('stream cancelled by user');
  WorkflowLogger.Info('ProjectAssistant', 'Stream cancelled by user');
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
      Result := AssistantPlanDirective(PlanRel) + LineEnding + LineEnding + ModelText;
    End
  Else If ActiveMode = amDocument Then
    Result := AssistantDocumentDirective(DocumentPathForTurn) + LineEnding + LineEnding + ModelText;
  { Chat keeps the harness no-tools sentence. Do not paraphrase it into the user text. }
  WithContext := (ActiveMode <> amChat) And Assigned(AssistantChatConfig) And
    AssistantChatConfig.IncludeIDEContext;
  If WithContext Then
    Begin
      { After several turns, full editor dumps explode the prompt; use light context. }
      If Assigned(AssistantClient) And (AssistantClient.MessageCount >= 8) Then
        ContextBlock := BuildIDEContextBlockLight
      Else
        ContextBlock := BuildIDEContextBlock;
      Result := Result + LineEnding + LineEnding + ContextBlock;
    End;
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
  SetLength(Refs, 0);
  ParseAssistantImageRefs(FComposerImagesJson, Refs);
  Refs := LimitAssistantImageRefs(Refs);
  If (Trim(ApiText) = '') And (Length(Refs) = 0) Then
    Exit;
  If FSending Then
    Exit;
  If AutoSend And FUseClaude Then
    Begin
      { No Claude prompt and no Claude process. Do not fall through to another backend. }
      MessageDlg('The Claude turn is not wired.', mtInformation, [mbOK], 0);
      Exit;
    End;
  If AutoSend And (Not FUseCodex) Then
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
  { One capability check for every backend. Codex stays unable to attach pictures. }
  If AutoSend And (Length(Refs) > 0) And (Not ComposerAttachAllowed(BlockReason)) Then
    Begin
      If BlockReason = '' Then
        BlockReason := 'This model lists no image input. Attach is disabled.';
      SetCurrentSystemNote(BlockReason);
      MessageDlg(BlockReason, mtInformation, [mbOK], 0);
      If Assigned(InputMemo) Then
        InputMemo.Text := DisplayText;
      Exit;
    End;
  If AutoSend And FUseCodex Then
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
  Skills := ListDiscoveredSkills(Root);
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
  If Not Assigned(AssistantChatConfig) Then
    Exit;
  Case Item.Tag Of
    FooterTagSkill:
      ToggleSkillForMode(Item.Hint);
    FooterTagSettings:
      SettingsActionExecute(Sender);
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
  If FUseClaude Then
    SkillName := 'Not wired';
  If Assigned(AssistantChatConfig) And AssistantChatConfig.IsSignedIn Then
    SignedIn := 'yes';
  Body :=
    'Project Assistant session' + LineEnding + LineEnding +
    'Mode: ' + ModeChipCaption(ActiveMode) + LineEnding +
    'Model: ' + FModelName + LineEnding;
  If Assigned(AssistantChatConfig) Then
    Body := Body +
      'Thinking: ' + ThinkingLevelCaption(AssistantChatConfig.GetThinkingLevel) + LineEnding +
      'Approval: ' + ApprovalModeCaption(AssistantChatConfig.GetApprovalMode) + LineEnding;
  Body := Body +
    SkillName + LineEnding +
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

Procedure TProjectAssistantForm.SkillsPickerActionExecute(Sender: TObject);
Var
  Host: TControl;
Begin
  If FUseClaude Then
    Begin
      MessageDlg('The Claude turn is not wired.', mtInformation, [mbOK], 0);
      Exit;
    End;
  EnsureFooterMenu(FFooterMenu);
  FillSkillFooterMenu;
  AddFooterItem(FFooterMenu, '-', 0, '', False, False, Nil);
  AddFooterItem(FFooterMenu, 'Settings…', FooterTagSettings, '', False, False, @FooterMenuClick);
  Host := StatusFooter.SkillLabel;
  If Not Assigned(Host) Then
    Host := StatusFooter;
  PopupUnderControl(Host, FFooterMenu);
End;

Procedure TProjectAssistantForm.OpenPlanActionExecute(Sender: TObject);
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

Procedure TProjectAssistantForm.RemovePlanActionExecute(Sender: TObject);
Var
  Rel, Err: String;
Begin
  If FSending Or FReviewInProgress Then
    Exit;
  Rel := GetActivePlanRelativePath;
  If Rel = '' Then
    Begin
      MessageDlg('Select a plan to remove from the list.', mtInformation, [mbOK], 0);
      Exit;
    End;
  If Not RemoveAvailableAssistantPlan(Rel, Err) Then
    Begin
      MessageDlg(Err, mtError, [mbOK], 0);
      Exit;
    End;
  SetActivePlanRelativePath('');
  PersistShellConfig;
  RefreshActivePlanChoices(Nil);
  RefreshBuildTodos;
  UpdateWorkActions;
  SetBuildStatusFeedback('Removed from the available list. The file was kept.');
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
  If FUseClaude Then
    Begin
      MessageDlg('The Claude turn is not wired.', mtInformation, [mbOK], 0);
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
  If FUseClaude Then
    Begin
      MessageDlg('The Claude turn is not wired.', mtInformation, [mbOK], 0);
      Exit;
    End;
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
  SyncCodexUsageIdle;
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
    FContextUsed := 0;
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

Procedure TProjectAssistantForm.StartNewChat(KeepPlanAgent: Boolean; UseChatDefault: Boolean);
Begin
  FPlanAgentResumeIndex := -1;
  If FPlanAgentRunning And (Not KeepPlanAgent) Then
    StopRunPlan('new chat');
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
  FContextUsed := 0;
  FContextWarnShown := False;
  FUserCancelled := False;
  FTurnRecorded := False;
  FLastChatPaintTick := 0;
  FSelectedTurnIndex := -1;
  ClearCurrentTurnDisplay;
  If Assigned(AssistantClient) Then
    AssistantClient.ClearHistory;
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
        SetCurrentSystemNote(Format('New conversation started in **%s**. Previous conversation moved to History.',
          [ModeChipCaption(ActiveMode)]));
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
      FContextUsed := 0;
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

End.
