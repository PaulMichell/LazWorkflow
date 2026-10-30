package computing.michell.monitor.ui

/* Coordinator boundaries after the screen reads the store (c) 2026 Michell Computing.

   Draft and sheets stay local. Conversation bodies are read back from the
   store. A disconnect is shown at once. A prompt is not matched to an older
   block. */

import computing.michell.monitor.connection.CatalogueResult
import computing.michell.monitor.connection.CatalogueWrite
import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.connection.LinkStatus
import computing.michell.monitor.connection.ReconnectingBanner
import computing.michell.monitor.connection.SessionPort
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.MonitorMessage
import computing.michell.monitor.protocol.PlanRow
import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WirePatch
import computing.michell.monitor.protocol.WireSnapshot
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.HelloOkMessage
import computing.michell.monitor.protocol.encodeHelloOk
import computing.michell.monitor.protocol.encodePatch
import computing.michell.monitor.protocol.encodePlan
import computing.michell.monitor.protocol.encodeSnapshot
import computing.michell.monitor.protocol.encodeSnapshotPage
import computing.michell.monitor.protocol.tryDecodeEnvelope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MonitorCoordinatorTest {
  @Test
  fun draftStaysLocalWhenTheStoreReplacesTheConversation() {
    val coordinator = open()
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "keep this"))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("snap", snapshot(live("old answer"))))))
    assertEquals("keep this", coordinator.state.draft)
    assertEquals("old answer", coordinator.state.live?.blocks?.first()?.body)
  }

  @Test
  fun submitClearsTheDraftAndDoesNotRestoreItFromALaterBlock() {
    val session = FakeSession()
    val coordinator = open(session)
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("snap", snapshot(null).copy(
      view = emptyView().copy(canSend = true)
    )))))
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "hello"))
    val effects = coordinator.onEvent(MonitorEvent.Submit(coordinator.state)).orEmpty()
    assertEquals("", coordinator.state.draft)
    assertTrue(effects.any { effect -> effect is MonitorEffect.Send })
    val echoed = live("hello world")
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("next", snapshot(echoed)))))
    assertEquals("", coordinator.state.draft)
  }

  @Test
  fun aFailedWritePutsTheDraftBack() {
    val session = FakeSession()
    val coordinator = open(session)
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("snap", snapshot(null).copy(
      view = emptyView().copy(canSend = true)
    )))))
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "keep this"))
    coordinator.onEvent(MonitorEvent.Submit(coordinator.state))
    coordinator.onEvent(MonitorEvent.CommandResult(coordinator.state, CatalogueResult("c1", 1, CatalogueWrite.Failed)))
    assertEquals("keep this", coordinator.state.draft)
    assertEquals(CouldNotSendBanner, coordinator.state.banner)
  }

  @Test
  fun hostChangeDropsThePreviousConversation() {
    val coordinator = open()
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("snap", snapshot(live("one"))))))
    assertEquals("one", coordinator.state.live?.blocks?.first()?.body)
    coordinator.onEvent(MonitorEvent.HostChanged(coordinator.state, "10.0.0.9", 56122, "other"))
    assertNull(coordinator.state.live)
    assertTrue(coordinator.state.turns.isEmpty())
  }

  @Test
  fun aLaterPatchReplacesTheBodyWithoutARevisionGate() {
    val coordinator = open()
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("snap", snapshot(live("first"))))))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodePatch("p2", patch("second", 8)))))
    assertEquals("second", coordinator.state.live?.blocks?.first()?.body)
    assertEquals(8, coordinator.state.hostCursor)
  }

  @Test
  fun disconnectIsShownAtOnce() {
    val coordinator = open()
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("snap", snapshot(live("live"))))))
    assertFalse(coordinator.holdingLink)
    coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Disconnected, ReconnectingBanner, "")))
    assertTrue(coordinator.state.disconnected)
    assertFalse(coordinator.holdingLink)
    assertNull(coordinator.revealHeldLink(coordinator.state, LinkStatus(LinkPhase.Disconnected, "", "")))
  }

  @Test
  fun aSnapshotPageEndsSyncingAndShowsTheDesktopTurn() {
    val coordinator = open()
    val hello = HelloOkMessage("nonce", "ide", "epoch", 118, "conversation-1", "/work", "Chat", "")
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeHelloOk("hello", hello))))
    assertTrue(coordinator.state.catchingUp)
    assertEquals(118, coordinator.state.hostCursor)
    val page = encodeSnapshotPage(
      "page-0",
      """{"conversation_id":"conversation-1","stream_id":"stream","seq":118,"turns":[{"turn_index":1,"turn_id":"turn-1","mode":"build","prompt_preview":"hello from the desktop","created_at":"","duration_ms":0}]}"""
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(page)))
    assertFalse(coordinator.state.catchingUp)
    assertEquals("hello from the desktop", coordinator.state.turns.single().promptPreview)
    val moved = encodePlan("plan-2", "Documents/Other.md", "Other", false, emptyList())
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(moved)))
    assertEquals("Documents/Other.md", coordinator.state.planPath)
    assertEquals("Other", coordinator.state.planTitle)
  }

  @Test
  fun aPlanFrameFillsTheScreenAndALaterPatchKeepsTheRows() {
    val coordinator = open()
    val row = PlanRow(1, 3, "Sync the plan", "", "not started", true)
    val frame = encodePlan("plan-1", "Documents/Plan.md", "Improved App Plan", true, listOf(row))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(frame)))
    assertEquals("Documents/Plan.md", coordinator.state.planPath)
    assertEquals("Improved App Plan", coordinator.state.planTitle)
    assertTrue(coordinator.state.planRunning)
    assertEquals("Sync the plan", coordinator.state.planRows.single().title)
    assertEquals("not started", coordinator.state.planRows.single().status)
    coordinator.noteSelectedPlan(1)
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodePatch("p2", patch("second", 8)))))
    assertEquals(1, coordinator.state.selectedPlan)
    assertEquals("Sync the plan", coordinator.state.planRows.single().title)
    val choices = frame.replace(
      "\"rows\" :",
      "\"choices\" : [{ \"path\" : \"Documents/Plan.md\", \"caption\" : \"Improved\" }], \"rows\" :"
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(choices)))
    assertEquals("Documents/Plan.md", coordinator.state.planChoices.single().path)
    assertEquals(1, coordinator.state.selectedPlan)
    val moved = encodePlan("plan-2", "Documents/Other.md", "Other", false, emptyList())
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(moved)))
    assertEquals(-1, coordinator.state.selectedPlan)
    assertEquals("Documents/Other.md", coordinator.state.planPath)
    assertTrue(coordinator.state.planChoices.isEmpty())
    assertFalse(coordinator.state.planRunning)
  }

  @Test
  fun steerErrorFallsBackToSendOfTheLocalDraft() {
    val session = FakeSession()
    val coordinator = open(session)
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "keep this"))
    val effects = coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(
      computing.michell.monitor.protocol.encodeError("e1", "command", NothingRunningToSteer, "steer-1")
    ))).orEmpty()
    val send = effects.filterIsInstance<MonitorEffect.Send>().single()
    assertEquals("keep this", computing.michell.monitor.protocol.decodeText(
      tryDecodeEnvelope(send.json).message.payloadJson
    ))
  }

  private fun open(session: FakeSession = FakeSession()): MonitorCoordinator {
    return MonitorCoordinator(session, FixedClock(1_000L), FixedDisplay(true, true))
  }
}

