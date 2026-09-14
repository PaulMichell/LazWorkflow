# Conversation canvas implementation

12 September 2026. Implements the core replacement in the [reviewed plan](LazAssistantTools-StyledText-Conversation-View-Plan.md), including the subsequent request for closed tool rows and rounded chat bubbles.

## Delivered

- One `TAssistantConversationSurface` derives from `TStyledSurface`. The native control count remains constant: two shared scrollbar controls, with only the vertical scrollbar displayed. Messages create no child controls.
- `TConversationLayout` stores ordered sections keyed by stable block ID, Markdown/literal source, parsed StyledText documents, full/collapsed measurements and one 64-bit effective height index. Hidden entries contribute neither height nor trailing gaps. Empty thinking never produces a visible block.
- The surface prepares layout before publishing the extent and painting. `TStyledMemoLayout.Paint` accepts an optional preparation flag; existing consumers retain their previous behavior.
- The old card/scrollbox machinery and `TTraceBlock.Frame` coupling are removed. Long answers use the conversation scrollbar without height caps.
- User messages appear in pale green rounded bubbles aligned right. Assistant replies appear in light gray rounded bubbles aligned left. Text measurement, hit testing, anchors and selection include the bubble padding and width.
- Tool and subagent rows initially show only their header, including when a result fails. A disclosure click or keyboard activation opens them. Later events preserve that choice. Failure remains visible in the header.
- Received thinking retains the existing compact/full presentation. Source text remains available when display filters hide it.
- Explicit tail-follow state distinguishes reading earlier output from following new output. Section/text anchors survive updates and rewrapping; turn-list navigation scrolls within the full conversation.
- Drag selection can span messages. Copy, Copy Markdown, word/line selection, Select All and Jump to latest are available in the context menu. Keyboard scrolling and disclosure focus are supported; Ctrl+Tab leaves the conversation control.
- Saved turns, live output and legacy history use the same view. New JSON trace entries carry stable block IDs; old archives remain readable through trace JSON, event replay or prompt/response fallback. No archive rewrite is required.
- Conversation reading positions are retained for up to 32 viewed conversations within the window lifetime. Saving a live turn preserves its IDs and avoids duplicate displayed sections.
- Unchanged sections retain their parsed Markdown. Header-only elapsed/status updates replace the header paragraph without reparsing the body.
- Offscreen paragraph drawing runs are discarded independently of source and measured heights. Visible fragments retain viewport paragraphs, a 200-pixel margin and two neighboring paragraphs. Each fragment may additionally retain its current background-measurement paragraph so long paragraphs make progress across timer slices. Parsed documents and height arrays remain proportional to conversation size.
- The package test runner rebuilds repository dependencies before the real assistant package check, preventing stale StyledText compiled units from masking interface changes.

## Reproduction and validation

The old view was exercised with ten answers containing 300 paragraphs each, interspersed with tools. Its widget range stopped at 29,999 and three of the twenty blocks were hidden. This reproduces the old coordinate-limit failure; it does not establish the exact cause of the user's blank screenshot.

Validation environment: Linux x86-64, GTK2, local Lazarus checkout, FPC 3.3.1. The full assistant runner passed all 28 programs, the direct package compilation, and real `lazbuild` checks for LazWorkflowCommon, LazStyledText and LazAssistantTools. Tests enable range and overflow checking. Final selection/cache adjustments also receive targeted surface/history tests and a real assistant package rebuild.

Covered regressions include:

- Empty/received thinking, visibility filters, failed tool defaults and persistent user disclosure choices.
- Bubble geometry and readable default text size.
- Answers over 4,000 pixels and conversations over 30,000 pixels; exact beginning/end and bounded offsets.
- Append while reading earlier output, append while following the end, width changes and selection across messages.
- Stable parsed content on unchanged/header-only updates, copy of hidden source through Markdown export and selection clearing on filters.
- Continuous saved history, turn navigation, live-to-saved deduplication, legacy loading and reading-position restoration.
- Constant native control count with 10,000 sections and paint using the published layout revision.

A GTK2 image of a mixed conversation was inspected: user message, thinking, assistant table/list/code, collapsed tool, final reply and elapsed footer. Tables and inline bold remain styled inside the bubbles.

### Performance observations

The deterministic harness explicitly finishes all measurement for assertions; ordinary interaction uses incremental preparation instead.

