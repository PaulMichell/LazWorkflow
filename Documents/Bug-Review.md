# LazWorkflow bug review

**Date:** 18 September 2026  
**Tree:** `684e087` (`Tools: add PascalStyle command-line formatter`) plus uncommitted documents and test binaries (not reviewed).  
**Scope:** Current Pascal sources under `Source/LazAssistantTools`, `Source/LazRepositoryTools`, `Source/LazWorkflowCommon`, and `Source/LazStyledText`. Tests were used as supporting evidence, not as a substitute for tracing the product paths.

This is a correctness review of the code that is in the tree today. Earlier audits (`Documents/LazWorkflowReview.md`, `Documents/LazWorkflowCommon-and-LazRepositoryTools-Review.md`, the ChatGPT notes, `Documents/Plugin-Lifecycle-Hardening.md`) were treated as claims to re-check, not as current findings. Many of those items are fixed. Missing Grok Build features (command runner, completion gate, skill routing) are out of scope unless they make an advertised path do the wrong thing.

**How to read priorities**

| Priority | Meaning |
|---|---|
| **P0** | Security or sandbox break, or a write that can leave the user's machine or repository wrong without a further warning. |
| **P1** | Crash, hang, data loss, or a Git/tool action that mutates the wrong files. |
| **P2** | Edge-case incorrectness that is real but narrower. |

Line numbers are for this tree.

---

## P0

### 1. xAI OAuth tokens are stored in plaintext, world-readable IDE XML

**Where:** `Source/LazAssistantTools/AssistantConfig.pas:362`, `Source/LazAssistantTools/GrokOAuth.pas:538` and `:897`, `Source/LazAssistantTools/ProjectAssistantForm.pas:778`

`TAssistantConfig.Save` writes `OAuth/AccessToken` and `OAuth/RefreshToken` through `GetIDEConfigStorage`. Every successful refresh calls `PersistTokens` → `Save`. Closing the Assistant form writes them again.

On this host `/home/paul/.lazarus/LazAssistantTools.xml` is mode `0664` (`-rw-rw-r--`) and contains a live access token (~822 bytes) and refresh token (~86 bytes). Any local account that can read that file can steal a long-lived SuperGrok / X Premium session.

There is no `chmod`, keyring, or session-only path. An older review claimed credentials were process-memory only; that is no longer true.

**Fix:** Keep tokens in process memory by default. If persistence is required, use a `0600` file or the OS credential store, purge the existing XML values, and never write tokens on a world-readable umask.

### 2. Native `write_file` / `write_markdown` follow a dangling symlink out of the project

**Where:** `Source/LazAssistantTools/AssistantTools.pas:584` (`IsPathUnderRoot`), `:1808` (`SaveProjectFileText`), `Source/LazAssistantTools/AssistantPlan.pas:74` (`PlanIsUnderRoot`), `:335` (`WriteMarkdownFile`), `Source/LazAssistantTools/AssistantWorkTarget.pas:69`

Containment only `GetPhysicalFilename`s an **existing** ancestor. `FileExistsUTF8` / `DirectoryExistsUTF8` are false for a dangling symlink, so the walk stops at the project directory and the lexical path is allowed. `TFileStream.Create(..., fmCreate)` and `TStringList.SaveToFile` then `open(O_CREAT)` without `O_NOFOLLOW` and create the outside target.

The safe publisher `CreateNewProjectText` (`AssistantFileCreation.pas`, `openat` + `O_NOFOLLOW` + `linkat`) is used by Codex `lazarus_create_file` and is tested against this exact dangling-link case. Native Build `write_file` never calls it. Existing symlinks whose targets exist are rejected (physical path leaves the root). The hole is the dangling destination.

**Fix:** `lstat` every component, including the leaf. Reject `S_ISLNK`. Create via the existing `O_NOFOLLOW` helper (or equivalent on Windows). Do not open with `fmCreate` / `SaveToFile` on a path that has not been proven regular and inside the root.

---

## P1

### 3. `grep` / `search_in_project` follow directory symlinks out of the tree

