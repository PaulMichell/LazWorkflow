# Monitor link baseline

Measurements of the `LazAssistantMonitor` LAN link, taken by `Tests/AssistantMonitorLinkTest.lpr` (plan item 2.1 of
`Documents/Plan-20261029-035918.md`). Items 3.3, 9.1, and 9.2 re-run the same harness and add their rows here. The
2026-10-29 numbers stay historical.

## How the harness measures

The test starts a real `TMonitorLanCarrier` and `TMonitorSession` on 127.0.0.1 with a throwaway certificate under a
temporary settings directory. An OpenSSL client socket connects and pairs on the open-LAN path (no code armed). The test
then reads the link in three phases, all on the same connection:

1. **Throughput.** 32 bulk snapshot pages (2000-byte title each) go through `TryQueueHostJson` and `DrainOutbound`.
   Plan frames coalesce, so they are not this workload. The 2026-10-29 row used plan frames. The test times how long
   the client takes to receive all 32. The rate is `frames / (last frame − queue time)`.
2. **Ping with a full queue.** 32 more bulk frames are queued, and then the client sends `ping`. The test records how
   many bulk frames arrived before the `pong`, and the ping→pong round trip.
3. **Resume answer.** The client sends `resume`. A stand-in for the bridge hears the command on the listen thread and
   hands it to the main thread with `TThread.Queue`, as the bridge does for the IDE thread. There it sends the bridge's
   answer set through `SendHostJson`: a catchup snapshot, a status, a plan, and the five menu lists (8 frames). The test
   records when the listen thread heard the resume, when the answer was queued, when the catchup arrived, and when the
   last frame arrived.

Each phase prints one `metric` line. The checks only require that every frame is delivered and that none is dropped.
The harness therefore passes on the slow baseline and on every later fix. Speed is read from the metric lines, not
asserted.

Run it with:

```sh
instantfpc Tests/RunAssistantTests.pas --lazarus-root /home/paul/Projects/FreePascal/Lazarus \
  --only AssistantMonitorLinkTest --output-dir <a temporary directory>
```

The metric lines are in `<output dir>/AssistantMonitorLinkTest.log`.

## Expected baseline (from reading the code)

The listen thread services the socket from `TInetServer.OnIdle`, once per 250 ms `AcceptIdleTimeOut`. Each pass writes
at most one frame. The expected results are:

| Measurement | Expected |
|---|---|
| Outbound throughput | about 4 frames/s (32 frames in about 8 s) |
| Ping→pong with 32 bulk frames queued | about 8 s; the pong arrives after the bulk frames |
| Resume answer (8 frames, idle link) | catchup within about 0.25 s, complete answer in about 2 s |

## Results

| Date | Commit | Throughput (frames/s) | First frame (ms) | Pong (ms) | Bulk frames before pong | Resume catchup (ms) | Resume complete (ms) | Notes |
|---|---|---|---|---|---|---|---|---|
| 2026-10-29 | bbd3789 | 4.0 | 251 | 8261 | 32 | not a number | not a number | `instantfpc Tests/RunAssistantTests.pas --only AssistantMonitorLinkTest`. 32 frames, `total_ms=8013`. Resume delivered 1 of 8 frames, then timed out. The metric line then hit an arithmetic overflow because the answer clock was never set. |
| 2026-11-03 | 901717e | 381.0 | 44 | 0 | 0 | 132 | 132 | Item 4.2. One harness run, `GetTickCount64`. 32 snapshot pages, not plan frames. Pong behind 64 queued pages was 0 ms with none before it. Resume answer clock was set (`answered_ms=6`, timeout path 1 ms). `heard_ms=0` is a same-millisecond delta, not an unset clock. |
| 2026-11-03 | 2fb368c | 470.6 | 27 | 0 | 1 of 120 | 48 | 49 | Item 9.1. FPC 3.3.1, x86_64-linux, `GetTickCount64`, 20 samples. Slice p95 21 ms, state p95 1 ms. See the item 9.1 section. |

Metric lines:

```text
metric throughput frames=32 title_bytes=2000 first_ms=251 total_ms=8013 frames_per_second=4.0
metric ping queued_bulk=32 bulk_before_pong=32 pong_ms=8261
metric resume frames=1 heard_ms=FAIL exception Arithmetic overflow
```

Item 4.2, one run, `GetTickCount64`:

```text
metric throughput frames=32 title_bytes=2000 first_ms=44 total_ms=84 frames_per_second=381.0
metric ping queued_bulk=32 bulk_before_pong=0 pong_ms=0
metric resume frames=8 heard_ms=0 answered_ms=6 catchup_ms=132 complete_ms=132
```

