package computing.michell.monitor.net

/* Three HTTPS lanes for the monitor phone (c) 2026 Michell Computing.

   Pulse, reads and commands each have their own dispatcher. They share one
   pinning trust manager and one Wi-Fi socket factory. Images are another
   lane from openLane, not one of these three. The desktop speaks HTTPS/1.1
   only. A malformed pin is refused in the application interceptor, before
   OkHttp opens a socket. */

import android.annotation.SuppressLint
import java.net.InetAddress
import java.net.Proxy
import java.net.Socket
import java.security.SecureRandom
import javax.net.SocketFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.X509TrustManager
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Protocol

const val PulseReadTimeoutMs = 25_000L
const val ReadTimeoutMs = 30_000L
const val CommandTimeoutMs = 15_000L
const val ConnectTimeoutMs = 10_000L

class MonitorHttp(
  private val pins: PinSource,
  val sockets: SocketFactory
) {
  internal val armed = ArmedPins()
  val trust: X509TrustManager = EndpointTrust(armed)
  val ssl: SSLSocketFactory = PinningSslSocketFactory(pins, trust, armed)
  val pulse: OkHttpClient = build(PulseReadTimeoutMs)
  val reads: OkHttpClient = build(ReadTimeoutMs)
  val commands: OkHttpClient = build(CommandTimeoutMs)

  /** A further lane. Item 6.5 uses this for images so a download cannot hold Stop. */
  fun openLane(readTimeoutMs: Long = ReadTimeoutMs): OkHttpClient = build(readTimeoutMs)

  @SuppressLint("BadHostnameVerifier")
  private fun build(readTimeoutMs: Long): OkHttpClient {
    return OkHttpClient.Builder()
      .dispatcher(okhttp3.Dispatcher())
      .socketFactory(sockets)
      .sslSocketFactory(ssl, trust)
      .hostnameVerifier { _, _ -> true }
      .proxy(Proxy.NO_PROXY)
      .protocols(listOf(Protocol.HTTP_1_1))
      .connectTimeout(ConnectTimeoutMs, java.util.concurrent.TimeUnit.MILLISECONDS)
      .readTimeout(readTimeoutMs, java.util.concurrent.TimeUnit.MILLISECONDS)
      .writeTimeout(CommandTimeoutMs, java.util.concurrent.TimeUnit.MILLISECONDS)
      .retryOnConnectionFailure(false)
      .addInterceptor(MalformedPinInterceptor(pins))
      .build()
  }
}

/** Runs before the connection. A bad pin never reaches the socket factory. */
internal class MalformedPinInterceptor(private val pins: PinSource) : Interceptor {
  override fun intercept(chain: Interceptor.Chain): okhttp3.Response {
    val url = chain.request().url
    refuseMalformedPin(pins.pinFor(url.host, url.port))
    return chain.proceed(chain.request())
  }
}

internal class PinningSslSocketFactory(
  private val pins: PinSource,
  trust: X509TrustManager,
  private val armed: ArmedPins
) : SSLSocketFactory() {
  private val delegate: SSLSocketFactory

  init {
    val context = SSLContext.getInstance("TLS")
    context.init(null, arrayOf(trust), SecureRandom())
    delegate = context.socketFactory
  }

  override fun getDefaultCipherSuites(): Array<String> = delegate.defaultCipherSuites

  override fun getSupportedCipherSuites(): Array<String> = delegate.supportedCipherSuites

  override fun createSocket(socket: Socket, host: String, port: Int, autoClose: Boolean): Socket {
    val pin = pins.pinFor(host, port)
    refuseMalformedPin(pin)
    val created = delegate.createSocket(socket, host, port, autoClose)
    armed.arm(created, socket, pin)
    if (created is SSLSocket) {
      val protocols = created.supportedProtocols.filter { it == "TLSv1.3" || it == "TLSv1.2" }
      if (protocols.isNotEmpty()) created.enabledProtocols = protocols.toTypedArray()
      val parameters = created.sslParameters
      parameters.endpointIdentificationAlgorithm = null
      created.sslParameters = parameters
    }
    return created
  }

  override fun createSocket(): Socket = delegate.createSocket()

  override fun createSocket(host: String, port: Int): Socket = delegate.createSocket(host, port)

  override fun createSocket(host: String, port: Int, local: InetAddress, localPort: Int): Socket =
    delegate.createSocket(host, port, local, localPort)

  override fun createSocket(host: InetAddress, port: Int): Socket = delegate.createSocket(host, port)

  override fun createSocket(host: InetAddress, port: Int, local: InetAddress, localPort: Int): Socket =
    delegate.createSocket(host, port, local, localPort)
}
