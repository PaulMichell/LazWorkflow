Program ClaudeCaptureTest;

{ Checks the Claude Code image capture without starting claude (c) 2026 Michell Computing.

  Builds Tests/ClaudeCaptureProgram.pas, the work of Tests/Fixtures/Claude/CaptureClaudeImages.lpr, so the capture
  program cannot stop compiling unseen. Checks the pictures, the stream-json lines, the claude arguments, the MCP
  server's replies, the stream summary, and, on Unix, the child runner's stdin handling with /bin/sh. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, fpjson, jsonparser, base64, FPImage, FPReadPNG, ClaudeCaptureSupport, ClaudeCaptureProgram;

Procedure Check(Const Name: String; OK: Boolean);
Begin
  If Not OK Then
    Begin
      WriteLn('FAIL ', Name);
      Halt(1);
    End;
  WriteLn('ok   ', Name);
End;

Function ImageFromPNG(Const Bytes: String): TFPMemoryImage;
Var
  Stream: TMemoryStream;
  Reader: TFPReaderPNG;
Begin
  Result := TFPMemoryImage.Create(0, 0);
  Stream := TMemoryStream.Create;
  Reader := TFPReaderPNG.Create;
  Try
    Stream.WriteBuffer(Bytes[1], Length(Bytes));
    Stream.Position := 0;
    Result.LoadFromStream(Stream, Reader);
  Finally
    Reader.Free;
    Stream.Free;
  End;
End;

Function SameColour(Colour: TFPColor; Red, Green, Blue: Byte): Boolean;
Begin
  Result := (Colour.Red Shr 8 = Red) And (Colour.Green Shr 8 = Green) And (Colour.Blue Shr 8 = Blue);
End;

Procedure CheckPictures;
Var
  Bytes: String;
  Image: TFPMemoryImage;
Begin
  Bytes := CapturePicturePNG(cpInputCircle);
  Check('the input picture is a PNG', Copy(Bytes, 1, 8) = #137'PNG'#13#10#26#10);
  Image := ImageFromPNG(Bytes);
  Try
    Check('the input picture is 256 pixels square', (Image.Width = 256) And (Image.Height = 256));
    Check('the input picture has a red circle on yellow', SameColour(Image.Colors[128, 128], 255, 0, 0) And
      SameColour(Image.Colors[2, 2], 255, 255, 0) And SameColour(Image.Colors[128, 50], 255, 0, 0));
  Finally
    Image.Free;
  End;
  Image := ImageFromPNG(CapturePicturePNG(cpToolTriangle));
  Try
    Check('the tool picture has a green triangle on white', SameColour(Image.Colors[128, 180], 0, $C0, 0) And
      SameColour(Image.Colors[20, 200], 255, 255, 255) And SameColour(Image.Colors[128, 20], 255, 255, 255));
  Finally
    Image.Free;
  End;
  Check('the pictures are the same on every call', CapturePicturePNG(cpInputCircle) = Bytes);
  Check('the large picture is over the API''s per-image limit', Length(CapturePicturePNG(cpLargeNoise)) > CaptureApiImageLimitBytes);
End;

Procedure CheckMessages;
Var
  Line, Data: String;
  Root, MessageObject, Source: TJSONObject;
  Content: TJSONArray;
Begin
  Data := EncodeStringBase64(CapturePicturePNG(cpInputCircle));
  Line := CaptureImageMessage('Describe it.', 'image/png', Data, cmsPlain);
  Check('a stream-json message is one line', (Pos(#10, Line) = 0) And (Pos(#13, Line) = 0));
  Root := TJSONObject(GetJSON(Line));
  Try
    MessageObject := Root.Objects['message'];
    Content := MessageObject.Arrays['content'];
    Source := Content.Objects[1].Objects['source'];
    Check('the plain shape is a user message', (Root.Get('type', '') = 'user') And (Root.Count = 2) And
      (MessageObject.Get('role', '') = 'user'));
    Check('the text block comes first', (Content.Count = 2) And (Content.Objects[0].Get('type', '') = 'text') And
      (Content.Objects[0].Get('text', '') = 'Describe it.'));
    Check('the image block carries base64 PNG data', (Content.Objects[1].Get('type', '') = 'image') And
      (Source.Get('type', '') = 'base64') And (Source.Get('media_type', '') = 'image/png') And (Source.Get('data', '') = Data));
  Finally
    Root.Free;
  End;
  Root := TJSONObject(GetJSON(CaptureTextMessage('Again?', cmsSDK)));
  Try
    Check('the SDK shape adds parent_tool_use_id and session_id', (Root.Find('parent_tool_use_id') Is TJSONNull) And
      (Root.Get('session_id', 'missing') = '') And (Root.Objects['message'].Arrays['content'].Count = 1));
  Finally
    Root.Free;
  End;
  Check('long data is shortened in summaries', CaptureShortenedJson(Line) <> Line);
  Check('the shortened line keeps the shape', Pos('"media_type" : "image/png"', CaptureShortenedJson(Line)) > 0);
End;

Procedure CheckArguments;
Var
  Args: TStringList;
  CaptureCase: TCaptureCase;
Begin
  Args := TStringList.Create;
  Try
    For CaptureCase := Low(TCaptureCase) To High(TCaptureCase) Do
      Begin
        Args.Clear;
        AppendCaptureArguments(CaptureCase, 'haiku', 'session-1', 'config.json', Args);
        Check(CaptureCaseNames[CaptureCase] + ' passes no forbidden flag', CaptureArgumentsAllowed(Args));
        Check(CaptureCaseNames[CaptureCase] + ' is a stream-json print turn', (Args[0] = '-p') And
          (Args.IndexOf('--verbose') > 0) And (Args.IndexOf('--strict-mcp-config') > 0) And
          (Args[Args.IndexOf('--output-format') + 1] = 'stream-json'));
        If CaptureCase = ccMCPImage Then
          Check('mcp-image reads plain stdin and loads only the capture server', (Args.IndexOf('--input-format') < 0) And
            (Args.IndexOf('--mcp-config=config.json') > 0) And (Args.IndexOf('--allowedTools=mcp__capture__*') > 0))
        Else
          Check(CaptureCaseNames[CaptureCase] + ' reads stream-json and has no tools',
            (Args[Args.IndexOf('--input-format') + 1] = 'stream-json') And (Args.IndexOf('--tools=') > 0));
      End;
    Args.Clear;
    AppendCaptureArguments(ccImageInput, '', 'session-1', '', Args);
    Check('the image turn starts its session', (Args[Args.IndexOf('--session-id') + 1] = 'session-1') And
      (Args.IndexOf('--model') < 0));
    Args.Clear;
    AppendCaptureArguments(ccImageResume, 'haiku', 'session-1', '', Args);
    Check('the resume turn resumes it', (Args[Args.IndexOf('--resume') + 1] = 'session-1') And (Args.IndexOf('--session-id') < 0));
    Args.Clear;
    AppendCaptureArguments(ccLimitsLarge, 'haiku', '', '', Args);
    Check('probe turns keep no session', Args.IndexOf('--no-session-persistence') > 0);
    Args.Add('--bare');
    Check('--bare is refused', Not CaptureArgumentsAllowed(Args));
    Args.Clear;
    Args.Add('--betas=x');
    Check('--betas=value is refused', Not CaptureArgumentsAllowed(Args));
    Args.Clear;
    Args.Add('--max-budget-usd');
    Check('--max-budget-usd is refused', Not CaptureArgumentsAllowed(Args));
  Finally
    Args.Free;
  End;
End;

Function ReplyObject(Const RequestLine: String): TJSONObject;
Var
  Reply: String;
Begin
  Result := Nil;
  If CaptureMCPReply(RequestLine, Reply) Then
    Result := TJSONObject(GetJSON(Reply));
End;

Procedure CheckMCPServer;
Var
  Reply: String;
  Answer, Item: TJSONObject;
  Config: TJSONData;
  Content: TJSONArray;
Begin
  Answer := ReplyObject('{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{}}}');
  Try
    Check('initialize is answered with the client''s protocol version', Assigned(Answer) And (Answer.Get('id', -1) = 0) And
      (Answer.Objects['result'].Get('protocolVersion', '') = '2025-03-26') And
      (Answer.Objects['result'].Objects['capabilities'].Find('tools') Is TJSONObject));
  Finally
    Answer.Free;
  End;
  Check('a notification gets no reply', Not CaptureMCPReply('{"jsonrpc":"2.0","method":"notifications/initialized"}', Reply));
  Check('a line that is not JSON gets no reply', Not CaptureMCPReply('not json', Reply));
  Answer := ReplyObject('{"jsonrpc":"2.0","id":"a1","method":"tools/list"}');
  Try
    Check('tools/list offers show_picture and keeps a string id', Assigned(Answer) And (Answer.Get('id', '') = 'a1') And
      (Answer.Objects['result'].Arrays['tools'].Objects[0].Get('name', '') = CaptureToolName));
  Finally
    Answer.Free;
  End;
  Answer := ReplyObject('{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"show_picture","arguments":{}}}');
  Try
    Content := Answer.Objects['result'].Arrays['content'];
    Item := Content.Objects[1];
    Check('the tool result carries an MCP image item', (Content.Objects[0].Get('type', '') = 'text') And
      (Item.Get('type', '') = 'image') And (Item.Get('mimeType', '') = 'image/png') And
      (Item.Get('data', '') = EncodeStringBase64(CapturePicturePNG(cpToolTriangle))));
  Finally
    Answer.Free;
  End;
  Answer := ReplyObject('{"jsonrpc":"2.0","id":3,"method":"resources/list"}');
  Try
    Check('an unknown method is an error', Assigned(Answer) And (Answer.Objects['error'].Get('code', 0) = -32601));
  Finally
    Answer.Free;
  End;
  Config := GetJSON(CaptureMCPConfig('/bin/capture', '/out/mcp.log'));
  Try
    Check('the MCP config starts this program as a stdio server',
      (Config.FindPath('mcpServers.capture.type').AsString = 'stdio') And
      (Config.FindPath('mcpServers.capture.command').AsString = '/bin/capture') And
      (Config.FindPath('mcpServers.capture.args').AsJSON = '["--mcp-server", "/out/mcp.log"]'));
  Finally
    Config.Free;
  End;
End;

Procedure CheckStreamReading;
Const
  Stream = '{"type":"system","subtype":"init","session_id":"s1","model":"haiku","mcp_servers":[]}' + #10 +
    '{"type":"assistant","message":{"content":[{"type":"text","text":"A red circle on yellow."}]}}' + #10 +
    '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":[{"type":"image","source":' +
    '{"type":"base64","media_type":"image/png","data":"' +
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}}]}]}}' + #10 +
    'stray text' + #10 +
    '{"type":"result","subtype":"success","is_error":false,"result":"A Red Circle on yellow."}' + #10;
