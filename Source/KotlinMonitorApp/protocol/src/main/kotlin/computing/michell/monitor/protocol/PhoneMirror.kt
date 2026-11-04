package computing.michell.monitor.protocol

/* Phone mirror rules. Catalogue 2 patch and catchup are not applied.
   A new epoch still files the closed id. No socket and no Android types.
   (c) 2026 Michell Computing. */

data class PhoneScreen(
  val epoch: String = "",
  val cursor: Long = 0,
  val catchingUp: Boolean = false,
  val announcedEpoch: String = "",
  val turns: List<WireTurn> = emptyList(),
  val live: WireTurn? = null,
  val patchOpenCursor: Long = 0,
  val patchPartCount: Int = 0,
  val patchParts: Map<Int, List<WireBlock>> = emptyMap(),
  val resumeOnce: Boolean = false,
  val closedId: String = "",
  val closedTitle: String = "",
  val fileClosedId: String = "",
  val conversationId: String = "",
  val projectRoot: String = "",
  val title: String = "",
  val blockFetchIds: List<String> = emptyList()
)

const val AckIntervalMs = 250L

data class AckPace(
  val lastSentMs: Long = 0,
  val sentSeq: Long = -1,
  val pendingSeq: Long = -1
)

data class AckDecision(
  val pace: AckPace,
  val sendNow: String = "",
  val laterMs: Long = 0,
  val sendLater: String = "",
  val seq: Long = -1
)

/** At most one ack every 250 ms. The later frame carries the newest seq. */
fun paceAck(
  pace: AckPace,
  nowMs: Long,
  id: String,
  conversationId: String,
  streamId: String,
  seq: Long
): AckDecision {
  if (conversationId.isEmpty() || streamId.isEmpty() || seq < 0) return AckDecision(pace)
  if (seq <= pace.sentSeq) return AckDecision(pace)
  val json = encodeAck(id, conversationId, streamId, seq)
  val elapsed = if (pace.lastSentMs == 0L) AckIntervalMs else nowMs - pace.lastSentMs
  if (elapsed >= AckIntervalMs) {
    return AckDecision(pace.copy(lastSentMs = nowMs, sentSeq = seq, pendingSeq = -1), json, 0, "", seq)
  }
  return AckDecision(pace.copy(pendingSeq = seq), "", AckIntervalMs - elapsed, json, seq)
}

fun notePhoneClosed(screen: PhoneScreen, id: String, title: String): PhoneScreen {
  if (id.isEmpty()) return screen.copy(fileClosedId = "")
  return screen.copy(closedId = id, closedTitle = title, fileClosedId = "")
}

/** Keeps the turns. Files a closed id only when this epoch is new. */
fun notePhoneEpoch(screen: PhoneScreen, epoch: String): PhoneScreen {
  if (epoch.isEmpty() || screen.epoch.isEmpty() || epoch == screen.epoch) return screen.copy(fileClosedId = "")
  val file = if (screen.closedId.isNotEmpty()) screen.closedId else ""
  return screen.copy(catchingUp = true, announcedEpoch = epoch, fileClosedId = file)
}

/** Catalogue 2 content is not applied. The screen stays with the store. */
fun applyPhonePatch(screen: PhoneScreen, patch: WirePatch): PhoneScreen = screen

/** Catalogue 2 catchup is not applied. An empty page does not replace the conversation. */
fun applyPhoneCatchup(
  screen: PhoneScreen,
  epoch: String,
  cursor: Long,
  conversationId: String,
  projectRoot: String,
  title: String,
  turns: List<WireTurn>,
  live: WireTurn?
): PhoneScreen = screen

/** A block_data frame replaces from offset 0, or appends when offset is the stored length. */
fun applyBlockDataJson(screen: PhoneScreen, payloadJson: String): PhoneScreen {
  val obj = parseObject(payloadJson) ?: return screen
  val blockId = obj.readString("block_id", true)
  val offset = obj.readInt("offset", true)
  val text = obj.readString("text", true)
  if (!blockId.ok || !offset.ok || !text.ok) return screen
  return applyBlockData(screen, blockId.value, offset.value, text.value)
}

fun applyBlockData(screen: PhoneScreen, blockId: String, offset: Int, text: String): PhoneScreen {
  if (blockId.isEmpty() || offset < 0) return screen
  fun splice(stored: String): String? {
    if (offset == 0) return text
    if (utf8Length(stored) != offset) return null
    return stored + text
  }
  fun rewrite(blocks: List<WireBlock>): List<WireBlock> {
    return blocks.map { block ->
      if (block.blockId != blockId) block
      else {
        val body = splice(block.body) ?: return@map block
        block.copy(body = body)
      }
    }
  }
  return screen.copy(
    live = screen.live?.copy(blocks = rewrite(screen.live.blocks)),
    turns = screen.turns.map { turn -> turn.copy(blocks = rewrite(turn.blocks)) },
    blockFetchIds = emptyList()
  )
}


