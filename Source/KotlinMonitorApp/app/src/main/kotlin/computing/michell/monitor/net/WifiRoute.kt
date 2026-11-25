package computing.michell.monitor.net

/* Wi-Fi bind sampled at each socket, not cached from a callback (c) 2026 Michell Computing.

   A desk LAN often has no upstream internet and is not the validated default
   route. A VPN is not the bind. The factory asks again for every socket so a
   roam is seen on the next request instead of waiting for a callback. */

import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.Socket
import javax.net.SocketFactory

data class RouteFacts(
  val wifi: Boolean,
  val vpn: Boolean
)

/** The Wi-Fi network to bind, or -1 when only VPN or non-Wi-Fi routes exist. */
fun selectWifiIndex(networks: List<RouteFacts>): Int {
  return networks.indexOfFirst { it.wifi && !it.vpn }
}

/** Binds one newly created socket. A no-op bind leaves the process default route. */
fun interface WifiSample {
  fun bind(socket: Socket)
}

/**
 * Reads ConnectivityManager on every bind. There is no remembered Network:
 * a callback is not the source of the route.
 */
class WifiRoute(private val connectivity: ConnectivityManager) : WifiSample {
  override fun bind(socket: Socket) {
    val network = sample() ?: return
    network.bindSocket(socket)
  }

  /** The Wi-Fi network visible now, or null. allNetworks is the snapshot; a callback would cache it. */
  @Suppress("DEPRECATION")
  fun sample(): Network? {
    val networks = try {
      connectivity.allNetworks
    } catch (error: Exception) {
      return null
    }
    val facts = ArrayList<RouteFacts>(networks.size)
    for (network in networks) {
      val caps = try {
        connectivity.getNetworkCapabilities(network)
      } catch (error: Exception) {
        null
      }
      facts.add(
        RouteFacts(
          wifi = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true,
          vpn = caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
        )
      )
    }
    val index = selectWifiIndex(facts)
    if (index < 0) return null
    return networks[index]
  }
}

/**
 * The one socket factory shared by the pulse, read and command clients.
 * createSocket asks the sample again. It does not keep the previous Network.
 */
class WifiSocketFactory(private val sample: WifiSample) : SocketFactory() {
  override fun createSocket(): Socket = open()

  override fun createSocket(host: String, port: Int): Socket {
    val socket = open()
    socket.connect(InetSocketAddress(host, port))
    return socket
  }

  override fun createSocket(host: String, port: Int, local: InetAddress, localPort: Int): Socket {
    val socket = open()
    socket.bind(InetSocketAddress(local, localPort))
    socket.connect(InetSocketAddress(host, port))
    return socket
  }

  override fun createSocket(host: InetAddress, port: Int): Socket {
    val socket = open()
    socket.connect(InetSocketAddress(host, port))
    return socket
  }

  override fun createSocket(host: InetAddress, port: Int, local: InetAddress, localPort: Int): Socket {
    val socket = open()
    socket.bind(InetSocketAddress(local, localPort))
    socket.connect(InetSocketAddress(host, port))
    return socket
  }

  private fun open(): Socket {
    val socket = Socket(Proxy.NO_PROXY)
    sample.bind(socket)
    return socket
  }
}
