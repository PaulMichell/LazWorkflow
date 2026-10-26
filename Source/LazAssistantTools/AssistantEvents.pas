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
    aekSubagentStarted,
    aekSubagentProgress,
    aekSubagentCompleted,
    aekTurnEnded,
    aekError,
    aekRecovery
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
    { Image refs for a tool result's following user message. JSON array, never pixel bytes. }
    AttachmentsJson: String;
  End;

  TAssistantEventArray = Array Of TAssistantEvent;

  TAssistantTraceNotify = Procedure(Const Event: TAssistantEvent) Of Object;

  { Thread-safe queue of steering notes. Drain at actor safe gaps.
    AttachmentsJson is a ref array, never pixel bytes. Image-only notes are pending. }
  TAssistantSteerBuffer = Class
  Private
    FLock: TRTLCriticalSection;
    FItems: TStringList;
    FAttachments: TStringList;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Enqueue(Const Text: String); Overload;
    Procedure Enqueue(Const Text, AttachmentsJson: String); Overload;
    Function HasPending: Boolean;
    { Concatenate and clear in arrival order. Empty string if none. }
    Function DrainConcat: String;
    { Text notes in order, plus one JSON array of every attachment ref. Clears the queue. }
    Function Drain(Out Text, AttachmentsJson: String): Boolean;
  End;

Function AssistantEventKindName(Kind: TAssistantEventKind): String;
Function AssistantPhaseName(Phase: TAssistantPhase): String;
{ True for live status strings the actor puts on the stream callback (not terminal errors). }
Function IsAssistantProgressStatus(Const Text: String): Boolean;
Function FormatSteerEnvelope(Const UserText: String): String;
Function AssistantEventToJson(Const Event: TAssistantEvent): String;
Function AppendAssistantEventLine(Const FileName, JsonLine: String): Boolean;
Function AppendAssistantEvent(Const FileName: String; Const Event: TAssistantEvent): Boolean;
Function ParseOpenAiToolCallsJson(Const Json: String; Out Calls: TSamplerToolCallArray): Boolean;
Function CompletionsToolsToResponsesTools(Const ToolsJson: String): String;
Function AssistantEventKindFromName(Const Name: String): TAssistantEventKind;
Function AssistantPhaseFromName(Const Name: String): TAssistantPhase;
Function ParseAssistantEventJson(Const Json: String; Out Event: TAssistantEvent): Boolean;
Function LoadAssistantEventsFile(Const FileName: String; Out Events: TAssistantEventArray): Boolean;
Function CreateAssistantEventsFilePath(Const ProjectRoot: String): String;
Function AssistantEventsRelativePath(Const AbsFile, ProjectRoot: String): String;
Function AssistantEventsAbsolutePath(Const RelOrAbs, ProjectRoot: String): String;

Implementation

Uses
  fpjson, jsonparser, AssistantRecovery;

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
    aekSubagentStarted: Result := 'subagent_started';
    aekSubagentProgress: Result := 'subagent_progress';
    aekSubagentCompleted: Result := 'subagent_completed';
    aekTurnEnded: Result := 'turn_ended';
    aekError: Result := 'error';
    aekRecovery: Result := 'recovery';
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

Function IsAssistantProgressStatus(Const Text: String): Boolean;
Var
  S: String;
Begin
  S := Trim(Text);
  Result :=
    (S = 'Waiting for first token…') Or
    (S = 'Waiting') Or
    { Earlier builds published the longer phrase. A late snapshot must not become an error. }
    (S = 'Waiting for model…') Or
    (S = 'Running tools…') Or
    (S = 'Steering at next model gap…') Or
    (S = 'Thinking…') Or
    (S = 'Streaming…') Or
    (S = 'Re-establishing Connection') Or
    IsAssistantRecoveryProgress(S);
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
  If Trim(Event.AttachmentsJson) <> '' Then
    Result := Result + ',"attachments":' + Event.AttachmentsJson;
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

Function CombineAttachmentJson(Parts: TStrings): String;
Var
  OutArr: TJSONArray;
  Data, Item: TJSONData;
  I, J: Integer;
Begin
  Result := '';
  If Not Assigned(Parts) Then Exit;
  OutArr := TJSONArray.Create;
  Try
    For I := 0 To Parts.Count - 1 Do
      Begin
        If Trim(Parts[I]) = '' Then Continue;
        Data := Nil;
        Try
          Data := GetJSON(Parts[I]);
        Except
          Data := Nil;
        End;
        If Not Assigned(Data) Then Continue;
        Try
          If Data Is TJSONArray Then
            For J := 0 To TJSONArray(Data).Count - 1 Do
              Begin
                Item := Nil;
                Try
                  Item := GetJSON(TJSONArray(Data).Items[J].AsJSON);
                Except
                  Item := Nil;
                End;
                If Assigned(Item) Then OutArr.Add(Item);
              End;
        Finally
          Data.Free;
        End;
      End;
    If OutArr.Count > 0 Then Result := OutArr.AsJSON;
  Finally
    OutArr.Free;
  End;
End;

Constructor TAssistantSteerBuffer.Create;
Begin
  Inherited Create;
  InitCriticalSection(FLock);
  FItems := TStringList.Create;
  FAttachments := TStringList.Create;
End;

Destructor TAssistantSteerBuffer.Destroy;
Begin
  FreeAndNil(FAttachments);
  FreeAndNil(FItems);
  DoneCriticalSection(FLock);
  Inherited Destroy;
End;

Procedure TAssistantSteerBuffer.Enqueue(Const Text: String);
Begin
  Enqueue(Text, '');
End;

Procedure TAssistantSteerBuffer.Enqueue(Const Text, AttachmentsJson: String);
Var
  Body, RefsJson: String;
Begin
  Body := Trim(Text);
  RefsJson := Trim(AttachmentsJson);
  If (Body = '') And (RefsJson = '') Then Exit;
  EnterCriticalSection(FLock);
  Try
    FItems.Add(Body);
    FAttachments.Add(RefsJson);
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

Function TAssistantSteerBuffer.Drain(Out Text, AttachmentsJson: String): Boolean;
Var
  I: Integer;
  Texts, Parts: TStringList;
Begin
  Text := '';
  AttachmentsJson := '';
  Texts := TStringList.Create;
  Parts := TStringList.Create;
  Try
    EnterCriticalSection(FLock);
    Try
      Result := FItems.Count > 0;
      If Not Result Then Exit;
      Texts.Assign(FItems);
      Parts.Assign(FAttachments);
      FItems.Clear;
      FAttachments.Clear;
    Finally
      LeaveCriticalSection(FLock);
    End;
    For I := 0 To Texts.Count - 1 Do
      Begin
        If Trim(Texts[I]) = '' Then Continue;
        If Text <> '' Then Text := Text + LineEnding + LineEnding;
        Text := Text + Texts[I];
      End;
    AttachmentsJson := CombineAttachmentJson(Parts);
  Finally
    Texts.Free;
    Parts.Free;
  End;
End;

Function TAssistantSteerBuffer.DrainConcat: String;
Var
  Ignored: String;
Begin
  If Not Drain(Result, Ignored) Then Result := '';
End;

Function ParseOpenAiToolCallsJson(Const Json: String; Out Calls: TSamplerToolCallArray): Boolean;
Var
  Data: TJSONData;
  Arr: TJSONArray;
  Item, Func: TJSONObject;
  I: Integer;
Begin
  Result := False;
  Calls := Nil;
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

Function AssistantEventKindFromName(Const Name: String): TAssistantEventKind;
Var
  N: String;
Begin
  N := LowerCase(Trim(Name));
  If N = 'turn_started' Then
    Result := aekTurnStarted
  Else If N = 'phase_changed' Then
    Result := aekPhaseChanged
  Else If N = 'thought_delta' Then
    Result := aekThoughtDelta
  Else If N = 'content_delta' Then
    Result := aekContentDelta
  Else If N = 'loop_started' Then
    Result := aekLoopStarted
  Else If N = 'tool_started' Then
    Result := aekToolStarted
  Else If N = 'tool_completed' Then
    Result := aekToolCompleted
  Else If N = 'steer_queued' Then
    Result := aekSteerQueued
  Else If N = 'interjected' Then
    Result := aekInterjected
  Else If N = 'subagent_started' Then
    Result := aekSubagentStarted
  Else If N = 'subagent_progress' Then
    Result := aekSubagentProgress
  Else If N = 'subagent_completed' Then
    Result := aekSubagentCompleted
  Else If N = 'turn_ended' Then
    Result := aekTurnEnded
  Else If N = 'recovery' Then
    Result := aekRecovery
  Else
    Result := aekError;
End;

Function AssistantPhaseFromName(Const Name: String): TAssistantPhase;
Var
  N: String;
Begin
  N := LowerCase(Trim(Name));
  If N = 'thinking' Then
    Result := apThinking
  Else If N = 'streaming' Then
    Result := apStreaming
  Else If N = 'tools' Then
    Result := apTools
  Else
    Result := apWaiting;
End;

Function ParseAssistantEventJson(Const Json: String; Out Event: TAssistantEvent): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  Event := Default(TAssistantEvent);
  Event.Ok := True;
  If Trim(Json) = '' Then
    Exit;
  Data := Nil;
  Try
    Try
      Data := GetJSON(Json);
      If Not (Data Is TJSONObject) Then
        Exit;
      Obj := TJSONObject(Data);
      Event.Kind := AssistantEventKindFromName(Obj.Get('type', ''));
      Event.Phase := AssistantPhaseFromName(Obj.Get('phase', ''));
      Event.LoopIndex := Obj.Get('loop', 0);
      Event.Ok := Obj.Get('ok', True);
      Event.DurationMs := Obj.Get('duration_ms', 0);
      Event.ToolName := Obj.Get('tool', '');
      Event.ToolId := Obj.Get('tool_id', '');
      Event.Text := Obj.Get('text', '');
      If Assigned(Obj.Find('attachments')) Then
        Event.AttachmentsJson := Obj.Find('attachments').AsJSON;
      Result := Obj.Get('type', '') <> '';
    Except
      Result := False;
    End;
  Finally
    Data.Free;
  End;
End;

Function LoadAssistantEventsFile(Const FileName: String; Out Events: TAssistantEventArray): Boolean;
Var
  SL: TStringList;
  I, N: Integer;
  Event: TAssistantEvent;
Begin
  Result := False;
  Events := Nil;
  If (Trim(FileName) = '') Or (Not FileExists(FileName)) Then
    Exit;
  SL := TStringList.Create;
  Try
    Try
      SL.LoadFromFile(FileName);
    Except
      Exit;
    End;
    N := 0;
    SetLength(Events, SL.Count);
    For I := 0 To SL.Count - 1 Do
      Begin
        If N >= 8000 Then
          Break;
        If Not ParseAssistantEventJson(SL[I], Event) Then
          Continue;
        Events[N] := Event;
        Inc(N);
      End;
    SetLength(Events, N);
    Result := N > 0;
  Finally
    SL.Free;
  End;
End;

Function CreateAssistantEventsFilePath(Const ProjectRoot: String): String;
Begin
  Result := '';
  If Trim(ProjectRoot) = '' Then
    Exit;
  Result := IncludeTrailingPathDelimiter(ProjectRoot) + '.assistant' + PathDelim + 'events' + PathDelim +
    FormatDateTime('yyyymmdd"T"hhnnsszzz', Now) + '.jsonl';
End;

Function AssistantEventsRelativePath(Const AbsFile, ProjectRoot: String): String;
Var
  Root: String;
Begin
  Result := Trim(AbsFile);
  Root := IncludeTrailingPathDelimiter(Trim(ProjectRoot));
  If (Length(Root) <= 1) Or (Result = '') Then
    Exit;
  If CompareText(Copy(Result, 1, Length(Root)), Root) = 0 Then
    Result := Copy(Result, Length(Root) + 1, MaxInt);
  Result := StringReplace(Result, '\', '/', [rfReplaceAll]);
End;

Function AssistantEventsAbsolutePath(Const RelOrAbs, ProjectRoot: String): String;
Var
  Rel: String;
Begin
  Rel := Trim(RelOrAbs);
  Result := Rel;
  If Rel = '' Then
    Exit;
  If (Length(Rel) >= 2) And (Rel[2] = ':') Then
    Exit;
  If (Length(Rel) > 0) And ((Rel[1] = '/') Or (Rel[1] = '\')) Then
    Exit;
  If Trim(ProjectRoot) = '' Then
    Exit;
  Result := IncludeTrailingPathDelimiter(ProjectRoot) + StringReplace(Rel, '/', PathDelim, [rfReplaceAll]);
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
