Unit AssistantMonitorPulse;

{ Long poll for GET /v4/pulse (c) 2026 Michell Computing.

  A held request waits on the waiter's event. The snapshot publisher signals that
  event when it publishes. This unit does not poll. interval is the shortest gap
  after this client's previous answer. A third wait for one token answers the
  oldest at once. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Const
  MonitorPulseMaxWaitMs = 10000;
  MonitorPulseIntervalDefault = 250;
  MonitorPulseIntervalMin = 150;
  MonitorPulseIntervalMax = 10000;

Procedure SetMonitorPulseEpoch(Const Epoch: String);
Function MonitorPulseEpoch: String;
Procedure CancelMonitorPulses;
Procedure WaitMonitorPulses;
Procedure WakeMonitorPulse;
Function MonitorPulseWaiting(Const Token: String): Integer;
Procedure ResetMonitorPulseClients;
Procedure ServeMonitorPulse(Const Token, ClientEpoch: String; AfterRev: Int64; IntervalMs: Integer;
  Out Status: Integer; Out Body: String);

Implementation

Uses
  Classes, DateUtils, SyncObjs, fpjson, AssistantMonitorSnapshot, AssistantMonitorCommands, AssistantMonitorPair,
  AssistantMonitorCodec;

Type
  TPulseWaiter = Class
    Token: String;
    Force: Boolean;
    Event: PRTLEvent;
    Started: QWord;
  End;

  TPulseClient = Class
    Token: String;
    LastAnswer: QWord;
    HasAnswer: Boolean;
  End;

Var
  PulseLock: TRTLCriticalSection;
  PulseEpoch: String;
  PulseStopping: Boolean;
  PulseInFlight: Integer;
  Waiters: TList;
  Clients: TList;

Function ClampInterval(IntervalMs: Integer): Integer;
Begin
  If IntervalMs <= 0 Then
    Result := MonitorPulseIntervalDefault
  Else If IntervalMs < MonitorPulseIntervalMin Then
    Result := MonitorPulseIntervalMin
  Else If IntervalMs > MonitorPulseIntervalMax Then
    Result := MonitorPulseIntervalMax
  Else
    Result := IntervalMs;
End;

Function FindClient(Const Token: String): TPulseClient;
Var
  Index: Integer;
Begin
  Result := Nil;
  For Index := 0 To Clients.Count - 1 Do
    If TPulseClient(Clients[Index]).Token = Token Then
      Exit(TPulseClient(Clients[Index]));
End;

Function IntervalElapsed(Const Token: String; IntervalMs: Integer; NowTick: QWord): Boolean;
Var
  Client: TPulseClient;
Begin
  Client := FindClient(Token);
  If (Client = Nil) Or (Not Client.HasAnswer) Then
    Exit(True);
  Result := NowTick - Client.LastAnswer >= QWord(IntervalMs);
End;

Procedure NoteAnswer(Const Token: String; NowTick: QWord);
Var
  Client: TPulseClient;
Begin
  Client := FindClient(Token);
  If Client = Nil Then
    Begin
      Client := TPulseClient.Create;
      Client.Token := Token;
      Clients.Add(Client);
    End;
  Client.LastAnswer := NowTick;
  Client.HasAnswer := True;
End;

Procedure SignalWaiters;
Var
  Index: Integer;
Begin
  EnterCriticalSection(PulseLock);
  Try
    For Index := 0 To Waiters.Count - 1 Do
      RTLEventSetEvent(TPulseWaiter(Waiters[Index]).Event);
  Finally
    LeaveCriticalSection(PulseLock);
  End;
End;

Procedure NotifyPulsePublished;
Begin
  SignalWaiters;
End;

Procedure WakeMonitorPulse;
Begin
  SignalWaiters;
End;

Function CurrentRev: Int64;
Var
  Snap: TMonitorSnapshot;
Begin
  Snap := PublishedMonitorSnapshot;
  If Assigned(Snap) Then
    Begin
      Result := Snap.Rev;
      Snap.Release;
    End
  Else
    Result := 0;
End;

Function ReadyToAnswer(Waiter: TPulseWaiter; Const ClientEpoch: String; AfterRev: Int64; IntervalMs: Integer;
  StartTick, NowTick: QWord): Boolean;
Begin
  If PulseStopping Then
    Exit(True);
  If ClientEpoch <> PulseEpoch Then
    Exit(True);
  If Waiter.Force Then
    Exit(True);
  If MonitorCommandStopPending Then
    Exit(True);
  If MonitorTokenRevoked(Waiter.Token) Then
    Exit(True);
  If NowTick - StartTick >= MonitorPulseMaxWaitMs Then
    Exit(True);
  Result := (CurrentRev > AfterRev) And IntervalElapsed(Waiter.Token, IntervalMs, NowTick);
End;

Function NextWaitMs(Waiter: TPulseWaiter; AfterRev: Int64; IntervalMs: Integer; StartTick, NowTick: QWord): Integer;
Var
  Client: TPulseClient;
  UntilDeadline, UntilInterval, WaitMs: QWord;
Begin
  If NowTick - StartTick >= MonitorPulseMaxWaitMs Then
    Exit(0);
  UntilDeadline := StartTick + MonitorPulseMaxWaitMs - NowTick;
  WaitMs := UntilDeadline;
  { Hold a change back until interval after the previous answer. No change waits out the cap. }
  If CurrentRev > AfterRev Then
    Begin
      Client := FindClient(Waiter.Token);
      If Assigned(Client) And Client.HasAnswer Then
        Begin
          If NowTick - Client.LastAnswer >= QWord(IntervalMs) Then
            UntilInterval := 0
          Else
            UntilInterval := Client.LastAnswer + QWord(IntervalMs) - NowTick;
          If UntilInterval < WaitMs Then
            WaitMs := UntilInterval;
        End;
    End;
  Result := Integer(WaitMs);
End;

Procedure RegisterWaiter(Waiter: TPulseWaiter);
Var
  Index, Count: Integer;
  Oldest: TPulseWaiter;
Begin
  Count := 0;
  Oldest := Nil;
  For Index := 0 To Waiters.Count - 1 Do
    If TPulseWaiter(Waiters[Index]).Token = Waiter.Token Then
      Begin
        Inc(Count);
        If (Oldest = Nil) Or (TPulseWaiter(Waiters[Index]).Started < Oldest.Started) Then
          Oldest := TPulseWaiter(Waiters[Index]);
      End;
  If (Count >= 2) And Assigned(Oldest) Then
    Oldest.Force := True;
  Waiters.Add(Waiter);
  If Assigned(Oldest) And Oldest.Force Then
    RTLEventSetEvent(Oldest.Event);
End;

Procedure AddJsonBool(Obj: TJSONObject; Const Name: String; Value: Boolean);
Begin
  Obj.Add(Name, Value);
End;

Function PulseServerTime: String;
Var
  Utc: TDateTime;
Begin
  Utc := LocalTimeToUniversal(Now);
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', Utc) + '.' +
    Format('%.3d', [MilliSecondOf(Utc)]) + 'Z';
End;

Function ErrorBody(Const Reason, MessageText: String): String;
Var
  Obj: TJSONObject;
Begin
  Obj := TJSONObject.Create;
  Try
    Obj.Add('reason', Reason);
    Obj.Add('message', MessageText);
    Result := Obj.AsJSON;
  Finally
    Obj.Free;
  End;
End;

Procedure AddLive(Root: TJSONObject; Snap: TMonitorSnapshot);
Var
  Live, Item: TJSONObject;
  Index, Chosen: Integer;
Begin
  If Not (Snap.HasLive And Snap.Sending And (Snap.LiveTurnId <> '')) Then
    Begin
      Root.Add('live', TJSONNull.Create);
      Exit;
    End;
  Live := TJSONObject.Create;
  Live.Add('turn_id', String(Snap.LiveTurnId));
  Live.Add('turn_index', Snap.LiveTurnIndex);
  Live.Add('rev', Snap.LiveRev);
  Chosen := -1;
  For Index := 0 To High(Snap.Items) Do
    If Snap.Items[Index].State = 'running' Then
      Chosen := Index;
  If (Chosen < 0) And (Length(Snap.Items) > 0) Then
    Chosen := High(Snap.Items);
  If Chosen < 0 Then
    Live.Add('item', TJSONNull.Create)
  Else
    Begin
      Item := TJSONObject.Create;
      Item.Add('id', String(Snap.Items[Chosen].Id));
      Item.Add('kind', String(Snap.Items[Chosen].Kind));
      Item.Add('state', String(Snap.Items[Chosen].State));
      Item.Add('rev', Snap.Items[Chosen].Revision);
      Item.Add('bytes', Length(Snap.Items[Chosen].Body));
      Live.Add('item', Item);
    End;
  Root.Add('live', Live);
End;

Function BuildPulseBody(Const Epoch: String): String;
Var
  Snap: TMonitorSnapshot;
Begin
  Snap := PublishedMonitorSnapshot;
  Result := MonitorPulseJson(Snap, Epoch, PulseServerTime, MonitorCommandStopPending);
  If Assigned(Snap) Then
    Snap.Release;
End;






Procedure ServeMonitorPulse(Const Token, ClientEpoch: String; AfterRev: Int64; IntervalMs: Integer;
  Out Status: Integer; Out Body: String);
Var
  Waiter: TPulseWaiter;
  Interval, Remaining: Integer;
  StartTick, NowTick: QWord;
  Stopping: Boolean;
Begin
  Status := 200;
  Body := '';
  Interval := ClampInterval(IntervalMs);
  Waiter := TPulseWaiter.Create;
  Waiter.Token := Token;
  Waiter.Event := RTLEventCreate;
  Waiter.Started := GetTickCount64;
  StartTick := Waiter.Started;
  EnterCriticalSection(PulseLock);
  Try
    Inc(PulseInFlight);
    RegisterWaiter(Waiter);
  Finally
    LeaveCriticalSection(PulseLock);
  End;
  Try
    Repeat
      NowTick := GetTickCount64;
      EnterCriticalSection(PulseLock);
      Try
        Stopping := PulseStopping;
        If ReadyToAnswer(Waiter, ClientEpoch, AfterRev, Interval, StartTick, NowTick) Then
          Begin
            If Not Stopping Then
              NoteAnswer(Token, NowTick);
            Remaining := -1;
          End
        Else
          Remaining := NextWaitMs(Waiter, AfterRev, Interval, StartTick, NowTick);
      Finally
        LeaveCriticalSection(PulseLock);
      End;
      If Remaining < 0 Then
        Break;
      If Remaining = 0 Then
        Break;
      RTLEventWaitFor(Waiter.Event, Remaining);
      RTLEventResetEvent(Waiter.Event);
    Until False;
    EnterCriticalSection(PulseLock);
    Try
      Stopping := PulseStopping;
      If Stopping Then
        Status := 503
      Else If MonitorTokenRevoked(Token) Then
        Status := 403
      Else
        Status := 200;
    Finally
      LeaveCriticalSection(PulseLock);
    End;
    If Status = 503 Then
      Body := ErrorBody('no_session', 'The listener is stopping.')
    Else If Status = 403 Then
      Body := ErrorBody('revoked', 'This phone was revoked.')
    Else
      Body := BuildPulseBody(MonitorPulseEpoch);
  Finally
    EnterCriticalSection(PulseLock);
    Try
      Waiters.Remove(Waiter);
      Dec(PulseInFlight);
    Finally
      LeaveCriticalSection(PulseLock);
    End;
    RTLEventDestroy(Waiter.Event);
    Waiter.Free;
  End;
End;

Procedure SetMonitorPulseEpoch(Const Epoch: String);
Var
  Changed: Boolean;
Begin
  EnterCriticalSection(PulseLock);
  Try
    Changed := PulseEpoch <> Epoch;
    PulseEpoch := Epoch;
    If Epoch <> '' Then
      PulseStopping := False;
  Finally
    LeaveCriticalSection(PulseLock);
  End;
  If Changed Then
    SignalWaiters;
End;

Function MonitorPulseEpoch: String;
Begin
  EnterCriticalSection(PulseLock);
  Try
    Result := PulseEpoch;
  Finally
    LeaveCriticalSection(PulseLock);
  End;
End;

Procedure CancelMonitorPulses;
Begin
  EnterCriticalSection(PulseLock);
  Try
    PulseStopping := True;
  Finally
    LeaveCriticalSection(PulseLock);
  End;
  SignalWaiters;
End;

Procedure WaitMonitorPulses;
Var
  Start: QWord;
Begin
  Start := GetTickCount64;
  While GetTickCount64 - Start < 2000 Do
    Begin
      EnterCriticalSection(PulseLock);
      Try
        If PulseInFlight = 0 Then
          Exit;
      Finally
        LeaveCriticalSection(PulseLock);
      End;
      Sleep(10);
    End;
End;

Function MonitorPulseWaiting(Const Token: String): Integer;
Var
  Index: Integer;
Begin
  Result := 0;
  EnterCriticalSection(PulseLock);
  Try
    For Index := 0 To Waiters.Count - 1 Do
      If TPulseWaiter(Waiters[Index]).Token = Token Then
        Inc(Result);
  Finally
    LeaveCriticalSection(PulseLock);
  End;
End;

Procedure ResetMonitorPulseClients;
Var
  Index: Integer;
Begin
  EnterCriticalSection(PulseLock);
  Try
    For Index := 0 To Clients.Count - 1 Do
      TPulseClient(Clients[Index]).Free;
    Clients.Clear;
    PulseStopping := False;
  Finally
    LeaveCriticalSection(PulseLock);
  End;
End;

Initialization

  InitCriticalSection(PulseLock);
  Waiters := TList.Create;
  Clients := TList.Create;
  SetMonitorPublishWake(@NotifyPulsePublished);

Finalization

  SetMonitorPublishWake(Nil);
  CancelMonitorPulses;
  WaitMonitorPulses;
  ResetMonitorPulseClients;
  Waiters.Free;
  Clients.Free;
  DoneCriticalSection(PulseLock);

End.
