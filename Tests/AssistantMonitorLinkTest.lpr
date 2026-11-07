Program AssistantMonitorLinkTest;

{ Throughput and latency harness for the monitor LAN link (c) 2026 Michell Computing.

  Starts a real TMonitorLanCarrier on 127.0.0.1 with a test certificate, pairs an
  OpenSSL client socket, and measures the catalogue 3 grain on that socket.
  A baseline resume is status, approval, snapshot_begin, one outline page, and
  snapshot_end. A tail resume is resume_ok and the events after the cursor.
  Slice latency includes the pump rule: the first change after a quiet period is
  queued at once, and a later change waits out the 20 ms coalesce, then
  ObserveTurn runs on the main thread through TThread.Queue. The form is not in
  this process. The link thread and the outbox wake are the real ones.

  Each measurement prints one "metric" line. Speed checks are the item 9.1
  budgets. The numbers are recorded in Documents/MonitorLinkBaseline.md.

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
  AssistantMonitorState, AssistantMonitorCommands, Classes, SysUtils, fpjson, sockets, ssockets, openssl, fpopenssl, opensslsockets,
  AssistantMonitorLinkStubs, AssistantHttps, AssistantMonitorTls, AssistantMonitorLan, AssistantMonitorSession,
  AssistantMonitorOutbox, AssistantMonitorCodec, AssistantMonitorFrames, AssistantMonitorCarrier, AssistantSessionObserve,
  AssistantMonitorSettings, AssistantMonitorMirror, AssistantMonitorSync, WorkflowSettings, WorkflowLog;

Const
  { Workload size for the harness, not a queue cap. }
  LinkBulkFrames = 32;
  LinkBulkTitleBytes = 2000;
  { snapshot_begin, snapshot_page, snapshot_end. State frames precede them. }
  LinkResumeFrames = 3;
  LinkSampleCount = 20;
  LinkCoalesceMs = 20;
  LinkCreditBodyBytes = 800 * 1024;
  LinkPlanBytes = 4 * 1024 * 1024 + 1;
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
    Procedure Hear(Kind: Integer; Const Id: String; Const PayloadJson: TMonitorPayload);
    Procedure Answer;
  End;

  { Main-thread observe, queued the way the pump is. Due is the coalesce deadline. }
  TSliceFire = Class
    Due: QWord;
    Body: String;
    Procedure Fire;
  End;

  { DebugLn has no output in this console program. Session and link log lines, such as why a link closed, are
    written as "log" lines so a failing run explains itself. }
  TLogEcho = Class
    Procedure Echo(Level: TWorkflowLogLevel; Const Area, Message: String);
  End;

Var
  FailCount: Integer;
  SettingsRoot: String;
  LiveBody: String;
  LastPump: QWord;
  LastAckSeq: Int64;
  Lan: TMonitorLanCarrier;
  LanRef: IMonitorCarrier;
  Session: TMonitorSession;
  Answerer: TResumeAnswerer;
  ErrorText: String;
  BulkSerial: Integer;
  LogEcho: TLogEcho;

Procedure TLogEcho.Echo(Level: TWorkflowLogLevel; Const Area, Message: String);
Begin
  WriteLn('log ', GetTickCount64, ' ', Ord(Level), ' [', Area, '] ', Message);
End;

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
  Mirror: TMonitorMirror;
  Source: TMonitorResumeSource;
  Status: TMonitorSyncStatus;
  Answer: TMonitorSyncAnswer;
  Epoch, ConversationId, ProjectRoot, Title: String;
  Index: Integer;
Begin
  Session.CopyMirrorIdentity(Epoch, ConversationId, ProjectRoot, Title, Cursor);
  Mirror := TMonitorMirror.Create;
  Try
    Mirror.BeginStream(Epoch, ConversationId, ProjectRoot, Title);
    Source := Default(TMonitorResumeSource);
    Mirror.CaptureResume('', Source);
    Status := Default(TMonitorSyncStatus);
    Answer := MonitorSyncResumeAnswer(Source, ConversationId, '', RefId, 0, Status);
    Cursor := Answer.Head;
    SetLength(Result, Length(Answer.Frames));
    For Index := 0 To High(Answer.Frames) Do
      Result[Index] := Answer.Frames[Index].Json;
  Finally
    Mirror.Free;
  End;
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
Procedure TResumeAnswerer.Hear(Kind: Integer; Const Id: String; Const PayloadJson: TMonitorPayload);
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
  { Set before the build. A resume that is not answered must not leave the clock unset. }
  AnsweredMs := GetTickCount64;
  Frames := ResumeAnswerFrames(RefId, Cursor);
  Built := Length(Frames);
  For I := 0 To High(Frames) Do
    Session.SendHostJson(Frames[I]);
  AnsweredMs := GetTickCount64;
End;

Function ClockDelta(Later, Earlier: QWord): String;
Begin
  If Later = 0 Then
    Result := 'unset'
  Else
    Result := IntToStr(Later - Earlier);
End;

Procedure TSliceFire.Fire;
Var
  Turn: TAssistantMonitorTurn;
Begin
  While GetTickCount64 < Due Do
    Sleep(1);
  Turn := Default(TAssistantMonitorTurn);
  Turn.TurnIndex := -2;
  Turn.Id := 'live';
  Turn.Live := True;
  Turn.Mode := 'ask';
  Turn.Prompt := 'link';
  Turn.PromptPreview := 'link';
  SetLength(Turn.Blocks, 1);
  Turn.Blocks[0].Kind := 'answer';
  Turn.Blocks[0].BlockId := 'live-block';
  Turn.Blocks[0].Body := Body;
  Turn.Blocks[0].Running := True;
  Turn.Blocks[0].Ok := True;
  If Assigned(Session) Then
    Session.ObserveTurn(Turn);
  LastPump := GetTickCount64;
End;

Function Percentile(Const Samples: Array Of QWord; Pct: Integer): QWord;
Var
  Sorted: Array Of QWord;
  Index, Rank, Hole: Integer;
  Value: QWord;
Begin
  Result := 0;
  If Length(Samples) = 0 Then
    Exit;
  SetLength(Sorted, Length(Samples));
  For Index := 0 To High(Samples) Do
    Sorted[Index] := Samples[Index];
  For Index := 1 To High(Sorted) Do
    Begin
      Value := Sorted[Index];
      Hole := Index;
      While (Hole > 0) And (Sorted[Hole - 1] > Value) Do
        Begin
          Sorted[Hole] := Sorted[Hole - 1];
          Dec(Hole);
        End;
      Sorted[Hole] := Value;
    End;
  Rank := (Pct * Length(Sorted) + 99) Div 100;
  If Rank < 1 Then
    Rank := 1;
  If Rank > Length(Sorted) Then
    Rank := Length(Sorted);
  Result := Sorted[Rank - 1];
End;

Function PayloadSeq(Const Json: String): Int64;
Var
  Token, Tail: String;
  At, EndAt: Integer;
Begin
  Result := 0;
  Token := '"seq":';
  At := Pos(Token, Json);
  If At = 0 Then
    Exit;
  Tail := Copy(Json, At + Length(Token), 24);
  EndAt := 1;
  While (EndAt <= Length(Tail)) And (Tail[EndAt] In ['0'..'9', '-']) Do
    Inc(EndAt);
  Result := StrToInt64Def(Copy(Tail, 1, EndAt - 1), 0);
End;

Procedure DrainClient(Client: TLoopClient; Ms: Integer);
Var
  Message: TMonitorMessage;
  ErrorText: String;
Begin
  While Client.ReadMessage(After(Ms), Message, ErrorText) Do;
End;

Procedure AckSeq(Client: TLoopClient; Seq: Int64);
Begin
  If (Seq < 1) Or Not Assigned(Session) Then
    Exit;
  If Seq > LastAckSeq Then
    LastAckSeq := Seq;
  Client.WriteJson('{"v":3,"id":"ack-' + IntToStr(Seq) + '","type":"ack","payload":{"stream_id":"' +
    Session.MirrorEpoch + '","seq":' + IntToStr(Seq) + '}}', After(1000));
End;

Procedure ObserveLive(Const Body: String);
Var
  Turn: TAssistantMonitorTurn;
Begin
  Turn := Default(TAssistantMonitorTurn);
  Turn.TurnIndex := -2;
  Turn.Id := 'live';
  Turn.Live := True;
  Turn.Mode := 'ask';
  Turn.Prompt := 'link';
  Turn.PromptPreview := 'link';
  SetLength(Turn.Blocks, 1);
  Turn.Blocks[0].Kind := 'answer';
  Turn.Blocks[0].BlockId := 'live-block';
  Turn.Blocks[0].Body := Body;
  Turn.Blocks[0].Running := True;
  Turn.Blocks[0].Ok := True;
  Session.ObserveTurn(Turn);
  LiveBody := Body;
End;

Procedure ObserveStored(Const TurnId, Body: String);
Var
  Turn: TAssistantMonitorTurn;
Begin
  Turn := Default(TAssistantMonitorTurn);
  Turn.TurnIndex := 0;
  Turn.Id := TurnId;
  Turn.Live := False;
  Turn.Mode := 'ask';
  Turn.Prompt := 'stored';
  Turn.PromptPreview := 'stored';
  SetLength(Turn.Blocks, 1);
  Turn.Blocks[0].Kind := 'answer';
  Turn.Blocks[0].BlockId := TurnId + '-block';
  Turn.Blocks[0].Body := Body;
  Turn.Blocks[0].Running := False;
  Turn.Blocks[0].Ok := True;
  Session.ObserveTurn(Turn);
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
Begin
  Result := '{"v":3,"id":"bulk-' + IntToStr(Index) + '","type":"snapshot_page","payload":{"page":' + IntToStr(Index) +
    ',"title":"' + StringOfChar('b', LinkBulkTitleBytes) + '"}}';
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
  Lan.AttachSession(Session);
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
  If Not Client.WriteJson(EncodeCommandHello('hello1', 'LinkTest', '1', ''), After(3000)) Then
    Exit;
  { No pairing code is armed, so the open-LAN pair is admitted. }
  If Not Client.WriteJson(EncodeCommandPair('pair1', '', ''), After(3000)) Then
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
      If Message.Kind = mmkSnapshotPage Then
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
  Check('ping write', Client.WriteJson(EncodeCommandTicks(mmkPing, 'ping1', PingTicks), After(3000)));
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
      If Message.Kind = mmkSnapshotPage Then
        Begin
          Inc(Received);
          If Not GotPong Then
            Inc(Before);
        End
      Else If (Message.Kind = mmkPong) And DecodeCommandTicks(Message.PayloadJson, Body) And (Body.Ticks = PingTicks) Then
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
  Check('resume write', Client.WriteJson(EncodeCommandResume('resume1', Session.MirrorEpoch, 0), After(3000)));
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
        mmkSnapshotPage, mmkStatus, mmkPlan, mmkTargets, mmkConversations, mmkModels, mmkReasoning, mmkPermissions:
          Begin
            Inc(Received);
            LastAt := GetTickCount64;
            If Message.Kind = mmkSnapshotPage Then
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
  WriteLn('metric resume frames=', Received, ' heard_ms=', ClockDelta(Answerer.HeardMs, Sent), ' answered_ms=',
    ClockDelta(Answerer.AnsweredMs, Sent), ' catchup_ms=', ClockDelta(CatchupAt, Sent), ' complete_ms=',
    ClockDelta(LastAt, Sent));
End;

{ Item 4.2 turns these green. Do not loosen the bounds to match the hybrid.
  These frames are snapshot pages, so they sit on the bulk lane. A plan frame is coalesced and is not this test. }
Function NextBulkFrame: String;
Begin
  Inc(BulkSerial);
  Result := '{"v":3,"id":"b' + IntToStr(BulkSerial) + '","type":"snapshot_page","payload":{"page":' + IntToStr(BulkSerial) + '}}';
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
  DrainClient(Client, 40);
  { Queue without waking, so the ping is in the socket before the first bulk write. }
  Queued := 0;
  For Before := 1 To 64 Do
    If Session.TryQueueHostJson(NextBulkFrame) Then
      Inc(Queued);
  Check('4.2 sixty-four bulk frames stay queued', Queued = 64);
  Sent := GetTickCount64;
  Check('4.2 priority ping write', Client.WriteJson(EncodeCommandTicks(mmkPing, 'priority-ping', 9), After(3000)));
  Session.DrainOutbound;
  GotPong := False;
  Before := 0;
  PongAt := 0;
  While Not GotPong Do
    Begin
      If Not Client.ReadMessage(After(150), Message, ErrorText) Then
        Break;
      If Message.Kind = mmkSnapshotPage Then
        Inc(Before)
      Else If (Message.Kind = mmkPong) And DecodeCommandTicks(Message.PayloadJson, Ticks) Then
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
  DroppedBefore, Queued, Received, FirstSerial, PageNo: Integer;
  Deadline: QWord;
  Message: TMonitorMessage;
  ErrorText: String;
Begin
  Session.DiscardUnsentBulk;
  While Client.ReadMessage(After(40), Message, ErrorText) Do;
  DroppedBefore := Session.FramesDropped;
  FirstSerial := BulkSerial + 1;
  Queued := QueueBulkLane(64);
  Received := 0;
  Deadline := After(3000);
  While GetTickCount64 < Deadline Do
    If Client.ReadMessage(After(200), Message, ErrorText) And (Message.Kind = mmkSnapshotPage) Then
      Begin
        PageNo := StrToIntDef(Copy(Message.Id, 2, 20), 0);
        If (PageNo >= FirstSerial) And (PageNo < FirstSerial + Queued) Then
          Inc(Received);
      End;
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
  Sent, Deadline: QWord;
Begin
  { A short resume that is not answered must still set the clock. Subtracting an unset
    clock overflowed the 2026-10-29 metric (LinkResumeFrames). }
  Answerer.AnsweredMs := 0;
  Answerer.HeardMs := 0;
  Sent := GetTickCount64;
  Check('4.2 timeout resume write', Client.WriteJson(EncodeCommandResume('resume-timeout', '', 0), After(3000)));
  Deadline := GetTickCount64 + 200;
  Repeat
    CheckSynchronize(1);
  Until (Answerer.AnsweredMs <> 0) Or (GetTickCount64 >= Deadline);
  Check('4.2 the answer clock is set on a timeout path', (Answerer.AnsweredMs <> 0) And (Answerer.AnsweredMs >= Sent));
  If Answerer.AnsweredMs <> 0 Then
    WriteLn('detail answer_clock_ms=', Answerer.AnsweredMs - Sent)
  Else
    WriteLn('detail answer_clock unset');
End;

Function ReadKind(Client: TLoopClient; Const TypeName: String; Deadline: QWord; Out Message: TMonitorMessage): Boolean;
Var
  ErrorText: String;
Begin
  Result := False;
  Message := Default(TMonitorMessage);
  While GetTickCount64 < Deadline Do
    Begin
      If Not Client.ReadMessage(Deadline, Message, ErrorText) Then
        Exit;
      If Message.TypeName = TypeName Then
        Exit(True);
      If Message.TypeName = 'event' Then
        AckSeq(Client, PayloadSeq(Message.PayloadJson));
      If (Message.Kind = mmkRejected) And (Message.Reason = 'busy') Then
        Exit;
    End;
End;

Procedure MeasureSliceLatency(Client: TLoopClient);
Var
  Samples: Array Of QWord;
  Index: Integer;
  Started, Arrived, Due: QWord;
  Fire: TSliceFire;
  Message: TMonitorMessage;
  ErrorText, Marker: String;
  Seen: Integer;
Begin
  SetLength(Samples, LinkSampleCount);
  Seen := 0;
  For Index := 1 To LinkSampleCount Do
    Begin
      Marker := 'slice-' + IntToStr(Index) + '-' + IntToStr(GetTickCount64);
      LiveBody := LiveBody + Marker;
      Started := GetTickCount64;
      If (LastPump = 0) Or (Started >= LastPump + LinkCoalesceMs) Then
        Due := Started
      Else
        Due := LastPump + LinkCoalesceMs;
      Fire := TSliceFire.Create;
      Fire.Due := Due;
      Fire.Body := LiveBody;
      { Queue from this thread runs the observe before the call returns. }
      TThread.Queue(Nil, @Fire.Fire);
      Session.DrainOutbound;
      Arrived := 0;
      While GetTickCount64 < Started + 1000 Do
        Begin
          If Not Client.ReadMessage(After(200), Message, ErrorText) Then
            Begin
              If Index = 1 Then
                WriteLn('detail slice read ', ErrorText);
              Break;
            End;
          If (Index = 1) And (Arrived = 0) And (Seen = 0) Then
            WriteLn('detail slice type=', Message.TypeName, ' id=', Message.Id);
          If Message.TypeName = 'event' Then
            Begin
              AckSeq(Client, PayloadSeq(Message.PayloadJson));
              If Pos(Marker, Message.PayloadJson) > 0 Then
                Begin
                  Arrived := GetTickCount64;
                  Break;
                End;
            End;
        End;
      Fire.Free;
      If Arrived = 0 Then
        Begin
          Samples[Index - 1] := 1000;
          Break;
        End;
      Samples[Index - 1] := Arrived - Started;
      Inc(Seen);
    End;
  If Seen < LinkSampleCount Then
    For Index := Seen + 1 To LinkSampleCount Do
      Samples[Index - 1] := 1000;
  Check('9.1 every slice sample reached the client', Seen = LinkSampleCount);
  Check('9.1 mirror change to slice read is under 150 ms at p95',
    (Seen = LinkSampleCount) And (Percentile(Samples, 95) < 150));
  WriteLn('metric slice samples=', LinkSampleCount, ' seen=', Seen, ' clock=GetTickCount64 coalesce_ms=',
    LinkCoalesceMs, ' p50=', Percentile(Samples, 50), ' p95=', Percentile(Samples, 95), ' p99=',
    Percentile(Samples, 99));
End;

Procedure MeasureStateLatency(Client: TLoopClient);
Var
  Samples: Array Of QWord;
  Index, Before: Integer;
  Started, Arrived: QWord;
  Message: TMonitorMessage;
  ErrorText, Key: String;
  Seen: Integer;
Begin
  SetLength(Samples, LinkSampleCount);
  Seen := 0;
  For Index := 1 To LinkSampleCount Do
    Begin
      Key := 'probe-' + IntToStr(Index);
      LiveBody := LiveBody + 's';
      ObserveLive(LiveBody);
      Started := GetTickCount64;
      Session.PublishState(Key, '{"n":' + IntToStr(Index) + '}');
      Session.DrainOutbound;
      Arrived := 0;
      Before := 0;
      While GetTickCount64 < Started + 500 Do
        Begin
          If Not Client.ReadMessage(After(100), Message, ErrorText) Then
            Begin
              If Index = 1 Then
                WriteLn('detail state read ', ErrorText, ' state=', Ord(Session.State));
              Break;
            End;
          If (Index = 1) And (Arrived = 0) Then
            WriteLn('detail state type=', Message.TypeName);
          If Message.TypeName = 'event' Then
            Begin
              Inc(Before);
              AckSeq(Client, PayloadSeq(Message.PayloadJson));
            End
          Else If (Message.TypeName = 'state') And (Pos(Key, Message.PayloadJson) > 0) Then
            Begin
              Arrived := GetTickCount64;
              Break;
            End;
        End;
      If Arrived = 0 Then
        Samples[Index - 1] := 500
      Else
        Begin
          Samples[Index - 1] := Arrived - Started;
          Inc(Seen);
        End;
      If Before > 8 Then
        WriteLn('detail state key=', Key, ' events_before=', Before);
    End;
  Check('9.1 every state sample reached the client', Seen = LinkSampleCount);
  Check('9.1 queued state to client read is under 50 ms at p95',
    (Seen = LinkSampleCount) And (Percentile(Samples, 95) < 50));
  WriteLn('metric state samples=', LinkSampleCount, ' seen=', Seen, ' clock=GetTickCount64 p50=',
    Percentile(Samples, 50), ' p95=', Percentile(Samples, 95), ' p99=', Percentile(Samples, 99));
End;

Function QueueFatFetches(Out Bytes: Int64): Integer;
Var
  Index: Integer;
  Frame: String;
Begin
  Result := 0;
  Bytes := 0;
  For Index := 1 To 120 Do
    Begin
      Frame := '{"v":3,"id":"fat-' + IntToStr(Index) + '","type":"snapshot_page","payload":{"page":' + IntToStr(Index) +
        ',"title":"' + StringOfChar('f', 20000) + '"}}';
      If Not Session.TryQueueHostJson(Frame) Then
        Break;
      Inc(Result);
      Inc(Bytes, Length(Frame));
    End;
End;

Procedure MeasureBulkPing(Client: TLoopClient; Const LabelName: String);
Var
  Message: TMonitorMessage;
  Ticks: TMonitorTicks;
  ErrorText: String;
  Sent, PongAt: QWord;
  Queued, Before: Integer;
  Bytes: Int64;
  GotPong: Boolean;
Begin
  LiveBody := LiveBody + StringOfChar('q', 4096);
  ObserveLive(LiveBody);
  Queued := QueueFatFetches(Bytes);
  Check(LabelName + ' at least 2 MiB of fetches are queued', Bytes >= 2 * 1024 * 1024);
  Sent := GetTickCount64;
  Check(LabelName + ' ping write', Client.WriteJson(EncodeCommandTicks(mmkPing, 'slices-ping', 77), After(3000)));
  Session.DrainOutbound;
  GotPong := False;
  Before := 0;
  PongAt := 0;
  While Not GotPong Do
    Begin
      If Not Client.ReadMessage(After(200), Message, ErrorText) Then
        Break;
      If (Message.TypeName = 'snapshot_page') Or (Message.TypeName = 'event') Or (Message.TypeName = 'plan_data') Then
        Begin
          Inc(Before);
          If Message.TypeName = 'event' Then
            AckSeq(Client, PayloadSeq(Message.PayloadJson));
        End
      Else If (Message.Kind = mmkPong) And DecodeCommandTicks(Message.PayloadJson, Ticks) And (Ticks.Ticks = 77) Then
        Begin
          GotPong := True;
          PongAt := GetTickCount64;
        End;
    End;
  Check(LabelName + ' pong is not after the queued frames', GotPong And (Before < Queued));
  Check(LabelName + ' pong is under 100 ms', GotPong And (PongAt >= Sent) And (PongAt - Sent < 100));
  If PongAt = 0 Then
    WriteLn('metric ', LabelName, ' queued=', Queued, ' bytes=', Bytes, ' before_pong=', Before, ' pong_ms=unset')
  Else
    WriteLn('metric ', LabelName, ' queued=', Queued, ' bytes=', Bytes, ' before_pong=', Before, ' pong_ms=',
      PongAt - Sent);
  DrainClient(Client, 30);
End;

Procedure MeasurePlanPing(Client: TLoopClient);
Var
  Path, ErrorText: String;
  Stream: TFileStream;
  Buffer: Array[0..8191] Of Byte;
  Left, Count: Integer;
  Message: TMonitorMessage;
  Ticks: TMonitorTicks;
  Sent, PongAt: QWord;
  Before, PlanFrames: Integer;
  GotPong, SawPlan: Boolean;
Begin
  Path := IncludeTrailingPathDelimiter(SettingsRoot) + 'Documents';
  ForceDirectories(Path);
  Path := Path + PathDelim + 'Big.md';
  FillChar(Buffer, SizeOf(Buffer), Ord('p'));
  Stream := TFileStream.Create(Path, fmCreate);
  Try
    Left := LinkPlanBytes;
    While Left > 0 Do
      Begin
        Count := SizeOf(Buffer);
        If Count > Left Then
          Count := Left;
        Stream.WriteBuffer(Buffer, Count);
        Dec(Left, Count);
      End;
  Finally
    Stream.Free;
  End;
  Check('9.1 plan file is larger than 4 MiB', FileExists(Path));
  Check('9.1 plan_get write', Client.WriteJson(
    '{"v":3,"id":"plan-get-1","type":"plan_get","payload":{"path":"Documents/Big.md","offset":0,"revision":"none"}}',
    After(3000)));
  SawPlan := False;
  PlanFrames := 0;
  While (Not SawPlan) And (PlanFrames < 4) Do
    Begin
      If Not Client.ReadMessage(After(3000), Message, ErrorText) Then
        Break;
      If Message.TypeName = 'plan_data' Then
        Begin
          SawPlan := True;
          Inc(PlanFrames);
        End;
    End;
  Check('9.1 plan_data is the bulk traffic', SawPlan);
  Sent := GetTickCount64;
  Check('9.1 plan ping write', Client.WriteJson(EncodeCommandTicks(mmkPing, 'plan-ping', 88), After(3000)));
  GotPong := False;
  Before := 0;
  PongAt := 0;
  While Not GotPong Do
    Begin
      If Not Client.ReadMessage(After(200), Message, ErrorText) Then
        Break;
      If Message.TypeName = 'plan_data' Then
        Inc(Before)
      Else If (Message.Kind = mmkPong) And DecodeCommandTicks(Message.PayloadJson, Ticks) And (Ticks.Ticks = 88) Then
        Begin
          GotPong := True;
          PongAt := GetTickCount64;
        End;
    End;
  Check('9.1 pong during plan_data is not after the transfer', GotPong And (Before < 100));
  Check('9.1 pong during a plan larger than 4 MiB is under 100 ms', GotPong And (PongAt >= Sent) And (PongAt - Sent < 100));
  If PongAt = 0 Then
    WriteLn('metric plan_ping plan_before_pong=', Before, ' pong_ms=unset clock=GetTickCount64')
  Else
    WriteLn('metric plan_ping plan_before_pong=', Before, ' pong_ms=', PongAt - Sent, ' clock=GetTickCount64');
  DrainClient(Client, 20);
  WriteLn('detail plan_ping sent=', Sent, ' done=', GetTickCount64);
End;

Procedure MeasureCreditPing(Client: TLoopClient);
Var
  Message: TMonitorMessage;
  Ticks: TMonitorTicks;
  ErrorText: String;
  Quiet, Sent, PongAt, Entered, QuietFrom: QWord;
  Events, QuietEvents, Others, QuietOthers: Integer;
  OtherType: String;
  GotPong: Boolean;
Begin
  Entered := GetTickCount64;
  LiveBody := LiveBody + StringOfChar('c', LinkCreditBodyBytes);
  ObserveLive(LiveBody);
  Events := 0;
  Quiet := 0;
  QuietEvents := 0;
  Others := 0;
  QuietOthers := 0;
  OtherType := '';
  Sent := GetTickCount64 + 2500;
  While GetTickCount64 < Sent Do
    Begin
      If Not Client.ReadMessage(After(80), Message, ErrorText) Then
        Begin
          If (Events > 20) And (Quiet <> 0) And (GetTickCount64 > Quiet + 200) Then
            Break;
          Continue;
        End;
      If Message.TypeName = 'event' Then
        Begin
          Inc(Events);
          Quiet := GetTickCount64;
        End
      Else
        Begin
          Inc(Others);
          OtherType := Message.TypeName;
        End;
    End;
  { A second quiet read confirms the window stopped the tail. }
  QuietFrom := GetTickCount64;
  While Client.ReadMessage(After(40), Message, ErrorText) Do
    If Message.TypeName = 'event' Then
      Inc(QuietEvents)
    Else
      Begin
        Inc(QuietOthers);
        OtherType := Message.TypeName;
      End;
  Check('9.1 an unacknowledged client stops inside the credit window', (Events > 0) And (Events < 400) And
    (QuietEvents = 0));
  WriteLn('detail credit before_ping state=', Ord(Session.State), ' events=', Events, ' dropped=', Session.FramesDropped,
    ' error=', Session.LastError, ' read=', ErrorText);
  WriteLn('detail credit timing entered=', Entered, ' quiet_from=', QuietFrom, ' now=', GetTickCount64, ' others=', Others,
    ' quiet_others=', QuietOthers, ' other_type=', OtherType);
  Sent := GetTickCount64;
  Check('9.1 credit ping write', Client.WriteJson(EncodeCommandTicks(mmkPing, 'credit-ping', 66), After(3000)));
  GotPong := False;
  PongAt := 0;
  While Not GotPong Do
    Begin
      If Not Client.ReadMessage(After(200), Message, ErrorText) Then
        Break;
      If (Message.Kind = mmkPong) And DecodeCommandTicks(Message.PayloadJson, Ticks) And (Ticks.Ticks = 66) Then
        Begin
          GotPong := True;
          PongAt := GetTickCount64;
        End;
    End;
  Check('9.1 ping is answered while the credit window is full', GotPong And (PongAt >= Sent) And (PongAt - Sent < 100));
  If Not GotPong Then
    WriteLn('detail credit no_pong state=', Ord(Session.State), ' dropped=', Session.FramesDropped, ' error=',
      Session.LastError, ' read=', ErrorText, ' last_type=', Message.TypeName);
  If PongAt = 0 Then
    WriteLn('metric credit events=', Events, ' quiet=', QuietEvents, ' pong_ms=unset')
  Else
    WriteLn('metric credit events=', Events, ' quiet=', QuietEvents, ' pong_ms=', PongAt - Sent, ' clock=GetTickCount64');
End;

Procedure MeasureTailResume(Client: TLoopClient; Out Head: Int64);
Var
  Message: TMonitorMessage;
  ErrorText: String;
  Sent, Answered: QWord;
  SawOk, SawBaseline: Boolean;
Begin
  Head := LastAckSeq;
  If Head < 1 Then
    Head := 0;
  DrainClient(Client, 30);
  ObserveLive(LiveBody + 'tail-near-head');
  Sent := GetTickCount64;
  Check('9.1 tail resume write',
    Client.WriteJson(EncodeCommandResume('resume-tail', Session.MirrorEpoch, Head), After(3000)));
  SawOk := False;
  SawBaseline := False;
  Answered := 0;
  While GetTickCount64 < Sent + 3000 Do
    Begin
      If Not Client.ReadMessage(After(200), Message, ErrorText) Then
        Break;
      If Message.TypeName = 'resume_ok' Then
        Begin
          SawOk := True;
          If Answered = 0 Then
            Answered := GetTickCount64;
        End
      Else If (Message.TypeName = 'snapshot_begin') Or (Message.TypeName = 'snapshot_page') Then
        SawBaseline := True
      Else If Message.TypeName = 'event' Then
        Begin
          If PayloadSeq(Message.PayloadJson) > Head Then
            Head := PayloadSeq(Message.PayloadJson);
          AckSeq(Client, PayloadSeq(Message.PayloadJson));
          If Pos('tail-near-head', Message.PayloadJson) > 0 Then
            Break;
        End;
    End;
  Check('9.1 resume near the head is resume_ok', SawOk And Not SawBaseline);
  Check('9.1 the tail resume clock is set', Answered <> 0);
  WriteLn('metric resume_tail frames_ok=', BoolToStr(SawOk, True), ' head=', Head, ' heard_ms=',
    ClockDelta(Answered, Sent), ' clock=GetTickCount64');
End;

Procedure MeasureBaselineResume(Client: TLoopClient);
Var
  Message: TMonitorMessage;
  ErrorText, Page: String;
  Sent, BeginAt, PageAt, EndAt: QWord;
  Frames, HashAt: Integer;
  Historical: String;
Begin
  Historical := 'HISTORICAL-BODY-9-1-' + StringOfChar('h', 80);
  DrainClient(Client, 30);
  ObserveStored('stored-hist', Historical);
  { Unacked events cannot be folded. Ack through a high sequence, then tighten the budget. }
  Check('9.1 fold ack write', Client.WriteJson('{"v":3,"id":"ack-fold","type":"ack","payload":{"stream_id":"' +
    Session.MirrorEpoch + '","seq":1000000}}', After(1000)));
  Sleep(50);
  DrainClient(Client, 80);
  Session.NoteMirrorAck(1000000);
  Session.SetMirrorLogBudget(256);
  ObserveStored('stored-fold', 'fold-a');
  ObserveStored('stored-more', 'fold-b');
  Check('9.1 the log has folded events the resume no longer holds', Session.MirrorDroppedThrough > 0);
  If Session.MirrorDroppedThrough = 0 Then
    WriteLn('detail dropped_through=0');
  Session.DiscardUnsentBulk;
  DrainClient(Client, 40);
  Sent := GetTickCount64;
  Check('9.1 baseline resume write', Client.WriteJson(EncodeCommandResume('resume-base', Session.MirrorEpoch, 0), After(3000)));
  Frames := 0;
  BeginAt := 0;
  PageAt := 0;
  EndAt := 0;
  HashAt := 0;
  Page := '';
  While EndAt = 0 Do
    Begin
      If Not Client.ReadMessage(After(LinkFrameWaitMs), Message, ErrorText) Then
        Begin
          WriteLn('detail baseline ', ErrorText, ' frames=', Frames, ' type=', Message.TypeName);
          Break;
        End;
      If Message.TypeName = 'resume_ok' Then
        WriteLn('detail baseline resume_ok');
      If (Message.TypeName = 'snapshot_begin') Or (Message.TypeName = 'snapshot_page') Or
        (Message.TypeName = 'snapshot_end') Then
        Begin
          Inc(Frames);
          If Message.TypeName = 'snapshot_begin' Then
            BeginAt := GetTickCount64;
          If Message.TypeName = 'snapshot_page' Then
            Begin
              PageAt := GetTickCount64;
              Page := Message.PayloadJson;
              HashAt := Pos('"hash"', Page);
            End;
          If Message.TypeName = 'snapshot_end' Then
            EndAt := GetTickCount64;
        End;
    End;
  Check('9.1 baseline answer built in full', Frames = LinkResumeFrames);
  Check('9.1 a dropped cursor is one baseline', (BeginAt <> 0) And (PageAt <> 0) And (EndAt <> 0) And (EndAt >= PageAt));
  Check('9.1 the baseline page has hashes and no historical body', (HashAt > 0) And (Pos(Historical, Page) = 0) And
    (Pos('HISTORICAL-BODY-9-1', Page) = 0));
  If (HashAt = 0) Or (Pos('HISTORICAL-BODY-9-1', Page) > 0) Then
    WriteLn('detail baseline page hash_at=', HashAt, ' body_at=', Pos('HISTORICAL-BODY-9-1', Page),
      ' page_bytes=', Length(Page));
  Check('9.1 the baseline resume clock is set', (BeginAt <> 0) And (EndAt >= Sent));
  WriteLn('metric resume_baseline frames=', Frames, ' expected=', LinkResumeFrames, ' begin_ms=', ClockDelta(BeginAt, Sent),
    ' page_ms=', ClockDelta(PageAt, Sent), ' end_ms=', ClockDelta(EndAt, Sent), ' clock=GetTickCount64');
End;
Procedure MeasureReplace(Client: TLoopClient);
Var
  Second: TLoopClient;
  Message: TMonitorMessage;
  Bye: TMonitorBye;
  ErrorText: String;
  SawBye, SawBusy: Boolean;
Begin
  Second := TLoopClient.Create;
  Try
    Check('9.1 second socket connects', Second.Open(Lan.BoundPort, 3000, ErrorText));
    If ErrorText <> '' Then
      WriteLn('detail replace ', ErrorText);
    SawBye := False;
    SawBusy := False;
    While Not SawBye Do
      Begin
        If Not Client.ReadMessage(After(2000), Message, ErrorText) Then
          Break;
        If Message.Kind = mmkBye Then
          Begin
            SawBye := DecodeCommandBye(Message.PayloadJson, Bye) And (Bye.Reason = 'replaced');
            If Not SawBye Then
              WriteLn('detail bye reason=', Message.Reason, ' payload=', String(Message.PayloadJson));
          End
        Else If (Message.Kind = mmkRejected) And (Message.Reason = 'busy') Then
          SawBusy := True;
      End;
    While Second.ReadMessage(After(200), Message, ErrorText) Do
      If (Message.Kind = mmkRejected) And (Message.Reason = 'busy') Then
        SawBusy := True;
    Check('9.1 the old link receives bye replaced', SawBye);
    Check('9.1 the new link reaches accepted', WaitSession(mssAccepted, 3000));
    Check('9.1 a second socket is not rejected busy', Not SawBusy);
    WriteLn('metric replace bye=', BoolToStr(SawBye, True), ' busy=', BoolToStr(SawBusy, True), ' state=',
      Ord(Session.State));
  Finally
    Second.Free;
  End;
End;

Procedure RunChecks;
Var
  Client: TLoopClient;
  Message: TMonitorMessage;
  ErrorText: String;
  Head: Int64;
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
    Check('no frame dropped', Session.FramesDropped = 0);
    If Session.FramesDropped <> 0 Then
      WriteLn('detail dropped=', Session.FramesDropped);
    TestIdleFrame(Client);
    TestPriorityPing(Client);
    TestNoDrops(Client);
    TestPartialWrite(Client);
    DrainClient(Client, 40);
    ObserveLive('open-lane');
    Check('9.1 log lane resume write', Client.WriteJson(EncodeCommandResume('resume-open', Session.MirrorEpoch, 0), After(3000)));
    If Not ReadKind(Client, 'resume_ok', After(3000), Message) Then
      Check('9.1 the open resume is resume_ok', False)
    Else
      Check('9.1 the open resume is resume_ok', True);
    DrainClient(Client, 40);
    MeasureSliceLatency(Client);
    MeasureStateLatency(Client);
    DrainClient(Client, 20);
    MeasureBulkPing(Client, '9.1 slices');
    MeasurePlanPing(Client);
    MeasureCreditPing(Client);
    MeasureTailResume(Client, Head);
    MeasureBaselineResume(Client);
    MeasureReplace(Client);
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
  LiveBody := '';
  LastPump := 0;
  LastAckSeq := 0;
  Lan := Nil;
  LanRef := Nil;
  Session := Nil;
  Answerer := Nil;
  LogEcho := TLogEcho.Create;
  If Assigned(WorkflowLogger) Then
    WorkflowLogger.OnLog := @LogEcho.Echo;
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
    {$IFDEF MONITOR_OUTBOX_METRICS}
    WriteLn('metric outbox locks=', MonitorOutboxLocks, ' frames=', MonitorOutboxFrames,
      ' locks/frame=', MonitorOutboxLocks / (MonitorOutboxFrames + Ord(MonitorOutboxFrames = 0)):0:2);
    {$ENDIF}
    RemoveSettings;
    If Assigned(WorkflowLogger) Then
      WorkflowLogger.OnLog := Nil;
    LogEcho.Free;
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
