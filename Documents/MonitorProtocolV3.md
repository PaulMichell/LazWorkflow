# Monitor protocol, catalogue 3

The wire protocol between `LazAssistantMonitor` (the IDE host) and `KotlinMonitorApp` (the phone). It replaces
catalogue 2. This document is the contract for `Documents/Plan-20261103-151841-revised.md`. The October plan
(`Documents/Plan-20261029-035918.md`) is the history of the libraries. Where that plan and this document disagree,
this document wins.

The machine-readable part of this document is `Tests/Fixtures/Monitor/catalogue.json`: every message type, its
direction, its lane, its payload fields, the event kinds, the state keys, the closed value sets and the limits. The
golden messages are `Tests/Fixtures/Monitor/messages/*.json`. `Tests/AssistantMonitorProtocolV3Test.lpr` and the
Kotlin `ProtocolV3FixtureTest` check every fixture against the catalogue, and check the shared limits against the
constants in each code base. If this document and `catalogue.json` disagree, fix whichever is wrong in the same commit.
Neither one wins by default.

Status: target; the live wire is still catalogue 2 until item 7.1.

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

A plan body is not one `chunk` item. `plan_data` pieces are whole frames on the bulk lane (section 6.3), so
`max_item_bytes` does not apply to a plan and is not a reason to stop. A state value, including `plan`, that does not
fit in `outbox_frame_bytes` is sent as `chunk` frames on the state lane. Rows are not dropped to make it fit.

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
| `stream_id` | host | one copy of the conversation's event log | The epoch string the host already stores. The phone already keeps it as `hostEpoch` / `streamId`. Same value. Not a new identifier. Made again whenever the host cannot continue the log it had: the IDE restarted without the log, the log was rebuilt from the archive, or the archive was replaced. A changed `stream_id` means "your `seq` means nothing here". |
| `seq` | host | within one `stream_id` | Gap-free event number, starting at 1. `0` means "nothing applied". |
| `turn_id`, `block_id`, `image_id` | host | within one conversation | Stable IDs. They survive a new `stream_id`. |
| command ID | phone | for ever (the envelope `id`) | Duplicate detection and command state (section 7). |

All IDs follow the envelope `id` rule, except `stream_id` and `host_id`, which are 32 lowercase hex digits.

Where the code says epoch and this document says `stream_id`, they are the same value. Do not mint a second identifier.

## 5. Resume and snapshots

### 5.1 Resume

After `pair_ok` or a successful `auth`, and before any other message, the phone sends:

```json
{"v":3,"id":"r-17","type":"resume","payload":{"conversation_id":"…","stream_id":"…","seq":4211,"commands":["send-0193"]}}
```

- `conversation_id` empty means "whatever conversation the host has open". Then `stream_id` is empty and `seq` 0.
- `stream_id` and `seq` are the values the phone stored in the same database transaction as the content they describe.
- `commands` lists the command IDs in the phone's outbox whose outcome it does not know (section 7.3). It may be empty.

The host first sends every state key (section 6.3), including approval when one is active. Then it sends exactly one
content answer. There is one answer. The link thread sends it. The IDE thread is not on the resume path.

1. **Tail replay.** `stream_id` matches and the log still holds every event after `seq`: `resume_ok
   {conversation_id, stream_id, from_seq: seq + 1, to_seq: <head>}`, then those events in order. No catchup blob. No
   snapshot. If `seq` is already the head, `from_seq` is `to_seq + 1` and no events follow.
2. **Baseline.** In every other case where the host has observed the conversation (another conversation, a changed
   `stream_id`, `seq` older than the log, or `seq` ahead of the head): a metadata baseline at a head H captured under
   the mirror lock (section 5.2). Live events begin at H+1. The host does not fabricate append events numbered at or
   below H.
3. **Not ready.** If the host has not observed the conversation: `not_ready {conversation_id}`. The phone keeps its
   cache. The host does not send an empty baseline or an empty page. An empty observation is not a conversation.

If `commands` was not empty, `command_states` follows (section 7.3). That reply is control, not content.

The phone may send `resume` again at any time. That is how it changes conversation, and how it recovers from a gap.
A new resume cancels unsent work of the previous resume generation. Generation is which answer the link is serving. It
is not a payload field and not a new identifier.

### 5.2 Snapshot paging

