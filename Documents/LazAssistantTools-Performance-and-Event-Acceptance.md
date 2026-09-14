# Conversation performance and event acceptance

14 September 2026. This completes the requested larger-input profiling and live IDE event-fixture pass. The limits below remain explicit; this is not an all-platform or strict frame-time certification.

## Changes resulting from the checks

1. **Oversized Unicode cluster:** a 2,048-byte drawing-run cap split a long combining sequence, sometimes inside a UTF-8 code point. Drawing runs now preserve that cluster across the cap. A regression verifies the complete source and run boundary. GTK/Pango no longer reports invalid UTF-8 for the fixture.
2. **Large table cell:** table setup measured every cell synchronously, bypassing incremental layout. Cell measurement now shares a per-slice deadline, publishes partial height/selection geometry, aligns each new line once, and releases temporary cell paragraphs on completion. Synchronous callers retain complete layout semantics. Tests compare incremental and synchronous extents/alignment and exercise resizing.
3. **Large-history starvation:** viewport preparation could exhaust the shared deadline before offscreen measurement began. A 15,000-block history sometimes finished in 79 seconds and sometimes failed to finish within 180 seconds. Offscreen measurement now gets its own bounded work slice, independently of the already-spent viewport allowance.
4. **First-use connection startup:** sending through a newly saved connection could launch the runtime with a nonexistent profile working directory, resulting in a misleading version-qualification error. The worker now prepares its managed profile first and reports preparation errors directly. The regression starts a complete worker/tool run with a profile that does not yet exist.

Commits: `0ded4b1` (Unicode), `42cf0df` (connection and event fixtures), `a295275` (tables), `92cb804` (history scheduling and profiles).

## Performance measurements

Linux, Lazarus 4.99, GTK2 controls, default test font, 900 × 650 host. Each fixture runs in a fresh process through the normal asynchronous conversation surface; it does not force synchronous completion. Figures are local observations, not timing assertions. Full elapsed time includes timer gaps, end/start navigation and final layout settling. Initial synchronization, event-pump, paint and layout-update times are measured separately.

| Fixture | Initial sync ms | Full elapsed ms | Max pump ms | Max update ms | Max paint ms | Peak RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 15,000 blocks (2.99 MiB source) | 119 | 26990 | 37 | 31 | 5 | 77.42 |
| 8 MiB formatted reply | 22 | 38839 | 44 | 37 | 5 | 90.77 |
| 256 KiB table cell | 6 | 1080 | 17 | 17 | 1 | 37.16 |
| 64 × 64 table | 6 | 2149 | 21 | 18 | 4 | 36.33 |
| 16,384 combining marks | 271 | 294 | 1 | 0 | 1 | 36.45 |

The original 256 KiB table-cell fixture stalled a UI update for approximately **410 ms**. The final incremental run reduced the largest update to **17 ms** (earlier post-fix runs measured 9–10 ms); full completion takes longer because measurement now yields between slices.

All five final fixtures preserve every source block, keep the native child-control count at two, maintain an extent equal to the shared height index, and reach both scroll endpoints. The history contains 5,000 user/answer/tool groups. The large reply contains repeated formatted paragraphs; it is not one 8 MiB unbroken token. The table tests contain a 256 KiB unbroken cell and a 64-column, 64-row Markdown table. The final shaping fixture is one base character followed by 16,384 combining acute accents.

### Memory attribution

All figures below are MiB of live Pascal heap.

| Fixture | Baseline | Source ready | Initial sync | Layout complete | View released | Source cleared |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 15,000 blocks (2.99 MiB source) | 0.066 | 6.287 | 9.859 | 39.233 | 6.304 | 0.086 |
| 8 MiB formatted reply | 0.066 | 8.129 | 40.409 | 22.629 | 8.144 | 0.082 |
| 256 KiB table cell | 0.066 | 0.324 | 0.355 | 1.758 | 0.339 | 0.082 |
| 64 × 64 table | 0.066 | 0.134 | 0.166 | 1.101 | 0.149 | 0.081 |
| 16,384 combining marks | 0.066 | 0.098 | 0.164 | 0.168 | 0.113 | 0.081 |

The Pascal heap stages distinguish retained fixture/source data from the view's parsed content, heights and drawing state. Fixture construction uses a separate scope so temporary concatenation buffers are released before source measurement. The peak heap still includes those temporary allocations. Returning near baseline after clearing is evidence for this run, not a repeated-session leak proof.

Peak RSS is measured using a fresh parent process and Linux `getrusage(RUSAGE_CHILDREN).ru_maxrss`; it includes GTK/Pango, loaded libraries and allocator retention. It must not be interpreted as a per-view allocation total or combined with the Pascal heap by simple subtraction.

### Remaining performance limits

