package computing.michell.monitor.data

/* Retention removes the oldest cache rows and keeps the current conversation
   and unsent commands (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Test

class RetentionTest {
  @Test
  fun oldestConversationsAndImagesGoAndCurrentAndUnsentStay() {
    val database = openTestDatabase()
    try {
      val dao = database.monitor()
      dao.replaceHost(host("10.0.0.8:56122"))
      dao.replaceConversation(conversation("current", updatedAt = 1, title = "Current", current = true))
      dao.replaceConversation(conversation("old", updatedAt = 2, title = "Old"))
      dao.replaceConversation(conversation("mid", updatedAt = 3, title = "Mid"))
      dao.replaceConversation(conversation("new", updatedAt = 4, title = "New"))
      dao.replaceTurn(turn("t-old", index = 0, prompt = "old", conversationId = "old"))
      dao.replaceTurn(turn("t-current", index = 0, prompt = "now", conversationId = "current"))
      dao.replaceItem(item("i-old", ordinal = 0, title = "old", turnId = "t-old"))
      dao.replaceItem(item("i-current", ordinal = 0, title = "now", turnId = "t-current"))
      dao.replaceImage(image("old-pic", name = "old.png", modifiedAt = 10, size = 50, turnId = "t-old"))
      dao.replaceImage(image("mid-pic", name = "mid.png", modifiedAt = 20, size = 50, turnId = "t-current"))
      dao.replaceImage(image("new-pic", name = "new.png", modifiedAt = 30, size = 40, turnId = "t-current"))
      dao.replaceOutbox(outbox("pending-1", createdAt = 1, type = "send", state = OutboxPending))
      dao.replaceOutbox(outbox("sent-1", createdAt = 2, type = "stop", state = OutboxSent))

      val removed = database.retain(RetentionLimits(conversationCap = 2, imageBudgetBytes = 80))
      val left = dao.conversations().map { it.id }
      assertEquals(listOf("old"), removed.conversations.map { it.id })
      assertEquals(listOf("current", "mid", "new"), left)
      assertEquals(listOf("mid-pic"), removed.images.map { it.id })
      assertEquals(listOf("new-pic"), dao.images().map { it.id })
      assertEquals(listOf("pending-1", "sent-1"), dao.outbox().map { it.commandId })
      assertEquals(OutboxPending, dao.outbox().first().state)
    } finally {
      database.close()
    }
  }

  @Test
  fun defaultsMatchTheOldCacheLimits() {
    assertEquals(50, DefaultConversationCap)
    assertEquals(128L * 1024L * 1024L, DefaultImageBudgetBytes)
    assertEquals(emptyList<String>(), conversationsToDrop(emptyList(), -1).map { it.id })
    assertEquals(emptyList<String>(), imagesToDrop(emptyList(), -1).map { it.id })
  }
}
