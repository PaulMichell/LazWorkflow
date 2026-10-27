package computing.michell.monitor.ui

/* App menu drawer. Seven sections, host check only (c) 2026 Michell Computing. */

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import computing.michell.monitor.protocol.ConversationChoice
import computing.michell.monitor.protocol.PlanChoice
import computing.michell.monitor.protocol.TargetChoice

/** One quiet sentence for a section that has no tappable row. */
const val MenuEmptySentence = "Nothing to choose."

/** Empty path is the open project, not a folder caption. */
const val CurrentProjectCaption = "Current Project"

fun targetChoiceCaption(choice: TargetChoice): String {
  if (choice.path.isEmpty()) return CurrentProjectCaption
  return choice.caption
}

/** Target rows stay put while disconnected, sending, or a plan run. */
fun targetRowsEnabled(disconnected: Boolean, sending: Boolean, planRunning: Boolean): Boolean {
  return !disconnected && !sending && !planRunning
}

/** Shown under the history list when the host omitted older archives. */
const val OlderConversationsSentence = "Older conversations stay on the desktop."

/** Model rows stay put while disconnected, sending, or a plan run. */
fun modelRowsEnabled(disconnected: Boolean, sending: Boolean, planRunning: Boolean): Boolean {
  return !disconnected && !sending && !planRunning
}

/** Reasoning rows use the same gate as the model list. */
fun reasoningRowsEnabled(disconnected: Boolean, sending: Boolean, planRunning: Boolean): Boolean {
  return modelRowsEnabled(disconnected, sending, planRunning)
}

/** Permission rows use the same gate. This is the footer mode, not the approval sheet. */
fun permissionRowsEnabled(disconnected: Boolean, sending: Boolean, planRunning: Boolean): Boolean {
  return modelRowsEnabled(disconnected, sending, planRunning)
}

/** History rows stay put while disconnected or sending. A plan run does not lock them. */
fun conversationRowsEnabled(disconnected: Boolean, sending: Boolean): Boolean {
  return !disconnected && !sending
}

/** The check is the flagged row, or the row whose id equals the host current. */
fun conversationSelectedId(choices: List<ConversationChoice>, current: String): String {
  val flagged = choices.firstOrNull { it.current }
  if (flagged != null) return flagged.id
  return current
}

enum class MenuSectionKind {
  Target,
  Mode,
  Conversation,
  Plan,
  Model,
  Reasoning,
  Permissions
}

enum class MenuTap {
  CloseOnly,
  CloseAndSend
}

data class MenuRow(val id: String, val caption: String)

data class MenuSectionModel(
  val kind: MenuSectionKind,
  val label: String,
  val rows: List<MenuRow>,
  val currentId: String,
  val enabled: Boolean,
  val note: String = ""
)

/** The check is the host id. A tap must not paint a new one before the next frame. */
fun menuCheckedId(hostId: String): String = hostId

/** Choosing the current row closes and sends nothing. Another row closes and sends. A disabled row does neither. */
fun menuTap(rowId: String, currentId: String, enabled: Boolean): MenuTap? {
  if (!enabled) return null
  if (rowId == currentId) return MenuTap.CloseOnly
  return MenuTap.CloseAndSend
}

fun menuHeader(ui: MonitorUi): String = ui.view.targetDisplay

/**
 * Seven sections in drawer order. Mode and Plan are already on the phone.
 * Target, Conversation, Model, Reasoning, and Tool Permissions fill from their host frames.
 * Disconnect disables rows and does not clear lists.
 */
fun appMenuSections(ui: MonitorUi): List<MenuSectionModel> {
  val linkUp = !ui.disconnected
  // Mode sends set_mode only when canChangeMode is true and the link is up, the same gate setMode can complete.
  val canSend = linkUp && ui.view.canChangeMode
  val targetEnabled = targetRowsEnabled(ui.disconnected, ui.view.sending, ui.view.planRunning || ui.planRunning)
  val historyEnabled = conversationRowsEnabled(ui.disconnected, ui.view.sending)
  val modelEnabled = modelRowsEnabled(ui.disconnected, ui.view.sending, ui.view.planRunning || ui.planRunning)
  val reasoningEnabled = reasoningRowsEnabled(ui.disconnected, ui.view.sending, ui.view.planRunning || ui.planRunning)
  val permissionEnabled = permissionRowsEnabled(ui.disconnected, ui.view.sending, ui.view.planRunning || ui.planRunning)
  val historyNote = if (ui.conversationsTruncated) OlderConversationsSentence else ""
  return listOf(
    MenuSectionModel(
      MenuSectionKind.Target, "Target",
      ui.targetChoices.map { MenuRow(it.path, targetChoiceCaption(it)) },
      ui.targetCurrent, targetEnabled
    ),
    MenuSectionModel(
      MenuSectionKind.Mode, "Mode", ModeChoices.map { MenuRow(it.first, modeCaption(it.first)) }, ui.view.mode, canSend
    ),
    MenuSectionModel(
      MenuSectionKind.Conversation, "Conversation",
      ui.conversationChoices.map { MenuRow(it.id, it.title) },
      conversationSelectedId(ui.conversationChoices, ui.conversationCurrent),
      historyEnabled, historyNote
    ),
    // Captions from planChoices. The check is planPath. A different row calls openPlan.
    MenuSectionModel(
      MenuSectionKind.Plan, "Plan", ui.planChoices.map { MenuRow(it.path, it.caption) }, ui.planPath, canSend
    ),
    MenuSectionModel(
      MenuSectionKind.Model, "Model",
      ui.modelChoices.map { MenuRow(it.id, it.caption) },
      ui.view.model, modelEnabled, ui.modelNote
    ),
    // The check is reasoningCurrent. view.effort is a caption and must not select a row.
    MenuSectionModel(
      MenuSectionKind.Reasoning, "Reasoning Level",
      ui.reasoningChoices.map { MenuRow(it.id, it.caption) },
      ui.reasoningCurrent, reasoningEnabled, ui.reasoningNote
    ),
    // The check is permissionCurrent. view.approvalCaption is a short word and must not select a row.
    MenuSectionModel(
      MenuSectionKind.Permissions, "Tool Permissions",
      ui.permissionChoices.map { MenuRow(it.id, it.caption) },
      ui.permissionCurrent, permissionEnabled, ui.permissionNote
    )
  )
}

