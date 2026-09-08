# LazAssistantTools implementation progress

Updated: 8 September 2026.

This records implementation against the [revision plan](LazAssistantTools-Architecture-and-IDE-Integration-Revision-Plan.md). Subscription-backed Grok and ChatGPT access remains mandatory. No metered backend or API-key fallback has been added.

## Completed in the first implementation pass

| Commit | Change | Validation |
| --- | --- | --- |
| `4debf77` | Separate streamed response item IDs from function call IDs; append tool-argument deltas without text deduplication; consume completed tool snapshots authoritatively; ignore duplicate Responses terminal events; reject truncated/incomplete rounds before tool execution. Restrict protocol fallback to HTTP 404/405/501. | Expanded `AssistantSamplerTest`; whole assistant package compilation. |
| `a2b9ab1` | Introduce editor range edits through the actual Lazarus `ReplaceText` implementation, preserving its Undo blocks and earlier user history. Add snapshot/read-only preconditions. Report disk-save failure as failure after a buffer update. Preserve supplied bytes for disk-only writes and remove redundant editor replacement after opening a newly written file. | Real SynEdit test through `TSourceEditorInterface`: user Undo history, UTF-8 boundaries, CRLF, empty buffers, no-op edits, stale snapshots and read-only rejection. |
| `6a226ff` | Extract the existing Grok OAuth, model discovery and one-shot transport into `AssistantXaiProvider`, behind `IAssistantModelProvider`. Shared service checks subscription authentication before dispatch. Child services inherit the parent provider; replacing providers clears shared history and cancels child work. | Fake-provider integration tests verify routing and reject unknown/metered authentication. Tests supply in-memory IDE configuration and do not read real account credentials. |
| `6d1ba6d` | Validate tool identities and JSON object arguments before reporting successful completion. Reject duplicate call IDs so they cannot produce duplicate mutations. | Missing-call-ID, malformed-argument and duplicate-call regression cases. |
| `a5e7f4d` | Add a transport-independent Codex initialization/account/browser-sign-in state machine and launch-argument builder requiring ChatGPT login and the OpenAI provider. It rejects API-key/unknown/external-provider accounts, invalid sign-in hosts, malformed/oversized frames and unsupported server tool requests. | Fragmented JSONL, correlation, subscription account, login lifecycle, stale/late replies and failure tests. |

A reproducible test runner and temporary project-rename fixtures accompany this progress record. The old path tests depended on a real project tree under the developer's home directory; the replacement performs an actual rename inside a disposable fixture.

## Current product boundary

**ChatGPT is not selectable or operational in the assistant panel yet.** The new Codex unit implements the connection/authentication protocol, not the process transport, conversation loop or Lazarus tool bridge. It deliberately exposes no model-request or tool-execution entry point. It is a foundation for the P0 prototype, not completion of P3.

The existing Grok path remains the operational backend. Its account flow has been moved behind an interface, but the native actor still owns Responses/chat-completions serialization. Provider-specific request capabilities, full backend event contracts and managed-runtime execution ownership remain to be extracted. This is partial P1, not a claim of arbitrary-model compatibility.

The editor helper verifies the exact snapshot supplied by its caller. Existing tools do not yet expose durable model-visible buffer revisions or multi-file change sets; those are P2 work. The successful Undo test is meaningful, but it is not an end-to-end stale-model-edit or designer transaction test. Disk-save failure reporting has been corrected by inspection; disk failure injection remains to be added when persistence moves behind the workspace adapter.

No live Grok/ChatGPT model calls, subscription-usage measurements, token refresh tests or browser sign-ins were performed. No `codex` executable was found on this shell's PATH. The installed runtime/version, account entitlement and bridge compatibility still require qualification. The protocol follows the documented App Server/account interface, whose experimental support caveat remains a release gate in the revision plan.

Existing plaintext Grok token persistence has **not** yet been migrated. The extraction preserves that behaviour pending the credential-store work; subscription enforcement must not be confused with credential-storage hardening.

## Verification

All 12 selected assistant test programs passed after replacing the machine-dependent path fixtures:

- `AssistantCommandsTest`, `AssistantEventsTest`, `AssistantLfmTest`, `AssistantProjectPathsTest`.
- `AssistantSamplerTest`, `AssistantSearchUtilTest`, `AssistantTraceTest`, `AssistantCodexHandshakeTest`.
- `AssistantSubagentsTest`, `AssistantHarnessTest`, `AssistantEditorEditsTest`, `AssistantProviderTest`.

The assistant package compiled against the local Lazarus checkout with Free Pascal 3.3.1 and range/overflow checks enabled. LCL tests used GTK2 and the local display. This does not establish Windows/macOS compatibility, a successful IDE reinstall, or live subscription-backed inference.

The [test runner](../Source/Tests/run_assistant_tests.py) uses compiled units from an existing Lazarus checkout and places generated files outside the source tree. Example on a Linux development machine:

```sh
python3 Source/Tests/run_assistant_tests.py \
  --lazarus-root /path/to/built/Lazarus \
  --output-dir /tmp/laz-assistant-tests \
  --gui
```

Omit `--gui` for the eight console tests. Use `--compile-only` to compile without running; use `--library-dir /path/to/linker/libraries` if the system needs additional library search paths. This pass used `/tmp/laz-assistant-baseline` for logs and an existing local linker-library directory. The GUI group needs a working display. No test invokes a live model.

## Next implementation order

