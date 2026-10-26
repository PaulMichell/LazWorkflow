package computing.michell.monitor.ui

/* monitor-cache directory: index, eviction, and the retired single file (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.OfflineCacheDocument
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.encodeClosedScreen
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CacheDirectoryTest {
  @Test
  fun anUnreadableIndexStartsEmpty() {
    val root = tempRoot()
    try {
      val directory = File(root, MonitorCacheDirectoryName)
      directory.mkdirs()
      File(directory, CacheIndexFileName).writeText("{")
      val store = OfflineStore(root)
      assertEquals(emptyList<String>(), store.loadIndex().map { it.conversationId })
      store.save("host-a", "/proj", "current", "Kept", screen("Kept"), emptyList(), 10L)
      assertEquals(listOf("current"), store.loadIndex().map { it.conversationId })
    } finally {
      root.deleteRecursively()
    }
  }

  @Test
  fun theTwentyFirstConversationDropsTheOldestAndItsImages() {
    val root = tempRoot()
    try {
      val store = OfflineStore(root, conversationCap = 20)
      val fingerprint = "aa".repeat(32)
      for (index in 1..21) {
        val images = if (index == 1) listOf(CacheImageBytes("img-old", byteArrayOf(1, 2, 3))) else emptyList()
        store.save(fingerprint, "/proj", "conversation-$index", "T$index", screen("T$index"), images, index.toLong())
      }
      val index = store.loadIndex()
      assertEquals(20, index.size)
      assertTrue(index.none { it.conversationId == "conversation-1" })
      assertTrue(index.any { it.conversationId == "conversation-21" })
      val dropped = cacheConversationFileName(fingerprint, "/proj", "conversation-1")
      assertFalse(File(store.directory, dropped).isFile)
      assertFalse(File(store.directory, dropped.removeSuffix(".json")).isDirectory)
      val other = "bb".repeat(32)
      store.save(other, "/other", "current", "Other", screen("Other"), emptyList(), 1L)
      store.save(fingerprint, "/proj", "conversation-22", "Newer", screen("Newer"), emptyList(), 30L)
      assertTrue(store.loadIndex().any { it.fingerprint == other && it.conversationId == "current" })
    } finally {
      root.deleteRecursively()
    }
  }

  @Test
  fun imageBytesOverTheCapEvictTheOldestFileFirst() {
    val root = tempRoot()
    try {
      val store = OfflineStore(root, imageBudgetBytes = 100L)
      val fingerprint = "cc".repeat(32)
      val other = "dd".repeat(32)
      store.save(fingerprint, "/proj", "one", "One", screen("One"), listOf(CacheImageBytes("img-old", ByteArray(60))), 1_000L)
      store.save(fingerprint, "/proj", "two", "Two", screen("Two"), listOf(CacheImageBytes("img-mid", ByteArray(60))), 3_000L)
      store.save(other, "/other", "current", "Other", screen("Other"), listOf(CacheImageBytes("img-keep", ByteArray(60))), 2_000L)
      store.save(fingerprint, "/proj", "two", "Two", screen("Two"), listOf(CacheImageBytes("img-new", ByteArray(60))), 5_000L)
      val kept = store.loadIndex().filter { it.fingerprint == fingerprint }
      val names = kept.flatMap { entry -> entry.images.map { it.imageId } }
      assertEquals(listOf("img-new"), names)
      assertNull(store.readImage(cacheConversationFileName(fingerprint, "/proj", "one"), "img-old"))
      val otherName = cacheConversationFileName(other, "/other", "current")
      assertEquals(60, store.readImage(otherName, "img-keep")?.size)
      val beside = File(store.directory, cacheConversationFileName(fingerprint, "/proj", "two").removeSuffix(".json"))
      assertTrue(File(beside, "img-new").isFile)
      assertFalse(File(beside, "img-mid").isFile)
    } finally {
      root.deleteRecursively()
    }
  }

  @Test
  fun forgetPairingDeletesOnlyThatFingerprint() {
    val root = tempRoot()
    try {
      val store = OfflineStore(root)
      val grouped = "ab".repeat(32).chunked(2).joinToString(":")
      val other = "cd".repeat(32)
      store.save(grouped, "/proj", "current", "Mine", screen("Mine"), listOf(CacheImageBytes("img-1", byteArrayOf(9))), 4L)
      store.save(other, "/other", "current", "Theirs", screen("Theirs"), listOf(CacheImageBytes("img-2", byteArrayOf(8))), 5L)
      store.forgetFingerprint("ab".repeat(32))
      val left = store.loadIndex()
      assertEquals(listOf(other), left.map { it.fingerprint })
      assertEquals("Theirs", left[0].title)
      assertEquals(1, store.readImage(left[0].fileName, "img-2")?.size)
    } finally {
      root.deleteRecursively()
    }
  }

  @Test
  fun theFirstDirectorySaveDeletesTheOldSingleFile() {
    val root = tempRoot()
    try {
      val legacy = File(root, LegacyOfflineCacheName)
      legacy.writeText("{\"turns\":[]}")
      File(root, LegacyOfflineCacheName + ".tmp").writeText("partial")
      val store = OfflineStore(root)
      store.save("host", "/proj", "current", "Now", screen("Now"), emptyList(), 8L)
      assertFalse(legacy.isFile)
      assertFalse(File(root, LegacyOfflineCacheName + ".tmp").isFile)
      assertTrue(File(store.directory, CacheIndexFileName).isFile)
      val filed = store.loadConversation(store.loadIndex().single().fileName)
      assertEquals("Now", filed?.planTitle)
      assertEquals(1, filed?.turns?.size)
      legacy.writeText("stale")
      store.save("host", "/proj", "current", "Now", screen("Now"), emptyList(), 9L)
      assertFalse(legacy.isFile)
    } finally {
      root.deleteRecursively()
    }
  }

  @Test
  fun switchingProjectRootDoesNotOverwriteThePreviousCurrent() {
    val root = tempRoot()
    try {
      val store = OfflineStore(root)
      store.save("host", "/old", "current", "Old title", screen("Old title"), emptyList(), 1L)
      store.save("host", "/work", "current", "New title", screen("New title"), emptyList(), 2L)
      val index = store.loadIndex()
      assertEquals(2, index.size)
      val old = index.single { it.projectRoot == "/old" }
      val next = index.single { it.projectRoot == "/work" }
      assertEquals("current", old.conversationId)
      assertEquals("current", next.conversationId)
      assertEquals("Old title", store.loadConversation(old.fileName)?.planTitle)
      assertEquals("New title", store.loadConversation(next.fileName)?.planTitle)
      store.save("host", "/work", "current", "Renamed", screen("Renamed"), emptyList(), 3L)
      val updated = store.loadIndex()
      assertEquals(2, updated.size)
      assertEquals("Renamed", updated.single { it.projectRoot == "/work" }.title)
      assertEquals("Old title", updated.single { it.projectRoot == "/old" }.title)
    } finally {
      root.deleteRecursively()
    }
  }

  @Test
  fun aClosedScreenIsFiledBesideItsImageId() {
    val root = tempRoot()
    try {
      val store = OfflineStore(root)
      val document = screen("Archived")
      store.saveClosed(
        "host-a",
        "/proj",
        "conversation-1",
        "Archived",
        encodeClosedScreen("conversation-1", "Archived", document),
        listOf(CacheImageBytes("shot-1", byteArrayOf(4, 5)))
      )
      val entry = store.loadIndex().single()
      assertEquals("conversation-1", entry.conversationId)
      assertEquals("/proj", entry.projectRoot)
      assertEquals("host-a", entry.fingerprint)
      assertEquals(1, entry.turnCount)
      assertTrue(entry.fileName.endsWith(".json"))
      assertEquals(2, store.readImage(entry.fileName, "shot-1")?.size)
    } finally {
      root.deleteRecursively()
    }
  }
}

private fun tempRoot(): File {
  val directory = File.createTempFile("monitor-cache", "dir")
  directory.delete()
  directory.mkdirs()
  return directory
}

private fun screen(title: String): OfflineCacheDocument {
  return OfflineCacheDocument(
    listOf(WireTurn(1, "turn-1", "build", "", title, "")),
    emptyList(),
    null,
    "",
    title,
    emptyList(),
    -1,
    ""
  )
}
