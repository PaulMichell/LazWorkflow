package computing.michell.monitor

/* Screen-off hold is a recorded result, not an assumption (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenHoldTest {
  @Test
  fun screenOffThenOnStopKeepsAGrantedHold() {
    val hold = harness(start = true)
    val decision = hold.screen.onScreenOff(demand = true)
    assertEquals(HoldActivation.Starting, decision.activation)
    assertEquals("", decision.notice)
    assertEquals(1, hold.starts)
    val stopped = hold.screen.onStop()
    assertEquals(HoldActivation.Starting, stopped.activation)
    assertFalse(stopped.closeLink)
    assertEquals(0, hold.stops)
    hold.screen.onPlatformResult(true)
    assertEquals(HoldActivation.Active, hold.screen.activation)
    assertEquals(0, hold.stops)
  }

  @Test
  fun aRefusedHoldIsNotAnAuthenticationFailure() {
    val hold = harness(start = false)
    val decision = hold.screen.onScreenOff(demand = true)
    assertEquals(HoldActivation.Failed, decision.activation)
    assertEquals(HoldNotGrantedNotice, decision.notice)
    assertNotEquals("Host closed", decision.notice)
    assertNotEquals("The desktop did not accept this phone.", decision.notice)
    assertTrue(decision.notice.contains("not a desktop"))
    assertEquals(0, hold.stops)
  }

  @Test
  fun onStopThenScreenOffStartsTheHoldAfterTheUserLeft() {
    val hold = harness(start = true)
    hold.screen.onStop()
    assertEquals(0, hold.stops)
    val decision = hold.screen.onScreenOff(demand = true)
    assertEquals(HoldActivation.Starting, decision.activation)
    assertEquals(1, hold.starts)
  }

  @Test
  fun screenOnAndDemandEndAndDisconnectReleaseTheHold() {
    val hold = harness(start = true)
    hold.screen.onScreenOff(demand = true)
    hold.screen.onPlatformResult(true)
    hold.screen.onScreenOn()
    assertEquals(HoldActivation.Inactive, hold.screen.activation)
    assertEquals(1, hold.stops)
    hold.screen.onScreenOff(demand = true)
    hold.screen.onPlatformResult(true)
    hold.screen.onDemandEnded()
    assertEquals(HoldActivation.Inactive, hold.screen.activation)
    hold.screen.onScreenOff(demand = true)
    hold.screen.onPlatformResult(true)
    hold.screen.onDisconnect()
    assertEquals(HoldActivation.Inactive, hold.screen.activation)
    assertEquals(3, hold.stops)
  }

  @Test
  fun aFailedResultAfterOnStopClosesTheLink() {
    val hold = harness(start = true)
    hold.screen.onScreenOff(demand = true)
    hold.screen.onStop()
    val failed = hold.screen.onPlatformResult(false)
    assertEquals(HoldActivation.Failed, failed.activation)
    assertEquals(HoldNotGrantedNotice, failed.notice)
    assertTrue(failed.closeLink)
  }

  @Test
  fun aNewProcessDoesNotInheritThePreviousHold() {
    val hold = harness(start = true)
    hold.screen.onScreenOff(demand = true)
    hold.screen.onPlatformResult(true)
    val fresh = hold.screen.recreated()
    assertEquals(HoldActivation.Inactive, fresh.activation)
    assertEquals("", fresh.notice)
  }

  @Test
  fun screenOffWithoutDemandDoesNotStartTheService() {
    val hold = harness(start = true)
    val decision = hold.screen.onScreenOff(demand = false)
    assertEquals(HoldActivation.Inactive, decision.activation)
    assertEquals(0, hold.starts)
  }
}

private class HoldHarness(
  val screen: ScreenHold,
  val counts: Counts
) {
  val starts: Int get() = counts.starts
  val stops: Int get() = counts.stops
}

private class Counts(var starts: Int = 0, var stops: Int = 0)

private fun harness(start: Boolean): HoldHarness {
  val counts = Counts()
  val screen = ScreenHold(
    start = {
      counts.starts += 1
      start
    },
    stop = { counts.stops += 1 }
  )
  return HoldHarness(screen, counts)
}
