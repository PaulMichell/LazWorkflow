package computing.michell.monitor.ui

/* App menu. Top-level headings, choices in flyouts (c) 2026 Michell Computing. */

import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import computing.michell.monitor.R
import computing.michell.monitor.protocol.ConversationChoice
import computing.michell.monitor.protocol.PlanChoice
import computing.michell.monitor.protocol.TargetChoice
import kotlin.math.roundToInt

/** One quiet sentence for a section that has no tappable row. */
const val MenuEmptySentence = "Nothing to choose."

/** Empty path is the open project, not a folder caption. */
const val CurrentProjectCaption = "Current Project"

/** Material will not draw a modal sheet narrower than this. It is the heading column. */
val MenuSheetWidth = 240.dp

/** Flyout starts at the end of the heading and chevron, relative to the heading row. */
val MenuFlyoutOffset = 168.dp

private val MenuFlyoutPreferred = 280.dp
private val MenuFlyoutMin = 160.dp
private val MenuFlyoutMargin = 8.dp

/** Leave a strip of the page so the existing scrim can still close the drawer. */
private val MenuFlyoutScrimReserve = 48.dp

private val MenuFlyoutShape = RoundedCornerShape(12.dp)

fun targetChoiceCaption(choice: TargetChoice): String {
  if (choice.path.isEmpty()) return CurrentProjectCaption
  return choice.caption
}

/** Target rows stay put while disconnected, sending, or a plan run. */
fun targetRowsEnabled(disconnected: Boolean, sending: Boolean, planRunning: Boolean): Boolean {
  return !disconnected && !sending && !planRunning
}

/** Shown under the history list when the host omitted older archives. */
const val OlderConversationsSentence = "Older conversations stay on the desktop."

/** Model rows stay put while disconnected, sending, or a plan run. */
fun modelRowsEnabled(disconnected: Boolean, sending: Boolean, planRunning: Boolean): Boolean {
  return !disconnected && !sending && !planRunning
}

/** Reasoning rows use the same gate as the model list. */
fun reasoningRowsEnabled(disconnected: Boolean, sending: Boolean, planRunning: Boolean): Boolean {
  return modelRowsEnabled(disconnected, sending, planRunning)
}

/** Permission rows use the same gate. This is the footer mode, not the approval sheet. */
fun permissionRowsEnabled(disconnected: Boolean, sending: Boolean, planRunning: Boolean): Boolean {
  return modelRowsEnabled(disconnected, sending, planRunning)
}

/**
 * A cleared list is still waiting for its frame. A note means that frame arrived with nothing to choose.
 * Plan is not in this check: an empty plan is a real desktop list, and the Plan tab already asks for it.
 */
fun menuListStillEmpty(ui: MonitorUi): Boolean {
  if (ui.targetChoices.isEmpty() || ui.conversationChoices.isEmpty()) return true
  if (ui.modelChoices.isEmpty() && ui.modelNote.isEmpty()) return true
  if (ui.reasoningChoices.isEmpty() && ui.reasoningNote.isEmpty()) return true
  if (ui.permissionChoices.isEmpty() && ui.permissionNote.isEmpty()) return true
  return false
}

/** One request when the drawer opens, the link is live, and a list is still empty. Not on every open. */
fun menuChoicesNeeded(ui: MonitorUi, linkLive: Boolean): Boolean {
  return linkLive && !ui.disconnected && menuListStillEmpty(ui)
}

/** A live link with no model name still needs the footer list. The drawer is not the only ask. */
fun statusModelNeeded(ui: MonitorUi, linkLive: Boolean): Boolean {
  return linkLive && !ui.disconnected && shownModel(ui.view.model).isEmpty()
}

/** History rows stay put while disconnected or sending. A plan run does not lock them. */
fun conversationRowsEnabled(disconnected: Boolean, sending: Boolean): Boolean {
  return !disconnected && !sending
}

