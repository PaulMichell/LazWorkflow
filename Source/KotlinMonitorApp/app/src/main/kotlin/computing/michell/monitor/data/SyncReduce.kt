package computing.michell.monitor.data

/* Apply one conversation's events onto the rows already stored (c) 2026 Michell Computing.

   A seq at or below the stored cursor is a duplicate. A seq that skips ahead
   is a gap: later events in the batch are not applied. The cursor moves only
   as far as the last event that was applied. */

import computing.michell.monitor.protocol.MonitorEvent
import computing.michell.monitor.protocol.utf8Length

data class SyncGap(
  val conversationId: String,
  val streamId: String,
  val seq: Long
)

data class BlockFetch(
  val conversationId: String,
  val blockId: String
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
  val images: List<ImageRecord>
)

data class SyncReduce(
  val commit: SyncCommit?,
  val gap: SyncGap?,
  val fetches: List<BlockFetch>,
  val applied: AppliedCursor?
)

fun reduceSync(
  host: String,
  nowMs: Long,
  conversation: ConversationRecord?,
  turns: List<TurnRecord>,
  blocks: List<BlockRecord>,
  images: List<ImageRecord>,
  events: List<MonitorEvent>
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
  val fetches = mutableListOf<BlockFetch>()
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
    applyOne(host, conversationId, event, turnMap, blockMap, imageMap, fetches)
    seq = event.seq
    applied = true
  }
  if (!applied) return SyncReduce(null, gap, fetches, null)
  val row = ConversationRecord(conversationId, host, projectRoot, title, streamId, seq, nowMs, pinned)
  val commit = SyncCommit(row, turnMap.values.toList(), blockMap.values.toList(), imageMap.values.toList())
  return SyncReduce(commit, gap, fetches, AppliedCursor(conversationId, streamId, seq))
}

private fun applyOne(
  host: String,
  conversationId: String,
  event: MonitorEvent,
  turns: MutableMap<String, TurnRecord>,
  blocks: MutableMap<String, BlockRecord>,
  images: MutableMap<String, ImageRecord>,
  fetches: MutableList<BlockFetch>
) {
  when (event) {
    is MonitorEvent.TurnOpen -> {
      val existing = turns[event.turnId]
      turns[event.turnId] = TurnRecord(
        host,
        conversationId,
        event.turnId,
        event.turnIndex,
        event.mode,
        event.prompt,
        event.createdAt,
        existing?.outcome ?: "",
        existing?.durationMs ?: 0,
        existing?.errorText ?: ""
      )
    }
    is MonitorEvent.BlockOpen -> {
      ensureTurn(host, conversationId, event.turnId, turns)
      val existing = blocks[event.blockId]
      blocks[event.blockId] = BlockRecord(
        host,
        conversationId,
        event.turnId,
        event.blockId,
        event.ordinal,
        event.kind,
        event.title,
        existing?.body ?: "",
        existing?.state ?: "running"
      )
    }
    is MonitorEvent.BlockAppend -> {
      val block = blocks[event.blockId]
      if (block == null || utf8Length(block.body) != event.offset) {
        fetches += BlockFetch(conversationId, event.blockId)
      } else {
        blocks[event.blockId] = block.copy(body = block.body + event.text)
      }
    }
    is MonitorEvent.BlockReplace -> {
      val block = blocks[event.blockId]
      if (block == null) {
        fetches += BlockFetch(conversationId, event.blockId)
      } else {
        blocks[event.blockId] = block.copy(body = event.body)
      }
    }
    is MonitorEvent.BlockClose -> {
      val block = blocks[event.blockId]
      if (block == null) {
        fetches += BlockFetch(conversationId, event.blockId)
      } else {
        blocks[event.blockId] = block.copy(state = event.state)
      }
    }
    is MonitorEvent.ImageAdded -> {
      val existing = images[event.imageId]
      images[event.imageId] = ImageRecord(
        event.imageId,
        host,
        conversationId,
        existing?.filePath ?: "",
        event.bytes,
        event.mime,
        existing?.size ?: event.bytes
      )
    }
    is MonitorEvent.TurnClose -> {
      val existing = turns[event.turnId]
      turns[event.turnId] = TurnRecord(
        host,
        conversationId,
        event.turnId,
        existing?.ordinal ?: 0,
        existing?.mode ?: "",
        existing?.prompt ?: "",
        existing?.createdAt ?: "",
        event.outcome,
        event.durationMs,
        event.errorText
      )
    }
    is MonitorEvent.TitleChanged -> { }
  }
}

private fun ensureTurn(host: String, conversationId: String, turnId: String, turns: MutableMap<String, TurnRecord>) {
  if (turnId in turns) return
  turns[turnId] = TurnRecord(host, conversationId, turnId, 0, "", "", "", "", 0, "")
}
