package computing.michell.monitor.net

/* Small JSON reader for the pulse-and-fetch link (c) 2026 Michell Computing.

   The phone does not take a JSON library for this protocol. Values are
   objects, arrays, strings, numbers, booleans and null. */

internal sealed class JsonValue {
  data class Obj(val fields: Map<String, JsonValue>) : JsonValue()
  data class Arr(val values: List<JsonValue>) : JsonValue()
  data class Str(val text: String) : JsonValue()
  data class Num(val text: String) : JsonValue()
  data object Yes : JsonValue()
  data object No : JsonValue()
  data object Null : JsonValue()
}

internal fun parseJson(text: String): JsonValue? {
  return try {
    val parser = JsonParser(text)
    val value = parser.parseValue()
    parser.skipSpace()
    value
  } catch (error: Exception) {
    null
  }
}

internal fun JsonValue.field(name: String): JsonValue? {
  val obj = this as? JsonValue.Obj ?: return null
  return obj.fields[name]
}

internal fun JsonValue.text(name: String, default: String = ""): String {
  return when (val value = field(name)) {
    is JsonValue.Str -> value.text
    is JsonValue.Num -> value.text
    else -> default
  }
}

internal fun JsonValue.long(name: String, default: Long = 0L): Long {
  val value = field(name) ?: return default
  return value.asLong(default)
}

internal fun JsonValue.int(name: String, default: Int = 0): Int = long(name, default.toLong()).toInt()

internal fun JsonValue.bool(name: String, default: Boolean = false): Boolean {
  return when (field(name)) {
    JsonValue.Yes -> true
    JsonValue.No -> false
    else -> default
  }
}

internal fun JsonValue.array(name: String): List<JsonValue> {
  val value = field(name) as? JsonValue.Arr ?: return emptyList()
  return value.values
}

internal fun JsonValue.asText(): String {
  return when (this) {
    is JsonValue.Str -> text
    is JsonValue.Num -> text
    else -> ""
  }
}

internal fun JsonValue.asLong(default: Long = 0L): Long {
  return when (this) {
    is JsonValue.Num -> text.toLongOrNull() ?: default
    is JsonValue.Str -> text.toLongOrNull() ?: default
    else -> default
  }
}

/** Raw JSON for one object field, so plan rows keep the host's encoding. */
internal fun rawJsonField(json: String, key: String): String {
  val needle = "\"$key\""
  val at = json.indexOf(needle)
  if (at < 0) return ""
  var index = json.indexOf(':', at + needle.length)
  if (index < 0) return ""
  index += 1
  while (index < json.length && json[index].isWhitespace()) index += 1
  if (index >= json.length) return ""
  val start = index
  var depth = 0
  var inString = false
  var escape = false
  while (index < json.length) {
    val ch = json[index]
    if (inString) {
      if (escape) escape = false
      else if (ch == '\\') escape = true
      else if (ch == '"') inString = false
      index += 1
      continue
    }
    when (ch) {
      '"' -> inString = true
      '{', '[' -> depth += 1
      '}', ']' -> {
        depth -= 1
        if (depth == 0) return json.substring(start, index + 1)
      }
      ',', '}' -> if (depth == 0) return json.substring(start, index).trim()
    }
    index += 1
  }
  return json.substring(start).trim()
}

private class JsonParser(private val text: String) {
  private var index = 0

  fun parseValue(): JsonValue {
    skipSpace()
    if (index >= text.length) throw IllegalArgumentException("empty")
    return when (text[index]) {
      '{' -> parseObject()
      '[' -> parseArray()
      '"' -> JsonValue.Str(parseString())
      't' -> literal("true", JsonValue.Yes)
      'f' -> literal("false", JsonValue.No)
      'n' -> literal("null", JsonValue.Null)
      else -> parseNumber()
    }
  }

  fun skipSpace() {
    while (index < text.length && text[index].isWhitespace()) index += 1
  }

  private fun parseObject(): JsonValue.Obj {
    index += 1
    val fields = LinkedHashMap<String, JsonValue>()
    skipSpace()
    if (index < text.length && text[index] == '}') {
      index += 1
      return JsonValue.Obj(fields)
    }
    while (index < text.length) {
      skipSpace()
      val name = parseString()
      skipSpace()
      expect(':')
      fields[name] = parseValue()
      skipSpace()
      if (index < text.length && text[index] == ',') {
        index += 1
        continue
      }
      expect('}')
      return JsonValue.Obj(fields)
    }
    throw IllegalArgumentException("object")
  }

  private fun parseArray(): JsonValue.Arr {
    index += 1
    val values = ArrayList<JsonValue>()
    skipSpace()
    if (index < text.length && text[index] == ']') {
      index += 1
      return JsonValue.Arr(values)
    }
    while (index < text.length) {
      values += parseValue()
      skipSpace()
      if (index < text.length && text[index] == ',') {
        index += 1
        continue
      }
      expect(']')
      return JsonValue.Arr(values)
    }
    throw IllegalArgumentException("array")
  }

  private fun parseString(): String {
    expect('"')
    val out = StringBuilder()
    while (index < text.length) {
      val ch = text[index]
      index += 1
      when (ch) {
        '"' -> return out.toString()
        '\\' -> out.append(escape())
        else -> out.append(ch)
      }
    }
    throw IllegalArgumentException("string")
  }

  private fun escape(): Char {
    if (index >= text.length) throw IllegalArgumentException("escape")
    val ch = text[index]
    index += 1
    return when (ch) {
      '"', '\\', '/' -> ch
      'b' -> '\b'
      'f' -> '\u000C'
      'n' -> '\n'
      'r' -> '\r'
      't' -> '\t'
      'u' -> {
        val hex = text.substring(index, (index + 4).coerceAtMost(text.length))
        index += hex.length
        hex.toInt(16).toChar()
      }
      else -> ch
    }
  }

  private fun parseNumber(): JsonValue.Num {
    val start = index
    if (text[index] == '-') index += 1
    while (index < text.length && (text[index].isDigit() || text[index] == '.' || text[index] == 'e' || text[index] == 'E' || text[index] == '+' || text[index] == '-')) {
      index += 1
    }
    if (start == index) throw IllegalArgumentException("number")
    return JsonValue.Num(text.substring(start, index))
  }

  private fun literal(word: String, value: JsonValue): JsonValue {
    if (!text.startsWith(word, index)) throw IllegalArgumentException(word)
    index += word.length
    return value
  }

  private fun expect(ch: Char) {
    if (index >= text.length || text[index] != ch) throw IllegalArgumentException(ch.toString())
    index += 1
  }
}
