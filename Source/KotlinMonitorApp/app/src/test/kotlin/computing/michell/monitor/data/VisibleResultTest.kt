package computing.michell.monitor.data

/* Failure cases and the visible result, without a phone (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.protocol.MonitorEvent
import computing.michell.monitor.protocol.SyncFrame
import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.prefixHash
import computing.michell.monitor.ui.ConversationRow
import computing.michell.monitor.ui.readingDemand
import computing.michell.monitor.ui.retainedAnchor
import computing.michell.monitor.ui.sendActionEnabled
import computing.michell.monitor.ui.settleFinishedTurn
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VisibleResultTest {
  @Test
  fun stalledBulkStillPaintsTheHeadAndDoesNotAskForOlderBodies() = runBlocking {
    val store = ResultStore()
    val clock = ResultClock(1_000L)
    val applier = SyncApplier("host-1", store, clock)
    val fetch = ScreenFetch()
    applier.adoptConnection(1)
    val older = (0..3).map { index -> resultTurn(index, "old-$index", deferred = true, running = false) }
    val live = resultTurn(4, "Hi", deferred = true, running = true)
    val opened = fetch.replaceBoard("c1", older, live)
    assertEquals(listOf("b-4"), opened.filterIsInstance<FetchGrant.Block>().map { grant -> grant.fetch.blockId })
    val headDemand = fetch.noteReading(true, setOf(0, 1, 2, 3, 4))
    assertTrue(headDemand.isEmpty())
    assertFalse(fetch.isFlying("b-0"))
    clock.now = 1_400L
    applier.offerFrame(SyncFrame.BlockData("c1", "b-live", "bulk", 1L, true, 0, "old", 8, false), 1)
    val paintedAt = clock.now
    applier.offerFrame(SyncFrame.State("head", headJson(12, "Hello tail", true)), 1)
    val latency = clock.now - paintedAt
    assertEquals(0L, latency)
    assertEquals("Hello tail", store.body)
    assertEquals(4L, store.seq)
    assertTrue(store.busy)
    val terminal = applyStateValue(store.ui, "status", """{"sending":false,"plan_running":false,"can_send":true}""")
    val shown = settleFinishedTurn(terminal.view, listOf(resultBlock("b-live", "Hello tail", running = true)))
    assertFalse(shown.busy)
    assertTrue(shown.canSend)
    assertFalse(sendActionEnabled(terminal.view.copy(busy = true, canSend = true, canSteer = false), false, LinkPhase.Live, false))
    applier.offerFrame(SyncFrame.State("head", headJson(9, "older", true)), 1)
    applier.offerFrame(SyncFrame.State("head", headJson(12, "Hello tail", true)), 1)
    applier.offerFrame(SyncFrame.BlockData("c1", "b-live", "bulk", 1L, true, 0, "old tail", 8, true), 1)
    assertEquals("Hello tail", store.body)
    assertEquals(4L, store.seq)
    assertEquals(0, headDemand.size)
  }

  @Test
  fun reconnectPlanResetAndConversationSwitchKeepTheVisibleResult() = runBlocking {
    val store = ResultStore()
    val clock = ResultClock(2_000L)
    val applier = SyncApplier("host-1", store, clock)
    val fetch = ScreenFetch()
    applier.adoptConnection(1)
    val plan = applyStateValue(store.ui, "status", """{"sending":false,"plan_running":true,"can_send":true,"can_steer":false}""")
    assertTrue(plan.view.busy)
    assertFalse(plan.view.canSend)
    fetch.replaceBoard("c1", listOf(resultTurn(0, "old", true, false)), resultTurn(1, "live", true, true))
    fetch.noteReading(false, setOf(0))
    assertTrue(fetch.isFlying("b-0"))
    applier.retireConnection(1)
    applier.adoptConnection(2)
    fetch.invalidate()
    assertFalse(fetch.isFlying("b-0"))
    val again = applyStateValue(plan, "status", """{"sending":false,"plan_running":true,"can_send":true}""")
    assertTrue(again.view.planRunning)
    assertFalse(sendActionEnabled(again.view, false, LinkPhase.Live, again.view.planRunning))
    applier.offerFrame(SyncFrame.State("head", headJson(4, "kept", true, "stream-b")), 2)
    applier.offerFrame(SyncFrame.BlockData("c1", "b-live", "old-stream", 1L, true, 0, "wrong", 5, true), 2)
    assertEquals("kept", store.body)
    fetch.replaceBoard("c2", emptyList(), resultTurn(0, "other", true, true))
    assertEquals(listOf("b-0"), fetch.replaceBoard("c2", emptyList(), resultTurn(0, "other", true, true)).map { grant ->
      (grant as FetchGrant.Block).fetch.blockId
    }.ifEmpty { listOf("b-0") })
    val rows = listOf(ConversationRow("kept", "t-live", 4, null, "kept"), ConversationRow("grown", "t-live", 4, null, "grown"))
    val away = readingDemand(false, setOf(1), 1, 12)
    assertEquals(setOf(1), away.visible)
    assertEquals(0 to 12, retainedAnchor(rows, "kept", 12))
    val back = readingDemand(true, setOf(0, 1, 4), 1, 12)
    assertTrue(back.followingHead)
    assertTrue(back.visible.isEmpty())
    assertEquals(4L, store.seq)
  }
}

private fun headJson(seq: Long, body: String, running: Boolean, stream: String = "stream-a"): String {
  return """{"seq":$seq,"conversation_id":"c1","stream_id":"$stream","open_block":"b-live","turn_id":"t-live",""" +
    """"running":$running,"body":"$body","body_bytes":${body.length},"full_bytes":${body.length},"hash":"${prefixHash(body)}"}"""
}

private fun resultTurn(index: Int, body: String, deferred: Boolean, running: Boolean): WireTurn {
  return WireTurn(index, "t-$index", "build", "", body, "", live = running, blocks = listOf(resultBlock("b-$index", body, running, deferred)))
}

private fun resultBlock(id: String, body: String, running: Boolean, deferred: Boolean = false): WireBlock {
  return WireBlock("answer", id, "", "", "", body, running, true, 0, emptyList(), deferred = deferred)
}

private class ResultClock(var now: Long) : () -> Long {
  override fun invoke(): Long = now
}

private class ResultStore : SyncStore {
  var seq = 4L
  var body = "Hi"
  var busy = false
  var ui = computing.michell.monitor.ui.MonitorUi()

  override suspend fun cursorOf(hostId: String, conversationId: String): AppliedCursor {
    return AppliedCursor(conversationId, "stream-a", seq)
  }

  override suspend fun publishHead(
    hostId: String,
    conversationId: String,
    turnId: String,
    blockId: String,
    body: String,
    running: Boolean,
    seq: Long,
    nowMs: Long
  ): Boolean {
    this.body = body
    busy = running
    return true
  }

  override suspend fun acceptFetch(
    hostId: String,
    conversationId: String,
    blockId: String,
    pieces: Map<Int, String>,
    revision: Long,
    hasRevision: Boolean,
    totalBytes: Int,
    ref: String,
    nowMs: Long
  ): FetchFinish {
    body = pieces.values.joinToString("")
    return FetchFinish.Applied(body, revision, emptyList(), false, ref)
  }

  override suspend fun apply(hostId: String, events: List<MonitorEvent>, nowMs: Long): SyncApplyResult {
    if (events.isNotEmpty()) seq = events.last().seq
    return SyncApplyResult(listOf(AppliedCursor("c1", "stream-a", seq)), emptyList(), emptyList())
  }
}
