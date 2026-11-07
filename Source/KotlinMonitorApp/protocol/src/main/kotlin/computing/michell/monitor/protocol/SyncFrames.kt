package computing.michell.monitor.protocol

/* Catalogue 3 sync frames the phone applies by cursor (c) 2026 Michell Computing.

   All monitor envelopes use catalogue 3. This file does not paint a screen. */

const val FnvOffsetBasis = 14695981039346656037uL
const val FnvPrime = 1099511628211uL
const val EmptyPrefixHash = "cbf29ce484222325"

fun fnv1a64(bytes: ByteArray): String {
  var hash = FnvOffsetBasis
  for (raw in bytes) {
    hash = hash xor (raw.toULong() and 0xFFu)
    hash *= FnvPrime
  }
  return hash.toString(16).padStart(16, '0')
}

/** FNV-1a 64 of the UTF-8 prefix before `offset`. Offset 0 is the basis. */
fun prefixHash(text: String): String {
  if (text.isEmpty()) return EmptyPrefixHash
  return fnv1a64(text.toByteArray(Charsets.UTF_8))
}

fun encodeSyncBlockGet(id: String, conversationId: String, blockId: String, offset: Int, prefixHash: String): String {
  val payload = JsonObjectBuilder()
  payload.add("conversation_id", conversationId)
  payload.add("block_id", blockId)
  payload.add("offset", offset)
  payload.add("prefix_hash", if (prefixHash.isEmpty()) EmptyPrefixHash else prefixHash)
  return encodeEnvelope(MessageKind.BlockGet, id, payload.build())
}

fun encodePlanGet(id: String, path: String, offset: Long, revision: String): String {
  val payload = JsonObjectBuilder()
  payload.add("path", path)
  payload.add("offset", offset)
  payload.add("revision", revision)
  return encodeNamedEnvelope("plan_get", id, payload.build())
}

fun encodeSyncResume(id: String, conversationId: String, streamId: String, seq: Long): String {
  val payload = JsonObjectBuilder()
  payload.add("conversation_id", conversationId)
  payload.add("stream_id", streamId)
  payload.add("epoch", streamId)
  payload.add("seq", seq)
  payload.add("cursor", seq)
  return encodeEnvelope(MessageKind.Resume, id, payload.build())
}

data class OutlineBlock(
  val blockId: String,
  val kind: String,
  val state: String,
  val revision: Long,
  val bodyBytes: Int,
  val hash: String
)

data class OutlineTurn(
  val turnId: String,
  val turnIndex: Int,
  val promptPreview: String,
  val blocks: List<OutlineBlock>
)

data class OpenBlockBody(
  val blockId: String,
  val revision: Long,
  val body: String,
  val bodyBytes: Int,
  val hash: String
)

sealed class SyncFrame {
  data class Event(val event: MonitorEvent, val wireBytes: Int) : SyncFrame()
  data class State(val key: String, val valueJson: String) : SyncFrame()
  data class SnapshotBegin(
    val conversationId: String,
    val streamId: String,
    val seq: Long,
    val title: String,
    val projectRoot: String,
    val pageCount: Int,
    val turns: List<OutlineTurn>,
    val openBlock: OpenBlockBody?,
    val state: List<Pair<String, String>>
  ) : SyncFrame()
  data class SnapshotPage(
    val conversationId: String,
    val streamId: String,
    val seq: Long,
    val page: Int,
    val pageCount: Int,
    val turns: List<OutlineTurn>,
    val turn: WireTurn?
  ) : SyncFrame()
  data class SnapshotEnd(val conversationId: String, val streamId: String, val seq: Long) : SyncFrame()
  data class BlockData(
    val conversationId: String,
    val blockId: String,
    val ref: String,
    val revision: Long,
    val hasRevision: Boolean,
    val offset: Int,
    val text: String,
    val totalBytes: Int,
    val last: Boolean
  ) : SyncFrame()
  data class NotReady(val conversationId: String) : SyncFrame()
  data class ResumeOk(val conversationId: String, val streamId: String, val fromSeq: Long) : SyncFrame()
  data class RevisionChanged(val ref: String) : SyncFrame()
  data class PlanData(
    val path: String,
    val revision: String,
    val offset: Long,
    val text: String,
    val totalBytes: Long,
    val last: Boolean
  ) : SyncFrame()
  data class StateChunk(val key: String, val part: Int, val partCount: Int, val data: String) : SyncFrame()
}

