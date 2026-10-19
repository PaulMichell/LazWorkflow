package computing.michell.monitor.ui

/* Conversation transcript. The action caption is not taken from busy (c) 2026 Michell Computing. */

import android.graphics.Bitmap
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.Image
import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.protocol.ModeNames
import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireImage

@Composable
fun ConversationScreen(
  ui: MonitorUi,
  phase: LinkPhase,
  bitmaps: Map<String, Bitmap>,
  onDraft: (String) -> Unit,
  onSend: () -> Unit,
  onStop: () -> Unit,
  onMode: (String) -> Unit,
  onTurn: (Int) -> Unit
) {
  val turn = ui.history[ui.selectedTurn] ?: ui.live
  Column(modifier = Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
    Text(
      "${connectionLabel(ui, phase)}  ${ui.view.targetDisplay}  ${ui.view.model}  ${ui.view.phase}",
      style = MaterialTheme.typography.titleMedium
    )
    if (ui.banner.isNotEmpty()) Text(ui.banner, color = MaterialTheme.colorScheme.error)
    Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      ModeNames.forEach { mode ->
        val selected = mode == ui.view.mode
        if (selected) {
          Button(onClick = { onMode(mode) }, enabled = ui.view.canChangeMode) { Text(mode) }
        } else {
          OutlinedButton(onClick = { onMode(mode) }, enabled = ui.view.canChangeMode) { Text(mode) }
        }
      }
    }
    if (ui.turns.isNotEmpty()) {
      Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        ui.turns.forEach { stored ->
          OutlinedButton(onClick = { onTurn(stored.turnIndex) }) {
            Text(stored.promptPreview.ifEmpty { "Turn ${stored.turnIndex}" })
          }
        }
      }
    }
    LazyColumn(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
      items(turn?.blocks ?: emptyList()) { block ->
        BlockCard(block, bitmaps, ui.imageReasons)
      }
    }
    OutlinedTextField(
      value = ui.draft,
      onValueChange = onDraft,
      modifier = Modifier.fillMaxWidth(),
      label = { Text("Prompt") }
    )
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      Button(onClick = onSend, enabled = actionEnabled(ui.view)) { Text(actionCaption(ui.view)) }
      Button(onClick = onStop, enabled = ui.view.canStop) { Text("Stop") }
    }
  }
}

@Composable
private fun BlockCard(block: WireBlock, bitmaps: Map<String, Bitmap>, reasons: Map<String, String>) {
  Card(modifier = Modifier.fillMaxWidth()) {
    Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
      Text(blockLabel(block), style = MaterialTheme.typography.titleSmall)
      if (block.title.isNotEmpty()) Text(block.title)
      if (block.body.isNotEmpty()) Text(block.body)
      if (block.truncated) Text("Truncated")
      block.images.forEach { image -> ImageTile(image, bitmaps, reasons) }
    }
  }
}

@Composable
private fun ImageTile(image: WireImage, bitmaps: Map<String, Bitmap>, reasons: Map<String, String>) {
  val bitmap = bitmaps[image.id]
  val reason = reasons[image.id]
  when {
    bitmap != null -> Image(bitmap.asImageBitmap(), contentDescription = image.name)
    reason != null -> Text("Image unavailable: $reason")
    image.missing -> Text("Image unavailable: missing")
    else -> Text("Loading image")
  }
}

private fun blockLabel(block: WireBlock): String {
  return when (block.kind) {
    "tool" -> {
      val state = if (block.running) "running" else if (block.ok) "ok" else "failed"
      "tool ${block.toolName} $state"
    }
    "user", "thinking", "steer", "subagent", "note", "answer" -> block.kind
    else -> block.kind
  }
}
