package computing.michell.monitor

/* Monitor phone shell (c) 2026 Michell Computing. */

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.TabRowDefaults
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.ui.AppTab
import computing.michell.monitor.ui.ApprovalSheet
import computing.michell.monitor.ui.ConversationScreen
import computing.michell.monitor.ui.MainTabs
import computing.michell.monitor.ui.MonitorViewModel
import computing.michell.monitor.ui.PlanScreen
import computing.michell.monitor.ui.SettingsScreen
import computing.michell.monitor.ui.pageForTab
import computing.michell.monitor.ui.shellConnectionCaption
import computing.michell.monitor.ui.tabAfterSwipe
import computing.michell.monitor.ui.tabCaption
import computing.michell.monitor.ui.tabForPage
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

  override fun onStop() {
    if (!isChangingConfigurations) model.leaveDictation()
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
  val showSettings = ui.settingsOpen
  val scope = rememberCoroutineScope()
  val pagerState = rememberPagerState(initialPage = pageForTab(tab)) { MainTabs.size }
  // A cancelled swipe never settles on the other page, so dictation and plan refresh stay put.
  LaunchedEffect(pagerState) {
    snapshotFlow { pagerState.settledPage }.collect { page ->
      val next = tabAfterSwipe(page, model.tab.value)
      if (next != null) model.selectTab(next)
    }
  }
  val connected = link.phase == LinkPhase.Live && !ui.disconnected
  val connecting = link.phase == LinkPhase.Connecting
  BackHandler(enabled = showSettings) { model.closeSettings() }
  Scaffold { padding ->
    val modifier = Modifier.padding(padding).fillMaxSize()
    if (showSettings) {
      Box(modifier) {
        SettingsScreen(
          address, port, ui.banner, link.phase, ui.disconnected, ui.showThinking, ui.showTools, true,
          { model.pairAddress.value = it },
          { model.pairPort.value = it },
          model::connectFromPair,
          model::setShowThinking,
          model::setShowTools,
          model::closeSettings
        )
      }
    } else {
      Column(modifier.fillMaxSize()) {
        MonitorHeader(shellConnectionCaption(connected, connecting, ui.banner), connected, model::showSettings)
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
              model::setMode, model::requestTurn, model::noteVisibleTurns, model::noteViewWidth,
              dictation, model::toggleDictationOn, model::toggleDictationOff,
              permissionRequest, model::dictationPermission, model::consumeDictationPermissionRequest
            )
            AppTab.Plan -> PlanScreen(ui, model::selectPlan, model::workOnPlan, model::runPlan, model::stopPlan, model::newPlan, model::removePlan)
          }
        }
      }
    }
  }
  val notice = ui.approval
  if (!showSettings && ui.approvalOpen && notice != null) {
    ApprovalSheet(notice, model::allowApproval, model::denyApproval, model::dismissApproval)
  }
}

@Composable
private fun MonitorHeader(caption: String, connected: Boolean, onSettings: () -> Unit) {
  val statusColor = if (connected) MonitorTeal else MonitorQuiet
  Row(
    Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 4.dp),
    verticalAlignment = Alignment.CenterVertically
  ) {
    Text("Monitor", style = MaterialTheme.typography.headlineMedium, modifier = Modifier.weight(1f))
    Text(
      caption,
      color = statusColor,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
      style = MaterialTheme.typography.titleMedium,
      modifier = Modifier.widthIn(max = 160.dp)
    )
    Box(Modifier.padding(start = 8.dp).size(8.dp).clip(CircleShape).background(statusColor))
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
