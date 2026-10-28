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
  HelpFixture = 'Usage: claude' + LineEnding +
    '--permission-mode <mode>  choices: "default", "acceptEdits", "bypassPermissions"';

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

  Check('ask maps to default when that is the accepted value', ClaudePermissionMode(HelpFixture, 'ask') = 'default');
  Check('auto maps to accept edits', ClaudePermissionMode(HelpFixture, 'auto') = 'acceptEdits');
  Check('always maps to bypass', ClaudePermissionMode(HelpFixture, 'always') = 'bypassPermissions');
  Check('missing flag is not sent', ClaudePermissionMode('usage: claude', 'always') = '');
  Check('refused flag text is recognised', PermissionFlagRefused('error: unknown option --permission-mode'));
  Check('a model error is not a refused flag', Not PermissionFlagRefused('model not found'));

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

  Source := UnitSource;
  Check('client unit is available to scan', Source <> '');
  Check('unit does not name an OAuth token', Not SourceContains(Source, 'CLAUDE_CODE_OAUTH_TOKEN'));
  Check('unit does not name a Claude account directory', Not SourceContains(Source, '.claude'));
  Check('unit does not name a credential file', Not SourceContains(Source, 'credentials'));
  Check('unit does not name an auth file', Not SourceContains(Source, 'auth.json'));
End.
