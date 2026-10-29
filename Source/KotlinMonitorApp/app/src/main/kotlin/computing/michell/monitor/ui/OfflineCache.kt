package computing.michell.monitor.ui

/* Offline conversation library under monitor-cache/ (c) 2026 Michell Computing.

   index.json lists conversations. One JSON file holds the screen. Decoded
   image bytes sit in a sibling directory, named by image id. The old
   offline-cache.json is deleted once, after the first directory save. */

import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.connection.ReconnectingBanner
import computing.michell.monitor.connection.normalizeFingerprint
import computing.michell.monitor.connection.sha256Hex
import computing.michell.monitor.protocol.CacheImageNote
import computing.michell.monitor.protocol.CacheIndexEntry
import computing.michell.monitor.protocol.OfflineCacheDocument
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.cacheFileNameIsSafe
import computing.michell.monitor.protocol.cacheStemIsSafe
import computing.michell.monitor.protocol.conversationIdIsIdentity
import computing.michell.monitor.protocol.decodeCacheIndex
import computing.michell.monitor.protocol.decodeClosedScreen
import computing.michell.monitor.protocol.indexWithoutFingerprint
import computing.michell.monitor.protocol.decodeOfflineCache
import computing.michell.monitor.protocol.encodeCacheIndex
import computing.michell.monitor.protocol.encodeOfflineCache
import java.io.File
import java.io.IOException

const val OfflineBanner = "Offline"
const val NoAddressBanner = "Set the desktop address in Settings."
const val MonitorCacheDirectoryName = "monitor-cache"
const val CacheIndexFileName = "index.json"
const val LegacyOfflineCacheName = "offline-cache.json"
const val CacheConversationsPerFingerprint = 20
const val CacheImageBudgetBytes = 32L * 1024L * 1024L
const val CacheSaveDebounceMs = 1_000L
const val ImagePlaceholder = "Image"
const val LoadingImageLabel = "Loading image"

fun bannerIsStatus(banner: String): Boolean {
  return banner == OfflineBanner || banner == NoAddressBanner || banner == ConnectingBanner || banner == ReconnectingBanner
}

fun offlineDocument(ui: MonitorUi): OfflineCacheDocument {
  return OfflineCacheDocument(
    ui.turns,
    ui.history.values.toList(),
    ui.live,
    ui.planPath,
    ui.planTitle,
    ui.planRows,
    ui.selectedPlan,
    ui.draft
  )
}

fun worthCaching(ui: MonitorUi): Boolean {
  return ui.turns.isNotEmpty() || ui.history.isNotEmpty() || ui.live != null || ui.planRows.isNotEmpty() || ui.draft.isNotEmpty()
}

/** A committed cursor is a finished patch or catchup. An open part set is not. */
fun cursorCommitted(before: MonitorUi, after: MonitorUi): Boolean {
  if (after.hostEpoch.isEmpty() || after.catchingUp || after.patchOpenCursor != 0L) return false
  if (after.hostEpoch != before.hostEpoch) return true
  return after.hostCursor > before.hostCursor
}

fun cacheFingerprint(text: String): String {
  val normalized = normalizeFingerprint(text)
  if (normalized.length == 64) return normalized
  return text.trim()
}

/** One file per host and conversation. Project root is not part of the key. */
fun cacheConversationFileName(hostFingerprint: String, conversationId: String): String {
  val key = cacheFingerprint(hostFingerprint) + "\u0000" + conversationId
  return "c-" + sha256Hex(key.toByteArray(Charsets.UTF_8)) + ".json"
}

fun cacheImageFileName(imageId: String): String {
  if (safeImageToken(imageId)) return imageId
  if (imageId.isEmpty()) return ""
  return "i-" + sha256Hex(imageId.toByteArray(Charsets.UTF_8)).substring(0, 32)
}

fun cacheTurnCount(document: OfflineCacheDocument): Int {
  val indices = document.turns.map { turn -> turn.turnIndex }.toMutableSet()
  var count = document.turns.size
  val live = document.live
  if (live != null && live.turnIndex !in indices) count += 1
  return count
}

fun cacheTitle(title: String, turns: List<WireTurn>, live: WireTurn?, history: List<WireTurn>): String {
  if (title.isNotEmpty()) return title
  return firstUserPromptPreview(turns, live, history)
}

