package computing.michell.monitor.ui

/* Offline restore keeps browseable rows and disables remote actions (c) 2026 Michell Computing. */

import computing.michell.monitor.data.ConversationRecord
import computing.michell.monitor.data.StoredPlan
import computing.michell.monitor.protocol.OfflineCacheDocument
import computing.michell.monitor.protocol.PlanRow
import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTurn
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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
    assertEquals("", restored.draft)
    assertTrue(restored.disconnected)
    assertFalse(restored.reachedLive)
    assertFalse(restored.view.canSend)
    assertEquals(OfflineBanner, restored.banner)
    assertEquals("offline", connectionLabel(restored, computing.michell.monitor.connection.LinkPhase.Idle))
  }

  @Test
  fun openingTheCacheKeepsTheModelAlreadyShown() {
    val document = OfflineCacheDocument(emptyList(), emptyList(), null, "", "", emptyList(), -1, "")
    val restored = applyOfflineCache(MonitorUi(view = emptyView().copy(model = "grok-4.5")), document, true)
    assertEquals("grok-4.5", restored.view.model)
    val placeholder = applyOfflineCache(MonitorUi(view = emptyView().copy(model = "Model")), document, true)
    assertEquals("", placeholder.view.model)
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
  fun aConversationIdIsOneFileAndCurrentIsNotAnIdentity() {
    val id = "6f1d2c3a-8b4e-4c7d-9a2f-0e5b1c3d4a7f"
    val oldRoot = MonitorUi(conversationId = id, projectRoot = "/old", draft = "keep")
    val newRoot = oldRoot.copy(projectRoot = "/work", conversationTitle = "Renamed")
    val oldTarget = cacheSaveTarget(oldRoot)
    val newTarget = cacheSaveTarget(newRoot)
    assertEquals(id, oldTarget!!.conversationId)
    assertEquals("/old", oldTarget.projectRoot)
    assertEquals(id, newTarget!!.conversationId)
    assertEquals("/work", newTarget.projectRoot)
    assertEquals("Renamed", newTarget.title)
    assertTrue(cacheRowChanged(oldRoot, newRoot))
    assertNull(cacheSaveTarget(oldRoot.copy(conversationId = "current")))
    assertNull(cacheSaveTarget(oldRoot.copy(conversationId = "")))
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
  fun aCachedReviewKeepsTheLiveBlobAndDoesNotEnableSend() {
    val live = WireTurn(-2, "live", "build", "", "Still writing", "", prompt = "Still writing", live = true)
    val document = OfflineCacheDocument(
      listOf(WireTurn(1, "turn-1", "build", "", "Shown", "")),
      emptyList(),
      live,
      "",
      "",
      emptyList(),
      -1,
      ""
    )
    val entry = ConversationRecord("current", "aa", "/work/LazWorkflow", "Shown", "", 0L, 1L, false)
    val reviewed = reviewedCacheState(MonitorUi(reachedLive = true, view = emptyView().copy(canSend = true)), document, entry, true)
    assertEquals("Still writing", reviewed.live?.prompt)
    assertEquals("Shown", reviewed.turns[0].promptPreview)
    assertEquals("current", reviewed.conversationId)
    assertEquals("/work/LazWorkflow", reviewed.projectRoot)
    assertFalse(reviewed.view.canSend)
    assertTrue(reviewed.disconnected)
    assertEquals(OfflineBanner, reviewed.banner)
  }

  @Test
  fun theCachedListIsTheLastFingerprintAndHidesWhileLive() {
    val hex = "ab".repeat(32)
    val older = ConversationRecord("conversation-1", hex, "/work/LazWorkflow", "Old", "", 0L, 1L, false)
    val newer = ConversationRecord("current", hex.chunked(2).joinToString(":"), "/other/Phone", "", "", 0L, 9L, false)
    val other = ConversationRecord("current", "cd".repeat(32), "/x", "Other", "", 0L, 8L, false)
    val rows = conversationsForHost(listOf(older, other, newer), hex)
    assertEquals(listOf("current", "conversation-1"), rows.map { it.id })
    assertEquals("Phone", projectDisplay(rows[0].projectRoot))
    assertEquals("LazWorkflow", projectDisplay("/work/LazWorkflow"))
    assertEquals("LazWorkflow", projectDisplay("C:\\work\\LazWorkflow"))
    assertEquals("current", cacheRowTitle(rows[0]))
    assertEquals("26 Oct 2026, 12:00", cacheUpdatedText(java.time.Instant.parse("2026-10-26T12:00:00Z").toEpochMilli(), java.time.ZoneId.of("UTC")))
  }

  @Test
  fun aCachedPlanFillsAnEmptyTabAndDoesNotReplaceALivePlan() {
    val cached = StoredPlan(
      "Documents/Plan.md", "Overview", listOf(PlanRow(0, 3, "Cache the plan", "", "not started", true)), 1, "# Plan"
    )
    val filled = withCachedPlan(MonitorUi(), cached)
    assertEquals("Overview", filled.planTitle)
    assertEquals("Cache the plan", filled.planRows.single().title)
    assertEquals(1, filled.selectedPlan)
    assertEquals("# Plan", filled.planBody)
    val outlined = filled.copy(planBody = "")
    assertEquals("# Plan", withCachedPlan(outlined, cached).planBody)
    val live = filled.copy(planTitle = "Live", planRows = listOf(PlanRow(0, 3, "Live row", "", "in progress", true)))
    assertEquals("Live", withCachedPlan(live, cached).planTitle)
    assertEquals(filled.planTitle, withCachedPlan(filled, StoredPlan("", "", emptyList(), -1)).planTitle)
  }

  @Test
  fun openingAStoredConversationKeepsThePlanAlreadyShown() {
    val shown = MonitorUi(
      planPath = "Documents/Plan.md",
      planTitle = "Overview",
      planRows = listOf(PlanRow(0, 3, "Cache the plan", "", "not started", true)),
      selectedPlan = 0
    )
    val stored = MonitorUi(conversationId = "conversation-1", turns = listOf(WireTurn(1, "t", "build", "", "Shown", "")))
    val kept = keepShownPlan(stored, shown)
    assertEquals("Overview", kept.planTitle)
    assertEquals("Cache the plan", kept.planRows.single().title)
    assertEquals("Shown", kept.turns.single().promptPreview)
    val newer = stored.copy(planTitle = "Other", planPath = "Documents/Other.md", planRows = listOf(PlanRow(0, 2, "Other", "", "", false)))
    assertEquals("Other", keepShownPlan(newer, shown).planTitle)
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
