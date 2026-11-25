package computing.michell.monitor.data

/* How many conversations and image bytes the phone keeps (c) 2026 Michell Computing.

   The cap applies to conversations that are not current, newest first, per host.
   The image budget is the whole phone. Oldest files go first. The current
   conversation and unsent outbox rows are never removed. Both numbers are
   settings. These defaults are used when a setting is absent. */

import java.io.File

const val DefaultConversationCap = 50
const val DefaultImageBudgetMiB = 128
const val DefaultImageBudgetBytes = DefaultImageBudgetMiB.toLong() * 1024L * 1024L

data class RetentionLimits(val conversationCap: Int, val imageBudgetBytes: Long)

data class RetentionRemoval(
  val conversations: List<ConversationRow>,
  val images: List<ImageRow>
)

fun conversationsToDrop(rows: List<ConversationRow>, cap: Int): List<ConversationRow> {
  if (cap < 0) return emptyList()
  return rows.groupBy { it.host }.values.flatMap { group -> dropHost(group, cap) }
}

private fun dropHost(rows: List<ConversationRow>, cap: Int): List<ConversationRow> {
  val rest = rows.filter { row -> !row.current }
    .sortedWith(compareByDescending<ConversationRow> { it.updatedAt }.thenByDescending { it.id })
  if (rest.size <= cap) return emptyList()
  return rest.drop(cap)
}

fun imagesToDrop(images: List<ImageRow>, budgetBytes: Long): List<ImageRow> {
  if (budgetBytes < 0) return emptyList()
  val oldest = images.sortedWith(compareBy<ImageRow> { it.modifiedAt }.thenBy { it.id })
  var total = 0L
  for (image in oldest) total += image.size
  val drop = ArrayList<ImageRow>()
  for (image in oldest) {
    if (total <= budgetBytes) break
    drop += image
    total -= image.size
  }
  return drop
}

/** Deletes rows past the limits. Does not delete the current conversation or any outbox row. */
fun MonitorDatabase.retain(limits: RetentionLimits): RetentionRemoval {
  val removed = monitor().retain(limits)
  for (image in removed.images) {
    if (image.localPath.isNotEmpty()) File(image.localPath).delete()
  }
  return removed
}
