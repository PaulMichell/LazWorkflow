package computing.michell.monitor.data

/* Cache queries. Replace is by primary key. Lists come back in display order.
   Retention runs in one transaction so a dropped conversation's images are
   gone before the byte budget is applied. (c) 2026 Michell Computing.

   Sync updates an existing host or conversation with UPDATE. INSERT OR REPLACE
   would delete the row first and cascade away its turns. */

import androidx.room3.Dao
import androidx.room3.Insert
import androidx.room3.OnConflictStrategy
import androidx.room3.Query
import androidx.room3.Transaction

@Dao
abstract class MonitorDao {
  @Insert(onConflict = OnConflictStrategy.REPLACE)
  abstract fun replaceHost(row: HostRow)

  @Query("SELECT * FROM host ORDER BY endpoint")
  abstract fun hosts(): List<HostRow>

  @Query("SELECT * FROM host WHERE endpoint = :endpoint")
  abstract fun host(endpoint: String): HostRow?

  @Query("UPDATE host SET lastEpoch = :epoch, lastRev = :rev WHERE endpoint = :endpoint")
  abstract fun updateHostCursor(endpoint: String, epoch: String, rev: Long)

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  abstract fun replaceConversation(row: ConversationRow)

  @Query("SELECT * FROM conversation ORDER BY updatedAt, id")
  abstract fun conversations(): List<ConversationRow>

  @Query("SELECT * FROM conversation WHERE id = :id")
  abstract fun conversation(id: String): ConversationRow?

  @Query("UPDATE conversation SET title = :title, etag = :etag, turnCount = :turnCount, current = :current, updatedAt = :updatedAt WHERE id = :id")
  abstract fun updateConversation(id: String, title: String, etag: String, turnCount: Int, current: Boolean, updatedAt: Long)

  @Query("UPDATE conversation SET current = 0 WHERE host = :host AND id != :id")
  abstract fun clearCurrentExcept(host: String, id: String)

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  abstract fun replaceTurn(row: TurnRow)

  @Query("SELECT * FROM turn WHERE conversationId = :conversationId ORDER BY turnIndex, id")
  abstract fun turns(conversationId: String): List<TurnRow>

  @Query("SELECT * FROM turn WHERE id = :id")
  abstract fun turn(id: String): TurnRow?

  @Query("UPDATE turn SET turnIndex = :index, etag = :etag, prompt = :prompt, mode = :mode, createdAt = :createdAt, outcome = :outcome, duration = :duration, errorText = :errorText, clientCommandId = :clientCommandId WHERE id = :id")
  abstract fun updateTurn(id: String, index: Int, etag: String, prompt: String, mode: String, createdAt: Long, outcome: String, duration: Int, errorText: String, clientCommandId: String)

  @Query("DELETE FROM turn WHERE id = :id")
  abstract fun deleteTurn(id: String)

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  abstract fun replaceItem(row: ItemRow)

  @Query("SELECT * FROM item WHERE turnId = :turnId ORDER BY ordinal, id")
  abstract fun items(turnId: String): List<ItemRow>

  @Query("SELECT * FROM item WHERE id = :id")
  abstract fun item(id: String): ItemRow?

  @Query("DELETE FROM item WHERE turnId = :turnId")
  abstract fun deleteItemsForTurn(turnId: String)

  @Query("DELETE FROM item WHERE id = :id")
  abstract fun deleteItem(id: String)

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  abstract fun replaceImage(row: ImageRow)

  @Query("SELECT * FROM image ORDER BY name, id")
  abstract fun imagesByName(): List<ImageRow>

  @Query("SELECT * FROM image ORDER BY modifiedAt, id")
  abstract fun images(): List<ImageRow>

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  abstract fun replacePlan(row: PlanCacheRow)

  @Query("SELECT * FROM plan ORDER BY path, host")
  abstract fun plans(): List<PlanCacheRow>

  @Query("SELECT * FROM plan WHERE host = :host AND path = :path")
  abstract fun plan(host: String, path: String): PlanCacheRow?

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  abstract fun replaceOutbox(row: OutboxRow)

  @Query("SELECT * FROM outbox ORDER BY createdAt, commandId")
  abstract fun outbox(): List<OutboxRow>

  @Query("DELETE FROM conversation WHERE id IN (:ids)")
  abstract fun deleteConversations(ids: List<String>)

  @Query("DELETE FROM image WHERE id IN (:ids)")
  abstract fun deleteImages(ids: List<String>)

  @Transaction
  open fun retain(limits: RetentionLimits): RetentionRemoval {
    val droppedConversations = conversationsToDrop(conversations(), limits.conversationCap)
    val conversationIds = droppedConversations.map { it.id }
    if (conversationIds.isNotEmpty()) deleteConversations(conversationIds)
    val droppedImages = imagesToDrop(images(), limits.imageBudgetBytes)
    val imageIds = droppedImages.map { it.id }
    if (imageIds.isNotEmpty()) deleteImages(imageIds)
    return RetentionRemoval(droppedConversations, droppedImages)
  }

  @Transaction
  open fun write(block: () -> Unit) {
    block()
  }
}
