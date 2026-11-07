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
  Classes, SysUtils, DateUtils, SyncObjs, fpjson, AssistantMonitorLinkStubs,
  AssistantMonitorCodec, AssistantMonitorFrames, AssistantMonitorCarrier, AssistantMonitorMirror, AssistantMonitorOutbox,
  AssistantMonitorSession,
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
  Check('loaded clients empty', Length(Settings.Clients) = 0);
  CheckOtherSections('after monitor save');
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
  Check(Title + ' payload', DecodeMonitorRejected(Message.PayloadJson, Rejected));
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
  Check(Title + ' spare payload', DecodeMonitorRejected(Message.PayloadJson, Rejected));
  Check(Title + ' spare busy', Rejected.Reason = 'busy');
End;

Procedure DeliverHello(Const ClientId: String);
Begin
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeMonitorHello('hello', 'Phone', '1', ClientId));
End;

Procedure DeliverPair(Const Code: String);
Begin
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeMonitorPair('pair', Code, 'ab12cd34'));
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
  Check('pair_ok payload', DecodeMonitorPairOk(Message.PayloadJson, PairOk));
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
  If Not DecodeMonitorHelloOk(Message.PayloadJson, HelloOk) Then
    Exit;
  Result := HelloOk.Nonce;
End;

Procedure TestOpenLanAdmitsWithoutCode;
Var
  Settings: TMonitorSettings;
  ErrorText: String;
Begin
  NewSocket;
  DeliverHello('');
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeMonitorPair('pair', '', ''));
  ExpectPairOk;
  Check('open pair stores client', LoadMonitorSettings(Settings, ErrorText) And (Length(Settings.Clients) = 1));
  Session.RevokeClient(SavedClientId);
  Session.NoteSocketClosed;
  Check('open pair revoked', LoadMonitorSettings(Settings, ErrorText) And (Length(Settings.Clients) = 0));
  Check('open pair returns to listening', Session.State = mssListening);
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
  Carrier.DeliverJson(EncodeMonitorEmpty(mmkSend, 'send-early'));
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
  Carrier.DeliverJson(EncodeMonitorAuth('auth-bad', SavedClientId, 'not-a-mac'));
  ExpectRejected('hmac failure', 'auth', True);
  Check('hmac failure is not live', Session.State <> mssLive);
  NewSocket;
  DeliverHello(SavedClientId);
  Nonce := NonceFromLast;
  Check('second nonce', Length(Nonce) = MonitorNonceBytes * 2);
  Carrier.ClearSent;
  Carrier.DeliverJson(EncodeMonitorAuth('auth-ok', SavedClientId, MonitorAuthMac(SavedToken, Nonce)));
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
  Carrier.DeliverJson(EncodeMonitorAuth('auth-run', SavedClientId, MonitorAuthMac(SavedToken, Nonce)));
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
    Check('idle steer encodes', TryEncodeMonitorSteer('steer-idle', 'hello from the phone', Json, ErrorJson));
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
    Check('running steer encodes', TryEncodeMonitorSteer('steer-run', 'nudge', Json, ErrorJson));
    Carrier.DeliverJson(Json);
    Check('running steer stays steer', (Sink.Calls = 1) And (Sink.Kind = Ord(mmkSteer)));
    Flags := Default(TMonitorHostFlags);
    Session.SetHostFlags(Flags);
    Check('finished turn is live', Session.State = mssLive);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Check('blocked steer encodes', TryEncodeMonitorSteer('steer-block', 'later', Json, ErrorJson));
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

Function BulkFrame(Index: Integer): String;
Begin
  Result := '{"v":2,"id":"bulk-' + IntToStr(Index) + '","type":"snapshot","payload":{}}';
End;

{ A live part is a real envelope. The id carries the name, so a check can find the part in the sent frames. }
Function LivePart(Const Name: String): String;
Begin
  Result := '{"v":2,"id":"' + Name + '","type":"patch","payload":{}}';
End;

Procedure TestOutboundLanes;
Var
  Index, Before: Integer;
  Ping, Seen: String;
  First, Second: TStringArray;
