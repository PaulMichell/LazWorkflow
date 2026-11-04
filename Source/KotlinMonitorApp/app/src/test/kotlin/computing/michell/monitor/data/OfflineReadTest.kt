package computing.michell.monitor.data

/* Offline read and a gap, on a real Room file (c) 2026 Michell Computing.

   Process death is close and reopen. A mocked store does not prove the
   transaction. No socket is opened. */

import androidx.room3.RoomDatabase
import androidx.room3.withWriteTransaction
import computing.michell.monitor.connection.CatalogueResult
import computing.michell.monitor.connection.SessionPort
import computing.michell.monitor.protocol.MonitorEvent
import computing.michell.monitor.protocol.OfflineCacheDocument
import computing.michell.monitor.protocol.OpenBlockBody
import computing.michell.monitor.protocol.OutlineBlock
import computing.michell.monitor.protocol.OutlineTurn
import computing.michell.monitor.protocol.PlanRow
import computing.michell.monitor.protocol.SyncFrame
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.encodeOfflineCache
import computing.michell.monitor.protocol.encodeSyncResume
import computing.michell.monitor.protocol.prefixHash
import computing.michell.monitor.ui.DisplayPreferences
import computing.michell.monitor.ui.MonitorClock
import computing.michell.monitor.ui.MonitorCoordinator
import computing.michell.monitor.ui.MonitorUi
import computing.michell.monitor.ui.planFetchVisible
import computing.michell.monitor.ui.shownPlanBody
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class OfflineReadTest {
  @Test
  fun threeSlicesSurviveCloseWithNoSocket() = runBlocking {
    val room = openRoom()
    try {
      val clock = RoomClock(1_000L)
      val applier = applier(room.database, clock)
      commit(applier, listOf(turn(1, "t-1"), block(2, "t-1", "b-1"), append(3, "b-1", 0, "kept-body")), clock)
      val reopened = room.reopen()
      val stored = reopened.sync().loadBlocks("host-1", "c1").single()
      assertEquals("kept-body", stored.body)
      assertEquals(3L, reopened.sync().loadConversation("host-1", "c1")!!.seq)
    } finally {
      room.delete()
    }
  }

  @Test
  fun aGapKeepsBodiesAndStatusCanClear() = runBlocking {
    val room = openRoom()
    try {
      val clock = RoomClock(1_000L)
      val applier = SyncApplier("host-1", RoomSyncStore(room.database), clock)
      commit(applier, listOf(turn(1, "t-1"), block(2, "t-1", "b-1"), append(3, "b-1", 0, "kept-body")), clock)
      val gapped = commit(applier, listOf(append(5, "b-1", 9, "skipped")), clock)
      val resume = gapped.filterIsInstance<SyncEffect.Resume>().single()
      assertEquals(3L, resume.seq)
      assertEquals("kept-body", room.database.sync().loadBlocks("host-1", "c1").single().body)
      applier.offerFrame(SyncFrame.State("status", """{"busy":true}"""))
      val cleared = applier.offerFrame(SyncFrame.State("status", """{"busy":false}"""))
      assertTrue(cleared.any { effect -> effect is SyncEffect.StateApplied })
      val ui = applyStateValue(MonitorUi(statusBusy = true), "status", """{"busy":false}""")
      assertFalse(ui.statusBusy)
      assertFalse(ui.view.busy)
      assertEquals(3L, room.database.sync().loadConversation("host-1", "c1")!!.seq)
      val reopened = room.reopen()
      assertEquals("false", stateFlag(reopened, "busy"))
      assertEquals("kept-body", reopened.sync().loadBlocks("host-1", "c1").single().body)
      val fillClock = RoomClock(2_000L)
      val filled = SyncApplier("host-1", RoomSyncStore(reopened), fillClock)
      commit(filled, listOf(append(4, "b-1", 9, "gap"), append(5, "b-1", 12, "-tail")), fillClock)
      assertEquals(5L, reopened.sync().loadConversation("host-1", "c1")!!.seq)
      assertEquals("kept-bodygap-tail", reopened.sync().loadBlocks("host-1", "c1").single().body)
    } finally {
      room.delete()
    }
  }

  @Test
  fun aBaselineKeepsMatchingBodiesAndRemovesTurnsOnlyAtEnd() = runBlocking {
    val room = openRoom()
    try {
      val clock = RoomClock(1_000L)
      val applier = applier(room.database, clock)
      commit(applier, listOf(
        turn(1, "t-keep"),
        block(2, "t-keep", "b-keep"),
        append(3, "b-keep", 0, "same"),
        turn(4, "t-gone"),
        block(5, "t-gone", "b-stale"),
        append(6, "b-stale", 0, "old"),
        block(7, "t-keep", "b-open", 1),
        append(8, "b-open", 0, "old-open")
      ), clock)
      applier.offerFrame(SyncFrame.SnapshotBegin(
        "c1", "stream-b", 9L, "Title", "/work", 1, emptyList(),
        OpenBlockBody("b-open", 3L, "", 0, ""),
        emptyList()
      ))
      applier.offerFrame(SyncFrame.SnapshotPage("c1", "stream-b", 9L, 1, 1, outline(), null))
      assertEquals("t-gone", room.database.sync().loadTurns("host-1", "c1").first { it.turnId == "t-gone" }.turnId)
      val ended = applier.offerFrame(SyncFrame.SnapshotEnd("c1", "stream-b", 9L))
      val openFetch = ended.filterIsInstance<SyncEffect.FetchBlock>().single { it.blockId == "b-open" }
      assertTrue(openFetch.open)
      assertEquals("same", room.database.sync().loadBlocks("host-1", "c1").first { it.blockId == "b-keep" }.body)
      assertEquals("old", room.database.sync().loadBlocks("host-1", "c1").first { it.blockId == "b-stale" }.body)
      assertTrue(room.database.sync().loadRepair("host-1", "c1", "b-stale")!!.stale)
      assertFalse(ended.filterIsInstance<SyncEffect.FetchBlock>().any { it.blockId == "b-keep" })
      assertEquals("stream-b", room.database.sync().loadConversation("host-1", "c1")!!.streamId)
      assertTrue(room.database.sync().loadTurns("host-1", "c1").none { it.turnId == "t-gone" })
    } finally {
      room.delete()
    }
  }

  @Test
  fun appendsDuringFetchFinishAsTheHostBody() = runBlocking {
    val room = openRoom()
    try {
      val clock = RoomClock(1_000L)
      val applier = applier(room.database, clock)
      commit(applier, listOf(turn(1, "t-1"), block(2, "t-1", "b-1")), clock)
      val first = commit(applier, listOf(append(3, "b-1", 5, "tail")), clock)
      val fetch = first.filterIsInstance<SyncEffect.FetchBlock>().singleOrNull()
        ?: throw AssertionError("effects=$first body=${room.database.sync().loadBlocks("host-1", "c1")}")
      val second = commit(applier, listOf(append(4, "b-1", 9, "!")), clock)
      assertTrue(second.none { effect -> effect is SyncEffect.FetchBlock })
      val done = applier.offerFrame(SyncFrame.BlockData(
        "c1", "b-1", fetch.requestId, 0L, false, 0, "alpha", 5, true
      ))
      assertTrue(done.none { effect -> effect is SyncEffect.FetchBlock })
      assertEquals("alphatail!", room.database.sync().loadBlocks("host-1", "c1").single().body)
    } finally {
      room.delete()
    }
  }

  @Test
  fun aKillBeforeApplyRollsBackAndKeepsTheBatch() = runBlocking {
    val room = openRoom()
    try {
      val clock = RoomClock(1_000L)
      val crashing = CrashStore(RoomSyncStore(room.database), room.database)
      crashing.crashBefore = true
      val applier = SyncApplier("host-1", crashing, clock)
      applier.offer(turn(1, "t-1"))
      applier.offer(block(2, "t-1", "b-1"))
      applier.offer(append(3, "b-1", 0, "later"))
      clock.now = 1_050L
      val failed = applier.tick()
      assertTrue(failed.none { effect -> effect is SyncEffect.Ack })
      assertNull(room.database.hosts().listAll().firstOrNull { it.id == "killed" })
      assertNull(room.database.sync().loadConversation("host-1", "c1"))
      crashing.crashBefore = false
      val retried = applier.tick()
      assertEquals(3L, retried.filterIsInstance<SyncEffect.Ack>().single().seq)
      assertEquals("later", room.database.sync().loadBlocks("host-1", "c1").single().body)
    } finally {
      room.delete()
    }
  }

  @Test
  fun aKillAfterApplyDoesNotAckAboveTheCommit() = runBlocking {
    val room = openRoom()
    try {
      val clock = RoomClock(1_000L)
      val crashing = CrashStore(RoomSyncStore(room.database), room.database)
      crashing.crashAfter = true
      val applier = SyncApplier("host-1", crashing, clock)
      applier.offer(turn(1, "t-1"))
      applier.offer(block(2, "t-1", "b-1"))
      applier.offer(append(3, "b-1", 0, "committed"))
      clock.now = 1_050L
      val failed = applier.tick()
      assertTrue(failed.none { effect -> effect is SyncEffect.Ack && effect.seq > 3L })
      assertTrue(failed.none { effect -> effect is SyncEffect.Ack })
      val reopened = room.reopen()
      assertEquals("committed", reopened.sync().loadBlocks("host-1", "c1").single().body)
      assertEquals(3L, reopened.sync().loadConversation("host-1", "c1")!!.seq)
      val cursor = RoomSyncStore(reopened).cursorOf("host-1", "c1")
      assertEquals(3L, cursor!!.seq)
    } finally {
      room.delete()
    }
  }

  @Test
  fun aDroppedPlanKeepsThePrefixAndNotTheMarkdown() = runBlocking {
    val room = openRoom()
    val files = tempDir("plan-files")
    try {
      val plans = PlanFiles(files)
      val marker = "PLANBODYMARKER"
      val prefix = marker + " prefix"
      val total = (PlanInlineBytes + 1).toLong()
      plans.append("host-1", "Documents/Plan.md", "rev-1", 0L, prefix, total, false)
      val dropped = plans.noteDrop("host-1", "Documents/Plan.md")
      assertTrue(dropped!!.incomplete)
      val rows = listOf(PlanRow(0, 2, "Layout", "", "not started", true))
      ConversationRepository(room.database).savePlan(
        "host-1", "Documents/Plan.md", "Overview", rows, 0, 9L, "rev-1", prefix.length.toLong(), total, true
      )
      val record = room.database.plans().listAll().single()
      assertFalse(record.rowsJson.contains(marker))
      val reopened = room.reopen()
      val stored = ConversationRepository(reopened).loadPlan("host-1")
      assertEquals("Layout", stored!!.rows.single().title)
      assertEquals("", stored.body)
      assertEquals(prefix, PlanFiles(files).readReview("host-1", "Documents/Plan.md", PlanInlineBytes))
      assertTrue(PlanFiles(files).state("host-1", "Documents/Plan.md")!!.incomplete)
      val ui = coordinator().notePlanFile("Documents/Plan.md", "rev-1", prefix.length.toLong(), total, true, prefix)
      assertEquals("", ui.planBody)
      assertEquals("", shownPlanBody(total, prefix))
    } finally {
      room.delete()
      files.deleteRecursively()
    }
  }

  @Test
  fun aSmallPlanIsReadableWithoutAProgressRecord() = runBlocking {
    val files = tempDir("plan-small")
    try {
      val text = "a".repeat(PlanInlineBytes)
      val plans = PlanFiles(files)
      plans.append("host-1", "Documents/Plan.md", "rev-1", 0L, text, text.length.toLong(), true)
      File(files, "host-1").listFiles()?.filter { it.name.endsWith(".meta") }?.forEach { it.delete() }
      assertNull(plans.state("host-1", "Documents/Plan.md"))
      assertEquals(text, plans.readReview("host-1", "Documents/Plan.md", PlanInlineBytes))
      assertFalse(planFetchVisible(text.length.toLong(), text.length.toLong(), false))
      assertEquals(text, shownPlanBody(text.length.toLong(), text))
    } finally {
      files.deleteRecursively()
    }
  }

  @Test
  fun anImportedCacheRowIsReadableAndResumesAsABaseline() = runBlocking {
    val room = openRoom()
    val root = tempDir("monitor-cache-root")
    try {
      val cache = File(root, MonitorCacheDirectoryName)
      cache.mkdirs()
      File(cache, "c-aa.json").writeText(encodeOfflineCache(OfflineCacheDocument(
        listOf(WireTurn(1, "t-1", "Build", "2026-10-29T09:20:00Z", "Add a heartbeat", "")),
        emptyList(), null, "", "", emptyList(), -1, "unsent"
      )))
      File(cache, CacheIndexFileName).writeText(
        "{ \"entries\" : [ { \"fingerprint\" : \"host-1\", \"project_root\" : \"/work\", \"conversation_id\" : \"conversation-1\", " +
          "\"title\" : \"Shown\", \"updated_ms\" : 9, \"turn_count\" : 1, \"file\" : \"c-aa.json\", \"images\" : [ ] } ] }"
      )
      importLegacyCache(root, ConversationRepository(room.database, File(root, "images")), File(root, "images"))
      val reopened = room.reopen()
      val row = reopened.sync().loadConversation("host-1", "conversation-1")
      assertEquals("Add a heartbeat", reopened.sync().loadTurns("host-1", "conversation-1").single().prompt)
      assertEquals(0L, row!!.seq)
      assertEquals("", row.streamId)
      val resume = encodeSyncResume("resume-1", row.id, row.streamId, row.seq)
      assertTrue(resume, resume.contains("\"stream_id\" : \"\""))
      assertTrue(resume, resume.contains("\"cursor\" : 0"))
      assertFalse(resume.contains("\"cursor\" : 1"))
    } finally {
      room.delete()
      root.deleteRecursively()
    }
  }
}

