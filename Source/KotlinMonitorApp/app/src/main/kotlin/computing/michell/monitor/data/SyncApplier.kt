package computing.michell.monitor.data

/* Batches catalogue-3 events and commits them with the cursor (c) 2026 Michell Computing.

   A batch closes at 128 events, 64 KiB, or 50 ms from the first queued event.
   The store writes the rows and (streamId, seq) in one transaction. Pending
   stays until that commit. A failed apply is not acknowledged. After a few
   failures the link reconnects from the last durable cursor. Ack is at most
   one per conversation per 250 ms. */

import androidx.room3.withWriteTransaction
import computing.michell.monitor.protocol.EmptyPrefixHash
import computing.michell.monitor.protocol.MonitorEvent
import computing.michell.monitor.protocol.SyncFrame
import computing.michell.monitor.protocol.flagField
import computing.michell.monitor.protocol.jsonObject
import computing.michell.monitor.protocol.longField
import computing.michell.monitor.protocol.prefixHash
import computing.michell.monitor.protocol.textField
import computing.michell.monitor.protocol.utf8Length
import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

const val SyncBatchLimit = 128
const val SyncBatchWindowMs = 50L
const val SyncBatchBytes = 64 * 1024
const val SyncAckIntervalMs = 250L
const val SyncApplyRetries = 3
/**
 * No committed cursor or baseline for this long replaces the socket.
 * The gap policy waits 1s, 2s, 4s and 8s, which is the same 15s.
 * Apply failures use [SyncApplyRetries] instead. A ping does not reset either budget.
 * A commit of an older event does not reset the open-turn clock. That clock is the announced head.
 */
const val SyncRecoveryBudgetMs = 15_000L

sealed class SyncEffect {
  data class Resume(val conversationId: String, val streamId: String, val seq: Long, val hold: Boolean = false) : SyncEffect()
  data object FetchReady : SyncEffect()
  data object Reconnect : SyncEffect()
  data class FetchBlock(
    val conversationId: String,
    val blockId: String,
    val offset: Int = 0,
    val prefixHash: String = "",
    val requestId: String = "",
    val open: Boolean = false
  ) : SyncEffect()
  /** The body is stored. The fetch slot is free before the board watch republishes. */
  data class BlockApplied(val blockId: String, val complete: Boolean) : SyncEffect()
  data class PlanPiece(
    val path: String,
    val revision: String,
    val offset: Long,
    val text: String,
    val totalBytes: Long,
    val last: Boolean
  ) : SyncEffect()
  data class Ack(val conversationId: String, val streamId: String, val seq: Long) : SyncEffect()
  data class StateApplied(val key: String, val valueJson: String) : SyncEffect()
  data class Note(val text: String) : SyncEffect()
  /** The open block is behind the announced head. The chip says Catching up, not Busy. */
  data class OpenBehind(val behind: Boolean) : SyncEffect()
  data object CacheReady : SyncEffect()
}

data class SyncApplyResult(
  val applied: List<AppliedCursor>,
  val gaps: List<SyncGap>,
  val fetches: List<BlockFetch>
)