## Item 9.1 catalogue 3 grain

One run of `instantfpc Tests/RunAssistantTests.pas --lazarus-root /home/paul/Projects/FreePascal/Lazarus --only AssistantMonitorLinkTest` on 127.0.0.1. Build: FPC 3.3.1, x86_64-linux. Clock: `GetTickCount64`. Sample count: 20 for slice and state latency. `LinkResumeFrames` is 3: `snapshot_begin`, `snapshot_page`, `snapshot_end`. State frames precede that baseline. The first slice after a quiet period is queued at once; later samples wait out the pump's 20 ms coalesce, then `ObserveTurn` runs through `TThread.Queue`. The form is not in this process. The carrier, the outbox wake, and the link thread are the real ones.

Workloads: 20 one-character appends; 20 state publishes while slices are in flight; 120 snapshot pages totalling 2,409,264 bytes plus an unacked append; a plan file of 4 MiB + 1 byte streamed as `plan_data`; 800 KiB of unacked slices against the 512 KiB credit window (118 events, then quiet); a tail resume; a baseline after the log budget was tightened so the cursor was no longer held.

| Check | p50 | p95 | p99 | Result |
|---|---|---|---|---|
| Mirror change to slice read | 20 ms | 21 ms | 21 ms | under 150 ms |
| Queued state to client read | 0 ms | 1 ms | 1 ms | under 50 ms |
| Ping while 2,409,264 bytes of fetches are queued | 0 ms | | | under 100 ms; 1 frame before pong, not after the queue |
| Ping while `plan_data` for a plan larger than 4 MiB is the bulk traffic | 2 ms | | | under 100 ms; 4 `plan_data` frames before pong, transfer still running |
| Ping while the credit window is full and the client does not ack | 1 ms | | | answered; host stopped at 118 events |
| Resume from a sequence near the head | 62 ms to `resume_ok` | | | tail, no baseline |
| Resume from a sequence the log no longer holds | begin 48 ms, page 49 ms, end 49 ms | | | one baseline, hashes, no historical body |
| Second socket | | | | old link `bye {reason: "replaced"}`, new link `mssAccepted`, no `rejected {reason: "busy"}` |

```text
metric slice samples=20 seen=20 clock=GetTickCount64 coalesce_ms=20 p50=20 p95=21 p99=21
metric state samples=20 seen=20 clock=GetTickCount64 p50=0 p95=1 p99=1
metric 9.1 slices queued=120 bytes=2409264 before_pong=1 pong_ms=0
metric plan_ping plan_before_pong=4 pong_ms=2 clock=GetTickCount64
metric credit events=118 quiet=0 pong_ms=1 clock=GetTickCount64
metric resume_tail frames_ok=True head=0 heard_ms=62 clock=GetTickCount64
metric resume_baseline frames=3 expected=3 begin_ms=48 page_ms=49 end_ms=49 clock=GetTickCount64
metric replace bye=True busy=False state=2
```

Commit `2fb368c`. The same run also printed the older transport lines (`frames_per_second=470.6`, idle 0 ms, priority pong 0 ms with no bulk before it). Those are not the 9.1 budgets.

## Success criteria (item 9.2)

These are the budgets in the plan. A miss is a defect, not a note.

| Criterion | Budget | Measured | Result |
|---|---|---|---|
| IDE change to phone screen while a turn streams | p95 < 150 ms | not measured on a phone. Host first frame is already 251 ms. | Defect |
| Pong while a 2 MiB snapshot is in flight | < 100 ms | not measured on a phone. Host pong behind 32 bulk frames is 8261 ms. | Defect |
| Resume after a 60 s drop, backlog up to 2 MiB | phone shows current state within 1 s | not measured on a phone. Host resume of 8 frames delivered 1 frame and timed out. | Defect |

## Device acceptance (item 9.3)

Not run. `adb devices -l` listed no device on 2026-10-29, and `emulator` is not installed. A host socket test is not a phone and IDE test. Each row stays unchecked until someone runs it on a real phone paired with this IDE.

| Check | Result |
|---|---|
| Pair | Not run |
| Stream a long turn | Not run |
| Airplane mode in the middle of a turn | Not run |
| Kill the app in the middle of a turn | Not run |
| Restart the IDE | Not run |
| Switch History conversations | Not run |
| Approve a tool from the phone during a bulk transfer | Not run |
| Review three conversations offline | Not run |

## On-device trace

Not run. `adb devices -l` listed no device, and `emulator` is not installed. The three traces still required are a 50 000-character streamed answer, a 2 MiB snapshot, and a 60 s Wi-Fi drop. Do not treat the host harness as that trace.