Begin
  Ping := EncodeMonitorTicks(mmkPing, 'lane-ping', 1);
  Carrier.ClearSent;
  For Index := 1 To 3 Do
    Check('bulk lane accepts ' + IntToStr(Index), Session.TryQueueHostJson(BulkFrame(Index)));
  SetLength(First, 2);
  First[0] := LivePart('patch-part-1');
  First[1] := LivePart('patch-part-2');
  SetLength(Second, 1);
  Second[0] := LivePart('patch-replaced');
  Before := Session.FramesDropped;
  Session.ReplaceLivePatch(8, First);
  Session.ReplaceLivePatch(9, Second);
  Check('a newer live set replaces the unsent parts', Session.FramesDropped = Before + 2);
  Check('control ping is queued beside bulk and state', Session.TryQueueHostJson(Ping));
  Session.DrainOutbound;
  Check('drain sends ping, the replacement, and the bulk lane', Carrier.SentCount = 5);
  Check('control ping is sent before the other lanes', Carrier.SentJson(0) = Ping);
  Check('live replacement is sent and not appended', Carrier.SentJson(1) = LivePart('patch-replaced'));
  Seen := '';
  For Index := 0 To Carrier.SentCount - 1 Do
    Seen := Seen + Carrier.SentJson(Index) + #10;
  Check('dropped live parts are not sent', Pos('patch-part-1', Seen) = 0);
  Check('bulk frames follow the live patch', Carrier.SentJson(2) = BulkFrame(1));
End;

Procedure TestPlanFrameBeforeBulk;
Var
  Before, Index: Integer;
  Ping, First, Second, Seen: String;
  Row: TAssistantMonitorPlanRow;
  Rows: Array Of TAssistantMonitorPlanRow;
Begin
  Ping := EncodeMonitorTicks(mmkPing, 'plan-ping', 2);
  Row.Index := 0;
  Row.Level := 3;
  Row.Title := 'Check the first show';
  Row.ParentTitle := '';
  Row.Status := 'not started';
  Row.Actionable := True;
  SetLength(Rows, 1);
  Rows[0] := Row;
  First := EncodeMonitorPlan('plan-old', 'Documents/Plan.md', 'Overview', False, Rows);
  Row.Status := 'in progress';
  Rows[0] := Row;
  Second := EncodeMonitorPlan('plan-new', 'Documents/Plan.md', 'Overview', True, Rows);
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

Procedure TestLivePatchReplaces;
Var
  First, Second: TStringArray;
  Before: Integer;
Begin
  SetLength(First, 2);
  First[0] := LivePart('patch-part-1');
  First[1] := LivePart('patch-part-2');
  SetLength(Second, 1);
  Second[0] := LivePart('patch-replaced');
  Before := Session.FramesDropped;
  Carrier.ClearSent;
  Session.ReplaceLivePatch(4, First);
  Session.ReplaceLivePatch(5, Second);
  Check('replaced unsent parts are dropped', Session.FramesDropped = Before + 2);
  Session.FlushLivePatch;
  Check('live lane sends the replacement only', (Carrier.SentCount = 1) And
    (Carrier.SentJson(0) = LivePart('patch-replaced')));
  Session.ReplaceLivePatch(6, First);
  SetLength(First, 0);
  Session.ReplaceLivePatch(6, First);
  Session.FlushLivePatch;
  Check('empty replace does not append', Carrier.SentCount = 1);
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
    Check('invalid JSON is refused', Not Fresh.TryQueueHostJson('{"v":2,"id":"bad-1","type":"ping",'));
    Check('invalid JSON puts nothing in the outbox', Fresh.OutboundCount = 0);
    Check('invalid JSON is not taken by the link', Not Fresh.TakeOutboundFrame(Bytes));
    Check('invalid JSON is counted as dropped', Fresh.FramesDropped = Before + 1);
    Fresh.PublishState('status', '{"busy":');
    Check('a state value that is not JSON puts nothing in the outbox', Fresh.OutboundCount = 0);
    Check('a state value that is not JSON is counted as dropped', Fresh.FramesDropped = Before + 2);
    SetLength(Parts, 1);
    Parts[0] := 'patch-part-1';
    Fresh.ReplaceLivePatch(1, Parts);
    Check('a placeholder live part puts nothing in the outbox', Fresh.OutboundCount = 0);
    Check('a placeholder live part is counted as dropped', Fresh.FramesDropped = Before + 3);
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
Function CreditEvent(Seq: Integer; Const Pad: String): String;
Begin
  Result := '{"v":3,"id":"credit-' + IntToStr(Seq) + '","type":"event","payload":{"seq":' + IntToStr(Seq) +
    ',"text":"' + Pad + '"}}';
End;

