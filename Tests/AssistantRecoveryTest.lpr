Program AssistantRecoveryTest;

{ Terminal stop note and the classification that keeps a first fault alive (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, SysUtils, DateUtils, AssistantRecovery;

Var
  FailCount: Integer;

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

Function Fault(Origin: TAssistantFaultOrigin; Const ToolName, ErrorClass, ErrorText: String;
  Attempt: Integer): TAssistantFault;
Begin
  Result := DefaultAssistantFault;
  Result.Origin := Origin;
  Result.Area := 'ExecuteAssistantToolForMode';
  Result.ToolName := ToolName;
  Result.ErrorClass := ErrorClass;
  Result.ErrorText := ErrorText;
  Result.Attempt := Attempt;
  Result.AttemptCap := 1;
  Result.OwnsTurn := True;
End;

Procedure TestCreditDecisions;
Var
  Sample: TAssistantFault;
  Decision: TAssistantRecovery;
  NowTime, ResetAt, RetryAt: TDateTime;
  WaitMs: QWord;
  UnixAt: Int64;
  Note: String;
Begin
  Sample := DefaultAssistantFault;
  Sample.Origin := afoHttpRound;
  Sample.HttpStatus := 402;
  Sample.ErrorText := 'HTTP 402';
  Sample.Attempt := 4;
  Sample.AttemptCap := 1;
  Sample.OwnsTurn := True;
  Decision := ClassifyAssistantFault(Sample);
  Check('402 waits for credits with no attempt cap', (Decision.Action = araRetryLastAction) And
    (Decision.HttpWait = ahwCredits) And (Not Decision.WaitForConnection));

  Sample.HttpStatus := 0;
  Sample.ErrorText := 'Unexpected response status code: 402';
  Decision := ClassifyAssistantFault(Sample);
  Check('status code text 402 is credits', Decision.HttpWait = ahwCredits);

  Sample.HttpStatus := 500;
  Sample.ErrorText := 'HTTP 500';
  Sample.ResponseBody := 'quota exceeded';
  Check('quota in the body is credits', AssistantFaultIsOutOfCredits(Sample));
  Sample.ResponseBody := 'spending limit reached';
  Check('spending in the body is credits', AssistantFaultIsOutOfCredits(Sample));
  Sample.ResponseBody := 'billing hard limit';
  Check('billing in the body is credits', AssistantFaultIsOutOfCredits(Sample));
  Sample.ErrorText := 'insufficient credit';
  Sample.ResponseBody := '';
  Check('insufficient credit is credits', AssistantFaultIsOutOfCredits(Sample));

  Sample.HttpStatus := 400;
  Sample.ErrorText := 'HTTP 400: bad request';
  Sample.ResponseBody := '{"error":"quota exceeded"}';
  Decision := ClassifyAssistantFault(Sample);
  Check('quota on a 400 is credits, not a bad request', (Decision.Action = araRetryLastAction) And
    (Decision.HttpWait = ahwCredits));

  Sample := DefaultAssistantFault;
  Sample.Origin := afoHttpRound;
  Sample.HttpStatus := 429;
  Sample.ErrorText := 'HTTP 429';
  Sample.Attempt := 3;
  Sample.AttemptCap := 1;
  Sample.OwnsTurn := True;
  Decision := ClassifyAssistantFault(Sample);
  Check('short 429 is a rate limit, not credits', (Decision.Action = araRetryLastAction) And
    (Decision.HttpWait = ahwRateLimit));

  Sample.HttpStatus := 0;
  Sample.ErrorText := 'Unexpected response status code: 429';
  Decision := ClassifyAssistantFault(Sample);
  Check('status code text 429 is a rate limit', Decision.HttpWait = ahwRateLimit);

  Sample.HttpStatus := 401;
  Sample.ErrorText := 'HTTP 401: insufficient credits';
  Decision := ClassifyAssistantFault(Sample);
  Check('401 still stops even if it mentions credits', Decision.Action = araStop);

  NowTime := EncodeDate(2026, 10, 16) + EncodeTime(12, 0, 0, 0);
  ResetAt := NowTime + (3 / 24);
  WaitMs := AssistantCreditWaitMs('HTTP 402', '', '', False, 0, 60 * 60 * 1000, NowTime, RetryAt);
  Check('credit failure without a reset uses the hourly interval', WaitMs = 60 * 60 * 1000);
  Check('credit failure does not use the 30 second interval', WaitMs <> 30000);
  Note := AssistantCreditWaitNote('HTTP 402', RetryAt);
  Check('credit note says the retry clock', Pos('Retry at ' + FormatDateTime('yyyy-mm-dd hh:nn', RetryAt), Note) > 0);
  Check('credit note is progress', IsAssistantRecoveryProgress(Note));

  WaitMs := AssistantCreditWaitMs('quota', '', '30', False, 0, 60 * 60 * 1000, NowTime, RetryAt);
  Check('bare Retry-After delay is not a credit reset', WaitMs = 60 * 60 * 1000);
  WaitMs := AssistantCreditWaitMs('', '{"retry_after":90}', '', False, 0, 60 * 60 * 1000, NowTime, RetryAt);
  Check('JSON retry_after delay is the credit wait', WaitMs = 90000);
  ResetAt := UniversalTimeToLocal(EncodeDate(2026, 10, 16) + EncodeTime(15, 0, 0, 0));
  NowTime := UniversalTimeToLocal(EncodeDate(2026, 10, 16) + EncodeTime(13, 0, 0, 0));
  WaitMs := AssistantCreditWaitMs('HTTP 402', '', 'Fri, 16 Oct 2026 15:00:00 GMT', False, 0, 60 * 60 * 1000,
    NowTime, RetryAt);
  Check('Retry-After HTTP-date is the credit reset', (Abs(RetryAt - ResetAt) < (2 / 86400)) And
    (Abs(Int64(WaitMs) - Round((ResetAt - NowTime) * 86400000)) < 2000));

  NowTime := EncodeDate(2026, 10, 16) + EncodeTime(12, 0, 0, 0);
  ResetAt := NowTime + (3 / 24);
  UnixAt := DateTimeToUnix(ResetAt, False);
  WaitMs := AssistantCreditWaitMs('quota exceeded', '{"reset_at":' + IntToStr(UnixAt) + '}', '', False, 0,
    60 * 60 * 1000, NowTime, RetryAt);
  Check('JSON reset_at unix waits until the local clock', (Abs(RetryAt - ResetAt) < (2 / 86400)) And
    (Abs(Int64(WaitMs) - 3 * 60 * 60 * 1000) < 2000));

  WaitMs := AssistantCreditWaitMs('billing', '', '', True, ResetAt, 60 * 60 * 1000, NowTime, RetryAt);
  Check('usage snapshot reset is the credit wait', (Abs(RetryAt - ResetAt) < (2 / 86400)) And
    (Abs(Int64(WaitMs) - 3 * 60 * 60 * 1000) < 2000));

  WaitMs := AssistantCreditWaitMs('billing', '', '', True, NowTime - 1, 60 * 60 * 1000, NowTime, RetryAt);
  Check('past usage reset uses the credit interval', WaitMs = 60 * 60 * 1000);

  WaitMs := AssistantRateLimitWaitMs('12', 30000, NowTime);
  Check('short 429 uses Retry-After', WaitMs = 12000);
  WaitMs := AssistantRateLimitWaitMs('', 30000, NowTime);
  Check('429 without Retry-After uses the connection interval', WaitMs = 30000);
End;

Procedure TestDroppedTransport;
Var
  Decision: TAssistantRecovery;
  NowTime, ResetAt, RetryAt: TDateTime;
  WaitMs: QWord;
  Note: String;
Begin
  Decision := ClassifyDroppedTransport('Codex runtime exited.', '', False);
  Check('Codex runtime exit does not replay the turn', Decision.Action = araStop);
  Decision := ClassifyDroppedTransport('Codex stdin closed unexpectedly.', '', False);
  Check('Codex stdin close does not replay the turn', Decision.Action = araStop);
  Decision := ClassifyDroppedTransport('Codex exited with a truncated protocol frame.', '', False);
  Check('truncated Codex frame does not replay the turn', Decision.Action = araStop);
  Decision := ClassifyDroppedTransport('Could not start Claude Code.', '', False);
  Check('Claude start failure retries the turn', Decision.Action = araRetryLastAction);
  Decision := ClassifyDroppedTransport('Claude Code did not complete the turn.', '', False);
  Check('incomplete Claude turn retries', Decision.Action = araRetryLastAction);
  Decision := ClassifyDroppedTransport('Claude Code timed out.', '', False);
  Check('Claude timeout retries as a lost connection', (Decision.Action = araRetryLastAction) And
    (Decision.HttpWait = ahwConnection));

  Decision := ClassifyDroppedTransport('quota exceeded', '', False);
  Check('process credit text waits for credits', (Decision.Action = araRetryLastAction) And
    (Decision.HttpWait = ahwCredits));
  Decision := ClassifyDroppedTransport('HTTP 402', '{"error":"insufficient credit"}', False);
  Check('process 402 is credits', Decision.HttpWait = ahwCredits);
  Decision := ClassifyDroppedTransport('status code: 429', '', False);
  Check('process 429 is a rate limit', (Decision.Action = araRetryLastAction) And
    (Decision.HttpWait = ahwRateLimit));

  Decision := ClassifyDroppedTransport('', '', False);
  Check('empty process result is not a drop', Decision.Action = araStop);
  Decision := ClassifyDroppedTransport('Cancelled.', '', False);
  Check('cancelled process stops', Decision.Action = araStop);
  Decision := ClassifyDroppedTransport('Codex connection cancelled.', '', True);
  Check('user stop does not retry a Codex drop', Decision.Action = araStop);
  Decision := ClassifyDroppedTransport('HTTP 401: Unauthorized', '', False);
  Check('process 401 stops once', Decision.Action = araStop);
  Decision := ClassifyDroppedTransport('Sign in to the qualified Codex runtime with ChatGPT before starting a run.', '',
    False);
  Check('Codex sign-in stops', Decision.Action = araStop);
  Decision := ClassifyDroppedTransport('Claude Code refused the permission mode flag.', '', False);
  Check('refused Claude permission flag stops', Decision.Action = araStop);
  Decision := ClassifyDroppedTransport('Invalid or oversized Codex protocol frame.', '', False);
  Check('Codex protocol error stops', Decision.Action = araStop);

  NowTime := EncodeDate(2026, 10, 16) + EncodeTime(12, 0, 0, 0);
  WaitMs := AssistantDroppedTransportWaitMs(ahwConnection, 'Codex runtime exited.', '', '', False, 0, 30000,
    60 * 60 * 1000, NowTime, RetryAt);
  Check('dropped transport uses the connection interval', WaitMs = 30000);
  Note := AssistantDroppedTransportWaitNote(ahwConnection, 'Codex runtime exited.', 0);
  Check('dropped transport note is the reconnect sentence', (Pos(AssistantRecoveryWaitReconnect, Note) > 0) And
    IsAssistantRecoveryProgress(Note));

  WaitMs := AssistantDroppedTransportWaitMs(ahwCredits, 'quota exceeded', '', '', False, 0, 30000, 60 * 60 * 1000,
    NowTime, RetryAt);
  Check('dropped credit failure uses the hourly interval', WaitMs = 60 * 60 * 1000);
  Check('dropped credit failure does not use 30 seconds', WaitMs <> 30000);
  ResetAt := NowTime + (2 / 24);
  WaitMs := AssistantDroppedTransportWaitMs(ahwCredits, 'billing', '', '', True, ResetAt, 30000, 60 * 60 * 1000,
    NowTime, RetryAt);
  Check('dropped credit failure waits until the usage reset', (Abs(RetryAt - ResetAt) < (2 / 86400)) And
    (Abs(Int64(WaitMs) - 2 * 60 * 60 * 1000) < 2000));
  Note := AssistantDroppedTransportWaitNote(ahwCredits, 'quota exceeded', RetryAt);
  Check('dropped credit note names the clock', Pos('Retry at ' + FormatDateTime('yyyy-mm-dd hh:nn', RetryAt), Note) > 0);
  Check('dropped credit note is progress', IsAssistantRecoveryProgress(Note));
  Note := AssistantDroppedTransportWaitNote(ahwRateLimit, 'status code: 429', 0);
  Check('dropped rate-limit note is progress', IsAssistantRecoveryProgress(Note));
End;

Var
  Note: String;
  Decision: TAssistantRecovery;
  Sample: TAssistantFault;
Begin
  FailCount := 0;
  Note := AssistantRecoveryStopNote('ExecuteAssistantToolForMode', 'EAccessViolation', 'Access violation');
  Check('note names the area', Pos('Area: ExecuteAssistantToolForMode.', Note) > 0);
  Check('note names the class', Pos('Exception: EAccessViolation.', Note) > 0);
  Check('note names the message', Pos('Message: Access violation.', Note) > 0);
  Check('note says the task has stopped', Pos('The task has stopped.', Note) = 1);
  Check('note has no tool recipe', (Pos('write_file', Note) = 0) And (Pos('replace_in_file', Note) = 0));

  Note := AssistantRecoveryStopNote('', '', 'line one' + LineEnding + 'line two');
  Check('empty area and class still stop', (Pos('Area: assistant.', Note) > 0) And
    (Pos('Exception: Exception.', Note) > 0));
  Check('message stays one line', Pos(LineEnding, Note) = 0);

  Decision := ClassifyAssistantFault(Fault(afoTool, 'replace_in_file', 'EAccessViolation', 'Access violation', 1));
  Check('first mutating tool fault continues the turn', Decision.Action = araContinueTurn);
  Decision := ClassifyAssistantFault(Fault(afoTool, 'read_file', 'EAccessViolation', 'Access violation', 1));
  Check('first read-only tool fault retries', Decision.Action = araRetryLastAction);
  Decision := ClassifyAssistantFault(Fault(afoTool, 'read_file', 'EAccessViolation', 'Access violation', 2));
  Check('second read-only tool fault stops', Decision.Action = araStop);
  Decision := ClassifyAssistantFault(Fault(afoHttpRound, '', 'EAccessViolation', 'Access violation', 1));
  Check('first HTTP fault retries', Decision.Action = araRetryLastAction);
  Decision := ClassifyAssistantFault(Fault(afoHttpRound, '', 'EAccessViolation', 'Access violation', 2));
  Check('second HTTP fault stops', Decision.Action = araStop);

  Note := AssistantRecoveryProgressNote(araRetryLastAction, afoHttpRound, 'TAssistantActor.DoHttpRound',
    'EAccessViolation', 'Access violation');
  Check('HTTP retry names the fault', Pos('EAccessViolation: Access violation.', Note) = 1);
  Check('HTTP retry names the resolution', Pos(AssistantRecoveryRetryHttp, Note) > 0);
  Check('HTTP retry is a progress sentence', IsAssistantRecoveryProgress(Note));

  Note := AssistantRecoveryProgressNote(araContinueTurn, afoTool, 'ExecuteAssistantToolForMode',
    'EAccessViolation', 'Access violation');
  Check('tool continue hands the error back', Pos(AssistantRecoveryHandBackTool, Note) > 0);

  Note := AssistantRecoveryProgressNote(araRetryLastAction, afoTool, 'ExecuteAssistantToolForMode',
    'EAccessViolation', 'Access violation');
  Check('read-only retry names the resolution', Pos(AssistantRecoveryRetryTool, Note) > 0);

  Note := AssistantRecoveryProgressNote(araIgnore, afoPaintLayout, 'TProjectAssistantForm.LayoutComposer',
    'EAccessViolation', 'Access violation');
  Check('paint ignore names the resolution', Pos(AssistantRecoveryIgnorePaint, Note) > 0);
  Check('paint ignore is a progress sentence', IsAssistantRecoveryProgress(Note));

  Note := AssistantRecoveryStopNote('ExecuteAssistantToolForMode', 'EAccessViolation', 'Access violation');
  Check('terminal stop is not a progress sentence', Not IsAssistantRecoveryProgress(Note));
  Check('stop has no progress phrase', AssistantRecoveryProgressNote(araStop, afoTool, 'tool', 'EAccessViolation',
    'Access violation') = '');

  Check('HTTP 502 is a lost connection', IsTransientNetworkError('HTTP 502: Bad Gateway'));
  Check('HTTP 503 is a lost connection', IsTransientNetworkError('HTTP 503'));
  Check('HTTP 504 is a lost connection', IsTransientNetworkError('HTTP 504: Gateway Timeout'));
  Check('empty socket close is a lost connection', IsTransientNetworkError(''));
  Check('socket closed is a lost connection', IsTransientNetworkError('Socket closed'));
  Check('WinINet read failure is a lost connection',
    IsTransientNetworkError('WinINet InternetReadFile failed (12030)'));
  Check('HTTP 401 is not a lost connection', Not IsTransientNetworkError('HTTP 401: Unauthorized'));
  Sample := Fault(afoHttpRound, '', '', 'HTTP 502: Bad Gateway', 8);
  Decision := ClassifyAssistantFault(Sample);
  Check('502 keeps retrying with a wait', (Decision.Action = araRetryLastAction) And Decision.WaitForConnection);
  Sample := DefaultAssistantFault;
  Sample.Origin := afoHttpRound;
  Sample.HttpStatus := 503;
  Sample.ErrorText := 'unavailable';
  Sample.Attempt := 9;
  Sample.AttemptCap := 1;
  Sample.OwnsTurn := True;
  Decision := ClassifyAssistantFault(Sample);
  Check('status 503 has no attempt cap', (Decision.Action = araRetryLastAction) And Decision.WaitForConnection);
  Sample := Fault(afoHttpRound, '', '', 'HTTP 401: Unauthorized', 1);
  Sample.HttpStatus := 401;
  Decision := ClassifyAssistantFault(Sample);
  Check('HTTP 401 still stops once', Decision.Action = araStop);
  Check('wait note names the fault', Pos('Error reading data from socket',
    AssistantReconnectWaitNote('Error reading data from socket')) > 0);
  Check('wait note is progress', IsAssistantRecoveryProgress(AssistantReconnectWaitNote('socket closed')));
  Check('connecting is a reconnect wait', AssistantPhaseIsReconnectWait('Connecting…'));
  Check('old reconnect phrase is a wait', AssistantPhaseIsReconnectWait('Re-establishing Connection'));
  Check('reconnect sentence is not a phase', Not AssistantPhaseIsReconnectWait(AssistantRecoveryWaitReconnect));
  Check('credit sentence is not a phase', Not AssistantPhaseIsReconnectWait(AssistantRecoveryWaitCredits));
  Check('resume note is progress', IsAssistantRecoveryProgress(AssistantReconnectResumeNote));
  Check('reconnect interval defaults to 30 seconds', AssistantReconnectIntervalMs = 30000);
  TestCreditDecisions;
  TestDroppedTransport;
  If FailCount <> 0 Then
    Halt(1);
End.
