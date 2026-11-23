# LazWorkflow: LLM Integration Review

Review of the Grok, ChatGPT and Claude integrations in `LazAssistantTools`, written so it can be turned into an implementation plan.

- **Source reviewed:** `github.com/PaulMichell/LazWorkflow`, branch `main`, commit `53a41c02` (23 Nov 2026, "Widen the assistant side bar further.").
- **Not reviewed:** the `claude-connector` branch and the documents named in `CLAUDE.md` (`Plan-ClaudeConnector.md`, `ClaudeConnectorReview.md`) are not on the public remote. Recheck any finding that the branch may already have changed.
- **Method:** I read the code statically. Nothing was built or run. Line numbers refer to the commit above.

---

## 1. Summary

LazWorkflow does not have one LLM integration with three providers. It has **three separate integration stacks**, and the only place they meet is `ProjectAssistantForm.pas` (11,811 lines):

| Stack | Connections | Turn engine | Tool catalogue | Tool executor |
|---|---|---|---|---|
| **Native** | Grok (xAI), OpenAI-compatible (OpenRouter) | `TAssistantActor` + `TAssistantService` (HTTP/SSE) | `AssistantTools.pas`: OpenAI `function` JSON | `ExecuteAssistantToolForMode` |
| **Codex** | ChatGPT | `TAssistantCodexRun` → `codex app-server` (JSON-RPC over stdio) | The native catalogue, converted to `dynamicTools` | `ExecuteAssistantToolForMode`, always on the IDE thread |
| **Claude** | Claude | `TAssistantClaudeRun` → `claude -p` (stream-json) | `TAssistantToolBroker`: `lazarus_*` names, MCP `inputSchema` | `TAssistantToolBroker` + `TAssistantIDEWorkspace` over the loopback MCP server |

Many differences you have seen between the models come from these harness differences, not from the models. The most significant ones:

1. **Claude turns do not get the harness system prompt.** That prompt carries the work policy, the mode overlay, skills, and the `AGENTS.md` project rules. Grok gets it as its system prompt and Codex as `developerInstructions`. Claude gets only `ClaudeReadImageNote` (§3.4).
2. **There are two tool catalogues with different names, schemas and semantics.** Grok and Codex use `write_file` / `replace_in_file` / `run_compile`. Claude uses revision-token buffer edits and async build jobs (`lazarus_replace_buffer`, `lazarus_start_build` / `lazarus_build_status`) (§3.2).
3. **Phone approval works only for Grok and OpenAI-compatible connections.** Codex and Claude call the approval gate with an empty tool id, which skips the remote waiter (§3.6).
4. **"Unsupported" is handled differently in each place.** A tool can be offered and then fail (`spawn_subagent` for Codex). A UI action can silently put the text back in the composer (Claude steer from the desktop). A remote action can return an ad hoc error (Claude steer from the phone). Capability checks are scattered string tests such as `Backend = 'grok'` (§3.8).

The house style (`free-pascal-engineer.md`, "Architecture") already prescribes the fix: *interchangeable backends each in their own unit, coupled only to a shared abstract base unit, self-registering in `Initialization`; adding a backend touches zero existing code.* The integration layer currently breaks that rule in roughly 130 places. The target architecture in §4 applies the rule.

---

## 2. Current architecture

```
                         ProjectAssistantForm (11.8k lines)
      FUseCodex / FUseClaude flags, ~80 branches, per-backend fields, Start*/Poll*/Launch* methods
                 │                          │                               │
        SubmitUserTextEx            StartCodexReply                 StartClaudeReply
                 │                          │                               │
        TAssistantService            TAssistantCodexRun              TAssistantClaudeRun
         + TAssistantActor            + CodexClient/Transport          + ClaudeStream/Input
         + Sampler/Protocol           + Handshake/Schema/Wire           │
         + XaiProvider/GrokOAuth      + Qualification/Profile          TMCPListener ─ TMCPBrokerBridge
         + CompatibleClient                 │                               │
                 │                          │                        TAssistantToolBroker
     ExecuteAssistantToolForMode  ◄─────────┘                        + TAssistantIDEWorkspace
         (AssistantTools, 4.9k)  ◄───────────────────────────────── (calls back into native for
                                                                     write_markdown, run_command…)
```

