Unit GitSettingsForm;

{ LazRepositoryTools settings: window options, local git config, description (c) 2026 Michell Computing. }

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
    FScrollBox: TScrollBox;
    FIdentityGroup: TGroupBox;
    FRepoPathLabel: TLabel;
    FUserNameLabel: TLabel;
    FUserNameEdit: TEdit;
    FUserEmailLabel: TLabel;
    FUserEmailEdit: TEdit;
    FDescriptionGroup: TGroupBox;
    FDescriptionMemo: TMemo;
    FAppGroup: TGroupBox;
    FAutoRefreshCheck: TCheckBox;
    FIntervalLabel: TLabel;
    FIntervalSpin: TSpinEdit;
    FSecondsLabel: TLabel;
    FButtonPanel: TButtonPanel;
    Procedure AutoRefreshCheckChange(Sender: TObject);
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
    Procedure FormCreate(Sender: TObject);
  Private
    FRepoPath: String;
    FHasRepo: Boolean;
    Procedure SetIdentityControlsEnabled(ControlsEnabled: Boolean);
  Public
    Procedure LoadFromConfig;
    Function SaveToConfig: Boolean;
  End;

Procedure ShowGitSettingsForm;

Implementation

{$R *.lfm}

Uses
  GitConfig, GitService, WorkflowLog, LazIDEIntf, ProjectIntf;

Function ResolveSettingsRepoPath: String;
Var
  StartPath: String;
  Proj: TLazProject;
Begin
  Result := '';
  If Assigned(GitClient) And (GitClient.RepoPath <> '') And
    GitClient.IsRepository(GitClient.RepoPath) Then
    Begin
      Result := GitClient.RepoPath;
      Exit;
    End;
  If Not Assigned(LazarusIDE) Or Not Assigned(LazarusIDE.ActiveProject) Then
    Exit;
  Proj := LazarusIDE.ActiveProject;
  StartPath := '';
  If Assigned(Proj.MainFile) And (Proj.MainFile.Filename <> '') Then
    StartPath := ExtractFilePath(ExpandFileName(Proj.MainFile.Filename));
  If StartPath = '' Then
    StartPath := ExtractFilePath(ExpandFileName(Proj.ProjectInfoFile));
  If (StartPath <> '') And Assigned(GitClient) Then
    Result := GitClient.DetectRepository(StartPath);
End;

Procedure ShowGitSettingsForm;
Var
  Form: TGitSettingsForm;
Begin
  Form := TGitSettingsForm.Create(Application.MainForm);
  Try
    Form.LoadFromConfig;
    If Form.ShowModal = mrOk Then
      Begin
        If Form.SaveToConfig Then
          WorkflowLogger.Info('GitSettings', Format(
            'Saved – AutoRefresh=%s Interval=%ds Repo=%s',
            [BoolToStr(GitManagerConfig.AutoRefresh, True),
             GitManagerConfig.AutoRefreshSeconds,
             Form.FRepoPath]))
        Else
          MessageDlg('Some repository settings could not be saved.' + LineEnding +
            GitClient.LastError, mtWarning, [mbOK], 0);
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
  FHasRepo := False;
  FRepoPath := '';
End;

Procedure TGitSettingsForm.SetIdentityControlsEnabled(ControlsEnabled: Boolean);
Begin
  FUserNameEdit.Enabled := ControlsEnabled;
  FUserEmailEdit.Enabled := ControlsEnabled;
  FDescriptionMemo.Enabled := ControlsEnabled;
  FUserNameLabel.Enabled := ControlsEnabled;
  FUserEmailLabel.Enabled := ControlsEnabled;
End;

Procedure TGitSettingsForm.AutoRefreshCheckChange(Sender: TObject);
Begin
  FIntervalSpin.Enabled := FAutoRefreshCheck.Checked;
  FIntervalLabel.Enabled := FAutoRefreshCheck.Checked;
  FSecondsLabel.Enabled := FAutoRefreshCheck.Checked;
End;

Procedure TGitSettingsForm.LoadFromConfig;
Var
  LocalName, LocalEmail, Description: String;
Begin
  If Assigned(GitManagerConfig) Then
    Begin
      FAutoRefreshCheck.Checked := GitManagerConfig.AutoRefresh;
      FIntervalSpin.Value := GitManagerConfig.AutoRefreshSeconds;
    End;
  AutoRefreshCheckChange(Nil);

  FRepoPath := ResolveSettingsRepoPath;
  FHasRepo := FRepoPath <> '';
  If Not FHasRepo Then
    Begin
      FRepoPathLabel.Caption := 'No Git repository for the current project — identity fields are disabled.';
      FUserNameEdit.Text := '';
      FUserEmailEdit.Text := '';
      FDescriptionMemo.Text := '';
      SetIdentityControlsEnabled(False);
      Exit;
    End;

  FRepoPathLabel.Caption := 'Repository: ' + FRepoPath;
  SetIdentityControlsEnabled(True);
  If Not Assigned(GitClient) Then
    Exit;

  GitClient.RepoPath := FRepoPath;
  LocalName := '';
  LocalEmail := '';
  Description := '';
  GitClient.GetConfigValue('user.name', True, LocalName);
  GitClient.GetConfigValue('user.email', True, LocalEmail);
  GitClient.GetDescription(Description);

  FUserNameEdit.Text := LocalName;
  FUserEmailEdit.Text := LocalEmail;
  FDescriptionMemo.Text := Description;
End;

Function TGitSettingsForm.SaveToConfig: Boolean;
Var
  Ok: Boolean;
Begin
  Result := True;
  If Assigned(GitManagerConfig) Then
    Begin
      GitManagerConfig.AutoRefresh := FAutoRefreshCheck.Checked;
      GitManagerConfig.AutoRefreshSeconds := FIntervalSpin.Value;
      GitManagerConfig.Save;
    End;

  If Not FHasRepo Or (FRepoPath = '') Or Not Assigned(GitClient) Then
    Exit;

  GitClient.RepoPath := FRepoPath;
  Ok := True;
  If Not GitClient.SetConfigValue('user.name', Trim(FUserNameEdit.Text), True) Then
    Ok := False;
  If Not GitClient.SetConfigValue('user.email', Trim(FUserEmailEdit.Text), True) Then
    Ok := False;
  If Not GitClient.SetDescription(FDescriptionMemo.Text) Then
    Ok := False;
  Result := Ok;
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
