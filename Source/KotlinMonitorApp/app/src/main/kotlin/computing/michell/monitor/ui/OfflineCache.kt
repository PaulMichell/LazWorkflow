package computing.michell.monitor.ui

/* Offline screen helpers (c) 2026 Michell Computing.

   The file cache is gone. Room holds the rows. These functions still build
   the browseable screen the conversation page already knows. */

import computing.michell.monitor.connection.ReconnectingBanner
import computing.michell.monitor.data.ConversationRecord
import computing.michell.monitor.data.StoredPlan
import computing.michell.monitor.data.hasStoredPlan
import computing.michell.monitor.data.hostKey
import computing.michell.monitor.protocol.OfflineCacheDocument
import computing.michell.monitor.protocol.WireTurn
import computing.michell.monitor.protocol.conversationIdIsIdentity

const val OfflineBanner = "Offline"
const val OfflineReviewBanner = "Offline review. Send, Stop, and New need a live connection."
const val NoAddressBanner = "Set the desktop address in Settings."
const val CacheSaveDebounceMs = 1_000L
const val ImagePlaceholder = "Image"
const val NotCurrentLabel = "Not current"
const val LoadingImageLabel = "Loading image"

fun bannerIsStatus(banner: String): Boolean {
  return banner == OfflineBanner || banner == OfflineReviewBanner || banner == NoAddressBanner || banner == ConnectingBanner ||
    banner == ReconnectingBanner
}

fun offlineDocument(ui: MonitorUi): OfflineCacheDocument {
  return OfflineCacheDocument(
    ui.turns,
    ui.history.values.toList(),
    ui.live,
    ui.planPath,
    ui.planTitle,
    ui.planRows,
    ui.selectedPlan,
    ""
  )
}

fun worthCaching(ui: MonitorUi): Boolean {
  return ui.turns.isNotEmpty() || ui.history.isNotEmpty() || ui.live != null || ui.planRows.isNotEmpty() || ui.draft.isNotEmpty()
}

/** A committed cursor is a finished patch or catchup. An open part set is not. */
fun cursorCommitted(before: MonitorUi, after: MonitorUi): Boolean {
  if (after.hostEpoch.isEmpty() || after.catchingUp) return false
  if (after.hostEpoch != before.hostEpoch) return true
  return after.hostCursor > before.hostCursor
}

fun cacheTitle(title: String, turns: List<WireTurn>, live: WireTurn?, history: List<WireTurn>): String {
  if (title.isNotEmpty()) return title
  return firstUserPromptPreview(turns, live, history)
}

/** Host title wins. Otherwise the prompt preview of the first user block. */
fun firstUserPromptPreview(turns: List<WireTurn>, live: WireTurn?, history: List<WireTurn>): String {
  val historyByIndex = history.associateBy { turn -> turn.turnIndex }
  val ordered = ArrayList<WireTurn>()
  for (turn in turns) {
    val body = historyByIndex[turn.turnIndex]
    ordered += if (body != null && body.blocks.any { block -> block.kind == "user" && block.body.isNotEmpty() }) body else turn
  }
  if (live != null) {
    val at = ordered.indexOfFirst { turn -> turn.turnIndex == live.turnIndex }
    val liveUser = live.blocks.any { block -> block.kind == "user" && block.body.isNotEmpty() }
    if (at < 0) ordered += live
    else if (liveUser && ordered[at].blocks.none { block -> block.kind == "user" && block.body.isNotEmpty() }) ordered[at] = live
  }
  for (turn in ordered) {
    val user = turn.blocks.firstOrNull { block -> block.kind == "user" && block.body.isNotEmpty() }
    if (user != null) {
      if (turn.promptPreview.isNotEmpty()) return turn.promptPreview
      return user.body
    }
    if (turn.promptPreview.isNotEmpty()) return turn.promptPreview
    if (turn.prompt.isNotEmpty()) return turn.prompt
  }
  return ""
}

data class CacheSaveTarget(val conversationId: String, val projectRoot: String, val title: String)

/** Empty and `current` are not identities. Project root is stored, not keyed. */
fun cacheSaveTarget(ui: MonitorUi): CacheSaveTarget? {
  if (!worthCaching(ui) || !conversationIdIsIdentity(ui.conversationId)) return null
  val history = ui.history.values.toList()
  return CacheSaveTarget(ui.conversationId, ui.projectRoot, cacheTitle(ui.conversationTitle, ui.turns, ui.live, history))
}

fun cacheRowChanged(before: MonitorUi, after: MonitorUi): Boolean {
  val next = cacheSaveTarget(after) ?: return false
  val previous = cacheSaveTarget(before)
  if (previous == null) return true
  return next.conversationId != previous.conversationId || next.projectRoot != previous.projectRoot || next.title != previous.title
}

fun projectDisplay(projectRoot: String): String {
  val trimmed = projectRoot.trim().trimEnd('/', '\\')
  if (trimmed.isEmpty()) return ""
  val slash = maxOf(trimmed.lastIndexOf('/'), trimmed.lastIndexOf('\\'))
  if (slash < 0 || slash >= trimmed.lastIndex) return trimmed
  return trimmed.substring(slash + 1)
}

fun cacheUpdatedText(updatedMs: Long, zone: java.time.ZoneId = java.time.ZoneId.systemDefault()): String {
  if (updatedMs <= 0L) return ""
  val formatter = java.time.format.DateTimeFormatter.ofPattern("d MMM yyyy, HH:mm").withLocale(java.util.Locale.UK)
  return java.time.Instant.ofEpochMilli(updatedMs).atZone(zone).format(formatter)
}