interface SyncStore {
  /** One transaction for the whole batch. Content and cursor move together. */
  suspend fun apply(hostId: String, events: List<MonitorEvent>, nowMs: Long): SyncApplyResult
  suspend fun cursorOf(hostId: String, conversationId: String): AppliedCursor? = null
  suspend fun commitBaseline(hostId: String, commit: BaselineCommit, nowMs: Long): BaselinePlan? = null
  suspend fun acceptFetch(
    hostId: String,
    conversationId: String,
    blockId: String,
    pieces: Map<Int, String>,
    revision: Long,
    hasRevision: Boolean,
    totalBytes: Int,
    ref: String,
    nowMs: Long
  ): FetchFinish = FetchFinish.Ignore
  suspend fun saveState(hostId: String, key: String, valueJson: String, nowMs: Long) {}
  suspend fun pendingFetches(hostId: String): List<BlockFetch> = emptyList()
  suspend fun noteRevisionChanged(hostId: String, ref: String, nowMs: Long): BlockFetch? = null
  suspend fun commitTurnPage(hostId: String, conversationId: String, turn: computing.michell.monitor.protocol.WireTurn, nowMs: Long) {}
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
        val turnIds = affectedTurnIds(group).toList()
        val blockIds = affectedBlockIds(group).toList()
        val imageIds = affectedImageIds(group).toList()
        val reduced = reduceSync(
          hostId,
          nowMs,
          dao.loadConversation(hostId, id),
          if (turnIds.isEmpty()) emptyList() else dao.loadTurnsById(hostId, id, turnIds),
          if (blockIds.isEmpty()) emptyList() else dao.loadBlocksById(hostId, id, blockIds),
          if (imageIds.isEmpty()) emptyList() else dao.loadImagesById(hostId, id, imageIds),
          group,
          if (blockIds.isEmpty()) emptyList() else dao.loadRepairs(hostId, id, blockIds).map { it.toRepair() },
          if (blockIds.isEmpty()) emptyList() else dao.loadHeld(hostId, id, blockIds).map { it.toHeld() }
        )
        val commit = reduced.commit
        if (commit != null) {
          if (!hostReady) {
            dao.insertHost(HostRecord(hostId, "", ""))
            hostReady = true
          }
          dao.saveConversation(commit.conversation)
          if (commit.turns.isNotEmpty()) dao.saveTurns(commit.turns)
          if (commit.blocks.isNotEmpty()) dao.saveBlocks(commit.blocks)
          for (claim in commit.claims) dao.supersedeTurnsAt(hostId, id, claim.turnId, claim.ordinal)
          if (commit.images.isNotEmpty()) dao.upsertImages(commit.images)
          if (commit.repairs.isNotEmpty()) dao.upsertRepairs(commit.repairs.map { it.toRecord() })
          for (blockId in commit.clearRepairIds) dao.deleteRepair(hostId, id, blockId)
          if (commit.held.isNotEmpty()) dao.upsertHeld(commit.held.map { it.toRecord() })
          for (blockId in commit.dropHeldBlocks) dao.deleteHeldBlock(hostId, id, blockId)
        }
        reduced.applied?.let { applied += it }
        reduced.gap?.let { gaps += it }
        fetches += reduced.fetches
      }
      SyncApplyResult(applied, gaps, fetches)
    }
  }

  override suspend fun cursorOf(hostId: String, conversationId: String): AppliedCursor? {
    val row = database.sync().loadConversation(hostId, conversationId) ?: return null
    return AppliedCursor(row.id, row.streamId, row.seq)
  }

  override suspend fun commitBaseline(hostId: String, commit: BaselineCommit, nowMs: Long): BaselinePlan? {
    return database.withWriteTransaction {
      val dao = database.sync()
      if (dao.findHost(hostId) == null) dao.insertHost(HostRecord(hostId, "", ""))
      val plan = reconcileBaseline(
        hostId,
        nowMs,
        dao.loadConversation(hostId, commit.conversationId),
        dao.loadTurns(hostId, commit.conversationId),
        dao.loadBlocks(hostId, commit.conversationId),
        commit
      ) ?: return@withWriteTransaction null
      dao.saveConversation(plan.conversation)
      if (plan.upsertTurns.isNotEmpty()) dao.saveTurns(plan.upsertTurns)
      if (plan.upsertBlocks.isNotEmpty()) dao.saveBlocks(plan.upsertBlocks)
      for (blockId in plan.deleteBlockIds) {
        dao.deleteHeldBlock(hostId, commit.conversationId, blockId)
        dao.deleteRepair(hostId, commit.conversationId, blockId)
        dao.deleteBlock(hostId, commit.conversationId, blockId)
      }
      for (turnId in plan.deleteTurnIds) dao.deleteTurn(hostId, commit.conversationId, turnId)
      if (plan.repairs.isNotEmpty()) dao.upsertRepairs(plan.repairs.map { it.toRecord() })
      for (blockId in plan.clearRepairIds) dao.deleteRepair(hostId, commit.conversationId, blockId)
      plan
    }
  }

  override suspend fun commitTurnPage(
    hostId: String,
    conversationId: String,
    turn: computing.michell.monitor.protocol.WireTurn,
    nowMs: Long
  ) {
    if (conversationId.isEmpty() || turn.id.isEmpty()) return
    database.withWriteTransaction {
      val dao = database.sync()
      if (dao.findHost(hostId) == null) dao.insertHost(HostRecord(hostId, "", ""))
      val existing = dao.loadBlocks(hostId, conversationId).filter { block -> block.turn == turn.id }.associateBy { block -> block.blockId }
      // A turn page carries the blocks, not the turn's prompt, mode or time. Keep what the outline or events stored.
      val previous = dao.loadTurnsById(hostId, conversationId, listOf(turn.id)).firstOrNull()
      val row = TurnRecord(
        hostId, conversationId, turn.id, turn.turnIndex, turn.mode.ifEmpty { previous?.mode.orEmpty() },
        turn.prompt.ifEmpty { turn.promptPreview }.ifEmpty { previous?.prompt.orEmpty() },
        turn.createdAt.ifEmpty { previous?.createdAt.orEmpty() },
        if (turn.live) "running" else previous?.outcome?.takeIf { outcome -> outcome != "running" && outcome.isNotEmpty() } ?: "ok",
        if (turn.durationMs > 0) turn.durationMs else previous?.durationMs ?: 0,
        turn.errorText.ifEmpty { previous?.errorText.orEmpty() }
      )
      dao.saveTurns(listOf(row))
      val blocks = turn.blocks.mapIndexed { index, block ->
        val kept = existing[block.blockId]
        val body = if (block.deferred && block.body.isEmpty()) kept?.body.orEmpty() else block.body
        if (body.isNotEmpty() && !block.deferred) dao.deleteRepair(hostId, conversationId, block.blockId)
        BlockRecord(
          hostId, conversationId, turn.id, block.blockId, index, block.kind, block.title, body,
          if (block.running) "running" else if (block.ok) "ok" else "failed"
        )
      }
      if (blocks.isNotEmpty()) dao.saveBlocks(blocks)
      // A page names the desktop's turn at this index. Live pages sit below zero and claim nothing.
      dao.supersedeTurnsAt(hostId, conversationId, turn.id, turn.turnIndex)
    }
  }

  override suspend fun acceptFetch(
    hostId: String,
    conversationId: String,
    blockId: String,
    pieces: Map<Int, String>,
    revision: Long,
    hasRevision: Boolean,
    totalBytes: Int,
    ref: String,
    nowMs: Long
  ): FetchFinish {
    return database.withWriteTransaction {
      val dao = database.sync()
      val located = if (conversationId.isNotEmpty()) conversationId
        else dao.loadRepairByBlock(hostId, blockId)?.conversation ?: return@withWriteTransaction FetchFinish.Ignore
      val repair = dao.loadRepair(hostId, located, blockId)?.toRepair()
        ?: return@withWriteTransaction FetchFinish.Ignore
      val block = dao.loadBlock(hostId, conversationId, blockId)
      val held = dao.loadHeld(hostId, conversationId, listOf(blockId)).map { it.toHeld() }
      val finished = finishFetch(block, repair, held, pieces, revision, hasRevision, totalBytes, ref, nowMs)
      when (finished) {
        is FetchFinish.Applied -> {
          if (block != null) dao.saveBlocks(listOf(block.copy(body = finished.body)))
          val next = repair.copy(
            revision = finished.revision,
            expectedLength = utf8Length(finished.body),
            missingBody = finished.missingBody,
            hash = prefixHash(finished.body),
            fetchedBody = if (block == null) finished.body else "",
            requestId = finished.requestId
          )
          if (finished.missingBody || block == null) dao.upsertRepairs(listOf(next.toRecord()))
          else dao.deleteRepair(hostId, located, blockId)
          for (seq in finished.dropSeqs) dao.deleteHeldSeq(hostId, located, blockId, seq)
        }
        is FetchFinish.Again -> {
          dao.upsertRepairs(listOf(repair.copy(
            revision = finished.revision,
            expectedLength = finished.offset,
            missingBody = true,
            hash = finished.prefixHash,
            requestId = finished.requestId,
            fetchedBody = ""
          ).toRecord()))
        }
        FetchFinish.Ignore -> { }
      }
      finished
    }
  }

  override suspend fun saveState(hostId: String, key: String, valueJson: String, nowMs: Long) {
    database.withWriteTransaction {
      val dao = database.sync()
      if (dao.findHost(hostId) == null) dao.insertHost(HostRecord(hostId, "", ""))
      dao.upsertState(HostStateRecord(hostId, key, valueJson, nowMs))
    }
  }

  override suspend fun pendingFetches(hostId: String): List<BlockFetch> {
    return database.sync().loadMissingRepairs(hostId).map { row ->
      val repair = row.toRepair()
      BlockFetch(repair.conversation, repair.blockId, repair.expectedLength, repair.hash.ifEmpty { EmptyPrefixHash }, repair.requestId)
    }
  }

  override suspend fun noteRevisionChanged(hostId: String, ref: String, nowMs: Long): BlockFetch? {
    if (ref.isEmpty()) return null
    return database.withWriteTransaction {
      val dao = database.sync()
      val row = dao.loadRepairByRequest(hostId, ref) ?: return@withWriteTransaction null
      val request = fetchRequestId(row.blockId, nowMs)
      dao.upsertRepairs(listOf(row.copy(revision = 0, expectedLength = 0, missingBody = true, hash = EmptyPrefixHash, requestId = request, fetchedBody = "")))
      BlockFetch(row.conversation, row.blockId, 0, EmptyPrefixHash, request)
    }
  }
}

