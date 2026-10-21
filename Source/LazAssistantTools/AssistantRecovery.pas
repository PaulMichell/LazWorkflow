Unit AssistantRecovery;

{ Fault classification for an assistant turn (c) 2026 Michell Computing.

  Owns the decision to ignore, retry, continue, or stop. Callers log with
  ReportPluginException and do not copy this policy. A disconnect is retried
  without the fault-retry cap; the HTTP round still owns that wait. A credit
  failure waits until reset, or the credit interval, and is not the reconnect
  interval. A dropped Codex or Claude process uses those same waits. It does
  not parse Codex frames. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Const
  { Fault retries per action until the setting in the recovery plan is snapshotted. }
  DefaultFaultRetryCap = 1;
  { Reconnect interval until item 5.1 stores the setting. Snapshotted when the turn starts. }
  DefaultReconnectIntervalSeconds = 30;
  { Credit retry when the reset is unknown, until item 5.1 stores the setting. }
  DefaultCreditIntervalMinutes = 60;
  { Stable phrases. IsAssistantProgressStatus matches these so a late snapshot is not an error. }
  AssistantRecoveryRetryHttp = 'Retrying the HTTP round.';
  AssistantRecoveryRetryTool = 'Retrying the read-only tool.';
  AssistantRecoveryHandBackTool = 'Handing the tool error back to the model.';
  AssistantRecoveryIgnorePaint = 'Ignoring a paint fault.';
  AssistantRecoveryIgnoreCallback = 'Ignoring a callback after detach.';
  AssistantRecoveryWaitReconnect = 'Waiting to reconnect.';
  AssistantRecoveryWaitCredits = 'Waiting for credits.';
  AssistantRecoveryWaitRateLimit = 'Waiting for the rate limit.';
  AssistantRecoveryResumeCall = 'Resuming the call.';

Type
  TAssistantRecoveryAction = (
    araIgnore,
    araRetryLastAction,
    araContinueTurn,
    araStop
  );

  TAssistantFaultOrigin = (
    afoCancel,
    afoCallbackAfterDetach,
    afoPaintLayout,
    afoHttpRound,
    afoTool,
    afoTurn
  );

  TAssistantFault = Record
    Origin: TAssistantFaultOrigin;
    Area: String;
    ToolName: String;
    ErrorClass: String;
    ErrorText: String;
    HttpStatus: Integer;
    Attempt: Integer;
    AttemptCap: Integer;
    UserStopped: Boolean;
    ServiceGone: Boolean;
    OwnsTurn: Boolean;
    Detached: Boolean;
    { Raw response body. Credit words may be here when the status line is only a code. }
    ResponseBody: String;
  End;

  { How long an HTTP retry waits. None uses the fault-retry cap and does not sleep. }
  TAssistantHttpWait = (
    ahwNone,
    ahwConnection,
    ahwRateLimit,
    ahwCredits
  );

  TAssistantRecovery = Record
    Action: TAssistantRecoveryAction;
    { True only for a disconnect retry. The fault-retry cap does not apply. }
    WaitForConnection: Boolean;
    HttpWait: TAssistantHttpWait;
  End;

Function DefaultAssistantFault: TAssistantFault;
Function ClassifyAssistantFault(Const Fault: TAssistantFault): TAssistantRecovery;
{ Tool result text. Names the area and the exception class. Not the log line. }
Function AssistantRecoveryToolError(Const Area, ErrorClass, ErrorText: String): String;
{ One conversation note. Area, exception class, message, and that the task has stopped.
  No tool arguments and no follow-up recipe. }
Function AssistantRecoveryStopNote(Const Area, ErrorClass, ErrorText: String): String;
{ Write, replace, git, and compile are not read-only, so a fault there is not replayed. }
Function AssistantToolIsReadOnly(Const ToolName: String): Boolean;
Function AssistantServiceGoneText: String;
{ One conversation sentence for ignore, retry, or continue. Names the fault and the resolution.
  The status phase uses the same sentence. Empty for a terminal stop. }
Function AssistantRecoveryProgressNote(Action: TAssistantRecoveryAction; Origin: TAssistantFaultOrigin;
  Const Area, ErrorClass, ErrorText: String): String;
{ True when Text is a recovery sentence. A late snapshot must not be stored as an error. }
Function IsAssistantRecoveryProgress(Const Text: String): Boolean;
{ Phrase list formerly in the actor. Connection-loss widening stays here. }
Function AssistantFaultIsDisconnect(Const ErrorText: String): Boolean;
Function IsTransientNetworkError(Const ErrorText: String): Boolean;
{ Milliseconds. The actor snapshots this when the turn starts. }
Function AssistantReconnectIntervalMs: QWord;
{ Milliseconds. The actor snapshots this when the turn starts. }
Function AssistantCreditIntervalMs: QWord;
{ Negative means the caller did not set a cap, so the stored setting or the default is used.
  Zero is a real setting: no extra retry. }
Function AssistantFaultRetryCap(Requested: Integer): Integer;
{ True for HTTP 402, or when the status text or body names a credit failure.
  A short 429 without those words is not this case. }
Function AssistantFaultIsOutOfCredits(Const Fault: TAssistantFault): Boolean;
{ Future reset from error JSON, a Retry-After clock time, then the usage snapshot. 0 if none. }
Function AssistantCreditResetTime(Const ErrorText, Body, RetryAfter: String; UsageHasReset: Boolean;
  UsageResetsAt, NowTime: TDateTime): TDateTime;
{ Milliseconds until RetryAt. RetryAt is the reset, or now plus the credit interval. }
Function AssistantCreditWaitMs(Const ErrorText, Body, RetryAfter: String; UsageHasReset: Boolean;
  UsageResetsAt: TDateTime; CreditIntervalMs: QWord; NowTime: TDateTime; Out RetryAt: TDateTime): QWord;
Function AssistantCreditWaitNote(Const ErrorText: String; RetryAt: TDateTime): String;
{ Retry-After delay or clock, otherwise the connection interval. }
Function AssistantRateLimitWaitMs(Const RetryAfter: String; ConnectionIntervalMs: QWord; NowTime: TDateTime): QWord;
Function AssistantRateLimitWaitNote(Const ErrorText: String): String;
Function AssistantReconnectWaitNote(Const ErrorText: String): String;
Function AssistantReconnectResumeNote: String;
Function AssistantPhaseIsReconnectWait(Const Phase: String): Boolean;
{ Codex or Claude process ended before an assistant answer. Credit, rate limit,
  and transport drops use the HTTP waits. Protocol, sign-in, and cancel stop.
  An empty error is not a drop: a completed turn can have no error text. }
Function ClassifyDroppedTransport(Const ErrorText, ResponseBody: String; UserStopped: Boolean): TAssistantRecovery;
{ Milliseconds for that decision. RetryAt is set for a credit reset. }
Function AssistantDroppedTransportWaitMs(Kind: TAssistantHttpWait; Const ErrorText, Body, RetryAfter: String;
  UsageHasReset: Boolean; UsageResetsAt: TDateTime; ConnectionIntervalMs, CreditIntervalMs: QWord;
  NowTime: TDateTime; Out RetryAt: TDateTime): QWord;
Function AssistantDroppedTransportWaitNote(Kind: TAssistantHttpWait; Const ErrorText: String;
  RetryAt: TDateTime): String;

Implementation

Uses
  SysUtils, DateUtils, fpjson, jsonparser, AssistantConfig;

Function OneLineFault(Const Text: String): String; Forward;

Const
  UnixSecondsFloor = 1000000000;
  UnixMillisecondsFloor = 100000000000;
  RateLimitDelayCapSeconds = 7 * 24 * 60 * 60;

Function NextToken(Const Text: String; Var At: Integer): String;
Var
  StartAt: Integer;
Begin
  While (At <= Length(Text)) And (Text[At] <= ' ') Do
    Inc(At);
  StartAt := At;
  While (At <= Length(Text)) And (Text[At] > ' ') Do
    Inc(At);
  Result := Copy(Text, StartAt, At - StartAt);
End;

Function MonthIndex(Const Name: String): Integer;
Const
  Names: Array[1..12] Of String = (
    'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec');
Var
  I: Integer;
  Key: String;
Begin
  Result := 0;
  Key := LowerCase(Copy(Trim(Name), 1, 3));
  For I := 1 To 12 Do
    If Names[I] = Key Then
      Exit(I);
End;

Function TryHttpDate(Const Text: String; Out When: TDateTime): Boolean;
Var
  S, Token, TimeText: String;
  At, Day, Month, Year, Hour, Minute, Second, Colon: Integer;
Begin
  Result := False;
  When := 0;
  S := Trim(Text);
  Colon := Pos(',', S);
  If Colon > 0 Then
    S := Trim(Copy(S, Colon + 1, MaxInt));
  At := 1;
  Token := NextToken(S, At);
  Day := StrToIntDef(Token, 0);
  Month := MonthIndex(NextToken(S, At));
  Year := StrToIntDef(NextToken(S, At), 0);
  TimeText := NextToken(S, At);
  If (Day < 1) Or (Day > 31) Or (Month < 1) Or (Year < 1970) Or (TimeText = '') Then
    Exit;
  Colon := Pos(':', TimeText);
  If Colon < 2 Then
    Exit;
  Hour := StrToIntDef(Copy(TimeText, 1, Colon - 1), -1);
  Minute := StrToIntDef(Copy(TimeText, Colon + 1, 2), -1);
  Second := 0;
  If (Colon + 3 <= Length(TimeText)) And (TimeText[Colon + 3] = ':') Then
    Second := StrToIntDef(Copy(TimeText, Colon + 4, 2), 0);
  If (Hour < 0) Or (Hour > 23) Or (Minute < 0) Or (Minute > 59) Or (Second < 0) Or (Second > 59) Then
    Exit;
  Try
    When := EncodeDate(Year, Month, Day) + EncodeTime(Hour, Minute, Second, 0);
    When := UniversalTimeToLocal(When);
    Result := When > 0;
  Except
    On E: Exception Do
      Result := False;
  End;
End;

Function TryIsoClock(Const Text: String; Out When: TDateTime): Boolean;
Var
  S: String;
  DotAt, I: Integer;
Begin
  Result := False;
  When := 0;
  S := Trim(Text);
  If S = '' Then
    Exit;
  DotAt := Pos('.', S);
  If DotAt >= 11 Then
    Begin
      I := DotAt + 1;
      While (I <= Length(S)) And (S[I] In ['0'..'9']) Do
        Inc(I);
      Delete(S, DotAt, I - DotAt);
    End;
  Try
    When := UniversalTimeToLocal(ISO8601ToDate(S, True));
    Result := When > 0;
  Except
    On E: Exception Do
      Result := False;
  End;
End;

Function TryClockTime(Const Text: String; Out When: TDateTime): Boolean;
Begin
  Result := TryIsoClock(Text, When) Or TryHttpDate(Text, When);
End;

Function UnixSecondsToLocal(Seconds: Int64): TDateTime;
Begin
  { The one-argument UnixToDateTime returns UTC. Waits compare with local Now. }
  Result := UnixToDateTime(Seconds, False);
End;

Function UnixNumberToLocal(Value: Double; AllowDelay: Boolean; NowTime: TDateTime; Out When: TDateTime): Boolean;
Var
  Seconds: Int64;
Begin
  Result := False;
  When := 0;
  If Value <= 0 Then
    Exit;
  If Value >= UnixMillisecondsFloor Then
    Seconds := Round(Value / 1000)
  Else If Value >= UnixSecondsFloor Then
    Seconds := Round(Value)
  Else If AllowDelay Then
    Begin
      When := NowTime + (Value / 86400);
      Exit(When > NowTime);
    End
  Else
    Exit;
  If Seconds <= 0 Then
    Exit;
  When := UnixSecondsToLocal(Seconds);
  Result := When > 0;
End;

Function ResetFromJsonValue(Node: TJSONData; AllowDelay: Boolean; NowTime: TDateTime; Out When: TDateTime): Boolean;
Var
  Number: Double;
  Text: String;
Begin
  Result := False;
  When := 0;
  If Not Assigned(Node) Or (Node.JSONType = jtNull) Then
    Exit;
  If Node.JSONType = jtNumber Then
    Exit(UnixNumberToLocal(Node.AsFloat, AllowDelay, NowTime, When));
  If Node.JSONType <> jtString Then
    Exit;
  Text := Trim(Node.AsString);
  If Text = '' Then
    Exit;
  If TryClockTime(Text, When) And (When > 0) Then
    Exit(True);
  If TryStrToFloat(Text, Number) Or TryStrToFloat(StringReplace(Text, ',', '.', []), Number) Then
    Result := UnixNumberToLocal(Number, AllowDelay, NowTime, When);
End;

Function FindDeep(Node: TJSONData; Const Name: String): TJSONData;
Var
  Obj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
Begin
  Result := Nil;
  If Not Assigned(Node) Then
    Exit;
  If Node Is TJSONObject Then
    Begin
      Obj := TJSONObject(Node);
      For I := 0 To Obj.Count - 1 Do
        If SameText(Obj.Names[I], Name) Then
          Exit(Obj.Items[I]);
      For I := 0 To Obj.Count - 1 Do
        Begin
          Result := FindDeep(Obj.Items[I], Name);
          If Assigned(Result) Then
            Exit;
        End;
    End
  Else If Node Is TJSONArray Then
    Begin
      Arr := TJSONArray(Node);
      For I := 0 To Arr.Count - 1 Do
        Begin
          Result := FindDeep(Arr.Items[I], Name);
          If Assigned(Result) Then
            Exit;
        End;
    End;
End;

Function JsonObjectSlice(Const Text: String): String;
Var
  StartAt, EndAt, I: Integer;
Begin
  Result := '';
  StartAt := Pos('{', Text);
  EndAt := 0;
  For I := Length(Text) DownTo 1 Do
    If Text[I] = '}' Then
      Begin
        EndAt := I;
        Break;
      End;
  If (StartAt > 0) And (EndAt > StartAt) Then
    Result := Copy(Text, StartAt, EndAt - StartAt + 1);
End;

Function ResetFromDocument(Node: TJSONData; NowTime: TDateTime; Out When: TDateTime): Boolean;
Const
  Names: Array[0..5] Of String = (
    'resets_at', 'resetsAt', 'reset_at', 'resetAt', 'retry_after', 'retryAfter');
Var
  I: Integer;
  Found: TJSONData;
  AllowDelay: Boolean;
Begin
  Result := False;
  When := 0;
  For I := 0 To High(Names) Do
    Begin
      Found := FindDeep(Node, Names[I]);
      If Not Assigned(Found) Then
        Continue;
      AllowDelay := SameText(Names[I], 'retry_after') Or SameText(Names[I], 'retryAfter');
      If ResetFromJsonValue(Found, AllowDelay, NowTime, When) And (When > NowTime) Then
        Exit(True);
    End;
End;

Function JsonResetTime(Const Text: String; NowTime: TDateTime; Out When: TDateTime): Boolean;
Var
  Data: TJSONData;
  Slice: String;
Begin
  Result := False;
  When := 0;
  Slice := JsonObjectSlice(Text);
  If Slice = '' Then
    Exit;
  Data := Nil;
  Try
    Try
      Data := GetJSON(Slice);
    Except
      On E: Exception Do
        Data := Nil;
    End;
    If Assigned(Data) Then
      Result := ResetFromDocument(Data, NowTime, When);
  Finally
    Data.Free;
  End;
End;

Function RetryAfterFutureTime(Const Header: String; NowTime: TDateTime; Out When: TDateTime): Boolean;
Var
  Text: String;
Begin
  Result := False;
  When := 0;
  Text := Trim(Header);
  If Text = '' Then
    Exit;
  { A bare delay is not a clock time. Credit waits use it only from JSON retry_after. }
  If (Pos(':', Text) = 0) And (Pos('-', Text) = 0) And (Pos(',', Text) = 0) Then
    Exit;
  Result := TryClockTime(Text, When) And (When > NowTime);
End;

Function AssistantCreditResetTime(Const ErrorText, Body, RetryAfter: String; UsageHasReset: Boolean;
  UsageResetsAt, NowTime: TDateTime): TDateTime;
Var
  Found: TDateTime;
Begin
  Result := 0;
  If JsonResetTime(Body, NowTime, Found) And (Found > NowTime) Then
    Exit(Found);
  If JsonResetTime(ErrorText, NowTime, Found) And (Found > NowTime) Then
    Exit(Found);
  If RetryAfterFutureTime(RetryAfter, NowTime, Found) Then
    Exit(Found);
  If UsageHasReset And (UsageResetsAt > NowTime) Then
    Result := UsageResetsAt;
End;

Function AssistantCreditWaitMs(Const ErrorText, Body, RetryAfter: String; UsageHasReset: Boolean;
  UsageResetsAt: TDateTime; CreditIntervalMs: QWord; NowTime: TDateTime; Out RetryAt: TDateTime): QWord;
Var
  ResetAt: TDateTime;
  Delta: Double;
Begin
  If CreditIntervalMs = 0 Then
    CreditIntervalMs := AssistantCreditIntervalMs;
  ResetAt := AssistantCreditResetTime(ErrorText, Body, RetryAfter, UsageHasReset, UsageResetsAt, NowTime);
  If ResetAt > NowTime Then
    Begin
      RetryAt := ResetAt;
      Delta := (ResetAt - NowTime) * 86400000;
      If Delta < 1 Then
        Delta := 1;
      If Delta > High(Int64) Then
        Result := High(Int64)
      Else
        Result := Round(Delta);
    End
  Else
    Begin
      Result := CreditIntervalMs;
      If Result < 1 Then
        Result := 1;
      RetryAt := NowTime + (Result / 86400000);
    End;
End;

Function AssistantCreditWaitNote(Const ErrorText: String; RetryAt: TDateTime): String;
Var
  Detail: String;
Begin
  Detail := OneLineFault(ErrorText);
  If Detail = '' Then
    Result := 'Out of credits. ' + AssistantRecoveryWaitCredits
  Else
    Result := 'Out of credits: ' + Detail + '. ' + AssistantRecoveryWaitCredits;
  If RetryAt > 0 Then
    Result := Result + ' Retry at ' + FormatDateTime('yyyy-mm-dd hh:nn', RetryAt) + '.';
End;

Function MillisecondsUntil(When, NowTime: TDateTime): QWord;
Var
  Delta: Double;
Begin
  Result := 0;
  If When <= NowTime Then
    Exit;
  Delta := (When - NowTime) * 86400000;
  If Delta < 1 Then
    Delta := 1;
  If Delta > High(Int64) Then
    Result := High(Int64)
  Else
    Result := Round(Delta);
End;

Function AssistantRateLimitWaitMs(Const RetryAfter: String; ConnectionIntervalMs: QWord; NowTime: TDateTime): QWord;
Var
  Text: String;
  Seconds: Int64;
  Number: Double;
  When: TDateTime;
Begin
  If ConnectionIntervalMs = 0 Then
    ConnectionIntervalMs := AssistantReconnectIntervalMs;
  Result := ConnectionIntervalMs;
  Text := Trim(RetryAfter);
  If Text = '' Then
    Exit;
  If TryStrToInt64(Text, Seconds) Or (TryStrToFloat(Text, Number) And (Number > 0) And (Round(Number) = Number)) Then
    Begin
      If Not TryStrToInt64(Text, Seconds) Then
        Seconds := Round(Number);
      If (Seconds > 0) And (Seconds <= RateLimitDelayCapSeconds) Then
        Result := QWord(Seconds) * 1000
      Else If Seconds >= UnixSecondsFloor Then
        Begin
          When := UnixSecondsToLocal(Seconds);
          If When > NowTime Then
            Result := MillisecondsUntil(When, NowTime);
        End;
      If Result = 0 Then
        Result := ConnectionIntervalMs;
      Exit;
    End;
  If TryClockTime(Text, When) And (When > NowTime) Then
    Begin
      Result := MillisecondsUntil(When, NowTime);
      If Result = 0 Then
        Result := ConnectionIntervalMs;
    End;
End;

Function AssistantRateLimitWaitNote(Const ErrorText: String): String;
Var
  Detail: String;
Begin
  Detail := OneLineFault(ErrorText);
  If Detail = '' Then
    Result := 'Rate limited. ' + AssistantRecoveryWaitRateLimit
  Else
    Result := 'Rate limited: ' + Detail + '. ' + AssistantRecoveryWaitRateLimit;
End;

Function DefaultAssistantFault: TAssistantFault;
Begin
  Result := Default(TAssistantFault);
  Result.Attempt := 1;
  { Negative means the caller did not set a cap. Zero is a real setting. }
  Result.AttemptCap := -1;
End;

Function AssistantFaultRetryCap(Requested: Integer): Integer;
Begin
  If Requested < 0 Then
    Begin
      If Assigned(AssistantChatConfig) Then
        Result := AssistantChatConfig.FaultRetries
      Else
        Result := DefaultFaultRetryCap;
    End
  Else
    Result := Requested;
End;

Function StatusCodeAfter(Const Lowered, Marker: String): Integer;
Var
  At, Code: Integer;
Begin
  Result := 0;
  At := Pos(Marker, Lowered);
  If At < 1 Then
    Exit;
  At := At + Length(Marker);
  While (At <= Length(Lowered)) And (Lowered[At] In [' ', ':']) Do
    Inc(At);
  Code := 0;
  While (At <= Length(Lowered)) And (Lowered[At] In ['0'..'9']) Do
    Begin
      Code := Code * 10 + (Ord(Lowered[At]) - Ord('0'));
      Inc(At);
    End;
  If (Code >= 100) And (Code <= 599) Then
    Result := Code;
End;

Function HttpStatusInText(Const ErrorText: String): Integer;
Var
  Lowered: String;
Begin
  Lowered := LowerCase(ErrorText);
  Result := StatusCodeAfter(Lowered, 'http ');
  { fphttpclient raises "Unexpected response status code: 402" and leaves the Out code at 0. }
  If Result = 0 Then
    Result := StatusCodeAfter(Lowered, 'status code');
End;

Function StatusIs(Const Fault: TAssistantFault; Wanted: Integer): Boolean;
Begin
  Result := (Fault.HttpStatus = Wanted) Or (HttpStatusInText(Fault.ErrorText) = Wanted);
End;

Function IsGatewayStatus(Code: Integer): Boolean;
Begin
  Result := (Code = 502) Or (Code = 503) Or (Code = 504);
End;

Function IsTransientNetworkError(Const ErrorText: String): Boolean;
Var
  Lowered: String;
Begin
  { An empty socket close has no message. Cancelled. is not empty. }
  If Trim(ErrorText) = '' Then
    Exit(True);
  Lowered := LowerCase(ErrorText);
  Result :=
    IsGatewayStatus(HttpStatusInText(ErrorText)) Or
    (Pos('host name resolution', Lowered) > 0) Or
    (Pos('could not resolve', Lowered) > 0) Or
    (Pos('name or service not known', Lowered) > 0) Or
    (Pos('temporary failure in name resolution', Lowered) > 0) Or
    (Pos('network is unreachable', Lowered) > 0) Or
    (Pos('no route to host', Lowered) > 0) Or
    (Pos('host is unreachable', Lowered) > 0) Or
    (Pos('host unreachable', Lowered) > 0) Or
    (Pos('could not connect', Lowered) > 0) Or
    (Pos('connection refused', Lowered) > 0) Or
    (Pos('connection reset', Lowered) > 0) Or
    (Pos('connection abort', Lowered) > 0) Or
    (Pos('forcibly closed', Lowered) > 0) Or
    (Pos('peer closed', Lowered) > 0) Or
    (Pos('server closed', Lowered) > 0) Or
    (Pos('socket closed', Lowered) > 0) Or
    (Pos('socket close', Lowered) > 0) Or
    (Pos('timed out', Lowered) > 0) Or
    (Pos('timeout', Lowered) > 0) Or
    (Pos('socket error', Lowered) > 0) Or
    (Pos('error reading data from socket', Lowered) > 0) Or
    (Pos('error writing data to socket', Lowered) > 0) Or
    (Pos('broken pipe', Lowered) > 0) Or
    (Pos('connection closed', Lowered) > 0) Or
    (Pos('unexpected eof', Lowered) > 0) Or
    (Pos('end of file', Lowered) > 0) Or
    (Pos('empty reply', Lowered) > 0) Or
    (Pos('response stream ended before completion', Lowered) > 0) Or
    (Pos('wininet internetopen failed', Lowered) > 0) Or
    (Pos('wininet internetconnect failed', Lowered) > 0) Or
    (Pos('wininet httpopenrequest failed', Lowered) > 0) Or
    (Pos('wininet httpsendrequest failed', Lowered) > 0) Or
    (Pos('wininet internetreadfile failed', Lowered) > 0);
End;

Function AssistantFaultIsDisconnect(Const ErrorText: String): Boolean;
Begin
  Result := IsTransientNetworkError(ErrorText);
End;

Function FaultIsCancel(Const Fault: TAssistantFault): Boolean;
Begin
  Result := (Fault.Origin = afoCancel) Or
    (Fault.ErrorClass = 'EAbort') Or
    (Trim(Fault.ErrorText) = 'Cancelled.');
End;

Function FaultIsMalformedRequest(Const Fault: TAssistantFault): Boolean;
Var
  Lowered: String;
Begin
  If AssistantFaultIsDisconnect(Fault.ErrorText) Then
    Exit(False);
  If StatusIs(Fault, 400) Or StatusIs(Fault, 422) Then
    Exit(True);
  Lowered := LowerCase(Fault.ErrorText);
  Result :=
    (Pos('malformed', Lowered) > 0) Or
    (Pos('bad request', Lowered) > 0) Or
    (Pos('invalid request', Lowered) > 0) Or
    (Pos('invalid json', Lowered) > 0) Or
    (Pos('could not parse', Lowered) > 0) Or
    (Pos('unexpected token', Lowered) > 0) Or
    (Pos('missing required', Lowered) > 0);
End;

Function AssistantToolIsReadOnly(Const ToolName: String): Boolean;
Var
  Name: String;
Begin
  Name := LowerCase(Trim(ToolName));
  Result := (Name = 'read_file') Or (Name = 'read_image') Or (Name = 'list_directory') Or
    (Name = 'grep') Or (Name = 'search_in_project') Or (Name = 'get_project_info') Or
    (Name = 'get_active_plan') Or (Name = 'list_plans') Or (Name = 'read_skill') Or
    (Name = 'open_file') Or (Name = 'open_markdown') Or
    (Name = 'find_declaration') Or (Name = 'symbol_context') Or (Name = 'find_references');
End;

Function Recovery(Action: TAssistantRecoveryAction; WaitForConnection: Boolean;
  HttpWait: TAssistantHttpWait = ahwNone): TAssistantRecovery;
Begin
  Result.Action := Action;
  Result.WaitForConnection := WaitForConnection;
  If WaitForConnection And (HttpWait = ahwNone) Then
    Result.HttpWait := ahwConnection
  Else
    Result.HttpWait := HttpWait;
End;

Function CreditScanText(Const Text: String): String;
Begin
  Result := LowerCase(Text);
  Result := StringReplace(Result, '_', ' ', [rfReplaceAll]);
  Result := StringReplace(Result, '-', ' ', [rfReplaceAll]);
End;

Function TextSaysOutOfCredits(Const Text: String): Boolean;
Var
  Lowered: String;
Begin
  Lowered := CreditScanText(Text);
  Result :=
    (Pos('credits', Lowered) > 0) Or
    (Pos('quota', Lowered) > 0) Or
    (Pos('spending', Lowered) > 0) Or
    (Pos('billing', Lowered) > 0) Or
    (Pos('insufficient credit', Lowered) > 0);
End;

Function AssistantFaultIsOutOfCredits(Const Fault: TAssistantFault): Boolean;
Begin
  Result := StatusIs(Fault, 402) Or TextSaysOutOfCredits(Fault.ErrorText) Or
    TextSaysOutOfCredits(Fault.ResponseBody);
End;

Function ClassifyAssistantFault(Const Fault: TAssistantFault): TAssistantRecovery;
Var
  Cap, Attempt: Integer;
  ReadOnlyTool: Boolean;
Begin
  Result := Recovery(araStop, False);
  If Fault.Detached Or (Fault.Origin = afoCallbackAfterDetach) Then
    Exit(Recovery(araIgnore, False));
  If (Fault.Origin = afoPaintLayout) And (Not Fault.OwnsTurn) Then
    Exit(Recovery(araIgnore, False));
  If (Not Fault.UserStopped) And FaultIsCancel(Fault) Then
    Exit(Recovery(araIgnore, False));
  If Fault.UserStopped And Fault.OwnsTurn Then
    Exit(Recovery(araStop, False));
  If Fault.ServiceGone And Fault.OwnsTurn Then
    Exit(Recovery(araStop, False));
  If StatusIs(Fault, 401) Then
    Exit(Recovery(araStop, False));
  { Before a malformed stop: a 400 body that names quota is out of credits, not a bad request. }
  If (Fault.Origin = afoHttpRound) And AssistantFaultIsOutOfCredits(Fault) Then
    Exit(Recovery(araRetryLastAction, False, ahwCredits));
  If (Fault.Origin = afoHttpRound) And StatusIs(Fault, 429) Then
    Exit(Recovery(araRetryLastAction, False, ahwRateLimit));
  If FaultIsMalformedRequest(Fault) Then
    Exit(Recovery(araStop, False));

  Cap := AssistantFaultRetryCap(Fault.AttemptCap);
  Attempt := Fault.Attempt;
  If Attempt < 1 Then
    Attempt := 1;

  If Fault.Origin = afoHttpRound Then
    Begin
      { Lost connection, including 502/503/504. No attempt cap. 401 already stopped above. }
      If IsTransientNetworkError(Fault.ErrorText) Or IsGatewayStatus(Fault.HttpStatus) Then
        Exit(Recovery(araRetryLastAction, True));
      If Attempt > Cap Then
        Exit(Recovery(araStop, False));
      Exit(Recovery(araRetryLastAction, False));
    End;

  If Fault.Origin = afoTool Then
    Begin
      ReadOnlyTool := AssistantToolIsReadOnly(Fault.ToolName);
      If ReadOnlyTool And (Attempt <= Cap) Then
        Exit(Recovery(araRetryLastAction, False));
      If ReadOnlyTool Then
        Exit(Recovery(araStop, False));
      { A mutating tool, including an access violation inside the tool call, is handed back. }
      Exit(Recovery(araContinueTurn, False));
    End;

  If Fault.OwnsTurn Then
    Exit(Recovery(araStop, False));
  Result := Recovery(araIgnore, False);
End;

Function AssistantRecoveryToolError(Const Area, ErrorClass, ErrorText: String): String;
Begin
  Result := Trim(Area);
  If Result = '' Then
    Result := 'tool';
  If Trim(ErrorClass) <> '' Then
    Result := Result + ': ' + Trim(ErrorClass);
  If Trim(ErrorText) <> '' Then
    Result := Result + ': ' + Trim(ErrorText);
End;

Function AssistantServiceGoneText: String;
Begin
  Result := 'The assistant service is gone.';
End;

Function AssistantRecoveryStopNote(Const Area, ErrorClass, ErrorText: String): String;
Var
  AreaText, ClassText, MessageText: String;
Begin
  AreaText := Trim(Area);
  If AreaText = '' Then
    AreaText := 'assistant';
  ClassText := Trim(ErrorClass);
  If ClassText = '' Then
    ClassText := 'Exception';
  MessageText := Trim(ErrorText);
  MessageText := StringReplace(MessageText, #13, ' ', [rfReplaceAll]);
  MessageText := StringReplace(MessageText, #10, ' ', [rfReplaceAll]);
  If MessageText = '' Then
    MessageText := '(none)';
  Result := 'The task has stopped. Area: ' + AreaText + '. Exception: ' + ClassText + '. Message: ' + MessageText + '.';
End;

Function OneLineFault(Const Text: String): String;
Begin
  Result := Trim(Text);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
End;

Function RecoveryPhrase(Action: TAssistantRecoveryAction; Origin: TAssistantFaultOrigin): String;
Begin
  Case Action Of
    araRetryLastAction:
      If Origin = afoTool Then
        Result := AssistantRecoveryRetryTool
      Else
        Result := AssistantRecoveryRetryHttp;
    araContinueTurn:
      Result := AssistantRecoveryHandBackTool;
    araIgnore:
      If Origin = afoCallbackAfterDetach Then
        Result := AssistantRecoveryIgnoreCallback
      Else If Origin = afoPaintLayout Then
        Result := AssistantRecoveryIgnorePaint
      Else
        Result := '';
  Else
    Result := '';
  End;
End;

Function AssistantRecoveryProgressNote(Action: TAssistantRecoveryAction; Origin: TAssistantFaultOrigin;
  Const Area, ErrorClass, ErrorText: String): String;
Var
  Phrase, FaultText, Detail: String;
Begin
  Phrase := RecoveryPhrase(Action, Origin);
  If Phrase = '' Then
    Exit('');
  FaultText := Trim(ErrorClass);
  If FaultText = '' Then
    FaultText := Trim(Area);
  Detail := OneLineFault(ErrorText);
  If Detail <> '' Then
    Begin
      If FaultText <> '' Then
        FaultText := FaultText + ': ' + Detail
      Else
        FaultText := Detail;
    End;
  If FaultText = '' Then
    Result := Phrase
  Else
    Result := FaultText + '. ' + Phrase;
End;

Function IsAssistantRecoveryProgress(Const Text: String): Boolean;
Var
  S: String;
Begin
  S := Trim(Text);
  Result :=
    (Pos(AssistantRecoveryRetryHttp, S) > 0) Or
    (Pos(AssistantRecoveryRetryTool, S) > 0) Or
    (Pos(AssistantRecoveryHandBackTool, S) > 0) Or
    (Pos(AssistantRecoveryIgnorePaint, S) > 0) Or
    (Pos(AssistantRecoveryIgnoreCallback, S) > 0) Or
    (Pos(AssistantRecoveryWaitReconnect, S) > 0) Or
    (Pos(AssistantRecoveryWaitCredits, S) > 0) Or
    (Pos(AssistantRecoveryWaitRateLimit, S) > 0) Or
    (Pos(AssistantRecoveryResumeCall, S) > 0);
End;

Function AssistantReconnectIntervalMs: QWord;
Var
  Seconds: Integer;
Begin
  If Assigned(AssistantChatConfig) Then
    Seconds := AssistantChatConfig.ReconnectIntervalSeconds
  Else
    Seconds := DefaultReconnectIntervalSeconds;
  Result := QWord(Seconds) * 1000;
End;

Function AssistantCreditIntervalMs: QWord;
Var
  Minutes: Integer;
Begin
  If Assigned(AssistantChatConfig) Then
    Minutes := AssistantChatConfig.CreditRetryMinutes
  Else
    Minutes := DefaultCreditIntervalMinutes;
  Result := QWord(Minutes) * 60 * 1000;
End;

Function AssistantReconnectWaitNote(Const ErrorText: String): String;
Var
  Detail: String;
Begin
  Detail := OneLineFault(ErrorText);
  If Detail = '' Then
    Result := 'Connection lost. ' + AssistantRecoveryWaitReconnect
  Else
    Result := 'Connection lost: ' + Detail + '. ' + AssistantRecoveryWaitReconnect;
End;

Function AssistantReconnectResumeNote: String;
Begin
  Result := AssistantRecoveryResumeCall;
End;

Function AssistantPhaseIsReconnectWait(Const Phase: String): Boolean;
Begin
  Result := (Phase = 'Re-establishing Connection') Or
    (Pos(AssistantRecoveryWaitReconnect, Phase) > 0) Or
    (Pos(AssistantRecoveryWaitCredits, Phase) > 0) Or
    (Pos(AssistantRecoveryWaitRateLimit, Phase) > 0);
End;

Function ProcessTransportDropped(Const ErrorText: String): Boolean;
Var
  Lowered: String;
Begin
  { An empty process result is not a socket close. A completed turn can have no error. }
  If Trim(ErrorText) = '' Then
    Exit(False);
  If IsTransientNetworkError(ErrorText) Then
    Exit(True);
  Lowered := LowerCase(ErrorText);
  Result :=
    (Pos('runtime exited', Lowered) > 0) Or
    (Pos('stdin closed', Lowered) > 0) Or
    (Pos('truncated protocol frame', Lowered) > 0) Or
    (Pos('unable to start the codex runtime', Lowered) > 0) Or
    (Pos('configure its pipes', Lowered) > 0) Or
    (Pos('pipe write', Lowered) > 0) Or
    (Pos('pipe signal', Lowered) > 0) Or
    (Pos('could not start claude code', Lowered) > 0) Or
    (Pos('did not complete the turn', Lowered) > 0);
End;

Function ClassifyDroppedTransport(Const ErrorText, ResponseBody: String; UserStopped: Boolean): TAssistantRecovery;
Var
  Fault: TAssistantFault;
Begin
  Fault := DefaultAssistantFault;
  { Default origin is cancel. A process drop is not a cancel unless the text says so. }
  Fault.Origin := afoTurn;
  Fault.ErrorText := ErrorText;
  Fault.ResponseBody := ResponseBody;
  Fault.HttpStatus := HttpStatusInText(ErrorText);
  If Fault.HttpStatus = 0 Then
    Fault.HttpStatus := HttpStatusInText(ResponseBody);
  Fault.OwnsTurn := True;
  Fault.UserStopped := UserStopped;
  Fault.Attempt := 1;
  If UserStopped Or FaultIsCancel(Fault) Then
    Exit(Recovery(araStop, False));
  If StatusIs(Fault, 401) Then
    Exit(Recovery(araStop, False));
  { App-server turns and tool results are not idempotent. A lost response must
    not replay an entire Codex turn with potentially completed IDE actions. }
  If Pos('codex', LowerCase(ErrorText)) > 0 Then
    Exit(Recovery(araStop, False));
  { Same order as an HTTP round: credits before a short 429, then a lost transport. }
  If AssistantFaultIsOutOfCredits(Fault) Then
    Exit(Recovery(araRetryLastAction, False, ahwCredits));
  If StatusIs(Fault, 429) Then
    Exit(Recovery(araRetryLastAction, False, ahwRateLimit));
  If ProcessTransportDropped(ErrorText) Or ProcessTransportDropped(ResponseBody) Then
    Exit(Recovery(araRetryLastAction, True));
  Result := Recovery(araStop, False);
End;

Function AssistantDroppedTransportWaitMs(Kind: TAssistantHttpWait; Const ErrorText, Body, RetryAfter: String;
  UsageHasReset: Boolean; UsageResetsAt: TDateTime; ConnectionIntervalMs, CreditIntervalMs: QWord;
  NowTime: TDateTime; Out RetryAt: TDateTime): QWord;
Begin
  RetryAt := 0;
  If ConnectionIntervalMs = 0 Then
    ConnectionIntervalMs := AssistantReconnectIntervalMs;
  If CreditIntervalMs = 0 Then
    CreditIntervalMs := AssistantCreditIntervalMs;
  Case Kind Of
    ahwCredits:
      Result := AssistantCreditWaitMs(ErrorText, Body, RetryAfter, UsageHasReset, UsageResetsAt, CreditIntervalMs,
        NowTime, RetryAt);
    ahwRateLimit:
      Result := AssistantRateLimitWaitMs(RetryAfter, ConnectionIntervalMs, NowTime);
  Else
    Result := ConnectionIntervalMs;
  End;
  If Result = 0 Then
    Result := ConnectionIntervalMs;
End;

Function AssistantDroppedTransportWaitNote(Kind: TAssistantHttpWait; Const ErrorText: String;
  RetryAt: TDateTime): String;
Begin
  Case Kind Of
    ahwCredits:
      Result := AssistantCreditWaitNote(ErrorText, RetryAt);
    ahwRateLimit:
      Result := AssistantRateLimitWaitNote(ErrorText);
  Else
    Result := AssistantReconnectWaitNote(ErrorText);
  End;
End;

End.
