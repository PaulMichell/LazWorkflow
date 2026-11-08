package computing.michell.monitor.ui

/* Acknowledge a prompt from desktop content after this submission (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTurn

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
