# Local-variable rename previews and transactions

Implemented and extended 11 September 2026 as the first semantic refactoring transaction in the assistant revision plan. This is a limited operation within the larger P6 work, not general project-wide rename support.

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

Old and new names must be plain ASCII Pascal identifiers of at most 127 characters. Keywords, `Self`, `Result`, escaped identifiers and case-only renames are rejected. To avoid capture, the new name must not already occur as an identifier in active Pascal code, including escaped spellings such as `&ItemCount`. CodeTools tokenization excludes comments, strings and inactive branches from this check. Active code elsewhere in the same unit still causes a conservative rejection; scope-specific name resolution remains future work.

The source may contain ordinary `MODE`, `CODEPAGE` and resource directives; `H`, `R`, `Q` and `B` switches with `+`/`-`; and `LONGSTRINGS`, `RANGECHECKS`, `OVERFLOWCHECKS`, `BOOLEVAL`, `WARNINGS`, `HINTS` and `NOTES` with `ON`/`OFF`. Directive names and values are case-insensitive and may be separated by whitespace, including tabs.

Conditional directives (`IF`, `IFDEF`, `IFNDEF`, `IFOPT`, `ELSE`, `ELSEIF`, `ENDIF`, `IFEND`) are allowed outside the selected routine's complete physical source range. A routine wholly inside an active conditional branch can be renamed; alternative routines in other branches remain unchanged. Any conditional directive inside the selected routine, including its declarations or nested routines, rejects the preview. This avoids silently omitting inactive uses of the selected local variable.

Includes, defines, macros and other unsupported directives remain rejected throughout the file, including inactive branches. CodeTools raw tokenization distinguishes actual directives from quoted/commented examples and checks conditional nesting. Active-source tokenization detects real assembly and identifier collisions; the word `asm` in comments or strings is harmless. Actual assembly remains unsupported. These checks use the IDE CodeTools configuration and do not claim to rename every alternative implementation across configurations.

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

The initial conflict/directive prerequisite is complete: comments/strings no longer cause false conflicts, common switches are supported, and conditionals outside the selected routine are handled. Next broaden semantic conflict analysis and qualify additional symbol scopes; active-code collisions are still checked conservatively across the unit. Project-wide renames require complete reference/resource discovery, snapshots of every affected input, reviewed multi-file change sets, and recovery that restores only unchanged assistant-owned edits. Parameter signatures, overloads, exported symbols and `.lfm` bindings remain separate qualification cases. Durable refactoring journals, Grok broker migration, dependency-complete build evidence and managed continuation remain open plan items.

## Conflict and directive qualification (11 September 2026)

Replaced substring/word scans with CodeTools token readers. The selected routine's syntax node is mapped back to physical source boundaries before inspecting raw directives, so inactive text inside that routine cannot be silently omitted. Name and assembly checks run over configured Pascal tokens. Apply continues to recompute the exact preview after approval; if changed IDE defines hide the selected declaration, it fails without editing.

New real-CodeTools/SynEdit regressions cover comments, strings, nested/line comments containing directive-looking text, compiler switches, escaped-name collisions, real assembly, macro and inactive-include rejection, conditional sections in unrelated routines, multiline routine boundaries, inactive declarations, application and Undo within a conditional wrapper, and define changes during approval.

Validation: all 22 assistant test programs and the package build passed with range/overflow checks. Logs: `/tmp/laz-assistant-rename-context`. No live model request was made. Rebuild/restart Lazarus to use the updated tools; the preview/apply arguments are unchanged.
