Unit AssistantSettingsForm;

{ Project Assistant settings dialog (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. General, Connections, Spelling
  and Tests are one streamed form so the designer opens a single resource.
  Reviewed 2026-10: kind-specific groups stay here; no extra frame unit is in
  scope for this settings page. General groups are alTop in reverse resource
  order so the page reads Transcript, Prompt, Context, then Skills. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Menus,
  ButtonPanel, ComCtrls, Spin, AssistantConnections, AssistantCodexSettings, SpellCheckerSettingsFrame,
  AssistantTestSettingsFrame;

Type
  TAssistantSettingsForm = Class(TForm)
    SettingsPages: TPageControl;
    GeneralPage: TTabSheet;
    SkillsGroup: TGroupBox;
    SkillsHintLabel: TLabel;
    SkillsHost: TScrollBox;
    ContextGroup: TGroupBox;
    IncludeContextCheck: TCheckBox;
    AutoCompactCheck: TCheckBox;
    PromptGroup: TGroupBox;
    EnterNewlineCheck: TCheckBox;
    TranscriptGroup: TGroupBox;
    ShowThinkingCheck: TCheckBox;
    ShowToolCallsCheck: TCheckBox;
    ConnectionsPage: TTabSheet;
    ConnectionSidebar: TPanel;
    ConnectionButtons: TPanel;
    AddConnectionButton: TButton;
    RemoveConnectionButton: TButton;
    ConnectionsList: TListBox;
    ConnectionDetail: TPanel;
    IdentityPanel: TPanel;
    NameLabel: TLabel;
    ConnectionNameEdit: TEdit;
    UseConnectionButton: TButton;
    KindCaptionLabel: TLabel;
    KindValueLabel: TLabel;
    ActiveConnectionLabel: TLabel;
    DetailHost: TPanel;
    EmptyConnectionLabel: TLabel;
    GrokPanel: TScrollBox;
    GrokAccountGroup: TGroupBox;
    StatusLabel: TLabel;
    StatusValueLabel: TLabel;
    SignInButton: TButton;
    SignOutButton: TButton;
    ManualLabel: TLabel;
    ManualEdit: TEdit;
    PasteCodeButton: TButton;
    GrokModelGroup: TGroupBox;
    ModelLabel: TLabel;
    RefreshModelsButton: TButton;
    ModelList: TListBox;
    ModelHintLabel: TLabel;
    ThinkingLabel: TLabel;
    ThinkingCombo: TComboBox;
    VerbosityLabel: TLabel;
    VerbosityCombo: TComboBox;
    MaxOutputLabel: TLabel;
    MaxOutputEdit: TSpinEdit;
    SearchLabel: TLabel;
    SearchCombo: TComboBox;
    CitationsCheck: TCheckBox;
    GrokEndpointGroup: TGroupBox;
    ApiBaseLabel: TLabel;
    ApiBaseEdit: TEdit;
    GrokPermissionsGroup: TGroupBox;
    ApprovalLabel: TLabel;
    ApprovalCombo: TComboBox;
    GrokUsageGroup: TGroupBox;
    GrokUsageLabel: TLabel;
    CodexPanel: TScrollBox;
    CodexFrame: TCodexConnectionFrame;
    CodexUsageGroup: TGroupBox;
    CodexUsageLabel: TLabel;
    CompatiblePanel: TScrollBox;
    CompatibleEndpointGroup: TGroupBox;
    PresetLabel: TLabel;
    PresetCombo: TComboBox;
    CompatibleBaseLabel: TLabel;
    CompatibleBaseEdit: TEdit;
    KeySourceLabel: TLabel;
    KeySourceCombo: TComboBox;
    KeyEnvLabel: TLabel;
    KeyEnvEdit: TEdit;
    KeyValueLabel: TLabel;
    KeyValueEdit: TEdit;
    WireCaptionLabel: TLabel;
    CompatibleWireLabel: TLabel;
    TestConnectionButton: TButton;
    CompatibleStatusLabel: TLabel;
    CompatibleModelGroup: TGroupBox;
    CompatibleModelLabel: TLabel;
    CompatibleModelCombo: TComboBox;
    RefreshCompatibleButton: TButton;
    CompatibleMaxLabel: TLabel;
    CompatibleMaxOutputEdit: TSpinEdit;
    CompatiblePermissionsGroup: TGroupBox;
    CompatibleApprovalLabel: TLabel;
    CompatibleApprovalCombo: TComboBox;
    CompatibleUsageGroup: TGroupBox;
    CompatibleUsageLabel: TLabel;
    ClaudePanel: TScrollBox;
    ClaudeAccountGroup: TGroupBox;
    ClaudeExecutableLabel: TLabel;
    ClaudeRuntimeEdit: TEdit;
    ClaudeBrowseButton: TButton;
    ClaudeDetectButton: TButton;
    ClaudeSignInButton: TButton;
    ClaudeCheckButton: TButton;
    ClaudeStatusLabel: TLabel;
    ClaudeModelGroup: TGroupBox;
    ClaudeModelLabel: TLabel;
    ClaudeModelEdit: TEdit;
    ClaudePermissionsGroup: TGroupBox;
    ClaudeApprovalLabel: TLabel;
    ClaudeApprovalCombo: TComboBox;
    ClaudeUsageGroup: TGroupBox;
    ClaudeUsageLabel: TLabel;
    SpellingPage: TTabSheet;
    GlobalSpellSettings: TSpellCheckerSettingsFrame;
    TestsPage: TTabSheet;
    ProjectTestSettings: TAssistantTestSettingsFrame;
    ButtonPanel: TButtonPanel;
    AddConnectionMenu: TPopupMenu;
    GrokAccountItem: TMenuItem;
    ChatGptAccountItem: TMenuItem;
    CompatibleAccountItem: TMenuItem;
    ClaudeAccountItem: TMenuItem;
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
    Procedure FormCreate(Sender: TObject);
    Procedure AddConnectionClick(Sender: TObject);
    Procedure RemoveConnectionClick(Sender: TObject);
    Procedure ConnectionChanged(Sender: TObject);
    Procedure UseConnectionClick(Sender: TObject);
    Procedure AddGrokAccountClick(Sender: TObject);
    Procedure AddChatGptAccountClick(Sender: TObject);
    Procedure AddCompatibleAccountClick(Sender: TObject);
    Procedure AddClaudeAccountClick(Sender: TObject);
    Procedure SignInButtonClick(Sender: TObject);
    Procedure SignOutButtonClick(Sender: TObject);
    Procedure PasteCodeButtonClick(Sender: TObject);
    Procedure RefreshModelsButtonClick(Sender: TObject);
    Procedure GrokModelSelectionChange(Sender: TObject; User: Boolean);
    Procedure GrokSearchModeChange(Sender: TObject);
    Procedure CompatiblePresetChange(Sender: TObject);
    Procedure KeySourceChange(Sender: TObject);
    Procedure TestConnectionClick(Sender: TObject);
    Procedure RefreshCompatibleClick(Sender: TObject);
    Procedure ClaudeBrowseClick(Sender: TObject);
    Procedure ClaudeDetectClick(Sender: TObject);
    Procedure ClaudeSignInClick(Sender: TObject);
    Procedure ClaudeCheckClick(Sender: TObject);
  Private
    Connections: TAssistantConnections;
    SkillRows: TFPList;
    NoSkillsLabel: TLabel;
    SelectedConnection: Integer;
    FFillingModels: Boolean;
    FLoading: Boolean;
    FPlanUsageWorker: TThread;
    FPlanUsageTimer: TTimer;
    FPlanUsageClosed: Boolean;
    FPlanUsageConnectionId: String;
    Procedure EnsureStaticChoices;
    Procedure UpdateCompactAvailability;
    Procedure ClearSkillRows;
    Procedure SaveSkillModes;
    Procedure ShowConnectionKind(Const Backend: String);
    Procedure RefreshConnections;
    Procedure StoreConnection;
    Procedure ShowConnectionUsage(Item: TAssistantConnection; UsageLabel: TLabel);
    Procedure StartPlanUsageRefresh(Item: TAssistantConnection);
    Procedure PlanUsageTimerTimer(Sender: TObject);
    Procedure ReleasePlanUsageRefresh;
    Procedure LoadGrokConnection(Item: TAssistantConnection);
    Procedure LoadCompatibleConnection(Item: TAssistantConnection);
    Procedure LoadClaudeConnection(Item: TAssistantConnection);
    Procedure AddKind(Const Backend, DisplayName: String);
    Procedure RefreshGrokReasoningChoices(Const PreferredEffort: String);
    Function HasGrokRow: Boolean;
    Procedure RefreshCompatibleModels;
  Public
    Destructor Destroy; Override;
    Procedure LoadFromConfig;
    Procedure SaveToConfig;
    Procedure RefreshAuthStatus;
    Procedure PopulateSkills;
    Procedure PopulateModels(ForceRefresh: Boolean);
  End;

Procedure ShowAssistantSettingsForm;

Implementation

{$R *.lfm}

Uses
  AssistantWorkTarget, AssistantConfig, AssistantService, GrokOAuth, AssistantSkills, AssistantHttps, WorkflowLog,
  AssistantConversation, ProjectAssistantForm, AssistantXaiProvider, AssistantCompatibleClient, AssistantClaudeClient,
  AssistantUsage, AssistantAccountUsage,
  LCLIntf, LazIDEIntf, FileUtil, LazFileUtils;

Type
  { One discovered skill and its mode ticks. Controls are ownerless so the designer does not stream them. }
  TSkillModeRow = Class
    SkillName: String;
    RowPanel: TPanel;
    NameLabel: TLabel;
    InspectCheck, DocumentCheck, PlanCheck, BuildCheck, ChatCheck: TCheckBox;
    Constructor Create(Const Name: String; Host: TWinControl; RowTop, RowWidth: Integer);
    Destructor Destroy; Override;
  End;

  TPlanUsageWorker = Class(TThread)
    Connection: TAssistantConnection;
    Procedure Execute; Override;
  End;

Constructor TSkillModeRow.Create(Const Name: String; Host: TWinControl; RowTop, RowWidth: Integer);
  Procedure Place(Var Box: TCheckBox; Const ModeCaption: String; ModeLeft: Integer);
  Begin
    Box := TCheckBox.Create(Nil);
    Box.Parent := RowPanel;
    Box.SetBounds(ModeLeft, 2, 96, 24);
    Box.Caption := ModeCaption;
  End;
Begin
  Inherited Create;
  SkillName := Name;
  RowPanel := TPanel.Create(Nil);
  RowPanel.Parent := Host;
  RowPanel.BevelOuter := bvNone;
  RowPanel.SetBounds(0, RowTop, RowWidth, 28);
  RowPanel.Anchors := [akLeft, akTop, akRight];
  NameLabel := TLabel.Create(Nil);
  NameLabel.Parent := RowPanel;
  NameLabel.AutoSize := False;
  NameLabel.SetBounds(8, 6, 200, 18);
  NameLabel.Caption := Name;
  Place(InspectCheck, 'Inspect', 216);
  Place(DocumentCheck, 'Document', 316);
  Place(PlanCheck, 'Plan', 420);
  Place(BuildCheck, 'Build', 520);
  Place(ChatCheck, 'Chat', 620);
End;

Destructor TSkillModeRow.Destroy;
Begin
  FreeAndNil(InspectCheck);
  FreeAndNil(DocumentCheck);
  FreeAndNil(PlanCheck);
  FreeAndNil(BuildCheck);
  FreeAndNil(ChatCheck);
  FreeAndNil(NameLabel);
  FreeAndNil(RowPanel);
  Inherited Destroy;
End;

Procedure TPlanUsageWorker.Execute;
Var
  Snapshot: TAccountUsageSnapshot;
  ErrorText: String;
Begin
  ErrorText := '';
  ClearAccountUsageSnapshot(Snapshot);
  Try
    Try
      QueryAccountUsage(Connection, '', '', Snapshot, ErrorText);
    Except
      On E: Exception Do
        ErrorText := '';
    End;
  Finally
    Connection.Free;
  End;
End;

Procedure AddFallbackModels(List: TStrings);
Begin
  If List.IndexOf(AssistantConfigDefaultModel) < 0 Then
    List.Add(AssistantConfigDefaultModel);
  If List.IndexOf('grok-4') < 0 Then
    List.Add('grok-4');
  If List.IndexOf('grok-3') < 0 Then
    List.Add('grok-3');
End;

Procedure SelectModelInList(List: TListBox; Const ModelName: String);
Var
  I: Integer;
  Wanted: String;
Begin
  Wanted := XaiModelIdFromDisplay(ModelName);
  If Wanted = '' Then
    Exit;
  For I := 0 To List.Items.Count - 1 Do
    If SameText(XaiModelIdFromDisplay(List.Items[I]), Wanted) Then
      Begin
        List.ItemIndex := I;
        Exit;
      End;
  List.Items.Insert(0, XaiModelDisplayText(Wanted));
  List.ItemIndex := 0;
End;

Procedure DecorateModelList(List: TStrings);
Var
  I: Integer;
Begin
  For I := 0 To List.Count - 1 Do
    List[I] := XaiModelDisplayText(XaiModelIdFromDisplay(List[I]));
End;

Function EffortFromCaption(Const Caption: String): String;
Begin
  If SameText(Caption, 'Low') Then
    Result := 'low'
  Else If SameText(Caption, 'Medium') Then
    Result := 'medium'
  Else If SameText(Caption, 'XHigh') Then
    Result := 'xhigh'
  Else
    Result := 'high';
End;

Function KindCaption(Const Backend: String): String;
Begin
  If Backend = 'grok' Then
    Result := 'Grok account'
  Else If Backend = 'codex' Then
    Result := 'ChatGPT (Codex app)'
  Else If Backend = 'openai-compatible' Then
    Result := 'OpenAI-compatible endpoint'
  Else If Backend = 'claude' Then
    Result := 'Claude account'
  Else
    Result := '';
End;

Function ApprovalIndex(Const Mode: String): Integer;
Begin
  If Mode = 'auto' Then
    Result := 1
  Else If Mode = 'always' Then
    Result := 2
  Else
    Result := 0;
End;

Function ApprovalFromIndex(Index: Integer): String;
Begin
  Case Index Of
    1: Result := 'auto';
    2: Result := 'always';
  Else
    Result := 'ask';
  End;
End;

Function NewConnectionId: String;
Var
  Id: TGuid;
Begin
  Result := '';
  If CreateGUID(Id) <> 0 Then
    Exit;
  Result := Copy(GUIDToString(Id), 2, 36);
End;

Procedure EnsureItems(Combo: TComboBox; Const Values: Array Of String; Index: Integer);
Var
  I: Integer;
Begin
  If Combo.Items.Count = 0 Then
    For I := Low(Values) To High(Values) Do
      Combo.Items.Add(Values[I]);
  If (Combo.ItemIndex < 0) And (Index >= 0) And (Index < Combo.Items.Count) Then
    Combo.ItemIndex := Index;
End;

Procedure ShowAssistantSettingsForm;
Var
  Form: TAssistantSettingsForm;
Begin
  Form := TAssistantSettingsForm.Create(Application.MainForm);
  Try
    Form.LoadFromConfig;
    If Form.ShowModal = mrOk Then
      Begin
        Form.SaveToConfig;
        If Assigned(AssistantClient) And Assigned(AssistantChatConfig) Then
          AssistantClient.ApplyConfig(AssistantChatConfig);
        WorkflowLogger.Info('AssistantSettings',
          Format('Saved – model=%s skill=%s thinking=%s approval=%s',
            [AssistantChatConfig.Model, AssistantChatConfig.ActiveSkill,
             AssistantChatConfig.ThinkingLevel, AssistantChatConfig.ApprovalMode]));
        NotifyOpenProjectAssistantFormsPreferencesChanged;
        NotifyOpenProjectAssistantFormsConnectionChanged;
      End;
  Finally
    Form.Free;
    If Assigned(AssistantClient) And Assigned(AssistantChatConfig) Then
      AssistantClient.ApplyConfig(AssistantChatConfig);
  End;
End;

Procedure TAssistantSettingsForm.EnsureStaticChoices;
Begin
  EnsureItems(SearchCombo, ['Off', 'Auto', 'On'], 0);
  EnsureItems(VerbosityCombo, ['Low', 'Medium', 'High'], 1);
  EnsureItems(ApprovalCombo, ['Ask — confirm each write/compile', 'Auto — allow project tools',
    'Always — never prompt (like Build always-approve)'], 0);
  EnsureItems(PresetCombo, ['OpenRouter', 'Custom'], 1);
  EnsureItems(KeySourceCombo, ['Environment variable', 'Stored key'], 0);
  EnsureItems(CompatibleApprovalCombo, ['Ask — confirm each write/compile', 'Auto — allow project tools',
    'Always — never prompt (like Build always-approve)'], 0);
  EnsureItems(ClaudeApprovalCombo, ['Ask — confirm each write/compile', 'Auto — allow project tools',
    'Always — never prompt (like Build always-approve)'], 0);
  CompatibleWireLabel.Caption := 'Chat completions';
  CodexUsageLabel.Caption := 'This program did not report counts.';
  GrokUsageLabel.Caption := 'This connection did not report usage.';
  CompatibleUsageLabel.Caption := 'This connection did not report usage.';
  ClaudeUsageLabel.Caption := 'This connection did not report usage.';
  ClaudeStatusLabel.Caption := ClaudeKeepsSessionText;
End;

Procedure TAssistantSettingsForm.ShowConnectionKind(Const Backend: String);
Begin
  GrokPanel.Visible := Backend = 'grok';
  CodexPanel.Visible := Backend = 'codex';
  CompatiblePanel.Visible := Backend = 'openai-compatible';
  ClaudePanel.Visible := Backend = 'claude';
  EmptyConnectionLabel.Visible := Backend = '';
  KindValueLabel.Caption := KindCaption(Backend);
  ConnectionNameEdit.Enabled := Backend <> '';
  UseConnectionButton.Enabled := Backend <> '';
End;

Function TAssistantSettingsForm.HasGrokRow: Boolean;
Var
  I: Integer;
Begin
  Result := False;
  If Not Assigned(Connections) Then
    Exit;
  For I := 0 To Connections.Count - 1 Do
    If Connections[I].Backend = 'grok' Then
      Exit(True);
End;

Procedure TAssistantSettingsForm.FormCreate(Sender: TObject);
Var
  I: Integer;
Begin
  Caption := 'Project Assistant Settings';
  ButtonPanel.OKButton.Caption := 'OK';
  ButtonPanel.CancelButton.Caption := 'Cancel';
  KeyValueEdit.PasswordChar := '*';
  EnsureStaticChoices;
  KeySourceChange(Nil);
  SkillRows := TFPList.Create;
  SelectedConnection := -1;
  Connections := TAssistantConnections.Create(LazarusIDE.GetPrimaryConfigPath);
  Connections.Load;
  If AssistantTarget.Available Then
    ProjectTestSettings.Load(AssistantTarget.StoreDirectory, AssistantTarget.Manifest)
  Else
    ProjectTestSettings.Load('', '');
  GlobalSpellSettings.LoadFromConfig;
  RefreshConnections;
  If Connections.Count > 0 Then
    Begin
      ConnectionsList.ItemIndex := 0;
      For I := 0 To Connections.Count - 1 Do
        If Connections[I].Id = Connections.ActiveId Then
          ConnectionsList.ItemIndex := I;
    End;
  ConnectionChanged(Nil);
  PopulateSkills;
  RefreshAuthStatus;
  SettingsPages.ActivePage := ConnectionsPage;
End;

Destructor TAssistantSettingsForm.Destroy;
Begin
  ReleasePlanUsageRefresh;
  ClearSkillRows;
  SkillRows.Free;
  Connections.Free;
  Inherited Destroy;
End;

Procedure TAssistantSettingsForm.UpdateCompactAvailability;
Var
  CanCompact: Boolean;
Begin
  CanCompact := False;
  If Assigned(Connections) And (SelectedConnection >= 0) And (SelectedConnection < Connections.Count) Then
    CanCompact := Connections[SelectedConnection].CanCompactContext;
  { Greyed does not clear the saved flag. }
  AutoCompactCheck.Enabled := CanCompact;
  AutoCompactCheck.ShowHint := True;
  If CanCompact Then
    AutoCompactCheck.Hint := 'Compact older history when the context budget is nearly full.'
  Else
    AutoCompactCheck.Hint := 'This connection keeps its own transcript.';
End;

Procedure TAssistantSettingsForm.ClearSkillRows;
Var
  I: Integer;
Begin
  If Assigned(SkillRows) Then
    Begin
      For I := 0 To SkillRows.Count - 1 Do
        TObject(SkillRows[I]).Free;
      SkillRows.Clear;
    End;
  FreeAndNil(NoSkillsLabel);
End;

Procedure TAssistantSettingsForm.SaveSkillModes;
Var
  I: Integer;
  Modes: TStringList;
  Row: TSkillModeRow;
Begin
  If (Not Assigned(AssistantChatConfig)) Or (Not Assigned(SkillRows)) Then
    Exit;
  Modes := TStringList.Create;
  Try
    For I := 0 To SkillRows.Count - 1 Do
      Begin
        Row := TSkillModeRow(SkillRows[I]);
        Modes.Clear;
        If Row.InspectCheck.Checked Then
          Modes.Add('inspect');
        If Row.DocumentCheck.Checked Then
          Modes.Add('document');
        If Row.PlanCheck.Checked Then
          Modes.Add('plan');
        If Row.BuildCheck.Checked Then
          Modes.Add('build');
        If Row.ChatCheck.Checked Then
          Modes.Add('chat');
        AssistantChatConfig.SetSkillModes(Row.SkillName, Modes);
      End;
  Finally
    Modes.Free;
  End;
End;

Procedure TAssistantSettingsForm.RefreshConnections;
Var
  I, Selected: Integer;
  Item: TAssistantConnection;
Begin
  Selected := ConnectionsList.ItemIndex;
  ConnectionsList.Items.BeginUpdate;
  Try
    ConnectionsList.Items.Clear;
    For I := 0 To Connections.Count - 1 Do
      Begin
        Item := Connections[I];
        If Item.Id = Connections.ActiveId Then
          ConnectionsList.Items.Add(Item.Name + ' (current)')
        Else
          ConnectionsList.Items.Add(Item.Name);
      End;
  Finally
    ConnectionsList.Items.EndUpdate;
  End;
  If Selected >= Connections.Count Then
    Selected := Connections.Count - 1;
  ConnectionsList.ItemIndex := Selected;
  Item := Connections.Active;
  If Assigned(Item) Then
    ActiveConnectionLabel.Caption := 'Current chat: ' + Item.Name + '.'
  Else
    ActiveConnectionLabel.Caption := 'No connection is selected for the current chat.';
End;

Procedure TAssistantSettingsForm.StoreConnection;
Var
  Item: TAssistantConnection;
Begin
  If (Not Assigned(Connections)) Or (SelectedConnection < 0) Or (SelectedConnection >= Connections.Count) Then
    Exit;
  Item := Connections[SelectedConnection];
  If Trim(ConnectionNameEdit.Text) <> '' Then
    Item.Name := Trim(ConnectionNameEdit.Text);
  If Item.Backend = 'grok' Then
    Begin
      Item.ApiBase := Trim(ApiBaseEdit.Text);
      If (ModelList.ItemIndex >= 0) And (ModelList.ItemIndex < ModelList.Items.Count) Then
        Item.Model := XaiModelIdFromDisplay(ModelList.Items[ModelList.ItemIndex]);
      If ThinkingCombo.ItemIndex >= 0 Then
        Item.ReasoningEffort := EffortFromCaption(ThinkingCombo.Items[ThinkingCombo.ItemIndex]);
      Item.ApprovalMode := ApprovalFromIndex(ApprovalCombo.ItemIndex);
      Case SearchCombo.ItemIndex Of
        1: Item.SearchMode := 'auto';
        2: Item.SearchMode := 'on';
      Else
        Item.SearchMode := 'off';
      End;
      Item.SearchCitations := CitationsCheck.Checked;
      Case VerbosityCombo.ItemIndex Of
        0: Item.AnswerVerbosity := 'low';
        2: Item.AnswerVerbosity := 'high';
      Else
        Item.AnswerVerbosity := 'medium';
      End;
      Item.MaxOutputTokens := MaxOutputEdit.Value;
    End
  Else If Item.Backend = 'codex' Then
    Begin
      Item.Runtime := Trim(CodexFrame.RuntimeEdit.Text);
      Item.Model := Trim(CodexFrame.ModelCombo.Text);
      Item.ReasoningEffort := CodexFrame.ReasoningEffort;
      Item.ApprovalMode := CodexFrame.ApprovalMode;
      Item.CachedModelsJson := CodexFrame.CachedModelsJson;
    End
  Else If Item.Backend = 'openai-compatible' Then
    Begin
      If PresetCombo.ItemIndex = 0 Then
        Item.Preset := 'openrouter'
      Else
        Item.Preset := 'custom';
      Item.ApiBase := Trim(CompatibleBaseEdit.Text);
      If KeySourceCombo.ItemIndex = 1 Then
        Item.KeySource := 'stored'
      Else
        Item.KeySource := 'env';
      Item.KeyEnv := Trim(KeyEnvEdit.Text);
      Item.KeyValue := KeyValueEdit.Text;
      Item.WireApi := AssistantWireChatCompletions;
      Item.Model := Trim(CompatibleModelCombo.Text);
      Item.MaxOutputTokens := CompatibleMaxOutputEdit.Value;
      Item.ApprovalMode := ApprovalFromIndex(CompatibleApprovalCombo.ItemIndex);
    End
  Else If Item.Backend = 'claude' Then
    Begin
      Item.Runtime := Trim(ClaudeRuntimeEdit.Text);
      Item.Model := Trim(ClaudeModelEdit.Text);
      Item.ApprovalMode := ApprovalFromIndex(ClaudeApprovalCombo.ItemIndex);
    End;
End;

{ Latest completed turn, then the Grok Build plan summary when that connection has one. }
Procedure TAssistantSettingsForm.ShowConnectionUsage(Item: TAssistantConnection; UsageLabel: TLabel);
Var
  Root, PlanText: String;
  Found: Boolean;
  Recorded: TAssistantUsageRecord;
Begin
  If Not Assigned(UsageLabel) Then
    Exit;
  Root := '';
  If Assigned(ProjectAssistantConversation) Then
    Root := ProjectAssistantConversation.ProjectRoot;
  Found := Assigned(Item) And (Root <> '') And LatestUsageRecord(Root, Item.Id, Recorded);
  UsageLabel.Caption := UsageDetailText(Found, Recorded);
  PlanText := '';
  If Assigned(Item) And (Item.Backend = 'grok') Then
    PlanText := AccountUsagePlanText(Item.Id);
  If PlanText = '' Then
    Exit;
  If (Not Found) Or (Recorded.State <> UsageStateReported) Then
    UsageLabel.Caption := PlanText
  Else
    UsageLabel.Caption := UsageLabel.Caption + LineEnding + PlanText;
End;

Procedure TAssistantSettingsForm.ReleasePlanUsageRefresh;
Begin
  FPlanUsageClosed := True;
  If Assigned(FPlanUsageTimer) Then
    Begin
      FPlanUsageTimer.Enabled := False;
      FPlanUsageTimer.OnTimer := Nil;
      FreeAndNil(FPlanUsageTimer);
    End;
  If Assigned(FPlanUsageWorker) Then
    Begin
      FPlanUsageWorker.WaitFor;
      FreeAndNil(FPlanUsageWorker);
    End;
End;

Procedure TAssistantSettingsForm.PlanUsageTimerTimer(Sender: TObject);
Var
  Item: TAssistantConnection;
Begin
  If FPlanUsageClosed Then
    Exit;
  If Assigned(FPlanUsageWorker) And (Not FPlanUsageWorker.Finished) Then
    Exit;
  If Assigned(FPlanUsageWorker) Then
    Begin
      FPlanUsageWorker.WaitFor;
      FreeAndNil(FPlanUsageWorker);
    End;
  If Assigned(FPlanUsageTimer) Then
    FPlanUsageTimer.Enabled := False;
  Item := Nil;
  If Assigned(Connections) And (SelectedConnection >= 0) And (SelectedConnection < Connections.Count) Then
    Item := Connections[SelectedConnection];
  If Assigned(Item) And (Item.Id = FPlanUsageConnectionId) And (Item.Backend = 'grok') Then
    ShowConnectionUsage(Item, GrokUsageLabel);
End;

Procedure TAssistantSettingsForm.StartPlanUsageRefresh(Item: TAssistantConnection);
Var
  Worker: TPlanUsageWorker;
  Copy: TAssistantConnection;
Begin
  If FPlanUsageClosed Or (Not Assigned(Item)) Or (Item.Backend <> 'grok') Then
    Exit;
  If Assigned(FPlanUsageWorker) And (Not FPlanUsageWorker.Finished) Then
    Exit;
  If Assigned(FPlanUsageWorker) Then
    Begin
      FPlanUsageWorker.WaitFor;
      FreeAndNil(FPlanUsageWorker);
    End;
  Copy := TAssistantConnection.Create;
  Copy.Id := Item.Id;
  Copy.Backend := Item.Backend;
  Copy.KeySource := 'stored';
  Copy.KeyValue := '';
  If Assigned(GrokOAuthClient) Then
    Copy.KeyValue := GrokOAuthClient.GetValidAccessToken;
  FPlanUsageConnectionId := Item.Id;
  Worker := TPlanUsageWorker.Create(True);
  Worker.FreeOnTerminate := False;
  Worker.Connection := Copy;
  FPlanUsageWorker := Worker;
  If Not Assigned(FPlanUsageTimer) Then
    Begin
      FPlanUsageTimer := TTimer.Create(Nil);
      FPlanUsageTimer.Interval := 250;
      FPlanUsageTimer.OnTimer := @PlanUsageTimerTimer;
    End;
  FPlanUsageTimer.Enabled := True;
  Worker.Start;
End;

Procedure TAssistantSettingsForm.LoadGrokConnection(Item: TAssistantConnection);
Begin
  If Item.ApiBase <> '' Then
    ApiBaseEdit.Text := Item.ApiBase
  Else
    ApiBaseEdit.Text := AssistantConfigDefaultApiBase;
  If Item.Model <> '' Then
    SelectModelInList(ModelList, Item.Model);
  RefreshGrokReasoningChoices(Item.ReasoningEffort);
  If SameText(Item.SearchMode, 'on') Then
    SearchCombo.ItemIndex := 2
  Else If SameText(Item.SearchMode, 'auto') Then
    SearchCombo.ItemIndex := 1
  Else
    SearchCombo.ItemIndex := 0;
  GrokSearchModeChange(Nil);
  CitationsCheck.Checked := Item.SearchCitations;
  If SameText(Item.AnswerVerbosity, 'low') Then
    VerbosityCombo.ItemIndex := 0
  Else If SameText(Item.AnswerVerbosity, 'high') Then
    VerbosityCombo.ItemIndex := 2
  Else
    VerbosityCombo.ItemIndex := 1;
  If Item.MaxOutputTokens < 0 Then
    MaxOutputEdit.Value := 0
  Else If Item.MaxOutputTokens > MaxOutputEdit.MaxValue Then
    MaxOutputEdit.Value := MaxOutputEdit.MaxValue
  Else
    MaxOutputEdit.Value := Item.MaxOutputTokens;
  ApprovalCombo.ItemIndex := ApprovalIndex(Item.ApprovalMode);
  ShowConnectionUsage(Item, GrokUsageLabel);
  StartPlanUsageRefresh(Item);
End;

Procedure TAssistantSettingsForm.LoadCompatibleConnection(Item: TAssistantConnection);
Begin
  If Item.Preset = 'openrouter' Then
    PresetCombo.ItemIndex := 0
  Else
    PresetCombo.ItemIndex := 1;
  CompatibleBaseEdit.Text := Item.ApiBase;
  CompatibleBaseEdit.ReadOnly := Item.Preset = 'openrouter';
  If Item.KeySource = 'stored' Then
    KeySourceCombo.ItemIndex := 1
  Else
    KeySourceCombo.ItemIndex := 0;
  KeyEnvEdit.Text := Item.KeyEnv;
  KeyValueEdit.Text := Item.KeyValue;
  KeySourceChange(Nil);
  CompatibleWireLabel.Caption := 'Chat completions';
  CompatibleModelCombo.Text := Item.Model;
  If Item.MaxOutputTokens < 0 Then
    CompatibleMaxOutputEdit.Value := 0
  Else If Item.MaxOutputTokens > CompatibleMaxOutputEdit.MaxValue Then
    CompatibleMaxOutputEdit.Value := CompatibleMaxOutputEdit.MaxValue
  Else
    CompatibleMaxOutputEdit.Value := Item.MaxOutputTokens;
  CompatibleApprovalCombo.ItemIndex := ApprovalIndex(Item.ApprovalMode);
  CompatibleStatusLabel.Caption := '';
  ShowConnectionUsage(Item, CompatibleUsageLabel);
End;

Procedure TAssistantSettingsForm.LoadClaudeConnection(Item: TAssistantConnection);
Begin
  ClaudeRuntimeEdit.Text := Item.Runtime;
  ClaudeModelEdit.Text := Item.Model;
  ClaudeApprovalCombo.ItemIndex := ApprovalIndex(Item.ApprovalMode);
  ClaudeStatusLabel.Caption := ClaudeKeepsSessionText;
  ShowConnectionUsage(Item, ClaudeUsageLabel);
End;

Procedure TAssistantSettingsForm.ConnectionChanged(Sender: TObject);
Var
  Item: TAssistantConnection;
  NewSelection: Integer;
Begin
  If CodexFrame.Busy Then
    Begin
      ConnectionsList.ItemIndex := SelectedConnection;
      Exit;
    End;
  NewSelection := ConnectionsList.ItemIndex;
  If Not FLoading Then
    StoreConnection;
  RefreshConnections;
  SelectedConnection := NewSelection;
  ConnectionsList.ItemIndex := NewSelection;
  If (SelectedConnection < 0) Or (SelectedConnection >= Connections.Count) Then
    Begin
      ShowConnectionKind('');
      ConnectionNameEdit.Text := '';
      UpdateCompactAvailability;
      Exit;
    End;
  Item := Connections[SelectedConnection];
  FLoading := True;
  Try
    ConnectionNameEdit.Text := Item.Name;
    ShowConnectionKind(Item.Backend);
    If Item.Backend = 'grok' Then
      LoadGrokConnection(Item)
    Else If Item.Backend = 'codex' Then
      Begin
        Try
          CodexFrame.LoadConnection(Connections.ProfileDir(Item), Item.Runtime, Item.Model, Item.ReasoningEffort,
            Item.ApprovalMode, Item.CachedModelsJson);
        Except
          On E: Exception Do
            CodexFrame.ConnectionStatus.Caption := E.Message;
        End;
      End
    Else If Item.Backend = 'openai-compatible' Then
      LoadCompatibleConnection(Item)
    Else If Item.Backend = 'claude' Then
      LoadClaudeConnection(Item);
  Finally
    FLoading := False;
  End;
  UpdateCompactAvailability;
End;

Procedure TAssistantSettingsForm.AddKind(Const Backend, DisplayName: String);
Var
  Item: TAssistantConnection;
  Id: String;
Begin
  If CodexFrame.Busy Then
    Exit;
  StoreConnection;
  If Backend = 'codex' Then
    Item := Connections.AddChatGPT
  Else
    Begin
      Id := NewConnectionId;
      If Id = '' Then
        Begin
          MessageDlg('Cannot create a connection identifier.', mtError, [mbOK], 0);
          Exit;
        End;
      Item := Connections.AddStored(Id, DisplayName, Backend);
      If Not Assigned(Item) Then
        Exit;
      Item.ApprovalMode := 'ask';
      If Backend = 'grok' Then
        Begin
          Item.ApiBase := AssistantConfigDefaultApiBase;
          If Assigned(AssistantChatConfig) And (AssistantChatConfig.ApiBase <> '') Then
            Item.ApiBase := AssistantChatConfig.ApiBase;
          Item.Model := AssistantConfigDefaultModel;
          Item.ReasoningEffort := 'high';
          Item.SearchMode := 'off';
          Item.AnswerVerbosity := 'medium';
        End
      Else If Backend = 'openai-compatible' Then
        Begin
          Item.Preset := 'custom';
          Item.KeySource := 'env';
          Item.WireApi := AssistantWireChatCompletions;
        End
      Else If Backend = 'claude' Then
        Item.Runtime := DetectClaudeExecutable;
    End;
  SelectedConnection := -1;
  RefreshConnections;
  ConnectionsList.ItemIndex := Connections.Count - 1;
  ConnectionChanged(Nil);
End;

Procedure TAssistantSettingsForm.AddConnectionClick(Sender: TObject);
Var
  Origin: TPoint;
Begin
  If CodexFrame.Busy Then
    Exit;
  { A saved row of the same kind does not disable these items. }
  GrokAccountItem.Enabled := True;
  ChatGptAccountItem.Enabled := True;
  CompatibleAccountItem.Enabled := True;
  ClaudeAccountItem.Enabled := True;
  Origin := AddConnectionButton.ClientToScreen(Point(0, AddConnectionButton.Height));
  AddConnectionMenu.PopUp(Origin.X, Origin.Y);
End;

Procedure TAssistantSettingsForm.AddGrokAccountClick(Sender: TObject);
Begin
  AddKind('grok', 'Grok');
End;

Procedure TAssistantSettingsForm.AddChatGptAccountClick(Sender: TObject);
Begin
  AddKind('codex', 'ChatGPT');
End;

Procedure TAssistantSettingsForm.AddCompatibleAccountClick(Sender: TObject);
Begin
  AddKind('openai-compatible', 'OpenAI-compatible');
End;

Procedure TAssistantSettingsForm.AddClaudeAccountClick(Sender: TObject);
Begin
  AddKind('claude', 'Claude');
End;

Procedure TAssistantSettingsForm.RemoveConnectionClick(Sender: TObject);
Begin
  If CodexFrame.Busy Or (SelectedConnection < 0) Then
    Exit;
  Connections.Remove(SelectedConnection);
  SelectedConnection := -1;
  RefreshConnections;
  If Connections.Count > 0 Then
    ConnectionsList.ItemIndex := 0
  Else
    ConnectionsList.ItemIndex := -1;
  ConnectionChanged(Nil);
End;

Procedure TAssistantSettingsForm.UseConnectionClick(Sender: TObject);
Var
  PreviousId: String;
Begin
  StoreConnection;
  If SelectedConnection < 0 Then
    Exit;
  If (Connections[SelectedConnection].Backend = 'codex') And
    ((Connections[SelectedConnection].Runtime = '') Or (Connections[SelectedConnection].Model = '')) Then
    Begin
      MessageDlg('Choose the runtime and sign in or refresh models first.', mtInformation, [mbOK], 0);
      Exit;
    End;
  PreviousId := Connections.ActiveId;
  Connections.ActiveId := Connections[SelectedConnection].Id;
  If Not Connections.Save Then
    Begin
      Connections.ActiveId := PreviousId;
      MessageDlg('The current chat could not be switched. The assistant is still on the previous connection.', mtError, [mbOK], 0);
      Exit;
    End;
  RefreshConnections;
  NotifyOpenProjectAssistantFormsConnectionChanged;
End;

Procedure TAssistantSettingsForm.CompatiblePresetChange(Sender: TObject);
Begin
  If FLoading Then
    Exit;
  If PresetCombo.ItemIndex = 0 Then
    Begin
      CompatibleBaseEdit.Text := AssistantOpenRouterApiBase;
      CompatibleBaseEdit.ReadOnly := True;
      KeyEnvEdit.Text := AssistantOpenRouterKeyEnv;
    End
  Else
    CompatibleBaseEdit.ReadOnly := False;
End;

Procedure TAssistantSettingsForm.KeySourceChange(Sender: TObject);
Var
  Stored: Boolean;
Begin
  Stored := KeySourceCombo.ItemIndex = 1;
  KeyEnvLabel.Visible := Not Stored;
  KeyEnvEdit.Visible := Not Stored;
  KeyValueLabel.Visible := Stored;
  KeyValueEdit.Visible := Stored;
End;

Procedure TAssistantSettingsForm.RefreshCompatibleModels;
Var
  Item: TAssistantConnection;
  Client: TAssistantCompatibleClient;
  Models: TStringList;
  ErrorText, KeptModel: String;
Begin
  If (SelectedConnection < 0) Or (SelectedConnection >= Connections.Count) Then
    Exit;
  StoreConnection;
  Item := Connections[SelectedConnection];
  If Item.Backend <> 'openai-compatible' Then
    Exit;
  KeptModel := Trim(CompatibleModelCombo.Text);
  Client := TAssistantCompatibleClient.Create;
  Models := TStringList.Create;
  Try
    CompatibleStatusLabel.Caption := 'Contacting the endpoint…';
    Application.ProcessMessages;
    If Not Client.ListModels(Item, Models, ErrorText) Then
      Begin
        CompatibleStatusLabel.Caption := ErrorText;
        Exit;
      End;
    CompatibleModelCombo.Items.Assign(Models);
    If KeptModel <> '' Then
      Begin
        CompatibleModelCombo.ItemIndex := CompatibleModelCombo.Items.IndexOf(KeptModel);
        If CompatibleModelCombo.ItemIndex < 0 Then
          CompatibleModelCombo.Text := KeptModel;
      End
    Else If CompatibleModelCombo.Items.Count > 0 Then
      CompatibleModelCombo.ItemIndex := 0;
    CompatibleStatusLabel.Caption := Format('%d models available.', [Models.Count]);
  Finally
    Models.Free;
    Client.Free;
  End;
End;

Procedure TAssistantSettingsForm.TestConnectionClick(Sender: TObject);
Begin
  RefreshCompatibleModels;
End;

Procedure TAssistantSettingsForm.RefreshCompatibleClick(Sender: TObject);
Begin
  RefreshCompatibleModels;
End;

Procedure TAssistantSettingsForm.ClaudeBrowseClick(Sender: TObject);
Var
  Dialog: TOpenDialog;
  Stored: String;
Begin
  Dialog := TOpenDialog.Create(Nil);
  Try
    Dialog.Title := 'Select the Claude executable';
    Dialog.Options := [ofFileMustExist, ofPathMustExist, ofEnableSizing];
    If FileExists(ClaudeRuntimeEdit.Text) Then
      Dialog.FileName := ClaudeRuntimeEdit.Text;
    If Not Dialog.Execute Then
      Exit;
    Stored := ClaudeRuntimeFromBrowsedPath(Dialog.FileName);
    If Stored = '' Then
      ClaudeStatusLabel.Caption := 'The selected file is not an executable. ' + ClaudeKeepsSessionText
    Else
      Begin
        ClaudeRuntimeEdit.Text := Stored;
        ClaudeStatusLabel.Caption := 'Executable selected. ' + ClaudeKeepsSessionText;
      End;
  Finally
    Dialog.Free;
  End;
End;

Procedure TAssistantSettingsForm.ClaudeDetectClick(Sender: TObject);
Var
  Found: String;
Begin
  Found := DetectClaudeExecutable;
  If Found = '' Then
    ClaudeStatusLabel.Caption := 'Claude Code was not found on PATH. Use Browse to select the installed executable. ' +
      ClaudeKeepsSessionText
  Else
    Begin
      ClaudeRuntimeEdit.Text := Found;
      ClaudeStatusLabel.Caption := 'Installed executable detected. ' + ClaudeKeepsSessionText;
    End;
End;

Procedure TAssistantSettingsForm.ClaudeSignInClick(Sender: TObject);
Var
  ErrorText: String;
Begin
  If StartClaudeSignIn(Trim(ClaudeRuntimeEdit.Text), ErrorText) Then
    ClaudeStatusLabel.Caption := 'Claude Code sign-in started. ' + ClaudeKeepsSessionText
  Else
    ClaudeStatusLabel.Caption := ErrorText + ' ' + ClaudeKeepsSessionText;
End;

Procedure TAssistantSettingsForm.ClaudeCheckClick(Sender: TObject);
Begin
  ClaudeRuntimeEdit.Text := Trim(ClaudeRuntimeEdit.Text);
  If FileIsExecutable(ClaudeRuntimeEdit.Text) Then
    ClaudeStatusLabel.Caption := 'Executable found. ' + ClaudeKeepsSessionText
  Else
    ClaudeStatusLabel.Caption := 'Claude Code was not found. Browse to the installed executable. ' + ClaudeKeepsSessionText;
End;

Procedure TAssistantSettingsForm.PopulateSkills;
Var
  Skills: TAssistantSkillList;
  Modes: TStringList;
  I, RowTop, RowWidth: Integer;
  Row: TSkillModeRow;
  Root: String;
Begin
  ClearSkillRows;
  If Not Assigned(SkillRows) Then
    Exit;
  Root := '';
  If Assigned(ProjectAssistantConversation) Then
    Root := ProjectAssistantConversation.ProjectRoot;
  If Assigned(ProjectAssistantConversation) Then
    Skills := ListDiscoveredSkills(ProjectAssistantConversation.ProjectRoot)
  Else
    Skills := ListUserSkills;
  RowWidth := SkillsHost.ClientWidth;
  If RowWidth < 200 Then
    RowWidth := 800;
  RowTop := 0;
  Modes := TStringList.Create;
  Try
    For I := 0 To High(Skills) Do
      Begin
        Row := TSkillModeRow.Create(Skills[I].Name, SkillsHost, RowTop, RowWidth);
        SkillRows.Add(Row);
        Modes.Clear;
        If Assigned(AssistantChatConfig) Then
          AssistantChatConfig.CollectModesForSkill(Skills[I].Name, Modes);
        Row.InspectCheck.Checked := Modes.IndexOf('inspect') >= 0;
        Row.DocumentCheck.Checked := Modes.IndexOf('document') >= 0;
        Row.PlanCheck.Checked := Modes.IndexOf('plan') >= 0;
        Row.BuildCheck.Checked := Modes.IndexOf('build') >= 0;
        Row.ChatCheck.Checked := Modes.IndexOf('chat') >= 0;
        RowTop := RowTop + 28;
      End;
  Finally
    Modes.Free;
  End;
  If Length(Skills) = 0 Then
    Begin
      NoSkillsLabel := TLabel.Create(Nil);
      NoSkillsLabel.Parent := SkillsHost;
      NoSkillsLabel.SetBounds(8, 8, 640, 36);
      NoSkillsLabel.AutoSize := False;
      NoSkillsLabel.WordWrap := True;
      If Root = '' Then
        Root := AssistantUserSkillsRoot
      Else
        Root := IncludeTrailingPathDelimiter(Root) + '.assistant' + PathDelim + 'skills';
      NoSkillsLabel.Caption := 'No skills found. Create ' + Root + PathDelim + '<name>' + PathDelim + 'SKILL.md.';
    End;
End;

Procedure TAssistantSettingsForm.PopulateModels(ForceRefresh: Boolean);
Var
  ErrorText, CurrentModel: String;
  Ok: Boolean;
Begin
  FFillingModels := True;
  CurrentModel := AssistantConfigDefaultModel;
  If (ModelList.ItemIndex >= 0) And (ModelList.ItemIndex < ModelList.Items.Count) Then
    CurrentModel := XaiModelIdFromDisplay(ModelList.Items[ModelList.ItemIndex])
  Else If (SelectedConnection >= 0) And (SelectedConnection < Connections.Count) And
    (Connections[SelectedConnection].Backend = 'grok') And (Connections[SelectedConnection].Model <> '') Then
    CurrentModel := Connections[SelectedConnection].Model
  Else If Assigned(AssistantChatConfig) And (Trim(AssistantChatConfig.Model) <> '') Then
    CurrentModel := AssistantChatConfig.Model;
  ModelList.Items.BeginUpdate;
  Try
    ModelList.Items.Clear;
    Ok := False;
    ErrorText := '';
    If Assigned(AssistantClient) And AssistantClient.IsSignedIn And ForceRefresh Then
      Begin
        ModelHintLabel.Caption := 'Loading models…';
        Application.ProcessMessages;
        Ok := AssistantClient.ListAvailableModels(ModelList.Items, ErrorText);
      End
    Else
      ErrorText := 'Use Refresh list to discover models from the account.';
    If Not Ok Then
      Begin
        AddFallbackModels(ModelList.Items);
        If ErrorText <> '' Then
          ModelHintLabel.Caption := ErrorText + ' Showing fallback list.'
        Else
          ModelHintLabel.Caption := 'Showing fallback list.';
      End
    Else
      ModelHintLabel.Caption := Format('%d models available. Select one, then OK.', [ModelList.Items.Count]);
    DecorateModelList(ModelList.Items);
    SelectModelInList(ModelList, CurrentModel);
    If (SelectedConnection >= 0) And (SelectedConnection < Connections.Count) And
      (Connections[SelectedConnection].Backend = 'grok') Then
      RefreshGrokReasoningChoices(Connections[SelectedConnection].ReasoningEffort)
    Else If Assigned(AssistantChatConfig) Then
      RefreshGrokReasoningChoices(AssistantChatConfig.ThinkingLevel)
    Else
      RefreshGrokReasoningChoices('high');
  Finally
    ModelList.Items.EndUpdate;
    FFillingModels := False;
  End;
End;

Procedure TAssistantSettingsForm.GrokModelSelectionChange(Sender: TObject; User: Boolean);
Var
  Effort: String;
Begin
  If (Not User) Or FFillingModels Or FLoading Then
    Exit;
  Effort := 'high';
  If ThinkingCombo.ItemIndex >= 0 Then
    Effort := EffortFromCaption(ThinkingCombo.Items[ThinkingCombo.ItemIndex]);
  RefreshGrokReasoningChoices(Effort);
End;

Procedure TAssistantSettingsForm.GrokSearchModeChange(Sender: TObject);
Begin
  CitationsCheck.Enabled := SearchCombo.ItemIndex > 0;
End;

Procedure TAssistantSettingsForm.RefreshGrokReasoningChoices(Const PreferredEffort: String);
Var
  ModelId, Effort: String;
  Procedure AddLevel(Const Level, Caption: String);
  Begin
    If Not XaiModelAllowsEffort(ModelId, Level) Then
      Exit;
    ThinkingCombo.Items.Add(Caption);
  End;
  Function IndexOfCaption(Const Caption: String): Integer;
  Begin
    Result := ThinkingCombo.Items.IndexOf(Caption);
  End;
Begin
  ModelId := '';
  If (ModelList.ItemIndex >= 0) And (ModelList.ItemIndex < ModelList.Items.Count) Then
    ModelId := XaiModelIdFromDisplay(ModelList.Items[ModelList.ItemIndex]);
  Effort := LowerCase(Trim(PreferredEffort));
  If Effort = '' Then
    Effort := 'high';
  ThinkingCombo.Items.BeginUpdate;
  Try
    ThinkingCombo.Items.Clear;
    AddLevel('low', 'Low');
    AddLevel('medium', 'Medium');
    AddLevel('high', 'High');
    AddLevel('xhigh', 'XHigh');
    If ThinkingCombo.Items.Count = 0 Then
      Begin
        ThinkingCombo.Items.Add('Low');
        ThinkingCombo.Items.Add('Medium');
        ThinkingCombo.Items.Add('High');
        ThinkingCombo.Items.Add('XHigh');
      End;
  Finally
    ThinkingCombo.Items.EndUpdate;
  End;
  If SameText(Effort, 'low') And (IndexOfCaption('Low') >= 0) Then
    ThinkingCombo.ItemIndex := IndexOfCaption('Low')
  Else If SameText(Effort, 'medium') And (IndexOfCaption('Medium') >= 0) Then
    ThinkingCombo.ItemIndex := IndexOfCaption('Medium')
  Else If SameText(Effort, 'xhigh') And (IndexOfCaption('XHigh') >= 0) Then
    ThinkingCombo.ItemIndex := IndexOfCaption('XHigh')
  Else If IndexOfCaption('High') >= 0 Then
    ThinkingCombo.ItemIndex := IndexOfCaption('High')
  Else
    ThinkingCombo.ItemIndex := ThinkingCombo.Items.Count - 1;
End;

Procedure TAssistantSettingsForm.RefreshAuthStatus;
Var
  Busy, Pending, SignedIn: Boolean;
Begin
  Busy := False;
  Pending := False;
  SignedIn := False;
  If Assigned(GrokOAuthClient) Then
    Begin
      StatusValueLabel.Caption := GrokOAuthClient.StatusText;
      Busy := GrokOAuthClient.LoginBusy;
      Pending := GrokOAuthClient.HasPendingLogin;
      SignedIn := GrokOAuthClient.IsAuthenticated;
    End
  Else
    StatusValueLabel.Caption := 'OAuth unavailable';
  SignInButton.Enabled := Assigned(GrokOAuthClient) And (Not Busy);
  SignOutButton.Enabled := Assigned(GrokOAuthClient) And SignedIn And (Not Busy);
  PasteCodeButton.Enabled := Assigned(GrokOAuthClient) And (Not Busy);
  ManualEdit.Enabled := Assigned(GrokOAuthClient) And (Not Busy);
  RefreshModelsButton.Enabled := Assigned(AssistantClient) And SignedIn And (Not Busy);
  If SignedIn And (Not Pending) Then
    ManualLabel.Caption := 'Already signed in — paste is only for a failed browser redirect:'
  Else If Pending Then
    ManualLabel.Caption := 'Browser open — paste code or callback URL only if it did not redirect:'
  Else
    ManualLabel.Caption := 'If browser cannot redirect, paste code or callback URL:';
End;

Procedure TAssistantSettingsForm.LoadFromConfig;
Begin
  If Not Assigned(AssistantChatConfig) Then
    Exit;
  ApiBaseEdit.Text := AssistantChatConfig.ApiBase;
  IncludeContextCheck.Checked := AssistantChatConfig.IncludeIDEContext;
  EnterNewlineCheck.Checked := AssistantChatConfig.EnterInsertsNewline;
  AutoCompactCheck.Checked := AssistantChatConfig.AutoCompactContext;
  ShowThinkingCheck.Checked := AssistantChatConfig.ShowThinking;
  ShowToolCallsCheck.Checked := AssistantChatConfig.ShowToolCalls;
  RefreshGrokReasoningChoices(AssistantChatConfig.ThinkingLevel);
  If SameText(AssistantChatConfig.SearchMode, 'on') Then
    SearchCombo.ItemIndex := 2
  Else If SameText(AssistantChatConfig.SearchMode, 'auto') Then
    SearchCombo.ItemIndex := 1
  Else
    SearchCombo.ItemIndex := 0;
  GrokSearchModeChange(Nil);
  CitationsCheck.Checked := AssistantChatConfig.SearchCitations;
  If SameText(AssistantChatConfig.AnswerVerbosity, 'low') Then
    VerbosityCombo.ItemIndex := 0
  Else If SameText(AssistantChatConfig.AnswerVerbosity, 'high') Then
    VerbosityCombo.ItemIndex := 2
  Else
    VerbosityCombo.ItemIndex := 1;
  MaxOutputEdit.Value := AssistantChatConfig.MaxOutputTokens;
  ApprovalCombo.ItemIndex := ApprovalIndex(AssistantChatConfig.ApprovalMode);
  PopulateSkills;
  If Assigned(GrokOAuthClient) And AssistantChatConfig.IsSignedIn Then
    GrokOAuthClient.SetTokens(AssistantChatConfig.ToOAuthTokens);
  If Assigned(AssistantClient) Then
    AssistantClient.ApplyConfig(AssistantChatConfig);
  RefreshAuthStatus;
  PopulateModels(False);
  GlobalSpellSettings.LoadFromConfig;
  If ConnectionsList.ItemIndex >= 0 Then
    ConnectionChanged(Nil)
  Else
    UpdateCompactAvailability;
End;

Procedure TAssistantSettingsForm.SaveToConfig;
Var
  ModelName: String;
Begin
  If Not Assigned(AssistantChatConfig) Then
    Exit;
  AssistantChatConfig.ApiBase := Trim(ApiBaseEdit.Text);
  If AssistantChatConfig.ApiBase = '' Then
    AssistantChatConfig.ApiBase := AssistantConfigDefaultApiBase;
  ModelName := '';
  If (ModelList.ItemIndex >= 0) And (ModelList.ItemIndex < ModelList.Items.Count) Then
    ModelName := XaiModelIdFromDisplay(ModelList.Items[ModelList.ItemIndex]);
  If ModelName = '' Then
    ModelName := AssistantConfigDefaultModel;
  AssistantChatConfig.Model := ModelName;
  AssistantChatConfig.IncludeIDEContext := IncludeContextCheck.Checked;
  AssistantChatConfig.EnterInsertsNewline := EnterNewlineCheck.Checked;
  { Disabled compact still keeps the saved flag. }
  AssistantChatConfig.AutoCompactContext := AutoCompactCheck.Checked;
  AssistantChatConfig.ShowThinking := ShowThinkingCheck.Checked;
  AssistantChatConfig.ShowToolCalls := ShowToolCallsCheck.Checked;
  SaveSkillModes;
  Case SearchCombo.ItemIndex Of
    1: AssistantChatConfig.SearchMode := 'auto';
    2: AssistantChatConfig.SearchMode := 'on';
  Else
    AssistantChatConfig.SearchMode := 'off';
  End;
  AssistantChatConfig.SearchCitations := CitationsCheck.Checked;
  Case VerbosityCombo.ItemIndex Of
    0: AssistantChatConfig.AnswerVerbosity := 'low';
    2: AssistantChatConfig.AnswerVerbosity := 'high';
  Else
    AssistantChatConfig.AnswerVerbosity := 'medium';
  End;
  AssistantChatConfig.MaxOutputTokens := MaxOutputEdit.Value;
  If ThinkingCombo.ItemIndex >= 0 Then
    AssistantChatConfig.ThinkingLevel := EffortFromCaption(ThinkingCombo.Items[ThinkingCombo.ItemIndex])
  Else
    AssistantChatConfig.SetThinkingLevelEnum(atlHigh);
  Case ApprovalCombo.ItemIndex Of
    0: AssistantChatConfig.SetApprovalModeEnum(aamAsk);
    1: AssistantChatConfig.SetApprovalModeEnum(aamAuto);
  Else
    AssistantChatConfig.SetApprovalModeEnum(aamAlways);
  End;
  If Assigned(GrokOAuthClient) Then
    AssistantChatConfig.ApplyOAuthTokens(GrokOAuthClient.Tokens);
  AssistantChatConfig.Save;
  StoreConnection;
  Connections.Save;
  GlobalSpellSettings.SaveToConfig;
  ProjectTestSettings.Save;
End;

Procedure TAssistantSettingsForm.RefreshModelsButtonClick(Sender: TObject);
Begin
  If Assigned(AssistantClient) Then
    AssistantClient.SetEndpoint(Trim(ApiBaseEdit.Text), AssistantClient.Model);
  PopulateModels(True);
End;

Procedure TAssistantSettingsForm.SignInButtonClick(Sender: TObject);
Begin
  If Not Assigned(GrokOAuthClient) Then
    Exit;
  ManualEdit.Clear;
  StatusValueLabel.Caption := 'Waiting for browser sign-in…';
  SignInButton.Enabled := False;
  PasteCodeButton.Enabled := False;
  ManualEdit.Enabled := False;
  SignOutButton.Enabled := False;
  Try
    Application.ProcessMessages;
    If GrokOAuthClient.LoginWithBrowser Then
      Begin
        If Assigned(AssistantChatConfig) Then
          Begin
            AssistantChatConfig.ApplyOAuthTokens(GrokOAuthClient.Tokens);
            AssistantChatConfig.Save;
          End;
        If Assigned(AssistantClient) Then
          AssistantClient.ApplyConfig(AssistantChatConfig);
        ManualEdit.Clear;
        MessageDlg('Signed in with SuperGrok / X Premium.' + LineEnding + LineEnding +
          'You do not need to paste the browser code — it is single-use and was already consumed.',
          mtInformation, [mbOK], 0);
        PopulateModels(True);
      End
    Else If GrokOAuthClient.HasPendingLogin Then
      MessageDlg('Browser callback did not finish: ' + GrokOAuthClient.LastError + LineEnding + LineEnding +
        'If the browser showed a code (or a localhost URL with ?code=…), paste it below once and click "Use pasted code".',
        mtWarning, [mbOK], 0)
    Else
      MessageDlg('Sign-in failed: ' + GrokOAuthClient.LastError, mtWarning, [mbOK], 0);
  Finally
    RefreshAuthStatus;
  End;
End;

Procedure TAssistantSettingsForm.SignOutButtonClick(Sender: TObject);
Begin
  If Not Assigned(GrokOAuthClient) Then
    Exit;
  If MessageDlg('Sign out of SuperGrok / X Premium on this machine?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes Then
    Exit;
  GrokOAuthClient.ClearTokens;
  If Assigned(AssistantChatConfig) Then
    Begin
      AssistantChatConfig.ClearOAuthTokens;
      AssistantChatConfig.Save;
    End;
  RefreshAuthStatus;
  PopulateModels(False);
  WorkflowLogger.Info('AssistantSettings', 'Signed out');
End;

Procedure TAssistantSettingsForm.PasteCodeButtonClick(Sender: TObject);
Var
  AuthUrl: String;
Begin
  If Not Assigned(GrokOAuthClient) Then
    Exit;
  If GrokOAuthClient.LoginBusy Then
    Begin
      MessageDlg('Sign-in is already in progress. Wait for the browser flow to finish.', mtInformation, [mbOK], 0);
      Exit;
    End;
  If Trim(ManualEdit.Text) = '' Then
    Begin
      If GrokOAuthClient.IsAuthenticated And (Not GrokOAuthClient.HasPendingLogin) Then
        Begin
          MessageDlg('You are already signed in. Paste is only needed when the browser cannot redirect back to Lazarus.',
            mtInformation, [mbOK], 0);
          Exit;
        End;
      If GrokOAuthClient.BeginManualLogin(AuthUrl) Then
        Begin
          OpenURL(AuthUrl);
          MessageDlg('Browser opened. After signing in, paste the callback URL or code into the box once, then click "Use pasted code".',
            mtInformation, [mbOK], 0);
        End
      Else
        MessageDlg(GrokOAuthClient.LastError, mtError, [mbOK], 0);
      RefreshAuthStatus;
      Exit;
    End;
  If GrokOAuthClient.LoginWithManualCode(ManualEdit.Text) Then
    Begin
      If Assigned(AssistantChatConfig) Then
        Begin
          AssistantChatConfig.ApplyOAuthTokens(GrokOAuthClient.Tokens);
          AssistantChatConfig.Save;
        End;
      If Assigned(AssistantClient) Then
        AssistantClient.ApplyConfig(AssistantChatConfig);
      ManualEdit.Clear;
      MessageDlg('Signed in with SuperGrok / X Premium.', mtInformation, [mbOK], 0);
      PopulateModels(True);
    End
  Else
    MessageDlg(GrokOAuthClient.LastError, mtWarning, [mbOK], 0);
  RefreshAuthStatus;
End;

Procedure TAssistantSettingsForm.FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
Var
  Note: String;
  ActiveConnection: TAssistantConnection;
Begin
  CanClose := True;
  If ModalResult <> mrOk Then
    Exit;
  If Not ProjectTestSettings.Validate(Note) Then
    Begin
      CanClose := False;
      MessageDlg(Note, mtError, [mbOK], 0);
      Exit;
    End;
  StoreConnection;
  If CodexFrame.Busy Then
    Begin
      CanClose := False;
      MessageDlg('Wait for the connection check, or Cancel to close settings.', mtInformation, [mbOK], 0);
      Exit;
    End;
  ActiveConnection := Connections.Active;
  If Assigned(ActiveConnection) And (ActiveConnection.Backend = 'codex') And
    ((ActiveConnection.Runtime = '') Or (ActiveConnection.Model = '')) Then
    Begin
      CanClose := False;
      MessageDlg('The current ChatGPT connection needs a runtime and model.', mtInformation, [mbOK], 0);
      Exit;
    End;
  If Not HasGrokRow Then
    Exit;
  If Trim(ApiBaseEdit.Text) = '' Then
    Begin
      MessageDlg('API base URL is required (e.g. https://api.x.ai/v1).', mtError, [mbOK], 0);
      CanClose := False;
      Exit;
    End;
  If Not UrlIsHttps(Trim(ApiBaseEdit.Text)) Then
    Begin
      MessageDlg('API base URL must be HTTPS (e.g. https://api.x.ai/v1).', mtError, [mbOK], 0);
      CanClose := False;
      Exit;
    End;
  If (ModelList.ItemIndex < 0) Or (ModelList.ItemIndex >= ModelList.Items.Count) Or
    (Trim(ModelList.Items[ModelList.ItemIndex]) = '') Then
    Begin
      MessageDlg('Select a model from the list (e.g. grok-4.5).', mtError, [mbOK], 0);
      CanClose := False;
    End;
End;

Initialization

RegisterClass(TAssistantTestSettingsFrame);
RegisterClass(TCodexConnectionFrame);
RegisterClass(TSpellCheckerSettingsFrame);

End.