| Fixture | Observed result |
| --- | --- |
| 10,000 collapsed tool sections | Approximately 150 ms for synchronization and complete measurement; 359,990 logical pixels; two child controls. |
| Two mixed Markdown answers totaling 4,194,592 bytes | Initial synchronization approximately 254 ms; explicit complete measurement approximately 6.2 seconds; extent 2,580,372 pixels, with the last line reachable. |

These are local measurements, not cross-platform performance guarantees. Tests and measurements can be repeated using:

```sh
python3 Source/Tests/run_assistant_tests.py \
  --lazarus-root /path/to/built/Lazarus \
  --output-dir /tmp/laz-assistant-tests --gui --package-check
LAZ_CONVERSATION_BENCHMARK=1 /tmp/laz-assistant-tests/AssistantConversationSurfaceTest
LAZ_CONVERSATION_CAPTURE=1 /tmp/laz-assistant-tests/AssistantConversationSurfaceTest
```

Where required, supply `--library-dir` for local linker libraries. Capture mode writes `/tmp/laz-conversation-canvas.png`. No live backend calls are made by these tests.

## Remaining acceptance and optimization work

1. **Performance acceptance:** Background parsing and prepared-document publication are implemented for large Markdown bodies; see both follow-ups below. The latest 2.8 MB test measured a 9 ms worst layout update. The 8 ms work budget is a scheduling target, not a guaranteed upper bound on all UI work. The first long-paragraph/code-line and Pascal heap measurements are recorded below. Larger inputs, allocation attribution and pathological shaping/table cases still need profiling. Automated font/DPI correctness checks are now covered by the follow-up below; physical monitor transitions remain unverified.
2. **Platform and accessibility validation:** The first live Qt5/XWayland output pass is complete. Native Wayland, GTK3, Windows, physical monitor DPI transitions and screen-reader behavior are not verified. The control has an accessible name and keyboard interaction, but a platform text-accessibility provider and screen-reader parity are not claimed. Bubble geometry and viewport gutters scale with font DPI; scrollbar space uses the actual native dimensions, respecting widget-set constraints.
3. **Live IDE acceptance:** The [live acceptance report](LazAssistantTools-Live-IDE-Acceptance.md) records two actual ChatGPT requests in a freshly built isolated Qt5 IDE, including streaming, splitter resizing, tool expansion, drag selection and history restoration. Output checks passed. Slow prompt-input processing (L1) and the narrow initial window (L2) are fixed and verified. A separate IDE shutdown exception (L3) needs reproduction/comparison. Populated thinking and other live event variants remain untested in this pass.
4. **Archive lifecycle:** Existing application restrictions on switching conversations during a running request remain. Reading earlier turns within the active conversation works while output arrives; background streaming into another archived conversation is not introduced here.
5. **Further profiling:** Measure heap peaks, per-frame rendering latency and extremely long single-paragraph/code-token cases before claiming a strict time or memory budget. Retained source/parsed content is intentionally not bounded by viewport size.

The existing Markdown subset and link/image behavior remain those of StyledMarkdown. This replacement does not promise broader Markdown syntax support.

## Follow-up: background Markdown parsing

Implemented after the core canvas replacement, 12 September 2026.

`ParseStyledMarkdown` now returns owned paragraph/style values without accessing a renderer, font or canvas. Its result can be bound to a renderer on the UI thread. The existing `BuildStyledMarkdown` entry point retains synchronous behavior for other StyledText consumers, with the same Markdown subset. Cooperative cancellation is available for background callers.

The assistant uses one lazily started worker per conversation surface. It retains at most one in-flight snapshot, rather than queuing every streaming token. Subsequent preparation submits the newest source after the current snapshot completes. Replies of at least 64 KiB use this path; short replies and compact thinking summaries remain synchronous. Canvas measurement and drawing stay on the UI thread.

During replacement, the last completed document and its measured height remain available. A first large reply initially shows its header until a parsed snapshot is ready. Completed intermediate streaming snapshots may be displayed in order while the newest one is pending. Conversation epochs, section instance identities, source versions and font size guard result publication. Clearing or destroying a view cancels outstanding parsing; the worker holds no control/section pointers and schedules no UI callbacks. Shutdown joins the worker before freeing its state.

The background layout timer is now rearmed after a work slice completes. This fixes a second responsiveness problem found during large-document testing: a periodic timer could keep the GTK event pump occupied with overdue layout updates until the entire history had been measured. `MaxUpdateMilliseconds` exposes the largest layout-timer update for profiling.

### Follow-up validation

