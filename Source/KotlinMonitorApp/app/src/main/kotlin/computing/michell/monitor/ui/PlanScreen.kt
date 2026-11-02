package computing.michell.monitor.ui

/* Plan list. Status tags match the assistant plan list.
   The title and document name scroll with the rows.
   Headings stay plain. Run becomes Stop while a run is going.
   Open previews the plan document. (c) 2026 Michell Computing. */

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.activity.compose.BackHandler
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import computing.michell.monitor.protocol.PlanRow
import java.util.Locale

/* Slightly rounded, not a capsule. Same 4px corner as BuildTodoListDrawItem. */
private val PlanTagShape = RoundedCornerShape(4.dp)

/** Pastel fill, darker ink, darker border. Colours match the assistant plan tags. */
data class PlanMarker(
  val caption: String,
  val fill: Int,
  val ink: Int,
  val border: Int
)

/**
 * Tag for an actionable row. Headings and unknown statuses have none.
 * Wire values are the assistant status strings: not started, in progress, complete, blocked.
 */
fun planLoaded(path: String): Boolean = path.isNotEmpty()

fun planRunCaption(running: Boolean): String = if (running) "Stop" else "Run"

/** Stop stays available during a run. Run waits until the current reply has finished. */
fun planRunEnabled(loaded: Boolean, online: Boolean, running: Boolean, sending: Boolean): Boolean {
  if (!online || !loaded) return false
  if (running) return true
  return !sending
}

/** New, Open, and Close wait until the run ends. Stop stays on the Run button. */
fun planHostButtonEnabled(loaded: Boolean, online: Boolean, running: Boolean): Boolean =
  loaded && online && !running

fun planNewEnabled(online: Boolean, running: Boolean): Boolean = online && !running

fun planOpenEnabled(loaded: Boolean, running: Boolean): Boolean = loaded && !running

fun planMarker(status: String, actionable: Boolean): PlanMarker? {
  if (!actionable) return null
  return when (status.trim().lowercase(Locale.ROOT)) {
    "not started" -> PlanMarker("Not Started", 0xFFFFF3CD.toInt(), 0xFF795500.toInt(), 0xFFD4A017.toInt())
    "in progress" -> PlanMarker("In Progress", 0xFFE8F5E9.toInt(), 0xFF1B5E20.toInt(), 0xFF43A047.toInt())
    "complete" -> PlanMarker("Complete", 0xFFE3F2FD.toInt(), 0xFF0D47A1.toInt(), 0xFF42A5F5.toInt())
    "blocked" -> PlanMarker("Blocked", 0xFFFFEBEE.toInt(), 0xFFB71C1C.toInt(), 0xFFE53935.toInt())
    else -> null
  }
}

@Composable
fun PlanScreen(
  ui: MonitorUi,
  onSelect: (Int) -> Unit,
  onRun: () -> Unit,
  onStop: () -> Unit,
  onNew: () -> Unit,
  onClose: () -> Unit,
  onPreview: () -> Unit
) {
  val loaded = planLoaded(ui.planPath)
  val running = ui.planRunning || ui.view.planRunning
  val online = !ui.disconnected
  Column(modifier = Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
    LazyColumn(modifier = Modifier.weight(1f)) {
      if (!loaded && ui.planTitle.isEmpty() && ui.planRows.isEmpty()) {
        item {
          Text("No plan is loaded.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
      }
      if (ui.planTitle.isNotEmpty() || ui.planPath.isNotEmpty()) {
        item {
          PlanHeading(ui.planTitle, ui.planPath)
        }
      }
      items(ui.planRows) { row ->
        PlanRowLine(row.title, row.status, row.actionable, row.level, row.index == ui.selectedPlan) {
          onSelect(row.index)
        }
      }
    }
    Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      Button(
        onClick = { if (running) onStop() else onRun() },
        enabled = planRunEnabled(loaded, online, running, ui.view.sending || ui.view.busy)
      ) { Text(planRunCaption(running)) }
      // New does not need a loaded plan. It is how the first plan is created.
      Button(onClick = onNew, enabled = planNewEnabled(online, running)) { Text("New") }
      Button(onClick = onPreview, enabled = planOpenEnabled(loaded, running)) { Text("Open") }
      Button(onClick = onClose, enabled = planHostButtonEnabled(loaded, online, running)) { Text("Close") }
    }
  }
}

/** Fills the slot under the title header and above the status line. Full screen width. */
@Composable
fun PlanPreviewPanel(
  title: String,
  path: String,
  body: String,
  rows: List<PlanRow>,
  onDismiss: () -> Unit,
  modifier: Modifier = Modifier
) {
  BackHandler(onBack = onDismiss)
  val heading = title.ifEmpty { "Plan" }
  Surface(
    modifier = modifier
      .fillMaxSize()
      .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {},
    color = MaterialTheme.colorScheme.surface
  ) {
    Column(Modifier.fillMaxSize()) {
      HorizontalDivider()
      Column(
        modifier = Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
      ) {
        Text(heading, style = MaterialTheme.typography.titleMedium)
        if (path.isNotEmpty()) {
          Text(
            path,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodySmall,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
          )
        }
        if (body.isNotEmpty()) {
          MarkdownText(body, modifier = Modifier.fillMaxWidth())
        } else {
          Text(
            "The plan text has not arrived yet.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.fillMaxWidth()
          )
          rows.forEach { row ->
            Text(
              "  ".repeat(row.level.coerceAtLeast(0)) + row.title,
              modifier = Modifier.fillMaxWidth(),
              maxLines = 2,
              overflow = TextOverflow.Ellipsis
            )
          }
        }
      }
      HorizontalDivider()
      Row(
        modifier = Modifier.fillMaxWidth().padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
      ) {
        Button(onClick = onDismiss) { Text("Close") }
      }
    }
  }
}

@Composable
private fun PlanHeading(title: String, path: String) {
  Column(
    modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
    verticalArrangement = Arrangement.spacedBy(4.dp)
  ) {
    if (title.isNotEmpty()) Text(title, style = MaterialTheme.typography.titleLarge)
    if (path.isNotEmpty()) Text(path, style = MaterialTheme.typography.bodySmall)
  }
}

@Composable
private fun PlanRowLine(
  title: String,
  status: String,
  actionable: Boolean,
  level: Int,
  selected: Boolean,
  onSelect: () -> Unit
) {
  val marker = planMarker(status, actionable)
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .clickable(onClick = onSelect)
      .padding(start = (level * 12).dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(6.dp)
  ) {
    Text(
      title,
      modifier = Modifier.weight(1f),
      color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
      fontWeight = if (actionable) FontWeight.Normal else FontWeight.Bold,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis
    )
    if (marker != null) PlanStatusTag(marker)
  }
}

@Composable
private fun PlanStatusTag(marker: PlanMarker) {
  Text(
    marker.caption,
    modifier = Modifier
      .background(Color(marker.fill), PlanTagShape)
      .border(1.dp, Color(marker.border), PlanTagShape)
      .padding(horizontal = 6.dp, vertical = 2.dp),
    color = Color(marker.ink),
    fontSize = 11.sp,
    lineHeight = 13.sp,
    fontWeight = FontWeight.Normal,
    maxLines = 1,
    softWrap = false
  )
}
