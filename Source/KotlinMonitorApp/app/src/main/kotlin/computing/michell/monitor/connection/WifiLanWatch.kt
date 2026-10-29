package computing.michell.monitor.connection

/* Wi-Fi callback for the monitor link (c) 2026 Michell Computing.

   Registers ConnectivityManager.NetworkCallback for TRANSPORT_WIFI.
   A desk LAN may have no upstream internet, so that capability is not
   required. The session reconnects when this callback reports Wi-Fi. */

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest

class WifiLanWatch(
  context: Context,
  private val onUp: () -> Unit,
  private val onDown: () -> Unit
) {
  private val appContext = context.applicationContext
  private val networks = mutableSetOf<Network>()
  private val callback = object : ConnectivityManager.NetworkCallback() {
    override fun onAvailable(network: Network) {
      synchronized(networks) { networks.add(network) }
      onUp()
    }

    override fun onLost(network: Network) {
      val empty = synchronized(networks) {
        networks.remove(network)
        networks.isEmpty()
      }
      if (empty) onDown()
    }
  }
  private var manager: ConnectivityManager? = null
  private var registered = false

  fun start() {
    if (registered) return
    val connectivity = appContext.getSystemService(ConnectivityManager::class.java) ?: return
    manager = connectivity
    // Down until a Wi-Fi network is known. The callback also reports one that already exists.
    onDown()
    if (activeWifi(connectivity)) onUp()
    val request = NetworkRequest.Builder()
      .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
      .build()
    try {
      connectivity.registerNetworkCallback(request, callback)
      registered = true
    } catch (error: Exception) {
      // A missing permission must not crash startup, or leave the link waiting forever.
      onUp()
    }
  }

  fun stop() {
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

  private fun activeWifi(connectivity: ConnectivityManager): Boolean {
    val network = try {
      connectivity.activeNetwork
    } catch (error: Exception) {
      return false
    } ?: return false
    val caps = try {
      connectivity.getNetworkCapabilities(network)
    } catch (error: Exception) {
      null
    }
    return caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
  }
}
