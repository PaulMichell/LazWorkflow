package computing.michell.monitor.data

/* Queries for the monitor Room database (c) 2026 Michell Computing.

   Flows are the UI's read path. A content replace deletes and inserts in one
   transaction so a kill cannot leave turns without their blocks. */

import androidx.room3.Dao
import androidx.room3.Insert
import androidx.room3.OnConflictStrategy
import androidx.room3.Query
import androidx.room3.Transaction
import kotlinx.coroutines.flow.Flow

@Dao
interface HostDao {
  @Query("SELECT * FROM host ORDER BY name")
  fun observeAll(): Flow<List<HostRecord>>

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(row: HostRecord)
}

@Dao
interface ConversationDao {
  @Query("SELECT * FROM conversation WHERE host = :host ORDER BY pinned DESC, updatedAt DESC")
  fun observeByHost(host: String): Flow<List<ConversationRecord>>

  @Query("SELECT * FROM conversation WHERE host = :host AND id = :id")
  fun observeOne(host: String, id: String): Flow<ConversationRecord?>

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(row: ConversationRecord)

  @Query("UPDATE conversation SET pinned = :pinned, updatedAt = :updatedAt WHERE host = :host AND id = :id")
  suspend fun setPinned(host: String, id: String, pinned: Boolean, updatedAt: Long)

  @Query("DELETE FROM conversation WHERE host = :host AND id = :id")
  suspend fun delete(host: String, id: String)
}

@Dao
abstract class ContentDao {
  @Query("SELECT * FROM turn WHERE host = :host AND conversationId = :conversationId ORDER BY ordinal")
  abstract fun observeTurns(host: String, conversationId: String): Flow<List<TurnRecord>>

  @Query(
    "SELECT block.host, block.conversation, block.turn, block.blockId, block.ordinal, block.kind, " +
      "block.title, block.body, block.state FROM block " +
      "INNER JOIN turn ON turn.host = block.host AND turn.conversationId = block.conversation AND turn.turnId = block.turn " +
      "WHERE block.host = :host AND block.conversation = :conversation " +
      "ORDER BY turn.ordinal, block.ordinal"
  )
  abstract fun observeBlocks(host: String, conversation: String): Flow<List<BlockRecord>>

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  abstract suspend fun insertTurns(rows: List<TurnRecord>)

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  abstract suspend fun insertBlocks(rows: List<BlockRecord>)

  @Query("DELETE FROM block WHERE host = :host AND conversation = :conversation")
  abstract suspend fun deleteBlocks(host: String, conversation: String)

  @Query("DELETE FROM turn WHERE host = :host AND conversationId = :conversationId")
  abstract suspend fun deleteTurns(host: String, conversationId: String)

  @Transaction
  open suspend fun replace(host: String, conversationId: String, turns: List<TurnRecord>, blocks: List<BlockRecord>) {
    deleteBlocks(host, conversationId)
    deleteTurns(host, conversationId)
    if (turns.isNotEmpty()) insertTurns(turns)
    if (blocks.isNotEmpty()) insertBlocks(blocks)
  }
}

@Dao
interface ImageDao {
  @Query("SELECT * FROM image WHERE host = :host AND conversation = :conversation ORDER BY id")
  fun observe(host: String, conversation: String): Flow<List<ImageRecord>>

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(row: ImageRecord)

  @Query("DELETE FROM image WHERE host = :host AND conversation = :conversation AND id = :id")
  suspend fun delete(host: String, conversation: String, id: String)
}

@Dao
abstract class SyncDao {
  @Query("SELECT id FROM host WHERE id = :id")
  abstract suspend fun findHost(id: String): String?

  @Insert(onConflict = OnConflictStrategy.IGNORE)
  abstract suspend fun insertHost(row: HostRecord)

  @Query("SELECT * FROM conversation WHERE host = :host AND id = :id")
  abstract suspend fun loadConversation(host: String, id: String): ConversationRecord?

  @Query("SELECT * FROM turn WHERE host = :host AND conversationId = :conversationId")
  abstract suspend fun loadTurns(host: String, conversationId: String): List<TurnRecord>

  @Query("SELECT * FROM block WHERE host = :host AND conversation = :conversation")
  abstract suspend fun loadBlocks(host: String, conversation: String): List<BlockRecord>

  @Query("SELECT * FROM image WHERE host = :host AND conversation = :conversation")
  abstract suspend fun loadImages(host: String, conversation: String): List<ImageRecord>

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  abstract suspend fun upsertConversation(row: ConversationRecord)

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  abstract suspend fun upsertTurns(rows: List<TurnRecord>)

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  abstract suspend fun upsertBlocks(rows: List<BlockRecord>)

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  abstract suspend fun upsertImages(rows: List<ImageRecord>)
}

@Dao
interface OutboxDao {
  @Query("SELECT * FROM outbox ORDER BY createdAt")
  fun observeAll(): Flow<List<OutboxRecord>>

  @Insert(onConflict = OnConflictStrategy.ABORT)
  suspend fun insert(row: OutboxRecord)

  @Query("UPDATE outbox SET state = :state WHERE commandId = :commandId")
  suspend fun setState(commandId: String, state: String)

  @Query("DELETE FROM outbox WHERE commandId = :commandId")
  suspend fun delete(commandId: String)
}
