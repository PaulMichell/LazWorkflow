package computing.michell.monitor.ui.model

/* Stored rows the screens still read. Room is gone; the fields are unchanged (c) 2026 Michell Computing. */

const val PlanIncompleteLabel = "Plan file incomplete"
const val PlanInlineBytes = 256 * 1024
const val MonitorImageDirectoryName = "monitor-images"
const val MonitorDatabaseName = "monitor.db"

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

data class StoredPlan(
  val path: String,
  val title: String,
  val rows: List<PlanRow>,
  val selected: Int,
  val body: String = ""
)

fun hasStoredPlan(path: String, title: String, rows: List<PlanRow>): Boolean {
  return path.isNotEmpty() || title.isNotEmpty() || rows.isNotEmpty()
}

fun hostKey(text: String): String = text.trim()
