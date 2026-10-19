Unit AssistantHttpsWinInet;

{ Windows WinINet fallback and OpenSSL DLL preload for AssistantHttps (c) 2026 Michell Computing.

  The LCL has no HTTP client. TFPHTTPClient is the cross-platform transport.
  WinINet stays until a Windows run shows OpenSSL streaming is enough.
  This body is inside WINDOWS so the unit compiles on Linux. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils;

Type
  TWinINetChunkEvent = Procedure(Const Chunk: String) Of Object;
  TWinINetStopCheck = Function: Boolean Of Object;

/// Windows OpenSSL DLL preload. Other hosts do nothing.
Procedure PreloadOpenSslLibraries;
/// One WinINet request. RequestSent is true once the body may already be in flight.
Function TryWinINetRequest(Const Method, Url, ContentType, Body, ExtraHeaders: String;
  Out ResponseBody: String; Out StatusCode: Integer; Out ErrorText: String; Out RequestSent: Boolean;
  IOTimeoutMs: Integer = 0; NoRedirect: Boolean = False; CaptureBytes: Pointer = Nil;
  Const AcceptValue: String = 'application/json'; MaxBytes: Integer = 0): Boolean;
/// Streaming JSON POST. False on hosts without WinINet so the caller uses fpHTTP.
Function TryWinINetPostJsonStream(Const Url, JsonBody, ExtraHeaders: String;
  OnChunk: TWinINetChunkEvent; ShouldStop: TWinINetStopCheck; Control: TObject;
  Out StatusCode: Integer; Out ErrorText: String): Boolean;
/// Closes WinINet handles bound to Control. Safe to call twice. Does not delete anything.
Function CloseWinINetStream(Control: TObject): Boolean;

Implementation

{$IFDEF WINDOWS}
Uses
  Windows, WinInet, Forms, WorkflowLog, AssistantHttps;

Type
  TBytesPointer = ^TBytes;
  TWinINetBinding = Record
    Control: TObject;
    Session, Connect, Request: HINTERNET;
  End;

Var
  BindLock: TRTLCriticalSection;
  Bindings: Array Of TWinINetBinding;

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
  ColonPos := Pos('@', HostPort);
  If ColonPos > 0 Then
    HostPort := Copy(HostPort, ColonPos + 1, MaxInt);
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

Procedure CloseInternetHandles(Session, Connect, Request: HINTERNET);
Begin
  If Request <> Nil Then
    InternetCloseHandle(Request);
  If Connect <> Nil Then
    InternetCloseHandle(Connect);
  If Session <> Nil Then
    InternetCloseHandle(Session);
End;

Procedure RegisterWinINetStream(Control: TObject; Session, Connect, Request: HINTERNET);
Var
  I: Integer;
Begin
  If Control = Nil Then
    Exit;
  EnterCriticalSection(BindLock);
  Try
    For I := 0 To High(Bindings) Do
      If Bindings[I].Control = Control Then
        Begin
          Bindings[I].Session := Session;
          Bindings[I].Connect := Connect;
          Bindings[I].Request := Request;
          Exit;
        End;
    I := Length(Bindings);
    SetLength(Bindings, I + 1);
    Bindings[I].Control := Control;
    Bindings[I].Session := Session;
    Bindings[I].Connect := Connect;
    Bindings[I].Request := Request;
  Finally
    LeaveCriticalSection(BindLock);
  End;
End;

Function TakeWinINetStream(Control: TObject; Out Session, Connect, Request: HINTERNET): Boolean;
Var
  I, Last: Integer;
Begin
  Result := False;
  Session := Nil;
  Connect := Nil;
  Request := Nil;
  If Control = Nil Then
    Exit;
  EnterCriticalSection(BindLock);
  Try
    For I := 0 To High(Bindings) Do
      If Bindings[I].Control = Control Then
        Begin
          Session := Bindings[I].Session;
          Connect := Bindings[I].Connect;
          Request := Bindings[I].Request;
          Last := High(Bindings);
          Bindings[I] := Bindings[Last];
          SetLength(Bindings, Last);
          Result := True;
          Exit;
        End;
  Finally
    LeaveCriticalSection(BindLock);
  End;
End;

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
{$ENDIF}

Procedure PreloadOpenSslLibraries;
Begin
  {$IFDEF WINDOWS}
  PreloadOpenSslFromDirs;
  {$ENDIF}
End;

Function TryWinINetRequest(Const Method, Url, ContentType, Body, ExtraHeaders: String;
  Out ResponseBody: String; Out StatusCode: Integer; Out ErrorText: String; Out RequestSent: Boolean;
  IOTimeoutMs: Integer; NoRedirect: Boolean; CaptureBytes: Pointer; Const AcceptValue: String;
  MaxBytes: Integer): Boolean;
{$IFDEF WINDOWS}
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
  Bytes: TBytesPointer;
{$ENDIF}
Begin
  Result := False;
  ResponseBody := '';
  StatusCode := 0;
  ErrorText := '';
  RequestSent := False;
  {$IFDEF WINDOWS}
  Session := Nil;
  Connect := Nil;
  Request := Nil;
  Bytes := TBytesPointer(CaptureBytes);
  If Assigned(Bytes) Then
    SetLength(Bytes^, 0);
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
    Connect := InternetConnect(Session, PChar(Host), Port, Nil, Nil, INTERNET_SERVICE_HTTP, 0, 0);
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
      StatusCode := StrToIntDef(String(StatusBuf), 0);

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
        If Assigned(Bytes) Then
          Begin
            SetLength(Bytes^, Length(Raw));
            If Length(Raw) > 0 Then
              Move(Raw[1], Bytes^[0], Length(Raw));
          End;
        ResponseBody := String(Raw);
        Result := True;
      End;
  Finally
    CloseInternetHandles(Session, Connect, Request);
  End;
  {$ENDIF}
End;

Function TryWinINetPostJsonStream(Const Url, JsonBody, ExtraHeaders: String;
  OnChunk: TWinINetChunkEvent; ShouldStop: TWinINetStopCheck; Control: TObject;
  Out StatusCode: Integer; Out ErrorText: String): Boolean;
{$IFDEF WINDOWS}
Var
  Session, Connect, Request: HINTERNET;
  Host, Path, Headers: String;
  Port: INTERNET_PORT;
  UseHttps, Registered, Stopped, ReadOk: Boolean;
  Flags, BytesRead, StatusSize, Index: DWORD;
  StatusBuf: Array[0..31] Of Char;
  Buf: Array[0..8191] Of Byte;
  BodyAnsi, Pending, Utf8Carry: RawByteString;
  BodyPtr: Pointer;
  BodyLen: DWORD;
  ChunkText: String;
{$ENDIF}
Begin
  Result := False;
  StatusCode := 0;
  ErrorText := '';
  {$IFDEF WINDOWS}
  Session := Nil;
  Connect := Nil;
  Request := Nil;
  Registered := False;
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
      Begin
        RegisterWinINetStream(Control, Session, Connect, Request);
        Registered := True;
        If THttpsStreamControl(Control).ClosedByAbort Then
          Begin
            ErrorText := 'Cancelled.';
            Exit;
          End;
      End;

    Headers := 'Accept: text/event-stream'#13#10 + 'Content-Type: application/json'#13#10;
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
      StatusCode := StrToIntDef(String(StatusBuf), 0);
    If Assigned(Control) Then
      THttpsStreamControl(Control).ResponseRetryAfter := WinINetRetryAfter(Request);

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
      { Same carry as the fpHTTP chunk stream. A split character must not be concatenated. }
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
    If Registered Then
      CloseWinINetStream(Control)
    Else
      CloseInternetHandles(Session, Connect, Request);
    If Assigned(Control) Then
      THttpsStreamControl(Control).ClearHandles;
  End;
  {$ENDIF}
End;

Function CloseWinINetStream(Control: TObject): Boolean;
{$IFDEF WINDOWS}
Var
  Session, Connect, Request: HINTERNET;
{$ENDIF}
Begin
  Result := False;
  {$IFDEF WINDOWS}
  Result := TakeWinINetStream(Control, Session, Connect, Request);
  If Result Then
    CloseInternetHandles(Session, Connect, Request);
  {$ENDIF}
End;

{$IFDEF WINDOWS}
Initialization
InitCriticalSection(BindLock);

Finalization
DoneCriticalSection(BindLock);
{$ENDIF}

End.
