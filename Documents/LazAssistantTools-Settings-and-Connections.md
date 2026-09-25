# Assistant settings and connections

Implemented 9 September 2026.

## Settings layout

The assistant no longer adds a Backend menu. Settings opens one resizable form with two pages:

- **Connections:** saved connection names, connection-specific account/model controls, and **Use for current chat**. Selecting a row edits that connection; it does not automatically switch the chat. **OK** saves the chosen connection and preferences. The model label in the assistant footer also opens Settings.
- **General:** automatic IDE context, the Grok context rollover preference, and the existing shared spell-checker controls (engine, language, library and dictionary location). The context preference now also applies to automatic context attached to Codex requests.

ChatGPT sign-in and model discovery are embedded in the Connections page. They remain asynchronous, use subscription authentication, and keep the pinned runtime and Lazarus tool restrictions. Grok retains its established browser sign-in, model list, endpoint, skill, reasoning and approval settings in its own connection details. Opening Settings no longer initiates Grok model discovery; Refresh list explicitly requests it.

## ChatGPT reasoning and tool permissions

Each ChatGPT connection has its own reasoning level and usage permissions. **Check / refresh models** obtains `supportedReasoningEfforts` for each model from the subscription runtime. The list always includes **Model default**, which omits the request's effort override. Selecting a different model removes unsupported choices; a saved value remains visible before discovery. Explicit choices are sent as `turn/start.effort`. Reasoning effort controls model work; **Show Thinking** controls visibility of whatever summary the model supplies.

- **Ask** (default): read operations proceed; new-file creation, buffer replacement, saving and starting a build require an Allow once response. The review shows the exact current and proposed text for replacements, the current content for saves, the complete proposed new-file content, or the build operation. Decline has no write/build effect.
- **Auto:** allow the registered project tools within the active mode.
- **Always:** allow registered tools without prompts. Because the current Codex registry contains only bounded project tools, Auto and Always currently have the same effect. Neither enables arbitrary runtime tools.

Ask remains read-only under all three permission choices. Plan can create, edit and save project Markdown files; other file changes and builds require Build mode. Runtime isolation and subscription-only authentication are independent of this setting. Approval is followed by run/project validation; buffer adapters still compare the approved text immediately before mutation. Build status polling does not prompt again. Settings cannot change while a chat request is running.

## Connection identity and persistence

Connection definitions and the current selection live in the `assistant` section of `<primary-config>/LazWorkflow.json`. Each connection has a stable id, display name, backend (`grok` or `codex`), model, thinking, and approval (`ask`, `auto`, `always`). Grok also stores API base, skill, and OAuth tokens. Codex stores the executable path only. The built-in Grok connection cannot be removed. A save replaces that section through a temporary file and rename. On Unix the file mode is `0600`. Other keys in the document, including `repository` and `spell`, are left untouched.

Every Codex connection uses `<primary-config>/codex/<connection-id>/`. That path is derived only. Opening Settings or saving a connection does not create it. Launch rewrites `config.toml` from the fixed policy. Runtime credential files are not copied into the JSON. Removing a connection removes its definition only; deleting the profile directory is a separate explicit action. Selecting Grok does not sign out ChatGPT, and selecting one ChatGPT profile does not invalidate another.

Legacy settings filenames are not read and are not migrated. A missing document means defaults.

Preferences and connection edits are staged until OK. Cancel discards those edits, including additions and removals. Explicit sign-in and sign-out take effect immediately. Switching away from a connection during its account check is prevented, and closing Settings cancels its worker without waiting on the IDE thread.

## Multiple connections and future agents

Grok and multiple ChatGPT connections can remain configured and authenticated concurrently. The chat currently uses one selected connection at a time. This step does not start parallel agents.

Future heterogeneous agents should bind a stable connection ID at task creation rather than consulting the current chat selection later. Each managed worker already owns its runtime client, and ChatGPT profile directories are separate. Grok still has one existing account owner; supporting multiple independent Grok accounts requires extracting that owner before adding such profiles. A future scheduler must also coordinate workspace revisions and write ownership across agents. The registry does not pretend to solve those execution concerns.

## Rendering corrections

Markdown list continuation paragraphs are now recognized using the preceding list marker's content indentation. This fixes bold labels under a two-digit list item: its four-space indentation previously entered the parser's literal-text path. Standalone indented text remains literal.

Thinking timing placeholders create no visible card until non-whitespace text arrives. Empty thinking entries are omitted when saving trace history, and empty entries in older histories also remain invisible. Real summaries retain the existing Show Thinking behavior.

## Validation

Connection tests cover the JSON round trip, derived profile directories, current selection, retaining other connections, discarded edits, and ignoring legacy filenames. Settings tests construct the actual form using isolated configuration, exercise adding/selecting/saving connections, verify General-page bounds, and verify Cancel preserves saved state. The Connections and General pages were also reviewed from captured GUI images.

Markdown regressions cover item 9 followed by item 10 with indented bold labels, alongside preservation of standalone literal indentation. Trace view tests check that empty thoughts have no card or saved-history entry, and that a card appears when summary text arrives.

Additional regressions check model-advertised effort choices and removal of unsupported values, per-connection effort/approval persistence, explicit effort serialization through both client and managed worker, approval denial, edits/project changes/cancellation during approval, build approval, and mode restrictions under automatic approval. All 20 programs passed and the full package compiled with range/overflow checks; logs: `/tmp/laz-settings-final`. The GUI tests required local-display access. No live model request was made in this revision.

## Runtime selection and extension updates (10 September 2026)

ChatGPT connection settings now include **Browse** and **Auto-detect** beside the Codex executable. Opening a connection with a missing or non-executable saved path searches the installed locations again, reports any replacement and stages it until OK. Valid custom paths are preserved. The account profile, model, reasoning and approval preferences remain attached to the same connection.

The installed VS Code extension moved from `26.5901.22334` to `26.5903.71938`, which explained the reported missing-executable message. Its runtime is 0.153.4; the preview now accepts that exact version alongside 0.153.0, following offline schema and signed-out startup checks. Other versions still require qualification. See [runtime evidence](LazAssistantTools-Codex-Implementation.md).

The settings regression passed missing-path recovery, existing-path preservation, connection preference retention, Save/Cancel behavior and a captured layout check. All 22 assistant programs and the package build passed across the full run and targeted reruns. After rebuilding/restarting Lazarus, open the ChatGPT connection, use **Check / refresh models**, then **OK** to save the recovered path.
