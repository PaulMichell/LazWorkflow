package computing.michell.monitor.ui

/* Screen state from a fake engine: Room rows, one pulse, and a link state.
   (c) 2026 Michell Computing. */

import computing.michell.monitor.data.ConversationRow
import computing.michell.monitor.data.ImageRow
import computing.michell.monitor.data.ItemRow
import computing.michell.monitor.data.MonitorDao
import computing.michell.monitor.data.PlanCacheRow
import computing.michell.monitor.data.TurnRow
import computing.michell.monitor.data.host
import computing.michell.monitor.data.openTestDatabase
import computing.michell.monitor.net.LinkState
import computing.michell.monitor.net.LiveTurnOutcome
import computing.michell.monitor.net.parseMonitorTime
import computing.michell.monitor.ui.model.LinkPhase
import computing.michell.monitor.ui.model.MonitorLink
import computing.michell.monitor.ui.model.MonitorUi
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MonitorScreenTest {
  @Test
  fun aLiveTurnGrowsItsThinkingText() {
    val engine = FakeEngine()
    try {
      engine.turn("t-live", LiveTurnOutcome, "Explain the index")
      engine.item("think", "thinking", "running", "Thinking…", "", "Hello")
      engine.pulse(busy = true, activity = "Thinking…", liveId = "t-live", itemKind = "thinking")
      val first = engine.project()
      assertEquals("Hello", thought(first))
      engine.item("think", "thinking", "running", "Thinking…", "", "Hello world")
      val second = engine.project()
      val grown = thought(second)
      assertTrue(grown.startsWith("Hello"))
      assertTrue(grown.length > thought(first).length)
      assertEquals("Hello world", grown)
    } finally {
      engine.close()
    }
  }

  @Test
  fun aToolCardRunsAndThenFinishes() {
    val engine = FakeEngine()
    try {
      engine.turn("t-tool", LiveTurnOutcome, "Read the file")
      engine.item("tool-1", "tool", "running", "Read file", "read_file", "")
      engine.pulse(busy = true, activity = "Running build", liveId = "t-tool", itemKind = "tool")
      val running = tool(engine.project())
      assertTrue(running.running)
      assertTrue(toolCardCaption(running).endsWith("…"))
      engine.item("tool-1", "tool", "done", "Read file", "read_file", "contents")
      val finished = tool(engine.project())
      assertFalse(finished.running)
      assertTrue(finished.ok)
      assertEquals("contents", finished.body)
      assertFalse(toolCardCaption(finished).endsWith("…"))
    } finally {
      engine.close()
    }
  }

  @Test
  fun anImageTileIsOnTheTurnTheScreenDraws() {
    val engine = FakeEngine()
    try {
      engine.turn("t-pic", "ok", "Show the map")
      engine.item("pic-item", "image", "done", "shot.png", "", "")
      engine.image("pic-1", "pic-item", "shot.png", "/cache/pic-1.png")
      engine.pulse(busy = false, activity = "Ready", liveId = null, itemKind = "")
      val ui = engine.project()
      val rows = conversationRows(ui.turns, ui.live, ui.view.sending, true, true)
      val image = rows.firstNotNullOf { row -> row.block?.images?.firstOrNull() }
      assertEquals("pic-1", image.id)
      assertEquals("shot.png", image.name)
      assertFalse(image.missing)
      assertEquals(LoadingImageLabel, imageTileLabel(false, ui.imageReasons[image.id], image.missing, true))
    } finally {
      engine.close()
    }
  }

  @Test
  fun theActivityTimerTicksWithoutANewPulse() {
    val engine = FakeEngine()
    try {
      val seen = parseMonitorTime(ServerTime)
      engine.pulse(busy = true, activity = "Thinking…", liveId = null, itemKind = "thinking", seenAt = seen)
      val ui = engine.project()
      val phase = linkPhaseOf(ui.linkKind)
      assertEquals("Thinking… 3:26", screenActivity(ui, phase, seen, false))
      assertEquals("Thinking… 3:31", screenActivity(ui, phase, seen + 5_000L, false))
      val skewed = engine.project(seenAt = seen + 60_000L)
      assertEquals("Thinking… 3:26", screenActivity(skewed, phase, seen + 60_000L, false))
      assertTrue(ui.statusBusy)
      assertTrue(engine.project(nowMs = seen + 60_000L).statusBusy)
    } finally {
      engine.close()
    }
  }

  @Test
  fun eachChipStateComesFromTheLinkAndBusy() {
    val engine = FakeEngine()
    try {
      engine.pulse(busy = false, activity = "Ready", liveId = null, itemKind = "")
      assertEquals(ChipLive, chip(engine, LinkState.Connected(1L)))
      engine.pulse(busy = true, activity = "Thinking…", liveId = null, itemKind = "thinking")
      assertEquals(ChipBusy, chip(engine, LinkState.Connected(1L)))
      assertEquals(ChipBusy, chip(engine, LinkState.Connected(1L), nowMs = 60_000L))
      engine.pulse(busy = false, activity = "Ready", liveId = null, itemKind = "")
      assertEquals(ChipLive, chip(engine, LinkState.Connected(2L)))
      engine.pulse(busy = true, activity = "Thinking…", liveId = null, itemKind = "thinking")
      assertEquals(ChipReconnecting, chip(engine, LinkState.Retrying(3L)))
      assertEquals(ChipOffline, chip(engine, LinkState.Stopped))
      assertEquals(ChipUnpaired, chip(engine, LinkState.Unpaired))
      assertEquals(ChipPinChanged, chip(engine, LinkState.PinMismatch))
      assertEquals(ChipUnpaired, chip(engine, LinkState.Stopped, paired = false))
    } finally {
      engine.close()
    }
  }
}

