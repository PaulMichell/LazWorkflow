Program AssistantClaudeClientTest;

{ Fixture coverage for the Claude Code wrapper. Does not start claude and does
  not read account files. (c) 2026 Michell Computing. }

{$IFDEF FPC}
  {$MODE OBJFPC}
  {$LONGSTRINGS ON}
{$ENDIF}

Uses
  {$IFDEF UNIX}
  cthreads, BaseUnix,
  {$ENDIF}
  Classes, SysUtils, AssistantClaudeClient, AssistantClaudeStream;

Const
  UsageFixture = '{"result":"fixture answer","usage":{"input_tokens":9,"output_tokens":3,"cost":1.25}}';
  NoUsageFixture = '{"result":"plain answer"}';
  { Claude Code 2.1.312 stderr for an unknown mode. }
  RefusedModeFixture = 'error: option ''--permission-mode <mode>'' argument ''ask'' is invalid. ' +
    'Allowed choices are acceptEdits, auto, bypassPermissions, manual, dontAsk, plan.';

Procedure Check(Const Name: String; OK: Boolean);
Begin
  If Not OK Then
    Begin
      WriteLn('FAIL ', Name);
      Halt(1);
    End;
  WriteLn('ok   ', Name);
End;

Function UnitSource: String;
Var
  Candidates: Array[0..3] Of String;
  Lines: TStringList;
  I: Integer;
Begin
  Result := '';
  Candidates[0] := ExpandFileName('Source/LazAssistantTools/AssistantClaudeClient.pas');
  Candidates[1] := ExpandFileName('../Source/LazAssistantTools/AssistantClaudeClient.pas');
  Candidates[2] := ExpandFileName('../../Source/LazAssistantTools/AssistantClaudeClient.pas');
  Candidates[3] := ExpandFileName(ExtractFilePath(ParamStr(0)) + '../Source/LazAssistantTools/AssistantClaudeClient.pas');
  Lines := TStringList.Create;
  Try
    For I := 0 To High(Candidates) Do
      If FileExists(Candidates[I]) Then
        Begin
          Lines.LoadFromFile(Candidates[I]);
          Result := Lines.Text;
          Exit;
        End;
  Finally
    Lines.Free;
  End;
End;

{ Captured from Claude Code 2.1.312 and redacted. See Tests/Fixtures/Claude/README.md. }
Function FixtureText(Const Name: String): String;
Var
  Candidates: Array[0..2] Of String;
  Lines: TStringList;
  I: Integer;
Begin
  Result := '';
  Candidates[0] := ExpandFileName('Tests/Fixtures/Claude/' + Name);
  Candidates[1] := ExpandFileName('../Tests/Fixtures/Claude/' + Name);
  Candidates[2] := ExpandFileName(ExtractFilePath(ParamStr(0)) + '../Tests/Fixtures/Claude/' + Name);
  Lines := TStringList.Create;
  Try
    For I := 0 To High(Candidates) Do
      If FileExists(Candidates[I]) Then
        Begin
          Lines.LoadFromFile(Candidates[I]);
          Result := Lines.Text;
          Exit;
        End;
  Finally
    Lines.Free;
  End;
  WriteLn('FAIL fixture not found: ', Name);
  Halt(1);
End;

{$IFDEF UNIX}
Const
  { Stands in for claude. Answers auth status as a subscription; --model picks the behaviour. }
  FakeClaudeScript =
    '#!/bin/sh' + LineEnding +
    'if [ "$1" = "auth" ]; then' + LineEnding +
    '  printf ''%s\n'' ''{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","subscriptionType":"pro"}''' +
    LineEnding +
    '  exit 0' + LineEnding +
    'fi' + LineEnding +
    'model=""' + LineEnding +
    'while [ $# -gt 0 ]; do' + LineEnding +
    '  if [ "$1" = "--model" ]; then model="$2"; fi' + LineEnding +
    '  shift' + LineEnding +
    'done' + LineEnding +
    'case "$model" in' + LineEnding +
    '  refuse)' + LineEnding +
    '    echo "error: option ''--permission-mode <mode>'' argument ''ask'' is invalid." >&2' + LineEnding +
    '    exit 1 ;;' + LineEnding +
    '  hang)' + LineEnding +
    '    sleep 600 &' + LineEnding +
    '    echo $! > child.pid' + LineEnding +
    '    wait ;;' + LineEnding +
    '  *)' + LineEnding +
    '    cat > /dev/null' + LineEnding +
    '    printf ''%s\n'' ''{"type":"system","subtype":"init","apiKeySource":"none","session_id":"s1"}''' + LineEnding +
    '    printf ''%s\n'' ''{"type":"assistant","message":{"content":[{"type":"text","text":"fake answer"}]}}''' + LineEnding +
    '    printf ''%s\n'' ''{"type":"result","subtype":"success","is_error":false,"result":"fake answer"}'' ;;' +
    LineEnding +
    'esac' + LineEnding;

