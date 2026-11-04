package computing.michell.monitor.ui

/* Local phone chrome. Conversation bodies come from the store, not a second
   transcript. Draft, scroll and open sheets stay here. A disconnect is shown
   at once. A prompt is not matched against older blocks.
   (c) 2026 Michell Computing. */

import computing.michell.monitor.data.StoredPlan
import computing.michell.monitor.connection.CatalogueResult
import computing.michell.monitor.connection.CatalogueWrite
import computing.michell.monitor.connection.HostClosedBanner
import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.connection.LinkStatus
import computing.michell.monitor.connection.ReconnectingBanner
import computing.michell.monitor.connection.SessionPort
import computing.michell.monitor.protocol.InboundPayload
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.MonitorMessage
import computing.michell.monitor.protocol.PlanRow
import computing.michell.monitor.protocol.WireConversationClosed
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.WireView
import computing.michell.monitor.protocol.conversationIdIsIdentity
import computing.michell.monitor.protocol.decodeConversationClosed
import computing.michell.monitor.protocol.NoSessionMessage
import computing.michell.monitor.protocol.NoSessionReason
import computing.michell.monitor.protocol.decodeError
import computing.michell.monitor.protocol.decodeHelloOk
import computing.michell.monitor.protocol.decodeModels
import computing.michell.monitor.protocol.decodePlan
import computing.michell.monitor.protocol.decodeStatusPayload
import computing.michell.monitor.protocol.decodeText
import computing.michell.monitor.protocol.encodeClosedScreen
import computing.michell.monitor.protocol.encodeEmpty
import computing.michell.monitor.protocol.encodeResume
import computing.michell.monitor.protocol.encodeSyncResume
import computing.michell.monitor.protocol.encodeTurnRequest
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

/** A plan or status frame has no effect. The screen still has to show it.
    Image-only effects stay off this path; those bitmaps are stored separately. */
fun incomingCopiesScreen(effects: List<MonitorEffect>): Boolean {
  if (effects.isEmpty()) return true
  return effects.any { effect -> effect !is MonitorEffect.DecodeImage }
}

