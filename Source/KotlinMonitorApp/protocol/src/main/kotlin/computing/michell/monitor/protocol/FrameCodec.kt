package computing.michell.monitor.protocol

/* LAM1 frame layout for the monitor catalogue (c) 2026 Michell Computing.

   The payload buffer is allocated only after the length field passes the cap.
   Length is big-endian. The session reader fills one reusable buffer by offset
   and compacts a consumed frame in place. This module does not write fixture files. */

import java.nio.CharBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.util.Base64

object MonitorLimits {
  const val FrameMagic = "LAM1"
  const val FrameVersion = 1
  const val FrameHeaderSize = 12
  const val MaxPayloadBytes = 262144
  const val CatalogueVersion = 3
  const val ListenPort = 56122
  const val MaxMessageIdChars = 64
  const val MaxSendChars = 65536
  const val MaxToolBodyChars = 4000
  const val MaxBodyPartBytes = 200000
  const val MaxImagePartBytes = 190000
  const val ImagePartBase64Chars = 253336
  const val ImageEnvelopeBytes = 8192
  const val MaxImageFetchBytes = 1048576
  const val MaxImageParts = 32
  const val MaxOpenImageAssemblies = 8
  const val ImageAssemblyTtlMs = 60_000L
  const val SnapshotStoredTurns = 30
  // Wire timing shared with the host (MonitorHeartbeatMs and MonitorDeadSessionMs).
  const val HeartbeatSilenceMs = 10_000L
  const val DeadSessionMs = 30_000L
  const val PartialFrameMs = 10_000L
  const val PairingCodeTtlMs = 120_000L
  const val ApprovalWaitMs = 120_000L
  const val NonceTtlMs = 30_000L
  const val NonceBytes = 16
  const val OutboundQueue = 32
  const val CoalesceWindowMs = 100L
  const val MainThreadCommandWaitMs = 5_000L
  const val MaxSimultaneousConnections = 2

  init {
    check(ListenPort == 56122)
    check(((MaxImagePartBytes + 2) / 3) * 4 == ImagePartBase64Chars)
    check(ImagePartBase64Chars + ImageEnvelopeBytes <= MaxPayloadBytes)
    check(MaxImageParts >= (MaxImageFetchBytes + MaxImagePartBytes - 1) / MaxImagePartBytes)
  }
}

enum class FrameStatus {
  Ok,
  NeedMore,
  BadMagic,
  BadVersion,
  Short,
  TooLarge,
  BadUtf8,
  BadJson
}

data class MonitorFrame(
  val version: Int,
  val flags: Int,
  val json: String,
  val parsed: JsonValue.Obj? = null
)

data class FrameEncode(
  val ok: Boolean,
  val bytes: ByteArray,
  val status: FrameStatus
)

data class FrameDecode(
  val ok: Boolean,
  val frame: MonitorFrame,
  val status: FrameStatus
)

data class FrameHeader(
  val ok: Boolean,
  val payloadLength: Long,
  val status: FrameStatus
)

data class FrameConsume(
  val ok: Boolean,
  val frame: MonitorFrame,
  val status: FrameStatus,
  val remaining: ByteArray
)

private val EmptyFrame = MonitorFrame(0, 0, "")

fun isStrictUtf8(bytes: ByteArray): Boolean {
  var index = 0
  val length = bytes.size
  while (index < length) {
    val lead = bytes[index].toInt() and 0xFF
    val need = when {
      lead < 0x80 -> 1
      lead in 0xC2..0xDF -> 2
      lead in 0xE0..0xEF -> 3
      lead in 0xF0..0xF4 -> 4
      else -> return false
    }
    if (index + need > length) return false
    if (need > 1) {
      val second = bytes[index + 1].toInt() and 0xFF
      if (second < 0x80 || second > 0xBF) return false
      if (lead == 0xE0 && second < 0xA0) return false
      if (lead == 0xED && second > 0x9F) return false
      if (lead == 0xF0 && second < 0x90) return false
      if (lead == 0xF4 && second > 0x8F) return false
    }
    if (need > 2) {
      val third = bytes[index + 2].toInt() and 0xFF
      if (third < 0x80 || third > 0xBF) return false
    }
    if (need > 3) {
      val fourth = bytes[index + 3].toInt() and 0xFF
      if (fourth < 0x80 || fourth > 0xBF) return false
    }
    index += need
  }
  return true
}

