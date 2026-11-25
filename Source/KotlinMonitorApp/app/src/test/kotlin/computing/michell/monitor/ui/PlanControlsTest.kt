package computing.michell.monitor.ui

/* Approval, save question and plan controls against a fake host.
   (c) 2026 Michell Computing. */

import computing.michell.monitor.data.openTestDatabase
import computing.michell.monitor.net.CommandSender
import computing.michell.monitor.net.LinkState
import computing.michell.monitor.net.SaveQuestion
import computing.michell.monitor.net.SyncEngine
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlanControlsTest {
  @Test
  fun anAnsweredApprovalUnblocksTheFakeWaiter() {
    val waiter = CountDownLatch(1)
    val decision = AtomicReference("")
    val database = openTestDatabase()
    val server = MockWebServer()
    val client = client()
    server.dispatcher = object : Dispatcher() {
      override fun dispatch(request: RecordedRequest): MockResponse {
        val path = request.path.orEmpty().substringBefore('?')
        if (path == "/v4/approval") {
          return MockResponse().setBody(
            """{"id":"tool-1","tool_name":"read_file","summary":"Read the plan","mode_caption":"Ask","decisions_accepted":true}"""
          )
        }
        if (path == "/v4/commands") {
          decision.set(request.body.readUtf8())
          waiter.countDown()
          return MockResponse().setBody("""{"state":"accepted"}""")
        }
        return MockResponse().setResponseCode(404)
      }
    }
    server.start()
    val engine = SyncEngine(database, client, server.url("/"), "desk")
    val sender = CommandSender(database, client, server.url("/"), "desk", clock = { 1_000L }, newId = { "cmd-allow" })
    try {
      val shown = approvalPulse("tool-1")
      engine.onPulse(shown)
      assertTrue(engine.awaitIdle())
      val notice = approvalNotice(shown, engine.approvalDetail())
      assertEquals("tool-1", notice?.toolId)
      assertEquals("Read the plan", notice?.summary)
      assertTrue(notice?.decisionsAccepted == true)
      val open = projectMonitor(database.monitor(), shown, LinkState.Connected(1L), 1L, true, approvalDetail = engine.approvalDetail())
      assertTrue(open.approvalOpen)
      sender.noteLink(true)
      sender.approval(notice!!.toolId, "allow")
      assertTrue(waiter.await(3, TimeUnit.SECONDS))
      assertTrue(decision.get().contains("\"decision\":\"allow\""))
    } finally {
      engine.close()
      server.shutdown()
      client.dispatcher.executorService.shutdownNow()
      database.close()
    }
  }

  @Test
  fun anApprovalClosedOnTheDesktopClosesTheSheet() {
    val database = openTestDatabase()
    try {
      val shown = projectMonitor(
        database.monitor(), approvalPulse("tool-1"), LinkState.Connected(1L), 1L, true,
        approvalDetail = """{"id":"tool-1","summary":"Read","mode_caption":"Ask","decisions_accepted":true}"""
      )
      assertTrue(shown.approvalOpen)
      assertEquals("tool-1", shown.approval?.toolId)
      val closed = projectMonitor(database.monitor(), approvalPulse(null), LinkState.Connected(2L), 2L, true, shown)
      assertFalse(closed.approvalOpen)
      assertEquals(null, closed.approval)
    } finally {
      database.close()
    }
  }

  @Test
  fun runPlanWithUnsavedEditsAsksAndResendsSaveFirst() {
    val asked = AtomicReference<SaveQuestion?>(null)
    val bodies = ArrayList<String>()
    val database = openTestDatabase()
    val server = MockWebServer()
    val client = client()
    server.dispatcher = object : Dispatcher() {
      override fun dispatch(request: RecordedRequest): MockResponse {
        val raw = request.body.readUtf8()
        bodies += raw
        if (!raw.contains("\"save_first\":true")) {
          return MockResponse().setResponseCode(409).setBody("""{"reason":"unsaved_edits","message":"Save first."}""")
        }
        return MockResponse().setBody("""{"state":"accepted"}""")
      }
    }
    server.start()
    val sender = CommandSender(
      database, client, server.url("/"), "desk", clock = { 1_000L }, newId = { "cmd-plan" },
      onSaveQuestion = { asked.set(it) }
    )
    try {
      sender.noteLink(true)
      val id = sender.runPlan()
      assertEquals(id, asked.get()?.id)
      assertEquals("run_plan", asked.get()?.type)
      sender.confirmSave(id)
      assertEquals(2, bodies.size)
      assertTrue(bodies[0].contains(id))
      assertTrue(bodies[1].contains(id))
      assertFalse(bodies[0].contains("\"save_first\":true"))
      assertTrue(bodies[1].contains("\"save_first\":true"))
    } finally {
      server.shutdown()
      client.dispatcher.executorService.shutdownNow()
      database.close()
    }
  }

  @Test
  fun planRowsUpdateWhenThePlanEtagChanges() {
    val database = openTestDatabase()
    val server = MockWebServer()
    val client = client()
    var etag = "p1"
    server.dispatcher = object : Dispatcher() {
      override fun dispatch(request: RecordedRequest): MockResponse {
        val path = request.path.orEmpty().substringBefore('?')
        if (path == "/v4/plan") {
          val title = if (etag == "p1") "Old" else "Review"
          return MockResponse().setBody(
            """{"path":"Documents/Plan.md","title":"Plan","etag":"$etag","rows":[{"index":1,"level":2,"title":"$title","status":"not started","actionable":true}]}"""
          )
        }
        return MockResponse().setBody("[]")
      }
    }
    server.start()
    val engine = SyncEngine(database, client, server.url("/"), "desk")
    try {
      engine.onPulse(planPulse("p1"))
      assertTrue(engine.awaitIdle())
      assertEquals("Old", projectMonitor(database.monitor(), planPulse("p1"), LinkState.Connected(1L), 1L, true).planRows.single().title)
      etag = "p2"
      engine.onPulse(planPulse("p2"))
      assertTrue(engine.awaitIdle())
      val updated = projectMonitor(database.monitor(), planPulse("p2"), LinkState.Connected(2L), 2L, true)
      assertEquals("Review", updated.planRows.single().title)
      assertEquals("p2", updated.planRevision)
    } finally {
      engine.close()
      server.shutdown()
      client.dispatcher.executorService.shutdownNow()
      database.close()
    }
  }
}

private fun client(): OkHttpClient {
  return OkHttpClient.Builder().retryOnConnectionFailure(false).build()
}

private fun approvalPulse(id: String?): String {
  val approval = if (id == null) "null" else """{"id":"$id","tool_name":"read_file"}"""
  return """{"epoch":"e","rev":1,"status":{"remote_approval":true,"available":true},"conversation":{"id":"","title":"","etag":"","turn_count":0},"live":null,"plan":{"path":"","etag":""},"lists":{"conversations":"","plans":"","tasks":""},"approval":$approval}"""
}

private fun planPulse(etag: String): String {
  return """{"epoch":"e","rev":1,"status":{"available":true},"conversation":{"id":"","title":"","etag":"","turn_count":0},"live":null,"plan":{"path":"Documents/Plan.md","etag":"$etag","running":false,"item":""},"lists":{"conversations":"","plans":"","tasks":""},"approval":null}"""
}
