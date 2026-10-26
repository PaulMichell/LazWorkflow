package computing.michell.monitor.ui

/* Conversation markdown. The same subset the assistant window draws, not CommonMark.
   Leading blank lines are skipped, so a thought starts on the next line under its header.
   (c) 2026 Michell Computing. */

data class MarkdownSpan(
  val text: String,
  val bold: Boolean = false,
  val italic: Boolean = false,
  val strike: Boolean = false,
  val code: Boolean = false
)

data class MarkdownBlock(
  val spans: List<MarkdownSpan>,
  val headingLevel: Int = 0,
  val indent: Int = 0,
  val quote: Boolean = false,
  val codeBlock: Boolean = false,
  val table: Boolean = false,
  val tableHeader: Boolean = false,
  val align: List<String> = emptyList(),
  val group: Int = 0
)

/** Tool output and steer stay literal. Everything else is the assistant's markdown path. */
fun rendersMarkdown(kind: String): Boolean = kind != "tool" && kind != "steer"

/** Drop blank lines above the first line of a thought. The header already names it. */
fun thinkingDisplayBody(body: String): String {
  val text = normaliseMarkdown(body)
  var index = 0
  while (index < text.length) {
    val next = text.indexOf('\n', index)
    val end = if (next < 0) text.length else next
    if (text.substring(index, end).isNotBlank()) return text.substring(index)
    if (next < 0) return ""
    index = next + 1
  }
  return ""
}

fun parseMonitorMarkdown(source: String): List<MarkdownBlock> {
  return MarkdownReader().parse(normaliseMarkdown(source))
}

fun markdownPlain(source: String): String {
  return parseMonitorMarkdown(source).joinToString("\n") { block ->
    block.spans.joinToString("") { span -> span.text }
  }
}

fun markdownSpans(source: String): List<MarkdownSpan> {
  return parseMonitorMarkdown(source).flatMap { block -> block.spans }
}

fun markdownCells(block: MarkdownBlock): List<List<MarkdownSpan>> {
  val cells = ArrayList<ArrayList<MarkdownSpan>>()
  var current = ArrayList<MarkdownSpan>()
  for (span in block.spans) {
    if (span.text == "\t" && !span.code && !span.bold && !span.italic && !span.strike) {
      cells += current
      current = ArrayList()
    } else current += span
  }
  cells += current
  return cells
}

private fun normaliseMarkdown(value: String): String {
  var text = value
  if (text.startsWith("\uFEFF")) text = text.substring(1)
  return text.replace("\r\n", "\n").replace('\r', '\n').replace("\u0000", "")
}

private fun splitMarkdownLines(value: String): List<String> {
  if (value.isEmpty()) return emptyList()
  val parts = value.split('\n')
  return if (parts.size > 1 && parts.last().isEmpty()) parts.dropLast(1) else parts
}

private class MarkdownReader {
  private val blocks = ArrayList<MarkdownBlock>()
  private val spans = ArrayList<MarkdownSpan>()
  private var open = false
  private var indent = 0
  private var quote = false
  private var codeBlock = false
  private var headingLevel = 0
  private var table = false
  private var tableHeader = false
  private var align = emptyList<String>()
  private var group = 0
  private var nextGroup = 1

