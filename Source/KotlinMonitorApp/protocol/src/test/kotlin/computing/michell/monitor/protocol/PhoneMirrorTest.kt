package computing.michell.monitor.protocol

/* Phone mirror cases. No Android runner and no open socket. (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneMirrorTest {
  @Test
  fun aPatchUpdatesOneBlockAndLeavesTheOthers() {
    val kept = block("thinking", "think-1", "kept")
    val answer = block("answer", "answer-1", "old")
    val shown = turn("Shown", listOf(kept, answer))
    val start = PhoneScreen(epoch = "aa", turns = listOf(shown), live = shown)
    val next = applyPhonePatch(start, patch("aa", 1, listOf(block("answer", "answer-1", "new")), 1, 1))
    assertEquals(1L, next.cursor)
    assertEquals(listOf("kept", "new"), next.live?.blocks?.map { it.body })
    assertEquals("Shown", next.turns[0].promptPreview)
  }

  @Test
  fun anAppendOffsetMustMatchTheStoredUtf8Length() {
    val start = PhoneScreen(epoch = "aa", live = turn("Shown", listOf(block("answer", "answer-1", "Größe → "))))
    val grown = applyPhonePatch(start, patch("aa", 1, listOf(block("answer", "answer-1", "10 s.").copy(appendOffset = 12)), 1, 1))
    assertEquals("Größe → 10 s.", grown.live?.blocks?.single()?.body)
    assertEquals(emptyList<String>(), grown.blockFetchIds)
    val mismatch = applyPhonePatch(start, patch("aa", 1, listOf(block("answer", "answer-1", "guess").copy(appendOffset = 3)), 1, 1))
    assertEquals("Größe → ", mismatch.live?.blocks?.single()?.body)
    assertEquals(listOf("answer-1"), mismatch.blockFetchIds)
    val repaired = applyBlockData(mismatch, "answer-1", 0, "Größe → 10 s.")
    assertEquals("Größe → 10 s.", repaired.live?.blocks?.single()?.body)
    assertEquals(emptyList<String>(), repaired.blockFetchIds)
  }

  @Test
  fun anIncompletePartSetDoesNotAdvanceTheCursor() {
    val start = PhoneScreen(epoch = "aa", live = turn("Shown", listOf(block("answer", "answer-1", "old"))))
    val partial = applyPhonePatch(start, patch("aa", 1, listOf(block("answer", "answer-1", "one")), 1, 2))
    assertEquals(0L, partial.cursor)
    assertEquals("one", partial.live?.blocks?.single()?.body)
    val done = applyPhonePatch(partial, patch("aa", 1, listOf(block("answer", "answer-1", "two")), 2, 2))
    assertEquals(1L, done.cursor)
    assertEquals("onetwo", done.live?.blocks?.single()?.body)
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
    assertTrue(announced.catchingUp)
    assertEquals("aa", announced.epoch)
    assertEquals(listOf(shown), announced.turns)
    assertEquals(shown, announced.live)
    val replaced = applyPhoneCatchup(announced, "bb", 0, "conversation-2", "/work", "New", emptyList(), null)
    assertEquals("bb", replaced.epoch)
    assertFalse(replaced.catchingUp)
    assertTrue(replaced.turns.isEmpty())
    assertNull(replaced.live)
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
    assertTrue(empty.turns.isEmpty())
    assertNull(empty.live)
    assertEquals("", empty.fileClosedId)
  }

  @Test
  fun twoSavedConversationsLoadWhileTheSocketStubIsDisconnected() {
    val library = MemoryConversationLibrary()
    val one = document("First")
    val two = document("Second")
    val other = document("Other host")
    library.save(entry("aa", "/work/One", "conversation-1", "c-one.json"), one)
    library.save(entry("aa", "/work/Two", "conversation-2", "c-two.json"), two)
    library.save(entry("bb", "/work/One", "conversation-1", "c-other.json"), other)
    val socket = DisconnectedSocket()
    assertFalse(socket.opened)
    assertEquals("First", library.load("aa", "conversation-1", socket)?.draft)
    assertEquals("Second", library.load("aa", "conversation-2", socket)?.draft)
    assertFalse(socket.opened)
    library.forgetFingerprint("aa")
    assertNull(library.load("aa", "conversation-1", socket))
    assertNull(library.load("aa", "conversation-2", socket))
    assertEquals("Other host", library.load("bb", "conversation-1", socket)?.draft)
    assertEquals(setOf("bb"), library.fingerprints())
    assertFalse(socket.opened)
  }

  /** Plan item 2.2 pins today's behaviour. Item 3.1 changes it, and this case is then rewritten. */
  @Test
  fun aCursorGapIgnoresEveryLaterPatchUntilACatchup() {
    var screen = applyPhonePatch(PhoneScreen(), patch("aa", 1, listOf(block("answer", "answer-1", "first")), 1, 1))
    assertEquals(1L, screen.cursor)
    screen = applyPhonePatch(screen, patch("aa", 3, listOf(block("answer", "answer-1", "after the gap")), 1, 1))
    assertTrue(screen.resumeOnce)
    var raised = 0
    for (cursor in 4L..41L) {
      val before = screen.resumeOnce
      screen = applyPhonePatch(screen, patch("aa", cursor, listOf(block("answer", "answer-1", "streamed $cursor")), 1, 1))
      if (!before && screen.resumeOnce) raised += 1
    }
    assertEquals(0, raised)
    assertTrue(screen.resumeOnce)
    assertEquals(1L, screen.cursor)
    assertEquals("first", screen.live?.blocks?.single()?.body)
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

private fun document(draft: String): OfflineCacheDocument {
  return OfflineCacheDocument(emptyList(), emptyList(), null, "", "", emptyList(), -1, draft)
}

private fun entry(fingerprint: String, projectRoot: String, conversationId: String, fileName: String): CacheIndexEntry {
  return CacheIndexEntry(fingerprint, projectRoot, conversationId, conversationId, 1L, 1, fileName)
}
