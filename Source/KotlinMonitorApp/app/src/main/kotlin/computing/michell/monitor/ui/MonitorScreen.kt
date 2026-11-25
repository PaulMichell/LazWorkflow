package computing.michell.monitor.ui

/* Screen state from Room, the latest pulse and the link.
   (c) 2026 Michell Computing.

   The kept screens read MonitorUi. Thinking, tool cards and image tiles are
   the blocks those screens already draw. The activity clock is corrected once
   from server_time and then ticks on the phone. Busy is status.busy from the
   pulse that was applied. A later clock reading does not clear it. */

import computing.michell.monitor.data.ImageRow
import computing.michell.monitor.data.ItemRow
import computing.michell.monitor.data.MonitorDao
import computing.michell.monitor.data.OutboxPending
import computing.michell.monitor.data.OutboxRow
import computing.michell.monitor.data.OutboxSending
import computing.michell.monitor.data.OutboxSent
import computing.michell.monitor.data.PlanCacheRow
import computing.michell.monitor.data.TurnRow
import computing.michell.monitor.net.JsonValue
import computing.michell.monitor.net.LinkState
import computing.michell.monitor.net.LiveTurnOutcome
import computing.michell.monitor.net.array
import computing.michell.monitor.net.bool
import computing.michell.monitor.net.field
import computing.michell.monitor.net.int
import computing.michell.monitor.net.parseJson
import computing.michell.monitor.net.parseMonitorTime
import computing.michell.monitor.net.parsePulse
import computing.michell.monitor.net.text
import computing.michell.monitor.ui.model.ApprovalNotice
import computing.michell.monitor.ui.model.ConversationChoice
import computing.michell.monitor.ui.model.LinkPhase
import computing.michell.monitor.ui.model.MonitorLink
import computing.michell.monitor.ui.model.ConversationRecord
import computing.michell.monitor.ui.model.MonitorUi
import computing.michell.monitor.ui.model.OfflineBanner
import computing.michell.monitor.ui.model.PendingPromptMark
import computing.michell.monitor.ui.model.StoredPlan
import computing.michell.monitor.ui.model.PhaseWaiting
import computing.michell.monitor.ui.model.PlanChoice
import computing.michell.monitor.ui.model.PlanRow
import computing.michell.monitor.ui.model.ReconnectingBanner
import computing.michell.monitor.ui.model.WireBlock
import computing.michell.monitor.ui.model.WireImage
import computing.michell.monitor.ui.model.WireTurn
import computing.michell.monitor.ui.model.WireView
import computing.michell.monitor.ui.model.emptyView
import computing.michell.monitor.ui.model.formatActivityClock
import computing.michell.monitor.ui.model.ideLinkLive
import computing.michell.monitor.ui.model.idleActivity

/** True while the pulse says the host is in a run. The screen ticks this locally. */
fun screenClockRunning(ui: MonitorUi): Boolean {
  return ui.statusBusy || ui.view.sending || ui.view.planRunning || ui.planRunning
}

/**
 * Activity caption from the pulse. [nowMs] is the phone clock. It is not a new
 * pulse, and it does not change [MonitorUi.statusBusy].
 */
fun screenActivity(ui: MonitorUi, phase: LinkPhase, nowMs: Long, pending: Boolean): String {
  val linkLive = ideLinkLive(ui.disconnected, phase)
  if (!linkLive) return ""
  if (!screenClockRunning(ui)) {
    if (pending) return PhaseWaiting
    return idleActivity(ui.view.statusText)
  }
  val activity = ui.view.phase.trim().ifEmpty { ui.view.statusText.trim() }
  if (activity.isEmpty()) return ""
  return activity + activityClock(ui.activityStartedMs, nowMs)
}

fun monitorLinkOf(state: LinkState, paired: Boolean): MonitorLink {
  return when (state) {
    is LinkState.Connected -> MonitorLink.Connected
    is LinkState.Retrying -> MonitorLink.Retrying
    LinkState.Unpaired -> MonitorLink.Unpaired
    LinkState.PinMismatch -> MonitorLink.PinChanged
    LinkState.Stopped -> if (paired) MonitorLink.Stopped else MonitorLink.Unpaired
  }
}

fun linkPhaseOf(kind: MonitorLink): LinkPhase {
  return if (kind == MonitorLink.Connected) LinkPhase.Live else LinkPhase.Disconnected
}

