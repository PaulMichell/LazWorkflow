package computing.michell.monitor.net

/* Sync engine against a fake host. Unchanged pulses fetch nothing. Streaming
   stays single-flight. A stored turn replaces live rows. An epoch change keeps
   cached turns. Dropped and reordered pulses still settle on the host.
   (c) 2026 Michell Computing. */

import computing.michell.monitor.data.ItemRow
import computing.michell.monitor.data.MonitorDatabase
import computing.michell.monitor.data.TurnRow
import computing.michell.monitor.data.conversation
import computing.michell.monitor.data.host
import computing.michell.monitor.data.item
import computing.michell.monitor.data.openTestDatabase
import computing.michell.monitor.data.turn
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SyncEngineTest {
  @Test
  fun aPulseWithUnchangedEtagsFetchesNothing() {
    val host = scriptHost()
    withEngine(host) { engine, server ->
      engine.onPulse(host.pulse(rev = 1))
      assertTrue(engine.awaitIdle())
      val fetched = server.requestCount
      assertTrue(fetched > 0)
      engine.onPulse(host.pulse(rev = 1))
      assertTrue(engine.awaitIdle())
      assertEquals(fetched, server.requestCount)
    }
  }

  @Test
  fun aHundredPulsesDuringStreamingNeverOverlapItemRequests() {
    val host = scriptHost()
    host.live = LiveView("t-live", 1, 4, "i-live", "thinking", "running", 9, 4)
    val hold = CountDownLatch(1)
    val started = AtomicInteger()
    val inFlight = AtomicInteger()
    val maxInFlight = AtomicInteger()
    withEngine(host, dispatcher = object : Dispatcher() {
      override fun dispatch(request: RecordedRequest): MockResponse {
        if (request.path.orEmpty().contains("/v4/items/")) {
          val now = inFlight.incrementAndGet()
          maxInFlight.updateAndGet { current -> maxOf(current, now) }
          started.incrementAndGet()
          if (!hold.await(8, TimeUnit.SECONDS)) return MockResponse().setResponseCode(500)
          inFlight.decrementAndGet()
        }
        return host.serve(request)
      }
    }) { engine, _ ->
      engine.followMs = 0
      engine.onPulse(host.pulse(rev = 3))
      awaitStarted(started)
      repeat(99) { engine.onPulse(host.pulse(rev = 3)) }
      Thread.sleep(300)
      assertEquals(1, started.get())
      assertEquals(1, maxInFlight.get())
      hold.countDown()
      assertTrue(engine.awaitIdle(8_000))
      assertEquals(1, maxInFlight.get())
    }
  }

  @Test
  fun liveToStoredMakesOneTurnFetchAndLeavesNoLiveRows() {
    val host = scriptHost()
    host.turns.clear()
    host.conversationEtag = "c-live"
    host.turnCount = 0
    host.live = LiveView("t-live", 0, 4, "i-live", "thinking", "running", 3, 5)
    withEngine(host) { engine, server ->
      engine.onPulse(host.pulse(rev = 1))
      assertTrue(engine.awaitIdle())
      assertTrue(engine.databaseTurns().any { it.outcome == LiveTurnOutcome })
      drain(server)
      host.live = null
      host.conversationEtag = "c-stored"
      host.turnCount = 1
      host.turns += HostTurn("t-live", 0, "t-stored", "hello", "i-live", "stored answer", 8, "done")
      engine.onPulse(host.pulse(rev = 2))
      assertTrue(engine.awaitIdle())
      val turnFetches = drain(server)
      assertEquals(1, turnFetches.size)
      assertTrue(turnFetches.single().path.orEmpty().startsWith("/v4/turns/t-live"))
      assertFalse(turnFetches.single().path.orEmpty().contains("bodies=0"))
      assertTrue(engine.databaseTurns().none { it.outcome == LiveTurnOutcome })
      assertEquals("stored answer", engine.databaseItems("t-live").single().body)
    }
  }

  @Test
  fun anEpochChangeKeepsCachedStoredTurns() {
    val database = openTestDatabase()
    val server = MockWebServer()
    val client = testClient()
    try {
      val dao = database.monitor()
      dao.replaceHost(host("desk", rev = 1).copy(lastEpoch = "epoch-a"))
      dao.replaceConversation(conversation("c1", updatedAt = 1, title = "Chat", current = true).copy(
        host = "desk", etag = "c-same", turnCount = 1
      ))
      dao.replaceTurn(turn("t0", index = 0, prompt = "keep me", conversationId = "c1").copy(etag = "keep"))
      dao.replaceItem(item("i0", ordinal = 0, title = "cached", turnId = "t0").copy(body = "cached-body", epoch = "epoch-a"))
      server.start()
      val script = scriptHost()
      script.epoch = "epoch-a"
      script.conversationEtag = "c-same"
      script.turnCount = 1
      script.turns.clear()
      script.turns += HostTurn("t0", 0, "keep", "keep me", "i0", "replaced-body", 1, "done")
      script.live = LiveView("t-live", 1, 5, "i-live", "thinking", "running", 5, 4)
      server.dispatcher = object : Dispatcher() {
        override fun dispatch(request: RecordedRequest): MockResponse = script.serve(request)
      }
      val engine = SyncEngine(database, client, server.url("/"), "desk", clock = { 1_000L })
      try {
        engine.followMs = 0
        engine.onPulse(script.pulse(rev = 2))
        assertTrue(engine.awaitIdle())
        drain(server)
        script.epoch = "epoch-b"
        engine.onPulse(script.pulse(rev = 1))
        assertTrue(engine.awaitIdle())
        val epochPaths = drain(server).map { it.path.orEmpty() }
        assertTrue(epochPaths.any { it.contains("/conversations/c1/turns") && it.contains("from=0") })
        assertEquals("cached-body", dao.items("t0").single().body)
        assertEquals("keep me", dao.turns("c1").single { it.id == "t0" }.prompt)
        assertEquals("keep", dao.turn("t0")?.etag)
      } finally {
        engine.close()
      }
    } finally {
      server.shutdown()
      client.dispatcher.executorService.shutdown()
      database.close()
    }
  }

  @Test
  fun aFaultScriptEndsWithRoomMatchingTheHost() {
    val script = scriptHost()
    val pulses = ArrayList<String>()
    script.turnCount = 1
    script.turns.clear()
    script.turns += script.turnsTemplate[0]
    pulses += script.pulse(rev = 1)
    script.live = LiveView("t1", 1, 2, "i1", "thinking", "running", 1, 2)
    pulses += script.pulse(rev = 2)
    script.live = script.live?.copy(itemRev = 4, bytes = 8)
    pulses += script.pulse(rev = 3)
    script.epoch = "e2"
    pulses += script.pulse(rev = 4)
    script.live = null
    script.turnCount = 2
    script.conversationEtag = "c-final"
    script.turns.clear()
    script.turns += script.turnsTemplate
    pulses += script.pulse(rev = 5)
    script.planEtag = "plan-final"
    script.planDocument = "# Done\n"
    pulses += script.pulse(rev = 6)
    val random = java.util.Random(20261124)
    val mixed = pulses.toMutableList()
    mixed.shuffle(random)
    repeat(4) { mixed.add(random.nextInt(mixed.size), pulses[random.nextInt(pulses.lastIndex)]) }
    repeat(12) { mixed += pulses.last() }
    val drops = AtomicInteger()
    withEngine(script, dropEveryThird = drops) { engine, _ ->
      engine.followMs = 0
      engine.setPlanScreenOpen(true)
      for (pulse in mixed) {
        engine.onPulse(pulse)
        assertTrue("sync did not settle", engine.awaitIdle(8_000))
      }
      assertRoomMatches(engine, script)
      assertTrue(drops.get() > 0)
    }
  }

  private fun assertRoomMatches(engine: EngineFixture, script: ScriptHost) {
    val dao = engine.database.monitor()
    val conversation = dao.conversations().single()
    assertEquals(script.conversationId, conversation.id)
    assertEquals(script.conversationEtag, conversation.etag)
    assertEquals(script.turnCount, conversation.turnCount)
    val turns = dao.turns(script.conversationId).filter { it.outcome != LiveTurnOutcome }
    assertEquals(script.turns.map { it.id }, turns.map { it.id })
    for ((expected, actual) in script.turns.zip(turns)) {
      assertEquals(expected.index, actual.index)
      assertEquals(expected.etag, actual.etag)
      assertEquals(expected.prompt, actual.prompt)
      assertEquals("", actual.outcome)
      val items = dao.items(actual.id)
      assertEquals(listOf(expected.body), items.map { it.body })
      assertEquals(expected.state, items.single().state)
    }
    val plan = dao.plans().single()
    assertEquals(script.planPath, plan.path)
    assertEquals(script.planEtag, plan.etag)
    assertEquals(script.planRows, plan.rowsJson)
    assertEquals(script.planDocument, plan.documentText)
    assertTrue(dao.turns(script.conversationId).none { it.outcome == LiveTurnOutcome })
  }
}

