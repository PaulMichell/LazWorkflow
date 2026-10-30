package computing.michell.monitor

/* Monitor phone shell (c) 2026 Michell Computing. */

import android.os.Bundle
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
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
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
import computing.michell.monitor.ui.ApprovalSheet
import computing.michell.monitor.ui.CachedListDialog
import computing.michell.monitor.ui.ConversationScreen
import computing.michell.monitor.ui.MainTabs
import computing.michell.monitor.ui.MonitorViewModel
import computing.michell.monitor.ui.PlanScreen
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

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent {
      MaterialTheme {
        MonitorShell(model)
      }
    }
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
  val conversationCap by model.conversationCapText.collectAsState()
  val imageBudget by model.imageBudgetText.collectAsState()
  val showSettings = ui.settingsOpen
  val cacheListOpen by model.cacheListOpen.collectAsState()
  val cacheRows by model.cacheRows.collectAsState()
  val cacheBackToList by model.cacheBackToList.collectAsState()
  val scope = rememberCoroutineScope()
  val pagerState = rememberPagerState(initialPage = pageForTab(tab)) { MainTabs.size }
  val drawerState = rememberDrawerState(DrawerValue.Closed) { next ->
    next != DrawerValue.Open || menuMayOpenDrawer(model.ui.value.approvalOpen)
  }
  var hostWidthPx by remember { mutableIntStateOf(0) }
  var sheetWidthPx by remember { mutableIntStateOf(0) }
  // A cancelled swipe never settles on the other page, so dictation and plan refresh stay put.
  LaunchedEffect(pagerState) {
    snapshotFlow { pagerState.settledPage }.collect { page ->
      val next = tabAfterSwipe(page, model.tab.value)
      if (next != null) model.selectTab(next)
    }
  }
  LaunchedEffect(showSettings) {
    if (showSettings) closeDrawer(drawerState)
  }
  // One request when the sheet is actually open, the link is live, and a list is still empty.
  LaunchedEffect(drawerState.currentValue) {
    if (drawerState.currentValue == DrawerValue.Open)
      model.requestMenuChoices(link.phase == LinkPhase.Live)
  }
  BackHandler(enabled = showSettings || cacheListOpen || cacheBackToList) {
    when {
      showSettings -> model.closeSettings()
      cacheListOpen -> model.closeCachedList()
      cacheBackToList -> model.showCachedList()
    }
  }
  // Later than settings, so an open drawer wins back before settings or the activity finishes.
  BackHandler(enabled = drawerConsumesBack(drawerState.isOpen, drawerState.targetValue == DrawerValue.Open)) {
    scope.launch { closeDrawer(drawerState) }
  }
  val dismissDrawer: () -> Unit = { scope.launch { closeDrawer(drawerState) } }
  Scaffold { padding ->
    val modifier = Modifier.padding(padding).fillMaxSize()
    if (showSettings) {
      Box(modifier) {
        SettingsScreen(
          address, port, ui.banner, link.phase, ui.disconnected, ui.showThinking, ui.showTools,
          conversationCap, imageBudget, true,
          { model.pairAddress.value = it },
          { model.pairPort.value = it },
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
              modifier = Modifier.onSizeChanged { sheetWidthPx = it.width },
              windowInsets = WindowInsets(0, 0, 0, 0)
            ) {
              AppMenu(ui, dismissDrawer, model::setMode, model::openPlan, model::selectTarget, model::selectConversation,
                model::selectModel, model::selectReasoning, model::selectPermissions)
            }
          },
          drawerState = drawerState,
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
                  model.showSettings()
                }
              },
              menuEnabled = menuMayOpenDrawer(ui.approvalOpen)
            )
            MonitorTabs(pagerState.currentPage) { item ->
              model.selectTab(item)
              scope.launch { pagerState.animateScrollToPage(pageForTab(item)) }
            }
            HorizontalPager(
              state = pagerState,
              modifier = Modifier.weight(1f).fillMaxWidth(),
              userScrollEnabled = !ui.approvalOpen
            ) { page ->
              when (tabForPage(page)) {
                AppTab.Conversation -> ConversationScreen(
                  ui, link.phase, bitmaps, model::changePrompt, model::sendOrSteer, model::stop, model::newConversation,
                  model::requestTurn, model::noteVisibleTurns, model::noteViewWidth,
                  dictation, model::toggleDictationOn, model::toggleDictationOff,
                  permissionRequest, model::dictationPermission, model::consumeDictationPermissionRequest,
                  model::retryUndelivered
                )
                AppTab.Plan -> PlanScreen(ui, model::selectPlan, model::runPlan, model::stopPlan, model::newPlan, model::removePlan)
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
  if (!showSettings && cacheListOpen) {
    CachedListDialog(cacheRows, model::openCachedRow, model::pinCached, model::deleteCached, model::closeCachedList)
  }
  if (!showSettings && ui.approvalOpen && notice != null) {
    ApprovalSheet(notice, model::allowApproval, model::denyApproval, model::dismissApproval)
  }
}

/** An approval sheet sits above the pages, so the menu button must not open the drawer. */
internal fun menuMayOpenDrawer(approvalOpen: Boolean): Boolean = !approvalOpen

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
