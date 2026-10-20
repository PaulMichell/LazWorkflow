package computing.michell.monitor

/* Monitor phone shell (c) 2026 Michell Computing. */

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import computing.michell.monitor.ui.AppTab
import computing.michell.monitor.ui.ApprovalSheet
import computing.michell.monitor.ui.ConversationScreen
import computing.michell.monitor.ui.MonitorViewModel
import computing.michell.monitor.ui.SettingsScreen
import computing.michell.monitor.ui.PlanScreen


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
  val link by model.link.collectAsState()
  val bitmaps by model.bitmaps.collectAsState()
  val address by model.pairAddress.collectAsState()
  val port by model.pairPort.collectAsState()
  val forcedSettings = ui.pairHold || !ui.reachedLive || link.banner == "TLS pin mismatch."
  val showSettings = forcedSettings || ui.settingsOpen
  BackHandler(enabled = showSettings && !forcedSettings) { model.closeSettings() }
  Scaffold(
    bottomBar = {
      if (!showSettings) {
        NavigationBar {
          NavigationBarItem(tab == AppTab.Conversation, { model.selectTab(AppTab.Conversation) }, label = { Text("Conversation") }, icon = {})
          NavigationBarItem(tab == AppTab.Plan, { model.selectTab(AppTab.Plan) }, label = { Text("Plan") }, icon = {})
        }
      }
    }
  ) { padding ->
    val modifier = Modifier.padding(padding)
    androidx.compose.foundation.layout.Box(modifier) {
      if (showSettings) {
        SettingsScreen(
          address, port, ui.banner, ui.showThinking, ui.showTools, !forcedSettings,
          { model.pairAddress.value = it },
          { model.pairPort.value = it },
          model::connectFromPair,
          model::setShowThinking,
          model::setShowTools,
          model::closeSettings
        )
      } else when (tab) {
        AppTab.Conversation -> ConversationScreen(
          ui, link.phase, bitmaps, model::updateDraft, model::sendOrSteer, model::stop, model::newConversation,
          model::setMode, model::requestTurn, model::showSettings, dictation.sendMustWait
        )
        AppTab.Plan -> PlanScreen(ui, model::selectPlan, model::workOnPlan, model::runPlan, model::stopPlan, model::newPlan, model::removePlan)
      }
    }
  }
  val notice = ui.approval
  if (!showSettings && ui.approvalOpen && notice != null) {
    ApprovalSheet(notice, model::allowApproval, model::denyApproval, model::dismissApproval)
  }
}
