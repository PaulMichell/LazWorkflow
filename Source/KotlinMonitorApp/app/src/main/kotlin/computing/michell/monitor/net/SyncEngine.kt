package computing.michell.monitor.net

/* Act on a pulse. Compare it with Room and fetch what differs.
   (c) 2026 Michell Computing.

   One worker drains a priority queue. A resource key is in flight at most
   once, so the same item is never requested twice at once. A failed fetch is
   not repaired here: the next pulse that still shows the difference schedules
   it again. followMs is the live-item cadence from item 6.6. It starts at
   250 ms. The plan document is fetched only while the plan screen is open.
   Older history is fetched only when the reader scrolls to it. */

import computing.michell.monitor.data.ConversationRow
import computing.michell.monitor.data.HostRow
import computing.michell.monitor.data.ItemRow
import computing.michell.monitor.data.MonitorDatabase
import computing.michell.monitor.data.PlanCacheRow
import computing.michell.monitor.data.TurnRow
import java.util.ArrayDeque
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request

const val LiveTurnOutcome = "live"
const val DefaultFollowMs = 250L

private const val RankItem = 0
private const val RankOutline = 1
private const val RankTurns = 2
private const val RankPlan = 3
private const val RankLists = 4
private const val RankApproval = 5
private const val RankHistory = 6

private const val TailCheckBytes = 64

private enum class FetchKind {
  ItemTail,
  LiveOutline,
  StoredTurn,
  TurnPage,
  Plan,
  PlanDocument,
  ConversationList,
  PlanList,
  TaskList,
  Approval,
  History
}

private class FetchJob(
  val key: String,
  val rank: Int,
  val url: String,
  val kind: FetchKind,
  val epoch: String,
  val conversationId: String,
  val turnId: String,
  val turnIndex: Int,
  val itemId: String,
  val planPath: String,
  val planEtag: String,
  val seq: Long
)