/** Host title wins. Otherwise the prompt preview of the first user block. */
fun firstUserPromptPreview(turns: List<WireTurn>, live: WireTurn?, history: List<WireTurn>): String {
  val historyByIndex = history.associateBy { turn -> turn.turnIndex }
  val ordered = ArrayList<WireTurn>()
  for (turn in turns) {
    val body = historyByIndex[turn.turnIndex]
    ordered += if (body != null && body.blocks.any { block -> block.kind == "user" && block.body.isNotEmpty() }) body else turn
  }
  if (live != null) {
    val at = ordered.indexOfFirst { turn -> turn.turnIndex == live.turnIndex }
    val liveUser = live.blocks.any { block -> block.kind == "user" && block.body.isNotEmpty() }
    if (at < 0) ordered += live
    else if (liveUser && ordered[at].blocks.none { block -> block.kind == "user" && block.body.isNotEmpty() }) ordered[at] = live
  }
  for (turn in ordered) {
    val user = turn.blocks.firstOrNull { block -> block.kind == "user" && block.body.isNotEmpty() }
    if (user != null) {
      if (turn.promptPreview.isNotEmpty()) return turn.promptPreview
      return user.body
    }
    if (turn.promptPreview.isNotEmpty()) return turn.promptPreview
    if (turn.prompt.isNotEmpty()) return turn.prompt
  }
  return ""
}

data class CacheSaveTarget(val conversationId: String, val projectRoot: String, val title: String)

/** Empty and `current` are not identities. Project root is stored, not keyed. */
fun cacheSaveTarget(ui: MonitorUi): CacheSaveTarget? {
  if (!worthCaching(ui) || !conversationIdIsIdentity(ui.conversationId)) return null
  val history = ui.history.values.toList()
  return CacheSaveTarget(ui.conversationId, ui.projectRoot, cacheTitle(ui.conversationTitle, ui.turns, ui.live, history))
}

fun cacheRowChanged(before: MonitorUi, after: MonitorUi): Boolean {
  val next = cacheSaveTarget(after) ?: return false
  val previous = cacheSaveTarget(before)
  if (previous == null) return true
  return next.conversationId != previous.conversationId || next.projectRoot != previous.projectRoot || next.title != previous.title
}

fun projectDisplay(projectRoot: String): String {
  val trimmed = projectRoot.trim().trimEnd('/', '\\')
  if (trimmed.isEmpty()) return ""
  val slash = maxOf(trimmed.lastIndexOf('/'), trimmed.lastIndexOf('\\'))
  if (slash < 0 || slash >= trimmed.lastIndex) return trimmed
  return trimmed.substring(slash + 1)
}

fun cacheUpdatedText(updatedMs: Long, zone: java.time.ZoneId = java.time.ZoneId.systemDefault()): String {
  if (updatedMs <= 0L) return ""
  val formatter = java.time.format.DateTimeFormatter.ofPattern("d MMM yyyy, HH:mm").withLocale(java.util.Locale.UK)
  return java.time.Instant.ofEpochMilli(updatedMs).atZone(zone).format(formatter)
}

fun cacheRowTitle(entry: CacheIndexEntry): String {
  if (entry.title.isNotEmpty()) return entry.title
  if (entry.conversationId.isNotEmpty()) return entry.conversationId
  return "Untitled"
}

/** Newest first. Only the last paired fingerprint. */
fun cacheRowsForFingerprint(entries: List<CacheIndexEntry>, fingerprint: String): List<CacheIndexEntry> {
  val key = cacheFingerprint(fingerprint)
  return entries.filter { entry -> cacheFingerprint(entry.fingerprint) == key }
    .sortedWith(compareByDescending<CacheIndexEntry> { it.updatedMs }.thenBy { it.fileName })
}

fun cachedButtonVisible(disconnected: Boolean, phase: LinkPhase): Boolean {
  return !ideLinkLive(disconnected, phase)
}

/** The page copy of a chosen cache file. Remote actions stay off. Does not open a socket. */
fun reviewedCacheState(state: MonitorUi, document: OfflineCacheDocument, entry: CacheIndexEntry, hasAddress: Boolean): MonitorUi {
  return applyOfflineCache(state, document, hasAddress).copy(
    conversationId = entry.conversationId,
    projectRoot = entry.projectRoot,
    conversationTitle = entry.title,
    hostEpoch = entry.epoch,
    hostCursor = entry.cursor
  )
}

