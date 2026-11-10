package computing.michell.monitor.ui

/* Assistant-window markdown subset, without a device (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MonitorMarkdownTest {
  @Test
  fun newConversationNoteRendersBoldWithoutMarkers() {
    val text = "New conversation started in **Build**. Previous conversation moved to History."
    assertEquals(
      "New conversation started in Build. Previous conversation moved to History.",
      markdownPlain(text)
    )
    val bold = markdownSpans(text).filter { span -> span.bold }.joinToString("") { span -> span.text }
    assertEquals("Build", bold)
    assertFalse(markdownPlain(text).contains("**"))
  }

  @Test
  fun emphasisCodeStrikeAndWordsMatchTheAssistant() {
    assertEquals("Error:", markdownSpans("**Error:** failed").first { span -> span.bold }.text)
    val italic = markdownSpans("*note*").single()
    assertTrue(italic.italic)
    assertFalse(italic.bold)
    assertEquals("note", italic.text)
    val both = markdownSpans("***both***").single()
    assertTrue(both.bold && both.italic)
    val code = markdownSpans("use `code` here").first { span -> span.code }
    assertEquals("code", code.text)
    assertTrue(markdownSpans("~~gone~~").single().strike)
    assertEquals("foo_bar", markdownPlain("foo_bar"))
    assertFalse(markdownSpans("foo_bar").any { span -> span.italic })
    assertEquals("**", markdownPlain("\\*\\*"))
    assertEquals("see [a](b)", markdownPlain("see [a](b)"))
    assertEquals("**not", markdownPlain("**not"))
  }

  @Test
  fun thinkingDropsLeadingBlankLinesAndStartsOnTheNextLine() {
    assertEquals("The request.", thinkingDisplayBody("\n\n\nThe request."))
    assertEquals("The request.", thinkingDisplayBody("\r\n\r\nThe request."))
    assertEquals("", thinkingDisplayBody("\n  \n\t\n"))
    assertEquals("  indented", thinkingDisplayBody("\n  indented"))
    val blocks = parseMonitorMarkdown("\n\n\nThe request.")
    assertEquals(1, blocks.size)
    assertEquals("The request.", blocks[0].spans.joinToString("") { span -> span.text })
    assertFalse(thinkingDisplayBody("\n\nHello").startsWith("\n"))
  }

  @Test
  fun paragraphsListsHeadingsAndFences() {
    assertEquals("Hello world", markdownPlain("Hello\nworld"))
    val broken = parseMonitorMarkdown("Hello  \nworld")
    assertEquals(listOf("Hello", "world"), broken.map { block -> block.spans.joinToString("") { span -> span.text } })
    assertEquals(listOf("Hello", "world"), parseMonitorMarkdown("Hello\n\nworld").map { block ->
      block.spans.joinToString("") { span -> span.text }
    })
    val heading = parseMonitorMarkdown("# Title").single()
    assertEquals(1, heading.headingLevel)
    assertEquals("Title", heading.spans.joinToString("") { span -> span.text })
    assertTrue(heading.spans.all { span -> span.bold })
    assertEquals("• item", markdownPlain("- item"))
    assertEquals("1. item", markdownPlain("1. item"))
    val fence = parseMonitorMarkdown("```\n**not bold**\n```")
    assertEquals(1, fence.size)
    assertTrue(fence[0].codeBlock)
    assertEquals("**not bold**", fence[0].spans.joinToString("") { span -> span.text })
    val table = parseMonitorMarkdown("| A | B |\n| --- | --- |\n| 1 | 2 |")
    assertEquals(2, table.size)
    assertTrue(table[0].tableHeader)
    assertEquals(listOf("A", "B"), markdownCells(table[0]).map { cell -> cell.joinToString("") { span -> span.text } })
    assertEquals(listOf("1", "2"), markdownCells(table[1]).map { cell -> cell.joinToString("") { span -> span.text } })
  }

  @Test
  fun appendingDoesNotRewalkTheParsedPrefix() {
    val prefix = "The plan has already explained the layout in detail.\n"
    val first = extendMonitorMarkdown(null, prefix)
    val full = prefix + "A new token"
    val second = extendMonitorMarkdown(first, full)
    assertEquals(parseMonitorMarkdown(full), second.blocks)
    assertTrue(second.walked < prefix.length)
    assertTrue(second.walked <= "A new token".length + 1)
    val replaced = extendMonitorMarkdown(first, "A different document.")
    assertEquals(parseMonitorMarkdown("A different document."), replaced.blocks)
  }

  @Test
  fun aClosedFenceStillMatchesAFullParseAfterStreaming() {
    val partial = "Intro\n\n```\ncode\n"
    val more = partial + "more\n```\nAfter\n"
    val streamed = extendMonitorMarkdown(extendMonitorMarkdown(null, partial), more)
    assertEquals(parseMonitorMarkdown(more), streamed.blocks)
    assertTrue(streamed.blocks.any { block -> block.codeBlock })
    assertTrue(streamed.walked < more.length)
  }

  @Test
  fun toolsStayLiteral() {
    assertFalse(rendersMarkdown("tool"))
    assertTrue(rendersMarkdown("steer"))
    assertTrue(rendersMarkdown("note"))
    assertTrue(rendersMarkdown("thinking"))
    assertTrue(rendersMarkdown("answer"))
    assertTrue(rendersMarkdown("user"))
    assertTrue(rendersMarkdown("worked"))
    assertTrue(rendersMarkdown("subagent"))
  }
}
