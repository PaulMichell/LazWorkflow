Unit AssistantProtocol;

{ Responses / Chat Completions request types and JSON builders (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Type
  { Which inference wire this parser / request uses. }
  TSamplerWireKind = (swkResponses, swkChatCompletions);

  TSamplerEventKind = (
    sekNone,
    sekStreamStarted,
    sekThoughtDelta,
    sekContentDelta,
    sekToolCallDelta,
    sekCompleted,
    sekFailed
  );

  TSamplerInputKind = (
    sikMessage,
    sikReasoning,
    sikFunctionCall,
    sikFunctionOutput,
    sikProviderOutput
  );

  TSamplerToolCall = Record
    { Id is the function call ID used when submitting its result. }
    Id: String;
    ItemId: String;
    Name: String;
    Arguments: String;
  End;
  TSamplerToolCallArray = Array Of TSamplerToolCall;

  { One conversation item for the next request (messages, encrypted reasoning, tools). }
  TSamplerInputItem = Record
    Kind: TSamplerInputKind;
    Role: String;
    Content: String;
    EncryptedContent: String;
    ItemId: String;
    CallId: String;
    FunctionName: String;
    Arguments: String;
    ProviderJson: String;
  End;
  TSamplerInputItemArray = Array Of TSamplerInputItem;

  { Incremental stream event. Completed also copies accumulators onto the parser. }
  TSamplerEvent = Record
    Kind: TSamplerEventKind;
    Text: String;
    ToolIndex: Integer;
    ToolId: String;
    ToolItemId: String;
    ToolName: String;
    ErrorText: String;
    InputTokens: Integer;
    OutputTokens: Integer;
    ReasoningTokens: Integer;
  End;
  TSamplerEventArray = Array Of TSamplerEvent;

  { Options for building a streaming inference request. }
  TSamplerRequestOptions = Record
    Model: String;
    ToolsJson: String;
    ReasoningEffort: String;
    { When True (default), Responses requests include encrypted reasoning and store:false. }
    IncludeEncryptedReasoning: Boolean;
  End;

Function JsonEscapeText(Const SourceText: String): String;
Function DefaultSamplerRequestOptions: TSamplerRequestOptions;
Function SamplerInputMessage(Const Role, Content: String): TSamplerInputItem;
Function SamplerInputReasoning(Const ItemId, EncryptedContent: String): TSamplerInputItem;
Function SamplerInputFunctionCall(Const CallId, FunctionName, Arguments: String): TSamplerInputItem;
Function SamplerInputFunctionOutput(Const CallId, OutputText: String): TSamplerInputItem;
{ POST /v1/responses body. ToolsJson is a JSON array or empty. }
Function BuildResponsesRequestJson(Const Items: TSamplerInputItemArray;
  Const Options: TSamplerRequestOptions): String;
{ POST /v1/chat/completions body. Reasoning items are skipped (no wire field). }
Function BuildChatCompletionsRequestJson(Const Items: TSamplerInputItemArray;
  Const Options: TSamplerRequestOptions): String;
{ Append Delta onto Accum; True when Accum changed. Handles delta vs snapshot streams. }
Function MergeSamplerText(Var Accum: String; Const Delta: String): Boolean;

Implementation

Const
  MaxSamplerAccumChars = 400000;

Function JsonEscapeText(Const SourceText: String): String;
Var
  I: Integer;
  C: Char;
Begin
  Result := '';
  For I := 1 To Length(SourceText) Do
    Begin
      C := SourceText[I];
      Case C Of
        '"': Result := Result + '\"';
        '\': Result := Result + '\\';
        #8: Result := Result + '\b';
        #9: Result := Result + '\t';
        #10: Result := Result + '\n';
        #12: Result := Result + '\f';
        #13: Result := Result + '\r';
      Else
        If Ord(C) < 32 Then
          Result := Result + '\u' + IntToHex(Ord(C), 4)
        Else
          Result := Result + C;
      End;
    End;
End;

Function DefaultSamplerRequestOptions: TSamplerRequestOptions;
Begin
  Result.Model := 'grok-4.5';
  Result.ToolsJson := '';
  Result.ReasoningEffort := 'high';
  Result.IncludeEncryptedReasoning := True;
End;

Function SamplerInputMessage(Const Role, Content: String): TSamplerInputItem;
Begin
  Result := Default(TSamplerInputItem);
  Result.Kind := sikMessage;
  Result.Role := Role;
  Result.Content := Content;
End;

Function SamplerInputReasoning(Const ItemId, EncryptedContent: String): TSamplerInputItem;
Begin
  Result := Default(TSamplerInputItem);
  Result.Kind := sikReasoning;
  Result.ItemId := ItemId;
  Result.EncryptedContent := EncryptedContent;
End;

Function SamplerInputFunctionCall(Const CallId, FunctionName, Arguments: String): TSamplerInputItem;
Begin
  Result := Default(TSamplerInputItem);
  Result.Kind := sikFunctionCall;
  Result.CallId := CallId;
  Result.FunctionName := FunctionName;
  Result.Arguments := Arguments;
End;

Function SamplerInputFunctionOutput(Const CallId, OutputText: String): TSamplerInputItem;
Begin
  Result := Default(TSamplerInputItem);
  Result.Kind := sikFunctionOutput;
  Result.CallId := CallId;
  Result.Content := OutputText;
End;

Function JoinJsonParts(Const Parts: Array Of String; Count: Integer): String;
Var
  I, TotalLen, P, L: Integer;
Begin
  TotalLen := 0;
  For I := 0 To Count - 1 Do
    Begin
      Inc(TotalLen, Length(Parts[I]));
      If I > 0 Then
        Inc(TotalLen);
    End;
  SetLength(Result, TotalLen);
  P := 1;
  For I := 0 To Count - 1 Do
    Begin
      If I > 0 Then
        Begin
          Result[P] := ',';
          Inc(P);
        End;
      L := Length(Parts[I]);
      If L > 0 Then
        Move(Parts[I][1], Result[P], L);
      Inc(P, L);
    End;
End;

Function ItemToResponsesJson(Const Item: TSamplerInputItem): String;
Begin
  Case Item.Kind Of
    sikProviderOutput: Result := Item.ProviderJson;
    sikReasoning:
      Begin
        Result := '{"type":"reasoning"';
        If Item.ItemId <> '' Then
          Result := Result + ',"id":"' + JsonEscapeText(Item.ItemId) + '"';
        Result := Result + ',"encrypted_content":"' + JsonEscapeText(Item.EncryptedContent) + '"}';
      End;
    sikFunctionCall:
      Result := '{"type":"function_call","call_id":"' + JsonEscapeText(Item.CallId) +
        '","name":"' + JsonEscapeText(Item.FunctionName) +
        '","arguments":"' + JsonEscapeText(Item.Arguments) + '"}';
    sikFunctionOutput:
      Result := '{"type":"function_call_output","call_id":"' + JsonEscapeText(Item.CallId) +
        '","output":"' + JsonEscapeText(Item.Content) + '"}';
  Else
    Result := '{"role":"' + JsonEscapeText(Item.Role) + '","content":"' +
      JsonEscapeText(Item.Content) + '"}';
  End;
End;

Function ItemToChatCompletionsJson(Const Item: TSamplerInputItem): String;
Begin
  Case Item.Kind Of
    sikFunctionCall:
      Result := '{"role":"assistant","content":"","tool_calls":[{"id":"' +
        JsonEscapeText(Item.CallId) +
        '","type":"function","function":{"name":"' + JsonEscapeText(Item.FunctionName) +
        '","arguments":"' + JsonEscapeText(Item.Arguments) + '"}}]}';
    sikFunctionOutput:
      Result := '{"role":"tool","tool_call_id":"' + JsonEscapeText(Item.CallId) +
        '","content":"' + JsonEscapeText(Item.Content) + '"}';
    sikReasoning, sikProviderOutput:
      Result := '';
  Else
    Result := '{"role":"' + JsonEscapeText(Item.Role) + '","content":"' +
      JsonEscapeText(Item.Content) + '"}';
  End;
End;

Function BuildResponsesRequestJson(Const Items: TSamplerInputItemArray;
  Const Options: TSamplerRequestOptions): String;
Var
  Parts: Array Of String;
  I, Count: Integer;
  Effort: String;
Begin
  SetLength(Parts, Length(Items));
  Count := 0;
  For I := 0 To High(Items) Do
    Begin
      Parts[Count] := ItemToResponsesJson(Items[I]);
      If Parts[Count] <> '' Then
        Inc(Count);
    End;
  Result := '{"model":"' + JsonEscapeText(Options.Model) + '","stream":true,"store":false,"input":[' +
    JoinJsonParts(Parts, Count) + ']';
  If Options.IncludeEncryptedReasoning Then
    Result := Result + ',"include":["reasoning.encrypted_content"]';
  Effort := LowerCase(Trim(Options.ReasoningEffort));
  If Effort <> '' Then
    Result := Result + ',"reasoning":{"effort":"' + JsonEscapeText(Effort) + '"}';
  If Trim(Options.ToolsJson) <> '' Then
    Result := Result + ',"tools":' + Options.ToolsJson;
  Result := Result + '}';
End;

Function BuildChatCompletionsRequestJson(Const Items: TSamplerInputItemArray;
  Const Options: TSamplerRequestOptions): String;
Var
  Parts: Array Of String;
  I, Count: Integer;
  Effort: String;
Begin
  SetLength(Parts, Length(Items));
  Count := 0;
  For I := 0 To High(Items) Do
    Begin
      Parts[Count] := ItemToChatCompletionsJson(Items[I]);
      If Parts[Count] <> '' Then
        Inc(Count);
    End;
  Result := '{"model":"' + JsonEscapeText(Options.Model) + '","stream":true,"messages":[' +
    JoinJsonParts(Parts, Count) + ']';
  If Trim(Options.ToolsJson) <> '' Then
    Result := Result + ',"tools":' + Options.ToolsJson;
  Effort := LowerCase(Trim(Options.ReasoningEffort));
  If Effort <> '' Then
    Result := Result + ',"reasoning_effort":"' + JsonEscapeText(Effort) + '"';
  Result := Result + '}';
End;

Function CollapseTrailingPhraseRepeats(Const SourceText: String): String;
Var
  PhraseLen, Count, Limit: Integer;
Begin
  Result := SourceText;
  If Length(Result) < 24 Then
    Exit;
  { Cap phrase length: walking PhraseLen to Length/3 is O(n^2) and freezes the actor. }
  Limit := Length(Result) Div 3;
  If Limit > 96 Then
    Limit := 96;
  PhraseLen := 8;
  While PhraseLen <= Limit Do
    Begin
      Count := 1;
      While ((Count + 1) * PhraseLen <= Length(Result)) And
        (Copy(Result, Length(Result) - (Count + 1) * PhraseLen + 1, PhraseLen) =
         Copy(Result, Length(Result) - Count * PhraseLen + 1, PhraseLen)) Do
        Inc(Count);
      If Count >= 3 Then
        Begin
          SetLength(Result, Length(Result) - (Count - 1) * PhraseLen);
          Exit;
        End;
      Inc(PhraseLen, 8);
    End;
End;

Function SanitizeSamplerText(Const SourceText: String): String;
Var
  I: Integer;
  C: Char;
Begin
  Result := '';
  For I := 1 To Length(SourceText) Do
    Begin
      C := SourceText[I];
      If (C = #9) Or (C = #10) Or (C = #13) Or (Ord(C) >= 32) Then
        Result := Result + C;
    End;
End;

Function MergeSamplerText(Var Accum: String; Const Delta: String): Boolean;
Var
  Candidate: String;
Begin
  Result := False;
  If Delta = '' Then
    Exit;
  If Accum = '' Then
    Begin
      Accum := CollapseTrailingPhraseRepeats(SanitizeSamplerText(Delta));
      Result := True;
      Exit;
    End;
  If Delta = Accum Then
    Exit;
  If (Length(Delta) >= Length(Accum)) And (Copy(Delta, 1, Length(Accum)) = Accum) Then
    Begin
      Candidate := CollapseTrailingPhraseRepeats(SanitizeSamplerText(Delta));
      If Candidate = Accum Then
        Exit;
      Accum := Candidate;
      Result := True;
      Exit;
    End;
  If (Length(Delta) < Length(Accum)) And (Copy(Accum, 1, Length(Delta)) = Delta) Then
    Exit;
  If (Length(Accum) >= Length(Delta)) And
    (Copy(Accum, Length(Accum) - Length(Delta) + 1, Length(Delta)) = Delta) Then
    Exit;
  Candidate := SanitizeSamplerText(Delta);
  If (Length(Candidate) >= 48) And (Pos(Copy(Candidate, 1, 80), Accum) > 0) Then
    Exit;
  Candidate := CollapseTrailingPhraseRepeats(SanitizeSamplerText(Accum + Candidate));
  If Candidate = Accum Then
    Exit;
  If Length(Candidate) > MaxSamplerAccumChars Then
    Begin
      If Length(Accum) >= MaxSamplerAccumChars Then
        Exit;
      Accum := Copy(Candidate, 1, MaxSamplerAccumChars);
      Result := True;
      Exit;
    End;
  Accum := Candidate;
  Result := True;
End;

End.
