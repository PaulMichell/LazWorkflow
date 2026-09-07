# LazWorkflowCommon and LazRepositoryTools review

Date: 7 September 2026

Scope: the two packages' source units, package definitions, relevant form wiring, and their existing Git/status and spell-checker console tests. LazAssistantTools implementation and tests were excluded. Shared extension interfaces were considered only where defined or called by the reviewed packages.

The findings below record the original review and distinguish **reproduced** behaviour from **static** findings established by tracing the code. R1–R5 have subsequently been fixed; see the implementation update at the end. Original line references refer to the pre-fix source.

Priority: **P1** = unintended changes, possible data loss or invalid object access; **P2** = functional errors to fix during normal development. Optimisations and simplifications follow the bugs.

## Bugs: LazRepositoryTools

### R1 — P1: selected filenames are interpreted as Git patterns

**Reproduced.** [GitService.pas](../Source/LazRepositoryTools/GitService.pas), `RunGitPaths` (778–798), `UnstagePaths` (805–859), and `RevertPaths` (879–915).

The `--` separator prevents option parsing but leaves Git pathspec matching enabled. In a temporary repository containing modified `literal[1].txt` and `literal1.txt`, `StagePaths(['literal[1].txt'])` returned success and staged **both files**. Revert uses the same argument convention, so a selected filename can also discard another file's changes.

Use literal pathspecs for operations on paths obtained from the file list, consistently across staging, unstaging, reverting and diff queries. Keep any intentional pattern API separate. Regression checks should include brackets, asterisks and pathspec-magic prefixes, with a second matching file that must remain untouched.

### R2 — P1: unstaging a rename leaves a deletion staged

**Reproduced.** [ManageRepositoryFiles.pas](../Source/LazRepositoryTools/ManageRepositoryFiles.pas), `ApplyFromStatus` (231–243); [GitService.pas](../Source/LazRepositoryTools/GitService.pas), `UnstagePaths` (805–859).

The status parser preserves `OldPath`, but the files pane keeps only the destination in `FStagedPaths`. After `git mv main.txt renamed.txt`, unstaging the displayed rename restores only `renamed.txt` in the index. The resulting status is:

```text
D  main.txt
?? renamed.txt
```

The original file is still staged for deletion and can be committed unintentionally. Retain the status record behind each row and include both paths when unstaging a rename. Handle copies separately. Test selected and “Unstage All” actions, then verify the entire staged diff is empty.

### R3 — P1: an old job completion can act on a newly selected repository

**Static.** [ManageRepositoryForm.pas](../Source/LazRepositoryTools/ManageRepositoryForm.pas), `GitJobFinished` (625–818), especially the commit handler (674–698), and `SetRepository` (1799–1854).

History/detail/status results have identity checks, but commit and remote-operation results do not. The form can be rebound through project changes or Open Repository while a job is running. A commit started in repository A can therefore complete after the form moves to B, clear B's message editor, and invoke `StartRemoteOp(rokPush)` using **B's current path** when “push after commit” was selected for A. Fetch/pull/push results can likewise install A's history into B's view.

Store follow-up intent on the job, including its repository, and validate repository identity/generation before applying any result to a form. Follow-up mutations must use the originating job's path. Test with a delayed commit hook in A while rebinding the form to B.

### R4 — P1: callback detachment can miss a job between queue states

**Static concurrency finding.** [GitJobRunner.pas](../Source/LazRepositoryTools/GitJobRunner.pas), worker transitions (290–305, 348–373), `DetachFinishedHandler` (793–817), and `CancelIfHandler` (819–832).

There are unlocked gaps between removing a job from `FQueue` and assigning `FCurrent`, and between clearing `FCurrent` and adding the job to `FDeliverQueue`. During either gap, form destruction can run `DetachFinishedHandler` and find the job in none of the three places it searches. The job retains a method pointer into the destroyed form and may call it later. `CancelIfHandler` also checks a captured job and then cancels whichever job is current later, allowing cancellation of a different job.

Make queue-to-current and current-to-delivery transitions atomic under the same lock, and select/mark the exact cancellation target under that lock. A test should pause the worker at each transition while detaching its owner. Also detach `GitIdeJobHost.JobFinished` before freeing the host in [RepositoryManagerMain.pas](../Source/LazRepositoryTools/RepositoryManagerMain.pas), finalization: it currently lacks the cleanup used by the forms.

