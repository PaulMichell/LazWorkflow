# LazWorkflow Project Review

**Review date:** 8 August 2026  
**Scope:** All four Lazarus packages, their package metadata, documentation, forms, and tracked Pascal source (approximately 31,000 lines).  
**Packages:** `LazWorkflowCommon`, `LazMarkdown`, `LazRepositoryTools`, and `LazAssistantTools`.

## Executive summary

The project has progressed well beyond the "Phase 0" label in the root README. All four packages compile successfully with the current Lazarus installation, and the code shows a coherent product direction: shared workflow events, a capable Git surface, Markdown rendering, and a project-aware assistant.

The main remaining concerns are responsiveness and regression protection at package boundaries. The first hardening pass addressed the highest-risk Markdown, build, credential, path, Git-process, and streaming defects, but several Git and assistant operations still run synchronously on the IDE thread and there is no automated test suite to catch regressions in these high-risk paths.

### Priority findings

| Priority | Finding | Affected package(s) |
|---|---|---|
| **P0** | An existing Markdown window is force-reloaded from disk, which can discard unsaved edits. | LazAssistantTools |
| **P0** | Quiet assistant builds do not reliably save changed IDE buffers, so `lazbuild` can compile stale disk content. | LazAssistantTools |
| **Fixed** | Assistant credentials are now session-only, legacy plaintext secrets are purged, and Windows TLS DLL discovery no longer includes the current/project directory. | LazAssistantTools |
| **P0** | Lexical path containment can be bypassed through a symlink/junction inside the project. | LazAssistantTools |
| **P1** | Git stderr is not drained while a process runs; a child can block forever when the pipe fills. | LazRepositoryTools |
| **P1** | Git status/diff parsing is not safe for quoted, non-ASCII, newline-containing, or rename paths. | LazRepositoryTools |
| **P1** | Many Git, HTTP, model, tool, and build operations block the Lazarus UI and have no timeout/cancellation. | Repository/Assistant |
| **P1** | Event listeners are invoked while the event-bus lock is held, allowing re-entrant deadlocks. | LazWorkflowCommon |
| **P1** | Stream retries, heuristic text de-duplication, and unbounded tool-call/SSE buffers can corrupt output or exhaust memory. | LazAssistantTools |
| **P1** | Repository detail workers leak, and stopping a worker that is waiting in `Synchronize` can deadlock the UI. | LazRepositoryTools |
| **P1** | No tracked automated tests exist, despite the README advertising a `Source/Tests` directory. | All packages |

### Recommended release gate

Before treating the packages as production-ready, fix the P0 items, move long-running work off the IDE thread with reliable cancellation, switch Git status/name handling to NUL-delimited machine-readable output, and add focused automated tests for persistence, paths, subprocesses, stream parsing, and partial Git patches.

## Implementation status — 8 August 2026

This review now also records the first hardening pass. The original findings below
remain intact as the audit baseline; this section states which items have changed in
the current working tree.

### Fixed or materially hardened

| Package | Changes completed in this pass |
|---|---|
| **LazWorkflowCommon** | Event listeners are snapshotted and invoked outside the lock; logger configuration is synchronized and callbacks run outside its lock; warning/error messages have a Lazarus debug-log fallback; the package is runtime-only and no longer depends on `IDEIntf`. |
| **LazMarkdown** | Initialized the email parser's previous-character state; completed renderer fallbacks; removed the compiler-confirmed unreachable renderer branch. |
| **LazRepositoryTools** | Drains stdout and stderr concurrently; parses status as NUL-delimited porcelain; reports stderr on Git failures; fixes worker cleanup and `Synchronize` shutdown deadlocks; avoids full-tree scans unless clean files are requested; refreshes when the dirty file set changes; shows untracked files by default; supports all merge parents; publishes accurate commit/checkout data; rejects lexical repository path escapes; preserves patch bytes, associates no-final-newline markers correctly, and runs `git apply --check`; accepts existing empty clone folders; makes legacy settings migration one-time; prevents stale-scroll cancellation from dropping unrelated UI callbacks; removes the unused `SynEditDsgn` dependency. |
| **LazAssistantTools** | Prevents forced reload of open Markdown and reports deleted/reappearing files; saves IDE buffers before quiet builds and aborts on save failure; removes current-directory TLS DLL search; requires HTTPS endpoints; makes OAuth randomness fail closed and bounds callback headers; propagates WinINet read errors; keeps all provider credentials in process memory and purges legacy persisted secrets; adds an extensible provider registry with switchable xAI OAuth and OpenAI API-key sessions plus per-provider endpoint/model settings; unifies project roots; rejects symlink/junction path components; validates archive IDs and rolls back failed archive switches; gives Ask/Auto/Always distinct approval behavior with Ask as the default; makes the raw tool executor private; disables automatic source-context attachment by default; validates skill names; discovers all supported Markdown extensions; bounds SSE/tool/response buffers; requires a terminal stream event; prevents retry after partial payload; preserves legitimate repeated output; coalesces queued stream snapshots; corrects the tool-round limit; removes the two-write workflow stop. |
| **Documentation/package metadata** | Added `LazMarkdown` and the correct build order to the README, updated the project status, and removed unnecessary design-time dependencies. |

