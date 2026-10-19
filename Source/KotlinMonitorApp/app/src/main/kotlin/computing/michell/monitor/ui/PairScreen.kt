package computing.michell.monitor.ui

/* Pair screen. Pin, protocol, and pair-code failures stay here (c) 2026 Michell Computing. */

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import computing.michell.monitor.protocol.MonitorLimits

@Composable
fun PairScreen(
  address: String,
  port: String,
  fingerprint: String,
  code: String,
  errorText: String,
  onAddress: (String) -> Unit,
  onPort: (String) -> Unit,
  onFingerprint: (String) -> Unit,
  onCode: (String) -> Unit,
  onConnect: () -> Unit
) {
  Column(
    modifier = Modifier.fillMaxSize().padding(16.dp),
    verticalArrangement = Arrangement.spacedBy(12.dp)
  ) {
    Text("Pair", style = MaterialTheme.typography.headlineSmall)
    OutlinedTextField(address, onAddress, modifier = Modifier.fillMaxWidth(), label = { Text("Host address") }, singleLine = true)
    OutlinedTextField(port, onPort, modifier = Modifier.fillMaxWidth(), label = { Text("Port") }, singleLine = true)
    OutlinedTextField(fingerprint, onFingerprint, modifier = Modifier.fillMaxWidth(), label = { Text("Fingerprint") })
    OutlinedTextField(code, onCode, modifier = Modifier.fillMaxWidth(), label = { Text("One-time code") }, singleLine = true)
    Button(onClick = onConnect) { Text("Connect") }
    if (errorText.isNotEmpty()) {
      Text(errorText, color = MaterialTheme.colorScheme.error)
    }
    Text(
      "Phone on the same Wi-Fi uses the host private IPv4 and port ${MonitorLimits.ListenPort}. " +
        "An emulator uses 127.0.0.1 after adb reverse tcp:${MonitorLimits.ListenPort} tcp:${MonitorLimits.ListenPort}, " +
        "with the IDE bound to 127.0.0.1.",
      style = MaterialTheme.typography.bodySmall
    )
  }
}
