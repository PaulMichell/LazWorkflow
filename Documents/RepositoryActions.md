# Repository Manager Actions

**Source review:** [LazWorkflowReview.md](LazWorkflowReview.md) (ChatGPT, 8 August 2026)  
**Assessment date:** 10 August 2026  
**Scope:** Recommendations that apply to **LazRepositoryTools** / the Manage Repository surface only (not Assistant, Markdown, or Common except where shared by the repository package).  
**Method:** Every LazRepositoryTools finding, optimization, simplification, and UX suggestion from the review was checked against the **current** working tree (`Source/LazRepositoryTools`, `Packages/LazRepositoryTools.lpk`). Validity and worth are engineering judgments for this product, not a re-statement of the review’s status table.

### Status legend

| Status | Meaning |
|---|---|
| **Completed** | Present in current code (or finished in the recent designer/Files-tab session). |
| **Partial** | Direction correct, but the claimed risk or full fix is not yet closed. |
| **Open** | Still applicable and unfinished. |
| **Defer** | Valid idea, lower value for now — track but do not prioritize ahead of Open P0/P1. |

### Note on the review’s “implementation status” section

The review claims a large hardening pass for LazRepositoryTools (NUL porcelain, concurrent stderr drain, worker deadlock fixes, dynamic parents, path containment, `git apply --check`, one-time config migration, empty clone folders, removal of `SynEditDsgn`, etc.). **Several of those claims do not match the current tree.** This document trusts the code over the review’s status table and marks those items **Open** or **Partial** where still broken.

---

## Priority ordered recommendations

Items are ordered by **importance for correctness, IDE safety, and user trust** first; maintainability and polish after.

---

### 1. Stop UI-thread `WaitFor` on workers that use `Synchronize` — **Completed · Valid · Critical**

**Review:** P1 detail/index shutdown deadlock (`StopDetailThread` / index stop + `Synchronize`).  
**Assessment:** Fully valid. Classic deadlock if a worker is inside `Synchronize` while the form waits.  
**Done (2026-08-10):** Index, detail, and remote workers deliver via `Queue` (not `Synchronize`). Soft cancel bumps a generation token and `Terminate`s without `WaitFor`. Form `Destroy` hard-disposes with `DetachForm` + `RemoveQueuedEvents` + `WaitFor` (safe because Queue does not block the worker on the UI thread). Stale Queue callbacks are ignored by generation mismatch; workers free themselves on the main thread in `Deliver`.

---

### 2. Free completed detail workers (no pointer overwrite leak) — **Completed · Valid · Critical**

**Review:** P1 detail-loading threads leak; `ApplyDetailsLoaded` does not free `FDetailThread`.  
**Assessment:** Valid.  
**Done (2026-08-10):** Fixed together with item 1. Each worker’s `Deliver` clears the form’s thread pointer when it matches `Self` and `Free`s the worker on the main thread. Soft cancel abandons the pointer so a newer worker can start without overwriting a live reference.

---

### 3. Move long-running Git off the IDE thread (shared job runner) — **Partial · Valid · Critical**

**Review:** P1 clone/fetch/pull/push/commit/checkout/diff/details/refresh block UI; no timeout/cancellation; `poNoConsole` hides credentials.  
**Code:** Fetch/pull/push run on `TGitRemoteOpThread`. Index/details use workers. Commit, checkout, clone, many diffs/refreshes still run on the UI thread via `TGitService`.  
**Assessment:** Valid and high value. Partial only because remote ops are already threaded.  
**Action:** One cancellable job service per repository (queue, progress, timeout, cancel). Show an operation panel (command, repo, elapsed, Cancel, copyable error). Surface credential/auth failures explicitly.

---

### 4. Concurrent stdout **and** stderr drain for all Git process paths — **Partial · Valid · High**

**Review:** P1 `RunGitBinary` can deadlock when stderr fills.  
**Code:** `RunGitEx` merges stderr (`poStderrToOutPut`) and drains the merged pipe. `RunGitBinary` drains **stdout while running**, but stderr only **after** the run loop — still a stall risk under verbose stderr.  
**Assessment:** Valid for binary path; text path partially mitigated by merge.  
**Action:** Drain both pipes interleaved (or always merge) on every process helper; include stderr text in failure messages for binary ops.

