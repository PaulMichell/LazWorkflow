Unit ProjectAssistantForm;

{ Project Assistant main window — shared turn view, mode side panel, status footer (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Contnrs, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Menus, ActnList, Clipbrd, WorkflowEvents, StatusFooterFrame, SpellMemo, CompOptsIntf,
  IDEExternToolIntf, AssistantConversation, AssistantPlan, AssistantEvents, AssistantTrace,
  AssistantTraceView;

Type
  TProjectAssistantForm = Class(TForm, ICompilerFinished, IMarkdownDocumentChanged)
    ActionList: TActionList;
    NewChatAction: TAction;
    SendAction: TAction;
    SendButton: TButton;
    StopAction: TAction;
    ReviewCompileAction: TAction;
    ReviewBuildAction: TAction;
    FixErrorAction: TAction;
    SettingsAction: TAction;
    StopButton: TButton;
    ToggleThinkingAction: TAction;
    ExportHistoryAction: TAction;
    DeleteHistoryAction: TAction;
    ModeBar: TPanel;
    ModeGroup: TRadioGroup;
    ModeBadge: TLabel;
    ClientPanel: TPanel;
    ModeSidePanel: TPanel;
    ModeSplitter: TSplitter;
    ChatSidePanel: TPanel;
    ChatSideLabel: TLabel;
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
    { Code TODO workspace (runtime, left mode panel). }
    CodePanel: TPanel;
    CodeActiveLabel: TLabel;
    CodeTodoList: TListBox;
    CodeRefreshButton: TButton;
    CodeOpenPlanButton: TButton;
    CodeStartButton: TButton;
    CodeDoneButton: TButton;
    CodeResetButton: TButton;
    CodeWorkButton: TButton;
    CodeWorkPlanButton: TButton;
    CodeStatusLabel: TLabel;
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
    InputMemo: TSpellMemo;
    InputPopup: TPopupMenu;
    InputCutItem: TMenuItem;
    InputCopyItem: TMenuItem;
    InputPasteItem: TMenuItem;
    InputSelectAllItem: TMenuItem;
    PromptSplitter: TSplitter;
    Procedure FormCreate(Sender: TObject);
    Procedure FormDestroy(Sender: TObject);
    Procedure ModeGroupClick(Sender: TObject);
    Procedure ConversationSearchChange(Sender: TObject);
    Procedure ConversationListClick(Sender: TObject);
    Procedure ConversationListSelectionChange(Sender: TObject; User: Boolean);
    Procedure HistoryComboChange(Sender: TObject);
    Procedure SendActionExecute(Sender: TObject);
    Procedure StopActionExecute(Sender: TObject);
    Procedure NewChatActionExecute(Sender: TObject);
    Procedure ReviewCompileActionExecute(Sender: TObject);
    Procedure ReviewBuildActionExecute(Sender: TObject);
    Procedure FixErrorActionExecute(Sender: TObject);
    Procedure SettingsActionExecute(Sender: TObject);
    Procedure ToggleThinkingActionExecute(Sender: TObject);
    Procedure ExportHistoryActionExecute(Sender: TObject);
    Procedure DeleteHistoryActionExecute(Sender: TObject);
    Procedure InputPopupPopup(Sender: TObject);
    Procedure InputCutClick(Sender: TObject);
    Procedure InputCopyClick(Sender: TObject);
    Procedure InputPasteClick(Sender: TObject);
    Procedure InputSelectAllClick(Sender: TObject);
    Procedure AutoNewChatCheckClick(Sender: TObject);
  Private
    ElapsedTimer: TTimer;
    ChatView: TControl; { unused; centre is FTraceView }
    Transcript: TStringList; { Session export / legacy; not the main UI surface. }
    FDisplayUser: String; { Current-turn user text shown in the Chat tab. }
    FDisplaySystemNote: String; { Optional system/error note for the current surface. }
    FDisplayDurationMs: Integer; { Stored turn wall time when browsing history. }
    FDisplayThinkingMs: Integer; { Stored thinking time when browsing history. }
    FShowThinking: Boolean;
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
    FStatusPhase: String; { e.g. Thinking… / Streaming… while FSending. }
    FLastChatPaintTick: QWord;
    FTrace: TAssistantTrace;
    FHistoryTrace: TAssistantTrace;
    FTraceView: TAssistantTraceView;
    FRefreshingChat: Boolean;
    FIgnoreConversationListChange: Boolean;
    FThinkingSliceStart: Integer;
    FSessionProjectKey: String; { ProjectInfoFile used for last save/load. }
    FSelectedTurnIndex: Integer; { Conversation list selection; -2 = live in-flight row. }
    HistoryIds: TStringList; { Parallel to HistoryCombo; '' = current conversation. }
    FHistoryUpdating: Boolean;
    FApplyingShellConfig: Boolean; { True while restoring mode tab from config.json. }
    FModeLocked: Boolean; { True while a send freezes the active mode (tools/prompt). }
    FModeSticky: Boolean; { Keep forced Code/Plan mode after send until user changes mode. }
    CodeSections: TObjectList; { of TPlanSection for the Code TODO list (not published). }
    FCodeSelectedIndex: Integer; { Survives button clicks that clear ListBox.ItemIndex. }
    FCodeWorkSectionIndex: Integer; { Plan section for active Work-on-this (-1 = none). }
    FCodeWorkSectionTitle: String;
    FCompileSeqAtSendStart: Integer; { Snapshot of AssistantLastCompileSeq at turn start. }
    FPendingReviewErrorOffer: Boolean; { After Review with errors, offer Fix Error. }
    FReviewErrorCount: Integer;
    FContextWarnShown: Boolean; { One-shot warning / auto-rollover when context ≥ 95%. }
    FAutoRolloverInProgress: Boolean; { Guard re-entry while starting a context New Chat. }
    FPlanAgentRunning: Boolean;
    FPlanAgentPackagesDone: Integer;
    FPlanAgentMaxPackages: Integer;
    FLastTurnHadError: Boolean;
    Procedure UpdateThinkingActionCaption;
    Procedure ClearCurrentTurnDisplay;
    Procedure ResetTraceCards;
    Procedure SetCurrentUserDisplay(Const UserText: String; Const WithIdeContext: Boolean);
    Procedure SetCurrentSystemNote(Const NoteText: String);
    Procedure EnsureConversationStore;
    Procedure RefreshConversationList;
    Procedure RefreshHistoryCombo;
    Procedure RebuildClientFromConversation;
    Procedure ApplyLoadedConversationToUi(Const StatusNote: String);
    Function BuildConversationMarkdownExport: String;
    Function DefaultExportFileName: String;
    Procedure ShowConversationTurn(TurnIndex: Integer);
    Procedure ShowLastConversationTurn;
    Procedure RecordCurrentTurn(Const ErrorText: String);
    Function CurrentStreamDurationMs: Integer;
    Procedure FinishLiveTrace(Const SystemNote: String; DurationMs: Integer);
    Function CurrentModeFromUi: TAssistantMode;
    Procedure SelectMode(Mode: TAssistantMode);
    Procedure SyncModeUi;
    Procedure UpdateModeBadge;
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
    Procedure PlanNewButtonClick(Sender: TObject);
    Procedure PlanOpenButtonClick(Sender: TObject);
    Procedure PlanSetActiveButtonClick(Sender: TObject);
    Procedure PlanRefreshButtonClick(Sender: TObject);
    Procedure PlanOpenDocsButtonClick(Sender: TObject);
    Procedure PlanListDblClick(Sender: TObject);
    Function SelectedPlanRelativePath: String;
    Procedure EnsureCodeTabUi;
    Procedure RefreshCodeTodos;
    Function SelectedCodeSectionIndex: Integer;
    Procedure SetCodeStatusFeedback(Const MessageText: String);
    Procedure SetSelectedCodeSectionStatus(NewStatus: TPlanSectionStatus);
    Procedure ClearCodeWorkTracking;
    Procedure BeginCodeWorkTracking(SectionIndex: Integer; Const SectionTitle: String);
    Procedure TryAutoCompleteCodeWork(Const StreamErrorText: String);
    Procedure PrepareTopErrorAfterReview(ErrorCount: Integer);
    Procedure OfferFixTopErrorAfterReview;
    Procedure CodeRefreshButtonClick(Sender: TObject);
    Procedure CodeOpenPlanButtonClick(Sender: TObject);
    Procedure CodeStartButtonClick(Sender: TObject);
    Procedure CodeDoneButtonClick(Sender: TObject);
    Procedure CodeResetButtonClick(Sender: TObject);
    Procedure CodeWorkButtonClick(Sender: TObject);
    Procedure CodeWorkPlanButtonClick(Sender: TObject);
    Procedure CodeWorkOnSelectedPackage;
    Procedure StartWorkOnPlanAgent;
    Procedure StopWorkOnPlanAgent(Const Reason: String);
    Procedure ContinueWorkOnPlanAgent(Data: PtrInt);
    Function FindNextIncompleteCodeSection: Integer;
    Function BuildCodeWorkPrompt(Const PlanRel, SectionTitle, StatusText, SectionBody: String): String;
    Procedure MaybeWarnHighContextUsage;
    Function AutoNewChatAtLimitEnabled: Boolean;
    Procedure SyncAutoNewChatCheckFromConfig;
    Procedure CodeTodoListDblClick(Sender: TObject);
    Procedure CodeTodoListClick(Sender: TObject);
    Procedure CodeTodoListSelectionChange(Sender: TObject; User: Boolean);
    Function ConversationListTurnIndex(ListIndex: Integer): Integer;
    Procedure UpdateStatusFooter;
    Function FormatElapsedStatus(Const Phase: String): String;
    Procedure SetStreamPhase(Const Phase: String);
    Procedure SetSending(IsSending: Boolean);
    Procedure ElapsedTimerTimer(Sender: TObject);
    Procedure EnsureChatView;
    Procedure RebuildTraceFromFields;
    Procedure ApplyLiveThinkingAndAnswer;
    Procedure HandleTraceEvent(Const Event: TAssistantEvent);
    Procedure EnsureInputPopup;
    Procedure ScrollChatToEnd;
    Procedure ScrollChatToTop;
    Procedure RefreshChatDisplay(Force: Boolean; ScrollToBottom: Boolean = True);
    Procedure SetBusyCursor(IsBusy: Boolean);
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
    Procedure SubmitUserText(Const UserText: String; AutoSend: Boolean);
    { DisplayText is shown/stored; ApiText is what the model receives (may include extra directives). }
    Procedure SubmitUserTextEx(Const DisplayText, ApiText: String; AutoSend: Boolean);
    { DisplayLabel is shown/stored; ApiText is sent to the model. No IDE context; tools off. }
    Procedure SubmitReviewRequest(Const DisplayLabel, ApiText: String);
    { ICompilerFinished – reserved for external bus notifications; review uses IDE API directly. }
    Procedure CompilerFinished(Const ProjectFile: String; Result: TCompilerResult;
      Const OutputText: String; ErrorCount, WarningCount: Integer);
    { IMarkdownDocumentChanged }
    Procedure DocumentChanged(Const FileName: String; Const NewContent: String);
    Procedure DocumentSaved(Const FileName: String);
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure StartNewChat(KeepPlanAgent: Boolean = False);
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

Uses
  WorkflowLog, AssistantService, AssistantConfig, AssistantSettingsForm, AssistantIDEContext,
  AssistantSession, AssistantTools, AssistantMarkdownForm, GrokOAuth, LazFileUtils,
  FileUtil, LCLIntf, LazIDEIntf, IDEMsgIntf, SrcEditorIntf,
  ProjectIntf;

Const
  ChatViewMargin = 4;
  ChatPaintMinIntervalMs = 80;
  { List Objects store TurnIndex+1; this marker is the in-flight (not yet recorded) turn. }
  LiveConversationMarker = -2;

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
  FHistoryTrace := TAssistantTrace.Create;
  FTraceView := Nil;
  FThinkingSliceStart := 1;
  FHistoryUpdating := False;
  HistoryIds := TStringList.Create;
  Transcript := TStringList.Create;
  CodeSections := TObjectList.Create(True);
  CodePanel := Nil;
  FCodeSelectedIndex := -1;
  FCodeWorkSectionIndex := -1;
  FCodeWorkSectionTitle := '';
  FCompileSeqAtSendStart := 0;
  FPendingReviewErrorOffer := False;
  FReviewErrorCount := 0;
  FContextWarnShown := False;
  FAutoRolloverInProgress := False;
  FPlanAgentRunning := False;
  FPlanAgentPackagesDone := 0;
  FPlanAgentMaxPackages := 25;
  FLastTurnHadError := False;
  WorkflowEventBus.AddListener(Self);
End;

Destructor TProjectAssistantForm.Destroy;
Begin
  If Assigned(AssistantClient) Then
    AssistantClient.CancelStream;
  PersistSession;
  WorkflowEventBus.RemoveListener(Self);
  If Assigned(AssistantClient) Then
    AssistantClient.OnTrace := Nil;
  FreeAndNil(Transcript);
  FreeAndNil(HistoryIds);
  FreeAndNil(CodeSections);
  FreeAndNil(FTrace);
  FreeAndNil(FHistoryTrace);
  Inherited Destroy;
End;

Procedure TProjectAssistantForm.FormCreate(Sender: TObject);
Begin
  Caption := 'Project Assistant';
  EnsureChatView;
  EnsureInputPopup;
  EnsurePlanTabUi;
  EnsureCodeTabUi;
  UpdateThinkingActionCaption;
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
  BindToActiveProject;
  WorkflowLogger.Info('ProjectAssistant', 'Project Assistant window created');
End;

Procedure TProjectAssistantForm.FormDestroy(Sender: TObject);
Begin
  If Assigned(ElapsedTimer) Then
    ElapsedTimer.Enabled := False;
  SetBusyCursor(False);
  { Persist OAuth tokens once on close (not on every prompt). }
  If Assigned(AssistantChatConfig) And Assigned(GrokOAuthClient) Then
    Begin
      AssistantChatConfig.ApplyOAuthTokens(GrokOAuthClient.Tokens);
      AssistantChatConfig.Save;
    End;
  WorkflowLogger.Info('ProjectAssistant', 'Project Assistant window destroyed');
End;

Procedure TProjectAssistantForm.UpdateThinkingActionCaption;
Begin
  If Not Assigned(ToggleThinkingAction) Then
    Exit;
  If FShowThinking Then
    ToggleThinkingAction.Caption := 'Hide Thinking'
  Else
    ToggleThinkingAction.Caption := 'Show Thinking';
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
  If Assigned(FTrace) Then
    FTrace.NilFrames;
  If Assigned(FHistoryTrace) Then
    FHistoryTrace.NilFrames;
  If Assigned(FTraceView) Then
    FTraceView.ResetFrames;
End;

Procedure TProjectAssistantForm.SetCurrentUserDisplay(Const UserText: String; Const WithIdeContext: Boolean);
Begin
  FDisplaySystemNote := '';
  If WithIdeContext Then
    FDisplayUser := UserText + LineEnding + LineEnding +
      '*(IDE context attached for the model: active editor + project files.)*'
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
  Else
    Screen.Cursor := crDefault;
End;

Function TProjectAssistantForm.CurrentModeFromUi: TAssistantMode;
Begin
  Result := amChat;
  If Not Assigned(ModeGroup) Then
    Exit;
  Case ModeGroup.ItemIndex Of
    1: Result := amPlan;
    2: Result := amCode;
  Else
    Result := amChat;
  End;
End;

Procedure TProjectAssistantForm.SelectMode(Mode: TAssistantMode);
Begin
  ActiveMode := Mode;
  FModeSticky := False;
  SyncModeUi;
  ApplyActiveMode;
End;

Procedure TProjectAssistantForm.SyncModeUi;
Var
  Wanted: Integer;
Begin
  FApplyingShellConfig := True;
  Try
    Case ActiveMode Of
      amPlan: Wanted := 1;
      amCode: Wanted := 2;
    Else
      Wanted := 0;
    End;
    If Assigned(ModeGroup) And (ModeGroup.ItemIndex <> Wanted) Then
      ModeGroup.ItemIndex := Wanted;
  Finally
    FApplyingShellConfig := False;
  End;
  UpdateModeSidePanels;
  UpdateModeBadge;
End;

Procedure TProjectAssistantForm.UpdateModeBadge;
Var
  ToolsHint: String;
Begin
  Case ActiveMode Of
    amPlan: ToolsHint := 'write plan Markdown';
    amCode: ToolsHint := 'edit sources · compile';
  Else
    ToolsHint := 'read-only tools';
  End;
  If Assigned(ModeBadge) Then
    Begin
      If FModeLocked Or FSending Then
        ModeBadge.Caption := Format('Mode: %s · %s · (reply in progress)',
          [AssistantModeToStr(ActiveMode), ToolsHint])
      Else If FModeSticky Then
        ModeBadge.Caption := Format('Mode: %s · %s · (sticky until you change mode)',
          [AssistantModeToStr(ActiveMode), ToolsHint])
      Else
        ModeBadge.Caption := Format('Mode: %s · %s',
          [AssistantModeToStr(ActiveMode), ToolsHint]);
    End;
  If Assigned(ModeGroup) Then
    ModeGroup.Enabled := Not (FSending Or FModeLocked);
End;

Procedure TProjectAssistantForm.UpdateModeSidePanels;
Begin
  If Assigned(ChatSidePanel) Then
    ChatSidePanel.Visible := ActiveMode = amChat;
  If Assigned(PlanPanel) Then
    PlanPanel.Visible := ActiveMode = amPlan;
  If Assigned(CodePanel) Then
    CodePanel.Visible := ActiveMode = amCode;
End;

Procedure TProjectAssistantForm.ShowChatSurfaceKeepMode;
Begin
  { Shared turn view is always visible; keep mode UI in sync without tab swaps. }
  SyncModeUi;
  If Assigned(AssistantClient) Then
    AssistantClient.SetActiveMode(ActiveMode);
End;

Procedure TProjectAssistantForm.LockModeForSend;
Begin
  { Capture mode from the mode control, then freeze it for the turn. }
  ActiveMode := CurrentModeFromUi;
  FModeLocked := True;
  FModeSticky := ActiveMode In [amPlan, amCode];
  If Assigned(AssistantClient) Then
    AssistantClient.SetActiveMode(ActiveMode);
  UpdateModeBadge;
  WorkflowLogger.Info('ProjectAssistant',
    'Mode locked for send: ' + AssistantModeToStr(ActiveMode));
End;

Procedure TProjectAssistantForm.ForceModeAndLock(Mode: TAssistantMode);
Begin
  { Enter a specific mode for this turn (e.g. Fix Error / Work-on-this → Code). }
  ActiveMode := Mode;
  FModeLocked := True;
  FModeSticky := Mode In [amPlan, amCode];
  If Assigned(AssistantClient) Then
    AssistantClient.SetActiveMode(Mode);
  SyncModeUi;
  WorkflowLogger.Info('ProjectAssistant',
    'Mode forced for send: ' + AssistantModeToStr(Mode));
End;

Procedure TProjectAssistantForm.UnlockModeAfterSend;
Begin
  FModeLocked := False;
  { FModeSticky keeps Plan/Code tools until the user picks another mode. }
  If Assigned(AssistantClient) Then
    AssistantClient.SetActiveMode(ActiveMode);
  UpdateModeBadge;
End;

Function TProjectAssistantForm.LooksLikePlanMarkdown(Const Body: String): Boolean;
Var
  T: String;
Begin
  T := Trim(Body);
  Result := (Length(T) >= 120) And
    ((Pos('##', T) > 0) Or (Pos('# ', T) = 1) Or (Pos('# ', T) > 0)) And
    ((Pos('Status:', T) > 0) Or (Pos('status:', LowerCase(T)) > 0) Or
     (Pos('Implementation', T) > 0) Or (Pos('work package', LowerCase(T)) > 0));
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
    Exit;
  If Not WriteMarkdownFile(PlanRel, Body + LineEnding, True, Resolved, Err) Then
    Begin
      WorkflowLogger.Warning('ProjectAssistant', 'Auto-save plan failed: ' + Err);
      Exit;
    End;
  SetActivePlanRelativePath(ProjectRelativePath(Resolved));
  PersistShellConfig;
  RefreshPlanList;
  If Assigned(CodePanel) Then
    RefreshCodeTodos;
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
    AssistantClient.SetActiveMode(ActiveMode);
  { Fix Error always switches into Code tools, so keep it available in every mode. }
  FixErrorAction.Enabled := Not FSending;
  Case ActiveMode Of
    amPlan:
      Begin
        ReviewCompileAction.Enabled := False;
        ReviewBuildAction.Enabled := False;
        EnsurePlanTabUi;
        RefreshPlanList;
      End;
    amCode:
      Begin
        ReviewCompileAction.Enabled := Not FSending;
        ReviewBuildAction.Enabled := Not FSending;
        EnsureCodeTabUi;
        RefreshCodeTodos;
      End;
  Else
    Begin
      ReviewCompileAction.Enabled := Not FSending;
      ReviewBuildAction.Enabled := Not FSending;
    End;
  End;
  SyncModeUi;
End;

Procedure TProjectAssistantForm.PersistShellConfig;
Begin
  If Not Assigned(ProjectAssistantConversation) Then
    Exit;
  If ProjectAssistantConversation.ProjectRoot = '' Then
    Exit;
  If Not ProjectAssistantConversation.SaveShellConfig(FShowThinking, ActiveMode,
    GetActivePlanRelativePath) Then
    WorkflowLogger.Warning('ProjectAssistant',
      'config.json save failed: ' + ProjectAssistantConversation.LastError);
End;

Procedure TProjectAssistantForm.ApplyShellConfigFromStore;
Var
  ShowThinking: Boolean;
  Mode: TAssistantMode;
  PlanFile: String;
Begin
  If Not Assigned(ProjectAssistantConversation) Then
    Exit;
  If Not ProjectAssistantConversation.LoadShellConfig(ShowThinking, Mode, PlanFile) Then
    Exit;
  FShowThinking := ShowThinking;
  UpdateThinkingActionCaption;
  SetActivePlanRelativePath(PlanFile);
  SelectMode(Mode);
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
  PlanPanel.Align := alClient;
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
  PlanNewButton.Caption := 'New plan…';
  PlanNewButton.AutoSize := True;
  PlanNewButton.OnClick := @PlanNewButtonClick;

  PlanOpenButton := TButton.Create(Self);
  PlanOpenButton.Parent := Bar;
  PlanOpenButton.Caption := 'Open';
  PlanOpenButton.AutoSize := True;
  PlanOpenButton.OnClick := @PlanOpenButtonClick;

  PlanSetActiveButton := TButton.Create(Self);
  PlanSetActiveButton.Parent := Bar;
  PlanSetActiveButton.Caption := 'Set active';
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
  If Not Assigned(PlanList) Then
    Exit;
  If (PlanList.ItemIndex < 0) Or (PlanList.ItemIndex >= PlanList.Items.Count) Then
    Exit;
  Result := PlanList.Items[PlanList.ItemIndex];
End;

Procedure TProjectAssistantForm.RefreshPlanList;
Var
  Paths: TStringList;
  Err: String;
  I, Sel: Integer;
  ActivePlan: String;
Begin
  If Not Assigned(PlanList) Then
    Exit;
  ActivePlan := GetActivePlanRelativePath;
  If Assigned(PlanActiveLabel) Then
    If ActivePlan = '' Then
      PlanActiveLabel.Caption := 'Active plan: (none) — create one under Documents/ or Set active'
    Else
      PlanActiveLabel.Caption := 'Active plan: ' + ActivePlan;

  Paths := Nil;
  Sel := -1;
  PlanList.Items.BeginUpdate;
  Try
    PlanList.Items.Clear;
    If Not ListProjectMarkdownPlans(Paths, Err) Then
      Begin
        If Err <> '' Then
          PlanList.Items.Add('(' + Err + ')');
        Exit;
      End;
    For I := 0 To Paths.Count - 1 Do
      Begin
        PlanList.Items.Add(Paths[I]);
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

Procedure TProjectAssistantForm.EnsureCodeTabUi;
Var
  Bar: TPanel;
Begin
  If Assigned(CodePanel) Or (Not Assigned(ModeSidePanel)) Then
    Exit;

  CodePanel := TPanel.Create(Self);
  CodePanel.Parent := ModeSidePanel;
  CodePanel.Align := alClient;
  CodePanel.BevelOuter := bvNone;
  CodePanel.BorderSpacing.Around := 8;
  CodePanel.Visible := ActiveMode = amCode;

  CodeActiveLabel := TLabel.Create(Self);
  CodeActiveLabel.Parent := CodePanel;
  CodeActiveLabel.Align := alTop;
  CodeActiveLabel.Caption := 'Active plan: (none)';
  CodeActiveLabel.WordWrap := True;
  CodeActiveLabel.BorderSpacing.Bottom := 6;

  Bar := TPanel.Create(Self);
  Bar.Parent := CodePanel;
  Bar.Align := alTop;
  Bar.Height := 36;
  Bar.BevelOuter := bvNone;
  Bar.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  Bar.ChildSizing.ControlsPerLine := 10;
  Bar.ChildSizing.HorizontalSpacing := 6;
  Bar.ChildSizing.LeftRightSpacing := 0;
  Bar.ChildSizing.TopBottomSpacing := 2;
  Bar.BorderSpacing.Bottom := 6;

  CodeRefreshButton := TButton.Create(Self);
  CodeRefreshButton.Parent := Bar;
  CodeRefreshButton.Caption := 'Refresh';
  CodeRefreshButton.AutoSize := True;
  CodeRefreshButton.OnClick := @CodeRefreshButtonClick;

  CodeOpenPlanButton := TButton.Create(Self);
  CodeOpenPlanButton.Parent := Bar;
  CodeOpenPlanButton.Caption := 'Open plan';
  CodeOpenPlanButton.AutoSize := True;
  CodeOpenPlanButton.OnClick := @CodeOpenPlanButtonClick;

  CodeStartButton := TButton.Create(Self);
  CodeStartButton.Parent := Bar;
  CodeStartButton.Caption := 'Start';
  CodeStartButton.AutoSize := True;
  CodeStartButton.OnClick := @CodeStartButtonClick;

  CodeDoneButton := TButton.Create(Self);
  CodeDoneButton.Parent := Bar;
  CodeDoneButton.Caption := 'Done';
  CodeDoneButton.AutoSize := True;
  CodeDoneButton.OnClick := @CodeDoneButtonClick;

  CodeResetButton := TButton.Create(Self);
  CodeResetButton.Parent := Bar;
  CodeResetButton.Caption := 'Reset';
  CodeResetButton.AutoSize := True;
  CodeResetButton.OnClick := @CodeResetButtonClick;

  CodeWorkButton := TButton.Create(Self);
  CodeWorkButton.Parent := Bar;
  CodeWorkButton.Caption := 'Work on this';
  CodeWorkButton.AutoSize := True;
  CodeWorkButton.OnClick := @CodeWorkButtonClick;

  CodeWorkPlanButton := TButton.Create(Self);
  CodeWorkPlanButton.Parent := Bar;
  CodeWorkPlanButton.Caption := 'Work on plan';
  CodeWorkPlanButton.AutoSize := True;
  CodeWorkPlanButton.Hint := 'Agentically work through incomplete plan packages until done, error, or context limit';
  CodeWorkPlanButton.ShowHint := True;
  CodeWorkPlanButton.OnClick := @CodeWorkPlanButtonClick;

  CodeStatusLabel := TLabel.Create(Self);
  CodeStatusLabel.Parent := CodePanel;
  CodeStatusLabel.Align := alBottom;
  CodeStatusLabel.Caption := 'Select a work package, then Start / Done / Reset.';
  CodeStatusLabel.WordWrap := True;
  CodeStatusLabel.BorderSpacing.Top := 6;

  CodeTodoList := TListBox.Create(Self);
  CodeTodoList.Parent := CodePanel;
  CodeTodoList.Align := alClient;
  CodeTodoList.OnClick := @CodeTodoListClick;
  CodeTodoList.OnDblClick := @CodeTodoListDblClick;
  CodeTodoList.OnSelectionChange := @CodeTodoListSelectionChange;
End;

Procedure TProjectAssistantForm.RefreshCodeTodos;
Var
  PlanRel, Err: String;
  I, Keep: Integer;
  Section: TPlanSection;
  NotStarted, InProgress, Complete: Integer;
Begin
  If Not Assigned(CodeTodoList) Then
    Exit;
  PlanRel := GetActivePlanRelativePath;
  If Assigned(CodeActiveLabel) Then
    If PlanRel = '' Then
      CodeActiveLabel.Caption :=
        'Active plan: (none) — set one on the Plan tab, then Refresh.'
    Else
      CodeActiveLabel.Caption := 'Active plan: ' + PlanRel +
        '  ·  TODO tiles are scanned from ## headings + Status: lines.';

  Keep := FCodeSelectedIndex;
  If (Keep < 0) And Assigned(CodeTodoList) Then
    Keep := CodeTodoList.ItemIndex;
  CodeTodoList.Items.BeginUpdate;
  Try
    CodeTodoList.Items.Clear;
    If Assigned(CodeSections) Then
      CodeSections.Clear;
    If PlanRel = '' Then
      Begin
        CodeTodoList.Items.Add('(No active plan — open the Plan tab and Set active.)');
        Exit;
      End;
    If Not ScanPlanSections(PlanRel, CodeSections, Err) Then
      Begin
        CodeTodoList.Items.Add('(' + Err + ')');
        Exit;
      End;
    If CodeSections.Count = 0 Then
      Begin
        CodeTodoList.Items.Add(
          '(No ## sections found. Add work packages with Status: not started | in progress | complete.)');
        Exit;
      End;
    NotStarted := 0;
    InProgress := 0;
    Complete := 0;
    For I := 0 To CodeSections.Count - 1 Do
      Begin
        Section := TPlanSection(CodeSections[I]);
        CodeTodoList.Items.Add(FormatPlanSectionTile(Section, I));
        Case Section.Status Of
          pssNotStarted: Inc(NotStarted);
          pssInProgress: Inc(InProgress);
          pssComplete: Inc(Complete);
        Else
          { }
        End;
      End;
    If Assigned(CodeActiveLabel) And (PlanRel <> '') Then
      CodeActiveLabel.Caption := Format(
        'Active plan: %s  ·  %d not started · %d in progress · %d complete',
        [PlanRel, NotStarted, InProgress, Complete]);
    If (Keep >= 0) And (Keep < CodeTodoList.Items.Count) Then
      CodeTodoList.ItemIndex := Keep
    Else
      Begin
        { Prefer first in-progress, else first not-started. }
        CodeTodoList.ItemIndex := 0;
        For I := 0 To CodeSections.Count - 1 Do
          If TPlanSection(CodeSections[I]).Status = pssInProgress Then
            Begin
              CodeTodoList.ItemIndex := I;
              Break;
            End;
        If (CodeTodoList.ItemIndex = 0) And (CodeSections.Count > 0) And
          (TPlanSection(CodeSections[0]).Status <> pssInProgress) Then
          For I := 0 To CodeSections.Count - 1 Do
            If TPlanSection(CodeSections[I]).Status = pssNotStarted Then
              Begin
                CodeTodoList.ItemIndex := I;
                Break;
              End;
      End;
    FCodeSelectedIndex := CodeTodoList.ItemIndex;
  Finally
    CodeTodoList.Items.EndUpdate;
  End;
End;

Function TProjectAssistantForm.SelectedCodeSectionIndex: Integer;
Begin
  Result := -1;
  If Not Assigned(CodeSections) Or (CodeSections.Count = 0) Then
    Exit;
  { Prefer the remembered index: button clicks often clear ListBox.ItemIndex on GTK. }
  If (FCodeSelectedIndex >= 0) And (FCodeSelectedIndex < CodeSections.Count) Then
    Result := FCodeSelectedIndex
  Else If Assigned(CodeTodoList) And (CodeTodoList.ItemIndex >= 0) And
    (CodeTodoList.ItemIndex < CodeSections.Count) Then
    Result := CodeTodoList.ItemIndex;
End;

Procedure TProjectAssistantForm.SetCodeStatusFeedback(Const MessageText: String);
Begin
  If Assigned(CodeStatusLabel) Then
    CodeStatusLabel.Caption := MessageText;
  StatusFooter.SetRightText(MessageText);
  WorkflowLogger.Info('ProjectAssistant', 'Code TODO: ' + MessageText);
End;

Procedure TProjectAssistantForm.SetSelectedCodeSectionStatus(NewStatus: TPlanSectionStatus);
Var
  PlanRel, Err, SectionTitle, Feedback: String;
  Idx: Integer;
  OldStatus: TPlanSectionStatus;
Begin
  PlanRel := GetActivePlanRelativePath;
  If PlanRel = '' Then
    Begin
      SetCodeStatusFeedback('Set an active plan on the Plan tab first.');
      MessageDlg('Set an active plan on the Plan tab first.', mtInformation, [mbOK], 0);
      Exit;
    End;
  Idx := SelectedCodeSectionIndex;
  If Idx < 0 Then
    Begin
      SetCodeStatusFeedback('Select a work package in the list, then Start / Done / Reset.');
      MessageDlg('Select a work package in the list.', mtInformation, [mbOK], 0);
      Exit;
    End;
  { Copy title/status before RefreshCodeTodos frees CodeSections entries. }
  SectionTitle := TPlanSection(CodeSections[Idx]).Title;
  OldStatus := TPlanSection(CodeSections[Idx]).Status;
  If OldStatus = NewStatus Then
    Begin
      Feedback := Format('"%s" is already %s.',
        [SectionTitle, PlanSectionStatusToStr(NewStatus)]);
      SetCodeStatusFeedback(Feedback);
      Exit;
    End;
  If Not SetPlanSectionStatus(PlanRel, Idx, NewStatus, Err) Then
    Begin
      SetCodeStatusFeedback('Failed: ' + Err);
      MessageDlg(Err, mtError, [mbOK], 0);
      Exit;
    End;
  FCodeSelectedIndex := Idx;
  RefreshCodeTodos;
  If Assigned(CodeTodoList) And (Idx >= 0) And (Idx < CodeTodoList.Items.Count) Then
    Begin
      CodeTodoList.ItemIndex := Idx;
      FCodeSelectedIndex := Idx;
    End;
  Feedback := Format('%s → %s', [SectionTitle, PlanSectionStatusToStr(NewStatus)]);
  SetCodeStatusFeedback(Feedback);
  SetCurrentSystemNote(Format('Plan status updated: **%s** → `%s`.',
    [SectionTitle, PlanSectionStatusToStr(NewStatus)]));
  If NewStatus = pssComplete Then
    ClearCodeWorkTracking;
End;

Procedure TProjectAssistantForm.ClearCodeWorkTracking;
Begin
  FCodeWorkSectionIndex := -1;
  FCodeWorkSectionTitle := '';
End;

Procedure TProjectAssistantForm.BeginCodeWorkTracking(SectionIndex: Integer; Const SectionTitle: String);
Begin
  FCodeWorkSectionIndex := SectionIndex;
  FCodeWorkSectionTitle := SectionTitle;
  FCompileSeqAtSendStart := AssistantLastCompileSeq;
End;

Procedure TProjectAssistantForm.TryAutoCompleteCodeWork(Const StreamErrorText: String);
Var
  PlanRel, Err, Note: String;
  Idx: Integer;
  CompileThisTurn, CompileClean: Boolean;
Begin
  Idx := FCodeWorkSectionIndex;
  If Idx < 0 Then
    Exit;
  If StreamErrorText <> '' Then
    Begin
      SetCodeStatusFeedback('Work interrupted — package still in progress.');
      Exit;
    End;
  CompileThisTurn := AssistantLastCompileSeq > FCompileSeqAtSendStart;
  CompileClean := CompileThisTurn And AssistantLastCompileWasClean;
  If Not CompileThisTurn Then
    Begin
      SetCodeStatusFeedback(Format('"%s" work finished (no run_compile this turn) — use Done when ready.',
        [FCodeWorkSectionTitle]));
      Exit;
    End;
  If Not CompileClean Then
    Begin
      SetCodeStatusFeedback(Format('"%s" work finished but compile is not clean — fix errors, then Done.',
        [FCodeWorkSectionTitle]));
      Exit;
    End;
  PlanRel := GetActivePlanRelativePath;
  If PlanRel = '' Then
    Begin
      ClearCodeWorkTracking;
      Exit;
    End;
  { Ensure list still matches; refresh may reorder if plan changed. }
  FCodeSelectedIndex := Idx;
  If Not SetPlanSectionStatus(PlanRel, Idx, pssComplete, Err) Then
    Begin
      SetCodeStatusFeedback('Auto-complete failed: ' + Err);
      WorkflowLogger.Warning('ProjectAssistant', 'Auto Status complete failed: ' + Err);
      Exit;
    End;
  RefreshCodeTodos;
  If Assigned(CodeTodoList) And (Idx >= 0) And (Idx < CodeTodoList.Items.Count) Then
    Begin
      CodeTodoList.ItemIndex := Idx;
      FCodeSelectedIndex := Idx;
    End;
  Note := Format('Auto-marked **%s** complete (Work-on-this + clean `run_compile`).',
    [FCodeWorkSectionTitle]);
  SetCodeStatusFeedback(Format('%s → complete (auto)', [FCodeWorkSectionTitle]));
  If FViewingLive Then
    Begin
      If FDisplaySystemNote <> '' Then
        FDisplaySystemNote := FDisplaySystemNote + LineEnding + LineEnding + Note
      Else
        FDisplaySystemNote := Note;
    End
  Else
    SetCurrentSystemNote(Note);
  WorkflowLogger.Info('ProjectAssistant', 'Auto Status complete: ' + FCodeWorkSectionTitle);
  ClearCodeWorkTracking;
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
    'Click **Fix Error** (or Assistant → Fix Error in Code mode) to apply a Code-mode fix with tools.';
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

Procedure TProjectAssistantForm.CodeRefreshButtonClick(Sender: TObject);
Begin
  RefreshCodeTodos;
  SetCodeStatusFeedback('TODO list refreshed from plan file.');
End;

Procedure TProjectAssistantForm.CodeOpenPlanButtonClick(Sender: TObject);
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

Procedure TProjectAssistantForm.CodeStartButtonClick(Sender: TObject);
Begin
  SetSelectedCodeSectionStatus(pssInProgress);
End;

Procedure TProjectAssistantForm.CodeDoneButtonClick(Sender: TObject);
Begin
  SetSelectedCodeSectionStatus(pssComplete);
End;

Procedure TProjectAssistantForm.CodeResetButtonClick(Sender: TObject);
Begin
  SetSelectedCodeSectionStatus(pssNotStarted);
End;

Function TProjectAssistantForm.BuildCodeWorkPrompt(Const PlanRel, SectionTitle, StatusText,
  SectionBody: String): String;
Const
  MaxBodyChars = 6000;
Var
  Body: String;
Begin
  Body := Trim(SectionBody);
  If Length(Body) > MaxBodyChars Then
    Body := Copy(Body, 1, MaxBodyChars) + LineEnding + LineEnding +
      '… *(section truncated for the prompt; open the plan file for the full text.)*';
  Result :=
    'Work on this plan package in **Code mode**.' + LineEnding +
    LineEnding +
    '**Active plan:** `' + PlanRel + '`' + LineEnding +
    '**Package:** ' + SectionTitle + LineEnding +
    '**Status:** ' + StatusText + LineEnding +
    LineEnding +
    'Instructions:' + LineEnding +
    '1. Focus only on this work package unless blocked.' + LineEnding +
    '2. Discover with `search_in_project` / `get_project_info` / `list_directory`, then `read_file`.' + LineEnding +
    '3. **Apply code changes with tools:** `replace_in_file` for surgical edits, `write_file` only for real ' +
    'non-empty project files (never ApiProbe/scratch/empty units), `ensure_form_component` for form components ' +
    '(updates .pas **and** .lfm), `add_unit_to_project` when needed. Discover APIs with search/read — do not ' +
    'create temporary probe units. Do not only describe patches; do not claim .lfm edits without tools.' + LineEnding +
    '4. After edits call `run_compile` (default is quiet/non-visual lazbuild — do not set ui=true ' +
    'for intermediate checks). Fix errors/warnings you introduced. A clean quiet compile (errors=0) ' +
    'auto-marks complete. Optional final `run_compile` with ui=true only if you need IDE Messages.' + LineEnding +
    '5. For inventory/review packages: put findings **in the chat** (tables); avoid extra Baseline.md files. ' +
    'If no code changes are required, still call `run_compile` once when the project should build clean, ' +
    'or tell the user to mark Done manually.' + LineEnding +
    '6. Prefer tools for Status updates; the IDE may also set `Status: complete` after a clean compile.' + LineEnding +
    '7. When finished, say clearly what changed and whether compile is clean.' + LineEnding +
    LineEnding +
    '----- begin plan section -----' + LineEnding +
    Body + LineEnding +
    '----- end plan section -----';
End;

Procedure TProjectAssistantForm.CodeWorkOnSelectedPackage;
Var
  PlanRel, Err, Body, Prompt, Title, StatusText: String;
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
  Idx := SelectedCodeSectionIndex;
  If Idx < 0 Then
    Begin
      MessageDlg('Select a work package in the list.', mtInformation, [mbOK], 0);
      Exit;
    End;
  Section := TPlanSection(CodeSections[Idx]);
  Title := Section.Title;
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
          FCodeSelectedIndex := Idx;
          RefreshCodeTodos;
          If Assigned(CodeTodoList) And (Idx < CodeTodoList.Items.Count) Then
            CodeTodoList.ItemIndex := Idx;
        End;
    End;
  If Not GetPlanSectionBody(PlanRel, Idx, Body, Err) Then
    Begin
      MessageDlg('Could not load plan section:' + LineEnding + Err, mtError, [mbOK], 0);
      Exit;
    End;
  Prompt := BuildCodeWorkPrompt(PlanRel, Title, StatusText, Body);
  { Stay in Code mode (tools + prompt) while showing the Chat turn surface. }
  BeginCodeWorkTracking(Idx, Title);
  ForceModeAndLock(amCode);
  ShowChatSurfaceKeepMode;
  SetCodeStatusFeedback('Working on: ' + Title);
  SubmitUserText(Prompt, True);
  If Not FSending Then
    Begin
      UnlockModeAfterSend;
      ClearCodeWorkTracking;
    End;
End;

Procedure TProjectAssistantForm.CodeWorkButtonClick(Sender: TObject);
Begin
  If FPlanAgentRunning Then
    Begin
      MessageDlg('Plan agent is already running. Use Stop to cancel the current reply, then try again.',
        mtInformation, [mbOK], 0);
      Exit;
    End;
  CodeWorkOnSelectedPackage;
End;

Function TProjectAssistantForm.FindNextIncompleteCodeSection: Integer;
Var
  I: Integer;
  Section: TPlanSection;
  FirstNotStarted: Integer;
Begin
  Result := -1;
  FirstNotStarted := -1;
  If Not Assigned(CodeSections) Then
    Exit;
  For I := 0 To CodeSections.Count - 1 Do
    Begin
      Section := TPlanSection(CodeSections[I]);
      If Section.Status = pssInProgress Then
        Begin
          Result := I;
          Exit;
        End;
      If (FirstNotStarted < 0) And (Section.Status In [pssNotStarted, pssUnknown]) Then
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
  SetCodeStatusFeedback('Plan agent stopped: ' + Reason);
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
  EnsureCodeTabUi;
  RefreshCodeTodos;
  Idx := FindNextIncompleteCodeSection;
  If Idx < 0 Then
    Begin
      MessageDlg('All plan packages are already complete (or none found).', mtInformation, [mbOK], 0);
      Exit;
    End;
  FPlanAgentRunning := True;
  FPlanAgentPackagesDone := 0;
  FLastTurnHadError := False;
  FCodeSelectedIndex := Idx;
  If Assigned(CodeTodoList) And (Idx < CodeTodoList.Items.Count) Then
    CodeTodoList.ItemIndex := Idx;
  SetCodeStatusFeedback('Plan agent: starting…');
  SetCurrentSystemNote(
    '**Plan agent** started — will work through incomplete packages until complete, error, ' +
    'context ≥ 95%, or max packages.');
  SelectMode(amCode);
  CodeWorkOnSelectedPackage;
  If Not FSending Then
    StopWorkOnPlanAgent('could not start first package');
End;

Procedure TProjectAssistantForm.ContinueWorkOnPlanAgent(Data: PtrInt);
Var
  Idx, Pct: Integer;
Begin
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
  EnsureCodeTabUi;
  RefreshCodeTodos;
  Idx := FindNextIncompleteCodeSection;
  If Idx < 0 Then
    Begin
      StopWorkOnPlanAgent(Format('all packages complete (%d worked this run)',
        [FPlanAgentPackagesDone]));
      Exit;
    End;
  FCodeSelectedIndex := Idx;
  If Assigned(CodeTodoList) And (Idx < CodeTodoList.Items.Count) Then
    CodeTodoList.ItemIndex := Idx;
  SetCodeStatusFeedback(Format('Plan agent: package %d…', [FPlanAgentPackagesDone + 1]));
  CodeWorkOnSelectedPackage;
  If Not FSending Then
    StopWorkOnPlanAgent('failed to start next package');
End;

Procedure TProjectAssistantForm.CodeWorkPlanButtonClick(Sender: TObject);
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

Procedure TProjectAssistantForm.CodeTodoListClick(Sender: TObject);
Begin
  If Assigned(CodeTodoList) And Assigned(CodeSections) And
    (CodeTodoList.ItemIndex >= 0) And
    (CodeTodoList.ItemIndex < CodeSections.Count) Then
    FCodeSelectedIndex := CodeTodoList.ItemIndex;
End;

Procedure TProjectAssistantForm.CodeTodoListSelectionChange(Sender: TObject; User: Boolean);
Begin
  If Assigned(CodeTodoList) And Assigned(CodeSections) And
    (CodeTodoList.ItemIndex >= 0) And
    (CodeTodoList.ItemIndex < CodeSections.Count) Then
    FCodeSelectedIndex := CodeTodoList.ItemIndex;
End;

Procedure TProjectAssistantForm.CodeTodoListDblClick(Sender: TObject);
Begin
  { Double-click = work on this package (not only mark in progress). }
  CodeTodoListClick(Sender);
  CodeWorkOnSelectedPackage;
End;

Procedure TProjectAssistantForm.ModeGroupClick(Sender: TObject);
Begin
  If FApplyingShellConfig Then
    Exit;
  If FSending Or FModeLocked Then
    Begin
      { Freeze mode UI during a send; restore radio selection to ActiveMode. }
      SyncModeUi;
      Exit;
    End;
  { Explicit mode change ends sticky Plan/Code behaviour. }
  FModeSticky := False;
  ActiveMode := CurrentModeFromUi;
  ApplyActiveMode;
  PersistShellConfig;
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
    ExcludeTrailingPathDelimiter(Root));
  If RootChanged Then
    Begin
      ProjectAssistantConversation.SetProjectRoot(Root);
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

Procedure TProjectAssistantForm.ShowConversationTurn(TurnIndex: Integer);
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
      FDisplaySystemNote := '';
      FDisplayDurationMs := 0;
      FDisplayThinkingMs := 0;
      RefreshChatDisplay(True, FSending);
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
  FDisplayDurationMs := Turn.DurationMs;
  FDisplayThinkingMs := Turn.ThinkingMs;
  If Turn.ErrorText <> '' Then
    FDisplaySystemNote := '**Error:** ' + Turn.ErrorText
  Else
    FDisplaySystemNote := '';
  RefreshChatDisplay(True, False);
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
    ShowConversationTurn(N - 1)
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
  If Assigned(ExportHistoryAction) Then
    ExportHistoryAction.Enabled := (Not FSending) And Assigned(ProjectAssistantConversation) And
      ProjectAssistantConversation.HasTurns;
  If Assigned(DeleteHistoryAction) Then
    DeleteHistoryAction.Enabled := Not FSending;
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
  ProjectName, MetaLine: String;
Begin
  SL := TStringList.Create;
  Try
    ProjectName := '(unknown project)';
    If Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject) Then
      Begin
        If Assigned(LazarusIDE.ActiveProject.MainFile) And
          (LazarusIDE.ActiveProject.MainFile.Filename <> '') Then
          ProjectName := LazarusIDE.ActiveProject.MainFile.Filename
        Else
          ProjectName := LazarusIDE.ActiveProject.ProjectInfoFile;
      End;
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
        Else
          SL.Add('*(empty)*');
        SL.Add('');
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
  I: Integer;
  Prompt, Response, Thinking, Err: String;
