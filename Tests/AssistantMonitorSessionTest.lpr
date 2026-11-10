Program AssistantMonitorSessionTest;

{ In-memory monitor session checks. No sockets and no Interfaces unit (c) 2026 Michell Computing.

  The runner writes this binary with a temporary -FU and -FE, never under Source/.
  Monitor load and save use a temp settings directory and leave other sections in place. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  AssistantMonitorState, AssistantMonitorCommands, Classes, SysUtils, DateUtils, SyncObjs, fpjson, AssistantMonitorLinkStubs,
  AssistantMonitorCodec, AssistantMonitorFrames, AssistantMonitorCarrier, AssistantMonitorMirror, AssistantMonitorOutbox,
  AssistantMonitorSession, AssistantMonitorApproval,
  AssistantMonitorSettings, AssistantSessionObserve, WorkflowSettings;

Var
  FailCount: Integer;
  Carrier: TMonitorMemoryCarrier;
  CarrierRef: IMonitorCarrier;
  Session: TMonitorSession;
  SettingsRoot: String;
  SavedClientId: String;
  SavedToken: String;
  DiscardedCode: String;
  ErrorText: String;

Type
  TCommandSink = Class
    Kind: Integer;
    Calls: Integer;
    Procedure Hear(CommandKind: Integer; Const CommandId: String; Const CommandPayload: TMonitorPayload);
  End;

{$PUSH}{$HINTS OFF}
Procedure TCommandSink.Hear(CommandKind: Integer; Const CommandId: String; Const CommandPayload: TMonitorPayload);
Begin
  Inc(Calls);
  Kind := CommandKind;
End;
{$POP}

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

Function SectionField(Const SectionName, FieldName: String): String;
Var
  Section: TJSONObject;
Begin
  Result := '';
  Section := ReadWorkflowSection(SectionName);
  If Not Assigned(Section) Then
    Exit;
  Try
    Result := Section.Get(FieldName, '');
  Finally
    Section.Free;
  End;
End;

Procedure SeedOtherSections;
Var
  Section: TJSONObject;
  ErrorText: String;
Begin
  Section := TJSONObject.Create;
  Try
    Section.Add('marker', 'keep-assistant');
    Check('seed assistant section', WriteWorkflowSection('assistant', Section, ErrorText));
  Finally
    Section.Free;
  End;
  Section := TJSONObject.Create;
  Try
    Section.Add('marker', 'keep-notes');
    Check('seed notes section', WriteWorkflowSection('notes', Section, ErrorText));
  Finally
    Section.Free;
  End;
End;

Procedure CheckOtherSections(Const Title: String);
Begin
  Check(Title + ' assistant marker', SectionField('assistant', 'marker') = 'keep-assistant');
  Check(Title + ' notes marker', SectionField('notes', 'marker') = 'keep-notes');
End;

Procedure TestSettingsLoadSave;
Var
  Settings: TMonitorSettings;
  ErrorText: String;
Begin
  Check('missing monitor section loads', LoadMonitorSettings(Settings, ErrorText));
  Check('missing monitor section is default', (Not Settings.Enabled) And (Settings.Port = MonitorListenPort) And
    (Length(Settings.Clients) = 0) And (ErrorText = ''));
  Check('missing monitor section requires a pair code', Settings.RequirePairCode);
  Settings := DefaultMonitorSettings;
  Settings.RequirePairCode := False;
  Check('save pair code off', SaveMonitorSettings(Settings, ErrorText));
  Check('load pair code off', LoadMonitorSettings(Settings, ErrorText) And (Not Settings.RequirePairCode));
  Settings := DefaultMonitorSettings;
  Settings.Enabled := False;
  Settings.Port := 56123;
  Settings.BindAddress := '10.1.2.3';
  Settings.BindAll := False;
  Settings.RemoteApproval := False;
  Check('save monitor section', SaveMonitorSettings(Settings, ErrorText));
  Check('load monitor section', LoadMonitorSettings(Settings, ErrorText));
  Check('loaded port', Settings.Port = 56123);
  Check('loaded bind', Settings.BindAddress = '10.1.2.3');
  Check('loaded pair code required', Settings.RequirePairCode);
  Check('loaded clients empty', Length(Settings.Clients) = 0);
  CheckOtherSections('after monitor save');
End;

Procedure TestOfflineRevoke;
Var
  Settings: TMonitorSettings;
  ErrorText: String;
Begin
  Check('offline revoke loads settings', LoadMonitorSettings(Settings, ErrorText));
  SetLength(Settings.Clients, 2);
  Settings.Clients[0].Id := 'offline-remove';
  Settings.Clients[0].Token := 'remove-token';
  Settings.Clients[1].Id := 'offline-keep';
  Settings.Clients[1].Name := 'Kept client';
  Settings.Clients[1].Token := 'keep-token';
  Settings.Clients[1].Fingerprint := 'keep-fingerprint';
  Settings.Clients[1].PairedAt := 'keep-date';
  Check('offline revoke seeds clients', SaveMonitorSettings(Settings, ErrorText));
  Check('offline revoke succeeds', RevokeMonitorClient('offline-remove', ErrorText));
  Check('offline revoke reloads', LoadMonitorSettings(Settings, ErrorText));
  Check('offline revoke keeps other client', (Length(Settings.Clients) = 1) And
    (Settings.Clients[0].Id = 'offline-keep') And (Settings.Clients[0].Name = 'Kept client') And
    (Settings.Clients[0].Token = 'keep-token') And (Settings.Clients[0].Fingerprint = 'keep-fingerprint') And
    (Settings.Clients[0].PairedAt = 'keep-date'));
  Check('offline revoke keeps configuration', (Settings.Port = 56123) And (Settings.BindAddress = '10.1.2.3') And
    (Not Settings.RemoteApproval));
  Check('offline revoke missing id succeeds', RevokeMonitorClient('missing-client', ErrorText));
  Check('offline revoke cleans up', RevokeMonitorClient('offline-keep', ErrorText));
  CheckOtherSections('after offline revoke');
End;

Procedure TestSharedApprovalFlag;
Var
  OtherSession: TMonitorSession;
Begin
  ApplyMonitorRemoteApproval(True);
  OtherSession := TMonitorSession.Create;
  Try
    Check('new session reads shared approval flag', OtherSession.RemoteApproval And Session.RemoteApproval);
    OtherSession.SetRemoteApproval(False);
    Check('session setter updates shared approval flag', (Not MonitorRemoteApprovalEnabled) And (Not Session.RemoteApproval));
    ApplyMonitorRemoteApproval(True);
    Check('global update reaches existing session', Session.RemoteApproval);
  Finally
    OtherSession.Free;
    ApplyMonitorRemoteApproval(False);
  End;
End;

Function LastJson: String;
Begin
  Result := '';
  If Not Assigned(Carrier) Or (Carrier.SentCount = 0) Then
    Exit;
  Result := Carrier.SentJson(Carrier.SentCount - 1);
End;

Function DecodeLast(Out Message: TMonitorMessage): Boolean;
Var
  ErrorText: String;
Begin
  Result := TryDecodeMonitorEnvelope(LastJson, Message, ErrorText);
End;

Function PayloadField(Const PayloadJson, Name: String): String;
Var
  Data: TJSONData;
Begin
  Result := '';
  Data := GetJSON(PayloadJson);
  Try
    If Data Is TJSONObject Then
      Result := TJSONObject(Data).Get(Name, '');
  Finally
    Data.Free;
  End;
End;

Function QueuedOnce(Const Ref: String): Boolean;
Var
  Index, Count: Integer;
  Message: TMonitorMessage;
  ErrorText: String;
Begin
  Count := 0;
  For Index := 0 To Carrier.SentCount - 1 Do
    Begin
      If Not TryDecodeMonitorEnvelope(Carrier.SentJson(Index), Message, ErrorText) Then
        Continue;
      If Message.Kind = mmkError Then
        Exit(False);
      If (Message.Kind = mmkCommandState) And (PayloadField(Message.PayloadJson, 'state') = 'queued') And
        (PayloadField(Message.PayloadJson, 'ref') = Ref) Then
        Inc(Count);
    End;
  Result := Count = 1;
End;

Procedure ExpectRejected(Const Title, Reason: String; ShouldClose: Boolean);
Var
  Message: TMonitorMessage;
  Rejected: TMonitorRejected;
Begin
  Check(Title + ' frame', DecodeLast(Message));
  Check(Title + ' type', Message.Kind = mmkRejected);
  Check(Title + ' payload', DecodeCommandRejected(Message.PayloadJson, Rejected));
  If Rejected.Reason <> Reason Then
    WriteLn('detail ', Title, ' reason=', Rejected.Reason);
  Check(Title + ' reason ' + Reason, Rejected.Reason = Reason);
  Check(Title + ' host version', Rejected.HostVersion = MonitorCatalogueVersion);
  If ShouldClose Then
    Begin
      Check(Title + ' closes', Session.CloseRequested);
      Check(Title + ' listening', Session.State = mssListening);
    End
  Else
    Begin
      Check(Title + ' stays open', Not Session.CloseRequested);
      Check(Title + ' stays accepted', Session.State = mssAccepted);
    End;
End;

Procedure NewSocket;
Var
  Spare: TMonitorFrame;
Begin
  Session.NoteSocketClosed;
  Check('socket accepted', Session.AcceptHandshake(Spare) And (Session.State = mssAccepted));
  Carrier.ClearSent;
End;

Procedure ExpectBusySpare(Const Title: String);
Var
  Spare: TMonitorFrame;
  Message: TMonitorMessage;
  Rejected: TMonitorRejected;
  ErrorText: String;
  Before: TMonitorSessionState;
Begin
  Before := Session.State;
  Check(Title + ' spare rejected', Not Session.AcceptHandshake(Spare));
  Check(Title + ' controller unchanged', Session.State = Before);
  Check(Title + ' spare envelope', TryDecodeMonitorEnvelope(Spare.Json, Message, ErrorText) And (Message.Kind = mmkRejected));
  Check(Title + ' spare payload', DecodeCommandRejected(Message.PayloadJson, Rejected));
  Check(Title + ' spare busy', Rejected.Reason = 'busy');
End;

Procedure DeliverHello(Const ClientId: String);
Begin
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeCommandHello('hello', 'Phone', '1', ClientId));
End;

