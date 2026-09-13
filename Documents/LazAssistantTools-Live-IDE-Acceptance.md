# Live IDE conversation-view acceptance

Tested: 13 September 2026. Source revision: `3be63c5`.

**Result: the exercised conversation-output checks passed. Prompt input has a reproducible rapid-typing failure that remains open.** This completes the first live Qt5 acceptance pass, not all platform or accessibility acceptance.

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

### L1 — Prompt editor loses characters during rapid synthetic typing

Priority: high. Status: reproduced; cause and fix pending.

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

The rapid prompt-editor check waited one second before copying the result. This separates the reproduced failure from merely clicking Send before input settles. The comparison does not establish whether ordinary human typing or other widget sets are affected.

Next work: reproduce in a small Qt5 `TSpellMemo` harness, trace key/text delivery and layout/change handling, fix the established cause, and repeat these exact-copy comparisons plus UTF-8, paste, editing and normal submission checks. Do not assume the conversation renderer or the backend drops the text.

### L2 — Fresh-window proportions leave little conversation space

Priority: low. Status: observed; design adjustment pending.

The initial 680 × 600 Assistant window left roughly 100 pixels for the conversation between its side panes. Enlarging the window restored usable proportions. Review the initial size and adaptive pane widths together, including small displays; simply imposing a large minimum width could create another usability problem.

## Remaining acceptance work

1. Fix and verify L1 before treating the complete chat workflow as accepted; review L2's initial layout.
2. Accessibility: platform text exposure, screen-reader behavior and a systematic keyboard-only workflow.
3. Native Wayland, GTK3, Windows and physical monitor/DPI transitions. Qt5/XWayland has the live coverage above; this does not imply every Qt configuration is verified.
4. Larger histories/inputs, allocation attribution and pathological shaping/table profiling beyond the existing automated fixtures.
5. Populated thinking, backend failures and other event variants in live IDE sessions. Existing automated coverage does not constitute a live test of every event type.

Application restrictions on switching conversations during an active request remain unchanged. These live history checks switched completed conversations. No source code was changed during this acceptance pass.
