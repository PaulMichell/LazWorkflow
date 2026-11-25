package computing.michell.monitor.net

/* One pulse coroutine. No pause flag, no terminal flag, no replaced latch.
   (c) 2026 Michell Computing.

   A second phone has its own token; this loop does not stop because another
   client is watching. Backoff is 1, 2, 4 and 8 seconds with jitter, then
   15 seconds. A touch, a foreground return, a Wi-Fi change or Reconnect
   cancels that wait. Unpaired, pin mismatch and Stopped do not retry until
   a new pairing, an accepted pin, or start(). */

import java.util.concurrent.Executors
import java.util.concurrent.ThreadLocalRandom
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.HttpUrl

const val ConnectedWindowMs = 20_000L
const val PulseRetryCapMs = 15_000L
const val PulseIntervalDefaultMs = 250L
const val PulseIntervalMinMs = 150L
const val PulseIntervalMaxMs = 10_000L

private val PulseRetryBases = longArrayOf(1_000L, 2_000L, 4_000L, 8_000L, PulseRetryCapMs)

/** Equal jitter in [base/2, base]. Roll 999 returns the base. 15 seconds is not jittered. */
fun jitteredPulseDelayMs(baseMs: Long, roll: Int): Long {
  if (baseMs >= PulseRetryCapMs) return PulseRetryCapMs
  if (baseMs <= 1L) return baseMs
  val half = baseMs / 2L
  val unit = Math.floorMod(roll, 1000)
  return half + (half * unit) / 999L
}

/** Failure 0 waits 1 second, then 2, 4, 8, and 15 seconds. */
fun pulseRetryDelayMs(failureIndex: Int, roll: Int): Long {
  val index = failureIndex.coerceAtLeast(0).coerceAtMost(PulseRetryBases.lastIndex)
  return jitteredPulseDelayMs(PulseRetryBases[index], roll)
}

sealed class LinkState {
  data object Stopped : LinkState()
  data object Unpaired : LinkState()
  data object PinMismatch : LinkState()
  data class Connected(val at: Long) : LinkState()
  data class Retrying(val nextAttemptAt: Long) : LinkState()
}

data class PulseQuery(
  val after: Long,
  val epoch: String,
  val intervalMs: Long,
  val token: String
)

data class PulseMessage(
  val epoch: String,
  val rev: Long,
  val json: String,
  val at: Long
)

sealed class PulseFetch {
  data class Ok(val epoch: String, val rev: Long, val json: String) : PulseFetch()
  data class Status(val code: Int) : PulseFetch()
  data class Unauthorized(val code: Int) : PulseFetch()
  data object TimedOut : PulseFetch()
  data object Reset : PulseFetch()
  data object PinMismatch : PulseFetch()
}

fun interface PulseSource {
  fun fetch(query: PulseQuery): PulseFetch
}

interface PulseClock {
  fun now(): Long
  fun wake()
  fun delayUntil(deadline: Long, cancel: () -> Boolean)
}

class SystemPulseClock : PulseClock {
  private val lock = ReentrantLock()
  private val arrived = lock.newCondition()

  override fun now(): Long = System.currentTimeMillis()

  override fun wake() {
    lock.withLock { arrived.signalAll() }
  }

  override fun delayUntil(deadline: Long, cancel: () -> Boolean) {
    lock.withLock {
      while (!cancel() && now() < deadline) {
        val left = deadline - now()
        if (left <= 0L) return
        arrived.await(left.coerceAtMost(50L), TimeUnit.MILLISECONDS)
      }
    }
  }
}

/** Test clock. Time moves only when [advanceTo] is called. */
class VirtualClock(start: Long = 0L) : PulseClock {
  private val lock = ReentrantLock()
  private val arrived = lock.newCondition()
  private var time = start

  override fun now(): Long = lock.withLock { time }

  fun advance(ms: Long) {
    advanceTo(now() + ms)
  }

  fun advanceTo(at: Long) {
    lock.withLock {
      if (at > time) time = at
      arrived.signalAll()
    }
  }

