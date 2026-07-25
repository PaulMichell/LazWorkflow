Unit AssistantService;

{ Assistant LLM service with OAuth Bearer auth and SSE streaming (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, WorkflowLog, WorkflowEvents, AssistantConfig;

Type
  TAssistantMessageRole = (amrSystem, amrUser, amrAssistant, amrTool);

  TAssistantMessage = Record
    Role: TAssistantMessageRole;
    Content: String;
    ToolCallId: String;
    { When set on an assistant message, raw OpenAI tool_calls JSON array. }
    ToolCallsJson: String;
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
    Procedure ClearStreamThread;
    Procedure RebuildSystemPrompt;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure ApplyConfig(Config: TAssistantConfig);
    Procedure SetEndpoint(Const ApiBase, Model: String);
    Procedure SetActiveSkill(Const SkillName: String);
    Procedure ClearHistory;
    Procedure AddMessage(Role: TAssistantMessageRole; Const Content: String);
    Procedure AddAssistantToolCalls(Const Content, ToolCallsJson: String);
    Procedure AddToolResult(Const ToolCallId, Content: String);
    Function MessageCount: Integer;
    Function GetMessage(Index: Integer; Out Role: TAssistantMessageRole; Out Content: String): Boolean;
    Function IsBusy: Boolean;
    Function IsSignedIn: Boolean;
    { Starts background SSE stream; OnToken is Synchronized to the main thread. }
    Function StartStream(OnToken: TAssistantStreamEvent): Boolean;
    Procedure CancelStream;
    { Call from the stream callback when IsFinished is True (main thread). }
    Procedure MarkStreamComplete;
    { GET /v1/language-models (fallback /v1/models). Fills ModelIds sorted, chat-oriented. }
    Function ListAvailableModels(ModelIds: TStrings; Out ErrorText: String): Boolean;
    { Rebuilds the next chat/completions body (used after a tool round). }
    Function BuildNextRequestJson: String;
    Property Model: String Read FModel;
    Property ApiBase: String Read FApiBase;
    Property ActiveSkill: String Read FActiveSkill;
    Property SystemPrompt: String Read FSystemPrompt Write FSystemPrompt;
    Property LastError: String Read FLastError;
  End;

Var
  AssistantClient: TAssistantService;

Implementation

Uses
  fphttpclient, opensslsockets, fpjson, jsonparser, GrokOAuth, AssistantSkills, AssistantTools;

Type
  TAssistantStreamThread = Class(TThread)
  Private
    FService: TAssistantService;
    FApiBase: String;
    FAccessToken: String;
    FModel: String;
    FRequestJson: String;
    FOnToken: TAssistantStreamEvent;
    FPendingContent: String;
    FPendingThinking: String;
    FPendingError: String;
    FPendingFinished: Boolean;
    FSseBuffer: String;
    FContentAccum: String;
    FThinkingAccum: String;
    FMergeLogCount: Integer;
    FToolCalls: TAssistantToolCallArray;
    FToolRound: Integer;
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
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(Service: TAssistantService; Const ApiBase, AccessToken, Model, RequestJson: String;
      OnToken: TAssistantStreamEvent);
  End;

  { Feeds TFPHTTPClient response bytes into SSE line parsing as they arrive. }
  TAssistantSSEStream = Class(TStream)
  Private
    FOwner: TAssistantStreamThread;
  Public
    Constructor Create(AOwner: TAssistantStreamThread);
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

Function JsonEscape(Const S: String): String;
Var
  I: Integer;
  C: Char;
Begin
  Result := '';
  For I := 1 To Length(S) Do
    Begin
      C := S[I];
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

Function BuildChatRequestJson(Const Model, SystemPrompt: String;
  Const Messages: Array Of TAssistantMessage; Const ToolsJson: String): String;
Var
  I: Integer;
  MsgJson, Joined: String;
  HasSystem: Boolean;
  ContentField: String;
Begin
  { Do not use TStringList.DelimitedText — QuoteChar wraps each part in extra "…"
    and produces invalid nested JSON (xAI returns HTTP 422). }
  Joined := '';
  HasSystem := False;
  If Trim(SystemPrompt) <> '' Then
    Begin
      Joined := Format('{"role":"system","content":"%s"}', [JsonEscape(SystemPrompt)]);
      HasSystem := True;
    End;
  For I := 0 To High(Messages) Do
    Begin
      If (Messages[I].Role = amrSystem) And HasSystem Then
        Continue;
      If Messages[I].Role = amrTool Then
        MsgJson := Format('{"role":"tool","tool_call_id":"%s","content":"%s"}',
          [JsonEscape(Messages[I].ToolCallId), JsonEscape(Messages[I].Content)])
      Else If Messages[I].ToolCallsJson <> '' Then
        Begin
          ContentField := Messages[I].Content;
          MsgJson := Format('{"role":"assistant","content":"%s","tool_calls":%s}',
            [JsonEscape(ContentField), Messages[I].ToolCallsJson]);
        End
      Else
        MsgJson := Format('{"role":"%s","content":"%s"}',
          [RoleToJson(Messages[I].Role), JsonEscape(Messages[I].Content)]);
      If Joined <> '' Then
        Joined := Joined + ',';
      Joined := Joined + MsgJson;
    End;
  If Trim(ToolsJson) <> '' Then
    Result := Format('{"model":"%s","stream":true,"messages":[%s],"tools":%s}',
      [JsonEscape(Model), Joined, ToolsJson])
  Else
    Result := Format('{"model":"%s","stream":true,"messages":[%s]}',
      [JsonEscape(Model), Joined]);
End;

{ TAssistantSSEStream }

Constructor TAssistantSSEStream.Create(AOwner: TAssistantStreamThread);
Begin
  Inherited Create;
  FOwner := AOwner;
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
  FService := Service;
  FApiBase := ApiBase;
  FAccessToken := AccessToken;
  FModel := Model;
  FRequestJson := RequestJson;
  FOnToken := OnToken;
  FSseBuffer := '';
  FContentAccum := '';
  FThinkingAccum := '';
  FMergeLogCount := 0;
  SetLength(FToolCalls, 0);
  FToolRound := 0;
End;

Procedure TAssistantStreamThread.NotifyMain;
Begin
  If Assigned(FOnToken) Then
    FOnToken(FPendingContent, FPendingThinking, FPendingFinished, FPendingError);
End;

Procedure TAssistantStreamThread.EmitSnapshots(IsDone: Boolean; Const ErrorText: String);
Begin
  FPendingContent := FContentAccum;
  FPendingThinking := FThinkingAccum;
  FPendingFinished := IsDone;
  FPendingError := ErrorText;
  Synchronize(@NotifyMain);
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

Function TAssistantStreamThread.MergeStreamText(Var Accum: String; Const Delta: String): Boolean;
Begin
  { Same rules as content merge: init / cumulative snapshot / stale ignore / append. }
  Result := False;
  If Delta = '' Then
    Exit;
  If Accum = '' Then
    Begin
      Accum := Delta;
      Result := True;
      Exit;
    End;
  If (Length(Delta) >= Length(Accum)) And (Copy(Delta, 1, Length(Accum)) = Accum) Then
    Begin
      If Delta = Accum Then
        Exit;
      Accum := Delta;
      Result := True;
      Exit;
    End;
  If (Length(Delta) < Length(Accum)) And (Copy(Accum, 1, Length(Delta)) = Delta) Then
    Exit;
  Accum := Accum + Delta;
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
  Result := False;
  For I := 0 To High(FToolCalls) Do
    If (FToolCalls[I].Name <> '') Or (FToolCalls[I].Arguments <> '') Then
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
      Ok := ExecuteAssistantTool(FToolCalls[I].Name, FToolCalls[I].Arguments, ResultText, ErrorText);
      If Ok Then
        Content := ResultText
      Else
        Content := 'Error: ' + ErrorText;
      FService.AddToolResult(FToolCalls[I].Id, Content);
      WorkflowLogger.Info('AssistantStream',
        Format('tool %s ok=%s len=%d', [FToolCalls[I].Name, BoolToStr(Ok, True), Length(Content)]));
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
  Client: TFPHTTPClient;
  Body: TStringStream;
  OutStream: TAssistantSSEStream;
  Code: Integer;
  ErrBody: String;
Begin
  Result := False;
  ErrorText := '';
  FSseBuffer := '';
  SetLength(FToolCalls, 0);
  Client := TFPHTTPClient.Create(Nil);
  Body := TStringStream.Create(RequestJson);
  OutStream := TAssistantSSEStream.Create(Self);
  Try
    Try
      Client.AllowRedirect := True;
      Client.AddHeader('Authorization', 'Bearer ' + FAccessToken);
      Client.AddHeader('Content-Type', 'application/json');
      Client.AddHeader('Accept', 'text/event-stream');
      Client.RequestBody := Body;
      Client.HTTPMethod('POST', Url, OutStream, []);
      Code := Client.ResponseStatusCode;
      If (Code < 200) Or (Code >= 300) Then
        Begin
          ErrBody := Trim(FSseBuffer);
          If ErrBody = '' Then
            ErrBody := Client.ResponseStatusText;
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
        ErrorText := E.Message;
    End;
  Finally
    Client.RequestBody := Nil;
    OutStream.Free;
    Body.Free;
    Client.Free;
  End;
End;

Procedure TAssistantStreamThread.Execute;
Const
  { One HTTP stream that ends with tool_calls counts as a round; allow multi-file
    exploration without failing mid-answer on large units. }
  MaxToolRounds = 12;
Var
  Url, ErrorText, RequestJson: String;
  RoundNo: Integer;
Begin
  Url := Trim(FApiBase);
  While (Length(Url) > 0) And (Url[Length(Url)] = '/') Do
    SetLength(Url, Length(Url) - 1);
  Url := Url + '/chat/completions';

  RequestJson := FRequestJson;
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
      { Tool round: run tools on the main thread, then continue the conversation. }
      Inc(FToolRound);
      WorkflowLogger.Info('AssistantStream', Format('tool round %d (%d calls)',
        [FToolRound, Length(FToolCalls)]));
      { ErrorText while not finished is treated as a status phase by the chat UI. }
      EmitSnapshots(False, 'Running tools…');
      Synchronize(@RunToolRoundOnMain);
      If Terminated Or Not Assigned(FService) Then
        Break;
      RequestJson := FService.BuildNextRequestJson;
    End;
  EmitSnapshots(True, Format(
    'Tool-call round limit reached after %d rounds. Ask a more focused question or use start_line on read_file to page large files.',
    [FToolRound]));
End;

{ TAssistantService }

Constructor TAssistantService.Create;
Begin
  Inherited Create;
  FApiBase := AssistantConfigDefaultApiBase;
  FModel := AssistantConfigDefaultModel;
  FBaseSystemPrompt := 'You are a helpful Free Pascal / Lazarus expert working inside the IDE. ' +
    'You may call tools read_file, list_directory, open_markdown, and get_project_info when you need project files or to open Markdown. ' +
    'For large files use read_file start_line/end_line to page; if a result says truncated, continue from the suggested start_line instead of re-reading from line 1. ' +
    'Prefer the active editor context already in the user message when it includes the code under discussion.';
  FActiveSkill := '';
  FSystemPrompt := FBaseSystemPrompt;
  SetLength(FMessages, 0);
  FStreamThread := Nil;
  FBusy := False;
  FLastError := '';
End;

Procedure TAssistantService.RebuildSystemPrompt;
Begin
  FSystemPrompt := BuildSystemPromptWithSkill(FBaseSystemPrompt, FActiveSkill);
End;

Destructor TAssistantService.Destroy;
Begin
  CancelStream;
  SetLength(FMessages, 0);
  Inherited Destroy;
End;

Procedure TAssistantService.ClearStreamThread;
Begin
  If Assigned(FStreamThread) Then
    Begin
      FStreamThread.Terminate;
      FStreamThread.WaitFor;
      FreeAndNil(FStreamThread);
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
Begin
  FActiveSkill := Trim(SkillName);
  RebuildSystemPrompt;
  If FActiveSkill <> '' Then
    WorkflowLogger.Info('AssistantService', 'Active skill set to ' + FActiveSkill)
  Else
    WorkflowLogger.Info('AssistantService', 'Active skill cleared');
End;

Procedure TAssistantService.ClearHistory;
Begin
  SetLength(FMessages, 0);
End;

Procedure TAssistantService.AddMessage(Role: TAssistantMessageRole; Const Content: String);
Var
  Idx: Integer;
Begin
  Idx := Length(FMessages);
  SetLength(FMessages, Idx + 1);
  FMessages[Idx].Role := Role;
  FMessages[Idx].Content := Content;
  FMessages[Idx].ToolCallId := '';
  FMessages[Idx].ToolCallsJson := '';
End;

Procedure TAssistantService.AddAssistantToolCalls(Const Content, ToolCallsJson: String);
Var
  Idx: Integer;
Begin
  Idx := Length(FMessages);
  SetLength(FMessages, Idx + 1);
  FMessages[Idx].Role := amrAssistant;
  FMessages[Idx].Content := Content;
  FMessages[Idx].ToolCallId := '';
  FMessages[Idx].ToolCallsJson := ToolCallsJson;
End;

Procedure TAssistantService.AddToolResult(Const ToolCallId, Content: String);
Var
  Idx: Integer;
Begin
  Idx := Length(FMessages);
  SetLength(FMessages, Idx + 1);
  FMessages[Idx].Role := amrTool;
  FMessages[Idx].Content := Content;
  FMessages[Idx].ToolCallId := ToolCallId;
  FMessages[Idx].ToolCallsJson := '';
End;

Function TAssistantService.BuildNextRequestJson: String;
Begin
  Result := BuildChatRequestJson(FModel, FSystemPrompt, FMessages, BuildAssistantToolsJson);
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
  Client: TFPHTTPClient;
  AccessToken, BaseUrl, Body: String;
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

  Client := TFPHTTPClient.Create(Nil);
  Try
    Client.AllowRedirect := True;
    Client.AddHeader('Authorization', 'Bearer ' + AccessToken);
    Client.AddHeader('Accept', 'application/json');
    For PathIdx := 0 To High(Paths) Do
      Begin
        Body := '';
        Data := Nil;
        Try
          Try
            Body := Client.Get(BaseUrl + Paths[PathIdx]);
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
  Finally
    Client.Free;
  End;
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
  { Persist refreshed tokens so the next IDE session keeps working. }
  If Assigned(AssistantChatConfig) Then
    Begin
      AssistantChatConfig.ApplyOAuthTokens(GrokOAuthClient.Tokens);
      AssistantChatConfig.Save;
    End;
  If Not Assigned(OnToken) Then
    Begin
      FLastError := 'No stream callback.';
      Exit;
    End;

  ClearStreamThread;
  RequestJson := BuildChatRequestJson(FModel, FSystemPrompt, FMessages, BuildAssistantToolsJson);
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
