# StyledText conversation output redesign

Prepared: 12 September 2026.  
Status: core replacement implemented; GTK2 validation and the first live Qt5/XWayland output pass completed. Prompt-input and initial-window fixes are verified. A separate IDE shutdown observation remains to investigate. See the [implementation report](LazAssistantTools-Conversation-Canvas-Implementation.md) and [live acceptance report](LazAssistantTools-Live-IDE-Acceptance.md) for results and remaining work.
Scope: the Project Assistant's central conversation/output control, including live output, history, visibility filters, selection and scrolling.

## Recommendation

Replace the control-per-card implementation with **one conversation surface derived from `TStyledSurface`, painted through `TStyledCanvas`**. Store the conversation as an ordered document of typed Markdown sections. A section represents a user message, assistant response, received thinking, tool result, subagent update, note or timing footer.

The sections remain visually distinguishable, but they are document elements rather than panels, memos or other child controls. A small layout record for each section stores its full/collapsed measurements and visibility. One indexed set of effective heights determines content positions, hit testing and scrollbar extent.

This follows the proposed direction closely. The important separation is between the conversation's content and its current geometry: Markdown and semantic metadata are retained; pixel heights, parsed display fragments and selection geometry are derived and replaceable.

The recommended final view shows the selected conversation, including its turns, as one continuous document. Selecting a turn in the history list scrolls to that turn. Selecting another conversation replaces the document and restores that conversation's reading position. The implementation stages below establish correct rendering of one turn before connecting the complete conversation.

## What the current code shows

These are findings from source inspection, not a confirmed reproduction of the exact screenshot failure.

| Current mechanism | Consequence |
| --- | --- |
| `TAssistantTraceView` owns a `TScrollBox`, a manually sized host panel, and panels/memos/labels for individual blocks. | Widget layout, StyledText body layout and the outer scrollbar each participate in geometry. |
| `ApplyScrollRange` temporarily returns the scrollbar to zero, lays out widgets, changes their heights, then restores a position. | Correctness depends on widget-set coordinate and resize behavior during several intermediate states. |
| `OrderFrames` caps widget coordinates at 30,000 and hides later cards beyond that limit. | Long output can become inaccessible, independently of its Markdown content. |
| A Markdown card taller than 4,000 pixels gets its own scrolling. | Mouse wheel handling and Start/End behavior depend on which child receives input. |
| `Sync` accepts `ScrollBottom` but ignores it; other form code sometimes calls `ScrollToEnd` explicitly. | Tail-follow policy is split between the view and form. |
| `RefreshElapsed` can rebind tool/subagent controls without committing the outer layout/range together. | Changes in displayed geometry have another update path. |
| `TTraceBlock.Frame` points to a view-created control. | Conversation data and widget lifetime are coupled. |
| Most view regressions check card existence/visibility and settings persistence. | The current tests do not exercise the long-output scrollbar failure shown here. |

Relevant sources: [AssistantTraceView.pas](../Source/LazAssistantTools/AssistantTraceView.pas), [AssistantTraceView.lfm](../Source/LazAssistantTools/AssistantTraceView.lfm), [AssistantTrace.pas](../Source/LazAssistantTools/AssistantTrace.pas), [ProjectAssistantForm.pas](../Source/LazAssistantTools/ProjectAssistantForm.pas), [AssistantTraceViewTest.lpr](../Source/Tests/AssistantTraceViewTest.lpr).

There is also an older proposed [HTML card plan](LazAssistantTools-Virtual-HTML-Chat-Cards-Plan.md). This proposal supersedes that rendering direction. Its descriptions of the old Markdown/package dependencies are no longer current. The new design uses the StyledText implementation already in this repository.

## Existing StyledText facilities to reuse

