package computing.michell.monitor.net

/* Command sender against a fake host. Offline prompts leave in order. A reset
   resends the same id. Stop does not wait. The save question keeps the id.
   (c) 2026 Michell Computing. */

import computing.michell.monitor.data.OutboxPending
import computing.michell.monitor.data.openTestDatabase
import java.util.concurrent.atomic.AtomicInteger
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.mockwebserver.SocketPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CommandSenderTest {
  @Test
  fun threePromptsQueuedOfflineAreSentInOrderOneAtATime() {
    val bodies = ArrayList<String>()
    val inFlight = AtomicInteger()
    val maxInFlight = AtomicInteger()
    withSender(dispatcher = object : Dispatcher() {
      override fun dispatch(request: RecordedRequest): MockResponse {
        val now = inFlight.incrementAndGet()
        maxInFlight.updateAndGet { current -> maxOf(current, now) }
        val raw = request.body.readUtf8()
        bodies += raw
        val response = MockResponse().setBody("""{"state":"accepted","turn_id":"t${bodies.size}"}""")
        inFlight.decrementAndGet()
        return response
      }
    }) { sender, server, _ ->
      sender.linkUp = false
      sender.send("one")
      sender.send("two")
      sender.send("three")
      assertEquals(0, server.requestCount)
      sender.linkUp = true
      sender.onPulse(pulse(canSend = true, live = null))
      assertEquals(1, server.requestCount)
      assertTrue(bodies[0].contains("one"))
      sender.onPulse(pulse(canSend = false, live = "t1"))
      assertEquals(1, server.requestCount)
      sender.onPulse(pulse(canSend = true, live = null))
      assertEquals(2, server.requestCount)
      assertTrue(bodies[1].contains("two"))
      sender.onPulse(pulse(canSend = false, live = "t2"))
      assertEquals(2, server.requestCount)
      sender.onPulse(pulse(canSend = true, live = null))
      assertEquals(3, server.requestCount)
      assertTrue(bodies[2].contains("three"))
      assertEquals(1, maxInFlight.get())
    }
  }

  @Test
  fun aResetAfterAcceptanceResendsTheSameIdAndStartsNoSecondTurn() {
    val ids = ArrayList<String>()
    var requests = 0
    var started = 0
    withSender(dispatcher = object : Dispatcher() {
      override fun dispatch(request: RecordedRequest): MockResponse {
        requests += 1
        val raw = request.body.readUtf8()
        val id = jsonId(raw)
        if (ids.contains(id)) return MockResponse().setBody("""{"state":"done","turn_id":"turn-1"}""")
        ids += id
        started += 1
        return MockResponse().setBody("{\"state\":\"accep").setSocketPolicy(SocketPolicy.DISCONNECT_DURING_RESPONSE_BODY)
      }
    }) { sender, _, _ ->
      sender.onPulse(pulse(canSend = true, live = null))
      sender.send("hello")
      assertEquals(2, requests)
      assertEquals(1, started)
      assertEquals(1, ids.size)
    }
  }

  @Test
  fun stopIsSentWhileASendWaitsInTheOutbox() {
    val types = ArrayList<String>()
    withSender(dispatcher = object : Dispatcher() {
      override fun dispatch(request: RecordedRequest): MockResponse {
        types += jsonType(request.body.readUtf8())
        return MockResponse().setBody("""{"state":"done"}""")
      }
    }) { sender, server, database ->
      sender.onPulse(pulse(canSend = false, live = null))
      val sendId = sender.send("waiting")
      assertEquals(0, server.requestCount)
      sender.stop()
      assertEquals(listOf("stop"), types)
      assertEquals(OutboxPending, database.monitor().outboxItem(sendId)?.state)
    }
  }

  @Test
  fun theSaveQuestionRoundTripKeepsTheId() {
    val bodies = ArrayList<String>()
    var asked: String? = null
    withSender(dispatcher = object : Dispatcher() {
      override fun dispatch(request: RecordedRequest): MockResponse {
        val raw = request.body.readUtf8()
        bodies += raw
        if (!raw.contains("\"save_first\":true")) {
          return MockResponse().setResponseCode(409).setBody("""{"reason":"unsaved_edits","message":"Save first."}""")
        }
        return MockResponse().setBody("""{"state":"done","turn_id":"t-saved"}""")
      }
    }, onSaveQuestion = { asked = it.id }) { sender, _, _ ->
      sender.onPulse(pulse(canSend = true, live = null))
      val id = sender.send("edit me")
      assertEquals(id, asked)
      sender.confirmSave(id)
      assertEquals(2, bodies.size)
      assertTrue(bodies[0].contains(id))
      assertTrue(bodies[1].contains(id))
      assertFalse(bodies[0].contains("\"save_first\":true"))
      assertTrue(bodies[1].contains("\"save_first\":true"))
    }
  }
}

private fun pulse(canSend: Boolean, live: String?): String {
  val liveJson = if (live == null) "null" else """{"turn_id":"$live","turn_index":1,"rev":1,"item":null}"""
  return """{"epoch":"e","rev":1,"status":{"can_send":$canSend},"conversation":{"id":"c","title":"","etag":"","turn_count":0},"live":$liveJson,"plan":{"path":"","etag":""},"lists":{"conversations":"","plans":"","tasks":""},"approval":null}"""
}

private fun jsonId(body: String): String = parseJson(body)?.text("id").orEmpty()

private fun jsonType(body: String): String = parseJson(body)?.text("type").orEmpty()

private fun withSender(
  dispatcher: Dispatcher,
  onSaveQuestion: (SaveQuestion) -> Unit = {},
  body: (CommandSender, MockWebServer, computing.michell.monitor.data.MonitorDatabase) -> Unit
) {
  val database = openTestDatabase()
  val server = MockWebServer()
  val client = OkHttpClient.Builder().retryOnConnectionFailure(false).build()
  server.dispatcher = dispatcher
  server.start()
  val sender = CommandSender(database, client, server.url("/"), "desk", clock = { 1_000L }, onSaveQuestion = onSaveQuestion)
  try {
    body(sender, server, database)
  } finally {
    server.shutdown()
    client.dispatcher.executorService.shutdownNow()
    database.close()
  }
}