@Composable
fun AppMenu(
  ui: MonitorUi,
  onClose: () -> Unit,
  onMode: (String) -> Unit,
  onPlan: (String) -> Unit,
  onTarget: (String) -> Unit,
  onConversation: (String) -> Unit,
  onModel: (String) -> Unit,
  onReasoning: (String) -> Unit,
  onPermissions: (String) -> Unit
) {
  Column(
    Modifier
      .fillMaxSize()
      .verticalScroll(rememberScrollState())
      .padding(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 16.dp)
  ) {
    Text(
      menuHeader(ui),
      style = MaterialTheme.typography.titleMedium,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
      modifier = Modifier.fillMaxWidth()
    )
    appMenuSections(ui).forEach { section ->
      MenuSection(section, onClose, onMode, onPlan, onTarget, onConversation, onModel, onReasoning, onPermissions)
    }
  }
}

@Composable
private fun MenuSection(
  section: MenuSectionModel,
  onClose: () -> Unit,
  onMode: (String) -> Unit,
  onPlan: (String) -> Unit,
  onTarget: (String) -> Unit,
  onConversation: (String) -> Unit,
  onModel: (String) -> Unit,
  onReasoning: (String) -> Unit,
  onPermissions: (String) -> Unit
) {
  Column(Modifier.fillMaxWidth().padding(top = 12.dp)) {
    Text(section.label, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
    if (section.rows.isEmpty()) {
      Text(
        MenuEmptySentence,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 4.dp)
      )
    } else {
      section.rows.forEach { row ->
        val current = row.id == menuCheckedId(section.currentId)
        MenuRowLine(row.caption, current, section.enabled) {
          val tap = menuTap(row.id, section.currentId, section.enabled) ?: return@MenuRowLine
          onClose()
          if (tap == MenuTap.CloseAndSend) {
            sendMenuCommand(section.kind, row.id, onMode, onPlan, onTarget, onConversation, onModel, onReasoning,
              onPermissions)
          }
        }
      }
    }
    if (section.note.isNotEmpty()) {
      Text(
        section.note,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 4.dp)
      )
    }
  }
}

/** Host refusals stay on the status banner. This does not open a dialog. */
private fun sendMenuCommand(
  kind: MenuSectionKind,
  id: String,
  onMode: (String) -> Unit,
  onPlan: (String) -> Unit,
  onTarget: (String) -> Unit,
  onConversation: (String) -> Unit,
  onModel: (String) -> Unit,
  onReasoning: (String) -> Unit,
  onPermissions: (String) -> Unit
) {
  when (kind) {
    MenuSectionKind.Mode -> onMode(id)
    MenuSectionKind.Plan -> onPlan(id)
    MenuSectionKind.Target -> onTarget(id)
    MenuSectionKind.Conversation -> onConversation(id)
    MenuSectionKind.Model -> onModel(id)
    MenuSectionKind.Reasoning -> onReasoning(id)
    // Footer approval mode. Do not call allowApproval or denyApproval from here.
    MenuSectionKind.Permissions -> onPermissions(id)
  }
}

@Composable
private fun MenuRowLine(caption: String, current: Boolean, enabled: Boolean, onClick: () -> Unit) {
  val color = when {
    current -> MaterialTheme.colorScheme.primary
    enabled -> MaterialTheme.colorScheme.onSurface
    else -> MaterialTheme.colorScheme.onSurfaceVariant
  }
  Box(
    Modifier
      .fillMaxWidth()
      .defaultMinSize(minHeight = 48.dp)
      .clickable(enabled = enabled, onClick = onClick)
      .semantics { selected = current },
    contentAlignment = Alignment.CenterStart
  ) {
    Text(caption, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
  }
}
