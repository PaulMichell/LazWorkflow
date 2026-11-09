package computing.michell.monitor.data

/* Baseline reconcile, held appends, and the state channel (c) 2026 Michell Computing.

   Content commits move the cursor. A block fetch does not. State does not.
   An append that does not meet the stored body is an obligation, not a guess. */

import computing.michell.monitor.protocol.ApprovalNotice
import computing.michell.monitor.protocol.ConversationChoice
import computing.michell.monitor.protocol.EmptyPrefixHash
import computing.michell.monitor.protocol.JsonValue
import computing.michell.monitor.protocol.ModelChoice
import computing.michell.monitor.protocol.MonitorEvent
import computing.michell.monitor.protocol.OpenBlockBody
import computing.michell.monitor.protocol.OutlineTurn
import computing.michell.monitor.protocol.PermissionChoice
import computing.michell.monitor.protocol.PlanChoice
import computing.michell.monitor.protocol.PlanRow
import computing.michell.monitor.protocol.ReasoningChoice
import computing.michell.monitor.protocol.SyncFrame
import computing.michell.monitor.protocol.TargetChoice
import computing.michell.monitor.protocol.arrayField
import computing.michell.monitor.protocol.flagField
import computing.michell.monitor.protocol.intField
import computing.michell.monitor.protocol.jsonObject
import computing.michell.monitor.protocol.longField
import computing.michell.monitor.protocol.prefixHash
import computing.michell.monitor.protocol.textField
import computing.michell.monitor.protocol.utf8Length
import computing.michell.monitor.ui.MonitorUi
import java.time.Instant

data class BlockRepair(
  val host: String,
  val conversation: String,
  val blockId: String,
  val revision: Long,
  val expectedLength: Int,
  val missingBody: Boolean,
  val hash: String,
  val stale: Boolean,
  val requestId: String,
  val fetchedBody: String = ""
)

data class HeldAppend(
  val host: String,
  val conversation: String,
  val blockId: String,
  val seq: Long,
  val offset: Int,
  val text: String,
  val streamId: String
)

data class HoldAppend(
  val block: BlockRecord?,
  val repair: BlockRepair?,
  val held: HeldAppend?,
  val fetch: BlockFetch?,
  val clearHeld: Boolean
)

data class BaselineCommit(
  val conversationId: String,
  val streamId: String,
  val seq: Long,
  val title: String,
  val projectRoot: String,
  val turns: List<OutlineTurn>,
  val openBlock: OpenBlockBody?
)

data class BaselinePlan(
  val conversation: ConversationRecord,
  val upsertTurns: List<TurnRecord>,
  val upsertBlocks: List<BlockRecord>,
  val deleteTurnIds: List<String>,
  val deleteBlockIds: List<String>,
  val repairs: List<BlockRepair>,
  val clearRepairIds: List<String>,
  val fetches: List<BlockFetch>,
  val openBlockId: String = ""
)

sealed class FetchFinish {
  data class Applied(
    val body: String,
    val revision: Long,
    val dropSeqs: List<Long>,
    val missingBody: Boolean,
    val requestId: String
  ) : FetchFinish()
  data class Again(val offset: Int, val prefixHash: String, val requestId: String, val revision: Long) : FetchFinish()
  data object Ignore : FetchFinish()
}

fun fetchRequestId(blockId: String, mark: Long): String {
  val cleaned = blockId.filter { ch -> ch.isLetterOrDigit() || ch == '-' || ch == '_' }.take(40)
  val stem = if (cleaned.isEmpty()) "block" else cleaned
  return "bg-$stem-$mark"
}

