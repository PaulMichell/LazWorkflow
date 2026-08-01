Unit AssistantService;

{ Assistant LLM service with OAuth Bearer auth and SSE streaming (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, WorkflowLog, WorkflowEvents, AssistantConfig, AssistantConversation;

Type
  TAssistantMessageRole = (amrSystem, amrUser, amrAssistant, amrTool);

  TAssistantMessage = Record
    Role: TAssistantMessageRole;
    Content: String;
    ToolCallId: String;
    { When set on an assistant message, raw OpenAI tool_calls JSON array. }
    ToolCallsJson: String;
    { Cached JSON-escaped fields so request rebuild is not O(n) re-escape every send. }
    ContentEscaped: String;
    ToolCallIdEscaped: String;
  End;

  TAssistantToolCall = Record
    Id: String;
    Name: String;
    Arguments: String;
  End;
  TAssistantToolCallArray = Array Of TAssistantToolCall;

  { Called on the main thread. ContentSnapshot / ThinkingSnapshot are full text so
    far (not raw deltas). IsFinished ends the stream. Thinking is reasoning_content
    when the model streams it; Content is the final answer channel only. }
  TAssistantStreamEvent = Procedure(Const ContentSnapshot, ThinkingSnapshot: String;
    IsFinished: Boolean; Const ErrorText: String) Of Object;

  TAssistantService = Class
  Private
    FApiBase: String;
    FModel: String;
    FBaseSystemPrompt: String;
    FSystemPrompt: String;
    FActiveSkill: String;
    FMessages: Array Of TAssistantMessage;
    FLastError: String;
    FStreamThread: TThread;
    FBusy: Boolean;
    FActiveMode: TAssistantMode;
    FSystemPromptEscaped: String;
    FToolsJsonCache: String;
    FToolsJsonMode: TAssistantMode;
    FToolsJsonValid: Boolean;
    FToolsEnabled: Boolean;
    FMaxPromptTokens: Integer;
    FLastTrimNotice: String;
    Procedure ClearStreamThread;
    Procedure RebuildSystemPrompt;
    Function EscapedContent(Var Msg: TAssistantMessage): String;
    Function EscapedToolCallId(Var Msg: TAssistantMessage): String;
    Function ToolsJsonCached: String;
    Function MessagePayloadChars(Const Msg: TAssistantMessage): Integer;
    Function EstimatePromptTokens: Integer;
    Procedure InvalidateMessageEscape(Var Msg: TAssistantMessage);
    Procedure TruncateMessageContent(Var Msg: TAssistantMessage; MaxChars: Integer; Const LabelText: String);
    Procedure DropMessageRange(FromIndex, Count: Integer);
    { Shrink/drop old messages so the next request fits the model limit. }
    Procedure TrimMessagesForBudget;
    Function BuildRequestJson: String;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure ApplyConfig(Config: TAssistantConfig);
    Procedure SetEndpoint(Const ApiBase, Model: String);
    Procedure SetActiveSkill(Const SkillName: String);
    Procedure SetActiveMode(Mode: TAssistantMode);
    Procedure ClearHistory;
    Procedure AddMessage(Role: TAssistantMessageRole; Const Content: String);
    Procedure AddAssistantToolCalls(Const Content, ToolCallsJson: String);
    Procedure AddToolResult(Const ToolCallId, Content: String);
    Function MessageCount: Integer;
    Function GetMessage(Index: Integer; Out Role: TAssistantMessageRole; Out Content: String): Boolean;
    Function IsBusy: Boolean;
    Function IsSignedIn: Boolean;
    { Rough prompt size (messages + system + tools) for UI / guards. }
    Function EstimatedPromptTokens: Integer;
    { Starts background SSE stream; OnToken is Synchronized to the main thread. }
    Function StartStream(OnToken: TAssistantStreamEvent): Boolean;
    Procedure CancelStream;
    { Call from the stream callback when IsFinished is True (main thread). }
    Procedure MarkStreamComplete;
    { One-shot non-streaming completion; does not touch chat history or tools.
      Intended for short side tasks (e.g. commit message suggestion). }
    Function CompleteOnce(Const SystemPrompt, UserPrompt: String;
      Out AnswerText, ErrorText: String): Boolean;
    { GET /v1/language-models (fallback /v1/models). Fills ModelIds sorted, chat-oriented. }
    Function ListAvailableModels(ModelIds: TStrings; Out ErrorText: String): Boolean;
    { Rebuilds the next chat/completions body (used after a tool round). }
    Function BuildNextRequestJson: String;
    Property Model: String Read FModel;
    Property ApiBase: String Read FApiBase;
    Property ActiveSkill: String Read FActiveSkill;
    Property ActiveMode: TAssistantMode Read FActiveMode;
    Property SystemPrompt: String Read FSystemPrompt Write FSystemPrompt;
    Property LastError: String Read FLastError;
    { When False, chat/completions is sent without tools (single-shot answer). }
    Property ToolsEnabled: Boolean Read FToolsEnabled Write FToolsEnabled;
    { Soft cap for chat/completions prompt (default leaves headroom under 500k models). }
    Property MaxPromptTokens: Integer Read FMaxPromptTokens Write FMaxPromptTokens;
  End;

Var
  AssistantClient: TAssistantService;

Implementation

Uses
  fphttpclient, opensslsockets, fpjson, jsonparser, GrokOAuth, AssistantSkills, AssistantTools,
  AssistantHttps;

Type
  { One UI snapshot for the main thread; queued under FSnapLock to avoid races. }
  TStreamSnapshot = Record
    Content: String;
    Thinking: String;
    ErrorText: String;
    IsFinished: Boolean;
  End;

  TAssistantStreamThread = Class(TThread)
  Private
    FService: TAssistantService;
    FApiBase: String;
    FAccessToken: String;
    FModel: String;
    FRequestJson: String;
    FOnToken: TAssistantStreamEvent;
    FSnapLock: TRTLCriticalSection;
    FSnapQueue: Array Of TStreamSnapshot;
    FSseBuffer: String;
    FContentAccum: String;
    FThinkingAccum: String;
    FMergeLogCount: Integer;
    FToolCalls: TAssistantToolCallArray;
    FToolRound: Integer;
    FHttpClient: TFPHTTPClient;
    FStreamControl: THttpsStreamControl;
    FFinishEmitted: Boolean;
    FWrotePlanFile: Boolean; { True after a successful write_markdown this stream. }
    Procedure NotifyMain;
    Procedure EmitSnapshots(IsDone: Boolean; Const ErrorText: String);
    Procedure ProcessSseChunk(Const Chunk: String);
    Procedure ProcessSseLine(Const Line: String);
    Procedure ExtractDeltaParts(Const JsonText: String; Out ContentDelta, ThinkingDelta: String);
    Procedure ExtractToolCallDeltas(Const JsonText: String);
    Function MergeStreamText(Var Accum: String; Const Delta: String): Boolean;
    Function HasToolCalls: Boolean;
    Procedure RunToolRoundOnMain;
    Function DoOneHttpRound(Const Url, RequestJson: String; Out ErrorText: String): Boolean;
    Procedure HttpsChunk(Const Chunk: String);
    Function HttpsShouldStop: Boolean;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(Service: TAssistantService; Const ApiBase, AccessToken, Model, RequestJson: String;
      OnToken: TAssistantStreamEvent);
    Destructor Destroy; Override;
    Procedure AbortHttp;
    Procedure Detach;
  End;

  { Feeds TFPHTTPClient response bytes into SSE line parsing as they arrive. }
  TAssistantSSEStream = Class(TStream)
  Private
    FOwner: TAssistantStreamThread;
  Public
    Constructor Create(StreamOwner: TAssistantStreamThread);
    Function Write(Const Buffer; Count: LongInt): LongInt; Override;
    Function Seek(Const Offset: Int64; Origin: TSeekOrigin): Int64; Override;
  End;

Function RoleToJson(Role: TAssistantMessageRole): String;
Begin
  Case Role Of
    amrSystem: Result := 'system';
    amrUser: Result := 'user';
    amrAssistant: Result := 'assistant';
    amrTool: Result := 'tool';
  Else
    Result := 'user';
  End;
End;

Function JsonEscape(Const SourceText: String): String;
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

{ TAssistantSSEStream }

Constructor TAssistantSSEStream.Create(StreamOwner: TAssistantStreamThread);
Begin
  Inherited Create;
  FOwner := StreamOwner;
End;

Function TAssistantSSEStream.Seek(Const Offset: Int64; Origin: TSeekOrigin): Int64;
Begin
  Result := 0;
End;

Function TAssistantSSEStream.Write(Const Buffer; Count: LongInt): LongInt;
Var
  Chunk: String;
Begin
  Result := Count;
  If (Count <= 0) Or (Not Assigned(FOwner)) Or FOwner.Terminated Then
    Exit;
  SetString(Chunk, PChar(@Buffer), Count);
  FOwner.ProcessSseChunk(Chunk);
End;

{ TAssistantStreamThread }

Constructor TAssistantStreamThread.Create(Service: TAssistantService;
  Const ApiBase, AccessToken, Model, RequestJson: String; OnToken: TAssistantStreamEvent);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  InitCriticalSection(FSnapLock);
  SetLength(FSnapQueue, 0);
  FService := Service;
  FApiBase := ApiBase;
  FAccessToken := AccessToken;
  FModel := Model;
  FRequestJson := RequestJson;
  FFinishEmitted := False;
  FWrotePlanFile := False;
  FOnToken := OnToken;
  FSseBuffer := '';
  FContentAccum := '';
  FThinkingAccum := '';
  FMergeLogCount := 0;
  SetLength(FToolCalls, 0);
  FToolRound := 0;
  FHttpClient := Nil;
  FStreamControl := Nil;
End;

Destructor TAssistantStreamThread.Destroy;
Begin
  AbortHttp;
  SetLength(FSnapQueue, 0);
  DoneCriticalSection(FSnapLock);
  Inherited Destroy;
End;

Procedure TAssistantStreamThread.HttpsChunk(Const Chunk: String);
Begin
  If Not Terminated Then
    ProcessSseChunk(Chunk);
End;

Function TAssistantStreamThread.HttpsShouldStop: Boolean;
Begin
  Result := Terminated;
End;

Procedure TAssistantStreamThread.AbortHttp;
Begin
  { Unblock WinINet / TFPHTTPClient so Terminate can finish without hanging the IDE. }
  If Assigned(FStreamControl) Then
    Try
      FStreamControl.Abort;
    Except
    End;
  If Assigned(FHttpClient) Then
    Try
      FHttpClient.Terminate;
    Except
      { ignore }
    End;
End;

Procedure TAssistantStreamThread.Detach;
Begin
  FOnToken := Nil;
  FService := Nil;
  AbortHttp;
End;

Procedure TAssistantStreamThread.NotifyMain;
Var
  Snap: TStreamSnapshot;
  HasItem: Boolean;
  I: Integer;
Begin
  { Drain all queued snapshots so rapid stream ticks do not drop finishes. }
  Repeat
    HasItem := False;
    EnterCriticalSection(FSnapLock);
    Try
      If Length(FSnapQueue) > 0 Then
        Begin
          Snap := FSnapQueue[0];
          For I := 1 To High(FSnapQueue) Do
            FSnapQueue[I - 1] := FSnapQueue[I];
          SetLength(FSnapQueue, Length(FSnapQueue) - 1);
          HasItem := True;
        End;
    Finally
      LeaveCriticalSection(FSnapLock);
    End;
    If Not HasItem Then
      Break;
    If Assigned(FOnToken) Then
      Try
        FOnToken(Snap.Content, Snap.Thinking, Snap.IsFinished, Snap.ErrorText);
      Except
        On E: Exception Do
          WorkflowLogger.Warning('AssistantStream', 'UI snapshot failed: ' + E.Message);
      End;
  Until False;
End;

Procedure TAssistantStreamThread.EmitSnapshots(IsDone: Boolean; Const ErrorText: String);
Var
  N: Integer;
Begin
  If Terminated And (Not IsDone) Then
    Exit;
  { At most one finished callback per stream (guards Break-then-fallthrough and double Exit paths). }
  If IsDone Then
    Begin
      If FFinishEmitted Then
        Exit;
      FFinishEmitted := True;
    End;
  { Queue a *copy* of the snapshot under lock so the worker can keep writing
    accumulators without racing the main thread (was a source of AVs). }
  EnterCriticalSection(FSnapLock);
  Try
    N := Length(FSnapQueue);
    SetLength(FSnapQueue, N + 1);
    FSnapQueue[N].Content := FContentAccum;
    FSnapQueue[N].Thinking := FThinkingAccum;
    FSnapQueue[N].ErrorText := ErrorText;
    FSnapQueue[N].IsFinished := IsDone;
  Finally
    LeaveCriticalSection(FSnapLock);
  End;
  { Queue avoids deadlock: main thread can CancelStream/WaitFor while we notify.
    Tool rounds still use Synchronize so tools run on the main thread. }
  Queue(@NotifyMain);
End;

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
  If Node.JSONType = jtString Then
    Result := Node.AsString
  Else
    Result := Node.AsString;
End;

Function SanitizeStreamText(Const SourceText: String): String;
Var
  I: Integer;
  C: Char;
Begin
  { Drop C0 controls except tab/LF/CR — incomplete UTF-8 / binary noise. }
  Result := '';
  SetLength(Result, Length(SourceText));
  Result := '';
  For I := 1 To Length(SourceText) Do
    Begin
      C := SourceText[I];
      If (C = #9) Or (C = #10) Or (C = #13) Or (Ord(C) >= 32) Then
        Result := Result + C;
    End;
End;

Function CollapseTrailingPhraseRepeats(Const SourceText: String): String;
Var
  PhraseLen, MaxLen, Count, PosEnd: Integer;
  Phrase: String;
Begin
  { Collapse "… phrase phrase phrase" (same unit 3+ times) to a single trailing phrase.
    Guards model/API loops such as repeating "0 of 6 work packages…". }
  Result := SourceText;
  If Length(Result) < 40 Then
    Exit;
  MaxLen := Length(Result) Div 3;
  If MaxLen > 240 Then
    MaxLen := 240;
  PhraseLen := 12;
  While PhraseLen <= MaxLen Do
    Begin
      Phrase := Copy(Result, Length(Result) - PhraseLen + 1, PhraseLen);
      If Trim(Phrase) = '' Then
        Begin
          Inc(PhraseLen);
          Continue;
        End;
      Count := 1;
      PosEnd := Length(Result) - PhraseLen;
      While (PosEnd >= PhraseLen) And
        (Copy(Result, PosEnd - PhraseLen + 1, PhraseLen) = Phrase) Do
        Begin
          Inc(Count);
          Dec(PosEnd, PhraseLen);
        End;
      If Count >= 3 Then
        Begin
          { Keep one copy of the repeated unit. }
          SetLength(Result, Length(Result) - (Count - 1) * PhraseLen);
          Exit;
        End;
      Inc(PhraseLen);
    End;
End;

Function TAssistantStreamThread.MergeStreamText(Var Accum: String; Const Delta: String): Boolean;
Var
  Candidate: String;
Begin
  { OpenAI-style streams usually send token deltas (append). Some providers send
    cumulative snapshots (replace when Delta starts with Accum). Also ignore
    exact re-sends of the last chunk and collapse runaway trailing repeats. }
  Result := False;
  If Delta = '' Then
    Exit;
  If Accum = '' Then
    Begin
      Accum := CollapseTrailingPhraseRepeats(SanitizeStreamText(Delta));
      Result := True;
      Exit;
    End;
  { Exact duplicate of full buffer. }
  If Delta = Accum Then
    Exit;
  { Cumulative snapshot (grows by replacing the whole string). }
  If (Length(Delta) >= Length(Accum)) And (Copy(Delta, 1, Length(Accum)) = Accum) Then
    Begin
      Candidate := CollapseTrailingPhraseRepeats(SanitizeStreamText(Delta));
      If Candidate = Accum Then
        Exit;
      Accum := Candidate;
      Result := True;
      Exit;
    End;
  { Stale shorter prefix of what we already have. }
  If (Length(Delta) < Length(Accum)) And (Copy(Accum, 1, Length(Delta)) = Delta) Then
    Exit;
  { Exact re-send of the last chunk (common when SSE frames are duplicated). }
  If (Length(Accum) >= Length(Delta)) And
    (Copy(Accum, Length(Accum) - Length(Delta) + 1, Length(Delta)) = Delta) Then
    Exit;
  Candidate := CollapseTrailingPhraseRepeats(SanitizeStreamText(Accum + SanitizeStreamText(Delta)));
  If Candidate = Accum Then
    Exit;
  { Hard cap — runaway streams must not grow forever or block Ready. }
  If Length(Candidate) > 400000 Then
    Begin
      If Length(Accum) >= 400000 Then
        Exit;
      Accum := Copy(Candidate, 1, 400000);
      Result := True;
      Exit;
    End;
  Accum := Candidate;
  Result := True;
End;

Procedure TAssistantStreamThread.ExtractDeltaParts(Const JsonText: String;
  Out ContentDelta, ThinkingDelta: String);
Var
  Data: TJSONData;
  Obj, Choice, Delta, MessageObj: TJSONObject;
  Arr: TJSONArray;
Begin
  { OpenAI-compatible stream: delta.content for answer, delta.reasoning_content
    (or delta.reasoning) for thinking summaries on reasoning models. }
  ContentDelta := '';
  ThinkingDelta := '';
  Data := Nil;
  Try
    Try
      Data := GetJSON(JsonText);
      If Not (Data Is TJSONObject) Then
        Exit;
      Obj := TJSONObject(Data);
      Arr := Obj.FindPath('choices') As TJSONArray;
      If (Arr = Nil) Or (Arr.Count < 1) Then
        Exit;
      If Not (Arr.Items[0] Is TJSONObject) Then
        Exit;
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
        End;
      If (ContentDelta = '') And (ThinkingDelta = '') Then
        Begin
          MessageObj := Choice.FindPath('message') As TJSONObject;
          If Assigned(MessageObj) Then
            Begin
              ContentDelta := JsonStringField(MessageObj, 'content');
              ThinkingDelta := JsonStringField(MessageObj, 'reasoning_content');
              If ThinkingDelta = '' Then
                ThinkingDelta := JsonStringField(MessageObj, 'reasoning');
            End;
        End;
    Except
      ContentDelta := '';
      ThinkingDelta := '';
    End;
  Finally
    Data.Free;
  End;
End;

Procedure TAssistantStreamThread.ExtractToolCallDeltas(Const JsonText: String);
Var
  Data: TJSONData;
  Obj, Choice, Delta, Item, Func: TJSONObject;
  Arr, ToolArr: TJSONArray;
  I, Idx: Integer;
  Id, Name, Args: String;
Begin
  Data := Nil;
  Try
    Try
      Data := GetJSON(JsonText);
      If Not (Data Is TJSONObject) Then
        Exit;
      Obj := TJSONObject(Data);
      Arr := Obj.FindPath('choices') As TJSONArray;
      If (Arr = Nil) Or (Arr.Count < 1) Or Not (Arr.Items[0] Is TJSONObject) Then
        Exit;
      Choice := TJSONObject(Arr.Items[0]);
      Delta := Choice.FindPath('delta') As TJSONObject;
      If Not Assigned(Delta) Then
        Exit;
      ToolArr := Delta.FindPath('tool_calls') As TJSONArray;
      If (ToolArr = Nil) Or (ToolArr.Count < 1) Then
        Exit;
      For I := 0 To ToolArr.Count - 1 Do
        Begin
          If Not (ToolArr.Items[I] Is TJSONObject) Then
            Continue;
          Item := TJSONObject(ToolArr.Items[I]);
          Idx := Item.Get('index', I);
          If Idx < 0 Then
            Continue;
          If Idx >= Length(FToolCalls) Then
            SetLength(FToolCalls, Idx + 1);
          Id := JsonStringField(Item, 'id');
          If Id <> '' Then
            FToolCalls[Idx].Id := Id;
          Func := Item.FindPath('function') As TJSONObject;
          If Assigned(Func) Then
            Begin
              Name := JsonStringField(Func, 'name');
              If Name <> '' Then
                FToolCalls[Idx].Name := Name;
              Args := JsonStringField(Func, 'arguments');
              If Args <> '' Then
                FToolCalls[Idx].Arguments := FToolCalls[Idx].Arguments + Args;
            End;
        End;
    Except
      { ignore malformed tool deltas }
    End;
  Finally
    Data.Free;
  End;
End;

Function TAssistantStreamThread.HasToolCalls: Boolean;
Var
  I: Integer;
Begin
  { Require a tool name — partial argument-only stubs must not start a tool round. }
  Result := False;
  For I := 0 To High(FToolCalls) Do
    If Trim(FToolCalls[I].Name) <> '' Then
      Begin
        Result := True;
        Exit;
      End;
End;

Procedure TAssistantStreamThread.RunToolRoundOnMain;
Var
  I: Integer;
  ToolCallsJson, ResultText, ErrorText, Content: String;
  Ok: Boolean;
Begin
  If Not Assigned(FService) Then
    Exit;
  Try
    { Build tool_calls JSON array for the assistant history message. }
    ToolCallsJson := '[';
    For I := 0 To High(FToolCalls) Do
      Begin
        If FToolCalls[I].Name = '' Then
          Continue;
        If Length(ToolCallsJson) > 1 Then
          ToolCallsJson := ToolCallsJson + ',';
        If FToolCalls[I].Id = '' Then
          FToolCalls[I].Id := Format('call_%d_%d', [FToolRound, I]);
        ToolCallsJson := ToolCallsJson + Format(
          '{"id":"%s","type":"function","function":{"name":"%s","arguments":"%s"}}',
          [JsonEscape(FToolCalls[I].Id), JsonEscape(FToolCalls[I].Name),
           JsonEscape(FToolCalls[I].Arguments)]);
      End;
    ToolCallsJson := ToolCallsJson + ']';
    FService.AddAssistantToolCalls(FContentAccum, ToolCallsJson);

    For I := 0 To High(FToolCalls) Do
      Begin
        If FToolCalls[I].Name = '' Then
          Continue;
        ResultText := '';
        ErrorText := '';
        Try
          Ok := ExecuteAssistantToolForMode(FToolCalls[I].Name, FToolCalls[I].Arguments,
            FService.ActiveMode, ResultText, ErrorText);
        Except
          On E: Exception Do
            Begin
              Ok := False;
              ErrorText := 'Tool raised: ' + E.Message;
              ResultText := '';
            End;
        End;
        If Ok Then
          Content := ResultText
        Else
          Content := 'Error: ' + ErrorText;
        FService.AddToolResult(FToolCalls[I].Id, Content);
        WorkflowLogger.Info('AssistantStream',
          Format('tool %s ok=%s len=%d', [FToolCalls[I].Name, BoolToStr(Ok, True), Length(Content)]));
        If Ok And (SameText(FToolCalls[I].Name, 'write_markdown') Or
          SameText(FToolCalls[I].Name, 'update_markdown')) Then
          FWrotePlanFile := True;
      End;
  Except
    On E: Exception Do
      Begin
        WorkflowLogger.Warning('AssistantStream', 'Tool round failed: ' + E.Message);
        { Ensure the model gets a tool error so the conversation can continue. }
        For I := 0 To High(FToolCalls) Do
          If (FToolCalls[I].Name <> '') And (FToolCalls[I].Id <> '') Then
            Try
              FService.AddToolResult(FToolCalls[I].Id, 'Error: tool round failed: ' + E.Message);
            Except
            End;
      End;
  End;
End;

Procedure TAssistantStreamThread.ProcessSseLine(Const Line: String);
Var
  Payload, ContentDelta, ThinkingDelta, Trimmed: String;
  Changed: Boolean;
Begin
  If Terminated Then
    Exit;
  Trimmed := Trim(Line);
  If Trimmed = '' Then
    Exit;
  { Accept "data: ..." and "data:..." }
  If Copy(Trimmed, 1, 5) <> 'data:' Then
    Exit;
  Payload := Trim(Copy(Trimmed, 6, MaxInt));
  If Payload = '' Then
    Exit;
  If Payload = '[DONE]' Then
    Exit;
  ExtractToolCallDeltas(Payload);
  ExtractDeltaParts(Payload, ContentDelta, ThinkingDelta);
  If (ContentDelta = '') And (ThinkingDelta = '') Then
    Exit;
  Changed := False;
  If ThinkingDelta <> '' Then
    If MergeStreamText(FThinkingAccum, ThinkingDelta) Then
      Changed := True;
  If ContentDelta <> '' Then
    If MergeStreamText(FContentAccum, ContentDelta) Then
      Changed := True;
  If Not Changed Then
    Exit;
  Inc(FMergeLogCount);
  If FMergeLogCount <= 12 Then
    WorkflowLogger.Info('AssistantStream',
      Format('merge #%d thinkLen=%d contentLen=%d dThink=%d dContent=%d',
        [FMergeLogCount, Length(FThinkingAccum), Length(FContentAccum),
         Length(ThinkingDelta), Length(ContentDelta)]));
  EmitSnapshots(False, '');
End;

Procedure TAssistantStreamThread.ProcessSseChunk(Const Chunk: String);
Var
  P: Integer;
  Line: String;
Begin
  If Terminated Then
    Exit;
  FSseBuffer := FSseBuffer + Chunk;
  FSseBuffer := StringReplace(FSseBuffer, #13#10, #10, [rfReplaceAll]);
  FSseBuffer := StringReplace(FSseBuffer, #13, #10, [rfReplaceAll]);
  Repeat
    P := Pos(#10, FSseBuffer);
    If P < 1 Then
      Break;
    Line := Copy(FSseBuffer, 1, P - 1);
    Delete(FSseBuffer, 1, P);
    ProcessSseLine(Line);
  Until Terminated;
End;

Function TAssistantStreamThread.DoOneHttpRound(Const Url, RequestJson: String;
  Out ErrorText: String): Boolean;
Var
  Code: Integer;
  ErrBody, Headers: String;
  Control: THttpsStreamControl;
Begin
  Result := False;
  ErrorText := '';
  FSseBuffer := '';
  SetLength(FToolCalls, 0);
  If Terminated Then
    Begin
      ErrorText := 'Cancelled.';
      Exit;
    End;

  Headers := 'Authorization: Bearer ' + FAccessToken;
  Control := THttpsStreamControl.Create;
  FStreamControl := Control;
  Try
    Try
      If Not HttpsPostJsonStream(Url, RequestJson, Headers, @HttpsChunk, @HttpsShouldStop,
        Control, Code, ErrorText) Then
        Begin
          If Terminated And (ErrorText = '') Then
            ErrorText := 'Cancelled.';
          Exit;
        End;
      If Terminated Then
        Begin
          ErrorText := 'Cancelled.';
          Exit;
        End;
      If (Code < 200) Or (Code >= 300) Then
        Begin
          ErrBody := Trim(FSseBuffer);
          If ErrBody = '' Then
            ErrBody := Format('HTTP %d', [Code]);
          If Length(ErrBody) > 400 Then
            ErrBody := Copy(ErrBody, 1, 400) + '…';
          ErrorText := Format('HTTP %d: %s', [Code, ErrBody]);
          Exit;
        End;
      If FSseBuffer <> '' Then
        ProcessSseLine(FSseBuffer);
      Result := True;
    Except
      On E: Exception Do
        If Terminated Then
          ErrorText := 'Cancelled.'
        Else
          Begin
            ErrorText := E.Message;
            If (Pos('OpenSSL', ErrorText) > 0) Or (Pos('initialize', LowerCase(ErrorText)) > 0) Then
              ErrorText := OpenSSLMissingHint + LineEnding + '(' + E.Message + ')';
          End;
    End;
  Finally
    FStreamControl := Nil;
    Control.Free;
  End;
End;

Procedure TAssistantStreamThread.Execute;
Const
  { One HTTP stream that ends with tool_calls counts as a round.
    Code-mode inventory / multi-file reads need more headroom than a short chat answer. }
  MaxToolRounds = 20;
Var
  Url, ErrorText, RequestJson: String;
  RoundNo: Integer;
  WroteBefore: Boolean;
  LastContent, LastThinking: String;
Begin
  Url := Trim(FApiBase);
  While (Length(Url) > 0) And (Url[Length(Url)] = '/') Do
    SetLength(Url, Length(Url) - 1);
  Url := Url + '/chat/completions';

  RequestJson := FRequestJson;
  FWrotePlanFile := False;
  LastContent := '';
  LastThinking := '';
  For RoundNo := 0 To MaxToolRounds Do
    Begin
      If Terminated Then
        Break;
      FContentAccum := '';
      FThinkingAccum := '';
      FMergeLogCount := 0;
      If Not DoOneHttpRound(Url, RequestJson, ErrorText) Then
        Begin
          EmitSnapshots(True, ErrorText);
          Exit;
        End;
      If Terminated Then
        Break;
      If Not HasToolCalls Then
        Begin
          EmitSnapshots(True, '');
          Exit;
        End;
      Inc(FToolRound);
      If FContentAccum <> '' Then
        LastContent := FContentAccum;
      If FThinkingAccum <> '' Then
        LastThinking := FThinkingAccum;
      WorkflowLogger.Info('AssistantStream', Format('tool round %d (%d calls)',
        [FToolRound, Length(FToolCalls)]));
      EmitSnapshots(False, 'Running tools…');
      WroteBefore := FWrotePlanFile;
      Synchronize(@RunToolRoundOnMain);
      If Terminated Or Not Assigned(FService) Then
        Break;
      { Avoid endless write_markdown / plan-tool ping-pong. }
      If FWrotePlanFile And WroteBefore Then
        Begin
          EmitSnapshots(True, '');
          Exit;
        End;
      RequestJson := FService.BuildNextRequestJson;
    End;
  If Terminated Then
    Begin
      If Not FFinishEmitted Then
        EmitSnapshots(True, 'Cancelled.');
    End
  Else
    Begin
      { Restore last visible snapshots if the final tool-only round left them empty. }
      If (FContentAccum = '') And (LastContent <> '') Then
        FContentAccum := LastContent;
      If (FThinkingAccum = '') And (LastThinking <> '') Then
        FThinkingAccum := LastThinking;
      If FWrotePlanFile Or (FContentAccum <> '') Or (FThinkingAccum <> '') Then
        Begin
          { Prefer Ready after partial progress; note the round cap in the thinking footer only. }
          If FContentAccum = '' Then
            FContentAccum :=
              '*(Tool-round limit reached after ' + IntToStr(FToolRound) +
              ' rounds. Partial progress above — send a follow-up to continue, or narrow the package.)*';
          EmitSnapshots(True, '');
        End
      Else
        EmitSnapshots(True, Format(
          'Stopped after %d tool rounds with no answer. Try a more focused request or split the package.',
          [FToolRound]));
    End;
End;

{ TAssistantService }

Function ModeSystemPromptBase(Mode: TAssistantMode): String;
Var
  PlanPath: String;
Begin
  Case Mode Of
    amPlan:
      Begin
        PlanPath := GetActivePlanRelativePath;
        If PlanPath = '' Then
          PlanPath := 'Documents/Plan.md';
        Result :=
          'You are the Project Assistant in **Plan mode** for Free Pascal / Lazarus. ' +
          'Your job is to write durable plan Markdown into project files via tools — NOT only into the chat. ' +
          LineEnding +
          '**Hard rules:**' + LineEnding +
          '1. When the user asks for a plan or implementation plan, you MUST call `write_markdown` ' +
          '(full rewrite) or `update_markdown` (surgical edit) so the plan file on disk is updated. ' +
          '2. Do NOT put the full plan body only in the chat reply. Chat should be a short summary ' +
          '(what changed, which file, next steps). The Markdown file is the source of truth. ' +
          '3. Default / active plan path: **' + PlanPath + '**. Use that path unless the user names another. ' +
          '4. Structure: `##` work packages; first non-empty line under each heading is ' +
          '`Status: not started` | `Status: in progress` | `Status: complete`. ' +
          '5. Prefer `update_markdown` for Status: lines or a single section; `write_markdown` for new files or full plans. ' +
          '6. After writing, you may call `set_active_plan` and `open_markdown` if helpful. ' +
          '7. Never edit source (.pas/.lfm) in Plan mode. ' +
          LineEnding +
          'Tools: read_file, list_directory, open_markdown, get_project_info, write_markdown, ' +
          'update_markdown, list_plans, get_active_plan, set_active_plan.';
      End;
    amCode:
      Result :=
        'You are the Project Assistant in **Code mode** for Free Pascal / Lazarus. ' +
        'You implement changes by calling tools — do not only describe patches.' + LineEnding +
        LineEnding +
        '**Source tools (prefer these):**' + LineEnding +
        '- `search_in_project` — find symbols/strings before bulk reads' + LineEnding +
        '- `read_file` — page large files with start_line/end_line' + LineEnding +
        '- `replace_in_file` — exact surgical edit (small unique old_text)' + LineEnding +
        '- `write_file` — create new files or full rewrites; add Pascal units to the project when needed' + LineEnding +
        '- `replace_in_file` — exact surgical edit' + LineEnding +
        '- `ensure_form_component` — add/update a component in BOTH .pas and .lfm (TTimer, TButton, events). ' +
        'Required for form wiring; do not claim LFM changes without calling this or editing the .lfm.' + LineEnding +
        '- `add_unit_to_project` — register an existing .pas with the .lpi' + LineEnding +
        '- `open_file` — open in the IDE editor' + LineEnding +
        '- `run_compile` — compile/build and return Messages' + LineEnding +
        LineEnding +
        '**Forms / LFM (critical — compile success is not enough):**' + LineEnding +
        '- Declaring a field in .pas does **not** create or wire the component. Events fire only when the ' +
        'matching .lfm has `object Name: TClass` and `OnEvent = MethodName`.' + LineEnding +
        '- Prefer `ensure_form_component` for timers, buttons, actions, etc. It patches .pas **and** .lfm.' + LineEnding +
        '- Example: ensure_form_component path=unit1.pas name=ColorTimer class_name=TTimer ' +
        'properties={"Interval":1000,"Enabled":true,"OnTimer":"ColorTimerTimer"} ' +
        'event_method=ColorTimerTimer uses_unit=ExtCtrls' + LineEnding +
        '- Then `replace_in_file` the handler body (ColorTimerTimer) with real logic.' + LineEnding +
        '- TTimer.Interval is **milliseconds** (1000 = once per second, not 100).' + LineEnding +
        '- Never claim the form works until the .lfm was actually edited in this turn.' + LineEnding +
        LineEnding +
        '**Plan tools:** update_markdown / write_markdown only for plan Status: or short plan notes — ' +
        'not for dumping code deliverables into the plan.' + LineEnding +
        LineEnding +
        '**Workflow:** search → read → edit (.pas and .lfm) → run_compile → fix until clean. ' +
        'A clean `run_compile` (errors=0) after Work-on-this may auto-mark the plan package complete. ' +
        'Stay on the active work package. Prefer Michell Free Pascal conventions.';
  Else
    Result :=
      'You are a helpful Free Pascal / Lazarus expert working inside the IDE (Chat mode). ' +
      'You may call tools read_file, list_directory, open_markdown, and get_project_info when you need project files or to open Markdown. ' +
      'For large files use read_file start_line/end_line to page; if a result says truncated, continue from the suggested start_line instead of re-reading from line 1. ' +
      'Prefer the active editor context already in the user message when it includes the code under discussion. ' +
      'You cannot write files or edit sources in Chat mode — ask the user to switch to Plan or Code for that.';
  End;
End;

Constructor TAssistantService.Create;
Begin
  Inherited Create;
  FApiBase := AssistantConfigDefaultApiBase;
  FModel := AssistantConfigDefaultModel;
  FBaseSystemPrompt := ModeSystemPromptBase(amChat);
  FActiveSkill := '';
  FActiveMode := amChat;
  FSystemPrompt := FBaseSystemPrompt;
  FSystemPromptEscaped := JsonEscape(FSystemPrompt);
  FToolsJsonCache := '';
  FToolsJsonMode := amChat;
  FToolsJsonValid := False;
  FToolsEnabled := True;
  { Grok / xAI chat models often hard-cap near 500k tokens; stay under with margin. }
  FMaxPromptTokens := 420000;
  FLastTrimNotice := '';
  SetLength(FMessages, 0);
  FStreamThread := Nil;
  FBusy := False;
  FLastError := '';
End;

Procedure TAssistantService.SetActiveMode(Mode: TAssistantMode);
Begin
  If FActiveMode <> Mode Then
    Begin
      FToolsJsonValid := False;
      FActiveMode := Mode;
      FBaseSystemPrompt := ModeSystemPromptBase(Mode);
      RebuildSystemPrompt;
      WorkflowLogger.Info('AssistantService', 'Active mode set to ' + AssistantModeToStr(Mode));
    End
  Else
    FActiveMode := Mode;
End;

Procedure TAssistantService.RebuildSystemPrompt;
Begin
  { Rebuild mode base each time so active plan path stays current. }
  FBaseSystemPrompt := ModeSystemPromptBase(FActiveMode);
  FSystemPrompt := BuildSystemPromptWithSkill(FBaseSystemPrompt, FActiveSkill);
  FSystemPromptEscaped := JsonEscape(FSystemPrompt);
End;

Function TAssistantService.EscapedContent(Var Msg: TAssistantMessage): String;
Begin
  If Msg.ContentEscaped = '' Then
    Msg.ContentEscaped := JsonEscape(Msg.Content);
  Result := Msg.ContentEscaped;
End;

Function TAssistantService.EscapedToolCallId(Var Msg: TAssistantMessage): String;
Begin
  If Msg.ToolCallIdEscaped = '' Then
    Msg.ToolCallIdEscaped := JsonEscape(Msg.ToolCallId);
  Result := Msg.ToolCallIdEscaped;
End;

Function TAssistantService.ToolsJsonCached: String;
Begin
  If (Not FToolsJsonValid) Or (FToolsJsonMode <> FActiveMode) Then
    Begin
      FToolsJsonCache := BuildAssistantToolsJsonForMode(FActiveMode);
      FToolsJsonMode := FActiveMode;
      FToolsJsonValid := True;
    End;
  Result := FToolsJsonCache;
End;

Function TAssistantService.BuildRequestJson: String;
Var
  I, PartCount, TotalLen, P, J, L: Integer;
  Parts: Array Of String;
  HasSystem: Boolean;
  MsgJson, Joined: String;
Begin
  { Pre-size and single-copy join — avoids quadratic string growth on long chats.
    Message bodies use cached JSON escapes filled on first use. }
  SetLength(Parts, Length(FMessages) + 2);
  PartCount := 0;
  HasSystem := False;
  If Trim(FSystemPrompt) <> '' Then
    Begin
      If FSystemPromptEscaped = '' Then
        FSystemPromptEscaped := JsonEscape(FSystemPrompt);
      Parts[PartCount] := '{"role":"system","content":"' + FSystemPromptEscaped + '"}';
      Inc(PartCount);
      HasSystem := True;
    End;
  For I := 0 To High(FMessages) Do
    Begin
      If (FMessages[I].Role = amrSystem) And HasSystem Then
        Continue;
      If FMessages[I].Role = amrTool Then
        MsgJson := '{"role":"tool","tool_call_id":"' + EscapedToolCallId(FMessages[I]) +
          '","content":"' + EscapedContent(FMessages[I]) + '"}'
      Else If FMessages[I].ToolCallsJson <> '' Then
        MsgJson := '{"role":"assistant","content":"' + EscapedContent(FMessages[I]) +
          '","tool_calls":' + FMessages[I].ToolCallsJson + '}'
      Else
        MsgJson := '{"role":"' + RoleToJson(FMessages[I].Role) + '","content":"' +
          EscapedContent(FMessages[I]) + '"}';
      Parts[PartCount] := MsgJson;
      Inc(PartCount);
    End;
  TotalLen := 0;
  For J := 0 To PartCount - 1 Do
    Begin
      Inc(TotalLen, Length(Parts[J]));
      If J > 0 Then
        Inc(TotalLen);
    End;
  SetLength(Joined, TotalLen);
  P := 1;
  For J := 0 To PartCount - 1 Do
    Begin
      If J > 0 Then
        Begin
          Joined[P] := ',';
          Inc(P);
        End;
      L := Length(Parts[J]);
      If L > 0 Then
        Move(Parts[J][1], Joined[P], L);
      Inc(P, L);
    End;
  If FToolsEnabled And (Trim(ToolsJsonCached) <> '') Then
    Result := '{"model":"' + JsonEscape(FModel) + '","stream":true,"messages":[' + Joined +
      '],"tools":' + ToolsJsonCached + '}'
  Else
    Result := '{"model":"' + JsonEscape(FModel) + '","stream":true,"messages":[' + Joined + ']}';
End;

Destructor TAssistantService.Destroy;
Begin
  CancelStream;
  SetLength(FMessages, 0);
  Inherited Destroy;
End;

Procedure TAssistantService.ClearStreamThread;
Var
  StartTick: QWord;
  Stream: TAssistantStreamThread;
Begin
  If Not Assigned(FStreamThread) Then
    Begin
      FBusy := False;
      Exit;
    End;
  Stream := TAssistantStreamThread(FStreamThread);
  Stream.Terminate;
  Stream.AbortHttp;
  { Pump Synchronize/Queue so a blocked EmitSnapshots can finish; never
    WaitFor alone on the main thread (classic deadlock with Synchronize). }
  StartTick := GetTickCount64;
  While (Not Stream.Finished) And (GetTickCount64 - StartTick < 8000) Do
    Begin
      CheckSynchronize(20);
      Sleep(5);
    End;
  If Not Stream.Finished Then
    WorkflowLogger.Warning('AssistantService', 'Stream thread did not finish within timeout; detaching');
  Try
    If Stream.Finished Then
      Begin
        Stream.WaitFor;
        FreeAndNil(FStreamThread);
      End
    Else
      Begin
        { Last resort: abandon the reference; thread free-on-terminate is false so
          it may leak if stuck in kernel I/O, but the IDE stays responsive. }
        Stream.Detach;
        FStreamThread := Nil;
      End;
  Except
    On E: Exception Do
      Begin
        WorkflowLogger.Warning('AssistantService', 'ClearStreamThread: ' + E.Message);
        FStreamThread := Nil;
      End;
  End;
  FBusy := False;
End;

Procedure TAssistantService.ApplyConfig(Config: TAssistantConfig);
Begin
  If Not Assigned(Config) Then
    Exit;
  SetEndpoint(Config.ApiBase, Config.Model);
  SetActiveSkill(Config.ActiveSkill);
  If Assigned(GrokOAuthClient) Then
    GrokOAuthClient.SetTokens(Config.ToOAuthTokens);
End;

Procedure TAssistantService.SetEndpoint(Const ApiBase, Model: String);
Begin
  If ApiBase <> '' Then
    FApiBase := ApiBase;
  If Model <> '' Then
    FModel := Model;
  WorkflowLogger.Info('AssistantService', 'Endpoint updated – model=' + FModel);
End;

Procedure TAssistantService.SetActiveSkill(Const SkillName: String);
Var
  NewName: String;
Begin
  NewName := Trim(SkillName);
  If SameText(FActiveSkill, NewName) And (FSystemPrompt <> '') Then
    Begin
      { Rebuild only if skill file may have changed (cache checks mtime). }
      RebuildSystemPrompt;
      Exit;
    End;
  FActiveSkill := NewName;
  RebuildSystemPrompt;
  If FActiveSkill <> '' Then
    WorkflowLogger.Info('AssistantService', 'Active skill set to ' + FActiveSkill)
  Else
    WorkflowLogger.Info('AssistantService', 'Active skill cleared');
End;

Procedure TAssistantService.ClearHistory;
Begin
  SetLength(FMessages, 0);
  FLastTrimNotice := '';
End;

Procedure TAssistantService.InvalidateMessageEscape(Var Msg: TAssistantMessage);
Begin
  Msg.ContentEscaped := '';
  Msg.ToolCallIdEscaped := '';
End;

Procedure TAssistantService.TruncateMessageContent(Var Msg: TAssistantMessage; MaxChars: Integer;
  Const LabelText: String);
Var
  KeepHead, KeepTail: Integer;
  Body: String;
Begin
  If MaxChars < 64 Then
    MaxChars := 64;
  If Length(Msg.Content) <= MaxChars Then
    Exit;
  KeepHead := (MaxChars * 2) Div 3;
  KeepTail := MaxChars - KeepHead - 80;
  If KeepTail < 40 Then
    KeepTail := 40;
  Body := Copy(Msg.Content, 1, KeepHead) + LineEnding +
    Format('[… %s truncated from %d chars for context budget …]',
      [LabelText, Length(Msg.Content)]) + LineEnding +
    Copy(Msg.Content, Length(Msg.Content) - KeepTail + 1, KeepTail);
  Msg.Content := Body;
  InvalidateMessageEscape(Msg);
End;

Function TAssistantService.MessagePayloadChars(Const Msg: TAssistantMessage): Integer;
Begin
  Result := Length(Msg.Content) + Length(Msg.ToolCallsJson) + Length(Msg.ToolCallId);
End;

Function TAssistantService.EstimatePromptTokens: Integer;
Var
  I, Chars: Integer;
Begin
  Chars := Length(FSystemPrompt) + Length(ToolsJsonCached) + 256;
  For I := 0 To High(FMessages) Do
    Inc(Chars, MessagePayloadChars(FMessages[I]));
  { ~4 characters per token is a common rough estimate for mixed code/text. }
  Result := (Chars + 3) Div 4;
  If Result < 1 Then
    Result := 1;
End;

Function TAssistantService.EstimatedPromptTokens: Integer;
Begin
  Result := EstimatePromptTokens;
End;

Procedure TAssistantService.DropMessageRange(FromIndex, Count: Integer);
Var
  I, N: Integer;
Begin
  N := Length(FMessages);
  If (Count < 1) Or (FromIndex < 0) Or (FromIndex >= N) Then
    Exit;
  If FromIndex + Count > N Then
    Count := N - FromIndex;
  For I := FromIndex To N - Count - 1 Do
    FMessages[I] := FMessages[I + Count];
  SetLength(FMessages, N - Count);
End;

Procedure TAssistantService.TrimMessagesForBudget;
Const
  MinMessagesToKeep = 6;
  RecentProtectCount = 14;
  OldToolMaxChars = 2500;
  OldUserMaxChars = 12000;
  RecentToolMaxChars = 48000;
Var
  Budget, Est, I, DropCount, ProtectFrom, UserTurns, StartDrop: Integer;
  Notice: String;
  Changed: Boolean;
Begin
  If FMaxPromptTokens < 50000 Then
    FMaxPromptTokens := 50000;
  Budget := FMaxPromptTokens;
  Changed := False;
  Est := EstimatePromptTokens;
  If Est <= Budget Then
    Exit;

  { Phase 1: aggressively shrink older tool results and huge user/assistant blobs. }
  ProtectFrom := Length(FMessages) - RecentProtectCount;
  If ProtectFrom < 0 Then
    ProtectFrom := 0;
  For I := 0 To High(FMessages) Do
    Begin
      If I >= ProtectFrom Then
        Begin
          If (FMessages[I].Role = amrTool) And (Length(FMessages[I].Content) > RecentToolMaxChars) Then
            Begin
              TruncateMessageContent(FMessages[I], RecentToolMaxChars, 'tool result');
              Changed := True;
            End;
          Continue;
        End;
      If FMessages[I].Role = amrTool Then
        Begin
          If Length(FMessages[I].Content) > OldToolMaxChars Then
            Begin
              TruncateMessageContent(FMessages[I], OldToolMaxChars, 'older tool result');
              Changed := True;
            End;
        End
      Else If Length(FMessages[I].Content) > OldUserMaxChars Then
        Begin
          TruncateMessageContent(FMessages[I], OldUserMaxChars, 'older message');
          Changed := True;
        End;
      { ToolCallsJson arguments can also be large (write_file content).
        Strip tool_calls entirely and drop following tool results so ids stay valid. }
      If Length(FMessages[I].ToolCallsJson) > 12000 Then
        Begin
          FMessages[I].ToolCallsJson := '';
          If Trim(FMessages[I].Content) = '' Then
            FMessages[I].Content :=
              '[Earlier assistant tool_calls were removed to fit the context window.]';
          InvalidateMessageEscape(FMessages[I]);
          While (I + 1 <= High(FMessages)) And (FMessages[I + 1].Role = amrTool) Do
            DropMessageRange(I + 1, 1);
          Changed := True;
        End;
    End;

  Est := EstimatePromptTokens;
  { Phase 2: drop oldest complete turns (from the start through a user boundary). }
  While (Est > Budget) And (Length(FMessages) > MinMessagesToKeep) Do
    Begin
      { Prefer dropping from the start up to (not including) a later user message
        so we keep recent user→assistant→tool chains intact. }
      StartDrop := 0;
      DropCount := 1;
      UserTurns := 0;
      For I := High(FMessages) DownTo 0 Do
        If FMessages[I].Role = amrUser Then
          Begin
            Inc(UserTurns);
            If UserTurns >= 3 Then
              Begin
                { Keep from this user message onward; drop [0 .. I-1]. }
                DropCount := I;
                Break;
              End;
          End;
      If DropCount < 1 Then
        DropCount := 1;
      If DropCount >= Length(FMessages) - MinMessagesToKeep + 1 Then
        DropCount := Length(FMessages) - MinMessagesToKeep;
      If DropCount < 1 Then
        Break;
      DropMessageRange(StartDrop, DropCount);
      Changed := True;
      Est := EstimatePromptTokens;
      { After one large drop, re-loop; if still over, drop more from start one-by-one. }
      If (Est > Budget) And (Length(FMessages) > MinMessagesToKeep) Then
        Begin
          { Drop a leading assistant/tool orphan or single message. }
          DropCount := 1;
          If (Length(FMessages) > 1) And (FMessages[0].Role = amrAssistant) And
            (FMessages[0].ToolCallsJson <> '') Then
            Begin
              DropCount := 1;
              While (DropCount < Length(FMessages)) And (FMessages[DropCount].Role = amrTool) Do
                Inc(DropCount);
            End;
          If DropCount > Length(FMessages) - MinMessagesToKeep Then
            DropCount := Length(FMessages) - MinMessagesToKeep;
          If DropCount > 0 Then
            Begin
              DropMessageRange(0, DropCount);
              Est := EstimatePromptTokens;
            End
          Else
            Break;
        End;
    End;

  { Phase 3: last-resort truncate remaining tool results. }
  If Est > Budget Then
    For I := 0 To High(FMessages) Do
      If (FMessages[I].Role = amrTool) And (Length(FMessages[I].Content) > 1200) Then
        Begin
          TruncateMessageContent(FMessages[I], 1200, 'tool result');
          Changed := True;
        End;

  Est := EstimatePromptTokens;
  If Changed Then
    Begin
      Notice := Format(
        '[Context trimmed to fit the model limit: ~%d estimated tokens remain (budget %d). ' +
        'Older tool results and turns may be shortened or dropped. Re-read files if needed.]',
        [Est, Budget]);
      FLastTrimNotice := Notice;
      If (Length(FMessages) = 0) Or (Pos('[Context trimmed', FMessages[0].Content) < 1) Then
        Begin
          SetLength(FMessages, Length(FMessages) + 1);
          For I := High(FMessages) DownTo 1 Do
            FMessages[I] := FMessages[I - 1];
          FMessages[0].Role := amrUser;
          FMessages[0].Content := Notice;
          FMessages[0].ToolCallId := '';
          FMessages[0].ToolCallsJson := '';
          InvalidateMessageEscape(FMessages[0]);
        End
      Else
        Begin
          FMessages[0].Content := Notice;
          InvalidateMessageEscape(FMessages[0]);
        End;
      WorkflowLogger.Info('AssistantService',
        Format('Trimmed chat context to ~%d tokens (budget %d, messages=%d)',
          [EstimatePromptTokens, Budget, Length(FMessages)]));
    End;
End;

Procedure TAssistantService.AddMessage(Role: TAssistantMessageRole; Const Content: String);
Var
  Idx: Integer;
  Body: String;
Begin
  Body := Content;
  { Cap very large user payloads (e.g. repeated IDE dumps). }
  If (Role = amrUser) And (Length(Body) > 100000) Then
    Body := Copy(Body, 1, 90000) + LineEnding +
      Format('[… user message truncated from %d chars …]', [Length(Content)]);
  Idx := Length(FMessages);
  SetLength(FMessages, Idx + 1);
  FMessages[Idx].Role := Role;
  FMessages[Idx].Content := Body;
  FMessages[Idx].ToolCallId := '';
  FMessages[Idx].ToolCallsJson := '';
  FMessages[Idx].ContentEscaped := '';
  FMessages[Idx].ToolCallIdEscaped := '';
End;

Procedure TAssistantService.AddAssistantToolCalls(Const Content, ToolCallsJson: String);
Var
  Idx: Integer;
  Calls: String;
Begin
  Calls := ToolCallsJson;
  { write_file / full rewrites in tool arguments can dominate the prompt. }
  If Length(Calls) > 100000 Then
    Calls :=
      '[{"id":"trimmed_args","type":"function","function":{"name":"large_tool_call","arguments":"{}"}}]';
  Idx := Length(FMessages);
  SetLength(FMessages, Idx + 1);
  FMessages[Idx].Role := amrAssistant;
  FMessages[Idx].Content := Content;
  If (FMessages[Idx].Content = '') And (Calls <> ToolCallsJson) Then
    FMessages[Idx].Content :=
      '[Assistant tool_calls arguments were truncated for context size.]';
  FMessages[Idx].ToolCallId := '';
  FMessages[Idx].ToolCallsJson := Calls;
  FMessages[Idx].ContentEscaped := '';
  FMessages[Idx].ToolCallIdEscaped := '';
End;

Procedure TAssistantService.AddToolResult(Const ToolCallId, Content: String);
Const
  MaxToolChars = 40000;
Var
  Idx: Integer;
  Body: String;
Begin
  Body := Content;
  If Length(Body) > MaxToolChars Then
    Body := Copy(Body, 1, MaxToolChars - 120) + LineEnding +
      Format('[… tool result truncated from %d chars at store time; re-read with start_line if needed …]',
        [Length(Content)]);
  Idx := Length(FMessages);
  SetLength(FMessages, Idx + 1);
  FMessages[Idx].Role := amrTool;
  FMessages[Idx].Content := Body;
  FMessages[Idx].ToolCallId := ToolCallId;
  FMessages[Idx].ToolCallsJson := '';
  FMessages[Idx].ContentEscaped := '';
  FMessages[Idx].ToolCallIdEscaped := '';
End;

Function TAssistantService.BuildNextRequestJson: String;
Begin
  TrimMessagesForBudget;
  Result := BuildRequestJson;
End;

Function TAssistantService.MessageCount: Integer;
Begin
  Result := Length(FMessages);
End;

Function TAssistantService.GetMessage(Index: Integer; Out Role: TAssistantMessageRole; Out Content: String): Boolean;
Begin
  Result := False;
  Role := amrUser;
  Content := '';
  If (Index < 0) Or (Index >= Length(FMessages)) Then
    Exit;
  Role := FMessages[Index].Role;
  Content := FMessages[Index].Content;
  Result := True;
End;

Function TAssistantService.IsBusy: Boolean;
Begin
  Result := FBusy;
End;

Function TAssistantService.IsSignedIn: Boolean;
Begin
  Result := Assigned(GrokOAuthClient) And GrokOAuthClient.IsAuthenticated;
End;

Function LooksLikeChatModelId(Const ModelId: String): Boolean;
Var
  LowerId: String;
Begin
  LowerId := LowerCase(Trim(ModelId));
  Result := LowerId <> '';
  If Not Result Then
    Exit;
  { Drop generation / media endpoints from the chat picker. }
  If (Pos('imagine', LowerId) > 0) Or (Pos('video', LowerId) > 0) Or
    (Pos('voice', LowerId) > 0) Or (Pos('tts', LowerId) > 0) Or
    (Pos('embedding', LowerId) > 0) Or (Pos('whisper', LowerId) > 0) Or
    (Pos('image-gen', LowerId) > 0) Then
    Result := False;
End;

Function TAssistantService.ListAvailableModels(ModelIds: TStrings; Out ErrorText: String): Boolean;
Var
  AccessToken, BaseUrl, Body, AuthHdr, HttpErr: String;
  StatusCode: Integer;
  Data, Item: TJSONData;
  Root, Obj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  ModelId: String;
  Paths: Array[0..1] Of String;
  PathIdx: Integer;
Begin
  Result := False;
  ErrorText := '';
  If Not Assigned(ModelIds) Then
    Begin
      ErrorText := 'Model list is nil.';
      Exit;
    End;
  ModelIds.Clear;
  If Not Assigned(GrokOAuthClient) Then
    Begin
      ErrorText := 'OAuth client is not available.';
      Exit;
    End;
  AccessToken := GrokOAuthClient.GetValidAccessToken;
  If AccessToken = '' Then
    Begin
      ErrorText := GrokOAuthClient.LastError;
      If ErrorText = '' Then
        ErrorText := 'Not signed in.';
      Exit;
    End;
  If Assigned(AssistantChatConfig) Then
    Begin
      AssistantChatConfig.ApplyOAuthTokens(GrokOAuthClient.Tokens);
      AssistantChatConfig.Save;
    End;

  BaseUrl := Trim(FApiBase);
  While (Length(BaseUrl) > 0) And (BaseUrl[Length(BaseUrl)] = '/') Do
    SetLength(BaseUrl, Length(BaseUrl) - 1);
  Paths[0] := '/language-models';
  Paths[1] := '/models';
  AuthHdr := 'Authorization: Bearer ' + AccessToken;

  For PathIdx := 0 To High(Paths) Do
    Begin
      Body := '';
      Data := Nil;
      Try
        Try
          If Not HttpsGet(BaseUrl + Paths[PathIdx], Body, StatusCode, HttpErr, AuthHdr) Then
            Begin
              ErrorText := HttpErr;
              Continue;
            End;
          If (StatusCode < 200) Or (StatusCode >= 300) Then
            Begin
              ErrorText := Format('HTTP %d listing models via %s', [StatusCode, Paths[PathIdx]]);
              Continue;
            End;
          Data := GetJSON(Body);
          If Not (Data Is TJSONObject) Then
            Continue;
          Root := TJSONObject(Data);
          Arr := Root.FindPath('models') As TJSONArray;
          If Arr = Nil Then
            Arr := Root.FindPath('data') As TJSONArray;
          If (Arr = Nil) Or (Arr.Count < 1) Then
            Continue;
          For I := 0 To Arr.Count - 1 Do
            Begin
              Item := Arr.Items[I];
              ModelId := '';
              If Item Is TJSONObject Then
                Begin
                  Obj := TJSONObject(Item);
                  ModelId := JsonStringField(Obj, 'id');
                  { Skip pure image-generation entries when /models is used. }
                  If (Obj.Find('image_price') <> Nil) And
                    (Obj.Find('completion_text_token_price') = Nil) And
                    (Obj.Find('prompt_text_token_price') = Nil) Then
                    Continue;
                End
              Else If Item.JSONType = jtString Then
                ModelId := Item.AsString;
              If LooksLikeChatModelId(ModelId) And (ModelIds.IndexOf(ModelId) < 0) Then
                ModelIds.Add(ModelId);
            End;
          If ModelIds.Count > 0 Then
            Begin
              If ModelIds Is TStringList Then
                TStringList(ModelIds).Sort;
              Result := True;
              WorkflowLogger.Info('AssistantService',
                Format('Listed %d models via %s', [ModelIds.Count, Paths[PathIdx]]));
              Exit;
            End;
        Except
          On E: Exception Do
            ErrorText := E.Message;
        End;
      Finally
        Data.Free;
      End;
    End;
  If ErrorText = '' Then
    ErrorText := 'No chat models returned by the API.';
End;

Function TAssistantService.StartStream(OnToken: TAssistantStreamEvent): Boolean;
Var
  RequestJson, AccessToken: String;
Begin
  Result := False;
  FLastError := '';
  If FBusy Then
    Begin
      FLastError := 'A request is already in progress.';
      Exit;
    End;
  If Not Assigned(GrokOAuthClient) Then
    Begin
      FLastError := 'OAuth client is not available.';
      Exit;
    End;
  AccessToken := GrokOAuthClient.GetValidAccessToken;
  If AccessToken = '' Then
    Begin
      FLastError := GrokOAuthClient.LastError;
      If FLastError = '' Then
        FLastError := 'Not signed in. Open Assistant Settings and sign in with SuperGrok / X Premium.';
      Exit;
    End;
  { Keep tokens in memory for this session; persist on Settings save / form close paths
    rather than blocking every prompt with a config write. }
  If Assigned(AssistantChatConfig) Then
    AssistantChatConfig.ApplyOAuthTokens(GrokOAuthClient.Tokens);
  If Not Assigned(OnToken) Then
    Begin
      FLastError := 'No stream callback.';
      Exit;
    End;

  ClearStreamThread;
  { Refresh mode/plan-path wording and tool list before every request. }
  RebuildSystemPrompt;
  FToolsJsonValid := False;
  TrimMessagesForBudget;
  RequestJson := BuildRequestJson;
  FStreamThread := TAssistantStreamThread.Create(Self, FApiBase, AccessToken, FModel, RequestJson, OnToken);
  FBusy := True;
  FStreamThread.Start;
  Result := True;
  WorkflowLogger.Info('AssistantService', 'Stream started – model=' + FModel);
End;

Procedure TAssistantService.CancelStream;
Begin
  If Assigned(FStreamThread) Then
    Begin
      WorkflowLogger.Info('AssistantService', 'Stream cancel requested');
      ClearStreamThread;
    End
  Else
    FBusy := False;
End;

Function TAssistantService.CompleteOnce(Const SystemPrompt, UserPrompt: String;
  Out AnswerText, ErrorText: String): Boolean;
Var
  AccessToken, Url, Body, ResponseBody, Headers: String;
  StatusCode: Integer;
  Data: TJSONData;
  Arr: TJSONArray;
  Choice, MessageObj: TJSONObject;
Begin
  Result := False;
  AnswerText := '';
  ErrorText := '';
  FLastError := '';
  If FBusy Then
    Begin
      ErrorText := 'A request is already in progress.';
      FLastError := ErrorText;
      Exit;
    End;
  If Not Assigned(GrokOAuthClient) Then
    Begin
      ErrorText := 'OAuth client is not available.';
      FLastError := ErrorText;
      Exit;
    End;
  AccessToken := GrokOAuthClient.GetValidAccessToken;
  If AccessToken = '' Then
    Begin
      ErrorText := GrokOAuthClient.LastError;
      If ErrorText = '' Then
        ErrorText := 'Not signed in. Open Project Assistant Settings and sign in.';
      FLastError := ErrorText;
      Exit;
    End;
  If Assigned(AssistantChatConfig) Then
    AssistantChatConfig.ApplyOAuthTokens(GrokOAuthClient.Tokens);
  If FModel = '' Then
    Begin
      ErrorText := 'No model configured.';
      FLastError := ErrorText;
      Exit;
    End;
  Url := Trim(FApiBase);
  While (Length(Url) > 0) And (Url[Length(Url)] = '/') Do
    SetLength(Url, Length(Url) - 1);
  Url := Url + '/chat/completions';
  Body :=
    '{"model":"' + JsonEscape(FModel) + '","stream":false,"messages":[' +
    '{"role":"system","content":"' + JsonEscape(SystemPrompt) + '"},' +
    '{"role":"user","content":"' + JsonEscape(UserPrompt) + '"}' +
    ']}';
  Headers := 'Authorization: Bearer ' + AccessToken;
  FBusy := True;
  Try
    If Not HttpsPostJson(Url, Body, Headers, ResponseBody, StatusCode, ErrorText) Then
      Begin
        If ErrorText = '' Then
          ErrorText := 'HTTPS request failed.';
        FLastError := ErrorText;
        Exit;
      End;
    If (StatusCode < 200) Or (StatusCode >= 300) Then
      Begin
        ErrorText := Format('HTTP %d: %s', [StatusCode, Copy(ResponseBody, 1, 400)]);
        FLastError := ErrorText;
        Exit;
      End;
    Data := Nil;
    Try
      Try
        Data := GetJSON(ResponseBody);
        If Not (Data Is TJSONObject) Then
          Begin
            ErrorText := 'Unexpected completion response.';
            FLastError := ErrorText;
            Exit;
          End;
        Arr := TJSONObject(Data).FindPath('choices') As TJSONArray;
        If (Arr = Nil) Or (Arr.Count < 1) Or Not (Arr.Items[0] Is TJSONObject) Then
          Begin
            ErrorText := 'No choices in completion response.';
            FLastError := ErrorText;
            Exit;
          End;
        Choice := TJSONObject(Arr.Items[0]);
        MessageObj := Choice.FindPath('message') As TJSONObject;
        If Assigned(MessageObj) Then
          AnswerText := JsonStringField(MessageObj, 'content')
        Else
          AnswerText := '';
        AnswerText := Trim(AnswerText);
        If AnswerText = '' Then
          Begin
            ErrorText := 'Empty completion content.';
            FLastError := ErrorText;
            Exit;
          End;
        Result := True;
      Except
        On E: Exception Do
          Begin
            ErrorText := 'Parse error: ' + E.Message;
            FLastError := ErrorText;
          End;
      End;
    Finally
      Data.Free;
    End;
  Finally
    FBusy := False;
  End;
End;

Procedure TAssistantService.MarkStreamComplete;
Begin
  FBusy := False;
End;

Initialization

AssistantClient := TAssistantService.Create;
If Assigned(AssistantChatConfig) Then
  AssistantClient.ApplyConfig(AssistantChatConfig);

Finalization

FreeAndNil(AssistantClient);

End.
