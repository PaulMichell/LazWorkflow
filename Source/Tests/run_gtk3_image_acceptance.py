#!/usr/bin/env python3
"""Compile and run the GTK3 image acceptance program. No model calls."""

import os
import subprocess
import sys
import tempfile
from pathlib import Path


def linker_flags():
    flags = []
    for package in ('gtk+-3.0', 'gdk-pixbuf-2.0'):
        probe = subprocess.run(['pkg-config', '--libs', package], text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if probe.returncode != 0:
            continue
        for part in probe.stdout.split():
            if part.startswith('-L'):
                flags.append('-Fl' + part[2:])
            elif part.startswith('-l'):
                flags.append('-k-l' + part[2:])
    return flags


def main():
    repo = Path(__file__).resolve().parents[2]
    lazarus = Path(os.environ.get('LAZARUS_ROOT', '/home/paul/Projects/FreePascal/Lazarus'))
    if not lazarus.is_dir():
        print(f'FAIL lazarus root not found: {lazarus}', flush=True)
        return 1
    if not os.environ.get('DISPLAY') and not os.environ.get('WAYLAND_DISPLAY'):
        print('FAIL no display for GTK3 acceptance', flush=True)
        return 1
    excluded = {'qt5', 'qt6', 'gtk2', 'nogui', 'win32', 'cocoa'}
    unit_dirs = sorted({p.parent for p in lazarus.rglob('*.ppu')
                        if not excluded.intersection(p.parts)})
    if not any('gtk3' in path.parts for path in unit_dirs):
        print('FAIL no GTK3 compiled Lazarus units', flush=True)
        return 1
    output = Path(tempfile.mkdtemp(prefix='gtk3-image-acceptance-'))
    flags = ['fpc', '-v0', '-gl', '-Cr', '-Co', '-Mobjfpc', '-dLCLgtk3', f'-FU{output}', f'-FE{output}']
    flags += [f'-Fu{repo / "Source" / name}' for name in
              ('LazAssistantTools', 'LazWorkflowCommon', 'LazStyledText', 'LazRepositoryTools')]
    flags += [f'-Fu{path}' for path in unit_dirs]
    flags += linker_flags()
    target = repo / 'Source' / 'Tests' / 'AssistantImageAcceptance.lpr'
    build = subprocess.run(flags + [str(target)], cwd=repo, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (output / 'build.log').write_text(build.stdout)
    if build.returncode:
        print(build.stdout)
        print(f'FAIL build, see {output / "build.log"}', flush=True)
        return 1
    run = subprocess.run([str(output / 'AssistantImageAcceptance')], cwd=repo, text=True)
    print(f'Logs: {output}', flush=True)
    return run.returncode


if __name__ == '__main__':
    raise SystemExit(main())
