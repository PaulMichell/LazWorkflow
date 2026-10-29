package computing.michell.monitor.connection

/* TLS session for the monitor phone (c) 2026 Michell Computing.

   Size note: exceeds the 1000 line preference. The socket, pin rules, and
   reconnect loop are one session. Wi-Fi registration lives in WifiLanWatch.
   Reviewed 2026-10-29.

   The socket is javax.net.ssl.SSLSocket. There is no cleartext open and no
   HTTP client. The TCP socket is created with no proxy: the emulator SOCKS
   proxy never reaches the desktop listener. Reads and writes run on Dispatchers.IO. An empty fingerprint
   trusts the server certificate so the phone can connect by endpoint only.
   Connect keeps a saved pin. A nonempty pin that is not 64 hex characters
   is refused. Inbound messages wait on a bounded queue. A slow collector
   is a failed delivery, not a dropped frame. A silent, rejected, or
   failed-write peer leaves the read loop and the owned socket is closed.
   The unsent prompt draft is kept across disconnect. A catalogue command
   is written only on the socket that accepted it. Wi-Fi becoming available
   reconnects at once and resets the backoff. On a LAN the wait is 1, 2, 4,
   8 seconds, then capped at 10 seconds with equal jitter. The link is up
   only in the foreground: background sends bye and waits to resume.
   Connect still keeps a saved pin and does not clear it. */

import computing.michell.monitor.protocol.ChunkAssembly
import computing.michell.monitor.protocol.FrameAssembler
import computing.michell.monitor.protocol.FrameStatus
import computing.michell.monitor.protocol.InboundPayload
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.MonitorFrame
import computing.michell.monitor.protocol.MonitorLimits
import computing.michell.monitor.protocol.MonitorMessage
import computing.michell.monitor.protocol.authMac
import computing.michell.monitor.protocol.decodeBye
import computing.michell.monitor.protocol.decodeHelloOk
import computing.michell.monitor.protocol.decodePairOk
import computing.michell.monitor.protocol.decodeTicks
import computing.michell.monitor.protocol.encodeAuth
import computing.michell.monitor.protocol.encodeBye
import computing.michell.monitor.protocol.encodeEmpty
import computing.michell.monitor.protocol.encodeResume
import computing.michell.monitor.protocol.encodeHello
import computing.michell.monitor.protocol.encodePair
import computing.michell.monitor.protocol.encodeTicks
import computing.michell.monitor.protocol.tryDecodeEnvelope
import computing.michell.monitor.protocol.tryEncodeFrame
import java.io.Closeable
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import java.io.InputStream
import java.io.OutputStream
import java.net.ConnectException
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.Socket
import java.net.SocketTimeoutException
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.ThreadLocalRandom
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
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.selects.onTimeout as selectOnTimeout
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

const val HostClosedBanner = "Host closed"
const val ConnectionRefusedBanner = "Connection refused."
const val ReconnectingBanner = "Reconnecting"
const val BackgroundBanner = "In the background"
const val WaitingForWifiBanner = "Waiting for Wi-Fi"
const val ByeBackground = "background"
const val LanBackoffCapMs = 10_000L
const val DeliveryFailedDetail = "Delivery failed."
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

/**
 * Equal jitter in [base/2, base], never above the LAN cap.
 * roll may be any Int; only its residue in 0..999 is used. 999 returns the base.
 */
fun jitteredLanDelayMs(baseMs: Long, roll: Int, capMs: Long = LanBackoffCapMs): Long {
  val capped = baseMs.coerceIn(0L, capMs)
  if (capped <= 1L) return capped
  val half = capped / 2L
  val unit = roll.mod(1000)
  return half + (half * unit) / 999L
}

private val LanBackoffBases = longArrayOf(1_000L, 2_000L, 4_000L, 8_000L, LanBackoffCapMs)

class ReconnectPolicy(private val roll: () -> Int = { ThreadLocalRandom.current().nextInt(1000) }) {
  private var index = 0
  @Volatile
  var paused: Boolean = false
    private set

  fun nextDelayMs(): Long {
    val base = synchronized(this) {
      val current = index
      if (index < LanBackoffBases.lastIndex) index += 1
      LanBackoffBases[current.coerceAtMost(LanBackoffBases.lastIndex)]
    }
    return jitteredLanDelayMs(base, roll())
  }

  fun resetBackoff() {
    synchronized(this) { index = 0 }
  }

  fun pause() {
    paused = true
  }