Procedure DeliverPair(Const Code: String);
Begin
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeCommandPair('pair', Code, 'ab12cd34'));
End;

Function WrongCode(Const Code: String): String;
Begin
  Result := '0000000000';
  If Result = Code Then
    Result := '1111111111';
End;

Function IsPairCode(Const Code: String): Boolean;
Var
  I: Integer;
Begin
  Result := Length(Code) = MonitorPairCodeLength;
  If Not Result Then
    Exit;
  For I := 1 To Length(Code) Do
    If Pos(Code[I], MonitorCrockfordAlphabet) = 0 Then
      Exit(False);
End;

Procedure ExpectPairOk;
Var
  Message: TMonitorMessage;
  PairOk: TMonitorPairOk;
Begin
  Check('pair reaches live', Session.State = mssLive);
  Check('pair code spent', Session.PairCode = '');
  Check('pair does not close', Not Session.CloseRequested);
  Check('pair_ok frame', DecodeLast(Message) And (Message.Kind = mmkPairOk));
  Check('pair_ok payload', DecodeCommandPairOk(Message.PayloadJson, PairOk));
  SavedClientId := PairOk.ClientId;
  SavedToken := PairOk.SessionToken;
  Check('client id present', SavedClientId <> '');
  Check('session token present', SavedToken <> '');
End;

Function NonceFromLast: String;
Var
  Message: TMonitorMessage;
  HelloOk: TMonitorHelloOk;
Begin
  Result := '';
  If Not DecodeLast(Message) Then
    Exit;
  If Message.Kind <> mmkHelloOk Then
    Exit;
  If Not DecodeCommandHelloOk(Message.PayloadJson, HelloOk) Then
    Exit;
  Result := HelloOk.Nonce;
End;

Procedure TestLoopbackPairingPolicy;
Var
  Settings: TMonitorSettings;
  ErrorText: String;
  Spare: TMonitorFrame;
Begin
  NewSocket;
  DeliverHello('');
  DeliverPair('');
  ExpectRejected('LAN without code', 'pair_code', True);
  Check('LAN rejection stores no client', LoadMonitorSettings(Settings, ErrorText) And (Length(Settings.Clients) = 0));
  Session.NoteSocketClosed;
  Check('loopback accepted', Session.AcceptHandshake(Spare, True));
  DeliverHello('');
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeCommandPair('pair', '', ''));
  ExpectPairOk;
  Check('open pair stores client', LoadMonitorSettings(Settings, ErrorText) And (Length(Settings.Clients) = 1));
  Session.RevokeClient(SavedClientId);
  Session.NoteSocketClosed;
  Check('open pair revoked', LoadMonitorSettings(Settings, ErrorText) And (Length(Settings.Clients) = 0));
  Check('open pair returns to listening', Session.State = mssListening);
End;

Procedure TestPairCodeOptional;
Var
  Code: String;
Begin
  Check('session requires a pair code by default', Session.PairCodeRequired);
  Session.PairCodeRequired := False;
  Try
    NewSocket;
    DeliverHello('');
    Carrier.ClearSent;
    Carrier.DeliverJson(EncodeCommandPair('pair', '', ''));
    ExpectRejected('codeless pair without a fingerprint', 'fingerprint', True);
    NewSocket;
    DeliverHello('');
    DeliverPair('');
    ExpectPairOk;
    Session.RevokeClient(SavedClientId);
    Session.NoteSocketClosed;
    Check('codeless LAN pair returns to listening', Session.State = mssListening);
    NewSocket;
    DeliverHello('');
    Carrier.ClearSent;
    Carrier.DeliverJson(EncodeCommandPair('pair', '', 'ffff0000'));
    ExpectRejected('codeless pair with another fingerprint', 'fingerprint', True);
    Session.RequestPairCode;
    Code := Session.PairCode;
    NewSocket;
    DeliverHello('');
    DeliverPair(WrongCode(Code));
    ExpectRejected('typed wrong code still checked', 'pair_code', False);
    DeliverPair('');
    ExpectPairOk;
    Session.RevokeClient(SavedClientId);
    Session.NoteSocketClosed;
  Finally
    Session.PairCodeRequired := True;
  End;
  NewSocket;
  DeliverHello('');
  DeliverPair('');
  ExpectRejected('LAN without code once required again', 'pair_code', True);
  Session.NoteSocketClosed;
End;

Procedure TestCodeAbsentUntilRequested;
Begin
  Check('code absent at start', Session.PairCode = '');
  Check('listening does not mint a code', Session.State = mssListening);
  Session.RequestPairCode;
  Check('requested code present', IsPairCode(Session.PairCode));
End;

Procedure TestSecondControllerWhileAccepted;
Begin
  NewSocket;
  ExpectBusySpare('accepted');
End;

Procedure TestCommandBeforeAuth;
Begin
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeCommandEmpty(mmkSend, 'send-early'));
  ExpectRejected('command before auth', 'auth', True);
  Check('command before auth is not live', Session.State <> mssLive);
End;

Procedure TestThreeFailuresDiscard;
Var
  Code: String;
  I: Integer;
Begin
  NewSocket;
  Session.RequestPairCode;
  Code := Session.PairCode;
  Check('failure setup has a code', IsPairCode(Code));
  DeliverHello('');
  Check('first hello sends nothing', Carrier.SentCount = 0);
  Check('first hello stays accepted', Session.State = mssAccepted);
  For I := 1 To MonitorPairFailureLimit Do
    Begin
      DeliverPair(WrongCode(Code));
      ExpectRejected('bad pair ' + IntToStr(I), 'pair_code', I = MonitorPairFailureLimit);
      If I < MonitorPairFailureLimit Then
        Check('code kept after failure ' + IntToStr(I), Session.PairCode = Code)
      Else
        Check('code discarded after three failures', Session.PairCode = '');
    End;
  DiscardedCode := Code;
End;

Procedure TestPairAfterDiscard;
Begin
  NewSocket;
  DeliverHello('');
  DeliverPair(DiscardedCode);
  ExpectRejected('pair after discard', 'pair_code', True);
  Check('discarded code stays discarded', Session.PairCode = '');
  Check('discarded pair is not live', Session.State <> mssLive);
End;

{ PairedAt is UTC with a Z suffix. True when it is within a minute of the UTC clock. }
Function PairedAtNearUtc(Const Text: String): Boolean;
Var
  Year, Month, Day, Hour, Minute, Second: Integer;
  Stamp: TDateTime;
Begin
  Result := False;
  If (Length(Text) <> 20) Or (Text[11] <> 'T') Or (Text[20] <> 'Z') Then
    Exit;
  If Not TryStrToInt(Copy(Text, 1, 4), Year) Or Not TryStrToInt(Copy(Text, 6, 2), Month) Or
    Not TryStrToInt(Copy(Text, 9, 2), Day) Or Not TryStrToInt(Copy(Text, 12, 2), Hour) Or
    Not TryStrToInt(Copy(Text, 15, 2), Minute) Or Not TryStrToInt(Copy(Text, 18, 2), Second) Then
    Exit;
  If Not TryEncodeDateTime(Year, Month, Day, Hour, Minute, Second, 0, Stamp) Then
    Exit;
  Result := Abs(Stamp - LocalTimeToUniversal(Now)) <= EncodeTime(0, 1, 0, 0);
End;

Procedure TestPairSuccess;
Var
  Settings: TMonitorSettings;
  ErrorText: String;