All four packages compile after these changes. `LazWorkflowCommon`, `LazMarkdown`, and
`LazAssistantTools` compile without warnings. `LazRepositoryTools` has two remaining
warnings for an experimental Lazarus highlighter hook and the deprecated
`TSynEdit.OnSpecialLineColors` compatibility API.

### Still open

The remaining work is larger or needs a broader architectural pass:

- Persistent sign-in is intentionally deferred. xAI OAuth tokens and OpenAI API keys
  now last only for the current Lazarus process and are never written by this package.
  A future optional “Remember me” feature should use native secure stores on each OS,
  with session-only authentication remaining the portable default.
- Long-running Git, non-Windows HTTP, tool, model-list, build, and file-search operations
  still need a shared cancellable background job abstraction with deadlines.
- Assistant/tool/plan/history writes still need one cross-platform atomic replacement
  service, and legacy delimiter sessions should be retired in favor of versioned JSON.
- Remote editing remains non-transactional; fetch and push URLs still need separate UI.
- Human-readable diff parsing, very large diff/document limits, and binary/encoding
  handling need a larger model/UI refactor.
- UI-thread event dispatch, shutdown registration tokens, visible operation/log UI,
  privacy/context previews, edit-conflict UX, accessibility/theme/DPI work, and automated
  regression tests remain outstanding.

## Validation performed

All four `.lpk` files were built with `C:\lazarus\lazbuild.exe` on Win64 using FPC 3.3.1. Every build completed successfully.

Compiler warnings worth addressing:

- `markdown.utils.pas:735`: local variable `prev` may be uninitialized.
- Markdown renderers: unreachable code and incomplete `case` statements in canvas, HTML, FPDoc, and LaTeX renderers.
- `GitGraphModel.pas:159` and many locations in `GitDiffView.pas`: pointer-to-signed-integer conversions.
- `GitDiffView.pas`: experimental/deprecated SynEdit APIs.
- `AssistantSkills.pas:113`: managed function result may be uninitialized.
- Unreachable code in `AssistantTools.pas:341`, `AssistantService.pas:197`, `AssistantSession.pas:58`, and `ProjectAssistantForm.pas:3843`.

This was a static source review plus package compilation. It did not exercise OAuth, remote Git hosts, model streaming, or every window interactively inside a running Lazarus IDE. Those paths need the regression tests proposed below.

---

## LazWorkflowCommon

### Bugs and correctness risks

1. **P1 — Re-entrant event delivery can deadlock.** Every `TWorkflowEventBus.Notify...`/request method takes `FLock` and invokes listeners before releasing it (`Source/LazWorkflowCommon/WorkflowEvents.pas`). If a listener publishes another event or adds/removes a listener, it tries to acquire the same critical section. Copy the listener references under the lock, release it, and then invoke the snapshot.

2. **P1 — “Thread-safe” registration does not make LCL callbacks thread-safe.** Publishers can call the bus from workers, but several listeners update IDE/LCL state. Either marshal UI-facing notifications with `TThread.Queue`, provide separate UI and worker events, or clearly enforce main-thread publication.

3. **P2 — Logging silently disappears unless a consumer installs `OnLog`.** `WorkflowLogger` has no default Lazarus logger/file sink, and callback exceptions are swallowed. Several error dialogs tell the user to inspect a log that may not exist. Provide an IDE Messages/log-file sink and expose its location in error dialogs.

4. **P2 — Logger state is not synchronized.** `MinLevel` and `OnLog` can be read or changed concurrently. Snapshot both under a lock, then invoke the handler outside it.

5. **P2 — Package lifetime relies on global singleton finalization order.** The event bus and logger are created/freed in unit initialization/finalization while other installed packages retain listener references. Add explicit registration tokens/disconnect methods and make shutdown idempotent.

### Optimizations

- Reuse a private “snapshot listeners” helper rather than repeating lock/list traversal in every notification method.
- Coalesce high-frequency document/status events when only the latest state matters.
- Avoid serializing slow Git or assistant listeners behind the event bus lock.