The new `AssistantMarkdownAsyncTest` covers rapid snapshot replacement, partial-to-complete fenced code and tables, equality of parsed text/style ranges with a complete synchronous parse, reading-anchor preservation, font changes while parsing, cancellation, reuse of a block ID after clearing, worker shutdown and binding detached styles to renderers. Existing Markdown tests additionally check independent style registries, repeat binding and cancellation before parsing.

All 29 test programs passed on GTK2, together with the direct assistant compilation and real LazWorkflowCommon, LazStyledText and LazAssistantTools package builds. The large fixture uses efficient string construction so fixture allocation/conversion does not dominate its measurements.

| Measurement | Observed result |
| --- | --- |
| Existing two-answer fixture, 4,194,592 bytes | Initial synchronization 5 ms, compared with approximately 254 ms before background parsing. Explicit full measurement still takes several seconds (6.8 seconds in this run). |
| Streaming snapshot, 2,818,137 bytes | Initial synchronization below the millisecond timer's resolution; largest layout-timer update approximately 101 ms, largest event-pump call approximately 106 ms. |
| Closing while a snapshot is pending | Approximately 101 ms in the local GTK2 harness; cooperative cancellation and thread join completed. |
| 10,000 collapsed tool rows | Approximately 154 ms for synchronization and explicit full measurement; control count and extent unchanged. |

These local measurements do not establish a strict frame-time guarantee. The diagnostic `CompleteLayout` deliberately forces synchronous completion; normal streaming does not call it. Parsed-result binding, document construction and cache/measurement work can still cause a noticeable one-off pause for multi-megabyte answers. Those handoff costs motivated the prepared-document stage below. Platform, accessibility and live-IDE acceptance items above remain open.

## Follow-up: prepared-document publication

Implemented after the background parser and Markdown Viewer tweaks, 12 September 2026.

The worker now has three stages, with exclusive ownership transferred between it and the UI:

1. Parse Markdown into local paragraph/style values.
2. After the UI registers the small style table, apply the returned integer mapping, compose the title/body/footer, build a `TStyledDocument`, and construct an unmeasured `TStyledMemoLayout` and initial height index. This stage uses no canvas, font object, widget or section pointer.
3. Reclaim the replaced fragment and cached content on the worker during normal publication. Clearing or closing the view still cancels/joins the worker and disposes any remaining state.

The UI attaches its renderer to the prepared layout once, swaps in the accepted document, and measures visible text. The existing epoch, section identity, source version and font-size checks still apply. Width, title, footer and result-state changes during preparation cause the same snapshot to be prepared again with current metadata. A width-only resize of a large reply preserves the old fragment until its replacement is ready and reuses the parsed body without parsing Markdown again.

`TStyledMemoLayout.AttachRenderer` explicitly supports this ownership transfer and rejects attaching a second renderer. `TParsedStyledMarkdown.BindStyles` accepts a registered style mapping without accessing the renderer. Existing synchronous callers remain supported.

Visible and background paragraph preparation now share an 8 ms work budget within a layout-timer update, including the measurement budget passed to StyledText. Visible text gets priority. Incomplete preparation keeps the timer active; exhausted passes no longer each receive a fresh 8 ms allowance. Painting, index updates and scheduling overhead remain outside a strict measurement-time guarantee.

### Validation and measurements

The 2,818,137-byte streaming fixture measured:

| Metric | Before this follow-up | After this follow-up |
| --- | --- | --- |
| Largest layout-timer update | Approximately 101 ms | 9 ms |
| Largest event-pump call | Approximately 106 ms | 14 ms |
| Initial synchronization | Below millisecond resolution | Below millisecond resolution |

The preparation-only change first measured 25 ms for a layout update; sharing the measurement budget reduced it further. These are local GTK2 observations, not universal timing limits.

The extended async regression checks parse/prepare/disposal ownership, valid document construction, header/footer composition, distinct body box groups, table columns, initial height indexes, one-time renderer attachment and disposal on the worker thread. Integration checks include width-only resize without reparsing, updated metadata and font size during preparation, stale-result rejection, reading-anchor preservation, shutdown and equality with synchronous Markdown output.

All 29 assistant test programs passed on GTK2, together with direct assistant compilation and real LazWorkflowCommon, LazStyledText and LazAssistantTools package builds. The standalone scrolling fixture also keeps all 10,000 tool sections reachable with two shared scrollbar controls.

The next acceptance work is the live IDE workflow, font/DPI and accessibility behavior, other widget sets, and profiling extreme single-paragraph inputs and memory peaks. The common large-reply handoff no longer rebuilds the entire styled document on the UI thread.


