package computing.michell.monitor.ui

/* Settings form. View options and the desktop connection (c) 2026 Michell Computing. */

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import computing.michell.monitor.protocol.MonitorLimits

@Composable
fun SettingsScreen(
  address: String,
  port: String,
  errorText: String,
  showThinking: Boolean,
  showTools: Boolean,
  canLeave: Boolean,
  onAddress: (String) -> Unit,
  onPort: (String) -> Unit,
  onConnect: () -> Unit,
  onThinking: (Boolean) -> Unit,
  onTools: (Boolean) -> Unit,
  onBack: () -> Unit
) {
  Column(
    modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
    verticalArrangement = Arrangement.spacedBy(12.dp)
  ) {
    if (canLeave) {
      TextButton(onClick = onBack) { Text("Back") }
    }
    Text("Settings", style = MaterialTheme.typography.headlineSmall)
    Text("View", style = MaterialTheme.typography.titleMedium)
    OptionRow("Thinking", showThinking, onThinking)
    OptionRow("Tool calls", showTools, onTools)
    Text("Connection", style = MaterialTheme.typography.titleMedium)
    OutlinedTextField(address, onAddress, modifier = Modifier.fillMaxWidth(), label = { Text("Host address") }, singleLine = true)
    OutlinedTextField(port, onPort, modifier = Modifier.fillMaxWidth(), label = { Text("Port") }, singleLine = true)
    Button(onClick = onConnect) { Text("Connect") }
    if (errorText.isNotEmpty()) {
      Text(errorText, color = MaterialTheme.colorScheme.error)
    }
    Text(
      "Use the endpoint shown in Assistant > Remote Monitor. Same Wi-Fi uses that IPv4 and port " +
        "${MonitorLimits.ListenPort}. An emulator uses 127.0.0.1 after " +
        "adb reverse tcp:${MonitorLimits.ListenPort} tcp:${MonitorLimits.ListenPort}, with the IDE bound to " +
        "127.0.0.1 or all interfaces. No fingerprint and no pairing code.",
      style = MaterialTheme.typography.bodySmall
    )
  }
}

@Composable
private fun OptionRow(label: String, checked: Boolean, onChecked: (Boolean) -> Unit) {
  Row(
    modifier = Modifier.fillMaxWidth().clickable { onChecked(!checked) },
    verticalAlignment = Alignment.CenterVertically
  ) {
    Checkbox(checked = checked, onCheckedChange = onChecked)
    Text(label)
  }
}
