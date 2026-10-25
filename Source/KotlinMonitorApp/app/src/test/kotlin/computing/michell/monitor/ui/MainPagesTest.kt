package computing.michell.monitor.ui

/* Main swipe order: Conversation, then Plan (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MainPagesTest {
  @Test
  fun swipeAdvancesFromConversationToPlan() {
    assertEquals(listOf(AppTab.Conversation, AppTab.Plan), MainTabs)
    assertEquals(0, pageForTab(AppTab.Conversation))
    assertEquals(1, pageForTab(AppTab.Plan))
    assertEquals(AppTab.Plan, tabAfterSwipe(pageForTab(AppTab.Plan), AppTab.Conversation))
    assertEquals(AppTab.Conversation, tabAfterSwipe(pageForTab(AppTab.Conversation), AppTab.Plan))
  }

  @Test
  fun settlingOnTheCurrentPageDoesNotReselect() {
    assertNull(tabAfterSwipe(0, AppTab.Conversation))
    assertNull(tabAfterSwipe(1, AppTab.Plan))
  }

  @Test
  fun outOfRangePageStaysOnConversation() {
    assertEquals(AppTab.Conversation, tabForPage(-1))
    assertEquals(AppTab.Conversation, tabForPage(MainTabs.size))
    assertEquals(AppTab.Conversation, tabAfterSwipe(9, AppTab.Plan))
  }

  @Test
  fun headerShowsConnectedOnlyWhileTheLinkIsLive() {
    assertEquals("Connected", shellConnectionCaption(true, false, "Host closed"))
    assertEquals("Connecting", shellConnectionCaption(false, true, ""))
    assertEquals("Reconnecting", shellConnectionCaption(false, true, "Reconnecting"))
    assertEquals("Host closed", shellConnectionCaption(false, false, "Host closed"))
    assertEquals("Not connected", shellConnectionCaption(false, false, ""))
  }
}
