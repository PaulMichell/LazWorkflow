#!/usr/bin/python3
"""Offline App Server fixture for live IDE acceptance; never contacts a provider.

Select this executable only in an isolated IDE connection/profile. Prompts may
contain CASE: thinking, failure, disconnect, cancel or final. Events are paced
so the production IDE timer, tool broker and conversation renderer all run.
"""
import json
import sys
import time


def send(value):
    print(json.dumps(value), flush=True)


def event(method, **params):
    send({'method': method, 'params': {'threadId': 'fixture-thread',
                                     'turnId': 'fixture-turn', **params}})


def message(text, item='answer', complete=False):
    if complete:
        event('item/completed', item={'id': item, 'type': 'agentMessage', 'text': text})
    else:
        event('item/agentMessage/delta', itemId=item, delta=text)


def finish(status='completed', **values):
    event('turn/completed', turn={'id': 'fixture-turn', 'status': status, **values})


def main():
    if '--version' in sys.argv:
        print('codex-cli 0.153.4', flush=True)
        time.sleep(.1)
        return
    case = ''
    for line in sys.stdin:
        request = json.loads(line)
        method = request.get('method', '')
        request_id = request.get('id')
        if request_id is None:
            continue

        def reply(result):
            send({'id': request_id, 'result': result})

        if method == 'initialize':
            reply({'userAgent': 'codex/0.153.4'})
        elif method == 'account/read':
            reply({'account': {'type': 'chatgpt'}, 'requiresOpenaiAuth': True})
        elif method == 'mcpServerStatus/list':
            reply({'data': [], 'nextCursor': None})
        elif method == 'model/list':
            reply({'data': [{'id': 'offline-event-fixture'}], 'nextCursor': None})
        elif method == 'thread/start':
            reply({'modelProvider': 'openai', 'approvalPolicy': 'on-request',
                   'sandbox': {'type': 'readOnly'}, 'thread': {'id': 'fixture-thread'}})
        elif method == 'turn/start':
            prompt = request['params']['input'][0]['text'].lower()
            case = next((c for c in ['thinking', 'failure', 'disconnect', 'cancel', 'final']
                         if 'case: ' + c in prompt), 'thinking')
            reply({'turn': {'id': 'fixture-turn', 'status': 'inProgress'}})
            if case == 'final':
                empty = {'id': 'empty-reasoning', 'type': 'reasoning', 'summary': [], 'content': []}
                event('item/completed', item=empty)
                message('FINAL-ONLY **answer** café.', complete=True)
                message('FINAL-ONLY **answer** café.', complete=True)
                finish()
                continue
            event('item/reasoning/summaryTextDelta', itemId='reasoning-1',
                  summaryIndex=0, delta='**Checking the fixture**')
            time.sleep(.6)
            event('item/reasoning/summaryTextDelta', itemId='reasoning-1',
                  summaryIndex=1, delta='Received summary detail: preserve both paragraphs and UTF-8 café.')
            time.sleep(.6)
            message('Partial **answer** retained before the next event.')
            time.sleep(.6)
            if case == 'failure':
                finish('failed', error={'message': 'FIXTURE BACKEND FAILURE: retryable test error'})
            elif case == 'disconnect':
                return
            elif case == 'thinking':
                send({'id': 'fixture-tool-request', 'method': 'item/tool/call',
                      'params': {'threadId': 'fixture-thread', 'turnId': 'fixture-turn',
                                 'callId': 'fixture-tool', 'tool': 'lazarus_read_file',
                                 'arguments': {'path': 'missing-acceptance-fixture.pas'}}})
        elif method == 'turn/interrupt':
            reply({})
            finish('interrupted')
        elif method == 'turn/steer':
            reply({})
        elif method == '' and request_id == 'fixture-tool-request':
            time.sleep(.6)
            event('item/reasoning/summaryTextDelta', itemId='reasoning-2',
                  summaryIndex=0, delta='The IDE returned the missing-file result; preserve the failed tool detail.')
            time.sleep(.6)
            message('Completed after tool failure.\n\n| Check | Result |\n| --- | --- |\n'
                    '| Received thinking | Present |\n| Failed tool | Retained |', item='final', complete=True)
            finish()


if __name__ == '__main__':
    main()