  fun parse(value: String): List<MarkdownBlock> {
    val lines = splitMarkdownLines(value)
    var index = 0
    var paragraphOpen = false
    var listContentIndent = -1
    while (index < lines.size) {
      val raw = lines[index]
      val bodyStart = raw.indexOfFirst { ch -> ch != ' ' && ch != '\t' }
      val lineIndent = if (bodyStart < 0) raw.length else bodyStart
      val body = if (bodyStart < 0) "" else raw.substring(bodyStart)
      if (body.isEmpty()) {
        paragraphOpen = false
        index += 1
        continue
      }
      if (index == 0 && raw == "---") {
        var finish = index + 1
        while (finish < lines.size && lines[finish] != "---") finish += 1
        if (finish == lines.size) finish = index
        while (index <= finish) {
          startParagraph()
          append(lines[index], false, false, false, false)
          index += 1
        }
        paragraphOpen = false
        continue
      }
      if (lineIndent <= 3 && (body[0] == '`' || body[0] == '~') && runLength(body, 0) >= 3) {
        val count = runLength(body, 0)
        val fence = body.substring(0, count)
        var finish = index + 1
        while (finish < lines.size) {
          val closing = lines[finish].trim()
          val closingIndent = lines[finish].length - lines[finish].trimStart().length
          if (closing.startsWith(fence) && runLength(closing, 0) == closing.length && closingIndent <= 3) break
          finish += 1
        }
        val literal = finish == lines.size
        val fenceGroup = nextGroup++
        if (!literal) index += 1
        while (index < finish) {
          startParagraph(codeBlock = !literal, group = fenceGroup)
          append(lines[index], false, false, false, false)
          index += 1
        }
        index += 1
        paragraphOpen = false
        continue
      }
      val tableEnd = tryTable(lines, index)
      if (tableEnd > index) {
        paragraphOpen = false
        index = tableEnd
        continue
      }
      var continuation = listContentIndent >= 0 && lineIndent >= listContentIndent && lineIndent < listContentIndent + 4
      if (listContentIndent >= 0 && lineIndent < listContentIndent) listContentIndent = -1
      continuation = continuation && listContentIndent >= 0
      val rule = body[0] in "-_*=" && runLength(body, 0) == body.length && body.length >= 3
      val literal = (lineIndent >= 4 && !continuation) || body.contains('|') || body[0] in "<$[!" || rule
      if (literal) {
        startParagraph()
        append(raw, false, false, false, false)
        paragraphOpen = false
        index += 1
        continue
      }
      var level = 0
      var text = body
      var displayIndent = lineIndent
      var quoted = false
      if (body[0] == '#') {
        val count = runLength(body, 0)
        if (count in 1..6 && (count == body.length || body[count] == ' ')) {
          level = count
          text = body.substring(count).trim()
        }
      }
      var blockLine = level > 0
      var unordered = false
      var markerLength = 0
      if (level == 0 && text.length >= 2) {
        if (text[0] in "-+*" && text[1] == ' ') {
          unordered = true
          markerLength = 2
        } else if (text[0].isDigit()) {
          var count = 0
          while (count < text.length && text[count].isDigit()) count += 1
          if (count < text.length && text[count] == '.' && count + 1 < text.length && text[count + 1] == ' ') {
            markerLength = count + 2
          }
        }
        if (markerLength > 0) {
          blockLine = true
          listContentIndent = lineIndent + markerLength
          displayIndent = 20 + lineIndent * 6
          if (unordered) text = "• " + text.substring(2)
        } else if (text[0] == '>' && text[1] == ' ') {
          blockLine = true
          displayIndent += 20
          quoted = true
          text = text.substring(2)
        }
      }
      var slashCount = text.length
      while (slashCount > 0 && text[slashCount - 1] == '\\') slashCount -= 1
      val hardBreak = text.endsWith("  ") || ((text.length - slashCount) % 2 == 1)
      if (hardBreak) {
        if (text.endsWith("\\")) text = text.dropLast(1)
        text = text.trimEnd()
      }
      if (!paragraphOpen || blockLine) startParagraph(indent = displayIndent, quote = quoted, headingLevel = level)
      else append(" ", false, false, false, false)
      inline(text, level > 0, false, false, 0)
      paragraphOpen = !blockLine && !hardBreak
      index += 1
    }
    finishParagraph()
    return blocks.toList()
  }

  private fun tryTable(lines: List<String>, index: Int): Int {
    if (index + 1 >= lines.size) return index
    val header = splitTableRow(lines[index]) ?: return index
    val separator = splitTableRow(lines[index + 1]) ?: return index
    if (header.size != separator.size || header.isEmpty()) return index
    val columns = ArrayList<String>()
    for (cell in separator) {
      var marker = cell
      if (marker.isEmpty()) return index
      var column = "left"
      if (marker[0] == ':') {
        column = "center"
        marker = marker.substring(1)
      }
      if (marker.isNotEmpty() && marker.last() == ':') {
        if (column == "left") column = "right"
        marker = marker.dropLast(1)
      } else column = "left"
      if (marker.length < 3 || marker.any { ch -> ch != '-' }) return index
      columns += column
    }
    var row = index
    var headerRow = true
    var cells = header
    while (true) {
      startParagraph(table = true, tableHeader = headerRow, align = columns.toList())
      cells.forEachIndexed { cellIndex, cell ->
        if (cellIndex > 0) append("\t", false, false, false, false)
        inline(cell, headerRow, false, false, 0)
      }
      row += if (headerRow) 2 else 1
      headerRow = false
      if (row >= lines.size) break
      val nextRaw = lines[row]
      val nextIndent = nextRaw.length - nextRaw.trimStart().length
      val nextCells = splitTableRow(nextRaw)
      if (nextIndent >= 4 || nextCells == null || nextCells.size > columns.size) break
      cells = nextCells
    }
    return row
  }

  private fun startParagraph(
    indent: Int = 0,
    quote: Boolean = false,
    codeBlock: Boolean = false,
    headingLevel: Int = 0,
    table: Boolean = false,
    tableHeader: Boolean = false,
    align: List<String> = emptyList(),
    group: Int = 0
  ) {
    finishParagraph()
    this.indent = indent
    this.quote = quote
    this.codeBlock = codeBlock
    this.headingLevel = headingLevel
    this.table = table
    this.tableHeader = tableHeader
    this.align = align
    this.group = group
    open = true
  }

  private fun finishParagraph() {
    if (!open) return
    if (spans.isNotEmpty() || codeBlock || table) {
      blocks += MarkdownBlock(
        spans = spans.toList(),
        headingLevel = headingLevel,
        indent = indent,
        quote = quote,
        codeBlock = codeBlock,
        table = table,
        tableHeader = tableHeader,
        align = align,
        group = group
      )
    }
    spans.clear()
    open = false
  }

