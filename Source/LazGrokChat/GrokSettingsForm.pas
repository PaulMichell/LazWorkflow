Unit GrokSettingsForm;

{ LazGrokChat OAuth sign-in and model settings dialog (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ButtonPanel;

Type
  TGrokSettingsForm = Class(TForm)
    FStatusLabel: TLabel;
    FStatusValue: TLabel;
    FModelLabel: TLabel;
    FModelEdit: TEdit;
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
  Public
    Procedure LoadFromConfig;
    Procedure SaveToConfig;
    Procedure RefreshAuthStatus;
  End;

Procedure ShowGrokSettingsForm;

Implementation

{$R *.lfm}

Uses
  GrokConfig, GrokService, GrokOAuth, WorkflowLog, LCLIntf;

Procedure ShowGrokSettingsForm;
Var
  Form: TGrokSettingsForm;
Begin
  Form := TGrokSettingsForm.Create(Application.MainForm);
  Try
    Form.LoadFromConfig;
    If Form.ShowModal = mrOk Then
      Begin
        Form.SaveToConfig;
        If Assigned(GrokClient) And Assigned(GrokChatConfig) Then
          GrokClient.ApplyConfig(GrokChatConfig);
        WorkflowLogger.Info('GrokSettings', 'Saved – model=' + GrokChatConfig.Model);
      End;
  Finally
    Form.Free;
  End;
End;

Procedure TGrokSettingsForm.FormCreate(Sender: TObject);
Begin
  FButtonPanel.OKButton.Caption := 'OK';
  FButtonPanel.CancelButton.Caption := 'Cancel';
  RefreshAuthStatus;
End;

Procedure TGrokSettingsForm.RefreshAuthStatus;
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
  { Paste is only needed when a login is pending and the browser did not redirect. }
  FPasteCodeButton.Enabled := Assigned(GrokOAuthClient) And (Not Busy);
  FManualEdit.Enabled := Assigned(GrokOAuthClient) And (Not Busy);
  If SignedIn And (Not Pending) Then
    FManualLabel.Caption := 'Already signed in — paste is only for a failed browser redirect:'
  Else If Pending Then
    FManualLabel.Caption := 'Browser open — paste code or callback URL only if it did not redirect:'
  Else
    FManualLabel.Caption := 'If browser cannot redirect, paste code or callback URL:';
End;

Procedure TGrokSettingsForm.LoadFromConfig;
Begin
  If Not Assigned(GrokChatConfig) Then
    Exit;
  FApiBaseEdit.Text := GrokChatConfig.ApiBase;
  FModelEdit.Text := GrokChatConfig.Model;
  If Assigned(GrokOAuthClient) And GrokChatConfig.IsSignedIn Then
    GrokOAuthClient.SetTokens(GrokChatConfig.ToOAuthTokens);
  RefreshAuthStatus;
End;

Procedure TGrokSettingsForm.SaveToConfig;
Begin
  If Not Assigned(GrokChatConfig) Then
    Exit;
  GrokChatConfig.ApiBase := Trim(FApiBaseEdit.Text);
  GrokChatConfig.Model := Trim(FModelEdit.Text);
  If GrokChatConfig.ApiBase = '' Then
    GrokChatConfig.ApiBase := GrokConfigDefaultApiBase;
  If GrokChatConfig.Model = '' Then
    GrokChatConfig.Model := GrokConfigDefaultModel;
  If Assigned(GrokOAuthClient) Then
    GrokChatConfig.ApplyOAuthTokens(GrokOAuthClient.Tokens);
  GrokChatConfig.Save;
End;

Procedure TGrokSettingsForm.SignInButtonClick(Sender: TObject);
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
        If Assigned(GrokChatConfig) Then
          Begin
            GrokChatConfig.ApplyOAuthTokens(GrokOAuthClient.Tokens);
            GrokChatConfig.Save;
          End;
        If Assigned(GrokClient) Then
          GrokClient.ApplyConfig(GrokChatConfig);
        FManualEdit.Clear;
        MessageDlg('Signed in with SuperGrok / X Premium.' + LineEnding + LineEnding +
          'You do not need to paste the browser code — it is single-use and was already consumed.',
          mtInformation, [mbOK], 0);
      End
    Else
      Begin
        { Callback failed but pending PKCE may still be valid for a one-shot paste. }
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

Procedure TGrokSettingsForm.SignOutButtonClick(Sender: TObject);
Begin
  If Not Assigned(GrokOAuthClient) Then
    Exit;
  If MessageDlg('Sign out of xAI Grok on this machine?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes Then
    Exit;
  GrokOAuthClient.ClearTokens;
  If Assigned(GrokChatConfig) Then
    Begin
      GrokChatConfig.ClearOAuthTokens;
      GrokChatConfig.Save;
    End;
  RefreshAuthStatus;
  WorkflowLogger.Info('GrokSettings', 'Signed out');
End;

Procedure TGrokSettingsForm.PasteCodeButtonClick(Sender: TObject);
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
      { Start a pending login and open the browser if none is active. }
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
      If Assigned(GrokChatConfig) Then
        Begin
          GrokChatConfig.ApplyOAuthTokens(GrokOAuthClient.Tokens);
          GrokChatConfig.Save;
        End;
      If Assigned(GrokClient) Then
        GrokClient.ApplyConfig(GrokChatConfig);
      FManualEdit.Clear;
      MessageDlg('Signed in with SuperGrok / X Premium.', mtInformation, [mbOK], 0);
    End
  Else
    MessageDlg(GrokOAuthClient.LastError, mtWarning, [mbOK], 0);
  RefreshAuthStatus;
End;

Procedure TGrokSettingsForm.FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
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
  If Trim(FModelEdit.Text) = '' Then
    Begin
      MessageDlg('Model name is required (e.g. grok-4).', mtError, [mbOK], 0);
      CanClose := False;
    End;
End;

End.
