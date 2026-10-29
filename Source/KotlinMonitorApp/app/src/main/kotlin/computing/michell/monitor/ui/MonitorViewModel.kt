package computing.michell.monitor.ui

/* Android shell for the monitor catalogue (c) 2026 Michell Computing.

   Size note: exceeds the 1000 line preference. Catalogue events live in
   MonitorCoordinator. Prompt acknowledgement lives in PromptAcknowledgement.
   The final-result deadline lives in DictationFinalWatch. Image request
   and cache policy live in ImageCache. What remains is speech,
   preferences, bitmap decode, and effect execution.
   Offline copies are Room rows. The retired file cache is imported once.
   Reviewed 2026-10-29. */

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
import computing.michell.monitor.data.ConversationRecord
import computing.michell.monitor.data.ConversationRepository
import computing.michell.monitor.data.MonitorImageDirectoryName
import computing.michell.monitor.data.importLegacyCache
import computing.michell.monitor.data.openMonitorDatabase
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
import java.io.ByteArrayOutputStream
import computing.michell.monitor.protocol.ApprovalNotice
import computing.michell.monitor.protocol.ErrorBody
import computing.michell.monitor.protocol.ImageAssembly
import computing.michell.monitor.protocol.HelloOkMessage
import computing.michell.monitor.protocol.InboundPayload
import computing.michell.monitor.protocol.MirrorPlace
import computing.michell.monitor.protocol.WireCatchup
import computing.michell.monitor.protocol.WirePatch
import computing.michell.monitor.protocol.applyPhoneCatchup
import computing.michell.monitor.protocol.applyBlockDataJson
import computing.michell.monitor.protocol.applyPhonePatch
import computing.michell.monitor.protocol.noteHelloIdentity
import computing.michell.monitor.protocol.notePhoneClosed
import computing.michell.monitor.protocol.notePhoneEpoch
import computing.michell.monitor.protocol.PhoneScreen
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.ModeNames
import computing.michell.monitor.protocol.MonitorLimits
import computing.michell.monitor.protocol.MonitorMessage
import computing.michell.monitor.protocol.OfflineCacheDocument
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
import computing.michell.monitor.protocol.decodeSnapshot
import computing.michell.monitor.protocol.decodeStatusPayload
import computing.michell.monitor.protocol.decodeTarget
import computing.michell.monitor.protocol.decodeTargets

import computing.michell.monitor.protocol.decodeText
import computing.michell.monitor.protocol.applySnapshotPageJson
import computing.michell.monitor.protocol.snapshotPageTurn

import computing.michell.monitor.protocol.encodeApprovalDecision
import computing.michell.monitor.protocol.encodeEmpty
import computing.michell.monitor.protocol.encodePlanChoices
import computing.michell.monitor.protocol.PlanChoice
import computing.michell.monitor.protocol.ConversationChoice
import computing.michell.monitor.protocol.ConversationsMessage
import computing.michell.monitor.protocol.ModelChoice
import computing.michell.monitor.protocol.ModelsMessage
import computing.michell.monitor.protocol.PermissionChoice
import computing.michell.monitor.protocol.PermissionsMessage
import computing.michell.monitor.protocol.ReasoningChoice
import computing.michell.monitor.protocol.ReasoningMessage
import computing.michell.monitor.protocol.decodeModels
import computing.michell.monitor.protocol.decodePermissions
import computing.michell.monitor.protocol.decodeReasoning
import computing.michell.monitor.protocol.encodeMenuChoices
import computing.michell.monitor.protocol.encodeSetModel
import computing.michell.monitor.protocol.encodeSetPermissions
import computing.michell.monitor.protocol.encodeSetReasoning
import computing.michell.monitor.protocol.TargetChoice
import computing.michell.monitor.protocol.TargetsMessage
import computing.michell.monitor.protocol.decodeConversations
import computing.michell.monitor.protocol.encodeSelectConversation
import computing.michell.monitor.protocol.hostIdIsValid
import computing.michell.monitor.protocol.encodeNewPlan
import computing.michell.monitor.protocol.encodePath
import computing.michell.monitor.protocol.encodeSetMode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import java.io.File

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
  val planChoices: List<PlanChoice> = emptyList(),
  val targetChoices: List<TargetChoice> = emptyList(),
  val targetCurrent: String = "",
  val conversationChoices: List<ConversationChoice> = emptyList(),
  val conversationCurrent: String = "",
  val conversationsTruncated: Boolean = false,
  val modelChoices: List<ModelChoice> = emptyList(),
  val modelBackend: String = "",
  val modelNote: String = "",
  val reasoningChoices: List<ReasoningChoice> = emptyList(),
  val reasoningCurrent: String = "",
  val reasoningNote: String = "",
  val permissionChoices: List<PermissionChoice> = emptyList(),
  val permissionCurrent: String = "",
  val permissionNote: String = "",
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
  val activityAppliedMs: Long = 0,
  val clockToken: Int = 0,
  val hostGeneration: Int = 0,
  val conversationGeneration: Int = 0,
  val connectionGeneration: Int = 0,
  val transcriptConnection: Int = 0,
  val transcriptTurnId: String = "",
  val hostEpoch: String = "",
  val hostCursor: Long = 0,
  val catchingUp: Boolean = false,
  val announcedEpoch: String = "",
  val conversationId: String = "",
  val projectRoot: String = "",
  val conversationTitle: String = "",
  val closedConversationId: String = "",
  val closedTitle: String = "",
  val patchParts: Map<Int, List<WireBlock>> = emptyMap(),
  val patchPartCount: Int = 0,
  val patchOpenCursor: Long = 0,
  val resumeOnce: Boolean = false,
  val closedPending: Boolean = false,
  val closedQueued: Boolean = false,
  val blockFetchIds: List<String> = emptyList()
)

