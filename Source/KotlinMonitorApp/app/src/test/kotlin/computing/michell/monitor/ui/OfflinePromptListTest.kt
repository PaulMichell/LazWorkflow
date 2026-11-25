package computing.michell.monitor.ui

/* Offline review and the pending prompt list (c) 2026 Michell Computing.

   Two prompts queued with the link down leave in order when the fake host
   returns. Each pending mark clears when that turn appears. A stored
   conversation opens with no host and no socket. */

import computing.michell.monitor.data.ConversationRow
import computing.michell.monitor.data.HostRow
import computing.michell.monitor.data.PlanCacheRow
import computing.michell.monitor.data.TurnRow
import computing.michell.monitor.data.openTestDatabase
import computing.michell.monitor.net.CommandSender
import computing.michell.monitor.net.LinkState
import computing.michell.monitor.ui.model.ConversationRecord
import computing.michell.monitor.ui.model.MonitorUi
import computing.michell.monitor.ui.model.sendActionEnabled
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OfflinePromptListTest {
  @Test
  fun twoPromptsQueuedOfflineAreSentInOrderAndClearAsEachTurnAppears() {
    val database = openTestDatabase()
    val server = MockWebServer()
    val client = OkHttpClient.Builder().retryOnConnectionFailure(false).build()
    val bodies = ArrayList<String>()
    server.dispatcher = object : Dispatcher() {
      override fun dispatch(request: RecordedRequest): MockResponse {
        val raw = request.body.readUtf8()
        bodies += raw
        return MockResponse().setBody("""{"state":"accepted","turn_id":"t${bodies.size}"}""")
      }
    }
    server.start()
    val dao = database.monitor()
    dao.replaceHost(HostRow(Endpoint, "", Endpoint, "", 0L))
    dao.replaceConversation(ConversationRow("c1", Endpoint, "Notes", "etag", 0, true, 5_000L))
    var nextId = 0
    val sender = CommandSender(
      database, client, server.url("/"), Endpoint, clock = { 1_000L }, newId = { "cmd-${++nextId}" }
    )
    try {
      sender.noteLink(false)
      val first = sender.send("one")
      val second = sender.send("two")
      assertEquals(0, server.requestCount)
      var ui = project(dao, "", LinkState.Stopped, MonitorUi())
      assertEquals(ChipOffline, monitorChip(ui.linkKind, ui.statusBusy).label)
      assertEquals("2 prompts waiting", ui.banner)
      assertEquals(listOf("one", "two"), ui.pendingPrompts.map { it.text })
      assertEquals(listOf(first, second), ui.pendingPrompts.map { it.id })
      assertTrue(ui.pendingPrompts.all { it.editable })
      assertTrue(ui.sendWhileOffline)
      assertTrue(promptFieldEnabled(ui.disconnected))
      assertTrue(sendActionEnabled(ui.view, ui.disconnected, linkPhaseOf(ui.linkKind), ui.planRunning, ui.sendWhileOffline))
      assertEquals(listOf("one", "two"), visiblePendingMarks(ui).map { it.text })

      sender.noteLink(true)
      sender.onPulse(pulse(canSend = true, live = null))
      assertEquals(1, server.requestCount)
      assertTrue(bodies[0].contains("one"))
      assertTrue(bodies[0].contains(first))
      dao.replaceTurn(TurnRow("t1", "c1", 1, "e1", "one", "build", 1L, "ok", 0, "", first))
      ui = project(dao, pulse(canSend = false, live = "t1"), LinkState.Connected(1L), ui)
      assertEquals(listOf("two"), ui.pendingPrompts.map { it.text })
      assertEquals("1 prompt waiting", ui.banner)
      assertTrue(promptShown(ui, "one"))

      sender.onPulse(pulse(canSend = true, live = null))
      assertEquals(2, server.requestCount)
      assertTrue(bodies[1].contains("two"))
      assertTrue(bodies[1].contains(second))
      dao.replaceTurn(TurnRow("t2", "c1", 2, "e2", "two", "build", 2L, "ok", 0, "", second))
      ui = project(dao, pulse(canSend = true, live = null), LinkState.Connected(2L), ui)
      assertTrue(ui.pendingPrompts.isEmpty())
      assertEquals("", ui.banner)
      assertTrue(visiblePendingMarks(ui).isEmpty())
    } finally {
      server.shutdown()
      client.dispatcher.executorService.shutdownNow()
      database.close()
    }
  }

  @Test
  fun aPendingPromptCanBeEditedOrDeletedBeforeItIsSent() {
    val database = openTestDatabase()
    val dao = database.monitor()
    val sender = CommandSender(database, OkHttpClient(), serverUrl(), Endpoint, clock = { 1_000L }, newId = { "cmd-edit" })
    try {
      sender.noteLink(false)
      val id = sender.send("draft")
      assertTrue(sender.editPrompt(id, "revised"))
      var ui = project(dao, "", LinkState.Stopped, MonitorUi())
      assertEquals("revised", ui.pendingPrompts.single().text)
      assertTrue(ui.pendingPrompts.single().editable)
      assertTrue(sender.deletePrompt(id))
      ui = project(dao, "", LinkState.Stopped, ui)
      assertTrue(ui.pendingPrompts.isEmpty())
      assertEquals("", ui.banner)
    } finally {
      database.close()
    }
  }

  @Test
  fun aCachedConversationOpensWithNoHost() {
    val database = openTestDatabase()
    val dao = database.monitor()
    try {
      dao.replaceHost(HostRow(Endpoint, "", Endpoint, "", 4L))
      dao.replaceConversation(ConversationRow("c1", Endpoint, "Notes", "etag", 1, true, 5_000L))
      dao.replaceTurn(TurnRow("t-old", "c1", 0, "e", "cached question", "build", 1L, "ok", 0, "", ""))
      dao.replacePlan(PlanCacheRow(Endpoint, "Documents/Plan.md", "Plan", "p", """[{"index":1,"title":"Review","status":"not started"}]""", "cached plan text"))
      val row = ConversationRecord("c1", Endpoint, "", "Notes", "epoch", 4L, 5_000L, false)
      val opened = openCachedConversation(dao, row)
      assertEquals("c1", opened.conversationId)
      assertEquals("Notes", opened.conversationTitle)
      assertEquals("cached question", opened.turns.single().prompt)
      assertEquals("Documents/Plan.md", opened.planPath)
      assertEquals("Plan", opened.planTitle)
      assertEquals("cached plan text", opened.planBody)
      assertEquals("Review", opened.planRows.single().title)
      assertTrue(opened.disconnected)
      assertFalse(opened.reachedLive)
      assertEquals(ChipOffline, monitorChip(opened.linkKind, opened.statusBusy).label)
      assertTrue(promptFieldEnabled(opened.disconnected))
      assertEquals("c1", conversationsForHost(listOf(row), Endpoint).single().id)
    } finally {
      database.close()
    }
  }
}