fun newestCacheEntry(entries: List<CacheIndexEntry>, fingerprint: String): CacheIndexEntry? {
  val key = cacheFingerprint(fingerprint)
  return entries.filter { entry -> cacheFingerprint(entry.fingerprint) == key }
    .maxWithOrNull(compareBy<CacheIndexEntry> { it.updatedMs }.thenBy { it.fileName })
}

fun documentImageIds(document: OfflineCacheDocument): List<String> {
  val ids = ArrayList<String>()
  fun add(turn: WireTurn) {
    for (id in turnImageIds(turn)) if (id !in ids) ids += id
  }
  for (turn in document.turns) add(turn)
  for (turn in document.history) add(turn)
  val live = document.live
  if (live != null) add(live)
  return ids
}

/** Missing decoded bytes stay a placeholder. A live link may still say it is loading. */
fun imageTileLabel(hasBitmap: Boolean, reason: String?, missing: Boolean, allowFetch: Boolean): String {
  if (hasBitmap) return ""
  if (!reason.isNullOrEmpty()) return "Image unavailable: $reason"
  if (missing) return "Image unavailable: missing"
  if (!allowFetch) return ImagePlaceholder
  return LoadingImageLabel
}

/** Restores browseable rows. Remote actions stay off until a live snapshot arrives. */
fun applyOfflineCache(state: MonitorUi, document: OfflineCacheDocument, hasAddress: Boolean): MonitorUi {
  val hasBrowse = document.turns.isNotEmpty() || document.history.isNotEmpty() || document.live != null || document.planRows.isNotEmpty()
  val banner = when {
    !hasAddress -> NoAddressBanner
    hasBrowse -> OfflineBanner
    else -> ""
  }
  return state.copy(
    turns = document.turns,
    history = document.history.associateBy { it.turnIndex },
    live = document.live,
    planPath = document.planPath,
    planTitle = document.planTitle,
    planRows = document.planRows,
    planRunning = false,
    selectedPlan = document.selectedPlan,
    draft = document.draft,
    disconnected = true,
    reachedLive = false,
    pairHold = false,
    settingsOpen = false,
    approval = null,
    approvalOpen = false,
    banner = banner,
    view = clearRemoteActions(emptyView())
  )
}

data class CacheImageBytes(val imageId: String, val bytes: ByteArray)

