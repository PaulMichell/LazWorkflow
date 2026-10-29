package computing.michell.monitor.data

/* Read model the phone UI observes (c) 2026 Michell Computing.

   Flows come from Room. A collector sees the same rows offline and live.
   Sync writes the cursor in the same transaction as the content it applied. */

import kotlinx.coroutines.flow.Flow

const val OutboxQueued = "queued"
const val OutboxAccepted = "accepted"
const val OutboxDone = "done"
const val OutboxRejected = "rejected"

class ConversationRepository(private val database: MonitorDatabase) {
  fun hosts(): Flow<List<HostRecord>> = database.hosts().observeAll()

  fun conversations(host: String): Flow<List<ConversationRecord>> = database.conversations().observeByHost(host)

  fun conversation(host: String, id: String): Flow<ConversationRecord?> = database.conversations().observeOne(host, id)

  fun turns(host: String, conversationId: String): Flow<List<TurnRecord>> = database.content().observeTurns(host, conversationId)

  fun blocks(host: String, conversationId: String): Flow<List<BlockRecord>> = database.content().observeBlocks(host, conversationId)

  fun images(host: String, conversationId: String): Flow<List<ImageRecord>> = database.images().observe(host, conversationId)

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
    database.conversations().delete(host, id)
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

  suspend fun setOutboxState(commandId: String, state: String) {
    database.outbox().setState(commandId, state)
  }

  suspend fun removeOutbox(commandId: String) {
    database.outbox().delete(commandId)
  }
}