| Existing facility | Use in this design |
| --- | --- |
| `BuildStyledMarkdown` | Convert each section's Markdown into `TStyledContent`: paragraphs, inline style ranges, boxes and table rows. |
| `TStyledDocument` | Store and mutate a section's parsed paragraphs; use paragraph identities/revisions for layout and selection. |
| `TStyledCanvas` | Measure, wrap, paint, clip, and map text coordinates using one shared renderer/style registry. |
| `TStyledMemoLayout` | Reuse paragraph and contiguous-box layout, including tables and selection painting, beneath the section layout. |
| `TStyledSurface` | Own the viewport, buffered drawing, wheel handling and the single vertical scrollbar. It already uses 64-bit logical vertical positions and bounds its backing bitmap. |
| `TStyledHeightIndex` | Maintain cumulative heights and locate a section by document Y without scanning all preceding sections. |
| `TStyledList` | Reference for bounded caches and visible-item lookup; its one-paragraph item and item-selection model do not directly cover a conversation document. |

Sources: [StyledMarkdown](../Source/LazStyledText/StyledMarkdown.pas), [StyledTextDocument](../Source/LazStyledText/StyledTextDocument.pas), [StyledCanvas](../Source/LazStyledText/StyledCanvas.pas), [StyledMemoLayout](../Source/LazStyledText/StyledMemoLayout.pas), [StyledSurface](../Source/LazStyledText/StyledSurface.pas), [StyledTextTypes](../Source/LazStyledText/StyledTextTypes.pas).

One integration detail needs deliberate work: `TStyledMemoLayout.Paint` currently calls `Ensure`, which can update paragraph heights during painting. The conversation must prepare layout and publish its extent before painting that layout. Introduce a narrow preparation/paint contract in StyledText if necessary, rather than copying its paragraph/table rendering into the assistant.

`TStyledSurface` also maps logical positions to a normalized native scrollbar range and currently uses fixed scrollbar dimensions. Verify endpoint rounding, line/page behavior and DPI scaling; inheriting it does not remove the need for scroll tests.

## Document and ownership model

Use one logical conversation document composed of independently updateable sections. Keep the Markdown source for exact export and reparsing; cache the parsed StyledText elements for display.

Proposed section information:

| Content/metadata, owned by the document | Purpose |
| --- | --- |
| Conversation ID, turn ID, stable block ID | Identify content across updates, history navigation and layout rebuilds. |
| Kind | User, answer, thinking, tool, subagent, note, steer or timing. |
| Markdown source or literal-text body | Preserve the original content; tool output can remain literal even when it contains Markdown punctuation. |
| Title, footer, provider/agent identity, tool ID and arguments | Keep structural information separate from presentation text. |
| Running/result state, timestamps and duration | Support live updates and status decoration. |
| Content and metadata revisions | Invalidate only the affected caches. |

Evolve the existing trace/block structures into this role. Avoid keeping a second mutable copy of every body just to feed the view. During migration, an adapter can expose the existing per-turn traces as sections of the conversation document. Backend/event producers should eventually update sections through operations that also advance their revisions.

The view owns the parsed/layout caches, collapsed state, selection and scroll anchors. Remove `Frame`/`NilFrames` and the view's control-ownership assumptions when the new renderer replaces the old one. No document section owns a window handle or widget.

A cached `TStyledDocument` per section is a useful starting point: it is a data object, allows independent replacement of a streaming body, and retains the shared paragraph-layout code. These section fragments form one logical document and one selection/scroll space. They do not create separate controls or scrollbars.

All fragments use the same renderer/style registry. Style IDs are renderer-local and must never be serialized. Scope paragraph and box identities to their section; if a later optimization combines fragments into one physical `TStyledDocument`, remap box-group IDs so adjacent messages cannot accidentally share a box.

### Persistence

Retain existing JSONL conversation storage initially. Store Markdown plus semantic section metadata; rebuild styled elements and geometry on load. Continue reading `TraceJson`, event replay and older prompt/thinking/response fields through one compatibility adapter. A single giant `.md` file would not by itself preserve tool identities, timing and status reliably.

Markdown export is produced from the document's source and metadata, not from painted text or cached layouts. Hiding tools/thinking affects the view only. Keep full-conversation export available and label any visible-only copy/export explicitly. Existing archives must remain readable without rewriting them during viewing.

