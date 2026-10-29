# Monitor protocol catalogue 3 fixtures

The golden data for `Documents/MonitorProtocolV3.md`. Both code bases read these files straight from this
directory: the Pascal `Tests/AssistantMonitorProtocolV3Test.lpr` and the Kotlin
`Source/KotlinMonitorApp/protocol/src/test/.../ProtocolV3FixtureTest.kt`. Neither test writes them.

- `catalogue.json` is the machine-readable catalogue. It holds limits, closed value sets (`enums`), shared objects,
  message types with their direction, lane and payload fields, event kinds, and state keys. A field kind is one of
  `string`, `integer`, `boolean`, `object`, `array`, `id` (the envelope ID rule), `hex32`, `enum:<name>`,
  `object:<name>`, `array:<name|string|id>`, `event_data` (checked against `events` by the sibling `event`),
  `state_value` (checked against `state` by the sibling `key`) or `state_map` (every state key and its value).
- `messages/<type>.json` and `messages/<type>-<variant>.json` hold one message each, as compact wire JSON. The part of
  the name before the first `-` must be the message type.

Rules the tests enforce:

- Every message has exactly `v`, `id`, `type` and `payload`, with `v` 3, and its payload matches the catalogue. No
  field may be missing, and no field may be added that the catalogue does not list. The one exception is
  `rejected-old-client.json`: a protocol rejection is written in the client's version (here 2), so an older app can
  read it, and its `v` must equal its `client_version`.
- Every message type, event kind and state key has at least one fixture.
- Every file fits one host frame (`outbox_frame_bytes`).
- `chunk-1.json` and `chunk-2.json` join into a valid `state` message.
- The offset in `event-block_append-second.json` is the UTF-8 byte length of the text in
  `event-block_append-first.json`, which is not ASCII.
- Each limit that also exists as a constant in code (`AssistantMonitorFrames`, `AssistantMonitorCodec`,
  `AssistantMonitorSession`, `AssistantMonitorOutbox`, `AssistantMonitorCommandIntake`, Kotlin `MonitorLimits`) has the
  same value.

To change the protocol, change `Documents/MonitorProtocolV3.md`, `catalogue.json` and the affected fixtures in the
same commit. Then run both tests.

The catalogue 2 frame fixtures stay in `Tests/Fixtures/monitor-frames/` until item 5.6 retires catalogue 2.
