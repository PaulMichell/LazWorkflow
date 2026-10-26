package computing.michell.monitor.ui

/* Cached conversation list. Only while the link is down. No drawer. (c) 2026 Michell Computing. */

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import computing.michell.monitor.protocol.CacheIndexEntry

@Composable
fun CachedListDialog(
  rows: List<CacheIndexEntry>,
  onChoose: (CacheIndexEntry) -> Unit,
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
          Text(OfflineBanner)
        } else {
          rows.forEach { row ->
            Column(
              modifier = Modifier.fillMaxWidth().clickable { onChoose(row) }.padding(vertical = 8.dp),
              verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
              Text(cacheRowTitle(row))
              val project = projectDisplay(row.projectRoot)
              if (project.isNotEmpty()) Text(project)
              val updated = cacheUpdatedText(row.updatedMs)
              if (updated.isNotEmpty()) Text(updated)
            }
          }
        }
      }
    }
  }
}
