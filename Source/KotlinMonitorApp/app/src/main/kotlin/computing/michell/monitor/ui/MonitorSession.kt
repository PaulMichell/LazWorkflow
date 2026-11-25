package computing.michell.monitor.ui

/* Pulse loop and sync engine for one paired desktop (c) 2026 Michell Computing.

   The view model observes this session's link, pulse and Room database.
   An unpaired phone does not open a socket. */

import android.app.Application
import android.net.ConnectivityManager
import computing.michell.monitor.data.MonitorDatabase
import computing.michell.monitor.data.openMonitorDatabase
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
    val engine = SyncEngine(database, http.reads, url, "$address:$port", token)
    created.useToken(token)
    loop = created
    sync = engine
    paired = true
    val scope = CoroutineScope(generation + Dispatchers.IO)
    scope.launch { created.state.collect { linkState.value = it } }
    scope.launch {
      created.pulses.collect { message ->
        engine.onPulse(message.json)
        pulseState.value = message.json
        seenState.value = message.at
      }
    }
    created.start()
  }

  private fun detach() {
    generation.cancel()
    generation = SupervisorJob(lifetime)
    loop?.close()
    loop = null
    sync?.close()
    sync = null
    paired = false
  }
}

fun savedMonitorPort(text: String): Int {
  return text.toIntOrNull()?.takeIf { it in 1..65535 } ?: MonitorLimits.ListenPort
}
