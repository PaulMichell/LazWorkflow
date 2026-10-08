Unit AssistantCompatibleClient;

{ OpenAI-compatible chat completions client. No Grok OAuth on this path.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, fpjson, AssistantConnections;

Const
  CompatibleUsageReported = 'reported';
  CompatibleUsageUnavailable = 'unavailable';

Type
  TCompatibleCompletion = Record
    Text: String;
    UsageState: String;
    PromptTokens: Integer;
    CompletionTokens: Integer;
    Cost: Double;
    HasCost: Boolean;
  End;

  { Plain functions so a fixture can answer without opening a socket.
    ExtraHeaders is "Name: value" lines. Do not log that text. }
  TCompatibleHttpGet = Function(Const Url, ExtraHeaders: String; Out ResponseBody: String;
    Out StatusCode: Integer; Out ErrorText: String): Boolean;
  TCompatibleHttpPost = Function(Const Url, JsonBody, ExtraHeaders: String; Out ResponseBody: String;
    Out StatusCode: Integer; Out ErrorText: String): Boolean;

  TAssistantCompatibleClient = Class
  Private
    FGet: TCompatibleHttpGet;
    FPost: TCompatibleHttpPost;
    Function DoGet(Const Url, ExtraHeaders: String; Out ResponseBody: String; Out StatusCode: Integer;
      Out ErrorText: String): Boolean;
    Function DoPost(Const Url, JsonBody, ExtraHeaders: String; Out ResponseBody: String;
      Out StatusCode: Integer; Out ErrorText: String): Boolean;
  Public
    Constructor Create;
    { Both procedures are required. A nil pair uses HttpsGet and HttpsPostJson. }
    Constructor CreateForTransport(GetFn: TCompatibleHttpGet; PostFn: TCompatibleHttpPost);
    Function ListModels(Connection: TAssistantConnection; ModelIds: TStrings; Out ErrorText: String): Boolean;
    Function CompleteOnce(Connection: TAssistantConnection; Messages: TJSONArray;
      Out Completion: TCompatibleCompletion; Out ErrorText: String): Boolean;
    /// GET {ApiBase}/key with the chat bearer header. Does not call /credits.
    Function FetchOpenRouterKey(Connection: TAssistantConnection; Out Body: String; Out StatusCode: Integer;
      Out ErrorText: String): Boolean;
  End;

Function ParseCompatibleModelList(Const Body: String; ModelIds: TStrings; Out ErrorText: String): Boolean;
Function ParseCompatibleCompletion(Const Body: String; Out Completion: TCompatibleCompletion;
  Out ErrorText: String): Boolean;

Implementation

Uses
  AssistantHttps;

Procedure ClearCompletion(Out Completion: TCompatibleCompletion);
Begin
  Completion.Text := '';
  Completion.UsageState := CompatibleUsageUnavailable;
  Completion.PromptTokens := 0;
  Completion.CompletionTokens := 0;
  Completion.Cost := 0;
  Completion.HasCost := False;
End;

Function JoinApiUrl(Const BaseUrl, Path: String): String;
Var
  Base, Suffix: String;
Begin
  Base := Trim(BaseUrl);
  While (Base <> '') And (Base[Length(Base)] = '/') Do
    Delete(Base, Length(Base), 1);
  Suffix := Path;
  If (Suffix = '') Or (Suffix[1] <> '/') Then
    Suffix := '/' + Suffix;
  Result := Base + Suffix;
End;

Function WireAccepted(Const WireApi: String): Boolean;
Begin
  Result := (WireApi = '') Or (WireApi = AssistantWireChatCompletions);
End;

Function KeyIsSingleLine(Const Key: String): Boolean;
Begin
  Result := (Pos(#10, Key) = 0) And (Pos(#13, Key) = 0);
End;

Function ResolveKey(Connection: TAssistantConnection; Out Key, ErrorText: String): Boolean;
Begin
  Result := False;
  Key := '';
  ErrorText := '';
  If Not Assigned(Connection) Then
    Begin
      ErrorText := 'A connection is required.';
      Exit;
    End;
  If Connection.KeySource = 'stored' Then
    Begin
      Key := Connection.KeyValue;
      If Key = '' Then
        Begin
          ErrorText := 'This connection has no stored key.';
          Exit;
        End;
    End
  Else If (Connection.KeySource = 'env') Or (Connection.KeySource = '') Then
    Begin
      If Trim(Connection.KeyEnv) = '' Then
        Begin
          ErrorText := 'This connection has no environment variable name.';
          Exit;
        End;
      { Read at request time. An empty or unset variable is not a key. }
      Key := GetEnvironmentVariable(Connection.KeyEnv);
      If Key = '' Then
        Begin
          ErrorText := 'Environment variable ' + Connection.KeyEnv + ' is not set.';
          Exit;
        End;
    End
  Else
    Begin
      ErrorText := 'Key source must be env or stored.';
      Exit;
    End;
  If Not KeyIsSingleLine(Key) Then
    Begin
      Key := '';
      ErrorText := 'The connection key is not a single line.';
      Exit;
    End;
  Result := True;
End;

Function RequestReady(Connection: TAssistantConnection; Out ErrorText: String): Boolean;
Begin
  Result := False;
  ErrorText := '';
  If Not Assigned(Connection) Then
    Begin
      ErrorText := 'A connection is required.';
      Exit;
    End;
  If Trim(Connection.ApiBase) = '' Then
    Begin
      ErrorText := 'This connection has no base URL.';
      Exit;
    End;
  If Not WireAccepted(Connection.WireApi) Then
    Begin
      ErrorText := 'Wire must be chat-completions.';
      Exit;
    End;
  Result := True;
End;

{ Authorization and the optional title. Callers must not log this text. }
Function RequestHeaders(Const Preset, Key: String): String;
Begin
  Result := 'Authorization: Bearer ' + Key;
  If Preset = 'openrouter' Then
    Result := Result + LineEnding + 'X-Title: LazWorkflow';
End;

Function HttpFailure(Const StatusCode: Integer; Const Body: String): String;
Var
  Detail: String;
Begin
  Result := 'HTTP ' + IntToStr(StatusCode);
  Detail := HttpsResponseErrorMessage(Body);
  If Detail <> '' Then
    Result := Result + ': ' + Detail;
End;

Function JsonInt(Obj: TJSONObject; Const Name: String): Integer;
Var
  Node: TJSONData;
Begin
  Result := 0;
  If Not Assigned(Obj) Then
    Exit;
  Node := Obj.Find(Name);
  If Assigned(Node) And (Node.JSONType = jtNumber) Then
    Result := Node.AsInteger;
End;

Function JsonNumber(Obj: TJSONObject; Const Name: String; Out Value: Double): Boolean;
Var
  Node: TJSONData;
Begin
  Result := False;
  Value := 0;
  If Not Assigned(Obj) Then
    Exit;
  Node := Obj.Find(Name);
  If Assigned(Node) And (Node.JSONType = jtNumber) Then
    Begin
      Value := Node.AsFloat;
      Result := True;
    End;
End;

Function MessageText(MessageObj: TJSONObject): String;
Var
  Content, Part: TJSONData;
  Arr: TJSONArray;
  I: Integer;
  Piece: String;
Begin
  Result := '';
  If Not Assigned(MessageObj) Then
    Exit;
  Content := MessageObj.Find('content');
  If (Not Assigned(Content)) Or (Content.JSONType = jtNull) Then
    Exit;
  If Content.JSONType = jtString Then
    Exit(Content.AsString);
  If Not (Content Is TJSONArray) Then
    Exit;
  Arr := TJSONArray(Content);
  For I := 0 To Arr.Count - 1 Do
    Begin
      Part := Arr.Items[I];
      Piece := '';
      If Part Is TJSONObject Then
        Piece := TJSONObject(Part).Get('text', '')
      Else If Part.JSONType = jtString Then
        Piece := Part.AsString;
      If Piece <> '' Then
        Result := Result + Piece;
    End;
End;

Function ParseCompatibleModelList(Const Body: String; ModelIds: TStrings; Out ErrorText: String): Boolean;
Var
  Data, Item: TJSONData;
  Root: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  ModelId: String;
Begin
  Result := False;
  ErrorText := '';
  If Not Assigned(ModelIds) Then
    Begin
      ErrorText := 'Model list is nil.';
      Exit;
    End;
  ModelIds.Clear;
  Data := Nil;
  Try
    Try
      Data := GetJSON(Body);
    Except
      On E: Exception Do
        Begin
          ErrorText := 'The response is not a model list.';
          Exit;
        End;
    End;
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'The response is not a model list.';
        Exit;
      End;
    Root := TJSONObject(Data);
    If Not (Root.Find('data') Is TJSONArray) Then
      Begin
        ErrorText := 'The response is not a model list.';
        Exit;
      End;
    Arr := TJSONArray(Root.Find('data'));
    For I := 0 To Arr.Count - 1 Do
      Begin
        Item := Arr.Items[I];
        ModelId := '';
        If Item Is TJSONObject Then
          ModelId := TJSONObject(Item).Get('id', '')
        Else If Item.JSONType = jtString Then
          ModelId := Item.AsString;
        If ModelId <> '' Then
          ModelIds.Add(ModelId);
      End;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function ParseCompatibleCompletion(Const Body: String; Out Completion: TCompatibleCompletion;
  Out ErrorText: String): Boolean;
Var
  Data: TJSONData;
  Root, Choice, MessageObj, Usage: TJSONObject;
  Arr: TJSONArray;
Begin
  Result := False;
  ErrorText := '';
  ClearCompletion(Completion);
  Data := Nil;
  Try
    Try
      Data := GetJSON(Body);
    Except
      On E: Exception Do
        Begin
          ErrorText := 'The response is not a completion.';
          Exit;
        End;
    End;
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'The response is not a completion.';
        Exit;
      End;
    Root := TJSONObject(Data);
    If Not (Root.Find('choices') Is TJSONArray) Then
      Begin
        ErrorText := 'The response is not a completion.';
        Exit;
      End;
    Arr := TJSONArray(Root.Find('choices'));
    If (Arr.Count < 1) Or Not (Arr.Items[0] Is TJSONObject) Then
      Begin
        ErrorText := 'The response is not a completion.';
        Exit;
      End;
    Choice := TJSONObject(Arr.Items[0]);
    If Not (Choice.Find('message') Is TJSONObject) Then
      Begin
        ErrorText := 'The response is not a completion.';
        Exit;
      End;
    MessageObj := TJSONObject(Choice.Find('message'));
    Completion.Text := MessageText(MessageObj);
    If Root.Find('usage') Is TJSONObject Then
      Usage := TJSONObject(Root.Find('usage'))
    Else
      Usage := Nil;
    If Assigned(Usage) Then
      Begin
        Completion.UsageState := CompatibleUsageReported;
        Completion.PromptTokens := JsonInt(Usage, 'prompt_tokens');
        Completion.CompletionTokens := JsonInt(Usage, 'completion_tokens');
        Completion.HasCost := JsonNumber(Usage, 'cost', Completion.Cost);
      End
    Else
      Completion.UsageState := CompatibleUsageUnavailable;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Constructor TAssistantCompatibleClient.Create;
Begin
  Inherited Create;
  FGet := Nil;
  FPost := Nil;
End;

Constructor TAssistantCompatibleClient.CreateForTransport(GetFn: TCompatibleHttpGet; PostFn: TCompatibleHttpPost);
Begin
  Inherited Create;
  If Assigned(GetFn) And Assigned(PostFn) Then
    Begin
      FGet := GetFn;
      FPost := PostFn;
    End
  Else
    Begin
      FGet := Nil;
      FPost := Nil;
    End;
End;

Function TAssistantCompatibleClient.DoGet(Const Url, ExtraHeaders: String; Out ResponseBody: String;
  Out StatusCode: Integer; Out ErrorText: String): Boolean;
Begin
  ResponseBody := '';
  StatusCode := 0;
  ErrorText := '';
  If Assigned(FGet) Then
    Result := FGet(Url, ExtraHeaders, ResponseBody, StatusCode, ErrorText)
  Else
    Result := HttpsGet(Url, ResponseBody, StatusCode, ErrorText, ExtraHeaders);
End;

Function TAssistantCompatibleClient.DoPost(Const Url, JsonBody, ExtraHeaders: String; Out ResponseBody: String;
  Out StatusCode: Integer; Out ErrorText: String): Boolean;
Begin
  ResponseBody := '';
  StatusCode := 0;
  ErrorText := '';
  If Assigned(FPost) Then
    Result := FPost(Url, JsonBody, ExtraHeaders, ResponseBody, StatusCode, ErrorText)
  Else
    Result := HttpsPostJson(Url, JsonBody, ExtraHeaders, ResponseBody, StatusCode, ErrorText);
End;

Function TAssistantCompatibleClient.ListModels(Connection: TAssistantConnection; ModelIds: TStrings;
  Out ErrorText: String): Boolean;
Var
  Key, Headers, Url, Body: String;
  StatusCode: Integer;
Begin
  Result := False;
  ErrorText := '';
  If Assigned(ModelIds) Then
    ModelIds.Clear;
  If Not RequestReady(Connection, ErrorText) Then
    Exit;
  If Not ResolveKey(Connection, Key, ErrorText) Then
    Exit;
  Headers := RequestHeaders(Connection.Preset, Key);
  Url := JoinApiUrl(Connection.ApiBase, '/models');
  Body := '';
  StatusCode := 0;
  If Not DoGet(Url, Headers, Body, StatusCode, ErrorText) Then
    Begin
      If ErrorText = '' Then
        ErrorText := 'HTTPS request failed.';
      Exit;
    End;
  If StatusCode <> 200 Then
    Begin
      ErrorText := HttpFailure(StatusCode, Body);
      Exit;
    End;
  Result := ParseCompatibleModelList(Body, ModelIds, ErrorText);
End;

Function TAssistantCompatibleClient.FetchOpenRouterKey(Connection: TAssistantConnection; Out Body: String;
  Out StatusCode: Integer; Out ErrorText: String): Boolean;
Var
  Key, Headers, Url: String;
Begin
  Result := False;
  Body := '';
  StatusCode := 0;
  ErrorText := '';
  If Not Assigned(Connection) Or (Connection.ApiBase <> AssistantOpenRouterApiBase) Then
    Begin
      ErrorText := 'This connection is not OpenRouter.';
      Exit;
    End;
  If Not RequestReady(Connection, ErrorText) Then
    Exit;
  If Not ResolveKey(Connection, Key, ErrorText) Then
    Exit;
  { Balance is /key. /credits needs a provisioning key this connection does not store. }
  Headers := RequestHeaders(Connection.Preset, Key);
  Url := JoinApiUrl(Connection.ApiBase, '/key');
  If Not DoGet(Url, Headers, Body, StatusCode, ErrorText) Then
    Begin
      If ErrorText = '' Then
        ErrorText := 'OpenRouter key usage request failed.';
      Exit;
    End;
  Result := True;
End;

Function TAssistantCompatibleClient.CompleteOnce(Connection: TAssistantConnection; Messages: TJSONArray;
  Out Completion: TCompatibleCompletion; Out ErrorText: String): Boolean;
Var
  Key, Headers, Url, Body, ResponseBody: String;
  StatusCode: Integer;
  Root: TJSONObject;
Begin
  Result := False;
  ErrorText := '';
  ClearCompletion(Completion);
  If Not RequestReady(Connection, ErrorText) Then
    Exit;
  If Trim(Connection.Model) = '' Then
    Begin
      ErrorText := 'This connection has no model.';
      Exit;
    End;
  If Not Assigned(Messages) Then
    Begin
      ErrorText := 'Messages are required.';
      Exit;
    End;
  If Not ResolveKey(Connection, Key, ErrorText) Then
    Exit;
  Headers := RequestHeaders(Connection.Preset, Key);
  Url := JoinApiUrl(Connection.ApiBase, '/chat/completions');
  Root := TJSONObject.Create;
  Try
    Root.Add('model', Connection.Model);
    Root.Add('messages', Messages.Clone);
    If Connection.MaxOutputTokens > 0 Then
      Root.Add('max_tokens', Connection.MaxOutputTokens);
    Body := Root.AsJSON;
  Finally
    Root.Free;
  End;
  ResponseBody := '';
  StatusCode := 0;
  If Not DoPost(Url, Body, Headers, ResponseBody, StatusCode, ErrorText) Then
    Begin
      If ErrorText = '' Then
        ErrorText := 'HTTPS request failed.';
      Exit;
    End;
  If StatusCode <> 200 Then
    Begin
      ErrorText := HttpFailure(StatusCode, ResponseBody);
      Exit;
    End;
  Result := ParseCompatibleCompletion(ResponseBody, Completion, ErrorText);
End;

End.
