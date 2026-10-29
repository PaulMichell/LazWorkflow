# KotlinMonitorApp review

Reviewed: 20 October 2026.

Scope: the Android application, JVM protocol module, build configuration, and existing unit tests. The desktop implementation was consulted where needed to understand transcript revisions. This is a review of the current application, not just a branch diff. No production code was changed.

Actions are grouped as requested and ranked within each group. **High** means security, lost commands/content, incorrect state, or potentially unbounded resource use; **Medium** means a broken feature or recovery path; **Low** means a local usability or maintenance issue. Optimisation rankings reflect expected benefit from the code, not measured device benchmarks.

The strongest foundations are the separate JVM protocol module, byte-level fixture tests, injectable TLS connector, and pure reducer functions. The most important weaknesses lie between these components: message delivery, ownership of state, reconnect boundaries, and request completion.

## Bugs

### B1. High — Preserve an explicitly saved TLS fingerprint

**Location:** `app/src/main/kotlin/computing/michell/monitor/connection/LanSession.kt:254–266`; `app/src/main/kotlin/computing/michell/monitor/ui/MonitorViewModel.kt:641,740`.

Both ViewModel connection paths call `connect(address, port)` without a fingerprint. Its default is an empty string, and even when the endpoint is unchanged, it saves that empty string over the existing fingerprint. `SslSocketConnector` then selects `TrustAllManager`. A previously pinned endpoint silently loses server authentication on application startup or a manual reconnect.

**Evidence:** reproduced by saving a paired record with a 64-character pin, calling the same two-argument connection method, and reading the record back; the fingerprint became empty. Endpoint-only trust is explicitly supported by the current code and tests; this finding concerns silently downgrading an existing pin.

**Action:** distinguish “no fingerprint update” from “explicitly clear fingerprint”; preserve the saved pin for an unchanged endpoint. Validate supplied fingerprints strictly rather than allowing a nonempty invalid value to normalise to empty. Add a regression test through the same connection path the ViewModel uses.

### B2. High — Make inbound message delivery lossless

**Location:** `app/src/main/kotlin/computing/michell/monitor/connection/LanSession.kt:228,464–470`.

The session publishes messages with `inbound.tryEmit(message)` and ignores its result. The shared flow has a replay capacity of 32 and the default suspending overflow policy. Once a subscriber falls behind, `tryEmit` can fail; the message is then lost even though `SessionState.apply` has already processed it. Slow bitmap decoding or a busy main thread can therefore leave the transport and UI disagreeing, or discard an approval, snapshot, transcript part, or image part. This behaviour follows the [official `tryEmit` contract](https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines.flow/-mutable-shared-flow/try-emit.html).

**Evidence:** a temporary probe used the session's actual inbound flow, held its collector after the first event, and issued 64 more events using the production publishing operation. Only 33 of the 65 events reached the collector. This reproduces the buffer failure, not an end-to-end network load test.

**Action:** use an ordered, bounded delivery mechanism with explicit backpressure. Coalesce only message types known to supersede earlier state; never silently discard commands, approvals, or multipart content. Test a burst while the subscriber is deliberately blocked.

### B3. High — Keep local edits and submissions in the authoritative reducer state

**Location:** `app/src/main/kotlin/computing/michell/monitor/ui/MonitorViewModel.kt:318–350,494–510,551,766–786,872–901,1035–1038`.

Incoming messages update `applied`, while typing and submitting update `uiState` and the session draft. The remote reducer therefore does not see the current draft or pending submission. This causes two concrete failures:

- An `InsertResult` leaves text in `applied.draft`. After the user submits it and clears `uiState.draft`, the next merge restores the old text through `current.draft.ifEmpty { next.draft }`, making duplicate submission possible.
- The “Nothing is running to steer” recovery examines `applied.draft`/`pendingPrompt`. An ordinary typed-and-submitted steer is absent there, so the intended fallback to Send does not run. The existing test passes because it supplies a draft directly to the reducer, unlike the actual ViewModel path.

**Evidence:** both paths were reproduced with temporary checks following the separate local and remote state transitions.

**Action:** route edits, submissions, incoming messages, and connection events through one authoritative reducer, or explicitly keep local-only fields out of the remote state. Use explicit draft replacement events rather than treating an empty draft as missing data. Test Insert → Send → Status, and typed Steer → host error through the coordinator.