class SyncApplier(
  private val hostId: String,
  private val store: SyncStore,
  private val nowMs: () -> Long,
  private val onEffect: (SyncEffect) -> Unit = {}
) {
  /** A committed cursor or baseline. A ping does not call this. Not a constructor parameter: trailing lambdas are effects. */
  var onCommitted: () -> Unit = {}
  private val gate = Mutex()
  private val pending = ArrayDeque<MonitorEvent>()
  private val pendingSizes = ArrayDeque<Int>()
  private var pendingBytes = 0
  private var openedMs = 0L
  private var failures = 0
  private val resume = SyncResumePolicy()
  private val acks = AckPacer()
  private val baseline = BaselineStage()
  /** When a baseline started and has not committed. Negative means none is waiting. */
  private var baselineSinceMs = -1L
  private var baselineConversation = ""
  private var baselineStream = ""
  private val stateChunks = StateChunkAssembly()
  private val fetches = HashMap<String, java.util.TreeMap<Int, String>>()
  private val fetchRevision = HashMap<String, Long>()
  private val committed = HashMap<String, AppliedCursor>()
  /** Open-turn sequence versus the announced head. Not reset by an older commit or a ping. */
  private val follow = OpenTurnFollow()
  /** Physical connection currently allowed to apply. Zero means none. */
  private var generation = 0
  /** Dispatcher of the last tick. Tests check that the flush job is not Main. */
  var tickDispatcher: String = ""
    private set

  /**
   * Binds this applier to one physical connection.
   * The caller joins any commit already inside the gate before the next
   * baseline is offered, and this lock waits for a tick that is still
   * committing. Uncommitted batches, a partial baseline, state chunks and
   * fetch assembly are dropped. Room rows, the command ledger and the
   * committed cursor cache stay. The next baseline therefore starts empty,
   * after the previous transaction has finished.
   */
  suspend fun adoptConnection(generation: Int) = gate.withLock {
    if (generation == 0 || generation == this.generation) return
    this.generation = generation
    discardTransient()
  }

  /**
   * The socket that owned [generation] is gone. A newer connection that has
   * already adopted is left alone. Otherwise transient assembly is dropped
   * and no generation may apply until the next adopt.
   */
  suspend fun retireConnection(generation: Int) = gate.withLock {
    if (generation == 0) return
    if (this.generation != 0 && this.generation != generation) return
    discardTransient()
    if (this.generation == generation) this.generation = 0
  }

  /** The connection offers each decoded event. A full batch commits at once. */
  suspend fun offer(event: MonitorEvent, bytes: Int = estimatedEventBytes(event), generation: Int = -1): List<SyncEffect> = gate.withLock {
    if (!accepts(generation)) return emptyList()
    val size = if (bytes > 0) bytes else estimatedEventBytes(event)
    if (pending.isEmpty()) openedMs = nowMs()
    pending.add(event)
    pendingSizes.add(size)
    pendingBytes += size
    if (pending.size < SyncBatchLimit && pendingBytes < SyncBatchBytes) return emptyList()
    deliver(flush())
  }

  /** Closes a batch that has waited 50 ms from the first event, and arms the next resume. */
  suspend fun tick(): List<SyncEffect> = gate.withLock {
    refuseMainDispatcher()
    val now = nowMs()
    val flushed = if (pending.isNotEmpty() && now - openedMs >= SyncBatchWindowMs) flush() else emptyList()
    val decision = follow.consider(now)
    val recovery = if (decision.recover) openTurnRecovery(now) else emptyList()
    deliver(flushed + acks.tick(now) + resume.tick(now) + baselineRecovery(now) + recovery + behindEffect(decision.changed))
  }

  /** State, baseline, and block fetch. None of these is a content event. */
  suspend fun offerFrame(frame: SyncFrame, generation: Int = -1): List<SyncEffect> = gate.withLock {
    if (!accepts(generation)) return emptyList()
    deliver(applyFrame(frame))
  }

  /** The inbound budget refused this event. Resume from the last durable cursor. */
  suspend fun noteRefused(event: MonitorEvent, generation: Int = -1): List<SyncEffect> = gate.withLock {
    if (!accepts(generation)) return emptyList()
    val cursor = store.cursorOf(hostId, event.conversationId) ?: committed[event.conversationId]
    val seq = cursor?.seq ?: 0L
    val stream = cursor?.streamId?.ifEmpty { null } ?: event.streamId
    deliver(listOf(resume.onGap(SyncGap(event.conversationId, stream, seq), nowMs()) ?: SyncEffect.Resume(event.conversationId, stream, seq)))
  }

  /** One flush job. The view-model scope is the main thread; the tick must not be. */
  fun start(scope: CoroutineScope): Job = scope.launch(Dispatchers.IO) {
    while (isActive) {
      val wait = gate.withLock { nextWaitMs(nowMs()) }
      delay(wait.coerceAtLeast(1L))
      tick()
    }
  }

  private suspend fun refuseMainDispatcher() {
    val dispatcher = coroutineContext[ContinuationInterceptor]?.toString().orEmpty()
    tickDispatcher = dispatcher
    check(!dispatcher.contains("Main")) { "SyncApplier.tick must not run on the main dispatcher" }
  }

  private fun nextWaitMs(now: Long): Long {
    var wait = SyncBatchWindowMs
    if (pending.isNotEmpty()) {
      val due = openedMs + SyncBatchWindowMs - now
      wait = if (due < 1L) 1L else due
    }
    val ackIn = acks.dueIn(now)
    if (ackIn in 1 until wait) wait = ackIn
    return wait
  }

  private suspend fun flush(): List<SyncEffect> {
    if (pending.isEmpty()) return emptyList()
    val batch = pending.toList()
    val now = nowMs()
    val result = try {
      store.apply(hostId, batch, now)
    } catch (error: CancellationException) {
      throw error
    } catch (error: Exception) {
      failures += 1
      if (failures < SyncApplyRetries) return emptyList()
      return giveUp(batch, now)
    }
    clearPending()
    failures = 0
    val effects = mutableListOf<SyncEffect>()
    for (applied in result.applied) {
      committed[applied.conversationId] = applied
      resume.noteApplied(applied.conversationId, applied.seq)
      acks.note(applied, now)?.let { effects += it }
    }
    if (result.applied.isNotEmpty()) {
      noteDurableProgress(now)
      val through = HashMap<String, Long>()
      for (applied in result.applied) through[applied.conversationId] = applied.seq
      for (event in batch) {
        val seq = through[event.conversationId] ?: continue
        if (event.seq <= seq) follow.noteApplied(event, now)
      }
    }
    for (fetch in result.fetches) {
      effects += SyncEffect.FetchBlock(fetch.conversationId, fetch.blockId, fetch.offset, fetch.prefixHash, fetch.requestId, true)
    }
    for (gap in result.gaps) resume.onGap(gap, now)?.let { effects += it }
    if (result.applied.isNotEmpty()) effects += SyncEffect.CacheReady
    if (follow.consumeChanged()) effects += SyncEffect.OpenBehind(follow.openBehind)
    return effects
  }

  private suspend fun giveUp(batch: List<MonitorEvent>, now: Long): List<SyncEffect> {
    clearPending()
    failures = 0
    val effects = mutableListOf<SyncEffect>()
    for (id in batch.map { it.conversationId }.distinct()) {
      val sample = batch.first { it.conversationId == id }
      effects += recover(id, sample.streamId, includeReconnect = false)
    }
    effects += SyncEffect.Reconnect
    return effects
  }

  private fun clearPending() {
    pending.clear()
    pendingSizes.clear()
    pendingBytes = 0
    openedMs = 0L
  }

  /** Untagged callers are tests. A live generation must match, and zero never applies. */
  private fun accepts(generation: Int): Boolean {
    if (generation < 0) return true
    return generation != 0 && generation == this.generation
  }

  private fun discardTransient() {
    clearPending()
    failures = 0
    baseline.abandon()
    baselineSinceMs = -1L
    baselineConversation = ""
    baselineStream = ""
    stateChunks.reset()
    fetches.clear()
    fetchRevision.clear()
    resume.reset()
    acks.reset()
    follow.suppressUntil(nowMs())
  }

  /** Resume from the durable cursor when the open turn has been behind the announced head for the budget. */
  private suspend fun openTurnRecovery(now: Long): List<SyncEffect> {
    val recovered = recover(follow.conversationId, follow.streamId)
    follow.suppressUntil(now)
    val effects = recovered.toMutableList()
    if (follow.markBehind()) effects += SyncEffect.OpenBehind(true)
    return effects
  }

  private fun behindEffect(changed: Boolean): List<SyncEffect> {
    if (!changed) return emptyList()
    return listOf(SyncEffect.OpenBehind(follow.openBehind))
  }

  /** A committed cursor or baseline restarts the baseline clock. A ping does not. An older event does not restart the open-turn clock. */
  private fun noteDurableProgress(now: Long) {
    onCommitted()
    if (!baseline.isOpen) {
      baselineSinceMs = -1L
      return
    }
    baselineSinceMs = now
  }

  private suspend fun baselineRecovery(now: Long): List<SyncEffect> {
    if (baselineSinceMs < 0L || now - baselineSinceMs < SyncRecoveryBudgetMs) return emptyList()
    val conversationId = baselineConversation
    val streamId = baselineStream
    baselineSinceMs = -1L
    baseline.abandon()
    return recover(conversationId, streamId)
  }

  /** Resume from the last committed cursor, then replace the socket when asked. */
  private suspend fun recover(conversationId: String, streamId: String, includeReconnect: Boolean = true): List<SyncEffect> {
    val cursor = durableCursor(conversationId)
    val seq = cursor?.seq ?: 0L
    val stream = cursor?.streamId?.ifEmpty { null } ?: streamId
    val effects = mutableListOf<SyncEffect>()
    if (conversationId.isNotEmpty()) effects += SyncEffect.Resume(conversationId, stream, seq, true)
    if (includeReconnect) effects += SyncEffect.Reconnect
    return effects
  }

  private suspend fun durableCursor(conversationId: String): AppliedCursor? {
    if (conversationId.isEmpty()) return null
    val stored = try {
      store.cursorOf(hostId, conversationId)
    } catch (error: CancellationException) {
      throw error
    } catch (error: Exception) {
      null
    }
    return stored ?: committed[conversationId]
  }

  private suspend fun applyFrame(frame: SyncFrame): List<SyncEffect> {
    return when (frame) {
      is SyncFrame.Event -> emptyList()
      is SyncFrame.State -> applyState(frame.key, frame.valueJson)
      is SyncFrame.StateChunk -> {
        val joined = stateChunks.accept(frame) ?: return emptyList()
        applyState(joined.key, joined.valueJson)
      }
      is SyncFrame.SnapshotBegin -> {
        baseline.begin(frame)
        if (baselineSinceMs < 0L) {
          baselineSinceMs = nowMs()
          baselineConversation = frame.conversationId
          baselineStream = frame.streamId
        }
        val effects = mutableListOf<SyncEffect>()
        for ((key, value) in frame.state) effects += applyState(key, value)
        effects
      }
      is SyncFrame.SnapshotPage -> {
        if (frame.turn != null && frame.turns.isEmpty()) {
          commitTurnPage(frame)
          return listOf(SyncEffect.CacheReady)
        }
        baseline.page(frame)
        emptyList()
      }
      is SyncFrame.SnapshotEnd -> {
        val commit = baseline.end(frame) ?: return listOf(SyncEffect.CacheReady)
        val plan = try {
          store.commitBaseline(hostId, commit, nowMs())
        } catch (error: CancellationException) {
          throw error
        } catch (error: Exception) {
          baselineSinceMs = -1L
          return recover(commit.conversationId, commit.streamId)
        } ?: run {
          baselineSinceMs = -1L
          return recover(commit.conversationId, commit.streamId)
        }
        committed[plan.conversation.id] = AppliedCursor(plan.conversation.id, plan.conversation.streamId, plan.conversation.seq)
        noteDurableProgress(nowMs())
        plan.fetches.map { fetch ->
          SyncEffect.FetchBlock(
            fetch.conversationId, fetch.blockId, fetch.offset, fetch.prefixHash, fetch.requestId,
            fetch.blockId == plan.openBlockId
          )
        } + listOf(SyncEffect.FetchReady, SyncEffect.CacheReady)
      }
      is SyncFrame.BlockData -> applyBlockData(frame)
      is SyncFrame.PlanData -> listOf(SyncEffect.PlanPiece(
        frame.path, frame.revision, frame.offset, frame.text, frame.totalBytes, frame.last
      ))
      is SyncFrame.NotReady -> listOf(SyncEffect.Note("The desktop has not observed this conversation yet."), SyncEffect.CacheReady)
      is SyncFrame.ResumeOk -> listOf(SyncEffect.FetchReady, SyncEffect.CacheReady)
      is SyncFrame.RevisionChanged -> {
        val fetch = try {
          store.noteRevisionChanged(hostId, frame.ref, nowMs())
        } catch (error: CancellationException) {
          throw error
        } catch (error: Exception) {
          null
        }
        fetches.remove(frame.ref)
        if (fetch == null) emptyList()
        else listOf(SyncEffect.FetchBlock(fetch.conversationId, fetch.blockId, fetch.offset, fetch.prefixHash, fetch.requestId))
      }
    }
  }

  private suspend fun commitTurnPage(frame: SyncFrame.SnapshotPage) {
    val turn = frame.turn ?: return
    val conversationId = frame.conversationId.ifEmpty { turn.id }
    if (conversationId.isEmpty()) return
    try {
      store.commitTurnPage(hostId, frame.conversationId, turn, nowMs())
    } catch (error: CancellationException) {
      throw error
    } catch (error: Exception) {
      // A failed turn page leaves the stored turn. The next visible pass can ask again.
    }
  }

  private suspend fun applyState(key: String, valueJson: String): List<SyncEffect> {
    val now = nowMs()
    when (key) {
      "head" -> follow.noteHeadJson(valueJson, now)
      "status" -> follow.noteStatusJson(valueJson, now)
    }
    try {
      store.saveState(hostId, key, valueJson, now)
    } catch (error: CancellationException) {
      throw error
    } catch (error: Exception) {
      if (key != "approval") return behindOnly()
    }
    val effects = mutableListOf<SyncEffect>(SyncEffect.StateApplied(key, valueJson), SyncEffect.CacheReady)
    if (follow.consumeChanged()) effects += SyncEffect.OpenBehind(follow.openBehind)
    return effects
  }

  private fun behindOnly(): List<SyncEffect> {
    if (!follow.consumeChanged()) return emptyList()
    return listOf(SyncEffect.OpenBehind(follow.openBehind))
  }

  private suspend fun applyBlockData(frame: SyncFrame.BlockData): List<SyncEffect> {
    follow.noteBodyPiece(frame.blockId, nowMs())
    val key = frame.ref.ifEmpty { frame.blockId }
    val pieces = fetches.getOrPut(key) { java.util.TreeMap() }
    if (frame.hasRevision) {
      val previous = fetchRevision[key]
      if (previous != null && previous != frame.revision) pieces.clear()
      fetchRevision[key] = frame.revision
    }
    pieces[frame.offset] = frame.text
    if (!frame.last) return emptyList()
    val conversationId = frame.conversationId
    val finished = try {
      store.acceptFetch(
        hostId, conversationId, frame.blockId, pieces.toMap(), frame.revision, frame.hasRevision,
        frame.totalBytes, frame.ref, nowMs()
      )
    } catch (error: CancellationException) {
      throw error
    } catch (error: Exception) {
      return emptyList()
    }
    fetches.remove(key)
    if (finished is FetchFinish.Applied) follow.noteBodyApplied(frame.blockId, nowMs())
    val effects = when (finished) {
      is FetchFinish.Again -> {
        mutableListOf<SyncEffect>(SyncEffect.FetchBlock(conversationId, frame.blockId, finished.offset, finished.prefixHash, finished.requestId))
      }
      is FetchFinish.Applied -> mutableListOf<SyncEffect>(SyncEffect.BlockApplied(frame.blockId, !finished.missingBody))
      FetchFinish.Ignore -> mutableListOf()
    }
    if (follow.consumeChanged()) effects += SyncEffect.OpenBehind(follow.openBehind)
    return effects
  }

  private fun deliver(effects: List<SyncEffect>): List<SyncEffect> {
    effects.forEach(onEffect)
    return effects
  }
}

