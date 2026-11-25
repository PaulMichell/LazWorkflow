package computing.michell.monitor.ui

/* App menu sections follow host capabilities (c) 2026 Michell Computing. */

import computing.michell.monitor.ui.model.ConversationChoice
import computing.michell.monitor.ui.model.MonitorUi
import computing.michell.monitor.ui.model.PlanChoice
import computing.michell.monitor.ui.model.TaskChoice
import computing.michell.monitor.ui.model.emptyView
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AppMenuTest {
  @Test
  fun menuChoicesWaitForAnEmptyConversationAndALiveLink() {
    val empty = sample()
    assertTrue(menuListStillEmpty(empty))
    assertTrue(menuChoicesNeeded(empty, true))
    assertFalse(menuChoicesNeeded(empty, false))
    assertFalse(menuChoicesNeeded(empty.copy(disconnected = true), true))
    val filled = empty.copy(conversationChoices = listOf(ConversationChoice("c1", "Chat", true)))
    assertFalse(menuListStillEmpty(filled))
    assertFalse(menuChoicesNeeded(filled, true))
    val withoutConversation = empty.copy(capabilities = KeptCommands - CommandSelectConversation)
    assertFalse(menuListStillEmpty(withoutConversation))
  }

  @Test
  fun omittedCapabilitiesHideModelReasoningTargetAndPermissions() {
    val labels = appMenuSections(sample()).map { it.label }
    assertEquals(listOf("Mode", "Conversation", "Plan", "Task"), labels)
    assertTrue(labels.none { it == "Model" || it == "Reasoning" || it == "Target" || it == "Tool Permissions" })
    assertTrue(appMenuSections(sample()).none { it.command == "set_model" || it.command == "set_reasoning" || it.command == "select_target" || it.command == "set_permissions" })
  }

  @Test
  fun aHostThatAdvertisesSetModelShowsAStub() {
    val ui = sample().copy(capabilities = KeptCommands + "set_model")
    val stub = appMenuSections(ui).first { it.command == "set_model" }
    assertTrue(stub.stub)
    assertEquals(MenuSectionKind.Stub, stub.kind)
    assertEquals("Model", stub.label)
    assertEquals(listOf(StubEntryCaption), stub.rows.map { it.caption })
    assertFalse(stub.enabled)
    val labels = appMenuSections(ui).map { it.label }
    assertEquals(listOf("Mode", "Conversation", "Plan", "Task", "Model"), labels)
  }

  @Test
  fun keptControlsStayHiddenUntilTheirCommandIsAdvertised() {
    val bare = appMenuSections(sample().copy(capabilities = emptySet()))
    assertTrue(bare.isEmpty())
    val modeOnly = appMenuSections(sample().copy(capabilities = setOf(CommandSetMode)))
    assertEquals(listOf(CommandSetMode), modeOnly.map { it.command })
  }

  @Test
  fun headerIsTheTargetDisplay() {
    assertEquals("Data Browser", menuHeader(sample()))
  }

  @Test
  fun missingListsAreOneQuietSentence() {
    val empty = appMenuSections(sample()).filter { it.rows.isEmpty() }
    assertEquals(listOf(MenuSectionKind.Conversation, MenuSectionKind.Task), empty.map { it.kind })
    assertEquals("Nothing to choose.", MenuEmptySentence)
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
  }

  @Test
  fun conversationRowsDisableWhileDisconnectedOrSending() {
    assertFalse(conversationRowsEnabled(true, false))
    assertFalse(conversationRowsEnabled(false, true))
    assertTrue(conversationRowsEnabled(false, false))
    val rows = listOf(ConversationChoice("", "Current", true))
    val sending = sample().copy(view = sample().view.copy(sending = true), conversationChoices = rows)
    val section = appMenuSections(sending).first { it.kind == MenuSectionKind.Conversation }
    assertFalse(section.enabled)
    assertEquals(rows.map { it.title }, section.rows.map { it.caption })
  }

  @Test
  fun taskSectionUsesTheStoredId() {
    val ui = sample().copy(
      taskChoices = listOf(TaskChoice("review", "Review"), TaskChoice("build", "Build")),
      taskCurrent = "review"
    )
    val section = appMenuSections(ui).first { it.kind == MenuSectionKind.Task }
    assertEquals(listOf("review", "build"), section.rows.map { it.id })
    assertEquals("review", section.currentId)
    assertEquals(MenuTap.CloseOnly, menuTap("review", section.currentId, section.enabled))
    assertEquals(MenuTap.CloseAndSend, menuTap("build", section.currentId, section.enabled))
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
  fun aHeadingTapOpensThatFlyoutAndASecondTapClosesIt() {
    assertEquals(CommandSetMode, menuFlyoutAfterTap(null, CommandSetMode))
    assertNull(menuFlyoutAfterTap(CommandSetMode, CommandSetMode))
    assertEquals(CommandSelectPlan, menuFlyoutAfterTap(CommandSetMode, CommandSelectPlan))
  }

  @Test
  fun backClosesTheFlyoutBeforeTheDrawer() {
    assertTrue(menuFlyoutConsumesBack(true))
    assertFalse(menuFlyoutConsumesBack(false))
  }

  @Test
  fun currentCaptionIsTheCheckedRow() {
    val plan = appMenuSections(sample()).first { it.kind == MenuSectionKind.Plan }
    assertEquals("Alpha", menuCurrentCaption(plan))
    assertEquals("", menuCurrentCaption(plan.copy(currentId = "missing")))
  }

  @Test
  fun flyoutSitsBesideTheHeadingsAndStaysOnScreen() {
    assertEquals(280, menuFlyoutWidthPx(16, 800, 164, 280, 8, 160, 48))
    assertEquals(200, menuFlyoutWidthPx(16, 436, 164, 280, 8, 160, 48))
    assertEquals(180, menuFlyoutWidthPx(16, 368, 164, 280, 8, 160, 48))
    assertEquals(280, menuFlyoutWidthPx(0, 320, 200, 280, 8, 160, 48))
    assertEquals(0, menuFlyoutWidthPx(0, 0, 164, 280, 8, 160, 48))
    val beside = menuFlyoutOrigin(16, 120, 800, 600, 164, 280, 200, 8)
    assertEquals(180, beside.x)
    assertEquals(120, beside.y)
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
}

private val KeptCommands = setOf(CommandSetMode, CommandSelectConversation, CommandSelectPlan, CommandRunTask)

private fun sample(): MonitorUi {
  return MonitorUi(
    view = emptyView().copy(mode = "plan", canChangeMode = true, targetDisplay = "Data Browser"),
    planChoices = listOf(PlanChoice("a.md", "Alpha"), PlanChoice("b.md", "Beta")),
    planPath = "a.md",
    capabilities = KeptCommands
  )
}
