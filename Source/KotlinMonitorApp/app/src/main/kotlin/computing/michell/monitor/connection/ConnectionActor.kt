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

class AccountedEvents(private val budgetBytes: Long = InboundCreditBytes.toLong()) {
  private val channel = Channel<CountedEvent>(Channel.UNLIMITED)
  private val queued = java.util.concurrent.atomic.AtomicLong(0)
  private val overflow = java.util.concurrent.atomic.AtomicBoolean(false)

  val queuedBytes: Long get() = queued.get()

  /** True when the event is queued, or the window overflowed and a resume is owed. */
  fun offer(event: MonitorEvent, bytes: Int): Boolean {
    if (bytes < 0) return false
    val next = queued.addAndGet(bytes.toLong())
    if (next > budgetBytes) {
      queued.addAndGet(-bytes.toLong())
      overflow.set(true)
      return true
    }
    if (!channel.trySend(CountedEvent(event, bytes)).isSuccess) {
      queued.addAndGet(-bytes.toLong())
      return false
    }
    return true
  }

  suspend fun receive(): MonitorEvent {
    val counted = channel.receive()
    queued.addAndGet(-counted.bytes.toLong())
    return counted.event
  }

  fun close() {
    channel.close()
  }

  fun takeOverflow(): Boolean = overflow.getAndSet(false)
}

private data class CountedEvent(val event: MonitorEvent, val bytes: Int)
