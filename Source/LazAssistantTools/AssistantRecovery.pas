Unit AssistantRecovery;

{ Fault classification for an assistant turn (c) 2026 Michell Computing.

  Owns the decision to ignore, retry, continue, or stop. Callers log with
  ReportPluginException and do not copy this policy. A disconnect is retried
  without the fault-retry cap; the HTTP round still owns that wait. }

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
  { Stable phrases. IsAssistantProgressStatus matches these so a late snapshot is not an error. }
  AssistantRecoveryRetryHttp = 'Retrying the HTTP round.';
  AssistantRecoveryRetryTool = 'Retrying the read-only tool.';
  AssistantRecoveryHandBackTool = 'Handing the tool error back to the model.';
  AssistantRecoveryIgnorePaint = 'Ignoring a paint fault.';
  AssistantRecoveryIgnoreCallback = 'Ignoring a callback after detach.';
  AssistantRecoveryWaitReconnect = 'Waiting to reconnect.';
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
  End;

  TAssistantRecovery = Record
    Action: TAssistantRecoveryAction;
    { True only for a disconnect retry. The fault-retry cap does not apply. }
    WaitForConnection: Boolean;
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
Function AssistantReconnectWaitNote(Const ErrorText: String): String;
Function AssistantReconnectResumeNote: String;
Function AssistantPhaseIsReconnectWait(Const Phase: String): Boolean;

Implementation

Uses
  SysUtils;

Function DefaultAssistantFault: TAssistantFault;
Begin
  Result := Default(TAssistantFault);
  Result.Attempt := 1;
  Result.AttemptCap := 0;
End;

Function AssistantFaultRetryCap(Requested: Integer): Integer;
Begin
  If Requested > 0 Then
    Result := Requested
  Else
    Result := DefaultFaultRetryCap;
End;

Function HttpStatusInText(Const ErrorText: String): Integer;
Var
  Lowered: String;
  At, Code: Integer;
Begin
  Result := 0;
  Lowered := LowerCase(ErrorText);
  At := Pos('http ', Lowered);
  If At < 1 Then
    Exit;
  At := At + 5;
  Code := 0;
  While (At <= Length(Lowered)) And (Lowered[At] In ['0'..'9']) Do
    Begin
      Code := Code * 10 + (Ord(Lowered[At]) - Ord('0'));
      Inc(At);
    End;
  If (Code >= 100) And (Code <= 599) Then
    Result := Code;
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
    (Name = 'open_file') Or (Name = 'open_markdown');
End;

Function Recovery(Action: TAssistantRecoveryAction; WaitForConnection: Boolean): TAssistantRecovery;
Begin
  Result.Action := Action;
  Result.WaitForConnection := WaitForConnection;
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
    (Pos(AssistantRecoveryResumeCall, S) > 0);
End;

Function AssistantReconnectIntervalMs: QWord;
Begin
  Result := QWord(DefaultReconnectIntervalSeconds) * 1000;
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
  Result := (Phase = 'Re-establishing Connection') Or (Pos(AssistantRecoveryWaitReconnect, Phase) > 0);
End;

End.
