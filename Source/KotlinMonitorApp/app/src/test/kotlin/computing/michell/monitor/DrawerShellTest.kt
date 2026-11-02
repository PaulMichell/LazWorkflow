package computing.michell.monitor

/* Drawer open and scrim-strip rules (c) 2026 Michell Computing. */

import computing.michell.monitor.ui.AppTab
import computing.michell.monitor.ui.menuClosesOnLeftSwipe
import computing.michell.monitor.ui.menuEdgeSwipeEnabled
import computing.michell.monitor.ui.menuOpensOnRightEdgeSwipe
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DrawerShellTest {
  @Test
  fun approvalBlocksTheOnlyOpenGesture() {
    assertTrue(menuMayOpenDrawer(false))
    assertFalse(menuMayOpenDrawer(true))
  }

  @Test
  fun backClosesTheDrawerWhileItIsStillSliding() {
    assertTrue(drawerConsumesBack(false, true))
    assertTrue(drawerConsumesBack(true, false))
    assertFalse(drawerConsumesBack(false, false))
  }

  @Test
  fun aLeftSwipeClosesTheMenu() {
    assertTrue(menuClosesOnLeftSwipe(-48f, 48f))
    assertTrue(menuClosesOnLeftSwipe(-120f, 48f))
    assertFalse(menuClosesOnLeftSwipe(-47f, 48f))
    assertFalse(menuClosesOnLeftSwipe(80f, 48f))
    assertFalse(menuClosesOnLeftSwipe(-80f, 0f))
  }

  @Test
  fun aLeftEdgeSwipeOpensTheMenuOnlyOnConversation() {
    assertTrue(menuEdgeSwipeEnabled(AppTab.Conversation, false))
    assertFalse(menuEdgeSwipeEnabled(AppTab.Plan, false))
    assertFalse(menuEdgeSwipeEnabled(AppTab.Conversation, true))
    assertTrue(menuOpensOnRightEdgeSwipe(8f, 32f, 48f, 48f))
    assertTrue(menuOpensOnRightEdgeSwipe(0f, 32f, 80f, 48f))
    assertFalse(menuOpensOnRightEdgeSwipe(40f, 32f, 80f, 48f))
    assertFalse(menuOpensOnRightEdgeSwipe(8f, 32f, 47f, 48f))
    assertFalse(menuOpensOnRightEdgeSwipe(8f, 32f, -60f, 48f))
    assertFalse(menuOpensOnRightEdgeSwipe(8f, 0f, 80f, 48f))
  }

  @Test
  fun backClosesTheCacheListBeforeSettings() {
    assertEquals(SettingsBack.CacheList, settingsBackTarget(true, true, false))
    assertEquals(SettingsBack.Settings, settingsBackTarget(false, true, true))
    assertEquals(SettingsBack.CacheReturn, settingsBackTarget(false, false, true))
    assertEquals(SettingsBack.None, settingsBackTarget(false, false, false))
  }

  @Test
  fun scrimStripIsTheUncoveredPage() {
    assertEquals(120, drawerScrimStripPx(480, 360, 0f))
    assertEquals(300, drawerScrimStripPx(480, 360, -180f))
    assertEquals(0, drawerScrimStripPx(0, 360, 0f))
    assertEquals(0, drawerScrimStripPx(480, 0, 0f))
    assertEquals(0, drawerScrimStripPx(480, 360, Float.NaN))
  }
}
