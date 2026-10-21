package computing.michell.monitor.protocol

/* fpjson-compatible JSON and envelope field checks (c) 2026 Michell Computing.

   Spacing in toFpJson is the fixture contract. Do not restyle it.
   The wire-type table stays in Messages.kt. This file does not assemble images. */

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

sealed class JsonValue {
  data class Obj(val fields: List<Pair<String, JsonValue>>) : JsonValue()
  data class Arr(val items: List<JsonValue>) : JsonValue()
  data class Str(val text: String) : JsonValue()
  data class Num(val literal: String) : JsonValue()
  data class Bool(val value: Boolean) : JsonValue()
  data object Null : JsonValue()
}

internal class JsonObjectBuilder {
  private val fields = mutableListOf<Pair<String, JsonValue>>()
  fun add(name: String, value: String) { fields += name to JsonValue.Str(value) }
  fun add(name: String, value: Int) { fields += name to JsonValue.Num(value.toString()) }
  fun add(name: String, value: Long) { fields += name to JsonValue.Num(value.toString()) }
  fun add(name: String, value: Boolean) { fields += name to JsonValue.Bool(value) }
  fun add(name: String, value: JsonValue) { fields += name to value }
  fun build(): JsonValue.Obj = JsonValue.Obj(fields.toList())
}

private val JsonParser = Json { isLenient = false }
private val HexDigits = "0123456789ABCDEF"
private val EmptyObject = JsonValue.Obj(emptyList())

internal fun escapeJson(text: String): String {
  val out = StringBuilder(text.length + 8)
  for (ch in text) {
    when (ch) {
      '\\' -> out.append("\\\\")
      '"' -> out.append("\\\"")
      '\b' -> out.append("\\b")
      '\t' -> out.append("\\t")
      '\n' -> out.append("\\n")
      '\u000C' -> out.append("\\f")
      '\r' -> out.append("\\r")
      else -> {
        val code = ch.code
        if (code < 0x20) {
          out.append("\\u00")
          out.append(HexDigits[code shr 4])
          out.append(HexDigits[code and 0x0F])
        } else {
          out.append(ch)
        }
      }
    }
  }
  return out.toString()
}

internal fun JsonValue.toFpJson(): String {
  return when (this) {
    is JsonValue.Obj -> {
      if (fields.isEmpty()) "{}"
      else fields.joinToString(prefix = "{ ", postfix = " }", separator = ", ") { (name, value) ->
        "\"${escapeJson(name)}\" : ${value.toFpJson()}"
      }
    }
    is JsonValue.Arr -> items.joinToString(prefix = "[", postfix = "]", separator = ", ") { it.toFpJson() }
    is JsonValue.Str -> "\"${escapeJson(text)}\""
    is JsonValue.Num -> literal
    is JsonValue.Bool -> if (value) "true" else "false"
    JsonValue.Null -> "null"
  }
}

private fun fromElement(element: JsonElement): JsonValue {
  return when (element) {
    is JsonNull -> JsonValue.Null
    is JsonObject -> JsonValue.Obj(element.entries.map { it.key to fromElement(it.value) })
    is JsonArray -> JsonValue.Arr(element.map { fromElement(it) })
    is JsonPrimitive -> {
      when {
        element.isString -> JsonValue.Str(element.content)
        element.booleanOrNull != null -> JsonValue.Bool(element.booleanOrNull == true)
        else -> JsonValue.Num(element.content)
      }
    }
  }
}

internal var jsonParseCount = 0

internal fun resetJsonParseCount() {
  jsonParseCount = 0
}

internal fun parseJson(text: String): JsonValue? {
  jsonParseCount += 1
  if (text.isEmpty()) return null
  return try {
    fromElement(JsonParser.parseToJsonElement(text))
  } catch (error: Exception) {
    null
  }
}

internal fun jsonTextIsObject(text: String): Boolean = parseJson(text) is JsonValue.Obj

