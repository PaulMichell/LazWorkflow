Unit AssistantMonitorSession;

{ Monitor session state machine. The LAN carrier owns the socket.
  This unit does not use TInetServer. An in-memory carrier delivers frames
  through SetFrameHandler. No relay class is compiled. (c) 2026 Michell Computing.

  Random, hex, and base64url are fphashutils. HMAC is fpsha256.TSHA256.HMAC.
  JSON stays in the codec. The pair code, session token, and HMAC are never logged.

  Size note: exceeds the 1000 line preference. Pairing, reconnect auth, command
  gates, approval, and the in-memory carrier are one state machine.
  Reviewed 2026-10-19: no socket or form code in this unit. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, AssistantMonitorFrames, AssistantMonitorCarrier;

Const
  MonitorPairCodeLength = 10;
  MonitorPairCodeTtlMs = 120000;
  MonitorPairFailureLimit = 3;
  MonitorNonceTtlMs = 30000;
  MonitorNonceBytes = 16;
  MonitorClientIdBytes = 16;
  MonitorSessionTokenBytes = 32;
  MonitorHeartbeatMs = 15000;
  MonitorDeadSessionMs = 45000;
  MonitorPartialFrameMs = 10000;
  MonitorCoalesceWindowMs = 100;
  MonitorOutboundQueueLimit = 32;
  MonitorCrockfordAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  MonitorServerName = 'LazAssistantMonitor';
  MonitorLogArea = 'AssistantMonitor';

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

  TMonitorCommandHandler = Procedure(Kind: Integer; Const Id, PayloadJson: String) Of Object;
  { The bridge writes approval_closed. Nil leaves a rejected decision silent. }
  TMonitorApprovalCloseHandler = Procedure(Const ToolId, Reason: String) Of Object;

  TMonitorSession = Class
  Private
    FLock: TRTLCriticalSection;
    FState: TMonitorSessionState;
    FCarrier: IMonitorCarrier;
    FOnCommand: TMonitorCommandHandler;
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
    FPingSent: Boolean;
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
    FPendingSends: Array Of String;
    FUnsentTranscript: String;
    FUnsentTranscriptTurn: Integer;
    FUnsentTranscriptAt: QWord;
    FHasUnsentTranscript: Boolean;
    FTranscriptRevision: Integer;
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
    Procedure QueueSend(Const Json: String);
    Procedure DrainSends;
    Procedure Transmit(Const Json: String);
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
    Procedure HandleApproval(Const PayloadJson: String);
    Function ApprovalRejectReason(Const ToolId: String): String;
    Function CommandBlocked(Kind: Integer; Out MessageText: String): Boolean;
    Procedure EnterBusy(Kind: Integer; Const Id, PayloadJson: String);
    Procedure FlushTranscriptLocked;
    Procedure CheckTimeoutsLocked;
    Procedure InboundFrame(Const Frame: TMonitorFrame);
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
    /// Next host frame id. Safe to call off the session lock.
    Function AllocateHostId: String;
    /// Queues one host frame and drains it. Does not build the JSON.
    Procedure SendHostJson(Const Json: String);
    Procedure SetApprovalCloseHandler(Handler: TMonitorApprovalCloseHandler);
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
    Property State: TMonitorSessionState Read FState;
    Property Carrier: IMonitorCarrier Read FCarrier;
    Property OnCommand: TMonitorCommandHandler Read FOnCommand Write FOnCommand;
    Property CloseRequested: Boolean Read FCloseRequested;
    Property FramesSent: Integer Read FFramesSent;
    Property FramesDropped: Integer Read FFramesDropped;
    Property LastError: String Read FLastError;
    Property BoundAddress: String Read FBindAddress;
    Property BoundPort: Integer Read FPort;
    Property ConnectedClientName: String Read FClientName;
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

Implementation

Uses
  SyncObjs, fpjson, jsonparser, fpsha256, fphashutils, WorkflowLog, AssistantMonitorCodec,
  AssistantMonitorSettings, AssistantSessionObserve;

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
  FPingSent := False;
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
  SetLength(FPendingSends, 0);
  FUnsentTranscript := '';
  FUnsentTranscriptTurn := 0;
  FUnsentTranscriptAt := 0;
  FHasUnsentTranscript := False;
  FTranscriptRevision := 0;
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

Procedure TMonitorSession.QueueSend(Const Json: String);
Begin
  If Json = '' Then
    Exit;
  SetLength(FPendingSends, Length(FPendingSends) + 1);
  FPendingSends[High(FPendingSends)] := Json;
End;

Procedure TMonitorSession.Transmit(Const Json: String);
Var
  Frame: TMonitorFrame;
  ErrorText: String;
Begin
  If (Json = '') Or (Not Assigned(FCarrier)) Then
    Exit;
  Frame.Version := MonitorFrameVersion;
  Frame.Flags := 0;
  Frame.Json := Json;
  If FCarrier.Send(Frame, ErrorText) Then
    Inc(FFramesSent)
  Else
    FLastError := ErrorText;
End;

Procedure TMonitorSession.DrainSends;
Var
  Pending: Array Of String;
  I: Integer;
Begin
  LockSession;
  Try
    Pending := FPendingSends;
    SetLength(FPendingSends, 0);
  Finally
    UnlockSession;
  End;
  For I := 0 To High(Pending) Do
    Transmit(Pending[I]);
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
  FPingSent := False;
  FHasUnsentTranscript := False;
  FUnsentTranscript := '';
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
  QueueSend(EncodeMonitorHelloOk(NewHostId, FNonceHex, MonitorServerName));
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
        End
      Else
        RejectLocked('pair_code', True);
      Exit;
    End;
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
  FState := mssLive;
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
  FPingSent := False;
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
    mmkSend, mmkSteer, mmkStop, mmkSetMode, mmkNewConversation, mmkRunPlan, mmkStopPlan, mmkWorkOnPlan, mmkRunTask,
    mmkRemovePlan, mmkInsertTask, mmkSelectPlan, mmkNewPlan, mmkRefresh, mmkTurn, mmkImageGet:
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
Begin
  If Not FHasUnsentTranscript Then
    Exit;
  If ClockMs < FUnsentTranscriptAt + MonitorCoalesceWindowMs Then
    Exit;
  FHasUnsentTranscript := False;
  QueueSend(FUnsentTranscript);
  FUnsentTranscript := '';
End;

Procedure TMonitorSession.CheckTimeoutsLocked;
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
  If (Not FPingSent) And (ClockMs >= FLastFrameMs + MonitorHeartbeatMs) Then
    Begin
      FPingSent := True;
      QueueSend(EncodeMonitorTicks(mmkPing, NewHostId, Int64(ClockMs)));
    End;
  If ClockMs >= FLastFrameMs + MonitorDeadSessionMs Then
    Begin
      LogLine(2, 'heartbeat timeout bind=' + FBindAddress + ' port=' + IntToStr(FPort));
      CloseToListening;
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

Procedure TMonitorSession.NoteTime(NowMs: QWord);
Begin
  LockSession;
  Try
    FNowMs := NowMs;
    CheckTimeoutsLocked;
    FlushTranscriptLocked;
  Finally
    UnlockSession;
  End;
  DrainSends;
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
    If (FState = mssLive) And (Flags.Sending Or Flags.PlanAgentRunning) Then
      FState := mssBusy
    Else If (FState = mssBusy) And (Not Flags.Sending) And (Not Flags.PlanAgentRunning) Then
      FState := mssLive;
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
    If (Not FHasUnsentTranscript) And (Length(FPendingSends) >= MonitorOutboundQueueLimit) Then
      Begin
        Inc(FFramesDropped);
        Exit;
      End;
    FUnsentTranscript := FrameJson;
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

Procedure TMonitorSession.SendHostJson(Const Json: String);
Begin
  If Json = '' Then
    Exit;
  LockSession;
  Try
    QueueSend(Json);
  Finally
    UnlockSession;
  End;
  DrainSends;
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
