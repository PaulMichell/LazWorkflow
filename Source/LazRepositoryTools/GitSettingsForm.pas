Unit GitSettingsForm;

{ LazRepositoryTools settings dialog (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Spin, ButtonPanel;

Type
  TGitSettingsForm = Class(TForm)
    FAutoRefreshCheck: TCheckBox;
    FIntervalLabel: TLabel;
    FIntervalSpin: TSpinEdit;
    FButtonPanel: TButtonPanel;
    FSecondsLabel: TLabel;
    Procedure AutoRefreshCheckChange(Sender: TObject);
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
    Procedure FormCreate(Sender: TObject);
  Public
    Procedure LoadFromConfig;
    Procedure SaveToConfig;
  End;

Procedure ShowGitSettingsForm;

Implementation

{$R *.lfm}

Uses
  GitConfig, WorkflowLog;

Procedure ShowGitSettingsForm;
Var
  Form: TGitSettingsForm;
Begin
  Form := TGitSettingsForm.Create(Application.MainForm);
  Try
    Form.LoadFromConfig;
    If Form.ShowModal = mrOk Then
      Begin
        Form.SaveToConfig;
        WorkflowLogger.Info('GitSettings', Format('Saved – AutoRefresh=%s Interval=%ds',
          [BoolToStr(GitManagerConfig.AutoRefresh, True), GitManagerConfig.AutoRefreshSeconds]));
      End;
  Finally
    Form.Free;
  End;
End;

Procedure TGitSettingsForm.FormCreate(Sender: TObject);
Begin
  FIntervalSpin.MinValue := GitConfigMinIntervalSec;
  FIntervalSpin.MaxValue := GitConfigMaxIntervalSec;
  FButtonPanel.OKButton.Caption := 'OK';
  FButtonPanel.CancelButton.Caption := 'Cancel';
End;

Procedure TGitSettingsForm.AutoRefreshCheckChange(Sender: TObject);
Begin
  FIntervalSpin.Enabled := FAutoRefreshCheck.Checked;
  FIntervalLabel.Enabled := FAutoRefreshCheck.Checked;
  FSecondsLabel.Enabled := FAutoRefreshCheck.Checked;
End;

Procedure TGitSettingsForm.LoadFromConfig;
Begin
  If Not Assigned(GitManagerConfig) Then
    Exit;
  FAutoRefreshCheck.Checked := GitManagerConfig.AutoRefresh;
  FIntervalSpin.Value := GitManagerConfig.AutoRefreshSeconds;
  AutoRefreshCheckChange(Nil);
End;

Procedure TGitSettingsForm.SaveToConfig;
Begin
  If Not Assigned(GitManagerConfig) Then
    Exit;
  GitManagerConfig.AutoRefresh := FAutoRefreshCheck.Checked;
  GitManagerConfig.AutoRefreshSeconds := FIntervalSpin.Value;
  GitManagerConfig.Save;
End;

Procedure TGitSettingsForm.FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
Begin
  CanClose := True;
  If ModalResult <> mrOk Then
    Exit;
  If FAutoRefreshCheck.Checked And (FIntervalSpin.Value < GitConfigMinIntervalSec) Then
    Begin
      MessageDlg(Format('Interval must be at least %d seconds.', [GitConfigMinIntervalSec]),
        mtError, [mbOK], 0);
      CanClose := False;
    End;
End;

End.
