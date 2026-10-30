package computing.michell.monitor.data

/* Room backing for the phone command ledger (c) 2026 Michell Computing.

   A user command is upserted before the socket write. Host answers update
   the same rows. The connection reads the cached ids without waiting. */

import computing.michell.monitor.connection.CommandLedger
import computing.michell.monitor.connection.HostCommandState
import computing.michell.monitor.connection.OutboxAccepted
import computing.michell.monitor.connection.OutboxDone
import computing.michell.monitor.connection.OutboxOpen
import computing.michell.monitor.connection.OutboxRejected
import computing.michell.monitor.connection.ReplayAction
import computing.michell.monitor.connection.ReplayPlan
import computing.michell.monitor.connection.commandText
import computing.michell.monitor.connection.replayAction
import computing.michell.monitor.protocol.tryDecodeEnvelope

class RoomCommandLedger(private val repository: ConversationRepository) : CommandLedger {
  private val gate = Any()
  private var rows = emptyList<OutboxRecord>()

  fun replace(next: List<OutboxRecord>) {
    synchronized(gate) { rows = next }
  }

  suspend fun refresh() {
    replace(repository.listOutbox())
  }

  /** A prompt from a previous open is not put back in the composer. */
  suspend fun dropOpenPrompts() {
    val current = synchronized(gate) { rows }
    for (row in current) {
      if (row.state == OutboxDone || row.state == OutboxRejected) continue
      if (row.kind != "send" && row.kind != "steer") continue
      repository.removeOutbox(row.commandId)
    }
    refresh()
  }

  override fun openIds(): List<String> = synchronized(gate) {
    rows.filter { it.state != OutboxDone && it.state != OutboxRejected }.map { it.commandId }
  }

  override suspend fun remember(json: String) {
    val decoded = tryDecodeEnvelope(json)
    if (!decoded.ok || decoded.message.id.isEmpty()) return
    val existing = synchronized(gate) { rows.firstOrNull { it.commandId == decoded.message.id } }
    val state = if (existing == null || existing.state == OutboxOpen) OutboxOpen else existing.state
    repository.saveOutbox(OutboxRecord(decoded.message.id, decoded.message.kind.wireName, json, state, System.currentTimeMillis()))
    refresh()
  }

  override suspend fun applyHost(states: List<HostCommandState>): ReplayPlan {
    val byId = states.associateBy { it.ref }
    val resend = ArrayList<String>()
    var retryText = ""
    var retryJson = ""
    val current = synchronized(gate) { rows }
    for (row in current) {
      if (row.state == OutboxDone || row.state == OutboxRejected) continue
      val hostState = byId[row.commandId]?.state ?: "unknown"
      when (replayAction(row.kind, row.state, hostState)) {
        ReplayAction.Clear -> repository.removeOutbox(row.commandId)
        ReplayAction.Wait -> repository.setOutboxState(row.commandId, hostState)
        ReplayAction.Resend -> resend += row.json
        ReplayAction.OfferRetry -> {
          repository.setOutboxState(row.commandId, OutboxAccepted)
          if (retryText.isEmpty()) {
            retryText = commandText(row.json)
            retryJson = row.json
          }
        }
      }
    }
    refresh()
    return ReplayPlan(resend, retryText, retryJson)
  }
}
