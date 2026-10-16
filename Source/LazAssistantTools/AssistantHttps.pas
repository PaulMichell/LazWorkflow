Unit AssistantHttps;

{ HTTPS helpers for LazAssistantTools: OpenSSL bootstrap + WinINet fallback on Windows
  (c) 2026 Michell Computing.

  Size note: exceeds the 1000 line preference. OpenSSL bootstrap, WinINet, and
  the fpHTTP path are one transport with no meaningful partition.
  Reviewed 2026-10-16: a bounded byte GET stays on this transport so an image
  download does not grow a second client. Linux and WinINet share one
  incomplete-UTF-8 carry so a split character is not concatenated. }

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
{ One HTTPS GET of raw bytes. Does not follow a redirect. MaxBytes 0 stores the whole body.
  A larger body fails and leaves Data empty. }
Function HttpsGetBytes(Const Url: String; Out Data: TBytes; Out StatusCode: Integer;
  Out ErrorText: String; Const ExtraHeaders: String = ''; IOTimeoutMs: Integer = 0;
  MaxBytes: Integer = 0): Boolean;

{ HTTPS POST application/x-www-form-urlencoded. }
Function HttpsPostForm(Const Url, FormBody: String; Out ResponseBody: String;
  Out StatusCode: Integer; Out ErrorText: String): Boolean;

{ HTTPS POST JSON body (optional Authorization bearer, etc.).
  IOTimeoutMs 0 keeps the chat default. A positive value bounds this call. }
Function HttpsPostJson(Const Url, JsonBody, ExtraHeaders: String;
  Out ResponseBody: String; Out StatusCode: Integer; Out ErrorText: String;
  IOTimeoutMs: Integer = 0): Boolean;

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
    FHttpClient: TObject;
    FResponseRetryAfter: String;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure AssignHandles(Session, Connect, Request: Pointer);
    Procedure AssignHttpClient(Client: TObject);
    Procedure ClearHandles;
    { True if the caller now owns the native handles and must close them. }
    Function StealNativeHandles(Out Session, Connect, Request: Pointer): Boolean;
    Procedure Abort;
    { True after Abort closed native handles — caller must not close them again. }
    Property ClosedByAbort: Boolean Read FClosedByAbort;
    { Response Retry-After, when the transport saw one. Empty if absent. }
    Property ResponseRetryAfter: String Read FResponseRetryAfter Write FResponseRetryAfter;
  End;

{ Streaming JSON POST. On Windows uses WinINet (no OpenSSL). Elsewhere OpenSSL/TFPHTTPClient. }
Function HttpsPostJsonStream(Const Url, JsonBody, ExtraHeaders: String;
  OnChunk: THttpsChunkEvent; ShouldStop: THttpsStopCheck; Control: THttpsStreamControl;
  Out StatusCode: Integer; Out ErrorText: String): Boolean;

{ User-facing hint when OpenSSL is missing (Windows). }
Function OpenSSLMissingHint: String;
Function UrlIsHttps(Const Url: String): Boolean;
{ Extract only a bounded provider error message, not a raw response/request dump. }
Function HttpsResponseErrorMessage(Const Body: String): String;

{ Complete UTF-8 characters from Pending. A trailing incomplete sequence is returned in Remainder
  and must be prepended to the next socket read. Concatenating that tail as a UTF-8 string makes
  the string manager read past the allocation. }
Function CompleteUtf8Chunk(Const Pending: RawByteString; Out Remainder: RawByteString): String;

Implementation

Uses
  {$IFDEF WINDOWS}
  Windows, WinInet,
  {$ENDIF}
  Forms, fphttpclient, opensslsockets, openssl, WorkflowLog, fpjson, jsonparser;

{$IFDEF WINDOWS}
Type
  TBytesPointer = ^TBytes;
{$ENDIF}

