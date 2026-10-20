package computing.michell.monitor.ui

/* Conversation transcript. The extent is virtual; recent bodies fill first.
   Styles follow the desktop bubbles. The bar is an absolute position in that extent.
   (c) 2026 Michell Computing. */

import android.Manifest
import android.app.Activity
import android.graphics.Bitmap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedIconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import computing.michell.monitor.R
import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.dictation.DictationListeningMessage
import computing.michell.monitor.dictation.DictationPhase
import computing.michell.monitor.dictation.DictationState
import computing.michell.monitor.dictation.DictationUnavailableMessage
import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireImage
import computing.michell.monitor.protocol.WireTurn
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

private val UserFill = Color(0xFFE5F8EF)
private val UserEdge = Color(0xFFC5E4D5)
private val AnswerFill = Color(0xFFF7F7F7)
private val AnswerEdge = Color(0xFFE4E4E4)
private val ToolFill = Color(0xFFF4F4F4)
private val FailedTitle = Color(0xFF800000)
private val QuietText = Color(0xFF666666)
private val Bubble = RoundedCornerShape(12.dp)

val ModeChoices = listOf(
  "chat" to "Chat",
  "inspect" to "Inspect",
  "document" to "Document",
  "plan" to "Plan",
  "build" to "Build"
)

fun modeCaption(mode: String): String {
  val known = ModeChoices.firstOrNull { it.first == mode }?.second
  if (known != null) return known
  return mode.replaceFirstChar { if (it.isLowerCase()) it.uppercase() else it.toString() }
}

@Composable
fun ConversationScreen(
  ui: MonitorUi,
  phase: LinkPhase,
  bitmaps: Map<String, Bitmap>,
  onPrompt: (String, Int, Int) -> Unit,
  onSend: () -> Unit,
  onStop: () -> Unit,
  onNew: () -> Unit,
  onMode: (String) -> Unit,
  onNeed: (Int) -> Unit,
  onSettings: () -> Unit,
  dictation: DictationState,
  onDictateOn: (Int, Int, Boolean) -> Unit,
  onDictateOff: () -> Unit,
  permissionRequest: Boolean,
  onPermissionResult: (Boolean) -> Unit,
  onPermissionConsumed: () -> Unit
) {
  val activity = LocalContext.current as? Activity
  val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
    onPermissionResult(granted)
  }
  LaunchedEffect(permissionRequest) {
    if (!permissionRequest) return@LaunchedEffect
    permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
    onPermissionConsumed()
  }
  val promptValue = promptFieldValue(ui.draft, dictation.selectionStart, dictation.selectionEnd)
  Column(modifier = Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
      Text("Mode")
      ModeCombo(ui.view.mode, ui.view.canChangeMode && !ui.disconnected, onMode, Modifier.weight(1f))
    }
    if (ui.banner.isNotEmpty()) Text(ui.banner, color = MaterialTheme.colorScheme.error)
    ConversationPane(ui, bitmaps, onNeed, Modifier.weight(1f).fillMaxWidth())
    PromptField(promptValue, onPrompt)
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
      DictateToggle(dictation, promptValue.selection.start, promptValue.selection.end, { start, end ->
        val showRationale = activity?.shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO) == true
        onDictateOn(start, end, showRationale)
      }, onDictateOff)
      Button(
        onClick = onSend,
        enabled = actionEnabled(ui.view) && !ui.disconnected && !dictation.sendMustWait
      ) { Text(actionCaption(ui.view)) }
      Button(onClick = onStop, enabled = ui.view.canStop && !ui.disconnected) { Text("Stop") }
      Button(onClick = onNew, enabled = ui.view.canSend && !ui.disconnected) { Text("New") }
      OutlinedButton(onClick = onSettings) { Text("Settings") }
    }
    ActivityStatus(ui, phase, dictation.listening, dictation.statusMessage)
  }
}

fun promptFieldValue(draft: String, selectionStart: Int, selectionEnd: Int): TextFieldValue {
  val length = draft.length
  return TextFieldValue(draft, TextRange(selectionStart.coerceIn(0, length), selectionEnd.coerceIn(0, length)))
}

