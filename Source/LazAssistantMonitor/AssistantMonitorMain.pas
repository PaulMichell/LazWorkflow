Unit AssistantMonitorMain;

{ IDE menu and listener lifetime for the remote monitor (c) 2026 Michell Computing.

  Looks up the Assistant menu registered by LazAssistantTools. Does not create a
  second top-level Assistant menu, and does not edit that package. The listen
  thread is FreeOnTerminate false. Shutdown waits for it. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, AssistantMonitorSession;

Procedure RegisterAssistantMonitor;
Procedure StopAssistantMonitorListener;
Function StartAssistantMonitorListener(Out ErrorText: String): Boolean;
Function MonitorLiveSession: TMonitorSession;
Function AssistantMonitorListenerRunning: Boolean;

Implementation

Uses
  Classes, Forms, LCLType, MenuIntf, IDECommands, WorkflowLog,
  AssistantMonitorForm, AssistantMonitorBridge, AssistantMonitorSettings, AssistantMonitorLan,
  AssistantMonitorTls;

Var
  LiveSession: TMonitorSession;
  LiveCarrier: TMonitorLanCarrier;
  RemoteMonitorCommand: TIDECommand;
  StoppingListener: Boolean;

Function MonitorLiveSession: TMonitorSession;
Begin
  Result := LiveSession;
End;

Function AssistantMonitorListenerRunning: Boolean;
Begin
  Result := Assigned(LiveSession) And (LiveSession.State <> mssStopped);
End;

Procedure StopAssistantMonitorListener;
Begin
  { WaitFor pumps the main thread. A second entry must not release the carrier while the first join is still running. }
  If StoppingListener Then
    Exit;
  StoppingListener := True;
  Try
    If Assigned(LiveSession) Then
      LiveSession.StopListening;
    DetachAssistantMonitorBridge;
    { Carrier.Stop joins the listen thread once. Unix WaitFor is pthread_join, and a second join is an access violation. }
    If Assigned(LiveCarrier) Then
      LiveCarrier.Stop;
    { The session interface owns the carrier. Releasing it destroys the object. Freeing the class pointer afterwards is an access violation. }
    If Assigned(LiveSession) Then
      LiveSession.AttachCarrier(Nil);
    LiveCarrier := Nil;
    FreeAndNil(LiveSession);
  Finally
    StoppingListener := False;
  End;
End;

Function StartAssistantMonitorListener(Out ErrorText: String): Boolean;
Var
  Settings: TMonitorSettings;
  Address, Fingerprint, HostId: String;
  Carrier: TMonitorLanCarrier;
  Session: TMonitorSession;
Begin
  Result := False;
  ErrorText := '';
  If AssistantMonitorListenerRunning Then
    Begin
      Result := True;
      Exit;
    End;
  If Not CaptureMonitorListenSnapshot(Settings, ErrorText) Then
    Exit;
  If Not ResolveMonitorBind(Settings, Address, ErrorText) Then
    Exit;
  If Not EnsureMonitorHostCertificate(ErrorText) Then
    Exit;
  Session := TMonitorSession.Create;
  Carrier := TMonitorLanCarrier.Create(Address, Settings.Port, MonitorCertificateFile, MonitorKeyFile);
  Try
    Try
      Carrier.AttachSession(Session);
      Session.AttachCarrier(Carrier);
      If Not Session.StartListening(Address, Settings.Port, ErrorText) Then
        Exit;
      If Not Carrier.Start(ErrorText) Then
        Begin
          If ErrorText = '' Then
            ErrorText := Carrier.LastError;
          Session.StopListening;
          Carrier.Stop;
          Exit;
        End;
      LiveSession := Session;
      LiveCarrier := Carrier;
      Session := Nil;
      Carrier := Nil;
    Except
      On E: Exception Do
        Begin
          ErrorText := E.Message;
          If Assigned(Session) Then
            Session.StopListening;
          If Assigned(Carrier) Then
            Carrier.Stop;
        End;
    End;
  Finally
    { Same ownership as Stop. The session interface is the only reference, so releasing it destroys the carrier. }
    If Assigned(Session) And Assigned(Session.Carrier) Then
      Begin
        Session.AttachCarrier(Nil);
        Carrier := Nil;
      End;
    FreeAndNil(Carrier);
    FreeAndNil(Session);
  End;
  If Not AssistantMonitorListenerRunning Then
    Exit;
  AttachAssistantMonitorBridge(LiveSession);
  If MonitorHostFingerprint(Fingerprint, ErrorText) Then
    LiveSession.SetHostFingerprint(Fingerprint);
  If EnsureMonitorHostId(HostId, ErrorText) Then
    LiveSession.SetInstallationHostId(HostId)
  Else If ErrorText <> '' Then
    WorkflowLogger.Warning('AssistantMonitor', 'host id was not stored: ' + ErrorText);
  ErrorText := '';
  Result := True;
  WorkflowLogger.Info('AssistantMonitor', 'listen start bind=' + Address + ' port=' + IntToStr(Settings.Port));
End;

Procedure ShowRemoteMonitor(Sender: TObject);
Begin
  ShowAssistantMonitorForm;
End;

Procedure RegisterRemoteMonitorMenu;
Var
  Item: TIDEMenuItem;
  AssistantMenu, MonitorSec: TIDEMenuSection;
  Cat: TIDECommandCategory;
  Key: TIDEShortCut;
Begin
  If Not Assigned(mnuMain) Then
    Exit;
  Item := mnuMain.FindByName('Assistant');
  If Not (Item Is TIDEMenuSection) Then
    Begin
      WorkflowLogger.Warning('AssistantMonitor', 'Assistant menu is not registered. Remote Monitor was not added.');
      Exit;
    End;
  AssistantMenu := TIDEMenuSection(Item);
  Cat := IDECommandList.FindCategoryByName('Assistant');
  If Cat = Nil Then
    Cat := IDECommandList.CreateCategory(Nil, 'Assistant', 'Assistant');
  Key := IDEShortCut(VK_UNKNOWN, []);
  If Not Assigned(RemoteMonitorCommand) Then
    RemoteMonitorCommand := RegisterIDECommand(Cat, 'AssistantRemoteMonitor', 'Remote Monitor', Key, Nil,
      @ShowRemoteMonitor);
  MonitorSec := RegisterIDEMenuSection(AssistantMenu, 'AssistantMonitorCmds');
  RegisterIDEMenuCommand(MonitorSec, 'AssistantRemoteMonitor', 'Remote Monitor…', Nil, Nil, RemoteMonitorCommand);
End;

Procedure RegisterAssistantMonitor;
Var
  Settings: TMonitorSettings;
  ErrorText: String;
Begin
  AssistantMonitorBridge.RegisterAssistantMonitor;
  RegisterRemoteMonitorMenu;
  If Not LoadMonitorSettings(Settings, ErrorText) Then
    Exit;
  If Not Settings.Enabled Then
    Exit;
  If Not StartAssistantMonitorListener(ErrorText) Then
    WorkflowLogger.Warning('AssistantMonitor', 'enabled listener did not start: ' + ErrorText);
End;

Initialization

Finalization

UnregisterAssistantMonitor;
StopAssistantMonitorListener;

End.
