# Development-loop validation and completion

Implemented: 12 September 2026.

## Dependency evidence

The IDE workspace now expands its saved project members and open buffers through the existing CodeTools configuration. Discovery follows both uses sections transitively, implicit `System`, and active includes throughout each source, including nested includes inside implementation bodies. It also captures existing paired `.lfm` and `.lrs` files. The shared CodeTools guard prevents reentrant symbol lookup and dependency discovery through IDE callbacks.

`lazarus_build_status.dependencies` reports:

| Field | Meaning |
| --- | --- |
| `sourceClosureComplete` | Discovery completed without missing sources/includes, parse/cache mismatches or scan limits, both before the build and at observation. |
| `gaps` | Up to 20 bounded explanations of incomplete coverage. |
| `initialScanIncomplete` | The original scan was incomplete; a later successful scan cannot upgrade that build to complete coverage. Rebuild. |
| `defineStep` | CodeTools configuration revision used for discovery. |
| `compilerEnvironmentComplete` | False: the entire compiler/linker/runtime environment is not captured. |
| `scope` | Explicit description of the source coverage and exclusions. |

Captured bytes are checked before and after the worker and at completed-status observation. Rediscovery detects changed resolution or a newly created paired dependency resource. Changed CodeTools defines, project/build settings, editors, captured files or dependency sets make earlier evidence stale. IDE cancellation during discovery stops launch; cancellation/replacement during status discards the result.

Missing dependency sources or an incomplete scan do not prevent obtaining compiler diagnostics. They do prevent automatic completion. Missing initial project members, unreadable initial inputs and unsaved project/editor/designer changes still prevent launch. The scan never saves or forcibly reverts editor/CodeTools buffers; a cache/disk mismatch produces an explicit gap.

Bounds remain 512 captured files, 1 MiB per file and 32 MiB total. The source queue is limited to 512 entries, with a two-second deadline checked between source explorations. A single CodeTools operation is synchronous and cannot be preempted by that deadline. Incomplete scans are reported, not silently treated as a complete manifest.

This is CodeTools **source** coverage. It does not freeze compiler binaries, FPC configuration/response files, package metadata/compiled units, arbitrary resource/object/linker directives, runtime libraries or the process environment. CodeTools and the external compiler can also differ in configuration. `verified` remains false; full compiler-derived dependency/artifact qualification remains on the plan.

## Explicit automatic-completion criteria

Add one of these lines to the selected plan section before starting **Work on this**:

```markdown
## Implement a parser correction
Status: not started
Validation: tests

Preserve the documented parser behavior and run the configured regression suite.
```

- `Validation: build` requires a completed, current successful build with complete CodeTools source coverage.
- `Validation: tests` additionally requires a completed current test job linked to that build, successful process exit, a valid passing FPCUnit XML report, and at least the configured number of executed tests.
- No validation line, `Validation: manual`, unknown or duplicate validation lines, and unchecked `[ ]` acceptance items leave the package in progress for manual **Done**. Validation examples inside fenced code blocks are ignored.

These lines opt into those specific machine checks. They do not prove prose requirements, test relevance or a fully frozen toolchain. Choose `tests` for behavioral work and keep manual acceptance checks for matters such as appearance or usability. A zero-exit command in exit-only report mode cannot satisfy `Validation: tests`.

The assistant snapshots the selected project, resolved plan path, complete saved plan text and selected section before the turn. Automatic completion requires those identities and saved plan bytes to remain unchanged, with no unsaved plan buffer. Editing/reordering the plan during work requires review and manual Done. The model's work prompt tells it to leave plan status and validation changes to the IDE/user.

Completion evidence is captured before releasing the ChatGPT run cancels the workspace jobs. It belongs to the selected turn and is cleared afterward. Failed/interrupted turns do not auto-complete. Manual Done remains available as the user's decision.

The previous Grok clean-compile shortcut has been removed: it could accept an unrelated or outdated compile as completion evidence. Grok currently requires manual Done; its automatic plan walk stops after the package for that review. Shared broker migration is needed before Grok can use the same completion checks. ChatGPT still operates individual turns; automatic multi-package execution is not introduced here.

## Tests and package validation

The regression suite includes real FPCUnit XML generation, real CodeTools source/include discovery, workspace tests for transitive edits/new resources/cancellation, and pure acceptance tests for missing, failed, stale, unrelated and insufficient evidence. Settings persistence and the report controls were tested and visually checked. No live model request is needed for these tests.

The SynEdit package dependency is now declared directly in `LazAssistantTools.lpk`. A direct compiler invocation with broad unit paths had masked its absence. The regression script now supports a real package check:

```sh
python3 Source/Tests/run_assistant_tests.py \
  --lazarus-root /path/to/built/Lazarus \
  --output-dir /tmp/laz-assistant-tests \
  --gui --package-check
```

This uses an isolated Lazarus configuration and the package's declared dependency paths. Repository dependency packages must already be built. The optional package check writes the package's ordinary `Lib` output, while regression executables/logs stay in the chosen output directory. Use `--library-dir` when local linker aliases are needed.

## Live acceptance

Rebuild the package and restart Lazarus. Configure **Settings → Project tests → FPCUnit XML on stdout**, choose a meaningful minimum, and configure your test runner to emit its complete XML report on stdout. Test Work on this with a small saved project and a section containing `Validation: tests`. Check build coverage, report counts and task status.

Repeat with a failing test, an exit-only command, an unchecked acceptance item, and a plan edited while work runs. These cases should remain in progress. Separately edit a transitive unit/include or create a paired dependency resource after compilation and check that the old build status becomes stale.

Final validation: all 27 regression programs, direct package compilation and a clean real `lazbuild` package rebuild passed (`/tmp/laz-assistant-acceptance-final`). The updated Project tests page was visually checked. No live model request was sent.