/**
 * The open turn's applied sequence, separate from any commit.
 * A ping is not an input. An older event does not restart either clock.
 * Body pieces for the open block are the gap closing; they are not a reconnect.
 */
private class OpenTurnFollow {
  var conversationId = ""
  var streamId = ""
  var openBehind = false
    private set

  private var announcedHead = -1L
  private var announcedOpenBlock = ""
  private var turnRunning = false
  private var openTurnId = ""
  private val openBlocks = HashSet<String>()
  private var openTurnAppliedSeq = -1L
  private var bodyOwed = false
  private var lastBodyMs = -1L
  private var bodyWaitSince = -1L
  private var seqBehindSince = -1L
  private var changed = false

  fun noteHeadJson(valueJson: String, now: Long): Boolean {
    val value = jsonObject(valueJson) ?: return false
    val seq = value.longField("seq") ?: return false
    value.textField("conversation_id")?.let { if (it.isNotEmpty()) conversationId = it }
    value.textField("stream_id")?.let { if (it.isNotEmpty()) streamId = it }
    value.textField("open_block")?.let { if (it.isNotEmpty()) announcedOpenBlock = it }
    value.flagField("running")?.let { turnRunning = it }
    if (seq > announcedHead) announcedHead = seq
    arm(now)
    return refresh()
  }

