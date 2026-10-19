Unit AssistantHttps;

{ HTTPS helpers for LazAssistantTools (c) 2026 Michell Computing.

  The LCL has no HTTP client. TFPHTTPClient is the cross-platform transport.
  WinINet preload and requests live in AssistantHttpsWinInet and stay the
  Windows fallback until a Windows run shows OpenSSL streaming is enough.
  New HTTPS behaviour goes through the fpHTTP path first.
  Reviewed 2026-10-19: the WinINet split drops this unit under the 1000 line
  preference. A bounded byte GET stays here so an image download does not
  grow a second client. }

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

  { Opaque cancel handle. Abort is the cancel operation. Native handles stay in AssistantHttpsWinInet. }
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
    { Opaque pointers only. Not an HINTERNET view for other units. }
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
  fphttpclient, opensslsockets, openssl, WorkflowLog, fpjson, jsonparser, AssistantHttpsWinInet;

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
  HttpClient: TObject;
Begin
  EnterCriticalSection(FLock);
  Try
    FRequest := Nil;
    FConnect := Nil;
    FSession := Nil;
    HttpClient := FHttpClient;
    FHttpClient := Nil;
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
  CloseWinINetStream(Self);
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
    PreloadOpenSslLibraries;
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
  If TryWinINetRequest('GET', Url, '', '', ExtraHeaders, IgnoredBody, StatusCode, ErrorText, RequestSent,
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
  If TryWinINetRequest('GET', Url, '', '', ExtraHeaders, ResponseBody, StatusCode, ErrorText, RequestSent) Then
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
  If TryWinINetRequest('POST', Url, 'application/x-www-form-urlencoded', FormBody, '',
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
  If TryWinINetRequest('POST', Url, 'application/json', JsonBody, ExtraHeaders,
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
  { Existing Windows path: WinINet so streamed chat works without OpenSSL DLLs.
    New HTTPS behaviour goes through the fpHTTP path first. }
  Result := TryWinINetPostJsonStream(Url, JsonBody, ExtraHeaders, TWinINetChunkEvent(OnChunk),
    TWinINetStopCheck(ShouldStop), Control, StatusCode, ErrorText);
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
          { A 402 or 429 can raise after the status is known. Do not leave the Out code at 0. }
          If (StatusCode = 0) And (Client.ResponseStatusCode <> 0) Then
            StatusCode := Client.ResponseStatusCode;
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
