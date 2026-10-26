package computing.michell.monitor.ui

/* Acknowledge a prompt only from a live block after this submission (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTurn

/** User and steer blocks already on the live turn when this submission epoch started. */
fun promptBaselineOf(turn: WireTurn?): Set<String> {
  if (turn == null) return emptySet()
  return displayBlocks(turn).mapNotNull { block ->
    if (block.kind == "user" || block.kind == "steer") promptBlockKey(turn.id, block) else null
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

/** Exact trimmed equality on a live user or steer block that arrived after the submission epoch. */
fun promptShown(state: MonitorUi, text: String): Boolean {
  val wanted = text.trim()
  if (wanted.isEmpty()) return true
  val live = state.live ?: return false
  return displayBlocks(live).any { block ->
    (block.kind == "user" || block.kind == "steer") &&
      block.body.trim() == wanted &&
      promptBlockKey(live.id, block) !in state.promptBaseline
  }
}
