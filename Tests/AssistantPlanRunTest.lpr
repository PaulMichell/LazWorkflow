Program AssistantPlanRunTest;

{ Decision tests for the Run Plan end report (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  SysUtils, AssistantPlanRun, AssistantTurnFinish, AssistantAcceptance;

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

Function Item(Const Title, Action: String; HasAction: Boolean): TPlanRunBlockedItem;
Begin
  Result.Title := Title;
  Result.UserAction := Action;
  Result.HasUserAction := HasAction;
End;

Function Facts(Kind: TPlanRunEndKind; Const Detail: String; Worked, NotStarted, InProgress, Blocked, Complete: Integer;
  TerminalFault: Boolean; Const Items: Array Of TPlanRunBlockedItem): TPlanRunReportFacts;
Var
  I: Integer;
Begin
  Result := DefaultPlanRunReportFacts;
  Result.Kind := Kind;
  Result.Detail := Detail;
  Result.PackagesWorked := Worked;
  Result.NotStarted := NotStarted;
  Result.InProgress := InProgress;
  Result.Blocked := Blocked;
  Result.Complete := Complete;
  Result.TerminalFault := TerminalFault;
  SetLength(Result.BlockedItems, Length(Items));
  For I := 0 To High(Items) Do
    Result.BlockedItems[I] := Items[I];
End;

Function Has(Const Report, Phrase: String): Boolean;
Begin
  Result := Pos(Phrase, Report) > 0;
End;

Procedure ExpectCounts(Const Title, Report: String; NotStarted, InProgress, Blocked, Complete: Integer);
Begin
  Check(Title, Has(Report, AssistantPlanRunCountsLine(NotStarted, InProgress, Blocked, Complete)));
End;

Var
  Report, StartMessage, ActionText: String;
  Sample: TPlanRunReportFacts;
Begin
  FailCount := 0;

  Check('empty plan counts match the list',
    AssistantPlanRunCountsLine(0, 0, 0, 0) = '0 not started · 0 in progress · 0 blocked · 0 complete  ·  no actionable items');
  Check('open counts match the list',
    AssistantPlanRunCountsLine(2, 1, 3, 4) = '2 not started · 1 in progress · 3 blocked · 4 complete');

  Sample := Facts(preCleanFinish, '', 2, 0, 0, 0, 5, False, []);
  Report := AssistantPlanRunReport(Sample);
  Check('clean finish names the worked count', Has(Report, 'All packages are complete (2 worked this run).'));
  ExpectCounts('clean finish counts', Report, 0, 0, 0, 5);
  Check('clean finish does not ask to run again', Not Has(Report, AssistantPlanRunAgain));
  Check('clean finish does not mention blocked actions', Not Has(Report, AssistantPlanRunBlockedLeft));

  Sample := Facts(preCleanFinish, '', 1, 0, 0, 1, 3, False, [Item('Review the form', 'review "Review the form"', True)]);
  Report := AssistantPlanRunReport(Sample);
  Check('blocked finish does not say all packages are complete', Not Has(LowerCase(Report), 'all packages are complete'));
  Check('blocked finish does not say already complete', Not Has(LowerCase(Report), 'already complete'));
  Check('blocked finish says the actions are required', Has(Report, AssistantPlanRunBlockedLeft));
  Check('blocked finish quotes the stored action',
    Has(Report, AssistantBlockedItemReport('Review the form', 'review "Review the form"')));
  Check('blocked finish does not ask to run again', Not Has(Report, AssistantPlanRunAgain));
  ExpectCounts('blocked finish counts', Report, 0, 0, 1, 3);
  Check('blocked sentence is not repeated',
    Pos(AssistantPlanRunBlockedLeft, Copy(Report, Pos(AssistantPlanRunBlockedLeft, Report) + Length(AssistantPlanRunBlockedLeft),
      MaxInt)) = 0);

  Sample := Facts(preCleanFinish, '', 0, 0, 0, 2, 1, False,
    [Item('First', 'do the first thing', True), Item('Second', '', False)]);
  Report := AssistantPlanRunReport(Sample);
  Check('both blocked items are listed', Has(Report, AssistantBlockedItemReport('First', 'do the first thing')) And
    Has(Report, 'Blocked "Second". No user action is stored.'));
  Check('missing action is not quoted as empty', Not Has(Report, AssistantBlockedItemReport('Second', '')));

  Sample := Facts(preUserStop, 'stopped by user', 1, 1, 1, 1, 2, False, [Item('Wait', 'supply the file', True)]);
  Report := AssistantPlanRunReport(Sample);
  Check('user stop names the user', Has(Report, 'Stopped by the user.'));
  Check('user stop with open items says run again', Has(Report, AssistantPlanRunAgain));
  Check('user stop still lists the blocked action', Has(Report, AssistantBlockedItemReport('Wait', 'supply the file')));
  ExpectCounts('user stop counts', Report, 1, 1, 1, 2);
  Check('user stop does not say all packages are complete', Not Has(LowerCase(Report), 'all packages are complete'));

  Sample := Facts(preUserStop, 'stream cancelled by user', 0, 1, 0, 0, 0, False, []);
  Report := AssistantPlanRunReport(Sample);
  Check('cancelled stream is a user stop', Has(Report, 'The stream was cancelled by the user.'));
  Check('cancelled stream with work left says run again', Has(Report, AssistantPlanRunAgain));

  Sample := Facts(preError, 'Could not start the first package.', 0, 2, 0, 0, 1, False, []);
  Report := AssistantPlanRunReport(Sample);
  Check('error names the detail', Has(Report, 'The run ended with an error. Could not start the first package.'));
  Check('error with work left says run again', Has(Report, AssistantPlanRunAgain));

  Sample := Facts(preError, 'the service is gone', 1, 0, 1, 0, 0, True, []);
  Report := AssistantPlanRunReport(Sample);
  Check('terminal error does not say run again', Not Has(Report, AssistantPlanRunAgain));
  Check('terminal error keeps the fault text', Has(Report, 'the service is gone'));

  Sample := Facts(prePackageCap, '25', 4, 3, 0, 0, 4, False, []);
  Report := AssistantPlanRunReport(Sample);
  Check('package cap names the limit', Has(Report, 'Reached the package cap (25).'));
  Check('package cap with work left says run again', Has(Report, AssistantPlanRunAgain));
  ExpectCounts('package cap counts', Report, 3, 0, 0, 4);

  Sample := Facts(preContextLimit, 'context usage 96% after compact — start a New Chat', 2, 1, 1, 0, 2, True, []);
  Report := AssistantPlanRunReport(Sample);
  Check('context limit keeps the percent', Has(Report, 'context usage 96% after compact — start a New Chat'));
  Check('context limit says start a new chat', Has(Report, AssistantPlanRunNewChat));
  Check('context limit does not say run again', Not Has(Report, AssistantPlanRunAgain));

  Sample := Facts(preContextLimit, 'context usage 97% — start a New Chat', 0, 0, 0, 1, 2, True,
    [Item('Manual', 'review it', True)]);
  Report := AssistantPlanRunReport(Sample);
  Check('context limit with only blocked items does not say all complete',
    Not Has(LowerCase(Report), 'all packages are complete'));
  Check('context limit with only blocked items names the action', Has(Report, AssistantPlanRunBlockedLeft));
  Check('context limit with only blocked items does not say run again', Not Has(Report, AssistantPlanRunAgain));

  Sample := Facts(preNewChat, 'new chat', 1, 2, 0, 0, 1, False, []);
  Report := AssistantPlanRunReport(Sample);
  Check('new chat names the exit', Has(Report, 'A new chat started.'));
  Check('new chat with work left says run again', Has(Report, AssistantPlanRunAgain));

  Sample := Facts(preCleanFinish, '', 0, 0, 0, 1, 4, False, [Item('Blocked item', 'add the missing file', True)]);
  StartMessage := AssistantPlanRunStartMessage(Sample);
  Check('start dialog does not say already complete when blocked', Not Has(LowerCase(StartMessage), 'already complete'));
  Check('start dialog does not say all packages when blocked', Not Has(LowerCase(StartMessage), 'all packages'));
  Check('start dialog says blocked items need the listed actions', Has(StartMessage, AssistantPlanRunBlockedLeft));
  Check('start dialog lists the stored action', Has(StartMessage, AssistantBlockedItemReport('Blocked item', 'add the missing file')));

  Sample := Facts(preCleanFinish, '', 0, 0, 0, 0, 6, False, []);
  StartMessage := AssistantPlanRunStartMessage(Sample);
  Check('start dialog says already complete when nothing is blocked', Has(StartMessage, AssistantPlanRunAlreadyComplete));

  Sample := Facts(preCleanFinish, '', 0, 0, 0, 0, 0, False, []);
  Check('start dialog says none found', AssistantPlanRunStartMessage(Sample) = AssistantPlanRunNoneFound);

  Check('fenced user action is not stored',
    Not PlanBodyUserAction('```' + LineEnding + 'User action: ignore this example' + LineEnding + '```', ActionText));
  Check('stored user action is the unfenced line',
    PlanBodyUserAction('```' + LineEnding + 'User action: ignore this example' + LineEnding + '```' + LineEnding +
      'User action: keep this one', ActionText) And (ActionText = 'keep this one'));
  Check('empty user action line still counts',
    PlanBodyUserAction('User action:', ActionText) And (ActionText = ''));

  If FailCount = 0 Then
    WriteLn('AssistantPlanRunTest passed')
  Else
    Begin
      WriteLn(FailCount, ' failed');
      Halt(1);
    End;
End.
