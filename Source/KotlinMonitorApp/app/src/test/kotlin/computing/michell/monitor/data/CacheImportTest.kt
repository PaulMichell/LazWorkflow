package computing.michell.monitor.data

/* Retired monitor-cache import (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.OfflineCacheDocument
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.encodeOfflineCache
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class CacheImportTest {
  @Test
  fun aReadableCachePlansSeqZeroAndACorruptFileKeepsTheIndex() {
    val root = tempRoot()
    try {
      val cache = File(root, MonitorCacheDirectoryName)
      val images = File(cache, "c-aa")
      images.mkdirs()
      File(images, "img-1").writeBytes(byteArrayOf(1, 2, 3))
      File(cache, "c-aa.json").writeText(encodeOfflineCache(document()))
      File(cache, CacheIndexFileName).writeText(index("host-1", "c-aa.json"))
      val plan = planLegacyImport(root)
      assertTrue(plan != null && plan.deleteDirectory)
      assertEquals(0L, storedScreen("host-1", "conversation-1", "/work", "Shown", 9L, plan!!.ready.single().document, 0L, "").conversation.seq)
      assertEquals("", storedScreen("host-1", "conversation-1", "/work", "Shown", 9L, plan.ready.single().document, 0L, "").conversation.streamId)
      assertEquals("img-1", plan.ready.single().images.single().first)
      File(cache, "c-aa.json").writeText("{")
      val blocked = planLegacyImport(root)
      assertTrue(blocked != null && !blocked!!.deleteDirectory)
      assertTrue(File(cache, CacheIndexFileName).isFile)
    } finally {
      root.deleteRecursively()
    }
  }

  @Test
  fun aMissingIndexIsLeftAlone() {
    val root = tempRoot()
    try {
      assertNull(planLegacyImport(root))
    } finally {
      root.deleteRecursively()
    }
  }

  private fun document(): OfflineCacheDocument {
    return OfflineCacheDocument(
      listOf(WireTurn(1, "t-1", "Build", "2026-10-29T09:20:00Z", "Add a heartbeat", "")),
      emptyList(),
      null,
      "",
      "",
      emptyList(),
      -1,
      "unsent"
    )
  }

  private fun index(host: String, fileName: String): String {
    return "{ \"entries\" : [ { \"fingerprint\" : \"$host\", \"project_root\" : \"/work\", \"conversation_id\" : \"conversation-1\", " +
      "\"title\" : \"Shown\", \"updated_ms\" : 9, \"turn_count\" : 1, \"file\" : \"$fileName\", \"images\" : [ { \"id\" : \"img-1\", \"bytes\" : 3, \"modified_ms\" : 9 } ] } ] }"
  }

  private fun tempRoot(): File {
    val root = File.createTempFile("monitor-cache", "dir")
    root.delete()
    root.mkdirs()
    return root
  }
}
