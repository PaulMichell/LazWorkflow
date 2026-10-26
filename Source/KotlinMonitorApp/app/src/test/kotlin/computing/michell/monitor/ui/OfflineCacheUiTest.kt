package computing.michell.monitor.ui

/* Offline restore keeps browseable rows and disables remote actions (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.OfflineCacheDocument
import computing.michell.monitor.protocol.PlanRow
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.encodeClosedScreen
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OfflineCacheUiTest {
  @Test
  fun aSavedSessionOpensOffline() {
    val document = OfflineCacheDocument(
      listOf(WireTurn(4, "turn-4", "build", "", "Anchor the composer", "")),
      emptyList(),
      null,
      "Documents/Plan.md",
      "Release layout",
      listOf(PlanRow(0, 3, "Anchor the composer", "", "not started", true)),
      0,
      "draft"
    )
    val restored = applyOfflineCache(MonitorUi(reachedLive = true), document, true)
    assertEquals("Release layout", restored.planTitle)
    assertEquals("Anchor the composer", restored.turns[0].promptPreview)
    assertEquals(0, restored.selectedPlan)
    assertEquals("draft", restored.draft)
    assertTrue(restored.disconnected)
    assertFalse(restored.reachedLive)
    assertFalse(restored.view.canSend)
    assertEquals(OfflineBanner, restored.banner)
    assertEquals("offline", connectionLabel(restored, computing.michell.monitor.connection.LinkPhase.Idle))
  }

  @Test
  fun aClosedFileIsNotDeletedWhenAnotherConversationIsFiled() {
    val directory = File.createTempFile("monitor-cache", "dir")
    directory.delete()
    directory.mkdirs()
    try {
      val store = OfflineStore(File(directory, "offline-cache.json"))
      val document = OfflineCacheDocument(emptyList(), emptyList(), null, "", "", emptyList(), -1, "")
      store.saveClosed("conversation-1", encodeClosedScreen("conversation-1", "Archived", document))
      store.saveClosed("conversation-2", encodeClosedScreen("conversation-2", "Next", document))
      val kept = File(directory, closedCacheName("conversation-1"))
      assertTrue(kept.isFile)
      assertTrue(kept.readText().contains("Archived"))
      store.clear()
      assertTrue(kept.isFile)
      assertEquals("", closedCacheName("../escape"))
    } finally {
      directory.deleteRecursively()
    }
  }

  @Test
  fun noAddressStillShowsTheCachedPlan() {
    val document = OfflineCacheDocument(
      emptyList(), emptyList(), null, "Documents/Plan.md", "Release layout",
      listOf(PlanRow(0, 2, "Layout", "", "", false)), -1, ""
    )
    val restored = applyOfflineCache(MonitorUi(), document, false)
    assertEquals("Release layout", restored.planTitle)
    assertEquals(NoAddressBanner, restored.banner)
    assertTrue(restored.disconnected)
  }
}
