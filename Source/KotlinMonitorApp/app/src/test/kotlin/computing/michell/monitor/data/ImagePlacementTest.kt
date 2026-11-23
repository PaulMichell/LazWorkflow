package computing.michell.monitor.data

/* Pictures keep their turn and block, are drawn there, and are saved when fetched (c) 2026 Michell Computing.

   The rework that moved the screen onto Room rows drew every picture in one
   note at the end and never asked the desktop for one. These cover the rows
   and the file; ImageCacheTest covers which pictures are asked for. */

import androidx.room3.RoomDatabase
import computing.michell.monitor.protocol.MonitorEvent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.sql.DriverManager

class ImagePlacementTest {
  @Test
  fun aPictureIsDrawnOnItsBlockOrOnItsTurnsPrompt() {
    val turns = listOf(
      TurnRecord("h", "c", "t1", 0, "build", "look", "", "ok", 0, ""),
      TurnRecord("h", "c", "t2", 1, "build", "and this", "", "ok", 0, "")
    )
    val blocks = listOf(
      BlockRecord("h", "c", "t1", "t1-user", 0, "user", "", "look", "ok"),
      BlockRecord("h", "c", "t1", "t1-tool", 1, "tool", "read_image", "", "ok"),
      BlockRecord("h", "c", "t2", "t2-user", 0, "user", "", "and this", "ok")
    )
    val images = listOf(
      ImageRecord("on-tool", "h", "c", "", 0, "", 0, "t1", "t1-tool"),
      ImageRecord("on-prompt", "h", "c", "", 0, "image/png", 0, "t2", ""),
      ImageRecord("before-schema-5", "h", "c", "", 0, "", 0)
    )
    val document = documentFromRows(turns, blocks, emptyList(), images)
    val first = document.turns.first { turn -> turn.id == "t1" }
    assertEquals(listOf("on-tool"), first.blocks.first { block -> block.blockId == "t1-tool" }.images.map { image -> image.id })
    assertTrue(first.blocks.first { block -> block.blockId == "t1-user" }.images.isEmpty())
    val second = document.turns.first { turn -> turn.id == "t2" }
    assertEquals(listOf("on-prompt"), second.blocks.first { block -> block.blockId == "t2-user" }.images.map { image -> image.id })
    assertEquals(
      listOf("before-schema-5"),
      second.blocks.first { block -> block.blockId == StoredImagesBlockId }.images.map { image -> image.id }
    )
    // Not fetched yet is loading, not missing.
    val all = document.turns.flatMap { turn -> turn.blocks }.flatMap { block -> block.images }
    assertFalse(all.any { image -> image.missing })
    assertTrue(all.all { image -> image.displayPath.isEmpty() })
  }

  @Test
  fun theNoticeRecordsTheTurnAndBlock() {
    val events = listOf(
      MonitorEvent.TurnOpen("c", "s", 1, "t1", 0, "build", "look", ""),
      MonitorEvent.BlockOpen("c", "s", 2, "t1", "t1-tool", 0, "tool", "read_image"),
      MonitorEvent.ImageAdded("c", "s", 3, "t1", "img-1", "shot.png", "image/png", 4, 3, 0, "t1-tool")
    )
    val reduced = reduceSync("h", 1L, null, emptyList(), emptyList(), emptyList(), events)
    val image = reduced.commit?.images?.single()
    assertNotNull(image)
    assertEquals("t1", image!!.turn)
    assertEquals("t1-tool", image.block)
    assertEquals("", image.filePath)
    // A later notice without a block keeps the block the first one named.
    val again = MonitorEvent.ImageAdded("c", "s", 4, "t1", "img-1", "shot.png", "image/png", 4, 3, 0, "")
    val conversation = reduced.commit!!.conversation
    val second = reduceSync("h", 2L, conversation, emptyList(), emptyList(), listOf(image), listOf(again))
    assertEquals("t1-tool", second.commit?.images?.single()?.block)
  }