  override fun wake() {
    lock.withLock { arrived.signalAll() }
  }

  override fun delayUntil(deadline: Long, cancel: () -> Boolean) {
    lock.withLock {
      while (!cancel() && time < deadline) arrived.await(5, TimeUnit.MILLISECONDS)
    }
  }
}

class PulseLoop(
  private val source: PulseSource,
  private val clock: PulseClock = SystemPulseClock(),
  private val roll: () -> Int = { ThreadLocalRandom.current().nextInt(1000) }
) : AutoCloseable {
  private val states = MutableStateFlow<LinkState>(LinkState.Stopped)
  val state: StateFlow<LinkState> = states.asStateFlow()
  private val pulseFlow = MutableSharedFlow<PulseMessage>(replay = 1, extraBufferCapacity = 8)
  val pulses: SharedFlow<PulseMessage> = pulseFlow.asSharedFlow()

  var intervalMs: Long = PulseIntervalDefaultMs

  private val nudgeCount = AtomicInteger()
  @Volatile private var running = false
  @Volatile private var failureIndex = 0
  @Volatile private var lastPulseAt: Long? = null
  @Volatile private var epoch = ""
  @Volatile private var rev = 0L
  @Volatile private var token = ""
  private val threads = Executors.newFixedThreadPool(2) { runnable ->
    Thread(runnable, "PulseLoop").apply { isDaemon = true }
  }
  private val dispatcher = threads.asCoroutineDispatcher()
  private val scope = CoroutineScope(SupervisorJob() + dispatcher)

  init {
    scope.launch { loop() }
    scope.launch { watchFreshness() }
  }

  fun start() {
    if (states.value is LinkState.Unpaired || states.value is LinkState.PinMismatch) return
    running = true
    if (states.value is LinkState.Stopped) states.value = LinkState.Retrying(clock.now())
    clock.wake()
  }

  fun disconnect() {
    running = false
    if (states.value !is LinkState.Unpaired && states.value !is LinkState.PinMismatch) {
      states.value = LinkState.Stopped
    }
    clock.wake()
  }

  /** Nothing to watch in the background stops the loop. A live run does not. */
  fun background(watching: Boolean) {
    if (watching) return
    disconnect()
  }

  fun touch() = nudge()

  fun foreground() = nudge()

  fun wifiChanged() = nudge()

  fun reconnect() = nudge()

  /** Leaves Unpaired. A pin mismatch stays until [acceptPin]. */
  fun pairedAgain(newToken: String = token) {
    token = newToken
    if (states.value !is LinkState.Unpaired) return
    running = true
    failureIndex = 0
    states.value = LinkState.Retrying(clock.now())
    clock.wake()
  }

  /** Leaves pin mismatch. Unpaired stays until [pairedAgain]. */
  fun acceptPin() {
    if (states.value !is LinkState.PinMismatch) return
    running = true
    failureIndex = 0
    states.value = LinkState.Retrying(clock.now())
    clock.wake()
  }

  override fun close() {
    running = false
    scope.cancel()
    clock.wake()
    dispatcher.close()
    threads.shutdownNow()
  }

  private fun nudge() {
    val phase = states.value
    if (!running || phase is LinkState.Stopped || phase is LinkState.Unpaired || phase is LinkState.PinMismatch) return
    nudgeCount.incrementAndGet()
    clock.wake()
  }

  private fun halted(): Boolean {
    if (!running) return true
    return states.value is LinkState.Unpaired || states.value is LinkState.PinMismatch
  }

  private fun loop() {
    while (scope.isActive) {
      if (halted()) {
        clock.delayUntil(Long.MAX_VALUE) { !halted() }
        continue
      }
      val seen = nudgeCount.get()
      val result = try {
        source.fetch(PulseQuery(rev, epoch, intervalMs.coerceIn(PulseIntervalMinMs, PulseIntervalMaxMs), token))
      } catch (error: kotlinx.coroutines.CancellationException) {
        throw error
      } catch (error: Exception) {
        classifyPulseFailure(error)
      }
      val waitUntil = apply(clock.now(), result) ?: continue
      clock.delayUntil(waitUntil) { nudgeCount.get() != seen || halted() }
    }
  }

  private fun watchFreshness() {
    while (scope.isActive) {
      val at = lastPulseAt
      val until = if (at == null || states.value !is LinkState.Connected) Long.MAX_VALUE else at + ConnectedWindowMs + 1L
      clock.delayUntil(until) { lastPulseAt != at || states.value !is LinkState.Connected }
      val pulseAt = lastPulseAt ?: continue
      if (states.value is LinkState.Connected && clock.now() - pulseAt > ConnectedWindowMs) {
        states.value = LinkState.Retrying(clock.now())
      }
    }
  }

  private fun apply(now: Long, result: PulseFetch): Long? {
    when (result) {
      is PulseFetch.Ok -> {
        failureIndex = 0
        lastPulseAt = now
        if (result.epoch.isNotEmpty()) epoch = result.epoch
        rev = result.rev
        states.value = LinkState.Connected(now)
        pulseFlow.tryEmit(PulseMessage(epoch, rev, result.json, now))
        return null
      }
      is PulseFetch.Unauthorized -> {
        running = false
        states.value = LinkState.Unpaired
        return null
      }
      PulseFetch.PinMismatch -> {
        running = false
        states.value = LinkState.PinMismatch
        return null
      }
      PulseFetch.TimedOut, PulseFetch.Reset, is PulseFetch.Status -> {
        val at = now + pulseRetryDelayMs(failureIndex, roll())
        failureIndex += 1
        states.value = LinkState.Retrying(at)
        return at
      }
    }
  }
}