Begin
  If Assigned(AssistantClient) Then
    AssistantClient.ClearHistory;
  FContextUsed := 0;
  If Not Assigned(ProjectAssistantConversation) Then
    Exit;
  For I := 0 To ProjectAssistantConversation.TurnCount - 1 Do
    Begin
      If Not ProjectAssistantConversation.GetTurnDisplay(I, Prompt, Response, Thinking, Err) Then
        Continue;
      If Assigned(AssistantClient) Then
        Begin
          If Trim(Prompt) <> '' Then
            Begin
              AssistantClient.AddMessage(amrUser, Prompt);
              FContextUsed := FContextUsed + Length(Prompt) Div 4 + 8;
            End;
          If Trim(Response) <> '' Then
            Begin
              AssistantClient.AddMessage(amrAssistant, Response);
              FContextUsed := FContextUsed + Length(Response) Div 4 + 20;
            End;
          If Trim(Thinking) <> '' Then
            FContextUsed := FContextUsed + Length(Thinking) Div 4;
        End;
    End;
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
  If (Trim(FLiveUser) = '') And (Trim(FDisplayUser) = '') And
    (Trim(FLiveContent) = '') And (Trim(FAssistantContent) = '') And (Trim(ErrorText) = '') Then
    Exit;
  DurationMs := CurrentStreamDurationMs;
  Turn.Id := NewConversationTurnId;
  Turn.Mode := AssistantModeToStr(ActiveMode);
  If FLiveUser <> '' Then
    Turn.Prompt := FLiveUser
  Else
    Turn.Prompt := FDisplayUser;
  If FLiveThinking <> '' Then
    Turn.Thinking := FLiveThinking
  Else
    Turn.Thinking := FAssistantThinking;
  If FLiveContent <> '' Then
    Turn.Response := FLiveContent
  Else
    Turn.Response := FAssistantContent;
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
  If Assigned(AssistantClient) Then
    Turn.Skill := AssistantClient.ActiveSkill
  Else
    Turn.Skill := '';
  Turn.TokenEstimate := Length(Turn.Prompt + Turn.Response + Turn.Thinking) Div 4;
  Turn.ErrorText := ErrorText;
  Turn.PlanFile := GetActivePlanRelativePath;
  Turn.TodoId := '';
  If ProjectAssistantConversation.AppendTurn(Turn, Entry) Then
    Begin
      FTurnRecorded := True;
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
  If FLiveContent <> '' Then
    FTrace.EnsureAnswer.Body := FLiveContent;
  FTrace.FinishCurrentThinking;
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
  UpdateThinkingActionCaption;
  PersistShellConfig;
  If Assigned(FTraceView) Then
    Begin
      FTraceView.ShowThinking := FShowThinking;
      If FViewingLive Then
        FTraceView.Sync(FTrace, False)
      Else If Assigned(FHistoryTrace) Then
        FTraceView.Sync(FHistoryTrace, False)
      Else
        RefreshChatDisplay(True);
    End
  Else
    RefreshChatDisplay(True);
