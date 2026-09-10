# CodeTools declaration lookup

Implemented 10 September 2026 as the next semantic-navigation step in the assistant revision plan.

## Available workflow

The ChatGPT broker now exposes `lazarus_find_declaration` in Ask, Plan and Build. It resolves a Pascal reference using Lazarus CodeTools without changing files, opening the target or moving the editor caret. The native Grok registry has not yet been migrated to this tool.

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

Find references, richer symbol context, semantic rename previews, designer transactions and Grok broker migration remain open. Source/build evidence and durable managed continuation remain separate work items. Declaration lookup alone does not establish that a semantic refactoring or build is correct.

Validation: all 22 assistant test programs and the full package build passed with range/overflow checks; logs: `/tmp/laz-assistant-declarations`. Tests use real CodeTools, mock IDE interfaces and fake runtime processes. No live model request was made for this revision.

The final shared-manager guard also passed a targeted CodeTools-test rerun and package rebuild.
