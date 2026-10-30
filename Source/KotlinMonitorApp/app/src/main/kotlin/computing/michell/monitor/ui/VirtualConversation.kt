package computing.michell.monitor.ui

/* Virtual conversation extent. The index is known; bodies load on demand.
   Recent slots are the ones filled first. (c) 2026 Michell Computing. */

import androidx.compose.runtime.Immutable
import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTurn
import kotlin.math.roundToInt

const val RecentTurnWindow = 3

@Immutable
data class VirtualSlot(
  val turnIndex: Int,
  val label: String,
  val live: Boolean
)

@Immutable
data class ScrollSpot(val index: Int, val unitOffset: Int, val unitSize: Int)

fun liveHasContent(turn: WireTurn?): Boolean {
  if (turn == null) return false
  if (turn.blocks.isNotEmpty()) return true
  return turn.prompt.isNotEmpty() || turn.thinking.isNotEmpty() || turn.response.isNotEmpty() || turn.errorText.isNotEmpty()
}

fun virtualSlots(turns: List<WireTurn>, live: WireTurn?, sending: Boolean): List<VirtualSlot> {
  val stored = turns.filter { !it.live }.map { turn ->
    VirtualSlot(turn.turnIndex, turn.promptPreview.ifEmpty { "Turn ${turn.turnIndex}" }, false)
  }
  if (live == null) return stored
  // An empty live row must not hide the stored turn the desktop is showing.
  val showLive = sending || liveHasContent(live)
  if (!showLive) return stored
  val label = live.promptPreview.ifEmpty { if (live.turnIndex < 0) "Live" else "Turn ${live.turnIndex}" }
  val liveSlot = VirtualSlot(live.turnIndex, label, true)
  if (live.turnIndex < 0) return stored + liveSlot
  return stored.filterNot { slot -> slot.turnIndex == live.turnIndex } + liveSlot
}

fun recentFetches(slots: List<VirtualSlot>, loaded: Set<Int>, window: Int = RecentTurnWindow): List<Int> {
  return slots.takeLast(window).map { slot -> slot.turnIndex }.filter { index -> index >= 0 && index !in loaded }.distinct()
}

/** Recent turns the screen may report as visible until 5.4. Not every history index. */
fun prefetchRecent(slots: List<VirtualSlot>, window: Int = RecentTurnWindow): Set<Int> {
  return slots.takeLast(window).map { slot -> slot.turnIndex }.filter { index -> index >= 0 }.toSet()
}

fun displayBlocks(turn: WireTurn?): List<WireBlock> {
  if (turn == null) return emptyList()
  if (turn.blocks.isNotEmpty()) return turn.blocks
  val built = ArrayList<WireBlock>()
  if (turn.prompt.isNotEmpty()) built += WireBlock("user", "", "", "", "", turn.prompt, false, true, 0, emptyList())
  if (turn.thinking.isNotEmpty()) built += WireBlock("thinking", "", "", "", "", turn.thinking, false, true, 0, emptyList())
  if (turn.response.isNotEmpty()) built += WireBlock("answer", "", "", "", "", turn.response, false, true, 0, emptyList())
  if (turn.errorText.isNotEmpty()) built += WireBlock("note", "", "", "", "", turn.errorText, false, true, 0, emptyList())
  return built
}

fun blockShown(block: WireBlock, showThinking: Boolean, showTools: Boolean): Boolean {
  return when (displayKind(block)) {
    // A running thought has a title before the first token. Hiding it left the turn looking empty.
    "thinking" -> showThinking && (block.body.isNotBlank() || block.running || block.title.isNotBlank())
    "tool", "subagent" -> showTools
    else -> block.body.isNotEmpty() || block.title.isNotEmpty() || block.images.isNotEmpty()
  }
}

fun shownBlocks(turn: WireTurn?, showThinking: Boolean, showTools: Boolean): List<WireBlock> {
  return displayBlocks(turn).filter { block -> blockShown(block, showThinking, showTools) }
}

data class ConversationRow(
  val key: String,
  val turnId: String,
  val turnIndex: Int,
  val block: WireBlock?,
  val label: String
)

/** One lazy row per visible block. The key is the turn id plus the block id. */
fun conversationRows(
  turns: List<WireTurn>,
  live: WireTurn?,
  sending: Boolean,
  showThinking: Boolean,
  showTools: Boolean
): List<ConversationRow> {
  val slots = virtualSlots(turns, live, sending)
  val rows = ArrayList<ConversationRow>()
  val used = HashSet<String>()
  for (slot in slots) {
    val turn = if (slot.live) live else turns.firstOrNull { it.turnIndex == slot.turnIndex }
    val turnId = turn?.id.orEmpty()
    val shown = shownBlocks(turn, showThinking, showTools)
    if (shown.isEmpty()) {
      val preview = turn?.promptPreview?.ifEmpty { null } ?: slot.label
      if (preview.isEmpty() || preview == "Turn ${slot.turnIndex}" || preview == "Live") continue
      val block = WireBlock("answer", "", "", "", "", preview, false, true, 0, emptyList())
      val key = uniqueRowKey(used, conversationRowKey(turnId, "preview", 0))
      rows += ConversationRow(key, turnId, slot.turnIndex, block, slot.label)
      continue
    }
    shown.forEachIndexed { index, block ->
      val key = uniqueRowKey(used, conversationRowKey(turnId, block.blockId, index))
      rows += ConversationRow(key, turnId, slot.turnIndex, block, slot.label)
    }
  }
  return rows
}

