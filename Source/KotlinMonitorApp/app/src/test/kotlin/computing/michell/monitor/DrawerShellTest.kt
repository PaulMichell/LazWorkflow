package computing.michell.monitor

/* Drawer open and scrim-strip rules (c) 2026 Michell Computing. */

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
  fun scrimStripIsTheUncoveredPage() {
    assertEquals(120, drawerScrimStripPx(480, 360, 0f))
    assertEquals(300, drawerScrimStripPx(480, 360, -180f))
    assertEquals(0, drawerScrimStripPx(0, 360, 0f))
    assertEquals(0, drawerScrimStripPx(480, 0, 0f))
    assertEquals(0, drawerScrimStripPx(480, 360, Float.NaN))
  }
}
