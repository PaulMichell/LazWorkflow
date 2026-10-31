package computing.michell.monitor.ui

/* Card captions follow the assistant trace layout (c) 2026 Michell Computing.

   Thinking stays a grey chevron title. The body stays closed until the row is
   opened, the same as the assistant. A tool or subagent is a grey header.
   The assistant answer stays in its own bubble. */

import computing.michell.monitor.protocol.WireBlock
import java.util.Locale

fun formatThinkingClock(durationMs: Int): String {
  val total = durationMs.coerceAtLeast(0) / 1000
  return String.format(Locale.US, "%d:%02d", total / 60, total % 60)
}

fun formatThoughtElapsed(durationMs: Int): String {
  val ms = durationMs.coerceAtLeast(0)
  if (ms < 60000) return String.format(Locale.US, "%.1fs", ms / 1000.0)
  val mins = ms / 60000
  val secs = (ms / 1000) % 60
  return String.format(Locale.US, "%d:%02d", mins, secs)
}

/** Kind used for drawing. A named tool is still a tool if the kind was lost. */
fun displayKind(block: WireBlock): String {
  val kind = block.kind.trim().lowercase(Locale.ROOT)
  if (kind == "tool" || kind == "subagent") return kind
  if (kind.isEmpty() && (block.toolName.isNotEmpty() || block.toolId.isNotEmpty())) return "tool"
  return kind
}

fun thinkingCardTitle(title: String, running: Boolean, durationMs: Int): String {
  if (title.isNotEmpty()) return title
  if (running) return "Thinking… ${formatThinkingClock(durationMs)}"
  return "Thinking"
}

fun thoughtFooter(running: Boolean, durationMs: Int): String {
  if (running || durationMs <= 0) return ""
  return "Thought for ${formatThinkingClock(durationMs)}"
}

/** Desktop header: caption, then running ellipsis, elapsed, and a failure mark. */
fun toolCardCaption(title: String, toolName: String, running: Boolean, ok: Boolean, durationMs: Int): String {
  var caption = title.ifEmpty { toolName.ifEmpty { "tool" } }
  if (running && !caption.endsWith("…")) caption += " …"
  if (durationMs > 0) {
    val elapsed = formatThoughtElapsed(durationMs)
    if (!caption.endsWith(elapsed)) caption += "  $elapsed"
  }
  if (!ok && !caption.endsWith("— failed")) caption += " — failed"
  return caption
}

fun toolCardCaption(block: WireBlock): String {
  return toolCardCaption(block.title, block.toolName, block.running, block.ok, block.durationMs)
}

/** Thinking, tools, and subagents start closed, matching the assistant. */
fun cardStartsOpen(kind: String): Boolean = false