class SyncEngine(
  private val database: MonitorDatabase,
  private val client: OkHttpClient,
  private val baseUrl: HttpUrl,
  private val endpoint: String,
  private val token: String = "",
  private val clock: () -> Long = { System.currentTimeMillis() }
) : AutoCloseable {
  /** Shortest gap between live item tails. Item 6.6 drives this. */
  @Volatile var followMs: Long = DefaultFollowMs

  /** When false, a scrolled-away reader does not pull item tails. */
  @Volatile var followHead: Boolean = true

  @Volatile var planScreenOpen: Boolean = false
    set(value) {
      field = value
      if (!value) return
      lock.withLock {
        openPlan = true
        ready.signalAll()
      }
    }

  private val dao = database.monitor()
  private val lock = ReentrantLock()
  private val ready = lock.newCondition()
  private val idle = lock.newCondition()
  private val pulses = ArrayDeque<String>()
  private val history = ArrayDeque<String>()
  private val pending = LinkedHashMap<String, FetchJob>()
  private val inflight = HashSet<String>()
  private var closed = false
  private var busy = false
  private var openPlan = false
  private var jobSeq = 0L
  private var lastItemFetchAt = Long.MIN_VALUE / 4
  private var watchingLiveId: String? = null
  private var watchingLiveIndex = 0
  private var liveOutlineTurnId = ""
  private var liveOutlineRev = -1L
  private var conversationsEtag = ""
  private var plansEtag = ""
  private var tasksEtag = ""
  private var approvalFetchedId = ""
  private var knownPlanPath = ""
  private var knownPlanEtag = ""
  private var documentForEtag = ""

  private val thread = Thread(::loop, "SyncEngine").apply {
    isDaemon = true
    start()
  }

  fun onPulse(json: String) {
    lock.withLock {
      pulses.addLast(json)
      ready.signalAll()
    }
  }

  /** Older pages of a conversation. Not scheduled from a pulse. */
  fun scrollToHistory(conversationId: String) {
    if (conversationId.isEmpty()) return
    lock.withLock {
      history.addLast(conversationId)
      ready.signalAll()
    }
  }

  fun awaitIdle(timeoutMs: Long = 5_000): Boolean {
    val deadline = System.currentTimeMillis() + timeoutMs
    lock.withLock {
      while (!closed && (busy || pulses.isNotEmpty() || history.isNotEmpty() || pending.isNotEmpty() || inflight.isNotEmpty() || openPlan)) {
        val left = deadline - System.currentTimeMillis()
        if (left <= 0L) return false
        idle.await(left, TimeUnit.MILLISECONDS)
      }
      return true
    }
  }

  override fun close() {
    lock.withLock {
      closed = true
      ready.signalAll()
      idle.signalAll()
    }
    thread.join(2_000)
  }

  private fun loop() {
    while (true) {
      val pulse = lock.withLock {
        if (closed) return
        val next = pulses.pollFirst()
        if (next != null) {
          busy = true
          next
        } else null
      }
      if (pulse != null) {
        try {
          acceptPulse(pulse)
        } catch (error: Exception) {
          // A bad pulse is ignored. The next one still shows any real difference.
        }
        continue
      }
      val historyId = lock.withLock {
        if (closed) return
        history.pollFirst()
      }
      if (historyId != null) {
        try {
          scheduleHistory(historyId)
        } catch (error: Exception) {
          // The scroll can be repeated.
        }
        continue
      }
      if (lock.withLock { openPlan }) {
        lock.withLock { openPlan = false }
        try {
          scheduleOpenDocument()
        } catch (error: Exception) {
          // The next pulse fetches the document if it is still missing.
        }
        continue
      }
      val job = lock.withLock {
        if (closed) return
        val now = clock()
        val next = nextReady(now)
        if (next == null) {
          if (pulses.isEmpty() && history.isEmpty() && pending.isEmpty() && inflight.isEmpty()) {
            busy = false
            idle.signalAll()
            ready.await()
          } else if (pulses.isEmpty() && history.isEmpty() && inflight.isEmpty()) {
            val wait = (followMs - (now - lastItemFetchAt)).coerceAtLeast(1L)
            ready.await(wait, TimeUnit.MILLISECONDS)
          } else {
            ready.await(50, TimeUnit.MILLISECONDS)
          }
          null
        } else {
          pending.remove(next.key)
          inflight += next.key
          busy = true
          if (next.kind == FetchKind.ItemTail) lastItemFetchAt = now
          next
        }
      }
      if (job == null) continue
      try {
        runJob(job)
      } catch (error: Exception) {
        // Failed fetch. The next pulse that still differs schedules it again.
      } finally {
        lock.withLock {
          inflight -= job.key
          idle.signalAll()
        }
      }
    }
  }

  private fun nextReady(now: Long): FetchJob? {
    return pending.values
      .filter { it.kind != FetchKind.ItemTail || itemDue(now) }
      .minWithOrNull(compareBy<FetchJob> { it.rank }.thenBy { it.seq })
  }

  private fun itemDue(now: Long): Boolean = followMs <= 0L || now - lastItemFetchAt >= followMs

  private fun acceptPulse(json: String) {
    val pulse = parsePulse(json) ?: return
    val host = dao.host(endpoint)
    if (host != null && host.lastEpoch == pulse.epoch && pulse.rev < host.lastRev) return
    val epochChanged = host != null && host.lastEpoch.isNotEmpty() && host.lastEpoch != pulse.epoch
    inTransaction { saveHost(pulse.epoch, pulse.rev) }
    if (epochChanged) {
      liveOutlineTurnId = ""
      liveOutlineRev = -1L
    }
    knownPlanPath = pulse.planPath
    knownPlanEtag = pulse.planEtag
    schedule(pulse, epochChanged)
  }

  private fun schedule(pulse: PulseView, epochChanged: Boolean) {
    val conversationId = pulse.conversationId
    val stored = if (conversationId.isEmpty()) 0 else storedCount(conversationId)
    val finishedLive = watchingLiveId?.takeIf { it.isNotEmpty() && it != pulse.liveTurnId }
    val becomingStored = finishedLive != null
    val roomConversation = if (conversationId.isEmpty()) null else dao.conversation(conversationId)
    val etagDiffers = roomConversation?.etag != pulse.conversationEtag
    val countDiffers = (roomConversation?.turnCount ?: 0) != pulse.turnCount
    if (pulse.liveTurnId != null && pulse.liveItemId != null && followHead && itemTailDiffers(pulse, epochChanged)) {
      want(itemJob(pulse))
    }
    if (pulse.liveTurnId != null && outlineDiffers(pulse, epochChanged)) {
      want(outlineJob(pulse))
    }
    if (finishedLive != null) want(storedTurnJob(pulse, finishedLive, watchingLiveIndex))
    val missing = pulse.turnCount - stored - if (becomingStored) 1 else 0
    if (conversationId.isNotEmpty() && (epochChanged || missing > 0 || (etagDiffers || countDiffers) && !becomingStored)) {
      val from = if (epochChanged) 0 else stored
      want(turnPageJob(pulse, from))
    }
    if (pulse.planPath.isNotEmpty() && planDiffers(pulse)) want(planJob(pulse))
    if (pulse.planPath.isNotEmpty() && planScreenOpen && documentDiffers(pulse)) want(documentJob(pulse))
    if (pulse.listConversations != conversationsEtag) {
      want(listJob(pulse, FetchKind.ConversationList, "list:conversations", "conversations", pulse.listConversations))
    }
    if (pulse.listPlans != plansEtag) want(listJob(pulse, FetchKind.PlanList, "list:plans", "plans", pulse.listPlans))
    if (pulse.listTasks != tasksEtag) want(listJob(pulse, FetchKind.TaskList, "list:tasks", "tasks", pulse.listTasks))
    val approvalId = pulse.approvalId
    if (approvalId != null && approvalId != approvalFetchedId) want(approvalJob(pulse, approvalId))
    if (approvalId == null) approvalFetchedId = ""
    watchingLiveId = pulse.liveTurnId
    watchingLiveIndex = pulse.liveTurnIndex
  }

  private fun itemTailDiffers(pulse: PulseView, epochChanged: Boolean): Boolean {
    val itemId = pulse.liveItemId ?: return false
    val row = dao.item(itemId) ?: return true
    if (epochChanged || row.epoch != pulse.epoch) return true
    return row.revision != pulse.liveItemRev
  }

  private fun outlineDiffers(pulse: PulseView, epochChanged: Boolean): Boolean {
    if (epochChanged) return true
    return liveOutlineTurnId != pulse.liveTurnId || liveOutlineRev != pulse.liveTurnRev
  }

  private fun planDiffers(pulse: PulseView): Boolean {
    val row = dao.plan(endpoint, pulse.planPath) ?: return true
    return row.etag != pulse.planEtag
  }

  private fun documentDiffers(pulse: PulseView): Boolean {
    if (documentForEtag != pulse.planEtag) return true
    val row = dao.plan(endpoint, pulse.planPath) ?: return true
    return row.documentText.isEmpty() || row.etag != pulse.planEtag
  }

  private fun scheduleHistory(conversationId: String) {
    val from = storedCount(conversationId)
    want(FetchJob(
      key = "history:$conversationId:$from",
      rank = RankHistory,
      url = resource("v4", "conversations", conversationId, "turns", query = listOf("from" to from.toString())),
      kind = FetchKind.History,
      epoch = dao.host(endpoint)?.lastEpoch ?: "",
      conversationId = conversationId,
      turnId = "",
      turnIndex = from,
      itemId = "",
      planPath = "",
      planEtag = "",
      seq = 0L
    ))
  }

  private fun scheduleOpenDocument() {
    if (!planScreenOpen || knownPlanPath.isEmpty()) return
    if (documentForEtag == knownPlanEtag && dao.plan(endpoint, knownPlanPath)?.documentText?.isNotEmpty() == true) return
    val host = dao.host(endpoint)
    want(FetchJob(
      key = "plan-document:$knownPlanPath",
      rank = RankPlan,
      url = resource("v4", "plan", "document"),
      kind = FetchKind.PlanDocument,
      epoch = host?.lastEpoch ?: "",
      conversationId = "",
      turnId = "",
      turnIndex = 0,
      itemId = "",
      planPath = knownPlanPath,
      planEtag = knownPlanEtag,
      seq = 0L
    ))
  }

  private fun itemJob(pulse: PulseView): FetchJob {
    val itemId = pulse.liveItemId.orEmpty()
    val body = dao.item(itemId)?.body.orEmpty()
    val bytes = body.toByteArray(Charsets.UTF_8)
    val query = if (bytes.size >= TailCheckBytes) {
      listOf("from" to bytes.size.toString(), "check" to monitorHash(bytes, bytes.size - TailCheckBytes, TailCheckBytes))
    } else {
      listOf("from" to "0")
    }
    return FetchJob("item:$itemId", RankItem, resource("v4", "items", itemId, query = query), FetchKind.ItemTail,
      pulse.epoch, pulse.conversationId, pulse.liveTurnId.orEmpty(), pulse.liveTurnIndex, itemId, "", "", 0L)
  }

  private fun outlineJob(pulse: PulseView): FetchJob {
    val turnId = pulse.liveTurnId.orEmpty()
    jobOutlineRev["turn:$turnId:outline"] = pulse.liveTurnRev
    return FetchJob("turn:$turnId:outline", RankOutline,
      resource("v4", "turns", turnId, query = listOf("bodies" to "0")), FetchKind.LiveOutline,
      pulse.epoch, pulse.conversationId, turnId, pulse.liveTurnIndex, "", "", "", 0L)
  }

  private fun storedTurnJob(pulse: PulseView, turnId: String, index: Int): FetchJob {
    return FetchJob("turn:$turnId:stored", RankTurns, resource("v4", "turns", turnId, query = listOf("bodies" to "1")),
      FetchKind.StoredTurn, pulse.epoch, pulse.conversationId, turnId, index, "", "", pulse.conversationEtag, 0L)
  }

  private fun turnPageJob(pulse: PulseView, from: Int): FetchJob {
    return FetchJob("turns:${pulse.conversationId}", RankTurns,
      resource("v4", "conversations", pulse.conversationId, "turns", query = listOf("from" to from.toString())),
      FetchKind.TurnPage, pulse.epoch, pulse.conversationId, "", from, "", "", pulse.conversationEtag, 0L)
  }

  private fun planJob(pulse: PulseView): FetchJob {
    return FetchJob("plan:${pulse.planPath}", RankPlan, resource("v4", "plan"), FetchKind.Plan,
      pulse.epoch, pulse.conversationId, "", 0, "", pulse.planPath, pulse.planEtag, 0L)
  }

  private fun documentJob(pulse: PulseView): FetchJob {
    return FetchJob("plan-document:${pulse.planPath}", RankPlan, resource("v4", "plan", "document"), FetchKind.PlanDocument,
      pulse.epoch, pulse.conversationId, "", 0, "", pulse.planPath, pulse.planEtag, 0L)
  }

  private fun listJob(pulse: PulseView, kind: FetchKind, key: String, segment: String, etag: String): FetchJob {
    return FetchJob(key, RankLists, resource("v4", segment), kind, pulse.epoch, pulse.conversationId, "", 0, "", "", etag, 0L)
  }

  private fun approvalJob(pulse: PulseView, approvalId: String): FetchJob {
    return FetchJob("approval:$approvalId", RankApproval, resource("v4", "approval"), FetchKind.Approval,
      pulse.epoch, pulse.conversationId, "", 0, "", "", approvalId, 0L)
  }

  private fun want(job: FetchJob) {
    lock.withLock {
      if (job.key in inflight || job.key in pending) return
      val seq = jobSeq
      jobSeq += 1
      pending[job.key] = FetchJob(job.key, job.rank, job.url, job.kind, job.epoch, job.conversationId, job.turnId,
        job.turnIndex, job.itemId, job.planPath, job.planEtag, seq)
      ready.signalAll()
    }
  }

  private fun runJob(job: FetchJob) {
    val body = httpGet(job.url) ?: return
    inTransaction {
      when (job.kind) {
        FetchKind.ItemTail -> applyItem(job, body)
        FetchKind.LiveOutline -> applyOutline(job, body)
        FetchKind.StoredTurn -> applyStoredTurn(job, body)
        FetchKind.TurnPage, FetchKind.History -> applyTurnPage(job, body)
        FetchKind.Plan -> applyPlan(job, body)
        FetchKind.PlanDocument -> applyDocument(job, body)
        FetchKind.ConversationList -> applyConversationList(job, body)
        FetchKind.PlanList -> plansEtag = job.planEtag
        FetchKind.TaskList -> tasksEtag = job.planEtag
        FetchKind.Approval -> approvalFetchedId = job.planEtag
      }
    }
  }

  private fun applyItem(job: FetchJob, body: String) {
    val parsed = parseTail(body) ?: return
    val turn = dao.turn(job.turnId)
    if (turn != null && turn.outcome != LiveTurnOutcome && turn.etag.isNotEmpty()) return
    ensureConversation(job.conversationId, "", "", 0, keepCounts = true)
    ensureTurn(job.turnId, job.conversationId, job.turnIndex, LiveTurnOutcome)
    val existing = dao.item(parsed.id)
    val merged = mergeTail(existing?.body.orEmpty(), parsed.start, parsed.text)
    dao.replaceItem(ItemRow(
      id = parsed.id.ifEmpty { job.itemId },
      turnId = job.turnId,
      ordinal = existing?.ordinal ?: 0,
      kind = existing?.kind ?: "answer",
      state = parsed.state.ifEmpty { existing?.state ?: "running" },
      title = existing?.title ?: "",
      toolName = existing?.toolName ?: "",
      body = merged,
      revision = parsed.rev,
      epoch = job.epoch,
      byteLength = parsed.totalBytes
    ))
  }

  private fun applyOutline(job: FetchJob, body: String) {
    val parsed = parseTurn(body) ?: return
    val existing = dao.turn(parsed.id)
    if (existing != null && existing.outcome != LiveTurnOutcome && existing.etag.isNotEmpty()) return
    ensureConversation(job.conversationId, "", "", 0, keepCounts = true)
    saveTurn(TurnRow(
      id = parsed.id.ifEmpty { job.turnId },
      conversationId = job.conversationId,
      index = job.turnIndex,
      etag = parsed.etag,
      prompt = parsed.prompt,
      mode = parsed.mode,
      createdAt = parsed.createdAt,
      outcome = LiveTurnOutcome,
      duration = 0,
      errorText = parsed.error,
      clientCommandId = parsed.clientCommandId
    ))
    mergeOutlineItems(parsed.id.ifEmpty { job.turnId }, parsed.items, job.epoch)
    liveOutlineTurnId = parsed.id.ifEmpty { job.turnId }
    liveOutlineRev = jobOutlineRev[job.key] ?: liveOutlineRev
  }

  private val jobOutlineRev = HashMap<String, Long>()

  private fun applyStoredTurn(job: FetchJob, body: String) {
    val parsed = parseTurn(body) ?: return
    val turnId = parsed.id.ifEmpty { job.turnId }
    ensureConversation(job.conversationId, "", "", storedCount(job.conversationId).coerceAtLeast(1))
    val existing = dao.turn(turnId)
    if (existing != null && existing.etag.isNotEmpty() && existing.etag == parsed.etag && existing.outcome != LiveTurnOutcome) {
      if (watchingLiveId == turnId) watchingLiveId = null
      return
    }
    if (job.turnId.isNotEmpty() && job.turnId != turnId) dao.deleteTurn(job.turnId)
    dao.deleteItemsForTurn(turnId)
    saveTurn(TurnRow(
      id = turnId,
      conversationId = job.conversationId,
      index = existing?.index ?: job.turnIndex,
      etag = parsed.etag,
      prompt = parsed.prompt,
      mode = parsed.mode,
      createdAt = parsed.createdAt,
      outcome = if (parsed.error.isEmpty()) "" else "failed",
      duration = existing?.duration ?: 0,
      errorText = parsed.error,
      clientCommandId = parsed.clientCommandId.ifEmpty { existing?.clientCommandId ?: "" }
    ))
    writeItems(turnId, parsed.items, job.epoch, replaceBodies = true)
    ensureConversation(job.conversationId, "", job.planEtag, storedCount(job.conversationId))
    if (watchingLiveId == turnId || watchingLiveId == job.turnId) watchingLiveId = null
  }

  private fun applyTurnPage(job: FetchJob, body: String) {
    val page = parseTurnPage(body) ?: return
    val conversationId = page.id.ifEmpty { job.conversationId }
    ensureConversation(conversationId, "", page.etag, page.from)
    page.turns.forEachIndexed { offset, parsed ->
      val existing = dao.turn(parsed.id)
      if (existing != null && existing.etag.isNotEmpty() && existing.etag == parsed.etag) return@forEachIndexed
      val index = page.from + offset
      dao.deleteItemsForTurn(parsed.id)
      saveTurn(TurnRow(
        id = parsed.id,
        conversationId = conversationId,
        index = index,
        etag = parsed.etag,
        prompt = parsed.prompt,
        mode = parsed.mode,
        createdAt = parsed.createdAt,
        outcome = if (parsed.live) LiveTurnOutcome else if (parsed.error.isEmpty()) "" else "failed",
        duration = 0,
        errorText = parsed.error,
        clientCommandId = parsed.clientCommandId
      ))
      writeItems(parsed.id, parsed.items, job.epoch, replaceBodies = true)
    }
    val stored = storedCount(conversationId)
    val caughtUp = page.next == null
    val etag = if (caughtUp && page.etag.isNotEmpty()) page.etag else dao.conversation(conversationId)?.etag ?: ""
    val count = if (caughtUp && page.turns.isEmpty()) page.from else stored
    val title = dao.conversation(conversationId)?.title ?: ""
    ensureConversation(conversationId, title, etag, count)
  }

  private fun applyPlan(job: FetchJob, body: String) {
    val parsed = parseJson(body) ?: return
    ensureHost(job.epoch, dao.host(endpoint)?.lastRev ?: 0L)
    val etag = parsed.text("etag").ifEmpty { job.planEtag }
    val existing = dao.plan(endpoint, job.planPath)
    val document = if (documentForEtag == etag) existing?.documentText.orEmpty() else ""
    if (documentForEtag != etag) documentForEtag = ""
    dao.replacePlan(PlanCacheRow(
      endpoint,
      parsed.text("path").ifEmpty { job.planPath },
      parsed.text("title"),
      etag,
      rawJsonField(body, "rows").ifEmpty { "[]" },
      document
    ))
  }

  private fun applyDocument(job: FetchJob, body: String) {
    ensureHost(job.epoch, dao.host(endpoint)?.lastRev ?: 0L)
    val existing = dao.plan(endpoint, job.planPath)
    dao.replacePlan(PlanCacheRow(
      endpoint,
      job.planPath,
      existing?.title ?: "",
      job.planEtag.ifEmpty { existing?.etag ?: "" },
      existing?.rowsJson ?: "[]",
      body
    ))
    documentForEtag = job.planEtag
  }

  private fun applyConversationList(job: FetchJob, body: String) {
    val root = parseJson(body) ?: return
    val rows = when (root) {
      is JsonValue.Arr -> root.values
      else -> root.array("conversations")
    }
    ensureHost(job.epoch, dao.host(endpoint)?.lastRev ?: 0L)
    for (row in rows) {
      val id = row.text("id")
      if (id.isEmpty()) continue
      val existing = dao.conversation(id)
      val current = row.bool("current")
      if (existing == null) {
        dao.replaceConversation(ConversationRow(
          id, endpoint, row.text("title"), "", 0, current, parseMonitorTime(row.text("created_at")).takeIf { it > 0L } ?: clock()
        ))
      } else if (id == job.conversationId) {
        dao.updateConversation(id, row.text("title").ifEmpty { existing.title }, existing.etag, existing.turnCount, current, existing.updatedAt)
      } else {
        dao.updateConversation(id, row.text("title"), row.text("etag"), row.int("turn_count"), current, existing.updatedAt)
      }
    }
    conversationsEtag = job.planEtag
  }

  private fun mergeOutlineItems(turnId: String, items: List<ParsedItem>, epoch: String) {
    val previous = dao.items(turnId).associateBy { it.id }
    val seen = HashSet<String>()
    items.forEachIndexed { ordinal, item ->
      seen += item.id
      val old = previous[item.id]
      dao.replaceItem(ItemRow(
        id = item.id,
        turnId = turnId,
        ordinal = ordinal,
        kind = item.kind.ifEmpty { old?.kind ?: "" },
        state = item.state.ifEmpty { old?.state ?: "" },
        title = item.title.ifEmpty { old?.title ?: "" },
        toolName = item.toolName.ifEmpty { old?.toolName ?: "" },
        body = old?.body ?: item.body.orEmpty(),
        revision = item.revision,
        epoch = epoch,
        byteLength = if (old != null && old.body.isNotEmpty()) old.byteLength else item.bytes
      ))
    }
    for (old in previous.values) if (old.id !in seen) dao.deleteItem(old.id)
  }

  private fun writeItems(turnId: String, items: List<ParsedItem>, epoch: String, replaceBodies: Boolean) {
    items.forEachIndexed { ordinal, item ->
      dao.replaceItem(ItemRow(
        id = item.id,
        turnId = turnId,
        ordinal = ordinal,
        kind = item.kind,
        state = item.state,
        title = item.title,
        toolName = item.toolName,
        body = if (replaceBodies) item.body.orEmpty() else "",
        revision = item.revision,
        epoch = epoch,
        byteLength = item.bytes.takeIf { it > 0L } ?: item.body.orEmpty().toByteArray(Charsets.UTF_8).size.toLong()
      ))
    }
  }

  private fun ensureTurn(turnId: String, conversationId: String, index: Int, outcome: String) {
    if (turnId.isEmpty() || dao.turn(turnId) != null) return
    dao.replaceTurn(TurnRow(turnId, conversationId, index, "", "", "", 0L, outcome, 0, "", ""))
  }

  private fun saveTurn(row: TurnRow) {
    if (dao.turn(row.id) == null) dao.replaceTurn(row)
    else dao.updateTurn(row.id, row.index, row.etag, row.prompt, row.mode, row.createdAt, row.outcome, row.duration, row.errorText, row.clientCommandId)
  }

  private fun ensureConversation(id: String, title: String, etag: String, turnCount: Int, keepCounts: Boolean = false) {
    if (id.isEmpty()) return
    ensureHost(dao.host(endpoint)?.lastEpoch ?: "", dao.host(endpoint)?.lastRev ?: 0L)
    val existing = dao.conversation(id)
    val nextEtag = if (keepCounts && existing != null) existing.etag else etag
    val nextCount = if (keepCounts && existing != null) existing.turnCount else turnCount
    if (existing == null) {
      dao.replaceConversation(ConversationRow(id, endpoint, title, nextEtag, nextCount, true, clock()))
    } else {
      dao.updateConversation(id, title.ifEmpty { existing.title }, nextEtag, nextCount, true, existing.updatedAt)
    }
    dao.clearCurrentExcept(endpoint, id)
  }

  private fun saveHost(epoch: String, rev: Long) {
    val existing = dao.host(endpoint)
    if (existing == null) dao.replaceHost(HostRow(endpoint, "", endpoint, epoch, rev))
    else if (existing.lastEpoch != epoch || existing.lastRev != rev) dao.updateHostCursor(endpoint, epoch, rev)
  }

  private fun ensureHost(epoch: String, rev: Long) {
    if (dao.host(endpoint) == null) dao.replaceHost(HostRow(endpoint, "", endpoint, epoch, rev))
  }

  private fun storedCount(conversationId: String): Int {
    return dao.turns(conversationId).count { it.outcome != LiveTurnOutcome }
  }

  private fun inTransaction(block: () -> Unit) {
    dao.write(block)
  }

  private fun httpGet(url: String): String? {
    val builder = Request.Builder().url(url).get()
    if (token.isNotEmpty()) builder.header("Authorization", "Bearer $token")
    return try {
      client.newCall(builder.build()).execute().use { response ->
        if (response.code !in 200..299) null else response.body?.string().orEmpty()
      }
    } catch (error: Exception) {
      null
    }
  }

  private fun resource(vararg segments: String, query: List<Pair<String, String>> = emptyList()): String {
    val builder = baseUrl.newBuilder()
    for (segment in segments) builder.addPathSegment(segment)
    for ((key, value) in query) builder.addQueryParameter(key, value)
    return builder.build().toString()
  }
}

