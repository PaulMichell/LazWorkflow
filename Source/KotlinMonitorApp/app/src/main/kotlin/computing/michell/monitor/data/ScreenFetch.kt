package computing.michell.monitor.data

/* Which bodies to ask for, and no others (c) 2026 Michell Computing.

   The running block owns one slot. A plan fetch may use the other. At the
   head, older bodies are not requested. While browsing, history fills only
   the visible turns, in the slots that remain. A return to the head drops
   that demand. A newer revision drops the previous flight and asks again.
   An applied body frees the slot before the board watch republishes. */

import computing.michell.monitor.protocol.WireTurn

const val FetchCap = 2

sealed class FetchGrant {
  data class Block(val fetch: BlockFetch, val open: Boolean) : FetchGrant()
  data class Turn(val index: Int) : FetchGrant()
  data class Plan(val path: String, val offset: Long, val revision: String) : FetchGrant()
}

private data class OwedBlock(
  val fetch: BlockFetch,
  val turnIndex: Int,
  val open: Boolean
)

class ScreenFetch(initiallyConnected: Boolean = true) {
  private var connected = initiallyConnected

  /** Disconnect releases socket-owned fetch slots; reconnect retries from the stored board. */
  fun setConnected(value: Boolean): List<FetchGrant> {
    connected = value
    if (!value) {
      inFlight.clear()
      planFlying = false
    }
    return release()
  }

  private val owed = LinkedHashMap<String, OwedBlock>()
  private val inFlight = LinkedHashSet<String>()
  /** Applied, and not yet cleared by a board that no longer marks the block deferred. */
  private val applied = HashSet<String>()
  private val knownTurns = HashSet<Int>()
  private val stale = HashSet<String>()
  private var visible = emptySet<Int>()
  private var followingHead = true
  private var planPath = ""
  private var planRevision = ""
  private var planOffset = 0L
  private var planWanted = false
  private var planFlying = false
  private var planHeld = false

  fun offerRepair(fetch: BlockFetch, open: Boolean): List<FetchGrant> {
    val previous = owed[fetch.blockId]
    val revised = previous != null && fetch.requestId.isNotEmpty() && previous.fetch.requestId != fetch.requestId
    if (revised) {
      applied.remove(fetch.blockId)
      inFlight.remove(fetch.blockId)
    }
    val row = OwedBlock(fetch, previous?.turnIndex ?: -1, open || previous?.open == true)
    owed[fetch.blockId] = row
    // Baselines may announce thousands of repairs before Room publishes their turn indices.
    // These cannot be granted yet; avoid scanning the growing board for each announcement.
    // A revision of a flight already granted must be asked again.
    if (!revised && !row.open && row.turnIndex !in wantedTurns()) return emptyList()
    return release()
  }

  /** Deferred blocks are owed. A hash match is not deferred, so it is not fetched. */
  fun replaceBoard(conversationId: String, turns: List<WireTurn>, live: WireTurn?): List<FetchGrant> {
    knownTurns.clear()
    val still = HashSet<String>()
    val rows = if (live == null) turns else turns + live
    for (turn in rows) {
      knownTurns += turn.turnIndex
      val openBlockId = if (live != null && turn.id == live.id) {
        turn.blocks.lastOrNull { it.running }?.blockId ?: turn.blocks.lastOrNull()?.blockId
      } else null
      for (block in turn.blocks) {
        if (block.blockId.isEmpty()) continue
        if (block.blockId in applied) {
          if (!block.deferred) applied.remove(block.blockId)
          continue
        }
        if (!block.deferred) continue
        still += block.blockId
        val previous = owed[block.blockId]
        val fetch = previous?.fetch?.takeIf { row -> row.conversationId.isNotEmpty() }
          ?: BlockFetch(conversationId, block.blockId, 0, "", "bg-" + block.blockId)
        owed[block.blockId] = OwedBlock(fetch, turn.turnIndex, block.blockId == openBlockId || block.running)
      }
    }
    val gone = owed.keys.filter { id -> id !in still && id !in inFlight }
    for (id in gone) owed.remove(id)
    val arrived = inFlight.filter { key ->
      val index = key.removePrefix("turn:").toIntOrNull()
      (key.startsWith("turn:") && index != null && index in knownTurns) ||
        (!key.startsWith("turn:") && !key.startsWith("plan:") && key !in still)
    }
    for (key in arrived) inFlight.remove(key)
    return release()
  }

  /** Head demand asks for nothing older. Browsing replaces the previous viewport. */
  /** A different host, conversation or stream owns none of the fetches already in flight. */
  fun invalidate(): List<FetchGrant> {
    owed.clear()
    inFlight.clear()
    stale.clear()
    applied.clear()
    knownTurns.clear()
    visible = emptySet()
    planWanted = false
    planFlying = false
    planHeld = false
    return emptyList()
  }

  fun noteReading(atHead: Boolean, indices: Set<Int>): List<FetchGrant> {
    followingHead = atHead
    visible = if (atHead) emptySet() else indices
    if (atHead) dropHistoryDemand() else dropUnwanted()
    return release()
  }

  fun noteVisible(indices: Set<Int>): List<FetchGrant> = noteReading(false, indices)

  fun staleBlockIds(): Set<String> {
    return stale.filter { key -> !key.startsWith("turn:") && !key.startsWith("plan:") }.toSet()
  }