fun strictUtf8Bytes(text: String): ByteArray? {
  val encoder = Charsets.UTF_8.newEncoder()
    .onMalformedInput(CodingErrorAction.REPORT)
    .onUnmappableCharacter(CodingErrorAction.REPORT)
  return try {
    val encoded = encoder.encode(CharBuffer.wrap(text))
    val out = ByteArray(encoded.remaining())
    encoded.get(out)
    out
  } catch (error: CharacterCodingException) {
    null
  }
}

fun utf8Length(text: String): Int {
  val bytes = strictUtf8Bytes(text) ?: return Int.MAX_VALUE
  return bytes.size
}

fun encodeImageBytes(bytes: ByteArray): String {
  return Base64.getEncoder().encodeToString(bytes)
}

fun decodeImageBytes(encoded: String): ByteArray? {
  val compact = encoded.replace("\r", "").replace("\n", "")
  if (compact.isEmpty()) return ByteArray(0)
  return try {
    Base64.getDecoder().decode(compact)
  } catch (error: IllegalArgumentException) {
    null
  }
}

private fun readLength(bytes: ByteArray, offset: Int = 0): Long {
  return ((bytes[offset + 8].toLong() and 0xFF) shl 24) or
    ((bytes[offset + 9].toLong() and 0xFF) shl 16) or
    ((bytes[offset + 10].toLong() and 0xFF) shl 8) or
    (bytes[offset + 11].toLong() and 0xFF)
}

fun tryInspectFrameHeader(bytes: ByteArray, offset: Int = 0, available: Int = bytes.size - offset): FrameHeader {
  if (offset < 0 || available < MonitorLimits.FrameHeaderSize || offset > bytes.size || available > bytes.size - offset) {
    return FrameHeader(false, 0, FrameStatus.Short)
  }
  if (bytes[offset] != 'L'.code.toByte() || bytes[offset + 1] != 'A'.code.toByte() ||
    bytes[offset + 2] != 'M'.code.toByte() || bytes[offset + 3] != '1'.code.toByte()) {
    return FrameHeader(false, 0, FrameStatus.BadMagic)
  }
  if ((bytes[offset + 4].toInt() and 0xFF) != MonitorLimits.FrameVersion) {
    return FrameHeader(false, 0, FrameStatus.BadVersion)
  }
  val payloadLength = readLength(bytes, offset)
  if (payloadLength > MonitorLimits.MaxPayloadBytes) {
    return FrameHeader(false, payloadLength, FrameStatus.TooLarge)
  }
  return FrameHeader(true, payloadLength, FrameStatus.Ok)
}

private fun finishPayload(bytes: ByteArray, payloadLength: Int): FrameDecode {
  val raw = ByteArray(payloadLength)
  if (payloadLength > 0) {
    bytes.copyInto(raw, 0, MonitorLimits.FrameHeaderSize, MonitorLimits.FrameHeaderSize + payloadLength)
  }
  if (!isStrictUtf8(raw)) {
    return FrameDecode(false, EmptyFrame, FrameStatus.BadUtf8)
  }
  val json = raw.toString(Charsets.UTF_8)
  val parsed = parseJson(json) as? JsonValue.Obj
  if (parsed == null) {
    return FrameDecode(false, EmptyFrame, FrameStatus.BadJson)
  }
  val frame = MonitorFrame(MonitorLimits.FrameVersion, bytes[5].toInt() and 0xFF, json, parsed)
  return FrameDecode(true, frame, FrameStatus.Ok)
}