The gap answer stays `snapshot_begin`, `snapshot_page`, and `snapshot_end`. It is a metadata baseline, not a body
dump, and it does not replace everything the phone held.

```
snapshot_begin {conversation_id, stream_id, seq, title, project_root, turn_count, page_count, turns: [outline…], state: {key: value…}[, open_block]}
snapshot_page  {conversation_id, stream_id, seq, page: 1…page_count, page_count, turns: [outline…]}   × page_count
snapshot_end   {conversation_id, stream_id, seq}
```

- `seq` is the head H the baseline represents. Live events after it begin at H+1, after `snapshot_end`.
- `page_count` is the number of `snapshot_page` frames. It is 0 when the outline fits in `snapshot_begin`.
- `turns` is the outline, oldest first: turn id, index, prompt preview, and for each block its `block_id`, `kind`,
  `state`, `revision`, `body_bytes`, and `hash`. No historical body. `state` on `snapshot_begin` repeats every state
  key, the same values the state channel just sent.
- `hash` is FNV-1a 64 over the UTF-8 body, offset basis 14695981039346656037, prime 1099511628211, written as 16
  lowercase hex digits. The same function hashes a plan file. `revision` increments when the body is replaced, not
  when it grows by append.
- The open block's current body may sit in `snapshot_begin.open_block` (`block_id`, `revision`, `body`,
  `body_bytes`, `hash`) when the encoded frame stays within `outbox_frame_bytes` (32 KiB). Otherwise that field is
  absent, the outline still names the block, and the phone fetches it at once.
- `snapshot_page` on this path carries more outline metadata when one frame is not enough. It does not carry
  historical bodies.
- `snapshot_end` is a barrier. It is not taken until every earlier frame of that resume generation has been taken.
  Pong, approval, and command acknowledgements may pass a page. They may not pass `snapshot_end` ahead of its pages.
- The phone commits the baseline in one database transaction at `snapshot_end`. It keeps every cached block whose
  hash matches, marks the others stale, removes turns and blocks the completed outline does not name, and stores the
  new `stream_id` and head. A failed or incomplete stage keeps the previous committed view. Only a complete baseline
  may remove rows. Stale blocks stay visible, marked not current, until a fetch replaces them. Byte length is not
  identity. If the link drops before `snapshot_end`, the staged pages are thrown away and the next `resume` starts
  again.

A turn fetch is not part of the baseline. The phone sends `turn {conversation_id, turn_index}`. The host answers with
one `snapshot_page` whose `turn` field is that turn's materialized rows. That page does not replace the conversation
and does not allocate or advance an event sequence. Its `seq` is the head the rows were read at. If the encoded page
exceeds `outbox_frame_bytes`, it travels as `chunk` frames of that one item (section 1.3). A turn the host does not
have is `error {reason: "not_found", ref}`.

### 5.3 Block fetch

`block_get {conversation_id, block_id, offset, prefix_hash}` asks for a block body. The request id is the envelope
`id`. `prefix_hash` is the FNV-1a 64 of the UTF-8 prefix the phone has stored, the bytes before `offset`, written as
16 lowercase hex digits. At offset 0 the prefix is empty and the hash is the offset basis, `cbf29ce484222325`.

The host answers from the phone's offset when its own body has that prefix, otherwise from 0. `block_data` echoes the
request id, revision, offset, `total_bytes`, and `last`: `block_data {conversation_id, block_id, ref, revision,
offset, text, total_bytes, last}`. `ref` is the request id. `revision` is the block revision the host is sending.
Each piece is at most `block_data_bytes` (24 KiB) of UTF-8. Offsets and lengths count UTF-8 bytes. The host never
splits a code point.

A revision that changes mid-fetch is `error {reason: "revision_changed", ref}`. The host keeps no mixed bytes. The
phone starts again from offset 0. The host keeps the revision it promised for that request until the fetch ends, the
revision changes, or the link closes.

A block that no longer exists is `error {reason: "not_found", ref}`. Transient overload is `overloaded`, not
`not_found`. The phone uses `block_get` for a deferred or stale body, and when an append offset does not match
(section 6.2).

### 5.4 Acknowledgements and flow control

The phone sends `ack {conversation_id, stream_id, seq}` after each database transaction that committed events, or
explicit deferred obligations, and at most every 250 ms. `seq` is the highest contiguous sequence whose effects, or
those obligations, have committed. It is not higher. It is not sent when apply fails.

