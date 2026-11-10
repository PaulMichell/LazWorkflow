package computing.michell.monitor.connection

/* Reader, writer, and heartbeat for one monitor socket (c) 2026 Michell Computing.

   The session thread is the only caller of the socket streams. It polls one
   frame here, control before commands before acks. Ping is answered on the
   control lane. 30 s with nothing received closes the link. */

import computing.michell.monitor.protocol.MonitorEvent
import computing.michell.monitor.protocol.MonitorLimits
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ClosedReceiveChannelException
import kotlinx.coroutines.isActive
import kotlinx.coroutines.selects.select
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.Job

/** Unacknowledged event JSON the phone will hold before it closes and resumes. */
const val InboundCreditBytes = 512 * 1024

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

class ConnectionWriter(private val write: suspend (ByteArray) -> Boolean) {
  private val control = Channel<ByteArray>(Channel.UNLIMITED)
  private val commands = Channel<ByteArray>(Channel.UNLIMITED)
  private val acks = Channel<ByteArray>(Channel.UNLIMITED)

  fun offerControl(bytes: ByteArray): Boolean = control.trySend(bytes).isSuccess

  fun offerCommand(bytes: ByteArray): Boolean = commands.trySend(bytes).isSuccess

  fun offerAck(bytes: ByteArray): Boolean = acks.trySend(bytes).isSuccess

  /** One frame, or null. Does not wait. Control beats a command, which beats an ack. */
  fun poll(): ByteArray? {
    return control.tryReceive().getOrNull()
      ?: commands.tryReceive().getOrNull()
      ?: acks.tryReceive().getOrNull()
  }

  fun close() {
    control.close()
    commands.close()
    acks.close()
  }

  suspend fun run(): Boolean {
    while (coroutineContext[Job]?.isActive != false) {
      val ready = control.tryReceive().getOrNull()
        ?: commands.tryReceive().getOrNull()
        ?: acks.tryReceive().getOrNull()
      val frame = ready ?: receiveNext() ?: return true
      if (!write(frame)) return false
    }
    return true
  }

  private suspend fun receiveNext(): ByteArray? {
    return try {
      select {
        control.onReceive { it }
        commands.onReceive { it }
        acks.onReceive { it }
      }
    } catch (error: ClosedReceiveChannelException) {
      null
    }
  }
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

  /** A full window holds the event. It is not queued, so it is not acked. */
  fun offer(event: MonitorEvent, bytes: Int): CreditOffer {
    if (bytes < 0) return CreditOffer.Rejected
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