private fun snapshot(live: WireTurn?): WireSnapshot {
  return WireSnapshot(emptyView().copy(canSend = true), emptyList(), live, "", "", false, emptyList(), emptyList(),
    computing.michell.monitor.protocol.ApprovalNotice(false, "", "", "", "", false))
}

private fun live(body: String): WireTurn {
  return WireTurn(1, "turn-1", "build", "", body, "", live = true, blocks = listOf(WireBlock("answer", "b1", "", "", "", body, false, true, 0, emptyList())))
}

private fun patch(body: String, cursor: Long): WirePatch {
  return WirePatch("epoch", cursor, 1, "turn-1", listOf(WireBlock("answer", "b1", "", "", "", body, false, true, 0, emptyList())),
    false, false, false, "", true, false, false, 0)
}

private fun envelope(json: String): MonitorMessage {
  val decoded = tryDecodeEnvelope(json)
  assertTrue(decoded.errorText, decoded.ok)
  return decoded.message
}

private class FixedClock(private val millis: Long) : MonitorClock {
  override fun nowMs(): Long = millis
}

private class FixedDisplay(private val thinking: Boolean, private val tools: Boolean) : DisplayPreferences {
  override val showThinking: Boolean get() = thinking
  override val showTools: Boolean get() = tools
}

private class FakeSession : SessionPort {
  private var draft = ""
  private var ids = 1
  override val promptDraft: String get() = draft
  override val hostAddress: String = ""
  override val hostPort: Int = 0
  override val hostClientId: String = ""
  override val linkEpoch: Int = 1
  override val commandResults: Flow<CatalogueResult> = emptyFlow()
  override fun nextCommandId(): String = "c" + ids++
  override fun updateDraft(text: String) { draft = text }
  override fun sendCatalogue(json: String) {}
  override fun resetImages() {}
}
