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
      synchronized(networks) { networks.remove(network) }
      val connectivity = manager
      if (connectivity != null && wifiPresent(connectivity)) return
      if (synchronized(networks) { networks.isEmpty() }) onDown()
    }
  }
  private var manager: ConnectivityManager? = null
  private var registered = false

  fun start() {
    if (registered) return
    val connectivity = appContext.getSystemService(ConnectivityManager::class.java) ?: return
    manager = connectivity
    // A desk LAN often has no upstream. Do not wait for Android to mark it as the default route.
    if (wifiPresent(connectivity)) onUp() else onDown()
    val request = NetworkRequest.Builder()
      .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
      .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
      .build()
    try {
      connectivity.registerNetworkCallback(request, callback)
      registered = true
      if (wifiPresent(connectivity)) onUp()
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
      if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return true
    }
    return false
  }
}
