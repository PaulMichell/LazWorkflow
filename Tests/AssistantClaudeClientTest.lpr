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
  Classes, SysUtils, AssistantClaudeClient;

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

Function SourceContains(Const Source, Needle: String): Boolean;
Begin
  Result := Pos(LowerCase(Needle), LowerCase(Source)) > 0;
End;

Var
  Source, ErrorText, Script: String;
  Turn: TClaudeTurnResult;
  Account: TClaudeAccount;
  Args, ParentVariables, Filtered: TStringList;
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
  Check('usage fixture leaves cost empty', Turn.Cost = '');
  Check('usage fixture is reported', Turn.UsageState = ClaudeUsageReported);
  Check('usage fixture keeps the answer', Turn.Text = 'fixture answer');

  Check('no-usage fixture parses', ParseClaudeTurnResult(NoUsageFixture, Turn, ErrorText));
  Check('no-usage fixture is unavailable', Turn.UsageState = ClaudeUsageUnavailable);
  Check('no-usage fixture leaves cost empty', Turn.Cost = '');
  Check('no-usage fixture keeps the answer', Turn.Text = 'plain answer');
  Check('error result is not an answer', (Not ParseClaudeTurnResult(
    '{"is_error":true,"result":"quota exceeded"}', Turn, ErrorText)) And (Pos('quota', LowerCase(ErrorText)) > 0) And
    (Turn.Text = ''));

  Check('ask leaves the program default', ClaudePermissionMode('ask') = '');
  Check('an empty approval leaves the program default', ClaudePermissionMode('') = '');
  Check('auto maps to accept edits', ClaudePermissionMode('auto') = 'acceptEdits');
  Check('always maps to bypass', ClaudePermissionMode(' Always ') = 'bypassPermissions');
  Check('plan maps to plan', ClaudePermissionMode('plan') = 'plan');
  Check('refused mode stderr is recognised', PermissionFlagRefused(RefusedModeFixture));
  Check('unknown flag stderr is recognised', PermissionFlagRefused('error: unknown option ''--permission-mode'''));
  Check('a model error is not a refused flag', Not PermissionFlagRefused('model not found'));
  Check('an answer about the flag is not a refused flag', Not PermissionFlagRefused(
    'Use --permission-mode plan for read-only work; an invalid value stops the program.'));

  Args := TStringList.Create;
  Try
    AppendClaudeTurnArguments('sonnet', 'acceptEdits', Args);
    Check('turn is claude print json', (Args[0] = '-p') And (Args[1] = '--output-format') And (Args[2] = 'json'));
    Check('turn sets the connection model', (Args[3] = '--model') And (Args[4] = 'sonnet'));
    Check('turn maps the accepted permission mode', (Args[5] = '--permission-mode') And (Args[6] = 'acceptEdits'));
    Check('turn does not send tools or skills', (Args.IndexOf('--tools') < 0) And (Args.IndexOf('--skill') < 0));
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
  Finally
    Filtered.Free;
    ParentVariables.Free;
  End;

  {$IFDEF UNIX}
  FakeDirectory := GetTempDir + 'laz-claude-fake-' + IntToStr(GetProcessID);
  ForceDirectories(FakeDirectory);
  FakeClaude := WriteFakeClaude(FakeDirectory);

  Run := TAssistantClaudeRun.Create(FakeClaude, 'answer', 'ask', 'hello', FakeDirectory, 20000);
  Try
    Run.Start;
    Snapshot := WaitForRun(Run, 20000);
    Check('fake turn completes', Snapshot.Done And (Snapshot.ErrorText = ''));
    Check('fake turn returns its answer', Snapshot.Content = 'fake answer');
    Check('fake turn records the start', Snapshot.Started);
  Finally
    Run.Free;
  End;

  { The fake exits before reading stdin. A 1 MB prompt cannot fit the pipe, so the write hits a closed pipe. }
  SetLength(LargePrompt, 1024 * 1024);
  FillChar(LargePrompt[1], Length(LargePrompt), Ord('x'));
  Run := TAssistantClaudeRun.Create(FakeClaude, 'refuse', 'ask', LargePrompt, FakeDirectory, 20000);
  Try
    Run.Start;
    Snapshot := WaitForRun(Run, 20000);
    Check('early exit during a large prompt does not end this process', Snapshot.Done);
    Check('early exit reports the refused flag from stderr',
      Pos('refused the permission mode flag', Snapshot.ErrorText) > 0);
  Finally
    Run.Free;
  End;

  Run := TAssistantClaudeRun.Create(FakeClaude, 'hang', 'ask', 'hello', FakeDirectory, 60000);
  Try
    Run.Start;
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