private class RoomClock(var now: Long) : () -> Long {
  override fun invoke(): Long = now
}

private class CrashStore(
  private val inner: RoomSyncStore,
  private val database: MonitorDatabase
) : SyncStore by inner {
  var crashBefore = false
  var crashAfter = false

  override suspend fun apply(hostId: String, events: List<MonitorEvent>, nowMs: Long): SyncApplyResult {
    if (crashBefore) {
      database.withWriteTransaction {
        database.sync().insertHost(HostRecord("killed", "killed", ""))
        throw IllegalStateException("killed before apply returned")
      }
    }
    val applied = inner.apply(hostId, events, nowMs)
    if (crashAfter) throw IllegalStateException("killed after apply returned")
    return applied
  }
}

private class RoomHandle(val file: File, var database: MonitorDatabase) {
  fun reopen(): MonitorDatabase {
    database.close()
    database = openDatabase(file)
    return database
  }

  fun delete() {
    database.close()
    file.delete()
    File(file.path + "-wal").delete()
    File(file.path + "-shm").delete()
    File(file.path + "-journal").delete()
  }
}

private fun openRoom(): RoomHandle {
  val file = File.createTempFile("monitor-room", ".db")
  file.delete()
  return RoomHandle(file, openDatabase(file))
}

@Suppress("UNCHECKED_CAST")
private fun openDatabase(file: File): MonitorDatabase {
  val ctor = RoomDatabase.Builder::class.java.declaredConstructors.first { constructor -> constructor.parameterCount == 4 }
  ctor.isAccessible = true
  val builder = ctor.newInstance(MonitorDatabase::class, file.absolutePath, { MonitorDatabase_Impl() }, null) as RoomDatabase.Builder<MonitorDatabase>
  return builder
    .setDriver(JdbcSqliteDriver())
    .setJournalMode(RoomDatabase.JournalMode.TRUNCATE)
    .allowMainThreadQueries()
    .setQueryCoroutineContext(Dispatchers.IO)
    .build()
}