/** The check is the flagged row, or the row whose id equals the host current. */
fun conversationSelectedId(choices: List<ConversationChoice>, current: String): String {
  val flagged = choices.firstOrNull { it.current }
  if (flagged != null) return flagged.id
  return current
}

enum class MenuSectionKind {
  Target,
  Mode,
  Conversation,
  Plan,
  Model,
  Reasoning,
  Permissions
}

enum class MenuTap {
  CloseOnly,
  CloseAndSend
}

data class MenuRow(val id: String, val caption: String)

data class MenuSectionModel(
  val kind: MenuSectionKind,
  val label: String,
  val rows: List<MenuRow>,
  val currentId: String,
  val enabled: Boolean,
  val note: String = ""
)

data class MenuFlyoutPoint(val x: Int, val y: Int)

/** The check is the host id. A tap must not paint a new one before the next frame. */
fun menuCheckedId(hostId: String): String = hostId

/** Caption of the checked row. Empty when the host id is not in the list. An empty id can match. */
fun menuCurrentCaption(section: MenuSectionModel): String {
  val checked = menuCheckedId(section.currentId)
  return section.rows.firstOrNull { it.id == checked }?.caption ?: ""
}

/** The same heading again closes its flyout. A different heading switches. */
fun menuFlyoutAfterTap(open: MenuSectionKind?, tapped: MenuSectionKind): MenuSectionKind? {
  if (open == tapped) return null
  return tapped
}

/** Back closes the flyout before the drawer. */
fun menuFlyoutConsumesBack(flyoutOpen: Boolean): Boolean = flyoutOpen

/** Left-edge swipe opens the menu on Conversation only. Plan keeps the pager swipe. */
fun menuEdgeSwipeEnabled(tab: AppTab, approvalOpen: Boolean): Boolean {
  return tab == AppTab.Conversation && !approvalOpen
}

/** A rightward drag that started inside the left edge. Values are pixels. */
fun menuOpensOnRightEdgeSwipe(startX: Float, edgePx: Float, totalDx: Float, minPx: Float): Boolean {
  return edgePx > 0f && startX >= 0f && startX <= edgePx && minPx > 0f && totalDx >= minPx
}

/** Hit width for the conversation edge. The Plan page has no strip, so its swipe still changes page. */
val MenuEdgeSwipeWidth = 32.dp

/**
 * Width of the flyout in pixels. Prefer the room beside the headings, and keep a scrim strip when that
 * still leaves a usable menu. Values are pixels, not dp.
 */
fun menuFlyoutWidthPx(
  anchorLeft: Int,
  windowWidth: Int,
  labelOffsetPx: Int,
  preferredPx: Int,
  marginPx: Int,
  minPx: Int,
  scrimReservePx: Int
): Int {
  if (windowWidth <= marginPx * 2) return 0
  val start = anchorLeft + labelOffsetPx
  val withScrim = windowWidth - start - marginPx - scrimReservePx
  if (withScrim >= minPx) return withScrim.coerceAtMost(preferredPx)
  val beside = windowWidth - start - marginPx
  if (beside >= minPx) return beside.coerceAtMost(preferredPx)
  return (windowWidth - marginPx * 2).coerceAtLeast(0).coerceAtMost(preferredPx)
}

/** Place the flyout at the end of the heading. Shift it back onto the window when that does not fit. */
fun menuFlyoutOrigin(
  anchorLeft: Int,
  anchorTop: Int,
  windowWidth: Int,
  windowHeight: Int,
  labelOffsetPx: Int,
  flyoutWidth: Int,
  flyoutHeight: Int,
  marginPx: Int
): MenuFlyoutPoint {
  val x = if (flyoutWidth <= 0 || windowWidth <= marginPx * 2) {
    0
  } else {
    val preferredX = anchorLeft + labelOffsetPx
    val fitted = windowWidth - marginPx - flyoutWidth
    if (preferredX >= 0 && preferredX + flyoutWidth <= windowWidth - marginPx) preferredX else fitted.coerceAtLeast(0)
  }
  val height = flyoutHeight.coerceAtMost((windowHeight - marginPx * 2).coerceAtLeast(0))
  val y = if (windowHeight <= marginPx * 2) {
    0
  } else {
    val maxY = windowHeight - marginPx - height
    if (maxY <= marginPx) marginPx else anchorTop.coerceIn(marginPx, maxY)
  }
  return MenuFlyoutPoint(x, y)
}

