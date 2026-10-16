Program AssistantTurnFinishTest;

{ Decision tests for a premature Ready (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  SysUtils, AssistantTurnFinish;

Function OneTool(Const Name: String; Ok: Boolean; Const Detail: String): TAssistantSummaryTool;
Begin
  Result.Name := Name;
  Result.Ok := Ok;
  Result.Detail := Detail;
End;

Function ToolList(Const Items: Array Of TAssistantSummaryTool): TAssistantSummaryToolArray;
Var
  I: Integer;
Begin
  Result := Nil;
  SetLength(Result, Length(Items));
  For I := 0 To High(Items) Do
    Result[I] := Items[I];
End;

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
  LongDeferral, Summary: String;
  Answer: TAssistantContinuation;
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

  Answer := AssistantDecideContinuation(Facts(True, False, False, False, False, 'Partial'), False, False, 0, 3, '');
  Check('first truncated turn continues', Answer.ContinueTurn);
  Check('continuation note names the stop', Pos('truncated', Answer.Note) > 0);
  Check('continuation note says resuming', Pos('resuming', Answer.Note) > 0);
  Check('continuation note is attempt 1 of 3', Pos('Attempt 1 of 3', Answer.Note) > 0);
  Check('instruction resumes from tool results', Pos('last tool results', AssistantContinuationInstruction) > 0);
  Check('instruction does not stop early', Pos('real block is written', AssistantContinuationInstruction) > 0);

  Answer := AssistantDecideContinuation(Facts(False, False, True, True, False, 'Still open.'), False, False, 2, 3,
    'Detect a premature Ready');
  Check('third continuation is allowed', Answer.ContinueTurn);
  Check('third note names the item', Pos('Detect a premature Ready', Answer.Note) > 0);

  Answer := AssistantDecideContinuation(Facts(False, True, True, False, False, ''), False, False, 3, 3, '');
  Check('cap does not continue', Not Answer.ContinueTurn);
  Check('cap says continuation stopped', Pos('Automatic continuation stopped', Answer.Note) > 0);
  Check('cap says what remains', Pos('tool-round limit', Answer.Note) > 0);

  Answer := AssistantDecideContinuation(Facts(True, False, False, False, True, 'Partial'), False, False, 0, 3, '');
  Check('blocked user action does not continue', Not Answer.ContinueTurn);
  Check('blocked user action has no resume note', Answer.Note = '');

  Answer := AssistantDecideContinuation(Facts(True, False, False, False, False, 'Partial'), True, False, 0, 3, '');
  Check('stop does not continue', Not Answer.ContinueTurn);
  Answer := AssistantDecideContinuation(Facts(False, False, False, False, False, 'Done.'), False, True, 0, 3, '');
  Check('terminal fault does not continue', Not Answer.ContinueTurn);
  Answer := AssistantDecideContinuation(Facts(False, False, False, False, False, 'Fixed the leak.'), False, False, 0, 3, '');
  Check('finished reply is not continued', Not Answer.ContinueTurn);

  Check('written text does not need a summary', Not AssistantNeedsFinalSummary('Done.'));
  Check('empty text needs a summary', AssistantNeedsFinalSummary(''));
  Check('whitespace needs a summary', AssistantNeedsFinalSummary('  ' + LineEnding));

  Summary := AssistantFinalSummary('Fix the leak.', ToolList([OneTool('read_file', True, ''),
    OneTool('run_compile', False, 'lazbuild exited 1')]));
  Check('summary names the ask', Pos('Asked: Fix the leak.', Summary) = 1);
  Check('summary names the tools', Pos('Tools: read_file, run_compile (failed).', Summary) > 0);
  Check('summary states the failure', Pos('Outcome: run_compile failed: lazbuild exited 1.', Summary) > 0);

  Summary := AssistantFinalSummary('Explain the leak', ToolList([]));
  Check('no tools says none', Pos('Tools: none.', Summary) > 0);
  Check('no tools states the empty outcome', Pos('Outcome: No assistant text was returned.', Summary) > 0);
  Check('ask without a stop gets one period', Pos('Asked: Explain the leak.', Summary) = 1);

  Summary := AssistantFinalSummary('', ToolList([OneTool('grep', True, 'unused')]));
  Check('missing prompt is named', Pos('Asked: no prompt text.', Summary) = 1);
  Check('successful tools are the outcome', Pos('Outcome: The tools finished.', Summary) > 0);
  Check('a successful tool detail is not dumped', Pos('unused', Summary) = 0);

  Summary := AssistantFinalSummary('Read it.', ToolList([OneTool('read_file', True, ''), OneTool('read_file', True, ''),
    OneTool('grep', True, '')]));
  Check('repeated tool is counted', Pos('read_file (2)', Summary) > 0);

  Summary := AssistantFinalSummary('x', ToolList([OneTool('git', False, 'line one' + LineEnding + 'line two')]));
  Check('failure detail keeps the first line', Pos('line one', Summary) > 0);
  Check('failure detail drops later lines', Pos('line two', Summary) = 0);

  Summary := AssistantFinalSummary(StringOfChar('a', 400), ToolList([]));
  Check('long ask keeps the start', Pos('Asked: ' + StringOfChar('a', 40), Summary) = 1);
  Check('long ask is shortened', Pos('...', Summary) > 0);
  Check('long ask is not copied whole', Pos(StringOfChar('a', 200), Summary) = 0);

  Check('successful empty turn is not stored', Not AssistantMayStoreTurn('', ''));
  Check('successful whitespace is not stored', Not AssistantMayStoreTurn('', '   '));
  Check('successful text is stored', AssistantMayStoreTurn('', Summary));
  Check('cancelled empty turn may be stored', AssistantMayStoreTurn('cancelled', ''));
  Check('error empty turn may be stored', AssistantMayStoreTurn('socket closed', ''));

  If FailCount = 0 Then
    WriteLn('All premature-Ready decisions passed.')
  Else
    Begin
      WriteLn(FailCount, ' failed');
      Halt(1);
    End;
End.
