# Monitor protocol, catalogue 3

The wire protocol between `LazAssistantMonitor` (the IDE host) and `KotlinMonitorApp` (the phone). It replaces
catalogue 2. The design and the reasons for it are in `Documents/Plan-20261029-035918.md`, sections 1 and 4.

The machine-readable part of this document is `Tests/Fixtures/Monitor/catalogue.json`: every message type, its
direction, its lane, its payload fields, the event kinds, the state keys, the closed value sets and the limits. The
golden messages are `Tests/Fixtures/Monitor/messages/*.json`. `Tests/AssistantMonitorProtocolV3Test.lpr` and the
Kotlin `ProtocolV3FixtureTest` check every fixture against the catalogue, and check the shared limits against the
constants in each code base. If this document and `catalogue.json` disagree, fix whichever is wrong in the same commit.
Neither one wins by default.

Status: specification. No code speaks catalogue 3 yet. Items 4.4, 5.2–5.6, 6.x and 7.x implement it.

## 1. Transport

### 1.1 Socket and TLS

Unchanged from catalogue 2. TCP on port 56122 (one above the Grok OAuth redirect port), TLS 1.2 or later with the
host's self-signed certificate. The phone pins the SHA-256 fingerprint it saw when it paired.

Each side enables TCP keepalive as a backstop under the heartbeat (section 9). The host uses an idle time of 30 s, an
interval of 10 s and 3 probes where the platform allows it.

### 1.2 LAM1 framing

Unchanged. Every message is one frame:

| Bytes | Field | Value |
|---|---|---|
| 0–3 | magic | ASCII `LAM1` |
| 4 | frame version | 1 |
| 5 | flags | 0 |
| 6–7 | reserved | 0 |
| 8–11 | payload length | unsigned 32-bit, big-endian |
| 12… | payload | strict UTF-8 JSON object |

A payload longer than 262 144 bytes is refused before it is read. Invalid UTF-8, or JSON that is not an object, closes
the link. A partial frame that is not finished within 10 s closes the link.

### 1.3 Frame size and chunks

The host writes no frame longer than 32 768 bytes (`outbox_frame_bytes`). This keeps a control message behind at most
one frame of bulk data (plan item 4.2). The phone can send frames up to the LAM1 cap.

A larger item (a snapshot page, an image, a long block fetch) is sent as an ordered run of `chunk` frames:

```json
{"v":3,"id":"c-41","type":"chunk","payload":{"item_id":"img-7","part":1,"part_count":3,"item_type":"image_data","data":"…"}}
```

- `data` is a slice of the item's complete envelope JSON text (`{"v":3,"id":…,"type":"image_data","payload":…}`).
  Join the `data` strings of parts 1 to `part_count` in order, then parse the result as one message.
- The sender slices only between Unicode code points, and keeps each chunk frame within `outbox_frame_bytes`.
- Parts of one item arrive in order. Chunks of different items, and whole frames, can come in between.
- `item_id` is unique among the open items from that sender. `item_type` is the type of the joined message, so a
  receiver can drop an item it does not want before joining it.
- A receiver holds at most 8 open items, and at most `max_item_bytes` (4 MiB) in one item. Going past either limit, a
  missing part, a repeated part, or a `part_count` that changes is a protocol error, and the link closes.
- A joined item must not be another `chunk`.

Either side may send chunks. In practice only the host needs them.

## 2. Envelope

```json
{"v":3,"id":"send-0193","type":"send","payload":{"text":"Hello"}}
```

| Field | Rule |
|---|---|
| `v` | Integer catalogue version. Exactly 3. |
| `id` | 1–64 characters from `A–Z a–z 0–9 . _ -`, not `.` or `..`. Unique per sender for the life of a link. A command's `id` is its command ID (section 7), so the phone keeps it unique across links too. |
| `type` | A type name from the catalogue, in snake case. |
| `payload` | A JSON object, `{}` when there are no fields. |