/** A left swipe closes. A short or rightward drag does not. */
fun menuClosesOnLeftSwipe(totalDx: Float, minPx: Float): Boolean = minPx > 0f && totalDx <= -minPx

/** Claims a rightward drag that starts in the left edge. A tap or a vertical drag is left alone. */
fun Modifier.menuEdgeSwipeToOpen(onOpen: () -> Unit): Modifier = pointerInput(onOpen) {
  val edge = MenuEdgeSwipeWidth.toPx()
  val threshold = 48.dp.toPx()
  val slop = viewConfiguration.touchSlop
  awaitEachGesture {
    val down = awaitFirstDown(pass = PointerEventPass.Initial, requireUnconsumed = false)
    if (down.position.x > edge) return@awaitEachGesture
    var total = 0f
    var tracking = false
    while (true) {
      val event = awaitPointerEvent(PointerEventPass.Initial)
      val change = event.changes.firstOrNull { pointer -> pointer.id == down.id } ?: break
      if (!change.pressed) {
        if (tracking && menuOpensOnRightEdgeSwipe(down.position.x, edge, total, threshold)) onOpen()
        break
      }
      val dx = change.position.x - change.previousPosition.x
      val dy = change.position.y - change.previousPosition.y
      if (!tracking) {
        if (kotlin.math.abs(dx) > slop && kotlin.math.abs(dx) > kotlin.math.abs(dy)) tracking = true
        else if (kotlin.math.abs(dy) > slop) break
      }
      if (tracking) {
        total += dx
        change.consume()
      }
    }
  }
}

/** Sees the swipe before the menu's vertical scroller, so a list drag still scrolls. */
fun Modifier.menuLeftSwipeToClose(onClose: () -> Unit): Modifier = pointerInput(onClose) {
  val threshold = 48.dp.toPx()
  val slop = viewConfiguration.touchSlop
  awaitEachGesture {
    val down = awaitFirstDown(requireUnconsumed = false)
    var total = 0f
    var tracking = false
    while (true) {
      val event = awaitPointerEvent(PointerEventPass.Initial)
      val change = event.changes.firstOrNull { pointer -> pointer.id == down.id } ?: break
      if (!change.pressed) {
        if (tracking && menuClosesOnLeftSwipe(total, threshold)) onClose()
        break
      }
      val dx = change.position.x - change.previousPosition.x
      val dy = change.position.y - change.previousPosition.y
      if (!tracking) {
        if (kotlin.math.abs(dx) > slop && kotlin.math.abs(dx) > kotlin.math.abs(dy)) tracking = true
        else if (kotlin.math.abs(dy) > slop) break
      }
      if (tracking) {
        total += dx
        change.consume()
      }
    }
  }
}

/** Choosing the current row closes and sends nothing. Another row closes and sends. A disabled row does neither. */
fun menuTap(rowId: String, currentId: String, enabled: Boolean): MenuTap? {
  if (!enabled) return null
  if (rowId == currentId) return MenuTap.CloseOnly
  return MenuTap.CloseAndSend
}

fun menuHeader(ui: MonitorUi): String = ui.view.targetDisplay

/**
 * Seven sections in drawer order. Mode and Plan are already on the phone.
 * Target, Conversation, Model, Reasoning, and Tool Permissions fill from their host frames.
 * Disconnect disables rows and does not clear lists.
 */
