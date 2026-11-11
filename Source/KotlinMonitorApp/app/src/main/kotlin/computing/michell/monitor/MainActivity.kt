package computing.michell.monitor

/* Monitor phone shell (c) 2026 Michell Computing. */

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.lifecycle.Lifecycle
import android.content.IntentFilter
import android.os.Bundle
import android.view.MotionEvent
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.DrawerState
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.TabRowDefaults
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.material3.Text
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.ui.ActivityStatus
import computing.michell.monitor.ui.AppMenu
import computing.michell.monitor.ui.AppTab
import computing.michell.monitor.ui.MenuSectionKind
import computing.michell.monitor.ui.MenuSheetWidth
import computing.michell.monitor.ui.menuEdgeSwipeEnabled
import computing.michell.monitor.ui.menuEdgeSwipeToOpen
import computing.michell.monitor.ui.menuFlyoutConsumesBack
import computing.michell.monitor.ui.ApprovalSheet
import computing.michell.monitor.ui.SaveQuestionDialog
import computing.michell.monitor.ui.CachedListDialog
import computing.michell.monitor.ui.ConversationScreen
import computing.michell.monitor.ui.MainTabs
import computing.michell.monitor.ui.MonitorViewModel
import computing.michell.monitor.ui.PlanPreviewPanel
import computing.michell.monitor.ui.PlanScreen
import computing.michell.monitor.ui.statusNotice
import computing.michell.monitor.protocol.PlanRow
import computing.michell.monitor.ui.PlanInlineBytes
import computing.michell.monitor.ui.planLoaded
import computing.michell.monitor.ui.planSectionCaption
import computing.michell.monitor.ui.planSectionExcerpt
import computing.michell.monitor.ui.SettingsScreen
import computing.michell.monitor.ui.pageForTab
import computing.michell.monitor.ui.tabAfterSwipe
import computing.michell.monitor.ui.tabCaption
import computing.michell.monitor.ui.tabForPage
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

private val MonitorTeal = Color(0xFF006C4C)
private val MonitorQuiet = Color(0xFF666666)


