package computing.michell.monitor.ui.model

/* Link phase and banner sentences the screens still show (c) 2026 Michell Computing. */

const val RebuildBanner = "Remote monitor is being rebuilt"
const val HostClosedBanner = "Host closed"
const val ConnectionRefusedBanner = "Connection refused."
const val ReconnectingBanner = "Reconnecting"
const val BackgroundBanner = "In the background"
const val WaitingForWifiBanner = "Waiting for Wi-Fi"
const val IdleOfflineBanner = "Offline until the screen is touched"
const val NotDeliveredRetry = "Not delivered — Retry"
const val OfflineBanner = "Offline"
const val OfflineReviewBanner = "Offline review. Send, Stop, and New need a live connection."
const val NoAddressBanner = "Set the desktop address in Settings."

enum class LinkPhase {
  Idle,
  Connecting,
  Live,
  Disconnected,
  Paused
}

data class LinkStatus(
  val phase: LinkPhase = LinkPhase.Idle,
  val banner: String = "",
  val draft: String = "",
  val lastError: String = "",
  val failureReason: String = ""
)