/** A mismatch, or a block already fetching, does not paint. The first mismatch asks once. */
fun holdAppend(
  host: String,
  conversationId: String,
  event: MonitorEvent.BlockAppend,
  block: BlockRecord?,
  repair: BlockRepair?
): HoldAppend {
  val fetching = repair?.missingBody == true
  val length = if (block == null) 0 else utf8Length(block.body)
  if (!fetching && block != null && length == event.offset) {
    return HoldAppend(block.copy(body = block.body + event.text), null, null, null, false)
  }
  val prefix = if (fetching) "" else block?.body.orEmpty()
  val prefixLength = if (fetching) repair?.expectedLength ?: length else length
  val hash = if (fetching) repair?.hash.orEmpty() else prefixHash(prefix)
  val request = repair?.requestId?.ifEmpty { null } ?: fetchRequestId(event.blockId, event.seq)
  val nextRepair = BlockRepair(
    host,
    conversationId,
    event.blockId,
    if (repair != null && repair.revision != 0L) repair.revision else 0L,
    if (fetching) prefixLength else length,
    true,
    if (hash.isEmpty()) EmptyPrefixHash else hash,
    repair?.stale ?: false,
    request,
    repair?.fetchedBody.orEmpty()
  )
  val held = HeldAppend(host, conversationId, event.blockId, event.seq, event.offset, event.text, event.streamId)
  val fetch = if (fetching) null else BlockFetch(conversationId, event.blockId, length, nextRepair.hash, request)
  return HoldAppend(block, nextRepair, held, fetch, false)
}

/** A deferred replace is a fetch. A body on the event is the new text and drops held appends. */
fun holdReplace(
  host: String,
  conversationId: String,
  event: MonitorEvent.BlockReplace,
  block: BlockRecord?,
  repair: BlockRepair?
): HoldAppend {
  if (!event.deferred) {
    if (block == null) {
      val request = fetchRequestId(event.blockId, event.seq)
      val missing = BlockRepair(
        host, conversationId, event.blockId, event.revision, 0, true, EmptyPrefixHash, false, request, ""
      )
      return HoldAppend(null, missing, null, BlockFetch(conversationId, event.blockId, 0, EmptyPrefixHash, request), true)
    }
    return HoldAppend(block.copy(body = event.body), null, null, null, true)
  }
  val request = fetchRequestId(event.blockId, event.seq)
  val next = BlockRepair(
    host,
    conversationId,
    event.blockId,
    event.revision,
    0,
    true,
    EmptyPrefixHash,
    true,
    request,
    ""
  )
  return HoldAppend(block, next, null, BlockFetch(conversationId, event.blockId, 0, EmptyPrefixHash, request), true)
}

