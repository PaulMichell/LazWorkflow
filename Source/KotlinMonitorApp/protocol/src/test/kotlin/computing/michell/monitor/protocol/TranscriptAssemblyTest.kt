package computing.michell.monitor.protocol

/* Fragment assembly without a device (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TranscriptAssemblyTest {
  @Test
  fun firstAppearanceOrderSurvivesALaterFrame() {
    val thinking = fragment("thinking", "think-1", "head", 1, 2, 1)
    val answer = fragment("answer", "answer-1", "done", 1, 1, 0)
    val tail = fragment("thinking", "think-1", "tail", 2, 2, 1)
    val assembled = assembleTranscriptBlocks(listOf(listOf(thinking, answer), listOf(tail)))
    assertEquals(listOf("thinking", "answer"), assembled.map { it.kind })
    assertEquals("headtail", assembled[0].body)
    assertEquals("done", assembled[1].body)
  }

  @Test
  fun missingPartHoldsTheTailAndADuplicateIsKeptOnce() {
    val tail = fragment("thinking", "think-1", "TAIL", 2, 2, 1)
    assertTrue(assembleTranscriptBlocks(listOf(listOf(tail))).isEmpty())
    val head = fragment("thinking", "think-1", "head", 1, 2, 1)
    val duplicate = fragment("thinking", "think-1", "HEAD", 1, 2, 1)
    val assembled = assembleTranscriptBlocks(listOf(listOf(head, duplicate, tail)))
    assertEquals("headTAIL", assembled.single().body)
  }

  @Test
  fun inconsistentPartCountDropsThatBlock() {
    val head = fragment("thinking", "think-1", "one", 1, 2, 1)
    val tail = fragment("thinking", "think-1", "two", 2, 3, 1)
    val answer = fragment("answer", "answer-1", "kept", 1, 1, 0)
    val assembled = assembleTranscriptBlocks(listOf(listOf(head, answer), listOf(tail)))
    assertEquals(listOf("kept"), assembled.map { it.body })
  }

  @Test
  fun higherRevisionReplacesTheOldBody() {
    val old = fragment("thinking", "think-1", "old-body", 1, 1, 1)
    val newer = fragment("thinking", "think-1", "new-body", 1, 1, 2)
    val answer = fragment("answer", "answer-1", "kept", 1, 1, 0)
    val assembled = assembleTranscriptBlocks(listOf(listOf(old, answer, newer)))
    assertEquals(listOf("new-body", "kept"), assembled.map { it.body })
    assertFalse(assembled.any { it.body.contains("old-body") })
  }
}

private fun fragment(kind: String, id: String, body: String, part: Int, partCount: Int, revision: Int): WireBlock {
  return WireBlock(kind, id, "", "", "", body, false, true, 0, emptyList(), false, part, partCount, revision)
}
