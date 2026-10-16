Program AssistantTurnFinishTest;

{ Decision tests for a premature Ready (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  SysUtils, AssistantTurnFinish;

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

Function Facts(Truncated, ToolRoundCap, HadToolRound, PlanInProgress, BlockedWithAction: Boolean;
  Const AssistantText: String): TAssistantTurnFinishFacts;
Begin
  Result := DefaultAssistantTurnFinishFacts;
  Result.Truncated := Truncated;
  Result.ToolRoundCap := ToolRoundCap;
  Result.HadToolRound := HadToolRound;
  Result.PlanItemInProgress := PlanInProgress;
  Result.PlanItemBlockedWithUserAction := BlockedWithAction;
  Result.AssistantText := AssistantText;
End;

Procedure Expect(Const Title: String; Const Sample: TAssistantTurnFinishFacts; Reason: TAssistantTurnFinishReason);
Var
  Decision: TAssistantTurnFinish;
Begin
  Decision := ClassifyAssistantTurnFinish(Sample);
  Check(Title, (Decision.Reason = Reason) And (Decision.Unfinished = (Reason <> atfFinished)));
End;

Var
  LongDeferral: String;
Begin
  FailCount := 0;
  Expect('truncated text is unfinished', Facts(True, False, False, False, False, 'Partial answer'), atfTruncated);
  Expect('length finish is the same truncated fact', Facts(True, False, True, True, False, 'Stopped mid-sentence'),
    atfTruncated);
  Expect('tool-round cap is unfinished', Facts(False, True, True, False, False, 'Still working.'), atfToolRoundCap);
  Expect('cap wins over an empty reply', Facts(False, True, True, False, False, ''), atfToolRoundCap);
  Expect('empty reply after tools is unfinished', Facts(False, False, True, False, False, ''), atfEmptyAfterTools);
  Expect('whitespace after tools is empty', Facts(False, False, True, False, False, '  ' + LineEnding), atfEmptyAfterTools);
  Expect('empty reply with no tools is finished', Facts(False, False, False, False, False, ''), atfFinished);
  Expect('short reply is finished', Facts(False, False, False, False, False, 'Fixed the leak.'), atfFinished);
  Expect('short done is finished', Facts(False, False, True, False, False, 'Done.'), atfFinished);

  Expect('continue-if-you-want is unfinished', Facts(False, False, False, False, False, 'I can continue if you want.'),
    atfDeferral);
  Expect('let-me-know is unfinished', Facts(False, False, False, False, False,
    'Let me know if you want me to continue'), atfDeferral);
  Expect('should-I-proceed is unfinished', Facts(False, False, False, False, False, 'SHOULD I PROCEED?'), atfDeferral);
  Expect('spaced deferral still matches', Facts(False, False, False, False, False, 'Should   I   proceed?'), atfDeferral);
  Check('I should proceed is not the listed deferral',
    Not AssistantReplyIsShortDeferral('I should proceed.'));
  Expect('near miss stays finished', Facts(False, False, False, False, False, 'I should proceed.'), atfFinished);

  LongDeferral := 'should i proceed ' + StringOfChar('x', AssistantDeferralMaxChars);
  Expect('a long reply is not a deferral', Facts(False, False, False, False, False, LongDeferral), atfFinished);
  Expect('deferral wins over a plan item', Facts(False, False, False, True, False, 'Should I proceed?'), atfDeferral);

  Expect('plan item in progress is unfinished', Facts(False, False, True, True, False,
    'The parser now keeps the partial text.'), atfPlanInProgress);
  Expect('blocked with a user action is finished', Facts(False, False, True, False, True,
    'The parser now keeps the partial text.'), atfFinished);
  Expect('blocked with a user action is not the plan rule', Facts(False, False, False, True, True, 'Still open.'),
    atfFinished);

  Check('user action line counts', PlanBodyHasUserAction('Status: blocked' + LineEnding + 'User action: review the item.'));
  Check('fenced user action does not count',
    Not PlanBodyHasUserAction('```' + LineEnding + 'User action: example' + LineEnding + '```'));
  Check('empty user action line still counts', PlanBodyHasUserAction('User action:'));

  If FailCount = 0 Then
    WriteLn('All premature-Ready decisions passed.')
  Else
    Begin
      WriteLn(FailCount, ' failed');
      Halt(1);
    End;
End.
