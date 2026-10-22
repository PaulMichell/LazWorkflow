package computing.michell.monitor.ui

/* Plan list. Status tags match the assistant plan list.
   Headings stay plain. No Open action and no Done button (c) 2026 Michell Computing. */

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
  onWork: () -> Unit,
  onRun: () -> Unit,
  onStop: () -> Unit,
  onNew: (String) -> Unit,
  onRemove: () -> Unit
) {
  var title by remember { mutableStateOf("") }
  Column(modifier = Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
    Text(ui.planTitle.ifEmpty { "Plan" }, style = MaterialTheme.typography.titleLarge)
    Text(ui.planPath, style = MaterialTheme.typography.bodySmall)
    if (ui.banner.isNotEmpty()) {
      Text(ui.banner, color = if (bannerIsStatus(ui.banner)) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.error)
    }
    LazyColumn(modifier = Modifier.weight(1f)) {
      items(ui.planRows) { row ->
        PlanRowLine(row.title, row.status, row.actionable, row.level, row.index == ui.selectedPlan) {
          onSelect(row.index)
        }
      }
    }
    OutlinedTextField(title, { title = it }, modifier = Modifier.fillMaxWidth(), label = { Text("New plan title") }, singleLine = true)
    Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      val online = !ui.disconnected
      Button(onClick = onWork, enabled = online && ui.selectedPlan >= 0) { Text("Work on this") }
      Button(onClick = onRun, enabled = online) { Text("Run") }
      Button(onClick = onStop, enabled = online) { Text("Stop") }
      Button(onClick = { onNew(title.trim()) }, enabled = online) { Text("New") }
      Button(onClick = onRemove, enabled = online && ui.planPath.isNotEmpty()) { Text("Remove") }
    }
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
