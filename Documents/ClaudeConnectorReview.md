# Claude connector review

Date: 28 October 2026. Repository baseline: `fac668d` (main).
Scope: `Source/LazAssistantTools/AssistantClaudeClient.pas` (604 lines), its integration in `ProjectAssistantForm.pas`, `AssistantSettingsForm.pas`, `AssistantRecovery.pas`, and `Tests/AssistantClaudeClientTest.lpr`.
Standard applied: `Documents/free-pascal-engineer.md` (the tracked copy, 19 Oct). The repository-root `free-pascal-engineer.md` is an older August copy and was not used.

This review was written before any implementation, without modifying the project; its builds and probes ran outside the repository. Work now tracks against the plan in `Documents/Plan-ClaudeConnector.md`. Sections 11 and 12 record the decisions and the progress up to the point the plan took over.

---

## 1. Summary

The connector is a small, sensible design: it drives the installed `claude` program in print mode (`-p`), never touches credentials, and runs each turn on a worker thread. That approach is the right one for subscription use.

As a prototype that has never been run, it has one **critical subscription problem** and several defects that would show up on first real use:

| # | Severity | Finding |
|---|----------|---------|
| S1 | **Critical** | Nothing ensures subscription billing. An `ANTHROPIC_API_KEY` in the IDE environment silently switches every turn to metered API billing (verified). |
| B1 | High | A successful answer that mentions `--permission-mode` and words like "invalid" is reported as a failure (verified). |
| B2 | High | A Claude turn that times out, or exits with no output, is replayed from scratch with no attempt cap. Agentic turns are not idempotent, so file edits and commands can run twice. |
| B3 | High | Writing the prompt to stdin can raise `SIGPIPE` in the IDE process if `claude` exits early (for example on a rejected flag). The project already has `WritePipeNoSignal` for this, but the connector doesn't use it. Plausible, not reproduced. |
| B4 | Medium | Cancel and timeout send SIGTERM to `claude` only. Child processes it started (Bash tool commands, MCP servers) are orphaned. `ProcessSession.TerminateSession` exists but isn't used. |
| B5 | Medium | "Claude Code keeps the session" is not true. No `--session-id` or `--resume` is passed. Each turn is a new session, and up to 24 kB of recap is re-sent every turn. |
| B6 | Medium | Token usage is parsed and then discarded. The snapshot carries text only, so the footer and settings always show "did not report usage". Cache tokens are not counted even when parsed. |
| B7 | Medium | The permission-mode mapping depends on matching words in `--help` output. `ask` maps to `default` only because the word "default" appears elsewhere in the help text. `default` is not a listed choice in 2.1.312; it is accepted today as an undocumented alias. |
| B8 | Low | Error results without a `result` field (for example `error_max_turns`) surface the raw JSON as the error message (verified). |
| B9 | Low | A diagnostic line containing `{` before the JSON makes parsing fail (verified). |
| B10 | Low | The subscription usage-limit message is not recognised as a credit wait, so it stops instead of waiting for the reset. |
| T1 | Medium | `AssistantClaudeClientTest` is not registered in `Tests/RunAssistantTests.pas`. As written it doesn't link: the LCL is pulled in through `AssistantConnections`, but the program has no `Interfaces`. |
| A1 | Medium | Layering: a process wrapper depends on `AssistantConnections` → `AssistantConversation` → `LazIDEIntf`, and only for `ApplyClaudeRuntime`, which nothing in production calls. |

There are also 12 style deviations from the skill document (§6), all straightforward to fix.

**Recommendation:** fix S1, B1–B4 and T1/A1 before the first live run. Then switch to `--output-format stream-json` with native sessions (§8.1–8.2). That single change resolves B5, B6, B8 and B9, and enables live streaming and safer recovery.

---

## 2. Method and evidence

| Check | Result |
|-------|--------|
| Installed CLI | `/home/paul/.local/bin/claude`, version `2.1.312 (Claude Code)` |
| `claude auth status --json` (normal environment) | `authMethod: claude.ai`, `apiProvider: firstParty`, `subscriptionType: pro`. No `ANTHROPIC_*` variables are set in this shell. |
| Same, with `ANTHROPIC_API_KEY=<dummy>` | `authMethod: api_key`, `apiKeySource: ANTHROPIC_API_KEY`, `subscriptionType: null`. **The environment overrides the subscription.** |
| `--permission-mode` choices (from CLI validation error) | `acceptEdits, auto, bypassPermissions, manual, dontAsk, plan`. `ask` is rejected; `default` is accepted but not listed. |
| `--session-id` with a braced GUID | Rejected: `Invalid session ID. Must be a valid UUID.` |
| `claude --help` cost | About 130 ms per call, run on every turn. |
| Existing test (built in scratchpad with `Interfaces` added) | 30/30 pass. The unmodified `.lpr` fails to link (`undefined reference to WSRegister…`). |
| Probe program against the real unit and real help text | See §4. All results quoted there were observed. |
| Code snippets in this report | §3.2, §4 (B7), §8.1, §8.2 and §9.1 compile together in one scratch unit with FPC 3.3.1 against `ProcessSession` and LazUtils. The only output is a hint about the uninitialised read buffer in `DrainPipe`. The §9.2 thread shape depends on routines not written here (`RunClaudeTurn`, `Publish`), so it was not compiled. |

**Not exercised:** any real model turn. I didn't spend your subscription allowance on one. The stream-json event shapes in §8 follow the Claude Code documentation and should be confirmed by capturing fixtures from one real turn before implementation (§10, step 1). I also did not run `claude auth login` without a terminal attached.

---

## 3. Subscription billing (S1): critical

### 3.1 Problem

`RunCaptured` (`AssistantClaudeClient.pas:327–336`) starts `claude` with the IDE's full inherited environment. Claude Code chooses its billing source in this order: environment API key / auth token, then `apiKeyHelper` from settings, then third-party provider switches, and only then the claude.ai subscription login. Any of the following in the Lazarus environment therefore moves every turn to metered billing, with no indication in the UI:

- `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` (verified for the first)
- `ANTHROPIC_BASE_URL` (a proxy or gateway)
- `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`, `CLAUDE_CODE_USE_FOUNDRY`
- an `apiKeyHelper` in the user's Claude settings, which the environment alone cannot remove

This is a real risk on this machine: the assistant already supports API-key rows (`key_source: env`) for other providers, so `ANTHROPIC_API_KEY` could easily end up exported in a desktop session.

Related gaps:

- `StartClaudeSignIn` runs `claude auth login` without `--claudeai`. Subscription is the current default, but the flag makes the intent explicit and protects against a changed default.
- The settings **Check** button (`AssistantSettingsForm.pas:1295`) only checks that the file is executable. It doesn't confirm sign-in or the billing method.
- Never add `--bare`. According to `--help`, it makes authentication "strictly ANTHROPIC_API_KEY or apiKeyHelper (OAuth and keychain are never read)". `--max-budget-usd` and `--betas` are API-key features and should also be avoided.

### 3.2 Required design: three independent guards