fun linkBannerOf(kind: MonitorLink): String {
  return when (kind) {
    MonitorLink.Retrying -> ReconnectingBanner
    MonitorLink.Stopped -> OfflineBanner
    else -> ""
  }
}

fun linkFailureOf(kind: MonitorLink): String {
  return when (kind) {
    MonitorLink.PinChanged -> "Pin changed"
    MonitorLink.Unpaired -> "Unpaired"
    else -> ""
  }
}

/**
 * Build the screen from the cache and one pulse. [seenAtMs] is the phone time
 * when that pulse arrived. [nowMs] is not read: a later clock does not clear busy.
 */
fun projectMonitor(
  dao: MonitorDao,
  pulseJson: String,
  link: LinkState,
  seenAtMs: Long,
  paired: Boolean,
  previous: MonitorUi = MonitorUi(),
  @Suppress("UNUSED_PARAMETER") nowMs: Long = seenAtMs,
  reviewedId: String = "",
  approvalDetail: String = ""
): MonitorUi {
  val kind = monitorLinkOf(link, paired)
  val root = if (pulseJson.isEmpty()) null else parseJson(pulseJson)
  val status = pulseStatus(root)
  val pulse = if (pulseJson.isEmpty()) null else parsePulse(pulseJson)
  val conversations = dao.conversations()
  val conversationId = shownConversationId(conversations, pulse?.conversationId, kind, reviewedId)
  val conversation = conversations.firstOrNull { it.id == conversationId }
  val turns = if (conversationId.isEmpty()) emptyList() else dao.turns(conversationId)
  val liveId = pulse?.liveTurnId
  val images = dao.images()
  val host = conversation?.host.orEmpty()
  val plans = dao.plans().filter { row -> host.isEmpty() || row.host == host }
  val planPath = pulse?.planPath?.ifEmpty { null } ?: plans.firstOrNull()?.path.orEmpty()
  val plan = plans.firstOrNull { it.path == planPath } ?: plans.firstOrNull()
  val planRows = planRowsOf(plan?.rowsJson.orEmpty())
  val planItem = root?.field("plan")?.text("item").orEmpty()
  val matchedPlan = planRows.indexOfFirst { row -> row.title == planItem || row.index.toString() == planItem }
  val selectedPlan = if (matchedPlan >= 0) matchedPlan else previous.selectedPlan
  val storedTurns = turns.filter { it.id != liveId }.map { row -> wireTurn(row, dao.items(row.id), images, false) }
  val live = liveTurn(turns.firstOrNull { it.id == liveId }, liveId, pulse?.liveTurnIndex ?: 0, status.mode, dao, images)
  val queued = queuedPrompts(dao.outbox())
  val continuing = previous.pendingPrompts.isNotEmpty() || previous.pendingPrompt.isNotEmpty()
  val baseline = queueBaseline(queued.isNotEmpty(), continuing, previous.promptBaseline, live, storedTurns)
  val seenCommands = turns.map { it.clientCommandId }.filter { it.isNotEmpty() }.toSet()
  val marks = pendingPromptMarks(queued, seenCommands, storedTurns, live, baseline)
  val waiting = waitingPromptBanner(marks.size)
  val notice = approvalNotice(pulseJson, approvalDetail)
  val hostEpoch = pulse?.epoch ?: previous.hostEpoch
  val hostGeneration = if (hostEpoch.isNotEmpty() && hostEpoch != previous.hostEpoch) previous.hostGeneration + 1 else previous.hostGeneration
  val runningPlan = status.planRunning || root?.field("plan")?.bool("running") == true
  val offline = paired && (kind == MonitorLink.Stopped || kind == MonitorLink.Retrying)
  val projected = previous.copy(
    view = wireView(status, plan, planPath),
    turns = storedTurns,
    live = live,
    history = emptyMap(),
    planPath = plan?.path ?: planPath,
    planTitle = plan?.title.orEmpty(),
    planRunning = runningPlan,
    planRows = planRows,
    selectedPlan = selectedPlan,
    planChoices = plans.map { row -> PlanChoice(row.path, row.title.ifEmpty { row.path }) },
    conversationChoices = conversations.map { row ->
      ConversationChoice(row.id, row.title, row.id == conversationId || row.current)
    },
    conversationCurrent = conversationId,
    approval = notice,
    approvalOpen = notice != null,
    banner = waiting.ifEmpty { if (kind == MonitorLink.Connected) status.errorText else "" },
    disconnected = kind != MonitorLink.Connected,
    imageReasons = images.filter { it.localPath.isEmpty() }.associate { it.id to "missing" },
    reachedLive = kind == MonitorLink.Connected,
    pendingPrompt = marks.firstOrNull()?.text.orEmpty(),
    pendingKind = if (marks.isEmpty()) "" else "user",
    pendingCommandId = marks.firstOrNull()?.id.orEmpty(),
    pendingPrompts = marks,
    pendingEpoch = if (marks.map { it.id } == previous.pendingPrompts.map { it.id }) previous.pendingEpoch else previous.pendingEpoch + 1,
    promptBaseline = if (marks.isEmpty()) emptySet() else baseline,
    activityStartedMs = activityStartMs(status.activitySince, status.serverTime, seenAtMs),
    statusBusy = status.present && status.busy,
    sendWhileOffline = offline,
    reconnectable = kind == MonitorLink.Connected || kind == MonitorLink.Retrying,
    linkBanner = linkBannerOf(kind),
    planBody = plan?.documentText.orEmpty(),
    planRevision = plan?.etag.orEmpty(),
    conversationId = conversationId,
    conversationTitle = conversation?.title ?: pulse?.conversationTitle.orEmpty(),
    hostEpoch = hostEpoch,
    hostCursor = pulse?.rev ?: previous.hostCursor,
    hostGeneration = hostGeneration,
    generation = previous.generation + 1,
    linkKind = kind
  )
  val storedPlan = StoredPlan(projected.planPath, projected.planTitle, projected.planRows, projected.selectedPlan, projected.planBody)
  return withCachedPlan(projected, storedPlan)
}

