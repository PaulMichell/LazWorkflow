Unit AssistantCodexHandshake;

{ Transport-independent App Server handshake and managed ChatGPT sign-in.
  No model requests, raw tokens, API-key fallback, or IDE actions are exposed.
  Protocol reference: https://learn.chatgpt.com/docs/app-server
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  Classes, SysUtils;

Type
  TCodexConnectionState = (ccsClosed, ccsInitializing, ccsCheckingAccount,
    ccsNeedsSignIn, ccsSigningIn, ccsSubscriptionAuthenticated, ccsFailed);
  TAssistantCodexHandshake = Class
  Private
    FState: TCodexConnectionState;
    FBuffer, FLastError, FLoginId, FLoginUrl: String;
    FOutgoing: TStringList;
    FNextId, FInitializeId, FAccountId, FLoginRequestId: Int64;
    Function Request(Const Method, Params: String): Int64;
    Procedure RemoveQueuedRequest(Id: Int64);
    Procedure CheckAccount;
    Procedure HandleLine(Const Line: String);
    Procedure Fail(Const Reason: String);
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Start(ExperimentalTools: Boolean = False);
    Procedure Close;
    Procedure Feed(Const Bytes: String);
    { Caller writes each returned JSONL frame once to the private stdio channel. }
    Function TakeOutgoing(Out Frame: String): Boolean;
    { Explicit user action only. Runtime owns browser OAuth and token refresh. }
    Procedure StartChatGPTLogin;
    Property State: TCodexConnectionState Read FState;
    Property LastError: String Read FLastError;
    Property LoginUrl: String Read FLoginUrl;
  End;
  { Pass arguments directly to TProcess, never through a shell. }
Procedure CodexSubscriptionArguments(Args: TStrings);

Implementation

Uses
  fpjson, jsonparser, StrUtils, AssistantProtocol;

Const
  MaxCodexFrameBytes = 1048576;

Procedure CodexSubscriptionArguments(Args: TStrings);
Begin
  Args.Clear;
  Args.Add('-c');
  Args.Add('forced_login_method="chatgpt"');
  Args.Add('-c');
  Args.Add('model_provider="openai"');
  { ChatGPT sign-in enables codex_apps by default even in an otherwise empty
    CODEX_HOME. Override on every launch, including existing preview profiles. }
  Args.Add('-c');
  Args.Add('features.apps=false');
  { Define the broker-only filesystem profile on every launch so existing
    managed profiles need no migration or renewed sign-in. }
  Args.Add('-c');
  Args.Add('permissions.lazarus_ide.filesystem={":minimal"="read"}');
  Args.Add('-c');
  Args.Add('permissions.lazarus_ide.network.enabled=false');
  Args.Add('app-server');
  Args.Add('--listen');
  Args.Add('stdio://');
End;

Constructor TAssistantCodexHandshake.Create;
Begin
  Inherited Create;
  FOutgoing := TStringList.Create;
  FState := ccsClosed;
End;

Destructor TAssistantCodexHandshake.Destroy;
Begin
  FOutgoing.Free;
  Inherited Destroy;
End;

Procedure TAssistantCodexHandshake.Close;
Begin
  FState := ccsClosed;
  FBuffer := '';
  FOutgoing.Clear;
  FInitializeId := 0;
  FAccountId := 0;
  FLoginRequestId := 0;
  FLoginId := '';
  FLoginUrl := '';
End;

Procedure TAssistantCodexHandshake.Fail(Const Reason: String);
Begin
  Close;
  FState := ccsFailed;
  FLastError := Reason;
End;

Function TAssistantCodexHandshake.Request(Const Method, Params: String): Int64;
Begin
  Inc(FNextId);
  Result := FNextId;
  FOutgoing.Add('{"id":' + IntToStr(Result) + ',"method":"' +
    JsonEscapeText(Method) + '","params":' + Params + '}');
End;

Procedure TAssistantCodexHandshake.Start(ExperimentalTools: Boolean);
Begin
  If FState <> ccsClosed Then
    Raise Exception.Create('Close the existing Codex connection before restarting.');
  FLastError := '';
  FState := ccsInitializing;
  FInitializeId := Request('initialize',
    '{"clientInfo":{"name":"lazworkflow","title":"Lazarus Project Assistant","version":"0.1.0"},' +
    '"capabilities":{"experimentalApi":' + LowerCase(BoolToStr(ExperimentalTools, True)) + '}}');
End;

Procedure TAssistantCodexHandshake.RemoveQueuedRequest(Id: Int64);
Var
  I: Integer;
  Prefix: String;
Begin
  If Id = 0 Then Exit;
  Prefix := '{"id":' + IntToStr(Id) + ',';
  For I := FOutgoing.Count - 1 DownTo 0 Do
    If Pos(Prefix, FOutgoing[I]) = 1 Then FOutgoing.Delete(I);
End;

Procedure TAssistantCodexHandshake.CheckAccount;
Begin
  FState := ccsCheckingAccount;
  FLastError := '';
  { Invalidate older account replies when a notification changes authentication. }
  RemoveQueuedRequest(FAccountId);
  FAccountId := Request('account/read', '{"refreshToken":false}');
End;

Procedure TAssistantCodexHandshake.StartChatGPTLogin;
Begin
  If FState <> ccsNeedsSignIn Then
    Raise Exception.Create('ChatGPT sign-in is not available in the current connection state.');
  FLoginId := '';
  FLoginUrl := '';
  FLastError := '';
  FState := ccsSigningIn;
  FLoginRequestId := Request('account/login/start', '{"type":"chatgpt"}');
End;

Function TAssistantCodexHandshake.TakeOutgoing(Out Frame: String): Boolean;
Begin
  Frame := '';
  Result := FOutgoing.Count > 0;
  If Not Result Then Exit;
  Frame := FOutgoing[0] + #10;
  FOutgoing.Delete(0);
End;

Procedure TAssistantCodexHandshake.HandleLine(Const Line: String);
Var
  Data, Node, Account, Value: TJSONData;
  Root, Params: TJSONObject;
  Id: Int64;
  Method, Kind, Url: String;
Begin
  Data := GetJSON(Line);
  Try
    If Not (Data Is TJSONObject) Then
      Raise Exception.Create('Expected an object');
    Root := TJSONObject(Data);
    Method := Root.Get('method', '');
    Node := Root.Find('id');
    If Method <> '' Then
      Begin
        If Assigned(Node) Then
          Begin
            { No server-initiated tool/approval requests are supported yet. }
            If Not (Node.JSONType In [jtNumber, jtString]) Then
              Raise Exception.Create('Invalid server request ID');
            If FOutgoing.Count >= 16 Then Raise Exception.Create('Too many server requests');
            FOutgoing.Add('{"id":' + Node.AsJSON +
              ',"error":{"code":-32601,"message":"Method not supported by this client"}}');
            Exit;
          End;
        Value := Root.Find('params');
        If Not (Value Is TJSONObject) Then Exit;
        Params := TJSONObject(Value);
        If FState = ccsInitializing Then Exit;
        If Method = 'account/updated' Then
          Begin
            Kind := Params.Get('authMode', '');
            If Kind = 'chatgpt' Then CheckAccount
            Else
              Begin
                RemoveQueuedRequest(FAccountId);
                RemoveQueuedRequest(FLoginRequestId);
                FAccountId := 0;
                FLoginRequestId := 0;
                FLoginId := '';
                FLoginUrl := '';
                FState := ccsNeedsSignIn;
                FLastError := 'ChatGPT subscription sign-in is required. API-key and other authentication modes are disabled.';
              End;
          End
            Else If (Method = 'account/login/completed') And
          (FLoginId <> '') And (Params.Get('loginId', '') = FLoginId) Then
            Begin
              FLoginId := '';
              FLoginUrl := '';
              If Params.Get('success', False) Then CheckAccount
              Else
                Begin
                  FState := ccsNeedsSignIn;
                  FLastError := 'ChatGPT sign-in did not complete. No metered fallback was attempted.';
                End;
            End;
        Exit;
      End;
    If Not Assigned(Node) Or (Node.JSONType <> jtNumber) Then Exit;
    Id := Node.AsInt64;
    If (Id = 0) Or ((Id <> FInitializeId) And (Id <> FAccountId) And
      (Id <> FLoginRequestId)) Then Exit;
    If Assigned(Root.Find('error')) Then
      Begin
        Fail('Codex rejected the connection/account request. No metered fallback was attempted.');
        Exit;
      End;
    Value := Root.Find('result');
    If Not (Value Is TJSONObject) Then
      Raise Exception.Create('Missing result object');
    Params := TJSONObject(Value);
    If Id = FInitializeId Then
      Begin
        FInitializeId := 0;
        FOutgoing.Add('{"method":"initialized","params":{}}');
        CheckAccount;
      End
    Else If Id = FAccountId Then
      Begin
        FAccountId := 0;
        Account := Params.Find('account');
        Kind := '';
        If Account Is TJSONObject Then Kind := TJSONObject(Account).Get('type', '');
        If (Kind = 'chatgpt') And Params.Get('requiresOpenaiAuth', False) Then
          Begin
            FState := ccsSubscriptionAuthenticated;
            FLastError := '';
          End
        Else
          Begin
            FState := ccsNeedsSignIn;
            FLastError := 'Sign in with ChatGPT. API-key, unknown and external-provider accounts are disabled.';
          End;
      End
        Else If Id = FLoginRequestId Then
          Begin
            FLoginRequestId := 0;
            If Params.Get('type', '') <> 'chatgpt' Then
              Begin
                Fail('Codex did not start the required ChatGPT sign-in flow.');
                Exit;
              End;
            Url := Params.Get('authUrl', '');
            If (Pos('https://auth.openai.com/', Url) <> 1) And
              (Pos('https://chatgpt.com/', Url) <> 1) Then
                Begin
                  Fail('Codex returned an unexpected sign-in URL.');
                  Exit;
                End;
            FLoginId := Params.Get('loginId', '');
            If FLoginId = '' Then
              Begin
                Fail('Codex returned no sign-in identifier.');
                Exit;
              End;
            FLoginUrl := Url;
          End;
  Finally
    Data.Free;
  End;
End;

Procedure TAssistantCodexHandshake.Feed(Const Bytes: String);
Var
  StartAt, NewlineAt, Count: Integer;
  Line: String;
Begin
  If FState In [ccsClosed, ccsFailed] Then Exit;
  Try
    StartAt := 1;
    While StartAt <= Length(Bytes) Do
      Begin
        NewlineAt := PosEx(#10, Bytes, StartAt);
        If NewlineAt = 0 Then Count := Length(Bytes) - StartAt + 1
        Else Count := NewlineAt - StartAt;
        If Count > MaxCodexFrameBytes - Length(FBuffer) Then
          Raise Exception.Create('Frame too large');
        FBuffer := FBuffer + Copy(Bytes, StartAt, Count);
        If NewlineAt = 0 Then Exit;
        Line := Trim(FBuffer);
        FBuffer := '';
        If Line <> '' Then HandleLine(Line);
        If FState In [ccsClosed, ccsFailed] Then Exit;
        StartAt := NewlineAt + 1;
      End;
  Except
    { Raw protocol data can contain account details; do not echo it into logs. }
    On E: Exception Do Fail('Invalid or oversized Codex protocol frame.');
  End;
End;
End.
