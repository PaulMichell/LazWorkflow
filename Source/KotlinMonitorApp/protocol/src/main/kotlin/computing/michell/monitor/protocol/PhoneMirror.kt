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
  val title: String = ""
)

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

/** Replace a block with the same id. Every other block stays. */
fun mergePatchBlocks(existing: List<WireBlock>, incoming: List<WireBlock>): List<WireBlock> {
  if (incoming.isEmpty()) return existing
  val result = existing.toMutableList()
  for (block in incoming) {
    val index = if (block.blockId.isEmpty()) -1 else result.indexOfFirst { item ->
      item.blockId == block.blockId && item.kind == block.kind
    }
    if (index >= 0) result[index] = block else result += block
  }
  return result
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
    blocks = merged,
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
    fileClosedId = ""
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
