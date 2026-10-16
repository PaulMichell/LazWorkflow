Program AssistantReconnectTest;
{$mode objfpc}{$H+}
Uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Forms, Classes, SysUtils, DateUtils,
  AssistantTestIDEHost, AssistantActor, AssistantHttps, AssistantConfig, AssistantAccountUsage, AssistantEvents;
Type
  TObserver = Class
    Calls: Integer;
    Notes: String;
    Procedure Token(Const Content, Thinking: String; Done: Boolean; Const ErrorText: String);
    Procedure Trace(Const Event: TAssistantEvent);
  End;
  TFakeActor = Class(TAssistantActor)
  Public
    Attempts, Waits: Integer;
    Failure, CreditBody, RetryHeader: String;
    StatusCode: Integer;
    RealWait, Ok: Boolean;
    Err: String;
    RecordedWait: QWord;
    Function PostRound(Const Url, RequestJson, Headers: String;
      Control: THttpsStreamControl; Out Code: Integer; Out ErrorText: String): Boolean; Override;
    Function WaitForReconnect: Boolean; Override;
    Procedure Execute; Override;
  End;
Procedure TObserver.Token(Const Content, Thinking: String; Done: Boolean; Const ErrorText: String);
Begin
  Inc(Calls);
  If Done And (Pos('credit', LowerCase(ErrorText)) > 0) Then
    Notes := Notes + 'FINISHED ' + ErrorText;
End;
Procedure TObserver.Trace(Const Event: TAssistantEvent);
Begin
  If Event.Kind = aekRecovery Then
    Notes := Notes + Event.Text + LineEnding;
End;
Function TFakeActor.PostRound(Const Url, RequestJson, Headers: String;
  Control: THttpsStreamControl; Out Code: Integer; Out ErrorText: String): Boolean;