fun cacheRowTitle(row: ConversationRecord): String {
  if (row.title.isNotEmpty()) return row.title
  if (row.id.isNotEmpty()) return row.id
  return "Untitled"
}

/** Newest first. The host key may be a pin with or without colons. */
fun conversationsForHost(rows: List<ConversationRecord>, host: String): List<ConversationRecord> {
  val key = hostKey(host)
  return rows.filter { row -> hostKey(row.host) == key }
    .sortedWith(compareByDescending<ConversationRecord> { it.pinned }.thenByDescending { it.updatedAt }.thenBy { it.id })
}

/** The page copy of a stored conversation. Remote actions stay off. Does not open a socket. */
fun reviewedCacheState(state: MonitorUi, document: OfflineCacheDocument, row: ConversationRecord, hasAddress: Boolean): MonitorUi {
  return applyOfflineCache(state, document, hasAddress).copy(
    conversationId = row.id,
    projectRoot = row.projectRoot,
    conversationTitle = row.title,
    hostEpoch = row.streamId,
    hostCursor = row.seq,
    reviewingOffline = true,
    banner = OfflineReviewBanner,
    lastSyncMs = row.updatedAt
  )
}

/** A stored conversation opened on a live link. Syncing until the host snapshot arrives. */
fun syncingCacheState(state: MonitorUi, document: OfflineCacheDocument, row: ConversationRecord): MonitorUi {
  return reviewedCacheState(state, document, row, true).copy(
    reviewingOffline = false,
    catchingUp = true,
    banner = "",
    reachedLive = false
  )
}

fun newestConversation(rows: List<ConversationRecord>, host: String): ConversationRecord? {
  return conversationsForHost(rows, host).firstOrNull()
}

fun documentImageIds(document: OfflineCacheDocument): List<String> {
  val ids = ArrayList<String>()
  fun add(turn: WireTurn) {
    for (id in turnImageIds(turn)) if (id !in ids) ids += id
  }
  for (turn in document.turns) add(turn)
  for (turn in document.history) add(turn)
  val live = document.live
  if (live != null) add(live)
  return ids
}

/** Missing decoded bytes stay a placeholder. A live link may still say it is loading. */
fun imageTileLabel(hasBitmap: Boolean, reason: String?, missing: Boolean, allowFetch: Boolean): String {
  if (hasBitmap) return ""
  if (!reason.isNullOrEmpty()) return "Image unavailable: $reason"
  if (missing) return "Image unavailable: missing"
  if (!allowFetch) return ImagePlaceholder
  return LoadingImageLabel
}

/** Fills an empty plan tab from the host cache. A plan already on screen wins, except a missing document. */
fun withCachedPlan(state: MonitorUi, plan: StoredPlan): MonitorUi {
  if (!hasStoredPlan(plan.path, plan.title, plan.rows)) return state
  if (hasStoredPlan(state.planPath, state.planTitle, state.planRows)) {
    if (state.planPath == plan.path && state.planBody.isEmpty() && plan.body.isNotEmpty()) {
      return state.copy(planBody = plan.body)
    }
    return state
  }
  return state.copy(
    planPath = plan.path,
    planTitle = plan.title,
    planRows = plan.rows,
    selectedPlan = plan.selected,
    planBody = plan.body,
    view = state.view.copy(planPath = plan.path, planTitle = plan.title)
  )
}

/** Opening a stored conversation must not blank the plan already on screen. */
fun keepShownPlan(incoming: MonitorUi, shown: MonitorUi): MonitorUi {
  if (hasStoredPlan(incoming.planPath, incoming.planTitle, incoming.planRows)) return incoming
  if (!hasStoredPlan(shown.planPath, shown.planTitle, shown.planRows)) return incoming
  return incoming.copy(
    planPath = shown.planPath,
    planTitle = shown.planTitle,
    planRows = shown.planRows,
    selectedPlan = shown.selectedPlan,
    planBody = shown.planBody,
    planChoices = if (incoming.planChoices.isNotEmpty()) incoming.planChoices else shown.planChoices,
    view = incoming.view.copy(planPath = shown.planPath, planTitle = shown.planTitle)
  )
}

/** Restores browseable rows. Remote actions stay off until a live snapshot arrives. */
fun applyOfflineCache(state: MonitorUi, document: OfflineCacheDocument, hasAddress: Boolean): MonitorUi {
  val hasBrowse = document.turns.isNotEmpty() || document.history.isNotEmpty() || document.live != null || document.planRows.isNotEmpty()
  val banner = when {
    !hasAddress -> NoAddressBanner
    hasBrowse -> OfflineBanner
    else -> ""
  }
  return state.copy(
    turns = document.turns,
    history = document.history.associateBy { it.turnIndex },
    live = document.live,
    planPath = document.planPath,
    planTitle = document.planTitle,
    planRows = document.planRows,
    planRunning = false,
    selectedPlan = document.selectedPlan,
    // An unsent prompt is not a default. Opening the app must not put it back in the composer.
    draft = "",
    reachedLive = false,
    pairHold = false,
    settingsOpen = false,
    approval = null,
    approvalOpen = false,
    banner = banner,
    view = clearRemoteActions(emptyView()).copy(model = shownModel(state.view.model))
  )
}
