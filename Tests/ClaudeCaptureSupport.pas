Unit ClaudeCaptureSupport;

{ Pieces of the Claude Code image capture (c) 2026 Michell Computing.

  The synthetic pictures, the stream-json user messages, the claude arguments for each case, the stdio MCP server whose
  tool result carries a picture, and the child-process runner that records when stdin is closed. ClaudeCaptureProgram
  puts them together for Tests/Fixtures/Claude/CaptureClaudeImages.lpr; Tests/ClaudeCaptureTest.lpr checks them
  without claude. Nothing here reads Claude sign-in files, and no argument list may carry ForbiddenClaudeFlags. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes;

Type
  { Each test picture is one shape on a plain background, so an answer can be checked by its colour and shape words. }
  TCapturePicture = (cpInputCircle, cpToolTriangle, cpLargeNoise);

  { cmsPlain has type and message only. cmsSDK adds the parent_tool_use_id and session_id the Agent SDK sends. }
  TCaptureMessageShape = (cmsPlain, cmsSDK);

  TCaptureCase = (ccImageInput, ccImageResume, ccMCPImage, ccStdinOpen, ccLimitsLarge, ccLimitsFormat);
  TCaptureCases = Set Of TCaptureCase;

  { One child process. Times are seconds from its start; -1 means it did not happen. }
  TCaptureRun = Record
    Started, TimedOut: Boolean;
    ExitCode: Integer;
    StdoutText, StderrText, ErrorText: String;
    ResultSeconds, InputClosedSeconds, ExitSeconds: Double;
    { The child ended before its stdin was closed. }
    ExitedWithInputOpen: Boolean;
  End;

Const
  CaptureServerName = 'capture';
  CaptureToolName = 'show_picture';
  CaptureCaseNames: Array[TCaptureCase] Of String = ('image-input', 'image-resume', 'mcp-image', 'stdin-open',
    'limits-large', 'limits-format');
  { --bare skips the subscription sign-in; the other two are per-use API options. None may reach claude. }
  ForbiddenClaudeFlags: Array[0..2] Of String = ('--bare', '--max-budget-usd', '--betas');
  { The Anthropic API's documented limit for one image. The large picture is over it. }
  CaptureApiImageLimitBytes = 5 * 1024 * 1024;
  CaptureInputWords: Array[0..1] Of String = ('red', 'circle');
  CaptureToolWords: Array[0..1] Of String = ('green', 'triangle');

/// PNG file bytes. The noise picture is the same on every run.
Function CapturePicturePNG(Picture: TCapturePicture): String;
/// One stream-json user line, without the line feed: a text block, then a base64 image block.
Function CaptureImageMessage(Const Prompt, MediaType, Base64Data: String; Shape: TCaptureMessageShape): String;
/// One stream-json user line, without the line feed, with a single text block.
Function CaptureTextMessage(Const Prompt: String; Shape: TCaptureMessageShape): String;
/// The claude arguments for one case. ccImageInput starts SessionId and ccImageResume resumes it; the other cases
/// keep no session. Only ccMCPImage loads MCPConfigFile, and it reads stdin as plain text, as the IDE's turns do.
Procedure AppendCaptureArguments(CaptureCase: TCaptureCase; Const Model, SessionId, MCPConfigFile: String; Args: TStrings);
/// False when an argument is one of ForbiddenClaudeFlags, alone or with =value.
Function CaptureArgumentsAllowed(Args: TStrings): Boolean;
/// The --mcp-config text that starts ServerExecutable --mcp-server LogFile over stdio.
Function CaptureMCPConfig(Const ServerExecutable, LogFile: String): String;
/// The JSON-RPC reply to one request line. False for a notification, a response or a line that is not JSON.
Function CaptureMCPReply(Const RequestLine: String; Out Reply: String): Boolean;
/// JSON text with every long "data" string replaced by its length. Text that is not JSON is returned unchanged.
Function CaptureShortenedJson(Const JsonText: String): String;
/// True when Answer contains every word, ignoring case.
Function CaptureAnswerMentions(Const Answer: String; Const Words: Array Of String): Boolean;
/// Reads the result event of a stream-json output. False when there is none.
Function CaptureStreamResult(Const StreamText: String; Out ResultText: String; Out IsError: Boolean): Boolean;
/// One Markdown line per stream event, with image data shortened.
Function CaptureStreamSummary(Const StreamText: String): String;
/// Runs Executable in WorkDir and writes InputText to its stdin. Without KeepInputOpen stdin is closed at once.
/// With it, stdin is closed OpenWaitMs after a result event appears, unless the child has already ended.
Function RunCaptureProcess(Const Executable, WorkDir: String; Args, Environment: TStrings; Const InputText: String;
  KeepInputOpen: Boolean; OpenWaitMs, TimeoutMs: Integer): TCaptureRun;
/// The stdio MCP server Claude Code starts for ccMCPImage. Logs each request and a shortened reply to LogFile.
Procedure RunCaptureMCPServer(Const LogFile: String);

Implementation

Uses
  SysUtils, Math, Process, Pipes, fpjson, jsonparser, base64, FPImage, FPWritePNG;

Const
  PictureSide = 256;
  NoiseSide = 1600;
  NoiseSeed = 20261122;
  ShortDataLength = 80;

Function PictureCovers(Picture: TCapturePicture; X, Y: Integer): Boolean;
Const
  Centre = PictureSide Div 2;
  Radius = 80;
  Top = 40;
  Bottom = PictureSide - 40;
Begin
  Case Picture Of
    cpInputCircle: Result := Sqr(X - Centre) + Sqr(Y - Centre) <= Sqr(Radius);
    cpToolTriangle: Result := (Y >= Top) And (Y <= Bottom) And (2 * Abs(X - Centre) <= Y - Top);
  Else
    Result := False;
  End;
End;

Function CapturePicturePNG(Picture: TCapturePicture): String;
Var
  Image: TFPMemoryImage;
  Writer: TFPWriterPNG;
  Stream: TMemoryStream;
  Side, X, Y: Integer;
  Background, Shape: TFPColor;
Begin
  Result := '';
  If Picture = cpLargeNoise Then
    Side := NoiseSide
  Else
    Side := PictureSide;
  If Picture = cpInputCircle Then
    Begin
      Background := FPColor($FFFF, $FFFF, 0);
      Shape := FPColor($FFFF, 0, 0);
    End
  Else
    Begin
      Background := FPColor($FFFF, $FFFF, $FFFF);
      Shape := FPColor(0, $C0C0, 0);
    End;
  Image := TFPMemoryImage.Create(Side, Side);
  Writer := TFPWriterPNG.Create;
  Stream := TMemoryStream.Create;
  Try
    RandSeed := NoiseSeed;
    For Y := 0 To Side - 1 Do
      For X := 0 To Side - 1 Do
        If Picture = cpLargeNoise Then
          Image.Colors[X, Y] := FPColor(Random($10000), Random($10000), Random($10000))
        Else If PictureCovers(Picture, X, Y) Then
          Image.Colors[X, Y] := Shape
        Else
          Image.Colors[X, Y] := Background;
    { Eight-bit RGB: the writer's default sixteen-bit samples would double the noise picture. }
    Writer.UseAlpha := False;
    Writer.Indexed := False;
    Writer.WordSized := False;
    Image.SaveToStream(Stream, Writer);
    SetString(Result, PChar(Stream.Memory), Stream.Size);
  Finally
    Stream.Free;
    Writer.Free;
    Image.Free;
  End;
End;

Function TextBlock(Const Prompt: String): TJSONObject;
Begin
  Result := TJSONObject.Create(['type', 'text', 'text', Prompt]);
End;

{ Takes ownership of Content. }
Function UserMessageLine(Content: TJSONArray; Shape: TCaptureMessageShape): String;
Var
  Root: TJSONObject;
Begin
  Root := TJSONObject.Create;
  Try
    Root.Add('type', 'user');
    Root.Add('message', TJSONObject.Create(['role', 'user', 'content', Content]));
    If Shape = cmsSDK Then
      Begin
        Root.Add('parent_tool_use_id', TJSONNull.Create);
        Root.Add('session_id', '');
      End;
    Result := Root.AsJSON;
  Finally
    Root.Free;
  End;
End;

Function CaptureImageMessage(Const Prompt, MediaType, Base64Data: String; Shape: TCaptureMessageShape): String;
Var
  Content: TJSONArray;
Begin
  Content := TJSONArray.Create;
  Content.Add(TextBlock(Prompt));
  Content.Add(TJSONObject.Create(['type', 'image', 'source',
    TJSONObject.Create(['type', 'base64', 'media_type', MediaType, 'data', Base64Data])]));
  Result := UserMessageLine(Content, Shape);
End;

Function CaptureTextMessage(Const Prompt: String; Shape: TCaptureMessageShape): String;
Var
  Content: TJSONArray;
Begin
  Content := TJSONArray.Create;
  Content.Add(TextBlock(Prompt));
  Result := UserMessageLine(Content, Shape);
End;

Procedure AppendCaptureArguments(CaptureCase: TCaptureCase; Const Model, SessionId, MCPConfigFile: String; Args: TStrings);
Begin
  If Not Assigned(Args) Then
    Exit;
  Args.Add('-p');
  If CaptureCase <> ccMCPImage Then
    Begin
      Args.Add('--input-format');
      Args.Add('stream-json');
    End;
  Args.Add('--output-format');
  Args.Add('stream-json');
  Args.Add('--verbose');
  If Model <> '' Then
    Begin
      Args.Add('--model');
      Args.Add(Model);
    End;
  Case CaptureCase Of
    ccImageInput:
      Begin
        Args.Add('--session-id');
        Args.Add(SessionId);
      End;
    ccImageResume:
      Begin
        Args.Add('--resume');
        Args.Add(SessionId);
      End;
  Else
    Args.Add('--no-session-persistence');
  End;
  If CaptureCase = ccMCPImage Then
    Begin
      { The tools of an IDE turn outside Chat (AppendClaudeModeArguments), with the capture server in place of lazarus. }
      Args.Add('--tools=Read,Grep,Glob');
      Args.Add('--mcp-config=' + MCPConfigFile);
      Args.Add('--allowedTools=mcp__' + CaptureServerName + '__*');
    End
  Else
    Args.Add('--tools=');
  Args.Add('--strict-mcp-config');
End;

Function CaptureArgumentsAllowed(Args: TStrings): Boolean;
Var
  I, J: Integer;
Begin
  Result := True;
  If Not Assigned(Args) Then
    Exit;
  For I := 0 To Args.Count - 1 Do
    For J := Low(ForbiddenClaudeFlags) To High(ForbiddenClaudeFlags) Do
      If (Args[I] = ForbiddenClaudeFlags[J]) Or (Pos(ForbiddenClaudeFlags[J] + '=', Args[I]) = 1) Then
        Exit(False);
End;

Function CaptureMCPConfig(Const ServerExecutable, LogFile: String): String;
Var
  Root: TJSONObject;
Begin
  Root := TJSONObject.Create(['mcpServers', TJSONObject.Create([CaptureServerName, TJSONObject.Create(['type', 'stdio',
    'command', ServerExecutable, 'args', TJSONArray.Create(['--mcp-server', LogFile])])])]);
  Try
    Result := Root.FormatJSON;
  Finally
    Root.Free;
  End;
End;

Function ToolResult: TJSONObject;
Var
  Content: TJSONArray;
Begin
  Content := TJSONArray.Create;
  Content.Add(TJSONObject.Create(['type', 'text', 'text', 'The picture follows.']));
  Content.Add(TJSONObject.Create(['type', 'image', 'data', EncodeStringBase64(CapturePicturePNG(cpToolTriangle)),
    'mimeType', 'image/png']));
  Result := TJSONObject.Create(['content', Content, 'isError', False]);
End;

Function ReplyResult(Request: TJSONObject; Const MethodName: String; Out ErrorObject: TJSONObject): TJSONObject;
Var
  Version: String;
  Params: TJSONObject;
Begin
  Result := Nil;
  ErrorObject := Nil;
  If MethodName = 'initialize' Then
    Begin
      Version := '2025-06-18';
      If Request.Find('params') Is TJSONObject Then
        Begin
          Params := TJSONObject(Request.Find('params'));
          Version := Params.Get('protocolVersion', Version);
        End;
      Result := TJSONObject.Create(['protocolVersion', Version, 'capabilities', TJSONObject.Create(['tools', TJSONObject.Create]),
        'serverInfo', TJSONObject.Create(['name', CaptureServerName, 'version', '1.0'])]);
    End
  Else If MethodName = 'tools/list' Then
    Result := TJSONObject.Create(['tools', TJSONArray.Create([TJSONObject.Create(['name', CaptureToolName,
      'description', 'Returns a small test picture.', 'inputSchema',
      TJSONObject.Create(['type', 'object', 'properties', TJSONObject.Create])])])])
  Else If MethodName = 'tools/call' Then
    Result := ToolResult
  Else If MethodName = 'ping' Then
    Result := TJSONObject.Create
  Else
    ErrorObject := TJSONObject.Create(['code', -32601, 'message', 'Method not found: ' + MethodName]);
End;

Function CaptureMCPReply(Const RequestLine: String; Out Reply: String): Boolean;
Var
  Data: TJSONData;
  Request, Answer, ResultObject, ErrorObject: TJSONObject;
Begin
  Result := False;
  Reply := '';
  Data := Nil;
  Try
    Try
      Data := GetJSON(RequestLine);
    Except
      On EParserError Do
        Exit;
    End;
    If Not (Data Is TJSONObject) Then
      Exit;
    Request := TJSONObject(Data);
    If (Request.Find('id') = Nil) Or Not (Request.Find('method') Is TJSONString) Then
      Exit;
    ResultObject := ReplyResult(Request, Request.Get('method', ''), ErrorObject);
    Answer := TJSONObject.Create(['jsonrpc', '2.0', 'id', Request.Find('id').Clone]);
    Try
      If Assigned(ResultObject) Then
        Answer.Add('result', ResultObject)
      Else
        Answer.Add('error', ErrorObject);
      Reply := Answer.AsJSON;
    Finally
      Answer.Free;
    End;
    Result := True;
  Finally
    Data.Free;
  End;
End;

Procedure ShortenData(Data: TJSONData);
Var
  I: Integer;
  Item: TJSONData;
Begin
  If Data Is TJSONArray Then
    For I := 0 To Data.Count - 1 Do
      ShortenData(Data.Items[I])
  Else If Data Is TJSONObject Then
    For I := 0 To Data.Count - 1 Do
      Begin
        Item := Data.Items[I];
        If (TJSONObject(Data).Names[I] = 'data') And (Item Is TJSONString) And (Length(Item.AsString) > ShortDataLength) Then
          Item.AsString := '<' + IntToStr(Length(Item.AsString)) + ' base64 characters>'
        Else
          ShortenData(Item);
      End;
End;

Function CaptureShortenedJson(Const JsonText: String): String;
Var
  Data: TJSONData;
Begin
  Result := JsonText;
  Data := Nil;
  Try
    Try
      Data := GetJSON(JsonText);
    Except
      On EParserError Do
        Exit;
    End;
    ShortenData(Data);
    Result := Data.AsJSON;
  Finally
    Data.Free;
  End;
End;

Function CaptureAnswerMentions(Const Answer: String; Const Words: Array Of String): Boolean;
Var
  I: Integer;
Begin
  Result := Trim(Answer) <> '';
  For I := Low(Words) To High(Words) Do
    If Pos(LowerCase(Words[I]), LowerCase(Answer)) = 0 Then
      Exit(False);
End;

Function ParseEvent(Const Line: String): TJSONObject;
Var
  Data: TJSONData;
Begin
  Result := Nil;
  Try
    Data := GetJSON(Line);
  Except
    On EParserError Do
      Exit;
  End;
  If Data Is TJSONObject Then
    Result := TJSONObject(Data)
  Else
    Data.Free;
End;

Function CaptureStreamResult(Const StreamText: String; Out ResultText: String; Out IsError: Boolean): Boolean;
Var
  Lines: TStringList;
  Event: TJSONObject;
  I: Integer;
Begin
  Result := False;
  ResultText := '';
  IsError := False;
  Lines := TStringList.Create;
  Try
    Lines.Text := StreamText;
    For I := 0 To Lines.Count - 1 Do
      Begin
        Event := ParseEvent(Lines[I]);
        If Not Assigned(Event) Then
          Continue;
        Try
          If Event.Get('type', '') = 'result' Then
            Begin
              ResultText := Event.Get('result', '');
              IsError := Event.Get('is_error', False);
              Result := True;
            End;
        Finally
          Event.Free;
        End;
      End;
  Finally
    Lines.Free;
  End;
End;

Function ShortenedField(Event: TJSONObject; Const FieldName: String): String;
Begin
  If Event.Find(FieldName) = Nil Then
    Result := ''
  Else
    Result := CaptureShortenedJson(Event.Find(FieldName).AsJSON);
End;

Procedure SummariseBlocks(Const Role: String; Content: TJSONArray; Summary: TStrings);
Var
  I: Integer;
  Block: TJSONObject;
  BlockType: String;
Begin
  For I := 0 To Content.Count - 1 Do
    Begin
      If Not (Content.Items[I] Is TJSONObject) Then
        Continue;
      Block := TJSONObject(Content.Items[I]);
      BlockType := Block.Get('type', '');
      If BlockType = 'text' Then
        Summary.Add('- ' + Role + ' text: ' + Block.Get('text', ''))
      Else If BlockType = 'thinking' Then
        Summary.Add('- ' + Role + ' thinking (not shown)')
      Else
        Summary.Add('- ' + Role + ' ' + BlockType + ': `' + CaptureShortenedJson(Block.AsJSON) + '`');
    End;
End;

Procedure SummariseEvent(Event: TJSONObject; Summary: TStrings);
Var
  EventType, Subtype: String;
  MessageObject: TJSONObject;
Begin
  EventType := Event.Get('type', '');
  Subtype := Event.Get('subtype', '');
  If (EventType = 'system') And (Subtype = 'init') Then
    Summary.Add('- init: session ' + Event.Get('session_id', '') + ', model ' + Event.Get('model', '') + ', version ' +
      Event.Get('claude_code_version', '') + ', mcp_servers `' + ShortenedField(Event, 'mcp_servers') + '`')
  Else If ((EventType = 'assistant') Or (EventType = 'user')) And (Event.Find('message') Is TJSONObject) Then
    Begin
      MessageObject := TJSONObject(Event.Find('message'));
      If MessageObject.Find('content') Is TJSONArray Then
        SummariseBlocks(EventType, TJSONArray(MessageObject.Find('content')), Summary)
      Else
        Summary.Add('- ' + EventType + ': `' + CaptureShortenedJson(MessageObject.AsJSON) + '`');
      If Event.Find('tool_use_result') <> Nil Then
        Summary.Add('- ' + EventType + ' tool_use_result: `' + CaptureShortenedJson(Event.Find('tool_use_result').AsJSON) + '`');
    End
  Else If EventType = 'result' Then
    Begin
      Summary.Add('- result: subtype ' + Subtype + ', is_error ' + BoolToStr(Event.Get('is_error', False), 'true', 'false') +
        ', result: ' + Event.Get('result', ''));
      If Event.Find('errors') <> Nil Then
        Summary.Add('- result errors: `' + Event.Find('errors').AsJSON + '`');
      If Event.Find('usage') Is TJSONObject Then
        Summary.Add('- result usage: `' + Event.Find('usage').AsJSON + '`');
    End
  Else If Subtype <> '' Then
    Summary.Add('- ' + EventType + '/' + Subtype)
  Else
    Summary.Add('- ' + EventType);
End;

Function CaptureStreamSummary(Const StreamText: String): String;
Var
  Lines, Summary: TStringList;
  Event: TJSONObject;
  I: Integer;
Begin
  Lines := TStringList.Create;
  Summary := TStringList.Create;
  Try
    Lines.Text := StreamText;
    For I := 0 To Lines.Count - 1 Do
      Begin
        If Trim(Lines[I]) = '' Then
          Continue;
        Event := ParseEvent(Lines[I]);
        If Not Assigned(Event) Then
          Begin
            Summary.Add('- not JSON: ' + Copy(Lines[I], 1, 300));
            Continue;
          End;
        Try
          SummariseEvent(Event, Summary);
        Finally
          Event.Free;
        End;
      End;
    Result := Summary.Text;
  Finally
    Summary.Free;
    Lines.Free;
  End;
End;

Function RunCaptureProcess(Const Executable, WorkDir: String; Args, Environment: TStrings; Const InputText: String;
  KeepInputOpen: Boolean; OpenWaitMs, TimeoutMs: Integer): TCaptureRun;
Const
  ChunkSize = 65536;
Var
  Run: TCaptureRun;
  Child: TProcess;
  StartTick: QWord;
  InputOpen, ReadSome: Boolean;
  Offset, Count: Integer;

  Function Elapsed: Double;
  Begin
    Result := (GetTickCount64 - StartTick) / 1000;
  End;

  Function DrainStream(Source: TInputPipeStream; Var Target: String): Boolean;
  Var
    Buffer: Array[0..ChunkSize - 1] Of Char;
    Got: LongInt;
    Piece: String;
  Begin
    Result := False;
    While Source.NumBytesAvailable > 0 Do
      Begin
        Got := Source.Read(Buffer, SizeOf(Buffer));
        If Got <= 0 Then
          Break;
        SetString(Piece, PChar(@Buffer[0]), Got);
        Target := Target + Piece;
        Result := True;
      End;
  End;

  Function Drain: Boolean;
  Begin
    Result := DrainStream(Child.Output, Run.StdoutText);
    Result := DrainStream(Child.Stderr, Run.StderrText) Or Result;
  End;

  Procedure CloseChildInput;
  Begin
    Child.CloseInput;
    InputOpen := False;
    Run.InputClosedSeconds := Elapsed;
  End;

Begin
  Run := Default(TCaptureRun);
  Run.ResultSeconds := -1;
  Run.InputClosedSeconds := -1;
  Run.ExitSeconds := -1;
  Run.ExitCode := -1;
  Child := TProcess.Create(Nil);
  Try
    Child.Executable := Executable;
    If Assigned(Args) Then
      Child.Parameters.Assign(Args);
    If Assigned(Environment) And (Environment.Count > 0) Then
      Child.Environment.Assign(Environment);
    Child.CurrentDirectory := WorkDir;
    Child.Options := [poUsePipes];
    StartTick := GetTickCount64;
    Try
      Child.Execute;
    Except
      On E: EProcess Do
        Begin
          Run.ErrorText := E.Message;
          Exit(Run);
        End;
    End;
    Run.Started := True;
    InputOpen := True;
    { In chunks, reading between them, so a child that writes before it reads all of stdin cannot block on its output. }
    Offset := 1;
    While Offset <= Length(InputText) Do
      Begin
        Count := Min(ChunkSize, Length(InputText) - Offset + 1);
        If Child.Input.Write(InputText[Offset], Count) <> Count Then
          Begin
            Run.ErrorText := 'stdin was closed by the child after ' + IntToStr(Offset - 1) + ' of ' +
              IntToStr(Length(InputText)) + ' bytes.';
            Break;
          End;
        Inc(Offset, Count);
        Drain;
      End;
    If Not KeepInputOpen Then
      CloseChildInput;
    While True Do
      Begin
        ReadSome := Drain;
        If (Run.ResultSeconds < 0) And (Pos('"type":"result"', Run.StdoutText) > 0) Then
          Run.ResultSeconds := Elapsed;
        If InputOpen And (Run.ResultSeconds >= 0) And ((Elapsed - Run.ResultSeconds) * 1000 >= OpenWaitMs) Then
          CloseChildInput;
        If Not Child.Running Then
          Break;
        If Elapsed * 1000 >= TimeoutMs Then
          Begin
            Run.TimedOut := True;
            Child.Terminate(124);
            Break;
          End;
        If Not ReadSome Then
          Sleep(20);
      End;
    Run.ExitSeconds := Elapsed;
    Run.ExitedWithInputOpen := InputOpen And Not Run.TimedOut;
    If InputOpen Then
      Child.CloseInput;
    Child.WaitOnExit;
    While Drain Do
      ;
    If (Run.ResultSeconds < 0) And (Pos('"type":"result"', Run.StdoutText) > 0) Then
      Run.ResultSeconds := Run.ExitSeconds;
    Run.ExitCode := Child.ExitCode;
  Finally
    Child.Free;
  End;
  Result := Run;
End;

Procedure AppendLogLine(Const LogFile, Line: String);
Var
  Stream: TFileStream;
  Text: String;
Begin
  If LogFile = '' Then
    Exit;
  If FileExists(LogFile) Then
    Begin
      Stream := TFileStream.Create(LogFile, fmOpenWrite Or fmShareDenyNone);
      Stream.Seek(0, soEnd);
    End
  Else
    Stream := TFileStream.Create(LogFile, fmCreate);
  Try
    Text := Line + LineEnding;
    Stream.WriteBuffer(Text[1], Length(Text));
  Finally
    Stream.Free;
  End;
End;

Procedure RunCaptureMCPServer(Const LogFile: String);
Var
  Line, Reply: String;
Begin
  While Not EOF(Input) Do
    Begin
      ReadLn(Input, Line);
      If Trim(Line) = '' Then
        Continue;
      AppendLogLine(LogFile, 'request ' + Line);
      If Not CaptureMCPReply(Line, Reply) Then
        Continue;
      WriteLn(Output, Reply);
      Flush(Output);
      AppendLogLine(LogFile, 'reply   ' + CaptureShortenedJson(Reply));
    End;
End;

End.
