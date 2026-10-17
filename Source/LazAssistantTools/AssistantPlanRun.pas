Unit AssistantPlanRun;

{ End-of-run plan status. The form posts the text; this unit owns the wording (c) 2026 Michell Computing.

  Every Run Plan exit uses one report: the plan-list counts, why the run ended,
  each blocked item's stored user action, and the next step. A finish with
  blocked items left does not say that all packages are complete. The start
  dialog uses the same rule when nothing unblocked remains. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Const
  AssistantPlanRunAgain = 'Next: run Run Plan again.';
  AssistantPlanRunNewChat = 'Next: start a New Chat.';
  AssistantPlanRunBlockedLeft = 'Blocked items need the listed actions. No unblocked item is left.';
  AssistantPlanRunAlreadyComplete = 'All plan packages are already complete.';
  AssistantPlanRunNoneFound = 'No plan packages were found.';
  { Context continuation. 0 in storage means the default. The form does not hard-code 95. }
  AssistantPlanContextPercentDefault = 95;
  AssistantPlanContextPercentMin = 50;
  AssistantPlanContextPercentMax = 99;

Type
  TPlanRunEndKind = (
    preCleanFinish,
    preUserStop,
    preError,
    prePackageCap,
    preContextLimit,
    preNewChat
  );

  TPlanRunBlockedItem = Record
    Title: String;
    UserAction: String;
    HasUserAction: Boolean;
  End;
  TPlanRunBlockedItemArray = Array Of TPlanRunBlockedItem;

  TPlanRunReportFacts = Record
    Kind: TPlanRunEndKind;
    Detail: String;
    PackagesWorked: Integer;
    NotStarted: Integer;
    InProgress: Integer;
    Blocked: Integer;
    Complete: Integer;
    BlockedItems: TPlanRunBlockedItemArray;
    { A fault that says not to continue with Run Plan. Context limit is that case too. }
    TerminalFault: Boolean;
  End;

Function DefaultPlanRunReportFacts: TPlanRunReportFacts;
{ Same line as the plan list, including the empty-plan suffix. }
Function AssistantPlanRunCountsLine(NotStarted, InProgress, Blocked, Complete: Integer): String;
Function AssistantPlanRunWhy(Const Facts: TPlanRunReportFacts): String;
{ One conversation report. Does not say that all packages are complete when a blocked item remains. }
Function AssistantPlanRunReport(Const Facts: TPlanRunReportFacts): String;
{ Start dialog when FindNextIncompleteBuildSection found nothing to run. }
Function AssistantPlanRunStartMessage(Const Facts: TPlanRunReportFacts): String;
{ Stored 0 keeps the default. Values outside 50..99 clamp to that range, except 0. }
Function PlanContextContinuePercent(StoredPercent: Integer): Integer;
{ A plan run at or over the threshold opens a new chat and continues, when the setting is on. }
Function PlanRunContinuesInNewChat(UsagePercent, ThresholdPercent: Integer; Enabled: Boolean): Boolean;
{ The agent is still marked running, nothing is sending, the user did not stop, and items remain. }
Function PlanRunUnexplainedStall(AgentRunning, Sending, UserStopped: Boolean; OpenItems: Integer): Boolean;
Function PlanRunStallWaitNote(WaitSeconds: Integer): String;
Function PlanRunStallResumeNote: String;
Function PlanRunNewChatNote(UsagePercent: Integer): String;

Implementation

Uses
  AssistantAcceptance;

Function PlanContextContinuePercent(StoredPercent: Integer): Integer;
Begin
  If StoredPercent <= 0 Then
    Result := AssistantPlanContextPercentDefault
  Else
    Result := StoredPercent;
  If Result < AssistantPlanContextPercentMin Then
    Result := AssistantPlanContextPercentMin;
  If Result > AssistantPlanContextPercentMax Then
    Result := AssistantPlanContextPercentMax;
End;

Function PlanRunContinuesInNewChat(UsagePercent, ThresholdPercent: Integer; Enabled: Boolean): Boolean;
Begin
  Result := Enabled And (ThresholdPercent > 0) And (UsagePercent >= ThresholdPercent);
End;

Function PlanRunUnexplainedStall(AgentRunning, Sending, UserStopped: Boolean; OpenItems: Integer): Boolean;
Begin
  Result := AgentRunning And (Not Sending) And (Not UserStopped) And (OpenItems > 0);
End;

Function PlanRunStallWaitNote(WaitSeconds: Integer): String;
Begin
  If WaitSeconds < 1 Then
    Result := 'The plan stopped with items still open. Waiting to reconnect.'
  Else
    Result := Format('The plan stopped with items still open. Waiting to reconnect. Retrying in %d seconds. Stop still interrupts the wait.',
      [WaitSeconds]);
End;

Function PlanRunStallResumeNote: String;
Begin
  Result := 'Resuming the call. The plan still has open items.';
End;

Function PlanRunNewChatNote(UsagePercent: Integer): String;
Begin
  Result := Format('Context usage %d%%. Starting a new chat and continuing the plan.', [UsagePercent]);
End;

Function DefaultPlanRunReportFacts: TPlanRunReportFacts;
Begin
  Result.Kind := preCleanFinish;
  Result.Detail := '';
  Result.PackagesWorked := 0;
  Result.NotStarted := 0;
  Result.InProgress := 0;
  Result.Blocked := 0;
  Result.Complete := 0;
  Result.BlockedItems := Nil;
  Result.TerminalFault := False;
End;

Function AssistantPlanRunCountsLine(NotStarted, InProgress, Blocked, Complete: Integer): String;
Begin
  Result := Format('%d not started · %d in progress · %d blocked · %d complete',
    [NotStarted, InProgress, Blocked, Complete]);
  If (NotStarted + InProgress + Blocked + Complete) = 0 Then
    Result := Result + '  ·  no actionable items';
End;

Function PlanRunOpenCount(Const Facts: TPlanRunReportFacts): Integer;
Begin
  Result := Facts.NotStarted + Facts.InProgress;
End;

Function AssistantPlanRunWhy(Const Facts: TPlanRunReportFacts): String;
Begin
  { Ord keeps Else reachable if a new kind is added. Result is assigned on every path. }
  Case Ord(Facts.Kind) Of
    Ord(preCleanFinish):
      Begin
        If PlanRunOpenCount(Facts) > 0 Then
          Result := 'The run stopped while items are still open.'
        Else If Facts.Blocked > 0 Then
          Result := AssistantPlanRunBlockedLeft
        Else
          Result := Format('All packages are complete (%d worked this run).', [Facts.PackagesWorked]);
      End;
    Ord(preUserStop):
      Begin
        If Pos('cancel', LowerCase(Facts.Detail)) > 0 Then
          Result := 'The stream was cancelled by the user.'
        Else
          Result := 'Stopped by the user.';
      End;
    Ord(preError):
      Begin
        Result := 'The run ended with an error.';
        If Trim(Facts.Detail) <> '' Then
          Result := Result + ' ' + Trim(Facts.Detail);
      End;
    Ord(prePackageCap):
      Begin
        If Trim(Facts.Detail) <> '' Then
          Result := 'Reached the package cap (' + Trim(Facts.Detail) + ').'
        Else
          Result := 'Reached the package cap.';
      End;
    Ord(preContextLimit):
      Begin
        If Trim(Facts.Detail) <> '' Then
          Result := Trim(Facts.Detail)
        Else
          Result := 'Context is at the limit. Start a New Chat.';
      End;
    Ord(preNewChat):
      Result := 'A new chat started.';
  Else
    Result := 'The plan run ended.';
  End;
End;

Function AssistantPlanRunBlockedLines(Const Facts: TPlanRunReportFacts): String;
Var
  I: Integer;
  Line: String;
Begin
  Result := '';
  For I := 0 To High(Facts.BlockedItems) Do
    Begin
      If Facts.BlockedItems[I].HasUserAction Then
        Line := AssistantBlockedItemReport(Facts.BlockedItems[I].Title, Facts.BlockedItems[I].UserAction)
      Else
        Line := 'Blocked "' + Facts.BlockedItems[I].Title + '". No user action is stored.';
      If Result <> '' Then
        Result := Result + LineEnding;
      Result := Result + Line;
    End;
End;

Function AssistantPlanRunNextStep(Const Facts: TPlanRunReportFacts): String;
Begin
  Result := '';
  If PlanRunOpenCount(Facts) > 0 Then
    Begin
      If Facts.TerminalFault Or (Facts.Kind = preContextLimit) Then
        Begin
          If (Facts.Kind = preContextLimit) Or (Pos('new chat', LowerCase(Facts.Detail)) > 0) Then
            Result := AssistantPlanRunNewChat
          Else If Trim(Facts.Detail) <> '' Then
            Result := 'Next: ' + Trim(Facts.Detail)
          Else
            Result := 'Next: the run stopped on a terminal fault.';
        End
      Else
        Result := AssistantPlanRunAgain;
    End
  Else If Facts.Blocked > 0 Then
    Result := AssistantPlanRunBlockedLeft;
End;

Function AssistantPlanRunReport(Const Facts: TPlanRunReportFacts): String;
Var
  Why, NextStep, Blocked: String;
Begin
  Why := AssistantPlanRunWhy(Facts);
  Result := '**Plan run ended:** ' + Why + LineEnding + LineEnding +
    AssistantPlanRunCountsLine(Facts.NotStarted, Facts.InProgress, Facts.Blocked, Facts.Complete);
  Blocked := AssistantPlanRunBlockedLines(Facts);
  If Blocked <> '' Then
    Result := Result + LineEnding + LineEnding + Blocked;
  NextStep := AssistantPlanRunNextStep(Facts);
  { The clean-finish why is already the blocked sentence. Do not repeat it. }
  If (NextStep <> '') And (Pos(NextStep, Why) = 0) Then
    Result := Result + LineEnding + LineEnding + NextStep;
End;

Function AssistantPlanRunStartMessage(Const Facts: TPlanRunReportFacts): String;
Var
  Blocked: String;
Begin
  If PlanRunOpenCount(Facts) > 0 Then
    Begin
      Result := 'Run Plan can continue.' + LineEnding + LineEnding +
        AssistantPlanRunCountsLine(Facts.NotStarted, Facts.InProgress, Facts.Blocked, Facts.Complete);
      Exit;
    End;
  If Facts.Blocked > 0 Then
    Begin
      Result := AssistantPlanRunBlockedLeft + LineEnding + LineEnding +
        AssistantPlanRunCountsLine(Facts.NotStarted, Facts.InProgress, Facts.Blocked, Facts.Complete);
      Blocked := AssistantPlanRunBlockedLines(Facts);
      If Blocked <> '' Then
        Result := Result + LineEnding + LineEnding + Blocked;
      Exit;
    End;
  If Facts.Complete > 0 Then
    Result := AssistantPlanRunAlreadyComplete + LineEnding + LineEnding +
      AssistantPlanRunCountsLine(Facts.NotStarted, Facts.InProgress, Facts.Blocked, Facts.Complete)
  Else
    Result := AssistantPlanRunNoneFound;
End;

End.