**Where:** `Source/LazAssistantTools/AssistantTools.pas:1424`, `:2116`

`CollectSearchableFiles` recurses into every `faDirectory` that is not a skipped name (`.git`, `lib`, …). It does not test `faSymLink` and does not re-run `IsPathUnderRoot` / `GetPhysicalFilename` on children. A project directory that is a symlink to `/etc` or a home folder is opened with `LoadFromFile` and returned as a project-relative path.

`read_file` of that symlink itself is rejected when the target exists. The leak is recursive search from a parent directory. Empty extensions are treated as text (`IsSearchableTextExtension`, line 1456), so unnamed FIFOs are in the same walk (see 7).

**Fix:** `lstat` and skip symlink directories, or drop any child whose physical path is outside the work-target root.

### 4. IDE-thread tools keep running after the actor reports a 30-second timeout

**Where:** `Source/LazAssistantTools/AssistantActor.pas:650–770`

`TIdeToolDispatch` is a per-call object, which retires the old shared-field race. `FAbandoned` is checked **only before** `ExecuteOnMain` starts the tool. If the callback is already inside `ExecuteAssistantToolForMode`, `run_compile` (up to 600 s), `run_git`, `write_file`, or `ensure_form_component` continue on the IDE thread after the model has been told `Timed out waiting for the IDE thread` and may retry the same mutation.

Cancel uses the same flag. Tools that do not poll `ToolsShouldStop` still finish.

**Fix:** Recheck a run token after approval and before mutation. Wait as long as the tool's own deadline, or cancel the tool. Do not report timeout while a write/compile is still running.

### 5. Quiet `lazbuild` is not killed as a process group; `TProcess.Free` can hang the IDE thread

**Where:** `Source/LazAssistantTools/AssistantTools.pas:1606–1684`

Timeout/cancel only `Proc.Terminate`s the lazbuild parent (no `setsid`, unlike `AssistantBuildJob.pas:135` / `:410`). Compiler grandchildren keep running. `AbortRunning` then `Exit`s into `Finally Proc.Free`; `TProcess.Destroy` waits on a still-running process. Combined with 4, a “timed out” compile can freeze the IDE indefinitely.

`RunProcessCapture` also stores `Proc.ExitStatus` (Unix wait status) rather than `ExitCode`, so a failing compile is reported as exit 256 instead of 1.

**Fix:** Mirror the async build job: new session, `kill(-pid, SIGKILL)` on timeout/cancel, bounded `WaitOnExit`, never `Free` a live process on the IDE thread. Decode the exit code with `WEXITSTATUS` / `ExitCode`.

### 6. Build-mode `git add` still treats `[…]` as a pathspec

**Where:** `Source/LazAssistantTools/AssistantGit.pas:100–129`

`add` requires `--` and rejects `*`, `?`, `..`, and absolute paths, but never passes `--literal-pathspecs` and does not reject `[`. `git add -- literal[1].txt` still stages `literal1.txt`. Repository tools already pass `--literal-pathspecs` on every process (`GitService.pas:443`). Assistant Git tests do not cover brackets. Package-mode commit later re-checks staged names; project-mode commit does not.

**Fix:** `git --literal-pathspecs add -- <paths>`, and reject `[`, `]`, and other pathspec magic. Add the two-file bracket case from `RepositorySafetyTest`.

### 7. Native `read_file` / grep can block forever on a FIFO

**Where:** `Source/LazAssistantTools/AssistantTools.pas:975`, `:2116`; contrast `AssistantIDEWorkspace.pas:212`

The Codex inspect path rejects non-regular files (`fpStat` + `FPS_ISREG`). Native `read_file` opens anything under the root with `TFileStream` on the IDE thread. Grep `LoadFromFile`s search hits with no regularity check and does not sample `ToolsShouldStop` inside the read, so a FIFO hangs the worker past the 8 s search deadline.

**Fix:** `lstat` + `S_ISREG` (and a size cap) before every disk open in `ToolReadFile` and search.

