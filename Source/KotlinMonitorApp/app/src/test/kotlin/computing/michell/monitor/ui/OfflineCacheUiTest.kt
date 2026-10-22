package computing.michell.monitor.ui

/* Offline restore keeps browseable rows and disables remote actions (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.OfflineCacheDocument
import computing.michell.monitor.protocol.PlanRow
import computing.michell.monitor.protocol.WireTurn
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
