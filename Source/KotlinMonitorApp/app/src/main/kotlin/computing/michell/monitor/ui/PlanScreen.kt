package computing.michell.monitor.ui

/* Plan list. No Open action and no Done button (c) 2026 Michell Computing. */

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

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
    LazyColumn(modifier = Modifier.weight(1f)) {
      itemsIndexed(ui.planRows) { _, row ->
        val selected = row.index == ui.selectedPlan
        Text(
          "${row.title}  ${row.status}",
          modifier = Modifier.fillMaxWidth().clickable { onSelect(row.index) }.padding(start = (row.level * 12).dp, top = 8.dp, bottom = 8.dp),
          color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
        )
      }
    }
    OutlinedTextField(title, { title = it }, modifier = Modifier.fillMaxWidth(), label = { Text("New plan title") }, singleLine = true)
    Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      Button(onClick = onWork, enabled = ui.selectedPlan >= 0) { Text("Work on this") }
      Button(onClick = onRun) { Text("Run") }
      Button(onClick = onStop) { Text("Stop") }
      Button(onClick = { onNew(title.trim()) }) { Text("New") }
      Button(onClick = onRemove, enabled = ui.planPath.isNotEmpty()) { Text("Remove") }
    }
  }
}