### 8. Disk writes truncate the destination before the new bytes are durable

**Where:** `Source/LazAssistantTools/AssistantTools.pas:1808`, `Source/LazAssistantTools/AssistantPlan.pas:335`

`fmCreate` / `SaveToFile` truncate the file, then write. A disk-full or I/O error in `WriteBuffer` returns failure with the original content already gone. `CreateNewProjectText` publishes via a sibling temp + `linkat` and does not truncate an existing file.

**Fix:** Write a sibling temp on the same directory, `fsync`, `rename` over the destination after a non-symlink `lstat`. On failure, leave the original file intact.

### 9. StyledText / conversation paint after the destructor has freed the bitmap and layout

**Where:** `Source/LazStyledText/StyledSurface.pas:111` and `:274`, `Source/LazAssistantTools/AssistantConversationSurface.pas:135` and `:559`, `Source/LazStyledText/StyledControls.pas:226` and `:321`

`TStyledSurface.Destroy` frees scrollbars, renderer, and `Bitmap`, then calls `Inherited Destroy`. `TWinControl.DestroyHandle` can still deliver a paint. `Paint` uses `Bitmap` with no `Assigned` / `csDestroying` guard. The conversation surface frees `FLayout` first; `PaintContent` then reads `FLayout.TotalHeight`. Markdown preview does the same with `LayoutState`. `Tick` / `GeometryChanged` already check teardown; paint does not. `PluginFormLifetimeTest` never shows the Assistant, so it does not catch expose-on-destroy.

`StyledCanvas.EnsureStops` can also raise `'The canvas cannot return text advances'` from the paint path (`StyledCanvas.pas:568`) with no handler in `TStyledSurface.Paint`.

**Fix:** Keep bitmap/layout alive through `Inherited Destroy`, or guard every paint path. Do not raise from `GetTextExtentExPoint` failure; fall back to a width estimate.

### 10. Revert of a staged rename leaves a deletion staged and deletes the new file

**Where:** `Source/LazRepositoryTools/GitService.pas:1043`, `Source/LazRepositoryTools/ManageRepositoryFiles.pas:215`

`UnstagePaths` expands a rename destination to include `OldPath`. `RevertPaths` does not. The Files pane stores only `Entry.Path`, so Revert of a `git mv` row runs `git restore --source=HEAD --staged --worktree -- dest`. That stages `D  main.txt` and removes `renamed.txt` from the worktree. A following commit drops the original file.

**Fix:** Reuse the unstage rename expansion (index `R` plus `OldPath`) inside `RevertPaths`. Cover `git mv` revert in `RepositorySafetyTest`.

### 11. “Ignore” on a selected filename writes a gitignore glob

**Where:** `Source/LazRepositoryTools/GitService.pas:1111`, `Source/LazRepositoryTools/ManageRepositoryForm.pas:1531`

Selected paths are slashed, optionally prefixed with `/`, and written as gitignore lines with no escaping of `[ ] * ? \ !`. `/literal[1].txt` does not ignore `literal[1].txt` and does ignore `literal1.txt`. The Ignore Files editor is free-form gitignore and is not this bug.

**Fix:** Write a gitignore-literal for a selected path (escape glob metacharacters, including a leading `!` or `#`).

### 12. Amend / Remove can rewrite a HEAD that was just pushed

**Where:** `Source/LazRepositoryTools/ManageRepositoryForm.pas:672` and `:1260`, `Source/LazRepositoryTools/GitJobRunner.pas:840`

`CanRewriteLastCommit` uses `FHeadPushed` from the last probe. Successful `gjkPush` does not set `FHeadPushed := True`. The handler shows a modal dialog, then refreshes; the probe that would mark HEAD published is not even queued while the dialog is up. Amend/Remove stay enabled and will `reset` a commit that is already on the remote.

`gjkPrepareAmend` / `gjkRemoveLastCommit` never call `IsCommitPushed` themselves.

**Fix:** Set `FHeadPushed := True` on a successful push of HEAD. In the amend/remove jobs, refuse if HEAD is published or the query fails. Do not trust the UI flag.

