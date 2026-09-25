Unit AssistantXaiProvider;

{ Existing Grok subscription OAuth transport, isolated from shared orchestration.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  AssistantModelProvider, AssistantConfig;

Type
  TXaiImageInput = (xiiUnknown, xiiAccepted, xiiAbsent);

Function CreateXaiModelProvider: IAssistantModelProvider;
Procedure RestoreXaiCredentials(Config: TAssistantConfig);
/// Last successful model list. xiiUnknown means no explicit input-modality list: allow attach.
Function XaiModelImageInput(Const ModelId: String): TXaiImageInput;

Implementation

Uses
  Classes, SysUtils, fpjson, jsonparser, GrokOAuth, AssistantHttps,
  AssistantProtocol, WorkflowLog;

Type
  TXaiModelProvider = Class(TInterfacedObject, IAssistantModelProvider)
    Function BackendId: String;
    Function Authentication: TAssistantAuthentication;
    Function IsSignedIn: Boolean;
    Function GetAccessToken(PersistRefresh: Boolean; Out Token, ErrorText: String): Boolean;
    Function ListModels(Const ApiBase: String; ModelIds: TStrings;
      PersistRefresh: Boolean; Out ErrorText: String): Boolean;
    Function CompleteOnce(Const ApiBase, Model, SystemPrompt, UserPrompt: String;
      PersistRefresh: Boolean; Out AnswerText, ErrorText: String): Boolean;
  End;

Function CreateXaiModelProvider: IAssistantModelProvider;
Begin
  Result := TXaiModelProvider.Create;
End;

Procedure RestoreXaiCredentials(Config: TAssistantConfig);
Begin
  If Assigned(Config) And Assigned(GrokOAuthClient) Then
    GrokOAuthClient.SetTokens(Config.ToOAuthTokens);
End;

Function TXaiModelProvider.BackendId: String;
Begin
  Result := 'xai-subscription';
End;

Function TXaiModelProvider.Authentication: TAssistantAuthentication;
Begin
  Result := aaaSubscription;
End;

Function TXaiModelProvider.IsSignedIn: Boolean;
Begin
  Result := Assigned(GrokOAuthClient) And GrokOAuthClient.IsAuthenticated;
End;

Function TXaiModelProvider.GetAccessToken(PersistRefresh: Boolean;
    Out Token, ErrorText: String): Boolean;
Begin
  Result := False;
  Token := '';
  ErrorText := '';
  If Not Assigned(GrokOAuthClient) Then
    Begin
      ErrorText := 'Grok OAuth client is not available.';
      Exit;
    End;
  Token := GrokOAuthClient.GetValidAccessToken;
  If Token = '' Then
    Begin
      ErrorText := GrokOAuthClient.LastError;
      If ErrorText = '' Then ErrorText := 'Sign in with your Grok subscription in Assistant Settings.';
      Exit;
    End;
  If PersistRefresh And Assigned(AssistantChatConfig) Then
    Begin
      AssistantChatConfig.ApplyOAuthTokens(GrokOAuthClient.Tokens);
      AssistantChatConfig.Save;
    End;
  Result := True;
End;

Function JsonStringField(Obj: TJSONObject; Const Name: String): String;
Var
  Node: TJSONData;
Begin
  Result := '';
  If Not Assigned(Obj) Then Exit;
  Node := Obj.Find(Name);
  If Assigned(Node) And (Node.JSONType <> jtNull) Then Result := Node.AsString;
End;

Var
  ImageInputIds: TStringList;

Function XaiModelImageInput(Const ModelId: String): TXaiImageInput;
Var
  Index: Integer;
  Key: String;
Begin
  Result := xiiUnknown;
  Key := LowerCase(Trim(ModelId));
  If (Key = '') Or (Not Assigned(ImageInputIds)) Then Exit;
  Index := ImageInputIds.IndexOfName(Key);
  If Index < 0 Then Exit;
  If ImageInputIds.ValueFromIndex[Index] = '1' Then
    Result := xiiAccepted
  Else
    Result := xiiAbsent;
End;

Procedure RememberImageInput(List: TStringList; Const ModelId: String; Accepts: Boolean);
Var
  Key, Flag: String;
Begin
  If Not Assigned(List) Then Exit;
  Key := LowerCase(Trim(ModelId));
  If Key = '' Then Exit;
  If Accepts Then Flag := '1' Else Flag := '0';
  List.Values[Key] := Flag;
End;

Function ModalityListHasImage(Arr: TJSONArray): Boolean;
Var
  I: Integer;
  Item: TJSONData;
  Name: String;
Begin
  Result := False;
  If Not Assigned(Arr) Then Exit;
  For I := 0 To Arr.Count - 1 Do
    Begin
      Item := Arr.Items[I];
      Name := '';
      If Item.JSONType = jtString Then
        Name := LowerCase(Trim(Item.AsString))
      Else If Item Is TJSONObject Then
        Begin
          Name := LowerCase(Trim(JsonStringField(TJSONObject(Item), 'type')));
          If Name = '' Then Name := LowerCase(Trim(JsonStringField(TJSONObject(Item), 'name')));
        End;
      If (Name = 'image') Or (Name = 'images') Then Exit(True);
    End;
End;

Procedure NoteExplicitImageInput(List: TStringList; Obj: TJSONObject; Const ModelId: String);
Var
  Node, AliasNode: TJSONData;
  Aliases: TJSONArray;
  I: Integer;
  Accepts: Boolean;
Begin
  If (Not Assigned(List)) Or (Not Assigned(Obj)) Or (Trim(ModelId) = '') Then Exit;
  Node := Obj.Find('input_modalities');
  If Node = Nil Then Node := Obj.Find('inputModalities');
  If (Node = Nil) Or (Node.JSONType <> jtArray) Then Exit;
  Accepts := ModalityListHasImage(TJSONArray(Node));
  RememberImageInput(List, ModelId, Accepts);
  AliasNode := Obj.Find('aliases');
  If (AliasNode = Nil) Or (AliasNode.JSONType <> jtArray) Then Exit;
  Aliases := TJSONArray(AliasNode);
  For I := 0 To Aliases.Count - 1 Do
    If Aliases.Items[I].JSONType = jtString Then
      RememberImageInput(List, Aliases.Items[I].AsString, Accepts);
End;

Procedure PublishImageInput(Noted: TStringList);
Begin
  FreeAndNil(ImageInputIds);
  ImageInputIds := Noted;
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

Function TXaiModelProvider.ListModels(Const ApiBase: String; ModelIds: TStrings;
    PersistRefresh: Boolean; Out ErrorText: String): Boolean;
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
  Noted: TStringList;
Begin
  Result := False;
  ErrorText := '';
  If Not Assigned(ModelIds) Then
    Begin
      ErrorText := 'Model list is nil.';
      Exit;
    End;
  ModelIds.Clear;
  If Not GetAccessToken(PersistRefresh, AccessToken, ErrorText) Then Exit;

  BaseUrl := Trim(ApiBase);
  While (Length(BaseUrl) > 0) And (BaseUrl[Length(BaseUrl)] = '/') Do
    SetLength(BaseUrl, Length(BaseUrl) - 1);
  Paths[0] := '/language-models';
  Paths[1] := '/models';
  AuthHdr := 'Authorization: Bearer ' + AccessToken;
  Noted := TStringList.Create;
  Noted.NameValueSeparator := '=';
  Try
    For PathIdx := 0 To High(Paths) Do
      Begin
        Noted.Clear;
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
                  NoteExplicitImageInput(Noted, Obj, ModelId);
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
              WorkflowLogger.Info('AssistantXaiProvider',
                Format('Listed %d models via %s', [ModelIds.Count, Paths[PathIdx]]));
              PublishImageInput(Noted);
              Noted := Nil;
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
  Finally
    Noted.Free;
  End;
  If ErrorText = '' Then
    ErrorText := 'No chat models returned by the API.';
End;

Function TXaiModelProvider.CompleteOnce(Const ApiBase, Model, SystemPrompt, UserPrompt: String;
    PersistRefresh: Boolean; Out AnswerText, ErrorText: String): Boolean;
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
  If Not GetAccessToken(PersistRefresh, AccessToken, ErrorText) Then Exit;
  If Model = '' Then
    Begin
      ErrorText := 'No model configured.';
      Exit;
    End;
  Url := Trim(ApiBase);
  While (Length(Url) > 0) And (Url[Length(Url)] = '/') Do
    SetLength(Url, Length(Url) - 1);
  Url := Url + '/chat/completions';
  Body :=
    '{"model":"' + JsonEscapeText(Model) + '","stream":false,"messages":[' +
    '{"role":"system","content":"' + JsonEscapeText(SystemPrompt) + '"},' +
    '{"role":"user","content":"' + JsonEscapeText(UserPrompt) + '"}' +
    ']}';
  Headers := 'Authorization: Bearer ' + AccessToken;
  If Not HttpsPostJson(Url, Body, Headers, ResponseBody, StatusCode, ErrorText) Then
    Begin
      If ErrorText = '' Then
        ErrorText := 'HTTPS request failed.';
      Exit;
    End;
  If (StatusCode < 200) Or (StatusCode >= 300) Then
    Begin
      ErrorText := Format('HTTP %d: %s', [StatusCode, Copy(ResponseBody, 1, 400)]);
      Exit;
    End;
  Data := Nil;
  Try
    Try
      Data := GetJSON(ResponseBody);
      If Not (Data Is TJSONObject) Then
        Begin
          ErrorText := 'Unexpected completion response.';
          Exit;
        End;
      Arr := TJSONObject(Data).FindPath('choices') As TJSONArray;
      If (Arr = Nil) Or (Arr.Count < 1) Or Not (Arr.Items[0] Is TJSONObject) Then
        Begin
          ErrorText := 'No choices in completion response.';
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
          Exit;
        End;
      Result := True;
    Except
      On E: Exception Do
        Begin
          ErrorText := 'Parse error: ' + E.Message;
        End;
    End;
  Finally
    Data.Free;
  End;
End;

Finalization
  FreeAndNil(ImageInputIds);

End.
