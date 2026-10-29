package computing.michell.monitor.data

/* One-shot import of monitor-cache into Room (c) 2026 Michell Computing.

   The imported cursor is 0, so the first connection asks for a snapshot.
   Files are deleted only after every listed conversation has been read.
   A corrupt file stays on disk and the next start tries again. */

import computing.michell.monitor.connection.normalizeFingerprint
import computing.michell.monitor.protocol.LegacyCacheEntry
import computing.michell.monitor.protocol.OfflineCacheDocument
import computing.michell.monitor.protocol.decodeLegacyCacheIndex
import computing.michell.monitor.protocol.decodeOfflineCache
import java.io.File

const val MonitorCacheDirectoryName = "monitor-cache"
const val CacheIndexFileName = "index.json"
const val LegacyOfflineCacheName = "offline-cache.json"
const val MonitorImageDirectoryName = "monitor-images"

data class LegacyReady(
  val hostKey: String,
  val projectRoot: String,
  val conversationId: String,
  val title: String,
  val updatedMs: Long,
  val document: OfflineCacheDocument,
  val images: List<Pair<String, File>>
)

data class LegacyPlan(val ready: List<LegacyReady>, val deleteDirectory: Boolean)

/** Null when there is no index. An unreadable index is an empty plan that keeps the files. */
fun planLegacyImport(filesDir: File): LegacyPlan? {
  val directory = File(filesDir, MonitorCacheDirectoryName)
  val index = File(directory, CacheIndexFileName)
  if (!index.isFile) return null
  val entries = try {
    decodeLegacyCacheIndex(index.readText())
  } catch (error: Exception) {
    null
  } ?: return LegacyPlan(emptyList(), false)
  val ready = ArrayList<LegacyReady>()
  var blocked = false
  for (entry in entries) {
    val file = legacyConversationFile(directory, entry.fileName)
    if (file == null) {
      blocked = true
      continue
    }
    if (!file.isFile) continue
    val document = try {
      decodeOfflineCache(file.readText())
    } catch (error: Exception) {
      null
    }
    if (document == null) {
      blocked = true
      continue
    }
    ready += LegacyReady(
      entry.hostKey,
      entry.projectRoot,
      entry.conversationId,
      entry.title,
      entry.updatedMs,
      document,
      legacyImageFiles(directory, entry)
    )
  }
  return LegacyPlan(ready, !blocked)
}

suspend fun importLegacyCache(filesDir: File, repository: ConversationRepository, imageRoot: File) {
  val plan = planLegacyImport(filesDir) ?: return
  for (row in plan.ready) {
    repository.saveImported(row, imageRoot)
  }
  if (!plan.deleteDirectory) return
  val directory = File(filesDir, MonitorCacheDirectoryName)
  if (directory.isDirectory) directory.deleteRecursively()
  File(filesDir, LegacyOfflineCacheName).delete()
  File(filesDir, LegacyOfflineCacheName + ".tmp").delete()
}

fun hostKey(text: String): String {
  val normalized = normalizeFingerprint(text)
  if (normalized.length == 64) return normalized
  return text.trim()
}

fun monitorImageFile(imageRoot: File, host: String, conversationId: String, imageId: String): File? {
  val hostName = safePathToken(host) ?: return null
  val conversationName = safePathToken(conversationId) ?: return null
  val imageName = safePathToken(imageId) ?: return null
  return File(File(File(imageRoot, hostName), conversationName), imageName)
}

private fun legacyConversationFile(directory: File, fileName: String): File? {
  if (fileName.contains('/') || fileName.contains('\\')) return null
  val file = File(directory, fileName)
  return try {
    if (file.parentFile?.canonicalFile != directory.canonicalFile) null else file
  } catch (error: Exception) {
    null
  }
}

private fun legacyImageFiles(directory: File, entry: LegacyCacheEntry): List<Pair<String, File>> {
  val stem = entry.fileName.removeSuffix(".json")
  val folder = File(directory, stem)
  val found = ArrayList<Pair<String, File>>()
  val wanted = entry.imageIds.toMutableSet()
  if (folder.isDirectory) {
    val children = folder.listFiles() ?: emptyArray()
    for (child in children) {
      if (!child.isFile) continue
      val id = entry.imageIds.firstOrNull { imageId -> imageId == child.name } ?: child.name
      found += id to child
      wanted.remove(id)
    }
  }
  return found
}

private fun safePathToken(text: String): String? {
  if (text.isEmpty() || text.length > 80 || text == "." || text == "..") return null
  for (ch in text) {
    val ok = ch.isLetterOrDigit() || ch == '-' || ch == '_' || ch == '.'
    if (!ok) return null
  }
  return text
}