private class EngineFixture(
  val engine: SyncEngine,
  val database: MonitorDatabase
) {
  fun onPulse(json: String) = engine.onPulse(json)
  fun awaitIdle(timeoutMs: Long = 5_000) = engine.awaitIdle(timeoutMs)
  fun databaseTurns(): List<TurnRow> = database.monitor().turns("c1")
  fun databaseItems(turnId: String): List<ItemRow> = database.monitor().items(turnId)
  fun setPlanScreenOpen(open: Boolean) {
    engine.planScreenOpen = open
  }
  var followMs: Long
    get() = engine.followMs
    set(value) { engine.followMs = value }
}

private fun withEngine(
  script: ScriptHost,
  dispatcher: Dispatcher? = null,
  dropEveryThird: AtomicInteger? = null,
  body: (EngineFixture, MockWebServer) -> Unit
) {
  val database = openTestDatabase()
  val server = MockWebServer()
  val client = testClient()
  val seen = AtomicInteger()
  server.dispatcher = dispatcher ?: object : Dispatcher() {
    override fun dispatch(request: RecordedRequest): MockResponse {
      val count = seen.incrementAndGet()
      if (dropEveryThird != null && count % 3 == 0) {
        dropEveryThird.incrementAndGet()
        return MockResponse().setResponseCode(500).setBody("""{"reason":"dropped"}""")
      }
      return script.serve(request)
    }
  }
  server.start()
  val engine = SyncEngine(database, client, server.url("/"), "desk", clock = { 5_000L })
  val fixture = EngineFixture(engine, database)
  try {
    body(fixture, server)
  } finally {
    engine.close()
    server.shutdown()
    client.dispatcher.executorService.shutdown()
    database.close()
  }
}

