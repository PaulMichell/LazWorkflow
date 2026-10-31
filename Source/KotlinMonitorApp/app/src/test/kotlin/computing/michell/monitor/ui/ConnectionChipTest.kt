package computing.michell.monitor.ui

/* Connection chip and lazy row keys (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTurn
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ConnectionChipTest {
  @Test
  fun liveAndBusyComeFromTheStateChannel() {
    val idle = connectionChip(LinkPhase.Live, false, false, false, false, 0, 0, 0)
    assertEquals(ChipLive, idle.label)
    val patchBusy = connectionChip(LinkPhase.Live, false, false, false, false, 4, 0, 0)
    assertEquals(ChipLive, patchBusy.label)
    val stateBusy = connectionChip(LinkPhase.Live, false, false, false, true, 4, 0, 0)
    assertEquals(ChipBusy, stateBusy.label)
  }

  @Test
  fun aLiveCatchUpDoesNotPrintTheLogCursor() {
    val chip = connectionChip(LinkPhase.Live, false, false, true, false, 413, 0, 0)
    assertEquals(ChipLive, chip.label)
    assertEquals(ChipSyncing, syncingLabel(413, 0))
  }

  @Test
  fun syncingShowsProgressAndOfflineShowsTheLastSync() {
    val syncing = connectionChip(LinkPhase.Connecting, false, false, true, false, 4, 10, 0)
    assertEquals("Syncing 40%", syncing.label)
    assertTrue(linkSyncing(LinkPhase.Connecting, false, true, false))
    assertFalse(linkSyncing(LinkPhase.Connecting, false, false, false))
    val offline = connectionChip(
      LinkPhase.Disconnected, true, false, false, false, 0, 0, 1_700_000_000_000L, ZoneOffset.UTC
    )
    assertTrue(offline.label.startsWith("Offline · "))
    assertFalse(offline.label == ChipOffline)
  }

  @Test
  fun replacedIsPairedElsewhere() {
    val chip = connectionChip(LinkPhase.Paused, true, true, false, true, 3, 3, 1L)
    assertEquals(PairedElsewhereLabel, chip.label)
  }

  @Test
  fun rowKeysUseTurnAndBlockIdentity() {
    val turn = WireTurn(
      2, "turn-2", "build", "", "prompt", "",
      blocks = listOf(
        WireBlock("answer", "block-a", "Running", "", "", "first", true, false, 0, emptyList()),
        WireBlock("thinking", "block-b", "Done", "", "", "second", false, true, 0, emptyList())
      )
    )
    val rows = conversationRows(listOf(turn), null, false, true, true)
    assertEquals(conversationRowKey("turn-2", "block-a", 0), rows[0].key)
    assertEquals(conversationRowKey("turn-2", "block-b", 1), rows[1].key)
    assertEquals(foldBlockKey(1, "turn-2", "block-b", 1), foldBlockKey(1, "turn-2", "block-b", 1))
    assertFalse(rows[0].key.contains("Running"))
    assertFalse(rows[1].key.contains("second"))
  }

  @Test
  fun duplicateTurnIdentityDoesNotReuseALazyKey() {
    val first = WireTurn(1, "same", "build", "", "One", "", blocks = listOf(
      WireBlock("answer", "block", "", "", "", "one", false, true, 0, emptyList())
    ))
    val second = WireTurn(1, "same", "build", "", "Two", "", blocks = listOf(
      WireBlock("answer", "block", "", "", "", "two", false, true, 0, emptyList())
    ))
    val rows = conversationRows(listOf(first, second), null, false, true, true)
    assertEquals(2, rows.size)
    assertFalse(rows[0].key == rows[1].key)
  }

  @Test
  fun outlineDoesNotAddATurnAlreadyOnScreen() {
    val shown = WireTurn(3, "turn-3", "build", "", "Shown", "")
    val outline = listOf(
      WireTurn(3, "turn-3", "build", "", "Shown again", ""),
      WireTurn(4, "turn-4", "build", "", "Next", ""),
      WireTurn(4, "turn-4b", "build", "", "Same index", "")
    )
    val added = addedOutlineTurns(listOf(shown), outline)
    assertEquals(1, added.size)
    assertEquals("turn-4", added[0].id)
  }

  @Test
  fun theDesktopOutlineDropsACachedThoughtTheDesktopDoesNotHave() {
    val thought = WireBlock("thinking", "think", "Thinking…", "", "", "still going", true, true, 0, emptyList())
    val stale = WireTurn(2, "stale", "build", "", "Old thought", "", live = true, blocks = listOf(thought))
    val kept = WireTurn(1, "turn-1", "build", "", "Kept", "", blocks = listOf(
      WireBlock("thinking", "t", "Thinking…", "", "", "done", true, true, 0, emptyList()),
      WireBlock("answer", "a", "", "", "", "the answer", false, true, 0, emptyList())
    ))
    val outline = listOf(WireTurn(1, "turn-1", "build", "", "Kept", ""))
    val shown = turnsFromDesktopOutline(listOf(kept), stale, outline)
    assertEquals(1, shown.size)
    assertEquals("turn-1", shown[0].id)
    assertFalse(shown[0].blocks.first().running)
    assertEquals("the answer", displayBlocks(shown[0]).last().body)
  }
}
