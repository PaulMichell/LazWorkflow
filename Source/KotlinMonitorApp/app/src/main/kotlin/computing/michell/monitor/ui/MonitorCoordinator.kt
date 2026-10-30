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
import computing.michell.monitor.connection.ReconnectingBanner
import computing.michell.monitor.connection.SessionPort
import computing.michell.monitor.protocol.InboundPayload
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.MonitorMessage
import computing.michell.monitor.protocol.WireCatchup
import computing.michell.monitor.protocol.WireConversationClosed
import computing.michell.monitor.protocol.WirePatch
import computing.michell.monitor.protocol.WireSnapshot
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.WireView
import computing.michell.monitor.protocol.applySnapshotPageJson
import computing.michell.monitor.protocol.mergePatchBlocks
import computing.michell.monitor.protocol.conversationIdIsIdentity
import computing.michell.monitor.protocol.decodeCatchup
import computing.michell.monitor.protocol.decodeConversationClosed
import computing.michell.monitor.protocol.decodeError
import computing.michell.monitor.protocol.decodeHelloOk
import computing.michell.monitor.protocol.decodePatch
import computing.michell.monitor.protocol.decodePlan
import computing.michell.monitor.protocol.decodeSnapshot
import computing.michell.monitor.protocol.decodeStatusPayload
import computing.michell.monitor.protocol.decodeText
import computing.michell.monitor.protocol.encodeClosedScreen
import computing.michell.monitor.protocol.snapshotPageConversationId
import computing.michell.monitor.protocol.snapshotPageOutline
import computing.michell.monitor.protocol.snapshotPageSeq
import computing.michell.monitor.protocol.snapshotPageStreamId
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
  private var contentHost = ""
  private var submittedText = ""
  private var submittedId = ""
  private var selectedTurn = -1
  private var awaitingConversation = false
  private val visibleTurns = HashSet<Int>()
  /** Live until the first status, so an idle form can send before that frame. */
  private var linkPhase = LinkPhase.Live
  /** Send or New tapped while Syncing, before the socket can take it. */
  private val held = ArrayList<HeldCommand>()

  val state: MonitorUi
    get() = synchronized(gate) { published() }

  val holdingLink: Boolean get() = false
  val requestedTurnEntries: Set<Int> get() = emptySet()
  val inFlightImageKeys: Set<String> get() = emptySet()
  val loadedImageKeys: Set<String> get() = emptySet()
  val bitmapKeyEntries: Set<String> get() = emptySet()

  /** Shows a Room conversation. A live open is Syncing until the host snapshot arrives. */
  fun showStored(cached: MonitorUi, liveSync: Boolean) = synchronized(gate) {
    val typed = unsentPrompt()
    if (held.isNotEmpty()) {
      submittedText = ""
      submittedId = ""
    }
    held.clear()
    local = cached.copy(
      draft = cached.draft.ifEmpty { typed },
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
    val typed = unsentPrompt()
    if (held.isNotEmpty()) {
      submittedText = ""
      submittedId = ""
    }
    held.clear()
    local = cached.copy(
      draft = cached.draft.ifEmpty { typed },
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
    val board = content.current()
    if (local.pendingPrompt.isNotEmpty()) {
      val shown = local.withBoard(board)
      if (promptShown(shown, local.pendingPrompt) || hostHasLaterUserBlock(shown)) {
        local = local.copy(pendingPrompt = "", pendingKind = "", pendingCommandId = "")
      }
    }
    return local.copy(
      selectedTurn = selectedTurn,
      showThinking = display.showThinking,
      showTools = display.showTools
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
      MessageKind.Snapshot -> applySnapshot(decodeSnapshot(message.payloadJson) ?: snapshotFrom(message))
      MessageKind.SnapshotPage -> applySnapshotPage(message)
      MessageKind.Catchup -> decodeCatchup(message.payloadJson)?.let { applyCatchup(it) }
      MessageKind.Patch -> decodePatch(message.payloadJson)?.let { applyPatch(it) }
      MessageKind.ConversationClosed -> {
        val closed = (message.inbound as? InboundPayload.ConversationClosed)?.value
          ?: decodeConversationClosed(message.payloadJson)
        if (closed != null) effects += applyClosed(closed)
      }
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
    noteRunClock()
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
    val payload = message.payloadJson
    val seq = snapshotPageSeq(payload)
    val pageConversation = snapshotPageConversationId(payload)
    val pageEpoch = snapshotPageStreamId(payload)
    if (pageStartsFresh(pageConversation)) {
      awaitingConversation = false
      val id = pageConversation.ifEmpty { local.conversationId }
      content.replace(contentHost, id, emptyList(), null)
      local = local.copy(
        conversationId = id,
        conversationTitle = "",
        hostEpoch = pageEpoch.ifEmpty { local.hostEpoch },
        hostCursor = 0,
        catchingUp = false
      )
    } else if (pageConversation.isNotEmpty() && local.conversationId.isEmpty()) {
      local = local.copy(conversationId = pageConversation)
    }
    if (pageEpoch.isNotEmpty()) local = local.copy(hostEpoch = pageEpoch)
    val outline = snapshotPageOutline(payload)
    if (outline != null) {
      // The index is the conversation until each turn page arrives. Do not wipe bodies already shown.
      seedOutline(outline, pageConversation)
      if (seq > local.hostCursor) local = local.copy(hostCursor = seq)
      return
    }
    val board = content.current()
    val applied = applySnapshotPageJson(board.turns, board.live, payload) ?: return
    val id = pageConversation.ifEmpty { local.conversationId }
    if (id.isNotEmpty() && id != local.conversationId) local = local.copy(conversationId = id)
    if (applied.first !== board.turns || applied.second !== board.live || id != board.conversationId) {
      content.replace(contentHost, id, applied.first, applied.second)
    }
    noteCaughtUp(seq)
  }

  /** Adds index rows the screen does not have yet. A later turn page supplies the body. */
  private fun seedOutline(outline: List<WireTurn>, pageConversation: String) {
    val board = content.current()
    val foreign = board.conversationId.isNotEmpty() && pageConversation.isNotEmpty() &&
      board.conversationId != pageConversation && (board.turns.isNotEmpty() || board.live != null)
    if (foreign) return
    val added = addedOutlineTurns(board.turns, outline)
    if (added.isEmpty()) return
    val id = pageConversation.ifEmpty { local.conversationId }
    content.replace(contentHost, id, (board.turns + added).sortedBy { turn -> turn.turnIndex }, board.live)
  }

  /** A new id or epoch is a new cache copy. The previous turns are not a prefix. */
  private fun pageStartsFresh(pageConversation: String): Boolean {
    if (awaitingConversation) return true
    val board = content.current()
    if (pageConversation.isNotEmpty() && board.conversationId.isNotEmpty() && pageConversation != board.conversationId) return true
    return pageConversation.isNotEmpty() && local.conversationId.isNotEmpty() && pageConversation != local.conversationId
  }

  private fun applyCatchup(catchup: WireCatchup) {
    if (catchup.mode == "snapshot") {
      if (pageStartsFresh(catchup.conversationId)) {
        awaitingConversation = false
        val id = catchup.conversationId.ifEmpty { local.conversationId }
        content.replace(contentHost, id, emptyList(), null)
        local = local.copy(conversationId = id, conversationTitle = "")
      }
      if (catchup.conversationId.isNotEmpty()) local = local.copy(conversationId = catchup.conversationId)
      if (catchup.projectRoot.isNotEmpty()) local = local.copy(projectRoot = catchup.projectRoot)
      if (catchup.title.isNotEmpty()) local = local.copy(conversationTitle = catchup.title)
      if (catchup.epoch.isNotEmpty()) local = local.copy(hostEpoch = catchup.epoch)
      applySnapshot(catchup.snapshot)
      noteCaughtUp(catchup.cursor)
      return
    }
    if (catchup.mode != "events") return
    if (awaitingConversation || (catchup.epoch.isNotEmpty() && local.hostEpoch.isNotEmpty() && catchup.epoch != local.hostEpoch)) return
    // No patches means the cursor matched. It does not mean this screen is the desktop's.
    if (catchup.patches.isEmpty()) return
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
    if (awaitingConversation) return
    if (patch.epoch.isNotEmpty() && local.hostEpoch.isNotEmpty() && patch.epoch != local.hostEpoch) {
      local = local.copy(catchingUp = true, announcedEpoch = patch.epoch)
      return
    }
    val board = content.current()
    val previous = board.live?.takeIf { turn -> turn.id == patch.turnId || turn.turnIndex == patch.turnIndex }
      ?: board.turns.firstOrNull { turn -> turn.id == patch.turnId || turn.turnIndex == patch.turnIndex }
    val merged = mergePatchBlocks(previous?.blocks.orEmpty(), patch.blocks).blocks
    val live = WireTurn(
      if (patch.turnIndex != 0) patch.turnIndex else previous?.turnIndex ?: -2,
      patch.turnId.ifEmpty { previous?.id.orEmpty() },
      previous?.mode.orEmpty(),
      previous?.createdAt.orEmpty(),
      previous?.promptPreview.orEmpty(),
      "",
      live = true,
      blocks = merged,
      durationMs = if (patch.elapsedMs > 0) patch.elapsedMs else previous?.durationMs ?: 0
    )
    val kept = board.turns.filter { turn -> turn.id != live.id && turn.turnIndex != live.turnIndex }
    content.replace(contentHost, local.conversationId, kept, live)
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
    local = local.copy(banner = body.messageText)
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
    val board = content.current()
    val haveBody = board.turns.isNotEmpty() || board.live != null
    val keepPlace = haveBody && local.hostEpoch.isNotEmpty() && local.hostCursor > 0L
    local = local.copy(
      conversationId = hello.conversationId.ifEmpty { local.conversationId },
      hostEpoch = if (keepPlace) local.hostEpoch else hello.epoch.ifEmpty { local.hostEpoch },
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
    awaitingConversation = true
    content.replace(contentHost, "", emptyList(), null)
    local = local.copy(conversationId = "", conversationTitle = "", banner = "")
    return filed
  }

  private fun resumeNow(): MonitorEffect {
    // A saved cursor is not the open screen. Empty epoch makes the host send the mirror pages.
    local = local.copy(catchingUp = true)
    return MonitorEffect.Send(encodeResume(session.nextCommandId(), "", 0L))
  }

  fun noteSyncTime(updatedAt: Long) = synchronized(gate) {
    if (updatedAt <= 0L || updatedAt == local.lastSyncMs) return
    local = local.copy(lastSyncMs = updatedAt)
  }

  /** Room may paint only the conversation New has not left. */
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
      local = local.copy(
        pairedElsewhere = false,
        disconnected = true,
        statusBusy = false,
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

  private fun snapshotFrom(message: MonitorMessage): WireSnapshot? {
    return (message.inbound as? InboundPayload.Snapshot)?.value
  }
}


