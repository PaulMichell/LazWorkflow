package computing.michell.monitor.ui

/* Reduces the monitor catalogue into one screen state (c) 2026 Michell Computing. */

import android.app.Application
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import computing.michell.monitor.connection.HostClosedBanner
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
import computing.michell.monitor.protocol.TaskRow
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
import computing.michell.monitor.protocol.decodeTasks
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
import computing.michell.monitor.protocol.encodeTaskCommand
import computing.michell.monitor.protocol.encodeTurnRequest
import computing.michell.monitor.protocol.encodeWorkOnPlan
import computing.michell.monitor.protocol.tryEncodeSend
import computing.michell.monitor.protocol.tryEncodeSteer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class AppTab {
  Conversation,
  Plan,
  Tasks
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
  val taskRows: List<TaskRow> = emptyList(),
  val approval: ApprovalNotice? = null,
  val approvalOpen: Boolean = false,
  val banner: String = "",
  val draft: String = "",
  val disconnected: Boolean = false,
  val liveRevision: Int = -1,
  val transcriptParts: Map<Int, List<WireBlock>> = emptyMap(),
  val imageReasons: Map<String, String> = emptyMap(),
  val reachedLive: Boolean = false,
  val pairHold: Boolean = false
)

fun emptyView(): WireView {
  return WireView(
    false, false, false, false, false, "", "", "", "", false, "", "", "", "",
    false, false, false, false, false, ""
  )
}

fun TaskRow.isRunnable(): Boolean {
  return enabled && !compileFirst && kind == "prompt"
}

fun TaskRow.desktopOnlyReason(): String {
  if (kind == "format" || compileFirst) return "This task runs on the desktop."
  return ""
}

fun connectionLabel(ui: MonitorUi, phase: LinkPhase): String {
  if (ui.disconnected || phase == LinkPhase.Disconnected || phase == LinkPhase.Paused) return "disconnected"
  if (ui.view.busy || ui.view.sending || ui.view.planRunning || ui.planRunning) return "busy"
  if (ui.reachedLive) return "live"
  return "disconnected"
}

fun actionCaption(view: WireView): String {
  if (view.canSteer) return "Steer"
  return "Send"
}

fun actionEnabled(view: WireView): Boolean {
  return view.canSend || view.canSteer
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
    MessageKind.Tasks -> applyTasks(state, message.payloadJson)
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
  return state.copy(disconnected = true, banner = shown)
}

private fun applySnapshot(state: MonitorUi, payloadJson: String): MonitorUi {
  val snapshot = decodeSnapshot(payloadJson) ?: return state
  val approval = snapshot.approval
  return state.copy(
    view = snapshot.view,
    turns = snapshot.storedTurns,
    live = snapshot.live,
    history = emptyMap(),
    selectedTurn = -1,
    planPath = snapshot.planPath,
    planTitle = snapshot.planTitle,
    planRunning = snapshot.planRunning,
    planRows = snapshot.planRows,
    taskRows = snapshot.taskRows,
    approval = if (approval.active) approval else null,
    approvalOpen = approval.active,
    liveRevision = -1,
    transcriptParts = emptyMap(),
    reachedLive = true,
    pairHold = false,
    disconnected = false,
    banner = ""
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
    previous?.durationMs ?: 0,
    true,
    blocks,
    previous?.images ?: emptyList()
  )
  return state.copy(
    live = live,
    liveRevision = transcript.revision,
    transcriptParts = parts,
    view = state.view.copy(phase = transcript.phase, statusText = transcript.statusText),
    reachedLive = true
  )
}