Type
  TBoundedMemoryStream = Class(TMemoryStream)
  Public
    MaxBytes: Int64;
    Exceeded: Boolean;
    Function Write(Const Buffer; Count: LongInt): LongInt; Override;
  End;

  THttpsChunkStream = Class(TStream)
  Private
    FOnChunk: THttpsChunkEvent;
    FShouldStop: THttpsStopCheck;
    FUtf8Carry: RawByteString;
  Public
    Constructor Create(OnChunk: THttpsChunkEvent; ShouldStop: THttpsStopCheck);
    Function Write(Const Buffer; Count: LongInt): LongInt; Override;
    Function Seek(Const Offset: Int64; Origin: TSeekOrigin): Int64; Override;
  End;

Function TBoundedMemoryStream.Write(Const Buffer; Count: LongInt): LongInt;
Begin
  If (MaxBytes > 0) And (Size + Count > MaxBytes) Then
    Begin
      Exceeded := True;
      Exit(0);
    End;
  Result := Inherited Write(Buffer, Count);
End;

Function HttpsResponseErrorMessage(Const Body: String): String;
Var Data, Node: TJSONData;
Begin
  Result := '';
  Data := Nil;
  Try
    Try
      Data := GetJSON(Body);
      If Not (Data Is TJSONObject) Then Exit;
      Node := Data.FindPath('error.message');
      If Not Assigned(Node) Then Node := TJSONObject(Data).Find('message');
      If Not Assigned(Node) Then Node := TJSONObject(Data).Find('error');
      If Assigned(Node) And (Node.JSONType = jtString) Then
        Result := Copy(Trim(Node.AsString), 1, 1000);
    Except
      { HTML proxy errors, truncated bodies and non-JSON payloads have no safe
        structured detail. The caller still reports the HTTP status. }
      Result := '';
    End;
  Finally Data.Free; End;
End;

Constructor THttpsChunkStream.Create(OnChunk: THttpsChunkEvent; ShouldStop: THttpsStopCheck);
Begin
  Inherited Create;
  FOnChunk := OnChunk;
  FShouldStop := ShouldStop;
End;

Function THttpsChunkStream.Seek(Const Offset: Int64; Origin: TSeekOrigin): Int64;
Begin
  Result := 0;
End;

Function CompleteUtf8Chunk(Const Pending: RawByteString; Out Remainder: RawByteString): String;
Var
  CompleteLen, Index, Need: Integer;
  Lead: Byte;
Begin
  Remainder := '';
  Result := '';
  If Length(Pending) = 0 Then
    Exit;
  CompleteLen := Length(Pending);
  Index := CompleteLen;
  While Index >= 1 Do
    Begin
      Lead := Byte(Pending[Index]);
      If Lead < $80 Then
        Break;
      If (Lead And $C0) <> $80 Then
        Begin
          If (Lead And $E0) = $C0 Then
            Need := 2
          Else If (Lead And $F0) = $E0 Then
            Need := 3
          Else If (Lead And $F8) = $F0 Then
            Need := 4
          Else
            Need := 1;
          If Index + Need - 1 > CompleteLen Then
            Begin
              Remainder := Copy(Pending, Index, CompleteLen - Index + 1);
              CompleteLen := Index - 1;
            End;
          Break;
        End;
      Dec(Index);
    End;
  If CompleteLen < 1 Then
    Exit;
  SetLength(Result, CompleteLen);
  Move(Pending[1], Result[1], CompleteLen);
  { Tag without converting. The prefix is already complete UTF-8. }
  SetCodePage(RawByteString(Result), CP_UTF8, False);
End;

Function THttpsChunkStream.Write(Const Buffer; Count: LongInt): LongInt;
Var
  Pending: RawByteString;
  Chunk: String;
Begin
  Result := Count;
  If Count <= 0 Then
    Exit;
  If Assigned(FShouldStop) And FShouldStop() Then
    Raise EAbort.Create('Cancelled');
  SetLength(Pending, Length(FUtf8Carry) + Count);
  If Length(FUtf8Carry) > 0 Then
    Move(FUtf8Carry[1], Pending[1], Length(FUtf8Carry));
  Move(Buffer, Pending[Length(FUtf8Carry) + 1], Count);
  { Hold a character the socket split. The callback concatenates every chunk. }
  Chunk := CompleteUtf8Chunk(Pending, FUtf8Carry);
  If Assigned(FOnChunk) And (Chunk <> '') Then
    FOnChunk(Chunk);
