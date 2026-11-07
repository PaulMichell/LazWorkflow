Unit AssistantMonitorLan;

{ Host-listens LAN carrier for monitor frames (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. This unit keeps accept, the
  simultaneous cap, and bind. The section 4 link thread is AssistantMonitorLink,
  not this unit.
  Reviewed 2026-11-07: no form code and no relay class.

  The listen thread keeps TInetServer for accept and the simultaneous cap. It
  hands each accepted socket to a link thread and does not read or write it.
  AcceptIdleTimeOut stays 250 ms and is not on any send or receive path.
  TLS, the wake handle, and the frame loop live in AssistantMonitorLink.
  A second socket that finishes TLS replaces the controller. The spare
  rejected busy path is gone.

  Listen path is ssockets.TInetServer. The client handler is a plain
  TSocketHandler, so accept does not call SSL_accept. OpenSSL load is
  AssistantHttps.EnsureOpenSSLReady. Frame bytes are AssistantMonitorFrames.
  There is no relay class.

  Accepted-socket non-blocking is not SetSocketBlockingMode and not
  TSocketServer.SetNonBlocking. Those helpers do not cover the accepted handle.
  The two calls below are the helpers' own fpfcntl or ioctlsocket lines.
  Every accepted socket also gets TCP keepalive, a backstop under the session heartbeat.
  The kernel port is sockets.fpGetSockName on TInetServer.FPSocket.
  TInetServer.Port is not read. Bind failures are TThread.Queue to the main thread. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, SyncObjs, ssockets, AssistantMonitorCarrier, AssistantMonitorFrames, AssistantMonitorLink,
  AssistantMonitorSession;

Const
  MonitorAcceptIdleMs = 250;
  MonitorSimultaneousCap = 2;

Type
  TMonitorListenThread = Class;

  { v1 host listener. Start reports mcsListening, then mcsConnected for the
    controller socket. It never reports mcsConnecting. }
  TMonitorLanCarrier = Class(TMonitorLinkHost, IMonitorCarrier)
  Private
    FLock: TRTLCriticalSection;
    FThread: TMonitorListenThread;
    FController: TMonitorLinkThread;
    FHandler: TMonitorFrameHandler;
    FSession: TMonitorSession;
    FState: TMonitorCarrierState;
    FBindAddress: String;
    FPort: Word;
    FCertificatePath: String;
    FKeyPath: String;
    FBoundPort: Word;
    FLastError: String;
    FJoined: Boolean;
    Procedure LockCarrier;
    Procedure UnlockCarrier;
    Procedure StoreError(Const ErrorText: String);
    Procedure NoteListening(BoundPort: Word);
    Procedure NoteConnected;
    Procedure NoteControllerDropped;
    Procedure NoteClosed;
    Function CopyHandler: TMonitorFrameHandler;
    Function CopySession: TMonitorSession;
    Function OutboundEmpty: Boolean;
    Procedure WakeController;
    Procedure ForgetController(Link: TMonitorLinkThread);
    Procedure DetachController;
  Public
    Constructor Create(Const BindAddress: String; Port: Integer; Const CertificatePath, KeyPath: String);
    Destructor Destroy; Override;
    Function Start(Out ErrorText: String): Boolean;
    Procedure Stop;
    Function Send(Const Frame: TMonitorFrame; Out ErrorText: String): Boolean;
    Function State: TMonitorCarrierState;
    Procedure SetFrameHandler(Handler: TMonitorFrameHandler);
    Procedure AttachSession(Session: TMonitorSession);
    { Kernel port after Bind. Zero before a successful bind. }
    Function BoundPort: Word;
    Function IsController(Link: TMonitorLinkThread): Boolean; Override;
    Function BeginLinkPass(Link: TMonitorLinkThread): TObject; Override;
    Function TakeSessionFrame(Link: TMonitorLinkThread; Out Bytes: RawByteString): Boolean; Override;
    Function OutboundPending(Link: TMonitorLinkThread): Boolean; Override;
    Function OutboundCount(Link: TMonitorLinkThread): Integer; Override;
    Procedure DeliverFrame(Link: TMonitorLinkThread; Const Frame: TMonitorFrame); Override;
    Procedure NotePartialFrame(Link: TMonitorLinkThread; Open: Boolean); Override;
    Procedure NoteTime(Link: TMonitorLinkThread; NowMs: QWord); Override;
    Function AcceptLink(Out RejectFrame: TMonitorFrame): Boolean; Override;
    Function CloseRequested(Link: TMonitorLinkThread): Boolean; Override;
    Function PrepareReplace(Link: TMonitorLinkThread): TMonitorLinkThread; Override;
    Procedure AdoptController(Link: TMonitorLinkThread); Override;
    Function ReleaseController(Link: TMonitorLinkThread): Boolean; Override;
    { Valid from a successful Start until Stop returns. Stop joins the thread. Do not WaitFor as well. }
    Property ListenThread: TMonitorListenThread Read FThread;
    Property LastError: String Read FLastError;
  End;

  { FreeOnTerminate is false. Stop joins this thread once. A second WaitFor is undefined on Unix. }
  TMonitorListenThread = Class(TThread)
  Private
    Type
      TMonitorLinkSlot = Record
        Stream: TSocketStream;
        Link: TMonitorLinkThread;
      End;
    Var
      FCarrier: TMonitorLanCarrier;
    FBindAddress: String;
    FPort: Word;
    FCertificatePath: String;
    FKeyPath: String;
    FCertificateDer: TBytes;
    FKeyDer: TBytes;
    FServer: TInetServer;
    FReady: PRTLEvent;
    FSignaled: Boolean;
    FBindOk: Boolean;
    FErrorText: String;
    FBoundPort: Word;
    FSlots: Array Of TMonitorLinkSlot;
    Procedure Fail(Const ErrorText: String);
    Procedure StopLinks;
    Procedure ReleaseServer;
    Procedure CreateClientHandler(Sender: TObject; Out AHandler: TSocketHandler);
    Procedure HandleConnect(Sender: TObject; Data: TSocketStream);
    Procedure HandleIdle(Sender: TObject);
    Procedure HandleDropped(Sender: TObject; Data: TSocketStream);
    Function Handoff(Data: TSocketStream): Boolean;
    Procedure ReapFinished;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(Const NewBindAddress: String; NewPort: Word; Const NewCertificatePath, NewKeyPath: String;
      OwnerCarrier: TMonitorLanCarrier);
    Destructor Destroy; Override;
    Property Server: TInetServer Read FServer;
    Property BoundPort: Word Read FBoundPort;
    Property ErrorText: String Read FErrorText;
  End;

{ Kernel port of a bound TInetServer. Does not read TInetServer.Port. }
Function MonitorKernelPort(Server: TInetServer): Word;

Implementation

Uses
  {$IFDEF UNIX}
  BaseUnix,
  {$ENDIF}
  {$IFDEF WINDOWS}
  Windows, winsock2,
  {$ENDIF}
  sockets, AssistantHttps, AssistantMonitorCodec, AssistantMonitorTls, WorkflowLog;

Const
  MonitorBindWaitMs = 10000;
  { Keepalive probes start after the heartbeat's dead-link time, so the heartbeat normally acts first. }
  MonitorKeepAliveIdleSeconds = MonitorDeadSessionMs Div 1000;
  MonitorKeepAliveIntervalSeconds = MonitorHeartbeatMs Div 1000;
  MonitorKeepAliveProbes = 3;

Type
  TMonitorBindNotice = Class
    MessageText: String;
    Procedure Run;
  End;

Procedure LogMonitor(Level: Integer; Const Text: String);
Begin
  If Not Assigned(WorkflowLogger) Then
    Exit;
  Case Level Of
    1: WorkflowLogger.Info(MonitorLogArea, Text);
    2: WorkflowLogger.Warning(MonitorLogArea, Text);
    3: WorkflowLogger.Error(MonitorLogArea, Text);
  Else
    WorkflowLogger.Debug(MonitorLogArea, Text);
  End;
End;

Procedure TMonitorBindNotice.Run;
Begin
  Try
    Try
      LogMonitor(3, MessageText);
    Except
      On E: Exception Do
        ReportPluginException(MonitorLogArea, E);
    End;
  Finally
    Free;
  End;
End;

Procedure QueueMainError(Const MessageText: String);
Var
  Notice: TMonitorBindNotice;
Begin
  Notice := TMonitorBindNotice.Create;
  Notice.MessageText := MessageText;
  Try
    TThread.Queue(Nil, @Notice.Run);
  Except
    On E: Exception Do
      Begin
        Notice.Free;
        ReportPluginException(MonitorLogArea, E);
      End;
  End;
End;

{ The FCL helpers leave the accepted handle blocking. These are their own calls. }
Procedure SetAcceptedHandleNonBlocking(Handle: THandle);
{$IFDEF UNIX}
Var
  Flags: Integer;
{$ENDIF}
{$IFDEF WINDOWS}
Var
  NonBlock: u_long;
{$ENDIF}
Begin
{$IFDEF UNIX}
  Flags := fpfcntl(Handle, F_GETFL, 0);
  If Flags >= 0 Then
    fpfcntl(Handle, F_SETFL, Flags Or O_NONBLOCK);
{$ENDIF}
{$IFDEF WINDOWS}
  NonBlock := 1; { u_long. FIONBIO treats a non-zero value as non-blocking. }
  ioctlsocket(Handle, Longint(FIONBIO), @NonBlock);
{$ENDIF}
End;

{ Backstop for a peer that vanished without a FIN. Linux also takes the probe timing,
  other systems keep their default timing. A failed call leaves the heartbeat in charge. }
Procedure EnableAcceptedKeepAlive(Handle: THandle);
{$IFDEF LINUX}
Const
  { Linux netinet/tcp.h values. }
  TcpKeepIdle = 4;
  TcpKeepInterval = 5;
  TcpKeepCount = 6;
{$ENDIF}
Var
  Value: Longint;
Begin
  Value := 1;
  If fpsetsockopt(Handle, SOL_SOCKET, SO_KEEPALIVE, @Value, SizeOf(Value)) <> 0 Then
    Begin
      LogMonitor(2, 'keepalive not enabled error=' + IntToStr(socketerror));
      Exit;
    End;
{$IFDEF LINUX}
  Value := MonitorKeepAliveIdleSeconds;
  fpsetsockopt(Handle, IPPROTO_TCP, TcpKeepIdle, @Value, SizeOf(Value));
  Value := MonitorKeepAliveIntervalSeconds;
  fpsetsockopt(Handle, IPPROTO_TCP, TcpKeepInterval, @Value, SizeOf(Value));
  Value := MonitorKeepAliveProbes;
  fpsetsockopt(Handle, IPPROTO_TCP, TcpKeepCount, @Value, SizeOf(Value));
{$ENDIF}
End;

Function MonitorKernelPort(Server: TInetServer): Word;
Var
  Addr: TSockAddr;
  Len: TSockLen;
Begin
  Result := 0;
  Addr := Default(TSockAddr);
  If Not Assigned(Server) Then
    Exit;
  Len := SizeOf(Addr);
  { TInetServer.Port stays at the requested value. Bind does not rewrite it. }
  If fpGetSockName(Server.FPSocket.FD, @Addr, @Len) <> 0 Then
    Exit;
  Result := NToHs(Addr.sin_port);
End;

{ TMonitorLanCarrier }

Constructor TMonitorLanCarrier.Create(Const BindAddress: String; Port: Integer; Const CertificatePath, KeyPath: String);
Begin
  Inherited Create;
  InitCriticalSection(FLock);
  FThread := Nil;
  FController := Nil;
  FHandler := Nil;
  FSession := Nil;
  FState := mcsIdle;
  FBindAddress := BindAddress;
  If (Port >= 0) And (Port <= 65535) Then
    FPort := Word(Port)
  Else
    FPort := 0;
  FCertificatePath := CertificatePath;
  FKeyPath := KeyPath;
  FBoundPort := 0;
  FLastError := '';
  FJoined := False;
End;

Destructor TMonitorLanCarrier.Destroy;
Begin
  Stop;
  DoneCriticalSection(FLock);
  Inherited Destroy;
End;

Procedure TMonitorLanCarrier.LockCarrier;
Begin
  EnterCriticalSection(FLock);
End;

Procedure TMonitorLanCarrier.UnlockCarrier;
Begin
  LeaveCriticalSection(FLock);
End;

Procedure TMonitorLanCarrier.StoreError(Const ErrorText: String);
Begin
  LockCarrier;
  Try
    FLastError := ErrorText;
  Finally
    UnlockCarrier;
  End;
End;

Procedure TMonitorLanCarrier.NoteListening(BoundPort: Word);
Begin
  LockCarrier;
  Try
    FBoundPort := BoundPort;
    FLastError := '';
    If FState <> mcsClosed Then
      FState := mcsListening;
  Finally
    UnlockCarrier;
  End;
End;

Procedure TMonitorLanCarrier.NoteConnected;
Begin
  LockCarrier;
  Try
    If (FState = mcsListening) Or (FState = mcsConnected) Then
      FState := mcsConnected;
  Finally
    UnlockCarrier;
  End;
End;

Procedure TMonitorLanCarrier.NoteControllerDropped;
Begin
  LockCarrier;
  Try
    If FState = mcsConnected Then
      FState := mcsListening;
  Finally
    UnlockCarrier;
  End;
End;

Procedure TMonitorLanCarrier.NoteClosed;
Begin
  LockCarrier;
  Try
    FState := mcsClosed;
    FBoundPort := 0;
  Finally
    UnlockCarrier;
  End;
End;

Function TMonitorLanCarrier.CopyHandler: TMonitorFrameHandler;
Begin
  LockCarrier;
  Try
    Result := FHandler;
  Finally
    UnlockCarrier;
  End;
End;

Function TMonitorLanCarrier.CopySession: TMonitorSession;
Begin
  LockCarrier;
  Try
    Result := FSession;
  Finally
    UnlockCarrier;
  End;
End;

Function TMonitorLanCarrier.OutboundEmpty: Boolean;
Var
  Session: TMonitorSession;
Begin
  Session := CopySession;
  Result := Not Assigned(Session) Or Not Session.OutboxPending;
End;

Function TMonitorLanCarrier.TakeSessionFrame(Link: TMonitorLinkThread; Out Bytes: RawByteString): Boolean;
Var
  Session: TMonitorSession;
Begin
  Bytes := '';
  Result := False;
  If Not Link.ControllerForPass Then
    Exit;
  Session := TMonitorSession(Link.PassSession);
  Result := Assigned(Session) And Session.TakeOutboundFrame(Bytes);
End;

Function TMonitorLanCarrier.Start(Out ErrorText: String): Boolean;
Var
  Thread: TMonitorListenThread;
Begin
  ErrorText := '';
  Result := False;
  LockCarrier;
  Try
    If (FState = mcsListening) Or (FState = mcsConnected) Then
      Begin
        ErrorText := '';
        Result := True;
        Exit;
      End;
    If Assigned(FThread) Then
      Begin
        ErrorText := 'The monitor listener is stopping.';
        Exit;
      End;
  Finally
    UnlockCarrier;
  End;
  If FBindAddress = '' Then
    Begin
      ErrorText := 'Monitor bind address is empty.';
      StoreError(ErrorText);
      QueueMainError('bind failed bind= port=' + IntToStr(FPort) + ' ' + ErrorText);
      If GetCurrentThreadId = MainThreadID Then
        CheckSynchronize(0);
      Exit;
    End;
  If (FCertificatePath = '') Or (FKeyPath = '') Then
    Begin
      ErrorText := 'Monitor certificate file is missing.';
      StoreError(ErrorText);
      QueueMainError('bind failed bind=' + FBindAddress + ' port=' + IntToStr(FPort) + ' ' + ErrorText);
      If GetCurrentThreadId = MainThreadID Then
        CheckSynchronize(0);
      Exit;
    End;
  Thread := TMonitorListenThread.Create(FBindAddress, FPort, FCertificatePath, FKeyPath, Self);
  LockCarrier;
  Try
    FThread := Thread;
    FJoined := False;
    FState := mcsIdle;
  Finally
    UnlockCarrier;
  End;
  RTLEventWaitFor(Thread.FReady, MonitorBindWaitMs);
  If GetCurrentThreadId = MainThreadID Then
    CheckSynchronize(0);
  If Not Thread.FBindOk Then
    Begin
      If Thread.FErrorText <> '' Then
        ErrorText := Thread.FErrorText
      Else
        ErrorText := 'Could not bind the monitor listener.';
      StoreError(ErrorText);
      Stop;
      Exit;
    End;
  Result := True;
  LogMonitor(1, 'listen start bind=' + FBindAddress + ' port=' + IntToStr(BoundPort));
End;

Procedure TMonitorLanCarrier.Stop;
Var
  Thread: TMonitorListenThread;
  Join: Boolean;
Begin
  LockCarrier;
  Try
    Thread := FThread;
    Join := Assigned(Thread) And (Not FJoined);
    If Join Then
      FJoined := True;
  Finally
    UnlockCarrier;
  End;
  If Not Assigned(Thread) Then
    Begin
      NoteClosed;
      Exit;
    End;
  { Unix TThread.WaitFor joins the pthread. A second join is an access violation. }
  If Not Join Then
    Exit;
  { TInetServer is owned by the listen thread. StopAccepting here races that thread freeing the
    socket: FAccepting is cleared first, the accept loop exits, and Abort then uses a freed object. }
  Thread.Terminate;
  If GetCurrentThreadId = Thread.ThreadID Then
    Begin
      LockCarrier;
      Try
        FJoined := False;
      Finally
        UnlockCarrier;
      End;
      Exit;
    End;
  Thread.WaitFor;
  LogMonitor(1, 'listen stop bind=' + FBindAddress + ' port=' + IntToStr(Thread.BoundPort));
  LockCarrier;
  Try
    If FThread = Thread Then
      FreeAndNil(FThread);
    FJoined := False;
    FState := mcsClosed;
    FBoundPort := 0;
  Finally
    UnlockCarrier;
  End;
End;

Function TMonitorLanCarrier.Send(Const Frame: TMonitorFrame; Out ErrorText: String): Boolean;
Var
  Session: TMonitorSession;
Begin
  ErrorText := '';
  Result := False;
  LockCarrier;
  Try
    If (FState = mcsIdle) Or (FState = mcsClosed) Then
      Begin
        ErrorText := 'The monitor listener is not running.';
        Exit;
      End;
  Finally
    UnlockCarrier;
  End;
  Session := CopySession;
  If Not Assigned(Session) Then
    Begin
      ErrorText := 'No session is attached.';
      Exit;
    End;
  Result := Session.TryQueueHostJson(Frame.Json);
  If Not Result Then
    ErrorText := 'The frame was not queued.';
End;

Function TMonitorLanCarrier.State: TMonitorCarrierState;
Begin
  LockCarrier;
  Try
    Result := FState;
  Finally
    UnlockCarrier;
  End;
End;

Procedure TMonitorLanCarrier.SetFrameHandler(Handler: TMonitorFrameHandler);
Begin
  LockCarrier;
  Try
    FHandler := Handler;
  Finally
    UnlockCarrier;
  End;
End;

Procedure TMonitorLanCarrier.AttachSession(Session: TMonitorSession);
Var
  Previous: TMonitorSession;
Begin
  LockCarrier;
  Try
    Previous := FSession;
    FSession := Session;
  Finally
    UnlockCarrier;
  End;
  If Assigned(Previous) And (Previous <> Session) Then
    Previous.NoteLinkPulls(False);
  If Assigned(Session) Then
    Session.NoteLinkPulls(True);
End;

Function TMonitorLanCarrier.BoundPort: Word;
Begin
  LockCarrier;
  Try
    Result := FBoundPort;
  Finally
    UnlockCarrier;
  End;
End;

Procedure TMonitorLanCarrier.WakeController;
Var
  Link: TMonitorLinkThread;
Begin
  LockCarrier;
  Try
    Link := FController;
    If Assigned(Link) Then
      Link.Retain;
  Finally
    UnlockCarrier;
  End;
  If Not Assigned(Link) Then
    Exit;
  Try
    Link.Wake;
  Finally
    Link.Release;
  End;
End;

Procedure TMonitorLanCarrier.ForgetController(Link: TMonitorLinkThread);
Begin
  LockCarrier;
  Try
    If FController = Link Then
      FController := Nil;
  Finally
    UnlockCarrier;
  End;
End;

Procedure TMonitorLanCarrier.DetachController;
Var
  Had: Boolean;
  Session: TMonitorSession;
Begin
  LockCarrier;
  Try
    Had := Assigned(FController);
    FController := Nil;
  Finally
    UnlockCarrier;
  End;
  If Not Had Then
    Exit;
  Session := CopySession;
  If Assigned(Session) Then
    Begin
      Session.SetOutboundWake(Nil);
      Session.NoteSocketClosed;
    End;
  NoteControllerDropped;
End;

Function TMonitorLanCarrier.IsController(Link: TMonitorLinkThread): Boolean;
Begin
  LockCarrier;
  Try
    Result := Assigned(Link) And (FController = Link);
  Finally
    UnlockCarrier;
  End;
End;

Function TMonitorLanCarrier.BeginLinkPass(Link: TMonitorLinkThread): TObject;
Begin
  Link.PassFrameCount := 0;
  LockCarrier;
  Try
    Link.PassIsController := FController = Link;
    If Link.PassIsController Then
      Result := FSession
    Else
      Result := Nil;
  Finally
    UnlockCarrier;
  End;
  If Assigned(Result) And Link.ControllerForPass Then
    Link.PassFrameCount := TMonitorSession(Result).PrepareOutboundCount;
End;

Function TMonitorLanCarrier.OutboundPending(Link: TMonitorLinkThread): Boolean;
Begin
  Result := Link.ControllerForPass And (Link.PassFrameCount > 0);
End;

Function TMonitorLanCarrier.OutboundCount(Link: TMonitorLinkThread): Integer;
Begin
  Result := 0;
  If Link.ControllerForPass Then
    Result := Link.PassFrameCount;
End;

Procedure TMonitorLanCarrier.DeliverFrame(Link: TMonitorLinkThread; Const Frame: TMonitorFrame);
Var
  Handler: TMonitorFrameHandler;
Begin
  If Not IsController(Link) Then
    Exit;
  Handler := CopyHandler;
  If Not Assigned(Handler) Then
    Exit;
  Try
    Handler(Frame);
  Except
    On E: Exception Do
      ReportPluginException(MonitorLogArea, E);
  End;
End;

Procedure TMonitorLanCarrier.NotePartialFrame(Link: TMonitorLinkThread; Open: Boolean);
Var
  Session: TMonitorSession;
Begin
  If Not Link.ControllerForPass Then
    Exit;
  Session := TMonitorSession(Link.PassSession);
  If Assigned(Session) Then
    Session.NotePartialFrame(Open);
End;

Procedure TMonitorLanCarrier.NoteTime(Link: TMonitorLinkThread; NowMs: QWord);
Var
  Session: TMonitorSession;
Begin
  If Not Link.ControllerForPass Then
    Exit;
  Session := TMonitorSession(Link.PassSession);
  If Assigned(Session) Then
    Session.NoteTime(NowMs);
End;

Function TMonitorLanCarrier.AcceptLink(Out RejectFrame: TMonitorFrame): Boolean;
Var
  Session: TMonitorSession;
  Message: TMonitorMessage;
  ErrorText: String;
Begin
  RejectFrame.Version := MonitorFrameVersion;
  RejectFrame.Flags := 0;
  RejectFrame.Json := '';
  Session := CopySession;
  If Not Assigned(Session) Then
    Exit(True);
  Result := Session.AcceptHandshake(RejectFrame);
  If Result Or (RejectFrame.Json = '') Then
    Exit;
  { The spare busy reject is not sent. disabled still is. }
  If Not TryDecodeMonitorEnvelope(RejectFrame.Json, Message, ErrorText) Or (Message.Kind <> mmkRejected) Or
    (Message.Reason <> 'disabled') Then
    RejectFrame.Json := '';
End;

Function TMonitorLanCarrier.CloseRequested(Link: TMonitorLinkThread): Boolean;
Var
  Session: TMonitorSession;
Begin
  Result := False;
  If Not Link.ControllerForPass Then
    Exit;
  Session := TMonitorSession(Link.PassSession);
  Result := Assigned(Session) And Session.CloseRequested;
End;

Function TMonitorLanCarrier.PrepareReplace(Link: TMonitorLinkThread): TMonitorLinkThread;
Begin
  Result := Nil;
  LockCarrier;
  Try
    If FController = Link Then
      Exit;
    Result := FController;
    If Assigned(Result) Then
      Result.Retain;
  Finally
    UnlockCarrier;
  End;
  If Assigned(Result) Then
    Result.StartReplace;
End;

Procedure TMonitorLanCarrier.AdoptController(Link: TMonitorLinkThread);
Var
  Session: TMonitorSession;
Begin
  LockCarrier;
  Try
    FController := Link;
  Finally
    UnlockCarrier;
  End;
  NoteConnected;
  Session := CopySession;
  If Assigned(Session) And Assigned(Link) Then
    Session.SetOutboundWake(@WakeController);
End;

Function TMonitorLanCarrier.ReleaseController(Link: TMonitorLinkThread): Boolean;
Var
  Session: TMonitorSession;
Begin
  LockCarrier;
  Try
    Result := Assigned(Link) And (FController = Link);
    If Result Then
      FController := Nil;
  Finally
    UnlockCarrier;
  End;
  If Not Result Then
    Exit;
  Session := CopySession;
  If Assigned(Session) Then
    Begin
      Session.SetOutboundWake(Nil);
      Session.NoteSocketClosed;
    End;
  NoteControllerDropped;
End;

{ TMonitorListenThread }

Constructor TMonitorListenThread.Create(Const NewBindAddress: String; NewPort: Word; Const NewCertificatePath, NewKeyPath: String;
  OwnerCarrier: TMonitorLanCarrier);
Begin
  FCarrier := OwnerCarrier;
  FBindAddress := NewBindAddress;
  FPort := NewPort;
  FCertificatePath := NewCertificatePath;
  FKeyPath := NewKeyPath;
  SetLength(FCertificateDer, 0);
  SetLength(FKeyDer, 0);
  FServer := Nil;
  FReady := RTLEventCreate;
  FSignaled := False;
  FBindOk := False;
  FErrorText := '';
  FBoundPort := 0;
  SetLength(FSlots, 0);
  FreeOnTerminate := False;
  Inherited Create(False);
End;

Destructor TMonitorListenThread.Destroy;
Begin
  StopLinks;
  ReleaseServer;
  If Assigned(FReady) Then
    RTLEventDestroy(FReady);
  FReady := Nil;
  Inherited Destroy;
End;

Procedure TMonitorListenThread.Fail(Const ErrorText: String);
Begin
  If FSignaled Then
    Exit;
  FErrorText := ErrorText;
  FBindOk := False;
  If Assigned(FCarrier) Then
    FCarrier.StoreError(ErrorText);
  QueueMainError('bind failed bind=' + FBindAddress + ' port=' + IntToStr(FPort) + ' ' + ErrorText);
  FSignaled := True;
  RTLEventSetEvent(FReady);
End;

Function DuplicateAcceptedSocket(Handle: THandle): cint;
{$IFDEF UNIX}
Begin
  Result := fpDup(Handle);
End;
{$ENDIF}
{$IFDEF WINDOWS}
Var
  Dup: THandle;
Begin
  Result := -1;
  Dup := 0;
  If DuplicateHandle(GetCurrentProcess, Handle, GetCurrentProcess, @Dup, 0, False, DUPLICATE_SAME_ACCESS) Then
    Result := cint(Dup);
End;
{$ENDIF}

Procedure TMonitorListenThread.StopLinks;
Var
  Index: Integer;
  Link: TMonitorLinkThread;
  Stream: TSocketStream;
Begin
  If Assigned(FCarrier) Then
    FCarrier.DetachController;
  For Index := 0 To High(FSlots) Do
    If Assigned(FSlots[Index].Link) Then
      Begin
        FSlots[Index].Link.Terminate;
        FSlots[Index].Link.Wake;
      End;
  For Index := 0 To High(FSlots) Do
    Begin
      Link := FSlots[Index].Link;
      Stream := FSlots[Index].Stream;
      FSlots[Index].Link := Nil;
      FSlots[Index].Stream := Nil;
      If Assigned(Link) Then
        Begin
          Link.WaitFor;
          While Link.Held Do
            Sleep(1);
          Link.Free;
        End;
      If Assigned(Stream) Then
        Try
          Stream.Free;
        Except
          On E: Exception Do
            LogMonitor(2, 'listen socket release ' + E.Message);
        End;
    End;
  SetLength(FSlots, 0);
End;

Procedure TMonitorListenThread.ReleaseServer;
Var
  ListenServer: TInetServer;
Begin
  ListenServer := FServer;
  FServer := Nil;
  If Not Assigned(ListenServer) Then
    Exit;
  ListenServer.OnConnect := Nil;
  ListenServer.OnIdle := Nil;
  ListenServer.OnConnectionDropped := Nil;
  ListenServer.OnCreateClientSocketHandler := Nil;
  Try
    ListenServer.StopAccepting(True);
  Except
    On E: Exception Do
      LogMonitor(2, 'listen stop accepting ' + E.Message);
  End;
  Try
    ListenServer.Free;
  Except
    On E: Exception Do
      LogMonitor(2, 'listen server release ' + E.Message);
  End;
End;

{$PUSH}{$HINTS OFF}
Procedure TMonitorListenThread.CreateClientHandler(Sender: TObject; Out AHandler: TSocketHandler);
Begin
  { Plain handler. SSL_accept runs on the link thread, not inside accept. }
  AHandler := TSocketHandler.Create;
End;
{$POP}

{ True when Data now belongs to a link, or has already been freed through one. HandleConnect frees Data only on False. }
Function TMonitorListenThread.Handoff(Data: TSocketStream): Boolean;
Var
  Dup: cint;
  Link: TMonitorLinkThread;
  Index: Integer;
Begin
  Result := False;
  If Not Assigned(Data) Then
    Exit;
  SetAcceptedHandleNonBlocking(Data.Handle);
  EnableAcceptedKeepAlive(Data.Handle);
  Dup := DuplicateAcceptedSocket(Data.Handle);
  If Dup < 0 Then
    Begin
      LogMonitor(2, 'could not detach the accepted socket bind=' + FBindAddress + ' port=' + IntToStr(FBoundPort));
      Exit;
    End;
  Link := TMonitorLinkThread.Create(Dup, True, FCertificateDer, FKeyDer, FCarrier, FBindAddress, FBoundPort);
  If Not Link.WakeOpen Then
    Begin
      Link.Free;
      LogMonitor(3, 'wake handle failed bind=' + FBindAddress + ' port=' + IntToStr(FBoundPort));
      Exit;
    End;
  { The stream is handed over before Start. A link that finishes at once releases it in Execute's Finally, so
    starting first could leave it unowned. From here the link owns Data, and Result stays True on every path:
    a failure below frees the link, which releases Data. }
  Link.TakeAccepted(Data);
  Result := True;
  Index := -1;
  Try
    Index := Length(FSlots);
    SetLength(FSlots, Index + 1);
    FSlots[Index].Stream := Nil;
    FSlots[Index].Link := Link;
    Link.Start;
  Except
    On E: Exception Do
      Begin
        ReportPluginException(MonitorLogArea, E);
        { The slot is the last one, and only this thread changes FSlots. Drop it if it was added. }
        If (Index >= 0) And (Index = High(FSlots)) And (FSlots[Index].Link = Link) Then
          SetLength(FSlots, Index);
        Try
          Link.Free;
        Except
          On FreeError: Exception Do
            LogMonitor(2, 'link release after failed hand-off ' + FreeError.Message);
        End;
      End;
  End;
End;

Procedure TMonitorListenThread.HandleConnect(Sender: TObject; Data: TSocketStream);
Var
  Owned: Boolean;
Begin
  If Not Assigned(Data) Or (Sender = Nil) Then
    Exit;
  Owned := False;
  Try
    Owned := Handoff(Data);
  Except
    On E: Exception Do
      ReportPluginException(MonitorLogArea, E);
  End;
  If Not Owned Then
    Data.Free;
End;

{$PUSH}{$HINTS OFF}
Procedure TMonitorListenThread.HandleDropped(Sender: TObject; Data: TSocketStream);
Begin
  { StartAccepting already closed this socket. OnConnect is not called.
    Closing it here must not call StopAccepting. }
  If Assigned(Data) Then
    LogMonitor(2, 'connection dropped bind=' + FBindAddress + ' port=' + IntToStr(FBoundPort) + ' bytes=0');
End;
{$POP}

Procedure TMonitorListenThread.ReapFinished;
Var
  Index: Integer;
  Link: TMonitorLinkThread;
  Stream: TSocketStream;
Begin
  Index := High(FSlots);
  While Index >= 0 Do
    Begin
      Link := FSlots[Index].Link;
      If Not Assigned(Link) Or Not Link.Finished Then
        Dec(Index)
      Else
        Begin
          Link.WaitFor;
          If Assigned(FCarrier) Then
            FCarrier.ForgetController(Link);
          While Link.Held Do
            Sleep(1);
          Stream := FSlots[Index].Stream;
          If Index < High(FSlots) Then
            FSlots[Index] := FSlots[High(FSlots)];
          SetLength(FSlots, Length(FSlots) - 1);
          Link.Free;
          If Assigned(Stream) Then
            Try
              Stream.Free;
            Except
              On E: Exception Do
                LogMonitor(2, 'listen socket release ' + E.Message);
            End;
          If Index > High(FSlots) Then
            Index := High(FSlots);
        End;
    End;
End;

Procedure TMonitorListenThread.HandleIdle(Sender: TObject);
Begin
  If Terminated Then
    Begin
      If Assigned(FServer) Then
        FServer.StopAccepting(True);
      Exit;
    End;
  If Sender = Nil Then
    Exit;
  Try
    ReapFinished;
  Except
    On E: Exception Do
      ReportPluginException(MonitorLogArea, E);
  End;
End;

Procedure TMonitorListenThread.Execute;
Var
  LoadError: String;
Begin
  Try
    Try
      If Not LoadMonitorDerFile(FCertificatePath, FCertificateDer, LoadError) Then
        Begin
          Fail(LoadError);
          Exit;
        End;
      If Not LoadMonitorDerFile(FKeyPath, FKeyDer, LoadError) Then
        Begin
          Fail(LoadError);
          Exit;
        End;
      If Not EnsureOpenSSLReady(LoadError) Then
        Begin
          Fail(LoadError);
          Exit;
        End;
      FServer := TInetServer.Create(FBindAddress, FPort);
      FServer.ReuseAddress := True;
      FServer.AcceptIdleTimeOut := MonitorAcceptIdleMs;
      { Lifetime accept count. -1 keeps accepting. Not the simultaneous cap. }
      FServer.MaxConnections := -1;
      FServer.MaxSimultaneousConnections := MonitorSimultaneousCap;
      FServer.OnConnect := @HandleConnect;
      FServer.OnIdle := @HandleIdle;
      FServer.OnConnectionDropped := @HandleDropped;
      FServer.OnCreateClientSocketHandler := @CreateClientHandler;
      FServer.Bind;
      FBoundPort := MonitorKernelPort(FServer);
      If FBoundPort = 0 Then
        Begin
          Fail('Could not read the monitor listen port.');
          Exit;
        End;
      FServer.Listen;
      If Assigned(FCarrier) Then
        FCarrier.NoteListening(FBoundPort);
      FBindOk := True;
      FSignaled := True;
      RTLEventSetEvent(FReady);
      If Terminated Then
        Exit;
      FServer.StartAccepting;
    Except
      On E: Exception Do
        If Not FSignaled Then
          Fail(E.Message)
        Else
          Begin
            If Assigned(FCarrier) Then
              FCarrier.StoreError(E.Message);
            QueueMainError('listen failed bind=' + FBindAddress + ' port=' + IntToStr(FBoundPort) + ' ' + E.Message);
          End;
    End;
  Finally
    StopLinks;
    ReleaseServer;
    If Assigned(FCarrier) And FBindOk Then
      FCarrier.NoteClosed;
    If Not FSignaled Then
      Fail('Monitor listener stopped.');
  End;
End;

End.
