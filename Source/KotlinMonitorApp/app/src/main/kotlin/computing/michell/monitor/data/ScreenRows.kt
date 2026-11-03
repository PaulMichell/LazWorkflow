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
  val pictures = images.map { image -> wireImage(image) }
  val byTurn = blocks.groupBy { block -> block.turn }
  val wire = turns.sortedBy { turn -> turn.ordinal }.map { turn ->
    val turnRunning = turn.outcome == "running"
    val bodies = (byTurn[turn.turnId] ?: emptyList()).sortedBy { block -> block.ordinal }.map { block ->
      WireBlock(
        block.kind,
        block.blockId,
        block.title,
        "",
        "",
        block.body,
        turnRunning && block.state == "running",
        block.state == "ok",
        0,
        emptyList(),
        deferred = block.blockId in stale
      )
    }
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
      "note", "stored-images", "", "", "", "", false, true, 0, pictures
    ))
  return OfflineCacheDocument(withPictures, withPictures, withPictures.lastOrNull { turn -> turn.live }, "", "", emptyList(), -1, "")
}

fun wireImage(image: ImageRecord): WireImage {
  val present = image.filePath.isNotEmpty() && File(image.filePath).isFile
  return WireImage(image.id, image.id, image.mime, 0, 0, image.filePath, !present)
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
