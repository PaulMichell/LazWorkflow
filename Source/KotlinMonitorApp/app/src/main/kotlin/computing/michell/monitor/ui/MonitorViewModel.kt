package computing.michell.monitor.ui

/* Android shell for the monitor catalogue (c) 2026 Michell Computing.

   Size note: exceeds the 1000 line preference. Catalogue events live in
   MonitorCoordinator. Prompt acknowledgement lives in PromptAcknowledgement.
   The final-result deadline lives in DictationFinalWatch. Image request
   and cache policy live in ImageCache. What remains is speech,
   preferences, bitmap decode, and effect execution.
   Offline copies are Room rows. The current plan is a host row, shown
   before the next plan frame. The retired file cache is imported once.
   Reviewed 2026-10-30. */

import android.Manifest
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.speech.SpeechRecognizer
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import computing.michell.monitor.connection.BackgroundBanner
import computing.michell.monitor.connection.ConnectionRefusedBanner
import computing.michell.monitor.data.ConversationRecord
import computing.michell.monitor.data.ConversationRepository
import computing.michell.monitor.data.StoredPlan
import computing.michell.monitor.data.hasStoredPlan
import computing.michell.monitor.data.documentFromRows
import computing.michell.monitor.ui.BoardContent
import computing.michell.monitor.data.RoomCommandLedger
import computing.michell.monitor.data.DefaultConversationCap
import computing.michell.monitor.data.DefaultImageBudgetBytes
import computing.michell.monitor.data.DefaultImageBudgetMiB
import computing.michell.monitor.data.MonitorImageDirectoryName
import computing.michell.monitor.data.RetentionLimits
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
import computing.michell.monitor.connection.WaitingForWifiBanner
import computing.michell.monitor.connection.WifiLanWatch
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
import computing.michell.monitor.protocol.NoSessionMessage
import computing.michell.monitor.protocol.NoSessionReason
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
  val blockFetchIds: List<String> = emptyList(),
  val undeliveredPrompt: String = "",
  val reviewingOffline: Boolean = false,
  val statusBusy: Boolean = false,
  val pairedElsewhere: Boolean = false,
  val lastSyncMs: Long = 0,
  val syncHead: Long = 0,
  val desktopPoint: Int = 0,
  val planBody: String = ""
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

const val StallGapMs = 5_000L

fun linkBanner(banner: String): Boolean {
  return banner == ReconnectingBanner || banner == ConnectingBanner || banner == ConnectionRefusedBanner ||
    banner == HostClosedBanner || banner == OfflineBanner || banner == OfflineReviewBanner || banner == NoAddressBanner ||
    banner == BackgroundBanner || banner == WaitingForWifiBanner
}

/**
 * A sentence for a toast. Empty when the text is already core status.
 * The status bar keeps the connection chip, the model, and progress.
 */
fun statusNotice(banner: String): String {
  val text = banner.trim()
  if (text.isEmpty() || linkBanner(text) || text == PairedElsewhereLabel) return ""
  return when (text) {
    "auth" -> "The desktop did not accept this phone."
    "revoked" -> "This phone was revoked on the desktop."
    "expired" -> "The desktop sign-in expired. Pair again."
    "protocol" -> "The desktop rejected the connection."
    "pair_code" -> "The pair code was not accepted."
    "fingerprint" -> "The desktop certificate did not match."
    "busy" -> "The Project Assistant is busy."
    "disabled" -> "Remote monitor is turned off."
    else -> text
  }
}

/** Left status slot. A notice never replaces Live, Offline, Syncing, or Busy. */
fun statusConnectionLabel(chipLabel: String, banner: String): String {
  if (statusNotice(banner).isNotEmpty()) return chipLabel
  return chipLabel
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
  // A finished turn must not keep Steer just because the last running patch said steering was allowed.
  if (view.canSteer && (view.sending || view.busy)) return "Steer"
  return "Send"
}

