package computing.michell.monitor.data

/* Cache queries. Replace is by primary key. Lists come back in display order.
   Retention runs in one transaction so a dropped conversation's images are
   gone before the byte budget is applied. (c) 2026 Michell Computing. */

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

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  abstract fun replaceConversation(row: ConversationRow)

  @Query("SELECT * FROM conversation ORDER BY updatedAt, id")
  abstract fun conversations(): List<ConversationRow>

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  abstract fun replaceTurn(row: TurnRow)

  @Query("SELECT * FROM turn WHERE conversationId = :conversationId ORDER BY turnIndex, id")
  abstract fun turns(conversationId: String): List<TurnRow>

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  abstract fun replaceItem(row: ItemRow)

  @Query("SELECT * FROM item WHERE turnId = :turnId ORDER BY ordinal, id")
  abstract fun items(turnId: String): List<ItemRow>

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
}
