package computing.michell.monitor.connection

/* Writer priority and heartbeat timing (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.MonitorLimits
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

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
  fun silencePingsAndADeadPeerCloses() {
    assertEquals(HeartbeatStep.None, heartbeatStep(0L, 0L, MonitorLimits.HeartbeatSilenceMs - 1))
    assertEquals(HeartbeatStep.Ping, heartbeatStep(0L, 0L, MonitorLimits.HeartbeatSilenceMs))
    assertEquals(HeartbeatStep.None, heartbeatStep(9_000L, 0L, 10_000L))
    assertEquals(HeartbeatStep.Close, heartbeatStep(0L, 0L, MonitorLimits.DeadSessionMs))
  }
}