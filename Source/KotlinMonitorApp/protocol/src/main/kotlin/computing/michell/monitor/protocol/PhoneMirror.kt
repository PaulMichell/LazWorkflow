package computing.michell.monitor.protocol

/* Phone mirror rules. A patch updates named blocks. A new epoch waits for catchup.
   No socket and no Android types. (c) 2026 Michell Computing. */

data class PhoneScreen(
  val epoch: String = "",
  val cursor: Long = 0,
  val catchingUp: Boolean = false,
  val announcedEpoch: String = "",
  val turns: List<WireTurn> = emptyList(),
  val live: WireTurn? = null,
  val patchOpenCursor: Long = 0,
  val patchPartCount: Int = 0,
  val patchParts: Map<Int, List<WireBlock>> = emptyMap(),
  val resumeOnce: Boolean = false,
  val closedId: String = "",
  val closedTitle: String = "",
  val fileClosedId: String = "",
  val conversationId: String = "",
  val projectRoot: String = "",
  val title: String = "",
  val blockFetchIds: List<String> = emptyList()
)

data class MergedBlocks(val blocks: List<WireBlock>, val fetchIds: List<String>)

const val AckIntervalMs = 250L

data class AckPace(
  val lastSentMs: Long = 0,
  val sentSeq: Long = -1,
  val pendingSeq: Long = -1
)

data class AckDecision(
  val pace: AckPace,
  val sendNow: String = "",
  val laterMs: Long = 0,
  val sendLater: String = "",
  val seq: Long = -1
)

/** At most one ack every 250 ms. The later frame carries the newest seq. */
fun paceAck(
  pace: AckPace,
  nowMs: Long,
  id: String,
  conversationId: String,
  streamId: String,
  seq: Long
): AckDecision {
  if (conversationId.isEmpty() || streamId.isEmpty() || seq < 0) return AckDecision(pace)
  if (seq <= pace.sentSeq) return AckDecision(pace)
  val json = encodeAck(id, conversationId, streamId, seq)
  val elapsed = if (pace.lastSentMs == 0L) AckIntervalMs else nowMs - pace.lastSentMs
  if (elapsed >= AckIntervalMs) {
    return AckDecision(pace.copy(lastSentMs = nowMs, sentSeq = seq, pendingSeq = -1), json, 0, "", seq)
  }
  return AckDecision(pace.copy(pendingSeq = seq), "", AckIntervalMs - elapsed, json, seq)
}

/** True when offset is the stored UTF-8 length. A mismatch does not change the body. */
fun applyBlockAppend(stored: String, offset: Int, text: String): Pair<String, Boolean> {
  if (offset < 0 || utf8Length(stored) != offset) return stored to false
  return stored + text to true
}

/** A stub that has not been opened. Load must not call open. */
class DisconnectedSocket {
  var opened: Boolean = false
    private set

  fun open() {
    opened = true
  }
}

class MemoryConversationLibrary {
  private val rows = LinkedHashMap<String, Pair<CacheIndexEntry, OfflineCacheDocument>>()

  fun save(entry: CacheIndexEntry, document: OfflineCacheDocument) {
    rows[entry.fileName] = entry to document
  }

  fun load(hostFingerprint: String, conversationId: String, socket: DisconnectedSocket): OfflineCacheDocument? {
    if (socket.opened) return null
    val row = rows.values.firstOrNull { pair ->
      pair.first.fingerprint == hostFingerprint && pair.first.conversationId == conversationId
    }
    return row?.second
  }

  fun forgetFingerprint(fingerprint: String, keyOf: (String) -> String = { it }) {
    val kept = indexWithoutFingerprint(rows.values.map { it.first }, fingerprint, keyOf)
    val names = kept.map { it.fileName }.toSet()
    val drop = rows.keys.filter { name -> name !in names }
    for (name in drop) rows.remove(name)
  }

  fun fingerprints(keyOf: (String) -> String = { it }): Set<String> {
    return rows.values.map { keyOf(it.first.fingerprint) }.toSet()
  }
}

