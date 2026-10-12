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
    AccountGroup: TGroupBox;
    ExecutableLabel: TLabel;
    RuntimeEdit: TEdit;
    BrowseRuntimeButton: TButton;
    DetectRuntimeButton: TButton;
    SignInButton: TButton;
    CheckButton: TButton;
    DeleteProfileButton: TButton;
    ConnectionStatus: TLabel;
    ModelGroup: TGroupBox;
    ModelLabel: TLabel;
    ModelCombo: TComboBox;
    EffortLabel: TLabel;
    EffortCombo: TComboBox;
    ModelNoteLabel: TLabel;
    PermissionsGroup: TGroupBox;
    ApprovalLabel: TLabel;
    ApprovalCombo: TComboBox;
    PermissionNoteLabel: TLabel;
    AccountTimer: TTimer;
    Procedure BrowseRuntime(Sender: TObject);
    Procedure DetectRuntime(Sender: TObject);
    Procedure ModelChanged(Sender: TObject);
    Procedure StartCheck(Sender: TObject);
    Procedure Tick(Sender: TObject);
    Procedure DeleteProfile(Sender: TObject);
  Private
    Job: TAssistantCodexAccount;
    OpenedUrl, ModelsJson: String;
  Public
    Profile: String;
    Procedure LoadConnection(Const ProfileDir, Runtime, Model: String; Const Effort: String = ''; Const Approval: String = 'ask'; Const CachedModels: String = '');
    Procedure LoadModels(Const Value: String);
    Function ReasoningEffort: String;
    Function ApprovalMode: String;
    Function Busy: Boolean;
    Property CachedModelsJson: String Read ModelsJson;
    Destructor Destroy; Override;
  End;

  { Move a cancelled worker's join/destruction off the IDE thread. No IDE callbacks. }
Procedure ReapCodexWorker(Worker: TThread);
/// Fills ModelIds from a saved Codex model list. False leaves ModelIds empty.
Function CollectCodexModelIds(Const ModelsJson: String; ModelIds: TStrings): Boolean;
/// Fills EffortIds for one model. False when that model is not in a valid list.
Function CollectCodexEffortIds(Const ModelsJson, ModelId: String; EffortIds: TStrings): Boolean;

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

Function CollectCodexModelIds(Const ModelsJson: String; ModelIds: TStrings): Boolean;
Var
  Data, Items, Item, ModelId: TJSONData;
  I: Integer;
  Id: String;
Begin
  Result := False;
  If Assigned(ModelIds) Then
    ModelIds.Clear;
  If (Not Assigned(ModelIds)) Or (Trim(ModelsJson) = '') Then
    Exit;
  Data := Nil;
  Try
    Data := GetJSON(ModelsJson);
  Except
    Data := Nil;
  End;
  If Not Assigned(Data) Then
    Exit;
  Try
    If Not (Data Is TJSONObject) Then
      Exit;
    Items := Data.FindPath('data');
    If Not (Items Is TJSONArray) Then
      Exit;
    For I := 0 To Items.Count - 1 Do
      Begin
        Item := Items.Items[I];
        If Not (Item Is TJSONObject) Then
          Continue;
        ModelId := TJSONObject(Item).Find('model');
        If Not Assigned(ModelId) Then
          ModelId := TJSONObject(Item).Find('id');
        If (Not Assigned(ModelId)) Or (ModelId.JSONType <> jtString) Then
          Continue;
        Id := Trim(ModelId.AsString);
        If (Id <> '') And (ModelIds.IndexOf(Id) < 0) Then
          ModelIds.Add(Id);
      End;
    Result := ModelIds.Count > 0;
  Finally
    Data.Free;
  End;
End;

Function CollectCodexEffortIds(Const ModelsJson, ModelId: String; EffortIds: TStrings): Boolean;
Var
  Data, Items, Item, FoundId, Levels, Level, Effort: TJSONData;
  I, J: Integer;
  Wanted, Value: String;
Begin
  Result := False;
  If Assigned(EffortIds) Then
    EffortIds.Clear;
  Wanted := Trim(ModelId);
  If (Not Assigned(EffortIds)) Or (Wanted = '') Or (Trim(ModelsJson) = '') Then
    Exit;
  Data := Nil;
  Try
    Data := GetJSON(ModelsJson);
  Except
    Data := Nil;
  End;
  If Not Assigned(Data) Then
    Exit;
  Try
    If Not (Data Is TJSONObject) Then
      Exit;
    Items := Data.FindPath('data');
    If Not (Items Is TJSONArray) Then
      Exit;
    For I := 0 To Items.Count - 1 Do
      Begin
        Item := Items.Items[I];
        If Not (Item Is TJSONObject) Then
          Continue;
        FoundId := TJSONObject(Item).Find('model');
        If Not Assigned(FoundId) Then
          FoundId := TJSONObject(Item).Find('id');
        If (Not Assigned(FoundId)) Or (FoundId.JSONType <> jtString) Or
          (Not SameText(Trim(FoundId.AsString), Wanted)) Then
          Continue;
        Levels := TJSONObject(Item).Find('supportedReasoningEfforts');
        If Not (Levels Is TJSONArray) Then
          Exit;
        For J := 0 To Levels.Count - 1 Do
          Begin
            Level := Levels.Items[J];
            If Not (Level Is TJSONObject) Then
              Continue;
            Effort := TJSONObject(Level).Find('reasoningEffort');
            If (Not Assigned(Effort)) Or (Effort.JSONType <> jtString) Then
              Continue;
            Value := Trim(Effort.AsString);
            If (Value <> '') And (EffortIds.IndexOf(Value) < 0) Then
              EffortIds.Add(Value);
          End;
        Result := True;
        Exit;
      End;
  Finally
    Data.Free;
  End;
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

Destructor TCodexConnectionFrame.Destroy;
Begin
  If Assigned(AccountTimer) Then
    AccountTimer.Enabled := False;
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
          ConnectionStatus.Caption := 'Executable selected. Check this connection to verify compatibility and sign-in.';
        End
      Else ConnectionStatus.Caption := 'The selected file is not executable. Select the Codex program.';
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
    ConnectionStatus.Caption := 'Codex was not found on PATH or in the VS Code extension. Use Browse to select an installed executable.'
  Else
    Begin
      RuntimeEdit.Text := Found;
      ConnectionStatus.Caption := 'Installed executable detected. Check this connection to verify compatibility and sign-in.';
    End;
End;

Procedure TCodexConnectionFrame.StartCheck(Sender: TObject);
Begin
  If Assigned(Job) Then Exit;
  RuntimeEdit.Text := Trim(RuntimeEdit.Text);
  If Not FileIsExecutable(RuntimeEdit.Text) Then
    Begin
      ConnectionStatus.Caption := 'The saved Codex path is missing or is not executable. An extension update may have moved it. Use Auto-detect or Browse, then check again.';
      Exit;
    End;
  Job := TAssistantCodexAccount.Create(RuntimeEdit.Text, Profile, Sender = SignInButton);
  OpenedUrl := '';
  SignInButton.Enabled := False;
  CheckButton.Enabled := False;
  DeleteProfileButton.Enabled := False;
  RuntimeEdit.Enabled := False;
  BrowseRuntimeButton.Enabled := False;
  DetectRuntimeButton.Enabled := False;
  ConnectionStatus.Caption := 'Connecting to Codex…';
  Job.Start;
  AccountTimer.Enabled := True;
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
  Data, Items, ModelData, ModelId, Levels, Level: TJSONData;
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
        ModelId := TJSONObject(ModelData).Find('model');
        If Not Assigned(ModelId) Then ModelId := TJSONObject(ModelData).Find('id');
        If ModelId.AsString <> ModelCombo.Text Then Continue;
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
  Data, Items, Item, ModelId, Levels, Level, Effort: TJSONData;
  I, J: Integer;
  Previous, Id: String;
  Models: TStringList;
Begin
  Data := GetJSON(Value);
  Models := TStringList.Create;
  Try
    If Not (Data Is TJSONObject) Then Raise Exception.Create('Invalid model list');
    Items := Data.FindPath('data');
    If Not (Items Is TJSONArray) Then Raise Exception.Create('Invalid model list');
    { Validate the whole response before replacing the last usable lists. }
    For I := 0 To Items.Count - 1 Do
      Begin
        Item := Items.Items[I];
        If Not (Item Is TJSONObject) Then Raise Exception.Create('Invalid model');
        ModelId := TJSONObject(Item).Find('model');
        If Not Assigned(ModelId) Then ModelId := TJSONObject(Item).Find('id');
        If Not Assigned(ModelId) Then Raise Exception.Create('Missing model identifier');
        If ModelId.JSONType <> jtString Then Raise Exception.Create('Invalid model identifier');
        Id := ModelId.AsString;
        If Trim(Id) = '' Then Raise Exception.Create('Empty model identifier');
        Levels := TJSONObject(Item).Find('supportedReasoningEfforts');
        If Not (Levels Is TJSONArray) Then Raise Exception.Create('Invalid reasoning levels');
        For J := 0 To Levels.Count - 1 Do
          Begin
            Level := Levels.Items[J];
            If Not (Level Is TJSONObject) Then Raise Exception.Create('Invalid reasoning level');
            Effort := TJSONObject(Level).Find('reasoningEffort');
            If Not Assigned(Effort) Then Raise Exception.Create('Missing reasoning level');
            If Effort.JSONType <> jtString Then Raise Exception.Create('Invalid reasoning level');
            If Trim(Effort.AsString) = '' Then Raise Exception.Create('Empty reasoning level');
          End;
        If Models.IndexOf(Id) < 0 Then Models.Add(Id);
      End;
    If Models.Count = 0 Then Raise Exception.Create('Empty model list');
    Previous := ModelCombo.Text;
    ModelCombo.Items.Assign(Models);
    ModelCombo.ItemIndex := ModelCombo.Items.IndexOf(Previous);
    If ModelCombo.ItemIndex < 0 Then ModelCombo.ItemIndex := 0;
    ModelsJson := Value;
    ModelChanged(Nil);
  Finally
    Models.Free;
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
      ConnectionStatus.Caption := SignInPrompt(OpenedUrl, Value.UserCode, OpenSignInUrl(OpenedUrl));
    End
  Else If (Value.UserCode <> '') And Not Value.Done Then
    ConnectionStatus.Caption := SignInPrompt(OpenedUrl, Value.UserCode, True);
  If Not Value.Done Then Exit;
  AccountTimer.Enabled := False;
  ReapCodexWorker(Job);
  Job := Nil;
  BrowseRuntimeButton.Enabled := True;
  DetectRuntimeButton.Enabled := True;
  RuntimeEdit.Enabled := True;
  SignInButton.Enabled := True;
  CheckButton.Enabled := True;
  DeleteProfileButton.Enabled := CodexProfilePathIsDerived(Profile);
  If Value.ErrorText <> '' Then
    Begin
      ConnectionStatus.Caption := Value.ErrorText;
      Exit;
    End;
  If Value.State <> ccsSubscriptionAuthenticated Then
    Begin
      ConnectionStatus.Caption := 'ChatGPT sign-in is required for this assistant profile.';
      Exit;
    End;
  Try
    LoadModels(Value.ModelsJson);
  Except
    ConnectionStatus.Caption := 'Signed in, but model discovery returned an invalid response.';
    Exit;
  End;
  If ModelCombo.Items.Count > 0 Then ConnectionStatus.Caption := 'Signed in with ChatGPT. Available allowance is checked when you send a request.'
  Else ConnectionStatus.Caption := 'Signed in, but no available models were discovered.';
End;

Procedure TCodexConnectionFrame.DeleteProfile(Sender: TObject);
Var
  ErrorText: String;
  Present: Boolean;
Begin
  If Busy Then Exit;
  If Not CodexProfilePathIsDerived(Profile) Then
    Begin
      ConnectionStatus.Caption := 'Refusing to delete a path that is not this connection''s derived Codex profile.';
      Exit;
    End;
  Present := DirectoryExists(Profile) Or FileExists(Profile);
  If Not Present Then
    Begin
      ConnectionStatus.Caption := 'No profile directory is present. The connection definition was not changed.';
      Exit;
    End;
  If MessageDlg('Delete the Codex profile directory for this connection?' + LineEnding + LineEnding +
    'Runtime sign-in in that directory will be removed. The connection definition is kept. ' +
    'Saving settings does not delete this directory.',
    mtWarning, [mbYes, mbNo], 0) <> mrYes Then Exit;
  If Not DeleteCodexProfileDirectory(Profile, ErrorText) Then
    ConnectionStatus.Caption := ErrorText
  Else
    ConnectionStatus.Caption := 'Profile directory deleted. The connection definition was kept.';
End;

Procedure TCodexConnectionFrame.LoadConnection(Const ProfileDir, Runtime, Model: String; Const Effort, Approval, CachedModels: String);
Var
  SavedModels: String;
Begin
  SavedModels := CachedModels;
  If Assigned(Job) Then
    Begin
      Job.Cancel;
      ReapCodexWorker(Job);
      Job := Nil;
    End;
  AccountTimer.Enabled := False;
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
  BrowseRuntimeButton.Enabled := True;
  DetectRuntimeButton.Enabled := True;
  RuntimeEdit.Enabled := True;
  SignInButton.Enabled := True;
  CheckButton.Enabled := True;
  DeleteProfileButton.Enabled := CodexProfilePathIsDerived(ProfileDir);
  RuntimeEdit.Text := Trim(Runtime);
  ModelCombo.Items.Clear;
  If Model <> '' Then
    Begin
      ModelCombo.Items.Add(Model);
      ModelCombo.ItemIndex := 0;
    End;
  If SavedModels <> '' Then
    Begin
      Try
        LoadModels(SavedModels);
      Except
        { Ignore an invalid stored cache; the saved selection remains usable. }
      End;
      { Cached discovery may be older than the saved model or effort. }
      If Model <> '' Then
        Begin
          If ModelCombo.Items.IndexOf(Model) < 0 Then ModelCombo.Items.Add(Model);
          ModelCombo.ItemIndex := ModelCombo.Items.IndexOf(Model);
          ModelChanged(Nil);
        End;
      If Effort = '' Then EffortCombo.ItemIndex := 0
      Else
        Begin
          If EffortCombo.Items.IndexOf(Effort) < 0 Then EffortCombo.Items.Add(Effort);
          EffortCombo.ItemIndex := EffortCombo.Items.IndexOf(Effort);
        End;
    End;
  ConnectionStatus.Caption := 'Sign in or check this connection. Other connections stay signed in.';
  If Not FileIsExecutable(RuntimeEdit.Text) Then
    Begin
      DetectRuntime(Nil);
      If (Trim(Runtime) <> '') And (RuntimeEdit.Text <> Trim(Runtime)) Then
        ConnectionStatus.Caption := 'The saved executable is no longer available. Found the installed Codex; check this connection, then press OK to save its new path.';
    End;
End;

Function TCodexConnectionFrame.Busy: Boolean;
Begin
  Result := Assigned(Job);
End;

Initialization

RegisterClass(TCodexConnectionFrame);

End.
