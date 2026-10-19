package computing.michell.monitor.ui

/* Approval sheet. Codex and Claude turns do not raise this message (c) 2026 Michell Computing. */

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import computing.michell.monitor.protocol.ApprovalNotice

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ApprovalSheet(notice: ApprovalNotice, onAllow: () -> Unit, onDeny: () -> Unit, onDismiss: () -> Unit) {
  ModalBottomSheet(onDismissRequest = onDismiss) {
    Column(modifier = Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
      Text(notice.toolName)
      Text(summaryText(notice.summary))
      if (!notice.decisionsAccepted) {
        Text("The decision is on the desktop.")
      } else {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
          Button(onClick = onAllow) { Text("Allow") }
          Button(onClick = onDeny) { Text("Deny") }
        }
      }
    }
  }
}

fun summaryText(summary: String): String {
  if (summary.length <= 240) return summary
  return summary.take(240) + "…"
}
