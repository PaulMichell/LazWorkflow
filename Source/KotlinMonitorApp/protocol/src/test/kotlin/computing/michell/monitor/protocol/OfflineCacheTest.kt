package computing.michell.monitor.protocol

/* Offline browse copy round trip (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class OfflineCacheTest {
  @Test
  fun bodiesAndPlanRowsSurviveTheFileText() {
    val index = WireTurn(2, "turn-2", "build", "2026-10-22T12:00:00Z", "Compact the list", "")
    val body = index.copy(
      prompt = "Compact the list",
      response = "Done",
      blocks = listOf(WireBlock("answer", "", "", "", "", "Done", false, true, 0, emptyList()))
    )
    val live = WireTurn(-2, "live", "build", "", "Still writing", "", prompt = "Still writing", live = true)
    val document = OfflineCacheDocument(
      listOf(index),
      listOf(body),
      live,
      "Documents/Plan.md",
      "Release layout",
      listOf(PlanRow(1, 3, "Reduce padding", "", "in progress", true)),
      1,
      "unsent"
    )
    val decoded = decodeOfflineCache(encodeOfflineCache(document))
    assertNotNull(decoded)
    assertEquals("Compact the list", decoded!!.turns[0].promptPreview)
    assertEquals("", decoded.turns[0].response)
    assertEquals("Done", decoded.history[0].response)
    assertEquals("Still writing", decoded.live?.prompt)
    assertEquals("Release layout", decoded.planTitle)
    assertEquals("in progress", decoded.planRows[0].status)
    assertEquals(1, decoded.selectedPlan)
    assertEquals("unsent", decoded.draft)
  }

  @Test
  fun aBrokenCopyIsIgnored() {
    assertNull(decodeOfflineCache(""))
    assertNull(decodeOfflineCache("{"))
    assertNull(decodeOfflineCache("{}"))
  }
}