  fun noteStatusJson(valueJson: String, now: Long): Boolean {
    val value = jsonObject(valueJson) ?: return false
    val busy = value.flagField("busy")
    val sending = value.flagField("sending")
    if (busy == null && sending == null) return false
    turnRunning = busy == true || sending == true
    if (!turnRunning) {
      bodyOwed = false
      bodyWaitSince = -1L
    }
    arm(now)
    return refresh()
  }

  fun noteApplied(event: MonitorEvent, now: Long): Boolean {
    if (event.conversationId.isNotEmpty()) conversationId = event.conversationId
    if (event.streamId.isNotEmpty()) streamId = event.streamId
    val openProgress = noteOpen(event, now)
    if (openProgress || !turnRunning) {
      if (event.seq > openTurnAppliedSeq) openTurnAppliedSeq = event.seq
      seqBehindSince = -1L
      arm(now)
    }
    return refresh()
  }

  fun noteBodyPiece(blockId: String, now: Long): Boolean {
    if (!isOpenBlock(blockId)) return false
    noteBody(now)
    return refresh()
  }

  fun noteBodyApplied(blockId: String, now: Long): Boolean {
    if (!isOpenBlock(blockId)) return false
    noteBody(now)
    return refresh()
  }

  fun consider(now: Long): FollowDecision {
    arm(now)
    val recover = seqStale(now) || bodyStale(now)
    return FollowDecision(recover, refresh())
  }

