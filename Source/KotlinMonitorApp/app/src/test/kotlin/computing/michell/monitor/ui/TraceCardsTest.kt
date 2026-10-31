package computing.michell.monitor.ui

/* Assistant card captions (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.WireBlock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TraceCardsTest {
  @Test
  fun thinkingTitleAndFooterMatchTheAssistant() {
    assertEquals("Thinking", thinkingCardTitle("", false, 0))
    assertEquals("Thinking… 0:04", thinkingCardTitle("", true, 4000))
    assertEquals("Thinking… 1:02", thinkingCardTitle("Thinking… 1:02", true, 90000))
    assertEquals("Thought for 0:12", thoughtFooter(false, 12000))
    assertEquals("", thoughtFooter(true, 12000))
    assertEquals("", thoughtFooter(false, 0))
  }

  @Test
  fun toolCaptionUsesTheAssistantHeaderNotAStatusWord() {
    val caption = toolCardCaption("read_file  ConversationScreen.kt", "read_file", false, true, 1500)
    assertEquals("read_file  ConversationScreen.kt  1.5s", caption)
    assertEquals("grep  Plan.md …", toolCardCaption("grep  Plan.md", "grep", true, true, 0))
    assertEquals("read_file — failed", toolCardCaption("", "read_file", false, false, 0))
    assertFalse(caption.contains(" ok"))
  }

  @Test
  fun aNamedToolIsStillAToolAndThinkingStartsClosed() {
    val lost = WireBlock("", "id", "", "read_file", "call-1", "body", false, true, 0, emptyList())
    assertEquals("tool", displayKind(lost))
    assertFalse(cardStartsOpen("thinking"))
    assertFalse(cardStartsOpen("tool"))
    assertFalse(cardStartsOpen("subagent"))
    assertTrue(blockShown(lost, true, true))
    assertFalse(blockShown(lost, true, false))
  }

  @Test
  fun aRunningThoughtShowsBeforeItsBody() {
    val running = WireBlock("thinking", "think-1", "Thinking…", "", "", "", true, true, 0, emptyList())
    assertTrue(blockShown(running, true, false))
    assertFalse(blockShown(running, false, true))
    val idle = WireBlock("thinking", "think-1", "", "", "", "   ", false, true, 0, emptyList())
    assertFalse(blockShown(idle, true, true))
  }
}