### 13. History restore and session save drop tool-call and Responses state

**Where:** `Source/LazAssistantTools/ProjectAssistantForm.pas:2507` and `:3834`, `Source/LazAssistantTools/AssistantService.pas:1784`, `Source/LazAssistantTools/AssistantSession.pas:141`

Three related holes, one user-visible effect (the next model turn is sent without tool IDs or encrypted reasoning):

1. `RebuildClientFromConversation` (History combo) only `AddMessage`s prompt/response text. Tool-call ids and `ToolCallsJson` are dropped even when `Turn.TraceJson` still has the cards. `PersistSession` then overwrites `.lazgrokchat-session` with the stripped list.
2. `GetMessage` does not return `ResponsesOutputJson`, so JSON session save cannot persist it. `RestoreMessage` always sets it to `''`.
3. A finished text reply is recorded with `AddMessage(amrAssistant, FLiveContent)`, which never stores the last Responses output array. The next user turn therefore omits encrypted reasoning items from `BuildResponsesRequestJson`.

In-turn replay of `ResponsesOutputJson` for tool rounds exists (`ExportSamplerItems`, `AssistantService.pas:1438`). It does not survive History, process restart, or the following user message.

**Fix:** Persist the output array and tool metadata with each assistant message, restore them, rebuild History from that record (not display text), and export them on the next Responses request.

### 14. Stream snapshots and message history are shared across threads without a lock

**Where:** `Source/LazAssistantTools/AssistantActor.pas:428` and `:343`, `Source/LazAssistantTools/AssistantService.pas:1124` and `:1390`

The worker writes `FContent` / `FThinking` unlocked. `NotifyMain` copies those managed strings under `FSnapLock` on the IDE thread. FPC string assignments are not atomic.

`FMessages` has no lock. The actor mutates it on the worker (`AddToolResult`, `ExportSamplerItems`, steer). The IDE thread can iterate it from `GetContextBreakdown` while a send is in progress (footer click is not disabled). Concurrent `SetLength` vs `High(FMessages)` is a use-after-realloc.

**Fix:** Copy `FContent` / `FThinking` only under `FSnapLock`. One service lock around history reads and writes, or marshal all `FMessages` access onto the actor thread.

### 15. Commit-message suggestion runs `AssistantClient` on the Git worker

**Where:** `Source/LazRepositoryTools/GitJobRunner.pas:816`, `Source/LazAssistantTools/AssistantMain.pas:197`

`gjkSuggestMessage` calls `SuggestCommitMessageFunc` on the Git worker. The handler uses the process-wide `AssistantClient`: `ApplyConfig` and `CompleteOnce`. `CompleteOnce` reads and writes unsynchronized `FBusy`; chat `StartStream` uses the same flag. Suggest while a turn is running can overlap HTTP, leave `FBusy` stuck, or tear shared endpoint/model strings. The worker already avoids publishing `WorkflowEventBus` for this reason.

**Fix:** Run the suggestion on the IDE thread, or on a dedicated service that does not share `AssistantClient` / `FBusy` with chat. Fail if a chat request is already in progress.

### 16. Plan/Markdown tools overwrite disk without the open viewer’s dirty buffer

**Where:** `Source/LazAssistantTools/AssistantPlan.pas:335` and `:662`, `Source/LazAssistantTools/AssistantMarkdownForm.pas:154` and `:189`

`WriteMarkdownFile` / `ReplaceInMarkdownFile` save model content to disk without consulting an open `TAssistantMarkdownForm`. If that viewer is dirty, unsaved buffer text is not merged. `OpenMarkdownDocument` then `ReloadFromDisk(False)`, so the user keeps seeing stale unsaved text with `FPendingDiskReload`. `SetPlanSectionStatus` writes from a fresh disk load and `ReloadMarkdownDocument(..., True)`, which prompts and can discard in-memory edits.

Silent force-reload of a clean window is fixed. Unmerged disk write plus confirm-to-discard is not.