End;

Function TProjectAssistantForm.FormatElapsedStatus(Const Phase: String): String;
Var
  Secs, Mins, Rem: Integer;
Begin
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
  FStatusPhase := Phase;
  StatusFooter.SetRightText(FormatElapsedStatus(Phase));
End;

Procedure TProjectAssistantForm.ElapsedTimerTimer(Sender: TObject);
Begin
  If FSending And (FStatusPhase <> '') Then
    StatusFooter.SetRightText(FormatElapsedStatus(FStatusPhase));
  If FSending And Assigned(FTraceView) And Assigned(FTrace) And FViewingLive Then
    FTraceView.RefreshElapsed(FTrace);
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
  StatusText, LeftText, CentreText, ThinkCap, ApprCap: String;
Begin
  If Assigned(AssistantClient) And (Not FSending) Then
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
  LeftText := Format('Model: %s · Think: %s · Approve: %s',
    [FModelName, ThinkCap, ApprCap]);
  If Assigned(AssistantChatConfig) And (AssistantChatConfig.ActiveSkill <> '') Then
    LeftText := LeftText + ' · Skill: ' + AssistantChatConfig.ActiveSkill;
  CentreText := Format('Context %d%%  (~%d / %d tok)', [Pct, FContextUsed, FContextLimit]);
  If Pct >= 95 Then
    CentreText := CentreText + ' ⚠';
  StatusFooter.SetAll(LeftText, CentreText, StatusText);
  If (Not FSending) And (Pct >= 95) Then
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
        StartNewChat(KeepAgent);
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
    Format('**Context usage is high (%d%%).** Start a **New Chat** before continuing long Code/Plan work ' +
      'so the model stays within its token limit. Or enable **Auto New Chat at 95%%** on this form.',
      [Pct]));
  MessageDlg(
    Format('Context usage is at about %d%% of the budget.%s%s' +
      'Start a New Chat before continuing large Plan/Code sessions, or enable "Auto New Chat at 95%%" ' +
      'on the assistant form (default is set in Settings).',
      [Pct, LineEnding, LineEnding]),
    mtWarning, [mbOK], 0);