fun promptActivityRight(activity: String, listening: Boolean, statusMessage: String): String {
  if (listening) return DictationListeningMessage
  if (statusMessage.isEmpty()) return activity
  if (statusMessage == DictationUnavailableMessage && activity != "Ready") return activity
  return statusMessage
}

@Composable
private fun ConversationPane(
  ui: MonitorUi,
  bitmaps: Map<String, Bitmap>,
  onNeed: (Int) -> Unit,
  modifier: Modifier
) {
  val slots = remember(ui.turns, ui.live, ui.view.sending) { virtualSlots(ui.turns, ui.live, ui.view.sending) }
  val scrollState = rememberScrollState()
  val scope = rememberCoroutineScope()
  var followHead by remember { mutableStateOf(true) }
  var dragging by remember { mutableStateOf(false) }
  var settling by remember { mutableStateOf(false) }
  var dragFraction by remember { mutableFloatStateOf(1f) }
  var seekPx by remember { mutableIntStateOf(-1) }
  val measured = remember { androidx.compose.runtime.mutableStateMapOf<String, Int>() }
  val need = rememberUpdatedState(onNeed)
  LaunchedEffect(Unit) {
    snapshotFlow { seekPx }
      .collect { y ->
        if (y < 0) return@collect
        settling = true
        scrollState.scrollTo(y.coerceIn(0, scrollState.maxValue))
        settling = false
      }
  }
  LaunchedEffect(ui.pendingEpoch) {
    if (ui.pendingEpoch > 0) followHead = true
  }
  LaunchedEffect(Unit) {
    snapshotFlow { Triple(scrollState.maxValue, followHead, dragging) }
      .collect { (max, stick, drag) ->
        if (!stick || drag) return@collect
        var guard = 0
        while (followHead && !dragging && scrollState.value < scrollState.maxValue && guard < 8) {
          settling = true
          scrollState.scrollTo(scrollState.maxValue)
          settling = false
          guard += 1
        }
        if (followHead && max > 0 && scrollState.value < scrollState.maxValue) {
          settling = true
          scrollState.scrollTo(scrollState.maxValue)
          settling = false
        }
      }
  }
  LaunchedEffect(scrollState) {
    var previousValue = scrollState.value
    var previousMax = scrollState.maxValue
    snapshotFlow { Triple(scrollState.isScrollInProgress, scrollState.value, scrollState.maxValue) }
      .collect { (_, value, max) ->
        if (!settling) followHead = stickToHead(followHead, previousValue, value, previousMax, max, dragging)
        previousValue = value
        previousMax = max
      }
  }
  LaunchedEffect(scrollState, slots) {
    snapshotFlow { Triple(scrollState.value, scrollState.viewportSize, measured.toMap()) }
      .distinctUntilChanged()
      .collect { (value, viewport, heights) ->
        var top = 0
        val view = viewport.coerceAtLeast(1)
        for (slot in slots) {
          val height = heights[slotKey(slot)] ?: 1
          if (top < value + view && top + height > value && slot.turnIndex >= 0) need.value(slot.turnIndex)
          top += height
        }
      }
  }
  val fraction = if (dragging) dragFraction else scrollFraction(scrollState.value, scrollState.maxValue)
  val content = scrollState.maxValue + scrollState.viewportSize
  val thumbFraction = if (content <= 0) 1f else scrollState.viewportSize.toFloat() / content.toFloat()
  val labelIndex = slotIndexForFraction(slots, measured, fraction)
  Row(modifier, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
    Column(
      Modifier.weight(1f).fillMaxHeight().verticalScroll(scrollState),
      verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
      slots.forEach { slot ->
        Box(Modifier.onSizeChanged { size ->
          val key = slotKey(slot)
          val previous = measured[key]
          measured[key] = size.height
          if (previous == null || followHead || dragging) return@onSizeChanged
          val delta = size.height - previous
          if (delta == 0) return@onSizeChanged
          val top = prefixHeight(slots, measured, key)
          if (top < scrollState.value) {
            scope.launch { scrollState.scrollTo((scrollState.value + delta).coerceAtLeast(0)) }
          }
        }) {
          SlotBody(slot, bodyFor(ui, slot), ui.showThinking, ui.showTools, bitmaps, ui.imageReasons)
        }
      }
      if (ui.pendingPrompt.isNotEmpty() && !promptShown(ui, ui.pendingPrompt)) {
        RoleBlock(
          WireBlock(ui.pendingKind.ifEmpty { "user" }, "pending", "", "", "", ui.pendingPrompt, false, true, 0, emptyList()),
          bitmaps,
          ui.imageReasons
        )
      }
    }
    ExtentBar(
      fraction,
      thumbFraction,
      dragging,
      slots.getOrNull(labelIndex)?.label ?: "",
      { next, active ->
        val fractionNow = next.coerceIn(0f, 1f)
        val max = scrollState.maxValue
        val y = if (!active && fractionNow >= 0.995f) max else scrollOffset(max, fractionNow)
        dragging = active
        dragFraction = fractionNow
        followHead = atHead(y, max)
        seekPx = y
      },
      Modifier.fillMaxHeight()
    )
  }
}

