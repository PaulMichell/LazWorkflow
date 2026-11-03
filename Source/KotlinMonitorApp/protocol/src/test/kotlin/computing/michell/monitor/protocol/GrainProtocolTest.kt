package computing.michell.monitor.protocol

/* Grain the hybrid still applies as a patch. Green at item 7.1.
   Do not weaken these assertions to match today's wire. (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class GrainProtocolTest {
  @Test
  fun aPatchIsNotOfferedToTheScreen() {
    val kept = block("answer", "b-1", "kept")
    val start = PhoneScreen(epoch = "aa", turns = listOf(turn("Shown", listOf(kept))), live = turn("Shown", listOf(kept)))
    val next = applyPhonePatch(start, patch("aa", 1, listOf(block("answer", "b-1", "changed")), 1, 1))
    assertEquals("7.1 a patch is not offered to SyncApplier or the screen", "kept", next.live?.blocks?.single()?.body)
  }

  @Test
  fun anEmptySnapshotPageIsNotAConversationReplace() {
    val kept = block("answer", "b-1", "kept")
    val start = PhoneScreen(epoch = "aa", turns = listOf(turn("Shown", listOf(kept))), live = turn("Shown", listOf(kept)))
    val emptied = applyPhoneCatchup(start, "bb", 0, "c1", "/work", "Empty", emptyList(), null)
    assertFalse("7.1 an empty snapshot page is not a conversation replace", emptied.turns.isEmpty())
    assertEquals("7.1 an empty page does not become the conversation", "kept", emptied.turns.single().blocks.single().body)
  }
}

private fun block(kind: String, id: String, body: String): WireBlock {
  return WireBlock(kind, id, "", "", "", body, false, true, 0, emptyList())
}

private fun turn(preview: String, blocks: List<WireBlock>): WireTurn {
  return WireTurn(1, "turn-1", "build", "", preview, "", blocks = blocks)
}

private fun patch(epoch: String, cursor: Long, blocks: List<WireBlock>, part: Int, partCount: Int): WirePatch {
  return WirePatch(epoch, cursor, 1, "turn-1", blocks, false, false, false, "idle", true, false, false, 0, part, partCount)
}
