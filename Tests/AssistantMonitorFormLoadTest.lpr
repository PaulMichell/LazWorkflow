Program AssistantMonitorFormLoadTest;

{ Opening the Remote Monitor dialog does not rewrite the stored settings (c) 2026 Michell Computing.

  Plan item 3.4 of Documents/Plan-20261105-130659.md. LoadFields sets
  RemoteApprovalCheck.Checked before AddressEdit.Text. With remote approval
  stored as on, that fired RemoteApprovalCheckClick, which saved an empty bind
  address and Enabled := ListenerRunning while the dialog was still loading.
  Closing the dialog wrote the address back, so the check right after creation
  is the one that catches the fault. The check after closing is the one the plan
  asks for.

  GUI test: needs a display. Settings go to a temporary directory, never the
  IDE's primary config. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Forms, Classes, SysUtils, AssistantTestIDEHost, WorkflowSettings, AssistantMonitorSettings,
  AssistantMonitorForm;

Const
  StoredAddress = '192.168.77.5';
  StoredPort = 47123;

Var
  FailCount: Integer;
  SettingsRoot: String;

Procedure Check(Const Title: String; Condition: Boolean);
Begin
  If Condition Then
    WriteLn('ok   ', Title)
  Else
    Begin
      WriteLn('FAIL ', Title);
      Inc(FailCount);
    End;
End;

Procedure UseTemporarySettings;
Var
  Guid: TGUID;
Begin
  If CreateGUID(Guid) <> 0 Then
    Raise Exception.Create('Could not create a settings directory name');
  SettingsRoot := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-monitor-form-' + GUIDToString(Guid);
  If Not ForceDirectories(SettingsRoot) Then
    Raise Exception.Create('Could not create ' + SettingsRoot);
  SetWorkflowSettingsDirectory(SettingsRoot);
End;

Procedure RemoveTemporarySettings;
Var
  SettingsFile: String;
Begin
  If SettingsRoot = '' Then
    Exit;
  SettingsFile := WorkflowSettingsPath;
  SetWorkflowSettingsDirectory('');
  If SettingsFile <> '' Then
    Begin
      DeleteFile(SettingsFile);
      DeleteFile(SettingsFile + '.tmp');
    End;
  RemoveDir(ExcludeTrailingPathDelimiter(SettingsRoot));
  SettingsRoot := '';
End;

Procedure StoreSettings;
Var
  Settings: TMonitorSettings;
  ErrorText: String;
Begin
  Settings := DefaultMonitorSettings;
  Settings.Enabled := True;
  Settings.Port := StoredPort;
  Settings.BindAddress := StoredAddress;
  Settings.BindAll := False;
  Settings.RemoteApproval := True;
  If Not SaveMonitorSettings(Settings, ErrorText) Then
    Raise Exception.Create('Could not store monitor settings: ' + ErrorText);
End;

Function Stored(Out Settings: TMonitorSettings): Boolean;
Var
  ErrorText: String;
Begin
  Result := LoadMonitorSettings(Settings, ErrorText);
  If Not Result Then
    WriteLn('settings did not load: ', ErrorText);
End;

Procedure TestTimerKeepsClientList;
Var
  Form: TAssistantMonitorForm;
  Settings: TMonitorSettings;
  ErrorText: String;
  I, PreviousTop: Integer;
Begin
  StoreSettings;
  If Not Stored(Settings) Then
    Exit;
  SetLength(Settings.Clients, 80);
  For I := 0 To High(Settings.Clients) Do
    Begin
      Settings.Clients[I].Id := 'client-' + IntToStr(I);
      Settings.Clients[I].Name := 'Phone ' + IntToStr(I);
    End;
  If Not SaveMonitorSettings(Settings, ErrorText) Then
    Raise Exception.Create(ErrorText);
  Form := TAssistantMonitorForm.Create(Nil);
  Try
    Form.Show;
    Application.ProcessMessages;
    Form.ClientList.ItemIndex := 45;
    Form.ClientList.TopIndex := 40;
    PreviousTop := Form.ClientList.TopIndex;
    For I := 1 To 5 Do
      Form.StatusTimerTimer(Nil);
    Check('idle timer preserves client selection', Form.ClientList.ItemIndex = 45);
    Check('idle timer preserves client scroll position', Form.ClientList.TopIndex = PreviousTop);
    If Not SaveMonitorSettings(Settings, ErrorText) Then
      Raise Exception.Create(ErrorText);
    Form.StatusTimerTimer(Nil);
    Check('unchanged saved clients preserve scroll position', Form.ClientList.TopIndex = PreviousTop);
    Settings.Clients[45].Name := 'Renamed phone';
    If Not SaveMonitorSettings(Settings, ErrorText) Then
      Raise Exception.Create(ErrorText);
    Form.StatusTimerTimer(Nil);
    Check('timer observes changed client names', Form.ClientList.Items[45] = 'Renamed phone');
    Check('changed clients preserve selection by id', Form.ClientList.ItemIndex = 45);
  Finally
    Form.Free;
  End;
End;

Procedure TestOpenDoesNotSave;
Var
  Form: TAssistantMonitorForm;
  Settings: TMonitorSettings;
Begin
  StoreSettings;
  Form := TAssistantMonitorForm.Create(Nil);
  Try
    Check('the stored settings still load after the dialog is created', Stored(Settings));
    Check('creating the dialog keeps the stored bind address', Settings.BindAddress = StoredAddress);
    Check('creating the dialog keeps the stored enabled flag', Settings.Enabled);
    Check('creating the dialog keeps remote approval on', Settings.RemoteApproval);
    Check('creating the dialog keeps the stored port', Settings.Port = StoredPort);
    Form.Show;
    Application.ProcessMessages;
    Form.Close;
    Application.ProcessMessages;
    Check('the stored settings still load after the dialog is closed', Stored(Settings));
    Check('closing the dialog without changes keeps the stored bind address', Settings.BindAddress = StoredAddress);
    Check('closing the dialog without changes keeps remote approval on', Settings.RemoteApproval);
    Check('closing the dialog without changes keeps the stored port', Settings.Port = StoredPort);
  Finally
    Form.Free;
  End;
End;

Begin
  FailCount := 0;
  SettingsRoot := '';
  Try
    Application.Initialize;
    UseTemporarySettings;
    Try
      TestOpenDoesNotSave;
      TestTimerKeepsClientList;
    Finally
      RemoveTemporarySettings;
    End;
  Except
    On E: Exception Do
      Begin
        WriteLn('FAIL ', E.ClassName, ': ', E.Message);
        Inc(FailCount);
      End;
  End;
  If FailCount = 0 Then
    WriteLn('AssistantMonitorFormLoadTest passed')
  Else
    Begin
      WriteLn(FailCount, ' failure(s)');
      Halt(1);
    End;
End.
