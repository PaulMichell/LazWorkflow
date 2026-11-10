package computing.michell.monitor.connection

/* Wi-Fi loss is confirmed before the session is told the radio is down (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WifiLanWatchTest {
  @Test
  fun onLostWhileWifiPresentDoesNotCallOnDown() {
    var down = 0
    var scheduled: (() -> Unit)? = null
    val gate = WifiLossGate(
      onUp = {},
      onDown = { down += 1 },
      wifiPresent = { true },
      confirmLater = { scheduled = it }
    )
    val network = "wlan0"
    gate.onAvailable(network)
    gate.onLost(network)
    assertEquals(0, down)
    assertNull(scheduled)
  }

  @Test
  fun onLostConfirmsWithASecondSampleBeforeDown() {
    var down = 0
    var present = false
    var scheduled: (() -> Unit)? = null
    val gate = WifiLossGate(
      onUp = {},
      onDown = { down += 1 },
      wifiPresent = { present },
      confirmLater = { scheduled = it }
    )
    val network = "wlan0"
    gate.onAvailable(network)
    gate.onLost(network)
    assertEquals(0, down)
    val firstConfirm = scheduled
    present = true
    firstConfirm!!()
    assertEquals(0, down)
    present = false
    scheduled = null
    gate.onLost(network)
    scheduled!!()
    assertEquals(1, down)
  }
}
