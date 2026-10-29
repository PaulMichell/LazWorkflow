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
  fun syncingShowsProgressAndOfflineShowsTheLastSync() {
    val syncing = connectionChip(LinkPhase.Connecting, false, false, true, false, 4, 10, 0)
    assertEquals("Syncing 40%", syncing.label)
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
}
