package computing.michell.monitor.ui

/* Useful image requests and the decoded-pixel cache (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.WireImage
import computing.michell.monitor.protocol.WireTurn

/** Two full-size decoded images. A later insert evicts the oldest. Not a wire limit. */
const val DecodedImageCacheBytes = MaxDecodedBytes * 2

data class ImageRequestKey(val hostGeneration: Int, val turnIndex: Int, val imageId: String)

data class ImageCacheKey(val hostGeneration: Int, val imageId: String, val revision: Int)

fun imageCacheText(key: ImageCacheKey): String {
  return key.hostGeneration.toString() + "\u0000" + key.imageId + "\u0000" + key.revision.toString()
}

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

/** Live turn, reported visible turns, and one snapshot neighbour on either side. */
fun imageTurnsWanted(storedOrder: List<Int>, visible: Set<Int>, liveIndex: Int?): Set<Int> {
  val wanted = linkedSetOf<Int>()
  if (liveIndex != null) wanted += liveIndex
  for (index in visible) {
    if (index < 0) continue
    wanted += index
    val at = storedOrder.indexOf(index)
    if (at > 0) wanted += storedOrder[at - 1]
    if (at >= 0 && at + 1 < storedOrder.size) wanted += storedOrder[at + 1]
  }
  return wanted
}

fun imageRequestKeys(
  hostGeneration: Int,
  storedOrder: List<Int>,
  imagesByTurn: Map<Int, List<String>>,
  liveIndex: Int?,
  visible: Set<Int>,
  unavailable: Set<String> = emptySet()
): List<ImageRequestKey> {
  val keys = ArrayList<ImageRequestKey>()
  val seen = HashSet<String>()
  for (index in imageTurnsWanted(storedOrder, visible, liveIndex)) {
    val ids = imagesByTurn[index] ?: continue
    for (imageId in ids) {
      if (imageId in unavailable) continue
      val flight = hostGeneration.toString() + ":" + index.toString() + ":" + imageId
      if (!seen.add(flight)) continue
      keys += ImageRequestKey(hostGeneration, index, imageId)
    }
  }
  return keys
}

private data class ImageCacheEntry(val key: ImageCacheKey, val turnIndex: Int, val bytes: Long)

class ImagePixelCache(private val budgetBytes: Long = DecodedImageCacheBytes) {
  private val entries = linkedMapOf<ImageCacheKey, ImageCacheEntry>()

  val keys: Set<ImageCacheKey> get() = entries.keys.toSet()

  fun insert(
    key: ImageCacheKey,
    turnIndex: Int,
    bytes: Long,
    hostGeneration: Int,
    snapshotTurns: Set<Int>
  ): Set<ImageCacheKey> {
    val removed = mutableSetOf<ImageCacheKey>()
    removed += drop { entry -> entry.key.hostGeneration != hostGeneration || entry.turnIndex !in snapshotTurns }
    if (key.hostGeneration != hostGeneration || turnIndex !in snapshotTurns || bytes <= 0L) {
      entries.remove(key)?.let { removed += key }
      return removed
    }
    entries.remove(key)
    entries[key] = ImageCacheEntry(key, turnIndex, bytes)
    val older = entries.keys.filter { old ->
      old != key && old.hostGeneration == key.hostGeneration && old.imageId == key.imageId
    }
    for (old in older) {
      entries.remove(old)
      removed += old
    }
    removed += evictToBudget()
    return removed
  }

  fun retain(hostGeneration: Int, snapshotTurns: Set<Int>): Set<ImageCacheKey> {
    return drop { entry -> entry.key.hostGeneration != hostGeneration || entry.turnIndex !in snapshotTurns }
  }

  fun reset(): Set<ImageCacheKey> {
    val removed = entries.keys.toSet()
    entries.clear()
    return removed
  }

  private fun evictToBudget(): Set<ImageCacheKey> {
    val removed = mutableSetOf<ImageCacheKey>()
    while (bytes() > budgetBytes && entries.isNotEmpty()) {
      val oldest = entries.keys.first()
      entries.remove(oldest)
      removed += oldest
    }
    return removed
  }

  private fun drop(reject: (ImageCacheEntry) -> Boolean): Set<ImageCacheKey> {
    val gone = entries.filter { (_, entry) -> reject(entry) }.keys.toList()
    for (key in gone) entries.remove(key)
    return gone.toSet()
  }

  private fun bytes(): Long {
    var total = 0L
    for (entry in entries.values) total += entry.bytes
    return total
  }
}