fun appMenuSections(ui: MonitorUi): List<MenuSectionModel> {
  val linkUp = !ui.disconnected
  // Mode sends set_mode only when canChangeMode is true and the link is up, the same gate setMode can complete.
  val canSend = linkUp && ui.view.canChangeMode
  val targetEnabled = targetRowsEnabled(ui.disconnected, ui.view.sending, ui.view.planRunning || ui.planRunning)
  val historyEnabled = conversationRowsEnabled(ui.disconnected, ui.view.sending)
  val modelEnabled = modelRowsEnabled(ui.disconnected, ui.view.sending, ui.view.planRunning || ui.planRunning)
  val reasoningEnabled = reasoningRowsEnabled(ui.disconnected, ui.view.sending, ui.view.planRunning || ui.planRunning)
  val permissionEnabled = permissionRowsEnabled(ui.disconnected, ui.view.sending, ui.view.planRunning || ui.planRunning)
  val historyNote = if (ui.conversationsTruncated) OlderConversationsSentence else ""
  return listOf(
    MenuSectionModel(
      MenuSectionKind.Target, "Target",
      ui.targetChoices.map { MenuRow(it.path, targetChoiceCaption(it)) },
      ui.targetCurrent, targetEnabled
    ),
    MenuSectionModel(
      MenuSectionKind.Mode, "Mode", ModeChoices.map { MenuRow(it.first, modeCaption(it.first)) }, ui.view.mode, canSend
    ),
    MenuSectionModel(
      MenuSectionKind.Conversation, "Conversation",
      ui.conversationChoices.map { MenuRow(it.id, it.title) },
      conversationSelectedId(ui.conversationChoices, ui.conversationCurrent),
      historyEnabled, historyNote
    ),
    // Captions from planChoices. The check is planPath. A different row calls openPlan.
    MenuSectionModel(
      MenuSectionKind.Plan, "Plan", ui.planChoices.map { MenuRow(it.path, it.caption) }, ui.planPath, canSend
    ),
    MenuSectionModel(
      MenuSectionKind.Model, "Model",
      ui.modelChoices.map { MenuRow(it.id, it.caption) },
      ui.view.model, modelEnabled, ui.modelNote
    ),
    // The check is reasoningCurrent. view.effort is a caption and must not select a row.
    MenuSectionModel(
      MenuSectionKind.Reasoning, "Reasoning Level",
      ui.reasoningChoices.map { MenuRow(it.id, it.caption) },
      ui.reasoningCurrent, reasoningEnabled, ui.reasoningNote
    ),
    // The check is permissionCurrent. view.approvalCaption is a short word and must not select a row.
    MenuSectionModel(
      MenuSectionKind.Permissions, "Tool Permissions",
      ui.permissionChoices.map { MenuRow(it.id, it.caption) },
      ui.permissionCurrent, permissionEnabled, ui.permissionNote
    )
  )
}

@Composable
fun AppMenu(
  ui: MonitorUi,
  openKind: MenuSectionKind?,
  onOpenKind: (MenuSectionKind?) -> Unit,
  onClose: () -> Unit,
  onMode: (String) -> Unit,
  onPlan: (String) -> Unit,
  onTarget: (String) -> Unit,
  onConversation: (String) -> Unit,
  onModel: (String) -> Unit,
  onReasoning: (String) -> Unit,
  onPermissions: (String) -> Unit
) {
  Column(
    Modifier
      .menuLeftSwipeToClose(onClose)
      .fillMaxSize()
      .verticalScroll(rememberScrollState())
      .padding(start = 12.dp, top = 12.dp, end = 8.dp, bottom = 16.dp)
  ) {
    Text(
      menuHeader(ui),
      style = MaterialTheme.typography.titleMedium,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
      modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp)
    )
    appMenuSections(ui).forEach { section ->
      MenuHeading(
        section,
        open = openKind == section.kind,
        onToggle = { onOpenKind(menuFlyoutAfterTap(openKind, section.kind)) },
        onDismissFlyout = { onOpenKind(null) },
        onClose = onClose,
        onMode = onMode,
        onPlan = onPlan,
        onTarget = onTarget,
        onConversation = onConversation,
        onModel = onModel,
        onReasoning = onReasoning,
        onPermissions = onPermissions
      )
    }
  }
}