{ Plan item 4.2. Frames held past the log budget queue one protocol bye and request close. Further held frames
  do not queue another bye. }
Procedure TestCreditOverflowByeOnce;
Var
  Fresh: TMonitorSession;
  Pad, Json: String;
  Seq, Extra, Byes: Integer;
  Unacked, Held: Int64;
  Bytes: RawByteString;
  Frame: TMonitorFrame;
  Status: TMonitorFrameStatus;
  Message: TMonitorMessage;
  Bye: TMonitorBye;
  ErrorText: String;
Begin
  Fresh := TMonitorSession.Create;
  Try
    { Larger than an outbox chunk, so the window frames are not queued. Only the bye should appear. }
    Pad := StringOfChar('x', 200000);
    Seq := 1;
    Unacked := 0;
    Json := CreditEvent(Seq, Pad);
    While Unacked + Length(Json) <= MonitorCreditWindowBytes Do
      Begin
        Fresh.TryQueueHostJson(Json);
        Unacked := Unacked + Length(Json);
        Inc(Seq);
        Json := CreditEvent(Seq, Pad);
      End;
    Held := 0;
    While Held + Length(Json) <= MonitorLogBudgetBytes Do
      Begin
        Fresh.TryQueueHostJson(Json);
        Held := Held + Length(Json);
        Inc(Seq);
        Json := CreditEvent(Seq, Pad);
      End;
    Check('held frames under the budget do not close the link', Not Fresh.CloseRequested);
    Check('held frames under the budget queue no bye', Fresh.OutboundCount = 0);
    Check('the frame past the held budget is accepted', Fresh.TryQueueHostJson(Json));
    Check('credit overflow requests close', Fresh.CloseRequested);
    Check('credit overflow queues one frame', Fresh.OutboundCount = 1);
    For Extra := 1 To 3 Do
      Begin
        Inc(Seq);
        Check('a later held frame adds no bye', Fresh.TryQueueHostJson(CreditEvent(Seq, Pad)) And (Fresh.OutboundCount = 1));
      End;
    Byes := 0;
    While Fresh.TakeOutboundFrame(Bytes) Do
      If TryDecodeMonitorFrame(Bytes, Frame, Status) And TryDecodeMonitorEnvelope(Frame.Json, Message, ErrorText) And
        (Message.Kind = mmkBye) Then
        Begin
          Inc(Byes);
          Check('the credit bye reason is protocol', DecodeMonitorBye(Message.PayloadJson, Bye) And (Bye.Reason = 'protocol'));
        End;
    Check('credit overflow queues exactly one bye', Byes = 1);
  Finally
    Fresh.Free;
  End;
End;

Function PatchPayload(Const Epoch: String; Cursor: Int64; Const Body: String): String;
Var
  Patch: TMonitorPatch;
  Block: TAssistantMonitorBlock;
  Message: TMonitorMessage;
  ErrorText: String;
Begin
  Result := '';
  Patch := Default(TMonitorPatch);
  Patch.Epoch := Epoch;
  Patch.Cursor := Cursor;
  Patch.TurnIndex := 1;
  Patch.TurnId := 'turn-1';
  Patch.Phase := 'idle';
  Patch.CanSend := True;
  Patch.Part := 1;
  Patch.PartCount := 1;
  Block := Default(TAssistantMonitorBlock);
  Block.Kind := 'answer';
  Block.BlockId := 'block-1';
  Block.Body := Body;
  SetLength(Patch.Blocks, 1);
  Patch.Blocks[0] := Block;
  If Not TryDecodeMonitorEnvelope(EncodeMonitorPatch('patch', Patch), Message, ErrorText) Then
    Exit;
  Result := Message.PayloadJson;
End;

Procedure HandPatch(Const Epoch, Body: String; Out Cursor: Int64);
Var
  Json: String;
Begin
  Cursor := 0;
  Check('patch commit ' + Body, Session.CommitMirrorCursor(Body, Cursor));
  Session.NoteMirrorHanded(Cursor);
  Json := PatchPayload(Epoch, Cursor, Body);
  Check('patch payload ' + Body, Json <> '');
  Session.RememberHandedPatch(Cursor, Json);
End;

