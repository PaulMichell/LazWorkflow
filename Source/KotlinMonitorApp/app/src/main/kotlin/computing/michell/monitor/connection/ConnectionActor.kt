package computing.michell.monitor.connection

/* Reader, writer, and heartbeat for one monitor socket (c) 2026 Michell Computing.

   One writer coroutine owns the socket output. It drains a bounded batch,
   control before commands before acks, then waits. An offer wakes that wait.
   The reader stays on the input stream, so a queued frame does not wait out
   the read timeout. Ping is answered on the control lane. 30 s with nothing
   received closes the link. */

import computing.michell.monitor.protocol.MonitorEvent
import computing.michell.monitor.protocol.MonitorLimits
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.isActive
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.yield

/** Unacknowledged event JSON the phone will hold before it closes and resumes. */
const val InboundCreditBytes = 512 * 1024
/** Snapshot and state frames waiting for the applier. A full queue recovers instead of growing. */
const val SyncFrameQueue = 64
/** Events the credit window refused. A full queue recovers instead of growing. */
const val RefusedEventQueue = 32
/**
 * Frames one wake may write before the writer yields. The yield is a
 * cancellation point during a burst. Control is still taken ahead of a
 * command on every frame, and the reader runs on its own call.
 */
const val OutboundDrainFrames = 8

enum class HeartbeatStep {
  None,
  Ping,
  Close
}

/** Close wins. A ping is due only when this side has been silent. */
fun heartbeatStep(lastSentMs: Long, lastReceivedMs: Long, nowMs: Long): HeartbeatStep {
  if (nowMs - lastReceivedMs >= MonitorLimits.DeadSessionMs) return HeartbeatStep.Close
  if (nowMs - lastSentMs >= MonitorLimits.HeartbeatSilenceMs) return HeartbeatStep.Ping
  return HeartbeatStep.None
}

/**
 * A credit pause stopped the read, so silence is not a dead peer.
 * The control ping is still due. Close stays with the write watchdog.
 */
fun heartbeatWhileCreditPaused(step: HeartbeatStep, lastSentMs: Long, nowMs: Long): HeartbeatStep {
  if (step != HeartbeatStep.Close) return step
  if (nowMs - lastSentMs >= MonitorLimits.HeartbeatSilenceMs) return HeartbeatStep.Ping
  return HeartbeatStep.None
}

