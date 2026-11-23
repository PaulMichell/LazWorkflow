package computing.michell.monitor.ui

/* Useful image requests and the decoded-pixel cache (c) 2026 Michell Computing.

   A picture the desktop announced has no file until the phone asks for it with
   image_get. The board says which pictures still have no file. The tracker
   keeps the requests on this link inside the phone's assembly limit. */

import computing.michell.monitor.data.StoredImagesBlockId
import computing.michell.monitor.protocol.MonitorLimits
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

/**
 * Pictures on the board with no stored file, as image_get requests. The live turn comes first, then stored turns
 * newest first, so the end of the conversation arrives before older history. Ids in [skip] are left out, ids in
 * [skipLive] are left out of turns with an index below 0, and no more than [room] requests are returned. The note of
 * pictures from before schema 5 names no turn, so the desktop could not find them; those are not asked for.
 */
fun boardImageFetches(
  hostGeneration: Int,
  turns: List<WireTurn>,
  live: WireTurn?,
  skip: Set<String>,
  room: Int,
  skipLive: Set<String> = emptySet()
): List<ImageRequestKey> {
  if (room <= 0) return emptyList()
  val keys = ArrayList<ImageRequestKey>()
  val seen = HashSet<String>()
  for (turn in listOfNotNull(live) + turns.sortedByDescending { turn -> turn.turnIndex }) {
    for (block in turn.blocks) {
      if (block.blockId == StoredImagesBlockId) continue
      for (image in block.images) {
        if (image.id.isEmpty() || image.missing || image.displayPath.isNotEmpty()) continue
        if (image.id in skip || (turn.turnIndex < 0 && image.id in skipLive)) continue
        if (!seen.add(image.id)) continue
        keys += ImageRequestKey(hostGeneration, turn.turnIndex, image.id)
        if (keys.size >= room) return keys
      }
    }
  }
  return keys
}

private data class AskedImage(val atMs: Long, val turnIndex: Int)

/**
 * The image_get requests on the current link. An answer settles an id, so it is not asked again. An unavailable
 * reply settles it too, unless it was asked for on the live turn: the live turn's rows change while it runs, so that
 * id is asked again once it shows on a stored turn. A request with no answer inside the assembly lifetime may be
 * asked again. A dropped link forgets what was in flight, because the replies went with the socket. No more than
 * [limit] requests are in flight.
 */
class ImageFetchTracker(
  private val limit: Int = MonitorLimits.MaxOpenImageAssemblies,
  private val lifetimeMs: Long = MonitorLimits.ImageAssemblyTtlMs
) {
  private val asked = HashMap<String, AskedImage>()
  private val settled = HashSet<String>()
  private val refusedLive = HashSet<String>()

  val inFlight: Set<String> get() = asked.keys.toSet()

  fun next(hostGeneration: Int, board: BoardContent, nowMs: Long): List<ImageRequestKey> {
    asked.entries.removeAll { entry -> nowMs - entry.value.atMs >= lifetimeMs }
    val keys = boardImageFetches(
      hostGeneration, board.turns, board.live, asked.keys + settled, limit - asked.size, refusedLive
    )
    for (key in keys) asked[key.imageId] = AskedImage(nowMs, key.turnIndex)
    return keys
  }

  fun settle(imageId: String) {
    asked.remove(imageId)
    refusedLive.remove(imageId)
    settled += imageId
  }

  /** The desktop sent image_unavailable. A refusal for the live turn waits for the stored turn. */
  fun refuse(imageId: String) {
    val request = asked.remove(imageId)
    if (request != null && request.turnIndex < 0) refusedLive += imageId else settle(imageId)
  }

  /** The assembly gave up on this id. It may be asked for again. */
  fun release(imageId: String) {
    asked.remove(imageId)
  }

  fun linkDropped() {
    asked.clear()
  }

  fun reset() {
    asked.clear()
    settled.clear()
    refusedLive.clear()
  }
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