  private fun append(text: String, bold: Boolean, italic: Boolean, strike: Boolean, code: Boolean) {
    if (text.isEmpty()) return
    if (!open) startParagraph()
    val separator = text == "\t" && !bold && !italic && !strike && !code
    val last = spans.lastOrNull()
    val lastIsSeparator = last != null && last.text == "\t" && !last.bold && !last.italic && !last.strike && !last.code
    if (!separator && !lastIsSeparator && last != null && last.bold == bold && last.italic == italic &&
      last.strike == strike && last.code == code) {
      spans[spans.lastIndex] = last.copy(text = last.text + text)
    } else spans += MarkdownSpan(text, bold, italic, strike, code)
  }

  private fun inline(value: String, bold: Boolean, italic: Boolean, strike: Boolean, depth: Int) {
    if (depth >= 16) {
      append(value, bold, italic, strike, false)
      return
    }
    var index = 0
    var start = 0
    while (index < value.length) {
      val ch = value[index]
      if (ch == '[') {
        val finish = bracketEnd(value, index)
        append(value.substring(start, finish.coerceAtMost(value.length)), bold, italic, strike, false)
        index = finish.coerceAtMost(value.length)
        start = index
        continue
      }
      if (ch == '\\' && index + 1 < value.length && value[index + 1] in Escaped) {
        append(value.substring(start, index), bold, italic, strike, false)
        append(value.substring(index + 1, index + 2), bold, italic, strike, false)
        index += 2
        start = index
        continue
      }
      if (ch == '*' || ch == '_' || ch == '~' || ch == '`') {
        val count = runLength(value, index)
        var closing = -1
        val eligible = ch == '`' || ((ch == '*' || ch == '_') && count <= 3) || (ch == '~' && count == 2)
        if (eligible) {
          var finish = index + count
          while (finish < value.length) {
            if (value[finish] == '[' && ch != '`') finish = bracketEnd(value, finish)
            else if (value[finish] == '\\' && ch != '`') finish += 2
            else if (value[finish] == ch) {
              val level = runLength(value, finish)
              val openerTight = index + count < value.length && value[index + count] > ' '
              val closerTight = finish > 0 && value[finish - 1] > ' '
              if (level == count && finish > index + count && (ch == '`' || (openerTight && closerTight))) {
                closing = finish
                break
              }
              finish += level.coerceAtLeast(1)
            } else finish += 1
          }
        }
        if (ch == '_' && closing >= 0) {
          val before = index > 0 && isWord(value[index - 1])
          val after = closing + count < value.length && isWord(value[closing + count])
          if (before || after) closing = -1
        }
        if (closing >= 0) {
          append(value.substring(start, index), bold, italic, strike, false)
          val chunk = value.substring(index + count, closing)
          if (ch == '`') append(chunk, bold, italic, strike, true)
          else {
            val nextBold = bold || ((ch == '*' || ch == '_') && count >= 2)
            val nextItalic = italic || ((ch == '*' || ch == '_') && count != 2)
            val nextStrike = strike || ch == '~'
            inline(chunk, nextBold, nextItalic, nextStrike, depth + 1)
          }
          index = closing + count
          start = index
          continue
        }
        index += count.coerceAtLeast(1)
      } else index += 1
    }
    append(value.substring(start), bold, italic, strike, false)
  }
}

private fun isWord(ch: Char): Boolean = ch.isLetterOrDigit() || ch.code >= 128

private fun runLength(value: String, start: Int): Int {
  if (start >= value.length) return 0
  val ch = value[start]
  var count = 0
  while (start + count < value.length && value[start + count] == ch) count += 1
  return count
}

private fun bracketEnd(value: String, start: Int): Int {
  var result = start
  if (result >= value.length) return value.length
  do {
    val openChar = value[result]
    val closeChar = if (openChar == '[') ']' else ')'
    var level = 1
    result += 1
    while (result < value.length && level > 0) {
      if (value[result] == '\\') {
        result += 2
        if (result > value.length) result = value.length
      } else {
        if (value[result] == openChar) level += 1
        else if (value[result] == closeChar) level -= 1
        result += 1
      }
    }
  } while (result < value.length && (value[result] == '[' || value[result] == '('))
  return result
}

private fun splitTableRow(value: String): List<String>? {
  val line = value.trim()
  if (!line.contains('|')) return null
  val cells = ArrayList<String>()
  var index = 0
  var start = 0
  while (index < line.length) {
    val ch = line[index]
    if (ch == '\\') index += 2
    else if (ch == '`') {
      val count = runLength(line, index)
      var finish = index + count
      while (finish < line.length) {
        if (line[finish] == '`') {
          val level = runLength(line, finish)
          if (level == count) {
            finish += count
            break
          }
          finish += level
        } else finish += 1
      }
      index = if (finish <= line.length) finish else index + count
    } else if (ch == '|') {
      if (index > 0) cells += line.substring(start, index).trim()
      start = index + 1
      index += 1
    } else index += 1
  }
  if (start < line.length) cells += line.substring(start).trim()
  else if (cells.isEmpty()) cells += ""
  return cells
}

private val Escaped = setOf(
  '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/', ':', ';', '<', '=', '>', '?', '@',
  '[', '\\', ']', '^', '_', '`', '{', '|', '}', '~'
)
