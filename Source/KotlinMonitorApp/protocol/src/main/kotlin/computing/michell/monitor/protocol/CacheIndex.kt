package computing.michell.monitor.protocol

/* Local monitor-cache index. Not a catalogue frame. (c) 2026 Michell Computing. */

data class CacheImageNote(
  val imageId: String,
  val bytes: Long,
  val modifiedMs: Long
)

data class CacheIndexEntry(
  val fingerprint: String,
  val projectRoot: String,
  val conversationId: String,
  val title: String,
  val updatedMs: Long,
  val turnCount: Int,
  val fileName: String,
  val images: List<CacheImageNote> = emptyList()
)

fun encodeCacheIndex(entries: List<CacheIndexEntry>): String {
  val rows = entries.map { entry ->
    val obj = JsonObjectBuilder()
    obj.add("fingerprint", entry.fingerprint)
    obj.add("project_root", entry.projectRoot)
    obj.add("conversation_id", entry.conversationId)
    obj.add("title", entry.title)
    obj.add("updated_ms", entry.updatedMs)
    obj.add("turn_count", entry.turnCount)
    obj.add("file", entry.fileName)
    obj.add("images", JsonValue.Arr(entry.images.map { imageNoteToJson(it) }))
    obj.build()
  }
  val root = JsonObjectBuilder()
  root.add("entries", JsonValue.Arr(rows))
  return root.build().toFpJson()
}

/** Null means the index cannot be read. The caller starts empty and does not crash. */
fun decodeCacheIndex(text: String): List<CacheIndexEntry>? {
  val obj = parseObject(text) ?: return null
  val array = obj.field("entries") as? JsonValue.Arr ?: return null
  val entries = ArrayList<CacheIndexEntry>(array.items.size)
  for (item in array.items) {
    val row = item as? JsonValue.Obj ?: return null
    val fingerprint = row.readString("fingerprint", true)
    val projectRoot = row.readString("project_root", true)
    val conversationId = row.readString("conversation_id", true)
    val title = row.readString("title", true)
    val updated = row.readLong("updated_ms", true)
    val turnCount = row.readInt("turn_count", true)
    val fileName = row.readString("file", true)
    if (!fingerprint.ok || !projectRoot.ok || !conversationId.ok || !title.ok || !updated.ok || !turnCount.ok || !fileName.ok) {
      return null
    }
    if (!cacheFileNameIsSafe(fileName.value)) return null
    val images = imageNotesFrom(row.field("images")) ?: return null
    entries += CacheIndexEntry(
      fingerprint.value,
      projectRoot.value,
      conversationId.value,
      title.value,
      updated.value,
      turnCount.value,
      fileName.value,
      images
    )
  }
  return entries
}

fun cacheFileNameIsSafe(name: String): Boolean {
  if (!name.endsWith(".json")) return false
  val stem = name.removeSuffix(".json")
  return cacheStemIsSafe(stem)
}

fun cacheStemIsSafe(stem: String): Boolean {
  if (!stem.startsWith("c-") || stem.length < 4 || stem.length > 70) return false
  for (ch in stem) {
    val ok = ch.isLetterOrDigit() || ch == '-' || ch == '_'
    if (!ok) return false
  }
  return true
}

private fun imageNoteToJson(note: CacheImageNote): JsonValue.Obj {
  val obj = JsonObjectBuilder()
  obj.add("id", note.imageId)
  obj.add("bytes", note.bytes)
  obj.add("modified_ms", note.modifiedMs)
  return obj.build()
}

private fun imageNotesFrom(node: JsonValue?): List<CacheImageNote>? {
  if (node == null) return emptyList()
  val array = node as? JsonValue.Arr ?: return null
  val notes = ArrayList<CacheImageNote>(array.items.size)
  for (item in array.items) {
    val row = item as? JsonValue.Obj ?: return null
    val id = row.readString("id", true)
    val bytes = row.readLong("bytes", true)
    val modified = row.readLong("modified_ms", true)
    if (!id.ok || !bytes.ok || !modified.ok || id.value.isEmpty()) return null
    notes += CacheImageNote(id.value, bytes.value, modified.value)
  }
  return notes
}