{ A real patch payload with one answer block of BodyBytes copies of Fill. The log replays only what decodes as a patch. }
Function LargePatchJson(Const Epoch: String; Cursor: Int64; Fill: Char; BodyBytes: Integer): String;
Begin
  Result := '{"epoch":"' + Epoch + '","cursor":' + IntToStr(Cursor) + ',"turn_index":1,"turn_id":"turn-1","part":1,' +
    '"part_count":1,"busy":false,"sending":false,"plan_running":false,"phase":"idle","can_send":true,"can_steer":false,' +
    '"can_stop":false,"elapsed_ms":0,"blocks":[{"kind":"answer","block_id":"block-1","title":"","tool_name":"",' +
    '"tool_id":"","body":"' + StringOfChar(Fill, BodyBytes) + '","running":false,"ok":true,"duration_ms":0}]}';
End;

Procedure TestResumeRing;
Var
  Catchup: TMonitorCatchup;
  Closed: TMonitorConversationClosed;
  Cursor: Int64;
  Index: Integer;
  Big: String;
Begin
  Session.BeginMirrorEpoch('Ab12Cd34', 'current', '/work/LazWorkflow', 'Current');
  { Since 6d0b0f2 'current' is not an identity. The unsaved chat has no conversation id. }
  Check('closed copy before patches', Session.CopyClosedMirror(Closed) And (Closed.Epoch = 'ab12cd34') And
    (Closed.Cursor = 0) And (Closed.ConversationId = '') And (Closed.Title = 'Current'));
  HandPatch('ab12cd34', 'one', Cursor);
  HandPatch('ab12cd34', 'two', Cursor);
  HandPatch('ab12cd34', 'three', Cursor);
  Check('ring replay from the middle', Session.TryResumeEvents('AB12CD34', 1, Catchup) And (Catchup.Mode = mcmEvents) And
    (Catchup.Cursor = 3) And (Length(Catchup.Patches) = 2) And (Catchup.Patches[0].Cursor = 2) And
    (Catchup.Patches[1].Cursor = 3) And (Catchup.Patches[0].Blocks[0].Body = 'two'));
  Check('caught up resume is empty events', Session.TryResumeEvents('ab12cd34', 3, Catchup) And (Catchup.Mode = mcmEvents) And
    (Length(Catchup.Patches) = 0) And (Catchup.Cursor = 3));
  Check('empty epoch is not this generation', Not Session.TryResumeEvents('', 0, Catchup));
  Check('other epoch is not events', Not Session.TryResumeEvents('eeff0011', 1, Catchup));
  Check('unknown cursor is not events', Not Session.TryResumeEvents('ab12cd34', 9, Catchup));
  Check('plan hole is not events', Session.CommitMirrorCursor('plan-row', Cursor) And (Cursor = 4));
  Session.NoteMirrorHanded(4);
  Check('cursor behind a plan hole snapshots', Not Session.TryResumeEvents('ab12cd34', 3, Catchup));
  Check('cursor on the plan hole can replay later patches', Session.MirrorCursor = 4);
  HandPatch('ab12cd34', 'after-plan', Cursor);
  Check('resume after the hole is events', Session.TryResumeEvents('ab12cd34', 4, Catchup) And (Length(Catchup.Patches) = 1) And
    (Catchup.Patches[0].Cursor = 5));
  Session.BeginMirrorEpoch('eeff0011', 'conversation-20261019T120000000', '/work/LazWorkflow', 'Archived');
  Check('new epoch drops the old ring', Not Session.TryResumeEvents('ab12cd34', 5, Catchup));
  Check('new epoch cursor is zero', Session.MirrorCursor = 0);
  Check('closed identity is the new epoch', Session.CopyClosedMirror(Closed) And (Closed.Epoch = 'eeff0011') And
    (Closed.ConversationId = 'conversation-20261019T120000000') And (Closed.Title = 'Archived') And (Closed.Cursor = 0));
  HandPatch('eeff0011', 'kept', Cursor);
  Big := LargePatchJson('eeff0011', 2, 'z', MonitorRingJsonCap + 1);
  Check('oversized commit', Session.CommitMirrorCursor('too-big', Cursor) And (Cursor = 2));
  Session.NoteMirrorHanded(2);
  Session.RememberHandedPatch(2, Big);
  Check('a patch under the log budget stays events', Session.TryResumeEvents('eeff0011', 1, Catchup) And
    (Length(Catchup.Patches) = 1) And (Catchup.Patches[0].Cursor = 2));
  Session.BeginMirrorEpoch('11223344', 'current', '/work/LazWorkflow', 'Cap');
  For Index := 1 To MonitorRingCapacity + 1 Do
    HandPatch('11223344', 'n' + IntToStr(Index), Cursor);
  Check('log budget keeps the small patches', Session.TryResumeEvents('11223344', 0, Catchup) And
    (Catchup.Mode = mcmEvents) And (Length(Catchup.Patches) = MonitorRingCapacity + 1) And
    (Catchup.Patches[0].Cursor = 1) And (Catchup.Patches[High(Catchup.Patches)].Cursor = MonitorRingCapacity + 1));
  Session.BeginMirrorEpoch('55667788', 'current', '/work/LazWorkflow', 'Bytes');
  HandPatch('55667788', 'small', Cursor);
  Big := LargePatchJson('55667788', 2, 'q', 1200000);
  Check('large patch is under the ring cap', (Length(Big) > 1000000) And (Length(Big) < MonitorRingJsonCap));
  Check('large commit', Session.CommitMirrorCursor('large-a', Cursor) And (Cursor = 2));
  Session.NoteMirrorHanded(2);
  Session.RememberHandedPatch(2, Big);
  Big := LargePatchJson('55667788', 3, 'r', 1200000);
  Check('second large commit', Session.CommitMirrorCursor('large-b', Cursor) And (Cursor = 3));
  Session.NoteMirrorHanded(3);
  Session.RememberHandedPatch(3, Big);
  Check('log budget keeps both large patches', Session.TryResumeEvents('55667788', 1, Catchup) And
    (Length(Catchup.Patches) = 2) And (Catchup.Patches[1].Cursor = 3) And
    (Length(Catchup.Patches[1].Blocks[0].Body) = 1200000));
  Check('snapshot cursor follows the committed tip', Session.CommitSnapshotCursor('picture', Cursor) And (Cursor = 4));
  Session.NoteMirrorHanded(4);
  Check('snapshot cursor is committed', Session.MirrorCursor = 4);
  Check('resume behind the snapshot is not events', Not Session.TryResumeEvents('55667788', 3, Catchup));
