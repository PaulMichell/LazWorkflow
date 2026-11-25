package computing.michell.monitor.net

/* Commands, the outbox, and offline prompts (c) 2026 Michell Computing.

   Every action is written down with one id, then sent. Stop, steer, stop
   plan and approval go straight to the network and fail visibly if the link
   is down. Prompts and run task wait in the outbox: the first leaves when a
   pulse says can_send, and the next waits until that turn has finished. A
   409 unsaved_edits asks the save question and resends the same id. A 409
   busy waits for the next can_send. A queued prompt can be edited or deleted
   until it is sent. */

import computing.michell.monitor.data.HostRow
import computing.michell.monitor.data.MonitorDatabase
import computing.michell.monitor.data.OutboxFailed
import computing.michell.monitor.data.OutboxPending
import computing.michell.monitor.data.OutboxRow
import computing.michell.monitor.data.OutboxSending
import computing.michell.monitor.data.OutboxSent
import java.io.IOException
import java.util.UUID
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

private val PromptTypes = setOf("send", "run_task")
private val JsonMedia = "application/json; charset=utf-8".toMediaType()

data class CommandResult(
  val id: String,
  val type: String,
  val ok: Boolean,
  val state: String,
  val reason: String,
  val message: String,
  val turnId: String
)

data class SaveQuestion(val id: String, val type: String, val text: String)

