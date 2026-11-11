Program AssistantMonitorSocketTest;

{ Loopback TLS checks for the monitor listen thread (c) 2026 Michell Computing.

  No Interfaces unit. The runner writes this binary with a temporary -FU and -FE,
  never under Source/. Certificate files are created under a temp settings
  directory. Loopback only. If EnsureOpenSSLReady fails, the process exits
  non-zero with that error. That is a failure, not a skip.

  The partial-record check is an incomplete TLS application-data record after
  the handshake. A second handshake must not stall the link already up.
  TLS alone does not replace the controller. An authenticated link does.
  The kernel port is fpGetSockName. TInetServer.Port is not the connect port. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads, BaseUnix, UnixType,
  {$ENDIF}
  AssistantMonitorCommands, Classes, SysUtils, fpjson, sockets, ssockets, openssl, fpopenssl, opensslsockets,
  fpsha256, fphashutils, AssistantMonitorLinkStubs,
  AssistantHttps, AssistantMonitorTls, AssistantMonitorLan, AssistantMonitorSession,
  AssistantMonitorCodec, AssistantMonitorFrames, AssistantMonitorCarrier,
  AssistantMonitorSettings, WorkflowSettings;

Type
  TLoopClient = Class
    Socket: TInetSocket;
    Handler: TOpenSSLSocketHandler;
    Pending: RawByteString;
    Destructor Destroy; Override;
    Function Open(Port: Word; HandshakeMs: Integer; Out ErrorText: String): Boolean;
    Function VersionText: String;
    Function Fingerprint: String;
    Function WriteJson(Const Json: String; Deadline: QWord): Boolean;
    Function ReadMessage(Deadline: QWord; Out Message: TMonitorMessage; Out ErrorText: String): Boolean;
    Function StillOpen: Boolean;
    Function InjectPartialApplicationRecord: Boolean;
  End;

Var
  FailCount: Integer;
  SawConnecting: Boolean;
  SettingsRoot: String;
  HostFingerprint: String;
  Lan: TMonitorLanCarrier;
  LanRef: IMonitorCarrier;
  Session: TMonitorSession;
  ErrorText: String;

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

Procedure NoteCarrier;
Begin
  If Assigned(Lan) And (Lan.State = mcsConnecting) Then
    SawConnecting := True;
End;

Procedure SleepPump(Ms: Integer);
Var
  Deadline: QWord;
Begin
  Deadline := GetTickCount64 + QWord(Ms);
  While GetTickCount64 < Deadline Do
    Begin
      NoteCarrier;
      CheckSynchronize(0);
      Sleep(20);
    End;
End;

Function After(Ms: Integer): QWord;
Begin
  Result := GetTickCount64 + QWord(Ms);
End;

Function RetryableSyscall: Boolean;
Begin
  Result := socketerror = EsockEWOULDBLOCK;
  {$IFDEF UNIX}
  Result := Result Or (socketerror = ESysEAGAIN) Or (socketerror = ESysEINTR);
  {$ENDIF}
End;

Procedure ApplyRecvTimeout(Handle: THandle; Ms: Integer);
{$IFDEF UNIX}
Var
  Tv: timeval;
{$ENDIF}
Begin
  If Ms < 1 Then
    Ms := 1;
  {$IFDEF UNIX}
  Tv.tv_sec := Ms Div 1000;
  Tv.tv_usec := (Ms Mod 1000) * 1000;
  fpSetSockOpt(Handle, SOL_SOCKET, SO_RCVTIMEO, @Tv, SizeOf(Tv));
  fpSetSockOpt(Handle, SOL_SOCKET, SO_SNDTIMEO, @Tv, SizeOf(Tv));
  {$ENDIF}
End;

Function KernelPort(Server: TInetServer): Word;
Var
  Addr: TSockAddr;
  Len: TSockLen;
Begin
  Result := 0;
  Addr := Default(TSockAddr);
  If Not Assigned(Server) Then
    Exit;
  Len := SizeOf(Addr);
  { Bind leaves TInetServer.Port at the requested value. Do not read it. }
  If fpGetSockName(Server.FPSocket.FD, @Addr, @Len) <> 0 Then
    Exit;
  Result := NToHs(Addr.sin_port);
End;

Procedure AppendBytes(Var Pending: RawByteString; Buf: Pointer; Count: Integer);
Var
  StartAt: Integer;
Begin
  If (Count <= 0) Or Not Assigned(Buf) Then
    Exit;
  StartAt := Length(Pending);
  SetLength(Pending, StartAt + Count);
  Move(Buf^, Pending[StartAt + 1], Count);
End;

Function FrameBytes(Const Json: String; Out Bytes: RawByteString): Boolean;
Var
  Status: TMonitorFrameStatus;
Begin
  Bytes := '';
  Result := (Json <> '') And TryEncodeMonitorFrame(Json, Bytes, Status);
End;

Function PeerFingerprint(Handler: TOpenSSLSocketHandler): String;
Var
  Cert: PX509;
  Bio: PBIO;
  Count: Integer;
  Der, Digest: TBytes;
Begin
  Result := '';
  Digest := Nil;
  Der := Nil;
  Cert := Nil;
  Bio := Nil;
  If Not Assigned(Handler) Or Not Assigned(Handler.SSL) Then
    Exit;
  Cert := Handler.SSL.PeerCertificate;
  If Cert = Nil Then
    Exit;
  Try
    Bio := BioNew(BioSMem);
    If Bio = Nil Then
      Exit;
    If i2dX509bio(Bio, Cert) <= 0 Then
      Exit;
    Count := BioCtrlPending(Bio);
    If Count < 1 Then
      Exit;
    SetLength(Der, Count);
    If BioRead(Bio, Der, Count) <> Count Then
      Exit;
    If (Length(Der) < 1) Or (Der[0] <> $30) Then
      Exit;
    TSHA256.DigestBytes(Der, Digest);
    Result := LowerCase(String(BytesToHexStr(Digest)));
  Finally
    If Bio <> Nil Then
      BioFreeAll(Bio);
    X509Free(Cert);
  End;
End;

Destructor TLoopClient.Destroy;
Begin
  FreeAndNil(Socket);
  Handler := Nil;
  Inherited Destroy;
End;

Function TLoopClient.Open(Port: Word; HandshakeMs: Integer; Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := '';
  Pending := '';
  If Assigned(Socket) Then
    FreeAndNil(Socket);
  Handler := Nil;
  Try
    Socket := TInetSocket.Create('127.0.0.1', Port, HandshakeMs, TOpenSSLSocketHandler.Create, False);
    Handler := TOpenSSLSocketHandler(Socket.Handler);
    Handler.VerifyPeerCert := False;
    Handler.SendHostAsSNI := False;
    If Assigned(Handler.CertificateData) Then
      Handler.CertificateData.ALPNProtocols := '';
    ApplyRecvTimeout(Socket.Handle, HandshakeMs);
    Socket.Connect;
  Except
    On E: Exception Do
      Begin
        ErrorText := E.Message;
        Exit;
      End;
  End;
  Result := Assigned(Handler) And Assigned(Handler.SSL);
  If Not Result Then
    ErrorText := 'TLS handshake did not finish.';
End;

Function TLoopClient.VersionText: String;
Begin
  Result := '';
  If Assigned(Handler) And Assigned(Handler.SSL) Then
    Result := String(Handler.SSL.Version);
End;

Function TLoopClient.Fingerprint: String;
Begin
  Result := PeerFingerprint(Handler);
End;

Function TLoopClient.WriteJson(Const Json: String; Deadline: QWord): Boolean;
Var
  Bytes: RawByteString;
  Offset, Count, Err: Integer;
Begin
  Result := False;
  If Not FrameBytes(Json, Bytes) Then
    Exit;
  If Not Assigned(Handler) Or Not Assigned(Handler.SSL) Then
    Exit;
  Offset := 1;
  While Offset <= Length(Bytes) Do
    Begin
      If GetTickCount64 >= Deadline Then
        Exit;
      NoteCarrier;
      Count := Handler.SSL.Write(@Bytes[Offset], Length(Bytes) - Offset + 1);
      If Count > 0 Then
        Inc(Offset, Count)
      Else
        Begin
          Err := Handler.SSL.GetError(Count);
          If (Err = SSL_ERROR_WANT_READ) Or (Err = SSL_ERROR_WANT_WRITE) Then
            Begin
              Sleep(20);
              Continue;
            End;
          If (Err = SSL_ERROR_SYSCALL) And RetryableSyscall Then
            Begin
              Sleep(20);
              Continue;
            End;
          Exit;
        End;
    End;
  Result := True;
End;

Function TLoopClient.ReadMessage(Deadline: QWord; Out Message: TMonitorMessage; Out ErrorText: String): Boolean;
Var
  Buf: Array[0..8191] Of Byte;
  Count, Err: Integer;
  Status: TMonitorFrameStatus;
  Frame: TMonitorFrame;
Begin
  Result := False;
  ErrorText := '';
  Message := Default(TMonitorMessage);
  If Not Assigned(Handler) Or Not Assigned(Handler.SSL) Then
    Begin
      ErrorText := 'TLS is not up.';
      Exit;
    End;
  While GetTickCount64 < Deadline Do
    Begin
      NoteCarrier;
      CheckSynchronize(0);
      If TryConsumeMonitorFrame(Pending, Frame, Status) Then
        Begin
          Result := TryDecodeMonitorEnvelope(Frame.Json, Message, ErrorText);
          If Not Result And (ErrorText = '') Then
            ErrorText := 'Could not decode the monitor frame.';
          Exit;
        End;
      If (Status <> mfsNeedMore) And (Length(Pending) >= MonitorFrameHeaderSize) Then
        Begin
          ErrorText := 'Bad frame status ' + IntToStr(Ord(Status)) + '.';
          Exit;
        End;
      If (Handler.SSL.Pending = 0) And Not Handler.CanRead(50) Then
        Continue;
      Count := Handler.SSL.Read(@Buf[0], SizeOf(Buf));
      If Count > 0 Then
        AppendBytes(Pending, @Buf[0], Count)
      Else
        Begin
          Err := Handler.SSL.GetError(Count);
          If (Err = SSL_ERROR_WANT_READ) Or (Err = SSL_ERROR_WANT_WRITE) Then
            Continue;
          If (Err = SSL_ERROR_SYSCALL) And RetryableSyscall Then
            Continue;
          ErrorText := 'Peer closed during read (' + IntToStr(Err) + ').';
          Exit;
        End;
    End;
  ErrorText := 'Timed out waiting for a frame.';
End;

Function TLoopClient.StillOpen: Boolean;
Var
  Buf: Byte;
  Count: ssize_t;
Begin
  Result := False;
  If Not Assigned(Socket) Or Not Assigned(Socket.Handler) Then
    Exit;
  If Not Socket.Handler.CanRead(0) Then
    Exit(True);
  Count := fpRecv(Socket.Handle, @Buf, 1, MSG_PEEK);
  If Count > 0 Then
    Exit(True);
  If Count = 0 Then
    Exit(False);
  Result := RetryableSyscall;
End;

Function TLoopClient.InjectPartialApplicationRecord: Boolean;
Var
  Header: Array[0..4] Of Byte;
  Sent: ssize_t;
Begin
  Result := False;
  If Not Assigned(Socket) Then
    Exit;
  { Incomplete application-data record: type, TLS 1.2 legacy version, length 256, no body. }
  Header[0] := $17;
  Header[1] := $03;
  Header[2] := $03;
  Header[3] := $01;
  Header[4] := $00;
  {$IFDEF UNIX}
  Sent := fpSend(Socket.Handle, @Header[0], 5, MSG_NOSIGNAL);
  {$ELSE}
  Sent := fpSend(Socket.Handle, @Header[0], 5, 0);
  {$ENDIF}
  Result := Sent = 5;
End;

Function ClampReceiveWindow(Handle: THandle): Boolean;
{$IFDEF UNIX}
Var
  Value: cint;
{$ENDIF}
Begin
  {$IFDEF UNIX}
  Value := 4096;
  Result := fpSetSockOpt(Handle, IPPROTO_TCP, TCP_WINDOW_CLAMP, @Value, SizeOf(Value)) = 0;
  Value := 4096;
  Result := Result And (fpSetSockOpt(Handle, SOL_SOCKET, SO_RCVBUF, @Value, SizeOf(Value)) = 0);
  {$ELSE}
  Result := True;
  {$ENDIF}
End;

Function ReleaseReceiveWindow(Handle: THandle): Boolean;
{$IFDEF UNIX}
Var
  Value: cint;
{$ENDIF}
Begin
  {$IFDEF UNIX}
  Value := 1048576;
  Result := fpSetSockOpt(Handle, IPPROTO_TCP, TCP_WINDOW_CLAMP, @Value, SizeOf(Value)) = 0;
  Value := 262144;
  Result := Result And (fpSetSockOpt(Handle, SOL_SOCKET, SO_RCVBUF, @Value, SizeOf(Value)) = 0);
  {$ELSE}
  Result := True;
  {$ENDIF}
End;

Function WaitCarrier(Expected: TMonitorCarrierState; Ms: Integer): Boolean;
Var
  Deadline: QWord;
Begin
  Deadline := After(Ms);
  Repeat
    NoteCarrier;
    CheckSynchronize(0);
    If Assigned(Lan) And (Lan.State = Expected) Then
      Exit(True);
    Sleep(20);
  Until GetTickCount64 >= Deadline;
  Result := Assigned(Lan) And (Lan.State = Expected);
End;

Function WaitSession(Expected: TMonitorSessionState; Ms: Integer): Boolean;
Var
  Deadline: QWord;
Begin
  Deadline := After(Ms);
  Repeat
    NoteCarrier;
    CheckSynchronize(0);
    If Assigned(Session) And (Session.State = Expected) Then
      Exit(True);
    Sleep(20);
  Until GetTickCount64 >= Deadline;
  Result := Assigned(Session) And (Session.State = Expected);
End;

Function RejectedReason(Const Message: TMonitorMessage; Out Reason: String): Boolean;
Var
  Rejected: TMonitorRejected;
Begin
  Reason := '';
  Result := (Message.Kind = mmkRejected) And DecodeCommandRejected(Message.PayloadJson, Rejected);
  If Result Then
    Reason := Rejected.Reason;
End;

Function ByeReason(Const Message: TMonitorMessage; Out Reason: String): Boolean;
Var
  Bye: TMonitorBye;
Begin
  Reason := '';
  Result := (Message.Kind = mmkBye) And DecodeCommandBye(Message.PayloadJson, Bye);
  If Result Then
    Reason := Bye.Reason;
End;

{ Half a ClientHello. The accept thread must hand this off and leave the live link free. }
Function OpenHandshakeStall(Port: Word): cint;
Var
  Addr: TSockAddr;
  One: Byte;
Begin
  Result := fpSocket(AF_INET, SOCK_STREAM, 0);
  If Result < 0 Then
    Exit;
  Addr := Default(TSockAddr);
  Addr.sin_family := AF_INET;
  Addr.sin_port := NToHs(Port);
  Addr.sin_addr.s_addr := htonl($7F000001);
  If fpConnect(Result, @Addr, SizeOf(Addr)) <> 0 Then
    Begin
      CloseSocket(Result);
      Result := -1;
      Exit;
    End;
  One := $16;
  If fpSend(Result, @One, 1, 0) <> 1 Then
    Begin
      CloseSocket(Result);
      Result := -1;
    End;
End;

Function PongTicks(Const Message: TMonitorMessage; Out Ticks: Int64): Boolean;
Var
  Body: TMonitorTicks;
Begin
  Ticks := 0;
  Result := (Message.Kind = mmkPong) And DecodeCommandTicks(Message.PayloadJson, Body);
  If Result Then
    Ticks := Body.Ticks;
End;

Function LargePingJson: String;
Var
  Payload: TJSONObject;
Begin
  Payload := TJSONObject.Create;
  Payload.Add('pad', StringOfChar('a', 32000));
  Result := EncodeMonitorEnvelope(mmkPing, 'large1', Payload);
  Payload.Free;
End;

Procedure RemoveSettings;
Var
  CertDir, SettingsFile: String;
Begin
  If SettingsRoot = '' Then
    Exit;
  DeleteFile(MonitorCertificateFile);
  DeleteFile(MonitorKeyFile);
  CertDir := ExcludeTrailingPathDelimiter(ExtractFilePath(MonitorCertificateFile));
  RemoveDir(CertDir);
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

Procedure PrepareSettings;
Var
  Guid: TGuid;
  ErrorText: String;
Begin
  If CreateGUID(Guid) <> 0 Then
    Raise Exception.Create('Could not create a settings directory name');
  SettingsRoot := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-monitor-socket-' + GUIDToString(Guid);
  If Not ForceDirectories(SettingsRoot) Then
    Raise Exception.Create('Could not create ' + SettingsRoot);
  SetWorkflowSettingsDirectory(SettingsRoot);
  Check('host certificate', EnsureMonitorHostCertificate(ErrorText));
  If ErrorText <> '' Then
    WriteLn('detail certificate ', ErrorText);
  Check('host fingerprint', MonitorHostFingerprint(HostFingerprint, ErrorText) And (Length(HostFingerprint) = 64));
  If ErrorText <> '' Then
    WriteLn('detail fingerprint ', ErrorText);
End;

Procedure StartListener;
Var
  ErrorText: String;
  Server: TInetServer;
  Port: Word;
Begin
  Session := TMonitorSession.Create;
  Check('session listens', Session.StartListening('127.0.0.1', 0, ErrorText) And (Session.State = mssListening));
  If ErrorText <> '' Then
    WriteLn('detail session ', ErrorText);
  Lan := TMonitorLanCarrier.Create('127.0.0.1', 0, MonitorCertificateFile, MonitorKeyFile);
  LanRef := Lan;
  Lan.AttachSession(Session);
  Session.AttachCarrier(LanRef);
  Check('carrier starts', Lan.Start(ErrorText));
  If ErrorText <> '' Then
    WriteLn('detail carrier ', ErrorText);
  Server := Nil;
  If Assigned(Lan.ListenThread) Then
    Server := Lan.ListenThread.Server;
  Port := KernelPort(Server);
  Check('kernel port from fpGetSockName', (Port <> 0) And (Port = Lan.BoundPort) And (Port = MonitorKernelPort(Server)));
  Check('requested port stays 0', Assigned(Server) And (Server.Port = 0));
  Check('listening not connecting', Lan.State = mcsListening);
End;

Procedure StopListener;
Begin
  If Assigned(Lan) Then
    Lan.Stop;
  If Assigned(Session) Then
    FreeAndNil(Session);
  Lan := Nil;
  LanRef := Nil;
End;

Procedure RunChecks;
Var
  First, Spare, Again, Partial, Probe, Blocked: TLoopClient;
  ErrorText, Reason, FirstPrint, SecondPrint, Version: String;
  Message: TMonitorMessage;
  Ticks: Int64;
  Frame: TMonitorFrame;
  Port: Word;
  Started: QWord;
  Elapsed: QWord;
  I: Integer;
  Server: TInetServer;
  Stall: cint;
Begin
  First := Nil;
  Spare := Nil;
  Again := Nil;
  Partial := Nil;
  Probe := Nil;
  Blocked := Nil;
  Stall := -1;
  FirstPrint := '';
  SecondPrint := '';
  Try
    Server := Lan.ListenThread.Server;
    Port := KernelPort(Server);
    First := TLoopClient.Create;
    Check('one tls connection', First.Open(Port, 3000, ErrorText));
    If ErrorText <> '' Then
      WriteLn('detail connect ', ErrorText);
    Check('handshake reaches accepted', WaitSession(mssAccepted, 2000) And WaitCarrier(mcsConnected, 2000));
    Version := First.VersionText;
    Check('tls version 1.2 or higher', MonitorTlsVersionAdequate(Version));
    If Not MonitorTlsVersionAdequate(Version) Then
      WriteLn('detail version=', Version);
    FirstPrint := First.Fingerprint;
    Check('fingerprint matches certificate', (FirstPrint <> '') And (FirstPrint = HostFingerprint));
    If FirstPrint <> HostFingerprint Then
      WriteLn('detail peer=', FirstPrint, ' file=', HostFingerprint);
    Check('frame round-trip write', First.WriteJson(EncodeCommandTicks(mmkPing, 'ping1', 42), After(3000)));
    Check('frame round-trip read', First.ReadMessage(After(3000), Message, ErrorText));
    If ErrorText <> '' Then
      WriteLn('detail round-trip ', ErrorText);
    Check('frame round-trip pong', PongTicks(Message, Ticks) And (Ticks = 42));
    If Message.Kind <> mmkPong Then
      WriteLn('detail round-trip type=', Message.TypeName);

    Stall := OpenHandshakeStall(Port);
    Check('handshake stall connected', Stall >= 0);
    Started := GetTickCount64;
    Check('live ping during handshake stall', First.WriteJson(EncodeCommandTicks(mmkPing, 'ping-stall', 9), After(1000)));
    Check('live pong during handshake stall', First.ReadMessage(After(800), Message, ErrorText) And PongTicks(Message, Ticks) And
      (Ticks = 9));
    Elapsed := GetTickCount64 - Started;
    If ErrorText <> '' Then
      WriteLn('detail stall ', ErrorText, ' elapsed=', IntToStr(Elapsed));
    Check('stall does not delay the live link', Elapsed < 800);
    If Stall >= 0 Then
      CloseSocket(Stall);
    Stall := -1;
    SleepPump(800);

    Spare := TLoopClient.Create;
    Check('second tls connection', Spare.Open(Port, 3000, ErrorText));
    If ErrorText <> '' Then
      WriteLn('detail second ', ErrorText);
    Check('idle candidate does not replace', Not First.ReadMessage(After(400), Message, ErrorText));
    Check('controller remains accepted', (Session.State = mssAccepted) And (Lan.State = mcsConnected));
    Check('controller ping during candidate', First.WriteJson(EncodeCommandTicks(mmkPing, 'ping-still', 11), After(3000)));
    Check('controller pong during candidate', First.ReadMessage(After(3000), Message, ErrorText) And PongTicks(Message, Ticks) And
      (Ticks = 11));
    If ErrorText <> '' Then
      WriteLn('detail candidate ', ErrorText);
    FreeAndNil(Spare);
    Check('bye write', First.WriteJson(EncodeCommandBye('bye1', 'client'), After(3000)));
    Check('listening after bye', WaitCarrier(mcsListening, 3000) And WaitSession(mssListening, 3000));
    FreeAndNil(First);

    Again := TLoopClient.Create;
    Check('reconnect after bye', Again.Open(Port, 3000, ErrorText));
    If ErrorText <> '' Then
      WriteLn('detail reconnect ', ErrorText);
    Check('reconnect reaches accepted', WaitSession(mssAccepted, 2000) And WaitCarrier(mcsConnected, 2000));
    Check('reconnect frame write', Again.WriteJson(EncodeCommandTicks(mmkPing, 'ping2', 7), After(3000)));
    Check('reconnect frame read', Again.ReadMessage(After(3000), Message, ErrorText));
    If ErrorText <> '' Then
      WriteLn('detail reconnect read ', ErrorText);
    Check('reconnect accepted', PongTicks(Message, Ticks) And (Ticks = 7));
    If Message.Kind = mmkRejected Then
      WriteLn('detail reconnect rejected ', String(Message.PayloadJson));
    SecondPrint := Again.Fingerprint;
    Check('sequential fingerprint matches', (SecondPrint <> '') And (SecondPrint = FirstPrint) And
      (SecondPrint = HostFingerprint));
    If SecondPrint <> FirstPrint Then
      WriteLn('detail second print=', SecondPrint, ' first=', FirstPrint);
    Check('bye before partial', Again.WriteJson(EncodeCommandBye('bye2', 'client'), After(3000)));
    Check('listening before partial', WaitCarrier(mcsListening, 3000) And WaitSession(mssListening, 3000));
    FreeAndNil(Again);

    Partial := TLoopClient.Create;
    Check('partial setup connection', Partial.Open(Port, 3000, ErrorText));
    If ErrorText <> '' Then
      WriteLn('detail partial setup ', ErrorText);
    Check('partial setup accepted', WaitSession(mssAccepted, 2000));
    Check('partial tls record sent', Partial.InjectPartialApplicationRecord);
    Probe := TLoopClient.Create;
    Started := GetTickCount64;
    Check('probe connects during partial record', Probe.Open(Port, 2500, ErrorText));
    Elapsed := GetTickCount64 - Started;
    If ErrorText <> '' Then
      WriteLn('detail probe ', ErrorText, ' elapsed=', IntToStr(Elapsed));
    Check('partial record does not stall', Elapsed < 1800);
    Check('unauthenticated probe does not replace', Not Partial.ReadMessage(After(400), Message, ErrorText));
    Check('probe is not the controller', (Session.State = mssAccepted) And (Lan.State = mcsConnected));
    FreeAndNil(Probe);
    FreeAndNil(Partial);
    Check('listening after partial', WaitCarrier(mcsListening, 3000) And WaitSession(mssListening, 3000));

    Blocked := TLoopClient.Create;
    Check('write-block connection', Blocked.Open(Port, 3000, ErrorText));
    If ErrorText <> '' Then
      WriteLn('detail write-block ', ErrorText);
    Check('write-block accepted', WaitSession(mssAccepted, 2000) And WaitCarrier(mcsConnected, 2000));
    Check('receive window clamped', Assigned(Blocked.Socket) And ClampReceiveWindow(Blocked.Socket.Handle));
    Frame.Version := MonitorFrameVersion;
    Frame.Flags := 0;
    Frame.Json := LargePingJson;
    For I := 1 To 3 Do
      Check('queue blocked write ' + IntToStr(I), Lan.Send(Frame, ErrorText));
    If ErrorText <> '' Then
      WriteLn('detail queue ', ErrorText);
    SleepPump(1500);
    Check('want_write does not close', Blocked.StillOpen And (Lan.State = mcsConnected) And (Session.State = mssAccepted));
    Check('window released', Assigned(Blocked.Socket) And ReleaseReceiveWindow(Blocked.Socket.Handle));
    Check('blocked write delivers', Blocked.ReadMessage(After(4000), Message, ErrorText) And (Message.Kind = mmkPing));
    If ErrorText <> '' Then
      WriteLn('detail blocked read ', ErrorText);
    Check('never connecting', Not SawConnecting);
  Finally
    If Stall >= 0 Then
      CloseSocket(Stall);
    FreeAndNil(Probe);
    FreeAndNil(Partial);
    FreeAndNil(Blocked);
    FreeAndNil(Again);
    FreeAndNil(Spare);
    FreeAndNil(First);
  End;
End;

Begin
  {$IFDEF UNIX}
  fpSignal(SIGPIPE, signalhandler(SIG_IGN));
  {$ENDIF}
  FailCount := 0;
  SawConnecting := False;
  SettingsRoot := '';
  HostFingerprint := '';
  Lan := Nil;
  LanRef := Nil;
  Session := Nil;
  If Not EnsureOpenSSLReady(ErrorText) Then
    Begin
      WriteLn('FAIL OpenSSL ', ErrorText);
      WriteLn(StdErr, ErrorText);
      Halt(1);
    End;
  Try
    Try
      PrepareSettings;
      StartListener;
      If (FailCount = 0) And Assigned(Lan) And (Lan.BoundPort <> 0) Then
        RunChecks
      Else
        Check('listener ready for socket checks', False);
    Except
      On E: Exception Do
        Begin
          WriteLn('FAIL exception ', E.Message);
          Inc(FailCount);
        End;
    End;
  Finally
    StopListener;
    RemoveSettings;
  End;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantMonitorSocketTest tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantMonitorSocketTest test(s) failed.');
      Halt(1);
    End;
End.