fun tryEncodeFrame(json: String): FrameEncode {
  val payload = strictUtf8Bytes(json)
  if (payload == null) {
    return FrameEncode(false, ByteArray(0), FrameStatus.BadUtf8)
  }
  if (payload.size > MonitorLimits.MaxPayloadBytes) {
    return FrameEncode(false, ByteArray(0), FrameStatus.TooLarge)
  }
  if (!isStrictUtf8(payload)) {
    return FrameEncode(false, ByteArray(0), FrameStatus.BadUtf8)
  }
  if (!jsonTextIsObject(json)) {
    return FrameEncode(false, ByteArray(0), FrameStatus.BadJson)
  }
  val bytes = ByteArray(MonitorLimits.FrameHeaderSize + payload.size)
  bytes[0] = 'L'.code.toByte()
  bytes[1] = 'A'.code.toByte()
  bytes[2] = 'M'.code.toByte()
  bytes[3] = '1'.code.toByte()
  bytes[4] = MonitorLimits.FrameVersion.toByte()
  val length = payload.size
  bytes[8] = (length ushr 24).toByte()
  bytes[9] = (length ushr 16).toByte()
  bytes[10] = (length ushr 8).toByte()
  bytes[11] = length.toByte()
  if (payload.isNotEmpty()) payload.copyInto(bytes, MonitorLimits.FrameHeaderSize)
  return FrameEncode(true, bytes, FrameStatus.Ok)
}

fun tryDecodeFrame(bytes: ByteArray): FrameDecode {
  val header = tryInspectFrameHeader(bytes)
  if (!header.ok) {
    val status = if (bytes.size < MonitorLimits.FrameHeaderSize) FrameStatus.Short else header.status
    return FrameDecode(false, EmptyFrame, status)
  }
  val payloadLength = header.payloadLength.toInt()
  if (bytes.size < MonitorLimits.FrameHeaderSize + payloadLength) {
    return FrameDecode(false, EmptyFrame, FrameStatus.Short)
  }
  return finishPayload(bytes, payloadLength)
}

fun tryConsumeFrame(pending: ByteArray): FrameConsume {
  if (pending.size < MonitorLimits.FrameHeaderSize) {
    return FrameConsume(false, EmptyFrame, FrameStatus.NeedMore, pending)
  }
  val header = tryInspectFrameHeader(pending)
  if (!header.ok) {
    return FrameConsume(false, EmptyFrame, header.status, pending)
  }
  val have = MonitorLimits.FrameHeaderSize + header.payloadLength.toInt()
  if (pending.size < have) {
    return FrameConsume(false, EmptyFrame, FrameStatus.NeedMore, pending)
  }
  val decoded = finishPayload(pending, header.payloadLength.toInt())
  if (!decoded.ok) {
    return FrameConsume(false, EmptyFrame, decoded.status, pending)
  }
  val remaining = pending.copyOfRange(have, pending.size)
  return FrameConsume(true, decoded.frame, FrameStatus.Ok, remaining)
}

fun readBigEndianLength(bytes: ByteArray): Long {
  if (bytes.size < MonitorLimits.FrameHeaderSize) return 0
  return readLength(bytes)
}

data class AssembledFrames(
  val frames: List<MonitorFrame>,
  val status: FrameStatus
)

/** One pending buffer for a read loop. Bytes are copied in at an offset, and a consumed frame is compacted in place. */
class FrameAssembler(val readChunk: Int = ReadChunkBytes) {
  val bound: Int = MonitorLimits.FrameHeaderSize + MonitorLimits.MaxPayloadBytes + readChunk

  private var storage = ByteArray(readChunk)
  private var filled = 0
  private var highWaterMark = 0
  private var partialSince = 0L
  private var copied = 0L

  val pendingSize: Int get() = filled
  val pendingCapacity: Int get() = storage.size
  val highWater: Int get() = highWaterMark
  val partialSinceMs: Long get() = partialSince
  /** Bytes copied into the pending buffer, including a compacted remainder. Not the decoded payload. */
  val copiedBytes: Long get() = copied
  internal val pendingStorage: ByteArray get() = storage

