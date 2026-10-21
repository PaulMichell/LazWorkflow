package computing.michell.monitor.ui

/* Catalogue orchestration without Android (c) 2026 Michell Computing.

   Speech stays on SpeechEngine. Draft edits replace the reducer draft,
   including with an empty string. Host change, forget pairing, and a
   null live snapshot share one reset. */

import computing.michell.monitor.connection.HostClosedBanner
import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.connection.LinkStatus
import computing.michell.monitor.connection.ReconnectingBanner
import computing.michell.monitor.connection.SessionPort
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.MonitorMessage
import computing.michell.monitor.protocol.WireSnapshot
import computing.michell.monitor.protocol.decodeSnapshot
import computing.michell.monitor.protocol.encodeEmpty
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

sealed class MonitorEvent {
  data class DraftEdited(val current: MonitorUi, val text: String) : MonitorEvent()
  data class Submit(val current: MonitorUi) : MonitorEvent()
  data class Incoming(val current: MonitorUi, val message: MonitorMessage) : MonitorEvent()
  data class LinkChanged(val current: MonitorUi, val status: LinkStatus) : MonitorEvent()
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
}

class MonitorCoordinator(
  private val session: SessionPort,
  private val clock: MonitorClock,
  private val display: DisplayPreferences
) {
  private val gate = Any()
  private var applied = MonitorUi()
  private var appliedDirty = false
  private var postedGeneration = 0
  private val requestedTurns = mutableSetOf<Int>()
  private val requestedImages = mutableSetOf<String>()
  private val bitmapKeys = mutableSetOf<String>()
  private var hostBound = false
  private var hostAddress = ""
  private var hostPort = 0
  private var hostClientId = ""
  private var screen = MonitorUi(
    draft = session.promptDraft,
    showThinking = display.showThinking,
    showTools = display.showTools
  )

  val state: MonitorUi get() = screen
  val requestedTurnEntries: Set<Int> get() = requestedTurns.toSet()
  val bitmapKeyEntries: Set<String> get() = bitmapKeys.toSet()

  fun onEvent(event: MonitorEvent): List<MonitorEffect>? = synchronized(gate) {
    when (event) {
      is MonitorEvent.DraftEdited -> editDraft(event.current, event.text)
      is MonitorEvent.Submit -> submit(event.current)
      is MonitorEvent.Incoming -> incoming(event.current, event.message)
      is MonitorEvent.LinkChanged -> linkChanged(event.current, event.status)
      is MonitorEvent.HostChanged -> noteHost(event.current, event.address, event.port, event.clientId)
      is MonitorEvent.ForgetPairing -> forgetPairing(event.current)
    }
  }

  /** Posts a dirty reduce. Null means the throttle has nothing to show. */
  fun flush(current: MonitorUi): List<MonitorEffect>? = synchronized(gate) {
    if (!appliedDirty) return null
    appliedDirty = false
    screen = stamp(current)
    publishReduced(applied, false, false)
  }

  fun noteTurnRequest(index: Int): Boolean = synchronized(gate) {
    if (index < 0) return false
    requestedTurns.add(index)
  }

  fun retainTurnRequests(known: Set<Int>) = synchronized(gate) {
    requestedTurns.retainAll(known)
  }

  fun noteImageRequest(key: String): Boolean = synchronized(gate) {
    if (key.isEmpty()) return false
    requestedImages.add(key)
  }

  fun noteBitmap(key: String) = synchronized(gate) {
    if (key.isNotEmpty()) bitmapKeys.add(key)
  }

  fun noteDisplay(current: MonitorUi): MonitorUi = synchronized(gate) {
    screen = current.copy(showThinking = display.showThinking, showTools = display.showTools)
    screen
  }

  private fun editDraft(current: MonitorUi, text: String): List<MonitorEffect> {
    screen = stamp(current).copy(draft = text)
    applied = applied.copy(draft = text)
    return listOf(MonitorEffect.RememberDraft(text))
  }

  private fun submit(current: MonitorUi): List<MonitorEffect>? {
    screen = stamp(current)
    if (screen.disconnected) return null
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
    val submitted = beginSubmit(screen, text, steer, clock.nowMs(), commandId)
    screen = stamp(submitted)
    applied = applied.copy(
      draft = "",
      pendingPrompt = submitted.pendingPrompt,
      pendingKind = submitted.pendingKind,
      pendingCommandId = submitted.pendingCommandId,
      pendingEpoch = submitted.pendingEpoch
    )
    return listOf(MonitorEffect.RememberDraft(""), MonitorEffect.Send(encoded.json))
  }

  private fun incoming(current: MonitorUi, message: MonitorMessage): List<MonitorEffect>? {
    if (message.kind == MessageKind.ImageData) return listOf(MonitorEffect.DecodeImage(message))
    if (message.kind == MessageKind.Snapshot) {
      val snapshot = decodeSnapshot(message.payloadJson)
      if (snapshot != null && snapshot.live == null) return acceptNullLive(current, snapshot)
    }
    val immediate = message.kind in ImmediateKinds
    applied = reduceMonitor(applied, message)
    if (!immediate) {
      appliedDirty = true
      return null
    }
    appliedDirty = false
    val reduced = applied
    screen = stamp(current)
    val posted = publishReduced(reduced, message.kind == MessageKind.InsertResult, message.kind == MessageKind.Snapshot)
    val effects = posted?.toMutableList() ?: mutableListOf()
    if (reduced.rescueSteer && reduced.draft.isNotEmpty()) {
      applied = applied.copy(rescueSteer = false)
      val encoded = tryEncodeSend(session.nextCommandId(), reduced.draft)
      if (encoded.ok) effects += MonitorEffect.Send(encoded.json)
      else screen = screen.copy(banner = "Text is longer than 65536 characters.", rescueSteer = false)
    }
    if (posted == null && effects.isEmpty()) return null
    return effects
  }

  private fun linkChanged(current: MonitorUi, status: LinkStatus): List<MonitorEffect> {
    val reset = noteHost(current, session.hostAddress, session.hostPort, session.hostClientId)
    val effects = reset?.toMutableList() ?: mutableListOf()
    if (reset == null) screen = stamp(current)
    if (status.phase == LinkPhase.Disconnected || status.phase == LinkPhase.Paused) {
      val bannerText = if (status.banner.isEmpty()) HostClosedBanner else status.banner
      applied = noteSocketClosed(applied, bannerText)
      effects += MonitorEffect.LeaveDictation
    }
    val pin = status.banner == "TLS pin mismatch."
    val wasDown = screen.disconnected || screen.banner == ReconnectingBanner
    if (session.promptDraft != screen.draft) effects += MonitorEffect.RememberDraft(screen.draft)
    val linked = applyLink(screen, status.phase, status.banner)
    val shown = linked.copy(pairHold = linked.pairHold || pin, draft = screen.draft)
    if (shown.generation > postedGeneration) postedGeneration = shown.generation
    screen = stamp(shown)
    if (status.phase == LinkPhase.Live && wasDown) {
      effects += MonitorEffect.Send(encodeEmpty(MessageKind.Refresh, session.nextCommandId()))
    }
    return effects
  }

  private fun acceptNullLive(current: MonitorUi, snapshot: WireSnapshot): List<MonitorEffect> {
    val effects = resetIdentity(stamp(current), false, applied.hostGeneration, applied.conversationGeneration + 1).toMutableList()
    val shown = overlaySnapshot(applied, snapshot, current.generation + 1)
    applied = shown
    screen = stamp(shown)
    postedGeneration = shown.generation
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
    val cleared = resetConversation(current, clearDraft, hostGeneration, conversationGeneration)
    applied = cleared
    screen = stamp(cleared)
    requestedTurns.clear()
    requestedImages.clear()
    bitmapKeys.clear()
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

  private fun stamp(current: MonitorUi): MonitorUi {
    return current.copy(showThinking = display.showThinking, showTools = display.showTools)
  }

  private companion object {
    val ImmediateKinds = setOf(
      MessageKind.Snapshot,
      MessageKind.Rejected,
      MessageKind.Error,
      MessageKind.InsertResult,
      MessageKind.Status
    )
  }
}