---

### 5. NUL-delimited porcelain status / machine-readable paths — **Open · Valid · High**

**Review:** P1 `ListStatus` line porcelain + quote strip + `" -> "` rename parse is unsafe.  
**Code:** Still `status --porcelain` / `--porcelain` with line split and `Pos(' -> ', ...)` (`GitService.ListStatus`). No `-z` / `--porcelain=v2`.  
**Assessment:** Valid for real-world repos (spaces, quotes, non-ASCII, renames).  
**Action:** Prefer `git -c core.quotePath=false status --porcelain=v2 -z` (or v1 `-z`) and parse NUL records; same discipline for path lists used by stage/unstage/diff.

---

### 6. Files refresh must not `FindAllFiles` the whole tree by default — **Open · Valid · High**

**Review:** P1 `RefreshFilesList` scans recursively even when clean files are off.  
**Code:** `FindAllFiles(AllFiles, FRepoPath, '*', True)` always runs (`ManageRepositoryForm.pas` ~1679), then filters.  
**Assessment:** Valid — large trees hang the IDE.  
**Action:** Build the left list from porcelain alone unless “Show clean” is checked; if clean is needed, enumerate off-thread and exclude `.git` / ignored / build dirs.

---

### 7. Auto-refresh must notice dirty-set changes, not only clean/HEAD/branch — **Open · Valid · High**

**Review:** P1 auto-refresh misses edits while already dirty.  
**Code:** `QuietRefreshIfChanged` compares HEAD SHA, branch, and `Clean` boolean only — **not** porcelain content.  
**Assessment:** Valid. Staging one file while another stays dirty will not refresh the Files tab.  
**Action:** Compare a porcelain digest (or index/worktree mtimes) and refresh Files when the dirty set changes.

---

### 8. Partial-patch model + `git apply --check` before apply — **Partial · Valid · High**

**Review:** P1 fragile patch builder; no-final-newline association; validate with `git apply --check`.  
**Code:** Substantial selection/patch logic remains inside `GitDiffView.pas` (~3.2k lines). `ApplyPatchToIndex` writes via `TStringList.SaveToFile` and runs `git apply --cached` **without** a prior `--check`. Recent session improved hunk selection UX (markers, double-click) but not the patch model.  
**Assessment:** Valid. Worth extracting a tested patch unit.  
**Action:** Extract parse/selection/build; preserve `\ No newline at end of file` per change line; `git apply --check` then apply; golden tests for add/delete/rename/zero-context/binary/no-NL.

---

### 9. Diff / name-status for unusual paths (renames, binary, quotes) — **Open · Valid · High**

**Review:** P1 human-readable diff path inference is weak.  
**Code:** Diffs still come from text `git diff` / `git show`; no separate machine-readable name-status binding.  
**Assessment:** Valid; pairs with #5.  
**Action:** Request name-status / pathspec data separately; associate with patch records; surface binary as non-text.

---

### 10. Patch bytes must not round-trip through `TStringList` — **Open · Valid · High**

**Review:** P2 EOL/encoding normalization can invalidate patches.  
**Code:** `ApplyPatchToIndex` still uses `TStringList.Text` / `SaveToFile`.  
**Assessment:** Valid for partial stage correctness.  
**Action:** Write exact UTF-8 bytes to a unique temp file; check every I/O result; delete in `finally`.

---

### 11. Path containment on repository-relative paths — **Open · Valid · High**

**Review:** P2 `WorkingTreeFullPath` lexical join allows `..` escapes.  
**Code:** Still concatenates `ExpandFileName(FRepoPath)` + path with slash normalize only — **no** containment check.  
**Assessment:** Valid (less severe than assistant tools, still wrong for a public service API).  
**Action:** Reject `..` and any expanded path outside the repo root before read/write/delete/ignore.

---

### 12. Dynamic parent list for octopus merges — **Open · Valid · Medium–High**