/** Clears conversation identity. Keeps display preferences. An unsent draft is kept only when clearDraft is false. */
fun resetConversation(state: MonitorUi, clearDraft: Boolean, hostGeneration: Int, conversationGeneration: Int): MonitorUi {
  val keepDraft = !clearDraft && state.draft.isNotEmpty() && state.pendingPrompt.isEmpty()
  return MonitorUi(
    draft = if (keepDraft) state.draft else "",
    showThinking = state.showThinking,
    showTools = state.showTools,
    settingsOpen = state.settingsOpen,
    targetChoices = state.targetChoices,
    targetCurrent = state.targetCurrent,
    conversationChoices = state.conversationChoices,
    conversationCurrent = state.conversationCurrent,
    conversationsTruncated = state.conversationsTruncated,
    modelChoices = state.modelChoices,
    modelBackend = state.modelBackend,
    modelNote = state.modelNote,
    reasoningChoices = state.reasoningChoices,
    reasoningCurrent = state.reasoningCurrent,
    reasoningNote = state.reasoningNote,
    permissionChoices = state.permissionChoices,
    permissionCurrent = state.permissionCurrent,
    permissionNote = state.permissionNote,
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
  // Patch flags are authoritative. A lost status frame must not leave the label on busy.
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
const val StallGapMs = 5_000L

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

fun patchSaysIdle(busy: Boolean, sending: Boolean, planRunning: Boolean): Boolean {
  return !busy && !sending && !planRunning
}

/** The displayed clock is this sample plus local time since the patch was applied. */
fun patchClockBase(elapsedMs: Int, appliedAtMs: Long): Long {
  if (appliedAtMs <= 0L) return 0L
  val elapsed = elapsedMs.coerceAtLeast(0).toLong()
  return (appliedAtMs - elapsed).coerceAtLeast(0L)
}

fun notePatchClock(state: MonitorUi, elapsedMs: Int, idle: Boolean, nowMs: Long): MonitorUi {
  if (idle || nowMs <= 0L) {
    return state.copy(activityStartedMs = 0L, activityObservedMs = 0, activityAppliedMs = nowMs.coerceAtLeast(0L))
  }
  val elapsed = elapsedMs.coerceAtLeast(0)
  return state.copy(
    activityStartedMs = patchClockBase(elapsed, nowMs),
    activityObservedMs = elapsed,
    activityAppliedMs = nowMs
  )
}

fun turnStillRunning(view: WireView, pending: Boolean, blocks: List<WireBlock>, live: WireTurn? = null): Boolean {
  if (hasWorkedFooter(blocks)) return false
  if (pending || view.sending || view.busy || view.planRunning) return true
  if (blocks.any { block -> block.running }) return true
  if (view.phase.isEmpty() && view.elapsedMs == 0) return false
  if (live != null && live.turnIndex < 0) {
    if (live.durationMs > 0) return true
    if (blocks.any { block -> block.kind in WorkKinds }) return true
  }
  return false
}

fun observedElapsedMs(view: WireView, live: WireTurn?, blocks: List<WireBlock>): Int {
  val fromStatus = if (hostHasElapsed(view.statusText)) elapsedMsOf(view.statusText) else 0
  val fromView = view.elapsedMs.coerceAtLeast(0)
  val fromLive = if (live != null && live.durationMs > 0) live.durationMs else 0
  val worked = blocks.lastOrNull { block -> block.kind == "worked" || block.body.startsWith("Worked for") }
  val fromWorked = if (worked == null) 0 else if (worked.durationMs > 0) worked.durationMs else elapsedMsOf(worked.body)
  return maxOf(fromStatus, fromView, fromLive, fromWorked)
}

/** Earlier start means more time has passed. A stale host sample must not pull the clock backward. */
fun activityStart(keptStart: Long, nowMs: Long, observedMs: Int, previousObservedMs: Int): Long {
  if (observedMs > 0 && observedMs == previousObservedMs && keptStart > 0L) return keptStart
  if (nowMs <= 0L) return keptStart.coerceAtLeast(0L)
  val hostStart = if (observedMs > 0) nowMs - observedMs else 0L
  if (hostStart > 0L && (keptStart <= 0L || hostStart < keptStart)) return hostStart
  if (keptStart > 0L) return keptStart
  return nowMs
}

/** Same live check connectionLabel uses. Anything else is no IDE connection. */
fun ideLinkLive(disconnected: Boolean, phase: LinkPhase): Boolean {
  return phase == LinkPhase.Live && !disconnected
}

fun displayInterrupted(ui: MonitorUi, phase: LinkPhase): Boolean {
  val pending = ui.pendingPrompt.isNotEmpty() && !promptShown(ui, ui.pendingPrompt)
  val running = ui.view.sending || ui.view.busy || ui.view.planRunning || pending
  if (!running) return false
  return ui.disconnected || phase != LinkPhase.Live
}

fun formatActivityClock(elapsedMs: Long): String {
  val secs = (elapsedMs / 1000L).toInt().coerceAtLeast(0)
  return "${secs / 60}:${(secs % 60).toString().padStart(2, '0')}"
}

const val PhaseWaiting = "Waiting…"
const val PhaseThinking = "Thinking…"
const val PhaseStreaming = "Streaming…"
const val PhaseRunning = "Running…"
const val PhaseSteering = "Steering…"
const val PhaseConnecting = "Connecting…"

fun progressPhase(name: String): String {
  return when (name) {
    "Waiting for first token…", "Waiting", "Waiting for model…" -> PhaseWaiting
    "Running tools…", "Subagent…", "Working…" -> PhaseRunning
    "Steer queued…", "Steering at next tool gap…", "Steering at next model gap…" -> PhaseSteering
    "Re-establishing Connection" -> PhaseConnecting
    else -> name
  }
}

fun activityPhase(view: WireView, pending: Boolean, pendingKind: String, blocks: List<WireBlock>): String {
  if (hostHasElapsed(view.statusText)) {
    val named = view.statusText.trim().substringBeforeLast(" ").trim()
    if (named.isNotEmpty() && named != "Ready" && named != "Offline" && named != "Not signed in") return progressPhase(named)
  }
  if (view.phase.isNotEmpty() && view.phase != "Ready" && view.phase != "Offline" && view.phase != "Not signed in") return progressPhase(view.phase)
  if (view.planRunning && view.statusText.isNotEmpty() && view.statusText != "Ready" &&
    view.statusText != "Offline" && view.statusText != "Not signed in") return view.statusText
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
  linkLive: Boolean = true
): String {
  // An invalid IDE link is Offline. Do not keep Ready, a progress word, or a reconnect clock.
  if (!linkLive) return "Offline"
  if (!turnStillRunning(view, pending, blocks, live)) {
    val text = view.statusText.trim()
    if (!view.signedIn || text == "Not signed in" || text == "Offline") return "Offline"
    if (text.isEmpty() || hostHasElapsed(text)) return "Ready"
    return text
  }
  val phase = activityPhase(view, pending, pendingKind, blocks)
  val start = if (startedMs > 0L) startedMs else nowMs
  if (nowMs <= 0L || start <= 0L || nowMs < start) return phase
  return "$phase ${formatActivityClock(nowMs - start)}"
}

fun beginSubmit(state: MonitorUi, text: String, steer: Boolean, nowMs: Long, commandId: String = ""): MonitorUi {
  val phase = if (steer) PhaseSteering else PhaseWaiting
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
  // Snapshot and transcript no longer race the screen. The reduced turn is the turn.
  val mergedLive = next.live
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
  val patchReplaced = next.activityAppliedMs > current.activityAppliedMs
  val start = when {
    !running -> 0L
    patchReplaced -> next.activityStartedMs
    else -> activityStart(keptStart, nowMs, observed, current.activityObservedMs)
  }
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
    MessageKind.Snapshot, MessageKind.Transcript, MessageKind.TurnData -> state
    MessageKind.SnapshotPage -> applySnapshotPage(state, message.payloadJson)
    MessageKind.Status -> applyStatus(state, message.payloadJson)
    MessageKind.Mode -> applyMode(state, message.payloadJson)
    MessageKind.Target -> applyTarget(state, message.payloadJson)
    MessageKind.Targets -> applyTargets(state, message.payloadJson)
    MessageKind.Conversations -> applyConversations(state, message.payloadJson)
    MessageKind.Models -> applyModels(state, message.payloadJson)
    MessageKind.Reasoning -> applyReasoning(state, message.payloadJson)
    MessageKind.Permissions -> applyPermissions(state, message.payloadJson)
    MessageKind.Plan -> applyPlan(state, message.payloadJson)
    MessageKind.ApprovalRequested -> applyApprovalRequested(state, message.payloadJson)
    MessageKind.ApprovalClosed -> state.copy(approvalOpen = false)
    MessageKind.InsertResult -> applyInsertResult(state, message.payloadJson)
    MessageKind.Rejected -> applyRejected(state, message)
    MessageKind.Error -> applyError(state, message.payloadJson)
    MessageKind.ImageUnavailable -> applyImageUnavailable(state, message.payloadJson)
    MessageKind.BlockData -> applyBlockDataMessage(state, message.payloadJson)
    // A host frame this build cannot apply stays on screen. It must not close the socket.
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

private fun mirrorOf(state: MonitorUi): MirrorPlace {
  return MirrorPlace(state.hostEpoch, state.hostCursor, state.catchingUp, state.announcedEpoch,
    state.conversationId, state.projectRoot, state.conversationTitle)
}

private fun MonitorUi.withMirror(place: MirrorPlace): MonitorUi {
  return copy(hostEpoch = place.epoch, hostCursor = place.cursor, catchingUp = place.catchingUp,
    announcedEpoch = place.announcedEpoch, conversationId = place.conversationId, projectRoot = place.projectRoot,
    conversationTitle = place.title)
}

private fun phoneOf(state: MonitorUi): PhoneScreen {
  return PhoneScreen(
    state.hostEpoch, state.hostCursor, state.catchingUp, state.announcedEpoch, state.turns, state.live,
    state.patchOpenCursor, state.patchPartCount, state.patchParts, state.resumeOnce, state.closedConversationId,
    state.closedTitle, "", state.conversationId, state.projectRoot, state.conversationTitle
  )
}

private fun MonitorUi.withPhone(phone: PhoneScreen): MonitorUi {
  val file = phone.fileClosedId.isNotEmpty() && !closedQueued
  return copy(
    hostEpoch = phone.epoch,
    hostCursor = phone.cursor,
    catchingUp = phone.catchingUp,
    announcedEpoch = phone.announcedEpoch,
    turns = phone.turns,
    live = phone.live,
    patchOpenCursor = phone.patchOpenCursor,
    patchPartCount = phone.patchPartCount,
    patchParts = phone.patchParts,
    resumeOnce = phone.resumeOnce,
    closedConversationId = phone.closedId,
    closedTitle = phone.closedTitle,
    closedPending = if (file) true else closedPending,
    closedQueued = closedQueued || file,
    conversationId = phone.conversationId,
    projectRoot = phone.projectRoot,
    conversationTitle = phone.title,
    blockFetchIds = phone.blockFetchIds
  )
}

private fun applyHelloIdentity(state: MonitorUi, hello: HelloOkMessage): MonitorUi {
  val hasScreen = state.live != null || state.turns.isNotEmpty() || state.history.isNotEmpty()
  var next = state.withMirror(noteHelloIdentity(mirrorOf(state), hello.epoch, hello.cursor, hello.conversationId,
    hello.projectRoot, hello.title, hasScreen))
  if (next.catchingUp && hello.epoch.isNotEmpty() && hello.epoch != state.hostEpoch) {
    val filed = notePhoneEpoch(phoneOf(state), hello.epoch)
    if (filed.fileClosedId.isNotEmpty() && !next.closedQueued) {
      next = next.copy(closedPending = true, closedQueued = true)
    }
  }
  if (next.catchingUp || hello.epoch != next.hostEpoch || hello.title.isEmpty() || hello.title == next.conversationTitle) return next
  return next.copy(conversationTitle = hello.title)
}

private fun applyBlockDataMessage(state: MonitorUi, payloadJson: String): MonitorUi {
  return state.withPhone(applyBlockDataJson(phoneOf(state), payloadJson))
}

private fun applyPatch(state: MonitorUi, patch: WirePatch): MonitorUi {
  val before = phoneOf(state)
  val phone = applyPhonePatch(before, patch)
  val next = state.withPhone(phone)
  val accepted = phone.live != before.live || phone.cursor != before.cursor || phone.patchParts != before.patchParts
  if (!accepted) return next
  return applyPatchFlags(next, patch).copy(reachedLive = true, clockToken = state.clockToken + 1)
}

private fun applyPatchFlags(state: MonitorUi, patch: WirePatch): MonitorUi {
  val flagged = state.view.copy(
    busy = patch.busy,
    sending = patch.sending,
    planRunning = patch.planRunning,
    phase = patch.phase,
    canSend = patch.canSend,
    canSteer = patch.canSteer,
    canStop = patch.canStop,
    elapsedMs = patch.elapsedMs
  )
  val view = if (patch.hasView) {
    flagged.copy(model = patch.model, signedIn = patch.signedIn, statusText = patch.statusText)
  } else {
    flagged
  }
  return state.copy(planRunning = patch.planRunning, view = view)
}

private fun applyCatchup(state: MonitorUi, catchup: WireCatchup): MonitorUi {
  if (catchup.epoch.isEmpty()) return state
  if (catchup.mode == "snapshot") {
    val snapshot = catchup.snapshot ?: return state
    val replaced = applySnapshot(state, snapshot)
    val phone = applyPhoneCatchup(
      phoneOf(state), catchup.epoch, catchup.cursor, catchup.conversationId, catchup.projectRoot, catchup.title,
      snapshot.storedTurns, snapshot.live
    )
    return replaced.copy(
      hostEpoch = phone.epoch,
      hostCursor = phone.cursor,
      catchingUp = false,
      announcedEpoch = "",
      turns = if (state.catchingUp) phone.turns else replaced.turns,
      live = if (state.catchingUp) phone.live else replaced.live,
      conversationId = phone.conversationId,
      projectRoot = phone.projectRoot,
      conversationTitle = phone.title,
      patchParts = emptyMap(),
      patchPartCount = 0,
      patchOpenCursor = 0,
      resumeOnce = false
    )
  }
  if (catchup.mode != "events" || state.catchingUp) return state
  if (state.hostEpoch.isNotEmpty() && catchup.epoch != state.hostEpoch) return state
  var next = state
  for (patch in catchup.patches) {
    val before = next.resumeOnce
    next = applyPatch(next, patch)
    if (next.resumeOnce && !before) break
  }
  return next.copy(
    conversationId = if (catchup.conversationId.isNotEmpty()) catchup.conversationId else next.conversationId,
    projectRoot = if (catchup.projectRoot.isNotEmpty()) catchup.projectRoot else next.projectRoot,
    conversationTitle = if (catchup.title.isNotEmpty()) catchup.title else next.conversationTitle
  )
}

private fun reduceInbound(state: MonitorUi, inbound: InboundPayload): MonitorUi {
  return when (inbound) {
    is InboundPayload.Snapshot, is InboundPayload.TranscriptPart, is InboundPayload.Turn -> state
    is InboundPayload.Status -> state.copy(view = state.view.patchStatus(inbound.view))
    is InboundPayload.Mode -> state.copy(view = state.view.copy(mode = inbound.value.mode, modeLocked = inbound.value.locked))
    is InboundPayload.Target -> applyTargetFrame(state, inbound.value.kind, inbound.value.display, inbound.value.root)
    is InboundPayload.Targets -> applyTargetsFrame(state, inbound.value)
    is InboundPayload.Conversations -> applyConversationsFrame(state, inbound.value)
    is InboundPayload.Models -> applyModelsFrame(state, inbound.value)
    is InboundPayload.Reasoning -> applyReasoningFrame(state, inbound.value)
    is InboundPayload.Permissions -> applyPermissionsFrame(state, inbound.value)
    is InboundPayload.Plan -> state.copy(
      planPath = inbound.value.path,
      planTitle = inbound.value.title,
      planRunning = inbound.value.running,
      planRows = inbound.value.rows,
      planChoices = inbound.value.choices.orEmpty(),
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
    is InboundPayload.HelloOk -> applyHelloIdentity(state, inbound.value)
    is InboundPayload.Patch -> applyPatch(state, inbound.value)
    is InboundPayload.Catchup -> applyCatchup(state, inbound.value)
    is InboundPayload.ConversationClosed -> state.withPhone(
      notePhoneClosed(phoneOf(state), inbound.value.conversationId, inbound.value.title)
    )
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
    val cleared = resetConversation(state, false, state.hostGeneration, state.conversationGeneration + 1)
    return overlaySnapshot(cleared, snapshot, state.generation + 1)
  }
  val previousId = state.live?.id ?: ""
  val acceptedNew = state.hostEpoch.isEmpty() && previousId.isNotEmpty() && previousId != incoming.id
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
    selectedPlan = -1,
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
  ).clearedMenuLists()
}

/** Snapshot drops the drawer lists. The following host frames fill them again. */
internal fun MonitorUi.clearedMenuLists(): MonitorUi {
  return copy(
    planChoices = emptyList(),
    targetChoices = emptyList(),
    targetCurrent = "",
    conversationChoices = emptyList(),
    conversationCurrent = "",
    conversationsTruncated = false,
    modelChoices = emptyList(),
    modelBackend = "",
    modelNote = "",
    reasoningChoices = emptyList(),
    reasoningCurrent = "",
    reasoningNote = "",
    permissionChoices = emptyList(),
    permissionCurrent = "",
    permissionNote = ""
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
    selectedPlan = -1,
    approval = if (approval.active) approval else null,
    approvalOpen = approval.active,
    reachedLive = true,
    pairHold = false,
    disconnected = false,
    banner = "",
    generation = generation,
    liveRevision = -1,
    transcriptParts = emptyMap()
  ).clearedMenuLists()
}

private fun applySnapshotPage(state: MonitorUi, payloadJson: String): MonitorUi {
  val applied = applySnapshotPageJson(state.turns, state.live, payloadJson) ?: return state
  val fetched = snapshotPageTurn(payloadJson)
  val history = if (fetched == null || applied.second?.id == fetched.id) state.history
    else state.history + (fetched.turnIndex to fetched)
  return state.copy(
    turns = applied.first,
    live = applied.second,
    history = history,
    reachedLive = true,
    generation = state.generation + 1
  )
}

/** A finished host turn. The status frame can be missed; this must not leave the label on busy. */
fun hostTranscriptIdle(phase: String, statusText: String): Boolean {
  val named = phase.trim()
  if (named.isNotEmpty() && named != "Ready" && named != "Offline" && named != "Not signed in") return false
  val text = statusText.trim()
  return text == "Ready" || text == "Offline" || text == "Not signed in"
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
  return applyTargetFrame(state, target.kind, target.display, target.root)
}

/** A new folder drops plan, target, and conversation lists. Connection lists stay. */
internal fun applyTargetFrame(state: MonitorUi, kind: String, display: String, root: String): MonitorUi {
  val sameFolder = state.view.targetRoot == root
  return state.copy(
    planChoices = if (sameFolder) state.planChoices else emptyList(),
    selectedPlan = if (sameFolder) state.selectedPlan else -1,
    targetChoices = if (sameFolder) state.targetChoices else emptyList(),
    targetCurrent = if (sameFolder) state.targetCurrent else "",
    conversationChoices = if (sameFolder) state.conversationChoices else emptyList(),
    conversationCurrent = if (sameFolder) state.conversationCurrent else "",
    conversationsTruncated = if (sameFolder) state.conversationsTruncated else false,
    view = state.view.copy(targetKind = kind, targetDisplay = display, targetRoot = root)
  )
}

private fun applyTargets(state: MonitorUi, payloadJson: String): MonitorUi {
  val targets = decodeTargets(payloadJson) ?: return state
  return applyTargetsFrame(state, targets)
}

private fun applyTargetsFrame(state: MonitorUi, targets: TargetsMessage): MonitorUi {
  return state.copy(targetChoices = targets.choices, targetCurrent = targets.current)
}

private fun applyConversations(state: MonitorUi, payloadJson: String): MonitorUi {
  val conversations = decodeConversations(payloadJson) ?: return state
  return applyConversationsFrame(state, conversations)
}

/** Replaces the history list only. Turns and the unsent draft stay. */
internal fun applyConversationsFrame(state: MonitorUi, conversations: ConversationsMessage): MonitorUi {
  return state.copy(
    conversationChoices = conversations.choices,
    conversationCurrent = conversations.current,
    conversationsTruncated = conversations.truncated
  )
}

private fun applyModels(state: MonitorUi, payloadJson: String): MonitorUi {
  val models = decodeModels(payloadJson) ?: return state
  return applyModelsFrame(state, models)
}

/** Replaces the model list only. The check stays on view.model until a status frame moves it. */
internal fun applyModelsFrame(state: MonitorUi, models: ModelsMessage): MonitorUi {
  return state.copy(
    modelChoices = models.choices,
    modelBackend = models.backend,
    modelNote = models.note
  )
}

private fun applyReasoning(state: MonitorUi, payloadJson: String): MonitorUi {
  val reasoning = decodeReasoning(payloadJson) ?: return state
  return applyReasoningFrame(state, reasoning)
}

/** Replaces the effort list only. view.effort is a caption and must not move this check. */
internal fun applyReasoningFrame(state: MonitorUi, reasoning: ReasoningMessage): MonitorUi {
  return state.copy(
    reasoningChoices = reasoning.choices,
    reasoningCurrent = reasoning.current,
    reasoningNote = reasoning.note
  )
}

private fun applyPermissions(state: MonitorUi, payloadJson: String): MonitorUi {
  val permissions = decodePermissions(payloadJson) ?: return state
  return applyPermissionsFrame(state, permissions)
}

/** Replaces the permission list only. view.approvalCaption is a short word and must not move this check. */
internal fun applyPermissionsFrame(state: MonitorUi, permissions: PermissionsMessage): MonitorUi {
  return state.copy(
    permissionChoices = permissions.choices,
    permissionCurrent = permissions.current,
    permissionNote = permissions.note
  )
}

private fun applyPlan(state: MonitorUi, payloadJson: String): MonitorUi {
  val plan = decodePlan(payloadJson) ?: return state
  return state.copy(
    planPath = plan.path,
    planTitle = plan.title,
    planRunning = plan.running,
    planRows = plan.rows,
    planChoices = plan.choices.orEmpty(),
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
    errorText = status.errorText,
    elapsedMs = status.elapsedMs
  )
}

/** The current id is a no-op. A different listed id is the only encode. */
internal fun targetSelectionCommand(state: MonitorUi, path: String, commandId: String): String? {
  if (state.disconnected || state.view.sending || state.view.planRunning || state.planRunning) return null
  if (path == state.targetCurrent || state.targetChoices.none { it.path == path }) return null
  return encodePath(MessageKind.SelectTarget, commandId, path)
}

internal fun conversationSelectionCommand(state: MonitorUi, id: String, commandId: String): String? {
  if (state.disconnected || state.view.sending) return null
  val selected = conversationSelectedId(state.conversationChoices, state.conversationCurrent)
  if (id == selected || state.conversationChoices.none { it.id == id }) return null
  return encodeSelectConversation(commandId, id)
}

internal fun modelSelectionCommand(state: MonitorUi, id: String, commandId: String): String? {
  if (state.disconnected || state.view.sending || state.view.planRunning || state.planRunning) return null
  if (id == state.view.model || state.modelChoices.none { it.id == id }) return null
  return encodeSetModel(commandId, id)
}

internal fun reasoningSelectionCommand(state: MonitorUi, id: String, commandId: String): String? {
  if (state.disconnected || state.view.sending || state.view.planRunning || state.planRunning) return null
  // Empty id is model default when that row exists. Compare the stored id, not view.effort.
  if (id == state.reasoningCurrent || state.reasoningChoices.none { it.id == id }) return null
  return encodeSetReasoning(commandId, id)
}

internal fun permissionsSelectionCommand(state: MonitorUi, id: String, commandId: String): String? {
  if (state.disconnected || state.view.sending || state.view.planRunning || state.planRunning) return null
  // Compare the stored id, not view.approvalCaption. This is not the tool-approval sheet.
  if (id == state.permissionCurrent || state.permissionChoices.none { it.id == id }) return null
  return encodeSetPermissions(commandId, id)
}

class MonitorViewModel(application: Application) : AndroidViewModel(application) {
  private val store = HostStore(application)
  private val database = openMonitorDatabase(application)
  private val imageRoot = File(application.filesDir, MonitorImageDirectoryName)
  private val conversations = ConversationRepository(database, imageRoot)
  private val session = LanSession(store)
  private val cacheGate = Any()
  private var cacheWriteSerial = 0
  private var cacheSaveJob: Job? = null
  private var suppressCache = false
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
  private val cacheListOpenState = MutableStateFlow(false)
  val cacheListOpen: StateFlow<Boolean> = cacheListOpenState.asStateFlow()
  private val cacheRowsState = MutableStateFlow<List<ConversationRecord>>(emptyList())
  val cacheRows: StateFlow<List<ConversationRecord>> = cacheRowsState.asStateFlow()
  private val cacheBackToListState = MutableStateFlow(false)
  val cacheBackToList: StateFlow<Boolean> = cacheBackToListState.asStateFlow()
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
    val restored = try {
      runBlocking(Dispatchers.IO) {
        importLegacyCache(application.filesDir, conversations, imageRoot)
        val key = if (hostIdIsValid(record.hostId)) record.hostId else record.fingerprint
        val open = newestConversation(conversations.listForHost(key), key) ?: return@runBlocking null
        val document = conversations.loadDocument(open.host, open.id) ?: return@runBlocking null
        open to document
      }
    } catch (error: Exception) {
      null
    }
    val open = restored?.first
    val cached = restored?.second
    if (cached != null || record.address.isEmpty()) {
      val seeded = if (cached != null) applyOfflineCache(coordinator.state, cached, record.address.isNotEmpty())
      else coordinator.state.copy(disconnected = true, banner = NoAddressBanner, reachedLive = false)
      coordinator.restoreOffline(seeded)
    }
    uiState = MutableStateFlow(coordinator.state)
    ui = uiState.asStateFlow()
    if (open != null && cached != null) restoreCachedImages(open.host, open.id, cached, uiState.value.hostGeneration)
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

  fun requestMenuChoices(linkLive: Boolean) {
    val state = uiState.value
    if (!menuChoicesNeeded(state, linkLive)) return
    session.sendCatalogue(encodeMenuChoices(session.nextCommandId()))
  }

  fun selectTab(tab: AppTab) {
    if (tab != AppTab.Conversation) {
      leaveDictation()
      closeCachedList()
    }
    screenState.value = tab
    if (tab == AppTab.Plan && !uiState.value.disconnected)
      session.sendCatalogue(encodePlanChoices(session.nextCommandId()))
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
    val shown = uiState.value
    // The keyboard can echo the text just sent when the field is cleared under the cursor.
    if (shown.pendingPrompt.isNotEmpty() && shown.draft.isEmpty() && text.trim() == shown.pendingPrompt) {
      dictationState.value = dictationState.value.copy(selectionStart = 0, selectionEnd = 0)
      return
    }
    if (text != shown.draft) updateDraft(text)
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

  fun showCachedList() {
    if (ideLinkLive(uiState.value.disconnected, link.value.phase)) return
    cacheBackToListState.value = false
    viewModelScope.launch(Dispatchers.IO) {
      val record = store.load()
      val key = if (hostIdIsValid(record.hostId)) record.hostId else record.fingerprint
      val rows = try {
        conversationsForHost(conversations.listForHost(key), key)
      } catch (error: Exception) {
        emptyList()
      }
      withContext(Dispatchers.Main) {
        if (ideLinkLive(uiState.value.disconnected, link.value.phase)) return@withContext
        cacheRowsState.value = rows
        cacheListOpenState.value = true
      }
    }
  }

  fun closeCachedList() {
    cacheListOpenState.value = false
  }

  /** Loads one stored conversation onto the page. Does not open a socket. */
  fun openCachedRow(row: ConversationRecord) {
    if (ideLinkLive(uiState.value.disconnected, link.value.phase)) return
    viewModelScope.launch(Dispatchers.IO) {
      val document = try {
        conversations.loadDocument(row.host, row.id)
      } catch (error: Exception) {
        null
      } ?: return@launch
      withContext(Dispatchers.Main) {
        if (ideLinkLive(uiState.value.disconnected, link.value.phase)) return@withContext
        val seeded = reviewedCacheState(uiState.value, document, row, store.load().address.isNotEmpty())
        coordinator.restoreOffline(seeded)
        uiState.value = coordinator.state
        cacheListOpenState.value = false
        cacheBackToListState.value = true
        restoreCachedImages(row.host, row.id, document, uiState.value.hostGeneration)
      }
    }
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
    val record = store.load()
    val fingerprint = record.fingerprint
    val hostId = record.hostId
    synchronized(cacheGate) {
      suppressCache = true
      cacheWriteSerial += 1
    }
    cacheSaveJob?.cancel()
    cacheSaveJob = null
    val effects = coordinator.onEvent(MonitorEvent.ForgetPairing(uiState.value)) ?: emptyList()
    applyUiEffects(effects)
    session.disconnect()
    store.clear()
    try {
      runBlocking(Dispatchers.IO) {
        conversations.forgetHost(fingerprint)
        if (hostIdIsValid(hostId)) conversations.forgetHost(hostId)
      }
    } catch (error: Exception) {
      // Forgetting the local copy must not drop the reset session.
    }
    synchronized(cacheGate) { suppressCache = false }
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
    val effects = coordinator.onEvent(MonitorEvent.NewConversation(uiState.value)) ?: return
    applyUiEffects(effects)
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

  fun selectTarget(path: String) {
    val json = targetSelectionCommand(uiState.value, path, session.nextCommandId()) ?: return
    session.sendCatalogue(json)
  }

  fun selectConversation(id: String) {
    val json = conversationSelectionCommand(uiState.value, id, session.nextCommandId()) ?: return
    session.sendCatalogue(json)
  }

  fun selectModel(id: String) {
    val json = modelSelectionCommand(uiState.value, id, session.nextCommandId()) ?: return
    session.sendCatalogue(json)
  }

  fun selectReasoning(id: String) {
    val json = reasoningSelectionCommand(uiState.value, id, session.nextCommandId()) ?: return
    session.sendCatalogue(json)
  }

  fun selectPermissions(id: String) {
    val json = permissionsSelectionCommand(uiState.value, id, session.nextCommandId()) ?: return
    session.sendCatalogue(json)
  }

  fun openPlan(path: String) {
    val state = uiState.value
    if (state.disconnected || !state.view.canChangeMode || path == state.planPath ||
      state.planChoices.none { it.path == path }) return
    session.sendCatalogue(encodePath(MessageKind.SelectPlan, session.nextCommandId(), path))
  }

  fun selectPlan(index: Int) {
    uiState.update { it.copy(selectedPlan = index) }
  }

  fun runPlan() {
    session.sendCatalogue(encodeEmpty(MessageKind.RunPlan, session.nextCommandId()))
  }

  fun stopPlan() {
    session.sendCatalogue(encodeEmpty(MessageKind.StopPlan, session.nextCommandId()))
  }

  fun newPlan() {
    session.sendCatalogue(encodeNewPlan(session.nextCommandId(), "", false))
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
    saveCacheNow(uiState.value, true)
    supportPending = false
    linkGrace?.cancel()
    finalWatch.cancel()
    engine.destroy()
    session.close()
    database.close()
  }

  private fun scheduleCacheSave() {
    if (suppressCache) return
    cacheSaveJob?.cancel()
    cacheSaveJob = viewModelScope.launch {
      delay(CacheSaveDebounceMs)
      writeCache(uiState.value, false)
    }
  }

  private fun saveCacheNow(ui: MonitorUi, await: Boolean) {
    cacheSaveJob?.cancel()
    cacheSaveJob = null
    writeCache(ui, await)
  }

  private fun writeCache(ui: MonitorUi, await: Boolean) {
    if (suppressCache) return
    val target = cacheSaveTarget(ui) ?: return
    val document = offlineDocument(ui)
    val images = cachedImageBytes(ui)
    val serial = synchronized(cacheGate) { ++cacheWriteSerial }
    val write = Runnable {
      synchronized(cacheGate) {
        if (suppressCache || serial != cacheWriteSerial) return@Runnable
        try {
          val hostId = store.load().hostId
          if (!hostIdIsValid(hostId)) return@Runnable
          runBlocking {
            conversations.saveScreen(hostId, target.conversationId, target.projectRoot, target.title, document, images, System.currentTimeMillis())
          }
        } catch (error: Exception) {
          // A failed local copy must not drop the live session.
        }
      }
    }
    if (await) write.run()
    else viewModelScope.launch(Dispatchers.IO) { write.run() }
  }

  private fun fileClosed(id: String, title: String, projectRoot: String, document: String, epoch: String, cursor: Long) {
    if (id.isEmpty() || id == "current") return
    val hostId = store.load().hostId
    if (!hostIdIsValid(hostId)) return
    val images = cachedImageBytes(uiState.value)
    viewModelScope.launch(Dispatchers.IO) {
      synchronized(cacheGate) {
        if (suppressCache) return@synchronized
        try {
          val decoded = computing.michell.monitor.protocol.decodeClosedScreen(document) ?: return@synchronized
          runBlocking {
            conversations.saveScreen(hostId, id, projectRoot, title, decoded, images, System.currentTimeMillis())
          }
        } catch (error: Exception) {
          // A failed local copy must not drop the live session.
        }
      }
    }
  }

  private fun cachedImageBytes(ui: MonitorUi): List<Pair<String, ByteArray>> {
    val images = ArrayList<Pair<String, ByteArray>>()
    val bitmaps = bitmapsState.value
    for (id in documentImageIds(offlineDocument(ui))) {
      val bitmap = findCachedBitmap(bitmaps, ui.hostGeneration, id) ?: continue
      val stream = ByteArrayOutputStream()
      try {
        if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) continue
      } catch (error: Exception) {
        continue
      }
      val bytes = stream.toByteArray()
      if (bytes.isEmpty()) continue
      images += id to bytes
    }
    return images
  }

  private fun restoreCachedImages(host: String, conversationId: String, document: OfflineCacheDocument, generation: Int) {
    val ids = documentImageIds(document)
    if (ids.isEmpty()) return
    viewModelScope.launch(Dispatchers.IO) {
      val decoded = LinkedHashMap<String, Bitmap>()
      for (id in ids) {
        val file = computing.michell.monitor.data.monitorImageFile(imageRoot, host, conversationId, id)
        val bytes = try {
          if (file == null || !file.isFile) null else file.readBytes()
        } catch (error: Exception) {
          null
        } ?: continue
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: continue
        decoded[imageCacheText(ImageCacheKey(generation, id, 0))] = bitmap
      }
      if (decoded.isEmpty()) return@launch
      withContext(Dispatchers.Main) {
        if (uiState.value.hostGeneration != generation) return@withContext
        bitmapsState.update { current -> current + decoded }
      }
    }
  }

  private suspend fun applyIncoming(message: MonitorMessage) {
    val hello = (message.inbound as? InboundPayload.HelloOk)?.value
    if (hello != null && hostIdIsValid(hello.hostId)) store.saveHostId(hello.hostId)
    val effects = coordinator.onEvent(MonitorEvent.Incoming(uiState.value, message)) ?: return
    execute(effects)
  }

  private fun onLink(status: computing.michell.monitor.connection.LinkStatus) {
    val effects = coordinator.onEvent(MonitorEvent.LinkChanged(uiState.value, status))
    if (effects != null) applyUiEffects(effects)
    if (status.phase == computing.michell.monitor.connection.LinkPhase.Disconnected) saveCacheNow(uiState.value, false)
    if (ideLinkLive(uiState.value.disconnected, status.phase)) {
      cacheListOpenState.value = false
      cacheBackToListState.value = false
    }
    if (effects == null) return
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

  private var ackJob: kotlinx.coroutines.Job? = null

  private fun scheduleAck(effect: MonitorEffect.Ack) {
    ackJob?.cancel()
    ackJob = null
    if (effect.delayMs <= 0L) {
      session.sendCatalogue(effect.json)
      coordinator.noteAckSent(System.currentTimeMillis(), effect.seq)
      return
    }
    ackJob = viewModelScope.launch {
      kotlinx.coroutines.delay(effect.delayMs)
      session.sendCatalogue(effect.json)
      coordinator.noteAckSent(System.currentTimeMillis(), effect.seq)
    }
  }

  private fun applyUiEffects(effects: List<MonitorEffect>) {
    val before = uiState.value
    uiState.value = coordinator.state
    if (cursorCommitted(before, uiState.value) || cacheRowChanged(before, uiState.value)) scheduleCacheSave()
    dropCachedBitmaps(imageCache.retain(uiState.value.hostGeneration, snapshotImageTurns(uiState.value)))
    for (effect in effects) {
      when (effect) {
        is MonitorEffect.DecodeImage -> {}
        MonitorEffect.LeaveDictation -> leaveDictation()
        is MonitorEffect.RememberDraft -> session.updateDraft(effect.text)
        is MonitorEffect.Send -> session.sendCatalogue(effect.json)
        is MonitorEffect.Ack -> scheduleAck(effect)
        MonitorEffect.Prefetch -> applyUiEffects(coordinator.collectMissing(uiState.value))
        MonitorEffect.ClearCaches -> {
          images.reset()
          imageCache.reset()
          bitmapsState.value = emptyMap()
        }
        is MonitorEffect.FileClosed -> fileClosed(effect.id, effect.title, effect.projectRoot, effect.document, effect.epoch, effect.cursor)
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