End;

Procedure TProjectAssistantForm.SetSending(IsSending: Boolean);
Begin
  If IsSending And (Not FSending) Then
    AssistantBeginQuietIdeSession
  Else If (Not IsSending) And FSending Then
    AssistantEndQuietIdeSession;
  FSending := IsSending;
  If Not IsSending Then
    FReviewInProgress := False;
  SendAction.Enabled := Not IsSending;
  StopAction.Enabled := IsSending;
  NewChatAction.Enabled := Not IsSending;
  ReviewCompileAction.Enabled := (Not IsSending) And (Not FReviewInProgress);
  ReviewBuildAction.Enabled := (Not IsSending) And (Not FReviewInProgress);
  FixErrorAction.Enabled := Not IsSending;
  InputMemo.ReadOnly := IsSending;
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
  UpdateStatusFooter;
End;

Procedure TProjectAssistantForm.PersistSession;
Var
  Key: String;
Begin
  If FSending Then
    Exit;
  Key := '';
  If Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject) Then
    Key := LazarusIDE.ActiveProject.ProjectInfoFile;
  If Key = '' Then
    Exit;
  FSessionProjectKey := Key;
  SaveProjectChatSession(Transcript, FContextUsed);
End;

Procedure TProjectAssistantForm.RestoreSessionIfNeeded;
Var
  Key: String;
  LoadedContext: Integer;
