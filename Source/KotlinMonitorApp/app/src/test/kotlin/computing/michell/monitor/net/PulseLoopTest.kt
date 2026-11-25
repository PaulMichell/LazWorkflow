package computing.michell.monitor.net

/* Pulse loop against a fake clock. Failures retry. Unpaired and pin mismatch do not.
   (c) 2026 Michell Computing. */

import java.util.ArrayDeque
import java.util.Random
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class PulseLoopTest {
  @Test
  fun a503ATimeoutAndAResetEachRetryOnTheSchedule() {
    val source = script(PulseFetch.Status(503), PulseFetch.TimedOut, PulseFetch.Reset, PulseFetch.Ok("e", 1, "{}"))
    val clock = VirtualClock()
    val loop = PulseLoop(source, clock) { 999 }
    try {
      loop.start()
      val expected = longArrayOf(1_000L, 2_000L, 4_000L)
      var step = 0
      var previous = 0L
      for (delay in expected) {
        await("failure ${step + 1}") { scheduledRetry(loop, clock, step + 1, source.calls) }
        val retry = loop.state.value as LinkState.Retrying
        assertEquals(previous + delay, retry.nextAttemptAt)
        assertTrue(clock.now() < retry.nextAttemptAt)
        previous = retry.nextAttemptAt
        clock.advanceTo(retry.nextAttemptAt)
        step += 1
      }
      await("success") { loop.state.value is LinkState.Connected }
      assertEquals(4, source.calls)
    } finally {
      loop.close()
    }
  }

  @Test
  fun aTimeoutAloneUsesTheFirstDelay() {
    assertFirstDelay(PulseFetch.TimedOut)
  }

  @Test
  fun aResetAloneUsesTheFirstDelay() {
    assertFirstDelay(PulseFetch.Reset)
  }

  @Test
  fun aTouchDuringBackoffRetriesAtOnce() {
    nudgeRetriesAtOnce { it.touch() }
  }

  @Test
  fun aForegroundReturnDuringBackoffRetriesAtOnce() {
    nudgeRetriesAtOnce { it.foreground() }
  }

  @Test
  fun aWifiChangeDuringBackoffRetriesAtOnce() {
    nudgeRetriesAtOnce { it.wifiChanged() }
  }

  @Test
  fun aReconnectTapDuringBackoffRetriesAtOnce() {
    nudgeRetriesAtOnce { it.reconnect() }
  }

  @Test
  fun a403StopsUntilANewPairing() {
    val source = script(PulseFetch.Unauthorized(403), PulseFetch.Ok("e", 4, "{}"))
    val clock = VirtualClock()
    val loop = PulseLoop(source, clock) { 999 }
    try {
      loop.start()
      await("unpaired") { loop.state.value is LinkState.Unpaired }
      assertEquals(1, source.calls)
      loop.touch()
      loop.foreground()
      loop.wifiChanged()
      loop.reconnect()
      loop.acceptPin()
      clock.advance(60_000L)
      Thread.sleep(30)
      assertEquals(1, source.calls)
      assertTrue(loop.state.value is LinkState.Unpaired)
      loop.pairedAgain("next-token")
      await("paired") { loop.state.value is LinkState.Connected }
      assertEquals(2, source.calls)
      assertEquals("next-token", source.queries.last().token)
    } finally {
      loop.close()
    }
  }

  @Test
  fun aPinMismatchStopsUntilTheNewPinIsAccepted() {
    val source = script(PulseFetch.PinMismatch, PulseFetch.Ok("e", 2, "{}"))
    val clock = VirtualClock()
    val loop = PulseLoop(source, clock) { 999 }
    try {
      loop.start()
      await("pin") { loop.state.value is LinkState.PinMismatch }
      loop.touch()
      loop.foreground()
      loop.wifiChanged()
      loop.reconnect()
      loop.pairedAgain("still-old")
      clock.advance(60_000L)
      Thread.sleep(30)
      assertEquals(1, source.calls)
      assertTrue(loop.state.value is LinkState.PinMismatch)
      loop.acceptPin()
      await("accepted") { loop.state.value is LinkState.Connected }
      assertEquals(2, source.calls)
    } finally {
      loop.close()
    }
  }

  @Test(timeout = 15_000)
  fun aThousandRandomFailuresThenSuccessReachConnected() {
    val random = Random(20261124L)
    val failures = Array(1000) {
      when (random.nextInt(3)) {
        0 -> PulseFetch.Status(503)
        1 -> PulseFetch.TimedOut
        else -> PulseFetch.Reset
      }
    }
    val source = script(*failures, PulseFetch.Ok("epoch-z", 9, "{}"))
    val clock = VirtualClock()
    val loop = PulseLoop(source, clock) { 999 }
    try {
      loop.start()
      var seen = 0
      while (seen < 1000) {
        await("step $seen") { scheduledRetry(loop, clock, seen + 1, source.calls) }
        val retry = loop.state.value as LinkState.Retrying
        assertTrue(retry.nextAttemptAt > clock.now())
        clock.advanceTo(retry.nextAttemptAt)
        seen += 1
      }
      await("connected") { loop.state.value is LinkState.Connected }
      assertEquals(1001, source.calls)
      assertTrue(loop.state.value !is LinkState.Unpaired)
      assertTrue(loop.state.value !is LinkState.PinMismatch)
    } finally {
      loop.close()
    }
  }

  @Test
  fun aPulseOlderThanTwentySecondsIsNotConnected() {
    val clock = VirtualClock()
    val source = object : PulseSource {
      var calls = 0
      var release = false
      override fun fetch(query: PulseQuery): PulseFetch {
        calls += 1
        if (calls == 1) return PulseFetch.Ok("e", 1, "{}")
        clock.delayUntil(Long.MAX_VALUE) { release }
        return PulseFetch.Ok("e", 2, "{}")
      }
    }
    val loop = PulseLoop(source, clock) { 999 }
    try {
      loop.start()
      await("first pulse") { loop.state.value is LinkState.Connected }
      clock.advanceTo(ConnectedWindowMs)
      Thread.sleep(20)
      assertTrue(loop.state.value is LinkState.Connected)
      clock.advance(1)
      await("stale") { loop.state.value is LinkState.Retrying }
      source.release = true
      clock.wake()
      await("late pulse") { loop.state.value is LinkState.Connected }
    } finally {
      loop.close()
    }
  }

  @Test
  fun thePulseRequestCarriesTheTokenAndMapsStatus() {
    val server = MockWebServer()
    server.start()
    val client = OkHttpClient()
    try {
      server.enqueue(MockResponse().setResponseCode(503).setBody("{\"reason\":\"no_session\"}"))
      server.enqueue(MockResponse().setResponseCode(403).setBody("{\"reason\":\"revoked\"}"))
      server.enqueue(MockResponse().setResponseCode(401).setBody("{\"reason\":\"auth\"}"))
      server.enqueue(MockResponse().setBody("{\"epoch\":\"abc\",\"rev\":12,\"status\":{}}"))
      val url = server.url("/").newBuilder().encodedPath("/").build()
      val base = "http://${server.hostName}:${server.port}/".toHttpUrl()
      val denied = requestPulse(client, base, PulseQuery(0, "", 250, "secret-token"))
      assertTrue(denied is PulseFetch.Status && denied.code == 503)
      val revoked = requestPulse(client, base, PulseQuery(0, "", 250, "secret-token"))
      assertTrue(revoked is PulseFetch.Unauthorized && revoked.code == 403)
      val unknown = requestPulse(client, base, PulseQuery(0, "", 250, "secret-token"))
      assertTrue(unknown is PulseFetch.Unauthorized && unknown.code == 401)
      val ok = requestPulse(client, base, PulseQuery(3, "old", 250, "secret-token"))
      assertTrue(ok is PulseFetch.Ok)
      assertEquals("abc", (ok as PulseFetch.Ok).epoch)
      assertEquals(12L, ok.rev)
      val recorded = server.takeRequest()
      assertEquals("/v4/pulse?after=0&epoch=&interval=250", recorded.path)
      assertEquals("Bearer secret-token", recorded.getHeader("Authorization"))
      assertEquals(url.host, server.hostName)
    } finally {
      client.dispatcher.executorService.shutdown()
      server.shutdown()
    }
  }

  @Test
  fun jitterStaysOnTheSchedule() {
    assertEquals(1_000L, pulseRetryDelayMs(0, 999))
    assertEquals(500L, pulseRetryDelayMs(0, 0))
    assertEquals(2_000L, pulseRetryDelayMs(1, 999))
    assertEquals(4_000L, pulseRetryDelayMs(2, 999))
    assertEquals(8_000L, pulseRetryDelayMs(3, 999))
    assertEquals(15_000L, pulseRetryDelayMs(4, 0))
    assertEquals(15_000L, pulseRetryDelayMs(80, 999))
    assertEquals(PulseFetch.PinMismatch, classifyPulseFailure(PinMismatchException("aa")))
    assertEquals(PulseFetch.Reset, classifyPulseFailure(java.net.SocketException("Connection reset")))
    assertEquals(PulseFetch.TimedOut, classifyPulseFailure(java.net.SocketTimeoutException("timed out")))
  }

  private fun assertFirstDelay(failure: PulseFetch) {
    val source = script(failure, PulseFetch.Ok("e", 1, "{}"))
    val clock = VirtualClock()
    val loop = PulseLoop(source, clock) { 999 }
    try {
      loop.start()
      await(failure.toString()) { scheduledRetry(loop, clock, 1, source.calls) }
      assertEquals(1_000L, (loop.state.value as LinkState.Retrying).nextAttemptAt)
      val at = (loop.state.value as LinkState.Retrying).nextAttemptAt
      clock.advanceTo(at - 1)
      Thread.sleep(30)
      assertEquals(1, source.calls)
      clock.advanceTo(at)
      await("retried now=${clock.now()} state=${loop.state.value} calls=${source.calls}") { source.calls == 2 }
    } finally {
      loop.close()
    }
  }

  private fun nudgeRetriesAtOnce(nudge: (PulseLoop) -> Unit) {
    val source = script(PulseFetch.Status(503), PulseFetch.Ok("e", 1, "{}"))
    val clock = VirtualClock()
    val loop = PulseLoop(source, clock) { 999 }
    try {
      loop.start()
      await("backoff") { scheduledRetry(loop, clock, 1, source.calls) }
      val retry = loop.state.value as LinkState.Retrying
      assertEquals(1_000L, retry.nextAttemptAt)
      nudge(loop)
      await("immediate") { loop.state.value is LinkState.Connected }
      assertEquals(0L, clock.now())
      assertEquals(2, source.calls)
    } finally {
      loop.close()
    }
  }
}

private class ScriptedPulse(private val script: ArrayDeque<PulseFetch>) : PulseSource {
  var calls = 0
    private set
  val queries = ArrayList<PulseQuery>()

  override fun fetch(query: PulseQuery): PulseFetch {
    synchronized(this) {
      while (script.isEmpty()) (this as Object).wait()
      calls += 1
      queries.add(query)
      return script.removeFirst()
    }
  }
}

private fun script(vararg steps: PulseFetch): ScriptedPulse {
  return ScriptedPulse(ArrayDeque(steps.toList()))
}

private fun scheduledRetry(loop: PulseLoop, clock: VirtualClock, calls: Int, seen: Int): Boolean {
  val phase = loop.state.value
  return seen >= calls && phase is LinkState.Retrying && phase.nextAttemptAt > clock.now()
}

private fun await(label: String, condition: () -> Boolean) {
  val deadline = System.nanoTime() + 3_000_000_000L
  while (!condition()) {
    if (System.nanoTime() > deadline) fail("timed out waiting for $label")
    Thread.sleep(1)
  }
}
