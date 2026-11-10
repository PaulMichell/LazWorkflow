package computing.michell.monitor.connection

/* Wi-Fi callback for the monitor link (c) 2026 Michell Computing.

   Registers ConnectivityManager.NetworkCallback for TRANSPORT_WIFI.
   A desk LAN may have no upstream internet and no validated default route,
   so neither is required. onLost is not a loss while allNetworks still has
   Wi-Fi. A first empty sample waits for a second sample before onDown. */

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import java.util.concurrent.atomic.AtomicInteger

/** How long a roam is allowed to look like a loss before the second sample. */
const val WifiLossConfirmMs = 500L

/**
 * The callback's tracked set is the first sample. allNetworks is the second.
 * onDown runs only when both say Wi-Fi is gone. Internet capability is irrelevant.
 */
internal class WifiLossGate(
  private val onUp: () -> Unit,
  private val onDown: () -> Unit,
  private val wifiPresent: () -> Boolean,
  private val confirmLater: (() -> Unit) -> Unit
) {
  private val tracked = HashSet<Any>()
  private val generation = AtomicInteger(0)

  fun onAvailable(network: Any) {
    synchronized(tracked) { tracked.add(network) }
    generation.incrementAndGet()
    onUp()
  }

  fun onLost(network: Any) {
    val empty = synchronized(tracked) {
      tracked.remove(network)
      tracked.isEmpty()
    }
    // Another network, or allNetworks still listing Wi-Fi, is not a loss.
    if (!empty || wifiPresent()) {
      generation.incrementAndGet()
      return
    }
    confirmAbsent()
  }

  /** First sample saw no Wi-Fi. The banner waits for the second sample. */
  fun confirmAbsent() {
    val stamp = generation.incrementAndGet()
    confirmLater {
      if (stamp != generation.get()) return@confirmLater
      if (synchronized(tracked) { tracked.isNotEmpty() }) return@confirmLater
      if (wifiPresent()) return@confirmLater
      onDown()
    }
  }

  fun cancel() {
    generation.incrementAndGet()
  }
}

class WifiLanWatch(
  context: Context,
  private val onUp: () -> Unit,
  private val onDown: () -> Unit,
  private val confirmLater: (() -> Unit) -> Unit = { task ->
    Handler(Looper.getMainLooper()).postDelayed(task, WifiLossConfirmMs)
  }
) {
  private val appContext = context.applicationContext
  private var manager: ConnectivityManager? = null
  private var registered = false
  private val gate = WifiLossGate(
    onUp = onUp,
    onDown = onDown,
    wifiPresent = { val connectivity = manager; connectivity != null && wifiPresent(connectivity) },
    confirmLater = confirmLater
  )
  private val callback = object : ConnectivityManager.NetworkCallback() {
    override fun onAvailable(network: Network) {
      gate.onAvailable(network)
    }

    override fun onLost(network: Network) {
      gate.onLost(network)
    }
  }

  fun start() {
    if (registered) return
    val connectivity = appContext.getSystemService(ConnectivityManager::class.java) ?: return
    manager = connectivity
    // A desk LAN often has no upstream and is not the validated default route.
    val request = NetworkRequest.Builder()
      .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
      .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
      .removeCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
      .build()
    try {
      connectivity.registerNetworkCallback(request, callback)
      registered = true
    } catch (error: Exception) {
      // A missing permission must not crash startup, or leave the link waiting forever.
      onUp()
      return
    }
    if (wifiPresent(connectivity)) onUp() else gate.confirmAbsent()
  }

  fun stop() {
    gate.cancel()
    if (!registered) return
    val connectivity = manager
    registered = false
    if (connectivity == null) return
    try {
      connectivity.unregisterNetworkCallback(callback)
    } catch (error: Exception) {
      // Already unregistered, or the process is closing.
    }
  }

  /** Any Wi-Fi network, including one Android will not use as the default because it has no internet. */
  private fun wifiPresent(connectivity: ConnectivityManager): Boolean {
    val networks = try {
      connectivity.allNetworks
    } catch (error: Exception) {
      return false
    }
    for (network in networks) {
      val caps = try {
        connectivity.getNetworkCapabilities(network)
      } catch (error: Exception) {
        null
      } ?: continue
      // TRANSPORT_WIFI is enough. Do not require INTERNET or NET_CAPABILITY_VALIDATED.
      if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return true
    }
    return false
  }
}
