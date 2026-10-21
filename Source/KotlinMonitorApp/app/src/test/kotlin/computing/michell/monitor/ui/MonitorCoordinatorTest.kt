package computing.michell.monitor.ui

/* Coordinator seam without AndroidViewModel (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.AcceptedCatalogue
import computing.michell.monitor.connection.CatalogueResult
import computing.michell.monitor.connection.CatalogueStep
import computing.michell.monitor.connection.CatalogueWrite
import computing.michell.monitor.connection.HostClosedBanner
import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.connection.LinkStatus
import computing.michell.monitor.connection.SessionPort
import computing.michell.monitor.connection.beginCatalogue
import computing.michell.monitor.connection.catalogueFromWrite
import computing.michell.monitor.connection.stepCatalogue
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import computing.michell.monitor.protocol.ApprovalNotice
import computing.michell.monitor.protocol.ImageAssembly
import computing.michell.monitor.protocol.ImageData
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.MonitorLimits
import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireSnapshot
import computing.michell.monitor.protocol.WireTranscript
import computing.michell.monitor.protocol.WireImage
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.tryEncodeTranscript
import computing.michell.monitor.protocol.decodeImageGet
import computing.michell.monitor.protocol.decodeText
import computing.michell.monitor.protocol.decodeTurnRequest
import computing.michell.monitor.protocol.encodeEnvelope
import computing.michell.monitor.protocol.encodeError
import computing.michell.monitor.protocol.encodeInsertResult
import computing.michell.monitor.protocol.encodeRejected
import computing.michell.monitor.protocol.encodeSnapshot
import computing.michell.monitor.protocol.encodeTurnData
import computing.michell.monitor.protocol.statusToJson
import computing.michell.monitor.protocol.tryDecodeEnvelope
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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
    assertEquals("pasted", coordinator.state.draft)
    assertEquals("pasted", coordinator.state.pendingPrompt)
    assertEquals("user", coordinator.state.pendingKind)
    assertEquals("c1", coordinator.state.pendingCommandId)
    assertEquals(1, coordinator.state.pendingEpoch)
    assertEquals(listOf("pasted"), sendTexts(sent))
    val written = coordinator.onEvent(MonitorEvent.CommandResult(
      coordinator.state,
      CatalogueResult(coordinator.state.pendingCommandId, 1, CatalogueWrite.Written)
    ))
    assertEquals("", coordinator.state.draft)
    assertEquals("pasted", coordinator.state.pendingPrompt)
    assertEquals(emptyList<String>(), sendTexts(written.orEmpty()))
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

  @Test
  fun failedSendBeforeWriteKeepsTheText() {
    val session = FakeSession()
    session.dropSocket()
    val coordinator = sendingCoordinator(session)
    val submitted = coordinator.onEvent(MonitorEvent.Submit(coordinator.state)).orEmpty()
    assertEquals("keep me", coordinator.state.draft)
    assertEquals("keep me", coordinator.state.pendingPrompt)
    assertTrue(coordinator.state.view.busy)
    drive(session, submitted)
    val settled = settleWrites(coordinator, session)
    assertEquals(0, session.writeAttempts)
    assertTrue(session.writes.isEmpty())
    assertEquals(CatalogueWrite.Failed, session.outcomes.single())
    assertEquals("keep me", coordinator.state.draft)
    assertEquals("", coordinator.state.pendingPrompt)
    assertFalse(coordinator.state.view.busy)
    assertFalse(coordinator.state.view.sending)
    assertTrue(coordinator.state.view.canSend)
    assertEquals(CouldNotSendBanner, coordinator.state.banner)
    assertEquals(emptyList<String>(), sendTexts(settled))
  }

  @Test
  fun failedWriteJsonKeepsTheText() {
    val session = FakeSession()
    session.failWriteJson()
    val coordinator = sendingCoordinator(session)
    drive(session, coordinator.onEvent(MonitorEvent.Submit(coordinator.state)))
    val settled = settleWrites(coordinator, session)
    assertEquals(1, session.writeAttempts)
    assertTrue(session.writes.isEmpty())
    assertEquals(CatalogueWrite.Failed, session.outcomes.single())
    assertEquals("keep me", coordinator.state.draft)
    assertEquals("", coordinator.state.pendingPrompt)
    assertFalse(coordinator.state.view.busy)
    assertTrue(coordinator.state.view.canSend)
    assertEquals(CouldNotSendBanner, coordinator.state.banner)
    assertEquals(emptyList<String>(), sendTexts(settled))
  }

  @Test
  fun writtenSendWithoutAckDoesNotSendAgain() {
    val session = FakeSession()
    val coordinator = sendingCoordinator(session)
    val submitted = coordinator.onEvent(MonitorEvent.Submit(coordinator.state)).orEmpty()
    assertEquals(listOf("keep me"), sendTexts(submitted))
    drive(session, submitted)
    val settled = settleWrites(coordinator, session)
    assertEquals(1, session.writes.size)
    assertEquals(CatalogueWrite.Written, session.outcomes.single())
    assertEquals("", coordinator.state.draft)
    assertEquals("keep me", coordinator.state.pendingPrompt)
    assertEquals("user", coordinator.state.pendingKind)
    assertTrue(coordinator.state.view.busy)
    assertEquals(emptyList<String>(), sendTexts(settled))
    val status = coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeEnvelope(
      MessageKind.Status, "st", statusToJson(emptyView().copy(canSend = true, signedIn = true))
    ))))
    assertEquals("", coordinator.state.draft)
    assertEquals("keep me", coordinator.state.pendingPrompt)
    assertEquals(emptyList<String>(), sendTexts(status.orEmpty()))
    val dropped = coordinator.onEvent(MonitorEvent.LinkChanged(
      coordinator.state,
      LinkStatus(LinkPhase.Disconnected, HostClosedBanner)
    ))
    assertEquals("keep me", coordinator.state.draft)
    assertEquals("", coordinator.state.pendingPrompt)
    assertEquals(HostClosedBanner, coordinator.state.banner)
    assertEquals(emptyList<String>(), sendTexts(dropped.orEmpty()))
    drive(session, dropped)
    session.completeWrites()
    assertEquals(1, session.writes.size)
    assertEquals(1, session.outcomes.size)
  }

  @Test
  fun commandAcceptedOnGenerationOneIsNotWrittenOnGenerationTwo() {
    val session = FakeSession()
    val coordinator = sendingCoordinator(session)
    val submitted = coordinator.onEvent(MonitorEvent.Submit(coordinator.state)).orEmpty()
    drive(session, submitted)
    assertEquals(1, session.linkEpoch)
    assertEquals(listOf(1), session.acceptedEpochs)
    val commandId = coordinator.state.pendingCommandId
    session.moveGeneration()
    assertEquals(2, session.linkEpoch)
    val settled = settleWrites(coordinator, session)
    assertTrue(session.writes.isEmpty())
    assertEquals(0, session.writeAttempts)
    assertEquals(CatalogueWrite.Stale, session.outcomes.single())
    assertEquals(commandId, session.settledIds.single())
    assertEquals("keep me", coordinator.state.draft)
    assertEquals("", coordinator.state.pendingPrompt)
    assertFalse(coordinator.state.view.busy)
    assertEquals(CouldNotSendBanner, coordinator.state.banner)
    assertEquals(emptyList<String>(), sendTexts(settled))
  }

  @Test
  fun disconnectBetweenFetchAndResponseRequestsTheTurnAgain() {
    val coordinator = coordinator()
    val first = snapshotWithStoredTurn(coordinator, 4, "turn-4")
    assertEquals(listOf(4), turnRequests(first))
    assertTrue(coordinator.requestedTurnEntries.contains(4))
    coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Disconnected, HostClosedBanner)))
    assertFalse(coordinator.requestedTurnEntries.contains(4))
    val again = snapshotWithStoredTurn(coordinator, 4, "turn-4")
    assertEquals(listOf(4), turnRequests(again))
  }

  @Test
  fun failedFetchWriteDoesNotStickTheKey() {
    val coordinator = coordinator()
    val first = snapshotWithStoredTurn(coordinator, 4, "turn-4")
    val commandId = envelope(turnSend(first).json).id
    coordinator.onEvent(MonitorEvent.CommandResult(
      coordinator.state,
      CatalogueResult(commandId, 1, CatalogueWrite.Failed)
    ))
    assertFalse(coordinator.requestedTurnEntries.contains(4))
    val again = snapshotWithStoredTurn(coordinator, 4, "turn-4")
    assertEquals(listOf(4), turnRequests(again))
  }

  @Test
  fun completedTurnIsNotRequestedAgainOnTheSameGeneration() {
    val coordinator = coordinator()
    assertEquals(listOf(4), turnRequests(snapshotWithStoredTurn(coordinator, 4, "turn-4")))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeTurnData(
      "td",
      WireTurn(4, "turn-4", "build", "", "preview", "", prompt = "loaded body")
    ))))
    coordinator.flush(coordinator.state)
    assertFalse(coordinator.requestedTurnEntries.contains(4))
    assertEquals(emptyList<Int>(), turnRequests(snapshotWithStoredTurn(coordinator, 4, "turn-4")))
  }

  @Test
  fun visibleTurnsDoNotRequestDistantHistoryImages() {
    val coordinator = coordinator()
    val stored = (0..4).map { index -> WireTurn(index, "turn-$index", "build", "", "preview", "") }
    val snapshot = WireSnapshot(
      emptyView().copy(canSend = true, signedIn = true),
      stored,
      WireTurn(-2, "live", "build", "", "", ""),
      "",
      "",
      false,
      emptyList(),
      emptyList(),
      ApprovalNotice(false, "", "", "", "", false)
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("many", snapshot))))
    for (index in listOf(0, 2, 3, 4)) {
      val image = WireImage("img-$index", "shot", "image/png", 8, 8, "", false)
      coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeTurnData(
        "td-$index",
        WireTurn(index, "turn-$index", "build", "", "preview", "", images = listOf(image))
      ))))
    }
    val flushed = coordinator.flush(coordinator.state).orEmpty()
    assertEquals(emptyList<String>(), imageRequests(flushed))
    val requested = imageRequests(coordinator.noteVisibleTurns(coordinator.state, setOf(3)))
    assertEquals(setOf("img-2", "img-3", "img-4"), requested.toSet())
    assertFalse(requested.contains("img-0"))
  }

  @Test
  fun expiredImageClearsTheInFlightKeyAndANewHostDoesNotShareIt() {
    val coordinator = coordinator()
    coordinator.onEvent(MonitorEvent.HostChanged(coordinator.state, "10.0.0.1", 8765, "client-a"))
    val first = snapshotWithImage(coordinator, "img-1")
    assertEquals(listOf("img-1"), imageRequests(first))
    assertEquals(listOf("0:-2:img-1"), coordinator.inFlightImageKeys.toList())
    assertFalse(coordinator.loadedImageKeys.contains("0:img-1"))
    assertEquals(emptyList<String>(), imageRequests(snapshotWithImage(coordinator, "img-1")))
    val assembly = ImageAssembly()
    val partial = ImageData("img-1", "image/png", 1, 1, 1, 2, 1, "")
    assertNull(assembly.accept(partial, byteArrayOf(1), 0L))
    assembly.accept(ImageData("other", "image/png", 1, 1, 1, 2, 1, ""), byteArrayOf(2), MonitorLimits.ImageAssemblyTtlMs)
    assertTrue(assembly.takeExpired().contains("img-1"))
    coordinator.noteImagesExpired(listOf("img-1"))
    assertTrue(coordinator.inFlightImageKeys.isEmpty())
    assertFalse(coordinator.loadedImageKeys.contains("0:img-1"))
    assertEquals(listOf("img-1"), imageRequests(snapshotWithImage(coordinator, "img-1")))
    coordinator.noteImageFetched("img-1")
    assertEquals(setOf("0:img-1"), coordinator.loadedImageKeys)
    assertEquals(emptyList<String>(), imageRequests(snapshotWithImage(coordinator, "img-1")))
    coordinator.onEvent(MonitorEvent.HostChanged(coordinator.state, "10.0.0.2", 8765, "client-b"))
    assertTrue(coordinator.loadedImageKeys.isEmpty())
    assertEquals(listOf("img-1"), imageRequests(snapshotWithImage(coordinator, "img-1")))
    assertTrue(coordinator.inFlightImageKeys.any { it.startsWith("1:") })
  }

  @Test
  fun historyPrefixDoesNotAcknowledgeAPendingPrompt() {
    val coordinator = coordinator()
    val older = promptTurn(1, "hist", "hello world", "old-user")
    val live = WireTurn(-2, "live", "build", "", "", "")
    rememberTurn(coordinator, older, live)
    assertEquals("hello world", coordinator.state.history[1]?.blocks?.single()?.body)
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "hello"))
    coordinator.onEvent(MonitorEvent.Submit(coordinator.state))
    assertEquals("hello", coordinator.state.pendingPrompt)
    postSnapshot(coordinator, catalogueSnapshot(listOf(older), live))
    assertEquals("hello", coordinator.state.pendingPrompt)
    val prefix = WireTurn(
      -2, "live", "build", "", "hello world", "",
      prompt = "hello world",
      blocks = listOf(userBlock("new-prefix", "hello world"))
    )
    postSnapshot(coordinator, catalogueSnapshot(listOf(older), prefix))
    assertEquals("hello", coordinator.state.pendingPrompt)
  }

  @Test
  fun repeatedPromptWaitsForANewLiveBlock() {
    val coordinator = coordinator()
    val older = promptTurn(1, "hist", "hello", "old-user")
    val live = WireTurn(
      -2, "shown", "build", "", "hello", "",
      prompt = "hello",
      blocks = listOf(userBlock("old-user", "hello"))
    )
    rememberTurn(coordinator, older, live)
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "hello"))
    coordinator.onEvent(MonitorEvent.Submit(coordinator.state))
    postSnapshot(coordinator, catalogueSnapshot(listOf(older), live))
    assertEquals("hello", coordinator.state.pendingPrompt)
    val echoed = WireTurn(
      -2, "live", "build", "", "hello", "",
      prompt = "hello",
      blocks = listOf(userBlock("echo-user", " hello "))
    )
    postSnapshot(coordinator, catalogueSnapshot(listOf(older), echoed))
    assertEquals("", coordinator.state.pendingPrompt)
  }

  @Test
  fun errorAndRejectionDoNotCountAsThePromptShown() {
    val coordinator = coordinator()
    val older = promptTurn(1, "hist", "hello world", "old-user")
    val live = WireTurn(-2, "live", "build", "", "", "")
    rememberTurn(coordinator, older, live)
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "hello"))
    coordinator.onEvent(MonitorEvent.Submit(coordinator.state))
    val commandId = coordinator.state.pendingCommandId
    coordinator.onEvent(MonitorEvent.Incoming(
      coordinator.state,
      envelope(encodeError("err", "command", "hello", commandId))
    ))
    assertEquals("hello", coordinator.state.pendingPrompt)
    coordinator.onEvent(MonitorEvent.Incoming(
      coordinator.state,
      envelope(encodeRejected("rej", "busy", 1, 1))
    ))
    assertEquals("hello", coordinator.state.pendingPrompt)
  }
}

private fun coordinator(): MonitorCoordinator {
  return MonitorCoordinator(FakeSession(), FixedClock(1_000L), FixedDisplay(true, true))
}

private fun userBlock(id: String, body: String, kind: String = "user"): WireBlock {
  return WireBlock(kind, id, "", "", "", body, false, true, 0, emptyList())
}

private fun promptTurn(index: Int, id: String, body: String, blockId: String): WireTurn {
  return WireTurn(index, id, "build", "", body, "", prompt = body, blocks = listOf(userBlock(blockId, body)))
}

private fun catalogueSnapshot(stored: List<WireTurn>, live: WireTurn?): WireSnapshot {
  return WireSnapshot(
    emptyView().copy(canSend = true, signedIn = true),
    stored,
    live,
    "",
    "",
    false,
    emptyList(),
    emptyList(),
    ApprovalNotice(false, "", "", "", "", false)
  )
}

private fun postSnapshot(coordinator: MonitorCoordinator, snapshot: WireSnapshot) {
  coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("snap", snapshot))))
}

private fun rememberTurn(coordinator: MonitorCoordinator, turn: WireTurn, live: WireTurn) {
  coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeTurnData("td", turn))))
  postSnapshot(coordinator, catalogueSnapshot(listOf(turn), live))
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

private fun snapshotWithStoredTurn(coordinator: MonitorCoordinator, index: Int, id: String): List<MonitorEffect> {
  val snapshot = WireSnapshot(
    emptyView().copy(canSend = true, signedIn = true),
    listOf(WireTurn(index, id, "build", "", "preview", "")),
    WireTurn(-2, "live", "build", "", "", ""),
    "",
    "",
    false,
    emptyList(),
    emptyList(),
    ApprovalNotice(false, "", "", "", "", false)
  )
  return coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("snap", snapshot)))).orEmpty()
}

private fun snapshotWithImage(coordinator: MonitorCoordinator, imageId: String): List<MonitorEffect> {
  val image = WireImage(imageId, "shot", "image/png", 8, 8, "", false)
  val live = WireTurn(-2, "live-image", "build", "", "preview", "", images = listOf(image))
  val snapshot = WireSnapshot(
    emptyView().copy(canSend = true, signedIn = true),
    emptyList(),
    live,
    "",
    "",
    false,
    emptyList(),
    emptyList(),
    ApprovalNotice(false, "", "", "", "", false)
  )
  return coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("img", snapshot)))).orEmpty()
}

private fun turnRequests(effects: List<MonitorEffect>): List<Int> {
  return effects.filterIsInstance<MonitorEffect.Send>().mapNotNull { effect ->
    val message = envelope(effect.json)
    if (message.kind != MessageKind.Turn) null else decodeTurnRequest(message.payloadJson)
  }
}

private fun turnSend(effects: List<MonitorEffect>): MonitorEffect.Send {
  val sends = effects.filterIsInstance<MonitorEffect.Send>().filter { envelope(it.json).kind == MessageKind.Turn }
  assertEquals(1, sends.size)
  return sends[0]
}

private fun imageRequests(effects: List<MonitorEffect>): List<String> {
  return effects.filterIsInstance<MonitorEffect.Send>().mapNotNull { effect ->
    val message = envelope(effect.json)
    if (message.kind != MessageKind.ImageGet) null else decodeImageGet(message.payloadJson)?.imageId
  }
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

private fun sendingCoordinator(session: FakeSession): MonitorCoordinator {
  val coordinator = MonitorCoordinator(session, FixedClock(1_000L), FixedDisplay(true, true))
  openLive(coordinator, canSend = true, canSteer = false)
  coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "keep me"))
  return coordinator
}

private fun drive(session: FakeSession, effects: List<MonitorEffect>?) {
  for (effect in effects.orEmpty()) {
    if (effect is MonitorEffect.Send) session.sendCatalogue(effect.json)
    if (effect is MonitorEffect.RememberDraft) session.updateDraft(effect.text)
  }
}

private fun settleWrites(coordinator: MonitorCoordinator, session: FakeSession): List<MonitorEffect> {
  session.completeWrites()
  val effects = mutableListOf<MonitorEffect>()
  for (result in session.takeResults()) {
    effects += coordinator.onEvent(MonitorEvent.CommandResult(coordinator.state, result)).orEmpty()
  }
  return effects
}

private class FakeSession : SessionPort {
  private var stored = ""
  private var generation = 1
  private var openSocket: Any? = Any()
  private var ids = 1
  private val queued = mutableListOf<AcceptedCatalogue>()
  var imagesReset = 0
  var writeJsonFails = false
  var writeAttempts = 0
  val writes = mutableListOf<String>()
  val outcomes = mutableListOf<CatalogueWrite>()
  val acceptedEpochs = mutableListOf<Int>()
  val settledIds = mutableListOf<String>()
  private val results = mutableListOf<CatalogueResult>()

  override val promptDraft: String get() = stored
  override val hostAddress: String = ""
  override val hostPort: Int = 0
  override val hostClientId: String = ""
  override val linkEpoch: Int get() = generation
  override val commandResults: Flow<CatalogueResult> = emptyFlow()
  override fun nextCommandId(): String {
    val id = "c" + ids.toString()
    ids += 1
    return id
  }
  override fun updateDraft(text: String) { stored = text }
  override fun sendCatalogue(json: String) {
    val accepted = beginCatalogue(json, generation, openSocket)
    acceptedEpochs += accepted.linkEpoch
    queued += accepted
  }
  override fun resetImages() { imagesReset += 1 }

  fun dropSocket() {
    openSocket = null
  }

  fun failWriteJson() {
    writeJsonFails = true
  }

  fun moveGeneration() {
    generation += 1
    openSocket = Any()
  }

  fun completeWrites() {
    val batch = queued.toList()
    queued.clear()
    for (accepted in batch) {
      val result = when (val step = stepCatalogue(accepted, generation, openSocket)) {
        is CatalogueStep.Done -> step.result
        is CatalogueStep.Write -> {
          writeAttempts += 1
          val wrote = if (writeJsonFails) {
            false
          } else {
            writes += accepted.json
            true
          }
          catalogueFromWrite(accepted, wrote)
        }
      }
      results += result
      outcomes += result.outcome
      settledIds += result.commandId
    }
  }

  fun takeResults(): List<CatalogueResult> {
    val copy = results.toList()
    results.clear()
    return copy
  }
}

private fun envelope(json: String): computing.michell.monitor.protocol.MonitorMessage {
  val decoded = tryDecodeEnvelope(json)
  assertTrue(decoded.errorText, decoded.ok)
  return decoded.message
}
