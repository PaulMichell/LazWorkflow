package computing.michell.monitor.data

/* Current plan kept beside the conversation rows (c) 2026 Michell Computing.

   The plan is one host row, not a turn. The Plan page reads this copy at
   once. A later plan frame replaces it. */

import computing.michell.monitor.protocol.OfflineCacheDocument
import computing.michell.monitor.protocol.PlanRow
import computing.michell.monitor.protocol.decodeOfflineCache
import computing.michell.monitor.protocol.encodeOfflineCache

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

fun planCacheText(path: String, title: String, rows: List<PlanRow>, selected: Int): String {
  return encodeOfflineCache(OfflineCacheDocument(emptyList(), emptyList(), null, path, title, rows, selected, "", ""))
}

/** Columns win when they are set. A damaged row list still keeps the title. */
fun storedPlanOf(path: String, title: String, selected: Int, rowsJson: String): StoredPlan? {
  val decoded = try {
    decodeOfflineCache(rowsJson)
  } catch (error: Exception) {
    null
  }
  val rows = decoded?.planRows ?: emptyList()
  val keptPath = if (path.isNotEmpty()) path else decoded?.planPath.orEmpty()
  val keptTitle = if (title.isNotEmpty()) title else decoded?.planTitle.orEmpty()
  val keptSelected = if (selected >= 0) selected else decoded?.selectedPlan ?: -1
  if (!hasStoredPlan(keptPath, keptTitle, rows)) return null
  return StoredPlan(keptPath, keptTitle, rows, keptSelected, "")
}
