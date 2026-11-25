package computing.michell.monitor.data

/* Room rows for the pulse-and-fetch cache (c) 2026 Michell Computing.

   The token itself stays in encrypted preferences. This table keeps only a
   reference. updatedAt and modifiedAt are the retention clocks: oldest
   conversations and images go first. Catalogue 3 tables are not recreated. */

import androidx.room3.ColumnInfo
import androidx.room3.Entity
import androidx.room3.ForeignKey
import androidx.room3.Index
import androidx.room3.PrimaryKey

@Entity(tableName = "host")
data class HostRow(
  @PrimaryKey val endpoint: String,
  val pin: String,
  val tokenRef: String,
  val lastEpoch: String,
  val lastRev: Long
)

@Entity(
  tableName = "conversation",
  foreignKeys = [
    ForeignKey(
      entity = HostRow::class,
      parentColumns = ["endpoint"],
      childColumns = ["host"],
      onDelete = ForeignKey.CASCADE
    )
  ],
  indices = [Index("host"), Index("updatedAt")]
)
data class ConversationRow(
  @PrimaryKey val id: String,
  val host: String,
  val title: String,
  val etag: String,
  val turnCount: Int,
  val current: Boolean,
  val updatedAt: Long
)

@Entity(
  tableName = "turn",
  foreignKeys = [
    ForeignKey(
      entity = ConversationRow::class,
      parentColumns = ["id"],
      childColumns = ["conversationId"],
      onDelete = ForeignKey.CASCADE
    )
  ],
  indices = [Index("conversationId"), Index("conversationId", "turnIndex")]
)
data class TurnRow(
  @PrimaryKey val id: String,
  val conversationId: String,
  @ColumnInfo(name = "turnIndex") val index: Int,
  val etag: String,
  val prompt: String,
  val mode: String,
  val createdAt: Long,
  val outcome: String,
  val duration: Int,
  val errorText: String,
  val clientCommandId: String
)

@Entity(
  tableName = "item",
  foreignKeys = [
    ForeignKey(
      entity = TurnRow::class,
      parentColumns = ["id"],
      childColumns = ["turnId"],
      onDelete = ForeignKey.CASCADE
    )
  ],
  indices = [Index("turnId"), Index("turnId", "ordinal")]
)
data class ItemRow(
  @PrimaryKey val id: String,
  val turnId: String,
  val ordinal: Int,
  val kind: String,
  val state: String,
  val title: String,
  val toolName: String,
  val body: String,
  val revision: Long,
  val epoch: String,
  val byteLength: Long
)

@Entity(
  tableName = "image",
  foreignKeys = [
    ForeignKey(
      entity = TurnRow::class,
      parentColumns = ["id"],
      childColumns = ["turnId"],
      onDelete = ForeignKey.CASCADE
    )
  ],
  indices = [Index("turnId"), Index("itemId"), Index("modifiedAt")]
)
data class ImageRow(
  @PrimaryKey val id: String,
  val turnId: String,
  val itemId: String,
  val name: String,
  val size: Long,
  val localPath: String,
  val modifiedAt: Long
)

@Entity(
  tableName = "plan",
  primaryKeys = ["host", "path"],
  foreignKeys = [
    ForeignKey(
      entity = HostRow::class,
      parentColumns = ["endpoint"],
      childColumns = ["host"],
      onDelete = ForeignKey.CASCADE
    )
  ],
  indices = [Index("host")]
)
data class PlanCacheRow(
  val host: String,
  val path: String,
  val title: String,
  val etag: String,
  val rowsJson: String,
  val documentText: String
)

const val OutboxPending = "pending"
const val OutboxSent = "sent"

@Entity(
  tableName = "outbox",
  foreignKeys = [
    ForeignKey(
      entity = HostRow::class,
      parentColumns = ["endpoint"],
      childColumns = ["host"],
      onDelete = ForeignKey.CASCADE
    )
  ],
  indices = [Index("host"), Index("createdAt")]
)
data class OutboxRow(
  @PrimaryKey val commandId: String,
  val host: String,
  val type: String,
  val argsJson: String,
  val createdAt: Long,
  val state: String,
  val lastError: String
) {
  val unsent: Boolean
    get() = state != OutboxSent
}