fun reconcileBaseline(
  host: String,
  nowMs: Long,
  existing: ConversationRecord?,
  turns: List<TurnRecord>,
  blocks: List<BlockRecord>,
  commit: BaselineCommit
): BaselinePlan? {
  if (commit.turns.isEmpty()) return null
  val namedTurns = commit.turns.associateBy { turn -> turn.turnId }
  val namedBlocks = HashMap<String, computing.michell.monitor.protocol.OutlineBlock>()
  for (turn in commit.turns) {
    for (block in turn.blocks) namedBlocks[block.blockId] = block
  }
  val turnById = turns.associateBy { turn -> turn.turnId }
  val blockById = blocks.associateBy { block -> block.blockId }
  val upsertTurns = ArrayList<TurnRecord>()
  val upsertBlocks = ArrayList<BlockRecord>()
  val repairs = ArrayList<BlockRepair>()
  val clearRepairs = ArrayList<String>()
  val fetches = ArrayList<BlockFetch>()
  val open = commit.openBlock
  val ordinals = HashMap<String, Int>()
  for (outline in commit.turns) {
    val previous = turnById[outline.turnId]
    upsertTurns += TurnRecord(
      host,
      commit.conversationId,
      outline.turnId,
      outline.turnIndex,
      previous?.mode ?: "",
      previous?.prompt?.ifEmpty { outline.promptPreview } ?: outline.promptPreview,
      previous?.createdAt ?: "",
      previous?.outcome ?: "",
      previous?.durationMs ?: 0,
      previous?.errorText ?: ""
    )
    for (named in outline.blocks) {
      val ordinal = ordinals[outline.turnId] ?: 0
      ordinals[outline.turnId] = ordinal + 1
      val cached = blockById[named.blockId]
      val delivered = open != null && open.blockId == named.blockId && openBlockDelivered(open)
      val cachedHash = if (cached == null) "" else prefixHash(cached.body)
      val hashMatches = named.hash.isNotEmpty() && cached != null && cachedHash == named.hash
      // A body sent with the outline is the desktop's text now. Without it the phone shows an empty item until a fetch.
      val inline = named.body?.takeIf { text -> named.hash.isEmpty() || prefixHash(text) == named.hash }
      val body = when {
        delivered -> open?.body.orEmpty()
        inline != null -> inline
        else -> cached?.body.orEmpty()
      }
      val isOpen = open != null && open.blockId == named.blockId
      val missing = !delivered && inline == null && !hashMatches
      val requestOpen = isOpen && !delivered && inline == null
      upsertBlocks += BlockRecord(
        host,
        commit.conversationId,
        outline.turnId,
        named.blockId,
        ordinal,
        named.kind.ifEmpty { cached?.kind ?: "answer" },
        named.title.ifEmpty { cached?.title ?: "" },
        body,
        named.state.ifEmpty { cached?.state ?: "ok" }
      )
      if (missing || requestOpen) {
        val offset = if (hashMatches) utf8Length(cached?.body.orEmpty()) else 0
        val hash = if (offset > 0) cachedHash else EmptyPrefixHash
        val request = fetchRequestId(named.blockId, commit.seq)
        repairs += BlockRepair(
          host, commit.conversationId, named.blockId, named.revision, offset, true, hash, missing, request, ""
        )
        fetches += BlockFetch(commit.conversationId, named.blockId, offset, hash, request)
      } else {
        clearRepairs += named.blockId
      }
    }
  }
  val deleteTurns = turns.map { turn -> turn.turnId }.filter { id -> id !in namedTurns }
  val deleteBlocks = blocks.map { block -> block.blockId }.filter { id -> id !in namedBlocks }
  val row = ConversationRecord(
    commit.conversationId,
    host,
    commit.projectRoot.ifEmpty { existing?.projectRoot ?: "" },
    commit.title.ifEmpty { existing?.title ?: "" },
    commit.streamId,
    commit.seq,
    nowMs,
    existing?.pinned ?: false
  )
  return BaselinePlan(row, upsertTurns, upsertBlocks, deleteTurns, deleteBlocks, repairs, clearRepairs, fetches, open?.blockId.orEmpty())
}

/** An omitted or truncated open block is not the stored body. The phone asks for it. */
private fun openBlockDelivered(open: OpenBlockBody): Boolean {
  if (open.body.isEmpty()) return false
  if (open.bodyBytes > 0 && utf8Length(open.body) != open.bodyBytes) return false
  if (open.hash.isNotEmpty() && prefixHash(open.body) != open.hash) return false
  return true
}

fun planStateRevision(valueJson: String): String {
  val value = jsonObject(valueJson) ?: return ""
  return value.textField("revision").orEmpty()
}

