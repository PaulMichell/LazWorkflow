package computing.michell.monitor.connection

/* TLS session for the monitor phone (c) 2026 Michell Computing.

   Size note: exceeds the 1000 line preference. The socket, pin rules, and
   reconnect loop are one session. Wi-Fi registration lives in WifiLanWatch.
   A physical connection is a context inside that session, not a second service.
   Reviewed 2026-11-12.

   The socket is javax.net.ssl.SSLSocket. There is no cleartext open and no
   HTTP client. The TCP socket is created with no proxy: the emulator SOCKS
   proxy never reaches the desktop listener. One writer coroutine owns the socket
   write. The reader coroutine owns the blocking read. SSLSocket allows that pair;
   it does not confine the write to an OS thread, and close() from any thread still
   unblocks either call. A queued frame wakes the writer instead of waiting out the
   read timeout. An empty fingerprint
   trusts the server certificate so the phone can connect by endpoint only.
   Connect keeps a saved pin. A nonempty pin that is not 64 hex characters
   is refused. A full credit window stops the read. The event is held, not
   dropped and not acked. A silent, rejected, or
   failed-write peer leaves the read loop and the owned socket is closed.
   The unsent prompt draft is kept across disconnect. A catalogue command
   is written only on the socket that accepted it. Wi-Fi becoming available
   reconnects at once and resets the backoff. A loss is a banner hint, not a
   latch: a touch, the 30 second in-use retry, and a failed attempt still open
   the saved endpoint. On a LAN the wait is 1, 2, 4,
   8 seconds with equal jitter, then 30 seconds while the app is in use. A
   touch, a key or a return to the foreground is use, and a link that is
   down tries at once on it. Two minutes without use is idle: the loop stops
   trying until the next use. A monitoring demand — a running plan, a running
   turn, or a screen-off hold — keeps the capped retry going through that idle
   window. The demand sticks across a drop until a resynchronised picture says
   execution ended. It does not fake a touch, and it does not override bye,
   background, or an explicit disconnect. The reconnect loop is one epoch.
   Each successful open is a later generation: its writer, assemblers,
   transient queues, last I/O and close outcome die with that socket. A
   completion tagged with an older generation is stale. Room and the command
   ledger stay. An in-flight Room commit finishes before the next baseline
   is applied; anything still uncommitted is dropped and the durable cursor
   is what the next resume asks for. Leaving the app sends bye and waits
   to resume. The backlight going off does not, while a plan or turn is running
   or the monitor task is still resumed. That hold does not open a second socket.
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
import computing.michell.monitor.protocol.decodeCommandState
import computing.michell.monitor.protocol.decodeCommandStates
import computing.michell.monitor.protocol.decodeResume
import computing.michell.monitor.protocol.decodeHelloOk
import computing.michell.monitor.protocol.decodePairOk
import computing.michell.monitor.protocol.decodeSyncEnvelope
import computing.michell.monitor.protocol.decodeTicks
import computing.michell.monitor.protocol.encodeAuth
import computing.michell.monitor.protocol.encodeBye
import computing.michell.monitor.protocol.encodeEmpty
import computing.michell.monitor.protocol.encodeHello
import computing.michell.monitor.protocol.encodeSyncResume
import computing.michell.monitor.protocol.encodePair
import computing.michell.monitor.protocol.encodeTicks
import computing.michell.monitor.protocol.SyncFrame
import computing.michell.monitor.protocol.tryDecodeEnvelope
import computing.michell.monitor.protocol.utf8Length
import computing.michell.monitor.protocol.tryEncodeFrame
import java.io.Closeable
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
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
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withTimeout
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
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.selects.onTimeout as selectOnTimeout
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.withContext

const val HostClosedBanner = "Host closed"
const val ConnectionRefusedBanner = "Connection refused."
const val ReconnectingBanner = "Reconnecting"
const val BackgroundBanner = "In the background"
const val WaitingForWifiBanner = "Waiting for Wi-Fi"
const val IdleOfflineBanner = "Offline until the screen is touched"
const val ByeBackground = "background"

/** Screen-off keeps the socket when a plan or turn is running, or the task is still resumed. */
fun holdLinkAcrossScreenOff(planRunning: Boolean, turnRunning: Boolean, taskResumed: Boolean): Boolean {
  return planRunning || turnRunning || taskResumed
}

/**
 * A running plan, a running turn, or a screen-off hold needs the link.
 * That need sticks across a drop. Only a resynchronised idle picture clears it.
 * A false report that is not a resynchronised picture leaves the previous demand.
 */
fun nextMonitoringDemand(
  demanded: Boolean,
  planRunning: Boolean,
  turnRunning: Boolean,
  screenHold: Boolean,
  resynchronised: Boolean
): Boolean {
  if (planRunning || turnRunning || screenHold) return true
  if (resynchronised) return false
  return demanded
}
const val LanBackoffCapMs = 10_000L
/** The retry after the short ramp, while the app is in use. */
const val LanSlowRetryMs = 30_000L
/** Use ends this long after the last touch, key or return to the foreground. */
const val LanActiveWindowMs = 120_000L
/** A touch or key does not start an attempt this soon after the last one began. */
const val ActivityRetryGapMs = 10_000L
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
  val lastError: String = "",
  /** Kept when the banner becomes Reconnecting. Not a session token or a prompt. */
  val failureReason: String = ""
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

private val LanBackoffBases = longArrayOf(1_000L, 2_000L, 4_000L, 8_000L, LanSlowRetryMs)

class ReconnectPolicy(private val roll: () -> Int = { ThreadLocalRandom.current().nextInt(1000) }) {
  private var index = 0
  @Volatile
  var paused: Boolean = false
    private set