**Review:** P2 graph drops parents beyond four.  
**Code:** `Parents: Array[0..3]` and parse cap still in `GitGraphModel.pas`. Review “fixed” claim is **wrong** for current tree.  
**Assessment:** Valid for correctness of rare merges; medium priority for typical repos.  
**Action:** Dynamic parent array; edges for all parents.

---

### 13. Typed integer lists instead of pointer-packed line numbers — **Open · Valid · Medium**

**Review:** P2 pointer-to-integer packing warnings / brittleness.  
**Code:** `TFPList` + `Pointer(PtrInt(...))` still used for selected lines and hunk starts in `GitDiffView.pas`.  
**Assessment:** Valid maintainability/safety cleanup; not an immediate user-facing bug on 64-bit.  
**Action:** `specialize TFPGList<Integer>` or dynamic arrays.

---

### 14. Accurate commit/checkout event metadata — **Open · Valid · Medium**

**Review:** P2 hard-coded parent count / guessed author / ref vs SHA.  
**Code:** `Commit` still sets `Info.ParentCount := 1`, empty author, `CommitDate := Now`, summary = message only.  
**Assessment:** Valid for event-bus consumers (assistant, status).  
**Action:** Query the new object once (`git show` / `cat-file`) and publish real `TGitCommitInfo`; same for checkout/HEAD events.

---

### 15. Remote save transactional + rename support — **Open · Valid · Medium**

**Review:** P2 `SaveToGit` removes remotes before all adds succeed.  
**Code:** Still removes non-kept remotes first, then add/set URL; no `git remote rename`.  
**Assessment:** Valid for destructive config errors.  
**Action:** Validate grid first; use rename where names change; incremental apply; report partial failure and avoid remove-before-add for renames.

---

### 16. Separate fetch and push URL columns — **Open · Valid · Medium**

**Review:** P2 fetch/push URLs conflated.  
**Code:** Remotes grid is name + single URL; no push URL UI.  
**Assessment:** Valid for dual-URL remotes.  
**Action:** Show and edit fetch URL and push URL explicitly; test-connection optional.

---

### 17. Config migration once via version marker — **Open · Valid · Medium**

**Review:** P2 migration re-runs when new values equal defaults.  
**Code:** `GitConfig.Load` still migrates from legacy when AutoRefresh equals defaults — **no** migration-version key.  
**Assessment:** Valid edge case.  
**Action:** Store `MigrationVersion` (or similar) and migrate once.

---

### 18. Accept empty existing clone destination — **Open · Valid · Medium**

**Review:** P2 clone rejects existing empty folder.  
**Code:** `CloneRepository` rejects any existing `Dest` directory.  
**Assessment:** Valid UX friction with folder pickers; Git allows empty dirs.  
**Action:** If directory exists and is empty (and not a repo), allow clone into it.

---

### 19. Transfer summaries without scraping localized text — **Open · Valid · Medium**

**Review:** P2 up-to-date misclassification from human output.  
**Code:** `BuildTransferSummary` still scrapes process text for ranges/refs.  
**Assessment:** Valid; intermittent wrong “up to date” messages.  
**Action:** Prefer before/after ref comparison or machine-readable progress.

---

### 20. Bound full-file diffs / previews — **Open · Valid · Medium**

**Review:** P2 `-U100000`, tree nodes, image/blob reads unbounded.  
**Code:** Diffs still use `-U100000`.  
**Assessment:** Valid for huge files.  
**Action:** Size thresholds, lazy hunks, external viewer for oversized/binary.

---

### 21. Shared async Git job service + cache — **Open · Valid · High (architecture)**

**Review:** Optimization — one job service; queue per repo; cache branch/status/remotes.  
**Assessment:** Valid; underpins #3 and reduces duplicate `git` processes.  
**Action:** Design after #1–#3 so all forms share one runner.

---

### 22. Filesystem watcher instead of multi-second Git poll — **Defer · Valid · Medium**

