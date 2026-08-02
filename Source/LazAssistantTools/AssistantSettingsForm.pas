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
    FStatusLabel: TLabel;
    FStatusValue: TLabel;
    FModelLabel: TLabel;
    FModelList: TListBox;
    FModelHintLabel: TLabel;
    FRefreshModelsButton: TButton;
    FSkillLabel: TLabel;
    FSkillCombo: TComboBox;
    FIncludeContextCheck: TCheckBox;
    FThinkingLabel: TLabel;
    FThinkingCombo: TComboBox;
    FApprovalLabel: TLabel;
    FApprovalCombo: TComboBox;
    FApiBaseLabel: TLabel;
    FApiBaseEdit: TEdit;
    FHintLabel: TLabel;
    FManualLabel: TLabel;
    FManualEdit: TEdit;
    FSignInButton: TButton;
    FSignOutButton: TButton;
    FPasteCodeButton: TButton;
    FButtonPanel: TButtonPanel;
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
    Procedure FormCreate(Sender: TObject);
    Procedure SignInButtonClick(Sender: TObject);
    Procedure SignOutButtonClick(Sender: TObject);
    Procedure PasteCodeButtonClick(Sender: TObject);
    Procedure RefreshModelsButtonClick(Sender: TObject);
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
  AssistantConfig, AssistantService, GrokOAuth, AssistantSkills, WorkflowLog, LCLIntf;

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
  If Assigned(FThinkingCombo) Then
    Exit;
  ClientHeight := ClientHeight + 90;
  If Assigned(FButtonPanel) Then
    FButtonPanel.Top := FButtonPanel.Top + 90;
  If Assigned(FHintLabel) Then
    FHintLabel.Top := FHintLabel.Top + 90;
  If Assigned(FManualLabel) Then
    FManualLabel.Top := FManualLabel.Top + 90;
  If Assigned(FManualEdit) Then
    FManualEdit.Top := FManualEdit.Top + 90;
  If Assigned(FPasteCodeButton) Then
    FPasteCodeButton.Top := FPasteCodeButton.Top + 90;
  If Assigned(FApiBaseLabel) Then
    FApiBaseLabel.Top := FApiBaseLabel.Top + 90;
  If Assigned(FApiBaseEdit) Then
    FApiBaseEdit.Top := FApiBaseEdit.Top + 90;

  FThinkingLabel := TLabel.Create(Self);
  FThinkingLabel.Parent := Self;
  FThinkingLabel.Left := 16;
  FThinkingLabel.Top := 350;
  FThinkingLabel.Caption := 'Thinking level (reasoning effort):';

  FThinkingCombo := TComboBox.Create(Self);
  FThinkingCombo.Parent := Self;
  FThinkingCombo.Left := 16;
  FThinkingCombo.Top := 370;
  FThinkingCombo.Width := 220;
  FThinkingCombo.Style := csDropDownList;
  FThinkingCombo.Items.Add('Low');
  FThinkingCombo.Items.Add('Medium');
  FThinkingCombo.Items.Add('High');
  FThinkingCombo.ItemIndex := 2;

  FApprovalLabel := TLabel.Create(Self);
  FApprovalLabel.Parent := Self;
  FApprovalLabel.Left := 260;
  FApprovalLabel.Top := 350;
  FApprovalLabel.Caption := 'Approval level (tool writes):';

  FApprovalCombo := TComboBox.Create(Self);
  FApprovalCombo.Parent := Self;
  FApprovalCombo.Left := 260;
  FApprovalCombo.Top := 370;
  FApprovalCombo.Width := 244;
  FApprovalCombo.Style := csDropDownList;
  FApprovalCombo.Items.Add('Ask — confirm each write/compile');
  FApprovalCombo.Items.Add('Auto — allow project tools');
  FApprovalCombo.Items.Add('Always — never prompt (like Build always-approve)');
  FApprovalCombo.ItemIndex := 2;
End;

