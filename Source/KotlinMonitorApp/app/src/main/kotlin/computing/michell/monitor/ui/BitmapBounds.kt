package computing.michell.monitor.ui

/* Bitmap bounds before any pixel allocation (c) 2026 Michell Computing. */

const val MaxDecodedLongEdge = 2048
const val DecodedBytesPerPixel = 4

/** ARGB_8888 size of a square at the long-edge cap. This is an app limit, not a wire limit. */
const val MaxDecodedBytes = MaxDecodedLongEdge.toLong() * MaxDecodedLongEdge * DecodedBytesPerPixel

data class BitmapBoundsPlan(
  val allocate: Boolean,
  val sampleSize: Int
)

/**
 * Decides whether a bounds pair may be decoded.
 * A non-positive edge is refused. A later viewport request may sample smaller; it must not raise these caps.
 * sampleSize is a power of two and is meaningful only when allocate is true.
 */
fun bitmapBoundsPlan(width: Int, height: Int): BitmapBoundsPlan {
  if (width <= 0 || height <= 0) return BitmapBoundsPlan(false, 0)
  var sample = 1
  while (true) {
    val sampledWidth = width / sample
    val sampledHeight = height / sample
    if (sampledWidth <= 0 || sampledHeight <= 0) return BitmapBoundsPlan(false, 0)
    val bytes = decodedBytes(sampledWidth, sampledHeight)
    if (bytes != null) {
      val longEdge = if (sampledWidth >= sampledHeight) sampledWidth else sampledHeight
      if (longEdge <= MaxDecodedLongEdge && bytes <= MaxDecodedBytes) return BitmapBoundsPlan(true, sample)
    }
    if (sample > Int.MAX_VALUE / 2) return BitmapBoundsPlan(false, 0)
    sample *= 2
  }
}

/** Four bytes per pixel. Returns null when the multiply would overflow. */
fun decodedBytes(width: Int, height: Int): Long? {
  if (width <= 0 || height <= 0) return null
  val area = width.toLong() * height.toLong()
  if (area > Long.MAX_VALUE / DecodedBytesPerPixel) return null
  return area * DecodedBytesPerPixel
}
