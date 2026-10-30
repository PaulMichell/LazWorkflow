package computing.michell.monitor.ui

/* Local phone chrome. Conversation bodies come from the store, not a second
   transcript. Draft, scroll and open sheets stay here. A disconnect is shown
   at once. A prompt is not matched against older blocks.
   (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.CatalogueResult
import computing.michell.monitor.connection.CatalogueWrite
import computing.michell.monitor.connection.HostClosedBanner
import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.connection.LinkStatus
import computing.michell.monitor.connection.NotDeliveredRetry
import computing.michell.monitor.connection.ReconnectingBanner
import computing.michell.monitor.connection.SessionPort
import computing.michell.monitor.protocol.InboundPayload
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.MonitorMessage
import computing.michell.monitor.protocol.WireCatchup
import computing.michell.monitor.protocol.WirePatch
import computing.michell.monitor.protocol.WireSnapshot
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.WireView
import computing.michell.monitor.protocol.applySnapshotPageJson
import computing.michell.monitor.protocol.decodeCatchup
import computing.michell.monitor.protocol.decodeError
import computing.michell.monitor.protocol.decodeHelloOk
import computing.michell.monitor.protocol.decodePatch
import computing.michell.monitor.protocol.decodePlan
import computing.michell.monitor.protocol.decodeSnapshot
import computing.michell.monitor.protocol.decodeStatusPayload
import computing.michell.monitor.protocol.decodeText
import computing.michell.monitor.protocol.snapshotPageOutline
import computing.michell.monitor.protocol.snapshotPageSeq
import computing.michell.monitor.protocol.encodeEmpty
import computing.michell.monitor.protocol.encodeResume
import computing.michell.monitor.protocol.tryEncodeSend
import computing.michell.monitor.protocol.tryEncodeSteer

interface MonitorClock {
  fun nowMs(): Long
}

object SystemMonitorClock : MonitorClock {
  override fun nowMs(): Long = System.currentTimeMillis()
}

interface DisplayPreferences {
  val showThinking: Boolean
  val showTools: Boolean
}

const val CouldNotSendBanner = "Could not send."

sealed class MonitorEvent {
  data class DraftEdited(val current: MonitorUi, val text: String) : MonitorEvent()
  data class Submit(val current: MonitorUi) : MonitorEvent()
  data class NewConversation(val current: MonitorUi) : MonitorEvent()
  data class Incoming(val current: MonitorUi, val message: MonitorMessage) : MonitorEvent()
  data class LinkChanged(val current: MonitorUi, val status: LinkStatus) : MonitorEvent()
  data class CommandResult(val current: MonitorUi, val result: CatalogueResult) : MonitorEvent()
  data class HostChanged(val current: MonitorUi, val address: String, val port: Int, val clientId: String) : MonitorEvent()
  data class ForgetPairing(val current: MonitorUi) : MonitorEvent()
}

sealed class MonitorEffect {
  data class Send(val json: String) : MonitorEffect()
  data class Ack(val json: String, val seq: Long, val delayMs: Long) : MonitorEffect()
  data class RememberDraft(val text: String) : MonitorEffect()
  data object LeaveDictation : MonitorEffect()
  data object Prefetch : MonitorEffect()
  data object ClearCaches : MonitorEffect()
  data class DecodeImage(val message: MonitorMessage) : MonitorEffect()
  data class FileClosed(
    val id: String,
    val title: String,
    val projectRoot: String,
    val document: String,
    val epoch: String = "",
    val cursor: Long = 0
  ) : MonitorEffect()
}

class MonitorCoordinator(
  private val session: SessionPort,
  private val clock: MonitorClock,
  private val display: DisplayPreferences,
  private val content: ConversationStore = MemoryConversationStore()
) {
  private val gate = Any()
  private var local = MonitorUi()
  private var contentHost = ""
  private var submittedText = ""
  private var selectedTurn = -1
  private val visibleTurns = HashSet<Int>()

  val state: MonitorUi
    get() = synchronized(gate) { published() }

  val holdingLink: Boolean get() = false
  val requestedTurnEntries: Set<Int> get() = emptySet()
  val inFlightImageKeys: Set<String> get() = emptySet()
  val loadedImageKeys: Set<String> get() = emptySet()
  val bitmapKeyEntries: Set<String> get() = emptySet()

  /** Shows a Room conversation. A live open is Syncing until the host snapshot arrives. */
  fun showStored(cached: MonitorUi, liveSync: Boolean) = synchronized(gate) {
    local = cached.copy(
      disconnected = !liveSync,
      reachedLive = false,
      catchingUp = liveSync,
      reviewingOffline = !liveSync,
      banner = if (liveSync) "" else OfflineReviewBanner,
      pairHold = false,
      settingsOpen = false,
      approvalOpen = false,
      approval = null,
      planRunning = false,
      statusBusy = false,
      turns = emptyList(),
      live = null,
      history = emptyMap(),
      view = if (liveSync) cached.view else clearRemoteActions(cached.view),
      showThinking = display.showThinking,
      showTools = display.showTools
    )
    content.replace(contentHost, cached.conversationId, cached.turns, cached.live)
  }

  fun restoreOffline(cached: MonitorUi) = synchronized(gate) {
    local = cached.copy(
      disconnected = true,
      reachedLive = false,
      pairHold = false,
      settingsOpen = false,
      approvalOpen = false,
      approval = null,
      planRunning = false,
      turns = emptyList(),
      live = null,
      history = emptyMap(),
      view = clearRemoteActions(cached.view),
      showThinking = display.showThinking,
      showTools = display.showTools
    )
    content.replace(contentHost, cached.conversationId, cached.turns, cached.live)
  }

  fun onEvent(event: MonitorEvent): List<MonitorEffect>? = synchronized(gate) {
    when (event) {
      is MonitorEvent.DraftEdited -> editDraft(event.text)
      is MonitorEvent.Submit -> submit()
      is MonitorEvent.NewConversation -> newConversation()
      is MonitorEvent.Incoming -> incoming(event.message)
      is MonitorEvent.LinkChanged -> linkChanged(event.status)
      is MonitorEvent.CommandResult -> commandResult(event.result)
      is MonitorEvent.HostChanged -> noteHost(event.clientId)
      is MonitorEvent.ForgetPairing -> forgetPairing()
    }
  }

  fun flush(current: MonitorUi): List<MonitorEffect>? = null

  fun noteUndelivered(current: MonitorUi, text: String): MonitorUi = synchronized(gate) {
    local = local.copy(draft = text, undeliveredPrompt = text, banner = NotDeliveredRetry)
    published()
  }

  fun noteDisplay(current: MonitorUi): MonitorUi = synchronized(gate) {
    selectedTurn = current.selectedTurn
    local = local.copy(selectedTurn = current.selectedTurn, showThinking = display.showThinking, showTools = display.showTools)
    published()
  }

  fun noteVisibleTurns(current: MonitorUi, indices: Set<Int>): List<MonitorEffect> = synchronized(gate) {
    visibleTurns.clear()
    visibleTurns.addAll(indices)
    emptyList()
  }

  fun noteImageFetched(imageId: String) {}

  fun noteImagesExpired(imageIds: List<String>) {}

  fun noteBitmap(key: String) {}

  fun collectMissing(current: MonitorUi): List<MonitorEffect> = emptyList()

  fun turnForImage(imageId: String): Int? = null

  fun requestTurnFetch(current: MonitorUi, index: Int): List<MonitorEffect> = emptyList()

  fun revealHeldLink(current: MonitorUi, status: LinkStatus): List<MonitorEffect>? = null

  fun noteAckSent(nowMs: Long, seq: Long) {}

  private fun published(): MonitorUi {
    return local.copy(
      selectedTurn = selectedTurn,
      showThinking = display.showThinking,
      showTools = display.showTools
    ).withBoard(content.current())
  }

  private fun editDraft(text: String): List<MonitorEffect> {
    local = local.copy(draft = text, undeliveredPrompt = "")
    return listOf(MonitorEffect.RememberDraft(text))
  }

  private fun submit(): List<MonitorEffect>? {
    if (local.disconnected) return null
    val text = local.draft.trim()
    if (text.isEmpty()) return null
    val steer = local.view.canSteer
    if (!local.view.canSend && !steer) return null
    val commandId = session.nextCommandId()
    val encoded = if (steer) tryEncodeSteer(commandId, text) else tryEncodeSend(commandId, text)
    if (!encoded.ok) {
      local = local.copy(banner = "Text is longer than 65536 characters.")
      return emptyList()
    }
    submittedText = text
    local = local.copy(draft = "", banner = "", undeliveredPrompt = "")
    return listOf(MonitorEffect.RememberDraft(""), MonitorEffect.LeaveDictation, MonitorEffect.Send(encoded.json))
  }

  private fun newConversation(): List<MonitorEffect> {
    content.replace(contentHost, "", emptyList(), null)
    local = local.copy(conversationId = "", banner = "")
    return listOf(MonitorEffect.Send(encodeEmpty(MessageKind.NewConversation, session.nextCommandId())))
  }

  private fun incoming(message: MonitorMessage): List<MonitorEffect> {
    val effects = mutableListOf<MonitorEffect>()
    when (message.kind) {
      MessageKind.HelloOk -> {
        noteHello(message)
        effects += resumeNow()
      }
      MessageKind.Snapshot -> applySnapshot(decodeSnapshot(message.payloadJson) ?: snapshotFrom(message))
      MessageKind.SnapshotPage -> applySnapshotPage(message)
      MessageKind.Catchup -> decodeCatchup(message.payloadJson)?.let { applyCatchup(it) }
      MessageKind.Patch -> decodePatch(message.payloadJson)?.let { applyPatch(it) }
      MessageKind.Status -> decodeStatusPayload(message.payloadJson)?.let { view ->
        local = local.copy(view = view, statusBusy = view.busy, planRunning = view.planRunning)
      }
      MessageKind.Plan -> applyPlan(message)
      MessageKind.InsertResult -> decodeText(message.payloadJson)?.let { text ->
        if (local.draft.isEmpty()) local = local.copy(draft = text)
      }
      MessageKind.Error -> applyError(message)?.let { effects += it }
      MessageKind.ImageData, MessageKind.ImageUnavailable -> effects += MonitorEffect.DecodeImage(message)
      else -> {}
    }
    return effects
  }

  private fun applySnapshot(snapshot: WireSnapshot?) {
    if (snapshot == null) return
    val live = snapshot.live?.takeIf { turn -> turn.live }
    content.replace(contentHost, local.conversationId, snapshot.storedTurns, live)
    local = local.copy(
      catchingUp = false,
      reviewingOffline = false,
      view = snapshot.view,
      planPath = snapshot.planPath,
      planTitle = snapshot.planTitle,
      planRunning = snapshot.planRunning,
      planRows = snapshot.planRows,
      disconnected = false,
      reachedLive = true,
      banner = if (linkBanner(local.banner)) "" else local.banner
    )
  }

  /** The host no longer sends a snapshot frame. Pages are the conversation. */
  private fun applySnapshotPage(message: MonitorMessage) {
    val seq = snapshotPageSeq(message.payloadJson)
    val outline = snapshotPageOutline(message.payloadJson)
    if (outline != null) {
      val liveId = content.current().live?.id.orEmpty()
      val live = outline.firstOrNull { turn -> liveId.isNotEmpty() && turn.id == liveId }
      val stored = if (live == null) outline else outline.filter { turn -> turn.id != live.id }
      content.replace(contentHost, local.conversationId, stored, live)
      noteCaughtUp(seq)
      return
    }
    val board = content.current()
    val applied = applySnapshotPageJson(board.turns, board.live, message.payloadJson) ?: return
    content.replace(contentHost, local.conversationId, applied.first, applied.second)
    noteCaughtUp(seq)
  }

  private fun applyCatchup(catchup: WireCatchup) {
    if (catchup.mode == "snapshot") {
      applySnapshot(catchup.snapshot)
      return
    }
    if (catchup.mode != "events") return
    for (patch in catchup.patches) applyPatch(patch)
    local = local.copy(
      conversationId = catchup.conversationId.ifEmpty { local.conversationId },
      projectRoot = catchup.projectRoot.ifEmpty { local.projectRoot },
      conversationTitle = catchup.title.ifEmpty { local.conversationTitle }
    )
    noteCaughtUp(catchup.cursor)
    if (catchup.epoch.isNotEmpty()) local = local.copy(hostEpoch = catchup.epoch)
  }

  private fun noteCaughtUp(seq: Long) {
    local = local.copy(
      catchingUp = false,
      reviewingOffline = false,
      disconnected = false,
      reachedLive = true,
      hostCursor = if (seq > 0L) seq else local.hostCursor,
      banner = if (linkBanner(local.banner)) "" else local.banner
    )
  }

  /** Snapshot pages do not carry rows. This frame is the phone's plan. */
  private fun applyPlan(message: MonitorMessage) {
    val plan = (message.inbound as? InboundPayload.Plan)?.value ?: decodePlan(message.payloadJson) ?: return
    val samePath = local.planPath == plan.path
    local = local.copy(
      planPath = plan.path,
      planTitle = plan.title,
      planRunning = plan.running,
      planRows = plan.rows,
      planChoices = plan.choices.orEmpty(),
      selectedPlan = if (samePath) local.selectedPlan else -1,
      view = local.view.copy(planPath = plan.path, planTitle = plan.title, planRunning = plan.running)
    )
  }

  private fun applyPatch(patch: WirePatch) {
    val board = content.current()
    val live = WireTurn(
      patch.turnIndex,
      patch.turnId,
      "",
      "",
      "",
      "",
      live = true,
      blocks = patch.blocks,
      durationMs = patch.elapsedMs
    )
    content.replace(contentHost, local.conversationId, board.turns, live)
    val flagged = local.view.copy(
      busy = patch.busy,
      sending = patch.sending,
      planRunning = patch.planRunning,
      canSend = patch.canSend,
      canSteer = patch.canSteer,
      canStop = patch.canStop,
      elapsedMs = patch.elapsedMs,
      phase = patch.phase
    )
    val view = if (patch.hasView) {
      flagged.copy(model = patch.model, signedIn = patch.signedIn, statusText = patch.statusText)
    } else {
      flagged
    }
    local = local.copy(
      view = view,
      hostEpoch = patch.epoch.ifEmpty { local.hostEpoch },
      hostCursor = patch.cursor,
      planRunning = patch.planRunning
    )
  }

  private fun applyError(message: MonitorMessage): MonitorEffect? {
    val body = (message.inbound as? InboundPayload.Error)?.body ?: decodeError(message.payloadJson) ?: return null
    if (body.messageText == NothingRunningToSteer && local.draft.isNotEmpty()) {
      val encoded = tryEncodeSend(session.nextCommandId(), local.draft.trim())
      if (!encoded.ok) return null
      local = local.copy(banner = "")
      return MonitorEffect.Send(encoded.json)
    }
    local = local.copy(banner = body.messageText)
    return null
  }

  private fun noteHello(message: MonitorMessage) {
    val hello = (message.inbound as? InboundPayload.HelloOk)?.value ?: decodeHelloOk(message.payloadJson) ?: return
    if (hello.hostId.isNotEmpty()) contentHost = hello.hostId
    local = local.copy(
      conversationId = hello.conversationId.ifEmpty { local.conversationId },
      hostEpoch = hello.epoch.ifEmpty { local.hostEpoch },
      hostCursor = if (hello.cursor > 0L) hello.cursor else local.hostCursor,
      projectRoot = hello.projectRoot.ifEmpty { local.projectRoot },
      conversationTitle = hello.title.ifEmpty { local.conversationTitle }
    )
  }

  private fun resumeNow(): MonitorEffect {
    local = local.copy(catchingUp = true)
    return MonitorEffect.Send(encodeResume(session.nextCommandId(), local.hostEpoch, local.hostCursor))
  }

  fun noteSyncTime(updatedAt: Long) = synchronized(gate) {
    if (updatedAt <= 0L || updatedAt == local.lastSyncMs) return
    local = local.copy(lastSyncMs = updatedAt)
  }

  /** The Plan tab highlight. A later plan frame for the same path keeps it. */
  fun noteSelectedPlan(index: Int): MonitorUi = synchronized(gate) {
    local = local.copy(selectedPlan = index)
    published()
  }

  private fun linkChanged(status: LinkStatus): List<MonitorEffect> {
    val replaced = status.lastError == ReplacedReason || status.banner == PairedElsewhereLabel
    if (replaced) {
      local = local.copy(
        pairedElsewhere = true,
        disconnected = true,
        catchingUp = false,
        statusBusy = false,
        banner = PairedElsewhereLabel,
        view = clearRemoteActions(local.view)
      )
      return emptyList()
    }
    val down = status.phase == LinkPhase.Disconnected || status.phase == LinkPhase.Paused
    if (down) {
      local = local.copy(
        pairedElsewhere = false,
        disconnected = true,
        statusBusy = false,
        banner = status.banner.ifEmpty { if (status.phase == LinkPhase.Paused) HostClosedBanner else ReconnectingBanner },
        view = clearRemoteActions(local.view)
      )
      return emptyList()
    }
    if (status.phase == LinkPhase.Live || status.phase == LinkPhase.Idle) {
      local = local.copy(
        pairedElsewhere = false,
        disconnected = false,
        reachedLive = true,
        banner = if (linkBanner(local.banner)) "" else local.banner
      )
    }
    return emptyList()
  }

  private fun commandResult(result: CatalogueResult): List<MonitorEffect> {
    if (result.outcome == CatalogueWrite.Written) {
      submittedText = ""
      return emptyList()
    }
    if (local.draft.isNotEmpty()) return emptyList()
    val text = submittedText.ifEmpty { session.promptDraft }
    if (text.isEmpty()) {
      local = local.copy(banner = CouldNotSendBanner)
      return emptyList()
    }
    local = local.copy(draft = text, banner = CouldNotSendBanner, view = clearRemoteActions(local.view))
    return listOf(MonitorEffect.RememberDraft(text))
  }

  private fun noteHost(clientId: String): List<MonitorEffect> {
    content.clear()
    contentHost = clientId
    val draft = local.draft
    local = MonitorUi(draft = draft, showThinking = display.showThinking, showTools = display.showTools, disconnected = true)
    return listOf(MonitorEffect.ClearCaches)
  }

  private fun forgetPairing(): List<MonitorEffect> {
    content.clear()
    contentHost = ""
    local = MonitorUi(showThinking = display.showThinking, showTools = display.showTools, disconnected = true)
    return listOf(MonitorEffect.ClearCaches, MonitorEffect.RememberDraft(""))
  }

  private fun snapshotFrom(message: MonitorMessage): WireSnapshot? {
    return (message.inbound as? InboundPayload.Snapshot)?.value
  }
}