private fun slotKey(slot: VirtualSlot): String = "${slot.turnIndex}:${slot.live}"

private fun prefixHeight(slots: List<VirtualSlot>, measured: Map<String, Int>, key: String): Int {
  var top = 0
  for (slot in slots) {
    val id = slotKey(slot)
    if (id == key) return top
    top += measured[id] ?: 0
  }
  return top
}

private fun slotIndexForFraction(slots: List<VirtualSlot>, measured: Map<String, Int>, fraction: Float): Int {
  if (slots.isEmpty()) return 0
  val heights = slots.map { slot -> (measured[slotKey(slot)] ?: 1).coerceAtLeast(1) }
  return spotAt(heights, fraction).index
}

private fun bodyFor(ui: MonitorUi, slot: VirtualSlot): WireTurn? {
  if (slot.live) return ui.live ?: ui.history[slot.turnIndex]
  return ui.history[slot.turnIndex]
}

@Composable
private fun SlotBody(
  slot: VirtualSlot,
  turn: WireTurn?,
  showThinking: Boolean,
  showTools: Boolean,
  bitmaps: Map<String, Bitmap>,
  reasons: Map<String, String>
) {
  val blocks = shownBlocks(turn, showThinking, showTools)
  if (blocks.isEmpty()) {
    Text(slot.label, color = QuietText, maxLines = 2, overflow = TextOverflow.Ellipsis)
    return
  }
  Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
    blocks.forEach { block -> RoleBlock(block, bitmaps, reasons) }
  }
}

