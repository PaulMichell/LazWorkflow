package computing.michell.monitor.ui

/* One connection chip. Busy comes only from the state channel.
   Catch-up is not a status. A live link says Live or Busy, the same as the desktop.
   (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.LinkPhase
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

const val ChipLive = "Live"
const val ChipSyncing = "Syncing"
const val ChipOffline = "Offline"
const val ChipBusy = "Busy"
const val PairedElsewhereLabel = "Paired elsewhere"
const val ReplacedReason = "replaced"

data class ConnectionChip(val label: String)

/** Send and New stay available during catch-up. A live chip does not say Syncing. */
fun linkSyncing(
  phase: LinkPhase,
  disconnected: Boolean,
  catchingUp: Boolean,
  pairedElsewhere: Boolean
): Boolean {
  if (pairedElsewhere || !catchingUp) return false
  return phase == LinkPhase.Live || phase == LinkPhase.Connecting || !disconnected
}

fun connectionChip(
  phase: LinkPhase,
  disconnected: Boolean,
  pairedElsewhere: Boolean,
  catchingUp: Boolean,
  statusBusy: Boolean,
  appliedSeq: Long,
  syncHead: Long,
  lastSyncMs: Long,
  zone: ZoneId = ZoneId.systemDefault()
): ConnectionChip {
  if (pairedElsewhere) return ConnectionChip(PairedElsewhereLabel)
  val live = phase == LinkPhase.Live && !disconnected
  // The log cursor is not a progress count. Sync runs behind a live screen.
  if (live && statusBusy) return ConnectionChip(ChipBusy)
  if (live) return ConnectionChip(ChipLive)
  if (linkSyncing(phase, disconnected, catchingUp, pairedElsewhere)) {
    return ConnectionChip(syncingLabel(appliedSeq, syncHead))
  }
  return ConnectionChip(offlineLabel(lastSyncMs, zone))
}

fun syncingLabel(appliedSeq: Long, syncHead: Long): String {
  if (syncHead > 1L && appliedSeq >= 0L && appliedSeq < syncHead) {
    val percent = ((appliedSeq.coerceAtMost(syncHead) * 100L) / syncHead).toInt()
    return "$ChipSyncing $percent%"
  }
  return ChipSyncing
}

fun offlineLabel(lastSyncMs: Long, zone: ZoneId = ZoneId.systemDefault()): String {
  if (lastSyncMs <= 0L) return ChipOffline
  val clock = Instant.ofEpochMilli(lastSyncMs).atZone(zone).format(DateTimeFormatter.ofPattern("HH:mm"))
  return "$ChipOffline · $clock"
}

fun conversationRowKey(turnId: String, blockId: String, blockIndex: Int): String {
  val block = if (blockId.isNotEmpty()) blockId else "index:$blockIndex"
  val turn = if (turnId.isNotEmpty()) turnId else "turn"
  return "$turn\u0000$block"
}