No other top-level fields. Payload field names are snake case. A receiver ignores no fields: a missing required field
or a field of the wrong JSON type is a protocol error for that message. A receiver ignores optional fields it does not
know only where this document says so (none in catalogue 3).

An unknown `type` is answered with `error {reason: "unknown_type", ref: <id>}` and changes no state, as in catalogue 2.

## 3. Handshake and version negotiation

```
phone                                      host
  hello {client_name, client_version[, client_id]}  →
                              ← hello_ok {nonce, server_name, host_id}
  pair {code, fingerprint}          →      (first time)
                              ← pair_ok {client_id, session_token}
  auth {client_id, hmac}            →      (paired)
  resume {…}                        →      (section 5)
                              ← state × every key, then the resume answer
```

- `hello` carries `v: 3` like every message. The host reads the envelope `v` before anything else.
- **Version mismatch.** If `v` is not 3, the host answers `rejected {reason: "protocol", host_version: 3,
  client_version: <v>}` and closes the link. That one reply uses the **client's** envelope version (1, 2 or 3), so an
  older app can decode it and tell the user to update. A catalogue 3 phone that receives `rejected` with any `v` from
  1 to 3 decodes it the same way. Either side shows "Update the app or the IDE: this IDE speaks protocol N, the app
  speaks M." No catalogue 2 messages are sent or accepted in catalogue 3, and there is no dual stack.
- `auth.hmac` is lowercase hex HMAC-SHA-256 of the `hello_ok.nonce` text, keyed with the session token. This is
  unchanged. The nonce is single-use and expires after 30 s. The pair code expires after 120 s, and three wrong codes
  discard it.
- `host_id` is a random 128-bit value in lowercase hex. It is made once per IDE installation and kept in the monitor
  settings. The phone stores it with the pairing and keys its database on `(host_id, conversation_id)`. It does not
  change when the certificate is renewed, so a new certificate does not orphan cached conversations. This is the
  "hostFingerprint" of plan item 5.2.
- **One controller.** A new link that authenticates replaces the old one. The old link gets `bye {reason:
  "replaced"}`, is flushed for at most 500 ms, and closes. The host no longer answers `rejected {reason: "busy"}`, but
  the reason stays in the closed set so a catalogue 3 phone can still read it.
- `bye` may be sent by either side, then the sender closes. Reasons: `disabled`, `revoked`, `replaced`, `background`,
  `user`, `protocol`.

## 4. Identity

| Name | Made by | Lifetime | Use |
|---|---|---|---|
| `host_id` | host | the IDE installation | Which IDE a cached conversation came from. |
| `conversation_id` | host | the conversation, kept in its archive | Which conversation. A GUID made when the conversation starts, including a new unsaved one (plan item 5.2). Never `current`. |
| `stream_id` | host | one copy of the conversation's event log | Made again whenever the host cannot continue the log it had: the IDE restarted without the log, the log was rebuilt from the archive, or the archive was replaced. A changed `stream_id` means "your `seq` means nothing here". |
| `seq` | host | within one `stream_id` | Gap-free event number, starting at 1. `0` means "nothing applied". |
| `turn_id`, `block_id`, `image_id` | host | within one conversation | Stable IDs. They survive a new `stream_id`. |
| command ID | phone | for ever (the envelope `id`) | Duplicate detection and command state (section 7). |

All IDs follow the envelope `id` rule, except `stream_id` and `host_id`, which are 32 lowercase hex digits.

## 5. Resume and snapshots

### 5.1 Resume

After `pair_ok` or a successful `auth`, and before any other message, the phone sends:

```json
{"v":3,"id":"r-17","type":"resume","payload":{"conversation_id":"…","stream_id":"…","seq":4211,"commands":["send-0193"]}}
```

- `conversation_id` empty means "whatever conversation the host has open". Then `stream_id` is empty and `seq` 0.
- `stream_id` and `seq` are the values the phone stored in the same database transaction as the content they describe.
- `commands` lists the command IDs in the phone's outbox whose outcome it does not know (section 7.3). It may be empty.