## Follow-up: font and DPI changes

Implemented 13 September 2026.

The new regression first reproduced a reading-position failure inside a large reply: changing the font discarded its full fragment, and anchor restoration clamped the paragraph to a temporary header-only document. Large replies now retain their previous fragment until the replacement is prepared. Renderer generation participates in replacement scheduling and duplicate-result checks, so a font-face or DPI change rebuilds measurements even when source and width are unchanged. Font-face/DPI changes reuse parsed Markdown; a point-size change reparses size-dependent heading styles. Forced synchronous completion also replaces stale fragments.

A second failure prevented high-DPI preparation from settling. Lazarus's `TFont.Assign` preserves the destination DPI, so the renderer's cached font never matched the surface font and every configure/paint invalidated measurements again. `StyledCanvas` now copies DPI explicitly before assigning the font.

Viewport gutters, chat-bubble padding/radius, inter-section spacing and disclosure hit areas scale with font DPI. Worker preparation receives DPI for section spacing and height estimates, and rechecks it before publication. `StyledSurface` updates scrollbar geometry on font changes as well as resize. It reserves actual native scrollbar dimensions: GTK2 may constrain a requested width, and the previous fixed reservation could disagree with the displayed control. The shared StyledText changes also apply to other consumers, including the Markdown viewer.

### Validation

- `MarkdownLayoutTest` verifies that repeated renderer configuration at 96, 144 and 192 DPI keeps a stable generation, that text height increases with DPI, and that returning to 96 DPI restores its original height.
- `AssistantMarkdownAsyncTest` reads paragraph 100 of the 2.8 MB reply while changing font size, font face and DPI, then returning to 96 DPI. It checks the reading paragraph, selected text, parsed-content reuse, prepared-fragment generation/width, viewport and bubble geometry, native scrollbar reservation and the shared extent. These checks use normal asynchronous preparation.
- The existing conversation surface regression still checks scroll endpoints, tail-follow, filtering, collapse, width changes, cross-message selection and 10,000 sections.

All 29 assistant regression programs passed, together with direct assistant compilation and real LazWorkflowCommon, LazStyledText and LazAssistantTools package builds. Logs are in `/tmp/laz-assistant-dpi-verified`.

These are real GTK2 controls with programmatic font/DPI changes. They do not establish physical monitor transition behavior, accessibility parity or results on other widget sets. Remaining work is live IDE acceptance, accessibility, other widget sets, and extreme single-paragraph/memory profiling.


## Follow-up: long-paragraph reflow and stress coverage

Implemented 13 September 2026.

The next acceptance step exercises one very long paragraph, rather than many small paragraphs. A 512 KiB unbroken reply reproduced a reading-position failure: resizing while reading near byte 262,000 moved the view back near byte 3,800. The replacement layout had measured only its first lines, and anchor restoration treated the last currently measured line as the requested position.

The surface now retains a pending text anchor until measurement reaches that byte offset. Position preparation shares the existing layout work deadline; it no longer forces a whole paragraph to finish synchronously just to restore an anchor. During reflow, later lines can remain temporarily unmeasured, but the desired reading position survives until they become available. Scrolling, wheel/keyboard navigation, clicking, explicit start/end navigation, clearing and restoring another view state take precedence over the pending restoration.

`AssistantConversationStressTest` is included in the GUI regression group. It covers a roughly 600 KiB paragraph with mixed formatting and UTF-8, a 512 KiB unbroken token, a 512 KiB fenced code line and a fenced line containing 512 KiB of spaces. It records elapsed layout time, maximum event-pump/paint/update duration and Pascal allocator usage. Assertions cover source retention, shared extents, constant native control count, the long-paragraph reading position after resize, incremental font reflow, cancellation by navigation, exact tail-follow and clearing a pending anchor. Timing figures are diagnostic, not machine-dependent pass/fail thresholds.

### Initial local measurements

| Fixture | Full layout elapsed | Largest event-pump call | Largest layout update | Pascal heap after layout |
| --- | ---: | ---: | ---: | ---: |
| Mixed prose, 606,208 bytes | 2,362 ms | 30 ms | 12 ms | 6.24 MiB |
| Unbroken token, 524,288 bytes | 3,071 ms | 10 ms | 8 ms | 2.74 MiB |
| Fenced code line, 524,302 bytes | 2,676 ms | 10 ms | 8 ms | 3.30 MiB |
| Fenced spaces, 524,304 bytes | 52 ms | 10 ms | 9 ms | 2.39 MiB |