End;

Procedure TestResumeHostRules;
Var
  Catchup: TMonitorCatchup;
  Snapshot: TMonitorSnapshot;
  Cursor: Int64;
  Json: String;
  Message: TMonitorMessage;
  Decoded: TMonitorCatchup;
  ErrorText: String;
Begin
  Session.BeginMirrorEpoch('ab12cd34', 'current', '/work/LazWorkflow', 'Current');
  HandPatch('ab12cd34', 'kept', Cursor);
  Check('resume of a cursor still in the ring returns events', Session.TryResumeEvents('ab12cd34', 0, Catchup) And
    (Catchup.Mode = mcmEvents) And (Length(Catchup.Patches) = 1) And (Catchup.Cursor = 1));
  Check('resume of a cursor still in the ring does not call the form snapshot fill',
    Not ResumeNeedsFormSnapshot(Session, 'ab12cd34', 0));
  Check('oversized handed patch', Session.CommitMirrorCursor('too-big', Cursor) And (Cursor = 2));
  Session.NoteMirrorHanded(2);
  Session.RememberHandedPatch(2, LargePatchJson('ab12cd34', 2, 'z', MonitorRingJsonCap + 1));
  Check('a patch under the log budget does not need a form snapshot',
    Not ResumeNeedsFormSnapshot(Session, 'ab12cd34', 0));
  Check('a hole still needs one form snapshot', Session.CommitMirrorCursor('hole', Cursor) And (Cursor = 3));
  Session.NoteMirrorHanded(3);
  Check('resume behind the hole is not events', Not Session.TryResumeEvents('ab12cd34', 2, Catchup));
  Check('resume behind the hole needs one form snapshot', ResumeNeedsFormSnapshot(Session, 'ab12cd34', 2));
  Check('resume snapshot cursor', Session.CommitSnapshotCursor('picture', Cursor) And (Cursor = 4));
  Snapshot := Default(TMonitorSnapshot);
  Snapshot.PlanTitle := 'Monitor plan';
  Json := EncodeResumeSnapshot('resume-snap', Cursor, 'ab12cd34', 'current', '/work/LazWorkflow', 'Current', Snapshot);
  Check('resume of a discarded cursor returns one snapshot', TryDecodeMonitorEnvelope(Json, Message, ErrorText) And
    (Message.Kind = mmkCatchup) And DecodeMonitorCatchup(Message.PayloadJson, Decoded) And (Decoded.Mode = mcmSnapshot) And
    Decoded.HasSnapshot);
  Check('resume of a discarded cursor returns the snapshot cursor', Decoded.Cursor = Cursor);
