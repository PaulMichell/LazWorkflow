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

  Size note: exceeds the 1000 line preference. What remains is connection state,
  command intake, and approval. The lane arrays and the second resume are gone.
  Catalogue 2 live-patch and log-credit helpers stay because the session and
  mirror tests still call them. Deleting those would change assertions those
  tests own.
  Reviewed 2026-11-07: no socket or form code in this unit. Known producers pass a lane
  to QueueFrame and do not parse the frame again. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, AssistantMonitorFrames, AssistantMonitorCarrier, AssistantMonitorCodec, AssistantMonitorMirror,
  AssistantMonitorOutbox, AssistantMonitorCommandIntake, AssistantMonitorSync, AssistantMonitorPlanFetch,
  AssistantSessionObserve;

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
  { Kept so older tests compile. The log budget is MonitorLogBudgetBytes. }
  MonitorRingCapacity = 256;
  { Closed approval ids remembered for this IDE session. Older ids are forgotten. }
  MonitorClosedToolMemory = 64;
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
  TMonitorCommandHandler = Procedure(Kind: Integer; Const Id: String; Const PayloadJson: TMonitorPayload) Of Object;
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
    { send, run_plan, or run_task accepted, before the form reports Sending or a plan run. }
    FSendPending: Boolean;
    FActiveCommandId: String;
    FActiveCommandKind: Integer;
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
    FPendingApprovalId: String;
    FDisplayApprovalId: String;
    FClosedToolIds: Array[0..MonitorClosedToolMemory - 1] Of String;
    FClosedToolHead: Integer;
    FClosedToolUsed: Integer;
    FRevokedIds: Array Of String;
    FOutbox: TMonitorOutbox;
    { True when the attached carrier's link takes the outbox. DrainOutbound must not also send. }
    FLinkPulls: Boolean;
    FIntake: TMonitorCommandIntake;
    { Highest event sequence the phone has acknowledged, and the highest put in the log lane. }
    FPhoneAcked: Int64;
    FQueuedLogSeq: Int64;
    LastFillHead, LastFillAck, LastFillQueued: Int64;
    LogFillSeen: Boolean;
    { Set when a resume names this stream. Catalogue 2 drains do not frame the log. }
    FLogResume: Boolean;
    { A resume got not_ready. The next observed turns are a baseline, not a second resume. }
    FAwaitingObservation: Boolean;
    FStateKeys: TStringArray;
    FStateValues: TStringArray;
    FEpoch: String;
    FConversationId: String;
    FProjectRoot: String;
    FTitle: String;
    FCommittedCursor: Int64;
    FNextCursor: Int64;
    FReservedCursor: Int64;
    FReservedPayload: RawByteString;
    FReservedHanded: Boolean;
    { Cursor of the live set currently in the state lane. Not a second queue. }
    FLiveCursor: Int64;
    FHasLivePatch: Boolean;
    FMirror: TMonitorMirror;
    FPlanFetch: TMonitorPlanFetch;
    FCredit: TMonitorLogCredit;
    FObserved: TMonitorSnapshot;
    FHasObserved: Boolean;
    FPendingCommand: Boolean;
    FPendingCommandKind: Integer;
    FPendingCommandId: String;
    FPendingCommandPayload: TMonitorPayload;
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
    { Caller holds the session lock. False when a bulk frame is refused. Unknown origin: classifies and validates. }
    Function QueueSend(Const Json: String): Boolean;
    { Caller holds the session lock. The producer already named the lane, so Json is not parsed.
      Seq is the log sequence, or the resume generation for bulk and barrier. Zero uses the plain bulk lane. }
    Function QueueFrame(Const Json: String; Lane: TMonitorSyncLane; Const StateKey: String; Seq: Int64): Boolean;
    Function QueueControl(Const Json: String): Boolean;
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
    Procedure HandleHello(Const PayloadJson: TMonitorPayload);
    Procedure HandlePair(Const PayloadJson: TMonitorPayload);
    Procedure HandleAuth(Const PayloadJson: TMonitorPayload);
    Procedure HandlePing(Const PayloadJson: TMonitorPayload);
    Procedure HandleBye;
    Procedure HandleCommand(Kind: Integer; Const Id: String; Const PayloadJson: TMonitorPayload);
    Procedure HandleResume(Const Id: String; Const PayloadJson: TMonitorPayload);
    Function CommandStatesFor(Const Id: String; Const Commands: TStringArray): String;
    Procedure PublishCommandState(Const Id, State, Reason, DoneText: String);

    Function ServeTurnFromMirror(Const Id: String; Const PayloadJson: TMonitorPayload): Boolean;
    Procedure ServeBlockGet(Const Id: String; Const PayloadJson: TMonitorPayload);
    Function LogFrameSeq(Const Json: String; Out Seq: Int64): Boolean;
    { One LAM1 frame for Json. False counts the frame in FFramesDropped and logs its type and status.
      Raw JSON is never returned in Bytes. The caller decides whether the failure closes the link. }
    Function EncodeHostFrame(Const Json: String; Out Bytes: RawByteString): Boolean;
    Procedure EnqueueAccepted(Const Json: String);
    { Caller holds the session lock. The previous unsent plan is counted as dropped. }
    Procedure StorePlanSend(Const Json: String);
    Procedure StorePlanFrames(Const Frames: TStringArray);
    Procedure QueueOverload(Const Json: String);
    Procedure CloseForQueueFailure;
    Procedure NoteLogAck(Const PayloadJson: TMonitorPayload);
    Procedure ReleaseHeldLog;
    Procedure HandleApproval(Const PayloadJson: TMonitorPayload);
    Function ClosedToolSeen(Const ToolId: String): Boolean;
    Procedure RememberClosedTool(Const ToolId: String);
    Function ApprovalRejectReason(Const ToolId: String): String;
    Function CommandBlocked(Kind: Integer; Out MessageText: String): Boolean;
    Procedure EnterBusy(Kind: Integer; Const Id: String; Const PayloadJson: TMonitorPayload);
    Procedure AdoptRunningHost;
    Procedure QueueBulkFramesLocked(Const Frames: TStringArray);
    Procedure CheckTimeoutsLocked;
    Procedure InboundFrame(Const Frame: TMonitorFrame);
    Function GetLastError: String;
    Function GetBoundAddress: String;
    Function GetConnectedClientName: String;
    { Locked reads for the link and IDE threads. The session lock is recursive, so a holder may call them. }
    Function GetState: TMonitorSessionState;
    Function GetCloseRequested: Boolean;
    Function LinkPulls: Boolean;
    Procedure QueueCommand(Kind: Integer; Const Id: String; Const PayloadJson: TMonitorPayload);
    Procedure FillLogLane;
    { Pulls is the caller's one read of LinkPulls. }
    Procedure PullPlanSlice(Pulls: Boolean);
    Procedure PlanFetchReady;
    Procedure QueueResumeAnswer(Const Answer: TMonitorSyncAnswer);
    Procedure RememberState(Const Key, ValueJson: String);
    Procedure PublishRememberedState;
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
    { Drops unsent pages and the carrier queue. Control frames already queued stay. }
    Procedure DiscardUnsentBulk;
    { Same conversation's stored epoch and cursor. The ring is empty, so resume snapshots. }
    Procedure RestoreMirror(Const Epoch, ConversationId, ProjectRoot, Title: String; Cursor: Int64);
    Function MirrorEpoch: String;
    Function MirrorCursor: Int64;
    { Oldest sequence the log has folded away. Zero when the tail from the start is still held. }
    Function MirrorDroppedThrough: Int64;
    { The harness folds the log without an 8 MiB fill. A later append applies the budget. }
    Procedure SetMirrorLogBudget(Bytes: Int64);
    { Marks the stream acked through Seq so a later append may fold older events. }
    Procedure NoteMirrorAck(Seq: Int64);
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
    { IDE thread. The file timer already hashed the file. Does not read it. }
    Procedure NotePlanCachedRevision(Const Path, Revision: String);
    Function HasMirrorModel: Boolean;
    Function CopyMirrorTurns(Out Stored: TMonitorMirrorTurnArray; Out Live: TAssistantMonitorTurn; Out HasLive: Boolean): Boolean;
    { Blocks the live pump already observed. Empty when the mirror has no live turn. }
    Function CopyLiveBlocks(Out Blocks: TAssistantMonitorBlockArray): Boolean;
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
    /// Queues into the outbox and does not drain. False when bulk is refused.
    Function TryQueueHostJson(Const Json: String): Boolean;
    /// Memory-carrier flush. A link that pulls the outbox ignores this.
    Procedure DrainOutbound;
    { The LAN carrier sets this so DrainOutbound does not also send. }
    Procedure NoteLinkPulls(Pulls: Boolean);
    { Wakes the controller when a frame is queued. Nil on the memory carrier. }
    Procedure SetOutboundWake(Handler: TMonitorOutboxWake);
    Function TakeOutboundFrame(Out Bytes: RawByteString): Boolean;
    { TakeOutboundFrame that also names the outbox lane the frame left from. The link does not need the lane;
      tests use it to check which lane a producer's frames reach. }
    Function TakeOutboundFrameWithLane(Out Bytes: RawByteString; Out Lane: TMonitorOutboxLane): Boolean;
    Function OutboxPending: Boolean;
    Function OutboundCount: Integer;
    Function PrepareOutboundCount: Integer;
    /// Next host frame id. Safe to call off the session lock.
    Function AllocateHostId: String;
    /// Queues one host frame and drains it. Does not build the JSON.
    Procedure SendHostJson(Const Json: String);
    { Replaces the unsent plan frames as one set and drains. A later plan drops the previous set. }
    Procedure ReplacePlanFrames(Const Frames: TStringArray);
    { Moves a recorded command and tells the phone. Unknown ids are ignored. }
    Procedure NoteCommandAccepted(Const Id: String);
    Procedure NoteCommandRejected(Const Id, Reason: String);
    Procedure NoteCommandDone(Const Id: String; Const DoneText: String = '');
    Procedure PublishState(Const Key, ValueJson: String);
    Procedure SetApprovalCloseHandler(Handler: TMonitorApprovalCloseHandler);
    Procedure SetIdleHandler(Handler: TMonitorIdleHandler);
    /// Records a pending or display id. Does not send a frame.
    Procedure NoteApprovalRequested(Const ToolId: String; DecisionsAccepted: Boolean);
    /// Records a closed id. Does not send a frame.
    Procedure NoteApprovalClosed(Const ToolId: String);
    Procedure PublishDisplayApproval(Const ToolId, ToolName, Summary, ModeCaption: String);
    Procedure CloseDisplayApproval(Const ToolId: String);
    Function ApplyApprovalDecision(Const ToolId: String; Allow: Boolean): Boolean;
    Procedure NoteApprovalCancel(Const ToolId: String);
    { Splits a payload into outbox chunk frames and queues every frame. Drains. }
    Procedure SendBulkPayload(Const ItemId, ItemType, PayloadJson: String);
    { Queues frames already split for the outbox. Drains. }
    Procedure SendPackedFrames(Const Frames: TStringArray);
    { One snapshot page for a turn the phone asked for. Does not send turn_data. }
    Procedure SendTurnPage(Const Id: String; Const Turn: TAssistantMonitorTurn);
    Property State: TMonitorSessionState Read GetState;
    Property Carrier: IMonitorCarrier Read FCarrier;
    Property OnCommand: TMonitorCommandHandler Read FOnCommand Write FOnCommand;
    Property CloseRequested: Boolean Read GetCloseRequested;
    Property FramesSent: Integer Read FFramesSent;
    Property FramesDropped: Integer Read FFramesDropped;
    Property LastError: String Read GetLastError;
    Property BoundAddress: String Read GetBoundAddress;
    Property BoundPort: Integer Read FPort;
    Property ConnectedClientName: String Read GetConnectedClientName;
    Property RemoteApproval: Boolean Read FRemoteApproval;
    Function SecondsSinceFrame: Integer;
    /// True after auth. A hello that has not been proved cannot take the open screen.
    Function ClientAuthenticated: Boolean;
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

Implementation

Uses
  SyncObjs, DateUtils, fpjson, jsonparser, fpsha256, fphashutils, WorkflowLog, AssistantProtocol, AssistantMonitorSettings;

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

{ True when Left and Right are the same bytes. The loop does not stop at the first mismatch. }
Function ConstantTimeEqual(Const Left, Right: String): Boolean;
Var
  Index, Limit, Diff, LeftByte, RightByte: Integer;
Begin
  Diff := Length(Left) Xor Length(Right);
  Limit := Length(Left);
  If Length(Right) > Limit Then
    Limit := Length(Right);
  For Index := 1 To Limit Do
    Begin
      LeftByte := 0;
      RightByte := 0;
      If Index <= Length(Left) Then
        LeftByte := Ord(Left[Index]);
      If Index <= Length(Right) Then
        RightByte := Ord(Right[Index]);
      Diff := Diff Or (LeftByte Xor RightByte);
    End;
  Result := Diff = 0;
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
  FPlanFetch := TMonitorPlanFetch.Create;
  FPlanFetch.OnReady := @PlanFetchReady;
  FCredit := TMonitorLogCredit.Create;
  FOutbox := TMonitorOutbox.Create;
  FIntake := TMonitorCommandIntake.Create;
  FPhoneAcked := 0;
  FQueuedLogSeq := 0;
  LogFillSeen := False;
  FLogResume := False;
  FSendPending := False;
  FActiveCommandId := '';
  FActiveCommandKind := 0;
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
  FPendingCommand := False;
  FPendingCommandKind := 0;
  FPendingCommandId := '';
  FPendingCommandPayload := '';
  FPendingApprovalId := '';
  FDisplayApprovalId := '';
  FClosedToolHead := 0;
  FClosedToolUsed := 0;
  SetLength(FRevokedIds, 0);
  FLinkPulls := False;
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
  FreeAndNil(FPlanFetch);
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
  THostLane = (hlControl, hlLive, hlPlan, hlBulk);

Function HostLane(Const Json: String): THostLane;
Var
  Message: TMonitorMessage;
  ErrorText: String;
Begin
  { An envelope the codec cannot decode stays on control. EncodeHostFrame has already refused text that is not JSON. }
  Result := hlControl;
  If Not TryDecodeMonitorEnvelope(Json, Message, ErrorText) Then
    Exit;
  If Message.TypeName = 'event' Then
    Exit(hlBulk);
  Case Message.Kind Of
    mmkPatch: Result := hlLive;
    mmkPlan: Result := hlPlan;
    mmkSnapshot, mmkTranscript, mmkCatchup, mmkImageData, mmkSnapshotPage, mmkChunk: Result := hlBulk;
  Else
    Result := hlControl;
  End;
End;

{ The "type" value of a frame, for a log line. The frame may not be JSON, so this is a text search. Only
  lowercase letters, digits and underscores are kept, at most 32 of them, so no frame content is logged. }
Function FrameTypeHint(Const Json: String): String;
Var
  At, Stop: Integer;
Begin
  Result := '?';
  At := Pos('"type"', Json);
  If At = 0 Then
    Exit;
  At := At + Length('"type"');
  While (At <= Length(Json)) And (Json[At] In [' ', ':']) Do
    Inc(At);
  If (At > Length(Json)) Or (Json[At] <> '"') Then
    Exit;
  Inc(At);
  Stop := At;
  While (Stop <= Length(Json)) And (Stop - At < 32) And (Json[Stop] In ['a'..'z', '0'..'9', '_']) Do
    Inc(Stop);
  If Stop > At Then
    Result := Copy(Json, At, Stop - At);
End;

Function TMonitorSession.EncodeHostFrame(Const Json: String; Out Bytes: RawByteString): Boolean;
Var
  Status: TMonitorFrameStatus;
  StatusName: String;
Begin
  Bytes := '';
  Result := False;
  If Json = '' Then
    Exit;
  If TryEncodeMonitorFrame(Json, Bytes, Status) Then
    Exit(True);
  { Raw JSON has no LAM1 header. The phone would read a bad magic and drop the link, and a resume would
    publish the same state again. So the frame is dropped here and is never queued. }
  Bytes := '';
  Inc(FFramesDropped);
  WriteStr(StatusName, Status);
  LogLine(2, 'frame not encoded type=' + FrameTypeHint(Json) + ' status=' + StatusName + ' bytes=' +
    IntToStr(Length(Json)));
End;

Function JsonMessageId(Const Json: String): String;
Var
  Message: TMonitorMessage;
  ErrorText: String;
Begin
  Result := '';
  If TryDecodeMonitorEnvelope(Json, Message, ErrorText) Then
    Result := Message.Id;
  If Result = '' Then
    Result := 'bulk';
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
    {$IFDEF MONITOR_COUNT_PARSES}
    MonitorNoteJsonParse;
    {$ENDIF}
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

Procedure TMonitorSession.StorePlanFrames(Const Frames: TStringArray);
Var
  Encoded: Array Of RawByteString;
  Index, Replaced: Integer;
Begin
  If (Length(Frames) = 0) Or Not Assigned(FOutbox) Then
    Exit;
  SetLength(Encoded, Length(Frames));
  For Index := 0 To High(Frames) Do
    If Not EncodeHostFrame(Frames[Index], Encoded[Index]) Then
      Begin
        CloseForQueueFailure;
        Exit;
      End;
  If Not FOutbox.ReplaceState('plan', Encoded, Replaced) Then
    CloseForQueueFailure
  Else If Replaced > 0 Then
    Inc(FFramesDropped);
End;

Procedure TMonitorSession.StorePlanSend(Const Json: String);
Var
  Frames: TStringArray;
Begin
  If Json = '' Then
    Exit;
  SetLength(Frames, 1);
  Frames[0] := Json;
  StorePlanFrames(Frames);
End;

Procedure TMonitorSession.ReplacePlanFrames(Const Frames: TStringArray);
Begin
  If Length(Frames) = 0 Then
    Exit;
  LockSession;
  Try
    StorePlanFrames(Frames);
  Finally
    UnlockSession;
  End;
  DrainOutbound;
End;

Procedure TMonitorSession.EnqueueAccepted(Const Json: String);
Begin
  QueueSend(Json);
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

Procedure TMonitorSession.NoteLogAck(Const PayloadJson: TMonitorPayload);
Var
  Data: TJSONData;
  Obj: TJSONObject;
  StreamId: String;
  Seq: Int64;
Begin
  Data := Nil;
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Begin
      Data.Free;
      Exit;
    End;
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
  If Assigned(FOutbox) Then
    FOutbox.Acknowledge(Seq);
  LockSession;
  Try
    If Seq > FPhoneAcked Then
      FPhoneAcked := Seq;
  Finally
    UnlockSession;
  End;
  If Assigned(FCredit) Then
    FCredit.NoteAck(Seq);
  ReleaseHeldLog;
  FillLogLane;
End;

Function FrameIsBye(Const Json: String): Boolean;
Var
  Message: TMonitorMessage;
  ErrorText: String;
Begin
  Result := TryDecodeMonitorEnvelope(Json, Message, ErrorText) And (Message.Kind = mmkBye);
End;

Procedure TMonitorSession.QueueOverload(Const Json: String);
Var
  Id, ErrorJson: String;
  Bytes: RawByteString;
Begin
  Id := JsonMessageId(Json);
  ErrorJson := EncodeMonitorError(Id, 'overloaded', 'The host cannot queue this now. Ask again.', Id);
  If Not EncodeHostFrame(ErrorJson, Bytes) Or Not Assigned(FOutbox) Or Not FOutbox.AddControl(Bytes) Then
    CloseToListening;
End;

Procedure TMonitorSession.CloseForQueueFailure;
Begin
  { A control or state frame that cannot be queued closes the link. Bye is best effort. }
  CloseToListening;
End;

Function TMonitorSession.QueueControl(Const Json: String): Boolean;
Begin
  Result := QueueFrame(Json, mslControl, '', 0);
End;

Function TMonitorSession.QueueFrame(Const Json: String; Lane: TMonitorSyncLane; Const StateKey: String; Seq: Int64): Boolean;
Var
  Bytes: RawByteString;
  One: Array Of RawByteString;
  Replaced: Integer;
Begin
  Result := False;
  If (Json = '') Or Not Assigned(FOutbox) Then
    Exit;
  If (Lane = mslLog) And (Seq > 0) And Assigned(FCredit) Then
    Begin
      If Not FCredit.CanSend(Length(Json)) Then
        Begin
          FCredit.Hold(Seq, Json);
          { One bye, then the same close CloseToListening uses. A later held frame must not queue another. }
          If (FCredit.HeldBytes > MonitorLogBudgetBytes) And (Not FCloseRequested) Then
            Begin
              QueueControl(EncodeMonitorBye(NewHostId, 'protocol'));
              CloseToListening;
            End;
          Result := True;
          Exit;
        End;
      FCredit.NoteSent(Seq, Length(Json));
    End;
  If Not EncodeMonitorFrameBytes(Json, Bytes) Then
    Begin
      Inc(FFramesDropped);
      LogLine(2, 'frame not encoded type=' + FrameTypeHint(Json) + ' status=mfsTooLarge bytes=' + IntToStr(Length(Json)));
      CloseToListening;
      Exit;
    End;
  SetLength(One, 1);
  One[0] := Bytes;
  Case Lane Of
    mslState:
      Begin
        If FOutbox.ReplaceState(StateKey, One, Replaced) Then
          Result := True
        Else
          CloseToListening;
      End;
    mslLog:
      Result := FOutbox.AppendLog(Seq, Bytes);
    mslBulk:
      Begin
        { A positive Seq is a resume generation. Plan and block slices pass zero and use the budgeted bulk lane. }
        If Seq > 0 Then
          Begin
            FOutbox.AddGeneratedBulk(Bytes, Seq);
            Result := True;
          End
        Else If FOutbox.AddBulk(One) Then
          Result := True
        Else
          QueueOverload(Json);
      End;
    mslBarrier:
      Begin
        If Seq > 0 Then
          FOutbox.HoldBarrier(Bytes, Seq)
        Else
          FOutbox.HoldBarrier(Bytes, 1);
        Result := True;
      End;
  Else
    If FOutbox.AddControl(Bytes) Then
      Result := True
    Else
      CloseToListening;
  End;
End;

Function TMonitorSession.QueueSend(Const Json: String): Boolean;
Var
  Lane: THostLane;
  SyncLane: TMonitorSyncLane;
  StateKey: String;
  Seq: Int64;
  Bytes: RawByteString;
  One: Array Of RawByteString;
  Replaced: Integer;
Begin
  Result := False;
  If (Json = '') Or Not Assigned(FOutbox) Then
    Exit;
  If LogFrameSeq(Json, Seq) And Assigned(FCredit) Then
    Begin
      If Not FCredit.CanSend(Length(Json)) Then
        Begin
          FCredit.Hold(Seq, Json);
          { One bye, then the same close CloseToListening uses. A later held frame must not queue another. }
          If (FCredit.HeldBytes > MonitorLogBudgetBytes) And (Not FCloseRequested) Then
            Begin
              QueueControl(EncodeMonitorBye(NewHostId, 'protocol'));
              CloseToListening;
            End;
          Result := True;
          Exit;
        End;
      FCredit.NoteSent(Seq, Length(Json));
    End;
  If MonitorSyncClassify(Json, SyncLane, StateKey) Then
    Begin
      If Not EncodeHostFrame(Json, Bytes) Then
        Begin
          CloseForQueueFailure;
          Exit;
        End;
      SetLength(One, 1);
      One[0] := Bytes;
      Case SyncLane Of
        mslState:
          Begin
            If FOutbox.ReplaceState(StateKey, One, Replaced) Then
              Result := True
            Else
              CloseForQueueFailure;
          End;
        mslLog:
          Result := FOutbox.AppendLog(MonitorSyncEventSeq(Json), Bytes);
        mslBulk:
          Begin
            If FOutbox.AddBulk(One) Then
              Result := True
            Else
              QueueOverload(Json);
          End;
        mslBarrier:
          Begin
            FOutbox.HoldBarrier(Bytes, 1);
            Result := True;
          End;
      Else
        If FOutbox.AddControl(Bytes) Then
          Result := True
        Else
          CloseForQueueFailure;
      End;
      Exit;
    End;
  If Not EncodeHostFrame(Json, Bytes) Then
    Begin
      If FrameIsBye(Json) Then
        Begin
          CloseToListening;
          Result := True;
        End
      Else
        CloseForQueueFailure;
      Exit;
    End;
  Lane := HostLane(Json);
  SetLength(One, 1);
  One[0] := Bytes;
  { Catalogue 2 live patches are not sent. Events travel on the log lane. }
  If Lane = hlLive Then
    Begin
      Inc(FFramesDropped);
      Result := True;
      Exit;
    End;
  If Lane = hlPlan Then
    Begin
      If Not FOutbox.ReplaceState('plan', One, Replaced) Then
        CloseForQueueFailure
      Else
        Begin
          If Replaced > 0 Then
            Inc(FFramesDropped);
          Result := True;
        End;
      Exit;
    End;
  If Lane = hlBulk Then
    Begin
      If FOutbox.AddBulk(One) Then
        Result := True
      Else
        QueueOverload(Json);
      Exit;
    End;
  If FOutbox.AddControl(Bytes) Then
    Result := True
  Else If FrameIsBye(Json) Then
    Begin
      CloseToListening;
      Result := True;
    End
  Else
    CloseForQueueFailure;
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

Function TMonitorSession.GetState: TMonitorSessionState;
Begin
  LockSession;
  Try
    Result := FState;
  Finally
    UnlockSession;
  End;
End;

Function TMonitorSession.GetCloseRequested: Boolean;
Begin
  LockSession;
  Try
    Result := FCloseRequested;
  Finally
    UnlockSession;
  End;
End;

Function TMonitorSession.LinkPulls: Boolean;
Begin
  LockSession;
  Try
    Result := FLinkPulls;
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
Var
  EmptyState: Array Of RawByteString;
  Dropped: Integer;
Begin
  SetLength(EmptyState, 0);
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
  { Control frames survive a close so the reject or bye queued in this turn can still drain.
    Bulk and state do not. A socket reset clears the whole outbox in NoteSocketClosed. }
  If Assigned(FOutbox) Then
    Begin
      FOutbox.DiscardBulk;
      FOutbox.ReplaceState('live', EmptyState, Dropped);
      FOutbox.ReplaceState('plan', EmptyState, Dropped);
    End;
  FHasLivePatch := False;
  FLiveCursor := 0;
  If Assigned(FPlanFetch) Then
    FPlanFetch.Cancel;
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

Function TMonitorSession.ClientAuthenticated: Boolean;
Begin
  LockSession;
  Try
    Result := FState In [mssLive, mssBusy];
  Finally
    UnlockSession;
  End;
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
  QueueControl(Json);
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

Procedure TMonitorSession.HandleHello(Const PayloadJson: TMonitorPayload);
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
  QueueControl(EncodeMonitorHelloOk(NewHostId, HelloOk));
End;

Procedure TMonitorSession.HandlePair(Const PayloadJson: TMonitorPayload);
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
      If Not ConstantTimeEqual(UpperCase(Trim(Pair.Code)), FPairCode) Then
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
  FClients[Index].PairedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', LocalTimeToUniversal(Now));
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
  QueueControl(EncodeMonitorPairOk(NewHostId, FClients[Index].Id, FClients[Index].Token));
  LogLine(1, 'pair success client=' + FClients[Index].Id + ' bind=' + FBindAddress + ' port=' + IntToStr(FPort));
End;

Procedure TMonitorSession.HandleAuth(Const PayloadJson: TMonitorPayload);
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
  If (Expected = '') Or (Not ConstantTimeEqual(LowerCase(Auth.Hmac), Expected)) Then
    Begin
      RejectLocked('auth', True);
      Exit;
    End;
  FClientName := FClients[Index].Name;
  FState := mssLive;
  AdoptRunningHost;
  LogLine(1, 'auth success client=' + Auth.ClientId + ' bind=' + FBindAddress + ' port=' + IntToStr(FPort));
End;

Procedure TMonitorSession.HandlePing(Const PayloadJson: TMonitorPayload);
Var
  Ticks: TMonitorTicks;
Begin
  If Not DecodeMonitorTicks(PayloadJson, Ticks) Then
    Ticks.Ticks := 0;
  QueueControl(EncodeMonitorTicks(mmkPong, NewHostId, Ticks.Ticks));
End;

Procedure TMonitorSession.HandleBye;
Begin
  LogLine(1, 'disconnect bind=' + FBindAddress + ' port=' + IntToStr(FPort));
  CloseToListening;
End;

Function TMonitorSession.CommandBlocked(Kind: Integer; Out MessageText: String): Boolean;

  Function HostBusy: Boolean;
  Begin
    Result := FHostFlags.Sending Or FSendPending;
  End;

Begin
  Result := False;
  MessageText := 'The desktop control is not available.';
  { CanSend starts false until the first status frame. An idle form still accepts Send.
    FSendPending is the gap before the form reports Sending. It blocks like a running turn. }
  If Kind = Ord(mmkSend) Then
    Result := HostBusy Or FHostFlags.PlanAgentRunning
  Else If Kind = Ord(mmkSetMode) Then
    Result := HostBusy Or FHostFlags.ModeLocked Or (Not FHostFlags.CanChangeMode)
  Else If Kind = Ord(mmkNewConversation) Then
    Result := HostBusy Or FHostFlags.PlanAgentRunning
  Else If Kind = Ord(mmkRunPlan) Then
    Result := HostBusy Or FHostFlags.PlanAgentRunning
  Else If Kind = Ord(mmkWorkOnPlan) Then
    Result := HostBusy
  Else If Kind = Ord(mmkRunTask) Then
    Result := HostBusy Or FHostFlags.PlanAgentRunning
  Else If (Kind = Ord(mmkClosePlan)) Or (Kind = Ord(mmkInsertTask)) Then
    Result := HostBusy Or FHostFlags.PlanAgentRunning
  Else If (Kind = Ord(mmkSelectPlan)) Or (Kind = Ord(mmkNewPlan)) Then
    Result := HostBusy
  Else If Kind = Ord(mmkSelectTarget) Then
    Begin
      { A bind stops in-flight work. Review is still the form's check. }
      Result := HostBusy Or FHostFlags.PlanAgentRunning;
      If HostBusy Then
        MessageText := 'Wait for the current reply to finish.'
      Else If FHostFlags.PlanAgentRunning Then
        MessageText := 'A plan run is already active.';
    End
  Else If Kind = Ord(mmkSelectConversation) Then
    Begin
      { The History combo refuses only while a reply is sending. }
      Result := HostBusy;
      If Result Then
        MessageText := 'Stop the current reply before switching History.';
    End
  Else If (Kind = Ord(mmkSetModel)) Or (Kind = Ord(mmkSetReasoning)) Or (Kind = Ord(mmkSetPermissions)) Then
    Begin
      { Review is still the form's check. A plan run is work in progress. }
      Result := HostBusy Or FHostFlags.PlanAgentRunning;
      If Result Then
        MessageText := 'Wait until the current work finishes before changing the model, effort, or permissions.';
    End
  Else If Kind = Ord(mmkSteer) Then
    Begin
      { The gap before Sending is reported is not a turn to steer, and it is not a second prompt. }
      If FSendPending Then
        Begin
          Result := True;
          MessageText := 'Wait for the current reply to finish.';
        End
      Else
        Begin
          Result := (FState <> mssBusy) Or (Not FHostFlags.CanSteer);
          If FState <> mssBusy Then
            MessageText := 'Nothing is running to steer.';
        End;
    End
  Else If Kind = Ord(mmkStop) Then
    Result := (FState = mssBusy) And (Not FHostFlags.CanStop);
End;

Procedure TMonitorSession.EnterBusy(Kind: Integer; Const Id: String; Const PayloadJson: TMonitorPayload);
Begin
  { The form, not this accept, is what makes the session busy. }
  If (Kind = Ord(mmkSend)) Or (Kind = Ord(mmkRunPlan)) Or (Kind = Ord(mmkRunTask)) Then
    Begin
      FSendPending := True;
      FActiveCommandId := Id;
      FActiveCommandKind := Kind;
    End;
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
    (Kind = Ord(mmkWorkOnPlan)) Or (Kind = Ord(mmkRunTask)) Or (Kind = Ord(mmkClosePlan)) Or
    (Kind = Ord(mmkInsertTask)) Or (Kind = Ord(mmkSelectPlan)) Or (Kind = Ord(mmkSelectTarget)) Or
    (Kind = Ord(mmkSelectConversation)) Or (Kind = Ord(mmkSetModel)) Or (Kind = Ord(mmkSetReasoning)) Or
    (Kind = Ord(mmkSetPermissions)) Or (Kind = Ord(mmkNewPlan));
End;

Procedure TMonitorSession.HandleCommand(Kind: Integer; Const Id: String; Const PayloadJson: TMonitorPayload);
Var
  Blocked: Boolean;
  MessageText: String;
  Prior: TMonitorCommandRecord;
  Admitted: TMonitorIntakeResult;
Begin
  Admitted := mirInvalid;
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
          QueueControl(EncodeMonitorCommandState(NewHostId, Prior.Id, MonitorCommandStateName(Prior.State), Prior.Reason));
          Exit;
        End;
    End;
  If Kind = Ord(mmkStop) Then
    Begin
      If CommandBlocked(Kind, MessageText) Then
        Begin
          If (Id <> '') And (Id = FActiveCommandId) Then
            Begin
              FSendPending := False;
              FActiveCommandId := '';
            End;
          FIntake.NoteRejected(Id, MonitorHostBusyReason);
          QueueControl(EncodeMonitorError(NewHostId, MonitorHostBusyReason, MessageText, Id));
        End
      Else
        Begin
          If RecordedCommand(Kind) And (Admitted = mirQueued) Then
            QueueControl(EncodeMonitorCommandState(NewHostId, Id, 'queued', ''));
          If FState = mssBusy Then
            FState := mssLive;
          QueueCommand(Kind, Id, PayloadJson);
        End;
      Exit;
    End;
  { A dropped socket clears busy. A steer that arrives before the next snapshot is a prompt, not a steer.
    One already accepted, and not yet reported as Sending, must not become a second prompt. }
  If (Kind = Ord(mmkSteer)) And (Not FSendPending) And ((FState <> mssBusy) Or (Not FHostFlags.CanSteer)) And
    (FState = mssLive) And FHostFlags.CanSend And (Not FHostFlags.Sending) And (Not FHostFlags.PlanAgentRunning) Then
    Begin
      LogLine(1, 'steer submitted as send bind=' + FBindAddress + ' port=' + IntToStr(FPort));
      If RecordedCommand(Kind) And (Admitted = mirQueued) Then
        QueueControl(EncodeMonitorCommandState(NewHostId, Id, 'queued', ''));
      EnterBusy(Ord(mmkSend), Id, PayloadJson);
      Exit;
    End;
  Blocked := CommandBlocked(Kind, MessageText);
  If Blocked Then
    Begin
      If (Id <> '') And (Id = FActiveCommandId) Then
        Begin
          FSendPending := False;
          FActiveCommandId := '';
        End;
      FIntake.NoteRejected(Id, MonitorHostBusyReason);
      QueueControl(EncodeMonitorError(NewHostId, MonitorHostBusyReason, MessageText, Id));
      Exit;
    End;
  If Kind = Ord(mmkTurn) Then
    Begin
      If ServeTurnFromMirror(Id, PayloadJson) Then
        Exit;
    End;
  If RecordedCommand(Kind) And (Admitted = mirQueued) Then
    QueueControl(EncodeMonitorCommandState(NewHostId, Id, 'queued', ''));
  If (Kind = Ord(mmkSend)) Or (Kind = Ord(mmkRunPlan)) Or (Kind = Ord(mmkWorkOnPlan)) Or (Kind = Ord(mmkRunTask)) Then
    EnterBusy(Kind, Id, PayloadJson)
  Else
    QueueCommand(Kind, Id, PayloadJson);
End;

Procedure TMonitorSession.HandleResume(Const Id: String; Const PayloadJson: TMonitorPayload);
Var
  ResumeMsg: TMonitorResume;
  Source: TMonitorResumeSource;
  Status: TMonitorSyncStatus;
  Answer: TMonitorSyncAnswer;
Begin
  If (FState <> mssLive) And (FState <> mssBusy) Then
    Begin
      RejectLocked('auth', True);
      Exit;
    End;
  If Not DecodeMonitorResume(PayloadJson, ResumeMsg) Then
    Begin
      QueueControl(EncodeMonitorError(NewHostId, 'protocol', 'Resume payload is not valid.', Id));
      Exit;
    End;
  If Assigned(FOutbox) Then
    Begin
      FOutbox.ClearLog;
      FOutbox.DiscardBulk;
    End;
  Source := Default(TMonitorResumeSource);
  If Assigned(FMirror) Then
    FMirror.CaptureResume(ResumeMsg.ConversationId, Source);
  { A cached id is not the chat on the desktop. Serve the open mirror, or the phone stays blank. }
  If (Not Source.Found) And Assigned(FMirror) And (FConversationId <> '') Then
    FMirror.CaptureResume('', Source);
  Status := Default(TMonitorSyncStatus);
  Status.Busy := FHostFlags.Sending Or FHostFlags.PlanAgentRunning;
  Status.Sending := FHostFlags.Sending;
  Status.PlanRunning := FHostFlags.PlanAgentRunning;
  Status.CanSend := FHostFlags.CanSend;
  Status.CanSteer := FHostFlags.CanSteer;
  Status.CanStop := FHostFlags.CanStop;
  Status.CanChangeMode := FHostFlags.CanChangeMode;
  Status.ApprovalActive := FRemoteApproval And (FPendingApprovalId <> '') And (FDisplayApprovalId = '');
  Status.ApprovalToolId := FPendingApprovalId;
  PublishRememberedState;
  { The tool id and the conversation id are escaped by the AssistantMonitorSync writers. }
  PublishState('status', MonitorResumeStatusValueJson(Status));
  PublishState('approval', MonitorApprovalValueJson(Status.ApprovalActive, Status.ApprovalToolId));
  If (FConversationId <> '') And (FConversationId <> 'current') Then
    PublishState('conversation', MonitorConversationValueJson(FConversationId));
  Answer := MonitorSyncResumeAnswer(Source, ResumeMsg.ConversationId, ResumeMsg.Epoch, Id, ResumeMsg.Cursor, Status);
  QueueResumeAnswer(Answer);
  LogFillSeen := False;
  FPhoneAcked := ResumeMsg.Cursor;
  If Answer.Replay Then
    Begin
      FLogResume := True;
      FQueuedLogSeq := ResumeMsg.Cursor;
      FAwaitingObservation := False;
      If Assigned(FMirror) Then
        FMirror.NoteAck(ResumeMsg.Epoch, ResumeMsg.Cursor);
    End
  Else If Answer.NotReady Then
    Begin
      FLogResume := False;
      FQueuedLogSeq := 0;
      LogFillSeen := False;
      { The open chat may still be loading. Push it when the mirror observes, even if the
        phone asked for a cache id that is not this conversation. }
      FAwaitingObservation := (ResumeMsg.ConversationId = '') Or (ResumeMsg.ConversationId = FConversationId) Or
        (Not Source.Found) Or (Source.ConversationId = FConversationId);
    End
  Else
    Begin
      FLogResume := True;
      FQueuedLogSeq := Answer.Head;
      FAwaitingObservation := False;
    End;
  If Length(ResumeMsg.Commands) > 0 Then
    QueueControl(CommandStatesFor(NewHostId, ResumeMsg.Commands));
End;

Function TMonitorSession.ClosedToolSeen(Const ToolId: String): Boolean;
Var
  Index, Slot: Integer;
Begin
  Result := False;
  If (ToolId = '') Or (FClosedToolUsed < 1) Then
    Exit;
  { Newest first. A resent decision is usually for a recent close. }
  For Index := FClosedToolUsed - 1 DownTo 0 Do
    Begin
      Slot := (FClosedToolHead + Index) Mod MonitorClosedToolMemory;
      If FClosedToolIds[Slot] = ToolId Then
        Exit(True);
    End;
End;

Procedure TMonitorSession.RememberClosedTool(Const ToolId: String);
Var
  Slot: Integer;
Begin
  If (ToolId = '') Or ClosedToolSeen(ToolId) Then
    Exit;
  If FClosedToolUsed < MonitorClosedToolMemory Then
    Begin
      Slot := (FClosedToolHead + FClosedToolUsed) Mod MonitorClosedToolMemory;
      Inc(FClosedToolUsed);
    End
  Else
    Begin
      Slot := FClosedToolHead;
      FClosedToolHead := (FClosedToolHead + 1) Mod MonitorClosedToolMemory;
    End;
  FClosedToolIds[Slot] := ToolId;
End;

Function TMonitorSession.ApplyApprovalDecision(Const ToolId: String; Allow: Boolean): Boolean;
Begin
  Result := False;
  If (ToolId = '') Or (Not FRemoteApproval) Then
    Exit;
  If ClosedToolSeen(ToolId) Then
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
Begin
  Result := '';
  If (ToolId = '') Or (Not FRemoteApproval) Then
    Exit;
  If ReadAssistantApprovalDecision = aadStopped Then
    Exit('stopped');
  If ClosedToolSeen(ToolId) Then
    Exit('finished');
  If (ToolId = FDisplayApprovalId) Or (ToolId <> FPendingApprovalId) Then
    Result := 'finished';
End;

Procedure TMonitorSession.HandleApproval(Const PayloadJson: TMonitorPayload);
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
  If Message.TypeName = 'plan_get' Then
    Begin
      If (FState <> mssLive) And (FState <> mssBusy) Then
        RejectLocked('auth', True)
      Else If Assigned(FPlanFetch) Then
        FPlanFetch.BeginGet(Message.Id, Message.PayloadJson, FProjectRoot);
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
    mmkClosePlan, mmkInsertTask, mmkSelectPlan, mmkSelectTarget, mmkSelectConversation, mmkSetModel, mmkSetReasoning,
    mmkSetPermissions, mmkNewPlan, mmkRefresh, mmkTurn, mmkImageGet:
      HandleCommand(Ord(Message.Kind), Message.Id, Message.PayloadJson);
  Else
    If (FState = mssLive) Or (FState = mssBusy) Then
      QueueSend(Message.WireJson)
    Else
      RejectLocked('auth', True);
  End;
End;

Procedure TMonitorSession.QueueCommand(Kind: Integer; Const Id: String; Const PayloadJson: TMonitorPayload);
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
Begin
  If Length(Frames) = 0 Then
    Exit;
  SetLength(Chunks, Length(Frames));
  For Index := 0 To High(Frames) Do
    If Not EncodeMonitorFrameBytes(Frames[Index], Chunks[Index]) Then
      Begin
        QueueOverload(Frames[0]);
        Exit;
      End;
  If (Not Assigned(FOutbox)) Or (Not FOutbox.AddBulk(Chunks)) Then
    QueueOverload(Frames[0]);
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
      QueueControl(EncodeMonitorTicks(mmkPing, NewHostId, Int64(ClockMs)));
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
      QueueControl(EncodeMonitorBye(NewHostId, 'disabled'));
    FCloseRequested := True;
    ClearConnection;
    FState := mssStopped;
    LogLine(1, 'listen stop bind=' + FBindAddress + ' port=' + IntToStr(FPort));
  Finally
    UnlockSession;
  End;
  FlushLivePatch;
  DrainOutbound;
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
    If Assigned(FOutbox) Then
      FOutbox.Clear;
    LogFillSeen := False;
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
  DrainOutbound;
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
Var
  WasSending, WasPlan: Boolean;
  DoneId: String;
Begin
  DoneId := '';
  LockSession;
  Try
    WasSending := FHostFlags.Sending;
    WasPlan := FHostFlags.PlanAgentRunning;
    FHostFlags := Flags;
    If Flags.Sending Or Flags.PlanAgentRunning Then
      FSendPending := False;
    AdoptRunningHost;
    If FActiveCommandId <> '' Then
      Begin
        If (FActiveCommandKind = Ord(mmkSend)) And WasSending And (Not Flags.Sending) Then
          Begin
            DoneId := FActiveCommandId;
            FActiveCommandId := '';
          End
        Else If ((FActiveCommandKind = Ord(mmkRunPlan)) Or (FActiveCommandKind = Ord(mmkRunTask))) And WasPlan And
          (Not Flags.PlanAgentRunning) Then
          Begin
            DoneId := FActiveCommandId;
            FActiveCommandId := '';
          End;
      End;
  Finally
    UnlockSession;
  End;
  If DoneId <> '' Then
    NoteCommandDone(DoneId);
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
        QueueControl(EncodeMonitorBye(NewHostId, 'revoked'));
        FCloseRequested := True;
        LogLine(1, 'revoke client=' + ClientId + ' bind=' + FBindAddress + ' port=' + IntToStr(FPort));
      End;
  Finally
    UnlockSession;
  End;
  DrainOutbound;
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
        QueueControl(EncodeMonitorBye(NewHostId, 'revoked'));
        FCloseRequested := True;
      End;
  Finally
    UnlockSession;
  End;
  DrainOutbound;
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
    FLogResume := False;
    LogFillSeen := False;
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

Procedure TMonitorSession.DiscardUnsentBulk;
Var
  Gone: Array Of RawByteString;
  Replaced: Integer;
Begin
  LockSession;
  Try
    FHasLivePatch := False;
    FLiveCursor := 0;
    If Assigned(FOutbox) Then
      Begin
        FOutbox.DiscardBulk;
        SetLength(Gone, 0);
        FOutbox.ReplaceState('live', Gone, Replaced);
      End;
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
  Encoded: Array Of RawByteString;
  Index, Replaced: Integer;
Begin
  LockSession;
  Try
    If Not Assigned(FOutbox) Then
      Exit;
    SetLength(Encoded, 0);
    If Length(Frames) = 0 Then
      Begin
        If FOutbox.ReplaceState('live', Encoded, Replaced) And (Replaced > 0) Then
          Inc(FFramesDropped, Replaced);
        FHasLivePatch := False;
        FLiveCursor := 0;
        Exit;
      End;
    SetLength(Encoded, Length(Frames));
    For Index := 0 To High(Frames) Do
      If Not EncodeHostFrame(Frames[Index], Encoded[Index]) Then
        Begin
          CloseForQueueFailure;
          Exit;
        End;
    If Not FOutbox.ReplaceState('live', Encoded, Replaced) Then
      CloseForQueueFailure
    Else
      Begin
        If Replaced > 0 Then
          Inc(FFramesDropped, Replaced);
        FLiveCursor := Cursor;
        FHasLivePatch := True;
      End;
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.FlushLivePatch;
Var
  Cursor: Int64;
  Had: Boolean;
Begin
  LockSession;
  Try
    Had := FHasLivePatch;
    Cursor := FLiveCursor;
    FHasLivePatch := False;
    FLiveCursor := 0;
  Finally
    UnlockSession;
  End;
  { The set is already in the state lane. Handed means the outbox accepted it. }
  If Had Then
    NoteMirrorHanded(Cursor);
  If Not LinkPulls Then
    DrainOutbound;
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

Procedure TMonitorSession.SetMirrorLogBudget(Bytes: Int64);
Begin
  If Assigned(FMirror) Then
    FMirror.SetLogBudget(Bytes);
End;

Procedure TMonitorSession.NoteMirrorAck(Seq: Int64);
Begin
  LockSession;
  Try
    If Seq > FPhoneAcked Then
      FPhoneAcked := Seq;
    If Assigned(FMirror) Then
      FMirror.NoteAck(FEpoch, Seq);
  Finally
    UnlockSession;
  End;
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
  If Assigned(FOutbox) Then
    FOutbox.Notify;
End;

Procedure TMonitorSession.RememberState(Const Key, ValueJson: String);
Var
  Index: Integer;
Begin
  For Index := 0 To High(FStateKeys) Do
    If FStateKeys[Index] = Key Then
      Begin
        FStateValues[Index] := ValueJson;
        Exit;
      End;
  SetLength(FStateKeys, Length(FStateKeys) + 1);
  SetLength(FStateValues, Length(FStateValues) + 1);
  FStateKeys[High(FStateKeys)] := Key;
  FStateValues[High(FStateValues)] := ValueJson;
End;

{ One parse of the value. The envelope is built from that value, so QueueFrame does not parse it again.
  An invalid value is dropped, which is what a raw embed of broken JSON used to fail in TryEncodeMonitorFrame. }
Function StateValueIsJson(Const ValueJson: String): Boolean;
Var
  Data: TJSONData;
Begin
  Result := False;
  Data := Nil;
  Try
    Try
      If ValueJson = '' Then
        Exit;
      {$IFDEF MONITOR_COUNT_PARSES}
      MonitorNoteJsonParse;
      {$ENDIF}
      Data := GetJSON(ValueJson);
    Except
      Exit;
    End;
    Result := Assigned(Data);
  Finally
    Data.Free;
  End;
End;

Procedure TMonitorSession.PublishState(Const Key, ValueJson: String);
Var
  Frames: TStringArray;
  Encoded: Array Of RawByteString;
  Index, Replaced: Integer;
  Lane: TMonitorSyncLane;
Begin
  If (Key = '') Or (Not Assigned(FOutbox)) Then
    Exit;
  RememberState(Key, ValueJson);
  If Not StateValueIsJson(ValueJson) Then
    Begin
      Inc(FFramesDropped);
      Exit;
    End;
  Frames := MonitorSyncStateFrames(NewHostId, Key, ValueJson);
  If Key = 'approval' Then
    Lane := mslControl
  Else
    Lane := mslState;
  { Chunks of one key are one ReplaceState. QueueFrame replaces a single part, so a loop would keep only the last. }
  If (Lane = mslState) And (Length(Frames) > 1) Then
    Begin
      SetLength(Encoded, Length(Frames));
      For Index := 0 To High(Frames) Do
        If Not EncodeMonitorFrameBytes(Frames[Index], Encoded[Index]) Then
          Begin
            Inc(FFramesDropped);
            Exit;
          End;
      If Not FOutbox.ReplaceState(Key, Encoded, Replaced) Then
        CloseToListening;
      Exit;
    End;
  For Index := 0 To High(Frames) Do
    If Not QueueFrame(Frames[Index], Lane, Key, 0) Then
      Exit;
End;

Procedure TMonitorSession.PublishRememberedState;
Var
  Index: Integer;
Begin
  For Index := 0 To High(FStateKeys) Do
    PublishState(FStateKeys[Index], FStateValues[Index]);
End;

Procedure TMonitorSession.QueueResumeAnswer(Const Answer: TMonitorSyncAnswer);
Var
  Index: Integer;
  Json: String;
  Lane: TMonitorSyncLane;
Begin
  If Not Assigned(FOutbox) Then
    Exit;
  For Index := 0 To High(Answer.Frames) Do
    Begin
      Json := Answer.Frames[Index].Json;
      { Oversize is skipped, as the old encode failure was. A fitting frame is queued without a parse. }
      If (Json = '') Or (Length(Json) > MonitorMaxPayloadBytes) Then
        Begin
          If Json <> '' Then
            Inc(FFramesDropped);
          Continue;
        End;
      Case Answer.Frames[Index].Kind Of
        mskBulk: Lane := mslBulk;
        mskBarrier: Lane := mslBarrier;
      Else
        Lane := mslControl;
      End;
      QueueFrame(Json, Lane, '', Answer.Generation);
    End;
End;

Procedure TMonitorSession.FillLogLane;
Var
  CloseLink: Boolean;
  Queued, Acked: Int64;
  Source: TMonitorResumeSource;
  Status: TMonitorSyncStatus;
  Answer: TMonitorSyncAnswer;
Begin
  CloseLink := False;
  LockSession;
  Try
    If FAwaitingObservation And Assigned(FMirror) And FMirror.HasConversation And Assigned(FOutbox) Then
      Begin
        Source := Default(TMonitorResumeSource);
        FMirror.CaptureResume('', Source);
        Status := Default(TMonitorSyncStatus);
        Status.Busy := FHostFlags.Sending Or FHostFlags.PlanAgentRunning;
        Status.Sending := FHostFlags.Sending;
        Status.CanSend := FHostFlags.CanSend;
        Answer := MonitorSyncResumeAnswer(Source, FConversationId, '', 'observed', 0, Status);
        If Not Answer.NotReady Then
          Begin
            QueueResumeAnswer(Answer);
            FAwaitingObservation := False;
            FLogResume := True;
            FQueuedLogSeq := Answer.Head;
          End;
      End;
    If (Not FLogResume) Or Not Assigned(FMirror) Or Not Assigned(FOutbox) Or (FQueuedLogSeq >= FMirror.Head) Then
      Exit;
    If LogFillSeen And (LastFillHead = FMirror.Head) And (LastFillAck = FPhoneAcked) And
      (LastFillQueued = FQueuedLogSeq) Then
      Exit;
    Queued := FQueuedLogSeq;
    Acked := FPhoneAcked;
    LastFillHead := FMirror.Head;
    MonitorSyncFill(FMirror, FOutbox, FConversationId, FEpoch, Acked, Queued, CloseLink);
    FQueuedLogSeq := Queued;
    LastFillAck := Acked;
    LastFillQueued := Queued;
    LogFillSeen := True;
    If CloseLink Then
      CloseToListening;
  Finally
    UnlockSession;
  End;
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

Function TMonitorSession.CopyLiveBlocks(Out Blocks: TAssistantMonitorBlockArray): Boolean;
Begin
  SetLength(Blocks, 0);
  Result := False;
  If Not Assigned(FMirror) Then
    Exit;
  Result := FMirror.CopyLiveBlocks(Blocks);
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

Procedure TMonitorSession.ServeBlockGet(Const Id: String; Const PayloadJson: TMonitorPayload);
Var
  Data: TJSONData;
  Obj, Payload: TJSONObject;
  BlockId, Body, Piece: String;
  Bytes: UTF8String;
  Offset, Total, Taken, AskedRevision, HeldRevision: Integer;
  Last, HasRevision: Boolean;
Begin
  Data := Nil;
  BlockId := '';
  Offset := 0;
  AskedRevision := 0;
  HasRevision := False;
  If Not ParseMonitorObject(PayloadJson, Data, Obj) Then
    Begin
      Data.Free;
      QueueControl(EncodeMonitorError(NewHostId, 'protocol', 'Block fetch payload is not valid.', Id));
      Exit;
    End;
  Try
    BlockId := Obj.Get('block_id', '');
    If Assigned(Obj.Find('offset')) And (Obj.Find('offset').JSONType = jtNumber) Then
      Offset := Obj.Find('offset').AsInteger;
    HasRevision := Assigned(Obj.Find('revision')) And (Obj.Find('revision').JSONType = jtNumber);
    If HasRevision Then
      AskedRevision := Obj.Find('revision').AsInteger;
  Finally
    Data.Free;
  End;
  { The envelope decode already refused an unsafe Id. A block id is echoed only after FetchBlock
    finds it in the mirror, so it is one the host wrote. Both are still escaped below. }
  If (BlockId = '') Or (Offset < 0) Or (Not Assigned(FMirror)) Or (Not FMirror.FetchBlock(BlockId, Body)) Then
    Begin
      QueueControl(EncodeMonitorError(NewHostId, 'not_found', 'Block was not found.', Id));
      Exit;
    End;
  HeldRevision := FMirror.BlockRevision(BlockId);
  If HasRevision And (AskedRevision <> HeldRevision) Then
    Begin
      QueueControl('{"v":3,"id":"' + NewHostId + '","type":"revision_changed","payload":{"ref":"' + JsonEscapeText(Id) +
        '","block_id":"' + JsonEscapeText(BlockId) + '","revision":' + IntToStr(HeldRevision) + '}}');
      Exit;
    End;
  Bytes := UTF8String(Body);
  Total := Length(Bytes);
  If Offset > Total Then
    Offset := Total;
  Repeat
    Taken := Total - Offset;
    If Taken > MonitorBlockDataBytes Then
      Taken := MonitorBlockDataBytes;
    While (Taken > 0) And (Offset + Taken < Total) And ((Ord(Bytes[Offset + Taken]) And $C0) = $80) Do
      Dec(Taken);
    If (Taken < 1) And (Offset < Total) Then
      Taken := 1;
    Piece := String(Copy(Bytes, Offset + 1, Taken));
    Last := Offset + Taken = Total;
    Payload := TJSONObject.Create;
    Try
      Payload.Add('conversation_id', FConversationId);
      Payload.Add('block_id', BlockId);
      Payload.Add('offset', Offset);
      Payload.Add('text', Piece);
      Payload.Add('total_bytes', Total);
      Payload.Add('last', Last);
      QueueFrame('{"v":3,"id":"' + NewHostId + '","type":"block_data","payload":' + Payload.AsJSON + '}', mslBulk, '', 0);
    Finally
      Payload.Free;
    End;
    Offset := Offset + Taken;
  Until Last;
End;

Function TMonitorSession.ServeTurnFromMirror(Const Id: String; Const PayloadJson: TMonitorPayload): Boolean;
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
    QueueControl(EncodeMonitorApprovalRequested(NewHostId, Notice));
  Finally
    UnlockSession;
  End;
  DrainOutbound;
End;

Procedure TMonitorSession.CloseDisplayApproval(Const ToolId: String);
Begin
  LockSession;
  Try
    If ToolId = '' Then
      Exit;
    RememberClosedTool(ToolId);
    If FDisplayApprovalId = ToolId Then
      FDisplayApprovalId := '';
    If FPendingApprovalId = ToolId Then
      FPendingApprovalId := '';
    QueueControl(EncodeMonitorApprovalClosed(NewHostId, ToolId, 'desktop'));
  Finally
    UnlockSession;
  End;
  DrainOutbound;
End;

Procedure TMonitorSession.NoteApprovalCancel(Const ToolId: String);
Begin
  LockSession;
  Try
    If (ToolId <> '') And ((ToolId = FPendingApprovalId) Or (FPendingApprovalId = '')) Then
      FPendingApprovalId := ToolId;
    StoreAssistantApprovalDecision(aadStopped);
    SignalAssistantApprovalWait;
  Finally
    UnlockSession;
  End;
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
  CommandId, CloseId, CloseReason: String;
  CommandPayload: TMonitorPayload;
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
    FPendingCommandPayload := '';
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
  { Apply the command before flushing bulk. A blocked bulk write must not swallow a send. }
  If RunClose And Assigned(CloseHandler) Then
    CloseHandler(CloseId, CloseReason);
  If RunCommand And Assigned(Handler) Then
    Handler(CommandKind, CommandId, CommandPayload);
  DrainOutbound;
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

Procedure TMonitorSession.NoteLinkPulls(Pulls: Boolean);
Begin
  LockSession;
  Try
    FLinkPulls := Pulls;
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.SetOutboundWake(Handler: TMonitorOutboxWake);
Begin
  If Assigned(FOutbox) Then
    FOutbox.OnWake := Handler;
End;

Function TMonitorSession.TakeOutboundFrame(Out Bytes: RawByteString): Boolean;
Var
  Lane: TMonitorOutboxLane;
Begin
  Result := TakeOutboundFrameWithLane(Bytes, Lane);
End;

Function TMonitorSession.TakeOutboundFrameWithLane(Out Bytes: RawByteString; Out Lane: TMonitorOutboxLane): Boolean;
Begin
  If LinkPulls Then
    PullPlanSlice(True);
  FillLogLane;
  Bytes := '';
  Lane := molControl;
  Result := Assigned(FOutbox) And FOutbox.Take(Bytes, Lane);
End;

Function TMonitorSession.PrepareOutboundCount: Integer;
Begin
  FillLogLane;
  Result := OutboundCount;
End;

Function TMonitorSession.OutboxPending: Boolean;
Begin
  Result := PrepareOutboundCount > 0;
End;

Function TMonitorSession.OutboundCount: Integer;
Begin
  Result := 0;
  If Not Assigned(FOutbox) Then
    Exit;
  Result := FOutbox.PendingFrameCount;
End;

Procedure TMonitorSession.PlanFetchReady;
Begin
  If Assigned(FOutbox) Then
    FOutbox.Notify;
End;

Procedure TMonitorSession.NotePlanCachedRevision(Const Path, Revision: String);
Begin
  If Assigned(FPlanFetch) Then
    FPlanFetch.NoteCachedRevision(Path, Revision);
End;

Procedure TMonitorSession.PullPlanSlice(Pulls: Boolean);
Var
  Json: String;
  Bulk: Boolean;
  Lane: TMonitorSyncLane;
Begin
  If Not Assigned(FPlanFetch) Or Not FPlanFetch.Ready Then
    Exit;
  { One slice in the bulk lane. A larger plan must not fill the 4 MiB budget. }
  If Pulls And ((Not Assigned(FOutbox)) Or (FOutbox.LaneCount(molBulk) > 0)) Then
    Exit;
  LockSession;
  Try
    If (FState <> mssLive) And (FState <> mssBusy) Then
      Exit;
    If Not FPlanFetch.Take(Json, Bulk) Then
      Exit;
    If Bulk Then
      Lane := mslBulk
    Else
      Lane := mslControl;
    If Not QueueFrame(Json, Lane, '', 0) Then
      FPlanFetch.Cancel;
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.DrainOutbound;
Var
  Bytes: RawByteString;
  Lane: TMonitorOutboxLane;
  Frame: TMonitorFrame;
  Status: TMonitorFrameStatus;
  Pulls: Boolean;
Begin
  { One read, so the pull and the wake below agree if the link changes mode meanwhile. }
  Pulls := LinkPulls;
  If Not Pulls Then
    PullPlanSlice(False);
  FillLogLane;
  { The link takes the outbox. Wake it; do not also send. }
  If Pulls Then
    Begin
      If Assigned(FOutbox) Then
        FOutbox.Notify;
      Exit;
    End;
  If Not Assigned(FOutbox) Then
    Exit;
  While FOutbox.Take(Bytes, Lane) Do
    If TryDecodeMonitorFrame(Bytes, Frame, Status) And (Status = mfsOk) Then
      Transmit(Frame.Json)
    Else
      Transmit(String(Bytes));
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
      Replies[Index].Text := '';
      If FIntake.Lookup(Commands[Index], Found) Then
        Begin
          Replies[Index].State := MonitorCommandStateName(Found.State);
          Replies[Index].Reason := Found.Reason;
          Replies[Index].Text := Found.Text;
        End
      Else
        Replies[Index].State := 'unknown';
    End;
  Result := EncodeMonitorCommandStates(Id, Replies);
End;

Procedure TMonitorSession.PublishCommandState(Const Id, State, Reason, DoneText: String);
Begin
  SendHostJson(EncodeMonitorCommandState(AllocateHostId, Id, State, Reason, DoneText));
End;

Procedure TMonitorSession.NoteCommandAccepted(Const Id: String);
Begin
  If Not FIntake.NoteAccepted(Id) Then
    Exit;
  PublishCommandState(Id, 'accepted', '', '');
End;

Procedure TMonitorSession.NoteCommandRejected(Const Id, Reason: String);
Begin
  LockSession;
  Try
    If (Id <> '') And (Id = FActiveCommandId) Then
      Begin
        FSendPending := False;
        FActiveCommandId := '';
      End;
  Finally
    UnlockSession;
  End;
  { The wire answer is error. The table keeps rejected for a later resume. }
  FIntake.NoteRejected(Id, Reason);
End;

Procedure TMonitorSession.NoteCommandDone(Const Id: String; Const DoneText: String);
Begin
  If Not FIntake.NoteDone(Id, DoneText) Then
    Exit;
  PublishCommandState(Id, 'done', '', DoneText);
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
    RememberClosedTool(ToolId);
    If FPendingApprovalId = ToolId Then
      FPendingApprovalId := '';
    If FDisplayApprovalId = ToolId Then
      FDisplayApprovalId := '';
  Finally
    UnlockSession;
  End;
End;

End.
