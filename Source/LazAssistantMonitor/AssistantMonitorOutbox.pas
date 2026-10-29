Unit AssistantMonitorOutbox;

{ Prioritised, byte-budgeted outbox for one monitor link (c) 2026 Michell Computing.

  Four lanes, taken in this order: control (pong, ack, approval, error), state
  (latest value per key), log (sequenced events kept until the phone acknowledges
  them) and bulk (images, turn fetches, snapshot pages). Each entry is one frame of
  at most MonitorOutboxChunkBytes. The caller splits a larger item into chunk
  frames, so the writer can change lane at every chunk boundary and control waits
  for at most one chunk. Budgets count bytes. Bulk refuses an item that would pass
  its budget, except into an empty lane. The log never drops an event: past its
  budget it reports LogOverflowed, and the link closes so the phone resumes from
  the log. Each lane is a ring buffer.

  Thread safe. Producers call the add methods from any thread, and the link thread
  calls Take. OnWake runs after a successful add, outside the lock.
  No socket, TLS, or JSON code in this unit. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Const
  MonitorOutboxChunkBytes = 32 * 1024;
  MonitorOutboxBulkBudget = 4 * 1024 * 1024;
  MonitorOutboxLogBudget = 8 * 1024 * 1024;

Type
  TMonitorOutboxLane = (molControl, molState, molLog, molBulk);

  TMonitorOutboxWake = Procedure Of Object;

  TMonitorOutboxEntry = Record
    Bytes: RawByteString;
    Key: String;
    Seq: Int64;
  End;

  TMonitorOutboxEntryArray = Array Of TMonitorOutboxEntry;

  { Growable FIFO ring. Not thread safe. The outbox lock guards it. }
  TMonitorOutboxRing = Class
  Private
    Items: TMonitorOutboxEntryArray;
    Head: Integer;
    Used: Integer;
    Procedure Grow;
    Function Slot(Index: Integer): Integer;
  Public
    Constructor Create;
    Procedure Push(Const Entry: TMonitorOutboxEntry);
    { Index 0 is the oldest entry. }
    Function Peek(Index: Integer): TMonitorOutboxEntry;
    Procedure Replace(Index: Integer; Const Entry: TMonitorOutboxEntry);
    Function Pop(Out Entry: TMonitorOutboxEntry): Boolean;
    Procedure Clear;
    Function Count: Integer;
  End;

  TMonitorOutbox = Class
  Private
    OutboxLock: TRTLCriticalSection;
    Rings: Array[TMonitorOutboxLane] Of TMonitorOutboxRing;
    LaneBytes: Array[TMonitorOutboxLane] Of Int64;
    { The first LogSent log entries were taken and wait for an acknowledgement. }
    LogSent: Integer;
    LastLogSeq: Int64;
    FLogOverflowed: Boolean;
    FOnWake: TMonitorOutboxWake;
    Function GetLogOverflowed: Boolean;
    Function GetOnWake: TMonitorOutboxWake;
    Procedure SetOnWake(Handler: TMonitorOutboxWake);
    Procedure Wake;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    { False when the frame is empty or larger than one chunk. }
    Function AddControl(Const Frame: RawByteString): Boolean;
    { Replaces an unsent entry with the same key in its place. A new key queues at the back. }
    Function PutState(Const Key: String; Const Frame: RawByteString): Boolean;
    { Seq must not fall. The chunks of one event share its Seq. Never refused for size. }
    Function AppendLog(Seq: Int64; Const Frame: RawByteString): Boolean;
    { Every chunk of one item, or none. False when the lane would pass its budget. }
    Function AddBulk(Const Chunks: Array Of RawByteString): Boolean;
    { Next frame by lane priority. A log frame stays held until Acknowledge. }
    Function Take(Out Frame: RawByteString; Out Lane: TMonitorOutboxLane): Boolean;
    { Releases every log entry with Seq <= UpTo, taken or not. }
    Procedure Acknowledge(UpTo: Int64);
    { Offers every held log entry again from the oldest. }
    Procedure RewindLog;
    Procedure Clear;
    Function PendingBytes: Int64;
    Function LaneCount(Lane: TMonitorOutboxLane): Integer;
    Function HeldLogCount: Integer;
    Property LogOverflowed: Boolean Read GetLogOverflowed;
    Property OnWake: TMonitorOutboxWake Read GetOnWake Write SetOnWake;
  End;

Implementation

Const
  MonitorOutboxRingStart = 16;

Function FrameFits(Const Frame: RawByteString): Boolean;
Begin
  Result := (Frame <> '') And (Length(Frame) <= MonitorOutboxChunkBytes);
End;

Function NewEntry(Const Frame: RawByteString; Const Key: String; Seq: Int64): TMonitorOutboxEntry;
Begin
  Result := Default(TMonitorOutboxEntry);
  Result.Bytes := Frame;
  Result.Key := Key;
  Result.Seq := Seq;
End;

{ TMonitorOutboxRing }

Constructor TMonitorOutboxRing.Create;
Begin
  Inherited Create;
  Items := Nil;
  SetLength(Items, MonitorOutboxRingStart);
  Head := 0;
  Used := 0;
End;

Procedure TMonitorOutboxRing.Grow;
Var
  Grown: TMonitorOutboxEntryArray;
  Index: Integer;
Begin
  Grown := Nil;
  SetLength(Grown, Length(Items) * 2);
  For Index := 0 To Used - 1 Do
    Grown[Index] := Items[Slot(Index)];
  Items := Grown;
  Head := 0;
End;

Function TMonitorOutboxRing.Slot(Index: Integer): Integer;
Begin
  Result := (Head + Index) Mod Length(Items);
End;

Procedure TMonitorOutboxRing.Push(Const Entry: TMonitorOutboxEntry);
Begin
  If Used = Length(Items) Then
    Grow;
  Items[Slot(Used)] := Entry;
  Inc(Used);
End;

Function TMonitorOutboxRing.Peek(Index: Integer): TMonitorOutboxEntry;
Begin
  If (Index < 0) Or (Index >= Used) Then
    Raise Exception.Create('Monitor outbox ring index out of range.');
  Result := Items[Slot(Index)];
End;

Procedure TMonitorOutboxRing.Replace(Index: Integer; Const Entry: TMonitorOutboxEntry);
Begin
  If (Index < 0) Or (Index >= Used) Then
    Raise Exception.Create('Monitor outbox ring index out of range.');
  Items[Slot(Index)] := Entry;
End;

Function TMonitorOutboxRing.Pop(Out Entry: TMonitorOutboxEntry): Boolean;
Begin
  Result := Used > 0;
  If Not Result Then
    Begin
      Entry := Default(TMonitorOutboxEntry);
      Exit;
    End;
  Entry := Items[Head];
  Items[Head] := Default(TMonitorOutboxEntry);
  Head := (Head + 1) Mod Length(Items);
  Dec(Used);
End;

Procedure TMonitorOutboxRing.Clear;
Var
  Index: Integer;
Begin
  For Index := 0 To High(Items) Do
    Items[Index] := Default(TMonitorOutboxEntry);
  Head := 0;
  Used := 0;
End;

Function TMonitorOutboxRing.Count: Integer;
Begin
  Result := Used;
End;

{ TMonitorOutbox }

Constructor TMonitorOutbox.Create;
Var
  Lane: TMonitorOutboxLane;
Begin
  Inherited Create;
  InitCriticalSection(OutboxLock);
  For Lane := Low(TMonitorOutboxLane) To High(TMonitorOutboxLane) Do
    Begin
      Rings[Lane] := TMonitorOutboxRing.Create;
      LaneBytes[Lane] := 0;
    End;
  LogSent := 0;
  LastLogSeq := 0;
  FLogOverflowed := False;
  FOnWake := Nil;
End;

Destructor TMonitorOutbox.Destroy;
Var
  Lane: TMonitorOutboxLane;
Begin
  For Lane := Low(TMonitorOutboxLane) To High(TMonitorOutboxLane) Do
    FreeAndNil(Rings[Lane]);
  DoneCriticalSection(OutboxLock);
  Inherited Destroy;
End;

Function TMonitorOutbox.GetLogOverflowed: Boolean;
Begin
  EnterCriticalSection(OutboxLock);
  Try
    Result := FLogOverflowed;
  Finally
    LeaveCriticalSection(OutboxLock);
  End;
End;

Function TMonitorOutbox.GetOnWake: TMonitorOutboxWake;
Begin
  EnterCriticalSection(OutboxLock);
  Try
    Result := FOnWake;
  Finally
    LeaveCriticalSection(OutboxLock);
  End;
End;

Procedure TMonitorOutbox.SetOnWake(Handler: TMonitorOutboxWake);
Begin
  EnterCriticalSection(OutboxLock);
  Try
    FOnWake := Handler;
  Finally
    LeaveCriticalSection(OutboxLock);
  End;
End;

Procedure TMonitorOutbox.Wake;
Var
  Handler: TMonitorOutboxWake;
Begin
  Handler := GetOnWake;
  If Assigned(Handler) Then
    Handler;
End;

Function TMonitorOutbox.AddControl(Const Frame: RawByteString): Boolean;
Begin
  Result := FrameFits(Frame);
  If Not Result Then
    Exit;
  EnterCriticalSection(OutboxLock);
  Try
    Rings[molControl].Push(NewEntry(Frame, '', 0));
    Inc(LaneBytes[molControl], Length(Frame));
  Finally
    LeaveCriticalSection(OutboxLock);
  End;
  Wake;
End;

Function TMonitorOutbox.PutState(Const Key: String; Const Frame: RawByteString): Boolean;
Var
  Ring: TMonitorOutboxRing;
  Index: Integer;
  Found: Boolean;
Begin
  Result := (Key <> '') And FrameFits(Frame);
  If Not Result Then
    Exit;
  EnterCriticalSection(OutboxLock);
  Try
    Ring := Rings[molState];
    Found := False;
    For Index := 0 To Ring.Count - 1 Do
      If Ring.Peek(Index).Key = Key Then
        Begin
          Dec(LaneBytes[molState], Length(Ring.Peek(Index).Bytes));
          Ring.Replace(Index, NewEntry(Frame, Key, 0));
          Found := True;
          Break;
        End;
    If Not Found Then
      Ring.Push(NewEntry(Frame, Key, 0));
    Inc(LaneBytes[molState], Length(Frame));
  Finally
    LeaveCriticalSection(OutboxLock);
  End;
  Wake;
End;

Function TMonitorOutbox.AppendLog(Seq: Int64; Const Frame: RawByteString): Boolean;
Begin
  Result := (Seq > 0) And FrameFits(Frame);
  If Not Result Then
    Exit;
  EnterCriticalSection(OutboxLock);
  Try
    Result := Seq >= LastLogSeq;
    If Result Then
      Begin
        Rings[molLog].Push(NewEntry(Frame, '', Seq));
        Inc(LaneBytes[molLog], Length(Frame));
        LastLogSeq := Seq;
        If LaneBytes[molLog] > MonitorOutboxLogBudget Then
          FLogOverflowed := True;
      End;
  Finally
    LeaveCriticalSection(OutboxLock);
  End;
  If Result Then
    Wake;
End;

Function TMonitorOutbox.AddBulk(Const Chunks: Array Of RawByteString): Boolean;
Var
  Index: Integer;
  Total: Int64;
Begin
  Result := False;
  If Length(Chunks) = 0 Then
    Exit;
  Total := 0;
  For Index := 0 To High(Chunks) Do
    Begin
      If Not FrameFits(Chunks[Index]) Then
        Exit;
      Inc(Total, Length(Chunks[Index]));
    End;
  EnterCriticalSection(OutboxLock);
  Try
    { An empty lane takes any item, so one large item can never stall. }
    Result := (Rings[molBulk].Count = 0) Or (LaneBytes[molBulk] + Total <= MonitorOutboxBulkBudget);
    If Result Then
      Begin
        For Index := 0 To High(Chunks) Do
          Rings[molBulk].Push(NewEntry(Chunks[Index], '', 0));
        Inc(LaneBytes[molBulk], Total);
      End;
  Finally
    LeaveCriticalSection(OutboxLock);
  End;
  If Result Then
    Wake;
End;

Function TMonitorOutbox.Take(Out Frame: RawByteString; Out Lane: TMonitorOutboxLane): Boolean;
Var
  Entry: TMonitorOutboxEntry;
Begin
  Result := False;
  Frame := '';
  Lane := molControl;
  EnterCriticalSection(OutboxLock);
  Try
    If Rings[molControl].Pop(Entry) Then
      Lane := molControl
    Else If Rings[molState].Pop(Entry) Then
      Lane := molState
    Else If LogSent < Rings[molLog].Count Then
      Begin
        Entry := Rings[molLog].Peek(LogSent);
        Inc(LogSent);
        Lane := molLog;
      End
    Else If Rings[molBulk].Pop(Entry) Then
      Lane := molBulk
    Else
      Exit;
    Frame := Entry.Bytes;
    { Log bytes stay counted until the phone acknowledges them. }
    If Lane <> molLog Then
      Dec(LaneBytes[Lane], Length(Frame));
    Result := True;
  Finally
    LeaveCriticalSection(OutboxLock);
  End;
End;

Procedure TMonitorOutbox.Acknowledge(UpTo: Int64);
Var
  Entry: TMonitorOutboxEntry;
Begin
  EnterCriticalSection(OutboxLock);
  Try
    While (Rings[molLog].Count > 0) And (Rings[molLog].Peek(0).Seq <= UpTo) Do
      Begin
        Rings[molLog].Pop(Entry);
        Dec(LaneBytes[molLog], Length(Entry.Bytes));
        If LogSent > 0 Then
          Dec(LogSent);
      End;
  Finally
    LeaveCriticalSection(OutboxLock);
  End;
End;

Procedure TMonitorOutbox.RewindLog;
Var
  Held: Boolean;
Begin
  EnterCriticalSection(OutboxLock);
  Try
    Held := LogSent > 0;
    LogSent := 0;
  Finally
    LeaveCriticalSection(OutboxLock);
  End;
  If Held Then
    Wake;
End;

Procedure TMonitorOutbox.Clear;
Var
  Lane: TMonitorOutboxLane;
Begin
  EnterCriticalSection(OutboxLock);
  Try
    For Lane := Low(TMonitorOutboxLane) To High(TMonitorOutboxLane) Do
      Begin
        Rings[Lane].Clear;
        LaneBytes[Lane] := 0;
      End;
    LogSent := 0;
    LastLogSeq := 0;
    FLogOverflowed := False;
  Finally
    LeaveCriticalSection(OutboxLock);
  End;
End;

Function TMonitorOutbox.PendingBytes: Int64;
Var
  Lane: TMonitorOutboxLane;
Begin
  Result := 0;
  EnterCriticalSection(OutboxLock);
  Try
    For Lane := Low(TMonitorOutboxLane) To High(TMonitorOutboxLane) Do
      Inc(Result, LaneBytes[Lane]);
  Finally
    LeaveCriticalSection(OutboxLock);
  End;
End;

Function TMonitorOutbox.LaneCount(Lane: TMonitorOutboxLane): Integer;
Begin
  EnterCriticalSection(OutboxLock);
  Try
    Result := Rings[Lane].Count;
  Finally
    LeaveCriticalSection(OutboxLock);
  End;
End;

Function TMonitorOutbox.HeldLogCount: Integer;
Begin
  EnterCriticalSection(OutboxLock);
  Try
    Result := LogSent;
  Finally
    LeaveCriticalSection(OutboxLock);
  End;
End;

End.