@Composable
private fun ExtentBar(
  fraction: Float,
  thumbFraction: Float,
  dragging: Boolean,
  label: String,
  onJump: (Float, Boolean) -> Unit,
  modifier: Modifier
) {
  val trackColor = MaterialTheme.colorScheme.surfaceVariant
  val thumbColor = MaterialTheme.colorScheme.primary
  val jump = rememberUpdatedState(onJump)
  val shownThumb = thumbFraction.coerceIn(0.08f, 1f)
  BoxWithConstraints(modifier.width(28.dp)) {
    val travel = 1f - shownThumb
    val thumbTop = maxHeight * (fraction.coerceIn(0f, 1f) * travel)
    Canvas(
      Modifier
        .fillMaxSize()
        .pointerInput(Unit) {
          detectTapGestures { offset ->
            val next = if (size.height <= 0) 0f else (offset.y / size.height.toFloat()).coerceIn(0f, 1f)
            jump.value(next, false)
          }
        }
        .pointerInput(Unit) {
          var held = 0f
          detectDragGestures(
            onDragStart = { offset ->
              held = if (size.height <= 0) 0f else (offset.y / size.height.toFloat()).coerceIn(0f, 1f)
              jump.value(held, true)
            },
            onDragEnd = { jump.value(held, false) },
            onDragCancel = { jump.value(held, false) },
            onDrag = { change, _ ->
              held = if (size.height <= 0) 0f else (change.position.y / size.height.toFloat()).coerceIn(0f, 1f)
              jump.value(held, true)
            }
          )
        }
    ) {
      drawRoundRect(
        color = trackColor,
        cornerRadius = CornerRadius(8f, 8f),
        size = Size(size.width, size.height)
      )
      val thumbHeight = size.height * shownThumb
      drawRoundRect(
        color = thumbColor,
        topLeft = Offset(2f, thumbTop.toPx()),
        size = Size(size.width - 4f, thumbHeight),
        cornerRadius = CornerRadius(8f, 8f)
      )
    }
    if (dragging) {
      Text(
        label,
        modifier = Modifier
          .align(Alignment.TopEnd)
          .wrapContentWidth(unbounded = true, align = Alignment.End)
          .offset(x = (-36).dp, y = thumbTop)
          .background(MaterialTheme.colorScheme.surface, MaterialTheme.shapes.small)
          .padding(horizontal = 8.dp, vertical = 4.dp)
          .width(160.dp),
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
        style = MaterialTheme.typography.bodySmall
      )
    }
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ModeCombo(mode: String, enabled: Boolean, onMode: (String) -> Unit, modifier: Modifier = Modifier) {
  var open by remember { mutableStateOf(false) }
  ExposedDropdownMenuBox(expanded = open && enabled, onExpandedChange = { if (enabled) open = it }, modifier = modifier) {
    OutlinedTextField(
      value = modeCaption(mode),
      onValueChange = {},
      readOnly = true,
      enabled = enabled,
      singleLine = true,
      trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = open && enabled) },
      modifier = Modifier.menuAnchor(MenuAnchorType.PrimaryNotEditable, enabled).fillMaxWidth()
    )
    ExposedDropdownMenu(expanded = open && enabled, onDismissRequest = { open = false }) {
      ModeChoices.forEach { choice ->
        DropdownMenuItem(
          text = { Text(choice.second) },
          onClick = {
            open = false
            if (choice.first != mode) onMode(choice.first)
          }
        )
      }
    }
  }
}

@Composable
private fun ActivityStatus(ui: MonitorUi, phase: LinkPhase, listening: Boolean, statusMessage: String) {
  var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
  val blocks = displayBlocks(ui.live)
  val pending = ui.pendingPrompt.isNotEmpty() && !promptShown(ui, ui.pendingPrompt)
  val running = turnStillRunning(ui.view, pending, blocks, ui.live)
  LaunchedEffect(running, ui.activityStartedMs) {
    if (!running) return@LaunchedEffect
    while (true) {
      now = System.currentTimeMillis()
      delay(1000)
    }
  }
  val runtime = runtimeCaption(ui.view)
  val activity = activityCaption(ui.view, pending, ui.pendingKind, ui.activityStartedMs, now, blocks, ui.live)
  val right = promptActivityRight(activity, listening, statusMessage)
  val statusStyle = MaterialTheme.typography.bodySmall
  Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
    Text(connectionLabel(ui, phase), color = QuietText, maxLines = 1, style = statusStyle)
    if (runtime.isNotEmpty()) {
      Text("  $runtime", color = QuietText, maxLines = 1, overflow = TextOverflow.Ellipsis, style = statusStyle, modifier = Modifier.weight(1f))
    } else {
      Spacer(Modifier.weight(1f))
    }
    Text(
      right,
      color = QuietText,
      maxLines = 3,
      overflow = TextOverflow.Ellipsis,
      textAlign = TextAlign.End,
      style = statusStyle,
      modifier = Modifier.widthIn(max = 180.dp)
    )
  }
}

@Composable
private fun PromptField(value: TextFieldValue, onPrompt: (String, Int, Int) -> Unit) {
  OutlinedTextField(
    value = value,
    onValueChange = { next -> onPrompt(next.text, next.selection.start, next.selection.end) },
    modifier = Modifier.fillMaxWidth(),
    label = { Text("Prompt") }
  )
}

