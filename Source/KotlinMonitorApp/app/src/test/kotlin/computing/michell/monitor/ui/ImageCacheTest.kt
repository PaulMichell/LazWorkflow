package computing.michell.monitor.ui

/* Image request and cache decisions without a device (c) 2026 Michell Computing. */

import computing.michell.monitor.data.StoredImagesBlockId
import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireImage
import computing.michell.monitor.protocol.WireTurn
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

private fun picture(id: String, path: String = "", missing: Boolean = false): WireImage {
  return WireImage(id, id, "image/png", 0, 0, path, missing)
}

private fun turnWith(index: Int, vararg blocks: Pair<String, List<WireImage>>): WireTurn {
  return WireTurn(index, "turn-$index", "build", "", "", "", blocks = blocks.map { (blockId, images) ->
    WireBlock("tool", blockId, "", "", "", "", false, true, 0, images)
  })
}

class ImageCacheTest {
  @Test
  fun theBoardAsksForUnfetchedPicturesLiveFirstThenNewest() {
    val old = turnWith(0, "b0" to listOf(picture("old")))
    val newer = turnWith(1, "b1" to listOf(picture("fetched", path = "/files/fetched"), picture("newer")))
    val live = turnWith(-2, "b-live" to listOf(picture("live")))
    val keys = boardImageFetches(3, listOf(old, newer), live, emptySet(), 8)
    assertEquals(listOf("live", "newer", "old"), keys.map { key -> key.imageId })
    assertEquals(listOf(-2, 1, 0), keys.map { key -> key.turnIndex })
    assertTrue(keys.all { key -> key.hostGeneration == 3 })
    assertEquals(listOf("live"), boardImageFetches(3, listOf(old, newer), live, emptySet(), 1).map { key -> key.imageId })
    assertEquals(listOf("old"), boardImageFetches(3, listOf(old, newer), live, setOf("live", "newer"), 8).map { key -> key.imageId })
    assertTrue(boardImageFetches(3, listOf(old), null, emptySet(), 0).isEmpty())
  }

  @Test
  fun missingPicturesAndTheUnplacedNoteAreNotAskedFor() {
    val turn = turnWith(
      4,
      "b4" to listOf(picture("gone", missing = true)),
      StoredImagesBlockId to listOf(picture("no-turn"))
    )
    assertTrue(boardImageFetches(0, listOf(turn), null, emptySet(), 8).isEmpty())
  }

  @Test
  fun theTrackerKeepsRequestsInsideTheLimitAndSettlesAnswers() {
    val board = BoardContent("host", "c1", listOf(turnWith(0, "b0" to listOf(picture("a"), picture("b"), picture("c")))))
    val tracker = ImageFetchTracker(limit = 2, lifetimeMs = 1_000L)
    assertEquals(listOf("a", "b"), tracker.next(0, board, 0L).map { key -> key.imageId })
    assertTrue(tracker.next(0, board, 10L).isEmpty())
    tracker.settle("a")
    assertEquals(listOf("c"), tracker.next(0, board, 20L).map { key -> key.imageId })
    // An answered picture is not asked for again. An unanswered one is, after the assembly lifetime.
    assertEquals(listOf("b", "c"), tracker.next(0, board, 1_020L).map { key -> key.imageId })
    tracker.linkDropped()
    assertEquals(setOf<String>(), tracker.inFlight)
    assertEquals(listOf("b", "c"), tracker.next(0, board, 1_030L).map { key -> key.imageId })
    tracker.release("b")
    assertEquals(listOf("b"), tracker.next(0, board, 1_040L).map { key -> key.imageId })
    tracker.reset()
    assertEquals(listOf("a", "b"), tracker.next(0, board, 1_050L).map { key -> key.imageId })
  }

  @Test
  fun aRefusalOnTheLiveTurnIsAskedAgainOnceTheTurnIsStored() {
    val tracker = ImageFetchTracker(limit = 4, lifetimeMs = 1_000L)
    val running = BoardContent("host", "c1", emptyList(), turnWith(-2, "u" to listOf(picture("shot"))))
    assertEquals(listOf(-2), tracker.next(0, running, 0L).map { key -> key.turnIndex })
    tracker.refuse("shot")
    // While the turn runs, the refused picture is not asked for again on the live turn.
    assertTrue(tracker.next(0, running, 10L).isEmpty())
    val stored = BoardContent("host", "c1", listOf(turnWith(5, "u" to listOf(picture("shot")))))
    val again = tracker.next(0, stored, 20L)
    assertEquals(listOf("shot"), again.map { key -> key.imageId })
    assertEquals(listOf(5), again.map { key -> key.turnIndex })
    // A refusal for a stored turn settles the id.
    tracker.refuse("shot")
    assertTrue(tracker.next(0, stored, 30L).isEmpty())
    assertTrue(tracker.next(0, running, 40L).isEmpty())
  }