Begin
  Inc(Attempts);
  If Assigned(Control) And (RetryHeader <> '') Then
    Control.ResponseRetryAfter := RetryHeader;
  If RequestJson <> 'same request' Then raise Exception.Create('Request changed');
  Code := 200;
  ErrorText := '';
  If (StatusCode <> 0) And (Attempts <= 5) Then
    Begin
      Code := StatusCode;
      ErrorText := '';
      HttpsChunk('{"error":"unavailable"}');
      Result := True;
      Exit;
    End;
  If CreditBody <> '' Then
    Begin
      If Attempts = 1 Then
        Begin
          Code := 402;
          ErrorText := 'insufficient credits';
          HttpsChunk(CreditBody);
          Result := False;
        End
      Else
        Begin
          HttpsChunk('data: {"choices":[{"delta":{"content":"recovered"}}]}' + #10#10);
          HttpsChunk('data: [DONE]' + #10#10);
          Result := True;
        End;
      Exit;
    End;
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
  If CurrentReconnectWaitMs > RecordedWait Then
    RecordedWait := CurrentReconnectWaitMs;
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
Procedure TestDetachedCallbacks;
Var A: TFakeActor; Observer: TObserver; Deadline: QWord;
Begin
  Observer := TObserver.Create;
  A := TFakeActor.Create(Nil, '', '', '', '', '', '', @Observer.Token);
  Try
    A.Failure := 'Error reading data from socket';
    A.Start;
    Deadline := GetTickCount64 + 5000;
    While (Not A.Finished) And (GetTickCount64 < Deadline) Do Sleep(5);
    Check('fake actor finished before view disposal', A.Finished);
    A.DetachCallbacks;
    A.WaitFor;
    CheckSynchronize;
    Check('queued stream callbacks cannot reach closed view', Observer.Calls = 0);
  Finally A.Free; Observer.Free; End;
End;
Var A: TFakeActor; Observer: TObserver; Started: QWord; ResetAt: TDateTime; Iso: String; Expected: Int64;
  Snapshot: TAccountUsageSnapshot;
Begin
  Application.Initialize;
  TestDetachedCallbacks;
  RunCase('Error reading data from socket', True);
  RunCase('Connection reset by peer', True);
  RunCase('', True);
  RunCase('HTTP 401: Unauthorized', False);
  RunCase('HTTP 503', True);
  A := TFakeActor.Create(Nil, '', '', '', '', '', '', Nil);
  Try
    A.StatusCode := 503;
    A.Start;
    A.WaitFor;
    Check('HTTP 503 status retries with no cap', A.Ok And (A.Attempts = 6) And (A.Waits = 5));
  Finally A.Free; End;
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
  If Assigned(AssistantChatConfig) Then
    Begin
      AssistantChatConfig.CreditRetryMinutes := 60;
      AssistantChatConfig.ReconnectIntervalSeconds := 30;
    End;
  A := TFakeActor.Create(Nil, '', '', '', '', '', '', Nil);
  Try
    A.CreditBody := '{"error":"insufficient credits"}';
    A.Start;
    A.WaitFor;
    Check('credit body with no reset uses the hourly interval', A.Ok And (A.Waits >= 1) And
      (A.RecordedWait = 60 * 60 * 1000));
  Finally A.Free; End;
  ResetAt := IncHour(Now, 3);
  Iso := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', LocalTimeToUniversal(ResetAt)) + 'Z';
  A := TFakeActor.Create(Nil, '', '', '', '', '', '', Nil);
  Try
    A.CreditBody := '{"error":"insufficient credits","resets_at":"' + Iso + '"}';
    A.Start;
    A.WaitFor;
    Expected := Round((ResetAt - Now) * 86400000);
    Check('credit body with a future reset waits until that time', A.Ok And (A.Waits >= 1) And
      (Abs(Int64(A.RecordedWait) - Expected) < 15000) And (A.RecordedWait > 2 * 60 * 60 * 1000));
  Finally A.Free; End;
  A := TFakeActor.Create(Nil, '', '', '', '', '', '', Nil);
  Try
    A.StatusCode := 402;
    A.Start;
    A.WaitFor;
    Check('HTTP 402 without credit words uses the hourly interval', A.Ok And (A.Attempts = 6) And (A.Waits = 5) And
      (A.RecordedWait = 60 * 60 * 1000));
  Finally A.Free; End;
  A := TFakeActor.Create(Nil, '', '', '', '', '', '', Nil);
  Try
    A.StatusCode := 429;
    A.Start;
    A.WaitFor;
    Check('short 429 without Retry-After uses the connection interval', A.Ok And (A.Attempts = 6) And
      (A.Waits = 5) And (A.RecordedWait = 30 * 1000));
  Finally A.Free; End;
  A := TFakeActor.Create(Nil, '', '', '', '', '', '', Nil);
  Try
    A.StatusCode := 429;
    A.RetryHeader := '12';
    A.Start;
    A.WaitFor;
    Check('short 429 waits for Retry-After', A.Ok And (A.Waits >= 1) And (A.RecordedWait = 12 * 1000));
  Finally A.Free; End;
  ResetAt := IncHour(Now, 2);
  Snapshot.Known := True;
  Snapshot.ConnectionId := 'credit-wait';
  Snapshot.Caption := 'Credits used: 100%';
  Snapshot.Hint := 'do not scrape this hint';
  Snapshot.FetchedAt := Now;
  Snapshot.HasReset := True;
  Snapshot.ResetsAt := ResetAt;
  PublishAccountUsageSnapshot(Snapshot);
  Observer := TObserver.Create;
  A := TFakeActor.Create(Nil, '', '', '', '', '', '', @Observer.Token);
  Try
    A.OnTrace := @Observer.Trace;
    A.CreditBody := '{"error":"insufficient credits"}';
    A.Start;
    A.WaitFor;
    CheckSynchronize;
    Expected := Round((ResetAt - Now) * 86400000);
    Check('credit body with no reset uses the usage snapshot', A.Ok And (A.Waits >= 1) And
      (Abs(Int64(A.RecordedWait) - Expected) < 15000) And (A.RecordedWait > 90 * 60 * 1000));
    Check('credit wait says the clock time', Pos('Retry at ' + FormatDateTime('yyyy-mm-dd hh:nn', ResetAt),
      Observer.Notes) > 0);
    Check('credit wait does not finish the reply', Pos('FINISHED', Observer.Notes) = 0);
  Finally A.Free; Observer.Free; End;
End.
