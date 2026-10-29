Unit AssistantMonitorCommandIntake;

{ Duplicate-detection table for monitor commands (c) 2026 Michell Computing.

  Plan item 4.4 of Documents/Plan-20261029-035918.md. The connection thread
  records each command ID here as it decodes the command. A new ID is stored as
  queued, so the thread can acknowledge `queued` at once without the IDE thread.
  An ID already in the table is a duplicate, and the caller answers with the
  stored state instead of running the command again. The bridge moves an ID on
  as the IDE thread handles it: queued, then accepted, then done, or rejected
  with a reason from queued or accepted. A finished command does not change
  again. Lookup answers the state of an ID for a phone that asks after an
  ambiguous disconnect (plan item 7.3).

  The table keeps the last MonitorCommandMemory IDs. The oldest is forgotten
  when it is full, and a forgotten ID counts as new. It is not cleared on a
  reconnect, because a resent command arrives on the next connection.

  Thread safe. No JSON, socket, or LCL code in this unit. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Const
  MonitorCommandMemory = 256;

Type
  TMonitorCommandState = (mcsUnknown, mcsQueued, mcsAccepted, mcsRejected, mcsDone);

  TMonitorCommandRecord = Record
    Id: String;
    Kind: Integer;
    State: TMonitorCommandState;
    Reason: String;
  End;

  TMonitorIntakeResult = (mirQueued, mirDuplicate, mirInvalid);

  TMonitorCommandIntake = Class
  Private
    IntakeLock: TRTLCriticalSection;
    Records: Array[0..MonitorCommandMemory - 1] Of TMonitorCommandRecord;
    { Slot of the oldest record, and how many slots are in use. }
    Head: Integer;
    Used: Integer;
    Function FindLocked(Const Id: String): Integer;
    Function Move(Const Id: String; State: TMonitorCommandState; Const Reason: String): Boolean;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    { mirQueued stores a new ID as queued. mirDuplicate leaves the table alone and returns the stored record.
      mirInvalid is an empty ID, which is never stored. }
    Function Admit(Const Id: String; Kind: Integer; Out Prior: TMonitorCommandRecord): TMonitorIntakeResult;
    { Each returns False, and changes nothing, for an unknown ID or a move the state does not allow. }
    Function NoteAccepted(Const Id: String): Boolean;
    Function NoteRejected(Const Id, Reason: String): Boolean;
    Function NoteDone(Const Id: String): Boolean;
    { False, with State mcsUnknown, for an ID never seen or already forgotten. }
    Function Lookup(Const Id: String; Out Found: TMonitorCommandRecord): Boolean;
    Procedure Clear;
    Function Count: Integer;
  End;

Function MonitorCommandStateName(State: TMonitorCommandState): String;
Function MonitorCommandStateFinal(State: TMonitorCommandState): Boolean;

Implementation

Function MonitorCommandStateName(State: TMonitorCommandState): String;
Begin
  Case State Of
    mcsQueued: Result := 'queued';
    mcsAccepted: Result := 'accepted';
    mcsRejected: Result := 'rejected';
    mcsDone: Result := 'done';
  Else
    Result := 'unknown';
  End;
End;

Function MonitorCommandStateFinal(State: TMonitorCommandState): Boolean;
Begin
  Result := (State = mcsRejected) Or (State = mcsDone);
End;

Function MoveAllowed(Current, Next: TMonitorCommandState): Boolean;
Begin
  Case Next Of
    mcsAccepted: Result := Current = mcsQueued;
    mcsRejected, mcsDone: Result := (Current = mcsQueued) Or (Current = mcsAccepted);
  Else
    Result := False;
  End;
End;

Constructor TMonitorCommandIntake.Create;
Begin
  Inherited Create;
  InitCriticalSection(IntakeLock);
  Head := 0;
  Used := 0;
End;

Destructor TMonitorCommandIntake.Destroy;
Begin
  DoneCriticalSection(IntakeLock);
  Inherited Destroy;
End;

Function TMonitorCommandIntake.FindLocked(Const Id: String): Integer;
Var
  Index, Slot: Integer;
Begin
  Result := -1;
  { Newest first: a resent command is usually recent. }
  For Index := Used - 1 DownTo 0 Do
    Begin
      Slot := (Head + Index) Mod MonitorCommandMemory;
      If Records[Slot].Id = Id Then
        Begin
          Result := Slot;
          Exit;
        End;
    End;
End;

Function TMonitorCommandIntake.Admit(Const Id: String; Kind: Integer; Out Prior: TMonitorCommandRecord): TMonitorIntakeResult;
Var
  Slot: Integer;
Begin
  Prior := Default(TMonitorCommandRecord);
  If Id = '' Then
    Begin
      Result := mirInvalid;
      Exit;
    End;
  EnterCriticalSection(IntakeLock);
  Try
    Slot := FindLocked(Id);
    If Slot >= 0 Then
      Begin
        Prior := Records[Slot];
        Result := mirDuplicate;
        Exit;
      End;
    If Used < MonitorCommandMemory Then
      Begin
        Slot := (Head + Used) Mod MonitorCommandMemory;
        Inc(Used);
      End
    Else
      Begin
        Slot := Head;
        Head := (Head + 1) Mod MonitorCommandMemory;
      End;
    Records[Slot].Id := Id;
    Records[Slot].Kind := Kind;
    Records[Slot].State := mcsQueued;
    Records[Slot].Reason := '';
    Prior := Records[Slot];
    Result := mirQueued;
  Finally
    LeaveCriticalSection(IntakeLock);
  End;
End;

Function TMonitorCommandIntake.Move(Const Id: String; State: TMonitorCommandState; Const Reason: String): Boolean;
Var
  Slot: Integer;
Begin
  Result := False;
  If Id = '' Then
    Exit;
  EnterCriticalSection(IntakeLock);
  Try
    Slot := FindLocked(Id);
    If (Slot < 0) Or (Not MoveAllowed(Records[Slot].State, State)) Then
      Exit;
    Records[Slot].State := State;
    Records[Slot].Reason := Reason;
    Result := True;
  Finally
    LeaveCriticalSection(IntakeLock);
  End;
End;

Function TMonitorCommandIntake.NoteAccepted(Const Id: String): Boolean;
Begin
  Result := Move(Id, mcsAccepted, '');
End;

Function TMonitorCommandIntake.NoteRejected(Const Id, Reason: String): Boolean;
Begin
  Result := Move(Id, mcsRejected, Reason);
End;

Function TMonitorCommandIntake.NoteDone(Const Id: String): Boolean;
Begin
  Result := Move(Id, mcsDone, '');
End;

Function TMonitorCommandIntake.Lookup(Const Id: String; Out Found: TMonitorCommandRecord): Boolean;
Var
  Slot: Integer;
Begin
  Found := Default(TMonitorCommandRecord);
  Found.Id := Id;
  Result := False;
  If Id = '' Then
    Exit;
  EnterCriticalSection(IntakeLock);
  Try
    Slot := FindLocked(Id);
    If Slot < 0 Then
      Exit;
    Found := Records[Slot];
    Result := True;
  Finally
    LeaveCriticalSection(IntakeLock);
  End;
End;

Procedure TMonitorCommandIntake.Clear;
Var
  Slot: Integer;
Begin
  EnterCriticalSection(IntakeLock);
  Try
    For Slot := 0 To MonitorCommandMemory - 1 Do
      Records[Slot] := Default(TMonitorCommandRecord);
    Head := 0;
    Used := 0;
  Finally
    LeaveCriticalSection(IntakeLock);
  End;
End;

Function TMonitorCommandIntake.Count: Integer;
Begin
  EnterCriticalSection(IntakeLock);
  Try
    Result := Used;
  Finally
    LeaveCriticalSection(IntakeLock);
  End;
End;

End.
