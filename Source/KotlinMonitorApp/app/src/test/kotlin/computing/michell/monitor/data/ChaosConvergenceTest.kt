package computing.michell.monitor.data

/* One thousand seeded TLS iterations against the scripted host (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.FrameAssembler
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.chaos.ChaosCommandId
import computing.michell.monitor.protocol.chaos.ChaosConversationId
import computing.michell.monitor.protocol.chaos.ChaosFinalBody
import computing.michell.monitor.protocol.chaos.ChaosFinalSeq
import computing.michell.monitor.protocol.chaos.ChaosIterations
import computing.michell.monitor.protocol.chaos.ChaosStreamId
import computing.michell.monitor.protocol.chaos.ScriptedTlsHost
import computing.michell.monitor.protocol.chaos.chaosClientContext
import computing.michell.monitor.protocol.chaos.chaosCommandFrame
import computing.michell.monitor.protocol.decodeMonitorEvent
import computing.michell.monitor.protocol.decodeStatusPayload
import computing.michell.monitor.protocol.tryDecodeEnvelope
import java.net.InetAddress
import javax.net.ssl.SSLSocket
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class ChaosConvergenceTest {
  @Test
  fun oneThousandIterationsMatchTheScript() {
    val host = ScriptedTlsHost()
    try {
      for (iteration in 0 until ChaosIterations) {
        host.resetCommands()
        val store = ChaosMemoryStore()
        var clock = 0L
        val applier = SyncApplier("host-1", store, { clock })
        var busy = true
        exchange(host, iteration, false, applier, { clock += 50; clock }, { busy = it })
        if (store.conversation?.seq != ChaosFinalSeq) {
          exchange(host, iteration, true, applier, { clock += 50; clock }, { busy = it })
        }
        runBlocking { applier.tick() }
        assertEquals("iteration $iteration", ChaosFinalSeq, store.conversation?.seq)
        assertEquals(ChaosFinalBody, store.blocks["block-1"]?.body)
        assertEquals(ChaosConversationId, store.conversation?.id)
        assertEquals(ChaosStreamId, store.conversation?.streamId)
        assertFalse("iteration $iteration still busy", busy)
        assertEquals("iteration $iteration executed twice", 1, host.executions)
      }
    } finally {
      host.close()
    }
  }

  private fun exchange(
    host: ScriptedTlsHost,
    iteration: Int,
    fullLog: Boolean,
    applier: SyncApplier,
    advance: () -> Long,
    onBusy: (Boolean) -> Unit
  ) {
    val accepted = Thread { host.acceptAndPlay(iteration, fullLog) }
    accepted.start()
    val socket = chaosClientContext().socketFactory.createSocket(
      InetAddress.getByName("127.0.0.1"), host.port
    ) as SSLSocket
    socket.soTimeout = 3_000
    socket.startHandshake()
    val assembler = FrameAssembler()
    val input = socket.inputStream
    val buffer = ByteArray(4096)
    var sawIdle = false
    while (!sawIdle) {
      val count = try {
        input.read(buffer)
      } catch (error: Exception) {
        -1
      }
      if (count < 0) break
      val assembled = assembler.offer(buffer, 0, count, advance())
      for (frame in assembled.frames) {
        if (frame.json.contains("\"type\":\"event\"")) {
          val event = decodeMonitorEvent(eventPayload(frame.json)) ?: continue
          runBlocking {
            applier.offer(event)
            advance()
            applier.tick()
          }
          continue
        }
        val message = tryDecodeEnvelope(frame)
        if (!message.ok) continue
        if (message.message.kind == MessageKind.Status) {
          val view = decodeStatusPayload(message.message.payloadJson) ?: continue
          onBusy(view.busy)
          if (!view.busy) sawIdle = true
        }
      }
    }
    if (fullLog || sawIdle) socket.outputStream.write(chaosCommandFrame())
    socket.close()
    accepted.join(3_000)
  }
}

private fun eventPayload(json: String): String {
  val marker = "\"payload\":"
  val start = json.indexOf(marker)
  if (start < 0) return ""
  val body = json.substring(start + marker.length).trim()
  return if (body.endsWith("}")) body.dropLast(1) else body
}

private class ChaosMemoryStore : SyncStore {
  var conversation: ConversationRecord? = null
  val turns = LinkedHashMap<String, TurnRecord>()
  val blocks = LinkedHashMap<String, BlockRecord>()

  override suspend fun apply(hostId: String, events: List<computing.michell.monitor.protocol.MonitorEvent>, nowMs: Long): SyncApplyResult {
    val reduced = reduceSync(hostId, nowMs, conversation, turns.values.toList(), blocks.values.toList(), emptyList(), events)
    val commit = reduced.commit
    if (commit != null) {
      conversation = commit.conversation
      turns.clear()
      blocks.clear()
      for (turn in commit.turns) turns[turn.turnId] = turn
      for (block in commit.blocks) blocks[block.blockId] = block
    }
    return SyncApplyResult(reduced.applied?.let { listOf(it) } ?: emptyList(), reduced.gap?.let { listOf(it) } ?: emptyList(), reduced.fetches)
  }
}
