package computing.michell.monitor.connection

/* Writer priority and heartbeat timing (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.MonitorEvent
import computing.michell.monitor.protocol.MonitorLimits
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

private fun event(seq: Long): MonitorEvent {
  return MonitorEvent.TurnOpen("c", "s", seq, "t$seq", seq.toInt(), "build", "prompt", "")
}

class ConnectionActorTest {
  @Test
  fun theWriterSendsControlBeforeCommandsAndAcks() = runBlocking {
    val written = mutableListOf<String>()
    val writer = ConnectionWriter { bytes ->
      written += bytes.toString(Charsets.UTF_8)
      true
    }
    writer.offerAck("ack".toByteArray())
    writer.offerCommand("command".toByteArray())
    writer.offerControl("control".toByteArray())
    writer.close()
    writer.run()
    assertEquals(listOf("control", "command", "ack"), written)
  }

  @Test
  fun anOfferWakesTheWriterAndALaterControlPreemptsTheBurst() = runBlocking {
    val written = mutableListOf<String>()
    val started = kotlinx.coroutines.CompletableDeferred<Unit>()
    val release = kotlinx.coroutines.CompletableDeferred<Unit>()
    var held = false
    val writer = ConnectionWriter { bytes ->
      val text = bytes.toString(Charsets.UTF_8)
      if (!held && text.startsWith("command")) {
        held = true
        started.complete(Unit)
        release.await()
      }
      synchronized(written) { written += text }
      true
    }
    val job = launch { writer.run() }
    try {
      delay(50)
      assertTrue(writer.offerCommand("command-0".toByteArray()))
      withTimeout(1_000) { started.await() }
      assertEquals(1L, writer.wakeCount)
      repeat(4) { index -> assertTrue(writer.offerCommand("command-${index + 1}".toByteArray())) }
      assertTrue(writer.offerControl("control".toByteArray()))
      release.complete(Unit)
      withTimeout(1_000) {
        while (synchronized(written) { written.size } < 6) yield()
      }
      val order = synchronized(written) { written.toList() }
      assertEquals("command-0", order[0])
      assertEquals("control", order[1])
    } finally {
      writer.close()
      job.cancel()
    }
  }

  @Test
  fun aFullWindowHoldsTheNextEventUntilTheEarlierOnesDrain() = runBlocking {
    val events = AccountedEvents(budgetBytes = 100)
    val first = event(1)
    val second = event(2)
    val held = event(3)
    assertEquals(CreditOffer.Queued, events.offer(first, 60))
    assertEquals(CreditOffer.Queued, events.offer(second, 40))
    assertEquals(CreditOffer.Held, events.offer(held, 30))
    assertEquals(listOf(held), events.heldEvents())
    assertEquals(first, events.receive())
    assertEquals(second, events.receive())
    assertTrue(events.heldEvents().isEmpty())
    assertEquals(held, events.receive())
  }

  @Test
  fun anEventLargerThanTheBudgetIsRejectedAndDoesNotPauseForever() = runBlocking {
    val events = AccountedEvents(budgetBytes = 100)
    assertEquals(CreditOffer.Rejected, events.offer(event(1), 101))
    assertFalse(events.shouldPauseRead())
    assertEquals(CreditOffer.Queued, events.offer(event(2), 40))
    assertEquals(event(2), events.receive())
  }

  @Test
  fun aFullWriterLaneRejectsTheNextControlFrame() {
    val writer = ConnectionWriter(capacity = 2) { true }
    assertTrue(writer.offerControl("one".toByteArray()))
    assertTrue(writer.offerControl("two".toByteArray()))
    assertFalse(writer.offerControl("three".toByteArray()))
    writer.close()
  }

  @Test
  fun aCreditPauseDoesNotTreatSilenceAsADeadPeer() {
    assertEquals(HeartbeatStep.None, heartbeatWhileCreditPaused(HeartbeatStep.None, 0L, 1_000L))
    assertEquals(HeartbeatStep.Ping, heartbeatWhileCreditPaused(HeartbeatStep.Close, 0L, MonitorLimits.HeartbeatSilenceMs))
    assertEquals(
      HeartbeatStep.None,
      heartbeatWhileCreditPaused(HeartbeatStep.Close, 0L, MonitorLimits.HeartbeatSilenceMs - 1)
    )
  }

  @Test
  fun silencePingsAndADeadPeerCloses() {
    assertEquals(HeartbeatStep.None, heartbeatStep(0L, 0L, MonitorLimits.HeartbeatSilenceMs - 1))
    assertEquals(HeartbeatStep.Ping, heartbeatStep(0L, 0L, MonitorLimits.HeartbeatSilenceMs))
    assertEquals(HeartbeatStep.None, heartbeatStep(9_000L, 0L, 10_000L))
    assertEquals(HeartbeatStep.Close, heartbeatStep(0L, 0L, MonitorLimits.DeadSessionMs))
  }
}