The host first sends every state key (section 6). Then it sends exactly one of these:

1. **Tail replay.** `stream_id` matches and the log still holds every event after `seq`: `resume_ok
   {conversation_id, stream_id, from_seq: seq + 1, to_seq: <head>}`, then events `from_seq` to `to_seq` in order. If
   `seq` is already the head, `from_seq` is `to_seq + 1` and no events follow.
2. **Snapshot.** In every other case (another conversation, a changed `stream_id`, `seq` older than the log, or `seq`
   ahead of the head): a full snapshot (section 5.2) at the current head, then live events.

If `commands` was not empty, `command_states` follows (section 7.3). After that, live events flow as they happen.

The phone may send `resume` again at any time. That is how it changes conversation, and how it recovers from a gap.
The host answers as above. Events of the previous answer that are still queued are discarded at the host.

### 5.2 Snapshot paging

```
snapshot_begin {conversation_id, stream_id, seq, title, project_root, turn_count, page_count, turns: [outline…], state: {key: value…}}
snapshot_page  {conversation_id, stream_id, seq, page: 1…page_count, page_count, turns: [turn…]}   × page_count
snapshot_end   {conversation_id, stream_id, seq}
```

- `seq` is the head the snapshot represents. Events after it follow `snapshot_end` straight away.
- `turns` in `snapshot_begin` is the outline of every turn (`outline_turn`), oldest first, so the phone can show the
  list before the bodies arrive. `state` holds every state key, the same values the state channel just sent.
- Each page carries whole turns (`turn` objects) in order, oldest first. The host fills a page up to about 32 KiB of
  JSON. One turn larger than that is a page by itself, and travels in chunks (section 1.3).
- **Nothing is truncated.** A block body longer than `inline_body_bytes` (256 KiB of UTF-8) is sent with `deferred:
  true`, `body: ""` and its real `body_bytes`. The phone fetches it with `block_get` (section 5.3) when it is shown.
- The phone stages the pages and applies them in one database transaction at `snapshot_end`, together with
  `(stream_id, seq)`. That replaces everything it held for the conversation. If the link drops before `snapshot_end`,
  the staged pages are thrown away and the next `resume` starts again.

### 5.3 Block fetch

`block_get {conversation_id, block_id, offset}` asks for a block body from the UTF-8 byte `offset`. The host answers
with `block_data {conversation_id, block_id, offset, text, total_bytes, last}` frames of at most `block_data_bytes`
(24 KiB) of text each, from `offset` to the end. A block that no longer exists is answered with `error {reason:
"not_found", ref}`. The phone uses `block_get` for deferred bodies, and when an append offset does not match (section
6.2).

### 5.4 Acknowledgements and flow control

The phone sends `ack {conversation_id, stream_id, seq}` after each database transaction that applied events, and at
most every 250 ms. `seq` is the highest event it has stored.

The host keeps every event after the last acknowledged `seq`, so it can replay it. It sends at most
`credit_window_bytes` (512 KiB) of unacknowledged event JSON ahead of the last ack. When the window is full it stops
sending events (the state channel and control messages still flow) until an ack arrives. A slow phone therefore slows
the host down instead of filling its queues. Snapshot pages and block data are not counted in the window.

The log of one conversation is bounded at `log_budget_bytes` (8 MiB). Older events are folded into the host's model
and dropped. A phone that resumes from before the oldest kept event gets a snapshot. If the host's outbox for the log
overflows (a phone that stopped reading), the host closes the link instead of dropping events. The phone resumes.

## 6. Content and state

### 6.1 Events

```json
{"v":3,"id":"e-4212","type":"event","payload":{"conversation_id":"…","stream_id":"…","seq":4212,"event":"block_append","data":{"block_id":"b-88","offset":5120,"text":"…"}}}
```