The host rejects an ack beyond the sent head with `error {reason: "protocol", ref}` and does not move credit. It
ignores an ack for a stale `stream_id` or a resume generation it is no longer serving.

The host keeps every event after the last acknowledged `seq`, so it can replay it. Credit counts serialized
unacknowledged event bytes, and does not count snapshot pages or fetch bodies. The host sends at most
`credit_window_bytes` (512 KiB) of that JSON ahead of the last ack. When the window is full it stops sending events.
Control and state are not gated by the window. A slow phone therefore slows the event stream instead of filling the
queues.

The log of one conversation is bounded at `log_budget_bytes` (8 MiB). Older events are folded into the host's model
and dropped. A phone that resumes from before the oldest kept event gets a baseline. If the host's outbox for the log
overflows (a phone that stopped reading), the host closes the link instead of dropping events. `bye` on that overflow
is best effort and is not a prerequisite for closing the socket. The phone resumes.

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
| `block_open` | `turn_id, block_id, ordinal, kind, title`; optional `tool_name, tool_id` | A new block in that turn, empty body, state `running`. The body follows as later events. `kind` is `answer`, `thinking`, `tool`, `note` or `error`. |
| `block_append` | `block_id, offset, text` | `text` added at the end of the body. At most `max_append_bytes` (4 KiB) of UTF-8, and less when JSON escaping would push the encoded frame over `outbox_frame_bytes`. Split only on a code-point boundary, before `seq` is assigned. Every slice has its own `seq`. `offset` is the body's length in UTF-8 bytes before this append. |
| `block_replace` | `block_id`; and either `body`, or `deferred, revision, body_bytes` | One event. Used when an earlier part changed. At most 4 KiB of UTF-8, and only when the encoded frame fits, it carries `body`. Over that it carries `deferred: true`, `revision`, and `body_bytes`, omits `body`, and the phone fetches it. |
| `block_close` | `block_id, state, duration_ms` | The block finished. `state` is `ok`, `failed` or `cancelled`. |
| `image_added` | `turn_id, image_id, name, mime, width, height, bytes`; optional `block_id` | Image metadata only. The bytes stay on `image_get`. |
| `turn_close` | `turn_id, outcome, duration_ms, error_text` | The turn ended. `outcome` is `done`, `failed` or `stopped`. |
| `title_changed` | `title` | The conversation title changed. |

A new block is `block_open`, then the body events, then `block_close` when it finishes. `block_open` does not carry
the body. An initial body of at most 4 KiB is one or more `block_append` slices. A larger initial body is one deferred
`block_replace`, and the phone fetches it.

### 6.2 Append offsets

`offset` and `body_bytes` count UTF-8 bytes. The host never splits a code point. A `block_append` carries at most
4 KiB of UTF-8, less when escaping would exceed 32 KiB encoded, and every slice has its own `seq`. Before applying
`block_append`, the phone checks that `offset` equals the byte length it has stored for that block. On a mismatch it
does not guess. It sends `block_get` with `prefix_hash` of the body it has, at the offset it has (section 5.3). Other
blocks and later events carry on.

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
| `status` | `busy, sending, plan_running, phase, status_text, started_at, can_send, can_steer, can_stop, can_change_mode, error_text` |
| `session` | `model, backend, signed_in, effort, skill, context_text, remote_approval, approval_caption` |
| `mode` | `mode, locked` |
| `target` | `kind, display, root` |
| `targets` | `current, choices` (`target_choice`) |
| `conversations` | `current, choices` (`conversation_choice`), `truncated` |
| `models` | `current, backend, choices` (`id_choice`), `note` |
| `reasoning` | `current, choices` (`id_choice`), `note` |
| `permissions` | `current, backend, choices` (`id_choice`), `note` |
| `plan` | `path, title, running, revision, rows` (`plan_row`). No body. |
| `plan_choices` | `choices` (`target_choice`: path and caption). Required. |
| `tasks` | `rows` (`task_row`). Required. |
| `approval` | `active`; when active also `tool_id, tool_name, summary, mode_caption, decisions_accepted` |

Every key in the table is required. The host sends each one on change, and every key before content on resume. A
content gap does not freeze the last value. `plan_choices` and `tasks` are required keys, not optional menus.

`started_at` is ISO 8601 UTC, empty when there is nothing to time. It replaces `elapsed_ms`. The phone computes
elapsed time from `started_at` and its own clock. A ticking clock is not a reason to send `status`.