### Simplifications

- `IAssistantToolCallRequested` appears to be declared but unused. Remove it until an event-bus tool-call bridge exists, or implement and test that bridge.
- `LazWorkflowCommon.lpk` depends on `IDEIntf`, although the shared units use LCL/classes rather than IDE APIs. If confirmed by a clean package build, make it a runtime-only package without `IDEIntf`; this reduces coupling and install/rebuild cost.
- Centralize singleton ownership in one lifecycle unit instead of independent unit initialization blocks.

### User-experience suggestions

- The status footer has a fixed 22-pixel height and three aligned labels. It can clip under high DPI/large fonts and long paths can crowd out state. Use scaled/auto-sized dimensions, ellipsis, and full-text hints.
- Add severity icons and an accessible status description rather than communicating state by terse text alone.
- Make log access discoverable from the footer or Tools menu.

---

## LazMarkdown

### Bugs and correctness risks

1. **P1 — `IsEmailLike` reads `prev` before initialization.** In `Source/LazMarkdown/Src_3_2/markdown.utils.pas:715-745`, `prev` is tested at line 735 and again after the loop. Initialize it before iteration and add empty/minimal-address tests. This is a compiler-confirmed warning and can produce nondeterministic parsing.

2. **P2 — Renderer `case` statements are incomplete.** Warnings in canvas, HTML, FPDoc, and LaTeX renderers mean a new or unexpected enum value can be silently omitted. Add explicit branches or an `else` that produces a safe fallback and diagnostic.

3. **P2 — The vendored fork has weak provenance.** `ORIGIN.md` describes two local fixes, but it does not pin an upstream repository commit/tag or preserve the changes as small patch files. Future upstream merges will be difficult to audit. Record the exact upstream URL/revision, license, local patch set, and update procedure.

4. **P2 — Local fixes lack regression tests.** The bare-ampersand and table-index fixes are precisely the sort of changes that can regress during a vendor refresh. Add golden parser/render tests for both.

### Optimizations

- The upstream canvas renderer still notes painting beyond the visible region. Cache parsed/layout output and render only the viewport for large assistant responses and plans.
- Add input-size guards and progressive rendering so a very large Markdown document cannot freeze the IDE.
- Cache theme/font metrics and invalidate only when the document or theme changes.

### Simplifications

- Prefer a pinned upstream dependency plus a minimal reviewed patch series over maintaining a complete anonymous source fork.
- Keep shared parsing independent of the canvas control so parser tests do not require an LCL window.
- Resolve the unreachable-code warnings and make all renderer fallbacks consistent.

### User-experience suggestions

- Derive colors, fonts, selection, and links from the Lazarus IDE theme; provide a high-contrast fallback.
- Preserve scroll position across re-render and support keyboard link traversal, text selection/copy, find, and in-document anchors.
- Show a friendly “document too large” or progressive-render state rather than appearing frozen.
- The vendored README describes component-palette installation while `LazMarkdown.lpk` is a runtime package. Align the documentation with how LazAssistantTools consumes it.

---

## LazRepositoryTools

### Bugs and correctness risks

1. **P1 — Git processes can deadlock on stderr.** `TGitService.RunGitBinary` drains stdout while the child is running but waits until exit to drain stderr (`Source/LazRepositoryTools/GitService.pas:262`). A verbose command can fill the stderr pipe and block both parent and child. Read both streams concurrently, merge them when ordering is unimportant, or use worker readers.

2. **P1 — Git status parsing is unsafe for real filenames.** `ListStatus` parses line-oriented porcelain text and manually strips quotes. It does not decode Git C quoting, and `" -> "` cannot safely distinguish a rename separator from filename content. Use `git -c core.quotePath=false status --porcelain=v2 -z` and parse NUL-delimited records. Apply the same rule to diff/file parsers.

3. **P1 — Long-running operations freeze the IDE.** Clone, fetch, pull, push, commit, checkout, diff/show, selected-commit details, and some refreshes execute synchronously. `poNoConsole` also hides credential prompts. Move commands to a shared job runner with progress, timeout, cancellation, and credential/error reporting.

4. **P1 — Detail-loading threads leak.** `ApplyDetailsLoaded` marks loading complete but does not free/reset `FDetailThread`; the next load overwrites the pointer (`ManageRepositoryForm.pas:607-730`). Free the completed worker in a safe queued completion path or use `FreeOnTerminate` with generation-owned result data.