fun indexWithoutFingerprint(
  entries: List<CacheIndexEntry>,
  fingerprintKey: String,
  keyOf: (String) -> String = { it }
): List<CacheIndexEntry> {
  return entries.filter { entry -> keyOf(entry.fingerprint) != fingerprintKey }
}

/** Replace a block with the same id. An append offset must match the stored UTF-8 length. */
fun mergePatchBlocks(existing: List<WireBlock>, incoming: List<WireBlock>): MergedBlocks {
  if (incoming.isEmpty()) return MergedBlocks(existing, emptyList())
  val result = existing.toMutableList()
  val fetches = mutableListOf<String>()
  for (block in incoming) {
    val index = if (block.blockId.isEmpty()) -1 else result.indexOfFirst { item ->
      item.blockId == block.blockId && item.kind == block.kind
    }
    val offset = block.appendOffset
    if (offset == null) {
      if (index >= 0) result[index] = block else result += block
    } else {
      val stored = if (index >= 0) result[index].body else ""
      val applied = applyBlockAppend(stored, offset, block.body)
      if (!applied.second) {
        if (block.blockId.isNotEmpty()) fetches += block.blockId
      } else {
        val updated = block.copy(body = applied.first, appendOffset = null)
        if (index >= 0) result[index] = updated else result += updated
      }
    }
  }
  return MergedBlocks(result, fetches)
}

fun notePhoneClosed(screen: PhoneScreen, id: String, title: String): PhoneScreen {
  if (id.isEmpty()) return screen.copy(fileClosedId = "")
  return screen.copy(closedId = id, closedTitle = title, fileClosedId = "")
}

/** Keeps the turns. Files a closed id only when this epoch is new. */
fun notePhoneEpoch(screen: PhoneScreen, epoch: String): PhoneScreen {
  if (epoch.isEmpty() || screen.epoch.isEmpty() || epoch == screen.epoch) return screen.copy(fileClosedId = "")
  val file = if (screen.closedId.isNotEmpty()) screen.closedId else ""
  return screen.copy(catchingUp = true, announcedEpoch = epoch, fileClosedId = file)
}

fun applyPhonePatch(screen: PhoneScreen, patch: WirePatch): PhoneScreen {
  if (patch.epoch.isEmpty()) return screen.copy(fileClosedId = "")
  if (screen.catchingUp) return screen.copy(fileClosedId = "")
  if (screen.epoch.isNotEmpty() && patch.epoch != screen.epoch) return notePhoneEpoch(screen, patch.epoch)
  val incomplete = screen.patchOpenCursor != 0L && screen.patchParts.size < screen.patchPartCount
  val acceptSame = incomplete && patch.cursor == screen.cursor && screen.patchOpenCursor == patch.cursor
  val acceptNext = patch.cursor == screen.cursor + 1L &&
    (screen.patchOpenCursor == 0L || screen.patchOpenCursor == patch.cursor)
  if (patch.cursor < screen.cursor + 1L && !acceptSame) return screen.copy(fileClosedId = "")
  if (!acceptNext && !acceptSame) {
    if (screen.resumeOnce) return screen.copy(fileClosedId = "")
    return screen.copy(resumeOnce = true, fileClosedId = "")
  }
  return storePart(screen, patch)
}

/** Catchup is the only step that replaces the turns. */
fun applyPhoneCatchup(
  screen: PhoneScreen,
  epoch: String,
  cursor: Long,
  conversationId: String,
  projectRoot: String,
  title: String,
  turns: List<WireTurn>,
  live: WireTurn?
): PhoneScreen {
  if (epoch.isEmpty()) return screen.copy(fileClosedId = "")
  return screen.copy(
    epoch = epoch,
    cursor = cursor,
    catchingUp = false,
    announcedEpoch = "",
    turns = turns,
    live = live,
    patchOpenCursor = 0,
    patchPartCount = 0,
    patchParts = emptyMap(),
    resumeOnce = false,
    fileClosedId = "",
    conversationId = if (conversationId.isNotEmpty()) conversationId else screen.conversationId,
    projectRoot = if (projectRoot.isNotEmpty()) projectRoot else screen.projectRoot,
    title = if (title.isNotEmpty()) title else screen.title
  )
}