Approximate size of each integration area (lines of Pascal):

| Area | Units | Lines |
|---|---|---|
| Native loop | Service, Actor, Sampler, Protocol, Subagents | 6,222 |
| xAI / OpenAI-compatible providers | XaiProvider, GrokOAuth, CompatibleClient | 2,167 |
| Native tools | AssistantTools | 4,929 |
| Codex | 13 `AssistantCodex*` units (+ `.lfm`) | 5,053 |
| Claude | ClaudeClient, ClaudeStream, ClaudeInput | 1,790 |
| MCP | MCPBridge, MCPListener, MCPProtocol | 1,480 |
| Broker | ToolBroker, IDEWorkspace, ChangeSets | 3,945 |
| Account usage | AccountUsage, AccountWorker, Usage | 2,235 |
| Backend branches inside the form | Start/Poll/Launch/Release/Steer/Approve… | ≈1,500 |
| **Total integration-related** | | **≈29,300 of 74,348 in the package** |

---

## 3. Findings

Each finding gives the evidence, its effect, and the objective(s) it bears on: O1 shared code, O2 standard tools and data, O3 easy new models, O4 stable API, O5 size, O6 missing capabilities.

### 3.1 Three turn engines with no common contract (O1, O3, O4)

- `IAssistantModelProvider` (`AssistantModelProvider.pas`) is the only provider abstraction. It covers sign-in, model listing and `CompleteOnce`. Its own header says "Managed agent runtimes own a separate loop", so Codex and Claude sit entirely outside it.
- The form holds a separate set of state for each backend: `FCodexRuntime, FCodexModel, FCodexProfile, …`, `FClaudeRuntime, FClaudeModel, FClaudeSessionId, …`, `FCodexRun`, `FClaudeRun`, `FPollingCodex`, `FPollingClaude` (lines 188–247).
- Every backend needs its own Start, Launch, Poll, Release and snapshot handling: `StartCodexReply` (118 lines), `PollCodex` (98), `StartClaudeReply` (87), `PollClaude` (96), `LaunchStoredCodexRun`, `LaunchStoredClaudeRun`, `ApplyClaudeToolSteps`, and others.
- There are three snapshot types: the stream callback (`TAssistantStreamEvent`), `TCodexRunSnapshot` and `TClaudeRunSnapshot`. They overlap but are not the same.

**Effect:** behaviour such as phases, retries, usage recording and plan-run completion is written three times, so fixes made on one path do not reach the others. A fourth backend means a fourth set of form fields and methods.

### 3.2 Two tool catalogues, two executors, one hybrid (O1, O2)

| Concern | Native (Grok, OpenAI-compatible, *and Codex*) | Broker (Claude) |
|---|---|---|
| Definition | Hand-built JSON strings in 9 `Build*ToolsJson` functions (≈344 lines) | One hand-built JSON string in `ToolsJsonForScope` (≈200 lines) |
| Format | `{"type":"function","function":{…,"parameters":…}}` | `{"name":…,"inputSchema":…}` |
| Names | `read_file`, `write_file`, `replace_in_file`, `run_compile`, `run_tests`, `get_project_info`, `spawn_subagent`, `read_skill`, `write_image`, `grep` | `lazarus_read_buffer`, `lazarus_replace_buffer`, `lazarus_replace_in_buffer`, `lazarus_prepare_changes` / `apply_changes` / `revert_changes`, `lazarus_start_build` / `build_status`, `lazarus_start_tests` / `test_status`, `lazarus_command_status`, `lazarus_project_info` |
| Edit model | Direct write or replace | Revision token from read, then edit, with a stale revision refused |
| Long jobs | Synchronous (`run_compile`) | Start + poll |
| Mode gate | `ToolAllowedInMode` + catalogue per `TAssistantMode` | `TAssistantWriteScope` per run |
| Approval | `ApproveToolIfNeeded` inside the executor | `TAssistantToolBroker.Approve` → `OnApproval` (10 call sites) |
| Thread | Actor thread unless `ToolNeedsIdeThread` | Always the IDE thread, through the bridge queue |

