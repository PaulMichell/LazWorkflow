package computing.michell.monitor.connection

/* Wi-Fi callback for the monitor link (c) 2026 Michell Computing.

   Registers ConnectivityManager.NetworkCallback for TRANSPORT_WIFI.
   A desk LAN may have no upstream internet and no validated default route,
   so neither is required. The callback reports a network identity, not a
   Boolean: a roam replaces that identity, and a stale loss of another
   network is not a loss. A VPN is not a LAN route. stop and restart clear
   the tracked set so a late callback cannot apply to the next registration. */

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/** How long a roam is allowed to look like a loss before the second sample. */
const val WifiLossConfirmMs = 500L

/** One observed Wi-Fi network. Equality is the identity, not a Boolean up/down. */
data class LanRoute(val identity: String)

/**
 * Facts used to choose a LAN route. Internet is recorded so a test can show it
 * is not the selection rule. A VPN transport is never the LAN route.
 */
data class RouteFacts(
  val identity: String,
  val wifi: Boolean,
  val vpn: Boolean,
  val internet: Boolean
)

/** The Wi-Fi network to bind, or null when only VPN or non-Wi-Fi routes exist. */
fun selectLanRoute(networks: List<RouteFacts>): LanRoute? {
  val wifi = networks.firstOrNull { it.wifi && !it.vpn } ?: return null
  return LanRoute(wifi.identity)
}

/** Binds an outbound socket to the selected Wi-Fi network. Null means no bind. */
fun interface LanSocketBinder {
  fun bind(socket: Socket, route: LanRoute?)

  companion object {
    val None: LanSocketBinder = LanSocketBinder { _, _ -> }
  }
}

/**
 * Identities the watch has seen, and the bind action for each. stop clears it
 * so a restarted watch cannot bind a socket to a network from the previous registration.
 */
class LanRouteBook : LanSocketBinder {
  private val binds = ConcurrentHashMap<String, (Socket) -> Unit>()

  fun remember(identity: String, bind: (Socket) -> Unit) {
    binds[identity] = bind
  }

  fun forget(identity: String) {
    binds.remove(identity)
  }

  fun clear() {
    binds.clear()
  }

  fun knows(identity: String): Boolean = binds.containsKey(identity)

  override fun bind(socket: Socket, route: LanRoute?) {
    if (route == null) return
    val action = binds[route.identity] ?: throw java.io.IOException("The Wi-Fi network is no longer available.")
    action(socket)
  }
}

/**
 * The callback's tracked set is the first sample. allNetworks is the second.
 * onDown runs only when both say this identity is gone. A loss of a different
 * identity is ignored. Internet capability is irrelevant.
 */
internal class WifiLossGate(
  private val onUp: (Any) -> Unit,
  private val onDown: (Any) -> Unit,
  private val onAbsent: () -> Unit,
  private val wifiPresent: () -> Boolean,
  private val confirmLater: (() -> Unit) -> Unit
) {
  private val tracked = HashSet<Any>()
  private val generation = AtomicInteger(0)
  private var active = false

  fun activate() {
    synchronized(tracked) { tracked.clear() }
    generation.incrementAndGet()
    active = true
  }

  fun deactivate() {
    active = false
    generation.incrementAndGet()
    synchronized(tracked) { tracked.clear() }
  }

  fun onAvailable(network: Any) {
    if (!active) return
    synchronized(tracked) { tracked.add(network) }
    generation.incrementAndGet()
    onUp(network)
  }

  fun onLost(network: Any) {
    if (!active) return
    val removed = synchronized(tracked) { tracked.remove(network) }
    val empty = synchronized(tracked) { tracked.isEmpty() }
    // A loss of some other network while one remains is not a loss.
    if (!removed && !empty) return
    // Another network, or allNetworks still listing Wi-Fi, is not a loss.
    if (!empty || wifiPresent()) {
      generation.incrementAndGet()
      return
    }
    confirmAbsent(network)
  }

  /** First sample saw no Wi-Fi. The banner waits for the second sample. */
  fun confirmAbsent(lost: Any? = null) {
    if (!active) return
    val stamp = generation.incrementAndGet()
    confirmLater {
      if (!active || stamp != generation.get()) return@confirmLater
      if (synchronized(tracked) { tracked.isNotEmpty() }) return@confirmLater
      if (wifiPresent()) return@confirmLater
      if (lost == null) onAbsent() else onDown(lost)
    }
  }
}