  init {
    require(readChunk > 0)
  }

  fun partialExpired(nowMs: Long): Boolean {
    if (filled == 0) return false
    val since = partialSince
    // A backward step is not a duration. Empty pending is not a partial frame.
    if (nowMs < since) return false
    return nowMs - since >= MonitorLimits.PartialFrameMs
  }

  fun offer(chunk: ByteArray, offset: Int = 0, count: Int = chunk.size - offset, nowMs: Long): AssembledFrames {
    if (count == 0) return AssembledFrames(emptyList(), FrameStatus.Ok)
    if (offset < 0 || count < 0 || offset > chunk.size || count > chunk.size - offset) {
      return AssembledFrames(emptyList(), FrameStatus.Short)
    }
    if (count > bound || filled > bound - count) {
      return AssembledFrames(emptyList(), FrameStatus.TooLarge)
    }
    val wasEmpty = filled == 0
    if (!accept(chunk, offset, count)) return AssembledFrames(emptyList(), FrameStatus.TooLarge)
    if (filled > highWaterMark) highWaterMark = filled
    if (wasEmpty) partialSince = nowMs
    return drain(nowMs)
  }

  private fun accept(chunk: ByteArray, offset: Int, count: Int): Boolean {
    val need = filled + count
    if (need > bound) return false
    val target = reserve(peekHeader(chunk, offset, count), need)
    if (target > storage.size && !grow(target)) return false
    chunk.copyInto(storage, filled, offset, offset + count)
    copied += count
    filled = need
    return true
  }

  private fun reserve(header: FrameHeader?, need: Int): Int {
    if (header != null && header.ok) {
      val frame = MonitorLimits.FrameHeaderSize + header.payloadLength.toInt()
      return minOf(bound, maxOf(need, frame + readChunk))
    }
    // A missing or rejected header must not reserve a max payload.
    return minOf(bound, maxOf(need, storage.size))
  }

  private fun grow(target: Int): Boolean {
    if (target < filled || target > bound) return false
    val next = ByteArray(target)
    if (filled > 0) {
      storage.copyInto(next, 0, 0, filled)
      copied += filled
    }
    storage = next
    return true
  }

  private fun peekHeader(chunk: ByteArray, offset: Int, count: Int): FrameHeader? {
    if (filled + count < MonitorLimits.FrameHeaderSize) return null
    if (filled >= MonitorLimits.FrameHeaderSize) return tryInspectFrameHeader(storage, 0, filled)
    if (filled == 0) return tryInspectFrameHeader(chunk, offset, count)
    val header = ByteArray(MonitorLimits.FrameHeaderSize)
    storage.copyInto(header, 0, 0, filled)
    val take = MonitorLimits.FrameHeaderSize - filled
    chunk.copyInto(header, filled, offset, offset + take)
    return tryInspectFrameHeader(header)
  }

  private fun drain(nowMs: Long): AssembledFrames {
    val frames = ArrayList<MonitorFrame>(1)
    var consumed = false
    while (filled >= MonitorLimits.FrameHeaderSize) {
      val header = tryInspectFrameHeader(storage, 0, filled)
      if (!header.ok) return AssembledFrames(frames, header.status)
      val payloadLength = header.payloadLength.toInt()
      val frameLength = MonitorLimits.FrameHeaderSize + payloadLength
      if (filled < frameLength) break
      val decoded = finishPayload(storage, payloadLength)
      if (!decoded.ok) return AssembledFrames(frames, decoded.status)
      frames.add(decoded.frame)
      compact(frameLength)
      consumed = true
    }
    if (filled == 0) partialSince = 0L
    else if (consumed) partialSince = nowMs
    return AssembledFrames(frames, FrameStatus.Ok)
  }

  private fun compact(frameLength: Int) {
    val remain = filled - frameLength
    if (remain > 0) {
      storage.copyInto(storage, 0, frameLength, filled)
      copied += remain
    }
    filled = remain
  }

  companion object {
    const val ReadChunkBytes = 8192
  }
}