1. **Scrub** the child environment of variables that select metered billing.
2. **Pre-flight** before each turn (or cached for a few minutes per executable): run `claude auth status --json` in that scrubbed environment. Require `loggedIn = true`, `authMethod = 'claude.ai'`, `apiProvider = 'firstParty'` and a non-empty `subscriptionType`. Read those four fields only; never log `email` or `orgId`. This uses the program's own report and doesn't read account files, so it keeps the unit's "no sign-in files" rule.
3. **In-stream backstop** (once stream-json is in use): the `system`/`init` event reports `apiKeySource`. If it is anything other than `none`, stop the process group at once and report an error. This catches `apiKeyHelper` and any future billing source that the pre-flight misses. *(Confirm on a captured fixture that `init` is emitted before the first model request.)*

```pascal
Type
  TClaudeAccount = Record
    SignedIn: Boolean;
    AuthMethod: String;
    ApiProvider: String;
    SubscriptionType: String;
  End;

Const
  { Each of these moves Claude Code off the subscription and onto metered billing. }
  ClaudeMeteredVariables: Array[0..5] Of String = ('ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_BASE_URL',
    'CLAUDE_CODE_USE_BEDROCK', 'CLAUDE_CODE_USE_VERTEX', 'CLAUDE_CODE_USE_FOUNDRY');
  ClaudeStatusTimeoutMs = 15000;

/// Copies this process environment without the variables that select metered billing.
Procedure BuildClaudeEnvironment(Environment: TStrings);
/// Runs the program's own status report in that environment. Reads four fields only.
Function ReadClaudeAccount(Const Executable: String; Out Account: TClaudeAccount; Out ErrorText: String): Boolean;
/// True only for a signed-in claude.ai subscription on the first-party service.
Function ClaudeAccountIsSubscription(Const Account: TClaudeAccount): Boolean;
```

```pascal
Procedure BuildClaudeEnvironment(Environment: TStrings);
Var
  I, J: Integer;
  Entry, VariableName: String;
  Metered: Boolean;
Begin
  If Not Assigned(Environment) Then
    Exit;
  Environment.Clear;
  For I := 1 To GetEnvironmentVariableCount Do
    Begin
      Entry := GetEnvironmentString(I);
      VariableName := Copy(Entry, 1, Pos('=', Entry) - 1);
      Metered := False;
      For J := Low(ClaudeMeteredVariables) To High(ClaudeMeteredVariables) Do
        If CompareText(VariableName, ClaudeMeteredVariables[J]) = 0 Then
          Metered := True;
      If Not Metered Then
        Environment.Add(Entry);
    End;
End;

Function JsonText(Root: TJSONObject; Const Key: String): String;
Begin
  { A null subscriptionType is a JSON null, not a string. }
  If Root.Find(Key) Is TJSONString Then
    Result := Root.Get(Key, '')
  Else
    Result := '';
End;

Function ReadClaudeAccount(Const Executable: String; Out Account: TClaudeAccount; Out ErrorText: String): Boolean;
Var
  Args, Environment: TStringList;
  StdoutText, StderrText: String;
  ExitCode: Integer;
  Data: TJSONData;
  Root: TJSONObject;
Begin
  Result := False;
  Account := Default(TClaudeAccount);
  Data := Nil;
  Args := TStringList.Create;
  Environment := TStringList.Create;
  Try
    Args.Add('auth');
    Args.Add('status');
    Args.Add('--json');
    BuildClaudeEnvironment(Environment);
    If Not RunCaptured(Executable, '', Args, Environment, '', ClaudeStatusTimeoutMs, StdoutText, StderrText, ExitCode,
      ErrorText) Then
      Exit;
    Try
      Data := GetJSON(StdoutText);
    Except
      On EParserError Do
        Begin
          ErrorText := 'Claude Code did not report its sign-in state.';
          Exit;
        End;
    End;
    If Not (Data Is TJSONObject) Then
      Begin
        ErrorText := 'Claude Code did not report its sign-in state.';
        Exit;
      End;
    Root := TJSONObject(Data);
    Account.SignedIn := Root.Get('loggedIn', False);
    Account.AuthMethod := JsonText(Root, 'authMethod');
    Account.ApiProvider := JsonText(Root, 'apiProvider');
    Account.SubscriptionType := JsonText(Root, 'subscriptionType');
    Result := True;
  Finally
    Data.Free;
    Environment.Free;
    Args.Free;
  End;
End;

Function ClaudeAccountIsSubscription(Const Account: TClaudeAccount): Boolean;
Begin
  Result := Account.SignedIn And (Account.AuthMethod = 'claude.ai') And (Account.ApiProvider = 'firstParty') And
    (Account.SubscriptionType <> '');
End;
```

The turn path then refuses to start with a clear message, for example *"This Claude connection is not using a Claude subscription (found api_key). Remove ANTHROPIC_API_KEY from the Lazarus environment or sign in with Claude."* The settings **Check** button should run the same check and show `Signed in — Claude Pro` or the refusal reason. `ClassifyDroppedTransport` must treat this refusal as a stop, never as a retry.

---

## 4. Correctness bugs

### B1: successful answers can be reported as a refused flag (verified)

`AssistantClaudeClient.pas:491` calls `PermissionFlagRefused(StderrText + LineEnding + StdoutText)` on every turn, including successful ones. Stdout holds the model's answer. Probe result:

```
refused? on a good answer -> TRUE
  ('{"type":"result","is_error":false,"result":"An invalid --permission-mode value is rejected by the CLI."}')
```

**Fix:** only test stderr, only when `ExitCode <> 0`, and match the CLI's actual wording: `option '--permission-mode <mode>' argument '…' is invalid`. Once B7 is fixed the client sends only known-valid values, so this branch becomes a diagnostic rather than a control path.

```pascal
  If (ExitCode <> 0) And PermissionFlagRefused(StderrText) Then
```

### B2: non-idempotent turns are replayed without limit

- `RunCaptured` returns `'Claude Code timed out.'` (line 393). `IsTransientNetworkError` (`AssistantRecovery.pas:627`) matches `timed out`, so `ClassifyDroppedTransport` returns `araRetryLastAction` with `WaitForConnection = True`.
- `'Claude Code did not complete the turn.'` is the fallback for any non-zero exit with empty output, and for any `Execute` failure (lines 502, 577). `ProcessTransportDropped` (`AssistantRecovery.pas:950`) matches it as well.
- `TryDeferDroppedTransport` / `ResumeDroppedTransport` (`ProjectAssistantForm.pas:4610–4762`) keep no attempt count.

A ten-minute agentic turn that legitimately runs long is therefore killed at `ClaudeRunTimeoutMs` (600000) and restarted with the same prompt, indefinitely. Edits it already made, and shell commands it already ran, are repeated. The Codex path already refuses this (`AssistantRecovery.pas:972`: "App-server turns and tool results are not idempotent"). The Claude path should follow the same rule.

**Fix:**

1. Only auto-retry a Claude turn if it is known that no tool ran. Stream-json makes this observable (`tool_use` count, §8.1). Until then, never auto-retry a Claude turn after the process has started.
2. Don't word the timeout as a network timeout (for example, "Claude Code did not finish within the turn limit."), and classify it as a stop.
3. Add an attempt cap that uses `AssistantFaultRetryCap`, as HTTP rounds already do.
4. With native sessions (§8.2), recovery can offer **Resume** (`--resume <id>` with "continue") instead of replaying the whole prompt.