private const val Endpoint = "10.0.0.8:56122"

private fun project(
  dao: computing.michell.monitor.data.MonitorDao,
  pulseJson: String,
  link: LinkState,
  previous: MonitorUi
): MonitorUi {
  return projectMonitor(dao, pulseJson, link, 1L, true, previous)
}

private fun pulse(canSend: Boolean, live: String?): String {
  val liveJson = if (live == null) "null" else """{"turn_id":"$live","turn_index":1,"rev":1,"item":null}"""
  return """{"epoch":"e","rev":1,"server_time":"2026-11-24T10:15:02.120Z","status":{"available":true,"busy":false,"sending":false,"plan_running":false,"mode":"build","phase":"","status_text":"Ready","activity":"Ready","activity_since":"","can_send":$canSend,"can_steer":false,"can_stop":false,"can_change_mode":false,"remote_approval":false,"error_text":""},"conversation":{"id":"c1","title":"Notes","etag":"etag","turn_count":1},"live":$liveJson,"plan":{"path":"","etag":""},"lists":{"conversations":"","plans":"","tasks":""},"approval":null}"""
}

private fun serverUrl() = "https://10.0.0.8:56122/".toOkHttpUrl()

private fun String.toOkHttpUrl() = okhttp3.HttpUrl.Builder().scheme("https").host("10.0.0.8").port(56122).build()