internal fun monitorHash(bytes: ByteArray, start: Int = 0, count: Int = bytes.size - start): String {
  var hash = 14695981039346656037uL
  val prime = 1099511628211uL
  val end = (start + count).coerceAtMost(bytes.size)
  var index = start.coerceAtLeast(0)
  while (index < end) {
    hash = hash xor bytes[index].toUByte().toULong()
    hash *= prime
    index += 1
  }
  return hash.toString(16).padStart(16, '0')
}

internal fun mergeTail(existing: String, start: Int, text: String): String {
  if (start <= 0) return text
  val bytes = existing.toByteArray(Charsets.UTF_8)
  if (start > bytes.size) return text
  var end = start
  while (end > 0 && end < bytes.size && (bytes[end].toInt() and 0xC0) == 0x80) end -= 1
  return bytes.copyOfRange(0, end).toString(Charsets.UTF_8) + text
}

internal fun parseMonitorTime(text: String): Long {
  if (text.isEmpty()) return 0L
  return try {
    java.time.Instant.parse(text).toEpochMilli()
  } catch (error: Exception) {
    0L
  }
}

internal data class PulseView(
  val epoch: String,
  val rev: Long,
  val conversationId: String,
  val conversationTitle: String,
  val conversationEtag: String,
  val turnCount: Int,
  val liveTurnId: String?,
  val liveTurnIndex: Int,
  val liveTurnRev: Long,
  val liveItemId: String?,
  val liveItemKind: String,
  val liveItemState: String,
  val liveItemRev: Long,
  val liveItemBytes: Long,
  val planPath: String,
  val planEtag: String,
  val listConversations: String,
  val listPlans: String,
  val listTasks: String,
  val approvalId: String?
)

