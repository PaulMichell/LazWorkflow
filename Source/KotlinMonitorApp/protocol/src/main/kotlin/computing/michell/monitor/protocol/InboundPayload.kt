package computing.michell.monitor.protocol

/* Typed inbound catalogue value. Produced once at the session edge (c) 2026 Michell Computing. */

sealed class InboundPayload {
  data object None : InboundPayload()
  data class Snapshot(val value: WireSnapshot) : InboundPayload()
  data class TranscriptPart(val value: WireTranscript) : InboundPayload()
  data class ImagePart(val image: ImageData, val bytes: ByteArray) : InboundPayload()
  data class Turn(val value: WireTurn) : InboundPayload()
  data class Status(val view: WireView) : InboundPayload()
  data class Mode(val value: ModeMessage) : InboundPayload()
  data class Target(val value: TargetMessage) : InboundPayload()
  data class Plan(val value: PlanMessage) : InboundPayload()
  data class ApprovalRequest(val notice: ApprovalNotice) : InboundPayload()
  data class Insert(val text: String) : InboundPayload()
  data class Error(val body: ErrorBody) : InboundPayload()
  data class Rejected(val value: RejectedMessage) : InboundPayload()
  data class ImageMissing(val value: ImageUnavailable) : InboundPayload()
  data class PairOk(val value: PairOkMessage) : InboundPayload()
  data class HelloOk(val value: HelloOkMessage) : InboundPayload()
  data class Text(val text: String) : InboundPayload()
}