@Composable
private fun DictateToggle(
  dictation: DictationState,
  selectionStart: Int,
  selectionEnd: Int,
  onStart: (Int, Int) -> Unit,
  onStop: () -> Unit
) {
  val listening = dictation.listening
  val available = dictation.available && dictation.statusMessage != DictationUnavailableMessage
  val description = when {
    listening -> "Stop dictation"
    !available -> DictationUnavailableMessage
    else -> "Dictate prompt"
  }
  val tint = when {
    !available -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
    listening -> MaterialTheme.colorScheme.onPrimary
    else -> MaterialTheme.colorScheme.primary
  }
  if (listening) {
    FilledIconButton(
      onClick = onStop,
      colors = IconButtonDefaults.filledIconButtonColors(
        containerColor = MaterialTheme.colorScheme.primary,
        contentColor = MaterialTheme.colorScheme.onPrimary
      )
    ) {
      Icon(painterResource(R.drawable.ic_dictate), contentDescription = description, tint = tint)
    }
  } else {
    OutlinedIconButton(
      onClick = {
        if (dictation.phase == DictationPhase.Idle) onStart(selectionStart, selectionEnd)
      },
      enabled = available,
      colors = IconButtonDefaults.outlinedIconButtonColors(contentColor = MaterialTheme.colorScheme.primary)
    ) {
      Icon(painterResource(R.drawable.ic_dictate), contentDescription = description, tint = tint)
    }
  }
}

@Composable
private fun RoleBlock(block: WireBlock, bitmaps: Map<String, Bitmap>, reasons: Map<String, String>) {
  when (block.kind) {
    "user" -> BubbleBlock(block, UserFill, UserEdge, Alignment.End, 0.85f, bitmaps, reasons)
    "answer" -> BubbleBlock(block, AnswerFill, AnswerEdge, Alignment.Start, 0.95f, bitmaps, reasons)
    "thinking" -> FoldBlock(block.title.ifEmpty { "Thinking" }, block.body, false, false)
    "tool", "subagent" -> FoldBlock(toolTitle(block), block.body, !block.ok && !block.running, true)
    "steer" -> Text(block.body.ifEmpty { block.title }, modifier = Modifier.padding(horizontal = 4.dp))
    "note", "worked" -> Text(
      block.body.ifEmpty { block.title },
      color = QuietText,
      fontStyle = FontStyle.Italic,
      modifier = Modifier.padding(horizontal = 4.dp)
    )
    else -> Text(block.body.ifEmpty { block.title })
  }
}

private fun toolTitle(block: WireBlock): String {
  val name = block.toolName.ifEmpty { block.title.ifEmpty { block.kind } }
  val state = if (block.running) "running" else if (block.ok) "ok" else "failed"
  return "$name $state"
}

@Composable
private fun BubbleBlock(
  block: WireBlock,
  fill: Color,
  edge: Color,
  align: Alignment.Horizontal,
  widthFraction: Float,
  bitmaps: Map<String, Bitmap>,
  reasons: Map<String, String>
) {
  Column(modifier = Modifier.fillMaxWidth(), horizontalAlignment = align) {
    Column(
      modifier = Modifier
        .fillMaxWidth(widthFraction)
        .clip(Bubble)
        .background(fill)
        .border(1.dp, edge, Bubble)
        .padding(12.dp),
      verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
      if (block.title.isNotEmpty()) Text(block.title, fontWeight = FontWeight.Bold)
      if (block.body.isNotEmpty()) Text(block.body)
      block.images.forEach { image -> ImageTile(image, bitmaps, reasons) }
    }
  }
}

@Composable
private fun FoldBlock(title: String, body: String, failed: Boolean, tool: Boolean) {
  var open by remember(title, body) { mutableStateOf(false) }
  Column(
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(6.dp))
      .background(if (tool) ToolFill else Color.Transparent)
      .clickable { open = !open }
      .padding(8.dp)
  ) {
    Text(
      (if (open) "▾ " else "▸ ") + title,
      color = if (failed) FailedTitle else QuietText,
      fontWeight = FontWeight.Bold
    )
    if (open && body.isNotEmpty()) Text(body, color = QuietText, modifier = Modifier.padding(top = 4.dp))
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
