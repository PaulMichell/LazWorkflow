Unit AssistantMonitorPair;

{ Pairing codes and hashed client tokens. Codes and tokens are never logged.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, AssistantMonitorSettings;

Const
  MonitorPairCodeLength = 10;
  MonitorPairLifetimeMs = 120000;
  MonitorPairLockoutAttempts = 3;

Type
  TMonitorAuth = (maAccepted, maUnknown, maRevoked);

Function IssueMonitorPairCode(Out Code: String): Boolean;
Function MonitorPairCodeText: String;
Procedure ExpireMonitorPairCode;
Function ServeMonitorPair(Const RequestBody: String; Out Status: Integer; Out Answer: String): Boolean;
Function MonitorAuthorize(Const Token: String; Out Status: Integer; Out Body: String): TMonitorAuth;
Function MonitorTokenRevoked(Const Token: String): Boolean;
Function RevokeMonitorPairedClient(Const ClientId: String; Out ErrorText: String): Boolean;
Function RevokeAllMonitorPairedClients(Out ErrorText: String): Boolean;
Procedure BeginMonitorPairFixture;
Procedure EndMonitorPairFixture;

Implementation

Uses
  Classes, SyncObjs, fpjson, jsonparser, fpsha256, fphashutils, GrokOAuth, AssistantMonitorTls, AssistantMonitorPulse,
  AssistantMonitorCodec;

Const
  PairAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

Var
  PairLock: TRTLCriticalSection;
  PairCode: String;
  PairIssuedAt: QWord;
  PairUsed: Boolean;
  PairFailures: Integer;
  PairLocked: Boolean;
  RevokedHashes: Array Of String;
  FixtureActive: Boolean;
  FixtureClients: TMonitorClientArray;
  FixtureRequireCode: Boolean;

Function ErrorJson(Const Reason, MessageText: String): String;
Begin
  Result := '{"reason":"' + Reason + '","message":"' + MessageText + '"}';
End;

Function HashToken(Const Token: String): String;
Var
  Raw, Digest: TBytes;
  Hex: AnsiString;
Begin
  Result := '';
  Raw := Nil;
  Digest := Nil;
  SetLength(Raw, Length(Token));
  If Length(Raw) > 0 Then
    Move(Token[1], Raw[0], Length(Raw));
  TSHA256.DigestBytes(Raw, Digest);
  Hex := BytesToHexStr(Digest);
  Result := LowerCase(String(Hex));
End;

Function RandomHex(ByteCount: Integer): String;
Var
  Bytes: TBytes;
  Hex: AnsiString;
Begin
  Result := '';
  Bytes := Nil;
  SetLength(Bytes, ByteCount);
  If Not CryptoGetRandomBytes(@Bytes[0], ByteCount) Then
    Exit;
  Hex := BytesToHexStr(Bytes);
  Result := LowerCase(String(Hex));
End;

Function NewPairCode: String;
Var
  Bytes: TBytes;
  Index: Integer;
Begin
  Result := '';
  Bytes := Nil;
  SetLength(Bytes, MonitorPairCodeLength);
  If Not CryptoGetRandomBytes(@Bytes[0], MonitorPairCodeLength) Then
    Exit;
  SetLength(Result, MonitorPairCodeLength);
  For Index := 1 To MonitorPairCodeLength Do
    Result[Index] := PairAlphabet[(Bytes[Index - 1] Mod Length(PairAlphabet)) + 1];
End;

Function HostName: String;
Begin
  Result := GetEnvironmentVariable('COMPUTERNAME');
  If Result = '' Then
    Result := GetEnvironmentVariable('HOSTNAME');
  If Result = '' Then
    Result := 'desktop';
End;

Function HostFingerprint: String;
Var
  ErrorText: String;
Begin
  Result := '';
  If Not MonitorHostFingerprint(Result, ErrorText) Then
    Result := '';
End;

Procedure CopyClients(Const Source: TMonitorClientArray; Out Dest: TMonitorClientArray);
Var
  Index: Integer;
Begin
  SetLength(Dest, Length(Source));
  For Index := 0 To High(Source) Do
    Dest[Index] := Source[Index];
End;

Procedure LoadClients(Out Clients: TMonitorClientArray; Out RequireCode: Boolean);
Var
  Settings: TMonitorSettings;
  ErrorText: String;
Begin
  SetLength(Clients, 0);
  RequireCode := True;
  If FixtureActive Then
    Begin
      CopyClients(FixtureClients, Clients);
      RequireCode := FixtureRequireCode;
      Exit;
    End;
  If Not LoadMonitorSettings(Settings, ErrorText) Then
    Exit;
  CopyClients(Settings.Clients, Clients);
  RequireCode := Settings.RequirePairCode;
End;

Function SaveClients(Const Clients: TMonitorClientArray; Out ErrorText: String): Boolean;
Var
  Settings: TMonitorSettings;
Begin
  ErrorText := '';
  If FixtureActive Then
    Begin
      CopyClients(Clients, FixtureClients);
      Result := True;
      Exit;
    End;
  Result := LoadMonitorSettings(Settings, ErrorText);
  If Not Result Then
    Exit;
  CopyClients(Clients, Settings.Clients);
  Result := SaveMonitorSettings(Settings, ErrorText);
End;

Procedure RememberRevoked(Const TokenHash: String);
Var
  Index: Integer;
Begin
  If TokenHash = '' Then
    Exit;
  For Index := 0 To High(RevokedHashes) Do
    If RevokedHashes[Index] = TokenHash Then
      Exit;
  SetLength(RevokedHashes, Length(RevokedHashes) + 1);
  RevokedHashes[High(RevokedHashes)] := TokenHash;
End;

Function HashRevoked(Const TokenHash: String): Boolean;
Var
  Index: Integer;
Begin
  Result := False;
  If TokenHash = '' Then
    Exit;
  For Index := 0 To High(RevokedHashes) Do
    If RevokedHashes[Index] = TokenHash Then
      Exit(True);
End;

Function ClientByHash(Const Clients: TMonitorClientArray; Const TokenHash: String): Integer;
Var
  Index: Integer;
Begin
  Result := -1;
  For Index := 0 To High(Clients) Do
    If Clients[Index].TokenHash = TokenHash Then
      Exit(Index);
End;

Function MonitorPairCodeText: String;
Begin
  Result := '';
  EnterCriticalSection(PairLock);
  Try
    If (PairCode <> '') And (Not PairUsed) And (GetTickCount64 - PairIssuedAt < MonitorPairLifetimeMs) And (Not PairLocked) Then
      Result := PairCode;
  Finally
    LeaveCriticalSection(PairLock);
  End;
End;

Function IssueMonitorPairCode(Out Code: String): Boolean;
Begin
  Code := NewPairCode;
  Result := Code <> '';
  If Not Result Then
    Exit;
  EnterCriticalSection(PairLock);
  Try
    PairCode := Code;
    PairIssuedAt := GetTickCount64;
    PairUsed := False;
    PairFailures := 0;
    PairLocked := False;
  Finally
    LeaveCriticalSection(PairLock);
  End;
End;

Procedure ExpireMonitorPairCode;
Begin
  EnterCriticalSection(PairLock);
  Try
    If PairIssuedAt > MonitorPairLifetimeMs Then
      PairIssuedAt := PairIssuedAt - MonitorPairLifetimeMs - 1
    Else
      PairIssuedAt := 1;
  Finally
    LeaveCriticalSection(PairLock);
  End;
End;

Function CodeRejected(Const Code: String; Out MessageText: String): Boolean;
Var
  NowTick: QWord;
Begin
  MessageText := 'The pairing code was not accepted.';
  Result := True;
  EnterCriticalSection(PairLock);
  Try
    If PairLocked Or (PairFailures >= MonitorPairLockoutAttempts) Then
      Begin
        PairLocked := True;
        MessageText := 'Pairing is locked. Generate a new code.';
        Exit;
      End;
    NowTick := GetTickCount64;
    If (PairCode = '') Or PairUsed Or (NowTick - PairIssuedAt >= MonitorPairLifetimeMs) Or
      (Not SameText(Code, PairCode)) Then
      Begin
        Inc(PairFailures);
        If PairFailures >= MonitorPairLockoutAttempts Then
          PairLocked := True;
        Exit;
      End;
    PairUsed := True;
    Result := False;
  Finally
    LeaveCriticalSection(PairLock);
  End;
End;

Function ServeMonitorPair(Const RequestBody: String; Out Status: Integer; Out Answer: String): Boolean;
Var
  Data: TJSONData;
  Root: TJSONObject;
  Code, ClientId, ClientName, Token, TokenHash, ErrorText: String;
  Clients: TMonitorClientArray;
  RequireCode: Boolean;
  Index, Kept: Integer;
  Obj: TJSONObject;
Begin
  Result := True;
  Status := 400;
  Answer := ErrorJson('protocol', 'The pairing request was not understood.');
  SetLength(Clients, 0);
  Data := Nil;
  Try
    Data := GetJSON(RequestBody);
  Except
    Data := Nil;
  End;
  If Not (Data Is TJSONObject) Then
    Begin
      Data.Free;
      Exit;
    End;
  Root := TJSONObject(Data);
  Try
    Code := Trim(Root.Get('code', ''));
    ClientId := Trim(Root.Get('client_id', ''));
    ClientName := Trim(Root.Get('client_name', ''));
    If (ClientId = '') Or (Length(ClientId) > 80) Or (Pos('/', ClientId) > 0) Or (Pos('\', ClientId) > 0) Then
      Begin
        Answer := ErrorJson('protocol', 'The client id was not accepted.');
        Exit;
      End;
    If ClientName = '' Then
      ClientName := ClientId;
    LoadClients(Clients, RequireCode);
    If RequireCode And CodeRejected(Code, ErrorText) Then
      Begin
        Status := 401;
        Answer := ErrorJson('auth', ErrorText);
        Exit;
      End;
    Token := RandomHex(32);
    If Length(Token) <> 64 Then
      Begin
        Status := 503;
        Answer := ErrorJson('no_session', 'Could not issue a token.');
        Exit;
      End;
    TokenHash := HashToken(Token);
    Kept := 0;
    For Index := 0 To High(Clients) Do
      If Clients[Index].Id <> ClientId Then
        Begin
          Clients[Kept] := Clients[Index];
          Inc(Kept);
        End
      Else
        RememberRevoked(Clients[Index].TokenHash);
    SetLength(Clients, Kept + 1);
    Clients[Kept].Id := ClientId;
    Clients[Kept].Name := ClientName;
    Clients[Kept].TokenHash := TokenHash;
    Clients[Kept].Fingerprint := HostFingerprint;
    Clients[Kept].PairedAt := '';
    If Not SaveClients(Clients, ErrorText) Then
      Begin
        Status := 503;
        Answer := ErrorJson('no_session', 'Could not store the pairing.');
        Exit;
      End;
    Answer := MonitorPairJson(Token, HostName, Clients[Kept].Fingerprint);
    Status := 200;
  Finally
    Root.Free;
  End;
End;

Function MonitorAuthorize(Const Token: String; Out Status: Integer; Out Body: String): TMonitorAuth;
Var
  Clients: TMonitorClientArray;
  RequireCode: Boolean;
  TokenHash: String;
Begin
  Status := 401;
  Body := ErrorJson('auth', 'The token was not accepted.');
  Result := maUnknown;
  If Token = '' Then
    Exit;
  TokenHash := HashToken(Token);
  If HashRevoked(TokenHash) Then
    Begin
      Status := 403;
      Body := ErrorJson('revoked', 'This phone was revoked.');
      Result := maRevoked;
      Exit;
    End;
  LoadClients(Clients, RequireCode);
  If ClientByHash(Clients, TokenHash) >= 0 Then
    Begin
      Status := 200;
      Body := '';
      Result := maAccepted;
    End;
End;

Function MonitorTokenRevoked(Const Token: String): Boolean;
Begin
  Result := (Token <> '') And HashRevoked(HashToken(Token));
End;

Function RevokeHashes(Const Clients: TMonitorClientArray; Const ClientId: String; All: Boolean): Boolean;
Var
  Index: Integer;
Begin
  Result := False;
  For Index := 0 To High(Clients) Do
    If All Or (Clients[Index].Id = ClientId) Then
      Begin
        RememberRevoked(Clients[Index].TokenHash);
        Result := True;
      End;
End;

Function RevokeMonitorPairedClient(Const ClientId: String; Out ErrorText: String): Boolean;
Var
  Clients: TMonitorClientArray;
  RequireCode: Boolean;
Begin
  LoadClients(Clients, RequireCode);
  RevokeHashes(Clients, ClientId, False);
  RevokeMonitorClient(Clients, ClientId);
  Result := SaveClients(Clients, ErrorText);
  If Result Then
    WakeMonitorPulse;
End;

Function RevokeAllMonitorPairedClients(Out ErrorText: String): Boolean;
Var
  Clients: TMonitorClientArray;
  RequireCode: Boolean;
Begin
  LoadClients(Clients, RequireCode);
  RevokeHashes(Clients, '', True);
  SetLength(Clients, 0);
  Result := SaveClients(Clients, ErrorText);
  If Result Then
    WakeMonitorPulse;
End;

Procedure BeginMonitorPairFixture;
Begin
  FixtureActive := True;
  FixtureRequireCode := True;
  SetLength(FixtureClients, 0);
  SetLength(RevokedHashes, 0);
  PairCode := '';
  PairUsed := False;
  PairFailures := 0;
  PairLocked := False;
End;

Procedure EndMonitorPairFixture;
Begin
  FixtureActive := False;
  SetLength(FixtureClients, 0);
  SetLength(RevokedHashes, 0);
End;

Initialization
  InitCriticalSection(PairLock);

Finalization
  DoneCriticalSection(PairLock);

End.
