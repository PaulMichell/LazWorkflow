package computing.michell.monitor.ui

/* Prompt status and caret without a device (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.dictation.DictationListeningMessage
import computing.michell.monitor.dictation.DictationUnavailableMessage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PromptStatusTest {
  @Test
  fun dictationStatusReplacesTheRightHandItem() {
    assertEquals(DictationListeningMessage, promptActivityRight("Thinking… 0:04", true, "No speech recognised."))
    assertEquals("Ready", promptActivityRight("Ready", false, ""))
    assertEquals(DictationUnavailableMessage, promptActivityRight("Ready", false, DictationUnavailableMessage))
    assertEquals("Thinking…", promptActivityRight("Thinking…", false, DictationUnavailableMessage))
    assertEquals("No speech recognised.", promptActivityRight("Ready", false, "No speech recognised."))
    assertEquals("Microphone permission is required.", promptActivityRight("Thinking…", false, "Microphone permission is required."))
    val field = promptFieldValue("Explain indexes.", 4, 80)
    assertEquals("Explain indexes.", field.text)
    assertEquals(4, field.selection.start)
    assertEquals("Explain indexes.".length, field.selection.end)
  }

  @Test
  fun aLiveIdleLinkCanSendBeforeStatusSetsCanSend() {
    val idle = emptyView()
    assertFalse(idle.canSend)
    assertTrue(sendActionEnabled(idle, false, LinkPhase.Live, false))
    assertTrue(newConversationEnabled(idle, false, LinkPhase.Live, false))
    assertFalse(sendActionEnabled(idle, true, LinkPhase.Live, false))
    assertFalse(sendActionEnabled(idle, false, LinkPhase.Connecting, false))
    val running = idle.copy(sending = true, busy = true, canSend = false)
    assertFalse(sendActionEnabled(running, false, LinkPhase.Live, false))
    assertFalse(newConversationEnabled(running, false, LinkPhase.Live, false))
    assertTrue(sendActionEnabled(idle.copy(canSteer = true), false, LinkPhase.Live, false))
  }

  @Test
  fun syncingKeepsSendAndNewAvailable() {
    val idle = emptyView()
    assertTrue(linkSyncing(LinkPhase.Connecting, true, true, false))
    assertFalse(linkSyncing(LinkPhase.Disconnected, true, true, false))
    assertFalse(linkSyncing(LinkPhase.Connecting, true, false, false))
    assertTrue(sendActionEnabled(idle, true, LinkPhase.Connecting, false, true))
    assertTrue(newConversationEnabled(idle, true, LinkPhase.Connecting, false, true))
    val running = idle.copy(sending = true, busy = true, canSend = false)
    assertFalse(sendActionEnabled(running, true, LinkPhase.Connecting, false, true))
    assertFalse(newConversationEnabled(running, true, LinkPhase.Connecting, false, true))
    assertFalse(sendActionEnabled(idle, true, LinkPhase.Disconnected, false, false))
    val thinking = emptyView().copy(sending = true, phase = "Thinking…")
    assertEquals("Thinking…", activityCaption(thinking, false, "", 0L, 5_000L))
    assertEquals("Thinking… 0:04", activityCaption(thinking, false, "", 1_000L, 5_000L))
  }

  @Test
  fun aPromptWaitingForTheLinkStillShowsBusy() {
    assertEquals("", heldPromptActivity(false, LinkPhase.Disconnected))
    assertEquals(PhaseConnecting, heldPromptActivity(true, LinkPhase.Connecting))
    assertEquals(WaitingForDesktop, heldPromptActivity(true, LinkPhase.Disconnected))
    // A link that is coming back passes as syncing, so Send stays up while it is down.
    assertTrue(sendActionEnabled(emptyView(), true, LinkPhase.Disconnected, false, true))
  }

  @Test
  fun creditPopupUsesTheDesktopCreditsBody() {
    assertEquals(CreditUsageUnknown, creditUsageBody("", ""))
    assertEquals(CreditUsageUnknown, creditUsageBody("   ", "\n"))
    assertEquals("Credits used: 42%", creditUsageBody("Credits used: 42%", ""))
    assertEquals("Weekly limit: 42%", creditUsageBody("", "Weekly limit: 42%"))
    assertEquals(
      "Credits used: 42%\n\nWeekly limit: 42%\nNext reset: October 30, 18:00",
      creditUsageBody("Credits used: 42%", "Weekly limit: 42%\nNext reset: October 30, 18:00")
    )
  }

  @Test
  fun microphoneAskDoesNotLoopADeniedDialog() {
    assertEquals(MicrophoneAsk.Start, microphoneAsk(true, false, false))
    assertEquals(MicrophoneAsk.RequestPermission, microphoneAsk(false, false, false))
    assertEquals(MicrophoneAsk.RequestPermission, microphoneAsk(false, true, true))
    assertEquals(MicrophoneAsk.ExplainSettings, microphoneAsk(false, true, false))
    assertEquals(MicrophoneRequiredMessage, promptActivityRight("Ready", false, MicrophoneRequiredMessage))
    assertEquals(MicrophoneSettingsMessage, promptActivityRight("Ready", false, MicrophoneSettingsMessage))
  }
}