## Layout records and the height index

Maintain a dense array in document order, with stable-ID lookup. A linked list is unnecessary for the normal append/update workload; the height index supplies efficient cumulative lookup.

Each section layout record contains:

- Its block ID and kind, with references to immutable/current content revisions.
- Cached full-body and collapsed-summary layouts, prepared only when needed.
- Full and collapsed heights as `Int64`, together with validity/estimated flags.
- The cache key: content revision, available width, font/DPI/style generation and wrapping policy.
- Visibility and expansion state, with current header/footer geometry.
- A handle to any retained paragraph layouts and interaction regions.

Only the **effective height index** is authoritative for vertical placement. Compute tops from its prefix sums. Avoid separately maintaining card `Top` values that can become stale.

```text
EffectiveHeight(block) = 0                                  when hidden
                       = CollapsedHeight + following gap   when collapsed
                       = FullHeight + following gap        when expanded

ContentHeight = top padding + sum(EffectiveHeight) + bottom padding
MaxScroll     = max(0, ContentHeight - ViewportHeight)
ScrollTop     = clamp(ScrollTop, 0, MaxScroll)
ScreenY       = ViewportTop + DocumentY - ScrollTop
```

Specify one gap policy: hidden elements contribute no gap, and the last visible element has no following gap. Empty documents have no scrollable blank tail. Zero-height entries must be skipped consistently by painting, hit testing, keyboard navigation and the height-index boundary search.

A body can have valid full and collapsed heights without keeping all of its expensive drawing runs in memory. Evict offscreen layouts separately from their measurements. Both cached heights become invalid when width or font metrics change.

For an existing full/collapsed cache, a visibility change needs no Markdown parsing or text measurement. An uncached expansion measures the revealed content, then commits its new effective height with the anchor-preservation rules below.

## One geometry update and one scroll policy

Every content, visibility or metric change follows one update transaction:

1. Capture whether the reader is following the end and capture a stable reading anchor.
2. Apply document/visibility changes and invalidate affected measurements.
3. Prepare the required layout, starting with visible content and the active streaming section.
4. Update the effective height index and publish a coherent layout revision.
5. Set the surface extent once, restore the anchor or follow the end, and clamp the position.
6. Invalidate the affected viewport area. Painting and hit testing use that published layout revision.

The form must not reset the view's scroll position as part of ordinary refresh. It requests an explicit action such as navigating to a turn or jumping to the end; the view owns all resulting positions.

### Following the end

Maintain explicit `FollowTail` state. A reader already at the end follows newly appended output. Wheel, keyboard or thumb navigation away from the end disables following. Returning to the end or choosing **Jump to latest** enables it again. Merely making the document temporarily shorter must not silently re-enable following.

Capture the state before changing content height. Selection dragging pauses following. Stream completion and elapsed-time updates must not force the reader to the bottom.

### Preserving a reading position

Use an anchor based on turn/block ID and a text position, with the visual offset into that line. A text anchor survives rewrapping better than a raw pixel offset into a tall message. Headers can use a block-relative anchor.

If collapse or filtering hides the anchor, retain the nearest visible successor, or the predecessor if no successor exists. Keep its screen position where possible, then clamp. Preserve the selected conversation's anchor when switching to history and returning.

### Large content and provisional measurements

Keep all document coordinates and cumulative heights in `Int64`. Pass only viewport-relative, clipped coordinates to drawing/widget APIs. A million-pixel conversation must not require a million-pixel panel or bitmap.

Exact total height is unknown until all relevant paragraphs are measured. Mark estimates explicitly, use them consistently in the published index, and refine them in bounded UI-thread work. Each refinement updates the extent and restores the anchor together. Never paint using a newer measurement while the scrollbar still describes an older index.

On a distant thumb jump, prioritize measuring the destination and its neighbors; do not synchronously lay out every intervening message. Cached measurements make subsequent navigation stable. First landing on estimated content may refine the thumb position, but must neither leave a stale blank viewport nor lose the reader's anchor.