Pending cleanup from the table-rendering fix: remove the unused `MergeSamplerText` helper in `AssistantProtocol.pas`, its private supporting routines/constants, and the obsolete `TestMergeSkipsRepeatedThought` test. Automatic approval review rejected the previous scripted deletion as too broad, so these remain unchanged. First verify that no production callers remain, then use a narrowly scoped patch with an explicitly reviewed diff. Retain the lossless-stream and snapshot regressions, run the assistant/Markdown suite and package build, and commit the cleanup separately.

1. **Complete the Codex transport spike.** Add a single-owner process/stdio transport with bounded queues, timeout, cancellation and exit handling. Locate and qualify a runtime/version, generate its schema and verify initialization/account flows using a fake process before an explicitly initiated real account test. Authentication readiness must remain separate from quota/entitlement availability.
2. **Establish the shared tool broker and workspace identity.** Centralize tool descriptors/policy; attach project generation and buffer revisions; make main-thread dispatch short and reject stale/cancelled requests. Wire the editor helper to caller-held snapshots and structured mutation/save outcomes.
3. **Prove Codex → Lazarus read/edit/build.** Connect a local MCP or qualified dynamic-tool bridge to that broker. Read an unsaved buffer, apply an Undo-preserving edit and return build diagnostics. Verify that managed built-in tools cannot bypass the live-buffer policy. Do not enable the ChatGPT panel until this path works.
4. **Fix asynchronous build/evidence coordination.** Replace main-thread process waits and automatic saving of all dirty editors. Associate builds with exact project/build-mode/source revisions. Remove clean-compile-only task completion.
5. **Complete native-provider extraction and durable continuation.** In-memory tool-round output preservation is now implemented (see the HTTP 400 follow-up below). Extend this to restored sessions and non-tool turns. Move request options/serialization behind capability-aware provider contracts. Text and reasoning deltas are now lossless as well (see the table-rendering follow-up below).
6. **Integrate credentials, persistence and UI.** Migrate Grok tokens safely, bind managed authentication to the runtime, add provider/profile/model selection, version sessions and present reviewable diffs/diagnostics. Continue into CodeTools and designer transactions after workspace/build correctness is established.

P0 and P1 are partially complete; P2 has an implemented editor primitive. Later phases remain open. This file should be updated alongside subsequent logical implementation commits.

## Follow-up: HTTP 400 after the first tool batch

A reported short prompt successfully invoked three read-only tools, then received HTTP 400 on the follow-up request. The old actor reconstructed the conversation and appended just one encrypted reasoning item after the tool results. This discarded the original output order, other reasoning items and fields such as reasoning summaries. xAI's documented stateless tool loop instead appends the complete response output before the tool results. [xAI tool continuation documentation](https://docs.x.ai/developers/tools/advanced-usage)

The actor now stores the complete ordered output array on the corresponding in-memory assistant tool-call message. Responses requests replay those objects before their results; chat-completions requests continue to use their separate representation. The old trailing encrypted-item insertion is removed. Large tool-call arguments also retain their real IDs instead of being replaced with a synthetic call that could not match subsequent results. Opaque continuation payloads count towards context budgeting and are cleared when their tool-call group is removed.

HTTP errors now extract a bounded structured provider message from the response body. Previously the stream parser discarded non-SSE error bodies, leaving only `HTTP 400` in the UI. Raw response bodies are not written to logs.

Regression coverage reproduces the reported three-tool sequence through parser, service history and request builder, checks a second tool round, verifies output ordering and matching IDs, and exercises structured error extraction. The assistant suite and package build are checked against the changes. This confirms the local request-construction fix; the exact original server rejection remains unconfirmed because its error body was not retained. A live retry after rebuilding/restarting Lazarus is still needed. Subscription authentication and billing behaviour are unchanged.

## Follow-up: partially rendered tables

The reported three-column table appeared with a one-column separator (`|---|`) and missing closing bold markers. A regression reproduced this corruption: the stream merger discarded repeated `---|` and `**` chunks as duplicates. The Markdown renderer correctly rejected the resulting malformed table.

Responses and Chat Completions now append text and reasoning deltas verbatim. Responses item snapshots replace the text belonging to that item, preserving separate messages even when their contents match. Completed message output replaces partial streamed text and retains all messages. The actor consumes the parser's authoritative text instead of applying a second heuristic merge; thinking from preceding tool rounds is kept separately.

Validation: all 13 assistant/Markdown test programs pass and the complete assistant package compiles. Regressions cover byte-fragmented SSE, repeated Markdown delimiters, item/final snapshots, identical messages, and two streamed tables rendered with three columns and bold cells. `MarkdownLayoutTest` is now part of the runner's GUI group. Logs are in `/tmp/laz-assistant-tables`. No live model request was made. Rebuild/restart Lazarus and retry the prompt; previously stored text that already lost delimiters is not repaired by this change.

## Follow-up: assistant View menu tool visibility

Added **View → Hide Tool Use** to the Project Assistant window's own menu, toggling to **Show Tool Use**. It hides tool-call rows in live and historical traces without deleting tool results or changing execution. Newly arriving rows and timer refreshes respect the setting. The project-local `show_tool_use` preference defaults to visible and survives plan updates by existing configuration callers.

Validation: all 14 test programs and the assistant package build pass. `AssistantTraceViewTest` covers hiding/restoring rows, incoming tools, timer refreshes, retained results and preference persistence. Logs: `/tmp/laz-assistant-hide-tools`.
