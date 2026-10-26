package computing.michell.monitor.protocol

/* JVM checks for catalogue version 1 and LAM1 framing (c) 2026 Michell Computing.

   Frame bytes are read from the vendored copies under test resources.
   Those copies must match Tests/Fixtures/monitor-frames/ byte for byte.
   This test does not write fixture files. */

import java.io.File
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ProtocolCodecTest {
  @Test
  fun planChoicesUseRefreshAndKeepDesktopCaptionsAndOrder() {
    val request = tryDecodeEnvelope(encodePlanChoices("choices-1")).message
    assertEquals(MessageKind.Refresh, request.kind)
    assertEquals("plan_choices", decodeText(request.payloadJson))
    val base = """{"path":"Documents/Plan.md","title":"Plan","running":false,"rows":[]}"""
    assertNull(decodePlan(base)?.choices)
    assertNotNull(decodePlan(base))
    assertEquals(emptyList<PlanChoice>(), decodePlan(base.dropLast(1) + ""","choices":[]}""")?.choices)
    val choices = ""","choices":[{"path":"Documents/Plan.md","caption":"Plan (Documents/Plan.md)"},
      {"path":"Documents/Überblick.md","caption":"Überblick"}]}"""
    assertEquals(listOf(PlanChoice("Documents/Plan.md", "Plan (Documents/Plan.md)"),
      PlanChoice("Documents/Überblick.md", "Überblick")), decodePlan(base.dropLast(1) + choices)?.choices)
    assertNull(decodePlan(base.dropLast(1) + ""","choices":[42]}"""))
    assertNull(decodePlan(base.dropLast(1) + ""","choices":[{"path":"Plan.md"}]}"""))
    assertNull(decodePlan(base.dropLast(1) + ""","choices":[{"path":"","caption":"Plan"}]}"""))
  }

  @Test
  fun helloShapesMatchTheHostFrames() {
    val first = encodeHello("hello-first", "Phone", "1", "")
    assertFalse(first.contains("client_id"))
    val firstFrame = tryEncodeFrame(first)
    assertTrue(firstFrame.ok)
    assertLam1(firstFrame.bytes, first.toByteArray(Charsets.UTF_8).size)
    val firstHello = decodeHello(tryDecodeEnvelope(first).message.payloadJson)
    assertNotNull(firstHello)
    assertFalse(firstHello!!.hasClientId)

    val reconnect = encodeHello("hello-reconnect", "Phone", "1", "client-1")
    assertTrue(reconnect.contains("client_id"))
    val reconnectHello = decodeHello(tryDecodeEnvelope(reconnect).message.payloadJson)
    assertNotNull(reconnectHello)
    assertTrue(reconnectHello!!.hasClientId)
    assertEquals("client-1", reconnectHello.clientId)

    assertArrayEquals(readVendored("hello-first.hex"), firstFrame.bytes)
    assertArrayEquals(readVendored("hello-reconnect.hex"), tryEncodeFrame(reconnect).bytes)
  }

  @Test
  fun imageDataPartsReassemble() {
    val bytes = ByteArray(MonitorLimits.MaxImagePartBytes + 16)
    for (index in bytes.indices) bytes[index] = ((index * 17 + 3) and 0xFF).toByte()
    val encoded = tryEncodeImageData("image-parts", "tile-1", "image/png", 8, 8, 4, bytes, false, false)
    assertTrue(encoded.ok)
    assertEquals("", encoded.unavailableReason)
    assertEquals(2, encoded.messages.size)
    val assembly = ImageAssembly()
    var joined: ByteArray? = null
    encoded.messages.forEachIndexed { index, json ->
      val envelope = tryDecodeEnvelope(json)
      assertTrue(envelope.ok)
      assertEquals(MessageKind.ImageData, envelope.message.kind)
      val image = decodeImageData(envelope.message.payloadJson)
      assertNotNull(image)
      assertEquals(index + 1, image!!.image.part)
      assertEquals(2, image.image.partCount)
      assertEquals(4, image.image.revision)
      val raw = decodeImageBytes(image.image.bytesBase64)
      assertNotNull(raw)
      assertEquals(image.decodedBytes, raw!!.size)
      joined = assembly.accept(image.image, raw)
    }
    assertNotNull(joined)
    assertArrayEquals(bytes, joined)
  }

  @Test
  fun hostileImagePartsAreRejectedOnTheCrossingPart() {
    val assembly = ImageAssembly()
    val chunk = MonitorLimits.MaxImagePartBytes
    for (index in 1..5) {
      assertNull(assembly.accept(imagePart("hot", index, 6), ByteArray(chunk), 0L))
    }
    assertNull(assembly.accept(imagePart("hot", 6, 6), ByteArray(chunk), 0L))
    assertNull(assembly.accept(imagePart("hot", 6, 6), ByteArray(1), 0L))
    val rejected = ImageAssembly()
    assertNull(rejected.accept(imagePart("count", 1, 100), ByteArray(1), 0L))
    assertNull(rejected.accept(imagePart("count", 1, Int.MAX_VALUE), ByteArray(1), 0L))
    assertArrayEquals(ByteArray(3), rejected.accept(imagePart("ok", 1, 1), ByteArray(3), 0L))
  }

  @Test
  fun duplicateImagePartsDoNotDoubleCount() {
    val assembly = ImageAssembly()
    assertNull(assembly.accept(imagePart("dup", 1, 2), ByteArray(10) { 1 }, 0L))
    assertNull(assembly.accept(imagePart("dup", 1, 2), ByteArray(10) { 2 }, 0L))
    val joined = assembly.accept(imagePart("dup", 2, 2), ByteArray(4) { 3 }, 0L)
    assertNotNull(joined)
    assertEquals(14, joined!!.size)
    assertEquals(2.toByte(), joined[0])
    assertEquals(3.toByte(), joined[10])
  }

  @Test
  fun secondImageDoesNotEraseTheFirstOrRaiseTheByteCap() {
    val assembly = ImageAssembly()
    val chunk = MonitorLimits.MaxImagePartBytes
    val remainder = MonitorLimits.MaxImageFetchBytes - 5 * chunk
    for (index in 1..5) {
      assertNull(assembly.accept(imagePart("a", index, 6), ByteArray(chunk), 0L))
    }
    assertNull(assembly.accept(imagePart("b", 1, 1), ByteArray(chunk), 0L))
    val completed = assembly.accept(imagePart("a", 6, 6), ByteArray(remainder), 0L)
    assertNotNull(completed)
    assertEquals(MonitorLimits.MaxImageFetchBytes, completed!!.size)
    val kept = ImageAssembly()
    assertNull(kept.accept(imagePart("a", 1, 2), ByteArray(100), 0L))
    assertNull(kept.accept(imagePart("b", 1, 2), ByteArray(80), 0L))
    assertNull(kept.accept(imagePart("a", 1, 2, revision = 2), ByteArray(20), 0L))
    val first = kept.accept(imagePart("a", 2, 2), ByteArray(50), 0L)
    assertNotNull(first)
    assertEquals(150, first!!.size)
    val second = kept.accept(imagePart("b", 2, 2), ByteArray(40), 0L)
    assertNotNull(second)
    assertEquals(120, second!!.size)
  }

  @Test
  fun inconsistentImageMetadataIsRejected() {
    assertMetadataDropped(imagePart("a", 2, 2, mime = "image/jpeg"))
    assertMetadataDropped(imagePart("a", 2, 2, width = 9))
    assertMetadataDropped(imagePart("a", 2, 2, height = 3))
    assertMetadataDropped(imagePart("a", 2, 3))
  }

  @Test
  fun expiredImagePartialDoesNotComplete() {
    val assembly = ImageAssembly()
    assertNull(assembly.accept(imagePart("old", 1, 2), byteArrayOf(9, 9, 9, 9), 0L))
    val late = assembly.accept(imagePart("old", 2, 2), byteArrayOf(1), MonitorLimits.ImageAssemblyTtlMs)
    assertNull(late)
    val fresh = ImageAssembly()
    assertNull(fresh.accept(imagePart("old", 1, 2), byteArrayOf(2), MonitorLimits.ImageAssemblyTtlMs))
    assertArrayEquals(byteArrayOf(2, 3), fresh.accept(imagePart("old", 2, 2), byteArrayOf(3), MonitorLimits.ImageAssemblyTtlMs))
    val stillOpen = ImageAssembly()
    assertNull(stillOpen.accept(imagePart("live", 1, 2), byteArrayOf(4), 0L))
    val joined = stillOpen.accept(imagePart("live", 2, 2), byteArrayOf(5), MonitorLimits.ImageAssemblyTtlMs - 1)
    assertArrayEquals(byteArrayOf(4, 5), joined)
  }

  @Test
  fun ninthOpenImageDoesNotEraseTheFirst() {
    val assembly = ImageAssembly()
    for (index in 1..MonitorLimits.MaxOpenImageAssemblies) {
      assertNull(assembly.accept(imagePart("img$index", 1, 2), ByteArray(2), 0L))
    }
    assertNull(assembly.accept(imagePart("extra", 1, 1), ByteArray(2), 0L))
    val first = assembly.accept(imagePart("img1", 2, 2), ByteArray(1), 0L)
    assertNotNull(first)
    assertEquals(3, first!!.size)
  }

  @Test
  fun desktopChunkImageStillAssembles() {
    val assembly = ImageAssembly()
    val chunk = MonitorLimits.MaxImagePartBytes
    val last = MonitorLimits.MaxImageFetchBytes - 5 * chunk
    assertTrue(last > 0)
    assertTrue(last <= chunk)
    var joined: ByteArray? = null
    for (index in 1..6) {
      val size = if (index < 6) chunk else last
      val bytes = ByteArray(size)
      bytes[0] = index.toByte()
      joined = assembly.accept(imagePart("desk", index, 6), bytes, 0L)
      if (index < 6) assertNull(joined)
    }
    assertNotNull(joined)
    assertEquals(MonitorLimits.MaxImageFetchBytes, joined!!.size)
    assertEquals(1.toByte(), joined[0])
    assertEquals(6.toByte(), joined[5 * chunk])
  }

  private fun assertMetadataDropped(changed: ImageData) {
    val assembly = ImageAssembly()
    assertNull(assembly.accept(imagePart("a", 1, 2), ByteArray(4), 0L))
    assertNull(assembly.accept(changed, ByteArray(4), 0L))
    assertNull(assembly.accept(imagePart("a", 2, 2), ByteArray(4), 0L))
  }

  @Test
  fun singleImageMatchesTheHostFrame() {
    val tiny = byteArrayOf(1, 2, 3, 4)
    val encoded = tryEncodeImageData("image-data", "tile-1", "image/png", 8, 8, 1, tiny, false, false)
    assertTrue(encoded.ok)
    assertEquals(1, encoded.messages.size)
    val frame = tryEncodeFrame(encoded.messages[0])
    assertTrue(frame.ok)
    assertLam1(frame.bytes, encoded.messages[0].toByteArray(Charsets.UTF_8).size)
    assertArrayEquals(readVendored("image-data.hex"), frame.bytes)
  }

  @Test
  fun missingImageDoesNotCloseTheCatalogue() {
    val encoded = tryEncodeImageData("image-missing", "tile-1", "image/png", 1, 1, 1, ByteArray(0), true, false)
    assertTrue(encoded.ok)
    assertTrue(encoded.messages.isEmpty())
    assertEquals("missing", encoded.unavailableReason)
    val tooLarge = ByteArray(MonitorLimits.MaxImageFetchBytes + 1)
    val blocked = tryEncodeImageData("image-big", "tile-1", "image/png", 1, 1, 1, tooLarge, false, false)
    assertTrue(blocked.ok)
    assertEquals("too_large", blocked.unavailableReason)
  }

  @Test
  fun unknownTypeDoesNotChangeSessionState() {
    val session = SessionState()
    session.onHandshakeComplete()
    assertEquals(SessionPhase.Accepted, session.phase)
    val wire = """{"v":${MonitorLimits.CatalogueVersion},"id":"widget-1","type":"widget","payload":{}}"""
    val decoded = tryDecodeEnvelope(wire)
    assertTrue(decoded.ok)
    assertEquals(UnknownTypeReason, decoded.message.reason)
    assertFalse(decoded.message.changesState)
    assertEquals(MessageKind.Error, decoded.message.kind)
    assertTrue(decoded.message.wireJson.contains("unknown_type"))
    session.apply(decoded.message)
    assertEquals(SessionPhase.Accepted, session.phase)
    assertFalse(session.outboundAllowed(MessageKind.Send))
    assertTrue(session.outboundAllowed(MessageKind.Hello))
  }

  @Test
  fun textLimitDoesNotChangeSessionState() {
    val session = SessionState()
    session.onHandshakeComplete()
    val huge = "x".repeat(MonitorLimits.MaxSendChars + 1)
    val encoded = tryEncodeSend("send-1", huge)
    assertFalse(encoded.ok)
    assertTrue(encoded.errorJson.contains(PayloadTooLargeReason))
    val inbound = encodeOneLongSend()
    val decoded = tryDecodeEnvelope(inbound)
    assertTrue(decoded.ok)
    assertFalse(decoded.message.changesState)
    session.apply(decoded.message)
    assertEquals(SessionPhase.Accepted, session.phase)
  }

  @Test
  fun framingRejectsBadVersionShortTooLargeAndNonUtf8() {
    val short = tryDecodeFrame(byteArrayOf(0x4C, 0x41, 0x4D))
    assertFalse(short.ok)
    assertEquals(FrameStatus.Short, short.status)
    assertEquals(FrameStatus.NeedMore, tryConsumeFrame(byteArrayOf(0x4C, 0x41)).status)

    val badVersion = ByteArray(MonitorLimits.FrameHeaderSize)
    badVersion[0] = 'L'.code.toByte()
    badVersion[1] = 'A'.code.toByte()
    badVersion[2] = 'M'.code.toByte()
    badVersion[3] = '1'.code.toByte()
    badVersion[4] = 2
    assertEquals(FrameStatus.BadVersion, tryDecodeFrame(badVersion).status)

    val tooLarge = ByteArray(MonitorLimits.FrameHeaderSize)
    tooLarge[0] = 'L'.code.toByte()
    tooLarge[1] = 'A'.code.toByte()
    tooLarge[2] = 'M'.code.toByte()
    tooLarge[3] = '1'.code.toByte()
    tooLarge[4] = 1
    val length = MonitorLimits.MaxPayloadBytes + 1
    tooLarge[8] = (length ushr 24).toByte()
    tooLarge[9] = (length ushr 16).toByte()
    tooLarge[10] = (length ushr 8).toByte()
    tooLarge[11] = length.toByte()
    val inspected = tryInspectFrameHeader(tooLarge)
    assertEquals(FrameStatus.TooLarge, inspected.status)
    assertFalse(inspected.ok)
    assertEquals(FrameStatus.TooLarge, tryConsumeFrame(tooLarge).status)

    val badUtf8 = ByteArray(MonitorLimits.FrameHeaderSize + 1)
    badUtf8[0] = 'L'.code.toByte()
    badUtf8[1] = 'A'.code.toByte()
    badUtf8[2] = 'M'.code.toByte()
    badUtf8[3] = '1'.code.toByte()
    badUtf8[4] = 1
    badUtf8[11] = 1
    badUtf8[12] = 0xFF.toByte()
    assertEquals(FrameStatus.BadUtf8, tryDecodeFrame(badUtf8).status)
  }

  @Test
  fun pairOkEntersLiveAndRejectedCloses() {
    val session = SessionState()
    session.onHandshakeComplete()
    val pairOk = encodePairOk("pair-ok", "client-1", "token-1")
    session.apply(tryDecodeEnvelope(pairOk).message)
    assertEquals(SessionPhase.Live, session.phase)
    val rejected = encodeRejected("rejected", "revoked", 1, 1)
    session.apply(tryDecodeEnvelope(rejected).message)
    assertEquals(SessionPhase.Closed, session.phase)
    assertFalse(session.outboundAllowed(MessageKind.Ping))
  }

  @Test
  fun catalogueV2RoundTrips() {
    val resume = encodeResume("resume", "abc123", 4)
    val resumeBody = decodeResume(tryDecodeEnvelope(resume).message.payloadJson)
    assertNotNull(resumeBody)
    assertEquals("abc123", resumeBody!!.epoch)
    assertEquals(4L, resumeBody.cursor)

    val block = WireBlock("answer", "block-1", "Answer", "", "", "Noted.", false, true, 12, emptyList())
    val patch = samplePatch(listOf(block))
    val encodedPatch = encodePatch("patch", patch)
    val decodedPatch = decodePatch(tryDecodeEnvelope(encodedPatch).message.payloadJson)
    assertNotNull(decodedPatch)
    assertEquals(patch, decodedPatch)
    assertNull(decodePatch("""{"turn_index":1,"revision":2,"part":1,"part_count":1,"phase":"streaming","status_text":"Writing","duration_ms":1,"blocks":[]}"""))

    val closed = encodeConversationClosed("conversation-closed", "abc123", 4, "conversation-20261019T120000000", "Monitor plan")
    val closedBody = decodeConversationClosed(tryDecodeEnvelope(closed).message.payloadJson)
    assertEquals("conversation-20261019T120000000", closedBody!!.conversationId)
    assertEquals(4L, closedBody.cursor)

    val events = encodeCatchup("catchup-events", WireCatchup("events", "abc123", 4, "current", "/work/LazWorkflow",
      "Monitor plan", null, listOf(patch)))
    val eventsBody = decodeCatchup(tryDecodeEnvelope(events).message.payloadJson)
    assertEquals("events", eventsBody!!.mode)
    assertEquals(listOf(patch), eventsBody.patches)

    val snapshot = WireSnapshot(sampleView(), emptyList(), null, "Documents/Plan.md", "Monitor plan", false,
      emptyList(), emptyList(), ApprovalNotice(false, "", "", "", "", false))
    val snap = encodeCatchup("catchup-snapshot", WireCatchup("snapshot", "abc123", 4, "current", "/work/LazWorkflow",
      "Monitor plan", snapshot, emptyList()))
    val snapBody = decodeCatchup(tryDecodeEnvelope(snap).message.payloadJson)
    assertEquals("snapshot", snapBody!!.mode)
    assertEquals("Monitor plan", snapBody.snapshot!!.planTitle)
    assertEquals(4L, snapBody.cursor)

    val old = """{"v":1,"id":"old-patch","type":"patch","payload":{"epoch":"abc123","cursor":1,"turn_index":0,"turn_id":"t","part":1,"part_count":1,"busy":false,"sending":false,"plan_running":false,"phase":"","can_send":true,"can_steer":false,"can_stop":false,"elapsed_ms":0,"blocks":[]}}"""
    val rejected = tryDecodeEnvelope(old)
    assertFalse(rejected.ok)
    assertTrue(rejected.errorText.contains("version"))
  }

  @Test
  fun patchOverCapMissingPartIsNotSuccess() {
    val left = WireBlock("answer", "block-a", "Answer", "", "", "a".repeat(150000), false, true, 12, emptyList())
    val right = WireBlock("answer", "block-b", "Answer", "", "", "b".repeat(150000), false, true, 12, emptyList())
    val messages = packPatch("patch-over", samplePatch(listOf(left, right)))
    assertTrue(messages.size >= 2)
    messages.forEachIndexed { index, json ->
      val envelope = tryDecodeEnvelope(json)
      assertTrue(envelope.ok)
      assertEquals(MessageKind.Patch, envelope.message.kind)
      val part = decodePatch(envelope.message.payloadJson)
      assertNotNull(part)
      assertEquals(9L, part!!.cursor)
      assertEquals(index + 1, part.part)
      assertEquals(messages.size, part.partCount)
    }
    val assembled = assemblePatch(messages)
    assertNotNull(assembled)
    assertEquals(listOf(left.body, right.body), assembled!!.blocks.map { it.body })
    assertNull(assemblePatch(messages.dropLast(1)))
  }

  @Test
  fun vendoredFramesMatchPascalFixtures() {
    val vendored = filesByName(vendoredDirectory())
    val pascal = filesByName(fixtureDirectory())
    assertEquals(pascal.keys.sorted(), vendored.keys.sorted())
    for (name in pascal.keys) {
      assertArrayEquals(name, pascal.getValue(name), vendored.getValue(name))
    }
  }

  @Test
  fun vendoredFramesDecodeAndRewrite() {
    val files = vendoredDirectory().listFiles { file -> file.extension == "hex" }?.sortedBy { it.name } ?: emptyList()
    assertTrue(files.isNotEmpty())
    for (file in files) {
      val bytes = readHex(file)
      val decoded = tryDecodeFrame(bytes)
      assertTrue(file.name + " frame", decoded.ok)
      assertLam1(bytes, decoded.frame.json.toByteArray(Charsets.UTF_8).size)
      val rewritten = parseJson(decoded.frame.json)?.toFpJson()
      assertEquals(file.name, decoded.frame.json, rewritten)
      val envelope = tryDecodeEnvelope(decoded.frame.json)
      assertTrue(file.name + " envelope " + envelope.errorText, envelope.ok)
      assertEquals(MonitorLimits.CatalogueVersion, envelope.message.version)
    }
    val first = tryDecodeFrame(readVendored("hello-first.hex"))
    val hello = decodeHello(tryDecodeEnvelope(first.frame.json).message.payloadJson)
    assertNotNull(hello)
    assertFalse(hello!!.hasClientId)
    val reconnect = tryDecodeFrame(readVendored("hello-reconnect.hex"))
    val again = decodeHello(tryDecodeEnvelope(reconnect.frame.json).message.payloadJson)
    assertEquals("client-1", again!!.clientId)
    val image = tryDecodeFrame(readVendored("image-data.hex"))
    val part = decodeImageData(tryDecodeEnvelope(image.frame.json).message.payloadJson)
    assertNotNull(part)
    assertEquals(1, part!!.image.part)
    assertEquals(1, part.image.partCount)
    assertEquals(4, part.decodedBytes)
  }

  @Test
  fun inboundImageIsDecodedOnceAndSessionDoesNotKeepTheBytes() {
    val bytes = readVendored("image-data.hex")
    resetJsonParseCount()
    val frame = tryDecodeFrame(bytes)
    assertTrue(frame.ok)
    assertEquals(1, jsonParseCount)
    val envelope = tryDecodeEnvelope(frame.frame)
    assertTrue(envelope.ok)
    assertEquals(1, jsonParseCount)
    val image = envelope.message.inbound as? InboundPayload.ImagePart
    assertNotNull(image)
    assertEquals(4, image!!.bytes.size)
    val session = SessionState()
    session.apply(envelope.message)
    assertEquals(0, session.retainedImageBytes())
    val assembly = ImageAssembly()
    assertNotNull(assembly.accept(image.image, image.bytes))
  }

  @Test
  fun inboundTranscriptCarriesBlocksWithoutASecondJoin() {
    val block = WireBlock("answer", "b1", "", "", "", "Hello", false, true, 0, emptyList(), false, 1, 1, 2)
    val encoded = tryEncodeTranscript("tr", WireTranscript(1, 2, "thinking", "working", listOf(block)))
    val envelope = tryDecodeEnvelope(encoded)
    val part = envelope.message.inbound as? InboundPayload.TranscriptPart
    assertNotNull(part)
    assertEquals(listOf(block.body), part!!.value.blocks.map { it.body })
    val joined = assembleTranscriptBlocks(listOf(part.value.blocks))
    assertEquals("Hello", joined.single().body)
    val session = SessionState()
    session.apply(envelope.message)
    assertEquals(2, session.liveRevision)
    assertEquals(0, session.retainedImageBytes())
  }

  private fun sampleView(): WireView {
    return WireView(true, false, false, false, false, "idle", "Ready", "grok-test", "native", true, "Ask", "high", "",
      "ctx", true, false, false, true, false, "")
  }

  private fun samplePatch(blocks: List<WireBlock>): WirePatch {
    return WirePatch("abc123", 9, 3, "turn-3", blocks, true, true, false, "streaming", false, true, true, 50)
  }

  private fun imagePart(
    id: String,
    part: Int,
    partCount: Int,
    revision: Int = 1,
    mime: String = "image/png",
    width: Int = 8,
    height: Int = 8
  ): ImageData {
    return ImageData(id, mime, width, height, part, partCount, revision, "")
  }

  private fun encodeOneLongSend(): String {
    val text = "y".repeat(MonitorLimits.MaxSendChars + 1)
    val payload = "{\"text\":\"$text\"}"
    return "{\"v\":${MonitorLimits.CatalogueVersion},\"id\":\"send-big\",\"type\":\"send\",\"payload\":$payload}"
  }

  private fun assertLam1(bytes: ByteArray, payloadLength: Int) {
    assertTrue(bytes.size >= MonitorLimits.FrameHeaderSize)
    assertEquals('L'.code.toByte(), bytes[0])
    assertEquals('A'.code.toByte(), bytes[1])
    assertEquals('M'.code.toByte(), bytes[2])
    assertEquals('1'.code.toByte(), bytes[3])
    assertEquals(MonitorLimits.FrameVersion, bytes[4].toInt() and 0xFF)
    assertEquals(0, bytes[5].toInt() and 0xFF)
    assertEquals(0, bytes[6].toInt() and 0xFF)
    assertEquals(0, bytes[7].toInt() and 0xFF)
    assertEquals(payloadLength.toLong(), readBigEndianLength(bytes))
    assertEquals((payloadLength ushr 24) and 0xFF, bytes[8].toInt() and 0xFF)
    assertEquals(payloadLength and 0xFF, bytes[11].toInt() and 0xFF)
  }

  private fun vendoredDirectory(): File {
    val resource = javaClass.classLoader.getResource("frames/hello-first.hex")
      ?: throw AssertionError("Vendored frame frames/hello-first.hex is not on the test classpath.")
    val dir = File(resource.toURI()).parentFile
    if (dir == null || !dir.isDirectory) {
      throw AssertionError("Vendored frames are not a directory.")
    }
    return dir
  }

  private fun readVendored(name: String): ByteArray {
    return readHex(File(vendoredDirectory(), name))
  }

  private fun filesByName(directory: File): Map<String, ByteArray> {
    val files = directory.listFiles { file -> file.isFile && file.extension == "hex" } ?: emptyArray()
    assertTrue(directory.path + " has no frame fixtures", files.isNotEmpty())
    return files.associate { it.name to it.readBytes() }
  }

  private fun fixtureDirectory(): File {
    var dir = File(System.getProperty("user.dir")).absoluteFile
    var remaining = 8
    while (remaining > 0) {
      val fixtures = File(dir, "Tests/Fixtures/monitor-frames")
      if (fixtures.isDirectory && File(dir, "Source").isDirectory) return fixtures
      dir = dir.parentFile ?: break
      remaining -= 1
    }
    throw AssertionError("Host frame fixtures were not found from " + System.getProperty("user.dir"))
  }

  private fun readHex(file: File): ByteArray {
    val hex = file.readText().filter { !it.isWhitespace() }
    assertEquals(0, hex.length % 2)
    return ByteArray(hex.length / 2) { index ->
      hex.substring(index * 2, index * 2 + 2).toInt(16).toByte()
    }
  }
}