### B4. High — Clear or partition content when the conversation or host changes

**Location:** `app/src/main/kotlin/computing/michell/monitor/ui/VirtualConversation.kt:126–143`; `app/src/main/kotlin/computing/michell/monitor/ui/MonitorViewModel.kt:381–405,731–740,756–764,939–962`.

`mergeLiveTurn(previous, null)` returns the previous turn, so a snapshot explicitly containing no live turn cannot clear the old conversation. Empty incoming turns also inherit old content when their numeric index matches; the desktop uses the reusable live index `-2`. History retention checks only numeric indices, not turn IDs. Switching hosts through Settings leaves the reducer and caches in place, allowing matching indices to reuse content from the previous host. `forgetPairing` clears the visible state but leaves `applied`, its dirty flag, the posted generation, and the image assembler intact.

**Evidence:** a snapshot with `live = null` retained an old answer in a temporary reducer probe. Cross-host/history reuse and incomplete reset follow from the cache keys and reset paths; those were inspected, not exercised against two desktops.

**Action:** introduce an explicit host/conversation identity and reset event. Treat an authoritative null live turn as a clear, retain history only when stable turn identity matches, and reset all reducer, request, image, and generation state together. Preserve only the local preferences/draft that are intentionally retained. Test empty snapshots, New Conversation, switching hosts with overlapping indices, and forgetting pairing while an update is pending.

### B5. High — Enforce image assembly limits before retaining each part

**Location:** `protocol/src/main/kotlin/computing/michell/monitor/protocol/SessionState.kt:45–89`; `protocol/src/main/kotlin/computing/michell/monitor/protocol/Messages.kt:1410–1426`.

`ImageAssembly` checks the 1 MiB fetch limit only after every advertised part has arrived. `partCount` is not capped, and incomplete assemblies have no byte budget or expiry. A peer can keep adding distinct valid-sized parts to an unfinished image indefinitely. The final total also uses `Int`, which is inappropriate once accumulated input is unbounded.

**Evidence:** six 190,000-byte parts with `partCount = 100` retained 1,140,000 bytes without triggering the 1,048,576-byte limit.

**Action:** track retained bytes as parts arrive, account correctly for replacements, reject oversized assemblies immediately, and bound part counts and assembly lifetime. Use checked/`Long` size arithmetic. Add tests for incomplete oversized images, duplicate parts, inconsistent metadata, and expiry. If transfers may interleave, maintain separately bounded assemblies by image ID and revision rather than resetting a single assembler for every different image.

### B6. High — Reset transcript revisions for each connection generation

**Location:** `app/src/main/kotlin/computing/michell/monitor/ui/MonitorViewModel.kt:368–405,408–418`.

Disconnect preserves `liveRevision` and `transcriptParts`. The following snapshot preserves them again when the live turn index matches. Desktop session revisions start over for a new session, and the live turn commonly remains at index `-2`. Consequently, reconnecting after revision 100 can reject new revisions 1 through 99 and reject an already-seen part at revision 100. Streaming appears frozen despite a healthy connection.

**Evidence:** a temporary probe applied disconnect, a fresh snapshot at the same live index, and revision 1 after a previous revision 100. The displayed block remained the old text. Desktop session initialisation resets `FTranscriptRevision` in `../LazAssistantMonitor/AssistantMonitorSession.pas:424`.

**Action:** scope revision comparisons and multipart accumulation to a transport/conversation generation, resetting them when that generation changes. Do not use turn index alone to infer continuity. Test reconnecting to the same live index with a lower revision.

### B7. High — Report outbound failures and retain recoverable submissions

**Location:** `app/src/main/kotlin/computing/michell/monitor/connection/LanSession.kt:243–246,522–536`; `app/src/main/kotlin/computing/michell/monitor/ui/MonitorViewModel.kt:766–786`.

`sendCatalogue` returns no result and discards `writeJson`'s Boolean. The UI clears the editable draft and marks the operation busy before that write runs. If the socket has disappeared or the write fails, there is no failure event to restore the draft, clear the optimistic state, or offer retry. The pending bubble can remain indefinitely. Separately launched writes also resolve the current link when they execute, without binding the command to the connection generation that accepted it.

