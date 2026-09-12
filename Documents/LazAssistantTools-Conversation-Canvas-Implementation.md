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

1. **Large-document publication latency:** Background parsing is now implemented for Markdown bodies of at least 64 KiB; see the follow-up below. Binding styles and publishing a very large parsed document still happen on the UI thread and can exceed the 8 ms target. Further staging of that handoff and profiling of measurement/cache work remain.
2. **Platform and accessibility validation:** GTK3, Qt, Windows, high-DPI transitions and screen-reader behavior are not verified. The control has an accessible name and keyboard interaction, but a platform text-accessibility provider and screen-reader parity are not claimed. Bubble/scrollbar dimensions use the current StyledSurface pixel conventions.
3. **Live IDE acceptance:** Test the user's actual IDE with streaming responses, splitter resizing, tool expansion, drag selection and long archived conversations. Automated GTK2 tests cover the model and real canvas, but do not substitute for this workflow check.
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

These local measurements do not establish a strict frame-time guarantee. The diagnostic `CompleteLayout` deliberately forces synchronous completion; normal streaming does not call it. Parsed-result binding, document construction and cache/measurement work can still cause a noticeable one-off pause for multi-megabyte answers. That handoff is the next performance optimization; platform, accessibility and live-IDE acceptance items above remain open.