- Codex is a hybrid. `StartCodexReply` opens a broker run (line 5131), but it advertises the **native** catalogue (`BuildAssistantToolsJsonForMode`, line 5197) and executes through `ExecuteAssistantToolForMode` (`AssistantCodexRun.pas:246`). The broker run for Codex only supplies a run id and scope bookkeeping.
- The broker partly calls back into native code. `TAssistantIDEWorkspace.WriteMarkdown` calls `ExecuteAssistantToolForMode(…, SkipApproval=True)`, and comments such as "run_command, with Grok's checks" and "Grok's run_project, open_file and open_markdown" show the broker re-implementing the native tools one by one.

**Effect:** the same request produces different tool behaviour per model, and every new IDE capability has to be written twice and described twice. On the safety side, the broker's revision-token edit model is the stronger design: it detects a stale editor buffer. Only Claude benefits from it.

### 3.3 Mode → permission mapping is duplicated (O1, O4)

The same five-way mapping appears in four places:

- `StartCodexReply`, lines 5131–5135 (`Case ActiveMode Of amChat: BeginRun(awsNone…)`)
- `LaunchStoredCodexRun`, lines 4952–4957 (a copy of the above)
- `ClaudeToolScopeForMode` (form, line 4849) → `TClaudeToolScope`
- `ClaudeBrokerWriteScope` (`AssistantMCPBridge`) → `TAssistantWriteScope`

The native path expresses the same policy a third way, through the per-mode catalogue composition in `BuildAssistantToolsJsonForSession` and `ToolAllowedInMode`. `TClaudeToolScope` is a fourth enum for a concept that `TAssistantWriteScope` already covers.

### 3.4 System prompt assembly is not shared (O1, O6)

| Part | Grok / OpenAI-compatible | Codex | Claude |
|---|---|---|---|
| `TAssistantHarness.BuildSystemPrompt` (policy, tool calling, IDE fusion, formatting, mode overlay) | ✔ system prompt | ✔ `developerInstructions` | ✘ |
| Skills section + `read_skill` | ✔ | ✔ | ✘ |
| `AGENTS.md` project rules | ✔ | ✔ | ✘ (Claude Code reads `CLAUDE.md` itself, not `AGENTS.md`) |
| Plan/Document directive (`BuildSubmitApiText`) | user text | user text | user text |
| IDE context block | full, then light after 8 messages | full, then light | **always full**: Claude turns are not added to `AssistantClient`, so `MessageCount >= 8` never holds |
| Backend-specific note | — | — | `ClaudeReadImageNote` via `--append-system-prompt` |

**Effect:** Claude runs without the work policy, completion rules and mode essay that the other two receive. Some of what looks like Claude behaving differently is probably this. The IDE context row adds a cost difference: Claude's prompts grow with every turn.

### 3.5 Three conversation-continuity models (O1, O4, O6)

| | Grok / OpenAI-compatible | Codex | Claude |
|---|---|---|---|
| History | Full message array in `TAssistantService`, with trimming (`TrimMessagesForBudget`) and compaction | **Ephemeral thread** (`"ephemeral":true`) plus a text recap of up to 24,000 characters built in the form | Claude Code session (`--session-id` / `--resume`); text recap only when a new session starts |
| Recap code | — | Inline in `StartCodexReply` (≈30 lines) | `ClaudeRecapPrompt`, an almost identical loop |
| Prior images | Kept in history | Re-attached from stored turns | Not re-sent (the session holds them) |
| Compaction | ✔ (`CanCompactContext`) | ✘ | ✘ |

The two recap loops are copies of each other. The choice of strategy belongs to the backend, but the recap builder, the size limits and the image re-attachment rules can be shared.

### 3.6 Approvals and remote control diverge (O1, O6)

- `ApproveToolIfNeeded` consults the phone waiter only when `ToolId <> ''`. Codex (`AssistantCodexRun.pas:246`) and Claude (`ApproveClaudeTool`, line 4844) both pass `''`, so **the phone cannot approve Codex or Claude tool calls**. The comment at `AssistantCodexRun.pas:244` ("Codex does not call the remote waiter") records this.
- The two sides show different approval text. Native shows the first 240 characters of the arguments JSON. The broker shows `MCPApprovalSummary` (path, line range, start of the new text).
- `aamAuto` and `aamAlways` behave the same (`AssistantTools.pas:370–373`). Either the distinction is unfinished or one of them should go.
- Codex-native approval requests (`item/commandExecution/requestApproval`, …) are declined automatically in `CodexNativeApprovalReply`. That is correct, but it is a policy written in a wire unit.