Reserve the vertical scrollbar gutter consistently, including when disabled, so its appearance does not repeatedly change the Markdown wrap width. Use actual scaled metrics for that gutter.

## Rendering and interaction

The surface paints only sections intersecting the viewport, with a small preparation margin. Use the existing canvas's clipped paragraph drawing so one enormous answer does not need full-height rendering. Paint headers, subdued thinking text, tool rows, disclosure indicators, borders and timing as canvas content.

There is one vertical scrolling owner. Long answers have no inner vertical scrollbar or artificial 4,000-pixel height cap. For initial parity, use the current StyledText wrapping/table policy for long code and table cells; test narrow viewports and oversized tokens. If unwrapped code requires horizontal navigation later, implement it deliberately without introducing vertical child scrollers again.

Default presentation remains familiar: full user/assistant messages, compact tool headers with expandable results, and collapsible received thinking. Running state and elapsed time occupy a stable header/footer area. Updating the clock should normally repaint that area without remeasuring the body.

**No received thinking text means no thinking document section in the visible layout.** Timing/internal activity can still be tracked separately. Apply the same rule when adapting old history containing empty thinking placeholders. Do not fabricate text for models that provide no reasoning summary.

Selection belongs to the conversation surface:

- Represent endpoints by block ID, paragraph identity and UTF-8 byte offset.
- Use StyledText's measured glyph positions for hit testing and painting selection.
- Support drag selection across messages, word/line selection, Ctrl+A, Ctrl+C and keyboard scrolling.
- Keep selection independent of layout-cache eviction. Map or clamp it when a streaming body is replaced.
- When a filter hides selected content, clear or remap the visible selection explicitly; ordinary Copy must not silently include newly hidden material.
- Provide a clear Copy Markdown command for source fidelity, separately from copying selected rendered text.
- Support disclosure activation from both mouse and keyboard with visible focus.

Removing native memos also removes their built-in accessibility behavior. Keyboard and text-accessibility checks belong in the acceptance work; expose the conversation's text and focus state through available LCL/platform facilities. Do not claim screen-reader parity until tested on the target widget sets.

The current Markdown reader intentionally supports a subset and does not resolve links/images. Preserve existing rendering behavior and literal fallback during migration. Link activation, nested-list continuation and other parser improvements should have their own tests and scoped commits, rather than being assumed consequences of using a canvas.

## Streaming and update cost

An incoming event updates a section's content or metadata revision. Coalesce display work on the UI thread using the existing refresh cadence or a small frame budget. Worker threads must not touch LCL canvases or measurement caches.

Initially reparse only the changed section. Completed sections retain their parsed content and layouts. Do not treat streamed Markdown as append-only styled text: arriving fences, table delimiters or closing emphasis can reinterpret earlier source. Include incomplete-to-complete Markdown transitions in regressions.

If a very large streaming section exceeds the update budget, retain its latest pending source and show the most recent completed layout until the replacement is ready. Prefer this bounded approach before implementing a new incremental Markdown parser. Further paragraph-level parsing needs measured justification and correct handling of cross-line constructs.

Reserve the 64-bit document revision/generation together with conversation identity for scheduled work. Switching conversations, clearing a session or closing the panel invalidates pending layout/repaint work. Updates for the live conversation can continue in the model while an archive is displayed without replacing the archived viewport.

## Proposed code boundaries

Names are provisional; they describe responsibilities rather than a requirement to add many units.

| Area | Intended change |
| --- | --- |
| `AssistantTrace.pas` and conversation adapter | Typed Markdown sections, stable identities/revisions, no control pointers; compatibility with stored turns and events. |
| New `AssistantConversationLayout.pas` | Section caches, effective height index, layout publication and anchor calculations. Keep non-LCL geometry testable. |
| New `AssistantConversationSurface.pas` | One `TStyledSurface` descendant: drawing, scrolling, selection and disclosure hit testing. |
| `AssistantTraceView.pas/.lfm` | Thin compatibility wrapper during migration, then remove the scrollbox/host/card-control machinery. |
| `ProjectAssistantForm.pas` | Pass document changes and explicit navigation requests; remove competing refresh-time scroll resets. |
| `StyledMemoLayout.pas`, possibly `StyledSurface.pas` | Narrow generic preparation/paint or geometry-notification extensions where required; no assistant-specific message kinds in StyledText. |
| `AssistantConversation.pas` | Compatibility adapters and stable history/turn navigation; no mandatory archive format rewrite. |
| Tests and package registration | Geometry, scrolling, selection, streaming and real-widget integration coverage. |

