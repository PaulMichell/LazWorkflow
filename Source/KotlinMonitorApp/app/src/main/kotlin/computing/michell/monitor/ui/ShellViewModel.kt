package computing.michell.monitor.ui

/* Temporary screen host while the phone link is rebuilt (c) 2026 Michell Computing.

   Holds an empty conversation and the rebuild banner. Does not open a socket.
   The first start deletes the old Room file and image cache. Catalogue 3 was removed. */

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import computing.michell.monitor.ui.model.ConversationRecord
import computing.michell.monitor.ui.model.LinkPhase
import computing.michell.monitor.ui.model.LinkStatus
import computing.michell.monitor.ui.model.MonitorDatabaseName
import computing.michell.monitor.ui.model.MonitorImageDirectoryName
import computing.michell.monitor.ui.model.MonitorLimits
import computing.michell.monitor.ui.model.MonitorUi
import computing.michell.monitor.ui.model.PlanRow
import computing.michell.monitor.ui.model.RebuildBanner
import computing.michell.monitor.ui.model.shellUi
import java.io.File
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

class ShellViewModel(application: Application) : AndroidViewModel(application) {
  private val preferences = application.getSharedPreferences(DisplayPreferenceFile, Context.MODE_PRIVATE)
  private val uiState = MutableStateFlow(shellUi())
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
  val link = MutableStateFlow(LinkStatus(phase = LinkPhase.Idle, banner = RebuildBanner))
  val incidentRingText = MutableStateFlow("")
  val bitmaps = MutableStateFlow(emptyMap<String, android.graphics.Bitmap>())
  val pairAddress = MutableStateFlow(preferences.getString(AddressKey, "").orEmpty())
  val pairPort = MutableStateFlow(preferences.getString(PortKey, MonitorLimits.ListenPort.toString()).orEmpty())
  val pairCode = MutableStateFlow("")
  val conversationCapText = MutableStateFlow(prompts.conversationCapText())
  val imageBudgetText = MutableStateFlow(prompts.imageBudgetText())
  val holdNotice = MutableStateFlow("")
  val cacheListOpen = MutableStateFlow(false)
  val storedBoard = MutableStateFlow<BoardContent?>(null)
  val cacheRows = MutableStateFlow(emptyList<ConversationRecord>())
  val cacheBackToList = MutableStateFlow(false)

  init {
    uiState.value = shellUi().copy(showThinking = prompts.thinking(), showTools = prompts.tools())
    clearCatalogue3Files(application)
  }

  fun enterForeground() {}

  fun leaveForeground() {
    prompts.leave()
  }

  fun noteUserActivity() {}

  fun noteScreenOff(@Suppress("UNUSED_PARAMETER") taskResumed: Boolean) {}

  fun noteScreenOn() {}

  fun selectTab(tab: AppTab) {
    if (tab != AppTab.Conversation) prompts.leave()
    tabState.value = tab
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
    uiState.update { it.copy(banner = RebuildBanner) }
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

  fun copyDiagnostics(): String = RebuildBanner

  fun restartTransient() {}

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

  fun noteReading(@Suppress("UNUSED_PARAMETER") demand: ReadingDemand) {}

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

  fun readPlanWindow(@Suppress("UNUSED_PARAMETER") row: PlanRow?): String = ""

  fun openCachedRow(@Suppress("UNUSED_PARAMETER") row: ConversationRecord) {}

  fun pinCached(@Suppress("UNUSED_PARAMETER") row: ConversationRecord) {}

  fun deleteCached(@Suppress("UNUSED_PARAMETER") row: ConversationRecord) {}

  fun allowApproval() {}

  fun denyApproval() {}

  fun dismissApproval() {}

  fun answerSaveQuestion(@Suppress("UNUSED_PARAMETER") save: Boolean) {}
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