**Fix:** If a viewer for the path is dirty, refuse the write, or apply the patch to the editor buffer and let the user save. Do not `Force` reload after an unmerged disk write.

### 17. Package-target `write_markdown` is rejected before the default plan path is applied

**Where:** `Source/LazAssistantTools/AssistantTools.pas:2900`, `:1199`

Package-mode `CheckTarget` resolves the raw JSON `path` and requires `AllowsWrite`. An omitted path becomes the working root (`ResolveProjectPath('')`). `AllowsWrite(Root)` is false for packages (the root is not a member directory), so the tool is rejected as “outside the selected package write scope” even though the tool would then default to `Documents/Plan.md`, which is allowed. Projects are unaffected.

**Fix:** Apply the same path defaulting as the Markdown tools before `AllowsWrite`.

### 18. Quiet `run_compile` does not pass the active build mode

**Where:** `Source/LazAssistantTools/AssistantTools.pas:1903`; contrast `AssistantIDEWorkspace.pas:708`

Quiet `lazbuild` is invoked with only `--build-all` (optional) and the manifest. It does not pass `--build-mode=` (`AssistantTarget.BuildMode`) or, for packages, `--pcp=` / `--widgetset=` as `StartAssistantBuild` does. A non-default IDE configuration is therefore not what quiet compile builds. The model can treat `COMPILE_CLEAN=1` as evidence for the wrong widgetset or mode.

**Fix:** Pass the same lazbuild arguments as the async build job.

### 19. Package UI compile skips saving editor files

**Where:** `Source/LazAssistantTools/AssistantTools.pas:2474`

`ui=true` package compile calls `DoCompilePackage(..., [pcfDoNotSaveEditorFiles], ...)`. The comment claims the quiet path already flushed; the UI path does not call `FlushOpenEditorsUnderProject`. Project UI compile uses `DoBuildProject` without that flag. Package UI compile therefore uses stale disk buffers. Broker `StartBuild` correctly refuses `Modified` / `ModifiedDesign` instead.

Quiet flush also skips `ModifiedDesign` without `Modified` (`AssistantTools.pas:1852`), so a designer-only LFM change is omitted from `lazbuild` while Git refuses to commit.

**Fix:** Flush authorized buffers (or refuse dirty ones) before `DoCompilePackage`. Use the same `Modified or ModifiedDesign` predicate as Git/build.

### 20. Remotes grid hides `pushurl`, so an edit changes fetch only

**Where:** `Source/LazRepositoryTools/GitService.pas:2086` and `:2134`, `Source/LazRepositoryTools/GitRemotesForm.pas:366`

`ListRemotes` drops `(push)` lines. `SetRemoteUrl` is `git remote set-url` without `--push`. A distinct `pushurl` stays hidden; the safety test even asserts it is preserved. Editing origin in the grid therefore changes fetch while later pushes still use the old push URL.

**Fix:** Load and save fetch URL and push URL as separate fields. Show both. Treat an empty push URL as “same as fetch”.

### 21. Queued IDE-tool exceptions are not caught

**Where:** `Source/LazAssistantTools/AssistantActor.pas:672`

`ExecuteOnMain` has `Try/Finally` and no `Except`. The callback is `TThread.Queue(Nil, …)`, so a raise runs on the IDE thread after `FDone` is set. The actor treats the tool as `Error: ` with an empty message while Lazarus still sees an uncaught exception.

**Fix:** Catch `Exception` in `ExecuteOnMain`, store `E.Message`, set `FOk := False`, and do not re-raise.

---

## P2

22. **`EnsureUsesHasUnit` is a substring search** (`AssistantTools.pas:2644`). The first `uses` in comments, `Unit Causes;`, or identifiers can be rewritten. `ensure_form_component` then saves `.pas` before `.lfm` (`:2863`), so an LFM save error leaves Pascal already changed.

23. **`ensure_form_component` does not change an existing component's class** (`AssistantLfm.pas:481`). Property merge keeps children (good) but never rewrites `object Name: TClass`. `EnsurePublishedField` skips when `name:` appears anywhere, so advertised “add or update” cannot change the streamed type.

