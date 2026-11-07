package computing.michell.monitor.protocol

/* Phone mirror cases. No Android runner and no open socket. (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneMirrorTest {

  @Test
  fun anAckWaits250MillisecondsForTheNewestSeq() {
    val first = paceAck(AckPace(), 1000, "ack-1", "conversation-a", "ab12cd34", 4)
    assertTrue(first.sendNow.contains("\"seq\" : 4"))
    assertEquals(0L, first.laterMs)
    val soon = paceAck(first.pace, 1100, "ack-2", "conversation-a", "ab12cd34", 5)
    assertEquals("", soon.sendNow)
    assertEquals(150L, soon.laterMs)
    assertTrue(soon.sendLater.contains("\"seq\" : 5"))
    val later = paceAck(first.pace, 1250, "ack-3", "conversation-a", "ab12cd34", 6)
    assertTrue(later.sendNow.contains("\"seq\" : 6"))
  }







  /** Plan item 2.2 pins today's behaviour. Item 3.1 changes it, and this case is then rewritten. */
}

private fun block(kind: String, id: String, body: String): WireBlock {
  return WireBlock(kind, id, "", "", "", body, false, true, 0, emptyList())
}

private fun turn(preview: String, blocks: List<WireBlock>): WireTurn {
  return WireTurn(1, "turn-1", "build", "", preview, "", blocks = blocks)
}


