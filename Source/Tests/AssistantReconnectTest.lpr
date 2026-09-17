Program AssistantReconnectTest;
{$mode objfpc}{$H+}
Uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Forms, Classes, SysUtils,
  AssistantTestIDEHost, AssistantActor, AssistantHttps;
Type
  TFakeActor = Class(TAssistantActor)
  Public
    Attempts, Waits: Integer;
    Failure: String;
    RealWait, Ok: Boolean;
    Err: String;
    Function PostRound(Const Url, RequestJson, Headers: String;
      Control: THttpsStreamControl; Out Code: Integer; Out ErrorText: String): Boolean; Override;
    Function WaitForReconnect: Boolean; Override;
    Procedure Execute; Override;
  End;
Function TFakeActor.PostRound(Const Url, RequestJson, Headers: String;
  Control: THttpsStreamControl; Out Code: Integer; Out ErrorText: String): Boolean;
Begin
  Inc(Attempts);
  If RequestJson <> 'same request' Then raise Exception.Create('Request changed');
  Code := 200;
  ErrorText := '';
  If Attempts <= 5 Then
    Begin
      { A partial answer must not cause a failed stream to be accepted. }
      HttpsChunk('data: {"choices":[{"delta":{"content":"partial"}}]}' + #10#10);
      ErrorText := Failure;
      Result := Failure = '';
    End
  Else
    Begin
      HttpsChunk('data: {"choices":[{"delta":{"content":"recovered"}}]}' + #10#10);
      HttpsChunk('data: [DONE]' + #10#10);
      Result := True;
    End;
End;
Function TFakeActor.WaitForReconnect: Boolean;
Begin
  Inc(Waits);
  If RealWait Then Result := Inherited WaitForReconnect Else Result := True;
End;
Procedure TFakeActor.Execute;
Begin
  Ok := DoHttpRound('fixture', 'same request', Err);
End;
Procedure Check(Const Title: String; Value: Boolean);
Begin
  If Not Value Then Begin WriteLn(StdErr, 'FAIL ', Title); Halt(1); End;
  WriteLn('PASS ', Title);
End;
Procedure RunCase(Const Failure: String; Recover: Boolean);
Var A: TFakeActor;
Begin
  A := TFakeActor.Create(Nil, '', '', '', '', '', '', Nil);
  Try
    A.Failure := Failure;
    A.Start;
    A.WaitFor;
    Check('recovery outcome: ' + Failure, A.Ok = Recover);
    If Recover Then
      Check('continues beyond old retry cap', (A.Attempts = 6) And (A.Waits = 5))
    Else
      Check('permanent error remains visible', (A.Attempts = 1) And (A.Err = Failure));
  Finally A.Free; End;
End;
Var A: TFakeActor; Started: QWord;
Begin
  Application.Initialize;
  RunCase('Error reading data from socket', True);
  RunCase('Connection reset by peer', True);
  RunCase('', True);
  RunCase('HTTP 401: Unauthorized', False);
  A := TFakeActor.Create(Nil, '', '', '', '', '', '', Nil);
  Try
    A.Failure := 'Error reading data from socket';
    A.RealWait := True;
    A.Start;
    Sleep(200);
    Started := GetTickCount64;
    A.Cancel;
    A.WaitFor;
    Check('Stop interrupts reconnect wait promptly', GetTickCount64 - Started < 1000);
    Check('Stop prevents another request', (A.Attempts = 1) And (A.Waits = 1) And
      (Not A.Ok) And (A.Err = 'Cancelled.'));
  Finally A.Free; End;
End.