class ConnectionWriter(
  capacity: Int = MonitorLimits.OutboundQueue,
  private val write: suspend (ByteArray) -> Boolean
) {
  private val control = Channel<ByteArray>(capacity)
  private val commands = Channel<ByteArray>(capacity)
  private val acks = Channel<ByteArray>(capacity)
  /** Wakes [run] without taking a frame, so the next poll still prefers control. */
  private val wake = Channel<Unit>(Channel.CONFLATED)
  private val drained = Channel<Unit>(Channel.CONFLATED)
  private val pendingLock = Any()
  private var pending = 0
  private var closed = false
  private val wakes = AtomicLong(0)

  /** Times [run] resumed from an empty queue. A burst is one wake, not one per frame. */
  val wakeCount: Long get() = wakes.get()

  internal fun pendingFrames(): Int = pendingCount()

  fun offerControl(bytes: ByteArray): Boolean = offer(control, bytes)

  fun offerCommand(bytes: ByteArray): Boolean = offer(commands, bytes)

  fun offerAck(bytes: ByteArray): Boolean = offer(acks, bytes)

  /** One frame, or null. Does not wait. Control beats a command, which beats an ack. */
  fun poll(): ByteArray? {
    return control.tryReceive().getOrNull()
      ?: commands.tryReceive().getOrNull()
      ?: acks.tryReceive().getOrNull()
  }

  fun close() {
    synchronized(pendingLock) { closed = true }
    control.close()
    commands.close()
    acks.close()
    wake.close()
    drained.trySend(Unit)
  }

  /** Returns when every accepted frame has been written, or the writer has closed. */
  suspend fun awaitDrained() {
    while (pendingCount() > 0 && !isClosed()) {
      drained.receive()
    }
  }

  /**
   * Writes until the queues stay empty. [writeFrame] replaces the constructor
   * callback when the session owns the socket. A full queue is not a busy poll:
   * the wait is the wake channel.
   */
  suspend fun run(writeFrame: suspend (ByteArray) -> Boolean = write): Boolean {
    try {
      while (coroutineContext[Job]?.isActive != false) {
        var sent = 0
        while (sent < OutboundDrainFrames) {
          val ready = poll() ?: break
          val ok = try {
            writeFrame(ready)
          } finally {
            // Count the frame written or abandoned, so a bye flush cannot return early.
            release()
          }
          if (!ok) return false
          sent += 1
        }
        if (pendingCount() > 0) {
          yield()
          continue
        }
        val signaled = wake.receiveCatching()
        if (signaled.isFailure) {
          if (pendingCount() == 0) return true
          continue
        }
        wakes.incrementAndGet()
      }
      return true
    } finally {
      drained.trySend(Unit)
    }
  }

  private fun offer(lane: Channel<ByteArray>, bytes: ByteArray): Boolean {
    synchronized(pendingLock) {
      if (closed) return false
      pending += 1
    }
    if (!lane.trySend(bytes).isSuccess) {
      release()
      return false
    }
    wake.trySend(Unit)
    return true
  }

  private fun release() {
    val empty = synchronized(pendingLock) { releaseLocked() }
    if (empty) drained.trySend(Unit)
  }

  /** Caller holds [pendingLock]. */
  private fun releaseLocked(): Boolean {
    if (pending > 0) pending -= 1
    val empty = pending == 0
    if (empty) drained.trySend(Unit)
    return empty
  }

  private fun pendingCount(): Int = synchronized(pendingLock) { pending }

  private fun isClosed(): Boolean = synchronized(pendingLock) { closed }
}

enum class CreditOffer {
  Queued,
  Held,
  Rejected
}

class AccountedEvents(private val budgetBytes: Long = InboundCreditBytes.toLong()) {
  private val channel = Channel<CountedEvent>(Channel.UNLIMITED)
  private val gate = Any()
  private var queued = 0L
  private val held = ArrayDeque<CountedEvent>()

  val queuedBytes: Long get() = synchronized(gate) { queued }

  /**
   * A full window holds the event. It is not queued, so it is not acked.
   * An event larger than the whole budget is rejected. Holding it would pause reads forever.
   */
  fun offer(event: MonitorEvent, bytes: Int): CreditOffer {
    if (bytes < 0 || bytes > budgetBytes) return CreditOffer.Rejected
    val counted = CountedEvent(event, bytes)
    synchronized(gate) {
      if (held.isNotEmpty() || queued + bytes > budgetBytes) {
        held.addLast(counted)
        return CreditOffer.Held
      }
      queued += bytes
    }
    if (!channel.trySend(counted).isSuccess) {
      synchronized(gate) {
        queued -= bytes
        held.addLast(counted)
      }
      return CreditOffer.Held
    }
    return CreditOffer.Queued
  }

  fun shouldPauseRead(): Boolean = synchronized(gate) { held.isNotEmpty() }

  fun heldEvents(): List<MonitorEvent> = synchronized(gate) { held.map { it.event } }

  suspend fun receive(): MonitorEvent {
    val counted = channel.receive()
    synchronized(gate) {
      queued -= counted.bytes
      admitHeld()
    }
    return counted.event
  }

  fun close() {
    channel.close()
  }

  private fun admitHeld() {
    while (held.isNotEmpty()) {
      val next = held.first()
      if (queued + next.bytes > budgetBytes) return
      held.removeFirst()
      queued += next.bytes
      if (!channel.trySend(next).isSuccess) {
        queued -= next.bytes
        held.addFirst(next)
        return
      }
    }
  }
}

private data class CountedEvent(val event: MonitorEvent, val bytes: Int)
