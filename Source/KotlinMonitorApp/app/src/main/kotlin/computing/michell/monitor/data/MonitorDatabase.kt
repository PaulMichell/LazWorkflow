package computing.michell.monitor.data

/* Local Room database for the monitor phone (c) 2026 Michell Computing.

   One file, monitor.db. The caller keeps the instance. Schema version 2.
   Version 2 adds the host plan row. Android framework SQLite is the driver. */

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

@Database(
  entities = [
    HostRecord::class,
    ConversationRecord::class,
    TurnRecord::class,
    BlockRecord::class,
    ImageRecord::class,
    PlanRecord::class,
    OutboxRecord::class
  ],
  version = 2
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
    .addMigrations(PlanTableMigration)
    .setQueryCoroutineContext(Dispatchers.IO)
    .build()
}
