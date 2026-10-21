package computing.michell.monitor.ui

/* Fold-block identity without Compose (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.WireBlock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Test

class FoldBlockKeyTest {
  @Test
  fun appendingAndATitleChangeKeepTheKey() {
    val block = WireBlock("thinking", "think-1", "Thinking", "", "", "Hel", true, true, 0, emptyList())
    val appended = block.copy(body = block.body + "lo")
    val finished = appended.copy(title = "Finished", running = false)
    val started = foldBlockKey(4, "turn-1", block.blockId, 0)
    assertEquals(started, foldBlockKey(4, "turn-1", appended.blockId, 0))
    assertEquals(started, foldBlockKey(4, "turn-1", finished.blockId, 0))
    assertFalse(started.contains(block.body))
    assertFalse(started.contains(appended.body))
    assertFalse(started.contains(block.title))
    assertFalse(started.contains(finished.title))
    assertNotEquals(started, foldBlockKey(4, "turn-1", "think-2", 0))
    assertNotEquals(started, foldBlockKey(5, "turn-1", block.blockId, 0))
    assertNotEquals(started, foldBlockKey(4, "turn-2", block.blockId, 0))
  }

  @Test
  fun emptyBlockIdUsesTheAssembledIndexNotTheText() {
    val block = WireBlock("thinking", "", "Thinking", "", "", "alpha", true, true, 0, emptyList())
    val appended = block.copy(body = "alpha beta", title = "Done")
    val key = foldBlockKey(4, "turn-1", block.blockId, 2)
    assertEquals(key, foldBlockKey(4, "turn-1", appended.blockId, 2))
    assertNotEquals(key, foldBlockKey(4, "turn-1", "", 3))
    assertNotEquals(key, foldBlockKey(4, "turn-1", "2", 0))
    assertFalse(key.contains("alpha"))
    assertFalse(key.contains("beta"))
    assertFalse(key.contains("Done"))
    assertFalse(key.contains("Thinking"))
  }
}
