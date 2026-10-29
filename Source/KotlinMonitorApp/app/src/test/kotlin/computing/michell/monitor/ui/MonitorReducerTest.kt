package computing.michell.monitor.ui

/* Catalogue reduction without a device (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.ConnectionRefusedBanner
import computing.michell.monitor.connection.HostClosedBanner
import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.connection.ReconnectingBanner
import computing.michell.monitor.protocol.ApprovalNotice
import computing.michell.monitor.protocol.MonitorLimits
import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTranscript
import computing.michell.monitor.protocol.splitTranscript
import computing.michell.monitor.protocol.PlanRow
import computing.michell.monitor.protocol.PlanChoice
import computing.michell.monitor.protocol.ConversationChoice
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.ModelChoice
import computing.michell.monitor.protocol.PermissionChoice
import computing.michell.monitor.protocol.ReasoningChoice
import computing.michell.monitor.protocol.TargetChoice
import computing.michell.monitor.protocol.encodeConversations
import computing.michell.monitor.protocol.encodeEnvelope
import computing.michell.monitor.protocol.encodeModels
import computing.michell.monitor.protocol.encodePath
import computing.michell.monitor.protocol.encodePermissions
import computing.michell.monitor.protocol.encodeReasoning
import computing.michell.monitor.protocol.encodeSelectConversation
import computing.michell.monitor.protocol.encodeSetModel
import computing.michell.monitor.protocol.encodeSetPermissions
import computing.michell.monitor.protocol.encodeSetReasoning
import computing.michell.monitor.protocol.encodeTargets
import computing.michell.monitor.protocol.statusToJson

import computing.michell.monitor.protocol.WireSnapshot
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.encodeApprovalClosed
import computing.michell.monitor.protocol.encodeApprovalRequested
import computing.michell.monitor.protocol.encodeError
import computing.michell.monitor.protocol.encodeImageUnavailable
import computing.michell.monitor.protocol.tryEncodeTranscript
import computing.michell.monitor.protocol.encodeInsertResult
import computing.michell.monitor.protocol.encodeTarget
import computing.michell.monitor.protocol.encodePlan
import computing.michell.monitor.protocol.encodeRejected
import computing.michell.monitor.protocol.encodeSnapshot
import computing.michell.monitor.protocol.encodeTurnData
import computing.michell.monitor.protocol.WirePatch
import computing.michell.monitor.protocol.WireCatchup
import computing.michell.monitor.protocol.encodePatch
import computing.michell.monitor.protocol.encodeCatchup
import computing.michell.monitor.protocol.encodeConversationClosed
import computing.michell.monitor.protocol.tryDecodeEnvelope
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MonitorReducerTest {
  @Test
  fun selectingAnotherPlanClearsTheOldWorkSelection() {
    val state = MonitorUi(planPath = "Documents/Old.md", selectedPlan = 7,
      planChoices = listOf(PlanChoice("Documents/Old.md", "Old")))
    val next = reduceMonitor(state, message(encodePlan("plan", "Documents/New.md", "New", false, emptyList())))
    assertEquals("Documents/New.md", next.planPath)
    assertEquals(-1, next.selectedPlan)
    assertTrue(next.planChoices.isEmpty())
  }

  @Test
  fun planResponseReplacesChoicesAndKeepsConversation() {
    val state = MonitorUi(planPath = "Documents/Plan.md", selectedPlan = 2, draft = "keep this")
    val frame = encodePlan("plan", state.planPath, "Plan", false, emptyList())
      .replace("\"rows\" : []", "\"rows\" : [], \"choices\" : [{\"path\":\"Plan.md\",\"caption\":\"Project plan\"}]")
    val next = reduceMonitor(state, message(frame))
    assertEquals(listOf(PlanChoice("Plan.md", "Project plan")), next.planChoices)
    assertEquals("keep this", next.draft)
    assertEquals(2, next.selectedPlan)
    val emptyFrame = frame.replace("[{\"path\":\"Plan.md\",\"caption\":\"Project plan\"}]", "[]")
    assertTrue(reduceMonitor(next, message(emptyFrame)).planChoices.isEmpty())
  }

  @Test
  fun targetChangeDropsChoicesFromThePreviousProject() {
    val keptTalk = listOf(ConversationChoice("archive-1", "Yesterday", false))
    val state = MonitorUi(view = emptyView().copy(targetRoot = "/old/"),
      selectedPlan = 3, planChoices = listOf(PlanChoice("Plan.md", "Old project")),
      targetChoices = listOf(TargetChoice("", "Current Project")), targetCurrent = "",
      conversationChoices = keptTalk)
    val same = reduceMonitor(state, message(encodeTarget("same", "project", "Old", "/old/")))
    assertEquals(state.planChoices, same.planChoices)
    assertEquals(state.targetChoices, same.targetChoices)
    assertEquals(keptTalk, same.conversationChoices)
    val next = reduceMonitor(state, message(encodeTarget("next", "project", "New", "/new/")))
    assertTrue(next.planChoices.isEmpty())
    assertTrue(next.targetChoices.isEmpty())
    assertEquals("", next.targetCurrent)
    assertTrue(next.conversationChoices.isEmpty())
    assertEquals(-1, next.selectedPlan)
    assertEquals("New", next.view.targetDisplay)
    assertEquals("", next.conversationCurrent)
    assertFalse(next.conversationsTruncated)
  }

  @Test
  fun conversationsFrameFillsHistoryAndLeavesTurnsAndDraft() {
    val turns = listOf(WireTurn(0, "stored", "chat", "", "older", ""))
    val state = MonitorUi(turns = turns, draft = "unsent", live = WireTurn(-2, "live", "chat", "", "now", ""))
    val frame = encodeConversations("conversations", "", listOf(
      ConversationChoice("", "Current — hello", true),
      ConversationChoice("20261019T120000000", "Older (2)", false)
    ), true)
    val next = reduceMonitor(state, message(frame))
    assertEquals("", next.conversationCurrent)
    assertTrue(next.conversationsTruncated)
    assertEquals(listOf(
      ConversationChoice("", "Current — hello", true),
      ConversationChoice("20261019T120000000", "Older (2)", false)
    ), next.conversationChoices)
    assertEquals(turns, next.turns)
    assertEquals("live", next.live?.id)
    assertEquals("unsent", next.draft)
  }

  @Test
  fun snapshotClearsTheMenuListsAndTheFollowingFramesFillThem() {
    val targets = listOf(TargetChoice("", "Current Project"))
    val talks = listOf(ConversationChoice("", "Current", true))
    val models = listOf(ModelChoice("grok-4", "grok-4"))
    val efforts = listOf(ReasoningChoice("high", "High"))
    val permissions = listOf(PermissionChoice("ask", "Ask before file changes and builds"))
    val start = MonitorUi(
      view = emptyView().copy(targetRoot = "/work", model = "grok-4", approvalCaption = "Ask"),
      targetChoices = targets,
      targetCurrent = "",
      conversationChoices = talks,
      modelChoices = models,
      modelBackend = "grok",
      modelNote = "The rest of this list is in desktop Settings.",
      reasoningChoices = efforts,
      reasoningCurrent = "high",
      permissionChoices = permissions,
      permissionCurrent = "ask",
      planChoices = listOf(PlanChoice("Plan.md", "Plan"))
    )
    val snapshot = WireSnapshot(
      start.view,
      emptyList(),
      WireTurn(-2, "live", "chat", "", "now", ""),
      "",
      "",
      false,
      emptyList(),
      emptyList(),
      ApprovalNotice(false, "", "", "", "", false)
    )
    val cleared = reduceMonitor(start, message(encodeSnapshot("snap", snapshot)))
    assertTrue(cleared.targetChoices.isEmpty())
    assertTrue(cleared.conversationChoices.isEmpty())
    assertTrue(cleared.modelChoices.isEmpty())
    assertEquals("", cleared.modelNote)
    assertTrue(cleared.reasoningChoices.isEmpty())
    assertEquals("", cleared.reasoningCurrent)
    assertTrue(cleared.permissionChoices.isEmpty())
    assertEquals("", cleared.permissionCurrent)
    assertTrue(cleared.planChoices.isEmpty())
    assertEquals("Ask", cleared.view.approvalCaption)
    assertFalse(cleared.disconnected)
    val withTargets = reduceMonitor(cleared, message(encodeTargets("targets", "", targets)))
    val withTalks = reduceMonitor(withTargets, message(encodeConversations("conversations", "", talks, false)))
    val withModels = reduceMonitor(withTalks, message(encodeModels(
      "models", "grok-4", "grok", "The rest of this list is in desktop Settings.", models
    )))
    val withEfforts = reduceMonitor(withModels, message(encodeReasoning("reasoning", "high", "", efforts)))
    val restored = reduceMonitor(withEfforts, message(encodePermissions("permissions", "ask", "codex", "", permissions)))
    assertEquals(targets, restored.targetChoices)
    assertEquals("", restored.targetCurrent)
    assertEquals(talks, restored.conversationChoices)
    assertEquals(models, restored.modelChoices)
    assertEquals("The rest of this list is in desktop Settings.", restored.modelNote)
    assertEquals(efforts, restored.reasoningChoices)
    assertEquals("high", restored.reasoningCurrent)
    assertEquals(permissions, restored.permissionChoices)
    assertEquals("ask", restored.permissionCurrent)
    val moved = reduceMonitor(restored, message(encodeTarget("next", "project", "New", "/new/")))
    assertTrue(moved.targetChoices.isEmpty())
    assertEquals("", moved.targetCurrent)
    assertTrue(moved.conversationChoices.isEmpty())
    assertEquals(models, moved.modelChoices)
    assertEquals("The rest of this list is in desktop Settings.", moved.modelNote)
    assertEquals(efforts, moved.reasoningChoices)
    assertEquals("high", moved.reasoningCurrent)
    assertEquals(permissions, moved.permissionChoices)
    assertEquals("ask", moved.permissionCurrent)
    val ignored = reduceMonitor(moved, message(encodeEnvelope(MessageKind.Permissions, "permissions-bad", null)))
    assertEquals(permissions, ignored.permissionChoices)
    assertFalse(ignored.disconnected)
  }

  @Test
  fun choosingTheCurrentIdEncodesNothingAndACaptionDoesNotMoveTheCheck() {
    val state = MonitorUi(
      view = emptyView().copy(model = "grok-4", effort = "Default", approvalCaption = "Always"),
      targetChoices = listOf(TargetChoice("", "Current Project"), TargetChoice("/other", "Other")),
      targetCurrent = "",
      conversationChoices = listOf(ConversationChoice("", "Current", true), ConversationChoice("arc", "Older", false)),
      conversationCurrent = "ignored",
      modelChoices = listOf(ModelChoice("grok-4", "grok-4"), ModelChoice("grok-3", "grok-3")),
      reasoningChoices = listOf(ReasoningChoice("", "Model default"), ReasoningChoice("high", "High")),
      reasoningCurrent = "",
      permissionChoices = listOf(
        PermissionChoice("ask", "Ask — confirm each write/compile"),
        PermissionChoice("auto", "Auto — allow project tools")
      ),
      permissionCurrent = "ask"
    )
    assertNull(targetSelectionCommand(state, "", "target-current"))
    assertNull(conversationSelectionCommand(state, "", "conversation-current"))
    assertNull(modelSelectionCommand(state, "grok-4", "model-current"))
    assertNull(reasoningSelectionCommand(state, "", "reasoning-current"))
    assertNull(permissionsSelectionCommand(state, "ask", "permissions-current"))
    assertEquals(
      encodePath(MessageKind.SelectTarget, "target-next", "/other"),
      targetSelectionCommand(state, "/other", "target-next")
    )
    assertEquals(
      encodeSelectConversation("conversation-next", "arc"),
      conversationSelectionCommand(state, "arc", "conversation-next")
    )
    assertEquals(encodeSetModel("model-next", "grok-3"), modelSelectionCommand(state, "grok-3", "model-next"))
    assertEquals(encodeSetReasoning("reasoning-next", "high"), reasoningSelectionCommand(state, "high", "reasoning-next"))
    val permissions = permissionsSelectionCommand(state, "auto", "permissions-next")
    assertNotNull(permissions)
    assertEquals(encodeSetPermissions("permissions-next", "auto"), permissions)
    assertFalse(permissions!!.contains("approval_decision"))
    val caption = reduceMonitor(state, message(encodeEnvelope(
      MessageKind.Status, "status-captions",
      statusToJson(emptyView().copy(effort = "High", approvalCaption = "Auto", model = "grok-3"))
    )))
    assertEquals("High", caption.view.effort)
    assertEquals("Auto", caption.view.approvalCaption)
    assertEquals("grok-3", caption.view.model)
    assertEquals("", caption.reasoningCurrent)
    assertEquals("ask", caption.permissionCurrent)
    assertEquals(state.reasoningChoices, caption.reasoningChoices)
    assertEquals(state.permissionChoices, caption.permissionChoices)
  }

  @Test
  fun snapshotReplacesTurnsAndKeepsAnUnsentDraft() {
    val kept = listOf(ConversationChoice("", "Current", true))
    val state = MonitorUi(
      view = emptyView().copy(targetRoot = "/work"),
      turns = listOf(WireTurn(0, "old", "chat", "", "gone", "")),
      draft = "still typing",
      conversationChoices = kept,
      conversationCurrent = ""
    )
    val snapshot = WireSnapshot(
      emptyView().copy(targetRoot = "/work", canSend = true),
      listOf(WireTurn(1, "new", "chat", "", "loaded", "")),
      WireTurn(-2, "live-2", "chat", "", "loaded", ""),
      "",
      "",
      false,
      emptyList(),
      emptyList(),
      ApprovalNotice(false, "", "", "", "", false)
    )
    val next = reduceMonitor(state, message(encodeSnapshot("snap", snapshot)))
    assertEquals("new", next.turns.single().id)
    assertEquals("still typing", next.draft)
    assertTrue(next.conversationChoices.isEmpty())
    assertEquals("", next.conversationCurrent)
    val moved = reduceMonitor(state, message(encodeSnapshot("moved", snapshot.copy(view = snapshot.view.copy(targetRoot = "/other")))))
    assertTrue(moved.conversationChoices.isEmpty())
    assertEquals("still typing", moved.draft)
    assertEquals("new", moved.turns.single().id)
  }

  @Test
  fun modelsFrameFillsTheListAndATargetChangeKeepsIt() {
    val choices = listOf(ModelChoice("grok-4", "grok-4 — 256k context"), ModelChoice("grok-3", "grok-3"))
    val frame = encodeModels("models", "grok-4", "grok", "The rest of this list is in desktop Settings.", choices)
    val filled = reduceMonitor(MonitorUi(view = emptyView().copy(model = "grok-4", targetRoot = "/old/")), message(frame))
    assertEquals(choices, filled.modelChoices)
    assertEquals("grok", filled.modelBackend)
    assertEquals("The rest of this list is in desktop Settings.", filled.modelNote)
    assertEquals("grok-4", filled.view.model)
    val moved = reduceMonitor(filled, message(encodeTarget("next", "project", "New", "/new/")))
    assertEquals(choices, moved.modelChoices)
    assertEquals("grok", moved.modelBackend)
    assertEquals("The rest of this list is in desktop Settings.", moved.modelNote)
    val status = encodeEnvelope(MessageKind.Status, "status-model", statusToJson(emptyView().copy(model = "grok-3")))
    val checked = reduceMonitor(moved, message(status))
    assertEquals("grok-3", checked.view.model)
    assertEquals(choices, checked.modelChoices)
  }

  @Test
  fun reasoningFrameIsTheCheckAndATargetOrEffortCaptionDoesNotReplaceIt() {
    val choices = listOf(
      ReasoningChoice("", "Model default"),
      ReasoningChoice("low", "Low"),
      ReasoningChoice("high", "High"),
      ReasoningChoice("xhigh", "XHigh")
    )
    val frame = encodeReasoning("reasoning", "", "", choices)
    val start = MonitorUi(view = emptyView().copy(effort = "Default", model = "grok-4", targetRoot = "/old/"))
    val filled = reduceMonitor(start, message(frame))
    assertEquals(choices, filled.reasoningChoices)
    assertEquals("", filled.reasoningCurrent)
    assertEquals("", filled.reasoningNote)
    assertEquals("Default", filled.view.effort)
    val moved = reduceMonitor(filled, message(encodeTarget("next", "project", "New", "/new/")))
    assertEquals(choices, moved.reasoningChoices)
    assertEquals("", moved.reasoningCurrent)
    val status = encodeEnvelope(MessageKind.Status, "status-effort", statusToJson(emptyView().copy(effort = "High", model = "grok-3")))
    val caption = reduceMonitor(moved, message(status))
    assertEquals("High", caption.view.effort)
    assertEquals("grok-3", caption.view.model)
    assertEquals("", caption.reasoningCurrent)
    assertEquals(choices, caption.reasoningChoices)
    val shrunk = listOf(ReasoningChoice("medium", "Medium"), ReasoningChoice("high", "High"))
    val next = reduceMonitor(caption, message(encodeReasoning("reasoning-next", "medium", "", shrunk)))
    assertEquals(shrunk, next.reasoningChoices)
    assertEquals("medium", next.reasoningCurrent)
    assertEquals("High", next.view.effort)
    val none = reduceMonitor(next, message(encodeReasoning(
      "reasoning-none", "", "This connection does not set an effort level.", emptyList()
    )))
    assertTrue(none.reasoningChoices.isEmpty())
    assertEquals("", none.reasoningCurrent)
    assertEquals("This connection does not set an effort level.", none.reasoningNote)
    assertEquals("High", none.view.effort)
  }

  @Test
  fun permissionsFrameIsTheCheckAndATargetOrApprovalCaptionDoesNotReplaceIt() {
    val choices = listOf(
      PermissionChoice("ask", "Ask before file changes and builds"),
      PermissionChoice("auto", "Auto: allow project tools"),
      PermissionChoice("always", "Always: allow registered tools")
    )
    val frame = encodePermissions("permissions", "ask", "codex", "", choices)
    val start = MonitorUi(view = emptyView().copy(approvalCaption = "Ask", targetRoot = "/old/"), approvalOpen = false)
    val filled = reduceMonitor(start, message(frame))
    assertEquals(choices, filled.permissionChoices)
    assertEquals("ask", filled.permissionCurrent)
    assertEquals("", filled.permissionNote)
    assertEquals("Ask", filled.view.approvalCaption)
    assertFalse(filled.approvalOpen)
    val moved = reduceMonitor(filled, message(encodeTarget("next", "project", "New", "/new/")))
    assertEquals(choices, moved.permissionChoices)
    assertEquals("ask", moved.permissionCurrent)
    val status = encodeEnvelope(
      MessageKind.Status, "status-approval", statusToJson(emptyView().copy(approvalCaption = "Always"))
    )
    val caption = reduceMonitor(moved, message(status))
    assertEquals("Always", caption.view.approvalCaption)
    assertEquals("ask", caption.permissionCurrent)
    assertEquals(choices, caption.permissionChoices)
    val notice = ApprovalNotice(true, "tool-1", "write_file", "short", "Build", true)
    val asked = reduceMonitor(caption, message(encodeApprovalRequested("approval", notice)))
    assertTrue(asked.approvalOpen)
    assertEquals("ask", asked.permissionCurrent)
    assertEquals(choices, asked.permissionChoices)
    val next = reduceMonitor(asked, message(encodePermissions("permissions-next", "always", "codex", "", choices)))
    assertEquals("always", next.permissionCurrent)
    assertEquals("Always", next.view.approvalCaption)
    assertTrue(next.approvalOpen)
    val none = reduceMonitor(next, message(encodePermissions(
      "permissions-none", "", "", "No connection is selected.", emptyList()
    )))
    assertTrue(none.permissionChoices.isEmpty())
    assertEquals("", none.permissionCurrent)
    assertEquals("No connection is selected.", none.permissionNote)
    assertEquals("Always", none.view.approvalCaption)
  }

  @Test
  fun targetsFrameFillsTheChoiceList() {
    val frame = encodeTargets("targets", "", listOf(TargetChoice("", "Current Project"), TargetChoice("/work/Other", "Other")))
    val next = reduceMonitor(MonitorUi(), message(frame))
    assertEquals("", next.targetCurrent)
    assertEquals(listOf(TargetChoice("", "Current Project"), TargetChoice("/work/Other", "Other")), next.targetChoices)
    assertTrue(next.planChoices.isEmpty())
  }

  @Test
  fun loadedBlockKeepsTheFullBody() {
    val body = "x".repeat(4000)
    val turn = WireTurn(1, "a", "chat", "", "", "", blocks = listOf(WireBlock("answer", "b", "", "", "", body, false, true, 0, emptyList())))
    assertEquals(body, shownBlocks(turn, true, true).single().body)
  }

  @Test
  fun snapshotReplacesViewPlanAndTurnIndex() {
    val snapshot = WireSnapshot(
      emptyView().copy(model = "grok-test", canSend = true, targetDisplay = "LazWorkflow", phase = "idle"),
      listOf(WireTurn(2, "turn-2", "build", "", "older", "")),
      WireTurn(3, "turn-3", "build", "", "live", "", blocks = emptyList()),
      "Documents/Plan.md",
      "Monitor plan",
      false,
      listOf(PlanRow(1, 1, "Codec", "", "pending", true)),
      emptyList(),
      ApprovalNotice(false, "", "", "", "", false)
    )
    val next = reduceMonitor(MonitorUi(draft = "keep", selectedPlan = 7,
      planChoices = listOf(PlanChoice("Old.md", "Old"))), message(encodeSnapshot("snapshot", snapshot)))
    assertTrue(next.planChoices.isEmpty())
    assertEquals(-1, next.selectedPlan)
    assertEquals("grok-test", next.view.model)
    assertEquals("LazWorkflow", next.view.targetDisplay)
    assertEquals("Documents/Plan.md", next.planPath)
    assertEquals(1, next.turns.size)
    assertEquals(3, next.live?.turnIndex)
    assertEquals("keep", next.draft)
    assertTrue(next.reachedLive)
  }

  @Test
  fun transcriptReplacesLiveBlocksOnlyWhenRevisionIsNewer() {
    val first = reduceMonitor(MonitorUi(), message(transcript(1, "one")))
    assertEquals("one", first.live?.blocks?.single()?.body)
    val older = reduceMonitor(first, message(transcript(1, "stale")))
    assertEquals("one", older.live?.blocks?.single()?.body)
    val newer = reduceMonitor(first, message(transcript(2, "two")))
    assertEquals("two", newer.live?.blocks?.single()?.body)
  }

  @Test
  fun turnDataFillsHistoryWithoutMovingTheView() {
    val turn = WireTurn(4, "turn-4", "build", "", "history", "", prompt = "full")
    val next = reduceMonitor(MonitorUi(selectedTurn = -1), message(encodeTurnData("turn-data", turn)))
    assertEquals("full", next.history[4]?.prompt)
    assertEquals(-1, next.selectedTurn)
  }

  @Test
  fun planPatchesThoseParts() {
    val planned = reduceMonitor(MonitorUi(), message(encodePlan("plan", "Documents/Plan.md", "Monitor", true, listOf(PlanRow(1, 1, "Row", "", "pending", true)))))
    assertEquals("Monitor", planned.planTitle)
    assertTrue(planned.planRunning)
  }

  @Test
  fun approvalOpensAndClosesAndInsertFillsThePrompt() {
    val notice = ApprovalNotice(true, "tool-1", "write_file", "short", "Build", true)
    val open = reduceMonitor(MonitorUi(draft = "old"), message(encodeApprovalRequested("approval", notice)))
    assertTrue(open.approvalOpen)
    assertEquals("write_file", open.approval?.toolName)
    val closed = reduceMonitor(open, message(encodeApprovalClosed("closed", "tool-1", "denied")))
    assertFalse(closed.approvalOpen)
    assertEquals("old", closed.draft)
    val filled = reduceMonitor(closed, message(encodeInsertResult("insert", "note text")))
    assertEquals("note text", filled.draft)
  }

  @Test
  fun rejectedAndSocketEofKeepTheDraft() {
    val kept = WireTurn(1, "a", "chat", "", "hi", "", prompt = "hi")
    val start = MonitorUi(draft = "unsent", reachedLive = true, turns = listOf(kept), history = mapOf(1 to kept))
    val rejected = reduceMonitor(start, message(encodeRejected("rejected", "protocol", 1, 1)))
    assertEquals("unsent", rejected.draft)
    assertTrue(rejected.disconnected)
    assertTrue(rejected.pairHold)
    val liveTurn = WireTurn(-2, "live", "chat", "", "hi", "", prompt = "hi", blocks = listOf(
      WireBlock("answer", "", "", "", "", "kept", false, true, 0, emptyList())
    ))
    val closed = noteSocketClosed(start.copy(live = liveTurn), HostClosedBanner)
    assertEquals("unsent", closed.draft)
    assertEquals("kept", closed.live?.blocks?.first()?.body)
    assertEquals(HostClosedBanner, closed.banner)
    assertTrue(closed.disconnected)
    assertEquals(start.turns, closed.turns)
    assertEquals(start.history, closed.history)
    assertFalse(closed.view.canSteer)
    assertFalse(closed.view.canSend)
    assertEquals(1, closed.generation)
    val again = noteSocketClosed(closed, HostClosedBanner)
    assertEquals(closed.generation, again.generation)
  }

  @Test
  fun imageUnavailableNamesTheReasonAndLeavesTheSessionUp() {
    val next = reduceMonitor(MonitorUi(reachedLive = true), message(encodeImageUnavailable("image", "tile-1", "missing")))
    assertEquals("missing", next.imageReasons["tile-1"])
    assertFalse(next.disconnected)
    assertTrue(next.reachedLive)
  }

  @Test
  fun actionCaptionFollowsCanSteerAndCanSendNotBusy() {
    val busySteer = emptyView().copy(busy = true, canSteer = true, canSend = false)
    assertEquals("Steer", actionCaption(busySteer))
    assertTrue(actionEnabled(busySteer))
    val send = emptyView().copy(busy = true, canSteer = false, canSend = true)
    assertEquals("Send", actionCaption(send))
    val neither = emptyView().copy(busy = false, canSend = false, canSteer = false)
    assertEquals("Send", actionCaption(neither))
    assertFalse(actionEnabled(neither))
  }

  @Test
  fun droppedConnectionClearsSteerAndANewerSnapshotWins() {
    val steering = MonitorUi(view = emptyView().copy(canSteer = true, canSend = false, sending = true), generation = 2)
    val closed = noteSocketClosed(steering, HostClosedBanner)
    assertFalse(closed.view.canSteer)
    assertFalse(actionEnabled(closed.view))
    assertEquals("Send", actionCaption(closed.view))
    val stale = closed.copy(view = steering.view, generation = closed.generation - 1)
    val kept = mergeApplied(closed, stale, false, false)
    assertFalse(kept.view.canSteer)
    val snapshot = WireSnapshot(
      emptyView().copy(canSend = true, canSteer = false, model = "grok-test"),
      emptyList(),
      null,
      "",
      "",
      false,
      emptyList(),
      emptyList(),
      ApprovalNotice(false, "", "", "", "", false)
    )
    val live = reduceMonitor(closed, message(encodeSnapshot("snapshot", snapshot)))
    assertTrue(live.view.canSend)
    assertFalse(live.view.canSteer)
    assertTrue(live.generation > closed.generation)
    val shown = mergeApplied(closed, live, false, true)
    assertEquals("grok-test", shown.view.model)
    assertTrue(shown.view.canSend)
    assertFalse(shown.disconnected)
  }

  @Test
  fun sendClearsTheDraftAndShowsThePromptBeforeTheHostReplies() {
    val start = MonitorUi(draft = "fix the form", view = emptyView().copy(canSend = true, signedIn = true, model = "grok-4", backend = "grok"))
    val next = beginSubmit(start, "fix the form", false, 1_000L)
    assertEquals("", next.draft)
    assertEquals("fix the form", next.pendingPrompt)
    assertEquals("user", next.pendingKind)
    assertEquals(PhaseWaiting, next.view.phase)
    assertFalse(promptShown(next, next.pendingPrompt))
    val echoed = next.copy(live = WireTurn(-2, "live", "build", "", "fix the form", "", prompt = "fix the form", blocks = listOf(
      WireBlock("user", "u", "", "", "", "fix the form", false, true, 0, emptyList())
    )))
    val merged = mergeApplied(next, echoed, false, false)
    assertEquals("fix the form", merged.pendingPrompt)
    assertEquals("grok-4", runtimeCaption(next.view))
    assertEquals("Waiting… 0:02", activityCaption(next.view, true, "user", 1_000L, 3_000L))
    assertEquals("Ready", activityCaption(emptyView().copy(signedIn = true, statusText = "Ready"), false, "", 0L, 3_000L))
    assertEquals("Offline", activityCaption(emptyView().copy(signedIn = false, statusText = "Not signed in"), false, "", 0L, 3_000L))
    val thought = WireBlock("thinking", "t", "", "", "", "hmm", true, true, 0, emptyList())
    val live = WireTurn(-2, "live", "build", "", "", "", live = true, blocks = listOf(thought))
    assertEquals("Thinking… 0:04", activityCaption(
      emptyView().copy(signedIn = true, statusText = "Ready", canSend = true),
      false, "", 1_000L, 5_000L, listOf(thought), live
    ))
    val now = 1_700_000_000_000L
    assertEquals(now - 724_000L, activityStart(now - 2_000L, now, 724_000, 0))
    assertEquals(now - 20_000L, activityStart(now - 20_000L, now, 10_000, 9_000))
    val running = MonitorUi(
      disconnected = true,
      view = emptyView().copy(sending = true, busy = true, phase = "Thinking…", statusText = "Thinking… 0:12", elapsedMs = 12_000)
    )
    assertTrue(displayInterrupted(running, LinkPhase.Disconnected))
    assertFalse(displayInterrupted(running.copy(disconnected = false), LinkPhase.Live))
    assertEquals("Offline", activityCaption(
      running.view, false, "", now - 12_000L, now, listOf(thought), live,
      ideLinkLive(running.disconnected, LinkPhase.Disconnected)
    ))
    assertEquals("Offline", activityCaption(
      emptyView().copy(signedIn = true, statusText = "Ready"), false, "", 0L, now, emptyList(), null,
      ideLinkLive(true, LinkPhase.Live)
    ))
    assertTrue(hostTranscriptIdle("", "Ready"))
    assertTrue(hostTranscriptIdle("", "Offline"))
    assertTrue(hostTranscriptIdle("Offline", "Not signed in"))
    assertFalse(hostTranscriptIdle("Thinking…", "Offline"))
    assertEquals("Thinking… 12:04", activityCaption(
      emptyView().copy(sending = true, phase = "Thinking…", statusText = "Ready"),
      false, "", now - 724_000L, now, listOf(thought), live
    ))
    val ticking = emptyView().copy(busy = true, phase = "Thinking…", signedIn = true, elapsedMs = 4_000)
    val first = notePatchClock(MonitorUi(view = ticking), 4_000, false, 10_000L)
    assertEquals(6_000L, first.activityStartedMs)
    assertEquals("Thinking… 0:07", activityCaption(ticking, false, "", first.activityStartedMs, 13_000L))
    val replaced = notePatchClock(first, 1_000, false, 20_000L)
    assertEquals(19_000L, replaced.activityStartedMs)
    assertEquals("Thinking… 0:02", activityCaption(ticking.copy(elapsedMs = 1_000), false, "", replaced.activityStartedMs, 21_000L))
    val idleView = emptyView().copy(signedIn = true, statusText = "Thinking… 0:12", elapsedMs = 0)
    val idle = notePatchClock(replaced, 0, true, 22_000L)
    assertEquals(0L, idle.activityStartedMs)
    val answer = WireBlock("answer", "a", "", "", "", "done", false, true, 0, emptyList())
    assertFalse(turnStillRunning(idleView, false, listOf(answer), live))
    assertEquals("Ready", activityCaption(idleView, false, "", idle.activityStartedMs, 30_000L, listOf(answer), live))
  }

  @Test
  fun reconnectingClearsWhenTheLinkReturns() {
    val closed = noteSocketClosed(MonitorUi(reachedLive = true, banner = ""), ReconnectingBanner)
    assertEquals(ReconnectingBanner, closed.banner)
    assertTrue(closed.disconnected)
    assertEquals("disconnected", connectionLabel(closed, LinkPhase.Disconnected))
    val back = applyLink(closed, LinkPhase.Connecting, "")
    assertEquals(ConnectingBanner, back.banner)
    assertTrue(back.disconnected)
    assertEquals("connecting", connectionLabel(back, LinkPhase.Connecting))
    val live = applyLink(back, LinkPhase.Live, "")
    assertEquals("", live.banner)
    assertFalse(live.disconnected)
    val recovered = applyLink(noteSocketClosed(MonitorUi(reachedLive = true), ConnectionRefusedBanner), LinkPhase.Live, "")
    assertEquals("", recovered.banner)
    assertFalse(recovered.disconnected)
    val idle = applyLink(MonitorUi(banner = OfflineBanner, disconnected = true, turns = listOf(WireTurn(1, "a", "build", "", "Row", ""))), LinkPhase.Idle, "")
    assertTrue(idle.disconnected)
    assertEquals(OfflineBanner, idle.banner)
    assertEquals("Row", idle.turns[0].promptPreview)
    assertEquals("offline", connectionLabel(idle, LinkPhase.Idle))
  }

  @Test
  fun steerWithNoConversationBecomesASend() {
    val start = MonitorUi(draft = "finish the form", view = emptyView().copy(canSteer = true, canSend = false))
    val next = reduceMonitor(start, message(encodeError("err", "command", NothingRunningToSteer, "steer-1")))
    assertTrue(next.rescueSteer)
    assertFalse(next.view.canSteer)
    assertTrue(next.view.canSend)
    assertEquals("", next.banner)
    assertEquals("finish the form", next.draft)
  }

  @Test
  fun virtualExtentKeepsTheIndexAndFetchesOnlyTheRecentTail() {
    val older = WireTurn(1, "a", "build", "", "first prompt", "")
    val newer = WireTurn(2, "b", "build", "", "second prompt", "")
    val slots = virtualSlots(listOf(older, newer), WireTurn(-2, "live", "build", "", "", ""), false)
    assertEquals(2, slots.size)
    val keptRows = virtualSlots(listOf(older, newer), WireTurn(2, "b", "build", "", "", ""), false)
    assertEquals(2, keptRows.size)
    assertFalse(keptRows[1].live)
    assertEquals("first prompt", slots[0].label)
    assertEquals(listOf(1, 2), recentFetches(slots, emptySet()))
    assertEquals(listOf(1), recentFetches(slots, setOf(2)))
    val spot = spotAt(listOf(1, 1, 8), 0.9f)
    assertEquals(2, spot.index)
    assertTrue(spot.unitOffset > 0)
    assertEquals(0, spotAt(listOf(1, 1, 8), 0.01f).index)
    assertEquals(500, scrollOffset(1000, 0.5f))
    assertEquals(1000, scrollOffset(1000, 1f))
    assertEquals(1f, scrollFraction(40, 0))
    assertTrue(atHead(1000, 1000))
    assertTrue(atHead(0, 0))
    assertFalse(atHead(900, 1000))
    assertTrue(stickToHead(true, 400, 400, 400, 900, false))
    assertFalse(stickToHead(true, 400, 200, 400, 900, false))
    assertTrue(stickToHead(false, 200, 900, 900, 900, false))
    val kept = WireTurn(2, "b", "build", "", "second prompt", "", prompt = "kept", blocks = listOf(WireBlock("answer", "b", "", "", "", "body", false, true, 0, emptyList())))
    val start = MonitorUi(draft = "half written", turns = listOf(older, newer), history = mapOf(2 to kept), reachedLive = true)
    val snapshot = WireSnapshot(
      emptyView().copy(model = "grok-test", canSend = true),
      listOf(older, newer),
      WireTurn(-2, "live", "build", "", "", ""),
      "",
      "",
      false,
      emptyList(),
      emptyList(),
      ApprovalNotice(false, "", "", "", "", false)
    )
    val next = reduceMonitor(start, message(encodeSnapshot("snapshot", snapshot)))
    assertEquals("half written", next.draft)
    assertEquals("kept", next.history[2]?.prompt)
    assertEquals("body", next.history[2]?.blocks?.single()?.body)
    assertTrue(next.reachedLive)
    assertFalse(next.disconnected)
    assertEquals("Chat", modeCaption("chat"))
    assertEquals("Build", modeCaption("build"))
    val hidden = shownBlocks(kept.copy(blocks = listOf(
      WireBlock("thinking", "t", "", "", "", "secret", false, true, 0, emptyList()),
      WireBlock("tool", "tool", "", "grep", "", "args", false, true, 0, emptyList()),
      WireBlock("answer", "a", "", "", "", "shown", false, true, 0, emptyList())
    )), false, false)
    assertEquals(listOf("answer"), hidden.map { it.kind })
  }

  @Test
  fun splitTranscriptKeepsThinkingAsOneBlockBeforeTheAnswer() {
    val thinking = "A".repeat(MonitorLimits.MaxBodyPartBytes) + "TAIL"
    val answer = "short answer"
    val frames = splitLongTurn(thinking, answer, 1)
    assertTrue(frames.size > 1)
    assertTrue(frames[0].blocks.any { it.kind == "thinking" })
    assertTrue(frames[0].blocks.any { it.kind == "answer" })
    assertTrue(frames[1].blocks.any { it.kind == "thinking" })
    assertFalse(frames[1].blocks.any { it.kind == "answer" })
    val shown = reduceTranscripts(frames)
    assertEquals(listOf("thinking", "answer"), shown.live?.blocks?.map { it.kind })
    assertEquals(thinking, shown.live?.blocks?.get(0)?.body)
    assertEquals(answer, shown.live?.blocks?.get(1)?.body)
  }

  @Test
  fun outOfOrderTranscriptPartsDoNotDuplicateTheThinkingBody() {
    val thinking = "A".repeat(MonitorLimits.MaxBodyPartBytes) + "TAIL"
    val answer = "short answer"
    val frames = splitLongTurn(thinking, answer, 3)
    val shown = reduceTranscripts(frames.reversed())
    val blocks = shown.live?.blocks ?: emptyList()
    assertEquals(listOf("thinking", "answer"), blocks.map { it.kind })
    assertEquals(thinking, blocks[0].body)
    assertEquals(answer, blocks[1].body)
    assertEquals(1, blocks.count { it.body.contains("TAIL") })
  }

  @Test
  fun duplicateTranscriptPartIsKeptOnce() {
    val piece = WireBlock("thinking", "think-1", "", "", "", "once", true, true, 0, emptyList(), false, 1, 2, 4)
    val frames = listOf(
      WireTranscript(-2, 4, "thinking", "working", listOf(piece), 1, 2, 0),
      WireTranscript(-2, 4, "thinking", "working", listOf(piece.copy(body = "ONCE")), 2, 2, 0)
    )
    val shown = reduceTranscripts(frames)
    assertEquals(listOf("once"), shown.live?.blocks?.map { it.body })
  }

  @Test
  fun missingTranscriptPartDoesNotJumpAhead() {
    val thinking = "A".repeat(MonitorLimits.MaxBodyPartBytes) + "TAIL"
    val frames = splitLongTurn(thinking, "short answer", 5)
    val held = reduceTranscripts(listOf(frames[1]))
    assertTrue(held.live?.blocks.orEmpty().none { it.body.contains("TAIL") })
    val shown = reduceTranscripts(frames.reversed())
    assertEquals(thinking, shown.live?.blocks?.first()?.body)
    assertEquals("short answer", shown.live?.blocks?.get(1)?.body)
  }

  @Test
  fun inconsistentPartCountDropsTheBlockInsteadOfJoiningIt() {
    val head = WireBlock("thinking", "think-1", "", "", "", "one", true, true, 0, emptyList(), false, 1, 2, 6)
    val tail = WireBlock("thinking", "think-1", "", "", "", "two", true, true, 0, emptyList(), false, 2, 3, 6)
    val answer = WireBlock("answer", "answer-1", "", "", "", "kept", false, true, 0, emptyList())
    val frames = listOf(
      WireTranscript(-2, 6, "thinking", "working", listOf(head, answer), 1, 2, 0),
      WireTranscript(-2, 6, "thinking", "working", listOf(tail), 2, 2, 0)
    )
    val shown = reduceTranscripts(frames)
    assertEquals(listOf("kept"), shown.live?.blocks?.map { it.body })
  }

  @Test
  fun revisionReplacementRemovesTheOldTranscriptBody() {
    val thinking = "A".repeat(MonitorLimits.MaxBodyPartBytes) + "TAIL"
    val first = reduceTranscripts(splitLongTurn(thinking, "short answer", 1))
    assertEquals(thinking, first.live?.blocks?.first()?.body)
    val replacement = WireTranscript(
      -2,
      2,
      "thinking",
      "working",
      listOf(WireBlock("thinking", "think-1", "", "", "", "replaced", false, true, 0, emptyList())),
      1,
      1,
      0
    )
    val shown = reduceTranscripts(listOf(replacement), first)
    assertEquals("replaced", shown.live?.blocks?.single()?.body)
    assertFalse(shown.live?.blocks?.any { it.body.contains("TAIL") } == true)
  }

  @Test
  fun aLiveReduceDoesNotRestoreTheOfflineBanner() {
    val shown = MonitorUi(banner = "", disconnected = false, reachedLive = true)
    val cached = shown.copy(banner = OfflineBanner, disconnected = true)
    val kept = mergeApplied(shown, cached, false, false)
    assertEquals("", kept.banner)
    assertFalse(kept.disconnected)
    val status = shown.copy(banner = "", disconnected = false, view = emptyView().copy(canSteer = true))
    val cleared = mergeApplied(cached, status, false, false)
    assertEquals("", cleared.banner)
    assertFalse(cleared.disconnected)
    assertTrue(cleared.view.canSteer)
  }

  @Test
  fun anUnchangedSnapshotKeepsTheDisplayedConversation() {
    val blocks = listOf(WireBlock("answer", "a", "", "", "", "kept", false, true, 0, emptyList()))
    val live = WireTurn(-2, "live", "build", "", "prompt", "", blocks = blocks)
    val start = MonitorUi(live = live, turns = listOf(WireTurn(0, "stored", "build", "", "older", "")), reachedLive = true)
    val again = mergeLiveTurn(live, live.copy(), true)
    assertTrue(again === live)
    val snapshot = WireSnapshot(
      emptyView().copy(model = "grok-4.7", canSend = true),
      start.turns,
      null,
      "",
      "",
      false,
      emptyList(),
      emptyList(),
      ApprovalNotice(false, "", "", "", "", false)
    )
    val next = reduceMonitor(start, message(encodeSnapshot("snap", snapshot)))
    assertTrue(next.live === live)
    assertEquals("kept", next.live?.blocks?.single()?.body)
    assertEquals(1, next.turns.size)
  }

  @Test
  fun incompleteReconnectStreamDoesNotWipeTheDisplayedConversation() {
    val shown = listOf(
      WireBlock("user", "u", "", "", "", "question", false, true, 0, emptyList()),
      WireBlock("answer", "a", "", "", "", "answer", false, true, 0, emptyList())
    )
    val start = MonitorUi(
      live = WireTurn(-2, "live", "build", "", "question", "", blocks = shown),
      reachedLive = true,
      disconnected = true
    )
    val partial = WireTranscript(
      -2, 1, "thinking", "working",
      listOf(WireBlock("thinking", "t", "", "", "", "more", true, true, 0, emptyList())),
      1, 2, 0
    )
    val next = reduceTranscripts(listOf(partial), start)
    assertEquals(shown, next.live?.blocks)
  }

  @Test
  fun patchCursorAssemblesPartsAndDoesNotGuessAGap() {
    val shown = WireTurn(1, "turn-1", "build", "", "Shown", "", blocks = listOf(answerBlock("keep")))
    val start = MonitorUi(
      hostEpoch = "aa",
      turns = listOf(shown),
      live = shown,
      view = emptyView().copy(busy = true, sending = true, planRunning = true, statusText = "Thinking…", phase = "thinking")
    )
    val partial = reduceMonitor(start, message(patchFrame("aa", 1, "one", 1, 2, true)))
    assertEquals(0L, partial.hostCursor)
    assertEquals("one", partial.live?.blocks?.single()?.body)
    assertEquals("Shown", partial.turns[0].promptPreview)
    val done = reduceMonitor(partial, message(patchFrame("aa", 1, "two", 2, 2, false)))
    assertEquals(1L, done.hostCursor)
    assertTrue(done.live?.blocks?.single()?.body?.contains("one") == true)
    assertTrue(done.live?.blocks?.single()?.body?.contains("two") == true)
    assertFalse(done.view.busy)
    assertFalse(done.view.sending)
    assertFalse(done.view.planRunning)
    assertEquals("Thinking…", done.view.statusText)
    assertEquals("live", connectionLabel(done, LinkPhase.Live))
    val lower = reduceMonitor(done, message(patchFrame("aa", 0, "old", 1, 1, true)))
    assertEquals(1L, lower.hostCursor)
    assertFalse(lower.view.busy)
    assertFalse(lower.live?.blocks?.single()?.body?.contains("old") == true)
    val gap = reduceMonitor(done, message(patchFrame("aa", 4, "missing", 1, 1, true)))
    assertTrue(gap.resumeOnce)
    assertEquals(1L, gap.hostCursor)
    assertFalse(gap.live?.blocks?.single()?.body?.contains("missing") == true)
    val again = reduceMonitor(gap, message(patchFrame("aa", 9, "later", 1, 1, true)))
    assertTrue(again.resumeOnce)
    val transcript = reduceMonitor(done, message(transcript(9, "stale-transcript")))
    assertEquals(done.live?.blocks, transcript.live?.blocks)
    val other = reduceMonitor(done, message(patchFrame("bb", 1, "new-epoch", 1, 1, false)))
    assertTrue(other.catchingUp)
    assertEquals("aa", other.hostEpoch)
    assertEquals("Shown", other.turns[0].promptPreview)
    assertFalse(other.live?.blocks?.single()?.body?.contains("new-epoch") == true)
  }

  @Test
  fun catchupSwitchesTheOpenKeyAndClosedKeepsTheScreen() {
    val shown = WireTurn(1, "turn-1", "build", "", "Shown", "")
    val start = MonitorUi(
      hostEpoch = "aa",
      hostCursor = 4,
      conversationId = "current",
      projectRoot = "/old",
      turns = listOf(shown),
      live = shown
    )
    val closed = reduceMonitor(start, message(encodeConversationClosed("closed", "aa", 4, "conversation-1", "Archived")))
    assertEquals("conversation-1", closed.closedConversationId)
    assertEquals("Archived", closed.closedTitle)
    assertFalse(closed.closedPending)
    assertEquals("Shown", closed.turns[0].promptPreview)
    assertEquals(shown, closed.live)
    val snapshot = WireSnapshot(
      emptyView().copy(canSend = true, phase = "idle"),
      listOf(WireTurn(2, "turn-2", "build", "", "Next", "")),
      WireTurn(3, "turn-3", "build", "", "Next live", "", live = true),
      "",
      "",
      false,
      emptyList(),
      emptyList(),
      ApprovalNotice(false, "", "", "", "", false)
    )
    val catchup = WireCatchup("snapshot", "bb", 0, "conversation-2", "/work", "New", snapshot, emptyList())
    val next = reduceMonitor(closed.copy(catchingUp = true, announcedEpoch = "bb"), message(encodeCatchup("catch", catchup)))
    assertEquals("bb", next.hostEpoch)
    assertEquals(0L, next.hostCursor)
    assertFalse(next.catchingUp)
    assertEquals("conversation-2", next.conversationId)
    assertEquals("/work", next.projectRoot)
    assertEquals("New", next.conversationTitle)
    assertEquals("Next", next.turns[0].promptPreview)
    val sameKey = WireCatchup("snapshot", "bb", 1, "conversation-2", "/work", "New", snapshot, emptyList())
    val replaced = reduceMonitor(next, message(encodeCatchup("again", sameKey)))
    assertEquals("conversation-2", replaced.conversationId)
    assertEquals("/work", replaced.projectRoot)
    assertEquals(1L, replaced.hostCursor)
    val retitled = reduceMonitor(replaced, message(computing.michell.monitor.protocol.encodeHelloOk(
      "hello-title",
      computing.michell.monitor.protocol.HelloOkMessage("n", "host", "bb", 1, "conversation-2", "/work", "Renamed")
    )))
    assertEquals("bb", retitled.hostEpoch)
    assertEquals("Renamed", retitled.conversationTitle)
    assertEquals("Next", retitled.turns[0].promptPreview)
  }
}

private fun message(json: String): computing.michell.monitor.protocol.MonitorMessage {
  val decoded = tryDecodeEnvelope(json)
  assertTrue(decoded.errorText, decoded.ok)
  return decoded.message
}

private fun splitLongTurn(thinking: String, answer: String, revision: Int): List<WireTranscript> {
  val source = WireTranscript(
    -2,
    revision,
    "thinking",
    "working",
    listOf(
      WireBlock("thinking", "think-1", "Thinking", "", "", thinking, true, true, 0, emptyList()),
      WireBlock("answer", "answer-1", "", "", "", answer, false, true, 0, emptyList())
    )
  )
  return splitTranscript(source)
}

private fun reduceTranscripts(frames: List<WireTranscript>, start: MonitorUi = MonitorUi()): MonitorUi {
  var state = start
  for (frame in frames) {
    val encoded = tryEncodeTranscript("tr-" + frame.revision.toString() + "-" + frame.part.toString(), frame)
    assertTrue(encoded.isNotEmpty())
    state = reduceMonitor(state, message(encoded))
  }
  return state
}

private fun answerBlock(body: String): WireBlock {
  return WireBlock("answer", "b1", "", "", "", body, false, true, 0, emptyList())
}

private fun patchFrame(epoch: String, cursor: Long, body: String, part: Int, partCount: Int, busy: Boolean): String {
  val patch = WirePatch(
    epoch, cursor, 1, "turn-1", listOf(answerBlock(body)), busy, false, false, "idle",
    !busy, false, busy, 0, part, partCount
  )
  return encodePatch("patch-" + cursor.toString() + "-" + part.toString(), patch)
}

private fun transcript(revision: Int, body: String): String {
  val block = WireBlock("answer", "b1", "", "", "", body, false, true, 0, emptyList())
  return tryEncodeTranscript("transcript", WireTranscript(1, revision, "thinking", "working", listOf(block)))
}

