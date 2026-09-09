# Assistant settings and connections

Implemented 9 September 2026.

## Settings layout

The assistant no longer adds a Backend menu. Settings opens one resizable form with two pages:

- **Connections:** saved connection names, connection-specific account/model controls, and **Use for current chat**. Selecting a row edits that connection; it does not automatically switch the chat. **OK** saves the chosen connection and preferences. The model label in the assistant footer also opens Settings.
- **General:** automatic IDE context, the Grok context rollover preference, and the existing shared spell-checker controls (engine, language, library and dictionary location). The context preference now also applies to automatic context attached to Codex requests.

ChatGPT sign-in and model discovery are embedded in the Connections page. They remain asynchronous, use subscription authentication, and keep the pinned runtime and Lazarus tool restrictions. Grok retains its established browser sign-in, model list, endpoint, skill, reasoning and approval settings in its own connection details. Opening Settings no longer initiates Grok model discovery; Refresh list explicitly requests it.

## ChatGPT reasoning and tool permissions

Each ChatGPT connection has its own reasoning level and usage permissions. **Check / refresh models** obtains `supportedReasoningEfforts` for each model from the subscription runtime. The list always includes **Model default**, which omits the request's effort override. Selecting a different model removes unsupported choices; a saved value remains visible before discovery. Explicit choices are sent as `turn/start.effort`. Reasoning effort controls model work; **Show Thinking** controls visibility of whatever summary the model supplies.

- **Ask** (default, including migration): read operations proceed; new-file creation, buffer replacement, saving and starting a build require an Allow once response. The review shows the exact current and proposed text for replacements, the current content for saves, the complete proposed new-file content, or the build operation. Decline has no write/build effect.
- **Auto:** allow the registered project tools within the active mode.
- **Always:** allow registered tools without prompts. Because the current Codex registry contains only bounded project tools, Auto and Always currently have the same effect. Neither enables arbitrary runtime tools.

Ask and Plan modes remain read-only under all three permission choices. Runtime isolation and subscription-only authentication are independent of this setting. Approval is followed by run/project validation; buffer adapters still compare the approved text immediately before mutation. Build status polling does not prompt again. Settings cannot change while a chat request is running.

## Connection identity and persistence

`AssistantConnections.pas` separates connection definitions from the current selection. Each definition has a stable ID, display name, backend ID, runtime, model, reasoning level and tool approval mode. `assistant-connections.ini` stores those non-secret values and the current connection ID. Writes use a temporary file and replacement on the supported Linux platform. Names can change without moving credentials.

The existing Grok credential owner remains intact. The default ChatGPT definition continues using `assistant-codex-preview`, so the existing subscription sign-in remains valid. Each additional ChatGPT connection has a separate directory under `assistant-codex-connections/<stable-id>`. Selecting Grok does not sign out ChatGPT, and selecting one ChatGPT profile does not invalidate another.

On first load, the legacy `assistant-backend.ini` selection, runtime and model are migrated in memory. The new registry is written only when settings are saved. The old file is retained. No credentials are copied into the registry. Removing a connection removes its definition, not its stored runtime credentials or files; the existing Grok definition uses its own Sign out action instead of removal.

Preferences and connection edits are staged until OK. Cancel discards those edits, including additions/removals. Explicit sign-in/sign-out actions take effect immediately; the General page explains this distinction. Switching away from a connection during its account check is prevented, and closing Settings cancels/reaps its worker without waiting on the IDE thread.

## Multiple connections and future agents

Grok and multiple ChatGPT connections can remain configured and authenticated concurrently. The chat currently uses one selected connection at a time. This step does not start parallel agents.

Future heterogeneous agents should bind a stable connection ID at task creation rather than consulting the current chat selection later. Each managed worker already owns its runtime client, and ChatGPT profile directories are separate. Grok still has one existing account owner; supporting multiple independent Grok accounts requires extracting that owner before adding such profiles. A future scheduler must also coordinate workspace revisions and write ownership across agents. The registry does not pretend to solve those execution concerns.

## Rendering corrections

Markdown list continuation paragraphs are now recognized using the preceding list marker's content indentation. This fixes bold labels under a two-digit list item: its four-space indentation previously entered the parser's literal-text path. Standalone indented text remains literal.

Thinking timing placeholders create no visible card until non-whitespace text arrives. Empty thinking entries are omitted when saving trace history, and empty entries in older histories also remain invisible. Real summaries retain the existing Show Thinking behavior.

## Validation

The full suite contains 20 test programs. New connection tests cover migration, stable profile directories, round trips, current selection, retaining other backend definitions, and discarded edits. Settings tests construct the actual form using isolated configuration, exercise adding/selecting/saving connections, verify General-page bounds, and verify Cancel preserves saved state. The Connections and General pages were also reviewed from captured GUI images.

Markdown regressions cover item 9 followed by item 10 with indented bold labels, alongside preservation of standalone literal indentation. Trace view tests check that empty thoughts have no card or saved-history entry, and that a card appears when summary text arrives.

Additional regressions check model-advertised effort choices and removal of unsupported values, per-connection effort/approval persistence, explicit effort serialization through both client and managed worker, approval denial, edits/project changes/cancellation during approval, build approval, and mode restrictions under automatic approval. All 20 programs passed and the full package compiled with range/overflow checks; logs: `/tmp/laz-settings-final`. The GUI tests required local-display access. No live model request was made in this revision.
