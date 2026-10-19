package computing.michell.monitor.connection

/* TLS session for the monitor phone (c) 2026 Michell Computing.

   The socket is javax.net.ssl.SSLSocket. There is no cleartext open and no
   HTTP client. Reads and writes run on Dispatchers.IO. A pin mismatch closes
   the handshake and does not clear the stored pairing. The unsent prompt
   draft is kept across disconnect. */

import computing.michell.monitor.protocol.FrameStatus
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.MonitorLimits
import computing.michell.monitor.protocol.authMac
import computing.michell.monitor.protocol.decodeBye
import computing.michell.monitor.protocol.decodeHelloOk
import computing.michell.monitor.protocol.decodePairOk
import computing.michell.monitor.protocol.encodeAuth
import computing.michell.monitor.protocol.encodeEmpty
import computing.michell.monitor.protocol.encodeHello
import computing.michell.monitor.protocol.encodePair
import computing.michell.monitor.protocol.encodeTicks
import computing.michell.monitor.protocol.tryConsumeFrame
import computing.michell.monitor.protocol.tryDecodeEnvelope
import computing.michell.monitor.protocol.tryEncodeFrame
import java.io.Closeable
import kotlin.coroutines.coroutineContext
import java.io.InputStream
import java.io.OutputStream
import java.net.ConnectException
import java.net.InetSocketAddress
import java.net.SocketTimeoutException
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.atomic.AtomicInteger
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509TrustManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

const val HostClosedBanner = "Host closed"
const val ClientName = "Phone"
const val ClientVersion = "1"

enum class LinkPhase {
  Idle,
  Connecting,
  Live,
  Disconnected,
  Paused
}

data class LinkStatus(
  val phase: LinkPhase = LinkPhase.Idle,
  val banner: String = "",
  val draft: String = "",
  val lastError: String = ""
)

class ReconnectPolicy {
  private var index = 0
  var paused: Boolean = false
    private set

  fun nextDelayMs(): Long {
    val delay = Delays[index.coerceAtMost(Delays.lastIndex)]
    if (index < Delays.lastIndex) index += 1
    return delay
  }

  fun pause() {
    paused = true
  }

  fun resume() {
    paused = false
    index = 0
  }

  companion object {
    val Delays = longArrayOf(1_000L, 2_000L, 4_000L, 8_000L, 30_000L)
  }
}

fun normalizeFingerprint(text: String): String {
  return text.lowercase().filter { it in '0'..'9' || it in 'a'..'f' }
}

fun fingerprintsEqual(left: String, right: String): Boolean {
  val actual = normalizeFingerprint(left)
  val pinned = normalizeFingerprint(right)
  return actual.length == 64 && actual == pinned
}

fun sha256Hex(bytes: ByteArray): String {
  val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
  val out = StringBuilder(digest.size * 2)
  for (byte in digest) {
    val value = byte.toInt() and 0xFF
    out.append(HexDigits[value shr 4])
    out.append(HexDigits[value and 0x0F])
  }
  return out.toString()
}

class PinMismatchException(val presented: String) : CertificateException("TLS pin mismatch.")

class PinnedTrustManager(private val pinnedFingerprint: String) : X509TrustManager {
  override fun checkClientTrusted(chain: Array<X509Certificate>?, authType: String?) {
    throw CertificateException("Client certificates are not used.")
  }

  override fun checkServerTrusted(chain: Array<X509Certificate>?, authType: String?) {
    val leaf = chain?.firstOrNull() ?: throw CertificateException("No server certificate.")
    val presented = sha256Hex(leaf.encoded)
    if (!fingerprintsEqual(presented, pinnedFingerprint)) throw PinMismatchException(presented)
  }

  override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
}

interface TlsLink : Closeable {
  val input: InputStream
  val output: OutputStream
}

fun interface TlsConnector {
  fun open(address: String, port: Int, fingerprint: String): TlsLink
}

class SslSocketConnector : TlsConnector {
  override fun open(address: String, port: Int, fingerprint: String): TlsLink {
    val context = SSLContext.getInstance("TLS")
    context.init(null, arrayOf(PinnedTrustManager(fingerprint)), SecureRandom())
    val socket = context.socketFactory.createSocket() as SSLSocket
    try {
      socket.connect(InetSocketAddress(address, port), ConnectTimeoutMs)
      val protocols = socket.supportedProtocols.filter { it == "TLSv1.3" || it == "TLSv1.2" }
      if (protocols.isNotEmpty()) socket.enabledProtocols = protocols.toTypedArray()
      socket.soTimeout = ReadTimeoutMs
      socket.startHandshake()
      return SocketLink(socket)
    } catch (error: Exception) {
      socket.close()
      throw error
    }
  }
}

private class SocketLink(private val socket: SSLSocket) : TlsLink {
  override val input: InputStream = socket.inputStream
  override val output: OutputStream = socket.outputStream
  override fun close() {
    socket.close()
  }
}

private enum class AttemptResult {
  Opened,
  Pinned,
  Refused,
  Failed
}

private enum class ReadEnd {
  Closed,
  Disabled,
  Rejected
}

