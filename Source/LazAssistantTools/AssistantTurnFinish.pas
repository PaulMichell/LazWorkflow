Unit AssistantTurnFinish;

{ Whether a turn that is about to return Ready is actually finished (c) 2026 Michell Computing.

  The decision is structural. A short reply is not unfinished by length alone.
  The only prose match is a short explicit deferral. Continuation uses that
  decision and does not guess from the prose. A finished turn with no assistant
  text gets one short trace summary. Text the model already wrote is kept. }

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
{ True only for the listed short deferrals, not for a long answer that happens to contain the words. }
Function AssistantReplyIsShortDeferral(Const Text: String): Boolean;
{ A User action line outside a fenced example. An empty line after the colon still counts.
  ActionText is the text after the colon. A fenced example does not count. }
Function PlanBodyUserAction(Const Body: String; Out ActionText: String): Boolean;
Function PlanBodyHasUserAction(Const Body: String): Boolean;
{ Stored automatic continuations, or the default when no config is loaded. }
Function AssistantAutomaticContinuationCap: Integer;
{ Model instruction for an injected continuation. Not the visible system note. }
Function AssistantContinuationInstruction: String;
{ Attempt is how many continuations have already been injected. }
Function AssistantDecideContinuation(Const Facts: TAssistantTurnFinishFacts; UserStopped, TerminalFault: Boolean;
  Attempt, Cap: Integer; Const ItemTitle: String): TAssistantContinuation;
Function AssistantTurnFinishRemains(Reason: TAssistantTurnFinishReason; Const ItemTitle: String): String;

Type
  { One tool or subagent the summary may name. Detail is optional and may be long; it is shortened. }
  TAssistantSummaryTool = Record
    Name: String;
    Ok: Boolean;
    Detail: String;
  End;
  TAssistantSummaryToolArray = Array Of TAssistantSummaryTool;

{ True when the assistant message is missing, so a trace summary may be written. Non-empty text is kept. }
Function AssistantNeedsFinalSummary(Const AssistantText: String): Boolean;
{ Asked, the tools that ran, and the outcome. Always non-empty. Does not repeat text the model already wrote. }
Function AssistantFinalSummary(Const Asked: String; Const Tools: TAssistantSummaryToolArray): String;
{ A successful turn needs a response. A cancel or other error may be stored with an empty reply. }
Function AssistantMayStoreTurn(Const ErrorText, Response: String): Boolean;

Implementation

Uses
  Classes, AssistantConfig;

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

Function PlanBodyUserAction(Const Body: String; Out ActionText: String): Boolean;
Var
  Lines: TStringList;
  I, N, FenceLength: Integer;
  Line: String;
  Fence: Char;
Begin
  Result := False;
  ActionText := '';
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
          Begin
            ActionText := Trim(Copy(Line, 13, MaxInt));
            Exit(True);
          End;
      End;
  Finally
    Lines.Free;
  End;
End;

Function PlanBodyHasUserAction(Const Body: String): Boolean;
Var
  ActionText: String;
Begin
  Result := PlanBodyUserAction(Body, ActionText);
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
  If Assigned(AssistantChatConfig) Then
    Result := AssistantChatConfig.AutomaticContinuations
  Else
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
  If Cap < 0 Then
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

Const
  SummaryAskedMax = 160;
  SummaryDetailMax = 120;
  SummaryNameMax = 48;
  SummaryToolNamesShown = 8;
  SummaryFailuresShown = 4;

Function AssistantNeedsFinalSummary(Const AssistantText: String): Boolean;
Begin
  Result := Trim(AssistantText) = '';
End;

Function AssistantMayStoreTurn(Const ErrorText, Response: String): Boolean;
Begin
  If Trim(ErrorText) <> '' Then
    Exit(True);
  Result := Trim(Response) <> '';
End;

Function CollapseSpaces(Const Text: String): String;
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
      If C <= ' ' Then
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
  Result := Trim(Result);
End;

Function CollapseLine(Const Text: String; MaxChars: Integer): String;
Begin
  Result := CollapseSpaces(Text);
  If MaxChars < 1 Then
    MaxChars := 1;
  If Length(Result) > MaxChars Then
    Result := Copy(Result, 1, MaxChars) + '...';
End;

Function FirstLine(Const Text: String; MaxChars: Integer): String;
Var
  Line: String;
  BreakAt: Integer;