End;

Constructor THttpsStreamControl.Create;
Begin
  Inherited Create;
  InitCriticalSection(FLock);
  FSession := Nil;
  FConnect := Nil;
  FRequest := Nil;
  FHttpClient := Nil;
  FClosedByAbort := False;
  FResponseRetryAfter := '';
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

Procedure THttpsStreamControl.AssignHttpClient(Client: TObject);
Begin
  EnterCriticalSection(FLock);
  Try
    FHttpClient := Client;
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
    FHttpClient := Nil;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function THttpsStreamControl.StealNativeHandles(Out Session, Connect, Request: Pointer): Boolean;
Begin
  EnterCriticalSection(FLock);
  Try
    If FClosedByAbort Then
      Begin
        Session := Nil;
        Connect := Nil;
        Request := Nil;
        Result := False;
        Exit;
      End;
    Session := FSession;
    Connect := FConnect;
    Request := FRequest;
    FSession := Nil;
    FConnect := Nil;
    FRequest := Nil;
    Result := (Session <> Nil) Or (Connect <> Nil) Or (Request <> Nil);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure THttpsStreamControl.Abort;
Var
  S, C, R: Pointer;
  HttpClient: TObject;
Begin
  EnterCriticalSection(FLock);
  Try
    R := FRequest;
    C := FConnect;
    S := FSession;
    FRequest := Nil;
    FConnect := Nil;
    FSession := Nil;
    HttpClient := FHttpClient;
    FHttpClient := Nil;
    If (R <> Nil) Or (C <> Nil) Or (S <> Nil) Or Assigned(HttpClient) Then
      FClosedByAbort := True;
    { Terminate while the lock is held so the worker cannot Free the client
      until the flag is set. Terminate itself only sets a stop flag. }
    If Assigned(HttpClient) Then
      Try
        TFPHTTPClient(HttpClient).Terminate;
      Except
      End;
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
  Out ResponseBody: String; Out StatusCode: Integer; Out ErrorText: String;
  Out RequestSent: Boolean; IOTimeoutMs: Integer = 0; NoRedirect: Boolean = False;
  CaptureBytes: TBytesPointer = Nil; Const AcceptValue: String = 'application/json';
  MaxBytes: Integer = 0): Boolean;
Var
  Session, Connect, Request: HINTERNET;
  Host, Path: String;
  Port: INTERNET_PORT;
  UseHttps: Boolean;
  Flags, BytesRead, StatusSize, Index, Timeout: DWORD;
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
  RequestSent := False;
  Session := Nil;
  Connect := Nil;
  Request := Nil;
  If Assigned(CaptureBytes) Then
    SetLength(CaptureBytes^, 0);
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
  If IOTimeoutMs > 0 Then
    Begin
      Timeout := DWORD(IOTimeoutMs);
      { INTERNET_OPTION_CONNECT_TIMEOUT, SEND_TIMEOUT, and RECEIVE_TIMEOUT. }
      InternetSetOption(Session, 2, @Timeout, SizeOf(Timeout));
      InternetSetOption(Session, 5, @Timeout, SizeOf(Timeout));
      InternetSetOption(Session, 6, @Timeout, SizeOf(Timeout));
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
    If NoRedirect Then
      Flags := Flags Or $40000000; { INTERNET_FLAG_NO_AUTO_REDIRECT: one request, then stop. }

    Request := HttpOpenRequest(Connect, PChar(Method), PChar(Path), Nil, Nil, Nil, Flags, 0);
    If Request = Nil Then
      Begin
        ErrorText := 'WinINet HttpOpenRequest failed (' + IntToStr(GetLastError) + ')';
        Exit;
      End;

    If AcceptValue = '' Then
      Headers := 'Accept: */*'#13#10
    Else
      Headers := 'Accept: ' + AcceptValue + #13#10;
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

    { Once HttpSendRequest is invoked the body may already be in flight. }
    RequestSent := True;
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
      If (MaxBytes > 0) And (Length(Raw) + Integer(BytesRead) > MaxBytes) Then
        Begin
          ErrorText := 'Response exceeded the size ceiling.';
          ReadOk := False;
          Break;
        End;
      SetLength(Raw, Length(Raw) + Integer(BytesRead));
      Move(Buf[0], Raw[Length(Raw) - Integer(BytesRead) + 1], BytesRead);
    Until False;
    If ReadOk Then
      Begin
        If Assigned(CaptureBytes) Then
          Begin
            SetLength(CaptureBytes^, Length(Raw));
            If Length(Raw) > 0 Then
              Move(Raw[1], CaptureBytes^[0], Length(Raw));
          End;
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
  Out ResponseBody: String; Out StatusCode: Integer; Out ErrorText: String;
  IOTimeoutMs: Integer = 0): Boolean;
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
      Client.ConnectTimeout := 15000;
      If IOTimeoutMs > 0 Then
        Client.IOTimeout := IOTimeoutMs
      Else
        Client.IOTimeout := 120000;
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

