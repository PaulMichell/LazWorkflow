package computing.michell.monitor.ui

/* Android shell for the monitor catalogue (c) 2026 Michell Computing.

   Size note: exceeds the 1000 line preference. Catalogue events live in
   MonitorCoordinator. Prompt acknowledgement lives in PromptAcknowledgement.
   The final-result deadline lives in DictationFinalWatch. Image request
   and cache policy live in ImageCache. What remains is speech,
   preferences, bitmap decode, and effect execution.
   Reviewed 2026-10-21. */

import android.Manifest
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.speech.SpeechRecognizer
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import computing.michell.monitor.connection.ConnectionRefusedBanner
import computing.michell.monitor.connection.HostClosedBanner
import computing.michell.monitor.dictation.acceptSpeechCallback
import computing.michell.monitor.dictation.DictationAudioMessage
import computing.michell.monitor.dictation.DictationBusyMessage
import computing.michell.monitor.dictation.DictationEvent
import computing.michell.monitor.dictation.DictationFailedMessage
import computing.michell.monitor.dictation.DictationFinalWatch
import computing.michell.monitor.dictation.DictationStopFollowUp
import computing.michell.monitor.dictation.dictationStopFollowUp
import computing.michell.monitor.dictation.DictationLanguageMissingMessage
import computing.michell.monitor.dictation.DictationLanguageUnsupportedMessage
import computing.michell.monitor.dictation.DictationModelDownloadMessage
import computing.michell.monitor.dictation.DictationModelDownloadingMessage
import computing.michell.monitor.dictation.DictationNoSpeechDetectedMessage
import computing.michell.monitor.dictation.DictationNoSpeechMessage
import computing.michell.monitor.dictation.DictationOnDeviceFailedMessage
import computing.michell.monitor.dictation.DictationStoppedMessage
import computing.michell.monitor.dictation.OnDeviceLanguage
import computing.michell.monitor.dictation.DictationPhase
import computing.michell.monitor.dictation.DictationState
import computing.michell.monitor.dictation.DictationStep
import computing.michell.monitor.dictation.OnDeviceSpeechEngine
import computing.michell.monitor.dictation.SpeechEngine
import computing.michell.monitor.dictation.SpeechEngineListener
import computing.michell.monitor.dictation.DictationUnavailableMessage
import computing.michell.monitor.dictation.reduceDictation
import computing.michell.monitor.connection.ReconnectingBanner
import computing.michell.monitor.connection.HostStore
import computing.michell.monitor.connection.LanSession
import computing.michell.monitor.connection.LinkPhase
import java.io.File
import computing.michell.monitor.protocol.ApprovalNotice
import computing.michell.monitor.protocol.ErrorBody
import computing.michell.monitor.protocol.ImageAssembly
import computing.michell.monitor.protocol.InboundPayload
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.ModeNames
import computing.michell.monitor.protocol.MonitorLimits
import computing.michell.monitor.protocol.encodeOfflineCache
import computing.michell.monitor.protocol.MonitorMessage
import computing.michell.monitor.protocol.PlanRow

import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.WireView
import computing.michell.monitor.protocol.decodeApprovalRequested
import computing.michell.monitor.protocol.decodeError
import computing.michell.monitor.protocol.decodeImageUnavailable
import computing.michell.monitor.protocol.decodeMode
import computing.michell.monitor.protocol.decodePlan
import computing.michell.monitor.protocol.decodeRejected
import computing.michell.monitor.protocol.WireSnapshot
import computing.michell.monitor.protocol.WireTranscript
import computing.michell.monitor.protocol.decodeSnapshot
import computing.michell.monitor.protocol.decodeStatusPayload
import computing.michell.monitor.protocol.decodeTarget

import computing.michell.monitor.protocol.decodeText
import computing.michell.monitor.protocol.assembleTranscriptBlocks
import computing.michell.monitor.protocol.decodeTranscript
import computing.michell.monitor.protocol.decodeTurnData
import computing.michell.monitor.protocol.encodeApprovalDecision
import computing.michell.monitor.protocol.encodeEmpty
import computing.michell.monitor.protocol.encodePlanBrowse
import computing.michell.monitor.protocol.encodeNewPlan
import computing.michell.monitor.protocol.encodePath
import computing.michell.monitor.protocol.encodeSetMode
import computing.michell.monitor.protocol.encodeWorkOnPlan
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

enum class AppTab {
  Conversation,
  Plan
}

data class MonitorUi(
  val view: WireView = emptyView(),
  val turns: List<WireTurn> = emptyList(),
  val live: WireTurn? = null,
  val history: Map<Int, WireTurn> = emptyMap(),
  val selectedTurn: Int = -1,
  val planPath: String = "",
  val planTitle: String = "",
  val planRunning: Boolean = false,
  val planRows: List<PlanRow> = emptyList(),
  val selectedPlan: Int = -1,
  val planFiles: List<String>? = null,
  val approval: ApprovalNotice? = null,
  val approvalOpen: Boolean = false,
  val banner: String = "",
  val draft: String = "",
  val disconnected: Boolean = false,
  val liveRevision: Int = -1,
  val transcriptParts: Map<Int, List<WireBlock>> = emptyMap(),
  val imageReasons: Map<String, String> = emptyMap(),
  val reachedLive: Boolean = false,
  val pairHold: Boolean = false,
  val settingsOpen: Boolean = false,
  val generation: Int = 0,
  val rescueSteer: Boolean = false,
  val showThinking: Boolean = true,
  val showTools: Boolean = true,
  val pendingPrompt: String = "",
  val pendingKind: String = "",
  val pendingCommandId: String = "",
  val pendingEpoch: Int = 0,
  val promptBaseline: Set<String> = emptySet(),
  val activityStartedMs: Long = 0,
  val activityObservedMs: Int = 0,
  val hostGeneration: Int = 0,
  val conversationGeneration: Int = 0,
  val connectionGeneration: Int = 0,
  val transcriptConnection: Int = 0,
  val transcriptTurnId: String = ""
)

/** Clears conversation identity. Keeps display preferences. An unsent draft is kept only when clearDraft is false. */
fun resetConversation(state: MonitorUi, clearDraft: Boolean, hostGeneration: Int, conversationGeneration: Int): MonitorUi {
  val keepDraft = !clearDraft && state.draft.isNotEmpty() && state.pendingPrompt.isEmpty()
  return MonitorUi(
    draft = if (keepDraft) state.draft else "",
    showThinking = state.showThinking,
    showTools = state.showTools,
    settingsOpen = state.settingsOpen,
    hostGeneration = hostGeneration,
    conversationGeneration = conversationGeneration,
    connectionGeneration = state.connectionGeneration + 1
  )
}

fun emptyView(): WireView {
  return WireView(
    false, false, false, false, false, "", "", "", "", false, "", "", "", "",
    false, false, false, false, false, ""
  )
}

fun statusCaption(ui: MonitorUi, phase: LinkPhase): String {
  if (ui.banner.isNotEmpty() && !linkBanner(ui.banner)) return ui.banner
  if (ui.banner.isNotEmpty() && phase != LinkPhase.Live && phase != LinkPhase.Idle) return ui.banner
  return connectionLabel(ui, phase)
}