Var
  ResultText, Summary: String;
  IsError: Boolean;
Begin
  Check('the result event is read', CaptureStreamResult(Stream, ResultText, IsError) And Not IsError And
    (ResultText = 'A Red Circle on yellow.'));
  Check('no result event is reported', Not CaptureStreamResult('{"type":"system"}', ResultText, IsError));
  Check('answer words are matched without case', CaptureAnswerMentions('A Red Circle on yellow.', CaptureInputWords) And
    Not CaptureAnswerMentions('A Red Circle on yellow.', CaptureToolWords) And Not CaptureAnswerMentions('', []));
  Summary := CaptureStreamSummary(Stream);
  Check('the summary shows the init, the answer and the result', (Pos('- init: session s1', Summary) > 0) And
    (Pos('assistant text: A red circle', Summary) > 0) And (Pos('result: subtype success', Summary) > 0));
  Check('the summary shows the tool result with its data shortened', (Pos('user tool_result', Summary) > 0) And
    (Pos(' base64 characters>', Summary) > 0) And (Pos('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', Summary) = 0));
  Check('a line that is not JSON is kept', Pos('- not JSON: stray text', Summary) > 0);
End;

{$IFDEF UNIX}
Procedure CheckChildRunner;
Var
  Args, Environment: TStringList;
  Run: TCaptureRun;
