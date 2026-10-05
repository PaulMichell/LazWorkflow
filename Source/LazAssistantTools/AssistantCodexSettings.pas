Unit AssistantCodexSettings;

{ Codex connection settings frame (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, AssistantCodexAccount;

Type
  TCodexConnectionFrame = Class(TFrame)
  Private

    Status: TLabel;
    SignIn, CheckButton, BrowseButton, DetectButton, DeleteProfileButton: TButton;
    Timer: TTimer;
    Job: TAssistantCodexAccount;
    OpenedUrl, ModelsJson: String;
    Procedure BrowseRuntime(Sender: TObject);
    Procedure DetectRuntime(Sender: TObject);
    Procedure ModelChanged(Sender: TObject);
    Procedure StartCheck(Sender: TObject);
    Procedure Tick(Sender: TObject);
    Procedure DeleteProfile(Sender: TObject);
  Public
    RuntimeEdit: TEdit;
    ModelCombo, EffortCombo, ApprovalCombo: TComboBox;
    Profile: String;
    Procedure LoadConnection(Const ProfileDir, Runtime, Model: String; Const Effort: String = ''; Const Approval: String = 'ask');
    Procedure LoadModels(Const Value: String);
    Function ReasoningEffort: String;
    Function ApprovalMode: String;
    Function Busy: Boolean;
    Constructor Create(TheOwner: TComponent); Override;
    Destructor Destroy; Override;
  End;

  { Move a cancelled worker's join/destruction off the IDE thread. No IDE callbacks. }
Procedure ReapCodexWorker(Worker: TThread);

Implementation

{$R *.lfm}

Uses
  Dialogs, LCLIntf, Process, FileUtil, fpjson, jsonparser, AssistantCodexHandshake, AssistantCodexProfile, LazFileUtils;

Type
  TWorkerReaper = Class(TThread)
    Worker: TThread;
    Procedure Execute; Override;
  End;

Procedure TWorkerReaper.Execute;
Begin
  Worker.WaitFor;
  Worker.Free;
End;

Procedure ReapCodexWorker(Worker: TThread);
Var
  Reaper: TWorkerReaper;
Begin
  If Not Assigned(Worker) Then Exit;
  Reaper := TWorkerReaper.Create(True);
  Reaper.FreeOnTerminate := True;
  Reaper.Worker := Worker;
  Reaper.Start;
End;

Constructor TCodexConnectionFrame.Create(TheOwner: TComponent);
Var
  LabelControl: TLabel;
Begin
  Inherited Create(TheOwner);
  SetBounds(0, 0, 660, 310);
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := Self;
  LabelControl.SetBounds(16, 16, 620, 20);
  LabelControl.Caption := 'Codex executable (any release build; schema checked on sign-in)';
  RuntimeEdit := TEdit.Create(Self);
  RuntimeEdit.Parent := Self;
  RuntimeEdit.SetBounds(16, 42, 405, 28);
  BrowseButton := TButton.Create(Self);
  BrowseButton.Parent := Self;
  BrowseButton.Name := 'BrowseRuntimeButton';
  BrowseButton.SetBounds(430, 42, 96, 28);
  BrowseButton.Caption := 'Browse…';
  BrowseButton.OnClick := @BrowseRuntime;
  DetectButton := TButton.Create(Self);
  DetectButton.Parent := Self;
  DetectButton.Name := 'DetectRuntimeButton';
  DetectButton.SetBounds(535, 42, 106, 28);
  DetectButton.Caption := 'Auto-detect';
  DetectButton.OnClick := @DetectRuntime;
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := Self;
  LabelControl.SetBounds(16, 85, 600, 20);
  LabelControl.Caption := 'Model';
  ModelCombo := TComboBox.Create(Self);
  ModelCombo.Style := csDropDownList;
  ModelCombo.Parent := Self;
  ModelCombo.SetBounds(16, 110, 625, 28);
  ModelCombo.OnChange := @ModelChanged;
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := Self;
  LabelControl.SetBounds(16, 150, 300, 20);
  LabelControl.Caption := 'Reasoning level';
  EffortCombo := TComboBox.Create(Self);
  EffortCombo.Parent := Self;
  EffortCombo.Style := csDropDownList;
  EffortCombo.SetBounds(16, 175, 300, 28);
  EffortCombo.Items.Add('Model default');
  EffortCombo.ItemIndex := 0;
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := Self;
  LabelControl.SetBounds(338, 150, 300, 20);
  LabelControl.Caption := 'Tool usage permissions';
  ApprovalCombo := TComboBox.Create(Self);
  ApprovalCombo.Parent := Self;
  ApprovalCombo.Style := csDropDownList;
  ApprovalCombo.SetBounds(338, 175, 303, 28);
  ApprovalCombo.Items.Add('Ask before file changes and builds');
  ApprovalCombo.Items.Add('Auto: allow project tools');
  ApprovalCombo.Items.Add('Always: allow registered tools');
  ApprovalCombo.ItemIndex := 0;
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := Self;
  LabelControl.AutoSize := False;
  LabelControl.SetBounds(16, 215, 625, 54);
  LabelControl.WordWrap := True;
  LabelControl.Caption := 'Refresh models to discover supported reasoning levels. Ask is read-only; Plan can write Markdown. Auto and Always currently allow the same bounded Lazarus tools.';
  SignIn := TButton.Create(Self);
  SignIn.Parent := Self;
  SignIn.SetBounds(16, 285, 180, 32);
  SignIn.Caption := 'Sign in with ChatGPT';
  SignIn.OnClick := @StartCheck;
  CheckButton := TButton.Create(Self);
  CheckButton.Parent := Self;
  CheckButton.SetBounds(210, 285, 180, 32);
  CheckButton.Caption := 'Check / refresh models';
  CheckButton.OnClick := @StartCheck;
  DeleteProfileButton := TButton.Create(Self);
  DeleteProfileButton.Parent := Self;
  DeleteProfileButton.Name := 'DeleteProfileButton';
  DeleteProfileButton.SetBounds(400, 285, 241, 32);
  DeleteProfileButton.Caption := 'Delete profile directory';
  DeleteProfileButton.Enabled := False;
  DeleteProfileButton.ShowHint := True;
  DeleteProfileButton.Hint := 'Deletes the runtime sign-in directory. Does not remove the connection definition.';
  DeleteProfileButton.OnClick := @DeleteProfile;
  Status := TLabel.Create(Self);
  Status.Name := 'ConnectionStatus';
  Status.Parent := Self;
  Status.AutoSize := False;
  Status.SetBounds(16, 332, 625, 70);
  Status.WordWrap := True;
  Status.Caption := 'Uses ChatGPT subscription access. API-key billing is disabled.';
  Timer := TTimer.Create(Self);
  Timer.Interval := 100;
  Timer.Enabled := False;
  Timer.OnTimer := @Tick;
End;

Destructor TCodexConnectionFrame.Destroy;
Begin
  Timer.Enabled := False;
  If Assigned(Job) Then
    Begin
      Job.Cancel;
      ReapCodexWorker(Job);
      Job := Nil;
    End;
  Inherited Destroy;
End;

Procedure TCodexConnectionFrame.BrowseRuntime(Sender: TObject);
Var
  Dialog: TOpenDialog;
Begin
  If Busy Then Exit;
  Dialog := TOpenDialog.Create(Self);
  Try
    Dialog.Title := 'Select the Codex executable';
    Dialog.Options := [ofFileMustExist, ofPathMustExist, ofEnableSizing];
    If FileExistsUTF8(RuntimeEdit.Text) Then Dialog.FileName := RuntimeEdit.Text;
    If Dialog.Execute Then
      If FileIsExecutable(Dialog.FileName) Then
        Begin
          RuntimeEdit.Text := Dialog.FileName;
          Status.Caption := 'Executable selected. Check this connection to verify compatibility and sign-in.';
        End
      Else Status.Caption := 'The selected file is not executable. Select the Codex program.';
  Finally
    Dialog.Free;
  End;
End;

Procedure TCodexConnectionFrame.DetectRuntime(Sender: TObject);
Var
  Found: String;
Begin
  If Busy Then Exit;
  Found := FindCodexExecutable;
  If Found = '' Then
    Status.Caption := 'Codex was not found on PATH or in the VS Code extension. Use Browse to select an installed executable.'
  Else
    Begin
      RuntimeEdit.Text := Found;
      Status.Caption := 'Installed executable detected. Check this connection to verify compatibility and sign-in.';
    End;
End;

Procedure TCodexConnectionFrame.StartCheck(Sender: TObject);
Begin
  If Assigned(Job) Then Exit;
  RuntimeEdit.Text := Trim(RuntimeEdit.Text);
  If Not FileIsExecutable(RuntimeEdit.Text) Then
    Begin
      Status.Caption := 'The saved Codex path is missing or is not executable. An extension update may have moved it. Use Auto-detect or Browse, then check again.';
      Exit;
    End;
  Job := TAssistantCodexAccount.Create(RuntimeEdit.Text, Profile, Sender = SignIn);
  OpenedUrl := '';
  SignIn.Enabled := False;
  CheckButton.Enabled := False;
  DeleteProfileButton.Enabled := False;
  RuntimeEdit.Enabled := False;
  BrowseButton.Enabled := False;
  DetectButton.Enabled := False;
  Status.Caption := 'Connecting to Codex…';
  Job.Start;
  Timer.Enabled := True;
End;

Function TCodexConnectionFrame.ReasoningEffort: String;
Begin
  If EffortCombo.ItemIndex <= 0 Then Result := ''
  Else Result := EffortCombo.Text;
End;

Function TCodexConnectionFrame.ApprovalMode: String;
Begin
  Case ApprovalCombo.ItemIndex Of 1: Result := 'auto';
    2: Result := 'always';
  Else Result := 'ask';
  End;
End;

Procedure TCodexConnectionFrame.ModelChanged(Sender: TObject);
Var
  Data, Items, ModelData, Levels, Level: TJSONData;
  I, J: Integer;
  Previous, Value: String;
Begin
  Previous := ReasoningEffort;
  EffortCombo.Items.Clear;
  EffortCombo.Items.Add('Model default');
  EffortCombo.ItemIndex := 0;
  If ModelsJson = '' Then Exit;
  Data := GetJSON(ModelsJson);
  Try
    Items := Data.FindPath('data');
    If Not (Items Is TJSONArray) Then Exit;
    For I := 0 To Items.Count - 1 Do
      Begin
        ModelData := Items.Items[I];
        If Not (ModelData Is TJSONObject) Then Continue;
        If TJSONObject(ModelData).Get('model', TJSONObject(ModelData).Get('id', '')) <> ModelCombo.Text Then Continue;
        Levels := ModelData.FindPath('supportedReasoningEfforts');
        If Not (Levels Is TJSONArray) Then Exit;
        For J := 0 To Levels.Count - 1 Do
          Begin
            Level := Levels.Items[J];
            If Not (Level Is TJSONObject) Then Continue;
            Value := TJSONObject(Level).Get('reasoningEffort', '');
            If (Value <> '') And (EffortCombo.Items.IndexOf(Value) < 0) Then EffortCombo.Items.Add(Value);
          End;
        EffortCombo.ItemIndex := EffortCombo.Items.IndexOf(Previous);
        If EffortCombo.ItemIndex < 0 Then EffortCombo.ItemIndex := 0;
        Exit;
      End;
  Finally
    Data.Free;
  End;
End;

Procedure TCodexConnectionFrame.LoadModels(Const Value: String);
Var
  Data, Items, Item: TJSONData;
  I: Integer;
  Previous, Id: String;
Begin
  Data := GetJSON(Value);
  Try
    Items := Data.FindPath('data');
    If Not (Items Is TJSONArray) Then Raise Exception.Create('Invalid model list');
    Previous := ModelCombo.Text;
    ModelCombo.Items.Clear;
    For I := 0 To Items.Count - 1 Do
      Begin
        Item := Items.Items[I];
        If Not (Item Is TJSONObject) Then Continue;
        Id := TJSONObject(Item).Get('model', TJSONObject(Item).Get('id', ''));
        If Id <> '' Then ModelCombo.Items.Add(Id);
      End;
    ModelCombo.ItemIndex := ModelCombo.Items.IndexOf(Previous);
    If (ModelCombo.ItemIndex < 0) And (ModelCombo.Items.Count > 0) Then ModelCombo.ItemIndex := 0;
    ModelsJson := Value;
    ModelChanged(Nil);
  Finally
    Data.Free;
  End;
End;

Function SignInPrompt(Const Url, Code: String; BrowserOpened: Boolean): String;
Begin
  If Not BrowserOpened Then
    Result := 'Could not open the sign-in browser. Open this URL manually: ' + Url
  Else If Code <> '' Then
    Result := 'If the browser asks for a device code, enter ' + Code + '. ' +
      'A page that says device-code sign-in is disabled has nowhere to put it.'
  Else
    Result := 'Complete ChatGPT sign-in in the browser. There is no code to enter.';
End;

Function OpenSignInUrl(Const Url: String): Boolean;
Var
  Proc: TProcess;
  Launcher: String;
Begin
  Result := OpenURL(Url);
  If Result Then Exit;
  Launcher := FindDefaultExecutablePath('xdg-open');
  If Launcher = '' Then Exit;
  Proc := TProcess.Create(Nil);
  Try
    Proc.Executable := Launcher;
    Proc.Parameters.Add(Url);
    Proc.Options := [poNoConsole];
    Proc.Execute;
    Result := True;
  Except
    Result := False;
  End;
  Proc.Free;
End;

Procedure TCodexConnectionFrame.Tick(Sender: TObject);
Var
  Value: TCodexAccountSnapshot;
Begin
  If Not Assigned(Job) Then Exit;
  Value := Job.Snapshot;
  If (Value.LoginUrl <> '') And (Value.LoginUrl <> OpenedUrl) Then
    Begin
      OpenedUrl := Value.LoginUrl;
      Status.Caption := SignInPrompt(OpenedUrl, Value.UserCode, OpenSignInUrl(OpenedUrl));
    End
  Else If (Value.UserCode <> '') And Not Value.Done Then
    Status.Caption := SignInPrompt(OpenedUrl, Value.UserCode, True);
  If Not Value.Done Then Exit;
  Timer.Enabled := False;
  ReapCodexWorker(Job);
  Job := Nil;
  BrowseButton.Enabled := True;
  DetectButton.Enabled := True;
  RuntimeEdit.Enabled := True;
  SignIn.Enabled := True;
  CheckButton.Enabled := True;
  DeleteProfileButton.Enabled := CodexProfilePathIsDerived(Profile);
  If Value.ErrorText <> '' Then
    Begin
      Status.Caption := Value.ErrorText;
      Exit;
    End;
  If Value.State <> ccsSubscriptionAuthenticated Then
    Begin
      Status.Caption := 'ChatGPT sign-in is required for this assistant profile.';
      Exit;
    End;
  Try
    LoadModels(Value.ModelsJson);
  Except
    Status.Caption := 'Signed in, but model discovery returned an invalid response.';
    Exit;
  End;
  If ModelCombo.Items.Count > 0 Then Status.Caption := 'Signed in with ChatGPT. Available allowance is checked when you send a request.'
  Else Status.Caption := 'Signed in, but no available models were discovered.';
End;

Procedure TCodexConnectionFrame.DeleteProfile(Sender: TObject);
Var
  ErrorText: String;
  Present: Boolean;
Begin
  If Busy Then Exit;
  If Not CodexProfilePathIsDerived(Profile) Then
    Begin
      Status.Caption := 'Refusing to delete a path that is not this connection''s derived Codex profile.';
      Exit;
    End;
  Present := DirectoryExists(Profile) Or FileExists(Profile);
  If Not Present Then
    Begin
      Status.Caption := 'No profile directory is present. The connection definition was not changed.';
      Exit;
    End;
  If MessageDlg('Delete the Codex profile directory for this connection?' + LineEnding + LineEnding +
    'Runtime sign-in in that directory will be removed. The connection definition is kept. ' +
    'Saving settings does not delete this directory.',
    mtWarning, [mbYes, mbNo], 0) <> mrYes Then Exit;
  If Not DeleteCodexProfileDirectory(Profile, ErrorText) Then
    Status.Caption := ErrorText
  Else
    Status.Caption := 'Profile directory deleted. The connection definition was kept.';
End;

Procedure TCodexConnectionFrame.LoadConnection(Const ProfileDir, Runtime, Model: String; Const Effort, Approval: String);
Begin
  If Assigned(Job) Then
    Begin
      Job.Cancel;
      ReapCodexWorker(Job);
      Job := Nil;
    End;
  Timer.Enabled := False;
  Profile := ProfileDir;
  ModelsJson := '';
  EffortCombo.Items.Clear;
  EffortCombo.Items.Add('Model default');
  EffortCombo.ItemIndex := 0;
  If Effort <> '' Then
    Begin
      EffortCombo.Items.Add(Effort);
      EffortCombo.ItemIndex := 1;
    End;
  ApprovalCombo.ItemIndex := 0;
  If Approval = 'auto' Then ApprovalCombo.ItemIndex := 1
  Else If Approval = 'always' Then ApprovalCombo.ItemIndex := 2;
  BrowseButton.Enabled := True;
  DetectButton.Enabled := True;
  RuntimeEdit.Enabled := True;
  SignIn.Enabled := True;
  CheckButton.Enabled := True;
  DeleteProfileButton.Enabled := CodexProfilePathIsDerived(ProfileDir);
  RuntimeEdit.Text := Trim(Runtime);
  ModelCombo.Items.Clear;
  If Model <> '' Then
    Begin
      ModelCombo.Items.Add(Model);
      ModelCombo.ItemIndex := 0;
    End;
  Status.Caption := 'Sign in or check this connection. Other connections stay signed in.';
  If Not FileIsExecutable(RuntimeEdit.Text) Then
    Begin
      DetectRuntime(Nil);
      If (Trim(Runtime) <> '') And (RuntimeEdit.Text <> Trim(Runtime)) Then
        Status.Caption := 'The saved executable is no longer available. Found the installed Codex; check this connection, then press OK to save its new path.';
    End;
End;

Function TCodexConnectionFrame.Busy: Boolean;
Begin
  Result := Assigned(Job);
End;
End.