Begin
  Session.RequestPairCode;
  NewSocket;
  DeliverHello('');
  DeliverPair(Session.PairCode);
  ExpectPairOk;
  Check('pair save loads', LoadMonitorSettings(Settings, ErrorText));
  Check('pair save keeps port', Settings.Port = 56123);
  Check('pair save stores one client', Length(Settings.Clients) = 1);
  Check('stored client id', (Length(Settings.Clients) = 1) And (Settings.Clients[0].Id = SavedClientId));
  Check('paired at matches UTC within a minute', (Length(Settings.Clients) = 1) And PairedAtNearUtc(Settings.Clients[0].PairedAt));
  CheckOtherSections('after pair save');
End;

Procedure TestHmac;
Var
  Nonce: String;
Begin
  NewSocket;
  DeliverHello(SavedClientId);
  Nonce := NonceFromLast;
  Check('hello_ok nonce', Length(Nonce) = MonitorNonceBytes * 2);
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeCommandAuth('auth-bad', SavedClientId, 'not-a-mac'));
  ExpectRejected('hmac failure', 'auth', True);
  Check('hmac failure is not live', Session.State <> mssLive);
  NewSocket;
  DeliverHello(SavedClientId);
  Nonce := NonceFromLast;
  Check('second nonce', Length(Nonce) = MonitorNonceBytes * 2);
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeCommandAuth('auth-ok', SavedClientId, MonitorAuthMac(SavedToken, Nonce)));
  Check('hmac success is live', Session.State = mssLive);
  Check('hmac success sends no extra frame', Carrier.SentCount = 0);
  Check('hmac success stays open', Not Session.CloseRequested);
End;

Procedure TestReconnectKeepsRunningTurn;
Var
  Flags: TMonitorHostFlags;
  Nonce: String;
Begin
  Flags := Default(TMonitorHostFlags);
  Flags.Sending := True;
  Flags.CanSteer := True;
  Flags.CanStop := True;
  Session.SetHostFlags(Flags);
  Check('flags make the live socket busy', Session.State = mssBusy);
  NewSocket;
  DeliverHello(SavedClientId);
  Nonce := NonceFromLast;
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeCommandAuth('auth-run', SavedClientId, MonitorAuthMac(SavedToken, Nonce)));
  Check('reconnect during a turn is busy', Session.State = mssBusy);
  Flags := Default(TMonitorHostFlags);
  Flags.CanSend := True;
  Session.SetHostFlags(Flags);
  Check('finished turn returns to live', Session.State = mssLive);
End;

Procedure TestIdleSteerSubmits;
Var
  Sink: TCommandSink;
  Flags: TMonitorHostFlags;
  Json, ErrorJson: String;
  Message: TMonitorMessage;
  ErrorBody: TMonitorErrorBody;
Begin
  Sink := TCommandSink.Create;
  Try
    Session.OnCommand := @Sink.Hear;
    Flags := Default(TMonitorHostFlags);
    Flags.CanSend := True;
    Session.SetHostFlags(Flags);
    Check('idle steer starts live', Session.State = mssLive);
    Carrier.ClearSent;
    Check('idle steer encodes', TryEncodeCommandSteer('steer-idle', 'hello from the phone', Json, ErrorJson));
    Carrier.DeliverJson(Json);
    Check('idle steer is submitted', Sink.Calls = 1);
    Check('idle steer becomes send', Sink.Kind = Ord(mmkSend));
    Check('idle steer stays live until the form is sending', Session.State = mssLive);
    Check('idle steer is answered queued once', QueuedOnce('steer-idle'));
    Flags.Sending := True;
    Flags.CanSteer := True;
    Flags.CanSend := False;
    Session.SetHostFlags(Flags);
    Sink.Calls := 0;
    Check('running steer encodes', TryEncodeCommandSteer('steer-run', 'nudge', Json, ErrorJson));
    Carrier.DeliverJson(Json);
    Check('running steer stays steer', (Sink.Calls = 1) And (Sink.Kind = Ord(mmkSteer)));
    Flags := Default(TMonitorHostFlags);
    Session.SetHostFlags(Flags);
    Check('finished turn is live', Session.State = mssLive);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Check('blocked steer encodes', TryEncodeCommandSteer('steer-block', 'later', Json, ErrorJson));
    Carrier.DeliverJson(Json);
    Check('blocked steer is not queued', Sink.Calls = 0);
    Check('blocked steer error', DecodeLast(Message) And (Message.Kind = mmkError));
    Check('blocked steer text', DecodeMonitorError(Message.PayloadJson, ErrorBody) And
      (ErrorBody.MessageText = 'Nothing is running to steer.'));
  Finally
    Session.OnCommand := Nil;
    Sink.Free;
  End;
End;

Function AckTurn: TAssistantMonitorTurn;
Begin
  Result := Default(TAssistantMonitorTurn);
  Result.TurnIndex := 0;
  Result.Id := 'ack-turn';
  Result.Mode := 'build';
  Result.Prompt := 'prompt';
  Result.CreatedAt := '2026-01-01T00:00:00Z';
  SetLength(Result.Blocks, 1);
  Result.Blocks[0].Kind := 'answer';
  Result.Blocks[0].BlockId := 'ack-block';
  Result.Blocks[0].Body := 'answer';
  Result.Blocks[0].Ok := True;
End;

Procedure TestAckThroughCarrier;
Var
  Sink: TCommandSink;
  Flags: TMonitorHostFlags;
  Json, ErrorJson, Nonce: String;
Begin
  NewSocket;
  DeliverHello(SavedClientId);
  Nonce := NonceFromLast;
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeCommandAuth('auth-ack', SavedClientId, MonitorAuthMac(SavedToken, Nonce)));
  Check('ack setup is live', Session.State = mssLive);
  Session.BeginMirrorEpoch('stream-1', 'conv', '/work', 'Ack');
  Session.ObserveTurn(AckTurn);
  Check('ack starts at zero', Session.LogAcked = 0);
  Carrier.DeliverJson('{"v":3,"id":"ack-1","type":"ack","payload":{"conversation_id":"conv","stream_id":"stream-1","seq":4}}');
  Check('ack through the carrier advances', Session.LogAcked = 4);
  Carrier.DeliverJson('{"v":3,"id":"ack-old","type":"ack","payload":{"conversation_id":"conv","stream_id":"stream-1","seq":2}}');
  Check('an older ack does not move back', Session.LogAcked = 4);
  Sink := TCommandSink.Create;
  Try
    Session.OnCommand := @Sink.Hear;
    Flags := Default(TMonitorHostFlags);
    Flags.CanSend := True;
    Session.SetHostFlags(Flags);
    Check('send after ack encodes', TryEncodeCommandSend('send-after-ack', 'hello', Json, ErrorJson, False));
    Carrier.DeliverJson(Json);
    Check('send after ack is accepted', (Sink.Calls = 1) And (Sink.Kind = Ord(mmkSend)));
    Check('send after ack stays open', (Session.State = mssLive) And (Not Session.CloseRequested));
    Flags.Sending := True;
    Session.SetHostFlags(Flags);
    Flags := Default(TMonitorHostFlags);
    Session.SetHostFlags(Flags);
  Finally
    Session.OnCommand := Nil;
    Sink.Free;
  End;
End;

Procedure TestAckRules;
Var
  Nonce: String;
  Queued, Acked, Index: Integer;
  Message: TMonitorMessage;
  ErrorBody: TMonitorErrorBody;
  ErrorText: String;
  SawError: Boolean;
Begin
  NewSocket;
  DeliverHello(SavedClientId);
  Nonce := NonceFromLast;
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeCommandAuth('auth-ack-rules', SavedClientId, MonitorAuthMac(SavedToken, Nonce)));
  Check('ack rules start live', Session.State = mssLive);
  Session.BeginMirrorEpoch('stream-ack', 'conv-ack', '/work', 'Ack rules');
  Session.ObserveTurn(AckTurn);
  Carrier.ClearSent;
  Carrier.DeliverJson('{"v":3,"id":"resume-ack","type":"resume","payload":{"epoch":"stream-ack","cursor":0,' +
    '"conversation_id":"conv-ack","commands":[]}}');
  Queued := Session.LogLaneCount;
  Acked := Session.LogAcked;
  Check('the open stream has log frames queued', Queued > 0);
  Carrier.ClearSent;
  Carrier.DeliverJson('{"v":3,"id":"ack-stale","type":"ack","payload":{"conversation_id":"old","stream_id":"other-stream","seq":99}}');
  Check('a stale stream is ignored', Session.LogAcked = Acked);
  Check('a stale stream leaves the log queued', Session.LogLaneCount = Queued);
  Check('a stale stream sends no error', Carrier.SentCount = 0);
  Carrier.DeliverJson('{"v":3,"id":"ack-past","type":"ack","payload":{"conversation_id":"conv-ack","stream_id":"stream-ack","seq":99}}');
  Check('a seq past the head does not move credit', Session.LogAcked = Acked);
  Check('a seq past the head leaves the log queued', Session.LogLaneCount = Queued);
  SawError := False;
  For Index := 0 To Carrier.SentCount - 1 Do
    If TryDecodeMonitorEnvelope(Carrier.SentJson(Index), Message, ErrorText) And (Message.Kind = mmkError) And
      DecodeMonitorError(Message.PayloadJson, ErrorBody) And (ErrorBody.Reason = 'protocol') And (ErrorBody.RefId = 'ack-past') Then
      SawError := True;
  Check('a seq past the head is a protocol error', SawError);
  Check('a refused ack stays open', (Session.State = mssLive) And (Not Session.CloseRequested));
