package computing.michell.monitor.ui

/* Coordinator seam without AndroidViewModel (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.SessionPort
import computing.michell.monitor.protocol.ApprovalNotice
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.WireSnapshot
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.decodeText
import computing.michell.monitor.protocol.encodeEnvelope
import computing.michell.monitor.protocol.encodeError
import computing.michell.monitor.protocol.encodeInsertResult
import computing.michell.monitor.protocol.encodeSnapshot
import computing.michell.monitor.protocol.statusToJson
import computing.michell.monitor.protocol.tryDecodeEnvelope
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MonitorCoordinatorTest {
  @Test
  fun draftEditIsVisibleAndTheSnapshotIsApplied() {
    val coordinator = MonitorCoordinator(FakeSession(), FixedClock(1_000L), FixedDisplay(true, false))
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "keep this"))
    assertEquals("keep this", coordinator.state.draft)
    val snapshot = WireSnapshot(
      emptyView().copy(model = "grok-test", canSend = true),
      emptyList(),
      WireTurn(3, "turn-3", "build", "", "live", ""),
      "Documents/Plan.md",
      "Monitor",
      false,
      emptyList(),
      emptyList(),
      ApprovalNotice(false, "", "", "", "", false)
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("snap", snapshot))))
    assertEquals("grok-test", coordinator.state.view.model)
    assertEquals("Documents/Plan.md", coordinator.state.planPath)
    assertEquals(3, coordinator.state.live?.turnIndex)
    // Today's merge keeps a typed draft. This is not the empty-draft fix.
    assertEquals("keep this", coordinator.state.draft)
    assertTrue(coordinator.state.showThinking)
    assertEquals(false, coordinator.state.showTools)
  }

  @Test
  fun insertThenSendThenStatusLeavesTheDraftEmpty() {
    val coordinator = coordinator()
    openLive(coordinator, canSend = true, canSteer = false)
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeInsertResult("ins", "pasted"))))
    assertEquals("pasted", coordinator.state.draft)
    val sent = coordinator.onEvent(MonitorEvent.Submit(coordinator.state)).orEmpty()
    assertEquals("", coordinator.state.draft)
    assertEquals("pasted", coordinator.state.pendingPrompt)
    assertEquals("user", coordinator.state.pendingKind)
    assertEquals("c1", coordinator.state.pendingCommandId)
    assertEquals(1, coordinator.state.pendingEpoch)
    assertEquals(listOf("pasted"), sendTexts(sent))
    val status = coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeEnvelope(
      MessageKind.Status, "st", statusToJson(emptyView().copy(canSend = true, signedIn = true))
    ))))
    assertEquals("", coordinator.state.draft)
    assertEquals(emptyList<String>(), sendTexts(status.orEmpty()))
  }

  @Test
  fun steerErrorFallsBackToSendOfTheSameText() {
    val coordinator = coordinator()
    openLive(coordinator, canSend = false, canSteer = true)
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "finish the form"))
    val steered = coordinator.onEvent(MonitorEvent.Submit(coordinator.state)).orEmpty()
    assertEquals("finish the form", coordinator.state.pendingPrompt)
    assertEquals("steer", coordinator.state.pendingKind)
    assertEquals("c1", coordinator.state.pendingCommandId)
    assertEquals(1, coordinator.state.pendingEpoch)
    assertEquals(MessageKind.Steer, envelope(sentJson(steered)).kind)
    val recovered = coordinator.onEvent(MonitorEvent.Incoming(
      coordinator.state,
      envelope(encodeError("err", "command", NothingRunningToSteer, "c1"))
    )).orEmpty()
    val send = envelope(sentJson(recovered))
    assertEquals(MessageKind.Send, send.kind)
    assertEquals("finish the form", decodeText(send.payloadJson))
  }
}

private fun coordinator(): MonitorCoordinator {
  return MonitorCoordinator(FakeSession(), FixedClock(1_000L), FixedDisplay(true, true))
}

private fun openLive(coordinator: MonitorCoordinator, canSend: Boolean, canSteer: Boolean) {
  val snapshot = WireSnapshot(
    emptyView().copy(canSend = canSend, canSteer = canSteer, signedIn = true),
    emptyList(),
    WireTurn(-2, "live", "build", "", "", ""),
    "",
    "",
    false,
    emptyList(),
    emptyList(),
    ApprovalNotice(false, "", "", "", "", false)
  )
  coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("live", snapshot))))
}

private fun sendTexts(effects: List<MonitorEffect>): List<String> {
  return effects.filterIsInstance<MonitorEffect.Send>().map { decodeText(envelope(it.json).payloadJson) ?: "" }
}

private fun sentJson(effects: List<MonitorEffect>): String {
  val sends = effects.filterIsInstance<MonitorEffect.Send>()
  assertEquals(1, sends.size)
  return sends[0].json
}

private class FixedClock(private val millis: Long) : MonitorClock {
  override fun nowMs(): Long = millis
}

private class FixedDisplay(
  override val showThinking: Boolean,
  override val showTools: Boolean
) : DisplayPreferences

private class FakeSession : SessionPort {
  private var stored = ""
  override val promptDraft: String get() = stored
  override fun nextCommandId(): String = "c1"
  override fun updateDraft(text: String) { stored = text }
  override fun sendCatalogue(json: String) {}
}

private fun envelope(json: String): computing.michell.monitor.protocol.MonitorMessage {
  val decoded = tryDecodeEnvelope(json)
  assertTrue(decoded.errorText, decoded.ok)
  return decoded.message
}
