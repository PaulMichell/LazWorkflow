package computing.michell.monitor.ui

/* Catalogue orchestration without Android (c) 2026 Michell Computing.

   Speech stays on SpeechEngine. Draft edits replace the reducer draft,
   including with an empty string. A send clears the prompt immediately
   and keeps a pending user block until the desktop shows that text.
   A failed write puts the text back. Loaded fetches are separate from
   in-flight requests. Host change, forget pairing, New, and a null live
   snapshot share one reset. New keeps the mode already selected. */

import computing.michell.monitor.connection.CatalogueResult
import computing.michell.monitor.connection.CatalogueWrite
import computing.michell.monitor.connection.HostClosedBanner
import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.connection.LinkStatus
import computing.michell.monitor.connection.ReconnectingBanner
import computing.michell.monitor.connection.SessionPort
import computing.michell.monitor.protocol.InboundPayload
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.MonitorLimits
import computing.michell.monitor.protocol.MonitorMessage
import computing.michell.monitor.protocol.WireSnapshot
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.WireView
import computing.michell.monitor.protocol.decodeError
import computing.michell.monitor.protocol.decodeImageUnavailable
import computing.michell.monitor.protocol.decodeSnapshot
import computing.michell.monitor.protocol.decodeTurnData
import computing.michell.monitor.protocol.encodeClosedScreen
import computing.michell.monitor.protocol.AckPace
import computing.michell.monitor.protocol.encodeBlockGet
import computing.michell.monitor.protocol.paceAck
import computing.michell.monitor.protocol.encodeEmpty
import computing.michell.monitor.protocol.encodeImageGet
import computing.michell.monitor.protocol.encodeResume
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
  private val display: DisplayPreferences
) {
  private val gate = Any()
  private var applied = MonitorUi()
  private var ackPace = AckPace()
  private var appliedDirty = false
  private var postedGeneration = 0
  private val inFlightTurns = mutableMapOf<Int, String>()
  private val completedTurns = mutableSetOf<String>()
  private val inFlightImages = mutableMapOf<String, ImageFlight>()
  private val loadedImages = mutableSetOf<String>()
  private val fetchCommands = mutableMapOf<String, FetchTarget>()
  private val bitmapKeys = mutableSetOf<String>()
  private var visibleTurns = emptySet<Int>()
  private var hostBound = false
  private var linkHeld = false
  private var linkHeldAt = 0L
  private var linkPhase = LinkPhase.Idle
  private var hostAddress = ""
  private var hostPort = 0
  private var hostClientId = ""
  private var pendingText = ""
  private var writeSettled = false
  private var newConversationCommand = ""
  private var transcriptBroken = false
  private var lastMirrorMs = 0L
  private var stallResumeSent = false
  private var retryView: WireView? = null
  private var retryActivityMs = 0L
  private var screen = MonitorUi(
    draft = session.promptDraft,
    showThinking = display.showThinking,
    showTools = display.showTools
  )

  val state: MonitorUi get() = screen
  val holdingLink: Boolean get() = linkHeld

  /** Shows a saved session before the background connect replaces it. */
  fun restoreOffline(cached: MonitorUi) = synchronized(gate) {
    val shown = cached.copy(
      disconnected = true,
      reachedLive = false,
      pairHold = false,
      settingsOpen = false,
      approvalOpen = false,
      approval = null,
      planRunning = false,
      view = clearRemoteActions(cached.view)
    )
    screen = stamp(shown)
    applied = shown
  }
  val requestedTurnEntries: Set<Int> get() = inFlightTurns.keys.toSet()
  val inFlightImageKeys: Set<String> get() = inFlightImages.keys.toSet()
  val loadedImageKeys: Set<String> get() = loadedImages.toSet()
  val bitmapKeyEntries: Set<String> get() = bitmapKeys.toSet()

  fun onEvent(event: MonitorEvent): List<MonitorEffect>? = synchronized(gate) {
    when (event) {
      is MonitorEvent.DraftEdited -> editDraft(event.current, event.text)
      is MonitorEvent.Submit -> submit(event.current)
      is MonitorEvent.NewConversation -> newConversation(event.current)
      is MonitorEvent.Incoming -> incoming(event.current, event.message)
      is MonitorEvent.LinkChanged -> linkChanged(event.current, event.status)
      is MonitorEvent.CommandResult -> commandResult(event.current, event.result)
      is MonitorEvent.HostChanged -> noteHost(event.current, event.address, event.port, event.clientId)
      is MonitorEvent.ForgetPairing -> forgetPairing(event.current)
    }
  }

  /** Posts a dirty reduce. Null means the throttle has nothing to show. */
  fun flush(current: MonitorUi): List<MonitorEffect>? = synchronized(gate) {
    val effects = mutableListOf<MonitorEffect>()
    if (appliedDirty) {
      appliedDirty = false
      screen = show(current)
      val posted = publishReduced(applied, false, false)
      if (posted != null) {
        effects += posted
        effects += missingImageFetches(screen)
      }
    }
    val stall = stallResume()
    if (stall != null) effects += stall
    if (effects.isEmpty()) return null
    effects
  }

  fun noteTurnRequest(index: Int): Boolean = synchronized(gate) {
    if (index < 0 || inFlightTurns.containsKey(index)) return false
    inFlightTurns[index] = ""
    true
  }

  fun retainTurnRequests(known: Set<Int>) = synchronized(gate) {
    val gone = inFlightTurns.keys.filter { it !in known }
    for (index in gone) releaseTurn(index)
  }

  fun noteImageRequest(key: String): Boolean = synchronized(gate) {
    if (key.isEmpty() || inFlightImages.containsKey(key)) return false
    inFlightImages[key] = ImageFlight("", clock.nowMs(), imageIdOf(key))
    true
  }

  fun noteBitmap(key: String) = synchronized(gate) {
    if (key.isNotEmpty()) bitmapKeys.add(key)
  }

  /** A joined image is loaded. An incomplete transfer does not call this. */
  fun noteImageFetched(imageId: String) = synchronized(gate) {
    if (imageId.isEmpty()) return
    loadedImages.add(loadedImageKey(screen.hostGeneration, imageId))
    releaseImageId(imageId)
  }

  /** 2.3 dropped these assemblies. The in-flight key must go with them. */
  fun noteImagesExpired(imageIds: List<String>) = synchronized(gate) {
    for (imageId in imageIds) releaseImageId(imageId)
  }

  fun collectMissing(current: MonitorUi): List<MonitorEffect> = synchronized(gate) {
    screen = show(current)
    missingFetches(screen)
  }

  /** Visible turns reported by the screen. Does not accept every history index by itself. */
  fun noteVisibleTurns(current: MonitorUi, indices: Set<Int>): List<MonitorEffect> = synchronized(gate) {
    screen = show(current)
    if (indices == visibleTurns) return emptyList()
    visibleTurns = indices
    missingImageFetches(screen)
  }

  fun turnForImage(imageId: String): Int? = synchronized(gate) {
    val key = inFlightImages.entries.firstOrNull { it.value.imageId == imageId }?.key ?: return null
    val rest = key.substringAfter(":")
    rest.substringBefore(":").toIntOrNull()
  }

  fun requestTurnFetch(current: MonitorUi, index: Int): List<MonitorEffect> = synchronized(gate) {
    screen = show(current)
    val send = beginTurnFetch(screen, index) ?: return emptyList()
    listOf(send)
  }

  fun noteDisplay(current: MonitorUi): MonitorUi = synchronized(gate) {
    screen = show(current)
    screen
  }

  private fun editDraft(current: MonitorUi, text: String): List<MonitorEffect> {
    screen = show(current).copy(draft = text)
    applied = applied.copy(draft = text)
    return listOf(MonitorEffect.RememberDraft(text))
  }

  private fun submit(current: MonitorUi): List<MonitorEffect>? {
    screen = show(current)
    if (screen.disconnected) return null
    if (screen.pendingCommandId.isNotEmpty() && !writeSettled) return null
    val steer = screen.view.canSteer
    if (!screen.view.canSend && !steer) return null
    val text = screen.draft.trim()
    if (text.isEmpty()) return null
    val commandId = session.nextCommandId()
    val encoded = if (steer) tryEncodeSteer(commandId, text) else tryEncodeSend(commandId, text)
    if (!encoded.ok) {
      screen = screen.copy(banner = "Text is longer than 65536 characters.")
      return emptyList()
    }
    armSubmission(text, steer, commandId)
    return listOf(MonitorEffect.RememberDraft(screen.draft), MonitorEffect.Send(encoded.json))
  }

  private fun newConversation(current: MonitorUi): List<MonitorEffect>? {
    val shown = show(current)
    if (shown.disconnected || !shown.view.canSend) return null
    val commandId = session.nextCommandId()
    newConversationCommand = commandId
    val kept = shown.view
    val effects = resetIdentity(shown, false, applied.hostGeneration, applied.conversationGeneration + 1).toMutableList()
    // The desktop keeps this mode. Do not blank it while the snapshot is still on the way.
    val view = screen.view.copy(mode = kept.mode, modeLocked = kept.modeLocked, canChangeMode = kept.canChangeMode)
    screen = screen.copy(view = view)
    applied = applied.copy(view = view)
    effects += MonitorEffect.Send(encodeEmpty(MessageKind.NewConversation, commandId))
    return effects
  }

  private fun incoming(current: MonitorUi, message: MonitorMessage): List<MonitorEffect>? {
    if (message.kind == MessageKind.ImageData) return listOf(MonitorEffect.DecodeImage(message))
    if (message.kind == MessageKind.Snapshot) {
      val snapshot = (message.inbound as? InboundPayload.Snapshot)?.value ?: decodeSnapshot(message.payloadJson)
      if (snapshot != null && snapshot.live == null) {
        newConversationCommand = ""
        return acceptNullLive(show(current), snapshot)
      }
    }
    if (message.kind == MessageKind.Patch || message.kind == MessageKind.Catchup || message.kind == MessageKind.Plan) {
      noteMirrorProgress()
    }
    if (transcriptBroken && (message.kind == MessageKind.Snapshot || message.kind == MessageKind.Transcript)) {
      transcriptBroken = false
      applied = applied.copy(liveRevision = -1, transcriptParts = emptyMap(), transcriptTurnId = "")
    }
    val immediate = message.kind in ImmediateKinds
    val resumeBefore = applied.resumeOnce
    val closedBefore = applied.closedPending
    val clockBefore = applied.clockToken
    applied = reduceMonitor(applied, message)
    if (applied.clockToken != clockBefore && message.kind == MessageKind.Patch) {
      val patch = (message.inbound as? InboundPayload.Patch)?.value
      if (patch != null) {
        val idle = patchSaysIdle(patch.busy, patch.sending, patch.planRunning)
        applied = notePatchClock(applied, patch.elapsedMs, idle, clock.nowMs())
      }
    }
    noteFetchArrival(message)
    val fetches = applied.blockFetchIds
    if (fetches.isNotEmpty()) applied = applied.copy(blockFetchIds = emptyList())
    val side = mirrorSideEffects(resumeBefore, closedBefore) + helloResume(message) +
      fetches.map { blockId -> MonitorEffect.Send(encodeBlockGet(session.nextCommandId(), applied.conversationId, blockId)) } +
      ackEffects()
    if (!immediate) {
      appliedDirty = true
      return if (side.isEmpty()) null else side
    }
    appliedDirty = false
    val reduced = applied
    screen = show(current)
    val posted = publishReduced(reduced, message.kind == MessageKind.InsertResult, message.kind == MessageKind.Snapshot)
    val effects = posted?.toMutableList() ?: mutableListOf()
    effects += side
    if (reduced.rescueSteer && reduced.draft.isNotEmpty()) {
      applied = applied.copy(rescueSteer = false)
      val text = reduced.draft.trim()
      val commandId = session.nextCommandId()
      val encoded = tryEncodeSend(commandId, text)
      if (encoded.ok) {
        armSubmission(text, false, commandId)
        effects += MonitorEffect.RememberDraft(screen.draft)
        effects += MonitorEffect.Send(encoded.json)
      } else screen = screen.copy(banner = "Text is longer than 65536 characters.", rescueSteer = false)
    }
    if (message.kind == MessageKind.Snapshot) {
      newConversationCommand = ""
      effects += missingFetches(screen)
    }
    if (newConversationCommand.isNotEmpty() && message.kind == MessageKind.Error) {
      val body = (message.inbound as? InboundPayload.Error)?.body ?: decodeError(message.payloadJson)
      if (body != null && body.refId == newConversationCommand) noteFailedNew(effects)
    }
    if (posted == null && effects.isEmpty()) return null
    return effects
  }

  fun noteAckSent(nowMs: Long, seq: Long) {
    synchronized(gate) {
      ackPace = ackPace.copy(lastSentMs = nowMs, sentSeq = seq, pendingSeq = -1)
    }
  }

  private fun ackEffects(): List<MonitorEffect> {
    if (applied.hostEpoch.isEmpty() || applied.hostCursor < 0) return emptyList()
    val decision = paceAck(ackPace, clock.nowMs(), session.nextCommandId(), applied.conversationId, applied.hostEpoch,
      applied.hostCursor)
    ackPace = decision.pace
    if (decision.sendNow.isNotEmpty()) return listOf(MonitorEffect.Ack(decision.sendNow, decision.seq, 0))
    if (decision.sendLater.isNotEmpty()) return listOf(MonitorEffect.Ack(decision.sendLater, decision.seq, decision.laterMs))
    return emptyList()
  }

  private fun mirrorSideEffects(resumeBefore: Boolean, closedBefore: Boolean): List<MonitorEffect> {
    val effects = mutableListOf<MonitorEffect>()
    if (!resumeBefore && applied.resumeOnce) {
      effects += MonitorEffect.Send(encodeResume(session.nextCommandId(), applied.hostEpoch, applied.hostCursor))
    }
    if (!closedBefore && applied.closedPending) {
      val screen = offlineDocument(applied)
      val title = cacheTitle(applied.closedTitle, applied.turns, applied.live, applied.history.values.toList())
      val document = encodeClosedScreen(applied.closedConversationId, title, screen)
      if (document.isNotEmpty()) {
        effects += MonitorEffect.FileClosed(applied.closedConversationId, title, applied.projectRoot, document,
        applied.hostEpoch, applied.hostCursor)
      }
      applied = applied.copy(closedPending = false)
    }
    return effects
  }

  fun revealHeldLink(current: MonitorUi, status: LinkStatus): List<MonitorEffect>? = synchronized(gate) {
    if (!linkHeld || status.phase == LinkPhase.Live) {
      linkHeld = false
      return null
    }
    linkHeldAt = clock.nowMs() - LinkGraceMs - 1L
    linkChanged(current, status)
  }

  private fun linkChanged(current: MonitorUi, status: LinkStatus): List<MonitorEffect> {
    linkPhase = status.phase
    val reset = noteHost(current, session.hostAddress, session.hostPort, session.hostClientId)
    val effects = reset?.toMutableList() ?: mutableListOf()
    if (reset == null) screen = show(current)
    val closed = status.phase == LinkPhase.Disconnected || status.phase == LinkPhase.Paused
    val down = closed || status.phase == LinkPhase.Connecting
    if (down && screen.reachedLive) transcriptBroken = true
    if (status.phase == LinkPhase.Live) {
      linkHeld = false
      linkHeldAt = 0L
    } else if (down && status.phase != LinkPhase.Paused && screen.reachedLive) {
      if (!linkHeld) {
        linkHeld = true
        linkHeldAt = clock.nowMs()
      }
      if (clock.nowMs() - linkHeldAt < LinkGraceMs) return effects
      linkHeld = false
    }
    if (closed) {
      stallResumeSent = false
      screen = keepUnackedText(screen).copy(pendingCommandId = "")
      applied = keepUnackedText(applied).copy(pendingCommandId = "")
      retryView = null
      writeSettled = false
      pendingText = ""
      dropInFlight()
      val bannerText = if (status.banner.isEmpty()) HostClosedBanner else status.banner
      applied = noteSocketClosed(applied, bannerText)
      effects += MonitorEffect.LeaveDictation
    }
    val pin = status.banner == "TLS pin mismatch."
    if (session.promptDraft != screen.draft) effects += MonitorEffect.RememberDraft(screen.draft)
    val linked = applyLink(screen, status.phase, status.banner)
    val shown = linked.copy(pairHold = linked.pairHold || pin, draft = screen.draft)
    if (shown.generation > postedGeneration) postedGeneration = shown.generation
    screen = stamp(shown)
    if (status.phase == LinkPhase.Live && lastMirrorMs <= 0L) lastMirrorMs = clock.nowMs()
    return effects
  }

  private fun commandResult(current: MonitorUi, result: CatalogueResult): List<MonitorEffect> {
    if (result.outcome == CatalogueWrite.Failed || result.outcome == CatalogueWrite.Stale) releaseFailedFetch(result.commandId)
    if (result.commandId.isNotEmpty() && result.commandId == newConversationCommand &&
      result.outcome != CatalogueWrite.Written) {
      screen = show(current)
      val effects = mutableListOf<MonitorEffect>()
      noteFailedNew(effects)
      return effects
    }
    screen = show(current)
    if (result.commandId.isEmpty() || result.commandId != screen.pendingCommandId || writeSettled) return emptyList()
    return when (result.outcome) {
      CatalogueWrite.Written -> acceptWritten(screen)
      CatalogueWrite.Failed, CatalogueWrite.Stale -> rejectWrite(screen)
    }
  }

  private fun noteFailedNew(effects: MutableList<MonitorEffect>) {
    newConversationCommand = ""
    effects += MonitorEffect.Send(encodeResume(session.nextCommandId(), applied.hostEpoch, applied.hostCursor))
  }

  private fun armSubmission(text: String, steer: Boolean, commandId: String) {
    val before = screen
    retryView = before.view
    retryActivityMs = before.activityStartedMs
    pendingText = text
    writeSettled = false
    val submitted = beginSubmit(before, text, steer, clock.nowMs(), commandId)
    screen = stamp(submitted)
    applied = applied.copy(
      draft = "",
      pendingPrompt = submitted.pendingPrompt,
      pendingKind = submitted.pendingKind,
      pendingCommandId = submitted.pendingCommandId,
      pendingEpoch = submitted.pendingEpoch,
      promptBaseline = submitted.promptBaseline,
      view = submitted.view,
      activityStartedMs = submitted.activityStartedMs,
      rescueSteer = false
    )
  }

  private fun acceptWritten(state: MonitorUi): List<MonitorEffect> {
    writeSettled = true
    retryView = null
    val kept = if (state.draft.trim() == pendingText) "" else state.draft
    screen = state.copy(draft = kept)
    applied = applied.copy(draft = kept)
    return listOf(MonitorEffect.RememberDraft(kept))
  }

  private fun rejectWrite(state: MonitorUi): List<MonitorEffect> {
    val text = state.draft.ifEmpty { state.pendingPrompt.ifEmpty { pendingText } }
    val view = (retryView ?: state.view).copy(busy = false, sending = false)
    retryView = null
    pendingText = ""
    writeSettled = false
    val restored = state.copy(
      draft = text,
      pendingPrompt = "",
      pendingKind = "",
      pendingCommandId = "",
      promptBaseline = emptySet(),
      banner = CouldNotSendBanner,
      view = view,
      activityStartedMs = retryActivityMs
    )
    screen = stamp(restored)
    applied = applied.copy(
      draft = text,
      pendingPrompt = "",
      pendingKind = "",
      pendingCommandId = "",
      promptBaseline = emptySet(),
      banner = CouldNotSendBanner,
      view = view,
      activityStartedMs = retryActivityMs
    )
    return listOf(MonitorEffect.RememberDraft(text))
  }

  private fun keepUnackedText(state: MonitorUi): MonitorUi {
    if (state.pendingPrompt.isEmpty()) return state
    val text = state.draft.ifEmpty { state.pendingPrompt }
    if (text.isEmpty()) return state
    return state.copy(
      draft = text,
      pendingPrompt = "",
      pendingKind = "",
      pendingCommandId = "",
      promptBaseline = emptySet()
    )
  }

  private fun acceptNullLive(current: MonitorUi, snapshot: WireSnapshot): List<MonitorEffect> {
    val effects = resetIdentity(stamp(current), false, applied.hostGeneration, applied.conversationGeneration + 1).toMutableList()
    val shown = overlaySnapshot(applied, snapshot, current.generation + 1)
    applied = shown
    screen = stamp(shown)
    postedGeneration = shown.generation
    effects += missingFetches(screen)
    effects += MonitorEffect.Prefetch
    return effects
  }

  private fun forgetPairing(current: MonitorUi): List<MonitorEffect> {
    hostBound = false
    hostAddress = ""
    hostPort = 0
    hostClientId = ""
    val effects = resetIdentity(stamp(current), true, applied.hostGeneration + 1, applied.conversationGeneration + 1).toMutableList()
    screen = screen.copy(settingsOpen = false, pairHold = false, disconnected = true)
    applied = applied.copy(settingsOpen = false, pairHold = false, disconnected = true)
    return effects
  }

  private fun noteHost(current: MonitorUi, address: String, port: Int, clientId: String): List<MonitorEffect>? {
    val adopting = !hostBound || (hostAddress.isEmpty() && address.isNotEmpty() && hostClientId.isEmpty())
    if (adopting) {
      hostBound = true
      hostAddress = address
      hostPort = port
      hostClientId = clientId
      return null
    }
    val endpointChanged = address != hostAddress || port != hostPort
    val clientChanged = hostClientId.isNotEmpty() && clientId != hostClientId
    hostAddress = address
    hostPort = port
    hostClientId = clientId
    if (!endpointChanged && !clientChanged) return null
    val effects = resetIdentity(stamp(current), true, applied.hostGeneration + 1, applied.conversationGeneration + 1)
    screen = screen.copy(settingsOpen = false, pairHold = false)
    applied = applied.copy(settingsOpen = false, pairHold = false)
    return effects
  }

  private fun resetIdentity(
    current: MonitorUi,
    clearDraft: Boolean,
    hostGeneration: Int,
    conversationGeneration: Int
  ): List<MonitorEffect> {
    appliedDirty = false
    postedGeneration = 0
    retryView = null
    pendingText = ""
    writeSettled = false
    val cleared = resetConversation(current, clearDraft, hostGeneration, conversationGeneration)
    applied = cleared
    screen = stamp(cleared)
    dropInFlight()
    completedTurns.clear()
    loadedImages.clear()
    bitmapKeys.clear()
    visibleTurns = emptySet()
    session.resetImages()
    val effects = mutableListOf<MonitorEffect>(MonitorEffect.ClearCaches)
    if (session.promptDraft != cleared.draft) effects += MonitorEffect.RememberDraft(cleared.draft)
    return effects
  }

  private fun publishReduced(hint: MonitorUi, useReducedDraft: Boolean, clearDisconnect: Boolean): List<MonitorEffect>? {
    val next = if (hint.generation < applied.generation) applied else hint
    if (next.generation < postedGeneration) return null
    postedGeneration = next.generation
    screen = stamp(mergeApplied(screen, next, useReducedDraft, clearDisconnect, clock.nowMs()))
    val effects = mutableListOf<MonitorEffect>()
    if (useReducedDraft) {
      effects += MonitorEffect.LeaveDictation
      effects += MonitorEffect.RememberDraft(next.draft)
    }
    if (clearDisconnect) effects += MonitorEffect.Prefetch
    return effects
  }

  /** A caller copy can lag the submission already on screen. Do not put that text back. */
  private fun adopt(current: MonitorUi): MonitorUi {
    if (screen.pendingEpoch > current.pendingEpoch) {
      return current.copy(
        draft = screen.draft,
        pendingPrompt = screen.pendingPrompt,
        pendingKind = screen.pendingKind,
        pendingCommandId = screen.pendingCommandId,
        pendingEpoch = screen.pendingEpoch,
        promptBaseline = screen.promptBaseline,
        activityStartedMs = if (screen.activityStartedMs > 0L) screen.activityStartedMs else current.activityStartedMs,
        view = if (screen.view.sending || screen.view.busy) screen.view else current.view
      )
    }
    if (screen.pendingPrompt.isNotEmpty() && screen.draft.isEmpty() && current.draft.trim() == screen.pendingPrompt) {
      return current.copy(
        draft = "",
        pendingPrompt = current.pendingPrompt.ifEmpty { screen.pendingPrompt },
        pendingKind = current.pendingKind.ifEmpty { screen.pendingKind },
        pendingCommandId = current.pendingCommandId.ifEmpty { screen.pendingCommandId },
        pendingEpoch = maxOf(current.pendingEpoch, screen.pendingEpoch),
        promptBaseline = if (current.promptBaseline.isEmpty()) screen.promptBaseline else current.promptBaseline
      )
    }
    return current
  }

  private fun noteMirrorProgress() {
    lastMirrorMs = clock.nowMs()
    stallResumeSent = false
  }

  private fun helloResume(message: MonitorMessage): List<MonitorEffect> {
    if (message.kind != MessageKind.HelloOk) return emptyList()
    lastMirrorMs = clock.nowMs()
    stallResumeSent = true
    return listOf(MonitorEffect.Send(encodeResume(session.nextCommandId(), applied.hostEpoch, applied.hostCursor)))
  }

  /** One resume for a live gap. Not another until patch, catchup, plan, or a socket drop. */
  private fun stallResume(): MonitorEffect? {
    if (linkPhase != LinkPhase.Live || linkHeld || screen.disconnected || stallResumeSent) return null
    val waiting = screen.catchingUp || screen.view.busy || screen.view.sending || screen.view.planRunning ||
      screen.planRunning
    if (!waiting) return null
    val now = clock.nowMs()
    if (lastMirrorMs <= 0L) {
      lastMirrorMs = now
      return null
    }
    if (now - lastMirrorMs < StallGapMs) return null
    stallResumeSent = true
    return MonitorEffect.Send(encodeResume(session.nextCommandId(), applied.hostEpoch, applied.hostCursor))
  }

  private fun show(current: MonitorUi): MonitorUi = stamp(adopt(current))

  private fun stamp(current: MonitorUi): MonitorUi {
    return current.copy(showThinking = display.showThinking, showTools = display.showTools)
  }

  private fun noteFetchArrival(message: MonitorMessage) {
    when (message.kind) {
      MessageKind.TurnData -> {
        val turn = (message.inbound as? InboundPayload.Turn)?.value ?: decodeTurnData(message.payloadJson) ?: return
        completeTurn(turn.turnIndex)
      }
      MessageKind.ImageUnavailable -> {
        val image = (message.inbound as? InboundPayload.ImageMissing)?.value ?: decodeImageUnavailable(message.payloadJson) ?: return
        noteImageFetched(image.imageId)
      }
      else -> {}
    }
  }

  private fun missingFetches(state: MonitorUi): List<MonitorEffect> {
    expireImageFlights(clock.nowMs())
    val effects = mutableListOf<MonitorEffect>()
    val slots = virtualSlots(state.turns, state.live, state.view.sending)
    val known = slots.map { slot -> slot.turnIndex }.filter { index -> index >= 0 }.toSet()
    for (index in inFlightTurns.keys.filter { it !in known }) releaseTurn(index)
    val loaded = loadedTurnIndices(state) + completedIndices(state.hostGeneration)
    for (index in recentFetches(slots, loaded)) {
      val send = beginTurnFetch(state, index) ?: continue
      effects += send
    }
    effects += missingImageFetches(state)
    return effects
  }

  private fun missingImageFetches(state: MonitorUi): List<MonitorEffect> {
    if (state.disconnected) return emptyList()
    val images = linkedMapOf<Int, List<String>>()
    for (turn in state.turns) {
      val loaded = state.history[turn.turnIndex]
      images[turn.turnIndex] = turnImageIds(loaded ?: turn)
    }
    val live = state.live
    if (live != null) images[live.turnIndex] = turnImageIds(live)
    val keys = imageRequestKeys(
      state.hostGeneration,
      state.turns.map { it.turnIndex },
      images,
      live?.turnIndex,
      visibleTurns,
      state.imageReasons.keys
    )
    val effects = mutableListOf<MonitorEffect>()
    for (key in keys) {
      val send = beginImageFetch(state, key.turnIndex, key.imageId) ?: continue
      effects += send
    }
    return effects
  }

  private fun beginTurnFetch(state: MonitorUi, index: Int): MonitorEffect? {
    if (state.disconnected) return null
    if (index < 0 || inFlightTurns.containsKey(index)) return null
    if (index in loadedTurnIndices(state) || turnDoneKey(state.hostGeneration, index) in completedTurns) return null
    val commandId = session.nextCommandId()
    inFlightTurns[index] = commandId
    fetchCommands[commandId] = FetchTarget.Turn(index)
    return MonitorEffect.Send(encodeTurnRequest(commandId, index))
  }

  private fun beginImageFetch(state: MonitorUi, turnIndex: Int, imageId: String): MonitorEffect? {
    if (state.disconnected) return null
    if (imageLoaded(state.hostGeneration, imageId)) return null
    val key = imageFlightKey(state.hostGeneration, turnIndex, imageId)
    if (inFlightImages.containsKey(key)) return null
    val commandId = session.nextCommandId()
    inFlightImages[key] = ImageFlight(commandId, clock.nowMs(), imageId)
    fetchCommands[commandId] = FetchTarget.Image(key)
    return MonitorEffect.Send(encodeImageGet(commandId, turnIndex, imageId))
  }

  private fun completeTurn(index: Int) {
    completedTurns.add(turnDoneKey(screen.hostGeneration, index))
    releaseTurn(index)
  }

  private fun releaseFailedFetch(commandId: String) {
    when (val target = fetchCommands.remove(commandId)) {
      is FetchTarget.Turn -> if (inFlightTurns[target.index] == commandId) inFlightTurns.remove(target.index)
      is FetchTarget.Image -> {
        val flight = inFlightImages[target.key]
        if (flight != null && flight.commandId == commandId) inFlightImages.remove(target.key)
      }
      null -> {}
    }
  }

  private fun releaseTurn(index: Int) {
    val commandId = inFlightTurns.remove(index) ?: return
    if (commandId.isNotEmpty()) fetchCommands.remove(commandId)
  }

  private fun releaseImage(key: String) {
    val flight = inFlightImages.remove(key) ?: return
    if (flight.commandId.isNotEmpty()) fetchCommands.remove(flight.commandId)
  }

  private fun releaseImageId(imageId: String) {
    val keys = inFlightImages.filter { (_, flight) -> flight.imageId == imageId }.keys.toList()
    for (key in keys) releaseImage(key)
  }

  private fun expireImageFlights(nowMs: Long) {
    val stale = inFlightImages.filter { (_, flight) -> nowMs - flight.startedMs >= MonitorLimits.ImageAssemblyTtlMs }.keys.toList()
    for (key in stale) releaseImage(key)
  }

  private fun dropInFlight() {
    inFlightTurns.clear()
    inFlightImages.clear()
    fetchCommands.clear()
  }

  private fun completedIndices(hostGeneration: Int): Set<Int> {
    val prefix = hostGeneration.toString() + ":"
    return completedTurns.filter { it.startsWith(prefix) }.map { it.removePrefix(prefix).toInt() }.toSet()
  }

  private fun imageLoaded(hostGeneration: Int, imageId: String): Boolean {
    return loadedImageKey(hostGeneration, imageId) in loadedImages
  }

  private fun turnDoneKey(hostGeneration: Int, index: Int): String = hostGeneration.toString() + ":" + index.toString()

  private fun loadedImageKey(hostGeneration: Int, imageId: String): String = hostGeneration.toString() + ":" + imageId

  private fun imageFlightKey(hostGeneration: Int, turnIndex: Int, imageId: String): String {
    return hostGeneration.toString() + ":" + turnIndex.toString() + ":" + imageId
  }

  private fun imageIdOf(key: String): String = key.substringAfterLast(":")

  private sealed class FetchTarget {
    data class Turn(val index: Int) : FetchTarget()
    data class Image(val key: String) : FetchTarget()
  }

  private data class ImageFlight(val commandId: String, val startedMs: Long, val imageId: String)

  private companion object {
    val ImmediateKinds = setOf(
      MessageKind.Snapshot,
      MessageKind.Rejected,
      MessageKind.Error,
      MessageKind.InsertResult,
      MessageKind.Status,
      MessageKind.Patch,
      MessageKind.Catchup,
      MessageKind.ConversationClosed,
      MessageKind.HelloOk
    )
  }
}
