package computing.michell.monitor.data

/* Sync applier: batch, skip, gap, and one commit (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.MonitorEvent
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SyncApplierTest {
  @Test
  fun resumeCompletionReleasesBodyRequestsDiscardedByTheHost() = runBlocking {
    val applier = SyncApplier("host-1", MemorySyncStore(), TestClock(0L))
    assertEquals(
      listOf(SyncEffect.FetchReady, SyncEffect.CacheReady),
      applier.offerFrame(computing.michell.monitor.protocol.SyncFrame.ResumeOk("c1", "stream-a", 4L))
    )
  }

  @Test
  fun tickIsNotEnteredOnTheMainDispatcher() = runBlocking {
    val applier = SyncApplier("host-1", MemorySyncStore(), TestClock(0L))
    val job = applier.start(this)
    delay(200)
    job.cancel()
    assertTrue(applier.tickDispatcher.isNotEmpty())
    assertFalse(applier.tickDispatcher.contains("Main"))
    assertTrue(applier.tickDispatcher.contains("IO"))
  }

  @Test
  fun aFullBatchCommitsOnceAndAShortBatchWaitsForTheWindow() = runBlocking {
    val store = MemorySyncStore()
    val clock = TestClock(1_000L)
    val applier = SyncApplier("host-1", store, clock)
    assertTrue(applier.offer(turn(1)).isEmpty())
    assertEquals(0, store.applyCalls)
    clock.now = 1_049L
    assertTrue(applier.tick().isEmpty())
    assertEquals(0, store.applyCalls)
    clock.now = 1_050L
    assertEquals(listOf(SyncEffect.Ack("c1", "stream-a", 1L), SyncEffect.CacheReady), applier.tick())
    assertEquals(1, store.applyCalls)
    assertEquals(1L, store.seq("c1"))
    repeat(127) { index ->
      applier.offer(turn(index + 2L))
    }
    assertEquals(1, store.applyCalls)
    assertEquals(listOf(SyncEffect.CacheReady), applier.offer(turn(129L)))
    assertEquals(2, store.applyCalls)
    assertEquals(129L, store.seq("c1"))
  }

  @Test
  fun duplicatesAreSkippedAndAGapResumesFromTheStoredSeq() = runBlocking {
    val store = MemorySyncStore()
    store.seed("c1", "stream-a", 4L)
    val clock = TestClock(0L)
    val applier = SyncApplier("host-1", store, clock)
    applier.offer(turn(4))
    applier.offer(turn(5))
    clock.now = 50L
    assertEquals(listOf(SyncEffect.Ack("c1", "stream-a", 5L), SyncEffect.CacheReady), applier.tick())
    assertEquals(5L, store.seq("c1"))
    assertEquals("Add 5", store.prompt("c1", "t5"))
    applier.offer(turn(7))
    clock.now = 100L
    assertEquals(listOf(SyncEffect.Resume("c1", "stream-a", 5L)), applier.tick())
    assertEquals(5L, store.seq("c1"))
    assertNull(store.prompt("c1", "t7"))
  }

  @Test
  fun resumeWaitsThenReconnectsAndAnAppliedSeqClearsTheWait() = runBlocking {
    val store = MemorySyncStore()
    store.seed("c1", "stream-a", 2L)
    val clock = TestClock(0L)
    val applier = SyncApplier("host-1", store, clock)
    applier.offer(turn(4))
    clock.now = 50L
    assertEquals(SyncEffect.Resume("c1", "stream-a", 2L), applier.tick().single())
    clock.now = 1_049L
    assertTrue(applier.tick().isEmpty())
    clock.now = 1_050L
    assertEquals(SyncEffect.Resume("c1", "stream-a", 2L), applier.tick().single())
    clock.now = 3_050L
    assertEquals(SyncEffect.Resume("c1", "stream-a", 2L), applier.tick().single())
    clock.now = 7_050L
    assertEquals(SyncEffect.Resume("c1", "stream-a", 2L), applier.tick().single())
    clock.now = 15_050L
    assertEquals(SyncEffect.Reconnect, applier.tick().single())

    val caught = SyncApplier("host-1", store, clock)
    caught.offer(turn(4))
    clock.now = 20_000L
    assertEquals(SyncEffect.Resume("c1", "stream-a", 2L), caught.tick().single())
    caught.offer(turn(3))
    clock.now = 20_050L
    assertEquals(listOf(SyncEffect.Ack("c1", "stream-a", 3L), SyncEffect.CacheReady), caught.tick())
    clock.now = 21_050L
    assertTrue(caught.tick().isEmpty())
    assertEquals(3L, store.seq("c1"))
  }

  @Test
  fun aGapWhileLiveResumesAndDoesNotReconnect() {
    val policy = SyncResumePolicy()
    val first = policy.onGap(computing.michell.monitor.data.SyncGap("c1", "stream-a", 2L), 0L)
    assertEquals(SyncEffect.Resume("c1", "stream-a", 2L), first)
    assertFalse(reconnectAllowed(linkLive = true, framesArriving = true))
    var now = 0L
    val admitted = mutableListOf<SyncEffect>()
    if (first != null) admitted += first
    repeat(6) {
      now += 8_000L
      for (effect in policy.tick(now)) {
        if (effect == SyncEffect.Reconnect && !reconnectAllowed(true, true)) continue
        admitted += effect
      }
    }
    assertTrue(admitted.any { effect -> effect is SyncEffect.Resume })
    assertTrue(admitted.none { effect -> effect == SyncEffect.Reconnect })
    assertTrue(reconnectAllowed(linkLive = false, framesArriving = false))
  }

  @Test
  fun anAppendPastTheStoredBodyAsksForTheBlockAndStillAdvancesTheCursor() = runBlocking {
    val store = MemorySyncStore()
    store.seed("c1", "stream-a", 0L)
    store.blocks += BlockRecord("host-1", "c1", "t1", "b1", 0, "answer", "", "Hi", "running")
    val clock = TestClock(0L)
    val applier = SyncApplier("host-1", store, clock)
    applier.offer(MonitorEvent.BlockAppend("c1", "stream-a", 1L, "b1", 4, " there"))
    clock.now = 50L
    val effects = applier.tick()
    assertEquals(SyncEffect.Ack("c1", "stream-a", 1L), effects[0])
    val fetch = effects[1] as SyncEffect.FetchBlock
    assertEquals("c1", fetch.conversationId)
    assertEquals("b1", fetch.blockId)
    assertEquals(2, fetch.offset)
    assertEquals("Hi", store.blocks.single().body)
    assertEquals(1L, store.seq("c1"))
  }

  @Test
  fun aStoredTurnReplacesTheRetiredTurnFiledAtItsIndex() = runBlocking {
    val store = MemorySyncStore()
    store.seed("c1", "stream-a", 0L)
    val clock = TestClock(0L)
    val applier = SyncApplier("host-1", store, clock)
    // A plan run's note turn goes live, then is retired at the next index when the prompt starts.
    applier.offer(MonitorEvent.TurnOpen("c1", "stream-a", 1L, "notes", -1, "Build", "", ""))
    applier.offer(MonitorEvent.BlockOpen("c1", "stream-a", 2L, "notes", "n1", 0, "note", ""))
    applier.offer(MonitorEvent.TurnOpen("c1", "stream-a", 3L, "notes", 0, "Build", "", ""))
    clock.now = 50L
    applier.tick()
    assertEquals(listOf("notes"), store.turns.map { it.turnId })
    // The prompt's turn is stored at the same index, then the report after it.
    applier.offer(MonitorEvent.TurnOpen("c1", "stream-a", 4L, "work", -1, "Build", "Work on 6.8", ""))
    applier.offer(MonitorEvent.TurnOpen("c1", "stream-a", 5L, "work", 0, "Build", "Work on 6.8", ""))
    applier.offer(MonitorEvent.TurnOpen("c1", "stream-a", 6L, "report", 1, "Build", "", ""))
    clock.now = 100L
    applier.tick()
    assertEquals(listOf("work", "report"), store.turns.sortedBy { it.ordinal }.map { it.turnId })
    assertTrue(store.blocks.none { it.turn == "notes" })
  }

  @Test
  fun theLastTurnOpenedAtAnIndexInOneBatchKeepsIt() = runBlocking {
    val store = MemorySyncStore()
    store.seed("c1", "stream-a", 0L)
    val clock = TestClock(0L)
    val applier = SyncApplier("host-1", store, clock)
    applier.offer(MonitorEvent.TurnOpen("c1", "stream-a", 1L, "notes", 0, "Build", "", ""))
    applier.offer(MonitorEvent.TurnOpen("c1", "stream-a", 2L, "work", 0, "Build", "Work on 6.8", ""))
    clock.now = 50L
    applier.tick()
    assertEquals(listOf("work"), store.turns.map { it.turnId })
  }

  private fun turn(seq: Long): MonitorEvent.TurnOpen {
    return MonitorEvent.TurnOpen("c1", "stream-a", seq, "t$seq", seq.toInt(), "Build", "Add $seq", "2026-10-29T09:20:00Z")
  }
}

private class TestClock(var now: Long) : () -> Long {
  override fun invoke(): Long = now
}

private class MemorySyncStore : SyncStore {
  var applyCalls = 0
  val conversations = mutableMapOf<String, ConversationRecord>()
  val turns = mutableListOf<TurnRecord>()
  val blocks = mutableListOf<BlockRecord>()
  val images = mutableListOf<ImageRecord>()

  fun seed(id: String, streamId: String, seq: Long) {
    conversations[id] = ConversationRecord(id, "host-1", "/work", "Title", streamId, seq, 0L, false)
  }

  fun seq(id: String): Long = conversations.getValue(id).seq

  fun prompt(id: String, turnId: String): String? {
    return turns.firstOrNull { it.conversationId == id && it.turnId == turnId }?.prompt
  }

  override suspend fun apply(hostId: String, events: List<MonitorEvent>, nowMs: Long): SyncApplyResult {
    applyCalls += 1
    val commits = mutableListOf<SyncCommit>()
    val gaps = mutableListOf<SyncGap>()
    val fetches = mutableListOf<BlockFetch>()
    val applied = mutableListOf<AppliedCursor>()
    for ((id, group) in events.groupBy { it.conversationId }) {
      val reduced = reduceSync(
        hostId,
        nowMs,
        conversations[id],
        turns.filter { it.conversationId == id },
        blocks.filter { it.conversation == id },
        images.filter { it.conversation == id },
        group
      )
      val commit = reduced.commit
      if (commit != null) {
        commits += commit
        conversations[id] = commit.conversation
        for (turn in commit.turns) {
          turns.removeAll { it.conversationId == id && it.turnId == turn.turnId }
          turns += turn
        }
        for (block in commit.blocks) {
          blocks.removeAll { it.conversation == id && it.blockId == block.blockId }
          blocks += block
        }
        for (claim in commit.claims) {
          val gone = turns.filter { it.conversationId == id && it.ordinal == claim.ordinal && it.turnId != claim.turnId }
            .map { it.turnId }.toSet()
          turns.removeAll { it.conversationId == id && it.turnId in gone }
          blocks.removeAll { it.conversation == id && it.turn in gone }
        }
        for (image in commit.images) {
          images.removeAll { it.conversation == id && it.id == image.id }
          images += image
        }
      }
      reduced.gap?.let { gaps += it }
      fetches += reduced.fetches
      reduced.applied?.let { applied += it }
    }
    check(commits.all { commit ->
      commit.conversation.seq == applied.first { it.conversationId == commit.conversation.id }.seq &&
        commit.conversation.streamId.isNotEmpty()
    })
    return SyncApplyResult(applied, gaps, fetches)
  }
}