Begin
  Key := '';
  If Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject) Then
    Key := LazarusIDE.ActiveProject.ProjectInfoFile;
  If Key = '' Then
    Exit;
  If SameText(Key, FSessionProjectKey) And Assigned(AssistantClient) And
    (AssistantClient.MessageCount > 0) Then
    Exit;
  FSessionProjectKey := Key;
  { Load messages for the model only — do not replace the chat pane with a banner.
    The visible turn comes from conversation (ShowLastConversationTurn). }
  If LoadProjectChatSession(Transcript, LoadedContext) Then
    Begin
      FContextUsed := LoadedContext;
      UpdateStatusFooter;
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
  InputPasteItem.ShortCut := ShortCut(Ord('V'), [ssCtrl]);
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
    InputPasteItem.Enabled := CanEdit And Clipboard.HasFormat(CF_TEXT);
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

Procedure TProjectAssistantForm.InputPasteClick(Sender: TObject);
Begin
  If Assigned(InputMemo) And (Not InputMemo.ReadOnly) Then
    InputMemo.PasteFromClipboard;
End;

Procedure TProjectAssistantForm.InputSelectAllClick(Sender: TObject);
Begin
  If Assigned(InputMemo) Then
    InputMemo.SelectAll;
End;

Procedure TProjectAssistantForm.ScrollChatToEnd;
Begin
  If Assigned(FTraceView) Then
    FTraceView.Sync(FTrace, True);