### R5 — P1: a dangling `.gitignore` symlink bypasses the path check

**Reproduced on Linux.** [GitService.pas](../Source/LazRepositoryTools/GitService.pas), `WorkingTreeFullPath` (1019–1062) and `AppendIgnorePatterns` (917–971); [GitIgnoreForm.pas](../Source/LazRepositoryTools/GitIgnoreForm.pas), save path (78–100).

Physical path validation runs only when `FileExistsUTF8` or `DirectoryExistsUTF8` succeeds. A `.gitignore` symlink pointing to a nonexistent file outside the repository passes the lexical check. Appending an ignore pattern then follows the symlink and creates the external target. A scratch reproduction returned success and wrote `/build` into the outside file.

Check symlink identity independently of target existence and validate the resolved destination/nearest existing parent before writing. For the ignore editor, rejecting a symlink at the destination is a simple option. Test existing and dangling links, including links in parent directories.

### R6 — P2: partial unstaging uses context from the wrong side of the diff

**Reproduced.** [GitDiffPatch.pas](../Source/LazRepositoryTools/GitDiffPatch.pas), `BuildGitPartialPatch` (196–230); [GitDiffView.pas](../Source/LazRepositoryTools/GitDiffView.pas), `UnstageSelection` (2322–2363).

The builder always converts unselected removals into context and drops unselected additions. That describes a partial forward patch against the old content. Unstaging then reverses that patch against an index containing **all** staged changes, including the unselected ones.

With two replacements in one hunk, selecting the first replacement produces context containing the old text of the second replacement. `git apply --cached --reverse` fails with “patch does not apply”. Build direction-aware patches, preserving the index-side text as context when unstaging. Test two changes in one hunk and each individual added/removed line, not just whole hunks.

### R7 — P2: valid changed lines are mistaken for diff metadata

**Reproduced in the patch builder; display effect is static.** [GitDiffPatch.pas](../Source/LazRepositoryTools/GitDiffPatch.pas), line classifiers (30–61) and header handling (174–193); [GitDiffView.pas](../Source/LazRepositoryTools/GitDiffView.pas), `SetEditorDiffText` (814–850).

A file line beginning `-- ` becomes a removed diff line beginning `--- `; a line beginning `++ ` becomes `+++ `. The parser treats these as file headers even inside a hunk. Changing `-- divider` to `++ divider` and selecting the whole diff produced an empty partial patch. The display filter also removes these lines, so the actual change can disappear from the preview.

Classify metadata according to parser state and hunk line counts. Inside a normal hunk, the first character determines addition/removal/context; the remaining content is arbitrary. Use the same parsed representation for display and patch construction. Include Markdown separators and source lines beginning with repeated plus/minus characters in regression cases.

### R8 — P2: root commit diffs and merge commit files are missing

**Reproduced.** [GitService.pas](../Source/LazRepositoryTools/GitService.pas), `ListCommitPaths` (1776–1801) and `ShowCommitPathDiff` (1803–1815).

`ListCommitPaths` includes `--root`, so it lists a root commit's files. `ShowCommitPathDiff` omits `--root`, producing an empty diff for those same files. For merge commits, neither command requests a first-parent comparison: the path-list comment promises this behaviour, but a clean merge with a real change relative to its first parent returns no paths.

Define one comparison policy for both methods: an empty tree for root commits and the first parent for merges, unless the UI explicitly offers another parent. In the reproduction, the root listed `file.txt` with no diff, and a merge listed nothing although `git diff --name-only HEAD^1 HEAD` returned `side.txt`.

### R9 — P2: showing clean files hides existing untracked and ignored files

**Static.** [ManageRepositoryFiles.pas](../Source/LazRepositoryTools/ManageRepositoryFiles.pas), `ApplyFromStatus` (248–302).

With “Clean” enabled, `AllFiles` comes only from `ListTrackedFiles`. The later pass over status records adds paths only if their working-tree file does **not** exist. Existing untracked and ignored files are therefore omitted, even when their corresponding checkboxes are enabled.

