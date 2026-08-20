Unit AssistantSettingsForm;

{ LazAssistantTools OAuth sign-in, model and skill settings dialog (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ButtonPanel;

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
  Public
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
  LCLIntf, SpellCheckerSettingsForm;

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
  ThinkingLabel.Caption := 'Thinking level (reasoning effort):';

  ThinkingCombo := TComboBox.Create(Self);
  ThinkingCombo.Parent := Self;
  ThinkingCombo.Left := 16;
  ThinkingCombo.Top := 370;
  ThinkingCombo.Width := 220;
  ThinkingCombo.Style := csDropDownList;
  ThinkingCombo.Items.Add('Low');
  ThinkingCombo.Items.Add('Medium');
  ThinkingCombo.Items.Add('High');
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
    'Default for the assistant form checkbox. Long Code/Plan runs can rollover into a fresh chat.';
End;

Procedure TAssistantSettingsForm.FormCreate(Sender: TObject);
Begin
  Caption := 'Project Assistant Settings';
  ButtonPanel.OKButton.Caption := 'OK';
  ButtonPanel.CancelButton.Caption := 'Cancel';
  EnsureExtraControls;
  PopulateSkills;
  RefreshAuthStatus;
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
  Root := AssistantUserSkillsRoot;
  SkillCombo.Style := csDropDownList;
  SkillCombo.Items.BeginUpdate;
  Try
    SkillCombo.Items.Clear;
    SkillCombo.Items.Add(AssistantSkillNoneCaption);
    SelectIdx := 0;
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
          Format('Loaded %d skill(s) from %s', [Length(Skills), Root]) + LineEnding +
          'Each skill is a subfolder with SKILL.md. Skills are not auto-synced across platforms. ' +
          'IDE context attaches the active source unit (or selection) and project file list.';
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
      (ForceRefresh Or Assigned(GrokOAuthClient)) Then
      Begin
        ModelHintLabel.Caption := 'Loading models…';
        Application.ProcessMessages;
        Ok := AssistantClient.ListAvailableModels(ModelList.Items, ErrorText);
      End
    Else
      ErrorText := 'Sign in to load the live model list.';

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
  PopulateModels(True);
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
Begin
  CanClose := True;
  If ModalResult <> mrOk Then
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

End.