- One indivisible, pathological combining cluster still incurs a native shaping call lasting hundreds of milliseconds. The final run paid this cost during initial synchronization (271 ms); other runs paid it during a timer update. The UTF-8 corruption is fixed; the native call is not preemptible by the layout deadline.
- A whole update can exceed eight milliseconds: viewport work, offscreen work, reindexing and painting have separate costs. The history fix prevents starvation; it does not promise a strict frame-time cap.
- Completed paragraphs can retain drawing data proportional to paragraph size. Source, parsed content and per-block metadata are deliberately retained. There is no hard total-memory cap.
- The earlier attempted “8 MiB” baseline accidentally doubled its fixture to about 15.25 MiB and timed out. It is excluded from the 8 MiB comparison; the committed fixture trims to complete paragraphs at the requested byte budget.

## Live IDE event coverage

A separately compiled Qt5/XWayland Lazarus IDE used a disposable `LiveViewCheck` project and isolated configuration. The production Assistant form, timer, Codex worker/client, IDE tool broker, trace/history storage and StyledText renderer were exercised. The IDE compiled the Unicode, table and connection changes; the subsequent history scheduling change was verified by the GTK2 surface/profile tests and package builds.

`Source/Tests/codex_event_fixture.py` supplied paced protocol events as an **offline runtime fixture**. It never connects to OpenAI or Grok and uses no account credential. Its model label in screenshots identifies it as a fixture. These are live IDE integration tests with deterministic backend events, not actual provider/network-failure tests.

| Event | Observed live result |
| --- | --- |
| Populated thinking | Both summary paragraphs appeared, including bold text and UTF-8 `café`; a second reasoning item appeared after the tool result. |
| Failed tool followed by recovery | The actual IDE broker rejected a nonexistent project file. The tool was marked failed, began closed, and displayed its error on expansion. The selection rectangle enclosed the expanded item. The subsequent answer and table remained visible. |
| Hide Tool Use | The failed tool appeared when the option was disabled; the conversation reflowed without an empty reserved row. |
| Backend failure | The error note appeared beneath the retained thinking and partial answer. |
| Runtime disconnect | Runtime exit was reported; the already-received thinking and partial answer were retained. |
| User Stop | Clicking Stop ended the pending turn, preserved received content and displayed “Stream cancelled.” |
| Recovery/new chat | New chat after each terminal event accepted the next request. The final request completed successfully after cancellation. |
| Final-only and duplicate completion | Two identical completed-message events produced one rendered answer. An empty reasoning item produced no thinking block. Bold text and `café` rendered correctly. |

Evidence: [expanded failed tool and thinking](Images/Conversation-Events-Acceptance/tool-expanded.png), [backend failure](Images/Conversation-Events-Acceptance/failure.png), [Stop cancellation](Images/Conversation-Events-Acceptance/cancel.png), [final-only response without empty thinking](Images/Conversation-Events-Acceptance/final-only.png).

A proposed additional real ChatGPT request was not run. Automatic approval review rejected copying the existing authentication file into the isolated profile because credential duplication and its cleanup risk had not been explicitly approved. The rejected command did not run and no credential was copied. The earlier real-provider pass in [the live IDE report](LazAssistantTools-Live-IDE-Acceptance.md) remains separate evidence; this pass does not establish how much reasoning text a particular live model chooses to supply.

## Repeatable checks

- `AssistantCodexClientTest`: complete first-run profile creation, existing protocol, isolation and cancellation checks.
- `AssistantCodexEventsTest Source/Tests/codex_event_fixture.py`: all five paced offline event cases through the production worker and broker. The fixture must be executable; its executable bit is committed. It is Linux/Python test infrastructure, not a production backend or a general runtime substitute.
- `MarkdownLayoutTest`: oversized Unicode cluster, incremental table geometry/alignment, temporary-state cleanup and narrower reflow, alongside existing Markdown coverage.
- `AssistantConversationProfileTest history|large|table-cell|wide-table|cluster [size]`: optional extended GUI profiling. `history` size is group count, `large`/`table-cell` size is bytes, `wide-table` size is columns, and `cluster` size is accent count. Run cases separately for attributable process peaks. Keep the build output under an ignored directory and provide normal Lazarus/LCL unit paths.

All **31 existing GTK2 test programs**, the added offline event test, and all three actual package builds (`LazStyledText`, `LazWorkflowCommon`, `LazAssistantTools`) passed. The five extended profiles also passed. Local build/test/profile logs and JSON resource measurements are retained under `Lib/ConversationAcceptance`; screenshots needed for review are committed above. No changes were made to the disposable project's Pascal sources.

Normal File → Quit after these tests reproduced a shutdown access violation after the Assistant and main forms were destroyed (exit code 217). That observation was subsequently traced to a double free of the Assistant message quick fix and fixed; see L3 in the live IDE report for the debugger evidence and three clean post-fix exits.

## What remains on the wider plan

- L3 is now fixed and verified; no further work is needed for that reproduced shutdown defect.
- A systematic keyboard-only workflow; screen-reader testing is excluded at the user’s request.
- Native Wayland, other widget sets/platforms, and physical monitor/DPI transitions.
- Further tuning of extreme shaping, full-update cost and retained paragraph memory if those workloads are product requirements.
- Optional new real-provider confirmation of these events, subject to an approved sign-in approach. Offline fixtures cannot reproduce every provider behavior or network condition.
