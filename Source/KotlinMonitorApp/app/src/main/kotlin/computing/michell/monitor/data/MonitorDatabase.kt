package computing.michell.monitor.data

/* Local Room database for the monitor phone (c) 2026 Michell Computing.

   One file, monitor.db. The caller keeps the instance. Schema version 5.
   Version 2 adds the host plan row. Version 3 adds repair, held append, and
   state rows. Version 4 keeps the plan file counts on that row. Version 5
   names the turn and block of each image row.
   Android framework SQLite is the driver. */

import android.content.Context
import androidx.room3.Database
import androidx.room3.Room
import androidx.room3.RoomDatabase
import androidx.room3.migration.Migration
import androidx.sqlite.SQLiteConnection
import androidx.sqlite.driver.AndroidSQLiteDriver
import kotlinx.coroutines.Dispatchers

private val PlanTableMigration = Migration(1, 2) { connection: SQLiteConnection ->
  connection.prepare(
    "CREATE TABLE IF NOT EXISTS `plan` (`host` TEXT NOT NULL, `path` TEXT NOT NULL, `title` TEXT NOT NULL, " +
      "`rowsJson` TEXT NOT NULL, `selected` INTEGER NOT NULL, `updatedAt` INTEGER NOT NULL, PRIMARY KEY(`host`))"
  ).use { statement ->
    statement.step()
  }
}

private val SyncObligationMigration = Migration(2, 3) { connection: SQLiteConnection ->
  connection.prepare(
    "CREATE TABLE IF NOT EXISTS `block_repair` (`host` TEXT NOT NULL, `conversation` TEXT NOT NULL, " +
      "`blockId` TEXT NOT NULL, `revision` INTEGER NOT NULL, `expectedLength` INTEGER NOT NULL, " +
      "`missingBody` INTEGER NOT NULL, `hash` TEXT NOT NULL, `stale` INTEGER NOT NULL, " +
      "`requestId` TEXT NOT NULL, `fetchedBody` TEXT NOT NULL, PRIMARY KEY(`host`, `conversation`, `blockId`), " +
      "FOREIGN KEY(`host`, `conversation`) REFERENCES `conversation`(`host`, `id`) ON UPDATE NO ACTION ON DELETE CASCADE )"
  ).use { statement -> statement.step() }
  connection.prepare(
    "CREATE INDEX IF NOT EXISTS `index_block_repair_host_conversation` ON `block_repair` (`host`, `conversation`)"
  ).use { statement -> statement.step() }
  connection.prepare(
    "CREATE INDEX IF NOT EXISTS `index_block_repair_host_requestId` ON `block_repair` (`host`, `requestId`)"
  ).use { statement -> statement.step() }
  connection.prepare(
    "CREATE TABLE IF NOT EXISTS `held_append` (`host` TEXT NOT NULL, `conversation` TEXT NOT NULL, " +
      "`blockId` TEXT NOT NULL, `seq` INTEGER NOT NULL, `offset` INTEGER NOT NULL, `text` TEXT NOT NULL, " +
      "`streamId` TEXT NOT NULL, PRIMARY KEY(`host`, `conversation`, `blockId`, `seq`), " +
      "FOREIGN KEY(`host`, `conversation`) REFERENCES `conversation`(`host`, `id`) ON UPDATE NO ACTION ON DELETE CASCADE )"
  ).use { statement -> statement.step() }
  connection.prepare(
    "CREATE INDEX IF NOT EXISTS `index_held_append_host_conversation_blockId` ON `held_append` (`host`, `conversation`, `blockId`)"
  ).use { statement -> statement.step() }
  connection.prepare(
    "CREATE TABLE IF NOT EXISTS `host_state` (`host` TEXT NOT NULL, `key` TEXT NOT NULL, `valueJson` TEXT NOT NULL, " +
      "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`host`, `key`), " +
      "FOREIGN KEY(`host`) REFERENCES `host`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )"
  ).use { statement -> statement.step() }
  connection.prepare(
    "CREATE INDEX IF NOT EXISTS `index_host_state_host` ON `host_state` (`host`)"
  ).use { statement -> statement.step() }
}

private val PlanFileCountsMigration = Migration(3, 4) { connection: SQLiteConnection ->
  connection.prepare(
    "CREATE TABLE IF NOT EXISTS `plan_new` (`host` TEXT NOT NULL, `path` TEXT NOT NULL, `title` TEXT NOT NULL, " +
      "`rowsJson` TEXT NOT NULL, `selected` INTEGER NOT NULL, `updatedAt` INTEGER NOT NULL, `revision` TEXT NOT NULL, " +
      "`receivedBytes` INTEGER NOT NULL, `totalBytes` INTEGER NOT NULL, `incomplete` INTEGER NOT NULL, PRIMARY KEY(`host`))"
  ).use { statement -> statement.step() }
  connection.prepare(
    "INSERT INTO `plan_new` (`host`, `path`, `title`, `rowsJson`, `selected`, `updatedAt`, `revision`, `receivedBytes`, `totalBytes`, `incomplete`) " +
      "SELECT `host`, `path`, `title`, `rowsJson`, `selected`, `updatedAt`, '', 0, 0, 0 FROM `plan`"
  ).use { statement -> statement.step() }
  connection.prepare("DROP TABLE `plan`").use { statement -> statement.step() }
  connection.prepare("ALTER TABLE `plan_new` RENAME TO `plan`").use { statement -> statement.step() }
}

/** Rows from before version 5 keep an empty turn and block. They are drawn at the end and are not fetched. */
private val ImagePlaceMigration = Migration(4, 5) { connection: SQLiteConnection ->
  connection.prepare("ALTER TABLE `image` ADD COLUMN `turn` TEXT NOT NULL DEFAULT ''").use { statement -> statement.step() }
  connection.prepare("ALTER TABLE `image` ADD COLUMN `block` TEXT NOT NULL DEFAULT ''").use { statement -> statement.step() }
}

/** Every step from version 1. Tests open an older file with the same list. */
internal val MonitorMigrations = arrayOf(PlanTableMigration, SyncObligationMigration, PlanFileCountsMigration, ImagePlaceMigration)

@Database(
  entities = [
    HostRecord::class,
    ConversationRecord::class,
    TurnRecord::class,
    BlockRecord::class,
    ImageRecord::class,
    PlanRecord::class,
    OutboxRecord::class,
    BlockRepairRecord::class,
    HeldAppendRecord::class,
    HostStateRecord::class
  ],
  version = 5
)
abstract class MonitorDatabase : RoomDatabase() {
  abstract fun hosts(): HostDao
  abstract fun conversations(): ConversationDao
  abstract fun content(): ContentDao
  abstract fun images(): ImageDao
  abstract fun plans(): PlanDao
  abstract fun outbox(): OutboxDao
  abstract fun sync(): SyncDao
}

fun openMonitorDatabase(context: Context): MonitorDatabase {
  val path = context.applicationContext.getDatabasePath("monitor.db").absolutePath
  return Room.databaseBuilder<MonitorDatabase>(context.applicationContext, path)
    .setDriver(AndroidSQLiteDriver())
    .addMigrations(*MonitorMigrations)
    .setQueryCoroutineContext(Dispatchers.IO)
    .build()
}