@Composable
private fun MenuHeading(
  section: MenuSectionModel,
  open: Boolean,
  onToggle: () -> Unit,
  onDismissFlyout: () -> Unit,
  onClose: () -> Unit,
  onMode: (String) -> Unit,
  onPlan: (String) -> Unit,
  onTarget: (String) -> Unit,
  onConversation: (String) -> Unit,
  onModel: (String) -> Unit,
  onReasoning: (String) -> Unit,
  onPermissions: (String) -> Unit
) {
  val density = LocalDensity.current
  val host = LocalView.current
  val labelOffsetPx = with(density) { MenuFlyoutOffset.roundToPx() }
  val marginPx = with(density) { MenuFlyoutMargin.roundToPx() }
  val preferredPx = with(density) { MenuFlyoutPreferred.roundToPx() }
  val minPx = with(density) { MenuFlyoutMin.roundToPx() }
  val scrimPx = with(density) { MenuFlyoutScrimReserve.roundToPx() }
  var anchorLeft by remember { mutableIntStateOf(-1) }
  var windowWidth by remember { mutableIntStateOf(0) }
  var windowHeight by remember { mutableIntStateOf(0) }
  val flyoutWidthPx = if (anchorLeft < 0 || windowWidth <= 0) {
    0
  } else {
    menuFlyoutWidthPx(anchorLeft, windowWidth, labelOffsetPx, preferredPx, marginPx, minPx, scrimPx)
  }
  val maxHeightPx = (windowHeight - marginPx * 2).coerceAtLeast(0)
  val labelColor = if (open) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
  val current = menuCurrentCaption(section)
  Box(
    Modifier
      .fillMaxWidth()
      .onGloballyPositioned { coordinates ->
        anchorLeft = coordinates.boundsInWindow().left.roundToInt()
        windowWidth = host.width
        windowHeight = host.height
      }
  ) {
    Row(
      Modifier
        .fillMaxWidth()
        .defaultMinSize(minHeight = 48.dp)
        .clickable(onClick = onToggle)
        .semantics { selected = open },
      verticalAlignment = Alignment.CenterVertically
    ) {
      Column(Modifier.width(140.dp)) {
        Text(
          section.label,
          color = labelColor,
          style = MaterialTheme.typography.labelLarge,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis
        )
        if (current.isNotEmpty()) {
          Text(
            current,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodySmall,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
          )
        }
      }
      Spacer(Modifier.width(4.dp))
      Icon(
        painterResource(R.drawable.ic_submenu),
        contentDescription = null,
        modifier = Modifier.size(24.dp),
        tint = labelColor
      )
    }
    if (open && flyoutWidthPx > 0) {
      val provider = remember(labelOffsetPx, marginPx) { MenuFlyoutPositionProvider(labelOffsetPx, marginPx) }
      Popup(
        popupPositionProvider = provider,
        onDismissRequest = onDismissFlyout,
        properties = PopupProperties(focusable = false, dismissOnBackPress = false, dismissOnClickOutside = false)
      ) {
        MenuFlyout(
          section,
          with(density) { flyoutWidthPx.toDp() },
          with(density) { maxHeightPx.toDp() },
          onDismissFlyout,
          onClose,
          onMode,
          onPlan,
          onTarget,
          onConversation,
          onModel,
          onReasoning,
          onPermissions
        )
      }
    }
  }
}

