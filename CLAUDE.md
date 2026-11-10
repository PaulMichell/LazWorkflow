# LazWorkflow

Lazarus IDE packages that add Git tooling (`LazRepositoryTools`) and an agentic project assistant
(`LazAssistantTools`, `LazAssistantMonitor`) to the IDE, on shared `LazWorkflowCommon` and `LazStyledText`.
Sources are under `Source/`, packages under `Packages/`, tests under `Tests/`.

## House style

All Pascal, Lazarus form, and design work follows `Documents/free-pascal-engineer.md`. Read it before writing or
reviewing code; it overrides generic Pascal or Delphi advice. In particular:

- PascalCase reserved words, two-space indent, 150-character lines, the unit layout and header comment it shows.
- The `F` prefix is only for the private field behind a `Property`. Existing units still use `F` more widely; do not
  rename existing fields as part of unrelated work.
- Static UI lives in the `.lfm`; keep `.pas` streamed fields and the `.lfm` object tree in step.
- Units stay under 1000 lines unless the header carries a dated size note.

## Building and testing

The compiler is FPC 3.3.1 with the Lazarus checkout at `/home/paul/Projects/FreePascal/Lazarus`.

```sh
instantfpc Tests/RunAssistantTests.pas --lazarus-root /home/paul/Projects/FreePascal/Lazarus \
  --only AssistantClaudeClientTest --output-dir Temporary/<run name>
```

`--only` may repeat. `--gui` adds the GUI tests (a display is required). Every run also builds the packages, so a
passing run means the package compiles. Without `--output-dir` the runner makes `Temporary/Tests-<pid>-<n>`.

Files made only for testing and not part of the project (test output directories, logs, generated inputs, screenshots,
scratch scripts) go in `Temporary/` at the project root. Create it when needed. Never use `/tmp` or the system
temporary directory, and never put them under `Source/` or `Tests/`. `Temporary/` is ignored by Git, and everything in
it must be safe to delete between sessions, so keep nothing there that is needed later. Test programs still make their
own scratch fixtures in the system temporary directory: a fixture inside this repository would find its `.git` and
`.assistant` when it searches upwards for a root. Screenshots that a test saves go to `LAZ_TEST_OUTPUT_DIR`, which the
runner sets to its output directory.

`--define NAME` passes `-dNAME` to every fpc build and to the monitor package build. `--heaptrc` and `--valgrind`
build and run only the named test programs, so each needs at least one `--only`. They cannot be combined, and
neither may be used with `--independent`, `--package-check` or `--gui`. Valgrind multiplies the run timeout by 20,
capped at 3600 seconds, and runs far slower than heaptrc. A valgrind build omits `-gl` and is then
stripped of debug sections, because Valgrind 3.24 aborts in its DWARF reader on these binaries.

Known failures that predate the Claude connector work: `AssistantSettingsTest` stops at the Codex check "missing
saved executable recovered without changing connection identity", and also fails "a new profile does not inherit
image output" once that first check is passed. `AssistantUsageTest` is not registered in the runner. Among the
GUI tests, `AssistantWorkspaceTest` and `AssistantWorkTargetTest` do not build (they call
`ExecuteAssistantToolForMode` without its `ToolId` argument), and `AssistantEditorEditsTest` fails "Plan advertises
Markdown edits and saves".

A change to a package needs the IDE rebuilt (Tools → Build Lazarus) before it can be seen in the running IDE.

## Git

Commit subjects take an area prefix and an imperative summary (`Claude: resume the Claude Code session …`); the
body explains the cause, the effect, and why the fix is right. Commit only the files you changed. Untracked files
under `Source/KotlinMonitorApp/` belong to other work: leave them alone.

## Current work: the Claude connector

Branch `claude-connector`. The plan, with progress, is `Documents/Plan-ClaudeConnector.md`; the review it came from,
with the design detail and the evidence, is `Documents/ClaudeConnectorReview.md`. Fixtures captured from the real
Claude Code program are in `Tests/Fixtures/Claude/` (see its README).

Constraints that hold throughout:

- Claude turns run on the user's Claude subscription, never per-use API billing. Never read or copy Claude sign-in
  files, and never add `--bare`, `--max-budget-usd`, or `--betas`.
- A Claude turn that has run a tool must not be replayed automatically.