fun connectionLabel(ui: MonitorUi, phase: LinkPhase): String {
  if (phase == LinkPhase.Live && !ui.disconnected) {
    if (ui.view.busy || ui.view.sending || ui.view.planRunning || ui.planRunning) return "busy"
    return "live"
  }
  if (phase == LinkPhase.Connecting) return "connecting"
  if (ui.banner == OfflineBanner) return "offline"
  if (ui.disconnected || phase == LinkPhase.Disconnected || phase == LinkPhase.Paused) return "disconnected"
  if (ui.view.busy || ui.view.sending || ui.view.planRunning || ui.planRunning) return "busy"
  if (ui.reachedLive) return "live"
  return "disconnected"
}

const val ConnectingBanner = "Connecting…"
const val LinkGraceMs = 4_000L

fun linkBanner(banner: String): Boolean {
  return banner == ReconnectingBanner || banner == ConnectingBanner || banner == ConnectionRefusedBanner ||
    banner == HostClosedBanner || banner == OfflineBanner || banner == NoAddressBanner
}

fun applyLink(state: MonitorUi, phase: LinkPhase, banner: String): MonitorUi {
  if (phase == LinkPhase.Idle) {
    if (state.reachedLive) return state
    return state.copy(disconnected = true, pairHold = false)
  }
  val closed = phase == LinkPhase.Disconnected || phase == LinkPhase.Paused
  if (closed && banner.isNotEmpty()) return noteSocketClosed(state, banner)
  if (phase == LinkPhase.Connecting) {
    val shown = if (banner.isEmpty() || banner == ReconnectingBanner) ConnectingBanner else banner
    return state.copy(disconnected = true, banner = shown, pairHold = false)
  }
  if (phase == LinkPhase.Live) {
    val shown = if (linkBanner(state.banner)) "" else state.banner
    return state.copy(disconnected = false, banner = shown, pairHold = false)
  }
  if (closed || (!state.disconnected && state.banner != ReconnectingBanner)) return state
  val shown = if (banner.isEmpty() || banner == ReconnectingBanner) "" else banner
  return state.copy(disconnected = false, banner = shown)
}

fun actionCaption(view: WireView): String {
  if (view.canSteer) return "Steer"
  return "Send"
}

fun actionEnabled(view: WireView): Boolean {
  return view.canSend || view.canSteer
}

fun loadedTurnIndices(state: MonitorUi): Set<Int> {
  val stored = state.history.filterValues { turn -> liveHasContent(turn) }.keys
  val live = state.live
  if (live != null && live.turnIndex >= 0 && liveHasContent(live)) return stored + live.turnIndex
  return stored
}

const val NothingRunningToSteer = "Nothing is running to steer."

fun clearRemoteActions(view: WireView): WireView {
  return view.copy(busy = false, sending = false, canSend = false, canSteer = false, canStop = false, planRunning = false)
}

fun runtimeCaption(view: WireView): String {
  return view.model
}

private val ElapsedTail = Regex("""(\d+):(\d{2})(?::(\d{2}))?$""")
private val WorkKinds = setOf("thinking", "answer", "tool", "subagent")

fun hostHasElapsed(text: String): Boolean = ElapsedTail.containsMatchIn(text.trim())

fun elapsedMsOf(text: String): Int {
  val match = ElapsedTail.find(text.trim()) ?: return 0
  val head = match.groupValues[1].toIntOrNull() ?: return 0
  val mid = match.groupValues[2].toIntOrNull() ?: return 0
  val tail = match.groupValues[3]
  val secs = if (tail.isEmpty()) head * 60 + mid else head * 3600 + mid * 60 + (tail.toIntOrNull() ?: 0)
  return secs * 1000
}

fun hasWorkedFooter(blocks: List<WireBlock>): Boolean {
  return blocks.any { block -> block.kind == "worked" || block.body.startsWith("Worked for") }
}

fun turnStillRunning(view: WireView, pending: Boolean, blocks: List<WireBlock>, live: WireTurn? = null): Boolean {
  if (hasWorkedFooter(blocks)) return false
  if (pending || view.sending || view.busy || view.planRunning) return true
  if (blocks.any { block -> block.running }) return true
  if (live != null && live.turnIndex < 0) {
    if (live.durationMs > 0) return true
    if (blocks.any { block -> block.kind in WorkKinds }) return true
  }
  return false
}

fun observedElapsedMs(view: WireView, live: WireTurn?, blocks: List<WireBlock>): Int {
  val fromStatus = if (hostHasElapsed(view.statusText)) elapsedMsOf(view.statusText) else 0
  if (fromStatus > 0) return fromStatus
  if (live != null && live.turnIndex < 0 && live.durationMs > 0) return live.durationMs
  val worked = blocks.lastOrNull { block -> block.kind == "worked" || block.body.startsWith("Worked for") }
  if (worked != null) {
    if (worked.durationMs > 0) return worked.durationMs
    return elapsedMsOf(worked.body)
  }
  return 0
}

fun activityStart(keptStart: Long, nowMs: Long, observedMs: Int, previousObservedMs: Int): Long {
  if (observedMs > 0 && observedMs != previousObservedMs && nowMs > 0L) return nowMs - observedMs
  if (keptStart > 0L) return keptStart
  return nowMs.coerceAtLeast(0L)
}

fun formatActivityClock(elapsedMs: Long): String {
  val secs = (elapsedMs / 1000L).toInt().coerceAtLeast(0)
  return "${secs / 60}:${(secs % 60).toString().padStart(2, '0')}"
}

fun activityPhase(view: WireView, pending: Boolean, pendingKind: String, blocks: List<WireBlock>): String {
  if (hostHasElapsed(view.statusText)) {
    val named = view.statusText.trim().substringBeforeLast(" ").trim()
    if (named.isNotEmpty() && named != "Ready") return named
  }
  if (view.phase.isNotEmpty() && view.phase != "Ready") return view.phase
  if (view.planRunning && view.statusText.isNotEmpty() && view.statusText != "Ready") return view.statusText
  val running = blocks.lastOrNull { block -> block.running }
  if (running != null) {
    return when (running.kind) {
      "thinking" -> "Thinking…"
      "answer" -> "Streaming…"
      "tool" -> if (running.toolName.isNotEmpty()) running.toolName else "Running tools…"
      "subagent" -> "Subagent…"
      else -> "Working…"
    }
  }
  if (pending && pendingKind == "steer") return "Steering…"
  if (blocks.any { block -> block.kind in WorkKinds }) return "Working…"
  return "Waiting for first token…"
}

fun activityCaption(
  view: WireView,
  pending: Boolean,
  pendingKind: String,
  startedMs: Long,
  nowMs: Long,
  blocks: List<WireBlock> = emptyList(),
  live: WireTurn? = null
): String {
  if (!turnStillRunning(view, pending, blocks, live)) {
    if (view.statusText.isNotEmpty()) return view.statusText
    return if (view.signedIn) "Ready" else "Not signed in"
  }
  val phase = activityPhase(view, pending, pendingKind, blocks)
  val start = if (startedMs > 0L) startedMs else nowMs
  if (nowMs <= 0L || start <= 0L || nowMs < start) return phase
  return "$phase ${formatActivityClock(nowMs - start)}"
}

