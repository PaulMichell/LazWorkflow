package computing.michell.monitor.ui

/* App menu sections: host check, empty lists, disconnect (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.PlanChoice
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AppMenuTest {
  @Test
  fun sectionsStayInDrawerOrder() {
    val labels = appMenuSections(sample()).map { it.label }
    assertEquals(
      listOf("Target", "Mode", "Conversation", "Plan", "Model", "Reasoning Level", "Tool Permissions"),
      labels
    )
  }

  @Test
  fun headerIsTheTargetDisplay() {
    assertEquals("Data Browser", menuHeader(sample()))
  }

  @Test
  fun missingListsAreOneQuietSentence() {
    val empty = appMenuSections(sample()).filter { it.rows.isEmpty() }
    assertEquals(
      listOf(MenuSectionKind.Target, MenuSectionKind.Conversation, MenuSectionKind.Model, MenuSectionKind.Reasoning, MenuSectionKind.Permissions),
      empty.map { it.kind }
    )
    assertEquals("Nothing to choose.", MenuEmptySentence)
    assertTrue(empty.all { it.rows.isEmpty() })
  }

  @Test
  fun modeAndPlanUseTheHostIdNotTheCaption() {
    val sections = appMenuSections(sample())
    val mode = sections.first { it.kind == MenuSectionKind.Mode }
    val plan = sections.first { it.kind == MenuSectionKind.Plan }
    assertEquals(listOf("Chat", "Inspect", "Document", "Plan", "Build"), mode.rows.map { it.caption })
    assertEquals("plan", menuCheckedId(mode.currentId))
    assertEquals(modeCaption("plan"), mode.rows.first { it.id == mode.currentId }.caption)
    assertEquals(listOf("Alpha", "Beta"), plan.rows.map { it.caption })
    assertEquals("a.md", menuCheckedId(plan.currentId))
    assertFalse(plan.rows.any { it.id == "missing.md" })
  }

  @Test
  fun anUnknownHostIdChecksNoRow() {
    val ui = sample().copy(view = sample().view.copy(mode = "weird"), planPath = "")
    val sections = appMenuSections(ui)
    val mode = sections.first { it.kind == MenuSectionKind.Mode }
    val plan = sections.first { it.kind == MenuSectionKind.Plan }
    assertEquals("weird", menuCheckedId(mode.currentId))
    assertTrue(mode.rows.none { it.id == mode.currentId })
    assertEquals("", menuCheckedId(plan.currentId))
    assertTrue(plan.rows.none { it.id == plan.currentId })
  }

  @Test
  fun currentRowClosesWithoutSending() {
    assertEquals(MenuTap.CloseOnly, menuTap("plan", "plan", true))
    assertEquals(MenuTap.CloseAndSend, menuTap("build", "plan", true))
    assertNull(menuTap("build", "plan", false))
  }

  @Test
  fun disconnectKeepsTheListsAndDisablesEveryRow() {
    val live = appMenuSections(sample())
    val down = appMenuSections(sample().copy(disconnected = true))
    assertEquals(live.first { it.kind == MenuSectionKind.Plan }.rows, down.first { it.kind == MenuSectionKind.Plan }.rows)
    assertEquals(live.first { it.kind == MenuSectionKind.Mode }.rows, down.first { it.kind == MenuSectionKind.Mode }.rows)
    assertTrue(down.all { !it.enabled })
    assertTrue(live.first { it.kind == MenuSectionKind.Mode }.enabled)
  }

  @Test
  fun aLockedModeDoesNotOfferASend() {
    val locked = appMenuSections(sample().copy(view = sample().view.copy(canChangeMode = false)))
    assertFalse(locked.first { it.kind == MenuSectionKind.Mode }.enabled)
    assertFalse(locked.first { it.kind == MenuSectionKind.Plan }.enabled)
    assertEquals(5, locked.first { it.kind == MenuSectionKind.Mode }.rows.size)
  }

  private fun sample(): MonitorUi {
    return MonitorUi(
      view = emptyView().copy(mode = "plan", canChangeMode = true, targetDisplay = "Data Browser"),
      planChoices = listOf(PlanChoice("a.md", "Alpha"), PlanChoice("b.md", "Beta")),
      planPath = "a.md"
    )
  }
}
