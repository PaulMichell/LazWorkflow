package computing.michell.monitor.ui

/* Coordinator seam without AndroidViewModel (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.HostClosedBanner
import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.connection.LinkStatus
import computing.michell.monitor.connection.SessionPort
import computing.michell.monitor.protocol.ApprovalNotice
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireSnapshot
import computing.michell.monitor.protocol.WireTranscript
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.tryEncodeTranscript
import computing.michell.monitor.protocol.decodeText
import computing.michell.monitor.protocol.encodeEnvelope
import computing.michell.monitor.protocol.encodeError
import computing.michell.monitor.protocol.encodeInsertResult
import computing.michell.monitor.protocol.encodeSnapshot
import computing.michell.monitor.protocol.encodeTurnData
import computing.michell.monitor.protocol.statusToJson
import computing.michell.monitor.protocol.tryDecodeEnvelope
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

  @Test
  fun nullLiveSnapshotClearsThePreviousAnswer() {
    val coordinator = coordinator()
    openLive(coordinator, canSend = true, canSteer = false, live = answeredTurn("live-1", "old answer"))
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "unsent"))
    assertEquals("old answer", coordinator.state.live?.response)
    openLive(coordinator, canSend = true, canSteer = false, live = null)
    assertEquals(null, coordinator.state.live)
    assertEquals("unsent", coordinator.state.draft)
    assertEquals(1, coordinator.state.conversationGeneration)
    val submitted = coordinator()
    openLive(submitted, canSend = true, canSteer = false)
    submitted.onEvent(MonitorEvent.Incoming(submitted.state, envelope(encodeInsertResult("ins", "pasted"))))
    submitted.onEvent(MonitorEvent.Submit(submitted.state))
    openLive(submitted, canSend = true, canSteer = false, live = null)
    assertEquals("", submitted.state.draft)
  }

  @Test
  fun newTurnIdAtLiveIndexDoesNotKeepThePreviousBody() {
    val coordinator = coordinator()
    openLive(coordinator, canSend = true, canSteer = false, live = answeredTurn("old-id", "old body"))
    openLive(coordinator, canSend = true, canSteer = false, live = WireTurn(-2, "new-id", "build", "", "", ""))
    assertEquals("new-id", coordinator.state.live?.id)
    assertEquals("", coordinator.state.live?.response)
    assertTrue(coordinator.state.live?.blocks?.none { it.body == "old body" } ?: true)
  }

  @Test
  fun hostGenerationsDoNotShareHistoryOrImages() {
    val session = FakeSession()
    val coordinator = MonitorCoordinator(session, FixedClock(1_000L), FixedDisplay(true, false))
    coordinator.onEvent(MonitorEvent.HostChanged(coordinator.state, "10.0.0.1", 8765, "client-a"))
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "unsent"))
    val first = WireSnapshot(
      emptyView().copy(canSend = true, signedIn = true),
      listOf(WireTurn(1, "turn-a", "build", "", "secret", "")),
      answeredTurn("old-id", "old answer"),
      "",
      "",
      false,
      emptyList(),
      emptyList(),
      ApprovalNotice(false, "", "", "", "", false)
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("first", first))))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeTurnData(
      "td",
      WireTurn(1, "turn-a", "build", "", "secret", "", prompt = "secret")
    ))))
    coordinator.flush(coordinator.state)
    assertEquals("secret", coordinator.state.history[1]?.prompt)
    coordinator.noteBitmap("1:img")
    assertTrue(coordinator.noteTurnRequest(1))
    coordinator.onEvent(MonitorEvent.HostChanged(coordinator.state, "10.0.0.1", 8765, "client-a"))
    assertEquals("unsent", coordinator.state.draft)
    assertEquals(0, coordinator.state.hostGeneration)
    val changed = coordinator.onEvent(MonitorEvent.HostChanged(coordinator.state, "10.0.0.2", 8765, ""))
    assertEquals(1, coordinator.state.hostGeneration)
    assertEquals("", coordinator.state.draft)
    assertEquals(null, coordinator.state.live)
    assertTrue(coordinator.bitmapKeyEntries.isEmpty())
    assertTrue(coordinator.requestedTurnEntries.isEmpty())
    assertEquals(false, coordinator.state.showTools)
    assertTrue(session.imagesReset > 0)
    assertTrue(changed.orEmpty().any { it == MonitorEffect.ClearCaches })
    val next = WireSnapshot(
      emptyView().copy(canSend = true, signedIn = true),
      listOf(WireTurn(1, "turn-b", "build", "", "other", "")),
      WireTurn(-2, "new-id", "build", "", "", ""),
      "",
      "",
      false,
      emptyList(),
      emptyList(),
      ApprovalNotice(false, "", "", "", "", false)
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("next", next))))
    assertEquals("new-id", coordinator.state.live?.id)
    assertEquals("", coordinator.state.live?.response ?: "")
    assertEquals("turn-b", coordinator.state.turns.firstOrNull()?.id)
    assertFalse(coordinator.state.history.values.any { it.prompt == "secret" })
    assertTrue(coordinator.bitmapKeyEntries.isEmpty())
  }

  @Test
  fun forgetPairingDropsAPendingReducerUpdate() {
    val coordinator = MonitorCoordinator(FakeSession(), FixedClock(1_000L), FixedDisplay(true, false))
    openLive(coordinator, canSend = true, canSteer = false, live = answeredTurn("live-1", "old answer"))
    coordinator.noteBitmap("-2:old")
    assertTrue(coordinator.noteTurnRequest(4))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeTurnData(
      "td",
      WireTurn(4, "stored", "build", "", "old", "", prompt = "pending body")
    ))))
    coordinator.onEvent(MonitorEvent.ForgetPairing(coordinator.state))
    assertEquals(null, coordinator.state.live)
    assertFalse(coordinator.state.history.containsKey(4))
    assertTrue(coordinator.bitmapKeyEntries.isEmpty())
    assertTrue(coordinator.requestedTurnEntries.isEmpty())
    assertEquals(true, coordinator.state.showThinking)
    assertEquals(false, coordinator.state.showTools)
    coordinator.flush(coordinator.state)
    assertEquals(null, coordinator.state.live)
    assertFalse(coordinator.state.history.values.any { it.prompt == "pending body" })
  }

  @Test
  fun lowerRevisionAfterDisconnectReplacesTheDisplayedBody() {
    val coordinator = coordinator()
    openLive(coordinator, canSend = true, canSteer = false, live = WireTurn(-2, "live-1", "build", "", "", ""))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(transcript(100, "old text", -2))))
    coordinator.flush(coordinator.state)
    assertEquals("old text", displayedBody(coordinator.state))
    coordinator.onEvent(MonitorEvent.LinkChanged(
      coordinator.state,
      LinkStatus(LinkPhase.Disconnected, HostClosedBanner)
    ))
    openLive(coordinator, canSend = true, canSteer = false, live = WireTurn(-2, "live-1", "build", "", "", ""))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(transcript(1, "new text", -2))))
    coordinator.flush(coordinator.state)
    assertEquals("new text", displayedBody(coordinator.state))
  }
}

private fun coordinator(): MonitorCoordinator {
  return MonitorCoordinator(FakeSession(), FixedClock(1_000L), FixedDisplay(true, true))
}

private fun openLive(
  coordinator: MonitorCoordinator,
  canSend: Boolean,
  canSteer: Boolean,
  live: WireTurn? = WireTurn(-2, "live", "build", "", "", "")
) {
  val snapshot = WireSnapshot(
    emptyView().copy(canSend = canSend, canSteer = canSteer, signedIn = true),
    emptyList(),
    live,
    "",
    "",
    false,
    emptyList(),
    emptyList(),
    ApprovalNotice(false, "", "", "", "", false)
  )
  coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("live", snapshot))))
}

private fun transcript(revision: Int, body: String, turnIndex: Int): String {
  val block = WireBlock("answer", "b1", "", "", "", body, false, true, 0, emptyList())
  return tryEncodeTranscript("transcript", WireTranscript(turnIndex, revision, "thinking", "working", listOf(block)))
}

private fun displayedBody(state: MonitorUi): String {
  return state.live?.blocks?.joinToString("") { it.body } ?: ""
}

private fun answeredTurn(id: String, body: String): WireTurn {
  val block = WireBlock("answer", "a", "", "", "", body, false, true, 0, emptyList())
  return WireTurn(-2, id, "build", "", "prompt", "", response = body, blocks = listOf(block))
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
  var imagesReset = 0
  override val promptDraft: String get() = stored
  override val hostAddress: String = ""
  override val hostPort: Int = 0
  override val hostClientId: String = ""
  override fun nextCommandId(): String = "c1"
  override fun updateDraft(text: String) { stored = text }
  override fun sendCatalogue(json: String) {}
  override fun resetImages() { imagesReset += 1 }
}

private fun envelope(json: String): computing.michell.monitor.protocol.MonitorMessage {
  val decoded = tryDecodeEnvelope(json)
  assertTrue(decoded.errorText, decoded.ok)
  return decoded.message
}
