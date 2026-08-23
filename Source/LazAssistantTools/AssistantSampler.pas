Unit AssistantSampler;

{ Pure SSE transform for Responses and Chat Completions streams (c) 2026 Michell Computing.

  HTTP POST stays with the session actor. This unit is the grok-build sampler
  analogue: bytes in, TSamplerEvent out, no LCL. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantProtocol;

Type
  TAssistantSseParser = Class
  Private
    FWire: TSamplerWireKind;
    FWireKnown: Boolean;
    FBuffer: String;
    FEvents: TSamplerEventArray;
    FThinking: String;
    FContent: String;
    FEncryptedContent: String;
    FEncryptedId: String;
    FTools: TSamplerToolCallArray;
    FInputTokens: Integer;
    FOutputTokens: Integer;
    FReasoningTokens: Integer;
    FFailed: Boolean;
    FIncomplete: Boolean;
    FCompleted: Boolean;
    FErrorText: String;
    Procedure Emit(Const Event: TSamplerEvent);
    Procedure CompactEmptyTools;
    Procedure EnsureToolIndex(Index: Integer);
    Procedure MergeTool(Const Id, Name, Arguments: String);
    Procedure ProcessLine(Const Line: String);
    Procedure ParsePayload(Const Payload: String);
    Procedure ParseResponsesEvent(Obj: TObject);
    Procedure ParseChatCompletionsChunk(Obj: TObject);
    Procedure HarvestCompletedOutput(ResponseObj: TObject);
    Procedure ApplyUsage(ResponseObj: TObject);
  Public
    Constructor Create;
    Procedure Reset;
    { Append raw SSE bytes; may emit zero or more events. }
    Procedure Feed(Const Chunk: String);
    Function EventCount: Integer;
    Function GetEvent(Index: Integer): TSamplerEvent;
    Property Wire: TSamplerWireKind Read FWire;
    Property Thinking: String Read FThinking;
    Property Content: String Read FContent;
    Property EncryptedContent: String Read FEncryptedContent;
    Property EncryptedId: String Read FEncryptedId;
    Property ToolCalls: TSamplerToolCallArray Read FTools;
    Property InputTokens: Integer Read FInputTokens;
    Property OutputTokens: Integer Read FOutputTokens;
    Property ReasoningTokens: Integer Read FReasoningTokens;
    Property Failed: Boolean Read FFailed;
    Property Incomplete: Boolean Read FIncomplete;
    Property ErrorText: String Read FErrorText;
  End;

Implementation

Uses
  fpjson, jsonparser;

Function JsonStringField(Obj: TJSONObject; Const FieldName: String): String;
Var
  Node: TJSONData;
Begin
  Result := '';
  If Not Assigned(Obj) Then
    Exit;
  Node := Obj.Find(FieldName);
  If Not Assigned(Node) Then
    Exit;
  If Node.JSONType = jtNull Then
    Exit;
  Result := Node.AsString;
End;

Function JsonIntField(Obj: TJSONObject; Const FieldName: String): Integer;
Var
  Node: TJSONData;
Begin
  Result := 0;
  If Not Assigned(Obj) Then
    Exit;
  Node := Obj.Find(FieldName);
  If Not Assigned(Node) Then
    Exit;
  If Node.JSONType In [jtNumber, jtString] Then
    Result := Node.AsInteger;
End;

Function EmptySamplerEvent: TSamplerEvent;
Begin
  Result := Default(TSamplerEvent);
  Result.Kind := sekNone;
  Result.ToolIndex := -1;
End;

Constructor TAssistantSseParser.Create;
Begin
  Inherited Create;
  Reset;
End;

Procedure TAssistantSseParser.Reset;
Begin
  FWire := swkResponses;
  FWireKnown := False;
  FBuffer := '';
  SetLength(FEvents, 0);
  FThinking := '';
  FContent := '';
  FEncryptedContent := '';
  FEncryptedId := '';
  SetLength(FTools, 0);
  FInputTokens := 0;
  FOutputTokens := 0;
  FReasoningTokens := 0;
  FFailed := False;
  FIncomplete := False;
  FCompleted := False;
  FErrorText := '';
End;

Procedure TAssistantSseParser.Emit(Const Event: TSamplerEvent);
Var
  N: Integer;
Begin
  If Event.Kind = sekNone Then
    Exit;
  If Event.Kind = sekCompleted Then
    FCompleted := True;
  N := Length(FEvents);
  SetLength(FEvents, N + 1);
  FEvents[N] := Event;
End;

Function TAssistantSseParser.EventCount: Integer;
Begin
  Result := Length(FEvents);
End;

Function TAssistantSseParser.GetEvent(Index: Integer): TSamplerEvent;
Begin
  Result := EmptySamplerEvent;
  If (Index < 0) Or (Index >= Length(FEvents)) Then
    Exit;
  Result := FEvents[Index];
End;

Procedure TAssistantSseParser.EnsureToolIndex(Index: Integer);
Begin
  If Index < 0 Then
    Exit;
  If Index >= Length(FTools) Then
    SetLength(FTools, Index + 1);
End;

Procedure TAssistantSseParser.MergeTool(Const Id, Name, Arguments: String);
Var
  I, Slot: Integer;
Begin
  Slot := -1;
  If Id <> '' Then
    For I := 0 To High(FTools) Do
      If FTools[I].Id = Id Then
        Begin
          Slot := I;
          Break;
        End;
  If Slot < 0 Then
    Begin
      Slot := Length(FTools);
      SetLength(FTools, Slot + 1);
    End;
  If Id <> '' Then
    FTools[Slot].Id := Id;
  If Name <> '' Then
    FTools[Slot].Name := Name;
  If Arguments <> '' Then
    If FTools[Slot].Arguments = '' Then
      FTools[Slot].Arguments := Arguments
    Else If Pos(FTools[Slot].Arguments, Arguments) = 1 Then
      FTools[Slot].Arguments := Arguments
    Else If Pos(Arguments, FTools[Slot].Arguments) <> 1 Then
      FTools[Slot].Arguments := FTools[Slot].Arguments + Arguments;
End;

Procedure TAssistantSseParser.CompactEmptyTools;
Var
  I, N: Integer;
Begin
  N := 0;
  For I := 0 To High(FTools) Do
    If (FTools[I].Name <> '') Or (FTools[I].Id <> '') Or (FTools[I].Arguments <> '') Then
      Begin
        If N <> I Then
          FTools[N] := FTools[I];
        Inc(N);
      End;
  SetLength(FTools, N);
End;

Procedure TAssistantSseParser.Feed(Const Chunk: String);
Var
  P: Integer;
  Line: String;
Begin
  If Chunk = '' Then
    Exit;
  FBuffer := FBuffer + Chunk;
  FBuffer := StringReplace(FBuffer, #13#10, #10, [rfReplaceAll]);
  FBuffer := StringReplace(FBuffer, #13, #10, [rfReplaceAll]);
  Repeat
    P := Pos(#10, FBuffer);
    If P < 1 Then
      Break;
    Line := Copy(FBuffer, 1, P - 1);
    Delete(FBuffer, 1, P);
    ProcessLine(Line);
  Until False;
End;

Procedure TAssistantSseParser.ProcessLine(Const Line: String);
Var
  Trimmed, Payload: String;
  Event: TSamplerEvent;
Begin
  Trimmed := Trim(Line);
  If Trimmed = '' Then
    Exit;
  If Copy(Trimmed, 1, 5) <> 'data:' Then
    Exit;
  Payload := Trim(Copy(Trimmed, 6, MaxInt));
  If Payload = '' Then
    Exit;
  If Payload = '[DONE]' Then
    Begin
      If (Not FCompleted) And (Not FFailed) Then
        Begin
          CompactEmptyTools;
          Event := EmptySamplerEvent;
          Event.Kind := sekCompleted;
          Event.Text := FContent;
          Event.InputTokens := FInputTokens;
          Event.OutputTokens := FOutputTokens;
          Event.ReasoningTokens := FReasoningTokens;
          Emit(Event);
        End;
      Exit;
    End;
  ParsePayload(Payload);
End;

Procedure TAssistantSseParser.ParsePayload(Const Payload: String);
Var
  Data: TJSONData;
  Obj: TJSONObject;
  TypeText: String;
Begin
  Data := Nil;
  Try
    Try
      Data := GetJSON(Payload);
      If Not (Data Is TJSONObject) Then
        Exit;
      Obj := TJSONObject(Data);
      TypeText := JsonStringField(Obj, 'type');
      If Not FWireKnown Then
        Begin
          If (Copy(TypeText, 1, 9) = 'response.') Or (Obj.Find('output') <> Nil) Then
            FWire := swkResponses
          Else If Assigned(Obj.Find('choices')) Then
            FWire := swkChatCompletions
          Else If TypeText <> '' Then
            FWire := swkResponses
          Else
            FWire := swkChatCompletions;
          FWireKnown := True;
        End;
      If FWire = swkResponses Then
        ParseResponsesEvent(Obj)
      Else
        ParseChatCompletionsChunk(Obj);
    Except
      On E: Exception Do
        Begin
          FFailed := True;
          FErrorText := 'SSE JSON: ' + E.Message;
        End;
    End;
  Finally
    Data.Free;
  End;
End;

Procedure TAssistantSseParser.ParseResponsesEvent(Obj: TObject);
Var
  Root, Item, UsageParent: TJSONObject;
  EventType, Delta, CallId, Name: String;
  Event: TSamplerEvent;
  OutputIndex: Integer;
Begin
  If Not (Obj Is TJSONObject) Then
    Exit;
  Root := TJSONObject(Obj);
  EventType := JsonStringField(Root, 'type');
  Event := EmptySamplerEvent;
  If EventType = 'response.created' Then
    Begin
      Event.Kind := sekStreamStarted;
      Emit(Event);
      Exit;
    End;
  If (EventType = 'response.failed') Or (EventType = 'response.error') Then
    Begin
      FFailed := True;
      FErrorText := JsonStringField(Root, 'message');
      If FErrorText = '' Then
        Begin
          Item := Root.FindPath('response.error') As TJSONObject;
          If Assigned(Item) Then
            FErrorText := JsonStringField(Item, 'message');
        End;
      If FErrorText = '' Then
        FErrorText := EventType;
      Event.Kind := sekFailed;
      Event.ErrorText := FErrorText;
      Emit(Event);
      Exit;
    End;
  If EventType = 'response.reasoning_summary_text.delta' Then
    Begin
      Delta := JsonStringField(Root, 'delta');
      If Delta = '' Then
        Exit;
      MergeSamplerText(FThinking, Delta);
      Event.Kind := sekThoughtDelta;
      Event.Text := Delta;
      Emit(Event);
      Exit;
    End;
  If EventType = 'response.reasoning_text.delta' Then
    Begin
      Delta := JsonStringField(Root, 'delta');
      If Delta = '' Then
        Exit;
      MergeSamplerText(FThinking, Delta);
      Event.Kind := sekThoughtDelta;
      Event.Text := Delta;
      Emit(Event);
      Exit;
    End;
  If EventType = 'response.output_text.delta' Then
    Begin
      Delta := JsonStringField(Root, 'delta');
      If Delta = '' Then
        Exit;
      MergeSamplerText(FContent, Delta);
      Event.Kind := sekContentDelta;
      Event.Text := Delta;
      Emit(Event);
      Exit;
    End;
  If EventType = 'response.output_item.added' Then
    Begin
      Item := Root.FindPath('item') As TJSONObject;
      If Not Assigned(Item) Then
        Exit;
      If JsonStringField(Item, 'type') <> 'function_call' Then
        Exit;
      OutputIndex := JsonIntField(Root, 'output_index');
      EnsureToolIndex(OutputIndex);
      CallId := JsonStringField(Item, 'call_id');
      If CallId = '' Then
        CallId := JsonStringField(Item, 'id');
      Name := JsonStringField(Item, 'name');
      MergeTool(CallId, Name, JsonStringField(Item, 'arguments'));
      Event.Kind := sekToolCallDelta;
      Event.ToolIndex := OutputIndex;
      Event.ToolId := CallId;
      Event.ToolName := Name;
      Emit(Event);
      Exit;
    End;
  If EventType = 'response.function_call_arguments.delta' Then
    Begin
      Delta := JsonStringField(Root, 'delta');
      If Delta = '' Then
        Exit;
      OutputIndex := JsonIntField(Root, 'output_index');
      EnsureToolIndex(OutputIndex);
      MergeSamplerText(FTools[OutputIndex].Arguments, Delta);
      CallId := JsonStringField(Root, 'item_id');
      If CallId <> '' Then
        FTools[OutputIndex].Id := CallId;
      Event.Kind := sekToolCallDelta;
      Event.ToolIndex := OutputIndex;
      Event.ToolId := FTools[OutputIndex].Id;
      Event.ToolName := FTools[OutputIndex].Name;
      Event.Text := Delta;
      Emit(Event);
      Exit;
    End;
  If EventType = 'response.completed' Then
    Begin
      UsageParent := Root.FindPath('response') As TJSONObject;
      If Not Assigned(UsageParent) Then
        UsageParent := Root;
      HarvestCompletedOutput(UsageParent);
      ApplyUsage(UsageParent);
      CompactEmptyTools;
      Event.Kind := sekCompleted;
      Event.Text := FContent;
      Event.InputTokens := FInputTokens;
      Event.OutputTokens := FOutputTokens;
      Event.ReasoningTokens := FReasoningTokens;
      Emit(Event);
      Exit;
    End;
  If EventType = 'response.incomplete' Then
    Begin
      FIncomplete := True;
      UsageParent := Root.FindPath('response') As TJSONObject;
      If Assigned(UsageParent) Then
        Begin
          HarvestCompletedOutput(UsageParent);
          ApplyUsage(UsageParent);
          Item := UsageParent.FindPath('incomplete_details') As TJSONObject;
          If Assigned(Item) Then
            FErrorText := JsonStringField(Item, 'reason');
        End;
      If FErrorText = '' Then
        FErrorText := 'incomplete';
      Event.Kind := sekCompleted;
      Event.Text := FContent;
      Event.ErrorText := FErrorText;
      Emit(Event);
    End;
End;

Procedure TAssistantSseParser.HarvestCompletedOutput(ResponseObj: TObject);
Var
  Root, Item, Part, UsageObj, Details: TJSONObject;
  Arr, Summary, ContentArr: TJSONArray;
  I, J: Integer;
  ItemType, SummaryText, MessageText: String;
Begin
  If Not (ResponseObj Is TJSONObject) Then
    Exit;
  Root := TJSONObject(ResponseObj);
  Arr := Root.FindPath('output') As TJSONArray;
  If Not Assigned(Arr) Then
    Exit;
  For I := 0 To Arr.Count - 1 Do
    Begin
      If Not (Arr.Items[I] Is TJSONObject) Then
        Continue;
      Item := TJSONObject(Arr.Items[I]);
      ItemType := JsonStringField(Item, 'type');
      If ItemType = 'reasoning' Then
        Begin
          If JsonStringField(Item, 'id') <> '' Then
            FEncryptedId := JsonStringField(Item, 'id');
          If JsonStringField(Item, 'encrypted_content') <> '' Then
            FEncryptedContent := JsonStringField(Item, 'encrypted_content');
          If FThinking = '' Then
            Begin
              Summary := Item.FindPath('summary') As TJSONArray;
              If Assigned(Summary) Then
                For J := 0 To Summary.Count - 1 Do
                  If Summary.Items[J] Is TJSONObject Then
                    Begin
                      SummaryText := JsonStringField(TJSONObject(Summary.Items[J]), 'text');
                      If SummaryText <> '' Then
                        MergeSamplerText(FThinking, SummaryText);
                    End;
            End;
        End
      Else If ItemType = 'function_call' Then
        Begin
          MergeTool(JsonStringField(Item, 'call_id'), JsonStringField(Item, 'name'),
            JsonStringField(Item, 'arguments'));
        End
      Else If ItemType = 'message' Then
        Begin
          If FContent <> '' Then
            Continue;
          ContentArr := Item.FindPath('content') As TJSONArray;
          If Not Assigned(ContentArr) Then
            Continue;
          MessageText := '';
          For J := 0 To ContentArr.Count - 1 Do
            If ContentArr.Items[J] Is TJSONObject Then
              Begin
                Part := TJSONObject(ContentArr.Items[J]);
                If JsonStringField(Part, 'type') = 'output_text' Then
                  MessageText := MessageText + JsonStringField(Part, 'text')
                Else If JsonStringField(Part, 'text') <> '' Then
                  MessageText := MessageText + JsonStringField(Part, 'text');
              End;
          If MessageText <> '' Then
            FContent := MessageText;
        End;
    End;
  UsageObj := Root.FindPath('usage') As TJSONObject;
  If Assigned(UsageObj) Then
    Begin
      FInputTokens := JsonIntField(UsageObj, 'input_tokens');
      FOutputTokens := JsonIntField(UsageObj, 'output_tokens');
      Details := UsageObj.FindPath('output_tokens_details') As TJSONObject;
      If Assigned(Details) Then
        FReasoningTokens := JsonIntField(Details, 'reasoning_tokens');
    End;
End;

Procedure TAssistantSseParser.ApplyUsage(ResponseObj: TObject);
Var
  Root, UsageObj, Details: TJSONObject;
Begin
  If Not (ResponseObj Is TJSONObject) Then
    Exit;
  Root := TJSONObject(ResponseObj);
  UsageObj := Root.FindPath('usage') As TJSONObject;
  If Not Assigned(UsageObj) Then
    Exit;
  FInputTokens := JsonIntField(UsageObj, 'input_tokens');
  FOutputTokens := JsonIntField(UsageObj, 'output_tokens');
  Details := UsageObj.FindPath('output_tokens_details') As TJSONObject;
  If Assigned(Details) Then
    FReasoningTokens := JsonIntField(Details, 'reasoning_tokens');
End;

Procedure TAssistantSseParser.ParseChatCompletionsChunk(Obj: TObject);
Var
  Root, Choice, Delta, MessageObj, Func, ToolItem, UsageObj: TJSONObject;
  Arr, ToolArr: TJSONArray;
  Event: TSamplerEvent;
  ContentDelta, ThinkingDelta, Id, Name, Args: String;
  I, Idx: Integer;
  Finish: String;
Begin
  If Not (Obj Is TJSONObject) Then
    Exit;
  Root := TJSONObject(Obj);
  Arr := Root.FindPath('choices') As TJSONArray;
  If Assigned(Arr) And (Arr.Count > 0) And (Arr.Items[0] Is TJSONObject) Then
    Begin
      Choice := TJSONObject(Arr.Items[0]);
      Delta := Choice.FindPath('delta') As TJSONObject;
      If Assigned(Delta) Then
        Begin
          ContentDelta := JsonStringField(Delta, 'content');
          If ContentDelta = '' Then
            ContentDelta := JsonStringField(Delta, 'text');
          ThinkingDelta := JsonStringField(Delta, 'reasoning_content');
          If ThinkingDelta = '' Then
            ThinkingDelta := JsonStringField(Delta, 'reasoning');
          If ThinkingDelta <> '' Then
            Begin
              MergeSamplerText(FThinking, ThinkingDelta);
              Event := EmptySamplerEvent;
              Event.Kind := sekThoughtDelta;
              Event.Text := ThinkingDelta;
              Emit(Event);
            End;
          If ContentDelta <> '' Then
            Begin
              MergeSamplerText(FContent, ContentDelta);
              Event := EmptySamplerEvent;
              Event.Kind := sekContentDelta;
              Event.Text := ContentDelta;
              Emit(Event);
            End;
          ToolArr := Delta.FindPath('tool_calls') As TJSONArray;
          If Assigned(ToolArr) Then
            For I := 0 To ToolArr.Count - 1 Do
              If ToolArr.Items[I] Is TJSONObject Then
                Begin
                  ToolItem := TJSONObject(ToolArr.Items[I]);
                  Idx := ToolItem.Get('index', I);
                  EnsureToolIndex(Idx);
                  Id := JsonStringField(ToolItem, 'id');
                  If Id <> '' Then
                    FTools[Idx].Id := Id;
                  Func := ToolItem.FindPath('function') As TJSONObject;
                  Name := '';
                  Args := '';
                  If Assigned(Func) Then
                    Begin
                      Name := JsonStringField(Func, 'name');
                      If Name <> '' Then
                        FTools[Idx].Name := Name;
                      Args := JsonStringField(Func, 'arguments');
                      If Args <> '' Then
                        MergeSamplerText(FTools[Idx].Arguments, Args);
                    End;
                  Event := EmptySamplerEvent;
                  Event.Kind := sekToolCallDelta;
                  Event.ToolIndex := Idx;
                  Event.ToolId := FTools[Idx].Id;
                  Event.ToolName := FTools[Idx].Name;
                  Event.Text := Args;
                  Emit(Event);
                End;
        End;
      MessageObj := Choice.FindPath('message') As TJSONObject;
      If Assigned(MessageObj) And (FContent = '') And (FThinking = '') Then
        Begin
          ContentDelta := JsonStringField(MessageObj, 'content');
          ThinkingDelta := JsonStringField(MessageObj, 'reasoning_content');
          If ThinkingDelta = '' Then
            ThinkingDelta := JsonStringField(MessageObj, 'reasoning');
          If ThinkingDelta <> '' Then
            MergeSamplerText(FThinking, ThinkingDelta);
          If ContentDelta <> '' Then
            MergeSamplerText(FContent, ContentDelta);
        End;
      Finish := JsonStringField(Choice, 'finish_reason');
      If Finish <> '' Then
        Begin
          If SameText(Finish, 'content_filter') Then
            Begin
              FFailed := True;
              FErrorText := Finish;
            End
          Else If SameText(Finish, 'length') Then
            Begin
              FIncomplete := True;
              FErrorText := Finish;
            End;
          Event := EmptySamplerEvent;
          If FFailed Then
            Event.Kind := sekFailed
          Else
            Event.Kind := sekCompleted;
          Event.Text := FContent;
          Event.ErrorText := Finish;
          UsageObj := Root.FindPath('usage') As TJSONObject;
          If Assigned(UsageObj) Then
            Begin
              FInputTokens := JsonIntField(UsageObj, 'prompt_tokens');
              If FInputTokens = 0 Then
                FInputTokens := JsonIntField(UsageObj, 'input_tokens');
              FOutputTokens := JsonIntField(UsageObj, 'completion_tokens');
              If FOutputTokens = 0 Then
                FOutputTokens := JsonIntField(UsageObj, 'output_tokens');
              Event.InputTokens := FInputTokens;
              Event.OutputTokens := FOutputTokens;
            End;
          Emit(Event);
        End;
    End;
End;

End.
