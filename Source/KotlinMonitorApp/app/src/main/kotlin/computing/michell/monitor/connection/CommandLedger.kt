package computing.michell.monitor.connection

/* Stored commands the connection can replay (c) 2026 Michell Computing.

   The ledger is asked before a user command is written, and again when the
   host answers resume. A missing ledger keeps the old send path. */

data class StoredCommand(val commandId: String, val kind: String, val json: String, val state: String)

data class ReplayPlan(val resendJson: List<String>, val retryText: String, val retryJson: String)

interface CommandLedger {
  fun openIds(): List<String>
  suspend fun remember(json: String)
  suspend fun applyHost(states: List<HostCommandState>): ReplayPlan
}

object NoCommandLedger : CommandLedger {
  override fun openIds(): List<String> = emptyList()
  override suspend fun remember(json: String) {}
  override suspend fun applyHost(states: List<HostCommandState>): ReplayPlan = ReplayPlan(emptyList(), "", "")
}

class MemoryCommandLedger : CommandLedger {
  private val gate = Any()
  private val rows = mutableListOf<StoredCommand>()

  override fun openIds(): List<String> = synchronized(gate) {
    rows.filter { it.state != OutboxDone && it.state != OutboxRejected }.map { it.commandId }
  }

  override suspend fun remember(json: String) {
    val decoded = computing.michell.monitor.protocol.tryDecodeEnvelope(json)
    if (!decoded.ok || decoded.message.id.isEmpty()) return
    val row = StoredCommand(decoded.message.id, decoded.message.kind.wireName, json, OutboxOpen)
    synchronized(gate) {
      val index = rows.indexOfFirst { it.commandId == row.commandId }
      if (index >= 0) rows[index] = row else rows += row
    }
  }

  override suspend fun applyHost(states: List<HostCommandState>): ReplayPlan {
    val byId = states.associateBy { it.ref }
    val resend = ArrayList<String>()
    var retryText = ""
    var retryJson = ""
    synchronized(gate) {
      val next = ArrayList<StoredCommand>()
      for (row in rows) {
        if (row.state == OutboxDone || row.state == OutboxRejected) continue
        val hostState = byId[row.commandId]?.state ?: "unknown"
        when (replayAction(row.kind, row.state, hostState)) {
          ReplayAction.Clear -> {}
          ReplayAction.Wait -> next += row.copy(state = hostState)
          ReplayAction.Resend -> {
            next += row
            resend += row.json
          }
          ReplayAction.OfferRetry -> {
            next += row.copy(state = OutboxAccepted)
            if (retryText.isEmpty()) {
              retryText = commandText(row.json)
              retryJson = row.json
            }
          }
        }
      }
      rows.clear()
      rows.addAll(next)
    }
    return ReplayPlan(resend, retryText, retryJson)
  }
}
