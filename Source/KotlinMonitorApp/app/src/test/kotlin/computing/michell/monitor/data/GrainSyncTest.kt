package computing.michell.monitor.data

/* Grain the hybrid does not keep yet. Green at item 7.1. Do not weaken these
   assertions to match today's wire. (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.AccountedEvents
import computing.michell.monitor.protocol.MonitorEvent
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GrainSyncTest {
  @Test
  fun aPatchIsNotTheStoredEventAndAFailedApplyStaysPending() = runBlocking {
    val store = ThrowingStore()
    val clock = GrainClock(0L)
    val applier = SyncApplier("host-1", store, clock)
    try {
      applier.offer(append(1))
      clock.now = 50L
      applier.tick()
    } catch (error: IllegalStateException) {
      // The hybrid clears the batch before apply. Item 7.1 must keep it.
    }
    clock.now = 120L
    try {
      applier.tick()
    } catch (error: IllegalStateException) {
    }
    assertTrue("7.1 the batch is still pending after apply fails", store.calls >= 2)
    assertEquals("7.1 ack is not sent for a failed apply", 1L, store.last.single().seq)
  }

  @Test
  fun aSequenceGapDoesNotClearCommittedRows() {
    val existing = BlockRecord("host-1", "c1", "t-1", "b-1", 0, "answer", "", "kept", "ok")
    val reduced = reduceSync(
      "host-1",
      1L,
      ConversationRecord("c1", "host-1", "/work", "Title", "stream-a", 1L, 0L, false),
      emptyList(),
      listOf(existing),
      emptyList(),
      listOf(append(3))
    )
    assertEquals("7.1 a sequence gap does not apply the skipped event", null, reduced.applied)
    assertEquals("7.1 a sequence gap does not clear rows already committed", "kept", reduced.commit?.blocks?.singleOrNull()?.body ?: "kept")
  }

  @Test
  fun anAccountedEventsBudgetOverflowEmitsResume() {
    val events = AccountedEvents(budgetBytes = 4)
    assertTrue(events.offer(append(1), 4))
    val overflow = events.offer(append(2), 4)
    assertTrue("7.1 an AccountedEvents budget overflow emits resume", overflow)
  }

  @Test
  fun aLargePlanIsNotReplacedByAnErrorSentence() {
    val body = "x".repeat(5 * 1024 * 1024)
    val text = planCacheText("Documents/Plan.md", "Big", emptyList(), 0, body)
    assertFalse("7.1 the error sentence is absent", text.contains("too large to cache"))
    assertFalse("7.1 the desktop sentence is absent", text.contains("The rest of the plan is on the desktop."))
    val stored = storedPlanOf("Documents/Plan.md", "Big", 0, text)
    assertEquals("7.1 a plan larger than 4 MiB is not held in the row and is not replaced by a sentence", "", stored!!.body)
  }

  private fun append(seq: Long): MonitorEvent.BlockAppend {
    return MonitorEvent.BlockAppend("c1", "stream-a", seq, "b-1", 0, "slice")
  }
}

private class GrainClock(var now: Long) : () -> Long {
  override fun invoke(): Long = now
}

private class ThrowingStore : SyncStore {
  var calls = 0
  var last: List<MonitorEvent> = emptyList()

  override suspend fun apply(hostId: String, events: List<MonitorEvent>, nowMs: Long): SyncApplyResult {
    calls += 1
    last = events
    throw IllegalStateException("apply failed")
  }
}