private fun testClient(): OkHttpClient {
  return OkHttpClient.Builder()
    .connectTimeout(2, TimeUnit.SECONDS)
    .readTimeout(10, TimeUnit.SECONDS)
    .retryOnConnectionFailure(false)
    .build()
}

private fun awaitStarted(started: AtomicInteger) {
  val deadline = System.currentTimeMillis() + 5_000
  while (started.get() == 0 && System.currentTimeMillis() < deadline) Thread.sleep(10)
  assertTrue(started.get() > 0)
}

private fun drain(server: MockWebServer): List<RecordedRequest> {
  val rows = ArrayList<RecordedRequest>()
  while (true) {
    val request = server.takeRequest(50, TimeUnit.MILLISECONDS) ?: break
    rows += request
  }
  return rows
}

private data class LiveView(
  val turnId: String,
  val turnIndex: Int,
  val turnRev: Long,
  val itemId: String,
  val kind: String,
  val state: String,
  val itemRev: Long,
  val bytes: Long
)

private data class HostTurn(
  val id: String,
  val index: Int,
  val etag: String,
  val prompt: String,
  val itemId: String,
  val body: String,
  val revision: Long,
  val state: String
)

private class ScriptHost {
  var epoch = "e1"
  val conversationId = "c1"
  var title = "Chat"
  var conversationEtag = "c-final"
  var turnCount = 2
  var planPath = "Documents/Plan.md"
  var planTitle = "Plan"
  var planEtag = "plan-1"
  val planRows = """[{"index":0,"level":2,"title":"Start","parent_title":"","status":"not started","actionable":true}]"""
  var planDocument = "# Start\n"
  var listConversations = "lc"
  var listPlans = "lp"
  var listTasks = "lt"
  val turns = ArrayList<HostTurn>()
  var live: LiveView? = null
  val turnsTemplate = listOf(
    HostTurn("t0", 0, "t0", "first", "i0", "one", 1, "done"),
    HostTurn("t1", 1, "t1", "second", "i1", "two", 6, "done")
  )

  init {
    turns += turnsTemplate
  }

