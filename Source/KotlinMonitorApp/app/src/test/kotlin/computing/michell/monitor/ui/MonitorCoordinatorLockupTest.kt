package computing.michell.monitor.ui

/* Phone lock-up reproduction for plan item 2.2 (c) 2026 Michell Computing.

   Pins today's behaviour. After a cursor gap the phone ignores every later patch
   until a catchup arrives. It sends one resume only, and the busy flags it last
   applied stay on screen. Each patch that arrives, even one that is ignored, resets
   the stall timer, so no second resume goes out while the host keeps streaming.
   Item 3.1 changes this. These assertions then fail and are rewritten to assert
   the recovery. */

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
import computing.michell.monitor.protocol.decodeResume
import computing.michell.monitor.protocol.encodePatch
import computing.michell.monitor.protocol.encodeSnapshot
import computing.michell.monitor.protocol.tryDecodeEnvelope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MonitorCoordinatorLockupTest {
  @Test
  fun aCursorGapLeavesThePhoneBusyAfterOneResume() {
    val startMs = 10_000L
    val clock = LockupClock(startMs)
    val coordinator = MonitorCoordinator(LockupSession(), clock, LockupDisplay)
    val effects = mutableListOf<MonitorEffect>()
    effects += coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Live, ""))).orEmpty()
    effects += deliver(coordinator, encodeSnapshot("live", liveSnapshot()))
    effects += deliver(coordinator, encodePatch("patch-1", patch(1, busy = true, body = "first")))
    assertEquals(1L, coordinator.state.hostCursor)
    assertTrue(coordinator.state.view.busy)

    // Patch 2 never arrives. Patch 3 opens the gap, then the host streams on, idle, every pump.
    effects += deliver(coordinator, encodePatch("patch-3", patch(3, busy = false, body = "after the gap")))
    for (cursor in 4L..41L) {
      clock.millis += PumpIntervalMs
      effects += deliver(coordinator, encodePatch("patch-$cursor", patch(cursor, busy = false, body = "streamed $cursor")))
      effects += coordinator.flush(coordinator.state).orEmpty()
    }
    assertTrue(clock.millis - startMs > StallGapMs)

    val resumes = effects.filterIsInstance<MonitorEffect.Send>().map { envelope(it.json) }
      .filter { it.kind == MessageKind.Resume }
    assertEquals(1, resumes.size)
    val body = decodeResume(resumes.single().payloadJson)
    assertEquals("aa", body!!.epoch)
    assertEquals(1L, body.cursor)

    assertTrue(coordinator.state.view.busy)
    assertTrue(coordinator.state.view.sending)
    assertFalse(coordinator.state.view.canSend)
    assertEquals(1L, coordinator.state.hostCursor)
    assertEquals("first", coordinator.state.live?.blocks?.single()?.body)
  }
}

/** The bridge pumps the mirror every 150 ms. */
private const val PumpIntervalMs = 150L

private fun patch(cursor: Long, busy: Boolean, body: String): WirePatch {
  val block = WireBlock("answer", "b1", "", "", "", body, false, true, 0, emptyList())
  val phase = if (busy) "Thinking…" else ""
  return WirePatch("aa", cursor, 1, "turn-1", listOf(block), busy, busy, false, phase, !busy, false, busy, 0)
}

private fun liveSnapshot(): WireSnapshot {
  return WireSnapshot(
    emptyView().copy(canSend = true, signedIn = true),
    emptyList(),
    WireTurn(-2, "live", "build", "", "", ""),
    "",
    "",
    false,
    emptyList(),
    emptyList(),
    ApprovalNotice(false, "", "", "", "", false)
  )
}

private fun deliver(coordinator: MonitorCoordinator, json: String): List<MonitorEffect> {
  return coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(json))).orEmpty()
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
  private var draft = ""
  private var ids = 1

  override val promptDraft: String get() = draft
  override val hostAddress: String = ""
  override val hostPort: Int = 0
  override val hostClientId: String = ""
  override val linkEpoch: Int = 1
  override val commandResults: Flow<CatalogueResult> = emptyFlow()
  override fun nextCommandId(): String {
    val id = "c$ids"
    ids += 1
    return id
  }
  override fun updateDraft(text: String) { draft = text }
  override fun sendCatalogue(json: String) {}
  override fun resetImages() {}
}