  @Test
  fun aFetchedPictureIsSavedAndAnUnfetchedOneSurvivesRetention() = runBlocking {
    val file = File.createTempFile("monitor-images", ".db")
    file.delete()
    val root = Files.createTempDirectory("monitor-images").toFile()
    val database = openImageDatabase(file, migrate = false)
    try {
      val dao = database.sync()
      dao.insertHost(HostRecord("host-1", "", ""))
      dao.insertConversation(ConversationRecord("c1", "host-1", "", "Pictures", "", 1, 1, false))
      dao.upsertImages(listOf(
        ImageRecord("img-1", "host-1", "c1", "", 0, "image/png", 0, "t1", "b1"),
        ImageRecord("img-2", "host-1", "c1", "", 0, "image/png", 0, "t1", "b1")
      ))
      val repository = ConversationRepository(database, root)
      repository.retain()
      assertEquals(setOf("img-1", "img-2"), dao.loadImages("host-1", "c1").map { image -> image.id }.toSet())
      val bytes = byteArrayOf(1, 2, 3, 4)
      assertTrue(repository.storeFetchedImage("host-1", "c1", "img-1", bytes))
      val stored = dao.loadImages("host-1", "c1").first { image -> image.id == "img-1" }
      assertTrue(File(stored.filePath).isFile)
      assertEquals(bytes.toList(), File(stored.filePath).readBytes().toList())
      assertEquals(4L, stored.size)
      assertEquals("b1", stored.block)
      assertFalse(repository.storeFetchedImage("host-1", "c1", "not-announced", bytes))
    } finally {
      database.close()
      file.delete()
      root.deleteRecursively()
    }
  }

  @Test
  fun aVersionFourFileGainsTheImagePlaceColumns() = runBlocking {
    val file = File.createTempFile("monitor-v4", ".db")
    file.delete()
    try {
      // Room writes version 5. Turning it back into a version 4 file leaves only the 4 to 5 step to run.
      val created = openImageDatabase(file, migrate = false)
      // Room creates the file on first use.
      created.sync().findHost("none")
      created.close()
      DriverManager.getConnection("jdbc:sqlite:" + file.absolutePath).use { connection ->
        connection.createStatement().use { statement ->
          statement.execute("ALTER TABLE `image` DROP COLUMN `turn`")
          statement.execute("ALTER TABLE `image` DROP COLUMN `block`")
          statement.execute("INSERT INTO host (id, fingerprint, name) VALUES ('host-1', '', '')")
          statement.execute(
            "INSERT INTO conversation (id, host, projectRoot, title, streamId, seq, updatedAt, pinned) " +
              "VALUES ('c1', 'host-1', '', 'Old', '', 1, 1, 0)"
          )
          statement.execute(
            "INSERT INTO image (id, host, conversation, filePath, bytes, mime, size) " +
              "VALUES ('old', 'host-1', 'c1', '', 0, 'image/png', 0)"
          )
          statement.execute("PRAGMA user_version = 4")
        }
      }
      val database = openImageDatabase(file, migrate = true)
      try {
        val old = database.sync().loadImages("host-1", "c1").single()
        assertEquals("", old.turn)
        assertEquals("", old.block)
      } finally {
        database.close()
      }
    } finally {
      file.delete()
      File(file.path + "-journal").delete()
    }
  }
}

@Suppress("UNCHECKED_CAST")
private fun openImageDatabase(file: File, migrate: Boolean): MonitorDatabase {
  val ctor = RoomDatabase.Builder::class.java.declaredConstructors.first { constructor -> constructor.parameterCount == 4 }
  ctor.isAccessible = true
  val builder = ctor.newInstance(MonitorDatabase::class, file.absolutePath, { MonitorDatabase_Impl() }, null) as RoomDatabase.Builder<MonitorDatabase>
  if (migrate) builder.addMigrations(*MonitorMigrations)
  return builder
    .setDriver(JdbcSqliteDriver())
    .setJournalMode(RoomDatabase.JournalMode.TRUNCATE)
    .allowMainThreadQueries()
    .setQueryCoroutineContext(Dispatchers.IO)
    .build()
}
