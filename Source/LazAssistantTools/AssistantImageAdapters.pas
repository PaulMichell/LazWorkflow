Unit AssistantImageAdapters;

{ Fills the generated-image record from each response shape, and posts one
  image request. Each backend builds its own JSON. A new provider is a new
  builder, not a new tool. The file writer does not use this unit.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils, AssistantGeneratedImage;

Type
  TGeneratedImagePost = Function(Const Url, Body, Headers: String; Out ResponseBody: String;
    Out StatusCode: Integer; Out ErrorText: String): Boolean;

Const
  { A hung image endpoint must not occupy the Build round budget. }
  AssistantImagePostTimeoutMs = 60000;

Procedure SetGeneratedImagePost(Post: TGeneratedImagePost);
/// POST this connection's image endpoint. The backend builds the JSON. Does not write a file.
/// Shape is optional. A value this backend cannot express is omitted, not an error.
Function RequestProfileImage(Const Prompt, Shape: String; Out Image: TAssistantGeneratedImage;
  Out ErrorText: String): Boolean;
/// Keep documented image parts from a Responses output array. An empty array is ignored.
Procedure RememberResponseImages(Const OutputJson: String);
Procedure RegisterBuiltinImageAdapters;

Implementation

Uses
  base64, fpjson, jsonparser, AssistantImages, AssistantConnections, AssistantConfig, AssistantHttps,
  AssistantXaiProvider, AssistantModelProvider;

Var
  ImagePost: TGeneratedImagePost;

Type
  TResponsesImageAdapter = Class(TInterfacedObject, IAssistantGeneratedImageAdapter)
    Function AdapterId: String;
    Function Collect(Const ResponseJson: String; Out Images: TAssistantGeneratedImageArray;
      Out ErrorText: String): Boolean;
  End;

  TImagesEndpointAdapter = Class(TInterfacedObject, IAssistantGeneratedImageAdapter)
    Function AdapterId: String;
    Function Collect(Const ResponseJson: String; Out Images: TAssistantGeneratedImageArray;
      Out ErrorText: String): Boolean;
  End;

  TChatCompletionsImageAdapter = Class(TInterfacedObject, IAssistantGeneratedImageAdapter)
    Function AdapterId: String;
    Function Collect(Const ResponseJson: String; Out Images: TAssistantGeneratedImageArray;
      Out ErrorText: String): Boolean;
  End;

Function StripWhitespace(Const Value: String): String;
Var
  I: Integer;
Begin
  Result := '';
  For I := 1 To Length(Value) Do
    If Not (Value[I] In [#9, #10, #13, ' ']) Then
      Result := Result + Value[I];
End;

Function PadBase64(Const Value: String): String;
Begin
  Result := StripWhitespace(Value);
  While (Result <> '') And (Length(Result) Mod 4 <> 0) Do
    Result := Result + '=';
End;

Function PayloadText(Const Encoded: String): String;
Var
  Marker, CommaAt: Integer;
  Lowered: String;
Begin
  Result := Trim(Encoded);
  Lowered := LowerCase(Result);
  Marker := Pos('base64,', Lowered);
  If Marker > 0 Then
    Result := Copy(Result, Marker + Length('base64,'), MaxInt)
  Else If Pos('data:', Lowered) = 1 Then
    Begin
      CommaAt := Pos(',', Result);
      If CommaAt > 0 Then
        Result := Copy(Result, CommaAt + 1, MaxInt);
    End;
End;

Function DecodeImagePayload(Const Encoded: String; Out Data: TBytes; Out ErrorText: String): Boolean;
Var
  Raw: AnsiString;
  I: Integer;
Begin
  SetLength(Data, 0);
  ErrorText := '';
  Result := False;
  Raw := '';
  Try
    Raw := DecodeStringBase64(PadBase64(PayloadText(Encoded)));
  Except
    On E: Exception Do
      Begin
        ErrorText := 'Generated image bytes could not be decoded.';
        Exit;
      End;
  End;
  If Raw = '' Then
    Begin
      ErrorText := 'Generated image bytes could not be decoded.';
      Exit;
    End;
  If Length(Raw) > AssistantImageMaxFileBytes Then
    Begin
      ErrorText := 'Generated image is over the size ceiling.';
      Exit;
    End;
  SetLength(Data, Length(Raw));
  For I := 1 To Length(Raw) Do
    Data[I - 1] := Byte(Raw[I]);
  Result := True;
End;

Function TurnLocalId(Const Candidate: String; Index: Integer): String;
Var
  I: Integer;
  C: Char;
Begin
  Result := Trim(Candidate);
  If (Result = '') Or (Length(Result) > 80) Then
    Exit('img-' + IntToStr(Index));
  For I := 1 To Length(Result) Do
    Begin
      C := Result[I];
      If Not (C In ['a'..'z', 'A'..'Z', '0'..'9', '-', '_', '.']) Then
        Exit('img-' + IntToStr(Index));
    End;
End;

Function AppendDecoded(Const Id, Encoded: String; Index: Integer;
  Var Images: TAssistantGeneratedImageArray; Out ErrorText: String): Boolean;
Var
  Image: TAssistantGeneratedImage;
  Data: TBytes;
Begin
  ClearGeneratedImage(Image);
  SetLength(Data, 0);
  Result := DecodeImagePayload(Encoded, Data, ErrorText);
  If Not Result Then
    Exit;
  If Not MeasureStillImage(Data, Image.Mime, Image.Width, Image.Height) Then
    Begin
      ErrorText := 'Generated image bytes are not a still image.';
      Exit(False);
    End;
  Image.Id := TurnLocalId(Id, Index);
  Image.Bytes := Data;
  SetLength(Images, Length(Images) + 1);
  Images[High(Images)] := Image;
  Result := True;
End;

Function OutputArray(Root: TJSONObject): TJSONArray;
Var
  Node: TJSONData;
Begin
  Result := Nil;
  If Not Assigned(Root) Then
    Exit;
  Node := Root.Find('output');
  If Node Is TJSONArray Then
    Exit(TJSONArray(Node));
  If Root.Find('type') <> Nil Then
    Begin
      Result := TJSONArray.Create;
      Result.Add(Root.Clone);
    End;
End;

Function TResponsesImageAdapter.AdapterId: String;
Begin
  Result := AssistantImageAdapterResponses;
End;

Function TResponsesImageAdapter.Collect(Const ResponseJson: String; Out Images: TAssistantGeneratedImageArray;
  Out ErrorText: String): Boolean;
Var
  Data: TJSONData;
  Root, Item: TJSONObject;
  Arr: TJSONArray;
  I, NextIndex: Integer;
  OwnedArray: Boolean;
Begin
  SetLength(Images, 0);
  ErrorText := '';
  Result := False;
  Data := Nil;
  Arr := Nil;
  OwnedArray := False;
  Try
    Try
      Data := GetJSON(ResponseJson);
    Except
      On E: Exception Do
        Begin
          ErrorText := 'Generated image response is not valid JSON.';
          Exit;
        End;
    End;
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'Generated image response is not valid JSON.';
        Exit;
      End;
    Root := TJSONObject(Data);
    Arr := OutputArray(Root);
    OwnedArray := Assigned(Arr) And (Root.Find('output') = Nil);
    If Not Assigned(Arr) Then
      Exit(True);
    NextIndex := 1;
    For I := 0 To Arr.Count - 1 Do
      Begin
        If Not (Arr.Items[I] Is TJSONObject) Then
          Continue;
        Item := TJSONObject(Arr.Items[I]);
        If Item.Get('type', '') <> 'image_generation_call' Then
          Continue;
        If Item.Get('result', '') = '' Then
          Begin
            ErrorText := 'Generated image response has no bytes.';
            SetLength(Images, 0);
            Exit(False);
          End;
        If Not AppendDecoded(Item.Get('id', ''), Item.Get('result', ''), NextIndex, Images, ErrorText) Then
          Begin
            SetLength(Images, 0);
            Exit(False);
          End;
        Inc(NextIndex);
      End;
    Result := True;
  Finally
    If OwnedArray Then
      Arr.Free;
    Data.Free;
  End;
End;

Function TImagesEndpointAdapter.AdapterId: String;
Begin
  Result := AssistantImageAdapterImages;
End;

Function TImagesEndpointAdapter.Collect(Const ResponseJson: String; Out Images: TAssistantGeneratedImageArray;
  Out ErrorText: String): Boolean;
Var
  Data: TJSONData;
  Root, Item: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  Encoded: String;
Begin
  SetLength(Images, 0);
  ErrorText := '';
  Result := False;
  Data := Nil;
  Try
    Try
      Data := GetJSON(ResponseJson);
    Except
      On E: Exception Do
        Begin
          ErrorText := 'Generated image response is not valid JSON.';
          Exit;
        End;
    End;
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'Generated image response is not valid JSON.';
        Exit;
      End;
    Root := TJSONObject(Data);
    If Not (Root.Find('data') Is TJSONArray) Then
      Exit(True);
    Arr := TJSONArray(Root.Find('data'));
    For I := 0 To Arr.Count - 1 Do
      Begin
        If Not (Arr.Items[I] Is TJSONObject) Then
          Continue;
        Item := TJSONObject(Arr.Items[I]);
        Encoded := Item.Get('b64_json', '');
        If Encoded = '' Then
          Begin
            If Item.Get('url', '') <> '' Then
              ErrorText := 'Generated image response has no bytes.'
            Else
              Continue;
            SetLength(Images, 0);
            Exit(False);
          End;
        If Not AppendDecoded(Item.Get('id', ''), Encoded, I + 1, Images, ErrorText) Then
          Begin
            SetLength(Images, 0);
            Exit(False);
          End;
      End;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function PartPayload(Part: TJSONObject; Out Encoded, PartId: String; Out NeedsBytes: Boolean): Boolean;
Var
  Source, UrlObj: TJSONObject;
  UrlNode: TJSONData;
Begin
  Encoded := '';
  PartId := Part.Get('id', '');
  NeedsBytes := False;
  Result := False;
  If Part.Get('type', '') = 'image_url' Then
    Begin
      UrlNode := Part.Find('image_url');
      If UrlNode Is TJSONObject Then
        Begin
          UrlObj := TJSONObject(UrlNode);
          Encoded := UrlObj.Get('url', '');
        End
      Else If Assigned(UrlNode) And (UrlNode.JSONType = jtString) Then
        Encoded := UrlNode.AsString;
      NeedsBytes := (Encoded <> '') And (Pos('base64', LowerCase(Encoded)) = 0);
      Result := Pos('base64', LowerCase(Encoded)) > 0;
      Exit;
    End;
  If Part.Get('type', '') <> 'image' Then
    Exit;
  If Not (Part.Find('source') Is TJSONObject) Then
    Exit;
  Source := TJSONObject(Part.Find('source'));
  If Source.Get('type', '') = 'url' Then
    Begin
      NeedsBytes := True;
      Exit;
    End;
  If Source.Get('type', '') <> 'base64' Then
    Exit;
  Encoded := Source.Get('data', '');
  NeedsBytes := Encoded = '';
  Result := Encoded <> '';
End;

Function TChatCompletionsImageAdapter.AdapterId: String;
Begin
  Result := AssistantImageAdapterChat;
End;

Function TChatCompletionsImageAdapter.Collect(Const ResponseJson: String;
  Out Images: TAssistantGeneratedImageArray; Out ErrorText: String): Boolean;
Var
  Data: TJSONData;
  Root, Choice, MessageObj, Part: TJSONObject;
  Choices, Content: TJSONArray;
  I, J, NextIndex: Integer;
  Encoded, PartId: String;
  NeedsBytes: Boolean;
Begin
  SetLength(Images, 0);
  ErrorText := '';
  Result := False;
  Data := Nil;
  Try
    Try
      Data := GetJSON(ResponseJson);
    Except
      On E: Exception Do
        Begin
          ErrorText := 'Generated image response is not valid JSON.';
          Exit;
        End;
    End;
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'Generated image response is not valid JSON.';
        Exit;
      End;
    Root := TJSONObject(Data);
    If Not (Root.Find('choices') Is TJSONArray) Then
      Exit(True);
    Choices := TJSONArray(Root.Find('choices'));
    NextIndex := 1;
    For I := 0 To Choices.Count - 1 Do
      Begin
        If Not (Choices.Items[I] Is TJSONObject) Then
          Continue;
        Choice := TJSONObject(Choices.Items[I]);
        If Not (Choice.Find('message') Is TJSONObject) Then
          Continue;
        MessageObj := TJSONObject(Choice.Find('message'));
        If Not (MessageObj.Find('content') Is TJSONArray) Then
          Continue;
        Content := TJSONArray(MessageObj.Find('content'));
        For J := 0 To Content.Count - 1 Do
          Begin
            If Not (Content.Items[J] Is TJSONObject) Then
              Continue;
            Part := TJSONObject(Content.Items[J]);
            If Not PartPayload(Part, Encoded, PartId, NeedsBytes) Then
              Begin
                If NeedsBytes Then
                  Begin
                    ErrorText := 'Generated image response has no bytes.';
                    SetLength(Images, 0);
                    Exit(False);
                  End;
                Continue;
              End;
            If Not AppendDecoded(PartId, Encoded, NextIndex, Images, ErrorText) Then
              Begin
                SetLength(Images, 0);
                Exit(False);
              End;
            Inc(NextIndex);
          End;
      End;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Procedure SetGeneratedImagePost(Post: TGeneratedImagePost);
Begin
  ImagePost := Post;
End;

Function PixelSizeAccepted(Const Size: String): Boolean;
Var
  I: Integer;
Begin
  Result := Size <> '';
  For I := 1 To Length(Size) Do
    If Not (Size[I] In ['0'..'9', 'x', 'X']) Then
      Exit(False);
End;

Function ImageEndpointUrl(Const ApiBase: String): String;
Begin
  Result := Trim(ApiBase);
  While (Result <> '') And (Result[Length(Result)] = '/') Do
    Delete(Result, Length(Result), 1);
  Result := Result + '/images/generations';
End;

Function GrokAspectRatio(Const Shape: String): String;
Const
  Ratios: Array[0..15] Of String = (
    '1:1', '16:9', '9:16', '4:3', '3:4', '3:2', '2:3', '2:1', '1:2',
    '19.5:9', '9:19.5', '20:9', '9:20', '21:9', '5:2', 'auto');
Var
  I: Integer;
  Trimmed: String;
Begin
  Result := '';
  Trimmed := LowerCase(Trim(Shape));
  For I := Low(Ratios) To High(Ratios) Do
    If Trimmed = Ratios[I] Then
      Exit(Ratios[I]);
End;

Procedure AddCommonImageFields(Body: TJSONObject; Const ImageModel, Prompt: String);
Begin
  Body.Add('model', ImageModel);
  Body.Add('prompt', Prompt);
  Body.Add('n', 1);
  Body.Add('response_format', 'b64_json');
End;

Function BuildGrokImageBody(Const ImageModel, Prompt, Shape: String): String;
Var
  Body: TJSONObject;
  Ratio: String;
Begin
  Body := TJSONObject.Create;
  Try
    AddCommonImageFields(Body, ImageModel, Prompt);
    Ratio := GrokAspectRatio(Shape);
    If Ratio <> '' Then
      Body.Add('aspect_ratio', Ratio);
    Result := Body.AsJSON;
  Finally
    Body.Free;
  End;
End;

Function BuildCompatibleImageBody(Const ImageModel, Prompt, Shape: String): String;
Var
  Body: TJSONObject;
  PixelSize: String;
Begin
  Body := TJSONObject.Create;
  Try
    AddCommonImageFields(Body, ImageModel, Prompt);
    PixelSize := Trim(Shape);
    If PixelSizeAccepted(PixelSize) Then
      Body.Add('size', PixelSize);
    Result := Body.AsJSON;
  Finally
    Body.Free;
  End;
End;

Function ProfileImageUrl(Const Profile: TAssistantProfileCall): String;
Var
  Base: String;
Begin
  Base := Trim(Profile.ApiBase);
  If (Base = '') And (Profile.Backend = 'grok') Then
    Base := AssistantConfigDefaultApiBase;
  Result := ImageEndpointUrl(Base);
End;

Function ProfileBearer(Const Profile: TAssistantProfileCall; Out Token, ErrorText: String): Boolean;
Var
  Provider: IAssistantModelProvider;
Begin
  Token := '';
  ErrorText := '';
  { A test post hook may supply the bearer so the fixture does not sign in. }
  If Assigned(ImagePost) And (Trim(Profile.KeyValue) <> '') And (Pos(#10, Profile.KeyValue) = 0) And
    (Pos(#13, Profile.KeyValue) = 0) Then
    Begin
      Token := Profile.KeyValue;
      Result := True;
      Exit;
    End;
  If Profile.Backend = 'grok' Then
    Begin
      Provider := CreateXaiModelProvider;
      Result := Provider.GetAccessToken(False, Token, ErrorText);
      Exit;
    End;
  If Profile.KeySource = 'stored' Then
    Token := Profile.KeyValue
  Else
    Token := GetEnvironmentVariable(Profile.KeyEnv);
  Result := (Token <> '') And (Pos(#10, Token) = 0) And (Pos(#13, Token) = 0);
  If Not Result Then
    ErrorText := 'This profile has no API key for its image endpoint.';
End;

Function RequestProfileImage(Const Prompt, Shape: String; Out Image: TAssistantGeneratedImage;
  Out ErrorText: String): Boolean;
Var
  Profile: TAssistantProfileCall;
  Images: TAssistantGeneratedImageArray;
  Url, Body, Headers, Token, ResponseBody: String;
  StatusCode: Integer;
  Posted: Boolean;
Begin
  ClearGeneratedImage(Image);
  ErrorText := '';
  Result := False;
  SetLength(Images, 0);
  If Trim(Prompt) = '' Then
    Begin
      ErrorText := 'write_image requires a prompt.';
      Exit;
    End;
  If Not ReadActiveProfileCall(Profile) Then
    Begin
      ErrorText := 'No profile is selected.';
      Exit;
    End;
  If Not AssistantBackendCanDraw(Profile.Backend) Then
    Begin
      ErrorText := 'This connection has no image endpoint.';
      Exit;
    End;
  If Trim(Profile.ImageModel) = '' Then
    Begin
      ErrorText := 'No image model is set.';
      Exit;
    End;
  Url := ProfileImageUrl(Profile);
  If Not UrlIsHttps(Url) Then
    Begin
      ErrorText := 'This profile has no image endpoint.';
      Exit;
    End;
  If Not ProfileBearer(Profile, Token, ErrorText) Then
    Exit;
  If Profile.Backend = 'grok' Then
    Body := BuildGrokImageBody(Profile.ImageModel, Prompt, Shape)
  Else If Profile.Backend = 'openai-compatible' Then
    Body := BuildCompatibleImageBody(Profile.ImageModel, Prompt, Shape)
  Else
    Begin
      ErrorText := 'This connection has no image endpoint.';
      Exit;
    End;
  Headers := 'Authorization: Bearer ' + Token;
  If Profile.Preset = 'openrouter' Then
    Headers := Headers + LineEnding + 'X-Title: LazWorkflow';
  StatusCode := 0;
  ResponseBody := '';
  If Assigned(ImagePost) Then
    Posted := ImagePost(Url, Body, Headers, ResponseBody, StatusCode, ErrorText)
  Else
    Posted := HttpsPostJson(Url, Body, Headers, ResponseBody, StatusCode, ErrorText,
      AssistantImagePostTimeoutMs);
  If Not Posted Or (StatusCode < 200) Or (StatusCode >= 300) Then
    Begin
      If ErrorText = '' Then
        ErrorText := 'Image endpoint returned HTTP ' + IntToStr(StatusCode) + '.';
      Exit;
    End;
  If Not CollectGeneratedImages(AssistantImageAdapterImages, ResponseBody, Images, ErrorText) Then
    Exit;
  If Length(Images) <> 1 Then
    Begin
      ErrorText := 'The image endpoint did not return one image.';
      Exit;
    End;
  Image := Images[0];
  Result := True;
End;

Procedure RememberResponseImages(Const OutputJson: String);
Var
  Images: TAssistantGeneratedImageArray;
  ErrorText, Body: String;
Begin
  If Trim(OutputJson) = '' Then
    Exit;
  If Trim(OutputJson)[1] = '[' Then
    Body := '{"output":' + OutputJson + '}'
  Else
    Body := OutputJson;
  If CollectGeneratedImages(AssistantImageAdapterResponses, Body, Images, ErrorText) And (Length(Images) > 0) Then
    SetTurnGeneratedImages(Images);
End;

Procedure RegisterBuiltinImageAdapters;
Begin
  RegisterGeneratedImageAdapter(TResponsesImageAdapter.Create);
  RegisterGeneratedImageAdapter(TImagesEndpointAdapter.Create);
  RegisterGeneratedImageAdapter(TChatCompletionsImageAdapter.Create);
End;

Initialization

RegisterBuiltinImageAdapters;

End.