fun classifyPulseFailure(error: Throwable): PulseFetch {
  if (namedPinError(error) != null) return PulseFetch.PinMismatch
  val text = generateSequence(error) { it.cause }.joinToString(" ") { it.message.orEmpty() }.lowercase()
  if ("reset" in text || "broken pipe" in text || "connection abort" in text) return PulseFetch.Reset
  return PulseFetch.TimedOut
}

fun requestPulse(client: OkHttpClient, url: HttpUrl, query: PulseQuery): PulseFetch {
  val target = url.newBuilder()
    .addPathSegments("v4/pulse")
    .addQueryParameter("after", query.after.toString())
    .addQueryParameter("epoch", query.epoch)
    .addQueryParameter("interval", query.intervalMs.toString())
    .build()
  val builder = Request.Builder().url(target).get()
  if (query.token.isNotEmpty()) builder.header("Authorization", "Bearer ${query.token}")
  return try {
    client.newCall(builder.build()).execute().use { response ->
      when (response.code) {
        401, 403 -> PulseFetch.Unauthorized(response.code)
        in 200..299 -> decodePulse(response.body?.string().orEmpty())
        else -> PulseFetch.Status(response.code)
      }
    }
  } catch (error: Exception) {
    classifyPulseFailure(error)
  }
}

internal fun decodePulse(json: String): PulseFetch.Ok {
  return PulseFetch.Ok(readJsonString(json, "epoch"), readJsonLong(json, "rev"), json)
}

private fun readJsonString(json: String, key: String): String {
  val needle = "\"$key\""
  val keyAt = json.indexOf(needle)
  if (keyAt < 0) return ""
  val colon = json.indexOf(':', keyAt + needle.length)
  if (colon < 0) return ""
  val open = json.indexOf('"', colon + 1)
  if (open < 0) return ""
  val close = json.indexOf('"', open + 1)
  if (close < 0) return ""
  return json.substring(open + 1, close)
}

private fun readJsonLong(json: String, key: String): Long {
  val needle = "\"$key\""
  val keyAt = json.indexOf(needle)
  if (keyAt < 0) return 0L
  val colon = json.indexOf(':', keyAt + needle.length)
  if (colon < 0) return 0L
  var index = colon + 1
  while (index < json.length && json[index].isWhitespace()) index += 1
  val start = index
  while (index < json.length && json[index].isDigit()) index += 1
  if (start == index) return 0L
  return json.substring(start, index).toLongOrNull() ?: 0L
}
