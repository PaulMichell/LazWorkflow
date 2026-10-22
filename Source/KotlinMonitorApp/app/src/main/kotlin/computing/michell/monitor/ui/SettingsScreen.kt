package computing.michell.monitor.ui

/* Settings form. Connection first, then view switches (c) 2026 Michell Computing. */

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import computing.michell.monitor.R
import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.connection.ReconnectingBanner
import computing.michell.monitor.protocol.MonitorLimits

private const val EndpointHint = "Use the address and port shown in Assistant > Remote Monitor."

@Composable
fun SettingsScreen(
  address: String,
  port: String,
  errorText: String,
  phase: LinkPhase,
  disconnected: Boolean,
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
  val shownError = settingsErrorText(errorText)
  var helpOpen by remember { mutableStateOf(false) }
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
      Button(onClick = onConnect, modifier = Modifier.fillMaxWidth()) { Text("Connect") }
      if (shownError.isNotEmpty()) {
        Text(shownError, color = MaterialTheme.colorScheme.error)
      }
      HorizontalDivider()
      Text("View", style = MaterialTheme.typography.titleMedium)
      SwitchRow("Show thinking", showThinking, onThinking)
      SwitchRow("Show tool calls", showTools, onTools)
      HorizontalDivider()
      HelpRow(helpOpen) { helpOpen = !helpOpen }
      if (helpOpen) {
        Text(connectionHelpText(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
      }
    }
  }
}

/** Link words for the settings status line. A connecting attempt is not a failure. */
fun settingsLinkCaption(phase: LinkPhase, disconnected: Boolean): String {
  if (phase == LinkPhase.Connecting) return "Connecting"
  if (phase == LinkPhase.Live && !disconnected) return "Connected"
  return "Not connected"
}

/** Progress banners belong on the status line, not in the error slot under Connect. */
fun settingsErrorText(banner: String): String {
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

@Composable
private fun HelpRow(open: Boolean, onToggle: () -> Unit) {
  Row(
    modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp).clickable(onClick = onToggle),
    verticalAlignment = Alignment.CenterVertically
  ) {
    Text("Connection help", modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
    Icon(
      painterResource(R.drawable.ic_expand),
      contentDescription = if (open) "Collapse connection help" else "Expand connection help",
      modifier = Modifier.rotate(if (open) 180f else 0f)
    )
  }
}

private fun connectionHelpText(): String {
  val port = MonitorLimits.ListenPort
  return "Same Wi-Fi uses that IPv4 and port $port. An emulator uses 127.0.0.1 after " +
    "adb reverse tcp:$port tcp:$port, with the IDE bound to 127.0.0.1 or all interfaces. " +
    "No fingerprint and no pairing code."
}