fun beginSubmit(state: MonitorUi, text: String, steer: Boolean, nowMs: Long, commandId: String = ""): MonitorUi {
  val phase = if (steer) "Steering…" else "Waiting for first token…"
  return state.copy(
    draft = "",
    pendingPrompt = text,
    pendingKind = if (steer) "steer" else "user",
    pendingCommandId = commandId,
    pendingEpoch = state.pendingEpoch + 1,
    promptBaseline = promptBaselineOf(state.live),
    activityStartedMs = if (state.activityStartedMs > 0L) state.activityStartedMs else nowMs,
    banner = "",
    view = state.view.copy(
      sending = true,
      busy = true,
      canSend = false,
      canSteer = steer,
      canStop = true,
      phase = phase,
      statusText = phase
    )
  )
}

fun mergeApplied(current: MonitorUi, next: MonitorUi, useReducedDraft: Boolean, clearDisconnect: Boolean, nowMs: Long = 0L): MonitorUi {
  if (next.generation < current.generation) return current
  val history = retainLoaded(current.history + next.history, next.turns)
  // An empty draft is explicit. Do not refill it from an older insert still sitting on next.
  val draft = if (useReducedDraft) next.draft else current.draft
  val sameGeneration = current.hostGeneration == next.hostGeneration &&
    current.conversationGeneration == next.conversationGeneration &&
    current.connectionGeneration == next.connectionGeneration
  val mergedLive = mergeLiveTurn(current.live, next.live, sameGeneration)
  val baseline = current.promptBaseline
  val merged = next.copy(live = mergedLive, history = history, promptBaseline = baseline)
  val dropStatus = (next.banner.isEmpty() && bannerIsStatus(current.banner)) ||
    (current.banner.isEmpty() && bannerIsStatus(next.banner))
  val nextBanner = if (dropStatus) "" else next.banner
  val shown = promptShown(merged, current.pendingPrompt)
  val pendingLeft = !shown && current.pendingPrompt.isNotEmpty()
  val blocks = displayBlocks(mergedLive)
  val running = turnStillRunning(next.view, pendingLeft, blocks, mergedLive)
  val observed = observedElapsedMs(next.view, mergedLive, blocks)
  val keptStart = if (current.activityStartedMs > 0L) current.activityStartedMs else next.activityStartedMs
  val start = if (!running) 0L else activityStart(keptStart, nowMs, observed, current.activityObservedMs)
  return next.copy(
    draft = draft,
    pairHold = if (clearDisconnect) false else current.pairHold,
    settingsOpen = current.settingsOpen,
    banner = if (clearDisconnect || dropStatus) "" else if (nextBanner.isNotEmpty()) nextBanner else current.banner,
    disconnected = if (clearDisconnect || !next.disconnected) false else current.disconnected,
    history = history,
    live = mergedLive,
    showThinking = current.showThinking,
    showTools = current.showTools,
    pendingPrompt = if (shown) "" else current.pendingPrompt,
    pendingKind = if (shown) "" else current.pendingKind,
    pendingEpoch = maxOf(current.pendingEpoch, next.pendingEpoch),
    promptBaseline = if (shown) emptySet() else baseline,
    activityStartedMs = start,
    activityObservedMs = if (running && observed > 0) observed else if (running) current.activityObservedMs else 0
  )
}

fun reduceMonitor(state: MonitorUi, message: MonitorMessage): MonitorUi {
  if (!message.changesState && message.kind != MessageKind.Error) return state
  if (message.inbound !is InboundPayload.None) return reduceInbound(state, message.inbound)
  return when (message.kind) {
    MessageKind.Snapshot -> applySnapshot(state, message.payloadJson)
    MessageKind.Transcript -> applyTranscript(state, message.payloadJson)
    MessageKind.TurnData -> applyTurnData(state, message.payloadJson)
    MessageKind.Status -> applyStatus(state, message.payloadJson)
    MessageKind.Mode -> applyMode(state, message.payloadJson)
    MessageKind.Target -> applyTarget(state, message.payloadJson)
    MessageKind.Plan -> applyPlan(state, message.payloadJson)
    MessageKind.ApprovalRequested -> applyApprovalRequested(state, message.payloadJson)
    MessageKind.ApprovalClosed -> state.copy(approvalOpen = false)
    MessageKind.InsertResult -> applyInsertResult(state, message.payloadJson)
    MessageKind.Rejected -> applyRejected(state, message)
    MessageKind.Error -> applyError(state, message.payloadJson)
    MessageKind.ImageUnavailable -> applyImageUnavailable(state, message.payloadJson)
    else -> state
  }
}

fun noteSocketClosed(state: MonitorUi, banner: String): MonitorUi {
  val shown = if (banner.isEmpty()) HostClosedBanner else banner
  val already = state.disconnected
  return state.copy(
    disconnected = true,
    banner = shown,
    generation = if (already) state.generation else state.generation + 1,
    connectionGeneration = if (already) state.connectionGeneration else state.connectionGeneration + 1,
    liveRevision = -1,
    transcriptParts = emptyMap(),
    transcriptTurnId = "",
    rescueSteer = false,
    view = clearRemoteActions(state.view)
  )
}

private fun reduceInbound(state: MonitorUi, inbound: InboundPayload): MonitorUi {
  return when (inbound) {
    is InboundPayload.Snapshot -> applySnapshot(state, inbound.value)
    is InboundPayload.TranscriptPart -> applyTranscript(state, inbound.value)
    is InboundPayload.Turn -> state.copy(history = state.history + (inbound.value.turnIndex to inbound.value))
    is InboundPayload.Status -> state.copy(view = state.view.patchStatus(inbound.view))
    is InboundPayload.Mode -> state.copy(view = state.view.copy(mode = inbound.value.mode, modeLocked = inbound.value.locked))
    is InboundPayload.Target -> state.copy(view = state.view.copy(
      targetKind = inbound.value.kind,
      targetDisplay = inbound.value.display,
      targetRoot = inbound.value.root
    ))
    is InboundPayload.Plan -> state.copy(
      planPath = inbound.value.path,
      planTitle = inbound.value.title,
      planRunning = inbound.value.running,
      planRows = inbound.value.rows,
      planFiles = inbound.value.files ?: state.planFiles,
      selectedPlan = if (state.planPath == inbound.value.path) state.selectedPlan else -1,
      view = state.view.copy(planPath = inbound.value.path, planTitle = inbound.value.title, planRunning = inbound.value.running)
    )
    is InboundPayload.ApprovalRequest -> state.copy(approval = inbound.notice, approvalOpen = true)
    is InboundPayload.Insert -> state.copy(draft = inbound.text)
    is InboundPayload.Error -> applyErrorValue(state, inbound.body)
    is InboundPayload.Rejected -> {
      val reason = inbound.value.reason
      val hold = reason == "protocol" || reason == "pair_code" || reason == "fingerprint"
      state.copy(disconnected = true, banner = reason, pairHold = hold || state.pairHold)
    }
    is InboundPayload.ImageMissing -> state.copy(imageReasons = state.imageReasons + (inbound.value.imageId to inbound.value.reason))
    else -> state
  }
}

private fun applySnapshot(state: MonitorUi, payloadJson: String): MonitorUi {
  val snapshot = decodeSnapshot(payloadJson) ?: return state
  return applySnapshot(state, snapshot)
}

