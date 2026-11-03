package computing.michell.monitor.protocol

/* JVM checks for the catalogue 3 golden fixtures (c) 2026 Michell Computing.

   Plan item 5.1. Reads Tests/Fixtures/Monitor/catalogue.json and every message under
   Tests/Fixtures/Monitor/messages/ straight from the repository, and makes the same checks as
   the Pascal AssistantMonitorProtocolV3Test: envelope, payload fields and kinds, event data,
   state values, closed value sets, frame size, coverage, chunk joining, UTF-8 append offsets and
   the client version on a protocol rejection.
   Shared limits are compared with MonitorLimits. No catalogue 3 codec exists yet; when it does,
   ProtocolCodecTest takes these fixtures over. This test does not write fixture files. */

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ProtocolV3FixtureTest {
  private val root: File = fixtureRoot()
  private val catalogue: JsonValue.Obj = parseObject(File(root, "catalogue.json").readText(Charsets.UTF_8))
    ?: throw AssertionError("catalogue.json is not a JSON object")
  private var problem = ""

  @Test
  fun catalogueIsVersion3WithEverySection() {
    assertEquals("3", (catalogue.field("catalogue") as? JsonValue.Num)?.literal)
    for (name in listOf("limits", "enums", "objects", "types", "events", "state")) {
      assertNotNull("catalogue section $name", catalogue.field(name) as? JsonValue.Obj)
    }
  }

  @Test
  fun everyTypeHasADirectionALaneAndFieldLists() {
    for ((name, value) in section("types").fields) {
      val spec = value as? JsonValue.Obj ?: throw AssertionError("type $name is not an object")
      val direction = text(spec.field("direction"))
      val lane = text(spec.field("lane"))
      assertTrue("type $name direction", enumHas("direction", direction))
      assertTrue("type $name lane", enumHas("lane", lane))
      assertTrue("type $name field lists", spec.field("required") is JsonValue.Obj && spec.field("optional") is JsonValue.Obj)
      // A type only the phone sends has no host lane, and every host type has one.
      assertEquals("type $name lane matches its direction", direction == "phone", lane == "none")
    }
  }

  @Test
  fun sharedLimitsMatchMonitorLimits() {
    assertEquals(MonitorLimits.MaxPayloadBytes.toLong(), limit("max_frame_payload_bytes"))
    assertEquals(MonitorLimits.FrameHeaderSize.toLong(), limit("frame_header_bytes"))
    assertEquals(MonitorLimits.MaxMessageIdChars.toLong(), limit("max_message_id_chars"))
    assertEquals(MonitorLimits.MaxSendChars.toLong(), limit("max_send_chars"))
    assertEquals(MonitorLimits.HeartbeatSilenceMs, limit("heartbeat_ms"))
    assertEquals(MonitorLimits.DeadSessionMs, limit("dead_link_ms"))
    assertEquals(MonitorLimits.PartialFrameMs, limit("partial_frame_ms"))
    assertEquals(MonitorLimits.PairingCodeTtlMs, limit("pair_code_ttl_ms"))
    assertEquals(MonitorLimits.NonceTtlMs, limit("nonce_ttl_ms"))
    assertEquals(MonitorLimits.ApprovalWaitMs, limit("approval_wait_ms"))
    assertEquals(MonitorLimits.MaxImageFetchBytes.toLong(), limit("max_image_fetch_bytes"))
    assertEquals(limit("dead_link_ms"), limit("keepalive_idle_s") * 1000)
    assertEquals(limit("heartbeat_ms"), limit("keepalive_interval_s") * 1000)
  }

  @Test
  fun everyFixtureMatchesTheCatalogue() {
    val files = messageFiles()
    assertTrue("message fixtures found", files.isNotEmpty())
    val seenTypes = mutableSetOf<String>()
    val seenEvents = mutableSetOf<String>()
    val seenKeys = mutableSetOf<String>()
    for (file in files) {
      val message = parseObject(file.readText(Charsets.UTF_8)) ?: throw AssertionError(file.name + " is not a JSON object")
      val expected = file.nameWithoutExtension.substringBefore('-')
      problem = ""
      val good = validateEnvelope(file.name, message, expected)
      assertTrue(file.name + " matches the catalogue: " + problem, good)
      assertTrue(file.name + " fits one outbox frame", file.length() <= limit("outbox_frame_bytes"))
      val type = text(message.field("type"))
      seenTypes += type
      val payload = message.field("payload") as? JsonValue.Obj ?: continue
      if (type == "event") seenEvents += text(payload.field("event"))
      if (type == "state") seenKeys += text(payload.field("key"))
    }
    assertEquals("types without a fixture", emptyList<String>(), section("types").fields.map { it.first }.filter { it !in seenTypes })
    assertEquals("event kinds without a fixture", emptyList<String>(),
      section("events").fields.map { it.first }.filter { it !in seenEvents })
    assertEquals("state keys without a fixture", emptyList<String>(), section("state").fields.map { it.first }.filter { it !in seenKeys })
  }

  /** Spec section 3: an older app must be able to read the rejection that tells it to update. */
  @Test
  fun aProtocolRejectionUsesTheClientVersion() {
    val message = parseObject(File(File(root, "messages"), "rejected-old-client.json").readText(Charsets.UTF_8))
      ?: throw AssertionError("rejected-old-client.json is not a JSON object")
    val payload = message.field("payload") as? JsonValue.Obj ?: throw AssertionError("rejected-old-client.json has no payload")
    assertEquals(longOf(payload.field("client_version")), longOf(message.field("v")))
    assertTrue("the old-client rejection is not version 3", longOf(message.field("v")) != 3L)
  }

  @Test
  fun chunkFixturesJoinIntoAValidMessage() {
    val first = payloadOf("chunk-1.json")
    val second = payloadOf("chunk-2.json")
    assertEquals(text(first.field("item_id")), text(second.field("item_id")))
    assertEquals("1", (first.field("part") as? JsonValue.Num)?.literal)
    assertEquals("2", (second.field("part") as? JsonValue.Num)?.literal)
    assertEquals("2", (first.field("part_count") as? JsonValue.Num)?.literal)
    assertEquals("2", (second.field("part_count") as? JsonValue.Num)?.literal)
    val joined = parseObject(text(first.field("data")) + text(second.field("data")))
      ?: throw AssertionError("joined chunk data is not a JSON object")
    val itemType = text(first.field("item_type"))
    problem = ""
    val good = validateEnvelope("joined chunk", joined, itemType)
    assertTrue("joined chunk data is a valid $itemType message: $problem", good)
    assertTrue("a joined item is not another chunk", text(joined.field("type")) != "chunk")
  }

  @Test
  fun appendOffsetsCountUtf8Bytes() {
    val first = payloadOf("event-block_append-first.json")
    val second = payloadOf("event-block_append-second.json")
    val firstData = first.field("data") as? JsonValue.Obj ?: throw AssertionError("first append has no data")
    val secondData = second.field("data") as? JsonValue.Obj ?: throw AssertionError("second append has no data")
    val firstText = text(firstData.field("text"))
    val firstBytes = firstText.toByteArray(Charsets.UTF_8).size
    assertTrue("the first append text is not ASCII", firstBytes > firstText.length)
    assertEquals(text(firstData.field("block_id")), text(secondData.field("block_id")))
    assertEquals(0L, longOf(firstData.field("offset")))
    assertEquals(firstBytes.toLong(), longOf(secondData.field("offset")))
    assertEquals(longOf(first.field("seq")) + 1, longOf(second.field("seq")))
  }

  private fun fail(text: String): Boolean {
    if (problem.isEmpty()) problem = text
    return false
  }

  private fun section(name: String): JsonValue.Obj =
    catalogue.field(name) as? JsonValue.Obj ?: throw AssertionError("catalogue has no section $name")

  private fun text(value: JsonValue?): String = (value as? JsonValue.Str)?.text ?: ""

  private fun longOf(value: JsonValue?): Long {
    val literal = (value as? JsonValue.Num)?.literal ?: return -1
    if (literal.any { it == '.' || it == 'e' || it == 'E' }) return -1
    return literal.toLongOrNull() ?: -1
  }

  private fun isInteger(value: JsonValue?): Boolean = value is JsonValue.Num && longOf(value) == value.literal.toLongOrNull()

  private fun limit(name: String): Long = longOf(section("limits").field(name))

  private fun enumHas(name: String, value: String): Boolean {
    val list = section("enums").field(name) as? JsonValue.Arr ?: return false
    return list.items.any { it is JsonValue.Str && it.text == value }
  }

  private fun isHex32(text: String): Boolean = text.length == 32 && text.all { it in '0'..'9' || it in 'a'..'f' }

  private fun validateNamed(path: String, value: JsonValue, sectionName: String, name: String): Boolean {
    val spec = section(sectionName).field(name) as? JsonValue.Obj ?: return fail("$path: $sectionName has no \"$name\"")
    val obj = value as? JsonValue.Obj ?: return fail("$path is not an object")
    return validateObject(path, obj, spec)
  }

  /** Owner is the object that holds value. event_data and state_value read their sibling event or key. */
  private fun checkKind(path: String, value: JsonValue, kind: String, owner: JsonValue.Obj?): Boolean {
    val ok = when {
      kind == "string" -> value is JsonValue.Str
      kind == "integer" -> isInteger(value)
      kind == "boolean" -> value is JsonValue.Bool
      kind == "object" -> value is JsonValue.Obj
      kind == "array" -> value is JsonValue.Arr
      kind == "id" -> value is JsonValue.Str && messageIdIsSafe(value.text)
      kind == "hex32" -> value is JsonValue.Str && isHex32(value.text)
      kind == "event_data" -> return validateNamed(path, value, "events", text(owner?.field("event")))
      kind == "state_value" -> return validateNamed(path, value, "state", text(owner?.field("key")))
      kind == "state_map" -> {
        val members = value as? JsonValue.Obj ?: return fail("$path is not an object")
        return members.fields.all { (name, member) -> validateNamed("$path.$name", member, "state", name) }
      }
      kind.startsWith("enum:") -> value is JsonValue.Str && enumHas(kind.removePrefix("enum:"), value.text)
      kind.startsWith("object:") -> return validateNamed(path, value, "objects", kind.removePrefix("object:"))
      kind.startsWith("array:") -> {
        val items = value as? JsonValue.Arr ?: return fail("$path is not an array")
        var itemKind = kind.removePrefix("array:")
        // README: array:<name|string|id>. A bare name is an object in the catalogue.
        if (itemKind != "string" && itemKind != "integer" && itemKind != "boolean" && itemKind != "id" &&
          itemKind != "hex32" && !itemKind.startsWith("enum:") && !itemKind.startsWith("object:")) {
          itemKind = "object:$itemKind"
        }
        return items.items.withIndex().all { (index, item) -> checkKind("$path[$index]", item, itemKind, null) }
      }
      else -> return fail("$path: unknown kind $kind")
    }
    return ok || fail("$path is not $kind")
  }

  private fun validateObject(path: String, obj: JsonValue.Obj, spec: JsonValue.Obj): Boolean {
    val required = spec.field("required") as? JsonValue.Obj ?: return fail("$path: spec has no required")
    val optional = spec.field("optional") as? JsonValue.Obj ?: return fail("$path: spec has no optional")
    for ((name, kind) in required.fields) {
      val found = obj.field(name) ?: return fail("$path.$name is missing")
      if (!checkKind("$path.$name", found, text(kind), obj)) return false
    }
    for ((name, value) in obj.fields) {
      if (required.has(name)) continue
      val kind = optional.field(name) ?: return fail("$path.$name is not in the catalogue")
      if (!checkKind("$path.$name", value, text(kind), obj)) return false
    }
    return true
  }

  private fun validateEnvelope(path: String, message: JsonValue.Obj, expectType: String): Boolean {
    val names = message.fields.map { it.first }
    if (names.sorted() != listOf("id", "payload", "type", "v")) return fail("$path: the envelope must be exactly v, id, type and payload")
    val version = longOf(message.field("v"))
    val type = text(message.field("type"))
    // A protocol rejection is written in the client's version, so an older app can read it (spec section 3).
    if (version != 3L && (type != "rejected" || version !in 1L..2L)) return fail("$path: v is not 3")
    if (!checkKind("$path.id", message.field("id")!!, "id", message)) return false
    val spec = section("types").field(type) as? JsonValue.Obj ?: return fail("$path: type $type is not in the catalogue")
    if (expectType.isNotEmpty() && type != expectType) return fail("$path: type $type does not match $expectType")
    val payload = message.field("payload") as? JsonValue.Obj ?: return fail("$path: payload is not an object")
    return validateObject("$path.payload", payload, spec)
  }

  private fun messageFiles(): List<File> =
    File(root, "messages").listFiles { file -> file.isFile && file.extension == "json" }?.sortedBy { it.name } ?: emptyList()

  private fun payloadOf(name: String): JsonValue.Obj {
    val message = parseObject(File(File(root, "messages"), name).readText(Charsets.UTF_8))
      ?: throw AssertionError("$name is not a JSON object")
    return message.field("payload") as? JsonValue.Obj ?: throw AssertionError("$name has no payload")
  }

  private fun fixtureRoot(): File {
    var dir = File(System.getProperty("user.dir")).absoluteFile
    var remaining = 8
    while (remaining > 0) {
      val fixtures = File(dir, "Tests/Fixtures/Monitor")
      if (fixtures.isDirectory && File(dir, "Source").isDirectory) return fixtures
      dir = dir.parentFile ?: break
      remaining -= 1
    }
    throw AssertionError("Monitor protocol fixtures were not found from " + System.getProperty("user.dir"))
  }
}