/** Null when this frame is not a sync frame. Catalogue 2 control still uses the other decoder. */
fun decodeSyncEnvelope(json: String): SyncFrame? {
  val root = parseObject(json) ?: return null
  val version = root.readInt("v", true)
  if (!version.ok || version.value != MonitorLimits.CatalogueVersion) return null
  val typeName = root.readString("type", true)
  val payload = root.field("payload") as? JsonValue.Obj
  if (!typeName.ok || payload == null) return null
  return when (typeName.value) {
    "event" -> {
      val event = decodeMonitorEvent(payload.toFpJson()) ?: return null
      SyncFrame.Event(event, utf8Length(json))
    }
    "state" -> decodeStateFrame(payload)
    "chunk" -> decodeStateChunk(payload)
    "snapshot_begin" -> decodeSnapshotBegin(payload)
    "snapshot_page" -> decodeSyncSnapshotPage(payload)
    "snapshot_end" -> decodeSnapshotEnd(payload)
    "block_data" -> decodeSyncBlockData(payload)
    "plan_data" -> decodePlanData(payload)
    "not_ready" -> {
      val id = payload.readString("conversation_id", false)
      if (!id.ok) null else SyncFrame.NotReady(id.value)
    }
    "resume_ok" -> {
      val id = payload.readString("conversation_id", false)
      val stream = payload.readString("stream_id", false)
      val from = payload.readLong("from_seq", false)
      if (!id.ok || !stream.ok || !from.ok) null
      else SyncFrame.ResumeOk(id.value, stream.value, from.value)
    }
    "error" -> {
      val reason = payload.readString("reason", false)
      val ref = payload.readString("ref", false)
      if (!reason.ok || reason.value != "revision_changed") null
      else SyncFrame.RevisionChanged(if (ref.ok) ref.value else "")
    }
    else -> null
  }
}

fun jsonObject(text: String): JsonValue.Obj? = parseObject(text)

fun JsonValue.Obj.textField(name: String): String? {
  val read = readString(name, false)
  if (!read.ok || !has(name)) return null
  return read.value
}

fun JsonValue.Obj.flagField(name: String): Boolean? {
  val read = readBool(name, false)
  if (!read.ok || !has(name)) return null
  return read.value
}

fun JsonValue.Obj.intField(name: String): Int? {
  val read = readInt(name, false)
  if (!read.ok || !has(name)) return null
  return read.value
}

fun JsonValue.Obj.longField(name: String): Long? {
  val read = readLong(name, false)
  if (!read.ok || !has(name)) return null
  return read.value
}

fun JsonValue.Obj.objectField(name: String): JsonValue.Obj? = field(name) as? JsonValue.Obj

fun JsonValue.Obj.arrayField(name: String): List<JsonValue>? = (field(name) as? JsonValue.Arr)?.items

private fun decodeStateFrame(payload: JsonValue.Obj): SyncFrame.State? {
  val key = payload.readString("key", true)
  val value = payload.field("value") ?: return null
  if (!key.ok || key.value.isEmpty()) return null
  val json = if (value is JsonValue.Obj || value is JsonValue.Arr) value.toFpJson() else return null
  return SyncFrame.State(key.value, json)
}

private fun decodeStateChunk(payload: JsonValue.Obj): SyncFrame.StateChunk? {
  val itemType = payload.readString("item_type", false)
  if (itemType.value.isNotEmpty() && itemType.value != "state") return null
  val key = payload.readString("item_id", true)
  val part = payload.readInt("part", true)
  val partCount = payload.readInt("part_count", true)
  val data = payload.readString("data", true)
  if (!key.ok || !part.ok || !partCount.ok || !data.ok) return null
  if (part.value !in 1..partCount.value) return null
  return SyncFrame.StateChunk(key.value, part.value, partCount.value, data.value)
}

private fun decodeSnapshotBegin(payload: JsonValue.Obj): SyncFrame.SnapshotBegin? {
  val id = payload.readString("conversation_id", true)
  val stream = payload.readString("stream_id", true)
  val seq = payload.readLong("seq", true)
  if (!id.ok || !stream.ok || !seq.ok) return null
  val pageCount = payload.readInt("page_count", false)
  return SyncFrame.SnapshotBegin(
    id.value,
    stream.value,
    seq.value,
    payload.readString("title", false).value,
    payload.readString("project_root", false).value,
    if (pageCount.ok) pageCount.value else 0,
    outlineTurns(payload.field("turns")),
    openBlock(payload.objectField("open_block")),
    statePairs(payload.objectField("state"))
  )
}

