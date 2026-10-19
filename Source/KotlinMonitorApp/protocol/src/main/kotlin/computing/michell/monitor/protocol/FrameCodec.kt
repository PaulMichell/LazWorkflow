package computing.michell.monitor.protocol

/* LAM1 frame layout for the monitor catalogue (c) 2026 Michell Computing.

   The payload buffer is allocated only after the length field passes the cap.
   Length is big-endian. This module does not write fixture files. */

import java.nio.CharBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.util.Base64

object MonitorLimits {
  const val FrameMagic = "LAM1"
  const val FrameVersion = 1
  const val FrameHeaderSize = 12
  const val MaxPayloadBytes = 262144
  const val CatalogueVersion = 1
  const val ListenPort = 56122
  const val MaxMessageIdChars = 64
  const val MaxSendChars = 65536
  const val MaxToolBodyChars = 4000
  const val MaxBodyPartBytes = 200000
  const val MaxImagePartBytes = 190000
  const val ImagePartBase64Chars = 253336
  const val ImageEnvelopeBytes = 8192
  const val MaxImageFetchBytes = 1048576
  const val SnapshotStoredTurns = 30
  const val HeartbeatSilenceMs = 15_000L
  const val DeadSessionMs = 45_000L
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
  val json: String
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

private fun readLength(bytes: ByteArray): Long {
  return ((bytes[8].toLong() and 0xFF) shl 24) or
    ((bytes[9].toLong() and 0xFF) shl 16) or
    ((bytes[10].toLong() and 0xFF) shl 8) or
    (bytes[11].toLong() and 0xFF)
}

fun tryInspectFrameHeader(bytes: ByteArray): FrameHeader {
  if (bytes.size < MonitorLimits.FrameHeaderSize) {
    return FrameHeader(false, 0, FrameStatus.Short)
  }
  if (bytes[0] != 'L'.code.toByte() || bytes[1] != 'A'.code.toByte() ||
    bytes[2] != 'M'.code.toByte() || bytes[3] != '1'.code.toByte()) {
    return FrameHeader(false, 0, FrameStatus.BadMagic)
  }
  if ((bytes[4].toInt() and 0xFF) != MonitorLimits.FrameVersion) {
    return FrameHeader(false, 0, FrameStatus.BadVersion)
  }
  val payloadLength = readLength(bytes)
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
  if (!jsonTextIsObject(json)) {
    return FrameDecode(false, EmptyFrame, FrameStatus.BadJson)
  }
  val frame = MonitorFrame(MonitorLimits.FrameVersion, bytes[5].toInt() and 0xFF, json)
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