/**
 * Opens a stored conversation without a socket. Room is the only source.
 * The chip says Offline. Send stays available only when a paired link can queue.
 */
fun openCachedConversation(dao: MonitorDao, row: ConversationRecord, previous: MonitorUi = MonitorUi()): MonitorUi {
  val seeded = projectMonitor(dao, "", LinkState.Stopped, row.updatedAt, false, previous, reviewedId = row.id)
  val document = offlineDocument(seeded).copy(planBody = seeded.planBody)
  val browsed = applyOfflineCache(previous, document, false)
  return withCachedPlan(
    browsed.copy(
      conversationId = row.id,
      projectRoot = row.projectRoot,
      conversationTitle = row.title.ifEmpty { seeded.conversationTitle },
      hostEpoch = row.streamId.ifEmpty { seeded.hostEpoch },
      hostCursor = if (row.seq > 0L) row.seq else seeded.hostCursor,
      lastSyncMs = row.updatedAt,
      planBody = seeded.planBody,
      disconnected = true,
      reachedLive = false,
      reviewingOffline = false,
      sendWhileOffline = seeded.sendWhileOffline,
      banner = seeded.banner,
      pendingPrompt = seeded.pendingPrompt,
      pendingKind = seeded.pendingKind,
      pendingCommandId = seeded.pendingCommandId,
      pendingPrompts = seeded.pendingPrompts,
      pendingEpoch = seeded.pendingEpoch,
      promptBaseline = seeded.promptBaseline,
      linkKind = MonitorLink.Stopped,
      linkBanner = OfflineBanner,
      view = seeded.view
    ),
    StoredPlan(seeded.planPath, seeded.planTitle, seeded.planRows, seeded.selectedPlan, seeded.planBody)
  )
}

private fun activityClock(startedMs: Long, nowMs: Long): String {
  if (startedMs <= 0L || nowMs < startedMs) return ""
  return " ${formatActivityClock(nowMs - startedMs)}"
}

private data class PulseStatus(
  val present: Boolean = false,
  val available: Boolean = false,
  val busy: Boolean = false,
  val sending: Boolean = false,
  val planRunning: Boolean = false,
  val mode: String = "",
  val phase: String = "",
  val statusText: String = "",
  val activity: String = "",
  val activitySince: String = "",
  val canSend: Boolean = false,
  val canSteer: Boolean = false,
  val canStop: Boolean = false,
  val canChangeMode: Boolean = false,
  val remoteApproval: Boolean = false,
  val errorText: String = "",
  val usageCaption: String = "",
  val usageHint: String = "",
  val serverTime: String = ""
)

