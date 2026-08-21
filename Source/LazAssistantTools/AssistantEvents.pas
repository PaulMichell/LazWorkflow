Unit AssistantEvents;

{ Typed turn events, JSONL log, and mid-turn steer buffer (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantProtocol;

Type
  TAssistantEventKind = (
    aekTurnStarted,
    aekPhaseChanged,
    aekThoughtDelta,
    aekContentDelta,
    aekLoopStarted,
    aekToolStarted,
    aekToolCompleted,
    aekSteerQueued,
    aekInterjected,
    aekTurnEnded,
    aekError
  );

  TAssistantPhase = (apWaiting, apThinking, apStreaming, apTools);

  TAssistantEvent = Record
    Kind: TAssistantEventKind;
    Phase: TAssistantPhase;
    Text: String;
    ToolName: String;
    ToolId: String;
    Ok: Boolean;
    DurationMs: Integer;
    LoopIndex: Integer;
  End;

  { Thread-safe queue of steering notes. Drain at actor safe gaps. }
  TAssistantSteerBuffer = Class
  Private
    FLock: TRTLCriticalSection;
    FItems: TStringList;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Enqueue(Const Text: String);
    Function HasPending: Boolean;
    { Concatenate and clear in arrival order. Empty string if none. }
    Function DrainConcat: String;
  End;

Function AssistantEventKindName(Kind: TAssistantEventKind): String;
Function AssistantPhaseName(Phase: TAssistantPhase): String;
Function FormatSteerEnvelope(Const UserText: String): String;
Function AssistantEventToJson(Const Event: TAssistantEvent): String;
Function AppendAssistantEventLine(Const FileName, JsonLine: String): Boolean;
Function AppendAssistantEvent(Const FileName: String; Const Event: TAssistantEvent): Boolean;
Function ParseOpenAiToolCallsJson(Const Json: String; Out Calls: TSamplerToolCallArray): Boolean;
Function CompletionsToolsToResponsesTools(Const ToolsJson: String): String;

Implementation

Uses
  fpjson, jsonparser;

Function AssistantEventKindName(Kind: TAssistantEventKind): String;
Begin
  Case Kind Of
    aekTurnStarted: Result := 'turn_started';
    aekPhaseChanged: Result := 'phase_changed';
    aekThoughtDelta: Result := 'thought_delta';
    aekContentDelta: Result := 'content_delta';
    aekLoopStarted: Result := 'loop_started';
    aekToolStarted: Result := 'tool_started';
    aekToolCompleted: Result := 'tool_completed';
    aekSteerQueued: Result := 'steer_queued';
    aekInterjected: Result := 'interjected';
    aekTurnEnded: Result := 'turn_ended';
    aekError: Result := 'error';
  End;
End;

Function AssistantPhaseName(Phase: TAssistantPhase): String;
Begin
  Case Phase Of
    apThinking: Result := 'thinking';
    apStreaming: Result := 'streaming';
    apWaiting: Result := 'waiting';
    apTools: Result := 'tools';
  End;
End;

Function FormatSteerEnvelope(Const UserText: String): String;
Begin
  Result :=
    'The user sent a message while you were working:' + LineEnding +
    '<user_query>' + LineEnding +
    Trim(UserText) + LineEnding +
    '</user_query>' + LineEnding +
    'Incorporate this into the current task. Finish unfinished work unless the user clearly cancelled or replaced it.';
End;

Function AssistantEventToJson(Const Event: TAssistantEvent): String;
Begin
  Result := '{"type":"' + AssistantEventKindName(Event.Kind) + '"' +
    ',"phase":"' + AssistantPhaseName(Event.Phase) + '"' +
    ',"loop":' + IntToStr(Event.LoopIndex) +
    ',"ok":' + LowerCase(BoolToStr(Event.Ok, True)) +
    ',"duration_ms":' + IntToStr(Event.DurationMs);
  If Event.ToolName <> '' Then
    Result := Result + ',"tool":"' + JsonEscapeText(Event.ToolName) + '"';
  If Event.ToolId <> '' Then
    Result := Result + ',"tool_id":"' + JsonEscapeText(Event.ToolId) + '"';
  If Event.Text <> '' Then
    Result := Result + ',"text":"' + JsonEscapeText(Event.Text) + '"';
  Result := Result + '}';
End;

Function AppendAssistantEventLine(Const FileName, JsonLine: String): Boolean;
Var
  Stream: TFileStream;
  Line: RawByteString;
  Mode: Word;
Begin
  Result := False;
  If Trim(FileName) = '' Then
    Exit;
  Try
    ForceDirectories(ExtractFilePath(FileName));
    If FileExists(FileName) Then
      Mode := fmOpenReadWrite Or fmShareDenyNone
    Else
      Mode := fmCreate;
    Stream := TFileStream.Create(FileName, Mode);
    Try
      Stream.Seek(0, soEnd);
      Line := JsonLine + #10;
      If Length(Line) > 0 Then
        Stream.WriteBuffer(Line[1], Length(Line));
      Result := True;
    Finally
      Stream.Free;
    End;
  Except
    Result := False;
  End;
End;

Function AppendAssistantEvent(Const FileName: String; Const Event: TAssistantEvent): Boolean;
Begin
  Result := AppendAssistantEventLine(FileName, AssistantEventToJson(Event));
End;

Constructor TAssistantSteerBuffer.Create;
Begin
  Inherited Create;
  InitCriticalSection(FLock);
  FItems := TStringList.Create;
End;

Destructor TAssistantSteerBuffer.Destroy;
Begin
  FreeAndNil(FItems);
  DoneCriticalSection(FLock);
  Inherited Destroy;
End;

Procedure TAssistantSteerBuffer.Enqueue(Const Text: String);
Var
  Body: String;
Begin
  Body := Trim(Text);
  If Body = '' Then
    Exit;
  EnterCriticalSection(FLock);
  Try
    FItems.Add(Body);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TAssistantSteerBuffer.HasPending: Boolean;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := FItems.Count > 0;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TAssistantSteerBuffer.DrainConcat: String;
Var
  I: Integer;
Begin
  Result := '';
  EnterCriticalSection(FLock);
  Try
    For I := 0 To FItems.Count - 1 Do
      Begin
        If Result <> '' Then
          Result := Result + LineEnding + LineEnding;
        Result := Result + FItems[I];
      End;
    FItems.Clear;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function ParseOpenAiToolCallsJson(Const Json: String; Out Calls: TSamplerToolCallArray): Boolean;
Var
  Data: TJSONData;
  Arr: TJSONArray;
  Item, Func: TJSONObject;
  I: Integer;
Begin
  Result := False;
  SetLength(Calls, 0);
  If Trim(Json) = '' Then
    Exit;
  Data := Nil;
  Try
    Try
      Data := GetJSON(Json);
      If Not (Data Is TJSONArray) Then
        Exit;
      Arr := TJSONArray(Data);
      SetLength(Calls, Arr.Count);
      For I := 0 To Arr.Count - 1 Do
        Begin
          Calls[I].Id := '';
          Calls[I].Name := '';
          Calls[I].Arguments := '';
          If Not (Arr.Items[I] Is TJSONObject) Then
            Continue;
          Item := TJSONObject(Arr.Items[I]);
          Calls[I].Id := Item.Get('id', '');
          Func := Item.FindPath('function') As TJSONObject;
          If Assigned(Func) Then
            Begin
              Calls[I].Name := Func.Get('name', '');
              Calls[I].Arguments := Func.Get('arguments', '');
            End
          Else
            Begin
              Calls[I].Name := Item.Get('name', '');
              Calls[I].Arguments := Item.Get('arguments', '');
            End;
        End;
      Result := Length(Calls) > 0;
    Except
      SetLength(Calls, 0);
      Result := False;
    End;
  Finally
    Data.Free;
  End;
End;

Function CompletionsToolsToResponsesTools(Const ToolsJson: String): String;
Var
  Data: TJSONData;
  Arr, OutArr: TJSONArray;
  Item, Func, Flat: TJSONObject;
  I: Integer;
  Name: String;
Begin
  Result := ToolsJson;
  If Trim(ToolsJson) = '' Then
    Exit;
  Data := Nil;
  OutArr := Nil;
  Try
    Try
      Data := GetJSON(ToolsJson);
      If Not (Data Is TJSONArray) Then
        Exit;
      Arr := TJSONArray(Data);
      OutArr := TJSONArray.Create;
      For I := 0 To Arr.Count - 1 Do
        Begin
          If Not (Arr.Items[I] Is TJSONObject) Then
            Continue;
          Item := TJSONObject(Arr.Items[I]);
          Func := Item.FindPath('function') As TJSONObject;
          If Assigned(Func) Then
            Begin
              Flat := TJSONObject.Create;
              Flat.Add('type', 'function');
              Name := Func.Get('name', '');
              If Name <> '' Then
                Flat.Add('name', Name);
              If Func.Find('description') <> Nil Then
                Flat.Add('description', Func.Get('description', ''));
              If Assigned(Func.Find('parameters')) Then
                Flat.Add('parameters', Func.Find('parameters').Clone);
              OutArr.Add(Flat);
            End
          Else
            OutArr.Add(Item.Clone);
        End;
      Result := OutArr.AsJSON;
    Except
      Result := ToolsJson;
    End;
  Finally
    OutArr.Free;
    Data.Free;
  End;
End;

End.
