package computing.michell.monitor.protocol

/* Client session rules for catalogue version 1 (c) 2026 Michell Computing.

   No socket and no Android UI. An unknown type, and a send or steer the text
   limit rejects, do not change phase. The auth MAC is javax.crypto HMAC-SHA256
   of the raw nonce bytes, keyed by the session token string, written as
   lowercase hex. */

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

enum class SessionPhase {
  Stopped,
  Accepted,
  Live,
  Busy,
  Closed
}

private val BeforeLive = setOf(
  MessageKind.Hello,
  MessageKind.Pair,
  MessageKind.Auth,
  MessageKind.Ping,
  MessageKind.Bye
)

private val LiveEvidence = setOf(
  MessageKind.Snapshot,
  MessageKind.Transcript,
  MessageKind.Status,
  MessageKind.Mode,
  MessageKind.Target,
  MessageKind.Plan,
  MessageKind.Tasks,
  MessageKind.TurnData,
  MessageKind.InsertResult,
  MessageKind.ApprovalRequested,
  MessageKind.ApprovalClosed,
  MessageKind.ImageData,
  MessageKind.ImageUnavailable
)

class ImageAssembly {
  private val parts = linkedMapOf<Int, ByteArray>()
  private var imageId = ""
  private var revision = -1
  private var partCount = 0

  fun reset() {
    parts.clear()
    imageId = ""
    revision = -1
    partCount = 0
  }

  fun accept(part: ImageData, decoded: ByteArray): ByteArray? {
    if (part.part < 1 || part.partCount < part.part || decoded.size > MonitorLimits.MaxImagePartBytes) return null
    if (imageId != part.imageId || revision != part.revision || partCount != part.partCount) {
      parts.clear()
      imageId = part.imageId
      revision = part.revision
      partCount = part.partCount
    }
    parts[part.part] = decoded
    if (parts.size < partCount) return null
    for (index in 1..partCount) {
      if (!parts.containsKey(index)) return null
    }
    var total = 0
    for (index in 1..partCount) total += parts.getValue(index).size
    if (total > MonitorLimits.MaxImageFetchBytes) {
      reset()
      return null
    }
    val joined = ByteArray(total)
    var at = 0
    for (index in 1..partCount) {
      val chunk = parts.getValue(index)
      chunk.copyInto(joined, at)
      at += chunk.size
    }
    reset()
    return joined
  }
}

class SessionState {
  var phase: SessionPhase = SessionPhase.Stopped
    private set
  private var authSent = false
  val images = ImageAssembly()
  var liveRevision: Int = -1
    private set
  var liveTranscript: WireTranscript? = null
    private set

  fun onHandshakeComplete() {
    if (phase == SessionPhase.Stopped || phase == SessionPhase.Closed) {
      phase = SessionPhase.Accepted
      authSent = false
      liveRevision = -1
      liveTranscript = null
      images.reset()
    }
  }

  fun onSocketClosed() {
    phase = SessionPhase.Closed
  }

  fun outboundAllowed(kind: MessageKind): Boolean {
    if (phase == SessionPhase.Stopped || phase == SessionPhase.Closed) return false
    if (phase == SessionPhase.Accepted) return kind in BeforeLive
    return true
  }

  fun noteOutbound(kind: MessageKind) {
    if (kind == MessageKind.Auth) authSent = true
  }

  fun apply(message: MonitorMessage) {
    if (!message.changesState) return
    when (message.kind) {
      MessageKind.Rejected, MessageKind.Bye -> {
        phase = SessionPhase.Closed
        return
      }
      MessageKind.PairOk -> {
        if (phase == SessionPhase.Accepted) phase = SessionPhase.Live
        return
      }
      else -> { }
    }
    if (phase == SessionPhase.Accepted && authSent && message.kind in LiveEvidence) {
      phase = SessionPhase.Live
    }
    updateBusy(message)
    if (message.kind == MessageKind.Transcript) acceptTranscript(message.payloadJson)
    if (message.kind == MessageKind.ImageData) acceptImage(message.payloadJson)
  }

  fun acceptTranscript(payloadJson: String): Boolean {
    val transcript = decodeTranscript(payloadJson) ?: return false
    if (liveTranscript != null && transcript.revision <= liveRevision) return false
    liveRevision = transcript.revision
    liveTranscript = transcript
    return true
  }

  fun acceptImage(payloadJson: String): ByteArray? {
    val decoded = decodeImageData(payloadJson) ?: return null
    val raw = decodeImageBytes(decoded.image.bytesBase64) ?: return null
    return images.accept(decoded.image, raw)
  }

  private fun updateBusy(message: MonitorMessage) {
    if (phase != SessionPhase.Live && phase != SessionPhase.Busy) return
    val sending: Boolean
    val planRunning: Boolean
    when (message.kind) {
      MessageKind.Snapshot -> {
        val snapshot = decodeSnapshot(message.payloadJson) ?: return
        sending = snapshot.view.sending
        planRunning = snapshot.view.planRunning || snapshot.planRunning
      }
      MessageKind.Status -> {
        val obj = parseJson(message.payloadJson) as? JsonValue.Obj ?: return
        val view = statusFromJson(obj) ?: return
        sending = view.sending
        planRunning = view.planRunning
      }
      else -> return
    }
    phase = if (sending || planRunning) SessionPhase.Busy else SessionPhase.Live
  }
}

fun hexToBytes(text: String): ByteArray? {
  if (text.isEmpty()) return ByteArray(0)
  if (text.length % 2 != 0) return null
  val out = ByteArray(text.length / 2)
  for (index in out.indices) {
    val high = hexValue(text[index * 2])
    val low = hexValue(text[index * 2 + 1])
    if (high < 0 || low < 0) return null
    out[index] = ((high shl 4) or low).toByte()
  }
  return out
}

private fun hexValue(ch: Char): Int {
  return when (ch) {
    in '0'..'9' -> ch.code - '0'.code
    in 'a'..'f' -> ch.code - 'a'.code + 10
    in 'A'..'F' -> ch.code - 'A'.code + 10
    else -> -1
  }
}

fun authMac(sessionToken: String, nonceHex: String): String {
  if (sessionToken.isEmpty() || nonceHex.isEmpty()) return ""
  val key = strictUtf8Bytes(sessionToken) ?: return ""
  val message = hexToBytes(nonceHex) ?: return ""
  if (key.isEmpty() || message.isEmpty()) return ""
  val mac = Mac.getInstance("HmacSHA256")
  mac.init(SecretKeySpec(key, "HmacSHA256"))
  val digest = mac.doFinal(message)
  val out = StringBuilder(digest.size * 2)
  for (byte in digest) {
    val value = byte.toInt() and 0xFF
    out.append(HexLower[value shr 4])
    out.append(HexLower[value and 0x0F])
  }
  return out.toString()
}

private val HexLower = "0123456789abcdef"
