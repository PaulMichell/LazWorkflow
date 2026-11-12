package computing.michell.monitor.ui

/* Settings form. Connection first, then view switches (c) 2026 Michell Computing. */

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import computing.michell.monitor.R
import computing.michell.monitor.connection.HostClosedBanner
import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.connection.ReconnectingBanner
import computing.michell.monitor.protocol.MonitorLimits

private const val EndpointHint = "Use the address and port shown in Assistant > Remote Monitor. An emulator cannot use 10.0.0.1; use that LAN address."

@Composable
fun SettingsScreen(
  address: String,
  port: String,
  pairCode: String,
  errorText: String,
  phase: LinkPhase,
  disconnected: Boolean,
  showThinking: Boolean,
  showTools: Boolean,
  conversationCap: String,
  imageBudgetMiB: String,
  canLeave: Boolean,
  onAddress: (String) -> Unit,
  onPort: (String) -> Unit,
  onPairCode: (String) -> Unit,
  onConnect: () -> Unit,
  onThinking: (Boolean) -> Unit,
  onTools: (Boolean) -> Unit,
  onConversationCap: (String) -> Unit,
  onImageBudget: (String) -> Unit,
  onCached: () -> Unit,
  onBack: () -> Unit,
  failureReason: String = "",
  diagnosticText: String = "",
  reconnectEnabled: Boolean = false,
  onReconnect: () -> Unit = {},
  onCopyDiagnostics: () -> Unit = {}
) {
  val shownError = settingsErrorText(errorText, failureReason)
  Column(modifier = Modifier.fillMaxSize()) {
    SettingsBar(canLeave, onBack)
    Column(
      modifier = Modifier
        .weight(1f)
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 16.dp)
        .padding(top = 12.dp, bottom = 16.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
      LinkStatusLine(settingsLinkCaption(phase, disconnected), phase == LinkPhase.Live && !disconnected)
      Text("Connection", style = MaterialTheme.typography.titleMedium)
      Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
        OutlinedTextField(
          address,
          onAddress,
          modifier = Modifier.weight(1f),
          label = { Text("Host address") },
          singleLine = true
        )
        OutlinedTextField(
          port,
          onPort,
          modifier = Modifier.width(112.dp),
          label = { Text("Port") },
          placeholder = { Text(MonitorLimits.ListenPort.toString()) },
          singleLine = true,
          keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
        )
      }
      Text(EndpointHint, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
      OutlinedTextField(
        pairCode,
        onPairCode,
        modifier = Modifier.fillMaxWidth(),
        label = { Text("Pairing code") },
        supportingText = { Text("In Assistant > Remote Monitor, enable the listener and select Generate pairing code. Enter that code here within two minutes. Saved connections do not need a new code.") },
        singleLine = true
      )
      Button(onClick = onConnect, modifier = Modifier.fillMaxWidth()) { Text("Connect") }
      if (reconnectEnabled) {
        Button(onClick = onReconnect, modifier = Modifier.fillMaxWidth()) { Text("Reconnect") }
        Text(
          "Restarts a failed connection. Pairing and saved conversations stay.",
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant
        )
      }
      if (shownError.isNotEmpty()) {
        Text(shownError, color = MaterialTheme.colorScheme.error)
      }
      HorizontalDivider()
      Text("Diagnostics", style = MaterialTheme.typography.titleMedium)
      Text(
        "Last posture changes. Kept on this phone after a restart.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
      )
      Text(
        diagnosticText.ifEmpty { "No incident captured yet." },
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
      )
      Button(onClick = onCopyDiagnostics, modifier = Modifier.fillMaxWidth()) { Text("Copy diagnostics") }
      HorizontalDivider()
      Text("View", style = MaterialTheme.typography.titleMedium)
      SwitchRow("Show thinking", showThinking, onThinking)
      SwitchRow("Show tool calls", showTools, onTools)
      HorizontalDivider()
      Text("Storage", style = MaterialTheme.typography.titleMedium)
      Text(
        "Pinned conversations are kept. Other conversations keep the newest entries per desktop. Images over the budget are removed oldest first.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
      )
      Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        OutlinedTextField(
          conversationCap,
          onConversationCap,
          modifier = Modifier.weight(1f),
          label = { Text("Conversations") },
          placeholder = { Text("50") },
          singleLine = true,
          keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
        )
        OutlinedTextField(
          imageBudgetMiB,
          onImageBudget,
          modifier = Modifier.weight(1f),
          label = { Text("Images, MiB") },
          placeholder = { Text("128") },
          singleLine = true,
          keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
        )
      }
      Button(onClick = onCached, modifier = Modifier.fillMaxWidth()) { Text("Cached conversations") }
    }
  }
}

/** Link words for the settings status line. A connecting attempt is not a failure. */
fun settingsLinkCaption(phase: LinkPhase, disconnected: Boolean): String {
  if (phase == LinkPhase.Connecting) return "Connecting"
  if (phase == LinkPhase.Live && !disconnected) return "Connected"
  return "Not connected"
}

/**
 * Progress banners belong on the status line, not in the error slot under Connect.
 * A retry keeps the original failure in [failureReason] so the banner does not hide it.
 */
fun settingsErrorText(banner: String, failureReason: String = ""): String {
  val kept = failureReason.isNotEmpty() && failureReason != banner && failureReason != ReconnectingBanner
  if (kept && (banner == ReconnectingBanner || banner == HostClosedBanner)) return failureReason
  if (banner.isEmpty() || banner == ConnectingBanner || banner == ReconnectingBanner) return ""
  return banner
}

@Composable
private fun SettingsBar(canLeave: Boolean, onBack: () -> Unit) {
  Column {
    Row(modifier = Modifier.fillMaxWidth().height(64.dp), verticalAlignment = Alignment.CenterVertically) {
      if (canLeave) {
        IconButton(onClick = onBack) {
          Icon(painterResource(R.drawable.ic_back), contentDescription = "Back")
        }
      } else {
        Spacer(Modifier.width(16.dp))
      }
      Text("Settings", style = MaterialTheme.typography.titleLarge)
    }
    HorizontalDivider()
  }
}

@Composable
private fun LinkStatusLine(caption: String, connected: Boolean) {
  val dot = if (connected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
  Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
    Box(Modifier.size(8.dp).background(dot, CircleShape))
    Text(caption, style = MaterialTheme.typography.bodyMedium)
  }
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onChecked: (Boolean) -> Unit) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .defaultMinSize(minHeight = 56.dp)
      .toggleable(value = checked, role = Role.Switch, onValueChange = onChecked),
    verticalAlignment = Alignment.CenterVertically
  ) {
    Text(label, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
    Switch(checked = checked, onCheckedChange = null)
  }
}