private fun applySnapshot(state: MonitorUi, snapshot: WireSnapshot): MonitorUi {
  val incoming = snapshot.live
  if (incoming == null) {
    if (state.live != null || state.turns.isNotEmpty() || state.history.isNotEmpty()) return keepOfflineSnapshot(state, snapshot)
    val cleared = resetConversation(state, false, state.hostGeneration, state.conversationGeneration + 1)
    return overlaySnapshot(cleared, snapshot, state.generation + 1)
  }
  val previousId = state.live?.id ?: ""
  val acceptedNew = previousId.isNotEmpty() && previousId != incoming.id
  val conversationGeneration = if (acceptedNew) state.conversationGeneration + 1 else state.conversationGeneration
  val live = mergeLiveTurn(state.live, incoming, !acceptedNew)
  val sameTurn = previousId.isNotEmpty() && previousId == incoming.id &&
    state.transcriptConnection == state.connectionGeneration
  val approval = snapshot.approval
  return state.copy(
    view = snapshot.view,
    turns = snapshot.storedTurns,
    live = live,
    history = retainLoaded(state.history, snapshot.storedTurns),
    planPath = snapshot.planPath,
    planTitle = snapshot.planTitle,
    planRunning = snapshot.planRunning,
    planRows = snapshot.planRows,
    approval = if (approval.active) approval else null,
    approvalOpen = approval.active,
    liveRevision = if (sameTurn) state.liveRevision else -1,
    transcriptParts = if (sameTurn) state.transcriptParts else emptyMap(),
    transcriptTurnId = if (sameTurn) state.transcriptTurnId else "",
    reachedLive = true,
    pairHold = false,
    disconnected = false,
    banner = "",
    generation = state.generation + 1,
    rescueSteer = false,
    conversationGeneration = conversationGeneration
  )
}

private fun keepOfflineSnapshot(state: MonitorUi, snapshot: WireSnapshot): MonitorUi {
  val turns = if (snapshot.storedTurns.isNotEmpty()) snapshot.storedTurns else state.turns
  val approval = snapshot.approval
  return state.copy(
    view = snapshot.view,
    turns = turns,
    history = retainLoaded(state.history, turns),
    planPath = snapshot.planPath,
    planTitle = snapshot.planTitle,
    planRunning = snapshot.planRunning,
    planRows = snapshot.planRows,
    approval = if (approval.active) approval else state.approval,
    approvalOpen = approval.active || state.approvalOpen,
    reachedLive = true,
    pairHold = false,
    disconnected = false,
    banner = "",
    generation = state.generation + 1
  )
}

fun overlaySnapshot(cleared: MonitorUi, snapshot: WireSnapshot, generation: Int): MonitorUi {
  val approval = snapshot.approval
  return cleared.copy(
    view = snapshot.view,
    turns = snapshot.storedTurns,
    live = null,
    history = emptyMap(),
    planPath = snapshot.planPath,
    planTitle = snapshot.planTitle,
    planRunning = snapshot.planRunning,
    planRows = snapshot.planRows,
    approval = if (approval.active) approval else null,
    approvalOpen = approval.active,
    reachedLive = true,
    pairHold = false,
    disconnected = false,
    banner = "",
    generation = generation,
    liveRevision = -1,
    transcriptParts = emptyMap()
  )
}

private fun transcriptInScope(state: MonitorUi, turnId: String): Boolean {
  if (state.liveRevision < 0) return false
  if (state.transcriptConnection != state.connectionGeneration) return false
  if (turnId.isNotEmpty() && state.transcriptTurnId.isNotEmpty() && turnId != state.transcriptTurnId) return false
  return true
}

private fun applyTranscript(state: MonitorUi, payloadJson: String): MonitorUi {
  val transcript = decodeTranscript(payloadJson) ?: return state
  return applyTranscript(state, transcript)
}

private fun applyTranscript(state: MonitorUi, transcript: WireTranscript): MonitorUi {
  val turnId = state.live?.id ?: ""
  val inScope = transcriptInScope(state, turnId)
  if (inScope && transcript.revision < state.liveRevision) return state
  if (inScope && transcript.revision == state.liveRevision && state.transcriptParts.containsKey(transcript.part)) return state
  val parts = if (!inScope || transcript.revision > state.liveRevision) {
    mapOf(transcript.part to transcript.blocks)
  } else {
    state.transcriptParts + (transcript.part to transcript.blocks)
  }
  // Part order, not arrival order, so a late frame cannot move an earlier block.
  val assembled = assembleTranscriptBlocks(parts.toSortedMap().values.toList())
  val previous = state.live
  val complete = transcript.partCount <= 1 || (1..transcript.partCount).all { part -> parts.containsKey(part) }
  // An incomplete reconnect stream must not wipe the conversation already on screen.
  val blocks = if (previous != null && previous.blocks.isNotEmpty() && !complete && assembled.size < previous.blocks.size) {
    previous.blocks
  } else assembled
  val duration = if (transcript.durationMs > 0) transcript.durationMs else previous?.durationMs ?: 0
  val live = if (previous != null && previous.blocks == blocks && previous.turnIndex == transcript.turnIndex) {
    if (previous.durationMs == duration) previous else previous.copy(durationMs = duration)
  } else WireTurn(
    transcript.turnIndex,
    previous?.id ?: "",
    previous?.mode ?: state.view.mode,
    previous?.createdAt ?: "",
    previous?.promptPreview ?: "",
    previous?.errorText ?: "",
    previous?.prompt ?: "",
    previous?.thinking ?: "",
    previous?.response ?: "",
    duration,
    true,
    blocks,
    previous?.images ?: emptyList()
  )
  return state.copy(
    live = live,
    liveRevision = transcript.revision,
    transcriptParts = parts,
    transcriptConnection = state.connectionGeneration,
    transcriptTurnId = turnId,
    view = state.view.copy(
      phase = transcript.phase.ifEmpty { state.view.phase },
      statusText = transcript.statusText.ifEmpty { state.view.statusText }
    ),
    reachedLive = true
  )
}

private fun applyTurnData(state: MonitorUi, payloadJson: String): MonitorUi {
  val turn = decodeTurnData(payloadJson) ?: return state
  return state.copy(history = state.history + (turn.turnIndex to turn))
}

private fun applyStatus(state: MonitorUi, payloadJson: String): MonitorUi {
  val status = decodeStatusPayload(payloadJson) ?: return state
  return state.copy(
    view = state.view.patchStatus(status),
    disconnected = false,
    banner = if (bannerIsStatus(state.banner)) "" else state.banner,
    reachedLive = true
  )
}

private fun applyMode(state: MonitorUi, payloadJson: String): MonitorUi {
  val mode = decodeMode(payloadJson) ?: return state
  return state.copy(view = state.view.copy(mode = mode.mode, modeLocked = mode.locked))
}

private fun applyTarget(state: MonitorUi, payloadJson: String): MonitorUi {
  val target = decodeTarget(payloadJson) ?: return state
  return state.copy(view = state.view.copy(targetKind = target.kind, targetDisplay = target.display, targetRoot = target.root))
}

private fun applyPlan(state: MonitorUi, payloadJson: String): MonitorUi {
  val plan = decodePlan(payloadJson) ?: return state
  return state.copy(
    planPath = plan.path,
    planTitle = plan.title,
    planRunning = plan.running,
    planRows = plan.rows,
    planFiles = plan.files ?: state.planFiles,
    selectedPlan = if (state.planPath == plan.path) state.selectedPlan else -1,
    view = state.view.copy(planPath = plan.path, planTitle = plan.title, planRunning = plan.running)
  )
}