internal fun parsePulse(json: String): PulseView? {
  val root = parseJson(json) ?: return null
  val conversation = root.field("conversation")
  val live = root.field("live")
  val liveObj = live as? JsonValue.Obj
  val item = liveObj?.field("item")
  val itemObj = item as? JsonValue.Obj
  val plan = root.field("plan")
  val lists = root.field("lists")
  val approval = root.field("approval") as? JsonValue.Obj
  return PulseView(
    epoch = root.text("epoch"),
    rev = root.long("rev"),
    conversationId = conversation?.text("id") ?: "",
    conversationTitle = conversation?.text("title") ?: "",
    conversationEtag = conversation?.text("etag") ?: "",
    turnCount = conversation?.int("turn_count") ?: 0,
    liveTurnId = liveObj?.text("turn_id")?.ifEmpty { null },
    liveTurnIndex = liveObj?.int("turn_index") ?: 0,
    liveTurnRev = liveObj?.long("rev") ?: 0L,
    liveItemId = itemObj?.text("id")?.ifEmpty { null },
    liveItemKind = itemObj?.text("kind") ?: "",
    liveItemState = itemObj?.text("state") ?: "",
    liveItemRev = itemObj?.long("rev") ?: 0L,
    liveItemBytes = itemObj?.long("bytes") ?: 0L,
    planPath = plan?.text("path") ?: "",
    planEtag = plan?.text("etag") ?: "",
    listConversations = lists?.text("conversations") ?: "",
    listPlans = lists?.text("plans") ?: "",
    listTasks = lists?.text("tasks") ?: "",
    approvalId = approval?.text("id")?.ifEmpty { null }
  )
}

