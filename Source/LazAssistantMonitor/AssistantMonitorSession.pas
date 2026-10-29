Unit AssistantMonitorSession;

{ Monitor session state machine. The LAN carrier owns the socket.
  This unit does not use TInetServer. An in-memory carrier delivers frames
  through SetFrameHandler. No relay class is compiled. (c) 2026 Michell Computing.

  Open LAN admits pair when no code is armed. RequestPairCode still checks the
  code and fingerprint. Random, hex, and base64url are fphashutils. HMAC is
  fpsha256.TSHA256.HMAC. JSON stays in the codec. The pair code, session token,
  and HMAC are never logged.

  Heartbeat: a ping goes out after MonitorHeartbeatMs with nothing sent, and the link
  is dead after MonitorDeadSessionMs with nothing received. A ping is answered with a
  pong on the control lane from the carrier thread. The phone's MonitorLimits holds the
  same two values.

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
  SysUtils, AssistantMonitorFrames, AssistantMonitorCarrier, AssistantMonitorCodec;

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
  { Committed patches a resume can replay. Fewer when the JSON would pass 2 MiB. }
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
    FUnsentTranscripts: Array Of String;
    FUnsentTranscriptTurn: Integer;
    FUnsentTranscriptAt: QWord;
    FHasUnsentTranscript: Boolean;
    FTranscriptRevision: Integer;
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
    FRingCursor: Array Of Int64;
    FRingJson: Array Of RawByteString;
    FRingBytes: Int64;
    { Highest cursor removed from the ring. A later resume must not treat that gap as complete. }
    FRingDroppedCursor: Int64;
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
    Procedure HandleApproval(Const PayloadJson: String);
    Procedure ClearRingLocked;
    Procedure NoteRingDropLocked(Cursor: Int64);
    Procedure DropOldestRingLocked;
    Procedure AppendRingLocked(Cursor: Int64; Const PatchJson: RawByteString);
    Function RingIndexLocked(Cursor: Int64): Integer;
    Function ApprovalRejectReason(Const ToolId: String): String;
    Function CommandBlocked(Kind: Integer; Out MessageText: String): Boolean;
    Procedure EnterBusy(Kind: Integer; Const Id, PayloadJson: String);
    Procedure AdoptRunningHost;
    Procedure FlushTranscriptLocked;
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
    Procedure SetHostFlags(Const Flags: TMonitorHostFlags);
    Procedure SetRemoteApproval(Enabled: Boolean);
    Procedure RevokeClient(Const ClientId: String);
    Procedure RevokeAll;
    Procedure NoteTurnEnded;
    { New epoch. Cursor returns to zero. Safe from the IDE thread. }
    Procedure BeginMirrorEpoch(Const Epoch, ConversationId, ProjectRoot, Title: String);
    Function MirrorEpoch: String;
    Function MirrorCursor: Int64;
    { Same cursor while the bytes are unsent or already handed unchanged. }
    Function CommitMirrorCursor(Const Payload: RawByteString; Out Cursor: Int64): Boolean;
    Procedure NoteMirrorHanded(Cursor: Int64);
    /// Stores a handed patch. A record that does not fit is dropped and stated.
    Procedure RememberHandedPatch(Cursor: Int64; Const PatchJson: RawByteString);
    /// True when every cursor after the client is still a patch in the ring. Does not read a form.
    Function TryResumeEvents(Const Epoch: String; Cursor: Int64; Out Catchup: TMonitorCatchup): Boolean;
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
    Function NextTranscriptRevision(TurnIndex: Integer): Integer;
    Procedure QueueTranscript(TurnIndex: Integer; Const FrameJson: String);
    { Replaces any unsent frames for this turn. Parts of one revision stay together. }
    Procedure QueueTranscriptParts(TurnIndex: Integer; Const Frames: TStringArray);
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
  SyncObjs, fpjson, jsonparser, fpsha256, fphashutils, WorkflowLog, AssistantMonitorSettings,
  AssistantSessionObserve;

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
  SetLength(FUnsentTranscripts, 0);
  FUnsentTranscriptTurn := 0;
  FUnsentTranscriptAt := 0;
  FHasUnsentTranscript := False;
  FTranscriptRevision := 0;
  FEpoch := '';
  FConversationId := 'current';
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
  SetLength(FRingCursor, 0);
  SetLength(FRingJson, 0);
  FRingBytes := 0;
  FRingDroppedCursor := 0;
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
  TOutboundLane = (olControl, olLive, olBulk);

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
    mmkSnapshot, mmkTranscript, mmkPlan, mmkCatchup, mmkImageData:
      Result := olBulk;
  Else
    Result := olControl;
  End;
End;

Function TMonitorSession.QueueSend(Const Json: String): Boolean;
Var
  Index: Integer;
  Lane: TOutboundLane;
Begin
  Result := False;
  If Json = '' Then
    Exit;
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
  Cursor: Int64;
  HadLive: Boolean;
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
  FHasUnsentTranscript := False;
  SetLength(FUnsentTranscripts, 0);
  FHasLivePatch := False;
  FLiveCursor := 0;
  SetLength(FLiveFrames, 0);
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
      FConversationId := 'current';
      FCommittedCursor := 0;
    End;
  HelloOk.Nonce := FNonceHex;
  HelloOk.ServerName := MonitorServerName;
  HelloOk.Epoch := FEpoch;
  HelloOk.Cursor := FCommittedCursor;
  HelloOk.ConversationId := FConversationId;
  HelloOk.ProjectRoot := FProjectRoot;
  HelloOk.Title := FTitle;
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

Procedure TMonitorSession.HandleCommand(Kind: Integer; Const Id, PayloadJson: String);
Var
  Blocked: Boolean;
  MessageText: String;
Begin
  If (FState <> mssLive) And (FState <> mssBusy) Then
    Begin
      RejectLocked('auth', True);
      Exit;
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
  { Not a user command. Stay queued for the IDE thread. Do not answer host_busy. }
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

Procedure TMonitorSession.FlushTranscriptLocked;
Var
  I: Integer;
Begin
  If Not FHasUnsentTranscript Then
    Exit;
  If ClockMs < FUnsentTranscriptAt + MonitorCoalesceWindowMs Then
    Exit;
  { Bulk may wait. The live lane does not share this cap. }
  If Length(FBulkSends) + Length(FUnsentTranscripts) > MonitorOutboundQueueLimit Then
    Exit;
  FHasUnsentTranscript := False;
  For I := 0 To High(FUnsentTranscripts) Do
    QueueSend(FUnsentTranscripts[I]);
  SetLength(FUnsentTranscripts, 0);
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
    FlushTranscriptLocked;
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
    If ConversationId = '' Then
      FConversationId := 'current'
    Else
      FConversationId := ConversationId;
    FProjectRoot := ProjectRoot;
    FTitle := Title;
    FCommittedCursor := 0;
    FNextCursor := 0;
    FReservedCursor := 0;
    FReservedPayload := '';
    FReservedHanded := False;
    ClearRingLocked;
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

Procedure TMonitorSession.ClearRingLocked;
Begin
  SetLength(FRingCursor, 0);
  SetLength(FRingJson, 0);
  FRingBytes := 0;
  FRingDroppedCursor := 0;
End;

Procedure TMonitorSession.NoteRingDropLocked(Cursor: Int64);
Begin
  If Cursor > FRingDroppedCursor Then
    FRingDroppedCursor := Cursor;
End;

Procedure TMonitorSession.DropOldestRingLocked;
Var
  Index, Size: Integer;
  Dropped: Int64;
Begin
  If Length(FRingCursor) = 0 Then
    Exit;
  Dropped := FRingCursor[0];
  Size := Length(FRingJson[0]);
  NoteRingDropLocked(Dropped);
  FRingBytes := FRingBytes - Size;
  If FRingBytes < 0 Then
    FRingBytes := 0;
  For Index := 0 To High(FRingCursor) - 1 Do
    Begin
      FRingCursor[Index] := FRingCursor[Index + 1];
      FRingJson[Index] := FRingJson[Index + 1];
    End;
  SetLength(FRingCursor, Length(FRingCursor) - 1);
  SetLength(FRingJson, Length(FRingJson) - 1);
  LogLine(1, 'ring drop cursor=' + IntToStr(Dropped) + ' bytes=' + IntToStr(Size));
End;

Procedure TMonitorSession.AppendRingLocked(Cursor: Int64; Const PatchJson: RawByteString);
Var
  Size, Index: Integer;
Begin
  Size := Length(PatchJson);
  If Size > MonitorRingJsonCap Then
    Begin
      NoteRingDropLocked(Cursor);
      LogLine(1, 'ring drop cursor=' + IntToStr(Cursor) + ' bytes=' + IntToStr(Size));
      Exit;
    End;
  While (Length(FRingCursor) > 0) And ((Length(FRingCursor) >= MonitorRingCapacity) Or
    (FRingBytes + Size > MonitorRingJsonCap)) Do
    DropOldestRingLocked;
  Index := Length(FRingCursor);
  SetLength(FRingCursor, Index + 1);
  SetLength(FRingJson, Index + 1);
  FRingCursor[Index] := Cursor;
  FRingJson[Index] := PatchJson;
  FRingBytes := FRingBytes + Size;
End;

Function TMonitorSession.RingIndexLocked(Cursor: Int64): Integer;
Var
  Index: Integer;
Begin
  Result := -1;
  For Index := 0 To High(FRingCursor) Do
    If FRingCursor[Index] = Cursor Then
      Exit(Index);
End;

Procedure TMonitorSession.RememberHandedPatch(Cursor: Int64; Const PatchJson: RawByteString);
Begin
  LockSession;
  Try
    If (Cursor <= 0) Or (PatchJson = '') Or (Cursor > FCommittedCursor) Or (Cursor <= FRingDroppedCursor) Then
      Exit;
    If RingIndexLocked(Cursor) >= 0 Then
      Exit;
    If (Length(FRingCursor) > 0) And (Cursor < FRingCursor[High(FRingCursor)]) Then
      Exit;
    AppendRingLocked(Cursor, PatchJson);
  Finally
    UnlockSession;
  End;
End;

Function TMonitorSession.TryResumeEvents(Const Epoch: String; Cursor: Int64; Out Catchup: TMonitorCatchup): Boolean;
Var
  Need: Int64;
  Index, Count: Integer;
  Patch: TMonitorPatch;
Begin
  Result := False;
  Catchup := Default(TMonitorCatchup);
  SetLength(Catchup.Patches, 0);
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
    { A client with nothing committed sends an empty epoch. That is not this generation. }
    If LowerCase(Epoch) <> FEpoch Then
      Exit;
    If (Cursor < 0) Or (Cursor > FCommittedCursor) Or (Cursor < FRingDroppedCursor) Then
      Exit;
    If Cursor = FCommittedCursor Then
      Begin
        Result := True;
        Exit;
      End;
    Need := Cursor + 1;
    Count := 0;
    While Need <= FCommittedCursor Do
      Begin
        Index := RingIndexLocked(Need);
        If Index < 0 Then
          Exit;
        If Not DecodeMonitorPatch(String(FRingJson[Index]), Patch) Then
          Exit;
        SetLength(Catchup.Patches, Count + 1);
        Catchup.Patches[Count] := Patch;
        Inc(Count);
        If Need = FCommittedCursor Then
          Break;
        Inc(Need);
      End;
    Result := True;
  Finally
    UnlockSession;
  End;
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

Function TMonitorSession.NextTranscriptRevision(TurnIndex: Integer): Integer;
Begin
  LockSession;
  Try
    If (FHasUnsentTranscript) And (FUnsentTranscriptTurn = TurnIndex) Then
      Inc(FTranscriptRevision)
    Else If FTranscriptRevision < 1 Then
      FTranscriptRevision := 1
    Else
      Inc(FTranscriptRevision);
    Result := FTranscriptRevision;
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.QueueTranscript(TurnIndex: Integer; Const FrameJson: String);
Begin
  LockSession;
  Try
    If FHasUnsentTranscript And (FUnsentTranscriptTurn = TurnIndex) Then
      Inc(FFramesDropped);
    SetLength(FUnsentTranscripts, 1);
    FUnsentTranscripts[0] := FrameJson;
    FUnsentTranscriptTurn := TurnIndex;
    FUnsentTranscriptAt := ClockMs;
    FHasUnsentTranscript := True;
  Finally
    UnlockSession;
  End;
End;

Procedure TMonitorSession.QueueTranscriptParts(TurnIndex: Integer; Const Frames: TStringArray);
Var
  I: Integer;
Begin
  If Length(Frames) = 0 Then
    Exit;
  LockSession;
  Try
    If FHasUnsentTranscript And (FUnsentTranscriptTurn = TurnIndex) Then
      Inc(FFramesDropped, Length(FUnsentTranscripts));
    SetLength(FUnsentTranscripts, Length(Frames));
    For I := 0 To High(Frames) Do
      FUnsentTranscripts[I] := Frames[I];
    FUnsentTranscriptTurn := TurnIndex;
    FUnsentTranscriptAt := ClockMs;
    FHasUnsentTranscript := True;
  Finally
    UnlockSession;
  End;
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
