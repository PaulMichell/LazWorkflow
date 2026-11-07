Program AssistantMonitorOutboxTest;

{ Checks for the prioritised monitor outbox (c) 2026 Michell Computing.

  Plan item 4.2 of Documents/Plan-20261029-035918.md. Lane order, a control frame
  between two bulk chunks, state coalescing, log frames held until acknowledged,
  byte budgets, ring growth and wrap, and the wake callback. No sockets, no LCL.
  The runner writes this binary with a temporary -FU and -FE, never under Source/. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils, AssistantMonitorOutbox;

Type
  TWakeCounter = Class
    Count: Integer;
    Procedure Wake;
  End;

  TChunkArray = Array Of RawByteString;

Var
  FailCount: Integer;

Procedure TWakeCounter.Wake;
Begin
  Inc(Count);
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

{ A frame of exactly Size bytes that starts with Tag. }
Function Sized(Const Tag: String; Size: Integer): RawByteString;
Begin
  Result := Tag + StringOfChar('.', Size - Length(Tag));
End;

Function Chunks(Const Tag: String; Count, Size: Integer): TChunkArray;
Var
  Index: Integer;
Begin
  Result := Nil;
  SetLength(Result, Count);
  For Index := 0 To Count - 1 Do
    Result[Index] := Sized(Tag + IntToStr(Index) + '|', Size);
End;

{ Tags end in '|' so that 'log1|' is never a prefix of 'log10|'. }
Function NextIs(Outbox: TMonitorOutbox; Const Tag: String; Expected: TMonitorOutboxLane): Boolean;
Var
  Frame: RawByteString;
  Lane: TMonitorOutboxLane;
Begin
  Result := Outbox.Take(Frame, Lane) And (Copy(Frame, 1, Length(Tag)) = Tag) And (Lane = Expected);
  If Not Result Then
    WriteLn('detail expected ', Tag, ' got ', Copy(Frame, 1, 24), ' lane ', Ord(Lane));
End;

Function Drain(Outbox: TMonitorOutbox): Integer;
Var
  Frame: RawByteString;
  Lane: TMonitorOutboxLane;
Begin
  Result := 0;
  While Outbox.Take(Frame, Lane) Do
    Inc(Result);
End;

Procedure TestBarrierReadiness;
Var
  Outbox: TMonitorOutbox;
Begin
  Outbox := TMonitorOutbox.Create;
  Try
    Outbox.AddGeneratedBulk('page|', 7);
    Outbox.HoldBarrier('end|', 7);
    Check('blocked barrier is not counted as sendable', Outbox.HasFrame And (Outbox.PendingFrameCount = 1));
    Check('generation page goes first', NextIs(Outbox, 'page|', molBulk));
    Check('released barrier is pending', Outbox.HasFrame And (Outbox.PendingFrameCount = 1));
    Check('released barrier goes next', NextIs(Outbox, 'end|', molControl));
    Check('barrier drain leaves no pending frame', Not Outbox.HasFrame And (Outbox.PendingFrameCount = 0));
  Finally
    Outbox.Free;
  End;
End;

Procedure TestLaneOrder;
Var
  Outbox: TMonitorOutbox;
  Frame: RawByteString;
  Lane: TMonitorOutboxLane;
Begin
  Outbox := TMonitorOutbox.Create;
  Try
    Check('new outbox has no pending frame', Not Outbox.HasFrame And (Outbox.PendingFrameCount = 0));
    Check('bulk accepts an item', Outbox.AddBulk(['bulk1|', 'bulk2|']));
    Check('log accepts two events', Outbox.AppendLog(1, 'log1|') And Outbox.AppendLog(2, 'log2|'));
    Check('state accepts a value', Outbox.PutState('status', 'state1|'));
    Check('control accepts a pong', Outbox.AddControl('pong1|'));
    Check('pending count covers all four lanes', Outbox.HasFrame And (Outbox.PendingFrameCount = 6));
    Check('control is taken first', NextIs(Outbox, 'pong1|', molControl));
    Check('state is taken second', NextIs(Outbox, 'state1|', molState));
    Check('log is taken third, in order', NextIs(Outbox, 'log1|', molLog) And NextIs(Outbox, 'log2|', molLog));
    Check('bulk is taken last, in order', NextIs(Outbox, 'bulk1|', molBulk) And NextIs(Outbox, 'bulk2|', molBulk));
    Check('the outbox is then empty', Not Outbox.Take(Frame, Lane));
  Finally
    Outbox.Free;
  End;
End;

Procedure TestControlBetweenChunks;
Var
  Outbox: TMonitorOutbox;
Begin
  Outbox := TMonitorOutbox.Create;
  Try
    Check('a three-chunk bulk item is accepted', Outbox.AddBulk(Chunks('big', 3, MonitorOutboxChunkBytes)));
    Check('the first chunk goes out', NextIs(Outbox, 'big0|', molBulk));
    Check('a pong is queued mid-item', Outbox.AddControl('pong|'));
    Check('the pong goes out at the next chunk boundary', NextIs(Outbox, 'pong|', molControl));
    Check('the item then continues', NextIs(Outbox, 'big1|', molBulk) And NextIs(Outbox, 'big2|', molBulk));
  Finally
    Outbox.Free;
  End;
End;

Procedure TestStateCoalesces;
Var
  Outbox: TMonitorOutbox;
Begin
  Outbox := TMonitorOutbox.Create;
  Try
    Outbox.PutState('status', 'status-old|');
    Outbox.PutState('plan', 'plan|');
    Outbox.PutState('status', 'status-new|');
    Check('one entry per key', Outbox.LaneCount(molState) = 2);
    Check('the latest value keeps its place', NextIs(Outbox, 'status-new|', molState));
    Check('the other key follows', NextIs(Outbox, 'plan|', molState));
    Check('state bytes are released', Outbox.PendingBytes = 0);
  Finally
    Outbox.Free;
  End;
End;

Procedure TestLogHeldUntilAcknowledged;
Var
  Outbox: TMonitorOutbox;
  Frame: RawByteString;
  Lane: TMonitorOutboxLane;
Begin
  Outbox := TMonitorOutbox.Create;
  Try
    Outbox.AppendLog(1, 'log1|');
    Outbox.AppendLog(2, 'log2|');
    Outbox.AppendLog(3, 'log3|');
    Check('three log frames go out', Drain(Outbox) = 3);
    Check('all three are held', (Outbox.HeldLogCount = 3) And (Outbox.LaneCount(molLog) = 3));
    Check('held log frames are not pending', Not Outbox.HasFrame And (Outbox.PendingFrameCount = 0));
    Check('held frames are not offered twice', Not Outbox.Take(Frame, Lane));
    Outbox.Acknowledge(2);
    Check('an acknowledgement releases up to its sequence', (Outbox.HeldLogCount = 1) And (Outbox.LaneCount(molLog) = 1));
    Outbox.RewindLog;
    Check('rewound log frame is pending', Outbox.HasFrame And (Outbox.PendingFrameCount = 1));
    Check('a rewind offers the unacknowledged frame again', NextIs(Outbox, 'log3|', molLog));
    Check('a falling sequence is refused', Not Outbox.AppendLog(2, 'late|'));
    Check('a second chunk of the same event is accepted', Outbox.AppendLog(3, 'log3-part2|'));
    Outbox.Acknowledge(3);
    Check('acknowledging the event releases every chunk', (Outbox.LaneCount(molLog) = 0) And (Outbox.HeldLogCount = 0));
    Check('log bytes are released', Outbox.PendingBytes = 0);
  Finally
    Outbox.Free;
  End;
End;

Procedure TestBulkBudget;
Var
  Outbox: TMonitorOutbox;
  Large, Small, Oversize: TChunkArray;
Begin
  Outbox := TMonitorOutbox.Create;
  Try
    Large := Chunks('large', 120, MonitorOutboxChunkBytes);
    Small := Chunks('small', 16, MonitorOutboxChunkBytes);
    Oversize := Chunks('over', 129, MonitorOutboxChunkBytes);
    Check('a 3.75 MiB item fits the budget', Outbox.AddBulk(Large));
    Check('a further 0.5 MiB is refused', Not Outbox.AddBulk(Small));
    Check('the refused item left nothing behind', Outbox.LaneCount(molBulk) = 120);
    Check('control is still accepted over a full bulk lane', Outbox.AddControl('pong|'));
    Check('everything queued drains', Drain(Outbox) = 121);
    Check('the drained lane accepts the item', Outbox.AddBulk(Small));
    Drain(Outbox);
    Check('an empty lane accepts an item over the budget', Outbox.AddBulk(Oversize));
    Check('that item drains whole', Drain(Outbox) = 129);
    Check('no bytes are left counted', Outbox.PendingBytes = 0);
  Finally
    Outbox.Free;
  End;
End;

Procedure TestFrameLimits;
Var
  Outbox: TMonitorOutbox;
Begin
  Outbox := TMonitorOutbox.Create;
  Try
    Check('an empty frame is refused', Not Outbox.AddControl(''));
    Check('a frame over one chunk is refused', Not Outbox.AddControl(Sized('x', MonitorOutboxChunkBytes + 1)));
    Check('a frame of exactly one chunk is accepted', Outbox.AddControl(Sized('x', MonitorOutboxChunkBytes)));
    Check('a state value needs a key', Not Outbox.PutState('', 'value|'));
    Check('a log sequence must be positive', Not Outbox.AppendLog(0, 'log|'));
    Check('an empty bulk item is refused', Not Outbox.AddBulk([]));
    Check('a bulk item with an oversize chunk is refused whole',
      Not Outbox.AddBulk(['fine|', Sized('x', MonitorOutboxChunkBytes + 1)]) And (Outbox.LaneCount(molBulk) = 0));
  Finally
    Outbox.Free;
  End;
End;

Procedure TestLogOverflow;
Var
  Outbox: TMonitorOutbox;
  Index: Integer;
  Accepted: Boolean;
Begin
  Outbox := TMonitorOutbox.Create;
  Try
    Accepted := True;
    For Index := 1 To (MonitorOutboxLogBudget Div MonitorOutboxChunkBytes) + 1 Do
      Accepted := Outbox.AppendLog(Index, Sized('log|', MonitorOutboxChunkBytes)) And Accepted;
    Check('the log never refuses an event for size', Accepted);
    Check('past its budget the log reports overflow', Outbox.LogOverflowed);
    Outbox.Clear;
    Check('a cleared outbox is empty and no longer overflowed', (Not Outbox.LogOverflowed) And (Outbox.PendingBytes = 0));
    Check('a cleared log starts its sequence again', Outbox.AppendLog(1, 'log1|'));
  Finally
    Outbox.Free;
  End;
End;

Procedure TestRingGrowthAndWrap;
Var
  Outbox: TMonitorOutbox;
  Index: Integer;
  InOrder: Boolean;
Begin
  Outbox := TMonitorOutbox.Create;
  Try
    For Index := 1 To 10 Do
      Outbox.AddControl('c' + IntToStr(Index) + '|');
    InOrder := True;
    For Index := 1 To 5 Do
      InOrder := NextIs(Outbox, 'c' + IntToStr(Index) + '|', molControl) And InOrder;
    For Index := 11 To 1000 Do
      Outbox.AddControl('c' + IntToStr(Index) + '|');
    For Index := 6 To 1000 Do
      InOrder := NextIs(Outbox, 'c' + IntToStr(Index) + '|', molControl) And InOrder;
    Check('a wrapped ring grows and keeps its order', InOrder);
    Check('the grown ring is empty after draining', Outbox.LaneCount(molControl) = 0);
  Finally
    Outbox.Free;
  End;
End;

Procedure TestWake;
Var
  Outbox: TMonitorOutbox;
  Counter: TWakeCounter;
Begin
  Outbox := TMonitorOutbox.Create;
  Counter := TWakeCounter.Create;
  Try
    Counter.Count := 0;
    Outbox.OnWake := @Counter.Wake;
    Outbox.AddControl('pong|');
    Outbox.PutState('status', 'status|');
    Outbox.AppendLog(1, 'log1|');
    Check('each accepted control, state and log add wakes the writer', Counter.Count = 3);
    { Since 901717e bulk is queued as a burst and woken once by Notify, so a ping is read before the first bulk
      write (AssistantMonitorLinkTest 4.2). }
    Outbox.AddBulk(['bulk|']);
    Check('a bulk add does not wake the writer', Counter.Count = 3);
    Outbox.Notify;
    Check('notify wakes the writer once', Counter.Count = 4);
    Outbox.AddControl('');
    Outbox.AppendLog(1, '');
    Check('a refused add does not wake the writer', Counter.Count = 4);
    Outbox.OnWake := Nil;
  Finally
    Counter.Free;
    Outbox.Free;
  End;
End;

Begin
  FailCount := 0;
  Try
    TestBarrierReadiness;
    TestLaneOrder;
    TestControlBetweenChunks;
    TestStateCoalesces;
    TestLogHeldUntilAcknowledged;
    TestBulkBudget;
    TestFrameLimits;
    TestLogOverflow;
    TestRingGrowthAndWrap;
    TestWake;
  Except
    On E: Exception Do
      Begin
        WriteLn('FAIL exception ', E.Message);
        Inc(FailCount);
      End;
  End;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantMonitorOutboxTest tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantMonitorOutboxTest test(s) failed.');
      Halt(1);
    End;
End.