**Evidence:** code-path inspection; no real network interruption was injected during a submission.

**Action:** return or publish command outcomes with command ID and connection generation. Reject stale queued work, preserve failed text for explicit retry, and distinguish transport-write success from host acceptance. Do not automatically resend a mutating command after an ambiguous disconnect unless the protocol supports deduplication. Test failures before writing, during writing, and after writing but before acknowledgement.

### B8. Medium — Detect silent peers and make reconnect exits explicit

**Resolved 2026-10-29.** `ReadEnd.Continue` is the only non-terminal value. A silent peer, a rejection, and a failed write close the owned socket. `inboundIsDead` enforces `MonitorLimits.DeadSessionMs`.

**Location:** `app/src/main/kotlin/computing/michell/monitor/connection/LanSession.kt:402–441,492–514`; `protocol/src/main/kotlin/computing/michell/monitor/protocol/FrameCodec.kt:30–32`.

The read loop converts socket timeouts into zero-byte reads and periodically sends pings, but never tracks the last received message or enforces `DeadSessionMs`. A peer that stops responding while writes still succeed can leave the UI live indefinitely. There is also a control-flow error: `ReadEnd.Closed` means both “continue reading” and “close/reconnect”. Setting it after an auth/busy rejection or failed pong write does not exit the loop; recovery depends on the peer closing its socket.

**Evidence:** code-path inspection. The 45-second dead-session constant is unused by the transport.

**Action:** track inbound activity with a monotonic clock, enforce the dead-session deadline, and represent “continue” separately from every terminal read result. Close the owned socket on a terminal result. Test a silent peer, a rejected peer that keeps the socket open, and a failed pong write.

### B9. Medium — Retry interrupted turn and image requests

**Location:** `app/src/main/kotlin/computing/michell/monitor/ui/MonitorViewModel.kt:810–816,939–962`.

Turn and image keys are inserted into `requestedTurns`/`requested` before the write is known to succeed. They are not removed on completion, write failure, timeout, or disconnect. After reconnect, turn keys still in the snapshot remain in the set, so missing content is never requested again. Image keys remain until `forgetPairing`. A single interrupted fetch can leave a placeholder or “Loading image” for the rest of the ViewModel's lifetime.

**Evidence:** inspected request, response, reconnect, and reset paths.

**Action:** separate loaded content from in-flight requests. Remove in-flight entries on completion/failure, expire them, and requeue missing content after reconnect. Include host/conversation identity in keys. Test disconnecting between a request and its response and receiving an incomplete multipart image.

### B10. Medium — Reassemble transcript blocks instead of flattening frame parts

**Location:** `app/src/main/kotlin/computing/michell/monitor/ui/MonitorViewModel.kt:408–440`; `protocol/src/main/kotlin/computing/michell/monitor/protocol/Messages.kt:1290–1317`.

The UI sorts transcript parts and flattens their block lists. It never joins a block's body fragments using `blockId`, `part`, `partCount`, and `revision`. For a long thinking block followed by an answer, frame 1 can contain the first thinking fragment plus the answer, while frame 2 contains the rest of the thinking. Flattening displays thinking → answer → thinking, splitting one logical block into multiple independent UI blocks.

**Evidence:** reproduced using `splitTranscript` with a 200,001-character thinking block followed by a small answer, encoding valid frames and reducing them in order.

**Action:** assemble fragments by stable block identity and revision, preserve original block order, and validate part ranges/counts. Define whether incomplete revisions are shown progressively or replaced atomically. Test multiple split blocks, out-of-order delivery, duplicate parts, and revision replacement.

### B11. Medium — Bind speech callbacks to the session that created them

**Location:** `app/src/main/kotlin/computing/michell/monitor/dictation/OnDeviceSpeechEngine.kt:44,60–68,104–106,161–199,211–246`; `app/src/main/kotlin/computing/michell/monitor/ui/MonitorViewModel.kt:966–1020`.

The engine reuses one recognition listener and filters callbacks with mutable `accepting`/`supportOpen` booleans. The ViewModel labels received text using the current `callbackSession`, rather than an identity carried by the callback. If a cancelled request delivers a delayed callback after another request starts, the booleans are true again and old text or support results can be accepted as belonging to the new request. Reducer tests with explicitly supplied old IDs do not test this adapter boundary.

