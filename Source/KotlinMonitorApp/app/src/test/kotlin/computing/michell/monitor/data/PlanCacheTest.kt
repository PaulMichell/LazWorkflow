package computing.michell.monitor.data

/* Host plan cache round trip (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.PlanRow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PlanCacheTest {
  @Test
  fun aStoredPlanRoundTripsAndABlankCopyIsAbsent() {
    val row = PlanRow(0, 3, "Cache the plan", "Layout", "not started", true)
    val text = planCacheText("Documents/Plan.md", "Overview", listOf(row), 1)
    val stored = storedPlanOf("Documents/Plan.md", "Overview", 1, text)
    assertEquals("Overview", stored!!.title)
    assertEquals("Cache the plan", stored.rows.single().title)
    assertEquals(1, stored.selected)
    assertEquals("", stored.body)
    val withBody = storedPlanOf("Documents/Plan.md", "Overview", 1, planCacheText("Documents/Plan.md", "Overview", listOf(row), 1))
    assertEquals("", withBody!!.body)
    assertNull(storedPlanOf("", "", -1, planCacheText("", "", emptyList(), -1)))
  }

  @Test
  fun aDamagedRowListStillKeepsTheTitle() {
    val stored = storedPlanOf("Documents/Plan.md", "Overview", 0, "{")
    assertEquals("Overview", stored!!.title)
    assertEquals(0, stored.rows.size)
  }
}
