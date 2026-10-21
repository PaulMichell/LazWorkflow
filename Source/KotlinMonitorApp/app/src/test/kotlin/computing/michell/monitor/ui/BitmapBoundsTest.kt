package computing.michell.monitor.ui

/* Bitmap sample decision without a device or BitmapFactory (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BitmapBoundsTest {
  @Test
  fun smallImageIsUnchanged() {
    val plan = bitmapBoundsPlan(64, 48)
    assertTrue(plan.allocate)
    assertEquals(1, plan.sampleSize)
    val atCap = bitmapBoundsPlan(MaxDecodedLongEdge, 100)
    assertTrue(atCap.allocate)
    assertEquals(1, atCap.sampleSize)
    assertEquals(MaxDecodedBytes, decodedBytes(MaxDecodedLongEdge, MaxDecodedLongEdge))
  }

  @Test
  fun hugeBoundsAreSampledInsideTheCaps() {
    val plan = bitmapBoundsPlan(10_000, 8_000)
    assertTrue(plan.allocate)
    assertTrue(plan.sampleSize > 1)
    assertEquals(0, plan.sampleSize and (plan.sampleSize - 1))
    val width = 10_000 / plan.sampleSize
    val height = 8_000 / plan.sampleSize
    assertTrue(width > 0 && height > 0)
    assertTrue(maxOf(width, height) <= MaxDecodedLongEdge)
    val area = width.toLong() * height.toLong()
    assertTrue(area <= Long.MAX_VALUE / DecodedBytesPerPixel)
    assertTrue(area * DecodedBytesPerPixel <= MaxDecodedBytes)
    val edge = bitmapBoundsPlan(4096, 2048)
    assertTrue(edge.allocate)
    assertEquals(2, edge.sampleSize)
  }

  @Test
  fun viewWidthSamplesDownWithoutRaisingTheCap() {
    val native = bitmapBoundsPlan(1600, 400)
    assertEquals(1, native.sampleSize)
    val fitted = bitmapBoundsPlan(1600, 400, 100)
    assertTrue(fitted.allocate)
    assertTrue(fitted.sampleSize > native.sampleSize)
    assertTrue(1600 / fitted.sampleSize <= 100)
    val raised = bitmapBoundsPlan(10_000, 8_000, 10_000)
    val capped = bitmapBoundsPlan(10_000, 8_000)
    assertEquals(capped.sampleSize, raised.sampleSize)
    assertTrue(maxOf(10_000 / raised.sampleSize, 8_000 / raised.sampleSize) <= MaxDecodedLongEdge)
  }

  @Test
  fun zeroDimensionIsRefused() {
    assertFalse(bitmapBoundsPlan(0, 100).allocate)
    assertFalse(bitmapBoundsPlan(100, 0).allocate)
    assertFalse(bitmapBoundsPlan(-1, 40).allocate)
    assertFalse(bitmapBoundsPlan(2049, 1).allocate)
  }

  @Test
  fun overflowingBoundsAreNotMultipliedAsInts() {
    assertNull(decodedBytes(Int.MAX_VALUE, Int.MAX_VALUE))
    val plan = bitmapBoundsPlan(Int.MAX_VALUE, Int.MAX_VALUE)
    if (!plan.allocate) return
    assertTrue(plan.sampleSize > 1)
    val width = Int.MAX_VALUE / plan.sampleSize
    val height = Int.MAX_VALUE / plan.sampleSize
    assertTrue(width > 0 && height > 0)
    assertTrue(maxOf(width, height) <= MaxDecodedLongEdge)
    val area = width.toLong() * height.toLong()
    assertTrue(area <= Long.MAX_VALUE / DecodedBytesPerPixel)
    assertTrue(area * DecodedBytesPerPixel <= MaxDecodedBytes)
  }
}