private fun applier(database: MonitorDatabase, clock: RoomClock): SyncApplier {
  return SyncApplier("host-1", RoomSyncStore(database), clock)
}

private suspend fun commit(
  applier: SyncApplier,
  events: List<MonitorEvent>,
  clock: RoomClock
): List<SyncEffect> {
  for (event in events) applier.offer(event)
  clock.now += SyncBatchWindowMs
  return applier.tick()
}

private fun turn(seq: Long, turnId: String): MonitorEvent.TurnOpen {
  return MonitorEvent.TurnOpen("c1", "stream-a", seq, turnId, 1, "build", "prompt", "")
}

private fun block(seq: Long, turnId: String, blockId: String, ordinal: Int = 0): MonitorEvent.BlockOpen {
  return MonitorEvent.BlockOpen("c1", "stream-a", seq, turnId, blockId, ordinal, "answer", "")
}

private fun append(seq: Long, blockId: String, offset: Int, text: String): MonitorEvent.BlockAppend {
  return MonitorEvent.BlockAppend("c1", "stream-a", seq, blockId, offset, text)
}

private fun outline(): List<OutlineTurn> {
  return listOf(OutlineTurn("t-keep", 1, "prompt", listOf(
    OutlineBlock("b-keep", "answer", "ok", 1L, 4, prefixHash("same")),
    OutlineBlock("b-stale", "answer", "ok", 2L, 3, prefixHash("new")),
    OutlineBlock("b-open", "answer", "running", 3L, 4, prefixHash("live"))
  )))
}

private fun stateFlag(database: MonitorDatabase, name: String): String = runBlocking {
  val row = database.sync().loadState("host-1", "status") ?: return@runBlocking ""
  if (row.valueJson.contains("\"$name\":false")) "false" else "true"
}

private fun coordinator(): MonitorCoordinator {
  val session = object : SessionPort {
    override val promptDraft = ""
    override val hostAddress = ""
    override val hostPort = 0
    override val hostClientId = ""
    override val linkEpoch = 0
    override val commandResults: Flow<CatalogueResult> = emptyFlow()
    override fun nextCommandId() = "1"
    override fun updateDraft(text: String) {}
    override fun sendCatalogue(json: String) {}
    override fun resetImages() {}
  }
  val clock = object : MonitorClock {
    override fun nowMs() = 0L
  }
  val display = object : DisplayPreferences {
    override val showThinking = false
    override val showTools = false
  }
  return MonitorCoordinator(session, clock, display)
}

private fun tempDir(name: String): File {
  val root = File.createTempFile(name, "dir")
  root.delete()
  root.mkdirs()
  return root
}
