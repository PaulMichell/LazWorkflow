package computing.michell.monitor.protocol

/* Version 4 command encoder and JSON reader for the shared fixtures.
   (c) 2026 Michell Computing. */

fun monitorCommandRequest(id: String, type: String, argsJson: String): String {
  return """{"id":${jsonQuote(id)},"type":${jsonQuote(type)},"args":$argsJson}"""
}

fun jsonQuote(value: String): String {
  val out = StringBuilder(value.length + 2)
  out.append('"')
  for (ch in value) {
    when (ch) {
      '"', '\\' -> out.append('\\').append(ch)
      '\b' -> out.append("\\b")
      '\t' -> out.append("\\t")
      '\n' -> out.append("\\n")
      '\r' -> out.append("\\r")
      else -> out.append(ch)
    }
  }
  out.append('"')
  return out.toString()
}

/** True when the text is one JSON value the phone can read. */
fun monitorJsonAccepted(text: String): Boolean {
  return parseMonitorJson(text) != null
}

internal sealed class MonitorJson {
  data class Obj(val fields: Map<String, MonitorJson>) : MonitorJson()
  data class Arr(val values: List<MonitorJson>) : MonitorJson()
  data class Str(val text: String) : MonitorJson()
  data class Num(val text: String) : MonitorJson()
  data object Yes : MonitorJson()
  data object No : MonitorJson()
  data object Null : MonitorJson()
}

internal fun parseMonitorJson(text: String): MonitorJson? {
  return try {
    val parser = MonitorJsonParser(text.trim())
    val value = parser.parseValue()
    parser.skipSpace()
    if (parser.ended()) value else null
  } catch (error: Exception) {
    null
  }
}

internal fun MonitorJson.text(name: String): String {
  val obj = this as? MonitorJson.Obj ?: return ""
  return when (val value = obj.fields[name]) {
    is MonitorJson.Str -> value.text
    is MonitorJson.Num -> value.text
    else -> ""
  }
}

internal fun MonitorJson.bool(name: String): Boolean {
  val obj = this as? MonitorJson.Obj ?: return false
  return obj.fields[name] == MonitorJson.Yes
}

private class MonitorJsonParser(private val text: String) {
  private var at = 0

  fun ended(): Boolean = at >= text.length

  fun skipSpace() {
    while (at < text.length && text[at].isWhitespace()) at += 1
  }

  fun parseValue(): MonitorJson {
    skipSpace()
    if (at >= text.length) throw IllegalArgumentException("end")
    return when (text[at]) {
      '{' -> parseObject()
      '[' -> parseArray()
      '"' -> MonitorJson.Str(parseString())
      't' -> literal("true", MonitorJson.Yes)
      'f' -> literal("false", MonitorJson.No)
      'n' -> literal("null", MonitorJson.Null)
      else -> parseNumber()
    }
  }

  private fun parseObject(): MonitorJson {
    expect('{')
    val fields = LinkedHashMap<String, MonitorJson>()
    skipSpace()
    if (peek('}')) {
      at += 1
      return MonitorJson.Obj(fields)
    }
    while (true) {
      skipSpace()
      val name = parseString()
      skipSpace()
      expect(':')
      fields[name] = parseValue()
      skipSpace()
      if (peek('}')) {
        at += 1
        return MonitorJson.Obj(fields)
      }
      expect(',')
    }
  }

  private fun parseArray(): MonitorJson {
    expect('[')
    val values = ArrayList<MonitorJson>()
    skipSpace()
    if (peek(']')) {
      at += 1
      return MonitorJson.Arr(values)
    }
    while (true) {
      values.add(parseValue())
      skipSpace()
      if (peek(']')) {
        at += 1
        return MonitorJson.Arr(values)
      }
      expect(',')
    }
  }

  private fun parseString(): String {
    expect('"')
    val out = StringBuilder()
    while (at < text.length) {
      val ch = text[at]
      at += 1
      if (ch == '"') return out.toString()
      if (ch != '\\') {
        out.append(ch)
        continue
      }
      if (at >= text.length) throw IllegalArgumentException("escape")
      val escaped = text[at]
      at += 1
      out.append(when (escaped) {
        '"', '\\', '/' -> escaped
        'b' -> '\b'
        't' -> '\t'
        'n' -> '\n'
        'r' -> '\r'
        else -> throw IllegalArgumentException("escape")
      })
    }
    throw IllegalArgumentException("string")
  }

  private fun parseNumber(): MonitorJson {
    val start = at
    if (text[at] == '-') at += 1
    while (at < text.length && (text[at].isDigit() || text[at] == '.')) at += 1
    if (at == start) throw IllegalArgumentException("number")
    return MonitorJson.Num(text.substring(start, at))
  }

  private fun literal(word: String, value: MonitorJson): MonitorJson {
    if (!text.startsWith(word, at)) throw IllegalArgumentException(word)
    at += word.length
    return value
  }

  private fun expect(ch: Char) {
    skipSpace()
    if (at >= text.length || text[at] != ch) throw IllegalArgumentException(ch.toString())
    at += 1
  }

  private fun peek(ch: Char): Boolean {
    skipSpace()
    return at < text.length && text[at] == ch
  }
}