Every content change is one event. `seq` increases by exactly 1 per event within a `stream_id`. The phone applies an
event only if its `seq` is the stored `seq + 1`. A lower `seq` is a duplicate and is skipped. A higher `seq` is a gap:
the phone stops applying and sends `resume`, with the retry rules of plan item 3.1 (1 s, 2 s, 4 s, then 8 s, then
reconnect).

| `event` | `data` | Meaning |
|---|---|---|
| `turn_open` | `turn_id, turn_index, mode, prompt, created_at` | A new turn. `prompt` is the full text. `created_at` is ISO 8601 UTC. |
| `block_open` | `turn_id, block_id, ordinal, kind, title`; optional `tool_name, tool_id` | A new block in that turn, empty body, state `running`. `kind` is `answer`, `thinking`, `tool`, `note` or `error`. |
| `block_append` | `block_id, offset, text` | `text` added at the end of the body. `offset` is the body's length in UTF-8 bytes before this append. |
| `block_replace` | `block_id, body` | The whole body replaced. Used only when an earlier part changed. |
| `block_close` | `block_id, state, duration_ms` | The block finished. `state` is `ok`, `failed` or `cancelled`. |
| `image_added` | `turn_id, image_id, name, mime, width, height, bytes`; optional `block_id` | Image metadata. The bytes come from `image_get`. |
| `turn_close` | `turn_id, outcome, duration_ms, error_text` | The turn ended. `outcome` is `done`, `failed` or `stopped`. |
| `title_changed` | `title` | The conversation title changed. |

### 6.2 Append offsets

`offset` and `body_bytes` count UTF-8 bytes. The host never splits a code point. Before applying `block_append`, the
phone checks that `offset` equals the byte length it has stored for that block. On a mismatch it does not guess. It
stops applying that block, sends `block_get` from offset 0, and replaces the body with the answer. Other blocks and
later events carry on.

The golden fixtures `event-block_append-first.json` and `event-block_append-second.json` include a non-ASCII
character, so both test suites check that the second offset is the UTF-8 length of the first text.

### 6.3 State channel

```json
{"v":3,"id":"s-90","type":"state","payload":{"key":"status","value":{"busy":true, …}}}
```

State is a set of keys. Each `state` message carries the **whole** value of one key, and the latest value wins. There
is no history and no `seq`. The host's outbox keeps only the newest unsent value of each key. On every resume the host
sends every key before anything else, and `snapshot_begin` repeats them all. A lost state message can therefore never
leave a stale "busy" on the phone.

State goes on the state lane, except key `approval`, which goes on the control lane so a tool approval is never stuck
behind bulk data.

| Key | Value fields |
|---|---|
| `status` | `busy, sending, plan_running, phase, status_text, elapsed_ms, can_send, can_steer, can_stop, can_change_mode, error_text` |
| `session` | `model, backend, signed_in, effort, skill, context_text, remote_approval, approval_caption` |
| `mode` | `mode, locked` |
| `target` | `kind, display, root` |
| `targets` | `current, choices` (`target_choice`) |
| `conversations` | `current, choices` (`conversation_choice`), `truncated` |
| `models` | `current, backend, choices` (`id_choice`), `note` |
| `reasoning` | `current, choices` (`id_choice`), `note` |
| `permissions` | `current, backend, choices` (`id_choice`), `note` |
| `plan` | `path, title, running, rows` (`plan_row`) |
| `plan_choices` | `choices` (`target_choice`: path and caption) |
| `tasks` | `rows` (`task_row`) |
| `approval` | `active`; when active also `tool_id, tool_name, summary, mode_caption, decisions_accepted` |

`busy` is true only while the IDE reports work running (`Sending` or a plan run). A command the host has queued but
not started does not make it busy (plan item 3.5).

The plan is state, not a log event. A plan belongs to the project, not to one conversation, and only its latest form
matters.

## 7. Commands