Procedure TAssistantSettingsForm.FormCreate(Sender: TObject);
Begin
  Caption := 'Project Assistant Settings';
  FButtonPanel.OKButton.Caption := 'OK';
  FButtonPanel.CancelButton.Caption := 'Cancel';
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
  FSkillCombo.Style := csDropDownList;
  FSkillCombo.Items.BeginUpdate;
  Try
    FSkillCombo.Items.Clear;
    FSkillCombo.Items.Add(AssistantSkillNoneCaption);
    SelectIdx := 0;
    Skills := ListUserSkills;
    For I := 0 To High(Skills) Do
      Begin
        FSkillCombo.Items.Add(Skills[I].Name);
        If SameText(Skills[I].Name, ActiveName) Then
          SelectIdx := FSkillCombo.Items.Count - 1;
      End;
  Finally
    FSkillCombo.Items.EndUpdate;
  End;
  FSkillCombo.ItemIndex := SelectIdx;
  { Show the real scan path — ~/.grok is per OS user profile, not cloud-synced. }
  If Assigned(FHintLabel) Then
    Begin
      If Length(Skills) = 0 Then
        FHintLabel.Caption :=
          'No skills found. Skills are local to this OS user (not shared across Windows/Linux).' +
          LineEnding +
          'Create folders as: ' + Root + PathDelim + '<name>' + PathDelim + 'SKILL.md' +
          LineEnding +
          'Copy from another machine''s ~/.grok/skills if needed. IDE context still attaches the active unit.'
      Else
        FHintLabel.Caption :=
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

  FModelList.Items.BeginUpdate;
  Try
    FModelList.Items.Clear;
    Ok := False;
    ErrorText := '';
    If Assigned(AssistantClient) And AssistantClient.IsSignedIn And
      (ForceRefresh Or Assigned(GrokOAuthClient)) Then
      Begin
        FModelHintLabel.Caption := 'Loading models…';
        Application.ProcessMessages;
        Ok := AssistantClient.ListAvailableModels(FModelList.Items, ErrorText);
      End
    Else
      ErrorText := 'Sign in to load the live model list.';

    If Not Ok Then
      Begin
        AddFallbackModels(FModelList.Items);
        If ErrorText <> '' Then
          FModelHintLabel.Caption := ErrorText + ' Showing fallback list.'
        Else
          FModelHintLabel.Caption := 'Showing fallback list.';
      End
    Else
      FModelHintLabel.Caption := Format('%d models available. Select one, then OK.',
        [FModelList.Items.Count]);

    SelectModelInList(FModelList, CurrentModel);
  Finally
    FModelList.Items.EndUpdate;
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
      FStatusValue.Caption := GrokOAuthClient.StatusText;
      Busy := GrokOAuthClient.LoginBusy;
      Pending := GrokOAuthClient.HasPendingLogin;
      SignedIn := GrokOAuthClient.IsAuthenticated;
    End
  Else
    FStatusValue.Caption := 'OAuth unavailable';
  FSignInButton.Enabled := Assigned(GrokOAuthClient) And (Not Busy);
  FSignOutButton.Enabled := Assigned(GrokOAuthClient) And SignedIn And (Not Busy);
  FPasteCodeButton.Enabled := Assigned(GrokOAuthClient) And (Not Busy);
  FManualEdit.Enabled := Assigned(GrokOAuthClient) And (Not Busy);
  FRefreshModelsButton.Enabled := Assigned(AssistantClient) And SignedIn And (Not Busy);
  If SignedIn And (Not Pending) Then
    FManualLabel.Caption := 'Already signed in — paste is only for a failed browser redirect:'
  Else If Pending Then
    FManualLabel.Caption := 'Browser open — paste code or callback URL only if it did not redirect:'
  Else
    FManualLabel.Caption := 'If browser cannot redirect, paste code or callback URL:';
End;

Procedure TAssistantSettingsForm.LoadFromConfig;
Var
  I: Integer;