5. **P1 — Stopping workers can deadlock the main thread.** `StopDetailThread`/index shutdown calls `Terminate` and `WaitFor`, while a worker can be blocked in `Synchronize`. Replace `Synchronize` with `Queue` plus generation IDs and never wait on the UI thread for code that needs the UI thread to complete.

6. **P1 — File refresh scans the whole repository on the UI thread.** `RefreshFilesList` runs Git and `FindAllFiles` recursively even when “show clean” is disabled (`ManageRepositoryForm.pas:1318`). Large/generated trees will hang Lazarus. Use status output alone unless clean files are requested; enumerate in a cancellable worker and exclude `.git`, ignored, build, and cache directories.

7. **P1 — Auto-refresh misses changes while the repository remains dirty.** The refresh snapshot mainly compares HEAD/branch/clean state. Editing or staging one dirty file while another already keeps `Clean=False` need not update the Files tab. Compare a NUL-porcelain digest or relevant index/worktree metadata.

8. **P1 — Partial-patch construction is fragile.** `GitDiffView.pas` combines a custom diff parser, selection model, patch writer, preview, and highlighter. In particular, `\ No newline at end of file` markers can be copied without reliably retaining the associated selected change. Extract a tested patch model and validate generated patches with `git apply --check` before applying.

9. **P1 — The diff model does not robustly represent unusual paths.** Quoted paths, renames/copies, tabs/newlines, and binary entries are inferred from human-readable text. Request machine-readable name/status data separately and associate it with patch records.

10. **P2 — Octopus merge edges are silently dropped.** `GitGraphModel` stores at most four parents. Commits with more parents lose graph edges and report an incomplete parent count. Use a dynamic parent array.

11. **P2 — Pointer-packed integers are type-unsafe.** `GitGraphModel.pas:159` and many `GitDiffView.pas` locations store line numbers/indexes as pointers and cast them to signed integers. This produces compiler warnings and is brittle across architectures. Use typed generic lists or dynamic integer arrays.

12. **P2 — Commit events publish inaccurate metadata.** Checkout/commit event construction hard-codes or guesses parent count, summary, author, and sometimes places a ref name where the interface promises a SHA. Query the committed object once and publish an accurate `TGitCommitInfo`; emit working-tree/head events consistently for branch creation and checkout.

13. **P2 — Repository paths are constructed without containment validation.** `WorkingTreeFullPath` (`GitService.pas:606`) lexically appends caller input. Public read methods should reject `..` escapes and canonical paths outside the repository.

14. **P2 — Patch text is round-tripped through `TStringList`.** This can normalize encoding/EOLs and make a valid patch invalid. Write the exact UTF-8 byte sequence to a uniquely named temporary file, check every I/O result, and clean it in `finally`.

15. **P2 — Remote editing is non-transactional.** `GitRemotesForm.SaveToGit` removes old remotes before all additions/updates succeed (`GitRemotesForm.pas:297`). A later error leaves a partially modified repository, and rename-via-remove/add can lose config. Validate first, use `git remote rename`, apply incremental changes, and roll back or clearly report partial completion.

16. **P2 — Fetch and push URLs are conflated.** The remotes grid shows the fetch URL but can preserve a different hidden push URL. Display and edit both explicitly.

17. **P2 — Configuration migration can repeat forever.** `GitConfig` infers “not migrated” when new values equal defaults. A user intentionally choosing defaults can have legacy values re-applied on every load. Store a migration-version marker and perform it once.

18. **P2 — Clone rejects an existing empty destination.** This conflicts with the folder picker’s natural output and Git’s supported behavior. Accept an empty existing directory after a clear safety check.

19. **P2 — Transfer summaries scrape localized human output.** This can misclassify a successful transfer as “up to date.” Compare before/after refs or use machine-readable progress/status instead.

20. **P2 — Full-file diffs and previews are unbounded.** `-U100000`, per-change tree nodes, and whole image/blob reads can exhaust memory. Set size thresholds, lazy-load hunks, and offer an external viewer for oversized/binary data.

### Optimizations

- Introduce one asynchronous Git job service used by all forms; queue jobs per repository and cache branch/status/remote results.
- Replace repeated polling Git processes every few seconds with a debounced filesystem watcher plus a slower fallback poll.
- Build graph lanes with a SHA-to-lane map/free-list rather than repeatedly scanning all active lanes.
- Load commit metadata/diffs on demand, cancel stale selections, and cache recent commits.
- Avoid `FindAllFiles` when Git already knows the changed/untracked set.

### Simplifications

