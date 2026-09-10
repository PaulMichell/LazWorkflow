# Codex implementation: development preview

Updated: 10 September 2026.

## Delivered

The assistant window now offers **Settings → Connections → ChatGPT**. This selects a managed Codex run path with a separate subscription sign-in profile, browser login, discovered models, streaming, Stop, steering, conversation history and Lazarus tools. Grok remains available as a separate saved connection in Settings. This is a Linux development preview; full live IDE read/edit/build acceptance remains to be performed by the user.

| Layer | Implementation | Evidence |
| --- | --- | --- |
| Assistant UI | Settings Connections/General pages; named accounts with independent profiles, model/effort/approval preferences; account work off the IDE thread; streamed tool cards and history | Package build; account/model worker exercised with fake runtime |
| Runtime qualification | Exact `codex-cli 0.153.0` / `0.153.4` allowlist before connection; offline experimental-schema inspection and SHA-256 report | `qualify_codex_runtime.py`; actual bundled runtime successfully inspected |
| Process transport | One owning worker, nonblocking stdin, fragmented JSONL, separate stderr draining, bounded frames/queues, write timeout, cancellation, process-group cleanup, EOF/error handling | `AssistantCodexTransportTest`, including blocked/closed stdin, flooding, truncation and missing executable |
| Managed client | ChatGPT account gate; explicit login entry point; model discovery; thread/turn requests; streamed text; steering; interruption; dynamic-tool correlation; rejection of unknown approvals, duplicate calls, authentication changes and unexpected returned provider/sandbox policy | `AssistantCodexClientTest` and existing handshake tests |
| Worker/IDE boundary | Worker owns Codex; IDE thread services one short broker operation at a time; bounded tool handoff; main thread reads snapshots without waiting for the process | Fake runtime → worker → broker → tool result test; cancellation-before-start regression |
| Revision broker | Per-run GUID, project identity, bounded snapshots, opaque revision tokens, Ask/Build policy, read/create/edit/save descriptors, no unrestricted fallback tool | Real SynEdit tests verify unsaved text, stale/replayed revision rejection and one-step Undo |
| IDE adapter | Project-scoped inspection and new-file creation; open-buffer operations through Lazarus; `ReplaceText` preserves Undo; explicit saves report failure; post-edit readback accounts for SynEdit normalization | Package compiles; shared editor primitive and broker tested with real SynEdit |
| Async build pilot | Worker-owned `lazbuild`; refuses dirty editor/project inputs; no implicit saves; timeout/cancel; bounded diagnostic output; observed-input manifest and stale checks | `AssistantBuildJobTest` covers success, compiler error, stale input, timeout, cancellation and absent compiler |

No metered API provider or fallback has been introduced. A recognized ChatGPT account is an authentication condition, not proof of available allowance or successful inference.

## Runtime evidence

The currently installed executable (after the 10 September extension update) is:

`/home/paul/.vscode/extensions/openai.chatgpt-26.5903.71938-linux-x64/bin/linux-x86_64/codex`

It reports `codex-cli 0.153.4`. Its experimental schema passed the field checks and the actual Pascal client reached the expected signed-out account state using an isolated temporary profile. Version 0.153.0 remains supported from the earlier qualification. Reproduce the offline check with:

```sh
python3 Source/Tests/qualify_codex_runtime.py \
  --runtime /absolute/path/to/codex \
  --output-dir /tmp/laz-codex-qualification
```

The resulting `qualification.json` records the executable hash and hashes of the relevant generated schemas. These artifacts belong to the inspected runtime version; they do not establish protocol compatibility with a later extension update.

`AssistantCodexProbe.lpr` is a separate, explicitly invoked diagnostic, excluded from ordinary tests. It accepts an executable and an isolated Codex home. The actual runtime initialized successfully using `/tmp/laz-codex-isolated-home` and reported that ChatGPT sign-in was required. No existing account identity, credentials, sign-in URL or model request was used as test output. No browser sign-in or live inference was performed.

