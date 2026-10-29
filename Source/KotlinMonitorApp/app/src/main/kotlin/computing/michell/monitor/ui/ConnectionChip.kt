package computing.michell.monitor.ui

/* One connection chip. Busy comes only from the state channel.
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
  if (catchingUp && (phase == LinkPhase.Live || phase == LinkPhase.Connecting || !disconnected)) {
    return ConnectionChip(syncingLabel(appliedSeq, syncHead))
  }
  val live = phase == LinkPhase.Live && !disconnected
  if (live && statusBusy) return ConnectionChip(ChipBusy)
  if (live) return ConnectionChip(ChipLive)
  return ConnectionChip(offlineLabel(lastSyncMs, zone))
}

fun syncingLabel(appliedSeq: Long, syncHead: Long): String {
  if (syncHead > 0L && appliedSeq >= 0L) {
    val percent = ((appliedSeq.coerceAtMost(syncHead) * 100L) / syncHead).toInt()
    return "$ChipSyncing $percent%"
  }
  if (appliedSeq > 0L) return "$ChipSyncing · $appliedSeq"
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