class MainActivity : ComponentActivity() {
  private val model: MonitorViewModel by viewModels()
  private val screenWatch = object : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
      when (intent?.action) {
        Intent.ACTION_SCREEN_OFF -> model.noteScreenOff(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED))
        // onStart can be later than the backlight. The socket was kept, so this is not a new link.
        Intent.ACTION_SCREEN_ON -> model.noteScreenOn()
      }
    }
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val screenFilter = IntentFilter().apply {
      addAction(Intent.ACTION_SCREEN_OFF)
      addAction(Intent.ACTION_SCREEN_ON)
    }
    if (android.os.Build.VERSION.SDK_INT >= 33)
      registerReceiver(screenWatch, screenFilter, Context.RECEIVER_NOT_EXPORTED)
    else
      registerReceiver(screenWatch, screenFilter)
    setContent {
      MaterialTheme {
        MonitorShell(model)
      }
    }
  }

  override fun onDestroy() {
    unregisterReceiver(screenWatch)
    super.onDestroy()
  }

  override fun onStart() {
    super.onStart()
    model.enterForeground()
  }

  override fun onResume() {
    super.onResume()
    // A screen that only paused, or a wake that was missed in onStart, still reconnects.
    model.enterForeground()
  }

  override fun onStop() {
    if (!isChangingConfigurations) {
      model.leaveDictation()
      model.leaveForeground()
    }
    super.onStop()
  }

  /** Every finger-down is use. After a quiet spell it is what brings an offline link back. The touch still goes on. */
  override fun dispatchTouchEvent(event: MotionEvent): Boolean {
    if (event.actionMasked == MotionEvent.ACTION_DOWN) model.noteUserActivity()
    return super.dispatchTouchEvent(event)
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MonitorShell(model: MonitorViewModel) {
  val ui by model.ui.collectAsState()
  val tab by model.tab.collectAsState()
  val dictation by model.dictation.collectAsState()
  val permissionRequest by model.dictationPermissionRequest.collectAsState()
  val link by model.link.collectAsState()
  val bitmaps by model.bitmaps.collectAsState()
  val address by model.pairAddress.collectAsState()
  val port by model.pairPort.collectAsState()
  val pairCode by model.pairCode.collectAsState()
  val conversationCap by model.conversationCapText.collectAsState()
  val imageBudget by model.imageBudgetText.collectAsState()
  val showSettings = ui.settingsOpen
  val context = LocalContext.current
  val statusNoticeText = statusNotice(ui.banner)
  val holdNotice by model.holdNotice.collectAsState()
  // A missing window or a rejected sign-in is a toast. It is not a status chip.
  // A refused screen-off hold is a separate toast, not an authentication failure.
  LaunchedEffect(statusNoticeText, holdNotice) {
    val text = if (holdNotice.isNotEmpty()) holdNotice else statusNoticeText
    if (text.isEmpty()) return@LaunchedEffect
    Toast.makeText(context, text, Toast.LENGTH_LONG).show()
  }
  val cacheListOpen by model.cacheListOpen.collectAsState()
  val stored by model.storedBoard.collectAsState()
  val cacheRows by model.cacheRows.collectAsState()
  val cacheBackToList by model.cacheBackToList.collectAsState()
  val scope = rememberCoroutineScope()
  val pagerState = rememberPagerState(initialPage = pageForTab(tab)) { MainTabs.size }
  val drawerState = rememberDrawerState(DrawerValue.Closed) { next ->
    next != DrawerValue.Open || menuMayOpenDrawer(model.ui.value.approvalOpen)
  }
  var menuFlyout by remember { mutableStateOf<MenuSectionKind?>(null) }
  var hostWidthPx by remember { mutableIntStateOf(0) }
  var sheetWidthPx by remember { mutableIntStateOf(0) }
  var planPreviewOpen by remember { mutableStateOf(false) }
  var sectionPreview by remember { mutableStateOf<PlanRow?>(null) }
  // A cancelled swipe never settles on the other page, so dictation and plan refresh stay put.
  LaunchedEffect(ui.planPath) {
    if (!planLoaded(ui.planPath)) {
      planPreviewOpen = false
      sectionPreview = null
    }
  }
  LaunchedEffect(pagerState) {
    snapshotFlow { pagerState.settledPage }.collect { page ->
      val next = tabAfterSwipe(page, model.tab.value)
      if (next != null) model.selectTab(next)
    }
  }
  LaunchedEffect(showSettings) {
    if (showSettings) {
      menuFlyout = null
      closeDrawer(drawerState)
    }
  }
  LaunchedEffect(drawerState.targetValue) {
    if (drawerState.targetValue != DrawerValue.Open) menuFlyout = null
  }
  // One request when the sheet is actually open, the link is live, and a list is still empty.
  LaunchedEffect(drawerState.currentValue) {
    if (drawerState.currentValue == DrawerValue.Open)
      model.requestMenuChoices(link.phase == LinkPhase.Live)
  }
  BackHandler(enabled = showSettings || cacheListOpen || cacheBackToList) {
    when (settingsBackTarget(cacheListOpen, showSettings, cacheBackToList)) {
      SettingsBack.CacheList -> model.closeCachedList()
      SettingsBack.Settings -> model.closeSettings()
      SettingsBack.CacheReturn -> model.showCachedList()
      SettingsBack.None -> {}
    }
  }
  // Later than settings, so an open drawer wins back before settings or the activity finishes.
  BackHandler(enabled = drawerConsumesBack(drawerState.isOpen, drawerState.targetValue == DrawerValue.Open)) {
    menuFlyout = null
    scope.launch { closeDrawer(drawerState) }
  }
  // Later than the drawer, so an open flyout wins back and leaves the headings in place.
  BackHandler(enabled = menuFlyoutConsumesBack(menuFlyout != null)) {
    menuFlyout = null
  }
  val dismissDrawer: () -> Unit = {
    menuFlyout = null
    scope.launch { closeDrawer(drawerState) }
  }
  val shownFlyout = if (drawerState.currentValue == DrawerValue.Open) menuFlyout else null
  Scaffold { padding ->
    val modifier = Modifier.padding(padding).fillMaxSize()
    if (showSettings) {
      Box(modifier) {
        SettingsScreen(
          address, port, pairCode, ui.banner, link.phase, ui.disconnected, ui.showThinking, ui.showTools,
          conversationCap, imageBudget, true,
          { model.pairAddress.value = it },
          { model.pairPort.value = it },
          { model.pairCode.value = it },
          model::connectFromPair,
          model::setShowThinking,
          model::setShowTools,
          model::setConversationCapText,
          model::setImageBudgetText,
          model::showCachedList,
          model::closeSettings
        )
      }
    } else {
      Box(modifier.onSizeChanged { hostWidthPx = it.width }) {
        // Overlay, not a pager page. Conversation and Plan both stay underneath.
        ModalNavigationDrawer(
          drawerContent = {
            ModalDrawerSheet(
              modifier = Modifier.width(MenuSheetWidth).onSizeChanged { sheetWidthPx = it.width },
              windowInsets = WindowInsets(0, 0, 0, 0)
            ) {
              AppMenu(
                ui, shownFlyout, { menuFlyout = it }, dismissDrawer,
                model::setMode, model::selectPlanPath, model::selectTarget, model::selectConversation,
                model::selectModel, model::selectReasoning, model::selectPermissions
              )
            }
          },
          drawerState = drawerState,
          // The pager owns horizontal swipes. Conversation adds its own left-edge opener below.
          gesturesEnabled = false
        ) {
          Column(Modifier.fillMaxSize()) {
            MonitorHeader(
              onMenu = {
                if (menuMayOpenDrawer(ui.approvalOpen)) scope.launch { drawerState.open() }
              },
              onSettings = {
                scope.launch {
                  closeDrawer(drawerState)
                  planPreviewOpen = false
                  sectionPreview = null
                  model.showSettings()
                }
              },
              menuEnabled = menuMayOpenDrawer(ui.approvalOpen)
            )
            Box(Modifier.weight(1f).fillMaxWidth()) {
              Column(Modifier.fillMaxSize()) {
                MonitorTabs(pagerState.currentPage) { item ->
                  planPreviewOpen = false
                  sectionPreview = null
                  model.selectTab(item)
                  scope.launch { pagerState.animateScrollToPage(pageForTab(item)) }
                }
                // The other page stays composed, so a swipe shows the cached plan at once.
                HorizontalPager(
                  state = pagerState,
                  modifier = Modifier.weight(1f).fillMaxWidth(),
                  beyondViewportPageCount = 1,
                  userScrollEnabled = !ui.approvalOpen && !planPreviewOpen && sectionPreview == null
                ) { page ->
                  when (tabForPage(page)) {
                    AppTab.Conversation -> Box(
                      Modifier
                        .fillMaxSize()
                        .then(
                          if (menuEdgeSwipeEnabled(AppTab.Conversation, ui.approvalOpen)) {
                            Modifier.menuEdgeSwipeToOpen {
                              if (menuMayOpenDrawer(model.ui.value.approvalOpen)) scope.launch { drawerState.open() }
                            }
                          } else {
                            Modifier
                          }
                        )
                    ) {
                      ConversationScreen(
                        ui, link.phase, bitmaps, model::changePrompt, model::sendOrSteer, model::stop, model::newConversation,
                        model::noteVisibleTurns, model::noteViewWidth,
                        dictation, model::toggleDictationOn, model::toggleDictationOff,
                        permissionRequest, model::dictationPermission, model::consumeDictationPermissionRequest,
                        model::retryUndelivered, stored
                      )
                    }
                    AppTab.Plan -> PlanScreen(
                      ui, model::selectPlan, model::runPlan, model::stopPlan, model::newPlan, model::closePlan,
                      onPreview = {
                        planPreviewOpen = true
                        sectionPreview = null
                      },
                      onPreviewSection = { row ->
                        sectionPreview = row
                        planPreviewOpen = false
                      },
                      onCancelFetch = model::cancelPlanFetch,
                      onContinueFetch = model::continuePlanFetch
                    )
                  }
                }
              }
              val shownSection = sectionPreview
              var planWindow by remember { mutableStateOf("") }
              LaunchedEffect(planPreviewOpen, shownSection, ui.planPath, ui.planBody, ui.planTotal) {
                planWindow = if (ui.planTotal > PlanInlineBytes) model.readPlanWindow(shownSection)
                else if (shownSection == null) ui.planBody
                else planSectionExcerpt(ui.planBody, shownSection)
              }
              if ((planPreviewOpen || shownSection != null) && planLoaded(ui.planPath) && tabForPage(pagerState.currentPage) == AppTab.Plan) {
                val text = if (shownSection == null) planWindow.ifEmpty { ui.planBody } else planWindow.ifEmpty {
                  "This section is not in the loaded plan text yet."
                }
                PlanPreviewPanel(
                  if (shownSection == null) ui.planTitle else planSectionCaption(shownSection),
                  ui.planPath,
                  text,
                  if (shownSection == null) ui.planRows else emptyList(),
                  onDismiss = {
                    planPreviewOpen = false
                    sectionPreview = null
                  },
                  modifier = Modifier.fillMaxSize()
                )
              }
            }
            // Below the pager, so Conversation and Plan both keep the same status line.
            HorizontalDivider()
            ActivityStatus(
              ui,
              link.phase,
              dictation.listening,
              dictation.statusMessage,
              Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
            )
          }
        }
        DrawerScrimClose(drawerState, hostWidthPx, sheetWidthPx, dismissDrawer)
      }
    }
  }
  val notice = ui.approval
  if (cacheListOpen) {
    CachedListDialog(cacheRows, model::openCachedRow, model::pinCached, model::deleteCached, model::closeCachedList)
  }
  if (!showSettings && ui.approvalOpen && notice != null) {
    ApprovalSheet(notice, model::allowApproval, model::denyApproval, model::dismissApproval)
  }
  if (ui.saveQuestion.isNotEmpty()) {
    SaveQuestionDialog(onYes = { model.answerSaveQuestion(true) }, onNo = { model.answerSaveQuestion(false) })
  }
}

/** An approval sheet sits above the pages, so the menu button must not open the drawer. */
internal fun menuMayOpenDrawer(approvalOpen: Boolean): Boolean = !approvalOpen

/** The cache list sits on Settings, so back closes that list before the form. */
internal enum class SettingsBack { CacheList, Settings, CacheReturn, None }

internal fun settingsBackTarget(cacheListOpen: Boolean, settingsOpen: Boolean, cacheBackToList: Boolean): SettingsBack {
  if (cacheListOpen) return SettingsBack.CacheList
  if (settingsOpen) return SettingsBack.Settings
  if (cacheBackToList) return SettingsBack.CacheReturn
  return SettingsBack.None
}

/** Back closes the drawer before settings or the activity, including while the sheet is still sliding. */
internal fun drawerConsumesBack(isOpen: Boolean, targetOpen: Boolean): Boolean = isOpen || targetOpen

/**
 * Uncovered page width, in pixels. The sheet slides in from the start, so a negative offset still covers nothing.
 * Material 3 ignores scrim taps when gestures are disabled, and this strip is that close target.
 */
internal fun drawerScrimStripPx(hostWidthPx: Int, sheetWidthPx: Int, sheetOffsetPx: Float): Int {
  if (hostWidthPx <= 0 || sheetWidthPx <= 0 || sheetOffsetPx.isNaN()) return 0
  val covered = (sheetOffsetPx + sheetWidthPx).roundToInt().coerceIn(0, hostWidthPx)
  return hostWidthPx - covered
}

@OptIn(ExperimentalMaterial3Api::class)
private suspend fun closeDrawer(drawerState: DrawerState) {
  if (!drawerState.isClosed || drawerState.targetValue != DrawerValue.Closed) drawerState.close()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DrawerScrimClose(drawerState: DrawerState, hostWidthPx: Int, sheetWidthPx: Int, onClose: () -> Unit) {
  val settlingOpen = drawerConsumesBack(drawerState.isOpen, drawerState.targetValue == DrawerValue.Open)
  val offset = drawerState.currentOffset
  val stripPx = if (settlingOpen) drawerScrimStripPx(hostWidthPx, sheetWidthPx, offset) else 0
  if (stripPx <= 0) return
  val coveredPx = hostWidthPx - stripPx
  val strip = with(LocalDensity.current) { stripPx.toDp() }
  Box(
    Modifier
      .offset { IntOffset(coveredPx, 0) }
      .width(strip)
      .fillMaxHeight()
      .semantics { contentDescription = "Close menu" }
      .pointerInput(onClose) { detectTapGestures { onClose() } }
  )
}

@Composable
private fun MonitorHeader(onMenu: () -> Unit, onSettings: () -> Unit, menuEnabled: Boolean) {
  Row(
    Modifier.fillMaxWidth().padding(start = 4.dp, end = 4.dp, top = 4.dp),
    verticalAlignment = Alignment.CenterVertically
  ) {
    IconButton(onClick = onMenu, enabled = menuEnabled) {
      Icon(painterResource(R.drawable.ic_menu), contentDescription = "Menu")
    }
    Text(
      "Assistant Monitor",
      style = MaterialTheme.typography.headlineMedium,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
      modifier = Modifier.weight(1f)
    )
    IconButton(onClick = onSettings) {
      Icon(painterResource(R.drawable.ic_settings), contentDescription = "Settings")
    }
  }
}

@Composable
private fun MonitorTabs(selectedPage: Int, onSelect: (AppTab) -> Unit) {
  val page = selectedPage.coerceIn(0, MainTabs.lastIndex)
  TabRow(
    selectedTabIndex = page,
    containerColor = Color.Transparent,
    contentColor = MonitorTeal,
    indicator = { positions ->
      if (page in positions.indices) {
        TabRowDefaults.SecondaryIndicator(Modifier.tabIndicatorOffset(positions[page]), color = MonitorTeal)
      }
    }
  ) {
    MainTabs.forEach { item ->
      Tab(
        selected = page == pageForTab(item),
        onClick = { onSelect(item) },
        selectedContentColor = MonitorTeal,
        unselectedContentColor = MonitorQuiet,
        text = { Text(tabCaption(item)) }
      )
    }
  }
}
