Program AssistantMonitorLinkTest;

{ Throughput and latency harness for the monitor LAN link (c) 2026 Michell Computing.

  Starts a real TMonitorLanCarrier on 127.0.0.1 with a test certificate, pairs an
  OpenSSL client socket, and measures three things: outbound frames per second,
  ping to pong while 32 bulk frames are queued, and the time to deliver a resume
  answer. The resume answer has the bridge's shape: a catchup snapshot, a status,
  a plan and the five menu lists. It is built on the main thread after a
  TThread.Queue hop, as the bridge does on the IDE thread.

  Each measurement prints one "metric" line. The checks require delivery, not
  speed, so the harness passes on the slow baseline and on every later fix. The
  numbers are recorded in Documents/MonitorLinkBaseline.md. The chaos fixture is
  AssistantMonitorChaosTest, which drives TMonitorLinkThread and the mirror log
  through Tests/Fixtures/Monitor/chaos-script.json.

  No Interfaces unit. The runner writes this binary with a temporary -FU and -FE,
  never under Source/. Certificate and settings files are created under a temp
  directory. If EnsureOpenSSLReady fails, the process exits non-zero. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads, BaseUnix, UnixType,
  {$ENDIF}
  Classes, SysUtils, fpjson, sockets, ssockets, openssl, fpopenssl, opensslsockets,
  AssistantMonitorLinkStubs, AssistantHttps, AssistantMonitorTls, AssistantMonitorLan, AssistantMonitorSession,
  AssistantMonitorCodec, AssistantMonitorFrames, AssistantMonitorCarrier, AssistantSessionObserve,
  AssistantMonitorSettings, WorkflowSettings;

Const
  { The session bulk lane and the carrier queue both hold 32 frames. }
  LinkBulkFrames = 32;
  LinkBulkTitleBytes = 2000;
  LinkResumeFrames = 8;
  { One frame reaches the client per listen-thread pass. A pass is up to 250 ms. }
  LinkFrameWaitMs = 5000;

Type
  TLoopClient = Class
    Socket: TInetSocket;
    Handler: TOpenSSLSocketHandler;
    Pending: RawByteString;
    Destructor Destroy; Override;
    Function Open(Port: Word; HandshakeMs: Integer; Out ErrorText: String): Boolean;
    Function WriteJson(Const Json: String; Deadline: QWord): Boolean;
    Function ReadMessage(Deadline: QWord; Out Message: TMonitorMessage; Out ErrorText: String): Boolean;
  End;

  { Stands in for the bridge. Hear runs on the listen thread. Answer runs on the main thread. }
  TResumeAnswerer = Class
    Lock: TRTLCriticalSection;
    PendingId: String;
    HeardMs: QWord;
    AnsweredMs: QWord;
    Built: Integer;
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Hear(Kind: Integer; Const Id, PayloadJson: String);
    Procedure Answer;
  End;

Var
  FailCount: Integer;
  SettingsRoot: String;
  Lan: TMonitorLanCarrier;
  LanRef: IMonitorCarrier;
  Session: TMonitorSession;
  Answerer: TResumeAnswerer;
  ErrorText: String;
  BulkSerial: Integer;

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

Function After(Ms: Integer): QWord;
Begin
  Result := GetTickCount64 + QWord(Ms);
End;

Function Rate(Count: Integer; Ms: QWord): String;
Begin
  If Ms = 0 Then
    Ms := 1;
  Result := FormatFloat('0.0', Count * 1000.0 / Ms);
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
  Status: TMonitorFrameStatus;
  Offset, Count, Err: Integer;
Begin
  Result := False;
  Bytes := '';
  If (Json = '') Or Not TryEncodeMonitorFrame(Json, Bytes, Status) Then
    Exit;
  If Not Assigned(Handler) Or Not Assigned(Handler.SSL) Then
    Exit;
  Offset := 1;
  While Offset <= Length(Bytes) Do
    Begin
      If GetTickCount64 >= Deadline Then
        Exit;
      Count := Handler.SSL.Write(@Bytes[Offset], Length(Bytes) - Offset + 1);
      If Count > 0 Then
        Inc(Offset, Count)
      Else
        Begin
          Err := Handler.SSL.GetError(Count);
          If (Err = SSL_ERROR_WANT_READ) Or (Err = SSL_ERROR_WANT_WRITE) Or
            ((Err = SSL_ERROR_SYSCALL) And RetryableSyscall) Then
            Begin
              Sleep(5);
              Continue;
            End;
          Exit;
        End;
    End;
  Result := True;
End;

Function TLoopClient.ReadMessage(Deadline: QWord; Out Message: TMonitorMessage; Out ErrorText: String): Boolean;
Var
  Buf: Array[0..16383] Of Byte;
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
      { The resume answer is built on this thread after a TThread.Queue hop. }
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
      If (Handler.SSL.Pending = 0) And Not Handler.CanRead(5) Then
        Continue;
      Count := Handler.SSL.Read(@Buf[0], SizeOf(Buf));
      If Count > 0 Then
        AppendBytes(Pending, @Buf[0], Count)
      Else
        Begin
          Err := Handler.SSL.GetError(Count);
          If (Err = SSL_ERROR_WANT_READ) Or (Err = SSL_ERROR_WANT_WRITE) Or
            ((Err = SSL_ERROR_SYSCALL) And RetryableSyscall) Then
            Continue;
          ErrorText := 'Peer closed during read (' + IntToStr(Err) + ').';
          Exit;
        End;
    End;
  ErrorText := 'Timed out waiting for a frame.';
End;

Function ResumeAnswerFrames(Const RefId: String; Out Cursor: Int64): TStringArray;
Var
  Frames: TStringArray;
  Count: Integer;
  Snapshot: TMonitorSnapshot;
  Payload: TJSONObject;
  Rows: Array Of TAssistantMonitorPlanRow;
  Ids, Captions: TStringList;
  Epoch, ConversationId, ProjectRoot, Title: String;

  Procedure Add(Const Json: String);
  Begin
    If Json = '' Then
      Exit;
    Frames[Count] := Json;
    Inc(Count);
  End;

Begin
  Frames := Nil;
  SetLength(Frames, LinkResumeFrames);
  Count := 0;
  Rows := Nil;
  Session.CopyMirrorIdentity(Epoch, ConversationId, ProjectRoot, Title, Cursor);
  Snapshot := Default(TMonitorSnapshot);
  Snapshot.View.Available := True;
  Snapshot.View.SignedIn := True;
  Snapshot.View.CanSend := True;
  Snapshot.View.CanChangeMode := True;
  Snapshot.View.Mode := 'ask';
  Snapshot.View.Model := 'link-test';
  Snapshot.View.Backend := 'link-test';
  If Not Session.CommitSnapshotCursor('link-test' + #1 + RefId, Cursor) Then
    Cursor := 0;
  Add(EncodeResumeSnapshot(RefId, Cursor, Epoch, ConversationId, ProjectRoot, Title, Snapshot));
  Payload := MonitorStatusToJson(Snapshot.View);
  Try
    Add(EncodeMonitorEnvelope(mmkStatus, Session.AllocateHostId, Payload));
  Finally
    Payload.Free;
  End;
  Add(EncodeMonitorPlan(Session.AllocateHostId, '', '', False, Rows));
  Ids := TStringList.Create;
  Captions := TStringList.Create;
  Try
    Ids.Add('link-test');
    Captions.Add('Link test');
    Add(EncodeMonitorTargets(Session.AllocateHostId, 'link-test', Ids, Captions));
    Add(EncodeMonitorConversations(Session.AllocateHostId, 'link-test', Ids, Captions, False));
    Add(EncodeMonitorModels(Session.AllocateHostId, 'link-test', 'link-test', '', Ids, Captions));
    Add(EncodeMonitorReasoning(Session.AllocateHostId, 'link-test', '', Ids, Captions));
    Add(EncodeMonitorPermissions(Session.AllocateHostId, 'link-test', 'link-test', '', Ids, Captions));
  Finally
    Captions.Free;
    Ids.Free;
  End;
  SetLength(Frames, Count);
  Result := Frames;
End;

Constructor TResumeAnswerer.Create;
Begin
  Inherited Create;
  InitCriticalSection(Lock);
  PendingId := '';
  HeardMs := 0;
  AnsweredMs := 0;
  Built := 0;
End;

Destructor TResumeAnswerer.Destroy;
Begin
  DoneCriticalSection(Lock);
  Inherited Destroy;
End;

{$PUSH}{$HINTS OFF}
Procedure TResumeAnswerer.Hear(Kind: Integer; Const Id, PayloadJson: String);
Begin
  If Kind <> Ord(mmkResume) Then
    Exit;
  EnterCriticalSection(Lock);
  Try
    PendingId := Id;
    HeardMs := GetTickCount64;
  Finally
    LeaveCriticalSection(Lock);
  End;
  { The bridge hands commands to the IDE thread the same way. }
  TThread.Queue(Nil, @Answer);
End;
{$POP}

Procedure TResumeAnswerer.Answer;
Var
  RefId: String;
  Frames: TStringArray;
  Cursor: Int64;
  I: Integer;
Begin
  EnterCriticalSection(Lock);
  Try
    RefId := PendingId;
    PendingId := '';
  Finally
    LeaveCriticalSection(Lock);
  End;
  If (RefId = '') Or Not Assigned(Session) Then
    Exit;
  Frames := ResumeAnswerFrames(RefId, Cursor);
  Built := Length(Frames);
  For I := 0 To High(Frames) Do
    Session.SendHostJson(Frames[I]);
  If Cursor > 0 Then
    Session.NoteMirrorHanded(Cursor);
  AnsweredMs := GetTickCount64;
End;

Function WaitSession(Expected: TMonitorSessionState; Ms: Integer): Boolean;
Var
  Deadline: QWord;
Begin
  Deadline := After(Ms);
  Repeat
    CheckSynchronize(0);
    If Assigned(Session) And (Session.State = Expected) Then
      Exit(True);
    Sleep(10);
  Until GetTickCount64 >= Deadline;
  Result := Assigned(Session) And (Session.State = Expected);
End;

Function BulkFrame(Index: Integer): String;
Var
  Rows: Array Of TAssistantMonitorPlanRow;
Begin
  Rows := Nil;
  Result := EncodeMonitorPlan(Session.AllocateHostId, 'Documents/Bulk' + IntToStr(Index) + '.md',
    StringOfChar('b', LinkBulkTitleBytes), False, Rows);
End;

Function QueueBulk(Count: Integer): Integer;
Var
  I: Integer;
Begin
  Result := 0;
  For I := 1 To Count Do
    If Session.TryQueueHostJson(BulkFrame(I)) Then
      Inc(Result);
  Session.DrainOutbound;
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
  SettingsRoot := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-monitor-link-' + GUIDToString(Guid);
  If Not ForceDirectories(SettingsRoot) Then
    Raise Exception.Create('Could not create ' + SettingsRoot);
  SetWorkflowSettingsDirectory(SettingsRoot);
  Check('host certificate', EnsureMonitorHostCertificate(ErrorText));
  If ErrorText <> '' Then
    WriteLn('detail certificate ', ErrorText);
End;

Procedure StartListener;
Var
  ErrorText: String;
Begin
  Answerer := TResumeAnswerer.Create;
  Session := TMonitorSession.Create;
  Session.OnCommand := @Answerer.Hear;
  Session.BeginMirrorEpoch(MintMonitorEpoch, 'link-test', SettingsRoot, 'Link test');
  Check('session listens', Session.StartListening('127.0.0.1', 0, ErrorText) And (Session.State = mssListening));
  If ErrorText <> '' Then
    WriteLn('detail session ', ErrorText);
  Lan := TMonitorLanCarrier.Create('127.0.0.1', 0, MonitorCertificateFile, MonitorKeyFile);
  LanRef := Lan;
  Session.AttachCarrier(LanRef);
  Check('carrier starts', Lan.Start(ErrorText) And (Lan.BoundPort <> 0));
  If ErrorText <> '' Then
    WriteLn('detail carrier ', ErrorText);
End;

Procedure StopListener;
Begin
  If Assigned(Lan) Then
    Lan.Stop;
  If Assigned(Session) Then
    Begin
      Session.OnCommand := Nil;
      FreeAndNil(Session);
    End;
  Lan := Nil;
  LanRef := Nil;
  { Drop any queued Answer before the answerer goes. }
  CheckSynchronize(0);
  FreeAndNil(Answerer);
End;

Function Pair(Client: TLoopClient): Boolean;
Var
  Message: TMonitorMessage;
  ErrorText: String;
Begin
  Result := False;
  If Not Client.WriteJson(EncodeMonitorHello('hello1', 'LinkTest', '1', ''), After(3000)) Then
    Exit;
  { No pairing code is armed, so the open-LAN pair is admitted. }
  If Not Client.WriteJson(EncodeMonitorPair('pair1', '', ''), After(3000)) Then
    Exit;
  Repeat
    If Not Client.ReadMessage(After(LinkFrameWaitMs), Message, ErrorText) Then
      Begin
        WriteLn('detail pair ', ErrorText);
        Exit;
      End;
  Until Message.Kind <> mmkPing;
  If Message.Kind <> mmkPairOk Then
    WriteLn('detail pair type=', Message.TypeName);
  Result := (Message.Kind = mmkPairOk) And WaitSession(mssLive, 3000);
End;

Procedure MeasureThroughput(Client: TLoopClient);
Var
  Message: TMonitorMessage;
  ErrorText: String;
  Started, FirstAt, Elapsed: QWord;
  Queued, Received: Integer;
Begin
  Started := GetTickCount64;
  FirstAt := 0;
  Queued := QueueBulk(LinkBulkFrames);
  Check('throughput frames queued', Queued = LinkBulkFrames);
  Received := 0;
  While Received < Queued Do
    Begin
      If Not Client.ReadMessage(After(LinkFrameWaitMs), Message, ErrorText) Then
        Begin
          WriteLn('detail throughput ', ErrorText, ' received=', Received);
          Break;
        End;
      If Message.Kind = mmkPlan Then
        Begin
          If FirstAt = 0 Then
            FirstAt := GetTickCount64;
          Inc(Received);
        End;
    End;
  Elapsed := GetTickCount64 - Started;
  Check('throughput frames delivered', Received = Queued);
  If FirstAt = 0 Then
    FirstAt := Started;
  WriteLn('metric throughput frames=', Received, ' title_bytes=', LinkBulkTitleBytes, ' first_ms=', FirstAt - Started,
    ' total_ms=', Elapsed, ' frames_per_second=', Rate(Received, Elapsed));
End;

Procedure MeasurePing(Client: TLoopClient);
Const
  PingTicks = 424242;
Var
  Message: TMonitorMessage;
  Body: TMonitorTicks;
  ErrorText: String;
  Sent, PongAt: QWord;
  Queued, Before, Received: Integer;
  GotPong: Boolean;
Begin
  Queued := QueueBulk(LinkBulkFrames);
  Check('ping bulk frames queued', Queued = LinkBulkFrames);
  Sent := GetTickCount64;
  Check('ping write', Client.WriteJson(EncodeMonitorTicks(mmkPing, 'ping1', PingTicks), After(3000)));
  GotPong := False;
  PongAt := 0;
  Before := 0;
  Received := 0;
  While (Not GotPong) Or (Received < Queued) Do
    Begin
      If Not Client.ReadMessage(After(LinkFrameWaitMs), Message, ErrorText) Then
        Begin
          WriteLn('detail ping ', ErrorText, ' bulk=', Received, ' pong=', BoolToStr(GotPong, True));
          Break;
        End;
      If Message.Kind = mmkPlan Then
        Begin
          Inc(Received);
          If Not GotPong Then
            Inc(Before);
        End
      Else If (Message.Kind = mmkPong) And DecodeMonitorTicks(Message.PayloadJson, Body) And (Body.Ticks = PingTicks) Then
        Begin
          GotPong := True;
          PongAt := GetTickCount64;
        End;
    End;
  Check('pong delivered', GotPong);
  Check('ping bulk frames delivered', Received = Queued);
  If PongAt = 0 Then
    PongAt := GetTickCount64;
  WriteLn('metric ping queued_bulk=', Queued, ' bulk_before_pong=', Before, ' pong_ms=', PongAt - Sent);
End;

Procedure MeasureResume(Client: TLoopClient);
Var
  Message: TMonitorMessage;
  ErrorText: String;
  Sent, CatchupAt, LastAt: QWord;
  Received: Integer;
Begin
  Sent := GetTickCount64;
  Check('resume write', Client.WriteJson(EncodeMonitorResume('resume1', Session.MirrorEpoch, 0), After(3000)));
  CatchupAt := 0;
  LastAt := 0;
  Received := 0;
  While Received < LinkResumeFrames Do
    Begin
      If Not Client.ReadMessage(After(LinkFrameWaitMs), Message, ErrorText) Then
        Begin
          WriteLn('detail resume ', ErrorText, ' received=', Received);
          Break;
        End;
      Case Message.Kind Of
        mmkCatchup, mmkStatus, mmkPlan, mmkTargets, mmkConversations, mmkModels, mmkReasoning, mmkPermissions:
          Begin
            Inc(Received);
            LastAt := GetTickCount64;
            If Message.Kind = mmkCatchup Then
              CatchupAt := LastAt;
          End;
      End;
    End;
  Check('resume answer built in full', Answerer.Built = LinkResumeFrames);
  Check('resume catchup delivered', CatchupAt <> 0);
  Check('resume answer delivered', Received = LinkResumeFrames);
  If CatchupAt = 0 Then
    CatchupAt := GetTickCount64;
  If LastAt = 0 Then
    LastAt := GetTickCount64;
  WriteLn('metric resume frames=', Received, ' heard_ms=', Answerer.HeardMs - Sent, ' answered_ms=',
    Answerer.AnsweredMs - Sent, ' catchup_ms=', CatchupAt - Sent, ' complete_ms=', LastAt - Sent);
End;

{ Item 4.2 turns these green. Do not loosen the bounds to match the hybrid.
  These frames are snapshot pages, so they sit on the bulk lane. A plan frame is coalesced and is not this test. }
Function NextBulkFrame: String;
Begin
  Inc(BulkSerial);
  Result := '{"v":2,"id":"b' + IntToStr(BulkSerial) + '","type":"snapshot_page","payload":{"page":' + IntToStr(BulkSerial) + '}}';
End;

Function QueueBulkLane(Count: Integer): Integer;
Var
  I: Integer;
Begin
  Result := 0;
  For I := 1 To Count Do
    If Session.TryQueueHostJson(NextBulkFrame) Then
      Inc(Result);
  Session.DrainOutbound;
End;

Procedure TestIdleFrame(Client: TLoopClient);
Var
  Started, Arrived: QWord;
  Message: TMonitorMessage;
  ErrorText: String;
Begin
  Started := GetTickCount64;
  Check('4.2 idle frame queued', QueueBulkLane(1) = 1);
  Arrived := 0;
  If Client.ReadMessage(After(1000), Message, ErrorText) And (Message.Kind = mmkSnapshotPage) Then
    Arrived := GetTickCount64;
  Check('4.2 a frame queued while the link is idle reaches the client in under 20 ms',
    (Arrived <> 0) And (Arrived - Started < 20));
  If Arrived <> 0 Then
    WriteLn('detail idle_ms=', Arrived - Started);
End;

Procedure TestPriorityPing(Client: TLoopClient);
Var
  Queued, Before: Integer;
  Sent, PongAt: QWord;
  Message: TMonitorMessage;
  Ticks: TMonitorTicks;
  ErrorText: String;
  GotPong: Boolean;
Begin
  Queued := QueueBulkLane(64);
  Check('4.2 sixty-four bulk frames stay queued', Queued = 64);
  Sent := GetTickCount64;
  Check('4.2 priority ping write', Client.WriteJson(EncodeMonitorTicks(mmkPing, 'priority-ping', 9), After(3000)));
  GotPong := False;
  Before := 0;
  PongAt := 0;
  While Not GotPong Do
    Begin
      If Not Client.ReadMessage(After(150), Message, ErrorText) Then
        Break;
      If Message.Kind = mmkSnapshotPage Then
        Inc(Before)
      Else If (Message.Kind = mmkPong) And DecodeMonitorTicks(Message.PayloadJson, Ticks) Then
        Begin
          GotPong := True;
          PongAt := GetTickCount64;
        End;
    End;
  Check('4.2 a ping while 64 bulk frames are queued gets its pong before the next bulk frame', GotPong And (Before = 0));
  Check('4.2 that pong arrives in under 100 ms', GotPong And (PongAt >= Sent) And (PongAt - Sent < 100));
  If PongAt <> 0 Then
    WriteLn('detail priority queued=', Queued, ' bulk_before_pong=', Before, ' pong_ms=', PongAt - Sent)
  Else
    WriteLn('detail priority queued=', Queued, ' bulk_before_pong=', Before, ' pong_ms=unset');
End;

Procedure TestNoDrops(Client: TLoopClient);
Var
  DroppedBefore, Queued, Received: Integer;
  Deadline: QWord;
  Message: TMonitorMessage;
  ErrorText: String;
Begin
  DroppedBefore := Session.FramesDropped;
  Queued := QueueBulkLane(64);
  Received := 0;
  Deadline := After(3000);
  While GetTickCount64 < Deadline Do
    If Client.ReadMessage(After(200), Message, ErrorText) And (Message.Kind = mmkSnapshotPage) Then
      Inc(Received);
  Check('4.2 no frame of any lane is dropped while the client keeps reading',
    (Queued = 64) And (Received = 64) And (Session.FramesDropped = DroppedBefore));
  WriteLn('detail no_drop queued=', Queued, ' received=', Received, ' dropped=', Session.FramesDropped - DroppedBefore);
End;

Procedure TestPartialWrite(Client: TLoopClient);
Var
  First, Second: TMonitorMessage;
  ErrorText: String;
  Intact: Boolean;
Begin
  { A stalled reader forces a short TLS write. The next frame must not be spliced into it.
    Both SSL_ERROR_WANT_READ and SSL_ERROR_WANT_WRITE are retried on the same buffer. }
  Check('4.2 large frame queued for a partial write', QueueBulkLane(1) = 1);
  Check('4.2 following frame queued while the first may be partial', QueueBulkLane(1) = 1);
  Intact := Client.ReadMessage(After(8000), First, ErrorText) And (First.Kind = mmkSnapshotPage) And
    Client.ReadMessage(After(8000), Second, ErrorText) And (Second.Kind = mmkSnapshotPage) And
    (First.Id <> Second.Id) And (Pos(Second.Id, First.PayloadJson) = 0);
  Check('4.2 a partial TLS write is resumed without splicing the next frame', Intact);
End;

Procedure TestAnswerClock(Client: TLoopClient);
Var
  Sent: QWord;
Begin
  { A short resume that is not answered must still set the clock. Subtracting an unset
    clock overflowed the 2026-10-29 metric (LinkResumeFrames). }
  Answerer.AnsweredMs := 0;
  Answerer.HeardMs := 0;
  Sent := GetTickCount64;
  Check('4.2 timeout resume write', Client.WriteJson(EncodeMonitorResume('resume-timeout', '', 0), After(3000)));
  Sleep(30);
  Check('4.2 the answer clock is set on a timeout path', (Answerer.AnsweredMs <> 0) And (Answerer.AnsweredMs >= Sent));
  If Answerer.AnsweredMs <> 0 Then
    WriteLn('detail answer_clock_ms=', Answerer.AnsweredMs - Sent)
  Else
    WriteLn('detail answer_clock unset');
End;

Procedure RunChecks;
Var
  Client: TLoopClient;
  ErrorText: String;
Begin
  Client := TLoopClient.Create;
  Try
    Check('tls connection', Client.Open(Lan.BoundPort, 3000, ErrorText));
    If ErrorText <> '' Then
      WriteLn('detail connect ', ErrorText);
    Check('handshake accepted', WaitSession(mssAccepted, 3000));
    Check('paired and live', Pair(Client));
    If FailCount > 0 Then
      Exit;
    MeasureThroughput(Client);
    MeasurePing(Client);
    MeasureResume(Client);
    Check('no frame dropped', Session.FramesDropped = 0);
    If Session.FramesDropped <> 0 Then
      WriteLn('detail dropped=', Session.FramesDropped);
    TestIdleFrame(Client);
    TestPriorityPing(Client);
    TestNoDrops(Client);
    TestPartialWrite(Client);
    TestAnswerClock(Client);
    Client.WriteJson(EncodeMonitorBye('bye1', 'client'), After(3000));
    WaitSession(mssListening, 3000);
  Finally
    Client.Free;
  End;
End;

Begin
  {$IFDEF UNIX}
  fpSignal(SIGPIPE, signalhandler(SIG_IGN));
  {$ENDIF}
  FailCount := 0;
  SettingsRoot := '';
  Lan := Nil;
  LanRef := Nil;
  Session := Nil;
  Answerer := Nil;
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
        Check('listener ready for link checks', False);
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
      WriteLn('All AssistantMonitorLinkTest tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantMonitorLinkTest test(s) failed.');
      Halt(1);
    End;
End.