End;

Procedure TestMirrorCursor;
Var
  Cursor: Int64;
Begin
  Session.BeginMirrorEpoch('ab12cd34', 'current', '/work/LazWorkflow', 'Current');
  Check('epoch stored', Session.MirrorEpoch = 'ab12cd34');
  Check('cursor starts at zero', Session.MirrorCursor = 0);
  Check('first commit', Session.CommitMirrorCursor('patch-a', Cursor) And (Cursor = 1));
  Check('unsent replace keeps cursor', Session.CommitMirrorCursor('patch-b', Cursor) And (Cursor = 1));
  Check('unsent is not handed', Session.MirrorCursor = 0);
  Session.NoteMirrorHanded(1);
  Check('handed cursor', Session.MirrorCursor = 1);
  Check('resend keeps cursor', Session.CommitMirrorCursor('patch-b', Cursor) And (Cursor = 1));
  Check('different bytes take the next cursor', Session.CommitMirrorCursor('patch-c', Cursor) And (Cursor = 2));
  Session.NoteMirrorHanded(2);
  Session.BeginMirrorEpoch('eeff0011', 'conversation-20261019T120000000', '/work/LazWorkflow', 'Archived');
  Check('new epoch resets cursor', (Session.MirrorEpoch = 'eeff0011') And (Session.MirrorCursor = 0));
  Check('new epoch does not reuse the old cursor', Session.CommitMirrorCursor('patch-c', Cursor) And (Cursor = 1));
End;

