Program AssistantMonitorLockupTest;

{ Host halves of the phone lock-up (c) 2026 Michell Computing.

  Plan item 2.2 of Documents/Plan-20261029-035918.md. These checks pin the current
  faults and pass on today's code. Item 3.2 changes this behaviour; these checks
  then fail and are rewritten to assert the fix.

  - A bulk frame the outbox cannot hold is refused. The phone gets a retryable
    overloaded error. It is not counted in FramesDropped.
  - A catchup snapshot that is still over the frame cap after every compaction
    level encodes to nothing. TAssistantMonitorBridge.SendCatchupSnapshot then logs
    a warning and sends nothing at all. That method is private and needs the IDE
    form, so this test makes the same session and codec calls in the same order.

  No sockets and no Interfaces unit. The runner writes this binary with a
  temporary -FU and -FE, never under Source/. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, AssistantMonitorLinkStubs, AssistantMonitorCodec, AssistantMonitorFrames,
  AssistantMonitorCarrier, AssistantMonitorSession, AssistantSessionObserve;

Const
  { SendCatchupSnapshot tries compaction levels 0 to 6. }
  BridgeCompactionLevels = 7;

Var
  FailCount: Integer;
  Carrier: TMonitorMemoryCarrier;
  CarrierRef: IMonitorCarrier;
  Session: TMonitorSession;

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

Function BulkFrame(Index: Integer): String;
Begin
  Result := '{"v":2,"id":"bulk-' + IntToStr(Index) + '","type":"snapshot","payload":{}}';
End;

Function CountSentKind(Kind: TMonitorMessageKind): Integer;
Var
  Index: Integer;
  Message: TMonitorMessage;
  ErrorText: String;
Begin
  Result := 0;
  For Index := 0 To Carrier.SentCount - 1 Do
    If TryDecodeMonitorEnvelope(Carrier.SentJson(Index), Message, ErrorText) And (Message.Kind = Kind) Then
      Inc(Result);
End;

Function SmallSnapshot: TMonitorSnapshot;
Begin
  Result := Default(TMonitorSnapshot);
  Result.View.Available := True;
  Result.View.SignedIn := True;
  Result.View.Busy := True;
  Result.View.Sending := True;
  Result.View.Mode := 'build';
End;

Function OverloadedSent: Boolean;
Var
  Index: Integer;
  Message: TMonitorMessage;
  Body: TMonitorErrorBody;
  ErrorText: String;
Begin
  Result := False;
  For Index := 0 To Carrier.SentCount - 1 Do
    If TryDecodeMonitorEnvelope(Carrier.SentJson(Index), Message, ErrorText) And (Message.Kind = mmkError) And
      DecodeMonitorError(Message.PayloadJson, Body) And (Body.Reason = 'overloaded') Then
      Exit(True);
End;

Procedure TestCatchupRefusedIsAnError;
Var
  Index, Queued, Before: Integer;
  Huge: String;
Begin
  Session.DrainOutbound;
  Carrier.ClearSent;
  Queued := 0;
  For Index := 1 To 2 Do
    If Session.TryQueueHostJson(BulkFrame(Index)) Then
      Inc(Queued);
  Check('small bulk frames are queued', Queued = 2);
  Huge := '{"v":2,"id":"huge-1","type":"snapshot_page","payload":{"body":"' + StringOfChar('x', 40000) + '"}}';
  Before := Session.FramesDropped;
  Check('a frame the outbox cannot hold is refused', Not Session.TryQueueHostJson(Huge));
  Check('a refused bulk frame is not counted as sent', Session.FramesDropped = Before);
  Session.DrainOutbound;
  Check('the queued bulk frames still reach the carrier', CountSentKind(mmkSnapshot) = 2);
  Check('the refused page is not sent', CountSentKind(mmkSnapshotPage) = 0);
  Check('the phone is told to ask again', CountSentKind(mmkError) = 1);
  Check('the refusal is overloaded', OverloadedSent);
End;

Procedure TestCatchupThatDoesNotFit;
Var
  Snapshot: TMonitorSnapshot;
  Epoch, ConversationId, ProjectRoot, Title, Json: String;
  Cursor: Int64;
  Level, Encoded: Integer;
Begin
  Session.DrainOutbound;
  Carrier.ClearSent;
  Session.CopyMirrorIdentity(Epoch, ConversationId, ProjectRoot, Title, Cursor);
  Snapshot := SmallSnapshot;
  Json := EncodeResumeSnapshot('resume-2', 1, Epoch, ConversationId, ProjectRoot, Title, Snapshot);
  Check('a small catchup fits', Json <> '');
  { CompactCatchupSnapshot only shortens Live, StoredTurns, PlanRows and TaskRows. They are already empty here, so
    every level of the bridge loop encodes this same snapshot. No level shortens View.ContextText. }
  Snapshot.View.ContextText := StringOfChar('c', MonitorMaxPayloadBytes);
  Encoded := 0;
  Json := '';
  For Level := 0 To BridgeCompactionLevels - 1 Do
    Begin
      Check('the snapshot cursor is reserved at level ' + IntToStr(Level),
        Session.CommitSnapshotCursor('lockup-level-' + IntToStr(Level), Cursor));
      Json := EncodeResumeSnapshot('resume-2', Cursor, Epoch, ConversationId, ProjectRoot, Title, Snapshot);
      If Json <> '' Then
        Begin
          Inc(Encoded);
          Break;
        End;
    End;
  Check('an oversized catchup encodes at no compaction level', Encoded = 0);
  { The bridge's next step: send only when a level fitted. Otherwise log and exit. }
  If Json <> '' Then
    Session.SendHostJson(Json);
  Session.DrainOutbound;
  Check('nothing is sent for that resume', Carrier.SentCount = 0);
  Check('no error tells the phone the snapshot was too large', CountSentKind(mmkError) = 0);
End;

Begin
  FailCount := 0;
  Carrier := TMonitorMemoryCarrier.Create;
  CarrierRef := Carrier;
  Session := TMonitorSession.Create;
  Try
    Try
      Session.AttachCarrier(CarrierRef);
      Session.BeginMirrorEpoch(MintMonitorEpoch, 'lockup', '/work', 'Lockup');
      TestCatchupRefusedIsAnError;
      TestCatchupThatDoesNotFit;
    Except
      On E: Exception Do
        Begin
          WriteLn('FAIL exception ', E.Message);
          Inc(FailCount);
        End;
    End;
  Finally
    Session.Free;
    CarrierRef := Nil;
    Carrier := Nil;
  End;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantMonitorLockupTest tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantMonitorLockupTest test(s) failed.');
      Halt(1);
    End;
End.
