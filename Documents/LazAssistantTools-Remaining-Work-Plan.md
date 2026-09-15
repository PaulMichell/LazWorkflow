# Assistant conversation view — remaining work plan

Created: 15 September 2026. Baseline: commit `d803588`.

This is the consolidated continuation of the [StyledText conversation-view plan](LazAssistantTools-StyledText-Conversation-View-Plan.md), reconciled with the latest [implementation](LazAssistantTools-Conversation-Canvas-Implementation.md), [live IDE acceptance](LazAssistantTools-Live-IDE-Acceptance.md), [keyboard acceptance](LazAssistantTools-Keyboard-Acceptance.md), and [performance/event acceptance](LazAssistantTools-Performance-and-Event-Acceptance.md) reports. It replaces their scattered remaining-work lists for execution; retain those documents as historical evidence.

The broader backend/development-loop roadmap is separate and remains paused for this conversation-view work. This document does not reopen its completed implementation or import speculative future features.

**Already complete:** the canvas replacement, rounded message outlines and disclosure behavior, scrollbar/layout fixes, deterministic event coverage, extended profiling, L1 input latency, L2 initial sizing, L3 shutdown ownership, and K1–K3 keyboard fixes. The focused keyboard suite has 18 passing checks on GTK2 and Qt5. Do not repeat these as implementation tasks unless new evidence reveals a regression.

**Execution rules:** work through R1–R4 first. R5–R6 depend on platform/hardware availability and can proceed independently. R7–R10 are optional follow-ups retained explicitly from the previous reports; their inclusion is not authorization to expand product scope or copy credentials. If a prerequisite is unavailable, record the exact missing prerequisite and leave the package incomplete. A skipped check is not a pass. Screen-reader testing is excluded at the user's request.

Use only the status values `not started`, `in progress`, and `complete`. Every second-level heading below is an actionable work package. Record results beneath the relevant package and in the linked acceptance report. Commit changes in logical groups, including findings and documentation. Use isolated IDE profiles and disposable projects; do not replace the installed IDE or modify the user's projects during acceptance testing. Model access must remain subscription-backed, with no metered API fallback.

## R1 — Complete live IDE keyboard conversation and history checks

Status: not started

Priority: high. Dependencies: none.

- Build the final Assistant into an isolated IDE; record compiler, Lazarus, widget set, display backend and revision.
- Configure the existing `Source/Tests/codex_event_fixture.py` offline runtime without provider credentials.
- Using keyboard input only, enter/edit/select a prompt, submit with Ctrl+Enter, cancel a pending fixture request, and start a fresh request after cancellation.
- Navigate a populated conversation with Tab/Shift+Tab and scrolling keys. Open/close tool and thinking details with Enter/Space. Verify Ctrl+Tab/Ctrl+Shift+Tab escape and traversal beyond the first/last item without focus trapping.
- Select all and copy the conversation; verify clipboard contents, including Unicode and rendered Markdown text. Do not confuse focused-item navigation with text selection.
- Select completed conversations and turns through the history controls. Verify the correct content and reading position restore; retain the existing restriction on switching during an active request.
- Exercise View visibility toggles from the keyboard; verify hidden items leave no blank extent and navigation skips them.

Acceptance: native keyboard events exercise the actual IDE form, all required operations remain reachable, and content/scroll extents agree after each operation. Record key sequences and results; control-handler tests alone do not close this package. Fix reproducible defects and add focused regressions where appropriate.

## R2 — Complete keyboard Settings and Work/Review menu checks

Status: not started

Priority: high. Dependencies: R1 test environment.