End;

Function BulkFrame(Index: Integer): String;
Begin
  Result := '{"v":3,"id":"bulk-' + IntToStr(Index) + '","type":"snapshot_page","payload":{}}';
End;

{ A live part is a real envelope. The id carries the name, so a check can find the part in the sent frames. }


Procedure TestSpacedEventSeq;
Var
  Fresh: TMonitorSession;
  Json: String;
  Bytes: RawByteString;
  Lane: TMonitorOutboxLane;
Begin
  Fresh := TMonitorSession.Create;
  Try
    Json := '{"v":3,"id":"e-spaced","type":"event","payload":{"conversation_id":"c","stream_id":"aa","seq" : 7,' +
      '"event":"block_append","data":{"block_id":"b","offset":0,"text":"x"}}}';
    Check('spaced seq event queues', Fresh.TryQueueHostJson(Json));
    Check('spaced seq event is on the log lane', Fresh.TakeOutboundFrameWithLane(Bytes, Lane) And (Lane = molLog));
    Check('a lower seq is not the stored sequence', Not Fresh.TryQueueHostJson(
      '{"v":3,"id":"e-low","type":"event","payload":{"seq" : 6,"event":"block_append","data":{}}}'));
    Check('the next seq still queues', Fresh.TryQueueHostJson(
      '{"v":3,"id":"e-next","type":"event","payload":{"seq" : 8,"event":"block_append","data":{}}}'));
  Finally
    Fresh.Free;
  End;
End;

Procedure TestObservedResumeCarriesStatus;
Var
  Nonce, Seen: String;
  Flags: TMonitorHostFlags;
  Index: Integer;
Begin
  NewSocket;
  DeliverHello(SavedClientId);
  Nonce := NonceFromLast;
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeCommandAuth('auth-observed', SavedClientId, MonitorAuthMac(SavedToken, Nonce)));
  Check('observed resume starts live', Session.State = mssLive);
  Flags := Default(TMonitorHostFlags);
  Flags.PlanAgentRunning := True;
  Flags.CanChangeMode := True;
  Flags.CanSend := True;
  Flags.CanSteer := True;
  Flags.CanStop := True;
  Session.SetHostFlags(Flags);
  Session.SetRemoteApproval(True);
  Session.NoteApprovalRequested('tool-obs', True);
  Carrier.ClearSent;
  Carrier.DeliverJson('{"v":3,"id":"resume-late","type":"resume","payload":{"epoch":"","cursor":0,' +
    '"conversation_id":"conv-late","commands":[]}}');
  Carrier.ClearSent;
  Session.BeginMirrorEpoch('epoch-late', 'conv-late', '/work', 'Late');
  Session.ObserveTurn(AckTurn);
  Session.DrainOutbound;
  Seen := '';
  For Index := 0 To Carrier.SentCount - 1 Do
    Seen := Seen + Carrier.SentJson(Index) + #10;
  Check('observed baseline is a snapshot', Pos('"snapshot_begin"', Seen) > 0);
  Check('observed baseline reports the plan run', Pos('"plan_running":true', Seen) > 0);
  Check('observed baseline reports mode changes', Pos('"can_change_mode":true', Seen) > 0);
  Check('observed baseline reports the approval', Pos('"tool_id":"tool-obs"', Seen) > 0);
  Session.NoteApprovalClosed('tool-obs');
  Session.SetRemoteApproval(False);
  Flags := Default(TMonitorHostFlags);
  Session.SetHostFlags(Flags);
End;

Procedure TestIdlePollStillFills;
Var
  Nonce: String;
  Flags: TMonitorHostFlags;
  Later: TAssistantMonitorTurn;
Begin
  NewSocket;
  DeliverHello(SavedClientId);
  Nonce := NonceFromLast;
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeCommandAuth('auth-idle-fill', SavedClientId, MonitorAuthMac(SavedToken, Nonce)));
  Check('idle fill starts live', Session.State = mssLive);
  Flags := Default(TMonitorHostFlags);
  Flags.CanSend := True;
  Session.SetHostFlags(Flags);
  Session.BeginMirrorEpoch('epoch-idle', 'conv-idle', '/work', 'Idle');
  Session.ObserveTurn(AckTurn);
  Carrier.ClearSent;
  Carrier.DeliverJson('{"v":3,"id":"resume-idle","type":"resume","payload":{"epoch":"epoch-idle","cursor":0,' +
    '"conversation_id":"conv-idle","commands":[]}}');
  Session.DrainOutbound;
  Session.PrepareOutboundCount;
  Carrier.ClearSent;
  Later := AckTurn;
  Later.Id := 'ack-turn-2';
  Later.TurnIndex := 1;
  Later.Blocks[0].BlockId := 'ack-block-2';
  Session.ObserveTurn(Later);
  Session.DrainOutbound;
  Check('an idle poll still fills the next turn', Carrier.SentCount > 0);
  Flags := Default(TMonitorHostFlags);
  Session.SetHostFlags(Flags);
End;

Procedure TestPlanFrameBeforeBulk;
Var
  Before, Index: Integer;
  Ping, First, Second, Seen: String;
  Row: TAssistantMonitorPlanRow;
  Rows: Array Of TAssistantMonitorPlanRow;
Begin
  Ping := EncodeCommandTicks(mmkPing, 'plan-ping', 2);
  Row.Index := 0;
  Row.Level := 3;
  Row.Title := 'Check the first show';
  Row.ParentTitle := '';
  Row.Status := 'not started';
  Row.Actionable := True;
  SetLength(Rows, 1);
  Rows[0] := Row;
  First := EncodeStatePlan('plan-old', 'Documents/Plan.md', 'Overview', False, Rows);
  Row.Status := 'in progress';
  Rows[0] := Row;
  Second := EncodeStatePlan('plan-new', 'Documents/Plan.md', 'Overview', True, Rows);
  Carrier.ClearSent;
  Before := Session.FramesDropped;
  Check('first plan is queued', Session.TryQueueHostJson(First));
  Check('later plan replaces the unsent plan', Session.TryQueueHostJson(Second));
  Check('replaced plan is dropped', Session.FramesDropped = Before + 1);
  For Index := 1 To 3 Do
    Check('bulk still queues beside a plan', Session.TryQueueHostJson(BulkFrame(Index)));
  Check('bulk does not block the latest plan', Session.TryQueueHostJson(Second));
  Check('replacing the unsent plan drops the previous copy', Session.FramesDropped = Before + 2);
  Check('control ping is queued beside a plan', Session.TryQueueHostJson(Ping));
  Session.DrainOutbound;
  Check('ping, plan, and bulk are sent', Carrier.SentCount = 5);
  Check('ping stays ahead of the plan', Carrier.SentJson(0) = Ping);
  Check('latest plan is sent before bulk', Carrier.SentJson(1) = Second);
  Check('bulk follows the plan', Carrier.SentJson(2) = BulkFrame(1));
  Seen := '';
  For Index := 0 To Carrier.SentCount - 1 Do
    Seen := Seen + Carrier.SentJson(Index) + #10;
  Check('the older plan status is not sent', Pos('"plan-old"', Seen) = 0);
  Check('the new status is in the sent plan', Pos('"in progress"', Carrier.SentJson(1)) > 0);
End;


{ Plan item 2.2. Text that is not JSON never reaches the outbox as raw bytes; it is counted as dropped.
  A fresh session, so a link the failure closes does not change the shared session the later tests use. }
Procedure TestEncodeFailureNotQueued;
Var
  Fresh: TMonitorSession;
  Parts: TStringArray;
  Bytes: RawByteString;
  Before: Integer;
Begin
  Fresh := TMonitorSession.Create;
  Try
    Before := Fresh.FramesDropped;
    Check('invalid JSON is refused', Not Fresh.TryQueueHostJson('{"v":3,"id":"bad-1","type":"ping",'));
    Check('invalid JSON puts nothing in the outbox', Fresh.OutboundCount = 0);
    Check('invalid JSON is not taken by the link', Not Fresh.TakeOutboundFrame(Bytes));
    Check('invalid JSON is counted as dropped', Fresh.FramesDropped = Before + 1);
    Fresh.PublishState('status', '{"busy":');
    Check('a state value that is not JSON puts nothing in the outbox', Fresh.OutboundCount = 0);
    Check('a state value that is not JSON is counted as dropped', Fresh.FramesDropped = Before + 2);
  Finally
    Fresh.Free;
  End;
