package computing.michell.monitor.data

/* Retention: pinned rows stay, and images leave oldest first (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Test

class RetentionTest {
  @Test
  fun pinnedConversationsStayAndOnlyTheNewestUnpinnedFitTheCap() {
    val rows = listOf(
      conversation("pinned-old", pinned = true, updatedAt = 1L),
      conversation("old", pinned = false, updatedAt = 2L),
      conversation("mid", pinned = false, updatedAt = 3L),
      conversation("new", pinned = false, updatedAt = 4L)
    )
    val dropped = conversationsToDrop(rows, 2)
    assertEquals(listOf("old"), dropped.map { it.id })
  }

  @Test
  fun imagesOverTheBudgetLeaveOldestFirst() {
    val images = listOf(
      AgedImage("h", "c", "new", "new.png", 30L, 40L),
      AgedImage("h", "c", "old", "old.png", 10L, 50L),
      AgedImage("h", "c", "mid", "mid.png", 20L, 50L)
    )
    val dropped = imagesToDrop(images, 80L)
    assertEquals(listOf("old", "mid"), dropped.map { it.imageId })
    assertEquals(emptyList<String>(), imagesToDrop(images, DefaultImageBudgetBytes).map { it.imageId })
  }

  private fun conversation(id: String, pinned: Boolean, updatedAt: Long): ConversationRecord {
    return ConversationRecord(id, "host", "/work", id, "", 0L, updatedAt, pinned)
  }
}