- Open Assistant Session, Work, Review and View menus through their mnemonics and navigate their available actions without a mouse.
- In a disposable project, exercise plan opening/selection and available review actions; explain unavailable actions by their actual prerequisites.
- In Settings, navigate Connections, General and Project tests pages, forward and backward through enabled fields and buttons.
- Select and edit saved connection entries; verify keyboard access to connection name, model, reasoning and usage permissions. Use isolated settings and avoid invoking sign-in or model refresh during this offline check.
- Change spell-checker and project-test preferences by keyboard. Verify Cancel discards edits and OK persists intended settings in the isolated profile.
- Confirm closing Settings returns focus to a usable Assistant control. Repeat New Chat prompt-focus verification in the actual IDE.

Acceptance: no unreachable enabled field/action or focus trap; keyboard edits save/cancel correctly. Record exact coverage separately from the earlier standalone-form Settings/New Chat checks.

## R3 — Verify native Markdown shortcuts and readonly selection

Status: not started

Priority: high. Dependencies: R1 test environment.

- Open the Markdown viewer through the IDE keyboard menu using a disposable Markdown file.
- Dispatch native Ctrl+O, Ctrl+1, Ctrl+2 and Ctrl+S events. Check Open dialog navigation, initial Preview selection, exclusive Preview/Source selection and focus transfer.
- Edit and save Source, then return to Preview. Verify selection with Shift+Arrow and Ctrl+A/C; verify typing and Delete cannot edit Preview and no caret is drawn.
- Close and reopen the file to verify the saved text. Exercise unsaved-change handling using the keyboard without touching user documents.

Acceptance: real shortcut dispatch reaches the intended actions and selection/copy remains available in readonly Preview. Existing direct Action.Execute/key-handler regressions remain supporting evidence, not substitutes.

## R4 — Close the keyboard acceptance pass and verify final IDE shutdown

Status: not started

Priority: high. Dependencies: R1–R3.

- Apply any resulting fixes in logical commits; run affected regressions and the actual Assistant package build. Broaden testing only when changes justify it.
- On the final tested build, quit the isolated IDE normally through the keyboard after the conversation/clipboard workflow. Capture exit status and confirm no shutdown exception or orphaned runtime remains.
- Treat any new shutdown failure as a new reproduction; L3's registry-ownership double free is already fixed.
- Update the keyboard and live IDE reports with passed/failed/unavailable checks and the tested revision. Keep standalone-form, control-level, offline-runtime and actual IDE evidence distinct.

Acceptance: R1–R3 have reproducible native-event evidence, final normal shutdown passes, and reports identify any remaining limitations without claiming untested coverage.

## R5 — Qualify additional display backends and platforms

Status: not started

Priority: medium. Dependencies: access to each environment; independent of R6.

- Establish which configurations can be built and run: native Wayland, GTK3 and Windows. Record the actual LCL widget set and display backend; Qt5/XWayland results do not qualify native Wayland.
- For each available configuration, build the packages and run the relevant conversation/Markdown/keyboard tests.
- Exercise live scrolling endpoints, streaming reflow, resize, tool/thinking collapse and filtering, message-outline focus, clipboard selection, history restoration and shutdown.
- Fix platform-specific defects with narrow changes; record unsupported configurations or missing environments explicitly rather than marking them passed.

Acceptance: an explicit per-platform matrix states version, environment, checks, evidence and unresolved defects. Unavailable targets remain outstanding unless the user explicitly removes them from supported scope.

## R6 — Test physical monitor and DPI transitions

Status: not started

Priority: medium. Dependencies: a desktop with appropriate physical monitors/scaling settings.

- Move an open Assistant with a long mixed conversation between monitors with different scaling; test normal and narrow window sizes and font changes.
- Repeat while reading history, with an expanded tool, with selected text and while receiving offline streamed output.
- Verify remeasurement, text wrapping, bubble/focus outlines, pointer hit testing, selection geometry, scrollbar endpoints and reading-anchor preservation. Include the Markdown viewer and its readonly selection.
- Record actual monitor scales, fonts, widget set and display backend. Synthetic resize/font tests are useful but do not replace physical transition evidence.

