package computing.michell.monitor.protocol

/* Cache index round trip. An unreadable index is null, not a crash. (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CacheIndexTest {
  @Test
  fun anIndexRoundTrips() {
    val entry = CacheIndexEntry(
      "ab".repeat(32),
      "/home/paul/Projects/LazWorkflow",
      "current",
      "Anchor the composer",
      1_700_000_000_000L,
      3,
      "c-" + "ab".repeat(32) + ".json",
      listOf(CacheImageNote("img-1", 12L, 40L))
    )
    val decoded = decodeCacheIndex(encodeCacheIndex(listOf(entry)))
    assertEquals(listOf(entry), decoded)
  }

  @Test
  fun anUnreadableIndexIsNull() {
    assertNull(decodeCacheIndex(""))
    assertNull(decodeCacheIndex("{"))
    assertNull(decodeCacheIndex("{}"))
    assertNull(decodeCacheIndex("{ \"entries\" : [ { \"fingerprint\" : \"\" } ] }"))
    assertNull(decodeCacheIndex("{ \"entries\" : [ { \"file\" : \"../escape.json\" } ] }"))
  }

  @Test
  fun aClosedScreenKeepsTheCacheDocument() {
    val document = OfflineCacheDocument(
      emptyList(), emptyList(), null, "Documents/Plan.md", "Release", emptyList(), -1, "draft"
    )
    val decoded = decodeClosedScreen(encodeClosedScreen("conversation-1", "Archived", document))
    assertEquals("Release", decoded?.planTitle)
    assertEquals("draft", decoded?.draft)
    assertEquals(document, decodeClosedScreen(encodeOfflineCache(document)))
  }
}