```pascal
        { A Claude turn that ran a tool may have changed files. Replaying it would repeat that work. }
        If (Snapshot.ToolCalls = 0) And (FTransportAttempts < AssistantFaultRetryCap(-1)) And
          TryDeferDroppedTransport(FLiveContent, Snapshot.ErrorText, Snapshot.ErrorText) Then
```

### B3: `SIGPIPE` on prompt write (plausible)

Lines 345–359 write the whole prompt with `Proc.Input.Write` before reading anything. If `claude` exits early (rejected flag, bad model, missing auth), the write gets `EPIPE`. Unless something ignores the signal, `SIGPIPE` is delivered to the **Lazarus process**. Prompts above the 64 kB pipe buffer always reach this window; smaller prompts reach it when the exit wins the race. The recap (24 kB) plus IDE context can exceed 64 kB.

`ProcessSession.WritePipeNoSignal` exists for exactly this case and is used by the Codex transport. **Fix:** use it, and on `Closed` stop writing but still drain stdout and stderr so the real reason is reported. See §9.1.

### B4: orphaned child processes on cancel or timeout

`Proc.Terminate(1)` (lines 350, 383, 391) signals only the `claude` process. Its own children (`Bash` tool commands such as `lazbuild` or `make`, MCP servers, sub-agents) survive and can keep editing files after the user has pressed Stop. **Fix:** `StartInOwnSession(Proc)` before `Execute`, and `TerminateSession(Proc)` (term, short wait, kill, process group) on cancel and timeout. Both are already in `LazWorkflowCommon/ProcessSession.pas`.

### B5: the "session" claim is inaccurate and expensive

`ClaudeKeepsSessionText` is shown in five places, but `AppendClaudeTurnArguments` passes neither `--session-id` nor `--resume`. Each turn is a brand-new Claude Code session. `StartClaudeReply` (`ProjectAssistantForm.pas:5040–5049`) makes up for this by prepending up to 24 000 characters of recap, with responses cut to 8 000 characters each. As a result:

- Tool results, file reads and the model's own reasoning from earlier turns are lost.
- Prompt caching across turns is limited. The recap is re-sent each time, which uses up subscription allowance faster.
- Each turn also creates an orphan session file under the user's Claude projects directory.

**Fix:** §8.2.

### B6: usage parsed, then discarded

`ParseClaudeTurnResult` fills `InputTokens` and `OutputTokens`, but `TClaudeRunSnapshot` has no usage fields and `Execute` copies only `Turn.Text` (line 595). `ShowConnectionUsage` therefore always says the connection did not report usage. Even if passed through, `input_tokens` excludes `cache_read_input_tokens` and `cache_creation_input_tokens`, which are most of the context on a resumed or tool-heavy turn. Probe result:

```
cached usage -> input=3 (40000+2000 cached tokens not counted)
```

`TClaudeTurnResult.Cost` is written three times (lines 84, 280, 296) and never read. It is dead weight, contrary to the intent of commit `184a28d`. Don't surface `total_cost_usd` either: on a subscription it is a notional figure, not a charge.

### B7: permission mode taken from words in the help text

`ClaudePermissionMode` scans the whole `--help` text for words. Results against the real 2.1.312 help:

```
ask    -> "default"            (matched the word "default" in unrelated option text)
auto   -> "acceptEdits"
always -> "bypassPermissions"
```

`default` isn't among the listed choices (`acceptEdits, auto, bypassPermissions, manual, dontAsk, plan`). It works only as an unlisted alias. If the alias is removed, every **Ask** turn fails at argument validation, and B1/B2 then turn that failure into retries.

Note also that in `-p` mode there is nobody to answer a prompt. In **Ask** mode, any tool that needs approval is denied, so Claude can read but not edit. That's a reasonable safe default, but the settings label should say so.

**Fix:** use a fixed mapping. Omit the flag for **Ask**, since the program default is always valid. Drop the per-turn `--help` probe.

```pascal
/// Claude Code permission mode for an approval setting. Empty means the program default.
Function ClaudePermissionMode(Const ApprovalMode: String): String;
Var
  Approval: String;
Begin
  Approval := LowerCase(Trim(ApprovalMode));
  If Approval = 'auto' Then
    Result := 'acceptEdits'
  Else If Approval = 'always' Then
    Result := 'bypassPermissions'
  Else If Approval = 'plan' Then
    Result := 'plan'
  Else
    Result := '';
End;
```

The local approval value `auto` and Claude Code's own `--permission-mode auto` (a classifier-driven mode) now mean different things. Document the mapping beside the combo box so nobody "fixes" it into a pass-through.

### B8 / B9: brittle JSON result handling (verified)

```
max turns error text -> "{"type":"result","subtype":"error_max_turns","is_error":true,"num_turns":5}"
leading brace noise parses -> FALSE err="Claude Code did not return a JSON result."
```

`JsonObjectText` takes everything from the first `{` to the last `}`. With `--verbose`, or with any warning that contains a brace, this fails. An error result without `result` text falls through to `BoundText(JsonText)`. **Fix:** with stream-json, parse each line as its own JSON object and map `subtype` to a user sentence (`error_max_turns` → "Claude Code stopped at its turn limit.", `error_during_execution` → the stderr tail).

### B10: subscription usage limit not recognised

`TextSaysOutOfCredits` looks for `credits`, `quota`, `spending`, `billing`. Claude Code's subscription limit messages use other wording ("usage limit reached", "hit your limit … resets …"). Historically the form was `Claude AI usage limit reached|<unix-epoch>`. The turn therefore stops instead of waiting for the reset. **Fix:** capture the real text in a fixture (§10). Add a Claude-specific classifier that returns `ahwCredits` and parses the reset time when one is present. Don't guess the wording in production code.

### Minor

- `RunCaptured` line 399 reads `Proc.ExitStatus`, which is the raw wait status on Unix. Use `ExitCode`, guarded by `ProcessWasSignalled` as `ProcessSession` documents.
- Lines 367–368 and 375–376: `If Count <= 0 Then Break` leaves the loop while the process may still be running, then reports success with partial output.
- `Root.Get('is_error', False)` treats a non-boolean value as "not an error" (probe: `"is_error":"yes"` parsed as success). Use `Root.Find('is_error') Is TJSONBoolean`.
- `RunCaptured` uses `TProcess`. On Windows, `TProcessUTF8` (as `SpawnDetached` uses) is needed for non-ASCII paths and arguments. The npm install of Claude Code on Windows is `claude.cmd`, which `TProcess` cannot run directly. The native installer's `claude.exe` is fine.
- `StartClaudeSignIn`: `poNewConsole` has no effect on Linux, so `claude auth login` runs with no terminal and its output goes to the IDE's stdout. If the browser doesn't open by itself, the user never sees the URL. Not tested here. Pass `--claudeai`, and after starting it, poll `auth status` so the settings page can report success.

---

## 5. Integration findings