private fun applyApprovalRequested(state: MonitorUi, payloadJson: String): MonitorUi {
  val notice = decodeApprovalRequested(payloadJson) ?: return state
  return state.copy(approval = notice, approvalOpen = true)
}

private fun applyInsertResult(state: MonitorUi, payloadJson: String): MonitorUi {
  val text = decodeText(payloadJson) ?: return state
  return state.copy(draft = text)
}

private fun applyRejected(state: MonitorUi, message: MonitorMessage): MonitorUi {
  val rejected = decodeRejected(message.payloadJson)
  val reason = rejected?.reason ?: message.reason
  val hold = reason == "protocol" || reason == "pair_code" || reason == "fingerprint"
  return state.copy(disconnected = true, banner = reason, pairHold = hold || state.pairHold)
}

private fun applyError(state: MonitorUi, payloadJson: String): MonitorUi {
  val error = decodeError(payloadJson) ?: return state.copy(banner = payloadJson)
  return applyErrorValue(state, error)
}

private fun applyErrorValue(state: MonitorUi, error: ErrorBody): MonitorUi {
  if (error.messageText == NothingRunningToSteer && (state.draft.isNotEmpty() || state.pendingPrompt.isNotEmpty()) && !state.disconnected) {
    return state.copy(
      banner = "",
      draft = state.draft.ifEmpty { state.pendingPrompt },
      pendingPrompt = "",
      pendingKind = "",
      rescueSteer = true,
      generation = state.generation + 1,
      view = state.view.copy(canSteer = false, canSend = true, sending = false, busy = false, canStop = false)
    )
  }
  if (error.messageText == NothingRunningToSteer) {
    return state.copy(banner = error.messageText, view = state.view.copy(canSteer = false))
  }
  return state.copy(banner = error.messageText)
}

private fun applyImageUnavailable(state: MonitorUi, payloadJson: String): MonitorUi {
  val image = decodeImageUnavailable(payloadJson) ?: return state
  return state.copy(imageReasons = state.imageReasons + (image.imageId to image.reason))
}

private fun WireView.patchStatus(status: WireView): WireView {
  return copy(
    available = status.available,
    busy = status.busy,
    sending = status.sending,
    modeLocked = status.modeLocked,
    planRunning = status.planRunning,
    phase = status.phase,
    statusText = status.statusText,
    model = status.model,
    backend = status.backend,
    signedIn = status.signedIn,
    approvalCaption = status.approvalCaption,
    effort = status.effort,
    skill = status.skill,
    contextText = status.contextText,
    canSend = status.canSend,
    canSteer = status.canSteer,
    canStop = status.canStop,
    canChangeMode = status.canChangeMode,
    remoteApproval = status.remoteApproval,
    errorText = status.errorText
  )
}

class MonitorViewModel(application: Application) : AndroidViewModel(application) {
  private val store = HostStore(application)
  private val offlineStore = OfflineStore(File(application.filesDir, "offline-cache.json"))
  private val session = LanSession(store)
  private var savedCache = ""
  private val images = ImageAssembly()
  private val displayPrefs = application.getSharedPreferences(DisplayPreferenceFile, Context.MODE_PRIVATE)
  private val display = object : DisplayPreferences {
    override val showThinking: Boolean get() = displayPrefs.getBoolean(DisplayThinkingKey, true)
    override val showTools: Boolean get() = displayPrefs.getBoolean(DisplayToolsKey, true)
  }
  private val coordinator = MonitorCoordinator(session, SystemMonitorClock, display)
  private val imageCache = ImagePixelCache()
  private var viewWidthPx = 0
  private val bitmapsState = MutableStateFlow<Map<String, Bitmap>>(emptyMap())
  private val uiState: MutableStateFlow<MonitorUi>
  val ui: StateFlow<MonitorUi>
  val bitmaps: StateFlow<Map<String, Bitmap>> = bitmapsState.asStateFlow()
  val link: StateFlow<computing.michell.monitor.connection.LinkStatus> = session.status
  private val screenState = MutableStateFlow(AppTab.Conversation)
  val tab: StateFlow<AppTab> = screenState.asStateFlow()
  val pairAddress = MutableStateFlow("")
  val pairPort = MutableStateFlow(MonitorLimits.ListenPort.toString())
  private val dictationState = MutableStateFlow(DictationState())
  val dictation: StateFlow<DictationState> = dictationState.asStateFlow()
  private val permissionRequestState = MutableStateFlow(false)
  val dictationPermissionRequest: StateFlow<Boolean> = permissionRequestState.asStateFlow()
  private var pendingSelectionStart = 0
  private var pendingSelectionEnd = 0
  private var callbackSession = 0
  private var supportGeneration = 0
  private var recognitionSupported = true
  private var supportPending = false
  private var linkGrace: Job? = null
  // Callbacks splice the prompt only. They must not call sendOrSteer.
  private val engineListener = object : SpeechEngineListener {
    override fun onReady(generation: Int) {
    }

    override fun onBeginningOfSpeech(generation: Int) {
    }

    override fun onEndOfSpeech(generation: Int) {
    }

    override fun onPartial(generation: Int, text: String) {
      onDictationPartial(generation, text)
    }

    override fun onFinal(generation: Int, text: String) {
      onDictationFinal(generation, text)
    }

    override fun onError(generation: Int, code: Int) {
      onDictationError(generation, code)
    }

    override fun onReadyToListen(generation: Int) {
      onSupportReady(generation)
    }

    override fun onLanguageBlocked(generation: Int, language: OnDeviceLanguage) {
      onSupportBlocked(generation, language)
    }

    override fun onSupportFailed(generation: Int, code: Int) {
      onSupportError(generation, code)
    }
  }
  private val engine: SpeechEngine = OnDeviceSpeechEngine(application, engineListener)
  private val finalWatch = DictationFinalWatch(viewModelScope, onExpired = ::abandonAwaitingFinal)

  init {
    val record = store.load()
    pairAddress.value = record.address
    pairPort.value = record.port.toString()
    val cached = offlineStore.load()
    if (cached != null || record.address.isEmpty()) {
      val seeded = if (cached != null) applyOfflineCache(coordinator.state, cached, record.address.isNotEmpty())
      else coordinator.state.copy(disconnected = true, banner = NoAddressBanner, reachedLive = false)
      coordinator.restoreOffline(seeded)
      if (cached != null) savedCache = encodeOfflineCache(cached)
    }
    uiState = MutableStateFlow(coordinator.state)
    ui = uiState.asStateFlow()
    viewModelScope.launch(Dispatchers.Default) {
      session.messages.collect { message -> applyIncoming(message) }
    }
    viewModelScope.launch(Dispatchers.Default) {
      while (isActive) {
        delay(ScreenRefreshMs)
        val effects = coordinator.flush(uiState.value) ?: continue
        withContext(Dispatchers.Main) { applyUiEffects(effects) }
      }
    }
    viewModelScope.launch {
      session.status.collect { status -> onLink(status) }
    }
    viewModelScope.launch(Dispatchers.Default) {
      session.commandResults.collect { result ->
        val effects = coordinator.onEvent(MonitorEvent.CommandResult(uiState.value, result)) ?: return@collect
        withContext(Dispatchers.Main) { applyUiEffects(effects) }
      }
    }
    // Creation is on the main thread. available() does not create the recognizer.
    if (!engine.available()) {
      dictationState.value = DictationState(statusMessage = DictationUnavailableMessage, available = false)
    }
    if (record.address.isNotEmpty()) {
      coordinator.onEvent(MonitorEvent.HostChanged(coordinator.state, record.address, record.port, record.clientId))
      session.connect(record.address, record.port)
    }
  }

