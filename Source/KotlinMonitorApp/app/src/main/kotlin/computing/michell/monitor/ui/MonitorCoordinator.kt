package computing.michell.monitor.ui

/* Catalogue orchestration without Android (c) 2026 Michell Computing.

   Speech stays on SpeechEngine. This class forwards catalogue events and
   returns effects. It does not replace today's merge rules. */

import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.connection.LinkStatus
import computing.michell.monitor.connection.ReconnectingBanner
import computing.michell.monitor.connection.SessionPort
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.MonitorMessage
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
}

sealed class MonitorEffect {
  data class Send(val json: String) : MonitorEffect()
  data class RememberDraft(val text: String) : MonitorEffect()
  data object LeaveDictation : MonitorEffect()
  data object Prefetch : MonitorEffect()
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
  private var screen = MonitorUi(
    draft = session.promptDraft,
    showThinking = display.showThinking,
    showTools = display.showTools
  )

  val state: MonitorUi get() = screen

  fun onEvent(event: MonitorEvent): List<MonitorEffect>? = synchronized(gate) {
    when (event) {
      is MonitorEvent.DraftEdited -> editDraft(event.current, event.text)
      is MonitorEvent.Submit -> submit(event.current)
      is MonitorEvent.Incoming -> incoming(event.current, event.message)
      is MonitorEvent.LinkChanged -> linkChanged(event.current, event.status)
    }
  }

  /** Posts a dirty reduce. Null means the throttle has nothing to show. */
  fun flush(current: MonitorUi): List<MonitorEffect>? = synchronized(gate) {
    if (!appliedDirty) return null
    appliedDirty = false
    screen = stamp(current)
    publishReduced(applied, false, false)
  }

  fun noteDisplay(current: MonitorUi): MonitorUi = synchronized(gate) {
    screen = current.copy(showThinking = display.showThinking, showTools = display.showTools)
    screen
  }

  private fun editDraft(current: MonitorUi, text: String): List<MonitorEffect> {
    screen = stamp(current).copy(draft = text)
    return listOf(MonitorEffect.RememberDraft(text))
  }

  private fun submit(current: MonitorUi): List<MonitorEffect>? {
    screen = stamp(current)
    if (screen.disconnected) return null
    val steer = screen.view.canSteer
    if (!screen.view.canSend && !steer) return null
    val text = screen.draft.trim()
    if (text.isEmpty()) return null
    val encoded = if (steer) tryEncodeSteer(session.nextCommandId(), text) else tryEncodeSend(session.nextCommandId(), text)
    if (!encoded.ok) {
      screen = screen.copy(banner = "Text is longer than 65536 characters.")
      return emptyList()
    }
    screen = stamp(beginSubmit(screen, text, steer, clock.nowMs()))
    return listOf(MonitorEffect.RememberDraft(""), MonitorEffect.Send(encoded.json))
  }

  private fun incoming(current: MonitorUi, message: MonitorMessage): List<MonitorEffect>? {
    if (message.kind == MessageKind.ImageData) return listOf(MonitorEffect.DecodeImage(message))
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
    screen = stamp(current)
    val effects = mutableListOf<MonitorEffect>()
    if (status.phase == LinkPhase.Disconnected || status.phase == LinkPhase.Paused) effects += MonitorEffect.LeaveDictation
    val pin = status.banner == "TLS pin mismatch."
    val wasDown = screen.disconnected || screen.banner == ReconnectingBanner
    val sessionDraft = session.promptDraft
    if (sessionDraft.isEmpty() && screen.draft.isNotEmpty()) effects += MonitorEffect.RememberDraft(screen.draft)
    val synced = if (sessionDraft.isEmpty()) screen.draft else sessionDraft
    val linked = applyLink(screen, status.phase, status.banner)
    val shown = linked.copy(pairHold = linked.pairHold || pin, draft = synced.ifEmpty { screen.draft })
    if (shown.generation > postedGeneration) postedGeneration = shown.generation
    screen = stamp(shown)
    if (status.phase == LinkPhase.Live && wasDown) {
      effects += MonitorEffect.Send(encodeEmpty(MessageKind.Refresh, session.nextCommandId()))
    }
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