**Evidence:** callback-generation gap found by inspection; delayed Android service callbacks were not exercised on a device.

**Action:** create callbacks that capture a request generation and reject mismatches at the engine boundary; ensure recognizer cancellation/recreation cannot relabel old events. Apply the same rule to support checks. Test cancel → restart → old partial/final/error/support result with a controllable engine adapter.

### B12. Medium — Add a recovery deadline while awaiting speech results

**Location:** `app/src/main/kotlin/computing/michell/monitor/ui/MonitorViewModel.kt:699–704`; `app/src/main/kotlin/computing/michell/monitor/dictation/OnDeviceSpeechEngine.kt:94–101`; `app/src/main/kotlin/computing/michell/monitor/dictation/PromptDictation.kt:86–88,200–220`.

Stopping dictation enters `AwaitingFinal`, which disables Send and prevents starting another dictation. If `stopListening()` throws, its exception is swallowed and the state never closes. A recognizer that fails to deliver a terminal callback has the same effect. The reducer's `Timeout` event only enters `AwaitingFinal`, and no ViewModel watchdog dispatches a terminal timeout.

**Evidence:** code-path inspection, including the swallowed exception path.

**Action:** report stop failures and schedule a cancellable deadline for final results. On expiry, keep the usable draft, cancel the engine, return to Idle, and show a concise retry message. Bind the deadline to the session ID. Test no callback, stop failure, and a final result racing with expiry.

### B13. Medium — Acknowledge prompts by submission identity, not historical prefixes

**Resolved 2026-10-29.** `promptShown` requires an exact trimmed match on a live user or steer block that was not in the submission baseline. A historical prefix no longer counts.

**Location:** `app/src/main/kotlin/computing/michell/monitor/ui/MonitorViewModel.kt:188–199,318–350`.

`promptShown` searches all loaded historical user/steer blocks using `startsWith`. A new prompt `hello` is considered acknowledged if an old turn contains `hello world`; repeating an earlier prompt also matches immediately. The next merge can clear the new pending prompt before the host has accepted it, obscuring an unsuccessful submission.

**Evidence:** reproduced with a loaded historical `hello world` block and a new pending `hello` prompt.

**Action:** correlate acceptance with command/turn identity where the protocol permits it. Otherwise restrict matching to new content in the expected turn after the submission boundary and require an exact match. Test repeated prompts, historical prefix matches, and delayed echoes.

### B14. Low — Keep expanded blocks open while their bodies stream

**Resolved 2026-10-29.** Thinking and tool cards remember expansion by `foldKey` (conversation generation, turn id, and block id), not by title or body.

**Location:** `app/src/main/kotlin/computing/michell/monitor/ui/ConversationScreen.kt:590–606`.

`FoldBlock` stores its expanded state in `remember(title, body)`. Every streamed body change reinitialises that state to false, immediately collapsing thinking/tool output the user is reading. Title changes such as running → finished also reset it.

**Evidence:** direct state-key inspection; no Compose interaction test was run.

**Action:** key expansion by stable conversation/turn/block identity and pass that identity into `FoldBlock`. Test expanding a block and then appending content or changing its status.

## Simplifications

### S1. High — Give state transitions one owner

**Location:** `app/src/main/kotlin/computing/michell/monitor/ui/MonitorViewModel.kt:98–135,318–350,545–643,872–937`.

The ViewModel coordinates `applied`, `uiState`, a dirty flag, a mutex, a posted-generation atomic, a local generation, session status, and merge-time preservation rules. Many fields are duplicated or repaired after the fact. This makes ordering difficult to reason about and underlies B3, B4, and B6.

**Action:** use one ordered event stream for user actions, network messages, and connection changes, with one reducer producing state and explicit effects. Keep presentation throttling separate from correctness. Represent submission and connection lifecycle explicitly instead of independent booleans and empty-string sentinels. Migrate incrementally using the reproduced failures as acceptance tests.

### S2. Medium — Make the ViewModel's collaborators injectable

**Location:** `app/src/main/kotlin/computing/michell/monitor/ui/MonitorViewModel.kt:545–610`.

