package computing.michell.monitor.data

/* How many conversations and image bytes the phone keeps (c) 2026 Michell Computing.

   Pinned conversations are never dropped. The cap applies to the rest, newest
   first, per host. The image budget is the whole phone. Oldest files go first.
   Both numbers are settings. These defaults are used when a setting is absent. */

const val DefaultConversationCap = 50
const val DefaultImageBudgetMiB = 128
const val DefaultImageBudgetBytes = DefaultImageBudgetMiB.toLong() * 1024L * 1024L

data class RetentionLimits(val conversationCap: Int, val imageBudgetBytes: Long)

data class AgedImage(
  val host: String,
  val conversationId: String,
  val imageId: String,
  val filePath: String,
  val modifiedMs: Long,
  val bytes: Long
)

fun conversationsToDrop(rows: List<ConversationRecord>, cap: Int): List<ConversationRecord> {
  if (cap < 0) return emptyList()
  val unpinned = rows.filter { row -> !row.pinned }
    .sortedWith(compareByDescending<ConversationRecord> { it.updatedAt }.thenByDescending { it.id })
  if (unpinned.size <= cap) return emptyList()
  return unpinned.drop(cap)
}

fun imagesToDrop(images: List<AgedImage>, budgetBytes: Long): List<AgedImage> {
  if (budgetBytes < 0) return emptyList()
  val oldest = images.sortedWith(compareBy<AgedImage> { it.modifiedMs }.thenBy { it.imageId })
  var total = 0L
  for (image in oldest) total += image.bytes
  val drop = ArrayList<AgedImage>()
  for (image in oldest) {
    if (total <= budgetBytes) break
    drop += image
    total -= image.bytes
  }
  return drop
}
