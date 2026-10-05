Unit AssistantSettingsForm;

{ LazAssistantTools OAuth sign-in, model and skill settings dialog (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ButtonPanel, ComCtrls, Spin, AssistantConnections, AssistantCodexSettings, SpellCheckerSettingsFrame, AssistantTestSettingsFrame;

Type
  TAssistantSettingsForm = Class(TForm)
    StatusLabel: TLabel;
    StatusValueLabel: TLabel;
    ModelLabel: TLabel;
    ModelList: TListBox;
    ModelHintLabel: TLabel;
    RefreshModelsButton: TButton;
    SkillLabel: TLabel;
    SkillCombo: TComboBox;
    IncludeContextCheck: TCheckBox;
    AutoNewChatDefaultCheck: TCheckBox;
    ShowThinkingCheck: TCheckBox;
    ShowToolCallsCheck: TCheckBox;
    ThinkingLabel: TLabel;
    ThinkingCombo: TComboBox;
    ApprovalLabel: TLabel;
    ApprovalCombo: TComboBox;
    SearchLabel: TLabel;
    SearchCombo: TComboBox;
    CitationsCheck: TCheckBox;
    VerbosityLabel: TLabel;
    VerbosityCombo: TComboBox;
    MaxOutputLabel: TLabel;
    MaxOutputEdit: TSpinEdit;
    ApiBaseLabel: TLabel;
    ApiBaseEdit: TEdit;
    HintLabel: TLabel;
    ManualLabel: TLabel;
    ManualEdit: TEdit;
    SignInButton: TButton;
    SignOutButton: TButton;
    PasteCodeButton: TButton;
    SpellButton: TButton;
    ButtonPanel: TButtonPanel;
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
    Procedure FormCreate(Sender: TObject);
    Procedure SignInButtonClick(Sender: TObject);
    Procedure SignOutButtonClick(Sender: TObject);
    Procedure PasteCodeButtonClick(Sender: TObject);
    Procedure RefreshModelsButtonClick(Sender: TObject);
    Procedure SpellButtonClick(Sender: TObject);
    Procedure EnsureExtraControls;
    Procedure GrokModelSelectionChange(Sender: TObject; User: Boolean);
    Procedure GrokSearchModeChange(Sender: TObject);
  Private
    Connections: TAssistantConnections;
    ConnectionList: TListBox;
    ConnectionName: TEdit;
    ActiveConnectionLabel: TLabel;
    GrokPanel: TScrollBox;
    CodexFrame: TCodexConnectionFrame;
    SpellFrame: TSpellCheckerSettingsFrame;
    TestFrame: TAssistantTestSettingsFrame;
    SelectedConnection: Integer;
    FFillingModels: Boolean;
    Procedure BuildSettingsPages;
    Procedure RefreshGrokReasoningChoices(Const PreferredEffort: String);
    Procedure GeneralPageResize(Sender: TObject);
    Procedure RefreshConnections;
    Procedure StoreConnection;
    Procedure ConnectionChanged(Sender: TObject);
    Procedure AddConnection(Sender: TObject);
    Procedure RemoveConnection(Sender: TObject);
    Procedure UseConnection(Sender: TObject);
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

Uses AssistantWorkTarget,
  AssistantConfig, AssistantService, GrokOAuth, AssistantSkills, AssistantHttps, WorkflowLog,
  AssistantConversation, ProjectAssistantForm, AssistantXaiProvider,
  LCLIntf, SpellCheckerSettingsForm, LazIDEIntf;

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
    { Restore any endpoint temporarily used for discovery when Cancel was chosen. }
    If Assigned(AssistantClient) And Assigned(AssistantChatConfig) Then
      AssistantClient.ApplyConfig(AssistantChatConfig);
  End;
End;

Procedure TAssistantSettingsForm.EnsureExtraControls;
Begin
  If Assigned(ThinkingCombo) Then
    Exit;
  ClientHeight := ClientHeight + 120;
  If Assigned(ButtonPanel) Then
    ButtonPanel.Top := ButtonPanel.Top + 120;
  If Assigned(HintLabel) Then
    HintLabel.Top := HintLabel.Top + 120;
  If Assigned(ManualLabel) Then
    ManualLabel.Top := ManualLabel.Top + 120;
  If Assigned(ManualEdit) Then
    ManualEdit.Top := ManualEdit.Top + 120;
  If Assigned(PasteCodeButton) Then
    PasteCodeButton.Top := PasteCodeButton.Top + 120;
  If Assigned(ApiBaseLabel) Then
    ApiBaseLabel.Top := ApiBaseLabel.Top + 120;
  If Assigned(ApiBaseEdit) Then
    ApiBaseEdit.Top := ApiBaseEdit.Top + 120;

  ThinkingLabel := TLabel.Create(Self);
  ThinkingLabel.Parent := Self;
  ThinkingLabel.Left := 16;
  ThinkingLabel.Top := 350;
  ThinkingLabel.Caption := 'Thinking level (Responses API; Completions is fallback):';

  ThinkingCombo := TComboBox.Create(Self);
  ThinkingCombo.Parent := Self;
  ThinkingCombo.Left := 16;
  ThinkingCombo.Top := 370;
  ThinkingCombo.Width := 220;
  ThinkingCombo.Style := csDropDownList;
  ThinkingCombo.Items.Add('Low');
  ThinkingCombo.Items.Add('Medium');
  ThinkingCombo.Items.Add('High');
  ThinkingCombo.Items.Add('XHigh');
  ThinkingCombo.ItemIndex := 2;

  ApprovalLabel := TLabel.Create(Self);
  ApprovalLabel.Parent := Self;
  ApprovalLabel.Left := 260;
  ApprovalLabel.Top := 350;
  ApprovalLabel.Caption := 'Approval level (tool writes):';

  ApprovalCombo := TComboBox.Create(Self);
  ApprovalCombo.Parent := Self;
  ApprovalCombo.Left := 260;
  ApprovalCombo.Top := 370;
  ApprovalCombo.Width := 244;
  ApprovalCombo.Style := csDropDownList;
  ApprovalCombo.Items.Add('Ask — confirm each write/compile');
  ApprovalCombo.Items.Add('Auto — allow project tools');
  ApprovalCombo.Items.Add('Always — never prompt (like Build always-approve)');
  ApprovalCombo.ItemIndex := 0;

  { Place below thinking/approval (may already exist from the .lfm). }
  If Not Assigned(AutoNewChatDefaultCheck) Then
    Begin
      AutoNewChatDefaultCheck := TCheckBox.Create(Self);
      AutoNewChatDefaultCheck.Parent := Self;
      AutoNewChatDefaultCheck.Left := 16;
      AutoNewChatDefaultCheck.Width := 488;
      AutoNewChatDefaultCheck.Caption :=
        'Default: automatically start a New Chat at 95% context use';
    End;
  AutoNewChatDefaultCheck.Top := 404;
  AutoNewChatDefaultCheck.ShowHint := True;
  AutoNewChatDefaultCheck.Hint :=
    'When a Grok chat reaches 95% of the context budget, start a new conversation automatically.';
  If Not Assigned(SearchCombo) Then
    Begin
      SearchLabel := TLabel.Create(Self);
      SearchLabel.Parent := Self;
      SearchLabel.Left := 16;
      SearchLabel.Caption := 'Live search:';
      SearchCombo := TComboBox.Create(Self);
      SearchCombo.Parent := Self;
      SearchCombo.Left := 16;
      SearchCombo.Width := 220;
      SearchCombo.Style := csDropDownList;
      SearchCombo.Items.Add('Off');
      SearchCombo.Items.Add('Auto');
      SearchCombo.Items.Add('On');
      SearchCombo.ItemIndex := 0;
      SearchCombo.OnChange := @GrokSearchModeChange;
      CitationsCheck := TCheckBox.Create(Self);
      CitationsCheck.Parent := Self;
      CitationsCheck.Left := 16;
      CitationsCheck.Width := 420;
      CitationsCheck.Caption := 'Return citations';
      VerbosityLabel := TLabel.Create(Self);
      VerbosityLabel.Parent := Self;
      VerbosityLabel.Left := 16;
      VerbosityLabel.Caption := 'Answer length:';
      VerbosityCombo := TComboBox.Create(Self);
      VerbosityCombo.Parent := Self;
      VerbosityCombo.Left := 16;
      VerbosityCombo.Width := 220;
      VerbosityCombo.Style := csDropDownList;
      VerbosityCombo.Items.Add('Low');
      VerbosityCombo.Items.Add('Medium');
      VerbosityCombo.Items.Add('High');
      VerbosityCombo.ItemIndex := 1;
      MaxOutputLabel := TLabel.Create(Self);
      MaxOutputLabel.Parent := Self;
      MaxOutputLabel.Left := 16;
      MaxOutputLabel.Caption := 'Max output tokens (0 = provider default):';
      MaxOutputEdit := TSpinEdit.Create(Self);
      MaxOutputEdit.Parent := Self;
      MaxOutputEdit.Left := 16;
      MaxOutputEdit.Width := 120;
      MaxOutputEdit.MinValue := 0;
      MaxOutputEdit.MaxValue := 1000000;
      MaxOutputEdit.Increment := 1024;
      MaxOutputEdit.Value := 0;
    End;
  SearchLabel.Top := 430;
  SearchCombo.Top := 450;
  CitationsCheck.Top := 486;
  VerbosityLabel.Top := 520;
  VerbosityCombo.Top := 540;
  MaxOutputLabel.Top := 576;
  MaxOutputEdit.Top := 596;
  SearchCombo.ShowHint := True;
  SearchCombo.Hint := 'Off sends no search. Auto lets Grok decide. On asks it to search on the completions fallback.';
  CitationsCheck.ShowHint := True;
  CitationsCheck.Hint := 'Ask the completions fallback to return source citations. The Responses path returns search sources with the search tools.';
  VerbosityCombo.ShowHint := True;
  VerbosityCombo.Hint := 'Length of the visible answer. Separate from reasoning level. Sent on the Responses path.';
  MaxOutputEdit.ShowHint := True;
  MaxOutputEdit.Hint := '0 uses the provider default.';
End;

Procedure TAssistantSettingsForm.FormCreate(Sender: TObject);
Begin
  Caption := 'Project Assistant Settings';
  ButtonPanel.OKButton.Caption := 'OK';
  ButtonPanel.CancelButton.Caption := 'Cancel';
  EnsureExtraControls;
  If Assigned(ModelList) Then
    ModelList.OnSelectionChange := @GrokModelSelectionChange;
  BuildSettingsPages;
  PopulateSkills;
  RefreshAuthStatus;
End;

Destructor TAssistantSettingsForm.Destroy;
Begin
  Connections.Free;
  Inherited Destroy;
End;

Procedure TAssistantSettingsForm.BuildSettingsPages;
Var Pages: TPageControl; ConnectionPage, GeneralPage, TestPage: TTabSheet;
  Sidebar, Details, Header: TPanel; Control: TControl; I: Integer; Button: TButton;
  LabelControl: TLabel;
Begin
  SelectedConnection := -1;
  ClientWidth := 960; ClientHeight := 760;
  Constraints.MinWidth := 900; Constraints.MinHeight := 650;
  BorderStyle := bsSizeable;
  Connections := TAssistantConnections.Create(LazarusIDE.GetPrimaryConfigPath);
  Connections.Load;
  Pages := TPageControl.Create(Self); Pages.Name := 'SettingsPages'; Pages.Parent := Self; Pages.Align := alClient;
  ConnectionPage := TTabSheet.Create(Pages); ConnectionPage.PageControl := Pages; ConnectionPage.Caption := 'Connections';
  GeneralPage := TTabSheet.Create(Pages); GeneralPage.PageControl := Pages; GeneralPage.Caption := 'General';
  TestPage := TTabSheet.Create(Pages); TestPage.PageControl := Pages; TestPage.Caption := 'Target tests';
  TestFrame := TAssistantTestSettingsFrame.Create(Self); TestFrame.Name := 'ProjectTestSettings'; TestFrame.Parent := TestPage; TestFrame.Align := alClient;
  If AssistantTarget.Available Then
    TestFrame.Load(AssistantTarget.StoreDirectory, AssistantTarget.Manifest)
  Else
    TestFrame.Load('', '');
  Sidebar := TPanel.Create(Self); Sidebar.Parent := ConnectionPage; Sidebar.Align := alLeft; Sidebar.Width := 220; Sidebar.BevelOuter := bvNone;
  Button := TButton.Create(Self); Button.Parent := Sidebar; Button.Name := 'AddConnectionButton'; Button.Caption := 'Add ChatGPT connection'; Button.Align := alBottom; Button.Height := 36; Button.OnClick := @AddConnection;
  Button := TButton.Create(Self); Button.Parent := Sidebar; Button.Caption := 'Remove connection'; Button.Align := alBottom; Button.Height := 36; Button.OnClick := @RemoveConnection;
  Button.ShowHint := True;
  Button.Hint := 'Removes the saved definition only. The Codex profile directory is kept.';
  ConnectionList := TListBox.Create(Self); ConnectionList.Name := 'ConnectionsList'; ConnectionList.Parent := Sidebar; ConnectionList.Align := alClient; ConnectionList.OnClick := @ConnectionChanged;
  Details := TPanel.Create(Self); Details.Parent := ConnectionPage; Details.Align := alClient; Details.BevelOuter := bvNone;
  Header := TPanel.Create(Self); Header.Parent := Details; Header.Align := alTop; Header.Height := 112; Header.BevelOuter := bvNone;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Header; LabelControl.SetBounds(16, 8, 150, 20); LabelControl.Caption := 'Connection name';
  ConnectionName := TEdit.Create(Self); ConnectionName.Name := 'ConnectionNameEdit'; ConnectionName.Parent := Header; ConnectionName.SetBounds(16, 30, 400, 28);
  Button := TButton.Create(Self); Button.Parent := Header; Button.SetBounds(430, 30, 230, 28); Button.Name := 'UseConnectionButton'; Button.Caption := 'Use for current chat'; Button.OnClick := @UseConnection;
  Button.ShowHint := True;
  Button.Hint := 'Switches the open assistant chat to this connection immediately.';
  ActiveConnectionLabel := TLabel.Create(Self); ActiveConnectionLabel.Parent := Header; ActiveConnectionLabel.SetBounds(16, 70, 650, 32); ActiveConnectionLabel.AutoSize := False; ActiveConnectionLabel.WordWrap := True;
  GrokPanel := TScrollBox.Create(Self); GrokPanel.Parent := Details; GrokPanel.Align := alClient; GrokPanel.BorderStyle := bsNone;
  { Reuse Grok's existing account and model controls inside its own connection
    details, retaining the established credential owner. }
  For I := ControlCount - 1 DownTo 0 Do
    Begin
      Control := Controls[I];
      If (Control = Pages) Or (Control = ButtonPanel) Then Continue;
      Control.Anchors := [akLeft, akTop];
      Control.Parent := GrokPanel;
    End;
  SpellButton.Visible := False;
  IncludeContextCheck.Parent := GeneralPage; IncludeContextCheck.SetBounds(20, 20, 700, 24);
  AutoNewChatDefaultCheck.Parent := GeneralPage; AutoNewChatDefaultCheck.SetBounds(20, 52, 800, 24);
  AutoNewChatDefaultCheck.Caption := 'Automatically start a new Grok chat at 95% context use';
  ShowThinkingCheck.Parent := GeneralPage; ShowThinkingCheck.SetBounds(20, 84, 800, 24);
  ShowToolCallsCheck.Parent := GeneralPage; ShowToolCallsCheck.SetBounds(20, 116, 800, 24);
  SpellFrame := TSpellCheckerSettingsFrame.Create(Self); SpellFrame.Name := 'GlobalSpellSettings'; SpellFrame.Parent := GeneralPage;
  SpellFrame.SetBounds(20, 156, 820, 260); SpellFrame.Anchors := [akLeft, akTop]; SpellFrame.LoadFromConfig;
  GeneralPage.OnResize := @GeneralPageResize;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := GeneralPage;
  LabelControl.SetBounds(20, 432, 800, 70); LabelControl.AutoSize := False; LabelControl.WordWrap := True;
  LabelControl.Caption := 'These preferences apply across connections. Sign-in, sign-out and Use for current chat take effect immediately. ' +
    'Cancel discards other preference edits. Selecting a connection does not sign out other accounts.';
  If Assigned(SearchLabel) Then
    Begin
      SearchLabel.Top := 430; SearchCombo.Top := 450;
      CitationsCheck.Top := 486;
      VerbosityLabel.Top := 520; VerbosityCombo.Top := 540;
      MaxOutputLabel.Top := 576; MaxOutputEdit.Top := 596;
    End;
  ApiBaseLabel.Top := 640; ApiBaseEdit.Top := 662;
  ManualLabel.Top := 706; ManualEdit.Top := 730; PasteCodeButton.Top := 730;
  HintLabel.Top := 774;
  ThinkingLabel.Caption := 'Grok reasoning level'; ApprovalLabel.Caption := 'Grok tool approvals';
  CodexFrame := TCodexConnectionFrame.Create(Self); CodexFrame.Parent := Details; CodexFrame.Align := alClient;
  RefreshConnections;
  For I := 0 To Connections.Count - 1 Do
    If Connections[I].Id = Connections.ActiveId Then ConnectionList.ItemIndex := I;
  ConnectionChanged(Nil);
  Pages.ActivePage := ConnectionPage;
End;

Procedure TAssistantSettingsForm.GeneralPageResize(Sender: TObject);
Begin
  If Assigned(SpellFrame) And Assigned(SpellFrame.Parent) Then
    SpellFrame.Width := SpellFrame.Parent.ClientWidth - 40;
End;

Procedure TAssistantSettingsForm.StoreConnection;
Var Item: TAssistantConnection;
Begin
  If (SelectedConnection < 0) Or (SelectedConnection >= Connections.Count) Then Exit;
  Item := Connections[SelectedConnection];
  If Trim(ConnectionName.Text) <> '' Then Item.Name := Trim(ConnectionName.Text);
  If Item.Backend = 'codex' Then
    Begin
      Item.Runtime := Trim(CodexFrame.RuntimeEdit.Text);
      Item.Model := Trim(CodexFrame.ModelCombo.Text);
      Item.ReasoningEffort := CodexFrame.ReasoningEffort;
      Item.ApprovalMode := CodexFrame.ApprovalMode;
      Item.CachedModelsJson := CodexFrame.CachedModelsJson;
    End;
End;

Procedure TAssistantSettingsForm.RefreshConnections;
Var I, Selected: Integer; Item: TAssistantConnection;
Begin
  Selected := ConnectionList.ItemIndex;
  ConnectionList.Items.Clear;
  For I := 0 To Connections.Count - 1 Do
    Begin
      Item := Connections[I];
      If Item.Id = Connections.ActiveId Then ConnectionList.Items.Add(Item.Name + ' (current)')
      Else ConnectionList.Items.Add(Item.Name);
    End;
  If Selected >= Connections.Count Then Selected := Connections.Count - 1;
  ConnectionList.ItemIndex := Selected;
  Item := Connections.Active;
  If Assigned(Item) Then
    ActiveConnectionLabel.Caption := 'Current chat: ' + Item.Name + '. The assistant status bar uses this connection.';
End;

Procedure TAssistantSettingsForm.ConnectionChanged(Sender: TObject);
Var Item: TAssistantConnection; NewSelection: Integer;
Begin
  If CodexFrame.Busy Then
    Begin
      ConnectionList.ItemIndex := SelectedConnection;
      Exit;
    End;
  NewSelection := ConnectionList.ItemIndex;
  StoreConnection; RefreshConnections;
  SelectedConnection := NewSelection; ConnectionList.ItemIndex := NewSelection;
  If SelectedConnection < 0 Then Exit;
  Item := Connections[SelectedConnection]; ConnectionName.Text := Item.Name;
  GrokPanel.Visible := Item.Backend = 'grok'; CodexFrame.Visible := Item.Backend = 'codex';
  If Item.Backend = 'codex' Then CodexFrame.LoadConnection(Connections.ProfileDir(Item), Item.Runtime, Item.Model, Item.ReasoningEffort, Item.ApprovalMode, Item.CachedModelsJson);
End;

Procedure TAssistantSettingsForm.AddConnection(Sender: TObject);
Begin
  If CodexFrame.Busy Then Exit;
  StoreConnection; Connections.AddChatGPT; RefreshConnections;
  SelectedConnection := -1; ConnectionList.ItemIndex := Connections.Count - 1; ConnectionChanged(Nil);
End;

Procedure TAssistantSettingsForm.RemoveConnection(Sender: TObject);
Begin
  If CodexFrame.Busy Or (SelectedConnection < 0) Then Exit;
  If Connections[SelectedConnection].Backend = 'grok' Then
    Begin
      MessageDlg('The existing Grok account is managed using Sign out.', mtInformation, [mbOK], 0);
      Exit;
    End;
  Connections.Remove(SelectedConnection); SelectedConnection := -1;
  RefreshConnections; ConnectionList.ItemIndex := 0; ConnectionChanged(Nil);
End;

Procedure TAssistantSettingsForm.UseConnection(Sender: TObject);
Var
  PreviousId: String;
Begin
  StoreConnection;
  If SelectedConnection < 0 Then Exit;
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

Procedure TAssistantSettingsForm.PopulateSkills;
Var
  Skills: TAssistantSkillList;
  I, SelectIdx: Integer;
  ActiveName, Root, SkillRoot: String;
Begin
  ActiveName := '';
  If Assigned(AssistantChatConfig) Then
    ActiveName := AssistantChatConfig.ActiveSkill;
  Root := '';
  If Assigned(ProjectAssistantConversation) Then
    Root := ProjectAssistantConversation.ProjectRoot;
  If Root = '' Then
    Root := AssistantUserSkillsRoot;
  SkillCombo.Style := csDropDownList;
  SkillCombo.Items.BeginUpdate;
  Try
    SkillCombo.Items.Clear;
    SkillCombo.Items.Add(AssistantSkillNoneCaption);
    SelectIdx := 0;
    If Assigned(ProjectAssistantConversation) Then
      Skills := ListDiscoveredSkills(ProjectAssistantConversation.ProjectRoot)
    Else
      Skills := ListUserSkills;
    For I := 0 To High(Skills) Do
      Begin
        SkillCombo.Items.Add(Skills[I].Name);
        If SameText(Skills[I].Name, ActiveName) Then
          SelectIdx := SkillCombo.Items.Count - 1;
      End;
  Finally
    SkillCombo.Items.EndUpdate;
  End;
  SkillCombo.ItemIndex := SelectIdx;
  { Show the real scan path — ~/.grok is per OS user profile, not cloud-synced. }
  If Assigned(HintLabel) Then
    Begin
      If Assigned(ProjectAssistantConversation) And (ProjectAssistantConversation.ProjectRoot <> '') Then
        SkillRoot := IncludeTrailingPathDelimiter(ProjectAssistantConversation.ProjectRoot) + '.assistant' + PathDelim + 'skills'
      Else
        SkillRoot := AssistantUserSkillsRoot;
      If Length(Skills) = 0 Then
        HintLabel.Caption :=
          'No skills found. Create ' + SkillRoot + PathDelim + '<name>' + PathDelim + 'SKILL.md.' + LineEnding +
          'Skills load from .assistant/skills, then ' + AssistantUserSkillsRoot + '.'
      Else
        HintLabel.Caption :=
          Format('Loaded %d skill(s) from .assistant/skills, then %s', [Length(Skills), AssistantUserSkillsRoot]) +
          LineEnding +
          'Pin is extra session context. Plan and Build always attach free-pascal-engineer when it is installed. ' +
          'Use read_skill for other catalog entries.';
    End;
End;

Procedure TAssistantSettingsForm.PopulateModels(ForceRefresh: Boolean);
Var
  ErrorText, CurrentModel: String;
  Ok: Boolean;
Begin
  FFillingModels := True;
  CurrentModel := AssistantConfigDefaultModel;
  If Assigned(AssistantChatConfig) And (Trim(AssistantChatConfig.Model) <> '') Then
    CurrentModel := AssistantChatConfig.Model;

  ModelList.Items.BeginUpdate;
  Try
    ModelList.Items.Clear;
    Ok := False;
    ErrorText := '';
    If Assigned(AssistantClient) And AssistantClient.IsSignedIn And
      ForceRefresh Then
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
      ModelHintLabel.Caption := Format('%d models available. Select one, then OK.',
        [ModelList.Items.Count]);

    DecorateModelList(ModelList.Items);
    SelectModelInList(ModelList, CurrentModel);
    If Assigned(AssistantChatConfig) Then
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
  If (Not User) Or FFillingModels Or (Not Assigned(ThinkingCombo)) Then
    Exit;
  Effort := 'high';
  If ThinkingCombo.ItemIndex >= 0 Then
    Effort := EffortFromCaption(ThinkingCombo.Items[ThinkingCombo.ItemIndex]);
  RefreshGrokReasoningChoices(Effort);
End;

Procedure TAssistantSettingsForm.GrokSearchModeChange(Sender: TObject);
Begin
  If Assigned(CitationsCheck) And Assigned(SearchCombo) Then
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
  If Not Assigned(ThinkingCombo) Then
    Exit;
  ModelId := '';
  If Assigned(ModelList) And (ModelList.ItemIndex >= 0) Then
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
Var
  I: Integer;
Begin
  If Not Assigned(AssistantChatConfig) Then
    Exit;
  ApiBaseEdit.Text := AssistantChatConfig.ApiBase;
  IncludeContextCheck.Checked := AssistantChatConfig.IncludeIDEContext;
  EnsureExtraControls;
  If Assigned(AutoNewChatDefaultCheck) Then
    AutoNewChatDefaultCheck.Checked := AssistantChatConfig.AutoNewChatAtContextLimit;
  If Assigned(ShowThinkingCheck) Then
    ShowThinkingCheck.Checked := AssistantChatConfig.ShowThinking;
  If Assigned(ShowToolCallsCheck) Then
    ShowToolCallsCheck.Checked := AssistantChatConfig.ShowToolCalls;
  RefreshGrokReasoningChoices(AssistantChatConfig.ThinkingLevel);
  If Assigned(SearchCombo) Then
    Begin
      If SameText(AssistantChatConfig.SearchMode, 'on') Then
        SearchCombo.ItemIndex := 2
      Else If SameText(AssistantChatConfig.SearchMode, 'auto') Then
        SearchCombo.ItemIndex := 1
      Else
        SearchCombo.ItemIndex := 0;
      GrokSearchModeChange(Nil);
    End;
  If Assigned(CitationsCheck) Then
    CitationsCheck.Checked := AssistantChatConfig.SearchCitations;
  If Assigned(VerbosityCombo) Then
    Begin
      If SameText(AssistantChatConfig.AnswerVerbosity, 'low') Then
        VerbosityCombo.ItemIndex := 0
      Else If SameText(AssistantChatConfig.AnswerVerbosity, 'high') Then
        VerbosityCombo.ItemIndex := 2
      Else
        VerbosityCombo.ItemIndex := 1;
    End;
  If Assigned(MaxOutputEdit) Then
    MaxOutputEdit.Value := AssistantChatConfig.MaxOutputTokens;
  Case AssistantChatConfig.GetApprovalMode Of
    aamAsk: ApprovalCombo.ItemIndex := 0;
    aamAuto: ApprovalCombo.ItemIndex := 1;
  Else
    ApprovalCombo.ItemIndex := 2;
  End;
  PopulateSkills;
  If AssistantChatConfig.ActiveSkill = '' Then
    SkillCombo.ItemIndex := 0
  Else
    Begin
      I := SkillCombo.Items.IndexOf(AssistantChatConfig.ActiveSkill);
      If I >= 0 Then
        SkillCombo.ItemIndex := I
      Else
        Begin
          { Skill was removed from disk; keep name visible until user clears it. }
          SkillCombo.Items.Add(AssistantChatConfig.ActiveSkill + ' (missing)');
          SkillCombo.ItemIndex := SkillCombo.Items.Count - 1;
        End;
    End;
  If Assigned(GrokOAuthClient) And AssistantChatConfig.IsSignedIn Then
    GrokOAuthClient.SetTokens(AssistantChatConfig.ToOAuthTokens);
  If Assigned(AssistantClient) Then
    AssistantClient.ApplyConfig(AssistantChatConfig);
  RefreshAuthStatus;
  PopulateModels(False);
End;

Procedure TAssistantSettingsForm.SaveToConfig;
Var
  SkillName, ModelName: String;
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

  SkillName := '';
  If (SkillCombo.ItemIndex > 0) And (SkillCombo.ItemIndex < SkillCombo.Items.Count) Then
    Begin
      SkillName := SkillCombo.Items[SkillCombo.ItemIndex];
      If Pos(' (missing)', SkillName) > 0 Then
        SkillName := Copy(SkillName, 1, Pos(' (missing)', SkillName) - 1);
    End;
  AssistantChatConfig.ActiveSkill := SkillName;
  AssistantChatConfig.IncludeIDEContext := IncludeContextCheck.Checked;
  EnsureExtraControls;
  If Assigned(AutoNewChatDefaultCheck) Then
    AssistantChatConfig.AutoNewChatAtContextLimit := AutoNewChatDefaultCheck.Checked;
  If Assigned(ShowThinkingCheck) Then
    AssistantChatConfig.ShowThinking := ShowThinkingCheck.Checked;
  If Assigned(ShowToolCallsCheck) Then
    AssistantChatConfig.ShowToolCalls := ShowToolCallsCheck.Checked;
  If Assigned(SearchCombo) Then
    Begin
      Case SearchCombo.ItemIndex Of
        1: AssistantChatConfig.SearchMode := 'auto';
        2: AssistantChatConfig.SearchMode := 'on';
      Else
        AssistantChatConfig.SearchMode := 'off';
      End;
    End;
  If Assigned(CitationsCheck) Then
    AssistantChatConfig.SearchCitations := CitationsCheck.Checked;
  If Assigned(VerbosityCombo) Then
    Begin
      Case VerbosityCombo.ItemIndex Of
        0: AssistantChatConfig.AnswerVerbosity := 'low';
        2: AssistantChatConfig.AnswerVerbosity := 'high';
      Else
        AssistantChatConfig.AnswerVerbosity := 'medium';
      End;
    End;
  If Assigned(MaxOutputEdit) Then
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
  SpellFrame.SaveToConfig;
  TestFrame.Save;
End;

Procedure TAssistantSettingsForm.RefreshModelsButtonClick(Sender: TObject);
Begin
  If Assigned(AssistantClient) Then
    AssistantClient.SetEndpoint(Trim(ApiBaseEdit.Text), AssistantClient.Model);
  PopulateModels(True);
End;

Procedure TAssistantSettingsForm.SpellButtonClick(Sender: TObject);
Begin
  ShowSpellCheckerSettingsDialog;
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
    Else
      Begin
        If GrokOAuthClient.HasPendingLogin Then
          MessageDlg('Browser callback did not finish: ' + GrokOAuthClient.LastError + LineEnding +
            LineEnding +
            'If the browser showed a code (or a localhost URL with ?code=…), paste it below once and click "Use pasted code".',
            mtWarning, [mbOK], 0)
        Else
          MessageDlg('Sign-in failed: ' + GrokOAuthClient.LastError, mtWarning, [mbOK], 0);
      End;
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
Var Note: String;
Begin
  CanClose := True;
  If ModalResult <> mrOk Then
    Exit;
  If Not TestFrame.Validate(Note) Then
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
  If Assigned(Connections.Active) And (Connections.Active.Backend = 'codex') And
    ((Connections.Active.Runtime = '') Or (Connections.Active.Model = '')) Then
    Begin
      CanClose := False;
      MessageDlg('The current ChatGPT connection needs a runtime and model.', mtInformation, [mbOK], 0);
      Exit;
    End;
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

End.
