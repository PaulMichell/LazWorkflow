package computing.michell.monitor.protocol

/* Bounded frame reads without copying the pending prefix (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class FrameAssemblerTest {
  @Test
  fun maxFrameInEightKibChunksStaysWithinTheBound() {
    val frame = maxPayloadFrame()
    val assembler = FrameAssembler()
    val chunk = FrameAssembler.ReadChunkBytes
    assertEquals(8192, chunk)
    assertEquals(MonitorLimits.FrameHeaderSize + MonitorLimits.MaxPayloadBytes + chunk, assembler.bound)

    var offset = 0
    var storage: ByteArray? = null
    var quadratic = 0L
    var pending = 0
    while (offset < frame.size) {
      val count = minOf(chunk, frame.size - offset)
      val batch = assembler.offer(frame, offset, count, 1_000L)
      pending += count
      quadratic += pending
      assertTrue(assembler.pendingSize <= assembler.bound)
      assertTrue(assembler.pendingCapacity <= assembler.bound)
      assertTrue(assembler.highWater <= assembler.bound)
      if (storage == null) storage = assembler.pendingStorage
      else assertSame(storage, assembler.pendingStorage)
      offset += count
      if (offset < frame.size) {
        assertEquals(FrameStatus.Ok, batch.status)
        assertTrue(batch.frames.isEmpty())
      } else {
        assertEquals(FrameStatus.Ok, batch.status)
        assertEquals(1, batch.frames.size)
        assertEquals(MonitorLimits.MaxPayloadBytes, batch.frames[0].json.toByteArray(Charsets.UTF_8).size)
        assertTrue(batch.frames[0].json.startsWith("{\"pad\":\""))
      }
    }
    // Concatenating each chunk onto the prefix copies about 4 MiB. Filling by offset does not.
    assertTrue(quadratic > 4_000_000L)
    assertTrue(assembler.copiedBytes * 4 < quadratic)
    assertEquals(frame.size.toLong(), assembler.copiedBytes)
    assertEquals(frame.size, assembler.highWater)
    assertEquals(0, assembler.pendingSize)
    assertEquals(0L, assembler.partialSinceMs)
    assertFalse(assembler.partialExpired(1_000L + MonitorLimits.PartialFrameMs))
    assertSame(storage, assembler.pendingStorage)
  }

  @Test
  fun completingChunkHoldsOneReadOfTheNextFrame() {
    val frame = maxPayloadFrame()
    val assembler = FrameAssembler()
    val chunk = FrameAssembler.ReadChunkBytes
    val started = 2_000L
    val keep = frame.size - 1
    var offset = 0
    var storage: ByteArray? = null
    while (offset < keep) {
      val count = minOf(chunk, keep - offset)
      val at = if (offset == 0) started else started + 5_000L
      assembler.offer(frame, offset, count, at)
      if (storage == null) storage = assembler.pendingStorage
      else assertSame(storage, assembler.pendingStorage)
      offset += count
    }
    assertEquals(started, assembler.partialSinceMs)
    assertFalse(assembler.partialExpired(started + MonitorLimits.PartialFrameMs - 1))

    val tail = ByteArray(chunk)
    frame.copyInto(tail, 0, frame.size - 1, frame.size)
    frame.copyInto(tail, 1, 0, chunk - 1)
    val resetAt = started + MonitorLimits.PartialFrameMs - 1
    val batch = assembler.offer(tail, 0, chunk, resetAt)
    assertEquals(FrameStatus.Ok, batch.status)
    assertEquals(1, batch.frames.size)
    assertEquals(chunk - 1, assembler.pendingSize)
    assertTrue(assembler.pendingCapacity <= assembler.bound)
    assertTrue(assembler.highWater <= assembler.bound)
    assertEquals(assembler.bound - 1, assembler.highWater)
    assertSame(storage, assembler.pendingStorage)
    assertEquals(resetAt, assembler.partialSinceMs)
    // The old clock started at `started` and would already have expired.
    assertFalse(assembler.partialExpired(started + MonitorLimits.PartialFrameMs))
    assertFalse(assembler.partialExpired(resetAt + MonitorLimits.PartialFrameMs - 1))
    assertTrue(assembler.partialExpired(resetAt + MonitorLimits.PartialFrameMs))
  }

  @Test
  fun coalescedSingleReadConsumesOneFrame() {
    val frame = encoded(encodeTicks(MessageKind.Pong, "solo", 7))
    val assembler = FrameAssembler()
    val batch = assembler.offer(frame, 0, frame.size, 50L)
    assertEquals(FrameStatus.Ok, batch.status)
    assertEquals(1, batch.frames.size)
    val envelope = tryDecodeEnvelope(batch.frames[0])
    assertTrue(envelope.ok)
    assertEquals(MessageKind.Pong, envelope.message.kind)
    assertEquals(7L, decodeTicks(envelope.message.payloadJson)?.ticks)
    assertEquals(0, assembler.pendingSize)
    assertEquals(0L, assembler.partialSinceMs)
    assertFalse(assembler.partialExpired(50L + MonitorLimits.PartialFrameMs))
    assertTrue(assembler.highWater <= assembler.bound)
    assertTrue(assembler.pendingCapacity <= assembler.bound)
    assertEquals(frame.size.toLong(), assembler.copiedBytes)

    val first = encoded(encodeTicks(MessageKind.Ping, "one", 1))
    val second = encoded(encodeTicks(MessageKind.Ping, "two", 2))
    val both = first + second
    val paired = FrameAssembler()
    val pair = paired.offer(both, 0, both.size, 60L)
    assertEquals(2, pair.frames.size)
    assertEquals(0, paired.pendingSize)
    assertEquals(0L, paired.partialSinceMs)
    assertEquals(1L, decodeTicks(tryDecodeEnvelope(pair.frames[0]).message.payloadJson)?.ticks)
    assertEquals(2L, decodeTicks(tryDecodeEnvelope(pair.frames[1]).message.payloadJson)?.ticks)
  }

  @Test
  fun splitAcrossTwoFramesResetsThePartialClock() {
    val first = encoded(encodeTicks(MessageKind.Ping, "one", 1))
    val second = encoded(encodeTicks(MessageKind.Ping, "two", 2))
    val assembler = FrameAssembler()
    val started = 5_000L
    val split = first.size / 2
    assertTrue(split >= MonitorLimits.FrameHeaderSize)
    val opened = assembler.offer(first, 0, split, started)
    assertTrue(opened.frames.isEmpty())
    assertEquals(started, assembler.partialSinceMs)
    val storage = assembler.pendingStorage

    val resetAt = started + MonitorLimits.PartialFrameMs - 1
    val rest = first.size - split
    val prefix = 4
    val mixed = ByteArray(rest + prefix)
    first.copyInto(mixed, 0, split, first.size)
    second.copyInto(mixed, rest, 0, prefix)
    val batch = assembler.offer(mixed, 0, mixed.size, resetAt)
    assertEquals(FrameStatus.Ok, batch.status)
    assertEquals(1, batch.frames.size)
    assertEquals(1L, decodeTicks(tryDecodeEnvelope(batch.frames[0]).message.payloadJson)?.ticks)
    assertEquals(prefix, assembler.pendingSize)
    assertSame(storage, assembler.pendingStorage)
    assertEquals(resetAt, assembler.partialSinceMs)
    assertFalse(assembler.partialExpired(started + MonitorLimits.PartialFrameMs))
    assertTrue(assembler.partialExpired(resetAt + MonitorLimits.PartialFrameMs))

    val finished = assembler.offer(second, prefix, second.size - prefix, resetAt + 10)
    assertEquals(1, finished.frames.size)
    assertEquals(2L, decodeTicks(tryDecodeEnvelope(finished.frames[0]).message.payloadJson)?.ticks)
    assertEquals(0, assembler.pendingSize)
    assertEquals(0L, assembler.partialSinceMs)
  }

  @Test
  fun backwardStepDoesNotExpireAPartialFrame() {
    val frame = encoded(encodeTicks(MessageKind.Ping, "slow", 3))
    val assembler = FrameAssembler()
    val started = 50_000L
    assembler.offer(frame, 0, 8, started)
    assertTrue(assembler.pendingSize > 0)
    assertFalse(assembler.partialExpired(started - 60_000L))
    assertFalse(assembler.partialExpired(0L))
    assertFalse(assembler.partialExpired(started + MonitorLimits.PartialFrameMs - 1))
    assertTrue(assembler.partialExpired(started + MonitorLimits.PartialFrameMs))
  }

  @Test
  fun moreBytesOfTheSameFrameDoNotResetThePartialClock() {
    val frame = encoded(encodeTicks(MessageKind.Ping, "slow", 3))
    val assembler = FrameAssembler()
    val started = 8_000L
    assertTrue(frame.size > 12)
    assembler.offer(frame, 0, 10, started)
    assembler.offer(frame, 10, 2, started + MonitorLimits.PartialFrameMs - 1)
    assertEquals(started, assembler.partialSinceMs)
    assertTrue(assembler.pendingSize < frame.size)
    assertFalse(assembler.partialExpired(started + MonitorLimits.PartialFrameMs - 1))
    assertTrue(assembler.partialExpired(started + MonitorLimits.PartialFrameMs))
  }

  @Test
  fun malformedHeaderAndBadUtf8StillFail() {
    val badMagic = FrameAssembler()
    val magic = header(1, magic = "XXXX")
    assertEquals(FrameStatus.BadMagic, badMagic.offer(magic, 0, magic.size, 0L).status)
    assertEquals(FrameAssembler.ReadChunkBytes, badMagic.pendingCapacity)
    assertTrue(badMagic.pendingCapacity < badMagic.bound)

    val badVersion = FrameAssembler()
    val version = header(1, version = 2)
    assertEquals(FrameStatus.BadVersion, badVersion.offer(version, 0, version.size, 0L).status)
    assertEquals(FrameAssembler.ReadChunkBytes, badVersion.pendingCapacity)

    val tooLarge = FrameAssembler()
    val opened = tooLarge.offer(byteArrayOf('L'.code.toByte(), 'A'.code.toByte(), 'M'.code.toByte(), '1'.code.toByte()), 0, 4, 0L)
    assertEquals(FrameStatus.Ok, opened.status)
    assertEquals(4, tooLarge.pendingSize)
    val length = MonitorLimits.MaxPayloadBytes + 1
    val rest = ByteArray(8)
    rest[4] = (length ushr 24).toByte()
    rest[5] = (length ushr 16).toByte()
    rest[6] = (length ushr 8).toByte()
    rest[7] = length.toByte()
    rest[0] = 1
    val rejected = tooLarge.offer(rest, 0, rest.size, 1L)
    assertEquals(FrameStatus.TooLarge, rejected.status)
    assertTrue(rejected.frames.isEmpty())
    assertEquals(FrameAssembler.ReadChunkBytes, tooLarge.pendingCapacity)
    assertTrue(tooLarge.pendingCapacity < tooLarge.bound)

    val badUtf8 = FrameAssembler()
    val utf8 = header(1) + byteArrayOf(0xFF.toByte())
    val failed = badUtf8.offer(utf8, 0, utf8.size, 0L)
    assertEquals(FrameStatus.BadUtf8, failed.status)
    assertTrue(failed.frames.isEmpty())
    assertTrue(badUtf8.pendingCapacity <= badUtf8.bound)
  }

  private fun maxPayloadFrame(): ByteArray {
    val prefix = "{\"pad\":\""
    val suffix = "\"}"
    val pad = MonitorLimits.MaxPayloadBytes - prefix.length - suffix.length
    assertTrue(pad > 0)
    val json = prefix + "a".repeat(pad) + suffix
    assertEquals(MonitorLimits.MaxPayloadBytes, json.toByteArray(Charsets.UTF_8).size)
    return encoded(json)
  }

  private fun encoded(json: String): ByteArray {
    val frame = tryEncodeFrame(json)
    assertTrue(frame.ok)
    return frame.bytes
  }

  private fun header(payloadLength: Int, version: Int = 1, magic: String = "LAM1"): ByteArray {
    val bytes = ByteArray(MonitorLimits.FrameHeaderSize)
    val chars = magic.encodeToByteArray()
    for (index in chars.indices) bytes[index] = chars[index]
    bytes[4] = version.toByte()
    bytes[8] = (payloadLength ushr 24).toByte()
    bytes[9] = (payloadLength ushr 16).toByte()
    bytes[10] = (payloadLength ushr 8).toByte()
    bytes[11] = payloadLength.toByte()
    return bytes
  }
}
