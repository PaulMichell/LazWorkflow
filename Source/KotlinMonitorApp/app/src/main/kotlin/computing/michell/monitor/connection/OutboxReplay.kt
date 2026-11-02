package computing.michell.monitor.connection

/* Replay rules for commands the phone has not finished (c) 2026 Michell Computing.

   A command is stored before it is written. On reconnect the phone lists the
   open ids in resume. Only a host state of unknown is sent again. A prompt
   the host has already queued or accepted is never sent again on its own.
   If that outcome can no longer be known, the draft is offered back. */

import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.decodeText
import computing.michell.monitor.protocol.tryDecodeEnvelope

const val NotDeliveredRetry = "Not delivered — Retry"
const val OutboxOpen = "open"
const val OutboxQueued = "queued"
const val OutboxAccepted = "accepted"
const val OutboxDone = "done"
const val OutboxRejected = "rejected"

data class HostCommandState(val ref: String, val state: String, val reason: String = "")

enum class ReplayAction {
  Resend,
  Wait,
  Clear,
  OfferRetry
}

/** Host state wins. A held prompt that the host no longer knows is not replayed. */
fun replayAction(kind: String, localState: String, hostState: String): ReplayAction {
  when (hostState) {
    OutboxDone, OutboxRejected -> return ReplayAction.Clear
    OutboxQueued, OutboxAccepted -> return ReplayAction.Wait
    else -> {
      val prompt = kind == MessageKind.Send.wireName || kind == MessageKind.Steer.wireName
      val held = localState == OutboxQueued || localState == OutboxAccepted
      if (prompt && held) return ReplayAction.OfferRetry
      return ReplayAction.Resend
    }
  }
}

fun isUserCommand(json: String): Boolean {
  val decoded = tryDecodeEnvelope(json)
  if (!decoded.ok) return false
  return decoded.message.kind in UserCommandKinds
}

fun commandKindName(json: String): String {
  val decoded = tryDecodeEnvelope(json)
  if (!decoded.ok) return ""
  return decoded.message.kind.wireName
}

fun commandText(json: String): String {
  val decoded = tryDecodeEnvelope(json)
  if (!decoded.ok) return ""
  if (decoded.message.kind != MessageKind.Send && decoded.message.kind != MessageKind.Steer) return ""
  return decodeText(decoded.message.payloadJson) ?: ""
}

private val UserCommandKinds = setOf(
  MessageKind.Send,
  MessageKind.Steer,
  MessageKind.Stop,
  MessageKind.NewConversation,
  MessageKind.RunPlan,
  MessageKind.StopPlan,
  MessageKind.SetMode,
  MessageKind.SelectConversation,
  MessageKind.SelectTarget,
  MessageKind.SetModel,
  MessageKind.SetReasoning,
  MessageKind.SetPermissions,
  MessageKind.SelectPlan,
  MessageKind.ClosePlan,
  MessageKind.NewPlan,
  MessageKind.WorkOnPlan,
  MessageKind.RunTask,
  MessageKind.InsertTask
)
