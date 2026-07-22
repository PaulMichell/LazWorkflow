Unit GrokSettingsForm;

{ LazGrokChat credentials and model settings dialog (c) 2026 Michell Computing. }

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
    FApiBaseLabel: TLabel;
    FApiBaseEdit: TEdit;
    FApiKeyLabel: TLabel;
    FApiKeyEdit: TEdit;
    FModelLabel: TLabel;
    FModelEdit: TEdit;
    FHintLabel: TLabel;
    FButtonPanel: TButtonPanel;
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
    Procedure FormCreate(Sender: TObject);
  Public
    Procedure LoadFromConfig;
    Procedure SaveToConfig;
  End;

Procedure ShowGrokSettingsForm;

Implementation

{$R *.lfm}

Uses
  GrokConfig, GrokService, WorkflowLog;

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
  FApiKeyEdit.EchoMode := emPassword;
End;

Procedure TGrokSettingsForm.LoadFromConfig;
Begin
  If Not Assigned(GrokChatConfig) Then
    Exit;
  FApiBaseEdit.Text := GrokChatConfig.ApiBase;
  FApiKeyEdit.Text := GrokChatConfig.ApiKey;
  FModelEdit.Text := GrokChatConfig.Model;
End;

Procedure TGrokSettingsForm.SaveToConfig;
Begin
  If Not Assigned(GrokChatConfig) Then
    Exit;
  GrokChatConfig.ApiBase := Trim(FApiBaseEdit.Text);
  GrokChatConfig.ApiKey := Trim(FApiKeyEdit.Text);
  GrokChatConfig.Model := Trim(FModelEdit.Text);
  If GrokChatConfig.ApiBase = '' Then
    GrokChatConfig.ApiBase := GrokConfigDefaultApiBase;
  If GrokChatConfig.Model = '' Then
    GrokChatConfig.Model := GrokConfigDefaultModel;
  GrokChatConfig.Save;
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
