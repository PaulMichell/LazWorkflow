package computing.michell.monitor.ui

/* Reduces the monitor catalogue into one screen state (c) 2026 Michell Computing. */

import android.Manifest
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.speech.SpeechRecognizer
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import computing.michell.monitor.connection.HostClosedBanner
import computing.michell.monitor.dictation.DictationAudioMessage
import computing.michell.monitor.dictation.DictationBusyMessage
import computing.michell.monitor.dictation.DictationEvent
import computing.michell.monitor.dictation.DictationFailedMessage
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
import computing.michell.monitor.protocol.ApprovalNotice
import computing.michell.monitor.protocol.ImageAssembly
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.ModeNames
import computing.michell.monitor.protocol.MonitorLimits
import computing.michell.monitor.protocol.MonitorMessage
import computing.michell.monitor.protocol.PlanRow

import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.WireView
import computing.michell.monitor.protocol.decodeApprovalRequested
import computing.michell.monitor.protocol.decodeError
import computing.michell.monitor.protocol.decodeImageData
import computing.michell.monitor.protocol.decodeImageUnavailable
import computing.michell.monitor.protocol.decodeMode
import computing.michell.monitor.protocol.decodePlan
import computing.michell.monitor.protocol.decodeRejected
import computing.michell.monitor.protocol.decodeSnapshot
import computing.michell.monitor.protocol.decodeStatusPayload
import computing.michell.monitor.protocol.decodeTarget

import computing.michell.monitor.protocol.decodeText
import computing.michell.monitor.protocol.decodeTranscript
import computing.michell.monitor.protocol.decodeTurnData
import computing.michell.monitor.protocol.decodeImageBytes
import computing.michell.monitor.protocol.encodeApprovalDecision
import computing.michell.monitor.protocol.encodeEmpty
import computing.michell.monitor.protocol.encodeImageGet
import computing.michell.monitor.protocol.encodeNewPlan
import computing.michell.monitor.protocol.encodePath
import computing.michell.monitor.protocol.encodeSetMode

import computing.michell.monitor.protocol.encodeTurnRequest
import computing.michell.monitor.protocol.encodeWorkOnPlan
import computing.michell.monitor.protocol.tryEncodeSend
import computing.michell.monitor.protocol.tryEncodeSteer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
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
  val pendingEpoch: Int = 0,
  val activityStartedMs: Long = 0,
  val activityObservedMs: Int = 0
)

fun emptyView(): WireView {
  return WireView(
    false, false, false, false, false, "", "", "", "", false, "", "", "", "",
    false, false, false, false, false, ""
  )
}

fun connectionLabel(ui: MonitorUi, phase: LinkPhase): String {
  if (phase == LinkPhase.Connecting) return "connecting"
  if (ui.disconnected || phase == LinkPhase.Disconnected || phase == LinkPhase.Paused) return "disconnected"
  if (ui.view.busy || ui.view.sending || ui.view.planRunning || ui.planRunning) return "busy"
  if (ui.reachedLive) return "live"
  return "disconnected"
}

const val ConnectingBanner = "Connecting…"

