Unit AssistantTestSettingsFrame;
{$mode objfpc}{$H+}
Interface
Uses Classes, SysUtils, Forms, Controls, StdCtrls, Spin, AssistantTestSettings;
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
    TimeoutEdit: TSpinEdit;
    Constructor Create(AOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure Load(Const ConfigRoot, ProjectFile: String);
    Function Validate(Out ErrorText: String): Boolean;
    Procedure Save;
  End;
Implementation
{$R *.lfm}
Uses Dialogs;
Constructor TAssistantTestSettingsFrame.Create(AOwner: TComponent);
Var LabelControl: TLabel; Button: TButton;
Begin
  Inherited Create(AOwner); Width := 850; Height := 530;
  ProjectLabel := TLabel.Create(Self); ProjectLabel.Parent := Self; ProjectLabel.SetBounds(20, 16, 800, 48);
  ProjectLabel.AutoSize := False; ProjectLabel.WordWrap := True; ProjectLabel.Anchors := [akLeft, akTop, akRight];
  EnabledCheck := TCheckBox.Create(Self); EnabledCheck.Parent := Self; EnabledCheck.SetBounds(20, 76, 780, 26);
  EnabledCheck.Caption := 'Enable the configured test command for this project';
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Self; LabelControl.SetBounds(20, 120, 750, 20); LabelControl.Caption := 'Test executable (absolute path or relative to the project directory)';
  ExecutableEdit := TEdit.Create(Self); ExecutableEdit.Parent := Self; ExecutableEdit.SetBounds(20, 145, 700, 30); ExecutableEdit.Anchors := [akLeft, akTop, akRight];
  Button := TButton.Create(Self); Button.Parent := Self; Button.SetBounds(730, 145, 100, 30); Button.Anchors := [akTop, akRight]; Button.Caption := 'Browse…'; Button.OnClick := @Browse;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Self; LabelControl.SetBounds(20, 195, 800, 20); LabelControl.Caption := 'Arguments — one nonempty argument per line, without shell quoting';
  ArgumentMemo := TMemo.Create(Self); ArgumentMemo.Parent := Self; ArgumentMemo.SetBounds(20, 222, 810, 145);
  ArgumentMemo.Anchors := [akLeft, akTop, akRight]; ArgumentMemo.ScrollBars := ssBoth; ArgumentMemo.WordWrap := False;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Self; LabelControl.SetBounds(20, 390, 160, 20); LabelControl.Caption := 'Timeout (seconds)';
  TimeoutEdit := TSpinEdit.Create(Self); TimeoutEdit.Parent := Self; TimeoutEdit.SetBounds(190, 386, 130, 30);
  TimeoutEdit.MinValue := 1; TimeoutEdit.MaxValue := 3600; TimeoutEdit.Value := 600;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Self; LabelControl.SetBounds(20, 442, 810, 80); LabelControl.AutoSize := False;
  LabelControl.WordWrap := True; LabelControl.Anchors := [akLeft, akTop, akRight];
  LabelControl.Caption := 'Tests run in the project directory after a current successful build. Use a runner that exits nonzero on failure. The assistant uses this exact command and cannot supply another executable or arguments. Settings are stored in your IDE profile; Cancel discards edits.';
End;
Destructor TAssistantTestSettingsFrame.Destroy;
Begin Settings.Free; Inherited Destroy; End;
Procedure TAssistantTestSettingsFrame.Load(Const ConfigRoot, ProjectFile: String);
Begin
  FreeAndNil(Settings); Settings := TAssistantTestSettings.Create(ConfigRoot, ProjectFile); Settings.Load;
  Enabled := ProjectFile <> ''; ProjectLabel.Caption := 'Project: ' + ProjectFile;
  If ProjectFile = '' Then ProjectLabel.Caption := 'Open a saved project to configure its test command.';
  EnabledCheck.Checked := Settings.Enabled; ExecutableEdit.Text := Settings.Executable;
  ArgumentMemo.Lines.Assign(Settings.Arguments); TimeoutEdit.Value := Settings.TimeoutSeconds;
End;
Procedure TAssistantTestSettingsFrame.Store;
Begin
  If Not Assigned(Settings) Then Exit;
  Settings.Enabled := EnabledCheck.Checked; Settings.Executable := Trim(ExecutableEdit.Text);
  Settings.Arguments.Assign(ArgumentMemo.Lines); Settings.TimeoutSeconds := TimeoutEdit.Value;
End;
Function TAssistantTestSettingsFrame.Validate(Out ErrorText: String): Boolean;
Begin ErrorText := ''; If Not Enabled Then Exit(True); Store; Result := Settings.Validate(ErrorText); End;
Procedure TAssistantTestSettingsFrame.Save;
Begin If Not Enabled Then Exit; Store; Settings.Save; End;
Procedure TAssistantTestSettingsFrame.Browse(Sender: TObject);
Var Dialog: TOpenDialog;
Begin
  Dialog := TOpenDialog.Create(Self);
  Try Dialog.Title := 'Select the project test executable'; Dialog.Options := [ofFileMustExist];
    If Dialog.Execute Then ExecutableEdit.Text := Dialog.FileName;
  Finally Dialog.Free; End;
End;
End.