fun finishFetch(
  block: BlockRecord?,
  repair: BlockRepair,
  held: List<HeldAppend>,
  pieces: Map<Int, String>,
  revision: Long,
  hasRevision: Boolean,
  totalBytes: Int,
  ref: String,
  nowMark: Long
): FetchFinish {
  if (ref.isNotEmpty() && repair.requestId.isNotEmpty() && ref != repair.requestId) return FetchFinish.Ignore
  if (!repair.missingBody && repair.requestId.isEmpty()) return FetchFinish.Ignore
  if (hasRevision && repair.revision != 0L && revision != repair.revision) {
    return FetchFinish.Again(0, EmptyPrefixHash, fetchRequestId(repair.blockId, nowMark), 0L)
  }
  val prefix = block?.body.orEmpty()
  val restarted = pieces.containsKey(0)
  val assembled = if (restarted) joinPieces(pieces, 0) else {
    val tail = joinPieces(pieces, repair.expectedLength)
    if (tail == null || utf8Length(prefix) != repair.expectedLength) null else prefix + tail
  }
  if (assembled == null || utf8Length(assembled) != totalBytes) {
    return FetchFinish.Again(0, EmptyPrefixHash, fetchRequestId(repair.blockId, nowMark), 0L)
  }
  val kept = held.filter { row -> row.blockId == repair.blockId && row.offset + utf8Length(row.text) > totalBytes }
    .sortedBy { row -> row.offset }
  val dropped = held.filter { row -> row.blockId == repair.blockId && row.seq !in kept.map { item -> item.seq } }
    .map { row -> row.seq }
  var body = assembled
  var length = utf8Length(body)
  val consumed = ArrayList<Long>()
  for (row in kept) {
    if (row.offset != length) break
    body += row.text
    length += utf8Length(row.text)
    consumed += row.seq
  }
  val stillHeld = kept.size - consumed.size
  return FetchFinish.Applied(
    body,
    if (hasRevision) revision else repair.revision,
    dropped + consumed,
    stillHeld > 0,
    repair.requestId
  )
}

fun joinPieces(pieces: Map<Int, String>, start: Int): String? {
  var at = start
  val out = StringBuilder()
  var saw = false
  for ((offset, text) in pieces.toSortedMap()) {
    if (offset < start) continue
    if (offset != at) return null
    out.append(text)
    at += utf8Length(text)
    saw = true
  }
  if (!saw) return null
  return out.toString()
}

