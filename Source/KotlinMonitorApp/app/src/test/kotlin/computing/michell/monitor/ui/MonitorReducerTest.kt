package computing.michell.monitor.ui

/* Screen helpers that are not the catalogue-2 reducer (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.HostClosedBanner
import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.protocol.ConversationChoice
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.ModelChoice
import computing.michell.monitor.protocol.PermissionChoice
import computing.michell.monitor.protocol.ReasoningChoice
import computing.michell.monitor.protocol.TargetChoice
import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.encodePath
import computing.michell.monitor.protocol.encodeSelectConversation
import computing.michell.monitor.protocol.encodeSetModel
import computing.michell.monitor.protocol.encodeSetPermissions
import computing.michell.monitor.protocol.encodeSetReasoning
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MonitorReducerTest {
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
  }

  @Test
  fun loadedBlockKeepsTheFullBody() {
    val body = "x".repeat(4000)
    val turn = WireTurn(1, "a", "chat", "", "", "", blocks = listOf(
      WireBlock("answer", "b", "", "", "", body, false, true, 0, emptyList())
    ))
    assertEquals(body, shownBlocks(turn, true, true).single().body)
  }

  @Test
  fun socketCloseKeepsTheDraftAndDoesNotBumpGenerationTwice() {
    val kept = WireTurn(1, "a", "chat", "", "hi", "", prompt = "hi")
    val liveTurn = WireTurn(-2, "live", "chat", "", "hi", "", prompt = "hi", blocks = listOf(
      WireBlock("answer", "", "", "", "", "kept", false, true, 0, emptyList())
    ))
    val start = MonitorUi(draft = "unsent", reachedLive = true, turns = listOf(kept), history = mapOf(1 to kept), live = liveTurn)
    val closed = noteSocketClosed(start, HostClosedBanner)
    assertEquals("unsent", closed.draft)
    assertEquals("kept", closed.live?.blocks?.first()?.body)
    assertEquals(HostClosedBanner, closed.banner)
    assertFalse(closed.disconnected)
    assertEquals(start.turns, closed.turns)
    assertEquals(start.history, closed.history)
    assertFalse(closed.view.canSteer)
    assertFalse(closed.view.canSend)
    assertEquals(1, closed.generation)
    val again = noteSocketClosed(closed, HostClosedBanner)
    assertEquals(closed.generation, again.generation)
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
  fun aWaitingPromptShowsElapsedTimeUntilTheTurnFinishes() {
    val start = MonitorUi(draft = "fix the form", view = emptyView().copy(canSend = true, signedIn = true, model = "grok-4", backend = "grok"))
    val next = beginSubmit(start, "fix the form", false, 1_000L)
    assertEquals("", next.draft)
    assertEquals("fix the form", next.pendingPrompt)
    assertEquals("user", next.pendingKind)
    assertEquals(PhaseWaiting, next.view.phase)
    assertFalse(promptShown(next, next.pendingPrompt))
    assertEquals("grok-4", runtimeCaption(next.view))
    assertEquals("Waiting… 0:02", activityCaption(next.view, true, "user", 1_000L, 3_000L))
    assertEquals("Ready", activityCaption(emptyView().copy(signedIn = true, statusText = "Ready"), false, "", 0L, 3_000L))
    assertEquals("Ready", activityCaption(emptyView().copy(signedIn = false, statusText = "Not signed in"), false, "", 0L, 3_000L))
    assertEquals("Ready", activityCaption(emptyView().copy(signedIn = false, statusText = ""), false, "", 0L, 3_000L))
    assertEquals("", activityCaption(emptyView().copy(signedIn = true, statusText = "Offline"), false, "", 0L, 3_000L, linkLive = false))
    val thought = WireBlock("thinking", "t", "", "", "", "hmm", true, true, 0, emptyList())
    val live = WireTurn(-2, "live", "build", "", "", "", live = true, blocks = listOf(thought))
    assertEquals("Ready", activityCaption(
      emptyView().copy(signedIn = true, statusText = "Ready", canSend = true),
      false, "", 1_000L, 5_000L, listOf(thought), live
    ))
    assertEquals("Thinking… 0:04", activityCaption(
      emptyView().copy(sending = true, busy = true, signedIn = true, statusText = "Thinking…", canSend = false),
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
    assertEquals("", activityCaption(
      running.view, false, "", now - 12_000L, now, listOf(thought), live,
      ideLinkLive(running.disconnected, LinkPhase.Disconnected)
    ))
    assertEquals("", activityCaption(
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
}