Build the union of tracked paths and status paths before filtering. Test clean + untracked and clean + ignored together, with ordinary files as well as deleted files and directories. Each enabled category should remain visible independently of the others.

### R10 — P2: Unix wait status is treated as a decoded exit code

**Reproduced on Linux with FPC 3.3.1.** [GitService.pas](../Source/LazRepositoryTools/GitService.pas), `RunGitPump` (416), `GetConfigValue` (1844–1873), and `UnsetConfigValue` (1875–1905).

`Proc.ExitStatus` exposes the Unix wait status, but callers compare it with ordinary exit codes 1 and 5. Reading an absent config key returned false with `git config exited 256`; unsetting an absent key returned false with `git config exited 1280`. Both are documented by these methods as successful empty/no-op cases.

Decode normal exit codes while preserving a separate signalled/cancelled result; do not accidentally classify signal termination as success. The local FPC process source confirms the distinction between `ExitStatus` and `ExitCode`. Add Linux tests for missing keys, real failures and process termination.

### R11 — P2: failed untracked-file diffs are reported as successful

**Reproduced.** [GitService.pas](../Source/LazRepositoryTools/GitService.pas), `DiffPath` (1207–1216).

After `git diff --no-index`, any nonempty output converts failure to success. Stderr is merged into that output, so an error message qualifies. Requesting a nonexistent `missing.txt` returned `True` and supplied `error: Could not access 'missing.txt'` as the diff.

Accept the documented “files differ” exit result only, after correcting R10, and preserve other failures. Keep diagnostic stderr separate from parsed diff data. Test a valid new file, a missing file and an unreadable file.

### R12 — P2: automatic refresh misses further edits to an already modified file

**Reproduced at the Git-output level; UI consequence is static.** [GitService.pas](../Source/LazRepositoryTools/GitService.pas), `ProbeRepository` (643–675); [ManageRepositoryForm.pas](../Source/LazRepositoryTools/ManageRepositoryForm.pas), probe completion (776–791).

The stored “digest” is porcelain v2 status text. It records status and index/HEAD information, not the current working-tree contents. Editing an already modified file again produced byte-identical probe output. The completion handler consequently leaves an open diff preview unchanged until a manual refresh or another status transition.

Track changes to the selected working file separately, for example with file notifications or a metadata/content version, and refresh its preview when that version changes. Do not require a status-code change to notice changed contents. Test repeated edits while the status remains ` M`.

## Bugs: LazWorkflowCommon

### C1 — P2: a standalone apostrophe stops scanning the rest of the text

**Reproduced.** [SpellWordBreaker.pas](../Source/LazWorkflowCommon/SpellWordBreaker.pas), `NextWord` (122–165).

An apostrophe-only token is consumed and stripped to an empty string. Returning false then tells every caller that iteration has finished, although more text remains. `SpellBreakWords("hello ' recieve world")` returned only `hello`; the misspelling and subsequent words were never examined.

Continue scanning after tokens that become empty. Return false only at end of input or an unrecoverable decoding error. Test standalone straight/curly apostrophes at the beginning and middle of text, as well as normal contractions and quoted words.

### C2 — P2: hard newline positions do not belong to any nonfinal visual row

**Static.** [SpellMemo.pas](../Source/LazWorkflowCommon/SpellMemo.pas), `ByteBelongsToPaintLine` (699–715), `CaretPixel` (717–740), and Home/End/Up/Down handling (940–995).

The half-open row rule correctly assigns a soft-wrap boundary to the next row, but it also excludes the position immediately before a hard newline. The following row starts after that newline, leaving a gap. For `abc\ndef`, caret byte 4 belongs to neither row. Empty nonfinal paragraphs have the same problem. `CaretPixel` falls back to the end of the final row, while navigation can fall back to row zero.

Distinguish soft-wrapped rows from hard-terminated paragraphs. Assign the pre-newline position and empty paragraph position to the preceding/current row. Test End, Home, vertical movement and clicking at the end of each paragraph, including blank lines.

### C3 — P2: changing the configured spell library silently keeps the old library

