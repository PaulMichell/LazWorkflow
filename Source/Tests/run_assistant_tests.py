#!/usr/bin/env python3
"""Build/test the assistant against an already-built Lazarus checkout (Linux).

Regression units, executables and logs go to an isolated output directory.
The optional real package check writes the package's normal Lib output too.
The GUI group needs a working display. No live model calls are made.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lazarus-root', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--library-dir', type=Path, action='append', default=[])
    parser.add_argument('--gui', action='store_true')
    parser.add_argument('--package-check', action='store_true',
                        help='Also validate .lpk dependencies with lazbuild (rebuilds repository dependencies).')
    parser.add_argument('--compile-only', action='store_true')
    parser.add_argument('--independent', action='store_true',
                        help='Prove Repository and Assistant install alone: restricted unit paths, section round-trip, nil Suggest.')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    output = (args.output_dir or Path(tempfile.mkdtemp(prefix='laz-assistant-tests-'))).resolve()
    output.mkdir(parents=True, exist_ok=True)
    excluded = {'qt5', 'qt6', 'gtk3', 'nogui', 'win32', 'cocoa'}
    unit_dirs = sorted({p.parent for p in args.lazarus_root.rglob('*.ppu')
                        if not excluded.intersection(p.parts)})
    if not unit_dirs:
        parser.error('No compiled Lazarus units found; build Lazarus/GTK2 first.')
    flags = ['fpc', '-v0', '-gl', '-Cr', '-Co', f'-FU{output}', f'-FE{output}']
    flags += [f'-Fu{repo / "Source" / name}' for name in
              ('LazAssistantTools', 'LazWorkflowCommon', 'LazStyledText', 'LazRepositoryTools')]
    flags += [f'-Fu{path}' for path in unit_dirs]
    flags += [f'-Fl{path.resolve()}' for path in args.library_dir]
    tests = ['WorkflowEventsLifetimeTest', 'GitStatusParseTest', 'RepositorySafetyTest', 'WasteBinArgsTest', 'AssistantArchiveRollbackTest', 'AssistantAcceptanceTest', 'AssistantCommandsTest', 'AssistantEventsTest', 'AssistantLfmTest',
             'AssistantImagesTest', 'AssistantProjectPathsTest', 'AssistantSamplerTest', 'AssistantSearchUtilTest',
             'AssistantTraceTest', 'AssistantConnectionsTest', 'AssistantFileCreationTest', 'AssistantCodexHandshakeTest',
             'AssistantTestRunnerTest', 'AssistantCodexTransportTest', 'AssistantCodexClientTest', 'AssistantBuildJobTest', 'AssistantGitTest',
             'IndependentInstallTest', 'RepositoryOnlyInstall', 'AssistantOnlyInstall']
    if args.gui:
        tests += ['PluginFormLifetimeTest', 'SpellMemoInputTest', 'AssistantSubagentsTest', 'AssistantHarnessTest',
                  'AssistantEditorEditsTest', 'AssistantBuildWorkspaceTest', 'AssistantBuildDependenciesTest', 'AssistantChangeSetsTest', 'AssistantWorkspaceTest', 'AssistantCodeToolsTest', 'AssistantSettingsTest', 'AssistantProviderTest', 'AssistantReconnectTest', 'MarkdownLayoutTest', 'AssistantTraceViewTest', 'AssistantConversationSurfaceTest', 'AssistantMarkdownAsyncTest', 'AssistantConversationStressTest']
    failures = []

    def run(label, command, timeout=90):
        try:
            result = subprocess.run(command, cwd=repo, text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    timeout=timeout)
            (output / f'{label}.log').write_text(result.stdout)
            if result.returncode:
                print(f'FAIL {label}: see {output / (label + ".log")}', flush=True)
                failures.append(label)
                return False
        except subprocess.TimeoutExpired as error:
            body = error.stdout or b''
            if isinstance(body, bytes):
                body = body.decode(errors='replace')
            (output / f'{label}.log').write_text(body + '\nTimed out.\n')
            print(f'FAIL {label}: timed out', flush=True)
            failures.append(label)
            return False
        print(f'PASS {label}', flush=True)
        return True

    def restricted(label, sources, target, execute=False, timeout=180):
        out = output / label
        out.mkdir(parents=True, exist_ok=True)
        command = ['fpc', '-v0', '-gl', '-Cr', '-Co', '-MObjFPC', f'-FU{out}', f'-FE{out}']
        command += [f'-Fu{repo / "Source" / name}' for name in sources]
        command += [f'-Fu{path}' for path in unit_dirs]
        command.append(str(target))
        built = run(label + '-build', command, timeout)
        if built and execute and not args.compile_only:
            built = run(label, [str(out / target.stem)], timeout)
        return built

    if args.independent:
        # Each compile gets its own output directory so a foreign package unit cannot be satisfied by a leftover ppu.
        checks = [
            restricted('common-package', ['LazWorkflowCommon'], repo / 'Packages' / 'LazWorkflowCommon.pas'),
            restricted('styled-package', ['LazStyledText'], repo / 'Packages' / 'LazStyledText.pas'),
            restricted('repository-package', ['LazRepositoryTools', 'LazWorkflowCommon'],
                       repo / 'Packages' / 'LazRepositoryTools.pas', False, 300),
            restricted('assistant-package', ['LazAssistantTools', 'LazWorkflowCommon', 'LazStyledText'],
                       repo / 'Packages' / 'LazAssistantTools.pas', False, 300),
            restricted('RepositoryOnlyInstall', ['LazRepositoryTools', 'LazWorkflowCommon'],
                       repo / 'Source' / 'Tests' / 'RepositoryOnlyInstall.lpr', True, 240),
            restricted('AssistantOnlyInstall', ['LazAssistantTools', 'LazWorkflowCommon', 'LazStyledText'],
                       repo / 'Source' / 'Tests' / 'AssistantOnlyInstall.lpr', True, 240),
            restricted('IndependentInstallTest',
                       ['LazRepositoryTools', 'LazAssistantTools', 'LazWorkflowCommon', 'LazStyledText'],
                       repo / 'Source' / 'Tests' / 'IndependentInstallTest.lpr', True, 240),
        ]
        print(f'Logs: {output}', flush=True)
        return not all(checks)

    for name in tests:
        if run(name + '-build', flags + [str(repo / 'Source' / 'Tests' / (name + '.lpr'))]):
            if not args.compile_only:
                run(name, [str(output / name)])
    run('assistant-package-build', flags + [str(repo / 'Packages' / 'LazAssistantTools.pas')])
    run('repository-package-build', flags + [str(repo / 'Packages' / 'LazRepositoryTools.pas')])
    if args.package_check:
        lazbuild = args.lazarus_root / 'lazbuild'
        package_flags = [str(lazbuild), f'--pcp={output / "package-config"}',
                         f'--lazarusdir={args.lazarus_root}', '--ws=gtk2']
        linked = True
        for name in ('LazWorkflowCommon', 'LazStyledText', 'LazAssistantTools'):
            linked = run(name + '-package-link', package_flags +
                         ['--add-package-link', str(repo / 'Packages' / (name + '.lpk'))]) and linked
        if linked:
            for name in ('LazWorkflowCommon', 'LazStyledText', 'LazAssistantTools'):
                if not run(name + '-lazbuild-package', package_flags +
                           ['--skip-dependencies', '--build-all', str(repo / 'Packages' / (name + '.lpk'))]):
                    break
    print(f'Logs: {output}', flush=True)
    return bool(failures)


if __name__ == '__main__':
    raise SystemExit(main())