- Split the 3,200+ line `GitDiffView` into diff parsing/model, patch selection/building, syntax/overview rendering, and UI orchestration units.
- Replace mutable global `GitClient.RepoPath`/`LastError` with repository-scoped clients or methods that take an immutable working directory. The current global is easy for dialogs and background work to overwrite.
- Use structured Git commands everywhere (`-z`, explicit formats) and remove ad-hoc quote/arrow parsing.
- Remove `SynEditDsgn` from package dependencies if a clean package build confirms it is unused.
- Make `.gitignore` writes atomic and share one safe text-save helper with the assistant package.

### User-experience suggestions

- Show an operation panel with command, repository, elapsed time, progress, Cancel, and a copyable sanitized error. “See log” is not useful until a visible log exists.
- Default to showing untracked files, or make their hidden state prominent; otherwise new work is easy to miss.
- Before checkout/reset/restore, show dirty/conflicted state and affected files, with options to stash, create a branch, or cancel.
- Add separate fetch/push URL columns and validation/test-connection controls.
- After clone, offer “Open project,” “Open folder,” and “Initialize submodules.”
- Make default shortcuts conflict-aware and editable. Avoid surprising defaults such as `Ctrl+Shift+C` where it commonly means Copy in terminals/tools.
- Use theme-derived red/green colors plus icons/patterns, a visible legend, keyboard hunk navigation, and clear partial-stage feedback. Color alone is not sufficient for accessibility.
- Offer per-file/hunk undo for stage/unstage and preserve selection/scroll position after refresh.

---

## LazAssistantTools

### Bugs, security, and correctness risks

#### Credentials, transport, and OAuth

1. **P0 — OAuth access and refresh tokens were stored in plain Lazarus XML configuration.** Any process/user able to read that file could reuse them. **Current status:** fixed by making all provider credentials session-only and clearing current and legacy secret fields during configuration migration. Optional persistent sign-in remains deferred.

2. **P0 — Windows TLS DLL discovery includes `GetCurrentDir`.** `PreloadOpenSslFromDirs` in `AssistantHttps.pas` can load a matching `libssl`/`libcrypto` pair from the current directory, which may be the untrusted project. This creates a DLL search-order code-execution risk. Load only trusted application/config locations and validate architecture/version; never search the project/current directory.

3. **P0 — Filesystem containment is lexical, not canonical.** `ResolveProjectPath` (`AssistantTools.pas:375`) checks expanded strings, but a symlink/junction inside the project can resolve outside it. Canonicalize the existing target or nearest existing ancestor, reject reparse-point escapes, and re-check immediately before open/write/rename.

4. **P1 — The default approval policy does not prompt.** The default is effectively “always allow,” and `aamAuto` and `aamAlways` follow the same branch. Default to Ask. Either give Auto a narrowly defined safe-read policy and Always an explicit opt-in warning, or remove the duplicate setting.

5. **P1 — Insecure/custom endpoints can receive bearer tokens.** The editable API base is validated mostly for being non-empty. Require HTTPS, except a separately enabled localhost development mode, and restrict authorization forwarding across redirects to the same origin.

6. **P1 — Cryptographic randomness fails open.** `GrokOAuth.RandomBase64Url` falls back to ordinary `Random` when the OS RNG fails, making state/nonce/PKCE values predictable. Abort login and report the RNG failure instead.

7. **P1 — The loopback OAuth listener is easy to stall.** Header reading has no strict maximum/per-connection timeout, and the login path pumps `Application.ProcessMessages` for up to five minutes. Use an asynchronous flow, bounded request size/time, one active attempt, an ephemeral loopback port where supported, and explicit cancellation.

8. **P1 — Non-Windows “streaming” buffers the entire HTTP response.** The fphttp path fills a `TMemoryStream` before invoking chunks, so cancellation and live rendering do not work and memory is unbounded. Use a true streaming socket/client callback or a maintained cross-platform HTTP abstraction.

9. **P1 — WinINet read failures can be reported as success.** A failed `InternetReadFile` breaks the read loop without converting the request to failure, allowing truncated JSON/SSE to look complete. Propagate the OS error and reject streams lacking a valid terminal event.

10. **P1 — HTTP operations have no comprehensive connect/send/receive timeout.** Add configurable deadlines and make Abort interrupt all supported transports.

11. **P2 — Rotated refresh tokens were not persisted immediately.** **Current status:** superseded by session-only authentication; rotated credentials remain in memory and are deliberately not persisted.

12. **P2 — Signing out could restore legacy credentials on restart.** **Current status:** fixed; configuration loading purges both current and legacy persisted secrets and never restores them into a provider session.

#### Files, builds, plans, and Markdown

