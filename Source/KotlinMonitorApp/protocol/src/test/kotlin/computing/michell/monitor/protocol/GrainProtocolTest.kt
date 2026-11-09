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
  fun anOutlineBlockCarriesItsTitleAndASmallBody() {
    val blocks = """[{"block_id":"b1","kind":"thinking","title":"Thinking","state":"ok","revision":1,"body_bytes":8,""" +
      """"hash":"${prefixHash("Thought.")}","body":"Thought."},""" +
      """{"block_id":"b2","kind":"tool","title":"read_file A.pas","state":"ok","revision":1,"body_bytes":9000,"hash":"0"}]"""
    val payload = """{"conversation_id":"c","stream_id":"s","seq":4,"page":1,"page_count":1,""" +
      """"turns":[{"turn_id":"t","turn_index":0,"prompt_preview":"p","blocks":$blocks}]}"""
    val page = decodeSyncEnvelope("""{"v":3,"id":"p1","type":"snapshot_page","payload":$payload}""") as SyncFrame.SnapshotPage
    val parsed = page.turns.single().blocks
    assertEquals("Thinking", parsed[0].title)
    assertEquals("Thought.", parsed[0].body)
    assertEquals("read_file A.pas", parsed[1].title)
    assertEquals(null, parsed[1].body)
  }

  @Test
  fun catalogueTwoIsRejected() {
    val decoded = tryDecodeEnvelope("""{"v":2,"id":"old","type":"hello","payload":{}}""")
    assertFalse(decoded.ok)
  }
}
