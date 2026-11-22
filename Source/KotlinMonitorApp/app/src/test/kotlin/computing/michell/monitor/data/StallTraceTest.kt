package computing.michell.monitor.data

/* Deterministic stall trace for a warm cache several turns behind (c) 2026 Michell Computing.

   No phone is attached, so this drives the publisher's frames through the
   applier, the screen fetch and the board. Durations are the test clock. */

import computing.michell.monitor.connection.CatalogueResult
import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.connection.LinkStatus
import computing.michell.monitor.connection.SessionPort
import computing.michell.monitor.protocol.EmptyPrefixHash
import computing.michell.monitor.protocol.MonitorEvent
import computing.michell.monitor.protocol.PlanMessage
import computing.michell.monitor.protocol.PlanRow
import computing.michell.monitor.protocol.SyncFrame
import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.prefixHash
import computing.michell.monitor.ui.DisplayPreferences
import computing.michell.monitor.ui.MonitorClock
import computing.michell.monitor.ui.MonitorCoordinator
import computing.michell.monitor.ui.MonitorEvent as UiEvent
import computing.michell.monitor.ui.MonitorUi
import computing.michell.monitor.ui.ScreenAssembler
import computing.michell.monitor.ui.applyPlanMessage
import computing.michell.monitor.ui.displayBlocks
import computing.michell.monitor.ui.followAfterMotion
import computing.michell.monitor.ui.settleFinishedTurn
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StallTraceTest {
  @Test
  fun theDisplayedBodyLagsTheDesktopHeadBeforeAnyContentArrives() = runBlocking {
    val clock = TraceClock(1_000L)
    val store = TraceStore()
    store.seedWarm()
    val applier = SyncApplier("host-1", store, clock)
    applier.adoptConnection(1)
    val trace = ArrayList<TraceSample>()

    val announced = applier.offerFrame(head(12, "b-live"), 1)
    trace += sample(clock.now, "head", store, 12L, announced.map { it.toString() }, "none")
    assertTrue(announced.contains(SyncEffect.OpenBehind(true)))
    assertEquals(4L, store.seq)
    assertEquals("Hi", store.body)
    assertEquals(0L, trace.single().ageMs)

    clock.now = 1_100L
    val quiet = applier.offerFrame(SyncFrame.State("status", """{"busy":true,"sending":false,"plan_running":false}"""), 1)
    var ui = applyStateValue(
      MonitorUi(conversationId = "c1", hostEpoch = "stream-a", hostCursor = store.seq, syncHead = 12L),
      "status",
      """{"busy":true,"sending":false,"plan_running":false,"phase":"tool","status_text":"read_file"}"""
    )
    trace += sample(clock.now, "status", store, 12L, quiet.map { it.toString() }, "status")
    assertTrue(ui.statusBusy)
    assertTrue(ui.view.busy)
    assertFalse(ui.view.sending)
    assertEquals("Hi", store.body)
    assertEquals("Hi", shownBody(store))

    clock.now = 1_200L
    applier.offer(MonitorEvent.BlockAppend("c1", "stream-a", 5L, "b-live", 4, " there"))
    clock.now = 1_250L
    val held = applier.tick()
    trace += sample(clock.now, "append", store, 12L, held.map { it.toString() }, "status")
    assertEquals(5L, store.seq)
    assertEquals("Hi", store.body)
    assertEquals("Hi", shownBody(store))
    val fetch = held.filterIsInstance<SyncEffect.FetchBlock>().single()
    assertEquals(2, fetch.offset)
    assertEquals(prefixHash("Hi"), fetch.prefixHash)
    assertEquals(250L, trace.last().ageMs)

    clock.now = 1_300L
    ui = applyPlanMessage(ui, PlanMessage(
      "/work/Documents/Plan.md", "Plan", true,
      listOf(PlanRow(1, 3, "1.1 Reproduce", "", "in progress", true)),
      body = "### 1.1\nStatus: in progress\n", complete = false
    ))
    trace += sample(clock.now, "plan-transition", store, 12L, listOf("plan-running"), "plan")
    assertTrue(ui.planRunning)
    assertEquals("Hi", shownBody(store))

    clock.now = 1_400L
    ui = applyPlanMessage(ui, PlanMessage(
      "/work/Documents/Plan.md", "Plan", false,
      listOf(PlanRow(1, 3, "1.1 Reproduce", "", "complete", false)),
      body = "### 1.1\nStatus: complete\n", complete = true
    ))
    trace += sample(clock.now, "plan-complete", store, 12L, listOf("plan-idle"), "plan")
    assertFalse(ui.planRunning)
    assertEquals("Hi", shownBody(store))

    val following = followAfterMotion(true, userScrolling = true, atEnd = false, programmatic = false)
    val screen = ScreenFetch()
    val older = (0..2).map { index ->
      WireTurn(index, "t$index", "build", "", "old", "", blocks = listOf(
        WireBlock("answer", "b$index", "", "", "", "old", false, true, 0, emptyList(), deferred = true)
      ))
    }
    assertEquals("b-live", (screen.replaceBoard("c1", older, liveTurn(store.body)).single() as FetchGrant.Block).fetch.blockId)
    val scrolled = screen.noteVisible(setOf(0))
    trace += sample(clock.now, "scroll", store, 12L, scrolled.map { it.toString() }, "status")
    assertFalse(following)
    assertEquals("b1", scrolled.filterIsInstance<FetchGrant.Block>().single().fetch.blockId)
    assertEquals("Hi", shownBody(store))

    clock.now = 2_000L
    screen.setConnected(false)
    applier.retireConnection(1)
    applier.adoptConnection(2)
    val retried = screen.setConnected(true)
    trace += sample(clock.now, "reconnect", store, 12L, retried.map { it.toString() }, "reconnect")
    assertEquals("Hi", store.body)
    clock.now = 2_000L + SyncRecoveryBudgetMs - 1
    val recovered = applier.tick()
    assertTrue(recovered.contains(SyncEffect.Reconnect))
    assertTrue(recovered.any { it is SyncEffect.Resume && it.conversationId == "c1" && it.streamId == "stream-a" })
    assertEquals("Hi", shownBody(store))

    clock.now = 3_000L
    val terminal = applier.offerFrame(SyncFrame.State("status", """{"busy":false,"sending":false,"plan_running":false}"""), 2)
    ui = applyStateValue(ui, "status", """{"busy":false,"sending":false,"plan_running":false}""")
    val settled = settleFinishedTurn(ui.view, displayBlocks(liveTurn(store.body)))
    trace += sample(clock.now, "terminal", store, 12L, terminal.map { it.toString() }, "status")
    assertFalse(ui.statusBusy)
    assertFalse(settled.busy)
    assertFalse(settled.sending)
    assertEquals("Hi", store.body)

    assertTrue(store.repair.missingBody)
    val finished = finishFetch(
      store.block, store.repair, store.held, mapOf(2 to "!!"), store.repair.revision, true,
      4, store.repair.requestId, clock.now
    ) as FetchFinish.Applied
    assertEquals("Hi!! there", finished.body)
    store.body = finished.body
    store.block = store.block.copy(body = finished.body, state = "ok")
    trace += sample(clock.now, "fetch", store, 12L, listOf("applied"), "fetch")
    assertEquals("Hi!! there", shownBody(store))
    assertEquals(listOf(5L), finished.dropSeqs)

    assertEquals("head", trace.first().source)
    assertEquals(12L, trace.first().desktopHead)
    assertEquals(4L, trace.first().applied)
    assertEquals("Hi", trace.first().displayed)
    assertTrue(trace.dropLast(1).all { it.displayed == "Hi" })
    assertEquals("fetch", trace.last().source)
  }

  @Test
  fun disconnectClearsBusyWithoutPaintingTheHeldSuffix() {
    val coordinator = MonitorCoordinator(TraceSession(), TraceClock(4_000L), TraceDisplay)
    val cached = liveTurn("Hi").copy(live = false)
    coordinator.showStored(MonitorUi(
      conversationId = "c1",
      hostEpoch = "stream-a",
      hostCursor = 5L,
      syncHead = 12L,
      turns = listOf(cached)
    ), false)
    coordinator.noteSyncedChrome(coordinator.state.copy(view = coordinator.state.view.copy(busy = true, sending = true)))
    coordinator.onEvent(UiEvent.LinkChanged(coordinator.state, LinkStatus(LinkPhase.Disconnected, "", "")))
    assertEquals("Hi", coordinator.state.turns.single().blocks.single().body)
    assertFalse(coordinator.state.view.busy)
    assertFalse(coordinator.state.view.sending)
    assertEquals(5L, coordinator.state.hostCursor)
  }
}

