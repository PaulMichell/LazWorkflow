Unit ProjectAssistantForm;

{ Project Assistant main window — mode tabs, current-turn view, status footer (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Contnrs, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Menus, ActnList, Clipbrd, WorkflowEvents, StatusFooterFrame, CompOptsIntf,
  IDEExternToolIntf, AssistantConversation, AssistantPlan;

Type
  TProjectAssistantForm = Class(TForm, IWorkflowListener, ICompilerFinished, IMarkdownDocumentChanged)
    FActionList: TActionList;
    FNewChatAction: TAction;
    FSendAction: TAction;
    FSendButton: TButton;
    FStopAction: TAction;
    FReviewCompileAction: TAction;
    FReviewBuildAction: TAction;
    FFixErrorAction: TAction;
    FSettingsAction: TAction;
    FStopButton: TButton;
    FToggleThinkingAction: TAction;
    FExportHistoryAction: TAction;
    FDeleteHistoryAction: TAction;
    FPages: TPageControl;
    FTabChat: TTabSheet;
    FTabPlan: TTabSheet;
    FTabCode: TTabSheet;
    FConversationPanel: TPanel;
    FHistoryLabel: TLabel;
    FHistoryCombo: TComboBox;
    FBtnExportHistory: TButton;
    FBtnDeleteHistory: TButton;
    FConversationLabel: TLabel;
    FConversationSearch: TEdit;
    FConversationList: TListBox;
    FChatSplitter: TSplitter;
    FChatHost: TPanel;
    FPlanPlaceholder: TLabel;
    FCodePlaceholder: TLabel;
    { Plan tab (created at runtime if placeholder present). }
    FPlanPanel: TPanel;
    FPlanActiveLabel: TLabel;
    FPlanList: TListBox;
    FPlanBtnNew: TButton;
    FPlanBtnOpen: TButton;
    FPlanBtnSetActive: TButton;
    FPlanBtnRefresh: TButton;
    FPlanBtnOpenDocs: TButton;
    { Code tab TODO panel (runtime). }
    FCodePanel: TPanel;
    FCodeActiveLabel: TLabel;
    FCodeTodoList: TListBox;
    FCodeBtnRefresh: TButton;
    FCodeBtnOpenPlan: TButton;
    FCodeBtnStart: TButton;
    FCodeBtnDone: TButton;
    FCodeBtnReset: TButton;
    FCodeBtnWork: TButton;
    FCodeStatusLabel: TLabel;
    FBottomBar: TPanel;
    FBtnNewChat: TButton;
    FBtnToggleThinking: TButton;
    FBtnReviewCompile: TButton;
    FBtnReviewBuild: TButton;
    FBtnFixError: TButton;
    FBtnSettings: TButton;
    FStatusFooter: TStatusFooterFrame;
    FInputPanel: TPanel;
    FInputEdit: TMemo;
    FInputPopup: TPopupMenu;
    FInputCutItem: TMenuItem;
    FInputCopyItem: TMenuItem;
    FInputPasteItem: TMenuItem;
    FInputSelectAllItem: TMenuItem;
    PromptSplitter: TSplitter;
    Procedure FormCreate(Sender: TObject);
    Procedure FormDestroy(Sender: TObject);
    Procedure PagesChange(Sender: TObject);
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
  Private
    FElapsedTimer: TTimer;
    FChatView: TControl; { TMarkDownControl created at runtime. }
    FTranscript: TStringList; { Session export / legacy; not the main UI surface. }
    FDisplayUser: String; { Current-turn user text shown in the Chat tab. }
    FDisplaySystemNote: String; { Optional system/error note for the current surface. }
    FShowThinking: Boolean;
    FActiveMode: TAssistantMode;
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
    FStreamStart: TDateTime;
    FTurnStartedAt: String;
    FStatusPhase: String; { e.g. Thinking… / Streaming… while FSending. }
    FLastChatPaintTick: QWord;
    FSessionProjectKey: String; { ProjectInfoFile used for last save/load. }
    FSelectedTurnIndex: Integer; { Conversation list selection; -2 = live in-flight row. }
    FHistoryIds: TStringList; { Parallel to FHistoryCombo; '' = current conversation. }
    FHistoryUpdating: Boolean;
    FApplyingShellConfig: Boolean; { True while restoring mode tab from config.json. }
    FModeLocked: Boolean; { True while a send uses Chat surface but keeps Plan/Code tools. }
    FCodeSections: TObjectList; { of TPlanSection for the Code TODO list (not published). }
    FCodeSelectedIndex: Integer; { Survives button clicks that clear ListBox.ItemIndex. }
    Procedure UpdateThinkingActionCaption;
    Procedure ClearCurrentTurnDisplay;
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
    Function CurrentModeFromTabs: TAssistantMode;
    Procedure SelectModeTab(Mode: TAssistantMode);
    Procedure ApplyActiveMode;
    Procedure ShowChatSurfaceKeepMode;
    Procedure LockModeForSend;
    Procedure UnlockModeAfterSend;
    Procedure PersistPlanReplyIfNeeded(Const ErrorText: String);
    Function LooksLikePlanMarkdown(Const Body: String): Boolean;
    Procedure PersistShellConfig;
    Procedure ApplyShellConfigFromStore;
    Procedure EnsurePlanTabUi;
    Procedure RefreshPlanList;
    Procedure PlanBtnNewClick(Sender: TObject);
    Procedure PlanBtnOpenClick(Sender: TObject);
    Procedure PlanBtnSetActiveClick(Sender: TObject);
    Procedure PlanBtnRefreshClick(Sender: TObject);
    Procedure PlanBtnOpenDocsClick(Sender: TObject);
    Procedure PlanListDblClick(Sender: TObject);
    Function SelectedPlanRelativePath: String;
    Procedure EnsureCodeTabUi;
    Procedure RefreshCodeTodos;
    Function SelectedCodeSectionIndex: Integer;
    Procedure SetCodeStatusFeedback(Const MessageText: String);
    Procedure SetSelectedCodeSectionStatus(NewStatus: TPlanSectionStatus);
    Procedure CodeBtnRefreshClick(Sender: TObject);
    Procedure CodeBtnOpenPlanClick(Sender: TObject);
    Procedure CodeBtnStartClick(Sender: TObject);
    Procedure CodeBtnDoneClick(Sender: TObject);
    Procedure CodeBtnResetClick(Sender: TObject);
    Procedure CodeBtnWorkClick(Sender: TObject);
    Procedure CodeWorkOnSelectedPackage;
    Function BuildCodeWorkPrompt(Const PlanRel, SectionTitle, StatusText, SectionBody: String): String;
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
    Procedure StartNewChat;
    Procedure ReviewCompile;
    Procedure ReviewBuild;
    Procedure FixSelectedError;
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
  FileUtil, LCLIntf, LazIDEIntf, IDEMsgIntf, MarkDown.Control, SrcEditorIntf,
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
  FContextLimit := 128000;
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
  FShowThinking := True;
  FActiveMode := amChat;
  FApplyingShellConfig := False;
  FModeLocked := False;
  FReviewInProgress := False;
  FStreamStart := 0;
  FTurnStartedAt := '';
  FStatusPhase := '';
  FLastChatPaintTick := 0;
  FSessionProjectKey := '';
  FChatView := Nil;
  FHistoryUpdating := False;
  FHistoryIds := TStringList.Create;
  FTranscript := TStringList.Create;
  FCodeSections := TObjectList.Create(True);
  FCodePanel := Nil;
  FCodeSelectedIndex := -1;
  WorkflowEventBus.AddListener(Self);
End;

Destructor TProjectAssistantForm.Destroy;
Begin
  If Assigned(AssistantClient) Then
    AssistantClient.CancelStream;
  PersistSession;
  WorkflowEventBus.RemoveListener(Self);
  FreeAndNil(FTranscript);
  FreeAndNil(FHistoryIds);
  FreeAndNil(FCodeSections);
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
  If Not Assigned(FElapsedTimer) Then
    Begin
      FElapsedTimer := TTimer.Create(Self);
      FElapsedTimer.Enabled := False;
      FElapsedTimer.Interval := 250;
      FElapsedTimer.OnTimer := @ElapsedTimerTimer;
    End;
  BindToActiveProject;
  WorkflowLogger.Info('ProjectAssistant', 'Project Assistant window created');
End;

Procedure TProjectAssistantForm.FormDestroy(Sender: TObject);
Begin
  If Assigned(FElapsedTimer) Then
    FElapsedTimer.Enabled := False;
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
  If Not Assigned(FToggleThinkingAction) Then
    Exit;
  If FShowThinking Then
    FToggleThinkingAction.Caption := 'Hide Thinking'
  Else
    FToggleThinkingAction.Caption := 'Show Thinking';
End;

Procedure TProjectAssistantForm.ClearCurrentTurnDisplay;
Begin
  FDisplayUser := '';
  FDisplaySystemNote := '';
  FAssistantContent := '';
  FAssistantThinking := '';
  FLiveUser := '';
  FLiveContent := '';
  FLiveThinking := '';
  FStreamingActive := False;
  FViewingLive := True;
  FSelectedTurnIndex := -1;
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

Function TProjectAssistantForm.CurrentModeFromTabs: TAssistantMode;
Begin
  Result := amChat;
  If Not Assigned(FPages) Or Not Assigned(FPages.ActivePage) Then
    Exit;
  If FPages.ActivePage = FTabPlan Then
    Result := amPlan
  Else If FPages.ActivePage = FTabCode Then
    Result := amCode
  Else
    Result := amChat;
End;

Procedure TProjectAssistantForm.SelectModeTab(Mode: TAssistantMode);
Begin
  If Not Assigned(FPages) Then
    Exit;
  FApplyingShellConfig := True;
  Try
    Case Mode Of
      amPlan:
        If Assigned(FTabPlan) Then
          FPages.ActivePage := FTabPlan;
      amCode:
        If Assigned(FTabCode) Then
          FPages.ActivePage := FTabCode;
    Else
      If Assigned(FTabChat) Then
        FPages.ActivePage := FTabChat;
    End;
  Finally
    FApplyingShellConfig := False;
  End;
  ApplyActiveMode;
End;

Procedure TProjectAssistantForm.ShowChatSurfaceKeepMode;
Begin
  { Plan/Code workspace tabs do not host the turn view. Switch the notebook to
    Chat for the reply without changing FActiveMode (Plan tools stay armed). }
  If Not Assigned(FPages) Or Not Assigned(FTabChat) Then
    Exit;
  If FPages.ActivePage = FTabChat Then
    Exit;
  FApplyingShellConfig := True;
  Try
    FPages.ActivePage := FTabChat;
  Finally
    FApplyingShellConfig := False;
  End;
  If Assigned(AssistantClient) Then
    AssistantClient.SetActiveMode(FActiveMode);
End;

Procedure TProjectAssistantForm.LockModeForSend;
Begin
  { Capture mode from the tab the user is on, then freeze it for the turn.
    SetSending(True) used to call ApplyActiveMode after the UI switched to Chat,
    which reclassified the turn as Chat and stripped Plan write tools. }
  FActiveMode := CurrentModeFromTabs;
  FModeLocked := True;
  If Assigned(AssistantClient) Then
    AssistantClient.SetActiveMode(FActiveMode);
  WorkflowLogger.Info('ProjectAssistant',
    'Mode locked for send: ' + AssistantModeToStr(FActiveMode));
End;

Procedure TProjectAssistantForm.UnlockModeAfterSend;
Begin
  FModeLocked := False;
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
  If FActiveMode <> amPlan Then
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
  If Assigned(FCodePanel) Then
    RefreshCodeTodos;
  If FViewingLive Then
    FDisplaySystemNote := '**Plan saved** to `' + GetActivePlanRelativePath +
      '` (auto-saved because the model did not call write_markdown).';
  WorkflowLogger.Info('ProjectAssistant', 'Auto-saved plan reply to ' + GetActivePlanRelativePath);
End;

Procedure TProjectAssistantForm.ApplyActiveMode;
Begin
  { When mode is locked for a send, keep FActiveMode (Plan/Code) even if the
    notebook shows Chat for the turn surface. }
  If Not FModeLocked Then
    FActiveMode := CurrentModeFromTabs;
  If Assigned(AssistantClient) Then
    AssistantClient.SetActiveMode(FActiveMode);
  Case FActiveMode Of
    amPlan:
      Begin
        FReviewCompileAction.Enabled := False;
        FReviewBuildAction.Enabled := False;
        FFixErrorAction.Enabled := False;
      End;
    amCode:
      Begin
        FReviewCompileAction.Enabled := Not FSending;
        FReviewBuildAction.Enabled := Not FSending;
        FFixErrorAction.Enabled := Not FSending;
        EnsureCodeTabUi;
        RefreshCodeTodos;
      End;
  Else
    Begin
      FReviewCompileAction.Enabled := Not FSending;
      FReviewBuildAction.Enabled := Not FSending;
      FFixErrorAction.Enabled := Not FSending;
    End;
  End;
  If FActiveMode = amPlan Then
    Begin
      EnsurePlanTabUi;
      RefreshPlanList;
    End;
End;

Procedure TProjectAssistantForm.PersistShellConfig;
Begin
  If Not Assigned(ProjectAssistantConversation) Then
    Exit;
  If ProjectAssistantConversation.ProjectRoot = '' Then
    Exit;
  If Not ProjectAssistantConversation.SaveShellConfig(FShowThinking, FActiveMode,
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
  SelectModeTab(Mode);
  RefreshPlanList;
End;

Procedure TProjectAssistantForm.EnsurePlanTabUi;
Var
  Bar: TPanel;
Begin
  If Assigned(FPlanPanel) Or (Not Assigned(FTabPlan)) Then
    Exit;
  If Assigned(FPlanPlaceholder) Then
    FPlanPlaceholder.Visible := False;

  FPlanPanel := TPanel.Create(Self);
  FPlanPanel.Parent := FTabPlan;
  FPlanPanel.Align := alClient;
  FPlanPanel.BevelOuter := bvNone;
  FPlanPanel.BorderSpacing.Around := 8;

  FPlanActiveLabel := TLabel.Create(Self);
  FPlanActiveLabel.Parent := FPlanPanel;
  FPlanActiveLabel.Align := alTop;
  FPlanActiveLabel.Caption := 'Active plan: (none)';
  FPlanActiveLabel.BorderSpacing.Bottom := 6;

  Bar := TPanel.Create(Self);
  Bar.Parent := FPlanPanel;
  Bar.Align := alTop;
  Bar.Height := 36;
  Bar.BevelOuter := bvNone;
  Bar.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  Bar.ChildSizing.ControlsPerLine := 8;
  Bar.ChildSizing.HorizontalSpacing := 6;
  Bar.ChildSizing.LeftRightSpacing := 0;
  Bar.ChildSizing.TopBottomSpacing := 2;
  Bar.BorderSpacing.Bottom := 6;

  FPlanBtnNew := TButton.Create(Self);
  FPlanBtnNew.Parent := Bar;
  FPlanBtnNew.Caption := 'New plan…';
  FPlanBtnNew.AutoSize := True;
  FPlanBtnNew.OnClick := @PlanBtnNewClick;

  FPlanBtnOpen := TButton.Create(Self);
  FPlanBtnOpen.Parent := Bar;
  FPlanBtnOpen.Caption := 'Open';
  FPlanBtnOpen.AutoSize := True;
  FPlanBtnOpen.OnClick := @PlanBtnOpenClick;

  FPlanBtnSetActive := TButton.Create(Self);
  FPlanBtnSetActive.Parent := Bar;
  FPlanBtnSetActive.Caption := 'Set active';
  FPlanBtnSetActive.AutoSize := True;
  FPlanBtnSetActive.OnClick := @PlanBtnSetActiveClick;

  FPlanBtnRefresh := TButton.Create(Self);
  FPlanBtnRefresh.Parent := Bar;
  FPlanBtnRefresh.Caption := 'Refresh';
  FPlanBtnRefresh.AutoSize := True;
  FPlanBtnRefresh.OnClick := @PlanBtnRefreshClick;

  FPlanBtnOpenDocs := TButton.Create(Self);
  FPlanBtnOpenDocs.Parent := Bar;
  FPlanBtnOpenDocs.Caption := 'Open Documents/';
  FPlanBtnOpenDocs.AutoSize := True;
  FPlanBtnOpenDocs.OnClick := @PlanBtnOpenDocsClick;

  FPlanList := TListBox.Create(Self);
  FPlanList.Parent := FPlanPanel;
  FPlanList.Align := alClient;
  FPlanList.OnDblClick := @PlanListDblClick;
End;

Function TProjectAssistantForm.SelectedPlanRelativePath: String;
Begin
  Result := '';
  If Not Assigned(FPlanList) Then
    Exit;
  If (FPlanList.ItemIndex < 0) Or (FPlanList.ItemIndex >= FPlanList.Items.Count) Then
    Exit;
  Result := FPlanList.Items[FPlanList.ItemIndex];
End;

Procedure TProjectAssistantForm.RefreshPlanList;
Var
  Paths: TStringList;
  Err: String;
  I, Sel: Integer;
  ActivePlan: String;
Begin
  If Not Assigned(FPlanList) Then
    Exit;
  ActivePlan := GetActivePlanRelativePath;
  If Assigned(FPlanActiveLabel) Then
    If ActivePlan = '' Then
      FPlanActiveLabel.Caption := 'Active plan: (none) — create one under Documents/ or Set active'
    Else
      FPlanActiveLabel.Caption := 'Active plan: ' + ActivePlan;

  Paths := Nil;
  Sel := -1;
  FPlanList.Items.BeginUpdate;
  Try
    FPlanList.Items.Clear;
    If Not ListProjectMarkdownPlans(Paths, Err) Then
      Begin
        If Err <> '' Then
          FPlanList.Items.Add('(' + Err + ')');
        Exit;
      End;
    For I := 0 To Paths.Count - 1 Do
      Begin
        FPlanList.Items.Add(Paths[I]);
        If SameText(Paths[I], ActivePlan) Then
          Sel := I;
      End;
    If Sel >= 0 Then
      FPlanList.ItemIndex := Sel
    Else If FPlanList.Items.Count > 0 Then
      FPlanList.ItemIndex := 0;
  Finally
    FPlanList.Items.EndUpdate;
    Paths.Free;
  End;
End;

Procedure TProjectAssistantForm.PlanBtnNewClick(Sender: TObject);
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
    '**. Switch to Plan mode chat on the Chat tab to refine it with the model.');
End;

Procedure TProjectAssistantForm.PlanBtnOpenClick(Sender: TObject);
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

Procedure TProjectAssistantForm.PlanBtnSetActiveClick(Sender: TObject);
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

Procedure TProjectAssistantForm.PlanBtnRefreshClick(Sender: TObject);
Begin
  RefreshPlanList;
End;

Procedure TProjectAssistantForm.PlanBtnOpenDocsClick(Sender: TObject);
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
  PlanBtnOpenClick(Sender);
End;

Procedure TProjectAssistantForm.EnsureCodeTabUi;
Var
  Bar: TPanel;
Begin
  If Assigned(FCodePanel) Or (Not Assigned(FTabCode)) Then
    Exit;
  If Assigned(FCodePlaceholder) Then
    FCodePlaceholder.Visible := False;

  FCodePanel := TPanel.Create(Self);
  FCodePanel.Parent := FTabCode;
  FCodePanel.Align := alClient;
  FCodePanel.BevelOuter := bvNone;
  FCodePanel.BorderSpacing.Around := 8;

  FCodeActiveLabel := TLabel.Create(Self);
  FCodeActiveLabel.Parent := FCodePanel;
  FCodeActiveLabel.Align := alTop;
  FCodeActiveLabel.Caption := 'Active plan: (none)';
  FCodeActiveLabel.WordWrap := True;
  FCodeActiveLabel.BorderSpacing.Bottom := 6;

  Bar := TPanel.Create(Self);
  Bar.Parent := FCodePanel;
  Bar.Align := alTop;
  Bar.Height := 36;
  Bar.BevelOuter := bvNone;
  Bar.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  Bar.ChildSizing.ControlsPerLine := 10;
  Bar.ChildSizing.HorizontalSpacing := 6;
  Bar.ChildSizing.LeftRightSpacing := 0;
  Bar.ChildSizing.TopBottomSpacing := 2;
  Bar.BorderSpacing.Bottom := 6;

  FCodeBtnRefresh := TButton.Create(Self);
  FCodeBtnRefresh.Parent := Bar;
  FCodeBtnRefresh.Caption := 'Refresh';
  FCodeBtnRefresh.AutoSize := True;
  FCodeBtnRefresh.OnClick := @CodeBtnRefreshClick;

  FCodeBtnOpenPlan := TButton.Create(Self);
  FCodeBtnOpenPlan.Parent := Bar;
  FCodeBtnOpenPlan.Caption := 'Open plan';
  FCodeBtnOpenPlan.AutoSize := True;
  FCodeBtnOpenPlan.OnClick := @CodeBtnOpenPlanClick;

  FCodeBtnStart := TButton.Create(Self);
  FCodeBtnStart.Parent := Bar;
  FCodeBtnStart.Caption := 'Start';
  FCodeBtnStart.AutoSize := True;
  FCodeBtnStart.OnClick := @CodeBtnStartClick;

  FCodeBtnDone := TButton.Create(Self);
  FCodeBtnDone.Parent := Bar;
  FCodeBtnDone.Caption := 'Done';
  FCodeBtnDone.AutoSize := True;
  FCodeBtnDone.OnClick := @CodeBtnDoneClick;

  FCodeBtnReset := TButton.Create(Self);
  FCodeBtnReset.Parent := Bar;
  FCodeBtnReset.Caption := 'Reset';
  FCodeBtnReset.AutoSize := True;
  FCodeBtnReset.OnClick := @CodeBtnResetClick;

  FCodeBtnWork := TButton.Create(Self);
  FCodeBtnWork.Parent := Bar;
  FCodeBtnWork.Caption := 'Work on this';
  FCodeBtnWork.AutoSize := True;
  FCodeBtnWork.OnClick := @CodeBtnWorkClick;

  FCodeStatusLabel := TLabel.Create(Self);
  FCodeStatusLabel.Parent := FCodePanel;
  FCodeStatusLabel.Align := alBottom;
  FCodeStatusLabel.Caption := 'Select a work package, then Start / Done / Reset.';
  FCodeStatusLabel.WordWrap := True;
  FCodeStatusLabel.BorderSpacing.Top := 6;

  FCodeTodoList := TListBox.Create(Self);
  FCodeTodoList.Parent := FCodePanel;
  FCodeTodoList.Align := alClient;
  FCodeTodoList.OnClick := @CodeTodoListClick;
  FCodeTodoList.OnDblClick := @CodeTodoListDblClick;
  FCodeTodoList.OnSelectionChange := @CodeTodoListSelectionChange;
End;

Procedure TProjectAssistantForm.RefreshCodeTodos;
Var
  PlanRel, Err: String;
  I, Keep: Integer;
  Section: TPlanSection;
  NotStarted, InProgress, Complete: Integer;
Begin
  If Not Assigned(FCodeTodoList) Then
    Exit;
  PlanRel := GetActivePlanRelativePath;
  If Assigned(FCodeActiveLabel) Then
    If PlanRel = '' Then
      FCodeActiveLabel.Caption :=
        'Active plan: (none) — set one on the Plan tab, then Refresh.'
    Else
      FCodeActiveLabel.Caption := 'Active plan: ' + PlanRel +
        '  ·  TODO tiles are scanned from ## headings + Status: lines.';

  Keep := FCodeSelectedIndex;
  If (Keep < 0) And Assigned(FCodeTodoList) Then
    Keep := FCodeTodoList.ItemIndex;
  FCodeTodoList.Items.BeginUpdate;
  Try
    FCodeTodoList.Items.Clear;
    If Assigned(FCodeSections) Then
      FCodeSections.Clear;
    If PlanRel = '' Then
      Begin
        FCodeTodoList.Items.Add('(No active plan — open the Plan tab and Set active.)');
        Exit;
      End;
    If Not ScanPlanSections(PlanRel, FCodeSections, Err) Then
      Begin
        FCodeTodoList.Items.Add('(' + Err + ')');
        Exit;
      End;
    If FCodeSections.Count = 0 Then
      Begin
        FCodeTodoList.Items.Add(
          '(No ## sections found. Add work packages with Status: not started | in progress | complete.)');
        Exit;
      End;
    NotStarted := 0;
    InProgress := 0;
    Complete := 0;
    For I := 0 To FCodeSections.Count - 1 Do
      Begin
        Section := TPlanSection(FCodeSections[I]);
        FCodeTodoList.Items.Add(FormatPlanSectionTile(Section, I));
        Case Section.Status Of
          pssNotStarted: Inc(NotStarted);
          pssInProgress: Inc(InProgress);
          pssComplete: Inc(Complete);
        Else
          { }
        End;
      End;
    If Assigned(FCodeActiveLabel) And (PlanRel <> '') Then
      FCodeActiveLabel.Caption := Format(
        'Active plan: %s  ·  %d not started · %d in progress · %d complete',
        [PlanRel, NotStarted, InProgress, Complete]);
    If (Keep >= 0) And (Keep < FCodeTodoList.Items.Count) Then
      FCodeTodoList.ItemIndex := Keep
    Else
      Begin
        { Prefer first in-progress, else first not-started. }
        FCodeTodoList.ItemIndex := 0;
        For I := 0 To FCodeSections.Count - 1 Do
          If TPlanSection(FCodeSections[I]).Status = pssInProgress Then
            Begin
              FCodeTodoList.ItemIndex := I;
              Break;
            End;
        If (FCodeTodoList.ItemIndex = 0) And (FCodeSections.Count > 0) And
          (TPlanSection(FCodeSections[0]).Status <> pssInProgress) Then
          For I := 0 To FCodeSections.Count - 1 Do
            If TPlanSection(FCodeSections[I]).Status = pssNotStarted Then
              Begin
                FCodeTodoList.ItemIndex := I;
                Break;
              End;
      End;
    FCodeSelectedIndex := FCodeTodoList.ItemIndex;
  Finally
    FCodeTodoList.Items.EndUpdate;
  End;
End;

Function TProjectAssistantForm.SelectedCodeSectionIndex: Integer;
Begin
  Result := -1;
  If Not Assigned(FCodeSections) Or (FCodeSections.Count = 0) Then
    Exit;
  { Prefer the remembered index: button clicks often clear ListBox.ItemIndex on GTK. }
  If (FCodeSelectedIndex >= 0) And (FCodeSelectedIndex < FCodeSections.Count) Then
    Result := FCodeSelectedIndex
  Else If Assigned(FCodeTodoList) And (FCodeTodoList.ItemIndex >= 0) And
    (FCodeTodoList.ItemIndex < FCodeSections.Count) Then
    Result := FCodeTodoList.ItemIndex;
End;

Procedure TProjectAssistantForm.SetCodeStatusFeedback(Const MessageText: String);
Begin
  If Assigned(FCodeStatusLabel) Then
    FCodeStatusLabel.Caption := MessageText;
  FStatusFooter.SetRightText(MessageText);
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
  { Copy title/status before RefreshCodeTodos frees FCodeSections entries. }
  SectionTitle := TPlanSection(FCodeSections[Idx]).Title;
  OldStatus := TPlanSection(FCodeSections[Idx]).Status;
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
  If Assigned(FCodeTodoList) And (Idx >= 0) And (Idx < FCodeTodoList.Items.Count) Then
    Begin
      FCodeTodoList.ItemIndex := Idx;
      FCodeSelectedIndex := Idx;
    End;
  Feedback := Format('%s → %s', [SectionTitle, PlanSectionStatusToStr(NewStatus)]);
  SetCodeStatusFeedback(Feedback);
  SetCurrentSystemNote(Format('Plan status updated: **%s** → `%s`.',
    [SectionTitle, PlanSectionStatusToStr(NewStatus)]));
End;

Procedure TProjectAssistantForm.CodeBtnRefreshClick(Sender: TObject);
Begin
  RefreshCodeTodos;
  SetCodeStatusFeedback('TODO list refreshed from plan file.');
End;

Procedure TProjectAssistantForm.CodeBtnOpenPlanClick(Sender: TObject);
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

Procedure TProjectAssistantForm.CodeBtnStartClick(Sender: TObject);
Begin
  SetSelectedCodeSectionStatus(pssInProgress);
End;

Procedure TProjectAssistantForm.CodeBtnDoneClick(Sender: TObject);
Begin
  SetSelectedCodeSectionStatus(pssComplete);
End;

Procedure TProjectAssistantForm.CodeBtnResetClick(Sender: TObject);
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
    '1. Focus only on this work package unless you need a tiny amount of neighbouring context.' + LineEnding +
    '2. Use tools sparingly and in batches: prefer `get_project_info` + `list_directory` first, ' +
    'then a few targeted `read_file` calls. Avoid many tiny tool rounds.' + LineEnding +
    '3. For inventory / review / baseline packages: deliver the result **in the chat reply** ' +
    '(tables, findings, next steps). Do **not** create extra Markdown files (no Baseline.md) ' +
    'unless I explicitly ask. Prefer one final answer over long write_markdown cycles.' + LineEnding +
    '4. For implementation packages: prefer concrete Free Pascal / Lazarus changes with file paths ' +
    'and clear steps (source-edit tools are limited — explain edits precisely when you cannot apply them).' + LineEnding +
    '5. Only use `update_markdown` on the active plan to set `Status: complete` (or a short note) ' +
    'when the package is truly finished — not for dumping the whole deliverable into the plan.' + LineEnding +
    '6. When finished, state clearly that I can mark **Done** on the Code tab.' + LineEnding +
    '7. Do not expand scope into other work packages unless blocked.' + LineEnding +
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
  Section := TPlanSection(FCodeSections[Idx]);
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
          If Assigned(FCodeTodoList) And (Idx < FCodeTodoList.Items.Count) Then
            FCodeTodoList.ItemIndex := Idx;
        End;
    End;
  If Not GetPlanSectionBody(PlanRel, Idx, Body, Err) Then
    Begin
      MessageDlg('Could not load plan section:' + LineEnding + Err, mtError, [mbOK], 0);
      Exit;
    End;
  Prompt := BuildCodeWorkPrompt(PlanRel, Title, StatusText, Body);
  { Stay in Code mode (tools + prompt) while showing the Chat turn surface. }
  FActiveMode := amCode;
  If Assigned(AssistantClient) Then
    AssistantClient.SetActiveMode(amCode);
  LockModeForSend;
  ShowChatSurfaceKeepMode;
  SetCodeStatusFeedback('Working on: ' + Title);
  SubmitUserText(Prompt, True);
  If Not FSending Then
    UnlockModeAfterSend;
End;

Procedure TProjectAssistantForm.CodeBtnWorkClick(Sender: TObject);
Begin
  CodeWorkOnSelectedPackage;
End;

Procedure TProjectAssistantForm.CodeTodoListClick(Sender: TObject);
Begin
  If Assigned(FCodeTodoList) And Assigned(FCodeSections) And
    (FCodeTodoList.ItemIndex >= 0) And
    (FCodeTodoList.ItemIndex < FCodeSections.Count) Then
    FCodeSelectedIndex := FCodeTodoList.ItemIndex;
End;

Procedure TProjectAssistantForm.CodeTodoListSelectionChange(Sender: TObject; User: Boolean);
Begin
  If Assigned(FCodeTodoList) And Assigned(FCodeSections) And
    (FCodeTodoList.ItemIndex >= 0) And
    (FCodeTodoList.ItemIndex < FCodeSections.Count) Then
    FCodeSelectedIndex := FCodeTodoList.ItemIndex;
End;

Procedure TProjectAssistantForm.CodeTodoListDblClick(Sender: TObject);
Begin
  { Double-click = work on this package (not only mark in progress). }
  CodeTodoListClick(Sender);
  CodeWorkOnSelectedPackage;
End;

Procedure TProjectAssistantForm.PagesChange(Sender: TObject);
Begin
  If FApplyingShellConfig Then
    Exit;
  If FSending Or FModeLocked Then
    Begin
      { During a send the notebook may show Chat while mode stays Plan/Code.
        Do not re-derive mode from the visible tab; keep the user on Chat surface. }
      If FModeLocked And Assigned(FTabChat) And (FPages.ActivePage <> FTabChat) Then
        Begin
          FApplyingShellConfig := True;
          Try
            FPages.ActivePage := FTabChat;
          Finally
            FApplyingShellConfig := False;
          End;
        End;
      Exit;
    End;
  ApplyActiveMode;
  PersistShellConfig;
  If Assigned(FPages) And Assigned(FPages.ActivePage) Then
    WorkflowLogger.Info('ProjectAssistant', 'Mode tab: ' + FPages.ActivePage.Caption);
  If FActiveMode = amPlan Then
    RefreshPlanList;
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
  If Not Assigned(FConversationList) Or (ListIndex < 0) Or (ListIndex >= FConversationList.Items.Count) Then
    Exit;
  Encoded := Integer(PtrUInt(FConversationList.Items.Objects[ListIndex]));
  If Encoded = 0 Then
    Exit;
  Result := Encoded - 1; { may be LiveConversationMarker (-2) }
End;

Procedure TProjectAssistantForm.ShowConversationTurn(TurnIndex: Integer);
Var
  Prompt, Response, Thinking, ErrorText: String;
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
      RefreshChatDisplay(True, FSending);
      Exit;
    End;
  FViewingLive := False;
  If Not Assigned(ProjectAssistantConversation) Then
    Exit;
  If Not ProjectAssistantConversation.GetTurnDisplay(TurnIndex, Prompt, Response, Thinking, ErrorText) Then
    Begin
      WorkflowLogger.Warning('ProjectAssistant', 'ShowConversationTurn failed idx=' + IntToStr(TurnIndex) +
        ' ' + ProjectAssistantConversation.LastError);
      Exit;
    End;
  FDisplayUser := Prompt;
  FAssistantContent := Response;
  FAssistantThinking := Thinking;
  If ErrorText <> '' Then
    FDisplaySystemNote := '**Error:** ' + ErrorText
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
  If Not Assigned(FConversationList) Or Not Assigned(ProjectAssistantConversation) Then
    Exit;
  EnsureConversationStore;
  Filter := '';
  If Assigned(FConversationSearch) Then
    Filter := LowerCase(Trim(FConversationSearch.Text));
  KeepTurnIndex := FSelectedTurnIndex;
  If KeepTurnIndex < 0 Then
    KeepTurnIndex := ConversationListTurnIndex(FConversationList.ItemIndex);
  SelectIdx := -1;
  FConversationList.Items.BeginUpdate;
  Try
    FConversationList.Clear;
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
            FConversationList.Items.AddObject(Line, TObject(PtrUInt(Entry.TurnIndex + 1)));
            If Entry.TurnIndex = KeepTurnIndex Then
              SelectIdx := FConversationList.Items.Count - 1;
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
            FConversationList.Items.AddObject(Line, TObject(PtrUInt(LiveConversationMarker + 1)));
            If (KeepTurnIndex = LiveConversationMarker) Or FViewingLive Then
              SelectIdx := FConversationList.Items.Count - 1;
          End;
      End;
  Finally
    FConversationList.Items.EndUpdate;
  End;
  If FConversationList.Items.Count > 0 Then
    Begin
      If SelectIdx < 0 Then
        SelectIdx := FConversationList.Items.Count - 1;
      FConversationList.ItemIndex := SelectIdx;
      FConversationList.TopIndex := SelectIdx;
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
  If Not Assigned(FHistoryCombo) Or Not Assigned(FHistoryIds) Then
    Exit;
  PrevId := '';
  If (FHistoryCombo.ItemIndex >= 0) And (FHistoryCombo.ItemIndex < FHistoryIds.Count) Then
    PrevId := FHistoryIds[FHistoryCombo.ItemIndex];
  FHistoryUpdating := True;
  Items := TObjectList.Create(True);
  Try
    FHistoryCombo.Items.BeginUpdate;
    Try
      FHistoryCombo.Items.Clear;
      FHistoryIds.Clear;
      If Assigned(ProjectAssistantConversation) And (ProjectAssistantConversation.ProjectRoot <> '') Then
        ProjectAssistantConversation.ListHistory(Items);
      SelectIdx := 0;
      For I := 0 To Items.Count - 1 Do
        Begin
          Hist := TConversationHistoryItem(Items[I]);
          If Not Assigned(Hist) Then
            Continue;
          FHistoryCombo.Items.Add(Hist.Title);
          FHistoryIds.Add(Hist.ArchiveId);
          If SameText(Hist.ArchiveId, PrevId) Then
            SelectIdx := FHistoryCombo.Items.Count - 1;
          If Hist.IsCurrent Then
            SelectIdx := FHistoryCombo.Items.Count - 1;
        End;
      If FHistoryCombo.Items.Count = 0 Then
        Begin
          FHistoryCombo.Items.Add('Current (empty)');
          FHistoryIds.Add('');
          SelectIdx := 0;
        End;
      If SelectIdx >= FHistoryCombo.Items.Count Then
        SelectIdx := 0;
      FHistoryCombo.ItemIndex := SelectIdx;
    Finally
      FHistoryCombo.Items.EndUpdate;
    End;
  Finally
    Items.Free;
    FHistoryUpdating := False;
  End;
  If Assigned(FExportHistoryAction) Then
    FExportHistoryAction.Enabled := (Not FSending) And Assigned(ProjectAssistantConversation) And
      ProjectAssistantConversation.HasTurns;
  If Assigned(FDeleteHistoryAction) Then
    FDeleteHistoryAction.Enabled := Not FSending;
End;

Function TProjectAssistantForm.DefaultExportFileName: String;
Var
  Stamp, Title: String;
  I: Integer;
Begin
  Stamp := FormatDateTime('yyyymmdd"-"hhnnss', Now);
  Title := 'conversation';
  If Assigned(FHistoryCombo) And (FHistoryCombo.ItemIndex >= 0) Then
    Title := FHistoryCombo.Items[FHistoryCombo.ItemIndex];
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
  FTranscript.Clear;
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
  { Allow browsing past turns while a stream continues in the background. }
  If Not Assigned(FConversationList) Or (FConversationList.ItemIndex < 0) Then
    Exit;
  TurnIndex := ConversationListTurnIndex(FConversationList.ItemIndex);
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
  DurationMs := 0;
  If FStreamStart > 0 Then
    DurationMs := Round((Now - FStreamStart) * 24 * 60 * 60 * 1000);
  Turn.Id := NewConversationTurnId;
  Turn.Mode := AssistantModeToStr(FActiveMode);
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

Procedure TProjectAssistantForm.ToggleThinkingActionExecute(Sender: TObject);
Begin
  FShowThinking := Not FShowThinking;
  UpdateThinkingActionCaption;
  PersistShellConfig;
  RefreshChatDisplay(True);
End;

Function TProjectAssistantForm.FormatElapsedStatus(Const Phase: String): String;
Var
  Secs, Mins, Rem: Integer;
Begin
  If FStreamStart <= 0 Then
    Begin
      Result := Phase;
      Exit;
    End;
  Secs := Round((Now - FStreamStart) * 24 * 60 * 60);
  If Secs < 0 Then
    Secs := 0;
  Mins := Secs Div 60;
  Rem := Secs Mod 60;
  Result := Format('%s %d:%2.2d', [Phase, Mins, Rem]);
End;

Procedure TProjectAssistantForm.SetStreamPhase(Const Phase: String);
Begin
  FStatusPhase := Phase;
  FStatusFooter.SetRightText(FormatElapsedStatus(Phase));
End;

Procedure TProjectAssistantForm.ElapsedTimerTimer(Sender: TObject);
Begin
  If FSending And (FStatusPhase <> '') Then
    FStatusFooter.SetRightText(FormatElapsedStatus(FStatusPhase));
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
  UpdateStatusFooter;
End;

Procedure TProjectAssistantForm.UpdateStatusFooter;
Var
  Pct: Integer;
  StatusText: String;
Begin
  If FContextLimit > 0 Then
    Pct := (FContextUsed * 100) Div FContextLimit
  Else
    Pct := 0;
  If FSending Then
    Begin
      If FStatusPhase = '' Then
        FStatusPhase := 'Waiting for first token…';
      StatusText := FormatElapsedStatus(FStatusPhase);
    End
  Else If FReviewInProgress Then
    StatusText := 'Reviewing…'
  Else If Assigned(AssistantChatConfig) And AssistantChatConfig.IsSignedIn Then
    StatusText := 'Ready'
  Else
    StatusText := 'Not signed in';
  If Assigned(AssistantChatConfig) And (AssistantChatConfig.ActiveSkill <> '') Then
    FStatusFooter.SetAll(
      Format('Model: %s | Skill: %s', [FModelName, AssistantChatConfig.ActiveSkill]),
      Format('Context: ~%d / %d (%d%%)', [FContextUsed, FContextLimit, Pct]),
      StatusText)
  Else
    FStatusFooter.SetAll(
      Format('Model: %s', [FModelName]),
      Format('Context: ~%d / %d (%d%%)', [FContextUsed, FContextLimit, Pct]),
      StatusText);
End;

Procedure TProjectAssistantForm.SetSending(IsSending: Boolean);
Begin
  FSending := IsSending;
  If Not IsSending Then
    FReviewInProgress := False;
  FSendAction.Enabled := Not IsSending;
  FStopAction.Enabled := IsSending;
  FNewChatAction.Enabled := Not IsSending;
  FReviewCompileAction.Enabled := (Not IsSending) And (Not FReviewInProgress);
  FReviewBuildAction.Enabled := (Not IsSending) And (Not FReviewInProgress);
  FFixErrorAction.Enabled := Not IsSending;
  FInputEdit.ReadOnly := IsSending;
  SetBusyCursor(IsSending);
  If IsSending Then
    Begin
      FStreamStart := Now;
      If FStatusPhase = '' Then
        FStatusPhase := 'Waiting for first token…';
      If Assigned(FElapsedTimer) Then
        FElapsedTimer.Enabled := True;
    End
  Else
    Begin
      If Assigned(FElapsedTimer) Then
        FElapsedTimer.Enabled := False;
      FStatusPhase := '';
      FStreamStart := 0;
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
  SaveProjectChatSession(FTranscript, FContextUsed);
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
  If LoadProjectChatSession(FTranscript, LoadedContext) Then
    Begin
      FContextUsed := LoadedContext;
      UpdateStatusFooter;
    End;
End;

Procedure TProjectAssistantForm.EnsureChatView;
Var
  View: TMarkDownControl;
Begin
  If Assigned(FChatView) Then
    Exit;
  FChatHost.Color := clWhite;
  FChatHost.ParentColor := False;
  FChatHost.ParentBackground := False;
  View := TMarkDownControl.Create(Self);
  View.Parent := FChatHost;
  View.Align := alClient;
  View.BorderSpacing.Around := ChatViewMargin;
  View.Color := clWhite;
  View.ParentColor := False;
  View.ParentBackground := False;
  View.ScrollBars := ssAutoBoth;
  View.MonoFontName := 'Monospace';
  View.FontName := 'default';
  View.TabStop := True;
  View.Visible := True;
  FChatView := View;
End;

Procedure TProjectAssistantForm.EnsureInputPopup;
Var
  Sep: TMenuItem;
Begin
  If Assigned(FInputPopup) Or (Not Assigned(FInputEdit)) Then
    Exit;
  FInputPopup := TPopupMenu.Create(Self);
  FInputPopup.OnPopup := @InputPopupPopup;
  FInputCutItem := TMenuItem.Create(FInputPopup);
  FInputCutItem.Caption := 'Cut';
  FInputCutItem.ShortCut := ShortCut(Ord('X'), [ssCtrl]);
  FInputCutItem.OnClick := @InputCutClick;
  FInputPopup.Items.Add(FInputCutItem);
  FInputCopyItem := TMenuItem.Create(FInputPopup);
  FInputCopyItem.Caption := 'Copy';
  FInputCopyItem.ShortCut := ShortCut(Ord('C'), [ssCtrl]);
  FInputCopyItem.OnClick := @InputCopyClick;
  FInputPopup.Items.Add(FInputCopyItem);
  FInputPasteItem := TMenuItem.Create(FInputPopup);
  FInputPasteItem.Caption := 'Paste';
  FInputPasteItem.ShortCut := ShortCut(Ord('V'), [ssCtrl]);
  FInputPasteItem.OnClick := @InputPasteClick;
  FInputPopup.Items.Add(FInputPasteItem);
  Sep := TMenuItem.Create(FInputPopup);
  Sep.Caption := '-';
  FInputPopup.Items.Add(Sep);
  FInputSelectAllItem := TMenuItem.Create(FInputPopup);
  FInputSelectAllItem.Caption := 'Select All';
  FInputSelectAllItem.ShortCut := ShortCut(Ord('A'), [ssCtrl]);
  FInputSelectAllItem.OnClick := @InputSelectAllClick;
  FInputPopup.Items.Add(FInputSelectAllItem);
  FInputEdit.PopupMenu := FInputPopup;
  FInputEdit.WantTabs := False;
End;

Procedure TProjectAssistantForm.InputPopupPopup(Sender: TObject);
Var
  HasSel: Boolean;
  CanEdit: Boolean;
Begin
  HasSel := Assigned(FInputEdit) And (FInputEdit.SelLength > 0);
  CanEdit := Assigned(FInputEdit) And (Not FInputEdit.ReadOnly);
  If Assigned(FInputCutItem) Then
    FInputCutItem.Enabled := HasSel And CanEdit;
  If Assigned(FInputCopyItem) Then
    FInputCopyItem.Enabled := HasSel;
  If Assigned(FInputPasteItem) Then
    FInputPasteItem.Enabled := CanEdit And Clipboard.HasFormat(CF_TEXT);
  If Assigned(FInputSelectAllItem) Then
    FInputSelectAllItem.Enabled := Assigned(FInputEdit) And (FInputEdit.GetTextLen > 0);
End;

Procedure TProjectAssistantForm.InputCutClick(Sender: TObject);
Begin
  If Assigned(FInputEdit) And (Not FInputEdit.ReadOnly) Then
    FInputEdit.CutToClipboard;
End;

Procedure TProjectAssistantForm.InputCopyClick(Sender: TObject);
Begin
  If Assigned(FInputEdit) Then
    FInputEdit.CopyToClipboard;
End;

Procedure TProjectAssistantForm.InputPasteClick(Sender: TObject);
Begin
  If Assigned(FInputEdit) And (Not FInputEdit.ReadOnly) Then
    FInputEdit.PasteFromClipboard;
End;

Procedure TProjectAssistantForm.InputSelectAllClick(Sender: TObject);
Begin
  If Assigned(FInputEdit) Then
    FInputEdit.SelectAll;
End;

Procedure TProjectAssistantForm.ScrollChatToEnd;
Var
  View: TMarkDownControl;
Begin
  If Not Assigned(FChatView) Then
    Exit;
  View := TMarkDownControl(FChatView);
  { Setter clamps to max scroll. }
  View.ScrolledTop := High(Integer) Div 4;
End;

Procedure TProjectAssistantForm.ScrollChatToTop;
Var
  View: TMarkDownControl;
Begin
  If Not Assigned(FChatView) Then
    Exit;
  View := TMarkDownControl(FChatView);
  View.ScrolledTop := 0;
End;

Procedure TProjectAssistantForm.RefreshChatDisplay(Force: Boolean; ScrollToBottom: Boolean);
Var
  View: TMarkDownControl;
  Body: String;
  NowTick: QWord;
Begin
  EnsureChatView;
  NowTick := GetTickCount64;
  If (Not Force) And FStreamingActive And (FLastChatPaintTick > 0) And
    (NowTick - FLastChatPaintTick < ChatPaintMinIntervalMs) Then
    Exit;
  FLastChatPaintTick := NowTick;

  { Current-turn surface: User first, then Assistant; optional note last. }
  Body := '';
  If FDisplayUser <> '' Then
    Body := '### User' + LineEnding + LineEnding + FDisplayUser;
  If FStreamingActive Or (FAssistantContent <> '') Or
    (FShowThinking And (FAssistantThinking <> '')) Then
    Begin
      If Body <> '' Then
        Body := Body + LineEnding + LineEnding;
      Body := Body + '### Assistant' + LineEnding + LineEnding +
        FormatAssistantMarkdown(FAssistantThinking, FAssistantContent);
    End;
  If FDisplaySystemNote <> '' Then
    Begin
      If Body <> '' Then
        Body := Body + LineEnding + LineEnding;
      Body := Body + FDisplaySystemNote;
    End;
  If Body = '' Then
    Body := '*Type a message below to start.*';

  View := TMarkDownControl(FChatView);
  Try
    { Clear selection before replacing live stream text (avoids copy AVs). }
    View.ClearSelection;
    View.MarkDown.BeginUpdate;
    Try
      { Force a content change so the control always re-parses when stepping conversation. }
      If View.MarkDown.Text = Body Then
        View.MarkDown.Text := Body + ' '
      Else
        View.MarkDown.Text := '';
      View.MarkDown.Text := Body;
    Finally
      View.MarkDown.EndUpdate;
    End;
    { TMarkDownControl can leave a stale paint until mouse-move; force layout + full repaint. }
    View.CalcLayout;
    View.Invalidate;
    View.Repaint;
    View.Update;
    If Assigned(FChatHost) Then
      Begin
        FChatHost.Invalidate;
        FChatHost.Repaint;
        FChatHost.Update;
      End;
  Except
    On E: Exception Do
      WorkflowLogger.Warning('ProjectAssistant', 'Chat Markdown render failed: ' + E.Message);
  End;
  If ScrollToBottom Then
    ScrollChatToEnd
  Else
    ScrollChatToTop;
  { Second pass after scroll so the exposed region is painted immediately. }
  If Assigned(View) Then
    Begin
      View.Invalidate;
      View.Repaint;
      View.Update;
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
  If FTranscript.Count > 0 Then
    FTranscript.Add('');
  FTranscript.Add('### ' + RoleHeading(Role));
  FTranscript.Add('');
  If Content <> '' Then
    FTranscript.Add(Content)
  Else
    FTranscript.Add('');
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
  DisplayBody: String;
Begin
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
      UnlockModeAfterSend;
      SetSending(False);
      Exit;
    End;
  { FLive* are authoritative for the completed stream (pane may be browsing elsewhere). }
  If FStreamingActive Then
    Begin
      If (ErrorText <> '') And (FLiveContent = '') And (FLiveThinking = '') Then
        DisplayBody := '*(error)*'
      Else
        DisplayBody := FormatAssistantMarkdown(FLiveThinking, FLiveContent);
      If FTranscript.Count > 0 Then
        FTranscript.Add('');
      FTranscript.Add('### Assistant');
      FTranscript.Add('');
      FTranscript.Add(DisplayBody);
    End;

  If ErrorText <> '' Then
    Begin
      If FViewingLive Then
        FDisplaySystemNote := '**Error:** ' + ErrorText;
      FStatusFooter.SetRightText('Error');
    End
  Else
    Begin
      { Full conversation for the API lives on AssistantClient (all prior turns). }
      If Assigned(AssistantClient) And (FLiveContent <> '') Then
        AssistantClient.AddMessage(amrAssistant, FLiveContent);
      FContextUsed := FContextUsed + Length(FLiveContent) Div 4 + 20;
      If FLiveThinking <> '' Then
        FContextUsed := FContextUsed + Length(FLiveThinking) Div 4;
      FStatusFooter.SetRightText('Ready');
    End;
  FStreamingActive := False;
  { Record from live buffers so a browsed-away pane still saves the real answer. }
  RecordCurrentTurn(ErrorText);
  If Assigned(AssistantClient) Then
    AssistantClient.MarkStreamComplete;
  PersistPlanReplyIfNeeded(ErrorText);
  UnlockModeAfterSend;
  { End send before list refresh so the in-flight row is not kept alongside the stored turn. }
  SetSending(False);
  If FViewingLive Then
    FSelectedTurnIndex := ProjectAssistantConversation.TurnCount - 1;
  RefreshConversationList;
  If FViewingLive Then
    Begin
      FDisplayUser := FLiveUser;
      FAssistantContent := FLiveContent;
      FAssistantThinking := FLiveThinking;
      If ErrorText <> '' Then
        FDisplaySystemNote := '**Error:** ' + ErrorText;
      { PersistPlanReplyIfNeeded may set a success note when ErrorText is empty. }
      RefreshChatDisplay(True, True);
    End;
  PersistSession;
End;

Procedure TProjectAssistantForm.StreamToken(Const ContentSnapshot, ThinkingSnapshot: String;
  IsFinished: Boolean; Const ErrorText: String);
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
  { Apply final snapshot only while still the active send (not a duplicate finish). }
  If FSending And ((ContentSnapshot <> '') Or (ThinkingSnapshot <> '')) Then
    ApplyAssistantSnapshots(ContentSnapshot, ThinkingSnapshot);
  FinishAssistantReply(ErrorText);
End;

Procedure TProjectAssistantForm.StopStream;
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
  RecordCurrentTurn('cancelled');
  FViewingLive := True;
  UnlockModeAfterSend;
  SetSending(False);
  FSelectedTurnIndex := ProjectAssistantConversation.TurnCount - 1;
  RefreshConversationList;
  RefreshChatDisplay(True, True);
  FStatusFooter.SetRightText('Cancelled');
  PersistSession;
  WorkflowLogger.Info('ProjectAssistant', 'Stream cancelled by user');
End;

Procedure TProjectAssistantForm.SubmitUserText(Const UserText: String; AutoSend: Boolean);
Var
  ApiText, ContextBlock, PlanRel: String;
  WithContext: Boolean;
Begin
  If Trim(UserText) = '' Then
    Exit;
  If FSending Then
    Exit;
  If AutoSend Then
    Begin
      If (Not Assigned(AssistantChatConfig)) Or (Not AssistantChatConfig.IsSignedIn) Then
        Begin
          AppendMessage('user', UserText);
          AppendMessage('system', 'Sign in under Settings to send this review to the Assistant.');
          Exit;
        End;
      If Not Assigned(AssistantClient) Then
        Exit;
      RefreshFromConfig;
      LockModeForSend; { freeze Plan/Code before Chat surface / SetSending }
      ShowChatSurfaceKeepMode; { turn UI on Chat tab; tools stay mode-locked }
      ApiText := UserText;
      If FActiveMode = amPlan Then
        Begin
          PlanRel := GetActivePlanRelativePath;
          If PlanRel = '' Then
            PlanRel := DefaultPlanRelativePath;
          ApiText :=
            '[SYSTEM DIRECTIVE — Plan mode] Write the plan into the project Markdown file ' +
            'using the write_markdown tool (path: "' + PlanRel +
            '"). Chat reply must be a short summary only, not the full plan body.' +
            LineEnding + LineEnding + UserText;
        End;
      WithContext := Assigned(AssistantChatConfig) And AssistantChatConfig.IncludeIDEContext;
      SetCurrentUserDisplay(UserText, WithContext);
      FLiveUser := FDisplayUser;
      FLiveContent := '';
      FLiveThinking := '';
      FAssistantContent := '';
      FAssistantThinking := '';
      If WithContext Then
        Begin
          ContextBlock := BuildIDEContextBlock;
          ApiText := ApiText + LineEnding + LineEnding + ContextBlock;
        End;
      AppendMessage('user', FDisplayUser);
      { Prior turns already on AssistantClient are sent with this request (full context). }
      AssistantClient.AddMessage(amrUser, ApiText);
      FContextUsed := FContextUsed + Length(ApiText) Div 4 + 8;
      FStatusPhase := 'Waiting for first token…';
      AssistantClient.ToolsEnabled := True;
      SetSending(True);
      BeginAssistantReply;
      { Large skill + IDE context means a noticeable wait before the first token.
        That gap is model/server time-to-first-token, not local UI hang. }
      If Not AssistantClient.StartStream(@StreamToken) Then
        FinishAssistantReply(AssistantClient.LastError);
    End
  Else
    AppendMessage('user', UserText);
End;

Procedure TProjectAssistantForm.SendActionExecute(Sender: TObject);
Var
  UserText: String;
Begin
  If FSending Then
    Exit;
  UserText := Trim(FInputEdit.Text);
  If UserText = '' Then
    Exit;
  If (Not Assigned(AssistantChatConfig)) Or (Not AssistantChatConfig.IsSignedIn) Then
    Begin
      MessageDlg('Sign in with SuperGrok / X Premium in Settings before sending.', mtInformation, [mbOK], 0);
      SettingsActionExecute(Nil);
      Exit;
    End;
  FInputEdit.Clear;
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
  FReviewCompileAction.Enabled := False;
  FReviewBuildAction.Enabled := False;
  FStatusFooter.SetRightText(KindLabel + '…');
  Application.ProcessMessages;
  WorkflowLogger.Info('ProjectAssistant', 'Review ' + KindLabel + ' started');

  Try
    BuildResult := LazarusIDE.DoBuildProject(Reason, []);
    BuildOk := BuildResult = mrOk;
    OutputText := CollectIDEMessagesText(ErrorCount, WarningCount, HintCount);
    DisplayLabel := BuildReviewDisplayLabel(KindLabel, ErrorCount, WarningCount, HintCount, BuildOk);
    PromptText := BuildReviewPrompt(KindLabel, OutputText, ErrorCount, WarningCount, HintCount, BuildOk);

    If BuildOk And (ErrorCount = 0) Then
      FStatusFooter.SetRightText(KindLabel + ' OK')
    Else If ErrorCount > 0 Then
      FStatusFooter.SetRightText(KindLabel + ' failed')
    Else
      FStatusFooter.SetRightText(KindLabel + ' done');

    { Reviews start a fresh conversation (own model context); prior chat is archived. }
    If Assigned(ProjectAssistantConversation) And (ProjectAssistantConversation.ProjectRoot <> '') Then
      Begin
        If Not ProjectAssistantConversation.StartNewConversation Then
          WorkflowLogger.Warning('ProjectAssistant', 'Review archive: ' + ProjectAssistantConversation.LastError);
      End;
    FTranscript.Clear;
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
        FReviewCompileAction.Enabled := True;
        FReviewBuildAction.Enabled := True;
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

Procedure TProjectAssistantForm.StartNewChat;
Begin
  If FSending Then
    StopStream;
  SetSending(False);
  EnsureConversationStore;
  If Assigned(ProjectAssistantConversation) And (ProjectAssistantConversation.ProjectRoot <> '') Then
    Begin
      If Not ProjectAssistantConversation.StartNewConversation Then
        WorkflowLogger.Warning('ProjectAssistant', 'StartNewConversation: ' + ProjectAssistantConversation.LastError);
    End;
  FTranscript.Clear;
  FContextUsed := 0;
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
  FTranscript.Clear;
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
  FTranscript.Clear;
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

Function TProjectAssistantForm.BuildFixErrorPromptForLine(Line: TMessageLine): String;
Var
  MsgText, FileName, Snippet: String;
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
  Result :=
    'Please fix this Free Pascal / Lazarus compiler message.' + LineEnding +
    LineEnding +
    'Message: ' + MsgText + LineEnding;
  If FileName <> '' Then
    Result := Result + 'File: ' + FileName + LineEnding;
  If LineNo > 0 Then
    Result := Result + Format('Location: line %d, column %d', [LineNo, Col]) + LineEnding;
  Result := Result + LineEnding;
  If Snippet <> '' Then
    Result := Result + Snippet + LineEnding + LineEnding;
  Result := Result +
    'Explain the error briefly, then propose a concrete fix (show the corrected code snippet).' + LineEnding +
    'Prefer the smallest change that resolves the issue.';
End;

Procedure TProjectAssistantForm.FixSelectedError;
Var
  Line: TMessageLine;
  Prompt: String;
  Col, TopLine: Integer;
Begin
  If FSending Then
    Exit;
  If Not Assigned(IDEMessagesWindow) Then
    Begin
      MessageDlg('The IDE Messages window is not available.', mtInformation, [mbOK], 0);
      Exit;
    End;
  Line := IDEMessagesWindow.GetSelectedLine;
  If Not Assigned(Line) Then
    Begin
      MessageDlg('Select a compiler message in the Messages window first, then choose Fix Error.',
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
  SubmitUserText(Prompt, True);
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
  If Not Assigned(FHistoryCombo) Or Not Assigned(FHistoryIds) Then
    Exit;
  If (FHistoryCombo.ItemIndex < 0) Or (FHistoryCombo.ItemIndex >= FHistoryIds.Count) Then
    Exit;
  ArchiveId := FHistoryIds[FHistoryCombo.ItemIndex];
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
  If Not Assigned(FHistoryCombo) Or Not Assigned(FHistoryIds) Then
    Exit;
  If (FHistoryCombo.ItemIndex < 0) Or (FHistoryCombo.ItemIndex >= FHistoryIds.Count) Then
    Exit;
  ArchiveId := FHistoryIds[FHistoryCombo.ItemIndex];
  LabelText := FHistoryCombo.Items[FHistoryCombo.ItemIndex];
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
      FTranscript.Clear;
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
      FStatusFooter.SetRightText(Format('Compile OK (%d warn)', [WarningCount]));
    crFailed:
      FStatusFooter.SetRightText(Format('Compile failed (%d err)', [ErrorCount]));
    crCancelled:
      FStatusFooter.SetRightText('Cancelled');
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
  If (PlanRel = '') Or (Not Assigned(FCodePanel)) Then
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
      If Assigned(FCodePanel) Then
        RefreshCodeTodos;
    End;
End;

End.
