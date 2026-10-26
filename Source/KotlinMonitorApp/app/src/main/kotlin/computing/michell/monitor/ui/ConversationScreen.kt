package computing.michell.monitor.ui

/* Conversation transcript. The extent is virtual; recent bodies fill first.
   Styles follow the desktop bubbles. Finger scrolling has no thumb.
   (c) 2026 Michell Computing. */

import android.Manifest
import android.app.Activity
import android.graphics.Bitmap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedIconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.getValue
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
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
  onNeed: (Int) -> Unit,
  onVisibleTurns: (Set<Int>) -> Unit,
  onViewWidth: (Int) -> Unit,
  dictation: DictationState,
  onDictateOn: (Int, Int, Boolean) -> Unit,
  onDictateOff: () -> Unit,
  permissionRequest: Boolean,
  onPermissionResult: (Boolean) -> Unit,
  onPermissionConsumed: () -> Unit,
  onCached: () -> Unit = {}
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
    if (cachedButtonVisible(ui.disconnected, phase)) {
      Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Start) {
        TextButton(onClick = onCached) { Text("Cached") }
      }
    }
    ConversationPane(ui, phase, bitmaps, onNeed, onVisibleTurns, onViewWidth, Modifier.weight(1f).fillMaxWidth())
    key(ui.pendingEpoch) {
      PromptField(promptValue, onPrompt)
    }
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
    }
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
  phase: LinkPhase,
  bitmaps: Map<String, Bitmap>,
  onNeed: (Int) -> Unit,
  onVisibleTurns: (Set<Int>) -> Unit,
  onViewWidth: (Int) -> Unit,
  modifier: Modifier
) {
  val showLive = ui.view.sending || ui.view.busy || ui.view.planRunning || ui.planRunning
  val slots = remember(ui.turns, ui.live, showLive) { virtualSlots(ui.turns, ui.live, showLive) }
  val scrollState = rememberScrollState()
  val scope = rememberCoroutineScope()
  var followHead by remember { mutableStateOf(true) }
  var settling by remember { mutableStateOf(false) }
  val measured = remember { androidx.compose.runtime.mutableStateMapOf<String, Int>() }
  val need = rememberUpdatedState(onNeed)
  LaunchedEffect(ui.pendingEpoch) {
    if (ui.pendingEpoch > 0) followHead = true
  }
  LaunchedEffect(Unit) {
    snapshotFlow { scrollState.maxValue to followHead }
      .collect { (max, stick) ->
        if (!stick) return@collect
        var guard = 0
        while (followHead && scrollState.value < scrollState.maxValue && guard < 8) {
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
        if (!settling) followHead = stickToHead(followHead, previousValue, value, previousMax, max, false)
        previousValue = value
        previousMax = max
      }
  }
  val reportVisible = rememberUpdatedState(onVisibleTurns)
  LaunchedEffect(slots) {
    reportVisible.value(prefetchRecent(slots))
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
  Column(
    modifier.fillMaxHeight().verticalScroll(scrollState).onSizeChanged { size ->
      if (size.width > 0) onViewWidth(size.width)
    },
    verticalArrangement = Arrangement.spacedBy(8.dp)
  ) {
      slots.forEach { slot ->
        Box(Modifier.onSizeChanged { size ->
          val key = slotKey(slot)
          val previous = measured[key]
          measured[key] = size.height
          if (previous == null || followHead) return@onSizeChanged
          val delta = size.height - previous
          if (delta == 0) return@onSizeChanged
          val top = prefixHeight(slots, measured, key)
          if (top < scrollState.value) {
            scope.launch { scrollState.scrollTo((scrollState.value + delta).coerceAtLeast(0)) }
          }
        }) {
          SlotBody(
            slot,
            bodyFor(ui, slot),
            ui.hostGeneration,
            ui.conversationGeneration,
            ui.showThinking,
            ui.showTools,
            bitmaps,
            ui.imageReasons,
            !ui.disconnected
          )
        }
      }
      if (ui.pendingPrompt.isNotEmpty() && !promptShown(ui, ui.pendingPrompt) && !hostHasLaterUserBlock(ui)) {
        val pending = WireBlock(
          ui.pendingKind.ifEmpty { "user" }, "pending", "", "", "", ui.pendingPrompt, false, true, 0, emptyList()
        )
        RoleBlock(
          pending,
          bitmaps,
          ui.imageReasons,
          ui.hostGeneration,
          foldBlockKey(ui.conversationGeneration, "", pending.blockId, 0),
          !ui.disconnected
        )
      }
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

private fun bodyFor(ui: MonitorUi, slot: VirtualSlot): WireTurn? {
  val stored = ui.history[slot.turnIndex]
  val live = if (slot.live) ui.live else null
  if (live != null && shownBlocks(live, ui.showThinking, ui.showTools).isNotEmpty()) return live
  if (stored != null) return stored
  return live
}

@Composable
private fun SlotBody(
  slot: VirtualSlot,
  turn: WireTurn?,
  hostGeneration: Int,
  conversationGeneration: Int,
  showThinking: Boolean,
  showTools: Boolean,
  bitmaps: Map<String, Bitmap>,
  reasons: Map<String, String>,
  fetchImages: Boolean
) {
  val assembled = displayBlocks(turn)
  val shown = assembled.withIndex().filter { (_, block) -> blockShown(block, showThinking, showTools) }
  if (shown.isEmpty()) {
    Text(slot.label, color = QuietText, maxLines = 2, overflow = TextOverflow.Ellipsis)
    return
  }
  val turnId = turn?.id.orEmpty()
  Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
    shown.forEach { (index, block) ->
      val foldKey = foldBlockKey(conversationGeneration, turnId, block.blockId, index)
      key(foldKey) {
        RoleBlock(block, bitmaps, reasons, hostGeneration, foldKey, fetchImages)
      }
    }
  }
}

/** Expansion identity. Title and body are not part of it. An empty block id uses the assembled index. */
fun foldBlockKey(conversationGeneration: Int, turnId: String, blockId: String, blockIndex: Int): String {
  val identity = if (blockId.isNotEmpty()) "id\u0000$blockId" else "index\u0000$blockIndex"
  return "$conversationGeneration\u0000$turnId\u0000$identity"
}

@Composable
fun ActivityStatus(
  ui: MonitorUi,
  phase: LinkPhase,
  listening: Boolean,
  statusMessage: String,
  modifier: Modifier = Modifier
) {
  var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
  val blocks = displayBlocks(ui.live)
  val pending = ui.pendingPrompt.isNotEmpty() && !promptShown(ui, ui.pendingPrompt)
  val linkLive = ideLinkLive(ui.disconnected, phase)
  val running = turnStillRunning(ui.view, pending, blocks, ui.live)
  LaunchedEffect(running, ui.activityStartedMs, linkLive) {
    if (!running || !linkLive) return@LaunchedEffect
    while (true) {
      now = System.currentTimeMillis()
      delay(1000)
    }
  }
  val runtime = runtimeCaption(ui.view)
  val activity = activityCaption(
    ui.view, pending, ui.pendingKind, ui.activityStartedMs, now, blocks, ui.live, linkLive
  )
  // displayInterrupted must not replace this slot, and must not start a reconnect clock.
  val right = if (linkLive) promptActivityRight(activity, listening, statusMessage) else activity
  val statusStyle = MaterialTheme.typography.bodySmall
  // Equal side columns keep the model on the screen centre. Connection stays left; progress stays right.
  Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
    Text(
      statusCaption(ui, phase),
      color = QuietText,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
      style = statusStyle,
      modifier = Modifier.weight(1f)
    )
    Text(
      runtime,
      color = QuietText,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
      textAlign = TextAlign.Center,
      style = statusStyle,
      modifier = Modifier.weight(1f)
    )
    Text(
      right,
      color = QuietText,
      maxLines = 2,
      overflow = TextOverflow.Ellipsis,
      textAlign = TextAlign.End,
      style = statusStyle,
      modifier = Modifier.weight(1f)
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
private fun RoleBlock(
  block: WireBlock,
  bitmaps: Map<String, Bitmap>,
  reasons: Map<String, String>,
  hostGeneration: Int,
  foldKey: String,
  fetchImages: Boolean
) {
  when (displayKind(block)) {
    "user" -> BubbleBlock(block, hostGeneration, UserFill, UserEdge, Alignment.End, 0.85f, bitmaps, reasons, fetchImages)
    "answer" -> BubbleBlock(block, hostGeneration, AnswerFill, AnswerEdge, Alignment.Start, 0.95f, bitmaps, reasons, fetchImages)
    "thinking" -> ThinkingCard(foldKey, block)
    "tool", "subagent" -> ToolCard(foldKey, block, bitmaps, reasons, hostGeneration, fetchImages)
    "steer" -> Text(block.body.ifEmpty { block.title }, modifier = Modifier.padding(horizontal = 4.dp))
    "note" -> CaptionBlock(block, hostGeneration, bitmaps, reasons, Color.Unspecified, false, fetchImages)
    "worked" -> CaptionBlock(block, hostGeneration, bitmaps, reasons, QuietText, true, fetchImages)
    else -> {
      val caption = block.body.ifEmpty { block.title }
      if (rendersMarkdown(displayKind(block))) MarkdownText(caption) else Text(caption)
    }
  }
}

@Composable
private fun CaptionBlock(
  block: WireBlock,
  hostGeneration: Int,
  bitmaps: Map<String, Bitmap>,
  reasons: Map<String, String>,
  color: Color,
  italic: Boolean,
  fetchImages: Boolean
) {
  Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
    val caption = block.body.ifEmpty { block.title }
    if (caption.isNotEmpty()) MarkdownText(caption, color = color, italic = italic)
    block.images.forEach { image -> ImageTile(image, hostGeneration, bitmaps, reasons, fetchImages) }
  }
}

@Composable
private fun BubbleBlock(
  block: WireBlock,
  hostGeneration: Int,
  fill: Color,
  edge: Color,
  align: Alignment.Horizontal,
  widthFraction: Float,
  bitmaps: Map<String, Bitmap>,
  reasons: Map<String, String>,
  fetchImages: Boolean
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
      if (block.body.isNotEmpty()) MarkdownText(block.body)
      block.images.forEach { image -> ImageTile(image, hostGeneration, bitmaps, reasons, fetchImages) }
    }
  }
}

@Composable
private fun ThinkingCard(foldKey: String, block: WireBlock) {
  var open by remember(foldKey) { mutableStateOf(true) }
  val body = thinkingDisplayBody(block.body)
  Column(Modifier.fillMaxWidth().clickable { open = !open }.padding(horizontal = 4.dp)) {
    Text(
      (if (open) "▾ " else "▸ ") + thinkingCardTitle(block.title, block.running, block.durationMs),
      style = thinkingHeaderStyle()
    )
    if (open && body.isNotEmpty()) MarkdownText(body)
    val footer = thoughtFooter(block.running, block.durationMs)
    if (open && footer.isNotEmpty()) {
      Text(
        footer,
        color = QuietText,
        fontStyle = FontStyle.Italic,
        style = tightTranscriptStyle(),
        modifier = Modifier.padding(top = 2.dp)
      )
    }
  }
}

@Composable
private fun ToolCard(
  foldKey: String,
  block: WireBlock,
  bitmaps: Map<String, Bitmap>,
  reasons: Map<String, String>,
  hostGeneration: Int,
  fetchImages: Boolean
) {
  var open by remember(foldKey) { mutableStateOf(false) }
  Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
    Text(
      (if (open) "▾ " else "▸ ") + toolCardCaption(block),
      color = if (block.ok) Color.Unspecified else FailedTitle,
      fontWeight = FontWeight.Bold,
      modifier = Modifier
        .fillMaxWidth()
        .clip(RoundedCornerShape(4.dp))
        .background(ToolFill)
        .clickable { open = !open }
        .padding(horizontal = 8.dp, vertical = 6.dp)
    )
    block.images.forEach { image -> ImageTile(image, hostGeneration, bitmaps, reasons, fetchImages) }
    if (open && block.body.isNotEmpty()) {
      val bodyModifier = Modifier.padding(horizontal = 8.dp)
      if (displayKind(block) == "subagent") MarkdownText(block.body, modifier = bodyModifier)
      else Text(block.body, modifier = bodyModifier)
    }
  }
}

@Composable
private fun ImageTile(
  image: WireImage,
  hostGeneration: Int,
  bitmaps: Map<String, Bitmap>,
  reasons: Map<String, String>,
  fetchImages: Boolean
) {
  val bitmap = findCachedBitmap(bitmaps, hostGeneration, image.id)
  val label = imageTileLabel(bitmap != null, reasons[image.id], image.missing, fetchImages)
  if (bitmap != null) Image(bitmap.asImageBitmap(), contentDescription = image.name)
  else if (label.isNotEmpty()) Text(label)
}

fun findCachedBitmap(bitmaps: Map<String, Bitmap>, hostGeneration: Int, imageId: String): Bitmap? {
  val prefix = imageCachePrefix(hostGeneration, imageId)
  var found: Bitmap? = null
  for ((key, bitmap) in bitmaps) {
    if (key.startsWith(prefix)) found = bitmap
  }
  return found
}
