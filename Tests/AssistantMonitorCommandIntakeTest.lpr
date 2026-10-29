Program AssistantMonitorCommandIntakeTest;

{ Checks for the monitor command duplicate-detection table (c) 2026 Michell Computing.

  Plan item 4.4 of Documents/Plan-20261029-035918.md. A new ID is queued, a repeated
  ID is a duplicate with its stored state, states move forward only, the oldest ID is
  forgotten past MonitorCommandMemory, and threads can admit at once. No sockets, no LCL.
  The runner writes this binary with a temporary -FU and -FE, never under Source/. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, AssistantMonitorCommandIntake;

Const
  ThreadCount = 4;
  IdsPerThread = 1000;

Type
  TAdmitThread = Class(TThread)
  Private
    Intake: TMonitorCommandIntake;
    Prefix: String;
  Public
    Queued: Integer;
    Constructor Create(Target: TMonitorCommandIntake; Const IdPrefix: String);
    Procedure Execute; Override;
  End;

Var
  FailCount: Integer;

Constructor TAdmitThread.Create(Target: TMonitorCommandIntake; Const IdPrefix: String);
Begin
  Intake := Target;
  Prefix := IdPrefix;
  Queued := 0;
  Inherited Create(False);
End;

Procedure TAdmitThread.Execute;
Var
  Index: Integer;
  Prior: TMonitorCommandRecord;
Begin
  For Index := 1 To IdsPerThread Do
    If Intake.Admit(Prefix + IntToStr(Index), 1, Prior) = mirQueued Then
      Inc(Queued);
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

Function StateOf(Intake: TMonitorCommandIntake; Const Id: String): TMonitorCommandState;
Var
  Found: TMonitorCommandRecord;
Begin
  Intake.Lookup(Id, Found);
  Result := Found.State;
End;

Procedure TestAdmit;
Var
  Intake: TMonitorCommandIntake;
  Prior: TMonitorCommandRecord;
Begin
  Intake := TMonitorCommandIntake.Create;
  Try
    Check('a new ID is queued', Intake.Admit('send-1', 7, Prior) = mirQueued);
    Check('the queued record is returned', (Prior.Id = 'send-1') And (Prior.Kind = 7) And (Prior.State = mcsQueued));
    Check('one ID stored', Intake.Count = 1);
    Check('a repeated ID is a duplicate', Intake.Admit('send-1', 9, Prior) = mirDuplicate);
    Check('the duplicate keeps the first kind and state', (Prior.Kind = 7) And (Prior.State = mcsQueued));
    Check('a duplicate is not stored again', Intake.Count = 1);
    Check('an empty ID is invalid', Intake.Admit('', 7, Prior) = mirInvalid);
    Check('an empty ID is not stored', Intake.Count = 1);
    Check('an empty ID has no record', Prior.State = mcsUnknown);
  Finally
    Intake.Free;
  End;
End;

Procedure TestStates;
Var
  Intake: TMonitorCommandIntake;
  Prior, Found: TMonitorCommandRecord;
Begin
  Intake := TMonitorCommandIntake.Create;
  Try
    Intake.Admit('a', 1, Prior);
    Check('queued to accepted', Intake.NoteAccepted('a') And (StateOf(Intake, 'a') = mcsAccepted));
    Check('accepted only once', Not Intake.NoteAccepted('a'));
    Check('accepted to done', Intake.NoteDone('a') And (StateOf(Intake, 'a') = mcsDone));
    Check('done is final', (Not Intake.NoteRejected('a', 'late')) And (Not Intake.NoteDone('a')) And
      (Not Intake.NoteAccepted('a')) And (StateOf(Intake, 'a') = mcsDone));
    Check('a duplicate of a done command reports done', (Intake.Admit('a', 1, Prior) = mirDuplicate) And (Prior.State = mcsDone));

    Intake.Admit('b', 2, Prior);
    Check('queued to rejected', Intake.NoteRejected('b', 'host_busy'));
    Check('the reject reason is kept', Intake.Lookup('b', Found) And (Found.State = mcsRejected) And (Found.Reason = 'host_busy'));
    Check('rejected is final', (Not Intake.NoteAccepted('b')) And (Not Intake.NoteDone('b')) And (StateOf(Intake, 'b') = mcsRejected));

    Intake.Admit('c', 3, Prior);
    Check('queued straight to done', Intake.NoteDone('c') And (StateOf(Intake, 'c') = mcsDone));

    Intake.Admit('d', 4, Prior);
    Intake.NoteAccepted('d');
    Check('accepted to rejected', Intake.NoteRejected('d', 'cancelled') And (StateOf(Intake, 'd') = mcsRejected));

    Check('an unknown ID cannot move', (Not Intake.NoteAccepted('zz')) And (Not Intake.NoteDone('zz')) And
      (Not Intake.NoteRejected('zz', 'x')));
    Check('an unknown ID looks up as unknown', (Not Intake.Lookup('zz', Found)) And (Found.State = mcsUnknown) And (Found.Id = 'zz'));
    Check('a move does not add an ID', Intake.Count = 4);
  Finally
    Intake.Free;
  End;
End;

Procedure TestEviction;
Var
  Intake: TMonitorCommandIntake;
  Prior: TMonitorCommandRecord;
  Index: Integer;
Begin
  Intake := TMonitorCommandIntake.Create;
  Try
    For Index := 0 To MonitorCommandMemory - 1 Do
      Intake.Admit('id' + IntToStr(Index), 1, Prior);
    Check('the table holds 256 IDs', (MonitorCommandMemory = 256) And (Intake.Count = MonitorCommandMemory));
    Check('the first ID is still known when full', StateOf(Intake, 'id0') = mcsQueued);
    Intake.NoteAccepted('id1');
    Intake.Admit('id' + IntToStr(MonitorCommandMemory), 1, Prior);
    Check('the count stays at the limit', Intake.Count = MonitorCommandMemory);
    Check('the oldest ID is forgotten', StateOf(Intake, 'id0') = mcsUnknown);
    Check('the next oldest keeps its state', StateOf(Intake, 'id1') = mcsAccepted);
    Check('the newest ID is known', StateOf(Intake, 'id' + IntToStr(MonitorCommandMemory)) = mcsQueued);
    Check('a forgotten ID is new again', Intake.Admit('id0', 1, Prior) = mirQueued);
    Check('that pushes out the next oldest', StateOf(Intake, 'id1') = mcsUnknown);
    { Wrap the ring more than once. }
    For Index := 1000 To 1000 + 3 * MonitorCommandMemory Do
      Intake.Admit('w' + IntToStr(Index), 1, Prior);
    Check('after wrapping the last 256 are known', (StateOf(Intake, 'w' + IntToStr(1000 + 3 * MonitorCommandMemory)) = mcsQueued) And
      (StateOf(Intake, 'w' + IntToStr(1001 + 2 * MonitorCommandMemory)) = mcsQueued));
    Check('after wrapping older ones are forgotten', StateOf(Intake, 'w' + IntToStr(1000 + 2 * MonitorCommandMemory)) = mcsUnknown);
    Check('a moved state survives the wrap', Intake.NoteDone('w' + IntToStr(1000 + 3 * MonitorCommandMemory)) And
      (StateOf(Intake, 'w' + IntToStr(1000 + 3 * MonitorCommandMemory)) = mcsDone));
    Intake.Clear;
    Check('clear forgets every ID', (Intake.Count = 0) And (StateOf(Intake, 'w' + IntToStr(1000 + 3 * MonitorCommandMemory)) = mcsUnknown));
  Finally
    Intake.Free;
  End;
End;

Procedure TestNames;
Begin
  Check('state names', (MonitorCommandStateName(mcsUnknown) = 'unknown') And (MonitorCommandStateName(mcsQueued) = 'queued') And
    (MonitorCommandStateName(mcsAccepted) = 'accepted') And (MonitorCommandStateName(mcsRejected) = 'rejected') And
    (MonitorCommandStateName(mcsDone) = 'done'));
  Check('final states', MonitorCommandStateFinal(mcsDone) And MonitorCommandStateFinal(mcsRejected) And
    (Not MonitorCommandStateFinal(mcsQueued)) And (Not MonitorCommandStateFinal(mcsAccepted)) And
    (Not MonitorCommandStateFinal(mcsUnknown)));
End;

Procedure TestThreads;
Var
  Intake: TMonitorCommandIntake;
  Threads: Array[1..ThreadCount] Of TAdmitThread;
  Index, Total: Integer;
Begin
  Intake := TMonitorCommandIntake.Create;
  Try
    For Index := 1 To ThreadCount Do
      Threads[Index] := TAdmitThread.Create(Intake, 't' + IntToStr(Index) + '-');
    Total := 0;
    For Index := 1 To ThreadCount Do
      Begin
        Threads[Index].WaitFor;
        Inc(Total, Threads[Index].Queued);
        Threads[Index].Free;
      End;
    Check('every distinct ID from four threads is queued', Total = ThreadCount * IdsPerThread);
    Check('the table stays at its limit', Intake.Count = MonitorCommandMemory);
  Finally
    Intake.Free;
  End;
End;

Begin
  FailCount := 0;
  Try
    TestAdmit;
    TestStates;
    TestEviction;
    TestNames;
    TestThreads;
  Except
    On E: Exception Do
      Begin
        WriteLn('FAIL exception ', E.Message);
        Inc(FailCount);
      End;
  End;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantMonitorCommandIntakeTest tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantMonitorCommandIntakeTest test(s) failed.');
      Halt(1);
    End;
End.
