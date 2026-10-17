Program AssistantWriteImageTest;

{ Fixture coverage for write_image. No live provider.

  Flag off: the tool is absent and a call is unknown. Flag on: the schema
  requires prompt, has optional shape, and has no image_id. A Grok mock posts
  grok-imagine-image-2.0 and writes a fixture PNG. An OpenAI-compatible mock
  posts a different image model. Claude and Codex do not post. Path escape, a
  symlink out of the project, bad magic, overwrite without the flag, a missing
  prompt, a missing image model, and Plan or Document calls are refused. An
  inapplicable shape is omitted. A missing extension, or one that does not
  match the bytes, still writes the sniffed format. A second call after a
  failed draw does not post. A subagent tool list has no write_image.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  BaseUnix,
  {$ENDIF}
  Interfaces, Classes, SysUtils, base64, fpimage, fpwritejpeg, fpjson, jsonparser,
  AssistantConfig, AssistantConnections, AssistantConversation,
  AssistantHarness, AssistantImageAdapters, AssistantImages, AssistantTools, AssistantWorkTarget,
  WorkflowSettings;

Const
  OnePixelPng: Array[0..66] Of Byte = (
    $89, $50, $4E, $47, $0D, $0A, $1A, $0A, $00, $00, $00, $0D, $49, $48, $44, $52,
    $00, $00, $00, $01, $00, $00, $00, $01, $08, $06, $00, $00, $00, $1F, $15, $C4,
    $89, $00, $00, $00, $0A, $49, $44, $41, $54, $78, $9C, $63, $00, $01, $00, $00,
    $05, $00, $01, $0D, $0A, $2D, $B4, $00, $00, $00, $00, $49, $45, $4E, $44, $AE,
    $42, $60, $82);
  ChatModel = 'kept-chat-model';
  OtherImageModel = 'gpt-image-1';

Var
  MockCalls: Integer;
  SeenUrl, SeenBody, SeenHeaders, MockResponse: String;
  LastRefs: TAssistantImageRefArray;

Procedure Check(Const Name: String; OK: Boolean);
Begin
  If Not OK Then
    Begin
      WriteLn('FAIL ', Name);
      Halt(1);
    End;
  WriteLn('ok   ', Name);
End;

Procedure CheckNoted(Const Name, Note: String; OK: Boolean);
Begin
  If OK Then
    Check(Name, True)
  Else
    Check(Name + ' [' + Note + ']', False);
End;

Function PngBytes: TBytes;
Var
  I: Integer;
Begin
  SetLength(Result, Length(OnePixelPng));
  For I := 0 To High(OnePixelPng) Do
    Result[I] := OnePixelPng[I];
End;

Function EncodeBytes(Const Data: TBytes): String;
Var
  Raw: RawByteString;
  I: Integer;
Begin
  SetLength(Raw, Length(Data));
  For I := 0 To High(Data) Do
    Raw[I + 1] := AnsiChar(Data[I]);
  Result := EncodeStringBase64(Raw);
  Result := StringReplace(Result, #10, '', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '', [rfReplaceAll]);
End;

Function PngBase64: String;
Begin
  Result := EncodeBytes(PngBytes);
End;

Function PngResponse: String;
Begin
  Result := '{"data":[{"b64_json":"' + PngBase64 + '"}]}';
End;

Var
  CachedJpeg: TBytes;

Function JpegBytes: TBytes;
Var
  Img: TFPMemoryImage;
  Writer: TFPWriterJPEG;
  Stream: TBytesStream;
Begin
  If Length(CachedJpeg) = 0 Then
    Begin
      Img := TFPMemoryImage.Create(1, 1);
      Writer := TFPWriterJPEG.Create;
      Stream := TBytesStream.Create;
      Try
        Img.Colors[0, 0] := FPColor($FFFF, $8000, $0000, $FFFF);
        Writer.CompressionQuality := 80;
        Img.SaveToStream(Stream, Writer);
        CachedJpeg := Copy(Stream.Bytes, 0, Stream.Size);
      Finally
        Stream.Free;
        Writer.Free;
        Img.Free;
      End;
    End;
  Result := CachedJpeg;
End;

Function JpegResponse: String;
Begin
  Result := '{"data":[{"b64_json":"' + EncodeBytes(JpegBytes) + '"}]}';
End;

Function BadMagicResponse: String;
Var
  Data: TBytes;
  I: Integer;
Begin
  SetLength(Data, 8);
  For I := 0 To 7 Do
    Data[I] := I + 1;
  Result := '{"data":[{"b64_json":"' + EncodeBytes(Data) + '"}]}';
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

Function ReadBytes(Const Path: String): TBytes;
Var
  Stream: TFileStream;
Begin
  SetLength(Result, 0);
  Stream := TFileStream.Create(Path, fmOpenRead);
  Try
    SetLength(Result, Stream.Size);
    If Stream.Size > 0 Then
      Stream.ReadBuffer(Result[0], Stream.Size);
  Finally
    Stream.Free;
  End;
End;

Procedure WriteText(Const Path, Body: String);
Var
  Stream: TFileStream;
Begin
  Stream := TFileStream.Create(Path, fmCreate);
  Try
    If Body <> '' Then
      Stream.WriteBuffer(Body[1], Length(Body));
  Finally
    Stream.Free;
  End;
End;

Function ReadText(Const Path: String): String;
Var
  Data: TBytes;
  I: Integer;
Begin
  Data := ReadBytes(Path);
  SetLength(Result, Length(Data));
  For I := 0 To High(Data) Do
    Result[I + 1] := AnsiChar(Data[I]);
End;

Function FindFrom(Const Source, Needle: String; FromIndex: Integer): Integer;
Var
  At: Integer;
Begin
  Result := 0;
  If (Needle = '') Or (FromIndex < 1) Or (FromIndex > Length(Source)) Then
    Exit;
  At := Pos(Needle, Copy(Source, FromIndex, MaxInt));
  If At > 0 Then
    Result := FromIndex + At - 1;
End;

Function CountText(Const Source, Needle: String): Integer;
Var
  At: Integer;
Begin
  Result := 0;
  At := FindFrom(Source, Needle, 1);
  While At > 0 Do
    Begin
      Inc(Result);
      At := FindFrom(Source, Needle, At + Length(Needle));
    End;
End;

Function IdentChar(C: Char): Boolean;
Begin
  Result := C In ['a'..'z', '0'..'9', '_'];
End;

Function ContainsToken(Const Source, Token: String): Boolean;
Var
  Lowered, Probe: String;
  At: Integer;
  BeforeOk, AfterOk: Boolean;
Begin
  Result := False;
  Lowered := LowerCase(Source);
  Probe := LowerCase(Token);
  At := FindFrom(Lowered, Probe, 1);
  While At > 0 Do
    Begin
      BeforeOk := (At = 1) Or Else (Not IdentChar(Lowered[At - 1]));
      AfterOk := (At + Length(Probe) > Length(Lowered)) Or Else (Not IdentChar(Lowered[At + Length(Probe)]));
      If BeforeOk And AfterOk Then
        Exit(True);
      At := FindFrom(Lowered, Probe, At + 1);
    End;
End;

Function ProviderNamed(Const Source: String): String;
Const
  Names: Array[0..9] Of String = (
    'grok', 'openai', 'xai', 'anthropic', 'claude', 'gemini', 'openrouter', 'dall-e', 'dalle', 'codex');
Var
  I: Integer;
Begin
  Result := '';
  For I := Low(Names) To High(Names) Do
    If ContainsToken(Source, Names[I]) Then
      Exit(Names[I]);
End;

Function LoadText(Const Path: String): String;
Var
  Lines: TStringList;
Begin
  Lines := TStringList.Create;
  Try
    Lines.LoadFromFile(Path);
    Result := Lines.Text;
  Finally
    Lines.Free;
  End;
End;

Function UpToRepo(Start: String): String;
Var
  Marker: String;
Begin
  Result := '';
  Start := ExcludeTrailingPathDelimiter(ExpandFileName(Start));
  While Start <> '' Do
    Begin
      Marker := IncludeTrailingPathDelimiter(Start) + 'Source' + PathDelim + 'LazAssistantTools' + PathDelim +
        'AssistantTools.pas';
      If FileExists(Marker) Then
        Exit(Start);
      If ExtractFileDir(Start) = Start Then
        Break;
      Start := ExtractFileDir(Start);
    End;
End;

Function RepoRoot: String;
Begin
  Result := UpToRepo(GetCurrentDir);
  If Result = '' Then
    Result := UpToRepo(ExtractFilePath(ParamStr(0)));
End;

Function WriterSlice(Const Source: String): String;
Var
  StartAt, ToolAt, NextAt: Integer;
Begin
  StartAt := Pos('Function ImageProjectRelative(', Source);
  If StartAt = 0 Then
    StartAt := Pos('Function PublishImageBytes(', Source);
  ToolAt := Pos('Function ToolWriteImage(', Source);
  If (StartAt = 0) Or (ToolAt < StartAt) Then
    Exit('');
  NextAt := FindFrom(Source, 'Function ', ToolAt + 1);
  If NextAt = 0 Then
    Result := Copy(Source, StartAt, MaxInt)
  Else
    Result := Copy(Source, StartAt, NextAt - StartAt);
End;

Function ImageToolSlice(Const ToolsJson: String): String;
Var
  StartAt, NextTool: Integer;
  Tail: String;
Begin
  StartAt := Pos('"name":"write_image"', ToolsJson);
  If StartAt = 0 Then
    Exit('');
  Tail := Copy(ToolsJson, StartAt + 1, MaxInt);
  NextTool := Pos('{"type":"function"', Tail);
  If NextTool = 0 Then
    Result := Copy(ToolsJson, StartAt, MaxInt)
  Else
    Result := Copy(ToolsJson, StartAt, NextTool);
End;

Procedure TestSharedWriter(Const UnitDir: String);
Var
  Info: TSearchRec;
  Path, Body, Slice, Named, AdapterBody, RecordBody: String;
  DefinitionCount, CallCount: Integer;
Begin
  DefinitionCount := 0;
  CallCount := 0;
  Slice := '';
  If FindFirst(IncludeTrailingPathDelimiter(UnitDir) + '*.pas', faAnyFile, Info) = 0 Then
    Begin
      Try
        Repeat
          If (Info.Attr And faDirectory) <> 0 Then
            Continue;
          Path := IncludeTrailingPathDelimiter(UnitDir) + Info.Name;
          Body := LoadText(Path);
          If Pos('Function PublishImageBytes(', Body) > 0 Then
            Begin
              Inc(DefinitionCount);
              Slice := WriterSlice(Body);
            End;
          CallCount := CallCount + CountText(Body, 'PublishImageBytes(');
        Until FindNext(Info) <> 0;
      Finally
        FindClose(Info);
      End;
    End;
  Check('one writer publishes the drawn bytes',
    (DefinitionCount = 1) And (CallCount = 2) And (Slice <> '') And
    (Pos('Function ToolWriteImage(', Slice) > 0) And (Pos('RequestProfileImage(', Slice) > 0) And
    (Pos('SelectTurnGeneratedImage(', Slice) = 0) And (Pos('image_id', Slice) = 0) And
    (Pos('ActiveProfileImageDelivery', Slice) = 0) And (CountText(Slice, 'PublishImageBytes(') = 2) And
    (Pos('HttpsPostJson', Slice) = 0) And (Pos('aspect_ratio', Slice) = 0) And (Pos('"size"', Slice) = 0));
  Named := ProviderNamed(Slice);
  If Named <> '' Then
    Check('writer source names a provider (' + Named + ')', False)
  Else
    Check('writer source does not name a provider', Slice <> '');
  AdapterBody := LoadText(IncludeTrailingPathDelimiter(UnitDir) + 'AssistantImageAdapters.pas');
  RecordBody := LoadText(IncludeTrailingPathDelimiter(UnitDir) + 'AssistantGeneratedImage.pas');
  Check('adapter units do not write the file',
    (Pos('PublishImageBytes', AdapterBody) = 0) And (Pos('PublishImageBytes', RecordBody) = 0) And
    (Pos('fmCreate', AdapterBody) = 0) And (Pos('fmCreate', RecordBody) = 0) And
    (Pos('TFileStream', AdapterBody) = 0) And (Pos('TFileStream', RecordBody) = 0));
End;

Function FixturePost(Const Url, Body, Headers: String; Out ResponseBody: String; Out StatusCode: Integer;
  Out PostError: String): Boolean;
Begin
  Inc(MockCalls);
  SeenUrl := Url;
  SeenBody := Body;
  SeenHeaders := Headers;
  PostError := '';
  StatusCode := 200;
  ResponseBody := MockResponse;
  Result := Pos('Bearer test-key', Headers) > 0;
End;

Function CallWrite(Mode: TAssistantMode; Const Args: String; Out Reply, Note: String): Boolean;
Begin
  Reply := '';
  Note := '';
  LastRefs := Nil;
  Result := ExecuteAssistantToolForMode('write_image', Args, Mode, Reply, Note, LastRefs);
End;

Function ProjectFile(Const Project, RelativePath: String): String;
Begin
  Result := IncludeTrailingPathDelimiter(Project) + StringReplace(RelativePath, '/', PathDelim, [rfReplaceAll]);
End;

Function WroteFixture(Const RelativePath, Reply, Dest, ImageModel: String): Boolean;
Begin
  Result := (Pos('Wrote ' + RelativePath + ' (' + IntToStr(Length(PngBytes)) + ' bytes).', Reply) = 1) And
    (Pos('path=' + RelativePath, Reply) > 0) And (Pos('bytes=' + IntToStr(Length(PngBytes)), Reply) > 0) And
    (Pos('width=1', Reply) > 0) And (Pos('height=1', Reply) > 0) And (Pos('mime=image/png', Reply) > 0) And
    (Pos('model=' + ImageModel, Reply) > 0) And (Pos(ChatModel, Reply) = 0) And
    FileExists(Dest) And SameBytes(ReadBytes(Dest), PngBytes) And (Length(LastRefs) = 1);
End;

Function BodyField(Const Name, Expected: String): Boolean;
Var
  Data: TJSONData;
Begin
  Result := False;
  Data := Nil;
  Try
    Data := GetJSON(SeenBody);
    Result := (Data Is TJSONObject) And (TJSONObject(Data).Get(Name, #1) = Expected);
  Finally
    Data.Free;
  End;
End;

Function BodyLacks(Const Name: String): Boolean;
Var
  Data: TJSONData;
Begin
  Result := False;
  Data := Nil;
  Try
    Data := GetJSON(SeenBody);
    Result := (Data Is TJSONObject) And (TJSONObject(Data).Find(Name) = Nil);
  Finally
    Data.Free;
  End;
End;

Function ArgsFor(Const RelativePath, Prompt, Shape: String): String;
Begin
  Result := '{"path":"' + RelativePath + '","prompt":"' + Prompt + '"';
  If Shape <> '' Then
    Result := Result + ',"shape":"' + Shape + '"';
  Result := Result + '}';
End;

Var
  Root, Project, Outside, SettingsDir, PreviousSettings, Reply, Note, Prompt, ToolsJson, Slice: String;
  Store: TAssistantConnections;
  GrokItem, CompatibleItem, ClaudeItem, CodexItem, EmptyModel: TAssistantConnection;
  SavedApproval: TAssistantApprovalMode;
  Kept: TBytes;
  PostsBefore: Integer;
Begin
  Root := IncludeTrailingPathDelimiter(GetTempDir) + 'laz-write-image-fixture-' + IntToStr(GetProcessID);
  Project := IncludeTrailingPathDelimiter(Root) + 'project';
  Outside := IncludeTrailingPathDelimiter(Root) + 'outside.png';
  SettingsDir := IncludeTrailingPathDelimiter(Root) + 'settings';
  ForceDirectories(Project);
  ForceDirectories(SettingsDir);
  WriteText(Outside, 'keep-outside');
  PreviousSettings := WorkflowSettingsDirectory;
  SetWorkflowSettingsDirectory(SettingsDir);
  SavedApproval := aamAsk;
  If Assigned(AssistantChatConfig) Then
    Begin
      SavedApproval := AssistantChatConfig.GetApprovalMode;
      AssistantChatConfig.SetApprovalModeEnum(aamAlways);
    End;
  Store := TAssistantConnections.Create(SettingsDir);
  MockResponse := PngResponse;
  SetGeneratedImagePost(@FixturePost);
  BeginWriteImageTurn;
  Try
    Check('repository source is visible from the working directory', RepoRoot <> '');
    Check('Grok default is the Imagine image model', AssistantGrokImageModel = 'grok-imagine-image-2.0');
    GrokItem := Store.AddStored('grok-draw', 'Grok draw', 'grok');
    GrokItem.Model := ChatModel;
    GrokItem.ApiBase := 'https://api.x.ai/v1';
    GrokItem.KeySource := 'stored';
    GrokItem.KeyValue := 'test-key';
    GrokItem.ImageOutput := False;
    GrokItem.ImageModel := '';
    Store.ActiveId := GrokItem.Id;
    Check('flag-off profile saved', Store.Save);
    Check('folder target selected', AssistantTarget.SelectFolder(Project, Note));
    ToolsJson := BuildAssistantToolsJsonForMode(amBuild);
    Prompt := WorkflowAssistantHarness.BuildSystemPrompt(amBuild, Nil, Project, '');
    MockCalls := 0;
    Check('flag off omits write_image',
      (Pos('write_image', ToolsJson) = 0) And (Pos('<image_output>', Prompt) = 0) And
      (Pos('Call `write_image` once', Prompt) = 0) And
      (Pos('This model cannot write image files; say so, and do not invent a path or a PNG.', Prompt) > 0) And
      (Not ToolAllowedInMode('write_image', amBuild)));
    CheckNoted('flag off call is an unknown tool and does not post', Note,
      (Not CallWrite(amBuild, ArgsFor('icons/flag-off.png', 'a red dot', ''), Reply, Note)) And
      (Note = 'Unknown tool: write_image') And (Reply = '') And (MockCalls = 0) And
      (Not FileExists(ProjectFile(Project, 'icons/flag-off.png'))));

    GrokItem.ImageOutput := True;
    ApplyImageOutputTurnedOn(GrokItem);
    Check('turning Grok image output on fills the default image model',
      (GrokItem.ImageModel = 'grok-imagine-image-2.0') And (GrokItem.Model = ChatModel));
    Store.ActiveId := GrokItem.Id;
    Check('capable Grok profile saved', Store.Save);
    ToolsJson := BuildAssistantToolsJsonForMode(amBuild);
    Slice := ImageToolSlice(ToolsJson);
    Prompt := WorkflowAssistantHarness.BuildSystemPrompt(amBuild, Nil, Project, '');
    Check('flag on schema requires prompt, has optional shape, and has no image_id',
      (Pos('"name":"write_image"', Slice) > 0) And (Pos('"prompt":', Slice) > 0) And
      (Pos('"required":["path","prompt"]', Slice) > 0) And (Pos('"shape":', Slice) > 0) And
      (Pos('"shape"', Copy(Slice, Pos('"required":', Slice), 40)) = 0) And
      (Pos('"image_id"', Slice) = 0) And (Pos('grok', LowerCase(Slice)) = 0) And
      (Pos('The path may omit an extension.', Slice) > 0) And
      (Pos('The image model chooses the format.', Slice) > 0) And
      (Pos('Prefer PNG', Slice) = 0));
    Check('flag on prompt tells the model to call once and not to name an image model',
      (Pos('<image_output>', Prompt) > 0) And
      (Pos('Call `write_image` once with a short prompt and a project path.', Prompt) > 0) And
      (Pos('Do not pick or name an image model in the call.', Prompt) > 0) And
      (Pos('Do not spawn a subagent to draw.', Prompt) > 0) And
      (Pos('unless the result starts with Wrote.', Prompt) > 0) And
      (Pos('Exact pixels may differ across models.', Prompt) > 0) And
      (Pos('The path may omit an extension.', Prompt) > 0) And
      (Pos('The image model chooses the format.', Prompt) > 0) And
      (Pos('do not call again only to change the extension.', Prompt) > 0) And
      (Pos('Prefer PNG', Prompt) = 0) And
      (Pos('image_id', Prompt) = 0) And (Pos('cannot write image files', Prompt) = 0) And
      (Pos('grok-imagine-image-2.0', Prompt) = 0) And
      ToolAllowedInMode('write_image', amBuild));
    Check('a subagent tool list has no write_image',
      (Pos('write_image', BuildAssistantToolsJsonForSession(amBuild, True, False)) = 0) And
      (Pos('write_image', BuildAssistantToolsJsonForSession(amBuild, False, False)) = 0) And
      (Pos('"name":"write_image"', BuildAssistantToolsJsonForSession(amBuild, True, True)) > 0));

    BeginWriteImageTurn;
    MockCalls := 0;
    CheckNoted('a response-part id is not a draw', Note,
      (Not CallWrite(amBuild, '{"path":"icons/from-id.png","image_id":"ig_turn"}', Reply, Note)) And
      (Pos('prompt', Note) > 0) And (MockCalls = 0) And (Reply = '') And
      (Not FileExists(ProjectFile(Project, 'icons/from-id.png'))));

    BeginWriteImageTurn;
    MockCalls := 0;
    MockResponse := PngResponse;
    CheckNoted('Grok mock post writes the fixture PNG', Note,
      CallWrite(amBuild, '{"path":"icons/grok.png","prompt":"a red dot","image_id":"ig_turn"}', Reply, Note) And
      WroteFixture('icons/grok.png', Reply, ProjectFile(Project, 'icons/grok.png'), 'grok-imagine-image-2.0') And
      (MockCalls = 1) And (SeenUrl = 'https://api.x.ai/v1/images/generations') And
      BodyField('model', 'grok-imagine-image-2.0') And BodyField('prompt', 'a red dot') And
      BodyLacks('size') And BodyLacks('aspect_ratio') And (Pos(ChatModel, SeenBody) = 0) And
      (Pos('ig_turn', Reply) = 0));
    CheckNoted('an inapplicable Grok shape is omitted and the draw still proceeds', Note,
      CallWrite(amBuild, ArgsFor('icons/grok-shape.png', 'a red dot', '1024x1024'), Reply, Note) And
      (MockCalls = 2) And WroteFixture('icons/grok-shape.png', Reply, ProjectFile(Project, 'icons/grok-shape.png'),
      'grok-imagine-image-2.0') And BodyField('model', 'grok-imagine-image-2.0') And
      BodyLacks('size') And BodyLacks('aspect_ratio') And (Pos('1024x1024', SeenBody) = 0) And
      (Pos(ChatModel, SeenBody) = 0));
    BeginWriteImageTurn;
    MockCalls := 0;
    CheckNoted('a path with no extension keeps the image model format', Note,
      CallWrite(amBuild, ArgsFor('icons/plain', 'a red dot', ''), Reply, Note) And
      WroteFixture('icons/plain.png', Reply, ProjectFile(Project, 'icons/plain.png'), 'grok-imagine-image-2.0') And
      (MockCalls = 1) And (Not FileExists(ProjectFile(Project, 'icons/plain'))) And
      (Pos('requested=icons/plain', Reply) > 0) And (Pos('chosen=image/png', Reply) > 0));
    MockResponse := JpegResponse;
    CheckNoted('a mismatched extension is saved as the image model format', Note,
      CallWrite(amBuild, ArgsFor('icons/chosen.png', 'a red dot', ''), Reply, Note) And
      (MockCalls = 2) And (Pos('Wrote icons/chosen.jpg (', Reply) = 1) And
      (Pos('path=icons/chosen.jpg', Reply) > 0) And (Pos('mime=image/jpeg', Reply) > 0) And
      (Pos('requested=icons/chosen.png', Reply) > 0) And (Pos('chosen=image/jpeg', Reply) > 0) And
      (Pos('model=grok-imagine-image-2.0', Reply) > 0) And (Length(LastRefs) = 1) And
      FileExists(ProjectFile(Project, 'icons/chosen.jpg')) And
      SameBytes(ReadBytes(ProjectFile(Project, 'icons/chosen.jpg')), JpegBytes) And
      (Not FileExists(ProjectFile(Project, 'icons/chosen.png'))));
    MockResponse := PngResponse;
    CheckNoted('a saved format adjustment does not block the next draw', Note,
      CallWrite(amBuild, ArgsFor('icons/after-adjust.png', 'a red dot', ''), Reply, Note) And
      (MockCalls = 3) And WroteFixture('icons/after-adjust.png', Reply,
      ProjectFile(Project, 'icons/after-adjust.png'), 'grok-imagine-image-2.0'));

    CompatibleItem := Store.AddStored('compatible-draw', 'Compatible draw', 'openai-compatible');
    CompatibleItem.Model := ChatModel;
    CompatibleItem.ImageModel := OtherImageModel;
    CompatibleItem.ApiBase := 'https://example.invalid/v1';
    CompatibleItem.KeySource := 'stored';
    CompatibleItem.KeyValue := 'test-key';
    CompatibleItem.ImageOutput := True;
    Store.ActiveId := CompatibleItem.Id;
    Check('compatible profile saved', Store.Save);
    BeginWriteImageTurn;
    MockCalls := 0;
    CheckNoted('OpenAI-compatible mock posts the other image model', Note,
      CallWrite(amBuild, ArgsFor('icons/compatible.png', 'a blue square', '16:9'), Reply, Note) And
      (MockCalls = 1) And (SeenUrl = 'https://example.invalid/v1/images/generations') And
      WroteFixture('icons/compatible.png', Reply, ProjectFile(Project, 'icons/compatible.png'), OtherImageModel) And
      BodyField('model', OtherImageModel) And BodyField('prompt', 'a blue square') And
      BodyLacks('aspect_ratio') And BodyLacks('size') And (Pos('16:9', SeenBody) = 0) And
      (Pos(ChatModel, SeenBody) = 0) And (Pos('model=' + OtherImageModel, Reply) > 0));

    ClaudeItem := Store.AddStored('claude-draw', 'Claude draw', 'claude');
    ClaudeItem.Model := ChatModel;
    ClaudeItem.ImageModel := 'should-not-post';
    ClaudeItem.ImageOutput := True;
    ClaudeItem.KeyValue := 'test-key';
    Store.ActiveId := ClaudeItem.Id;
    Check('Claude profile saved', Store.Save);
    Check('Claude with the flag on still offers the tool',
      Pos('"name":"write_image"', BuildAssistantToolsJsonForMode(amBuild)) > 0);
    BeginWriteImageTurn;
    MockCalls := 0;
    CheckNoted('Claude with the flag on does not post', Note,
      (Not CallWrite(amBuild, ArgsFor('icons/claude.png', 'a red dot', '1:1'), Reply, Note)) And
      (MockCalls = 0) And (Pos('no image endpoint', Note) > 0) And
      (Not FileExists(ProjectFile(Project, 'icons/claude.png'))));

    CodexItem := Store.AddStored('codex-draw', 'Codex draw', 'codex');
    CodexItem.Model := ChatModel;
    CodexItem.ImageModel := 'should-not-post';
    CodexItem.ImageOutput := True;
    CodexItem.KeyValue := 'test-key';
    Store.ActiveId := CodexItem.Id;
    Check('Codex profile saved', Store.Save);
    BeginWriteImageTurn;
    MockCalls := 0;
    CheckNoted('Codex with the flag on does not post', Note,
      (Not CallWrite(amBuild, ArgsFor('icons/codex.png', 'a red dot', ''), Reply, Note)) And
      (MockCalls = 0) And (Pos('no image endpoint', Note) > 0) And
      (Not FileExists(ProjectFile(Project, 'icons/codex.png'))));

    EmptyModel := Store.AddStored('empty-model', 'Empty model', 'openai-compatible');
    EmptyModel.Model := ChatModel;
    EmptyModel.ImageModel := '';
    EmptyModel.ApiBase := 'https://example.invalid/v1';
    EmptyModel.KeySource := 'stored';
    EmptyModel.KeyValue := 'test-key';
    EmptyModel.ImageOutput := True;
    ApplyImageOutputTurnedOn(EmptyModel);
    Store.ActiveId := EmptyModel.Id;
    Check('empty image model saved', Store.Save And (EmptyModel.ImageModel = '') And (EmptyModel.Model = ChatModel));
    BeginWriteImageTurn;
    MockCalls := 0;
    CheckNoted('a missing image model is refused before the post', Note,
      (Not CallWrite(amBuild, ArgsFor('icons/no-model.png', 'a red dot', ''), Reply, Note)) And
      (MockCalls = 0) And (Pos('image model', Note) > 0) And
      (Not FileExists(ProjectFile(Project, 'icons/no-model.png'))));

    Store.ActiveId := GrokItem.Id;
    Check('Grok profile restored', Store.Save);
    BeginWriteImageTurn;
    MockCalls := 0;
    CheckNoted('a missing prompt is refused before the post', Note,
      (Not CallWrite(amBuild, '{"path":"icons/no-prompt.png"}', Reply, Note)) And
      (MockCalls = 0) And (Pos('prompt', Note) > 0) And (Reply = '') And
      (Not FileExists(ProjectFile(Project, 'icons/no-prompt.png'))));

    BeginWriteImageTurn;
    MockCalls := 0;
    CheckNoted('path escape is refused before the post', Note,
      (Not CallWrite(amBuild, ArgsFor('../outside.png', 'a red dot', ''), Reply, Note)) And
      (Pos('outside', Note) > 0) And (MockCalls = 0) And (ReadText(Outside) = 'keep-outside'));
    BeginWriteImageTurn;
    CheckNoted('nested path escape is refused before the post', Note,
      (Not CallWrite(amBuild, ArgsFor('icons/../../outside.png', 'a red dot', ''), Reply, Note)) And
      (Pos('outside', Note) > 0) And (MockCalls = 0) And (ReadText(Outside) = 'keep-outside'));
    BeginWriteImageTurn;
    CheckNoted('absolute path escape is refused before the post', Note,
      (Not CallWrite(amBuild, '{"path":"' + Outside + '","prompt":"a red dot"}', Reply, Note)) And
      (Pos('outside', Note) > 0) And (MockCalls = 0) And (ReadText(Outside) = 'keep-outside'));
    {$IFDEF UNIX}
    Check('escape link created', fpSymlink(PChar(Outside), PChar(ProjectFile(Project, 'escape.png'))) = 0);
    BeginWriteImageTurn;
    MockCalls := 0;
    CheckNoted('symlink out of the project is refused', Note,
      (Not CallWrite(amBuild, ArgsFor('escape.png', 'a red dot', ''), Reply, Note)) And
      (Pos('symbolic link', Note) > 0) And (MockCalls = 0) And (ReadText(Outside) = 'keep-outside'));
    {$ENDIF}

    BeginWriteImageTurn;
    MockCalls := 0;
    MockResponse := BadMagicResponse;
    CheckNoted('bad magic bytes are refused', Note,
      (Not CallWrite(amBuild, ArgsFor('icons/bad.png', 'a red dot', ''), Reply, Note)) And
      (MockCalls = 1) And ((Pos('not a still image', Note) > 0) Or (Pos('Do not retry.', Note) > 0)) And
      (Reply = '') And (Not FileExists(ProjectFile(Project, 'icons/bad.png'))) And
      (Not FileExists(ProjectFile(Project, 'icons/bad.png') + '.writing')));
    PostsBefore := MockCalls;
    CheckNoted('a second call after a failed draw does not post', Note,
      (Not CallWrite(amBuild, ArgsFor('icons/retry.png', 'a red dot', '1:1'), Reply, Note)) And
      (MockCalls = PostsBefore) And (Pos('Stop and report that error.', Note) > 0) And (Reply = '') And
      (Not FileExists(ProjectFile(Project, 'icons/retry.png'))));
    MockResponse := PngResponse;

    Kept := ReadBytes(ProjectFile(Project, 'icons/grok.png'));
    BeginWriteImageTurn;
    MockCalls := 0;
    CheckNoted('overwrite without the flag is refused before the post', Note,
      (Not CallWrite(amBuild, ArgsFor('icons/grok.png', 'a red dot', ''), Reply, Note)) And
      (Pos('overwrite', Note) > 0) And (Reply = '') And (MockCalls = 0) And
      SameBytes(ReadBytes(ProjectFile(Project, 'icons/grok.png')), Kept));

    BeginWriteImageTurn;
    MockCalls := 0;
    CheckNoted('Plan call is refused', Note,
      (Not CallWrite(amPlan, ArgsFor('icons/plan-mode.png', 'a red dot', ''), Reply, Note)) And
      (Note = 'Unknown tool: write_image') And (Reply = '') And (MockCalls = 0) And
      (Not FileExists(ProjectFile(Project, 'icons/plan-mode.png'))) And
      (Pos('write_image', BuildAssistantToolsJsonForMode(amPlan)) = 0));
    CheckNoted('Document call is refused', Note,
      (Not CallWrite(amDocument, ArgsFor('icons/document-mode.png', 'a red dot', ''), Reply, Note)) And
      (Note = 'Unknown tool: write_image') And (Reply = '') And (MockCalls = 0) And
      (Not FileExists(ProjectFile(Project, 'icons/document-mode.png'))) And
      (Pos('write_image', BuildAssistantToolsJsonForMode(amDocument)) = 0));
    TestSharedWriter(IncludeTrailingPathDelimiter(RepoRoot) + 'Source' + PathDelim + 'LazAssistantTools');
    WriteLn('AssistantWriteImageTest passed');
  Finally
    SetGeneratedImagePost(Nil);
    BeginWriteImageTurn;
    If Assigned(AssistantChatConfig) Then
      AssistantChatConfig.SetApprovalModeEnum(SavedApproval);
    Store.Free;
    SetWorkflowSettingsDirectory(PreviousSettings);
  End;
End.
