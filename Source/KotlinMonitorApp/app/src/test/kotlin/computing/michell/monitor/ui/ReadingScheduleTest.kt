package computing.michell.monitor.ui

/* Reading position and the history it is allowed to ask for (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTurn
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReadingScheduleTest {
  @Test
  fun firstLayoutAndProgrammaticTailAreNotAHistoryScroll() {
    assertTrue(followAfterMotion(true, userScrolling = true, atEnd = false, programmatic = true))
    assertFalse(followAfterMotion(true, userScrolling = true, atEnd = false, programmatic = false))
    val head = readingDemand(true, setOf(0, 1, 2), 8, 12)
    assertTrue(head.followingHead)
    assertEquals(emptySet<Int>(), head.visible)
    assertEquals(8, head.anchorIndex)
    val browsing = readingDemand(false, setOf(1, -2), 1, 4)
    assertEquals(setOf(1), browsing.visible)
    assertFalse(browsing.followingHead)
  }

  @Test
  fun anArrivingBodyKeepsTheRowTheReaderHad() {
    val rows = listOf(
      ConversationRow("older", "t0", 0, null, "older"),
      ConversationRow("kept", "t1", 1, null, "kept")
    )
    assertEquals(1 to 20, retainedAnchor(rows, "kept", 20))
    assertNull(retainedAnchor(rows, "gone", 4))
  }

  @Test
  fun aDiscardedHistoryResultDoesNotRepaintTheHead() {
    val cached = turn(0, "cached")
    val late = turn(0, "late")
    val shown = BoardContent("host", "c1", listOf(cached))
    val incoming = BoardContent("host", "c1", listOf(late), revision = 2)
    val held = boardForReader(true, incoming, shown, setOf("b-0"), emptySet())
    assertEquals("cached", held.turns.single().blocks.single().body)
    val shownAgain = boardForReader(false, incoming, shown, setOf("b-0"), emptySet())
    assertEquals("late", shownAgain.turns.single().blocks.single().body)
    val omitted = boardForReader(true, incoming, BoardContent("host", "c1"), emptySet(), setOf(0))
    assertTrue(omitted.turns.isEmpty())
  }

  private fun turn(index: Int, body: String): WireTurn {
    val block = WireBlock("answer", "b-$index", "", "", "", body, false, true, 0, emptyList())
    return WireTurn(index, "t-$index", "build", "", body, "", blocks = listOf(block))
  }
}
