package computing.michell.monitor.ui

/* Stored conversations for one host. Newest first, pinned rows first.
   Opening does not require a socket. (c) 2026 Michell Computing. */

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import computing.michell.monitor.data.ConversationRecord

@Composable
fun CachedListDialog(
  rows: List<ConversationRecord>,
  onChoose: (ConversationRecord) -> Unit,
  onPin: (ConversationRecord) -> Unit,
  onDelete: (ConversationRecord) -> Unit,
  onBack: () -> Unit
) {
  Dialog(onDismissRequest = onBack) {
    Surface(modifier = Modifier.fillMaxWidth()) {
      Column(
        modifier = Modifier.padding(16.dp).heightIn(max = 480.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(8.dp)
      ) {
        TextButton(onClick = onBack) { Text("Back") }
        if (rows.isEmpty()) {
          Text("No stored conversations for this host.")
        } else {
          rows.forEach { row ->
            Column(modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
              Text(
                cacheRowTitle(row),
                modifier = Modifier.fillMaxWidth().clickable { onChoose(row) }
              )
              val project = projectDisplay(row.projectRoot)
              if (project.isNotEmpty()) Text(project)
              val updated = cacheUpdatedText(row.updatedAt)
              if (updated.isNotEmpty()) Text(updated)
              Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = { onPin(row) }) { Text(if (row.pinned) "Unpin" else "Pin") }
                TextButton(onClick = { onDelete(row) }) { Text("Delete") }
              }
            }
          }
        }
      }
    }
  }
}
