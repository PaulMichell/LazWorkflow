Unit GrokOAuth;

{ xAI SuperGrok / X Premium OAuth (PKCE) client for LazAssistantTools (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Const
  { Shared public desktop OAuth client used by Hermes / OpenClaw / Grok Build integrations. }
  GrokOAuthClientId = 'b1a00492-073a-47ea-816f-4c329264a828';
  GrokOAuthScope = 'openid profile email offline_access grok-cli:access api:access';
  GrokOAuthRedirectUri = 'http://127.0.0.1:56121/callback';
  GrokOAuthRedirectHost = '127.0.0.1';
  GrokOAuthRedirectPort = 56121;
  GrokOAuthRedirectPath = '/callback';
  GrokOAuthDiscoveryUrl = 'https://auth.x.ai/.well-known/openid-configuration';
  GrokOAuthDefaultAuthEndpoint = 'https://auth.x.ai/oauth2/authorize';
  GrokOAuthDefaultTokenEndpoint = 'https://auth.x.ai/oauth2/token';
  GrokOAuthDefaultTimeoutMs = 300000;
  GrokOAuthRefreshSkewSeconds = 60;

Type
  TGrokOAuthTokens = Record
    AccessToken: String;
    RefreshToken: String;
    TokenType: String;
    Scope: String;
    { Local time when AccessToken expires; 0 if unknown. }
    ExpiresAt: TDateTime;
  End;

  TGrokOAuthClient = Class
  Private
    FAuthEndpoint: String;
    FTokenEndpoint: String;
    FTokens: TGrokOAuthTokens;
    FLastError: String;
    FPendingState: String;
    FPendingNonce: String;
    FPendingVerifier: String;
    FPendingChallenge: String;
    FLoginBusy: Boolean;
    Procedure ClearPending;
    Function HttpPostForm(Const Url, FormBody: String; Out ResponseBody: String;
      Out StatusCode: Integer): Boolean;
    Function ParseTokenResponse(Const ResponseBody: String; Out NewTokens: TGrokOAuthTokens): Boolean;
    Function TokenRequest(Const FormBody: String; Out NewTokens: TGrokOAuthTokens): Boolean;
    Function ExchangeAuthorizationCode(Const AuthCode: String): Boolean;
    Function IsAlreadyUsedError(Const MessageText: String): Boolean;
  Public
    Constructor Create;
    Function DiscoverEndpoints: Boolean;
    Function BuildAuthorizeUrl: String;
    { Starts a local loopback listener, opens the browser, and waits for the OAuth code. }
    Function LoginWithBrowser(TimeoutMs: Integer = GrokOAuthDefaultTimeoutMs): Boolean;
    { Completes login when the user pastes a code or full callback URL (no local listener). }
    Function LoginWithManualCode(Const CodeOrCallbackUrl: String): Boolean;
    Function BeginManualLogin(Out AuthUrl: String): Boolean;
    Function RefreshAccessToken: Boolean;
    Function GetValidAccessToken: String;
    Procedure ClearTokens;
    Procedure SetTokens(Const NewTokens: TGrokOAuthTokens);
    Function IsAuthenticated: Boolean;
    Function HasPendingLogin: Boolean;
    Function StatusText: String;
    Property Tokens: TGrokOAuthTokens Read FTokens;
    Property AuthEndpoint: String Read FAuthEndpoint;
    Property TokenEndpoint: String Read FTokenEndpoint;
    Property LastError: String Read FLastError;
    Property LoginBusy: Boolean Read FLoginBusy;
  End;

Var
  GrokOAuthClient: TGrokOAuthClient;

Implementation

Uses
  Forms, LCLIntf, dateutils, fpjson, jsonparser,
  httpprotocol, fpsha256, fphashutils, ssockets, WorkflowLog, AssistantHttps;

Type
  TGrokOAuthCallbackThread = Class(TThread)
  Private
    FExpectedState: String;
    FTimeoutMs: Integer;
    FCode: String;
    FError: String;
    FGotCode: Boolean;
    FServer: TInetServer;
    FStartTick: QWord;
    Procedure HandleConnect(Sender: TObject; Data: TSocketStream);
    Procedure HandleIdle(Sender: TObject);
    Procedure SendResponse(Data: TSocketStream; Const StatusLine, BodyText: String);
  Protected
    Procedure Execute; Override;
  Public
    Constructor Create(Const ExpectedState: String; TimeoutMs: Integer);
    Property Code: String Read FCode;
    Property ErrorText: String Read FError;
    Property GotCode: Boolean Read FGotCode;
  End;

Function BytesToBase64Url(Const Data: TBytes): String;
Begin
  Result := BytesEncodeBase64(Data, True, False, False);
End;

Function RandomBase64Url(ByteCount: Integer): String;
Var
  Buf: TBytes;
Begin
  Result := '';
  If ByteCount <= 0 Then
    Exit;
  SetLength(Buf, ByteCount);
  If Not CryptoGetRandomBytes(@Buf[0], ByteCount) Then
    Exit;
  Result := BytesToBase64Url(Buf);
End;

Function Sha256Base64Url(Const TextValue: String): String;
Var
  Source: TBytes;
  Digest: AnsiString;
Begin
  SetLength(Source, Length(TextValue));
  If Length(Source) > 0 Then
    Move(TextValue[1], Source[0], Length(Source));
  Digest := '';
  TSHA256.DigestBase64(Source, True, Digest);
  Result := String(Digest);
  While (Length(Result) > 0) And (Result[Length(Result)] = '=') Do
    SetLength(Result, Length(Result) - 1);
End;

Function EncodeQuery(Const Name, Value: String): String;
Begin
  Result := HTTPEncode(Name) + '=' + HTTPEncode(Value);
End;

Function ExtractQueryParam(Const Query, Key: String): String;
Var
  Parts: TStringList;
  I, EqPos: Integer;
  Item, Name, Val: String;
Begin
  Result := '';
  Parts := TStringList.Create;
  Try
    Parts.Delimiter := '&';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := Query;
    For I := 0 To Parts.Count - 1 Do
      Begin
        Item := Parts[I];
        EqPos := Pos('=', Item);
        If EqPos < 1 Then
          Continue;
        Name := Copy(Item, 1, EqPos - 1);
        Val := Copy(Item, EqPos + 1, MaxInt);
        If SameText(HTTPDecode(Name), Key) Then
          Begin
            Result := HTTPDecode(Val);
            Exit;
          End;
      End;
  Finally
    Parts.Free;
  End;
End;

{ TGrokOAuthCallbackThread }

Constructor TGrokOAuthCallbackThread.Create(Const ExpectedState: String; TimeoutMs: Integer);
Begin
  Inherited Create(True);
  FreeOnTerminate := False;
  FExpectedState := ExpectedState;
  FTimeoutMs := TimeoutMs;
  FCode := '';
  FError := '';
  FGotCode := False;
  FServer := Nil;
End;

Procedure TGrokOAuthCallbackThread.SendResponse(Data: TSocketStream; Const StatusLine, BodyText: String);
Var
  Response: String;
Begin
  Response :=
    StatusLine + #13#10 +
    'Content-Type: text/plain; charset=utf-8'#13#10 +
    'Connection: close'#13#10 +
    'Content-Length: ' + IntToStr(Length(BodyText)) + #13#10#13#10 +
    BodyText;
  If Length(Response) > 0 Then
    Data.WriteBuffer(Response[1], Length(Response));
End;

Procedure TGrokOAuthCallbackThread.HandleIdle(Sender: TObject);
Begin
  If Terminated Then
    Begin
      If Assigned(FServer) Then
        FServer.StopAccepting(True);
      Exit;
    End;
  If Integer(GetTickCount64 - FStartTick) >= FTimeoutMs Then
    Begin
      If FError = '' Then
        FError := 'Timed out waiting for the browser OAuth callback.';
      If Assigned(FServer) Then
        FServer.StopAccepting(True);
    End;
End;

Procedure TGrokOAuthCallbackThread.HandleConnect(Sender: TObject; Data: TSocketStream);
Const
  MaxCallbackBytes = 16384;
Var
  Request, Line, Path, Query, AuthCode, State, ErrParam, Chunk: String;
  Buf: Array[0..4095] Of Byte;
  N, HeaderEnd, SpacePos, QPos: Integer;
Begin
  If Not Assigned(Data) Then
    Exit;
  Request := '';
  Try
    Repeat
      N := Data.Read(Buf[0], SizeOf(Buf));
      If N <= 0 Then
        Break;
      If Length(Request) + N > MaxCallbackBytes Then
        Begin
          FError := 'OAuth callback request too large.';
          SendResponse(Data, 'HTTP/1.1 413 Payload Too Large', 'Request too large');
          Exit;
        End;
      SetLength(Chunk, N);
      Move(Buf[0], Chunk[1], N);
      Request := Request + Chunk;
      HeaderEnd := Pos(#13#10#13#10, Request);
      If HeaderEnd = 0 Then
        HeaderEnd := Pos(#10#10, Request);
    Until HeaderEnd > 0;

    Line := '';
    If Pos(#13#10, Request) > 0 Then
      Line := Copy(Request, 1, Pos(#13#10, Request) - 1)
    Else If Pos(#10, Request) > 0 Then
      Line := Copy(Request, 1, Pos(#10, Request) - 1)
    Else
      Line := Request;

    Path := '';
    Query := '';
    If (Length(Line) >= 4) And (Copy(Line, 1, 4) = 'GET ') Then
      Begin
        Delete(Line, 1, 4);
        SpacePos := Pos(' ', Line);
        If SpacePos > 0 Then
          Line := Copy(Line, 1, SpacePos - 1);
        QPos := Pos('?', Line);
        If QPos > 0 Then
          Begin
            Path := Copy(Line, 1, QPos - 1);
            Query := Copy(Line, QPos + 1, MaxInt);
          End
        Else
          Path := Line;
      End;

    If Path <> GrokOAuthRedirectPath Then
      Begin
        SendResponse(Data, 'HTTP/1.1 404 Not Found', 'Not found');
        Exit;
      End;

    AuthCode := ExtractQueryParam(Query, 'code');
    State := ExtractQueryParam(Query, 'state');
    ErrParam := ExtractQueryParam(Query, 'error');
    If ErrParam <> '' Then
      Begin
        FError := 'OAuth callback error: ' + ErrParam;
        SendResponse(Data, 'HTTP/1.1 400 Bad Request', 'OAuth error: ' + ErrParam);
        If Assigned(FServer) Then
          FServer.StopAccepting(True);
        Exit;
      End;
    If (AuthCode = '') Or (State <> FExpectedState) Then
      Begin
        SendResponse(Data, 'HTTP/1.1 400 Bad Request',
          'Invalid OAuth callback. If xAI showed a code, paste it in Assistant Settings.');
        Exit;
      End;

    FCode := AuthCode;
    FGotCode := True;
    SendResponse(Data, 'HTTP/1.1 200 OK',
      'xAI login complete. You can close this tab and return to Lazarus.');
    If Assigned(FServer) Then
      FServer.StopAccepting(True);
  Except
    On E: Exception Do
      FError := E.Message;
  End;
End;

Procedure TGrokOAuthCallbackThread.Execute;
Begin
  FStartTick := GetTickCount64;
  FServer := Nil;
  Try
    Try
      FServer := TInetServer.Create(GrokOAuthRedirectHost, GrokOAuthRedirectPort);
      FServer.ReuseAddress := True;
      FServer.AcceptIdleTimeOut := 250;
      FServer.MaxConnections := 5;
      FServer.OnConnect := @HandleConnect;
      FServer.OnIdle := @HandleIdle;
      FServer.Bind;
      FServer.Listen;
      FServer.StartAccepting;
    Except
      On E: Exception Do
        If FError = '' Then
          FError := E.Message;
    End;
  Finally
    If Assigned(FServer) Then
      Begin
        Try
          FServer.StopAccepting(True);
        Except
        End;
        FreeAndNil(FServer);
      End;
    If (Not FGotCode) And (FError = '') And Terminated Then
      FError := 'OAuth login cancelled.';
    If (Not FGotCode) And (FError = '') Then
      FError := 'OAuth callback did not complete.';
  End;
End;

{ TGrokOAuthClient }

Constructor TGrokOAuthClient.Create;
Begin
  Inherited Create;
  FAuthEndpoint := GrokOAuthDefaultAuthEndpoint;
  FTokenEndpoint := GrokOAuthDefaultTokenEndpoint;
  ClearTokens;
  ClearPending;
  FLastError := '';
  FLoginBusy := False;
End;

Function TGrokOAuthClient.HasPendingLogin: Boolean;
Begin
  Result := FPendingVerifier <> '';
End;

Function TGrokOAuthClient.IsAlreadyUsedError(Const MessageText: String): Boolean;
Begin
  Result := Pos('already been used', LowerCase(MessageText)) > 0;
End;

Procedure TGrokOAuthClient.ClearPending;
Begin
  FPendingState := '';
  FPendingNonce := '';
  FPendingVerifier := '';
  FPendingChallenge := '';
End;

Procedure TGrokOAuthClient.ClearTokens;
Begin
  FTokens.AccessToken := '';
  FTokens.RefreshToken := '';
  FTokens.TokenType := 'Bearer';
  FTokens.Scope := '';
  FTokens.ExpiresAt := 0;
End;

Procedure TGrokOAuthClient.SetTokens(Const NewTokens: TGrokOAuthTokens);
Begin
  FTokens := NewTokens;
  If FTokens.TokenType = '' Then
    FTokens.TokenType := 'Bearer';
End;

Function TGrokOAuthClient.IsAuthenticated: Boolean;
Begin
  Result := (Trim(FTokens.AccessToken) <> '') Or (Trim(FTokens.RefreshToken) <> '');
End;

Function TGrokOAuthClient.StatusText: String;
Begin
  If Not IsAuthenticated Then
    Begin
      Result := 'Not signed in';
      Exit;
    End;
  If FTokens.ExpiresAt > 0 Then
    Begin
      If FTokens.ExpiresAt <= Now Then
        Result := 'Signed in (token expired – will refresh)'
      Else
        Result := 'Signed in (expires ' + FormatDateTime('yyyy-mm-dd hh:nn', FTokens.ExpiresAt) + ')';
    End
  Else
    Result := 'Signed in';
End;

Function TGrokOAuthClient.HttpPostForm(Const Url, FormBody: String; Out ResponseBody: String;
  Out StatusCode: Integer): Boolean;
Var
  Err: String;
Begin
  Result := HttpsPostForm(Url, FormBody, ResponseBody, StatusCode, Err);
  If Not Result Then
    FLastError := Err;
End;

Function TGrokOAuthClient.ParseTokenResponse(Const ResponseBody: String;
  Out NewTokens: TGrokOAuthTokens): Boolean;
Var
  Data: TJSONData;
  Obj: TJSONObject;
  ExpiresIn: Int64;
Begin
  Result := False;
  NewTokens.AccessToken := '';
  NewTokens.RefreshToken := '';
  NewTokens.TokenType := 'Bearer';
  NewTokens.Scope := '';
  NewTokens.ExpiresAt := 0;
  Data := Nil;
  Try
    Try
      Data := GetJSON(ResponseBody);
      If Not (Data Is TJSONObject) Then
        Begin
          FLastError := 'Token response was not JSON.';
          Exit;
        End;
      Obj := TJSONObject(Data);
      NewTokens.AccessToken := Obj.Get('access_token', '');
      NewTokens.RefreshToken := Obj.Get('refresh_token', '');
      NewTokens.TokenType := Obj.Get('token_type', 'Bearer');
      NewTokens.Scope := Obj.Get('scope', '');
      ExpiresIn := Obj.Get('expires_in', Int64(0));
      If ExpiresIn > 0 Then
        NewTokens.ExpiresAt := IncSecond(Now, ExpiresIn)
      Else
        NewTokens.ExpiresAt := 0;
      If NewTokens.AccessToken = '' Then
        Begin
          FLastError := 'Token response did not include access_token.';
          Exit;
        End;
      Result := True;
    Except
      On E: Exception Do
        FLastError := 'Failed to parse token response: ' + E.Message;
    End;
  Finally
    Data.Free;
  End;
End;

Function TGrokOAuthClient.TokenRequest(Const FormBody: String; Out NewTokens: TGrokOAuthTokens): Boolean;
Var
  Body: String;
  StatusCode: Integer;
Begin
  Result := False;
  If Not HttpPostForm(FTokenEndpoint, FormBody, Body, StatusCode) Then
    Exit;
  If (StatusCode < 200) Or (StatusCode >= 300) Then
    Begin
      If Length(Body) > 400 Then
        Body := Copy(Body, 1, 400) + '…';
      FLastError := Format('Token request failed (HTTP %d): %s', [StatusCode, Body]);
      Exit;
    End;
  Result := ParseTokenResponse(Body, NewTokens);
End;

Function TGrokOAuthClient.ExchangeAuthorizationCode(Const AuthCode: String): Boolean;
Var
  FormBody: String;
  NewTokens: TGrokOAuthTokens;
  OldRefresh: String;
Begin
  Result := False;
  OldRefresh := FTokens.RefreshToken;
  FormBody :=
    EncodeQuery('grant_type', 'authorization_code') + '&' +
    EncodeQuery('code', AuthCode) + '&' +
    EncodeQuery('redirect_uri', GrokOAuthRedirectUri) + '&' +
    EncodeQuery('client_id', GrokOAuthClientId) + '&' +
    EncodeQuery('code_verifier', FPendingVerifier) + '&' +
    EncodeQuery('code_challenge', FPendingChallenge) + '&' +
    EncodeQuery('code_challenge_method', 'S256');
  If Not TokenRequest(FormBody, NewTokens) Then
    Exit;
  If NewTokens.RefreshToken = '' Then
    NewTokens.RefreshToken := OldRefresh;
  FTokens := NewTokens;
  ClearPending;
  Result := True;
End;

Function TGrokOAuthClient.DiscoverEndpoints: Boolean;
Var
  Body, Err: String;
  StatusCode: Integer;
  Data: TJSONData;
  Obj: TJSONObject;
Begin
  Result := False;
  FLastError := '';
  { Defaults always usable if discovery HTTPS fails (e.g. missing OpenSSL). }
  FAuthEndpoint := GrokOAuthDefaultAuthEndpoint;
  FTokenEndpoint := GrokOAuthDefaultTokenEndpoint;
  Data := Nil;
  Try
    If Not HttpsGet(GrokOAuthDiscoveryUrl, Body, StatusCode, Err) Then
      Begin
        WorkflowLogger.Warning('GrokOAuth', 'Discovery failed, using defaults: ' + Err);
        Result := True;
        Exit;
      End;
    If (StatusCode < 200) Or (StatusCode >= 300) Then
      Begin
        WorkflowLogger.Warning('GrokOAuth',
          Format('Discovery HTTP %d, using defaults', [StatusCode]));
        Result := True;
        Exit;
      End;
    Try
      Data := GetJSON(Body);
      If Not (Data Is TJSONObject) Then
        Begin
          WorkflowLogger.Warning('GrokOAuth', 'Discovery was not JSON; using defaults');
          Result := True;
          Exit;
        End;
      Obj := TJSONObject(Data);
      FAuthEndpoint := Obj.Get('authorization_endpoint', GrokOAuthDefaultAuthEndpoint);
      FTokenEndpoint := Obj.Get('token_endpoint', GrokOAuthDefaultTokenEndpoint);
      If (Not UrlIsHttps(FAuthEndpoint)) Or (Not UrlIsHttps(FTokenEndpoint)) Then
        Begin
          FAuthEndpoint := GrokOAuthDefaultAuthEndpoint;
          FTokenEndpoint := GrokOAuthDefaultTokenEndpoint;
        End;
      Result := True;
    Except
      On E: Exception Do
        Begin
          WorkflowLogger.Warning('GrokOAuth', 'Discovery parse failed, using defaults: ' + E.Message);
          Result := True;
        End;
    End;
  Finally
    Data.Free;
  End;
End;

Function TGrokOAuthClient.BuildAuthorizeUrl: String;
Begin
  Result :=
    FAuthEndpoint + '?' +
    EncodeQuery('response_type', 'code') + '&' +
    EncodeQuery('client_id', GrokOAuthClientId) + '&' +
    EncodeQuery('redirect_uri', GrokOAuthRedirectUri) + '&' +
    EncodeQuery('scope', GrokOAuthScope) + '&' +
    EncodeQuery('state', FPendingState) + '&' +
    EncodeQuery('nonce', FPendingNonce) + '&' +
    EncodeQuery('code_challenge', FPendingChallenge) + '&' +
    EncodeQuery('code_challenge_method', 'S256') + '&' +
    EncodeQuery('plan', 'generic') + '&' +
    EncodeQuery('referrer', 'laz-grok-chat');
End;

Function TGrokOAuthClient.BeginManualLogin(Out AuthUrl: String): Boolean;
Begin
  Result := False;
  AuthUrl := '';
  FLastError := '';
  If FLoginBusy Then
    Begin
      FLastError := 'A sign-in is already in progress. Finish or cancel it first.';
      Exit;
    End;
  If Not DiscoverEndpoints Then
    Exit;
  FPendingState := RandomBase64Url(16);
  FPendingNonce := RandomBase64Url(16);
  FPendingVerifier := RandomBase64Url(64);
  If (FPendingState = '') Or (FPendingNonce = '') Or (FPendingVerifier = '') Then
    Begin
      ClearPending;
      FLastError := 'Could not generate secure OAuth randomness.';
      Exit;
    End;
  FPendingChallenge := Sha256Base64Url(FPendingVerifier);
  AuthUrl := BuildAuthorizeUrl;
  Result := AuthUrl <> '';
End;

Function TGrokOAuthClient.LoginWithBrowser(TimeoutMs: Integer): Boolean;
Var
  AuthUrl: String;
  Thread: TGrokOAuthCallbackThread;
  StartTick: QWord;
Begin
  Result := False;
  FLastError := '';
  If FLoginBusy Then
    Begin
      FLastError := 'A sign-in is already in progress.';
      Exit;
    End;
  If Not BeginManualLogin(AuthUrl) Then
    Exit;

  FLoginBusy := True;
  Thread := TGrokOAuthCallbackThread.Create(FPendingState, TimeoutMs);
  Try
    Thread.Start;
    Sleep(200);
    If Not OpenURL(AuthUrl) Then
      WorkflowLogger.Warning('GrokOAuth', 'OpenURL failed; open this URL manually: ' + AuthUrl);

    StartTick := GetTickCount64;
    While (Not Thread.Finished) And (Integer(GetTickCount64 - StartTick) < TimeoutMs + 5000) Do
      Begin
        Sleep(50);
        { Process paints/timers only — avoid re-entering Sign in / paste handlers. }
        Application.ProcessMessages;
      End;

    If Not Thread.Finished Then
      Begin
        Thread.Terminate;
        Thread.WaitFor;
      End
    Else
      Thread.WaitFor;

    { Manual paste may have completed login while we waited (ProcessMessages). }
    If IsAuthenticated And (Not HasPendingLogin) Then
      Begin
        Result := True;
        WorkflowLogger.Info('GrokOAuth', 'Login completed during browser wait');
        Exit;
      End;

    If Not Thread.GotCode Then
      Begin
        If Thread.ErrorText <> '' Then
          FLastError := Thread.ErrorText
        Else
          FLastError := 'OAuth browser login did not complete.';
        { Keep pending so the user can paste a code if the callback never arrived. }
        Exit;
      End;

    If Not ExchangeAuthorizationCode(Thread.Code) Then
      Begin
        { Code is single-use: callback may have raced with a paste, or user re-pasted. }
        If IsAuthenticated And IsAlreadyUsedError(FLastError) Then
          Begin
            ClearPending;
            Result := True;
            FLastError := '';
            WorkflowLogger.Info('GrokOAuth', 'Browser code already used; existing session kept');
            Exit;
          End;
        If IsAlreadyUsedError(FLastError) Then
          FLastError := 'Authorization code was already used. Click Sign in again for a fresh login.';
        Exit;
      End;
    Result := True;
    WorkflowLogger.Info('GrokOAuth', 'Browser OAuth login succeeded');
  Finally
    FLoginBusy := False;
    Thread.Free;
  End;
End;

Function TGrokOAuthClient.LoginWithManualCode(Const CodeOrCallbackUrl: String): Boolean;
Var
  Raw, AuthCode, State, ErrParam, Query: String;
  QPos: Integer;
Begin
  Result := False;
  FLastError := '';
  If FLoginBusy And (Not HasPendingLogin) Then
    Begin
      FLastError := 'A sign-in is already in progress.';
      Exit;
    End;
  If FPendingVerifier = '' Then
    Begin
      If IsAuthenticated Then
        FLastError := 'Already signed in. The browser code is single-use and does not need to be pasted again.'
      Else
        FLastError := 'No pending login. Click Sign in first, then paste the code only if the browser did not redirect.';
      Exit;
    End;
  Raw := Trim(CodeOrCallbackUrl);
  If Raw = '' Then
    Begin
      FLastError := 'Paste the OAuth code or full callback URL.';
      Exit;
    End;

  AuthCode := '';
  State := '';
  If (Pos('://', Raw) > 0) Or (Pos('code=', Raw) > 0) Then
    Begin
      QPos := Pos('?', Raw);
      If QPos > 0 Then
        Query := Copy(Raw, QPos + 1, MaxInt)
      Else
        Query := Raw;
      AuthCode := ExtractQueryParam(Query, 'code');
      State := ExtractQueryParam(Query, 'state');
      ErrParam := ExtractQueryParam(Query, 'error');
      If ErrParam <> '' Then
        Begin
          FLastError := 'OAuth error: ' + ErrParam;
          Exit;
        End;
      If (State <> '') And (State <> FPendingState) Then
        Begin
          FLastError := 'OAuth state mismatch. Start Sign in again.';
          Exit;
        End;
    End
  Else
    AuthCode := Raw;

  If AuthCode = '' Then
    Begin
      FLastError := 'Could not find an OAuth code in the pasted text.';
      Exit;
    End;

  If FTokenEndpoint = '' Then
    FTokenEndpoint := GrokOAuthDefaultTokenEndpoint;

  If Not ExchangeAuthorizationCode(AuthCode) Then
    Begin
      If IsAuthenticated And IsAlreadyUsedError(FLastError) Then
        Begin
          ClearPending;
          Result := True;
          FLastError := '';
          WorkflowLogger.Info('GrokOAuth', 'Pasted code already used; existing session kept');
          Exit;
        End;
      If IsAlreadyUsedError(FLastError) Then
        Begin
          ClearPending;
          FLastError := 'Authorization code was already used (codes work only once). ' +
            'If you are not signed in, click Sign in again and complete the browser flow once.';
        End;
      Exit;
    End;
  Result := True;
  WorkflowLogger.Info('GrokOAuth', 'Manual OAuth code exchange succeeded');
End;

Function TGrokOAuthClient.RefreshAccessToken: Boolean;
Var
  FormBody: String;
  NewTokens: TGrokOAuthTokens;
  OldRefresh: String;
Begin
  Result := False;
  FLastError := '';
  If Trim(FTokens.RefreshToken) = '' Then
    Begin
      FLastError := 'No refresh token. Sign in again with SuperGrok / X Premium.';
      Exit;
    End;
  If FTokenEndpoint = '' Then
    If Not DiscoverEndpoints Then
      FTokenEndpoint := GrokOAuthDefaultTokenEndpoint;
  OldRefresh := FTokens.RefreshToken;
  FormBody :=
    EncodeQuery('grant_type', 'refresh_token') + '&' +
    EncodeQuery('refresh_token', FTokens.RefreshToken) + '&' +
    EncodeQuery('client_id', GrokOAuthClientId);
  If Not TokenRequest(FormBody, NewTokens) Then
    Exit;
  If NewTokens.RefreshToken = '' Then
    NewTokens.RefreshToken := OldRefresh;
  FTokens := NewTokens;
  Result := True;
  WorkflowLogger.Info('GrokOAuth', 'Access token refreshed');
End;

Function TGrokOAuthClient.GetValidAccessToken: String;
Begin
  Result := '';
  FLastError := '';
  If Trim(FTokens.AccessToken) = '' Then
    Begin
      If Trim(FTokens.RefreshToken) = '' Then
        Begin
          FLastError := 'Not signed in. Open Grok Settings and sign in with SuperGrok / X Premium.';
          Exit;
        End;
      If Not RefreshAccessToken Then
        Exit;
    End
  Else If (FTokens.ExpiresAt > 0) And
    (FTokens.ExpiresAt <= IncSecond(Now, GrokOAuthRefreshSkewSeconds)) Then
    Begin
      If Trim(FTokens.RefreshToken) <> '' Then
        Begin
          If Not RefreshAccessToken Then
            Exit;
        End
      Else
        Begin
          FLastError := 'Access token expired. Sign in again.';
          Exit;
        End;
    End;
  Result := FTokens.AccessToken;
End;

Initialization

GrokOAuthClient := TGrokOAuthClient.Create;

Finalization

FreeAndNil(GrokOAuthClient);

End.