| Location | Finding |
|----------|---------|
| `ProjectAssistantForm.pas:4566–4578`, `AssistantClaudeClient.pas:536–546` | Both work around a suspended thread (`If Suspended Then Start` before `WaitFor`). If the constructor started the thread itself (`Inherited Create(False)` last, as the skill requires), both workarounds and the separate `.Start` call in `LaunchStoredClaudeRun` go away. |
| `ProjectAssistantForm.pas:5049` | The recap filter `Turn.Model = FModelName` resets the recap when the user changes model, but not when the project changes. With native sessions this becomes a per-project session map (§8.2). |
| `ProjectAssistantForm.pas:5058` | `FContextUsed := Length(Prompt) Div 4` is a guess. Replace it with reported usage (B6). |
| `PollClaude` | Applies `Snapshot.Content` only when the run completes, because the snapshot is all-or-nothing. With streaming, `Content` grows and the existing `ApplyAssistantSnapshots` path renders it live with no other form changes. |
| Settings, Claude panel | Raw `OnClick` on Browse, Detect, Sign in and Check. The skill makes `TAction` in the form's `TActionList` the default for static buttons. The settings form currently has no `ActionList`; add one when this panel is reworked. |
| Settings, model | A free-text `TEdit`. A `TComboBox` (`csDropDown`) prefilled with the CLI aliases (`fable`, `opus`, `sonnet`, `haiku`) avoids typos and still accepts full model IDs. |
| Settings, effort | Codex rows already store `ReasoningEffort`. Claude Code 2.1.312 accepts `--effort low|medium|high|xhigh|max`, so the Claude panel can reuse the same field. |
| Edited files | When Claude edits files open in the source editor, Lazarus only notices on its next disk check. Collecting `Edit`/`Write` tool paths from the stream (§8.1) would let the form reload unmodified buffers and list the changed files, reusing `AssistantChangeSets` if it fits. |

---

## 6. Compliance with `free-pascal-engineer.md`

| # | Rule (skill section) | Location | Deviation | Correction |
|---|---|---|---|---|
| 1 | Unit structure: `Type`, `Const`, `Var`, then declarations | `AssistantClaudeClient.pas:18–67` | `Const` comes before `Type`, and a second `Type` block follows the routine declarations. | One `Type` block (records, method type, thread class), then `Const`, then the routines. |
| 2 | Interface `Uses` only for public declarations | line 16 | `SysUtils` isn't needed by the interface. `AssistantConnections` is needed only by `ApplyClaudeRuntime`, which production never calls. | Interface: `Classes`. Move `SysUtils` to implementation. Remove `ApplyClaudeRuntime` (the settings form already uses `ClaudeRuntimeFromBrowsedPath`), and the IDE dependency (A1) goes with it. |
| 3 | `///` comments on public declarations | lines 34–42, 62–66 | None present. | Add one line per routine, as `ProcessSession.pas` does. |
| 4 | Thread constructors call `Inherited Create` **last** | line 518 | `Inherited Create(True)` is the first statement. | Assign everything, then `Inherited Create(False)` last. Delete the suspended-thread workarounds (§5). |
| 5 | `On Error: Exception Do` in thread `Execute` | line 582 | Uses `E`. | Rename to `Error`. |
| 6 | Specific exception handlers where possible | lines 253, 338 | `On E: Exception` around `GetJSON` and `Proc.Execute`. `E` is unused at line 253. | `On EParserError Do` (covers `EJSONParser` and `EScannerError`). `On E: EProcess Do`. |
| 7 | Avoid repeated `Result := Result + …` in tight loops | lines 370, 377 | Pipe output is accumulated by string concatenation in a 4 kB loop. | `TMemoryStream` per pipe (§9.1). |
| 8 | `F` prefix only for property storage fields | lines 53–57 | `FLock`, `FExecutable`, `FSnapshot`, `FCancelled` etc. don't back properties. | Strictly: `Lock`, `Settings`, `Latest`, `CancelFlag`. **Note:** the rest of the package (for example `ProjectAssistantForm`) uses `F` for every private field. Decide once whether the skill or the package convention wins, rather than mixing them in one unit. |
| 9 | Clear names, no letter soup | lines 310, 408, 198 | `Proc`, `Args`, `Lower`. | `ClaudeProcess`, `Arguments` (or keep `Args`, which is established across the package), `Lowered` as in `AssistantRecovery`. Low priority. |
| 10 | Remove dead code / assign once | lines 31, 84, 280, 296, 326 | The `Cost` field is never read and assigned three times; `FillChar` on a read buffer is unnecessary. | Remove both. |
| 11 | Library code assigns `Result` on every path | `ProbeHelp`, `RunCaptured` | Compliant. | No change. |
| 12 | Tests compile in the runner | `Tests/AssistantClaudeClientTest.lpr` | Not in `TestNames`. Doesn't link standalone. | Register it. Removing `AssistantConnections` (row 2) makes it link headless without `Interfaces`. |

Compliant: mode block, PascalCase reserved words, two-space indentation, no tabs, no line over 150 characters, `Try…Finally` around locals, `Case` not used, `Assigned` checks, unit header comment with copyright, and size (604 lines, under the 1000-line preference). `ProjectAssistantForm.pas` (11 008 lines) has a size note. New Claude logic should go in `AssistantClaudeClient` or a new `AssistantClaudeStream` unit rather than growing the form.

---

## 7. Optimisations

1. **Drop the per-turn `--help` probe** (B7): about 130 ms and one process start saved per turn, plus a failure mode removed.
2. **Native sessions instead of recap** (B5): removes up to 24 kB of re-sent text per turn and lets Claude Code use its own prompt caching and auto-compaction. This is the largest saving of subscription allowance.
3. **Stream buffering**: `TMemoryStream` instead of quadratic string growth. For stream-json, split lines incrementally and keep only the parsed state.
4. **`ContainsToken`** copies the tail of the help text on every iteration (`Copy(Text, StartAt, MaxInt)`). It becomes unnecessary with the fixed mapping. If any token scan remains, use the FPC 3.3.1 `Pos(Substr, S, Offset)` overload.
5. **Cache the account pre-flight** per executable path for a few minutes, and invalidate it on any authentication error, so a burst of turns costs one `auth status` call.
6. **Optional persistent process** (§8.6): one long-lived `claude` per conversation with `--input-format stream-json` avoids starting Node for every turn and allows interrupting mid-turn without killing the process.

---

## 8. Capability enhancements (prioritised)

### 8.1 Stream-json output (do first)

Arguments: `-p --output-format stream-json --verbose` (`--verbose` is required with stream-json in print mode). Optionally add `--include-partial-messages` for token-level deltas.

Expected events (per Claude Code documentation; **confirm with a captured fixture**):

| Event | Use |
|-------|-----|
| `{"type":"system","subtype":"init", "session_id", "apiKeySource", "model", "permissionMode", "tools"}` | Billing backstop (§3.2). Session ID. Show the model actually used. |
| `{"type":"assistant","message":{"content":[{"type":"text"}, {"type":"tool_use","name","input"}]}}` | Live text in `Snapshot.Content`. Tool activity in the trace view. The tool count is the replay-safety signal (B2). File paths for editor reload (§5). |
| `{"type":"user","message":{"content":[{"type":"tool_result"}]}}` | Tool completion in the trace. |
| `{"type":"result","subtype","is_error","result","session_id","num_turns","duration_ms","usage"}` | Final answer, error classification (B8), usage (B6). |