24. **SSE parser buffer is unbounded** (`AssistantSampler.pas:278`). `Feed` concatenates every chunk and runs two `StringReplace` passes over the whole buffer. The actor caps only `FResponsePrefix` at 16 KiB. A huge unterminated line can hang the actor.

25. **Codex `Stop` signals a reaped PID** (`AssistantCodexTransport.pas:152`). Live-child kills correctly require `ProcessID > 0`. After `WaitOnExit(500)` it always `fpKill(-pid, SIGKILL)` again. That PID can be recycled.

26. **`FOnTrace` is read unlocked** (`AssistantActor.pas:278`, `:297`). `Detach` writes it under `FSnapLock`. A torn method pointer after detach is the residual risk; `FOnToken` is already copied under the lock.

27. **`AppendTurn` rollback holes** (`AssistantConversation.pas:571`). Index-write failure now truncates the conversation file. `EntryFromTurn` raising after `WriteBuffer`, or `FIndex.Add` failing after a successful index append, can still leave a JSONL line that `Load` will resurrect (and a retry can duplicate).

28. **Session `contextUsed` can raise after history is cleared** (`AssistantSession.pas:219`). Non-array `transcript` / `messages` are checked. `Root.Get('contextUsed', 0)` still `AsInteger`s a present non-numeric value outside the parse handler, after `ClearHistory`.

29. **Settings `ProcessMessages` while modal** (`AssistantSettingsForm.pas:445`, `:619`). Nested processing can run close or a second sign-in. Replace with a direct repaint.

30. **Amend unpacks HEAD with no confirmation** (`ManageRepositoryForm.pas:1695`). Remove asks first. An accidental Amend is a soft `reset HEAD~1`; switching repository clears `FAmendHead` while the previous repo is already unpacked.

31. **Unborn HEAD is shown as SHA `(initia`** (`GitService.pas:796`). Porcelain v2 `# branch.oid (initial)` is stored as `HeadSha`; `IsCommitPushed('(initial)')` fails. Rewrite stays disabled (`HeadPushedKnown` remains False). Treat `(initial)` as no HEAD.

32. **Closing the repository manager does not cancel queued jobs** (`GitJobRunner.pas:948`). `CancelIfHandler` only marks `FCurrent`. `DetachFinishedHandler` nils the callback, so a queued commit/checkout still runs after the window is gone.

33. **Bind can show conversation JSONL while the model session is empty** (`ProjectAssistantForm.pas:3214`). Session file and `conversation.jsonl` are independent. If session load fails after `AppendTurn`, the canvas shows the last turn and the next request has no history.

---

## Retired prior findings

These were real in earlier reviews and are **not** open in this tree. They are listed so the older documents are not treated as a current bug list.

