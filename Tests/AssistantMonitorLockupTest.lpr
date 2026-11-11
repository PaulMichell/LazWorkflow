Program AssistantMonitorLockupTest;

{ Host recovery after a refused bulk frame and a main-thread publish stall
  (c) 2026 Michell Computing.

  A bulk frame the outbox cannot hold is not a stuck host. The phone is told to
  ask again, frames already queued are still delivered, and another small frame
  can be queued afterwards. That is the recovery, not a pinned fault.

  A publish burst on this thread stands in for a compilation or tool stall. Time
  notes, which the link worker sends through NoteTime, keep running. They do not
  wait on a UI timer, and they are not blocked by state publication. Heartbeat
  and dead-session limits stay 10 seconds and 30 seconds. Raising them is not
  the fix.

  A finished remote approval wait disarms its event before it is destroyed. Run
  this binary under -gh or valgrind to confirm a later cancel or decision touches
  no freed block.

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
  AssistantMonitorCarrier, AssistantMonitorSession, AssistantSessionObserve, AssistantMonitorApproval, AssistantConfig;

Const
  ApprovalToolId = 'tool-after-wait';

Type
  { Stands in for the link worker. NoteTime is what RunLink calls, not a UI timer. }
  TTimeNote = Class(TThread)
  Public
    Session: TMonitorSession;
    Procedure Execute; Override;
  End;

  { Runs one remote approval wait off the main thread, as a tool call does. }
  TApprovalWaiter = Class(TThread)
  Protected
    Procedure Execute; Override;
  Public
    StopNow: Boolean;
    Allowed: Boolean;
    Handled: Boolean;
    ErrorText: String;
    Function Aborting: Boolean;
  End;

Var
  FailCount: Integer;
  TimeNotes: Integer;
  Carrier: TMonitorMemoryCarrier;
  CarrierRef: IMonitorCarrier;
  Session: TMonitorSession;

Procedure TTimeNote.Execute;
Begin
  While Not Terminated Do
    Begin
      Session.NoteTime(GetTickCount64);
      InterlockedIncrement(TimeNotes);
    End;
End;

Function TApprovalWaiter.Aborting: Boolean;
Begin
  Result := StopNow;
End;

Procedure TApprovalWaiter.Execute;
Begin
  Allowed := AssistantMonitorApprovalWait('write_file', ApprovalToolId, '{"path":"Notes.md"}', @Aborting, ErrorText,
    Handled);
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

Function BulkFrame(Index: Integer): String;
Begin
  Result := '{"v":3,"id":"bulk-' + IntToStr(Index) + '","type":"chunk","payload":{}}';
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
  Huge := '{"v":3,"id":"huge-1","type":"snapshot_page","payload":{"body":"' + StringOfChar('x', 40000) + '"}}';
  Before := Session.FramesDropped;
  Check('a frame the outbox cannot hold is refused', Not Session.TryQueueHostJson(Huge));
  Check('a refused bulk frame is not counted as sent', Session.FramesDropped = Before);
  Session.DrainOutbound;
  Check('the queued bulk frames still reach the carrier', CountSentKind(mmkChunk) = 2);
  Check('the refused page is not sent', CountSentKind(mmkSnapshotPage) = 0);
  Check('the phone is told to ask again', CountSentKind(mmkError) = 1);
  Check('the refusal is overloaded', OverloadedSent);
  Check('the session can queue again after the refusal', Session.TryQueueHostJson(BulkFrame(3)));
  Session.DrainOutbound;
  Check('the later bulk frame is delivered', CountSentKind(mmkChunk) = 3);
End;

{ A publish burst must not stall the link worker's time notes, and must not be
  papered over by a longer heartbeat. }
Procedure TestPublishStallDoesNotBlockTimeNotes;
Var
  Worker: TTimeNote;
  Started: QWord;
  Seen: Integer;
Begin
  Check('heartbeat silence stays 10 seconds', MonitorHeartbeatMs = 10000);
  Check('dead session stays 30 seconds', MonitorDeadSessionMs = 30000);
  TimeNotes := 0;
  Worker := TTimeNote.Create(True);
  Worker.Session := Session;
  Worker.Start;
  Try
    Started := GetTickCount64;
    Seen := 0;
    While GetTickCount64 - Started < 200 Do
      Begin
        Session.PublishState('status', '{"busy":true,"sending":true}', True);
        If TimeNotes > Seen Then
          Seen := TimeNotes;
      End;
    Check('time notes ran during the publish stall', Seen > 0);
  Finally
    Worker.Terminate;
    Worker.WaitFor;
    Worker.Free;
  End;
End;



{ Plan item 3.1. Disarm clears only the event it is given, so a newer waiter keeps its own. }
Procedure TestDisarmKeepsNewerEvent;
Var
  Older, Newer: PRTLEvent;
Begin
  Older := RTLEventCreate;
  Newer := RTLEventCreate;
  Try
    ArmAssistantApprovalWait(Older);
    ArmAssistantApprovalWait(Newer);
    DisarmAssistantApprovalWait(Older);
    Check('disarming an older event keeps the newer one armed', AssistantApprovalWaitArmed);
    DisarmAssistantApprovalWait(Newer);
    Check('disarming the stored event clears it', Not AssistantApprovalWaitArmed);
    SignalAssistantApprovalWait;
    Check('a signal with nothing armed is harmless', Not AssistantApprovalWaitArmed);
  Finally
    DisarmAssistantApprovalWait(Newer);
    DisarmAssistantApprovalWait(Older);
    RTLEventDestroy(Newer);
    RTLEventDestroy(Older);
  End;
End;

{ Plan item 3.1. One approval wait runs on a worker thread and ends, then the session cancels and decides on that
  tool. Before the fix both calls set the waiter's destroyed event. The wait ends through the abort callback after
  one slice. The two-minute timeout leaves by the same Finally, and a unit test must not wait two minutes. }
Procedure TestApprovalWaitDisarms;
Var
  Waiter: TApprovalWaiter;
Begin
  AssistantChatConfig.ApprovalMode := 'ask';
  ApplyMonitorRemoteApproval(True);
  Session.SetRemoteApproval(True);
  Waiter := TApprovalWaiter.Create(True);
  Try
    Waiter.StopNow := True;
    Waiter.Start;
    Waiter.WaitFor;
    { The waiter queued its approval notices for the main thread. No listener is set, so this only empties the queue. }
    CheckSynchronize(0);
    Check('the approval wait ran off the main thread', Waiter.Handled);
    Check('a stopped wait does not allow the tool', Not Waiter.Allowed);
    Check('a finished wait leaves no event armed', Not AssistantApprovalWaitArmed);
    Session.NoteApprovalCancel(ApprovalToolId);
    Session.ApplyApprovalDecision(ApprovalToolId, True);
    SignalAssistantApprovalWait;
    Check('a cancel and a decision after the wait arm nothing', Not AssistantApprovalWaitArmed);
  Finally
    Waiter.Free;
    ApplyMonitorRemoteApproval(False);
    Session.SetRemoteApproval(False);
  End;
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
      TestPublishStallDoesNotBlockTimeNotes;
      TestDisarmKeepsNewerEvent;
      TestApprovalWaitDisarms;
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
  { Do not Halt on success. Halt skips this block's temporary finalization, and heaptrc then reports those strings as leaks. }
  If FailCount = 0 Then
    WriteLn('All AssistantMonitorLockupTest tests passed.')
  Else
    Begin
      WriteLn(FailCount, ' AssistantMonitorLockupTest test(s) failed.');
      Halt(1);
    End;
End.
