package computing.michell.monitor.ui

/* Draws the assistant markdown subset. The first block has no top margin, so a
   thought can sit on the line under its header. (c) 2026 Michell Computing. */

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val CodeFill = Color(0xFFFFF8DC)
private val QuoteFill = Color(0xFFF0F0F0)
private val QuietInk = Color(0xFF666666)

private val HeadingScale = floatArrayOf(1.80f, 1.55f, 1.35f, 1.20f, 1.10f, 1f)

@Composable
fun tightTranscriptStyle(): TextStyle {
  val base = androidx.compose.material3.MaterialTheme.typography.bodyLarge
  return base.copy(
    platformStyle = PlatformTextStyle(includeFontPadding = false),
    lineHeightStyle = LineHeightStyle(
      alignment = LineHeightStyle.Alignment.Proportional,
      trim = LineHeightStyle.Trim.Both
    )
  )
}

/** Header box is one line tall, so the thought is the next line, not a padded gap. */
@Composable
fun thinkingHeaderStyle(): TextStyle {
  val base = tightTranscriptStyle()
  return base.copy(lineHeight = base.fontSize, fontWeight = FontWeight.Bold, color = QuietInk)
}

@Composable
fun MarkdownText(
  source: String,
  modifier: Modifier = Modifier,
  color: Color = Color.Unspecified,
  italic: Boolean = false,
  style: TextStyle? = null,
  live: Boolean = false
) {
  val resolved = style ?: tightTranscriptStyle()
  val held = remember { mutableStateOf<MarkdownParse?>(null) }
  val blocks = remember(source, live) {
    val next = extendMonitorMarkdown(if (live) held.value else null, source)
    if (live) held.value = next
    next.blocks
  }
  if (blocks.isEmpty()) return
  Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
    var index = 0
    while (index < blocks.size) {
      val block = blocks[index]
      if (block.group != 0 && block.codeBlock) {
        val grouped = ArrayList<MarkdownBlock>()
        val group = block.group
        val groupKey = index
        while (index < blocks.size && blocks[index].group == group) {
          grouped += blocks[index]
          index += 1
        }
        key(groupKey) { CodeGroup(grouped, resolved) }
      } else {
        key(index) { BlockText(block, color, italic, resolved) }
        index += 1
      }
    }
  }
}

@Composable
private fun CodeGroup(blocks: List<MarkdownBlock>, style: TextStyle) {
  Text(
    blocks.joinToString("\n") { block -> block.spans.joinToString("") { span -> span.text } },
    modifier = Modifier.fillMaxWidth().background(CodeFill).padding(horizontal = 8.dp, vertical = 6.dp),
    style = style.copy(fontFamily = FontFamily.Monospace, fontSize = style.fontSize * 0.9f)
  )
}

@Composable
private fun BlockText(block: MarkdownBlock, color: Color, italic: Boolean, style: TextStyle) {
  val ink = if (block.quote) QuietInk else color
  val text = annotated(block.spans, ink, italic)
  val blockStyle = if (block.headingLevel in 1..6) {
    val scale = HeadingScale[block.headingLevel - 1]
    val size = (style.fontSize.value * scale).sp
    style.copy(fontSize = size, fontWeight = FontWeight.Bold, lineHeight = (size.value * 1.15f).sp)
  } else style
  val pad = Modifier.padding(start = block.indent.dp).then(
    if (block.quote) Modifier.background(QuoteFill).padding(horizontal = 8.dp, vertical = 2.dp) else Modifier
  )
  if (block.table) {
    Row(Modifier.fillMaxWidth().then(if (block.tableHeader) Modifier.background(QuoteFill) else Modifier)) {
      val cells = markdownCells(block)
      cells.forEachIndexed { cellIndex, cell ->
        val align = when (block.align.getOrElse(cellIndex) { "left" }) {
          "center" -> TextAlign.Center
          "right" -> TextAlign.End
          else -> TextAlign.Start
        }
        Text(
          annotated(cell, ink, italic),
          modifier = Modifier.weight(1f).padding(horizontal = 6.dp, vertical = 4.dp),
          style = blockStyle,
          textAlign = align
        )
      }
    }
  } else {
    Text(text, modifier = pad.fillMaxWidth(), style = blockStyle)
  }
}

private fun annotated(spans: List<MarkdownSpan>, color: Color, italic: Boolean): AnnotatedString {
  return buildAnnotatedString {
    for (span in spans) {
      withStyle(spanStyle(span, color, italic)) { append(span.text) }
    }
  }
}

private fun spanStyle(span: MarkdownSpan, color: Color, baseItalic: Boolean): SpanStyle {
  val italic = span.italic || (baseItalic && !span.code)
  return SpanStyle(
    color = color,
    fontWeight = if (span.bold) FontWeight.Bold else FontWeight.Normal,
    fontStyle = if (italic) FontStyle.Italic else FontStyle.Normal,
    fontFamily = if (span.code) FontFamily.Monospace else FontFamily.Default,
    background = if (span.code) CodeFill else Color.Unspecified,
    textDecoration = if (span.strike) TextDecoration.LineThrough else TextDecoration.None
  )
}