class CommandSender(
  private val database: MonitorDatabase,
  private val client: OkHttpClient,
  private val baseUrl: HttpUrl,
  private val endpoint: String,
  private val token: String = "",
  private val clock: () -> Long = { System.currentTimeMillis() },
  private val newId: () -> String = { UUID.randomUUID().toString() },
  private val onSaveQuestion: (SaveQuestion) -> Unit = {},
  private val onResult: (CommandResult) -> Unit = {}
) {
  var linkUp: Boolean = true

  private val dao = database.monitor()
  private val lock = ReentrantLock()
  private var canSend = false
  private var pulseGeneration = 0
  private var acceptedGeneration = -1
  private var awaitingTurn: String? = null
  private var saveHoldId: String? = null
  private var busyHold = false
  private var posting = false
  private var ticks = 0L

  fun send(text: String): String = enqueue("send", textArgs(text, false))

  fun runTask(taskId: String, note: String): String = enqueue("run_task", taskArgs(taskId, note, false))

  fun stop(): String = actNow("stop", "{}")

  fun steer(text: String): String = actNow("steer", """{"text":${jsonString(text)}}""")

  fun stopPlan(): String = actNow("stop_plan", "{}")

  fun approval(toolId: String, decision: String): String {
    return actNow("approval", """{"tool_id":${jsonString(toolId)},"decision":${jsonString(decision)}}""")
  }

  fun setMode(mode: String): String = actNow("set_mode", """{"mode":${jsonString(mode)}}""")

  fun editPrompt(id: String, text: String): Boolean = rewrite(id) { row ->
    val task = row.type == "run_task"
    val note = parseJson(row.argsJson)?.text("note").orEmpty()
    val taskId = parseJson(row.argsJson)?.text("task_id").orEmpty()
    if (task) taskArgs(taskId, note, saveFirst(row)) else textArgs(text, saveFirst(row))
  }

  fun deletePrompt(id: String): Boolean {
    return lock.withLock {
      val row = dao.outboxItem(id) ?: return false
      if (!PromptTypes.contains(row.type) || row.state != OutboxPending || id == saveHoldId) return false
      dao.deleteOutbox(id)
      true
    }
  }

  fun confirmSave(id: String) {
    lock.withLock {
      if (saveHoldId != id) return
      val row = dao.outboxItem(id) ?: return
      val args = if (row.type == "run_task") {
        taskArgs(parseJson(row.argsJson)?.text("task_id").orEmpty(), parseJson(row.argsJson)?.text("note").orEmpty(), true)
      } else {
        textArgs(parseJson(row.argsJson)?.text("text").orEmpty(), true)
      }
      dao.replaceOutbox(row.copy(argsJson = args, state = OutboxPending, lastError = ""))
      saveHoldId = null
    }
    pump()
  }

  fun declineSave(id: String) {
    lock.withLock {
      if (saveHoldId != id) return
      dao.deleteOutbox(id)
      saveHoldId = null
    }
    report(CommandResult(id, "send", false, "declined", "unsaved_edits", "The prompt was not sent.", ""))
  }

  fun onPulse(json: String) {
    val root = parseJson(json)
    val status = root?.field("status")
    val live = parsePulse(json)?.liveTurnId
    lock.withLock {
      pulseGeneration += 1
      canSend = status?.bool("can_send") ?: false
      if (canSend) busyHold = false
      releaseFinishedTurn(live)
    }
    pump()
  }

  private fun enqueue(type: String, argsJson: String): String {
    val id = newId()
    lock.withLock {
      ensureHost()
      dao.replaceOutbox(OutboxRow(id, endpoint, type, argsJson, now(), OutboxPending, ""))
    }
    pump()
    return id
  }

  private fun actNow(type: String, argsJson: String): String {
    val id = newId()
    val row = lock.withLock {
      ensureHost()
      val written = OutboxRow(id, endpoint, type, argsJson, now(), OutboxPending, "")
      dao.replaceOutbox(written)
      written
    }
    if (!linkUp) {
      fail(row, "The link is down.")
      return id
    }
    val answer = post(row, retryReset = false)
    if (answer != null) applyAnswer(row, answer, queued = false)
    return id
  }

  private fun pump() {
    val row = lock.withLock {
      if (posting || saveHoldId != null || awaitingTurn != null || busyHold || !linkUp || !canSend) return
      val next = dao.outbox().firstOrNull { PromptTypes.contains(it.type) && it.state == OutboxPending } ?: return
      posting = true
      dao.replaceOutbox(next.copy(state = OutboxSending))
      next
    }
    try {
      val answer = post(row, retryReset = true)
      if (answer != null) applyAnswer(row, answer, queued = true)
      else lock.withLock { posting = false }
    } catch (error: Exception) {
      lock.withLock {
        posting = false
        dao.outboxItem(row.commandId)?.let { dao.replaceOutbox(it.copy(state = OutboxPending, lastError = error.message ?: "failed")) }
      }
    }
  }

  private fun post(row: OutboxRow, retryReset: Boolean): HttpAnswer? {
    var http = client
    var attempt = 0
    var last = "The link reset."
    while (true) {
      try {
        return execute(row, http)
      } catch (error: Exception) {
        last = error.javaClass.simpleName + ": " + (error.message ?: "")
        attempt += 1
        http = client.newBuilder().connectionPool(okhttp3.ConnectionPool()).build()
        if (!retryReset || attempt >= 2) {
          if (retryReset) {
            lock.withLock {
              dao.outboxItem(row.commandId)?.let { dao.replaceOutbox(it.copy(state = OutboxPending, lastError = last)) }
            }
          } else {
            fail(row, "The link is down.")
          }
          return null
        }
      }
    }
  }

  private fun execute(row: OutboxRow, http: OkHttpClient): HttpAnswer {
    val body = """{"id":${jsonString(row.commandId)},"type":${jsonString(row.type)},"args":${row.argsJson}}"""
    val builder = Request.Builder().url(baseUrl.newBuilder().addPathSegments("v4/commands").build())
      .header("Connection", "close").post(body.toRequestBody(JsonMedia))
    if (token.isNotEmpty()) builder.header("Authorization", "Bearer $token")
    http.newCall(builder.build()).execute().use { response ->
      val text = response.body?.string().orEmpty()
      val parsed = parseJson(text)
      if (parsed?.text("state").isNullOrEmpty() && parsed?.text("reason").isNullOrEmpty()) throw IOException("The link reset.")
      return HttpAnswer(response.code, text)
    }
  }

  private fun applyAnswer(row: OutboxRow, answer: HttpAnswer, queued: Boolean) {
    val parsed = parseJson(answer.body)
    val reason = parsed?.text("reason").orEmpty()
    val state = parsed?.text("state").orEmpty()
    val turnId = parsed?.text("turn_id").orEmpty()
    val message = parsed?.text("message").orEmpty()
    if (answer.code == 409 && reason == "unsaved_edits" && queued) {
      lock.withLock {
        posting = false
        saveHoldId = row.commandId
        dao.outboxItem(row.commandId)?.let { dao.replaceOutbox(it.copy(state = OutboxPending, lastError = reason)) }
      }
      onSaveQuestion(SaveQuestion(row.commandId, row.type, parseJson(row.argsJson)?.text("text").orEmpty()))
      return
    }
    if (answer.code == 409 && reason == "busy" && queued) {
      lock.withLock {
        posting = false
        busyHold = true
        dao.outboxItem(row.commandId)?.let { dao.replaceOutbox(it.copy(state = OutboxPending, lastError = reason)) }
      }
      return
    }
    if (answer.code !in 200..299) {
      if (queued) {
        lock.withLock {
          posting = false
          dao.outboxItem(row.commandId)?.let { dao.replaceOutbox(it.copy(state = OutboxPending, lastError = reason.ifEmpty { answer.code.toString() })) }
        }
      } else {
        fail(row, message.ifEmpty { reason.ifEmpty { "The command was refused." } })
      }
      return
    }
    lock.withLock {
      posting = false
      dao.outboxItem(row.commandId)?.let { dao.replaceOutbox(it.copy(state = OutboxSent, lastError = "")) }
      if (queued && state != "done") {
        awaitingTurn = turnId.ifEmpty { row.commandId }
        acceptedGeneration = pulseGeneration
      }
    }
    report(CommandResult(row.commandId, row.type, true, state.ifEmpty { "done" }, "", message, turnId))
    if (queued && state == "done") pump()
  }

  private fun releaseFinishedTurn(liveTurnId: String?) {
    val waiting = awaitingTurn ?: return
    if (pulseGeneration <= acceptedGeneration) return
    if (liveTurnId != waiting) awaitingTurn = null
  }

  private fun fail(row: OutboxRow, message: String) {
    lock.withLock {
      dao.outboxItem(row.commandId)?.let { dao.replaceOutbox(it.copy(state = OutboxFailed, lastError = message)) }
    }
    report(CommandResult(row.commandId, row.type, false, "failed", "link", message, ""))
  }

  private fun rewrite(id: String, args: (OutboxRow) -> String): Boolean {
    return lock.withLock {
      val row = dao.outboxItem(id) ?: return false
      if (!PromptTypes.contains(row.type) || row.state != OutboxPending || id == saveHoldId) return false
      dao.replaceOutbox(row.copy(argsJson = args(row)))
      true
    }
  }

  private fun saveFirst(row: OutboxRow): Boolean = parseJson(row.argsJson)?.bool("save_first") ?: false

  private fun report(result: CommandResult) {
    onResult(result)
  }

  private fun ensureHost() {
    if (dao.host(endpoint) == null) dao.replaceHost(HostRow(endpoint, "", endpoint, "", 0))
  }

  private fun now(): Long {
    ticks += 1
    return clock() + ticks
  }
}

private data class HttpAnswer(val code: Int, val body: String)

private fun textArgs(text: String, saveFirst: Boolean): String {
  return """{"text":${jsonString(text)},"save_first":$saveFirst}"""
}

private fun taskArgs(taskId: String, note: String, saveFirst: Boolean): String {
  return """{"task_id":${jsonString(taskId)},"note":${jsonString(note)},"save_first":$saveFirst}"""
}

internal fun jsonString(text: String): String {
  val out = StringBuilder("\"")
  for (ch in text) {
    when (ch) {
      '\\' -> out.append("\\\\")
      '"' -> out.append("\\\"")
      '\n' -> out.append("\\n")
      '\r' -> out.append("\\r")
      else -> out.append(ch)
    }
  }
  out.append('"')
  return out.toString()
}
