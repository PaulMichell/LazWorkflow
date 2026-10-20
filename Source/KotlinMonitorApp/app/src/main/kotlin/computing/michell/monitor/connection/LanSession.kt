package computing.michell.monitor.connection

/* TLS session for the monitor phone (c) 2026 Michell Computing.

   The socket is javax.net.ssl.SSLSocket. There is no cleartext open and no
   HTTP client. Reads and writes run on Dispatchers.IO. An empty fingerprint
   trusts the server certificate so the phone can connect by endpoint only.
   A supplied pin is still checked. The unsent prompt draft is kept across
   disconnect. */

import computing.michell.monitor.protocol.FrameStatus
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.MonitorLimits
import computing.michell.monitor.protocol.authMac
import computing.michell.monitor.protocol.decodeBye
import computing.michell.monitor.protocol.decodeHelloOk
import computing.michell.monitor.protocol.decodePairOk
import computing.michell.monitor.protocol.decodeTicks
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
import kotlinx.coroutines.CancellationException
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
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

const val HostClosedBanner = "Host closed"
const val ConnectionRefusedBanner = "Connection refused."
const val ReconnectingBanner = "Reconnecting"
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

class TrustAllManager : X509TrustManager {
  override fun checkClientTrusted(chain: Array<X509Certificate>?, authType: String?) {
    throw CertificateException("Client certificates are not used.")
  }

  override fun checkServerTrusted(chain: Array<X509Certificate>?, authType: String?) {
    if (chain.isNullOrEmpty()) throw CertificateException("No server certificate.")
  }

