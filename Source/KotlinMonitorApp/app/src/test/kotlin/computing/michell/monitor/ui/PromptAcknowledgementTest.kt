package computing.michell.monitor.ui

/* Prompt acknowledgement across completed-turn synchronisation (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.WireBlock
import computing.michell.monitor.protocol.WireTurn
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PromptAcknowledgementTest {
  private fun turn(id: String, text: String) = WireTurn(
    0, id, "build", "", text, "", live = false,
    blocks = listOf(WireBlock("user", "$id-user", "", "", "", text, false, true, 0, emptyList()))
  )

  @Test
  fun completedSnapshotAcknowledgesPendingPromptWithoutLiveTurn() {
    val state = MonitorUi(pendingPrompt = "fix this", turns = listOf(turn("new", "fix this")))
    assertTrue(promptShown(state, state.pendingPrompt))
  }

  @Test
  fun olderIdenticalPromptCannotAcknowledgeResubmission() {
    val old = turn("old", "fix this")
    val baseline = promptBaselineOf(null, listOf(old))
    val pending = MonitorUi(pendingPrompt = "fix this", promptBaseline = baseline, turns = listOf(old))
    assertFalse(promptShown(pending, pending.pendingPrompt))
    assertTrue(promptShown(pending.copy(turns = listOf(old, turn("new", "fix this"))), pending.pendingPrompt))
  }

  @Test
  fun previewOrAssistantTextDoesNotAcknowledgeSubmission() {
    val preview = turn("new", "fix this").copy(blocks = emptyList())
    assertFalse(promptShown(MonitorUi(turns = listOf(preview)), "fix this"))
    val answer = turn("new", "fix this").let { row -> row.copy(blocks = row.blocks.map { it.copy(kind = "answer") }) }
    assertFalse(promptShown(MonitorUi(turns = listOf(answer)), "fix this"))
  }
}
