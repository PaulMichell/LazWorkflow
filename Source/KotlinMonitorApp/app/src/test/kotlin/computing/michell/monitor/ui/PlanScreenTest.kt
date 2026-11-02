package computing.michell.monitor.ui

/* Plan status tags match the assistant plan list (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.PlanRow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PlanScreenTest {
  @Test
  fun actionableStatusesUseTheAssistantTagColours() {
    val notStarted = planMarker("not started", true)
    assertEquals("Not Started", notStarted?.caption)
    assertEquals(0xFFFFF3CD.toInt(), notStarted?.fill)
    assertEquals(0xFF795500.toInt(), notStarted?.ink)
    assertEquals(0xFFD4A017.toInt(), notStarted?.border)

    val progress = planMarker("in progress", true)
    assertEquals("In Progress", progress?.caption)
    assertEquals(0xFFE8F5E9.toInt(), progress?.fill)
    assertEquals(0xFF1B5E20.toInt(), progress?.ink)
    assertEquals(0xFF43A047.toInt(), progress?.border)

    val complete = planMarker("complete", true)
    assertEquals("Complete", complete?.caption)
    assertEquals(0xFFE3F2FD.toInt(), complete?.fill)
    assertEquals(0xFF0D47A1.toInt(), complete?.ink)
    assertEquals(0xFF42A5F5.toInt(), complete?.border)

    val blocked = planMarker("blocked", true)
    assertEquals("Blocked", blocked?.caption)
    assertEquals(0xFFFFEBEE.toInt(), blocked?.fill)
    assertEquals(0xFFB71C1C.toInt(), blocked?.ink)
    assertEquals(0xFFE53935.toInt(), blocked?.border)
  }

  @Test
  fun headingsAndUnknownStatusesHaveNoTag() {
    assertNull(planMarker("complete", false))
    assertNull(planMarker("not started", false))
    assertNull(planMarker("unknown", true))
    assertNull(planMarker("pending", true))
    assertNull(planMarker("", true))
    assertNull(planMarker("   ", true))
  }

  /** Idle caption is Run. Running caption is Stop. Enable cases stay as written. */
  @Test
  fun runTogglesToStopAndStaysOffWithoutAPlan() {
    assertFalse(planLoaded(""))
    assertTrue(planLoaded("Documents/Plan.md"))
    assertEquals("Run", planRunCaption(false))
    assertEquals("Stop", planRunCaption(true))
    assertFalse(planRunEnabled(false, true, false, false))
    assertFalse(planRunEnabled(true, false, true, false))
    assertFalse(planRunEnabled(true, true, false, true))
    assertTrue(planRunEnabled(true, true, false, false))
    assertTrue(planRunEnabled(true, true, true, true))
    assertFalse(planHostButtonEnabled(false, true, false))
    assertFalse(planHostButtonEnabled(true, false, false))
    assertTrue(planHostButtonEnabled(true, true, false))
    assertFalse(planHostButtonEnabled(true, true, true))
    assertTrue(planNewEnabled(true, false))
    assertFalse(planNewEnabled(true, true))
    assertFalse(planNewEnabled(false, false))
    assertTrue(planOpenEnabled(true, false))
    assertFalse(planOpenEnabled(true, true))
    assertFalse(planOpenEnabled(false, false))
    assertEquals("Weekly limit", keptPlanBody("Documents/Plan.md", "Weekly limit", "Documents/Plan.md", ""))
    assertEquals("# Plan", keptPlanBody("Documents/Plan.md", "old", "Documents/Plan.md", "# Plan"))
    assertEquals("", keptPlanBody("Documents/Plan.md", "old", "Documents/Other.md", ""))
  }

  @Test
  fun trimmedDisplayCaptionStillTags() {
    val marker = planMarker("  Complete  ", true)
    assertEquals("Complete", marker?.caption)
    assertEquals(0xFF0D47A1.toInt(), marker?.ink)
  }

  @Test
  fun sectionPreviewIncludesChildItems() {
    val body = """
      # Plan

      ## One
      Context.

      ### 1.1 First
      Status: not started
      Do the first thing.

      ### 1.2 Second
      Status: complete
      Do the second thing.

      ## Two
      Later.
    """.trimIndent()
    val section = PlanRow(0, 2, "One", "", "unknown", false)
    val item = PlanRow(1, 3, "1.1 First", "One", "not started", true)
    assertEquals("One", planSectionCaption(section))
    assertEquals("One — 1.1 First", planSectionCaption(item))
    assertTrue(planSectionExcerpt(body, section).contains("### 1.2 Second"))
    assertFalse(planSectionExcerpt(body, section).contains("## Two"))
    assertTrue(planSectionExcerpt(body, item).contains("Do the first thing."))
    assertFalse(planSectionExcerpt(body, item).contains("### 1.2 Second"))
    assertEquals("", planSectionExcerpt("", item))
  }
}