**Review:** Optimization — debounced watcher + slow fallback poll.  
**Assessment:** Valid, platform-fiddly (especially network mounts). Worth after reliable job runner and porcelain digest (#7).  
**Action:** Defer until poll correctness is fixed.

---

### 23. Graph lane layout via SHA→lane map — **Defer · Valid · Low–Medium**

**Review:** Optimization — free-list / map instead of scanning active lanes.  
**Assessment:** Valid micro-optimization; only matters on huge multi-lane histories.  
**Action:** Profile first; then rewrite layout if needed.

---

### 24. On-demand commit metadata with cancel + cache — **Partial · Valid · Medium**

**Review:** Optimization — load details on demand, cancel stale, cache.  
**Code:** Visible-range detail loading already exists; cancellation/generation still weak (#1–#2).  
**Assessment:** Direction good; finish with generation IDs and a small LRU cache.  
**Action:** Tie to worker redesign.

---

### 25. Split `GitDiffView` into model / patch / render / UI units — **Open · Valid · Medium (maintainability)**

**Review:** Simplification — 3,200+ line unit.  
**Code:** Still ~3,283 lines; mixed highlighter, selection, patch, overview, SynEdit host.  
**Assessment:** Valid for testability and patch correctness (#8).  
**Action:** Split after patch model extraction so tests do not need the LCL frame.

---

### 26. Repository-scoped client instead of global `GitClient` path/error — **Open · Valid · Medium**

**Review:** Simplification — mutable global `RepoPath` / `LastError` races.  
**Assessment:** Valid under concurrent jobs.  
**Action:** Immutable workdir per call or per-repo instance; thread-local or job-owned errors.

---

### 27. Structured Git commands everywhere (`-z`, formats) — **Open · Valid · High**

**Review:** Simplification — remove ad-hoc quote/arrow parsing.  
**Assessment:** Same family as #5/#9; do as one protocol pass.  
**Action:** Standardize helpers in `GitService`.

---

### 28. Remove unused `SynEditDsgn` dependency — **Open · Valid · Low–Medium**

**Review:** Simplification — drop if unused. Review claimed removed.  
**Code:** `Packages/LazRepositoryTools.lpk` still requires `SynEditDsgn`.  
**Assessment:** Valid if build confirms unused — faster package install.  
**Action:** Clean build without it; remove if link succeeds.

---

### 29. Atomic `.gitignore` writes + shared safe text-save helper — **Open · Valid · Medium**

**Review:** Simplification / correctness.  
**Code:** `AppendIgnorePatterns` loads/saves with `TStringList` directly.  
**Assessment:** Valid small hardening.  
**Action:** Temp file + replace; share with assistant package later.

---

### 30. Operation panel with progress, Cancel, copyable error — **Open · Valid · High (UX)**

**Review:** UX — “See log” useless without visible log.  
**Assessment:** Valid and user-visible; pairs with #3.  
**Action:** Panel or status strip: command, repo, elapsed, Cancel, last error text.

---

### 31. Default show untracked (or make hidden state obvious) — **Open · Valid · Medium (UX)**

**Review:** UX — untracked hidden by default hides new work.  
**Code:** `FormCreate` still forces `UntrackedCheck.Checked := False`.  
**Assessment:** Valid product default.  
**Action:** Default True, or bold “Untracked hidden” when off.

---

### 32. Dirty/conflict guard before checkout/reset/restore — **Open · Valid · Medium (UX)**

**Review:** UX — show dirty/conflicted files; stash / new branch / cancel.  
**Assessment:** Valid safety UX.  
**Action:** Preflight dialog with file list and actions.

---

### 33. Post-clone offers (open project / folder / submodules) — **Defer · Valid · Low–Medium**

**Review:** UX after clone.  
**Assessment:** Nice; not blocking correctness.  
**Action:** After clone reliability (#18) and async clone (#3).

---

### 34. Conflict-aware editable shortcuts (e.g. avoid `Ctrl+Shift+C`) — **Defer · Valid · Low**

**Review:** UX shortcuts.  
**Assessment:** Valid once shortcuts are audited against IDE defaults.  
**Action:** Settings page or IDE keymap integration later.

---

### 35. Accessibility: theme colors, icons/patterns, legend, keyboard hunk nav — **Partial · Valid · Medium (UX)**

**Review:** UX — color alone insufficient.  
**Recent session:** Graph selection under edges; 45° hunk markers; double-click hunk select; Files ActionList staging UX improvements.  
**Assessment:** Valid; partial progress on hunk affordances only.  
**Action:** Theme-derived colors, legend, keyboard next/prev hunk, non-color status cues.

---

### 36. Per-file/hunk undo for stage/unstage + preserve selection after refresh — **Open · Valid · Medium (UX)**

**Review:** UX undo / selection preserve.  
**Assessment:** Valid for trust in partial stage.  
**Action:** Stack last patch ops; restore list selection/scroll after refresh.

---

## Recent session items (not in ChatGPT review, but repository-manager)

These were addressed while fixing designer corruption and Files/History UX. Tracked here so the report matches reality.

| Item | Status |
|---|---|
| `TGitMixedDiffHighlighter` owned with `Create(Nil)` so designer cannot stream nameless objects into host LFM | **Completed** |
| Strip corrupt `object TGitMixedDiffHighlighter` from `ManageRepositoryForm.lfm` (+ stale `Lib/` copy) | **Completed** |
| Files tab commands via `TActionList` (stage/unstage/revert/delete/ignore, etc.) | **Completed** (in prior session work) |
| Stage All respects filtered `FFilesPaths` | **Completed** |
| Graph paint order (selection under edges), hunk markers, double-click hunk select | **Completed** |
| Free-pascal skill: no `Create(Self)` for runtime-only frame helpers that stream | **Completed** (skill) |

None of the above close ChatGPT P1 items #1–#9; they close a separate designer AV / UX track.

---

## Explicitly not “Completed” despite review claims

Cross-check where the review’s status table overstates the tree:

| Claimed fixed (review) | Current tree |
|---|---|
| NUL-delimited porcelain | Still line porcelain + quote/arrow parse |
| All merge parents | Still max 4 parents |
| Path containment | Still lexical join |
| `git apply --check` | Not present |
| Empty clone folder | Still rejected if exists |
| One-time config migration | Still default-equality migration |
| Concurrent stderr drain | Binary path post-drain only; text path merges |
| Worker `Synchronize`/leak fixes | `Synchronize` + `WaitFor` remain; detail free missing |
| Remove `SynEditDsgn` | Still in `.lpk` |
| Untracked shown by default | FormCreate forces unchecked |

Treat those as **still Open** unless re-verified after a dedicated hardening PR.

---

## Suggested implementation order (repository manager only)

1. **Thread safety:** #1, #2 (deadlock + leak) — **done** (Queue + generation + main-thread free).  
2. **Git process protocol:** #4, #5, #10, #27 (drain, porcelain `-z`, patch bytes).  
3. **UI freeze / jobs:** #3, #6, #7, #21, #30 (async runner, no full-tree scan, dirty digest, op panel).  
4. **Patch correctness:** #8, #9, #25 (model extract, check, split unit).  
5. **Safety / remotes / config:** #11, #15–#18, #29.  
6. **Graph / events / bounds:** #12–#14, #19–#20.  
7. **UX polish:** #31, #32, #35, #36; then #22–#24, #33–#34, #28.

---

## Worth summary

| Bucket | Count | Guidance |
|---|---|---|
| Critical Open/Partial | ~4 | Do before treating package as stable (#1–#3, leaks). |
| High protocol/perf | ~8 | Porcelain, drains, refresh, patch, jobs. |
| Medium correctness/UX | ~15 | Remotes, paths, parents, events, defaults, a11y. |
| Defer / low | ~5 | Watchers, lane micro-opt, post-clone offers, shortcuts. |
| Recent session Completed | 6 | Designer AV + Files/History UX (orthogonal to ChatGPT P1s). |

**Bottom line:** ChatGPT’s repository findings remain largely **valid and worthwhile**. The highest-value unfinished work is **worker lifecycle (#1–#2)**, **async Git jobs (#3)**, and **machine-readable Git status/paths (#5/#6/#7)**. Treat the review’s “already fixed” list as aspirational history, not as a green board for the current sources.
