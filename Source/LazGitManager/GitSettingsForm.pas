Unit GitSettingsForm;

{ LazGitManager settings dialog (c) 2026 Michell Computing. }

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
  Private
    FAutoRefreshCheck: TCheckBox;
    FIntervalLabel: TLabel;
    FIntervalSpin: TSpinEdit;
    FButtonPanel: TButtonPanel;
    FSecondsLabel: TLabel;
    Procedure CreateUI;
    Procedure AutoRefreshCheckChange(Sender: TObject);
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
  Public
    Constructor Create(TheOwner: TComponent); Override;
    Procedure LoadFromConfig;
    Procedure SaveToConfig;
  End;

Procedure ShowGitSettingsForm;

Implementation

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

Constructor TGitSettingsForm.Create(TheOwner: TComponent);
Begin
  Inherited CreateNew(TheOwner);
  CreateUI;
End;

Procedure TGitSettingsForm.CreateUI;
Begin
  Caption := 'Repository Settings';
  Position := poScreenCenter;
  BorderStyle := bsDialog;
  Width := 420;
  Height := 180;
  OnCloseQuery := @FormCloseQuery;

  FAutoRefreshCheck := TCheckBox.Create(Self);
  With FAutoRefreshCheck Do
    Begin
      Parent := Self;
      Left := 16;
      Top := 20;
      Width := 380;
      Caption := 'Automatically refresh repository state';
      OnChange := @AutoRefreshCheckChange;
    End;

  FIntervalLabel := TLabel.Create(Self);
  With FIntervalLabel Do
    Begin
      Parent := Self;
      Left := 36;
      Top := 56;
      Caption := 'Refresh interval:';
    End;

  FIntervalSpin := TSpinEdit.Create(Self);
  With FIntervalSpin Do
    Begin
      Parent := Self;
      Left := 160;
      Top := 52;
      Width := 80;
      MinValue := GitConfigMinIntervalSec;
      MaxValue := GitConfigMaxIntervalSec;
      Value := GitConfigDefaultIntervalSec;
    End;

  FSecondsLabel := TLabel.Create(Self);
  With FSecondsLabel Do
    Begin
      Parent := Self;
      Left := 250;
      Top := 56;
      Caption := 'seconds';
    End;

  FButtonPanel := TButtonPanel.Create(Self);
  With FButtonPanel Do
    Begin
      Parent := Self;
      Align := alBottom;
      ShowButtons := [pbOK, pbCancel];
      OKButton.Caption := 'OK';
      CancelButton.Caption := 'Cancel';
    End;
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