Begin
  Line := Text;
  BreakAt := Pos(#10, Line);
  If BreakAt > 0 Then
    Line := Copy(Line, 1, BreakAt - 1);
  BreakAt := Pos(#13, Line);
  If BreakAt > 0 Then
    Line := Copy(Line, 1, BreakAt - 1);
  Result := CollapseLine(Line, MaxChars);
End;

Function SummaryToolName(Const Name: String): String;
Begin
  Result := CollapseLine(Name, SummaryNameMax);
  If Result = '' Then
    Result := 'tool';
End;

Function AssistantFinalSummary(Const Asked: String; Const Tools: TAssistantSummaryToolArray): String;
Type
  TNameRoll = Record
    Name: String;
    Count: Integer;
    Failed: Boolean;
    Detail: String;
  End;
  TNameRollArray = Array Of TNameRoll;
Var
  Rolls: TNameRollArray;
  Failed: TStringList;
  I, J, Shown, Distinct: Integer;
  Name, Detail, ToolLine, FailLine, AskedLine: String;
  Found: Boolean;
Begin
  Rolls := Nil;
  Failed := TStringList.Create;
  Try
    For I := 0 To High(Tools) Do
      Begin
        Name := SummaryToolName(Tools[I].Name);
        Found := False;
        For J := 0 To High(Rolls) Do
          If SameText(Rolls[J].Name, Name) Then
            Begin
              Inc(Rolls[J].Count);
              If Not Tools[I].Ok Then
                Rolls[J].Failed := True;
              If (Rolls[J].Detail = '') And (Not Tools[I].Ok) Then
                Rolls[J].Detail := FirstLine(Tools[I].Detail, SummaryDetailMax);
              Found := True;
              Break;
            End;
        If Found Then
          Continue;
        J := Length(Rolls);
        SetLength(Rolls, J + 1);
        Rolls[J].Name := Name;
        Rolls[J].Count := 1;
        Rolls[J].Failed := Not Tools[I].Ok;
        If Rolls[J].Failed Then
          Rolls[J].Detail := FirstLine(Tools[I].Detail, SummaryDetailMax)
        Else
          Rolls[J].Detail := '';
      End;
    ToolLine := '';
    Shown := Length(Rolls);
    If Shown > SummaryToolNamesShown Then
      Shown := SummaryToolNamesShown;
    For I := 0 To Shown - 1 Do
      Begin
        If ToolLine <> '' Then
          ToolLine := ToolLine + ', ';
        ToolLine := ToolLine + Rolls[I].Name;
        If Rolls[I].Failed And (Rolls[I].Count > 1) Then
          ToolLine := ToolLine + ' (' + IntToStr(Rolls[I].Count) + ', failed)'
        Else If Rolls[I].Failed Then
          ToolLine := ToolLine + ' (failed)'
        Else If Rolls[I].Count > 1 Then
          ToolLine := ToolLine + ' (' + IntToStr(Rolls[I].Count) + ')';
      End;
    Distinct := Length(Rolls) - Shown;
    If Distinct > 0 Then
      Begin
        If ToolLine <> '' Then
          ToolLine := ToolLine + ', ';
        ToolLine := ToolLine + 'and ' + IntToStr(Distinct) + ' more';
      End;
    If ToolLine = '' Then
      ToolLine := 'none';
    Detail := '';
    For I := 0 To High(Rolls) Do
      If Rolls[I].Failed Then
        Begin
          Failed.Add(Rolls[I].Name);
          If (Detail = '') And (Rolls[I].Detail <> '') Then
            Detail := Rolls[I].Detail;
        End;
    If Failed.Count = 0 Then
      Begin
        If Length(Rolls) = 0 Then
          FailLine := 'No assistant text was returned.'
        Else
          FailLine := 'The tools finished.';
      End
    Else
      Begin
        FailLine := '';
        Shown := Failed.Count;
        If Shown > SummaryFailuresShown Then
          Shown := SummaryFailuresShown;
        For I := 0 To Shown - 1 Do
          Begin
            If I = 0 Then
              FailLine := Failed[I]
            Else If (I = Shown - 1) And (Failed.Count <= SummaryFailuresShown) Then
              FailLine := FailLine + ' and ' + Failed[I]
            Else
              FailLine := FailLine + ', ' + Failed[I];
          End;
        If Failed.Count > SummaryFailuresShown Then
          FailLine := FailLine + ', and ' + IntToStr(Failed.Count - SummaryFailuresShown) + ' more';
        FailLine := FailLine + ' failed';
        If Detail <> '' Then
          FailLine := FailLine + ': ' + Detail;
        FailLine := FailLine + '.';
      End;
  Finally
    Failed.Free;
  End;
  If Trim(Asked) = '' Then
    AskedLine := 'no prompt text'
  Else
    AskedLine := CollapseLine(Asked, SummaryAskedMax);
  If (AskedLine <> '') And (Not (AskedLine[Length(AskedLine)] In ['.', '!', '?'])) Then
    AskedLine := AskedLine + '.';
  Result := 'Asked: ' + AskedLine + LineEnding + LineEnding + 'Tools: ' + ToolLine + '.' + LineEnding + LineEnding +
    'Outcome: ' + FailLine;
End;

End.
