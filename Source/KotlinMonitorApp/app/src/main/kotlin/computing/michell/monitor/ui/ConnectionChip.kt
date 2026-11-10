package computing.michell.monitor.ui

/* One connection chip. Busy comes only from the state channel.
   Catch-up is not a status. A live link says Live or Busy, the same as the desktop.
   An in-use retry says Reconnecting, or Connecting once the attempt has started.
   (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.BackgroundBanner
import computing.michell.monitor.connection.IdleOfflineBanner
import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.connection.WaitingForWifiBanner
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

const val ChipLive = "Live"
const val ChipSyncing = "Syncing"
const val ChipOffline = "Offline"
const val ChipBusy = "Busy"
const val ChipReconnecting = "Reconnecting"
const val ChipConnecting = "Connecting"
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
  zone: ZoneId = ZoneId.systemDefault(),
  reconnectable: Boolean = false,
  banner: String = ""
): ConnectionChip {
  if (pairedElsewhere) return ConnectionChip(PairedElsewhereLabel)
  val live = phase == LinkPhase.Live && !disconnected
  // The log cursor is not a progress count. Sync runs behind a live screen.
  // Busy still wins on a live link while a plan or turn is running.
  if (live && statusBusy) return ConnectionChip(ChipBusy)
  if (live) return ConnectionChip(ChipLive)
  if (linkSyncing(phase, disconnected, catchingUp, pairedElsewhere)) {
    return ConnectionChip(syncingLabel(appliedSeq, syncHead))
  }
  if (inUseRetry(phase, reconnectable, banner)) {
    val label = if (phase == LinkPhase.Connecting) ChipConnecting else ChipReconnecting
    return ConnectionChip(label)
  }
  return ConnectionChip(offlineLabel(lastSyncMs, zone))
}

/**
 * A backoff or a handshake, while the app is still in use. Not a pause, an unpaired
 * phone, an idle-until-touch wait, or a confirmed Wi-Fi loss.
 */
fun inUseRetry(phase: LinkPhase, reconnectable: Boolean, banner: String): Boolean {
  if (!reconnectable || phase == LinkPhase.Paused) return false
  if (phase == LinkPhase.Connecting) return true
  if (phase != LinkPhase.Disconnected) return false
  return banner != IdleOfflineBanner && banner != WaitingForWifiBanner && banner != BackgroundBanner
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