class WifiLanWatch(
  context: Context,
  private val routes: LanRouteBook,
  private val onRoute: (LanRoute) -> Unit,
  private val onRouteLost: (LanRoute) -> Unit,
  private val onAbsent: () -> Unit = {},
  private val onUnbound: () -> Unit = {},
  private val confirmLater: (() -> Unit) -> Unit = { task ->
    Handler(Looper.getMainLooper()).postDelayed(task, WifiLossConfirmMs)
  }
) {
  private val appContext = context.applicationContext
  private var manager: ConnectivityManager? = null
  private var registered = false
  private val gate = WifiLossGate(
    onUp = { network -> if (network is LanRoute) onRoute(network) },
    onDown = { network -> if (network is LanRoute) onRouteLost(network) },
    onAbsent = onAbsent,
    wifiPresent = { val connectivity = manager; connectivity != null && wifiPresent(connectivity) },
    confirmLater = confirmLater
  )
  private val callback = object : ConnectivityManager.NetworkCallback() {
    override fun onAvailable(network: Network) {
      note(network)
    }

    override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
      note(network, caps)
    }

    override fun onLost(network: Network) {
      val identity = identityOf(network)
      routes.forget(identity)
      gate.onLost(LanRoute(identity))
    }
  }

  fun start() {
    stop()
    val connectivity = appContext.getSystemService(ConnectivityManager::class.java) ?: return
    manager = connectivity
    gate.activate()
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
      gate.deactivate()
      onUnbound()
      return
    }
    val current = currentWifiRoute(connectivity)
    if (current != null) onRoute(current) else gate.confirmAbsent()
  }

  fun stop() {
    gate.deactivate()
    routes.clear()
    if (!registered) return
    val connectivity = manager
    registered = false
    manager = null
    if (connectivity == null) return
    try {
      connectivity.unregisterNetworkCallback(callback)
    } catch (error: Exception) {
      // Already unregistered, or the process is closing.
    }
  }

  private fun note(network: Network, caps: NetworkCapabilities? = null) {
    val facts = factsOf(network, caps) ?: return
    val selected = selectLanRoute(listOf(facts)) ?: return
    routes.remember(selected.identity) { socket -> network.bindSocket(socket) }
    gate.onAvailable(selected)
  }

  private fun factsOf(network: Network, known: NetworkCapabilities? = null): RouteFacts? {
    val connectivity = manager ?: return null
    val caps = known ?: try {
      connectivity.getNetworkCapabilities(network)
    } catch (error: Exception) {
      null
    } ?: return null
    return RouteFacts(
      identityOf(network),
      caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
      caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN),
      caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    )
  }

  private fun identityOf(network: Network): String = network.networkHandle.toString()

  /** Any Wi-Fi network, including one Android will not use as the default because it has no internet. */
  private fun wifiPresent(connectivity: ConnectivityManager): Boolean = currentWifiRoute(connectivity) != null

  private fun currentWifiRoute(connectivity: ConnectivityManager): LanRoute? {
    val networks = try {
      connectivity.allNetworks
    } catch (error: Exception) {
      return null
    }
    val facts = ArrayList<RouteFacts>()
    for (network in networks) {
      val one = factsOf(network) ?: continue
      if (one.wifi && !one.vpn) routes.remember(one.identity) { socket -> network.bindSocket(socket) }
      facts.add(one)
    }
    return selectLanRoute(facts)
  }
}
