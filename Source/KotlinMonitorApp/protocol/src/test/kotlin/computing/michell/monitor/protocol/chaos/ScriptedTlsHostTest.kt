package computing.michell.monitor.protocol.chaos

/* The scripted host speaks TLS and keeps a fixed fault seed (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Test

class ScriptedTlsHostTest {
  @Test
  fun faultsStayOnTheFixedSeed() {
    val first = chaosFaults(ChaosSeed, 7)
    val again = chaosFaults(ChaosSeed, 7)
    assertEquals(first, again)
    assertEquals(ChaosIterations, 1000)
  }
}