**Reproduced for Hunspell; the same logic exists in Aspell.** [SpellEngineHunspell.pas](../Source/LazWorkflowCommon/SpellEngineHunspell.pas), `BindHunspell` (99–107); [SpellEngineAspell.pas](../Source/LazWorkflowCommon/SpellEngineAspell.pas), `BindAspell` (104–112).

Once a global library handle exists, the bind function returns success without comparing the requested filename. After loading Hunspell successfully, setting `LibraryFileName` to `/does/not/exist.so` and calling `Load` again returned true, still using `libhunspell-1.7.so.0`. Availability checks can bind a default library before the user applies a custom path, so this affects the settings workflow too.

Either support bindings keyed by resolved library path with explicit lifetime ownership, or reject/report changes that require a restart. Make global binding initialization synchronized because discovery and background preload can reach these globals from different threads. Test a valid initial load followed by a different and an invalid path.

### C4 — P2: externally owned popup menus retain unsafe spell-memo state

**Static; applies when a host supplies a popup menu.** [SpellMemo.pas](../Source/LazWorkflowCommon/SpellMemo.pas), destructor (227–245), `EnsurePopupHook` (1341–1359), and menu rebuilding (1384–1441).

`FHookedPopup` has no destruction notification. Freeing an external menu first leaves a pointer that the memo later dereferences. In the other destruction order, injected menu items are owned by the external menu and retain callbacks into the freed memo. Switching menus also carries `FSpellItemCount` from the old menu, so clearing the new menu can delete its host items.

Track injected items by identity and remove them when unhooking; register/remove component free notifications for the external menu. Reset menu-specific state during a switch. Test freeing either object first and replacing an already populated popup.

## Optimisations

### O1 — Move the remaining Git reads off the UI thread

[ManageRepositoryForm.pas](../Source/LazRepositoryTools/ManageRepositoryForm.pas), `GitDirStampChanged` (1638–1658) and `RefreshRepositoryInfo` (1756–1775); [ManageRepositoryFiles.pas](../Source/LazRepositoryTools/ManageRepositoryFiles.pas), `ApplyFromStatus` and `ShowSelectedDiff`; [GitDiffView.pas](../Source/LazRepositoryTools/GitDiffView.pas), `LoadCommit` and `ShowSelectedBrowseFile`.

The background queue covers many operations, but the one-second timer still launches `rev-parse --git-dir` synchronously. Status refresh, tracked-file listing and selecting a commit/file also perform synchronous Git reads, sometimes several per selection. Slow storage, large files or an external diff helper can block the IDE.

Cache the Git directory for the bound repository and return tracked paths/diffs/blob data through generation-checked read jobs. Measure selection latency and idle Git process launches before and after. For machine-parsed diff operations, explicitly control colour and external-diff behaviour rather than inheriting presentation settings.

### O2 — Avoid reindexing the whole history for working-tree changes

[ManageRepositoryForm.pas](../Source/LazRepositoryTools/ManageRepositoryForm.pas), probe completion (776–791), `ManualRefresh` (455–468) and `SetRepository` (1799–1854).

Every detected probe difference calls `ManualRefresh`, which clears/reloads the graph and resets the selected commit. A simple file edit therefore triggers full `rev-list --all`, graph reconstruction and new detail loads. Separate working-tree refresh from HEAD/ref/history refresh; preserve selection by SHA and file path where possible. Combine this with R12 so preview freshness does not depend on rebuilding history.

### O3 — Index visible graph edges and cache diff overview markers

[ManageRepositoryHistory.pas](../Source/LazRepositoryTools/ManageRepositoryHistory.pas), `Paint` (488–506); [GitDiffHighlighter.pas](../Source/LazRepositoryTools/GitDiffHighlighter.pas), overview `Paint` (258–303).

Graph painting visits every history edge before rejecting offscreen edges. The overview gutter similarly rescans every displayed diff line for each paint. Visible commit details are virtualized, but these loops still scale with the entire dataset.

Maintain an interval/bucket index for edges intersecting visible rows, including long edges whose child is above the viewport. Cache added/removed line positions when diff content changes and map those positions into overview pixels. Profile large histories and diffs while scrolling; no timing improvement is claimed here without measurement.

### O4 — Reduce repeated spell layout and dictionary work