@Composable
private fun MenuFlyout(
  section: MenuSectionModel,
  width: Dp,
  maxHeight: Dp,
  onDismissFlyout: () -> Unit,
  onClose: () -> Unit,
  onMode: (String) -> Unit,
  onPlan: (String) -> Unit,
  onTarget: (String) -> Unit,
  onConversation: (String) -> Unit,
  onModel: (String) -> Unit,
  onReasoning: (String) -> Unit,
  onPermissions: (String) -> Unit
) {
  Surface(
    modifier = Modifier.width(width).heightIn(max = maxHeight).menuLeftSwipeToClose(onDismissFlyout),
    shape = MenuFlyoutShape,
    color = MaterialTheme.colorScheme.surface,
    shadowElevation = 8.dp,
    tonalElevation = 2.dp
  ) {
    Column(Modifier.verticalScroll(rememberScrollState()).padding(vertical = 4.dp)) {
      Text(
        section.label,
        style = MaterialTheme.typography.labelLarge,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
      )
      HorizontalDivider()
      if (section.rows.isEmpty()) {
        Text(
          MenuEmptySentence,
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
          modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
        )
      } else {
        section.rows.forEach { row ->
          val current = row.id == menuCheckedId(section.currentId)
          MenuRowLine(row.caption, current, section.enabled) {
            val tap = menuTap(row.id, section.currentId, section.enabled) ?: return@MenuRowLine
            onDismissFlyout()
            onClose()
            if (tap == MenuTap.CloseAndSend) {
              sendMenuCommand(
                section.kind, row.id, onMode, onPlan, onTarget, onConversation, onModel, onReasoning, onPermissions
              )
            }
          }
        }
      }
      if (section.note.isNotEmpty()) {
        Text(
          section.note,
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
          modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
        )
      }
    }
  }
}

private class MenuFlyoutPositionProvider(
  private val labelOffsetPx: Int,
  private val marginPx: Int
) : PopupPositionProvider {
  override fun calculatePosition(
    anchorBounds: IntRect,
    windowSize: IntSize,
    layoutDirection: LayoutDirection,
    popupContentSize: IntSize
  ): IntOffset {
    val point = menuFlyoutOrigin(
      anchorBounds.left,
      anchorBounds.top,
      windowSize.width,
      windowSize.height,
      labelOffsetPx,
      popupContentSize.width,
      popupContentSize.height,
      marginPx
    )
    return IntOffset(point.x, point.y)
  }
}

/** Host refusals stay on the status banner. This does not open a dialog. */
private fun sendMenuCommand(
  kind: MenuSectionKind,
  id: String,
  onMode: (String) -> Unit,
  onPlan: (String) -> Unit,
  onTarget: (String) -> Unit,
  onConversation: (String) -> Unit,
  onModel: (String) -> Unit,
  onReasoning: (String) -> Unit,
  onPermissions: (String) -> Unit
) {
  when (kind) {
    MenuSectionKind.Mode -> onMode(id)
    MenuSectionKind.Plan -> onPlan(id)
    MenuSectionKind.Target -> onTarget(id)
    MenuSectionKind.Conversation -> onConversation(id)
    MenuSectionKind.Model -> onModel(id)
    MenuSectionKind.Reasoning -> onReasoning(id)
    // Footer approval mode. Do not call allowApproval or denyApproval from here.
    MenuSectionKind.Permissions -> onPermissions(id)
  }
}

@Composable
private fun MenuRowLine(caption: String, current: Boolean, enabled: Boolean, onClick: () -> Unit) {
  val color = when {
    current -> MaterialTheme.colorScheme.primary
    enabled -> MaterialTheme.colorScheme.onSurface
    else -> MaterialTheme.colorScheme.onSurfaceVariant
  }
  Box(
    Modifier
      .fillMaxWidth()
      .defaultMinSize(minHeight = 48.dp)
      .clickable(enabled = enabled, onClick = onClick)
      .semantics { selected = current }
      .padding(horizontal = 16.dp),
    contentAlignment = Alignment.CenterStart
  ) {
    Text(caption, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
  }
}
