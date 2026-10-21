Program AssistantCodexTransportTest;
{$mode objfpc}{$H+}
Uses cthreads, Classes, SysUtils, BaseUnix, AssistantCodexTransport;
Procedure Check(Const Name: String; OK: Boolean);
Begin
  If Not OK Then Begin WriteLn('FAIL ', Name); Halt(1); End;
  WriteLn('ok   ', Name);
End;
Procedure Fake;
Var Line, Mode: String; Fd: Integer;
Begin
  Mode := ParamStr(2);
  If Mode = 'blocked' Then Begin Sleep(10000); Halt; End;
  If Mode = 'diagnostic' Then
    Begin WriteLn(StdErr, 'secret-token workspace routing discovery failed'); Halt(7); End;
  If Mode = 'truncated' Then Begin Write('{"id":'); Flush(Output); Halt; End;
  If Mode = 'oversized' Then Begin Write(StringOfChar('x', CodexMaxFrameBytes + 1)); Flush(Output); Sleep(10000); Halt; End;
  If Mode = 'flood' Then Begin Write(StdErr, StringOfChar('e', 200000)); Flush(StdErr); End;
  If Mode = 'closed' Then Begin fpClose(0); For Fd := 3 To 255 Do fpClose(Fd); WriteLn('{"closed":true}'); Flush(Output); Sleep(10000); Halt; End;
  While Not EOF(Input) Do
    Begin
      ReadLn(Line);
      Write(Copy(Line, 1, 4)); Flush(Output); Sleep(1);
      WriteLn(Copy(Line, 5, MaxInt)); Flush(Output);
    End;
End;
Var Transport: TAssistantCodexTransport; Args: TStringList; Frame: String;
  Deadline, Started: QWord; I: Integer;
Procedure Start(Const Mode: String);
Begin
  Args.Clear; Args.Add('--fake'); Args.Add(Mode);
  Check('start ' + Mode, Transport.Start(ParamStr(0), GetTempDir, Args));
End;
Procedure PumpUntilFrame;
Begin
  Deadline := GetTickCount64 + 3000;
  Repeat
    Transport.Poll;
    If Transport.TakeFrame(Frame) Then Exit;
    Sleep(1);
  Until (Transport.LastError <> '') Or (GetTickCount64 >= Deadline);
End;
Procedure PumpUntilError;
Begin
  Deadline := GetTickCount64 + 3000;
  Repeat Transport.Poll; Sleep(1);
  Until (Transport.LastError <> '') Or (GetTickCount64 >= Deadline);
End;
Begin
  If ParamStr(1) = '--fake' Then Begin Fake; Halt; End;
  Args := TStringList.Create;
  Transport := TAssistantCodexTransport.Create(100);
  Try
    Start('echo');
    Check('queue request', Transport.Queue('{"id":1,"params":{"text":"**x**"}}'));
    PumpUntilFrame;
    Check('fragmented round trip', Frame = '{"id":1,"params":{"text":"**x**"}}');
    Transport.Cancel;
    Started := GetTickCount64; Transport.Poll;
    Check('cancel bounded', (Not Transport.Running) And (GetTickCount64 - Started < 1000));
    Start('flood'); Transport.Queue('{"id":2}'); PumpUntilFrame;
    Check('stderr flood does not deadlock or contaminate protocol', Frame = '{"id":2}');
    Start('diagnostic'); PumpUntilError;
    Check('exit status retained', Pos('Exit status 7', Transport.LastError) > 0);
    Check('stderr categorized', Pos('workspace routing', Transport.LastError) > 0);
    Check('stderr credentials omitted', Pos('secret-token', Transport.LastError) = 0);
    Start('truncated'); PumpUntilError;
    Check('truncated EOF detected', Pos('truncated', Transport.LastError) > 0);
    Start('oversized'); PumpUntilError;
    Check('frame limit', Pos('Oversized', Transport.LastError) > 0);
    Start('blocked'); Transport.Queue(StringOfChar('x', CodexMaxFrameBytes)); PumpUntilError;
    Check('blocked stdin times out', Pos('timed out', Transport.LastError) > 0);
    Start('closed'); PumpUntilFrame; Transport.Queue('{"id":3}'); PumpUntilError;
    Check('closed stdin cannot kill host with SIGPIPE', Pos('stdin closed', Transport.LastError) > 0);
    Start('blocked');
    For I := 1 To CodexMaxQueueFrames + 1 Do Transport.Queue('{}');
    Check('outgoing queue bounded', Pos('queue limit', Transport.LastError) > 0);
    Args.Clear;
    Check('missing executable fails', Not Transport.Start('/no/such/codex', GetTempDir, Args));
  Finally Transport.Free; Args.Free; End;
  WriteLn('All Codex transport tests passed.');
End.
