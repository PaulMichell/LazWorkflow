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
import computing.michell.monitor.protocol.tryDecodeEnvelope
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
    val state = MonitorUi(view = emptyView().copy(targetRoot = "/old/"),
      selectedPlan = 3, planChoices = listOf(PlanChoice("Plan.md", "Old project")))
    val same = reduceMonitor(state, message(encodeTarget("same", "project", "Old", "/old/")))
    assertEquals(state.planChoices, same.planChoices)
    val next = reduceMonitor(state, message(encodeTarget("next", "project", "New", "/new/")))
    assertTrue(next.planChoices.isEmpty())
    assertEquals(-1, next.selectedPlan)
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
    assertEquals("Waiting for first token…", next.view.phase)
    assertFalse(promptShown(next, next.pendingPrompt))
    val echoed = next.copy(live = WireTurn(-2, "live", "build", "", "fix the form", "", prompt = "fix the form", blocks = listOf(
      WireBlock("user", "u", "", "", "", "fix the form", false, true, 0, emptyList())
    )))
    val merged = mergeApplied(next, echoed, false, false)
    assertEquals("", merged.pendingPrompt)
    assertEquals("grok-4", runtimeCaption(next.view))
    assertEquals("Waiting for first token… 0:02", activityCaption(next.view, true, "user", 1_000L, 3_000L))
    assertEquals("Ready", activityCaption(emptyView().copy(signedIn = true, statusText = "Ready"), false, "", 0L, 3_000L))
    val thought = WireBlock("thinking", "t", "", "", "", "hmm", true, true, 0, emptyList())
    val live = WireTurn(-2, "live", "build", "", "", "", live = true, blocks = listOf(thought))
    assertEquals("Thinking… 0:04", activityCaption(
      emptyView().copy(signedIn = true, statusText = "Ready", canSend = true),
      false, "", 1_000L, 5_000L, listOf(thought), live
    ))
    val now = 1_700_000_000_000L
    assertEquals(now - 724_000L, activityStart(now - 2_000L, now, 724_000, 0))
    assertEquals("Thinking… 12:04", activityCaption(
      emptyView().copy(sending = true, phase = "Thinking…", statusText = "Ready"),
      false, "", now - 724_000L, now, listOf(thought), live
    ))
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

private fun transcript(revision: Int, body: String): String {
  val block = WireBlock("answer", "b1", "", "", "", body, false, true, 0, emptyList())
  return tryEncodeTranscript("transcript", WireTranscript(1, revision, "thinking", "working", listOf(block)))
}