Function WriteFakeClaude(Const Directory: String): String;
Var
  Lines: TStringList;
Begin
  Result := IncludeTrailingPathDelimiter(Directory) + 'claude';
  Lines := TStringList.Create;
  Try
    Lines.Text := FakeClaudeScript;
    Lines.SaveToFile(Result);
  Finally
    Lines.Free;
  End;
  FpChmod(Result, &755);
End;

Function WaitForRun(Run: TAssistantClaudeRun; TimeoutMs: Integer): TClaudeRunSnapshot;
Var
  Started: QWord;
Begin
  Started := GetTickCount64;
  Result := Run.Snapshot;
  While (Not Result.Done) And (GetTickCount64 - Started < QWord(TimeoutMs)) Do
    Begin
      Sleep(20);
      Result := Run.Snapshot;
    End;
End;

Function ReadChildPid(Const Directory: String; TimeoutMs: Integer): Integer;
Var
  Started: QWord;
  Lines: TStringList;
  PidFile: String;
Begin
  Result := 0;
  PidFile := IncludeTrailingPathDelimiter(Directory) + 'child.pid';
  Started := GetTickCount64;
  While (Not FileExists(PidFile)) And (GetTickCount64 - Started < QWord(TimeoutMs)) Do
    Sleep(20);
  If Not FileExists(PidFile) Then
    Exit;
  Sleep(50);
  Lines := TStringList.Create;
  Try
    Lines.LoadFromFile(PidFile);
    If Lines.Count > 0 Then
      Result := StrToIntDef(Trim(Lines[0]), 0);
  Finally
    Lines.Free;
  End;
End;
{$ENDIF}

{ Folds every line of a stream-json fixture. }
Function FoldFixture(Const Name: String): TClaudeStreamState;
Var
  Lines: TStringList;
  I: Integer;
Begin
  ClearClaudeStream(Result);
  Lines := TStringList.Create;
  Try
    Lines.Text := FixtureText(Name);
    For I := 0 To Lines.Count - 1 Do
      If Trim(Lines[I]) <> '' Then
        ApplyClaudeStreamLine(Lines[I], Result);
  Finally
    Lines.Free;
  End;
End;

Function SourceContains(Const Source, Needle: String): Boolean;
Begin
  Result := Pos(LowerCase(Needle), LowerCase(Source)) > 0;
End;

Var
  Source, ErrorText, Script: String;
  Turn: TClaudeTurnResult;
  Account: TClaudeAccount;
  Stream: TClaudeStreamState;
  TurnSettings: TClaudeTurnSettings;
  Args, ParentVariables, Filtered: TStringList;
  Scope: TClaudeToolScope;
  {$IFDEF UNIX}
  Handle: THandle;
  FakeDirectory, FakeClaude, LargePrompt: String;
  Run: TAssistantClaudeRun;
  Snapshot: TClaudeRunSnapshot;
  ChildPid: Integer;
  {$ENDIF}