Procedure ApplyExtraHeaders(Client: TFPHTTPClient; Const ExtraHeaders: String);
Var
  Parts: TStringList;
  I, ColonPos: Integer;
  HdrBlock, Line: String;
Begin
  HdrBlock := Trim(ExtraHeaders);
  If HdrBlock = '' Then
    Exit;
  Parts := TStringList.Create;
  Try
    Parts.Text := StringReplace(HdrBlock, #13#10, #10, [rfReplaceAll]);
    For I := 0 To Parts.Count - 1 Do
      Begin
        Line := Trim(Parts[I]);
        If Line = '' Then
          Continue;
        ColonPos := Pos(':', Line);
        If ColonPos > 1 Then
          Client.AddHeader(Trim(Copy(Line, 1, ColonPos - 1)), Trim(Copy(Line, ColonPos + 1, MaxInt)));
      End;
  Finally
    Parts.Free;
  End;
End;

Function CopyBoundedBytes(Stream: TBoundedMemoryStream; MaxBytes: Integer; Out Data: TBytes;
  Out ErrorText: String): Boolean;
Begin
  SetLength(Data, 0);
  ErrorText := '';
  If Stream.Exceeded Or ((MaxBytes > 0) And (Stream.Size > MaxBytes)) Then
    Begin
      ErrorText := 'Response exceeded the size ceiling.';
      Exit(False);
    End;
  SetLength(Data, Stream.Size);
  If Stream.Size > 0 Then
    Begin
      Stream.Position := 0;
      Stream.ReadBuffer(Data[0], Stream.Size);
    End;
  Result := True;
End;

Function HttpsGetBytes(Const Url: String; Out Data: TBytes; Out StatusCode: Integer;
  Out ErrorText: String; Const ExtraHeaders: String; IOTimeoutMs: Integer; MaxBytes: Integer): Boolean;
Var
  Client: TFPHTTPClient;
  Stream: TBoundedMemoryStream;
  SslErr: String;
  GotResponse: Boolean;
  {$IFDEF WINDOWS}
  RequestSent: Boolean;
  IgnoredBody: String;
  {$ENDIF}
Begin
  SetLength(Data, 0);
  StatusCode := 0;
  ErrorText := '';
  Result := False;
  If Not UrlIsHttps(Url) Then
    Begin
      ErrorText := 'HTTPS URL required.';
      Exit;
    End;
  {$IFDEF WINDOWS}
  RequestSent := False;
  If WinINetRequest('GET', Url, '', '', ExtraHeaders, IgnoredBody, StatusCode, ErrorText, RequestSent,
    IOTimeoutMs, True, @Data, '*/*', MaxBytes) Then
    Exit(True);
  { The request already left. A second client would be a second download. }
  If RequestSent Then
    Exit(False);
  {$ENDIF}
  If Not EnsureOpenSSLReady(SslErr) Then
    Begin
      ErrorText := SslErr;
      Exit;
    End;
  Client := TFPHTTPClient.Create(Nil);
  Stream := TBoundedMemoryStream.Create;
  Try
    Stream.MaxBytes := MaxBytes;
    GotResponse := False;
    Try
      Client.ConnectTimeout := 15000;
      If IOTimeoutMs > 0 Then
        Client.IOTimeout := IOTimeoutMs
      Else
        Client.IOTimeout := 60000;
      Client.AllowRedirect := False;
      Client.AddHeader('Accept', '*/*');
      ApplyExtraHeaders(Client, ExtraHeaders);
      Client.Get(Url, Stream);
      StatusCode := Client.ResponseStatusCode;
      GotResponse := True;
    Except
      On E: Exception Do
        Begin
          StatusCode := Client.ResponseStatusCode;
          ErrorText := E.Message;
          If (Pos('OpenSSL', ErrorText) > 0) Or (Pos('initialize', LowerCase(ErrorText)) > 0) Then
            ErrorText := OpenSSLMissingHint + LineEnding + '(' + E.Message + ')';
          GotResponse := StatusCode <> 0;
        End;
    End;
    If Stream.Exceeded Then
      Begin
        SetLength(Data, 0);
        ErrorText := 'Response exceeded the size ceiling.';
        Exit(False);
      End;
    If Not GotResponse Then
      Exit(False);
    Result := CopyBoundedBytes(Stream, MaxBytes, Data, ErrorText);
  Finally
    Stream.Free;
    Client.Free;
  End;
End;

Function HttpsGet(Const Url: String; Out ResponseBody: String; Out StatusCode: Integer;
  Out ErrorText: String; Const ExtraHeaders: String): Boolean;
{$IFDEF WINDOWS}
Var
  RequestSent: Boolean;
{$ENDIF}
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
  If WinINetRequest('GET', Url, '', '', ExtraHeaders, ResponseBody, StatusCode, ErrorText, RequestSent) Then
    Begin
      Result := True;
      Exit;
    End;
  {$ENDIF}
  Result := HttpsViaFpHttp('GET', Url, '', '', ExtraHeaders, ResponseBody, StatusCode, ErrorText);
End;

Function HttpsPostForm(Const Url, FormBody: String; Out ResponseBody: String;
  Out StatusCode: Integer; Out ErrorText: String): Boolean;
{$IFDEF WINDOWS}
Var
  RequestSent: Boolean;
{$ENDIF}
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
  { Do not replay a POST that WinINet may already have sent (OAuth codes rotate). }
  If WinINetRequest('POST', Url, 'application/x-www-form-urlencoded', FormBody, '',
    ResponseBody, StatusCode, ErrorText, RequestSent) Then
    Begin
      Result := True;
      Exit;
    End;
  If RequestSent Then
    Begin
      Result := False;
      Exit;
    End;
  {$ENDIF}
  Result := HttpsViaFpHttp('POST', Url, 'application/x-www-form-urlencoded', FormBody, '',
    ResponseBody, StatusCode, ErrorText);
End;

Function HttpsPostJson(Const Url, JsonBody, ExtraHeaders: String;
  Out ResponseBody: String; Out StatusCode: Integer; Out ErrorText: String;
  IOTimeoutMs: Integer = 0): Boolean;
{$IFDEF WINDOWS}
Var
  RequestSent: Boolean;
{$ENDIF}
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
    ResponseBody, StatusCode, ErrorText, RequestSent, IOTimeoutMs) Then
    Begin
      Result := True;
      Exit;
    End;
  If RequestSent Then
    Begin
      Result := False;
      Exit;
    End;
  {$ENDIF}
  Result := HttpsViaFpHttp('POST', Url, 'application/json', JsonBody, ExtraHeaders,
    ResponseBody, StatusCode, ErrorText, IOTimeoutMs);