  fun selectTab(tab: AppTab) {
    if (tab != AppTab.Conversation) leaveDictation()
    screenState.value = tab
  }

  fun updateDraft(text: String) {
    if (dictationState.value.phase != DictationPhase.Idle) {
      editPrompt(text, text.length, text.length)
      return
    }
    storeDraft(text)
  }

  fun changePrompt(text: String, selectionStart: Int, selectionEnd: Int) {
    if (dictationState.value.phase != DictationPhase.Idle) {
      editPrompt(text, selectionStart, selectionEnd)
      return
    }
    if (text != uiState.value.draft) updateDraft(text)
    val length = text.length
    dictationState.value = dictationState.value.copy(
      selectionStart = selectionStart.coerceIn(0, length),
      selectionEnd = selectionEnd.coerceIn(0, length)
    )
  }

  fun toggleDictationOn(selectionStart: Int, selectionEnd: Int, showRationale: Boolean) {
    if (dictationState.value.phase != DictationPhase.Idle || supportPending) return
    if (!recognitionSupported || !engine.available()) {
      dictationState.value = dictationState.value.copy(statusMessage = DictationUnavailableMessage, available = false)
      return
    }
    if (!microphoneGranted()) {
      when (microphoneAsk(false, microphoneAsked(), showRationale)) {
        MicrophoneAsk.ExplainSettings -> {
          permissionRequestState.value = false
          dictationState.value = dictationState.value.copy(statusMessage = MicrophoneSettingsMessage)
        }
        MicrophoneAsk.RequestPermission -> {
          pendingSelectionStart = selectionStart
          pendingSelectionEnd = selectionEnd
          permissionRequestState.value = true
        }
        MicrophoneAsk.Start -> beginDictation(selectionStart, selectionEnd)
      }
      return
    }
    beginDictation(selectionStart, selectionEnd)
  }

  fun consumeDictationPermissionRequest() {
    permissionRequestState.value = false
  }

  fun toggleDictationOff() {
    val state = dictationState.value
    if (state.phase != DictationPhase.Listening) return
    val sessionId = state.sessionId
    val step = applyDictation(DictationEvent.ToggleOff(sessionId))
    if (step.state.phase != DictationPhase.AwaitingFinal) return
    var thrown = false
    val accepted = try {
      engine.stopListening()
    } catch (error: Exception) {
      thrown = true
      false
    }
    when (dictationStopFollowUp(step.state.phase, accepted, thrown)) {
      DictationStopFollowUp.ArmDeadline -> finalWatch.arm(sessionId)
      DictationStopFollowUp.ReportFailure -> abandonAwaitingFinal(sessionId)
      DictationStopFollowUp.Idle -> {}
    }
  }

  fun dictationPermission(granted: Boolean) {
    permissionRequestState.value = false
    rememberMicrophoneAsked()
    if (!granted) {
      dictationState.value = dictationState.value.copy(statusMessage = MicrophoneRequiredMessage)
      return
    }
    beginDictation(pendingSelectionStart, pendingSelectionEnd)
  }

  fun editPrompt(text: String, selectionStart: Int, selectionEnd: Int) {
    val before = dictationState.value
    val step = reduceDictation(before, text, DictationEvent.Edited(selectionStart, selectionEnd))
    dictationState.value = step.state
    storeDraft(step.draft)
    if (before.phase != DictationPhase.Idle && step.state.phase == DictationPhase.Idle) {
      callbackSession = 0
      supportGeneration = 0
      finalWatch.cancel()
      engine.cancel()
    }
  }

  fun leaveDictation() {
    supportPending = false
    supportGeneration = 0
    finalWatch.cancel()
    applyDictation(DictationEvent.LeaveScreen)
    callbackSession = 0
    supportGeneration = 0
    engine.cancel()
  }

  fun connectFromPair() {
    val address = pairAddress.value.trim()
    val port = pairPort.value.toIntOrNull() ?: MonitorLimits.ListenPort
    pairPort.value = port.toString()
    if (address.isEmpty() || port !in 1..65535) {
      uiState.update { it.copy(banner = "Enter the desktop address and port.", pairHold = true) }
      return
    }
    val record = store.load()
    val endpointChanged = record.address != address || record.port != port
    val clientId = if (endpointChanged) "" else record.clientId
    val effects = coordinator.onEvent(MonitorEvent.HostChanged(uiState.value, address, port, clientId))
    if (effects != null) applyUiEffects(effects)
    uiState.update { it.copy(pairHold = false, settingsOpen = false, disconnected = true, banner = ConnectingBanner) }
    session.connect(address, port)
  }

  fun showSettings() {
    leaveDictation()
    uiState.update { it.copy(settingsOpen = true, banner = "") }
  }

  fun closeSettings() {
    uiState.update { it.copy(settingsOpen = false) }
  }

  fun forgetPairing() {
    leaveDictation()
    val effects = coordinator.onEvent(MonitorEvent.ForgetPairing(uiState.value)) ?: emptyList()
    applyUiEffects(effects)
    session.disconnect()
    store.clear()
  }

  fun sendOrSteer() {
    if (dictationState.value.sendMustWait) return
    val effects = coordinator.onEvent(MonitorEvent.Submit(uiState.value)) ?: return
    applyUiEffects(effects)
  }

  fun stop() {
    session.sendCatalogue(encodeEmpty(MessageKind.Stop, session.nextCommandId()))
  }

  fun newConversation() {
    leaveDictation()
    if (!uiState.value.view.canSend || uiState.value.disconnected) return
    session.sendCatalogue(encodeEmpty(MessageKind.NewConversation, session.nextCommandId()))
  }

  fun setMode(mode: String) {
    if (!ModeNames.contains(mode) || !uiState.value.view.canChangeMode) return
    session.sendCatalogue(encodeSetMode(session.nextCommandId(), mode))
  }

  fun setShowThinking(value: Boolean) {
    displayPrefs.edit().putBoolean(DisplayThinkingKey, value).apply()
    uiState.value = coordinator.noteDisplay(uiState.value)
  }

  fun setShowTools(value: Boolean) {
    displayPrefs.edit().putBoolean(DisplayToolsKey, value).apply()
    uiState.value = coordinator.noteDisplay(uiState.value)
  }

  fun noteVisibleTurns(indices: Set<Int>) {
    val effects = coordinator.noteVisibleTurns(uiState.value, indices)
    if (effects.isEmpty()) return
    applyUiEffects(effects)
  }

  fun noteViewWidth(px: Int) {
    if (px > 0) viewWidthPx = px
  }

  fun requestTurn(index: Int) {
    if (index < 0) return
    val effects = coordinator.requestTurnFetch(uiState.value, index)
    if (effects.isEmpty()) return
    applyUiEffects(effects)
  }

  private var planBrowseGeneration = 0

