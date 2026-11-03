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
import computing.michell.monitor.protocol.WirePatch
import computing.michell.monitor.protocol.WireSnapshot
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.encodePatch
import computing.michell.monitor.protocol.encodeSnapshot
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
  fun aPatchDoesNotReplaceTheStoredBody() {
    val coordinator = MonitorCoordinator(LockupSession(), LockupClock(1_000L), LockupDisplay)
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("snap", snapshot("first")))))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodePatch("late", patch("second", 9)))))
    assertNull(coordinator.state.live)
    assertEquals(0, coordinator.state.hostCursor)
    assertFalse(coordinator.holdingLink)
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

private fun snapshot(body: String): WireSnapshot {
  return WireSnapshot(
    emptyView().copy(canSend = true, busy = true),
    emptyList(),
    WireTurn(1, "turn-1", "build", "", body, "", live = true, blocks = listOf(block(body))),
    "",
    "",
    false,
    emptyList(),
    emptyList(),
    ApprovalNotice(false, "", "", "", "", false)
  )
}

private fun patch(body: String, cursor: Long): WirePatch {
  return WirePatch("epoch", cursor, 1, "turn-1", listOf(block(body)), false, false, false, "", true, false, false, 0)
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