  fun consumeChanged(): Boolean {
    val was = changed
    changed = false
    return was
  }

  fun markBehind(): Boolean {
    if (openBehind) return false
    openBehind = true
    changed = true
    return true
  }

  /** The new socket gets a full budget. The announced head stays, so the chip can stay on Catching up. */
  fun suppressUntil(now: Long) {
    seqBehindSince = if (seqBehind()) now else -1L
    bodyWaitSince = if (lastBodyMs < 0L && bodyCondition()) now else -1L
    if (lastBodyMs >= 0L && now - lastBodyMs >= SyncRecoveryBudgetMs) lastBodyMs = now
  }

  private fun noteOpen(event: MonitorEvent, now: Long): Boolean {
    return when (event) {
      is MonitorEvent.TurnOpen -> {
        openTurnId = event.turnId
        openBlocks.clear()
        bodyOwed = false
        true
      }
      is MonitorEvent.TurnClose -> {
        if (event.turnId != openTurnId || openTurnId.isEmpty()) return false
        openTurnId = ""
        openBlocks.clear()
        true
      }
      is MonitorEvent.BlockOpen -> {
        if (openTurnId.isNotEmpty() && event.turnId != openTurnId) return false
        if (openTurnId.isEmpty()) openTurnId = event.turnId
        openBlocks.add(event.blockId)
        true
      }
      is MonitorEvent.BlockAppend -> {
        if (!isOpenBlock(event.blockId)) return false
        noteBody(now)
        true
      }
      is MonitorEvent.BlockReplace -> {
        if (!isOpenBlock(event.blockId)) return false
        if (event.deferred) bodyOwed = true else noteBody(now)
        true
      }
      is MonitorEvent.BlockClose -> isOpenBlock(event.blockId)
      is MonitorEvent.ImageAdded -> event.turnId.isNotEmpty() && event.turnId == openTurnId
      else -> false
    }
  }