  fun pulse(rev: Long): String {
    val liveJson = live?.let { row ->
      """{"turn_id":${js(row.turnId)},"turn_index":${row.turnIndex},"rev":${row.turnRev},"item":{"id":${js(row.itemId)},"kind":${js(row.kind)},"state":${js(row.state)},"rev":${row.itemRev},"bytes":${row.bytes}}}"""
    } ?: "null"
    return """{"epoch":${js(epoch)},"rev":$rev,"server_time":"2026-11-24T10:15:02.120Z","status":{"busy":false},"conversation":{"id":${js(conversationId)},"title":${js(title)},"etag":${js(conversationEtag)},"turn_count":$turnCount},"live":$liveJson,"plan":{"path":${js(planPath)},"etag":${js(planEtag)},"running":false,"item":""},"lists":{"conversations":${js(listConversations)},"plans":${js(listPlans)},"tasks":${js(listTasks)}},"approval":null}"""
  }

  fun serve(request: RecordedRequest): MockResponse {
    val path = request.path.orEmpty().substringBefore('?')
    val query = request.path.orEmpty().substringAfter('?', "")
    val body = when {
      path.startsWith("/v4/items/") -> itemJson(path.removePrefix("/v4/items/"))
      path.startsWith("/v4/turns/") -> turnJson(path.removePrefix("/v4/turns/"), bodies = !query.contains("bodies=0"))
      path.contains("/turns") -> pageJson(queryValue(query, "from").toIntOrNull() ?: 0)
      path == "/v4/plan/document" -> return MockResponse().setBody(planDocument).setHeader("Content-Type", "text/markdown")
      path == "/v4/plan" -> planJson()
      path == "/v4/conversations" -> """[{"id":${js(conversationId)},"title":${js(title)},"created_at":"2026-11-24T10:15:02.000Z","turn_count":$turnCount,"etag":${js(conversationEtag)},"current":true}]"""
      path == "/v4/plans" -> """[{"path":${js(planPath)},"title":${js(planTitle)}}]"""
      path == "/v4/tasks" -> "[]"
      path == "/v4/approval" -> """{"id":"","tool_name":"","summary":"","mode":""}"""
      else -> return MockResponse().setResponseCode(404)
    }
    return if (body == null) MockResponse().setResponseCode(404) else MockResponse().setBody(body)
  }

  private fun itemJson(id: String): String? {
    val turn = turns.firstOrNull { it.itemId == id }
    if (turn != null) {
      return """{"id":${js(turn.itemId)},"rev":${turn.revision},"state":${js(turn.state)},"total_bytes":${turn.body.toByteArray().size},"start":0,"text":${js(turn.body)}}"""
    }
    val row = live?.takeIf { it.itemId == id } ?: return null
    return """{"id":${js(row.itemId)},"rev":${row.itemRev},"state":${js(row.state)},"total_bytes":${row.bytes},"start":0,"text":"tail"}"""
  }

  private fun turnJson(id: String, bodies: Boolean): String? {
    val turn = turns.firstOrNull { it.id == id } ?: live?.takeIf { it.turnId == id }?.let {
      HostTurn(it.turnId, it.turnIndex, "", "", it.itemId, "", it.itemRev, it.state)
    } ?: return null
    return turnObject(turn, bodies)
  }

  private fun pageJson(from: Int): String {
    val page = turns.drop(from)
    val rendered = page.joinToString(",") { turnObject(it, bodies = true) }
    return """{"id":${js(conversationId)},"etag":${js(conversationEtag)},"from":$from,"turns":[$rendered],"next":null}"""
  }

  private fun turnObject(turn: HostTurn, bodies: Boolean): String {
    val body = if (bodies) ""","body":${js(turn.body)}""" else ""
    return """{"id":${js(turn.id)},"etag":${js(turn.etag)},"live":false,"mode":"build","prompt":${js(turn.prompt)},"created_at":"2026-11-24T10:15:02.120Z","error":"","items":[{"id":${js(turn.itemId)},"kind":"answer","state":${js(turn.state)},"rev":${turn.revision},"bytes":${turn.body.toByteArray().size}$body}]}"""
  }

  private fun planJson(): String {
    return """{"path":${js(planPath)},"title":${js(planTitle)},"etag":${js(planEtag)},"running":false,"rows":$planRows}"""
  }
}

private fun scriptHost(): ScriptHost = ScriptHost()

private fun js(text: String): String {
  val out = StringBuilder("\"")
  for (ch in text) {
    when (ch) {
      '\\' -> out.append("\\\\")
      '"' -> out.append("\\\"")
      '\n' -> out.append("\\n")
      else -> out.append(ch)
    }
  }
  out.append('"')
  return out.toString()
}

private fun queryValue(query: String, name: String): String {
  return query.split('&').firstOrNull { it.substringBefore('=') == name }?.substringAfter('=') ?: ""
}
