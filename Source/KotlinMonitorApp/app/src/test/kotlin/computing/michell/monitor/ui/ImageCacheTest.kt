package computing.michell.monitor.ui

/* Image request and cache decisions without a device (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImageCacheTest {
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