  /** The short ramp is jittered. The slow retry is a steady 30 seconds. */
  fun nextDelayMs(): Long {
    val base = synchronized(this) {
      val current = index
      if (index < LanBackoffBases.lastIndex) index += 1
      LanBackoffBases[current.coerceAtMost(LanBackoffBases.lastIndex)]
    }
    if (base >= LanSlowRetryMs) return base
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
  val peerFingerprint: String get() = ""
  val input: InputStream
  val output: OutputStream
}

fun interface TlsConnector {
  fun open(address: String, port: Int, fingerprint: String): TlsLink
  /** A null route keeps the process default. A LAN route is bound before connect. */
  fun open(address: String, port: Int, fingerprint: String, route: LanRoute?): TlsLink =
    open(address, port, fingerprint)
}

internal data class OpeningDeadlines(
  val connectMs: Int,
  val handshakeMs: Int,
  val sessionSetupMs: Int,
  val steadyReadMs: Int
)

internal val MonitorOpeningDeadlines = OpeningDeadlines(
  connectMs = ConnectTimeoutMs,
  handshakeMs = HandshakeTimeoutMs,
  sessionSetupMs = SessionSetupMs,
  steadyReadMs = ReadTimeoutMs
)

/**
 * TCP connect, TLS handshake, and the later steady read each have their own
 * budget. The handshake must not inherit the one-second read timeout.
 * A failure closes the socket.
 */
internal fun openWithDeadlines(
  deadlines: OpeningDeadlines = MonitorOpeningDeadlines,
  bind: () -> Unit = {},
  connect: (Int) -> Unit = {},
  handshake: (Int) -> Unit,
  restore: (Int) -> Unit = {},
  close: () -> Unit = {}
) {
  try {
    bind()
    connect(deadlines.connectMs)
    handshake(deadlines.handshakeMs)
    restore(deadlines.steadyReadMs)
  } catch (error: Exception) {
    close()
    throw error
  }
}

/** Empty selects endpoint-only trust. A 64-hex pin is pinned. Any other nonempty value is refused. */
internal fun trustManagerForFingerprint(fingerprint: String): X509TrustManager {
  val pinned = normalizeFingerprint(fingerprint)
  if (fingerprint.isNotEmpty() && pinned.length != 64) throw PinMismatchException(fingerprint)
  if (pinned.length == 64) return PinnedTrustManager(fingerprint)
  return TrustAllManager()
}

class SslSocketConnector(
  private val binder: LanSocketBinder = LanSocketBinder.None
) : TlsConnector {
  override fun open(address: String, port: Int, fingerprint: String): TlsLink =
    open(address, port, fingerprint, null)

  override fun open(address: String, port: Int, fingerprint: String, route: LanRoute?): TlsLink {
    val manager = trustManagerForFingerprint(fingerprint)
    val context = SSLContext.getInstance("TLS")
    context.init(null, arrayOf(manager), SecureRandom())
    // The emulator installs a SOCKS proxy. Socket.connect then never reaches the desktop listener.
    val plain = Socket(Proxy.NO_PROXY)
    var wrapped: SSLSocket? = null
    try {
      plain.keepAlive = true
      plain.tcpNoDelay = true
      openWithDeadlines(
        MonitorOpeningDeadlines,
        bind = { binder.bind(plain, route) },
        connect = { timeout -> plain.connect(InetSocketAddress(address, port), timeout) },
        handshake = { timeout ->
          val socket = context.socketFactory.createSocket(plain, address, port, true) as SSLSocket
          socket.keepAlive = true
          socket.tcpNoDelay = true
          wrapped = socket
          val protocols = socket.supportedProtocols.filter { it == "TLSv1.3" || it == "TLSv1.2" }
          if (protocols.isNotEmpty()) socket.enabledProtocols = protocols.toTypedArray()
          val parameters = socket.sslParameters
          parameters.endpointIdentificationAlgorithm = null
          socket.sslParameters = parameters
          // Handshake budget, not the steady-state read timeout.
          socket.soTimeout = timeout
          socket.startHandshake()
        },
        restore = { timeout -> wrapped?.soTimeout = timeout },
        close = {
          try {
            wrapped?.close()
          } catch (ignored: Exception) {
          }
          try {
            plain.close()
          } catch (ignored: Exception) {
          }
        }
      )
      return SocketLink(wrapped ?: throw java.io.IOException("TLS handshake did not open a socket."))
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
  override val peerFingerprint: String = sha256Hex(socket.session.peerCertificates.first().encoded)
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
  Waiting,
  Superseded
}

/**
 * Continue is the only non-terminal value.
 * PeerClosed, Dead, WriteFailed, Retry and WorkerFailed back off and try again.
 * Rejected and Disabled pause until the user resumes. Background waits for the foreground.
 */
private enum class ReadEnd {
  Continue,
  PeerClosed,
  Dead,
  Rejected,
  Disabled,
  WriteFailed,
  Retry,
  WorkerFailed,
  Background
}

private class OpenTimedOut : Exception("Connection opening timed out.")

internal interface LinkApplier {
  suspend fun offer(event: computing.michell.monitor.protocol.MonitorEvent, generation: Int)
  suspend fun offerFrame(frame: SyncFrame, generation: Int)
  suspend fun noteRefused(event: computing.michell.monitor.protocol.MonitorEvent, generation: Int)
  /** The next baseline waits until this returns. In-flight commits already finished. */
  suspend fun adoptConnection(generation: Int) {}
  /** Ignore a newer generation. Drop this socket's uncommitted assembly. */
  suspend fun retireConnection(generation: Int) {}
}

/**
 * One open socket. The reconnect loop may own several of these in turn.
 * Downstream work is tagged with [generation]. A later socket does not
 * inherit the writer, assemblers, queues, clocks or close outcome.
 */
private class PhysicalConnection(
  val generation: Int,
  val socket: TlsLink,
  val openedAtMs: Long,
  inboundNanos: Long,
  eventBudget: Long
) {
  // The session binds the real write when the writer coroutine starts. This refuses a stray run().
  val writer = ConnectionWriter { _ -> false }
  val chunks = ChunkAssembly()
  val events = AccountedEvents(eventBudget)
  val syncFrames = Channel<SyncFrame>(SyncFrameQueue)
  val refusedEvents = Channel<computing.michell.monitor.protocol.MonitorEvent>(RefusedEventQueue)
  @Volatile var lastSentMs: Long = openedAtMs
  @Volatile var lastReceivedMs: Long = openedAtMs
  @Volatile var lastInboundNanos: Long = inboundNanos
  @Volatile var setupComplete: Boolean = false
  /** First time this socket was Live. Negative until then. The stall budget starts here. */
  @Volatile var liveAtMs: Long = -1L
  /** A committed cursor or baseline on this socket. Negative until then. A ping does not set this. */
  @Volatile var committedAtMs: Long = -1L
  @Volatile var outcome: ReadEnd = ReadEnd.Continue
  private val outcomeLock = Any()

  /** True when this call recorded the first terminal outcome. */
  fun closeOutcome(end: ReadEnd): Boolean {
    if (end == ReadEnd.Continue) return false
    return synchronized(outcomeLock) {
      if (outcome != ReadEnd.Continue) {
        false
      } else {
        outcome = end
        true
      }
    }
  }

  fun abandon() {
    chunks.reset()
    events.close()
    syncFrames.close()
    refusedEvents.close()
    writer.close()
  }
}

/** Monotonic nanoseconds. Ping writes are not inbound activity and do not move this clock. */
interface MonotonicClock {
  fun nanoTime(): Long
  /** Civil milliseconds. A partial frame must not be timed with this. */
  fun wallTimeMillis(): Long = System.currentTimeMillis()
  fun addListener(listener: () -> Unit) {}
  fun removeListener(listener: () -> Unit) {}
}

object SystemMonotonicClock : MonotonicClock {
  override fun nanoTime(): Long = System.nanoTime()
}

/** Advances only when the test says so, and wakes delivery waits without sleeping. */
class SteppableClock : MonotonicClock {
  private var nanos = 0L
  private var wallMs = 0L
  private val listeners = mutableListOf<() -> Unit>()

  override fun nanoTime(): Long = nanos

  override fun wallTimeMillis(): Long = wallMs

  /** A civil-time step. Does not move nanoTime and does not wake listeners. */
  fun advanceWallMs(ms: Long) {
    wallMs += ms
  }

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
  Dropped,
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

  internal fun queuedBytes(): Long = synchronized(gate) { queuedBytes }

  suspend fun publish(message: MonitorMessage): DeliveryResult {
    // Never wait. A page larger than the budget used to block the reader, the host
    // then could not read a send, and the reconnect came back stuck on Syncing.
    return if (offer(message)) DeliveryResult.Queued else DeliveryResult.Dropped
  }

  private fun offer(message: MonitorMessage): Boolean {
    val stored = synchronized(gate) {
      val incoming = messageBytes(message)
      if (incoming < 0) return@synchronized false
      if (message.kind in CoalescedKinds) {
        val index = pending.indexOfFirst { it.kind == message.kind }
        if (index >= 0) return@synchronized replaceCoalesced(index, message, incoming)
      }
      if (queuedBytes + incoming <= byteBudget) {
        enqueue(message, incoming)
        return@synchronized true
      }
      if (!isEssentialDelivery(message.kind)) return@synchronized false
      evictNonEssential(incoming)
      if (queuedBytes + incoming <= byteBudget || incoming > byteBudget) {
        if (incoming > byteBudget) dropOversized()
        enqueue(message, incoming)
        return@synchronized true
      }
      false
    }
    if (stored) available.trySend(Unit)
    return stored
  }

  /** Latest coalesced value. A replacement that does not fit is kept only when it is essential. */
  private fun replaceCoalesced(index: Int, message: MonitorMessage, incoming: Int): Boolean {
    val old = messageBytes(pending[index])
    val without = queuedBytes - old
    if (without + incoming <= byteBudget) {
      pending[index] = message
      queuedBytes = without + incoming
      return true
    }
    if (!isEssentialDelivery(message.kind)) return false
    pending[index] = message
    queuedBytes = without + incoming
    evictNonEssential(0, index)
    if (incoming > byteBudget) dropOversized(index)
    return true
  }

  private fun enqueue(message: MonitorMessage, incoming: Int) {
    val slot = if (message.kind == MessageKind.Plan) planInsertAt() else pending.size
    pending.add(slot, message)
    queuedBytes += incoming
  }

  /** Drops bulk from the tail until [incoming] fits, or nothing bulk remains. */
  private fun evictNonEssential(incoming: Int, keep: Int = -1) {
    var index = pending.size - 1
    while (index >= 0 && queuedBytes + incoming > byteBudget) {
      if (index != keep && !isEssentialDelivery(pending[index].kind)) {
        queuedBytes -= messageBytes(pending[index])
        pending.removeAt(index)
      }
      index -= 1
    }
  }

  /** At most one message may exceed the budget. It is the latest oversized essential. */
  private fun dropOversized(keep: Int = -1) {
    var index = pending.size - 1
    while (index >= 0) {
      if (index != keep && messageBytes(pending[index]) > byteBudget) {
        queuedBytes -= messageBytes(pending[index])
        pending.removeAt(index)
      }
      index -= 1
    }
  }

  private fun planInsertAt(): Int {
    val index = pending.indexOfFirst { message -> message.kind in PlanBefore }
    if (index < 0) return pending.size
    return index
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
    val text = if (message.wireJson.isNotEmpty()) message.wireJson else message.payloadJson
    val counted = utf8Length(text)
    if (counted < 0 || counted == Int.MAX_VALUE) return -1
    return counted
  }

  companion object {
    // Transcript, TurnData, ImageData, ImageUnavailable, ApprovalRequested,
    // ApprovalClosed, InsertResult, Error, Rejected, Bye, PairOk, HelloOk, and Ping are never coalesced.
    private val CoalescedKinds = setOf(
      MessageKind.Status,
      MessageKind.Mode,
      MessageKind.Target,
      MessageKind.Plan,
      MessageKind.Tasks
    )
    private val PlanBefore = setOf(
      MessageKind.SnapshotPage,
      MessageKind.ImageData,
      MessageKind.ImageUnavailable,
      MessageKind.Chunk
    )
  }
}

/** Handshake, approval, and the latest plan must not disappear behind bulk pages. */
internal fun isEssentialDelivery(kind: MessageKind): Boolean {
  return kind == MessageKind.HelloOk || kind == MessageKind.PairOk || kind == MessageKind.Bye ||
    kind == MessageKind.Rejected || kind == MessageKind.ApprovalRequested || kind == MessageKind.ApprovalClosed ||
    kind == MessageKind.Ping || kind == MessageKind.Pong || kind == MessageKind.CommandState ||
    kind == MessageKind.CommandStates || kind == MessageKind.Plan
}

enum class CatalogueWrite {
  /** The writer accepted the frame. The socket has not taken the bytes yet. */
  Queued,
  /** The owned socket write returned. Not a host acknowledgement. */
  Written,
  /** The host reported a durable command state. */
  Acknowledged,
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

/** Socket write, not queue admission. Admission uses [catalogueFromAdmission]. */
fun catalogueFromWrite(accepted: AcceptedCatalogue, wrote: Boolean): CatalogueResult {
  return catalogueFromSocketWrite(accepted, wrote)
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
  /**
   * The only resume. Stores the Room cursor and writes it once on this live socket.
   * The same triple is refused while that socket is still up. A later cursor, a gap,
   * or a new socket may send again.
   */
  fun resumeFromRoom(conversationId: String, streamId: String, seq: Long): Boolean = false
  fun reconnect() {}
  /** The link is down but will come back on its own or on use. A prompt may wait for it. */
  val reconnectable: Boolean get() = false
  /** A touch, a key or a send. A link that is down tries at once. */
  fun noteActivity() {}
  /**
   * The model reports a running plan, a running turn, or a screen-off hold.
   * True sticks until a resynchronised idle picture. A drop must not clear it.
   */
  fun noteMonitoring(planRunning: Boolean, turnRunning: Boolean, screenHold: Boolean, resynchronised: Boolean) {}
}

class LanSession(
  private val store: HostStore,
  private val connector: TlsConnector = SslSocketConnector(),
  private val clock: MonotonicClock = SystemMonotonicClock,
  private val ledger: CommandLedger = NoCommandLedger,
  private val diagnostic: (String) -> Unit = {},
  private val eventBudget: Long = InboundCreditBytes.toLong()
) : SessionPort {
  private val job = SupervisorJob()
  private val scope = CoroutineScope(job + Dispatchers.IO + CoroutineExceptionHandler { _, error ->
    if (error is CancellationException) return@CoroutineExceptionHandler
    publish(LinkPhase.Disconnected, HostClosedBanner, error.message ?: "Connection failed.")
  })
  private val resumes = Channel<Unit>(Channel.CONFLATED)
  private val wakes = Channel<Unit>(Channel.CONFLATED)
  private val ids = AtomicInteger(1)
  /** Reconnect-loop lifetime. Automatic attempts share it. startLoop and disconnect move it. */
  private val epochCounter = AtomicInteger(0)
  /** Physical sockets. Each successful open takes the next value. */
  private val connectionCounter = AtomicInteger(0)
  @Volatile
  private var activeGeneration = 0
  private var connection: PhysicalConnection? = null
  private val commandResultsChannel = Channel<CatalogueResult>(Channel.BUFFERED)
  private val policy = ReconnectPolicy()
  private val session = computing.michell.monitor.protocol.SessionState()
  private val statusState = MutableStateFlow(LinkStatus())
  internal val inbound = InboundDelivery(clock)
  private var loop: Job? = null
  private var link: TlsLink? = null
  private var writer: ConnectionWriter? = null
  private var stagedOpening: List<ByteArray> = emptyList()
  /** Identity of the service coroutine's write lane. Not an OS thread. */
  @Volatile
  private var writeLane: Any? = null
  private val writeLock = Any()
  private val openingLock = Any()
  private var opening: TlsLink? = null
  /** Test injection at the decode boundary. Production leaves this null. */
  internal var frameProbe: ((MonitorFrame) -> Unit)? = null
  /** Test injection for a resume the writer did not accept. Production leaves this null. */
  internal var resumeQueued: (() -> Boolean)? = null
  /** Re-samples the current Wi-Fi bind. The view model sets this. Tests may too. */
  internal var refreshLanRoute: (() -> Unit)? = null
  /** Persists a posture change. The view model writes app files. Tests may too. */
  internal var recordIncident: ((IncidentSnapshot, List<String>) -> Unit)? = null
  @Volatile
  private var writeStartedNanos = 0L
  private val applierReady = Channel<Unit>(Channel.CONFLATED)
  private var applier: LinkApplier? = null
  private var sentResumeGeneration = -1
  private var sentResumeConversation = ""
  private var sentResumeStream = ""
  private var sentResumeSeq = -1L
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
  private var lanRoute: LanRoute? = null
  /** Once a desk route has been chosen, a missing bind must not fall through to mobile data. */
  @Volatile
  private var lanRouteRequired = false
  /** Immediate retries after a forgotten bind. Stops a refresh that cannot restore it. */
  private var staleRouteSkips = 0
  @Volatile
  private var connectNow = false
  @Volatile
  private var replaceLink = false
  @Volatile
  private var leftForBackground = false
  @Volatile
  private var lastActivityMs = clockMs()
  @Volatile
  private var monitoringDemand = false
  @Volatile
  private var lastAttemptMs = clockMs() - ActivityRetryGapMs
  @Volatile
  private var attemptCount = 0
  @Volatile
  private var nextRetryAtMs = -1L
  @Volatile
  private var openingNow = false
  /** This session has started the socket that replaces the current one. */
  @Volatile
  private var holdingReplacement = false
  /** Client id this session was replacing with. Empty when it did not open that socket. */
  @Volatile
  private var replacementClientId = ""
  @Volatile
  private var transitionReason = ""
  @Volatile
  private var workerExit = ""
  @Volatile
  private var terminalKind = ""
  @Volatile
  private var lastCommittedProgressMs = -1L
  /** Last touch that replaced a socket with no committed progress. Negative until then. */
  private var lastStalledTouchMs = -1L
  private val queuedCommands = ArrayDeque<QueuedCommand>()
  private val queuedLock = Any()
  private val incidentState = MutableStateFlow(IncidentSnapshot())

  val status: StateFlow<LinkStatus> = statusState.asStateFlow()
  /** Latest correlated incident. Export reads a fresh capture, not only this cache. */
  val incident: StateFlow<IncidentSnapshot> = incidentState.asStateFlow()
  private val undeliveredState = MutableStateFlow("")
  val undeliveredPrompt: StateFlow<String> = undeliveredState.asStateFlow()
  private var retryJson = ""
  val messages: Flow<computing.michell.monitor.protocol.MonitorMessage> = inbound.messages
  override val commandResults: Flow<CatalogueResult> = commandResultsChannel.receiveAsFlow()
  /** Generation of the open socket. Zero while no physical connection is current. */
  override val linkEpoch: Int
    get() = activeGeneration
  val reconnectPaused: Boolean
    get() = policy.paused

  /** A pin failure, a pause for the user, or no saved endpoint will not come back by itself. */
  override val reconnectable: Boolean
    get() = armed && !stopped && !terminal && !policy.paused && store.load().address.isNotEmpty()

  @Volatile
  override var promptDraft: String = ""
    private set

  override fun sendCatalogue(json: String) {
    if (json.isEmpty()) return
    val accepted = beginCatalogue(json, activeGeneration, if (stopped) null else link)
    scope.launch {
      val outboundJson = prepareOutbound(json)
      val step = stepCatalogue(accepted.copy(json = outboundJson), activeGeneration, link)
      val result = when (step) {
        is CatalogueStep.Done -> step.result
        is CatalogueStep.Write -> {
          val socket = step.accepted.socket as? TlsLink
          val admitted = socket != null && offerCommand(step.accepted.json, socket)
          // Admission is Queued and is reported by offerCommand. A miss is Failed, not Written.
          if (admitted) null else catalogueFromAdmission(step.accepted, false)
        }
      }
      if (result != null) {
        if (result.outcome != CatalogueWrite.Queued && result.outcome != CatalogueWrite.Written) {
          trace("outbound ${tryDecodeEnvelope(outboundJson).message.kind}: ${result.outcome}, generation=${result.linkEpoch}")
        }
        emitResult(result)
      }
    }
  }

  override fun nextCommandId(): String = newId()

  /** User asked to send the prompt whose outcome could not be known. Same command id. */
  fun retryUndelivered() {
    val json = retryJson
    if (json.isEmpty()) return
    retryJson = ""
    undeliveredState.value = ""
    sendCatalogue(json)
  }

  fun clearUndelivered() {
    retryJson = ""
    undeliveredState.value = ""
  }

  private suspend fun prepareOutbound(json: String): String {
    if (isUserCommand(json)) ledger.remember(json)
    return resumeWithOpenCommands(json)
  }

  private fun resumeWithOpenCommands(json: String): String {
    val decoded = tryDecodeEnvelope(json)
    if (!decoded.ok || decoded.message.kind != MessageKind.Resume) return json
    val ids = ledger.openIds()
    if (ids.isEmpty()) return json
    if (decodeResume(decoded.message.payloadJson) == null) return json
    val payload = computing.michell.monitor.protocol.jsonObject(decoded.message.payloadJson) ?: return json
    val fields = payload.fields.filter { it.first != "commands" } + ("commands" to
      computing.michell.monitor.protocol.JsonValue.Arr(ids.map { computing.michell.monitor.protocol.JsonValue.Str(it) }))
    val next = computing.michell.monitor.protocol.encodeEnvelope(MessageKind.Resume, decoded.message.id,
      computing.michell.monitor.protocol.JsonValue.Obj(fields))
    return if (next.isEmpty()) json else next
  }

  private suspend fun applyHostStates(states: List<HostCommandState>, context: PhysicalConnection) {
    if (activeGeneration != context.generation || link !== context.socket) return
    val plan = ledger.applyHost(states)
    if (activeGeneration != context.generation || link !== context.socket) return
    for (state in states) {
      val acknowledged = catalogueFromHostState(state.ref, context.generation, state.state) ?: continue
      emitResult(acknowledged)
    }
    for (json in plan.resendJson) {
      if (!offerCommand(json, context.socket)) break
    }
    if (plan.retryText.isNotEmpty()) {
      retryJson = plan.retryJson
      undeliveredState.value = plan.retryText
    } else if (retryJson.isNotEmpty() && !ledger.openIds().contains(catalogueCommandId(retryJson))) {
      clearUndelivered()
    }
  }

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
    lastActivityMs = clockMs()
    armed = true
    terminal = false
    terminalKind = ""
    attemptCount = 0
    workerExit = ""
    nextRetryAtMs = -1L
    policy.resume()
    stopped = false
    startLoop()
  }

  /**
   * Activity is visible. A return from the background reconnects.
   * The socket is closed on the reader thread. Closing it here, on the UI thread, kills the
   * process on some phones while SSL_read is still in that socket.
   */
  /** True when this call is the return from the background. A hello will resume. */
  fun enterForeground(): Boolean {
    // A frozen background loss can forget the bind and leave this route set.
    // Sample the radio before the reconnect, or the open toasts and never lands.
    refreshLanRoute?.invoke()
    staleRouteSkips = 0
    val returning = !inForeground
    inForeground = true
    leftForBackground = false
    val released = releaseRecoverableLatch()
    if (returning) {
      // A screen-off Wi-Fi callback must not leave the open app waiting forever.
      lanAvailable = true
      connectNow = true
      replaceLink = true
      beginOwnReplacement()
      if (!policy.paused) policy.resetBackoff()
    }
    wakes.trySend(Unit)
    if ((released || mayReconnect()) && loop?.isActive != true) startLoop()
    // A return must not leave a heartbeating socket that has never committed.
    if (returning && lacksCommittedProgress()) replaceStalledLink()
    // Coming forward is use. An idle loop that stopped trying starts again now.
    // A latch released above has already started its attempt.
    if (!released) noteActivity()
    return returning
  }

  /**
   * A touch, a key or a send. Use keeps the 30 second retry going. A link that is down tries at once,
   * unless an attempt began in the last ten seconds, so typing does not start one per key.
   * A Wi-Fi loss hint does not block this.
   */
  override fun noteActivity() {
    val now = clockMs()
    lastActivityMs = now
    if (releaseRecoverableLatch()) return
    // An open socket that is applying stays. Heartbeats alone are not delivery.
    if (link != null) {
      if (!mayReconnect() || !lacksCommittedProgress()) return
      if (lastStalledTouchMs >= 0L && now - lastStalledTouchMs < ActivityRetryGapMs) return
      replaceStalledLink()
      return
    }
    if (!mayReconnect()) return
    // A parked loss is not a retry in flight. The ten-second gap must not leave
    // this touch in a receive the callback will not signal again.
    val parkedForLoss = nextRetryAtMs < 0L && lossHint()
    if (!parkedForLoss && now - lastAttemptMs < ActivityRetryGapMs) return
    if (parkedForLoss) sampleLanRoute()
    connectNow = true
    wakes.trySend(Unit)
    if (loop?.isActive != true) startLoop()
  }

  /**
   * The open socket has authenticated and has not committed a cursor or baseline.
   * A ping does not count. A transfer that is committing is not this.
   */
  private fun lacksCommittedProgress(): Boolean {
    val context = connection ?: return false
    if (link == null || context.committedAtMs >= 0L) return false
    noteLive(context)
    return context.liveAtMs >= 0L
  }

  /** Close a heartbeating socket that is not applying, and open the next one. */
  private fun replaceStalledLink() {
    if (link == null || stopped || !mayReconnect()) return
    lastStalledTouchMs = clockMs()
    connectNow = true
    replaceLink = true
    beginOwnReplacement()
    nextRetryAtMs = -1L
    if (!policy.paused) policy.resetBackoff()
    startLoop()
  }

  /**
   * A live socket is already delivering the plan. Asking the host to resume clears its log.
   * A return from the background reconnects, and hello resumes from the Room cursor.
   */
  fun requestLiveSync() {
  }

  /** True after a screen-off hold. The onStop path must not undo that hold. */
  @Volatile
  var holdingAcrossSleep: Boolean = false
    private set

  /** The screen came back. The socket was never closed, so this is not a reconnect. */
  fun clearScreenHold() {
    holdingAcrossSleep = false
  }

  /**
   * The user left the app. Send bye, then wait until it returns.
   * A screen-off hold does not. The owned socket stays open and no bye is written.
   */
  fun leaveForeground(screenOff: Boolean = false, holdLink: Boolean = false) {
    if (screenOff && holdLink) {
      holdingAcrossSleep = true
      noteMonitoring(planRunning = false, turnRunning = false, screenHold = true, resynchronised = false)
      return
    }
    holdingAcrossSleep = false
    if (!inForeground && leftForBackground) return
    val outbound = writer
    if (outbound != null) {
      val frame = tryEncodeFrame(encodeBye(newId(), ByeBackground))
      if (frame.ok) outbound.offerControl(frame.bytes)
    }
    inForeground = false
    leftForBackground = true
    val epoch = epochCounter.get()
    scope.launch { closeForBackground(epoch) }
    wakes.trySend(Unit)
  }
  /**
   * The open refused the saved route because its bind is gone. Drop that route,
   * sample the radio again, and try at once. Do not publish the exception: it is
   * not a host failure, and leaving the route set made every retry fail the same way.
   */
  private fun recoverStaleRoute(): Boolean {
    lanRouteRequired = true
    lanRoute = null
    refreshLanRoute?.invoke()
    if (lanRoute != null) {
      staleRouteSkips = 0
      connectNow = true
      return true
    }
    if (staleRouteSkips >= 2) return false
    staleRouteSkips += 1
    connectNow = true
    return true
  }

  /** Wi-Fi is up. Reset the LAN backoff and connect at once if the link is down. */
  fun onWifiAvailable() {
    lanAvailable = true
    connectNow = true
    if (!policy.paused) policy.resetBackoff()
    wakes.trySend(Unit)
    if (mayReconnect() && loop?.isActive != true) startLoop()
  }

  /**
   * The observed Wi-Fi network. A different identity is a roam or replacement:
   * the live socket is dropped so the next open binds to the new network.
   * A repeated report of the same identity does not reconnect.
   */
  fun onWifiRoute(route: LanRoute) {
    val previous = lanRoute
    lanRouteRequired = true
    lanRoute = route
    lanAvailable = true
    if (previous == route) return
    connectNow = true
    if (previous != null && link != null) {
      replaceLink = true
      beginOwnReplacement()
    }
    if (!policy.paused) policy.resetBackoff()
    wakes.trySend(Unit)
    if (mayReconnect() && loop?.isActive != true) startLoop()
  }

  /**
   * Confirmed Wi-Fi loss. A hint for the banner, not a latch. A touch, the in-use
   * retry, and a failed attempt still open the saved endpoint. This does not close
   * a live socket. The wake is not a connect signal: the loop samples, and a real
   * absence still waits. It must not sit in a receive the callback already left.
   */
  fun onWifiLost() {
    if (lanRoute != null) lanRouteRequired = true
    lanRoute = null
    lanAvailable = false
    wakes.trySend(Unit)
  }

  /** A loss of some other network, including a stale callback, leaves the current route. */
  fun onWifiRouteLost(route: LanRoute) {
    if (lanRoute != route) return
    onWifiLost()
  }

  internal fun currentLanRoute(): LanRoute? = lanRoute

  /**
   * Replaces the saved pin when the value normalises to 64 hex characters.
   * Anything else is not saved, does not open a socket, and shows the pin banner.
   */
  fun replaceFingerprint(fingerprint: String) {
    if (normalizeFingerprint(fingerprint).length != 64) {
      markTerminal("pin", "TLS pin mismatch.")
      publish(LinkPhase.Disconnected, "TLS pin mismatch.", "The fingerprint is not 64 hex characters.", "pin")
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

  /** User tapped Connect after a refused or disabled listener paused backoff. A terminal failure stays. */
  fun resume() {
    if (blocksAutomaticRecovery(terminal, terminalKind)) return
    lastActivityMs = clockMs()
    policy.resume()
    resumes.trySend(Unit)
    if (loop?.isActive != true && !stopped) startLoop()
  }

  fun disconnect() {
    stopped = true
    armed = false
    monitoringDemand = false
    terminal = false
    terminalKind = ""
    clearOwnReplacement()
    policy.pause()
    epochCounter.incrementAndGet()
    loop?.cancel()
    closeLink()
    publish(LinkPhase.Disconnected, HostClosedBanner, "", "disconnect", clearFailure = true)
  }

  fun close() {
    disconnect()
    job.cancel()
  }

  private fun startLoop() {
    // The previous loop must finish closing its own socket before this one opens.
    // A stuck predecessor must not hold a user reconnect forever.
    val epoch = epochCounter.incrementAndGet()
    val previous = loop
    previous?.cancel()
    closeLink()
    closeOpening()
    loop = scope.launch {
      try {
        withTimeoutOrNull(PredecessorJoinMs) { previous?.join() }
      } catch (error: CancellationException) {
        throw error
      } catch (error: Exception) {
        // The predecessor failed. This generation still owns the next attempt.
      }
      if (epochCounter.get() != epoch || stopped) return@launch
      try {
        runLoop()
      } catch (error: CancellationException) {
        throw error
      } finally {
        if (epochCounter.get() == epoch) closeLink()
      }
    }
  }

  private fun mayReconnect(): Boolean {
    // lanAvailable is a hint. A touch still retries when the watch has reported a loss.
    return armed && !stopped && !terminal && !policy.paused && inForeground &&
      store.load().address.isNotEmpty()
  }

  private suspend fun runLoop() {
    val epoch = epochCounter.get()
    var waitBeforeConnect = false
    while (coroutineContext[Job]?.isActive != false && !stopped && epochCounter.get() == epoch) {
      if (policy.paused) {
        val shown = statusState.value.banner.ifEmpty { HostClosedBanner }
        publish(LinkPhase.Paused, shown, statusState.value.lastError, "paused")
        resumes.receive()
        if (stopped || epochCounter.get() != epoch) return
        waitBeforeConnect = false
        continue
      }
      if (!inForeground) {
        publishCurrent(epoch, LinkPhase.Disconnected, BackgroundBanner, "", "background")
        wakes.receive()
        continue
      }
      // A loss hint is not a latch. Sample before parking: the callback that cleared
      // the route may already have fired, and the radio may still be up. A due retry,
      // a touch, a foreground return, and a monitoring demand must not sit in
      // resumes.receive() or a wake that will not come again.
      sampleLanRoute()
      val demanded = monitoringDemand || connectNow || leftForBackground || replaceLink
      val inUseRetryDue = !appIdle() && (waitBeforeConnect || attemptCount > 0)
      if (!lanAvailable && !demanded && !inUseRetryDue && (!waitBeforeConnect || appIdle())) {
        publishCurrent(epoch, LinkPhase.Disconnected, WaitingForWifiBanner, "", "wifi")
        wakes.receive()
        if (stopped || epochCounter.get() != epoch) return
        sampleLanRoute()
        continue
      }
      if (connectNow || leftForBackground || replaceLink) {
        connectNow = false
        replaceLink = false
        waitBeforeConnect = false
        policy.resetBackoff()
      }
      if (waitBeforeConnect) {
        if (!lanAvailable && !retriesParked()) {
          publishCurrent(epoch, LinkPhase.Disconnected, WaitingForWifiBanner, "", "wifi")
        }
        if (retriesParked()) {
          // Nobody is using the app, and no plan, turn, or screen-off hold needs the link.
          // Stop trying until a touch, a key, the foreground or Wi-Fi wakes the loop.
          publishCurrent(epoch, LinkPhase.Disconnected, IdleOfflineBanner, "", "idle")
          wakes.receive()
          if (stopped || epochCounter.get() != epoch) return
          continue
        }
        val delayMs = policy.nextDelayMs()
        nextRetryAtMs = clockMs() + delayMs
        publishIncident("retry", true)
        val woke = waitBackoffOrWake(delayMs)
        nextRetryAtMs = -1L
        if (stopped || epochCounter.get() != epoch) return
        if (woke) {
          if (connectNow || leftForBackground || replaceLink || monitoringDemand || lanAvailable) {
            policy.resetBackoff()
            waitBeforeConnect = false
            continue
          }
          // A loss hint's wake is not a callback still to come. Do not drop the
          // retry this backoff was counting and then park on wakes.receive().
          sampleLanRoute()
          if (lanAvailable || connectNow || monitoringDemand) {
            policy.resetBackoff()
            waitBeforeConnect = false
            continue
          }
        }
        if (retriesParked()) continue
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
        AttemptResult.Waiting -> publishCurrent(epoch, LinkPhase.Disconnected, WaitingForWifiBanner, "", "wifi")
        AttemptResult.Failed -> publishCurrent(epoch, LinkPhase.Disconnected, HostClosedBanner, "", "open-failed")
        AttemptResult.Opened -> {
          policy.resume()
          val end = try {
            readUntilClose(epoch)
          } catch (error: CancellationException) {
            if (epochCounter.get() == epoch) closeLink()
            throw error
          }
          if (epochCounter.get() != epoch) return
          closeLink()
          session.onSocketClosed()
          if (epochCounter.get() != epoch) return
          // Rejected and Disabled pause. Background waits for the foreground. Everything else backs off.
          if (end == ReadEnd.Disabled || end == ReadEnd.Rejected) {
            policy.pause()
            val shown = statusState.value.banner.ifEmpty { HostClosedBanner }
            publishCurrent(epoch, LinkPhase.Paused, shown, "", "user-action")
          } else if (end == ReadEnd.Background || leftForBackground) {
            waitBeforeConnect = false
            policy.resetBackoff()
            publishCurrent(epoch, LinkPhase.Disconnected, BackgroundBanner, "", "background")
          } else {
            val reason = if (statusState.value.failureReason.isEmpty()) workerExit else ""
            publishCurrent(epoch, LinkPhase.Disconnected, ReconnectingBanner, reason, "retry")
          }
        }
      }
    }
  }

  private fun appIdle(): Boolean = clockMs() - lastActivityMs >= LanActiveWindowMs

  /** Idle parking applies only when the model is not asking the link to stay up. */
  private fun retriesParked(): Boolean = !monitoringDemand && appIdle()

  /**
   * The model supplies demand. A true report, including a screen-off hold, sticks
   * across a drop. Only a resynchronised idle picture clears it. This does not
   * move the touch clock, and a stopped session is not started again.
   */
  override fun noteMonitoring(planRunning: Boolean, turnRunning: Boolean, screenHold: Boolean, resynchronised: Boolean) {
    val next = nextMonitoringDemand(monitoringDemand, planRunning, turnRunning, screenHold, resynchronised)
    if (next == monitoringDemand) return
    monitoringDemand = next
    if (!next) return
    if (mayReconnect()) sampleLanRoute()
    wakes.trySend(Unit)
    if (mayReconnect() && loop?.isActive != true) startLoop()
  }

  /** The watch has reported a loss, or a required bind is gone. Not a pause. */
  private fun lossHint(): Boolean = !lanAvailable || (lanRouteRequired && lanRoute == null)

  /** Re-read the radio. A loss hint is stale once this sample lists Wi-Fi. */
  private fun sampleLanRoute() {
    if (!lossHint()) return
    refreshLanRoute?.invoke()
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
    val context = connection ?: return
    val current = context.socket
    if (epochCounter.get() != epoch || !leftForBackground) return
    if (writer == null && writeLane == null) {
      closeWithBye(current)
      noteReadEnd(epoch, ReadEnd.Background, context)
      return
    }
    withTimeoutOrNull(1_500L) {
      while (context.outcome == ReadEnd.Continue && link === current && epochCounter.get() == epoch) delay(20)
    }
    noteReadEnd(epoch, ReadEnd.Background, context)
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

  private suspend fun openBounded(address: String, port: Int, fingerprint: String): TlsLink {
    var held: TlsLink? = null
    openingNow = true
    try {
      publishIncident("opening", true)
      return withTimeout(OpenBudgetMs) {
        withContext(Dispatchers.IO) {
          val socket = connector.open(address, port, fingerprint, lanRoute)
          held = socket
          rememberOpening(socket)
          ensureActive()
          socket
        }
      }
    } catch (error: TimeoutCancellationException) {
      abandonOpening(held)
      throw OpenTimedOut()
    } catch (error: CancellationException) {
      abandonOpening(held)
      throw error
    } finally {
      openingNow = false
    }
  }

  private fun rememberOpening(socket: TlsLink) {
    synchronized(openingLock) { opening = socket }
  }

  private fun claimOpening(socket: TlsLink) {
    synchronized(openingLock) {
      if (opening === socket) opening = null
    }
  }

  private fun closeOpening() {
    val socket = synchronized(openingLock) {
      val current = opening
      opening = null
      current
    }
    closeQuiet(socket)
  }

  private fun abandonOpening(socket: TlsLink?) {
    if (socket == null) return
    synchronized(openingLock) {
      if (opening === socket) opening = null
    }
    closeQuiet(socket)
  }

  private fun closeQuiet(socket: TlsLink?) {
    if (socket == null) return
    try {
      socket.close()
    } catch (error: Exception) {
      // The peer may already have closed the socket.
    }
  }

  /** A successful open. The loop epoch is unchanged; this generation is new. */
  private fun beginOwnReplacement() {
    holdingReplacement = true
    replacementClientId = store.load().clientId
  }

  private fun clearOwnReplacement() {
    holdingReplacement = false
    replacementClientId = ""
  }

  private fun installConnection(opened: TlsLink): PhysicalConnection {
    clearOwnReplacement()
    val generation = connectionCounter.incrementAndGet()
    val context = PhysicalConnection(generation, opened, clockMs(), clock.nanoTime(), eventBudget)
    connection = context
    writer = context.writer
    link = opened
    activeGeneration = generation
    writeStartedNanos = 0L
    trace("socket generation $generation, loop ${epochCounter.get()}")
    return context
  }

  private suspend fun attempt(epoch: Int): AttemptResult {
    if (epochCounter.get() != epoch || stopped) return AttemptResult.Superseded
    if (!inForeground) return AttemptResult.Deferred
    val record = store.load()
    val pinned = normalizeFingerprint(record.fingerprint)
    if (record.fingerprint.isNotEmpty() && pinned.length != 64) {
      markTerminal("pin", "TLS pin mismatch.")
      publish(LinkPhase.Disconnected, "TLS pin mismatch.", "The fingerprint is not 64 hex characters.", "pin")
      return AttemptResult.Pinned
    }
    if (epochCounter.get() != epoch) return AttemptResult.Superseded
    // A touch-triggered retry stays in the foreground. Sample before the open, not only on return.
    refreshLanRoute?.invoke()
    if (epochCounter.get() != epoch || stopped) return AttemptResult.Superseded
    if (!inForeground) return AttemptResult.Deferred
    if (lanRouteRequired && lanRoute == null) {
      lanAvailable = false
      publishCurrent(epoch, LinkPhase.Disconnected, WaitingForWifiBanner, "", "wifi")
      return AttemptResult.Waiting
    }
    lastAttemptMs = clockMs()
    attemptCount += 1
    publishCurrent(epoch, LinkPhase.Connecting, "", "", "opening")
    val opened = try {
      openBounded(record.address, record.port, record.fingerprint)
    } catch (error: CancellationException) {
      throw error
    } catch (error: Exception) {
      if (epochCounter.get() != epoch) return AttemptResult.Superseded
      if (isPinFailure(error)) {
        val detail = error.message ?: "TLS pin mismatch."
        markTerminal("pin", detail)
        publish(LinkPhase.Disconnected, "TLS pin mismatch.", detail, "pin")
        return AttemptResult.Pinned
      }
      if (isRefused(error)) {
        val detail = error.message ?: ConnectionRefusedBanner
        publish(LinkPhase.Disconnected, ConnectionRefusedBanner, detail, "refused")
        return AttemptResult.Refused
      }
      if (isStaleLanRoute(error)) {
        // The exception is not a host failure and must not become a toast.
        if (recoverStaleRoute()) return AttemptResult.Deferred
        publish(LinkPhase.Disconnected, WaitingForWifiBanner, "", "stale-route")
        return AttemptResult.Waiting
      }
      val detail = error.message ?: "Connection failed."
      publish(LinkPhase.Disconnected, detail, detail, "open-failed")
      return AttemptResult.Failed
    }
    staleRouteSkips = 0
    if (epochCounter.get() != epoch || stopped) {
      abandonOpening(opened)
      return AttemptResult.Superseded
    }
    claimOpening(opened)
    if (!inForeground) {
      closeWithBye(opened)
      return AttemptResult.Deferred
    }
    if (stopped || epochCounter.get() != epoch) {
      closeOwned(opened)
      return AttemptResult.Superseded
    }
    // The endpoint answered, so a stale loss hint must not banner the next drop.
    lanAvailable = true
    installConnection(opened)
    session.onHandshakeComplete()
    val helloId = newId()
    val openPair = !record.paired
    val hello = if (openPair) {
      encodeHello(helloId, ClientName, ClientVersion, "")
    } else {
      encodeHello(helloId, ClientName, ClientVersion, record.clientId)
    }
    val staged = ArrayList<ByteArray>(2)
    val helloFrame = tryEncodeFrame(hello)
    if (!helloFrame.ok) {
      if (epochCounter.get() == epoch) closeLink() else closeOwned(opened)
      return if (epochCounter.get() == epoch) AttemptResult.Failed else AttemptResult.Superseded
    }
    staged.add(helloFrame.bytes)
    if (openPair) {
      val pairFrame = tryEncodeFrame(encodePair(newId(), pairCode, opened.peerFingerprint))
      if (!pairFrame.ok) {
        if (epochCounter.get() == epoch) closeLink() else closeOwned(opened)
        return if (epochCounter.get() == epoch) AttemptResult.Failed else AttemptResult.Superseded
      }
      staged.add(pairFrame.bytes)
    }
    stagedOpening = staged
    return AttemptResult.Opened
  }

  fun attachApplier(next: computing.michell.monitor.data.SyncApplier) {
    attachLinkApplier(object : LinkApplier {
      override suspend fun offer(event: computing.michell.monitor.protocol.MonitorEvent, generation: Int) {
        next.offer(event, generation = generation)
      }
      override suspend fun offerFrame(frame: SyncFrame, generation: Int) {
        next.offerFrame(frame, generation)
      }
      override suspend fun noteRefused(event: computing.michell.monitor.protocol.MonitorEvent, generation: Int) {
        next.noteRefused(event, generation)
      }
      override suspend fun adoptConnection(generation: Int) {
        next.adoptConnection(generation)
      }
      override suspend fun retireConnection(generation: Int) {
        next.retireConnection(generation)
      }
    })
  }

  internal fun attachLinkApplier(next: LinkApplier) {
    applier = next
    applierReady.trySend(Unit)
  }

  override fun resumeFromRoom(conversationId: String, streamId: String, seq: Long): Boolean {
    if (!canWriteResume()) return false
    // The same triple is not written again on this socket generation. A later cursor,
    // a gap, or a new socket may send the cursor the previous socket already queued.
    // The reconnect-loop epoch is shared by automatic attempts, so it is not the key.
    // A failed offer is not remembered, so it can be tried again.
    val generation = activeGeneration
    if (generation != 0 && sentResumeGeneration == generation && sentResumeConversation == conversationId &&
      sentResumeStream == streamId && sentResumeSeq == seq) return false
    return writeResume(conversationId, streamId, seq)
  }

  private fun canWriteResume(): Boolean = link != null

  private fun writeResume(conversationId: String, streamId: String, seq: Long): Boolean {
    val json = encodeSyncResume(nextCommandId(), conversationId, streamId, seq)
    val outbound = writer
    val owned = link
    val queued = resumeQueued?.invoke() ?: if (outbound != null && owned != null && owned === link) {
      val prepared = resumeWithOpenCommands(json)
      val frame = tryEncodeFrame(prepared)
      frame.ok && outbound.offerControl(frame.bytes)
    } else {
      false
    }
    if (!queued) return false
    sentResumeGeneration = activeGeneration
    sentResumeConversation = conversationId
    sentResumeStream = streamId
    sentResumeSeq = seq
    return true
  }

  override fun reconnect() {
    if (stopped || blocksAutomaticRecovery(terminal, terminalKind)) return
    if (!computing.michell.monitor.data.reconnectAllowed(statusState.value.phase == LinkPhase.Live, framesArriving())) return
    forceReconnect()
  }

  /** The recovery budget expired. Heartbeats and a paused read do not hold the socket. A terminal failure stays. */
  fun forceReconnect() {
    if (stopped || blocksAutomaticRecovery(terminal, terminalKind)) return
    policy.resume()
    startLoop()
  }

  /**
   * Restarts a failed transient session. Does not clear pairing, the session token, or Room.
   * A user disconnect, revocation, disable, and a pin failure are not this action.
   * A recoverable pause and an auth or expired flag are.
   */
  fun restartTransient(): Boolean {
    if (!transientRestartAllowed(stopped, terminalKind, policy.paused, armed, store.load().address, statusState.value.phase)) {
      return false
    }
    if (!releaseRecoverableLatch()) {
      lastActivityMs = clockMs()
      connectNow = true
      nextRetryAtMs = -1L
      policy.resetBackoff()
      wakes.trySend(Unit)
      if (loop?.isActive != true) startLoop()
    }
    publishIncident("reconnect", true)
    return true
  }

  /**
   * A pause or auth/expired flag that is not a hard stop. Clears it and starts an attempt.
   * Does not touch pairing or Room. A user disconnect and a hard stop stay stopped.
   */
  private fun releaseRecoverableLatch(): Boolean {
    if (stopped || isHardStop(terminalKind)) return false
    if (!policy.paused && !isTransientTerminal(terminalKind)) return false
    if (isTransientTerminal(terminalKind)) {
      terminal = false
      terminalKind = ""
    }
    policy.resume()
    connectNow = true
    lastActivityMs = clockMs()
    nextRetryAtMs = -1L
    policy.resetBackoff()
    resumes.trySend(Unit)
    wakes.trySend(Unit)
    if (loop?.isActive != true) startLoop()
    return true
  }

  /** A committed cursor or baseline. A ping does not call this. */
  fun noteCommittedProgress() {
    val now = clockMs()
    lastCommittedProgressMs = now
    connection?.let { current -> if (current.committedAtMs < 0L) current.committedAtMs = now }
    publishIncident("", false)
  }

  fun exportIncident(): String {
    val snapshot = captureIncident("export")
    val text = redactDiagnostic(formatIncident(snapshot), secretValues())
    diagnostic(text)
    incidentState.value = snapshot
    recordIncident?.invoke(snapshot, secretValues())
    return text
  }

  private suspend fun readUntilClose(epoch: Int): ReadEnd {
    val context = connection ?: return ReadEnd.PeerClosed
    val current = context.socket
    if (epochCounter.get() != epoch || activeGeneration != context.generation || link !== current) return ReadEnd.PeerClosed
    for (frame in stagedOpening) context.writer.offerControl(frame)
    stagedOpening = emptyList()
    val listener = { noteClock(epoch, context) }
    clock.addListener(listener)
    val adopted = CompletableDeferred<Unit>()
    try {
      try {
        coroutineScope {
          // Adopt before any queued frame is applied. Serving may already be reading.
          val adopting = launch {
            val target = awaitApplier()
            if (target != null && epochCounter.get() == epoch && activeGeneration == context.generation) {
              target.adoptConnection(context.generation)
            }
            adopted.complete(Unit)
          }
          val lane = Any()
          val writing = launch { serviceWriter(epoch, context, lane) }
          val serving = launch { serviceLink(epoch, context) }
          val watchdog = launch {
            while (coroutineContext[Job]?.isActive != false && epochCounter.get() == epoch) {
              delay(1_000L)
              if (writeStuck() || inboundIsDead(context) || deliveryStalled(context)) noteReadEnd(epoch, ReadEnd.Dead, context)
            }
          }
          val applying = launch {
            adopted.await()
            while (coroutineContext[Job]?.isActive != false) {
              val event = context.events.receive()
              val target = applier ?: continue
              // A Room commit already started must finish. The next baseline waits for this join.
              withContext(NonCancellable) { target.offer(event, context.generation) }
            }
          }
          val framing = launch {
            adopted.await()
            for (frame in context.syncFrames) {
              trace("sync frame ${frame::class.simpleName}")
              val target = applier ?: continue
              withContext(NonCancellable) { target.offerFrame(frame, context.generation) }
            }
          }
          val refusing = launch {
            adopted.await()
            for (event in context.refusedEvents) {
              val target = applier ?: continue
              withContext(NonCancellable) { target.noteRefused(event, context.generation) }
            }
          }
          try {
            serving.join()
          } finally {
            adopting.cancel()
            writing.cancel()
            watchdog.cancel()
            applying.cancel()
            framing.cancel()
            refusing.cancel()
            if (!adopted.isCompleted) adopted.cancel()
            // A blocked write is not a suspension point. Closing the socket unblocks it
            // before this scope waits for the writer.
            closeOwned(current)
          }
          listOf(adopting, writing, watchdog, applying, framing, refusing).forEach { child ->
            try {
              child.join()
            } catch (error: CancellationException) {
              // The socket owner finished. The other lanes are stopped with it.
              // NonCancellable commits have already returned.
            }
          }
        }
      } catch (error: CancellationException) {
        if (coroutineContext[Job]?.isActive == false) throw error
        if (context.outcome == ReadEnd.Continue) noteReadEnd(epoch, ReadEnd.WorkerFailed, context)
      } catch (error: Exception) {
        if (context.outcome == ReadEnd.Continue) noteReadEnd(epoch, ReadEnd.WorkerFailed, context)
      }
      return context.outcome
    } finally {
      clock.removeListener(listener)
      // Children have joined, so a commit that held the applier lock has finished.
      // Drop what that generation did not commit before another socket can adopt.
      val retiring = applier
      if (retiring != null) {
        withContext(NonCancellable) { retiring.retireConnection(context.generation) }
      }
      failQueued(context.generation)
      context.abandon()
      if (writer === context.writer) writer = null
      if (connection === context) {
        connection = null
        if (activeGeneration == context.generation) activeGeneration = 0
      }
      closeOwned(current)
    }
  }

  private suspend fun awaitApplier(): LinkApplier? {
    applier?.let { return it }
    while (coroutineContext[Job]?.isActive != false) {
      applierReady.receive()
      applier?.let { return it }
    }
    return null
  }

  private fun noteClock(epoch: Int, context: PhysicalConnection) {
    if (writeStuck() || deliveryStalled(context)) {
      noteReadEnd(epoch, ReadEnd.Dead, context)
      return
    }
    noteHeartbeat(epoch, context)
  }

  /** Live, and no committed cursor or baseline for the sync budget. A ping is not progress. */
  private fun deliveryStalled(context: PhysicalConnection): Boolean {
    if (context.committedAtMs >= 0L || context.events.shouldPauseRead()) return false
    noteLive(context)
    val started = context.liveAtMs
    if (started < 0L) return false
    return clockMs() - started >= computing.michell.monitor.data.SyncRecoveryBudgetMs
  }

  private fun noteLive(context: PhysicalConnection) {
    if (context.liveAtMs >= 0L) return
    val phase = session.phase
    if (phase != computing.michell.monitor.protocol.SessionPhase.Live &&
      phase != computing.michell.monitor.protocol.SessionPhase.Busy) return
    context.liveAtMs = clockMs()
  }

  private fun writeStuck(): Boolean {
    val started = writeStartedNanos
    if (started == 0L) return false
    val elapsed = clock.nanoTime() - started
    return elapsed / 1_000_000L >= MonitorLimits.DeadSessionMs
  }

  private fun noteHeartbeat(epoch: Int, context: PhysicalConnection) {
    if (epochCounter.get() != epoch || activeGeneration != context.generation) return
    val now = clockMs()
    val step = heartbeatStep(context.lastSentMs, context.lastReceivedMs, now)
    val due = if (context.events.shouldPauseRead()) heartbeatWhileCreditPaused(step, context.lastSentMs, now) else step
    when (due) {
      HeartbeatStep.Close -> noteReadEnd(epoch, ReadEnd.Dead, context)
      HeartbeatStep.Ping -> {
        val ping = encodeTicks(MessageKind.Ping, newId(), now)
        val frame = tryEncodeFrame(ping)
        if (frame.ok && context.writer.offerControl(frame.bytes)) context.lastSentMs = now
        else noteReadEnd(epoch, ReadEnd.WriteFailed, context)
      }
      HeartbeatStep.None -> {}
    }
  }
  private fun clockMs(): Long = clock.nanoTime() / 1_000_000L

  /**
   * The only socket writer. Offers wake [ConnectionWriter.run]; this call does not
   * read. Closing the socket unblocks a write that is not a suspension point.
   */
  private suspend fun serviceWriter(epoch: Int, context: PhysicalConnection, lane: Any) {
    writeLane = lane
    try {
      val wrote = context.writer.run { frame ->
        if (context.outcome != ReadEnd.Continue) return@run false
        if (epochCounter.get() != epoch || activeGeneration != context.generation) return@run false
        val ok = writeBytes(frame, context.socket, lane)
        if (ok) noteSocketWrite(frame)
        ok
      }
      if (!wrote && context.outcome == ReadEnd.Continue) noteReadEnd(epoch, ReadEnd.WriteFailed, context)
    } finally {
      if (writeLane === lane) writeLane = null
    }
  }

  /** The reader. Outbound frames are not polled here; the writer wakes on its queues. */
  private suspend fun serviceLink(epoch: Int, context: PhysicalConnection): ReadEnd {
    val outbound = context.writer
    val buffer = ByteArray(FrameAssembler.ReadChunkBytes)
    val reader = FrameAssembler()
    while (coroutineContext[Job]?.isActive != false && !stopped && epochCounter.get() == epoch &&
      activeGeneration == context.generation) {
      if (replaceLink) {
        replaceLink = false
        return finishRead(epoch, context, ReadEnd.PeerClosed)
      }
      if (leftForBackground) {
        // The bye is already on the control lane. Wait until the writer has taken it.
        withTimeoutOrNull(BackgroundByeMs) { outbound.awaitDrained() }
        return finishRead(epoch, context, ReadEnd.Background)
      }
      if (!context.setupComplete && clockMs() - context.openedAtMs >= SessionSetupMs) {
        return finishRead(epoch, context, ReadEnd.Dead)
      }
      if (inboundIsDead(context) || writeStuck() || deliveryStalled(context)) return finishRead(epoch, context, ReadEnd.Dead)
      if (context.events.shouldPauseRead()) {
        delay(50)
        noteHeartbeat(epoch, context)
        continue
      }
      val count = readOnce(context, buffer)
      if (context.outcome != ReadEnd.Continue) return finishRead(epoch, context, context.outcome)
      if (count < 0) return finishRead(epoch, context, ReadEnd.PeerClosed)
      // Partial-frame age is a duration on this clock, not civil time.
      val now = clockMs()
      if (count > 0) {
        val batch = reader.offer(buffer, 0, count, now)
        for (frame in batch.frames) {
          noteInbound(context)
          onFrame(frame, epoch, context)
          if (context.outcome != ReadEnd.Continue) return finishRead(epoch, context, context.outcome)
        }
        if (batch.status != FrameStatus.Ok) return finishRead(epoch, context, ReadEnd.PeerClosed)
      }
      if (reader.partialExpired(now)) return finishRead(epoch, context, ReadEnd.PeerClosed)
      if (inboundIsDead(context) || writeStuck() || deliveryStalled(context)) return finishRead(epoch, context, ReadEnd.Dead)
      if (epochCounter.get() != epoch || activeGeneration != context.generation) {
        return finishRead(epoch, context, ReadEnd.PeerClosed)
      }
      noteHeartbeat(epoch, context)
      if (context.outcome != ReadEnd.Continue) return finishRead(epoch, context, context.outcome)
    }
    return finishRead(epoch, context, ReadEnd.PeerClosed)
  }

  internal fun outboundWakeCount(): Long = connection?.writer?.wakeCount ?: 0L

  internal fun outboundPending(): Int = connection?.writer?.pendingFrames() ?: 0

  private fun readOnce(context: PhysicalConnection, buffer: ByteArray): Int {
    return try {
      context.socket.input.read(buffer)
    } catch (error: CancellationException) {
      throw error
    } catch (error: Exception) {
      if (isReadTimeout(error)) 0
      else {
        if (context.outcome == ReadEnd.Continue) {
          val detail = error.message ?: "Read failed."
          publishCurrent(epochCounter.get(), LinkPhase.Disconnected, detail, detail)
        }
        -1
      }
    }
  }

  private suspend fun onFrame(frame: MonitorFrame, epoch: Int, context: PhysicalConnection) {
    if (epochCounter.get() != epoch || activeGeneration != context.generation) return
    val owned = context.socket
    val outbound = context.writer
    frameProbe?.invoke(frame)
    // Any accepted frame ends the opening budget, including a sync event.
    context.setupComplete = true
    val sync = decodeSyncEnvelope(frame.json)
    if (sync is SyncFrame.Event) {
      session.noteSyncTraffic()
      when (context.events.offer(sync.event, sync.wireBytes)) {
        CreditOffer.Rejected -> {
          if (!context.refusedEvents.trySend(sync.event).isSuccess) noteReadEnd(epoch, ReadEnd.Retry, context)
        }
        CreditOffer.Queued, CreditOffer.Held -> {}
      }
      if (session.phase == computing.michell.monitor.protocol.SessionPhase.Live) publishCurrent(epoch, LinkPhase.Live, "", "")
      noteLive(context)
      return
    }
    if (sync != null && sync !is SyncFrame.RevisionChanged) {
      session.noteSyncTraffic()
      if (!context.syncFrames.trySend(sync).isSuccess) noteReadEnd(epoch, ReadEnd.Retry, context)
      if (session.phase == computing.michell.monitor.protocol.SessionPhase.Live) publishCurrent(epoch, LinkPhase.Live, "", "")
      return
    }
    if (sync is SyncFrame.RevisionChanged && !context.syncFrames.trySend(sync).isSuccess) {
      noteReadEnd(epoch, ReadEnd.Retry, context)
    }
    val envelope = tryDecodeEnvelope(frame)
    if (!envelope.ok) return
    val message = context.chunks.accept(envelope.message) ?: return
    session.apply(message)
    noteLive(context)
    when (message.kind) {
      MessageKind.PairOk -> {
        val paired = (message.inbound as? InboundPayload.PairOk)?.value ?: decodePairOk(message.payloadJson)
        if (paired != null) {
          store.savePairing(paired.clientId, paired.sessionToken)
          val presented = normalizeFingerprint(owned.peerFingerprint)
          if (presented.length == 64) store.save(store.load().copy(fingerprint = presented))
          pairCode = ""
          // First pair has no Room row. One resume, owned here, not by the screen.
          resumeFromRoom("", "", 0L)
        }
      }
      MessageKind.HelloOk -> {
        val hello = (message.inbound as? InboundPayload.HelloOk)?.value ?: decodeHelloOk(message.payloadJson)
        val record = store.load()
        if (hello != null && record.paired) {
          val mac = authMac(record.sessionToken, hello.nonce)
          session.noteOutbound(MessageKind.Auth)
          if (mac.isNotEmpty()) offerControl(encodeAuth(newId(), record.clientId, mac), owned, outbound)
          // The screen asks for the one resume after hello. Do not write a second here.
        }
      }
      MessageKind.CommandStates -> {
        val states = decodeCommandStates(message.payloadJson) ?: return
        applyHostStates(states.map { HostCommandState(it.ref, it.state, it.reason) }, context)
      }
      MessageKind.CommandState -> {
        val one = decodeCommandState(message.payloadJson) ?: return
        applyHostStates(listOf(HostCommandState(one.ref, one.state, one.reason)), context)
      }
      MessageKind.Ping -> {
        val ticks = decodeTicks(message.payloadJson)?.ticks ?: 0L
        if (!offerControl(encodeTicks(MessageKind.Pong, newId(), ticks), owned, outbound)) noteReadEnd(epoch, ReadEnd.WriteFailed, context)
      }
      MessageKind.Bye -> {
        val bye = decodeBye(message.payloadJson)
        if (bye?.reason == "replaced") {
          val saved = store.load().clientId
          if (retriesReplacedBye(openingNow || replaceLink, holdingReplacement, saved, replacementClientId)) {
            // This session opened the next socket. The desktop's replaced bye is our own takeover.
            noteReadEnd(epoch, ReadEnd.PeerClosed, context)
          } else {
            noteReadEnd(epoch, ReadEnd.Rejected, context)
            publishCurrent(epoch, LinkPhase.Paused, "Paired elsewhere", bye.reason, "replaced")
          }
        } else if (bye?.reason == "reconnected") {
          // Same client took a new socket. Retry; do not treat it as paired elsewhere.
          noteReadEnd(epoch, ReadEnd.PeerClosed, context)
        } else if (bye?.reason == "disabled" || bye?.reason == "revoked") {
          noteReadEnd(epoch, ReadEnd.Disabled, context)
          markTerminal(bye.reason, bye.reason)
          // Disabled keeps the host-closed banner. Revocation stays a distinct reason.
          val shown = if (bye.reason == "revoked") bye.reason else HostClosedBanner
          publishCurrent(epoch, LinkPhase.Paused, shown, bye.reason, bye.reason)
        }
      }
      MessageKind.Rejected -> {
        pairCode = ""
        val reason = message.reason
        // A saved pairing is not discarded, and a truncated close is not an
        // authentication failure. auth, expired, busy, an empty reason, and
        // protocol back off. Revocation, disable, pin, and pair code still pause.
        if (retriesTransientReject(store.load().paired, reason)) {
          noteReadEnd(epoch, ReadEnd.Retry, context)
          publishCurrent(epoch, LinkPhase.Connecting, ReconnectingBanner, reason, reason.ifEmpty { "rejected" })
        } else {
          noteReadEnd(epoch, ReadEnd.Rejected, context)
          val kind = if (isUserActionReject(reason)) terminalKindOf(reason) else ""
          if (kind.isNotEmpty()) markTerminal(kind, reason.ifEmpty { kind })
          val shown = reason.ifEmpty { HostClosedBanner }
          publishCurrent(epoch, LinkPhase.Paused, shown, reason, kind.ifEmpty { "rejected" })
        }
      }
      else -> publishCurrent(epoch, if (session.phase == computing.michell.monitor.protocol.SessionPhase.Live ||
        session.phase == computing.michell.monitor.protocol.SessionPhase.Busy) LinkPhase.Live else LinkPhase.Connecting, "", "")
    }
    // Auth is written here, before the screen sees hello. The screen still owns the Room resume.
    // A dropped essential frame is not left half-applied: the link recovers and hello runs again.
    if (activeGeneration != context.generation || link !== context.socket) return
    val delivered = inbound.publish(message)
    if (delivered == DeliveryResult.Dropped && isEssentialDelivery(message.kind)) {
      noteReadEnd(epoch, ReadEnd.Retry, context)
    }
  }

  private fun offerControl(json: String, owned: TlsLink, outbound: ConnectionWriter): Boolean {
    val context = connection
    if (context == null || owned !== link || owned !== context.socket || outbound !== context.writer) return false
    if (activeGeneration != context.generation) return false
    val frame = tryEncodeFrame(json)
    if (!frame.ok) return false
    return outbound.offerControl(frame.bytes)
  }

  private fun offerCommand(json: String, owned: TlsLink): Boolean {
    val context = connection
    val outbound = writer
    // Setup and teardown have no writer. Do not touch the socket from this caller.
    if (context == null || outbound == null || owned !== link || owned !== context.socket) return false
    if (activeGeneration != context.generation) return false
    val frame = tryEncodeFrame(json)
    if (!frame.ok) return false
    if (!outbound.offerCommand(frame.bytes)) return false
    val commandId = catalogueCommandId(json)
    if (commandId.isNotEmpty()) trackQueued(commandId, context.generation, frame.bytes)
    return true
  }

  private fun writeJson(json: String, owned: TlsLink? = link): Boolean {
    val frame = tryEncodeFrame(json)
    if (!frame.ok) return false
    val target = owned ?: return false
    return writeBeforeOwner(frame.bytes, target)
  }

  /** A bye before the service coroutine starts. Refuses once that coroutine owns the lane. */
  private fun writeBeforeOwner(bytes: ByteArray, owned: TlsLink): Boolean {
    return writeSocket(bytes, owned) { writeLane == null }
  }

  private fun writeBytes(bytes: ByteArray, owned: TlsLink, lane: Any): Boolean {
    return writeSocket(bytes, owned) { writeLane === lane }
  }

  private fun writeSocket(bytes: ByteArray, owned: TlsLink, allowed: () -> Boolean): Boolean {
    synchronized(writeLock) {
      if (!allowed()) return false
      val context = connection
      if (context != null && context.socket !== owned) return false
      writeStartedNanos = clock.nanoTime()
      return try {
        owned.output.write(bytes)
        owned.output.flush()
        val sent = clockMs()
        if (context != null && context.socket === owned) context.lastSentMs = sent
        true
      } catch (error: Exception) {
        false
      } finally {
        writeStartedNanos = 0L
      }
    }
  }

  private fun noteReadEnd(epoch: Int, end: ReadEnd, context: PhysicalConnection) {
    if (end == ReadEnd.Continue) return
    if (epochCounter.get() != epoch || activeGeneration != context.generation) return
    if (context.closeOutcome(end)) {
      workerExit = end.name
      closeOwned(context.socket)
    }
  }

  private fun finishRead(epoch: Int, context: PhysicalConnection, end: ReadEnd): ReadEnd {
    noteReadEnd(epoch, end, context)
    return context.outcome
  }

  private fun noteInbound(context: PhysicalConnection) {
    context.lastInboundNanos = clock.nanoTime()
    context.lastReceivedMs = clockMs()
  }

  private fun inboundIsDead(context: PhysicalConnection): Boolean {
    if (context.events.shouldPauseRead()) return false
    val delta = clock.nanoTime() - context.lastInboundNanos
    if (delta <= 0L) return false
    return delta / 1_000_000L >= MonitorLimits.DeadSessionMs
  }

  /** Bytes are still coming, or we stopped reading so they can sit in TCP. */
  fun framesArriving(): Boolean {
    val context = connection ?: return false
    if (link == null) return false
    if (context.events.shouldPauseRead()) return true
    val quiet = clock.nanoTime() - context.lastInboundNanos
    if (quiet <= 0L) return true
    return quiet / 1_000_000L < MonitorLimits.DeadSessionMs
  }

  private fun publishCurrent(epoch: Int, phase: LinkPhase, banner: String, error: String, transition: String = "") {
    if (epochCounter.get() != epoch) return
    publish(phase, banner, error, transition)
  }

  private fun publish(phase: LinkPhase, banner: String, error: String, transition: String = "", clearFailure: Boolean = false) {
    val current = statusState.value
    val failure = if (clearFailure) "" else nextFailureReason(current.failureReason, phase, banner, error)
    val nextError = if (error.isEmpty()) current.lastError else error
    val changed = current.phase != phase || current.banner != banner || current.failureReason != failure ||
      current.lastError != nextError
    statusState.value = current.copy(
      phase = phase,
      banner = banner,
      draft = promptDraft,
      lastError = nextError,
      failureReason = failure
    )
    if (changed || transition.isNotEmpty()) publishIncident(transition, changed || transition.isNotEmpty())
  }

  private fun closeLink() {
    val context = connection
    val generation = context?.generation ?: 0
    connection = null
    activeGeneration = 0
    writer = null
    writeStartedNanos = 0L
    val owned = link
    link = null
    sentResumeGeneration = -1
    sentResumeConversation = ""
    sentResumeStream = ""
    sentResumeSeq = -1L
    if (generation != 0) failQueued(generation)
    context?.abandon()
    closeOwned(owned)
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

  private fun markTerminal(kind: String, reason: String) {
    terminal = true
    terminalKind = kind
    if (reason.isNotEmpty()) {
      val current = statusState.value
      statusState.value = current.copy(failureReason = reason, lastError = reason)
    }
  }

  private fun trackQueued(commandId: String, epoch: Int, bytes: ByteArray) {
    synchronized(queuedLock) { queuedCommands.add(QueuedCommand(commandId, epoch, bytes)) }
    emitResult(CatalogueResult(commandId, epoch, CatalogueWrite.Queued))
  }

  private fun noteSocketWrite(bytes: ByteArray) {
    val found = synchronized(queuedLock) {
      val index = queuedCommands.indexOfFirst { it.bytes === bytes }
      if (index < 0) return
      queuedCommands.removeAt(index)
    }
    scope.launch {
      ledger.noteWritten(found.commandId)
      emitResult(CatalogueResult(found.commandId, found.epoch, CatalogueWrite.Written))
    }
  }

  private fun failQueued(epoch: Int) {
    val dropped = synchronized(queuedLock) {
      val mine = queuedCommands.filter { it.epoch == epoch }
      queuedCommands.removeAll { it.epoch == epoch }
      mine
    }
    for (row in dropped) emitResult(CatalogueResult(row.commandId, row.epoch, CatalogueWrite.Failed))
  }

  private fun emitResult(result: CatalogueResult) {
    if (commandResultsChannel.trySend(result).isSuccess) return
    scope.launch { commandResultsChannel.send(result) }
  }

  private fun trace(text: String) {
    val clean = redactDiagnostic(text, secretValues())
    if (clean.isNotEmpty()) diagnostic(clean)
  }

  private fun secretValues(): List<String> {
    val record = store.load()
    return listOf(record.sessionToken, pairCode, promptDraft)
  }

  private fun captureIncident(transition: String): IncidentSnapshot {
    val now = clockMs()
    val context = connection
    val receivedAge = if (context == null) -1L else now - context.lastReceivedMs
    val progressAge = if (lastCommittedProgressMs < 0L) -1L else now - lastCommittedProgressMs
    val outbound = context?.writer?.pendingByteCount() ?: 0L
    val inbound = context?.events?.pressureBytes ?: 0L
    val shown = statusState.value
    return IncidentSnapshot(
      loopGeneration = epochCounter.get(),
      socketGeneration = activeGeneration,
      phase = shown.phase.name,
      banner = shown.banner,
      transitionReason = transition.ifEmpty { transitionReason },
      failureReason = shown.failureReason,
      attemptCount = attemptCount,
      nextRetryAtMs = nextRetryAtMs,
      nowMs = now,
      monitoringDemand = monitoringDemand,
      networkIdentity = lanRoute?.identity ?: "",
      lastReceivedFrameAgeMs = receivedAge,
      lastCommittedProgressAgeMs = progressAge,
      queueBytes = outbound + inbound,
      outboundBytes = outbound,
      inboundBytes = inbound,
      workerExit = workerExit,
      terminalKind = terminalKind,
      opening = openingNow,
      ioBlocked = openingNow || writeStuck(),
      framesArriving = framesArriving(),
      stopped = stopped,
      paused = policy.paused,
      armed = armed,
      reconnectable = reconnectable,
      socketAgeMs = if (context == null) -1L else now - context.openedAtMs
    )
  }

  private fun publishIncident(transition: String, log: Boolean) {
    if (transition.isNotEmpty()) transitionReason = transition
    val previous = incidentState.value
    val snapshot = captureIncident(transitionReason)
    incidentState.value = snapshot
    if (log || snapshot.posture != previous.posture) trace(formatIncident(snapshot))
    val changed = previous.phase != snapshot.phase || previous.posture != snapshot.posture ||
      previous.failureReason != snapshot.failureReason
    if (changed) recordIncident?.invoke(snapshot, secretValues())
  }
}

private class QueuedCommand(val commandId: String, val epoch: Int, val bytes: ByteArray)

/**
 * A replaced bye is our own next socket when we are opening or holding it, or when
 * the client id we started that replacement with is still the saved one.
 * A different client, with no local reconnect, is not this.
 */
internal fun retriesReplacedBye(
  openingNext: Boolean,
  holdingReplacement: Boolean,
  savedClientId: String,
  replacementClientId: String
): Boolean {
  if (openingNext || holdingReplacement) return true
  return replacementClientId.isNotEmpty() && replacementClientId == savedClientId
}

/** Revocation, disable, a bad pin, and a refused pair code need the user. */
internal fun isUserActionReject(reason: String): Boolean {
  return reason == "revoked" || reason == "disabled" || reason == "fingerprint" || reason == "pair_code"
}

/**
 * A paired session can try these again. They are not stored as a terminal
 * authentication failure, and an empty reason is a truncated close, not auth.
 * busy retries even before pairing. An unpaired auth reject still pauses.
 */
internal fun retriesTransientReject(paired: Boolean, reason: String): Boolean {
  if (isUserActionReject(reason)) return false
  if (reason == "busy") return true
  if (!paired) return false
  return reason == "auth" || reason == "expired" || reason.isEmpty() || reason == "protocol"
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

private fun isStaleLanRoute(error: Throwable): Boolean {
  var current: Throwable? = error
  while (current != null) {
    if (current is LanRouteUnavailable) return true
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

internal const val ConnectTimeoutMs = 10_000
internal const val HandshakeTimeoutMs = 10_000
internal const val SessionSetupMs = 15_000
internal const val ReadTimeoutMs = 1_000
private const val BackgroundByeMs = 500L
private const val OpenBudgetMs = 25_000L
private const val PredecessorJoinMs = 2_000L
private const val HexDigits = "0123456789abcdef"
