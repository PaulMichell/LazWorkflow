Program AssistantAccountUsageTest;

{ Fixture checks for account allowance captions. No socket, no codex binary, and no key.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, SysUtils, DateUtils, AssistantConnections, AssistantAccountUsage;

Var
  FailCount: Integer;
  TransportCalls: Integer;
  SignedConnection: TAssistantConnection;
  SignedSnapshot: TAccountUsageSnapshot;
  SignedError: String;

Procedure Check(Const Title: String; Condition: Boolean);
Begin
  If Condition Then
    WriteLn('ok   ', Title)
  Else
    Begin
      WriteLn('FAIL ', Title);
      Inc(FailCount);
    End;
End;

Procedure CheckText(Const Title, Actual, Expected: String);
Begin
  Check(Title, Actual = Expected);
  If Actual <> Expected Then
    Begin
      WriteLn('  actual: [', Actual, ']');
      WriteLn('  expected: [', Expected, ']');
    End;
End;

{$PUSH}{$HINTS OFF}
Function CountingGet(Const Url, ExtraHeaders: String; Out ResponseBody: String; Out StatusCode: Integer;
  Out ErrorText: String): Boolean;
Begin
  Inc(TransportCalls);
  ResponseBody := '';
  StatusCode := 500;
  ErrorText := 'Account usage fixture must not call transport.';
  Result := False;
End;

Function CountingPost(Const Url, JsonBody, ExtraHeaders: String; Out ResponseBody: String; Out StatusCode: Integer;
  Out ErrorText: String): Boolean;
Begin
  Inc(TransportCalls);
  ResponseBody := '';
  StatusCode := 500;
  ErrorText := 'Account usage fixture must not call transport.';
  Result := False;
End;

Function GrokFixtureGet(Const Url, ExtraHeaders: String; Out ResponseBody: String; Out StatusCode: Integer;
  Out ErrorText: String): Boolean;
Begin
  Inc(TransportCalls);
  ErrorText := '';
  If Pos('billing?format=credits', Url) = 0 Then
    Begin
      ResponseBody := '';
      StatusCode := 404;
      Result := False;
      Exit;
    End;
  { ExtraHeaders carries the bearer token. Do not write it. }
  If ExtraHeaders = '' Then
    Begin
      ResponseBody := '';
      StatusCode := 401;
      Result := False;
      Exit;
    End;
  ResponseBody := '{"config":{"creditUsagePercent":25,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY",' +
    '"end":"2026-10-11T20:55:00Z"}}}';
  StatusCode := 200;
  Result := True;
End;
{$POP}

Procedure TestOpenRouterBodies;
Var
  Snapshot: TAccountUsageSnapshot;
  ErrorText: String;
Begin
  Check('openrouter balance is known', ParseOpenRouterAccountUsage(
    '{"data":{"limit_remaining":18.2,"usage_daily":1.25}}', 'or-1', Snapshot, ErrorText) And Snapshot.Known And
    (ErrorText = '') And (Snapshot.ConnectionId = 'or-1'));
  CheckText('openrouter balance caption is Left', Snapshot.Caption, 'Left $18.20');

  Check('free request counter is shown', ParseOpenRouterAccountUsage(
    '{"data":{"limit_remaining":null,"free_model_daily_requests":{"remaining":12}}}', 'or-free', Snapshot, ErrorText) And
    Snapshot.Known And (Snapshot.Caption = 'Free 12 left') And (ErrorText = ''));

  Check('null limit without a counter is unknown', ParseOpenRouterAccountUsage('{"data":{"limit_remaining":null}}',
    'or-open', Snapshot, ErrorText) And (Not Snapshot.Known) And (Snapshot.Caption = '') And (ErrorText = ''));
  Check('null limit does not need a transport call', TransportCalls = 0);
End;

Procedure TestQuietConnections;
Var
  Connection: TAssistantConnection;
  Snapshot: TAccountUsageSnapshot;
  ErrorText: String;
Begin
  Connection := TAssistantConnection.Create;
  Try
    Connection.Preset := 'custom';
    Connection.Backend := 'openai-compatible';
    Connection.ApiBase := 'https://example.invalid/v1';
    Connection.Id := 'custom-1';
    Connection.KeySource := 'stored';
    Connection.KeyValue := '';
    Check('custom base is registered but unknown', AccountUsageRegistered('openai-compatible') And
      QueryAccountUsage(Connection, '', '', Snapshot, ErrorText) And (Not Snapshot.Known) And (ErrorText = '') And
      (Snapshot.Caption = ''));
    Check('custom connection leaves the usage label hidden', AccountUsageCaption(Snapshot, Connection.Id) = '');
    Check('custom base does not call transport', TransportCalls = 0);

    Connection.Backend := 'grok';
    Connection.Preset := 'grok';
    Connection.ApiBase := '';
    Connection.Id := 'grok-1';
    Connection.KeyValue := '';
    SetGrokCliAuthBody('');
    Check('unsigned grok is registered but unknown', AccountUsageRegistered('grok') And
      QueryAccountUsage(Connection, '', '', Snapshot, ErrorText) And (Not Snapshot.Known) And (ErrorText = '') And
      (Snapshot.Caption = ''));
    Check('unsigned grok leaves the usage label hidden', AccountUsageCaption(Snapshot, Connection.Id) = '');
    Check('unsigned grok does not call transport', TransportCalls = 0);
  Finally
    Connection.Free;
  End;
End;

Procedure TestCodexResult;
Const
  PrimaryReset = 1730937600;
  SecondaryReset = 1731542400;
Var
  Snapshot: TAccountUsageSnapshot;
  ErrorText, Body, PrimaryWhen, SecondaryWhen: String;
Begin
  PrimaryWhen := FormatDateTime('yyyy-mm-dd hh:nn', UnixToDateTime(PrimaryReset));
  SecondaryWhen := FormatDateTime('yyyy-mm-dd hh:nn', UnixToDateTime(SecondaryReset));
  Check('reset times are distinct', (PrimaryWhen <> '') And (PrimaryWhen <> SecondaryWhen));
  Body := Format('{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":%d},' +
    '"secondary":{"usedPercent":7,"windowDurationMins":10080,"resetsAt":%d}}}', [PrimaryReset, SecondaryReset]);
  Check('codex result parses', ParseCodexAccountUsage(Body, 'codex-1', Snapshot, ErrorText) And Snapshot.Known And
    (ErrorText = '') And (Pos('left', Snapshot.Hint) > 0));
  CheckText('codex result is remaining, matching Usage remaining', Snapshot.Caption, '5h 75% left · 7d 93% left');
  Check('codex hint contains both reset times', (Pos(PrimaryWhen, Snapshot.Hint) > 0) And
    (Pos(SecondaryWhen, Snapshot.Hint) > 0));
  If (Pos(PrimaryWhen, Snapshot.Hint) = 0) Or (Pos(SecondaryWhen, Snapshot.Hint) = 0) Then
    WriteLn('  hint: [', Snapshot.Hint, ']');

  Body := Format('{"rateLimits":{"rateLimitReachedType":"primary","primary":{"usedPercent":100,' +
    '"windowDurationMins":300,"resetsAt":%d}}}', [PrimaryReset]);
  Check('reached rate limit parses', ParseCodexAccountUsage(Body, 'codex-1', Snapshot, ErrorText) And Snapshot.Known And
    (ErrorText = ''));
  CheckText('reached rate limit captions Limit', Snapshot.Caption, 'Limit');

  Body := '{"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":300,"resetsAt":1},' +
    '"secondary":{"usedPercent":0,"windowDurationMins":10080,"resetsAt":2}}}';
  Check('unused codex windows parse', ParseCodexAccountUsage(Body, 'codex-1', Snapshot, ErrorText) And Snapshot.Known);
  CheckText('unused codex windows are 100% left', Snapshot.Caption, '5h 100% left · 7d 100% left');
End;

Procedure TestGrokBilling;
Var
  Snapshot: TAccountUsageSnapshot;
  ErrorText, When: String;
Begin
  When := FormatDateTime('mmmm d, hh:nn', UniversalTimeToLocal(ISO8601ToDate('2026-10-11T20:55:00Z', True)));
  Check('grok weekly pool parses', ParseGrokAccountUsage(
    '{"config":{"creditUsagePercent":25,"subscriptionTier":"SuperGrok Heavy","currentPeriod":{' +
    '"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-10-11T20:55:00.959221+00:00"},' +
    '"productUsage":[{"product":"GrokBuild","usagePercent":20},{"product":"GrokChat","usagePercent":5}]}}',
    'grok-1', Snapshot, ErrorText) And Snapshot.Known And (ErrorText = ''));
  CheckText('grok weekly pool captions used percent', Snapshot.Caption, 'Credits used: 25%');
  Check('grok hint matches the Build usage summary', (Pos('Weekly limit: 25%', Snapshot.Hint) > 0) And
    (Pos('Next reset: ' + When, Snapshot.Hint) > 0) And (Pos('Grok Build: 20%', Snapshot.Hint) > 0) And
    (Pos('Plan: SuperGrok Heavy', Snapshot.Hint) > 0));
  If (Pos(When, Snapshot.Hint) = 0) Then
    WriteLn('  hint: [', Snapshot.Hint, ']');
  CheckText('settings can read the plan summary', AccountUsagePlanText('grok-1'), Snapshot.Hint);
  ClearAccountUsageSnapshot(Snapshot);
  Snapshot := AccountUsageForFooter('grok-1', Snapshot);
  Check('footer uses the published plan when the slot is empty', Snapshot.Caption = 'Credits used: 25%');

  Check('omitted grok percent on a fresh week is zero used', ParseGrokAccountUsage(
    '{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-10-11T20:55:00Z"}}}', 'grok-1', Snapshot,
    ErrorText) And Snapshot.Known And (Snapshot.Caption = 'Credits used: 0%'));
  Check('Build session is preferred over an API key', SelectGrokCliCredential(
    '{"xai::api_key":{"key":"xai-secret","user_id":""},' +
    '"https://accounts.x.ai/sign-in":{"key":"session-token","user_id":"user-1","email":"hidden@example.com"}}',
    ErrorText, When) And (ErrorText = 'session-token') And (When = 'user-1'));
  Check('official Build slot does not need a user id', SelectGrokCliCredential(
    '{"https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828":{"key":"session-jwt","auth_mode":"oauth"}}',
    ErrorText, When) And (ErrorText = 'session-jwt'));
End;

Procedure TestFooterChoice;
Var
  Snapshot: TAccountUsageSnapshot;
  ErrorText, Applied: String;
Begin
  Check('footer fixture has a known caption', ParseOpenRouterAccountUsage('{"data":{"limit_remaining":18.2}}', 'or-1',
    Snapshot, ErrorText) And Snapshot.Known And (Snapshot.Caption <> ''));
  Applied := AccountUsageCaption(Snapshot, 'other-connection');
  Check('other connection is not the footer text', (Applied = '') And (Applied <> Snapshot.Caption));
  Check('other connection does not keep the hint', AccountUsageHint(Snapshot, 'other-connection') = '');
  Check('matching connection is the footer text', AccountUsageCaption(Snapshot, Snapshot.ConnectionId) = Snapshot.Caption);
End;

Begin
  FailCount := 0;
  TransportCalls := 0;
  SetAccountUsageCompatibleTransport(@CountingGet, @CountingPost);
  Try
    TestOpenRouterBodies;
    TestQuietConnections;
    TestCodexResult;
    TestGrokBilling;
    TestFooterChoice;
    Check('fixture never called transport', TransportCalls = 0);
  Finally
    SetAccountUsageCompatibleTransport(Nil, Nil);
  End;
  TransportCalls := 0;
  SetAccountUsageCompatibleTransport(@GrokFixtureGet, @CountingPost);
  Try
    SetGrokCliAuthBody('');
    SignedConnection := TAssistantConnection.Create;
    Try
      SignedConnection.Backend := 'grok';
      SignedConnection.Id := 'grok-signed';
      SignedConnection.KeyValue := 'fixture-token-not-a-real-key';
      Check('signed-in grok uses the injected billing call', QueryAccountUsage(SignedConnection, '', '', SignedSnapshot,
        SignedError) And SignedSnapshot.Known And (SignedSnapshot.Caption = 'Credits used: 25%') And (TransportCalls = 1) And
        (SignedError = ''));
      Check('signed-in grok shows the usage label', AccountUsageCaption(SignedSnapshot, SignedConnection.Id) =
        'Credits used: 25%');
    Finally
      SignedConnection.Free;
    End;
  Finally
    ClearGrokCliAuthBody;
    SetAccountUsageCompatibleTransport(Nil, Nil);
  End;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantAccountUsage tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantAccountUsage test(s) failed.');
      Halt(1);
    End;
End.