Acceptance: no clipped/unreachable content, stale selection/hit geometry, blank scroll tail or unintended jump after transitions. Record hardware limitations if the physical setup is unavailable.

## R7 — Optional: resolve conversation keyboard text-selection limits

Status: not started

Priority: optional. Dependencies: R1 findings; product scope decision before expansion.

The conversation currently supports block navigation and whole-document keyboard selection. It does not provide Shift+Arrow character selection or copy an unselected focused block. Markdown Preview supports character selection separately.

- Assess whether the tested workflow needs either additional capability; document existing behavior and the proposed key semantics.
- If adopted, implement document-based selection across blocks, defining collapsed/hidden content behavior and preserving existing disclosure/navigation keys. Keep copy behavior explicit and consistent with the selected text/Markdown representation.
- Test Unicode boundaries, selection across messages, scrolling/reflow and visibility changes; verify clipboard output and visible selection agree.

Acceptance: either the adopted feature has tests and native keyboard evidence, or an explicit scope decision retains the documented limitation. Do not silently mark an unimplemented enhancement complete.

## R8 — Optional: tune pathological shaping and total update latency

Status: not started

Priority: optional. Dependencies: measured product need; existing profile fixtures.

- Retain the already-completed profiling as the baseline. The oversized combining-cluster fixture still spends hundreds of milliseconds in an indivisible native shaping call, despite the UTF-8 corruption fix.
- Measure initial synchronization and the entire UI update separately from individual layout slices. Viewport preparation, background work, reindexing and paint together can exceed the approximate 8 ms tuning target.
- Investigate improvements only for justified workloads. Preserve grapheme boundaries, Markdown correctness, offscreen progress and reading anchors; do not split a combining cluster merely to satisfy a byte/time limit.
- Compare fresh-process runs of normal, large-history, large-reply, table and shaping fixtures; report maximum update/pump times and source integrity.

Acceptance: improvements have attributable measurements and correctness checks, or the remaining non-preemptible shaping/full-update limits are explicitly accepted as product limits. Do not promise a strict frame-time bound without evidence.

## R9 — Optional: bound retained drawing data and check repeated-session memory

Status: not started

Priority: optional. Dependencies: measured product need; existing memory-attribution fixtures.

- Separate required source/parsed-section metadata from evictable drawing data. Completed paragraphs may retain drawing data proportional to their size; there is no hard total-memory cap today.
- Define a practical drawing-cache retention policy if required by supported workloads, then verify eviction/recreation preserves selection, hit testing and scroll anchors.
- Profile repeated load, stream, switch, clear and close cycles. Existing one-run near-baseline heap results do not prove repeated-session leak freedom.
- Report Pascal heap stages and process RSS separately, including allocator/native-library retention. Preserve the constant native child-control count as traces grow.

Acceptance: either a tested retention policy meets an explicit target, or retained-memory limits are documented and explicitly accepted. Distinguish a drawing-cache limit from a total-memory guarantee.

## R10 — Optional: confirm event behavior with subscription-backed providers

Status: not started

Priority: optional. Dependencies: an available authorized subscription sign-in; R4 preferred.

- Use normal sign-in in an isolated profile or another already-authorized access route. Do not repeat the previously rejected copying of authentication files. Offline fixtures require no credentials and remain the default regression mechanism.
- Run a small real-provider confirmation for available ChatGPT/Grok connections: supplied thinking summaries, tools, final text, cancellation and recovery. Record account route, runtime/model version and which events actually occurred.
- Verify that missing reasoning text creates no empty block; do not expect every model to provide the same summary detail. Do not manufacture provider failures or report offline fixture outcomes as real network/provider evidence.
- Confirm there is no metered API fallback. Keep secrets out of reports, logs and commits.

Acceptance: a clearly labelled real-provider report covers observed behavior, or this optional package remains deferred with its exact sign-in/environment prerequisite. Existing deterministic failure/disconnect/final-only coverage remains complete and need not be reopened.