private fun applyTurnData(state: MonitorUi, payloadJson: String): MonitorUi {
  val turn = decodeTurnData(payloadJson) ?: return state
  return state.copy(history = state.history + (turn.turnIndex to turn), selectedTurn = turn.turnIndex)
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

private fun applyTasks(state: MonitorUi, payloadJson: String): MonitorUi {
  val rows = decodeTasks(payloadJson) ?: return state
  return state.copy(taskRows = rows)
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
  private val bitmapsState = MutableStateFlow<Map<String, Bitmap>>(emptyMap())
  private val uiState: MutableStateFlow<MonitorUi>
  val ui: StateFlow<MonitorUi>
  val bitmaps: StateFlow<Map<String, Bitmap>> = bitmapsState.asStateFlow()
  val link: StateFlow<computing.michell.monitor.connection.LinkStatus> = session.status
  private val screenState = MutableStateFlow(AppTab.Conversation)
  val tab: StateFlow<AppTab> = screenState.asStateFlow()
  val pairAddress = MutableStateFlow("")
  val pairPort = MutableStateFlow(MonitorLimits.ListenPort.toString())
  val pairFingerprint = MutableStateFlow("")
  val pairCode = MutableStateFlow("")

  init {
    val record = store.load()
    pairAddress.value = record.address
    pairPort.value = record.port.toString()
    pairFingerprint.value = record.fingerprint
    uiState = MutableStateFlow(MonitorUi(draft = session.promptDraft))
    ui = uiState.asStateFlow()
    viewModelScope.launch {
      session.messages.collect { message -> onMessage(message) }
    }
    viewModelScope.launch {
      session.status.collect { status -> onLink(status) }
    }
    if (record.paired && record.address.isNotEmpty()) {
      session.connect(record.address, record.port, record.fingerprint, "")
    }
  }

  fun selectTab(tab: AppTab) {
    screenState.value = tab
  }

  fun updateDraft(text: String) {
    session.updateDraft(text)
    uiState.update { it.copy(draft = text) }
  }

  fun connectFromPair() {
    val port = pairPort.value.toIntOrNull() ?: MonitorLimits.ListenPort
    pairPort.value = port.toString()
    uiState.update { it.copy(pairHold = false, banner = "") }
    session.connect(pairAddress.value.trim(), port, pairFingerprint.value.trim(), pairCode.value.trim())
  }

  fun resumeConnect() {
    session.resume()
  }

  fun forgetPairing() {
    session.disconnect()
    store.clear()
    pairCode.value = ""
    uiState.value = MonitorUi()
    bitmapsState.value = emptyMap()
    requested.clear()
  }

  fun sendOrSteer() {
    val view = uiState.value.view
    val text = uiState.value.draft
    val encoded = if (view.canSteer) tryEncodeSteer(session.nextCommandId(), text) else tryEncodeSend(session.nextCommandId(), text)
    if (!encoded.ok) {
      uiState.update { it.copy(banner = "Text is longer than 65536 characters.") }
      return
    }
    session.sendCatalogue(encoded.json)
  }

  fun stop() {
    session.sendCatalogue(encodeEmpty(MessageKind.Stop, session.nextCommandId()))
  }

  fun setMode(mode: String) {
    if (!ModeNames.contains(mode) || !uiState.value.view.canChangeMode) return
    session.sendCatalogue(encodeSetMode(session.nextCommandId(), mode))
  }

  fun selectTurn(index: Int) {
    uiState.update { it.copy(selectedTurn = index) }
    session.sendCatalogue(encodeTurnRequest(session.nextCommandId(), index))
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

  fun runTask(task: TaskRow, note: String) {
    if (!task.isRunnable()) return
    session.sendCatalogue(encodeTaskCommand(MessageKind.RunTask, session.nextCommandId(), task.id, note))
  }

  fun insertTask(task: TaskRow, note: String) {
    if (!task.isRunnable()) return
    session.sendCatalogue(encodeTaskCommand(MessageKind.InsertTask, session.nextCommandId(), task.id, note))
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
    session.close()
  }

  private fun onMessage(message: MonitorMessage) {
    if (message.kind == MessageKind.ImageData) {
      acceptImage(message)
      return
    }
    uiState.update { reduceMonitor(it, message) }
    if (message.kind == MessageKind.InsertResult) session.updateDraft(uiState.value.draft)
    requestImages(displayedTurn())
  }

  private fun onLink(status: computing.michell.monitor.connection.LinkStatus) {
    val pin = status.banner == "TLS pin mismatch."
    val closed = status.phase == LinkPhase.Disconnected || status.phase == LinkPhase.Paused
    uiState.update { current ->
      val next = if (closed && status.banner.isNotEmpty()) noteSocketClosed(current, status.banner) else current
      next.copy(
        pairHold = next.pairHold || pin,
        draft = if (status.draft.isNotEmpty()) status.draft else next.draft
      )
    }
  }

  private fun displayedTurn(): WireTurn? {
    val state = uiState.value
    val selected = state.history[state.selectedTurn]
    return selected ?: state.live
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

  private fun acceptImage(message: MonitorMessage) {
    val decoded = decodeImageData(message.payloadJson) ?: return
    val raw = decodeImageBytes(decoded.image.bytesBase64) ?: return
    val joined = images.accept(decoded.image, raw) ?: return
    val bitmap = BitmapFactory.decodeByteArray(joined, 0, joined.size) ?: return
    bitmapsState.update { it + (decoded.image.imageId to bitmap) }
  }
}
