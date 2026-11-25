# Monitor protocol, version 4

The wire contract between `LazAssistantMonitor` (the IDE host) and `KotlinMonitorApp` (the phone). It replaces
catalogue 3. `Documents/MonitorProtocolV3.md` is superseded. The machine-readable examples are
`Tests/Fixtures/Monitor/v4/*.json`. `Tests/AssistantMonitorFixtureTest.lpr` checks that the host encoders produce
them. The Kotlin `MonitorFixtureTest` in the `protocol` module checks that the phone accepts them and that its
command encoder produces the request fixtures. Changing a field in a fixture must fail at least one of those tests.

## 1. Transport and identity

All traffic is HTTPS/1.1 to one listener on the desktop. The certificate is the self-signed certificate minted by
`AssistantMonitorTls`. The phone pins its SHA-256 fingerprint. Every request except `pair` carries
`Authorization: Bearer <token>`. JSON bodies are UTF-8. Paths are versioned under `/v4/`.

The listener is `TFPHttpServer` in threaded mode, started off the IDE thread. `CertificateData` takes the minted DER
directly. On Linux and macOS the host ignores SIGPIPE before listen. The default port is 56122.

Identity:

- `epoch` is a random id minted when the listener starts. It changes on IDE restart.
- `rev` is a 64-bit counter within an epoch. It goes up whenever anything the phone could show changes.
- Conversation ids are the persisted monitor ids from `TAssistantConversationStore`, so they survive archiving.
- Turn ids are `TConversationTurn.Id`. The live turn already has the id it will be stored under.
- Item ids are trace block ids. Item revisions are `TTraceBlock.Revision`, meaningful within one epoch.
- Stored turns get a content `etag`: FNV-1a 64 of the stored JSON line, using `AssistantPlanHashFold`. A stored
  turn's etag stays valid across epochs.
- Image ids are the image store ids. A stored image never changes under its id.
- `client_command_id` is stored on the turn a `send` or `run_task` starts, including the live turn, and is omitted
  when empty so older lines still parse.

Errors use HTTP status codes with `{"reason":"...","message":"..."}`:

| Status | Reason |
|---|---|
| 400 | `protocol` |
| 401 | `auth` |
| 403 | `revoked` |
| 404 | `not_found` |
| 409 | `busy` or `unsaved_edits` |
| 413 | `too_large` |
| 503 | `no_session`, with `Retry-After` |

Conversation lists, turns and the plan send `ETag` and honour `If-None-Match` with 304. Quoted and bare tags match.

## 2. The pulse

`GET /v4/pulse?after=<rev>&epoch=<epoch>&interval=<ms>` is a long poll. The desktop answers at once if its epoch
differs or its rev is above `after`. Otherwise it waits until a change arrives, or for 10 seconds, and then answers
with the current pulse. A waiting request blocks on an event the snapshot publisher signals. It does not poll.

`interval` is the shortest gap the phone wants between answers. It is clamped to 150–10,000 ms and defaults to 250.
The host holds a change back until that long after its previous answer. The phone treats a link as down after 20
seconds with no answer. At most two pulse waits are held per token. A third answers the oldest at once.

`live` is null when no turn is running. `approval` is null when nothing is waiting. The phone shows the activity
clock from `activity` and `activity_since`, corrected by `server_time`, and ticks it locally. `stop_pending` stays
true until a priority stop has run on the IDE thread. See `pulse-live.json`, `pulse-idle.json` and
`pulse-sending.json`.

## 3. Reads, images and commands

| Request | Answer |
|---|---|
| `POST /v4/pair` | `{code, client_id, client_name}` in, `{token, host_name, fingerprint}` out. The only call without a token. |
| `GET /v4/hello` | `{epoch, rev, capabilities}`. `capabilities` names exactly the command types that have handlers. |
| `GET /v4/conversations` | `[{id, title, created_at, turn_count, etag, current}]` |
| `GET /v4/conversations/{id}/turns?from=N&max_bytes=B` | Stored turns from index N, with items and bodies, up to about B bytes (default 512 KiB), and `next`. |
| `GET /v4/turns/{id}?bodies=0\|1` | One turn, live or stored. `bodies=0` is the outline: ids, kinds, states, revisions and byte lengths. |
| `GET /v4/items/{id}?from=N&check=H` | `{id, rev, state, total_bytes, start, text}`. The tail after byte N is returned only when the 64 bytes before N still hash to H. Otherwise the whole item is returned with `start` 0. The host moves `start` back to a UTF-8 character boundary. |
| `GET /v4/plan` | `{path, title, etag, running, rows}` |
| `GET /v4/plan/document` | The plan Markdown preview. The fixture records the content type and body. |
| `GET /v4/plans`, `GET /v4/tasks` | Plan and task choices. |
| `GET /v4/images/{id}` | Display-size image bytes and their content type. `Cache-Control: immutable`. Not JSON. Missing is 404 `not_found`. Above 1 MiB is 413 `too_large`. Image reads take no lock the pulse or commands need. |
| `GET /v4/approval` | `{id, tool_name, summary, mode_caption, decisions_accepted}` |

Commands are `POST /v4/commands` with `{id, type, args}`. `id` is a UUID the phone makes once and reuses on every
retry. The answer is 200 `{state: "done" | "accepted"}`, or a 4xx reason. `done` may include `turn_id`. `accepted`
means the desktop has taken the command and the pulse will show its effect. An ordinary command waits up to 5
seconds for the IDE thread. If that wait runs out, the answer is `accepted`.

The command set:

- `send {text, save_first}`
- `steer {text}`
- `stop`
- `approval {tool_id, decision: allow | deny}`
- `set_mode {mode}`
- `new_conversation`
- `select_conversation {id}`
- `select_plan {path}`
- `new_plan {title}`
- `close_plan`
- `run_plan {save_first}`
- `stop_plan`
- `work_on_plan {section}`
- `run_task {task_id, note, save_first}`
- `insert_task {task_id, note}`

`select_target`, `set_model`, `set_reasoning` and `set_permissions` are not in this version. Adding one back needs a
host handler, its name in `capabilities`, and a phone control shown only when that capability is present.

`send` and `run_task` are recognised again by `TurnForClientCommand`, including after an IDE restart, and answer
`done` with the turn id. Other commands use a 256-entry table. `stop`, `stop_plan` and `approval` are naturally
idempotent.

`stop`, `steer`, `stop_plan` and `approval` never wait behind other work. They are decided on the HTTP thread, which
sets `stop_pending` or stores the approval decision under a lock and queues the form call at once. If the IDE thread
is inside a modal, the queued call runs when the modal closes.

`save_first` is false unless the phone is resending a command the host refused with 409 `unsaved_edits`. The same
command id is reused.

Pairing uses a single-use 10-character code that expires after two minutes, the require-code option, and lockout
after three failures. The host stores only the SHA-256 of the token. Revocation removes that hash. The next request
gets 403 `revoked`, and a waiting pulse is answered at once with 403. Codes and tokens are never logged. Catalogue 3
pairings do not carry over.
