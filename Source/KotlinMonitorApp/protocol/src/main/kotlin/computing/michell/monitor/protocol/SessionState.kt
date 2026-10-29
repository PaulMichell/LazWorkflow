package computing.michell.monitor.protocol

/* Client session rules for catalogue version 1 (c) 2026 Michell Computing.

   No socket and no Android UI. An unknown type, and a send or steer the text
   limit rejects, do not change phase. Image parts are bounded as they arrive.
   The auth MAC is javax.crypto HMAC-SHA256 of the raw nonce bytes, keyed by
   the session token string, written as lowercase hex. */

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
  MessageKind.SnapshotPage,
  MessageKind.Status,
  MessageKind.Mode,
  MessageKind.Target,
  MessageKind.Plan,
  MessageKind.Tasks,
  MessageKind.InsertResult,
  MessageKind.ApprovalRequested,
  MessageKind.ApprovalClosed,
  MessageKind.ImageData,
  MessageKind.ImageUnavailable
)

class ImageAssembly {
  private val open = linkedMapOf<ImageKey, OpenImage>()
  private val expiredIds = mutableListOf<String>()
  private var retainedBytes = 0L

  fun reset() {
    open.clear()
    expiredIds.clear()
    retainedBytes = 0L
  }

  /** Image ids dropped by the assembly TTL since the last call. */
  fun takeExpired(): List<String> {
    val copy = expiredIds.toList()
    expiredIds.clear()
    return copy
  }

  fun accept(part: ImageData, decoded: ByteArray, nowMs: Long = System.currentTimeMillis()): ByteArray? {
    if (decoded.size > MonitorLimits.MaxImagePartBytes) return null
    if (part.partCount !in 1..MonitorLimits.MaxImageParts || part.part !in 1..part.partCount) return null
    expire(nowMs)
    val key = ImageKey(part.imageId, part.revision)
    val existing = open[key]
    if (existing != null && !existing.matches(part)) {
      drop(key)
      return null
    }
    if (existing == null && open.size >= MonitorLimits.MaxOpenImageAssemblies) return null
    val current = existing ?: OpenImage(part.mime, part.width, part.height, part.partCount, nowMs)
    val previous = current.parts[part.part]?.size?.toLong() ?: 0L
    val nextAssembly = current.retained - previous + decoded.size
    val nextTotal = retainedBytes - previous + decoded.size
    if (nextAssembly > MonitorLimits.MaxImageFetchBytes || nextTotal > MonitorLimits.MaxImageFetchBytes) {
      if (existing != null) drop(key)
      return null
    }
    if (existing == null) open[key] = current
    current.parts[part.part] = decoded
    current.retained = nextAssembly
    retainedBytes = nextTotal
    if (current.parts.size < current.partCount) return null
    for (index in 1..current.partCount) {
      if (!current.parts.containsKey(index)) return null
    }
    if (current.retained > MonitorLimits.MaxImageFetchBytes) {
      drop(key)
      return null
    }
    val joined = ByteArray(current.retained.toInt())
    var at = 0
    for (index in 1..current.partCount) {
      val chunk = current.parts.getValue(index)
      chunk.copyInto(joined, at)
      at += chunk.size
    }
    drop(key)
    return joined
  }

  private fun expire(nowMs: Long) {
    val stale = open.filter { (_, image) -> nowMs - image.startedMs >= MonitorLimits.ImageAssemblyTtlMs }.keys.toList()
    for (key in stale) {
      expiredIds += key.imageId
      drop(key)
    }
  }

  private fun drop(key: ImageKey) {
    val removed = open.remove(key) ?: return
    retainedBytes -= removed.retained
    if (retainedBytes < 0L) retainedBytes = 0L
  }

  private data class ImageKey(val imageId: String, val revision: Int)

  private class OpenImage(
    val mime: String,
    val width: Int,
    val height: Int,
    val partCount: Int,
    val startedMs: Long,
    val parts: MutableMap<Int, ByteArray> = linkedMapOf(),
    var retained: Long = 0L
  ) {
    fun matches(part: ImageData): Boolean {
      return mime == part.mime && width == part.width && height == part.height && partCount == part.partCount
    }
  }
}

class SessionState {
  var phase: SessionPhase = SessionPhase.Stopped
    private set
  private var authSent = false
  var liveRevision: Int = -1
    private set
  private var retainedImageBytes = 0

  /** Image part bytes are not kept here. The UI assembler is the only copy. */
  fun retainedImageBytes(): Int = retainedImageBytes

  fun onHandshakeComplete() {
    if (phase == SessionPhase.Stopped || phase == SessionPhase.Closed) {
      phase = SessionPhase.Accepted
      authSent = false
      liveRevision = -1
      retainedImageBytes = 0
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
  }

  private fun updateBusy(message: MonitorMessage) {
    if (phase != SessionPhase.Live && phase != SessionPhase.Busy) return
    val sending: Boolean
    val planRunning: Boolean
    when (val body = message.inbound) {
      is InboundPayload.Snapshot -> {
        sending = body.value.view.sending
        planRunning = body.value.view.planRunning || body.value.planRunning
      }
      is InboundPayload.Status -> {
        sending = body.view.sending
        planRunning = body.view.planRunning
      }
      else -> when (message.kind) {
        MessageKind.Snapshot -> {
          val snapshot = decodeSnapshot(message.payloadJson) ?: return
          sending = snapshot.view.sending
          planRunning = snapshot.view.planRunning || snapshot.planRunning
        }
        MessageKind.Status -> {
          val view = decodeStatusPayload(message.payloadJson) ?: return
          sending = view.sending
          planRunning = view.planRunning
        }
        else -> return
      }
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
