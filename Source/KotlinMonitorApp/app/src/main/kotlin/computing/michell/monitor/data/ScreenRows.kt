package computing.michell.monitor.data

/* Map a retired cache document onto Room rows (c) 2026 Michell Computing.

   The imported cursor is always zero. A later save keeps a cursor the sync
   applier has already advanced. Plan rows are a host cache, not turn
   columns. The unsent draft is not stored. */

import computing.michell.monitor.protocol.OfflineCacheDocument
import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireImage
import computing.michell.monitor.protocol.WireTurn
import java.io.File

/** The note at the end that holds pictures whose turn is not known. */
const val StoredImagesBlockId = "stored-images"

data class StoredScreen(
  val conversation: ConversationRecord,
  val turns: List<TurnRecord>,
  val blocks: List<BlockRecord>
)

fun storedScreen(
  host: String,
  conversationId: String,
  projectRoot: String,
  title: String,
  updatedAt: Long,
  document: OfflineCacheDocument,
  seq: Long,
  streamId: String
): StoredScreen {
  val merged = mergedTurns(document)
  val turns = ArrayList<TurnRecord>(merged.size)
  val blocks = ArrayList<BlockRecord>()
  val seen = HashSet<String>()
  for (turn in merged) {
    var turnId = turn.id.ifEmpty { "t-" + turn.turnIndex }
    if (!seen.add(turnId)) turnId = turnId + "-" + turn.turnIndex
    val live = document.live
    val running = live != null && live.turnIndex == turn.turnIndex && live.live
    turns += TurnRecord(
      host,
      conversationId,
      turnId,
      turn.turnIndex,
      turn.mode,
      turn.prompt.ifEmpty { turn.promptPreview },
      turn.createdAt,
      if (running) "running" else if (turn.errorText.isNotEmpty()) "failed" else "done",
      turn.durationMs,
      turn.errorText
    )
    blocks += blockRows(host, conversationId, turnId, turn)
  }
  val shown = title.ifEmpty { turns.firstOrNull()?.prompt ?: conversationId }
  return StoredScreen(
    ConversationRecord(conversationId, host, projectRoot, shown, streamId, seq, updatedAt, false),
    turns,
    blocks
  )
}

fun documentFromRows(
  turns: List<TurnRecord>,
  blocks: List<BlockRecord>,
  repairs: List<BlockRepairRecord> = emptyList(),
  images: List<ImageRecord> = emptyList()
): OfflineCacheDocument {
  val stale = repairs.filter { repair -> repair.missingBody || repair.stale }.map { repair -> repair.blockId }.toSet()
  val byTurn = blocks.groupBy { block -> block.turn }
  // A picture is drawn on the block that showed it on the desktop. A notice with no block puts it on its turn's
  // prompt. A row from before schema 5 names neither, and goes in one note at the end as before.
  val blockIds = blocks.map { block -> block.blockId }.toSet()
  val turnIds = turns.map { turn -> turn.turnId }.toSet()
  val onBlock = HashMap<String, MutableList<WireImage>>()
  val onTurn = HashMap<String, MutableList<WireImage>>()
  val pictures = ArrayList<WireImage>()
  for (image in images) {
    val picture = wireImage(image)
    when {
      image.block.isNotEmpty() && image.block in blockIds -> onBlock.getOrPut(image.block) { ArrayList() } += picture
      image.turn.isNotEmpty() && image.turn in turnIds -> onTurn.getOrPut(image.turn) { ArrayList() } += picture
      else -> pictures += picture
    }
  }
  val wire = turns.sortedBy { turn -> turn.ordinal }.map { turn ->
    val sorted = (byTurn[turn.turnId] ?: emptyList()).sortedBy { block -> block.ordinal }
    val promptBlock = (sorted.firstOrNull { block -> block.kind == "user" } ?: sorted.firstOrNull())?.blockId
    val turnPictures = onTurn[turn.turnId] ?: emptyList<WireImage>()
    if (promptBlock == null) pictures += turnPictures
    val bodies = sorted.map { block ->
      val running = block.state == "running" || (turn.outcome == "running" && block.state.isEmpty())
      val shown = (onBlock[block.blockId] ?: emptyList<WireImage>()) +
        (if (block.blockId == promptBlock) turnPictures else emptyList())
      WireBlock(
        block.kind,
        block.blockId,
        block.title,
        "",
        "",
        block.body,
        running,
        block.state == "ok",
        0,
        shown,
        deferred = block.blockId in stale
      )
    }
    val turnRunning = turn.outcome == "running" || bodies.any { block -> block.running }
    val response = bodies.firstOrNull { block -> block.kind == "answer" }?.body ?: ""
    WireTurn(
      turn.ordinal,
      turn.turnId,
      turn.mode,
      turn.createdAt,
      turn.prompt,
      turn.errorText,
      prompt = turn.prompt,
      response = response,
      durationMs = turn.durationMs,
      live = turnRunning,
      blocks = bodies
    )
  }
  val withPictures = if (pictures.isEmpty() || wire.isEmpty()) wire
    else wire.dropLast(1) + wire.last().copy(blocks = wire.last().blocks + WireBlock(
      "note", StoredImagesBlockId, "", "", "", "", false, true, 0, pictures
    ))
  return OfflineCacheDocument(withPictures, withPictures, withPictures.lastOrNull { turn -> turn.live }, "", "", emptyList(), -1, "")
}

/** A picture not fetched yet has no path. It is not missing: the tile says it is loading until the file arrives. */
fun wireImage(image: ImageRecord): WireImage {
  val present = image.filePath.isNotEmpty() && File(image.filePath).isFile
  return WireImage(image.id, image.id, image.mime, 0, 0, if (present) image.filePath else "", false)
}

private fun mergedTurns(document: OfflineCacheDocument): List<WireTurn> {
  val byIndex = LinkedHashMap<Int, WireTurn>()
  for (turn in document.turns) byIndex[turn.turnIndex] = richer(byIndex[turn.turnIndex], turn)
  for (turn in document.history) byIndex[turn.turnIndex] = richer(byIndex[turn.turnIndex], turn)
  val live = document.live
  if (live != null) byIndex[live.turnIndex] = richer(byIndex[live.turnIndex], live)
  return byIndex.values.sortedBy { turn -> turn.turnIndex }
}

private fun richer(current: WireTurn?, incoming: WireTurn): WireTurn {
  if (current == null) return incoming
  if (incoming.blocks.isNotEmpty() || incoming.response.isNotEmpty() || incoming.thinking.isNotEmpty()) return incoming
  return current
}

private fun blockRows(host: String, conversationId: String, turnId: String, turn: WireTurn): List<BlockRecord> {
  val source = ArrayList<WireBlock>()
  if (turn.blocks.isNotEmpty()) source += turn.blocks
  else {
    if (turn.thinking.isNotEmpty()) source += WireBlock("thinking", "", "", "", "", turn.thinking, false, true, 0, emptyList())
    if (turn.response.isNotEmpty()) source += WireBlock("answer", "", "", "", "", turn.response, turn.live, !turn.live, turn.durationMs, emptyList())
  }
  return source.mapIndexed { ordinal, block ->
    val id = block.blockId.ifEmpty { "b-" + turnId + "-" + ordinal }
    val state = if (block.running) "running" else if (block.ok) "ok" else "failed"
    BlockRecord(host, conversationId, turnId, id, ordinal, block.kind, block.title, block.body, state)
  }
}
