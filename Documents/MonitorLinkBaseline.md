# Monitor link baseline

Measurements of the `LazAssistantMonitor` LAN link, taken by `Tests/AssistantMonitorLinkTest.lpr` (plan item 2.1 of
`Documents/Plan-20261029-035918.md`). Items 3.3 and 9.2 re-run the same harness and add their rows here.

## How the harness measures

The test starts a real `TMonitorLanCarrier` and `TMonitorSession` on 127.0.0.1 with a throwaway certificate under a
temporary settings directory. An OpenSSL client socket connects and pairs on the open-LAN path (no code armed). The test
then reads the link in three phases, all on the same connection:

1. **Throughput.** 32 bulk `plan` frames (2000-byte title each) go through `TryQueueHostJson` and `DrainOutbound`, as
   the bridge queues them. The test times how long the client takes to receive all 32. The rate is
   `frames / (last frame − queue time)`.
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
| 2026-10-29 | baseline | not yet measured | | | | | | The harness was written in a session that could not compile or run it. Run the command above and fill in this row. |
