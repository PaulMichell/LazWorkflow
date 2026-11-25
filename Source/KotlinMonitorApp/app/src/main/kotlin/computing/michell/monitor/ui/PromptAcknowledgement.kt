package computing.michell.monitor.ui

/* Acknowledge a prompt from desktop content after this submission (c) 2026 Michell Computing. */

import computing.michell.monitor.ui.model.MonitorUi
import computing.michell.monitor.ui.model.PendingPromptMark
import computing.michell.monitor.ui.model.WireBlock
import computing.michell.monitor.ui.model.WireTurn

/** Include history so an older identical prompt cannot acknowledge a new submission. */
fun promptBaselineOf(turn: WireTurn?, turns: List<WireTurn> = emptyList()): Set<String> {
  return (turns + listOfNotNull(turn)).flatMap { row ->
    displayBlocks(row).mapNotNull { block ->
      if (block.kind == "user" || block.kind == "steer") promptBlockKey(row.id, block) else null
    }
  }.toSet()
}

fun promptBlockKey(turnId: String, block: WireBlock): String {
  val identity = if (block.blockId.isNotEmpty()) block.blockId else turnId
  return identity + "\u0000" + block.kind + "\u0000" + block.body.trim()
}

/** A user or steer block that arrived after this submission, even if the desktop added a context note. */
fun hostHasLaterUserBlock(state: MonitorUi): Boolean {
  val live = state.live ?: return false
  return displayBlocks(live).any { block ->
    (block.kind == "user" || block.kind == "steer") &&
      block.body.trim().isNotEmpty() &&
      promptBlockKey(live.id, block) !in state.promptBaseline
  }
}

/** How many prompts are still waiting to appear. Zero is not a banner. */
fun waitingPromptBanner(count: Int): String {
  return when (count) {
    0 -> ""
    1 -> "1 prompt waiting"
    else -> "$count prompts waiting"
  }
}

/**
 * The prompt field stays up with the link down. Send queues; it does not wait
 * for a socket. Callers must not gate the field on the chip.
 */
fun promptFieldEnabled(@Suppress("UNUSED_PARAMETER") disconnected: Boolean): Boolean = true

/**
 * Baseline captured when this queue started. A later identical prompt must not
 * be cleared by the turn that acknowledged the previous one.
 */
fun queueBaseline(queued: Boolean, continuing: Boolean, previous: Set<String>, live: WireTurn?, turns: List<WireTurn>): Set<String> {
  if (!queued) return emptySet()
  if (continuing) return previous
  return promptBaselineOf(live, turns)
}

/**
 * Queued prompts whose turn has not appeared. A stored command id wins. Otherwise
 * each later user or steer body clears one matching prompt, in queue order.
 */
fun pendingPromptMarks(
  queued: List<PendingPromptMark>,
  seenCommandIds: Set<String>,
  turns: List<WireTurn>,
  live: WireTurn?,
  baseline: Set<String>
): List<PendingPromptMark> {
  val left = queued.filter { mark -> mark.id.isEmpty() || mark.id !in seenCommandIds }.toMutableList()
  val state = MonitorUi(turns = turns, live = live, promptBaseline = baseline)
  for (body in laterUserBodies(state)) {
    val index = left.indexOfFirst { mark -> mark.text.trim() == body }
    if (index >= 0) left.removeAt(index)
  }
  return left
}

private fun laterUserBodies(state: MonitorUi): List<String> {
  return (state.turns + listOfNotNull(state.live)).flatMap { turn ->
    displayBlocks(turn).mapNotNull { block ->
      val text = block.body.trim()
      if ((block.kind == "user" || block.kind == "steer") && text.isNotEmpty() &&
        promptBlockKey(turn.id, block) !in state.promptBaseline) text else null
    }
  }
}

/** A snapshot may already have moved the acknowledged prompt into a completed turn. */
fun promptShown(state: MonitorUi, text: String): Boolean {
  val wanted = text.trim()
  if (wanted.isEmpty()) return true
  return (state.turns + listOfNotNull(state.live)).any { turn ->
    displayBlocks(turn).any { block ->
      (block.kind == "user" || block.kind == "steer") &&
        block.body.trim() == wanted &&
        promptBlockKey(turn.id, block) !in state.promptBaseline
    }
  }
}
