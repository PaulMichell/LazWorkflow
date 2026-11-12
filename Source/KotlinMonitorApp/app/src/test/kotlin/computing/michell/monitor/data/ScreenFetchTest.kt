package computing.michell.monitor.data

/* Visible fetches stay inside the cap of two (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTurn
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ScreenFetchTest {
  @Test
  fun cachedRowsWaitForConnectionAndRetryAfterDisconnect() {
    val fetch = ScreenFetch(initiallyConnected = false)
    assertTrue(fetch.noteVisible(setOf(0, 1)).isEmpty())
    assertTrue(fetch.replaceBoard("c1", emptyList(), null).isEmpty())
    val connected = fetch.setConnected(true)
    assertEquals(listOf(0, 1), connected.map { (it as FetchGrant.Turn).index })
    assertTrue(fetch.setConnected(true).isEmpty())
    assertTrue(fetch.setConnected(false).isEmpty())
    assertTrue(fetch.noteVisible(setOf(0, 1)).isEmpty())
    assertEquals(connected, fetch.setConnected(true))
  }

  @Test
  fun deferredBlockAndPlanWaitForConnection() {
    val fetch = ScreenFetch(initiallyConnected = false)
    val live = turn(1, "t-live", deferred = true, running = true)
    assertTrue(fetch.replaceBoard("c1", emptyList(), live).isEmpty())
    assertTrue(fetch.notePlan("/work/Plan.md", "rev-2", false, "", 0L, true).isEmpty())
    val connected = fetch.setConnected(true)
    assertTrue(connected[0] is FetchGrant.Block)
    assertTrue(connected[1] is FetchGrant.Plan)
    fetch.setConnected(false)
    assertEquals(connected, fetch.setConnected(true))
  }

  @Test
  fun anOpenBlockGoesBeforeHistoryAndTheCapHolds() {
    val fetch = ScreenFetch()
    val live = turn(1, "t-live", deferred = true, running = true)
    val older = turn(0, "t-old", deferred = true, running = false)
    val grants = fetch.replaceBoard("c1", listOf(older), live)
    assertEquals(1, grants.size)
    assertTrue((grants.single() as FetchGrant.Block).open)
    val more = fetch.noteVisible(setOf(0, 1))
    assertEquals(1, more.size)
    assertEquals("b-0", (more.single() as FetchGrant.Block).fetch.blockId)
  }

  @Test
  fun aLongLiveTurnFetchesItsTailBeforeOldTools() {
    val fetch = ScreenFetch()
    val blocks = (0 until 9000).map { index ->
      WireBlock("tool", "tool-$index", "", "", "", "", false, true, 0, emptyList(), deferred = true)
    } + WireBlock("answer", "latest", "", "", "", "", true, true, 0, emptyList(), deferred = true)
    val live = WireTurn(1, "live", "build", "", "", "", live = true, blocks = blocks)
    val first = fetch.replaceBoard("c1", emptyList(), live)
    assertEquals("latest", (first.single() as FetchGrant.Block).fetch.blockId)
    val visible = fetch.noteVisible(setOf(1))
    assertEquals("tool-8999", (visible.single() as FetchGrant.Block).fetch.blockId)
  }

  @Test
  fun aRunningBlockPastTheAppendSliceUpdatesWhileAPlanIsOwed() {
    val fetch = ScreenFetch()
    fetch.notePlan("/work/Plan.md", "rev-2", false, "", 0L, true)
    fetch.noteVisible(setOf(4))
    assertTrue(fetch.isFlying("turn:4"))
    val live = turn(1, "t-live", deferred = true, running = true)
    val grants = fetch.replaceBoard("c1", emptyList(), live)
    val block = grants.filterIsInstance<FetchGrant.Block>().single()
    assertTrue(block.open)
    assertEquals("b-1", block.fetch.blockId)
    assertTrue(fetch.isFlying("plan:/work/Plan.md"))
    assertFalse(fetch.isFlying("turn:4"))
  }

  @Test
  fun aRevisionReleasesThePreviousFetch() {
    val fetch = ScreenFetch()
    val first = fetch.replaceBoard("c1", emptyList(), turn(1, "t-live", deferred = true, running = true))
    val flying = first.single() as FetchGrant.Block
    assertTrue(fetch.isFlying(flying.fetch.blockId))
    val revised = fetch.offerRepair(flying.fetch.copy(requestId = "bg-b-1-2"), true)
    val next = revised.filterIsInstance<FetchGrant.Block>().single()
    assertEquals("bg-b-1-2", next.fetch.requestId)
    assertTrue(next.open)
    assertTrue(fetch.isFlying("b-1"))
    val plan = fetch.notePlan("/work/Plan.md", "rev-2", false, "", 0L, true)
    assertTrue(plan.single() is FetchGrant.Plan)
  }

  @Test
  fun anAppliedBodyReleasesTheSlotBeforeTheBoardRepublishes() {
    val fetch = ScreenFetch()
    val live = turn(1, "t-live", deferred = true, running = true)
    fetch.replaceBoard("c1", listOf(turn(0, "t-old", deferred = true, running = false)), live)
    fetch.noteVisible(setOf(0))
    assertTrue(fetch.isFlying("b-1"))
    assertTrue(fetch.isFlying("b-0"))
    val freed = fetch.noteApplied("b-1", true)
    assertFalse(fetch.isFlying("b-1"))
    assertTrue(freed.none { grant -> grant is FetchGrant.Block && grant.fetch.blockId == "b-1" })
    val stale = fetch.replaceBoard("c1", listOf(turn(0, "t-old", deferred = true, running = false)), live)
    assertTrue(stale.none { grant -> grant is FetchGrant.Block && grant.fetch.blockId == "b-1" })
    assertFalse(fetch.isFlying("b-1"))
  }

  @Test
  fun aResumeAsksForTheOpenBodyAgain() {
    val fetch = ScreenFetch()
    val live = turn(1, "t-live", deferred = true, running = true)
    val first = fetch.replaceBoard("c1", emptyList(), live)
    assertEquals("b-1", (first.single() as FetchGrant.Block).fetch.blockId)
    assertTrue(fetch.setConnected(false).isEmpty())
    assertFalse(fetch.isFlying("b-1"))
    val again = fetch.setConnected(true)
    val block = again.filterIsInstance<FetchGrant.Block>().single()
    assertTrue(block.open)
    assertEquals("b-1", block.fetch.blockId)
  }

  @Test
  fun aPlanFetchKeepsTheOpenSlotAndHistoryWaits() {
    val fetch = ScreenFetch()
    val live = turn(1, "t-live", deferred = true, running = true)
    fetch.replaceBoard("c1", listOf(turn(0, "t-old", deferred = true, running = false)), live)
    val plan = fetch.notePlan("/work/Plan.md", "rev-2", false, "", 0L, true)
    assertTrue(plan.single() is FetchGrant.Plan)
    val visible = fetch.noteVisible(setOf(0))
    assertTrue(visible.isEmpty())
  }

  @Test
  fun aTurnTheUserHasNotOpenedIsNotRequested() {
    val fetch = ScreenFetch()
    fetch.replaceBoard("c1", emptyList(), null)
    val grants = fetch.noteVisible(setOf(2))
    assertEquals(2, (grants.single() as FetchGrant.Turn).index)
    assertTrue(grants.none { grant -> grant is FetchGrant.Turn && grant.index == 9 })
  }

  @Test
  fun aDropKeepsThePlanPrefix() {
    val root = File("build/plan-fetch-test")
    root.deleteRecursively()
    val files = PlanFiles(root)
    val first = files.append("host-1", "/work/Plan.md", "rev-1", 0L, "Hello", 11L, false)
    assertEquals(5L, first!!.received)
    val dropped = files.noteDrop("host-1", "/work/Plan.md")
    assertTrue(dropped!!.incomplete)
    assertEquals("Hello", files.readReview("host-1", "/work/Plan.md", 100))
    val done = files.append("host-1", "/work/Plan.md", "rev-1", 5L, " world", 11L, true)
    assertTrue(done!!.complete)
    assertEquals("Hello world", files.readReview("host-1", "/work/Plan.md", 100))
    root.deleteRecursively()
  }

  @Test
  fun cancelStopsThePlanFetchUntilContinue() {
    val fetch = ScreenFetch()
    fetch.notePlan("/work/Plan.md", "rev-2", false, "", 0L, true)
    fetch.cancelPlan()
    assertTrue(fetch.notePlan("/work/Plan.md", "rev-2", false, "", 0L, true).isEmpty())
    val again = fetch.continuePlan("/work/Plan.md", "rev-2", false, "", 0L)
    assertTrue(again.single() is FetchGrant.Plan)
  }

  @Test
  fun aLargeWindowDoesNotKeepTheWholeFile() {
    val root = File("build/plan-window-test")
    root.deleteRecursively()
    val files = PlanFiles(root)
    val body = "# One\n\nStatus: not started\n\n" + "x".repeat(80 * 1024) + "\n## Two\n\nkept\n"
    files.append("host-1", "/work/Plan.md", "rev-1", 0L, body, body.toByteArray().size.toLong(), true)
    val window = files.readWindow("host-1", "/work/Plan.md", "Two", 2)
    assertEquals("## Two\n\nkept", window)
    assertTrue(window.length < body.length)
    root.deleteRecursively()
  }

  private fun turn(index: Int, id: String, deferred: Boolean, running: Boolean): WireTurn {
    val block = WireBlock("answer", "b-$index", "", "", "", "stored", running, true, 0, emptyList(), deferred = deferred)
    return WireTurn(index, id, "build", "", "prompt", "", live = running, blocks = listOf(block))
  }
}
