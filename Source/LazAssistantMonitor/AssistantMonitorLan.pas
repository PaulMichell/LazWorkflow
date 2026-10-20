Unit AssistantMonitorLan;

{ Host-listens LAN carrier for monitor frames (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. The accept loop, per-socket frame
  buffer, and the locked queues are one carrier. Splitting the idle read from the
  thread would hide the single-read rule.
  Reviewed 2026-10-19: no form code and no relay class.

  Listen path is ssockets.TInetServer. TLS is opensslsockets.TOpenSSLSocketHandler.
  Reads and writes go through the public SSL: TSSL property (Read, Write, Pending,
  GetError). OpenSSL load is AssistantHttps.EnsureOpenSSLReady. Frame bytes are
  AssistantMonitorFrames. There is no relay class.

  Accepted-socket non-blocking is not SetSocketBlockingMode and not
  TSocketServer.SetNonBlocking. Those helpers do not cover the accepted handle.
  The two calls below are the helpers' own fpfcntl or ioctlsocket lines.
  The kernel port is sockets.fpGetSockName on TInetServer.FPSocket.
  TInetServer.Port is not read. Bind failures are TThread.Queue to the main thread. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, SyncObjs, ssockets, AssistantMonitorCarrier, AssistantMonitorFrames, AssistantMonitorSession;

Const
  MonitorAcceptIdleMs = 250;
  MonitorSimultaneousCap = 2;

Type
  TMonitorListenThread = Class;

  { v1 host listener. Start reports mcsListening, then mcsConnected for the
    controller socket. It never reports mcsConnecting. }
  TMonitorLanCarrier = Class(TInterfacedObject, IMonitorCarrier)
  Private
    FLock: TRTLCriticalSection;
    FThread: TMonitorListenThread;
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
    FOutboundQueue: Array Of RawByteString;
    FInboundQueue: Array Of TMonitorFrame;
    Procedure LockCarrier;
    Procedure UnlockCarrier;
    Procedure StoreError(Const ErrorText: String);
    Procedure NoteListening(BoundPort: Word);
    Procedure NoteConnected;
    Procedure NoteControllerDropped;
    Procedure NoteClosed;
    Function CopyHandler: TMonitorFrameHandler;
    Function CopySession: TMonitorSession;
    Procedure EnqueueInbound(Const Frame: TMonitorFrame);
    Function PopInbound(Out Frame: TMonitorFrame): Boolean;
    Function TakeOutbound(Out Bytes: RawByteString): Boolean;
    Function OutboundEmpty: Boolean;
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
    { Valid from a successful Start until Stop returns. Stop joins the thread. Do not WaitFor as well. }
    Property ListenThread: TMonitorListenThread Read FThread;
    Property LastError: String Read FLastError;
  End;

  { FreeOnTerminate is false. Stop joins this thread once. A second WaitFor is undefined on Unix. }
  TMonitorListenThread = Class(TThread)
  Private
    Type
      TMonitorAccepted = Record
        Stream: TSocketStream;
        Pending: RawByteString;
        Unsent: RawByteString;
        SpareFrame: RawByteString;
        HasSpareFrame: Boolean;
        FirstByteMs: QWord;
        ReadOwed: Boolean;
        WriteOwed: Boolean;
        Controller: Boolean;
        Noted: Boolean;
        CloseAfterWrite: Boolean;
        DropAfter: Boolean;
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
    FAccepted: Array Of TMonitorAccepted;
    FCloseWaitMs: QWord;
    Procedure Fail(Const ErrorText: String);
    Procedure FreeSockets;
    Procedure ReleaseServer;
    Procedure CreateClientHandler(Sender: TObject; Out AHandler: TSocketHandler);
    Procedure HandleConnect(Sender: TObject; Data: TSocketStream);
    Procedure HandleIdle(Sender: TObject);
    Procedure HandleDropped(Sender: TObject; Data: TSocketStream);
    Procedure NoteHandshake(Var Accepted: TMonitorAccepted);
    Procedure AppendPending(Var Pending: RawByteString; Buf: Pointer; Count: Integer);
    Procedure ConsumePending(Var Accepted: TMonitorAccepted);
    Function ReadOnce(Var Accepted: TMonitorAccepted): Boolean;
    Function WriteOnce(Var Accepted: TMonitorAccepted): Boolean;
    Procedure ServiceAccepted(Var Accepted: TMonitorAccepted);
    Procedure DropAccepted(Index: Integer; Const Reason: String);
    Procedure ServiceIdle;
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
  winsock2,
  {$ENDIF}
  sockets, openssl, fpopenssl, opensslsockets, AssistantHttps, AssistantMonitorCodec, AssistantMonitorTls, WorkflowLog;

Const
  MonitorReadChunk = 16384;
  MonitorOutboundCap = 32;
  MonitorBindWaitMs = 10000;

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

Function EncodeFrame(Const Json: String; Out Bytes: RawByteString): Boolean;
Var
  Status: TMonitorFrameStatus;
Begin
  Bytes := '';
  Result := (Json <> '') And TryEncodeMonitorFrame(Json, Bytes, Status);
End;

Function RetryableSyscall: Boolean;
Var
  Code: Integer;
Begin
  Code := socketerror;
  Result := Code = EsockEWOULDBLOCK;
{$IFDEF UNIX}
  Result := Result Or (Code = ESysEINTR) Or (Code = ESysEAGAIN);
{$ENDIF}
End;

{ TMonitorLanCarrier }

Constructor TMonitorLanCarrier.Create(Const BindAddress: String; Port: Integer; Const CertificatePath, KeyPath: String);
Begin
  Inherited Create;
  InitCriticalSection(FLock);
  FThread := Nil;
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
  SetLength(FOutboundQueue, 0);
  SetLength(FInboundQueue, 0);
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
    SetLength(FOutboundQueue, 0);
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
    SetLength(FOutboundQueue, 0);
    SetLength(FInboundQueue, 0);
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

Procedure TMonitorLanCarrier.EnqueueInbound(Const Frame: TMonitorFrame);
Begin
  LockCarrier;
  Try
    SetLength(FInboundQueue, Length(FInboundQueue) + 1);
    FInboundQueue[High(FInboundQueue)] := Frame;
  Finally
    UnlockCarrier;
  End;
End;

Function TMonitorLanCarrier.PopInbound(Out Frame: TMonitorFrame): Boolean;
Var
  Index: Integer;
Begin
  Frame.Version := 0;
  Frame.Flags := 0;
  Frame.Json := '';
  LockCarrier;
  Try
    Result := Length(FInboundQueue) > 0;
    If Not Result Then
      Exit;
    Frame := FInboundQueue[0];
    For Index := 0 To High(FInboundQueue) - 1 Do
      FInboundQueue[Index] := FInboundQueue[Index + 1];
    SetLength(FInboundQueue, Length(FInboundQueue) - 1);
  Finally
    UnlockCarrier;
  End;
End;

Function TMonitorLanCarrier.OutboundEmpty: Boolean;
Begin
  LockCarrier;
  Try
    Result := Length(FOutboundQueue) = 0;
  Finally
    UnlockCarrier;
  End;
End;

Function TMonitorLanCarrier.TakeOutbound(Out Bytes: RawByteString): Boolean;
Var
  Index: Integer;
Begin
  Bytes := '';
  LockCarrier;
  Try
    Result := Length(FOutboundQueue) > 0;
    If Not Result Then
      Exit;
    Bytes := FOutboundQueue[0];
    For Index := 0 To High(FOutboundQueue) - 1 Do
      FOutboundQueue[Index] := FOutboundQueue[Index + 1];
    SetLength(FOutboundQueue, Length(FOutboundQueue) - 1);
  Finally
    UnlockCarrier;
  End;
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
    SetLength(FOutboundQueue, 0);
    SetLength(FInboundQueue, 0);
  Finally
    UnlockCarrier;
  End;
End;

Function TMonitorLanCarrier.Send(Const Frame: TMonitorFrame; Out ErrorText: String): Boolean;
Var
  Bytes: RawByteString;
Begin
  ErrorText := '';
  Result := False;
  If Not EncodeFrame(Frame.Json, Bytes) Then
    Begin
      ErrorText := 'Could not encode the monitor frame.';
      Exit;
    End;
  LockCarrier;
  Try
    If (FState = mcsIdle) Or (FState = mcsClosed) Then
      Begin
        ErrorText := 'The monitor listener is not running.';
        Exit;
      End;
    If Length(FOutboundQueue) >= MonitorOutboundCap Then
      Begin
        ErrorText := 'The monitor outbound queue is full.';
        Exit;
      End;
    SetLength(FOutboundQueue, Length(FOutboundQueue) + 1);
    FOutboundQueue[High(FOutboundQueue)] := Bytes;
    Result := True;
  Finally
    UnlockCarrier;
  End;
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
Var
  Method: TMethod;
Begin
  LockCarrier;
  Try
    FHandler := Handler;
    Method := TMethod(Handler);
    If TObject(Method.Data) Is TMonitorSession Then
      FSession := TMonitorSession(Method.Data)
    Else If Not Assigned(Method.Code) Then
      FSession := Nil;
  Finally
    UnlockCarrier;
  End;
End;

Procedure TMonitorLanCarrier.AttachSession(Session: TMonitorSession);
Begin
  LockCarrier;
  Try
    FSession := Session;
  Finally
    UnlockCarrier;
  End;
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
  SetLength(FAccepted, 0);
  FCloseWaitMs := 0;
  FreeOnTerminate := False;
  Inherited Create(False);
End;

Destructor TMonitorListenThread.Destroy;
Begin
  FreeSockets;
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

Procedure TMonitorListenThread.FreeSockets;
Var
  Index: Integer;
  Stream: TSocketStream;
Begin
  For Index := 0 To High(FAccepted) Do
    Begin
      Stream := FAccepted[Index].Stream;
      FAccepted[Index].Stream := Nil;
      If Assigned(Stream) Then
        Try
          Stream.Free;
        Except
          On E: Exception Do
            LogMonitor(2, 'listen socket release ' + E.Message);
        End;
    End;
  SetLength(FAccepted, 0);
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
Var
  Handler: TMonitorTlsHandler;
Begin
  AHandler := Nil;
  Handler := TMonitorTlsHandler.Create;
  Handler.LoadHostMaterial(FCertificateDer, FKeyDer);
  AHandler := Handler;
End;
{$POP}

Procedure TMonitorListenThread.AppendPending(Var Pending: RawByteString; Buf: Pointer; Count: Integer);
Var
  StartAt: Integer;
Begin
  If (Count <= 0) Or Not Assigned(Buf) Then
    Exit;
  StartAt := Length(Pending);
  SetLength(Pending, StartAt + Count);
  Move(Buf^, Pending[StartAt + 1], Count);
End;

Procedure TMonitorListenThread.ConsumePending(Var Accepted: TMonitorAccepted);
Var
  Frame: TMonitorFrame;
  Status: TMonitorFrameStatus;
  Had, Consumed: Integer;
  Ok: Boolean;
Begin
  Had := Length(Accepted.Pending);
  Consumed := 0;
  Status := mfsNeedMore;
  Ok := True;
  While Ok And (Length(Accepted.Pending) > 0) Do
    Begin
      Ok := TryConsumeMonitorFrame(Accepted.Pending, Frame, Status);
      If Ok And Accepted.Controller And Assigned(FCarrier) Then
        Begin
          FCarrier.EnqueueInbound(Frame);
          Inc(Consumed);
        End
      Else If Ok Then
        Inc(Consumed);
    End;
  If (Not Ok) And (Status <> mfsNeedMore) And (Length(Accepted.Pending) > 0) Then
    Begin
      Accepted.DropAfter := True;
      LogMonitor(2, 'frame rejected status=' + IntToStr(Ord(Status)) + ' bytes=' + IntToStr(Length(Accepted.Pending)) +
        ' bind=' + FBindAddress + ' port=' + IntToStr(FBoundPort));
    End;
  If Length(Accepted.Pending) = 0 Then
    Begin
      If Accepted.Controller Then
        Accepted.FirstByteMs := 0;
    End
  Else If Accepted.Controller And ((Had = 0) Or (Consumed > 0) Or (Accepted.FirstByteMs = 0)) Then
    Accepted.FirstByteMs := GetTickCount64;
End;

Procedure TMonitorListenThread.NoteHandshake(Var Accepted: TMonitorAccepted);
Var
  Session: TMonitorSession;
  RejectFrame: TMonitorFrame;
  Json, Bytes: RawByteString;
  HasController, Released: Boolean;
  Index: Integer;
Begin
  If Accepted.Noted Then
    Exit;
  { A reconnect arrives while the previous socket is still the controller.
    Rejecting it as busy leaves the phone looping on Reconnecting. }
  Released := False;
  For Index := 0 To High(FAccepted) Do
    If FAccepted[Index].Controller And (FAccepted[Index].Stream <> Accepted.Stream) Then
      Begin
        FAccepted[Index].Controller := False;
        FAccepted[Index].DropAfter := True;
        Released := True;
      End;
  Session := Nil;
  If Assigned(FCarrier) Then
    Session := FCarrier.CopySession;
  If Released And Assigned(Session) Then
    Session.NoteSocketClosed;
  If Assigned(Session) Then
    Begin
      If Session.AcceptHandshake(RejectFrame) Then
        Begin
          Accepted.Controller := True;
          Accepted.Noted := True;
          If Assigned(FCarrier) Then
            FCarrier.NoteConnected;
          Exit;
        End;
      Accepted.Controller := False;
      Accepted.Noted := True;
      Accepted.CloseAfterWrite := True;
      If Accepted.FirstByteMs = 0 Then
        Accepted.FirstByteMs := GetTickCount64;
      If EncodeFrame(RejectFrame.Json, Bytes) Then
        Begin
          Accepted.SpareFrame := Bytes;
          Accepted.HasSpareFrame := True;
          LogMonitor(2, 'rejected bytes=' + IntToStr(Length(Bytes)) + ' bind=' + FBindAddress + ' port=' + IntToStr(FBoundPort));
        End;
      Exit;
    End;
  HasController := False;
  For Index := 0 To High(FAccepted) Do
    If FAccepted[Index].Controller Then
      HasController := True;
  If Not HasController Then
    Begin
      Accepted.Controller := True;
      Accepted.Noted := True;
      If Assigned(FCarrier) Then
        FCarrier.NoteConnected;
      Exit;
    End;
  Accepted.Controller := False;
  Accepted.Noted := True;
  Accepted.CloseAfterWrite := True;
  If Accepted.FirstByteMs = 0 Then
    Accepted.FirstByteMs := GetTickCount64;
  Json := EncodeMonitorRejected('spare', 'busy', MonitorCatalogueVersion, 0);
  If EncodeFrame(Json, Bytes) Then
    Begin
      Accepted.SpareFrame := Bytes;
      Accepted.HasSpareFrame := True;
      LogMonitor(2, 'rejected reason=busy bytes=' + IntToStr(Length(Bytes)) + ' bind=' + FBindAddress +
        ' port=' + IntToStr(FBoundPort));
    End;
End;

Procedure TMonitorListenThread.HandleConnect(Sender: TObject; Data: TSocketStream);
Var
  Index: Integer;
Begin
  If Not Assigned(Data) Or (Sender = Nil) Then
    Exit;
  Index := -1;
  Try
    SetLength(FAccepted, Length(FAccepted) + 1);
    Index := High(FAccepted);
    FAccepted[Index].Stream := Data;
    FAccepted[Index].Pending := '';
    FAccepted[Index].Unsent := '';
    FAccepted[Index].SpareFrame := '';
    FAccepted[Index].HasSpareFrame := False;
    FAccepted[Index].FirstByteMs := 0;
    FAccepted[Index].ReadOwed := False;
    FAccepted[Index].WriteOwed := False;
    FAccepted[Index].Controller := False;
    FAccepted[Index].Noted := False;
    FAccepted[Index].CloseAfterWrite := False;
    FAccepted[Index].DropAfter := False;
    { IOTimeout stays 0. A positive timeout would turn WANT_READ into a close inside Recv. }
    NoteHandshake(FAccepted[Index]);
  Except
    On E: Exception Do
      Begin
        ReportPluginException(MonitorLogArea, E);
        If Index >= 0 Then
          FAccepted[Index].DropAfter := True;
      End;
  End;
  { Registration has returned. The accepted handle is still blocking until these calls. }
  SetAcceptedHandleNonBlocking(Data.Handle);
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

Function TMonitorListenThread.ReadOnce(Var Accepted: TMonitorAccepted): Boolean;
Var
  Handler: TOpenSSLSocketHandler;
  Buf: Array[0..MonitorReadChunk - 1] Of Byte;
  Count, Err: Integer;
  ReadDue: Boolean;
Begin
  Result := True;
  If Not Assigned(Accepted.Stream) Or Not Assigned(Accepted.Stream.Handler) Then
    Begin
      Accepted.DropAfter := True;
      Exit;
    End;
  If Not (Accepted.Stream.Handler Is TOpenSSLSocketHandler) Then
    Begin
      Accepted.DropAfter := True;
      Exit;
    End;
  Handler := TOpenSSLSocketHandler(Accepted.Stream.Handler);
  If Not Assigned(Handler.SSL) Then
    Begin
      Accepted.DropAfter := True;
      Exit;
    End;
  { A write that returned WANT_READ must be retried before another SSL.Read. }
  If Accepted.WriteOwed Then
    Exit;
  { Or does not skip CanRead. Pending does not replace the TCP poll. }
  ReadDue := Accepted.ReadOwed Or (Handler.SSL.Pending > 0) Or Handler.CanRead(0);
  If Not ReadDue Then
    Exit;
  Count := Handler.SSL.Read(@Buf[0], SizeOf(Buf));
  Err := Handler.SSL.GetError(Count);
  If Count > 0 Then
    Begin
      AppendPending(Accepted.Pending, @Buf[0], Count);
      Accepted.ReadOwed := False;
      ConsumePending(Accepted);
      Exit;
    End;
  If (Err = SSL_ERROR_WANT_READ) Or (Err = SSL_ERROR_WANT_WRITE) Then
    Begin
      Accepted.ReadOwed := True;
      Exit;
    End;
  If (Err = SSL_ERROR_SYSCALL) And RetryableSyscall Then
    Begin
      Accepted.ReadOwed := True;
      Exit;
    End;
  Accepted.DropAfter := True;
  Result := False;
End;

Function TMonitorListenThread.WriteOnce(Var Accepted: TMonitorAccepted): Boolean;
Var
  Handler: TOpenSSLSocketHandler;
  Count, Err: Integer;
  Took: RawByteString;
Begin
  Result := True;
  If Accepted.DropAfter Or Not Assigned(Accepted.Stream) Or Not Assigned(Accepted.Stream.Handler) Then
    Exit;
  If Not (Accepted.Stream.Handler Is TOpenSSLSocketHandler) Then
    Exit;
  Handler := TOpenSSLSocketHandler(Accepted.Stream.Handler);
  If Not Assigned(Handler.SSL) Then
    Exit;
  { An owed read must be retried before a new SSL.Write. }
  If Accepted.ReadOwed Then
    Exit;
  If Accepted.Unsent = '' Then
    Begin
      If Accepted.HasSpareFrame Then
        Begin
          Accepted.Unsent := Accepted.SpareFrame;
          Accepted.SpareFrame := '';
          Accepted.HasSpareFrame := False;
        End
      Else If Accepted.Controller And Assigned(FCarrier) And FCarrier.TakeOutbound(Took) Then
        Accepted.Unsent := Took
      Else
        Exit;
    End;
  If Accepted.Unsent = '' Then
    Exit;
  Count := Handler.SSL.Write(@Accepted.Unsent[1], Length(Accepted.Unsent));
  Err := Handler.SSL.GetError(Count);
  If Count > 0 Then
    Begin
      If Count > Length(Accepted.Unsent) Then
        Count := Length(Accepted.Unsent);
      Delete(Accepted.Unsent, 1, Count);
      Accepted.WriteOwed := False;
      Exit;
    End;
  If (Err = SSL_ERROR_WANT_READ) Or (Err = SSL_ERROR_WANT_WRITE) Then
    Begin
      Accepted.WriteOwed := True;
      Exit;
    End;
  If (Err = SSL_ERROR_SYSCALL) And RetryableSyscall Then
    Begin
      Accepted.WriteOwed := True;
      Exit;
    End;
  Accepted.DropAfter := True;
  Result := False;
End;

Procedure TMonitorListenThread.ServiceAccepted(Var Accepted: TMonitorAccepted);
Var
  NowMs: QWord;
  Session: TMonitorSession;
Begin
  If Accepted.DropAfter Then
    Exit;
  If Not Accepted.Noted Then
    NoteHandshake(Accepted);
  ReadOnce(Accepted);
  WriteOnce(Accepted);
  NowMs := GetTickCount64;
  If (Accepted.FirstByteMs <> 0) And (NowMs >= Accepted.FirstByteMs + MonitorPartialFrameMs) Then
    Begin
      Accepted.DropAfter := True;
      LogMonitor(2, 'partial frame timeout bytes=' + IntToStr(Length(Accepted.Pending)) + ' bind=' + FBindAddress +
        ' port=' + IntToStr(FBoundPort));
    End;
  If Accepted.Controller And Assigned(FCarrier) Then
    Begin
      Session := FCarrier.CopySession;
      If Assigned(Session) Then
        Session.NotePartialFrame((Accepted.FirstByteMs <> 0) And (Length(Accepted.Pending) > 0) And (Not Accepted.DropAfter));
    End;
  If Accepted.CloseAfterWrite And (Not Accepted.WriteOwed) And (Accepted.Unsent = '') And (Not Accepted.HasSpareFrame) Then
    Accepted.DropAfter := True;
End;

Procedure TMonitorListenThread.DropAccepted(Index: Integer; Const Reason: String);
Var
  Stream: TSocketStream;
  WasController: Boolean;
  PendingBytes: Integer;
  Session: TMonitorSession;
Begin
  If (Index < 0) Or (Index > High(FAccepted)) Then
    Exit;
  WasController := FAccepted[Index].Controller;
  PendingBytes := Length(FAccepted[Index].Pending);
  Stream := FAccepted[Index].Stream;
  FAccepted[Index].Stream := Nil;
  If Index < High(FAccepted) Then
    FAccepted[Index] := FAccepted[High(FAccepted)];
  SetLength(FAccepted, Length(FAccepted) - 1);
  If Assigned(Stream) Then
    Stream.Free;
  LogMonitor(1, 'disconnect bind=' + FBindAddress + ' port=' + IntToStr(FBoundPort) + ' bytes=' + IntToStr(PendingBytes) +
    ' ' + Reason);
  If Not WasController Then
    Exit;
  FCloseWaitMs := 0;
  If Assigned(FCarrier) Then
    Begin
      Session := FCarrier.CopySession;
      If Assigned(Session) Then
        Session.NoteSocketClosed;
      FCarrier.NoteControllerDropped;
    End;
End;

Procedure TMonitorListenThread.ServiceIdle;
Var
  Index: Integer;
  NowMs: QWord;
  Session: TMonitorSession;
  Handler: TMonitorFrameHandler;
  Frame: TMonitorFrame;
  Controller: Integer;
  WaitingClose: Boolean;
Begin
  For Index := 0 To High(FAccepted) Do
    ServiceAccepted(FAccepted[Index]);
  Handler := Nil;
  If Assigned(FCarrier) Then
    Handler := FCarrier.CopyHandler;
  If Assigned(Handler) And Assigned(FCarrier) Then
    While FCarrier.PopInbound(Frame) Do
      Try
        Handler(Frame);
      Except
        On E: Exception Do
          ReportPluginException(MonitorLogArea, E);
      End;
  Session := Nil;
  If Assigned(FCarrier) Then
    Session := FCarrier.CopySession;
  If Assigned(Session) Then
    Session.NoteTime(GetTickCount64);
  NowMs := GetTickCount64;
  Controller := -1;
  For Index := 0 To High(FAccepted) Do
    If FAccepted[Index].Controller Then
      Controller := Index;
  WaitingClose := Assigned(Session) And Session.CloseRequested And (Controller >= 0);
  If WaitingClose And (FCloseWaitMs = 0) Then
    FCloseWaitMs := NowMs;
  If Not WaitingClose Then
    FCloseWaitMs := 0;
  If WaitingClose And (FCloseWaitMs <> 0) And (NowMs >= FCloseWaitMs + MonitorPartialFrameMs) Then
    FAccepted[Controller].DropAfter := True;
  If WaitingClose And (Not FAccepted[Controller].WriteOwed) And (FAccepted[Controller].Unsent = '') And
    Assigned(FCarrier) And FCarrier.OutboundEmpty Then
    FAccepted[Controller].DropAfter := True;
  Index := High(FAccepted);
  While Index >= 0 Do
    Begin
      If FAccepted[Index].DropAfter Then
        DropAccepted(Index, 'closed')
      Else
        Dec(Index);
      If Index > High(FAccepted) Then
        Index := High(FAccepted);
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
    ServiceIdle;
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
    FreeSockets;
    ReleaseServer;
    If Assigned(FCarrier) And FBindOk Then
      FCarrier.NoteClosed;
    If Not FSignaled Then
      Fail('Monitor listener stopped.');
  End;
End;

End.
