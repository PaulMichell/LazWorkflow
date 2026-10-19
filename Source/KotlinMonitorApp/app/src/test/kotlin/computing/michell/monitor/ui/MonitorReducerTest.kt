package computing.michell.monitor.ui

/* Catalogue reduction without a device (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.HostClosedBanner
import computing.michell.monitor.protocol.ApprovalNotice
import computing.michell.monitor.protocol.JsonValue
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTranscript
import computing.michell.monitor.protocol.PlanRow
import computing.michell.monitor.protocol.TaskRow
import computing.michell.monitor.protocol.WireSnapshot
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.encodeApprovalClosed
import computing.michell.monitor.protocol.encodeApprovalRequested
import computing.michell.monitor.protocol.encodeEnvelope
import computing.michell.monitor.protocol.encodeImageUnavailable
import computing.michell.monitor.protocol.tryEncodeTranscript
import computing.michell.monitor.protocol.encodeInsertResult
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
  fun snapshotReplacesViewPlanTasksAndTurnIndex() {
    val snapshot = WireSnapshot(
      emptyView().copy(model = "grok-test", canSend = true, targetDisplay = "LazWorkflow", phase = "idle"),
      listOf(WireTurn(2, "turn-2", "build", "", "older", "")),
      WireTurn(3, "turn-3", "build", "", "live", "", blocks = emptyList()),
      "Documents/Plan.md",
      "Monitor plan",
      false,
      listOf(PlanRow(1, 1, "Codec", "", "pending", true)),
      listOf(promptTask()),
      ApprovalNotice(false, "", "", "", "", false)
    )
    val next = reduceMonitor(MonitorUi(draft = "keep"), message(encodeSnapshot("snapshot", snapshot)))
    assertEquals("grok-test", next.view.model)
    assertEquals("LazWorkflow", next.view.targetDisplay)
    assertEquals("Documents/Plan.md", next.planPath)
    assertEquals(1, next.taskRows.size)
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
  fun turnDataFillsTheSelectedHistoryTurn() {
    val turn = WireTurn(4, "turn-4", "build", "", "history", "", prompt = "full")
    val next = reduceMonitor(MonitorUi(), message(encodeTurnData("turn-data", turn)))
    assertEquals("full", next.history[4]?.prompt)
    assertEquals(4, next.selectedTurn)
  }

  @Test
  fun planAndTasksPatchThoseParts() {
    val planned = reduceMonitor(MonitorUi(), message(encodePlan("plan", "Documents/Plan.md", "Monitor", true, listOf(PlanRow(1, 1, "Row", "", "pending", true)))))
    assertEquals("Monitor", planned.planTitle)
    assertTrue(planned.planRunning)
    val tasks = reduceMonitor(planned, message(tasksJson()))
    assertEquals("format", tasks.taskRows.single().kind)
    assertEquals("This task runs on the desktop.", tasks.taskRows.single().desktopOnlyReason())
    assertFalse(tasks.taskRows.single().isRunnable())
    assertTrue(promptTask().isRunnable())
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
    val start = MonitorUi(draft = "unsent", reachedLive = true)
    val rejected = reduceMonitor(start, message(encodeRejected("rejected", "protocol", 1, 1)))
    assertEquals("unsent", rejected.draft)
    assertTrue(rejected.disconnected)
    assertTrue(rejected.pairHold)
    val closed = noteSocketClosed(start, HostClosedBanner)
    assertEquals("unsent", closed.draft)
    assertEquals(HostClosedBanner, closed.banner)
    assertTrue(closed.disconnected)
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
}

private fun message(json: String): computing.michell.monitor.protocol.MonitorMessage {
  val decoded = tryDecodeEnvelope(json)
  assertTrue(decoded.errorText, decoded.ok)
  return decoded.message
}

private fun transcript(revision: Int, body: String): String {
  val block = WireBlock("answer", "b1", "", "", "", body, false, true, 0, emptyList())
  return tryEncodeTranscript("transcript", WireTranscript(1, revision, "thinking", "working", listOf(block)))
}

private fun tasksJson(): String {
  val row = JsonValue.Obj(listOf(
    "id" to JsonValue.Str("format-unit"),
    "title" to JsonValue.Str("Format"),
    "summary" to JsonValue.Str("Desktop"),
    "mode" to JsonValue.Str("build"),
    "kind" to JsonValue.Str("format"),
    "scope" to JsonValue.Str("project"),
    "compile_first" to JsonValue.Bool(false),
    "enabled" to JsonValue.Bool(true),
    "needs_note" to JsonValue.Bool(false)
  ))
  return encodeEnvelope(MessageKind.Tasks, "tasks", JsonValue.Obj(listOf("rows" to JsonValue.Arr(listOf(row)))))
}

private fun promptTask(): TaskRow {
  return TaskRow("review-unit", "Review", "Read", "build", "prompt", "project", false, true, false)
}
