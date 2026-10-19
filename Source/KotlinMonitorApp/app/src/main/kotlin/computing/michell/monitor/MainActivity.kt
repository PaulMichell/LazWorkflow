package computing.michell.monitor

/* Monitor phone shell (c) 2026 Michell Computing. */

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
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
import androidx.lifecycle.viewmodel.compose.viewModel
import computing.michell.monitor.ui.AppTab
import computing.michell.monitor.ui.ApprovalSheet
import computing.michell.monitor.ui.ConversationScreen
import computing.michell.monitor.ui.MonitorViewModel
import computing.michell.monitor.ui.PairScreen
import computing.michell.monitor.ui.PlanScreen
import computing.michell.monitor.ui.TasksScreen

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent {
      MaterialTheme {
        MonitorShell()
      }
    }
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MonitorShell(model: MonitorViewModel = viewModel()) {
  val ui by model.ui.collectAsState()
  val tab by model.tab.collectAsState()
  val link by model.link.collectAsState()
  val bitmaps by model.bitmaps.collectAsState()
  val address by model.pairAddress.collectAsState()
  val port by model.pairPort.collectAsState()
  val fingerprint by model.pairFingerprint.collectAsState()
  val code by model.pairCode.collectAsState()
  val showPair = !ui.reachedLive || ui.pairHold || link.banner == "TLS pin mismatch."
  Scaffold(
    bottomBar = {
      if (!showPair) {
        NavigationBar {
          NavigationBarItem(tab == AppTab.Conversation, { model.selectTab(AppTab.Conversation) }, label = { Text("Conversation") }, icon = {})
          NavigationBarItem(tab == AppTab.Plan, { model.selectTab(AppTab.Plan) }, label = { Text("Plan") }, icon = {})
          NavigationBarItem(tab == AppTab.Tasks, { model.selectTab(AppTab.Tasks) }, label = { Text("Tasks") }, icon = {})
        }
      }
    }
  ) { padding ->
    val modifier = Modifier.padding(padding)
    androidx.compose.foundation.layout.Box(modifier) {
      if (showPair) {
        PairScreen(
          address, port, fingerprint, code, ui.banner,
          { model.pairAddress.value = it },
          { model.pairPort.value = it },
          { model.pairFingerprint.value = it },
          { model.pairCode.value = it },
          model::connectFromPair
        )
      } else when (tab) {
        AppTab.Conversation -> ConversationScreen(ui, link.phase, bitmaps, model::updateDraft, model::sendOrSteer, model::stop, model::setMode, model::selectTurn)
        AppTab.Plan -> PlanScreen(ui, model::selectPlan, model::workOnPlan, model::runPlan, model::stopPlan, model::newPlan, model::removePlan)
        AppTab.Tasks -> TasksScreen(ui, model::runTask, model::insertTask)
      }
    }
  }
  val notice = ui.approval
  if (!showPair && ui.approvalOpen && notice != null) {
    ApprovalSheet(notice, model::allowApproval, model::denyApproval, model::dismissApproval)
  }
}