class LanSession(
  private val store: HostStore,
  private val connector: TlsConnector = SslSocketConnector()
) {
  private val job = SupervisorJob()
  private val scope = CoroutineScope(job + Dispatchers.IO)
  private val writeLock = Mutex()
  private val resumes = Channel<Unit>(Channel.CONFLATED)
  private val ids = AtomicInteger(1)
  private val policy = ReconnectPolicy()
  private val session = computing.michell.monitor.protocol.SessionState()
  private val statusState = MutableStateFlow(LinkStatus())
  private var loop: Job? = null
  private var link: TlsLink? = null
  private var pairCode = ""
  private var stopped = false

  val status: StateFlow<LinkStatus> = statusState.asStateFlow()
  val reconnectPaused: Boolean
    get() = policy.paused

  @Volatile
  var promptDraft: String = ""
    private set

  fun updateDraft(text: String) {
    promptDraft = text
    statusState.update { it.copy(draft = text) }
  }

  fun connect(address: String, port: Int, fingerprint: String, code: String) {
    store.saveEndpoint(address, port, fingerprint)
    pairCode = code
    policy.resume()
    stopped = false
    startLoop()
  }

  /** User tapped Connect after a refused or disabled listener paused backoff. */
  fun resume() {
    policy.resume()
    resumes.trySend(Unit)
    if (loop?.isActive != true && !stopped) startLoop()
  }

  fun disconnect() {
    stopped = true
    policy.pause()
    loop?.cancel()
    closeLink()
    publish(LinkPhase.Disconnected, HostClosedBanner, "")
  }

  fun close() {
    disconnect()
    job.cancel()
  }

  private fun startLoop() {
    loop?.cancel()
    closeLink()
    loop = scope.launch { runLoop() }
  }

  private suspend fun runLoop() {
    var waitBeforeConnect = false
    while (coroutineContext[Job]?.isActive != false && !stopped) {
      if (policy.paused) {
        publish(LinkPhase.Paused, HostClosedBanner, statusState.value.lastError)
        resumes.receive()
        if (stopped) return
        waitBeforeConnect = false
      }
      if (waitBeforeConnect) delay(policy.nextDelayMs())
      if (stopped) return
      waitBeforeConnect = true
      when (attempt()) {
        AttemptResult.Pinned -> return
        AttemptResult.Refused -> policy.pause()
        AttemptResult.Failed -> publish(LinkPhase.Disconnected, HostClosedBanner, statusState.value.lastError)
        AttemptResult.Opened -> {
          policy.resume()
          val end = readUntilClose()
          closeLink()
          session.onSocketClosed()
          if (end == ReadEnd.Disabled || end == ReadEnd.Rejected) policy.pause()
          publish(LinkPhase.Disconnected, HostClosedBanner, statusState.value.lastError)
        }
      }
    }
  }

  private suspend fun attempt(): AttemptResult {
    val record = store.load()
    if (normalizeFingerprint(record.fingerprint).length != 64) {
      publish(LinkPhase.Disconnected, "TLS pin mismatch.", "The fingerprint is not 64 hex characters.")
      return AttemptResult.Pinned
    }
    publish(LinkPhase.Connecting, "", "")
    val opened = try {
      withContext(Dispatchers.IO) {
        connector.open(record.address, record.port, record.fingerprint)
      }
    } catch (error: Exception) {
      if (isPinFailure(error)) {
        publish(LinkPhase.Disconnected, "TLS pin mismatch.", error.message ?: "TLS pin mismatch.")
        return AttemptResult.Pinned
      }
      if (isRefused(error)) {
        publish(LinkPhase.Paused, HostClosedBanner, error.message ?: "Connection refused.")
        return AttemptResult.Refused
      }
      publish(LinkPhase.Disconnected, HostClosedBanner, error.message ?: "Connection failed.")
      return AttemptResult.Failed
    }
    link = opened
    session.onHandshakeComplete()
    val helloId = newId()
    val hello = if (pairCode.isNotEmpty() && !record.paired) {
      encodeHello(helloId, ClientName, ClientVersion, "")
    } else if (record.paired) {
      encodeHello(helloId, ClientName, ClientVersion, record.clientId)
    } else {
      closeLink()
      publish(LinkPhase.Disconnected, "Pairing code required.", "Enter the pairing code from the desktop.")
      return AttemptResult.Pinned
    }
    if (!writeJson(hello)) {
      closeLink()
      return AttemptResult.Failed
    }
    if (pairCode.isNotEmpty() && !record.paired) {
      val pair = encodePair(newId(), pairCode, normalizeFingerprint(record.fingerprint))
      if (!writeJson(pair)) {
        closeLink()
        return AttemptResult.Failed
      }
    }
    return AttemptResult.Opened
  }

  private suspend fun readUntilClose(): ReadEnd {
    val current = link ?: return ReadEnd.Closed
    readEnd = ReadEnd.Closed
    return withContext(Dispatchers.IO) {
      val buffer = ByteArray(8192)
      var pending = ByteArray(0)
      var partialSince = 0L
      var lastFrame = System.currentTimeMillis()
      while (coroutineContext[Job]?.isActive != false && !stopped) {
        val count = try {
          current.input.read(buffer)
        } catch (error: SocketTimeoutException) {
          0
        } catch (error: Exception) {
          return@withContext ReadEnd.Closed
        }
        if (count < 0) return@withContext ReadEnd.Closed
        if (count > 0) {
          pending = pending + buffer.copyOf(count)
          if (partialSince == 0L) partialSince = System.currentTimeMillis()
          lastFrame = System.currentTimeMillis()
          val consumed = consume(pending)
          if (consumed == null) return@withContext ReadEnd.Closed
          pending = consumed
        }
        val now = System.currentTimeMillis()
        if (pending.isEmpty()) partialSince = 0L
        if (pending.isNotEmpty() && now - partialSince >= MonitorLimits.PartialFrameMs) {
          return@withContext ReadEnd.Closed
        }
        if (now - lastFrame >= MonitorLimits.HeartbeatSilenceMs) {
          val ping = encodeTicks(MessageKind.Ping, newId(), now)
          if (!writeJson(ping)) return@withContext ReadEnd.Closed
          lastFrame = now
        }
        if (readEnd != ReadEnd.Closed) return@withContext readEnd
      }
      ReadEnd.Closed
    }
  }

  private var readEnd = ReadEnd.Closed

  private suspend fun consume(start: ByteArray): ByteArray? {
    var pending = start
    while (true) {
      val step = tryConsumeFrame(pending)
      when (step.status) {
        FrameStatus.Ok -> {
          onFrame(step.frame.json)
          pending = step.remaining
          if (readEnd != ReadEnd.Closed) return pending
        }
        FrameStatus.NeedMore -> return pending
        else -> return null
      }
    }
  }

  private suspend fun onFrame(json: String) {
    val envelope = tryDecodeEnvelope(json)
    if (!envelope.ok) return
    val message = envelope.message
    session.apply(message)
    when (message.kind) {
      MessageKind.PairOk -> {
        val paired = decodePairOk(message.payloadJson)
        if (paired != null) {
          store.savePairing(paired.clientId, paired.sessionToken)
          pairCode = ""
          writeJson(encodeEmpty(MessageKind.Refresh, newId()))
        }
      }
      MessageKind.HelloOk -> {
        val hello = decodeHelloOk(message.payloadJson)
        val record = store.load()
        if (hello != null && record.paired) {
          val mac = authMac(record.sessionToken, hello.nonce)
          session.noteOutbound(MessageKind.Auth)
          if (mac.isNotEmpty()) writeJson(encodeAuth(newId(), record.clientId, mac))
          writeJson(encodeEmpty(MessageKind.Refresh, newId()))
        }
      }
      MessageKind.Bye -> {
        val bye = decodeBye(message.payloadJson)
        if (bye?.reason == "disabled" || bye?.reason == "revoked") {
          readEnd = ReadEnd.Disabled
          publish(LinkPhase.Paused, HostClosedBanner, bye.reason)
        }
      }
      MessageKind.Rejected -> {
        pairCode = ""
        readEnd = ReadEnd.Rejected
        publish(LinkPhase.Paused, HostClosedBanner, message.reason)
      }
      else -> publish(if (session.phase == computing.michell.monitor.protocol.SessionPhase.Live ||
        session.phase == computing.michell.monitor.protocol.SessionPhase.Busy) LinkPhase.Live else LinkPhase.Connecting, "", "")
    }
  }

  private suspend fun writeJson(json: String): Boolean {
    val frame = tryEncodeFrame(json)
    if (!frame.ok) return false
    return writeLock.withLock {
      withContext(Dispatchers.IO) {
        val output = link?.output ?: return@withContext false
        try {
          output.write(frame.bytes)
          output.flush()
          true
        } catch (error: Exception) {
          false
        }
      }
    }
  }

  private fun publish(phase: LinkPhase, banner: String, error: String) {
    statusState.update { current ->
      current.copy(phase = phase, banner = banner, draft = promptDraft, lastError = if (error.isEmpty()) current.lastError else error)
    }
  }

  private fun closeLink() {
    val current = link
    link = null
    try {
      current?.close()
    } catch (error: Exception) {
      // The peer may already have closed the socket.
    }
  }

  private fun newId(): String {
    val id = "m" + ids.getAndIncrement().toString()
    return if (id.length <= 64) id else id.substring(0, 64)
  }
}

private fun isPinFailure(error: Throwable): Boolean {
  var current: Throwable? = error
  while (current != null) {
    if (current is PinMismatchException) return true
    current = current.cause
  }
  return false
}

private fun isRefused(error: Throwable): Boolean {
  var current: Throwable? = error
  while (current != null) {
    if (current is ConnectException) return true
    val message = current.message?.lowercase().orEmpty()
    if (message.contains("connection refused") || message.contains("econnrefused")) return true
    current = current.cause
  }
  return false
}

private const val ConnectTimeoutMs = 10_000
private const val ReadTimeoutMs = 1_000
private const val HexDigits = "0123456789abcdef"
