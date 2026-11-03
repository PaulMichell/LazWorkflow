package computing.michell.monitor.data

/* Read model the phone UI observes (c) 2026 Michell Computing.

   Flows come from Room. A collector sees the same rows offline and live.
   Sync writes the cursor in the same transaction as the content it applied.
   A screen save keeps that cursor. An import forces seq 0. */

import androidx.room3.withWriteTransaction
import computing.michell.monitor.protocol.OfflineCacheDocument
import computing.michell.monitor.protocol.PlanRow
import kotlinx.coroutines.flow.Flow
import java.io.File

const val OutboxQueued = "queued"
const val OutboxAccepted = "accepted"
const val OutboxDone = "done"
const val OutboxRejected = "rejected"

class ConversationRepository(
  private val database: MonitorDatabase,
  private val imageRoot: File? = null,
  private val limits: () -> RetentionLimits = { RetentionLimits(DefaultConversationCap, DefaultImageBudgetBytes) }
) {
  fun hosts(): Flow<List<HostRecord>> = database.hosts().observeAll()

  fun conversations(host: String): Flow<List<ConversationRecord>> = database.conversations().observeByHost(host)

  fun conversation(host: String, id: String): Flow<ConversationRecord?> = database.conversations().observeOne(host, id)

  fun turns(host: String, conversationId: String): Flow<List<TurnRecord>> = database.content().observeTurns(host, conversationId)

  fun blocks(host: String, conversationId: String): Flow<List<BlockRecord>> = database.content().observeBlocks(host, conversationId)

  fun images(host: String, conversationId: String): Flow<List<ImageRecord>> = database.images().observe(host, conversationId)

  fun repairs(host: String, conversationId: String): Flow<List<BlockRepairRecord>> = database.sync().observeRepairs(host, conversationId)

  fun outbox(): Flow<List<OutboxRecord>> = database.outbox().observeAll()

  suspend fun saveHost(row: HostRecord) {
    database.hosts().upsert(row)
  }

  suspend fun saveConversation(row: ConversationRecord) {
    database.conversations().upsert(row)
  }

  suspend fun setPinned(host: String, id: String, pinned: Boolean, updatedAt: Long) {
    database.conversations().setPinned(host, id, pinned, updatedAt)
  }

  suspend fun deleteConversation(host: String, id: String) {
    val images = database.sync().loadImages(host, id)
    database.conversations().delete(host, id)
    for (image in images) deleteStoredFile(image.filePath)
  }

  suspend fun replaceContent(host: String, conversationId: String, turns: List<TurnRecord>, blocks: List<BlockRecord>) {
    database.content().replace(host, conversationId, turns, blocks)
  }

  suspend fun saveImage(row: ImageRecord) {
    database.images().upsert(row)
  }

  suspend fun deleteImage(host: String, conversationId: String, imageId: String) {
    database.images().delete(host, conversationId, imageId)
  }

  suspend fun enqueue(row: OutboxRecord) {
    database.outbox().insert(row)
  }

  suspend fun saveOutbox(row: OutboxRecord) {
    database.outbox().upsert(row)
  }

  suspend fun listOutbox(): List<OutboxRecord> = database.outbox().listAll()

  suspend fun setOutboxState(commandId: String, state: String) {
    database.outbox().setState(commandId, state)
  }

  suspend fun removeOutbox(commandId: String) {
    database.outbox().delete(commandId)
  }

  suspend fun listForHost(key: String): List<ConversationRecord> {
    val wanted = hostKey(key)
    return database.conversations().listAll().filter { row -> hostKey(row.host) == wanted }
  }

  suspend fun loadDocument(host: String, id: String): OfflineCacheDocument? {
    if (database.sync().loadConversation(host, id) == null) return null
    return documentFromRows(database.sync().loadTurns(host, id), database.sync().loadBlocks(host, id))
  }

  /** One-time import. Later text reaches Room through the applier, not a document rewrite. */
  suspend fun saveImported(row: LegacyReady, imageRoot: File) {
    val stored = storedScreen(row.hostKey, row.conversationId, row.projectRoot, row.title, row.updatedMs, row.document, 0L, "")
    val images = ArrayList<ImageRecord>()
    for ((id, source) in row.images) {
      if (!source.isFile) continue
      val target = monitorImageFile(imageRoot, row.hostKey, row.conversationId, id) ?: continue
      copyBytes(source.readBytes(), target)
      images += ImageRecord(id, row.hostKey, row.conversationId, target.absolutePath, source.length(), "application/octet-stream", source.length())
    }
    commit(row.hostKey, stored, images)
    retain()
  }

  suspend fun retain() {
    val settings = limits()
    val conversations = database.conversations().listAll()
    for ((host, rows) in conversations.groupBy { row -> row.host }) {
      for (row in conversationsToDrop(rows, settings.conversationCap)) {
        val images = database.sync().loadImages(host, row.id)
        database.conversations().delete(host, row.id)
        for (image in images) deleteStoredFile(image.filePath)
      }
    }
    val present = ArrayList<AgedImage>()
    for (image in database.images().listAll()) {
      val file = File(image.filePath)
      if (!file.isFile) {
        database.images().delete(image.host, image.conversation, image.id)
        continue
      }
      present += AgedImage(image.host, image.conversation, image.id, image.filePath, file.lastModified(), file.length())
    }
    for (image in imagesToDrop(present, settings.imageBudgetBytes)) {
      deleteStoredFile(image.filePath)
      database.images().delete(image.host, image.conversationId, image.imageId)
    }
  }

  suspend fun forgetHost(key: String) {
    val wanted = hostKey(key)
    val hosts = database.hosts().listAll().filter { row -> hostKey(row.id) == wanted || hostKey(row.fingerprint) == wanted }
    for (host in hosts) {
      database.hosts().delete(host.id)
      val folder = imageRoot?.let { root -> safeImageDir(root, host.id) }
      if (folder != null && folder.isDirectory) folder.deleteRecursively()
    }
    for (plan in database.plans().listAll()) {
      if (hostKey(plan.host) == wanted) database.plans().delete(plan.host)
    }
  }

  /** The plan page reads this before the host frame arrives. */
  suspend fun loadPlan(key: String): StoredPlan? {
    if (key.isEmpty()) return null
    val wanted = hostKey(key)
    val row = database.plans().listAll().firstOrNull { plan -> hostKey(plan.host) == wanted } ?: return null
    return storedPlanOf(row.path, row.title, row.selected, row.rowsJson)
  }

  suspend fun savePlan(
    host: String,
    path: String,
    title: String,
    rows: List<PlanRow>,
    selected: Int,
    nowMs: Long,
    revision: String = "",
    receivedBytes: Long = 0,
    totalBytes: Long = 0,
    incomplete: Boolean = false
  ) {
    if (host.isEmpty() || !hasStoredPlan(path, title, rows)) return
    database.hosts().insertIfAbsent(HostRecord(host, host, ""))
    database.plans().upsert(PlanRecord(
      host, path, title, planCacheText(path, title, rows, selected), selected, nowMs,
      revision, receivedBytes, totalBytes, incomplete
    ))
  }

  suspend fun deletePlan(key: String) {
    if (key.isEmpty()) return
    val wanted = hostKey(key)
    for (plan in database.plans().listAll()) {
      if (hostKey(plan.host) == wanted) database.plans().delete(plan.host)
    }
  }

  private suspend fun commit(host: String, stored: StoredScreen, images: List<ImageRecord>) {
    database.withWriteTransaction {
      database.hosts().insertIfAbsent(HostRecord(host, host, ""))
      database.sync().upsertConversation(stored.conversation)
      database.content().replace(host, stored.conversation.id, stored.turns, stored.blocks)
      val previous = database.sync().loadImages(host, stored.conversation.id)
      val kept = images.map { image -> image.id }.toSet()
      for (old in previous) {
        if (old.id in kept) continue
        if (old.filePath.isNotEmpty()) File(old.filePath).delete()
        database.images().delete(host, stored.conversation.id, old.id)
      }
      for (image in images) database.images().upsert(image)
    }
  }
}

private fun deleteStoredFile(path: String) {
  if (path.isEmpty()) return
  File(path).delete()
}

private fun copyBytes(bytes: ByteArray, target: File) {
  val parent = target.parentFile ?: return
  if (!parent.isDirectory && !parent.mkdirs() && !parent.isDirectory) return
  val temporary = File(parent, target.name + ".tmp")
  temporary.writeBytes(bytes)
  if (!temporary.renameTo(target)) {
    target.writeBytes(bytes)
    temporary.delete()
  }
}

private fun safeImageDir(root: File, host: String): File? {
  if (host.isEmpty() || host.contains('/') || host.contains('\\')) return null
  return File(root, host)
}