Begin
  Args := TStringList.Create;
  Environment := TStringList.Create;
  Try
    Args.Add('-c');
    Args.Add('cat');
    Run := RunCaptureProcess('/bin/sh', GetTempDir(False), Args, Environment, 'hello' + #10, False, 0, 10000);
    Check('a closed stdin ends a reader at once', Run.Started And Not Run.TimedOut And (Run.ExitCode = 0) And
      (Run.StdoutText = 'hello' + #10) And Not Run.ExitedWithInputOpen And (Run.InputClosedSeconds >= 0));
    Args[1] := 'read line; printf ''{"type":"result"}\n''; cat > /dev/null';
    Run := RunCaptureProcess('/bin/sh', GetTempDir(False), Args, Environment, 'x' + #10, True, 300, 10000);
    Check('an open stdin is closed after the result event', Not Run.TimedOut And (Run.ResultSeconds >= 0) And
      (Run.InputClosedSeconds >= Run.ResultSeconds) And Not Run.ExitedWithInputOpen And (Run.ExitCode = 0));
    Args[1] := 'read line; printf ''{"type":"result"}\n''';
    Run := RunCaptureProcess('/bin/sh', GetTempDir(False), Args, Environment, 'x' + #10, True, 5000, 10000);
    Check('a child that ends with stdin open is recorded', Not Run.TimedOut And Run.ExitedWithInputOpen And
      (Run.InputClosedSeconds < 0) And (Run.ResultSeconds >= 0));
    Args[1] := 'sleep 5';
    Run := RunCaptureProcess('/bin/sh', GetTempDir(False), Args, Environment, '', False, 0, 300);
    Check('a child past its time limit is stopped', Run.TimedOut And Not Run.ExitedWithInputOpen);
    Run := RunCaptureProcess('/nonexistent/claude', GetTempDir(False), Args, Environment, '', False, 0, 1000);
    { The RTL either refuses to start it or the forked child fails to exec it; neither may raise. }
    Check('a missing program is reported, not raised', (Not Run.Started And (Run.ErrorText <> '')) Or
      (Run.Started And (Run.ExitCode <> 0)));
  Finally
    Environment.Free;
    Args.Free;
  End;
End;
{$ENDIF}

Begin
  CheckPictures;
  CheckMessages;
  CheckArguments;
  CheckMCPServer;
  CheckStreamReading;
  {$IFDEF UNIX}
  CheckChildRunner;
  {$ENDIF}
  { Referenced so the program unit is linked as well as compiled. }
  Check('the capture program is built', Assigned(@RunCaptureProgram));
  WriteLn('ClaudeCaptureTest passed');
End.