## Implementation sequence and review gates

The user approved implementation after design review. The core deliverables of phases 1–6 are implemented; platform/accessibility validation and extreme-input performance acceptance remain follow-up work, as recorded in the implementation report.

| Phase | Deliverable | Gate before proceeding |
| --- | --- | --- |
| 1. Reproduction and geometry specification | Synthetic traces for the blank-output/scrollbar problem; expected scroll/anchor behavior and test fixtures. | Reproduce at least a long-output or mutation failure in the old path and record the scenario. Do not invent an exact explanation for the screenshot. |
| 2. Document and layout foundation | Stable section IDs/revisions, data-only layout records, full/collapsed cache keys, height index and anchor tests. | Hidden/collapsed/mutated sections produce correct extents and positions without widgets. |
| 3. Canvas feasibility slice | Render a complete mixed turn directly on one StyledText surface; establish measure-before-paint and clipping behavior. | A tall answer and a long sequence of tool results remain fully reachable, without inner scrollers or oversized child controls. |
| 4. Live behavior and interaction | Streaming, tail-follow, collapse/filter updates, selection/copy, timer updates, resizing and DPI changes. | Scroll/selection invariants hold throughout updates; completed sections are not repeatedly parsed. |
| 5. Conversation/history integration | Continuous selected conversation, turn-list navigation, old-history loading and live/archive anchor restoration. | History and live output use the same document/layout path, and saved/exported content remains compatible. |
| 6. Replacement and removal | Switch the production view; remove the old cards, `Frame` coupling, nested wheel forwarding, coordinate caps and duplicate scroll policies. | Target-widget testing passes; the old implementation is removed rather than retained as a permanent second renderer. |

Keep the new surface in an isolated test harness while it is incomplete. A temporary development switch can help compare screenshots, but no permanent backend/rendering choice belongs in global settings.

## Acceptance and performance checks

The core invariant is testable after every published layout: the height-index total equals the surface extent, the scroll position is within range, and painting/hit testing use that same layout revision.

| Scenario | Required result |
| --- | --- |
| Many blocks extending beyond 30,000 pixels | Every block is reachable; none is hidden by a coordinate limit. |
| One answer substantially taller than 4,000 pixels | Entire answer scrolls in the main viewport. |
| Append while at the end | Latest visible output remains in view. |
| Append while reading earlier text | Reading anchor and selection stay put. |
| Hide/show tools and thinking at top, middle and end | Extent changes immediately; hidden blocks leave no gaps; visible anchor is preserved. |
| Collapse a tall block above or containing the viewport | Predictable anchored/clamped position with no empty region from stale geometry. |
| All optional blocks hidden or document cleared | Empty state and disabled/zero-range scrolling agree. |
| Resize, font/DPI change, splitter movement, minimize/restore | Rewrap and measurement invalidation update content and scroll geometry together. |
| Drag thumb/page/keyboard to beginning and end | No missing last lines, unreachable first message or endpoint drift. |
| Stream partial tables, bold text, fenced code and UTF-8 across chunks | Content converges to the same rendering as loading the completed Markdown. |
| Switch conversation while output/layout work is pending | No stale work appears in the new document; reading positions restore. |
| Select across messages, then scroll or evict caches | Copy and highlight still identify the intended text. |
| Empty thinking, failed tools, subagents and elapsed updates | Correct visibility/status without phantom sections or scroll jumps. |