The transport has an injectable connector and dictation has a `SpeechEngine` interface, but the ViewModel constructs the store, session, recognizer, preferences, and clocks itself. Tests consequently focus on pure helpers and miss the actual orchestration paths.

**Action:** inject small interfaces for the session, speech engine, preferences, and clock/dispatchers, with an Android factory supplying production implementations. Move coordination into a JVM-testable class if that keeps the constructor manageable. Add integration-style unit tests for local edit → send → remote event and reconnect/reset sequences.

### S3. Medium — Separate codec mechanics from the message catalogue

**Location:** `protocol/src/main/kotlin/computing/michell/monitor/protocol/Messages.kt:255–392,481–529,1290–1426`.

The same file owns models, a custom JSON tree, parsing, formatting, envelope validation, payload validation, and multipart helpers. The custom formatter has a legitimate purpose: byte compatibility with Pascal fixtures. Replacing it wholesale would risk that contract.

**Action:** retain the compatibility formatter and fixtures, but isolate JSON access/validation, envelope handling, and multipart assembly behind small typed boundaries. Keep the wire-type catalogue discoverable in one place. Return structured decoded values so callers cannot repeatedly parse the same payload differently. Validate with the existing golden-frame tests.

### S4. Low — Remove unused helpers or connect them to an intentional feature

**Location:** `app/src/main/kotlin/computing/michell/monitor/ui/VirtualConversation.kt:67,111`; `app/src/main/kotlin/computing/michell/monitor/ui/MonitorViewModel.kt:177,752,756,819`; `app/src/main/kotlin/computing/michell/monitor/connection/HostStore.kt:91`.

Repository searches found no callers for `slotUnits`, `fractionAt`, `idleTurnToShow`, `resumeConnect`, `selectTurn`, or `saveEndpoint`. `forgetPairing` also has no UI caller, despite containing a separate reset implementation. These surfaces imply behaviours the app does not currently expose and expand the maintenance/test burden.

**Action:** remove obsolete helpers and redundant aliases. If forgetting pairing is intended as a user feature, wire it to Settings after making its reset complete under B4. Avoid retaining unused transport/UI APIs solely as speculative extension points.

### S5. Low — Document and reduce Gradle compatibility overrides

**Location:** `gradle.properties:5–14`; `gradle/libs.versions.toml:2–4`.

The build emits deprecation warnings for several compatibility settings. The version-catalogue comment also says “Kotlin 2.0 line” while selecting Kotlin 2.2.10. The settings obscure which departures from defaults are actually required.

**Action:** correct stale comments and document the reason for each non-default flag. Remove unnecessary flags individually with a build check. Treat `android.builtInKotlin=false` and `android.newDsl=false` as a deliberate plugin migration task, since removing them blindly can conflict with the current external Kotlin plugin. Base this cleanup on observed build requirements, not blanket flag removal.

## Optimisations

### O1. High — Bound decoded image memory and request only useful images

**Location:** `app/src/main/kotlin/computing/michell/monitor/ui/MonitorViewModel.kt:554,872–879,946–962,1083–1089`.

Every completed image is decoded at its native dimensions and added to `bitmapsState`. Entries are not evicted when turns disappear or hosts change. `requestVisibleImages` actually scans the live turn and all loaded history, including images outside the viewport. The compressed-byte limit does not bound decoded pixel memory; even one small compressed image can require a large bitmap allocation. Android's [bitmap-loading guidance](https://developer.android.com/topic/performance/graphics/load-bitmap) describes checking bounds before allocation and sampling to the display size.

**Action:** inspect actual encoded dimensions before decoding, impose a pixel/decoded-byte budget, sample to the display size, and use a byte-bounded cache with conversation-aware keys. Request viewport images plus a small prefetch margin, and evict obsolete entries. Measure peak heap and decode time while scrolling several image-heavy conversations. Prioritise the dimension guard as a crash-prevention fix; cache sizing is the performance work.

### O2. Medium — Parse and decode each inbound payload once

**Location:** `protocol/src/main/kotlin/computing/michell/monitor/protocol/FrameCodec.kt:184–200`; `protocol/src/main/kotlin/computing/michell/monitor/protocol/Messages.kt:481–529,1410–1426`; `protocol/src/main/kotlin/computing/michell/monitor/protocol/SessionState.kt:128–157`; `app/src/main/kotlin/computing/michell/monitor/ui/MonitorViewModel.kt:1083–1089`.

