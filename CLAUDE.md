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
  --only AssistantClaudeClientTest --output-dir <a temporary directory>
```

`--only` may repeat. `--gui` adds the GUI tests (a display is required). Every run also builds the packages, so a
passing run means the package compiles. Write output to a temporary directory, never under `Source/`.

Known failures that predate the Claude connector work: `AssistantSettingsTest` stops at the Codex check "missing
saved executable recovered without changing connection identity", and also fails "a new profile does not inherit
image output" once that first check is passed. `AssistantUsageTest` is not registered in the runner.

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
