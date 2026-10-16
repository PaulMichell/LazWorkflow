Unit AssistantTurnFinish;

{ Whether a turn that is about to return Ready is actually finished (c) 2026 Michell Computing.

  The decision is structural. A short reply is not unfinished by length alone.
  The only prose match is a short explicit deferral. Continuation uses that
  decision and does not guess from the prose. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Const
  { A longer answer is not scanned for deferral words. Short text alone is finished. }
  AssistantDeferralMaxChars = 240;
  { Automatic continuations per task until item 5.1 stores the setting. }
  DefaultAutomaticContinuationCap = 3;

Type
  TAssistantTurnFinishReason = (
    atfFinished,
    atfTruncated,
    atfToolRoundCap,
    atfEmptyAfterTools,
    atfDeferral,
    atfPlanInProgress
  );

  TAssistantTurnFinish = Record
    Reason: TAssistantTurnFinishReason;
    Unfinished: Boolean;
  End;

  { Facts already known at the Ready gate. Do not infer them from the prose. }
  TAssistantTurnFinishFacts = Record
    { response.incomplete, or chat finish_reason length. }
    Truncated: Boolean;
    ToolRoundCap: Boolean;
    AssistantText: String;
    HadToolRound: Boolean;
    PlanItemInProgress: Boolean;
    { Blocked, and the item body already has a User action line. Not unfinished for that reason. }
    PlanItemBlockedWithUserAction: Boolean;
  End;

  TAssistantContinuation = Record
    ContinueTurn: Boolean;
    Note: String;
  End;

Function DefaultAssistantTurnFinishFacts: TAssistantTurnFinishFacts;
{ First matching rule wins. A normal reply with text, not truncated and not a deferral, is finished
  unless a plan item is still in progress and is not blocked with a user action. }
Function ClassifyAssistantTurnFinish(Const Facts: TAssistantTurnFinishFacts): TAssistantTurnFinish;
Function AssistantTurnFinishReasonName(Reason: TAssistantTurnFinishReason): String;
{ True only for the listed short deferrals, not for a long answer that happens to contain the words. }
Function AssistantReplyIsShortDeferral(Const Text: String): Boolean;
{ A User action line outside a fenced example. An empty line after the colon still counts. }
Function PlanBodyHasUserAction(Const Body: String): Boolean;
{ Cap until the recovery setting is snapshotted. }
Function AssistantAutomaticContinuationCap: Integer;
{ Model instruction for an injected continuation. Not the visible system note. }
Function AssistantContinuationInstruction: String;
{ Attempt is how many continuations have already been injected. }
Function AssistantDecideContinuation(Const Facts: TAssistantTurnFinishFacts; UserStopped, TerminalFault: Boolean;
  Attempt, Cap: Integer; Const ItemTitle: String): TAssistantContinuation;
Function AssistantTurnFinishRemains(Reason: TAssistantTurnFinishReason; Const ItemTitle: String): String;

Implementation

Uses
  Classes;

Const
  DeferralPhrases: Array[0..2] Of String = (
    'i can continue if you want',
    'let me know if you want me to continue',
    'should i proceed');

Function DefaultAssistantTurnFinishFacts: TAssistantTurnFinishFacts;
Begin
  Result.Truncated := False;
  Result.ToolRoundCap := False;
  Result.AssistantText := '';
  Result.HadToolRound := False;
  Result.PlanItemInProgress := False;
  Result.PlanItemBlockedWithUserAction := False;
End;

Function AssistantTurnFinishReasonName(Reason: TAssistantTurnFinishReason): String;
Begin
  Case Reason Of
    atfTruncated: Result := 'truncated';
    atfToolRoundCap: Result := 'tool_round_cap';
    atfEmptyAfterTools: Result := 'empty_after_tools';
    atfDeferral: Result := 'deferral';
    atfPlanInProgress: Result := 'plan_in_progress';
  Else
    Result := 'finished';
  End;
End;

Function IsAsciiSpace(C: Char): Boolean;
Begin
  Result := C <= ' ';
End;

Function IsTrailingPunct(C: Char): Boolean;
Begin
  Result := C In ['.', '!', '?', ',', ';', ':', '"', '''', ')'];
End;

Function NormalizedReply(Const Text: String): String;
Var
  I: Integer;
  C: Char;
  PendingSpace: Boolean;
Begin
  Result := '';
  PendingSpace := False;
  For I := 1 To Length(Text) Do
    Begin
      C := Text[I];
      If IsAsciiSpace(C) Then
        Begin
          If Result <> '' Then
            PendingSpace := True;
        End
      Else
        Begin
          If PendingSpace Then
            Result := Result + ' ';
          PendingSpace := False;
          Result := Result + C;
        End;
    End;
  Result := LowerCase(Trim(Result));
  While (Result <> '') And IsTrailingPunct(Result[Length(Result)]) Do
    Begin
      SetLength(Result, Length(Result) - 1);
      Result := Trim(Result);
    End;
End;

Function AssistantReplyIsShortDeferral(Const Text: String): Boolean;
Var
  Normalized: String;
  I: Integer;
Begin
  Result := False;
  Normalized := NormalizedReply(Text);
  If (Normalized = '') Or (Length(Normalized) > AssistantDeferralMaxChars) Then
    Exit;
  For I := 0 To High(DeferralPhrases) Do
    If Pos(DeferralPhrases[I], Normalized) > 0 Then
      Exit(True);
End;

Function PlanBodyHasUserAction(Const Body: String): Boolean;
Var
  Lines: TStringList;
  I, N, FenceLength: Integer;
  Line: String;
  Fence: Char;
Begin
  Result := False;
  Lines := TStringList.Create;
  Try
    Lines.Text := Body;
    Fence := #0;
    FenceLength := 0;
    For I := 0 To Lines.Count - 1 Do
      Begin
        Line := Trim(Lines[I]);
        If (Copy(Line, 1, 3) = '```') Or (Copy(Line, 1, 3) = '~~~') Then
          Begin
            N := 1;
            While (N <= Length(Line)) And (Line[N] = Line[1]) Do
              Inc(N);
            Dec(N);
            If Fence = #0 Then
              Begin
                Fence := Line[1];
                FenceLength := N;
              End
            Else If (Line[1] = Fence) And (N >= FenceLength) And (Trim(Copy(Line, N + 1, MaxInt)) = '') Then
              Fence := #0;
            Continue;
          End;
        If Fence <> #0 Then
          Continue;
        If SameText(Copy(Line, 1, 12), 'User action:') Then
          Exit(True);
      End;
  Finally
    Lines.Free;
  End;
End;

Function ClassifyAssistantTurnFinish(Const Facts: TAssistantTurnFinishFacts): TAssistantTurnFinish;
Begin
  If Facts.Truncated Then
    Result.Reason := atfTruncated
  Else If Facts.ToolRoundCap Then
    Result.Reason := atfToolRoundCap
  Else If Facts.HadToolRound And (Trim(Facts.AssistantText) = '') Then
    Result.Reason := atfEmptyAfterTools
  Else If AssistantReplyIsShortDeferral(Facts.AssistantText) Then
    Result.Reason := atfDeferral
  Else If Facts.PlanItemInProgress And (Not Facts.PlanItemBlockedWithUserAction) Then
    Result.Reason := atfPlanInProgress
  Else
    Result.Reason := atfFinished;
  Result.Unfinished := Result.Reason <> atfFinished;
End;

Function AssistantAutomaticContinuationCap: Integer;
Begin
  Result := DefaultAutomaticContinuationCap;
End;

Function AssistantContinuationInstruction: String;
Begin
  Result := 'Resume from the last tool results. Do not stop until the task is done or a real block is written.';
End;

Function StoppedPhrase(Reason: TAssistantTurnFinishReason; Const ItemTitle: String): String;
Begin
  Case Reason Of
    atfTruncated: Result := 'The reply was truncated.';
    atfToolRoundCap: Result := 'The tool-round limit was reached.';
    atfEmptyAfterTools: Result := 'The assistant reply was empty after tools.';
    atfDeferral: Result := 'The assistant deferred.';
    atfPlanInProgress:
      If Trim(ItemTitle) <> '' Then
        Result := '"' + ItemTitle + '" is still in progress.'
      Else
        Result := 'The plan item is still in progress.';
  Else
    Result := 'The turn is unfinished.';
  End;
End;

Function AssistantTurnFinishRemains(Reason: TAssistantTurnFinishReason; Const ItemTitle: String): String;
Begin
  Case Reason Of
    atfTruncated: Result := 'The reply is still truncated.';
    atfToolRoundCap: Result := 'The tool-round limit was reached.';
    atfEmptyAfterTools: Result := 'There is still no assistant answer after the tools.';
    atfDeferral: Result := 'The assistant still deferred.';
    atfPlanInProgress:
      If Trim(ItemTitle) <> '' Then
        Result := '"' + ItemTitle + '" is still in progress.'
      Else
        Result := 'The plan item is still in progress.';
  Else
    Result := 'The task is still unfinished.';
  End;
End;

Function AssistantDecideContinuation(Const Facts: TAssistantTurnFinishFacts; UserStopped, TerminalFault: Boolean;
  Attempt, Cap: Integer; Const ItemTitle: String): TAssistantContinuation;
Var
  Decision: TAssistantTurnFinish;
Begin
  Result.ContinueTurn := False;
  Result.Note := '';
  If UserStopped Or TerminalFault Then
    Exit;
  Decision := ClassifyAssistantTurnFinish(Facts);
  If Not Decision.Unfinished Then
    Exit;
  { A blocked item that already names a user action is not continued, even if the reply was truncated. }
  If Facts.PlanItemBlockedWithUserAction Then
    Exit;
  If Cap < 1 Then
    Cap := DefaultAutomaticContinuationCap;
  If Attempt < 0 Then
    Attempt := 0;
  If Attempt >= Cap Then
    Begin
      Result.Note := 'Automatic continuation stopped. ' + AssistantTurnFinishRemains(Decision.Reason, ItemTitle);
      Exit;
    End;
  Result.ContinueTurn := True;
  Result.Note := StoppedPhrase(Decision.Reason, ItemTitle) + ' The assistant is resuming. Attempt ' +
    IntToStr(Attempt + 1) + ' of ' + IntToStr(Cap) + '.';
End;

End.
