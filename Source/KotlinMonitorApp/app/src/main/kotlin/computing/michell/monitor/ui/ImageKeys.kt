package computing.michell.monitor.ui

/* Bitmap cache keys the conversation screen still uses (c) 2026 Michell Computing. */

import computing.michell.monitor.ui.model.WireImage
import computing.michell.monitor.ui.model.WireTurn

fun imageCachePrefix(hostGeneration: Int, imageId: String): String {
  return hostGeneration.toString() + "\u0000" + imageId + "\u0000"
}

fun turnImageIds(turn: WireTurn): List<String> {
  val ids = ArrayList<String>()
  fun add(image: WireImage) {
    if (image.id.isNotEmpty() && !image.missing && image.id !in ids) ids += image.id
  }
  for (image in turn.images) add(image)
  for (block in turn.blocks) for (image in block.images) add(image)
  return ids
}
