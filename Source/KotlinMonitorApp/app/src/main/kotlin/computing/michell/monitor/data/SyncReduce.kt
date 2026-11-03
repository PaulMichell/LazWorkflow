package computing.michell.monitor.data

/* Apply one conversation's events onto the rows the batch names (c) 2026 Michell Computing.

   A seq at or below the stored cursor is a duplicate. A seq that skips ahead
   is a gap: later events in the batch are not applied, and rows already
   committed stay. The cursor moves only as far as the last event applied,
   including an append that is held until its block fetch finishes. */

import computing.michell.monitor.protocol.MonitorEvent
import computing.michell.monitor.protocol.utf8Length

data class SyncGap(
  val conversationId: String,
  val streamId: String,
  val seq: Long
)

data class BlockFetch(
  val conversationId: String,
  val blockId: String,
  val offset: Int = 0,
  val prefixHash: String = "",
  val requestId: String = ""
)

data class AppliedCursor(
  val conversationId: String,
  val streamId: String,
  val seq: Long
)

data class SyncCommit(
  val conversation: ConversationRecord,
  val turns: List<TurnRecord>,
  val blocks: List<BlockRecord>,
  val images: List<ImageRecord>,
  val repairs: List<BlockRepair> = emptyList(),
  val clearRepairIds: List<String> = emptyList(),
  val held: List<HeldAppend> = emptyList(),
  val dropHeldBlocks: List<String> = emptyList()
)

data class SyncReduce(
  val commit: SyncCommit?,
  val gap: SyncGap?,
  val fetches: List<BlockFetch>,
  val applied: AppliedCursor?
)

fun affectedTurnIds(events: List<MonitorEvent>): Set<String> {
  val ids = HashSet<String>()
  for (event in events) {
    when (event) {
      is MonitorEvent.TurnOpen -> ids += event.turnId
      is MonitorEvent.TurnClose -> ids += event.turnId
      is MonitorEvent.BlockOpen -> ids += event.turnId
      is MonitorEvent.ImageAdded -> ids += event.turnId
      else -> { }
    }
  }
  return ids
}

fun affectedBlockIds(events: List<MonitorEvent>): Set<String> {
  val ids = HashSet<String>()
  for (event in events) {
    when (event) {
      is MonitorEvent.BlockOpen -> ids += event.blockId
      is MonitorEvent.BlockAppend -> ids += event.blockId
      is MonitorEvent.BlockReplace -> ids += event.blockId
      is MonitorEvent.BlockClose -> ids += event.blockId
      is MonitorEvent.ImageAdded -> if (event.blockId.isNotEmpty()) ids += event.blockId
      else -> { }
    }
  }
  return ids
}

fun affectedImageIds(events: List<MonitorEvent>): Set<String> {
  val ids = HashSet<String>()
  for (event in events) {
    if (event is MonitorEvent.ImageAdded) ids += event.imageId
  }
  return ids
}

fun reduceSync(
  host: String,
  nowMs: Long,
  conversation: ConversationRecord?,
  turns: List<TurnRecord>,
  blocks: List<BlockRecord>,
  images: List<ImageRecord>,
  events: List<MonitorEvent>,
  repairs: List<BlockRepair> = emptyList(),
  held: List<HeldAppend> = emptyList()
): SyncReduce {
  if (events.isEmpty()) return SyncReduce(null, null, emptyList(), null)
  val conversationId = events.first().conversationId
  var seq = conversation?.seq ?: 0L
  var streamId = conversation?.streamId ?: ""
  var title = conversation?.title ?: ""
  var projectRoot = conversation?.projectRoot ?: ""
  var pinned = conversation?.pinned ?: false
  val turnMap = turns.associateBy { it.turnId }.toMutableMap()
  val blockMap = blocks.associateBy { it.blockId }.toMutableMap()
  val imageMap = images.associateBy { it.id }.toMutableMap()
  val repairMap = repairs.associateBy { it.blockId }.toMutableMap()
  val fetches = mutableListOf<BlockFetch>()
  val heldRows = mutableListOf<HeldAppend>()
  val clearRepairs = mutableListOf<String>()
  val dropHeld = mutableListOf<String>()
  val touchedTurns = HashSet<String>()
  val touchedBlocks = HashSet<String>()
  val touchedImages = HashSet<String>()
  var gap: SyncGap? = null
  var applied = false
  for (event in events.sortedBy { it.seq }) {
    if (event.conversationId != conversationId) continue
    if (streamId.isNotEmpty() && event.streamId != streamId) {
      gap = SyncGap(conversationId, streamId, seq)
      break
    }
    if (event.seq <= seq) continue
    if (event.seq != seq + 1L) {
      val resumeStream = if (streamId.isEmpty()) event.streamId else streamId
      gap = SyncGap(conversationId, resumeStream, seq)
      break
    }
    if (streamId.isEmpty()) streamId = event.streamId
    if (event is MonitorEvent.TitleChanged) title = event.title
    applyOne(
      host, conversationId, event, turnMap, blockMap, imageMap, repairMap, fetches, heldRows,
      clearRepairs, dropHeld, touchedTurns, touchedBlocks, touchedImages
    )
    seq = event.seq
    applied = true
  }
  if (!applied) return SyncReduce(null, gap, fetches, null)
  val row = ConversationRecord(conversationId, host, projectRoot, title, streamId, seq, nowMs, pinned)
  val commit = SyncCommit(
    row,
    touchedTurns.mapNotNull { id -> turnMap[id] },
    touchedBlocks.mapNotNull { id -> blockMap[id] },
    touchedImages.mapNotNull { id -> imageMap[id] },
    repairMap.values.toList(),
    clearRepairs,
    heldRows,
    dropHeld
  )
  return SyncReduce(commit, gap, fetches, AppliedCursor(conversationId, streamId, seq))
}

