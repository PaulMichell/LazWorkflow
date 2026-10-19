Program AssistantMonitorAcceptance;

{ Loopback pairing through the LAN carrier (c) 2026 Michell Computing.

  No Interfaces unit. This program does not construct TProjectAssistantForm.
  The runner writes this binary with a temporary -FU and -FE, never under Source/.
  Certificate files are created under a temp settings directory. Loopback only.
  If EnsureOpenSSLReady fails, the process exits non-zero. That is a failure, not a skip.

  The in-memory command sink records send and stop. It does not call
  RemoteSubmit or RemoteStop.

  The twelve phone steps below are for a person after the phone is installed.
  This program does not execute them.

  1. Build and restart Lazarus. Confirm the Assistant menu gains Remote Monitor and that the assistant window still sends a local prompt with the listener disabled.
  2. Enable the listener on the private LAN address. Confirm LazWorkflow.json changes only the monitor section.
  3. Pair the phone. Confirm the snapshot shows the current mode, target caption, model, and the live transcript, and that the desktop selection does not move when the phone opens an older turn.
  4. Send from the phone while idle. Confirm the desktop transcript and the phone both show the user row and the streaming answer.
  5. Steer during the turn. Stop from the phone. Confirm the desktop ends in the same cancelled state StopStream already writes.
  6. Change mode from the phone while idle, and confirm a mode change is rejected while busy.
  7. Open the plan list, run Work on this for one actionable item in Build, and stop the plan agent from the phone.
  8. Run a prompt task that needs a note. Confirm a format task is disabled on the phone.
  9. With remote approval off, trigger an Ask-mode write tool. Confirm the phone shows one approval sheet with no Allow or Deny, the desktop dialog still decides, the sheet closes with reason desktop when the dialog returns, and a phone decision is rejected.
  10. Enable remote approval. Confirm Allow on the phone runs the tool and Deny does not. Then confirm Stop during a pending remote approval does not write, and an Allow that arrives after Stop does not write, including while a newer turn is running.
  11. Revoke the phone. Confirm the next connection fails auth.
  12. Stop the IDE. Confirm the phone shows Host closed and keeps the draft. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  BaseUnix, UnixType,
  {$ENDIF}
  Classes, SysUtils, SyncObjs, sockets, ssockets, openssl, fpopenssl, opensslsockets,
  AssistantMonitorLinkStubs,
  AssistantHttps, AssistantMonitorTls, AssistantMonitorLan, AssistantMonitorSession,
  AssistantMonitorCodec, AssistantMonitorFrames, AssistantMonitorCarrier,
  AssistantMonitorSettings, WorkflowSettings;

Type
  TCommandSink = Class
    Lock: TRTLCriticalSection;
    SendCount: Integer;
    StopCount: Integer;
    LastSendText: String;
    RemoteSubmitCalled: Boolean;
    RemoteStopCalled: Boolean;
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Handle(Kind: Integer; Const Id, PayloadJson: String);
    Function Sends: Integer;
    Function Stops: Integer;
    Function SendText: String;
    Function CalledForm: Boolean;
  End;

  TLoopClient = Class
    Socket: TInetSocket;
    Handler: TOpenSSLSocketHandler;
    Pending: RawByteString;
    Destructor Destroy; Override;
    Function Open(Port: Word; HandshakeMs: Integer; Out ErrorText: String): Boolean;
    Function WriteJson(Const Json: String; Deadline: QWord): Boolean;
    Function ReadMessage(Deadline: QWord; Out Message: TMonitorMessage; Out ErrorText: String): Boolean;
  End;

Var
  FailCount: Integer;
  Session: TMonitorSession;
  Lan: TMonitorLanCarrier;
  LanRef: IMonitorCarrier;
  Sink: TCommandSink;
  SettingsRoot: String;
  HostFingerprint: String;

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

Procedure Pump;
Begin
  CheckSynchronize(0);
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

Constructor TCommandSink.Create;
Begin
  Inherited Create;
  InitCriticalSection(Lock);
  SendCount := 0;
  StopCount := 0;
  LastSendText := '';
  RemoteSubmitCalled := False;
  RemoteStopCalled := False;
End;

Destructor TCommandSink.Destroy;
Begin
  DoneCriticalSection(Lock);
  Inherited Destroy;
End;

Procedure TCommandSink.Handle(Kind: Integer; Const Id, PayloadJson: String);
Var
  Text: String;
Begin
  EnterCriticalSection(Lock);
  Try
    If Kind = Ord(mmkSend) Then
      Begin
        Inc(SendCount);
        Text := '';
        If DecodeMonitorText(PayloadJson, Text) Then
          LastSendText := Text;
      End
    Else If Kind = Ord(mmkStop) Then
      Inc(StopCount);
  Finally
    LeaveCriticalSection(Lock);
  End;
End;

Function TCommandSink.Sends: Integer;
Begin
  EnterCriticalSection(Lock);
  Try
    Result := SendCount;
  Finally
    LeaveCriticalSection(Lock);
  End;
End;

Function TCommandSink.Stops: Integer;
Begin
  EnterCriticalSection(Lock);
  Try
    Result := StopCount;
  Finally
    LeaveCriticalSection(Lock);
  End;
End;

Function TCommandSink.SendText: String;
Begin
  EnterCriticalSection(Lock);
  Try
    Result := LastSendText;
  Finally
    LeaveCriticalSection(Lock);
  End;
End;

Function TCommandSink.CalledForm: Boolean;
Begin
  EnterCriticalSection(Lock);
  Try
    Result := RemoteSubmitCalled Or RemoteStopCalled;
  Finally
    LeaveCriticalSection(Lock);
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

Function TLoopClient.WriteJson(Const Json: String; Deadline: QWord): Boolean;
Var
  Bytes: RawByteString;
  Offset, Count, Err: Integer;
  Status: TMonitorFrameStatus;
Begin
  Result := False;
  If Not TryEncodeMonitorFrame(Json, Bytes, Status) Then
    Exit;
  If Not Assigned(Handler) Or Not Assigned(Handler.SSL) Then
    Exit;
  Offset := 1;
  While Offset <= Length(Bytes) Do
    Begin
      If GetTickCount64 >= Deadline Then
        Exit;
      Pump;
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
      Pump;
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

Function WaitSink(ExpectedSends, ExpectedStops: Integer; Ms: Integer): Boolean;
Var
  Deadline: QWord;
Begin
  Deadline := After(Ms);
  Repeat
    Pump;
    If (Sink.Sends >= ExpectedSends) And (Sink.Stops >= ExpectedStops) Then
      Exit(True);
    Sleep(20);
  Until GetTickCount64 >= Deadline;
  Result := (Sink.Sends >= ExpectedSends) And (Sink.Stops >= ExpectedStops);
End;

Function WaitSession(Expected: TMonitorSessionState; Ms: Integer): Boolean;
Var
  Deadline: QWord;
Begin
  Deadline := After(Ms);
  Repeat
    Pump;
    If Assigned(Session) And (Session.State = Expected) Then
      Exit(True);
    Sleep(20);
  Until GetTickCount64 >= Deadline;
  Result := Assigned(Session) And (Session.State = Expected);
End;

Function RepositoryRoot: String;
Var
  I: Integer;
  Probe, Dir: String;
Begin
  Result := '';
  Dir := GetCurrentDir;
  For I := 1 To 8 Do
    Begin
      If FileExists(IncludeTrailingPathDelimiter(Dir) + 'Tests' + PathDelim + 'AssistantMonitorAcceptance.lpr') And
        DirectoryExists(IncludeTrailingPathDelimiter(Dir) + 'Source') Then
        Exit(ExcludeTrailingPathDelimiter(Dir));
      Probe := ExpandFileName(IncludeTrailingPathDelimiter(Dir) + '..');
      If Probe = Dir Then
        Exit;
      Dir := Probe;
    End;
End;

Procedure CheckSourceStaysOffTheForm;
Var
  Root, Source, UsesText: String;
  UsesAt, ImplAt: Integer;
Begin
  Root := RepositoryRoot;
  Check('acceptance source found', Root <> '');
  If Root = '' Then
    Exit;
  Source := '';
  With TStringList.Create Do
    Try
      LoadFromFile(IncludeTrailingPathDelimiter(Root) + 'Tests' + PathDelim + 'AssistantMonitorAcceptance.lpr');
      Source := Text;
    Finally
      Free;
    End;
  Check('phone steps stay in the comment', Pos('12. Stop the IDE', Source) > 0);
  UsesAt := Pos('Uses', Source);
  ImplAt := Pos('Type', Source);
  If (UsesAt > 0) And (ImplAt > UsesAt) Then
    UsesText := Copy(Source, UsesAt, ImplAt - UsesAt)
  Else
    UsesText := '';
  Check('uses clause has no Interfaces unit', Pos('Interfaces', UsesText) = 0);
  Check('program does not construct the assistant form', Pos('TProjectAssistantForm' + '.Create', Source) = 0);
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
  SettingsRoot := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-monitor-accept-' + GUIDToString(Guid);
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
  Flags: TMonitorHostFlags;
  Server: TInetServer;
  Port: Word;
Begin
  Session := TMonitorSession.Create;
  Check('session listens', Session.StartListening('127.0.0.1', 0, ErrorText) And (Session.State = mssListening));
  If ErrorText <> '' Then
    WriteLn('detail session ', ErrorText);
  Flags := Default(TMonitorHostFlags);
  Flags.CanSend := True;
  Flags.CanStop := True;
  Session.SetHostFlags(Flags);
  Session.SetHostFingerprint(HostFingerprint);
  Session.RequestPairCode;
  Session.OnCommand := @Sink.Handle;
  Lan := TMonitorLanCarrier.Create('127.0.0.1', 0, MonitorCertificateFile, MonitorKeyFile);
  LanRef := Lan;
  Session.AttachCarrier(LanRef);
  Check('carrier starts', Lan.Start(ErrorText));
  If ErrorText <> '' Then
    WriteLn('detail carrier ', ErrorText);
  Server := Nil;
  If Assigned(Lan.ListenThread) Then
    Server := Lan.ListenThread.Server;
  Port := MonitorKernelPort(Server);
  Check('loopback port', (Port <> 0) And (Port = Lan.BoundPort));
  Check('listening', Lan.State = mcsListening);
End;

Procedure StopListener;
Begin
  If Assigned(Session) Then
    Session.OnCommand := Nil;
  If Assigned(Lan) Then
    Lan.Stop;
  If Assigned(Session) Then
    FreeAndNil(Session);
  Lan := Nil;
  LanRef := Nil;
End;

Procedure RunPairSendStop;
Var
  Client: TLoopClient;
  ErrorText, SendJson, StopJson: String;
  Message: TMonitorMessage;
  PairOk: TMonitorPairOk;
  Port: Word;
Begin
  Client := TLoopClient.Create;
  Try
    Port := 0;
    If Assigned(Lan) And Assigned(Lan.ListenThread) Then
      Port := MonitorKernelPort(Lan.ListenThread.Server);
    Check('client handshake', Client.Open(Port, 3000, ErrorText));
    If ErrorText <> '' Then
      WriteLn('detail handshake ', ErrorText);
    Check('accepted', WaitSession(mssAccepted, 2000));
    Check('hello', Client.WriteJson(EncodeMonitorHello('hello', 'Phone', '1', ''), After(2000)));
    Check('pair', Client.WriteJson(EncodeMonitorPair('pair', Session.PairCode, HostFingerprint), After(2000)));
    Check('pair_ok', Client.ReadMessage(After(3000), Message, ErrorText) And (Message.Kind = mmkPairOk));
    If ErrorText <> '' Then
      WriteLn('detail pair_ok ', ErrorText);
    Check('pair_ok payload', DecodeMonitorPairOk(Message.PayloadJson, PairOk) And (PairOk.ClientId <> '') And
      (PairOk.SessionToken <> ''));
    Check('session live', WaitSession(mssLive, 2000));
    Check('send encodes', TryEncodeMonitorSend('send-1', 'hello from the phone', SendJson, ErrorText));
    Check('send frame', Client.WriteJson(SendJson, After(2000)));
    Check('sink records send', WaitSink(1, 0, 3000));
    Check('send text', Sink.SendText = 'hello from the phone');
    StopJson := EncodeMonitorEmpty(mmkStop, 'stop-1');
    Check('stop frame', Client.WriteJson(StopJson, After(2000)));
    Check('sink records stop', WaitSink(1, 1, 3000));
    Check('sink does not call the form', Not Sink.CalledForm);
    Check('one send and one stop', (Sink.Sends = 1) And (Sink.Stops = 1));
  Finally
    Client.Free;
  End;
End;

Begin
  FailCount := 0;
  Session := Nil;
  Lan := Nil;
  LanRef := Nil;
  Sink := TCommandSink.Create;
  SettingsRoot := '';
  HostFingerprint := '';
  Try
    CheckSourceStaysOffTheForm;
    PrepareSettings;
    If FailCount = 0 Then
      Begin
        StartListener;
        If FailCount = 0 Then
          RunPairSendStop;
      End;
  Finally
    StopListener;
    Sink.Free;
    RemoveSettings;
  End;
  If FailCount = 0 Then
    WriteLn('AssistantMonitorAcceptance passed')
  Else
    WriteLn('AssistantMonitorAcceptance failed: ', FailCount);
  If FailCount <> 0 Then
    Halt(1);
End.
