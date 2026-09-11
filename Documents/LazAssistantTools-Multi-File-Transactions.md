# Multi-file editor changes and recovery

Implemented: 11 September 2026.

This completes the initial multi-file change-set foundation in the shared broker and ChatGPT preview. It supports coordinated edits to already-open project text buffers, with a combined review, revision checks, native Undo and explicit recovery outcomes. It does not yet turn CodeTools reference results into a complete project-wide rename.

## Workflow

1. Open each affected project file and call `lazarus_read_buffer` to obtain its current text and revision.
2. Call `lazarus_prepare_changes` with a `changes` array. Each entry supplies `path`, `revision` and the complete proposed `text`. Preparation changes no source text and returns a `change_set_id`. Preparing another set replaces the pending preview; starting or cancelling a run discards it.
3. In Build mode, call `lazarus_apply_changes` with that ID. The connection's existing approval policy applies. When approval is required, the dialog shows all before/after buffers with file headings. The preview is consumed even if declined or rejected, preventing accidental replay.
4. Inspect the receipt's overall state and each file's state. Reread affected buffers before further edits or explicit `lazarus_save_buffer` calls. Applying does not save or build.
5. Use `lazarus_change_status` with the ID to inspect the retained outcome. Omit the ID to list receipts for the active project. In Build, `lazarus_revert_changes` reviews and restores eligible edits from a receipt without saving.

Preparation and status are available in Ask, Plan and Build. Coordinated apply/revert currently require Build, including all-Markdown sets. Plan retains its existing individual Markdown edit/create/save tools.

## Validation and recovery

Preparation requires current nonempty broker revisions and unique resolved editor paths. All inputs are checked again before review, after approval, before every individual write and after the final write. Validation includes exact bytes, active project/run, writable editor, editor lifetime identity and SynEdit's change stamp. Nested broker calls during a transaction are rejected.

Every actual edit uses the existing Lazarus editor replacement path. Each file has its own native Undo operation. Explicit recovery is another undoable edit; there is no global IDE Undo transaction.

A file becomes eligible for automatic recovery only after the adapter confirms the write and exact proposed text is read back with a changed stamp. If application fails, recovery visits confirmed edits in reverse order. It restores a buffer only when its text, editor identity and stamp still match the recorded result. Later user edits are preserved, even if the user subsequently restores the same text. Closed/reopened or read-only editors are skipped.

Cancellation or a project switch stops further writes and automatic recovery. Receipts survive subsequent runs in the same assistant panel; after returning to the original project, explicit recovery can restore earlier confirmed edits. Receipts from other projects are not exposed.

An exception or interruption during mutation can leave an uncertain result. Such a file is marked `unknown`, and its ownership is not inferred from matching text. It must be inspected and recovered manually, for example with native Undo. Unexpected newline normalization also prevents a successful exact-text confirmation. These are logical transactions with reported partial outcomes, not atomic multi-file writes.

## Receipt states and limits

| State | Meaning |
| --- | --- |
| `prepared` | Pending preview; no source edits. |
| `rejected` | Application did not begin, or approval was declined/invalidated. |
| `applied` | All proposed buffers were confirmed. |
| `rolled_back` | Application failed and every confirmed assistant edit was restored. Unrelated user changes may remain. |
| `reverted` | An explicit recovery completed for eligible edits. |
| `partial` | Recovery was interrupted or at least one file has a conflict/unknown outcome. |

Per-file states distinguish pending, unchanged, applied, restored, conflict and unknown. `hasRecoverySnapshot` means the receipt retains ownership data for an edit; recovery must still validate it. The top-level error can retain the original application/approval failure after subsequent recovery; inspect the current state and per-file outcomes as well.

Supported names and physical targets are Pascal (`.pas`, `.pp`, `.lpr`, `.dpr`, `.inc`), Markdown (`.md`, `.markdown`, `.mdown`) and `.txt`. Project/designer metadata, including `.lpi`, `.lpk`, `.lps` and `.lfm`, is excluded. Existing project-root/path checks apply. Files must already be open in writable SynEdit buffers.

A set contains 1–16 files, with at most 1 MiB per source/proposed buffer and 2 MiB combined before/after text. The existing approximately 1 MiB serialized tool-argument limit also applies. At most 32 consumed receipts and 8 MiB of before/after recovery text are retained; exceeding a limit rejects preparation rather than silently dropping earlier recovery data.

Receipts are in memory only. Closing the assistant panel or restarting the IDE discards them. No durable journal, disk rollback, file creation/deletion/rename, project membership change or designer transaction is included. Grok's native tools have not yet migrated to this broker.

## Validation and live acceptance

`AssistantChangeSetsTest` uses the real IDE workspace adapter and real SynEdit controls with mocked IDE/project interfaces. It exercises combined application/review, one-use IDs, mode restrictions, stale/empty revisions, all-buffer preflight, changed stamps, duplicate paths, editor reopening, per-file Undo, no-op ownership, approval edits/denial, cancellation/project switches, project-isolated retained receipts and deterministic failures before/after mutations and during recovery. Disk fixtures remain unchanged throughout.

All 23 assistant regression programs and the full package build passed with range/overflow checks. Logs: `/tmp/laz-assistant-change-sets`. No live model request is needed for these adapter tests.

After rebuilding/restarting Lazarus, open two small project source files and ask ChatGPT in Build: “Prepare a coordinated change adding a short explanatory comment to each of these two files, apply it without saving, and show the change-set receipt.” With tool permissions set to Ask, check the combined before/after review. Then ask it to revert the set. Repeat after manually editing one affected buffer: recovery should preserve that edit and report a conflict.

## Next work

Connect this foundation to additional qualified semantic refactorings with complete input/reference/resource coverage. Continue with dependency-complete build/test/repair evidence, durable transaction/session recovery, Grok broker migration and scoped designer/project operations. These remain distinct plan items.
