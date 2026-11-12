package computing.michell.monitor.ui

/* One connection chip. The label follows the link phase, whether that link will
   reconnect, busy, and whether the open block is behind the announced head.
   A paired-elsewhere flag and a chrome banner are not inputs. A body fetch is
   not an input: a finished status clears Busy even while an older fetch runs.
   A parked wait still uses the banner the link itself published, so
   idle-until-touch and a confirmed Wi-Fi loss stay Offline.
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
const val ChipCatchingUp = "Catching up"
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

/**
 * Live or Busy when the socket is up and the open block matches the announced head.
 * A stale open block says Catching up, then Busy or Live once it matches.
 * Busy is the status frame, not an in-flight body fetch. Reconnecting or Connecting
 * while an in-use retry will come back. Offline otherwise. `banner` is the link
 * status text, not a chrome note: it only keeps a parked wait from printing Reconnecting.
 */
fun connectionChip(
  phase: LinkPhase,
  reconnectable: Boolean,
  busy: Boolean,
  lastSyncMs: Long = 0L,
  zone: ZoneId = ZoneId.systemDefault(),
  banner: String = "",
  openBehind: Boolean = false
): ConnectionChip {
  if (phase == LinkPhase.Live) {
    if (openBehind) return ConnectionChip(ChipCatchingUp)
    return ConnectionChip(if (busy) ChipBusy else ChipLive)
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
