package computing.michell.monitor.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class GrainProtocolTest {
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