  fun resume() {
    paused = false
    resetBackoff()
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

/** Empty selects endpoint-only trust. A 64-hex pin is pinned. Any other nonempty value is refused. */
internal fun trustManagerForFingerprint(fingerprint: String): X509TrustManager {
  val pinned = normalizeFingerprint(fingerprint)
  if (fingerprint.isNotEmpty() && pinned.length != 64) throw PinMismatchException(fingerprint)
  if (pinned.length == 64) return PinnedTrustManager(fingerprint)
  return TrustAllManager()
}

class SslSocketConnector : TlsConnector {
  override fun open(address: String, port: Int, fingerprint: String): TlsLink {
    val manager = trustManagerForFingerprint(fingerprint)
    val context = SSLContext.getInstance("TLS")
    context.init(null, arrayOf(manager), SecureRandom())
    // The emulator installs a SOCKS proxy. Socket.connect then never reaches the desktop listener.
    val plain = Socket(Proxy.NO_PROXY)
    var wrapped: SSLSocket? = null
    try {
      plain.keepAlive = true
      plain.connect(InetSocketAddress(address, port), ConnectTimeoutMs)
      val socket = context.socketFactory.createSocket(plain, address, port, true) as SSLSocket
      socket.keepAlive = true
      wrapped = socket
      val protocols = socket.supportedProtocols.filter { it == "TLSv1.3" || it == "TLSv1.2" }
      if (protocols.isNotEmpty()) socket.enabledProtocols = protocols.toTypedArray()
      val parameters = socket.sslParameters
      parameters.endpointIdentificationAlgorithm = null
      socket.sslParameters = parameters
      // One second so the loop can ping and check a partial frame. A timeout is not a closed host.
      socket.soTimeout = ReadTimeoutMs
      socket.startHandshake()
      return SocketLink(socket)
    } catch (error: Exception) {
      try {
        wrapped?.close()
      } catch (ignored: Exception) {
      }
      try {
        plain.close()
      } catch (ignored: Exception) {
      }
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
  Deferred,
  Superseded
}

/** Continue is the only non-terminal value. Retry keeps the busy/auth reconnect path. */
private enum class ReadEnd {
  Continue,
  PeerClosed,
  Dead,
  Rejected,
  Disabled,
  WriteFailed,
  Retry,
  Background
}

/** Monotonic nanoseconds. Ping writes are not inbound activity and do not move this clock. */
interface MonotonicClock {
  fun nanoTime(): Long
  fun addListener(listener: () -> Unit) {}
  fun removeListener(listener: () -> Unit) {}
}

object SystemMonotonicClock : MonotonicClock {
  override fun nanoTime(): Long = System.nanoTime()
}

/** Advances only when the test says so, and wakes delivery waits without sleeping. */
class SteppableClock : MonotonicClock {
  private var nanos = 0L
  private val listeners = mutableListOf<() -> Unit>()

  override fun nanoTime(): Long = nanos

  override fun addListener(listener: () -> Unit) {
    synchronized(listeners) { listeners += listener }
  }

  override fun removeListener(listener: () -> Unit) {
    synchronized(listeners) { listeners -= listener }
  }

  fun advanceMs(ms: Long) {
    nanos += ms * 1_000_000L
    val copy = synchronized(listeners) { listeners.toList() }
    for (listener in copy) listener()
  }
}

enum class DeliveryResult {
  Queued,
  Failed
}

class InboundDelivery(
  private val clock: MonotonicClock = SystemMonotonicClock,
  private val byteBudget: Long = InboundCreditBytes.toLong()
) {
  private val pending = ArrayDeque<MonitorMessage>()
  private val gate = Any()
  private val available = Channel<Unit>(Channel.CONFLATED)
  private var queuedBytes = 0L

  val messages: Flow<MonitorMessage> = flow {
    while (coroutineContext[Job]?.isActive != false) emit(take())
  }

  internal fun isWaiting(): Boolean = false

  suspend fun publish(message: MonitorMessage): DeliveryResult {
    return if (offer(message)) DeliveryResult.Queued else DeliveryResult.Failed
  }

  private fun offer(message: MonitorMessage): Boolean {
    val stored = synchronized(gate) {
      val incoming = messageBytes(message)
      if (message.kind in CoalescedKinds) {
        val index = pending.indexOfFirst { it.kind == message.kind }
        if (index >= 0) {
          queuedBytes = queuedBytes - messageBytes(pending[index]) + incoming
          pending[index] = message
          return@synchronized true
        }
      }
      if (queuedBytes + incoming > byteBudget) return@synchronized false
      pending.addLast(message)
      queuedBytes += incoming
      true
    }
    if (stored) available.trySend(Unit)
    return stored
  }

  private suspend fun take(): MonitorMessage {
    while (true) {
      val next = synchronized(gate) {
        if (pending.isEmpty()) null else {
          val message = pending.removeFirst()
          queuedBytes -= messageBytes(message)
          message
        }
      }
      if (next != null) return next
      available.receive()
    }
  }

private fun messageBytes(message: MonitorMessage): Int {
  val counted = message.wireJson.length
  return if (counted > 0) counted else message.payloadJson.length
}

  companion object {
    // Transcript, TurnData, ImageData, ImageUnavailable, ApprovalRequested,
    // ApprovalClosed, InsertResult, Error, Rejected, Bye, PairOk, HelloOk, and Ping are never coalesced.
    private val CoalescedKinds = setOf(
      MessageKind.Snapshot,
      MessageKind.Status,
      MessageKind.Mode,
      MessageKind.Target,
      MessageKind.Plan,
      MessageKind.Tasks
    )
  }
}

enum class CatalogueWrite {
  Written,
  Failed,
  Stale
}

data class CatalogueResult(
  val commandId: String,
  val linkEpoch: Int,
  val outcome: CatalogueWrite
)

data class AcceptedCatalogue(
  val commandId: String,
  val linkEpoch: Int,
  val json: String,
  val socket: Any?
)

sealed class CatalogueStep {
  data class Done(val result: CatalogueResult) : CatalogueStep()
  data class Write(val accepted: AcceptedCatalogue) : CatalogueStep()
}

/** Captures the command id and the link epoch that accepted the command. */
fun beginCatalogue(json: String, linkEpoch: Int, socket: Any?): AcceptedCatalogue {
  return AcceptedCatalogue(catalogueCommandId(json), linkEpoch, json, socket)
}

/** A stale command or a missing socket is finished here. The caller must not write. */
fun stepCatalogue(accepted: AcceptedCatalogue, currentEpoch: Int, currentSocket: Any?): CatalogueStep {
  val socket = accepted.socket
  if (socket == null) {
    return CatalogueStep.Done(CatalogueResult(accepted.commandId, accepted.linkEpoch, CatalogueWrite.Failed))
  }
  if (currentEpoch != accepted.linkEpoch || currentSocket !== socket) {
    return CatalogueStep.Done(CatalogueResult(accepted.commandId, accepted.linkEpoch, CatalogueWrite.Stale))
  }
  return CatalogueStep.Write(accepted)
}

fun catalogueFromWrite(accepted: AcceptedCatalogue, wrote: Boolean): CatalogueResult {
  val outcome = if (wrote) CatalogueWrite.Written else CatalogueWrite.Failed
  return CatalogueResult(accepted.commandId, accepted.linkEpoch, outcome)
}

fun catalogueCommandId(json: String): String {
  val decoded = tryDecodeEnvelope(json)
  if (!decoded.ok) return ""
  return decoded.message.id
}

interface SessionPort {
  val promptDraft: String
  val hostAddress: String
  val hostPort: Int
  val hostClientId: String
  val linkEpoch: Int
  val commandResults: Flow<CatalogueResult>
  fun nextCommandId(): String
  fun updateDraft(text: String)
  fun sendCatalogue(json: String)
  fun resetImages()
}

class LanSession(
  private val store: HostStore,
  private val connector: TlsConnector = SslSocketConnector(),
  private val clock: MonotonicClock = SystemMonotonicClock
) : SessionPort {
  private val job = SupervisorJob()
  private val scope = CoroutineScope(job + Dispatchers.IO)
  private val writeLock = Mutex()
  private val socketLock = Any()
  private val resumes = Channel<Unit>(Channel.CONFLATED)
  private val wakes = Channel<Unit>(Channel.CONFLATED)
  private val ids = AtomicInteger(1)
  private val epochCounter = AtomicInteger(0)
  private val commandResultsChannel = Channel<CatalogueResult>(Channel.BUFFERED)
  private val policy = ReconnectPolicy()
  private val session = computing.michell.monitor.protocol.SessionState()
  private val chunks = ChunkAssembly()
  private val statusState = MutableStateFlow(LinkStatus())
  internal val inbound = InboundDelivery(clock)
  private var loop: Job? = null
  private var link: TlsLink? = null
  private var writer: ConnectionWriter? = null
  internal val events = AccountedEvents()
  private var applier: computing.michell.monitor.data.SyncApplier? = null
  @Volatile
  private var lastSentMs = 0L
  @Volatile
  private var lastReceivedMs = 0L
  private var pairCode = ""
  private var stopped = false
  @Volatile
  private var armed = false
  @Volatile
  private var terminal = false
  @Volatile
  private var inForeground = true
  @Volatile
  private var lanAvailable = true
  @Volatile
  private var connectNow = false
  @Volatile
  private var leftForBackground = false

  val status: StateFlow<LinkStatus> = statusState.asStateFlow()
  val messages: Flow<computing.michell.monitor.protocol.MonitorMessage> = inbound.messages
  override val commandResults: Flow<CatalogueResult> = commandResultsChannel.receiveAsFlow()
  override val linkEpoch: Int
    get() = epochCounter.get()
  val reconnectPaused: Boolean
    get() = policy.paused

  @Volatile
  override var promptDraft: String = ""
    private set

  override fun sendCatalogue(json: String) {
    if (json.isEmpty()) return
    val accepted = beginCatalogue(json, epochCounter.get(), if (stopped) null else link)
    scope.launch {
      val step = stepCatalogue(accepted, epochCounter.get(), link)
      val result = when (step) {
        is CatalogueStep.Done -> step.result
        is CatalogueStep.Write -> {
          val socket = step.accepted.socket as? TlsLink
          val wrote = if (socket == null) false else offerCommand(step.accepted.json, socket)
          catalogueFromWrite(step.accepted, wrote)
        }
      }
      commandResultsChannel.send(result)
    }
  }

  override fun nextCommandId(): String = newId()

  override fun updateDraft(text: String) {
    promptDraft = text
  }

  override val hostAddress: String get() = store.load().address
  override val hostPort: Int get() = store.load().port
  override val hostClientId: String get() = store.load().clientId

  override fun resetImages() {
    // Image bytes are assembled only in the UI. There is no session copy to drop.
  }

  /** Opens the saved endpoint. Does not replace or clear the TLS pin. */
  fun connect(address: String, port: Int, code: String = "") {
    val current = store.load()
    val trimmed = address.trim()
    val changed = current.address != trimmed || current.port != port
    val next = if (changed) {
      current.copy(address = trimmed, port = port, fingerprint = current.fingerprint, clientId = "", sessionToken = "")
    } else {
      current.copy(address = trimmed, port = port, fingerprint = current.fingerprint)
    }
    store.save(next)
    pairCode = code
    armed = true
    terminal = false
    policy.resume()
    stopped = false
    startLoop()
  }

  /** Activity is visible. A return from the background reconnects at once. */
  fun enterForeground() {
    val returning = !inForeground
    inForeground = true
    leftForBackground = false
    if (returning) {
      connectNow = true
      if (!policy.paused) policy.resetBackoff()
    }
    wakes.trySend(Unit)
    if (mayReconnect() && loop?.isActive != true) startLoop()
  }

  /** Activity is no longer visible. Send bye, then wait until it returns. */
  fun leaveForeground() {
    if (!inForeground && leftForBackground) return
    inForeground = false
    leftForBackground = true
    val epoch = epochCounter.get()
    scope.launch { closeForBackground(epoch) }
    wakes.trySend(Unit)
  }

  /** Wi-Fi is up. Reset the LAN backoff and connect at once if the link is down. */
  fun onWifiAvailable() {
    lanAvailable = true
    connectNow = true
    if (!policy.paused) policy.resetBackoff()
    wakes.trySend(Unit)
    if (mayReconnect() && loop?.isActive != true) startLoop()
  }

  /** Wi-Fi is gone. Do not open another socket until it returns. */
  fun onWifiLost() {
    lanAvailable = false
    wakes.trySend(Unit)
  }

  /**
   * Replaces the saved pin when the value normalises to 64 hex characters.
   * Anything else is not saved, does not open a socket, and shows the pin banner.
   */
  fun replaceFingerprint(fingerprint: String) {
    if (normalizeFingerprint(fingerprint).length != 64) {
      publish(LinkPhase.Disconnected, "TLS pin mismatch.", "The fingerprint is not 64 hex characters.")
      return
    }
    store.save(store.load().copy(fingerprint = fingerprint))
  }

  /**
   * Clears the saved pin without opening a socket.
   * Connect does not call this. Forgetting a pairing uses HostStore.clear.
   */
  fun clearFingerprint() {
    store.save(store.load().copy(fingerprint = ""))
  }

  /** User tapped Connect after a refused or disabled listener paused backoff. */
  fun resume() {
    policy.resume()
    resumes.trySend(Unit)
    if (loop?.isActive != true && !stopped) startLoop()
  }

  fun disconnect() {
    stopped = true
    armed = false
    policy.pause()
    epochCounter.incrementAndGet()
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
    val epoch = epochCounter.incrementAndGet()
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
      if (epochCounter.get() != epoch || stopped) return@launch
      runLoop()
    }
  }

  private fun mayReconnect(): Boolean {
    return armed && !stopped && !terminal && !policy.paused && inForeground && lanAvailable &&
      store.load().address.isNotEmpty()
  }

  private suspend fun runLoop() {
    val epoch = epochCounter.get()
    var waitBeforeConnect = false
    while (coroutineContext[Job]?.isActive != false && !stopped && epochCounter.get() == epoch) {
      if (policy.paused) {
        val shown = statusState.value.banner.ifEmpty { HostClosedBanner }
        publish(LinkPhase.Paused, shown, statusState.value.lastError)
        resumes.receive()
        if (stopped || epochCounter.get() != epoch) return
        waitBeforeConnect = false
        continue
      }
      if (!inForeground || !lanAvailable) {
        val shown = if (!inForeground) BackgroundBanner else WaitingForWifiBanner
        publishCurrent(epoch, LinkPhase.Disconnected, shown, statusState.value.lastError)
        wakes.receive()
        continue
      }
      if (connectNow || leftForBackground) {
        connectNow = false
        waitBeforeConnect = false
        policy.resetBackoff()
      }
      if (waitBeforeConnect) {
        val woke = waitBackoffOrWake(policy.nextDelayMs())
        if (stopped || epochCounter.get() != epoch) return
        if (woke) {
          policy.resetBackoff()
          waitBeforeConnect = false
          continue
        }
      }
      if (stopped || epochCounter.get() != epoch) return
      waitBeforeConnect = true
      when (attempt(epoch)) {
        AttemptResult.Pinned -> {
          terminal = true
          return
        }
        AttemptResult.Superseded -> return
        AttemptResult.Deferred -> {
          waitBeforeConnect = false
          policy.resetBackoff()
        }
        AttemptResult.Refused -> {
          // A refused port may be the listener starting. Keep the backoff instead of waiting for a tap.
        }
        AttemptResult.Failed -> publishCurrent(epoch, LinkPhase.Disconnected, HostClosedBanner, statusState.value.lastError)
        AttemptResult.Opened -> {
          policy.resume()
          val end = readUntilClose(epoch)
          if (epochCounter.get() != epoch) return
          closeLink()
          session.onSocketClosed()
          if (epochCounter.get() != epoch) return
          // Rejected and Disabled pause. Background waits for the foreground. Everything else backs off.
          if (end == ReadEnd.Disabled || end == ReadEnd.Rejected) {
            policy.pause()
            val shown = statusState.value.banner.ifEmpty { HostClosedBanner }
            publishCurrent(epoch, LinkPhase.Disconnected, shown, statusState.value.lastError)
          } else if (end == ReadEnd.Background || leftForBackground) {
            waitBeforeConnect = false
            policy.resetBackoff()
            publishCurrent(epoch, LinkPhase.Disconnected, BackgroundBanner, statusState.value.lastError)
          } else {
            publishCurrent(epoch, LinkPhase.Disconnected, ReconnectingBanner, statusState.value.lastError)
          }
        }
      }
    }
  }

  @OptIn(ExperimentalCoroutinesApi::class)
  private suspend fun waitBackoffOrWake(delayMs: Long): Boolean {
    if (delayMs <= 0L) return false
    return select {
      wakes.onReceive { true }
      selectOnTimeout(delayMs) { false }
    }
  }

  private suspend fun closeForBackground(epoch: Int) {
    val current = link ?: return
    if (epochCounter.get() != epoch || !leftForBackground) return
    closeWithBye(current)
    noteReadEnd(epoch, ReadEnd.Background, current)
  }

  private suspend fun closeWithBye(target: TlsLink) {
    val writing = scope.launch { writeJson(encodeBye(newId(), ByeBackground), target) }
    withTimeoutOrNull(BackgroundByeMs) { writing.join() }
    closeOwned(target)
    try {
      writing.join()
    } catch (error: CancellationException) {
      throw error
    } catch (error: Exception) {
      // Closing the socket unblocks a write that could not finish.
    }
  }

  private suspend fun attempt(epoch: Int): AttemptResult {
    if (epochCounter.get() != epoch || stopped) return AttemptResult.Superseded
    if (!inForeground || !lanAvailable) return AttemptResult.Deferred
    val record = store.load()
    val pinned = normalizeFingerprint(record.fingerprint)
    if (record.fingerprint.isNotEmpty() && pinned.length != 64) {
      publish(LinkPhase.Disconnected, "TLS pin mismatch.", "The fingerprint is not 64 hex characters.")
      return AttemptResult.Pinned
    }
    if (epochCounter.get() != epoch) return AttemptResult.Superseded
    publishCurrent(epoch, LinkPhase.Connecting, "", "")
    val opened = try {
      withContext(Dispatchers.IO) {
        connector.open(record.address, record.port, record.fingerprint)
      }
    } catch (error: Exception) {
      if (epochCounter.get() != epoch) return AttemptResult.Superseded
      if (isPinFailure(error)) {
        publish(LinkPhase.Disconnected, "TLS pin mismatch.", error.message ?: "TLS pin mismatch.")
        return AttemptResult.Pinned
      }
      if (isRefused(error)) {
        publish(LinkPhase.Disconnected, ConnectionRefusedBanner, error.message ?: ConnectionRefusedBanner)
        return AttemptResult.Refused
      }
      val detail = error.message ?: "Connection failed."
      publish(LinkPhase.Disconnected, detail, detail)
      return AttemptResult.Failed
    }
    if (epochCounter.get() != epoch || stopped) {
      closeOwned(opened)
      return AttemptResult.Superseded
    }
    if (!inForeground) {
      closeWithBye(opened)
      return AttemptResult.Deferred
    }
    if (!lanAvailable) {
      closeOwned(opened)
      return AttemptResult.Deferred
    }
    link = opened
    if (!inForeground || stopped || epochCounter.get() != epoch) {
      if (!inForeground && epochCounter.get() == epoch) closeWithBye(opened) else closeOwned(opened)
      return if (epochCounter.get() == epoch && !stopped) AttemptResult.Deferred else AttemptResult.Superseded
    }
    session.onHandshakeComplete()
    val helloId = newId()
    val openPair = !record.paired
    val hello = if (openPair) {
      encodeHello(helloId, ClientName, ClientVersion, "")
    } else {
      encodeHello(helloId, ClientName, ClientVersion, record.clientId)
    }
    if (!writeJson(hello, opened)) {
      if (epochCounter.get() == epoch) closeLink() else closeOwned(opened)
      return if (epochCounter.get() == epoch) AttemptResult.Failed else AttemptResult.Superseded
    }
    if (openPair) {
      val pair = encodePair(newId(), pairCode, pinned)
      if (!writeJson(pair, opened)) {
        if (epochCounter.get() == epoch) closeLink() else closeOwned(opened)
        return if (epochCounter.get() == epoch) AttemptResult.Failed else AttemptResult.Superseded
      }
    }
    return AttemptResult.Opened
  }

  fun attachApplier(next: computing.michell.monitor.data.SyncApplier) {
    applier = next
  }

  private suspend fun readUntilClose(epoch: Int): ReadEnd {
    val current = link ?: return ReadEnd.PeerClosed
    if (epochCounter.get() != epoch) return ReadEnd.PeerClosed
    synchronized(readEndLock) { readEnd = ReadEnd.Continue }
    val openedAt = clockMs()
    lastInboundNanos = clock.nanoTime()
    lastReceivedMs = openedAt
    lastSentMs = openedAt
    val outbound = ConnectionWriter { bytes -> writeBytes(bytes, current) }
    writer = outbound
    val supervisor = SupervisorJob(coroutineContext[Job])
    val actor = CoroutineScope(supervisor + Dispatchers.IO)
    val listener = { noteHeartbeat(epoch, current, outbound) }
    clock.addListener(listener)
    try {
      val reading = actor.launch { readFrames(epoch, current, outbound) }
      val writing = actor.launch {
        if (!outbound.run()) noteReadEnd(epoch, ReadEnd.WriteFailed, current)
      }
      val beating = actor.launch {
        while (coroutineContext[Job]?.isActive != false && epochCounter.get() == epoch) {
          delay(1_000L)
          noteHeartbeat(epoch, current, outbound)
        }
      }
      val applying = actor.launch {
        while (coroutineContext[Job]?.isActive != false) {
          val event = events.receive()
          applier?.offer(event)
        }
      }
      reading.join()
      supervisor.cancel()
      for (child in listOf(writing, beating, applying)) {
        try {
          child.join()
        } catch (error: CancellationException) {
          // The reader finished. The other lanes are stopped with it.
        }
      }
      return readEnd
    } finally {
      clock.removeListener(listener)
      outbound.close()
      writer = null
      supervisor.cancel()
    }
  }

  private fun noteHeartbeat(epoch: Int, current: TlsLink, outbound: ConnectionWriter) {
    if (epochCounter.get() != epoch) return
    val now = clockMs()
    when (heartbeatStep(lastSentMs, lastReceivedMs, now)) {
      HeartbeatStep.Close -> noteReadEnd(epoch, ReadEnd.Dead, current)
      HeartbeatStep.Ping -> {
        val ping = encodeTicks(MessageKind.Ping, newId(), now)
        val frame = tryEncodeFrame(ping)
        if (frame.ok && outbound.offerControl(frame.bytes)) lastSentMs = now
      }
      HeartbeatStep.None -> {}
    }
  }

  private fun clockMs(): Long = clock.nanoTime() / 1_000_000L

  private suspend fun readFrames(epoch: Int, current: TlsLink, outbound: ConnectionWriter) {
    withContext(Dispatchers.IO) {
        val buffer = ByteArray(FrameAssembler.ReadChunkBytes)
        val reader = FrameAssembler()
        while (coroutineContext[Job]?.isActive != false && !stopped && epochCounter.get() == epoch) {
          if (inboundIsDead()) return@withContext finishRead(epoch, current, ReadEnd.Dead)
          val count = try {
            current.input.read(buffer)
          } catch (error: CancellationException) {
            throw error
          } catch (error: SocketTimeoutException) {
            0
          } catch (error: Exception) {
            if (isReadTimeout(error)) 0
            else {
              if (readEnd != ReadEnd.Continue) return@withContext finishRead(epoch, current, readEnd)
              val detail = error.message ?: "Read failed."
              publishCurrent(epoch, LinkPhase.Disconnected, detail, detail)
              return@withContext finishRead(epoch, current, ReadEnd.PeerClosed)
            }
          }
          // Closing the socket to enforce a terminal result unblocks this read. Keep that result.
          if (readEnd != ReadEnd.Continue) return@withContext finishRead(epoch, current, readEnd)
          if (count < 0) return@withContext finishRead(epoch, current, ReadEnd.PeerClosed)
          if (count > 0) {
            val arrived = System.currentTimeMillis()
            val batch = reader.offer(buffer, 0, count, arrived)
            for (frame in batch.frames) {
              noteInbound()
              onFrame(frame, epoch, current, outbound)
              if (readEnd != ReadEnd.Continue) return@withContext finishRead(epoch, current, readEnd)
            }
            if (batch.status != FrameStatus.Ok) return@withContext finishRead(epoch, current, ReadEnd.PeerClosed)
          }
          // A timeout read does not update last inbound. A ping write does not either.
          // A leftover partial starts its own clock; it does not inherit the frame just consumed.
          val now = System.currentTimeMillis()
          if (reader.partialExpired(now)) return@withContext finishRead(epoch, current, ReadEnd.PeerClosed)
          if (inboundIsDead()) return@withContext finishRead(epoch, current, ReadEnd.Dead)
          if (epochCounter.get() != epoch) return@withContext finishRead(epoch, current, ReadEnd.PeerClosed)
          if (readEnd != ReadEnd.Continue) return@withContext finishRead(epoch, current, readEnd)
        }
        finishRead(epoch, current, ReadEnd.PeerClosed)
    }
  }

  private val readEndLock = Any()
  @Volatile
  private var readEnd = ReadEnd.Continue
  @Volatile
  private var lastInboundNanos = 0L

  private suspend fun onFrame(frame: MonitorFrame, epoch: Int, owned: TlsLink, outbound: ConnectionWriter) {
    if (epochCounter.get() != epoch) return
    val envelope = tryDecodeEnvelope(frame)
    if (!envelope.ok) return
    val message = chunks.accept(envelope.message) ?: return
    session.apply(message)
    if (message.typeName == "event") {
      val event = computing.michell.monitor.protocol.decodeMonitorEvent(message.payloadJson)
      if (event != null && !events.offer(event, message.wireJson.length)) {
        closeLink()
        publishCurrent(epoch, LinkPhase.Disconnected, HostClosedBanner, DeliveryFailedDetail)
        noteReadEnd(epoch, ReadEnd.PeerClosed, owned)
        return
      }
    }
    if (inbound.publish(message) == DeliveryResult.Failed) {
      closeLink()
      publishCurrent(epoch, LinkPhase.Disconnected, HostClosedBanner, DeliveryFailedDetail)
      noteReadEnd(epoch, ReadEnd.PeerClosed, owned)
      return
    }
    when (message.kind) {
      MessageKind.PairOk -> {
        val paired = (message.inbound as? InboundPayload.PairOk)?.value ?: decodePairOk(message.payloadJson)
        if (paired != null) {
          store.savePairing(paired.clientId, paired.sessionToken)
          pairCode = ""
          offerControl(encodeResume(newId(), "", 0), owned, outbound)
        }
      }
      MessageKind.HelloOk -> {
        val hello = (message.inbound as? InboundPayload.HelloOk)?.value ?: decodeHelloOk(message.payloadJson)
        val record = store.load()
        if (hello != null && record.paired) {
          val mac = authMac(record.sessionToken, hello.nonce)
          session.noteOutbound(MessageKind.Auth)
          if (mac.isNotEmpty()) offerControl(encodeAuth(newId(), record.clientId, mac), owned, outbound)
        }
      }
      MessageKind.Ping -> {
        val ticks = decodeTicks(message.payloadJson)?.ticks ?: 0L
        if (!offerControl(encodeTicks(MessageKind.Pong, newId(), ticks), owned, outbound)) noteReadEnd(epoch, ReadEnd.WriteFailed, owned)
      }
      MessageKind.Bye -> {
        val bye = decodeBye(message.payloadJson)
        if (bye?.reason == "disabled" || bye?.reason == "revoked") {
          noteReadEnd(epoch, ReadEnd.Disabled, owned)
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
          noteReadEnd(epoch, ReadEnd.Retry, owned)
          publishCurrent(epoch, LinkPhase.Connecting, ReconnectingBanner, reason)
        } else {
          noteReadEnd(epoch, ReadEnd.Rejected, owned)
          publishCurrent(epoch, LinkPhase.Paused, reason.ifEmpty { HostClosedBanner }, reason)
        }
      }
      else -> publishCurrent(epoch, if (session.phase == computing.michell.monitor.protocol.SessionPhase.Live ||
        session.phase == computing.michell.monitor.protocol.SessionPhase.Busy) LinkPhase.Live else LinkPhase.Connecting, "", "")
    }
  }

  private fun offerControl(json: String, owned: TlsLink, outbound: ConnectionWriter): Boolean {
    if (owned !== link) return false
    val frame = tryEncodeFrame(json)
    if (!frame.ok) return false
    return outbound.offerControl(frame.bytes)
  }

  private fun offerCommand(json: String, owned: TlsLink): Boolean {
    val outbound = writer
    if (outbound == null || owned !== link) return writeJson(json, owned)
    val frame = tryEncodeFrame(json)
    if (!frame.ok) return false
    return outbound.offerCommand(frame.bytes)
  }

  private fun writeJson(json: String, owned: TlsLink? = link): Boolean {
    val frame = tryEncodeFrame(json)
    if (!frame.ok) return false
    val target = owned ?: return false
    return writeBytes(frame.bytes, target)
  }

  private fun writeBytes(bytes: ByteArray, owned: TlsLink): Boolean {
    synchronized(socketLock) {
      return try {
        owned.output.write(bytes)
        owned.output.flush()
        lastSentMs = clockMs()
        true
      } catch (error: Exception) {
        false
      }
    }
  }

  private fun noteReadEnd(epoch: Int, end: ReadEnd, owned: TlsLink?) {
    if (end == ReadEnd.Continue) return
    if (epochCounter.get() != epoch) return
    val closeNow = synchronized(readEndLock) {
      if (readEnd != ReadEnd.Continue) {
        false
      } else {
        readEnd = end
        true
      }
    }
    if (closeNow) closeOwned(owned)
  }

  private fun finishRead(epoch: Int, owned: TlsLink, end: ReadEnd): ReadEnd {
    noteReadEnd(epoch, end, owned)
    return readEnd
  }

  private fun noteInbound() {
    lastInboundNanos = clock.nanoTime()
    lastReceivedMs = clockMs()
  }

  private fun inboundIsDead(): Boolean {
    val delta = clock.nanoTime() - lastInboundNanos
    if (delta <= 0L) return false
    return delta / 1_000_000L >= MonitorLimits.DeadSessionMs
  }

  private fun publishCurrent(epoch: Int, phase: LinkPhase, banner: String, error: String) {
    if (epochCounter.get() != epoch) return
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

private fun isReadTimeout(error: Throwable): Boolean {
  var current: Throwable? = error
  while (current != null) {
    if (current is SocketTimeoutException) return true
    val text = current.message?.lowercase() ?: ""
    if (text.contains("timed out") || text.contains("timeout")) return true
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
private const val BackgroundByeMs = 500L
private const val HexDigits = "0123456789abcdef"
