package computing.michell.monitor.data

/* Local Room database for the monitor phone (c) 2026 Michell Computing.

   One file, monitor.db. Schema version 1. The caller keeps the instance.
   Android uses the framework driver. Tests pass a JVM SQLite driver. */

import android.content.Context
import androidx.room3.Database
import androidx.room3.Room
import androidx.room3.RoomDatabase
import androidx.sqlite.SQLiteDriver
import androidx.sqlite.driver.AndroidSQLiteDriver
import computing.michell.monitor.ui.model.MonitorDatabaseName
import kotlinx.coroutines.Dispatchers

@Database(
  entities = [
    HostRow::class,
    ConversationRow::class,
    TurnRow::class,
    ItemRow::class,
    ImageRow::class,
    PlanCacheRow::class,
    OutboxRow::class
  ],
  version = 1,
  exportSchema = true
)
abstract class MonitorDatabase : RoomDatabase() {
  abstract fun monitor(): MonitorDao
}

fun openMonitorDatabase(path: String, driver: SQLiteDriver, allowMainThread: Boolean = false): MonitorDatabase {
  val builder = Room.databaseBuilder<MonitorDatabase>(name = path)
    .setDriver(driver)
    .setQueryCoroutineContext(Dispatchers.IO)
  if (allowMainThread) builder.allowMainThreadQueries()
  return builder.build()
}

fun openMonitorDatabase(context: Context): MonitorDatabase {
  val file = context.applicationContext.getDatabasePath(MonitorDatabaseName)
  file.parentFile?.mkdirs()
  return openMonitorDatabase(file.absolutePath, AndroidSQLiteDriver())
}