13. **P0 — Opening an already open Markdown document can discard unsaved edits.** `OpenMarkdownDocument` calls `ReloadFromDisk(True)` (`AssistantMarkdownForm.pas:153-166`), and assistant plan updates force viewer reloads. Before overwrite/reload, compare the buffer’s dirty/version state and offer Keep mine, Review diff/merge, or Reload. Never force replacement silently.

14. **P0 — Quiet builds can compile stale files.** `FlushOpenEditorsUnderProject` (`AssistantTools.pas:1224`) routes an editor buffer through a helper that, for an open editor, sets `SourceText` rather than writing it to disk. The subsequent external `lazbuild` can therefore see old content and falsely report success. Use the Lazarus save API and stop the build if any save fails, or build a controlled temporary snapshot.

15. **P1 — Project roots are inconsistent.** Tools/plans often prefer the main source file directory, while conversation storage prefers the `.lpi` directory and special-cases directories named `Source`, `src`, or `Units`. This can place tools, plans, and `.assistant` history in different trees. Create one canonical project-root service, default to the `.lpi` directory, and make overrides explicit.

16. **P1 — Writes are not atomic.** Tool and plan saves commonly write the destination directly. A crash/full disk can corrupt an existing file. Write to a same-directory temporary file, flush, and atomically replace while preserving encoding/EOL where required.

17. **P1 — Conversation/archive operations are not transactional.** Appending the conversation then failing to append the index leaves canonical and index state mismatched; archive activation can park the current conversation before activation fails. Treat the JSONL conversation as canonical, rebuild indexes automatically, and use temp files/journaling plus rollback for multi-file transitions.

18. **P1 — Public archive IDs are not strictly validated.** Activate/delete paths construct filenames from an `ArchiveId`; a programmatic caller could pass traversal components. Accept only generated timestamp/nonce IDs and perform canonical containment checks.

19. **P1 — Assistant history can be committed accidentally.** `.assistant/` and the legacy `.lazgrokchat-session` are not automatically excluded. They can contain prompts, source excerpts, paths, and model output. Offer to add them to `.git/info/exclude` (not necessarily the shared `.gitignore`), explain the privacy choice, and provide export/redaction controls.

20. **P1 — Legacy session serialization is delimiter-based.** Message content equal to `---MESSAGES---`, `---MSG ...---`, or `---END---` can corrupt parsing. Migrate to versioned JSON and retire the duplicate legacy transcript path.

21. **P1 — Open source/project context is sent by default.** Up to roughly 48 KB of active source plus absolute paths can be added to prompts without a per-send preview. Add a visible context chip/list, a send-without-context option, secret/ignore filters, relative-path redaction, and a first-use privacy explanation.

22. **P1 — Tool search caps results after enumerating the tree.** `FindAllFiles` can first collect a huge repository, so the 2,500-result cap does not bound work or memory. Stream enumeration, stop at the cap, ignore VCS/build/cache directories, and run it off-thread.

23. **P1 — Open-buffer edits and tool writes need explicit undo/conflict semantics.** Assigning `SourceText` does not guarantee the user-friendly, grouped undo behavior implied by the tool. Use IDE editor commands/undo groups and detect disk/buffer version conflicts.

24. **P2 — Binary rejection by extension is insufficient.** File reads use text abstractions and may normalize encoding/EOL. Detect NUL/binary content, preserve UTF-8/encoding metadata, and report unsupported files rather than mangling them.

25. **P2 — Markdown plan discovery is inconsistent.** The validator accepts `.md`, `.markdown`, and `.mdown`, while list discovery searches only `*.md`. Use the same extension set.

26. **P2 — Plan heading parsing flattens hierarchy.** `##` and `###` can become peer work items and parent body/status interpretation is surprising. Define a plan schema or configurable root/heading level and surface parsing errors in the plan UI.

27. **P2 — Plan status support is narrower than documented.** The implementation primarily recognizes a `Status:` line and does not fully implement the promised HTML-comment/checklist fallback. Align code and documentation and add parser tests.

28. **P2 — Markdown file watching is coarse.** A `FileAge`-style timestamp can miss multiple fast writes, and a deleted file can remain displayed as “Live.” Compare high-resolution time, size, and optionally a small hash; show deleted/conflict states.

#### Streaming, tools, and threading

29. **P1 — Streaming text is heuristically rewritten.** `MergeStreamText` and trailing-repeat collapse (`AssistantService.pas:460`) can remove legitimate repeated code/prose. Provider adapters should define whether events are deltas or snapshots; preserve content exactly and handle replay by event/request identity.