private data class TraceSample(
  val atMs: Long,
  val source: String,
  val conversation: String,
  val stream: String,
  val desktopHead: Long,
  val applied: Long,
  val displayed: String,
  val outstanding: Int,
  val ageMs: Long,
  val busySource: String
)

private fun sample(
  atMs: Long,
  source: String,
  store: TraceStore,
  head: Long,
  effects: List<String>,
  busySource: String
): TraceSample {
  return TraceSample(
    atMs, source, "c1", "stream-a", head, store.seq, store.body,
    effects.count { it.contains("Fetch") || it.contains("Turn") || it.contains("Plan") },
    atMs - 1_000L, busySource
  )
}

private fun shownBody(store: TraceStore): String {
  val board = ScreenAssembler().board("host-1", "c1", store.turns, listOf(store.block), emptyList(), emptyList())
  return board.live?.blocks?.single()?.body ?: ""
}

private fun liveTurn(body: String): WireTurn {
  return WireTurn(3, "t-live", "build", "", body, "", live = true, blocks = listOf(
    WireBlock("answer", "b-live", "", "", "", body, true, true, 0, emptyList(), deferred = true)
  ))
}

private fun head(seq: Long, block: String): SyncFrame.State {
  return SyncFrame.State(
    "head",
    """{"seq":$seq,"conversation_id":"c1","stream_id":"stream-a","open_block":"$block","running":true}"""
  )
}

