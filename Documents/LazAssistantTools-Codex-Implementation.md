# Codex implementation: development preview

Updated: 8 September 2026.

## Delivered

The code now has a managed Codex run path, separate from the Grok native actor. It is a development library and test harness, not yet a selectable backend in the Project Assistant window.

| Layer | Implementation | Evidence |
| --- | --- | --- |
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

Create `TAssistantCodexRun` with the runtime path, working directory, model, prompt, broker tool descriptors and broker run ID. Start its worker. An IDE timer should call `ServiceTool(Broker)` and read `Snapshot`; it must not call the process client directly. On cancellation, cancel both the run and broker. Continue servicing lifecycle completion until `Snapshot.Done` before destroying the worker. No asynchronous callback owns an IDE pointer.

The generic broker and real IDE adapter are implemented, but this host contract is not yet wired into the existing Project Assistant form's send/stop/history lifecycle. The Grok tool registry also still needs migration to the shared broker; this pass does not claim that every backend already uses one registry.

## Build result boundary

The build pilot observes open editor buffers and the saved project file. It checks those bytes before and after compilation and checks current IDE state before returning diagnostics. It does not freeze every unit, include, package or generated dependency. Therefore the result contains `verified: false` and an explicit validation scope, even if the compiler exits successfully. It must not trigger the native actor's existing automatic task-completion logic.

Complete build evidence requires a dependency-complete immutable snapshot or equivalent coordinated source/version tracking. The original Grok `run_compile` implementation has not been replaced by this pilot yet.

## Remaining release work

1. Qualify an isolated runtime profile and inherited configuration. Prove that built-in tools, configured MCP servers, hooks and plugins cannot bypass broker edits or subscription routing. The requested and returned read-only sandbox/provider policies are checked; that alone is not proof about external tools. The [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) documents separate shell and MCP controls.
2. Add the explicit account/connection UI and run a user-initiated ChatGPT sign-in and live subscription-backed inference check. Check allowance separately from account authentication. The existing handshake login method is not a finished UI flow.
3. Wire the managed worker into the assistant panel, including project/IDE closure, send/stop/steer, model selection, event/history presentation and resume. Keep it unavailable until the tool-isolation and live read/edit/build acceptance checks pass.
4. Complete source-consistent asynchronous builds, then migrate the native path and remove its main-thread compile waits and automatic-save/completion behaviour.
5. Expand protocol tests for multiple/interleaved message items, final-item snapshots, persistent thread resume, account refresh, quota errors and broader runtime-failure permutations. Qualify Windows/macOS separately; the process/build pilots currently support Linux only.

## Verification

All 17 test programs and the full assistant package build passed against the local Lazarus checkout with range/overflow checks. Logs: `/tmp/laz-codex-implementation`.

The tests use fake runtime/compiler processes and real SynEdit where applicable. They establish the local implementation behaviour described above, not a live model → full Lazarus project acceptance run.