```pascal
Type
  TClaudeStreamState = Record
    SessionId: String;
    KeySource: String;
    Text: String;
    ToolCalls: Integer;
    Finished: Boolean;
    IsError: Boolean;
    ResultSubtype: String;
    Turn: TClaudeTurnResult;
  End;

/// Folds one stream-json line into State. False when the line is not a JSON object.
Function ApplyClaudeStreamLine(Const Line: String; Var State: TClaudeStreamState): Boolean;
```

```pascal
Procedure ReadClaudeUsage(Event: TJSONObject; Var Turn: TClaudeTurnResult);
Var
  Usage: TJSONObject;
Begin
  If Not (Event.Find('usage') Is TJSONObject) Then
    Exit;
  Usage := TJSONObject(Event.Find('usage'));
  If Not (Usage.Find('input_tokens') Is TJSONNumber) Or Not (Usage.Find('output_tokens') Is TJSONNumber) Then
    Exit;
  Turn.UsageState := ClaudeUsageReported;
  { Cached prompt tokens are still context. Without them a resumed turn looks almost empty. }
  Turn.InputTokens := Usage.Get('input_tokens', Int64(0)) + Usage.Get('cache_read_input_tokens', Int64(0)) +
    Usage.Get('cache_creation_input_tokens', Int64(0));
  Turn.OutputTokens := Usage.Get('output_tokens', Int64(0));
End;

Function ApplyClaudeStreamLine(Const Line: String; Var State: TClaudeStreamState): Boolean;
Var
  Data: TJSONData;
  Event, MessageNode, Block: TJSONObject;
  Content: TJSONArray;
  EventType: String;
  I: Integer;
Begin
  Result := False;
  Data := Nil;
  Try
    Try
      Data := GetJSON(Line);
    Except
      On EParserError Do
        Exit;
    End;
    If Not (Data Is TJSONObject) Then
      Exit;
    Event := TJSONObject(Data);
    EventType := Event.Get('type', '');
    If Event.Find('session_id') Is TJSONString Then
      State.SessionId := Event.Get('session_id', '');
    If (EventType = 'system') And (Event.Get('subtype', '') = 'init') Then
      State.KeySource := Event.Get('apiKeySource', '')
    Else If (EventType = 'assistant') And (Event.Find('message') Is TJSONObject) Then
      Begin
        MessageNode := TJSONObject(Event.Find('message'));
        If MessageNode.Find('content') Is TJSONArray Then
          Begin
            Content := TJSONArray(MessageNode.Find('content'));
            For I := 0 To Content.Count - 1 Do
              If Content.Items[I] Is TJSONObject Then
                Begin
                  Block := TJSONObject(Content.Items[I]);
                  If Block.Get('type', '') = 'text' Then
                    State.Text := State.Text + Block.Get('text', '')
                  Else If Block.Get('type', '') = 'tool_use' Then
                    Inc(State.ToolCalls);
                End;
          End;
      End
    Else If EventType = 'result' Then
      Begin
        State.Finished := True;
        State.ResultSubtype := Event.Get('subtype', '');
        State.IsError := (Event.Find('is_error') Is TJSONBoolean) And Event.Get('is_error', False);
        ReadClaudeUsage(Event, State.Turn);
        If Event.Find('result') Is TJSONString Then
          State.Turn.Text := Event.Get('result', '');
      End;
    Result := True;
  Finally
    Data.Free;
  End;
End;
```

`TClaudeTurnResult.InputTokens` and `OutputTokens` become `Int64`. `TClaudeRunSnapshot` gains `ToolCalls`, `SessionId`, `InputTokens`, `OutputTokens` and `UsageState`. `Execute` updates the snapshot under the lock after each line, not only at the end. The result event's usage is a sum across all model calls in the turn, which is right for allowance accounting. For a "context used" figure, the last `assistant` message's usage is the better measure.

### 8.2 Native sessions

- First turn of a conversation: generate a UUID and pass `--session-id <uuid>`. Later turns: `--resume <uuid>`. Store the ID with the conversation, keyed by project root and connection. **New conversation** clears it.
- The CLI rejects braced GUIDs (verified), so strip the braces:

```pascal
/// A new lower-case UUID without braces, as --session-id requires. Empty on failure.
Function NewClaudeSessionId: String;
Var
  Identifier: TGUID;
Begin
  Result := '';
  If CreateGUID(Identifier) <> 0 Then
    Exit;
  Result := LowerCase(Copy(GUIDToString(Identifier), 2, 36));
End;
```

