Unit AssistantAccountUsage;

{ Account allowance for the status footer. Not the per-turn usage log.

  grok is registered. The desktop OAuth token has grok-cli:access, which is
  the credential Grok Build uses for GET /v1/billing?format=credits. That is
  the weekly pool the Build usage screen shows. It is not the team management
  API, and this unit does not read a team id. claude stays unregistered: plan
  quota is an interactive screen, not a JSON result this program owns.
  openai-compatible is registered, but only AssistantOpenRouterApiBase is
  queried, via GET /key. A custom base returns unknown and does not open a
  socket. codex is registered. That read is a short-lived app-server, only
  while the connection is idle, and is not sent on the live turn client.
  Codex captions are remaining percent, matching the app's Usage remaining
  panel, not the raw usedPercent field. A missing registration is unknown,
  not an error, and does not open a socket.

  OpenRouter and Codex response parsers are plain functions so a fixture can
  fill a snapshot without a socket or a process. Caption and hint never receive
  a key, token, Authorization header, or account email.

  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Interface

Uses
  SysUtils, AssistantConnections, AssistantCompatibleClient;

Type
  TAccountUsageSnapshot = Record
    Known: Boolean;
    ConnectionId: String;
    Caption: String;
    Hint: String;
    FetchedAt: TDateTime;
  End;

  { HTTP backends ignore RuntimePath and ProfileDir. Codex uses them so this unit does not reach into the form. }
  TAccountUsageQuery = Function(Connection: TAssistantConnection; Const RuntimePath, ProfileDir: String;
    Out Snapshot: TAccountUsageSnapshot; Out ErrorText: String): Boolean;

Procedure ClearAccountUsageSnapshot(Out Snapshot: TAccountUsageSnapshot);
Procedure RegisterAccountUsageQuery(Const BackendId: String; Query: TAccountUsageQuery);
/// Does not append a turn-usage line and does not change the Settings usage sentence.
Function QueryAccountUsage(Connection: TAssistantConnection; Const RuntimePath, ProfileDir: String;
  Out Snapshot: TAccountUsageSnapshot; Out ErrorText: String): Boolean;
Function AccountUsageRegistered(Const BackendId: String): Boolean;
/// Keeps a known figure for the same connection when it is under 15 minutes old. The caption is never an error. 
Function AccountUsageKeepOnFailure(Const Current: TAccountUsageSnapshot; Const ConnectionId: String;
  NowTime: TDateTime): TAccountUsageSnapshot;

Type
  { Shared by the footer and the usage worker. The worker may outlive the form. }
  TAccountUsageSlot = Class
  Private
    FLock: TRTLCriticalSection;
    FSnapshot: TAccountUsageSnapshot;
    FActiveId: String;
    FClosed: LongInt;
    FRefs: LongInt;
  Public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Retain;
    Procedure Release;
    Procedure Close;
    Function IsClosed: Boolean;
    Procedure SetActive(Const ConnectionId: String);
    Function ReadSnapshot: TAccountUsageSnapshot;
    { True when the caller should log one generic warning. A discarded result returns false. }
    Function StoreResult(Const Item: TAccountUsageSnapshot; QueryOk: Boolean): Boolean;
  End;
Function AccountUsageApplies(Const Snapshot: TAccountUsageSnapshot; Const ActiveConnectionId: String): Boolean;
Function AccountUsageCaption(Const Snapshot: TAccountUsageSnapshot; Const ActiveConnectionId: String): String;
Function AccountUsageHint(Const Snapshot: TAccountUsageSnapshot; Const ActiveConnectionId: String): String;
Function ParseOpenRouterAccountUsage(Const Body, ConnectionId: String; Out Snapshot: TAccountUsageSnapshot;
  Out ErrorText: String): Boolean;
Function ParseCodexAccountUsage(Const Body, ConnectionId: String; Out Snapshot: TAccountUsageSnapshot;
  Out ErrorText: String): Boolean;
Function ParseGrokAccountUsage(Const Body, ConnectionId: String; Out Snapshot: TAccountUsageSnapshot;
  Out ErrorText: String): Boolean;
/// Picks the Grok Build session from auth.json. Does not return an API key, email, or refresh token.
Function SelectGrokCliCredential(Const AuthBody: String; Out Token, UserId: String): Boolean;
/// Tests pass a stand-in auth.json. Empty body means no CLI session. Nil the override to read the file.
Procedure SetGrokCliAuthBody(Const Body: String);
Procedure ClearGrokCliAuthBody;
/// Both functions are required. A nil pair uses the real HTTPS client. Do not log the headers.
Procedure SetAccountUsageCompatibleTransport(GetFn: TCompatibleHttpGet; PostFn: TCompatibleHttpPost);

Implementation

Uses
  Classes, DateUtils, base64, fpjson, jsonparser, AssistantCodexUsage, AssistantHttps, WorkflowLog;

Type
  TAccountUsageRegistration = Record
    BackendId: String;
    Query: TAccountUsageQuery;
  End;

  TUsageWindow = Record
    Present: Boolean;
    UsedPercent: Double;
    Minutes: Integer;
    ResetsAt: Int64;
    HasReset: Boolean;
  End;

Const
  { Secondary window joins the caption only while the whole line stays this short. }
  AccountUsageCaptionLimit = 32;

Var
  Registry: Array Of TAccountUsageRegistration;
  RegistryLock: TRTLCriticalSection;
  RegistryReady: Boolean;
  AccountGet: TCompatibleHttpGet;
  AccountPost: TCompatibleHttpPost;

Procedure ClearAccountUsageSnapshot(Out Snapshot: TAccountUsageSnapshot);
Begin
  Snapshot.Known := False;
  Snapshot.ConnectionId := '';
  Snapshot.Caption := '';
  Snapshot.Hint := '';
  Snapshot.FetchedAt := 0;
End;

Function FindQuery(Const BackendId: String): TAccountUsageQuery;
Var
  I: Integer;
Begin
  Result := Nil;
  If Not RegistryReady Then
    Exit;
  EnterCriticalSection(RegistryLock);
  Try
    For I := 0 To High(Registry) Do
      If Registry[I].BackendId = BackendId Then
        Exit(Registry[I].Query);
  Finally
    LeaveCriticalSection(RegistryLock);
  End;
End;

Procedure RegisterAccountUsageQuery(Const BackendId: String; Query: TAccountUsageQuery);
Var
  I, Count: Integer;
Begin
  If (BackendId = '') Or (Not Assigned(Query)) Or (Not RegistryReady) Then
    Exit;
  EnterCriticalSection(RegistryLock);
  Try
    For I := 0 To High(Registry) Do
      If Registry[I].BackendId = BackendId Then
        Begin
          Registry[I].Query := Query;
          Exit;
        End;
    Count := Length(Registry);
    SetLength(Registry, Count + 1);
    Registry[Count].BackendId := BackendId;
    Registry[Count].Query := Query;
  Finally
    LeaveCriticalSection(RegistryLock);
  End;
End;

Function QueryAccountUsage(Connection: TAssistantConnection; Const RuntimePath, ProfileDir: String;
  Out Snapshot: TAccountUsageSnapshot; Out ErrorText: String): Boolean;
Var
  Query: TAccountUsageQuery;
Begin
  ClearAccountUsageSnapshot(Snapshot);
  ErrorText := '';
  Result := True;
  If Not Assigned(Connection) Or (Connection.Backend = '') Then
    Exit;
  Snapshot.ConnectionId := Connection.Id;
  Query := FindQuery(Connection.Backend);
  If Not Assigned(Query) Then
    Exit;
  Try
    Result := Query(Connection, RuntimePath, ProfileDir, Snapshot, ErrorText);
  Except
    On E: Exception Do
      Begin
        ClearAccountUsageSnapshot(Snapshot);
        Snapshot.ConnectionId := Connection.Id;
        ErrorText := 'Account usage query failed.';
        Result := False;
        Exit;
      End;
  End;
  If Snapshot.ConnectionId = '' Then
    Snapshot.ConnectionId := Connection.Id;
  If (Not Result) And (ErrorText = '') Then
    ErrorText := 'Account usage query failed.';
End;

Function AccountUsageRegistered(Const BackendId: String): Boolean;
Begin
  Result := Assigned(FindQuery(BackendId));
End;

Constructor TAccountUsageSlot.Create;
Begin
  Inherited Create;
  InitCriticalSection(FLock);
  FRefs := 1;
End;

Destructor TAccountUsageSlot.Destroy;
Begin
  DoneCriticalSection(FLock);
  Inherited Destroy;
End;

Procedure TAccountUsageSlot.Retain;
Begin
  InterlockedIncrement(FRefs);
End;

Procedure TAccountUsageSlot.Release;
Begin
  If InterlockedDecrement(FRefs) = 0 Then
    Free;
End;

Procedure TAccountUsageSlot.Close;
Begin
  EnterCriticalSection(FLock);
  Try
    FClosed := 1;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TAccountUsageSlot.IsClosed: Boolean;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := FClosed <> 0;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Procedure TAccountUsageSlot.SetActive(Const ConnectionId: String);
Begin
  EnterCriticalSection(FLock);
  Try
    FActiveId := ConnectionId;
    ClearAccountUsageSnapshot(FSnapshot);
    FSnapshot.ConnectionId := ConnectionId;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TAccountUsageSlot.ReadSnapshot: TAccountUsageSnapshot;
Begin
  EnterCriticalSection(FLock);
  Try
    Result := FSnapshot;
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function TAccountUsageSlot.StoreResult(Const Item: TAccountUsageSnapshot; QueryOk: Boolean): Boolean;
Begin
  Result := False;
  EnterCriticalSection(FLock);
  Try
    If (FClosed <> 0) Or (Item.ConnectionId <> FActiveId) Then
      Exit;
    If QueryOk Then
      Begin
        FSnapshot := Item;
        Exit;
      End;
    Result := True;
    FSnapshot := AccountUsageKeepOnFailure(FSnapshot, FActiveId, Now);
  Finally
    LeaveCriticalSection(FLock);
  End;
End;

Function AccountUsageKeepOnFailure(Const Current: TAccountUsageSnapshot; Const ConnectionId: String;
  NowTime: TDateTime): TAccountUsageSnapshot;
Begin
  Result := Current;
  If (Not Current.Known) Or (Current.Caption = '') Or (Current.ConnectionId = '') Or
    (Current.ConnectionId <> ConnectionId) Or (Current.FetchedAt <= 0) Or
    ((NowTime - Current.FetchedAt) >= (15 / (24 * 60))) Then
    Begin
      ClearAccountUsageSnapshot(Result);
      Result.ConnectionId := ConnectionId;
      Exit;
    End;
  Result.Hint := 'Could not refresh account usage.';
End;

Function AccountUsageApplies(Const Snapshot: TAccountUsageSnapshot; Const ActiveConnectionId: String): Boolean;
Begin
  Result := Snapshot.Known And (Snapshot.Caption <> '') And (Snapshot.ConnectionId <> '') And
    (Snapshot.ConnectionId = ActiveConnectionId);
End;

Function AccountUsageCaption(Const Snapshot: TAccountUsageSnapshot; Const ActiveConnectionId: String): String;
Begin
  If AccountUsageApplies(Snapshot, ActiveConnectionId) Then
    Result := Snapshot.Caption
  Else
    Result := '';
End;

Function AccountUsageHint(Const Snapshot: TAccountUsageSnapshot; Const ActiveConnectionId: String): String;
Begin
  If AccountUsageApplies(Snapshot, ActiveConnectionId) Then
    Result := Snapshot.Hint
  Else
    Result := '';
End;

Function DotDecimal(Const Text: String): String;
Begin
  Result := StringReplace(Text, ',', '.', []);
End;

Function FormatCredits(Value: Double): String;
Var
  Text: String;
  DotAt: Integer;
Begin
  Text := DotDecimal(FormatFloat('0.00####', Value));
  DotAt := Pos('.', Text);
  While (DotAt > 0) And (Length(Text) > DotAt + 2) And (Text[Length(Text)] = '0') Do
    Delete(Text, Length(Text), 1);
  Result := 'Left $' + Text;
End;

Function FormatAmount(Value: Double): String;
Var
  Text: String;
  DotAt: Integer;
Begin
  Text := DotDecimal(FormatFloat('0.####', Value));
  DotAt := Pos('.', Text);
  If DotAt = Length(Text) Then
    Delete(Text, DotAt, 1);
  Result := Text;
End;

Function PercentText(Value: Double): String;
Begin
  If Abs(Value - Round(Value)) < 0.05 Then
    Result := IntToStr(Round(Value))
  Else
    Result := DotDecimal(FormatFloat('0.0', Value));
  Result := Result + '%';
End;

Function WindowTag(Minutes: Integer): String;
Begin
  If Minutes = 300 Then
    Result := '5h'
  Else If Minutes = 10080 Then
    Result := '7d'
  Else
    Result := IntToStr(Minutes) + 'm';
End;

Function SafeToken(Const Value: String): String;
Var
  I: Integer;
Begin
  Result := '';
  If (Value = '') Or (Length(Value) > 32) Then
    Exit;
  For I := 1 To Length(Value) Do
    If Not (Value[I] In ['a'..'z', 'A'..'Z', '0'..'9', '_', '-']) Then
      Exit;
  Result := Value;
End;

Function JsonObject(Data: TJSONData): TJSONObject;
Begin
  If Data Is TJSONObject Then
    Result := TJSONObject(Data)
  Else
    Result := Nil;
End;

Function NumberValue(Node: TJSONData; Out Value: Double): Boolean;
Begin
  Result := Assigned(Node) And (Node.JSONType = jtNumber);
  If Result Then
    Value := Node.AsFloat
  Else
    Value := 0;
End;

Procedure NoteFetched(Var Snapshot: TAccountUsageSnapshot);
Begin
  Snapshot.FetchedAt := Now;
End;

Function OpenRouterHint(Payload: TJSONObject): String;
Var
  Daily: Double;
Begin
  Result := 'Fetched ' + FormatDateTime('yyyy-mm-dd hh:nn', Now);
  If NumberValue(Payload.Find('usage_daily'), Daily) Then
    Result := 'Daily ' + FormatAmount(Daily) + '. ' + Result;
End;

Function ParseOpenRouterAccountUsage(Const Body, ConnectionId: String; Out Snapshot: TAccountUsageSnapshot;
  Out ErrorText: String): Boolean;
Var
  Data: TJSONData;
  Root, Payload, FreeRequests: TJSONObject;
  LimitNode, RemainNode: TJSONData;
  Amount, Remaining: Double;
Begin
  Result := False;
  ErrorText := '';
  ClearAccountUsageSnapshot(Snapshot);
  Snapshot.ConnectionId := ConnectionId;
  Data := Nil;
  Try
    Try
      Data := GetJSON(Body);
    Except
      On E: Exception Do
        Begin
          ErrorText := 'OpenRouter key usage was not JSON.';
          Exit;
        End;
    End;
    Root := JsonObject(Data);
    If Not Assigned(Root) Then
      Begin
        ErrorText := 'OpenRouter key usage was not an object.';
        Exit;
      End;
    Payload := JsonObject(Root.Find('data'));
    If Not Assigned(Payload) Then
      Begin
        ErrorText := 'OpenRouter key usage had no data object.';
        Exit;
      End;
    LimitNode := Payload.Find('limit_remaining');
    If NumberValue(LimitNode, Amount) Then
      Begin
        Snapshot.Known := True;
        Snapshot.Caption := FormatCredits(Amount);
        Snapshot.Hint := OpenRouterHint(Payload);
        NoteFetched(Snapshot);
        Result := True;
        Exit;
      End;
    If Assigned(LimitNode) And (LimitNode.JSONType = jtNull) Then
      Begin
        FreeRequests := JsonObject(Payload.Find('free_model_daily_requests'));
        RemainNode := Nil;
        If Assigned(FreeRequests) Then
          RemainNode := FreeRequests.Find('remaining');
        If NumberValue(RemainNode, Remaining) Then
          Begin
            Snapshot.Known := True;
            Snapshot.Caption := Format('Free %d left', [Round(Remaining)]);
            Snapshot.Hint := OpenRouterHint(Payload);
            NoteFetched(Snapshot);
            Result := True;
            Exit;
          End;
        { Explicit null limit and no free-request counter: unlimited, nothing to show. }
        NoteFetched(Snapshot);
        Result := True;
        Exit;
      End;
    ErrorText := 'OpenRouter key usage did not include a balance.';
  Finally
    Data.Free;
  End;
End;

Function ResetText(ResetsAt: Int64): String;
Begin
  If ResetsAt <= 0 Then
    Result := ''
  Else
    Result := FormatDateTime('yyyy-mm-dd hh:nn', UnixToDateTime(ResetsAt));
End;

Function ReadWindow(Node: TJSONData; Out Window: TUsageWindow; Out ErrorText: String): Boolean;
Var
  Obj: TJSONObject;
  Used: Double;
  Minutes: Double;
  ResetAt: Double;
Begin
  Result := False;
  ErrorText := '';
  Window.Present := False;
  Window.UsedPercent := 0;
  Window.Minutes := 0;
  Window.ResetsAt := 0;
  Window.HasReset := False;
  If (Node = Nil) Or (Node.JSONType = jtNull) Then
    Begin
      Result := True;
      Exit;
    End;
  Obj := JsonObject(Node);
  If Not Assigned(Obj) Then
    Begin
      ErrorText := 'Codex rate-limit window was not an object.';
      Exit;
    End;
  If Not NumberValue(Obj.Find('usedPercent'), Used) Then
    Begin
      ErrorText := 'Codex rate-limit window had no used percent.';
      Exit;
    End;
  If Not NumberValue(Obj.Find('windowDurationMins'), Minutes) Then
    Begin
      ErrorText := 'Codex rate-limit window had no duration.';
      Exit;
    End;
  If Minutes < 0 Then
    Begin
      ErrorText := 'Codex rate-limit window had no duration.';
      Exit;
    End;
  Window.Present := True;
  Window.UsedPercent := Used;
  Window.Minutes := Round(Minutes);
  If NumberValue(Obj.Find('resetsAt'), ResetAt) And (ResetAt > 0) Then
    Begin
      Window.ResetsAt := Round(ResetAt);
      Window.HasReset := Window.ResetsAt > 0;
    End;
  Result := True;
End;

Function RemainingPercent(Used: Double): Double;
Begin
  Result := 100 - Used;
  If Result < 0 Then
    Result := 0
  Else If Result > 100 Then
    Result := 100;
End;

Function WindowCaption(Const Window: TUsageWindow): String;
Begin
  { Codex Usage remaining shows 100 - usedPercent. 0% used is 100% left. }
  Result := WindowTag(Window.Minutes) + ' ' + PercentText(RemainingPercent(Window.UsedPercent)) + ' left';
End;

Function WindowHint(Const Window: TUsageWindow): String;
Var
  When: String;
Begin
  Result := PercentText(RemainingPercent(Window.UsedPercent)) + ' of the ' + WindowTag(Window.Minutes) + ' window left';
  When := ResetText(Window.ResetsAt);
  If When <> '' Then
    Result := Result + ', resets ' + When;
End;

Function SelectCodexLimits(Root: TJSONObject): TJSONObject;
Var
  Node: TJSONData;
  ById: TJSONObject;
Begin
  Result := Nil;
  If Not Assigned(Root) Then
    Exit;
  Node := Root.Find('result');
  If Node Is TJSONObject Then
    Root := TJSONObject(Node);
  Node := Root.Find('rateLimitsByLimitId');
  If Node Is TJSONObject Then
    Begin
      ById := TJSONObject(Node);
      If ById.Find('codex') Is TJSONObject Then
        Exit(TJSONObject(ById.Find('codex')));
    End;
  If Root.Find('rateLimits') Is TJSONObject Then
    Exit(TJSONObject(Root.Find('rateLimits')));
  If Root.Find('primary') Is TJSONObject Then
    Result := Root;
End;

Function LimitReachedName(Limits: TJSONObject; Out Name: String): Boolean;
Var
  Node: TJSONData;
Begin
  Result := False;
  Name := '';
  If Not Assigned(Limits) Then
    Exit;
  Node := Limits.Find('rateLimitReachedType');
  If (Node = Nil) Or (Node.JSONType = jtNull) Then
    Exit;
  If Node.JSONType = jtString Then
    Begin
      Name := SafeToken(Node.AsString);
      Result := Name <> '';
    End
  Else If Node.JSONType = jtBoolean Then
    Result := Node.AsBoolean;
End;

Function ParseCodexAccountUsage(Const Body, ConnectionId: String; Out Snapshot: TAccountUsageSnapshot;
  Out ErrorText: String): Boolean;
Var
  Data: TJSONData;
  Limits: TJSONObject;
  Primary, Secondary: TUsageWindow;
  Caption, Hint, ReachedName: String;
  Reached: Boolean;
Begin
  Result := False;
  ErrorText := '';
  ClearAccountUsageSnapshot(Snapshot);
  Snapshot.ConnectionId := ConnectionId;
  Data := Nil;
  Try
    Try
      Data := GetJSON(Body);
    Except
      On E: Exception Do
        Begin
          ErrorText := 'Codex rate limits were not JSON.';
          Exit;
        End;
    End;
    Limits := SelectCodexLimits(JsonObject(Data));
    If Not Assigned(Limits) Then
      Begin
        ErrorText := 'Codex rate limits were not in the result.';
        Exit;
      End;
    If Not ReadWindow(Limits.Find('primary'), Primary, ErrorText) Then
      Exit;
    If Not Primary.Present Then
      Begin
        ErrorText := 'Codex rate limits had no primary window.';
        Exit;
      End;
    If Not ReadWindow(Limits.Find('secondary'), Secondary, ErrorText) Then
      Exit;
    Caption := WindowCaption(Primary);
    Hint := WindowHint(Primary);
    If Secondary.Present Then
      Begin
        If Length(Caption + ' · ' + WindowCaption(Secondary)) <= AccountUsageCaptionLimit Then
          Caption := Caption + ' · ' + WindowCaption(Secondary);
        Hint := Hint + '. ' + WindowHint(Secondary);
      End;
    Reached := LimitReachedName(Limits, ReachedName);
    If Reached Then
      Begin
        Caption := 'Limit';
        If ReachedName <> '' Then
          Hint := 'Rate limit reached (' + ReachedName + '). ' + Hint
        Else
          Hint := 'Rate limit reached. ' + Hint;
      End;
    Snapshot.Known := True;
    Snapshot.Caption := Caption;
    Snapshot.Hint := Hint;
    NoteFetched(Snapshot);
    Result := True;
  Finally
    Data.Free;
  End;
End;

Procedure SetAccountUsageCompatibleTransport(GetFn: TCompatibleHttpGet; PostFn: TCompatibleHttpPost);
Begin
  If Assigned(GetFn) And Assigned(PostFn) Then
    Begin
      AccountGet := GetFn;
      AccountPost := PostFn;
    End
  Else
    Begin
      AccountGet := Nil;
      AccountPost := Nil;
    End;
End;

Function QueryCompatibleAccountUsage(Connection: TAssistantConnection; Const RuntimePath, ProfileDir: String;
  Out Snapshot: TAccountUsageSnapshot; Out ErrorText: String): Boolean;
Var
  Client: TAssistantCompatibleClient;
  Body: String;
  StatusCode: Integer;
Begin
  ClearAccountUsageSnapshot(Snapshot);
  ErrorText := '';
  Result := True;
  { RuntimePath and ProfileDir are for the Codex query. }
  If Not Assigned(Connection) Then
    Exit;
  Snapshot.ConnectionId := Connection.Id;
  If Connection.ApiBase <> AssistantOpenRouterApiBase Then
    Exit;
  If Assigned(AccountGet) And Assigned(AccountPost) Then
    Client := TAssistantCompatibleClient.CreateForTransport(AccountGet, AccountPost)
  Else
    Client := TAssistantCompatibleClient.Create;
  Try
    If Not Client.FetchOpenRouterKey(Connection, Body, StatusCode, ErrorText) Then
      Begin
        Result := False;
        Snapshot.Known := False;
        If ErrorText = '' Then
          ErrorText := 'OpenRouter key usage request failed.';
        Exit;
      End;
    If StatusCode <> 200 Then
      Begin
        Result := False;
        Snapshot.Known := False;
        ErrorText := 'OpenRouter key usage was not returned.';
        Exit;
      End;
    Result := ParseOpenRouterAccountUsage(Body, Connection.Id, Snapshot, ErrorText);
  Finally
    Client.Free;
  End;
End;

Const
  GrokBillingUrl = 'https://cli-chat-proxy.grok.com/v1/billing?format=credits';
  GrokLegacyAuthScope = 'https://accounts.x.ai/sign-in';
  { Floor the proxy accepts when no installed Grok Build version can be read. }
  GrokClientVersionFallback = '1.0.50';

Var
  GrokAuthOverride: Boolean;
  GrokAuthBody: String;

Function GrokHomeDir: String;
Begin
  Result := GetEnvironmentVariable('GROK_HOME');
  If Result = '' Then
    Result := IncludeTrailingPathDelimiter(GetUserDir) + '.grok'
  Else
    Result := IncludeTrailingPathDelimiter(Result);
End;

Function LooksLikeVersion(Const Text: String): Boolean;
Var
  I: Integer;
  SawDigit: Boolean;
Begin
  Result := False;
  SawDigit := False;
  If (Text = '') Or (Length(Text) > 32) Then
    Exit;
  For I := 1 To Length(Text) Do
    If Text[I] In ['0'..'9'] Then
      SawDigit := True
    Else If Not (Text[I] In ['.', '-', '+', 'a'..'z', 'A'..'Z']) Then
      Exit;
  Result := SawDigit;
End;

Function ReadWholeFile(Const Path: String): String;
Var
  Lines: TStringList;
Begin
  Result := '';
  If Not FileExists(Path) Then
    Exit;
  Lines := TStringList.Create;
  Try
    Try
      Lines.LoadFromFile(Path);
      Result := Trim(Lines.Text);
    Except
      On E: Exception Do
        Result := '';
    End;
  Finally
    Lines.Free;
  End;
End;

Function GrokClientVersion: String;
Var
  Home, Text: String;
  Data: TJSONData;
  Root: TJSONObject;
Begin
  Home := GrokHomeDir;
  Text := ReadWholeFile(Home + '.metadata_version');
  If Pos(LineEnding, Text) > 0 Then
    Text := Trim(Copy(Text, 1, Pos(LineEnding, Text) - 1));
  If LooksLikeVersion(Text) Then
    Exit(Text);
  Text := '';
  Data := Nil;
  Try
    Try
      If FileExists(Home + 'version.json') Then
        Begin
          Data := GetJSON(ReadWholeFile(Home + 'version.json'));
          Root := JsonObject(Data);
          If Assigned(Root) Then
            Text := Trim(Root.Get('version', ''));
        End;
    Except
      On E: Exception Do
        Text := '';
    End;
  Finally
    Data.Free;
  End;
  If LooksLikeVersion(Text) Then
    Result := Text
  Else
    Result := GrokClientVersionFallback;
End;

Function HeaderSafe(Const Value: String): String;
Var
  I: Integer;
Begin
  Result := Trim(Value);
  If (Result = '') Or (Length(Result) > 128) Or (Pos('@', Result) > 0) Then
    Exit('');
  For I := 1 To Length(Result) Do
    If Result[I] In [#10, #13, ':'] Then
      Exit('');
End;

Function GrokBillingHeaders(Const Token, UserId: String): String;
Var
  Version, SafeUser: String;
Begin
  Version := GrokClientVersion;
  SafeUser := HeaderSafe(UserId);
  Result := 'Authorization: Bearer ' + Token + LineEnding +
    'Accept: application/json' + LineEnding +
    'X-XAI-Token-Auth: xai-grok-cli' + LineEnding +
    'x-grok-client-version: ' + Version + LineEnding +
    'x-grok-client-identifier: grok-shell' + LineEnding +
    'x-grok-client-mode: interactive' + LineEnding +
    'User-Agent: xai-grok-cli/' + Version;
  If SafeUser <> '' Then
    Result := Result + LineEnding + 'x-userid: ' + SafeUser;
End;

Function JsonString(Node: TJSONData): String;
Begin
  Result := '';
  If Assigned(Node) And (Node.JSONType = jtString) Then
    Result := Trim(Node.AsString);
End;

Function PlanLabel(Const Text: String): String;
Var
  I: Integer;
Begin
  Result := Trim(Text);
  If (Result = '') Or (Length(Result) > 40) Or (Pos('@', Result) > 0) Then
    Exit('');
  For I := 1 To Length(Result) Do
    If Not (Result[I] In ['A'..'Z', 'a'..'z', '0'..'9', ' ', '-', '_', '+']) Then
      Exit('');
End;

Function NormalizeIsoTimestamp(Const Text: String): String;
Var
  DotAt, I: Integer;
Begin
  Result := Trim(Text);
  DotAt := Pos('.', Result);
  If DotAt < 11 Then
    Exit;
  I := DotAt + 1;
  While (I <= Length(Result)) And (Result[I] In ['0'..'9']) Do
    Inc(I);
  Delete(Result, DotAt, I - DotAt);
End;

Function IsoToLocal(Const Text: String; Out When: TDateTime): Boolean;
Begin
  Result := False;
  When := 0;
  If Trim(Text) = '' Then
    Exit;
  Try
    When := UniversalTimeToLocal(ISO8601ToDate(NormalizeIsoTimestamp(Text), True));
    Result := When > 0;
  Except
    On E: Exception Do
      Result := False;
  End;
End;

Function WeeklyWindow(Const PeriodType: String; StartAt, EndAt: TDateTime): Boolean;
Begin
  Result := Pos('WEEKLY', UpperCase(PeriodType)) > 0;
  If Result Then
    Exit;
  If (StartAt > 0) And (EndAt > StartAt) And (Abs((EndAt - StartAt) - 7) < 0.5) Then
    Result := True;
End;

Function CredentialFromEntry(Obj: TJSONObject; Out Token, UserId: String): Boolean;
Begin
  Result := False;
  Token := '';
  UserId := '';
  If Not Assigned(Obj) Then
    Exit;
  Token := Trim(Obj.Get('key', ''));
  If Token = '' Then
    Token := Trim(Obj.Get('access_token', ''));
  UserId := HeaderSafe(Obj.Get('user_id', ''));
  If Token = '' Then
    Exit;
  { An API key is not the SuperGrok weekly session. }
  If (Pos('api_key', LowerCase(Obj.Get('auth_mode', ''))) > 0) Or
    ((Copy(Token, 1, 4) = 'xai-') And (UserId = '')) Then
    Exit;
  Result := True;
End;

Function SelectGrokCliCredential(Const AuthBody: String; Out Token, UserId: String): Boolean;
Var
  Data: TJSONData;
  Root, Entry: TJSONObject;
  I: Integer;
  Scope, FallbackToken, FallbackUser, OtherToken, OtherUser: String;
Begin
  Result := False;
  Token := '';
  UserId := '';
  FallbackToken := '';
  FallbackUser := '';
  OtherToken := '';
  OtherUser := '';
  Data := Nil;
  Try
    Try
      Data := GetJSON(AuthBody);
    Except
      On E: Exception Do
        Exit;
    End;
    Root := JsonObject(Data);
    If Not Assigned(Root) Then
      Exit;
    If Root.Find(GrokLegacyAuthScope) Is TJSONObject Then
      If CredentialFromEntry(TJSONObject(Root.Find(GrokLegacyAuthScope)), Token, UserId) Then
        Exit(True);
    For I := 0 To Root.Count - 1 Do
      Begin
        If Not (Root.Items[I] Is TJSONObject) Then
          Continue;
        Entry := TJSONObject(Root.Items[I]);
        If Not CredentialFromEntry(Entry, OtherToken, OtherUser) Then
          Continue;
        Scope := LowerCase(Root.Names[I]);
        If (Pos('auth.x.ai', Scope) > 0) And (OtherUser <> '') Then
          Begin
            Token := OtherToken;
            UserId := OtherUser;
            Exit(True);
          End;
        If (FallbackToken = '') And (OtherUser <> '') Then
          Begin
            FallbackToken := OtherToken;
            FallbackUser := OtherUser;
          End;
      End;
    If FallbackToken <> '' Then
      Begin
        Token := FallbackToken;
        UserId := FallbackUser;
        Result := True;
      End;
  Finally
    Data.Free;
  End;
End;

Procedure SetGrokCliAuthBody(Const Body: String);
Begin
  GrokAuthOverride := True;
  GrokAuthBody := Body;
End;

Procedure ClearGrokCliAuthBody;
Begin
  GrokAuthOverride := False;
  GrokAuthBody := '';
End;

Function GrokAuthPath: String;
Begin
  Result := GetEnvironmentVariable('GROK_AUTH_PATH');
  If Result <> '' Then
    Exit;
  Result := GrokHomeDir + 'auth.json';
End;

Function JwtSubject(Const Token: String): String;
Var
  Dot, Second: Integer;
  Payload, Pad: String;
  Data: TJSONData;
  Root: TJSONObject;
Begin
  Result := '';
  Dot := Pos('.', Token);
  If Dot < 2 Then
    Exit;
  Payload := Copy(Token, Dot + 1, MaxInt);
  Second := Pos('.', Payload);
  If Second > 1 Then
    Payload := Copy(Payload, 1, Second - 1);
  Payload := StringReplace(Payload, '-', '+', [rfReplaceAll]);
  Payload := StringReplace(Payload, '_', '/', [rfReplaceAll]);
  Case Length(Payload) Mod 4 Of
    2: Pad := '==';
    3: Pad := '=';
  Else
    Pad := '';
  End;
  Data := Nil;
  Try
    Try
      Data := GetJSON(DecodeStringBase64(Payload + Pad));
      Root := JsonObject(Data);
      If Assigned(Root) Then
        Result := HeaderSafe(Root.Get('sub', ''));
    Except
      On E: Exception Do
        Result := '';
    End;
  Finally
    Data.Free;
  End;
End;

Function ParseGrokAccountUsage(Const Body, ConnectionId: String; Out Snapshot: TAccountUsageSnapshot;
  Out ErrorText: String): Boolean;
Var
  Data: TJSONData;
  Root, Payload, Period: TJSONObject;
  Percent: Double;
  PeriodType, ResetText, Tier: String;
  StartAt, EndAt: TDateTime;
  HasEnd: Boolean;
Begin
  Result := False;
  ErrorText := '';
  ClearAccountUsageSnapshot(Snapshot);
  Snapshot.ConnectionId := ConnectionId;
  Data := Nil;
  Try
    Try
      Data := GetJSON(Body);
    Except
      On E: Exception Do
        Begin
          ErrorText := 'Grok usage was not JSON.';
          Exit;
        End;
    End;
    Root := JsonObject(Data);
    If Not Assigned(Root) Then
      Begin
        ErrorText := 'Grok usage was not an object.';
        Exit;
      End;
    Payload := JsonObject(Root.Find('config'));
    If Not Assigned(Payload) Then
      Payload := Root;
    Period := JsonObject(Payload.Find('currentPeriod'));
    PeriodType := '';
    StartAt := 0;
    EndAt := 0;
    HasEnd := False;
    If Assigned(Period) Then
      Begin
        PeriodType := JsonString(Period.Find('type'));
        IsoToLocal(JsonString(Period.Find('start')), StartAt);
        HasEnd := IsoToLocal(JsonString(Period.Find('end')), EndAt);
      End;
    If Not HasEnd Then
      HasEnd := IsoToLocal(JsonString(Payload.Find('billingPeriodEnd')), EndAt);
    If Not NumberValue(Payload.Find('creditUsagePercent'), Percent) Then
      Begin
        { A fresh weekly period omits the percent. That is 0% used, not unknown. }
        If Not WeeklyWindow(PeriodType, StartAt, EndAt) Then
          Begin
            ErrorText := 'Grok usage did not include a weekly percent.';
            Exit;
          End;
        Percent := 0;
      End;
    If (Percent < 0) Or (Percent > 100) Then
      Begin
        ErrorText := 'Grok usage percent was out of range.';
        Exit;
      End;
    Snapshot.Known := True;
    { format=credits is the weekly pool Grok Build's usage screen shows. }
    Snapshot.Caption := '7d ' + PercentText(Percent);
    Tier := PlanLabel(JsonString(Payload.Find('subscriptionTier')));
    If Tier = '' Then
      Tier := PlanLabel(JsonString(Root.Find('subscriptionTier')));
    If Tier = '' Then
      Tier := PlanLabel(JsonString(Root.Find('subscription_tier_display')));
    Snapshot.Hint := PercentText(Percent) + ' of the weekly pool used';
    If Tier <> '' Then
      Snapshot.Hint := Tier + '. ' + Snapshot.Hint;
    If HasEnd Then
      Begin
        ResetText := FormatDateTime('yyyy-mm-dd hh:nn', EndAt);
        Snapshot.Hint := Snapshot.Hint + '. Resets ' + ResetText;
      End;
    NoteFetched(Snapshot);
    Result := True;
  Finally
    Data.Free;
  End;
End;

Function FetchGrokBilling(Const Token, UserId: String; Out Body: String; Out StatusCode: Integer;
  Out ErrorText: String): Boolean;
Var
  Headers: String;
Begin
  Body := '';
  StatusCode := 0;
  ErrorText := '';
  Headers := GrokBillingHeaders(Token, UserId);
  If Assigned(AccountGet) Then
    Result := AccountGet(GrokBillingUrl, Headers, Body, StatusCode, ErrorText)
  Else
    Result := HttpsGet(GrokBillingUrl, Body, StatusCode, ErrorText, Headers);
  If Result And (ErrorText = '') And (StatusCode <> 200) Then
    ErrorText := 'Grok usage was not returned.';
  If (Not Result) And (ErrorText = '') Then
    ErrorText := 'Grok usage request failed.';
End;

Function QueryGrokAccountUsage(Connection: TAssistantConnection; Const RuntimePath, ProfileDir: String;
  Out Snapshot: TAccountUsageSnapshot; Out ErrorText: String): Boolean;
Var
  AuthText, Token, UserId, FallbackToken, FallbackUser, Body: String;
  StatusCode: Integer;
  Fetched: Boolean;
Begin
  ClearAccountUsageSnapshot(Snapshot);
  ErrorText := '';
  Result := True;
  { RuntimePath and ProfileDir are for the Codex query. }
  If Not Assigned(Connection) Then
    Exit;
  Snapshot.ConnectionId := Connection.Id;
  If GrokAuthOverride Then
    AuthText := GrokAuthBody
  Else
    AuthText := ReadWholeFile(GrokAuthPath);
  Token := '';
  UserId := '';
  SelectGrokCliCredential(AuthText, Token, UserId);
  FallbackToken := Trim(Connection.KeyValue);
  FallbackUser := JwtSubject(FallbackToken);
  If (Token = '') And (FallbackToken = '') Then
    Exit;
  Body := '';
  StatusCode := 0;
  Fetched := False;
  If Token <> '' Then
    Fetched := FetchGrokBilling(Token, UserId, Body, StatusCode, ErrorText) And (StatusCode = 200);
  If (Not Fetched) And (FallbackToken <> '') And (FallbackToken <> Token) Then
    Begin
      ErrorText := '';
      Fetched := FetchGrokBilling(FallbackToken, FallbackUser, Body, StatusCode, ErrorText) And (StatusCode = 200);
    End;
  If Not Fetched Then
    Begin
      Result := False;
      If StatusCode <> 0 Then
        ErrorText := 'Grok usage was not returned (HTTP ' + IntToStr(StatusCode) + ').'
      Else If ErrorText = '' Then
        ErrorText := 'Grok usage was not returned.';
      WorkflowLogger.Warning('AccountUsage', ErrorText);
      Exit;
    End;
  Result := ParseGrokAccountUsage(Body, Connection.Id, Snapshot, ErrorText);
End;

Initialization

InitCriticalSection(RegistryLock);
RegistryReady := True;
{ claude and a custom base stay quiet. A later official call is a new query here. }
RegisterAccountUsageQuery('openai-compatible', @QueryCompatibleAccountUsage);
RegisterAccountUsageQuery('codex', @QueryCodexAccountUsage);
RegisterAccountUsageQuery('grok', @QueryGrokAccountUsage);

Finalization

RegistryReady := False;
DoneCriticalSection(RegistryLock);

End.
