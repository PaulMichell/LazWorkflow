Unit AssistantMonitorSession;

{ Monitor session state machine. The LAN carrier owns the socket.
  This unit does not use TInetServer. An in-memory carrier delivers frames
  through SetFrameHandler. No relay class is compiled. (c) 2026 Michell Computing.

  Open LAN admits pair when no code is armed. RequestPairCode still checks the
  code and fingerprint. Random, hex, and base64url are fphashutils. HMAC is
  fpsha256.TSHA256.HMAC. JSON stays in the codec. The pair code, session token,
  and HMAC are never logged.

  Threading: the carrier thread calls the frame handler under the session lock.
  The IDE thread calls the public setters and must not touch the socket. A ping
  goes out after MonitorHeartbeatMs with nothing sent, and the link is dead after
  MonitorDeadSessionMs with nothing received. Pong is answered on the control lane
  from the carrier thread. The phone's MonitorLimits holds the same two values.

  Size note: exceeds the 1000 line preference. Pairing, reconnect auth, command
  gates, approval, the in-memory carrier, the resume ring, and the outbound lanes
  are one state machine.
  Reviewed 2026-10-27: select_conversation is busy only while a reply is sending.
  No socket or form code in this unit. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, AssistantMonitorFrames, AssistantMonitorCarrier, AssistantMonitorCodec, AssistantMonitorMirror,
  AssistantMonitorOutbox, AssistantMonitorCommandIntake, AssistantSessionObserve;

Const
  MonitorPairCodeLength = 10;
  MonitorPairCodeTtlMs = 120000;
  MonitorPairFailureLimit = 3;
  MonitorNonceTtlMs = 30000;
  MonitorNonceBytes = 16;
  MonitorClientIdBytes = 16;
  MonitorSessionTokenBytes = 32;
  { Wire timing shared with the phone (MonitorLimits.HeartbeatSilenceMs and DeadSessionMs). }
  MonitorHeartbeatMs = 10000;
  MonitorDeadSessionMs = 30000;
  MonitorPartialFrameMs = 10000;
  MonitorCoalesceWindowMs = 100;
  { Bulk lane only. Control is not capped, and live holds one unsent patch part-set. }
  MonitorOutboundQueueLimit = 32;
  { Idle sweep. Resume is not a user command and is never answered host_busy here. }
  MonitorCommandWaitMs = 5000;
  { Kept so older tests compile. The log budget is MonitorLogBudgetBytes. }
  MonitorRingCapacity = 256;
  MonitorRingJsonCap = 2 * 1024 * 1024;
  MonitorCrockfordAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  MonitorServerName = 'LazAssistantMonitor';
  MonitorLogArea = 'AssistantMonitor';

Function MintMonitorEpoch: String;

Type
  TMonitorSessionState = (
    mssStopped,
    mssListening,
    mssAccepted,
    mssLive,
    mssBusy,
    mssRevoked
  );

  { Flags the command sink reports. Busy is Sending or PlanAgentRunning. }
  TMonitorHostFlags = Record
    Sending: Boolean;
    PlanAgentRunning: Boolean;
    CanSend: Boolean;
    CanSteer: Boolean;
    CanStop: Boolean;
    CanChangeMode: Boolean;
    ModeLocked: Boolean;
  End;

  { Listen-thread idle. Must return without waiting on the IDE thread. }
  TMonitorIdleHandler = Procedure Of Object;
  TMonitorCommandHandler = Procedure(Kind: Integer; Const Id, PayloadJson: String) Of Object;
  { The bridge writes approval_closed. Nil leaves a rejected decision silent. }
  TMonitorApprovalCloseHandler = Procedure(Const ToolId, Reason: String) Of Object;

  TMonitorSession = Class
  Private
    FLock: TRTLCriticalSection;
    FState: TMonitorSessionState;
    FCarrier: IMonitorCarrier;
    FOnCommand: TMonitorCommandHandler;
    FOnIdle: TMonitorIdleHandler;
    FOnApprovalClosed: TMonitorApprovalCloseHandler;
    FBindAddress: String;
    FPort: Integer;
    FHostFingerprint: String;
    FInstallationHostId: String;
    FHostFlags: TMonitorHostFlags;
    FRemoteApproval: Boolean;
    FPairCode: String;
    FPairCodeUntil: QWord;
    FPairFailures: Integer;
    FCodeExpired: Boolean;
    { True only after RequestPairCode, until that code succeeds. Open LAN admits a pair while this is false. }
    FPairGate: Boolean;
    FNonce: TBytes;
    FNonceHex: String;
    FNonceUntil: QWord;
    FNonceUsed: Boolean;
    FExpectPair: Boolean;
    FConnectionClientId: String;
    FClientName: String;
    FClientVersion: Integer;
    FCloseRequested: Boolean;
    FNowMs: QWord;
    FLastFrameMs: QWord;
    { Last frame the carrier accepted. Zero until this connection sends one. }
    LastSentMs: QWord;
    { When the last heartbeat ping was queued. A ping the carrier has not taken is not queued again. }
    PingQueuedMs: QWord;
    FPartialOpen: Boolean;
    FPartialSinceMs: QWord;
    FFramesSent: Integer;
    FFramesDropped: Integer;
    FLastError: String;
    FHostSeq: Integer;
    FToolExecuted: Boolean;
    FPendingApprovalId: String;
    FDisplayApprovalId: String;
    FClosedToolIds: Array Of String;
    FRevokedIds: Array Of String;
    FControlSends: Array Of String;
    FBulkSends: Array Of String;
    { Latest unsent plan. Replaced, not queued, so a status change is not dropped behind bulk. }
    FPlanSend: String;
    FHasPlanSend: Boolean;
    FOutbox: TMonitorOutbox;
    FIntake: TMonitorCommandIntake;
    FEpoch: String;
    FConversationId: String;
    FProjectRoot: String;
    FTitle: String;
    FCommittedCursor: Int64;
    FNextCursor: Int64;
    FReservedCursor: Int64;
    FReservedPayload: RawByteString;
    FReservedHanded: Boolean;
    FLiveFrames: Array Of String;
    FLiveCursor: Int64;
    FHasLivePatch: Boolean;
    FMirror: TMonitorMirror;
    FCredit: TMonitorLogCredit;
    FObserved: TMonitorSnapshot;
    FHasObserved: Boolean;
    FPendingCommand: Boolean;
    FPendingCommandKind: Integer;
    FPendingCommandId: String;
    FPendingCommandPayload: String;
    FPendingApprovalClose: Boolean;
    FPendingApprovalCloseId: String;
    FPendingApprovalCloseReason: String;
    FClients: Array Of Record
      Id: String;
      Name: String;
      Token: String;
      Fingerprint: String;
      PairedAt: String;
    End;
    Procedure LockSession;
    Procedure UnlockSession;
    Function ClockMs: QWord;
    Function NewHostId: String;
    { Caller holds the session lock. False when a bulk frame finds that lane full. }
    Function QueueSend(Const Json: String): Boolean;
    Procedure DrainSends;
    Function Transmit(Const Json: String): Boolean;
    Procedure LogLine(Level: Integer; Const Text: String);
    Procedure ClearConnection;
    Procedure RejectLocked(Const Reason: String; DoClose: Boolean);
    Procedure CloseToListening;
    Function IsRevoked(Const ClientId: String): Boolean;
    Function FindClient(Const ClientId: String): Integer;
    Procedure RememberRevoked(Const ClientId: String);
    Function PersistClients(Out ErrorText: String): Boolean;
    Procedure LoadClients;
    Function MintPairCode: String;
    Procedure DiscardPairCode(Expired: Boolean);
    Function PairCodeActive: Boolean;
    Function KindAllowedBeforeAuth(Kind: Integer): Boolean;
    Function Connected: Boolean;
    Procedure HandleLocked(Const Frame: TMonitorFrame);
    Procedure HandleHello(Const PayloadJson: String);
    Procedure HandlePair(Const PayloadJson: String);
    Procedure HandleAuth(Const PayloadJson: String);
    Procedure HandlePing(Const PayloadJson: String);
    Procedure HandleBye;
    Procedure HandleCommand(Kind: Integer; Const Id, PayloadJson: String);
    Procedure HandleResume(Const Id, PayloadJson: String);
    Function CommandStatesFor(Const Id: String; Const Commands: TStringArray): String;
    Procedure PublishCommandState(Const Id, State, Reason: String);
    Function ServeResumeFromMirror(Const Id: String; Const ResumeMsg: TMonitorResume): Boolean;
    Function ServeTurnFromMirror(Const Id, PayloadJson: String): Boolean;
    Procedure ServeBlockGet(Const Id, PayloadJson: String);
    Function LogFrameSeq(Const Json: String; Out Seq: Int64): Boolean;
    Procedure EnqueueAccepted(Const Json: String);
    { Caller holds the session lock. The previous unsent plan is counted as dropped. }
    Procedure StorePlanSend(Const Json: String);
    Procedure NoteLogAck(Const PayloadJson: String);
    Procedure ReleaseHeldLog;
    Procedure HandleApproval(Const PayloadJson: String);
    Function MirrorDroppedThrough: Int64;
    Function ApprovalRejectReason(Const ToolId: String): String;
    Function CommandBlocked(Kind: Integer; Out MessageText: String): Boolean;
    Procedure EnterBusy(Kind: Integer; Const Id, PayloadJson: String);
    Procedure AdoptRunningHost;
    Procedure QueueBulkFramesLocked(Const Frames: TStringArray);
    { Caller holds the session lock. Does not drain. }
    Function QueueMirrorPagesLocked(Const Id: String): Boolean;
    Procedure CheckTimeoutsLocked;
    Procedure InboundFrame(Const Frame: TMonitorFrame);
    Function GetLastError: String;
    Function GetBoundAddress: String;
    Function GetConnectedClientName: String;
    Procedure QueueCommand(Kind: Integer; Const Id, PayloadJson: String);
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure AttachCarrier(Const Carrier: IMonitorCarrier);
    Function StartListening(Const BindAddress: String; Port: Integer; Out ErrorText: String): Boolean;
    Procedure StopListening;
    { False fills RejectFrame for the spare socket. The controller is unchanged. }
    Function AcceptHandshake(Out RejectFrame: TMonitorFrame): Boolean;
    Procedure NoteSocketClosed;
    Procedure NotePartialFrame(Open: Boolean);
    Procedure NoteTime(NowMs: QWord);
    Procedure RequestPairCode;
    Function PairCode: String;
    Procedure SetHostFingerprint(Const Fingerprint: String);
    Procedure SetInstallationHostId(Const HostId: String);
    Procedure SetHostFlags(Const Flags: TMonitorHostFlags);
    Procedure SetRemoteApproval(Enabled: Boolean);
    Procedure RevokeClient(Const ClientId: String);
    Procedure RevokeAll;
    Procedure NoteTurnEnded;
    { New epoch. Cursor returns to zero. Safe from the IDE thread. }
    Procedure BeginMirrorEpoch(Const Epoch, ConversationId, ProjectRoot, Title: String);
    { Same conversation's stored epoch and cursor. The ring is empty, so resume snapshots. }
    Procedure RestoreMirror(Const Epoch, ConversationId, ProjectRoot, Title: String; Cursor: Int64);
    Function MirrorEpoch: String;
    Function MirrorCursor: Int64;
    { Same cursor while the bytes are unsent or already handed unchanged. }
    Function CommitMirrorCursor(Const Payload: RawByteString; Out Cursor: Int64): Boolean;
    Procedure NoteMirrorHanded(Cursor: Int64);
    /// Stores a handed patch. A record that does not fit is dropped and stated.
    Procedure RememberHandedPatch(Cursor: Int64; Const PatchJson: RawByteString);
    /// True when every cursor after the client is still a patch in the log. Does not read a form.
    Function TryResumeEvents(Const Epoch: String; Cursor: Int64; Out Catchup: TMonitorCatchup): Boolean;
    { IDE thread. Copies one turn into the model and appends the events that describe the change. }
    Procedure ObserveTurn(Const Turn: TAssistantMonitorTurn);
    Procedure ObservePlan(Const PlanPath, PlanTitle: String; PlanRunning: Boolean; Const Rows: Array Of TAssistantMonitorPlanRow);
    Function HasMirrorModel: Boolean;
    Function CopyMirrorTurns(Out Stored: TMonitorMirrorTurnArray; Out Live: TAssistantMonitorTurn; Out HasLive: Boolean): Boolean;
    Function FetchMirrorTurn(TurnIndex: Integer; Out Turn: TAssistantMonitorTurn): Boolean;
    Function BuildMirrorPages(Out Pages: TMonitorSnapshotPageArray): Boolean;
    { IDE thread. The connection thread copies this instead of reading the form. }
    Procedure ObserveSnapshot(Const Snapshot: TMonitorSnapshot);
    Function CopyObservedSnapshot(Out Snapshot: TMonitorSnapshot): Boolean;
    /// Copies the open epoch. False when none has been minted. Does not mint the next one.
    Function CopyClosedMirror(Out Closed: TMonitorConversationClosed): Boolean;
    Procedure CopyMirrorIdentity(Out Epoch, ConversationId, ProjectRoot, Title: String; Out Cursor: Int64);
    /// Next snapshot cursor. The caller sends the catchup, then NoteMirrorHanded.
    Function CommitSnapshotCursor(Const BodyStamp: RawByteString; Out Cursor: Int64): Boolean;
    { Replaces the unsent live part set. Does not append a transcript. }
    Procedure ReplaceLivePatch(Cursor: Int64; Const Frames: TStringArray);
    Procedure FlushLivePatch;
    /// Queues into the frame's lane and does not drain. False when bulk is already at the cap.
    Function TryQueueHostJson(Const Json: String): Boolean;
    /// Sends control, then the live part-set, then bulk. A full bulk lane does not block the others.
    Procedure DrainOutbound;
    /// Next host frame id. Safe to call off the session lock.
    Function AllocateHostId: String;
    /// Queues one host frame and drains it. Does not build the JSON.
    Procedure SendHostJson(Const Json: String);
    { Moves a recorded command and tells the phone. Unknown ids are ignored. }
    Procedure NoteCommandAccepted(Const Id: String);
    Procedure NoteCommandRejected(Const Id, Reason: String);
    Procedure NoteCommandDone(Const Id: String);
    Procedure SetApprovalCloseHandler(Handler: TMonitorApprovalCloseHandler);
    Procedure SetIdleHandler(Handler: TMonitorIdleHandler);
    /// Records a pending or display id. Does not send a frame.
    Procedure NoteApprovalRequested(Const ToolId: String; DecisionsAccepted: Boolean);
    /// Records a closed id. Does not send a frame.
    Procedure NoteApprovalClosed(Const ToolId: String);
    Procedure PublishDisplayApproval(Const ToolId, ToolName, Summary, ModeCaption: String);
    Procedure CloseDisplayApproval(Const ToolId: String);
    Function ApplyApprovalDecision(Const ToolId: String; Allow: Boolean): Boolean;
    Function BareApprovalSignalIsAllow: Boolean;
    Procedure NoteApprovalCancel(Const ToolId: String);
    Function ToolExecutionRecorded: Boolean;
    { Splits a payload into outbox chunk frames and queues every frame. Drains. }
    Procedure SendBulkPayload(Const ItemId, ItemType, PayloadJson: String);
    { Queues frames already split for the outbox. Drains. }
    Procedure SendPackedFrames(Const Frames: TStringArray);
    { One snapshot page for a turn the phone asked for. Does not send turn_data. }
    Procedure SendTurnPage(Const Id: String; Const Turn: TAssistantMonitorTurn);
    { Snapshot pages for the open model. False when the mirror has no stream. }
    Function SendMirrorPages(Const Id: String): Boolean;
    Property State: TMonitorSessionState Read FState;
    Property Carrier: IMonitorCarrier Read FCarrier;
    Property OnCommand: TMonitorCommandHandler Read FOnCommand Write FOnCommand;
    Property CloseRequested: Boolean Read FCloseRequested;
    Property FramesSent: Integer Read FFramesSent;
    Property FramesDropped: Integer Read FFramesDropped;
    Property LastError: String Read GetLastError;
    Property BoundAddress: String Read GetBoundAddress;
    Property BoundPort: Integer Read FPort;
    Property ConnectedClientName: String Read GetConnectedClientName;
    Property RemoteApproval: Boolean Read FRemoteApproval;
    Function SecondsSinceFrame: Integer;
  End;

  { In-memory double. The session's interface reference keeps it alive.
    It does not open a socket and it is not a relay. }
  TMonitorMemoryCarrier = Class(TInterfacedObject, IMonitorCarrier)
  Private
    FHandler: TMonitorFrameHandler;
    FState: TMonitorCarrierState;
    FSent: Array Of TMonitorFrame;
  Public
    Constructor Create;
    Function Start(Out ErrorText: String): Boolean;
    Procedure Stop;
    Function Send(Const Frame: TMonitorFrame; Out ErrorText: String): Boolean;
    Function State: TMonitorCarrierState;
    Procedure SetFrameHandler(Handler: TMonitorFrameHandler);
    Procedure DeliverJson(Const Json: String);
    Function SentCount: Integer;
    Function SentJson(Index: Integer): String;
    Procedure ClearSent;
  End;

{ HMAC-SHA256 of the raw nonce bytes, keyed by the stored token string. Lowercase hex. }
Function MonitorAuthMac(Const SessionToken, NonceHex: String): String;
{ False when the ring can answer. The caller must not fill a form snapshot on that path. }
Function ResumeNeedsFormSnapshot(Session: TMonitorSession; Const Epoch: String; Cursor: Int64): Boolean;
{ True when the idle sweep should answer host_busy. Resume stays queued until the IDE thread claims it. }
Function MonitorCommandSweepSendsBusy(Kind: Integer; Claimed, Finished: Boolean; AgeMs: QWord): Boolean;

Implementation

Uses
  SyncObjs, fpjson, jsonparser, fpsha256, fphashutils, WorkflowLog, AssistantMonitorSettings;

Function MonitorAuthMac(Const SessionToken, NonceHex: String): String;
Var
  Key, Msg, DigestBytes: TBytes;
  Digest: TSHA256Digest;
  Hex: AnsiString;
  I: Integer;
Begin
  Result := '';
  Key := Nil;
  Msg := Nil;
  DigestBytes := Nil;
  For I := 0 To High(Digest) Do
    Digest[I] := 0;
  If (SessionToken = '') Or (NonceHex = '') Then
    Exit;
  SetLength(Key, Length(SessionToken));
  If Length(Key) > 0 Then
    Move(SessionToken[1], Key[0], Length(Key));
  Msg := HexStrToBytes(NonceHex);
  If (Length(Key) = 0) Or (Length(Msg) = 0) Then
    Exit;
  If Not TSHA256.HMAC(@Key[0], Length(Key), @Msg[0], Length(Msg), Digest) Then
    Exit;
  SetLength(DigestBytes, SizeOf(Digest));
  For I := 0 To High(DigestBytes) Do
    DigestBytes[I] := Digest[I];
  Hex := BytesToHexStr(DigestBytes);
  Result := LowerCase(String(Hex));
End;

Function NormalizeHex(Const Text: String): String;
Var
  I: Integer;
  C: Char;
Begin
  Result := '';
  For I := 1 To Length(Text) Do
    Begin
      C := Text[I];
      If ((C >= '0') And (C <= '9')) Or ((C >= 'a') And (C <= 'f')) Or ((C >= 'A') And (C <= 'F')) Then
        Result := Result + LowerCase(C);
    End;
End;

Function RandomBytes(Count: Integer): TBytes;
Begin
  Result := Nil;
  SetLength(Result, 0);
  If Count <= 0 Then
    Exit;
  SetLength(Result, Count);
  If Not CryptoGetRandomBytes(@Result[0], Count) Then
    SetLength(Result, 0);
End;

Function MintMonitorEpoch: String;
Var
  Bytes: TBytes;
  Hex: AnsiString;
Begin
  Result := '';
  Bytes := RandomBytes(16);
  If Length(Bytes) <> 16 Then
    Exit;
  Hex := BytesToHexStr(Bytes);
  Result := LowerCase(String(Hex));
End;

Constructor TMonitorMemoryCarrier.Create;
Begin
  Inherited Create;
  FState := mcsIdle;
  FHandler := Nil;
  SetLength(FSent, 0);
End;

Function TMonitorMemoryCarrier.Start(Out ErrorText: String): Boolean;
Begin
  ErrorText := '';
  FState := mcsListening;
  Result := True;
End;

Procedure TMonitorMemoryCarrier.Stop;
Begin
  FState := mcsClosed;
  FHandler := Nil;
End;

Function TMonitorMemoryCarrier.Send(Const Frame: TMonitorFrame; Out ErrorText: String): Boolean;
Begin
  ErrorText := '';
  SetLength(FSent, Length(FSent) + 1);
  FSent[High(FSent)] := Frame;
  If FState = mcsListening Then
    FState := mcsConnected;
  Result := True;
End;

Function TMonitorMemoryCarrier.State: TMonitorCarrierState;
Begin
  Result := FState;
End;

Procedure TMonitorMemoryCarrier.SetFrameHandler(Handler: TMonitorFrameHandler);
Begin
  FHandler := Handler;
End;

Procedure TMonitorMemoryCarrier.DeliverJson(Const Json: String);
Var
  Frame: TMonitorFrame;
Begin
  If Not Assigned(FHandler) Then
    Exit;
  Frame.Version := MonitorFrameVersion;
  Frame.Flags := 0;
  Frame.Json := Json;
  FHandler(Frame);
End;

Function TMonitorMemoryCarrier.SentCount: Integer;
Begin
  Result := Length(FSent);
End;

Function TMonitorMemoryCarrier.SentJson(Index: Integer): String;
Begin
  Result := '';
  If (Index < 0) Or (Index > High(FSent)) Then
    Exit;
  Result := FSent[Index].Json;
End;

Procedure TMonitorMemoryCarrier.ClearSent;
Begin
  SetLength(FSent, 0);
End;

Constructor TMonitorSession.Create;
Begin
  Inherited Create;
  InitCriticalSection(FLock);
  FMirror := TMonitorMirror.Create;
  FCredit := TMonitorLogCredit.Create;
  FOutbox := TMonitorOutbox.Create;
  FIntake := TMonitorCommandIntake.Create;
  FObserved := Default(TMonitorSnapshot);
  FHasObserved := False;
  FState := mssStopped;
  FCarrier := Nil;
  FOnCommand := Nil;
  FOnIdle := Nil;
  FOnApprovalClosed := Nil;
  FPendingApprovalClose := False;
  FBindAddress := '';
  FPort := 0;
  FHostFingerprint := '';
  FRemoteApproval := False;
  FPairCode := '';
  FPairCodeUntil := 0;
  FPairFailures := 0;
  FCodeExpired := False;
  FPairGate := False;
  SetLength(FNonce, 0);
  FNonceHex := '';
  FNonceUntil := 0;
  FNonceUsed := False;
  FExpectPair := False;
  FConnectionClientId := '';
  FClientName := '';
  FClientVersion := 0;
  FCloseRequested := False;
  FNowMs := 0;
  FLastFrameMs := 0;
  LastSentMs := 0;
  PingQueuedMs := 0;
  FPartialOpen := False;
  FPartialSinceMs := 0;
  FFramesSent := 0;
  FFramesDropped := 0;
  FLastError := '';
  FHostSeq := 0;
  FToolExecuted := False;
  FPendingCommand := False;
  FPendingCommandKind := 0;
  FPendingCommandId := '';
  FPendingCommandPayload := '';
  FPendingApprovalId := '';
  FDisplayApprovalId := '';
  SetLength(FClosedToolIds, 0);
  SetLength(FRevokedIds, 0);
  SetLength(FControlSends, 0);
  SetLength(FBulkSends, 0);
  FPlanSend := '';
  FHasPlanSend := False;
  FEpoch := '';
  FConversationId := '';
  FInstallationHostId := '';
  FProjectRoot := '';
  FTitle := '';
  FCommittedCursor := 0;
  FNextCursor := 0;
  FReservedCursor := 0;
  FReservedPayload := '';
  FReservedHanded := False;
  FHasLivePatch := False;
  FLiveCursor := 0;
  SetLength(FLiveFrames, 0);
  SetLength(FClients, 0);
  FHostFlags.Sending := False;
  FHostFlags.PlanAgentRunning := False;
  FHostFlags.CanSend := False;
  FHostFlags.CanSteer := False;
  FHostFlags.CanStop := False;
  FHostFlags.CanChangeMode := False;
  FHostFlags.ModeLocked := False;
End;

Destructor TMonitorSession.Destroy;
Begin
  AttachCarrier(Nil);
  FreeAndNil(FIntake);
  FreeAndNil(FOutbox);
  FreeAndNil(FCredit);
  FreeAndNil(FMirror);
  DoneCriticalSection(FLock);
  Inherited Destroy;
End;

Procedure TMonitorSession.LockSession;
Begin
  EnterCriticalSection(FLock);
End;

Procedure TMonitorSession.UnlockSession;
Begin
  LeaveCriticalSection(FLock);
End;

Function TMonitorSession.ClockMs: QWord;
Begin
  If FNowMs <> 0 Then
    Result := FNowMs
  Else
    Result := GetTickCount64;
End;

Function TMonitorSession.NewHostId: String;
Begin
  Inc(FHostSeq);
  Result := 'h' + IntToStr(FHostSeq);
End;

Type
  TOutboundLane = (olControl, olLive, olPlan, olBulk);

Function OutboundLane(Const Json: String): TOutboundLane;
Var
  Message: TMonitorMessage;
  ErrorText: String;
Begin
  { An unreadable frame stays on control so it is not dropped. }
  Result := olControl;
  If Not TryDecodeMonitorEnvelope(Json, Message, ErrorText) Then
    Exit;
  Case Message.Kind Of
    mmkPatch:
      Result := olLive;
    { After control, so a pong is not stuck behind it, and before bulk, so a status
      change is not stuck behind pages or images. A full control lane must not hold it. }
    mmkPlan:
      Result := olPlan;
    mmkSnapshot, mmkTranscript, mmkCatchup, mmkImageData, mmkSnapshotPage, mmkChunk:
      Result := olBulk;
  Else
    Result := olControl;
  End;
End;

Function TMonitorSession.LogFrameSeq(Const Json: String; Out Seq: Int64): Boolean;
Var
  Data: TJSONData;
  Root, Payload: TJSONObject;
  TypeName: String;
Begin
  Result := False;
  Seq := 0;
  Data := Nil;
  Try
    Data := GetJSON(Json);
  Except
    Data := Nil;
  End;
  If Not (Data Is TJSONObject) Then
    Begin
      Data.Free;
      Exit;
    End;
  Root := TJSONObject(Data);
  Try
    TypeName := Root.Get('type', '');
    If (TypeName <> 'patch') And (TypeName <> 'event') Then
      Exit;
    If Not (Root.Find('payload') Is TJSONObject) Then
      Exit;
    Payload := TJSONObject(Root.Find('payload'));
    If TypeName = 'patch' Then
      Seq := Payload.Get('cursor', Int64(0))
    Else
      Seq := Payload.Get('seq', Int64(0));
    Result := Seq > 0;
  Finally
    Data.Free;
  End;
End;

Procedure TMonitorSession.StorePlanSend(Const Json: String);
Begin
  If FHasPlanSend Then
    Inc(FFramesDropped);
  FPlanSend := Json;
  FHasPlanSend := True;
End;

Procedure TMonitorSession.EnqueueAccepted(Const Json: String);
Var
  Index: Integer;
  Lane: TOutboundLane;
Begin
  If Json = '' Then
    Exit;
  Lane := OutboundLane(Json);
  If Lane = olLive Then
    Begin
      SetLength(FLiveFrames, 1);
      FLiveFrames[0] := Json;
      FHasLivePatch := True;
      Exit;
    End;
  If Lane = olPlan Then
    Begin
      StorePlanSend(Json);
      Exit;
    End;
  If Lane = olBulk Then
    Begin
      If Length(FBulkSends) >= MonitorOutboundQueueLimit Then
        Begin
          QueueSend(EncodeMonitorBye(NewHostId, 'protocol'));
          Exit;
        End;
      Index := Length(FBulkSends);
      SetLength(FBulkSends, Index + 1);
      FBulkSends[Index] := Json;
      Exit;
    End;
  Index := Length(FControlSends);
  SetLength(FControlSends, Index + 1);
  FControlSends[Index] := Json;
End;

Procedure TMonitorSession.ReleaseHeldLog;
Var
  Seq: Int64;
  Json: String;
Begin
  If Not Assigned(FCredit) Then
    Exit;
  While FCredit.TakeHeld(Seq, Json) Do
    Begin
      If Not FCredit.CanSend(Length(Json)) Then
        Begin
          FCredit.Hold(Seq, Json);
          Exit;
        End;
      FCredit.NoteSent(Seq, Length(Json));
      EnqueueAccepted(Json);
    End;
End;

Procedure TMonitorSession.NoteLogAck(Const PayloadJson: String);
Var
  Data: TJSONData;
  Obj: TJSONObject;
  StreamId: String;
  Seq: Int64;
Begin
  Data := Nil;
  Try
    Data := GetJSON(PayloadJson);
  Except
    Data := Nil;
  End;
  If Not (Data Is TJSONObject) Then
    Begin
      Data.Free;
      Exit;
    End;
  Obj := TJSONObject(Data);
  Try
    StreamId := Obj.Get('stream_id', '');
    Seq := 0;
    If Assigned(Obj.Find('seq')) And (Obj.Find('seq').JSONType = jtNumber) Then
      Seq := Obj.Find('seq').AsInt64;
  Finally
    Data.Free;
  End;
  If (StreamId = '') Or (Seq < 0) Then
    Exit;
  If Assigned(FMirror) Then
    FMirror.NoteAck(StreamId, Seq);
  If Assigned(FCredit) Then
    FCredit.NoteAck(Seq);
  ReleaseHeldLog;
End;

Function TMonitorSession.QueueSend(Const Json: String): Boolean;
Var
  Index: Integer;
  Lane: TOutboundLane;
  Seq: Int64;
Begin
  Result := False;
  If Json = '' Then
    Exit;
  If LogFrameSeq(Json, Seq) And Assigned(FCredit) Then
    Begin
      If Not FCredit.CanSend(Length(Json)) Then
        Begin
          FCredit.Hold(Seq, Json);
          If FCredit.HeldBytes > MonitorLogBudgetBytes Then
            EnqueueAccepted(EncodeMonitorBye(NewHostId, 'protocol'));
          Result := True;
          Exit;
        End;
      FCredit.NoteSent(Seq, Length(Json));
    End;
  Lane := OutboundLane(Json);
  If Lane = olLive Then
    Begin
      If FHasLivePatch Then
        Inc(FFramesDropped, Length(FLiveFrames));
      SetLength(FLiveFrames, 1);
      FLiveFrames[0] := Json;
      FLiveCursor := 0;
      FHasLivePatch := True;
      Result := True;
      Exit;
    End;
  If Lane = olPlan Then
    Begin
      StorePlanSend(Json);
      Result := True;
      Exit;
    End;
  If Lane = olBulk Then
    Begin
      If Length(FBulkSends) >= MonitorOutboundQueueLimit Then
        Begin
          Inc(FFramesDropped);
          Exit;
        End;
      Index := Length(FBulkSends);
      SetLength(FBulkSends, Index + 1);
      FBulkSends[Index] := Json;
      Result := True;
      Exit;
    End;
  Index := Length(FControlSends);
  SetLength(FControlSends, Index + 1);
  FControlSends[Index] := Json;
  Result := True;
End;

Function TMonitorSession.Transmit(Const Json: String): Boolean;
Var
  Frame: TMonitorFrame;
  ErrorText: String;
Begin
  Result := False;
  If (Json = '') Or (Not Assigned(FCarrier)) Then
    Exit;
  Frame.Version := MonitorFrameVersion;
  Frame.Flags := 0;
  Frame.Json := Json;
  If FCarrier.Send(Frame, ErrorText) Then
    Begin
      LockSession;
      Try
        Inc(FFramesSent);
        LastSentMs := ClockMs;
      Finally
        UnlockSession;
      End;
      Result := True;
    End
  Else
    Begin
      LockSession;
      Try
        FLastError := ErrorText;
      Finally
        UnlockSession;
      End;
    End;
End;

Function TMonitorSession.GetLastError: String;
Begin
  LockSession;
  Try
    Result := FLastError;
  Finally
    UnlockSession;
  End;
End;

Function TMonitorSession.GetBoundAddress: String;
Begin
  LockSession;
  Try
    Result := FBindAddress;
  Finally
    UnlockSession;
  End;
End;

Function TMonitorSession.GetConnectedClientName: String;
Begin
  LockSession;
  Try
    Result := FClientName;
  Finally
    UnlockSession;
  End;
End;

Procedure PrependUnsent(Var Lane: TStringArray; Const Frames: TStringArray; FromIndex: Integer);
Var
  Extra, Count, Index: Integer;
  Kept: TStringArray;
Begin
  Kept := Nil;
  Extra := Length(Frames) - FromIndex;
  If Extra <= 0 Then
    Exit;
  Count := Length(Lane);
  SetLength(Kept, Count + Extra);
  For Index := 0 To Extra - 1 Do
    Kept[Index] := Frames[FromIndex + Index];
  For Index := 0 To Count - 1 Do
    Kept[Extra + Index] := Lane[Index];
  Lane := Kept;
End;

Procedure TMonitorSession.DrainSends;
Var
  Control, Live, Bulk: TStringArray;
  Plan: String;
  Cursor: Int64;
  HadLive, HadPlan: Boolean;
  Index, Sent: Integer;
Begin
  LockSession;
  Try
    Control := FControlSends;
    SetLength(FControlSends, 0);
  Finally
    UnlockSession;
  End;
  Sent := 0;
  While Sent < Length(Control) Do
    Begin
      If Not Transmit(Control[Sent]) Then
        Break;
      Inc(Sent);
    End;
  If Sent < Length(Control) Then
    Begin
      LockSession;
      Try
        PrependUnsent(FControlSends, Control, Sent);
      Finally
        UnlockSession;
      End;
      Exit;
    End;
  LockSession;
  Try
    HadLive := FHasLivePatch;
    Live := FLiveFrames;
    Cursor := FLiveCursor;
    FHasLivePatch := False;
    FLiveCursor := 0;
    SetLength(FLiveFrames, 0);
  Finally
    UnlockSession;
  End;
  If HadLive Then
    Begin
      Sent := 0;
      While Sent < Length(Live) Do
        Begin
          If Not Transmit(Live[Sent]) Then
            Break;
          Inc(Sent);
        End;
      If Sent < Length(Live) Then
        Begin
          LockSession;
          Try
            If FHasLivePatch Then
              Inc(FFramesDropped, Length(Live) - Sent)
            Else
              Begin
                SetLength(FLiveFrames, Length(Live) - Sent);
                For Index := 0 To High(FLiveFrames) Do
                  FLiveFrames[Index] := Live[Sent + Index];
                FLiveCursor := Cursor;
                FHasLivePatch := Length(FLiveFrames) > 0;
              End;
          Finally
            UnlockSession;
          End;
          Exit;
        End;
      NoteMirrorHanded(Cursor);
    End;
  LockSession;
  Try
    HadPlan := FHasPlanSend;
    Plan := FPlanSend;
    FHasPlanSend := False;
    FPlanSend := '';
  Finally
    UnlockSession;
  End;
  If HadPlan Then
    Begin
      If Not Transmit(Plan) Then
        Begin
          LockSession;
          Try
            { A plan queued while this one was in flight is newer. Keep that one. }
            If FHasPlanSend Then
              Inc(FFramesDropped)
            Else
              StorePlanSend(Plan);
          Finally
            UnlockSession;
          End;
          Exit;
        End;
    End;
  LockSession;
  Try
    Bulk := FBulkSends;
    SetLength(FBulkSends, 0);
  Finally
    UnlockSession;
  End;
  Sent := 0;
  While Sent < Length(Bulk) Do
    Begin
      If Not Transmit(Bulk[Sent]) Then
        Break;
      Inc(Sent);
    End;
  If Sent < Length(Bulk) Then
    Begin
      LockSession;
      Try
        PrependUnsent(FBulkSends, Bulk, Sent);
      Finally
        UnlockSession;
      End;
    End;
End;

Procedure TMonitorSession.LogLine(Level: Integer; Const Text: String);
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

Procedure TMonitorSession.ClearConnection;
Begin
  SetLength(FNonce, 0);
  FNonceHex := '';
  FNonceUntil := 0;
  FNonceUsed := False;
  FExpectPair := False;
  FConnectionClientId := '';
  FClientName := '';
  FClientVersion := 0;
  FPartialOpen := False;
  FPartialSinceMs := 0;
  FLastFrameMs := 0;
  LastSentMs := 0;
  PingQueuedMs := 0;
  If Assigned(FOutbox) Then
    FOutbox.Clear;
  FHasLivePatch := False;
  FLiveCursor := 0;
  SetLength(FLiveFrames, 0);
  FHasPlanSend := False;
  FPlanSend := '';
End;

Procedure TMonitorSession.CloseToListening;
Begin
  ClearConnection;
  FCloseRequested := True;
  If FState <> mssStopped Then
    FState := mssListening;
End;

Function TMonitorSession.Connected: Boolean;
Begin
  Result := FState In [mssAccepted, mssLive, mssBusy, mssRevoked];
End;

Function TMonitorSession.IsRevoked(Const ClientId: String): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  For I := 0 To High(FRevokedIds) Do
    If FRevokedIds[I] = ClientId Then
      Exit(True);
End;

Function TMonitorSession.FindClient(Const ClientId: String): Integer;
Var
  I: Integer;
Begin
  Result := -1;
  For I := 0 To High(FClients) Do
    If FClients[I].Id = ClientId Then
      Exit(I);
End;

Procedure TMonitorSession.RememberRevoked(Const ClientId: String);
Begin
  If (ClientId = '') Or IsRevoked(ClientId) Then
    Exit;
  SetLength(FRevokedIds, Length(FRevokedIds) + 1);
  FRevokedIds[High(FRevokedIds)] := ClientId;
End;

Procedure TMonitorSession.LoadClients;
Var
  Settings: TMonitorSettings;
  ErrorText: String;
  I: Integer;
Begin
  SetLength(FClients, 0);
  If Not LoadMonitorSettings(Settings, ErrorText) Then
    Begin
      FLastError := ErrorText;
      FRemoteApproval := False;
      Exit;
    End;
  FRemoteApproval := Settings.RemoteApproval;
  SetLength(FClients, Length(Settings.Clients));
  For I := 0 To High(Settings.Clients) Do
    Begin
      FClients[I].Id := Settings.Clients[I].Id;
      FClients[I].Name := Settings.Clients[I].Name;
      FClients[I].Token := Settings.Clients[I].Token;
      FClients[I].Fingerprint := Settings.Clients[I].Fingerprint;
      FClients[I].PairedAt := Settings.Clients[I].PairedAt;
    End;
End;

Function TMonitorSession.PersistClients(Out ErrorText: String): Boolean;
Var
  Settings: TMonitorSettings;
  I: Integer;
Begin
  ErrorText := '';
  If Not LoadMonitorSettings(Settings, ErrorText) Then
    Settings := DefaultMonitorSettings;
  SetLength(Settings.Clients, Length(FClients));
  For I := 0 To High(FClients) Do
    Begin
      Settings.Clients[I].Id := FClients[I].Id;
      Settings.Clients[I].Name := FClients[I].Name;
      Settings.Clients[I].Token := FClients[I].Token;
      Settings.Clients[I].Fingerprint := FClients[I].Fingerprint;
      Settings.Clients[I].PairedAt := FClients[I].PairedAt;
    End;
  Result := SaveMonitorSettings(Settings, ErrorText);
  If Not Result Then
    FLastError := ErrorText;
End;

Function TMonitorSession.MintPairCode: String;
Var
  I, Drawn, Limit: Integer;
  Buf: Byte;
Begin
  Result := '';
  Limit := 256 - (256 Mod Length(MonitorCrockfordAlphabet));
  For I := 1 To MonitorPairCodeLength Do
    Begin
      Repeat
        If Not CryptoGetRandomBytes(@Buf, 1) Then
          Exit;
      Until Integer(Buf) < Limit;
      Drawn := Integer(Buf) Mod Length(MonitorCrockfordAlphabet);
      Result := Result + MonitorCrockfordAlphabet[Drawn + 1];
    End;
End;

Procedure TMonitorSession.DiscardPairCode(Expired: Boolean);
Begin
  FPairCode := '';
  FPairCodeUntil := 0;
  FPairFailures := 0;
  FCodeExpired := Expired;
End;

Function TMonitorSession.PairCodeActive: Boolean;
Begin
  Result := (FPairCode <> '') And (ClockMs < FPairCodeUntil);
  If (FPairCode <> '') And (Not Result) Then
    DiscardPairCode(True);
End;

Procedure TMonitorSession.RejectLocked(Const Reason: String; DoClose: Boolean);
Var
  Json: String;
Begin
  Json := EncodeMonitorRejected(NewHostId, Reason, MonitorCatalogueVersion, FClientVersion);
  QueueSend(Json);
  LogLine(2, 'rejected reason=' + Reason + ' bytes=' + IntToStr(Length(Json)) + ' bind=' + FBindAddress +
    ' port=' + IntToStr(FPort));
  If DoClose Then
    CloseToListening;
End;

Function TMonitorSession.KindAllowedBeforeAuth(Kind: Integer): Boolean;
Begin
  Result := (Kind = Ord(mmkHello)) Or (Kind = Ord(mmkPair)) Or (Kind = Ord(mmkAuth)) Or
    (Kind = Ord(mmkPing)) Or (Kind = Ord(mmkBye));
End;

Procedure TMonitorSession.HandleHello(Const PayloadJson: String);
Var
  Hello: TMonitorHello;
  HelloOk: TMonitorHelloOk;
  Index: Integer;
  NonceHex: AnsiString;
Begin
  If FState <> mssAccepted Then
    Begin
      RejectLocked('protocol', True);
      Exit;
    End;
  If Not DecodeMonitorHello(PayloadJson, Hello) Then
    Begin
      RejectLocked('protocol', True);
      Exit;
    End;
  FClientName := Hello.ClientName;
  FClientVersion := StrToIntDef(Hello.ClientVersion, 0);
  FExpectPair := Not Hello.HasClientId;
  If Not Hello.HasClientId Then
    Begin
      FConnectionClientId := '';
      Exit;
    End;
  FConnectionClientId := Hello.ClientId;
  FExpectPair := False;
  If IsRevoked(Hello.ClientId) Then
    Begin
      RejectLocked('revoked', True);
      Exit;
    End;
  Index := FindClient(Hello.ClientId);
  If Index < 0 Then
    Begin
      RejectLocked('auth', True);
      Exit;
    End;
  FNonce := RandomBytes(MonitorNonceBytes);
  If Length(FNonce) <> MonitorNonceBytes Then
    Begin
      FLastError := 'Could not mint an auth nonce.';
      RejectLocked('auth', True);
      Exit;
    End;
  NonceHex := BytesToHexStr(FNonce);
  FNonceHex := LowerCase(String(NonceHex));
  FNonceUntil := ClockMs + MonitorNonceTtlMs;
  FNonceUsed := False;
  If FEpoch = '' Then
    Begin
      FEpoch := MintMonitorEpoch;
      FCommittedCursor := 0;
    End;
  If FConversationId = 'current' Then
    FConversationId := '';
  HelloOk.Nonce := FNonceHex;
  HelloOk.ServerName := MonitorServerName;
  HelloOk.Epoch := FEpoch;
  HelloOk.Cursor := FCommittedCursor;
  HelloOk.ConversationId := FConversationId;
  HelloOk.ProjectRoot := FProjectRoot;
  HelloOk.Title := FTitle;
  HelloOk.HostId := FInstallationHostId;
  QueueSend(EncodeMonitorHelloOk(NewHostId, HelloOk));
End;

Procedure TMonitorSession.HandlePair(Const PayloadJson: String);
Var
  Pair: TMonitorPair;
  IdBytes, TokenBytes: TBytes;
  ErrorText, SavedError: String;
  Index: Integer;
Begin
  If (FState <> mssAccepted) Or (Not FExpectPair) Then
    Begin
      RejectLocked('auth', True);
      Exit;
    End;
  If Not DecodeMonitorPair(PayloadJson, Pair) Then
    Begin
      RejectLocked('protocol', True);
      Exit;
    End;
  If Not PairCodeActive Then
    Begin
      If FCodeExpired Then
        Begin
          FCodeExpired := False;
          RejectLocked('expired', True);
          Exit;
        End;
      { No code is armed. Admit the endpoint. Fingerprint and code are not checked. }
      If FPairGate Then
        Begin
          RejectLocked('pair_code', True);
          Exit;
        End;
    End
  Else
    Begin
      If (FHostFingerprint <> '') And (NormalizeHex(Pair.Fingerprint) <> NormalizeHex(FHostFingerprint)) Then
        Begin
          RejectLocked('fingerprint', True);
          Exit;
        End;
      If UpperCase(Trim(Pair.Code)) <> FPairCode Then
        Begin
          Inc(FPairFailures);
          If FPairFailures >= MonitorPairFailureLimit Then
            Begin
              DiscardPairCode(False);
              RejectLocked('pair_code', True);
            End
          Else
            RejectLocked('pair_code', False);
          Exit;
        End;
    End;
  IdBytes := RandomBytes(MonitorClientIdBytes);
  TokenBytes := RandomBytes(MonitorSessionTokenBytes);
  If (Length(IdBytes) <> MonitorClientIdBytes) Or (Length(TokenBytes) <> MonitorSessionTokenBytes) Then
    Begin
      FLastError := 'Could not allocate a monitor client.';
      RejectLocked('auth', True);
      Exit;
    End;
  Index := Length(FClients);
  SetLength(FClients, Index + 1);
  FClients[Index].Id := String(BytesToHexStr(IdBytes));
  FClients[Index].Name := FClientName;
  FClients[Index].Token := String(BytesEncodeBase64(TokenBytes, True, False, False));
  FClients[Index].Fingerprint := Pair.Fingerprint;
  FClients[Index].PairedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', Now);
  If Not PersistClients(ErrorText) Then
    Begin
      SetLength(FClients, Index);
      SavedError := ErrorText;
      FLastError := SavedError;
      RejectLocked('protocol', True);
      Exit;
    End;
  FConnectionClientId := FClients[Index].Id;
  DiscardPairCode(False);
  FPairGate := False;
  FState := mssLive;
  AdoptRunningHost;
  QueueSend(EncodeMonitorPairOk(NewHostId, FClients[Index].Id, FClients[Index].Token));
  LogLine(1, 'pair success client=' + FClients[Index].Id + ' bind=' + FBindAddress + ' port=' + IntToStr(FPort));
End;

Procedure TMonitorSession.HandleAuth(Const PayloadJson: String);
Var
  Auth: TMonitorAuth;
  Index: Integer;
  Expected: String;
Begin
  If FState <> mssAccepted Then
    Begin
      RejectLocked('auth', True);
      Exit;
    End;
  If Not DecodeMonitorAuth(PayloadJson, Auth) Then
    Begin
      RejectLocked('protocol', True);
      Exit;
    End;
  If FNonceHex = '' Then
    Begin
      RejectLocked('auth', True);
      Exit;
    End;
  If FNonceUsed Or (ClockMs >= FNonceUntil) Then
    Begin
      FNonceUsed := True;
      RejectLocked('expired', True);
      Exit;
    End;
  FNonceUsed := True;
  If Auth.ClientId <> FConnectionClientId Then
    Begin
      RejectLocked('auth', True);
      Exit;
    End;
  Index := FindClient(Auth.ClientId);
  If Index < 0 Then
    Begin
      RejectLocked('auth', True);
      Exit;
    End;
  Expected := MonitorAuthMac(FClients[Index].Token, FNonceHex);
  If (Expected = '') Or (LowerCase(Auth.Hmac) <> Expected) Then
    Begin
      RejectLocked('auth', True);
      Exit;
    End;
  FClientName := FClients[Index].Name;
  FState := mssLive;
  AdoptRunningHost;
  LogLine(1, 'auth success client=' + Auth.ClientId + ' bind=' + FBindAddress + ' port=' + IntToStr(FPort));
End;

Procedure TMonitorSession.HandlePing(Const PayloadJson: String);
Var
  Ticks: TMonitorTicks;
Begin
  If Not DecodeMonitorTicks(PayloadJson, Ticks) Then
    Ticks.Ticks := 0;
  QueueSend(EncodeMonitorTicks(mmkPong, NewHostId, Ticks.Ticks));
End;

Procedure TMonitorSession.HandleBye;
Begin
  LogLine(1, 'disconnect bind=' + FBindAddress + ' port=' + IntToStr(FPort));
  CloseToListening;
End;

Function TMonitorSession.CommandBlocked(Kind: Integer; Out MessageText: String): Boolean;
Begin
  Result := False;
  MessageText := 'The desktop control is not available.';
  If Kind = Ord(mmkSend) Then
    Result := (Not FHostFlags.CanSend) Or FHostFlags.Sending Or FHostFlags.PlanAgentRunning
  Else If Kind = Ord(mmkSetMode) Then
    Result := FHostFlags.Sending Or FHostFlags.ModeLocked Or (Not FHostFlags.CanChangeMode)
  Else If Kind = Ord(mmkNewConversation) Then
    Result := FHostFlags.Sending Or FHostFlags.PlanAgentRunning
  Else If Kind = Ord(mmkRunPlan) Then
    Result := FHostFlags.Sending Or FHostFlags.PlanAgentRunning
  Else If Kind = Ord(mmkWorkOnPlan) Then
    Result := FHostFlags.Sending
  Else If Kind = Ord(mmkRunTask) Then
    Result := FHostFlags.Sending Or FHostFlags.PlanAgentRunning
  Else If (Kind = Ord(mmkRemovePlan)) Or (Kind = Ord(mmkInsertTask)) Then
    Result := FHostFlags.Sending Or FHostFlags.PlanAgentRunning
  Else If (Kind = Ord(mmkSelectPlan)) Or (Kind = Ord(mmkNewPlan)) Then
    Result := FHostFlags.Sending
  Else If Kind = Ord(mmkSelectTarget) Then
    Begin
      { A bind stops in-flight work. Review is still the form's check. }
      Result := FHostFlags.Sending Or FHostFlags.PlanAgentRunning;
      If FHostFlags.Sending Then
        MessageText := 'Wait for the current reply to finish.'
      Else If FHostFlags.PlanAgentRunning Then
        MessageText := 'A plan run is already active.';
    End
  Else If Kind = Ord(mmkSelectConversation) Then
    Begin
      { The History combo refuses only while a reply is sending. }
      Result := FHostFlags.Sending;
      If Result Then
        MessageText := 'Stop the current reply before switching History.';
    End
  Else If (Kind = Ord(mmkSetModel)) Or (Kind = Ord(mmkSetReasoning)) Or (Kind = Ord(mmkSetPermissions)) Then
    Begin
      { Review is still the form's check. A plan run is work in progress. }
      Result := FHostFlags.Sending Or FHostFlags.PlanAgentRunning;
      If Result Then
        MessageText := 'Wait until the current work finishes before changing the model, effort, or permissions.';
    End
  Else If Kind = Ord(mmkSteer) Then
    Begin
      Result := (FState <> mssBusy) Or (Not FHostFlags.CanSteer);
      If FState <> mssBusy Then
        MessageText := 'Nothing is running to steer.';
    End
  Else If Kind = Ord(mmkStop) Then
    Result := (FState = mssBusy) And (Not FHostFlags.CanStop);
End;

Procedure TMonitorSession.EnterBusy(Kind: Integer; Const Id, PayloadJson: String);
Begin
  FState := mssBusy;
  QueueCommand(Kind, Id, PayloadJson);
End;

Procedure TMonitorSession.AdoptRunningHost;
Begin
  If (FState = mssLive) And (FHostFlags.Sending Or FHostFlags.PlanAgentRunning) Then
    FState := mssBusy
  Else If (FState = mssBusy) And (Not FHostFlags.Sending) And (Not FHostFlags.PlanAgentRunning) Then
    FState := mssLive;
End;

Function RecordedCommand(Kind: Integer): Boolean;
Begin
  Result := (Kind = Ord(mmkSend)) Or (Kind = Ord(mmkSteer)) Or (Kind = Ord(mmkStop)) Or (Kind = Ord(mmkSetMode)) Or
    (Kind = Ord(mmkNewConversation)) Or (Kind = Ord(mmkRunPlan)) Or (Kind = Ord(mmkStopPlan)) Or
    (Kind = Ord(mmkWorkOnPlan)) Or (Kind = Ord(mmkRunTask)) Or (Kind = Ord(mmkRemovePlan)) Or
    (Kind = Ord(mmkInsertTask)) Or (Kind = Ord(mmkSelectPlan)) Or (Kind = Ord(mmkSelectTarget)) Or
    (Kind = Ord(mmkSelectConversation)) Or (Kind = Ord(mmkSetModel)) Or (Kind = Ord(mmkSetReasoning)) Or
    (Kind = Ord(mmkSetPermissions)) Or (Kind = Ord(mmkNewPlan));
End;

Procedure TMonitorSession.HandleCommand(Kind: Integer; Const Id, PayloadJson: String);
Var
  Blocked: Boolean;
  MessageText: String;
  Prior: TMonitorCommandRecord;
  Admitted: TMonitorIntakeResult;
Begin
  If (FState <> mssLive) And (FState <> mssBusy) Then
    Begin
      RejectLocked('auth', True);
      Exit;
    End;
  If RecordedCommand(Kind) Then
    Begin
      Admitted := FIntake.Admit(Id, Kind, Prior);
      If Admitted = mirInvalid Then
        Exit;
      If Admitted = mirDuplicate Then
        Begin
          QueueSend(EncodeMonitorCommandState(NewHostId, Prior.Id, MonitorCommandStateName(Prior.State), Prior.Reason));
          Exit;
        End;
    End;
  If Kind = Ord(mmkStop) Then
    Begin
      If CommandBlocked(Kind, MessageText) Then
        QueueSend(EncodeMonitorError(NewHostId, MonitorHostBusyReason, MessageText, Id))
      Else
        Begin
          If FState = mssBusy Then
            FState := mssLive;
          QueueCommand(Kind, Id, PayloadJson);
        End;
      Exit;
    End;
  { A dropped socket clears busy. A steer that arrives before the next snapshot is a prompt, not a steer. }
  If (Kind = Ord(mmkSteer)) And ((FState <> mssBusy) Or (Not FHostFlags.CanSteer)) And (FState = mssLive) And
    FHostFlags.CanSend And (Not FHostFlags.Sending) And (Not FHostFlags.PlanAgentRunning) Then
    Begin
      LogLine(1, 'steer submitted as send bind=' + FBindAddress + ' port=' + IntToStr(FPort));
      EnterBusy(Ord(mmkSend), Id, PayloadJson);
      Exit;
    End;
  Blocked := CommandBlocked(Kind, MessageText);
  If Blocked Then
    Begin
      QueueSend(EncodeMonitorError(NewHostId, MonitorHostBusyReason, MessageText, Id));
      Exit;
    End;
  If Kind = Ord(mmkTurn) Then
    Begin
      If ServeTurnFromMirror(Id, PayloadJson) Then
        Exit;
    End;
  If (Kind = Ord(mmkSend)) Or (Kind = Ord(mmkRunPlan)) Or (Kind = Ord(mmkWorkOnPlan)) Or (Kind = Ord(mmkRunTask)) Then
    EnterBusy(Kind, Id, PayloadJson)
  Else
    QueueCommand(Kind, Id, PayloadJson);
End;

Procedure TMonitorSession.HandleResume(Const Id, PayloadJson: String);
Var
  ResumeMsg: TMonitorResume;
Begin
  If (FState <> mssLive) And (FState <> mssBusy) Then
    Begin
      RejectLocked('auth', True);
      Exit;
    End;
  If Not DecodeMonitorResume(PayloadJson, ResumeMsg) Then
    Begin
      QueueSend(EncodeMonitorError(NewHostId, 'protocol', 'Resume payload is not valid.', Id));
      Exit;
    End;
  If Length(ResumeMsg.Commands) > 0 Then
    QueueSend(CommandStatesFor(NewHostId, ResumeMsg.Commands));
  { The log or the materialised model answers on this thread. An empty model still waits for the IDE thread. }
  If ServeResumeFromMirror(Id, ResumeMsg) Then
    Exit;
  QueueCommand(Ord(mmkResume), Id, PayloadJson);
End;

Function TMonitorSession.ApplyApprovalDecision(Const ToolId: String; Allow: Boolean): Boolean;
Var
  I: Integer;
Begin
  Result := False;
  If (ToolId = '') Or (Not FRemoteApproval) Then
    Exit;
  For I := 0 To High(FClosedToolIds) Do
    If FClosedToolIds[I] = ToolId Then
      Exit;
  If ToolId = FDisplayApprovalId Then
    Exit;
  If ToolId <> FPendingApprovalId Then
    Exit;
  If ReadAssistantApprovalDecision <> aadNone Then
    Exit;
  If Allow Then
    StoreAssistantApprovalDecision(aadAllow)
  Else
    StoreAssistantApprovalDecision(aadDeny);
  SignalAssistantApprovalWait;
  Result := ReadAssistantApprovalDecision <> aadNone;
End;

Function TMonitorSession.ApprovalRejectReason(Const ToolId: String): String;
Var
  I: Integer;
Begin
  Result := '';
  If (ToolId = '') Or (Not FRemoteApproval) Then
    Exit;
  If ReadAssistantApprovalDecision = aadStopped Then
    Exit('stopped');
  For I := 0 To High(FClosedToolIds) Do
    If FClosedToolIds[I] = ToolId Then
      Exit('finished');
  If (ToolId = FDisplayApprovalId) Or (ToolId <> FPendingApprovalId) Then
    Result := 'finished';
End;

Procedure TMonitorSession.HandleApproval(Const PayloadJson: String);
Var
  Decision: TMonitorApprovalDecision;
  Reason: String;
Begin
  If Not DecodeMonitorApprovalDecision(PayloadJson, Decision) Then
    Exit;
  If ApplyApprovalDecision(Decision.ToolId, Decision.Allow) Then
    Exit;
  Reason := ApprovalRejectReason(Decision.ToolId);
  If Reason = '' Then
    Exit;
  FPendingApprovalClose := True;
  FPendingApprovalCloseId := Decision.ToolId;
  FPendingApprovalCloseReason := Reason;
End;

Procedure TMonitorSession.HandleLocked(Const Frame: TMonitorFrame);
Var
  Message: TMonitorMessage;
  ErrorText: String;
Begin
  FLastFrameMs := ClockMs;
  If Not TryDecodeMonitorEnvelope(Frame.Json, Message, ErrorText) Then
    Begin
      LogLine(2, 'version mismatch bytes=' + IntToStr(Length(Frame.Json)) + ' bind=' + FBindAddress +
        ' port=' + IntToStr(FPort));
      RejectLocked('protocol', True);
      Exit;
    End;
  If Message.TypeName = 'ack' Then
    Begin
      If (FState = mssLive) Or (FState = mssBusy) Then
        NoteLogAck(Message.PayloadJson);
      Exit;
    End;
  If Message.TypeName = 'block_get' Then
    Begin
      If (FState <> mssLive) And (FState <> mssBusy) Then
        RejectLocked('auth', True)
      Else
        ServeBlockGet(Message.Id, Message.PayloadJson);
      Exit;
    End;
  If (FState <> mssLive) And (FState <> mssBusy) Then
    Begin
      If Not KindAllowedBeforeAuth(Ord(Message.Kind)) Then
        Begin
          RejectLocked('auth', True);
          Exit;
        End;
    End
  Else If Not Message.ChangesState Then
    Begin
      QueueSend(Message.WireJson);
      Exit;
    End;
  Case Message.Kind Of
    mmkHello: HandleHello(Message.PayloadJson);
    mmkPair: HandlePair(Message.PayloadJson);
    mmkAuth: HandleAuth(Message.PayloadJson);
    mmkPing: HandlePing(Message.PayloadJson);
    mmkBye: HandleBye;
    mmkPong: ;
    mmkApprovalDecision: HandleApproval(Message.PayloadJson);
    mmkResume:
      HandleResume(Message.Id, Message.PayloadJson);
    mmkSend, mmkSteer, mmkStop, mmkSetMode, mmkNewConversation, mmkRunPlan, mmkStopPlan, mmkWorkOnPlan, mmkRunTask,
    mmkRemovePlan, mmkInsertTask, mmkSelectPlan, mmkSelectTarget, mmkSelectConversation, mmkSetModel, mmkSetReasoning,
    mmkSetPermissions, mmkNewPlan, mmkRefresh, mmkTurn, mmkImageGet:
      HandleCommand(Ord(Message.Kind), Message.Id, Message.PayloadJson);
  Else
    If (FState = mssLive) Or (FState = mssBusy) Then
      QueueSend(Message.WireJson)
    Else
      RejectLocked('auth', True);
  End;
End;

Procedure TMonitorSession.QueueCommand(Kind: Integer; Const Id, PayloadJson: String);
Begin
  FPendingCommand := True;
  FPendingCommandKind := Kind;
  FPendingCommandId := Id;
  FPendingCommandPayload := PayloadJson;
End;

Procedure TMonitorSession.QueueBulkFramesLocked(Const Frames: TStringArray);
Var
  Chunks: Array Of RawByteString;
  Index: Integer;
  Frame: RawByteString;
  Lane: TMonitorOutboxLane;
Begin
  If Length(Frames) = 0 Then
    Exit;
  SetLength(Chunks, Length(Frames));
  For Index := 0 To High(Frames) Do
    Chunks[Index] := Frames[Index];
  { The outbox already accepted the whole item. Do not drop the tail at the old 32-frame cap. }
  If (Not Assigned(FOutbox)) Or (Not FOutbox.AddBulk(Chunks)) Then
    Begin
      Inc(FFramesDropped);
      Exit;
    End;
  While FOutbox.Take(Frame, Lane) Do
    Begin
      Index := Length(FBulkSends);
      SetLength(FBulkSends, Index + 1);
      FBulkSends[Index] := String(Frame);
    End;
End;

Procedure TMonitorSession.CheckTimeoutsLocked;
Var
  QuietSince: QWord;
Begin
  If (FPairCode <> '') And (ClockMs >= FPairCodeUntil) Then
    DiscardPairCode(True);
  If FPartialOpen And (FPartialSinceMs <> 0) And (ClockMs >= FPartialSinceMs + MonitorPartialFrameMs) And Connected Then
    Begin
      LogLine(2, 'partial frame timeout bind=' + FBindAddress + ' port=' + IntToStr(FPort));
      CloseToListening;
      Exit;
    End;
  If (FState = mssAccepted) And (FNonceHex <> '') And (Not FNonceUsed) And (ClockMs >= FNonceUntil) Then
    Begin
      FNonceUsed := True;
      RejectLocked('expired', True);
      Exit;
    End;
  If (FState <> mssLive) And (FState <> mssBusy) Then
    Exit;
  If FLastFrameMs = 0 Then
    Exit;
  { Only received frames keep the link alive. Our own pings do not. }
  If ClockMs >= FLastFrameMs + MonitorDeadSessionMs Then
    Begin
      LogLine(2, 'heartbeat timeout bind=' + FBindAddress + ' port=' + IntToStr(FPort));
      CloseToListening;
      Exit;
    End;
  QuietSince := LastSentMs;
  If QuietSince = 0 Then
    QuietSince := FLastFrameMs;
  If (ClockMs >= QuietSince + MonitorHeartbeatMs) And ((PingQueuedMs = 0) Or (ClockMs >= PingQueuedMs + MonitorHeartbeatMs)) Then
    Begin
      PingQueuedMs := ClockMs;
      QueueSend(EncodeMonitorTicks(mmkPing, NewHostId, Int64(ClockMs)));
    End;
End;

Procedure TMonitorSession.AttachCarrier(Const Carrier: IMonitorCarrier);
Begin
  LockSession;
  Try
    If Assigned(FCarrier) Then
      FCarrier.SetFrameHandler(Nil);
    FCarrier := Carrier;
    If Assigned(FCarrier) Then
      FCarrier.SetFrameHandler(@InboundFrame);
  Finally
    UnlockSession;
  End;
End;

Function TMonitorSession.StartListening(Const BindAddress: String; Port: Integer; Out ErrorText: String): Boolean;
Begin
  ErrorText := '';
  LockSession;
  Try
    Result := False;
    If FState <> mssStopped Then
      Begin
        Result := FState = mssListening;
        Exit;
      End;
    FBindAddress := BindAddress;
    FPort := Port;
    FLastError := '';
    LoadClients;
    FState := mssListening;
    FCloseRequested := False;
    Result := True;
    LogLine(1, 'listen start bind=' + FBindAddress + ' port=' + IntToStr(FPort));
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.StopListening;
Begin
  LockSession;
  Try
    If Connected Then
      QueueSend(EncodeMonitorBye(NewHostId, 'disabled'));
    FCloseRequested := True;
    ClearConnection;
    FState := mssStopped;
    LogLine(1, 'listen stop bind=' + FBindAddress + ' port=' + IntToStr(FPort));
  Finally
    UnlockSession;
  End;
  FlushLivePatch;
  DrainSends;
End;

Function TMonitorSession.AcceptHandshake(Out RejectFrame: TMonitorFrame): Boolean;
Var
  Json: String;
Begin
  RejectFrame.Version := MonitorFrameVersion;
  RejectFrame.Flags := 0;
  RejectFrame.Json := '';
  LockSession;
  Try
    Result := False;
    If FState = mssListening Then
      Begin
        ClearConnection;
        FCloseRequested := False;
        FState := mssAccepted;
        Result := True;
        Exit;
      End;
    If FState = mssStopped Then
      Json := EncodeMonitorRejected(NewHostId, 'disabled', MonitorCatalogueVersion, 0)
    Else
      Json := EncodeMonitorRejected(NewHostId, 'busy', MonitorCatalogueVersion, 0);
    RejectFrame.Json := Json;
    If FState = mssStopped Then
      LogLine(2, 'rejected reason=disabled bind=' + FBindAddress + ' port=' + IntToStr(FPort))
    Else
      LogLine(2, 'rejected reason=busy bind=' + FBindAddress + ' port=' + IntToStr(FPort));
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.NoteSocketClosed;
Begin
  LockSession;
  Try
    If FState = mssStopped Then
      Begin
        FCloseRequested := False;
        Exit;
      End;
    LogLine(1, 'disconnect bind=' + FBindAddress + ' port=' + IntToStr(FPort) + ' bytes=0');
    ClearConnection;
    FCloseRequested := False;
    FState := mssListening;
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.NotePartialFrame(Open: Boolean);
Begin
  LockSession;
  Try
    If Open Then
      Begin
        If Not FPartialOpen Then
          FPartialSinceMs := ClockMs;
        FPartialOpen := True;
      End
    Else
      Begin
        FPartialOpen := False;
        FPartialSinceMs := 0;
      End;
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.SetIdleHandler(Handler: TMonitorIdleHandler);
Begin
  LockSession;
  Try
    FOnIdle := Handler;
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.NoteTime(NowMs: QWord);
Var
  Idle: TMonitorIdleHandler;
Begin
  LockSession;
  Try
    FNowMs := NowMs;
    CheckTimeoutsLocked;
    Idle := FOnIdle;
  Finally
    UnlockSession;
  End;
  DrainSends;
  { After the lock. A command sweep must not stall this carrier. }
  If Assigned(Idle) Then
    Idle;
End;

Procedure TMonitorSession.RequestPairCode;
Var
  Minted: String;
Begin
  LockSession;
  Try
    Minted := MintPairCode;
    If Length(Minted) <> MonitorPairCodeLength Then
      Begin
        FLastError := 'Could not mint a pairing code.';
        FPairCode := '';
        Exit;
      End;
    FPairCode := Minted;
    FPairCodeUntil := ClockMs + MonitorPairCodeTtlMs;
    FPairFailures := 0;
    FCodeExpired := False;
    FPairGate := True;
  Finally
    UnlockSession;
  End;
End;

Function TMonitorSession.PairCode: String;
Begin
  LockSession;
  Try
    If PairCodeActive Then
      Result := FPairCode
    Else
      Result := '';
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.SetHostFingerprint(Const Fingerprint: String);
Begin
  LockSession;
  Try
    FHostFingerprint := Fingerprint;
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.SetInstallationHostId(Const HostId: String);
Begin
  LockSession;
  Try
    If MonitorHostIdIsValid(HostId) Then
      FInstallationHostId := HostId
    Else
      FInstallationHostId := '';
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.SetHostFlags(Const Flags: TMonitorHostFlags);
Begin
  LockSession;
  Try
    FHostFlags := Flags;
    AdoptRunningHost;
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.SetRemoteApproval(Enabled: Boolean);
Begin
  LockSession;
  Try
    FRemoteApproval := Enabled;
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.RevokeClient(Const ClientId: String);
Var
  Index, I: Integer;
  ErrorText: String;
  Live: Boolean;
Begin
  LockSession;
  Try
    Index := FindClient(ClientId);
    If Index >= 0 Then
      Begin
        For I := Index To High(FClients) - 1 Do
          FClients[I] := FClients[I + 1];
        SetLength(FClients, Length(FClients) - 1);
      End;
    RememberRevoked(ClientId);
    PersistClients(ErrorText);
    Live := (FConnectionClientId = ClientId) And ((FState = mssLive) Or (FState = mssBusy));
    If Live Then
      Begin
        FState := mssRevoked;
        QueueSend(EncodeMonitorBye(NewHostId, 'revoked'));
        FCloseRequested := True;
        LogLine(1, 'revoke client=' + ClientId + ' bind=' + FBindAddress + ' port=' + IntToStr(FPort));
      End;
  Finally
    UnlockSession;
  End;
  DrainSends;
End;

Procedure TMonitorSession.RevokeAll;
Var
  I: Integer;
  ErrorText: String;
  LiveId: String;
Begin
  LockSession;
  Try
    For I := 0 To High(FClients) Do
      RememberRevoked(FClients[I].Id);
    SetLength(FClients, 0);
    PersistClients(ErrorText);
    LiveId := FConnectionClientId;
    If (LiveId <> '') And ((FState = mssLive) Or (FState = mssBusy)) Then
      Begin
        FState := mssRevoked;
        QueueSend(EncodeMonitorBye(NewHostId, 'revoked'));
        FCloseRequested := True;
      End;
  Finally
    UnlockSession;
  End;
  DrainSends;
End;

Procedure TMonitorSession.NoteTurnEnded;
Begin
  LockSession;
  Try
    If FState = mssBusy Then
      FState := mssLive;
    FHostFlags.Sending := False;
    FHostFlags.PlanAgentRunning := False;
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.BeginMirrorEpoch(Const Epoch, ConversationId, ProjectRoot, Title: String);
Begin
  LockSession;
  Try
    FEpoch := LowerCase(Epoch);
    If ConversationId = 'current' Then
      FConversationId := ''
    Else
      FConversationId := ConversationId;
    FProjectRoot := ProjectRoot;
    FTitle := Title;
    FCommittedCursor := 0;
    FNextCursor := 0;
    FReservedCursor := 0;
    FReservedPayload := '';
    FReservedHanded := False;
    FMirror.BeginStream(FEpoch, FConversationId, FProjectRoot, FTitle);
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.RestoreMirror(Const Epoch, ConversationId, ProjectRoot, Title: String; Cursor: Int64);
Begin
  LockSession;
  Try
    FEpoch := LowerCase(Epoch);
    If ConversationId = 'current' Then
      FConversationId := ''
    Else
      FConversationId := ConversationId;
    FProjectRoot := ProjectRoot;
    FTitle := Title;
    If Cursor < 0 Then
      Cursor := 0;
    FCommittedCursor := Cursor;
    FNextCursor := Cursor;
    FReservedCursor := 0;
    FReservedPayload := '';
    FReservedHanded := False;
    FHasLivePatch := False;
    FLiveCursor := 0;
    SetLength(FLiveFrames, 0);
    FMirror.BeginStream(FEpoch, FConversationId, FProjectRoot, FTitle);
  Finally
    UnlockSession;
  End;
End;

Function TMonitorSession.MirrorEpoch: String;
Begin
  LockSession;
  Try
    Result := FEpoch;
  Finally
    UnlockSession;
  End;
End;

Function TMonitorSession.MirrorCursor: Int64;
Begin
  LockSession;
  Try
    Result := FCommittedCursor;
  Finally
    UnlockSession;
  End;
End;

Function TMonitorSession.CommitMirrorCursor(Const Payload: RawByteString; Out Cursor: Int64): Boolean;
Begin
  Result := False;
  Cursor := 0;
  LockSession;
  Try
    If FEpoch = '' Then
      Exit;
    If (FReservedCursor <> 0) And (Not FReservedHanded) Then
      Begin
        FReservedPayload := Payload;
        Cursor := FReservedCursor;
        Result := True;
        Exit;
      End;
    If (FReservedCursor <> 0) And FReservedHanded And (Payload = FReservedPayload) Then
      Begin
        Cursor := FReservedCursor;
        Result := True;
        Exit;
      End;
    If FNextCursor = High(Int64) Then
      Exit;
    Inc(FNextCursor);
    FReservedCursor := FNextCursor;
    FReservedPayload := Payload;
    FReservedHanded := False;
    Cursor := FReservedCursor;
    Result := True;
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.ReplaceLivePatch(Cursor: Int64; Const Frames: TStringArray);
Var
  I: Integer;
Begin
  LockSession;
  Try
    If FHasLivePatch Then
      Inc(FFramesDropped, Length(FLiveFrames));
    If Length(Frames) = 0 Then
      Begin
        FHasLivePatch := False;
        FLiveCursor := 0;
        SetLength(FLiveFrames, 0);
        Exit;
      End;
    SetLength(FLiveFrames, Length(Frames));
    For I := 0 To High(Frames) Do
      FLiveFrames[I] := Frames[I];
    FLiveCursor := Cursor;
    FHasLivePatch := True;
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.FlushLivePatch;
Var
  Frames: Array Of String;
  Cursor: Int64;
  Had: Boolean;
  I, Sent: Integer;
Begin
  LockSession;
  Try
    Had := FHasLivePatch;
    Frames := FLiveFrames;
    Cursor := FLiveCursor;
    FHasLivePatch := False;
    FLiveCursor := 0;
    SetLength(FLiveFrames, 0);
  Finally
    UnlockSession;
  End;
  If Not Had Then
    Exit;
  Sent := 0;
  While Sent < Length(Frames) Do
    Begin
      If Not Transmit(Frames[Sent]) Then
        Break;
      Inc(Sent);
    End;
  If Sent < Length(Frames) Then
    Begin
      LockSession;
      Try
        If Not FHasLivePatch Then
          Begin
            SetLength(FLiveFrames, Length(Frames) - Sent);
            For I := 0 To High(FLiveFrames) Do
              FLiveFrames[I] := Frames[Sent + I];
            FLiveCursor := Cursor;
            FHasLivePatch := Length(FLiveFrames) > 0;
          End
        Else
          Inc(FFramesDropped, Length(Frames) - Sent);
      Finally
        UnlockSession;
      End;
      Exit;
    End;
  NoteMirrorHanded(Cursor);
End;

Procedure TMonitorSession.NoteMirrorHanded(Cursor: Int64);
Begin
  LockSession;
  Try
    If (Cursor <> 0) And (Cursor = FReservedCursor) Then
      Begin
        FReservedHanded := True;
        If Cursor > FCommittedCursor Then
          FCommittedCursor := Cursor;
      End;
  Finally
    UnlockSession;
  End;
End;

Function TMonitorSession.MirrorDroppedThrough: Int64;
Begin
  If Assigned(FMirror) Then
    Result := FMirror.DroppedThrough
  Else
    Result := 0;
End;

Procedure TMonitorSession.RememberHandedPatch(Cursor: Int64; Const PatchJson: RawByteString);
Begin
  If Not Assigned(FMirror) Then
    Exit;
  LockSession;
  Try
    If (Cursor <= 0) Or (PatchJson = '') Or (Cursor > FCommittedCursor) Or (Cursor <= FMirror.DroppedThrough) Then
      Exit;
  Finally
    UnlockSession;
  End;
  FMirror.RememberPatch(Cursor, PatchJson);
End;

Function TMonitorSession.TryResumeEvents(Const Epoch: String; Cursor: Int64; Out Catchup: TMonitorCatchup): Boolean;
Var
  Events: TMonitorMirrorEventArray;
  Head: Int64;
  Index: Integer;
  Patch: TMonitorPatch;
Begin
  Result := False;
  Catchup := Default(TMonitorCatchup);
  SetLength(Catchup.Patches, 0);
  SetLength(Events, 0);
  If Not Assigned(FMirror) Then
    Exit;
  LockSession;
  Try
    Catchup.Mode := mcmEvents;
    Catchup.Epoch := FEpoch;
    Catchup.Cursor := FCommittedCursor;
    Catchup.ConversationId := FConversationId;
    Catchup.ProjectRoot := FProjectRoot;
    Catchup.Title := FTitle;
    Catchup.HasSnapshot := False;
    If FEpoch = '' Then
      Exit;
    If LowerCase(Epoch) <> FEpoch Then
      Exit;
    If (Cursor < 0) Or (Cursor > FCommittedCursor) Then
      Exit;
  Finally
    UnlockSession;
  End;
  If Not FMirror.TryReplayPatches(Epoch, Cursor, Catchup.Cursor, Events, Head) Then
    Exit;
  For Index := 0 To High(Events) Do
    Begin
      If Not DecodeMonitorPatch(String(Events[Index].Data), Patch) Then
        Exit;
      SetLength(Catchup.Patches, Length(Catchup.Patches) + 1);
      Catchup.Patches[High(Catchup.Patches)] := Patch;
    End;
  Result := True;
End;

Procedure TMonitorSession.ObserveTurn(Const Turn: TAssistantMonitorTurn);
Begin
  If Assigned(FMirror) Then
    FMirror.ObserveTurn(Turn);
End;

Procedure TMonitorSession.ObservePlan(Const PlanPath, PlanTitle: String; PlanRunning: Boolean;
  Const Rows: Array Of TAssistantMonitorPlanRow);
Begin
  If Assigned(FMirror) Then
    FMirror.ObservePlan(PlanPath, PlanTitle, PlanRunning, Rows);
End;

Function TMonitorSession.HasMirrorModel: Boolean;
Begin
  Result := Assigned(FMirror) And FMirror.HasModel;
End;

Function TMonitorSession.CopyMirrorTurns(Out Stored: TMonitorMirrorTurnArray; Out Live: TAssistantMonitorTurn;
  Out HasLive: Boolean): Boolean;
Begin
  Result := False;
  SetLength(Stored, 0);
  Live := Default(TAssistantMonitorTurn);
  HasLive := False;
  If Not Assigned(FMirror) Then
    Exit;
  Result := FMirror.CopyTurns(Stored, Live, HasLive);
End;

Function TMonitorSession.FetchMirrorTurn(TurnIndex: Integer; Out Turn: TAssistantMonitorTurn): Boolean;
Begin
  Result := False;
  Turn := Default(TAssistantMonitorTurn);
  If Assigned(FMirror) Then
    Result := FMirror.FetchTurn(TurnIndex, Turn);
End;

Function TMonitorSession.BuildMirrorPages(Out Pages: TMonitorSnapshotPageArray): Boolean;
Begin
  Result := False;
  SetLength(Pages, 0);
  If Not Assigned(FMirror) Then
    Exit;
  LockSession;
  Try
    Result := FMirror.BuildSnapshotPages(FEpoch, FCommittedCursor, Pages);
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.ObserveSnapshot(Const Snapshot: TMonitorSnapshot);
Var
  Index: Integer;
Begin
  LockSession;
  Try
    FObserved := Snapshot;
    FHasObserved := True;
  Finally
    UnlockSession;
  End;
  If Not Assigned(FMirror) Then
    Exit;
  For Index := 0 To High(Snapshot.StoredTurns) Do
    FMirror.ObserveTurn(Snapshot.StoredTurns[Index]);
  If Snapshot.HasLive Then
    FMirror.ObserveTurn(Snapshot.Live);
  FMirror.ObservePlan(Snapshot.PlanPath, Snapshot.PlanTitle, Snapshot.PlanRunning, Snapshot.PlanRows);
End;

Function TMonitorSession.CopyObservedSnapshot(Out Snapshot: TMonitorSnapshot): Boolean;
Begin
  LockSession;
  Try
    Snapshot := FObserved;
    Result := FHasObserved;
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.ServeBlockGet(Const Id, PayloadJson: String);
Var
  Data: TJSONData;
  Obj, Payload: TJSONObject;
  BlockId, Body, Piece: String;
  Bytes: UTF8String;
  Offset, Total, Taken: Integer;
  Last: Boolean;
Begin
  Data := Nil;
  BlockId := '';
  Offset := 0;
  Try
    Data := GetJSON(PayloadJson);
  Except
    Data := Nil;
  End;
  If Not (Data Is TJSONObject) Then
    Begin
      Data.Free;
      QueueSend(EncodeMonitorError(NewHostId, 'protocol', 'Block fetch payload is not valid.', Id));
      Exit;
    End;
  Obj := TJSONObject(Data);
  Try
    BlockId := Obj.Get('block_id', '');
    If Assigned(Obj.Find('offset')) And (Obj.Find('offset').JSONType = jtNumber) Then
      Offset := Obj.Find('offset').AsInteger;
  Finally
    Data.Free;
  End;
  If (BlockId = '') Or (Offset < 0) Or (Not Assigned(FMirror)) Or (Not FMirror.FetchBlock(BlockId, Body)) Then
    Begin
      QueueSend(EncodeMonitorError(NewHostId, 'not_found', 'Block was not found.', Id));
      Exit;
    End;
  Bytes := UTF8String(Body);
  Total := Length(Bytes);
  If Offset > Total Then
    Offset := Total;
  Bytes := Copy(Bytes, Offset + 1, MaxInt);
  Repeat
    Taken := Length(Bytes);
    If Taken > MonitorBlockDataBytes Then
      Taken := MonitorBlockDataBytes;
    While (Taken > 0) And (Taken < Length(Bytes)) And ((Ord(Bytes[Taken]) And $C0) = $80) Do
      Dec(Taken);
    If (Taken < 1) And (Length(Bytes) > 0) Then
      Taken := 1;
    Piece := String(Copy(Bytes, 1, Taken));
    Delete(Bytes, 1, Taken);
    Last := Length(Bytes) = 0;
    Payload := TJSONObject.Create;
    Try
      Payload.Add('conversation_id', FConversationId);
      Payload.Add('block_id', BlockId);
      Payload.Add('offset', Offset);
      Payload.Add('text', Piece);
      Payload.Add('total_bytes', Total);
      Payload.Add('last', Last);
      QueueSend('{"v":2,"id":"' + NewHostId + '","type":"block_data","payload":' + Payload.AsJSON + '}');
    Finally
      Payload.Free;
    End;
    Offset := Offset + Taken;
  Until Last;
End;

Function TMonitorSession.QueueMirrorPagesLocked(Const Id: String): Boolean;
Var
  Pages: TMonitorSnapshotPageArray;
  Frames: TStringArray;
  Index: Integer;
Begin
  Result := False;
  SetLength(Pages, 0);
  SetLength(Frames, 0);
  If (Not Assigned(FMirror)) Or (FEpoch = '') Then
    Exit;
  If Not FMirror.BuildSnapshotPages(FEpoch, FCommittedCursor, Pages) Then
    Exit;
  For Index := 0 To High(Pages) Do
    Begin
      If Not PackMonitorBulkItem(Id, 'snapshot_page', Pages[Index].Json, Frames) Then
        Exit;
      QueueBulkFramesLocked(Frames);
    End;
  Result := Length(Pages) > 0;
End;

Function TMonitorSession.ServeTurnFromMirror(Const Id, PayloadJson: String): Boolean;
Var
  TurnIndex: Integer;
  Turn: TAssistantMonitorTurn;
  Frames: TStringArray;
Begin
  Result := False;
  TurnIndex := 0;
  SetLength(Frames, 0);
  If Not DecodeMonitorTurnRequest(PayloadJson, TurnIndex) Then
    Exit;
  If Not FetchMirrorTurn(TurnIndex, Turn) Then
    Exit;
  If Not PackMonitorBulkItem(Id, 'snapshot_page', MonitorTurnPageJson(FConversationId, FEpoch, FCommittedCursor, Turn),
    Frames) Then
    Exit;
  QueueBulkFramesLocked(Frames);
  Result := True;
End;

Function TMonitorSession.ServeResumeFromMirror(Const Id: String; Const ResumeMsg: TMonitorResume): Boolean;
Var
  Catchup: TMonitorCatchup;
  Json: String;
Begin
  Result := False;
  { An empty event list means the cursor matched. It does not mean the phone has this screen.
    Fall through and send the mirror pages, which are the open conversation. }
  If TryResumeEvents(ResumeMsg.Epoch, ResumeMsg.Cursor, Catchup) And (Length(Catchup.Patches) > 0) Then
    Begin
      Json := EncodeMonitorCatchup(Id, Catchup);
      If Json <> '' Then
        Begin
          QueueSend(Json);
          Result := True;
          Exit;
        End;
    End;
  If (Not Assigned(FMirror)) Or (Not FMirror.HasModel) Then
    Exit;
  Result := QueueMirrorPagesLocked(Id);
End;

Function TMonitorSession.CopyClosedMirror(Out Closed: TMonitorConversationClosed): Boolean;
Begin
  LockSession;
  Try
    Closed.Epoch := '';
    Closed.Cursor := 0;
    Closed.ConversationId := '';
    Closed.Title := '';
    Result := FEpoch <> '';
    If Not Result Then
      Exit;
    Closed.Epoch := FEpoch;
    Closed.Cursor := FCommittedCursor;
    Closed.ConversationId := FConversationId;
    Closed.Title := FTitle;
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.CopyMirrorIdentity(Out Epoch, ConversationId, ProjectRoot, Title: String; Out Cursor: Int64);
Begin
  LockSession;
  Try
    Epoch := FEpoch;
    ConversationId := FConversationId;
    ProjectRoot := FProjectRoot;
    Title := FTitle;
    Cursor := FCommittedCursor;
  Finally
    UnlockSession;
  End;
End;

Function TMonitorSession.CommitSnapshotCursor(Const BodyStamp: RawByteString; Out Cursor: Int64): Boolean;
Begin
  Result := CommitMirrorCursor('catchup-snapshot' + #1 + BodyStamp, Cursor);
End;

Function ResumeNeedsFormSnapshot(Session: TMonitorSession; Const Epoch: String; Cursor: Int64): Boolean;
Var
  Catchup: TMonitorCatchup;
Begin
  Result := True;
  If Not Assigned(Session) Then
    Exit;
  Result := Not Session.TryResumeEvents(Epoch, Cursor, Catchup);
End;

Function MonitorCommandSweepSendsBusy(Kind: Integer; Claimed, Finished: Boolean; AgeMs: QWord): Boolean;
Begin
  If Kind = Ord(mmkResume) Then
    Exit(False);
  If Finished Or Claimed Then
    Exit(False);
  Result := AgeMs >= MonitorCommandWaitMs;
End;

Procedure TMonitorSession.PublishDisplayApproval(Const ToolId, ToolName, Summary, ModeCaption: String);
Var
  Notice: TAssistantApprovalNotice;
Begin
  LockSession;
  Try
    If (ToolId = '') Or (ToolId = FDisplayApprovalId) Then
      Exit;
    FDisplayApprovalId := ToolId;
    FPendingApprovalId := '';
    Notice.Active := True;
    Notice.ToolId := ToolId;
    Notice.ToolName := ToolName;
    Notice.Summary := Summary;
    Notice.ModeCaption := ModeCaption;
    Notice.DecisionsAccepted := False;
    Notice.Reason := '';
    QueueSend(EncodeMonitorApprovalRequested(NewHostId, Notice));
  Finally
    UnlockSession;
  End;
  DrainSends;
End;

Procedure TMonitorSession.CloseDisplayApproval(Const ToolId: String);
Begin
  LockSession;
  Try
    If ToolId = '' Then
      Exit;
    SetLength(FClosedToolIds, Length(FClosedToolIds) + 1);
    FClosedToolIds[High(FClosedToolIds)] := ToolId;
    If FDisplayApprovalId = ToolId Then
      FDisplayApprovalId := '';
    If FPendingApprovalId = ToolId Then
      FPendingApprovalId := '';
    QueueSend(EncodeMonitorApprovalClosed(NewHostId, ToolId, 'desktop'));
    FToolExecuted := False;
  Finally
    UnlockSession;
  End;
  DrainSends;
End;

Procedure TMonitorSession.NoteApprovalCancel(Const ToolId: String);
Begin
  LockSession;
  Try
    If (ToolId <> '') And ((ToolId = FPendingApprovalId) Or (FPendingApprovalId = '')) Then
      FPendingApprovalId := ToolId;
    StoreAssistantApprovalDecision(aadStopped);
    SignalAssistantApprovalWait;
    FToolExecuted := False;
  Finally
    UnlockSession;
  End;
End;

Function TMonitorSession.BareApprovalSignalIsAllow: Boolean;
Begin
  SignalAssistantApprovalWait;
  Result := ReadAssistantApprovalDecision = aadAllow;
End;

Function TMonitorSession.ToolExecutionRecorded: Boolean;
Begin
  Result := FToolExecuted;
End;

Procedure TMonitorSession.SendPackedFrames(Const Frames: TStringArray);
Begin
  If Length(Frames) = 0 Then
    Exit;
  LockSession;
  Try
    QueueBulkFramesLocked(Frames);
  Finally
    UnlockSession;
  End;
  DrainOutbound;
End;

Procedure TMonitorSession.SendBulkPayload(Const ItemId, ItemType, PayloadJson: String);
Var
  Frames: TStringArray;
Begin
  SetLength(Frames, 0);
  LockSession;
  Try
    If Not PackMonitorBulkItem(ItemId, ItemType, PayloadJson, Frames) Then
      Begin
        Inc(FFramesDropped);
        Exit;
      End;
    QueueBulkFramesLocked(Frames);
  Finally
    UnlockSession;
  End;
  DrainOutbound;
End;

Procedure TMonitorSession.SendTurnPage(Const Id: String; Const Turn: TAssistantMonitorTurn);
Var
  Frames: TStringArray;
Begin
  SetLength(Frames, 0);
  LockSession;
  Try
    If Not PackMonitorBulkItem(Id, 'snapshot_page', MonitorTurnPageJson(FConversationId, FEpoch, FCommittedCursor, Turn),
      Frames) Then
      Begin
        Inc(FFramesDropped);
        Exit;
      End;
    QueueBulkFramesLocked(Frames);
  Finally
    UnlockSession;
  End;
  DrainOutbound;
End;

Function TMonitorSession.SendMirrorPages(Const Id: String): Boolean;
Begin
  LockSession;
  Try
    Result := QueueMirrorPagesLocked(Id);
  Finally
    UnlockSession;
  End;
  If Result Then
    DrainOutbound;
End;

Function TMonitorSession.SecondsSinceFrame: Integer;
Begin
  LockSession;
  Try
    If FLastFrameMs = 0 Then
      Result := -1
    Else
      Result := Integer((ClockMs - FLastFrameMs) Div 1000);
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.InboundFrame(Const Frame: TMonitorFrame);
Var
  RunCommand, RunClose: Boolean;
  CommandKind: Integer;
  CommandId, CommandPayload, CloseId, CloseReason: String;
  Handler: TMonitorCommandHandler;
  CloseHandler: TMonitorApprovalCloseHandler;
Begin
  LockSession;
  Try
    FPendingCommand := False;
    FPendingApprovalClose := False;
    HandleLocked(Frame);
    RunCommand := FPendingCommand;
    CommandKind := FPendingCommandKind;
    CommandId := FPendingCommandId;
    CommandPayload := FPendingCommandPayload;
    Handler := FOnCommand;
    FPendingCommand := False;
    RunClose := FPendingApprovalClose;
    CloseId := FPendingApprovalCloseId;
    CloseReason := FPendingApprovalCloseReason;
    CloseHandler := FOnApprovalClosed;
    FPendingApprovalClose := False;
  Finally
    UnlockSession;
  End;
  DrainSends;
  If RunClose And Assigned(CloseHandler) Then
    CloseHandler(CloseId, CloseReason);
  If RunCommand And Assigned(Handler) Then
    Handler(CommandKind, CommandId, CommandPayload);
End;

Function TMonitorSession.AllocateHostId: String;
Begin
  LockSession;
  Try
    Result := NewHostId;
  Finally
    UnlockSession;
  End;
End;

Function TMonitorSession.TryQueueHostJson(Const Json: String): Boolean;
Begin
  Result := False;
  If Json = '' Then
    Exit;
  LockSession;
  Try
    Result := QueueSend(Json);
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.DrainOutbound;
Begin
  DrainSends;
End;

Procedure TMonitorSession.SendHostJson(Const Json: String);
Begin
  If Json = '' Then
    Exit;
  TryQueueHostJson(Json);
  DrainOutbound;
End;

Function TMonitorSession.CommandStatesFor(Const Id: String; Const Commands: TStringArray): String;
Var
  Index: Integer;
  Found: TMonitorCommandRecord;
  Replies: Array Of TMonitorCommandStateReply;
Begin
  Replies := Nil;
  SetLength(Replies, Length(Commands));
  For Index := 0 To High(Commands) Do
    Begin
      Replies[Index].Ref := Commands[Index];
      Replies[Index].Reason := '';
      If FIntake.Lookup(Commands[Index], Found) Then
        Begin
          Replies[Index].State := MonitorCommandStateName(Found.State);
          Replies[Index].Reason := Found.Reason;
        End
      Else
        Replies[Index].State := 'unknown';
    End;
  Result := EncodeMonitorCommandStates(Id, Replies);
End;

Procedure TMonitorSession.PublishCommandState(Const Id, State, Reason: String);
Begin
  SendHostJson(EncodeMonitorCommandState(AllocateHostId, Id, State, Reason));
End;

Procedure TMonitorSession.NoteCommandAccepted(Const Id: String);
Begin
  If Not FIntake.NoteAccepted(Id) Then
    Exit;
  PublishCommandState(Id, 'accepted', '');
End;

Procedure TMonitorSession.NoteCommandRejected(Const Id, Reason: String);
Begin
  If Not FIntake.NoteRejected(Id, Reason) Then
    Exit;
  PublishCommandState(Id, 'rejected', Reason);
End;

Procedure TMonitorSession.NoteCommandDone(Const Id: String);
Begin
  If Not FIntake.NoteDone(Id) Then
    Exit;
  PublishCommandState(Id, 'done', '');
End;

Procedure TMonitorSession.SetApprovalCloseHandler(Handler: TMonitorApprovalCloseHandler);
Begin
  LockSession;
  Try
    FOnApprovalClosed := Handler;
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.NoteApprovalRequested(Const ToolId: String; DecisionsAccepted: Boolean);
Begin
  LockSession;
  Try
    If ToolId = '' Then
      Exit;
    If DecisionsAccepted Then
      Begin
        FPendingApprovalId := ToolId;
        If FDisplayApprovalId = ToolId Then
          FDisplayApprovalId := '';
      End
    Else
      FDisplayApprovalId := ToolId;
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.NoteApprovalClosed(Const ToolId: String);
Begin
  LockSession;
  Try
    If ToolId = '' Then
      Exit;
    SetLength(FClosedToolIds, Length(FClosedToolIds) + 1);
    FClosedToolIds[High(FClosedToolIds)] := ToolId;
    If FPendingApprovalId = ToolId Then
      FPendingApprovalId := '';
    If FDisplayApprovalId = ToolId Then
      FDisplayApprovalId := '';
  Finally
    UnlockSession;
  End;
End;

End.