private fun pulseStatus(root: JsonValue?): PulseStatus {
  val status = root?.field("status") as? JsonValue.Obj ?: return PulseStatus()
  return PulseStatus(
    present = true,
    available = status.bool("available"),
    busy = status.bool("busy"),
    sending = status.bool("sending"),
    planRunning = status.bool("plan_running"),
    mode = status.text("mode"),
    phase = status.text("phase"),
    statusText = status.text("status_text"),
    activity = status.text("activity"),
    activitySince = status.text("activity_since"),
    canSend = status.bool("can_send"),
    canSteer = status.bool("can_steer"),
    canStop = status.bool("can_stop"),
    canChangeMode = status.bool("can_change_mode"),
    remoteApproval = status.bool("remote_approval"),
    errorText = status.text("error_text"),
    usageCaption = status.text("usage_caption"),
    usageHint = status.text("usage_hint"),
    serverTime = root.text("server_time")
  )
}

private fun activityStartMs(activitySince: String, serverTime: String, seenAtMs: Long): Long {
  val since = parseMonitorTime(activitySince)
  if (since <= 0L) return 0L
  val server = parseMonitorTime(serverTime)
  if (server <= 0L || seenAtMs <= 0L) return since
  return since + (seenAtMs - server)
}

private fun wireView(status: PulseStatus, plan: PlanCacheRow?, planPath: String): WireView {
  val activity = status.activity.trim()
  return emptyView().copy(
    available = status.available,
    busy = status.busy,
    sending = status.sending,
    modeLocked = status.available && !status.canChangeMode,
    planRunning = status.planRunning,
    phase = activity.ifEmpty { status.phase },
    statusText = status.statusText.ifEmpty { "Ready" },
    canSend = status.canSend,
    canSteer = status.canSteer,
    canStop = status.canStop,
    canChangeMode = status.canChangeMode,
    remoteApproval = status.remoteApproval,
    errorText = status.errorText,
    mode = status.mode,
    planPath = plan?.path ?: planPath,
    planTitle = plan?.title.orEmpty(),
    usageCaption = status.usageCaption,
    usageHint = status.usageHint
  )
}

private fun liveTurn(
  row: TurnRow?,
  liveId: String?,
  index: Int,
  mode: String,
  dao: MonitorDao,
  images: List<ImageRow>
): WireTurn? {
  if (liveId.isNullOrEmpty()) return null
  if (row == null) return WireTurn(index, liveId, mode, "", "", "", live = true)
  return wireTurn(row, dao.items(row.id), images, true)
}

private fun wireTurn(row: TurnRow, items: List<ItemRow>, images: List<ImageRow>, live: Boolean): WireTurn {
  return WireTurn(
    turnIndex = row.index,
    id = row.id,
    mode = row.mode,
    createdAt = if (row.createdAt > 0L) java.time.Instant.ofEpochMilli(row.createdAt).toString() else "",
    promptPreview = previewOf(row.prompt),
    errorText = row.errorText,
    prompt = row.prompt,
    durationMs = row.duration,
    live = live || row.outcome == LiveTurnOutcome,
    blocks = blocksFor(row, items, images)
  )
}

private fun blocksFor(row: TurnRow, items: List<ItemRow>, images: List<ImageRow>): List<WireBlock> {
  val blocks = ArrayList<WireBlock>()
  if (row.prompt.isNotEmpty() && items.none { it.kind.equals("user", ignoreCase = true) }) {
    blocks += WireBlock("user", "", "", "", "", row.prompt, false, true, 0, emptyList())
  }
  val used = HashSet<String>()
  for (item in items) {
    val attached = images.filter { it.itemId == item.id }
    attached.forEach { used += it.id }
    blocks += blockFor(item, attached)
  }
  val orphans = images.filter { it.turnId == row.id && it.id !in used && (it.itemId.isEmpty() || items.none { item -> item.id == it.itemId }) }
  for (image in orphans) {
    if (image.id in used) continue
    used += image.id
    blocks += WireBlock("note", image.id, image.name, "", "", "", false, true, 0, listOf(wireImage(image)))
  }
  if (row.errorText.isNotEmpty()) {
    blocks += WireBlock("note", "", "", "", "", row.errorText, false, false, 0, emptyList())
  }
  return blocks
}

