package computing.michell.monitor.data

/* A head snapshot paints without waiting for history, and history cannot undo it
   (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.MonitorEvent
import computing.michell.monitor.protocol.SyncFrame
import computing.michell.monitor.protocol.prefixHash
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HeadSnapshotTest {
  @Test
  fun aWithheldFetchCannotHideTheNextHead() = runBlocking {
    val store = HeadStore()
    val clock = HeadClock(1_000L)
    val applier = SyncApplier("host-1", store, clock)
    applier.adoptConnection(1)
    applier.offerFrame(SyncFrame.BlockData("c1", "b-live", "old", 1L, true, 0, "Hi", 4, false), 1)
    val snapshot = headJson(12, "Hello tail")
    val painted = applier.offerFrame(SyncFrame.State("head", snapshot), 1)
    assertTrue(painted.any { it is SyncEffect.StateApplied && it.key == "head" })
    assertEquals("Hello tail", store.body)
    assertEquals(4L, store.seq)
    assertFalse(store.cursorMoved)
    val older = applier.offerFrame(SyncFrame.State("head", headJson(3, "old")), 1)
    assertTrue(older.any { it is SyncEffect.CacheReady })
    assertEquals("Hello tail", store.body)
    assertEquals(4L, store.seq)
    val late = applier.offerFrame(SyncFrame.BlockData("c1", "b-live", "old", 1L, true, 0, "Hi!!", 4, true), 1)
    assertTrue(late.none { it is SyncEffect.Ack })
    assertEquals("Hello tail", store.body)
    assertEquals(4L, store.seq)
  }

  @Test
  fun anOlderSnapshotDoesNotShortenThePaintedBody() {
    val current = headSnapshot(headJson(12, "Hello tail"))!!
    assertEquals("Hello tail", acceptHeadBody(-1L, "Hi", current))
    assertNull(acceptHeadBody(12L, "Hello tail", headSnapshot(headJson(12, "Hello"))!!))
    assertNull(acceptHeadBody(12L, "Hello tail", headSnapshot(headJson(4, "older"))!!))
    assertEquals("Hello tail", retainHeadBody("Hello tail", 12L, "b-live", "b-live", "Hi!!", 1L))
    assertEquals("Hello tail more", retainHeadBody("Hello tail", 12L, "b-live", "b-live", "Hello tail more", 1L))
  }

  private fun headJson(seq: Long, body: String): String {
    return """{"seq":$seq,"conversation_id":"c1","stream_id":"stream-a","open_block":"b-live","turn_id":"t-live",""" +
      """"running":true,"body":"$body","body_bytes":${body.length},"full_bytes":${body.length},"hash":"${prefixHash(body)}"}"""
  }
}

private class HeadClock(var now: Long) : () -> Long {
  override fun invoke(): Long = now
}

private class HeadStore : SyncStore {
  var seq = 4L
  var body = "Hi"
  var cursorMoved = false

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
    val candidate = pieces.values.joinToString("")
    body = candidate
    return FetchFinish.Applied(candidate, revision, emptyList(), false, ref)
  }

  override suspend fun apply(hostId: String, events: List<MonitorEvent>, nowMs: Long): SyncApplyResult {
    cursorMoved = true
    if (events.isNotEmpty()) seq = events.last().seq
    return SyncApplyResult(listOf(AppliedCursor("c1", "stream-a", seq)), emptyList(), emptyList())
  }
}
