Unit GrokService;

{ Grok / OpenAI-compatible LLM service with SSE streaming (c) 2026 Michell Computing. }

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

  { Called on the main thread for each content fragment; IsFinished ends the stream. }
  TGrokStreamEvent = Procedure(Const Token: String; IsFinished: Boolean;
    Const ErrorText: String) Of Object;

  TGrokService = Class
  Private
    FApiBase: String;
    FApiKey: String;
    FModel: String;
    FSystemPrompt: String;
    FMessages: Array Of TGrokMessage;
    FLastError: String;
    FStreamThread: TThread;
    FBusy: Boolean;
    Procedure ClearStreamThread;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure ApplyConfig(Config: TGrokConfig);
    Procedure SetCredentials(Const ApiBase, ApiKey, Model: String);
    Procedure ClearHistory;
    Procedure AddMessage(Role: TGrokMessageRole; Const Content: String);
    Function MessageCount: Integer;
    Function IsBusy: Boolean;
    { Starts background SSE stream; OnToken is Synchronized to the main thread. }
    Function StartStream(OnToken: TGrokStreamEvent): Boolean;
    Procedure CancelStream;
    { Call from the stream callback when IsFinished is True (main thread). }
    Procedure MarkStreamComplete;
    Property Model: String Read FModel;
    Property ApiBase: String Read FApiBase;
    Property SystemPrompt: String Read FSystemPrompt Write FSystemPrompt;
    Property LastError: String Read FLastError;
  End;

Var
  GrokClient: TGrokService;

Implementation

Uses
  fphttpclient, opensslsockets, fpjson, jsonparser;

Type
  TGrokStreamThread = Class(TThread)
  Private
    FApiBase: String;
    FApiKey: String;
    FModel: String;
    FRequestJson: String;
    FOnToken: TGrokStreamEvent;
    FPendingToken: String;
    FPendingError: String;
    FPendingFinished: Boolean;
    FSseBuffer: String;
    FAccumulated: String;
    Procedure NotifyMain;
    Procedure EmitToken(Const Token: String; IsDone: Boolean; Const ErrorText: String);
    Procedure ProcessSseChunk(Const Chunk: String);
    Procedure ProcessSseLine(Const Line: String);
    Function ExtractDeltaContent(Const JsonText: String): String;
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(Const ApiBase, ApiKey, Model, RequestJson: String;
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

Constructor TGrokStreamThread.Create(Const ApiBase, ApiKey, Model, RequestJson: String;
  OnToken: TGrokStreamEvent);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  FApiBase := ApiBase;
  FApiKey := ApiKey;
  FModel := Model;
  FRequestJson := RequestJson;
  FOnToken := OnToken;
  FSseBuffer := '';
  FAccumulated := '';
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

Function TGrokStreamThread.ExtractDeltaContent(Const JsonText: String): String;
Var
  Data: TJSONData;
  Obj, Choice, Delta: TJSONObject;
  Arr: TJSONArray;
Begin
  Result := '';
  Data := Nil;
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
    If Assigned(Delta) And (Delta.Find('content') <> Nil) Then
      Result := Delta.Get('content', '');
  Except
    Result := '';
  End;
  Data.Free;
End;

Procedure TGrokStreamThread.ProcessSseLine(Const Line: String);
Var
  Payload, Delta: String;
Begin
  If Terminated Then
    Exit;
  If Trim(Line) = '' Then
    Exit;
  If Copy(Line, 1, 6) <> 'data: ' Then
    Exit;
  Payload := Trim(Copy(Line, 7, MaxInt));
  If Payload = '' Then
    Exit;
  If Payload = '[DONE]' Then
    Exit;
  Delta := ExtractDeltaContent(Payload);
  If Delta <> '' Then
    Begin
      FAccumulated := FAccumulated + Delta;
      EmitToken(Delta, False, '');
    End;
End;

Procedure TGrokStreamThread.ProcessSseChunk(Const Chunk: String);
Var
  P: Integer;
  Line: String;
Begin
  FSseBuffer := FSseBuffer + Chunk;
  { Normalize CRLF. }
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
      Client.AddHeader('Authorization', 'Bearer ' + FApiKey);
      Client.AddHeader('Content-Type', 'application/json');
      Client.AddHeader('Accept', 'text/event-stream');
      Client.RequestBody := Body;
      { Empty allowed codes: accept any status so we can report the error body. }
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
  FApiKey := '';
  FModel := GrokConfigDefaultModel;
  FSystemPrompt := 'You are a helpful Free Pascal / Lazarus expert working inside the IDE.';
  SetLength(FMessages, 0);
  FStreamThread := Nil;
  FBusy := False;
  FLastError := '';
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
  SetCredentials(Config.ApiBase, Config.ApiKey, Config.Model);
End;

Procedure TGrokService.SetCredentials(Const ApiBase, ApiKey, Model: String);
Begin
  If ApiBase <> '' Then
    FApiBase := ApiBase;
  FApiKey := ApiKey;
  If Model <> '' Then
    FModel := Model;
  WorkflowLogger.Info('GrokService', 'Credentials updated – model=' + FModel);
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

Function TGrokService.StartStream(OnToken: TGrokStreamEvent): Boolean;
Var
  RequestJson: String;
Begin
  Result := False;
  FLastError := '';
  If FBusy Then
    Begin
      FLastError := 'A request is already in progress.';
      Exit;
    End;
  If Trim(FApiKey) = '' Then
    Begin
      FLastError := 'API key is not set. Open Grok Settings and enter your key.';
      Exit;
    End;
  If Not Assigned(OnToken) Then
    Begin
      FLastError := 'No stream callback.';
      Exit;
    End;

  ClearStreamThread;
  RequestJson := BuildChatRequestJson(FModel, FSystemPrompt, FMessages);
  FStreamThread := TGrokStreamThread.Create(FApiBase, FApiKey, FModel, RequestJson, OnToken);
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
