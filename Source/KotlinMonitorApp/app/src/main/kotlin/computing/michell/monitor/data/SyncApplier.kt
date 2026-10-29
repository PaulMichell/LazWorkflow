package computing.michell.monitor.data

/* Batches catalogue-3 events and commits them with the cursor (c) 2026 Michell Computing.

   A batch closes at 128 events or 50 ms, whichever comes first. The store
   writes the rows and (streamId, seq) in one transaction, so a process kill
   cannot keep content the cursor does not cover. A seq that skips ahead
   starts resume. The waits are 1 s, 2 s, 4 s and 8 s, then the link reconnects. */

import androidx.room3.withWriteTransaction
import computing.michell.monitor.protocol.MonitorEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

const val SyncBatchLimit = 128
const val SyncBatchWindowMs = 50L

sealed class SyncEffect {
  data class Resume(val conversationId: String, val streamId: String, val seq: Long) : SyncEffect()
  data object Reconnect : SyncEffect()
  data class FetchBlock(val conversationId: String, val blockId: String) : SyncEffect()
}

data class SyncApplyResult(
  val applied: List<AppliedCursor>,
  val gaps: List<SyncGap>,
  val fetches: List<BlockFetch>
)

interface SyncStore {
  /** One transaction for the whole batch. Content and cursor move together. */
  suspend fun apply(hostId: String, events: List<MonitorEvent>, nowMs: Long): SyncApplyResult
}

class RoomSyncStore(private val database: MonitorDatabase) : SyncStore {
  override suspend fun apply(hostId: String, events: List<MonitorEvent>, nowMs: Long): SyncApplyResult {
    return database.withWriteTransaction {
      val dao = database.sync()
      var hostReady = dao.findHost(hostId) != null
      val applied = mutableListOf<AppliedCursor>()
      val gaps = mutableListOf<SyncGap>()
      val fetches = mutableListOf<BlockFetch>()
      for ((id, group) in events.groupBy { it.conversationId }) {
        val reduced = reduceSync(
          hostId,
          nowMs,
          dao.loadConversation(hostId, id),
          dao.loadTurns(hostId, id),
          dao.loadBlocks(hostId, id),
          dao.loadImages(hostId, id),
          group
        )
        val commit = reduced.commit
        if (commit != null) {
          if (!hostReady) {
            dao.insertHost(HostRecord(hostId, "", ""))
            hostReady = true
          }
          dao.upsertConversation(commit.conversation)
          if (commit.turns.isNotEmpty()) dao.upsertTurns(commit.turns)
          if (commit.blocks.isNotEmpty()) dao.upsertBlocks(commit.blocks)
          if (commit.images.isNotEmpty()) dao.upsertImages(commit.images)
        }
        reduced.applied?.let { applied += it }
        reduced.gap?.let { gaps += it }
        fetches += reduced.fetches
      }
      SyncApplyResult(applied, gaps, fetches)
    }
  }
}

class SyncApplier(
  private val hostId: String,
  private val store: SyncStore,
  private val nowMs: () -> Long,
  private val onEffect: (SyncEffect) -> Unit = {}
) {
  private val gate = Mutex()
  private val pending = ArrayDeque<MonitorEvent>()
  private var openedMs = 0L
  private val resume = SyncResumePolicy()

  /** The connection offers each decoded event. A full batch commits at once. */
  suspend fun offer(event: MonitorEvent): List<SyncEffect> = gate.withLock {
    if (pending.isEmpty()) openedMs = nowMs()
    pending.add(event)
    if (pending.size < SyncBatchLimit) return emptyList()
    deliver(flush())
  }

  /** Closes a batch that has waited 50 ms, and arms the next resume. */
  suspend fun tick(): List<SyncEffect> = gate.withLock {
    val now = nowMs()
    val flushed = if (pending.isNotEmpty() && now - openedMs >= SyncBatchWindowMs) flush() else emptyList()
    deliver(flushed + resume.tick(now))
  }

  fun start(scope: CoroutineScope): Job = scope.launch {
    while (isActive) {
      delay(SyncBatchWindowMs)
      tick()
    }
  }

  private suspend fun flush(): List<SyncEffect> {
    val batch = pending.toList()
    pending.clear()
    openedMs = 0L
    val now = nowMs()
    val result = store.apply(hostId, batch, now)
    val effects = mutableListOf<SyncEffect>()
    for (fetch in result.fetches) effects += SyncEffect.FetchBlock(fetch.conversationId, fetch.blockId)
    for (gap in result.gaps) resume.onGap(gap, now)?.let { effects += it }
    for (applied in result.applied) resume.noteApplied(applied.conversationId, applied.seq)
    return effects
  }

  private fun deliver(effects: List<SyncEffect>): List<SyncEffect> {
    effects.forEach(onEffect)
    return effects
  }
}

/** Four resumes, then reconnect. A later applied seq clears the wait. */
class SyncResumePolicy {
  private val waits = longArrayOf(1_000L, 2_000L, 4_000L, 8_000L)
  private val waiting = mutableMapOf<String, Wait>()

  private class Wait(val gap: SyncGap, var sent: Int, var nextMs: Long)

  fun onGap(gap: SyncGap, nowMs: Long): SyncEffect.Resume? {
    if (gap.conversationId in waiting) return null
    waiting[gap.conversationId] = Wait(gap, 1, nowMs + waits[0])
    return SyncEffect.Resume(gap.conversationId, gap.streamId, gap.seq)
  }

  fun tick(nowMs: Long): List<SyncEffect> {
    val effects = mutableListOf<SyncEffect>()
    for (id in waiting.keys.toList()) {
      val wait = waiting[id] ?: continue
      if (nowMs < wait.nextMs) continue
      if (wait.sent >= waits.size) {
        waiting.remove(id)
        effects += SyncEffect.Reconnect
        continue
      }
      val delay = waits[wait.sent]
      wait.sent += 1
      wait.nextMs = nowMs + delay
      effects += SyncEffect.Resume(id, wait.gap.streamId, wait.gap.seq)
    }
    return effects
  }

  fun noteApplied(conversationId: String, seq: Long) {
    val wait = waiting[conversationId] ?: return
    if (seq > wait.gap.seq) waiting.remove(conversationId)
  }
}
