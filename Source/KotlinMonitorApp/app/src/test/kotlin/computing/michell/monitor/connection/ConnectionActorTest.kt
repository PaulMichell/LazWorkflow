package computing.michell.monitor.connection

/* Writer priority and heartbeat timing (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.MonitorEvent
import computing.michell.monitor.protocol.MonitorLimits
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
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
  fun silencePingsAndADeadPeerCloses() {
    assertEquals(HeartbeatStep.None, heartbeatStep(0L, 0L, MonitorLimits.HeartbeatSilenceMs - 1))
    assertEquals(HeartbeatStep.Ping, heartbeatStep(0L, 0L, MonitorLimits.HeartbeatSilenceMs))
    assertEquals(HeartbeatStep.None, heartbeatStep(9_000L, 0L, 10_000L))
    assertEquals(HeartbeatStep.Close, heartbeatStep(0L, 0L, MonitorLimits.DeadSessionMs))
  }
}
