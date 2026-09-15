# Working on Lazarus packages

Implemented on 15 September 2026. The Assistant can work on a selected package while an unrelated application remains the open Lazarus project.

## Using it

1. Open the Assistant and use **Working on** above the Ask/Plan/Build controls.
2. Select a loaded package, or choose **Open package…** and select its saved `.lpk` file.
3. Use Ask, Plan or Build normally. The window title identifies the selected target. Changing editor tabs or opening/closing another project does not redirect a pinned package.
4. Configure the package's test executable and arguments under **Settings → Target tests**. These settings are separate for every project/package manifest.
5. Choose **Current Lazarus project** to return to project work. Target switching is refused during a request or review; stop/finish it first.

Selection is pinned for the IDE session, not restored automatically across IDE restarts. The Assistant does not install packages or rebuild the IDE. Creating/registering package members and editing `.lpk` metadata remain operations in the Lazarus package editor; newly created source files are not silently registered with either the package or the unrelated project.

## Context, folders and permissions

`AssistantWorkTarget` provides the target kind, manifest, runtime identity, member list, dependencies, working root, build configuration and storage identity. It resolves a selected package through the IDE package registry on use rather than retaining a potentially dangling package object. A missing selected package fails closed; it does not fall back to the open project.

For packages the working root is the nearest repository, or the common directory of the manifest and members when no repository is present. This supports `Packages/Library.lpk` with units in `Source/Library/`. Filesystem/home roots are not inferred as a common-directory workspace. Source inspection is bounded by the working root; dependencies outside it are listed as context and can contribute to build evidence, but do not become writable roots.

Package writes are limited to member directories and the working root's `Documents` directory, including creation of the first Documents directory. Physical-path checks prevent symlinks from extending that scope. `.lpk` and `.lpi` metadata are excluded from direct Assistant writes. Shared member directories are a directory-level scope, not an exact ownership guarantee for every sibling file. Ask remains read-only; Plan retains its Markdown-only restriction.

The active editor is attached automatically only when it is a package member. An unrelated editor's source is not inserted into package prompts. Both the Grok tools and the managed Codex broker resolve paths against the selected target. Existing tool names such as `get_project_info` and `lazarus_project_info` are retained for compatibility, but describe the selected target.

Git still operates on the repository. Package staging is restricted to the package's permitted paths and its own manifest. A commit is refused if the index includes paths outside that scope; both sides of a staged rename are checked. This does not replace reviewing the staged diff.

## History and plan isolation

Existing project stores and their legacy session lookup remain compatible. A package uses:

```text
<working root>/.assistant/targets/package-<manifest-relative hash>/
```

Each package has its own conversation, archives, shell preferences, active plan selection and session file. Markdown plans themselves may remain together in the repository's Documents directory. Package-only `targets` containers do not count as a legacy project store during project-root discovery.

Explicit target changes invalidate broker approvals/snapshots and cancel owned build/test jobs before rebinding the view. Returning to a target reloads its saved conversation and preferences.

## Builds and tests

The shared asynchronous build path passes the selected `.lpk` to `lazbuild`, without a project build-mode argument. Package builds use the current IDE profile and widget set. Compiler discovery checks PATH, the IDE executable directory, then Lazarus's configured installation directory.

Build evidence includes package members, paired resources, dependency manifests and the existing CodeTools source scan. Package/dependency configuration changes, observed source changes and target switches invalidate previous results. Relevant dirty buffers must be saved explicitly; unrelated dirty project buffers do not prevent package builds. Configured tests remain tied to a successful, current build and their reviewed executable/configuration.

The existing evidence limits still apply: CodeTools may report incomplete source closure, and the compiler/linker environment is not frozen. A successful compile is not a behavioural-test pass. Review Compile/Build and the legacy Grok compile tool also route to the selected package; the asynchronous broker path is the one exercised by the complete live workflow below.

## Validation

- All 33 programs in the GTK2 regression run passed, including the new package-target test and the existing project/build/settings/history/keyboard tests.
- `AssistantWorkTargetTest` passed on GTK2 and Qt5. It covers unrelated project/editor isolation, source roots outside the manifest directory, dependency write exclusion, symlinks, package-specific plans/history/test settings, build arguments and freshness, actual form selection and project lifecycle notifications.
- Final focused checks also cover staging outside package scope, creation of a first Documents directory and refusal to build with unsaved dependency settings.
- The actual Assistant GTK2 package and an isolated Qt5 Lazarus IDE build passed.
- In the live Qt5/XWayland IDE, `Unrelated.lpi` remained open while the Assistant selected `PackageTargetCheck.lpk`, read its context, opened its source buffer, changed `Answer` from 42 to 43, saved it, compiled the package, and ran a configured test that linked the compiled unit and asserted `Answer = 43`.
- The offline runtime reported **PACKAGE ACCEPTANCE PASSED**. SHA-256 checks confirmed the unrelated project's `.lpi` and `.lpr` files were unchanged. Returning to the current-project selector was also exercised. The isolated IDE exited normally with status 0 after the workflow.

[Live package workflow screenshot](Images/Package-Target-Acceptance/package-workflow.png)

This is real IDE/broker/editor/compiler/test-runner integration with an offline protocol fixture, not a live ChatGPT/Grok request. No account credentials were copied and no subscription/API call was made. Additional platforms and actual-provider confirmation are not claimed. Logs, the complete trace and file-hash comparisons are retained in ignored `Lib/PackageAcceptance/`.

## Reproducing the live check

1. Build an isolated IDE with LazAssistantTools; retain a separate IDE profile.
2. Run `python3 Source/Tests/create_package_target_fixture.py /tmp/package-target-check`. The destination must not already exist.
3. Open `App/Unrelated.lpi` in that workspace. In the Assistant choose `Packages/PackageTargetCheck.lpk` through **Working on → Open package…**.
4. Add an isolated ChatGPT-type connection whose Codex executable is `Source/Tests/codex_package_fixture.py`, model is `offline-package-fixture`, and tool permission allows the fixture's registered tools. This executable simulates the protocol and does not access any account.
5. In **Target tests**, enable the runner, select the local Python 3 executable, and supply the absolute path to `run_tests.py` as its single argument. Use exit-code reporting. FPC must be on PATH.
6. Select Build mode and submit a short prompt. The fixture refuses to edit unless the target context identifies `PackageTargetCheck.lpk` and the unit still contains its original `Result := 42;`.
7. Confirm the final success message and compare the unrelated project files. Use a freshly generated workspace for another full run; the successful run intentionally changes the disposable source.

The fixture generator/test runner is qualified on Linux. Keep these executables confined to test connections; they are not model providers.
