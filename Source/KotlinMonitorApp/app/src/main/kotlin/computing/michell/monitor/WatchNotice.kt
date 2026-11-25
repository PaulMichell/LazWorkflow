package computing.michell.monitor

/* Notification text for a run watched with the screen off (c) 2026 Michell Computing.

   The service does not open a socket. It only decides whether the existing
   pulse loop should keep watching, and what the notification should say. */

import computing.michell.monitor.net.parseJson
import computing.michell.monitor.net.parseMonitorTime
import computing.michell.monitor.net.bool
import computing.michell.monitor.net.field
import computing.michell.monitor.net.text
import computing.michell.monitor.ui.model.formatActivityClock

const val WatchIntervalMs = 5_000L

data class WatchSnapshot(
  val sending: Boolean,
  val planRunning: Boolean,
  val planItem: String,
  val activity: String,
  val activitySinceMs: Long
) {
  val watching: Boolean
    get() = sending || planRunning
}

fun watchSnapshotOf(json: String): WatchSnapshot? {
  if (json.isEmpty()) return null
  val root = parseJson(json) ?: return null
  val status = root.field("status")
  val plan = root.field("plan")
  return WatchSnapshot(
    sending = status != null && status.bool("sending"),
    planRunning = status != null && status.bool("plan_running"),
    planItem = if (plan == null) "" else plan.text("item"),
    activity = if (status == null) "" else status.text("activity"),
    activitySinceMs = parseMonitorTime(if (status == null) "" else status.text("activity_since"))
  )
}

fun watchItemLabel(snapshot: WatchSnapshot): String {
  val item = snapshot.planItem.trim()
  if (item.isEmpty()) return if (snapshot.planRunning) "Plan" else "Reply"
  if (item.startsWith("Plan")) return item
  return if (snapshot.planRunning) "Plan $item" else item
}

/** "Plan 3.2 · Running build · 12:04" */
fun watchNotificationText(snapshot: WatchSnapshot, nowMs: Long): String {
  val activity = snapshot.activity.trim().ifEmpty { if (snapshot.planRunning) "Running" else "Sending" }
  val elapsed = if (snapshot.activitySinceMs <= 0L || nowMs < snapshot.activitySinceMs) 0L else nowMs - snapshot.activitySinceMs
  return watchItemLabel(snapshot) + " · " + activity + " · " + formatActivityClock(elapsed)
}

fun watchCompletionText(wasPlan: Boolean): String = if (wasPlan) "Plan finished" else "Reply finished"
