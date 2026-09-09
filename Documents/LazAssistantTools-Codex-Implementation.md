# Codex implementation: development preview

Updated: 8 September 2026.

## Delivered

The assistant window now offers **Backend → ChatGPT (preview)…**. This selects a managed Codex run path with a separate subscription sign-in profile, browser login, discovered models, streaming, Stop, steering, conversation history and Lazarus tools. Grok remains available in the same menu. This is a Linux development preview; full live IDE read/edit/build acceptance remains to be performed by the user.

| Layer | Implementation | Evidence |
| --- | --- | --- |
| Assistant UI | Assistant-owned backend menu and connection dialog; account work off the IDE thread; persisted non-secret runtime/model selection; streamed tool cards and history | Package build; account/model worker exercised with fake runtime |
| Runtime qualification | Exact `codex-cli 0.153.0` check before connection; offline experimental-schema inspection and SHA-256 report | `qualify_codex_runtime.py`; actual bundled runtime successfully inspected |
| Process transport | One owning worker, nonblocking stdin, fragmented JSONL, separate stderr draining, bounded frames/queues, write timeout, cancellation, process-group cleanup, EOF/error handling | `AssistantCodexTransportTest`, including blocked/closed stdin, flooding, truncation and missing executable |
| Managed client | ChatGPT account gate; explicit login entry point; model discovery; thread/turn requests; streamed text; steering; interruption; dynamic-tool correlation; rejection of unknown approvals, duplicate calls, authentication changes and unexpected returned provider/sandbox policy | `AssistantCodexClientTest` and existing handshake tests |
| Worker/IDE boundary | Worker owns Codex; IDE thread services one short broker operation at a time; bounded tool handoff; main thread reads snapshots without waiting for the process | Fake runtime → worker → broker → tool result test; cancellation-before-start regression |
| Revision broker | Per-run GUID, project identity, bounded snapshots, opaque revision tokens, Ask/Build policy, read/edit/save descriptors, no unrestricted fallback tool | Real SynEdit tests verify unsaved text, stale/replayed revision rejection and one-step Undo |
| IDE adapter | Project-scoped open-buffer operations through Lazarus; `ReplaceText` preserves Undo; explicit saves report failure; post-edit readback accounts for SynEdit normalization | Package compiles; shared editor primitive and broker tested with real SynEdit |
| Async build pilot | Worker-owned `lazbuild`; refuses dirty editor/project inputs; no implicit saves; timeout/cancel; bounded diagnostic output; observed-input manifest and stale checks | `AssistantBuildJobTest` covers success, compiler error, stale input, timeout, cancellation and absent compiler |

No metered API provider or fallback has been introduced. A recognized ChatGPT account is an authentication condition, not proof of available allowance or successful inference.

## Runtime evidence

The executable found in this environment is:

`/home/paul/.vscode/extensions/openai.chatgpt-26.5901.22334-linux-x64/bin/linux-x86_64/codex`

It reports `codex-cli 0.153.0`. Stable and experimental schemas were generated, and the relevant fields were checked against the implementation. Reproduce the offline check with:

```sh
python3 Source/Tests/qualify_codex_runtime.py \
  --runtime /absolute/path/to/codex \
  --output-dir /tmp/laz-codex-qualification
```

The resulting `qualification.json` records the executable hash and hashes of the relevant generated schemas. These artifacts belong to the inspected runtime version; they do not establish protocol compatibility with a later extension update.

`AssistantCodexProbe.lpr` is a separate, explicitly invoked diagnostic, excluded from ordinary tests. It accepts an executable and an isolated Codex home. The actual runtime initialized successfully using `/tmp/laz-codex-isolated-home` and reported that ChatGPT sign-in was required. No existing account identity, credentials, sign-in URL or model request was used as test output. No browser sign-in or live inference was performed.

