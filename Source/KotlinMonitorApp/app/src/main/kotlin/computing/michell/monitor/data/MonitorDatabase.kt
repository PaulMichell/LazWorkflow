package computing.michell.monitor.data

/* Local Room database for the monitor phone (c) 2026 Michell Computing.

   One file, monitor.db. The caller keeps the instance. Schema version 1.
   Android framework SQLite is the driver. */

import android.content.Context
import androidx.room3.Database
import androidx.room3.Room
import androidx.room3.RoomDatabase
import androidx.sqlite.driver.AndroidSQLiteDriver
import kotlinx.coroutines.Dispatchers

@Database(
  entities = [
    HostRecord::class,
    ConversationRecord::class,
    TurnRecord::class,
    BlockRecord::class,
    ImageRecord::class,
    OutboxRecord::class
  ],
  version = 1
)
abstract class MonitorDatabase : RoomDatabase() {
  abstract fun hosts(): HostDao
  abstract fun conversations(): ConversationDao
  abstract fun content(): ContentDao
  abstract fun images(): ImageDao
  abstract fun outbox(): OutboxDao
}

fun openMonitorDatabase(context: Context): MonitorDatabase {
  val path = context.applicationContext.getDatabasePath("monitor.db").absolutePath
  return Room.databaseBuilder<MonitorDatabase>(context.applicationContext, path)
    .setDriver(AndroidSQLiteDriver())
    .setQueryCoroutineContext(Dispatchers.IO)
    .build()
}
