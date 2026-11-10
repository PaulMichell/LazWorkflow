package computing.michell.monitor.ui

/* The desktop's save question, asked on the phone (c) 2026 Michell Computing.
   The desktop refused a prompt or Run Plan because it has unsaved edits that the turn could change. Yes asks it to
   save everything and then start; No leaves the prompt in the box and starts nothing. */

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import computing.michell.monitor.protocol.SaveBeforeTurnQuestion

@Composable
fun SaveQuestionDialog(onYes: () -> Unit, onNo: () -> Unit) {
  AlertDialog(
    onDismissRequest = onNo,
    title = { Text("Unsaved edits on the desktop") },
    text = { Text(SaveBeforeTurnQuestion) },
    confirmButton = { TextButton(onClick = onYes) { Text("Yes") } },
    dismissButton = { TextButton(onClick = onNo) { Text("No") } }
  )
}