private class TraceClock(var now: Long) : () -> Long, MonitorClock {
  override fun invoke(): Long = now
  override fun nowMs(): Long = now
}

private class TraceStore : SyncStore {
  var seq = 0L
  var body = ""
  var repair = BlockRepair("host-1", "c1", "b-live", 0L, 0, false, EmptyPrefixHash, false, "", "")
  var held = emptyList<HeldAppend>()
  val turns = listOf(
    TurnRecord("host-1", "c1", "t0", 0, "build", "one", "", "ok", 0, ""),
    TurnRecord("host-1", "c1", "t1", 1, "build", "two", "", "ok", 0, ""),
    TurnRecord("host-1", "c1", "t2", 2, "build", "three", "", "ok", 0, ""),
    TurnRecord("host-1", "c1", "t-live", 3, "build", "four", "", "running", 0, "")
  )
  var block = BlockRecord("host-1", "c1", "t-live", "b-live", 0, "answer", "", "Hi", "running")

  fun seedWarm() {
    seq = 4L
    body = "Hi"
    block = block.copy(body = body)
  }

  override suspend fun cursorOf(hostId: String, conversationId: String): AppliedCursor {
    return AppliedCursor(conversationId, "stream-a", seq)
  }

  override suspend fun apply(hostId: String, events: List<MonitorEvent>, nowMs: Long): SyncApplyResult {
    val reduced = reduceSync(
      hostId, nowMs,
      ConversationRecord("c1", "host-1", "/work", "Title", "stream-a", seq, 0L, false),
      turns, listOf(block), emptyList(), events
    )
    val commit = reduced.commit
    if (commit != null) {
      seq = commit.conversation.seq
      val next = commit.blocks.singleOrNull()
      if (next != null) {
        block = next
        body = next.body
      }
      repair = commit.repairs.singleOrNull() ?: repair
      held = commit.held
    }
    return SyncApplyResult(
      listOfNotNull(reduced.applied),
      listOfNotNull(reduced.gap),
      reduced.fetches
    )
  }
}

private object TraceDisplay : DisplayPreferences {
  override val showThinking: Boolean = true
  override val showTools: Boolean = true
}

private class TraceSession : SessionPort {
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