Use deterministic layout tests for index/anchor behavior and real LCL harness tests for measurement, scrollbar events, resizing and clipping. Replace current tests that inspect `Block.Frame` with content/layout/interaction assertions. Keep Markdown regression coverage and run the actual `.lpk` build.

Run live checks on the user's Linux widget set, explicitly recording whether GTK2 or GTK3 is in use; exercise both where supported. Add Windows/other widget-set results when available rather than inferring them from Linux tests.

Benchmark at least a normal conversation, 10,000 small blocks, and a few multi-megabyte sections with tables/code. Record changed-section parse time, layout time, painted sections/lines, cache memory and scrollbar updates. Initial target: normal scrolling fits a display frame and streaming layout uses roughly 8 ms UI work slices on the test machine. These are tuning targets to measure, not unverified performance claims. Native child-control count must remain constant as conversations grow; drawing-cache growth must have a defined limit, separate from retained source text.

## Decision for review

My recommendation is to proceed with the typed Markdown document, one StyledText surface, and one effective-height index. Keep the existing history format and use data-only per-section caches. Establish scroll/anchor correctness before adding broader Markdown features or further rendering optimizations.

The first implementation work would be the reproduction/geometry harness and document layout foundation. Backend and development-loop feature work remains paused while this output-control replacement is reviewed and implemented.

## Implementation update — 12 September 2026

The production view now uses one StyledText surface, with typed Markdown sections, stable block identities, cached paragraph measurements and one effective height index. History turns form a continuous conversation. The former panel/memo cards, nested vertical scrolling, 4,000-pixel card limit and 30,000-pixel coordinate limit have been removed.

Following the user's additional design feedback, tool/subagent rows start collapsed, including failed calls, and subsequent events retain the user's expansion choice. User and assistant messages use rounded canvas-painted bubbles, aligned right and left respectively. Bubble padding participates in the same measurements used for scrolling and selection.

The implementation report distinguishes completed regression checks from outstanding performance and platform acceptance work. Backend/development-loop work can resume after the user has tested this replacement in the IDE.

### Background parsing follow-up

Large Markdown sections now parse in a single background worker using detached paragraph/style values. The UI retains the last completed snapshot, publishes accepted results with conversation/section/version checks, and binds styles and measures text on the UI thread. Rapid-update, cancellation, font-change and stale-result regressions are included. The layout timer now waits a fresh interval after each work slice to avoid continuously overdue updates.

The existing 4.2 MB fixture's initial synchronization fell from approximately 254 ms to 5 ms locally. Large-result publication can still take roughly 100 ms, so the 8 ms target remains open for that stage. See the implementation report for measurements, validation and remaining work.

### Prepared-document publication follow-up

The worker now prepares the mapped paragraph content, complete document and initial layout index before publication, then reclaims the replaced snapshot. The UI retains renderer ownership and performs only registration, attachment, visible measurement and painting. Width-only changes to large replies reuse parsed content and retain the previous fragment until the replacement is ready.

Visible and background preparation share one 8 ms measurement budget per timer update. In the existing 2.8 MB streaming fixture, the largest measured layout update fell from approximately 101 ms to 9 ms and the event-pump call from approximately 106 ms to 14 ms. Those measurements support the common-case improvement; they do not close platform, accessibility, font/DPI or extreme-input acceptance work. See the implementation report for tests and remaining items.


### Font/DPI correctness follow-up — 13 September 2026

Implemented the next automated acceptance step. Large replies retain their reading paragraph and selection through font-size, font-face and programmatic DPI changes. Fixed repeated renderer invalidation caused by `TFont.Assign` preserving the destination DPI. The viewport and bubble geometry now scale with font DPI, while scrollbar space follows actual native dimensions. Prepared replacement documents validate current DPI and renderer generation.

Regressions cover 96/144/192 DPI and returning to 96 DPI, including paragraph 100 inside the existing 2.8 MB asynchronous reply. See the implementation report for details. Physical monitor transitions, live IDE acceptance, accessibility, other widget sets and extreme-input/memory profiling remain open.