End;

Function HeaderLineValue(Headers: TStrings; Const Name: String): String;
Var
  I, Colon: Integer;
  Line, Key: String;
Begin
  Result := '';
  If Not Assigned(Headers) Then
    Exit;
  For I := 0 To Headers.Count - 1 Do
    Begin
      Line := Headers[I];
      Colon := Pos(':', Line);
      If Colon < 2 Then
        Continue;
      Key := Trim(Copy(Line, 1, Colon - 1));
      If SameText(Key, Name) Then
        Exit(Trim(Copy(Line, Colon + 1, MaxInt)));
    End;
End;

Procedure RememberRetryAfter(Client: TFPHTTPClient; Control: THttpsStreamControl);
Begin
  If (Not Assigned(Control)) Or (Not Assigned(Client)) Then
    Exit;
  Control.ResponseRetryAfter := HeaderLineValue(Client.ResponseHeaders, 'Retry-After');
End;

{$IFDEF WINDOWS}
Function WinINetRetryAfter(Request: HINTERNET): String;
Var
  Buf: Array[0..255] Of Char;
  Size, Index: DWORD;
  Name: String;
  I: Integer;
Begin
  Result := '';
  If Request = Nil Then
    Exit;
  FillChar(Buf, SizeOf(Buf), 0);
  Name := 'Retry-After';
  For I := 1 To Length(Name) Do
    Buf[I - 1] := Name[I];
  Size := SizeOf(Buf);
  Index := 0;
  If HttpQueryInfo(Request, HTTP_QUERY_CUSTOM, @Buf[0], Size, Index) Then
    Result := Trim(String(PChar(@Buf[0])));
