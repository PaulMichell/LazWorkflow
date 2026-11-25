package computing.michell.monitor.ui

/* Screen host for the pulse-and-fetch link (c) 2026 Michell Computing.

   Builds MonitorUi from Room, the latest pulse and the link state. Dictation,
   drafts and display preferences stay in PromptController. Commands that are
   not yet connected remain no-ops until their own items. */

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
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
    cacheListOpen.value = true
    cacheBackToList.value = false
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

  fun selectTarget(@Suppress("UNUSED_PARAMETER") path: String) {}

  fun selectConversation(@Suppress("UNUSED_PARAMETER") id: String) {}

  fun selectModel(@Suppress("UNUSED_PARAMETER") id: String) {}

  fun selectReasoning(@Suppress("UNUSED_PARAMETER") id: String) {}

  fun selectPermissions(@Suppress("UNUSED_PARAMETER") id: String) {}

  fun changePrompt(text: String, selectionStart: Int, selectionEnd: Int) {
    prompts.changePrompt(text, selectionStart, selectionEnd, uiState.value.pendingPrompt)
  }

  fun sendOrSteer() {}

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

  fun openCachedRow(@Suppress("UNUSED_PARAMETER") row: ConversationRecord) {}

  fun pinCached(@Suppress("UNUSED_PARAMETER") row: ConversationRecord) {}

  fun deleteCached(@Suppress("UNUSED_PARAMETER") row: ConversationRecord) {}

  fun allowApproval() {}

  fun denyApproval() {}

  fun dismissApproval() {
    uiState.update { it.copy(approvalOpen = false) }
  }

  fun answerSaveQuestion(@Suppress("UNUSED_PARAMETER") save: Boolean) {
    uiState.update { it.copy(saveQuestion = "") }
  }

  private fun publish() {
    val projected = projectMonitor(
      dao,
      session.pulseJson.value,
      session.link.value,
      session.seenAtMs.value,
      session.paired,
      uiState.value
    )
    uiState.update { current ->
      projected.copy(
        draft = current.draft,
        settingsOpen = current.settingsOpen,
        showThinking = current.showThinking,
        showTools = current.showTools
      )
    }
    val shown = uiState.value
    link.value = LinkStatus(
      phase = linkPhaseOf(shown.linkKind),
      banner = shown.linkBanner,
      failureReason = linkFailureOf(shown.linkKind)
    )
  }
}

private const val DisplayPreferenceFile = "monitor-display"
private const val AddressKey = "address"
private const val PortKey = "port"
private const val CatalogueClearedKey = "old-monitor-cache-cleared"

private fun clearCatalogue3Files(context: Context) {
  val preferences = context.getSharedPreferences(DisplayPreferenceFile, Context.MODE_PRIVATE)
  if (preferences.getBoolean(CatalogueClearedKey, false)) return
  context.deleteDatabase(MonitorDatabaseName)
  File(context.filesDir, MonitorImageDirectoryName).deleteRecursively()
  preferences.edit().putBoolean(CatalogueClearedKey, true).apply()
}