End;

Procedure TProjectAssistantForm.ScrollChatToTop;
Begin
  If Assigned(FTraceView) Then
    FTraceView.Sync(FTrace, False);
End;

Procedure TProjectAssistantForm.RebuildTraceFromFields;
Var
  Block: TTraceBlock;
  Last: TTraceBlock;
Begin
  If Not Assigned(FHistoryTrace) Then
    FHistoryTrace := TAssistantTrace.Create;
  ResetTraceCards;
  FHistoryTrace.Clear;
  FHistoryTrace.EnsureUser(FDisplayUser);
  If FAssistantThinking <> '' Then
    Begin
      Block := FHistoryTrace.StartThinking(0);
      Block.Body := FAssistantThinking;
      Block.StartedAt := 0;
      If FDisplayThinkingMs > 0 Then
        Block.DurationMs := FDisplayThinkingMs;
      FHistoryTrace.FinishCurrentThinking;
    End;
  If FAssistantContent <> '' Then
    FHistoryTrace.EnsureAnswer.Body := FAssistantContent;
  If FDisplaySystemNote <> '' Then
    Begin
      Last := Nil;
      If FHistoryTrace.Count > 0 Then
        Last := FHistoryTrace[FHistoryTrace.Count - 1];
      If (Not Assigned(Last)) Or (Last.Kind <> tbkNote) Or (Last.Body <> FDisplaySystemNote) Then
        FHistoryTrace.AddNote(FDisplaySystemNote);
    End;
  If FDisplayDurationMs > 0 Then
    FHistoryTrace.ApplyWorkedFooter(FDisplayDurationMs);