  private fun noteBody(now: Long) {
    lastBodyMs = now
    bodyOwed = false
    bodyWaitSince = -1L
  }

  private fun isOpenBlock(blockId: String): Boolean {
    if (blockId.isEmpty()) return false
    return blockId == announcedOpenBlock || blockId in openBlocks
  }

  private fun openBlockKnown(): Boolean = announcedOpenBlock.isNotEmpty() || openBlocks.isNotEmpty()

  private fun seqBehind(): Boolean = announcedHead > 0L && openTurnAppliedSeq < announcedHead

  private fun bodyCondition(): Boolean = turnRunning && openBlockKnown() && (bodyOwed || seqBehind())

  private fun bodyRecent(now: Long): Boolean = lastBodyMs >= 0L && now - lastBodyMs < SyncRecoveryBudgetMs

  private fun arm(now: Long) {
    if (seqBehind()) {
      if (seqBehindSince < 0L) seqBehindSince = now
    } else {
      seqBehindSince = -1L
    }
    if (lastBodyMs < 0L && bodyCondition()) {
      if (bodyWaitSince < 0L) bodyWaitSince = now
    } else if (!bodyCondition()) {
      bodyWaitSince = -1L
    }
  }

  private fun seqStale(now: Long): Boolean {
    return seqBehind() && seqBehindSince >= 0L && now - seqBehindSince >= SyncRecoveryBudgetMs && !bodyRecent(now)
  }