[SpellMemo.pas](../Source/LazWorkflowCommon/SpellMemo.pas), `RebuildLayout` (527–621), `CharIndexAtPoint` (769–800), `Paint` (1129–1238) and `Rescan` (1240–1272).

Wrapping repeatedly measures growing prefixes and deletes consumed text from the front of a string. Every edit rebuilds the whole layout; caret movement schedules another whole-text spell scan. Painting checks all error ranges for each visible row, and each scan emits an info-level log entry.

Cache paragraph layout and shaped-text measurements, reflow changed paragraphs, and cache dictionary results by word plus configuration generation. Index underline ranges by row and log routine rescans at debug level. Preserve kerning/shaping when replacing prefix measurements. Benchmark long pasted paragraphs and cursor movement as well as ordinary short messages.

### O5 — Enforce preview limits before loading entire files

[GitDiffView.pas](../Source/LazRepositoryTools/GitDiffView.pas), `TryShowBinaryOrImage` (1412–1454); [GitService.pas](../Source/LazRepositoryTools/GitService.pas), working-tree/blob reads (1065–1151).

The 8 MiB image limit is checked only after the complete blob has been read into memory. Clean text previews also load whole files. Diff context limits reduce surrounding lines, but do not cap a huge addition or deletion.

Check file/blob sizes first and enforce a bounded read while streaming, with a clear oversized-preview state. Also limit decoded image dimensions/pixel count, since compressed byte size alone does not bound image memory. Test oversized working-tree files and committed blobs.

## Simplifications and maintainability

1. **Use one parsed diff model for display, selection and patch generation.** The patch builder, metadata filter, tree parser and highlighters duplicate prefix classification. A shared file/hunk/line model with explicit old/new coordinates would address R6/R7 and reduce inconsistent fixes.

2. **Keep structured file records behind the lists.** `ManageRepositoryFiles` currently spreads identity across labels, parallel path lists and a `TStringList` name/value map. Preserve raw paths, old paths and XY status together, deriving labels only for display. This also fixes R2/R9 more naturally. The comment that Git rejects ASCII control characters in paths is incorrect; using SOH as a map separator is not a general filename solution. Avoid unconditional backslash replacement on Unix and use filesystem-appropriate case comparison consistently.

3. **Unify spell-engine loading and avoid reloading unchanged settings.** [SpellCheckerConfig.pas](../Source/LazWorkflowCommon/SpellCheckerConfig.pas) duplicates engine selection/loading in the preload thread and synchronous `Apply` (412–446). `AssignOptions` always calls `Apply`, so accepting repository settings can synchronously tear down/reload a dictionary even when spell options are unchanged. Use one engine factory/load-result path, compare relevant options, and keep UI application asynchronous where possible.

4. **Separate operation results from mutable diagnostics.** `TGitService.LastError` is overwritten by subsequent commands. Transfer-summary counting runs extra Git commands after the transfer, and settings saving runs multiple writes before presenting one final `LastError`. Return structured results containing success, decoded exit status, stdout and stderr; retain each failed operation's diagnostic. Likewise, let personal-dictionary persistence report failure instead of silently presenting an unsaved word as added.

5. **Make remote row identity explicit.** [GitRemotesForm.pas](../Source/LazRepositoryTools/GitRemotesForm.pas), `SaveToGit` (297–470), infers renames by matching URLs. Changing both a remote's name and URL becomes add/remove, potentially losing remote-specific configuration and tracking relationships. Keep the original remote name on each edited row, then perform an explicit rename and URL update. Rollback should preserve the affected configuration, rather than reconstructing only a name/URL pair.

## Validation performed and remaining checks

- Built and ran `Source/Tests/GitStatusParseTest.lpr`: all checks passed, including live Git rename parsing, unstaging before the first commit and rejection of an existing symlink target outside the repository.
- Built and ran `Source/Tests/SpellCheckerTest.lpr`: all checks passed. Hunspell and Aspell were both available and their checks executed successfully.
- Compiled a temporary Pascal probe against the actual reviewed units and exercised scratch repositories. Reproduced R1, R2, R5, R6, R7, R8, R10, R11, C1 and the Hunspell instance of C3. Separately verified that porcelain output stays identical across repeated worktree edits for R12.
- Used FPC 3.3.1 and Git 2.47.3 on Linux. Build outputs, the probe and scratch repositories were placed under `/tmp/lazworkflow-review`; no reviewed source files or existing documents were edited.
- No full Lazarus IDE/package build, interactive GUI session, Windows/macOS run or deterministic thread-race test was performed. R3/R4/R9/C2/C4 need focused GUI/concurrency regression coverage. Performance proposals are based on code structure, not benchmark results.

