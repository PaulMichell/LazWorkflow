package computing.michell.monitor.ui

/* Busy follows the desktop's turn and plan flags, not a missing history body
   (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.data.applyStateValue
import computing.michell.monitor.data.authoritativeBusy
import computing.michell.monitor.data.authoritativeCanSend
import computing.michell.monitor.protocol.WireBlock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ActivityReconcileTest {
  @Test
  fun aQuietToolAndAPlanGapKeepBusyAndAFinishedHostClearsIt() {
    assertTrue(authoritativeBusy(sending = true, planRunning = false))
    assertTrue(authoritativeBusy(sending = false, planRunning = true))
    assertFalse(authoritativeBusy(sending = false, planRunning = false))
    assertFalse(authoritativeCanSend(true, sending = true, planRunning = false))
    assertFalse(authoritativeCanSend(true, sending = false, planRunning = true))
    assertTrue(authoritativeCanSend(true, sending = false, planRunning = false))

    val quiet = applyStateValue(MonitorUi(), "status", """{"busy":false,"sending":true,"plan_running":false,"can_send":true,"can_steer":true}""")
    assertTrue(quiet.view.busy)
    assertTrue(quiet.view.sending)
    assertFalse(quiet.view.canSend)
    assertTrue(quiet.view.canSteer)
    val tool = WireBlock("tool", "read", "read_file", "read_file", "t1", "", true, true, 0, emptyList())
    assertTrue(settleFinishedTurn(quiet.view, listOf(tool)).busy)

    val gap = applyStateValue(quiet, "status", """{"sending":false,"plan_running":true,"can_send":true}""")
    assertTrue(gap.statusBusy)
    assertTrue(gap.view.planRunning)
    assertFalse(gap.view.canSend)
    val worked = WireBlock("worked", "done", "", "", "", "Worked for 1s", false, true, 0, emptyList())
    assertTrue(settleFinishedTurn(gap.view, listOf(worked)).busy)

    val done = applyStateValue(gap, "status", """{"sending":false,"plan_running":false,"can_send":true,"can_steer":true}""")
    assertFalse(done.view.busy)
    assertFalse(done.view.canSteer)
    assertTrue(done.view.canSend)
    val missing = WireBlock("answer", "b", "", "", "", "Hi", true, true, 0, emptyList())
    val settled = settleFinishedTurn(done.view, listOf(missing))
    assertFalse(settled.busy)
    assertFalse(settled.sending)
    assertTrue(sendActionEnabled(settled, false, LinkPhase.Live, false))
    assertFalse(sendActionEnabled(quiet.view.copy(canSend = true, canSteer = false), false, LinkPhase.Live, false))
    assertTrue(sendActionEnabled(quiet.view, false, LinkPhase.Live, false))
  }
}