- Remove the recap from `StartClaudeReply`. Keep it only as a fallback when `--resume` reports an unknown session (for example, the user cleared Claude's history), then start a new ID.
- After this change `ClaudeKeepsSessionText` is accurate.
- `--fork-session` with `--resume` gives a cheap "branch from here" if the conversation surface ever offers one.

### 8.3 IDE context through the system prompt, used carefully

`--append-system-prompt` can carry stable project facts: Lazarus project, package list, build mode, the house style rule ("follow `Documents/free-pascal-engineer.md`"). **Caveat from `--help`:** `--system-prompt-snapshot` defaults to `on`, so the appended prompt is recorded on the first request and reused **verbatim** on every resume, even if later launches pass different text. Volatile context (active file, caret, selection, build errors) must therefore stay in the user message, as `BuildSubmitApiText` already does. Only facts that are stable for the whole session belong in the system prompt.

`--add-dir` can grant access to package source folders outside the project root (for example `Source/LazWorkflowCommon` when the project is a test program).

### 8.4 Per-mode tool policy

Map assistant modes to Claude Code policy instead of one approval setting:

| Mode | Suggested policy |
|------|------------------|
| Chat | `--permission-mode plan` (read-only research) |
| Document / Plan | `acceptEdits`, with `--allowedTools "Read Edit Write Glob Grep"` |
| Build | `acceptEdits`, plus `--allowedTools "Bash(lazbuild *)" "Bash(git status*)" "Bash(git diff*)"` |
| Always | `bypassPermissions`, behind a confirmation in settings |

`--disallowedTools "Bash(git push*)" "Bash(git commit*)"` keeps repository writes in the LazRepositoryTools package, which already owns them.

### 8.5 IDE-hosted approval prompts (larger)

`--permission-prompts host` routes approval requests to "the SDK host or `--permission-prompt-tool`". The tool flag isn't listed in 2.1.312 `--help`, so confirm it is supported first. With stream-json input and output, the IDE can answer each request with a modal dialog. That makes **Ask** mean "ask me" rather than "deny silently". It needs the bidirectional control protocol, so it is best done together with §8.6.

### 8.6 Persistent conversation process (optional)

`--input-format stream-json --output-format stream-json` keeps one `claude` process per conversation. Each user turn is one JSON line on stdin. This enables image input (content blocks instead of the current "Claude Code turns do not attach images" refusal; confirm the block shape on a fixture), interruption without killing the process, and IDE-hosted approvals (§8.5). The trade-off: the transport must be long-lived like `AssistantCodexTransport`. Reuse that unit's patterns (non-blocking pipes, `WritePipeNoSignal`, session teardown).

### 8.7 Lazarus tools over MCP (decision needed)

`--mcp-config` could expose the assistant's own Lazarus-aware tools (build, LFM validation, CodeTools rename, symbol search) to Claude. Commit `cd69058` deliberately keeps Claude off the private tool path, so this is listed for your decision rather than recommended. If adopted, use `--strict-mcp-config` so only the IDE's server is loaded, and a read-only tool subset to start with.

### 8.8 Smaller items

- `--fallback-model` (for example `sonnet`) when the chosen model is overloaded.
- `--effort` from the connection's `ReasoningEffort` (§5).
- `-n/--name "<Project> – <date>"` so sessions are recognisable in `claude --resume`.
- Optional git checkpoint before an agentic turn (the repository package already has the plumbing), giving one-click undo of a Claude turn.
- `--no-session-persistence` for throwaway calls such as commit-message drafting.

---

## 9. Revised process core

### 9.1 `RunCaptured`

This fixes B3, B4, the `ExitStatus` misuse and quadratic buffering, and passes the scrubbed environment. In the stream-json version, `DrainPipe` feeds a line splitter instead of a memory stream, but the process handling is the same.

```pascal
Procedure DrainPipe(Pipe: TInputPipeStream; Buffer: TStream);
Var
  Chunk: Array[0..4095] Of Byte;
  Count: Integer;
Begin
  While Pipe.NumBytesAvailable > 0 Do
    Begin
      Count := Pipe.Read(Chunk, SizeOf(Chunk));
      If Count <= 0 Then
        Exit;
      Buffer.WriteBuffer(Chunk, Count);
    End;
End;

Function StreamText(Buffer: TMemoryStream): String;
Begin
  SetString(Result, PAnsiChar(Buffer.Memory), Buffer.Size);
End;

Function RunCaptured(Const Executable, WorkingDirectory: String; Args, Environment: TStrings; Const InputText: String;
  TimeoutMs: Integer; Out StdoutText, StderrText: String; Out ExitCode: Integer; Out ErrorText: String;
  StopQuery: TClaudeStopQuery = Nil): Boolean;
Var
  ClaudeProcess: TProcess;
  StdoutBuffer, StderrBuffer: TMemoryStream;
  Started: QWord;
  Offset, Written: Integer;
  Closed, Again: Boolean;
  WriteError: String;
Begin
  Result := False;
  StdoutText := '';
  StderrText := '';
  ExitCode := -1;
  ErrorText := '';
  If Not FileIsExecutable(Executable) Then
    Begin
      ErrorText := 'Claude Code was not found. Browse to the installed executable.';
      Exit;
    End;
  StdoutBuffer := TMemoryStream.Create;
  StderrBuffer := TMemoryStream.Create;
  ClaudeProcess := TProcess.Create(Nil);
  Try
    ClaudeProcess.Executable := Executable;
    If WorkingDirectory <> '' Then
      ClaudeProcess.CurrentDirectory := WorkingDirectory;
    ClaudeProcess.Options := [poUsePipes, poNoConsole];
    If Assigned(Args) Then
      ClaudeProcess.Parameters.Assign(Args);
    If Assigned(Environment) Then
      ClaudeProcess.Environment.Assign(Environment);
    { Own process group, so a stop also ends the commands Claude Code started. }
    StartInOwnSession(ClaudeProcess);
    Try
      ClaudeProcess.Execute;
    Except
      On E: EProcess Do
        Begin
          ErrorText := 'Could not start Claude Code. ' + E.Message;
          Exit;
        End;
    End;
    Offset := 1;
    While Offset <= Length(InputText) Do
      Begin
        If Assigned(StopQuery) And StopQuery() Then
          Begin
            TerminateSession(ClaudeProcess);
            ErrorText := 'Cancelled.';
            Exit;
          End;
        { An early exit closes the pipe. Stop writing and read the reason from stderr. }
        If (Not WritePipeNoSignal(ClaudeProcess.Input.Handle, InputText[Offset], Length(InputText) - Offset + 1,
          Written, Closed, Again, WriteError)) Or Closed Or (Written <= 0) Then
          Break;
        Inc(Offset, Written);
      End;
    ClaudeProcess.CloseInput;
    Started := GetTickCount64;
    While ClaudeProcess.Running Or (ClaudeProcess.Output.NumBytesAvailable > 0) Or
      (ClaudeProcess.Stderr.NumBytesAvailable > 0) Do
      Begin
        DrainPipe(ClaudeProcess.Output, StdoutBuffer);
        DrainPipe(ClaudeProcess.Stderr, StderrBuffer);
        If Assigned(StopQuery) And StopQuery() Then
          Begin
            TerminateSession(ClaudeProcess);
            ErrorText := 'Cancelled.';
            Exit;
          End;
        If GetTickCount64 - Started >= QWord(TimeoutMs) Then
          Begin
            TerminateSession(ClaudeProcess);
            { Not a network timeout. Recovery must not replay a turn that may have changed files. }
            ErrorText := 'Claude Code did not finish within the turn limit.';
            Exit;
          End;
        If ClaudeProcess.Running And (ClaudeProcess.Output.NumBytesAvailable = 0) And
          (ClaudeProcess.Stderr.NumBytesAvailable = 0) Then
          Sleep(5);
      End;
    StdoutText := StreamText(StdoutBuffer);
    StderrText := StreamText(StderrBuffer);
    If ProcessWasSignalled(ClaudeProcess) Then
      Begin
        ErrorText := 'Claude Code was stopped by a signal.';
        Exit;
      End;
    ExitCode := ClaudeProcess.ExitCode;
    Result := True;
  Finally
    ClaudeProcess.Free;
    StderrBuffer.Free;
    StdoutBuffer.Free;
  End;
End;
```

Implementation `Uses` gains `Pipes` (for `TInputPipeStream`). `ProcessSession` is already listed. Check that `Again` is handled if the input pipe is ever made non-blocking; here it is blocking, so `Again` stays false. Keep the error wording that `ProcessTransportDropped` relies on ("Could not start Claude Code") or update that classifier in the same commit.

### 9.2 Thread class (skill-compliant shape)

```pascal
Type
  TClaudeTurnSettings = Record
    Executable: String;
    Model: String;
    PermissionMode: String;
    Effort: String;
    SessionId: String;
    Resume: Boolean;
    WorkingDirectory: String;
    TimeoutMs: Integer;
  End;

  TClaudeRunSnapshot = Record
    Content, ErrorText, SessionId: String;
    ToolCalls: Integer;
    UsageState: String;
    InputTokens, OutputTokens: Int64;
    Done: Boolean;
  End;

  /// Worker for one Claude Code turn. The IDE timer reads Snapshot. Cancel stops the process group.
  TAssistantClaudeRun = Class(TThread)
  Private
    Lock: TRTLCriticalSection;
    Settings: TClaudeTurnSettings;
    Prompt: String;
    Latest: TClaudeRunSnapshot;
    CancelFlag: LongInt;
    Function IsCancelled: Boolean;
  Protected
    Procedure Execute; Override;
  Public
    /// Starts at once. The caller owns the thread and frees it off the IDE thread.
    Constructor Create(Const TurnSettings: TClaudeTurnSettings; Const TurnPrompt: String);
    Destructor Destroy; Override;
    Procedure Cancel;
    Function Snapshot: TClaudeRunSnapshot;
  End;
```

```pascal
Constructor TAssistantClaudeRun.Create(Const TurnSettings: TClaudeTurnSettings; Const TurnPrompt: String);
Begin
  InitCriticalSection(Lock);
  Settings := TurnSettings;
  If Settings.TimeoutMs < 1 Then
    Settings.TimeoutMs := ClaudeTurnTimeoutMs;
  Prompt := TurnPrompt;
  Latest := Default(TClaudeRunSnapshot);
  CancelFlag := 0;
  FreeOnTerminate := False;
  { Last: this starts the thread. }
  Inherited Create(False);
End;

Destructor TAssistantClaudeRun.Destroy;
Begin
  Cancel;
  WaitFor;
  DoneCriticalSection(Lock);
  Inherited Destroy;
End;

Procedure TAssistantClaudeRun.Execute;
Var
  ErrorText: String;
Begin
  ErrorText := '';
  Try
    If Not RunClaudeTurn(Settings, Prompt, @IsCancelled, @Publish, ErrorText) And (ErrorText = '') Then
      ErrorText := 'Claude Code did not complete the turn.';
  Except
    On Error: Exception Do
      If IsCancelled Then
        ErrorText := 'Cancelled.'
      Else If Error.Message <> '' Then
        ErrorText := Error.Message
      Else
        ErrorText := Error.ClassName;
  End;
  EnterCriticalSection(Lock);
  Try
    Latest.ErrorText := ErrorText;
    Latest.Done := True;
  Finally
    LeaveCriticalSection(Lock);
  End;
End;
```

`Publish` is a private method that copies the current `TClaudeStreamState` into `Latest` under `Lock` after each stream line. `Snapshot` returns a copy under the same lock, unchanged from today. Note the field naming row in §6 (#8) before adopting this shape.

---

## 10. Suggested implementation order

Each step compiles and runs tests on its own, following the skill's commit discipline.

1. **Fixtures.** Run one real turn of each kind by hand and save the stream-json output under `Tests/Fixtures/Claude/`: plain answer, tool-using turn, `--resume` turn, an `error_max_turns` result, the usage-limit message if one can be captured, and `auth status` for subscription and API-key cases (emails redacted). Every later parser test uses these files.
2. **`Claude: keep turns on the subscription`.** Environment scrub, `auth status` pre-flight, `--claudeai` on sign-in, settings Check shows the plan. Tests: an environment built from an `ANTHROPIC_API_KEY` fixture omits the key; `ClaudeAccountIsSubscription` is false for the `api_key` fixture and true for `claude.ai`.
3. **`Claude: stop replaying turns that may have changed files`.** Timeout wording and classification, attempt cap, B1 refused-flag scope, fixed permission mapping, help probe removed. Tests in `AssistantRecoveryTest`.
4. **`Claude: run the process in its own group`.** `StartInOwnSession`, `TerminateSession`, `WritePipeNoSignal`, `ExitCode`, stream buffers. Test with a fixture script that ignores stdin and exits 2 after printing an argument error, and one that spawns `sleep 600` and must be gone after Cancel.
5. **`Claude: drop the IDE dependency from the client unit`** and register `AssistantClaudeClientTest` in `RunAssistantTests.pas`. Fix the style rows in §6 here.
6. **`Claude: stream turns and report usage`** (§8.1), with snapshot fields and usage in the footer and settings.
7. **`Claude: resume the Claude Code session`** (§8.2). Remove the recap.
8. Enhancements §8.3–8.8 as separate, optional commits.

---

## 11. Decisions (answered 28 October 2026)

| # | Question | Decision |
|---|----------|----------|
| 1 | Field prefix | **The skill wins.** `F` is used only for the private field behind a `Property`. The §9.2 shape (`Lock`, `Settings`, `Latest`, `CancelFlag`) applies to the Claude unit. |
| 2 | Ask mode | **No silent denial.** Approvals are shown as IDE dialogs. |
| 3 | Lazarus tools | **Yes.** Claude gets the IDE's own tools. This reverses `cd69058`. |
| 4 | Subscription check | **Check once, then trust.** Confirm the connection is on the subscription when it is first used, and revisit if Claude Code starts drifting to API billing. |
| 5 | Root `free-pascal-engineer.md` | Explained separately. It is the August copy, identical to `~/Projects/` and the Grok skill folder. Not yet decided. |

The sections below replace the earlier recommendations wherever they disagree.

### 11.1 Decision 1: the `F` prefix

- Apply the rule to everything new or rewritten in `AssistantClaudeClient` (and any new `AssistantClaudeStream` / `AssistantClaudeMcp` units).
- **Open scope question:** the rest of the package (for example `ProjectAssistantForm`, about 150 `F` fields in the form class alone) still uses the old convention. Renaming those is a large mechanical change that touches nearly every unit. I suggest one separate commit per unit, done later, rather than mixed into the Claude work. The integration code added to `ProjectAssistantForm` for Claude would then match its surroundings (`F…`) until that unit is migrated. Tell me if you would rather the new form code follow the skill immediately.

### 11.2 Decisions 2 and 3 together: one Lazarus MCP server

Both decisions can be met with one mechanism that the package mostly has already.

`TAssistantToolBroker` (`AssistantToolBroker.pas`) already:

- is "backend-neutral" and runs on the IDE thread;
- publishes its tools as JSON (`ToolsJson`) and runs them (`Execute(RunId, Tool, Arguments)`);
- works on **IDE buffers**, not files on disk (`ReadBuffer`, `ReplaceBuffer`, `SaveBuffer`, change sets);
- covers build, tests, git, CodeTools (declaration, references, rename preview) and file creation, each behind a capability check and a write scope (`awsReadOnly`, `awsMarkdown`, `awsProject`);
- has an approval hook, `TAssistantToolApproval(Tool, Path, OldText, NewText)`, which the Codex path already uses to show a diff and ask.

**Recommended design:** expose the broker to Claude Code as an MCP server, and remove Claude's own write and command tools so that every change goes through the broker:

```text
claude -p --output-format stream-json --verbose
       --mcp-config <lazarus server>  --strict-mcp-config
       --tools "Read,Grep,Glob"                      (read-only built-ins)
       --allowedTools "mcp__lazarus__*"
       --permission-mode manual
```

With this design:

- **Ask mode becomes real dialogs, using the existing broker approval path.** No undocumented Claude Code permission protocol is needed for write tools, because Claude has no write tools of its own. Read-only built-ins need no approval.
- **Edits go into the open editor buffers**, so the "file changed on disk" problem in §5 doesn't arise, and the change sets and undo already work.
- **Build, tests and git** use the broker's guarded operations (`StartBuild`, `StartTests`, `RunGit`) instead of an unrestricted `Bash`. That also covers B4 in practice: no Claude-spawned shell commands are left to orphan.
- **Auto / Always** map to the broker's existing approval settings instead of Claude Code's permission modes.
- Claude and Codex share one tool implementation. A fix to a tool fixes both.

**Transport.** Claude Code starts stdio MCP servers itself, so the IDE cannot be one directly. There are two options:

| Option | How it works | Trade-off |
|--------|--------------|-----------|
| A. HTTP MCP inside the IDE (**recommended**) | An `fphttpserver` listener on `127.0.0.1` with a random port, and a per-run bearer token in the `--mcp-config` JSON (`"type":"http"`). Requests are queued to the IDE thread, run by the broker, and answered when done. | No extra executable. It needs a small JSON-RPC layer for MCP (`initialize`, `tools/list`, `tools/call`). |
| B. Stdio relay | A tiny helper program that Claude starts. It forwards MCP over a local socket to the IDE. | Easier to reason about protocol-wise, but adds an executable to build, find and ship on three platforms. |

Security for option A: bind to loopback only, use a new token for each run, refuse requests without it, and stop the listener when the run ends. Put the token in a temporary `--mcp-config` file with mode `0600` rather than on the command line, where `ps` would show it.

**Still to verify before building:**

1. That Claude Code 2.1.312 accepts `--tools "Read,Grep,Glob"` together with MCP tools, and that `mcp__lazarus__*` matches in `--allowedTools`. This can be checked with a stub server and one cheap turn.
2. How long Claude Code waits for an MCP tool call. An approval dialog may stay open for minutes. If its timeout is short, the broker should return "awaiting approval" and let Claude poll, or the timeout should be raised through the MCP config (`MCP_TOOL_TIMEOUT` is the documented environment variable; confirm it).
3. Whether to keep `WebFetch` / `WebSearch` available. They're read-only, but they reach the network. I suggest offering them behind a setting.

**Fallback if you want Claude's built-in Edit/Bash kept:** approvals for those need the stream-json control protocol (`can_use_tool` requests answered by the host), which means the long-lived process in §8.6. This works, but it is a second approval path to maintain next to the broker's. I don't recommend it as the first step.

This replaces §8.5 and §8.7. §8.6 (persistent process) becomes optional again: the MCP design works with one process per turn plus `--resume`.

### 11.3 Decision 4: check once, then trust

- **Keep the environment scrub (§3.2, guard 1).** It isn't a check; it removes a cause, and it costs nothing at run time. Without it, a stray `ANTHROPIC_API_KEY` bills from the very first turn, and a check done once would just report that.
- **Pre-flight `auth status` once per connection per IDE session**, on first use and again after the connection settings are saved or a sign-in completes. The result is held in memory only.
- **In-stream `apiKeySource`:** log it, but don't block on it. The first value is already parsed with each turn, so a log line costs nothing and gives you the evidence you'd need if you revisit this decision. Promote it to a hard stop later if it ever shows anything other than `none`.

### 11.4 Revised implementation order

Replaces §10 from step 2 onward. Step 1 (fixtures) is unchanged.

2. **`Claude: keep turns on the subscription`.** Environment scrub, a one-time `auth status` check per connection, `--claudeai` on sign-in, and the settings Check button shows the plan.
3. **`Claude: stop replaying turns that may have changed files`.** As before.
4. **`Claude: run the process in its own group`.** As before.
5. **`Claude: drop the IDE dependency from the client unit`.** Register the test and apply the §6 style fixes, including the decision-1 field names.
6. **`Claude: stream turns and report usage`** (§8.1).
7. **`Claude: resume the Claude Code session`** (§8.2).
8. **`Assistant: serve the tool broker over MCP`.** HTTP listener, token, `initialize` / `tools/list` / `tools/call`, IDE-thread dispatch. Tests use a scripted HTTP client and need no Claude.
9. **`Claude: use the Lazarus tools and IDE approvals`.** `--mcp-config`, read-only built-ins, the approval mode wired to the broker. Run the verification items in §11.2 first.
10. Optional extras from §8.3, §8.4 and §8.8.

---

## 12. Implementation progress (28 October 2026, branch `claude-connector`)

| Commit | Step | Summary |
|--------|------|---------|
| `8ecee46` | 1, 5 (part) | Captured Claude Code 2.1.312 fixtures; removed the IDE dependency from the client; registered `AssistantClaudeClientTest` in the runner. |
| `c0f32a2` | 2 | Subscription guard: environment scrub, one-time `auth status` check per executable per IDE session, `--claudeai` sign-in, settings Check shows the plan. |
| `138518b` | 3 | No replay after the process starts; fixed permission mapping; refused-flag test reads stderr only. |
| `0213872` | 4 | Prompt given as an owner-only file on FPC 3.3.1; process-group stop on Cancel and the turn limit. |
| `0e280eb` | 6, 5 | Stream-json, live text, usage including cache, subscription windows in the footer, new `AssistantClaudeStream` unit, skill-compliant thread. |
| `7fdef5d` | 7 | Native sessions (`--session-id`, then `--resume`), recap only for new sessions, lost-session fallback. |
| `5aeb5f7` | extra | Model list and effort levels from Claude Code's initialize control request, cached on the connection. |

**New defect found while implementing (fixed in `0213872`):** with FPC 3.3.1, `TProcess.Input` creates a stream that owns the pipe, after which `CloseInput` closes nothing. The prototype wrote the prompt through `Input`, so `claude -p` never saw the end of its input, and every real turn would have waited for the ten-minute limit. A test with a fake `claude` reproduces this against the old unit.

**Verified against the real program:** a dummy `ANTHROPIC_API_KEY` in the IDE environment no longer reaches Claude Code; a turn streams text before and after a tool call; usage, context and the five-hour and seven-day windows are reported; a code word given in one turn is answered in the resumed next turn.

**Test results:** `AssistantClaudeClientTest` has 88 checks, all passing. Recovery, account-usage, reconnect and provider tests pass, and the package builds. `AssistantSettingsTest` fails at its Codex check "missing saved executable recovered without changing connection identity", exactly as on the baseline before any change. It halts at that point, so its later Claude panel checks don't run. `AssistantUsageTest` isn't registered in the runner (pre-existing); its uses list was updated but it hasn't been run.

### 12.1 Verification for steps 8–9 (stub MCP server, real Claude Code)

| Question (§11.2) | Result |
|---|---|
| `--tools "Read,Grep,Glob"` with MCP tools | Tool list is exactly `Glob, Grep, Read, mcp__lazarus__echo, mcp__lazarus__wait`. Asked to create a file, Claude reports it has no tool that can. |
| `--allowedTools "mcp__lazarus__*"` | The MCP tool ran in the default permission mode without a prompt or a denial. |
| Bearer token in `--mcp-config` headers | Sent on every request (`server/discover`, `initialize`, `notifications/initialized`, `tools/list`, `tools/call`). An unknown `server/discover` answered with JSON-RPC "no method" is tolerated. |
| Tool-call timeout | About **60 s** by default ("The operation timed out"). With `MCP_TOOL_TIMEOUT=600000` in Claude Code's environment, a 90 s call completed normally. |
| Server concurrency | A blocked single-threaded server stopped the next session from connecting ("server is still connecting"). The IDE's listener must keep serving while an approval dialog is open. |

Design consequences for step 8: set `MCP_TOOL_TIMEOUT` (for example 30 minutes) in the scrubbed environment; serve each HTTP request on its own thread and queue only the broker call to the IDE thread; answer `server/discover` and other unknown methods with JSON-RPC error -32601.
