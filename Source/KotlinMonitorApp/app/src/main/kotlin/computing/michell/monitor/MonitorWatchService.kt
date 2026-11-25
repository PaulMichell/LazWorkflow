package computing.michell.monitor

/* Foreground hold while a desktop run continues and the screen is off.
   (c) 2026 Michell Computing.

   PulseLoop stays the only connection. This service slows that loop to five
   seconds and shows the activity. A pulse that clears the run, or a disconnect,
   stops the service. Only a finished run posts the completion notice. */

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

class MonitorWatchService : Service() {
  private var wasPlan = false
  private var completionPosted = false
  private val onPulse: (String) -> Unit = { json -> applyPulse(json, System.currentTimeMillis()) }

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onCreate() {
    super.onCreate()
    running = true
    WatchBridge.setWatching(true)
    WatchBridge.listen(onPulse)
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    val json = intent?.getStringExtra(ExtraPulse).orEmpty()
    val now = intent?.getLongExtra(ExtraNow, System.currentTimeMillis()) ?: System.currentTimeMillis()
    val snapshot = watchSnapshotOf(json)
    val text = if (snapshot != null && snapshot.watching) watchNotificationText(snapshot, now) else getString(R.string.monitor_hold_text)
    if (snapshot?.planRunning == true) wasPlan = true
    try {
      val notice = ongoing(text)
      if (Build.VERSION.SDK_INT >= 29) {
        startForeground(ForegroundId, notice, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
      } else {
        startForeground(ForegroundId, notice)
      }
    } catch (error: Exception) {
      stopWatch(completion = false)
      return START_NOT_STICKY
    }
    if (json.isNotEmpty()) applyPulse(json, now)
    return START_NOT_STICKY
  }

  override fun onDestroy() {
    running = false
    WatchBridge.unlisten(onPulse)
    WatchBridge.setWatching(false)
    super.onDestroy()
  }

  internal fun applyPulse(json: String, nowMs: Long) {
    if (json.isEmpty()) {
      stopWatch(completion = false)
      return
    }
    val snapshot = watchSnapshotOf(json) ?: return
    if (snapshot.watching) {
      if (snapshot.planRunning) wasPlan = true
      show(watchNotificationText(snapshot, nowMs))
      return
    }
    stopWatch(completion = true)
  }

  private fun show(text: String) {
    val manager = getSystemService(NotificationManager::class.java) ?: return
    ensureChannel(manager)
    manager.notify(ForegroundId, ongoing(text))
  }

  private fun stopWatch(completion: Boolean) {
    WatchBridge.setWatching(false)
    if (completion && !completionPosted) {
      completionPosted = true
      val manager = getSystemService(NotificationManager::class.java)
      if (manager != null) {
        ensureChannel(manager)
        manager.notify(CompletionId, completionNotice(watchCompletionText(wasPlan)))
      }
    }
    try {
      stopForeground(STOP_FOREGROUND_REMOVE)
    } catch (error: Exception) {
      // Foreground was never entered.
    }
    stopSelf()
  }

  private fun ongoing(text: String): Notification {
    ensureChannel(getSystemService(NotificationManager::class.java))
    return Notification.Builder(this, ChannelId)
      .setSmallIcon(R.drawable.ic_launcher_foreground)
      .setContentTitle(getString(R.string.monitor_hold_title))
      .setContentText(text)
      .setOngoing(true)
      .setOnlyAlertOnce(true)
      .build()
  }

  private fun completionNotice(text: String): Notification {
    return Notification.Builder(this, ChannelId)
      .setSmallIcon(R.drawable.ic_launcher_foreground)
      .setContentTitle(getString(R.string.monitor_hold_title))
      .setContentText(text)
      .setAutoCancel(true)
      .build()
  }

  private fun ensureChannel(manager: NotificationManager?) {
    if (Build.VERSION.SDK_INT < 26 || manager == null) return
    if (manager.getNotificationChannel(ChannelId) != null) return
    manager.createNotificationChannel(
      NotificationChannel(ChannelId, getString(R.string.monitor_watch_channel), NotificationManager.IMPORTANCE_LOW)
    )
  }

  companion object {
    const val ExtraPulse = "pulse"
    const val ExtraNow = "now"
    private const val ForegroundId = 56122
    private const val CompletionId = 56123
    private const val ChannelId = "monitor-watch"

    @Volatile var running: Boolean = false
      private set

    fun start(context: Context, pulseJson: String, nowMs: Long) {
      val intent = Intent(context, MonitorWatchService::class.java)
        .putExtra(ExtraPulse, pulseJson)
        .putExtra(ExtraNow, nowMs)
      try {
        context.startForegroundService(intent)
      } catch (error: Exception) {
        // A refused start leaves the existing loop at its normal interval.
      }
    }

    fun stop(context: Context) {
      try {
        context.stopService(Intent(context, MonitorWatchService::class.java))
      } catch (error: Exception) {
        // Already stopped.
      }
    }
  }
}