### 7.1 Command messages

The phone sends these. Each payload is unchanged from catalogue 2.

| Type | Payload |
|---|---|
| `send`, `steer` | `text` (at most 65 536 characters) |
| `stop`, `new_conversation`, `run_plan`, `stop_plan` | none |
| `set_mode` | `mode` |
| `select_conversation` | `id` (archive ID, empty for the current conversation) |
| `select_target` | `path` (empty for the current project) |
| `set_model` | `model` |
| `set_reasoning` | `level` (empty for the model default) |
| `set_permissions` | `approval` |
| `select_plan`, `remove_plan` | `path` |
| `new_plan` | optional `title` |
| `work_on_plan` | `index` |
| `run_task`, `insert_task` | `id, note` |

`approval_decision {tool_id, allow}` is not a command. The connection thread applies it at once, as in catalogue 2,
and the host answers `approval_closed {tool_id, reason}`. `resume`, `ack`, `block_get`, `image_get`, `ping` and
`pong` are not commands either. They have no lifecycle and are not recorded.

### 7.2 Lifecycle

```
send (id = command ID) →
                       ← queued   {ref}                 at once, from the connection thread
                       ← accepted {ref}                 the IDE thread started it
                       ← done     {ref[, text]}         it finished
                    or ← error    {reason, message, ref} it was refused (state "rejected")
```

- The host records every command ID in a table of the last `command_memory` (256) IDs with their state (plan item
  4.4). `queued` goes out before the IDE thread is involved, so a slow IDE never looks like a lost command.
- `accepted` may be skipped: a quick command can go straight from `queued` to `done` or `error`. States only move
  forward. `done` and `rejected` are final.
- For `send`, `done` comes when the turn ends. `insert_task` puts the inserted text in `done.text`. This replaces
  catalogue 2's `insert_result`.
- **Duplicates.** A command whose ID is still in the table is not run again. The host answers `command_state {ref,
  state[, reason]}` with the recorded state.
- `host_busy` is a reason for `error`, used only when the host refuses the command because of its real state (for
  example, a send while a reply is running). It is never a timeout.

### 7.3 After an ambiguous disconnect

The phone keeps each command in its database outbox until the command reaches a final state. On reconnect it lists
the IDs with no final state in `resume.commands`. The host answers once with `command_states {states: [command_state…]}`,
one entry per listed ID, in the same order. The state is `unknown` when the ID is not in the table.

- `unknown`: the host never received it (or forgot it, after 256 newer commands). The phone may send it again, with
  the **same** ID.
- `queued` or `accepted`: the host has it. The phone waits for the outcome.
- `done` or `rejected`: final. The phone clears it.

The phone never sends a prompt again automatically once the host has reported any state other than `unknown` for it.
If the outcome cannot be known, it offers the draft back with "Not delivered — Retry". This keeps the rule that a turn
that ran a tool is never replayed automatically.

## 8. Images

`image_get {conversation_id, image_id}` asks for an image. The host answers `image_data {image_id, mime, width,
height, revision, bytes_base64}` as one item (in chunks when it is large), or `image_unavailable {image_id, reason}`
with reason `missing`, `too_large` or `refused`. Images larger than `max_image_fetch_bytes` (1 MiB decoded) are
`too_large`.

## 9. Heartbeat

Both sides send `ping {ticks}` after `heartbeat_ms` (10 s) without sending anything, and treat `dead_link_ms` (30 s)
without receiving anything as a dead link, and close it. Any received frame counts. A side's own pings do not count as
received. `pong {ticks}` echoes the ping's ticks. Each side answers a ping at once from its connection thread, on the
control lane, without waiting for its UI or the IDE thread. `ticks` is the sender's monotonic clock in milliseconds,
used only for its own round-trip measurement.

## 10. Errors

