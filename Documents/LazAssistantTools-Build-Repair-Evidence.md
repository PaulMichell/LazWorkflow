# Build and repair evidence

Implemented: 11 September 2026.

This step gives the ChatGPT development loop correlated build jobs, live output, structured compiler diagnostics and broader saved-input checks. It retains the managed runtime's existing inspect/edit/tool loop; it does not start a second hidden agent loop.

## Workflow

1. Inspect the relevant source and agree the intended behavior or acceptance criteria.
2. Use the revision-checked edit/refactoring tools. Save authorized changes explicitly. A build never silently saves buffers or project settings.
3. In Build mode, call `lazarus_start_build`. Retain the returned `job_id`.
4. Poll `lazarus_build_status` with that ID until `done` is true. A different current job is rejected. Omitting the ID remains compatible with older callers, but the managed prompt instructs the model to correlate its jobs.
5. Inspect `outcome`, `stale`, `error`, truncation flags and diagnostic `items`. Read the affected source again before proposing a repair, apply/save that repair through the existing tools, and start a new build.
6. Report compilation and test evidence separately. A passing compile is not proof of correct behavior or a completed task.

The updated assistant prompt describes this sequence. The connection's existing tool approval policy and Build-only permission boundary remain in force.

## Job results

Each job gets an ID before the worker starts and records its executable, working directory and argument array. The worker continues to launch `lazbuild` without a shell, with the selected build mode and saved project filename. Cancellation and timeout terminate its owned process group on Linux. Starting/cancelling a broker run discards the workspace's current build handle; evidence is not durable across runs or IDE restart.

While running, output snapshots are published approximately every 100 ms. Standard error is merged into the same pipe as standard output. Status returns the available log and diagnostics while `done` is false; those are provisional. Polling does not wait for the compiler to finish.

| Field | Meaning |
| --- | --- |
| `job_id`, `command` | Build identity and the executable/arguments actually selected. |
| `done`, `outcome` | Running, cancelled, stale, failed, compile_failed or compile_passed. |
| `exitCode`, `error` | Compiler status and worker/launch/timeout errors. |
| `stale` | Observed source, workspace or build settings no longer match the build evidence. |
| `items` | Located FPC diagnostics: job ID, path, line, column, severity, message and raw line. Column zero means the compiler gave no column. Paths are compiler-reported, not automatically opened or rewritten. |
| `manifest` | SHA-1 fingerprints of the observed saved inputs. These identify bytes; they are not a security or immutable-build guarantee. |
| `diagnostics` | Bounded raw log excerpt, including messages the location parser does not recognize. |
| `verified`, `testsRun` | Both remain false for build jobs. The configured-test follow-up provides separate test jobs; full dependency qualification remains open. |

The parser accepts FPC location lines with fatal/error/warning/hint/note severity. Unrecognized lines remain in the raw log; they are not guessed into locations. Compiler exit status determines compile failure even when no located error can be parsed.

## Saved-input policy and stale evidence

The snapshot now includes the project file, project file entries even when their editors are closed, existing paired `.lfm`/`.lrs` resources and all named open buffers. It rejects missing/unreadable inputs, unsaved project settings, dirty source buffers, pending designer changes and editor text that differs from disk even when its Modified flag is false. It does not save any of them.

The worker checks captured disk bytes before launch and after completion. Completed status checks disk bytes again, so a later saved change to a closed source or form resource invalidates an earlier passing build. Status also checks the active project/build mode, project Modified state, all dirty editors/designer resources (including newly opened ones), and captured buffers' current text.

Snapshots are limited to 512 unique filenames, 1 MiB per input and 32 MiB total. Duplicated filenames do not consume another snapshot. Special files such as FIFOs are refused before opening on Linux. Exceeding a limit for the initial project/editor snapshot prevents launch. The dependency follow-up below records discovery limits as explicit coverage gaps, so compiler diagnostics remain available.

## Output limits

The worker retains the first 1 MiB of merged output and continues draining the pipe to avoid blocking the compiler. `outputTruncated` reports when further bytes were discarded. Status returns at most the last 48,000 bytes of that retained output, with `logExcerptTruncated` when shortened.

Structured diagnostic items are capped at 200 entries and 64 KiB of serialized entries. Manifest output is capped at 64 KiB. Oversized command details are omitted. `diagnosticsTruncated`, `manifestTruncated` and `commandTruncated` expose these limits. The complete captured input list is still used for validation even if the returned manifest is shortened. These bounds keep large compiler logs within the managed tool transport's frame limit.

## Validation and remaining work

All 24 assistant regression programs and the assistant package build passed with range/overflow checks (`/tmp/laz-assistant-refactor-loop`). A subsequent targeted workspace regression and package rebuild verify the final pending-designer correction.

`AssistantBuildJobTest` uses owned fixture processes to test live output, errors, timeouts, cancellation, stable IDs, observed input mismatches, post-build disk changes, bounded logs/diagnostics, transport-size bounds, duplicate inputs and special-file rejection. `AssistantBuildWorkspaceTest` exercises the real workspace adapter and broker with mock IDE objects, including closed project units/resources, stale/replacement jobs, repair/rebuild, newly dirty editors, pending designer changes, saved-buffer mismatches, build-mode changes, missing members and Plan restrictions. No live model request was sent, and the fixture compiler is not a full Lazarus project build.

After rebuilding/restarting Lazarus, test in a small project with an intentional compile error: “Build the saved project, inspect the diagnostics, repair the error with Lazarus tools, and build again. Do not claim tests passed unless you actually ran them.” With tool permissions set to Ask, inspect each proposed edit/save/build. Separately check that a saved edit after build completion makes the earlier job stale.

Next: discover and fingerprint the actual transitive source/include/package/configuration dependencies; qualify consistent build inputs; add a user-configured test runner and test-result evidence; connect acceptance criteria to completion checks; add diagnostic navigation and durable job/task recovery. Parameter/exported-symbol/multi-file semantic refactoring also remains open. No FPCUnit runner or automatic “task complete” gate is claimed by this step.

## Configured-test follow-up

The [configured project test runner](LazAssistantTools-Configured-Tests.md) is now implemented. It reuses this worker, with separate test outcomes, executable fingerprints and parent build IDs. Test discovery/report parsing, complete dependency/artifact qualification and completion gates remain open.

## Source coverage and completion follow-up (12 September 2026)

Build snapshots now expand through CodeTools transitive uses, implicit System, active nested includes and paired dependency resources. Completed status rechecks both captured bytes and current resolution. Missing sources, scan limits and cache mismatches produce explicit gaps and prevent automatic completion. Compiler/linker/runtime coverage remains incomplete.

FPCUnit report parsing and explicit `Validation: build` / `Validation: tests` completion checks are implemented. See [current scope, criteria, tests and live acceptance](LazAssistantTools-Validation-and-Completion.md). These changes supersede the earlier remaining-work descriptions above.
