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
  Posts: Integer;
  Store: TAssistantConnections;
  Item: TAssistantConnection;
  Image: TAssistantGeneratedImage;
  BodyObj: TJSONObject;
  Data: TJSONData;
  Function FakePost(Const Url, Body, Headers: String; Out ResponseBody: String; Out StatusCode: Integer;
    Out PostError: String): Boolean;
  Begin
    Inc(Posts);
    SeenUrl := Url;
    SeenBody := Body;
    PostError := '';
    StatusCode := 200;
    ResponseBody := '{"data":[{"b64_json":"' + PngBase64 + '"}]}';
    Result := Pos('Bearer test-key', Headers) > 0;
  End;
  Function BodyField(Const Name, Expected: String): Boolean;
  Begin
    Result := False;
    Data.Free;
    Data := GetJSON(SeenBody);
    If Not (Data Is TJSONObject) Then
      Exit;
    BodyObj := TJSONObject(Data);
    Result := BodyObj.Get(Name, '') = Expected;
  End;
Begin
  Root := GetTempDir + 'laz-image-endpoint-' + IntToStr(Random(100000));
  ForceDirectories(Root);
  SetWorkflowSettingsDirectory(Root);
  SetGeneratedImagePost(@FakePost);
  Store := TAssistantConnections.Create(Root);
  Data := Nil;
  Posts := 0;
  Try
    Item := Store.AddStored('endpoint', 'Endpoint', 'openai-compatible');
    Item.Model := 'kept-chat-model';
    Item.ImageModel := 'gpt-image-1';
    Item.ApiBase := 'https://example.invalid/v1';
    Item.KeySource := 'stored';
    Item.KeyValue := 'test-key';
    Item.ImageOutput := True;
    Store.ActiveId := Item.Id;
    Check('profile saves', Store.Save);
    Check('compatible builder posts the image model and a known pixel size',
      RequestProfileImage('a dot', '1024x1024', Image, ErrorText) And (ErrorText = '') And
      (Image.Mime = 'image/png') And (Posts = 1) And
      (SeenUrl = 'https://example.invalid/v1/images/generations'));
    Check('compatible body has no aspect ratio and does not use the chat model',
      BodyField('model', 'gpt-image-1') And BodyField('size', '1024x1024') And BodyField('prompt', 'a dot') And
      BodyField('response_format', 'b64_json') And (TJSONObject(Data).Get('n', 0) = 1) And
      (Pos('aspect_ratio', SeenBody) = 0) And (Pos('quality', SeenBody) = 0) And
      (Pos('kept-chat-model', SeenBody) = 0));
    Posts := 0;
    Check('a ratio the compatible builder cannot express is omitted',
      RequestProfileImage('a dot', '16:9', Image, ErrorText) And (ErrorText = '') And (Posts = 1) And
      (Pos('aspect_ratio', SeenBody) = 0) And (Pos('"size"', SeenBody) = 0) And
      BodyField('model', 'gpt-image-1'));
    Item.ApiBase := 'http://example.invalid/v1';
    Store.Save;
    Posts := 0;
    Check('a non-HTTPS endpoint fails before the post',
      (Not RequestProfileImage('a dot', '1:1', Image, ErrorText)) And
      (Pos('image endpoint', ErrorText) > 0) And (Posts = 0));
    Item.ApiBase := 'https://example.invalid/v1';
    Store.Save;
    Item.ImageModel := '';
    Store.Save;
    Posts := 0;
    Check('an empty image model fails before the post',
      (Not RequestProfileImage('a dot', '1:1', Image, ErrorText)) And (Pos('image model', ErrorText) > 0) And
      (Posts = 0));
    Item := Store.AddStored('grok-draw', 'Grok draw', 'grok');
    Item.Model := 'kept-chat-model';
    Item.ImageModel := AssistantGrokImageModel;
    Item.ApiBase := 'https://api.x.ai/v1';
    Item.KeyValue := 'test-key';
    Item.ImageOutput := True;
    Store.ActiveId := Item.Id;
    Store.Save;
    Posts := 0;
    Check('Grok builder posts a documented ratio and not a pixel size',
      RequestProfileImage('a tree', '16:9', Image, ErrorText) And (ErrorText = '') And (Posts = 1) And
      (SeenUrl = 'https://api.x.ai/v1/images/generations') And
      BodyField('model', AssistantGrokImageModel) And BodyField('aspect_ratio', '16:9') And
      BodyField('prompt', 'a tree') And (TJSONObject(Data).Get('n', 0) = 1) And
      (Pos('"size"', SeenBody) = 0) And (Pos('quality', SeenBody) = 0) And
      (Pos('kept-chat-model', SeenBody) = 0));
    Posts := 0;
    Check('a pixel size the Grok builder cannot express is omitted',
      RequestProfileImage('a tree', '1024x1024', Image, ErrorText) And (ErrorText = '') And (Posts = 1) And
      (Pos('"size"', SeenBody) = 0) And (Pos('aspect_ratio', SeenBody) = 0) And
      BodyField('model', AssistantGrokImageModel));
    Item := Store.AddStored('codex-draw', 'Codex draw', 'codex');
    Item.Model := 'codex-model';
    Item.ImageModel := 'should-not-post';
    Item.ImageOutput := True;
    Store.ActiveId := Item.Id;
    Store.Save;
    Posts := 0;
    Check('Codex fails before any post',
      (Not RequestProfileImage('a dot', '1:1', Image, ErrorText)) And
      (Pos('no image endpoint', ErrorText) > 0) And (Posts = 0));
    Item := Store.AddStored('claude-draw', 'Claude draw', 'claude');
    Item.Model := 'claude-model';
    Item.ImageOutput := True;
    Store.ActiveId := Item.Id;
    Store.Save;
    Posts := 0;
    Check('Claude fails before any post',
      (Not RequestProfileImage('a dot', '', Image, ErrorText)) And
      (Pos('no image endpoint', ErrorText) > 0) And (Posts = 0));
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
  Check('image post is bounded to about a minute', AssistantImagePostTimeoutMs = 60000);
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