internal data class ParsedItem(
  val id: String,
  val kind: String,
  val state: String,
  val title: String,
  val toolName: String,
  val revision: Long,
  val bytes: Long,
  val body: String?
)

internal data class ParsedTurn(
  val id: String,
  val etag: String,
  val live: Boolean,
  val mode: String,
  val prompt: String,
  val createdAt: Long,
  val error: String,
  val clientCommandId: String,
  val items: List<ParsedItem>
)

internal data class ParsedTurnPage(
  val id: String,
  val etag: String,
  val from: Int,
  val turns: List<ParsedTurn>,
  val next: Int?
)

internal data class ParsedTail(
  val id: String,
  val rev: Long,
  val state: String,
  val totalBytes: Long,
  val start: Int,
  val text: String
)

internal fun parseTurn(json: String): ParsedTurn? {
  val root = parseJson(json) ?: return null
  return turnFrom(root)
}

internal fun parseTurnPage(json: String): ParsedTurnPage? {
  val root = parseJson(json) ?: return null
  val next = root.field("next")
  return ParsedTurnPage(
    id = root.text("id"),
    etag = root.text("etag"),
    from = root.int("from"),
    turns = root.array("turns").mapNotNull { value -> if (value is JsonValue.Obj) turnFrom(value) else null },
    next = if (next == null || next is JsonValue.Null) null else next.asLong(-1L).toInt().takeIf { it >= 0 }
  )
}

internal fun parseTail(json: String): ParsedTail? {
  val root = parseJson(json) ?: return null
  return ParsedTail(root.text("id"), root.long("rev"), root.text("state"), root.long("total_bytes"), root.int("start"), root.text("text"))
}

private fun turnFrom(root: JsonValue): ParsedTurn {
  return ParsedTurn(
    id = root.text("id"),
    etag = root.text("etag"),
    live = root.bool("live"),
    mode = root.text("mode"),
    prompt = root.text("prompt"),
    createdAt = parseMonitorTime(root.text("created_at")),
    error = root.text("error"),
    clientCommandId = root.text("client_command_id"),
    items = root.array("items").map { item ->
      ParsedItem(
        id = item.text("id"),
        kind = item.text("kind"),
        state = item.text("state"),
        title = item.text("title"),
        toolName = item.text("tool_name"),
        revision = item.long("rev"),
        bytes = item.long("bytes"),
        body = if (item.field("body") == null) null else item.text("body")
      )
    }
  )
}
