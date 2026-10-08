Program AssistantUsageTest;

{ Fixture checks for usage.jsonl. No socket and no prompt body is written.
  (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, FileUtil, LazFileUtils, AssistantSampler, AssistantCompatibleClient, AssistantClaudeClient,
  AssistantConnections, AssistantAccountUsage, AssistantCodexUsage, AssistantUsage;

Const
  PromptText = 'please summarise the secret prompt body ALPHA-PROMPT';
  GrokFixture =
    'data: {"type":"response.completed","response":{"id":"resp_test","status":"completed","output":[' +
    '{"type":"message","id":"msg_test","role":"assistant","content":[{"type":"output_text","text":"The answer."}]}],' +
    '"usage":{"input_tokens":10,"output_tokens":8,"output_tokens_details":{"reasoning_tokens":5}}}}' + LineEnding +
    LineEnding +
    'data: [DONE]' + LineEnding;
  OpenRouterBody = '{"choices":[{"message":{"role":"assistant","content":"fixture answer"}}],' +
    '"usage":{"prompt_tokens":12,"completion_tokens":4,"cost":0.5}}';
  ClaudeNoUsage = '{"result":"plain answer"}';

Var
  FailCount: Integer;

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

Function MakeTempRoot: String;
Begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'lazworkflow-usage-' + FormatDateTime('hhnnsszzz', Now);
  ForceDirectoriesUTF8(Result);
End;

Function FileText(Const Path: String): String;
Var
  Lines: TStringList;
Begin
  Result := '';
  If Not FileExistsUTF8(Path) Then
    Exit;
  Lines := TStringList.Create;
  Try
    Lines.LoadFromFile(Path);
    Result := Lines.Text;
  Finally
    Lines.Free;
  End;
End;

Procedure TestFixtures;
Var
  Root, Path, Body, ErrorText: String;
  Parser: TAssistantSseParser;
  Completion: TCompatibleCompletion;
  Turn: TClaudeTurnResult;
  Item: TAssistantUsageRecord;
  Lines: TStringList;
Begin
  Root := MakeTempRoot;
  Parser := TAssistantSseParser.Create;
  Lines := TStringList.Create;
  Try
    Parser.Feed(GrokFixture);
    Check('grok fixture reported usage', Parser.UsageReported And (Parser.InputTokens = 10) And (Parser.OutputTokens = 8));
    Item := ReportedUsageRecord('grok-1', 'grok', 'grok-4', Parser.InputTokens, Parser.OutputTokens,
      Parser.HasReasoning, Parser.ReasoningTokens, False, 0, '');
    Check('grok usage line appended', AppendUsageRecord(Root, Item, ErrorText));
    Path := UsageFilePath(Root);
    Body := FileText(Path);
    Lines.Text := Body;
    Check('grok appends one reported line', (Lines.Count = 1) And (Pos('"state":"reported"', Lines[0]) > 0));
    Check('grok line has no cost', Pos('"cost"', Lines[0]) = 0);

    Check('openrouter fixture parses', ParseCompatibleCompletion(OpenRouterBody, Completion, ErrorText) And Completion.HasCost);
    Item := ReportedUsageRecord('or-1', 'openai-compatible', 'openai/gpt-4.1', Completion.PromptTokens,
      Completion.CompletionTokens, False, 0, Completion.HasCost, Completion.Cost, '');
    Check('openrouter usage line appended', AppendUsageRecord(Root, Item, ErrorText));
    Body := FileText(Path);
    Lines.Text := Body;
    Check('openrouter appends the cost', (Lines.Count = 2) And (Pos('"cost"', Lines[1]) > 0) And (Pos('0.5', Lines[1]) > 0));

    Check('claude fixture parses', ParseClaudeTurnResult(ClaudeNoUsage, Turn, ErrorText));
    Check('claude fixture is unavailable', Turn.UsageState = ClaudeUsageUnavailable);
    Item := UnavailableUsageRecord('claude-1', 'claude', 'claude-sonnet');
    Check('claude usage line appended', AppendUsageRecord(Root, Item, ErrorText));
    Body := FileText(Path);
    Lines.Text := Body;
    Check('claude appends unavailable', (Lines.Count = 3) And (Pos('"state":"unavailable"', Lines[2]) > 0));
    Check('usage file has none of the prompt text', Pos(PromptText, Body) = 0);
    Check('usage file has none of the answer text', (Pos('The answer.', Body) = 0) And
      (Pos('fixture answer', Body) = 0) And (Pos('plain answer', Body) = 0));
    Check('turn log has no account quota', (Pos('limit_remaining', Body) = 0) And (Pos('rateLimits', Body) = 0));
  Finally
    Lines.Free;
    Parser.Free;
    DeleteDirectory(ExcludeTrailingPathDelimiter(Root), False);
  End;
End;

Procedure TestQuotaLeavesTurnLog;
Var
  Root, ErrorText: String;
  Snapshot: TAccountUsageSnapshot;
  Item: TAssistantUsageRecord;
  Connection: TAssistantConnection;
  Found: Boolean;
Begin
  Item := UnavailableUsageRecord('turn-1', 'grok', 'grok-4');
  Check('missing turn still says usage was not reported', UsageDetailText(False, Item) = UsageUnavailableText);
  Check('unavailable turn still says usage was not reported', UsageDetailText(True, Item) = UsageUnavailableText);
  Check('usage sentence is unchanged', UsageUnavailableText = 'This connection did not report usage.');
  Root := MakeTempRoot;
  Connection := TAssistantConnection.Create;
  Try
    Connection.Id := 'acct-1';
    Connection.Backend := 'grok';
    Check('unregistered quota query is unknown', QueryAccountUsage(Connection, '', '', Snapshot, ErrorText) And
      (Not Snapshot.Known) And (ErrorText = ''));
    Check('openrouter balance parses without a usage line',
      ParseOpenRouterAccountUsage('{"data":{"limit_remaining":18.2,"usage_daily":1.25}}', 'acct-1', Snapshot, ErrorText) And
      Snapshot.Known);
    Check('codex limits parse without a usage line',
      ParseCodexAccountUsage('{"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,' +
      '"resetsAt":1730947200}}}}', 'acct-1', Snapshot, ErrorText) And Snapshot.Known);
    Check('quota parse does not append a usage line', Not FileExistsUTF8(UsageFilePath(Root)));
    Found := LatestUsageRecord(Root, 'acct-1', Item);
    Check('missing quota does not change the usage sentence', (Not Found) And
      (UsageDetailText(Found, Item) = UsageUnavailableText));
  Finally
    Connection.Free;
    DeleteDirectory(ExcludeTrailingPathDelimiter(Root), False);
  End;
End;

Var
  CodexReadCalls, QuietGetCalls: Integer;
  CodexReadSignedIn, CodexReadOk: Boolean;
  CodexReadBody, CodexReadError: String;

Function QuietGet(Const Url, ExtraHeaders: String; Out ResponseBody: String; Out StatusCode: Integer;
  Out ErrorText: String): Boolean;
Begin
  Inc(QuietGetCalls);
  ResponseBody := '';
  StatusCode := 500;
  ErrorText := '';
  Result := True;
End;

Function QuietPost(Const Url, JsonBody, ExtraHeaders: String; Out ResponseBody: String; Out StatusCode: Integer;
  Out ErrorText: String): Boolean;
Begin
  Inc(QuietGetCalls);
  ResponseBody := '';
  StatusCode := 500;
  ErrorText := '';
  Result := True;
End;

Function FixtureCodexRead(Const Executable, ProfileDir: String; Out Body: String; Out SignedIn: Boolean;
  Out ErrorText: String): Boolean;
Begin
  Inc(CodexReadCalls);
  Body := CodexReadBody;
  SignedIn := CodexReadSignedIn;
  ErrorText := CodexReadError;
  Result := CodexReadOk;
  If (Executable = '') Or (ProfileDir = '') Then
    Result := False;
End;

Procedure TestCodexUsageIdle;
Var
  Connection: TAssistantConnection;
  Snapshot: TAccountUsageSnapshot;
  ErrorText: String;
Begin
  Connection := TAssistantConnection.Create;
  Try
    Connection.Id := 'codex-1';
    Connection.Backend := 'codex';
    CodexReadCalls := 0;
    CodexReadOk := True;
    CodexReadSignedIn := False;
    CodexReadBody := '';
    CodexReadError := '';
    SetCodexAccountUsageRead(@FixtureCodexRead);
    SetCodexAccountUsageIdle(False);
    Check('busy codex query is unknown', QueryAccountUsage(Connection, '/usr/bin/codex', '/tmp/profile', Snapshot,
      ErrorText) And (Not Snapshot.Known) And (ErrorText = ''));
    Check('busy codex query does not start a read', CodexReadCalls = 0);
    SetCodexAccountUsageIdle(True);
    Check('missing codex paths do not start a read', QueryAccountUsage(Connection, '', '', Snapshot, ErrorText) And
      (Not Snapshot.Known) And (CodexReadCalls = 0));
    CancelCodexAccountUsage;
    Check('cancelled codex query does not start a read', QueryAccountUsage(Connection, '/usr/bin/codex', '/tmp/profile',
      Snapshot, ErrorText) And (Not Snapshot.Known) And (CodexReadCalls = 0));
    SetCodexAccountUsageIdle(True);
    Check('unsigned codex query is unknown', QueryAccountUsage(Connection, '/usr/bin/codex', '/tmp/profile', Snapshot,
      ErrorText) And (Not Snapshot.Known) And (ErrorText = '') And (Snapshot.Caption = ''));
    Check('unsigned codex query asked the reader', CodexReadCalls = 1);
    CodexReadSignedIn := True;
    CodexReadBody := '{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1730947200},' +
      '"secondary":{"usedPercent":7,"windowDurationMins":10080,"resetsAt":1731552000}},' +
      '"account":{"email":"secret@example.com"}}';
    Check('codex rate limits become a used caption', QueryAccountUsage(Connection, '/usr/bin/codex', '/tmp/profile',
      Snapshot, ErrorText) And Snapshot.Known And (Snapshot.Caption = '5h 25% · 7d 7%'));
    Check('codex hint says the numbers are used', (Pos('used', Snapshot.Hint) > 0) And (Pos('resets', Snapshot.Hint) > 0));
    Check('codex snapshot does not show the account email', (Pos('secret@example.com', Snapshot.Caption) = 0) And
      (Pos('secret@example.com', Snapshot.Hint) = 0));
    CodexReadBody := '{"rateLimits":{"rateLimitReachedType":"primary","primary":{"usedPercent":100,' +
      '"windowDurationMins":300,"resetsAt":1730947200}}}';
    Check('reached codex limit captions Limit', QueryAccountUsage(Connection, '/usr/bin/codex', '/tmp/profile', Snapshot,
      ErrorText) And Snapshot.Known And (Snapshot.Caption = 'Limit') And (Pos('primary', Snapshot.Hint) > 0));
    CodexReadOk := False;
    CodexReadSignedIn := True;
    CodexReadError := 'Codex rate-limit connection failed.';
    Check('codex read failure is not a zero figure', (Not QueryAccountUsage(Connection, '/usr/bin/codex', '/tmp/profile',
      Snapshot, ErrorText)) And (Not Snapshot.Known) And (Snapshot.Caption = '') And
      (Pos('secret@example.com', ErrorText) = 0));
  Finally
    SetCodexAccountUsageIdle(False);
    SetCodexAccountUsageRead(Nil);
    Connection.Free;
  End;
End;

Procedure TestQuietBackends;
Var
  Connection: TAssistantConnection;
  Snapshot: TAccountUsageSnapshot;
  ErrorText: String;

  Procedure ExpectQuiet(Const Backend, ApiBase: String);
  Begin
    Connection.Backend := Backend;
    Connection.ApiBase := ApiBase;
    Connection.Id := Backend + '-quiet';
    Check(Backend + ' account usage is unknown', QueryAccountUsage(Connection, '/usr/bin/claude', '/tmp/claude-profile',
      Snapshot, ErrorText) And (Not Snapshot.Known) And (ErrorText = '') And (Snapshot.Caption = ''));
    Check(Backend + ' query does not expose the key', Pos('should-not-be-sent', ErrorText) = 0);
  End;

Begin
  Connection := TAssistantConnection.Create;
  Try
    Connection.KeySource := 'stored';
    Connection.KeyValue := 'should-not-be-sent';
    Connection.Preset := 'custom';
    Connection.WireApi := AssistantWireChatCompletions;
    QuietGetCalls := 0;
    CodexReadCalls := 0;
    SetAccountUsageCompatibleTransport(@QuietGet, @QuietPost);
    SetCodexAccountUsageRead(@FixtureCodexRead);
    SetCodexAccountUsageIdle(True);
    ExpectQuiet('grok', AssistantOpenRouterApiBase);
    ExpectQuiet('claude', AssistantOpenRouterApiBase);
    ExpectQuiet('openai-compatible', 'https://example.invalid/v1');
    Check('quiet backends do not call a usage transport', (QuietGetCalls = 0) And (CodexReadCalls = 0));
    Check('quiet backends leave the turn usage sentence', UsageUnavailableText = 'This connection did not report usage.');
  Finally
    SetCodexAccountUsageIdle(False);
    SetCodexAccountUsageRead(Nil);
    SetAccountUsageCompatibleTransport(Nil, Nil);
    Connection.Free;
  End;
End;

Begin
  FailCount := 0;
  TestFixtures;
  TestQuotaLeavesTurnLog;
  TestCodexUsageIdle;
  TestQuietBackends;
  If FailCount = 0 Then
    Begin
      WriteLn('All AssistantUsage tests passed.');
      Halt(0);
    End
  Else
    Begin
      WriteLn(FailCount, ' AssistantUsage test(s) failed.');
      Halt(1);
    End;
End.
