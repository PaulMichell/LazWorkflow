#!/usr/bin/env python3
"""Build/test the assistant against an already-built Lazarus checkout (Linux).

All generated units, executables and logs go to an isolated output directory.
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
    parser.add_argument('--compile-only', action='store_true')
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
              ('LazAssistantTools', 'LazWorkflowCommon', 'LazStyledText')]
    flags += [f'-Fu{path}' for path in unit_dirs]
    flags += [f'-Fl{path.resolve()}' for path in args.library_dir]
    tests = ['AssistantCommandsTest', 'AssistantEventsTest', 'AssistantLfmTest',
             'AssistantProjectPathsTest', 'AssistantSamplerTest', 'AssistantSearchUtilTest',
             'AssistantTraceTest', 'AssistantConnectionsTest', 'AssistantFileCreationTest', 'AssistantCodexHandshakeTest',
             'AssistantCodexTransportTest', 'AssistantCodexClientTest', 'AssistantBuildJobTest']
    if args.gui:
        tests += ['AssistantSubagentsTest', 'AssistantHarnessTest',
                  'AssistantEditorEditsTest', 'AssistantWorkspaceTest', 'AssistantSettingsTest', 'AssistantProviderTest', 'MarkdownLayoutTest', 'AssistantTraceViewTest']
    failures = []

    def run(label, command):
        try:
            result = subprocess.run(command, cwd=repo, text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    timeout=90)
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

    for name in tests:
        if run(name + '-build', flags + [str(repo / 'Source' / 'Tests' / (name + '.lpr'))]):
            if not args.compile_only:
                run(name, [str(output / name)])
    run('assistant-package-build', flags + [str(repo / 'Packages' / 'LazAssistantTools.pas')])
    print(f'Logs: {output}', flush=True)
    return bool(failures)


if __name__ == '__main__':
    raise SystemExit(main())
