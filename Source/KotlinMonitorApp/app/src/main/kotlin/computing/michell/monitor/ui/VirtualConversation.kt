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
  return when (block.kind) {
    "thinking" -> showThinking && (block.body.isNotEmpty() || block.title.isNotEmpty())
    "tool", "subagent" -> showTools
    else -> block.body.isNotEmpty() || block.title.isNotEmpty() || block.images.isNotEmpty()
  }
}

fun shownBlocks(turn: WireTurn?, showThinking: Boolean, showTools: Boolean): List<WireBlock> {
  return displayBlocks(turn).filter { block -> blockShown(block, showThinking, showTools) }
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
