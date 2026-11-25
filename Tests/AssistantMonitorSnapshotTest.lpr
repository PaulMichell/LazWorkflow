Program AssistantMonitorSnapshotTest;

{ Coalesced host snapshot: one rev for a burst, a change during a build is kept,
  and readers do not leak. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Classes, SysUtils, SyncObjs, AssistantSessionObserve, AssistantMonitorSnapshot;

Var
  FailCount: Integer;

Type
  TFakeSource = Class(TMonitorSnapshotSource)
    Text: String;
    Hold: Boolean;
    Held, ReleaseBuild: PRTLEvent;
    Function Fill(Snap: TMonitorSnapshot): Boolean; Override;
  End;

  TReaderThread = Class(TThread)
    Procedure Execute; Override;
  End;

  TChangeThread = Class(TThread)
    Source: TFakeSource;
    Procedure Execute; Override;
  End;

Var
  ReadersDone: Boolean;

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

Function TFakeSource.Fill(Snap: TMonitorSnapshot): Boolean;
Begin
  Snap.Available := True;
  Snap.StatusText := Text;
  Snap.HasLive := True;
  Snap.LiveTurnId := 'live';
  SetLength(Snap.Items, 1);
  Snap.Items[0].Id := 'item';
  Snap.Items[0].Kind := 'thinking';
  Snap.Items[0].State := 'running';
  Snap.Items[0].Revision := 1;
  Snap.Items[0].Body := Text;
  If Hold Then
    Begin
      Hold := False;
      RTLEventSetEvent(Held);
      RTLEventWaitFor(ReleaseBuild, 5000);
    End;
  Result := True;
End;

Procedure TReaderThread.Execute;
Var
  Snap: TMonitorSnapshot;
  Body: AnsiString;
Begin
  While Not ReadersDone Do
    Begin
      Snap := PublishedMonitorSnapshot;
      If Assigned(Snap) Then
        Begin
          If Length(Snap.Items) > 0 Then
            Body := Snap.Items[0].Body;
          Snap.Release;
        End;
    End;
  Body := '';
End;

Procedure TChangeThread.Execute;
Begin
  RTLEventWaitFor(Source.Held, 5000);
  Source.Text := 'two';
  TouchAssistantMirror;
  RTLEventSetEvent(Source.ReleaseBuild);
End;

Procedure Pump(Ms: Integer);
Var
  Start: QWord;
Begin
  Start := GetTickCount64;
  While GetTickCount64 - Start < QWord(Ms) Do
    CheckSynchronize(20);
End;

Procedure TestBurst;
Var
  Source: TFakeSource;
  Before, After: Int64;
  Index: Integer;
Begin
  Source := TFakeSource.Create;
  Source.Text := 'burst';
  StartMonitorSnapshot(Source);
  Check('reference counts are atomic', IsMultiThread);
  Before := MonitorSnapshotRev;
  For Index := 1 To 50 Do
    TouchAssistantMirror;
  Pump(400);
  After := MonitorSnapshotRev;
  Check('burst is one or two revs', (After > Before) And (After - Before <= 2));
  StopMonitorSnapshot;
  Check('stopped clears the publisher', Not MonitorSnapshotRunning);
End;

Procedure TestChangeDuringBuild;
Var
  Source: TFakeSource;
  Changer: TChangeThread;
  Snap: TMonitorSnapshot;
  Seen: String;
  Held, ReleaseHold: PRTLEvent;
Begin
  Source := TFakeSource.Create;
  Source.Text := 'one';
  Source.Hold := True;
  Source.Held := RTLEventCreate;
  Source.ReleaseBuild := RTLEventCreate;
  Changer := TChangeThread.Create(True);
  Changer.FreeOnTerminate := False;
  Changer.Source := Source;
  Changer.Start;
  StartMonitorSnapshot(Source);
  TouchAssistantMirror;
  Pump(800);
  Changer.WaitFor;
  Changer.Free;
  Snap := PublishedMonitorSnapshot;
  If Assigned(Snap) Then
    Begin
      Seen := Snap.StatusText;
      Snap.Release;
    End
  Else
    Seen := '';
  Check('change during build is published', Seen = 'two');
  Check('second build advanced the rev', MonitorSnapshotRev >= 2);
  Held := Source.Held;
  ReleaseHold := Source.ReleaseBuild;
  StopMonitorSnapshot;
  RTLEventDestroy(Held);
  RTLEventDestroy(ReleaseHold);
End;

Procedure TestReaders;
Var
  Source: TFakeSource;
  Readers: Array[0..1] Of TReaderThread;
  Index: Integer;
Begin
  Source := TFakeSource.Create;
  Source.Text := 'read';
  StartMonitorSnapshot(Source);
  ReadersDone := False;
  For Index := 0 To 1 Do
    Begin
      Readers[Index] := TReaderThread.Create(False);
      Readers[Index].FreeOnTerminate := False;
    End;
  For Index := 1 To 20 Do
    Begin
      Source.Text := 'read-' + IntToStr(Index);
      TouchAssistantMirror;
      Pump(120);
    End;
  ReadersDone := True;
  For Index := 0 To 1 Do
    Begin
      Readers[Index].WaitFor;
      Readers[Index].Free;
    End;
  StopMonitorSnapshot;
  Check('readers finished', True);
End;

Begin
  FailCount := 0;
  ReadersDone := False;
  TestBurst;
  TestChangeDuringBuild;
  TestReaders;
  If FailCount = 0 Then
    WriteLn('AssistantMonitorSnapshotTest passed')
  Else
    Begin
      WriteLn(FailCount, ' check(s) failed');
      Halt(1);
    End;
End.