private fun decodeSyncSnapshotPage(payload: JsonValue.Obj): SyncFrame.SnapshotPage? {
  val id = payload.readString("conversation_id", false)
  val stream = payload.readString("stream_id", false)
  val seq = payload.readLong("seq", false)
  if (!id.ok || !stream.ok || !seq.ok) return null
  val page = payload.readInt("page", false)
  val pageCount = payload.readInt("page_count", false)
  val turn = if (payload.field("turn") == null) null else snapshotPageTurn(payload.toFpJson())
  return SyncFrame.SnapshotPage(
    id.value,
    stream.value,
    seq.value,
    if (page.ok) page.value else 0,
    if (pageCount.ok) pageCount.value else 0,
    outlineTurns(payload.field("turns")),
    turn
  )
}

private fun decodeSnapshotEnd(payload: JsonValue.Obj): SyncFrame.SnapshotEnd? {
  val id = payload.readString("conversation_id", true)
  val stream = payload.readString("stream_id", true)
  val seq = payload.readLong("seq", true)
  if (!id.ok || !stream.ok || !seq.ok) return null
  return SyncFrame.SnapshotEnd(id.value, stream.value, seq.value)
}

private fun decodePlanData(payload: JsonValue.Obj): SyncFrame.PlanData? {
  val path = payload.readString("path", true)
  val revision = payload.readString("revision", true)
  val offset = payload.readLong("offset", true)
  val text = payload.readString("text", false)
  val total = payload.readLong("total_bytes", true)
  val last = payload.readBool("last", true)
  if (!path.ok || !revision.ok || !offset.ok || !text.ok || !total.ok || !last.ok || offset.value < 0) return null
  return SyncFrame.PlanData(path.value, revision.value, offset.value, text.value, total.value, last.value)
}

private fun decodeSyncBlockData(payload: JsonValue.Obj): SyncFrame.BlockData? {
  val blockId = payload.readString("block_id", true)
  val text = payload.readString("text", true)
  val offset = payload.readInt("offset", true)
  val total = payload.readInt("total_bytes", true)
  val last = payload.readBool("last", true)
  if (!blockId.ok || !text.ok || !offset.ok || !total.ok || !last.ok || offset.value < 0) return null
  val revision = payload.readLong("revision", false)
  return SyncFrame.BlockData(
    payload.readString("conversation_id", false).value,
    blockId.value,
    payload.readString("ref", false).value,
    revision.value,
    payload.has("revision") && revision.ok,
    offset.value,
    text.value,
    total.value,
    last.value
  )
}

private fun outlineTurns(node: JsonValue?): List<OutlineTurn> {
  val array = node as? JsonValue.Arr ?: return emptyList()
  val turns = ArrayList<OutlineTurn>()
  for (item in array.items) {
    val row = item as? JsonValue.Obj ?: continue
    val turnId = row.readString("turn_id", true)
    val index = row.readInt("turn_index", false)
    if (!turnId.ok || turnId.value.isEmpty()) continue
    val blocks = ArrayList<OutlineBlock>()
    val rawBlocks = row.field("blocks") as? JsonValue.Arr
    if (rawBlocks != null) {
      for (blockNode in rawBlocks.items) {
        val block = blockNode as? JsonValue.Obj ?: continue
        val blockId = block.readString("block_id", true)
        if (!blockId.ok || blockId.value.isEmpty()) continue
        blocks += OutlineBlock(
          blockId.value,
          block.readString("kind", false).value,
          block.readString("state", false).value,
          block.readLong("revision", false).value,
          block.readInt("body_bytes", false).value,
          block.readString("hash", false).value
        )
      }
    }
    turns += OutlineTurn(turnId.value, if (index.ok) index.value else 0, row.readString("prompt_preview", false).value, blocks)
  }
  return turns
}

private fun openBlock(row: JsonValue.Obj?): OpenBlockBody? {
  if (row == null) return null
  val blockId = row.readString("block_id", true)
  val body = row.readString("body", false)
  if (!blockId.ok || blockId.value.isEmpty() || !body.ok) return null
  return OpenBlockBody(
    blockId.value,
    row.readLong("revision", false).value,
    body.value,
    row.readInt("body_bytes", false).value,
    row.readString("hash", false).value
  )
}

private fun statePairs(row: JsonValue.Obj?): List<Pair<String, String>> {
  if (row == null) return emptyList()
  val pairs = ArrayList<Pair<String, String>>()
  for ((key, value) in row.fields) {
    if (value is JsonValue.Obj || value is JsonValue.Arr) pairs += key to value.toFpJson()
  }
  return pairs
}
