package computing.michell.monitor.ui

/* A block append must not rebuild every turn or decode an unchanged image
   (c) 2026 Michell Computing. */

import computing.michell.monitor.data.BlockRecord
import computing.michell.monitor.data.BlockRepairRecord
import computing.michell.monitor.data.ConversationRecord
import computing.michell.monitor.data.ImageRecord
import computing.michell.monitor.data.TurnRecord
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenWatchTest {
  @Test
  fun twoBlockUpdatesDecodeAnUnchangedImageOnceAndReuseTheOtherTurn() = runBlocking {
    val store = FakeScreenStore()
    store.turns.value = listOf(turn("t1", 1, "done"), turn("t2", 2, "running"))
    store.blocks.value = listOf(block("t1", "b1", "kept"))
    store.images.value = listOf(image("img", 12L))
    val boards = Channel<BoardContent>(Channel.UNLIMITED)
    val decoded = AtomicInteger(0)
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    val job = watchStoredScreen(
      scope, store.turns, store.blocks, store.images, store.repairs, store.row,
      "host", "c1", { pictured -> pictured.bytes },
      onBoard = { board, _ -> boards.send(board) },
      decode = { pictured -> decoded.incrementAndGet() }
    )
    val first = withTimeout(2_000) { boards.receive() }
    store.blocks.value = listOf(block("t1", "b1", "kept"), block("t2", "b2", "more"))
    val second = withTimeout(2_000) { boards.receive() }
    assertEquals("kept", second.turns.single().blocks.single().body)
    assertTrue(first.turns.single() === second.turns.single())
    assertEquals("more", second.live?.blocks?.first { row -> row.blockId == "b2" }?.body)
    withTimeout(2_000) { while (decoded.get() < 1) yield() }
    yield()
    assertEquals(1, decoded.get())
    job.cancel()
    scope.cancel()
  }

  @Test
  fun aReplacedFileLengthCancelsTheInFlightDecode() = runBlocking {
    val store = FakeScreenStore()
    store.turns.value = listOf(turn("t1", 1, "done"))
    store.blocks.value = listOf(block("t1", "b1", "kept"))
    store.images.value = listOf(image("img", 12L))
    val started = CompletableDeferred<Unit>()
    val cancelled = AtomicInteger(0)
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    val job = watchStoredScreen(
      scope, store.turns, store.blocks, store.images, store.repairs, store.row,
      "host", "c1", { pictured -> pictured.bytes },
      onBoard = { _, _ -> },
      decode = { pictured ->
        if (pictured.bytes != 12L) return@watchStoredScreen
        if (!started.isCompleted) started.complete(Unit)
        try {
          delay(60_000)
        } catch (error: CancellationException) {
          cancelled.incrementAndGet()
          throw error
        }
      }
    )
    withTimeout(2_000) { started.await() }
    store.images.value = listOf(image("img", 20L))
    withTimeout(2_000) { while (cancelled.get() < 1) yield() }
    assertEquals(1, cancelled.get())
    job.cancel()
    scope.cancel()
  }
}

private class FakeScreenStore {
  val turns = MutableStateFlow<List<TurnRecord>>(emptyList())
  val blocks = MutableStateFlow<List<BlockRecord>>(emptyList())
  val images = MutableStateFlow<List<ImageRecord>>(emptyList())
  val repairs = MutableStateFlow<List<BlockRepairRecord>>(emptyList())
  val row = MutableStateFlow<ConversationRecord?>(null)
}

private fun turn(id: String, ordinal: Int, outcome: String): TurnRecord {
  return TurnRecord("host", "c1", id, ordinal, "build", "prompt", "", outcome, 0, "")
}

private fun block(turnId: String, id: String, body: String): BlockRecord {
  return BlockRecord("host", "c1", turnId, id, 0, "answer", "", body, "ok")
}

private fun image(id: String, bytes: Long): ImageRecord {
  return ImageRecord(id, "host", "c1", "/tmp/$id", bytes, "image/png", bytes)
}