class MonitorCoordinator(
  private val session: SessionPort,
  private val clock: MonitorClock,
  private val display: DisplayPreferences,
  private val content: ConversationStore = MemoryConversationStore()
) {
  private val gate = Any()
  private var local = MonitorUi()
  /** User sheet. Incoming frames must not clear it. */
  private var settingsHeld = false
  private var contentHost = ""
  private var submittedText = ""
  private var submittedId = ""
  private var selectedTurn = -1
  private var awaitingConversation = false
  /** Pages for this id arrived after New. They are the conversation that was just left. */
  private var closedAwaitId = ""
  private val visibleTurns = HashSet<Int>()
  private var resumeConversation = ""
  private var resumeStream = ""
  private var resumeSeq = 0L
  /** Last time an empty screen asked the desktop for the open turn. */
  private var screenAskedAt = 0L
  /** Live until the first status, so an idle form can send before that frame. */
  private var linkPhase = LinkPhase.Live
  /** Send or New tapped while Syncing, before the socket can take it. */
  private val held = ArrayList<HeldCommand>()

  val state: MonitorUi
    get() = synchronized(gate) { published() }

  /** The last name the phone showed. A later frame with a real id replaces it. */
  fun seedModel(model: String) = synchronized(gate) {
    val named = shownModel(model)
    if (named.isEmpty() || shownModel(local.view.model).isNotEmpty()) return
    local = local.copy(view = local.view.copy(model = named))
  }

  val holdingLink: Boolean get() = false
  val requestedTurnEntries: Set<Int> get() = emptySet()
  val inFlightImageKeys: Set<String> get() = emptySet()
  val loadedImageKeys: Set<String> get() = emptySet()
  val bitmapKeyEntries: Set<String> get() = emptySet()

  /** Shows a Room conversation. A live open is Syncing until the host snapshot arrives.
      The current plan stays. A stored conversation does not carry that host row. */
  fun showStored(cached: MonitorUi, liveSync: Boolean) = synchronized(gate) {
    val typed = unsentPrompt()
    if (held.isNotEmpty()) {
      submittedText = ""
      submittedId = ""
    }
    held.clear()
    val kept = keepShownPlan(cached, local)
    local = kept.copy(
      draft = kept.draft.ifEmpty { typed },
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
      view = if (liveSync) kept.view else clearRemoteActions(kept.view),
      showThinking = display.showThinking,
      showTools = display.showTools
    )
    content.replace(contentHost, kept.conversationId, kept.turns, kept.live)
  }

  /** Puts the cached plan on an empty plan tab. Does not wait for the host. */
  fun noteCachedPlan(path: String, title: String, rows: List<PlanRow>, selected: Int, body: String = "") =
    synchronized(gate) {
      local = withCachedPlan(local, StoredPlan(path, title, rows, selected, body))
    }

  fun restoreOffline(cached: MonitorUi) = synchronized(gate) {
    val typed = unsentPrompt()
    if (held.isNotEmpty()) {
      submittedText = ""
      submittedId = ""
    }
    held.clear()
    val kept = keepShownPlan(cached, local)
    local = kept.copy(
      draft = kept.draft.ifEmpty { typed },
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
      view = clearRemoteActions(kept.view),
      showThinking = display.showThinking,
      showTools = display.showTools
    )
    content.replace(contentHost, kept.conversationId, kept.turns, kept.live)
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

  /** Asks again while the link is up and this chat still has no turn.
      An empty outline answered before the window was bound must not be the last word. */
  fun flush(current: MonitorUi): List<MonitorEffect>? = synchronized(gate) {
    if (!commandsReady()) return null
    val board = content.current()
    if (board.turns.isNotEmpty() || board.live != null) {
      screenAskedAt = 0L
      return null
    }
    if (local.conversationId.isEmpty() && !local.catchingUp) return null
    val now = clock.nowMs()
    if (screenAskedAt != 0L && now - screenAskedAt < 2000L) return null
    screenAskedAt = now
    listOf(resumeNow())
  }

  /** The retry chip may offer the old text. It must not become the composer on the next open. */
  fun noteUndelivered(current: MonitorUi, text: String): MonitorUi = synchronized(gate) {
    local = local.copy(undeliveredPrompt = text)
    published()
  }

  fun noteDisplay(current: MonitorUi): MonitorUi = synchronized(gate) {
    selectedTurn = current.selectedTurn
    local = local.copy(selectedTurn = current.selectedTurn, showThinking = display.showThinking, showTools = display.showTools)
    published()
  }

  /** Open or close stays until the user dismisses it. A frame, a switch, or Connect must not clear it. */
  fun setSettingsOpen(open: Boolean) = synchronized(gate) {
    settingsHeld = open
    local = local.copy(settingsOpen = open, banner = if (open) "" else local.banner)
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

  /** Chrome from a state frame. The conversation board stays with the store. */
  fun noteSyncedChrome(next: MonitorUi): MonitorUi = synchronized(gate) {
    local = local.copy(
      view = next.view,
      planPath = next.planPath,
      planTitle = next.planTitle,
      planRunning = next.planRunning,
      planRows = next.planRows,
      planChoices = next.planChoices,
      targetChoices = next.targetChoices,
      targetCurrent = next.targetCurrent,
      conversationChoices = next.conversationChoices,
      conversationCurrent = next.conversationCurrent,
      conversationsTruncated = next.conversationsTruncated,
      modelChoices = next.modelChoices,
      modelBackend = next.modelBackend,
      modelNote = next.modelNote,
      reasoningChoices = next.reasoningChoices,
      reasoningCurrent = next.reasoningCurrent,
      reasoningNote = next.reasoningNote,
      permissionChoices = next.permissionChoices,
      permissionCurrent = next.permissionCurrent,
      permissionNote = next.permissionNote,
      approval = next.approval,
      approvalOpen = next.approvalOpen,
      statusBusy = next.statusBusy,
      activityStartedMs = next.activityStartedMs,
      projectRoot = next.projectRoot.ifEmpty { local.projectRoot },
      conversationTitle = next.conversationTitle.ifEmpty { local.conversationTitle },
      conversationId = next.conversationId.ifEmpty { local.conversationId },
      planRevision = next.planRevision,
      planReceived = next.planReceived,
      planTotal = next.planTotal,
      planIncomplete = next.planIncomplete,
      planBody = shownPlanBody(next.planTotal, next.planBody)
    )
    published()
  }

  fun notePlanFile(path: String, revision: String, received: Long, total: Long, incomplete: Boolean, body: String): MonitorUi =
    synchronized(gate) {
      local = local.copy(
        planPath = path.ifEmpty { local.planPath },
        planRevision = revision.ifEmpty { local.planRevision },
        planReceived = received,
        planTotal = total,
        planIncomplete = incomplete,
        planBody = shownPlanBody(total, body)
      )
      published()
    }

  fun noteSyncNote(text: String): MonitorUi = synchronized(gate) {
    if (text.isNotEmpty()) local = local.copy(banner = text)
    published()
  }

  fun noteCacheReadable(): MonitorUi = synchronized(gate) {
    local = local.copy(catchingUp = false, reviewingOffline = false)
    published()
  }

  /** The conversation row is the resume cursor. A hello head must not replace it. */
  fun noteResumeCursor(conversationId: String, streamId: String, seq: Long) = synchronized(gate) {
    resumeConversation = conversationId
    resumeStream = streamId
    resumeSeq = seq
    if (conversationId.isNotEmpty()) {
      local = local.copy(
        conversationId = conversationId,
        hostEpoch = streamId,
        hostCursor = seq
      )
    }
  }

  private fun quietFinishedBlocks() {
    if (local.view.sending || local.view.busy || local.view.planRunning || local.planRunning) return
    val board = content.current()
    val live = board.live?.let { turn ->
      val closed = closeFinishedRunning(turn.blocks)
      if (closed === turn.blocks) turn else turn.copy(blocks = closed)
    }
    val turns = board.turns.map { turn ->
      val closed = closeFinishedRunning(turn.blocks)
      if (closed === turn.blocks) turn else turn.copy(blocks = closed)
    }
    if (live == board.live && turns == board.turns) return
    content.replace(contentHost, board.conversationId, turns, live)
  }

  private fun published(): MonitorUi {
    quietFinishedBlocks()
    val board = content.current()
    if (local.pendingPrompt.isNotEmpty()) {
      val shown = local.withBoard(board)
      if (promptShown(shown, local.pendingPrompt) || hostHasLaterUserBlock(shown)) {
        local = local.copy(pendingPrompt = "", pendingKind = "", pendingCommandId = "")
      }
    }
    val settled = settleFinishedTurn(local.view, displayBlocks(board.live))
    if (settled != local.view) local = local.copy(view = settled)
    return local.copy(
      selectedTurn = selectedTurn,
      showThinking = display.showThinking,
      showTools = display.showTools,
      settingsOpen = settingsHeld
    ).withBoard(board)
  }

  private fun editDraft(text: String): List<MonitorEffect> {
    local = local.copy(draft = text, undeliveredPrompt = "")
    return listOf(MonitorEffect.RememberDraft(text))
  }

  /** Same rule as the enabled Send button. Syncing does not count as disconnected. */
  private fun maySubmit(): Boolean {
    return sendActionEnabled(local.view, local.disconnected, linkPhase, local.planRunning, syncingAccept())
  }

  private fun submit(): List<MonitorEffect>? {
    if (!maySubmit()) return null
    val text = local.draft.trim()
    if (text.isEmpty()) return null
    val steer = local.view.canSteer
    val commandId = session.nextCommandId()
    val encoded = if (steer) tryEncodeSteer(commandId, text) else tryEncodeSend(commandId, text)
    if (!encoded.ok) {
      local = local.copy(banner = "Text is longer than 65536 characters.")
      return emptyList()
    }
    submittedText = text
    submittedId = commandId
    val phase = if (steer) PhaseSteering else PhaseWaiting
    local = local.copy(
      draft = "",
      banner = "",
      undeliveredPrompt = "",
      pendingPrompt = text,
      pendingKind = if (steer) "steer" else "user",
      pendingCommandId = commandId,
      pendingEpoch = local.pendingEpoch + 1,
      promptBaseline = promptBaselineOf(content.current().live),
      view = local.view.copy(
        sending = true,
        busy = true,
        canSend = false,
        canSteer = steer,
        canStop = true,
        phase = phase,
        statusText = phase
      )
    )
    noteRunClock()
    if (syncingGap()) {
      held += HeldCommand(commandId, encoded.json, text, false)
      return listOf(MonitorEffect.RememberDraft(""), MonitorEffect.LeaveDictation)
    }
    return listOf(MonitorEffect.RememberDraft(""), MonitorEffect.LeaveDictation, MonitorEffect.Send(encoded.json))
  }

  private fun newConversation(): List<MonitorEffect>? {
    if (!newConversationEnabled(local.view, local.disconnected, linkPhase, local.planRunning, syncingAccept())) return null
    val commandId = session.nextCommandId()
    val json = encodeEmpty(MessageKind.NewConversation, commandId)
    if (syncingGap()) {
      if (held.any { command -> command.freshConversation }) return emptyList()
      held += HeldCommand(commandId, json, "", true)
      return emptyList()
    }
    return openFreshConversation(json)
  }

  private fun openFreshConversation(json: String): List<MonitorEffect> {
    val filed = fileOpenScreen()
    awaitingConversation = true
    content.replace(contentHost, "", emptyList(), null)
    local = local.copy(conversationId = "", conversationTitle = "", banner = "")
    return filed + MonitorEffect.Send(json)
  }

  private fun incoming(message: MonitorMessage): List<MonitorEffect> {
    val effects = mutableListOf<MonitorEffect>()
    when (message.kind) {
      MessageKind.HelloOk -> {
        noteHello(message)
        effects += resumeNow()
      }
      MessageKind.Snapshot, MessageKind.SnapshotPage, MessageKind.Catchup, MessageKind.Patch, MessageKind.BlockData -> {
        // Slices, fetches, and the baseline own the board. These frames must not paint it.
      }
      MessageKind.ConversationClosed -> {
        val closed = (message.inbound as? InboundPayload.ConversationClosed)?.value
          ?: decodeConversationClosed(message.payloadJson)
        if (closed != null) effects += applyClosed(closed)
      }
      MessageKind.Models -> decodeModels(message.payloadJson)?.let { models ->
        val named = if (models.current.isNotEmpty()) models.current else local.view.model
        local = local.copy(
          modelChoices = models.choices,
          modelBackend = models.backend,
          modelNote = models.note,
          view = local.view.copy(model = named)
        )
      }
      MessageKind.Status -> decodeStatusPayload(message.payloadJson)?.let { view ->
        val merged = settleFinishedTurn(
          local.view.patchStatus(view),
          displayBlocks(content.current().live)
        )
        local = local.copy(view = merged, statusBusy = view.busy, planRunning = view.planRunning)
      }
      MessageKind.Plan -> applyPlan(message)
      MessageKind.InsertResult -> decodeText(message.payloadJson)?.let { text ->
        if (local.draft.isEmpty()) local = local.copy(draft = text)
      }
      MessageKind.Error -> applyError(message)?.let { effects += it }
      MessageKind.ImageData, MessageKind.ImageUnavailable -> effects += MonitorEffect.DecodeImage(message)
      else -> {}
    }
    noteRunClock()
    return effects
  }

  private fun resetMatch() {
    content.unsealHostPaint()
  }

  /** Snapshot pages do not carry rows. This frame is the phone's plan. */
  private fun applyPlan(message: MonitorMessage) {
    val plan = (message.inbound as? InboundPayload.Plan)?.value ?: decodePlan(message.payloadJson) ?: return
    local = applyPlanMessage(local, plan)
  }

  private fun applyError(message: MonitorMessage): MonitorEffect? {
    val body = (message.inbound as? InboundPayload.Error)?.body ?: decodeError(message.payloadJson) ?: return null
    if (body.messageText == NothingRunningToSteer && local.draft.isNotEmpty()) {
      val encoded = tryEncodeSend(session.nextCommandId(), local.draft.trim())
      if (!encoded.ok) return null
      local = local.copy(banner = "")
      return MonitorEffect.Send(encoded.json)
    }
    if (body.refId.isNotEmpty() && body.refId == submittedId && local.draft.isEmpty() && submittedText.isNotEmpty()) {
      val text = submittedText
      submittedText = ""
      submittedId = ""
      local = local.copy(
        draft = text,
        pendingPrompt = "",
        pendingKind = "",
        pendingCommandId = "",
        banner = body.messageText,
        view = clearRemoteActions(local.view)
      )
      return MonitorEffect.RememberDraft(text)
    }
    // No screen is coming from this resume. Keep the turns already on screen.
    val waiting = body.reason == NoSessionReason || body.messageText == NoSessionMessage
    local = local.copy(banner = body.messageText, catchingUp = if (waiting) false else local.catchingUp)
    return null
  }

  private fun noteHello(message: MonitorMessage) {
    val hello = (message.inbound as? InboundPayload.HelloOk)?.value ?: decodeHelloOk(message.payloadJson) ?: return
    if (hello.hostId.isNotEmpty()) contentHost = hello.hostId
    if (awaitingConversation) {
      local = local.copy(projectRoot = hello.projectRoot.ifEmpty { local.projectRoot })
      return
    }
    // Keep the cached screen until the host pages arrive. Clearing here is the blank open.
    // A hello cursor is the desktop head. Copying it before resume asks for nothing, or the
    // desktop answers with every page and the phone dies under that dump.
    // The cached section stays until the desktop's current turn is ready to replace it.
    resetMatch()
    val board = content.current()
    val haveBody = board.turns.isNotEmpty() || board.live != null
    val announced = hello.epoch.ifEmpty { local.hostEpoch }
    val sameEpoch = announced.isEmpty() || announced == local.hostEpoch
    val keepPlace = haveBody && sameEpoch && local.hostCursor > 0L
    local = local.copy(
      conversationId = hello.conversationId.ifEmpty { local.conversationId },
      // A saved epoch must not reject the chat the desktop is about to send.
      hostEpoch = announced,
      hostCursor = if (keepPlace) local.hostCursor else if (hello.cursor > 0L) hello.cursor else local.hostCursor,
      projectRoot = hello.projectRoot.ifEmpty { local.projectRoot },
      conversationTitle = hello.title.ifEmpty { local.conversationTitle },
      catchingUp = true
    )
  }

  /** Writes the open screen under its id, then the caller drops it. */
  private fun fileOpenScreen(closedId: String = "", closedTitle: String = "", epoch: String = "", cursor: Long = 0): List<MonitorEffect> {
    val board = content.current()
    val id = closedId.ifEmpty { local.conversationId.ifEmpty { board.conversationId } }
    if (!conversationIdIsIdentity(id) || (board.turns.isEmpty() && board.live == null)) return emptyList()
    val title = cacheTitle(closedTitle.ifEmpty { local.conversationTitle }, board.turns, board.live, emptyList())
    val screen = local.copy(conversationId = id, conversationTitle = title).withBoard(board)
    val document = encodeClosedScreen(id, title, offlineDocument(screen))
    if (document.isEmpty()) return emptyList()
    val filedEpoch = epoch.ifEmpty { local.hostEpoch }
    val filedCursor = if (cursor > 0L) cursor else local.hostCursor
    return listOf(MonitorEffect.FileClosed(id, title, local.projectRoot, document, filedEpoch, filedCursor))
  }

  private fun applyClosed(closed: WireConversationClosed): List<MonitorEffect> {
    val filed = fileOpenScreen(closed.conversationId, closed.title, closed.epoch, closed.cursor)
    resetMatch()
    closedAwaitId = closed.conversationId
    awaitingConversation = true
    content.replace(contentHost, "", emptyList(), null)
    local = local.copy(conversationId = "", conversationTitle = "", banner = "", catchingUp = true)
    return filed
  }

  private fun resumeNow(): MonitorEffect {
    local = local.copy(catchingUp = true)
    val owed = session.takeSyncResume()
    if (owed != null) return MonitorEffect.Send(owed)
    if (resumeConversation.isNotEmpty()) {
      return MonitorEffect.Send(encodeSyncResume(session.nextCommandId(), resumeConversation, resumeStream, resumeSeq))
    }
    if (local.conversationId.isNotEmpty() && (local.hostEpoch.isNotEmpty() || local.hostCursor > 0L)) {
      return MonitorEffect.Send(encodeSyncResume(session.nextCommandId(), local.conversationId, local.hostEpoch, local.hostCursor))
    }
    return MonitorEffect.Send(encodeResume(session.nextCommandId(), "", 0L))
  }

  fun noteSyncTime(updatedAt: Long) = synchronized(gate) {
    if (updatedAt <= 0L || updatedAt == local.lastSyncMs) return
    local = local.copy(lastSyncMs = updatedAt)
  }

  /** Room may paint only the conversation New has not left. Catch-up does not hide a committed row. */
  fun acceptsRepository(conversationId: String): Boolean = synchronized(gate) {
    !awaitingConversation && conversationId.isNotEmpty() && conversationId == local.conversationId
  }

  /** The Plan tab highlight. A later plan frame for the same path keeps it. */
  fun noteSelectedPlan(index: Int): MonitorUi = synchronized(gate) {
    local = local.copy(selectedPlan = index)
    published()
  }

  private fun linkChanged(status: LinkStatus): List<MonitorEffect> {
    linkPhase = status.phase
    val replaced = status.lastError == ReplacedReason || status.banner == PairedElsewhereLabel
    if (replaced) {
      val restored = abandonHeld(true)
      local = local.copy(
        pairedElsewhere = true,
        disconnected = true,
        catchingUp = false,
        statusBusy = false,
        banner = PairedElsewhereLabel,
        view = clearRemoteActions(local.view)
      )
      noteRunClock()
      return restored
    }
    val down = status.phase == LinkPhase.Disconnected || status.phase == LinkPhase.Paused
    if (down) {
      closedAwaitId = ""
      local = local.copy(
        pairedElsewhere = false,
        disconnected = true,
        catchingUp = false,
        statusBusy = false,
        approvalOpen = false,
        approval = null,
        banner = status.banner.ifEmpty { if (status.phase == LinkPhase.Paused) HostClosedBanner else ReconnectingBanner },
        view = viewAfterDrop(clearRemoteActions(local.view))
      )
      noteRunClock()
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
    val released = releaseHeld()
    noteRunClock()
    return released
  }

  private fun commandResult(result: CatalogueResult): List<MonitorEffect> {
    if (held.any { command -> command.commandId == result.commandId }) return emptyList()
    if (result.outcome == CatalogueWrite.Written) {
      if (result.commandId == submittedId) {
        submittedText = ""
        submittedId = ""
      }
      return emptyList()
    }
    if (held.any { command -> command.commandId == submittedId }) return emptyList()
    if (local.draft.isNotEmpty()) return emptyList()
    val text = submittedText.ifEmpty { session.promptDraft }
    submittedText = ""
    submittedId = ""
    if (text.isEmpty()) {
      local = local.copy(banner = CouldNotSendBanner, pendingPrompt = "", pendingKind = "", pendingCommandId = "")
      return emptyList()
    }
    local = local.copy(
      draft = text,
      pendingPrompt = "",
      pendingKind = "",
      pendingCommandId = "",
      banner = CouldNotSendBanner,
      view = clearRemoteActions(local.view)
    )
    return listOf(MonitorEffect.RememberDraft(text))
  }

  private fun noteHost(clientId: String): List<MonitorEffect> {
    val draft = local.draft.ifEmpty { unsentPrompt() }
    if (held.isNotEmpty()) {
      submittedText = ""
      submittedId = ""
    }
    held.clear()
    content.clear()
    contentHost = clientId
    local = MonitorUi(draft = draft, showThinking = display.showThinking, showTools = display.showTools, disconnected = true)
    return listOf(MonitorEffect.ClearCaches)
  }

  private fun forgetPairing(): List<MonitorEffect> {
    held.clear()
    content.clear()
    contentHost = ""
    local = MonitorUi(showThinking = display.showThinking, showTools = display.showTools, disconnected = true)
    return listOf(MonitorEffect.ClearCaches, MonitorEffect.RememberDraft(""))
  }

  private fun syncingAccept(): Boolean {
    return linkSyncing(linkPhase, local.disconnected, local.catchingUp, local.pairedElsewhere)
  }

  private fun commandsReady(): Boolean {
    return linkPhase == LinkPhase.Live && !local.disconnected && !local.pairedElsewhere
  }

  /** The chip says Syncing and the socket cannot take a command yet. */
  private fun syncingGap(): Boolean = syncingAccept() && !commandsReady()

  /** The status clock is this start plus local time. A later zero sample must not put it back to 0:00. */
  private fun noteRunClock() {
    val board = content.current()
    val shown = local.withBoard(board)
    val blocks = displayBlocks(board.live)
    val pending = local.pendingPrompt.isNotEmpty() && !promptShown(shown, local.pendingPrompt)
    val running = turnStillRunning(local.view, pending, blocks, board.live)
    val now = clock.nowMs()
    if (!running) {
      if (local.activityStartedMs == 0L && local.activityObservedMs == 0) return
      local = local.copy(activityStartedMs = 0L, activityObservedMs = 0, activityAppliedMs = now.coerceAtLeast(0L))
      return
    }
    val observed = observedElapsedMs(local.view, board.live, blocks)
    val start = activityStart(local.activityStartedMs, now, observed, local.activityObservedMs)
    if (start == local.activityStartedMs && observed == local.activityObservedMs) return
    local = local.copy(
      activityStartedMs = start,
      activityObservedMs = observed,
      activityAppliedMs = now.coerceAtLeast(0L)
    )
  }

  private fun unsentPrompt(): String {
    return held.lastOrNull { command -> command.prompt.isNotEmpty() }?.prompt.orEmpty()
  }

  /** A dropped link must not look idle while a prompt is waiting to go out. */
  private fun viewAfterDrop(cleared: WireView): WireView {
    if (held.none { command -> command.prompt.isNotEmpty() }) return cleared
    return cleared.copy(sending = true, busy = true, canSend = false, canSteer = false, canStop = false)
  }

  private fun abandonHeld(restore: Boolean): List<MonitorEffect> {
    val prompt = if (restore) unsentPrompt() else ""
    held.clear()
    if (!restore || prompt.isEmpty() || local.draft.isNotEmpty()) return emptyList()
    submittedText = ""
    submittedId = ""
    local = local.copy(draft = prompt, pendingPrompt = "", pendingKind = "", pendingCommandId = "", banner = "")
    return listOf(MonitorEffect.RememberDraft(prompt))
  }

  private fun releaseHeld(): List<MonitorEffect> {
    if (!commandsReady() || held.isEmpty()) return emptyList()
    val waiting = held.toList()
    held.clear()
    val effects = ArrayList<MonitorEffect>()
    for (command in waiting) {
      if (command.freshConversation) effects += openFreshConversation(command.json)
      else effects += MonitorEffect.Send(command.json)
    }
    return effects
  }

  private data class HeldCommand(
    val commandId: String,
    val json: String,
    val prompt: String,
    val freshConversation: Boolean
  )

}