For reproducing the existing console checks, use the Lazarus `components/lazutils` directory as a unit search path, the relevant `Source/LazWorkflowCommon` and `Source/LazRepositoryTools` directories, and separate temporary `-FU`/`-FE` output directories. The existing passing tests are useful baselines, but do not currently cover the failures above.

Recommended order: first fix R1–R5, then the partial-patch and history/file-display failures, then the Common editing/loader defects. Add the narrow regression checks described with each finding before undertaking the larger refactors.

## Implementation update: R1–R5

Implemented on 7 September 2026. R6 onward remain outstanding.

| Finding | Change |
| --- | --- |
| R1 | The shared Git command runner supplies `--literal-pathspecs`, so staging, unstaging, reverting and diff queries treat supplied filenames literally. |
| R2 | `UnstagePaths` expands selected rename destinations to include their original paths using fresh index status. This covers both individual selection and the UI's list-based “Unstage All”; copied-file sources remain independent. |
| R3 | Jobs carry a repository generation and push-after-commit intent. Form callbacks reject results from another repository or an earlier visit. Push follow-ups copy the originating job's repository/context, including when the window has switched repositories. Modal completion paths recheck context before further changes. |
| R4 | Queue-to-current and current-to-delivery transitions now happen under the runner lock. Cancellation selects and cancels the same job under that lock, and cancellation reset occurs before publishing a new current job. IDE job-host finalization detaches callbacks; runner shutdown suppresses completion delivery. |
| R5 | Path validation checks dangling links and the nearest existing ancestor of missing paths. Both ignore-file save paths use a shared service method that revalidates at save time and rejects a symlink at `.gitignore`. |

Added [RepositorySafetyTest.lpr](../Source/Tests/RepositorySafetyTest.lpr), which exercises actual temporary Git repositories and the background runner:

- Literal bracket, wildcard, leading-dash and pathspec-magic filenames, including selective unstaging from an already populated index and preservation of other matching files.
- Selected rename unstaging, the UI's list-based unstaging, service-level unstaging, and preservation of a separately staged copy source.
- Normal ignore writes, existing/dangling external symlinks, internal symlinks, and missing files below linked directories.
- A commit paused in a hook while the test switches repository context; its push follow-up updates A's local bare remote and leaves B unchanged.
- Detachment of running and queued callbacks, cancellation without cancelling an unrelated successor, and 100 batches totalling 1,600 rapid jobs to exercise transition timing.

The new suite passed with range, overflow and heap checks enabled. `GitStatusParseTest` and `SpellCheckerTest` also passed, with both spell engines exercised. `Packages/LazRepositoryTools.pas` compiled successfully against the installed Lazarus dependencies, with compiler outputs kept in `/tmp`. `git diff --check` passed. The transition stress test does not exhaust all possible thread schedules; no interactive IDE or Windows/macOS validation was performed.

## Implementation update: R8, R10 and R11

Root commits now show their additions, and both merge path lists and patches use the first parent. The Git runner decodes Unix wait statuses, keeps stderr separate from parsed output, and exposes a command-result snapshot. Missing config keys are successful empty/no-op operations; multi-value unset errors remain failures. Untracked diffs accept exit 1 only when actual diff output is present without error diagnostics. Transfer summaries preserve the transfer's original result across follow-up queries (part of simplification 4).

Validation: the repository package compiled, and `RepositorySafetyTest` passed with range, overflow and heap checks (zero leaks). Added live Git cases for root/merge commits, missing and invalid config, multi-value unset, valid/missing/unreadable untracked files, and failed transfer diagnostics. Existing R1–R5 checks also passed. Interactive GUI and other-platform checks remain outstanding.

## Implementation update: R6 and R7

