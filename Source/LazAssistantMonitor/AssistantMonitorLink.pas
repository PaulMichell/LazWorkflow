Unit AssistantMonitorLink;

{ One monitor link thread per accepted socket (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. The handshake, the poll loop,
  and the one-frame write quantum are one thread. Splitting them would hide
  the owed-read rule and the wake-handle lifetime.
  Reviewed 2026-11-07: no form code and no second connection inside this thread.

  The listen thread accepts and stops. This thread owns the SSL object, including
  a non-blocking SSL_accept under the 10 s handshake deadline. It waits on the
  socket and a wake handle together: the read end of an fpPipe on Unix, or a
  loopback UDP pair with select on Windows. TMonitorOutbox.OnWake writes one
  byte to that handle, so a queued frame wakes this thread in the same turn.
  Write interest is requested only while a frame is ready or a write is owed.
  Each wake reads until SSL_ERROR_WANT_READ, hands complete frames to the session,
  then writes one frame or until the socket would block. An owed read is retried
  before a new write. A partial write keeps its unsent tail across WANT_WRITE.
  Heartbeat and partial-frame deadlines are the poll timeout. A later handshake
  does not share this thread, so it cannot delay frames already in flight.
  A new controller asks this thread to queue bye with reason replaced, flush for
  at most 500 ms, and close. The session then resets as on a socket close.

  Cross-thread fields (plan item 3.3 of Documents/Plan-20261105-130659.md):
  another link's thread calls StartReplace, Retain, Release, Held and
  WaitRetired. ReplaceFlag, ByeState, RetiredFlag and Refs are read and written
  only through Interlocked calls, which are full barriers. ReplaceUntil is
  written once, by the caller that claims ReplaceFlag, before the flag is
  published; this thread reads it only after it sees the flag. So it needs no
  64-bit atomic, and a 32-bit target cannot read half of it. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}
{$IFDEF DEBUG}
  {$ASSERTIONS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, SyncObjs, ctypes, AssistantMonitorFrames, AssistantMonitorOutbox;

Const
  MonitorReplaceFlushMs = 500;

Type
  TMonitorLinkThread = Class;

  { The listen carrier implements this. The link keeps a raw reference, not an interface. }
  TMonitorLinkHost = Class(TInterfacedObject)
  Public
    Function IsController(Link: TMonitorLinkThread): Boolean; Virtual; Abstract;
    Function BeginLinkPass(Link: TMonitorLinkThread): TObject; Virtual;
    Function TakeSessionFrame(Link: TMonitorLinkThread; Out Bytes: RawByteString): Boolean; Virtual; Abstract;
    Function OutboundPending(Link: TMonitorLinkThread): Boolean; Virtual; Abstract;
    Function OutboundCount(Link: TMonitorLinkThread): Integer; Virtual; Abstract;
    Procedure DeliverFrame(Link: TMonitorLinkThread; Const Frame: TMonitorFrame); Virtual; Abstract;
    Procedure NotePartialFrame(Link: TMonitorLinkThread; Open: Boolean); Virtual; Abstract;
    Procedure NoteTime(Link: TMonitorLinkThread; NowMs: QWord); Virtual; Abstract;
    Function AcceptLink(Out RejectFrame: TMonitorFrame): Boolean; Virtual; Abstract;
    Function CloseRequested(Link: TMonitorLinkThread): Boolean; Virtual; Abstract;
    { Retains the current controller, asks it to flush bye, and returns it. Nil if none. }
    Function PrepareReplace(Link: TMonitorLinkThread): TMonitorLinkThread; Virtual; Abstract;
    Procedure AdoptController(Link: TMonitorLinkThread); Virtual; Abstract;
    { True when this link was still the controller and the session was reset. }
    Function ReleaseController(Link: TMonitorLinkThread): Boolean; Virtual; Abstract;
  End;

  { FreeOnTerminate is false. The listen thread joins it once. }
  TMonitorLinkThread = Class(TThread)
  Private
    Host: TMonitorLinkHost;
    SocketHandle: cint;
    OwnsSocket: Boolean;
    WakeRead: cint;
    WakeWrite: cint;
    CertificateDer: TBytes;
    KeyDer: TBytes;
    BindAddress: String;
    BoundPort: Word;
    Outbox: TMonitorOutbox;
    Pending: RawByteString;
    Unsent: RawByteString;
    ReadOwed: Boolean;
    WriteOwed: Boolean;
    ReadWantsWrite: Boolean;
    WriteWantsWrite: Boolean;
    ReadAgain: Boolean;
    FrameTakenThisPass: Boolean;
    ControllerLink: Boolean;
    Adopted: Boolean;
    DropLink: Boolean;
    { 0 not replacing, 1 claimed while ReplaceUntil is written, 2 replacing. Interlocked only. }
    ReplaceFlag: LongInt;
    { 0 until the replace bye is queued, then 1. Interlocked only. }
    ByeState: LongInt;
    ByeArmed: Boolean;
    ByeSent: Boolean;
    { Written once before ReplaceFlag becomes 2. Read only after Replacing is True. }
    ReplaceUntil: QWord;
    HandshakeStart: QWord;
    PartialSince: QWord;
    CloseSince: QWord;
    DropReason: String;
    FinishedFlag: LongInt;
    { Interlocked only. Never below zero. }
    Refs: LongInt;
    Retired: PRTLEvent;
    { 1 once the link has retired. Interlocked only. }
    RetiredFlag: LongInt;
    Shut: Boolean;
    Ssl: TObject;
    SslContext: TObject;
    AcceptedStream: TObject;
    Procedure OutboxWake;
    Procedure ReleaseAccepted;
    Procedure OpenWake;
    Procedure CloseWake;
    Procedure DrainWake;
    Procedure ShutdownLink;
    Procedure SignalRetired;
    Procedure QueueReplaceBye;
    Function Replacing: Boolean;
    Function ByeQueued: Boolean;
    Function BuildSsl: Boolean;
    Function Handshake: Boolean;
    Procedure BecomeController;
    Procedure SendReject(Const Reject: TMonitorFrame);
    Function PollWait(TimeoutMs: Integer; WantWrite: Boolean): Boolean;
    Function NextTimeout: Integer;
    Function FrameReady: Boolean;
    Function WantsWrite(Ready: Boolean): Boolean;
    Function TakeFrame(Out Bytes: RawByteString): Boolean;
    Procedure AppendPending(Var Buffer: RawByteString; Buf: Pointer; Count: Integer);
    Procedure ConsumePending;
    Procedure DrainReads;
    Procedure WriteQuantum;
    Procedure ServiceOnce;
    Procedure CheckDeadlines(Ready: Boolean);
    Procedure RunLink;
  Public
    { Borrowed session, valid only on this link thread during its current pass. }
    PassSession: TObject;
    PassFrameCount: Integer;
    PassIsController: Boolean;
    Function ControllerForPass: Boolean;
    Constructor Create(NewSocket: cint; NewOwnsSocket: Boolean; Const NewCertificateDer, NewKeyDer: TBytes;
      NewHost: TMonitorLinkHost; Const NewBindAddress: String; NewPort: Word);
    Destructor Destroy; Override;
    Procedure Wake;
    Procedure TakeAccepted(Stream: TObject);
    Procedure Retain;
    Procedure Release;
    Function Held: Boolean;
    Function Finished: Boolean;
    Function WakeOpen: Boolean;
    { Called from the new controller's thread, never from this link's own thread. }
    Procedure StartReplace;
    Function WaitRetired(TimeoutMs: Integer): Boolean;
  Protected
    Procedure Execute; Override;
  End;

Implementation

Uses
  {$IFDEF UNIX}
  BaseUnix,
  {$ENDIF}
  {$IFDEF WINDOWS}
  winsock2,
  {$ENDIF}
  sockets, openssl, fpopenssl, AssistantMonitorCodec, AssistantMonitorSession, AssistantMonitorTls,
  WorkflowLog;

Const
  MonitorReadChunk = 16384;
  MonitorLinkReadCap = 64;
  MonitorTls12Version = $0303;
  SslVerifyNone = 0;
  ReplaceIdle = 0;
  ReplaceClaimed = 1;
  ReplacePublished = 2;

Procedure LogLink(Level: Integer; Const Text: String);
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

Function Lesser(Left, Right: Integer): Integer;
Begin
  If Left < Right Then
    Result := Left
  Else
    Result := Right;
End;

Function RemainingMs(NowMs, Deadline: QWord): Integer;
Begin
  If NowMs >= Deadline Then
    Exit(1);
  If Deadline - NowMs > QWord(High(Integer)) Then
    Exit(High(Integer));
  Result := Integer(Deadline - NowMs);
  If Result < 1 Then
    Result := 1;
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

Function EncodeFrame(Const Json: String; Out Bytes: RawByteString): Boolean;
Var
  Status: TMonitorFrameStatus;
Begin
  Bytes := '';
  Result := (Json <> '') And TryEncodeMonitorFrame(Json, Bytes, Status);
End;

Procedure SetHandleNonBlocking(Handle: cint);
{$IFDEF UNIX}
Var
  Flags: cint;
{$ENDIF}
{$IFDEF WINDOWS}
Var
  NonBlock: u_long;
{$ENDIF}
Begin
  If Handle < 0 Then
    Exit;
{$IFDEF UNIX}
  Flags := fpfcntl(Handle, F_GETFL, 0);
  If Flags >= 0 Then
    fpfcntl(Handle, F_SETFL, Flags Or O_NONBLOCK);
{$ENDIF}
{$IFDEF WINDOWS}
  NonBlock := 1;
  ioctlsocket(Handle, Longint(FIONBIO), @NonBlock);
{$ENDIF}
End;

Constructor TMonitorLinkThread.Create(NewSocket: cint; NewOwnsSocket: Boolean; Const NewCertificateDer, NewKeyDer: TBytes;
  NewHost: TMonitorLinkHost; Const NewBindAddress: String; NewPort: Word);
Begin
  Host := NewHost;
  SocketHandle := NewSocket;
  OwnsSocket := NewOwnsSocket;
  WakeRead := -1;
  WakeWrite := -1;
  CertificateDer := NewCertificateDer;
  KeyDer := NewKeyDer;
  BindAddress := NewBindAddress;
  BoundPort := NewPort;
  Outbox := Nil;
  Pending := '';
  Unsent := '';
  ReadOwed := False;
  WriteOwed := False;
  ReadWantsWrite := False;
  WriteWantsWrite := False;
  ReadAgain := False;
  ControllerLink := False;
  Adopted := False;
  DropLink := False;
  ReplaceFlag := ReplaceIdle;
  ByeState := 0;
  ByeArmed := False;
  ByeSent := False;
  ReplaceUntil := 0;
  HandshakeStart := 0;
  PartialSince := 0;
  CloseSince := 0;
  DropReason := '';
  FinishedFlag := 0;
  Refs := 1;
  Retired := Nil;
  RetiredFlag := 0;
  Shut := False;
  Ssl := Nil;
  SslContext := Nil;
  AcceptedStream := Nil;
  Retired := RTLEventCreate;
  Outbox := TMonitorOutbox.Create;
  Outbox.OnWake := @OutboxWake;
  OpenWake;
  FreeOnTerminate := False;
  Inherited Create(True);
End;

Destructor TMonitorLinkThread.Destroy;
Begin
  If Assigned(Outbox) Then
    Outbox.OnWake := Nil;
  FreeAndNil(Outbox);
  ShutdownLink;
  ReleaseAccepted;
  CloseWake;
  If Assigned(Retired) Then
    RTLEventDestroy(Retired);
  Retired := Nil;
  Inherited Destroy;
End;

Procedure CloseIo(Handle: cint);
Begin
  If Handle < 0 Then
    Exit;
{$IFDEF UNIX}
  fpClose(Handle);
{$ELSE}
  CloseSocket(Handle);
{$ENDIF}
End;

Procedure TMonitorLinkThread.Retain;
Begin
  InterlockedIncrement(Refs);
End;

Procedure TMonitorLinkThread.Release;
Var
  Seen: LongInt;
Begin
  { Compare-and-swap keeps the old rule: an extra release does not take the count below zero. }
  Repeat
    Seen := InterlockedExchangeAdd(Refs, 0);
    If Seen <= 0 Then
      Exit;
  Until InterlockedCompareExchange(Refs, Seen - 1, Seen) = Seen;
End;

Function TMonitorLinkThread.Held: Boolean;
Begin
  Result := InterlockedExchangeAdd(Refs, 0) > 1;
End;

Function TMonitorLinkThread.Finished: Boolean;
Begin
  Result := InterlockedExchangeAdd(FinishedFlag, 0) <> 0;
End;

Function TMonitorLinkThread.WakeOpen: Boolean;
Begin
  Result := (WakeRead >= 0) And (WakeWrite >= 0);
End;

Procedure TMonitorLinkThread.OutboxWake;
Begin
  Wake;
End;

Procedure TMonitorLinkThread.OpenWake;
{$IFDEF UNIX}
Var
  Ends: TFilDes;
{$ENDIF}
{$IFDEF WINDOWS}
Var
  First, Second: cint;
  Addr, Peer: TSockAddr;
  Len: TSockLen;
{$ENDIF}
Begin
  WakeRead := -1;
  WakeWrite := -1;
{$IFDEF UNIX}
  Ends[0] := -1;
  Ends[1] := -1;
  If fpPipe(Ends) <> 0 Then
    Exit;
  WakeRead := Ends[0];
  WakeWrite := Ends[1];
  SetHandleNonBlocking(WakeRead);
  SetHandleNonBlocking(WakeWrite);
{$ENDIF}
{$IFDEF WINDOWS}
  First := fpSocket(AF_INET, SOCK_DGRAM, 0);
  Second := fpSocket(AF_INET, SOCK_DGRAM, 0);
  If (First < 0) Or (Second < 0) Then
    Begin
      If First >= 0 Then
        CloseSocket(First);
      If Second >= 0 Then
        CloseSocket(Second);
      Exit;
    End;
  Addr := Default(TSockAddr);
  Addr.sin_family := AF_INET;
  Addr.sin_port := 0;
  Addr.sin_addr.s_addr := htonl($7F000001);
  If (fpBind(First, @Addr, SizeOf(Addr)) <> 0) Or (fpBind(Second, @Addr, SizeOf(Addr)) <> 0) Then
    Begin
      CloseSocket(First);
      CloseSocket(Second);
      Exit;
    End;
  Len := SizeOf(Peer);
  Peer := Default(TSockAddr);
  If (fpGetSockName(Second, @Peer, @Len) <> 0) Or (fpConnect(First, @Peer, Len) <> 0) Then
    Begin
      CloseSocket(First);
      CloseSocket(Second);
      Exit;
    End;
  Len := SizeOf(Peer);
  If (fpGetSockName(First, @Peer, @Len) <> 0) Or (fpConnect(Second, @Peer, Len) <> 0) Then
    Begin
      CloseSocket(First);
      CloseSocket(Second);
      Exit;
    End;
  SetHandleNonBlocking(First);
  SetHandleNonBlocking(Second);
  WakeRead := Second;
  WakeWrite := First;
{$ENDIF}
End;

Procedure TMonitorLinkThread.CloseWake;
Begin
  CloseIo(WakeRead);
  If WakeWrite <> WakeRead Then
    CloseIo(WakeWrite);
  WakeRead := -1;
  WakeWrite := -1;
End;

Procedure TMonitorLinkThread.DrainWake;
Var
  Buf: Array[0..31] Of Byte;
  Count: Integer;
Begin
  If WakeRead < 0 Then
    Exit;
  Buf[0] := 0;
  Repeat
{$IFDEF UNIX}
    Count := fpRead(WakeRead, Buf, SizeOf(Buf));
{$ELSE}
    Count := fpRecv(WakeRead, @Buf[0], SizeOf(Buf), 0);
{$ENDIF}
  Until Count <= 0;
End;

Procedure TMonitorLinkThread.TakeAccepted(Stream: TObject);
Begin
  AcceptedStream := Stream;
End;

Procedure TMonitorLinkThread.ReleaseAccepted;
Var
  Stream: TObject;
Begin
  Stream := AcceptedStream;
  AcceptedStream := Nil;
  If Not Assigned(Stream) Then
    Exit;
  Try
    Stream.Free;
  Except
    On E: Exception Do
      LogLink(2, 'accepted socket release ' + E.Message);
  End;
End;

Procedure TMonitorLinkThread.Wake;
Var
  Mark: Byte;
Begin
  If WakeWrite < 0 Then
    Exit;
  Mark := 1;
{$IFDEF UNIX}
  If fpWrite(WakeWrite, Mark, 1) < 0 Then
    Exit;
{$ELSE}
  If fpSend(WakeWrite, @Mark, 1, 0) < 0 Then
    Exit;
{$ENDIF}
End;

Procedure TMonitorLinkThread.ShutdownLink;
Var
  SocketSsl: TSSL;
  Context: TSSLContext;
Begin
  If Shut Then
    Exit;
  Shut := True;
  SocketSsl := TSSL(Ssl);
  Ssl := Nil;
  Context := TSSLContext(SslContext);
  SslContext := Nil;
  If Assigned(SocketSsl) Then
    Begin
      Try
        SocketSsl.Shutdown;
      Except
        On E: Exception Do
          LogLink(2, 'ssl shutdown ' + E.Message);
      End;
      SocketSsl.Free;
    End;
  Context.Free;
  If SocketHandle < 0 Then
    Exit;
{$IFDEF UNIX}
  fpShutdown(SocketHandle, SHUT_RDWR);
{$ELSE}
  Shutdown(SocketHandle, 2);
{$ENDIF}
  If OwnsSocket Then
    CloseIo(SocketHandle);
  SocketHandle := -1;
End;

Procedure TMonitorLinkThread.SignalRetired;
Begin
  InterlockedExchange(RetiredFlag, 1);
  If Assigned(Retired) Then
    RTLEventSetEvent(Retired);
End;

Function TMonitorLinkThread.Replacing: Boolean;
Begin
  Result := InterlockedExchangeAdd(ReplaceFlag, 0) = ReplacePublished;
End;

Function TMonitorLinkThread.ByeQueued: Boolean;
Begin
  Result := InterlockedExchangeAdd(ByeState, 0) <> 0;
End;

Procedure TMonitorLinkThread.StartReplace;
Begin
  {$IFDEF DEBUG}
  Assert(GetCurrentThreadId <> ThreadID, 'StartReplace was called on the link''s own thread');
  {$ENDIF}
  { Only the caller that claims the flag writes the deadline. The exchange that publishes the flag is a full
    barrier, so a thread that sees Replacing also sees ReplaceUntil. }
  If InterlockedCompareExchange(ReplaceFlag, ReplaceClaimed, ReplaceIdle) = ReplaceIdle Then
    Begin
      ReplaceUntil := GetTickCount64 + MonitorReplaceFlushMs;
      InterlockedExchange(ReplaceFlag, ReplacePublished);
    End;
  QueueReplaceBye;
  Wake;
End;

Function TMonitorLinkThread.WaitRetired(TimeoutMs: Integer): Boolean;
Begin
  If TimeoutMs < 1 Then
    TimeoutMs := 1;
  If Assigned(Retired) Then
    RTLEventWaitFor(Retired, TimeoutMs);
  Result := InterlockedExchangeAdd(RetiredFlag, 0) <> 0;
End;

Procedure TMonitorLinkThread.QueueReplaceBye;
Var
  Json: String;
  Bytes: RawByteString;
Begin
  If InterlockedCompareExchange(ByeState, 1, 0) <> 0 Then
    Exit;
  Json := EncodeMonitorBye('replaced', 'replaced');
  If Not EncodeFrame(Json, Bytes) Then
    Exit;
  If Assigned(Outbox) Then
    Outbox.AddControl(Bytes);
End;

Function TMonitorLinkThread.BuildSsl: Boolean;
Var
  Raw: PSSL_CTX;
  Context: TSSLContext;
  SocketSsl: TSSL;
Begin
  Result := False;
  Raw := Nil;
  Context := Nil;
  SocketSsl := Nil;
  If SocketHandle < 0 Then
    Exit;
  Try
    Try
      If Assigned(SslTLSMethod) Then
        Raw := SslCtxNew(SslTLSMethod)
      Else
        Raw := SslCtxNew(SslMethodV23);
      If Raw = Nil Then
        Begin
          LogLink(3, 'monitor TLS context was not created bind=' + BindAddress + ' port=' + IntToStr(BoundPort));
          Exit;
        End;
      Context := TSSLContext.Create(Raw);
      Raw := Nil;
      Context.SetOptions(SSL_OP_NO_SSLv2 Or SSL_OP_NO_SSLv3);
      Context.SetMinProtoVersion(MonitorTls12Version);
      Context.SetVerify(SslVerifyNone, Nil);
      Context.SetEcdhAuto(True);
      If Context.UseCertificateASN1(Length(CertificateDer), CertificateDer) <> 1 Then
        Begin
          LogLink(3, 'monitor certificate was not loaded bind=' + BindAddress + ' port=' + IntToStr(BoundPort));
          Exit;
        End;
      If SslCtxUsePrivateKeyASN1(EVP_PKEY_RSA, Context.CTX, KeyDer, Length(KeyDer)) <> 1 Then
        Begin
          LogLink(3, 'monitor key was not loaded bind=' + BindAddress + ' port=' + IntToStr(BoundPort));
          Exit;
        End;
      SocketSsl := TSSL.Create(Context);
      If SocketSsl.SetFd(SocketHandle) <> 1 Then
        Begin
          LogLink(3, 'monitor socket was not attached bind=' + BindAddress + ' port=' + IntToStr(BoundPort));
          Exit;
        End;
      Ssl := SocketSsl;
      SslContext := Context;
      SocketSsl := Nil;
      Context := Nil;
      Result := True;
    Except
      On E: Exception Do
        LogLink(3, 'tls setup bind=' + BindAddress + ' port=' + IntToStr(BoundPort) + ' ' + E.Message);
    End;
  Finally
    FreeAndNil(SocketSsl);
    FreeAndNil(Context);
    If Raw <> Nil Then
      SslCtxFree(Raw);
  End;
End;

Function TMonitorLinkThread.Handshake: Boolean;
Var
  SocketSsl: TSSL;
  Code, Err, Timeout: Integer;
  NowMs: QWord;
Begin
  Result := False;
  HandshakeStart := GetTickCount64;
  If Not BuildSsl Then
    Begin
      DropReason := 'tls setup failed';
      Exit;
    End;
  SocketSsl := TSSL(Ssl);
  Repeat
    If Terminated Then
      Begin
        DropReason := 'stopped';
        Exit;
      End;
    NowMs := GetTickCount64;
    If NowMs >= HandshakeStart + MonitorPartialFrameMs Then
      Begin
        DropReason := 'handshake timeout';
        LogLink(2, 'handshake timeout bind=' + BindAddress + ' port=' + IntToStr(BoundPort));
        Exit;
      End;
    Code := SocketSsl.Accept;
    If Code = 1 Then
      Begin
        If Not MonitorTlsVersionAdequate(String(SocketSsl.Version)) Then
          Begin
            DropReason := 'tls version';
            LogLink(2, 'TLS version is below 1.2 bind=' + BindAddress + ' port=' + IntToStr(BoundPort));
            Exit;
          End;
        Exit(True);
      End;
    Err := SocketSsl.GetError(Code);
    If (Err <> SSL_ERROR_WANT_READ) And (Err <> SSL_ERROR_WANT_WRITE) Then
      Begin
        If (Err = SSL_ERROR_SYSCALL) And RetryableSyscall Then
          Err := SSL_ERROR_WANT_READ
        Else
          Begin
            DropReason := 'handshake failed';
            LogLink(2, 'handshake failed bind=' + BindAddress + ' port=' + IntToStr(BoundPort) + ' error=' + IntToStr(Err));
            Exit;
          End;
      End;
    Timeout := RemainingMs(NowMs, HandshakeStart + MonitorPartialFrameMs);
    PollWait(Timeout, Err = SSL_ERROR_WANT_WRITE);
    DrainWake;
  Until DropLink;
End;

Procedure TMonitorLinkThread.SendReject(Const Reject: TMonitorFrame);
Var
  Deadline: QWord;
Begin
  If Not EncodeFrame(Reject.Json, Unsent) Then
    Exit;
  Deadline := GetTickCount64 + MonitorReplaceFlushMs;
  While (Unsent <> '') And Not Terminated And (GetTickCount64 < Deadline) Do
    Begin
      WriteQuantum;
      If DropLink Or (Unsent = '') Then
        Exit;
      PollWait(50, True);
      DrainWake;
    End;
End;

Procedure TMonitorLinkThread.BecomeController;
Var
  Previous: TMonitorLinkThread;
  Reject: TMonitorFrame;
Begin
  If Not Assigned(Host) Then
    Exit;
  Previous := Host.PrepareReplace(Self);
  Try
    If Assigned(Previous) And Not Previous.WaitRetired(MonitorReplaceFlushMs + 200) Then
      Host.ReleaseController(Previous);
  Finally
    If Assigned(Previous) Then
      Previous.Release;
  End;
  If Terminated Or DropLink Then
    Exit;
  If Not Host.AcceptLink(Reject) Then
    Begin
      If Reject.Json <> '' Then
        SendReject(Reject);
      DropReason := 'handshake rejected';
      Exit;
    End;
  Host.AdoptController(Self);
  Adopted := True;
  ControllerLink := True;
End;

Function TMonitorLinkThread.PollWait(TimeoutMs: Integer; WantWrite: Boolean): Boolean;
{$IFDEF UNIX}
Var
  Fds: Array[0..1] Of pollfd;
  Count, Res: cint;
{$ENDIF}
{$IFDEF WINDOWS}
Var
  ReadSet, WriteSet: TFDSet;
  Time: TTimeVal;
  Res: LongInt;
{$ENDIF}
Begin
  Result := False;
  If TimeoutMs < 0 Then
    TimeoutMs := 0;
{$IFDEF UNIX}
  Fds[0].fd := WakeRead;
  Fds[0].events := POLLIN;
  Fds[0].revents := 0;
  Count := 0;
  If WakeRead >= 0 Then
    Count := 1;
  If SocketHandle >= 0 Then
    Begin
      Fds[Count].fd := SocketHandle;
      Fds[Count].events := POLLIN;
      If WantWrite Then
        Fds[Count].events := Fds[Count].events Or POLLOUT;
      Fds[Count].revents := 0;
      Inc(Count);
    End;
  If Count = 0 Then
    Begin
      Sleep(TimeoutMs);
      Exit;
    End;
  Res := fpPoll(@Fds[0], Count, TimeoutMs);
  If Res < 0 Then
    Begin
      If fpGetErrno = ESysEINTR Then
        Exit;
      DropLink := True;
      DropReason := 'poll failed';
      Exit;
    End;
  Result := Res > 0;
{$ENDIF}
{$IFDEF WINDOWS}
  FD_ZERO(ReadSet);
  FD_ZERO(WriteSet);
  If WakeRead >= 0 Then
    FD_SET(WakeRead, ReadSet);
  If SocketHandle >= 0 Then
    Begin
      FD_SET(SocketHandle, ReadSet);
      If WantWrite Then
        FD_SET(SocketHandle, WriteSet);
    End;
  Time.tv_sec := TimeoutMs Div 1000;
  Time.tv_usec := (TimeoutMs Mod 1000) * 1000;
  Res := Select(SocketHandle + 1, @ReadSet, @WriteSet, Nil, @Time);
  If Res < 0 Then
    Begin
      If socketerror = EsockEINTR Then
        Exit;
      DropLink := True;
      DropReason := 'poll failed';
      Exit;
    End;
  Result := Res > 0;
{$ENDIF}
End;

Function TMonitorLinkThread.NextTimeout: Integer;
Var
  NowMs: QWord;
Begin
  If ReadAgain Then
    Exit(0);
  NowMs := GetTickCount64;
  If Not ControllerLink Then
    Exit(RemainingMs(NowMs, HandshakeStart + MonitorPartialFrameMs));
  Result := MonitorHeartbeatMs;
  If PartialSince <> 0 Then
    Result := Lesser(Result, RemainingMs(NowMs, PartialSince + MonitorPartialFrameMs));
  If Replacing And (ReplaceUntil <> 0) Then
    Result := Lesser(Result, RemainingMs(NowMs, ReplaceUntil));
  If CloseSince <> 0 Then
    Result := Lesser(Result, RemainingMs(NowMs, CloseSince + MonitorPartialFrameMs));
End;

Function TMonitorLinkHost.BeginLinkPass(Link: TMonitorLinkThread): TObject;
Begin
  Link.PassIsController := IsController(Link);
  Result := Nil;
End;

Function TMonitorLinkThread.ControllerForPass: Boolean;
Begin
  Result := PassIsController And Not Replacing;
End;

Function TMonitorLinkThread.FrameReady: Boolean;
Begin
  Result := Unsent <> '';
  If Result Or Not Assigned(Outbox) Then
    Exit;
  Result := Outbox.HasFrame;
  If Result Or Replacing Or Not ControllerLink Then
    Exit;
  Result := Assigned(Host) And Host.OutboundPending(Self);
End;

Function TMonitorLinkThread.WantsWrite(Ready: Boolean): Boolean;
Begin
  If WriteOwed Then
    Exit(WriteWantsWrite);
  If ReadOwed Then
    Exit(ReadWantsWrite);
  Result := Ready;
End;

Function TMonitorLinkThread.TakeFrame(Out Bytes: RawByteString): Boolean;
Var
  Lane: TMonitorOutboxLane;
Begin
  Bytes := '';
  Result := False;
  If Not Assigned(Outbox) Then
    Exit;
  Result := Outbox.Take(Bytes, Lane);
  If Result Then
    Begin
      If Replacing And ByeQueued Then
        ByeArmed := True;
      Exit;
    End;
  If Replacing Or Not ControllerLink Or Not Assigned(Host) Then
    Exit;
  Result := Host.TakeSessionFrame(Self, Bytes);
End;

Procedure TMonitorLinkThread.AppendPending(Var Buffer: RawByteString; Buf: Pointer; Count: Integer);
Var
  StartAt: Integer;
Begin
  If (Count <= 0) Or Not Assigned(Buf) Then
    Exit;
  StartAt := Length(Buffer);
  SetLength(Buffer, StartAt + Count);
  Move(Buf^, Buffer[StartAt + 1], Count);
End;

Procedure TMonitorLinkThread.ConsumePending;
Var
  Frame: TMonitorFrame;
  Status: TMonitorFrameStatus;
  Had, Consumed, ReadOffset: Integer;
  Ok: Boolean;
Begin
  Had := Length(Pending);
  Consumed := 0;
  ReadOffset := 0;
  Status := mfsNeedMore;
  Ok := True;
  While Ok And (ReadOffset < Length(Pending)) And Not DropLink Do
    Begin
      Ok := TryConsumeMonitorFrame(Pending, ReadOffset, Frame, Status);
      If Ok Then
        Begin
          Inc(Consumed);
          If ControllerLink And Assigned(Host) Then
            Try
              Host.DeliverFrame(Self, Frame);
            Except
              On E: Exception Do
                ReportPluginException(MonitorLogArea, E);
            End;
        End;
    End;
  If ReadOffset > 0 Then
    Delete(Pending, 1, ReadOffset);
  If (Not Ok) And (Status <> mfsNeedMore) And (Length(Pending) > 0) Then
    Begin
      DropLink := True;
      DropReason := 'bad frame';
      LogLink(2, 'frame rejected status=' + IntToStr(Ord(Status)) + ' bytes=' + IntToStr(Length(Pending)) + ' bind=' +
        BindAddress + ' port=' + IntToStr(BoundPort));
    End;
  If Length(Pending) = 0 Then
    PartialSince := 0
  Else If (Had = 0) Or (Consumed > 0) Or (PartialSince = 0) Then
    PartialSince := GetTickCount64;
End;

Procedure TMonitorLinkThread.DrainReads;
Var
  SocketSsl: TSSL;
  Buf: Array[0..MonitorReadChunk - 1] Of Byte;
  Count, Err, Reads: Integer;
Begin
  If DropLink Or WriteOwed Or Not Assigned(Ssl) Then
    Exit;
  SocketSsl := TSSL(Ssl);
  ReadAgain := False;
  Reads := 0;
  Repeat
    If Reads >= MonitorLinkReadCap Then
      Begin
        ReadAgain := True;
        Exit;
      End;
    Inc(Reads);
    Count := SocketSsl.Read(@Buf[0], SizeOf(Buf));
    If Count > 0 Then
      Begin
        AppendPending(Pending, @Buf[0], Count);
        ReadOwed := False;
        ReadWantsWrite := False;
        ConsumePending;
        If DropLink Then
          Exit;
        Continue;
      End;
    Err := SocketSsl.GetError(Count);
    If Err = SSL_ERROR_WANT_READ Then
      Begin
        ReadOwed := False;
        ReadWantsWrite := False;
        Exit;
      End;
    If Err = SSL_ERROR_WANT_WRITE Then
      Begin
        ReadOwed := True;
        ReadWantsWrite := True;
        Exit;
      End;
    If (Err = SSL_ERROR_SYSCALL) And RetryableSyscall Then
      Begin
        ReadOwed := True;
        ReadWantsWrite := False;
        Exit;
      End;
    DropLink := True;
    If Err = SSL_ERROR_ZERO_RETURN Then
      DropReason := 'peer closed'
    Else
      DropReason := 'read failed';
    Exit;
  Until False;
End;

Procedure TMonitorLinkThread.WriteQuantum;
Var
  SocketSsl: TSSL;
  Count, Err: Integer;
Begin
  If DropLink Or Not Assigned(Ssl) Then
    Exit;
  If ReadOwed And Not WriteOwed Then
    Exit;
  SocketSsl := TSSL(Ssl);
  If Unsent = '' Then
    Begin
      If Not TakeFrame(Unsent) Then
        Exit;
      FrameTakenThisPass := True;
    End;
  If Unsent = '' Then
    Exit;
  While Unsent <> '' Do
    Begin
      Count := SocketSsl.Write(@Unsent[1], Length(Unsent));
      If Count > 0 Then
        Begin
          If Count > Length(Unsent) Then
            Count := Length(Unsent);
          Delete(Unsent, 1, Count);
          WriteOwed := False;
          WriteWantsWrite := False;
          If Unsent = '' Then
            Begin
              If ByeArmed Then
                ByeSent := True;
              Exit;
            End;
        End
      Else
        Begin
          Err := SocketSsl.GetError(Count);
          If (Err = SSL_ERROR_WANT_READ) Or (Err = SSL_ERROR_WANT_WRITE) Then
            Begin
              WriteOwed := True;
              WriteWantsWrite := Err = SSL_ERROR_WANT_WRITE;
              Exit;
            End;
          If (Err = SSL_ERROR_SYSCALL) And RetryableSyscall Then
            Begin
              WriteOwed := True;
              WriteWantsWrite := True;
              Exit;
            End;
          DropLink := True;
          DropReason := 'write failed';
          Exit;
        End;
    End;
End;

Procedure TMonitorLinkThread.ServiceOnce;
Begin
  If WriteOwed Then
    Begin
      WriteQuantum;
      If WriteOwed Or DropLink Then
        Exit;
    End;
  DrainReads;
  If DropLink Or ReadOwed Then
    Exit;
  WriteQuantum;
End;

Procedure TMonitorLinkThread.CheckDeadlines(Ready: Boolean);
Var
  NowMs: QWord;
Begin
  If DropLink Then
    Exit;
  NowMs := GetTickCount64;
  If (PartialSince <> 0) And (NowMs >= PartialSince + MonitorPartialFrameMs) Then
    Begin
      DropLink := True;
      DropReason := 'partial frame timeout';
      LogLink(2, 'partial frame timeout bytes=' + IntToStr(Length(Pending)) + ' bind=' + BindAddress + ' port=' +
        IntToStr(BoundPort));
      Exit;
    End;
  If Replacing And (ByeSent And (Unsent = '') And Not WriteOwed) Then
    Begin
      DropLink := True;
      DropReason := 'replaced';
      Exit;
    End;
  If Replacing And (ReplaceUntil <> 0) And (NowMs >= ReplaceUntil) Then
    Begin
      DropLink := True;
      DropReason := 'replaced';
      Exit;
    End;
  If Not Assigned(Host) Or Not Host.CloseRequested(Self) Then
    Begin
      CloseSince := 0;
      Exit;
    End;
  If CloseSince = 0 Then
    CloseSince := NowMs;
  If (Not WriteOwed) And (Unsent = '') And Not Ready And Not ReadOwed Then
    Begin
      DropLink := True;
      DropReason := 'close requested';
      Exit;
    End;
  If NowMs >= CloseSince + MonitorPartialFrameMs Then
    Begin
      DropLink := True;
      DropReason := 'close timeout';
    End;
End;

Procedure TMonitorLinkThread.RunLink;
Var
  HeldOff, Ready: Boolean;
Begin
  HeldOff := False;
  Ready := False;
  If Not WakeOpen Then
    Begin
      DropReason := 'wake handle failed';
      LogLink(3, 'wake handle failed bind=' + BindAddress + ' port=' + IntToStr(BoundPort));
      Exit;
    End;
  If Not Handshake Then
    Exit;
  BecomeController;
  If Not ControllerLink Then
    Exit;
  While Not Terminated And Not DropLink Do
    Begin
      If Replacing And Not ByeQueued Then
        QueueReplaceBye;
      { The previous snapshot drives poll interest. Refresh once after polling, so
        a producer wake participates in the burst hold-off before ServiceOnce. }
      PollWait(NextTimeout, WantsWrite(Ready));
      DrainWake;
      If Assigned(Host) Then
        PassSession := Host.BeginLinkPass(Self);
      If Adopted And Assigned(Host) And Not PassIsController Then
        Begin
          DropLink := True;
          DropReason := 'replaced';
          Break;
        End;
      Ready := FrameReady;
      FrameTakenThisPass := False;
      { One queued frame is sent at once. A burst waits briefly so a ping that follows
        the queue is read before the first bulk write. }
      If (Not HeldOff) And Ready And Not WriteOwed And Not ReadOwed And Assigned(Host) And
        (Host.OutboundCount(Self) > 1) Then
        Begin
          { Read a ping that is already in TLS before the first bulk write of this burst. }
          PollWait(20, False);
          DrainReads;
          If Not DropLink And Assigned(Ssl) And (TSSL(Ssl).Pending = 0) Then
            Begin
              PollWait(5, False);
              DrainReads;
            End;
          HeldOff := True;
        End;
      If Not Ready Then
        HeldOff := False;
      If ControllerLink And Assigned(Host) Then
        Host.NoteTime(Self, GetTickCount64);
      ServiceOnce;
      If ControllerLink And Assigned(Host) Then
        Host.NotePartialFrame(Self, PartialSince <> 0);
      { Reads and timers can queue frames after the readiness snapshot. Wait for
        a pass that took no frame before treating a close as fully drained. }
      CheckDeadlines(Ready Or FrameTakenThisPass);
      PassSession := Nil;
    End;
End;

Procedure TMonitorLinkThread.Execute;
Begin
  Try
    Try
      RunLink;
    Except
      On E: Exception Do
        Begin
          DropReason := 'link failed';
          ReportPluginException(MonitorLogArea, E);
        End;
    End;
  Finally
    If DropReason = '' Then
      If Terminated Then
        DropReason := 'stopped'
      Else
        DropReason := 'closed';
    LogLink(1, 'disconnect bind=' + BindAddress + ' port=' + IntToStr(BoundPort) + ' ' + DropReason);
    ShutdownLink;
    { Free the accepted stream before the session reset, so the simultaneous cap
      does not keep a finished socket until the accept idle. }
    ReleaseAccepted;
    If Adopted And Assigned(Host) Then
      Host.ReleaseController(Self);
    SignalRetired;
    InterlockedExchange(FinishedFlag, 1);
  End;
End;

End.