All 30 assistant regression programs passed, together with direct assistant compilation and real LazWorkflowCommon, LazStyledText and LazAssistantTools package builds. Logs are in `/tmp/laz-assistant-stress-verified`.

These figures are from the initial isolated GTK2 stress run. Full layout elapsed time includes timer gaps; it is not one continuous UI block. The process-wide Pascal heap peak was approximately 6.86 MiB in that run. Heap figures include the harness, source and renderer state, and exclude allocations owned by GTK/Pango and other native libraries. They do not establish a bound on total process memory. A completed very long paragraph retains drawing runs for that paragraph, so memory is not strictly proportional to the viewport.

A separate run of the complete stress harness, including resize/font/navigation checks, finished in 20.26 seconds with a peak resident set of 43,736 KiB (42.71 MiB), measured using Linux `getrusage` through Python. This includes the harness, loaded libraries and native allocations; it is a process-wide peak, not an allocation breakdown or a memory limit. The output and resource measurements are saved in `/tmp/laz-conversation-stress-isolated.log` and `/tmp/laz-conversation-stress-resources.txt`.

The checks provide repeatable coverage for these long-input cases. Physical monitor transitions, live IDE acceptance, accessibility, other widget sets, larger-input/allocation profiling and pathological single-cluster/table shaping remain open.

## Follow-up: live Qt5 IDE acceptance

13 September 2026. The first live Qt5/XWayland output pass is complete; see the [acceptance report](LazAssistantTools-Live-IDE-Acceptance.md) for the environment, results and screenshot evidence. The current sources compiled into a separate IDE executable, and real ChatGPT requests exercised the production conversation surface. No source code changed during this pass.

The output checks passed, including history reading-position restoration and full expanded-tool selection geometry. The session also reproduced rapid-input loss in `TSpellMemo`: 150 of 457 characters survived 1 ms synthetic typing, while paste, 20 ms typing and a native `TEdit` comparison retained the exact text. That is the next focused fix; the report distinguishes it from the remaining accessibility, platform and performance work.

### Prompt-input fix — 14 September 2026

Further tracing corrected L1's diagnosis: keystrokes queued behind repeated paragraph measurement and arrived later. The prompt editor now batches input layout and uses canvas text fitting with corrected painted-prefix boundaries. Three rapid-input/immediate-submission checks captured the complete prompt in the real Assistant-form harness. All 31 GTK2 regression programs and package checks passed, together with the focused Qt5 input test. See L1 in the acceptance report for details. The conversation renderer and backend transport did not require changes.

### Initial-window fix — 14 September 2026

The IDE's initial bounds now use screen percentages, and the form reserves conversation space when resized narrowly. Side-pane widths shrink proportionally; the history buttons divide their available width. The fresh IDE profile and final Qt5 form checks confirm the default size and narrow layouts. See L2 and its screenshot in the acceptance report. That report also records the separate, unresolved shutdown exception as L3.


### Performance and live-event follow-up — 14 September 2026

The requested extended profiling and live IDE event-fixture pass is complete. It found and fixed Unicode cluster splitting, synchronous large-table measurement, offscreen history-layout starvation, and missing first-run Codex profile creation. The [performance and event acceptance report](LazAssistantTools-Performance-and-Event-Acceptance.md) records reproducible fixtures, allocation/RSS attribution, live screenshots, test results and remaining limits.

The live Qt5 IDE exercised supplied thinking, an actual missing-file tool rejection, backend failure, runtime exit, user cancellation and final-only/duplicate events using a deterministic offline runtime. An additional real ChatGPT call was blocked by automatic approval review of credential copying; it was not run. This distinction is retained in the report. L3, accessibility and further platform/DPI acceptance remain open.


### Shutdown ownership fix — 14 September 2026

L3 is fixed. GDB identified a second free of the registered Assistant message quick fix during unit finalization. The IDE registry owns and destroys that object, including on unregistration; the Assistant now only clears its borrowed reference after optional unregistration. Three normal exits of the isolated Qt5 IDE passed (Assistant hidden, open, and after clipboard copy), and the actual GTK2 Assistant package build passed. See [L3 evidence and ownership diagnosis](LazAssistantTools-Live-IDE-Acceptance.md#l3--access-violation-during-isolated-ide-shutdown). No clipboard code was changed.

Screen-reader testing is excluded at the user’s request. Remaining work is keyboard-only acceptance, relevant platform/physical-DPI checks, and the optional performance/provider follow-ups already listed.
