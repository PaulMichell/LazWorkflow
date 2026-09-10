# CodeTools navigation and symbol inspection

Implemented 10 September 2026 as the next semantic-navigation step in the assistant revision plan.

## Available workflow

The ChatGPT broker exposes `lazarus_find_declaration`, `lazarus_symbol_context` and `lazarus_find_references` in Ask, Plan and Build. It resolves a Pascal reference using Lazarus CodeTools without changing files, opening the target or moving the editor caret. The native Grok registry has not yet been migrated to these tools.

1. Use `lazarus_open_buffer` for a closed source file, or `lazarus_read_buffer` for an existing editor.
2. Locate the identifier in the returned text and retain the returned revision.
3. Call `lazarus_find_declaration` with `path`, `revision`, `line` and `column`.
4. Inspect the returned declaration location. Use the normal project read/open tools for additional context; editing the target requires its own fresh buffer revision.

Lines and columns are one-based. Columns count UTF-8 **bytes**, with a tab counting as one byte, matching CodeTools coordinates. Positions inside a multibyte character, outside a line, or outside the current buffer are rejected.

```json
{
  "path": "Source/Main.pas",
  "revision": "<revision from the preceding buffer read>",
  "line": 42,
  "column": 7
}
```

The result contains the source revision and a declaration object with its path, line, column, `columnEncoding`, `inProject` and a bounded `lineText`. For library declarations outside the project, only location metadata is returned; `lineText` is empty. This does not expand the existing project file-reading boundary.

## Symbol context

`lazarus_symbol_context` accepts the same path/revision/line/column arguments. Its `symbol` result contains the declaration location, source context (three lines either side), declaration context (five lines either side), and the CodeTools smart hint. Snippet lines are limited to 256 Unicode characters, with `linesTruncated` reported; hints are limited to 2,000 characters. External declarations return location metadata only, with null declaration context and an empty hint. Context does not issue a target edit revision.

## Reference search

`lazarus_find_references` adds required `search_paths` (1–32 explicit project Pascal files) and optional `max_results` (1–200, default 100). Read/open the queried source first; searched files may remain closed. Canonical duplicates are removed. For example:

```json
{
  "path": "Source/Main.pas",
  "revision": "<revision from the preceding buffer read>",
  "line": 42,
  "column": 7,
  "search_paths": ["Source/Main.pas", "Source/Worker.pas"],
  "max_results": 100
}
```

The `references` result includes `declaration`, `items`, `requestedFiles`, `searchedFiles`, `failedFiles`, `truncated`, `stopReason` and `completeForRequestedFiles`. CodeTools resolves usages semantically; shadowed identifiers, comments, strings, inactive branches and the resolved declaration itself are excluded. Project include locations can appear when searching their owning unit. Form-resource usages and override-family expansion are not included; this is not a rename inventory or a whole-project completeness guarantee.

Every requested input is validated before searching. Invalid/missing input files reject the request. CodeTools failures are reported per file and do not prevent results from other files; partial coverage is explicit. CodeTools can rule out a file without fully parsing it, so `searchedFiles` is not a syntax-validation result.

The search uses synchronized unsaved buffers and refreshes directory metadata to discover newly created files. Each input is limited to 1 MiB; combined source/disk snapshots are limited to 8 MiB. Results stop at the requested count, 60 KB of reference entries, or a five-second budget checked between files. The latter cannot interrupt an individual synchronous CodeTools call. Requested inputs are rechecked afterward, including closed-file bytes, and changes reject the result. Transitive dependencies and project configuration are not captured as an immutable snapshot.

## IDE integration and checks

The adapter calls `LazarusIDE.BeginCodeTools` to synchronize unsaved editor contents into the IDE's existing CodeTools cache. It uses the actual editor's `CodeToolsBuffer` and the existing `CodeToolBoss`, preserving project defines, include/unit search paths and language configuration. It does not build a separate approximate parser or replace the IDE's define tree.

The request requires a current project-scoped Pascal editor buffer (`.pas`, `.pp`, `.p`, `.lpr`, `.dpr` or `.inc`) and an exact broker revision. The queried buffer is limited to 1 MiB. The broker rejects stale coordinates before invoking CodeTools and discards results if the source text, project identity or run changes during the operation. Busy/unprepared CodeTools, invalid positions and unresolved declarations produce explicit errors without invoking the IDE's error-jump UI.

CodeTools runs synchronously on the IDE thread. The adapter rejects reentry and uses the IDE's preparation guard; it does not access the global manager from a worker thread. Dependency parsing is governed by the IDE configuration and is not bounded by the queried-buffer size limit. This step does not claim an immutable dependency/configuration snapshot or a hard lookup timeout.

IDE callbacks can cancel an assistant run. The managed worker's detached reaper now waits for an active tool handoff to return before freeing its state. The panel rejects nested polling and stops processing the old result when the run was replaced or cancelled during the callback. The wait is in the reaper, not a new main-thread join.

## Tests

`AssistantCodeToolsTest` uses real CodeTools with mock IDE interfaces and disposable files. It covers unsaved source revisions, local and cross-unit declarations, an unsaved dependency protected from disk reload like an IDE editor, conditional-compilation defines, changed defines, UTF-8/tab byte positions, malformed and stale coordinates, IDE preparation failure, reentry through a second adapter, and source/project/cancellation changes during lookup. It verifies that lookup neither creates nor saves the queried source.

`AssistantCodexClientTest` additionally cancels a worker from inside an IDE tool callback and starts its destruction on another thread, proving that destruction waits for the handoff to finish.

Full suite command:

```sh
python3 Source/Tests/run_assistant_tests.py \
  --lazarus-root /path/to/built/Lazarus \
  --output-dir /tmp/laz-assistant-declarations \
  --gui
```

## Remaining work

Reference lookup and symbol context are implemented. Next: reviewable semantic rename/refactoring previews and transactions. Designer transactions and Grok broker migration remain open. Source/build evidence and durable managed continuation remain separate work items. Declaration lookup alone does not establish that a semantic refactoring or build is correct.

Validation: all 22 assistant test programs and the full package build passed with range/overflow checks; logs: `/tmp/laz-assistant-declarations`. Tests use real CodeTools, mock IDE interfaces and fake runtime processes. No live model request was made for this revision.

The final shared-manager guard also passed a targeted CodeTools-test rerun and package rebuild.

## Reference/context validation (10 September 2026)

Extended the real-CodeTools regression program to cover semantic reference filtering, deduplicated scopes, explicit result limits, closed/newly created files, parser failures followed by successful files, missing files, traversal, invalid scopes/limits, unsaved context/hints, stale revisions, source changes and cancellation. All three tools are advertised in every mode.

All 22 assistant test programs and the full package build passed with range/overflow checks; logs: `/tmp/laz-assistant-references`. No live model request was made for these navigation changes. After rebuilding/restarting Lazarus, ask ChatGPT to find usages of a project identifier in a named set of units and explain the declaration with symbol context.