`busy` is true only while the IDE reports work running (`Sending` or a plan run). A command the host has queued but
not started does not make it busy (plan item 3.5).

`revision` on `plan` is FNV-1a 64 of the whole file, the same basis and prime as a block hash, written as 16 lowercase
hex digits. It is empty when no file is open. It is not a fingerprint of a capped preview.

The plan is state, not a log event. A plan belongs to the project, not to one conversation, and only its latest form
matters. The body is not in the state value. A plan is never refused for size. The body is `plan_get {path, offset,
revision}` answered by `plan_data {path, revision, offset, text, total_bytes, last, ref}` pieces of at most
`block_data_bytes` (24 KiB) of UTF-8. `ref` is the `id` of `plan_get`. Each piece is its own frame on the bulk lane.
`plan_data` is not a `chunk` item, so `max_item_bytes` does not cap a plan and is not a reason to stop. The host
reads the file in slices and releases any lock before the read and the socket write. A revision that changes
mid-transfer is `revision_changed`, and the phone starts again from offset 0. The same revision resumes from the
stored length. If the encoded `plan` state exceeds `outbox_frame_bytes`, the host sends it as `chunk` frames on the
state lane and does not drop rows.

The progress dialog is phone UI. It is not a message. While `last` has not checked out and `total_bytes` exceeds
`inline_body_bytes` (256 KiB), the plan screen may show bytes received and the total. It does not cover the
conversation and does not disable send, steer, stop, or approval. A body of 256 KiB or less arrives without that
dialog. When the body file cannot grow, the phone shows `storage`, keeps the prefix, and does not substitute a
sentence for the document. `storage` is not a host message.

## 7. Commands

### 7.1 Command messages

The phone sends these. Each payload is unchanged from catalogue 2.

| Type | Payload |
|---|---|
| `send`, `steer` | `text` (at most 65 536 characters) |
| `stop`, `new_conversation`, `run_plan`, `stop_plan`, `close_plan` | none |
| `set_mode` | `mode` |
| `select_conversation` | `id` (archive ID, empty for the current conversation) |
| `select_target` | `path` (empty for the current project) |
| `set_model` | `model` |
| `set_reasoning` | `level` (empty for the model default) |
| `set_permissions` | `approval` |
| `select_plan` | `path` |
| `new_plan` | optional `title` |
| `work_on_plan` | `index` |
| `run_task`, `insert_task` | `id, note` |

`approval_decision {tool_id, allow}` is not a command. The link thread applies it at once, as in catalogue 2, and the
host answers `approval_closed {tool_id, reason}`. `resume`, `ack`, `block_get`, `plan_get`, `turn`, `image_get`,
`ping` and `pong` are not commands either. They have no lifecycle and are not recorded.

The host refuses `work_on_plan`. Run Plan starts at the first item that is not complete. Which section runs is not a
wire decision.

### 7.2 Lifecycle

```
send (id = command ID) →
                       ← command_state {ref, state: "queued"}          at once, before the IDE thread runs
                       ← command_state {ref, state: "accepted"}        the IDE thread started it
                       ← command_state {ref, state: "done"[, text]}    it finished
                    or ← error {reason, message, ref}                  refused (recorded state "rejected")
```

There is no parallel `queued`, `accepted`, or `done` type. The lifecycle is `command_state`, and `command_states` on
resume. `insert_task` puts the inserted text on `command_state.text` when `state` is `done`.

- The host records every command ID in a table of the last `command_memory` (256) IDs with their state (plan item
  4.4). `queued` goes out before the IDE thread is involved, so a slow IDE never looks like a lost command.
- `accepted` may be skipped: a quick command can go straight from `queued` to `done` or `error`. States only move
  forward. `done` and `rejected` are final.
- For `send`, `done` comes when the turn ends. This replaces catalogue 2's `insert_result`.
- **Duplicates.** A command whose ID is still in the table is not run again. The host answers `command_state {ref,
  state[, reason][, text]}` with the recorded state.
- `host_busy` is a reason for `error`, used only when the host refuses the command because of its real state (for
  example, a send while a reply is running). It is never a timeout, and it is never the answer to a second link. A
  second controller replaces the first with `bye {reason: "replaced"}` (section 3). The `busy` reject is not sent.
  The reason stays in the closed set so an older frame can still be read.

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
`revision_changed`, `overloaded`, `snapshot_too_large` (not sent by a catalogue 3 host, which pages instead; kept so
the reason set matches item 3.2), `cancelled`, `failed`.