Frame validation parses JSON; envelope decoding parses it again and serialises the payload back to text. Session and UI processing then parse payloads separately. For an image part, `decodeImageData` decodes base64 to obtain its size, and each caller decodes it again: the transport/session and ViewModel together decode the same bytes four times. Both layers also assemble images, although the session's completed image result is discarded.

**Action:** create one validated typed inbound message, carrying decoded image bytes where relevant. Assign image assembly to one owner and let session phase tracking inspect only the metadata it needs. Preserve strict UTF-8/size checks and fixture-compatible output. Measure allocations and CPU per large image/transcript before and after.

### O3. Medium — Use lazy conversation rendering with stable item identity

**Resolved 2026-10-29.** The transcript is a `LazyColumn`. Each row key is the turn id plus the block id. Visible items drive the body fetch.

**Location:** `app/src/main/kotlin/computing/michell/monitor/ui/ConversationScreen.kt:197–298,330–348`.

Bodies load on demand, but the displayed conversation is a scrolling `Column` that composes every slot and every loaded block. As the user visits more history, all those bodies remain part of composition/layout. Visibility detection also copies the height map and scans all slots on scroll changes. The snapshot limit of 30 turns bounds the turn count, but individual turns can still contain substantial text and many blocks.

**Action:** use a `LazyColumn` with stable turn/block keys, preferably flattening large turns into block items, and derive fetches from visible-item layout information. Preserve bottom-following, explicit user scrolling, and scrollbar behaviour with acceptance checks. Measure frame time and composition counts on long streamed turns before committing to the redesign.

### O4. Medium — Replace repeated byte-array growth with a bounded incremental frame reader

**Resolved 2026-10-29.** `LanSession` reads into one `FrameAssembler`. The assembler compacts a consumed frame in place and allocates the payload only after the length check.

**Location:** `app/src/main/kotlin/computing/michell/monitor/connection/LanSession.kt:407–427,448–460`; `protocol/src/main/kotlin/computing/michell/monitor/protocol/FrameCodec.kt:242–259`.

Each 8 KiB read copies the new chunk and concatenates it with all pending bytes; consuming a frame copies its remainder again. A maximum-sized frame arriving in roughly 32 chunks causes about 4 MiB of cumulative pending-buffer copying before JSON processing, despite carrying only about 256 KiB of payload. Fragmented traffic increases the overhead further.

**Action:** inspect the fixed header first, then fill a bounded payload buffer using offsets, or use a reusable compacting buffer. Preserve length validation before allocating the payload. Reset partial-frame timing when a complete frame is consumed and a new partial frame begins; the current timer can span successive partial frames. Benchmark fragmented and coalesced frame streams and retain malformed-header/UTF-8 coverage.

## Validation and limits

- The normal command is `JAVA_HOME=/opt/android-studio/jbr ./gradlew --offline :protocol:test :app:testDebugUnitTest`. Java was not on the shell's default PATH, so the installed Android Studio JDK was used.
- The existing suite contains **50 tests: 10 protocol and 40 app tests**. All 50 passed, with no failures, errors, or skips. The protocol task initially reused its existing result; the successful final run explicitly reran it with `:protocol:test --rerun` and restored the normal app test set after the temporary probes.
- Nine temporary regression probes were run from `/tmp/kotlin-monitor-review-tests` using an external Gradle init script. Their assertions described the desired behaviour and failed on the current implementation, reproducing B1, B2, both B3 scenarios, the null-snapshot part of B4, B5, B6, B10, and B13. The multipart probe was corrected to fit the frame limit and rerun; its final failure was the incorrect reconstructed block sequence. These probes were not added to the repository.
- Other bug findings are labelled as code inspection above. No physical-device/emulator UI session, live desktop-to-phone network test, Android speech-service race test, release packaging test, or performance benchmark was performed. Performance improvements are therefore proposed measurements, not claimed speedups.
- Highest-value permanent test additions are coordinator-level state transitions, backpressure, connection-generation resets, interrupted fetches/writes, and delayed speech callbacks. Existing passing helper tests do not establish correctness across those boundaries.
