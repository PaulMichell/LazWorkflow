package computing.michell.monitor.ui.model

/* Pure display helpers. Catalogue 3 view-model machinery was removed (c) 2026 Michell Computing. */

const val ConnectingBanner = "Connecting…"
const val PhaseWaiting = "Waiting…"
const val PhaseThinking = "Thinking…"
const val PhaseStreaming = "Streaming…"
const val PhaseRunning = "Running…"
const val PhaseSteering = "Steering…"
const val PhaseConnecting = "Connecting…"
const val WaitingForDesktop = "Waiting for the desktop"
const val PairedElsewhereLabel = "Paired elsewhere"

private val ElapsedTail = Regex("""(\d+):(\d{2})(?::(\d{2}))?$""")
private val PlanRunSuffix = Regex(""" \((\d+):(\d{2})(?::(\d{2}))?\)$""")
private val WorkKinds = setOf("thinking", "answer", "tool", "subagent")

fun linkBanner(banner: String): Boolean {
  return banner == ReconnectingBanner || banner == ConnectingBanner || banner == ConnectionRefusedBanner ||
    banner == HostClosedBanner || banner == OfflineBanner || banner == OfflineReviewBanner || banner == NoAddressBanner ||
    banner == BackgroundBanner || banner == WaitingForWifiBanner || banner == IdleOfflineBanner
}

fun statusNotice(banner: String): String {
  val text = banner.trim()
  if (text.isEmpty() || linkBanner(text) || text == PairedElsewhereLabel) return ""
  return when (text) {
    "auth" -> "The desktop did not accept this phone."
    "revoked" -> "This phone was revoked on the desktop."
    "expired" -> "The desktop sign-in expired. Pair again."
    "protocol" -> "Update the app or the IDE: the desktop and this app are not speaking the same protocol."
    "pair_code" -> "The pair code was not accepted."
    "fingerprint" -> "The desktop certificate did not match."
    "busy" -> "The Project Assistant is busy."
    "disabled" -> "Remote monitor is turned off."
    else -> text
  }
}

fun statusConnectionLabel(chipLabel: String, banner: String): String {
  if (statusNotice(banner).isNotEmpty()) return chipLabel
  return chipLabel
}

fun clearRemoteActions(view: WireView): WireView {
  return view.copy(busy = false, sending = false, canSend = false, canSteer = false, canStop = false, planRunning = false)
}

fun actionCaption(view: WireView): String {
  if (view.canSteer && (view.sending || view.busy)) return "Steer"
  return "Send"
}

fun shownModel(model: String): String {
  val id = model.trim()
  if (id.isEmpty() || id == "Model") return ""
  return id
}

fun sendActionEnabled(
  view: WireView,
  disconnected: Boolean,
  phase: LinkPhase,
  planRunning: Boolean,
  syncing: Boolean = false
): Boolean {
  if (!syncing && (disconnected || phase != LinkPhase.Live)) return false
  if (view.sending || view.busy || view.planRunning || planRunning) return view.canSteer
  if (view.canSend || view.canSteer) return true
  return !view.available
}

fun newConversationEnabled(
  view: WireView,
  disconnected: Boolean,
  phase: LinkPhase,
  planRunning: Boolean,
  syncing: Boolean = false
): Boolean {
  if (!syncing && (disconnected || phase != LinkPhase.Live)) return false
  if (view.sending || view.busy || view.planRunning || planRunning) return false
  if (view.canSend) return true
  return !view.available
}

fun ideLinkLive(disconnected: Boolean, phase: LinkPhase): Boolean {
  return phase == LinkPhase.Live && !disconnected
}

fun formatActivityClock(elapsedMs: Long): String {
  val secs = (elapsedMs / 1000L).toInt().coerceAtLeast(0)
  return "${secs / 60}:${(secs % 60).toString().padStart(2, '0')}"
}

fun formatPlanRunElapsed(elapsedMs: Long): String {
  val secs = (elapsedMs / 1000L).coerceAtLeast(0L)
  val rem = (secs % 60L).toString().padStart(2, '0')
  return if (secs >= 3600L) {
    val hours = secs / 3600L
    val mins = ((secs % 3600L) / 60L).toString().padStart(2, '0')
    "$hours:$mins:$rem"
  } else {
    "${secs / 60L}:$rem"
  }
}

fun planRunElapsedMs(text: String): Long {
  val match = PlanRunSuffix.find(text.trim()) ?: return -1L
  val head = match.groupValues[1].toLongOrNull() ?: return -1L
  val mid = match.groupValues[2].toLongOrNull() ?: return -1L
  val tail = match.groupValues[3]
  val secs = if (tail.isEmpty()) head * 60L + mid else head * 3600L + mid * 60L + (tail.toLongOrNull() ?: 0L)
  return secs * 1000L
}

fun stripPlanRunSuffix(text: String): String = text.replace(PlanRunSuffix, "").trim()

fun planRunSuffix(startedMs: Long, nowMs: Long): String {
  if (startedMs <= 0L || nowMs < startedMs) return ""
  return " (${formatPlanRunElapsed(nowMs - startedMs)})"
}

fun hostHasElapsed(text: String): Boolean = ElapsedTail.containsMatchIn(text.trim())

