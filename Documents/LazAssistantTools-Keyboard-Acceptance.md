# Keyboard acceptance — 15 September 2026

Status: focused keyboard checks and fixes complete; the full live IDE workflow matrix remains partially tested. Screen-reader testing is excluded at the user's request.

## Fixed issues

- **K1 — conversation focus trap.** Tab beyond the last item and Ctrl+Tab searched only the containing trace frame, which contains no other focusable control. Navigation now searches the form's tab order. Reverse traversal and empty conversations use the same route.
- **K2 — Markdown toolbar keyboard access.** Added Ctrl+O (Open), Ctrl+S (Save), Ctrl+1 (Preview), and Ctrl+2 (Source). Changing mode focuses its text control. Preview remains read-only, hides the caret and permits selection.
- **K3 — menu and prompt access.** Added explicit Assistant/Session/Work/Review/View menu mnemonics. Explicit New Chat focuses the prompt so typing can resume immediately.

## Validation

`Source/Tests/AssistantKeyboardTest.lpr` passes all 18 checks on GTK2 and Qt5. It exercises real controls with protected key-handler calls and actions: forward/reverse escape, tool disclosure, skipping hidden tools, select-all, empty conversation, Markdown mode changes and save, read-only preview selection, and New Chat focus. A nested panel reproduces the original focus trap; four conversation checks failed before K1.

The GTK2 Assistant package builds successfully. AssistantSettingsTest, AssistantLfmTest, AssistantTraceViewTest and AssistantConversationSurfaceTest also pass after these changes.

Native Qt5/XWayland keyboard input was separately exercised against the real Assistant form with an isolated memory-backed IDE host:

1. Alt+S, End, Return opens Settings.
2. Keyboard navigation reaches the General page and spell-checker engine control.
3. Escape cancels Settings.
4. Alt+S, Home, Return starts a new chat; typing `Keyboard focus check` reaches the prompt without clicking it.

No provider login or model call was made. The standalone form checks do not replace testing the complete installed IDE. Earlier live IDE checks established Session menu access and keyboard prompt entry; they did not establish every menu action or successful submission.

## Remaining coverage and limits

- Finish the complete live IDE keyboard sequence: submit/cancel using the offline runtime, populated history navigation, Work/Review/View actions, clipboard copy, Markdown shortcut dispatch through native events, and normal shutdown with the final build.
- Exercise connection selection/editing and Project tests settings entirely from the keyboard; page/field access above is only partial Settings coverage.
- Conversation keyboard selection currently supports whole-document selection, not Shift+Arrow character selection or copying an unselected focused block. Markdown preview has character selection. These are distinct capabilities, not proof of full text-selection parity.
- Other widget sets and physical monitor/DPI transitions remain outside this pass.

Reproduction artifacts and logs are in ignored `Lib/KeyboardAcceptance/`. The regression uses a disposable configuration and a no-op memory-storage writer; it does not read or write the user's connection credentials.