`revision_changed` answers a fetch whose revision moved. The phone starts again from offset 0. `overloaded` is a
retryable overload, distinct from `not_found`. The phone may ask again. Do not report overload as a missing object.
`storage` is the name the phone shows when a body file cannot grow. It is not a host message and not a reason on
`error`.

A malformed message of a known type is answered with `error {reason: "protocol"}` and changes no state. A framing
error, a chunk error or a failed `auth` closes the link.

## 11. Lanes

The host outbox takes frames in this order: control, state, log, bulk.

`snapshot_begin`, the metadata `snapshot_page` frames, and `snapshot_end` of one resume generation are ordered by the
barrier in section 5.2. Pong, approval, and command acknowledgements stay on the control lane. They may pass a page.
They may not pass `snapshot_end` ahead of its pages. `plan_data` is bulk.

| Lane | Types |
|---|---|
| control | `hello_ok`, `pair_ok`, `rejected`, `bye`, `ping`, `pong`, `error`, `command_state`, `command_states`, `approval_closed`, `resume_ok`, `not_ready`, `snapshot_begin`, `snapshot_end`, `image_unavailable`, `state` with key `approval` |
| state | `state` (other keys), and `chunk` frames of a state value |
| log | `event` |
| bulk | `snapshot_page`, `block_data`, `plan_data`, `image_data`, and `chunk` frames of those |

A `chunk` frame goes on the lane of its `item_type`. A `plan_data` piece is not a `chunk`.

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
| `max_append_bytes` | 4 096 |
| `max_image_fetch_bytes` | 1 048 576 |

## 13. What catalogue 2 types become

| Catalogue 2 | Catalogue 3 |
|---|---|
| `snapshot`, `catchup`, `transcript`, `turn_data`, `patch` | `resume_ok` / baseline `snapshot_*` and `event`. No body dump. |
| `turn` | still the turn-fetch request. The answer is one materialized `snapshot_page`, not a conversation replace. |
| `conversation_closed` | a `resume` for the new conversation, after `state` key `conversations` changes |
| `status`, `mode`, `target`, `targets`, `conversations`, `models`, `reasoning`, `permissions`, `plan`, `tasks` | `state` keys. `status` carries `started_at`, not `elapsed_ms`. `plan` carries `revision` and no body. |
| `refresh` (`plan_choices`, `menu_choices`) | not needed: menus are state keys, sent on change and on resume |
| `approval_requested` | `state` key `approval` |
| `queued`, `accepted`, `done`, `insert_result` | `command_state`. `insert_task` text is `command_state.text` when `state` is `done`. |
| `rejected {reason: "busy"}` | not sent. A second controller gets `bye {reason: "replaced"}`. |
| `image_get {turn_index, image_id}` | `image_get {conversation_id, image_id}` |
| `hello_ok` epoch, cursor and conversation fields | `host_id` in `hello_ok`. The epoch string is `stream_id`. Same value. The rest is in the resume answer. |
| plan body inside a plan frame | `plan_get` / `plan_data`. Never refused for size. |
| everything else | unchanged payload |

## 14. Fixtures

`Tests/Fixtures/Monitor/` (see its README):

- `catalogue.json` is the catalogue described above.
- `messages/<type>.json` or `messages/<type>-<variant>.json` is one golden message per file, compact JSON as it
  appears on the wire. Every type, every event kind and every state key has at least one fixture.
- `messages/chunk-1.json` and `messages/chunk-2.json` split one `state` message, so the tests also check that joining
  the slices gives a valid message.
- Changed with this cut: `snapshot_begin`, `snapshot_page` (outline) and `snapshot_page-turn` (a turn fetch),
  `block_get`, `block_data`, `state-status`, `state-plan`, `event-block_replace-deferred`, and
  `command_state-insert_task`. Added: `not_ready`, `plan_get`, `plan_data`, `turn`, `error-revision_changed`,
  `error-overloaded`. Removed as types: `queued`, `accepted`, `done`.

When the catalogue 3 codecs are written (items 5.3–5.6), their encoders must reproduce these fixtures, and their
decoders must read them. Both codec test suites will then take them over.
