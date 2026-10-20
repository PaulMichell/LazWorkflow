package computing.michell.monitor.ui

/* Prompt status and caret without a device (c) 2026 Michell Computing. */

import computing.michell.monitor.dictation.DictationListeningMessage
import computing.michell.monitor.dictation.DictationUnavailableMessage
import org.junit.Assert.assertEquals
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
  fun microphoneAskDoesNotLoopADeniedDialog() {
    assertEquals(MicrophoneAsk.Start, microphoneAsk(true, false, false))
    assertEquals(MicrophoneAsk.RequestPermission, microphoneAsk(false, false, false))
    assertEquals(MicrophoneAsk.RequestPermission, microphoneAsk(false, true, true))
    assertEquals(MicrophoneAsk.ExplainSettings, microphoneAsk(false, true, false))
    assertEquals(MicrophoneRequiredMessage, promptActivityRight("Ready", false, MicrophoneRequiredMessage))
    assertEquals(MicrophoneSettingsMessage, promptActivityRight("Ready", false, MicrophoneSettingsMessage))
  }
}
