Unit AssistantCodexContext;

{ Runtime context measurements and presentation for ChatGPT connections (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  fpjson;

Type
  TCodexTokenCounts = Record
    TotalTokens, InputTokens, CachedInputTokens, OutputTokens, ReasoningOutputTokens: Int64;
  End;
  TCodexContextUsage = Record
    Reported: Boolean;
    ModelContextWindow: Int64;
    Last, Total: TCodexTokenCounts;
  End;

/// Missing or invalid counters are unknown (-1), including a nullable capacity.
Function EmptyCodexContextUsage: TCodexContextUsage;
Function ParseCodexContextUsage(Node: TJSONData; Out Usage: TCodexContextUsage): Boolean;
/// Uses the latest request footprint, never the cumulative thread counters.
Function CodexContextCaption(Const Usage: TCodexContextUsage; EstimatedTokens: Integer): String;
Function CodexContextDetails(Const Usage: TCodexContextUsage; EstimatedTokens: Integer): String;

Implementation

Uses
  SysUtils;

Function Counter(Node: TJSONData; Const FieldName: String): Int64;
Var
  Value: TJSONData;
Begin
  Result := -1;
  If Not (Node Is TJSONObject) Then Exit;
  Value := TJSONObject(Node).Find(FieldName);
  If Not Assigned(Value) Or (Value.JSONType <> jtNumber) Then Exit;
  If Not TryStrToInt64(Value.AsJSON, Result) Or (Result < 0) Then Result := -1;
End;

Function Counts(Node: TJSONData): TCodexTokenCounts;
Begin
  Result.TotalTokens := Counter(Node, 'totalTokens');
  Result.InputTokens := Counter(Node, 'inputTokens');
  Result.CachedInputTokens := Counter(Node, 'cachedInputTokens');
  Result.OutputTokens := Counter(Node, 'outputTokens');
  Result.ReasoningOutputTokens := Counter(Node, 'reasoningOutputTokens');
End;

Function EmptyCodexContextUsage: TCodexContextUsage;
Begin
  Result.Reported := False;
  Result.ModelContextWindow := -1;
  Result.Last := Counts(Nil);
  Result.Total := Counts(Nil);
End;

Function ParseCodexContextUsage(Node: TJSONData; Out Usage: TCodexContextUsage): Boolean;
Begin
  Usage := EmptyCodexContextUsage;
  Result := Node Is TJSONObject;
  If Not Result Then Exit;
  Usage.ModelContextWindow := Counter(Node, 'modelContextWindow');
  Usage.Last := Counts(TJSONObject(Node).Find('last'));
  Usage.Total := Counts(TJSONObject(Node).Find('total'));
  Usage.Reported := True;
End;

Function TokenText(Value: Int64): String;
Begin
  If Value < 0 Then
    Result := 'not reported'
  Else
    Result := IntToStr(Value);
End;

Function CodexContextCaption(Const Usage: TCodexContextUsage; EstimatedTokens: Integer): String;
Var
  Percent: Extended;
Begin
  If Usage.Reported And (Usage.Last.TotalTokens >= 0) And (Usage.ModelContextWindow > 0) Then
    Begin
      Percent := Usage.Last.TotalTokens / Usage.ModelContextWindow * 100;
      Result := Format('Context ~%.1f%%', [Percent]);
      If Percent >= 95 Then Result := Result + ' ⚠';
    End
  Else If Usage.Reported And (Usage.Last.TotalTokens >= 0) Then
    Result := Format('Context %d tokens (capacity unknown)', [Usage.Last.TotalTokens])
  Else
    Result := Format('Context ~%d tokens (capacity unknown)', [EstimatedTokens]);
End;

Function CountDetails(Const Value: TCodexTokenCounts): String;
Begin
  Result := '  Input: ' + TokenText(Value.InputTokens) + LineEnding +
    '  Cached input (included in input): ' + TokenText(Value.CachedInputTokens) + LineEnding +
    '  Output: ' + TokenText(Value.OutputTokens) + LineEnding +
    '  Reasoning output (included in output): ' + TokenText(Value.ReasoningOutputTokens) + LineEnding +
    '  Total: ' + TokenText(Value.TotalTokens);
End;

Function CodexContextDetails(Const Usage: TCodexContextUsage; EstimatedTokens: Integer): String;
Begin
  Result := CodexContextCaption(Usage, EstimatedTokens) + LineEnding + LineEnding +
    'Runtime context capacity: ' + TokenText(Usage.ModelContextWindow) + ' tokens' + LineEnding;
  If Usage.Reported Then
    Result := Result + LineEnding + 'Latest model request (tokens):' + LineEnding + CountDetails(Usage.Last) +
      LineEnding + LineEnding + 'Cumulative runtime thread usage (tokens; not context occupancy):' + LineEnding +
      CountDetails(Usage.Total) + LineEnding + LineEnding +
      'Source: ChatGPT runtime token-usage notification. The approximate percentage uses the latest request total / ' +
      'runtime context capacity. It is a snapshot at the last usage update; tools and generation can change it.'
  Else
    Result := Result + LineEnding + 'Runtime token usage has not been reported for this request.' + LineEnding +
      'The text estimate excludes runtime instructions, tool definitions, tool exchanges and image costs. ' +
      'A usage percentage is unavailable until the runtime reports both usage and capacity.';
  Result := Result + LineEnding + LineEnding +
    'Each ChatGPT send starts a runtime thread with the current prompt, IDE context and a bounded conversation recap. ' +
    'Cumulative counters apply to that thread. Context usage is separate from subscription allowance (Credits).';
End;

End.
