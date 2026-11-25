package computing.michell.monitor.ui

/* Pulse loop and sync engine for one paired desktop (c) 2026 Michell Computing.

   The view model observes this session's link, pulse and Room database.
   An unpaired phone does not open a socket. */

import android.app.Application
import android.net.ConnectivityManager
import computing.michell.monitor.WatchBridge
import computing.michell.monitor.data.MonitorDatabase
import computing.michell.monitor.data.openMonitorDatabase
import computing.michell.monitor.net.CommandSender
import computing.michell.monitor.net.SaveQuestion
import computing.michell.monitor.net.LinkState
import computing.michell.monitor.net.MonitorHttp
import computing.michell.monitor.net.PairingStore
import computing.michell.monitor.net.PulseLoop
import computing.michell.monitor.net.PulseSource
import computing.michell.monitor.net.SyncEngine
import computing.michell.monitor.net.WifiRoute
import computing.michell.monitor.net.WifiSample
import computing.michell.monitor.net.WifiSocketFactory
import computing.michell.monitor.net.requestPulse
import computing.michell.monitor.ui.model.MonitorLimits
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

class MonitorSession(private val application: Application) : AutoCloseable {
  val database: MonitorDatabase = openMonitorDatabase(application)
  private val pairing = runCatching { PairingStore(application) }.getOrNull()
  private val linkState = MutableStateFlow<LinkState>(LinkState.Stopped)
  val link: StateFlow<LinkState> = linkState.asStateFlow()
  private val pulseState = MutableStateFlow("")
  val pulseJson: StateFlow<String> = pulseState.asStateFlow()
  private val seenState = MutableStateFlow(0L)
  val seenAtMs: StateFlow<Long> = seenState.asStateFlow()
  var paired: Boolean = false
    private set

  private val lifetime = SupervisorJob()
  private var generation = SupervisorJob(lifetime)
  private var loop: PulseLoop? = null
  private var sync: SyncEngine? = null
  private var commands: CommandSender? = null
  var onSaveQuestion: (SaveQuestion) -> Unit = {}

  fun sendPrompt(text: String): String = commands?.send(text).orEmpty()

  fun runPlan(): String = commands?.runPlan().orEmpty()

  fun stopPlan(): String = commands?.stopPlan().orEmpty()

  fun workOnPlan(section: Int): String = commands?.workOnPlan(section).orEmpty()

  fun runTask(taskId: String, note: String): String = commands?.runTask(taskId, note).orEmpty()

  fun insertTask(taskId: String, note: String): String = commands?.insertTask(taskId, note).orEmpty()

  fun decideApproval(toolId: String, decision: String): String = commands?.approval(toolId, decision).orEmpty()

  fun confirmSave(id: String) { commands?.confirmSave(id) }

  fun declineSave(id: String) { commands?.declineSave(id) }

  fun approvalDetail(): String = sync?.approvalDetail().orEmpty()

  fun steerPrompt(text: String): String = commands?.steer(text).orEmpty()

  fun editQueued(id: String, text: String): Boolean = commands?.editPrompt(id, text) ?: false

  fun deleteQueued(id: String): Boolean = commands?.deletePrompt(id) ?: false

  fun retarget(address: String, port: Int) {
    detach()
    val record = pairing?.let { store ->
      runCatching {
        if (address.isNotEmpty()) store.lookup(address, port) else store.selected()
      }.getOrNull()
    }
    if (record == null || !record.paired) {
      paired = false
      linkState.value = LinkState.Unpaired
      pulseState.value = ""
      return
    }
    attach(record.address, record.port, record.token)
  }

  fun foreground() {
    val current = loop ?: return
    current.foreground()
    current.start()
  }

  fun background(watching: Boolean) {
    loop?.background(watching)
    WatchBridge.setWatching(watching)
  }

  fun touch() {
    loop?.touch()
  }

  fun planOpen(open: Boolean) {
    sync?.planScreenOpen = open
  }

  fun followHead(following: Boolean) {
    sync?.followHead = following
  }

  override fun close() {
    detach()
    lifetime.cancel()
    database.close()
  }

  private fun attach(address: String, port: Int, token: String) {
    val url = "https://$address:$port/".toHttpUrlOrNull() ?: run {
      paired = false
      linkState.value = LinkState.Unpaired
      return
    }
    val connectivity = application.getSystemService(ConnectivityManager::class.java)
    val sample: WifiSample = if (connectivity == null) WifiSample { } else WifiRoute(connectivity)
    val http = MonitorHttp(pairing ?: return, WifiSocketFactory(sample))
    val created = PulseLoop(PulseSource { query -> requestPulse(http.pulse, url, query) })
    val endpoint = "$address:$port"
    val engine = SyncEngine(database, http.reads, url, endpoint, token)
    val sender = CommandSender(database, http.commands, url, endpoint, token, onSaveQuestion = { question -> onSaveQuestion(question) })
    sender.noteLink(false)
    created.useToken(token)
    loop = created
    WatchBridge.attach(created)
    sync = engine
    commands = sender
    paired = true
    val scope = CoroutineScope(generation + Dispatchers.IO)
    scope.launch {
      created.state.collect { state ->
        linkState.value = state
        sender.noteLink(state is LinkState.Connected)
      }
    }
    scope.launch {
      created.pulses.collect { message ->
        engine.onPulse(message.json)
        sender.onPulse(message.json)
        pulseState.value = message.json
        seenState.value = message.at
        WatchBridge.publish(message.json)
      }
    }
    created.start()
  }

  private fun detach() {
    generation.cancel()
    generation = SupervisorJob(lifetime)
    val current = loop
    WatchBridge.detach(current)
    current?.close()
    loop = null
    sync?.close()
    sync = null
    commands = null
    paired = false
  }
}

fun savedMonitorPort(text: String): Int {
  return text.toIntOrNull()?.takeIf { it in 1..65535 } ?: MonitorLimits.ListenPort
}