  private fun bodyStale(now: Long): Boolean {
    if (!bodyCondition() || bodyRecent(now)) return false
    if (lastBodyMs >= 0L) return now - lastBodyMs >= SyncRecoveryBudgetMs
    return bodyWaitSince >= 0L && now - bodyWaitSince >= SyncRecoveryBudgetMs
  }

  private fun refresh(): Boolean {
    val behind = seqBehind()
    if (behind == openBehind) return false
    openBehind = behind
    changed = true
    return true
  }
}

private data class FollowDecision(val recover: Boolean, val changed: Boolean)

fun estimatedEventBytes(event: MonitorEvent): Int {
  val text = when (event) {
    is MonitorEvent.BlockAppend -> event.text
    is MonitorEvent.BlockReplace -> event.body
    is MonitorEvent.TurnOpen -> event.prompt
    is MonitorEvent.TitleChanged -> event.title
    is MonitorEvent.ImageAdded -> event.name
    else -> ""
  }
  return utf8Length(text) + 128
}

/**
 * An opportunistic refresh must not replace a socket that is still receiving.
 * Forced recovery ignores heartbeats and a paused read: those are not a committed cursor.
 */
fun reconnectAllowed(linkLive: Boolean, framesArriving: Boolean, forced: Boolean = false): Boolean {
  if (forced) return true
  if (linkLive && framesArriving) return false
  return true
}

/**
 * Four resumes, then replace the link. A later applied seq clears the wait.
 * An identical cursor is not written again; the replacement is the retry.
 * The waits sum to [SyncRecoveryBudgetMs].
 */
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
        effects += SyncEffect.Resume(id, wait.gap.streamId, wait.gap.seq, true)
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

  fun reset() {
    waiting.clear()
  }
}

private class AckPacer {
  private val lastMs = HashMap<String, Long>()
  private val held = HashMap<String, AppliedCursor>()

  fun note(applied: AppliedCursor, now: Long): SyncEffect.Ack? {
    val last = lastMs[applied.conversationId]
    if (last == null || now - last >= SyncAckIntervalMs) {
      lastMs[applied.conversationId] = now
      held.remove(applied.conversationId)
      return SyncEffect.Ack(applied.conversationId, applied.streamId, applied.seq)
    }
    held[applied.conversationId] = applied
    return null
  }

  fun tick(now: Long): List<SyncEffect.Ack> {
    val ready = ArrayList<SyncEffect.Ack>()
    for (key in held.keys.toList()) {
      val applied = held[key] ?: continue
      val last = lastMs[key]
      if (last != null && now - last < SyncAckIntervalMs) continue
      held.remove(key)
      lastMs[key] = now
      ready += SyncEffect.Ack(applied.conversationId, applied.streamId, applied.seq)
    }
    return ready
  }

  fun dueIn(now: Long): Long {
    var soonest = Long.MAX_VALUE
    for (key in held.keys) {
      val last = lastMs[key] ?: continue
      val left = SyncAckIntervalMs - (now - last)
      if (left < soonest) soonest = left
    }
    return soonest
  }

  fun reset() {
    lastMs.clear()
    held.clear()
  }
}

private fun BlockRepair.toRecord(): BlockRepairRecord {
  return BlockRepairRecord(host, conversation, blockId, revision, expectedLength, missingBody, hash, stale, requestId, fetchedBody)
}

private fun BlockRepairRecord.toRepair(): BlockRepair {
  return BlockRepair(host, conversation, blockId, revision, expectedLength, missingBody, hash, stale, requestId, fetchedBody)
}

private fun HeldAppend.toRecord(): HeldAppendRecord {
  return HeldAppendRecord(host, conversation, blockId, seq, offset, text, streamId)
}

private fun HeldAppendRecord.toHeld(): HeldAppend {
  return HeldAppend(host, conversation, blockId, seq, offset, text, streamId)
}
