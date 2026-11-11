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
      onAbsent = {},
      wifiPresent = { true },
      confirmLater = { scheduled = it }
    )
    gate.activate()
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
      onAbsent = {},
      wifiPresent = { present },
      confirmLater = { scheduled = it }
    )
    gate.activate()
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

  @Test
  fun aStillListedIdentityKeepsItsBind() {
    val step = callbackLoss("wifi-a", LanRoute("wifi-a"))
    assertNull(step.forget)
    assertEquals(LanRoute("wifi-a"), step.selected)
  }

  @Test
  fun aGoneIdentityIsForgottenAndTheRemainingWifiIsSelected() {
    val step = callbackLoss("wifi-a", LanRoute("wifi-b"))
    assertEquals("wifi-a", step.forget)
    assertEquals(LanRoute("wifi-b"), step.selected)
  }

  @Test
  fun noListedWifiForgetsTheLostIdentity() {
    val step = callbackLoss("wifi-a", null)
    assertEquals("wifi-a", step.forget)
    assertNull(step.selected)
  }
}