/** The footer placeholder is not a model name. An empty field is not one either. */
fun shownModel(model: String): String {
  val id = model.trim()
  if (id.isEmpty() || id == "Model") return ""
  return id
}

/** An empty or placeholder model field must not blank the name already shown. */
internal fun keptModel(previous: String, incoming: String, @Suppress("UNUSED_PARAMETER") incomingSignedIn: Boolean): String {
  val named = shownModel(incoming)
  if (named.isNotEmpty()) return named
  return shownModel(previous)
}

/** A progress caption left on a finished turn. Ready and Offline stay as they are. */
internal fun finishedStatusText(text: String): String {
  val trimmed = text.trim()
  if (trimmed == "Offline" || trimmed == "Not signed in" || trimmed == "Ready" || trimmed.isEmpty()) return trimmed
  if (hostHasElapsed(trimmed) || trimmed.endsWith("…")) return "Ready"
  return trimmed
}

/** A worked footer, or a host that is no longer sending, ends the steer. The next tap is Send. */
internal fun settleFinishedTurn(view: WireView, blocks: List<WireBlock>): WireView {
  val finished = hasWorkedFooter(blocks)
  val hostIdle = !view.sending && !view.busy && !view.planRunning
  if (!finished && !hostIdle) return view
  val settled = view.copy(
    sending = false,
    busy = false,
    canSteer = false,
    canStop = false,
    canSend = !view.planRunning,
    phase = if (view.phase.endsWith("…")) "" else view.phase,
    statusText = finishedStatusText(view.statusText)
  )
  if (settled == view) return view
  return settled
}

/** The host has stopped. A thought left marked running must not stay on screen. */
internal fun closeFinishedRunning(blocks: List<WireBlock>): List<WireBlock> {
  if (blocks.none { block -> block.running }) return blocks
  return blocks.map { block -> if (block.running) block.copy(running = false) else block }
}

fun actionEnabled(view: WireView): Boolean {
  return view.canSend || view.canSteer
}

/** A live idle link can send before the first status frame sets canSend. A running turn still cannot.
    Syncing is not a disconnect: the buttons stay up, and the coordinator holds the command. */
fun sendActionEnabled(
  view: WireView,
  disconnected: Boolean,
  phase: LinkPhase,
  planRunning: Boolean,
  syncing: Boolean = false
): Boolean {
  if (!syncing && (disconnected || phase != LinkPhase.Live)) return false
  if (view.canSteer || view.canSend) return true
  if (view.sending || view.busy || view.planRunning || planRunning) return false
  return true
}