fun elapsedMsOf(text: String): Int {
  val match = ElapsedTail.find(text.trim()) ?: return 0
  val head = match.groupValues[1].toIntOrNull() ?: return 0
  val mid = match.groupValues[2].toIntOrNull() ?: return 0
  val tail = match.groupValues[3]
  val secs = if (tail.isEmpty()) head * 60 + mid else head * 3600 + mid * 60 + (tail.toIntOrNull() ?: 0)
  return secs * 1000
}

fun idleActivity(statusText: String): String {
  val text = stripPlanRunSuffix(statusText.trim())
  if (text.isEmpty() || text == "Ready" || text == "Offline" || text == "Not signed in" || hostHasElapsed(text)) return "Ready"
  return text
}

fun runtimeCaption(model: String, choices: List<ModelChoice> = emptyList()): String {
  val id = shownModel(model)
  if (id.isEmpty()) return ""
  val caption = choices.firstOrNull { choice -> choice.id == id }?.caption?.trim().orEmpty()
  return caption.ifEmpty { id }
}

fun runtimeCaption(view: WireView): String = runtimeCaption(view.model)

fun heldPromptActivity(pending: Boolean, phase: LinkPhase): String {
  if (!pending) return ""
  return if (phase == LinkPhase.Connecting) PhaseConnecting else WaitingForDesktop
}

fun progressPhase(name: String): String {
  return when (name) {
    "Waiting for first token…", "Waiting", "Waiting for model…" -> PhaseWaiting
    "Running tools…", "Subagent…", "Working…" -> PhaseRunning
    "Steer queued…", "Steering at next tool gap…", "Steering at next model gap…" -> PhaseSteering
    "Re-establishing Connection" -> PhaseConnecting
    else -> name
  }
}

fun turnStillRunning(
  view: WireView,
  pending: Boolean,
  blocks: List<WireBlock>,
  @Suppress("UNUSED_PARAMETER") live: WireTurn? = null
): Boolean {
  if (blocks.any { block -> block.kind == "worked" || block.body.startsWith("Worked for") }) return false
  return pending || view.sending || view.busy || view.planRunning
}

fun observedElapsedMs(view: WireView, live: WireTurn?, blocks: List<WireBlock>): Int {
  val fromStatus = if (hostHasElapsed(view.statusText)) elapsedMsOf(view.statusText) else 0
  val fromView = view.elapsedMs.coerceAtLeast(0)
  val fromLive = if (live != null && live.durationMs > 0) live.durationMs else 0
  val worked = blocks.lastOrNull { block -> block.kind == "worked" || block.body.startsWith("Worked for") }
  val fromWorked = if (worked == null) 0 else if (worked.durationMs > 0) worked.durationMs else elapsedMsOf(worked.body)
  return maxOf(fromStatus, fromView, fromLive, fromWorked)
}

fun activityPhase(view: WireView, pending: Boolean, pendingKind: String, blocks: List<WireBlock>): String {
  if (hostHasElapsed(view.statusText)) {
    val named = view.statusText.trim().substringBeforeLast(" ").trim()
    if (named.isNotEmpty() && named != "Ready" && named != "Offline" && named != "Not signed in") return progressPhase(named)
  }
  if (view.phase.isNotEmpty() && view.phase != "Ready" && view.phase != "Offline" && view.phase != "Not signed in") return progressPhase(view.phase)
  val status = stripPlanRunSuffix(view.statusText)
  if (view.planRunning && status.isNotEmpty() && status != "Ready" && status != "Offline" && status != "Not signed in") return status
  val running = blocks.lastOrNull { block -> block.running }
  if (running != null) {
    return when (running.kind) {
      "thinking" -> PhaseThinking
      "answer" -> PhaseStreaming
      "tool", "subagent" -> PhaseRunning
      else -> PhaseRunning
    }
  }
  if (pending && pendingKind == "steer") return PhaseSteering
  if (blocks.any { block -> block.kind in WorkKinds }) return PhaseWaiting
  return PhaseWaiting
}

fun activityCaption(
  view: WireView,
  pending: Boolean,
  pendingKind: String,
  startedMs: Long,
  nowMs: Long,
  blocks: List<WireBlock> = emptyList(),
  live: WireTurn? = null,
  linkLive: Boolean = true,
  planRunning: Boolean = false,
  planStartedMs: Long = 0L
): String {
  if (!linkLive) return ""
  val planOn = planRunning || view.planRunning
  val total = if (planOn) planRunSuffix(planStartedMs, nowMs) else ""
  val betweenItems = planOn && !view.sending && !pending
  if (betweenItems || !turnStillRunning(view, pending, blocks, live)) return idleActivity(view.statusText) + total
  val phase = activityPhase(view, pending, pendingKind, blocks)
  val elapsed = observedElapsedMs(view, live, blocks).toLong()
  val start = when {
    startedMs > 0L -> startedMs
    elapsed > 0L && nowMs > elapsed -> nowMs - elapsed
    else -> 0L
  }
  if (nowMs <= 0L || start <= 0L || nowMs < start) return phase + total
  return "$phase ${formatActivityClock(nowMs - start)}$total"
}