30. **P1 — Stream UI updates are O(n²) and can backlog.** Each token can copy full accumulated content/thinking into a queued snapshot, while queue handling shifts arrays. Throttle/coalesce to the newest snapshot at about 30–60 Hz and prioritize the final event.

31. **P1 — SSE and tool-call buffers are unbounded.** A server can send no newline, a huge tool index (causing `SetLength(FToolCalls, Idx + 1)` around lines 599-600), or endless arguments. Cap event size, tool count/index, argument bytes, and total response bytes; fail with a visible error.

32. **P1 — Retrying after partial stream data can duplicate/corrupt a response.** Accumulators are not cleanly reset for each retry. Do not automatically retry once response bytes have been accepted unless the protocol supplies resumable IDs; otherwise start a clearly separate attempt with fresh state.

33. **P1 — A clean connection close can masquerade as a complete answer.** Require `[DONE]`, a recognized `finish_reason`, or equivalent provider terminal record before executing tool calls or recording success.

34. **P1 — Tool rounds execute expensive work on the main thread.** Search, compile/build, and other actions are invoked through synchronization, freezing the UI and making Stop ineffective. Separate tool execution policy from UI presentation and run cancellable jobs in a worker, marshaling only IDE API calls.

35. **P1 — Stream-thread cleanup has unsafe ownership.** After a timeout `ClearStreamThread` can detach/leak a non-freeing thread, while shared stream-control references can race Abort/worker cleanup. Give the thread sole transport ownership, signal cancellation through a synchronized token, and join outside UI-dependent callbacks.

36. **P1 — Large-tool-call trimming breaks call/result identity.** Replacing calls with a synthetic `trimmed_args` ID while later results retain original IDs can produce an invalid next API request. Preserve every call ID and store/summarize large arguments out-of-band.

37. **P2 — Tool-round limits are off by one.** `for RoundNo := 0 to MaxToolRounds` with `MaxToolRounds = 20` allows 21 rounds (`AssistantService.pas:892-908`). Express the limit as a count and test the boundary.

38. **P2 — Two successful Markdown writes can prematurely stop a valid workflow.** The “second write” guard treats ordinary multi-document/multi-edit plans as looping. Detect repeated identical calls or use a total round/write budget with user-visible continuation instead.

39. **P2 — Response/history truncation is silent.** The 400 KB content cap and large-history trimming can omit content without explaining it to the user. Store full content where safe, show a truncation marker, and offer export/open-full-response.

40. **P2 — Synchronous side requests freeze dialogs.** Model discovery and one-shot completions run synchronously; opening settings may trigger a network request, and refreshing can mutate global service configuration even if Cancel is clicked. Fetch asynchronously into dialog-local state and commit only on OK.

41. **P2 — Skill names are used as path components without strong validation.** `LoadUserSkillBody` should only accept a name returned by discovery and must canonicalize it beneath the configured skills root. Also replace coarse timestamp caching with high-resolution metadata/hash.

42. **P2 — Direct `ExecuteAssistantTool` bypasses mode/approval policy.** It is currently wrapped in normal use but remains a public package API. Make the raw executor private or require an authorization decision/token that cannot be skipped accidentally.

### Optimizations

- Use one cancellable background-job abstraction for HTTP, tool execution, builds, file search, and side completions.
- Coalesce streamed UI updates; render Markdown after an idle interval rather than for every token.
- Lazy-load conversation turns by JSONL offset instead of loading every complete turn into memory. Keep a bounded recent-turn cache.
- Cache repository/project file indexes and invalidate them with watchers.
- Make context token-aware: send selected symbols/diffs or a compact project map rather than repeatedly attaching the full active file.
- Store tool-call payloads separately from the compact conversation history so normal requests remain small without breaking IDs.

### Simplifications

- Consolidate root/path/atomic-write/encoding logic into one tested project-files service shared by tools, plans, Markdown windows, and conversation storage.
- Replace delimiter legacy sessions with one versioned JSONL conversation format and a one-time importer.
- Replace custom dual HTTP implementations with a maintained cross-platform client that supports streaming, timeouts, cancellation, TLS validation, and redirect policy.
- Remove or implement distinct semantics for duplicate approval modes.
- Remove unused service fields such as obsolete HTTP/SSE objects after confirming no external package API relies on them.
- Put dynamically created Thinking/Approval controls into the `.lfm` or a layout container; hard-coded pixel coordinates complicate DPI, localization, and tab order.
- Keep provider adapters narrow and register new providers through `AssistantProviders.pas`; the new registry already separates provider identity, authentication kind, defaults, model discovery endpoints, and session credentials.

### User-experience suggestions

