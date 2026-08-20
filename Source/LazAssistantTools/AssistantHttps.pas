Unit AssistantHttps;

{ HTTPS helpers for LazAssistantTools: OpenSSL bootstrap + WinINet fallback on Windows
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

{ Load OpenSSL (1.1 / 3.x DLL names and common search paths). Safe to call repeatedly. }
Function EnsureOpenSSLReady(Out ErrorText: String): Boolean;
{ Convenience: empty ErrorText when True. }
Function EnsureOpenSSLReady: Boolean;

{ HTTPS GET. Prefers WinINet on Windows (no OpenSSL); otherwise TFPHTTPClient.
  ExtraHeaders is optional "Name: value" lines (with or without CRLF). }
Function HttpsGet(Const Url: String; Out ResponseBody: String; Out StatusCode: Integer;
  Out ErrorText: String; Const ExtraHeaders: String = ''): Boolean;

{ HTTPS POST application/x-www-form-urlencoded. }
Function HttpsPostForm(Const Url, FormBody: String; Out ResponseBody: String;
  Out StatusCode: Integer; Out ErrorText: String): Boolean;

{ HTTPS POST JSON body (optional Authorization bearer, etc.). }
Function HttpsPostJson(Const Url, JsonBody, ExtraHeaders: String;
  Out ResponseBody: String; Out StatusCode: Integer; Out ErrorText: String): Boolean;

Type
  { Streaming POST (SSE). OnChunk receives decoded UTF-8 text chunks as they arrive. }
  THttpsChunkEvent = Procedure(Const Chunk: String) Of Object;
  THttpsStopCheck = Function: Boolean Of Object;

  { Opaque cancel handle for in-flight WinINet streams. }
  THttpsStreamControl = Class
  Private
    FLock: TRTLCriticalSection;
    FSession: Pointer;
    FConnect: Pointer;
    FRequest: Pointer;
    FClosedByAbort: Boolean;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure AssignHandles(Session, Connect, Request: Pointer);
    Procedure ClearHandles;
    Procedure Abort;
    { True after Abort closed native handles — caller must not close them again. }
    Property ClosedByAbort: Boolean Read FClosedByAbort;
  End;

{ Streaming JSON POST. On Windows uses WinINet (no OpenSSL). Elsewhere OpenSSL/TFPHTTPClient. }
Function HttpsPostJsonStream(Const Url, JsonBody, ExtraHeaders: String;
  OnChunk: THttpsChunkEvent; ShouldStop: THttpsStopCheck; Control: THttpsStreamControl;
  Out StatusCode: Integer; Out ErrorText: String): Boolean;

{ User-facing hint when OpenSSL is missing (Windows). }
Function OpenSSLMissingHint: String;
Function UrlIsHttps(Const Url: String): Boolean;

Implementation

Uses
  {$IFDEF WINDOWS}
  Windows, WinInet,
  {$ENDIF}
  Forms, fphttpclient, opensslsockets, openssl, WorkflowLog;

Constructor THttpsStreamControl.Create;
Begin
  Inherited Create;
  InitCriticalSection(FLock);
  FSession := Nil;
  FConnect := Nil;
  FRequest := Nil;
  FClosedByAbort := False;
End;

Destructor THttpsStreamControl.Destroy;
Begin
  Abort;
  DoneCriticalSection(FLock);
  Inherited Destroy;
End;

Procedure THttpsStreamControl.AssignHandles(Session, Connect, Request: Pointer);
Begin
  EnterCriticalSection(FLock);
  Try
    FSession := Session;
    FConnect := Connect;
    FRequest := Request;
    FClosedByAbort := False;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure THttpsStreamControl.ClearHandles;
Begin
  EnterCriticalSection(FLock);
  Try
    FSession := Nil;
    FConnect := Nil;
    FRequest := Nil;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure THttpsStreamControl.Abort;
Var
  S, C, R: Pointer;
Begin
  EnterCriticalSection(FLock);
  Try
    R := FRequest;
    C := FConnect;
    S := FSession;
    FRequest := Nil;
    FConnect := Nil;
    FSession := Nil;
    If (R <> Nil) Or (C <> Nil) Or (S <> Nil) Then
      FClosedByAbort := True;
  Finally
    LeaveCriticalSection(FLock);
  End;
  {$IFDEF WINDOWS}
  If R <> Nil Then
    InternetCloseHandle(HINTERNET(R));
  If C <> Nil Then
    InternetCloseHandle(HINTERNET(C));
  If S <> Nil Then
    InternetCloseHandle(HINTERNET(S));
  {$ELSE}
  S := S; C := C; R := R;
  {$ENDIF}
End;

Function UrlIsHttps(Const Url: String): Boolean;
Begin
  Result := SameText(Copy(Trim(Url), 1, 8), 'https://');
End;

Function OpenSSLMissingHint: String;
Begin
  {$IFDEF WINDOWS}
  Result :=
    'Could not load OpenSSL for HTTPS streaming.' + LineEnding +
    'WinINet streaming should be used on Windows; if you still see this message, ' +
    'rebuild LazAssistantTools. Optional: install OpenSSL Light and copy ' +
    'libssl-1_1-x64.dll + libcrypto-1_1-x64.dll next to lazarus.exe.';
  {$ELSE}
  Result :=
    'Could not initialize OpenSSL. Install libssl development packages ' +
    '(e.g. libssl3 / openssl) for your distribution.';
  {$ENDIF}
End;

{$IFDEF WINDOWS}
Function FileExistsNonEmpty(Const Path: String): Boolean;
Begin
  Result := (Path <> '') And FileExists(Path);
End;

Procedure AddSearchDir(Dirs: TStringList; Const Dir: String);
Var
  Clean: String;
Begin
  Clean := ExcludeTrailingPathDelimiter(Trim(Dir));
  If (Clean <> '') And DirectoryExists(Clean) And (Dirs.IndexOf(Clean) < 0) Then
    Dirs.Add(Clean);
End;

{ Preload known OpenSSL DLL pairs so InitSSLInterface's short-name LoadLibrary
  can resolve them. Do not assign openssl.DLLSSLName* — those vars are not
  exported on all FPC/Lazarus builds (e.g. trunk used by Lazarus 4.99). }
Procedure PreloadOpenSslFromDirs;
Const
  {$IFDEF WIN64}
  PairCount = 4;
  SslNames: Array[0..PairCount - 1] Of String = (
    'libssl-1_1-x64.dll', 'libssl-3-x64.dll', 'libssl32.dll', 'ssleay32.dll');
  CryptoNames: Array[0..PairCount - 1] Of String = (
    'libcrypto-1_1-x64.dll', 'libcrypto-3-x64.dll', 'libeay32.dll', 'libeay32.dll');
  {$ELSE}
  PairCount = 4;
  SslNames: Array[0..PairCount - 1] Of String = (
    'libssl-1_1.dll', 'libssl-3.dll', 'libssl32.dll', 'ssleay32.dll');
  CryptoNames: Array[0..PairCount - 1] Of String = (
    'libcrypto-1_1.dll', 'libcrypto-3.dll', 'libeay32.dll', 'libeay32.dll');
  {$ENDIF}
Var
  Dirs: TStringList;
  D, I: Integer;
  SslPath, CryptoPath: String;
  HSsl, HCrypto: HMODULE;
Begin
  Dirs := TStringList.Create;
  Try
    AddSearchDir(Dirs, ExtractFilePath(ParamStr(0)));
    If Assigned(Application) Then
      AddSearchDir(Dirs, ExtractFilePath(Application.ExeName));
    AddSearchDir(Dirs, ExpandFileName(ExtractFilePath(ParamStr(0)) + 'openssl'));
    For D := 0 To Dirs.Count - 1 Do
      For I := 0 To PairCount - 1 Do
        Begin
          SslPath := IncludeTrailingPathDelimiter(Dirs[D]) + SslNames[I];
          CryptoPath := IncludeTrailingPathDelimiter(Dirs[D]) + CryptoNames[I];
          If (Not FileExistsNonEmpty(SslPath)) Or (Not FileExistsNonEmpty(CryptoPath)) Then
            Continue;
          HCrypto := LoadLibrary(PChar(CryptoPath));
          HSsl := LoadLibrary(PChar(SslPath));
          If (HSsl <> 0) And (HCrypto <> 0) Then
            Begin
              WorkflowLogger.Info('AssistantHttps',
                'Preloaded OpenSSL from ' + Dirs[D] + ' (' + SslNames[I] + ')');
              Exit;
            End;
          If HSsl <> 0 Then
            FreeLibrary(HSsl);
          If HCrypto <> 0 Then
            FreeLibrary(HCrypto);
        End;
  Finally
    Dirs.Free;
  End;
End;
{$ENDIF}

Function EnsureOpenSSLReady(Out ErrorText: String): Boolean;
Begin
  ErrorText := '';
  Result := False;
  Try
    If IsSSLloaded Then
      Begin
        Result := True;
        Exit;
      End;
    {$IFDEF WINDOWS}
    PreloadOpenSslFromDirs;
    {$ENDIF}
    Result := InitSSLInterface;
  Except
    On E: Exception Do
      Begin
        ErrorText := E.Message;
        Result := False;
      End;
  End;
  If Result Then
    Exit;
  If ErrorText = '' Then
    ErrorText := OpenSSLMissingHint;
  WorkflowLogger.Warning('AssistantHttps', 'OpenSSL init failed');
End;

Function EnsureOpenSSLReady: Boolean;
Var
  Err: String;
Begin
  Result := EnsureOpenSSLReady(Err);
End;

{$IFDEF WINDOWS}
Function CrackUrlParts(Const Url: String; Out Host, Path: String; Out Port: INTERNET_PORT;
  Out UseHttps: Boolean): Boolean;
Var
  Rest, HostPort: String;
  SlashPos, ColonPos, SchemeEnd: Integer;
Begin
  { Simple URL split — avoids A/W InternetCrackUrl mismatches under UNICODE. }
  Result := False;
  Host := '';
  Path := '/';
  Port := 0;
  UseHttps := False;
  SchemeEnd := Pos('://', Url);
  If SchemeEnd < 1 Then
    Exit;
  UseHttps := SameText(Copy(Url, 1, SchemeEnd - 1), 'https');
  If Not UseHttps Then
    Exit;
  Rest := Copy(Url, SchemeEnd + 3, MaxInt);
  SlashPos := Pos('/', Rest);
  If SlashPos > 0 Then
    Begin
      HostPort := Copy(Rest, 1, SlashPos - 1);
      Path := Copy(Rest, SlashPos, MaxInt);
    End
  Else
    Begin
      HostPort := Rest;
      Path := '/';
    End;
  If HostPort = '' Then
    Exit;
  { strip userinfo if present }
  ColonPos := Pos('@', HostPort);
  If ColonPos > 0 Then
    HostPort := Copy(HostPort, ColonPos + 1, MaxInt);
  { IPv6 in brackets not required for x.ai hosts }
  ColonPos := Pos(':', HostPort);
  If ColonPos > 0 Then
    Begin
      Host := Copy(HostPort, 1, ColonPos - 1);
      Port := INTERNET_PORT(StrToIntDef(Copy(HostPort, ColonPos + 1, MaxInt), 0));
    End
  Else
    Host := HostPort;
  If Port = 0 Then
    If UseHttps Then
      Port := INTERNET_DEFAULT_HTTPS_PORT
    Else
      Port := INTERNET_DEFAULT_HTTP_PORT;
  Result := Host <> '';
End;

Function WinINetRequest(Const Method, Url, ContentType, Body, ExtraHeaders: String;
  Out ResponseBody: String; Out StatusCode: Integer; Out ErrorText: String): Boolean;
Var
  Session, Connect, Request: HINTERNET;
  Host, Path: String;
  Port: INTERNET_PORT;
  UseHttps: Boolean;
  Flags, BytesRead, StatusSize, Index: DWORD;
  StatusBuf: Array[0..31] Of Char;
  Buf: Array[0..8191] Of Byte;
  Headers: String;
  BodyAnsi: RawByteString;
  BodyPtr: Pointer;
  BodyLen: DWORD;
  Raw: RawByteString;
  ReadOk: Boolean;
Begin
  Result := False;
  ResponseBody := '';
  StatusCode := 0;
  ErrorText := '';
  Session := Nil;
  Connect := Nil;
  Request := Nil;
  If Not CrackUrlParts(Url, Host, Path, Port, UseHttps) Then
    Begin
      ErrorText := 'Invalid URL: ' + Url;
      Exit;
    End;

  Session := InternetOpen(PChar('LazAssistantTools/1.0'), INTERNET_OPEN_TYPE_PRECONFIG, Nil, Nil, 0);
  If Session = Nil Then
    Begin
      ErrorText := 'WinINet InternetOpen failed (' + IntToStr(GetLastError) + ')';
      Exit;
    End;
  Try
    Connect := InternetConnect(Session, PChar(Host), Port, Nil, Nil,
      INTERNET_SERVICE_HTTP, 0, 0);
    If Connect = Nil Then
      Begin
        ErrorText := 'WinINet InternetConnect failed (' + IntToStr(GetLastError) + ')';
        Exit;
      End;

    Flags := INTERNET_FLAG_RELOAD Or INTERNET_FLAG_NO_CACHE_WRITE Or INTERNET_FLAG_KEEP_CONNECTION;
    If UseHttps Then
      Flags := Flags Or INTERNET_FLAG_SECURE;

    Request := HttpOpenRequest(Connect, PChar(Method), PChar(Path), Nil, Nil, Nil, Flags, 0);
    If Request = Nil Then
      Begin
        ErrorText := 'WinINet HttpOpenRequest failed (' + IntToStr(GetLastError) + ')';
        Exit;
      End;

    Headers := 'Accept: application/json'#13#10;
    If ContentType <> '' Then
      Headers := Headers + 'Content-Type: ' + ContentType + #13#10;
    If Trim(ExtraHeaders) <> '' Then
      Begin
        Headers := Headers + ExtraHeaders;
        If (Length(Headers) < 2) Or (Copy(Headers, Length(Headers) - 1, 2) <> #13#10) Then
          Headers := Headers + #13#10;
      End;

    { Body is octet stream (ASCII form / UTF-8 JSON). }
    {$IF SIZEOF(CHAR) = 2}
    BodyAnsi := UTF8Encode(Body);
    {$ELSE}
    BodyAnsi := RawByteString(Body);
    {$ENDIF}
    BodyPtr := Nil;
    BodyLen := 0;
    If Length(BodyAnsi) > 0 Then
      Begin
        BodyPtr := @BodyAnsi[1];
        BodyLen := Length(BodyAnsi);
      End;

    If Not HttpSendRequest(Request, PChar(Headers), Length(Headers), BodyPtr, BodyLen) Then
      Begin
        ErrorText := 'WinINet HttpSendRequest failed (' + IntToStr(GetLastError) + ')';
        Exit;
      End;

    FillChar(StatusBuf, SizeOf(StatusBuf), 0);
    StatusSize := SizeOf(StatusBuf);
    Index := 0;
    If HttpQueryInfo(Request, HTTP_QUERY_STATUS_CODE, @StatusBuf[0], StatusSize, Index) Then
      StatusCode := StrToIntDef(string(StatusBuf), 0);

    Raw := '';
    ReadOk := True;
    Repeat
      BytesRead := 0;
      If Not InternetReadFile(Request, @Buf[0], SizeOf(Buf), BytesRead) Then
        Begin
          ReadOk := False;
          ErrorText := 'WinINet InternetReadFile failed (' + IntToStr(GetLastError) + ')';
          Break;
        End;
      If BytesRead = 0 Then
        Break;
      SetLength(Raw, Length(Raw) + Integer(BytesRead));
      Move(Buf[0], Raw[Length(Raw) - Integer(BytesRead) + 1], BytesRead);
    Until False;
    If ReadOk Then
      Begin
        ResponseBody := string(Raw);
        Result := True;
      End;
  Finally
    If Request <> Nil Then
      InternetCloseHandle(Request);
    If Connect <> Nil Then
      InternetCloseHandle(Connect);
    If Session <> Nil Then
      InternetCloseHandle(Session);
  End;
End;
{$ENDIF}

Function HttpsViaFpHttp(Const Method, Url, ContentType, Body, ExtraHeaders: String;
  Out ResponseBody: String; Out StatusCode: Integer; Out ErrorText: String): Boolean;
Var
  Client: TFPHTTPClient;
  BodyStream: TStringStream;
  SslErr, HdrBlock, Line: String;
  Parts: TStringList;
  I, ColonPos: Integer;
Begin
  Result := False;
  ResponseBody := '';
  StatusCode := 0;
  ErrorText := '';
  If Not UrlIsHttps(Url) Then
    Begin
      ErrorText := 'HTTPS URL required.';
      Exit;
    End;
  If SameText(Copy(Url, 1, 8), 'https://') Then
    If Not EnsureOpenSSLReady(SslErr) Then
      Begin
        ErrorText := SslErr;
        Exit;
      End;

  Client := TFPHTTPClient.Create(Nil);
  BodyStream := Nil;
  Parts := Nil;
  Try
    Try
      Client.AllowRedirect := False;
      Client.AddHeader('Accept', 'application/json');
      If ContentType <> '' Then
        Client.AddHeader('Content-Type', ContentType);
      HdrBlock := Trim(ExtraHeaders);
      If HdrBlock <> '' Then
        Begin
          Parts := TStringList.Create;
          Parts.Text := StringReplace(HdrBlock, #13#10, #10, [rfReplaceAll]);
          For I := 0 To Parts.Count - 1 Do
            Begin
              Line := Trim(Parts[I]);
              If Line = '' Then
                Continue;
              ColonPos := Pos(':', Line);
              If ColonPos > 1 Then
                Client.AddHeader(Trim(Copy(Line, 1, ColonPos - 1)),
                  Trim(Copy(Line, ColonPos + 1, MaxInt)));
            End;
        End;
      If SameText(Method, 'POST') Then
        Begin
          BodyStream := TStringStream.Create(Body);
          Client.RequestBody := BodyStream;
          ResponseBody := Client.Post(Url);
        End
      Else
        ResponseBody := Client.Get(Url);
      StatusCode := Client.ResponseStatusCode;
      Result := True;
    Except
      On E: Exception Do
        Begin
          ErrorText := E.Message;
          If (Pos('OpenSSL', ErrorText) > 0) Or (Pos('initialize', LowerCase(ErrorText)) > 0) Then
            ErrorText := OpenSSLMissingHint + LineEnding + '(' + E.Message + ')';
          Result := False;
        End;
    End;
  Finally
    Client.RequestBody := Nil;
    Parts.Free;
    BodyStream.Free;
    Client.Free;
  End;
End;

Function HttpsGet(Const Url: String; Out ResponseBody: String; Out StatusCode: Integer;
  Out ErrorText: String; Const ExtraHeaders: String): Boolean;
Begin
  If Not UrlIsHttps(Url) Then
    Begin
      ResponseBody := '';
      StatusCode := 0;
      ErrorText := 'HTTPS URL required.';
      Result := False;
      Exit;
    End;
  {$IFDEF WINDOWS}
  If WinINetRequest('GET', Url, '', '', ExtraHeaders, ResponseBody, StatusCode, ErrorText) Then
    Begin
      Result := True;
      Exit;
    End;
  {$ENDIF}
  Result := HttpsViaFpHttp('GET', Url, '', '', ExtraHeaders, ResponseBody, StatusCode, ErrorText);
End;

Function HttpsPostForm(Const Url, FormBody: String; Out ResponseBody: String;
  Out StatusCode: Integer; Out ErrorText: String): Boolean;
Begin
  If Not UrlIsHttps(Url) Then
    Begin
      ResponseBody := '';
      StatusCode := 0;
      ErrorText := 'HTTPS URL required.';
      Result := False;
      Exit;
    End;
  {$IFDEF WINDOWS}
  If WinINetRequest('POST', Url, 'application/x-www-form-urlencoded', FormBody, '',
    ResponseBody, StatusCode, ErrorText) Then
    Begin
      Result := True;
      Exit;
    End;
  {$ENDIF}
  Result := HttpsViaFpHttp('POST', Url, 'application/x-www-form-urlencoded', FormBody, '',
    ResponseBody, StatusCode, ErrorText);
End;

Function HttpsPostJson(Const Url, JsonBody, ExtraHeaders: String;
  Out ResponseBody: String; Out StatusCode: Integer; Out ErrorText: String): Boolean;
Begin
  If Not UrlIsHttps(Url) Then
    Begin
      ResponseBody := '';
      StatusCode := 0;
      ErrorText := 'HTTPS URL required.';
      Result := False;
      Exit;
    End;
  {$IFDEF WINDOWS}
  If WinINetRequest('POST', Url, 'application/json', JsonBody, ExtraHeaders,
    ResponseBody, StatusCode, ErrorText) Then
    Begin
      Result := True;
      Exit;
    End;
  {$ENDIF}
  Result := HttpsViaFpHttp('POST', Url, 'application/json', JsonBody, ExtraHeaders,
    ResponseBody, StatusCode, ErrorText);
End;

{$IFDEF WINDOWS}
Function WinINetPostJsonStream(Const Url, JsonBody, ExtraHeaders: String;
  OnChunk: THttpsChunkEvent; ShouldStop: THttpsStopCheck; Control: THttpsStreamControl;
  Out StatusCode: Integer; Out ErrorText: String): Boolean;
Var
  Session, Connect, Request: HINTERNET;
  Host, Path, Headers: String;
  Port: INTERNET_PORT;
  UseHttps: Boolean;
  Flags, BytesRead, StatusSize, Index: DWORD;
  StatusBuf: Array[0..31] Of Char;
  Buf: Array[0..8191] Of Byte;
  BodyAnsi: RawByteString;
  BodyPtr: Pointer;
  BodyLen: DWORD;
  ChunkRaw, Utf8Carry: RawByteString;
  ChunkText: String;
  Stopped: Boolean;
  ReadOk: Boolean;
  CompleteLen, I, Need: Integer;
  B0: Byte;
Begin
  Result := False;
  StatusCode := 0;
  ErrorText := '';
  Session := Nil;
  Connect := Nil;
  Request := Nil;
  Utf8Carry := '';
  If Not CrackUrlParts(Url, Host, Path, Port, UseHttps) Then
    Begin
      ErrorText := 'Invalid URL: ' + Url;
      Exit;
    End;
  If Assigned(ShouldStop) And ShouldStop() Then
    Begin
      ErrorText := 'Cancelled.';
      Exit;
    End;

  Session := InternetOpen(PChar('LazAssistantTools/1.0'), INTERNET_OPEN_TYPE_PRECONFIG, Nil, Nil, 0);
  If Session = Nil Then
    Begin
      ErrorText := 'WinINet InternetOpen failed (' + IntToStr(GetLastError) + ')';
      Exit;
    End;
  Try
    Connect := InternetConnect(Session, PChar(Host), Port, Nil, Nil, INTERNET_SERVICE_HTTP, 0, 0);
    If Connect = Nil Then
      Begin
        ErrorText := 'WinINet InternetConnect failed (' + IntToStr(GetLastError) + ')';
        Exit;
      End;

    Flags := INTERNET_FLAG_RELOAD Or INTERNET_FLAG_NO_CACHE_WRITE Or INTERNET_FLAG_KEEP_CONNECTION Or
      INTERNET_FLAG_NO_UI;
    If UseHttps Then
      Flags := Flags Or INTERNET_FLAG_SECURE;

    Request := HttpOpenRequest(Connect, PChar('POST'), PChar(Path), Nil, Nil, Nil, Flags, 0);
    If Request = Nil Then
      Begin
        ErrorText := 'WinINet HttpOpenRequest failed (' + IntToStr(GetLastError) + ')';
        Exit;
      End;

    If Assigned(Control) Then
      Control.AssignHandles(Pointer(Session), Pointer(Connect), Pointer(Request));

    Headers := 'Accept: text/event-stream'#13#10 +
      'Content-Type: application/json'#13#10;
    If Trim(ExtraHeaders) <> '' Then
      Begin
        Headers := Headers + ExtraHeaders;
        If (Length(Headers) < 2) Or (Copy(Headers, Length(Headers) - 1, 2) <> #13#10) Then
          Headers := Headers + #13#10;
      End;

    {$IF SIZEOF(CHAR) = 2}
    BodyAnsi := UTF8Encode(JsonBody);
    {$ELSE}
    BodyAnsi := RawByteString(JsonBody);
    {$ENDIF}
    BodyPtr := Nil;
    BodyLen := 0;
    If Length(BodyAnsi) > 0 Then
      Begin
        BodyPtr := @BodyAnsi[1];
        BodyLen := Length(BodyAnsi);
      End;

    If Not HttpSendRequest(Request, PChar(Headers), Length(Headers), BodyPtr, BodyLen) Then
      Begin
        ErrorText := 'WinINet HttpSendRequest failed (' + IntToStr(GetLastError) + ')';
        Exit;
      End;

    FillChar(StatusBuf, SizeOf(StatusBuf), 0);
    StatusSize := SizeOf(StatusBuf);
    Index := 0;
    If HttpQueryInfo(Request, HTTP_QUERY_STATUS_CODE, @StatusBuf[0], StatusSize, Index) Then
      StatusCode := StrToIntDef(string(StatusBuf), 0);

    Stopped := False;
    ReadOk := True;
    Repeat
      If Assigned(ShouldStop) And ShouldStop() Then
        Begin
          Stopped := True;
          Break;
        End;
      BytesRead := 0;
      If Not InternetReadFile(Request, @Buf[0], SizeOf(Buf), BytesRead) Then
        Begin
          ReadOk := False;
          ErrorText := 'WinINet InternetReadFile failed (' + IntToStr(GetLastError) + ')';
          Break;
        End;
      If BytesRead = 0 Then
        Break;
      { Append to any incomplete UTF-8 sequence from the previous read. }
      SetLength(ChunkRaw, Length(Utf8Carry) + Integer(BytesRead));
      If Length(Utf8Carry) > 0 Then
        Move(Utf8Carry[1], ChunkRaw[1], Length(Utf8Carry));
      Move(Buf[0], ChunkRaw[Length(Utf8Carry) + 1], BytesRead);
      Utf8Carry := '';
      { Keep trailing incomplete multi-byte sequence for the next chunk. }
      CompleteLen := Length(ChunkRaw);
      I := CompleteLen;
      While I >= 1 Do
        Begin
          B0 := Byte(ChunkRaw[I]);
          If B0 < $80 Then
            Break; { ASCII — sequence complete through I }
          If (B0 And $C0) <> $80 Then
            Begin
              { Lead byte of a multi-byte sequence at I }
              If (B0 And $E0) = $C0 Then
                Need := 2
              Else If (B0 And $F0) = $E0 Then
                Need := 3
              Else If (B0 And $F8) = $F0 Then
                Need := 4
              Else
                Need := 1;
              If I + Need - 1 > CompleteLen Then
                Begin
                  Utf8Carry := Copy(ChunkRaw, I, CompleteLen - I + 1);
                  CompleteLen := I - 1;
                End;
              Break;
            End;
          Dec(I); { continuation byte — look for lead }
        End;
      If CompleteLen < 1 Then
        Continue;
      SetLength(ChunkRaw, CompleteLen);
      {$IF SIZEOF(CHAR) = 2}
      ChunkText := UTF8ToString(ChunkRaw);
      {$ELSE}
      ChunkText := string(ChunkRaw);
      {$ENDIF}
      If Assigned(OnChunk) And (ChunkText <> '') Then
        OnChunk(ChunkText);
    Until False;

    If Stopped Then
      Begin
        ErrorText := 'Cancelled.';
        Result := False;
      End
    Else If ReadOk Then
      Result := True;
  Finally
    If Assigned(Control) And Control.ClosedByAbort Then
      Control.ClearHandles
    Else
      Begin
        If Assigned(Control) Then
          Control.ClearHandles;
        If Request <> Nil Then
          InternetCloseHandle(Request);
        If Connect <> Nil Then
          InternetCloseHandle(Connect);
        If Session <> Nil Then
          InternetCloseHandle(Session);
      End;
  End;
End;
{$ENDIF}

Function HttpsPostJsonStream(Const Url, JsonBody, ExtraHeaders: String;
  OnChunk: THttpsChunkEvent; ShouldStop: THttpsStopCheck; Control: THttpsStreamControl;
  Out StatusCode: Integer; Out ErrorText: String): Boolean;
Var
  Client: TFPHTTPClient;
  BodyStream: TStringStream;
  OutStream: TMemoryStream;
  SslErr, Auth: String;
  Chunk: String;
  N, ColonPos: Integer;
  Buf: Array[0..8191] Of Byte;
Begin
  Result := False;
  StatusCode := 0;
  ErrorText := '';
  If Not UrlIsHttps(Url) Then
    Begin
      ErrorText := 'HTTPS URL required.';
      Exit;
    End;
  {$IFDEF WINDOWS}
  { Prefer WinINet so streamed chat works without OpenSSL DLLs. }
  Result := WinINetPostJsonStream(Url, JsonBody, ExtraHeaders, OnChunk, ShouldStop, Control,
    StatusCode, ErrorText);
  Exit;
  {$ENDIF}

  If SameText(Copy(Url, 1, 8), 'https://') And (Not EnsureOpenSSLReady(SslErr)) Then
    Begin
      ErrorText := SslErr;
      Exit;
    End;

  Client := TFPHTTPClient.Create(Nil);
  BodyStream := TStringStream.Create(JsonBody);
  OutStream := TMemoryStream.Create;
  Try
    Try
      Client.AllowRedirect := False;
      Client.AddHeader('Content-Type', 'application/json');
      Client.AddHeader('Accept', 'text/event-stream');
      Auth := Trim(ExtraHeaders);
      If Auth <> '' Then
        Begin
          ColonPos := Pos(':', Auth);
          If ColonPos > 1 Then
            Client.AddHeader(Trim(Copy(Auth, 1, ColonPos - 1)),
              Trim(Copy(Auth, ColonPos + 1, MaxInt)));
        End;
      Client.RequestBody := BodyStream;
      Client.HTTPMethod('POST', Url, OutStream, []);
      StatusCode := Client.ResponseStatusCode;
      OutStream.Position := 0;
      While OutStream.Position < OutStream.Size Do
        Begin
          If Assigned(ShouldStop) And ShouldStop() Then
            Begin
              ErrorText := 'Cancelled.';
              Exit;
            End;
          N := OutStream.Read(Buf[0], SizeOf(Buf));
          If N <= 0 Then
            Break;
          SetLength(Chunk, N);
          Move(Buf[0], Chunk[1], N);
          If Assigned(OnChunk) Then
            OnChunk(Chunk);
        End;
      Result := True;
    Except
      On E: Exception Do
        Begin
          ErrorText := E.Message;
          If (Pos('OpenSSL', ErrorText) > 0) Or (Pos('initialize', LowerCase(ErrorText)) > 0) Then
            ErrorText := OpenSSLMissingHint + LineEnding + '(' + E.Message + ')';
        End;
    End;
  Finally
    Client.RequestBody := Nil;
    OutStream.Free;
    BodyStream.Free;
    Client.Free;
  End;
End;

End.