End;

Procedure TProjectAssistantForm.ApplyLiveThinkingAndAnswer;
Var
  Block, Last: TTraceBlock;
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
  Block := FTrace.CurrentRunningThinking;
  If Assigned(Block) Then
    Begin
      If Slice <> '' Then
        Block.Body := Slice;
    End
  Else If FStreamingActive And (Slice <> '') Then
    Begin
      Block := FTrace.StartThinking(0);
      Block.Body := Slice;
    End;
  Last := Nil;
  If FTrace.Count > 0 Then
    Last := FTrace[FTrace.Count - 1];
  If (FLiveContent <> '') And (Not (Assigned(Last) And (Last.Kind = tbkNote))) Then
    Begin
      FTrace.EnsureAnswer.Body := FLiveContent;
      If FThinkingSliceStart <= Length(FLiveThinking) Then
        FThinkingSliceStart := Length(FLiveThinking) + 1;
    End;
End;

Procedure TProjectAssistantForm.HandleTraceEvent(Const Event: TAssistantEvent);
Var
  Block: TTraceBlock;
Begin
  If Not FViewingLive Then
    Exit;
  If Not Assigned(FTrace) Then
    Exit;
  Try
    Case Event.Kind Of
    aekLoopStarted:
      Begin
        Block := FTrace.CurrentRunningThinking;
        If Assigned(Block) Then
          Block.LoopIndex := Event.LoopIndex
        Else
          Begin
            FThinkingSliceStart := Length(FLiveThinking) + 1;
            FTrace.StartThinking(Event.LoopIndex);
          End;
      End;
    aekToolStarted:
      FTrace.AddTool(Event.ToolId, Event.ToolName, Event.Text);
    aekToolCompleted:
      Begin
        Block := FTrace.FindTool(Event.ToolId);
        If Not Assigned(Block) Then
          Block := FTrace.AddTool(Event.ToolId, Event.ToolName, Event.Text);
        Block.Running := False;
        Block.Ok := Event.Ok;
        If Event.DurationMs > 0 Then
          Block.DurationMs := Event.DurationMs;
        If Not Event.Ok Then
          Block.Title := Block.Title + '  failed';
      End;
    aekSteerQueued:
      FTrace.AddSteer(Event.Text);
    aekInterjected:
      Begin
        Block := Nil;
        If FTrace.Count > 0 Then
          Block := FTrace[FTrace.Count - 1];
        If Assigned(Block) And (Block.Kind = tbkSteer) Then
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
      If FViewingLive Then
        ApplyLiveThinkingAndAnswer
      Else
        RebuildTraceFromFields;
      If Assigned(FTraceView) Then
        Begin
          FTraceView.ShowThinking := FShowThinking;
          If FViewingLive Then
            FTraceView.Sync(FTrace, ScrollToBottom)
          Else
            FTraceView.Sync(FHistoryTrace, ScrollToBottom);
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
  FDisplaySystemNote := '';
  FThinkingSliceStart := 1;
  ResetTraceCards;
  If Assigned(FTrace) Then
    Begin
      FTrace.Clear;
      FTrace.EnsureUser(FDisplayUser);
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
    If FLiveContent <> '' Then
      SetStreamPhase('Streaming…')
    Else If FLiveThinking <> '' Then
      SetStreamPhase('Thinking…')
    Else If FStatusPhase = '' Then
      SetStreamPhase('Waiting for first token…');
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
  DisplayBody, ResolvedError, TraceNote: String;
  WorkedMs: Integer;
Begin
  ResolvedError := ErrorText;
  If IsAssistantProgressStatus(ResolvedError) Then
    ResolvedError := '';
  If Assigned(AssistantClient) Then
    AssistantClient.ToolsEnabled := True;
  { Second IsFinished (or Stop after finish) must not append another conversation row. }
  If Not FSending Then
    Begin
      If Assigned(AssistantClient) Then
        AssistantClient.MarkStreamComplete;
      Exit;
    End;
  If FUserCancelled Then
    Begin
      FUserCancelled := False;
      FStreamingActive := False;
      If Assigned(AssistantClient) Then
        AssistantClient.MarkStreamComplete;
      If FCodeWorkSectionIndex >= 0 Then
        SetCodeStatusFeedback(Format('"%s" cancelled — still in progress.',
          [FCodeWorkSectionTitle]));
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
  FinishLiveTrace(TraceNote, WorkedMs);
  { Record from live buffers so a browsed-away pane still saves the real answer. }
  RecordCurrentTurn(ResolvedError);
  If Assigned(AssistantClient) Then
    AssistantClient.MarkStreamComplete;
  PersistPlanReplyIfNeeded(ResolvedError);
  { Code Work-on-this: auto Status: complete after a clean run_compile this turn. }
  If ActiveMode = amCode Then
    TryAutoCompleteCodeWork(ResolvedError)
  Else If FCodeWorkSectionIndex >= 0 Then
    ClearCodeWorkTracking;
  { Review with errors: select top error and prompt Fix Error. }
  If FPendingReviewErrorOffer And (ResolvedError = '') Then
    OfferFixTopErrorAfterReview
  Else If ResolvedError <> '' Then
    FPendingReviewErrorOffer := False;
  UnlockModeAfterSend;
  { End send before list refresh so the in-flight row is not kept alongside the stored turn. }
  SetSending(False);
  If FPlanAgentRunning Then
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
  { CancelStream pumps CheckSynchronize so Queue/Synchronize cannot deadlock. }
  If Assigned(AssistantClient) Then
    Begin
      AssistantClient.CancelStream;
      AssistantClient.ToolsEnabled := True;
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
    StopWorkOnPlanAgent('stream cancelled by user');
  WorkflowLogger.Info('ProjectAssistant', 'Stream cancelled by user');