Begin
  If Not Assigned(AssistantChatConfig) Then
    Exit;
  FApiBaseEdit.Text := AssistantChatConfig.ApiBase;
  FIncludeContextCheck.Checked := AssistantChatConfig.IncludeIDEContext;
  EnsureExtraControls;
  Case AssistantChatConfig.GetThinkingLevel Of
    atlLow: FThinkingCombo.ItemIndex := 0;
    atlMedium: FThinkingCombo.ItemIndex := 1;
  Else
    FThinkingCombo.ItemIndex := 2;
  End;
  Case AssistantChatConfig.GetApprovalMode Of
    aamAsk: FApprovalCombo.ItemIndex := 0;
    aamAuto: FApprovalCombo.ItemIndex := 1;
  Else
    FApprovalCombo.ItemIndex := 2;
  End;
  PopulateSkills;
  If AssistantChatConfig.ActiveSkill = '' Then
    FSkillCombo.ItemIndex := 0
  Else
    Begin
      I := FSkillCombo.Items.IndexOf(AssistantChatConfig.ActiveSkill);
      If I >= 0 Then
        FSkillCombo.ItemIndex := I
      Else
        Begin
          { Skill was removed from disk; keep name visible until user clears it. }
          FSkillCombo.Items.Add(AssistantChatConfig.ActiveSkill + ' (missing)');
          FSkillCombo.ItemIndex := FSkillCombo.Items.Count - 1;
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
  AssistantChatConfig.ApiBase := Trim(FApiBaseEdit.Text);
  If AssistantChatConfig.ApiBase = '' Then
    AssistantChatConfig.ApiBase := AssistantConfigDefaultApiBase;

  ModelName := '';
  If (FModelList.ItemIndex >= 0) And (FModelList.ItemIndex < FModelList.Items.Count) Then
    ModelName := Trim(FModelList.Items[FModelList.ItemIndex]);
  If ModelName = '' Then
    ModelName := AssistantConfigDefaultModel;
  AssistantChatConfig.Model := ModelName;

  SkillName := '';
  If (FSkillCombo.ItemIndex > 0) And (FSkillCombo.ItemIndex < FSkillCombo.Items.Count) Then
    Begin
      SkillName := FSkillCombo.Items[FSkillCombo.ItemIndex];
      If Pos(' (missing)', SkillName) > 0 Then
        SkillName := Copy(SkillName, 1, Pos(' (missing)', SkillName) - 1);
    End;
  AssistantChatConfig.ActiveSkill := SkillName;
  AssistantChatConfig.IncludeIDEContext := FIncludeContextCheck.Checked;
  EnsureExtraControls;
  Case FThinkingCombo.ItemIndex Of
    0: AssistantChatConfig.SetThinkingLevelEnum(atlLow);
    1: AssistantChatConfig.SetThinkingLevelEnum(atlMedium);
  Else
    AssistantChatConfig.SetThinkingLevelEnum(atlHigh);
  End;
  Case FApprovalCombo.ItemIndex Of
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
    AssistantClient.SetEndpoint(Trim(FApiBaseEdit.Text), AssistantClient.Model);
  PopulateModels(True);
End;

Procedure TAssistantSettingsForm.SignInButtonClick(Sender: TObject);
Begin
  If Not Assigned(GrokOAuthClient) Then
    Exit;
  FManualEdit.Clear;
  FStatusValue.Caption := 'Waiting for browser sign-in…';
  FSignInButton.Enabled := False;
  FPasteCodeButton.Enabled := False;
  FManualEdit.Enabled := False;
  FSignOutButton.Enabled := False;
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
        FManualEdit.Clear;
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
  If Trim(FManualEdit.Text) = '' Then
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
  If GrokOAuthClient.LoginWithManualCode(FManualEdit.Text) Then
    Begin
      If Assigned(AssistantChatConfig) Then
        Begin
          AssistantChatConfig.ApplyOAuthTokens(GrokOAuthClient.Tokens);
          AssistantChatConfig.Save;
        End;
      If Assigned(AssistantClient) Then
        AssistantClient.ApplyConfig(AssistantChatConfig);
      FManualEdit.Clear;
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
  If Trim(FApiBaseEdit.Text) = '' Then
    Begin
      MessageDlg('API base URL is required (e.g. https://api.x.ai/v1).', mtError, [mbOK], 0);
      CanClose := False;
      Exit;
    End;
  If (FModelList.ItemIndex < 0) Or (FModelList.ItemIndex >= FModelList.Items.Count) Or
    (Trim(FModelList.Items[FModelList.ItemIndex]) = '') Then
    Begin
      MessageDlg('Select a model from the list (e.g. grok-4.5).', mtError, [mbOK], 0);
      CanClose := False;
    End;
End;

End.
