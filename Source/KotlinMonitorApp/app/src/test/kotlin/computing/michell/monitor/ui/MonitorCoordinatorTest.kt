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
import computing.michell.monitor.protocol.ModelChoice
import computing.michell.monitor.protocol.MonitorMessage
import computing.michell.monitor.protocol.PlanRow
import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.WireView
import computing.michell.monitor.protocol.HelloOkMessage
import computing.michell.monitor.protocol.UnsavedEditsReason
import computing.michell.monitor.protocol.decodeSaveFirst
import computing.michell.monitor.protocol.encodeConversationClosed
import computing.michell.monitor.protocol.encodeError
import computing.michell.monitor.protocol.decodeResume
import computing.michell.monitor.protocol.encodeHelloOk
import computing.michell.monitor.protocol.encodeEnvelope
import computing.michell.monitor.protocol.encodeModels
import computing.michell.monitor.protocol.statusToJson
import computing.michell.monitor.protocol.encodePlan
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
  fun anIdleLiveLinkSendsBeforeStatusSetsCanSend() {
    val session = FakeSession()
    val coordinator = open(session)
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "hello from the phone"))
    val effects = coordinator.onEvent(MonitorEvent.Submit(coordinator.state)).orEmpty()
    assertEquals("", coordinator.state.draft)
    assertEquals("hello from the phone", coordinator.state.pendingPrompt)
    assertTrue(coordinator.state.view.canStop)
    assertFalse(coordinator.state.view.canSend)
    val sent = effects.filterIsInstance<MonitorEffect.Send>().single()
    val decoded = tryDecodeEnvelope(sent.json)
    assertTrue(decoded.errorText, decoded.ok)
    assertEquals(MessageKind.Send, decoded.message.kind)
    assertTrue(decoded.message.payloadJson.contains("hello from the phone"))
  }

  @Test
  fun aRunningTurnDoesNotSendWhenCanSendIsFalse() {
    val coordinator = open()
    noteView(coordinator, emptyView().copy(sending = true, busy = true, canSend = false))
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "too soon"))
    assertNull(coordinator.onEvent(MonitorEvent.Submit(coordinator.state)))
    assertEquals("too soon", coordinator.state.draft)
  }

  @Test
  fun replacedConnectionResultsDoNotReportSendFailureOrRestoreThePrompt() {
    val coordinator = open()
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "current prompt"))
    coordinator.onEvent(MonitorEvent.Submit(coordinator.state))
    val before = coordinator.state
    for (result in listOf(
      CatalogueResult("old-command", 0, computing.michell.monitor.connection.CatalogueWrite.Failed),
      CatalogueResult("old-command", 1, computing.michell.monitor.connection.CatalogueWrite.Stale)
    )) {
      coordinator.onEvent(MonitorEvent.CommandResult(coordinator.state, result))
      assertEquals(before.banner, coordinator.state.banner)
      assertEquals(before.draft, coordinator.state.draft)
      assertEquals(before.pendingPrompt, coordinator.state.pendingPrompt)
    }
  }

  @Test
  fun aHostRejectionPutsThePromptBack() {
    val coordinator = open()
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "keep this"))
    coordinator.onEvent(MonitorEvent.Submit(coordinator.state))
    assertEquals("", coordinator.state.draft)
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(
      encodeError("e1", "host_busy", "The desktop control is not available.", "c1")
    )))
    assertEquals("keep this", coordinator.state.draft)
    assertEquals("The desktop control is not available.", coordinator.state.banner)
  }

  @Test
  fun unsavedEditsAskBeforeSendingAgainWithSaveFirst() {
    val coordinator = open()
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "fix the build"))
    coordinator.onEvent(MonitorEvent.Submit(coordinator.state))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(
      encodeError("e1", UnsavedEditsReason, "The desktop has unsaved edits.", "c1")
    )))
    assertEquals("fix the build", coordinator.state.draft)
    assertEquals(SaveQuestionSend, coordinator.state.saveQuestion)
    assertEquals("", coordinator.state.banner)
    val sent = coordinator.answerSaveQuestion(true).filterIsInstance<MonitorEffect.Send>().single()
    val decoded = tryDecodeEnvelope(sent.json)
    assertTrue(decoded.errorText, decoded.ok)
    assertEquals(MessageKind.Send, decoded.message.kind)
    assertTrue(decodeSaveFirst(decoded.message.payloadJson))
    assertTrue(decoded.message.id != "c1")
    assertEquals("", coordinator.state.saveQuestion)
    assertEquals("", coordinator.state.draft)
  }

  @Test
  fun noToUnsavedEditsKeepsThePromptAndSendsNothing() {
    val coordinator = open()
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "keep for later"))
    coordinator.onEvent(MonitorEvent.Submit(coordinator.state))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(
      encodeError("e1", UnsavedEditsReason, "The desktop has unsaved edits.", "c1")
    )))
    assertTrue(coordinator.answerSaveQuestion(false).isEmpty())
    assertEquals("keep for later", coordinator.state.draft)
    assertEquals("", coordinator.state.saveQuestion)
  }

  @Test
  fun unsavedEditsOnRunPlanAskThenRunWithSaveFirst() {
    val coordinator = open()
    val first = tryDecodeEnvelope(coordinator.runPlanCommand(saveFirst = false))
    assertFalse(decodeSaveFirst(first.message.payloadJson))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(
      encodeError("e1", UnsavedEditsReason, "The desktop has unsaved edits.", first.message.id)
    )))
    assertEquals(SaveQuestionRunPlan, coordinator.state.saveQuestion)
    val sent = coordinator.answerSaveQuestion(true).filterIsInstance<MonitorEffect.Send>().single()
    val decoded = tryDecodeEnvelope(sent.json)
    assertEquals(MessageKind.RunPlan, decoded.message.kind)
    assertTrue(decodeSaveFirst(decoded.message.payloadJson))
  }




  @Test
  fun hostChangeDropsThePreviousConversation() {
    val coordinator = open()
    coordinator.restoreOffline(MonitorUi(live = live("one")))
    assertEquals("one", coordinator.state.live?.blocks?.first()?.body)
    coordinator.onEvent(MonitorEvent.HostChanged(coordinator.state, "10.0.0.9", 56122, "other"))
    assertNull(coordinator.state.live)
    assertTrue(coordinator.state.turns.isEmpty())
  }



  @Test
  fun aStoredConversationKeepsThePlanAlreadyOnScreen() {
    val coordinator = open()
    coordinator.noteCachedPlan(
      "Documents/Plan.md",
      "Overview",
      listOf(PlanRow(0, 3, "Cache the plan", "", "not started", true)),
      0
    )
    coordinator.showStored(MonitorUi(conversationId = "conversation-1", turns = listOf(WireTurn(1, "t", "build", "", "Shown", ""))), true)
    assertEquals("Overview", coordinator.state.planTitle)
    assertEquals("Cache the plan", coordinator.state.planRows.single().title)
    assertEquals("Shown", coordinator.state.turns.single().promptPreview)
    assertFalse(coordinator.state.planRunning)
  }

  @Test
  fun aMissingWindowKeepsTheCachedTurnAndStopsSyncing() {
    val coordinator = open()
    val prompt = WireBlock("user", "u", "", "", "", "the prompt", false, true, 0, emptyList())
    coordinator.restoreOffline(MonitorUi(
      conversationId = "conversation-1",
      turns = listOf(WireTurn(1, "turn-1", "build", "", "the prompt", "", blocks = listOf(prompt)))
    ))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeHelloOk(
      "hello", HelloOkMessage("nonce", "ide", "epoch", 4, "conversation-1", "/work", "Chat", "")
    ))))
    assertTrue(coordinator.state.catchingUp)
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(
      encodeError("e1", "no_session", "The Project Assistant window is not open.", "c1")
    )))
    assertFalse(coordinator.state.catchingUp)
    assertEquals("the prompt", coordinator.state.turns.single().blocks.single().body)
    assertEquals("The Project Assistant window is not open.", coordinator.state.banner)
    assertEquals(ChipLive, statusConnectionLabel(ChipLive, coordinator.state.banner))
  }


  @Test
  fun firstHelloRequestsABaselineInsteadOfClaimingTheDesktopHead() {
    val coordinator = open()
    val hello = HelloOkMessage("nonce", "ide", "epoch", 200, "conversation-1", "/work", "Chat", "")
    val effects = coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeHelloOk("hello", hello)))).orEmpty()
    val sent = effects.filterIsInstance<MonitorEffect.Send>().single()
    val asked = decodeResume(tryDecodeEnvelope(sent.json).message.payloadJson)!!
    assertEquals("", asked.epoch)
    assertEquals(0L, asked.cursor)
    assertEquals(0L, coordinator.state.hostCursor)
  }

  @Test
  fun reconnectFollowsTheDesktopConversationInsteadOfTheCachedCursor() {
    val coordinator = open()
    coordinator.restoreOffline(MonitorUi(
      conversationId = "conversation-old", hostEpoch = "stream-old", hostCursor = 118,
      turns = listOf(WireTurn(1, "turn-old", "build", "", "Old conversation", ""))
    ))
    coordinator.noteResumeCursor("conversation-old", "stream-old", 118)
    val hello = HelloOkMessage("nonce", "ide", "stream-new", 200, "conversation-new", "/work", "Current", "")
    val effects = coordinator.onEvent(MonitorEvent.Incoming(
      coordinator.state, envelope(encodeHelloOk("hello", hello))
    )).orEmpty()
    val sent = effects.filterIsInstance<MonitorEffect.Send>().single()
    val payload = tryDecodeEnvelope(sent.json).message.payloadJson
    assertFalse(payload.contains("conversation-old"))
    assertEquals("", decodeResume(payload)!!.epoch)
    assertEquals(0L, decodeResume(payload)!!.cursor)
    assertEquals("conversation-new", coordinator.state.conversationId)
  }

  @Test
  fun helloResumesFromTheStoredCursor() {
    val coordinator = open()
    val prompt = WireBlock("user", "u", "", "", "", "the prompt", false, true, 0, emptyList())
    coordinator.restoreOffline(MonitorUi(
      conversationId = "conversation-1",
      hostEpoch = "epoch",
      hostCursor = 118,
      turns = listOf(WireTurn(1, "turn-1", "build", "", "the prompt", "", blocks = listOf(prompt)))
    ))
    val hello = HelloOkMessage("nonce", "ide", "epoch", 200, "conversation-1", "/work", "Chat", "")
    val effects = coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeHelloOk("hello", hello)))).orEmpty()
    val sent = effects.filterIsInstance<MonitorEffect.Send>().single()
    val asked = decodeResume(tryDecodeEnvelope(sent.json).message.payloadJson)
    assertEquals("epoch", asked!!.epoch)
    assertEquals(118L, asked.cursor)
    assertEquals("the prompt", coordinator.state.turns.single().blocks.single().body)
  }


  @Test
  fun anEmptyOutlineFinishesSync() {
    val coordinator = open()
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeHelloOk(
      "hello", HelloOkMessage("nonce", "ide", "epoch", 0, "conversation-2", "/work", "New", "")
    ))))
    assertTrue(coordinator.state.catchingUp)
    val outline = encodeSnapshotPage(
      "page-0",
      """{"conversation_id":"conversation-2","stream_id":"epoch","seq":0,"point_id":"","turns":[]}"""
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(outline)))
    assertTrue(coordinator.state.catchingUp)
    assertTrue(coordinator.state.turns.isEmpty())
    assertNull(coordinator.state.live)
    assertEquals("conversation-2", coordinator.state.conversationId)
    assertTrue(coordinator.acceptsRepository("conversation-2"))
  }

  @Test
  fun theCurrentTurnArrivesWholeAndACachedTurnIsNotReplayed() {
    val coordinator = open()
    val hello = HelloOkMessage("nonce", "ide", "epoch", 118, "conversation-1", "/work", "Chat", "")
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeHelloOk("hello", hello))))
    assertTrue(coordinator.state.catchingUp)
    val outline = encodeSnapshotPage(
      "page-0",
      """{"conversation_id":"conversation-1","stream_id":"stream","seq":118,"turns":[{"turn_index":1,"turn_id":"old","mode":"build","prompt_preview":"old","created_at":"","duration_ms":0}]}"""
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(outline)))
    assertTrue(coordinator.state.turns.isEmpty())
    assertNull(coordinator.state.live)
    val current = encodeSnapshotPage(
      "page-1",
      """{"conversation_id":"conversation-1","stream_id":"stream","seq":118,"turn":{"live":true,"turn_id":"live-1","turn_index":4,"blocks":[{"block_id":"u","kind":"user","title":"","state":"ok","body":"the prompt"},{"block_id":"a","kind":"answer","title":"","state":"ok","body":"the answer"}]}}"""
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(current)))
    assertTrue(coordinator.state.catchingUp)
    assertNull(coordinator.state.live)
    val again = encodeSnapshotPage(
      "page-2",
      """{"conversation_id":"conversation-1","stream_id":"stream","seq":118,"turn":{"live":true,"turn_id":"live-1","turn_index":4,"blocks":[{"block_id":"u","kind":"user","title":"","state":"ok","body":"the prompt"}]}}"""
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(again)))
    assertNull(coordinator.state.live)
    val moved = encodePlan("plan-2", "Documents/Other.md", "Other", false, emptyList())
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(moved)))
    assertEquals("Documents/Other.md", coordinator.state.planPath)
    assertEquals("Other", coordinator.state.planTitle)
  }

  @Test
  fun aDeferredAnswerIsFetchedAndShown() {
    val coordinator = open()
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeHelloOk(
      "hello", HelloOkMessage("nonce", "ide", "epoch", 1, "conversation-1", "/work", "Chat", "")
    ))))
    val page = encodeSnapshotPage(
      "page-1",
      """{"conversation_id":"conversation-1","stream_id":"stream","seq":8,"turn":{"live":true,"turn_id":"live-1","turn_index":1,"blocks":[{"block_id":"think","kind":"thinking","title":"Thinking","state":"ok","body":"short"},{"block_id":"answer","kind":"answer","title":"","state":"ok","body":"","deferred":true}]}}"""
    )
    val effects = coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(page))).orEmpty()
    assertTrue(effects.none { effect -> effect is MonitorEffect.Send && effect.json.contains("block_get") })
    assertNull(coordinator.state.live)
    val data = """{"v":3,"id":"bd","type":"block_data","payload":{"conversation_id":"conversation-1","block_id":"answer","offset":0,"text":"the desktop answer","total_bytes":18,"last":true}}"""
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(data)))
    assertNull(coordinator.state.live)
  }

  @Test
  fun aDifferentDesktopConversationDoesNotKeepTheCachedSection() {
    val coordinator = open()
    coordinator.restoreOffline(MonitorUi(
      conversationId = "old",
      turns = listOf(WireTurn(1, "old-turn", "build", "", "old section", "", blocks = listOf(
        WireBlock("answer", "a", "", "", "", "old section", false, true, 0, emptyList())
      )))
    ))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeHelloOk(
      "hello", HelloOkMessage("nonce", "ide", "epoch", 9, "conversation-1", "/work", "Chat", "")
    ))))
    assertEquals("old section", coordinator.state.turns.single().blocks.single().body)
    val point = encodeSnapshotPage(
      "page-1",
      """{"conversation_id":"conversation-1","stream_id":"stream","seq":9,"point":true,"point_end":true,"turn":{"live":true,"turn_id":"live-1","turn_index":2,"blocks":[{"block_id":"a","kind":"answer","title":"","state":"ok","body":"the desktop part"}]}}"""
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(point)))
    assertNull(coordinator.state.live)
    assertEquals("old section", coordinator.state.turns.single().blocks.single().body)
  }

  @Test
  fun theCacheStaysUntilTheDesktopPointThenOlderPagesFillBehindIt() {
    val coordinator = open()
    coordinator.restoreOffline(MonitorUi(
      conversationId = "conversation-1",
      planTitle = "Cached plan",
      turns = listOf(WireTurn(1, "old-turn", "build", "", "cached section", "", blocks = listOf(
        WireBlock("answer", "old", "", "", "", "cached section", false, true, 0, emptyList())
      )))
    ))
    val outline = encodeSnapshotPage(
      "page-0",
      """{"conversation_id":"conversation-1","stream_id":"stream","seq":4,"point_id":"live-1","turns":[{"turn_index":1,"turn_id":"old-turn","mode":"build","prompt_preview":"cached section","created_at":"","duration_ms":0},{"turn_index":2,"turn_id":"live-1","mode":"build","prompt_preview":"now","created_at":"","duration_ms":0}]}"""
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(outline)))
    assertEquals("cached section", coordinator.state.turns.single().blocks.single().body)
    assertEquals("Cached plan", coordinator.state.planTitle)
    val point = encodeSnapshotPage(
      "page-1",
      """{"conversation_id":"conversation-1","stream_id":"stream","seq":4,"point":true,"point_end":true,"turn":{"live":true,"turn_id":"live-1","turn_index":2,"blocks":[{"block_id":"u","kind":"user","title":"","state":"ok","body":"the prompt"},{"block_id":"a","kind":"answer","title":"","state":"ok","body":"the desktop part"}]}}"""
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(point)))
    assertNull(coordinator.state.live)
    val older = encodeSnapshotPage(
      "page-2",
      """{"conversation_id":"conversation-1","stream_id":"stream","seq":4,"turn":{"turn_id":"old-turn","turn_index":1,"blocks":[{"block_id":"old","kind":"answer","title":"","state":"ok","body":"filled later"}]}}"""
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(older)))
    assertNull(coordinator.state.live)
    assertEquals("cached section", coordinator.state.turns.single().blocks.single().body)
  }

  @Test
  fun aPlanFrameWithNoEffectStillReachesTheScreen() {
    val coordinator = open()
    val waiting = PlanRow(0, 3, "Check the first show", "", "not started", true)
    val first = coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(
      encodePlan("plan-1", "Documents/Plan.md", "Overview", false, listOf(waiting))
    ))).orEmpty()
    assertTrue(first.isEmpty())
    assertTrue(incomingCopiesScreen(first))
    val started = waiting.copy(status = "in progress")
    val next = coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(
      encodePlan("plan-2", "Documents/Plan.md", "Overview", true, listOf(started))
    ))).orEmpty()
    assertTrue(next.isEmpty())
    assertTrue(incomingCopiesScreen(next))
    assertEquals("in progress", coordinator.state.planRows.single().status)
    assertTrue(coordinator.state.planRunning)
    assertFalse(incomingCopiesScreen(listOf(MonitorEffect.DecodeImage(envelope(encodePlan("img", "", "", false, emptyList()))))))
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

  @Test
  fun aPromptDuringSyncWaitsUntilTheLinkIsLive() {
    val coordinator = open()
    showAnswer(coordinator, "conversation-1", "epoch", "old answer")
    coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Disconnected, ReconnectingBanner, "")))
    coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Connecting, "", "")))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeHelloOk(
      "hello-2", HelloOkMessage("nonce", "ide", "epoch", 4, "conversation-1", "/work", "Old", "")
    ))))
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "queued while syncing"))
    val held = coordinator.onEvent(MonitorEvent.Submit(coordinator.state)).orEmpty()
    assertTrue(held.none { effect -> effect is MonitorEffect.Send })
    assertEquals("", coordinator.state.draft)
    assertEquals("queued while syncing", coordinator.state.pendingPrompt)
    assertEquals("old answer", coordinator.state.live?.blocks?.single()?.body)
    val stillDown = coordinator.onEvent(MonitorEvent.LinkChanged(
      coordinator.state, LinkStatus(LinkPhase.Connecting, "", "")
    )).orEmpty()
    assertTrue(stillDown.none { effect -> effect is MonitorEffect.Send })
    val flushed = coordinator.onEvent(MonitorEvent.LinkChanged(
      coordinator.state, LinkStatus(LinkPhase.Live, "", "")
    )).orEmpty()
    val sent = flushed.filterIsInstance<MonitorEffect.Send>().single()
    assertTrue(sent.json.contains("queued while syncing"))
    assertEquals("queued while syncing", coordinator.state.pendingPrompt)
  }

  @Test
  fun aLiveSyncStillSendsAtOnce() {
    val coordinator = open()
    coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Live, "", "")))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeHelloOk(
      "hello", HelloOkMessage("nonce", "ide", "epoch", 4, "conversation-1", "/work", "Old", "")
    ))))
    assertTrue(coordinator.state.catchingUp)
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "send now"))
    val effects = coordinator.onEvent(MonitorEvent.Submit(coordinator.state)).orEmpty()
    assertTrue(effects.filterIsInstance<MonitorEffect.Send>().any { effect -> effect.json.contains("send now") })
  }

  @Test
  fun newDuringSyncKeepsTheScreenUntilTheLinkIsLive() {
    val coordinator = open()
    showAnswer(coordinator, "conversation-1", "epoch", "old answer")
    coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Disconnected, ReconnectingBanner, "")))
    coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Connecting, "", "")))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeHelloOk(
      "hello-2", HelloOkMessage("nonce", "ide", "epoch", 4, "conversation-1", "/work", "Old", "")
    ))))
    val held = coordinator.onEvent(MonitorEvent.NewConversation(coordinator.state)).orEmpty()
    assertTrue(held.none { effect -> effect is MonitorEffect.Send })
    assertEquals("old answer", coordinator.state.live?.blocks?.single()?.body)
    val flushed = coordinator.onEvent(MonitorEvent.LinkChanged(
      coordinator.state, LinkStatus(LinkPhase.Live, "", "")
    )).orEmpty()
    assertTrue(flushed.filterIsInstance<MonitorEffect.Send>().any { effect -> effect.json.contains("new_conversation") })
    assertNull(coordinator.state.live)
  }

  @Test
  fun offlineWithoutSyncDoesNotQueueAPrompt() {
    val coordinator = open()
    coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Disconnected, ReconnectingBanner, "")))
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "still here"))
    assertNull(coordinator.onEvent(MonitorEvent.Submit(coordinator.state)))
    assertEquals("still here", coordinator.state.draft)
  }

  @Test
  fun aRunningTurnDuringSyncDoesNotQueue() {
    val coordinator = open()
    coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Live, "", "")))
    noteView(coordinator, emptyView().copy(sending = true, busy = true, canSend = false))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeHelloOk(
      "hello", HelloOkMessage("nonce", "ide", "epoch", 4, "conversation-1", "/work", "Old", "")
    ))))
    assertTrue(coordinator.state.catchingUp)
    coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Connecting, "", "")))
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "too soon"))
    assertNull(coordinator.onEvent(MonitorEvent.Submit(coordinator.state)))
    assertEquals("too soon", coordinator.state.draft)
  }

  @Test
  fun aRunningTurnStartsTheStatusClockOnce() {
    val clock = MovableClock(10_000L)
    val coordinator = MonitorCoordinator(FakeSession(), clock, FixedDisplay(true, true))
    coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Live, "", "")))
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "go"))
    coordinator.onEvent(MonitorEvent.Submit(coordinator.state))
    assertEquals(10_000L, coordinator.state.activityStartedMs)
    assertEquals("Waiting… 0:05", activityCaption(
      coordinator.state.view, true, "user", coordinator.state.activityStartedMs, 15_000L,
      displayBlocks(coordinator.state.live), coordinator.state.live
    ))
    clock.millis = 20_000L
    noteView(coordinator, emptyView().copy(
      busy = true, sending = true, canStop = true, canSend = false, elapsedMs = 12_000, statusText = "Thinking… 0:12"
    ))
    assertEquals(8_000L, coordinator.state.activityStartedMs)
    clock.millis = 25_000L
    noteView(coordinator, emptyView().copy(
      busy = true, sending = true, canStop = true, canSend = false, elapsedMs = 0,
      phase = "Thinking…", statusText = "Thinking…"
    ))
    assertEquals(8_000L, coordinator.state.activityStartedMs)
    assertEquals("Thinking… 0:17", activityCaption(
      coordinator.state.view, false, "", coordinator.state.activityStartedMs, 25_000L,
      displayBlocks(coordinator.state.live), coordinator.state.live
    ))
    noteView(coordinator, emptyView().copy(
      busy = false, sending = false, canSend = true, canStop = false, phase = "Ready", statusText = "Ready"
    ))
    assertEquals(8_000L, coordinator.state.activityStartedMs)
  }

  @Test
  fun aFinishedTurnReturnsToSendAndKeepsTheModel() {
    val coordinator = open()
    coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Live, "", "")))
    noteView(coordinator, emptyView().copy(
      busy = true, sending = true, canSteer = true, canSend = false, canStop = true,
      signedIn = true, model = "grok-4", statusText = "Thinking… 0:04", elapsedMs = 4_000
    ))
    assertEquals("Steer", actionCaption(coordinator.state.view))
    assertEquals("grok-4", coordinator.state.view.model)
    noteView(coordinator, emptyView().copy(
      busy = false, sending = false, canSteer = false, canSend = true, canStop = false,
      signedIn = true, model = "", statusText = "Thinking… 0:04"
    ))
    assertEquals("Send", actionCaption(coordinator.state.view))
    assertFalse(coordinator.state.view.canSteer)
    assertTrue(coordinator.state.view.canSend)
    assertEquals("grok-4", coordinator.state.view.model)
    val status = encodeEnvelope(MessageKind.Status, "status-idle", statusToJson(emptyView().copy(
      canSend = true, canSteer = false, signedIn = true, model = "", statusText = "Ready"
    )))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(status)))
    assertEquals("Send", actionCaption(coordinator.state.view))
    assertEquals("grok-4", coordinator.state.view.model)
    assertEquals("Ready", coordinator.state.view.statusText)
  }

  @Test
  fun aModelsFrameFillsTheStatusBarWhenTheViewModelIsEmpty() {
    val coordinator = open()
    val choices = listOf(ModelChoice("grok-4", "grok-4"))
    val frame = encodeModels("models", "grok-4", "grok", "", choices)
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(frame)))
    assertEquals("grok-4", coordinator.state.view.model)
    assertEquals("grok-4", runtimeCaption(coordinator.state.view.model, coordinator.state.modelChoices))
    val blank = encodeEnvelope(MessageKind.Status, "status-blank", statusToJson(emptyView().copy(
      canSend = true, signedIn = false, model = ""
    )))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(blank)))
    assertEquals("grok-4", coordinator.state.view.model)
    assertEquals("grok-4", runtimeCaption(coordinator.state.view))
  }




  @Test
  fun closingAConversationReplacesItInsteadOfAppendingTheNote() {
    val coordinator = open()
    showAnswer(coordinator, "conversation-1", "epoch", "old answer")
    val closed = coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(
      encodeConversationClosed("closed", "epoch", 4, "conversation-1", "Old")
    ))).orEmpty()
    val filed = closed.filterIsInstance<MonitorEffect.FileClosed>().single()
    assertEquals("conversation-1", filed.id)
    assertTrue(filed.document.contains("conversation-1"))
    assertNull(coordinator.state.live)
    showNote(coordinator, "conversation-2", "epoch-2")
    assertEquals(listOf("New conversation started."), coordinator.state.live?.blocks?.map { block -> block.body })
    assertTrue(coordinator.state.turns.none { turn -> turn.blocks.any { block -> block.body == "old answer" } })
  }

  @Test
  fun aLaterDesktopTurnReplacesTheEmptyCatchup() {
    val coordinator = open()
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeHelloOk("hello",
      HelloOkMessage("nonce", "ide", "epoch", 1, "conversation-1", "/work", "Open", "")))))
    val emptyOutline = encodeSnapshotPage(
      "empty",
      """{"conversation_id":"conversation-1","stream_id":"epoch","seq":1,"point_id":"","turns":[]}"""
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(emptyOutline)))
    val emptyPoint = encodeSnapshotPage(
      "empty-point",
      """{"point":true,"point_end":true,"conversation_id":"conversation-1","stream_id":"epoch","seq":1,"turn":{"live":true,"turn_id":"live","turn_index":-2,"blocks":[]}}"""
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(emptyPoint)))
    val real = encodeSnapshotPage(
      "real",
      """{"point":true,"point_end":true,"conversation_id":"conversation-1","stream_id":"epoch","seq":2,"turn":{"live":true,"turn_id":"turn-1","turn_index":0,"blocks":[{"block_id":"a","kind":"answer","title":"","state":"ok","body":"desktop answer"}]}}"""
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(real)))
    assertNull(coordinator.state.live)
    assertTrue(coordinator.state.turns.isEmpty())
  }

  private fun showAnswer(coordinator: MonitorCoordinator, conversationId: String, epoch: String, body: String) {
    val live = WireTurn(1, "turn-1", "build", "", body, "", live = true, blocks = listOf(
      WireBlock("answer", "a", "", "", "", body, false, true, 0, emptyList())
    ))
    coordinator.restoreOffline(MonitorUi(conversationId = conversationId, hostEpoch = epoch, hostCursor = 4, live = live))
    coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Live, "", "")))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeHelloOk(
      "hello", HelloOkMessage("nonce", "ide", epoch, 4, conversationId, "/work", "Old", "")
    ))))
    assertEquals(body, coordinator.state.live?.blocks?.single()?.body)
  }

  private fun showNote(coordinator: MonitorCoordinator, conversationId: String, epoch: String) {
    val note = WireTurn(-2, "live", "build", "", "New conversation started.", "", live = true, blocks = listOf(
      WireBlock("note", "n", "Note", "", "", "New conversation started.", false, true, 0, emptyList())
    ))
    coordinator.restoreOffline(MonitorUi(conversationId = conversationId, hostEpoch = epoch, live = note))
  }

  private fun noteView(coordinator: MonitorCoordinator, view: WireView) {
    val json = encodeEnvelope(MessageKind.Status, "status", computing.michell.monitor.protocol.statusToJson(view))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(json)))
  }

  @Test
  fun anEmptyHelloKeepsAskingUntilTheOpenTurnArrives() {
    val clock = MovableClock(1_000L)
    val coordinator = MonitorCoordinator(FakeSession(), clock, FixedDisplay(true, true))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeHelloOk(
      "hello", HelloOkMessage("nonce", "ide", "epoch", 0, "conversation-1", "/work", "", "")
    ))))
    val first = coordinator.flush(coordinator.state).orEmpty().filterIsInstance<MonitorEffect.Send>()
    assertEquals(1, first.size)
    assertTrue(first.single().json.contains("resume"))
    assertNull(coordinator.flush(coordinator.state))
    clock.millis += 2_000L
    assertEquals(1, coordinator.flush(coordinator.state).orEmpty().filterIsInstance<MonitorEffect.Send>().size)
    val point = encodeSnapshotPage(
      "page-1",
      """{"point":true,"point_end":true,"conversation_id":"conversation-1","stream_id":"epoch","seq":1,"turn":{"live":true,"turn_id":"live-1","turn_index":1,"blocks":[{"block_id":"u","kind":"user","title":"","state":"ok","body":"the prompt"}]}}"""
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(point)))
    assertNull(coordinator.state.live)
    clock.millis += 5_000L
    assertEquals(1, coordinator.flush(coordinator.state).orEmpty().filterIsInstance<MonitorEffect.Send>().size)
  }

  @Test
  fun aPromptSentOfflineShowsAtOnceAndGoesWhenTheLinkIsBack() {
    val coordinator = holdingOffline("while offline")
    assertEquals("while offline", coordinator.state.pendingPrompt)
    assertEquals("", coordinator.state.draft)
    assertTrue(coordinator.state.view.busy)
    assertTrue(coordinator.state.view.canStop)
    // Still connecting: nothing goes yet.
    val connecting = coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Connecting, "", ""))).orEmpty()
    assertTrue(connecting.filterIsInstance<MonitorEffect.Send>().isEmpty())
    assertTrue(coordinator.state.sendWhileOffline)
    hello(coordinator, "conversation-1")
    val live = coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Live, "", ""))).orEmpty()
    val sent = live.filterIsInstance<MonitorEffect.Send>().single()
    assertTrue(sent.json.contains("while offline"))
    assertFalse(coordinator.state.sendWhileOffline)
    assertEquals("while offline", coordinator.state.pendingPrompt)
  }

  @Test
  fun aHeldPromptComesBackWhenTheDesktopOpenedAnotherConversation() {
    val coordinator = holdingOffline("meant for the first chat")
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "typed since"))
    val returned = hello(coordinator, "conversation-2")
    assertEquals("meant for the first chat\ntyped since", coordinator.state.draft)
    assertEquals("", coordinator.state.pendingPrompt)
    assertEquals(HeldPromptMovedBanner, coordinator.state.banner)
    assertEquals("meant for the first chat\ntyped since", returned.filterIsInstance<MonitorEffect.RememberDraft>().single().text)
    val live = coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Live, "", ""))).orEmpty()
    assertTrue(live.none { effect -> effect is MonitorEffect.Send && effect.json.contains("meant for the first chat") })
  }

  @Test
  fun stopTakesBackAPromptThatHasNotLeftThePhone() {
    val coordinator = holdingOffline("never mind")
    val returned = coordinator.cancelHeld().orEmpty()
    assertEquals("never mind", coordinator.state.draft)
    assertEquals("", coordinator.state.pendingPrompt)
    assertFalse(coordinator.state.view.busy)
    assertEquals("never mind", returned.filterIsInstance<MonitorEffect.RememberDraft>().single().text)
    assertNull(coordinator.cancelHeld())
    hello(coordinator, "conversation-1")
    val live = coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Live, "", ""))).orEmpty()
    assertTrue(live.filterIsInstance<MonitorEffect.Send>().none { effect -> effect.json.contains("never mind") })
  }

  @Test
  fun aPausedLinkPutsAHeldPromptBackInTheBox() {
    val coordinator = holdingOffline("waiting")
    coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Paused, "Host closed", "disabled")))
    assertEquals("waiting", coordinator.state.draft)
    assertEquals("", coordinator.state.pendingPrompt)
    assertFalse(coordinator.state.sendWhileOffline)
  }

  @Test
  fun aLinkThatWillNotComeBackKeepsSendOff() {
    val session = FakeSession()
    val coordinator = open(session)
    showAnswer(coordinator, "conversation-1", "epoch", "earlier answer")
    coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Disconnected, ReconnectingBanner, "")))
    assertFalse(coordinator.state.sendWhileOffline)
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "stays here"))
    assertNull(coordinator.onEvent(MonitorEvent.Submit(coordinator.state)))
    assertEquals("stays here", coordinator.state.draft)
    assertEquals("", coordinator.state.pendingPrompt)
  }

  /** A live chat, then a dropped link that will come back, then a prompt sent into that gap. */
  private fun holdingOffline(text: String): MonitorCoordinator {
    val session = FakeSession()
    session.canReconnect = true
    val coordinator = open(session)
    showAnswer(coordinator, "conversation-1", "epoch", "earlier answer")
    coordinator.onEvent(MonitorEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Disconnected, ReconnectingBanner, "")))
    assertTrue(coordinator.state.sendWhileOffline)
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, text))
    val effects = coordinator.onEvent(MonitorEvent.Submit(coordinator.state))
    assertTrue(effects != null)
    assertTrue(effects.orEmpty().filterIsInstance<MonitorEffect.Send>().isEmpty())
    return coordinator
  }

  private fun hello(coordinator: MonitorCoordinator, conversationId: String): List<MonitorEffect> {
    return coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeHelloOk(
      "hello", HelloOkMessage("nonce", "ide", "epoch", 4, conversationId, "/work", "Old", "")
    )))).orEmpty()
  }

  private fun open(session: FakeSession = FakeSession()): MonitorCoordinator {
    return MonitorCoordinator(session, FixedClock(1_000L), FixedDisplay(true, true))
  }
}


private fun live(body: String): WireTurn {
  return WireTurn(1, "turn-1", "build", "", body, "", live = true, blocks = listOf(WireBlock("answer", "b1", "", "", "", body, false, true, 0, emptyList())))
}


private fun envelope(json: String): MonitorMessage {
  val decoded = tryDecodeEnvelope(json)
  assertTrue(decoded.errorText, decoded.ok)
  return decoded.message
}

private class FixedClock(private val millis: Long) : MonitorClock {
  override fun nowMs(): Long = millis
}

private class MovableClock(var millis: Long) : MonitorClock {
  override fun nowMs(): Long = millis
}

private class FixedDisplay(private val thinking: Boolean, private val tools: Boolean) : DisplayPreferences {
  override val showThinking: Boolean get() = thinking
  override val showTools: Boolean get() = tools
}

private class FakeSession : SessionPort {
  private var draft = ""
  private var ids = 1
  var canReconnect = false
  override val reconnectable: Boolean get() = canReconnect
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
