# Live IDE conversation-view acceptance

Tested: 13 September 2026. Source revision: `3be63c5`.

**Result: the exercised conversation-output checks passed. The rapid-input and initial-window findings were fixed and verified on 14 September; see L1/L2 below.** A separate IDE shutdown exception is recorded as L3. This completes the first live Qt5 acceptance pass, not all platform or accessibility acceptance.

## Environment and scope

- Linux KDE Wayland desktop, Lazarus 4.99, Qt5 using XWayland (`QT_QPA_PLATFORM=xcb`). Native Wayland was not exercised.
- A separate IDE executable was compiled from the current repository packages and local Lazarus checkout. The build compiled both conversation surface/layout units and finished successfully: 286,762 lines, 19.8 seconds, 14 warnings and 54 notes. Local build evidence is in `Lib/LiveIDEAcceptance/build.log`.
- A separate Lazarus profile and disposable `LiveViewCheck` project were used. The installed IDE executable was not replaced. The project's program and `Greeting.pas` remained unchanged.
- Two real requests used the existing ChatGPT sign-in through Codex, model `gpt-6-astra`, low reasoning, in Ask mode. No new API billing configuration was introduced. The copied sign-in file was removed from the isolated profile after testing.
- This was real IDE interaction with mouse/keyboard automation and screenshot/clipboard checks. Earlier GTK2 regression results remain separate: 30 programs plus the three package builds passed before this live session.

## Observed results

| Check | Result |
| --- | --- |
| Real streamed output | Project information, directory listing and two source-file reads completed; the reply rendered a dependency table and 30 numbered entries. The turn took approximately 29 seconds. |
| Markdown rendering | The table rendered as a table; bold labels rendered throughout the numbered list, including the last entry. |
| End of conversation | Entry 30 and the elapsed footer were reachable at the scrollbar endpoint, without an inaccessible tail or persistent blank viewport. |
| Reading earlier output | Earlier content could be inspected during the response/completion sequence without a forced jump to the end. Sustained high-rate streaming remains covered by the separate harness, not a timing guarantee from this live check. |
| Tool defaults and expansion | All four tool calls started closed. Opening the source-file result displayed its complete ten-line detail. |
| Item selection outlines | Assistant selection outlined its full rounded bubble; the expanded tool's blue rectangle enclosed its header and full detail. |
| Hide Tool Use | Tool rows disappeared without leaving their old vertical space. |
| Empty thinking | Thinking display was enabled, but no thinking blocks appeared when these requests supplied no thinking text. Populated thinking disclosure was not exercised by these requests. |
| Resize | Resizing from 1400 × 900 to 1100 × 750 preserved the reading position around entry 8 and rewrapped the answer. No persistent stale or blank region remained after repaint. |
| Splitter movement | Widening the left pane rewrapped the conversation while preserving the selected text. |
| Selection and copy | Select All/Copy included the user prompt, expanded tool source and both the first and last numbered entries. Drag selection copied the expected entries 15–16. |
| New chat | Starting a new chat cleared the previous output correctly. |
| Minimize/restore | A second request completed across minimize/restore and displayed `HISTORY CHECK PASSED`; the response took approximately four seconds. |
| History restoration | Switching to the short conversation and back restored the long conversation's reading position. The compared content crop `(350,110)–(780,550)` was pixel-identical before and after. |

The first prompt was truncated during automated typing, before submission. The model noticed the incomplete instruction and still produced the requested 30 entries. That input defect is recorded below; the output observations concern the actual submitted conversation.

Screenshots: [expanded tool and full selection outline](Images/Live-IDE-Acceptance/expanded-tool.png), [resized conversation](Images/Live-IDE-Acceptance/resized-conversation.png), [last entry and scroll endpoint](Images/Live-IDE-Acceptance/conversation-end.png).

## Open findings

### L1 — Prompt input queues behind layout and can be submitted early

Priority: high. Status: diagnosed, fixed and verified on 14 September 2026.

The prompt editor uses `TSpellMemo` in `Source/LazWorkflowCommon/SpellMemo.pas`, independently of the StyledText conversation surface. After the initial submitted prompt was visibly truncated, input-only comparisons used this exact 457-character string:

```python
"INPUT ACCEPTANCE " + "The quick brown fox tests the complete input buffer. " * 8 + " END INPUT CHECK"
```

| Input method and control | Copied text after input settled |
| --- | --- |
| Prompt editor, `xdotool type --delay 1` | 150 of 457 characters; mismatch |
| Prompt editor, clipboard paste | All 457 characters; exact match |
| Prompt editor, `xdotool type --delay 20` | All 457 characters; exact match |
| Native history-search `TEdit`, `xdotool type --delay 1` | All 457 characters; exact match |

The original check waited one second before copying. Further tracing showed that this was insufficient: the remaining keystrokes eventually arrived. Repeated full-prefix measurements on each edit held up keyboard processing; immediate submission could capture a partial prompt. This corrects the original interpretation of permanently lost characters.

`TSpellMemo` now updates text, selection and change notifications immediately and batches input layout through a 16 ms timer. Painting, geometry-dependent navigation and hit testing flush pending layout when needed. Text replacement, resize and font changes supersede queued measurements; destruction frees the timer. Wrapping uses the canvas text-fit operation with a full-prefix boundary correction for backend shaping/rounding differences, instead of measuring every growing prefix.

Validation:

