package computing.michell.monitor.data

/* DAO insert, replace by id, and ordered query on JVM SQLite (c) 2026 Michell Computing. */

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Test

class MonitorDaoTest {
  @Test
  fun rowsInsertReplaceByIdAndQueryInOrder() {
    val database = openTestDatabase()
    try {
      val dao = database.monitor()
      dao.replaceHost(host("10.0.0.8:56122", rev = 1))
      dao.replaceHost(host("10.0.0.8:56122", rev = 9))
      dao.replaceHost(host("10.0.0.2:56122", rev = 2))
      assertEquals(listOf("10.0.0.2:56122", "10.0.0.8:56122"), dao.hosts().map { it.endpoint })
      assertEquals(9L, dao.hosts().single { it.endpoint == "10.0.0.8:56122" }.lastRev)

      dao.replaceConversation(conversation("c-new", updatedAt = 30, title = "New"))
      dao.replaceConversation(conversation("c-old", updatedAt = 10, title = "Old"))
      dao.replaceConversation(conversation("c-old", updatedAt = 10, title = "Older"))
      assertEquals(listOf("c-old", "c-new"), dao.conversations().map { it.id })
      assertEquals("Older", dao.conversations().first().title)

      dao.replaceTurn(turn("t-2", index = 2, prompt = "second"))
      dao.replaceTurn(turn("t-0", index = 0, prompt = "first"))
      dao.replaceTurn(turn("t-1", index = 1, prompt = "middle"))
      dao.replaceTurn(turn("t-1", index = 1, prompt = "replaced"))
      val turns = dao.turns("c-old")
      assertEquals(listOf(0, 1, 2), turns.map { it.index })
      assertEquals("replaced", turns[1].prompt)

      dao.replaceItem(item("i-2", ordinal = 2, title = "later"))
      dao.replaceItem(item("i-0", ordinal = 0, title = "first"))
      dao.replaceItem(item("i-0", ordinal = 0, title = "renamed"))
      val items = dao.items("t-0")
      assertEquals(listOf(0, 2), items.map { it.ordinal })
      assertEquals("renamed", items.first().title)

      dao.replaceImage(image("pic-b", name = "b.png", modifiedAt = 2))
      dao.replaceImage(image("pic-a", name = "a.png", modifiedAt = 9))
      dao.replaceImage(image("pic-a", name = "a.png", modifiedAt = 9, size = 12))
      assertEquals(listOf("pic-a", "pic-b"), dao.imagesByName().map { it.id })
      assertEquals(12L, dao.imagesByName().first().size)

      dao.replacePlan(plan("docs/b.md", title = "B"))
      dao.replacePlan(plan("docs/a.md", title = "A"))
      dao.replacePlan(plan("docs/a.md", title = "A2"))
      assertEquals(listOf("docs/a.md", "docs/b.md"), dao.plans().map { it.path })
      assertEquals("A2", dao.plans().first().title)

      dao.replaceOutbox(outbox("cmd-2", createdAt = 20, type = "stop"))
      dao.replaceOutbox(outbox("cmd-1", createdAt = 10, type = "send"))
      dao.replaceOutbox(outbox("cmd-1", createdAt = 10, type = "steer"))
      val commands = dao.outbox()
      assertEquals(listOf("cmd-1", "cmd-2"), commands.map { it.commandId })
      assertEquals("steer", commands.first().type)
    } finally {
      database.close()
    }
  }
}

internal fun openTestDatabase(): MonitorDatabase {
  val file = File.createTempFile("monitor-cache-", ".db")
  file.deleteOnExit()
  return openMonitorDatabase(file.absolutePath, JdbcSqliteDriver(), allowMainThread = true)
}

internal fun host(endpoint: String, rev: Long = 0): HostRow {
  return HostRow(endpoint, pin = "ab".repeat(32), tokenRef = endpoint, lastEpoch = "epoch", lastRev = rev)
}

internal fun conversation(id: String, updatedAt: Long, title: String, current: Boolean = false): ConversationRow {
  return ConversationRow(id, "10.0.0.8:56122", title, etag = "e-$id", turnCount = 1, current = current, updatedAt = updatedAt)
}

internal fun turn(id: String, index: Int, prompt: String, conversationId: String = "c-old"): TurnRow {
  return TurnRow(id, conversationId, index, etag = "t-$id", prompt, mode = "build", createdAt = index.toLong(),
    outcome = "ok", duration = 0, errorText = "", clientCommandId = "")
}

internal fun item(id: String, ordinal: Int, title: String, turnId: String = "t-0"): ItemRow {
  return ItemRow(id, turnId, ordinal, kind = "answer", state = "done", title, toolName = "", body = title,
    revision = 1, epoch = "epoch", byteLength = title.length.toLong())
}

internal fun image(id: String, name: String, modifiedAt: Long, size: Long = name.length.toLong(), turnId: String = "t-0"): ImageRow {
  return ImageRow(id, turnId, itemId = "i-0", name, size, localPath = name, modifiedAt = modifiedAt)
}

internal fun plan(path: String, title: String): PlanCacheRow {
  return PlanCacheRow("10.0.0.8:56122", path, title, etag = "p", rowsJson = "[]", documentText = title)
}

internal fun outbox(id: String, createdAt: Long, type: String, state: String = OutboxPending): OutboxRow {
  return OutboxRow(id, "10.0.0.8:56122", type, argsJson = "{}", createdAt, state, lastError = "")
}
