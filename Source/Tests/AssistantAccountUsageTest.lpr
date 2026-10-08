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
    Connection.ApiBase := AssistantOpenRouterApiBase;
    Connection.Id := 'grok-1';
    Check('grok query is unknown', (Not AccountUsageRegistered('grok')) And
      QueryAccountUsage(Connection, '', '', Snapshot, ErrorText) And (Not Snapshot.Known) And (ErrorText = '') And
      (Snapshot.Caption = ''));
    Check('grok connection leaves the usage label hidden', AccountUsageCaption(Snapshot, Connection.Id) = '');
    Check('grok query does not call transport', TransportCalls = 0);
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
    (ErrorText = '') And (Pos('used', Snapshot.Hint) > 0));
  CheckText('codex result is a used caption', Snapshot.Caption, '5h 25% · 7d 7%');
  Check('codex hint contains both reset times', (Pos(PrimaryWhen, Snapshot.Hint) > 0) And
    (Pos(SecondaryWhen, Snapshot.Hint) > 0));
  If (Pos(PrimaryWhen, Snapshot.Hint) = 0) Or (Pos(SecondaryWhen, Snapshot.Hint) = 0) Then
    WriteLn('  hint: [', Snapshot.Hint, ']');

  Body := Format('{"rateLimits":{"rateLimitReachedType":"primary","primary":{"usedPercent":100,' +
    '"windowDurationMins":300,"resetsAt":%d}}}', [PrimaryReset]);
  Check('reached rate limit parses', ParseCodexAccountUsage(Body, 'codex-1', Snapshot, ErrorText) And Snapshot.Known And
    (ErrorText = ''));
  CheckText('reached rate limit captions Limit', Snapshot.Caption, 'Limit');
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
    TestFooterChoice;
    Check('fixture never called transport', TransportCalls = 0);
  Finally
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
