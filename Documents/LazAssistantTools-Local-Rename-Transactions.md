# Local-variable rename previews and transactions

Implemented 11 September 2026 as the first semantic refactoring transaction in the assistant revision plan. This is a limited operation within the larger P6 work, not general project-wide rename support.

## Workflow

The shared broker exposes these tools to ChatGPT:

| Tool | Modes | Result |
| --- | --- | --- |
| `lazarus_preview_local_rename` | Ask, Plan, Build | Exact declaration/use edits and a one-use preview token; no source changes |
| `lazarus_apply_local_rename` | Build | Apply the stored changes to the editor, preserve native Undo, return a fresh revision; no save |

Read or open the source buffer first. Pass its current revision, a position on either the variable declaration or a use, and the proposed name:

```json
{
  "path": "Source/Main.pas",
  "revision": "<current buffer revision>",
  "line": 42,
  "column": 7,
  "new_name": "ItemCount"
}
```

Coordinates are one-based UTF-8 byte positions. The preview contains `preview_id`, `path`, `sourceRevision`, `applied: false`, `saved: false`, and a `rename` object. Its `changes` array identifies each exact line/column, old/new identifier text, and whether the occurrence is the declaration. Full proposed source remains in the broker rather than being accepted back from the model.

After reviewing those changes in Build mode, apply with:

```json
{"preview_id": "<token from the preview>"}
```

The result identifies the applied preview, reports `bufferUpdated` and `saved: false`, and supplies the actual editor text and its new revision. Saving uses the existing explicit save tool. One Lazarus Undo restores the rename; previous editor Undo history is preserved by the shared editor primitive.

Each broker run retains only one pending rename. Another preview attempt replaces it. Applying consumes the token even if approval is declined or validation fails. Cancellation and starting another run clear it. Previews from Ask/Plan must be regenerated in a Build run before application; they are not durable cross-conversation transactions.

## Supported semantics and limits

CodeTools must identify a routine-local `var` declaration in the queried standalone Pascal editor. Declaration and references are resolved through the IDE's existing synchronized CodeTools cache and project settings. Nested-routine captures are included; unrelated same-name variables, comments and strings are excluded. Multiple variables in one declaration are handled individually.

Parameters, fields, constants, procedure/type names, global/exported symbols, included source files, and form-resource changes are unsupported. `.inc` files and references crossing a physical source boundary are rejected. There is no truncated or partial rename preview.

Old and new names must be plain ASCII Pascal identifiers of at most 127 characters. Keywords, `Self`, `Result`, escaped identifiers and case-only renames are rejected. To avoid capture, the new name must not already occur as a word anywhere in the source, including comments and strings. This deliberately rejects some otherwise valid renames until richer conflict analysis is implemented.

The source may contain ordinary `MODE`, `H+`/`H-`, `R+`/`R-`, resource and `CODEPAGE` directives. Other directives, including conditional compilation, includes and macros, are rejected. The check is conservative even for directive-looking text or the word `asm` inside comments/strings. This first implementation does not claim to cover inactive branches or assembly references.

Source and resulting text are limited to 1 MiB; a preview contains at most 200 distinct occurrences and 64 KiB of edit metadata. Only one additional before/after source pair is retained. CodeTools calls remain synchronous under the existing global reentry guard; these size limits are not a hard parsing timeout or an immutable transitive-dependency snapshot.

## Apply and failure handling

Apply checks run/project identity and the exact original source before requesting the connection's normal approval. Ask permissions show current and proposed source in the existing review dialog; Auto/Always still require Build mode and a valid preview.

After approval, the broker checks the source again and recomputes the semantic preview under current IDE settings. Both the proposed text and edit metadata must match the reviewed result. It then reserves snapshot capacity and uses the shared version-checked editor update. No CodeTools source-change cache is applied directly.

The common editor commit path reads back actual text to account for SynEdit newline normalization. Cancellation, run replacement or exceptions during mutation invalidate the old snapshot safely and report that the buffer needs inspection. They do not claim that no change occurred or attempt to overwrite concurrent user edits. Native Undo remains available. There is no automatic save, compile, disk rollback or multi-file transaction in this step.

## Validation

All 22 assistant regression programs and the full package build passed with range/overflow checks. Logs: `/tmp/laz-assistant-local-rename`. A final resource-directive correction also passed a targeted CodeTools regression and package rebuild.

`AssistantCodeToolsTest` now uses real CodeTools and real SynEdit together for declaration/use previews, semantic filtering, nested captures/shadowing, multiple variable declarations, UTF-8/tab locations, exact application, one-step Undo, stale/consumed tokens, mode restrictions, approval denial, user edits, cancellation, project changes, unsupported declarations/names/directives and occurrence limits.

`AssistantEditorEditsTest` additionally injects cancellation, run replacement and an exception after editor mutation. These cases return explicit failure with no stale revision or snapshot-index error, while preserving native Undo.

No model request was made for these tests. After rebuilding/restarting Lazarus, try in Build: “Preview renaming local variable Counter in procedure Test to ItemCount using Lazarus CodeTools, then apply the preview without saving.” Inspect the edits and exercise Undo.

## Next work

Broaden conflict and directive handling before expanding symbol scope. Project-wide renames require complete reference/resource discovery, snapshots of every affected input, reviewed multi-file change sets, and recovery that restores only unchanged assistant-owned edits. Parameter signatures, overloads, exported symbols and `.lfm` bindings remain separate qualification cases. Durable refactoring journals, Grok broker migration, dependency-complete build evidence and managed continuation remain open plan items.
