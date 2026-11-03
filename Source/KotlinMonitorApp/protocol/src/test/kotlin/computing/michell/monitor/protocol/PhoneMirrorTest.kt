package computing.michell.monitor.protocol

/* Phone mirror cases. No Android runner and no open socket. (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneMirrorTest {
  @Test
  fun aPatchDoesNotChangeTheScreen() {
    val kept = block("thinking", "think-1", "kept")
    val answer = block("answer", "answer-1", "old")
    val shown = turn("Shown", listOf(kept, answer))
    val start = PhoneScreen(epoch = "aa", turns = listOf(shown), live = shown)
    val next = applyPhonePatch(start, patch("aa", 1, listOf(block("answer", "answer-1", "new")), 1, 1))
    assertEquals(start, next)
  }

  @Test
  fun anAckWaits250MillisecondsForTheNewestSeq() {
    val first = paceAck(AckPace(), 1000, "ack-1", "conversation-a", "ab12cd34", 4)
    assertTrue(first.sendNow.contains("\"seq\":4"))
    assertEquals(0L, first.laterMs)
    val soon = paceAck(first.pace, 1100, "ack-2", "conversation-a", "ab12cd34", 5)
    assertEquals("", soon.sendNow)
    assertEquals(150L, soon.laterMs)
    assertTrue(soon.sendLater.contains("\"seq\":5"))
    val later = paceAck(first.pace, 1250, "ack-3", "conversation-a", "ab12cd34", 6)
    assertTrue(later.sendNow.contains("\"seq\":6"))
  }

  @Test
  fun aThinkingAppendGrowsTheOpenThought() {
    val start = PhoneScreen(epoch = "aa", live = turn("Shown", listOf(block("thinking", "think-1", "The ").copy(running = true))))
    val grown = applyPhonePatch(start, patch("aa", 1, listOf(block("thinking", "think-1", "request.").copy(running = true, appendOffset = 4)), 1, 1))
    assertEquals(start, grown)
  }

  @Test
  fun anAppendOffsetMustMatchTheStoredUtf8Length() {
    val start = PhoneScreen(epoch = "aa", live = turn("Shown", listOf(block("answer", "answer-1", "Größe → "))))
    val grown = applyPhonePatch(start, patch("aa", 1, listOf(block("answer", "answer-1", "10 s.").copy(appendOffset = 12)), 1, 1))
    assertEquals(start, grown)
  }

  @Test
  fun anIncompletePartSetDoesNotAdvanceTheCursor() {
    val start = PhoneScreen(epoch = "aa", live = turn("Shown", listOf(block("answer", "answer-1", "old"))))
    val partial = applyPhonePatch(start, patch("aa", 1, listOf(block("answer", "answer-1", "one")), 1, 2))
    assertEquals(start, partial)
  }

  @Test
  fun aLowerCursorInTheSameEpochDoesNotChangeTheScreen() {
    val shown = turn("Shown", listOf(block("answer", "answer-1", "kept"), block("thinking", "think-1", "also")))
    val start = PhoneScreen(epoch = "aa", cursor = 4, turns = listOf(shown), live = shown)
    val lower = applyPhonePatch(start, patch("aa", 3, listOf(block("answer", "answer-1", "old")), 1, 1))
    assertEquals(start.cursor, lower.cursor)
    assertEquals(start.turns, lower.turns)
    assertEquals(start.live, lower.live)
  }

  @Test
  fun aNewEpochKeepsTurnsUntilCatchupReplacesThem() {
    val shown = turn("Shown", listOf(block("answer", "answer-1", "kept")))
    val start = PhoneScreen(epoch = "aa", cursor = 4, turns = listOf(shown), live = shown)
    val announced = applyPhonePatch(start, patch("bb", 1, listOf(block("answer", "answer-1", "hidden")), 1, 1))
    assertEquals(start, announced)
    val replaced = applyPhoneCatchup(announced, "bb", 0, "conversation-2", "/work", "New", emptyList(), null)
    assertEquals(start, replaced)
  }

  @Test
  fun closedThenANewEpochFilesTheIdAndShowsEmptyOnlyAfterCatchup() {
    val shown = turn("Shown", listOf(block("answer", "answer-1", "kept")))
    val start = PhoneScreen(epoch = "aa", cursor = 4, conversationId = "current", turns = listOf(shown), live = shown)
    val closed = notePhoneClosed(start, "conversation-1", "Archived")
    assertEquals("conversation-1", closed.closedId)
    assertEquals("", closed.fileClosedId)
    assertEquals(listOf(shown), closed.turns)
    val epoch = notePhoneEpoch(closed, "bb")
    assertEquals("conversation-1", epoch.fileClosedId)
    assertEquals("Archived", epoch.closedTitle)
    assertEquals(listOf(shown), epoch.turns)
    assertEquals(shown, epoch.live)
    val empty = applyPhoneCatchup(epoch, "bb", 0, "current", "/work", "", emptyList(), null)
    assertEquals(listOf(shown), empty.turns)
    assertEquals(shown, empty.live)
  }

  /** Plan item 2.2 pins today's behaviour. Item 3.1 changes it, and this case is then rewritten. */
  @Test
  fun aCursorGapIgnoresEveryLaterPatchUntilACatchup() {
    val start = PhoneScreen()
    val screen = applyPhonePatch(start, patch("aa", 1, listOf(block("answer", "answer-1", "first")), 1, 1))
    assertEquals(start, screen)
    val later = applyPhonePatch(screen, patch("aa", 3, listOf(block("answer", "answer-1", "after the gap")), 1, 1))
    assertEquals(start, later)
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


