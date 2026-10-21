package computing.michell.monitor.ui

/* Coordinator seam without AndroidViewModel (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.SessionPort
import computing.michell.monitor.protocol.ApprovalNotice
import computing.michell.monitor.protocol.WireSnapshot
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.encodeSnapshot
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
