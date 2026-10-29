package computing.michell.monitor.ui

/* Offline review list order and open mode (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.LinkPhase
import computing.michell.monitor.data.ConversationRecord
import computing.michell.monitor.protocol.OfflineCacheDocument
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OfflineReviewTest {
  @Test
  fun pinnedRowsStayAboveNewerUnpinnedRows() {
    val host = "host-1"
    val olderPinned = row(host, "old", "Older", 1_000L, true)
    val newer = row(host, "new", "Newer", 9_000L, false)
    val listed = conversationsForHost(listOf(newer, olderPinned), host)
    assertEquals("old", listed[0].id)
    assertEquals("new", listed[1].id)
  }

  @Test
  fun offlineOpenDisablesRemoteActionsAndLiveOpenSyncs() {
    val stored = row("host-1", "conv-1", "Notes", 5_000L, false)
    val document = OfflineCacheDocument(emptyList(), emptyList(), null, "", "", emptyList(), -1, "")
    val reviewed = reviewedCacheState(MonitorUi(), document, stored, true)
    assertTrue(reviewed.reviewingOffline)
    assertTrue(reviewed.disconnected)
    assertFalse(reviewed.view.canSend)
    assertEquals(OfflineReviewBanner, reviewed.banner)
    val syncing = syncingCacheState(MonitorUi(), document, stored)
    assertFalse(syncing.reviewingOffline)
    assertTrue(syncing.catchingUp)
    assertFalse(syncing.disconnected)
    assertEquals(ChipSyncing, connectionChip(LinkPhase.Connecting, false, false, true, false, 0, 0, 0).label)
    assertTrue(cachedButtonVisible(false, LinkPhase.Live))
  }

  private fun row(host: String, id: String, title: String, updatedAt: Long, pinned: Boolean): ConversationRecord {
    return ConversationRecord(id, host, "/work", title, "stream", 3L, updatedAt, pinned)
  }
}
