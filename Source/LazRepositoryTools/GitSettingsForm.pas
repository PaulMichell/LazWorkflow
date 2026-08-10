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
    ScrollBox: TScrollBox;
    IdentityGroup: TGroupBox;
    RepoPathLabel: TLabel;
    UserNameLabel: TLabel;
    UserNameEdit: TEdit;
    UserEmailLabel: TLabel;
    UserEmailEdit: TEdit;
    DescriptionGroup: TGroupBox;
    DescriptionMemo: TMemo;
    AppGroup: TGroupBox;
    AutoRefreshCheck: TCheckBox;
    IntervalLabel: TLabel;
    IntervalSpin: TSpinEdit;
    SecondsLabel: TLabel;
    GraphFontLabel: TLabel;
    GraphFontNameEdit: TEdit;
    GraphFontChooseButton: TButton;
    GraphFontSizeLabel: TLabel;
    GraphFontSizeSpin: TSpinEdit;
    GraphFontPointsLabel: TLabel;
    ButtonPanel: TButtonPanel;
    Procedure AutoRefreshCheckChange(Sender: TObject);
    Procedure GraphFontChooseClick(Sender: TObject);
    Procedure FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
    Procedure FormCreate(Sender: TObject);
  Private
    FRepoPath: String;
    FHasRepo: Boolean;
    Procedure SetIdentityControlsEnabled(ControlsEnabled: Boolean);
    Procedure SyncGraphFontNameDisplay;
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
            'Saved – AutoRefresh=%s Interval=%ds GraphFont=%s %dpt Repo=%s',
            [BoolToStr(GitManagerConfig.AutoRefresh, True),
             GitManagerConfig.AutoRefreshSeconds,
             GitManagerConfig.GraphFontName,
             GitManagerConfig.GraphFontSize,
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
  IntervalSpin.MinValue := GitConfigMinIntervalSec;
  IntervalSpin.MaxValue := GitConfigMaxIntervalSec;
  GraphFontSizeSpin.MinValue := GitConfigMinGraphFontSize;
  GraphFontSizeSpin.MaxValue := GitConfigMaxGraphFontSize;
  ButtonPanel.OKButton.Caption := 'OK';
  ButtonPanel.CancelButton.Caption := 'Cancel';
  FHasRepo := False;
  FRepoPath := '';
End;

Procedure TGitSettingsForm.SetIdentityControlsEnabled(ControlsEnabled: Boolean);
Begin
  UserNameEdit.Enabled := ControlsEnabled;
  UserEmailEdit.Enabled := ControlsEnabled;
  DescriptionMemo.Enabled := ControlsEnabled;
  UserNameLabel.Enabled := ControlsEnabled;
  UserEmailLabel.Enabled := ControlsEnabled;
End;

Procedure TGitSettingsForm.SyncGraphFontNameDisplay;
Begin
  If Trim(GraphFontNameEdit.Text) = '' Then
    GraphFontNameEdit.Text := '(use window font)';
End;

Procedure TGitSettingsForm.AutoRefreshCheckChange(Sender: TObject);
Begin
  IntervalSpin.Enabled := AutoRefreshCheck.Checked;
  IntervalLabel.Enabled := AutoRefreshCheck.Checked;
  SecondsLabel.Enabled := AutoRefreshCheck.Checked;
End;

Procedure TGitSettingsForm.GraphFontChooseClick(Sender: TObject);
Var
  FontDialog: TFontDialog;
  NameText: String;
Begin
  FontDialog := TFontDialog.Create(Nil);
  Try
    NameText := Trim(GraphFontNameEdit.Text);
    If (NameText = '') Or (NameText = '(use window font)') Then
      FontDialog.Font.Name := Font.Name
    Else
      FontDialog.Font.Name := NameText;
    FontDialog.Font.Size := GraphFontSizeSpin.Value;
    FontDialog.Options := FontDialog.Options + [fdNoStyleSel, fdForceFontExist];
    If FontDialog.Execute Then
      Begin
        GraphFontNameEdit.Text := FontDialog.Font.Name;
        GraphFontSizeSpin.Value := FontDialog.Font.Size;
      End;
  Finally
    FontDialog.Free;
  End;
End;

Procedure TGitSettingsForm.LoadFromConfig;
Var
  LocalName, LocalEmail, Description: String;
Begin
  If Assigned(GitManagerConfig) Then
    Begin
      AutoRefreshCheck.Checked := GitManagerConfig.AutoRefresh;
      IntervalSpin.Value := GitManagerConfig.AutoRefreshSeconds;
      GraphFontNameEdit.Text := GitManagerConfig.GraphFontName;
      GraphFontSizeSpin.Value := GitManagerConfig.GraphFontSize;
    End
  Else
    Begin
      GraphFontNameEdit.Text := '';
      GraphFontSizeSpin.Value := GitConfigDefaultGraphFontSize;
    End;
  SyncGraphFontNameDisplay;
  AutoRefreshCheckChange(Nil);

  FRepoPath := ResolveSettingsRepoPath;
  FHasRepo := FRepoPath <> '';
  If Not FHasRepo Then
    Begin
      RepoPathLabel.Caption := 'No Git repository for the current project — identity fields are disabled.';
      UserNameEdit.Text := '';
      UserEmailEdit.Text := '';
      DescriptionMemo.Text := '';
      SetIdentityControlsEnabled(False);
      Exit;
    End;

  RepoPathLabel.Caption := 'Repository: ' + FRepoPath;
  SetIdentityControlsEnabled(True);
  If Not Assigned(GitClient) Then
    Exit;

  GitClient.RepoPath := FRepoPath;
  LocalName := '';
  LocalEmail := '';
  Description := '';
  { Prefer repository-local identity; fall back to effective git config (global [user]). }
  GitClient.GetConfigValue('user.name', True, LocalName);
  If Trim(LocalName) = '' Then
    GitClient.GetConfigValue('user.name', False, LocalName);
  GitClient.GetConfigValue('user.email', True, LocalEmail);
  If Trim(LocalEmail) = '' Then
    GitClient.GetConfigValue('user.email', False, LocalEmail);
  GitClient.GetDescription(Description);

  UserNameEdit.Text := LocalName;
  UserEmailEdit.Text := LocalEmail;
  DescriptionMemo.Text := Description;
End;

Function TGitSettingsForm.SaveToConfig: Boolean;
Var
  Ok: Boolean;
  FontName: String;
Begin
  Result := True;
  If Assigned(GitManagerConfig) Then
    Begin
      GitManagerConfig.AutoRefresh := AutoRefreshCheck.Checked;
      GitManagerConfig.AutoRefreshSeconds := IntervalSpin.Value;
      FontName := Trim(GraphFontNameEdit.Text);
      If FontName = '(use window font)' Then
        FontName := '';
      GitManagerConfig.GraphFontName := FontName;
      GitManagerConfig.GraphFontSize := GraphFontSizeSpin.Value;
      GitManagerConfig.Save;
    End;

  If Not FHasRepo Or (FRepoPath = '') Or Not Assigned(GitClient) Then
    Exit;

  GitClient.RepoPath := FRepoPath;
  Ok := True;
  If Not GitClient.SetConfigValue('user.name', Trim(UserNameEdit.Text), True) Then
    Ok := False;
  If Not GitClient.SetConfigValue('user.email', Trim(UserEmailEdit.Text), True) Then
    Ok := False;
  If Not GitClient.SetDescription(DescriptionMemo.Text) Then
    Ok := False;
  Result := Ok;
End;

Procedure TGitSettingsForm.FormCloseQuery(Sender: TObject; Var CanClose: Boolean);
Begin
  CanClose := True;
  If ModalResult <> mrOk Then
    Exit;
  If AutoRefreshCheck.Checked And (IntervalSpin.Value < GitConfigMinIntervalSec) Then
    Begin
      MessageDlg(Format('Interval must be at least %d seconds.', [GitConfigMinIntervalSec]),
        mtError, [mbOK], 0);
      CanClose := False;
    End;
End;

End.