/** Latest value of one key. It does not move the content cursor. */
fun applyStateValue(ui: MonitorUi, key: String, valueJson: String): MonitorUi {
  if (key == "approval") return applyApprovalState(ui, valueJson)
  val value = jsonObject(valueJson) ?: return ui
  return when (key) {
    "status" -> {
      val started = value.textField("started_at")?.let { startedAtMillis(it) }
      ui.copy(
        statusBusy = value.flagField("busy") ?: ui.statusBusy,
        planRunning = value.flagField("plan_running") ?: ui.planRunning,
        activityStartedMs = when {
          value.flagField("busy") == false && value.flagField("sending") == false -> 0L
          started != null -> started
          else -> ui.activityStartedMs
        },
        view = ui.view.copy(
          busy = value.flagField("busy") ?: ui.view.busy,
          sending = value.flagField("sending") ?: ui.view.sending,
          planRunning = value.flagField("plan_running") ?: ui.view.planRunning,
          phase = value.textField("phase") ?: ui.view.phase,
          statusText = value.textField("status_text") ?: ui.view.statusText,
          canSend = value.flagField("can_send") ?: ui.view.canSend,
          canSteer = value.flagField("can_steer") ?: ui.view.canSteer,
          canStop = value.flagField("can_stop") ?: ui.view.canStop,
          canChangeMode = value.flagField("can_change_mode") ?: ui.view.canChangeMode,
          errorText = value.textField("error_text") ?: ui.view.errorText
        )
      )
    }
    "session" -> ui.copy(view = ui.view.copy(
      model = value.textField("model") ?: ui.view.model,
      backend = value.textField("backend") ?: ui.view.backend,
      signedIn = value.flagField("signed_in") ?: ui.view.signedIn,
      effort = value.textField("effort") ?: ui.view.effort,
      skill = value.textField("skill") ?: ui.view.skill,
      contextText = value.textField("context_text") ?: ui.view.contextText,
      remoteApproval = value.flagField("remote_approval") ?: ui.view.remoteApproval,
      approvalCaption = value.textField("approval_caption") ?: ui.view.approvalCaption
    ))
    "mode" -> ui.copy(view = ui.view.copy(
      mode = value.textField("mode") ?: ui.view.mode,
      modeLocked = value.flagField("locked") ?: ui.view.modeLocked
    ))
    "target" -> ui.copy(view = ui.view.copy(
      targetKind = value.textField("kind") ?: ui.view.targetKind,
      targetDisplay = value.textField("display") ?: ui.view.targetDisplay,
      targetRoot = value.textField("root") ?: ui.view.targetRoot
    ), projectRoot = value.textField("root") ?: ui.projectRoot)
    "targets" -> ui.copy(
      targetCurrent = value.textField("current") ?: ui.targetCurrent,
      targetChoices = choicePaths(value) ?: ui.targetChoices
    )
    "conversation" -> {
      val id = value.textField("id")
      if (id.isNullOrEmpty() || id == "current") ui
      else ui.copy(conversationId = id, conversationTitle = value.textField("title") ?: ui.conversationTitle)
    }
    "conversations" -> ui.copy(
      conversationCurrent = value.textField("current") ?: ui.conversationCurrent,
      conversationsTruncated = value.flagField("truncated") ?: ui.conversationsTruncated,
      conversationChoices = conversationChoices(value) ?: ui.conversationChoices
    )
    "models" -> ui.copy(
      modelBackend = value.textField("backend") ?: ui.modelBackend,
      modelNote = value.textField("note") ?: ui.modelNote,
      modelChoices = idChoices(value).map { ModelChoice(it.first, it.second) }.ifEmpty { ui.modelChoices },
      view = ui.view.copy(model = value.textField("current") ?: ui.view.model)
    )
    "reasoning" -> ui.copy(
      reasoningCurrent = value.textField("current") ?: ui.reasoningCurrent,
      reasoningNote = value.textField("note") ?: ui.reasoningNote,
      reasoningChoices = idChoices(value).map { ReasoningChoice(it.first, it.second) }.ifEmpty { ui.reasoningChoices }
    )
    "permissions" -> ui.copy(
      permissionCurrent = value.textField("current") ?: ui.permissionCurrent,
      permissionNote = value.textField("note") ?: ui.permissionNote,
      permissionChoices = idChoices(value).map { PermissionChoice(it.first, it.second) }.ifEmpty { ui.permissionChoices }
    )
    "plan" -> {
      val path = value.textField("path") ?: ui.planPath
      val title = value.textField("title") ?: ui.planTitle
      val running = value.flagField("running") ?: ui.planRunning
      val rows = planRows(value) ?: ui.planRows
      ui.copy(
        planPath = path,
        planTitle = title,
        planRunning = running,
        planRows = rows,
        planRevision = value.textField("revision") ?: ui.planRevision,
        view = ui.view.copy(planPath = path, planTitle = title, planRunning = running)
      )
    }
    "plan_choices" -> ui.copy(planChoices = choicePaths(value)?.map { PlanChoice(it.path, it.caption) } ?: ui.planChoices)
    else -> ui
  }
}

fun applyApprovalState(ui: MonitorUi, valueJson: String): MonitorUi {
  val value = jsonObject(valueJson) ?: return ui
  val active = value.flagField("active") ?: false
  if (!active) return ui.copy(approval = null, approvalOpen = false)
  val notice = ApprovalNotice(
    true,
    value.textField("tool_id").orEmpty(),
    value.textField("tool_name").orEmpty(),
    value.textField("summary").orEmpty(),
    value.textField("mode_caption").orEmpty(),
    value.flagField("decisions_accepted") ?: false
  )
  return ui.copy(approval = notice, approvalOpen = true)
}

class BaselineStage {
  private var open = false
  private var failed = false
  private var conversationId = ""
  private var streamId = ""
  private var title = ""
  private var projectRoot = ""
  private var pageCount = 0
  private var pages = 0
  private val turns = ArrayList<OutlineTurn>()
  private var openBlock: OpenBlockBody? = null

  fun begin(frame: SyncFrame.SnapshotBegin) {
    open = true
    failed = false
    conversationId = frame.conversationId
    streamId = frame.streamId
    title = frame.title
    projectRoot = frame.projectRoot
    pageCount = frame.pageCount
    pages = 0
    turns.clear()
    turns.addAll(frame.turns)
    openBlock = frame.openBlock
  }

