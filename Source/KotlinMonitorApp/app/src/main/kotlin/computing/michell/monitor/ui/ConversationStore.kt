package computing.michell.monitor.ui

/* Conversation the screen reads. The coordinator does not keep a second copy.
   (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.WireTurn
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class BoardContent(
  val host: String = "",
  val conversationId: String = "",
  val turns: List<WireTurn> = emptyList(),
  val live: WireTurn? = null,
  val revision: Long = 0
)

interface ConversationStore {
  val updates: StateFlow<BoardContent>
  fun current(): BoardContent
  fun replace(host: String, conversationId: String, turns: List<WireTurn>, live: WireTurn?)
  fun adopt(host: String, conversationId: String, turns: List<WireTurn>, live: WireTurn?)
  fun sealHostPaint()
  fun unsealHostPaint()
  fun clear()
}

class MemoryConversationStore : ConversationStore {
  private val gate = Any()
  private var board = BoardContent()
  private var revision = 0L
  private var sealed = false
  private val updatesState = MutableStateFlow(board)
  override val updates: StateFlow<BoardContent> = updatesState.asStateFlow()

  override fun current(): BoardContent = synchronized(gate) { board }

  override fun replace(host: String, conversationId: String, turns: List<WireTurn>, live: WireTurn?) {
    revision += 1
    publish(host, conversationId, turns, live, revision)
  }

  override fun sealHostPaint() {
    synchronized(gate) { sealed = true }
  }

  override fun unsealHostPaint() {
    synchronized(gate) { sealed = false }
  }

  override fun adopt(host: String, conversationId: String, turns: List<WireTurn>, live: WireTurn?) {
    val current = current()
    if (sealed && conversationId == current.conversationId && (current.turns.isNotEmpty() || current.live != null)) return
    val showing = current.turns.isNotEmpty() || current.live != null
    // An empty repository read must not wipe a screen the host just painted.
    if (turns.isEmpty() && live == null && showing && current.conversationId == conversationId) return
    // A late read of the previous conversation must not paint over the new one.
    if (showing && current.conversationId.isNotEmpty() && conversationId != current.conversationId) return
    val hostLive = current.live
    if (hostLive != null && hostLive.id.isNotEmpty() && conversationId == current.conversationId) {
      val kept = (live != null && live.id == hostLive.id) || turns.any { turn -> turn.id == hostLive.id }
      if (!kept) return
    }
    publish(host, conversationId, turns, live, current.revision)
  }

  override fun clear() {
    synchronized(gate) {
      sealed = false
      board = BoardContent()
      updatesState.value = board
    }
  }

  private fun publish(host: String, conversationId: String, turns: List<WireTurn>, live: WireTurn?, revision: Long) {
    synchronized(gate) {
      val next = BoardContent(host, conversationId, turns, live, revision)
      if (next == board) return
      board = next
      updatesState.value = board
    }
  }
}

fun MonitorUi.withBoard(board: BoardContent): MonitorUi {
  return copy(
    turns = board.turns,
    live = board.live,
    history = board.turns.associateBy { turn -> turn.turnIndex }
  )
}

/**
 * Room is the screen only for the open chat. A New tap clears that id, and a stored
 * page for the chat just left must not stay in front of Send or the empty new chat.
 */
fun shownConversation(ui: MonitorUi, stored: BoardContent): MonitorUi {
  if (stored.conversationId.isNotEmpty() && stored.conversationId == ui.conversationId) return ui.withBoard(stored)
  // New and conversation_closed clear the id. The page just left must not stay up.
  if (ui.conversationId.isEmpty()) return ui.copy(turns = emptyList(), live = null, history = emptyMap())
  // Room has not emitted for this open yet. Keep the coordinator copy.
  if (stored.conversationId.isEmpty()) return ui
  return ui.copy(turns = emptyList(), live = null, history = emptyMap())
}