Procedure TestOldCatalogueRejects;
Begin
  Carrier.ClearSent;
  Carrier.DeliverJson('{"v":1,"id":"old","type":"ping","payload":{"ticks":1}}');
  ExpectRejected('old catalogue', 'protocol', True);
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
    Check('lifecycle send encodes', TryEncodeMonitorSend('send-live', 'hello', Json, ErrorJson));
    Carrier.DeliverJson(Json);
    Check('send stays live until the form reports sending', Session.State = mssLive);
    Check('send is answered queued once', QueuedOnce('send-live'));
    Check('send reached the bridge hook once', Sink.Calls = 1);
    Carrier.ClearSent;
    Check('pending steer encodes', TryEncodeMonitorSteer('steer-pending', 'not yet', Json, ErrorJson));
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
    Check('repeat send encodes', TryEncodeMonitorSend('send-live', 'again', Json, ErrorJson));
    Carrier.DeliverJson(Json);
    Check('repeated id does not reach the hook again', Sink.Calls = 0);
    Check('repeated id is command_state', DecodeLast(Message) And (Message.Kind = mmkCommandState) And
      (PayloadField(Message.PayloadJson, 'state') = 'done'));
    Carrier.ClearSent;
    Flags.Sending := True;
    Session.SetHostFlags(Flags);
    Check('blocked send encodes', TryEncodeMonitorSend('send-blocked', 'no', Json, ErrorJson));
    Carrier.DeliverJson(Json);
    Check('blocked send does not reach the hook', Sink.Calls = 0);
    Check('blocked send is an error', DecodeLast(Message) And (Message.Kind = mmkError) And
      DecodeMonitorError(Message.PayloadJson, ErrorBody) And (ErrorBody.Reason = 'host_busy'));
    Carrier.ClearSent;
    Carrier.DeliverJson('{"v":2,"id":"resume-states","type":"resume","payload":{"epoch":"","cursor":0,"commands":["send-blocked"]}}');
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
    Check('later send encodes', TryEncodeMonitorSend('send-wait', 'still here', Json, ErrorJson));
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
    Carrier.DeliverJson(EncodeMonitorPath(mmkSelectTarget, 'select-target', ''));
    Check('empty path select_target is accepted', (Sink.Calls = 1) And (Sink.Kind = Ord(mmkSelectTarget)));
    Check('empty path select_target is answered queued once', QueuedOnce('select-target'));
    Flags.Sending := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeMonitorPath(mmkSelectTarget, 'select-target-busy', '/work/Other'));
    Check('sending select_target is not queued', Sink.Calls = 0);
    Check('sending select_target error', DecodeLast(Message) And (Message.Kind = mmkError) And (Message.Reason = 'host_busy'));
    Check('sending select_target sentence', DecodeMonitorError(Message.PayloadJson, ErrorBody) And
      (ErrorBody.MessageText = 'Wait for the current reply to finish.'));
    Flags.Sending := False;
    Flags.PlanAgentRunning := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeMonitorPath(mmkSelectTarget, 'select-target-plan', '/work/Other'));
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
    Carrier.DeliverJson(EncodeMonitorSelectConversation('select-conversation', ''));
    Check('empty id select_conversation is accepted', (Sink.Calls = 1) And (Sink.Kind = Ord(mmkSelectConversation)));
    Check('empty id select_conversation is answered queued once', QueuedOnce('select-conversation'));
    Flags.PlanAgentRunning := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeMonitorSelectConversation('select-conversation-plan', '20261019T120000000'));
    Check('plan-running select_conversation is accepted', (Sink.Calls = 1) And (Sink.Kind = Ord(mmkSelectConversation)));
    Check('plan-running select_conversation is answered queued once', QueuedOnce('select-conversation-plan'));
    Flags.PlanAgentRunning := False;
    Flags.Sending := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeMonitorSelectConversation('select-conversation-busy', '20261019T120000000'));
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
    Carrier.DeliverJson(EncodeMonitorSetModel('set-model', 'grok-4'));
    Check('set_model is accepted', (Sink.Calls = 1) And (Sink.Kind = Ord(mmkSetModel)));
    Check('set_model is answered queued once', QueuedOnce('set-model'));
    Flags.PlanAgentRunning := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeMonitorSetModel('set-model-plan', 'grok-4'));
    Check('plan-running set_model is not queued', Sink.Calls = 0);
    Check('plan-running set_model is host_busy', DecodeLast(Message) And (Message.Kind = mmkError) And (Message.Reason = 'host_busy'));
    Check('plan-running set_model sentence', DecodeMonitorError(Message.PayloadJson, ErrorBody) And
      (ErrorBody.MessageText = 'Wait until the current work finishes before changing the model, effort, or permissions.'));
    Flags.PlanAgentRunning := False;
    Flags.Sending := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeMonitorSetModel('set-model-busy', 'grok-4'));
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
    Carrier.DeliverJson(EncodeMonitorSetReasoning('set-reasoning', ''));
    Check('empty set_reasoning is accepted', (Sink.Calls = 1) And (Sink.Kind = Ord(mmkSetReasoning)));
    Check('empty set_reasoning is answered queued once', QueuedOnce('set-reasoning'));
    Flags.PlanAgentRunning := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeMonitorSetReasoning('set-reasoning-plan', 'high'));
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
    Carrier.DeliverJson(EncodeMonitorSetReasoning('set-reasoning-busy', 'high'));
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
    Carrier.DeliverJson(EncodeMonitorSetPermissions('set-permissions', 'ask'));
    Check('set_permissions is accepted', (Sink.Calls = 1) And (Sink.Kind = Ord(mmkSetPermissions)));
    Check('set_permissions is not an approval decision', Sink.Kind <> Ord(mmkApprovalDecision));
    Check('set_permissions is answered queued once', QueuedOnce('set-permissions'));
    Flags.PlanAgentRunning := True;
    Session.SetHostFlags(Flags);
    Carrier.ClearSent;
    Sink.Calls := 0;
    Carrier.DeliverJson(EncodeMonitorSetPermissions('set-permissions-plan', 'auto'));
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
    Carrier.DeliverJson(EncodeMonitorSetPermissions('set-permissions-busy', 'always'));
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
  Carrier.DeliverJson('{"v":2,"id":"u1","type":"not_a_type","payload":{}}');
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
  Carrier.DeliverJson(EncodeMonitorTicks(mmkPing, 'ping-live', 42));
  Check('controller still live', Session.State = mssLive);
  Check('controller still answers ping', DecodeLast(Message) And (Message.Kind = mmkPong) And
    DecodeMonitorTicks(Message.PayloadJson, Ticks) And (Ticks.Ticks = 42));
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
    Carrier.DeliverJson(EncodeMonitorApprovalDecision('decide-off', 'tool-off', True));
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
    Carrier.DeliverJson(EncodeMonitorResume('resume-busy', '', 0));
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
  Check('revoke payload', DecodeMonitorBye(Message.PayloadJson, Bye) And (Bye.Reason = 'revoked'));
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
    Check('display approval payload', DecodeMonitorApprovalRequested(Message.PayloadJson, Notice));
    Check('display approval is not accepted', (Notice.ToolId = 'tool-desk') And (Not Notice.DecisionsAccepted));
    Check('display decision ignored', Not Session.ApplyApprovalDecision('tool-desk', True));
    Check('display decision leaves none', ReadAssistantApprovalDecision = aadNone);
    Session.CloseDisplayApproval('tool-desk');
    Check('still one display approval', CountSent('approval_requested') = 1);
    Check('display close frame', DecodeLast(Message) And (Message.Kind = mmkApprovalClosed));
    Check('display close desktop', DecodeMonitorApprovalClosed(Message.PayloadJson, Closed) And (Closed.Reason = 'desktop') And
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
    Check('bare signal is not allow', Not Session.BareApprovalSignalIsAllow);
    Check('bare signal leaves none', ReadAssistantApprovalDecision = aadNone);
    Check('no tool execution before cancel', Not Session.ToolExecutionRecorded);
    Session.NoteApprovalCancel('tool-stop');
    Check('cancel stores stopped', ReadAssistantApprovalDecision = aadStopped);
    Check('cancel records no tool execution', Not Session.ToolExecutionRecorded);
    Check('later allow does not replace stopped', ReadAssistantApprovalDecision = aadStopped);
    Session.ApplyApprovalDecision('tool-stop', True);
    Check('allow after cancel stays stopped', ReadAssistantApprovalDecision = aadStopped);
    Check('allow after cancel records no tool execution', Not Session.ToolExecutionRecorded);
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
  Carrier.DeliverJson(EncodeMonitorTicks(mmkPing, 'beat-start', 1));
  Carrier.ClearSent;
  Session.NoteTime(Start + MonitorHeartbeatMs - 1);
  Check('no ping before 10 s without sending', CountSent('ping') = 0);
  Session.NoteTime(Start + MonitorHeartbeatMs);
  Check('a ping after 10 s without sending', CountSent('ping') = 1);
  Session.NoteTime(Start + MonitorHeartbeatMs + 5000);
  Check('the ping restarts the quiet clock', CountSent('ping') = 1);
  Session.SendHostJson(EncodeMonitorTicks(mmkPong, 'beat-host-frame', 2));
  Session.NoteTime(Start + 2 * MonitorHeartbeatMs);
  Check('any sent frame restarts the quiet clock', CountSent('ping') = 1);
  Session.NoteTime(Start + 2 * MonitorHeartbeatMs + 5000);
  Check('a second ping after another quiet 10 s', CountSent('ping') = 2);
  Session.NoteTime(Start + MonitorDeadSessionMs - 1);
  Check('live just under 30 s without receiving', (Session.State = mssLive) And (Not Session.CloseRequested));
  Heard := Start + MonitorDeadSessionMs - 1;
  Carrier.DeliverJson(EncodeMonitorTicks(mmkPing, 'beat-heard', 3));
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
  Carrier.DeliverJson(EncodeMonitorAuth('auth-beat', SavedClientId, MonitorAuthMac(SavedToken, Nonce)));
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
      Carrier := TMonitorMemoryCarrier.Create;
      CarrierRef := Carrier;
      Session := TMonitorSession.Create;
      Session.AttachCarrier(CarrierRef);
      Session.SetHostFingerprint('ab12cd34');
      Session.NoteTime(5000);
      Check('listen starts', Session.StartListening('10.1.2.3', 56123, ErrorText));
      If ErrorText <> '' Then
        WriteLn(ErrorText);
      Check('listen state', Session.State = mssListening);
      TestOpenLanAdmitsWithoutCode;
      TestCodeAbsentUntilRequested;
      TestSecondControllerWhileAccepted;
      TestCommandBeforeAuth;
      TestThreeFailuresDiscard;
      TestPairAfterDiscard;
      TestPairSuccess;
      TestHmac;
      TestReconnectKeepsRunningTurn;
      TestIdleSteerSubmits;
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
      TestMirrorCursor;
      TestResumeRing;
      TestResumeHostRules;
      TestOutboundLanes;
      TestPlanFrameBeforeBulk;
      TestLivePatchReplaces;
      TestEncodeFailureNotQueued;
      {$IFDEF MONITOR_COUNT_PARSES}
      TestStateFrameParsesOnce;
      {$ENDIF}
      TestCreditOverflowByeOnce;
      TestOldCatalogueRejects;
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