/** New stays available through a short sync. A running turn still cannot start another conversation. */
fun newConversationEnabled(
  view: WireView,
  disconnected: Boolean,
  phase: LinkPhase,
  planRunning: Boolean,
  syncing: Boolean = false
): Boolean {
  if (!syncing && (disconnected || phase != LinkPhase.Live)) return false
  if (view.sending || view.busy || view.planRunning || planRunning || view.canSteer) return false
  return true
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

/** A live idle host. Offline and a missing sign-in flag are not a second status. */
fun idleActivity(statusText: String): String {
  val text = statusText.trim()
  if (text.isEmpty() || text == "Ready" || text == "Offline" || text == "Not signed in" || hostHasElapsed(text)) return "Ready"
  return text
}

fun runtimeCaption(view: WireView): String = runtimeCaption(view.model)

fun runtimeCaption(model: String, choices: List<ModelChoice> = emptyList()): String {
  val id = shownModel(model)
  if (id.isEmpty()) return ""
  val caption = choices.firstOrNull { choice -> choice.id == id }?.caption?.trim().orEmpty()
  return caption.ifEmpty { id }
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

fun turnStillRunning(view: WireView, pending: Boolean, blocks: List<WireBlock>, @Suppress("UNUSED_PARAMETER") live: WireTurn? = null): Boolean {
  if (hasWorkedFooter(blocks)) return false
  if (pending || view.sending || view.busy || view.planRunning) return true
  // The host has stopped. A thought left marked running must not keep Thinking… on a finished turn.
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
  val running = ui.view.sending || ui.view.busy || ui.view.planRunning
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
  // The left label owns the link. A live idle host is Ready. Offline is not repeated on the right.
  if (!linkLive) return ""
  if (!turnStillRunning(view, pending, blocks, live)) return idleActivity(view.statusText)
  val phase = activityPhase(view, pending, pendingKind, blocks)
  // A missing start must not be replaced with now. That freezes the caption at 0:00.
  val elapsed = observedElapsedMs(view, live, blocks).toLong()
  val start = when {
    startedMs > 0L -> startedMs
    elapsed > 0L && nowMs > elapsed -> nowMs - elapsed
    else -> 0L
  }
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
  val pendingLeft = current.pendingPrompt.isNotEmpty()
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
    pendingPrompt = current.pendingPrompt,
    pendingKind = current.pendingKind,
    pendingEpoch = maxOf(current.pendingEpoch, next.pendingEpoch),
    promptBaseline = baseline,
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
    flagged.copy(
      model = keptModel(state.view.model, patch.model, patch.signedIn),
      signedIn = patch.signedIn,
      statusText = patch.statusText
    )
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
    is InboundPayload.Plan -> applyPlanMessage(state, inbound.value)
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
    return overlaySnapshot(
      cleared.copy(view = cleared.view.copy(model = shownModel(state.view.model))),
      snapshot,
      state.generation + 1
    )
  }
  val previousId = state.live?.id ?: ""
  val acceptedNew = state.hostEpoch.isEmpty() && previousId.isNotEmpty() && previousId != incoming.id
  val conversationGeneration = if (acceptedNew) state.conversationGeneration + 1 else state.conversationGeneration
  val live = mergeLiveTurn(state.live, incoming, !acceptedNew)
  val sameTurn = previousId.isNotEmpty() && previousId == incoming.id &&
    state.transcriptConnection == state.connectionGeneration
  val approval = snapshot.approval
  return state.copy(
    view = snapshot.view.copy(model = keptModel(state.view.model, snapshot.view.model, snapshot.view.signedIn)),
    turns = snapshot.storedTurns,
    live = live,
    history = retainLoaded(state.history, snapshot.storedTurns),
    planPath = snapshot.planPath,
    planTitle = snapshot.planTitle,
    planRunning = snapshot.planRunning,
    planRows = snapshot.planRows,
    planBody = keptPlanBody(state.planPath, state.planBody, snapshot.planPath, ""),
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
    view = snapshot.view.copy(model = keptModel(cleared.view.model, snapshot.view.model, snapshot.view.signedIn)),
    turns = snapshot.storedTurns,
    live = null,
    history = emptyMap(),
    planPath = snapshot.planPath,
    planTitle = snapshot.planTitle,
    planRunning = snapshot.planRunning,
    planRows = snapshot.planRows,
    planBody = keptPlanBody(cleared.planPath, cleared.planBody, snapshot.planPath, ""),
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
    planBody = if (sameFolder) state.planBody else "",
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

/** The list and the current id. An empty current must not blank a model the status bar already shows. */
internal fun applyModelsFrame(state: MonitorUi, models: ModelsMessage): MonitorUi {
  val named = if (models.current.isNotEmpty()) models.current else state.view.model
  return state.copy(
    modelChoices = models.choices,
    modelBackend = models.backend,
    modelNote = models.note,
    view = state.view.copy(model = named)
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

/**
 * A later frame without a document keeps the text already shown for that path.
 * A complete frame replaces it, including when the desktop file is now empty.
 */
internal fun keptPlanBody(
  previousPath: String,
  previousBody: String,
  nextPath: String,
  nextBody: String,
  nextComplete: Boolean = false
): String {
  if (nextComplete) return nextBody
  if (nextBody.isNotEmpty()) return nextBody
  if (nextPath.isNotEmpty() && nextPath == previousPath) return previousBody
  return ""
}

internal fun applyPlanMessage(state: MonitorUi, plan: computing.michell.monitor.protocol.PlanMessage): MonitorUi {
  val samePath = state.planPath == plan.path
  return state.copy(
    planPath = plan.path,
    planTitle = plan.title,
    planRunning = plan.running,
    planRows = plan.rows,
    planChoices = plan.choices.orEmpty(),
    planBody = keptPlanBody(state.planPath, state.planBody, plan.path, plan.body, plan.complete),
    selectedPlan = if (samePath) state.selectedPlan else -1,
    view = state.view.copy(planPath = plan.path, planTitle = plan.title, planRunning = plan.running)
  )
}

private fun applyPlan(state: MonitorUi, payloadJson: String): MonitorUi {
  val plan = decodePlan(payloadJson) ?: return state
  return applyPlanMessage(state, plan)
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
  // The window was not ready. Keep the cached turns; the bar must not sit on Syncing.
  if (error.reason == NoSessionReason || error.messageText == NoSessionMessage) {
    return state.copy(banner = error.messageText, catchingUp = false)
  }
  return state.copy(banner = error.messageText)
}

private fun applyImageUnavailable(state: MonitorUi, payloadJson: String): MonitorUi {
  val image = decodeImageUnavailable(payloadJson) ?: return state
  return state.copy(imageReasons = state.imageReasons + (image.imageId to image.reason))
}

internal fun WireView.patchStatus(status: WireView): WireView {
  return copy(
    available = status.available,
    busy = status.busy,
    sending = status.sending,
    modeLocked = status.modeLocked,
    planRunning = status.planRunning,
    phase = status.phase,
    statusText = status.statusText,
    model = keptModel(model, status.model, status.signedIn),
    backend = status.backend,
    signedIn = status.signedIn,
    approvalCaption = status.approvalCaption,
    effort = status.effort,
    skill = status.skill,
    contextText = status.contextText,
    usageCaption = status.usageCaption,
    usageHint = status.usageHint,
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
  private val displayPrefs = application.getSharedPreferences(DisplayPreferenceFile, Context.MODE_PRIVATE)
  private val conversations = ConversationRepository(database, imageRoot, ::retentionLimits)
  private val commandLedger = RoomCommandLedger(conversations)
  val conversationCapText = MutableStateFlow(displayPrefs.getInt(ConversationCapKey, DefaultConversationCap).toString())
  val imageBudgetText = MutableStateFlow(displayPrefs.getInt(ImageBudgetKey, DefaultImageBudgetMiB).toString())
  private val session = LanSession(store, ledger = commandLedger)
  private val lanWatch = WifiLanWatch(application, session::onWifiAvailable, session::onWifiLost)
  private val cacheGate = Any()
  private var cacheWriteSerial = 0
  private var cacheSaveJob: Job? = null
  private var suppressCache = false
  private val images = ImageAssembly()
  private val display = object : DisplayPreferences {
    override val showThinking: Boolean get() = displayPrefs.getBoolean(DisplayThinkingKey, true)
    override val showTools: Boolean get() = displayPrefs.getBoolean(DisplayToolsKey, true)
  }
  private val content = MemoryConversationStore()
  private val coordinator = MonitorCoordinator(session, SystemMonitorClock, display, content)
  private var askedStatusModel = false
  private var rememberedModel = ""
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
  private var contentWatch: Job? = null
  private var savedBoardRevision = 0L
  private var watchedHost = ""
  private var watchedConversation = ""
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
    // 1. The shell is on screen before Room or the socket. The last model is already on the bar.
    rememberedModel = shownModel(displayPrefs.getString(LastModelKey, "").orEmpty())
    coordinator.seedModel(rememberedModel)
    uiState = MutableStateFlow(coordinator.state)
    ui = uiState.asStateFlow()
    viewModelScope.launch(Dispatchers.Default) {
      session.messages.collect { message ->
        try {
          applyIncoming(message)
        } catch (error: Exception) {
          // A bad frame must not kill the process. The next resume can ask again.
        }
      }
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
    viewModelScope.launch {
      content.updates.collect { board ->
        uiState.value = coordinator.state
        val hostId = store.load().hostId
        val conversationId = board.conversationId.ifEmpty { coordinator.state.conversationId }
        watchRepository(hostId, conversationId)
        if (board.revision > savedBoardRevision && hostIdIsValid(hostId) && conversationId.isNotEmpty()) {
          savedBoardRevision = board.revision
          persistBoard(hostId, conversationId, board)
        }
      }
    }
    viewModelScope.launch {
      conversations.outbox().collect { commandLedger.replace(it) }
    }
    viewModelScope.launch {
      session.undeliveredPrompt.collect { text ->
        if (text.isEmpty()) {
          uiState.update { it.copy(undeliveredPrompt = "") }
          return@collect
        }
        val shown = coordinator.noteUndelivered(uiState.value, text)
        withContext(Dispatchers.Main) { uiState.value = shown }
      }
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
    // 2. Cached conversation and plan. 3. Only then reconnect.
    viewModelScope.launch {
      showCachedThenConnect(record)
    }
  }

  private suspend fun showCachedThenConnect(record: computing.michell.monitor.connection.HostRecord) {
    val restored = try {
      withContext(Dispatchers.IO) {
        importLegacyCache(imageRoot.parentFile ?: imageRoot, conversations, imageRoot)
        conversations.retain()
        val key = if (hostIdIsValid(record.hostId)) record.hostId else record.fingerprint
        val open = newestConversation(conversations.listForHost(key), key)
        val document = if (open == null) null else conversations.loadDocument(open.host, open.id)
        RestoredScreen(open, document, conversations.loadPlan(key))
      }
    } catch (error: Exception) {
      null
    }
    val open = restored?.row
    val cached = restored?.document
    val cachedPlan = restored?.plan
    withContext(Dispatchers.Main) {
      if (cached != null || record.address.isEmpty()) {
        val seeded = if (cached != null) {
          applyOfflineCache(coordinator.state, cached, record.address.isNotEmpty()).copy(
            conversationId = open?.id.orEmpty(),
            hostEpoch = open?.streamId.orEmpty(),
            hostCursor = open?.seq ?: 0L,
            projectRoot = open?.projectRoot ?: coordinator.state.projectRoot,
            conversationTitle = open?.title ?: coordinator.state.conversationTitle,
            lastSyncMs = open?.updatedAt ?: 0L
          )
        } else coordinator.state.copy(disconnected = true, banner = NoAddressBanner, reachedLive = false)
        coordinator.restoreOffline(seeded)
      }
      if (cachedPlan != null) coordinator.noteCachedPlan(
        cachedPlan.path, cachedPlan.title, cachedPlan.rows, cachedPlan.selected, cachedPlan.body
      )
      uiState.value = coordinator.state
      if (open != null && cached != null) restoreCachedImages(open.host, open.id, cached, uiState.value.hostGeneration)
    }
    if (record.address.isEmpty()) return
    try {
      withContext(Dispatchers.IO) {
        commandLedger.refresh()
        commandLedger.dropOpenPrompts()
      }
    } catch (error: Exception) {
      // A damaged outbox must not stop the app opening.
    }
    withContext(Dispatchers.Main) {
      lanWatch.start()
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
    // The cached plan is already on screen. This only asks for a newer copy.
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

  fun enterForeground() {
    // A reconnect resumes from hello. A screen that stayed connected still needs the head and the plan.
    if (!session.enterForeground()) session.requestLiveSync()
  }

  fun leaveForeground() {
    session.leaveForeground()
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
    uiState.update { it.copy(pairHold = false, disconnected = true, banner = ConnectingBanner) }
    session.connect(address, port)
  }

  fun showCachedList() {
    leaveDictation()
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
        cacheRowsState.value = rows
        cacheListOpenState.value = true
      }
    }
  }

  fun closeCachedList() {
    cacheListOpenState.value = false
  }

  /** Offline opens Room only. A live link selects the conversation and waits for the host. */
  fun openCachedRow(row: ConversationRecord) {
    val live = ideLinkLive(uiState.value.disconnected, link.value.phase)
    viewModelScope.launch(Dispatchers.IO) {
      val document = try {
        conversations.loadDocument(row.host, row.id)
      } catch (error: Exception) {
        null
      } ?: return@launch
      withContext(Dispatchers.Main) {
        val seeded = if (live) syncingCacheState(uiState.value, document, row)
          else reviewedCacheState(uiState.value, document, row, store.load().address.isNotEmpty())
        coordinator.setSettingsOpen(false)
        coordinator.showStored(seeded, live)
        uiState.value = coordinator.state
        cacheListOpenState.value = false
        cacheBackToListState.value = !live
        restoreCachedImages(row.host, row.id, document, uiState.value.hostGeneration)
        if (live) session.sendCatalogue(encodeSelectConversation(session.nextCommandId(), row.id))
      }
    }
  }

  fun pinCached(row: ConversationRecord) {
    viewModelScope.launch(Dispatchers.IO) {
      conversations.setPinned(row.host, row.id, !row.pinned, row.updatedAt)
      refreshCachedRows()
    }
  }

  fun deleteCached(row: ConversationRecord) {
    viewModelScope.launch(Dispatchers.IO) {
      conversations.deleteConversation(row.host, row.id)
      withContext(Dispatchers.Main) {
        if (uiState.value.conversationId == row.id) {
          coordinator.showStored(uiState.value.copy(turns = emptyList(), live = null, conversationId = ""), false)
          uiState.value = coordinator.state
        }
        refreshCachedRows()
      }
    }
  }

  private suspend fun refreshCachedRows() {
    val record = store.load()
    val key = if (hostIdIsValid(record.hostId)) record.hostId else record.fingerprint
    val rows = try {
      conversationsForHost(conversations.listForHost(key), key)
    } catch (error: Exception) {
      emptyList()
    }
    withContext(Dispatchers.Main) { cacheRowsState.value = rows }
  }

  fun showSettings() {
    coordinator.setSettingsOpen(true)
    leaveDictation()
    uiState.value = coordinator.state
  }

  fun closeSettings() {
    coordinator.setSettingsOpen(false)
    uiState.value = coordinator.state
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

  fun retryUndelivered() {
    session.retryUndelivered()
  }

  fun sendOrSteer() {
    if (dictationState.value.sendMustWait) return
    session.clearUndelivered()
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

  fun setConversationCapText(text: String) {
    val digits = text.filter { character -> character.isDigit() }.take(4)
    conversationCapText.value = digits
    val value = digits.toIntOrNull() ?: return
    if (value < 1) return
    displayPrefs.edit().putInt(ConversationCapKey, value).apply()
    viewModelScope.launch(Dispatchers.IO) { conversations.retain() }
  }

  fun setImageBudgetText(text: String) {
    val digits = text.filter { character -> character.isDigit() }.take(4)
    imageBudgetText.value = digits
    val value = digits.toIntOrNull() ?: return
    if (value < 1) return
    displayPrefs.edit().putInt(ImageBudgetKey, value).apply()
    viewModelScope.launch(Dispatchers.IO) { conversations.retain() }
  }

  private fun persistBoard(hostId: String, conversationId: String, board: BoardContent) {
    val chrome = coordinator.state
    val document = computing.michell.monitor.protocol.OfflineCacheDocument(
      board.turns,
      board.turns,
      board.live,
      chrome.planPath,
      chrome.planTitle,
      chrome.planRows,
      chrome.selectedPlan,
      ""
    )
    viewModelScope.launch(Dispatchers.IO) {
      conversations.saveScreen(hostId, conversationId, chrome.projectRoot, chrome.conversationTitle, document, emptyList(), System.currentTimeMillis())
    }
  }

  private fun watchRepository(hostId: String, conversationId: String) {
    if (!hostIdIsValid(hostId) || conversationId.isEmpty() || !coordinator.acceptsRepository(conversationId)) {
      contentWatch?.cancel()
      contentWatch = null
      watchedHost = ""
      watchedConversation = ""
      return
    }
    if (hostId == watchedHost && conversationId == watchedConversation) return
    watchedHost = hostId
    watchedConversation = conversationId
    contentWatch?.cancel()
    contentWatch = viewModelScope.launch {
      kotlinx.coroutines.flow.combine(
        conversations.turns(hostId, conversationId),
        conversations.blocks(hostId, conversationId),
        conversations.conversation(hostId, conversationId)
      ) { turns, blocks, row -> documentFromRows(turns, blocks) to (row?.updatedAt ?: 0L) }
        .collect { (document, updatedAt) ->
          if (!coordinator.acceptsRepository(conversationId)) return@collect
          coordinator.noteSyncTime(updatedAt)
          content.adopt(hostId, conversationId, document.turns, document.live)
          uiState.value = coordinator.state
        }
    }
  }

  private fun attachApplier(hostId: String) {
    if (!hostIdIsValid(hostId)) return
    val current = syncApplier
    if (current != null) return
    val created = computing.michell.monitor.data.SyncApplier(hostId, computing.michell.monitor.data.RoomSyncStore(database), { System.currentTimeMillis() })
    syncApplier = created
    session.attachApplier(created)
    created.start(viewModelScope)
  }

  private var syncApplier: computing.michell.monitor.data.SyncApplier? = null

  private fun retentionLimits(): RetentionLimits {
    val cap = displayPrefs.getInt(ConversationCapKey, DefaultConversationCap)
    val mebibytes = displayPrefs.getInt(ImageBudgetKey, DefaultImageBudgetMiB)
    val budget = if (mebibytes < 1) DefaultImageBudgetBytes else mebibytes.toLong() * 1024L * 1024L
    return RetentionLimits(if (cap < 1) DefaultConversationCap else cap, budget)
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

  fun selectPlanPath(path: String) {
    val state = uiState.value
    if (state.disconnected || !state.view.canChangeMode || path == state.planPath ||
      state.planChoices.none { it.path == path }) return
    session.sendCatalogue(encodePath(MessageKind.SelectPlan, session.nextCommandId(), path))
  }

  fun selectPlan(index: Int) {
    uiState.value = coordinator.noteSelectedPlan(index)
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

  fun closePlan() {
    session.sendCatalogue(encodeEmpty(MessageKind.ClosePlan, session.nextCommandId()))
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
    lanWatch.stop()
    saveCacheNow(uiState.value, true)
    if (hasStoredPlan(uiState.value.planPath, uiState.value.planTitle, uiState.value.planRows))
      rememberPlan(uiState.value, uiState.value, true)
    supportPending = false
    contentWatch?.cancel()
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

  private fun rememberPlan(before: MonitorUi, after: MonitorUi, await: Boolean) {
    val afterHas = hasStoredPlan(after.planPath, after.planTitle, after.planRows)
    val beforeHas = hasStoredPlan(before.planPath, before.planTitle, before.planRows)
    // A status tick on an empty plan must not delete a cache this start failed to read.
    if (!afterHas && !beforeHas) return
    if (suppressCache) return
    val hostId = store.load().hostId
    if (!hostIdIsValid(hostId)) return
    val write = Runnable {
      synchronized(cacheGate) {
        if (suppressCache) return@Runnable
        try {
          runBlocking {
            if (afterHas) {
              conversations.savePlan(
                hostId, after.planPath, after.planTitle, after.planRows, after.selectedPlan, after.planBody,
                System.currentTimeMillis()
              )
            } else {
              conversations.deletePlan(hostId)
            }
          }
        } catch (error: Exception) {
          // A failed local copy must not drop the live session.
        }
      }
    }
    if (await) write.run()
    else viewModelScope.launch(Dispatchers.IO) { write.run() }
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
        val bitmap = decodeBounded(bytes) ?: continue
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
    if (hello != null && hostIdIsValid(hello.hostId)) {
      store.saveHostId(hello.hostId)
      attachApplier(hello.hostId)
    }
    val effects = coordinator.onEvent(MonitorEvent.Incoming(uiState.value, message)) ?: return
    execute(effects)
  }

  /** The next open paints this name before the desktop frame arrives. */
  private fun rememberShownModel(model: String) {
    val named = shownModel(model)
    if (named.isEmpty() || named == rememberedModel) return
    rememberedModel = named
    displayPrefs.edit().putString(LastModelKey, named).apply()
  }

  private fun onLink(status: computing.michell.monitor.connection.LinkStatus) {
    val effects = coordinator.onEvent(MonitorEvent.LinkChanged(uiState.value, status))
    if (effects != null) applyUiEffects(effects)
    if (status.phase == computing.michell.monitor.connection.LinkPhase.Disconnected) {
      saveCacheNow(uiState.value, false)
      askedStatusModel = false
    }
    if (ideLinkLive(uiState.value.disconnected, status.phase)) {
      cacheListOpenState.value = false
      cacheBackToListState.value = false
      if (!askedStatusModel && statusModelNeeded(uiState.value, true)) {
        askedStatusModel = true
        session.sendCatalogue(encodeMenuChoices(session.nextCommandId()))
      }
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
    // An empty effect list is a plan or status frame. Leaving it unpublished is why
    // the Plan page stayed stale until Conversation was opened and closed.
    val copyState = incomingCopiesScreen(effects)
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

  private fun planChromeChanged(before: MonitorUi, after: MonitorUi): Boolean {
    return before.planPath != after.planPath || before.planTitle != after.planTitle ||
      before.planRunning != after.planRunning || before.planRows != after.planRows ||
      before.planChoices != after.planChoices || before.planBody != after.planBody
  }

  private fun applyUiEffects(effects: List<MonitorEffect>) {
    val before = uiState.value
    // File the open screen before the coordinator's clear replaces it.
    for (effect in effects) {
      if (effect is MonitorEffect.FileClosed) {
        fileClosed(effect.id, effect.title, effect.projectRoot, effect.document, effect.epoch, effect.cursor)
      }
    }
    uiState.value = coordinator.state
    rememberShownModel(uiState.value.view.model)
    if (planChromeChanged(before, uiState.value)) rememberPlan(before, uiState.value, false)
    if (cursorCommitted(before, uiState.value) || cacheRowChanged(before, uiState.value) ||
      planChromeChanged(before, uiState.value)) scheduleCacheSave()
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
        is MonitorEffect.FileClosed -> {}
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
    val bitmap = decodeBounded(joined) ?: return null
    val turnIndex = coordinator.turnForImage(part.image.imageId) ?: uiState.value.live?.turnIndex ?: -1
    return DecodedImage(uiState.value.hostGeneration, part.image.imageId, part.image.revision, turnIndex, bitmap)
  }

  private fun decodeBounded(bytes: ByteArray): Bitmap? {
    val bounds = BitmapFactory.Options()
    bounds.inJustDecodeBounds = true
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
    val plan = bitmapBoundsPlan(bounds.outWidth, bounds.outHeight, viewWidthPx)
    if (!plan.allocate) return null
    val pixels = BitmapFactory.Options()
    pixels.inSampleSize = plan.sampleSize
    pixels.inPreferredConfig = Bitmap.Config.ARGB_8888
    return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, pixels)
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

private data class RestoredScreen(
  val row: ConversationRecord?,
  val document: computing.michell.monitor.protocol.OfflineCacheDocument?,
  val plan: StoredPlan?
)

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
private const val ConversationCapKey = "conversation-cap"
private const val ImageBudgetKey = "image-budget-mib"
private const val DictationPermissionAskedKey = "dictation-asked"
private const val LastModelKey = "last-model"
