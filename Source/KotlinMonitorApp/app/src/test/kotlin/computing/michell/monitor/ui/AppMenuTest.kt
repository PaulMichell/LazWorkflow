package computing.michell.monitor.ui

/* App menu sections: host check, empty lists, disconnect (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.ConversationChoice
import computing.michell.monitor.protocol.ModelChoice
import computing.michell.monitor.protocol.PlanChoice
import computing.michell.monitor.protocol.ReasoningChoice
import computing.michell.monitor.protocol.TargetChoice
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
  fun targetSectionUsesChoiceCaptions() {
    val choices = listOf(TargetChoice("", "ignored"), TargetChoice("/work/Other", "Other"))
    val ui = sample().copy(
      view = sample().view.copy(targetDisplay = "LazWorkflow", targetKind = "project", targetRoot = "/work/LazWorkflow"),
      targetChoices = choices,
      targetCurrent = ""
    )
    val target = appMenuSections(ui).first { it.kind == MenuSectionKind.Target }
    assertEquals(listOf(CurrentProjectCaption, "Other"), target.rows.map { it.caption })
    assertEquals(listOf("", "/work/Other"), target.rows.map { it.id })
    assertEquals("", target.currentId)
    assertEquals("LazWorkflow", menuHeader(ui))
    assertEquals(MenuTap.CloseOnly, menuTap("", target.currentId, target.enabled))
    assertEquals(MenuTap.CloseAndSend, menuTap("/work/Other", target.currentId, target.enabled))
    assertTrue(target.enabled)
  }

  @Test
  fun aPackageTargetChecksNoRow() {
    val ui = sample().copy(
      view = sample().view.copy(targetDisplay = "Tools", targetKind = "package", targetRoot = "/work/Tools.lpk"),
      targetChoices = listOf(TargetChoice("", "Current Project"), TargetChoice("/work/Other", "Other")),
      targetCurrent = "/work/Tools.lpk"
    )
    val target = appMenuSections(ui).first { it.kind == MenuSectionKind.Target }
    assertTrue(target.rows.none { it.id == target.currentId })
    assertEquals("Tools", menuHeader(ui))
  }

  @Test
  fun targetRowsDisableWhileBusy() {
    assertFalse(targetRowsEnabled(true, false, false))
    assertFalse(targetRowsEnabled(false, true, false))
    assertFalse(targetRowsEnabled(false, false, true))
    assertTrue(targetRowsEnabled(false, false, false))
    val busy = sample().copy(
      view = sample().view.copy(sending = true),
      targetChoices = listOf(TargetChoice("", "Current Project")),
      targetCurrent = ""
    )
    assertFalse(appMenuSections(busy).first { it.kind == MenuSectionKind.Target }.enabled)
  }

  @Test
  fun conversationSectionUsesHistoryTitles() {
    val choices = listOf(
      ConversationChoice("", "Current — hello", true),
      ConversationChoice("20261019T120000000", "Older (2)", false)
    )
    val ui = sample().copy(conversationChoices = choices, conversationCurrent = "", conversationsTruncated = true)
    val section = appMenuSections(ui).first { it.kind == MenuSectionKind.Conversation }
    assertEquals(listOf("Current — hello", "Older (2)"), section.rows.map { it.caption })
    assertEquals(listOf("", "20261019T120000000"), section.rows.map { it.id })
    assertEquals("", section.currentId)
    assertEquals(MenuTap.CloseOnly, menuTap("", section.currentId, section.enabled))
    assertEquals(MenuTap.CloseAndSend, menuTap("20261019T120000000", section.currentId, section.enabled))
    assertEquals(OlderConversationsSentence, section.note)
    assertTrue(section.enabled)
    val byId = sample().copy(
      conversationChoices = listOf(ConversationChoice("archive-1", "Yesterday", false)),
      conversationCurrent = "archive-1"
    )
    assertEquals("archive-1", appMenuSections(byId).first { it.kind == MenuSectionKind.Conversation }.currentId)
  }

  @Test
  fun conversationRowsDisableWhileDisconnectedOrSending() {
    assertFalse(conversationRowsEnabled(true, false))
    assertFalse(conversationRowsEnabled(false, true))
    assertTrue(conversationRowsEnabled(false, false))
    val rows = listOf(ConversationChoice("", "Current", true))
    val sending = sample().copy(
      view = sample().view.copy(sending = true, planRunning = true),
      planRunning = true,
      conversationChoices = rows
    )
    val section = appMenuSections(sending).first { it.kind == MenuSectionKind.Conversation }
    assertFalse(section.enabled)
    assertEquals(rows.map { it.title }, section.rows.map { it.caption })
    val planning = sample().copy(view = sample().view.copy(planRunning = true), planRunning = true, conversationChoices = rows)
    assertTrue(appMenuSections(planning).first { it.kind == MenuSectionKind.Conversation }.enabled)
  }

  @Test
  fun modelSectionUsesCaptionsAndTheStatusModel() {
    val choices = listOf(ModelChoice("grok-4", "grok-4 — 256k context"), ModelChoice("grok-3", "grok-3"))
    val ui = sample().copy(
      view = sample().view.copy(model = "grok-4"),
      modelChoices = choices,
      modelBackend = "grok",
      modelNote = "The rest of this list is in desktop Settings."
    )
    val section = appMenuSections(ui).first { it.kind == MenuSectionKind.Model }
    assertEquals(listOf("grok-4 — 256k context", "grok-3"), section.rows.map { it.caption })
    assertEquals(listOf("grok-4", "grok-3"), section.rows.map { it.id })
    assertEquals("grok-4", section.currentId)
    assertEquals(MenuTap.CloseOnly, menuTap("grok-4", section.currentId, section.enabled))
    assertEquals(MenuTap.CloseAndSend, menuTap("grok-3", section.currentId, section.enabled))
    assertEquals("The rest of this list is in desktop Settings.", section.note)
    assertTrue(section.enabled)
  }

  @Test
  fun modelRowsDisableWhileDisconnectedSendingOrPlanning() {
    assertFalse(modelRowsEnabled(true, false, false))
    assertFalse(modelRowsEnabled(false, true, false))
    assertFalse(modelRowsEnabled(false, false, true))
    assertTrue(modelRowsEnabled(false, false, false))
    val rows = listOf(ModelChoice("grok-4", "grok-4"))
    val planning = sample().copy(
      view = sample().view.copy(planRunning = true, model = "grok-4"),
      planRunning = true,
      modelChoices = rows
    )
    val section = appMenuSections(planning).first { it.kind == MenuSectionKind.Model }
    assertFalse(section.enabled)
    assertEquals(listOf("grok-4"), section.rows.map { it.caption })
  }

  @Test
  fun reasoningSectionUsesTheStoredIdNotTheEffortCaption() {
    val choices = listOf(ReasoningChoice("", "Model default"), ReasoningChoice("high", "High"))
    val ui = sample().copy(
      view = sample().view.copy(effort = "Default"),
      reasoningChoices = choices,
      reasoningCurrent = "",
      reasoningNote = ""
    )
    val section = appMenuSections(ui).first { it.kind == MenuSectionKind.Reasoning }
    assertEquals("Reasoning Level", section.label)
    assertEquals(listOf("", "high"), section.rows.map { it.id })
    assertEquals(listOf("Model default", "High"), section.rows.map { it.caption })
    assertEquals("", section.currentId)
    assertEquals("", menuCheckedId(section.currentId))
    assertEquals(MenuTap.CloseOnly, menuTap("", section.currentId, section.enabled))
    assertEquals(MenuTap.CloseAndSend, menuTap("high", section.currentId, section.enabled))
    assertTrue(section.rows.any { it.id.isEmpty() })
    val captionOnly = ui.copy(view = ui.view.copy(effort = "High"))
    val still = appMenuSections(captionOnly).first { it.kind == MenuSectionKind.Reasoning }
    assertEquals("", still.currentId)
    assertEquals(choices.map { it.id }, still.rows.map { it.id })
  }

  @Test
  fun reasoningNoteDoesNotInventRows() {
    val ui = sample().copy(
      view = sample().view.copy(effort = "High"),
      reasoningNote = "This connection does not set an effort level."
    )
    val section = appMenuSections(ui).first { it.kind == MenuSectionKind.Reasoning }
    assertTrue(section.rows.isEmpty())
    assertEquals("This connection does not set an effort level.", section.note)
    assertEquals("", section.currentId)
  }

  @Test
  fun reasoningRowsDisableWhileDisconnectedSendingOrPlanning() {
    assertFalse(reasoningRowsEnabled(true, false, false))
    assertFalse(reasoningRowsEnabled(false, true, false))
    assertFalse(reasoningRowsEnabled(false, false, true))
    assertTrue(reasoningRowsEnabled(false, false, false))
    val rows = listOf(ReasoningChoice("high", "High"))
    val planning = sample().copy(
      view = sample().view.copy(planRunning = true, effort = "High"),
      planRunning = true,
      reasoningChoices = rows,
      reasoningCurrent = "high"
    )
    val section = appMenuSections(planning).first { it.kind == MenuSectionKind.Reasoning }
    assertFalse(section.enabled)
    assertEquals(listOf("High"), section.rows.map { it.caption })
    assertEquals("high", section.currentId)
  }

  @Test
  fun activePlanUsesTheChoiceList() {
    val plan = appMenuSections(sample()).first { it.kind == MenuSectionKind.Plan }
    assertEquals(listOf("Alpha", "Beta"), plan.rows.map { it.caption })
    assertEquals(listOf("a.md", "b.md"), plan.rows.map { it.id })
    assertEquals("a.md", plan.currentId)
    assertEquals(MenuTap.CloseOnly, menuTap(plan.currentId, plan.currentId, plan.enabled))
    assertEquals(MenuTap.CloseAndSend, menuTap("b.md", plan.currentId, plan.enabled))
    assertFalse(plan.rows.any { it.id == "not-in-list.md" })
    val empty = appMenuSections(sample().copy(planChoices = emptyList())).first { it.kind == MenuSectionKind.Plan }
    assertTrue(empty.rows.isEmpty())
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
