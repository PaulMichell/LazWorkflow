Program AssistantMonitorCommandsTest;

{ Command acceptance: one send per id, a fast stop, and the protocol errors.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Classes, SysUtils, fpjson, jsonparser, AssistantMonitorCommands, AssistantMonitorPulse;

Var
  FailCount: Integer;

Type
  TFakeHost = Class(TMonitorCommandHost)
    Sends: Integer;
    StoredId, StoredTurn: String;
    Unsaved: Boolean;
    Function KnownTurn(Const CommandId: String; Out TurnId: String): Boolean; Override;
    Function Send(Const Text: String; SaveFirst: Boolean; Const CommandId: String): TMonitorHostAnswer; Override;
    Function Stop: TMonitorHostAnswer; Override;
  End;

  TSendThread = Class(TThread)
    Status: Integer;
    Answer: String;
    Procedure Execute; Override;
  End;

  TStopThread = Class(TThread)
    Elapsed: QWord;
    Status: Integer;
    Procedure Execute; Override;
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

Function TFakeHost.KnownTurn(Const CommandId: String; Out TurnId: String): Boolean;
Begin
  TurnId := StoredTurn;
  Result := (StoredId <> '') And (CommandId = StoredId);
End;

Function TFakeHost.Send(Const Text: String; SaveFirst: Boolean; Const CommandId: String): TMonitorHostAnswer;
Begin
  If Unsaved Then
    Begin
      Result.Ok := False;
      Result.Reason := 'unsaved_edits';
      Result.Message := 'The desktop has unsaved edits.';
      Result.TurnId := '';
      Exit;
    End;
  Inc(Sends);
  Result.Ok := True;
  Result.Reason := '';
  Result.Message := '';
  Result.TurnId := 'turn-1';
End;

Function TFakeHost.Stop: TMonitorHostAnswer;
Begin
  Result.Ok := True;
  Result.Reason := '';
  Result.Message := '';
  Result.TurnId := '';
End;

Procedure TSendThread.Execute;
Begin
  ServeMonitorCommand('{"id":"cmd-send","type":"send","args":{"text":"hello","save_first":false}}', Status, Answer);
  ServeMonitorCommand('{"id":"cmd-send","type":"send","args":{"text":"hello","save_first":false}}', Status, Answer);
End;

Procedure TStopThread.Execute;
Var
  Started: QWord;
  Answer: String;
Begin
  Sleep(200);
  Started := GetTickCount64;
  ServeMonitorCommand('{"id":"cmd-stop","type":"stop","args":{}}', Status, Answer);
  Elapsed := GetTickCount64 - Started;
End;

Function StopPending(Const Body: String): Boolean;
Var
  Data: TJSONData;
  Status: TJSONData;
Begin
  Result := False;
  Data := GetJSON(Body);
  Try
    If Data Is TJSONObject Then
      Begin
        Status := TJSONObject(Data).Find('status');
        If Status Is TJSONObject Then
          Result := TJSONObject(Status).Get('stop_pending', False);
      End;
  Finally
    Data.Free;
  End;
End;

Procedure PumpUntil(Thread: TThread);
Var
  Start: QWord;
Begin
  Start := GetTickCount64;
  While (Not Thread.Finished) And (GetTickCount64 - Start < 8000) Do
    CheckSynchronize(20);
  Thread.WaitFor;
End;

Procedure TestOneSend;
Var
  Host: TFakeHost;
  Worker: TSendThread;
Begin
  Host := TFakeHost.Create;
  SetMonitorCommandHost(Host);
  ResetMonitorCommands;
  Worker := TSendThread.Create(True);
  Worker.FreeOnTerminate := False;
  Worker.Start;
  PumpUntil(Worker);
  Check('send twice starts one turn', Host.Sends = 1);
  Worker.Free;
  Host.Free;
End;

Procedure TestRestart;
Var
  Host: TFakeHost;
  Status: Integer;
  Answer: String;
Begin
  Host := TFakeHost.Create;
  Host.StoredId := 'cmd-send';
  Host.StoredTurn := 'turn-stored';
  SetMonitorCommandHost(Host);
  ResetMonitorCommands;
  ServeMonitorCommand('{"id":"cmd-send","type":"send","args":{"text":"again"}}', Status, Answer);
  Check('stored id starts no turn', (Host.Sends = 0) And (Status = 200) And (Pos('turn-stored', Answer) > 0));
  Host.Free;
End;

Procedure TestStop;
Var
  Host: TFakeHost;
  Worker: TStopThread;
  Status: Integer;
  Body: String;
Begin
  Host := TFakeHost.Create;
  SetMonitorCommandHost(Host);
  ResetMonitorCommands;
  SetMonitorPulseEpoch('epoch-a');
  Worker := TStopThread.Create(True);
  Worker.FreeOnTerminate := False;
  Worker.Start;
  Sleep(3000);
  Worker.WaitFor;
  Check('stop answers within 50 ms', (Worker.Status = 200) And (Worker.Elapsed <= 50));
  ServeMonitorPulse('cmd', 'epoch-a', 0, 150, Status, Body);
  Check('pulse shows stop pending', StopPending(Body));
  CheckSynchronize(50);
  SetMonitorPulseEpoch('epoch-b');
  ServeMonitorPulse('cmd', 'epoch-a', 0, 150, Status, Body);
  Check('stop pending clears when the queued call runs', Not StopPending(Body));
  Worker.Free;
  Host.Free;
End;

Procedure TestUnsavedAndUnknown;
Var
  Host: TFakeHost;
  Worker: TSendThread;
  Status: Integer;
  Answer: String;
Begin
  Host := TFakeHost.Create;
  Host.Unsaved := True;
  SetMonitorCommandHost(Host);
  ResetMonitorCommands;
  Worker := TSendThread.Create(True);
  Worker.FreeOnTerminate := False;
  Worker.Start;
  PumpUntil(Worker);
  Check('unsaved edits is 409', (Worker.Status = 409) And (Pos('unsaved_edits', Worker.Answer) > 0));
  Worker.Free;
  ServeMonitorCommand('{"id":"cmd-x","type":"set_model","args":{}}', Status, Answer);
  Check('unknown type is 400 protocol', (Status = 400) And (Pos('protocol', Answer) > 0));
  Host.Free;
End;

Begin
  FailCount := 0;
  TestOneSend;
  TestRestart;
  TestStop;
  TestUnsavedAndUnknown;
  ResetMonitorCommands;
  SetMonitorCommandHost(Nil);
  If FailCount = 0 Then
    WriteLn('AssistantMonitorCommandsTest passed')
  Else
    Begin
      WriteLn(FailCount, ' check(s) failed');
      Halt(1);
    End;
End.
