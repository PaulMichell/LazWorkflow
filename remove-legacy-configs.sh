#!/bin/sh
python3 - << 'PY'
import os, subprocess, json
from pathlib import Path
home = Path.home()
roots = [
    home / '.vscode/extensions',
    home / '.vscode-oss/extensions',
    home / '.vscode-insiders/extensions',
    home / '.cursor/extensions',
    home / '.local/share/vscode/extensions',
    home / '.local/share/code/extensions',
    home / '.local/share/chatgpt',
    Path('/opt'),
    Path('/usr/lib'),
    Path('/usr/share'),
]
cands = []
def add(path):
    path = Path(path)
    if path.is_file() and os.access(path, os.X_OK) and path not in cands:
        cands.append(path)
for root in roots:
    if not root.is_dir():
        continue
    try:
        children = list(root.glob('openai.chatgpt-*'))
    except OSError:
        continue
    for child in children:
        add(child / 'bin/linux-x86_64/codex')
        add(child / 'bin/codex')
for directory in os.environ.get('PATH', '').split(':'):
    if directory:
        add(Path(directory) / 'codex')
out = Path('/home/paul/Projects/LazWorkflow/Source/Tools/codex-runtime-report.txt')
lines = [f'candidates={len(cands)}']
for path in cands:
    lines.append(f'path={path}')
preferred = next((path for path in cands if '26.5930.51102' in str(path)), None)
target = preferred or (cands[0] if cands else None)
if target is None:
    lines.append('no-executable')
else:
    lines.append(f'selected={target}')
    def run(args, timeout=40):
        try:
            return subprocess.run([str(target), *args], capture_output=True, text=True, timeout=timeout)
        except Exception as error:
            lines.append(f'run-failed {args} {error}')
            return None
    proc = run(['--version'], 20)
    if proc is not None:
        lines.append(f'version-exit={proc.returncode}')
        lines.append('version-stdout=' + json.dumps(proc.stdout))
        lines.append('version-stderr=' + json.dumps(proc.stderr[:800]))
    proc = run(['app-server', '--help'], 20)
    if proc is not None:
        text = (proc.stdout + '\n' + proc.stderr)
        interesting = [line for line in text.splitlines() if any(token in line.lower() for token in ('schema', 'login', 'listen', 'experimental'))]
        lines.append('app-server-help=' + json.dumps(interesting[:40]))
    schema = Path('/home/paul/Projects/LazWorkflow/Source/Tools/codex-schema-report')
    schema.mkdir(parents=True, exist_ok=True)
    proc = run(['app-server', 'generate-json-schema', '--experimental', '--out', str(schema)], 40)
    if proc is not None:
        lines.append(f'schema-exit={proc.returncode}')
        lines.append('schema-stdout=' + json.dumps(proc.stdout[:400]))
        lines.append('schema-stderr=' + json.dumps(proc.stderr[:800]))
        if proc.returncode == 0:
            for file in sorted(schema.rglob('*.json')):
                name = str(file.relative_to(schema))
                if not any(token in name for token in ('ogin', 'Account', 'account', 'Initialize', 'ThreadStart', 'TurnStart', 'TurnSteer')):
                    continue
                try:
                    data = json.loads(file.read_text())
                except Exception as error:
                    lines.append(f'schema {name} parse-error={error}')
                    continue
                props = sorted((data.get('properties') or {}).keys())
                required = data.get('required') or []
                lines.append(f'schema {name} properties={props} required={required}')
out.write_text('\n'.join(lines) + '\n')
print('\n'.join(lines))
PY
exit 0