`error {reason, message, ref}`: `ref` is the `id` of the message it answers, or empty. `message` is one sentence for
the user. Reasons: `unknown_type`, `protocol`, `payload_too_large`, `host_busy`, `no_session`, `not_found`,
`snapshot_too_large` (not sent by a catalogue 3 host, which pages instead; kept so the reason set matches item 3.2),
`cancelled`, `failed`.

A malformed message of a known type is answered with `error {reason: "protocol"}` and changes no state. A framing
error, a chunk error or a failed `auth` closes the link.

## 11. Lanes

The host outbox (plan item 4.2) takes frames in this order: control, state, log, bulk.

| Lane | Types |
|---|---|
| control | `hello_ok`, `pair_ok`, `rejected`, `bye`, `ping`, `pong`, `error`, `queued`, `accepted`, `done`, `command_state`, `command_states`, `approval_closed`, `resume_ok`, `snapshot_begin`, `snapshot_end`, `image_unavailable`, `state` with key `approval` |
| state | `state` (other keys) |
| log | `event` |
| bulk | `snapshot_page`, `block_data`, `image_data`, and `chunk` frames of those |

A `chunk` frame goes on the lane of its `item_type`.

## 12. Limits

All of these are in `catalogue.json` under `limits`. The tests compare each one that exists in code with the code's
constant.

| Limit | Value |
|---|---|
| `max_frame_payload_bytes` | 262 144 |
| `frame_header_bytes` | 12 |
| `outbox_frame_bytes` | 32 768 |
| `max_item_bytes` | 4 194 304 |
| `max_open_chunk_items` | 8 |
| `max_message_id_chars` | 64 |
| `max_send_chars` | 65 536 |
| `heartbeat_ms` | 10 000 |
| `dead_link_ms` | 30 000 |
| `partial_frame_ms` | 10 000 |
| `handshake_ms` | 10 000 (TLS handshake deadline) |
| `keepalive_idle_s`, `keepalive_interval_s`, `keepalive_probes` | 30, 10, 3 |
| `pair_code_ttl_ms` | 120 000 |
| `nonce_ttl_ms` | 30 000 |
| `approval_wait_ms` | 120 000 |
| `command_memory` | 256 |
| `ack_interval_ms` | 250 |
| `credit_window_bytes` | 524 288 |
| `log_budget_bytes` | 8 388 608 |
| `inline_body_bytes` | 262 144 |
| `block_data_bytes` | 24 576 |
| `max_image_fetch_bytes` | 1 048 576 |

## 13. What catalogue 2 types become

| Catalogue 2 | Catalogue 3 |
|---|---|
| `snapshot`, `catchup`, `transcript`, `turn`, `turn_data`, `patch` | `resume_ok`/`snapshot_*` and `event` |
| `conversation_closed` | a `resume` for the new conversation, after `state` key `conversations` changes |
| `status`, `mode`, `target`, `targets`, `conversations`, `models`, `reasoning`, `permissions`, `plan`, `tasks` | `state` keys |
| `refresh` (`plan_choices`, `menu_choices`) | not needed: menus are state keys, sent on change and on resume |
| `approval_requested` | `state` key `approval` |
| `insert_result` | `done.text` |
| `image_get {turn_index, image_id}` | `image_get {conversation_id, image_id}` |
| `hello_ok` epoch, cursor and conversation fields | `host_id` in `hello_ok`, the rest in the resume answer |
| everything else | unchanged payload |

## 14. Fixtures

`Tests/Fixtures/Monitor/` (see its README):

- `catalogue.json` is the catalogue described above.
- `messages/<type>.json` or `messages/<type>-<variant>.json` is one golden message per file, compact JSON as it
  appears on the wire. Every type, every event kind and every state key has at least one fixture.
- `messages/chunk-1.json` and `messages/chunk-2.json` split one `state` message, so the tests also check that joining
  the slices gives a valid message.

When the catalogue 3 codecs are written (items 5.3–5.6), their encoders must reproduce these fixtures, and their
decoders must read them. Both codec test suites will then take them over.
