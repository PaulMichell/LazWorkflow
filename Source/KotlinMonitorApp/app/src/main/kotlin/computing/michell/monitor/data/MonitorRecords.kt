package computing.michell.monitor.data

/* Room rows for the phone's local copy (c) 2026 Michell Computing.

   The database is the source of truth for live view and offline review.
   Images are files. The row keeps the path and the sizes, not the pixels. */

import androidx.room3.Entity
import androidx.room3.ForeignKey
import androidx.room3.Index
import androidx.room3.PrimaryKey

@Entity(tableName = "host")
data class HostRecord(
  @PrimaryKey val id: String,
  val fingerprint: String,
  val name: String
)

@Entity(
  tableName = "conversation",
  primaryKeys = ["host", "id"],
  foreignKeys = [
    ForeignKey(
      entity = HostRecord::class,
      parentColumns = ["id"],
      childColumns = ["host"],
      onDelete = ForeignKey.CASCADE
    )
  ],
  indices = [Index("host"), Index("updatedAt")]
)
data class ConversationRecord(
  val id: String,
  val host: String,
  val projectRoot: String,
  val title: String,
  val streamId: String,
  val seq: Long,
  val updatedAt: Long,
  val pinned: Boolean
)

@Entity(
  tableName = "turn",
  primaryKeys = ["host", "conversationId", "turnId"],
  foreignKeys = [
    ForeignKey(
      entity = ConversationRecord::class,
      parentColumns = ["host", "id"],
      childColumns = ["host", "conversationId"],
      onDelete = ForeignKey.CASCADE
    )
  ],
  indices = [Index("host", "conversationId")]
)
data class TurnRecord(
  val host: String,
  val conversationId: String,
  val turnId: String,
  val ordinal: Int,
  val mode: String,
  val prompt: String,
  val createdAt: String,
  val outcome: String,
  val durationMs: Int,
  val errorText: String
)

@Entity(
  tableName = "block",
  primaryKeys = ["host", "conversation", "blockId"],
  foreignKeys = [
    ForeignKey(
      entity = TurnRecord::class,
      parentColumns = ["host", "conversationId", "turnId"],
      childColumns = ["host", "conversation", "turn"],
      onDelete = ForeignKey.CASCADE
    )
  ],
  indices = [Index("host", "conversation"), Index("host", "conversation", "turn")]
)
data class BlockRecord(
  val host: String,
  val conversation: String,
  val turn: String,
  val blockId: String,
  val ordinal: Int,
  val kind: String,
  val title: String,
  val body: String,
  val state: String
)

@Entity(
  tableName = "image",
  primaryKeys = ["host", "conversation", "id"],
  foreignKeys = [
    ForeignKey(
      entity = ConversationRecord::class,
      parentColumns = ["host", "id"],
      childColumns = ["host", "conversation"],
      onDelete = ForeignKey.CASCADE
    )
  ],
  indices = [Index("host", "conversation")]
)
data class ImageRecord(
  val id: String,
  val host: String,
  val conversation: String,
  val filePath: String,
  val bytes: Long,
  val mime: String,
  val size: Long
)

/** A block whose body is not the cursor's text until a fetch finishes. */
@Entity(
  tableName = "block_repair",
  primaryKeys = ["host", "conversation", "blockId"],
  foreignKeys = [
    ForeignKey(
      entity = ConversationRecord::class,
      parentColumns = ["host", "id"],
      childColumns = ["host", "conversation"],
      onDelete = ForeignKey.CASCADE
    )
  ],
  indices = [Index("host", "conversation"), Index("host", "requestId")]
)
data class BlockRepairRecord(
  val host: String,
  val conversation: String,
  val blockId: String,
  val revision: Long,
  val expectedLength: Int,
  val missingBody: Boolean,
  val hash: String,
  val stale: Boolean,
  val requestId: String,
  val fetchedBody: String
)

/** An append held until the block fetch it depends on has committed. */
@Entity(
  tableName = "held_append",
  primaryKeys = ["host", "conversation", "blockId", "seq"],
  foreignKeys = [
    ForeignKey(
      entity = ConversationRecord::class,
      parentColumns = ["host", "id"],
      childColumns = ["host", "conversation"],
      onDelete = ForeignKey.CASCADE
    )
  ],
  indices = [Index("host", "conversation", "blockId")]
)
data class HeldAppendRecord(
  val host: String,
  val conversation: String,
  val blockId: String,
  val seq: Long,
  val offset: Int,
  val text: String,
  val streamId: String
)

/** Latest value of one state key. It has no content sequence. */
@Entity(
  tableName = "host_state",
  primaryKeys = ["host", "key"],
  foreignKeys = [
    ForeignKey(
      entity = HostRecord::class,
      parentColumns = ["id"],
      childColumns = ["host"],
      onDelete = ForeignKey.CASCADE
    )
  ],
  indices = [Index("host")]
)
data class HostStateRecord(
  val host: String,
  val key: String,
  val valueJson: String,
  val updatedAt: Long
)

/** The desktop's current plan for one host. Not a conversation row. */
@Entity(tableName = "plan")
data class PlanRecord(
  @PrimaryKey val host: String,
  val path: String,
  val title: String,
  val rowsJson: String,
  val selected: Int,
  val updatedAt: Long,
  val revision: String = "",
  val receivedBytes: Long = 0,
  val totalBytes: Long = 0,
  val incomplete: Boolean = false
)

@Entity(tableName = "outbox")
data class OutboxRecord(
  @PrimaryKey val commandId: String,
  val kind: String,
  val json: String,
  val state: String,
  val createdAt: Long
)
