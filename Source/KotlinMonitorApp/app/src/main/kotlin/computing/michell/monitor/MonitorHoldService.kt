package computing.michell.monitor

/* Keeps the monitor process and Wi-Fi radio awake while the screen is off (c) 2026 Michell Computing.

   The TLS socket stays in LanSession. This service does not open another one. */

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
    val notice = holdNotification()
    if (Build.VERSION.SDK_INT >= 29) {
      startForeground(NotificationId, notice, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
    } else {
      startForeground(NotificationId, notice)
    }
    acquireRadio()
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

  private fun acquireRadio() {
    if (radioLock?.isHeld == true) return
    val wifi = applicationContext.getSystemService(WifiManager::class.java) ?: return
    val mode = if (Build.VERSION.SDK_INT >= 29) WifiManager.WIFI_MODE_FULL_LOW_LATENCY
      else WifiManager.WIFI_MODE_FULL_HIGH_PERF
    val lock = try {
      wifi.createWifiLock(mode, LockName)
    } catch (error: Exception) {
      return
    }
    lock.setReferenceCounted(false)
    try {
      lock.acquire()
      radioLock = lock
    } catch (error: Exception) {
      // A missing lock must not drop the socket the session is already holding.
    }
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

    fun start(context: Context) {
      val intent = Intent(context, MonitorHoldService::class.java)
      try {
        context.startForegroundService(intent)
      } catch (error: Exception) {
        // The session hold still stands if the process cannot promote the service.
      }
    }

    fun stop(context: Context) {
      try {
        context.stopService(Intent(context, MonitorHoldService::class.java))
      } catch (error: Exception) {
        // Already stopped.
      }
    }
  }
}
