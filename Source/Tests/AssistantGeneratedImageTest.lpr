Program AssistantGeneratedImageTest;

{ Fixture checks for the generated-image record. No live provider. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, base64, fpjson, jsonparser, AssistantGeneratedImage, AssistantImageAdapters,
  AssistantConnections, WorkflowSettings;

Const
  OnePixelPng: Array[0..66] Of Byte = (
    $89, $50, $4E, $47, $0D, $0A, $1A, $0A, $00, $00, $00, $0D, $49, $48, $44, $52,
    $00, $00, $00, $01, $00, $00, $00, $01, $08, $06, $00, $00, $00, $1F, $15, $C4,
    $89, $00, $00, $00, $0A, $49, $44, $41, $54, $78, $9C, $63, $00, $01, $00, $00,
    $05, $00, $01, $0D, $0A, $2D, $B4, $00, $00, $00, $00, $49, $45, $4E, $44, $AE,
    $42, $60, $82);

Procedure Check(Const Name: String; OK: Boolean);
Begin
  If Not OK Then
    Begin
      WriteLn('FAIL ', Name);
      Halt(1);
    End;
  WriteLn('ok   ', Name);
End;

Function PngBytes: TBytes;
Var
  I: Integer;
Begin
  SetLength(Result, Length(OnePixelPng));
  For I := 0 To High(OnePixelPng) Do
    Result[I] := OnePixelPng[I];
End;

Function PngBase64: String;
Var
  Raw: RawByteString;
  I: Integer;
  Data: TBytes;
Begin
  Data := PngBytes;
  SetLength(Raw, Length(Data));
  For I := 0 To High(Data) Do
    Raw[I + 1] := AnsiChar(Data[I]);
  Result := EncodeStringBase64(Raw);
  Result := StringReplace(Result, #10, '', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '', [rfReplaceAll]);
End;

Function SameBytes(Const Left, Right: TBytes): Boolean;
Var
  I: Integer;
Begin
  Result := Length(Left) = Length(Right);
  If Not Result Then
    Exit;
  For I := 0 To High(Left) Do
    If Left[I] <> Right[I] Then
      Exit(False);
End;

Procedure ExpectOne(Const Title, AdapterId, Body, WantedId: String);
Var
  Images: TAssistantGeneratedImageArray;
  ErrorText, ResultText: String;
Begin
  SetLength(Images, 0);
  Check(Title + ' collects', CollectGeneratedImages(AdapterId, Body, Images, ErrorText) And (ErrorText = '') And
    (Length(Images) = 1));
  Check(Title + ' record matches the bytes',
    (Images[0].Id = WantedId) And (Images[0].Mime = 'image/png') And (Images[0].Width = 1) And
    (Images[0].Height = 1) And SameBytes(Images[0].Bytes, PngBytes) And
    GeneratedImageBytesAccepted(Images[0], ErrorText));
  ResultText := GeneratedImageResultText('icons/dot.png', Images[0]);
  Check(Title + ' result uses only the record',
    (Pos('path=icons/dot.png', ResultText) > 0) And (Pos('bytes=' + IntToStr(Length(PngBytes)), ResultText) > 0) And
    (Pos('width=1', ResultText) > 0) And (Pos('height=1', ResultText) > 0) And
    (Pos('mime=image/png', ResultText) > 0) And (Pos('id=' + WantedId, ResultText) > 0) And
    (Pos('b64', ResultText) = 0) And (Pos('grok', LowerCase(ResultText)) = 0) And
    (Pos('openai', LowerCase(ResultText)) = 0));
End;

Procedure TestProfileEndpoint;
Var
  Root, SeenUrl, SeenBody, ErrorText: String;
  Store: TAssistantConnections;
  Item: TAssistantConnection;
  Image: TAssistantGeneratedImage;
  BodyObj: TJSONObject;
  Data: TJSONData;
  Function FakePost(Const Url, Body, Headers: String; Out ResponseBody: String; Out StatusCode: Integer;
    Out PostError: String): Boolean;
  Begin
    SeenUrl := Url;
    SeenBody := Body;
    PostError := '';
    StatusCode := 200;
    ResponseBody := '{"data":[{"b64_json":"' + PngBase64 + '"}]}';
    Result := Pos('Bearer test-key', Headers) > 0;
  End;
Begin
  Root := GetTempDir + 'laz-image-endpoint-' + IntToStr(Random(100000));
  ForceDirectories(Root);
  SetWorkflowSettingsDirectory(Root);
  SetGeneratedImagePost(@FakePost);
  Store := TAssistantConnections.Create(Root);
  Data := Nil;
  Try
    Item := Store.AddStored('endpoint', 'Endpoint', 'openai-compatible');
    Item.Model := 'kept-chat-model';
    Item.ApiBase := 'https://example.invalid/v1';
    Item.KeySource := 'stored';
    Item.KeyValue := 'test-key';
    Item.ImageOutput := True;
    Item.ImageDelivery := aidToolPrompt;
    Store.ActiveId := Item.Id;
    Check('profile saves', Store.Save);
    Check('tool-prompt calls this profile endpoint',
      RequestProfileImage('a dot', '1024x1024', Image, ErrorText) And (ErrorText = '') And
      (Image.Mime = 'image/png') And (Image.Width = 1));
    Check('endpoint is this profile, not another image product',
      (SeenUrl = 'https://example.invalid/v1/images/generations') And
      (Pos('grok-imagine', LowerCase(SeenBody)) = 0) And (Pos('dall-e', LowerCase(SeenBody)) = 0));
    Data := GetJSON(SeenBody);
    Check('request body uses the selected model', Data Is TJSONObject);
    If Data Is TJSONObject Then
      Begin
        BodyObj := TJSONObject(Data);
        Check('model and size stay on this profile',
          (BodyObj.Get('model', '') = 'kept-chat-model') And (BodyObj.Get('size', '') = '1024x1024') And
          (BodyObj.Get('prompt', '') = 'a dot'));
      End;
    Check('the endpoint call writes nothing',
      Not FileExists(IncludeTrailingPathDelimiter(Root) + 'icons' + PathDelim + 'dot.png'));
  Finally
    Data.Free;
    SetGeneratedImagePost(Nil);
    Store.Free;
    SetWorkflowSettingsDirectory('');
  End;
End;

Var
  Images: TAssistantGeneratedImageArray;
  ErrorText, Encoded, Body: String;
Begin
  Encoded := PngBase64;
  Check('responses adapter is registered for a grok profile',
    ProfileImageAdapterId('grok', AssistantImageDeliveryResponsePart) = AssistantImageAdapterResponses);
  Check('images adapter is registered for tool prompt without a model id',
    (ProfileImageAdapterId('grok', AssistantImageDeliveryToolPrompt) = AssistantImageAdapterImages) And
    (ProfileImageAdapterId('openai-compatible', AssistantImageDeliveryToolPrompt) = AssistantImageAdapterImages));
  Check('chat adapter is the compatible response part',
    ProfileImageAdapterId('openai-compatible', AssistantImageDeliveryResponsePart) = AssistantImageAdapterChat);
  ExpectOne('responses call', AssistantImageAdapterResponses,
    '{"output":[{"id":"ig_turn","type":"image_generation_call","status":"completed","result":"' + Encoded + '"}]}',
    'ig_turn');
  ExpectOne('images endpoint', AssistantImageAdapterImages,
    '{"data":[{"b64_json":"' + Encoded + '"}]}', 'img-1');
  ExpectOne('chat data uri', AssistantImageAdapterChat,
    '{"choices":[{"message":{"content":[{"type":"image_url","image_url":{"url":"data:image/png;base64,' +
    Encoded + '"}}]}}]}', 'img-1');
  Body := '{"output":[{"type":"message","content":[{"type":"output_text","text":"No pixels."}]}]}';
  Check('text response does not invent an image',
    CollectGeneratedImages(AssistantImageAdapterResponses, Body, Images, ErrorText) And (Length(Images) = 0));
  Check('url-only image response has no bytes',
    (Not CollectGeneratedImages(AssistantImageAdapterImages,
    '{"data":[{"url":"https://example.invalid/dot.png","mime_type":"image/png"}]}', Images, ErrorText)) And
    (Length(Images) = 0) And (Pos('no bytes', ErrorText) > 0));
  Check('unknown profile has no adapter and no new tool',
    (Not CollectGeneratedImages('codex', '{"output":[]}', Images, ErrorText)) And (Length(Images) = 0) And
    (Pos('write_image', ErrorText) = 0));
  TestProfileEndpoint;
  WriteLn('AssistantGeneratedImageTest passed');
End.
