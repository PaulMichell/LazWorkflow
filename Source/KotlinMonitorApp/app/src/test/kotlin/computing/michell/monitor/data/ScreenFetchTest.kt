package computing.michell.monitor.data

/* Visible fetches stay inside the cap of two (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTurn
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ScreenFetchTest {
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

  private fun turn(index: Int, id: String, deferred: Boolean, running: Boolean): WireTurn {
    val block = WireBlock("answer", "b-$index", "", "", "", "stored", running, true, 0, emptyList(), deferred = deferred)
    return WireTurn(index, id, "build", "", "prompt", "", live = running, blocks = listOf(block))
  }
}