The protocol route follows the [official App Server documentation](https://learn.chatgpt.com/docs/app-server). Dynamic tools require the experimental capability and use the runtime's generated schema. The implementation pins the locally inspected schema instead of assuming that all documented/current versions have identical fields.

## Host integration contract

`TAssistantToolBroker` and `TAssistantIDEWorkspace` belong to the IDE thread. Begin a fresh broker run when starting a task, and cancel it when the project, IDE lifetime, or task changes. The initial IDE adapter works with files already open in Lazarus and rejects paths outside the project resolver's scope.

Create `TAssistantCodexRun` with the runtime path, working directory, model, prompt, broker tool descriptors and broker run ID. Start its worker. An IDE timer should call `ServiceTool(Broker)` and read `Snapshot`; it must not call the process client directly. On cancellation, cancel both the run and broker. The form hands cancelled/completed workers to a detached reaper, which joins and destroys them off the IDE thread. No asynchronous callback owns an IDE pointer.

The Project Assistant form now implements this contract, including project changes and closure. It records tool cards and ChatGPT model labels without attaching Grok event/skill metadata. Each request creates an ephemeral Codex thread and includes a bounded recap from the same conversation and ChatGPT model. Durable Codex thread resume and migration of the Grok tool registry to the shared broker remain open.

## Build result boundary

The build pilot observes open editor buffers and the saved project file. It checks those bytes before and after compilation and checks current IDE state before returning diagnostics. It does not freeze every unit, include, package or generated dependency. Therefore the result contains `verified: false` and an explicit validation scope, even if the compiler exits successfully. It must not trigger the native actor's existing automatic task-completion logic.

Complete build evidence requires a dependency-complete immutable snapshot or equivalent coordinated source/version tracking. The original Grok `run_compile` implementation has not been replaced by this pilot yet.

## Testing the preview

1. Rebuild the installed `LazAssistantTools` package/IDE and restart Lazarus to load the changed units.
2. Open a project and open the units you want ChatGPT to inspect in the Lazarus editor.
3. In the **assistant window**, choose **Backend → ChatGPT (preview)…**. The dialog searches PATH and the local VS Code ChatGPT extension for Codex. Select the executable above if discovery is empty or finds a different version.
4. Click **Sign in with ChatGPT**, complete sign-in in your browser, then select a discovered model and click **Use ChatGPT**. On subsequent visits, **Check / refresh models** checks the existing account without starting a model turn.
5. In **Ask**, try: `Read the active editor buffer using the Lazarus tools and summarize it. Do not modify anything.` Include a small unsaved comment to confirm that the answer uses the editor rather than disk.
6. In **Build**, request a small edit to an open unit. Inspect the unsaved edit, use Lazarus Undo, then request another edit to check fresh revisions. Saving is a separate tool operation. Ask/Plan expose no write or build tools.
7. With project and editor changes saved, request a build and ask for its diagnostics. The pilot uses `lazbuild` asynchronously; a successful exit is deliberately not reported as fully source-verified.
8. Test **Stop**, a follow-up prompt, **Hide Tool Use** in the assistant View menu, and switching back to **Backend → Grok** while idle.

Sign-in is kept in `<Lazarus primary config>/assistant-codex-preview`; the runtime owns credentials. The IDE saves only backend/runtime/model preferences in `assistant-backend.ini`. It does not import the user's global Codex credentials or API keys. Account authentication does not guarantee available subscription allowance; request failures appear in the answer's error note.

The managed profile disables app connectors, shell/unified execution, automatic skill MCP dependency installation and web search. Runtime startup and thread working directory use the separate profile, not the project. Before starting a thread, the client requires an empty MCP-server inventory; unknown/native approval requests are rejected. Threads and turns select the launcher-defined `lazarus_ide` permissions profile: only `:minimal` filesystem reads, no project-readable roots, and command network access disabled. IDE edits and saves go through the revision broker. These controls are tied to the pinned runtime; broader adversarial/plugin and platform qualification is still required before calling this production-ready.

The real `0.153.0` runtime rejects `approval_policy = "untrusted"` even though its generated schema includes that value. The implementation now uses `on-request` and rejects unsupported approval requests. Both real signed-out initialization and strict configuration parsing succeeded with the preview settings. No browser sign-in or model inference was initiated during development.

## Remaining release work

1. Perform the user-initiated live subscription sign-in/read/edit/build acceptance sequence above, including quota exhaustion, account refresh, Stop during inference and project closure. Broaden isolation checks for inherited hooks/plugins and runtime upgrades.
2. Add durable thread resume and complete handling of arbitrarily interleaved message/reasoning items. Current tests cover literal deltas, completed message snapshots without deltas, repeated completion and distinct sequential messages.
3. Expand the broker beyond open buffers: project-scoped file reading/opening, fine-grained symbol operations and other planned IDE capabilities. Pinned Grok skills, reasoning controls and automatic plan execution are not enabled for the ChatGPT preview. Plan mode returns its plan in the answer.
4. Complete source-consistent asynchronous builds, then migrate the native path and remove its main-thread compile waits and automatic-save/completion behaviour.
5. Qualify Windows/macOS separately; the process/build pilots currently support Linux only.

## Verification

All 17 test programs and the full assistant package build passed against the local Lazarus checkout with range/overflow checks. Logs: `/tmp/laz-codex-preview`.

The tests use fake runtime/compiler processes and real SynEdit where applicable. They establish the local implementation behaviour described above, not a live model → full Lazarus project acceptance run.

## Signed-in startup correction (9 September 2026)

The first live test failed the external-tool check because a ChatGPT-authenticated runtime enables the built-in `codex_apps` server by default, even with a dedicated `CODEX_HOME`. This was absent in the earlier signed-out probe. The [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) documents `features.apps` as enabled by default.

The launcher now passes `-c features.apps=false` on every start, and new managed profile configurations also persist that setting. Existing sign-ins work without recreating the profile. The check requiring an empty external MCP inventory remains in place; Lazarus dynamic tools are registered separately.

An inventory-only check against the existing signed-in Lazarus profile reproduced `codex_apps` with 88 tools. Repeating with the override returned an empty inventory. No model turn or app tool was invoked. The fake signed-in runtime now models this default, and tests verify both successful isolated startup and continued rejection of unrelated external MCP servers.

## Restricted-read protocol correction (9 September 2026)

The next live request exposed another schema/runtime discrepancy: the pinned runtime still emits the legacy `readOnly.access` shape in its schema but rejects that field during turn startup. Restricted reads now use the named `permissions` field on both `thread/start` and `turn/start`. The launcher defines `permissions.lazarus_ide.filesystem={":minimal"="read"}` and `permissions.lazarus_ide.network.enabled=false` on every launch, so existing profiles require no migration. The client still validates the returned read-only sandbox and approval policy.

The [official configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) describes named filesystem permission profiles. A real ephemeral thread using the existing ChatGPT sign-in accepted this profile and returned a read-only sandbox with network access disabled. One minimal subscription-backed request (`Reply with OK only. Do not use tools.`) then completed successfully. No project files or IDE tools were involved; full IDE acceptance remains open.

Regression tests now reject the obsolete sandbox override and require named permissions for both thread and turn requests. The offline qualification script checks the `permissions` fields. All 17 regression programs and the package build pass; logs are in `/tmp/laz-codex-permissions-fix`.