private fun applyOne(
  host: String,
  conversationId: String,
  event: MonitorEvent,
  turns: MutableMap<String, TurnRecord>,
  blocks: MutableMap<String, BlockRecord>,
  images: MutableMap<String, ImageRecord>,
  repairs: MutableMap<String, BlockRepair>,
  fetches: MutableList<BlockFetch>,
  held: MutableList<HeldAppend>,
  clearRepairs: MutableList<String>,
  dropHeld: MutableList<String>,
  touchedTurns: MutableSet<String>,
  touchedBlocks: MutableSet<String>,
  touchedImages: MutableSet<String>
) {
  when (event) {
    is MonitorEvent.TurnOpen -> {
      val existing = turns[event.turnId]
      turns[event.turnId] = TurnRecord(
        host, conversationId, event.turnId, event.turnIndex, event.mode, event.prompt, event.createdAt,
        existing?.outcome ?: "", existing?.durationMs ?: 0, existing?.errorText ?: ""
      )
      touchedTurns += event.turnId
    }
    is MonitorEvent.BlockOpen -> {
      ensureTurn(host, conversationId, event.turnId, turns, touchedTurns)
      val existing = blocks[event.blockId]
      val repair = repairs[event.blockId]
      val body = when {
        repair != null && repair.fetchedBody.isNotEmpty() -> repair.fetchedBody
        else -> existing?.body ?: ""
      }
      blocks[event.blockId] = BlockRecord(
        host, conversationId, event.turnId, event.blockId, event.ordinal, event.kind, event.title,
        body, existing?.state ?: "running"
      )
      touchedBlocks += event.blockId
      if (repair != null && repair.fetchedBody.isNotEmpty() && utf8Length(body) == repair.expectedLength) {
        repairs.remove(event.blockId)
        clearRepairs += event.blockId
      }
    }
    is MonitorEvent.BlockAppend -> {
      val heldAppend = holdAppend(host, conversationId, event, blocks[event.blockId], repairs[event.blockId])
      if (heldAppend.block != null) {
        blocks[event.blockId] = heldAppend.block
        touchedBlocks += event.blockId
      }
      if (heldAppend.clearHeld) dropHeld += event.blockId
      if (heldAppend.repair == null) {
        repairs.remove(event.blockId)
        clearRepairs += event.blockId
      } else {
        repairs[event.blockId] = heldAppend.repair
      }
      heldAppend.held?.let { held += it }
      heldAppend.fetch?.let { fetches += it }
    }
    is MonitorEvent.BlockReplace -> {
      val replaced = holdReplace(host, conversationId, event, blocks[event.blockId], repairs[event.blockId])
      if (replaced.block != null) {
        blocks[event.blockId] = replaced.block
        touchedBlocks += event.blockId
      }
      if (replaced.clearHeld) dropHeld += event.blockId
      if (replaced.repair == null) {
        repairs.remove(event.blockId)
        clearRepairs += event.blockId
      } else {
        repairs[event.blockId] = replaced.repair
      }
      replaced.fetch?.let { fetches += it }
    }
    is MonitorEvent.BlockClose -> {
      val block = blocks[event.blockId]
      if (block == null) {
        val request = fetchRequestId(event.blockId, event.seq)
        repairs[event.blockId] = BlockRepair(
          host, conversationId, event.blockId, 0, 0, true, "", false, request, ""
        )
        fetches += BlockFetch(conversationId, event.blockId, 0, "", request)
      } else {
        blocks[event.blockId] = block.copy(state = event.state)
        touchedBlocks += event.blockId
      }
    }
    is MonitorEvent.ImageAdded -> {
      val existing = images[event.imageId]
      images[event.imageId] = ImageRecord(
        event.imageId, host, conversationId, existing?.filePath ?: "", event.bytes, event.mime,
        existing?.size ?: event.bytes
      )
      touchedImages += event.imageId
    }
    is MonitorEvent.TurnClose -> {
      val existing = turns[event.turnId]
      turns[event.turnId] = TurnRecord(
        host, conversationId, event.turnId, existing?.ordinal ?: 0, existing?.mode ?: "",
        existing?.prompt ?: "", existing?.createdAt ?: "", event.outcome, event.durationMs, event.errorText
      )
      touchedTurns += event.turnId
    }
    is MonitorEvent.TitleChanged -> { }
  }
}

private fun ensureTurn(
  host: String,
  conversationId: String,
  turnId: String,
  turns: MutableMap<String, TurnRecord>,
  touched: MutableSet<String>
) {
  if (turnId in turns) return
  turns[turnId] = TurnRecord(host, conversationId, turnId, 0, "", "", "", "", 0, "")
  touched += turnId
}
