package computing.michell.monitor.data

/* Cursor apply: held appends, fetch completion, and a failed batch (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.EmptyPrefixHash
import computing.michell.monitor.protocol.MonitorEvent
import computing.michell.monitor.protocol.OutlineBlock
import computing.michell.monitor.protocol.OutlineTurn
import computing.michell.monitor.protocol.prefixHash
import computing.michell.monitor.ui.MonitorUi
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SyncSliceTest {
  @Test
  fun aFailedApplyKeepsTheBatchAndDoesNotAck() = runBlocking {
    val store = SliceThrowingStore()
    val clock = SliceClock(0L)
    val effects = mutableListOf<SyncEffect>()
    val applier = SyncApplier("host-1", store, clock) { effects += it }
    applier.offer(append(1, 0, "one"))
    clock.now = 50L
    applier.tick()
    clock.now = 100L
    applier.tick()
    assertTrue(store.calls >= 2)
    assertEquals(1L, store.last.single().seq)
    assertTrue(effects.none { it is SyncEffect.Ack })
  }

  @Test
  fun aGapLeavesTheCommittedBody() {
    val existing = BlockRecord("host-1", "c1", "t-1", "b-1", 0, "answer", "", "kept", "ok")
    val reduced = reduceSync(
      "host-1", 1L,
      ConversationRecord("c1", "host-1", "/work", "Title", "stream-a", 1L, 0L, false),
      emptyList(), listOf(existing), emptyList(), listOf(append(3, 4, "more"))
    )
    assertNull(reduced.applied)
    assertNull(reduced.commit)
    assertEquals(1L, reduced.gap?.seq)
  }

  @Test
  fun aMismatchHoldsTheAppendAndFetchesThePrefix() {
    val block = BlockRecord("host-1", "c1", "t-1", "b-1", 0, "answer", "", "Hi", "running")
    val reduced = reduceSync(
      "host-1", 1L,
      ConversationRecord("c1", "host-1", "/work", "Title", "stream-a", 0L, 0L, false),
      emptyList(), listOf(block), emptyList(), listOf(append(1, 4, " there"))
    )
    assertEquals(1L, reduced.applied?.seq)
    assertEquals("Hi", reduced.commit?.blocks?.single()?.body)
    assertEquals(2, reduced.fetches.single().offset)
    assertEquals(prefixHash("Hi"), reduced.fetches.single().prefixHash)
    assertTrue(reduced.commit?.repairs?.single()?.missingBody == true)
    assertEquals(2, reduced.commit?.repairs?.single()?.expectedLength)
    assertEquals(1L, reduced.commit?.held?.single()?.seq)
  }

  @Test
  fun aLaterAppendWhileFetchingDoesNotPaintOrFetchAgain() {
    val block = BlockRecord("host-1", "c1", "t-1", "b-1", 0, "answer", "", "Hi", "running")
    val repair = BlockRepair("host-1", "c1", "b-1", 3L, 2, true, prefixHash("Hi"), false, "bg-b-1-1", "")
    val reduced = reduceSync(
      "host-1", 2L,
      ConversationRecord("c1", "host-1", "/work", "Title", "stream-a", 1L, 0L, false),
      emptyList(), listOf(block), emptyList(), listOf(append(2, 9, " more")),
      listOf(repair)
    )
    assertEquals("Hi", reduced.commit?.blocks?.single()?.body)
    assertTrue(reduced.fetches.isEmpty())
    assertEquals(1, reduced.commit?.held?.size)
    assertEquals(3L, reduced.commit?.repairs?.single()?.revision)
  }

  @Test
  fun fetchCompletionAppliesTheTailAndDoesNotNeedACursor() {
    val block = BlockRecord("host-1", "c1", "t-1", "b-1", 0, "answer", "", "Hi", "running")
    val repair = BlockRepair("host-1", "c1", "b-1", 4L, 2, true, prefixHash("Hi"), false, "bg-b-1-1", "")
    val held = listOf(
      HeldAppend("host-1", "c1", "b-1", 1L, 2, "!!", "stream-a"),
      HeldAppend("host-1", "c1", "b-1", 2L, 4, " tail", "stream-a")
    )
    val finished = finishFetch(
      block, repair, held, mapOf(2 to "!!"), 4L, true, 4, "bg-b-1-1", 9L
    ) as FetchFinish.Applied
    assertEquals("Hi!! tail", finished.body)
    assertFalse(finished.missingBody)
    assertEquals(listOf(1L, 2L), finished.dropSeqs)
  }

  @Test
  fun aMismatchedRevisionDiscardsTheBody() {
    val repair = BlockRepair("host-1", "c1", "b-1", 4L, 0, true, EmptyPrefixHash, true, "bg-b-1-1", "")
    val finished = finishFetch(
      null, repair, emptyList(), mapOf(0 to "new"), 5L, true, 3, "bg-b-1-1", 9L
    )
    assertTrue(finished is FetchFinish.Again)
    assertEquals(0, (finished as FetchFinish.Again).offset)
  }

  @Test
  fun aLongTurnCanSpanSeveralOutlinePages() {
    val stage = BaselineStage()
    stage.begin(computing.michell.monitor.protocol.SyncFrame.SnapshotBegin(
      "c1", "stream-a", 8L, "Title", "/work", 2, emptyList(), null, emptyList()
    ))
    for (page in 1..2) {
      val block = OutlineBlock("b-$page", "answer", "ok", 1L, 4, prefixHash("body"))
      val turn = OutlineTurn("t-1", 0, "prompt", listOf(block))
      assertTrue(stage.page(computing.michell.monitor.protocol.SyncFrame.SnapshotPage(
        "c1", "stream-a", 8L, page, 2, listOf(turn), null
      )))
    }
    val commit = stage.end(computing.michell.monitor.protocol.SyncFrame.SnapshotEnd("c1", "stream-a", 8L))
    assertTrue(commit != null)
    val plan = reconcileBaseline("host-1", 1L, null, emptyList(), emptyList(), commit!!)
    assertEquals(setOf("b-1", "b-2"), plan!!.upsertBlocks.map { it.blockId }.toSet())
    assertEquals(listOf(0, 1), plan.upsertBlocks.map { it.ordinal })
    assertEquals(setOf("b-1", "b-2"), plan.fetches.map { it.blockId }.toSet())
  }

  @Test
  fun anEmptyBaselineDoesNotReplaceRows() {
    val plan = reconcileBaseline(
      "host-1", 1L,
      ConversationRecord("c1", "host-1", "/work", "Title", "old", 3L, 0L, false),
      emptyList(),
      listOf(BlockRecord("host-1", "c1", "t-1", "b-1", 0, "answer", "", "kept", "ok")),
      BaselineCommit("c1", "new", 8L, "Title", "/work", emptyList(), null)
    )
    assertNull(plan)
  }

  @Test
  fun aMatchingHashKeepsTheBodyAndAMismatchIsFetched() {
    val kept = BlockRecord("host-1", "c1", "t-1", "b-kept", 0, "answer", "", "same", "ok")
    val stale = BlockRecord("host-1", "c1", "t-1", "b-stale", 1, "answer", "", "old", "ok")
    val plan = reconcileBaseline(
      "host-1", 1L, null, emptyList(), listOf(kept, stale),
      BaselineCommit("c1", "stream-a", 8L, "Title", "/work", listOf(OutlineTurn("t-1", 1, "prompt", listOf(
        OutlineBlock("b-kept", "answer", "ok", 1L, 4, prefixHash("same")),
        OutlineBlock("b-stale", "answer", "ok", 2L, 4, prefixHash("new"))
      ))), null)
    )
    assertEquals("same", plan!!.upsertBlocks.first { it.blockId == "b-kept" }.body)
    assertEquals("old", plan.upsertBlocks.first { it.blockId == "b-stale" }.body)
    assertEquals("b-stale", plan.fetches.single().blockId)
    assertEquals(8L, plan.conversation.seq)
    assertTrue(plan.clearRepairIds.contains("b-kept"))
  }

  @Test
  fun anOutlineBodyAndTitleFillABlockThePhoneNeverSaw() {
    val plan = reconcileBaseline(
      "host-1", 1L, null, emptyList(), emptyList(),
      BaselineCommit("c1", "stream-a", 8L, "Title", "/work", listOf(OutlineTurn("t-1", 0, "prompt", listOf(
        OutlineBlock("b-user", "user", "ok", 1L, 6, prefixHash("prompt"), "User", "prompt"),
        OutlineBlock("b-tool", "tool", "ok", 1L, 9000, "0123456789abcdef", "read_file Source/Unit.pas"),
        OutlineBlock("b-answer", "answer", "ok", 1L, 4, prefixHash("done"), "Assistant", "done")
      ))), null)
    )
    val blocks = plan!!.upsertBlocks.associateBy { block -> block.blockId }
    assertEquals("prompt", blocks.getValue("b-user").body)
    assertEquals("done", blocks.getValue("b-answer").body)
    assertEquals("read_file Source/Unit.pas", blocks.getValue("b-tool").title)
    assertEquals(listOf(0, 1, 2), plan.upsertBlocks.map { block -> block.ordinal })
    // Only the large tool result is still owed.
    assertEquals("b-tool", plan.fetches.single().blockId)
    assertTrue(plan.clearRepairIds.containsAll(listOf("b-user", "b-answer")))
  }

  @Test
  fun anOutlineBodyThatFailsItsHashIsFetched() {
    val plan = reconcileBaseline(
      "host-1", 1L, null, emptyList(), emptyList(),
      BaselineCommit("c1", "stream-a", 8L, "Title", "/work", listOf(OutlineTurn("t-1", 0, "prompt", listOf(
        OutlineBlock("b-answer", "answer", "ok", 1L, 4, prefixHash("done"), "Assistant", "dome")
      ))), null)
    )
    assertEquals("", plan!!.upsertBlocks.single().body)
    assertEquals("b-answer", plan.fetches.single().blockId)
  }

  @Test
  fun stateDoesNotAdvanceTheContentSequence() {
    val ui = MonitorUi()
    val next = applyStateValue(ui, "status", """{"busy":true,"sending":true,"can_send":false}""")
    assertTrue(next.view.busy)
    assertTrue(next.view.sending)
    assertFalse(next.view.canSend)
    assertEquals(0L, ui.hostCursor)
    assertEquals(0L, next.hostCursor)
  }

  @Test
  fun theBatchClosesOnPendingBytesBefore128Events() = runBlocking {
    val store = CountingStore()
    val clock = SliceClock(0L)
    val applier = SyncApplier("host-1", store, clock)
    applier.offer(append(1, 0, "x".repeat(SyncBatchBytes)), SyncBatchBytes)
    assertEquals(1, store.calls)
  }
}

private fun append(seq: Long, offset: Int, text: String): MonitorEvent.BlockAppend {
  return MonitorEvent.BlockAppend("c1", "stream-a", seq, "b-1", offset, text)
}

private class SliceClock(var now: Long) : () -> Long {
  override fun invoke(): Long = now
}

private class SliceThrowingStore : SyncStore {
  var calls = 0
  var last: List<MonitorEvent> = emptyList()
  override suspend fun apply(hostId: String, events: List<MonitorEvent>, nowMs: Long): SyncApplyResult {
    calls += 1
    last = events
    throw IllegalStateException("apply failed")
  }
}

private class CountingStore : SyncStore {
  var calls = 0
  override suspend fun apply(hostId: String, events: List<MonitorEvent>, nowMs: Long): SyncApplyResult {
    calls += 1
    return SyncApplyResult(listOf(AppliedCursor("c1", "stream-a", events.last().seq)), emptyList(), emptyList())
  }
}
