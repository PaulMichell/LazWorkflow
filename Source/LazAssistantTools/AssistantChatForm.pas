Unit AssistantChatForm;

{ Project Assistant main window — mode tabs, current-turn view, status footer (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Menus, ActnList, WorkflowEvents, StatusFooterFrame, CompOptsIntf,
  IDEExternToolIntf, AssistantHistory;

Type
  TAssistantChatForm = Class(TForm, IWorkflowListener, ICompilerFinished, IMarkdownDocumentChanged)
    FActionList: TActionList;
    FNewChatAction: TAction;
    FSendAction: TAction;
    FStopAction: TAction;
    FReviewCompileAction: TAction;
    FReviewBuildAction: TAction;
    FFixErrorAction: TAction;
    FSettingsAction: TAction;
    FToggleThinkingAction: TAction;
    FPages: TPageControl;
    FTabChat: TTabSheet;
    FTabPlan: TTabSheet;
    FTabCode: TTabSheet;
    FHistoryPanel: TPanel;
    FHistoryLabel: TLabel;
    FHistorySearch: TEdit;
    FHistoryList: TListBox;
    FChatSplitter: TSplitter;
    FChatHost: TPanel;
    FPlanPlaceholder: TLabel;
    FCodePlaceholder: TLabel;
    FBottomBar: TPanel;
    FBtnNewChat: TButton;
    FBtnToggleThinking: TButton;
    FBtnReviewCompile: TButton;
    FBtnReviewBuild: TButton;
    FBtnFixError: TButton;
    FBtnSettings: TButton;
    FStatusFooter: TStatusFooterFrame;
    FInputPanel: TPanel;
    FSendButton: TButton;
    FStopButton: TButton;
    FInputEdit: TMemo;
    Procedure FormCreate(Sender: TObject);
    Procedure FormDestroy(Sender: TObject);
    Procedure PagesChange(Sender: TObject);
    Procedure HistorySearchChange(Sender: TObject);
    Procedure HistoryListClick(Sender: TObject);
    Procedure HistoryListSelectionChange(Sender: TObject; User: Boolean);
    Procedure SendActionExecute(Sender: TObject);
    Procedure StopActionExecute(Sender: TObject);
    Procedure NewChatActionExecute(Sender: TObject);
    Procedure ReviewCompileActionExecute(Sender: TObject);
    Procedure ReviewBuildActionExecute(Sender: TObject);
    Procedure FixErrorActionExecute(Sender: TObject);
    Procedure SettingsActionExecute(Sender: TObject);
    Procedure ToggleThinkingActionExecute(Sender: TObject);
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
    FUserCancelled: Boolean;
    FAssistantContent: String; { Final answer channel (API history). }
    FAssistantThinking: String; { Reasoning stream (display optional). }
    FReviewInProgress: Boolean;
    FStreamStart: TDateTime;
    FTurnStartedAt: String;
    FStatusPhase: String; { e.g. Thinking… / Streaming… while FSending. }
    FLastChatPaintTick: QWord;
    FSessionProjectKey: String; { ProjectInfoFile used for last save/load. }
    Procedure UpdateThinkingActionCaption;
    Procedure ClearCurrentTurnDisplay;
    Procedure SetCurrentUserDisplay(Const UserText: String; Const WithIdeContext: Boolean);
    Procedure SetCurrentSystemNote(Const NoteText: String);
    Procedure EnsureHistoryStore;
    Procedure RefreshHistoryList;
    Procedure ShowHistoryTurn(TurnIndex: Integer);
    Procedure ShowLastHistoryTurn;
    Procedure RecordCurrentTurn(Const ErrorText: String);
    Function CurrentModeFromTabs: TAssistantMode;
    Procedure ApplyActiveMode;
    Function HistoryListTurnIndex(ListIndex: Integer): Integer;
    Procedure UpdateStatusFooter;
    Function FormatElapsedStatus(Const Phase: String): String;
    Procedure SetStreamPhase(Const Phase: String);
    Procedure SetSending(IsSending: Boolean);
    Procedure ElapsedTimerTimer(Sender: TObject);
    Procedure EnsureChatView;
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
    Function BuildFixErrorPromptForLine(Line: TMessageLine): String;
    Procedure SubmitUserText(Const UserText: String; AutoSend: Boolean);
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
  End;

Implementation

{$R *.lfm}

Uses
  WorkflowLog, AssistantService, AssistantConfig, AssistantSettingsForm, AssistantIDEContext, AssistantSession,
  LazFileUtils, LazIDEIntf, IDEMsgIntf, MarkDown.Control, SrcEditorIntf, ProjectIntf;

Const
  ChatViewMargin = 4;
  ChatPaintMinIntervalMs = 80;

Constructor TAssistantChatForm.Create(TheOwner: TComponent);
Begin
  Inherited Create(TheOwner);
  FModelName := AssistantConfigDefaultModel;
  FContextUsed := 0;
  FContextLimit := 128000;
  FSending := False;
  FStreamingActive := False;
  FUserCancelled := False;
  FAssistantContent := '';
  FAssistantThinking := '';
  FDisplayUser := '';
  FDisplaySystemNote := '';
  FShowThinking := True;
  FActiveMode := amChat;
  FReviewInProgress := False;
  FStreamStart := 0;
  FTurnStartedAt := '';
  FStatusPhase := '';
  FLastChatPaintTick := 0;
  FSessionProjectKey := '';
  FChatView := Nil;
  FTranscript := TStringList.Create;
  WorkflowEventBus.AddListener(Self);
End;

Destructor TAssistantChatForm.Destroy;
Begin
  If Assigned(AssistantClient) Then
    AssistantClient.CancelStream;
  PersistSession;
  WorkflowEventBus.RemoveListener(Self);
  FreeAndNil(FTranscript);
  Inherited Destroy;
End;

Procedure TAssistantChatForm.FormCreate(Sender: TObject);
Begin
  Caption := 'Project Assistant';
  EnsureChatView;
  UpdateThinkingActionCaption;
  If Not Assigned(FElapsedTimer) Then
    Begin
      FElapsedTimer := TTimer.Create(Self);
      FElapsedTimer.Enabled := False;
      FElapsedTimer.Interval := 250;
      FElapsedTimer.OnTimer := @ElapsedTimerTimer;
    End;
  EnsureHistoryStore;
  RefreshFromConfig;
  UpdateStatusFooter;
  ApplyActiveMode;
  { Restore API conversation context without painting a "session loaded" banner. }
  RestoreSessionIfNeeded;
  RefreshHistoryList;
  { Always open on the latest history turn when present. }
  ShowLastHistoryTurn;
  WorkflowLogger.Info('AssistantChat', 'Project Assistant window created');
End;

Procedure TAssistantChatForm.FormDestroy(Sender: TObject);
Begin
  If Assigned(FElapsedTimer) Then
    FElapsedTimer.Enabled := False;
  SetBusyCursor(False);
  WorkflowLogger.Info('AssistantChat', 'Project Assistant window destroyed');
End;

Procedure TAssistantChatForm.UpdateThinkingActionCaption;
Begin
  If Not Assigned(FToggleThinkingAction) Then
    Exit;
  If FShowThinking Then
    FToggleThinkingAction.Caption := 'Hide Thinking'
  Else
    FToggleThinkingAction.Caption := 'Show Thinking';
End;

Procedure TAssistantChatForm.ClearCurrentTurnDisplay;
Begin
  FDisplayUser := '';
  FDisplaySystemNote := '';
  FAssistantContent := '';
  FAssistantThinking := '';
  FStreamingActive := False;
End;

Procedure TAssistantChatForm.SetCurrentUserDisplay(Const UserText: String; Const WithIdeContext: Boolean);
Begin
  FDisplaySystemNote := '';
  If WithIdeContext Then
    FDisplayUser := UserText + LineEnding + LineEnding +
      '*(IDE context attached for the model: active editor + project files.)*'
  Else
    FDisplayUser := UserText;
End;

Procedure TAssistantChatForm.SetCurrentSystemNote(Const NoteText: String);
Begin
  FDisplaySystemNote := NoteText;
  RefreshChatDisplay(True, False);
End;

Procedure TAssistantChatForm.SetBusyCursor(IsBusy: Boolean);
Begin
  { crAppStart is the classic pointer+hourglass "busy but usable" cursor. }
  If IsBusy Then
    Screen.Cursor := crAppStart
  Else
    Screen.Cursor := crDefault;
End;

Function TAssistantChatForm.CurrentModeFromTabs: TAssistantMode;
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

Procedure TAssistantChatForm.ApplyActiveMode;
Begin
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
      End;
  Else
    Begin
      FReviewCompileAction.Enabled := Not FSending;
      FReviewBuildAction.Enabled := Not FSending;
      FFixErrorAction.Enabled := Not FSending;
    End;
  End;
End;

Procedure TAssistantChatForm.PagesChange(Sender: TObject);
Begin
  If FSending Then
    Begin
      { Keep mode stable while a stream is in flight. }
      Case FActiveMode Of
        amPlan: FPages.ActivePage := FTabPlan;
        amCode: FPages.ActivePage := FTabCode;
      Else
        FPages.ActivePage := FTabChat;
      End;
      Exit;
    End;
  ApplyActiveMode;
  If Assigned(FPages) And Assigned(FPages.ActivePage) Then
    WorkflowLogger.Info('AssistantChat', 'Mode tab: ' + FPages.ActivePage.Caption);
  RefreshHistoryList;
End;

Procedure TAssistantChatForm.EnsureHistoryStore;
Var
  Root: String;
  ShowThinking: Boolean;
Begin
  If Not Assigned(ProjectAssistantHistory) Then
    Exit;
  Root := ProjectAssistantRoot;
  If Root = '' Then
    Exit;
  If Not SameFileName(ExcludeTrailingPathDelimiter(ProjectAssistantHistory.ProjectRoot),
    ExcludeTrailingPathDelimiter(Root)) Then
    Begin
      ProjectAssistantHistory.SetProjectRoot(Root);
      ProjectAssistantHistory.Load; { one bulk parse into memory }
      If ProjectAssistantHistory.LoadShowThinking(ShowThinking) Then
        Begin
          FShowThinking := ShowThinking;
          UpdateThinkingActionCaption;
        End;
    End
  Else If Not ProjectAssistantHistory.Loaded Then
    ProjectAssistantHistory.Load;
End;

Function TAssistantChatForm.HistoryListTurnIndex(ListIndex: Integer): Integer;
Begin
  { Objects store TurnIndex+1 so index 0 is never stored as Nil. }
  Result := -1;
  If Not Assigned(FHistoryList) Or (ListIndex < 0) Or (ListIndex >= FHistoryList.Items.Count) Then
    Exit;
  Result := Integer(PtrUInt(FHistoryList.Items.Objects[ListIndex]));
  If Result > 0 Then
    Dec(Result)
  Else
    Result := -1;
End;

Procedure TAssistantChatForm.ShowHistoryTurn(TurnIndex: Integer);
Var
  Prompt, Response, Thinking, ErrorText: String;
Begin
  If Not Assigned(ProjectAssistantHistory) Then
    Exit;
  If Not ProjectAssistantHistory.GetTurnDisplay(TurnIndex, Prompt, Response, Thinking, ErrorText) Then
    Begin
      WorkflowLogger.Warning('AssistantChat', 'ShowHistoryTurn failed idx=' + IntToStr(TurnIndex) +
        ' ' + ProjectAssistantHistory.LastError);
      Exit;
    End;
  FDisplayUser := Prompt;
  FAssistantContent := Response;
  FAssistantThinking := Thinking;
  If ErrorText <> '' Then
    FDisplaySystemNote := '**Error:** ' + ErrorText
  Else
    FDisplaySystemNote := '';
  FStreamingActive := False;
  RefreshChatDisplay(True, False);
End;

Procedure TAssistantChatForm.ShowLastHistoryTurn;
Var
  N: Integer;
Begin
  If Not Assigned(ProjectAssistantHistory) Then
    Begin
      RefreshChatDisplay(True, False);
      Exit;
    End;
  N := ProjectAssistantHistory.TurnCount;
  If N > 0 Then
    ShowHistoryTurn(N - 1)
  Else
    Begin
      ClearCurrentTurnDisplay;
      RefreshChatDisplay(True, False);
    End;
End;

Procedure TAssistantChatForm.RefreshHistoryList;
Var
  I, SeqNo, KeepTurnIndex: Integer;
  Entry: THistoryIndexEntry;
  Filter, Line: String;
  ShowItem: Boolean;
  SelectIdx: Integer;
Begin
  If Not Assigned(FHistoryList) Or Not Assigned(ProjectAssistantHistory) Then
    Exit;
  EnsureHistoryStore;
  Filter := '';
  If Assigned(FHistorySearch) Then
    Filter := LowerCase(Trim(FHistorySearch.Text));
  KeepTurnIndex := HistoryListTurnIndex(FHistoryList.ItemIndex);
  SelectIdx := -1;
  FHistoryList.Items.BeginUpdate;
  Try
    FHistoryList.Clear;
    { Oldest first so new turns append at the bottom (grow down).
      Objects store TurnIndex+1 (never 0/Nil) for O(1) memory retrieval. }
    For I := 0 To ProjectAssistantHistory.IndexCount - 1 Do
      Begin
        Entry := ProjectAssistantHistory.IndexEntry(I);
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
            FHistoryList.Items.AddObject(Line, TObject(PtrUInt(Entry.TurnIndex + 1)));
            If Entry.TurnIndex = KeepTurnIndex Then
              SelectIdx := FHistoryList.Items.Count - 1;
          End;
      End;
  Finally
    FHistoryList.Items.EndUpdate;
  End;
  If FHistoryList.Items.Count > 0 Then
    Begin
      If SelectIdx < 0 Then
        SelectIdx := FHistoryList.Items.Count - 1;
      FHistoryList.ItemIndex := SelectIdx;
      FHistoryList.TopIndex := SelectIdx;
    End;
End;

Procedure TAssistantChatForm.HistorySearchChange(Sender: TObject);
Begin
  RefreshHistoryList;
End;

Procedure TAssistantChatForm.HistoryListClick(Sender: TObject);
Begin
  HistoryListSelectionChange(Sender, True);
End;

Procedure TAssistantChatForm.HistoryListSelectionChange(Sender: TObject; User: Boolean);
Var
  TurnIndex: Integer;
Begin
  If FSending Then
    Exit;
  If Not Assigned(FHistoryList) Or (FHistoryList.ItemIndex < 0) Then
    Exit;
  TurnIndex := HistoryListTurnIndex(FHistoryList.ItemIndex);
  If TurnIndex < 0 Then
    Exit;
  ShowHistoryTurn(TurnIndex);
End;

Procedure TAssistantChatForm.RecordCurrentTurn(Const ErrorText: String);
Var
  Turn: THistoryTurn;
  Entry: THistoryIndexEntry;
  DurationMs: Integer;
Begin
  If Not Assigned(ProjectAssistantHistory) Then
    Exit;
  EnsureHistoryStore;
  If ProjectAssistantHistory.ProjectRoot = '' Then
    Exit;
  If (Trim(FDisplayUser) = '') And (Trim(FAssistantContent) = '') And (Trim(ErrorText) = '') Then
    Exit;
  DurationMs := 0;
  If FStreamStart > 0 Then
    DurationMs := Round((Now - FStreamStart) * 24 * 60 * 60 * 1000);
  Turn.Id := NewHistoryTurnId;
  Turn.Mode := AssistantModeToStr(FActiveMode);
  Turn.Prompt := FDisplayUser;
  Turn.Thinking := FAssistantThinking;
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
  Turn.PlanFile := '';
  Turn.TodoId := '';
  If ProjectAssistantHistory.AppendTurn(Turn, Entry) Then
    RefreshHistoryList
  Else
    WorkflowLogger.Warning('AssistantChat', 'History append failed: ' + ProjectAssistantHistory.LastError);
End;

Procedure TAssistantChatForm.ToggleThinkingActionExecute(Sender: TObject);
Begin
  FShowThinking := Not FShowThinking;
  UpdateThinkingActionCaption;
  If Assigned(ProjectAssistantHistory) And (ProjectAssistantHistory.ProjectRoot <> '') Then
    ProjectAssistantHistory.SaveShowThinking(FShowThinking);
  RefreshChatDisplay(True);
End;

Function TAssistantChatForm.FormatElapsedStatus(Const Phase: String): String;
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

Procedure TAssistantChatForm.SetStreamPhase(Const Phase: String);
Begin
  FStatusPhase := Phase;
  FStatusFooter.SetRightText(FormatElapsedStatus(Phase));
End;

Procedure TAssistantChatForm.ElapsedTimerTimer(Sender: TObject);
Begin
  If FSending And (FStatusPhase <> '') Then
    FStatusFooter.SetRightText(FormatElapsedStatus(FStatusPhase));
End;

Procedure TAssistantChatForm.RefreshFromConfig;
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

Procedure TAssistantChatForm.UpdateStatusFooter;
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

Procedure TAssistantChatForm.SetSending(IsSending: Boolean);
Begin
  FSending := IsSending;
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

Procedure TAssistantChatForm.PersistSession;
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

Procedure TAssistantChatForm.RestoreSessionIfNeeded;
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
    The visible turn comes from history (ShowLastHistoryTurn). }
  If LoadProjectChatSession(FTranscript, LoadedContext) Then
    Begin
      FContextUsed := LoadedContext;
      UpdateStatusFooter;
    End;
End;

Procedure TAssistantChatForm.EnsureChatView;
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
  View.Visible := True;
  FChatView := View;
End;

Procedure TAssistantChatForm.ScrollChatToEnd;
Var
  View: TMarkDownControl;
Begin
  If Not Assigned(FChatView) Then
    Exit;
  View := TMarkDownControl(FChatView);
  { Setter clamps to max scroll. }
  View.ScrolledTop := High(Integer) Div 4;
End;

Procedure TAssistantChatForm.ScrollChatToTop;
Var
  View: TMarkDownControl;
Begin
  If Not Assigned(FChatView) Then
    Exit;
  View := TMarkDownControl(FChatView);
  View.ScrolledTop := 0;
End;

Procedure TAssistantChatForm.RefreshChatDisplay(Force: Boolean; ScrollToBottom: Boolean);
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
    View.MarkDown.BeginUpdate;
    Try
      { Force a content change so the control always re-parses when stepping history. }
      If View.MarkDown.Text = Body Then
        View.MarkDown.Text := Body + ' '
      Else
        View.MarkDown.Text := '';
      View.MarkDown.Text := Body;
    Finally
      View.MarkDown.EndUpdate;
    End;
  Except
    On E: Exception Do
      WorkflowLogger.Warning('AssistantChat', 'Chat Markdown render failed: ' + E.Message);
  End;
  If ScrollToBottom Then
    ScrollChatToEnd
  Else
    ScrollChatToTop;
End;

Function TAssistantChatForm.RoleHeading(Const Role: String): String;
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

Function TAssistantChatForm.QuoteMarkdownLines(Const TextValue: String): String;
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

Function TAssistantChatForm.FormatAssistantMarkdown(Const Thinking, Content: String): String;
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

Procedure TAssistantChatForm.AppendMessage(Const Role, Content: String);
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

Procedure TAssistantChatForm.BeginAssistantReply;
Begin
  FAssistantContent := '';
  FAssistantThinking := '';
  FUserCancelled := False;
  FStreamingActive := True;
  FLastChatPaintTick := 0;
  FTurnStartedAt := IsoNowUtc;
  RefreshChatDisplay(True);
End;

Procedure TAssistantChatForm.ApplyAssistantSnapshots(Const ContentSnapshot, ThinkingSnapshot: String);
Begin
  If Not FStreamingActive Then
    BeginAssistantReply;
  FAssistantContent := ContentSnapshot;
  FAssistantThinking := ThinkingSnapshot;
  If FAssistantContent <> '' Then
    SetStreamPhase('Streaming…')
  Else If FAssistantThinking <> '' Then
    SetStreamPhase('Thinking…')
  Else
    SetStreamPhase('Waiting for first token…');
  RefreshChatDisplay(False);
End;

Procedure TAssistantChatForm.FinishAssistantReply(Const ErrorText: String);
Var
  DisplayBody: String;
Begin
  If FUserCancelled Then
    Begin
      { StopStream already cleaned UI and cancelled the worker. }
      FUserCancelled := False;
      If Assigned(AssistantClient) Then
        AssistantClient.MarkStreamComplete;
      SetSending(False);
      Exit;
    End;
  If FStreamingActive Then
    Begin
      If (ErrorText <> '') And (FAssistantContent = '') And (FAssistantThinking = '') Then
        DisplayBody := '*(error)*'
      Else
        DisplayBody := FormatAssistantMarkdown(FAssistantThinking, FAssistantContent);
      If FTranscript.Count > 0 Then
        FTranscript.Add('');
      FTranscript.Add('### Assistant');
      FTranscript.Add('');
      FTranscript.Add(DisplayBody);
    End;

  If ErrorText <> '' Then
    Begin
      FDisplaySystemNote := '**Error:** ' + ErrorText;
      FStatusFooter.SetRightText('Error');
    End
  Else
    Begin
      { Full conversation for the API lives on AssistantClient (all prior turns). }
      If Assigned(AssistantClient) And (FAssistantContent <> '') Then
        AssistantClient.AddMessage(amrAssistant, FAssistantContent);
      FContextUsed := FContextUsed + Length(FAssistantContent) Div 4 + 20;
      If FAssistantThinking <> '' Then
        FContextUsed := FContextUsed + Length(FAssistantThinking) Div 4;
      FStatusFooter.SetRightText('Ready');
    End;
  FStreamingActive := False;
  { Keep FAssistantContent / thinking on the current-turn surface until the next send. }
  RecordCurrentTurn(ErrorText);
  RefreshChatDisplay(True);
  If Assigned(AssistantClient) Then
    AssistantClient.MarkStreamComplete;
  SetSending(False);
  PersistSession;
End;

Procedure TAssistantChatForm.StreamToken(Const ContentSnapshot, ThinkingSnapshot: String;
  IsFinished: Boolean; Const ErrorText: String);
Begin
  { Invoked on the main thread via Synchronize from the stream worker.
    Thinking streams first on reasoning models; content is the final answer. }
  If FUserCancelled Then
    Begin
      If IsFinished Then
        Begin
          FUserCancelled := False;
          If Assigned(AssistantClient) Then
            AssistantClient.MarkStreamComplete;
          SetSending(False);
        End;
      Exit;
    End;
  If Not IsFinished Then
    Begin
      ApplyAssistantSnapshots(ContentSnapshot, ThinkingSnapshot);
      { Non-empty ErrorText while still streaming is a status phase (e.g. tool round). }
      If ErrorText <> '' Then
        SetStreamPhase(ErrorText);
      Exit;
    End;
  { Final empty emit may still carry last snapshots already applied. }
  If (ContentSnapshot <> '') Or (ThinkingSnapshot <> '') Then
    ApplyAssistantSnapshots(ContentSnapshot, ThinkingSnapshot);
  FinishAssistantReply(ErrorText);
End;

Procedure TAssistantChatForm.StopStream;
Var
  DisplayBody: String;
Begin
  If Not FSending Then
    Exit;
  FUserCancelled := True;
  If Assigned(AssistantClient) Then
    AssistantClient.CancelStream;
  If FStreamingActive Then
    Begin
      If (FAssistantContent <> '') Or (FAssistantThinking <> '') Then
        Begin
          DisplayBody := FormatAssistantMarkdown(FAssistantThinking, FAssistantContent) +
            LineEnding + LineEnding + '*[stream cancelled]*';
          If FTranscript.Count > 0 Then
            FTranscript.Add('');
          FTranscript.Add('### Assistant');
          FTranscript.Add('');
          FTranscript.Add(DisplayBody);
          If Assigned(AssistantClient) And (FAssistantContent <> '') Then
            AssistantClient.AddMessage(amrAssistant, FAssistantContent);
          FContextUsed := FContextUsed + Length(FAssistantContent) Div 4 + 20;
          FDisplaySystemNote := '*Stream cancelled.*';
        End
      Else
        FDisplaySystemNote := '*Stream cancelled before the first token.*';
    End
  Else
    FDisplaySystemNote := '*Stream cancelled.*';
  FStreamingActive := False;
  RecordCurrentTurn('cancelled');
  RefreshChatDisplay(True);
  SetSending(False);
  FStatusFooter.SetRightText('Cancelled');
  PersistSession;
  WorkflowLogger.Info('AssistantChat', 'Stream cancelled by user');
End;

Procedure TAssistantChatForm.SubmitUserText(Const UserText: String; AutoSend: Boolean);
Var
  ApiText, ContextBlock: String;
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
      ApplyActiveMode;
      ApiText := UserText;
      WithContext := Assigned(AssistantChatConfig) And AssistantChatConfig.IncludeIDEContext;
      SetCurrentUserDisplay(UserText, WithContext);
      FAssistantContent := '';
      FAssistantThinking := '';
      If WithContext Then
        Begin
          ContextBlock := BuildIDEContextBlock;
          ApiText := UserText + LineEnding + LineEnding + ContextBlock;
        End;
      AppendMessage('user', FDisplayUser);
      { Prior turns already on AssistantClient are sent with this request (full context). }
      AssistantClient.AddMessage(amrUser, ApiText);
      FContextUsed := FContextUsed + Length(ApiText) Div 4 + 8;
      BeginAssistantReply;
      FStatusPhase := 'Waiting for first token…';
      SetSending(True);
      { Large skill + IDE context means a noticeable wait before the first token.
        That gap is model/server time-to-first-token, not local UI hang. }
      If Not AssistantClient.StartStream(@StreamToken) Then
        FinishAssistantReply(AssistantClient.LastError);
    End
  Else
    AppendMessage('user', UserText);
End;

Procedure TAssistantChatForm.SendActionExecute(Sender: TObject);
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

Procedure TAssistantChatForm.StopActionExecute(Sender: TObject);
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

Function TAssistantChatForm.CollectIDEMessagesText(Out ErrorCount, WarningCount, HintCount: Integer): String;
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

Function TAssistantChatForm.BuildReviewPrompt(Const KindLabel, OutputText: String;
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
    KindLabel + ' output for review:' + LineEnding +
    LineEnding +
    'Project: ' + ProjectName + LineEnding +
    'Outcome: ' + Outcome +
      Format(' — errors=%d, warnings=%d, hints/notes=%d', [ErrorCount, WarningCount, HintCount]) +
      LineEnding +
    LineEnding +
    '----- begin compiler/messages output -----' + LineEnding +
    OutputText + LineEnding +
    '----- end compiler/messages output -----' + LineEnding +
    LineEnding +
    'You are reviewing Free Pascal / Lazarus IDE ' + LowerCase(KindLabel) +
    ' output from my local machine (same text as the Messages window).' + LineEnding +
    'If there are errors: explain them briefly and propose concrete fixes (file, location, and change).' + LineEnding +
    'If there are warnings or hints: address only those that are practical and useful; ignore pure noise.' + LineEnding +
    'If the ' + LowerCase(KindLabel) + ' is clean (no errors and no actionable warnings), say so briefly — no further action is required.';
End;

Procedure TAssistantChatForm.ReviewProject(Reason: TCompileReason; Const KindLabel: String);
Var
  BuildResult: TModalResult;
  OutputText, PromptText: String;
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
  WorkflowLogger.Info('AssistantChat', 'Review ' + KindLabel + ' started');

  Try
    BuildResult := LazarusIDE.DoBuildProject(Reason, []);
    BuildOk := BuildResult = mrOk;
    OutputText := CollectIDEMessagesText(ErrorCount, WarningCount, HintCount);
    PromptText := BuildReviewPrompt(KindLabel, OutputText, ErrorCount, WarningCount, HintCount, BuildOk);

    If BuildOk And (ErrorCount = 0) Then
      FStatusFooter.SetRightText(KindLabel + ' OK')
    Else If ErrorCount > 0 Then
      FStatusFooter.SetRightText(KindLabel + ' failed')
    Else
      FStatusFooter.SetRightText(KindLabel + ' done');

    SubmitUserText(PromptText, True);
  Finally
    FReviewInProgress := False;
    If Not FSending Then
      Begin
        FReviewCompileAction.Enabled := True;
        FReviewBuildAction.Enabled := True;
        UpdateStatusFooter;
      End;
  End;
End;

Procedure TAssistantChatForm.ReviewCompile;
Begin
  ReviewProject(crCompile, 'Compile');
End;

Procedure TAssistantChatForm.ReviewBuild;
Begin
  ReviewProject(crBuild, 'Build');
End;

Procedure TAssistantChatForm.StartNewChat;
Begin
  If FSending Then
    StopStream;
  SetSending(False);
  FTranscript.Clear;
  FContextUsed := 0;
  FUserCancelled := False;
  FLastChatPaintTick := 0;
  ClearCurrentTurnDisplay;
  If Assigned(AssistantClient) Then
    AssistantClient.ClearHistory;
  ClearProjectChatSession;
  SetCurrentSystemNote('New conversation started. Model context cleared.');
  PersistSession;
  UpdateStatusFooter;
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

Function TAssistantChatForm.BuildFixErrorPromptForLine(Line: TMessageLine): String;
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

Procedure TAssistantChatForm.FixSelectedError;
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

Procedure TAssistantChatForm.NewChatActionExecute(Sender: TObject);
Begin
  StartNewChat;
End;

Procedure TAssistantChatForm.ReviewCompileActionExecute(Sender: TObject);
Begin
  ReviewCompile;
End;

Procedure TAssistantChatForm.ReviewBuildActionExecute(Sender: TObject);
Begin
  ReviewBuild;
End;

Procedure TAssistantChatForm.FixErrorActionExecute(Sender: TObject);
Begin
  FixSelectedError;
End;

Procedure TAssistantChatForm.SettingsActionExecute(Sender: TObject);
Begin
  ShowAssistantSettingsForm;
  RefreshFromConfig;
End;

Procedure TAssistantChatForm.CompilerFinished(Const ProjectFile: String; Result: TCompilerResult;
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
    WorkflowLogger.Debug('AssistantChat', 'CompilerFinished for ' + ProjectFile);
  UpdateStatusFooter;
End;

Procedure TAssistantChatForm.DocumentChanged(Const FileName: String; Const NewContent: String);
Begin
  WorkflowLogger.Debug('AssistantChat', 'Document changed: ' + FileName);
End;

Procedure TAssistantChatForm.DocumentSaved(Const FileName: String);
Begin
  WorkflowLogger.Debug('AssistantChat', 'Document saved: ' + FileName);
End;

End.
