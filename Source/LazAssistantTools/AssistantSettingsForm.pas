Unit AssistantSettingsForm;

{ LazAssistantTools OAuth sign-in, model and skill settings dialog (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ButtonPanel, ComCtrls, AssistantConnections, AssistantCodexSettings, SpellCheckerSettingsFrame, AssistantTestSettingsFrame;

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
    ThinkingLabel: TLabel;
    ThinkingCombo: TComboBox;
    ApprovalLabel: TLabel;
    ApprovalCombo: TComboBox;
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
    Procedure BuildSettingsPages;
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

Uses
  AssistantConfig, AssistantService, GrokOAuth, AssistantSkills, AssistantHttps, WorkflowLog,
  AssistantConversation,
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
Begin
  If ModelName = '' Then
    Exit;
  I := List.Items.IndexOf(ModelName);
  If I >= 0 Then
    List.ItemIndex := I
  Else
    Begin
      List.Items.Insert(0, ModelName);
      List.ItemIndex := 0;
    End;
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
    'Default for the assistant form checkbox. Long Build/Plan runs can rollover into a fresh chat.';
End;

Procedure TAssistantSettingsForm.FormCreate(Sender: TObject);
Begin
  Caption := 'Project Assistant Settings';
  ButtonPanel.OKButton.Caption := 'OK';
  ButtonPanel.CancelButton.Caption := 'Cancel';
  EnsureExtraControls;
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
  TestPage := TTabSheet.Create(Pages); TestPage.PageControl := Pages; TestPage.Caption := 'Project tests';
  TestFrame := TAssistantTestSettingsFrame.Create(Self); TestFrame.Name := 'ProjectTestSettings'; TestFrame.Parent := TestPage; TestFrame.Align := alClient;
  If Assigned(LazarusIDE.ActiveProject) Then TestFrame.Load(LazarusIDE.GetPrimaryConfigPath, LazarusIDE.ActiveProject.ProjectInfoFile)
  Else TestFrame.Load(LazarusIDE.GetPrimaryConfigPath, '');
  Sidebar := TPanel.Create(Self); Sidebar.Parent := ConnectionPage; Sidebar.Align := alLeft; Sidebar.Width := 220; Sidebar.BevelOuter := bvNone;
  Button := TButton.Create(Self); Button.Parent := Sidebar; Button.Name := 'AddConnectionButton'; Button.Caption := 'Add ChatGPT connection'; Button.Align := alBottom; Button.Height := 36; Button.OnClick := @AddConnection;
  Button := TButton.Create(Self); Button.Parent := Sidebar; Button.Caption := 'Remove connection'; Button.Align := alBottom; Button.Height := 36; Button.OnClick := @RemoveConnection;
  ConnectionList := TListBox.Create(Self); ConnectionList.Name := 'ConnectionsList'; ConnectionList.Parent := Sidebar; ConnectionList.Align := alClient; ConnectionList.OnClick := @ConnectionChanged;
  Details := TPanel.Create(Self); Details.Parent := ConnectionPage; Details.Align := alClient; Details.BevelOuter := bvNone;
  Header := TPanel.Create(Self); Header.Parent := Details; Header.Align := alTop; Header.Height := 112; Header.BevelOuter := bvNone;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Header; LabelControl.SetBounds(16, 8, 150, 20); LabelControl.Caption := 'Connection name';
  ConnectionName := TEdit.Create(Self); ConnectionName.Name := 'ConnectionNameEdit'; ConnectionName.Parent := Header; ConnectionName.SetBounds(16, 30, 400, 28);
  Button := TButton.Create(Self); Button.Parent := Header; Button.SetBounds(430, 30, 230, 28); Button.Name := 'UseConnectionButton'; Button.Caption := 'Use for current chat'; Button.OnClick := @UseConnection;
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
  SpellFrame := TSpellCheckerSettingsFrame.Create(Self); SpellFrame.Name := 'GlobalSpellSettings'; SpellFrame.Parent := GeneralPage;
  SpellFrame.SetBounds(20, 104, 820, 230); SpellFrame.Anchors := [akLeft, akTop]; SpellFrame.LoadFromConfig;
  GeneralPage.OnResize := @GeneralPageResize;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := GeneralPage;
  LabelControl.SetBounds(20, 358, 800, 70); LabelControl.AutoSize := False; LabelControl.WordWrap := True;
  LabelControl.Caption := 'These preferences apply across connections. Sign-in and sign-out actions take effect immediately; Cancel discards preference edits. Selecting a connection does not sign out other accounts.';
  ApiBaseLabel.Top := 418; ApiBaseEdit.Top := 440;
  ManualLabel.Top := 484; ManualEdit.Top := 508; PasteCodeButton.Top := 508;
  HintLabel.Top := 552;
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
    Begin Item.Runtime := Trim(CodexFrame.RuntimeEdit.Text); Item.Model := Trim(CodexFrame.ModelCombo.Text);
      Item.ReasoningEffort := CodexFrame.ReasoningEffort; Item.ApprovalMode := CodexFrame.ApprovalMode; End;
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
  If Assigned(Item) Then ActiveConnectionLabel.Caption := 'Current chat: ' + Item.Name + '. Other saved connections remain available.';
End;

Procedure TAssistantSettingsForm.ConnectionChanged(Sender: TObject);
Var Item: TAssistantConnection; NewSelection: Integer;
Begin
  If CodexFrame.Busy Then Begin ConnectionList.ItemIndex := SelectedConnection; Exit; End;
  NewSelection := ConnectionList.ItemIndex;
  StoreConnection; RefreshConnections;
  SelectedConnection := NewSelection; ConnectionList.ItemIndex := NewSelection;
  If SelectedConnection < 0 Then Exit;
  Item := Connections[SelectedConnection]; ConnectionName.Text := Item.Name;
  GrokPanel.Visible := Item.Backend = 'grok'; CodexFrame.Visible := Item.Backend = 'codex';
  If Item.Backend = 'codex' Then CodexFrame.LoadConnection(Connections.ProfileDir(Item), Item.Runtime, Item.Model, Item.ReasoningEffort, Item.ApprovalMode);
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
    Begin MessageDlg('The existing Grok account is managed using Sign out.', mtInformation, [mbOK], 0); Exit; End;
  Connections.Remove(SelectedConnection); SelectedConnection := -1;
  RefreshConnections; ConnectionList.ItemIndex := 0; ConnectionChanged(Nil);
End;

Procedure TAssistantSettingsForm.UseConnection(Sender: TObject);
Begin
  StoreConnection;
  If SelectedConnection < 0 Then Exit;
  If (Connections[SelectedConnection].Backend = 'codex') And
    ((Connections[SelectedConnection].Runtime = '') Or (Connections[SelectedConnection].Model = '')) Then
    Begin MessageDlg('Choose the runtime and sign in or refresh models first.', mtInformation, [mbOK], 0); Exit; End;
  Connections.ActiveId := Connections[SelectedConnection].Id; RefreshConnections;
End;

Procedure TAssistantSettingsForm.PopulateSkills;
Var
  Skills: TAssistantSkillList;
  I, SelectIdx: Integer;
  ActiveName, Root: String;
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
      If Length(Skills) = 0 Then
        HintLabel.Caption :=
          'No skills found. Skills are local to this OS user (not shared across Windows/Linux).' +
          LineEnding +
          'Create folders as: ' + Root + PathDelim + '<name>' + PathDelim + 'SKILL.md' +
          LineEnding +
          'Copy from another machine''s ~/.grok/skills if needed. IDE context still attaches the active unit.'
      Else
        HintLabel.Caption :=
          Format('Loaded %d skill(s) from project, .assistant, and %s', [Length(Skills), AssistantUserSkillsRoot]) +
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

    SelectModelInList(ModelList, CurrentModel);
  Finally
    ModelList.Items.EndUpdate;
  End;
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
  Case AssistantChatConfig.GetThinkingLevel Of
    atlLow: ThinkingCombo.ItemIndex := 0;
    atlMedium: ThinkingCombo.ItemIndex := 1;
    atlXHigh: ThinkingCombo.ItemIndex := 3;
  Else
    ThinkingCombo.ItemIndex := 2;
  End;
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
    ModelName := Trim(ModelList.Items[ModelList.ItemIndex]);
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
  Case ThinkingCombo.ItemIndex Of
    0: AssistantChatConfig.SetThinkingLevelEnum(atlLow);
    1: AssistantChatConfig.SetThinkingLevelEnum(atlMedium);
    3: AssistantChatConfig.SetThinkingLevelEnum(atlXHigh);
  Else
    AssistantChatConfig.SetThinkingLevelEnum(atlHigh);
  End;
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
    Begin CanClose := False; MessageDlg(Note, mtError, [mbOK], 0); Exit; End;
  StoreConnection;
  If CodexFrame.Busy Then
    Begin CanClose := False; MessageDlg('Wait for the connection check, or Cancel to close settings.', mtInformation, [mbOK], 0); Exit; End;
  If Assigned(Connections.Active) And (Connections.Active.Backend = 'codex') And
    ((Connections.Active.Runtime = '') Or (Connections.Active.Model = '')) Then
    Begin CanClose := False; MessageDlg('The current ChatGPT connection needs a runtime and model.', mtInformation, [mbOK], 0); Exit; End;
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