internal fun parseObject(text: String): JsonValue.Obj? = parseJson(text) as? JsonValue.Obj

internal fun JsonValue.Obj.field(name: String): JsonValue? = fields.firstOrNull { it.first == name }?.second

internal fun JsonValue.Obj.has(name: String): Boolean = fields.any { it.first == name }

internal data class ReadString(val ok: Boolean, val value: String)
internal data class ReadInt(val ok: Boolean, val value: Int)
internal data class ReadLong(val ok: Boolean, val value: Long)
internal data class ReadBool(val ok: Boolean, val value: Boolean)

internal fun JsonValue.Obj.readString(name: String, required: Boolean): ReadString {
  val node = field(name)
  if (node == null) return ReadString(!required, "")
  val text = (node as? JsonValue.Str)?.text ?: return ReadString(false, "")
  return ReadString(true, text)
}

private fun integral(literal: String): Long? {
  if (literal.isEmpty() || literal.any { it == '.' || it == 'e' || it == 'E' }) return null
  return literal.toLongOrNull()
}

internal fun JsonValue.Obj.readInt(name: String, required: Boolean): ReadInt {
  val node = field(name)
  if (node == null) return ReadInt(!required, 0)
  val literal = (node as? JsonValue.Num)?.literal ?: return ReadInt(false, 0)
  val number = integral(literal) ?: return ReadInt(false, 0)
  if (number < Int.MIN_VALUE || number > Int.MAX_VALUE) return ReadInt(false, 0)
  return ReadInt(true, number.toInt())
}

internal fun JsonValue.Obj.readLong(name: String, required: Boolean): ReadLong {
  val node = field(name)
  if (node == null) return ReadLong(!required, 0)
  val literal = (node as? JsonValue.Num)?.literal ?: return ReadLong(false, 0)
  val number = integral(literal) ?: return ReadLong(false, 0)
  return ReadLong(true, number)
}

internal fun JsonValue.Obj.readBool(name: String, required: Boolean): ReadBool {
  val node = field(name)
  if (node == null) return ReadBool(!required, false)
  val value = (node as? JsonValue.Bool)?.value ?: return ReadBool(false, false)
  return ReadBool(true, value)
}

fun messageIdIsSafe(id: String): Boolean {
  if (id.isEmpty() || id == "." || id == "..") return false
  if (utf8Length(id) > MonitorLimits.MaxMessageIdChars) return false
  for (ch in id) {
    val ok = ch in 'A'..'Z' || ch in 'a'..'z' || ch in '0'..'9' || ch == '.' || ch == '_' || ch == '-'
    if (!ok) return false
  }
  return true
}

internal class CheckedEnvelope(
  val ok: Boolean,
  val id: String,
  val typeName: String,
  val payload: JsonValue.Obj,
  val payloadJson: String,
  val errorText: String
)

/** Fixed envelope fields only. Payload typing stays with the wire-type table. */
internal fun checkEnvelope(root: JsonValue.Obj): CheckedEnvelope {
  val version = root.readInt("v", true)
  if (!version.ok || version.value != MonitorLimits.CatalogueVersion) {
    return CheckedEnvelope(false, "", "", EmptyObject, "{}", "Unsupported catalogue version.")
  }
  val id = root.readString("id", true)
  if (!id.ok || !messageIdIsSafe(id.value)) {
    return CheckedEnvelope(false, "", "", EmptyObject, "{}", "Message id is not valid.")
  }
  val typeName = root.readString("type", false)
  if (!typeName.ok) {
    return CheckedEnvelope(false, id.value, "", EmptyObject, "{}", "Message type must be a string.")
  }
  val payload = root.field("payload") as? JsonValue.Obj
    ?: return CheckedEnvelope(false, id.value, typeName.value, EmptyObject, "{}", "Message payload must be an object.")
  return CheckedEnvelope(true, id.value, typeName.value, payload, payload.toFpJson(), "")
}