  @Test
  fun anAnswerAfterALiveRefusalSettlesThePicture() {
    val tracker = ImageFetchTracker(limit = 4, lifetimeMs = 1_000L)
    val running = BoardContent("host", "c1", emptyList(), turnWith(-2, "u" to listOf(picture("shot"))))
    tracker.next(0, running, 0L)
    tracker.refuse("shot")
    val stored = BoardContent("host", "c1", listOf(turnWith(5, "u" to listOf(picture("shot")))))
    tracker.next(0, stored, 10L)
    tracker.settle("shot")
    assertTrue(tracker.next(0, stored, 20L).isEmpty())
    // A reset forgets the refusal, so a new link may ask on the live turn again.
    tracker.reset()
    assertEquals(listOf("shot"), tracker.next(0, running, 30L).map { key -> key.imageId })
  }

  @Test
  fun visibleSetRequestsLiveNeighboursAndNotDistantHistory() {
    val order = listOf(0, 1, 2, 3, 4)
    val images = mapOf(
      0 to listOf("img-0"),
      2 to listOf("img-2"),
      3 to listOf("img-3"),
      4 to listOf("img-4"),
      -2 to listOf("live-img")
    )
    val keys = imageRequestKeys(7, order, images, -2, setOf(3))
    val ids = keys.map { it.imageId }.toSet()
    assertEquals(setOf("img-2", "img-3", "img-4", "live-img"), ids)
    assertFalse(ids.contains("img-0"))
    assertTrue(keys.all { it.hostGeneration == 7 })
    assertEquals(3, keys.first { it.imageId == "img-3" }.turnIndex)
    assertEquals(emptySet<String>(), imageRequestKeys(7, order, images, null, emptySet()).map { it.imageId }.toSet())
  }

  @Test
  fun prefetchRecentDoesNotReportEveryHistoryTurn() {
    val slots = (0..10).map { index -> VirtualSlot(index, "Turn $index", false) } + VirtualSlot(-2, "Live", true)
    val reported = prefetchRecent(slots)
    assertEquals(setOf(9, 10), reported)
    assertFalse(reported.contains(0))
    assertFalse(reported.contains(-2))
    assertTrue(reported.size < 11)
  }

  @Test
  fun generationChangeAndTurnLeavingEvictCachedKeys() {
    val cache = ImagePixelCache(100)
    val first = ImageCacheKey(0, "img-1", 1)
    val second = ImageCacheKey(0, "img-2", 1)
    cache.insert(first, 1, 40, 0, setOf(1, 2))
    cache.insert(second, 2, 40, 0, setOf(1, 2))
    assertEquals(setOf(first, second), cache.keys)
    val left = cache.retain(0, setOf(2))
    assertEquals(setOf(first), left)
    assertEquals(setOf(second), cache.keys)
    val next = ImageCacheKey(1, "img-2", 1)
    val dropped = cache.insert(next, 2, 40, 1, setOf(2))
    assertTrue(dropped.contains(second))
    assertEquals(setOf(next), cache.keys)
    assertEquals(setOf(next), cache.reset())
    assertTrue(cache.keys.isEmpty())
  }

  @Test
  fun insertEvictsOldestWhenDecodedBytesExceedTheBudget() {
    val cache = ImagePixelCache(100)
    val oldest = ImageCacheKey(0, "old", 1)
    val middle = ImageCacheKey(0, "mid", 1)
    val newest = ImageCacheKey(0, "new", 2)
    cache.insert(oldest, 1, 40, 0, setOf(1))
    cache.insert(middle, 1, 40, 0, setOf(1))
    val removed = cache.insert(newest, 1, 40, 0, setOf(1))
    assertTrue(removed.contains(oldest))
    assertFalse(cache.keys.contains(oldest))
    assertEquals(setOf(middle, newest), cache.keys)
    val replaced = ImageCacheKey(0, "new", 3)
    val revision = cache.insert(replaced, 1, 40, 0, setOf(1))
    assertTrue(revision.contains(newest))
    assertFalse(cache.keys.contains(newest))
    assertTrue(cache.keys.contains(replaced))
  }
}