- Add an always-visible context/privacy strip showing exactly which files, selection, plan, diagnostics, and paths will be sent.
- Tool approval should show a human summary, affected paths, and a before/after diff, with **Allow once**, **Allow for this turn**, and **Deny**. Raw JSON is not an adequate consent surface.
- Show each tool/network/build action as a timeline item with live status, elapsed time, cancel, result, and expandable logs.
- Preserve unsent prompts and partial streamed answers through cancellation/project switching; clearly distinguish Cancelled, Failed, and Completed.
- Add conflict UI for assistant edits: accept/reject by hunk, keep local, keep assistant, or merge.
- Use IDE theme colors in Markdown/chat, respect font scaling, restore scroll position, and add accessible keyboard navigation.
- For model/endpoint configuration, test the connection without saving, display provider/capabilities, and show where credentials are stored.
- Add storage controls: private-by-default history, retention period, clear/export conversation, redact paths, and exclude assistant artifacts from Git.
- Provide a first-run checklist for login, privacy, tool approval, project root, and Git integration instead of discovering these settings during failure.

---

## Cross-package project issues

### Documentation and packaging

- The root README package table and installation instructions omit `LazMarkdown`, even though LazAssistantTools depends on it. Add it to the architecture and install/compile order.
- The README says `Source/Tests` exists, but no tracked test directory or test runner is present.
- The README status still says **Phase 0 — Foundations**, while the repository contains substantial Git and assistant implementations. Replace the phase statement with an accurate support/stability matrix.
- Package type/dependency choices should be reviewed: Common likely does not need `IDEIntf`; Repository may not need `SynEditDsgn`; package version metadata/schema is inconsistent.
- Document supported Lazarus/FPC versions, Git minimum version, OS/TLS prerequisites, credential storage, data locations, and the upgrade/migration policy.

### Suggested automated test suite

1. **Common:** event-bus subscribe/unsubscribe during callback, nested publish, concurrent publication, listener exception isolation, and UI-thread dispatch.
2. **Markdown:** golden cases for the two local fixes, empty/minimal email-like strings, malformed/fuzzed Markdown, renderer enum coverage, tables/entities, and large documents.
3. **Git service:** temporary repositories containing spaces, tabs, quotes, backslashes, non-ASCII and newline filenames; root/octopus merges; rename/copy; separate fetch/push URLs; stderr flooding; timeout/cancel; and patch byte preservation.
4. **Diff/patch:** golden partial-stage/unstage cases including add/delete/rename, zero-context hunks, adjacent selections, binary files, and no-final-newline markers. Run `git apply --check` before assertions.
5. **Assistant paths:** `..`, absolute paths, case variants, missing parents, symlink/junction escapes, archive-ID traversal, atomic-write failure, and open-buffer conflicts.
6. **Assistant streaming:** split UTF-8/SSE boundaries, missing terminal record, partial retry, duplicate legitimate text, oversized event/tool index/arguments, cancellation at every phase, and 20-round boundary.
7. **Persistence:** crash/failure injection between conversation/index/archive operations, legacy migration exactly once, sign-out persistence, corrupt JSONL recovery, and same-millisecond archive creation.
8. **IDE integration:** unsaved buffer then quiet build, project switch during a stream, package shutdown with active listeners/jobs, dark theme/high DPI, and canceled settings changes.

### Practical implementation order

1. **Safety:** Markdown conflict protection; correct saving before builds; secure token storage; remove current-directory DLL loading; canonical path/archive validation.
2. **Responsiveness:** shared cancellable job runner for Git, HTTP, assistant tools, model list, history details, and file enumeration.
3. **Protocol correctness:** NUL-delimited Git parsing; exact SSE/provider adapters; bounded buffers; terminal-event validation; atomic persistence.
4. **Maintainability:** split `GitDiffView`, unify project-file/root services, retire legacy sessions, pin the Markdown upstream, and remove unused dependencies/APIs.
5. **UX and accessibility:** operation timeline, visible logs, privacy/context controls, edit diffs/conflicts, theme/DPI support, keyboard navigation, and first-run guidance.
6. **Quality gate:** make the focused tests above part of CI and require warning-free package builds for supported Lazarus/FPC versions.

## Overall assessment

LazWorkflow already contains enough functionality to be genuinely useful, particularly the integrated repository history/diff surface and project-aware assistant workflow. Its next milestone should be a hardening release rather than another broad feature phase. Fixing the handful of P0 data/security issues, centralizing asynchronous jobs and safe file handling, and adding protocol-focused tests would substantially improve reliability while also simplifying the codebase and making the UI feel faster and more trustworthy.