  override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
}

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
    val manager: X509TrustManager = if (normalizeFingerprint(fingerprint).length == 64) {
      PinnedTrustManager(fingerprint)
    } else {
      TrustAllManager()
    }
    context.init(null, arrayOf(manager), SecureRandom())
    val socket = context.socketFactory.createSocket() as SSLSocket
    try {
      socket.connect(InetSocketAddress(address, port), ConnectTimeoutMs)
      val protocols = socket.supportedProtocols.filter { it == "TLSv1.3" || it == "TLSv1.2" }
      if (protocols.isNotEmpty()) socket.enabledProtocols = protocols.toTypedArray()
      val parameters = socket.sslParameters
      parameters.endpointIdentificationAlgorithm = null
      socket.sslParameters = parameters
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
  Failed,
  Superseded
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
  private val linkEpoch = AtomicInteger(0)
  private val policy = ReconnectPolicy()
  private val session = computing.michell.monitor.protocol.SessionState()
  private val statusState = MutableStateFlow(LinkStatus())
  private val inbound = MutableSharedFlow<computing.michell.monitor.protocol.MonitorMessage>(replay = 32)
  private var loop: Job? = null
  private var link: TlsLink? = null
  private var pairCode = ""
  private var stopped = false

  val status: StateFlow<LinkStatus> = statusState.asStateFlow()
  val messages: SharedFlow<computing.michell.monitor.protocol.MonitorMessage> = inbound.asSharedFlow()
  val reconnectPaused: Boolean
    get() = policy.paused

  @Volatile
  var promptDraft: String = ""
    private set

  fun sendCatalogue(json: String) {
    if (json.isEmpty() || stopped) return
    scope.launch { writeJson(json) }
  }

  fun nextCommandId(): String = newId()

  fun updateDraft(text: String) {
    promptDraft = text
  }

  fun connect(address: String, port: Int, fingerprint: String = "", code: String = "") {
    val current = store.load()
    val trimmed = address.trim()
    val changed = current.address != trimmed || current.port != port
    val next = if (changed) {
      current.copy(address = trimmed, port = port, fingerprint = fingerprint, clientId = "", sessionToken = "")
    } else {
      current.copy(address = trimmed, port = port, fingerprint = fingerprint)
    }
    store.save(next)
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
    linkEpoch.incrementAndGet()
    loop?.cancel()
    closeLink()
    publish(LinkPhase.Disconnected, HostClosedBanner, "")
  }

  fun close() {
    disconnect()
    job.cancel()
  }

  private fun startLoop() {
    // The previous loop must finish closing its own socket before this one opens.
    val epoch = linkEpoch.incrementAndGet()
    val previous = loop
    previous?.cancel()
    closeLink()
    loop = scope.launch {
      try {
        previous?.join()
      } catch (error: CancellationException) {
        throw error
      } catch (error: Exception) {
        // The predecessor failed. This generation still owns the next attempt.
      }
      if (linkEpoch.get() != epoch || stopped) return@launch
      runLoop()
    }
  }

  private suspend fun runLoop() {
    val epoch = linkEpoch.get()
    var waitBeforeConnect = false
    while (coroutineContext[Job]?.isActive != false && !stopped && linkEpoch.get() == epoch) {
      if (policy.paused) {
        val shown = statusState.value.banner.ifEmpty { HostClosedBanner }
        publish(LinkPhase.Paused, shown, statusState.value.lastError)
        resumes.receive()
        if (stopped) return
        waitBeforeConnect = false
      }
      if (waitBeforeConnect) delay(policy.nextDelayMs())
      if (stopped) return
      waitBeforeConnect = true
      when (attempt(epoch)) {
        AttemptResult.Pinned -> return
        AttemptResult.Superseded -> return
        AttemptResult.Refused -> policy.pause()
        AttemptResult.Failed -> publishCurrent(epoch, LinkPhase.Disconnected, HostClosedBanner, statusState.value.lastError)
        AttemptResult.Opened -> {
          policy.resume()
          val end = readUntilClose(epoch)
          if (linkEpoch.get() != epoch) return
          closeLink()
          session.onSocketClosed()
          if (linkEpoch.get() != epoch) return
          if (end == ReadEnd.Disabled || end == ReadEnd.Rejected) {
            policy.pause()
            val shown = statusState.value.banner.ifEmpty { HostClosedBanner }
            publishCurrent(epoch, LinkPhase.Disconnected, shown, statusState.value.lastError)
          } else {
            publishCurrent(epoch, LinkPhase.Disconnected, ReconnectingBanner, statusState.value.lastError)
          }
        }
      }
    }
  }

  private suspend fun attempt(epoch: Int): AttemptResult {
    val record = store.load()
    val pinned = normalizeFingerprint(record.fingerprint)
    if (pinned.isNotEmpty() && pinned.length != 64) {
      publish(LinkPhase.Disconnected, "TLS pin mismatch.", "The fingerprint is not 64 hex characters.")
      return AttemptResult.Pinned
    }
    if (linkEpoch.get() != epoch) return AttemptResult.Superseded
    publishCurrent(epoch, LinkPhase.Connecting, "", "")
    val opened = try {
      withContext(Dispatchers.IO) {
        connector.open(record.address, record.port, record.fingerprint)
      }
    } catch (error: Exception) {
      if (linkEpoch.get() != epoch) return AttemptResult.Superseded
      if (isPinFailure(error)) {
        publish(LinkPhase.Disconnected, "TLS pin mismatch.", error.message ?: "TLS pin mismatch.")
        return AttemptResult.Pinned
      }
      if (isRefused(error)) {
        publish(LinkPhase.Paused, ConnectionRefusedBanner, error.message ?: ConnectionRefusedBanner)
        return AttemptResult.Refused
      }
      val detail = error.message ?: "Connection failed."
      publish(LinkPhase.Disconnected, detail, detail)
      return AttemptResult.Failed
    }
    if (linkEpoch.get() != epoch || stopped) {
      closeOwned(opened)
      return AttemptResult.Superseded
    }
    link = opened
    session.onHandshakeComplete()
    val helloId = newId()
    val openPair = !record.paired
    val hello = if (openPair) {
      encodeHello(helloId, ClientName, ClientVersion, "")
    } else {
      encodeHello(helloId, ClientName, ClientVersion, record.clientId)
    }
    if (!writeJson(hello, opened)) {
      if (linkEpoch.get() == epoch) closeLink() else closeOwned(opened)
      return if (linkEpoch.get() == epoch) AttemptResult.Failed else AttemptResult.Superseded
    }
    if (openPair) {
      val pair = encodePair(newId(), pairCode, pinned)
      if (!writeJson(pair, opened)) {
        if (linkEpoch.get() == epoch) closeLink() else closeOwned(opened)
        return if (linkEpoch.get() == epoch) AttemptResult.Failed else AttemptResult.Superseded
      }
    }
    return AttemptResult.Opened
  }

  private suspend fun readUntilClose(epoch: Int): ReadEnd {
    val current = link ?: return ReadEnd.Closed
    if (linkEpoch.get() != epoch) return ReadEnd.Closed
    readEnd = ReadEnd.Closed
    return withContext(Dispatchers.IO) {
      val buffer = ByteArray(8192)
      var pending = ByteArray(0)
      var partialSince = 0L
      var lastSent = System.currentTimeMillis()
      while (coroutineContext[Job]?.isActive != false && !stopped && linkEpoch.get() == epoch) {
        val count = try {
          current.input.read(buffer)
        } catch (error: SocketTimeoutException) {
          0
        } catch (error: Exception) {
          val detail = error.message ?: "Read failed."
          publishCurrent(epoch, LinkPhase.Disconnected, detail, detail)
          return@withContext ReadEnd.Closed
        }
        if (count < 0) return@withContext ReadEnd.Closed
        if (count > 0) {
          pending = pending + buffer.copyOf(count)
          if (partialSince == 0L) partialSince = System.currentTimeMillis()
          val consumed = consume(pending, epoch, current)
          if (consumed == null) return@withContext ReadEnd.Closed
          pending = consumed
        }
        val now = System.currentTimeMillis()
        if (pending.isEmpty()) partialSince = 0L
        if (pending.isNotEmpty() && now - partialSince >= MonitorLimits.PartialFrameMs) {
          return@withContext ReadEnd.Closed
        }
        if (now - lastSent >= MonitorLimits.HeartbeatSilenceMs) {
          val ping = encodeTicks(MessageKind.Ping, newId(), now)
          if (!writeJson(ping, current)) return@withContext ReadEnd.Closed
          lastSent = now
        }
        if (linkEpoch.get() != epoch) return@withContext ReadEnd.Closed
        if (readEnd != ReadEnd.Closed) return@withContext readEnd
      }
      ReadEnd.Closed
    }
  }

  private var readEnd = ReadEnd.Closed

  private suspend fun consume(start: ByteArray, epoch: Int, owned: TlsLink): ByteArray? {
    var pending = start
    while (true) {
      val step = tryConsumeFrame(pending)
      when (step.status) {
        FrameStatus.Ok -> {
          onFrame(step.frame.json, epoch, owned)
          pending = step.remaining
          if (readEnd != ReadEnd.Closed) return pending
        }
        FrameStatus.NeedMore -> return pending
        else -> return null
      }
    }
  }

  private suspend fun onFrame(json: String, epoch: Int, owned: TlsLink) {
    if (linkEpoch.get() != epoch) return
    val envelope = tryDecodeEnvelope(json)
    if (!envelope.ok) return
    val message = envelope.message
    session.apply(message)
    inbound.tryEmit(message)
    when (message.kind) {
      MessageKind.PairOk -> {
        val paired = decodePairOk(message.payloadJson)
        if (paired != null) {
          store.savePairing(paired.clientId, paired.sessionToken)
          pairCode = ""
          writeJson(encodeEmpty(MessageKind.Refresh, newId()), owned)
        }
      }
      MessageKind.HelloOk -> {
        val hello = decodeHelloOk(message.payloadJson)
        val record = store.load()
        if (hello != null && record.paired) {
          val mac = authMac(record.sessionToken, hello.nonce)
          session.noteOutbound(MessageKind.Auth)
          if (mac.isNotEmpty()) writeJson(encodeAuth(newId(), record.clientId, mac), owned)
          writeJson(encodeEmpty(MessageKind.Refresh, newId()), owned)
        }
      }
      MessageKind.Ping -> {
        val ticks = decodeTicks(message.payloadJson)?.ticks ?: 0L
        if (!writeJson(encodeTicks(MessageKind.Pong, newId(), ticks), owned)) noteReadEnd(epoch, ReadEnd.Closed)
      }
      MessageKind.Bye -> {
        val bye = decodeBye(message.payloadJson)
        if (bye?.reason == "disabled" || bye?.reason == "revoked") {
          noteReadEnd(epoch, ReadEnd.Disabled)
          publishCurrent(epoch, LinkPhase.Paused, HostClosedBanner, bye.reason)
        }
      }
      MessageKind.Rejected -> {
        pairCode = ""
        val reason = message.reason
        val retryOpen = (reason == "auth" || reason == "revoked") && store.load().paired
        if (reason == "busy" || retryOpen) {
          if (retryOpen) {
            val current = store.load()
            store.save(current.copy(clientId = "", sessionToken = ""))
          }
          noteReadEnd(epoch, ReadEnd.Closed)
          publishCurrent(epoch, LinkPhase.Connecting, ReconnectingBanner, reason)
        } else {
          noteReadEnd(epoch, ReadEnd.Rejected)
          publishCurrent(epoch, LinkPhase.Paused, reason.ifEmpty { HostClosedBanner }, reason)
        }
      }
      else -> publishCurrent(epoch, if (session.phase == computing.michell.monitor.protocol.SessionPhase.Live ||
        session.phase == computing.michell.monitor.protocol.SessionPhase.Busy) LinkPhase.Live else LinkPhase.Connecting, "", "")
    }
  }

  private suspend fun writeJson(json: String, owned: TlsLink? = link): Boolean {
    val frame = tryEncodeFrame(json)
    if (!frame.ok) return false
    val target = owned ?: return false
    return writeLock.withLock {
      withContext(Dispatchers.IO) {
        try {
          target.output.write(frame.bytes)
          target.output.flush()
          true
        } catch (error: Exception) {
          false
        }
      }
    }
  }

  private fun noteReadEnd(epoch: Int, end: ReadEnd) {
    if (linkEpoch.get() == epoch) readEnd = end
  }

  private fun publishCurrent(epoch: Int, phase: LinkPhase, banner: String, error: String) {
    if (linkEpoch.get() != epoch) return
    publish(phase, banner, error)
  }

  private fun publish(phase: LinkPhase, banner: String, error: String) {
    statusState.update { current ->
      current.copy(phase = phase, banner = banner, draft = promptDraft, lastError = if (error.isEmpty()) current.lastError else error)
    }
  }

  private fun closeLink() {
    closeOwned(link)
    link = null
  }

  private fun closeOwned(owned: TlsLink?) {
    if (owned == null) return
    if (link === owned) link = null
    try {
      owned.close()
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
