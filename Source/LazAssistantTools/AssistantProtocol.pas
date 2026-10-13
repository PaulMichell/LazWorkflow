Unit AssistantProtocol;

{ Responses / Chat Completions request types and JSON builders (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantImages;

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
    { User messages only. Other kinds keep string content even if this is set. }
    ImageRefs: TAssistantImageRefArray;
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
    { Project root used to read upload derivatives. Empty when the item has no images. }
    ProjectRoot: String;
    { low | medium | high. Empty omits text.verbosity (Responses only). }
    AnswerVerbosity: String;
    { 0 omits the output cap. }
    MaxOutputTokens: Integer;
    { off | auto | on. Empty or off sends no search. }
    SearchMode: String;
    SearchCitations: Boolean;
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

Implementation

Function JsonEscapeText(Const SourceText: String): String;
Const
  Replacement = #$EF#$BF#$BD;
Var
  I, Len, Need, Extra, Code, Used, Capacity: Integer;
  Lead, Cont: Byte;
  Procedure Grow(ExtraBytes: Integer);
  Begin
    If Used + ExtraBytes <= Capacity Then Exit;
    If Capacity < 16 Then Capacity := 16;
    While Used + ExtraBytes > Capacity Do Capacity := Capacity * 2;
    SetLength(Result, Capacity);
  End;
  Procedure AppendRaw(Const Text: String);
  Var
    Count: Integer;
  Begin
    Count := Length(Text);
    If Count = 0 Then Exit;
    Grow(Count);
    Move(Text[1], Result[Used + 1], Count);
    Inc(Used, Count);
  End;
  Procedure AppendByte(Value: Byte);
  Begin
    Grow(1);
    Inc(Used);
    Result[Used] := Chr(Value);
  End;
  Procedure AppendAscii(Value: Byte);
  Begin
    Case Chr(Value) Of
      '"': AppendRaw('\"');
      '\': AppendRaw('\\');
      #8: AppendRaw('\b');
      #9: AppendRaw('\t');
      #10: AppendRaw('\n');
      #12: AppendRaw('\f');
      #13: AppendRaw('\r');
    Else
      If Value < 32 Then AppendRaw('\u' + IntToHex(Value, 4))
      Else AppendByte(Value);
    End;
  End;
Begin
  { Tool output can contain raw bytes from a file. A strict JSON parser rejects
    those bytes as an invalid Unicode code point, so only scalar values are kept.
    The buffer doubles so a large body is not copied once per byte. }
  Result := '';
  Len := Length(SourceText);
  If Len = 0 Then Exit;
  Used := 0;
  Capacity := Len;
  SetLength(Result, Capacity);
  I := 1;
  While I <= Len Do
    Begin
      Lead := Ord(SourceText[I]);
      If Lead < $80 Then
        Begin
          AppendAscii(Lead);
          Inc(I);
          Continue;
        End;
      Need := 0;
      Code := 0;
      If (Lead >= $C2) And (Lead <= $DF) Then
        Begin
          Need := 2;
          Code := Lead And $1F;
        End
      Else If (Lead >= $E0) And (Lead <= $EF) Then
        Begin
          Need := 3;
          Code := Lead And $0F;
        End
      Else If (Lead >= $F0) And (Lead <= $F4) Then
        Begin
          Need := 4;
          Code := Lead And $07;
        End;
      If (Need = 0) Or (I + Need - 1 > Len) Then
        Begin
          AppendRaw(Replacement);
          Inc(I);
          Continue;
        End;
      For Extra := 1 To Need - 1 Do
        Begin
          Cont := Ord(SourceText[I + Extra]);
          If (Cont And $C0) <> $80 Then
            Begin
              Need := 0;
              Break;
            End;
          Code := (Code Shl 6) Or (Cont And $3F);
        End;
      If (Need = 0) Or (Code > $10FFFF) Or ((Code >= $D800) And (Code <= $DFFF)) Or
        ((Need = 2) And (Code < $80)) Or ((Need = 3) And (Code < $800)) Or
        ((Need = 4) And (Code < $10000)) Then
        Begin
          AppendRaw(Replacement);
          Inc(I);
          Continue;
        End;
      Grow(Need);
      Move(SourceText[I], Result[Used + 1], Need);
      Inc(Used, Need);
      Inc(I, Need);
    End;
  SetLength(Result, Used);
End;

Function DefaultSamplerRequestOptions: TSamplerRequestOptions;
Begin
  Result.Model := 'grok-4.5';
  Result.ToolsJson := '';
  Result.ReasoningEffort := 'high';
  Result.IncludeEncryptedReasoning := True;
  Result.ProjectRoot := '';
  Result.AnswerVerbosity := '';
  Result.MaxOutputTokens := 0;
  Result.SearchMode := '';
  Result.SearchCitations := False;
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

Function ItemCarriesUserImages(Const Item: TSamplerInputItem): Boolean;
Begin
  Result := (Item.Kind = sikMessage) And SameText(Item.Role, 'user') And (Length(Item.ImageRefs) > 0);
End;

Function QuotedJson(Const Value: String): String;
Begin
  Result := '"' + JsonEscapeText(Value) + '"';
End;

Function UploadDataUri(Const ProjectRoot: String; Const Ref: TAssistantImageRef): String;
Var
  ErrorText: String;
Begin
  If Not AssistantImageDataUri(ProjectRoot, Ref, Result, ErrorText) Then
    Raise Exception.Create(ErrorText);
End;

{ Frozen against Tests/Fixtures/XaiImageUnderstandingParts.json.
  Responses image_url is a data URI string. Chat image_url.url is a data URI; detail is omitted. }
Function UserImageContentArray(Const Item: TSamplerInputItem; Const ProjectRoot: String; ResponsesWire: Boolean): String;
Var
  I: Integer;
  Uri, ImagePart, TextPart: String;
Begin
  Result := '';
  For I := 0 To High(Item.ImageRefs) Do
    Begin
      Uri := UploadDataUri(ProjectRoot, Item.ImageRefs[I]);
      If ResponsesWire Then
        ImagePart := '{"type":"input_image","image_url":' + QuotedJson(Uri) + '}'
      Else
        ImagePart := '{"type":"image_url","image_url":{"url":' + QuotedJson(Uri) + '}}';
      If Result <> '' Then
        Result := Result + ',';
      Result := Result + ImagePart;
    End;
  If ResponsesWire Then
    TextPart := '{"type":"input_text","text":' + QuotedJson(Item.Content) + '}'
  Else
    TextPart := '{"type":"text","text":' + QuotedJson(Item.Content) + '}';
  If Result <> '' Then
    Result := Result + ',';
  Result := '[' + Result + TextPart + ']';
End;

Function ItemToResponsesJson(Const Item: TSamplerInputItem; Const ProjectRoot: String): String;
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
    If ItemCarriesUserImages(Item) Then
      Result := '{"role":"user","content":' + UserImageContentArray(Item, ProjectRoot, True) + '}'
    Else
      Result := '{"role":"' + JsonEscapeText(Item.Role) + '","content":"' +
        JsonEscapeText(Item.Content) + '"}';
  End;
End;

Function ItemToChatCompletionsJson(Const Item: TSamplerInputItem; Const ProjectRoot: String): String;
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
    If ItemCarriesUserImages(Item) Then
      Result := '{"role":"user","content":' + UserImageContentArray(Item, ProjectRoot, False) + '}'
    Else
      Result := '{"role":"' + JsonEscapeText(Item.Role) + '","content":"' +
        JsonEscapeText(Item.Content) + '"}';
  End;
End;

Function ActiveSearchMode(Const Mode: String): String;
Begin
  Result := LowerCase(Trim(Mode));
  If (Result <> 'auto') And (Result <> 'on') Then
    Result := '';
End;

Function ActiveVerbosity(Const Value: String): String;
Begin
  Result := LowerCase(Trim(Value));
  If (Result <> 'low') And (Result <> 'medium') And (Result <> 'high') Then
    Result := '';
End;

Function ToolsWithGrokSearch(Const ToolsJson, SearchMode: String): String;
Const
  SearchTools = '{"type":"web_search"},{"type":"x_search"}';
Begin
  Result := ToolsJson;
  If ActiveSearchMode(SearchMode) = '' Then
    Exit;
  If Pos('"web_search"', LowerCase(ToolsJson)) > 0 Then
    Exit;
  If Trim(ToolsJson) = '' Then
    Result := '[' + SearchTools + ']'
  Else If ToolsJson[Length(ToolsJson)] = ']' Then
    Begin
      If Length(Trim(ToolsJson)) <= 2 Then
        Result := '[' + SearchTools + ']'
      Else
        Result := Copy(ToolsJson, 1, Length(ToolsJson) - 1) + ',' + SearchTools + ']';
    End;
End;

Function BuildResponsesRequestJson(Const Items: TSamplerInputItemArray;
  Const Options: TSamplerRequestOptions): String;
Var
  Parts: Array Of String;
  I, Count: Integer;
  Effort, Tools: String;
Begin
  SetLength(Parts, Length(Items));
  Count := 0;
  For I := 0 To High(Items) Do
    Begin
      Parts[Count] := ItemToResponsesJson(Items[I], Options.ProjectRoot);
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
  Tools := Options.ToolsJson;
  If ActiveSearchMode(Options.SearchMode) <> '' Then
    Tools := ToolsWithGrokSearch(Tools, Options.SearchMode);
  If Trim(Tools) <> '' Then
    Result := Result + ',"tools":' + Tools;
  If Options.MaxOutputTokens > 0 Then
    Result := Result + ',"max_output_tokens":' + IntToStr(Options.MaxOutputTokens);
  If ActiveVerbosity(Options.AnswerVerbosity) <> '' Then
    Result := Result + ',"text":{"verbosity":"' + JsonEscapeText(ActiveVerbosity(Options.AnswerVerbosity)) + '"}';
  Result := Result + '}';
End;

Function BuildChatCompletionsRequestJson(Const Items: TSamplerInputItemArray;
  Const Options: TSamplerRequestOptions): String;
Var
  Parts: Array Of String;
  I, Count: Integer;
  Effort, Mode: String;
Begin
  SetLength(Parts, Length(Items));
  Count := 0;
  For I := 0 To High(Items) Do
    Begin
      Parts[Count] := ItemToChatCompletionsJson(Items[I], Options.ProjectRoot);
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
  Mode := ActiveSearchMode(Options.SearchMode);
  If Mode <> '' Then
    Begin
      Result := Result + ',"search_parameters":{"mode":"' + JsonEscapeText(Mode) + '"';
      If Options.SearchCitations Then
        Result := Result + ',"return_citations":true';
      Result := Result + '}';
    End;
  If Options.MaxOutputTokens > 0 Then
    Result := Result + ',"max_completion_tokens":' + IntToStr(Options.MaxOutputTokens);
  Result := Result + '}';
End;

End.
