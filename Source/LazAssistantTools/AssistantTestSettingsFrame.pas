Unit AssistantTestSettingsFrame;

{ Configured-test settings editor (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Spin, AssistantTestSettings;

Type
  TAssistantTestSettingsFrame = Class(TFrame)
  Private
    Settings: TAssistantTestSettings;
    ProjectLabel: TLabel;
    Procedure Browse(Sender: TObject);
    Procedure Store;
  Public
    EnabledCheck: TCheckBox;
    ExecutableEdit: TEdit;
    ArgumentMemo: TMemo;
    TimeoutEdit, MinimumEdit: TSpinEdit;
    ReportCombo: TComboBox;
    Constructor Create(AOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure Load(Const ConfigRoot, ProjectFile: String);
    Function Validate(Out ErrorText: String): Boolean;
    Procedure Save;
  End;

Implementation

{$R *.lfm}

Uses
  Dialogs;

Constructor TAssistantTestSettingsFrame.Create(AOwner: TComponent);
Var
  LabelControl: TLabel;
  Button: TButton;
Begin
  Inherited Create(AOwner);
  Width := 850;
  Height := 580;
  ProjectLabel := TLabel.Create(Self);
  ProjectLabel.Parent := Self;
  ProjectLabel.SetBounds(20, 16, 800, 48);
  ProjectLabel.AutoSize := False;
  ProjectLabel.WordWrap := True;
  ProjectLabel.Anchors := [akLeft, akTop, akRight];
  EnabledCheck := TCheckBox.Create(Self);
  EnabledCheck.Parent := Self;
  EnabledCheck.SetBounds(20, 76, 780, 26);
  EnabledCheck.Caption := 'Enable the configured test command for this project';
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := Self;
  LabelControl.SetBounds(20, 120, 750, 20);
  LabelControl.Caption := 'Test executable (absolute path or relative to the project directory)';
  ExecutableEdit := TEdit.Create(Self);
  ExecutableEdit.Parent := Self;
  ExecutableEdit.SetBounds(20, 145, 700, 30);
  ExecutableEdit.Anchors := [akLeft, akTop, akRight];
  Button := TButton.Create(Self);
  Button.Parent := Self;
  Button.SetBounds(730, 145, 100, 30);
  Button.Anchors := [akTop, akRight];
  Button.Caption := 'Browse…';
  Button.OnClick := @Browse;
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := Self;
  LabelControl.SetBounds(20, 195, 800, 20);
  LabelControl.Caption := 'Arguments — one nonempty argument per line, without shell quoting';
  ArgumentMemo := TMemo.Create(Self);
  ArgumentMemo.Parent := Self;
  ArgumentMemo.SetBounds(20, 222, 810, 145);
  ArgumentMemo.Anchors := [akLeft, akTop, akRight];
  ArgumentMemo.ScrollBars := ssBoth;
  ArgumentMemo.WordWrap := False;
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := Self;
  LabelControl.SetBounds(20, 390, 160, 20);
  LabelControl.Caption := 'Timeout (seconds)';
  TimeoutEdit := TSpinEdit.Create(Self);
  TimeoutEdit.Parent := Self;
  TimeoutEdit.SetBounds(190, 386, 130, 30);
  TimeoutEdit.MinValue := 1;
  TimeoutEdit.MaxValue := 3600;
  TimeoutEdit.Value := 600;
  ReportCombo := TComboBox.Create(Self);
  ReportCombo.Parent := Self;
  ReportCombo.SetBounds(20, 444, 350, 30);
  ReportCombo.Style := csDropDownList;
  ReportCombo.Items.Add('Process exit only (no test count)');
  ReportCombo.Items.Add('FPCUnit XML on stdout');
  ReportCombo.ItemIndex := 0;
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := Self;
  LabelControl.SetBounds(390, 449, 220, 20);
  LabelControl.Caption := 'Minimum executed tests';
  MinimumEdit := TSpinEdit.Create(Self);
  MinimumEdit.Parent := Self;
  MinimumEdit.SetBounds(620, 444, 130, 30);
  MinimumEdit.MinValue := 1;
  MinimumEdit.MaxValue := 1000000;
  MinimumEdit.Value := 1;
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := Self;
  LabelControl.SetBounds(20, 494, 810, 80);
  LabelControl.AutoSize := False;
  LabelControl.WordWrap := True;
  LabelControl.Anchors := [akLeft, akTop, akRight];
  LabelControl.Caption := 'Tests run after a current successful build. FPCUnit XML must be the complete stdout report; ignored tests do not count towards the minimum. Exit-only mode records process success without verifying test counts. The assistant uses this exact command. Settings are stored in your IDE profile.';
End;

Destructor TAssistantTestSettingsFrame.Destroy;
Begin
  Settings.Free;
  Inherited Destroy;
End;

Procedure TAssistantTestSettingsFrame.Load(Const ConfigRoot, ProjectFile: String);
Begin
  FreeAndNil(Settings);
  Settings := TAssistantTestSettings.Create(ConfigRoot, ProjectFile);
  Settings.Load;
  Enabled := ProjectFile <> '';
  ProjectLabel.Caption := 'Target: ' + ProjectFile;
  If ProjectFile = '' Then ProjectLabel.Caption := 'Select a saved project or package to configure its test command.';
  EnabledCheck.Checked := Settings.Enabled;
  ExecutableEdit.Text := Settings.Executable;
  If Settings.ReportFormat = 'fpcunit-xml' Then ReportCombo.ItemIndex := 1
  Else ReportCombo.ItemIndex := 0;
  MinimumEdit.Value := Settings.MinimumTests;
  ArgumentMemo.Lines.Assign(Settings.Arguments);
  TimeoutEdit.Value := Settings.TimeoutSeconds;
End;

Procedure TAssistantTestSettingsFrame.Store;
Begin
  If Not Assigned(Settings) Then Exit;
  Settings.Enabled := EnabledCheck.Checked;
  Settings.Executable := Trim(ExecutableEdit.Text);
  If ReportCombo.ItemIndex = 1 Then Settings.ReportFormat := 'fpcunit-xml'
  Else Settings.ReportFormat := 'exit-code';
  Settings.MinimumTests := MinimumEdit.Value;
  Settings.Arguments.Assign(ArgumentMemo.Lines);
  Settings.TimeoutSeconds := TimeoutEdit.Value;
End;

Function TAssistantTestSettingsFrame.Validate(Out ErrorText: String): Boolean;
Begin
  ErrorText := '';
  If Not Enabled Then Exit(True);
  Store;
  Result := Settings.Validate(ErrorText);
End;

Procedure TAssistantTestSettingsFrame.Save;
Begin
  If Not Enabled Then Exit;
  Store;
  Settings.Save;
End;

Procedure TAssistantTestSettingsFrame.Browse(Sender: TObject);
Var
  Dialog: TOpenDialog;
Begin
  Dialog := TOpenDialog.Create(Self);
  Try
    Dialog.Title := 'Select the project test executable';
    Dialog.Options := [ofFileMustExist];
    If Dialog.Execute Then ExecutableEdit.Text := Dialog.FileName;
  Finally
    Dialog.Free;
  End;
End;
End.
