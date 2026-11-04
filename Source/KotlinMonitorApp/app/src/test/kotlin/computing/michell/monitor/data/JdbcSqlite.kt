package computing.michell.monitor.data

/* Desktop SQLite for Room unit tests (c) 2026 Michell Computing.

   The Android bundled library will not load on a Linux JVM. This driver
   still opens a real SQLite file. Room's BEGIN, savepoint, and ROLLBACK
   are executed as SQL so a thrown transaction rolls back. A uniqueness
   failure is reported as the Android exception Room's upsert expects. */

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.SQLiteDriver
import androidx.sqlite.SQLiteStatement
import java.sql.DriverManager
import java.sql.PreparedStatement
import java.sql.ResultSet
import java.sql.Types

class JdbcSqliteDriver : SQLiteDriver {
  private val open = HashMap<String, SharedSqlite>()

  override fun open(fileName: String): SQLiteConnection {
    val shared = open.getOrPut(fileName) { SharedSqlite(connect(fileName)) }
    shared.refs += 1
    return JdbcSqliteConnection(shared) {
      shared.refs -= 1
      if (shared.refs <= 0) {
        open.remove(fileName)
        if (!shared.connection.isClosed) shared.connection.close()
      }
    }
  }
}

private class SharedSqlite(val connection: java.sql.Connection) {
  var depth = 0
  var refs = 0
}

private fun connect(fileName: String): java.sql.Connection {
  Class.forName("org.sqlite.JDBC")
  val url = if (fileName == ":memory:") "jdbc:sqlite::memory:" else "jdbc:sqlite:$fileName"
  val connection = DriverManager.getConnection(url)
  connection.autoCommit = true
  connection.createStatement().use { statement ->
    statement.execute("PRAGMA foreign_keys = ON")
    statement.execute("PRAGMA busy_timeout = 5000")
  }
  return connection
}

private class JdbcSqliteConnection(
  private val shared: SharedSqlite,
  private val onClose: () -> Unit
) : SQLiteConnection {
  override fun inTransaction(): Boolean = shared.depth > 0

  override fun prepare(sql: String): SQLiteStatement {
    return JdbcSqliteStatement(shared.connection, sql) { delta ->
      shared.depth = (shared.depth + delta).coerceAtLeast(0)
    }
  }

  override fun close() {
    onClose()
  }
}

private class JdbcSqliteStatement(
  private val connection: java.sql.Connection,
  private val sql: String,
  private val onTransaction: (Int) -> Unit
) : SQLiteStatement {
  private var statement: PreparedStatement = connection.prepareStatement(sql)
  private val bindings = HashMap<Int, Any?>()
  private var rows = emptyList<Array<Any?>>()
  private var names = emptyList<String>()
  private var types = IntArray(0)
  private var cursor = -1
  private var started = false

  override fun bindBlob(index: Int, value: ByteArray) = bind(index, value)
  override fun bindDouble(index: Int, value: Double) = bind(index, value)
  override fun bindLong(index: Int, value: Long) = bind(index, value)
  override fun bindText(index: Int, value: String) = bind(index, value)
  override fun bindNull(index: Int) = bind(index, null)

  override fun step(): Boolean {
    ensureLoaded()
    cursor += 1
    return cursor < rows.size
  }

  override fun reset() {
    started = false
    cursor = -1
    rows = emptyList()
    statement.close()
    statement = connection.prepareStatement(sql)
    for ((index, value) in bindings) apply(index, value)
  }

  override fun clearBindings() {
    bindings.clear()
    statement.clearParameters()
  }

  override fun close() {
    statement.close()
  }

  override fun getBlob(index: Int): ByteArray = current(index) as ByteArray
  override fun getDouble(index: Int): Double = (current(index) as Number).toDouble()
  override fun getLong(index: Int): Long = (current(index) as Number).toLong()
  override fun getText(index: Int): String = current(index).toString()
  override fun isNull(index: Int): Boolean = current(index) == null
  override fun getColumnCount(): Int {
    ensureLoaded()
    return names.size
  }

  override fun getColumnName(index: Int): String {
    ensureLoaded()
    return names[index]
  }

  override fun getColumnType(index: Int): Int = if (index in types.indices) types[index] else 5

  private fun bind(index: Int, value: Any?) {
    bindings[index] = value
    apply(index, value)
  }

  private fun apply(index: Int, value: Any?) {
    when (value) {
      null -> statement.setNull(index, Types.NULL)
      is ByteArray -> statement.setBytes(index, value)
      is Double -> statement.setDouble(index, value)
      is Long -> statement.setLong(index, value)
      is String -> statement.setString(index, value)
      else -> statement.setObject(index, value)
    }
  }

  private fun current(index: Int): Any? = rows[cursor][index]

  private fun ensureLoaded() {
    if (started) return
    if (controlTransaction()) return
    started = true
    load()
  }

  private fun controlTransaction(): Boolean {
    val trimmed = sql.trim().lowercase()
    val transactional = trimmed.startsWith("begin") || trimmed.startsWith("commit") || trimmed.startsWith("end ") ||
      trimmed.startsWith("rollback") || trimmed.startsWith("savepoint") || trimmed.startsWith("release")
    if (!transactional) return false
    connection.createStatement().use { command -> command.execute(sql) }
    when {
      trimmed.startsWith("begin") || trimmed.startsWith("savepoint") -> onTransaction(1)
      trimmed.startsWith("rollback") && !trimmed.contains(" to ") -> onTransaction(-100)
      else -> onTransaction(-1)
    }
    started = true
    return true
  }

  private fun load() {
    val hasRows = try {
      statement.execute()
    } catch (error: java.sql.SQLException) {
      if (isUniqueConflict(error)) {
        throw android.database.sqlite.SQLiteConstraintException(error.message + " SQLITE_CONSTRAINT_PRIMARYKEY")
      }
      throw error
    }
    if (!hasRows) return
    val result = statement.resultSet ?: return
    try {
      val meta = result.metaData
      val count = meta.columnCount
      names = (1..count).map { column -> meta.getColumnName(column) }
      types = IntArray(count) { column -> columnType(meta.getColumnType(column + 1)) }
      val loaded = ArrayList<Array<Any?>>()
      while (result.next()) loaded += readRow(result, count)
      rows = loaded
    } finally {
      result.close()
    }
  }

  private fun isUniqueConflict(error: java.sql.SQLException): Boolean {
    val text = error.message.orEmpty()
    return text.contains("SQLITE_CONSTRAINT_PRIMARYKEY") || text.contains("SQLITE_CONSTRAINT_UNIQUE") ||
      text.contains("UNIQUE constraint failed") || text.contains("PRIMARY KEY")
  }

  private fun readRow(result: ResultSet, count: Int): Array<Any?> {
    return Array(count) { column ->
      val value = result.getObject(column + 1)
      if (result.wasNull()) null else value
    }
  }

  private fun columnType(jdbc: Int): Int {
    return when (jdbc) {
      Types.INTEGER, Types.BIGINT, Types.SMALLINT, Types.TINYINT, Types.BIT -> 1
      Types.FLOAT, Types.DOUBLE, Types.REAL, Types.NUMERIC, Types.DECIMAL -> 2
      Types.BLOB, Types.BINARY, Types.VARBINARY, Types.LONGVARBINARY -> 4
      Types.NULL -> 5
      else -> 3
    }
  }
}
