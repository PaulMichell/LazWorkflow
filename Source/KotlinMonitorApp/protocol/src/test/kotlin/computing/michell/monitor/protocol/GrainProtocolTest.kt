package computing.michell.monitor.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class GrainProtocolTest {
  @Test
  fun desktopBlockCloseWithoutDurationAdvancesTheEventStream() {
    val payload = """{"conversation_id":"chat","stream_id":"stream","seq":11586,"event":"block_close","data":{"block_id":"block","state":"ok"}}"""
    val frame = decodeSyncEnvelope("""{"v":3,"id":"close","type":"event","payload":$payload}""") as SyncFrame.Event
    val closed = frame.event as MonitorEvent.BlockClose
    assertEquals(11586L, closed.seq)
    assertEquals("block", closed.blockId)
    assertEquals(0, closed.durationMs)
  }

  @Test
  fun retiredContentKindsAreUnknown() {
    for (kind in listOf("snapshot", "transcript", "turn_data", "patch", "catchup")) {
      val frame = """{"v":3,"id":"retired","type":"$kind","payload":{}}"""
      val decoded = tryDecodeEnvelope(frame)
      assertEquals(UnknownTypeReason, decoded.message.reason)
      assertFalse(decoded.message.changesState)
    }
  }

  @Test
  fun catalogueTwoIsRejected() {
    val decoded = tryDecodeEnvelope("""{"v":2,"id":"old","type":"hello","payload":{}}""")
    assertFalse(decoded.ok)
  }
}