End;

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
  Pending, Utf8Carry: RawByteString;
  ChunkText: String;
  Stopped: Boolean;
  ReadOk: Boolean;
  StolenSession, StolenConnect, StolenRequest: Pointer;
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
    If Assigned(Control) Then
      Control.ResponseRetryAfter := WinINetRetryAfter(Request);

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
      { Same carry as the Linux chunk stream. A split character must not be concatenated. }
      SetLength(Pending, Length(Utf8Carry) + Integer(BytesRead));
      If Length(Utf8Carry) > 0 Then
        Move(Utf8Carry[1], Pending[1], Length(Utf8Carry));
      Move(Buf[0], Pending[Length(Utf8Carry) + 1], BytesRead);
      ChunkText := CompleteUtf8Chunk(Pending, Utf8Carry);
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
    If Assigned(Control) Then
      Begin
        If Control.StealNativeHandles(StolenSession, StolenConnect, StolenRequest) Then
          Begin
            If StolenRequest <> Nil Then
              InternetCloseHandle(HINTERNET(StolenRequest));
            If StolenConnect <> Nil Then
              InternetCloseHandle(HINTERNET(StolenConnect));
            If StolenSession <> Nil Then
              InternetCloseHandle(HINTERNET(StolenSession));
          End;
        Control.ClearHandles;
      End
    Else
      Begin
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
  OutStream: TStream;
  SslErr, Auth: String;
  ColonPos: Integer;
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
  OutStream := THttpsChunkStream.Create(OnChunk, ShouldStop);
  Try
    Try
      If Assigned(Control) Then
        Control.AssignHttpClient(Client);
      Client.ConnectTimeout := 15000;
      Client.IOTimeout := 120000;
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
      RememberRetryAfter(Client, Control);
      Result := True;
    Except
      On E: EAbort Do
        Begin
          ErrorText := 'Cancelled.';
          Result := False;
        End;
      On E: Exception Do
        Begin
          ReportPluginException('HttpsPostJsonStream', E);
          ErrorText := E.Message;
          If ErrorText = '' Then
            ErrorText := E.ClassName;
          If (Pos('OpenSSL', ErrorText) > 0) Or (Pos('initialize', LowerCase(ErrorText)) > 0) Then
            ErrorText := OpenSSLMissingHint + LineEnding + '(' + E.Message + ')';
          RememberRetryAfter(Client, Control);
        End;
    End;
  Finally
    If Assigned(Control) Then
      Control.AssignHttpClient(Nil);
    Client.RequestBody := Nil;
    OutStream.Free;
    BodyStream.Free;
    Client.Free;
  End;
End;

End.