fun applyLink(state: MonitorUi, phase: LinkPhase, banner: String): MonitorUi {
  val closed = phase == LinkPhase.Disconnected || phase == LinkPhase.Paused
  if (closed && banner.isNotEmpty()) return noteSocketClosed(state, banner)
  if (phase == LinkPhase.Connecting) {
    val shown = if (banner.isEmpty() || banner == ReconnectingBanner) ConnectingBanner else banner
    return state.copy(disconnected = true, banner = shown, pairHold = false)
  }
  if (phase == LinkPhase.Live) {
    val shown = if (state.banner == ReconnectingBanner) "" else state.banner
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

fun idleTurnToShow(state: MonitorUi): Int {
  val slots = virtualSlots(state.turns, state.live, state.view.sending)
  return recentFetches(slots, loadedTurnIndices(state)).lastOrNull() ?: -1
}

const val NothingRunningToSteer = "Nothing is running to steer."

fun clearRemoteActions(view: WireView): WireView {
  return view.copy(busy = false, sending = false, canSend = false, canSteer = false, canStop = false, planRunning = false)
}

fun promptShown(state: MonitorUi, text: String): Boolean {
  val wanted = text.trim()
  if (wanted.isEmpty()) return true
  if (state.live?.prompt?.trim()?.startsWith(wanted) == true) return true
  val turns = listOfNotNull(state.live) + state.history.values
  return turns.any { turn ->
    displayBlocks(turn).any { block ->
      (block.kind == "user" || block.kind == "steer") && block.body.trim().startsWith(wanted)
    }
  }
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

fun beginSubmit(state: MonitorUi, text: String, steer: Boolean, nowMs: Long): MonitorUi {
  val phase = if (steer) "Steering…" else "Waiting for first token…"
  return state.copy(
    draft = "",
    pendingPrompt = text,
    pendingKind = if (steer) "steer" else "user",
    pendingEpoch = state.pendingEpoch + 1,
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
  val draft = if (useReducedDraft) next.draft else current.draft.ifEmpty { next.draft }
  val mergedLive = mergeLiveTurn(current.live, next.live)
  val merged = next.copy(live = mergedLive, history = history)
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
    banner = if (clearDisconnect) "" else if (next.banner.isNotEmpty()) next.banner else current.banner,
    disconnected = if (clearDisconnect) false else current.disconnected,
    history = history,
    live = mergedLive,
    showThinking = current.showThinking,
    showTools = current.showTools,
    pendingPrompt = if (shown) "" else current.pendingPrompt,
    pendingKind = if (shown) "" else current.pendingKind,
    pendingEpoch = maxOf(current.pendingEpoch, next.pendingEpoch),
    activityStartedMs = start,
    activityObservedMs = if (running && observed > 0) observed else if (running) current.activityObservedMs else 0
  )
}

fun reduceMonitor(state: MonitorUi, message: MonitorMessage): MonitorUi {
  if (!message.changesState && message.kind != MessageKind.Error) return state
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
  val generation = if (state.disconnected) state.generation else state.generation + 1
  return state.copy(
    disconnected = true,
    banner = shown,
    generation = generation,
    rescueSteer = false,
    view = clearRemoteActions(state.view)
  )
}

private fun applySnapshot(state: MonitorUi, payloadJson: String): MonitorUi {
  val snapshot = decodeSnapshot(payloadJson) ?: return state
  val approval = snapshot.approval
  val live = mergeLiveTurn(state.live, snapshot.live)
  val sameLive = state.live?.turnIndex == live?.turnIndex
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
    liveRevision = if (sameLive) state.liveRevision else -1,
    transcriptParts = if (sameLive) state.transcriptParts else emptyMap(),
    reachedLive = true,
    pairHold = false,
    disconnected = false,
    banner = "",
    generation = state.generation + 1,
    rescueSteer = false
  )
}

private fun applyTranscript(state: MonitorUi, payloadJson: String): MonitorUi {
  val transcript = decodeTranscript(payloadJson) ?: return state
  if (transcript.revision < state.liveRevision) return state
  if (transcript.revision == state.liveRevision && state.transcriptParts.containsKey(transcript.part)) return state
  val parts = if (transcript.revision > state.liveRevision) {
    mapOf(transcript.part to transcript.blocks)
  } else {
    state.transcriptParts + (transcript.part to transcript.blocks)
  }
  val blocks = parts.toSortedMap().values.flatten()
  val previous = state.live
  val live = WireTurn(
    transcript.turnIndex,
    previous?.id ?: "",
    previous?.mode ?: state.view.mode,
    previous?.createdAt ?: "",
    previous?.promptPreview ?: "",
    previous?.errorText ?: "",
    previous?.prompt ?: "",
    previous?.thinking ?: "",
    previous?.response ?: "",
    if (transcript.durationMs > 0) transcript.durationMs else previous?.durationMs ?: 0,
    true,
    blocks,
    previous?.images ?: emptyList()
  )
  return state.copy(
    live = live,
    liveRevision = transcript.revision,
    transcriptParts = parts,
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
  return state.copy(view = state.view.patchStatus(status))
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
  private val session = LanSession(store)
  private val images = ImageAssembly()
  private val requested = mutableSetOf<String>()
  private val requestedTurns = mutableSetOf<Int>()
  private val displayPrefs = application.getSharedPreferences(DisplayPreferenceFile, Context.MODE_PRIVATE)
  private val applyLock = Mutex()
  private var applied = MonitorUi()
  private var appliedDirty = false
  private val postedGeneration = AtomicInteger(0)
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
  private var recognitionSupported = true
  private var supportPending = false
  // Callbacks splice the prompt only. They must not call sendOrSteer.
  private val engineListener = object : SpeechEngineListener {
    override fun onReady() {
    }

    override fun onBeginningOfSpeech() {
    }

    override fun onEndOfSpeech() {
    }

    override fun onPartial(text: String) {
      onDictationPartial(text)
    }

    override fun onFinal(text: String) {
      onDictationFinal(text)
    }

    override fun onError(code: Int) {
      onDictationError(code)
    }

    override fun onReadyToListen() {
      onSupportReady()
    }

    override fun onLanguageBlocked(language: OnDeviceLanguage) {
      onSupportBlocked(language)
    }

    override fun onSupportFailed(code: Int) {
      onSupportError(code)
    }
  }
  private val engine: SpeechEngine = OnDeviceSpeechEngine(application, engineListener)

  init {
    val record = store.load()
    pairAddress.value = record.address
    pairPort.value = record.port.toString()
    uiState = MutableStateFlow(MonitorUi(
      draft = session.promptDraft,
      showThinking = displayPrefs.getBoolean(DisplayThinkingKey, true),
      showTools = displayPrefs.getBoolean(DisplayToolsKey, true)
    ))
    ui = uiState.asStateFlow()
    viewModelScope.launch(Dispatchers.Default) {
      session.messages.collect { message -> applyIncoming(message) }
    }
    viewModelScope.launch(Dispatchers.Default) {
      while (isActive) {
        delay(ScreenRefreshMs)
        val next = applyLock.withLock {
          if (!appliedDirty) return@withLock null
          appliedDirty = false
          applied
        } ?: continue
        postApplied(next, false, false)
      }
    }
    viewModelScope.launch {
      session.status.collect { status -> onLink(status) }
    }
    // Creation is on the main thread. available() does not create the recognizer.
    if (!engine.available()) {
      dictationState.value = DictationState(statusMessage = DictationUnavailableMessage, available = false)
    }
    if (record.address.isNotEmpty()) {
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
    val step = applyDictation(DictationEvent.ToggleOff(state.sessionId))
    if (step.state.phase == DictationPhase.AwaitingFinal) engine.stopListening()
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
    if (before.phase != DictationPhase.Idle && step.state.phase == DictationPhase.Idle) engine.cancel()
  }

  fun leaveDictation() {
    supportPending = false
    applyDictation(DictationEvent.LeaveScreen)
    callbackSession = 0
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

  fun resumeConnect() {
    session.resume()
  }

  fun forgetPairing() {
    leaveDictation()
    session.disconnect()
    store.clear()
    uiState.value = MonitorUi(showThinking = uiState.value.showThinking, showTools = uiState.value.showTools)
    bitmapsState.value = emptyMap()
    requested.clear()
    requestedTurns.clear()
  }

  fun sendOrSteer() {
    if (dictationState.value.sendMustWait) return
    val state = uiState.value
    if (state.disconnected) return
    val steer = state.view.canSteer
    if (!state.view.canSend && !steer) return
    val text = state.draft.trim()
    if (text.isEmpty()) return
    val encoded = if (steer) tryEncodeSteer(session.nextCommandId(), text) else tryEncodeSend(session.nextCommandId(), text)
    if (!encoded.ok) {
      uiState.update { it.copy(banner = "Text is longer than 65536 characters.") }
      return
    }
    val submitted = beginSubmit(state, text, steer, System.currentTimeMillis())
    session.updateDraft("")
    uiState.value = submitted
    session.sendCatalogue(encoded.json)
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
    uiState.update { it.copy(showThinking = value) }
  }

  fun setShowTools(value: Boolean) {
    displayPrefs.edit().putBoolean(DisplayToolsKey, value).apply()
    uiState.update { it.copy(showTools = value) }
  }

  fun requestTurn(index: Int) {
    if (index < 0) return
    val state = uiState.value
    if (state.history[index]?.let { liveHasContent(it) } == true) return
    if (state.live?.turnIndex == index && liveHasContent(state.live)) return
    if (!requestedTurns.add(index)) return
    session.sendCatalogue(encodeTurnRequest(session.nextCommandId(), index))
  }

  fun selectTurn(index: Int) {
    requestTurn(index)
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
    supportPending = false
    engine.destroy()
    session.close()
  }

  private suspend fun applyIncoming(message: MonitorMessage) {
    if (message.kind == MessageKind.ImageData) {
      val bitmap = decodeBitmap(message) ?: return
      withContext(Dispatchers.Main) {
        bitmapsState.update { it + (bitmap.first to bitmap.second) }
      }
      return
    }
    val immediate = message.kind == MessageKind.Snapshot || message.kind == MessageKind.Rejected ||
      message.kind == MessageKind.Error || message.kind == MessageKind.InsertResult ||
      message.kind == MessageKind.Status
    val next = applyLock.withLock {
      applied = reduceMonitor(applied, message)
      appliedDirty = !immediate
      applied
    }
    if (immediate) {
      postApplied(next, message.kind == MessageKind.InsertResult, message.kind == MessageKind.Snapshot)
      if (next.rescueSteer && next.draft.isNotEmpty()) {
        applyLock.withLock { applied = applied.copy(rescueSteer = false) }
        val encoded = tryEncodeSend(session.nextCommandId(), next.draft)
        if (encoded.ok) session.sendCatalogue(encoded.json)
        else {
          withContext(Dispatchers.Main) {
            uiState.update { it.copy(banner = "Text is longer than 65536 characters.", rescueSteer = false) }
          }
        }
      }
    }
  }

  private suspend fun postApplied(hint: MonitorUi, useReducedDraft: Boolean, clearDisconnect: Boolean) {
    val next = applyLock.withLock {
      if (hint.generation < applied.generation) applied else hint
    }
    if (next.generation < postedGeneration.get()) return
    postedGeneration.set(next.generation)
    withContext(Dispatchers.Main) {
      if (useReducedDraft) {
        leaveDictation()
        session.updateDraft(next.draft)
      }
      uiState.update { current -> mergeApplied(current, next, useReducedDraft, clearDisconnect, System.currentTimeMillis()) }
      if (clearDisconnect) prefetchRecent()
      requestVisibleImages()
    }
  }

  private fun onLink(status: computing.michell.monitor.connection.LinkStatus) {
    if (status.phase == LinkPhase.Disconnected || status.phase == LinkPhase.Paused) leaveDictation()
    val pin = status.banner == "TLS pin mismatch."
    val wasDown = uiState.value.disconnected || uiState.value.banner == ReconnectingBanner
    if (session.promptDraft.isEmpty() && uiState.value.draft.isNotEmpty()) session.updateDraft(uiState.value.draft)
    uiState.update { current ->
      val next = applyLink(current, status.phase, status.banner)
      val shown = next.copy(
        pairHold = next.pairHold || pin,
        draft = session.promptDraft.ifEmpty { current.draft }
      )
      if (shown.generation > postedGeneration.get()) postedGeneration.set(shown.generation)
      shown
    }
    if (status.phase == LinkPhase.Live && wasDown) {
      session.sendCatalogue(encodeEmpty(MessageKind.Refresh, session.nextCommandId()))
    }
  }

  private fun prefetchRecent() {
    val state = uiState.value
    val slots = virtualSlots(state.turns, state.live, state.view.sending)
    val known = slots.map { slot -> slot.turnIndex }.toSet()
    requestedTurns.retainAll(known)
    for (index in recentFetches(slots, loadedTurnIndices(state))) requestTurn(index)
  }

  private fun requestVisibleImages() {
    val state = uiState.value
    requestImages(state.live)
    for (turn in state.history.values) requestImages(turn)
  }

  private fun requestImages(turn: WireTurn?) {
    if (turn == null) return
    val found = turn.blocks.flatMap { it.images } + turn.images
    for (image in found) {
      if (image.id.isEmpty() || image.missing) continue
      val key = turn.turnIndex.toString() + ":" + image.id
      if (!requested.add(key)) continue
      session.sendCatalogue(encodeImageGet(session.nextCommandId(), turn.turnIndex, image.id))
    }
  }

  private fun onDictationPartial(text: String) {
    if (!acceptDictationCallback()) return
    val before = dictationState.value
    releaseIfClosed(before, applyDictation(DictationEvent.Partial(callbackSession, text)))
  }

  private fun onDictationFinal(text: String) {
    if (!acceptDictationCallback()) return
    val before = dictationState.value
    releaseIfClosed(before, applyDictation(DictationEvent.Final(callbackSession, text)))
  }

  private fun onDictationError(code: Int) {
    if (!acceptDictationCallback()) return
    if (code == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED) {
      recognitionSupported = false
      dictationState.value = dictationState.value.copy(available = false)
    }
    val before = dictationState.value
    val step = applyDictation(DictationEvent.Failure(callbackSession, speechFailureMessage(code)))
    callbackSession = 0
    if (code == SpeechRecognizer.ERROR_CLIENT) engine.destroy()
    else releaseIfClosed(before, step)
  }

  private fun onSupportReady() {
    if (!supportPending) return
    supportPending = false
    startListeningSession(pendingSelectionStart, pendingSelectionEnd)
  }

  private fun onSupportBlocked(language: OnDeviceLanguage) {
    if (!supportPending) return
    supportPending = false
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

  private fun onSupportError(code: Int) {
    if (!supportPending) return
    supportPending = false
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

  private fun acceptDictationCallback(): Boolean {
    val state = dictationState.value
    return callbackSession > 0 && state.sessionId == callbackSession && state.phase != DictationPhase.Idle
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
    engine.cancel()
  }

  private fun storeDraft(text: String) {
    session.updateDraft(text)
    uiState.update { it.copy(draft = text) }
  }

  private fun beginDictation(selectionStart: Int, selectionEnd: Int) {
    if (supportPending || dictationState.value.phase != DictationPhase.Idle) return
    permissionRequestState.value = false
    pendingSelectionStart = selectionStart
    pendingSelectionEnd = selectionEnd
    supportPending = true
    if (engine.checkSupport()) return
    supportPending = false
    showSpeechStatus(DictationUnavailableMessage, true)
  }

  private fun startListeningSession(selectionStart: Int, selectionEnd: Int) {
    val step = applyDictation(DictationEvent.Start(selectionStart, selectionEnd))
    if (!step.state.listening) return
    callbackSession = step.state.sessionId
    if (engine.start()) return
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

  private fun decodeBitmap(message: MonitorMessage): Pair<String, Bitmap>? {
    val decoded = decodeImageData(message.payloadJson) ?: return null
    val raw = decodeImageBytes(decoded.image.bytesBase64) ?: return null
    val joined = images.accept(decoded.image, raw) ?: return null
    val bitmap = BitmapFactory.decodeByteArray(joined, 0, joined.size) ?: return null
    return decoded.image.imageId to bitmap
  }
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