The protocol route follows the [official App Server documentation](https://learn.chatgpt.com/docs/app-server). Dynamic tools require the experimental capability and use the runtime's generated schema. The implementation pins the locally inspected schema instead of assuming that all documented/current versions have identical fields.

## Host integration contract

`TAssistantToolBroker` and `TAssistantIDEWorkspace` belong to the IDE thread. Begin a fresh broker run when starting a task, and cancel it when the project, IDE lifetime, or task changes. The IDE adapter lists and reads project files and can explicitly open an existing file in a background editor tab. Reads prefer unsaved editor contents. Paths outside the project resolver's scope are rejected.

Create `TAssistantCodexRun` with the runtime path, working directory, model, prompt, broker tool descriptors and broker run ID. Start its worker. An IDE timer should call `ServiceTool(Broker)` and read `Snapshot`; it must not call the process client directly. On cancellation, cancel both the run and broker. The form hands cancelled/completed workers to a detached reaper, which joins and destroys them off the IDE thread. No asynchronous callback owns an IDE pointer.

The Project Assistant form now implements this contract, including project changes and closure. It records tool cards and ChatGPT model labels without attaching Grok event/skill metadata. Each request creates an ephemeral Codex thread and includes a bounded recap from the same conversation and ChatGPT model. Durable Codex thread resume and migration of the Grok tool registry to the shared broker remain open.

## Build result boundary

The build pilot observes open editor buffers and the saved project file. It checks those bytes before and after compilation and checks current IDE state before returning diagnostics. It does not freeze every unit, include, package or generated dependency. Therefore the result contains `verified: false` and an explicit validation scope, even if the compiler exits successfully. It must not trigger the native actor's existing automatic task-completion logic.

Complete build evidence requires a dependency-complete immutable snapshot or equivalent coordinated source/version tracking. The original Grok `run_compile` implementation has not been replaced by this pilot yet.

## Testing the preview

1. Rebuild the installed `LazAssistantTools` package/IDE and restart Lazarus to load the changed units.
2. Open a project. Units can be inspected while closed; existing unsaved buffers take precedence over disk.
3. In the **assistant window**, open **Settings → Connections** and select **ChatGPT**. The dialog searches PATH and the local VS Code ChatGPT extension for Codex. Missing saved paths are rediscovered when the connection opens. Use **Auto-detect** or **Browse** to change the executable, then check the connection and press **OK** to persist it. Valid custom paths are retained.
4. Click **Sign in with ChatGPT**, complete sign-in in your browser, then select a discovered model, reasoning level and tool usage permissions, click **Use for current chat**, then **OK**. On subsequent visits, **Check / refresh models** checks the existing account without starting a model turn.
5. In **Ask**, try: `Read the active editor buffer using the Lazarus tools and summarize it. Do not modify anything.` Include a small unsaved comment to confirm that the answer uses the editor rather than disk.
6. In **Build**, request a small edit to an open unit. Inspect the unsaved edit, use Lazarus Undo, then request another edit to check fresh revisions. Saving is a separate tool operation. The default Ask approval setting presents edits, saves and builds for review. Ask exposes no write tools. Plan can create, edit and save Markdown only; source edits and builds require Build mode.
7. In **Plan** (or Build), try: `Review this project and save a new Markdown report to Documents/BugReport.md.` With Ask permissions, review the proposed content and choose Allow once. The tool creates missing parent directories and refuses existing destinations; use another filename or revision-checked editor tools for an existing report.
8. With project and editor changes saved, request a build and ask for its diagnostics. The pilot uses `lazbuild` asynchronously; a successful exit is deliberately not reported as fully source-verified.
9. Test **Stop**, a follow-up prompt, **Hide Tool Use** in the assistant View menu, and selecting Grok under **Settings → Connections** while idle.

Sign-in is kept in `<Lazarus primary config>/assistant-codex-preview`; the runtime owns credentials. The IDE saves named connection definitions and the current selection in `assistant-connections.ini`; existing `assistant-backend.ini` values migrate on first load. It does not import the user's global Codex credentials or API keys. Account authentication does not guarantee available subscription allowance; request failures appear in the answer's error note.

The managed profile disables app connectors, shell/unified execution, automatic skill MCP dependency installation and web search. Runtime startup and thread working directory use the separate profile, not the project. Before starting a thread, the client requires an empty MCP-server inventory; unknown/native approval requests are rejected. Threads and turns select the launcher-defined `lazarus_ide` permissions profile: only `:minimal` filesystem reads, no project-readable roots, and command network access disabled. IDE edits and saves go through the revision broker. These controls are tied to the pinned runtime; broader adversarial/plugin and platform qualification is still required before calling this production-ready.

The real `0.153.0` runtime rejects `approval_policy = "untrusted"` even though its generated schema includes that value. The implementation now uses `on-request` and rejects unsupported approval requests. Both real signed-out initialization and strict configuration parsing succeeded with the preview settings. No browser sign-in or model inference was initiated during development.

## Remaining release work

1. Perform the user-initiated live subscription sign-in/read/edit/build acceptance sequence above, including quota exhaustion, account refresh, Stop during inference and project closure. Broaden isolation checks for inherited hooks/plugins and runtime upgrades.
2. Add durable thread resume and complete handling of arbitrarily interleaved message/reasoning items. Current tests cover literal deltas, completed message snapshots without deltas, repeated completion and distinct sequential messages.
3. Continue expanding the broker with fine-grained symbol operations and other planned IDE capabilities. Project-scoped listing, file reading, explicit editor opening, new text-file creation and revision-checked CodeTools declaration lookup, scoped references and symbol context are implemented. Pinned Grok skills and automatic plan execution are not enabled for the ChatGPT preview. Plan mode can save and revise Markdown plans through the broker.
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

## Thinking summary correction (9 September 2026)

Codex turns now explicitly request `summary: "auto"`. Previously the client relied on the runtime default and parsed only reasoning deltas, leaving empty Thinking cards when summaries were disabled or supplied only at item completion. The client now also consumes completed reasoning-item summaries, preserves section and item boundaries, and replaces streamed text with the completed summary without duplicating it. Summaries are retained in worker snapshots and pre-tool text for the existing Thinking display and history. Show Thinking remains a local visibility toggle; it does not request private reasoning or guarantee a summary on every turn.

The [App Server documentation](https://learn.chatgpt.com/docs/app-server) specifies the turn summary option and reasoning summary/completion events. A small live arithmetic request using the existing subscription sign-in completed and delivered 26 summary characters through both streaming and completion events; the diagnostic recorded counts only. All 17 test programs and the package build passed (`/tmp/laz-codex-thinking-fix`), including streamed sections, completion-only items, duplicate completion and worker delivery.

## Project inspection tools (9 September 2026)

The shared broker now advertises `lazarus_list_directory`, `lazarus_read_file` and `lazarus_open_buffer` when its adapter supports project inspection. They use the same run/project identity and cancellation checks as buffer edits. Ask and Plan can list, read and open tabs. Since 10 September, Plan can change and save Markdown; other file changes require Build.

File reading reuses the existing native bounded read helper, including unsaved-buffer preference, line ranges, truncation information and the 48,000-character output cap. Directory listings reuse the existing 400-entry cap. The IDE adapter validates project scope before reading or opening. Closed files must be regular files of at most 1 MiB; binary/UTF-16 files containing NUL are rejected. New editor tabs open in the background without loading designer resources, creating missing files or saving anything. Opening an already-open file preserves its unsaved buffer. `lazarus_open_buffer` returns a revision for subsequent buffer operations; paged `lazarus_read_file` results are not edit revisions.

Test by asking ChatGPT to list the project root and review a unit that is not open, then in Build ask for a small edit to that unit. It should open the existing file and use the returned revision before editing. Markdown-file creation is not part of this step; reports can still be returned in chat, and existing open documents can be edited in Build.

`AssistantWorkspaceTest` exercises the real broker and workspace adapter against temporary files and mock Lazarus project/editor interfaces. It covers directory discovery, paged disk reads, unsaved-buffer preference, background opening/reuse, revision return, Ask write rejection, missing files, traversal/symlink escapes, binary files, FIFOs, size limits, cancellation and project changes. The existing SynEdit tests continue to cover edit revision checks and Undo. Full-suite results are recorded in `/tmp/laz-workspace-inspection`.

Validation for this step: all 18 test programs and the assistant package build passed. The final bounded file-scan change also passed a targeted workspace test and package rebuild. No live model request was needed for these adapter tests.

## Settings and rendering revision (9 September 2026)

Connection management now lives entirely in Settings, with independent saved connections and a General page containing shared spell-checker preferences. The Backend menu has been removed. See [the settings design and migration record](LazAssistantTools-Settings-and-Connections.md). The same revision fixes bold list continuations and suppresses empty Thinking cards/history entries.

## Settings revision (9 September 2026)

The assistant Backend menu has been removed. All saved connections are managed in Settings; General includes the shared spell-checker preferences. Each ChatGPT connection now has model-advertised reasoning effort and Ask/Auto/Always permissions for Lazarus tools. The selected effort is sent to each new turn, while approval remains in the IDE broker. Ask/Plan restrictions and managed runtime isolation apply regardless of approval choice. Existing ChatGPT sign-in profiles are retained. See [settings design and validation](LazAssistantTools-Settings-and-Connections.md). All 20 regression programs and the assistant package build passed for this revision.

## New project file creation (9 September 2026)

`lazarus_create_file` now supports new reports and other project text files in Build mode. It creates missing directories, applies the selected connection's approval policy, refuses existing disk/editor content and publishes only a complete file. It does not add files to the Lazarus project or save existing editor buffers. Linux directory handles and atomic no-overwrite publication enforce this boundary. Ask exposes no creation tool; Plan supports Markdown creation as of 10 September. See the [progress report](LazAssistantTools-Implementation-Progress.md) for filesystem limits and regression coverage.

Validation: all 21 assistant test programs and the package build passed; logs: `/tmp/laz-assistant-report-creation`. Tests use isolated files, mock IDE interfaces and fake runtime processes; the live report prompt remains a user acceptance check after rebuilding/restarting Lazarus.

## Markdown writes in Plan mode (10 September 2026)

ChatGPT Plan mode now matches the native Grok behavior: it can create and edit project Markdown documents (`.md`, `.markdown`, `.mdown`, case-insensitive). New documents use `lazarus_create_file`; existing documents use `lazarus_open_buffer`/`lazarus_read_buffer`, `lazarus_replace_buffer` with the current revision, and `lazarus_save_buffer` to persist the exact edited text. Plan cannot create or save sources/forms/project files, or start builds. Ask remains read-only. All connection approval settings continue to apply.

The broker now records an explicit read-only, Markdown or project write scope instead of a Boolean edit flag. The IDE adapter checks both the document name and resolved target for Markdown, including after approval, so a Markdown-named symlink cannot disguise a source file or escape the project. Tool descriptions, the managed prompt and the mode hint reflect the same policy.

Validation: all 21 test programs and the assistant package build passed with range/overflow checks. Logs: `/tmp/laz-plan-markdown`. No live model request was made; rebuild/restart Lazarus to test the updated Plan workflow.

## CodeTools navigation (10 September 2026)

ChatGPT can now resolve Pascal declarations through `lazarus_find_declaration` in Ask, Plan and Build. After reading/opening a source buffer, it supplies the current revision and one-based line/UTF-8 byte column. The IDE synchronizes its CodeTools cache and resolves the identifier under the existing project configuration. Results contain the declaration location; they do not open or edit the target. Stale requests and state changes during lookup are rejected.

After rebuilding/restarting Lazarus, try: `Use Lazarus CodeTools to find the declaration of <identifier> in this unit and explain where it is defined.` Include an unsaved identifier change to check that the lookup uses the editor cache. See [navigation details and tests](LazAssistantTools-CodeTools-Navigation.md).

Validation: all 22 assistant test programs and the full package build passed with range/overflow checks; logs: `/tmp/laz-assistant-declarations`. Tests use real CodeTools, mock IDE interfaces and fake runtime processes. No live model request was made for this revision.

## Reference lookup and symbol context (10 September 2026)

ChatGPT now has `lazarus_find_references` and `lazarus_symbol_context`, available in Ask, Plan and Build alongside declaration lookup. References require an explicit batch of project files and return coverage/failure/truncation metadata. Symbol context includes bounded source/declaration snippets and a CodeTools hint. All require the queried buffer's current revision and preserve unsaved editor content. See [navigation details](LazAssistantTools-CodeTools-Navigation.md).

Validation: all 22 regression programs and the assistant package build passed with range/overflow checks (`/tmp/laz-assistant-references`). Live IDE/model acceptance remains a separate check after rebuilding/restarting Lazarus.

## Extension-update connection recovery (10 September 2026)

A VS Code extension update removed the saved `26.5901.22334` runtime directory and installed `26.5903.71938` with Codex 0.153.4. Settings previously retried the missing saved filename and displayed only “Select the installed Codex executable first.”

Connections now rediscover a missing/non-executable saved path when opened, explain the replacement, and provide Browse and Auto-detect controls. Detection does not launch a model or change the account profile, model, effort or approvals. A working custom executable stays selected; Cancel discards the staged replacement. Executable checks and errors now distinguish path selection from the subsequent compatibility/account check.

The runtime allowlist now includes exactly 0.153.0 and 0.153.4; unknown versions still fail. The installed 0.153.4 passed offline generated-schema checks (`/tmp/laz-codex-1534-qualification`) and an actual `TAssistantCodexClient` startup/account handshake in a fresh signed-out profile. This follows the [official App Server protocol](https://learn.chatgpt.com/docs/app-server); it does not establish full signed-in inference/isolation qualification for this new binary. No credentials were copied and no model request was sent.

All 22 regression programs passed. The settings test and package build were rerun successfully after fixing a declaration-order compilation error in the new controls. GUI capture confirmed the runtime controls fit. Tests cover missing-path recovery, valid custom paths, retained connection values, the new runtime, continued acceptance of 0.153.0, and rejection of unqualified versions. Logs and binaries are under `/tmp/laz-assistant-references`.

## Local-variable rename transactions (11 September 2026)

ChatGPT can now preview a routine-local variable rename through CodeTools using `lazarus_preview_local_rename`, then apply its one-use token in Build through `lazarus_apply_local_rename`. Preview is available in all modes. Apply repeats source/semantic validation after approval, preserves native Undo and returns a fresh buffer revision without saving. Unsupported declarations, conditional/include sources, collisions and incomplete/oversized change sets are rejected. See [workflow, limits and acceptance prompt](LazAssistantTools-Local-Rename-Transactions.md).

All 22 regression programs and the package build passed with range/overflow checks (`/tmp/laz-assistant-local-rename`); the final resource-directive correction also passed a targeted semantic test and package rebuild. No live model request was made. General rename, multi-file recovery and form-resource refactoring remain open.