End;

{ A chunk whose envelope is over the frame cap must close the link and must not enter the outbox. }
Procedure TestChunkedStateEncodeCloses;
Var
  Fresh: TMonitorSession;
  ErrorText, Key: String;
  Bytes: RawByteString;
  Lane: TMonitorOutboxLane;
  SawKey: Boolean;
Begin
  Fresh := TMonitorSession.Create;
  Try
    Check('chunk failure can listen', Fresh.StartListening('127.0.0.1', 9, ErrorText));
    Fresh.PublishState('status', '{"busy":false}');
    Key := StringOfChar('k', MonitorMaxPayloadBytes);
    Fresh.PublishState(Key, '{"ok":true}');
    Check('unframeable state closes the link', Fresh.CloseRequested And (Fresh.State = mssListening));
    SawKey := False;
    While Fresh.TakeOutboundFrameWithLane(Bytes, Lane) Do
      If Pos(Key, String(Bytes)) > 0 Then
        SawKey := True;
    Check('unframeable state is not in the outbox', Not SawKey);
  Finally
    Fresh.Free;
  End;
End;

{ Plan item 5.1. Compile with -dMONITOR_COUNT_PARSES. One state frame parses its value once and does not parse
  the envelope again to classify it or to write the LAM1 header. }
{$IFDEF MONITOR_COUNT_PARSES}
Procedure TestStateFrameParsesOnce;
Var
  Fresh: TMonitorSession;
  Bytes: RawByteString;
  Lane: TMonitorOutboxLane;
  Parsed: Integer;
Begin
  Fresh := TMonitorSession.Create;
  Try
    MonitorJsonParseCount := 0;
    Fresh.PublishState('status', '{"busy":false}');
    Parsed := MonitorJsonParseCount;
    Check('one state frame parses at most once', Parsed <= 1);
    Check('one state frame is queued on the state lane', Fresh.TakeOutboundFrameWithLane(Bytes, Lane) And (Lane = molState));
    Check('one state frame is a LAM1 frame', Copy(Bytes, 1, 4) = MonitorFrameMagic);
  Finally
    Fresh.Free;
  End;
End;
{$ENDIF}

{ A catalogue 3 event large enough to fill the credit window, and too large for an outbox chunk. }

{ Plan item 4.2. Frames held past the log budget queue one protocol bye and request close. Further held frames
  do not queue another bye. }



{ A real patch payload with one answer block of BodyBytes copies of Fill. The log replays only what decodes as a patch. }




Procedure CheckClientVersionReject(Const Title: String; ClientVersion: Integer);
Var
  Data: TJSONData;
  Root, Payload: TJSONObject;
Begin
  Check(Title + ' closes', Session.CloseRequested And (Session.State = mssListening));
  Data := Nil;
  Try
    Data := GetJSON(LastJson);
  Except
    Data := Nil;
  End;
  Check(Title + ' is JSON', Data Is TJSONObject);
  If Not (Data Is TJSONObject) Then
    Begin
      Data.Free;
      Exit;
    End;
  Try
    Root := TJSONObject(Data);
    Check(Title + ' envelope version', Root.Get('v', 0) = ClientVersion);
    Check(Title + ' type', Root.Get('type', '') = 'rejected');
    Payload := Nil;
    If Root.Find('payload') Is TJSONObject Then
      Payload := TJSONObject(Root.Find('payload'));
    Check(Title + ' payload', Assigned(Payload));
    If Assigned(Payload) Then
      Begin
        Check(Title + ' reason protocol', Payload.Get('reason', '') = 'protocol');
        Check(Title + ' host version', Payload.Get('host_version', 0) = MonitorCatalogueVersion);
        Check(Title + ' client version', Payload.Get('client_version', 0) = ClientVersion);
      End;
  Finally
    Data.Free;
  End;
End;

Procedure TestOldCatalogueRejects;
Begin
  Carrier.ClearSent;
  Carrier.DeliverJson('{"v":1,"id":"old","type":"ping","payload":{"ticks":1}}');
  CheckClientVersionReject('old catalogue', 1);
End;

Procedure TestCatalogueMismatchHello;
Begin
  NewSocket;
  Carrier.ClearSent;
  Carrier.DeliverJson('{"v":2,"id":"hello-v2","type":"hello","payload":{"client_name":"Old phone","client_version":"2"}}');
  CheckClientVersionReject('v2 hello', 2);
End;

Procedure TestWorkOnPlanDoesNotBlockSend;
Var
  Sink: TCommandSink;
  Flags: TMonitorHostFlags;
  Json, ErrorJson: String;
Begin
  Sink := TCommandSink.Create;
  Try
    Session.OnCommand := @Sink.Hear;
    Flags := Default(TMonitorHostFlags);
    Flags.CanSend := True;
    Session.SetHostFlags(Flags);
    Check('work_on_plan starts live', Session.State = mssLive);
    Carrier.ClearSent;
    Carrier.DeliverJson(EncodeCommandWorkOnPlan('work-on-plan', 0));
    Check('work_on_plan is delivered', (Sink.Calls = 1) And (Sink.Kind = Ord(mmkWorkOnPlan)));
    Check('work_on_plan does not close the link', (Session.State = mssLive) And (Not Session.CloseRequested));
    Check('send after work_on_plan encodes', TryEncodeCommandSend('send-after-work', 'hello', Json, ErrorJson, False));
    Carrier.DeliverJson(Json);
    Check('send after work_on_plan is admitted', (Sink.Calls = 2) And (Sink.Kind = Ord(mmkSend)));
    Check('send after work_on_plan is queued', QueuedOnce('send-after-work'));
    Flags.Sending := True;
    Session.SetHostFlags(Flags);
    Flags := Default(TMonitorHostFlags);
    Session.SetHostFlags(Flags);
  Finally
    Session.OnCommand := Nil;
    Sink.Free;
  End;
End;

Procedure TestCommandLifecycle;
Var
  Sink: TCommandSink;
  Flags: TMonitorHostFlags;
  Json, ErrorJson: String;
  Message: TMonitorMessage;
  ErrorBody: TMonitorErrorBody;
  Data: TJSONData;
  States: TJSONArray;
  Item: TJSONObject;
  Index: Integer;
Begin
  Sink := TCommandSink.Create;
  Try
    Session.OnCommand := @Sink.Hear;
    Flags := Default(TMonitorHostFlags);
    Flags.CanSend := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Check('lifecycle send encodes', TryEncodeCommandSend('send-live', 'hello', Json, ErrorJson));
    Carrier.DeliverJson(Json);
    Check('send stays live until the form reports sending', Session.State = mssLive);
    Check('send is answered queued once', QueuedOnce('send-live'));
    Check('send reached the bridge hook once', Sink.Calls = 1);
    Carrier.ClearSent;
    Check('pending steer encodes', TryEncodeCommandSteer('steer-pending', 'not yet', Json, ErrorJson));
    Carrier.DeliverJson(Json);
    Check('steer during the pending gap is not a second prompt', Sink.Calls = 1);
    Check('steer during the pending gap is refused', DecodeLast(Message) And (Message.Kind = mmkError) And
      (Message.Reason = 'host_busy'));
    Check('pending send is still live', Session.State = mssLive);
    Flags.Sending := True;
    Session.SetHostFlags(Flags);
    Check('sending flag is what makes the session busy', Session.State = mssBusy);
    Flags := Default(TMonitorHostFlags);
    Flags.CanSend := True;
    Session.SetHostFlags(Flags);
    Check('finished send returns to live', Session.State = mssLive);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Check('repeat send encodes', TryEncodeCommandSend('send-live', 'again', Json, ErrorJson));
    Carrier.DeliverJson(Json);
    Check('repeated id does not reach the hook again', Sink.Calls = 0);
    Check('repeated id is command_state', DecodeLast(Message) And (Message.Kind = mmkCommandState) And
      (PayloadField(Message.PayloadJson, 'state') = 'done'));
    Carrier.ClearSent;
    Flags.Sending := True;
    Session.SetHostFlags(Flags);
    Check('blocked send encodes', TryEncodeCommandSend('send-blocked', 'no', Json, ErrorJson));
    Carrier.DeliverJson(Json);
    Check('blocked send does not reach the hook', Sink.Calls = 0);
    Check('blocked send is an error', DecodeLast(Message) And (Message.Kind = mmkError) And
      DecodeMonitorError(Message.PayloadJson, ErrorBody) And (ErrorBody.Reason = 'host_busy'));
    Carrier.ClearSent;
    Carrier.DeliverJson('{"v":3,"id":"resume-states","type":"resume","payload":{"epoch":"","cursor":0,"commands":["send-blocked"]}}');
    Message.Kind := mmkUnknown;
    Message.PayloadJson := '';
    For Index := 0 To Carrier.SentCount - 1 Do
      If TryDecodeMonitorEnvelope(Carrier.SentJson(Index), Message, ErrorJson) And (Message.Kind = mmkCommandStates) Then
        Break;
    Check('blocked command is answered with command_states', Message.Kind = mmkCommandStates);
    If Message.Kind = mmkCommandStates Then
      Data := GetJSON(String(Message.PayloadJson))
    Else
      Data := Nil;
    Try
      Check('command_states has a states array', Assigned(Data) And (Data Is TJSONObject) And
        (TJSONObject(Data).Find('states') Is TJSONArray));
      If Assigned(Data) And (Data Is TJSONObject) And (TJSONObject(Data).Find('states') Is TJSONArray) Then
        Begin
          States := TJSONArray(TJSONObject(Data).Find('states'));
          Item := States.Objects[0];
          Check('rejected state is in command_states', (Item.Get('ref', '') = 'send-blocked') And
            (Item.Get('state', '') = 'rejected') And (Item.Get('reason', '') = 'host_busy'));
        End;
    Finally
      Data.Free;
    End;
    Flags := Default(TMonitorHostFlags);
    Flags.CanSend := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Check('later send encodes', TryEncodeCommandSend('send-wait', 'still here', Json, ErrorJson));
    Carrier.DeliverJson(Json);
    Check('an accepted send is not host_busy', QueuedOnce('send-wait'));
    Check('an accepted send reaches the hook once', Sink.Calls = 1);
    Check('an accepted send leaves the session live', Session.State = mssLive);
  Finally
    Flags := Default(TMonitorHostFlags);
    Flags.Sending := True;
    Session.SetHostFlags(Flags);
    Flags.Sending := False;
    Flags.CanSend := True;
    Session.SetHostFlags(Flags);
    Session.OnCommand := Nil;
    Sink.Free;
  End;
