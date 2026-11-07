package computing.michell.monitor.ui

/* Catalogue 2 patches do not paint the conversation board (c) 2026 Michell Computing.

   The applier commits slices. A patch must not replace the stored body. */

import computing.michell.monitor.connection.CatalogueResult
import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.connection.LinkStatus
import computing.michell.monitor.connection.SessionPort
import computing.michell.monitor.protocol.ApprovalNotice
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.MonitorMessage
import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.tryDecodeEnvelope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MonitorCoordinatorLockupTest {

  @Test
  fun disconnectKeepsTheCommittedRows() {
    val coordinator = MonitorCoordinator(LockupSession(), LockupClock(1_000L), LockupDisplay)
    val prompt = WireBlock("user", "u", "", "", "", "kept", false, true, 0, emptyList())
    coordinator.showStored(MonitorUi(
      conversationId = "c1",
      turns = listOf(WireTurn(1, "t", "build", "", "kept", "", blocks = listOf(prompt))),
      planTitle = "Plan",
      planRows = listOf(computing.michell.monitor.protocol.PlanRow(1, 1, "Step", "", "pending", false))
    ), false)
    coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Disconnected, "", "")))
    assertEquals("kept", coordinator.state.turns.single().blocks.single().body)
    assertEquals("Plan", coordinator.state.planTitle)
    assertTrue(coordinator.state.disconnected)
    assertFalse(coordinator.state.approvalOpen)
    assertFalse(coordinator.state.view.busy)
    assertFalse(coordinator.state.view.sending)
  }

  @Test
  fun disconnectDoesNotKeepTheLinkLookingLive() {
    val coordinator = MonitorCoordinator(LockupSession(), LockupClock(1_000L), LockupDisplay)
    coordinator.noteSyncedChrome(coordinator.state.copy(view = coordinator.state.view.copy(canSend = true, busy = true, sending = true)))
    coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Disconnected, "", "")))
    assertTrue(coordinator.state.disconnected)
    assertFalse(coordinator.state.view.busy)
    assertFalse(coordinator.state.view.sending)
  }
}



private fun block(body: String): WireBlock {
  return WireBlock("answer", "b1", "", "", "", body, false, true, 0, emptyList())
}

private fun envelope(json: String): MonitorMessage {
  val decoded = tryDecodeEnvelope(json)
  assertTrue(decoded.errorText, decoded.ok)
  return decoded.message
}

private class LockupClock(var millis: Long) : MonitorClock {
  override fun nowMs(): Long = millis
}

private object LockupDisplay : DisplayPreferences {
  override val showThinking: Boolean = true
  override val showTools: Boolean = true
}

private class LockupSession : SessionPort {
  override val promptDraft: String = ""
  override val hostAddress: String = ""
  override val hostPort: Int = 0
  override val hostClientId: String = ""
  override val linkEpoch: Int = 1
  override val commandResults: Flow<CatalogueResult> = emptyFlow()
  override fun nextCommandId(): String = "c1"
  override fun updateDraft(text: String) {}
  override fun sendCatalogue(json: String) {}
  override fun resetImages() {}
}