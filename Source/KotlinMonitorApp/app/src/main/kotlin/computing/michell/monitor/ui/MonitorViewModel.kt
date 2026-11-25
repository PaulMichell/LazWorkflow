package computing.michell.monitor.ui

/* Screen host for the pulse-and-fetch link (c) 2026 Michell Computing.

   Builds MonitorUi from Room, the latest pulse and the link state. Dictation,
   drafts and display preferences stay in PromptController. Send queues in the
   outbox, including while the link is down. Approval and plan commands wait
   for their own items. */

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import computing.michell.monitor.net.LinkState
import computing.michell.monitor.ui.model.ConversationRecord
import computing.michell.monitor.ui.model.LinkStatus
import computing.michell.monitor.ui.model.MonitorDatabaseName
import computing.michell.monitor.ui.model.MonitorImageDirectoryName
import computing.michell.monitor.ui.model.MonitorLink
import computing.michell.monitor.ui.model.MonitorUi
import computing.michell.monitor.ui.model.PlanRow
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class MonitorViewModel(application: Application) : AndroidViewModel(application) {
  private val preferences = application.getSharedPreferences(DisplayPreferenceFile, Context.MODE_PRIVATE)

  init {
    clearCatalogue3Files(application)
  }

  private val session = MonitorSession(application)
  private val uiState = MutableStateFlow(MonitorUi(disconnected = true, linkKind = MonitorLink.Unpaired))
  private val prompts = PromptController(
    application,
    viewModelScope,
    preferences,
    draftOf = { uiState.value.draft },
    storeDraft = { text -> uiState.update { it.copy(draft = text) } }
  )
  val ui: StateFlow<MonitorUi> = uiState.asStateFlow()
  private val tabState = MutableStateFlow(AppTab.Conversation)
  val tab: StateFlow<AppTab> = tabState.asStateFlow()
  val dictation = prompts.dictation
  val dictationPermissionRequest = prompts.dictationPermissionRequest
  val link = MutableStateFlow(LinkStatus(phase = linkPhaseOf(MonitorLink.Unpaired), failureReason = "Unpaired"))
  val incidentRingText = MutableStateFlow("")
  val bitmaps = MutableStateFlow(emptyMap<String, android.graphics.Bitmap>())
  val pairAddress = MutableStateFlow(preferences.getString(AddressKey, "").orEmpty())
  val pairPort = MutableStateFlow(preferences.getString(PortKey, computing.michell.monitor.ui.model.MonitorLimits.ListenPort.toString()).orEmpty())
  val pairCode = MutableStateFlow("")
  val conversationCapText = MutableStateFlow(prompts.conversationCapText())
  val imageBudgetText = MutableStateFlow(prompts.imageBudgetText())
  val holdNotice = MutableStateFlow("")
  val cacheListOpen = MutableStateFlow(false)
  val storedBoard = MutableStateFlow<BoardContent?>(null)
  val cacheRows = MutableStateFlow(emptyList<ConversationRecord>())
  val cacheBackToList = MutableStateFlow(false)
  private val dao = session.database.monitor()
  private val pinnedIds = preferences.getStringSet(PinnedKey, emptySet()).orEmpty().toMutableSet()
  private var keepDraft = true
  private var editingCommandId = ""
  private var reviewedId = ""

  init {
    uiState.value = uiState.value.copy(showThinking = prompts.thinking(), showTools = prompts.tools())
    session.retarget(pairAddress.value, savedMonitorPort(pairPort.value))
    viewModelScope.launch(Dispatchers.IO) {
      merge(
        dao.observeTurns(),
        dao.observeItems(),
        dao.observeImages(),
        dao.observeConversations(),
        dao.observePlans(),
        dao.observeOutbox()
      ).collect { publish() }
    }
    viewModelScope.launch(Dispatchers.IO) { session.link.collect { publish() } }
    viewModelScope.launch(Dispatchers.IO) { session.pulseJson.collect { publish() } }
  }

  override fun onCleared() {
    session.close()
    super.onCleared()
  }

  fun enterForeground() {
    session.foreground()
  }

  fun leaveForeground() {
    prompts.leave()
    session.background(screenClockRunning(uiState.value))
  }

  fun noteUserActivity() {
    session.touch()
  }

  fun noteScreenOff(@Suppress("UNUSED_PARAMETER") taskResumed: Boolean) {
    if (!taskResumed) session.background(screenClockRunning(uiState.value))
  }

  fun noteScreenOn() {
    session.foreground()
  }

  fun selectTab(tab: AppTab) {
    if (tab != AppTab.Conversation) prompts.leave()
    tabState.value = tab
    session.planOpen(tab == AppTab.Plan)
  }

  fun requestMenuChoices(@Suppress("UNUSED_PARAMETER") live: Boolean) {}

  fun showSettings() {
    uiState.update { it.copy(settingsOpen = true) }
  }

  fun closeSettings() {
    uiState.update { it.copy(settingsOpen = false) }
    cacheListOpen.value = false
    cacheBackToList.value = false
  }

  fun showCachedList() {
    cacheBackToList.value = false
    viewModelScope.launch(Dispatchers.IO) {
      refreshCacheRows()
      cacheListOpen.value = true
    }
  }

  fun closeCachedList() {
    cacheListOpen.value = false
    cacheBackToList.value = true
  }

  fun connectFromPair() {
    preferences.edit().putString(AddressKey, pairAddress.value).putString(PortKey, pairPort.value).apply()
    session.retarget(pairAddress.value, savedMonitorPort(pairPort.value))
  }

  fun setShowThinking(value: Boolean) {
    prompts.setThinking(value)
    uiState.update { it.copy(showThinking = value) }
  }

  fun setShowTools(value: Boolean) {
    prompts.setTools(value)
    uiState.update { it.copy(showTools = value) }
  }

  fun setConversationCapText(text: String) {
    prompts.setConversationCapText(text)
    conversationCapText.value = text
  }

  fun setImageBudgetText(text: String) {
    prompts.setImageBudgetText(text)
    imageBudgetText.value = text
  }

  fun copyDiagnostics(): String {
    val state = uiState.value
    return "${monitorChip(state.linkKind, state.statusBusy).label} ${state.hostEpoch} ${state.banner}".trim()
  }

  fun restartTransient() {
    session.touch()
    session.foreground()
  }

  fun setMode(@Suppress("UNUSED_PARAMETER") mode: String) {}

  fun selectPlanPath(@Suppress("UNUSED_PARAMETER") path: String) {}

  fun selectConversation(@Suppress("UNUSED_PARAMETER") id: String) {}

  fun selectTask(@Suppress("UNUSED_PARAMETER") id: String) {}

  fun changePrompt(text: String, selectionStart: Int, selectionEnd: Int) {
    keepDraft = true
    prompts.changePrompt(text, selectionStart, selectionEnd, uiState.value.pendingPrompt)
  }

  fun sendOrSteer() {
    val state = uiState.value
    val text = state.draft.trim()
    if (text.isEmpty()) return
    val steer = state.view.canSteer && !state.disconnected && editingCommandId.isEmpty()
    val editing = editingCommandId
    editingCommandId = ""
    keepDraft = false
    uiState.update { it.copy(draft = "") }
    viewModelScope.launch(Dispatchers.IO) {
      if (steer) session.steerPrompt(text)
      else if (editing.isEmpty() || !session.editQueued(editing, text)) session.sendPrompt(text)
      publish()
    }
  }

  fun editPending(id: String) {
    val mark = uiState.value.pendingPrompts.firstOrNull { it.id == id && it.editable } ?: return
    editingCommandId = id
    keepDraft = true
    uiState.update { it.copy(draft = mark.text) }
  }

  fun deletePending(id: String) {
    viewModelScope.launch(Dispatchers.IO) {
      if (session.deleteQueued(id) && editingCommandId == id) editingCommandId = ""
      publish()
    }
  }

  fun stop() {}

  fun newConversation() {}

  fun noteReading(demand: ReadingDemand) {
    session.followHead(demand.followingHead)
  }

  fun noteViewWidth(@Suppress("UNUSED_PARAMETER") px: Int) {}

  fun toggleDictationOn(selectionStart: Int, selectionEnd: Int, showRationale: Boolean) {
    prompts.toggleDictationOn(selectionStart, selectionEnd, showRationale)
  }

  fun toggleDictationOff() {
    prompts.toggleDictationOff()
  }

  fun leaveDictation() {
    prompts.leave()
  }

  fun dictationPermission(granted: Boolean) {
    prompts.dictationPermission(granted)
  }

  fun consumeDictationPermissionRequest() {
    prompts.consumeDictationPermissionRequest()
  }

  fun retryUndelivered() {}

  fun selectPlan(@Suppress("UNUSED_PARAMETER") index: Int) {}

  fun runPlan() {}

  fun stopPlan() {}

  fun newPlan() {}

  fun closePlan() {}

  fun cancelPlanFetch() {}

  fun continuePlanFetch() {}

  fun readPlanWindow(row: PlanRow?): String {
    val body = uiState.value.planBody
    if (row == null) return body
    return planSectionExcerpt(body, row)
  }

  fun openCachedRow(row: ConversationRecord) {
    reviewedId = row.id
    cacheListOpen.value = false
    cacheBackToList.value = session.link.value !is LinkState.Connected
    viewModelScope.launch(Dispatchers.IO) { publish() }
  }

  fun pinCached(row: ConversationRecord) {
    synchronized(pinnedIds) {
      if (row.pinned) pinnedIds.remove(row.id) else pinnedIds.add(row.id)
      preferences.edit().putStringSet(PinnedKey, pinnedIds.toSet()).apply()
    }
    viewModelScope.launch(Dispatchers.IO) { refreshCacheRows() }
  }

  fun deleteCached(row: ConversationRecord) {
    viewModelScope.launch(Dispatchers.IO) {
      dao.deleteConversations(listOf(row.id))
      synchronized(pinnedIds) {
        pinnedIds.remove(row.id)
        preferences.edit().putStringSet(PinnedKey, pinnedIds.toSet()).apply()
      }
      if (reviewedId == row.id) reviewedId = ""
      publish()
    }
  }

  fun allowApproval() {}

  fun denyApproval() {}

  fun dismissApproval() {
    uiState.update { it.copy(approvalOpen = false) }
  }

  fun answerSaveQuestion(@Suppress("UNUSED_PARAMETER") save: Boolean) {
    uiState.update { it.copy(saveQuestion = "") }
  }

  private fun publish() {
    if (session.link.value is LinkState.Connected) reviewedId = ""
    val projected = projectMonitor(
      dao,
      session.pulseJson.value,
      session.link.value,
      session.seenAtMs.value,
      session.paired,
      uiState.value,
      reviewedId = reviewedId
    )
    uiState.update { current ->
      projected.copy(
        draft = if (keepDraft) current.draft else "",
        settingsOpen = current.settingsOpen,
        showThinking = current.showThinking,
        showTools = current.showTools
      )
    }
    refreshCacheRows()
    val shown = uiState.value
    link.value = LinkStatus(
      phase = linkPhaseOf(shown.linkKind),
      banner = shown.linkBanner,
      failureReason = linkFailureOf(shown.linkKind)
    )
  }

  private fun refreshCacheRows() {
    val rows = dao.conversations()
    val endpoint = pairAddress.value.trim() + ":" + savedMonitorPort(pairPort.value)
    val host = if (rows.any { it.host == endpoint }) endpoint else rows.firstOrNull()?.host.orEmpty()
    val pinned = synchronized(pinnedIds) { pinnedIds.toSet() }
    val records = rows.map { row ->
      ConversationRecord(row.id, row.host, "", row.title, "", 0L, row.updatedAt, row.id in pinned)
    }
    cacheRows.value = conversationsForHost(records, host)
  }
}

private const val DisplayPreferenceFile = "monitor-display"
private const val AddressKey = "address"
private const val PortKey = "port"
private const val CatalogueClearedKey = "old-monitor-cache-cleared"
private const val PinnedKey = "pinned-conversations"

private fun clearCatalogue3Files(context: Context) {
  val preferences = context.getSharedPreferences(DisplayPreferenceFile, Context.MODE_PRIVATE)
  if (preferences.getBoolean(CatalogueClearedKey, false)) return
  context.deleteDatabase(MonitorDatabaseName)
  File(context.filesDir, MonitorImageDirectoryName).deleteRecursively()
  preferences.edit().putBoolean(CatalogueClearedKey, true).apply()
}
