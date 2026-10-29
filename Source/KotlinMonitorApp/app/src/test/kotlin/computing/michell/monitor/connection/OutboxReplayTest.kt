package computing.michell.monitor.connection

/* Outbox replay rules without a socket (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Test

class OutboxReplayTest {
  @Test
  fun unknownIsResentUnlessThePromptWasAlreadyHeld() {
    assertEquals(ReplayAction.Resend, replayAction("stop", OutboxOpen, "unknown"))
    assertEquals(ReplayAction.Resend, replayAction("send", OutboxOpen, "unknown"))
    assertEquals(ReplayAction.Wait, replayAction("send", OutboxOpen, OutboxAccepted))
    assertEquals(ReplayAction.Wait, replayAction("send", OutboxQueued, OutboxQueued))
    assertEquals(ReplayAction.Clear, replayAction("send", OutboxAccepted, OutboxDone))
    assertEquals(ReplayAction.Clear, replayAction("set_mode", OutboxQueued, OutboxRejected))
    assertEquals(ReplayAction.OfferRetry, replayAction("send", OutboxAccepted, "unknown"))
    assertEquals(ReplayAction.OfferRetry, replayAction("steer", OutboxQueued, "unknown"))
    assertEquals(ReplayAction.Resend, replayAction("stop", OutboxAccepted, "unknown"))
  }
}
