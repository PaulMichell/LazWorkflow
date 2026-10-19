package computing.michell.monitor.protocol

/* JVM checks for catalogue version 1 and LAM1 framing (c) 2026 Michell Computing.

   Reads the host fixtures. Does not copy them and does not write fixture files. */

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

    val fixtures = fixtureDirectory()
    assertArrayEquals(readHex(File(fixtures, "hello-first.hex")), firstFrame.bytes)
    assertArrayEquals(readHex(File(fixtures, "hello-reconnect.hex")), tryEncodeFrame(reconnect).bytes)
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
  fun singleImageMatchesTheHostFrame() {
    val tiny = byteArrayOf(1, 2, 3, 4)
    val encoded = tryEncodeImageData("image-data", "tile-1", "image/png", 8, 8, 1, tiny, false, false)
    assertTrue(encoded.ok)
    assertEquals(1, encoded.messages.size)
    val frame = tryEncodeFrame(encoded.messages[0])
    assertTrue(frame.ok)
    assertLam1(frame.bytes, encoded.messages[0].toByteArray(Charsets.UTF_8).size)
    assertArrayEquals(readHex(File(fixtureDirectory(), "image-data.hex")), frame.bytes)
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
    val wire = """{"v":1,"id":"widget-1","type":"widget","payload":{}}"""
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
  fun hostFixturesDecodeAndRewrite() {
    val directory = fixtureDirectory()
    val files = directory.listFiles { file -> file.extension == "hex" }?.sortedBy { it.name } ?: emptyList()
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
    val first = tryDecodeFrame(readHex(File(directory, "hello-first.hex")))
    val hello = decodeHello(tryDecodeEnvelope(first.frame.json).message.payloadJson)
    assertNotNull(hello)
    assertFalse(hello!!.hasClientId)
    val reconnect = tryDecodeFrame(readHex(File(directory, "hello-reconnect.hex")))
    val again = decodeHello(tryDecodeEnvelope(reconnect.frame.json).message.payloadJson)
    assertEquals("client-1", again!!.clientId)
    val image = tryDecodeFrame(readHex(File(directory, "image-data.hex")))
    val part = decodeImageData(tryDecodeEnvelope(image.frame.json).message.payloadJson)
    assertNotNull(part)
    assertEquals(1, part!!.image.part)
    assertEquals(1, part.image.partCount)
    assertEquals(4, part.decodedBytes)
  }

  private fun encodeOneLongSend(): String {
    val text = "y".repeat(MonitorLimits.MaxSendChars + 1)
    val payload = "{\"text\":\"$text\"}"
    return "{\"v\":1,\"id\":\"send-big\",\"type\":\"send\",\"payload\":$payload}"
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