  fun browsePlans() {
    if (uiState.value.disconnected) return
    val generation = ++planBrowseGeneration
    uiState.update { it.copy(planFiles = null, banner = "") }
    session.sendCatalogue(encodePlanBrowse(session.nextCommandId()))
    viewModelScope.launch {
      delay(15_000)
      if (generation != planBrowseGeneration) return@launch
      uiState.update {
        if (it.planFiles == null && it.banner.isEmpty() && !it.disconnected)
          it.copy(banner = "No Markdown list received. Check the connection and update the desktop monitor package.")
        else it
      }
    }
  }

  fun openPlan(path: String) {
    if (uiState.value.disconnected) return
    uiState.update { it.copy(selectedPlan = -1) }
    session.sendCatalogue(encodePath(MessageKind.SelectPlan, session.nextCommandId(), path))
  }

  fun selectPlan(index: Int) {
    uiState.update { it.copy(selectedPlan = index) }
  }

  fun workOnPlan() {
    val index = uiState.value.selectedPlan
    if (index < 0) return
    session.sendCatalogue(encodeWorkOnPlan(session.nextCommandId(), index))
  }

  fun runPlan() {
    session.sendCatalogue(encodeEmpty(MessageKind.RunPlan, session.nextCommandId()))
  }

  fun stopPlan() {
    session.sendCatalogue(encodeEmpty(MessageKind.StopPlan, session.nextCommandId()))
  }

  fun newPlan(title: String) {
    val hasTitle = title.isNotEmpty()
    session.sendCatalogue(encodeNewPlan(session.nextCommandId(), title, hasTitle))
  }

  fun removePlan() {
    session.sendCatalogue(encodePath(MessageKind.RemovePlan, session.nextCommandId(), uiState.value.planPath))
  }

  fun allowApproval() {
    val notice = uiState.value.approval ?: return
    if (!notice.decisionsAccepted) return
    session.sendCatalogue(encodeApprovalDecision(session.nextCommandId(), notice.toolId, true))
  }

  fun denyApproval() {
    val notice = uiState.value.approval ?: return
    if (!notice.decisionsAccepted) return
    session.sendCatalogue(encodeApprovalDecision(session.nextCommandId(), notice.toolId, false))
  }

  fun dismissApproval() {
    uiState.update { it.copy(approvalOpen = false) }
  }

  override fun onCleared() {
    rememberDisplayed(uiState.value)
    supportPending = false
    linkGrace?.cancel()
    finalWatch.cancel()
    engine.destroy()
    session.close()
  }

  private fun rememberDisplayed(ui: MonitorUi) {
    if (!worthCaching(ui)) {
      if (savedCache.isEmpty()) return
      savedCache = ""
      viewModelScope.launch(Dispatchers.IO) {
        try {
          offlineStore.clear()
        } catch (error: Exception) {
        }
      }
      return
    }
    val text = encodeOfflineCache(offlineDocument(ui))
    if (text == savedCache) return
    savedCache = text
    viewModelScope.launch(Dispatchers.IO) {
      try {
        offlineStore.save(text)
      } catch (error: Exception) {
        // A failed local copy must not drop the live session.
      }
    }
  }

  private suspend fun applyIncoming(message: MonitorMessage) {
    val effects = coordinator.onEvent(MonitorEvent.Incoming(uiState.value, message)) ?: return
    execute(effects)
  }

  private fun onLink(status: computing.michell.monitor.connection.LinkStatus) {
    applyUiEffects(coordinator.onEvent(MonitorEvent.LinkChanged(uiState.value, status)) ?: return)
    linkGrace?.cancel()
    if (!coordinator.holdingLink) return
    linkGrace = viewModelScope.launch {
      delay(LinkGraceMs)
      if (!coordinator.holdingLink) return@launch
      val effects = coordinator.revealHeldLink(uiState.value, session.status.value) ?: return@launch
      applyUiEffects(effects)
    }
  }

  private suspend fun execute(effects: List<MonitorEffect>) {
    val decoded = mutableListOf<DecodedImage>()
    for (effect in effects) {
      if (effect is MonitorEffect.DecodeImage) {
        val generation = uiState.value.hostGeneration
        val bitmap = decodeBitmap(effect.message)
        val expired = images.takeExpired()
        if (expired.isNotEmpty()) coordinator.noteImagesExpired(expired)
        if (bitmap != null && uiState.value.hostGeneration == generation) {
          val cacheKey = ImageCacheKey(generation, bitmap.imageId, bitmap.revision)
          coordinator.noteBitmap(imageCacheText(cacheKey))
          coordinator.noteImageFetched(bitmap.imageId)
          decoded += bitmap
        }
      }
    }
    val copyState = effects.any { it !is MonitorEffect.DecodeImage }
    withContext(Dispatchers.Main) {
      for (image in decoded) storeDecoded(image)
      if (copyState) applyUiEffects(effects)
    }
  }

  private fun applyUiEffects(effects: List<MonitorEffect>) {
    uiState.value = coordinator.state
    rememberDisplayed(uiState.value)
    dropCachedBitmaps(imageCache.retain(uiState.value.hostGeneration, snapshotImageTurns(uiState.value)))
    for (effect in effects) {
      when (effect) {
        is MonitorEffect.DecodeImage -> {}
        MonitorEffect.LeaveDictation -> leaveDictation()
        is MonitorEffect.RememberDraft -> session.updateDraft(effect.text)
        is MonitorEffect.Send -> session.sendCatalogue(effect.json)
        MonitorEffect.Prefetch -> applyUiEffects(coordinator.collectMissing(uiState.value))
        MonitorEffect.ClearCaches -> {
          images.reset()
          imageCache.reset()
          bitmapsState.value = emptyMap()
        }
      }
    }
  }

  private fun onDictationPartial(generation: Int, text: String) {
    if (!acceptSpeechCallback(callbackSession, generation)) return
    val before = dictationState.value
    releaseIfClosed(before, applyDictation(DictationEvent.Partial(generation, text)))
  }

  private fun onDictationFinal(generation: Int, text: String) {
    if (!acceptSpeechCallback(callbackSession, generation)) return
    val before = dictationState.value
    val step = applyDictation(DictationEvent.Final(generation, text))
    if (step.state.phase == DictationPhase.Idle) finalWatch.cancel()
    releaseIfClosed(before, step)
  }

  private fun onDictationError(generation: Int, code: Int) {
    if (!acceptSpeechCallback(callbackSession, generation)) return
    finalWatch.cancel()
    if (code == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED) {
      recognitionSupported = false
      dictationState.value = dictationState.value.copy(available = false)
    }
    val before = dictationState.value
    val step = applyDictation(DictationEvent.Failure(generation, speechFailureMessage(code)))
    callbackSession = 0
    if (code == SpeechRecognizer.ERROR_CLIENT) engine.destroy()
    else releaseIfClosed(before, step)
  }

  private fun onSupportReady(generation: Int) {
    if (!acceptSpeechCallback(supportGeneration, generation) || !supportPending) return
    supportPending = false
    supportGeneration = 0
    startListeningSession(pendingSelectionStart, pendingSelectionEnd)
  }

  private fun onSupportBlocked(generation: Int, language: OnDeviceLanguage) {
    if (!acceptSpeechCallback(supportGeneration, generation) || !supportPending) return
    supportPending = false
    supportGeneration = 0
    when (language) {
      OnDeviceLanguage.Downloading -> showSpeechStatus(DictationModelDownloadingMessage, false)
      OnDeviceLanguage.NeedsDownload -> showSpeechStatus(DictationModelDownloadMessage, false)
      OnDeviceLanguage.OnlineOnly, OnDeviceLanguage.Missing -> {
        recognitionSupported = false
        showSpeechStatus(DictationLanguageUnsupportedMessage, true)
      }
      OnDeviceLanguage.Installed -> startListeningSession(pendingSelectionStart, pendingSelectionEnd)
    }
  }

