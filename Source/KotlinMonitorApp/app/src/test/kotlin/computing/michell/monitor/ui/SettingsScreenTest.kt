package computing.michell.monitor.ui

/* Settings status and error copy (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.connection.ReconnectingBanner
import org.junit.Assert.assertEquals
import org.junit.Test

class SettingsScreenTest {
  @Test
  fun linkCaptionNamesTheSocketInWords() {
    assertEquals("Not connected", settingsLinkCaption(LinkPhase.Idle, false))
    assertEquals("Connecting", settingsLinkCaption(LinkPhase.Connecting, true))
    assertEquals("Connected", settingsLinkCaption(LinkPhase.Live, false))
    assertEquals("Not connected", settingsLinkCaption(LinkPhase.Live, true))
    assertEquals("Not connected", settingsLinkCaption(LinkPhase.Disconnected, true))
    assertEquals("Not connected", settingsLinkCaption(LinkPhase.Paused, true))
  }

  @Test
  fun progressBannersAreNotInlineErrors() {
    assertEquals("", settingsErrorText(""))
    assertEquals("", settingsErrorText(ConnectingBanner))
    assertEquals("", settingsErrorText(ReconnectingBanner))
    assertEquals("Connection refused.", settingsErrorText("Connection refused."))
  }
}