private fun storePart(screen: PhoneScreen, patch: WirePatch): PhoneScreen {
  if (patch.part < 1 || patch.partCount < 1 || patch.part > patch.partCount) return screen.copy(fileClosedId = "")
  val sameOpen = screen.patchOpenCursor == patch.cursor
  if (sameOpen && screen.patchPartCount != 0 && patch.partCount != screen.patchPartCount) return screen.copy(fileClosedId = "")
  val prior = if (sameOpen) screen.patchParts else emptyMap()
  val stored = if (prior.containsKey(patch.part)) prior else prior + (patch.part to patch.blocks)
  val assembled = assembleParts(stored, patch.partCount)
  val merged = mergePatchBlocks(screen.live?.blocks.orEmpty(), assembled)
  val complete = (1..patch.partCount).all { part -> stored.containsKey(part) }
  val previous = screen.live
  val live = WireTurn(
    turnIndex = if (patch.turnIndex != 0) patch.turnIndex else previous?.turnIndex ?: -2,
    id = patch.turnId.ifEmpty { previous?.id ?: "" },
    mode = previous?.mode ?: "",
    createdAt = previous?.createdAt ?: "",
    promptPreview = previous?.promptPreview ?: "",
    errorText = previous?.errorText ?: "",
    prompt = previous?.prompt ?: "",
    thinking = previous?.thinking ?: "",
    response = previous?.response ?: "",
    live = true,
    blocks = merged.blocks,
    images = previous?.images ?: emptyList()
  )
  return screen.copy(
    epoch = patch.epoch,
    cursor = if (complete) patch.cursor else screen.cursor,
    live = live,
    patchOpenCursor = if (complete) 0L else patch.cursor,
    patchPartCount = if (complete) 0 else patch.partCount,
    patchParts = if (complete) emptyMap() else stored,
    resumeOnce = if (complete) false else screen.resumeOnce,
    fileClosedId = "",
    blockFetchIds = merged.fetchIds
  )
}

/** A block_data frame replaces from offset 0, or appends when offset is the stored length. */
fun applyBlockDataJson(screen: PhoneScreen, payloadJson: String): PhoneScreen {
  val obj = parseObject(payloadJson) ?: return screen
  val blockId = obj.readString("block_id", true)
  val offset = obj.readInt("offset", true)
  val text = obj.readString("text", true)
  if (!blockId.ok || !offset.ok || !text.ok) return screen
  return applyBlockData(screen, blockId.value, offset.value, text.value)
}

fun applyBlockData(screen: PhoneScreen, blockId: String, offset: Int, text: String): PhoneScreen {
  if (blockId.isEmpty() || offset < 0) return screen
  fun splice(stored: String): String? {
    if (offset == 0) return text
    if (utf8Length(stored) != offset) return null
    return stored + text
  }
  fun rewrite(blocks: List<WireBlock>): List<WireBlock> {
    return blocks.map { block ->
      if (block.blockId != blockId) block
      else {
        val body = splice(block.body) ?: return@map block
        block.copy(body = body)
      }
    }
  }
  return screen.copy(
    live = screen.live?.copy(blocks = rewrite(screen.live.blocks)),
    turns = screen.turns.map { turn -> turn.copy(blocks = rewrite(turn.blocks)) },
    blockFetchIds = emptyList()
  )
}

private fun assembleParts(parts: Map<Int, List<WireBlock>>, count: Int): List<WireBlock> {
  val blocks = mutableListOf<WireBlock>()
  for (part in 1..count) {
    val frame = parts[part] ?: continue
    for (block in frame) {
      val previous = blocks.lastOrNull()
      if (previous != null && previous.blockId.isNotEmpty() && previous.blockId == block.blockId && previous.kind == block.kind) {
        blocks[blocks.lastIndex] = previous.copy(body = previous.body + block.body)
      } else {
        blocks += block
      }
    }
  }
  return blocks
}
