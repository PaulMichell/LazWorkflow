package computing.michell.monitor.net

/* Item follower against a fake clock. A fast host stays at four fetches a
   second. A slow host backs off to two seconds. Scrolling away stops tails.
   A closing item still gets one final fetch. (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ItemFollowerTest {
  @Test
  fun aFastHostGetsAboutFourFetchesASecond() {
    val clock = VirtualClock()
    val tails = ArrayList<Long>()
    val follower = ItemFollower(clock, onTail = { tails += clock.now() })
    follower.watching(screenOn = true, foreground = true, followingHead = true)
    var rev = 1L
    for (at in 0L..2000L step 50L) {
      clock.advanceTo(at)
      follower.onPulse("t1", "i1", rev, "running")
      follower.noteFetchCompleted()
      rev += 1
    }
    assertEquals(listOf(0L, 250L, 500L, 750L, 1000L, 1250L, 1500L, 1750L, 2000L), tails)
    assertEquals(FollowMinMs, follower.followMs)
    assertEquals(FollowMinMs, follower.intervalMs)
    assertEquals(4.0, (tails.size - 1) / 2.0, 0.01)
  }

  @Test
  fun aSlowHostBacksOffToOneFetchEveryTwoSeconds() {
    val clock = VirtualClock()
    val tails = ArrayList<Long>()
    val follower = ItemFollower(clock, onTail = { tails += clock.now() })
    follower.watching(screenOn = true, foreground = true, followingHead = true)
    fun pulse(at: Long, rev: Long) {
      clock.advanceTo(at)
      follower.onPulse("t1", "i1", rev, "running")
    }
    pulse(0, 1)
    clock.advanceTo(200)
    follower.noteFetchCompleted()
    assertEquals(500L, follower.followMs)
    pulse(200, 2)
    assertEquals(1, tails.size)
    pulse(500, 3)
    clock.advanceTo(900)
    follower.noteFetchCompleted()
    assertEquals(1000L, follower.followMs)
    pulse(1500, 4)
    clock.advanceTo(2300)
    follower.noteFetchCompleted()
    assertEquals(2000L, follower.followMs)
    assertEquals(2000L, follower.intervalMs)
    pulse(3500, 5)
    clock.advanceTo(5000)
    follower.noteFetchCompleted()
    assertEquals(2000L, follower.followMs)
    var rev = 20L
    for (at in 3600L..7500L step 100L) {
      pulse(at, rev)
      rev += 1
    }
    assertEquals(listOf(0L, 500L, 1500L, 3500L, 5500L, 7500L), tails)
    clock.advanceTo(7550)
    follower.noteFetchCompleted()
    assertEquals(FollowMinMs, follower.followMs)
    assertEquals(FollowMinMs, follower.intervalMs)
  }

  @Test
  fun scrollingAwayStopsTailFetches() {
    val clock = VirtualClock()
    val tails = ArrayList<String>()
    val follower = ItemFollower(clock, onTail = { tails += it })
    follower.watching(screenOn = true, foreground = true, followingHead = true)
    clock.advanceTo(0)
    follower.onPulse("t1", "i1", 1, "running")
    follower.noteFetchCompleted()
    assertEquals(listOf("i1"), tails)
    follower.scrollAway()
    assertEquals(FollowAwayIntervalMs, follower.intervalMs)
    var rev = 2L
    for (at in 250L..2000L step 250L) {
      clock.advanceTo(at)
      follower.onPulse("t1", "i1", rev, "running")
      follower.noteFetchCompleted()
      rev += 1
    }
    assertEquals(1, tails.size)
    follower.background()
    follower.screenOff()
    clock.advanceTo(8000)
    follower.onPulse("t1", "i1", 99, "running")
    assertEquals(FollowAwayIntervalMs, follower.intervalMs)
    assertEquals(1, tails.size)
  }

  @Test
  fun aClosingItemAlwaysGetsItsFinalFetch() {
    val clock = VirtualClock()
    val tails = ArrayList<String>()
    val itemFinals = ArrayList<String>()
    val turnFinals = ArrayList<String>()
    val follower = ItemFollower(clock, onTail = { tails += it }, onItemFinal = { itemFinals += it }, onTurnFinal = { turnFinals += it })
    follower.scrollAway()
    clock.advanceTo(0)
    follower.onPulse("t1", "i1", 1, "running")
    follower.onPulse("t1", "i1", 2, "running")
    assertTrue(tails.isEmpty())
    assertTrue(itemFinals.isEmpty())
    follower.onPulse("t1", "i1", 3, "done")
    assertEquals(listOf("i1"), itemFinals)
    follower.onPulse("t1", "i1", 4, "done")
    assertEquals(1, itemFinals.size)
    follower.onPulse(null, null, 0, "")
    assertEquals(listOf("t1"), turnFinals)
    follower.onPulse(null, null, 0, "")
    assertEquals(1, turnFinals.size)
    assertTrue(tails.isEmpty())
  }
}