End;

Procedure TProjectAssistantForm.SubmitUserText(Const UserText: String; AutoSend: Boolean);
Begin
  SubmitUserTextEx(UserText, UserText, AutoSend);
End;

Procedure TProjectAssistantForm.SubmitUserTextEx(Const DisplayText, ApiText: String; AutoSend: Boolean);
Var
  FinalApi, ContextBlock, PlanRel: String;
  WithContext: Boolean;
Begin
  If Trim(ApiText) = '' Then
    Exit;
  If FSending Then
    Exit;
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
      MaybeWarnHighContextUsage;
      { Callers like Fix Error / Work-on-this may already ForceModeAndLock. }
      If Not FModeLocked Then
        LockModeForSend; { freeze Plan/Code before Chat surface / SetSending }
      ShowChatSurfaceKeepMode; { shared turn view already visible; sync mode chrome }
      { Detect run_compile during this turn for Code auto Status: complete. }
      FCompileSeqAtSendStart := AssistantLastCompileSeq;
      FinalApi := ApiText;
      If ActiveMode = amPlan Then
        Begin
          PlanRel := GetActivePlanRelativePath;
          If PlanRel = '' Then
            PlanRel := DefaultPlanRelativePath;
          FinalApi :=
            '[SYSTEM DIRECTIVE — Plan mode] Write the plan into the project Markdown file ' +
            'using the write_markdown tool (path: "' + PlanRel +
            '"). Chat reply must be a short summary only, not the full plan body.' +
            LineEnding + LineEnding + ApiText;
        End;
      WithContext := Assigned(AssistantChatConfig) And AssistantChatConfig.IncludeIDEContext;
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
      { Prior turns already on AssistantClient are sent with this request (trimmed if huge). }
      AssistantClient.AddMessage(amrUser, FinalApi);
      FContextUsed := AssistantClient.EstimatedPromptTokens;
      If FContextUsed < Length(FinalApi) Div 4 Then
        FContextUsed := Length(FinalApi) Div 4 + 8;
      FStatusPhase := 'Waiting for first token…';
      AssistantClient.ToolsEnabled := True;
      SetSending(True);
      BeginAssistantReply;
      { Large skill + IDE context means a noticeable wait before the first token.
        That gap is model/server time-to-first-token, not local UI hang. }
      If Not AssistantClient.StartStream(@StreamToken) Then
        Begin
          FinishAssistantReply(AssistantClient.LastError);
          If Assigned(GrokOAuthClient) And (Not GrokOAuthClient.IsAuthenticated) Then
            SettingsActionExecute(Nil);
        End;
    End
  Else
    AppendMessage('user', DisplayText);
End;

Procedure TProjectAssistantForm.SendActionExecute(Sender: TObject);
Var
  UserText: String;
Begin
  If FSending Then
    Exit;
  UserText := Trim(InputMemo.Text);
  If UserText = '' Then
    Exit;
  If (Not Assigned(AssistantChatConfig)) Or (Not AssistantChatConfig.IsSignedIn) Then
    Begin
      MessageDlg('Sign in with SuperGrok / X Premium in Settings before sending.', mtInformation, [mbOK], 0);
      SettingsActionExecute(Nil);
      Exit;
    End;
  InputMemo.Clear;
  SubmitUserText(UserText, True);
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
  ProjectName := '(unknown)';
  If Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject) Then
    Begin
      If Assigned(LazarusIDE.ActiveProject.MainFile) Then
        ProjectName := LazarusIDE.ActiveProject.MainFile.Filename
      Else
        ProjectName := LazarusIDE.ActiveProject.ProjectInfoFile;
    End;
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
    'If there are errors, end with one short line: the user can click **Fix Error** to start Code mode on the top error.' + LineEnding +
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
      AssistantClient.ToolsEnabled := True;
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
  If Not Assigned(LazarusIDE.ActiveProject) Then
    Begin
      MessageDlg('Open a project before using Review ' + KindLabel + '.', mtInformation, [mbOK], 0);
      Exit;
    End;

  FReviewInProgress := True;
  ReviewCompileAction.Enabled := False;
  ReviewBuildAction.Enabled := False;
  StatusFooter.SetRightText(KindLabel + '…');
  Application.ProcessMessages;
  WorkflowLogger.Info('ProjectAssistant', 'Review ' + KindLabel + ' started');

  Try
    BuildResult := LazarusIDE.DoBuildProject(Reason, []);
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

Procedure TProjectAssistantForm.StartNewChat(KeepPlanAgent: Boolean);
Begin
  If FPlanAgentRunning And (Not KeepPlanAgent) Then
    StopWorkOnPlanAgent('new chat');
  If FSending Then
    StopStream;
  SetSending(False);
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
  If Not FAutoRolloverInProgress Then
    SetCurrentSystemNote('New conversation started. Previous chat moved to History.');
  PersistSession;
  UpdateStatusFooter;
End;

Procedure TProjectAssistantForm.UnbindFromProject;
Begin
  { Do not call PersistSession here: ActiveProject is half-torn during close.
    Conversation turns are already on disk via AppendTurn. }
  If FSending Then
    StopStream;
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
  Key, Title, Root: String;
  Proj: TLazProject;
Begin
  { Cancel any in-flight stream for the previous project before rebinding.
    Do not PersistSession first: when ProjectOpened fires, ActiveProject is already
    the new project, so a save would write the old transcript under the new path.
    Turns for the previous project were already flushed by AppendTurn. }
  If FSending Then
    StopStream;

  Key := '';
  Root := '';
  Title := 'Project Assistant';
  Proj := Nil;
  If Assigned(LazarusIDE) Then
    Proj := LazarusIDE.ActiveProject;
  If Assigned(Proj) And (Not Proj.IsVirtual) Then
    Begin
      Key := Proj.ProjectInfoFile;
      Root := ProjectAssistantRoot;
      If Assigned(Proj.MainFile) And (Proj.MainFile.Filename <> '') Then
        Title := 'Project Assistant — ' + ExtractFileName(Proj.MainFile.Filename)
      Else If Key <> '' Then
        Title := 'Project Assistant — ' + ExtractFileName(Key);
    End
  Else If Assigned(Proj) And Proj.IsVirtual Then
    Title := 'Project Assistant — (unsaved project)';

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
        ProjectAssistantConversation.SetProjectRoot('')
      Else
        Begin
          ProjectAssistantConversation.SetProjectRoot(Root);
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
      ShowLastConversationTurn;
      RefreshPlanList;
    End
  Else
    Begin
      SetActivePlanRelativePath('');
      RefreshHistoryCombo;
      RefreshConversationList;
      ClearCurrentTurnDisplay;
      RefreshChatDisplay(True, False);
      RefreshPlanList;
    End;
  UpdateStatusFooter;
  WorkflowLogger.Info('ProjectAssistant', 'Bound to project: ' + Title);
End;

Procedure NotifyOpenProjectAssistantFormsProjectChanged;
Var
  I: Integer;
  Form: TCustomForm;
Begin
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
    'You are in **Code mode**. Fix this Free Pascal / Lazarus compiler message by **editing sources with tools**.' +
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
  { Snapshot compile seq so a clean run_compile this turn can auto-complete Work-on-this. }
  FCompileSeqAtSendStart := AssistantLastCompileSeq;
  ForceModeAndLock(amCode);
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
    If Assigned(LazarusIDE) And Assigned(LazarusIDE.ActiveProject) And
      (Not LazarusIDE.ActiveProject.IsVirtual) Then
      Begin
        If LazarusIDE.ActiveProject.ProjectInfoFile <> '' Then
          Dlg.InitialDir := ExtractFilePath(ExpandFileName(LazarusIDE.ActiveProject.ProjectInfoFile));
      End;
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

Procedure TProjectAssistantForm.FixErrorActionExecute(Sender: TObject);
Begin
  FixSelectedError;
End;

Procedure TProjectAssistantForm.SettingsActionExecute(Sender: TObject);
Begin
  ShowAssistantSettingsForm;
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
  If (PlanRel = '') Or (Not Assigned(CodePanel)) Then
    Exit;
  If Not ResolvePlanPath(PlanRel, Resolved, Err) Then
    Exit;
  If SameFileName(ExpandFileName(FileName), ExpandFileName(Resolved)) Then
    RefreshCodeTodos;
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
      If Assigned(CodePanel) Then
        RefreshCodeTodos;
    End;
End;

End.
