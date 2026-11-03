package computing.michell.monitor.data

/* Which bodies to ask for, and no others (c) 2026 Michell Computing.

   The open block goes first. A plan fetch may use the other slot. History
   fills only what is on screen, plus one turn of prefetch, and only when a
   slot remains. A stored hash that already matches is not asked for again. */

import computing.michell.monitor.protocol.WireTurn

const val FetchCap = 2
const val PrefetchTurns = 1

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

class ScreenFetch {
  private val owed = LinkedHashMap<String, OwedBlock>()
  private val inFlight = LinkedHashSet<String>()
  private val knownTurns = HashSet<Int>()
  private var visible = emptySet<Int>()
  private var planPath = ""
  private var planRevision = ""
  private var planOffset = 0L
  private var planWanted = false
  private var planFlying = false
  private var planHeld = false

  fun offerRepair(fetch: BlockFetch, open: Boolean): List<FetchGrant> {
    owed[fetch.blockId] = OwedBlock(fetch, owed[fetch.blockId]?.turnIndex ?: -1, open || owed[fetch.blockId]?.open == true)
    return release()
  }

  /** Deferred blocks are owed. A hash match is not deferred, so it is not fetched. */
  fun replaceBoard(conversationId: String, turns: List<WireTurn>, live: WireTurn?): List<FetchGrant> {
    knownTurns.clear()
    val still = HashSet<String>()
    val rows = if (live == null) turns else turns + live
    for (turn in rows) {
      knownTurns += turn.turnIndex
      val openTurn = live != null && turn.id == live.id
      for (block in turn.blocks) {
        if (!block.deferred || block.blockId.isEmpty()) continue
        still += block.blockId
        val previous = owed[block.blockId]
        val fetch = previous?.fetch?.takeIf { row -> row.conversationId.isNotEmpty() }
          ?: BlockFetch(conversationId, block.blockId, 0, "", "bg-" + block.blockId)
        owed[block.blockId] = OwedBlock(fetch, turn.turnIndex, openTurn || block.running || previous?.open == true)
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

  fun noteVisible(indices: Set<Int>): List<FetchGrant> {
    visible = indices
    return release()
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

  fun notePlanDropped() {
    planFlying = false
    inFlight.remove(planKey())
  }

  private fun planKey(): String = "plan:" + planPath

  private fun release(): List<FetchGrant> {
    val grants = ArrayList<FetchGrant>()
    val open = owed.values.firstOrNull { row -> row.open && row.fetch.blockId !in inFlight }
    if (open != null && free() > 0) grants += take(open)
    if (planWanted && !planFlying && free() > 0 && openWaiting().not()) {
      planFlying = true
      inFlight += planKey()
      grants += FetchGrant.Plan(planPath, planOffset, planRevision)
    }
    val wanted = wantedTurns()
    val history = owed.values.filter { row -> !row.open && row.fetch.blockId !in inFlight && row.turnIndex in wanted }
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

  private fun free(): Int = (FetchCap - inFlight.size).coerceAtLeast(0)

  private fun openWaiting(): Boolean = owed.values.any { row -> row.open && row.fetch.blockId !in inFlight }

  private fun reserved(): Int {
    var slots = 0
    if (openWaiting()) slots += 1
    if (planWanted && !planFlying) slots += 1
    return slots
  }

  private fun wantedTurns(): Set<Int> {
    if (visible.isEmpty()) return emptySet()
    val ahead = visible.max() + PrefetchTurns
    val wanted = HashSet<Int>(visible)
    var index = visible.max() + 1
    while (index <= ahead) {
      wanted += index
      index += 1
    }
    return wanted
  }
}
