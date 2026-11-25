Program AssistantMonitorPulseTest;

{ Pulse long poll: wake on publish, honour interval, time out, and epoch change.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Classes, SysUtils, fpjson, jsonparser, AssistantSessionObserve, AssistantMonitorSnapshot,
  AssistantMonitorPulse;

Var
  FailCount: Integer;

Type
  TFakeSource = Class(TMonitorSnapshotSource)
    Text: String;
    Function Fill(Snap: TMonitorSnapshot): Boolean; Override;
  End;

  TPulseThread = Class(TThread)
    Token, Epoch: String;
    AfterRev: Int64;
    IntervalMs, Status: Integer;
    Body: String;
    FinishedTick: QWord;
    Procedure Execute; Override;
  End;

  TChangeThread = Class(TThread)
    Source: TFakeSource;
    StopChanging: Boolean;
    Procedure Execute; Override;
  End;

  TIntervalThread = Class(TThread)
    AfterRev: Int64;
    SecondTick, ThirdTick: QWord;
    SecondBody, ThirdBody: String;
    FirstDone: Boolean;
    Procedure Execute; Override;
  End;

Function RevOf(Const Body: String): Int64; Forward;

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
  Snap.Sending := False;
  Snap.HasLive := False;
  Result := True;
End;

Procedure TPulseThread.Execute;
Begin
  ServeMonitorPulse(Token, Epoch, AfterRev, IntervalMs, Status, Body);
  FinishedTick := GetTickCount64;
End;

Procedure TChangeThread.Execute;
Var
  N: Integer;
Begin
  N := 0;
  While Not StopChanging Do
    Begin
      Inc(N);
      Source.Text := 'change-' + IntToStr(N);
      TouchAssistantMirror;
      Sleep(100);
    End;
End;

Procedure TIntervalThread.Execute;
Var
  Status: Integer;
  Body: String;
Begin
  ServeMonitorPulse('interval', 'epoch-a', AfterRev, 1000, Status, Body);
  SecondTick := GetTickCount64;
  SecondBody := Body;
  FirstDone := True;
  ServeMonitorPulse('interval', 'epoch-a', RevOf(Body), 1000, Status, ThirdBody);
  ThirdTick := GetTickCount64;
End;

Procedure Pump(Ms: Integer);
Var
  Start: QWord;
Begin
  Start := GetTickCount64;
  While GetTickCount64 - Start < QWord(Ms) Do
    CheckSynchronize(20);
End;

Function RevOf(Const Body: String): Int64;
Var
  Data: TJSONData;
Begin
  Result := -1;
  If Body = '' Then
    Exit;
  Data := GetJSON(Body);
  Try
    If Data Is TJSONObject Then
      Result := TJSONObject(Data).Get('rev', 0);
  Finally
    Data.Free;
  End;
End;

Function EpochOf(Const Body: String): String;
Var
  Data: TJSONData;
Begin
  Result := '';
  If Body = '' Then
    Exit;
  Data := GetJSON(Body);
  Try
    If Data Is TJSONObject Then
      Result := TJSONObject(Data).Get('epoch', '');
  Finally
    Data.Free;
  End;
End;

Procedure WaitUntil(Const Token: String; Count: Integer);
Var
  Start: QWord;
Begin
  Start := GetTickCount64;
  While (MonitorPulseWaiting(Token) < Count) And (GetTickCount64 - Start < 2000) Do
    CheckSynchronize(10);
End;

Function Publish(Source: TFakeSource; Const Text: String; Previous: Int64): Int64;
Var
  Start: QWord;
Begin
  Source.Text := Text;
  TouchAssistantMirror;
  Start := GetTickCount64;
  Result := Previous;
  While (Result = Previous) And (GetTickCount64 - Start < 2000) Do
    Begin
      CheckSynchronize(10);
      Result := MonitorSnapshotRev;
    End;
End;

Procedure TestHeldRequestWakes;
Var
  Source: TFakeSource;
  Pulse: TPulseThread;
  Rev: Int64;
  NoticedTick: QWord;
Begin
  Source := TFakeSource.Create;
  Source.Text := 'one';
  StartMonitorSnapshot(Source);
  SetMonitorPulseEpoch('epoch-a');
  Rev := Publish(Source, 'one', 0);
  Pulse := TPulseThread.Create(True);
  Pulse.FreeOnTerminate := False;
  Pulse.Token := 'held';
  Pulse.Epoch := 'epoch-a';
  Pulse.AfterRev := Rev;
  Pulse.IntervalMs := 150;
  Pulse.Start;
  WaitUntil('held', 1);
  Check('request is held', MonitorPulseWaiting('held') = 1);
  Rev := Publish(Source, 'two', Rev);
  NoticedTick := GetTickCount64;
  While (Pulse.FinishedTick = 0) And (GetTickCount64 - NoticedTick < 50) Do
    CheckSynchronize(1);
  Check('held request answered within 50 ms', (Pulse.FinishedTick <> 0) And (Pulse.FinishedTick <= NoticedTick + 50));
  Pulse.WaitFor;
  Check('held request has the new rev', RevOf(Pulse.Body) = Rev);
  Pulse.Free;
  StopMonitorSnapshot;
  ResetMonitorPulseClients;
End;

Procedure TestEpochAtOnce;
Var
  Source: TFakeSource;
  Pulse: TPulseThread;
  Rev: Int64;
  Started: QWord;
Begin
  Source := TFakeSource.Create;
  Source.Text := 'epoch';
  StartMonitorSnapshot(Source);
  SetMonitorPulseEpoch('epoch-a');
  Rev := Publish(Source, 'epoch', 0);
  Pulse := TPulseThread.Create(True);
  Pulse.FreeOnTerminate := False;
  Pulse.Token := 'epoch';
  Pulse.Epoch := 'epoch-a';
  Pulse.AfterRev := Rev;
  Pulse.IntervalMs := 1000;
  Pulse.Start;
  WaitUntil('epoch', 1);
  Started := GetTickCount64;
  SetMonitorPulseEpoch('epoch-b');
  While (Pulse.FinishedTick = 0) And (GetTickCount64 - Started < 50) Do
    CheckSynchronize(1);
  Check('changed epoch answered within 50 ms', (Pulse.FinishedTick <> 0) And (Pulse.FinishedTick <= Started + 50));
  Pulse.WaitFor;
  Check('answer carries the new epoch', EpochOf(Pulse.Body) = 'epoch-b');
  Pulse.Free;
  StopMonitorSnapshot;
  ResetMonitorPulseClients;
End;

Procedure TestInterval;
Var
  Source: TFakeSource;
  Changer: TChangeThread;
  Job: TIntervalThread;
  FirstTick: QWord;
  Status: Integer;
  Body: String;
  FirstRev, SecondRev, ThirdRev: Int64;
Begin
  Source := TFakeSource.Create;
  Source.Text := 'interval';
  StartMonitorSnapshot(Source);
  SetMonitorPulseEpoch('epoch-a');
  Publish(Source, 'interval', 0);
  ServeMonitorPulse('interval', 'epoch-a', 0, 1000, Status, Body);
  FirstTick := GetTickCount64;
  FirstRev := RevOf(Body);
  Changer := TChangeThread.Create(True);
  Changer.FreeOnTerminate := False;
  Changer.Source := Source;
  Job := TIntervalThread.Create(True);
  Job.FreeOnTerminate := False;
  Job.AfterRev := FirstRev;
  Changer.Start;
  Job.Start;
  While (Not Job.FirstDone) And (GetTickCount64 - FirstTick < 3000) Do
    CheckSynchronize(20);
  Changer.StopChanging := True;
  While (Job.ThirdTick = 0) And (GetTickCount64 - FirstTick < 5000) Do
    CheckSynchronize(20);
  Job.WaitFor;
  Changer.WaitFor;
  SecondRev := RevOf(Job.SecondBody);
  ThirdRev := RevOf(Job.ThirdBody);
  Check('interval answers about one second apart', (Job.SecondTick > FirstTick) And (Job.SecondTick - FirstTick >= 900) And
    (Job.SecondTick - FirstTick <= 1500) And (Job.ThirdTick - Job.SecondTick >= 900) And (Job.ThirdTick - Job.SecondTick <= 1500));
  Check('each interval answer has a newer rev', (SecondRev > FirstRev) And (ThirdRev >= SecondRev));
  Check('last interval answer has the latest rev', ThirdRev = MonitorSnapshotRev);
  Job.Free;
  Changer.Free;
  StopMonitorSnapshot;
  ResetMonitorPulseClients;
End;

Procedure TestQuietTimeout;
Var
  Source: TFakeSource;
  Pulse: TPulseThread;
  Rev: Int64;
  Started: QWord;
Begin
  Source := TFakeSource.Create;
  Source.Text := 'quiet';
  StartMonitorSnapshot(Source);
  SetMonitorPulseEpoch('epoch-a');
  Rev := Publish(Source, 'quiet', 0);
  Pulse := TPulseThread.Create(True);
  Pulse.FreeOnTerminate := False;
  Pulse.Token := 'quiet';
  Pulse.Epoch := 'epoch-a';
  Pulse.AfterRev := Rev;
  Pulse.IntervalMs := 1000;
  Started := GetTickCount64;
  Pulse.Start;
  While (Pulse.FinishedTick = 0) And (GetTickCount64 - Started < 12000) Do
    CheckSynchronize(50);
  Pulse.WaitFor;
  Check('quiet pulse answers after 10 seconds', (Pulse.FinishedTick - Started >= 9500) And (Pulse.FinishedTick - Started <= 11500));
  Check('quiet pulse keeps the same rev', RevOf(Pulse.Body) = Rev);
  Pulse.Free;
  StopMonitorSnapshot;
  ResetMonitorPulseClients;
End;

Begin
  FailCount := 0;
  TestHeldRequestWakes;
  TestEpochAtOnce;
  TestInterval;
  TestQuietTimeout;
  If FailCount = 0 Then
    WriteLn('AssistantMonitorPulseTest passed')
  Else
    Begin
      WriteLn(FailCount, ' check(s) failed');
      Halt(1);
    End;
End.
