Unit GrokService;

{ Grok LLM service with OAuth Bearer auth and SSE streaming (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, WorkflowLog, WorkflowEvents, GrokConfig;

Type
  TGrokMessageRole = (gmrSystem, gmrUser, gmrAssistant, gmrTool);

  TGrokMessage = Record
    Role: TGrokMessageRole;
    Content: String;
    ToolCallId: String;
  End;

  { Called on the main thread. While streaming, Token is the full assistant text so
    far (snapshot), not a raw delta. IsFinished ends the stream. }
  TGrokStreamEvent = Procedure(Const Token: String; IsFinished: Boolean;
    Const ErrorText: String) Of Object;

  TGrokService = Class
  Private
    FApiBase: String;
    FModel: String;
    FBaseSystemPrompt: String;
    FSystemPrompt: String;
    FActiveSkill: String;
    FMessages: Array Of TGrokMessage;
    FLastError: String;
    FStreamThread: TThread;
    FBusy: Boolean;
    Procedure ClearStreamThread;
    Procedure RebuildSystemPrompt;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure ApplyConfig(Config: TGrokConfig);
    Procedure SetEndpoint(Const ApiBase, Model: String);
    Procedure SetActiveSkill(Const SkillName: String);
    Procedure ClearHistory;
    Procedure AddMessage(Role: TGrokMessageRole; Const Content: String);
    Function MessageCount: Integer;
    Function IsBusy: Boolean;
    Function IsSignedIn: Boolean;
    { Starts background SSE stream; OnToken is Synchronized to the main thread. }
    Function StartStream(OnToken: TGrokStreamEvent): Boolean;
    Procedure CancelStream;
    { Call from the stream callback when IsFinished is True (main thread). }
    Procedure MarkStreamComplete;
    Property Model: String Read FModel;
    Property ApiBase: String Read FApiBase;
    Property ActiveSkill: String Read FActiveSkill;
    Property SystemPrompt: String Read FSystemPrompt Write FSystemPrompt;
    Property LastError: String Read FLastError;
  End;

Var
  GrokClient: TGrokService;

Implementation

Uses
  fphttpclient, opensslsockets, fpjson, jsonparser, GrokOAuth, GrokSkills;

Type
  TGrokStreamThread = Class(TThread)
  Private
    FApiBase: String;
    FAccessToken: String;
    FModel: String;
    FRequestJson: String;
    FOnToken: TGrokStreamEvent;
    FPendingToken: String;
    FPendingError: String;
    FPendingFinished: Boolean;
    FSseBuffer: String;
    FAccumulated: String;
    FMergeLogCount: Integer;
    Procedure NotifyMain;
    Procedure EmitToken(Const Token: String; IsDone: Boolean; Const ErrorText: String);
    Procedure ProcessSseChunk(Const Chunk: String);
    Procedure ProcessSseLine(Const Line: String);
    Function ExtractDeltaContent(Const JsonText: String): String;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(Const ApiBase, AccessToken, Model, RequestJson: String;
      OnToken: TGrokStreamEvent);
  End;

  { Feeds TFPHTTPClient response bytes into SSE line parsing as they arrive. }
  TGrokSSEStream = Class(TStream)
  Private
    FOwner: TGrokStreamThread;
  Public
    Constructor Create(AOwner: TGrokStreamThread);
    Function Write(Const Buffer; Count: LongInt): LongInt; Override;
    Function Seek(Const Offset: Int64; Origin: TSeekOrigin): Int64; Override;
  End;

Function RoleToJson(Role: TGrokMessageRole): String;
Begin
  Case Role Of
    gmrSystem: Result := 'system';
    gmrUser: Result := 'user';
    gmrAssistant: Result := 'assistant';
    gmrTool: Result := 'tool';
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
  Const Messages: Array Of TGrokMessage): String;
Var
  I: Integer;
  MsgJson, Joined: String;
  HasSystem: Boolean;
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
      If (Messages[I].Role = gmrSystem) And HasSystem Then
        Continue;
      MsgJson := Format('{"role":"%s","content":"%s"}',
        [RoleToJson(Messages[I].Role), JsonEscape(Messages[I].Content)]);
      If Joined <> '' Then
        Joined := Joined + ',';
      Joined := Joined + MsgJson;
    End;
  Result := Format('{"model":"%s","stream":true,"messages":[%s]}',
    [JsonEscape(Model), Joined]);
End;

{ TGrokSSEStream }

Constructor TGrokSSEStream.Create(AOwner: TGrokStreamThread);
Begin
  Inherited Create;
  FOwner := AOwner;
End;

Function TGrokSSEStream.Seek(Const Offset: Int64; Origin: TSeekOrigin): Int64;
Begin
  Result := 0;
End;

Function TGrokSSEStream.Write(Const Buffer; Count: LongInt): LongInt;
Var
  Chunk: String;
Begin
  Result := Count;
  If (Count <= 0) Or (Not Assigned(FOwner)) Or FOwner.Terminated Then
    Exit;
  SetString(Chunk, PChar(@Buffer), Count);
  FOwner.ProcessSseChunk(Chunk);
End;

{ TGrokStreamThread }

Constructor TGrokStreamThread.Create(Const ApiBase, AccessToken, Model, RequestJson: String;
  OnToken: TGrokStreamEvent);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  FApiBase := ApiBase;
  FAccessToken := AccessToken;
  FModel := Model;
  FRequestJson := RequestJson;
  FOnToken := OnToken;
  FSseBuffer := '';
  FAccumulated := '';
  FMergeLogCount := 0;
End;

Procedure TGrokStreamThread.NotifyMain;
Begin
  If Assigned(FOnToken) Then
    FOnToken(FPendingToken, FPendingFinished, FPendingError);
End;

Procedure TGrokStreamThread.EmitToken(Const Token: String; IsDone: Boolean;
  Const ErrorText: String);
Begin
  FPendingToken := Token;
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

Function TGrokStreamThread.ExtractDeltaContent(Const JsonText: String): String;
Var
  Data: TJSONData;
  Obj, Choice, Delta, MessageObj: TJSONObject;
  Arr: TJSONArray;
Begin
  { OpenAI-compatible stream: choices[0].delta.content (incremental only). }
  Result := '';
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
          Result := JsonStringField(Delta, 'content');
          If Result <> '' Then
            Exit;
          { Some gateways put text under delta.text. }
          Result := JsonStringField(Delta, 'text');
          If Result <> '' Then
            Exit;
        End;
      { Non-stream fallback shape (should be rare with stream:true). }
      MessageObj := Choice.FindPath('message') As TJSONObject;
      If Assigned(MessageObj) Then
        Result := JsonStringField(MessageObj, 'content');
    Except
      Result := '';
    End;
  Finally
    Data.Free;
  End;
End;

Procedure TGrokStreamThread.ProcessSseLine(Const Line: String);
Var
  Payload, Delta, Trimmed, Mode: String;
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
  Delta := ExtractDeltaContent(Payload);
  If Delta = '' Then
    Exit;
  { Merge rules (no last-line rewrite — that duplicated growing first-line prefixes):
      1. Empty buffer → take delta.
      2. Delta already contains full buffer as prefix → snapshot replace.
      3. Delta is a shorter prefix of buffer → stale snapshot, ignore.
      4. Otherwise → pure OpenAI-style delta, append. }
  If FAccumulated = '' Then
    Begin
      FAccumulated := Delta;
      Mode := 'init';
    End
  Else If (Length(Delta) >= Length(FAccumulated)) And
    (Copy(Delta, 1, Length(FAccumulated)) = FAccumulated) Then
    Begin
      If Delta = FAccumulated Then
        Exit;
      FAccumulated := Delta;
      Mode := 'snapshot';
    End
  Else If (Length(Delta) < Length(FAccumulated)) And
    (Copy(FAccumulated, 1, Length(Delta)) = Delta) Then
    Begin
      { Stale / rewound snapshot — keep what we have. }
      Exit;
    End
  Else
    Begin
      FAccumulated := FAccumulated + Delta;
      Mode := 'append';
    End;
  Inc(FMergeLogCount);
  If FMergeLogCount <= 12 Then
    WorkflowLogger.Info('GrokStream',
      Format('merge #%d %s deltaLen=%d accumLen=%d head=%s',
        [FMergeLogCount, Mode, Length(Delta), Length(FAccumulated),
         StringReplace(Copy(FAccumulated, 1, 80), #10, '\n', [rfReplaceAll])]));
  { Always push the full assistant text so far; UI replaces, never appends. }
  EmitToken(FAccumulated, False, '');
End;

Procedure TGrokStreamThread.ProcessSseChunk(Const Chunk: String);
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

Procedure TGrokStreamThread.Execute;
Var
  Client: TFPHTTPClient;
  Body: TStringStream;
  OutStream: TGrokSSEStream;
  Url: String;
  Code: Integer;
  ErrBody: String;
Begin
  Url := Trim(FApiBase);
  While (Length(Url) > 0) And (Url[Length(Url)] = '/') Do
    SetLength(Url, Length(Url) - 1);
  Url := Url + '/chat/completions';

  Client := TFPHTTPClient.Create(Nil);
  Body := TStringStream.Create(FRequestJson);
  OutStream := TGrokSSEStream.Create(Self);
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
          EmitToken('', True, Format('HTTP %d: %s', [Code, ErrBody]));
          Exit;
        End;
      If FSseBuffer <> '' Then
        ProcessSseLine(FSseBuffer);
      EmitToken('', True, '');
    Except
      On E: Exception Do
        EmitToken('', True, E.Message);
    End;
  Finally
    Client.RequestBody := Nil;
    OutStream.Free;
    Body.Free;
    Client.Free;
  End;
End;

{ TGrokService }

Constructor TGrokService.Create;
Begin
  Inherited Create;
  FApiBase := GrokConfigDefaultApiBase;
  FModel := GrokConfigDefaultModel;
  FBaseSystemPrompt := 'You are a helpful Free Pascal / Lazarus expert working inside the IDE.';
  FActiveSkill := '';
  FSystemPrompt := FBaseSystemPrompt;
  SetLength(FMessages, 0);
  FStreamThread := Nil;
  FBusy := False;
  FLastError := '';
End;

Procedure TGrokService.RebuildSystemPrompt;
Begin
  FSystemPrompt := BuildSystemPromptWithSkill(FBaseSystemPrompt, FActiveSkill);
End;

Destructor TGrokService.Destroy;
Begin
  CancelStream;
  SetLength(FMessages, 0);
  Inherited Destroy;
End;

Procedure TGrokService.ClearStreamThread;
Begin
  If Assigned(FStreamThread) Then
    Begin
      FStreamThread.Terminate;
      FStreamThread.WaitFor;
      FreeAndNil(FStreamThread);
    End;
  FBusy := False;
End;

Procedure TGrokService.ApplyConfig(Config: TGrokConfig);
Begin
  If Not Assigned(Config) Then
    Exit;
  SetEndpoint(Config.ApiBase, Config.Model);
  SetActiveSkill(Config.ActiveSkill);
  If Assigned(GrokOAuthClient) Then
    GrokOAuthClient.SetTokens(Config.ToOAuthTokens);
End;

Procedure TGrokService.SetEndpoint(Const ApiBase, Model: String);
Begin
  If ApiBase <> '' Then
    FApiBase := ApiBase;
  If Model <> '' Then
    FModel := Model;
  WorkflowLogger.Info('GrokService', 'Endpoint updated – model=' + FModel);
End;

Procedure TGrokService.SetActiveSkill(Const SkillName: String);
Begin
  FActiveSkill := Trim(SkillName);
  RebuildSystemPrompt;
  If FActiveSkill <> '' Then
    WorkflowLogger.Info('GrokService', 'Active skill set to ' + FActiveSkill)
  Else
    WorkflowLogger.Info('GrokService', 'Active skill cleared');
End;

Procedure TGrokService.ClearHistory;
Begin
  SetLength(FMessages, 0);
End;

Procedure TGrokService.AddMessage(Role: TGrokMessageRole; Const Content: String);
Var
  Idx: Integer;
Begin
  Idx := Length(FMessages);
  SetLength(FMessages, Idx + 1);
  FMessages[Idx].Role := Role;
  FMessages[Idx].Content := Content;
  FMessages[Idx].ToolCallId := '';
End;

Function TGrokService.MessageCount: Integer;
Begin
  Result := Length(FMessages);
End;

Function TGrokService.IsBusy: Boolean;
Begin
  Result := FBusy;
End;

Function TGrokService.IsSignedIn: Boolean;
Begin
  Result := Assigned(GrokOAuthClient) And GrokOAuthClient.IsAuthenticated;
End;

Function TGrokService.StartStream(OnToken: TGrokStreamEvent): Boolean;
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
        FLastError := 'Not signed in. Open Grok Settings and sign in with SuperGrok / X Premium.';
      Exit;
    End;
  { Persist refreshed tokens so the next IDE session keeps working. }
  If Assigned(GrokChatConfig) Then
    Begin
      GrokChatConfig.ApplyOAuthTokens(GrokOAuthClient.Tokens);
      GrokChatConfig.Save;
    End;
  If Not Assigned(OnToken) Then
    Begin
      FLastError := 'No stream callback.';
      Exit;
    End;

  ClearStreamThread;
  RequestJson := BuildChatRequestJson(FModel, FSystemPrompt, FMessages);
  FStreamThread := TGrokStreamThread.Create(FApiBase, AccessToken, FModel, RequestJson, OnToken);
  FBusy := True;
  FStreamThread.Start;
  Result := True;
  WorkflowLogger.Info('GrokService', 'Stream started – model=' + FModel);
End;

Procedure TGrokService.CancelStream;
Begin
  If Assigned(FStreamThread) Then
    Begin
      WorkflowLogger.Info('GrokService', 'Stream cancel requested');
      ClearStreamThread;
    End
  Else
    FBusy := False;
End;

Procedure TGrokService.MarkStreamComplete;
Begin
  FBusy := False;
End;

Initialization

GrokClient := TGrokService.Create;
If Assigned(GrokChatConfig) Then
  GrokClient.ApplyConfig(GrokChatConfig);

Finalization

FreeAndNil(GrokClient);

End.