/** LazyColumn throws, and the process dies, when two rows share a key. */
internal fun uniqueRowKey(used: MutableSet<String>, key: String): String {
  if (used.add(key)) return key
  var copy = 2
  var unique = "$key\u0000$copy"
  while (!used.add(unique)) {
    copy += 1
    unique = "$key\u0000$copy"
  }
  return unique
}

/** Outline rows the screen does not already show. One row per turn index and id. */
fun addedOutlineTurns(existing: List<WireTurn>, outline: List<WireTurn>): List<WireTurn> {
  val haveIndex = existing.map { turn -> turn.turnIndex }.toMutableSet()
  val haveId = existing.map { turn -> turn.id }.filter { id -> id.isNotEmpty() }.toMutableSet()
  val added = ArrayList<WireTurn>()
  for (row in outline) {
    if (row.live || row.id.isEmpty() || row.turnIndex in haveIndex || row.id in haveId) continue
    haveIndex += row.turnIndex
    haveId += row.id
    added += row
  }
  return added
}

fun spotAt(units: List<Int>, fraction: Float): ScrollSpot {
  if (units.isEmpty()) return ScrollSpot(0, 0, 1)
  val sizes = units.map { size -> size.coerceAtLeast(1) }
  val total = sizes.sum().coerceAtLeast(1)
  val target = (fraction.coerceIn(0f, 0.999f) * total).toInt()
  var cursor = 0
  for (index in sizes.indices) {
    val size = sizes[index]
    if (target < cursor + size) return ScrollSpot(index, target - cursor, size)
    cursor += size
  }
  return ScrollSpot(sizes.lastIndex, 0, sizes.last())
}

const val HeadSlopPx = 4

fun scrollFraction(value: Int, max: Int): Float {
  if (max <= 0) return 1f
  return (value.toFloat() / max.toFloat()).coerceIn(0f, 1f)
}

fun scrollOffset(max: Int, fraction: Float): Int {
  if (max <= 0) return 0
  return (fraction.coerceIn(0f, 1f) * max).roundToInt()
}

fun atHead(value: Int, max: Int): Boolean {
  return max <= 0 || value >= max - HeadSlopPx
}

fun stickToHead(following: Boolean, previousValue: Int, value: Int, previousMax: Int, max: Int, userDragging: Boolean): Boolean {
  if (userDragging) return atHead(value, max)
  if (value < previousValue - HeadSlopPx && !atHead(value, max)) return false
  if (atHead(value, max)) return true
  if (following && max >= previousMax) return true
  return following
}

/** Row count misses a growing last block. The tail text is what the live turn is writing. */
fun liveTailToken(rows: List<ConversationRow>, pending: String): String {
  val last = rows.lastOrNull()
  val body = last?.block?.body.orEmpty()
  val end = if (body.length <= 48) body else body.substring(body.length - 48)
  return "${rows.size}\u0000${last?.key.orEmpty()}\u0000$end\u0000${pending.length}"
}

/**
 * Leaving the bottom stops the live tail. Returning to it resumes the tail.
 * A scroll the screen itself started must not count as the finger.
 */
fun followAfterMotion(following: Boolean, userScrolling: Boolean, atEnd: Boolean, programmatic: Boolean): Boolean {
  if (programmatic) return following
  if (atEnd) return true
  if (userScrolling) return false
  return following
}

fun mergeLiveTurn(previous: WireTurn?, incoming: WireTurn?, sameGeneration: Boolean = true): WireTurn? {
  if (incoming == null) return null
  val sameTurn = sameGeneration && previous != null && previous.id.isNotEmpty() && previous.id == incoming.id
  if (!sameTurn) return incoming
  if (incoming.blocks.isEmpty() && liveHasContent(previous)) {
    return incoming.copy(
      prompt = incoming.prompt.ifEmpty { previous.prompt },
      thinking = incoming.thinking.ifEmpty { previous.thinking },
      response = incoming.response.ifEmpty { previous.response },
      errorText = incoming.errorText.ifEmpty { previous.errorText },
      blocks = previous.blocks,
      images = if (incoming.images.isNotEmpty()) incoming.images else previous.images
    )
  }
  // Same text must keep the displayed object. A new instance rebuilds every bubble.
  if (previous.blocks == incoming.blocks && previous.prompt == incoming.prompt && previous.response == incoming.response &&
    previous.thinking == incoming.thinking) {
    if (previous.durationMs == incoming.durationMs && previous.promptPreview == incoming.promptPreview) return previous
    return previous.copy(
      durationMs = if (incoming.durationMs > 0) incoming.durationMs else previous.durationMs,
      promptPreview = incoming.promptPreview.ifEmpty { previous.promptPreview }
    )
  }
  return incoming
}

fun retainLoaded(history: Map<Int, WireTurn>, turns: List<WireTurn>): Map<Int, WireTurn> {
  val ids = turns.associate { turn -> turn.turnIndex to turn.id }
  return history.filter { (index, cached) ->
    val id = ids[index]
    id != null && id.isNotEmpty() && id == cached.id
  }
}
