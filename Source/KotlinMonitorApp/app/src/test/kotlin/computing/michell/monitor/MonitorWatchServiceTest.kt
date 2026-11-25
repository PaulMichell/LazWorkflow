package computing.michell.monitor

/* The screen-off watch starts, updates, and stops from pulses.
   (c) 2026 Michell Computing. */

import android.app.Notification
import android.app.NotificationManager
import android.os.Looper
import computing.michell.monitor.net.PulseFetch
import computing.michell.monitor.net.PulseIntervalDefaultMs
import computing.michell.monitor.net.PulseLoop
import computing.michell.monitor.net.PulseSource
import computing.michell.monitor.net.parseMonitorTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class MonitorWatchServiceTest {
  @Test
  fun aPlanRunStartsUpdatesAndStopsTheWatch() {
    val since = "2026-07-16T11:52:00Z"
    val firstNow = parseMonitorTime(since)
    val secondNow = firstNow + 12 * 60_000L + 4_000L
    val loop = PulseLoop(PulseSource { PulseFetch.TimedOut })
    WatchBridge.attach(loop)
    val controller = Robolectric.buildService(
      MonitorWatchService::class.java,
      android.content.Intent(org.robolectric.RuntimeEnvironment.getApplication(), MonitorWatchService::class.java)
        .putExtra(MonitorWatchService.ExtraPulse, planPulse(true, "Thinking", since))
        .putExtra(MonitorWatchService.ExtraNow, firstNow)
    ).create()
    try {
      controller.startCommand(0, 0)
      val service = controller.get()
      assertEquals(WatchIntervalMs, loop.intervalMs)
      shadowOf(Looper.getMainLooper()).idle()
      assertTrue(noticeText(service, 56122).contains("Plan 3.2"))
      assertTrue(noticeText(service, 56122).contains("Thinking"))
      service.applyPulse(planPulse(true, "Running build", since), secondNow)
      shadowOf(Looper.getMainLooper()).idle()
      assertEquals("Plan 3.2 · Running build · 12:04", noticeText(service, 56122))
      service.applyPulse(planPulse(false, "", since), secondNow)
      shadowOf(Looper.getMainLooper()).idle()
      assertTrue(shadowOf(service).isStoppedBySelf)
      assertEquals("Plan finished", noticeText(service, 56123))
      assertFalse(WatchBridge.active)
      assertEquals(PulseIntervalDefaultMs, loop.intervalMs)
    } finally {
      WatchBridge.detach(loop)
      loop.close()
      controller.destroy()
    }
  }
}

private fun noticeText(service: MonitorWatchService, id: Int): String {
  val manager = service.getSystemService(NotificationManager::class.java)
  val status = manager.activeNotifications.first { it.id == id }
  return status.notification.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
}

private fun planPulse(running: Boolean, activity: String, since: String): String {
  return """{"status":{"sending":false,"plan_running":$running,"activity":"$activity","activity_since":"$since"},"plan":{"item":"3.2","running":$running}}"""
}
