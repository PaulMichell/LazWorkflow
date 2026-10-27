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
import computing.michell.monitor.protocol.PlanChoice

/** One quiet sentence for a section that has no tappable row. */
const val MenuEmptySentence = "Nothing to choose."

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
  val enabled: Boolean
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
 * Seven sections in drawer order. Lists already on the phone are Mode and Plan.
 * The others stay empty until their frames arrive. Disconnect disables rows and does not clear lists.
 */
fun appMenuSections(ui: MonitorUi): List<MenuSectionModel> {
  val linkUp = !ui.disconnected
  // setMode and openPlan both refuse when the mode cannot change. A row that cannot send stays disabled.
  val canSend = linkUp && ui.view.canChangeMode
  return listOf(
    MenuSectionModel(MenuSectionKind.Target, "Target", emptyList(), "", linkUp),
    MenuSectionModel(MenuSectionKind.Mode, "Mode", ModeChoices.map { MenuRow(it.first, it.second) }, ui.view.mode, canSend),
    MenuSectionModel(MenuSectionKind.Conversation, "Conversation", emptyList(), "", linkUp),
    MenuSectionModel(
      MenuSectionKind.Plan, "Plan", ui.planChoices.map { MenuRow(it.path, it.caption) }, ui.planPath, canSend
    ),
    MenuSectionModel(MenuSectionKind.Model, "Model", emptyList(), "", linkUp),
    MenuSectionModel(MenuSectionKind.Reasoning, "Reasoning Level", emptyList(), "", linkUp),
    MenuSectionModel(MenuSectionKind.Permissions, "Tool Permissions", emptyList(), "", linkUp)
  )
}

@Composable
fun AppMenu(ui: MonitorUi, onClose: () -> Unit, onMode: (String) -> Unit, onPlan: (String) -> Unit) {
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
      MenuSection(section, onClose, onMode, onPlan)
    }
  }
}

@Composable
private fun MenuSection(
  section: MenuSectionModel,
  onClose: () -> Unit,
  onMode: (String) -> Unit,
  onPlan: (String) -> Unit
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
          if (tap == MenuTap.CloseAndSend) sendMenuCommand(section.kind, row.id, onMode, onPlan)
        }
      }
    }
  }
}

/** Host refusals stay on the status banner. This does not open a dialog. */
private fun sendMenuCommand(kind: MenuSectionKind, id: String, onMode: (String) -> Unit, onPlan: (String) -> Unit) {
  when (kind) {
    MenuSectionKind.Mode -> onMode(id)
    MenuSectionKind.Plan -> onPlan(id)
    else -> Unit
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