class OfflineStore(
  private val filesDir: File,
  private val clock: () -> Long = { System.currentTimeMillis() },
  private val conversationCap: Int = CacheConversationsPerFingerprint,
  private val imageBudgetBytes: Long = CacheImageBudgetBytes
) {
  private val gate = Any()
  val directory: File = File(filesDir, MonitorCacheDirectoryName)
  private val legacyFile = File(filesDir, LegacyOfflineCacheName)

  fun loadIndex(): List<CacheIndexEntry> = synchronized(gate) {
    readIndex()
  }

  fun loadConversation(fileName: String): OfflineCacheDocument? = synchronized(gate) {
    val file = conversationFile(fileName) ?: return null
    if (!file.isFile) return null
    return try {
      decodeOfflineCache(file.readText())
    } catch (error: Exception) {
      null
    }
  }

  fun readImage(fileName: String, imageId: String): ByteArray? = synchronized(gate) {
    val file = imageFile(fileName, imageId) ?: return null
    if (!file.isFile) return null
    return try {
      file.readBytes()
    } catch (error: Exception) {
      null
    }
  }

  fun save(
    fingerprint: String,
    projectRoot: String,
    conversationId: String,
    title: String,
    document: OfflineCacheDocument,
    images: List<CacheImageBytes> = emptyList(),
    nowMs: Long = clock(),
    epoch: String = "",
    cursor: Long = 0
  ) = synchronized(gate) {
    if (conversationId.isEmpty() || cursor < 0L) return
    val key = cacheFingerprint(fingerprint)
    val fileName = cacheConversationFileName(key, conversationId)
    if (!cacheFileNameIsSafe(fileName)) throw IOException("Unsafe cache file name.")
    writeAtomic(conversationFile(fileName) ?: throw IOException("Unsafe cache file name."), encodeOfflineCache(document))
    val written = writeImages(fileName, images, nowMs)
    var entries = readIndex().toMutableList()
    val previous = entries.filter { entry -> sameConversation(entry, key, conversationId) }
    val previousImages = previous.flatMap { entry -> entry.images }
    entries.removeAll { entry -> sameConversation(entry, key, conversationId) }
    val keptImages = mergeImageNotes(previousImages, written)
    entries += CacheIndexEntry(
      key,
      projectRoot,
      conversationId,
      title,
      nowMs,
      cacheTurnCount(document),
      fileName,
      keptImages,
      epoch,
      cursor
    )
    val dropped = evictConversations(entries, key)
    entries = dropped.kept
    val imageDrop = evictImages(entries, key)
    entries = imageDrop.entries
    writeAtomic(File(directory, CacheIndexFileName), encodeCacheIndex(entries))
    for (entry in dropped.removed) deleteConversation(entry.fileName)
    for (gone in imageDrop.files) gone.delete()
    retireLegacyFile()
  }

  fun saveClosed(
    fingerprint: String,
    projectRoot: String,
    conversationId: String,
    title: String,
    documentText: String,
    images: List<CacheImageBytes> = emptyList(),
    epoch: String = "",
    cursor: Long = 0
  ) {
    val document = decodeClosedScreen(documentText) ?: return
    val shown = title.ifEmpty { cacheTitle("", document.turns, document.live, document.history) }
    save(fingerprint, projectRoot, conversationId, shown, document, images, clock(), epoch, cursor)
  }

  fun forgetFingerprint(fingerprint: String) = synchronized(gate) {
    val key = cacheFingerprint(fingerprint)
    val entries = readIndex()
    val kept = indexWithoutFingerprint(entries, key) { cacheFingerprint(it) }
    val removed = entries.filter { entry -> cacheFingerprint(entry.fingerprint) == key }
    if (removed.isEmpty() && kept.size == entries.size) return
    if (directory.isDirectory || kept.isNotEmpty()) {
      if (!directory.isDirectory) directory.mkdirs()
      writeAtomic(File(directory, CacheIndexFileName), encodeCacheIndex(kept))
    }
    for (entry in removed) deleteConversation(entry.fileName)
  }

  private fun writeImages(fileName: String, images: List<CacheImageBytes>, nowMs: Long): List<CacheImageNote> {
    val notes = ArrayList<CacheImageNote>()
    for ((index, image) in images.withIndex()) {
      val target = imageFile(fileName, image.imageId) ?: continue
      try {
        writeAtomicBytes(target, image.bytes)
        val stamp = nowMs + index
        target.setLastModified(stamp)
        notes += CacheImageNote(image.imageId, image.bytes.size.toLong(), stamp)
      } catch (error: Exception) {
        // A missing image file stays a placeholder.
      }
    }
    return notes
  }

  private data class ConversationEviction(val kept: MutableList<CacheIndexEntry>, val removed: List<CacheIndexEntry>)
  private data class ImageEviction(val entries: MutableList<CacheIndexEntry>, val files: List<File>)

  private fun evictConversations(entries: MutableList<CacheIndexEntry>, fingerprint: String): ConversationEviction {
    val mine = entries.filter { entry -> entry.fingerprint == fingerprint }
    if (mine.size <= conversationCap) return ConversationEviction(entries, emptyList())
    val oldest = mine.sortedWith(compareBy<CacheIndexEntry> { it.updatedMs }.thenBy { it.fileName })
    val removed = oldest.take(mine.size - conversationCap)
    val names = removed.map { entry -> entry.fileName }.toSet()
    return ConversationEviction(entries.filter { entry -> entry.fileName !in names }.toMutableList(), removed)
  }

  private fun evictImages(entries: MutableList<CacheIndexEntry>, fingerprint: String): ImageEviction {
    data class Aged(val fileName: String, val note: CacheImageNote, val file: File)
    val present = entries.map { entry ->
      entry.copy(images = entry.images.filter { note ->
        val file = imageFile(entry.fileName, note.imageId)
        file != null && file.isFile
      })
    }.toMutableList()
    val aged = ArrayList<Aged>()
    for (entry in present) {
      if (entry.fingerprint != fingerprint) continue
      for (note in entry.images) {
        val file = imageFile(entry.fileName, note.imageId) ?: continue
        if (!file.isFile) continue
        aged += Aged(entry.fileName, note, file)
      }
    }
    aged.sortWith(compareBy<Aged> { it.note.modifiedMs }.thenBy { it.note.imageId })
    var total = 0L
    for (item in aged) total += item.file.length()
    val drop = ArrayList<Aged>()
    for (item in aged) {
      if (total <= imageBudgetBytes) break
      drop += item
      total -= item.file.length()
    }
    if (drop.isEmpty()) return ImageEviction(present, emptyList())
    val droppedIds = drop.groupBy { it.fileName }.mapValues { (_, items) -> items.map { it.note.imageId }.toSet() }
    val next = present.map { entry ->
      val gone = droppedIds[entry.fileName] ?: return@map entry
      entry.copy(images = entry.images.filter { note -> note.imageId !in gone })
    }.toMutableList()
    return ImageEviction(next, drop.map { it.file })
  }

  private fun mergeImageNotes(previous: List<CacheImageNote>, written: List<CacheImageNote>): List<CacheImageNote> {
    val replaced = written.map { note -> note.imageId }.toSet()
    return previous.filter { note -> note.imageId !in replaced } + written
  }

  private fun sameConversation(entry: CacheIndexEntry, fingerprint: String, conversationId: String): Boolean {
    return entry.fingerprint == fingerprint && entry.conversationId == conversationId
  }

  private fun readIndex(): List<CacheIndexEntry> {
    val file = File(directory, CacheIndexFileName)
    if (!file.isFile) return emptyList()
    return try {
      decodeCacheIndex(file.readText()) ?: emptyList()
    } catch (error: Exception) {
      emptyList()
    }
  }

  private fun retireLegacyFile() {
    val temporary = File(filesDir, LegacyOfflineCacheName + ".tmp")
    if (legacyFile.isFile) legacyFile.delete()
    if (temporary.isFile) temporary.delete()
  }

  private fun deleteConversation(fileName: String) {
    conversationFile(fileName)?.delete()
    val stem = fileName.removeSuffix(".json")
    val images = childFile(stem)
    if (images != null && images.isDirectory) images.deleteRecursively()
  }

  private fun conversationFile(fileName: String): File? {
    if (!cacheFileNameIsSafe(fileName)) return null
    return childFile(fileName)
  }

  private fun imageFile(fileName: String, imageId: String): File? {
    val stem = fileName.removeSuffix(".json")
    if (!cacheStemIsSafe(stem)) return null
    val name = cacheImageFileName(imageId)
    if (!safeImageToken(name)) return null
    val folder = childFile(stem) ?: return null
    val file = File(folder, name)
    return try {
      if (file.parentFile?.canonicalFile != folder.canonicalFile) null else file
    } catch (error: Exception) {
      null
    }
  }

  private fun childFile(name: String): File? {
    if (name.isEmpty() || name == "." || name == ".." || name.contains('/') || name.contains('\\')) return null
    val file = File(directory, name)
    return try {
      if (file.parentFile?.canonicalFile != directory.canonicalFile) null else file
    } catch (error: Exception) {
      null
    }
  }

  private fun writeAtomic(target: File, text: String) {
    val parent = target.parentFile ?: throw IOException("No parent for " + target.name)
    if (!parent.isDirectory && !parent.mkdirs() && !parent.isDirectory) throw IOException("Could not create " + parent.path)
    val temporary = File(parent, target.name + ".tmp")
    temporary.writeText(text)
    if (!temporary.renameTo(target)) {
      target.writeText(text)
      temporary.delete()
    }
  }

  private fun writeAtomicBytes(target: File, bytes: ByteArray) {
    val parent = target.parentFile ?: throw IOException("No parent for " + target.name)
    if (!parent.isDirectory && !parent.mkdirs() && !parent.isDirectory) throw IOException("Could not create " + parent.path)
    val temporary = File(parent, target.name + ".tmp")
    temporary.writeBytes(bytes)
    if (!temporary.renameTo(target)) {
      target.writeBytes(bytes)
      temporary.delete()
    }
  }
}

private fun safeImageToken(text: String): Boolean {
  if (text.isEmpty() || text.length > 80 || text == "." || text == "..") return false
  for (ch in text) {
    val ok = ch.isLetterOrDigit() || ch == '-' || ch == '_' || ch == '.'
    if (!ok) return false
  }
  return true
}