Partial patch construction now accepts a reverse direction and preserves the index-side context for unstaging. Hunk coordinates account for selected changes across multiple hunks. A shared parsed line model classifies additions/removals using hunk counts, so `--- divider` and `+++ divider` remain changed content. Patch construction, header filtering, selection/colouring, the tree and overview markers use this model. Overview markers are cached when content changes (the diff portion of O3); graph edge indexing remains outstanding.

Validation: the package compiled and the expanded checked `RepositorySafetyTest` passed with zero leaks. Live index tests cover both directions, selecting a replacement or either individual changed line, repeated plus/minus content, separated hunks with unselected line-count changes, and missing final newlines. Interactive selection/rendering validation remains outstanding.

## Implementation update: C1–C4

The word breaker skips tokens reduced to empty apostrophes. Hard-newline and blank-paragraph caret positions now belong to their paragraph while soft-wrap boundaries still belong to the next row. Hunspell and Aspell binding/discovery use synchronized initialization and reject a different configured library after binding, with a restart diagnostic. Spell popup items are tracked by identity, removed when unhooking, and registered for destruction notifications; switching menus preserves host items and destroying either owner removes stale callbacks.

Validation: the repository package compiled. Expanded `SpellCheckerTest` passed with range, overflow and heap checks (zero leaks), exercising straight/curly apostrophes, quoted words, contractions, and same/changed library reloads for both installed engines. Caret movement and popup lifetime changes were checked by code tracing and package compilation; an interactive LCL test remains necessary. Larger spell layout/loading optimisations remain outstanding.

## Implementation update: R9 and R12, refresh work

The files pane now merges structured status entries with tracked paths before filtering. It retains untracked/ignored/deleted entries, raw control characters and Unix backslashes, and rename sources; SOH name/value encoding is removed. Selected paths survive status refresh. Tracked-file listing and repository information queries run in jobs, and the idle timer uses a cached Git directory (part of O1). Worktree-only probe changes refresh files without reindexing history; HEAD, branch or ref changes still rebuild history (O2). A visible selected preview is polled on successful probes even when porcelain is unchanged, fixing repeated-edit staleness (R12). Preview reads themselves remain synchronous pending the remaining O1 work.

Validation: package compilation and checked `RepositorySafetyTest` passed with zero leaks. Added category-union, control-character, rename-source, Unix-backslash and repeated-dirty-edit checks. GUI category combinations, selection persistence and polling still need interactive validation. No selection-latency benchmark has yet been run.

## Implementation update: preview limits (O5)

Working-tree and blob previews check the 8 MiB limit before reading; working-tree reads copy only the checked size, and blob/diff subprocess output is bounded during streaming. Failed or truncated diff text is discarded. Images require readable dimensions before decoding, with a 16 megapixel / 16384-pixel-side ceiling; unsupported dimension readers fall back to an explanatory unavailable-preview message. Also made Stage/Unstage pass patch direction explicitly, covering the tree view as well as embedded previews.

Validation: package compilation and checked repository regressions passed with zero leaks. Added oversized working-tree, committed-blob and large-addition diff cases, plus a normal command after a rejected preview. Image decoding/rendering remains an interactive check.

## Implementation update: spell loading, repeated work and diagnostics

Simplification 3 uses the existing preload worker as the sole engine factory/load path. Unchanged options preserve the engine; changed options retire an older worker without waiting in the UI, and generation checks reject obsolete results. Dictionary checks use a bounded, configuration-invalidated cache. Spell memo tokenization is reused while text is unchanged; unchanged paragraphs reuse bounded layout caches, wrapping advances offsets instead of deleting string prefixes, and painting walks sorted underline ranges. Native prefix measurement remains in use to preserve kerning/shaping. Routine rescan logs are debug-level (O4).

Simplification 4 now retains all failed repository-setting write diagnostics and reports personal-dictionary save failures, removing an unsuccessfully saved word from the in-memory personal set. Transfer-result snapshots were handled in the earlier Git result commit.

Validation: package compilation, checked `SpellCheckerTest` and new checked `SpellConfigTest` passed, with zero heap leaks. Config tests cover asynchronous loading, unchanged options, cache invalidation, save failure, and rejecting obsolete loads. Paragraph/rendering performance improvements have not yet been benchmarked in a running IDE.
