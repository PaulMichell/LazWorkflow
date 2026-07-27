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

{ User-facing hint when OpenSSL is missing (Windows). }
Function OpenSSLMissingHint: String;

Implementation

Uses
  {$IFDEF WINDOWS}
  Windows, WinInet,
  {$ENDIF}
  Forms, fphttpclient, opensslsockets, openssl, WorkflowLog;

Function OpenSSLMissingHint: String;
Begin
  {$IFDEF WINDOWS}
  Result :=
    'Could not load OpenSSL (needed for streamed HTTPS to x.ai).' + LineEnding +
    'Install OpenSSL for Windows (Win64) and copy these next to lazarus.exe,' + LineEnding +
    'or into a folder on PATH:' + LineEnding +
    '  libssl-1_1-x64.dll  and  libcrypto-1_1-x64.dll' + LineEnding +
    '(or libssl-3-x64.dll and libcrypto-3-x64.dll if your FPC build supports them).' + LineEnding +
    'Download: https://slproweb.com/products/Win32OpenSSL.html' + LineEnding +
    '(Light package is enough.)' + LineEnding +
    'Note: Sign-in uses Windows WinINet and does not require OpenSSL.';
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
    AddSearchDir(Dirs, GetCurrentDir);
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
  If (Not UseHttps) And (Not SameText(Copy(Url, 1, SchemeEnd - 1), 'http')) Then
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

    StatusSize := SizeOf(StatusBuf);
    Index := 0;
    FillChar(StatusBuf, SizeOf(StatusBuf), 0);
    If HttpQueryInfo(Request, HTTP_QUERY_STATUS_CODE, @StatusBuf[0], StatusSize, Index) Then
      StatusCode := StrToIntDef(string(StatusBuf), 0);

    Raw := '';
    Repeat
      BytesRead := 0;
      If Not InternetReadFile(Request, @Buf[0], SizeOf(Buf), BytesRead) Then
        Break;
      If BytesRead = 0 Then
        Break;
      SetLength(Raw, Length(Raw) + Integer(BytesRead));
      Move(Buf[0], Raw[Length(Raw) - Integer(BytesRead) + 1], BytesRead);
    Until False;
    ResponseBody := string(Raw);
    Result := True;
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
      Client.AllowRedirect := True;
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

End.