End;

Procedure TestSelectTarget;
Var
  Sink: TCommandSink;
  Flags: TMonitorHostFlags;
  Message: TMonitorMessage;
  ErrorBody: TMonitorErrorBody;
Begin
  Sink := TCommandSink.Create;
  Try
    Session.OnCommand := @Sink.Hear;
    Flags := Default(TMonitorHostFlags);
    Flags.CanSend := True;
    Flags.CanChangeMode := True;
    Session.SetHostFlags(Flags);
    Check('select_target starts live', Session.State = mssLive);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeCommandPath(mmkSelectTarget, 'select-target', ''));
    Check('empty path select_target is accepted', (Sink.Calls = 1) And (Sink.Kind = Ord(mmkSelectTarget)));
    Check('empty path select_target is answered queued once', QueuedOnce('select-target'));
    Flags.Sending := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeCommandPath(mmkSelectTarget, 'select-target-busy', '/work/Other'));
    Check('sending select_target is not queued', Sink.Calls = 0);
    Check('sending select_target error', DecodeLast(Message) And (Message.Kind = mmkError) And (Message.Reason = 'host_busy'));
    Check('sending select_target sentence', DecodeMonitorError(Message.PayloadJson, ErrorBody) And
      (ErrorBody.MessageText = 'Wait for the current reply to finish.'));
    Flags.Sending := False;
    Flags.PlanAgentRunning := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeCommandPath(mmkSelectTarget, 'select-target-plan', '/work/Other'));
    Check('plan-running select_target is not queued', Sink.Calls = 0);
    Check('plan-running select_target is host_busy', DecodeLast(Message) And (Message.Kind = mmkError) And
      (Message.Reason = 'host_busy'));
    Flags := Default(TMonitorHostFlags);
    Flags.CanSend := True;
    Session.SetHostFlags(Flags);
  Finally
    Session.OnCommand := Nil;
    Sink.Free;
  End;
End;

Procedure TestSelectConversation;
Var
  Sink: TCommandSink;
  Flags: TMonitorHostFlags;
  Message: TMonitorMessage;
  ErrorBody: TMonitorErrorBody;
Begin
  Sink := TCommandSink.Create;
  Try
    Session.OnCommand := @Sink.Hear;
    Flags := Default(TMonitorHostFlags);
    Flags.CanSend := True;
    Flags.CanChangeMode := True;
    Session.SetHostFlags(Flags);
    Check('select_conversation starts live', Session.State = mssLive);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeCommandSelectConversation('select-conversation', ''));
    Check('empty id select_conversation is accepted', (Sink.Calls = 1) And (Sink.Kind = Ord(mmkSelectConversation)));
    Check('empty id select_conversation is answered queued once', QueuedOnce('select-conversation'));
    Flags.PlanAgentRunning := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeCommandSelectConversation('select-conversation-plan', '20261019T120000000'));
    Check('plan-running select_conversation is accepted', (Sink.Calls = 1) And (Sink.Kind = Ord(mmkSelectConversation)));
    Check('plan-running select_conversation is answered queued once', QueuedOnce('select-conversation-plan'));
    Flags.PlanAgentRunning := False;
    Flags.Sending := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeCommandSelectConversation('select-conversation-busy', '20261019T120000000'));
    Check('sending select_conversation is not queued', Sink.Calls = 0);
    Check('sending select_conversation error', DecodeLast(Message) And (Message.Kind = mmkError) And (Message.Reason = 'host_busy'));
    Check('sending select_conversation sentence', DecodeMonitorError(Message.PayloadJson, ErrorBody) And
      (ErrorBody.MessageText = 'Stop the current reply before switching History.'));
    Flags := Default(TMonitorHostFlags);
    Flags.CanSend := True;
    Session.SetHostFlags(Flags);
  Finally
    Session.OnCommand := Nil;
    Sink.Free;
  End;
End;

Procedure TestSetModel;
Var
  Sink: TCommandSink;
  Flags: TMonitorHostFlags;
  Message: TMonitorMessage;
  ErrorBody: TMonitorErrorBody;
Begin
  Sink := TCommandSink.Create;
  Try
    Session.OnCommand := @Sink.Hear;
    Flags := Default(TMonitorHostFlags);
    Flags.CanSend := True;
    Flags.CanChangeMode := True;
    Session.SetHostFlags(Flags);
    Check('set_model starts live', Session.State = mssLive);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeCommandSetModel('set-model', 'grok-4'));
    Check('set_model is accepted', (Sink.Calls = 1) And (Sink.Kind = Ord(mmkSetModel)));
    Check('set_model is answered queued once', QueuedOnce('set-model'));
    Flags.PlanAgentRunning := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeCommandSetModel('set-model-plan', 'grok-4'));
    Check('plan-running set_model is not queued', Sink.Calls = 0);
    Check('plan-running set_model is host_busy', DecodeLast(Message) And (Message.Kind = mmkError) And (Message.Reason = 'host_busy'));
    Check('plan-running set_model sentence', DecodeMonitorError(Message.PayloadJson, ErrorBody) And
      (ErrorBody.MessageText = 'Wait until the current work finishes before changing the model, effort, or permissions.'));
    Flags.PlanAgentRunning := False;
    Flags.Sending := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeCommandSetModel('set-model-busy', 'grok-4'));
    Check('sending set_model is not queued', Sink.Calls = 0);
    Check('sending set_model error', DecodeLast(Message) And (Message.Kind = mmkError) And (Message.Reason = 'host_busy'));
    Check('sending set_model sentence', DecodeMonitorError(Message.PayloadJson, ErrorBody) And
      (ErrorBody.MessageText = 'Wait until the current work finishes before changing the model, effort, or permissions.'));
    Flags := Default(TMonitorHostFlags);
    Flags.CanSend := True;
    Session.SetHostFlags(Flags);
  Finally
    Session.OnCommand := Nil;
    Sink.Free;
  End;
End;

Procedure TestSetReasoning;
Var
  Sink: TCommandSink;
  Flags: TMonitorHostFlags;
  Message: TMonitorMessage;
  ErrorBody: TMonitorErrorBody;