- The unchanged Qt5 editor took approximately 1,991 ms to process the 457-character fixture. The final regression, including final layout, took approximately 3 ms locally on both Qt5 and GTK2. This measures a controlled input burst, not a universal latency guarantee.
- Merely optimizing fitting was insufficient: immediate Send still captured 448/457 characters in the full Assistant form. With batching, three consecutive 1 ms typing runs followed immediately by Send captured all 457 characters exactly. The harness used the real form and prompt handlers, replacing Send with a local recorder; it made no model calls.
- `SpellMemoInputTest` compares observable wrapped End positions against the former full-prefix algorithm at four widths, including accented text, Greek, Japanese, emoji, tabs and hard newlines. It also covers UTF-8 deletion, replacement, read-only behavior, copy/paste, navigation before the timer fires, replacing pending text and destruction with pending input.
- All 31 programs in the GTK2 assistant suite, direct assistant compilation and the three actual package builds passed. The focused input test also passed on Qt5. Logs are retained locally under `Lib/InputVerification` and `/tmp/laz-input-repro`.

### L2 — Fresh-window proportions leave little conversation space

Priority: low. Status: fixed and verified on 14 September 2026.

The initial 680 × 600 Assistant window left roughly 100 pixels for the conversation between its side panes. The IDE registration supplied absolute right/bottom coordinates, overriding the form's larger design size. Registration now uses screen-relative bounds: left/right 10%/90%, top/bottom 8%/90%. A fresh isolated IDE profile recorded a 1536 × 850 window on the 1920 × 1080 desktop. Existing saved IDE positions remain under the IDE's layout management.

When a small/restored window would squeeze the conversation, the form reduces the two side panes proportionally. It reserves up to 360 scaled pixels for conversation content, or half the available width on small windows. It does not impose a large minimum window size. Ordinary splitter choices remain unchanged unless resizing makes that reserve unavailable. History Export/Delete buttons share the available width so they do not overlap after the pane narrows.

The real Qt5 Assistant form was checked at 640, 680 and 1200 pixels wide, including shrinking and widening. The conversation stayed usable and the final history buttons did not overlap. Narrow panes still abbreviate long labels; this is not a redesign of every work-panel toolbar. See the [680-pixel window after the change](Images/Live-IDE-Acceptance/narrow-window-after.png).

### L3 — Access violation during isolated IDE shutdown

Status: **fixed and verified, 14 September 2026**.

The crash occurred after project closure, Assistant destruction and main-form destruction. Earlier address mapping suggested clipboard cleanup, but that was only an unconfirmed lead. A debug build of the unchanged code reproduced the failure on normal File → Quit and identified the actual call:

```text
SYSTEM.TObject.Free
SYSUTILS.FreeAndNil
AssistantMain.finalize at AssistantMain.pas:316
SYSTEM.FinalizeUnits
```

`TMsgQuickFixes` owns its registered quick fixes through `TObjectList.Create(True)`. Its destructor frees those objects and sets the global `MsgQuickFixes` to nil. The Assistant retained a borrowed pointer to its registered `TAssistantFixMessageQuickFix`, then called `FreeAndNil` on that stale pointer during unit finalization. There was also a double-free path if the registry was still alive: `UnregisterQuickFix` removes the object from the owning list and destroys it, before the same explicit free.

The Assistant now unregisters only while the registry is alive, then clears its borrowed reference without freeing it again. Registration and the “Ask Assistant to Fix...” behavior are unchanged. No clipboard implementation was changed.

Validation used the same local Lazarus 4.99 Qt5/XWayland environment and a separately built executable. The unchanged debug executable stopped with SIGSEGV at the Assistant finalizer. With the fix, three independent normal File → Quit checks returned exit code **0**, logged completed IDE destruction and contained no access violation:

| Case | Assistant visible | Exit code |
| --- | --- | ---: |
| Assistant hidden | No | 0 |
| Assistant open with restored conversation | Yes | 0 |
| After selecting/copying text in the Assistant prompt | Yes | 0 |

The actual `LazAssistantTools` GTK2 package build also passed. These checks exercised application shutdown and unit finalization; a standalone renderer test would not cover the faulty ownership path. Local evidence is in `Lib/ShutdownAcceptance`: `baseline-debug.log`, `build-before.log`, `build-after.log`, `exit-hidden.log`, `exit-open.log`, `exit-clipboard.log`, their JSON results and `package-build.log`. The disposable profiles contain no copied provider credentials and these tests made no model requests. The installed IDE was not replaced.

## Remaining acceptance work

1. L1, L2 and L3 are fixed and verified. No shutdown work remains for this reproduced defect.
2. Complete the remaining live keyboard workflow checks. Focus trapping and Markdown shortcut gaps are fixed; 18 focused GTK2/Qt5 checks pass, with partial native form coverage. See the [keyboard acceptance report](LazAssistantTools-Keyboard-Acceptance.md). Screen-reader testing is excluded from acceptance at the user’s request.
3. Native Wayland, GTK3, Windows and physical monitor/DPI transitions. Qt5/XWayland has the live coverage above; this does not imply every Qt configuration is verified.
4. Extended history/input/allocation and pathological table/shaping profiling: completed on 14 September; see the [follow-up report](LazAssistantTools-Performance-and-Event-Acceptance.md) for fixes, measurements and remaining performance limits.
5. Live IDE event variants: the deterministic offline-runtime pass is complete; see the follow-up report for populated thinking, failures, disconnect, Stop and final-only events. An additional real-provider request was blocked by credential-copy approval review and remains unrun.

Application restrictions on switching conversations during an active request remain unchanged. These live history checks switched completed conversations. No source code was changed during this acceptance pass.
