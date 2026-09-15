#!/usr/bin/python3
"""Offline, opt-in live IDE package acceptance. Only edits PackageTargetCheck.

Requires the disposable fixture package and configured test runner described in
Documents/LazAssistantTools-Package-Targets.md. No network or account access.
"""
import json
import sys
import time
sys.dont_write_bytecode = True
from codex_event_fixture import send, event, message, finish


def workflow():
    info = yield 'lazarus_project_info', {}
    if 'Target: Package — PackageTargetCheck.lpk' not in info:
        raise ValueError('Select the disposable PackageTargetCheck package first.')
    path = 'Source/PackageUnit.pas'
    original = yield 'lazarus_open_buffer', {'path': path}
    text = original['text']
    if 'Result := 42;' not in text:
        raise ValueError('Expected the untouched disposable unit fixture.')
    yield 'lazarus_replace_buffer', {'path': path, 'revision': original['revision'],
                                    'text': text.replace('Result := 42;', 'Result := 43;')}
    current = yield 'lazarus_read_buffer', {'path': path}
    yield 'lazarus_save_buffer', {'path': path, 'revision': current['revision']}
    build = yield 'lazarus_start_build', {}
    for _ in range(240):
        time.sleep(.25)
        status = yield 'lazarus_build_status', {'job_id': build['job_id']}
        if status['done']:
            if status['outcome'] != 'compile_passed':
                raise ValueError('Package build failed: ' + json.dumps(status))
            break
    else:
        raise ValueError('Build did not finish within the fixture poll limit.')
    tests = yield 'lazarus_start_tests', {'build_job_id': build['job_id']}
    for _ in range(120):
        time.sleep(.25)
        status = yield 'lazarus_test_status', {'job_id': tests['job_id']}
        if status['done']:
            if status['outcome'] != 'test_command_passed':
                raise ValueError('Package tests failed: ' + json.dumps(status))
            break
    else:
        raise ValueError('Tests did not finish within the fixture poll limit.')
    message('PACKAGE ACCEPTANCE PASSED: inspected, edited and saved the selected '
            'package unit; compiled its .lpk; ran its configured behavioural test.', complete=True)
    finish()


def main():
    if '--version' in sys.argv:
        print('codex-cli 0.153.4', flush=True)
        return
    run = None
    count = 0

    def advance(value=None):
        nonlocal count
        try:
            tool, args = run.send(value)
            count += 1
            send({'id': f'package-{count}', 'method': 'item/tool/call',
                  'params': {'threadId': 'fixture-thread', 'turnId': 'fixture-turn',
                             'callId': f'call-{count}', 'tool': tool, 'arguments': args}})
        except StopIteration:
            pass
        except Exception as exc:
            message('PACKAGE ACCEPTANCE FAILED: ' + str(exc), complete=True)
            finish('failed', error={'message': str(exc)})

    for line in sys.stdin:
        request = json.loads(line)
        ident, method = request.get('id'), request.get('method', '')
        if ident is None:
            continue
        result = {}
        if method == 'initialize':
            result = {'userAgent': 'codex/0.153.4'}
        elif method == 'account/read':
            result = {'account': {'type': 'chatgpt'}, 'requiresOpenaiAuth': True}
        elif method == 'mcpServerStatus/list':
            result = {'data': [], 'nextCursor': None}
        elif method == 'model/list':
            result = {'data': [{'id': 'offline-package-fixture'}], 'nextCursor': None}
        elif method == 'thread/start':
            result = {'modelProvider': 'openai', 'approvalPolicy': 'on-request',
                      'sandbox': {'type': 'readOnly'}, 'thread': {'id': 'fixture-thread'}}
        elif method == 'turn/start':
            send({'id': ident, 'result': {'turn': {'id': 'fixture-turn', 'status': 'inProgress'}}})
            run = workflow()
            advance()
            continue
        elif not method and str(ident).startswith('package-'):
            result = request['result']
            text = '\n'.join(item.get('text', '') for item in result.get('contentItems', []))
            if not result.get('success'):
                message('PACKAGE ACCEPTANCE FAILED: ' + text, complete=True)
                finish('failed', error={'message': text})
                continue
            try:
                value = json.loads(text)
            except ValueError:
                value = text
            advance(value)
            continue
        elif method == 'turn/interrupt':
            send({'id': ident, 'result': {}})
            finish('interrupted')
            continue
        send({'id': ident, 'result': result})


if __name__ == '__main__':
    main()