### Long-paragraph stress follow-up — 13 September 2026

Added a regular GUI stress regression for long formatted prose, unbroken tokens, fenced code and whitespace. It found and reproduced a reading-position jump when resizing halfway through a long paragraph. Anchor restoration now waits for incremental measurement to reach the requested text position and yields to explicit navigation or a conversation change.

The implementation report records timings, Pascal heap usage and a 42.71 MiB process resident-memory peak, with their limits. This closes the first long-paragraph correctness/profiling pass; it does not claim a strict frame-time or total-memory bound. Remaining acceptance work includes live IDE use, physical monitor transitions, accessibility, other widget sets, larger-input/allocation profiling and pathological shaping/table cases.

### Live Qt5 IDE acceptance — 13 September 2026

The first live output pass used a freshly built, isolated Qt5 IDE and two actual ChatGPT requests against a disposable project. Streaming output, tables/bold, scroll endpoints, collapsed tools, complete selection outlines, filtering, resize/splitters, selection/copy, minimize/restore and completed-conversation history restoration passed the exercised checks. Requests without thinking text produced no empty thinking blocks.

The [acceptance report](LazAssistantTools-Live-IDE-Acceptance.md) records screenshots and limitations. It also adds two findings: **L1**, rapid synthetic typing loses characters in the separate `TSpellMemo` prompt editor, and **L2**, the fresh window leaves too little width for the conversation. Investigate and fix L1 next, with a focused Qt5 reproduction and exact input/copy checks; review initial pane proportions alongside L2. Full chat-workflow acceptance remains open until L1 is resolved.

Accessibility, native Wayland/GTK3/Windows, physical monitor transitions, remaining live event variants and larger-input/allocation/pathological-table profiling follow. The completed Qt5/XWayland checks do not establish coverage for those configurations.

### Prompt-input follow-up — 14 September 2026

L1 is fixed. Tracing showed delayed keyboard delivery rather than permanently discarded characters: expensive per-keystroke wrapping allowed Send to capture an incomplete prompt. Input now updates immediately while a short timer batches layout; geometry-dependent operations flush pending work. Canvas text fitting replaces sequential prefix measurements, with boundary corrections preserving GTK2/Qt5 wrapping.

The real Assistant-form harness captured all 457 rapidly typed characters on immediate submission in three consecutive runs. All 31 GTK2 regression programs and three package builds passed; focused Qt5 editing/wrapping tests passed too. See the acceptance report for measurements and test scope. L2's initial proportions are the next item being completed.

### Initial-window follow-up — 14 September 2026

L2 is fixed. IDE registration now uses screen-relative initial bounds, replacing absolute coordinates that produced the cramped window. Resizing preserves space for the conversation by reducing side panes proportionally when necessary. History buttons share the available width without overlapping. A fresh IDE profile recorded 1536 × 850 on a 1920 × 1080 desktop; the final form was inspected at 640, 680 and 1200 pixels wide. The current sources also compiled into the isolated Qt5 IDE successfully.

The acceptance report records a separate shutdown access violation after IDE/form teardown, mapped to the LCL clipboard area (L3). Reproduce and compare that exit path before attributing it to a particular change. Accessibility, further platform/DPI checks, live event variants and additional performance profiling remain as listed above.


### Performance and live-event follow-up — 14 September 2026

The requested extended profiling and live IDE event-fixture pass is complete. It found and fixed Unicode cluster splitting, synchronous large-table measurement, offscreen history-layout starvation, and missing first-run Codex profile creation. The [performance and event acceptance report](LazAssistantTools-Performance-and-Event-Acceptance.md) records reproducible fixtures, allocation/RSS attribution, live screenshots, test results and remaining limits.

The live Qt5 IDE exercised supplied thinking, an actual missing-file tool rejection, backend failure, runtime exit, user cancellation and final-only/duplicate events using a deterministic offline runtime. An additional real ChatGPT call was blocked by automatic approval review of credential copying; it was not run. This distinction is retained in the report. L3, accessibility and further platform/DPI acceptance remain open.