  /** False when the page is not this baseline. A turn body page is not an outline page. */
  fun page(frame: SyncFrame.SnapshotPage): Boolean {
    if (!open || failed) return false
    if (frame.conversationId.isNotEmpty() && frame.conversationId != conversationId) {
      failed = true
      return false
    }
    if (frame.streamId.isNotEmpty() && frame.streamId != streamId) {
      failed = true
      return false
    }
    if (frame.turns.isEmpty()) return true
    turns.addAll(frame.turns)
    pages += 1
    return true
  }

  fun end(frame: SyncFrame.SnapshotEnd): BaselineCommit? {
    if (!open || failed || frame.conversationId != conversationId || frame.streamId != streamId || pages < pageCount) {
      open = false
      failed = true
      return null
    }
    open = false
    if (turns.isEmpty()) return null
    return BaselineCommit(conversationId, streamId, frame.seq, title, projectRoot, turns.toList(), openBlock)
  }
}

class StateChunkAssembly {
  private class Open(val count: Int, val parts: MutableMap<Int, String>)
  private val open = HashMap<String, Open>()

  fun accept(chunk: SyncFrame.StateChunk): SyncFrame.State? {
    val current = open[chunk.key]
    val item = if (current == null || current.count != chunk.partCount) Open(chunk.partCount, linkedMapOf()) else current
    if (chunk.part in item.parts) return null
    item.parts[chunk.part] = chunk.data
    if (item.parts.size < item.count) {
      open[chunk.key] = item
      return null
    }
    open.remove(chunk.key)
    val joined = StringBuilder()
    for (index in 1..item.count) joined.append(item.parts[index] ?: return null)
    return SyncFrame.State(chunk.key, joined.toString())
  }
}

private fun startedAtMillis(text: String): Long? {
  if (text.isEmpty()) return null
  return try {
    Instant.parse(text).toEpochMilli()
  } catch (error: Exception) {
    null
  }
}

private fun choicePaths(value: JsonValue.Obj): List<TargetChoice>? {
  val items = value.arrayField("choices") ?: return null
  val rows = ArrayList<TargetChoice>()
  for (item in items) {
    val row = item as? JsonValue.Obj ?: continue
    val path = row.textField("path") ?: row.textField("id") ?: continue
    rows += TargetChoice(path, row.textField("caption") ?: path)
  }
  return rows
}

private fun conversationChoices(value: JsonValue.Obj): List<ConversationChoice>? {
  val items = value.arrayField("choices") ?: return null
  val current = value.textField("current").orEmpty()
  val rows = ArrayList<ConversationChoice>()
  for (item in items) {
    val row = item as? JsonValue.Obj ?: continue
    val id = row.textField("path") ?: row.textField("id") ?: continue
    rows += ConversationChoice(id, row.textField("caption") ?: row.textField("title") ?: id, id == current)
  }
  return rows
}

private fun idChoices(value: JsonValue.Obj): List<Pair<String, String>> {
  val items = value.arrayField("choices") ?: return emptyList()
  val rows = ArrayList<Pair<String, String>>()
  for (item in items) {
    val row = item as? JsonValue.Obj ?: continue
    val id = row.textField("path") ?: row.textField("id") ?: continue
    rows += id to (row.textField("caption") ?: id)
  }
  return rows
}

private fun planRows(value: JsonValue.Obj): List<PlanRow>? {
  val items = value.arrayField("rows") ?: return null
  val rows = ArrayList<PlanRow>()
  for (item in items) {
    val row = item as? JsonValue.Obj ?: continue
    val index = row.intField("index") ?: continue
    rows += PlanRow(
      index,
      row.intField("level") ?: 0,
      row.textField("title").orEmpty(),
      row.textField("parent_title").orEmpty(),
      row.textField("status").orEmpty(),
      row.flagField("actionable") ?: false
    )
  }
  return rows
}
