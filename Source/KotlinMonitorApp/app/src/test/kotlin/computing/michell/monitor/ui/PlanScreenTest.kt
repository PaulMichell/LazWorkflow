package computing.michell.monitor.ui

/* Plan status tags match the assistant plan list (c) 2026 Michell Computing. */

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

  @Test
  fun sendTogglesToStopAndStaysOffWithoutAPlan() {
    assertFalse(planLoaded(""))
    assertTrue(planLoaded("Documents/Plan.md"))
    assertEquals("Run", planSendCaption(false))
    assertEquals("Stop", planSendCaption(true))
    assertFalse(planSendEnabled(false, true, false, false))
    assertFalse(planSendEnabled(true, false, true, false))
    assertFalse(planSendEnabled(true, true, false, true))
    assertTrue(planSendEnabled(true, true, false, false))
    assertTrue(planSendEnabled(true, true, true, true))
    assertFalse(planHostButtonEnabled(false, true))
    assertFalse(planHostButtonEnabled(true, false))
    assertTrue(planHostButtonEnabled(true, true))
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
}
