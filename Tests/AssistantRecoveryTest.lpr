Program AssistantRecoveryTest;

{ Terminal stop note and the classification that keeps a first fault alive (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  SysUtils, AssistantRecovery;

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

Var
  Note: String;
  Decision: TAssistantRecovery;
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
  If FailCount <> 0 Then
    Halt(1);
End.