### 3.7 Capability matrix: harness rather than model (O6)

Status of each capability in the **harness**, not what the model can do:

| Capability | Grok | OpenAI-compatible | ChatGPT (Codex) | Claude |
|---|---|---|---|---|
| Harness system prompt | ✔ | ✔ | ✔ | ✘ harness |
| Skills | ✔ | ✔ | ✔ | ✘ harness |
| Subagents | ✔ | ✔ | ⚠ **offered, then fails**: "spawn_subagent must run on the parent session actor" | ✘ harness (Claude Code's own agent tool is excluded by `--tools=Read,Grep,Glob`) |
| `todo_write` | ✔ Plan/Build | ✔ | ✔ | ✔ (added 23 Nov via broker) |
| Image input | ✔ model-gated | depends on model | ✔ `localImage` | ✔ stream-json |
| Image output (`write_image`) | ✔ per profile | ✔ per profile | ✘ (no endpoint) | ✘ (no endpoint) |
| Web search | ✔ `SearchMode` | not verified | ✘ harness | ✘ harness (excluded by `--tools`) |
| Steer mid-turn | ✔ text + images | ✔ | ✔ (images on one path only) | ✘: the desktop silently puts the text back in the composer, the phone gets "This connection cannot steer." |
| Phone approval | ✔ | ✔ | ✘ harness | ✘ harness |
| Context compaction | ✔ | ✔ | ✘ | ✘ |
| Events JSONL (trace replay) | ✔ | ✔ | ✘ harness | ✘ harness |
| Buffer edits with revisions | ✘ | ✘ | ✘ | ✔ |
| Async build/test jobs | ✘ | ✘ | ✘ | ✔ |
| Live account usage | ✔ registry | ✔ registry | ✔ registry | ✔ registry |

Most ✘ entries can be fixed in the harness. Only image output is a real provider limit.

### 3.8 Capabilities are expressed as ad hoc predicates (O3, O6)

- 128 string-literal backend checks (`'grok'`, `'claude'`, `'codex'`, `'openai-compatible'`) across 12 units. Most are in `AssistantSettingsForm` (49) and `ProjectAssistantForm` (29).
- Capability tests are scattered free functions: `TAssistantConnection.CanCompactContext` (`Backend = 'grok' Or …`), `AssistantBackendCanDraw`, `XaiModelImageInput`, `ImagesAttachAllowed`, the inline `FUseClaude` checks in `SteerQueuedText` and `RemoteSteer`.
- `TAssistantConnection` is a flat union of every backend's fields (`SearchMode` only for Grok, `Runtime` only for the CLIs, `KeyEnv` / `WireApi` only for compatible connections). Every backend therefore shares one load/save path and one settings form.

### 3.9 Events, trace and usage are three pipelines (O1, O2)

- Only the native actor emits `TAssistantEvent` and writes the events JSONL. `RecordCurrentTurn` sets `Turn.EventsFile` only when `(Not FUseCodex) And (Not FUseClaude)` (line 4553). For the other two, history replay and the monitor see less.
- Codex and Claude rebuild trace blocks inside the form (`PollCodex`, `ApplyClaudeToolSteps`, `ClaudeStepWritesPlan`) from their own snapshot shapes.
- Usage arrives in three shapes: `NoteReportedUsage`, `TCodexContextUsage`, and the `FClaude*Tokens` fields. `AssistantAccountUsage` is the exception: it already has a **registry** (`RegisterAccountUsageQuery(BackendId, …)`), and that is the pattern the rest of the integration should follow.

### 3.10 Naming and structural debt (O4, O5)

- `FCodexBroker` / `FCodexWorkspace` are the shared broker and workspace that **Claude** uses. The names are wrong for what they hold.
- Broker comments describe behaviour in terms of another backend ("Grok offers todo_write in Plan and Build only", "Grok's checks").
- `ProjectAssistantForm.pas` (11.8k), `AssistantTools.pas` (4.9k), `AssistantService.pas`, `AssistantActor.pas`, `AssistantToolBroker.pas` and `AssistantSettingsForm.pas` (each over 2k) all exceed the house 1,000-line preference by a wide margin.
- Codex alone is 13 units and 5k lines. The qualification, schema and diagnostics units (≈900 lines) guard against app-server contract drift. That is worth keeping, but it belongs in a backend-private sub-folder.

### 3.11 Defects found along the way

| # | Defect | Location |
|---|---|---|
| D1 | Codex is offered `spawn_subagent`, but the executor refuses it | `BuildAssistantToolsJsonForMode` → `ForSession(Mode, True, True)`; `AssistantTools.pas` end of dispatcher |
| D2 | Claude turns always carry the full IDE context block | `BuildSubmitApiText` relies on `AssistantClient.MessageCount` |
| D3 | Phone approval unavailable for Codex and Claude | `ToolId = ''` at both call sites |
| D4 | Claude steer from the desktop fails silently | `SteerQueuedText` |
| D5 | `aamAuto` = `aamAlways` | `ApproveToolIfNeeded` |
| D6 | The Codex launch path and the relaunch path repeat the mode→scope `Case` | lines 4952 and 5131 |

---

## 4. Target architecture

### 4.1 Layers (following `free-pascal-engineer.md`)

```
Foundation   AssistantAgentTypes       messages, tool specs, tool calls/results, events, usage, capabilities (records + functions)
             AssistantToolSpecs        declarative tool table (name, schema, scope, flags) — data, no IDE
             AssistantToolWire         spec ⇄ OpenAI function / Responses / Codex dynamicTools / MCP inputSchema
             AssistantPromptParts      harness prompt sections as pure functions

Services     AssistantToolService      ONE executor (today's broker + native tool bodies), scope, approval, IDE thread marshalling
             AssistantSession          conversation, continuity strategy, recap builder, events JSONL, usage log
             AssistantBackendRegistry  abstract IAssistantBackend + registration

Backends     AssistantBackendXai       (wraps Actor/Sampler/Protocol — shared with Compatible)
             AssistantBackendCompatible
             AssistantBackendCodex     (+ private Codex* units)
             AssistantBackendClaude    (+ private Claude* units)

Bridges      AssistantMCPBridge        ToolService ⇄ MCP listener (Claude, and any future MCP-speaking CLI)
             AssistantCodexToolBridge  ToolService ⇄ Codex dynamicTools

Application  ProjectAssistantForm      talks only to IAssistantBackend / ITurn / TAssistantTurnSnapshot
             Settings frames           registered per backend
```

The deletion test should pass: removing `AssistantBackendClaude` and its private units from the package leaves everything else compiling.

### 4.2 Backend contract

This sketch shows the shape. Names are for discussion only.

```pascal
Type
  TAssistantSupport = (asNative, asEmulated, asAbsent);

  TAssistantCapability = (acSystemPrompt, acSkills, acSubagents, acTodo, acImageInput, acImageOutput,
    acWebSearch, acSteer, acSteerImages, acRemoteApproval, acCompaction, acReasoningEffort,
    acThinkingStream, acSessionResume, acModelList, acAccountUsage);

  TAssistantCapabilities = Array[TAssistantCapability] Of TAssistantSupport;

  TAssistantContinuity = (acoMessageHistory, acoRuntimeSession, acoRecapOnly);

  TAssistantTurnRequest = Record
    Mode: TAssistantMode;
    UserText: String;
    ImageRefs: TAssistantImageRefArray;
    SystemPrompt: String;          { built once by AssistantPromptParts }
    Tools: TAssistantToolSpecArray; { already filtered by mode + capabilities }
    Effort: String;
    Continuity: TAssistantContinuityState;
  End;

  IAssistantTurn = Interface
    Function Snapshot: TAssistantTurnSnapshot;   { one shape for every backend }
    Function Steer(Const Text: String; Const ImageRefs: TAssistantImageRefArray; Out ErrorText: String): Boolean;
    Procedure Cancel;
  End;

  IAssistantBackend = Interface
    Function Id: String;                          { 'grok', 'claude', … — the only place the literal appears }
    Function DisplayName: String;
    Function Capabilities(Const Connection: TAssistantConnection): TAssistantCapabilities;
    Function Continuity: TAssistantContinuity;
    Function CheckReady(Const Connection: TAssistantConnection; Out ErrorText: String): Boolean;
    Function ListModels(Const Connection: TAssistantConnection; Models: TStrings; Out ErrorText: String): Boolean;
    Function StartTurn(Const Connection: TAssistantConnection; Const Request: TAssistantTurnRequest;
      Tools: TAssistantToolService; Out Turn: IAssistantTurn; Out ErrorText: String): Boolean;
    Function CreateSettingsFrame(Owner: TComponent): TFrame;
  End;

Procedure RegisterAssistantBackend(Const Backend: IAssistantBackend);
Function FindAssistantBackend(Const Id: String): IAssistantBackend;
```

The existing `IAssistantModelProvider` (sign-in, token, `CompleteOnce`) becomes a helper used by the xAI and compatible backends. It stops being the top-level abstraction.

### 4.3 Standard handling for a missing capability (O6)

Every capability is declared by the backend as **Native**, **Emulated** or **Absent**, and one shared function decides what to do:

| Declared | Catalogue / prompt | UI (desktop) | Remote (phone) | Model asks anyway |
|---|---|---|---|---|
| **Native** | Offered | Enabled | Enabled | — |
| **Emulated** | Offered; the shared layer implements it | Enabled | Enabled | — |
| **Absent** | **Not offered**, and the prompt section is dropped | Disabled, with the standard hint "*Not available with this connection (Claude).*" | Standard refusal `unsupported:<capability>` with the same sentence | Standard tool error `"<tool> is not available with this connection."`. This path should only be reachable through a bug, and it is logged as one |

Rules:

1. **Never offer and then fail.** The catalogue, the prompt sections and the UI enablement all come from the same `TAssistantCapabilities` value.
2. **Emulate in shared code, never in the backend.** Examples: the recap is shared emulation of continuity; steering for Claude can be emulated by queuing the text as the next turn's opening, which needs your decision (§6); subagents for managed runtimes can be emulated by running the child through the native one-shot service.
3. **The sentence is the same everywhere.** One function builds it from the capability and the backend's display name.
4. **Tests cover the matrix.** For each registered backend and each mode, a test asserts that every advertised tool has a capability that is not Absent, and that no Absent capability shows up in the catalogue, the prompt or the UI state.

### 4.4 One tool layer (O1, O2, O5)

- **Declarative specs.** Each tool is one record: canonical name, description, JSON schema, minimum write scope, read-only flag, thread affinity, required capability, and handler. Today's 9 native builders and the broker's `ToolsJsonForScope` become a single table.
- **Wire adapters, not catalogues.** `AssistantToolWire` renders the table as an OpenAI `function`, a Responses tool, Codex `dynamicTools` or MCP `inputSchema`. That replaces `CodexDynamicToolsFromCatalogue` and both hand-written JSON blocks.
- **One canonical name set.** Pick one name per operation. The MCP server name already namespaces the tools for Claude (`mcp__lazarus__read_buffer`), so the internal `lazarus_` prefix can go.
- **One executor.** The broker's model (run id, write scope, revision snapshots, approval hook, IDE-thread marshalling) is the better base, so the native tool bodies move under it. The native actor then calls the same executor as MCP and Codex.
- **One mode → scope function** replaces the four copies in §3.3.
- **One approval gate**, always called with a real tool-call id, so the phone works for every backend. The approval summary is the broker's `MCPApprovalSummary`, used everywhere.

The open question is edit semantics: revision tokens for everyone, or plain writes kept for some backends. See §6.

### 4.5 One turn snapshot and event stream (O1, O2)

- Each backend's turn worker publishes `TAssistantTurnSnapshot` (content, thinking, phase, tool steps, usage, error, done, replay-safety) and appends `TAssistantEvent` records to the session's events JSONL.
- The form has one `PollTurn` that replaces `PollCodex`, `PollClaude` and the native stream callback. Trace blocks are built from events in one place.
- Usage is reported in one record (input, output, cached, reasoning, context, rate-limit JSON) and recorded by `AssistantSession`.

### 4.6 One prompt builder (O1, O6)

`AssistantPromptParts` produces the harness prompt for every backend. Each backend states how it delivers it: a system message (native), `developerInstructions` (Codex), or `--append-system-prompt` (Claude). Backend-specific notes such as `ClaudeReadImageNote` become sections added when the backend declares them. The IDE context policy (when to switch to the light block) depends on the session's turn count, not on `AssistantClient`.

### 4.7 Configuration (O3, O4)

- Split `TAssistantConnection` into common fields (`Id`, `Name`, `Backend`, `Model`, `Effort`, `ApprovalMode`) plus a backend-owned JSON object that the backend loads and validates. Existing `assistant` config files are migrated once, on load.
- Each backend registers its settings frame, so `AssistantSettingsForm` loses its per-backend branches.

---

## 5. Implementation plan

Each phase leaves the IDE working and the test suite green, apart from the known failures listed in `CLAUDE.md`. Fix or quarantine those first so a regression is visible.

### Phase 0: Safety net

| Task | Exit criterion |
|---|---|
| 0.1 Snapshot tests: tool catalogue for each backend × mode | Golden files under `Tests/Fixtures/Catalogue/` |
| 0.2 Snapshot tests: system prompt and first-turn input for each backend × mode | Golden files |
| 0.3 Capability matrix test (§3.7) that records today's state | Test passes and documents the gaps |
| 0.4 Fix `AssistantWorkspaceTest` / `AssistantWorkTargetTest` build (`ToolId` argument) and `AssistantMCPApprovalTest` (`bufferUpdated`) | They build and run |

### Phase 1: Foundation types and registry (low risk)

| Task | Exit criterion |
|---|---|
| 1.1 Add `AssistantAgentTypes` with the capability enum and support levels, snapshot, usage record | Compiles; no callers yet |
| 1.2 Add `AssistantBackendRegistry`; register the four backends as thin wrappers over today's code | `FindAssistantBackend('claude')` works |
| 1.3 Replace backend string literals with `Backend.Id` / registry lookups and capability queries (`CanCompactContext`, `AssistantBackendCanDraw`, the steer checks) | `grep` for the four literals finds only the backend units and config migration |
| 1.4 Rename `FCodexBroker` / `FCodexWorkspace` → `FToolBroker` / `FIDEWorkspace` | Mechanical |
| 1.5 Fix D1 (stop offering `spawn_subagent` to Codex) and D5 (decide Auto vs Always) | Phase 0 snapshots updated deliberately |

### Phase 2: Unified tool layer (highest value, highest risk)

| Task | Exit criterion |
|---|---|
| 2.1 `AssistantToolSpecs`: move every tool definition into the declarative table | Both current catalogues regenerate byte-identical from the table (Phase 0 goldens) |
| 2.2 `AssistantToolWire`: OpenAI / Responses / Codex / MCP renderers | Replaces `CodexDynamicToolsFromCatalogue` and both hand-written JSON blocks |
| 2.3 Choose canonical names and edit semantics (§6); add aliases for one release so stored conversations still replay | Decision recorded |
| 2.4 Move native tool bodies under the broker's executor (`AssistantToolService`); split `AssistantTools.pas` by tool family into units under 1,000 lines | `ExecuteAssistantToolForMode` becomes a thin shim, then is removed |
| 2.5 One mode → scope function; one approval gate with a real tool-call id; one approval summary | D3 and D6 fixed; phone approval works for every backend |
| 2.6 Point the Codex run at the tool service through `AssistantCodexToolBridge` | Codex uses the same executor as Claude |

### Phase 3: Prompt parity

| Task | Exit criterion |
|---|---|
| 3.1 `AssistantPromptParts` with per-backend delivery | Claude receives the harness prompt; goldens updated |
| 3.2 IDE context policy by session turn count | D2 fixed |
| 3.3 Skills for Claude: a `read_skill` tool in the shared catalogue, plus the skills section | Capability matrix row turns ✔ |
| 3.4 Check the Claude prompt size and argument-length limits against the captured fixtures in `Tests/Fixtures/Claude/` | Tested on Linux and Windows |

### Phase 4: One turn contract

| Task | Exit criterion |
|---|---|
| 4.1 `IAssistantTurn` + `TAssistantTurnSnapshot`; adapt the actor, `TAssistantCodexRun` and `TAssistantClaudeRun` | Each backend returns the same snapshot |
| 4.2 Replace `PollCodex` / `PollClaude` / the stream callback with one `PollTurn`; trace built from events | Roughly 1,000 form lines removed |
| 4.3 Every backend writes the events JSONL | History replay and the monitor show the same trace for every backend |
| 4.4 Replay safety in the snapshot (`ReplaySafe = Not ToolRan`) checked by shared recovery code | The Claude "never replay after a tool" rule holds for every backend |

### Phase 5: Session and continuity

| Task | Exit criterion |
|---|---|
| 5.1 `AssistantSession`: shared recap builder (one copy of the 24k loop), image re-attachment rules | `ClaudeRecapPrompt` and the inline Codex recap removed |
| 5.2 Continuity strategy per backend (`acoMessageHistory`, `acoRuntimeSession`, `acoRecapOnly`) | Plan-item sessions (`TClaudePlanItemSession`) generalised or kept Claude-private |
| 5.3 Standard handling of an Absent capability (§4.3) for steer, compaction and web search | No silent no-ops; one sentence everywhere |

### Phase 6: Configuration and settings

| Task | Exit criterion |
|---|---|
| 6.1 Common connection record + backend-owned JSON; a one-time migration on load | Old configs load; round-trip test |
| 6.2 Settings frames registered by each backend | `AssistantSettingsForm` has no backend branches |

### Phase 7: Deletion and partition pass

| Task | Exit criterion |
|---|---|
| 7.1 Remove the shims and aliases introduced in Phases 2–4 | — |
| 7.2 Split `ProjectAssistantForm.pas` (composer, history, trace, plan-run, account usage) | Each unit under 1,000 lines or carrying a dated size note |
| 7.3 Move backend-private units into `Source/LazAssistantTools/Backends/<Name>/` | The deletion test passes for each backend |

### Expected size change

These are estimates, not measurements:

| Source of reduction | Lines |
|---|---|
| Form backend branches → one turn contract | −1,000 to −1,300 |
| Two hand-written catalogues + converter → one table + renderers | −300 to −400 |
| Duplicate tool bodies in the broker / IDE workspace vs native | −800 to −1,500 |
| Duplicated recap, mode mapping, approval and usage code | −200 to −300 |
| Settings form per-backend branches | −500 to −800 |
| New shared units (registry, types, wire, session) | +1,200 to +1,600 |
| **Net** | **about −2,000 to −3,000 (7–10 % of the integration code)** |

The larger gain is not the line count. A new backend becomes one unit plus private helpers, and behaviour stops drifting between models.

---

## 6. Decisions needed from you

1. **Edit semantics.** Should every backend use revision-token buffer edits (the broker's model, which is safer), or should plain `write_file` / `replace_in_file` stay available to native backends?
2. **Canonical tool names.** Native short names (`read_file`), broker names without the prefix (`read_buffer`), or a new set? This affects prompts, stored conversations and skills that mention tool names.
3. **Claude Code built-in tools.** Keep `--tools=Read,Grep,Glob` only, or let Claude Code's own web search and agent tools in as *Native* capabilities? Either way it must stay within your constraints: subscription billing only, and no automatic replay after a tool.
4. **Steering on Claude.** Mark it *Absent* (disabled with the standard sentence), or *Emulated* (queued as the opening of the next turn)?
5. **Codex qualification and schema units.** Keep these defences against app-server drift as they are, or reduce them now that the wire is shared?
6. **`aamAuto` vs `aamAlways`.** Define the difference (for example, Auto still asks for git and delete), or merge them?

---

## 7. Checklist for adding a backend (after Phase 6)

1. Create `Backends/<Name>/AssistantBackend<Name>.pas` that implements `IAssistantBackend` and registers itself in `Initialization`.
2. Declare `Capabilities`, with every entry set to Native, Emulated or Absent. The capability matrix test fails until all are set.
3. Implement `StartTurn` so it returns an `IAssistantTurn` that publishes `TAssistantTurnSnapshot` and events.
4. Choose the tool delivery: the native wire through `AssistantToolWire`, an MCP bridge, or a custom bridge. Do not add tools inside the backend.
5. Choose the prompt delivery and the continuity strategy.
6. Register a settings frame and the backend-owned config keys, and optionally an account-usage query.
7. Add the backend to the Phase 0 golden tests (catalogue, prompt, capability matrix) and add captured wire fixtures under `Tests/Fixtures/<Name>/`.

No change to `ProjectAssistantForm`, `AssistantSettingsForm`, the tool service or other backends should be needed.
