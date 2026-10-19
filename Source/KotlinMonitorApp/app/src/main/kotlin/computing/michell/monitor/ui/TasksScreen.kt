package computing.michell.monitor.ui

/* Task list. Format and compile-first rows stay visible and disabled (c) 2026 Michell Computing. */

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import computing.michell.monitor.protocol.TaskRow

@Composable
fun TasksScreen(ui: MonitorUi, onRun: (TaskRow, String) -> Unit, onInsert: (TaskRow, String) -> Unit) {
  var selectedId by remember { mutableStateOf("") }
  var note by remember { mutableStateOf("") }
  val selected = ui.taskRows.firstOrNull { it.id == selectedId }
  Column(modifier = Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
    Text("Tasks", style = MaterialTheme.typography.titleLarge)
    LazyColumn(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
      items(ui.taskRows) { row ->
        Column(
          modifier = Modifier.fillMaxWidth().clickable { selectedId = row.id }.padding(8.dp)
        ) {
          Text(row.title, color = if (row.id == selectedId) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface)
          Text("${row.mode}  ${row.scope}", style = MaterialTheme.typography.bodySmall)
          if (row.summary.isNotEmpty()) Text(row.summary)
          val reason = row.desktopOnlyReason()
          if (reason.isNotEmpty()) Text(reason, color = MaterialTheme.colorScheme.error)
        }
      }
    }
    if (selected?.needsNote == true) {
      OutlinedTextField(note, { note = it }, modifier = Modifier.fillMaxWidth(), label = { Text("Note") })
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      Button(onClick = { selected?.let { onRun(it, note) } }, enabled = selected?.isRunnable() == true) { Text("Run") }
      Button(onClick = { selected?.let { onInsert(it, note) } }, enabled = selected?.isRunnable() == true) { Text("Insert") }
    }
  }
}