Begin
  Sink := TCommandSink.Create;
  Try
    Session.OnCommand := @Sink.Hear;
    Flags := Default(TMonitorHostFlags);
    Flags.CanSend := True;
    Flags.CanChangeMode := True;
    Session.SetHostFlags(Flags);
    Check('set_reasoning starts live', Session.State = mssLive);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeCommandSetReasoning('set-reasoning', ''));
    Check('empty set_reasoning is accepted', (Sink.Calls = 1) And (Sink.Kind = Ord(mmkSetReasoning)));
    Check('empty set_reasoning is answered queued once', QueuedOnce('set-reasoning'));
    Flags.PlanAgentRunning := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeCommandSetReasoning('set-reasoning-plan', 'high'));
    Check('plan-running set_reasoning is not queued', Sink.Calls = 0);
    Check('plan-running set_reasoning is host_busy', DecodeLast(Message) And (Message.Kind = mmkError) And
      (Message.Reason = 'host_busy'));
    Check('plan-running set_reasoning sentence', DecodeMonitorError(Message.PayloadJson, ErrorBody) And
      (ErrorBody.MessageText = 'Wait until the current work finishes before changing the model, effort, or permissions.'));
    Flags.PlanAgentRunning := False;
    Flags.Sending := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeCommandSetReasoning('set-reasoning-busy', 'high'));
    Check('sending set_reasoning is not queued', Sink.Calls = 0);
    Check('sending set_reasoning error', DecodeLast(Message) And (Message.Kind = mmkError) And (Message.Reason = 'host_busy'));
    Check('sending set_reasoning sentence', DecodeMonitorError(Message.PayloadJson, ErrorBody) And
      (ErrorBody.MessageText = 'Wait until the current work finishes before changing the model, effort, or permissions.'));
    Flags := Default(TMonitorHostFlags);
    Flags.CanSend := True;
    Session.SetHostFlags(Flags);
  Finally
    Session.OnCommand := Nil;
    Sink.Free;
  End;
End;

Procedure TestSetPermissions;
Var
  Sink: TCommandSink;
  Flags: TMonitorHostFlags;
  Message: TMonitorMessage;
  ErrorBody: TMonitorErrorBody;
Begin
  Sink := TCommandSink.Create;
  Try
    Session.OnCommand := @Sink.Hear;
    Flags := Default(TMonitorHostFlags);
    Flags.CanSend := True;
    Flags.CanChangeMode := True;
    Session.SetHostFlags(Flags);
    Check('set_permissions starts live', Session.State = mssLive);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeCommandSetPermissions('set-permissions', 'ask'));
    Check('set_permissions is accepted', (Sink.Calls = 1) And (Sink.Kind = Ord(mmkSetPermissions)));
    Check('set_permissions is not an approval decision', Sink.Kind <> Ord(mmkApprovalDecision));
    Check('set_permissions is answered queued once', QueuedOnce('set-permissions'));
    Flags.PlanAgentRunning := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeCommandSetPermissions('set-permissions-plan', 'auto'));
    Check('plan-running set_permissions is not queued', Sink.Calls = 0);
    Check('plan-running set_permissions is host_busy', DecodeLast(Message) And (Message.Kind = mmkError) And
      (Message.Reason = 'host_busy'));
    Check('plan-running set_permissions sentence', DecodeMonitorError(Message.PayloadJson, ErrorBody) And
      (ErrorBody.MessageText = 'Wait until the current work finishes before changing the model, effort, or permissions.'));
    Flags.PlanAgentRunning := False;
    Flags.Sending := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeCommandSetPermissions('set-permissions-busy', 'always'));
    Check('sending set_permissions is not queued', Sink.Calls = 0);
    Check('sending set_permissions error', DecodeLast(Message) And (Message.Kind = mmkError) And (Message.Reason = 'host_busy'));
    Check('sending set_permissions sentence', DecodeMonitorError(Message.PayloadJson, ErrorBody) And
      (ErrorBody.MessageText = 'Wait until the current work finishes before changing the model, effort, or permissions.'));
    Flags := Default(TMonitorHostFlags);
    Flags.CanSend := True;
    Session.SetHostFlags(Flags);
  Finally
    Session.OnCommand := Nil;
    Sink.Free;
  End;
End;

Procedure TestUnknownTypeDoesNotChangeLive;
Var
  Message: TMonitorMessage;
Begin
  Carrier.ClearSent;
  Carrier.DeliverJson('{"v":3,"id":"u1","type":"not_a_type","payload":{}}');
  Check('unknown type stays live', Session.State = mssLive);
  Check('unknown type does not close', Not Session.CloseRequested);
  Check('unknown type error frame', DecodeLast(Message) And (Message.Kind = mmkError) And (Message.Reason = 'unknown_type'));
End;

Procedure TestSecondControllerWhileLive;
Var
  Message: TMonitorMessage;
  Ticks: TMonitorTicks;
Begin
  ExpectBusySpare('live');
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeCommandTicks(mmkPing, 'ping-live', 42));
  Check('controller still live', Session.State = mssLive);
  Check('controller still answers ping', DecodeLast(Message) And (Message.Kind = mmkPong) And
    DecodeCommandTicks(Message.PayloadJson, Ticks) And (Ticks.Ticks = 42));
End;

Procedure TestDecisionIgnoredWhenDisabled;
Var
  Event: PRTLEvent;
Begin
  Event := RTLEventCreate;
  Try
    ArmAssistantApprovalWait(Event);
    Session.SetRemoteApproval(False);
    Carrier.ClearSent;
    Carrier.DeliverJson(EncodeStateApprovalDecision('decide-off', 'tool-off', True));
    Check('disabled decision stays live', Session.State = mssLive);
    Check('disabled decision sends nothing', Carrier.SentCount = 0);
    Check('disabled decision ignored', Not Session.ApplyApprovalDecision('tool-off', True));
    Check('disabled decision leaves none', ReadAssistantApprovalDecision = aadNone);
  Finally
    { Disarm first. A later signal must not touch this freed event. }
    DisarmAssistantApprovalWait(Event);
    RTLEventDestroy(Event);
  End;
End;

Procedure TestResumeQueued;
Var
  Sink: TCommandSink;
  Flags: TMonitorHostFlags;
  Message: TMonitorMessage;
  ErrorBody: TMonitorErrorBody;
Begin
  Sink := TCommandSink.Create;
  Try
    Session.OnCommand := @Sink.Hear;
    Flags := Default(TMonitorHostFlags);
    Flags.Sending := True;
    Flags.CanStop := True;
    Session.SetHostFlags(Flags);
    Check('resume setup is busy', Session.State = mssBusy);
    Carrier.ClearSent;
    Carrier.DeliverJson(EncodeCommandResume('resume-busy', '', 0));
    { Since eefac54 the session answers every resume from the mirror. The form never receives one. }
    Check('busy resume is answered by the session, not the form', Sink.Calls = 0);
    Check('busy resume is not host_busy', (Carrier.SentCount = 0) Or
      (Not (DecodeLast(Message) And (Message.Kind = mmkError) And DecodeMonitorError(Message.PayloadJson, ErrorBody) And
      (ErrorBody.Reason = MonitorHostBusyReason))));
    Flags := Default(TMonitorHostFlags);
    Flags.CanSend := True;
    Session.SetHostFlags(Flags);
    Check('resume setup returns to live', Session.State = mssLive);
  Finally
    Session.OnCommand := Nil;
    Sink.Free;
  End;
End;

Procedure TestRevokeLive;
Var
  Message: TMonitorMessage;
  Bye: TMonitorBye;
  Settings: TMonitorSettings;
  ErrorText: String;
Begin
  Carrier.ClearSent;
  Session.RevokeClient(SavedClientId);
  Check('revoke frame', DecodeLast(Message) And (Message.Kind = mmkBye));
  Check('revoke payload', DecodeCommandBye(Message.PayloadJson, Bye) And (Bye.Reason = 'revoked'));
  Check('revoke closes', Session.CloseRequested);
  Check('revoke state', Session.State = mssRevoked);
  Check('revoke save', LoadMonitorSettings(Settings, ErrorText));
  Check('revoke removes the client', Length(Settings.Clients) = 0);
  Check('revoke keeps port', Settings.Port = 56123);
  Check('revoke does not enable remote approval', Not Settings.RemoteApproval);
  CheckOtherSections('after revoke save');
End;

Procedure TestRevokedNewSocket;
Begin
  NewSocket;
  DeliverHello(SavedClientId);
  ExpectRejected('revoked id', 'revoked', True);
  Check('revoked id never live', Session.State <> mssLive);
End;

Function CountSent(Const TypeName: String): Integer;
Var
  I: Integer;
  Message: TMonitorMessage;
  ErrorText: String;
Begin
  Result := 0;
  For I := 0 To Carrier.SentCount - 1 Do
    If TryDecodeMonitorEnvelope(Carrier.SentJson(I), Message, ErrorText) And (Message.TypeName = TypeName) Then
      Inc(Result);
End;

Procedure TestDisplayApproval;
Var
  Message: TMonitorMessage;
  Notice: TAssistantApprovalNotice;
  Closed: TMonitorApprovalClosed;
  Event: PRTLEvent;