Begin
  Check('usage fixture records input tokens', ParseClaudeTurnResult(UsageFixture, Turn, ErrorText) And
    (Turn.InputTokens = 9));
  Check('usage fixture records output tokens', Turn.OutputTokens = 3);
  Check('usage fixture is reported', Turn.UsageState = ClaudeUsageReported);
  Check('usage fixture keeps the answer', Turn.Text = 'fixture answer');

  Check('no-usage fixture parses', ParseClaudeTurnResult(NoUsageFixture, Turn, ErrorText));
  Check('no-usage fixture is unavailable', Turn.UsageState = ClaudeUsageUnavailable);
  Check('no-usage fixture keeps the answer', Turn.Text = 'plain answer');
  Check('error result is not an answer', (Not ParseClaudeTurnResult(
    '{"is_error":true,"result":"quota exceeded"}', Turn, ErrorText)) And (Pos('quota', LowerCase(ErrorText)) > 0) And
    (Turn.Text = ''));

  Stream := FoldFixture('plain.jsonl');
  Check('plain stream finishes', Stream.Finished And (Not Stream.IsError));
  Check('plain stream answer', Stream.Text = 'pong');
  Check('plain stream is on the subscription', Stream.KeySource = 'none');
  Check('plain stream has its session', Stream.SessionId <> '');
  Check('plain stream counts cached prompt tokens', (Stream.Turn.UsageState = ClaudeUsageReported) And
    (Stream.Turn.InputTokens = 2 + 6531 + 9013) And (Stream.Turn.OutputTokens = 4));
  Check('plain stream context includes the cache', Stream.ContextTokens = 2 + 6531 + 9013);
  Check('plain stream reports the subscription windows', (Stream.RateLimitStatus = 'allowed') And
    (Pos('five_hour', Stream.RateLimitJson) > 0));
  Check('plain stream ran no tool', Stream.ToolCalls = 0);
  Check('plain stream outcome is an answer', ClaudeTurnOutcome(Stream, 0, '', ErrorText) And (ErrorText = ''));

  Stream := FoldFixture('tool.jsonl');
  Check('tool stream counts the tool call', Stream.ToolCalls = 1);
  Check('tool stream answer', Stream.Text = 'Lazarus');
  Check('tool stream outcome is an answer', ClaudeTurnOutcome(Stream, 0, '', ErrorText));

  Check('tool stream records the call', (Length(Stream.Tools) = 1) And (Stream.Tools[0].Name = 'Read') And
    (Pos('notes.txt', Stream.Tools[0].Input) > 0));
  Check('tool stream records the result', Stream.Tools[0].Done And (Not Stream.Tools[0].IsError) And
    (Pos('Lazarus fixture notes', Stream.Tools[0].Output) > 0));
  Check('tool call comes before the answer text', Stream.Tools[0].TextBefore = 0);

  Stream := FoldFixture('plain.jsonl');
  Check('a turn without tools records none', (Length(Stream.Tools) = 0) And (Stream.Thinking = ''));

  Stream := FoldFixture('maxturns.jsonl');
  Check('thinking is shown as a size, not as text', Pos('Thought for about', Stream.Thinking) = 1);

  ClearClaudeStream(Stream);
  ApplyClaudeStreamLine('{"type":"system","subtype":"thinking_tokens","estimated_tokens":50}', Stream);
  Check('live thinking note', Stream.Thinking = 'Thinking… about 50 tokens.');
  ApplyClaudeStreamLine('{"type":"system","subtype":"thinking_tokens","estimated_tokens":200}', Stream);
  Check('live thinking note grows in place', Stream.Thinking = 'Thinking… about 200 tokens.');
  ApplyClaudeStreamLine('{"type":"assistant","message":{"content":[{"type":"thinking","thinking":""}]}}', Stream);
  Check('finished thinking note stays', Stream.Thinking = 'Thought for about 200 tokens.' + LineEnding);
  ApplyClaudeStreamLine('{"type":"assistant","message":{"content":[{"type":"text","text":"Reading now."},' +
    '{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]}}', Stream);
  Check('a call is placed after the text before it', (Length(Stream.Tools) = 1) And
    (Stream.Tools[0].TextBefore = Length('Reading now.')) And (Stream.Tools[0].ThinkingBefore = Length(Stream.Thinking)));
  Check('a pending call is not done', Not Stream.Tools[0].Done);
  ApplyClaudeStreamLine('{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1",' +
    '"content":[{"type":"text","text":"a.pas"}],"is_error":true}]}}', Stream);
  Check('a block-list result is read and its error kept', Stream.Tools[0].Done And Stream.Tools[0].IsError And
    (Stream.Tools[0].Output = 'a.pas'));
  ApplyClaudeStreamLine('{"type":"assistant","message":{"content":[{"type":"text","text":"Done."}]}}', Stream);
  Check('text after a call follows it', Stream.Text = 'Reading now.' + LineEnding + LineEnding + 'Done.');

  Stream := FoldFixture('denied.jsonl');
  Check('a refused call is an error result', (Length(Stream.Tools) = 1) And Stream.Tools[0].Done And
    Stream.Tools[0].IsError);

  Stream := FoldFixture('resume.jsonl');
  Check('resumed stream answer', Stream.Text = 'notes.txt');

  Stream := FoldFixture('denied.jsonl');
  Check('denied write still finishes', Stream.Finished And (Not Stream.IsError));
  Check('denied write is counted', Stream.Denials = 1);
  Check('denied write counts the attempted tool', Stream.ToolCalls = 1);

  Stream := FoldFixture('maxturns.jsonl');
  Check('turn limit is an error', Stream.Finished And Stream.IsError And (Stream.ResultSubtype = 'error_max_turns'));
  Check('turn limit has a sentence', (Not ClaudeTurnOutcome(Stream, 1, '', ErrorText)) And
    (ErrorText = 'Claude Code stopped at its turn limit.'));

  Stream := FoldFixture('badresume.jsonl');
  Check('unknown session reports the reason', (Not ClaudeTurnOutcome(Stream, 1, '', ErrorText)) And
    (Pos('No conversation found', ErrorText) > 0));
  Check('unknown session is recognised', ClaudeSessionMissing(ErrorText));
  Check('a model error is not a missing session', Not ClaudeSessionMissing('model not found'));
  Script := NewClaudeSessionId;
  Check('session id is a bare lower-case UUID', (Length(Script) = 36) And (Script[9] = '-') And
    (Script = LowerCase(Script)) And (Pos('{', Script) = 0));
  Check('session ids differ', NewClaudeSessionId <> Script);

  ClearClaudeStream(Stream);
  Check('noise line is not an event', Not ApplyClaudeStreamLine('Warning: config {legacy} ignored', Stream));
  Check('no result after a clean exit is not an answer', (Not ClaudeTurnOutcome(Stream, 0, '', ErrorText)) And
    (ErrorText <> ''));
  Check('no result after a refused flag says so', (Not ClaudeTurnOutcome(Stream, 1, RefusedModeFixture, ErrorText)) And
    (Pos('refused the permission mode flag', ErrorText) > 0));
  ApplyClaudeStreamLine('{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","rateLimitType":"five_hour"}}',
    Stream);
  ApplyClaudeStreamLine('{"type":"result","subtype":"success","is_error":true,"result":"Limit reached"}', Stream);
  Check('a refused subscription window reads as quota', (Not ClaudeTurnOutcome(Stream, 1, '', ErrorText)) And
    (Pos('quota', ErrorText) > 0));
  Check('single json result parses', ParseClaudeTurnResult(FixtureText('plain-result.json'), Turn, ErrorText) And
    (Turn.Text = 'pong'));
  Check('single json result with noise parses', ParseClaudeTurnResult('Warning: config {legacy} ignored' + LineEnding +
    '{"result":"hello","is_error":false}', Turn, ErrorText) And (Turn.Text = 'hello'));

  Check('models come from the initialize response', ClaudeModelsFromControlResponse(FixtureText('initialize.jsonl'),
    'init-1', Script));
  Check('another request id is not this response', Not ClaudeModelsFromControlResponse(
    FixtureText('initialize.jsonl'), 'other', ErrorText));
  Check('stream output without a control response has no models', Not ClaudeModelsFromControlResponse(
    FixtureText('plain.jsonl'), 'init-1', ErrorText));
  ParentVariables := TStringList.Create;
  Try
    CollectClaudeModels(Script, ParentVariables);
    Check('every reported model is listed', ParentVariables.Count = 13);
    Check('models keep the program order', (ParentVariables[0] = 'default') And (ParentVariables[1] = 'opus') And
      (ParentVariables.IndexOf('claude-opus-4-8') >= 0));
    Check('model description combines name and purpose',
      Pos('Opus 5.5', ClaudeModelDescription(Script, 'opus')) = 1);
    Check('unknown model has no description', ClaudeModelDescription(Script, 'nothing') = '');
    Check('effort levels for a model', CollectClaudeEffortLevels(Script, 'fable', ParentVariables) And
      (ParentVariables.IndexOf('max') >= 0) And (ParentVariables.IndexOf('low') = 0));
    Check('a model without effort levels has none', Not CollectClaudeEffortLevels(Script,
      'claude-haiku-4-5-20251001', ParentVariables));
    CollectClaudeModels('', ParentVariables);
    Check('no list falls back to the aliases', (ParentVariables.Count = 5) And (ParentVariables[0] = 'default'));
    CollectClaudeModels('not json', ParentVariables);
    Check('a bad list falls back to the aliases', ParentVariables.Count = 5);
  Finally
    FreeAndNil(ParentVariables);
  End;

  Check('refused mode stderr is recognised', PermissionFlagRefused(RefusedModeFixture));
  Check('unknown flag stderr is recognised', PermissionFlagRefused('error: unknown option ''--permission-mode'''));
  Check('a model error is not a refused flag', Not PermissionFlagRefused('model not found'));
  Check('an answer about the flag is not a refused flag', Not PermissionFlagRefused(
    'Use --permission-mode plan for read-only work; an invalid value stops the program.'));

  Args := TStringList.Create;
  Try
    AppendClaudeTurnArguments('sonnet', '', '', False, Args);
    Check('turn is claude print stream-json', (Args[0] = '-p') And (Args[1] = '--output-format') And
      (Args[2] = 'stream-json') And (Args[3] = '--verbose'));
    Check('turn sets the connection model', (Args[4] = '--model') And (Args[5] = 'sonnet'));
    Check('turn leaves Claude Code''s permission mode at its default', (Args.Count = 6) And
      (Args.IndexOf('--permission-mode') < 0));
    Check('turn does not send tools or skills', (Args.IndexOf('--tools') < 0) And (Args.IndexOf('--skill') < 0));
    Check('turn without a session leaves it to Claude Code', (Args.IndexOf('--session-id') < 0) And
      (Args.IndexOf('--resume') < 0));
    Args.Clear;
    AppendClaudeTurnArguments('sonnet', '', 'a1b2', False, Args);
    Check('first turn names its session', (Args.IndexOf('--session-id') >= 0) And
      (Args[Args.IndexOf('--session-id') + 1] = 'a1b2') And (Args.IndexOf('--permission-mode') < 0));
    Args.Clear;
    AppendClaudeTurnArguments('sonnet', '', 'a1b2', True, Args);
    Check('later turn resumes its session', (Args.IndexOf('--resume') >= 0) And
      (Args[Args.IndexOf('--resume') + 1] = 'a1b2') And (Args.IndexOf('--session-id') < 0));
    Check('turn without an effort leaves it to the model', Args.IndexOf('--effort') < 0);
    Args.Clear;
    AppendClaudeTurnArguments('default', 'high', '', False, Args);
    Check('default model leaves the choice to Claude Code', Args.IndexOf('--model') < 0);
    Check('effort is passed', (Args.IndexOf('--effort') >= 0) And (Args[Args.IndexOf('--effort') + 1] = 'high'));

    Args.Clear;
    AppendClaudeModeArguments(ctsNone, '/tmp/lazarus-mcp-x.json', Args);
    Check('chat turns get no tools and no server, even with a config file', (Args.Count = 2) And (Args[0] = '--tools=') And
      (Args[1] = '--strict-mcp-config'));
    For Scope In [ctsRead, ctsMarkdown, ctsProject] Do
      Begin
        Args.Clear;
        AppendClaudeModeArguments(Scope, '/tmp/lazarus-mcp-x.json', Args);
        Check('turns outside chat read with Claude Code and act through the Lazarus server', (Args.Count = 4) And
          (Args[0] = '--tools=Read,Grep,Glob') And (Args[1] = '--mcp-config=/tmp/lazarus-mcp-x.json') And
          (Args[2] = '--allowedTools=mcp__lazarus__*') And (Args[3] = '--strict-mcp-config'));
        Check('turns outside chat have no Claude Code edit, write or shell tool',
          (Pos('Edit', Args.Text) = 0) And (Pos('Write', Args.Text) = 0) And (Pos('Bash', Args.Text) = 0));
      End;
    Args.Clear;
    AppendClaudeModeArguments(ctsProject, '', Args);
    Check('without a config file a turn only reads and loads no server', (Args.Count = 2) And
      (Args[0] = '--tools=Read,Grep,Glob') And (Args[1] = '--strict-mcp-config'));
    Check('a Lazarus tool is shown without the server prefix', ClaudeToolDisplayName('mcp__lazarus__read_buffer') = 'read_buffer');
    Check('a Claude Code tool keeps its name', ClaudeToolDisplayName('Read') = 'Read');
    Check('a malformed MCP name is left alone', (ClaudeToolDisplayName('mcp__lazarus__') = 'mcp__lazarus__') And
      (ClaudeToolDisplayName('mcp____x') = 'mcp____x'));
    Check('a settings record left at its default reads only', Default(TClaudeTurnSettings).ToolScope = ctsRead);
  Finally
    Args.Free;
  End;
  Check('row status says Claude Code keeps the session', ClaudeKeepsSessionText = 'Claude Code keeps the session.');

  Check('a missing file is not a runtime', ClaudeRuntimeFromBrowsedPath(ParamStr(0) + '.missing') = '');
  {$IFDEF UNIX}
  Script := GetTempDir + 'laz-claude-runtime-' + IntToStr(GetProcessID);
  Handle := FileCreate(Script);
  Check('runtime fixture created', Handle >= 0);
  If Handle >= 0 Then
    FileClose(Handle);
  Check('a plain file is not a runtime', ClaudeRuntimeFromBrowsedPath(Script) = '');
  Check('runtime fixture is executable', FpChmod(Script, &755) = 0);
  Check('browsed executable is the expanded runtime path', ClaudeRuntimeFromBrowsedPath(Script) = ExpandFileName(Script));
  DeleteFile(Script);
  {$ENDIF}

  Check('subscription status parses', ParseClaudeAccount(FixtureText('auth-sub.json'), Account));
  Check('subscription status is a subscription', ClaudeAccountIsSubscription(Account));
  Check('subscription text names the plan', ClaudeAccountText(Account) = 'Signed in with a Claude Pro subscription.');
  Check('api key status parses', ParseClaudeAccount(FixtureText('auth-key.json'), Account));
  Check('api key status is not a subscription', Not ClaudeAccountIsSubscription(Account));
  Check('api key text says billed per use', Pos('billed per use', ClaudeAccountText(Account)) > 0);
  Check('api key text names the key source', Pos('ANTHROPIC_API_KEY', ClaudeAccountText(Account)) > 0);
  Check('signed-out status is not a subscription', ParseClaudeAccount('{"loggedIn":false}', Account) And
    (Not ClaudeAccountIsSubscription(Account)) And (Pos('not signed in', ClaudeAccountText(Account)) > 0));
  Check('cloud provider is not a subscription', ParseClaudeAccount(
    '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"bedrock","subscriptionType":"pro"}', Account) And
    (Not ClaudeAccountIsSubscription(Account)));
  Check('non-status text is refused', Not ParseClaudeAccount('error: unknown command', Account));
  Check('status without loggedIn is refused', Not ParseClaudeAccount('{"authMethod":"claude.ai"}', Account));

  ParentVariables := TStringList.Create;
  Filtered := TStringList.Create;
  Try
    ParentVariables.Add('PATH=/usr/bin');
    ParentVariables.Add('ANTHROPIC_API_KEY=sk-ant-fixture');
    ParentVariables.Add('ANTHROPIC_AUTH_TOKEN=fixture');
    ParentVariables.Add('ANTHROPIC_BASE_URL=http://127.0.0.1:1');
    ParentVariables.Add('CLAUDE_CODE_USE_BEDROCK=1');
    ParentVariables.Add('CLAUDE_CODE_USE_VERTEX=1');
    ParentVariables.Add('CLAUDE_CODE_USE_FOUNDRY=1');
    ParentVariables.Add('ANTHROPIC_MODEL=sonnet');
    ParentVariables.Add('HOME=/home/fixture');
    FilterClaudeEnvironment(ParentVariables, Filtered);
    Check('environment keeps ordinary variables', (Filtered.IndexOf('PATH=/usr/bin') >= 0) And
      (Filtered.IndexOf('HOME=/home/fixture') >= 0) And (Filtered.IndexOf('ANTHROPIC_MODEL=sonnet') >= 0));
    Check('environment drops every metered billing variable', Filtered.Count = 3);
    BuildClaudeEnvironment(Filtered);
    Check('this process environment is copied', Filtered.Count > 0);
    Check('this process environment has no API key', Filtered.IndexOfName('ANTHROPIC_API_KEY') < 0);
    Check('the environment lets an MCP tool call wait for approval',
      Filtered.Values['MCP_TOOL_TIMEOUT'] = IntToStr(ClaudeMCPToolTimeoutMs));
    Check('the tool timeout outlasts Claude Code''s own 60 s', ClaudeMCPToolTimeoutMs > 60000);
    Filtered.Clear;
    Filtered.Add('PATH=/usr/bin');
    Filtered.Add('MCP_TOOL_TIMEOUT=5000');
    SetClaudeToolTimeout(Filtered);
    Check('an inherited tool timeout is replaced, not doubled',
      (Filtered.Count = 2) And (Filtered.Values['MCP_TOOL_TIMEOUT'] = IntToStr(ClaudeMCPToolTimeoutMs)));
  Finally
    Filtered.Free;
    ParentVariables.Free;
  End;

  {$IFDEF UNIX}
  FakeDirectory := GetTempDir + 'laz-claude-fake-' + IntToStr(GetProcessID);
  ForceDirectories(FakeDirectory);
  FakeClaude := WriteFakeClaude(FakeDirectory);

  TurnSettings := Default(TClaudeTurnSettings);
  TurnSettings.Executable := FakeClaude;
  TurnSettings.WorkingDirectory := FakeDirectory;
  TurnSettings.TimeoutMs := 20000;
  TurnSettings.Model := 'answer';
  Run := TAssistantClaudeRun.Create(TurnSettings, 'hello');
  Try
    Snapshot := WaitForRun(Run, 20000);
    Check('fake turn completes', Snapshot.Done And (Snapshot.ErrorText = ''));
    Check('fake turn returns its answer', Snapshot.Content = 'fake answer');
    Check('fake turn records the start', Snapshot.Started);
    Check('fake turn reports its session and billing source', (Snapshot.SessionId = 's1') And
      (Snapshot.KeySource = 'none'));
  Finally
    Run.Free;
  End;

  { The fake exits before reading stdin. A 1 MB prompt cannot fit the pipe, so the write hits a closed pipe. }
  SetLength(LargePrompt, 1024 * 1024);
  FillChar(LargePrompt[1], Length(LargePrompt), Ord('x'));
  TurnSettings.Model := 'refuse';
  Run := TAssistantClaudeRun.Create(TurnSettings, LargePrompt);
  Try
    Snapshot := WaitForRun(Run, 20000);
    Check('early exit during a large prompt does not end this process', Snapshot.Done);
    Check('early exit reports the refused flag from stderr',
      Pos('refused the permission mode flag', Snapshot.ErrorText) > 0);
  Finally
    Run.Free;
  End;

  TurnSettings.Model := 'hang';
  TurnSettings.TimeoutMs := 60000;
  Run := TAssistantClaudeRun.Create(TurnSettings, 'hello');
  Try
    ChildPid := ReadChildPid(FakeDirectory, 10000);
    Check('fake turn started a child command', ChildPid > 0);
    Run.Cancel;
    Snapshot := WaitForRun(Run, 10000);
    Check('cancelled turn finishes', Snapshot.Done And (Snapshot.ErrorText = 'Cancelled.'));
  Finally
    Run.Free;
  End;
  Sleep(200);
  Check('cancel also ends commands the turn started', (ChildPid > 0) And (FpKill(ChildPid, 0) <> 0));
  If (ChildPid > 0) And (FpKill(ChildPid, 0) = 0) Then
    FpKill(ChildPid, SIGKILL);
  DeleteFile(IncludeTrailingPathDelimiter(FakeDirectory) + 'child.pid');
  DeleteFile(FakeClaude);
  RemoveDir(FakeDirectory);
  {$ENDIF}

  Source := UnitSource;
  Check('client unit is available to scan', Source <> '');
  Check('unit does not name an OAuth token', Not SourceContains(Source, 'CLAUDE_CODE_OAUTH_TOKEN'));
  Check('unit does not name a Claude account directory', Not SourceContains(Source, '.claude'));
  Check('unit does not name a credential file', Not SourceContains(Source, 'credentials'));
  Check('unit does not name an auth file', Not SourceContains(Source, 'auth.json'));
End.