  fun staleTurnIndices(): Set<Int> {
    return stale.mapNotNull { key ->
      if (key.startsWith("turn:")) key.removePrefix("turn:").toIntOrNull() else null
    }.toSet()
  }

  fun notePlan(path: String, revision: String, filePresent: Boolean, fileRevision: String, fileLength: Long, showing: Boolean): List<FetchGrant> {
    if (planHeld) return emptyList()
    planPath = path
    planRevision = revision
    planWanted = showing && path.isNotEmpty() && revision.isNotEmpty() && (!filePresent || fileRevision != revision)
    planOffset = if (filePresent && fileRevision == revision) fileLength else 0L
    if (!planWanted) planFlying = false
    return release()
  }

  fun cancelPlan() {
    planWanted = false
    planFlying = false
    planHeld = true
    inFlight.remove(planKey())
  }

  fun continuePlan(path: String, revision: String, filePresent: Boolean, fileRevision: String, fileLength: Long): List<FetchGrant> {
    planHeld = false
    return notePlan(path, revision, filePresent, fileRevision, fileLength, true)
  }

  fun isFlying(key: String): Boolean = key in inFlight

  fun finished(key: String): List<FetchGrant> {
    inFlight.remove(key)
    owed.remove(key)
    if (key == planKey()) planFlying = false
    return release()
  }

  /**
   * The fetch completed. The slot is free even if the board still shows the block deferred.
   * A complete body is not asked for again until the board clears that mark, or a new revision arrives.
   */
  fun noteApplied(blockId: String, complete: Boolean): List<FetchGrant> {
    if (blockId.isEmpty()) return emptyList()
    inFlight.remove(blockId)
    if (complete) {
      applied += blockId
      owed.remove(blockId)
    }
    return release()
  }

  fun notePlanDropped() {
    planFlying = false
    inFlight.remove(planKey())
  }

  private fun planKey(): String = "plan:" + planPath

  private fun dropHistoryDemand() {
    val history = inFlight.filter { key -> historyKey(key) }
    for (key in history) {
      inFlight.remove(key)
      stale += key
    }
  }

  /** A rapid scroll keeps only the turns now on screen. The cap is not a queue of old viewports. */
  private fun dropUnwanted() {
    val wanted = wantedTurns()
    val gone = inFlight.filter { key ->
      if (!historyKey(key)) return@filter false
      val index = turnIndexOf(key)
      index == null || index !in wanted
    }
    for (key in gone) {
      inFlight.remove(key)
      stale += key
    }
    stale.removeAll { key ->
      val index = turnIndexOf(key)
      index != null && index in wanted
    }
  }

  private fun historyKey(key: String): Boolean {
    if (key.startsWith("plan:")) return false
    return owed[key]?.open != true
  }

  private fun turnIndexOf(key: String): Int? {
    if (key.startsWith("turn:")) return key.removePrefix("turn:").toIntOrNull()
    val row = owed[key] ?: return null
    if (row.turnIndex < 0) return null
    return row.turnIndex
  }

  private fun release(): List<FetchGrant> {
    if (!connected) return emptyList()
    val grants = ArrayList<FetchGrant>()
    val open = owed.values.firstOrNull { row -> row.open && row.fetch.blockId !in inFlight }
    if (open != null) {
      makeRoomForOpen()
      if (free() > 0) grants += take(open)
    }
    if (planWanted && !planFlying && free() == 0 && openWaiting().not()) {
      val history = inFlight.firstOrNull { key -> !key.startsWith("plan:") && owed[key]?.open != true }
      if (history != null) inFlight.remove(history)
    }
    if (free() == 0) return grants
    if (planWanted && !planFlying && free() > 0 && openWaiting().not()) {
      planFlying = true
      inFlight += planKey()
      grants += FetchGrant.Plan(planPath, planOffset, planRevision)
    }
    val wanted = wantedTurns()
    val history = owed.values.filter { row -> !row.open && row.fetch.blockId !in inFlight && row.turnIndex in wanted }.asReversed()
    for (row in history) {
      if (free() <= reserved()) break
      grants += take(row)
    }
    for (index in visible.sorted()) {
      if (index in knownTurns) continue
      val key = "turn:$index"
      if (key in inFlight) continue
      if (free() <= reserved()) break
      inFlight += key
      grants += FetchGrant.Turn(index)
    }
    return grants
  }

  private fun take(row: OwedBlock): FetchGrant.Block {
    inFlight += row.fetch.blockId
    return FetchGrant.Block(row.fetch, row.open)
  }

  /** History yields first. The plan yields only if it is sitting in the running block's slot. */
  private fun makeRoomForOpen() {
    if (free() > 0) return
    val history = inFlight.firstOrNull { key -> !key.startsWith("plan:") && owed[key]?.open != true }
    val victim = history ?: inFlight.firstOrNull { key -> key.startsWith("plan:") } ?: return
    inFlight.remove(victim)
    if (victim == planKey()) planFlying = false
  }

  private fun free(): Int = (FetchCap - inFlight.size).coerceAtLeast(0)

  private fun openWaiting(): Boolean = owed.values.any { row -> row.open && row.fetch.blockId !in inFlight }

  private fun reserved(): Int {
    var slots = 0
    if (openWaiting()) slots += 1
    if (planWanted && !planFlying) slots += 1
    return slots
  }

  private fun wantedTurns(): Set<Int> {
    if (followingHead || visible.isEmpty()) return emptySet()
    return visible
  }
}
