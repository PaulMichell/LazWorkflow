package computing.michell.monitor.ui

/* Offline restore keeps browseable rows and disables remote actions (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.OfflineCacheDocument
import computing.michell.monitor.protocol.PlanRow
import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTurn
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OfflineCacheUiTest {
  @Test
  fun aSavedSessionOpensOffline() {
    val document = OfflineCacheDocument(
      listOf(WireTurn(4, "turn-4", "build", "", "Anchor the composer", "")),
      emptyList(),
      null,
      "Documents/Plan.md",
      "Release layout",
      listOf(PlanRow(0, 3, "Anchor the composer", "", "not started", true)),
      0,
      "draft"
    )
    val restored = applyOfflineCache(MonitorUi(reachedLive = true), document, true)
    assertEquals("Release layout", restored.planTitle)
    assertEquals("Anchor the composer", restored.turns[0].promptPreview)
    assertEquals(0, restored.selectedPlan)
    assertEquals("draft", restored.draft)
    assertTrue(restored.disconnected)
    assertFalse(restored.reachedLive)
    assertFalse(restored.view.canSend)
    assertEquals(OfflineBanner, restored.banner)
    assertEquals("offline", connectionLabel(restored, computing.michell.monitor.connection.LinkPhase.Idle))
  }

  @Test
  fun aMissingImageStaysAPlaceholderWhileDisconnected() {
    assertEquals(ImagePlaceholder, imageTileLabel(false, null, false, false))
    assertEquals(LoadingImageLabel, imageTileLabel(false, null, false, true))
    assertEquals("Image unavailable: missing", imageTileLabel(false, null, true, false))
    assertEquals("", imageTileLabel(true, null, false, false))
  }

  @Test
  fun anEmptyTitleUsesTheFirstUserPromptPreview() {
    val user = WireBlock("user", "u1", "", "", "", "Anchor the composer", false, true, 0, emptyList())
    val note = WireTurn(0, "note", "build", "", "", "")
    val live = WireTurn(-2, "live", "build", "", "Anchor preview", "", blocks = listOf(user))
    assertEquals("Release", cacheTitle("Release", listOf(note), live, emptyList()))
    assertEquals("Anchor preview", cacheTitle("", listOf(note), live, emptyList()))
    assertEquals("Shown", cacheTitle("", listOf(WireTurn(1, "t", "build", "", "Shown", "")), null, emptyList()))
    assertEquals("Anchor the composer", cacheTitle("", emptyList(), live.copy(promptPreview = ""), emptyList()))
  }

  @Test
  fun currentOnAnotherProjectRootIsADifferentFile() {
    val oldRoot = MonitorUi(conversationId = "current", projectRoot = "/old", draft = "keep")
    val newRoot = oldRoot.copy(projectRoot = "/work", conversationTitle = "Renamed")
    val oldTarget = cacheSaveTarget(oldRoot)
    val newTarget = cacheSaveTarget(newRoot)
    assertEquals("current", oldTarget!!.conversationId)
    assertEquals("/old", oldTarget.projectRoot)
    assertEquals("current", newTarget!!.conversationId)
    assertEquals("/work", newTarget.projectRoot)
    assertEquals("Renamed", newTarget.title)
    assertTrue(cacheRowChanged(oldRoot, newRoot))
    assertFalse(cacheConversationFileName("aa", oldTarget.projectRoot, oldTarget.conversationId) ==
      cacheConversationFileName("aa", newTarget.projectRoot, newTarget.conversationId))
  }

  @Test
  fun aFinishedPatchCommitsTheCursorAndAnOpenPartDoesNot() {
    val before = MonitorUi(hostEpoch = "aa", hostCursor = 3)
    val committed = before.copy(hostCursor = 4)
    val partial = before.copy(patchOpenCursor = 4, patchPartCount = 2)
    val catching = before.copy(hostEpoch = "bb", hostCursor = 1, catchingUp = true)
    assertTrue(cursorCommitted(before, committed))
    assertFalse(cursorCommitted(before, partial))
    assertFalse(cursorCommitted(before, catching))
    assertTrue(cursorCommitted(before, before.copy(hostEpoch = "bb", hostCursor = 0)))
  }

  @Test
  fun noAddressStillShowsTheCachedPlan() {
    val document = OfflineCacheDocument(
      emptyList(), emptyList(), null, "Documents/Plan.md", "Release layout",
      listOf(PlanRow(0, 2, "Layout", "", "", false)), -1, ""
    )
    val restored = applyOfflineCache(MonitorUi(), document, false)
    assertEquals("Release layout", restored.planTitle)
    assertEquals(NoAddressBanner, restored.banner)
    assertTrue(restored.disconnected)
  }
}
