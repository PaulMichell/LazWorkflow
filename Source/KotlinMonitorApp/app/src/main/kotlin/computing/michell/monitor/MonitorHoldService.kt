package computing.michell.monitor

/* Keeps the monitor process and Wi-Fi radio awake while the screen is off (c) 2026 Michell Computing.

   The TLS socket stays in LanSession. This service does not open another one.
   A refused start is recorded. It is not swallowed, and it is not a CPU wake
   lock: Doze was not measured on a device, so no partial wake lock is taken. */

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder

class MonitorHoldService : Service() {
  private var radioLock: WifiManager.WifiLock? = null

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    try {
      val notice = holdNotification()
      if (Build.VERSION.SDK_INT >= 29) {
        startForeground(NotificationId, notice, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
      } else {
        startForeground(NotificationId, notice)
      }
    } catch (error: Exception) {
      fail(error.message ?: "Foreground hold was not granted.")
      return START_NOT_STICKY
    }
    if (!acquireRadio()) {
      fail("Wi-Fi lock was not acquired.")
      return START_NOT_STICKY
    }
    note(HoldActivation.Active, "")
    return START_NOT_STICKY
  }

  override fun onDestroy() {
    releaseRadio()
    super.onDestroy()
  }

  private fun holdNotification(): Notification {
    val manager = getSystemService(NotificationManager::class.java)
    if (Build.VERSION.SDK_INT >= 26 && manager?.getNotificationChannel(ChannelId) == null) {
      manager?.createNotificationChannel(
        NotificationChannel(ChannelId, getString(R.string.monitor_hold_title), NotificationManager.IMPORTANCE_LOW)
      )
    }
    return Notification.Builder(this, ChannelId)
      .setSmallIcon(R.mipmap.ic_launcher)
      .setContentTitle(getString(R.string.monitor_hold_title))
      .setContentText(getString(R.string.monitor_hold_text))
      .setOngoing(true)
      .build()
  }

  private fun acquireRadio(): Boolean {
    if (radioLock?.isHeld == true) return true
    val wifi = applicationContext.getSystemService(WifiManager::class.java) ?: return false
    val mode = if (Build.VERSION.SDK_INT >= 29) WifiManager.WIFI_MODE_FULL_LOW_LATENCY
      else WifiManager.WIFI_MODE_FULL_HIGH_PERF
    val lock = try {
      wifi.createWifiLock(mode, LockName)
    } catch (error: Exception) {
      return false
    }
    lock.setReferenceCounted(false)
    return try {
      lock.acquire()
      radioLock = lock
      lock.isHeld
    } catch (error: Exception) {
      false
    }
  }

  private fun fail(detail: String) {
    releaseRadio()
    note(HoldActivation.Failed, detail)
    try {
      stopForeground(STOP_FOREGROUND_DETACH)
    } catch (error: Exception) {
      // Foreground was never entered.
    }
    stopSelf()
  }

  private fun releaseRadio() {
    val lock = radioLock
    radioLock = null
    if (lock == null || !lock.isHeld) return
    try {
      lock.release()
    } catch (error: Exception) {
      // Already released.
    }
  }

  companion object {
    private const val NotificationId = 56122
    private const val ChannelId = "monitor-link"
    private const val LockName = "monitor-link"

    @Volatile
    var activation: HoldActivation = HoldActivation.Inactive
      private set

    @Volatile
    var detail: String = ""
      private set

    @Volatile
    var listener: ((Boolean) -> Unit)? = null

    fun start(context: Context): Boolean {
      val intent = Intent(context, MonitorHoldService::class.java)
      return try {
        context.startForegroundService(intent)
        activation = HoldActivation.Starting
        true
      } catch (error: Exception) {
        note(HoldActivation.Failed, error.message ?: HoldNotGrantedNotice)
        false
      }
    }

    fun stop(context: Context) {
      try {
        context.stopService(Intent(context, MonitorHoldService::class.java))
      } catch (error: Exception) {
        // Already stopped.
      }
      if (activation != HoldActivation.Failed) note(HoldActivation.Inactive, "")
    }

    private fun note(next: HoldActivation, text: String) {
      activation = next
      detail = text
      listener?.invoke(next == HoldActivation.Active)
    }
  }
}