private fun blockFor(item: ItemRow, images: List<ImageRow>): WireBlock {
  val running = item.state.equals("running", ignoreCase = true)
  val failed = item.state.equals("failed", ignoreCase = true) || item.state.equals("error", ignoreCase = true)
  val attached = images.map { wireImage(it) }
  if (item.kind.equals("image", ignoreCase = true)) {
    val tiles = if (attached.isNotEmpty()) attached else {
      val path = item.body
      listOf(WireImage(item.id, item.title.ifEmpty { item.id }, "", 0, 0, path, path.isEmpty()))
    }
    return WireBlock("note", item.id, item.title, "", "", "", false, !failed, 0, tiles)
  }
  return WireBlock(
    kind = item.kind,
    blockId = item.id,
    title = item.title,
    toolName = item.toolName,
    toolId = "",
    body = item.body,
    running = running,
    ok = !failed,
    durationMs = 0,
    images = attached
  )
}

private fun wireImage(row: ImageRow): WireImage {
  return WireImage(
    id = row.id,
    name = row.name.ifEmpty { row.id },
    mime = "",
    width = 0,
    height = 0,
    displayPath = row.localPath,
    missing = row.localPath.isEmpty()
  )
}

private fun previewOf(prompt: String): String {
  val line = prompt.lineSequence().firstOrNull()?.trim().orEmpty()
  if (line.length <= 80) return line
  return line.substring(0, 80)
}

private fun planRowsOf(json: String): List<PlanRow> {
  if (json.isEmpty()) return emptyList()
  val root = parseJson(json) ?: return emptyList()
  val values = when (root) {
    is JsonValue.Arr -> root.values
    else -> root.array("rows")
  }
  return values.mapIndexed { index, row ->
    PlanRow(
      index = row.int("index", index),
      level = row.int("level"),
      title = row.text("title"),
      parentTitle = row.text("parent_title"),
      status = row.text("status"),
      actionable = row.bool("actionable")
    )
  }
}

/** Pulse id opens the sheet. GET /v4/approval fills the summary and whether the phone may answer. */
fun approvalNotice(pulseJson: String, detailJson: String): ApprovalNotice? {
  val root = if (pulseJson.isEmpty()) null else parseJson(pulseJson)
  val approval = root?.field("approval") as? JsonValue.Obj ?: return null
  val id = approval.text("id")
  if (id.isEmpty()) return null
  val detail = parseJson(detailJson)
  val detailId = detail?.text("id").orEmpty().ifEmpty { detail?.text("tool_id").orEmpty() }
  val same = detailId == id
  val remote = root.field("status")?.bool("remote_approval") == true
  return ApprovalNotice(
    active = true,
    toolId = id,
    toolName = approval.text("tool_name").ifEmpty { if (same) detail?.text("tool_name").orEmpty() else "" },
    summary = if (same) detail?.text("summary").orEmpty() else "",
    modeCaption = if (same) detail?.text("mode_caption").orEmpty() else "",
    decisionsAccepted = if (same) detail?.bool("decisions_accepted") == true else remote
  )
}

private fun shownConversationId(
  conversations: List<computing.michell.monitor.data.ConversationRow>,
  pulseId: String?,
  kind: MonitorLink,
  reviewedId: String
): String {
  val reviewed = reviewedId.takeIf { id -> id.isNotEmpty() && conversations.any { it.id == id } }
  if (reviewed != null && kind != MonitorLink.Connected) return reviewed
  val live = pulseId?.takeIf { it.isNotEmpty() }
  if (live != null) return live
  return conversations.firstOrNull { it.current }?.id ?: conversations.firstOrNull()?.id ?: reviewed.orEmpty()
}

private fun queuedPrompts(rows: List<OutboxRow>): List<PendingPromptMark> {
  return rows.mapNotNull { row ->
    if (row.type != "send" && row.type != "run_task") return@mapNotNull null
    if (row.state != OutboxPending && row.state != OutboxSending && row.state != OutboxSent) return@mapNotNull null
    val parsed = parseJson(row.argsJson)
    val text = parsed?.text("text").orEmpty().ifEmpty { parsed?.text("note").orEmpty() }
    if (text.isEmpty()) return@mapNotNull null
    PendingPromptMark(row.commandId, text, row.state == OutboxPending)
  }
}
