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
import computing.michell.monitor.protocol.encodeConversationClosed
import computing.michell.monitor.protocol.encodeError
import computing.michell.monitor.protocol.decodeResume
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
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("snap", snapshot(null).copy(
      view = emptyView().copy(sending = true, busy = true, canSend = false)
    )))))
    coordinator.onEvent(MonitorEvent.DraftEdited(coordinator.state, "too soon"))
    assertNull(coordinator.onEvent(MonitorEvent.Submit(coordinator.state)))
    assertEquals("too soon", coordinator.state.draft)
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
  fun helloAsksForTheOpenScreenNotTheSavedCursor() {
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
    assertEquals("", asked!!.epoch)
    assertEquals(0L, asked.cursor)
    assertEquals("the prompt", coordinator.state.turns.single().blocks.single().body)
  }

  @Test
  fun aLaterPatchKeepsThePromptBesideTheReply() {
    val coordinator = open()
    val prompt = WireBlock("user", "u", "", "", "", "the prompt", false, true, 0, emptyList())
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("snap", snapshot(
      WireTurn(1, "turn-1", "build", "", "the prompt", "", live = true, blocks = listOf(prompt))
    )))))
    val reply = WireBlock("answer", "a", "", "", "", "the reply", false, true, 0, emptyList())
    val delta = WirePatch("epoch", 9, 1, "turn-1", listOf(reply), false, false, false, "", true, false, false, 0)
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodePatch("p", delta))))
    assertEquals(listOf("the prompt", "the reply"), coordinator.state.live?.blocks?.map { block -> block.body })
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
    assertFalse(coordinator.state.catchingUp)
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
    assertFalse(coordinator.state.catchingUp)
    assertEquals(listOf("the prompt", "the answer"), coordinator.state.live?.blocks?.map { block -> block.body })
    val again = encodeSnapshotPage(
      "page-2",
      """{"conversation_id":"conversation-1","stream_id":"stream","seq":118,"turn":{"live":true,"turn_id":"live-1","turn_index":4,"blocks":[{"block_id":"u","kind":"user","title":"","state":"ok","body":"the prompt"}]}}"""
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(again)))
    assertEquals(2, coordinator.state.live?.blocks?.size)
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
    val fetch = effects.filterIsInstance<MonitorEffect.Send>().single()
    assertTrue(fetch.json.contains("block_get"))
    assertTrue(fetch.json.contains("answer"))
    assertEquals("", coordinator.state.live?.blocks?.last()?.body)
    val data = """{"v":2,"id":"bd","type":"block_data","payload":{"conversation_id":"conversation-1","block_id":"answer","offset":0,"text":"the desktop answer","total_bytes":18,"last":true}}"""
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(data)))
    assertEquals("the desktop answer", coordinator.state.live?.blocks?.last()?.body)
    assertFalse(coordinator.state.live?.blocks?.last()?.deferred ?: true)
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
    assertEquals("the desktop part", coordinator.state.live?.blocks?.single()?.body)
    assertTrue(coordinator.state.turns.isEmpty())
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
    assertEquals("the desktop part", coordinator.state.live?.blocks?.last()?.body)
    val older = encodeSnapshotPage(
      "page-2",
      """{"conversation_id":"conversation-1","stream_id":"stream","seq":4,"turn":{"turn_id":"old-turn","turn_index":1,"blocks":[{"block_id":"old","kind":"answer","title":"","state":"ok","body":"filled later"}]}}"""
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(older)))
    assertEquals("the desktop part", coordinator.state.live?.blocks?.last()?.body)
    assertEquals("filled later", coordinator.state.turns.single().blocks.single().body)
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
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeSnapshot("snap", snapshot(null).copy(
      view = emptyView().copy(sending = true, busy = true, canSend = false)
    )))))
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
    val sampled = WirePatch(
      "epoch", 2, 1, "turn-1", emptyList(), true, true, false, "Thinking…",
      false, false, true, 12_000, hasView = true, statusText = "Thinking… 0:12"
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodePatch("p", sampled))))
    assertEquals(8_000L, coordinator.state.activityStartedMs)
    clock.millis = 25_000L
    val zero = sampled.copy(cursor = 3, elapsedMs = 0, statusText = "Thinking…")
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodePatch("p2", zero))))
    assertEquals(8_000L, coordinator.state.activityStartedMs)
    assertEquals("Thinking… 0:17", activityCaption(
      coordinator.state.view, false, "", coordinator.state.activityStartedMs, 25_000L,
      displayBlocks(coordinator.state.live), coordinator.state.live
    ))
    val echoed = WireBlock("user", "u", "", "", "", "go", false, true, 0, emptyList())
    val idle = zero.copy(
      cursor = 4, blocks = listOf(echoed), busy = false, sending = false, canSend = true, canStop = false,
      phase = "Ready", statusText = "Ready"
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodePatch("p3", idle))))
    assertEquals(0L, coordinator.state.activityStartedMs)
  }

  @Test
  fun newConversationFilesTheScreenAndTheNextPageDoesNotKeepIt() {
    val coordinator = open()
    showAnswer(coordinator, "conversation-1", "epoch", "old answer")
    val started = coordinator.onEvent(MonitorEvent.NewConversation(coordinator.state)).orEmpty()
    val filed = started.filterIsInstance<MonitorEffect.FileClosed>().single()
    assertEquals("conversation-1", filed.id)
    assertTrue(filed.document.contains("old answer"))
    assertNull(coordinator.state.live)
    assertFalse(coordinator.acceptsRepository("conversation-1"))
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodePatch("p", patch("should not stick", 5)))))
    assertNull(coordinator.state.live)
    showNote(coordinator, "conversation-2", "epoch-2")
    assertEquals("conversation-2", coordinator.state.conversationId)
    assertEquals(listOf("New conversation started."), coordinator.state.live?.blocks?.map { block -> block.body })
    assertTrue(coordinator.state.turns.isEmpty())
    assertTrue(coordinator.acceptsRepository("conversation-2"))
    assertFalse(coordinator.acceptsRepository("conversation-1"))
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
    assertTrue(filed.document.contains("old answer"))
    assertNull(coordinator.state.live)
    showNote(coordinator, "conversation-2", "epoch-2")
    assertEquals(listOf("New conversation started."), coordinator.state.live?.blocks?.map { block -> block.body })
    assertTrue(coordinator.state.turns.none { turn -> turn.blocks.any { block -> block.body == "old answer" } })
  }

  private fun showAnswer(coordinator: MonitorCoordinator, conversationId: String, epoch: String, body: String) {
    val hello = HelloOkMessage("nonce", "ide", epoch, 4, conversationId, "/work", "Old", "")
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(encodeHelloOk("hello", hello))))
    val answer = encodeSnapshotPage(
      "page-1",
      """{"conversation_id":"$conversationId","stream_id":"$epoch","seq":4,"turn":{"live":true,"turn_id":"turn-1","turn_index":1,"blocks":[{"block_id":"a","kind":"answer","title":"","state":"ok","body":"$body"}]}}"""
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(answer)))
    assertEquals(body, coordinator.state.live?.blocks?.single()?.body)
  }

  private fun showNote(coordinator: MonitorCoordinator, conversationId: String, epoch: String) {
    val note = encodeSnapshotPage(
      "page-2",
      """{"conversation_id":"$conversationId","stream_id":"$epoch","seq":1,"turn":{"live":true,"turn_id":"live","turn_index":-2,"blocks":[{"block_id":"n","kind":"note","title":"Note","state":"ok","body":"New conversation started."}]}}"""
    )
    coordinator.onEvent(MonitorEvent.Incoming(coordinator.state, envelope(note)))
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