private const val ServerTime = "2026-11-24T10:15:02.120Z"
private const val ActivitySince = "2026-11-24T10:11:36.004Z"
private const val Endpoint = "10.0.0.8:56122"

private fun thought(ui: MonitorUi): String {
  val rows = conversationRows(ui.turns, ui.live, ui.view.sending, true, true)
  val block = rows.first { it.block?.kind == "thinking" }.block!!
  return thinkingDisplayBody(block.body)
}

private fun tool(ui: MonitorUi) = conversationRows(ui.turns, ui.live, true, true, true).first { it.block?.kind == "tool" }.block!!

private fun chip(engine: FakeEngine, link: LinkState, nowMs: Long = 0L, paired: Boolean = true): String {
  engine.link = link
  engine.paired = paired
  val ui = engine.project(nowMs = nowMs)
  return monitorChip(ui.linkKind, ui.statusBusy).label
}

private class FakeEngine {
  private val database = openTestDatabase()
  private val dao: MonitorDao = database.monitor()
  var link: LinkState = LinkState.Connected(1L)
  var paired = true
  private var pulse = ""
  private var seenAt = 1L

  init {
    dao.replaceHost(host(Endpoint))
    dao.replaceConversation(ConversationRow("c1", Endpoint, "Chat", "etag", 1, true, 1L))
  }

  fun turn(id: String, outcome: String, prompt: String) {
    dao.replaceTurn(TurnRow(id, "c1", 1, "t-$id", prompt, "build", 0L, outcome, 0, "", ""))
  }

  fun item(id: String, kind: String, state: String, title: String, toolName: String, body: String) {
    dao.replaceItem(ItemRow(id, "t-live".takeIf { kind == "thinking" } ?: turnIdFor(kind), 0, kind, state, title, toolName, body, 1L, "epoch", body.length.toLong()))
  }

  fun image(id: String, itemId: String, name: String, path: String) {
    dao.replaceImage(ImageRow(id, "t-pic", itemId, name, 12L, path, 1L))
  }

  fun pulse(busy: Boolean, activity: String, liveId: String?, itemKind: String, seenAt: Long = 1L) {
    this.seenAt = seenAt
    val live = if (liveId == null) "null" else """{"turn_id":"$liveId","turn_index":1,"rev":2,"item":{"id":"item","kind":"$itemKind","state":"running","rev":2,"bytes":4}}"""
    pulse = """{"epoch":"epoch","rev":9,"server_time":"$ServerTime","status":{"available":true,"busy":$busy,"sending":$busy,"plan_running":false,"mode":"build","phase":"tool","status_text":"Ready","activity":"$activity","activity_since":"$ActivitySince","turn_started_at":"$ActivitySince","can_send":${!busy},"can_steer":$busy,"can_stop":$busy,"can_change_mode":false,"stop_pending":false,"remote_approval":false,"error_text":"","usage_caption":"","usage_hint":""},"conversation":{"id":"c1","title":"Chat","etag":"etag","turn_count":1},"live":$live,"plan":{"path":"Documents/Plan.md","etag":"p","running":false,"item":""},"lists":{"conversations":"","plans":"","tasks":""},"approval":null}"""
    dao.replacePlan(PlanCacheRow(Endpoint, "Documents/Plan.md", "Plan", "p", "[]", ""))
  }

  fun project(seenAt: Long = this.seenAt, nowMs: Long = seenAt): MonitorUi {
    return projectMonitor(dao, pulse, link, seenAt, paired, MonitorUi(showThinking = true, showTools = true), nowMs)
  }

  fun close() {
    database.close()
  }

  private fun turnIdFor(kind: String): String {
    return if (kind == "image") "t-pic" else "t-tool"
  }
}
