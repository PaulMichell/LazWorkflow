#!/usr/bin/env python3
"""Offline Codex version/schema qualification; never signs in or starts a turn."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--runtime', type=Path, required=True)
parser.add_argument('--output-dir', type=Path, required=True)
args = parser.parse_args()
runtime = args.runtime.resolve(strict=True)
output = args.output_dir.resolve()
output.mkdir(parents=True, exist_ok=True)


def run(*arguments):
    result = subprocess.run([str(runtime), *arguments], capture_output=True,
                            text=True, timeout=60, cwd=output)
    if result.returncode:
        raise SystemExit(f'Runtime qualification command failed with exit {result.returncode}')
    return result.stdout.strip()


def release_version(text):
    if not re.fullmatch(r'codex-cli [0-9]+(?:\.[0-9]+){2}', text):
        return False
    for part in text.split(' ', 1)[1].split('.'):
        if len(part) > 1 and part.startswith('0'):
            return False
    return True


def property_names(node, found):
    if isinstance(node, dict):
        props = node.get('properties')
        if isinstance(props, dict):
            found.update(props)
        for value in node.values():
            property_names(value, found)
    elif isinstance(node, list):
        for item in node:
            property_names(item, found)


version = run('--version')
if not release_version(version):
    raise SystemExit('Unsupported runtime version; expected a codex-cli release such as codex-cli 0.160.0')
schema_dir = output / 'schema'
run('app-server', 'generate-json-schema', '--experimental', '--out', str(schema_dir))
required = {
    'v2/LoginAccountParams.json': ['type'],
    'v2/LoginAccountResponse.json': ['type', 'loginId', 'authUrl'],
    'v2/GetAccountResponse.json': ['account', 'requiresOpenaiAuth'],
    'v2/ThreadStartParams.json': ['dynamicTools', 'modelProvider', 'permissions', 'approvalPolicy'],
    'v2/ThreadStartResponse.json': ['modelProvider', 'sandbox', 'approvalPolicy', 'thread'],
    'v2/TurnStartParams.json': ['threadId', 'input', 'permissions', 'summary'],
    'v2/TurnInterruptParams.json': ['threadId', 'turnId'],
    'v2/TurnSteerParams.json': ['threadId', 'expectedTurnId', 'input'],
    'DynamicToolCallParams.json': ['threadId', 'turnId', 'callId', 'tool', 'arguments'],
    'DynamicToolCallResponse.json': ['contentItems', 'success'],
    'v2/AgentMessageDeltaNotification.json': ['threadId', 'turnId', 'itemId', 'delta'],
}
hashes = {}
for name, fields in required.items():
    data = (schema_dir / name).read_bytes()
    schema = json.loads(data)
    found = set()
    property_names(schema, found)
    missing = [field for field in fields if field not in found]
    if missing:
        raise SystemExit(f'Required protocol field missing from {name}: {missing[0]}')
    hashes[name] = hashlib.sha256(data).hexdigest()
manifest = {
    'version': version,
    'runtime_sha256': hashlib.sha256(runtime.read_bytes()).hexdigest(),
    'experimental_schema_sha256': hashes,
    'scope': 'Offline schema shape only; not account entitlement, model inference or tool isolation',
}
(output / 'qualification.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Qualified {version}: {output / "qualification.json"}')