Begin
  Event := RTLEventCreate;
  Try
    ArmAssistantApprovalWait(Event);
    Session.SetRemoteApproval(True);
    Carrier.ClearSent;
    Session.PublishDisplayApproval('tool-desk', 'write_file', 'Write the test.', 'Ask');
    Session.PublishDisplayApproval('tool-desk', 'write_file', 'Write the test.', 'Ask');
    Check('one display approval', CountSent('approval_requested') = 1);
    Check('display approval frame', DecodeLast(Message) And (Message.Kind = mmkApprovalRequested));
    Check('display approval payload', DecodeStateApprovalRequested(Message.PayloadJson, Notice));
    Check('display approval is not accepted', (Notice.ToolId = 'tool-desk') And (Not Notice.DecisionsAccepted));
    Check('display decision ignored', Not Session.ApplyApprovalDecision('tool-desk', True));
    Check('display decision leaves none', ReadAssistantApprovalDecision = aadNone);
    Session.CloseDisplayApproval('tool-desk');
    Check('still one display approval', CountSent('approval_requested') = 1);
    Check('display close frame', DecodeLast(Message) And (Message.Kind = mmkApprovalClosed));
    Check('display close desktop', DecodeStateApprovalClosed(Message.PayloadJson, Closed) And (Closed.Reason = 'desktop') And
      (Closed.ToolId = 'tool-desk'));
    Check('closed id decision ignored', Not Session.ApplyApprovalDecision('tool-desk', True));
    Check('closed id leaves none', ReadAssistantApprovalDecision = aadNone);
  Finally
    { Disarm first. A later signal must not touch this freed event. }
    DisarmAssistantApprovalWait(Event);
    RTLEventDestroy(Event);
  End;
End;

Procedure TestBareSignalAndCancel;
Var
  Event: PRTLEvent;
Begin
  Event := RTLEventCreate;
  Try
    ArmAssistantApprovalWait(Event);
    SignalAssistantApprovalWait;
    Check('bare signal leaves none', ReadAssistantApprovalDecision = aadNone);
    Session.NoteApprovalCancel('tool-stop');
    Check('cancel stores stopped', ReadAssistantApprovalDecision = aadStopped);
    Check('later allow does not replace stopped', ReadAssistantApprovalDecision = aadStopped);
    Check('allow after cancel is rejected', Not Session.ApplyApprovalDecision('tool-stop', True));
    Check('allow after cancel stays stopped', ReadAssistantApprovalDecision = aadStopped);
  Finally
    { Disarm first. A later signal must not touch this freed event. }
    DisarmAssistantApprovalWait(Event);
    RTLEventDestroy(Event);
  End;
End;

{ Plan item 4.3. The session clock is driven through NoteTime, so no test waits. Leaves the controller live again. }
Procedure TestHeartbeat;
Var
  Start, Heard: QWord;
  Nonce: String;
Begin
  Check('heartbeat interval is 10 s', MonitorHeartbeatMs = 10000);
  Check('dead link time is 30 s', MonitorDeadSessionMs = 30000);
  Check('heartbeat starts live', Session.State = mssLive);
  Start := 5000;
  Session.NoteTime(Start);
  Carrier.ClearSent;
  { The pong to this ping is the last frame sent, and the ping is the last frame received. }
  Carrier.DeliverJson(EncodeCommandTicks(mmkPing, 'beat-start', 1));
  Carrier.ClearSent;
  Session.NoteTime(Start + MonitorHeartbeatMs - 1);
  Check('no ping before 10 s without sending', CountSent('ping') = 0);
  Session.NoteTime(Start + MonitorHeartbeatMs);
  Check('a ping after 10 s without sending', CountSent('ping') = 1);
  Session.NoteTime(Start + MonitorHeartbeatMs + 5000);
  Check('the ping restarts the quiet clock', CountSent('ping') = 1);
  Session.SendHostJson(EncodeCommandTicks(mmkPong, 'beat-host-frame', 2));
  Session.NoteTime(Start + 2 * MonitorHeartbeatMs);
  Check('any sent frame restarts the quiet clock', CountSent('ping') = 1);
  Session.NoteTime(Start + 2 * MonitorHeartbeatMs + 5000);
  Check('a second ping after another quiet 10 s', CountSent('ping') = 2);
  Session.NoteTime(Start + MonitorDeadSessionMs - 1);
  Check('live just under 30 s without receiving', (Session.State = mssLive) And (Not Session.CloseRequested));
  Heard := Start + MonitorDeadSessionMs - 1;
  Carrier.DeliverJson(EncodeCommandTicks(mmkPing, 'beat-heard', 3));
  Session.NoteTime(Start + MonitorDeadSessionMs);
  Check('a received frame restarts the dead-link clock', (Session.State = mssLive) And (Not Session.CloseRequested));
  Session.NoteTime(Heard + MonitorDeadSessionMs - 1);
  Check('our own pings do not end the link', (Session.State = mssLive) And (CountSent('ping') >= 3));
  Session.NoteTime(Heard + MonitorDeadSessionMs);
  Check('dead after 30 s without receiving', Session.CloseRequested And (Session.State = mssListening));
  NewSocket;
  DeliverHello(SavedClientId);
  Nonce := NonceFromLast;
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeCommandAuth('auth-beat', SavedClientId, MonitorAuthMac(SavedToken, Nonce)));
  Check('the phone reconnects after a dead link', Session.State = mssLive);
End;

Procedure CleanupSettings;
Begin
  If SettingsRoot = '' Then
    Exit;
  If WorkflowSettingsPath <> '' Then
    Begin
      DeleteFile(WorkflowSettingsPath);
      DeleteFile(WorkflowSettingsPath + '.tmp');
    End;
  SetWorkflowSettingsDirectory('');
  RemoveDir(ExcludeTrailingPathDelimiter(SettingsRoot));
  SettingsRoot := '';
End;

Procedure PrepareSettings;
Var
  Guid: TGuid;
Begin
  If CreateGUID(Guid) <> 0 Then
    Raise Exception.Create('Could not create a settings directory name');
  SettingsRoot := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-monitor-session-' + GUIDToString(Guid);
  If Not ForceDirectories(SettingsRoot) Then
    Raise Exception.Create('Could not create ' + SettingsRoot);
  SetWorkflowSettingsDirectory(SettingsRoot);
End;

Begin
  FailCount := 0;
  Carrier := Nil;
  CarrierRef := Nil;
  Session := Nil;
  SettingsRoot := '';
  SavedClientId := '';
  SavedToken := '';
  DiscardedCode := '';
  Try
    Try
      PrepareSettings;
      SeedOtherSections;
      TestSettingsLoadSave;
      TestOfflineRevoke;
      Carrier := TMonitorMemoryCarrier.Create;
      CarrierRef := Carrier;
      Session := TMonitorSession.Create;
      Session.AttachCarrier(CarrierRef);
      TestSharedApprovalFlag;
      Session.SetHostFingerprint('ab12cd34');
      Session.NoteTime(5000);
      Check('listen starts', Session.StartListening('10.1.2.3', 56123, ErrorText));
      If ErrorText <> '' Then
        WriteLn(ErrorText);
      Check('listen state', Session.State = mssListening);
      TestLoopbackPairingPolicy;
      TestPairCodeOptional;
      TestCodeAbsentUntilRequested;
      TestSecondControllerWhileAccepted;
      TestCommandBeforeAuth;
      TestThreeFailuresDiscard;
      TestPairAfterDiscard;
      TestPairSuccess;
      TestHmac;
      TestAckThroughCarrier;
      TestAckRules;
      TestObservedResumeCarriesStatus;
      TestIdlePollStillFills;
      TestReconnectKeepsRunningTurn;
      TestIdleSteerSubmits;
      TestWorkOnPlanDoesNotBlockSend;
      TestCommandLifecycle;
      TestSelectTarget;
      TestSelectConversation;
      TestSetModel;
      TestSetReasoning;
      TestSetPermissions;
      TestUnknownTypeDoesNotChangeLive;
      TestSecondControllerWhileLive;
      TestHeartbeat;
      TestDecisionIgnoredWhenDisabled;
      TestResumeQueued;
      TestRevokeLive;
      TestRevokedNewSocket;
      TestDisplayApproval;
      TestBareSignalAndCancel;
      TestSpacedEventSeq;
      TestPlanFrameBeforeBulk;
      TestEncodeFailureNotQueued;
      TestChunkedStateEncodeCloses;
      {$IFDEF MONITOR_COUNT_PARSES}
      TestStateFrameParsesOnce;
      {$ENDIF}
      TestOldCatalogueRejects;
      TestCatalogueMismatchHello;
      CheckOtherSections('at end');
    Except
      On E: Exception Do
        Begin
          WriteLn('FAIL exception ', E.Message);
          Inc(FailCount);
        End;
    End;
  Finally
    If Assigned(Session) Then
      Session.Free;
    CarrierRef := Nil;
    Carrier := Nil;
    CleanupSettings;
  End;
  { Do not Halt on success. Halt skips this block's temporary finalization, and heaptrc then reports those strings as leaks. }
  If FailCount = 0 Then
    WriteLn('All AssistantMonitorSessionTest tests passed.')
  Else
    Begin
      WriteLn(FailCount, ' AssistantMonitorSessionTest test(s) failed.');
      Halt(1);
    End;
End.