  private fun onSupportError(generation: Int, code: Int) {
    if (!acceptSpeechCallback(supportGeneration, generation) || !supportPending) return
    supportPending = false
    supportGeneration = 0
    if (code == SpeechRecognizer.ERROR_CLIENT) engine.destroy()
    val unavailable = code == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED
    if (unavailable) recognitionSupported = false
    showSpeechStatus(speechFailureMessage(code), unavailable)
  }

  private fun showSpeechStatus(message: String, unavailable: Boolean) {
    dictationState.value = dictationState.value.copy(
      statusMessage = message,
      available = if (unavailable) false else dictationState.value.available
    )
  }

  private fun applyDictation(event: DictationEvent): DictationStep {
    val step = reduceDictation(dictationState.value, uiState.value.draft, event)
    dictationState.value = step.state
    storeDraft(step.draft)
    return step
  }

  private fun releaseIfClosed(before: DictationState, step: DictationStep) {
    if (before.phase == DictationPhase.Idle || step.state.phase != DictationPhase.Idle) return
    callbackSession = 0
    supportGeneration = 0
    finalWatch.cancel()
    engine.cancel()
  }

  private fun abandonAwaitingFinal(sessionId: Int) {
    val state = dictationState.value
    if (state.phase != DictationPhase.AwaitingFinal || state.sessionId != sessionId) return
    finalWatch.cancel()
    callbackSession = 0
    supportGeneration = 0
    engine.cancel()
    applyDictation(DictationEvent.Expired(sessionId))
  }

  private fun storeDraft(text: String) {
    applyUiEffects(coordinator.onEvent(MonitorEvent.DraftEdited(uiState.value, text)) ?: return)
  }

  private fun beginDictation(selectionStart: Int, selectionEnd: Int) {
    if (supportPending || dictationState.value.phase != DictationPhase.Idle) return
    permissionRequestState.value = false
    pendingSelectionStart = selectionStart
    pendingSelectionEnd = selectionEnd
    supportGeneration = dictationState.value.sessionId + 1
    supportPending = true
    if (engine.checkSupport(supportGeneration)) return
    supportGeneration = 0
    supportPending = false
    showSpeechStatus(DictationUnavailableMessage, true)
  }

  private fun startListeningSession(selectionStart: Int, selectionEnd: Int) {
    finalWatch.cancel()
    val step = applyDictation(DictationEvent.Start(selectionStart, selectionEnd))
    if (!step.state.listening) return
    callbackSession = step.state.sessionId
    if (engine.start(callbackSession)) return
    callbackSession = 0
    dictationState.value = dictationState.value.copy(available = false)
    applyDictation(DictationEvent.Failure(step.state.sessionId, DictationUnavailableMessage))
    engine.cancel()
  }

  private fun microphoneGranted(): Boolean {
    return getApplication<Application>().checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
  }

  private fun microphoneAsked(): Boolean {
    return displayPrefs.getBoolean(DictationPermissionAskedKey, false)
  }

  private fun rememberMicrophoneAsked() {
    if (microphoneAsked()) return
    displayPrefs.edit().putBoolean(DictationPermissionAskedKey, true).commit()
  }

  private fun decodeBitmap(message: MonitorMessage): DecodedImage? {
    val part = message.inbound as? InboundPayload.ImagePart ?: return null
    val joined = images.accept(part.image, part.bytes) ?: return null
    val bounds = BitmapFactory.Options()
    bounds.inJustDecodeBounds = true
    BitmapFactory.decodeByteArray(joined, 0, joined.size, bounds)
    val plan = bitmapBoundsPlan(bounds.outWidth, bounds.outHeight, viewWidthPx)
    if (!plan.allocate) return null
    val pixels = BitmapFactory.Options()
    pixels.inSampleSize = plan.sampleSize
    pixels.inPreferredConfig = Bitmap.Config.ARGB_8888
    val bitmap = BitmapFactory.decodeByteArray(joined, 0, joined.size, pixels) ?: return null
    val turnIndex = coordinator.turnForImage(part.image.imageId) ?: uiState.value.live?.turnIndex ?: -1
    return DecodedImage(uiState.value.hostGeneration, part.image.imageId, part.image.revision, turnIndex, bitmap)
  }

  private fun storeDecoded(image: DecodedImage) {
    val generation = uiState.value.hostGeneration
    if (image.hostGeneration != generation) return
    val key = ImageCacheKey(generation, image.imageId, image.revision)
    val bytes = decodedBytes(image.bitmap.width, image.bitmap.height) ?: return
    val removed = imageCache.insert(key, image.turnIndex, bytes, generation, snapshotImageTurns(uiState.value))
    bitmapsState.update { current ->
      val next = current.toMutableMap()
      for (gone in removed) next.remove(imageCacheText(gone))
      if (key in imageCache.keys) next[imageCacheText(key)] = image.bitmap
      next
    }
  }

  private fun dropCachedBitmaps(removed: Set<ImageCacheKey>) {
    if (removed.isEmpty()) return
    bitmapsState.update { current ->
      val next = current.toMutableMap()
      for (key in removed) next.remove(imageCacheText(key))
      next
    }
  }
}

private data class DecodedImage(
  val hostGeneration: Int,
  val imageId: String,
  val revision: Int,
  val turnIndex: Int,
  val bitmap: Bitmap
)

private fun snapshotImageTurns(state: MonitorUi): Set<Int> {
  val indices = state.turns.map { turn -> turn.turnIndex }.toMutableSet()
  val live = state.live
  if (live != null) indices += live.turnIndex
  return indices
}

private fun speechFailureMessage(code: Int): String {
  return when (code) {
    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> MicrophoneRequiredMessage
    SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> DictationNoSpeechDetectedMessage
    SpeechRecognizer.ERROR_NO_MATCH -> DictationNoSpeechMessage
    SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> DictationBusyMessage
    SpeechRecognizer.ERROR_AUDIO -> DictationAudioMessage
    SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> DictationLanguageMissingMessage
    SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> DictationLanguageUnsupportedMessage
    SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT, SpeechRecognizer.ERROR_SERVER ->
      DictationOnDeviceFailedMessage
    SpeechRecognizer.ERROR_CLIENT, SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> DictationStoppedMessage
    else -> DictationFailedMessage
  }
}

const val MicrophoneRequiredMessage = "Microphone permission is required."
const val MicrophoneSettingsMessage = "Microphone permission is off. System settings can enable it."

enum class MicrophoneAsk {
  Start,
  RequestPermission,
  ExplainSettings
}

fun microphoneAsk(granted: Boolean, asked: Boolean, showRationale: Boolean): MicrophoneAsk {
  if (granted) return MicrophoneAsk.Start
  if (asked && !showRationale) return MicrophoneAsk.ExplainSettings
  return MicrophoneAsk.RequestPermission
}

private const val ScreenRefreshMs = 250L
private const val DisplayPreferenceFile = "monitor-display"
private const val DisplayThinkingKey = "thinking"
private const val DisplayToolsKey = "tools"
private const val DictationPermissionAskedKey = "dictation-asked"