| Claim | Status |
|---|---|
| `TrimMessagesForBudget` walks off a shortened array | Fixed (`While I <= High(FMessages)`) |
| `ExportSamplerItems` undersized result array | Fixed (dynamic grow) |
| `response.failed` accepted as a successful reply | Fixed (`FParser.Failed` / incomplete checked) |
| `FHttpControl` abort use-after-free | Fixed (`FHttpLock` held across `Abort`) |
| Session restore dropped `toolCallsJson` | Fixed for the JSON format; Responses output is still missing (13) |
| Timeout detach leaked the actor thread | Fixed (orphan list + reaper) |
| Windows POST replay after WinINet send | Fixed (`RequestSent` skips fallback) |
| Subagent `Finished`/`FailText` races | Fixed (`SnapshotState` under `FLock`) |
| Child service freed while the actor held it | Fixed (`RegisterAbandonedService`) |
| Timed-out callback wrote the next tool's fields | Fixed as originally stated; in-flight tools still run (4) |
| Chat Completions fallback on any HTTP 400/403 | Fixed (404/405/501 only) |
| Session `As TJSONArray` into the IDE | Fixed (`Is TJSONArray`) |
| LFM upsert missed indented `object`, destroyed children, `Caption = Go` | Fixed (`AssistantLfm.pas`, `AssistantLfmTest`) |
| Tools vs chat disagreed on project root | Fixed (`AssistantTarget.Root` / `ResolveAssistantProjectRoot`) |
| `read_file` ignored `max_chars` on a long line | Fixed (streaming + mid-line budget) |
| Quiet compile never saved buffers | Fixed for `Modified`; designer-only gap remains (19) |
| `FindAllFiles` materialized the whole tree | Fixed (capped walk) |
| Markdown force-reload discarded unsaved edits silently | Fixed; unmerged tool write remains (16) |
| `run_git` allowed `push` / `reset --hard` / `--amend` | Fixed (allowlist) |
| Git filenames as pathspecs (repository tools) | Fixed (`--literal-pathspecs`); Assistant Git still open (6) |
| `.gitignore` dangling symlink write | Fixed (`WorkingTreeFullPath` / `SaveIgnoreFile`) |
| Unstage rename left a deletion staged | Fixed for unstage; Revert still open (10) |
| Stale Git job applied to a rebound repo | Fixed (`RepoGeneration`) |
| Job detach missed queue→current / current→deliver | Fixed (both under the runner lock) |
| Partial unstage used the wrong side of the hunk | Fixed (`Reverse` keeps index-side context) |
| `---` / `+++` content treated as diff metadata | Fixed (hunk-count parser) |
| Root / merge commit diffs missing | Fixed (`--root --diff-merges=first-parent`) |
| Clean + untracked hid existing files | Fixed (`MergeGitFileEntries`) |
| Unix `ExitStatus` vs exit code in `GitService` | Fixed (`WEXITSTATUS`); still wrong in `RunProcessCapture` (5) |
| Failed `--no-index` diffs reported success | Fixed (exit 1 + empty stderr only) |
| Auto-refresh missed further edits to an already-dirty file | Fixed (always refresh the selected diff) |
| Apostrophe-only token stopped the spell scanner | Fixed |
| Hard-newline caret belonged to no row | Fixed |
| Spell library path change silently kept the old `.so` | Fixed (bind fails and asks for restart) |
| External popup menus retained spell-memo callbacks | Fixed (`FreeNotification`) |
| Git `Terminate` with PID 0 signalled the IDE | Fixed (`ProcessID > 0` after `Execute`) |
| `CreateForm` double-free on constructor failure | Fixed (assign only after `Create` returns) |
| Event bus invoked listeners under the lock / raw interfaces | Fixed (subscription tokens, snapshot outside lock) |
| Git stderr pipe deadlock | Fixed (drain both streams in one loop) |
| `Synchronize` deadlock on detail-thread stop | Fixed (jobs + `TThread.Queue`) |
| Octopus merges capped at four parents | Fixed (dynamic parent array) |
| Remotes save removed-before-add | Fixed (snapshot + rollback); hidden `pushurl` remains (20) |
| Clone rejected an existing empty folder | Fixed |
| Quiet IDE disk-check left disabled after cancel | Fixed (`AssistantResetQuietIdeSession` in `Destroy`) |
| Form factory / stream callbacks into a destroyed view | Fixed (detach before cancel; reconnect test) |

---

## What this review did not do

- Live IDE clicks, OAuth against x.ai, or a real `git push` of a user's branch.
- Windows junction / macOS tests (dangling-symlink and `setsid` behaviour are Linux-traced).
- Exhaustive StyledText layout fuzzing beyond the destructor/paint path.
- Product-parity gaps versus Grok Build (no general `run_command`, no completion gate, no semantic compaction). Those are design work, not defects in the current contract.

Highest-leverage fixes: stop writing OAuth tokens in XML; route native file creates through the existing `O_NOFOLLOW` publisher; skip symlink dirs in search; wait-or-kill IDE tools instead of abandoning them at 30 s; pass `--literal-pathspecs` in Assistant Git; expand rename revert the same way as unstage.
