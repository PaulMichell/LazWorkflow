package computing.michell.monitor.protocol

/* Monitor catalogue version 2. Wire names are snake case. (c) 2026 Michell Computing.

   Limits live here, not in a later screen. Unknown types become error / unknown_type
   and do not change session state. JSON text uses the same spacing as the host
   fpjson writer so encoded frames match the checked-in catalogue.

   Size note: exceeds the 1000 line preference. The catalogue is one table of
   message types, payload fields, and limits. Splitting that table would hide a type.
   v2 adds resume, patch, catchup, and conversation_closed to that same table.
   JSON text and envelope field checks live in CatalogueJson. The catalogue calls them.
   Reviewed 2026-10-27: models, reasoning, permissions, and their set commands stay in this table. Inbound values are typed once.
   No socket, TLS, or Android UI in this file. */

const val NoSessionReason = "no_session"
const val NoSessionMessage = "The Project Assistant window is not open."
const val UnknownTypeReason = "unknown_type"
const val PayloadTooLargeReason = "payload_too_large"
const val HostBusyReason = "host_busy"
const val PayloadTooLargeMessage = "Text is longer than 65536 characters."

val ModeNames = listOf("inspect", "document", "plan", "build", "chat")
val RejectedReasons = setOf("protocol", "pair_code", "fingerprint", "expired", "auth", "revoked", "busy", "disabled")
val ApprovalCloseReasons = setOf("allowed", "denied", "finished", "timeout", "desktop", "disabled", "stopped")
val ImageUnavailableReasons = setOf("missing", "too_large", "refused")

enum class MessageKind(val wireName: String) {
  Unknown(""),
  Hello("hello"),
  Pair("pair"),
  PairOk("pair_ok"),
  HelloOk("hello_ok"),
  Auth("auth"),
  Rejected("rejected"),
  Bye("bye"),
  Snapshot("snapshot"),
  Refresh("refresh"),
  Transcript("transcript"),
  Turn("turn"),
  TurnData("turn_data"),
  Mode("mode"),
  SetMode("set_mode"),
  Send("send"),
  Steer("steer"),
  Stop("stop"),
  Status("status"),
  Target("target"),
  Plan("plan"),
  SelectPlan("select_plan"),
  NewPlan("new_plan"),
  RemovePlan("remove_plan"),
  WorkOnPlan("work_on_plan"),
  RunPlan("run_plan"),
  StopPlan("stop_plan"),
  Tasks("tasks"),
  RunTask("run_task"),
  InsertTask("insert_task"),
  InsertResult("insert_result"),
  ApprovalRequested("approval_requested"),
  ApprovalDecision("approval_decision"),
  ApprovalClosed("approval_closed"),
  ImageGet("image_get"),
  ImageData("image_data"),
  ImageUnavailable("image_unavailable"),
  NewConversation("new_conversation"),
  Error("error"),
  Ping("ping"),
  Pong("pong"),
  Resume("resume"),
  Patch("patch"),
  Catchup("catchup"),
  ConversationClosed("conversation_closed"),
  Targets("targets"),
  SelectTarget("select_target"),
  Conversations("conversations"),
  SelectConversation("select_conversation"),
  Models("models"),
  SetModel("set_model"),
  Reasoning("reasoning"),
  SetReasoning("set_reasoning"),
  Permissions("permissions"),
  SetPermissions("set_permissions"),
  BlockGet("block_get"),
  BlockData("block_data"),
  Ack("ack");

  companion object {
    fun fromWire(name: String): MessageKind {
      for (kind in entries) {
        if (kind != Unknown && kind.wireName == name) return kind
      }
      return Unknown
    }
  }
}

data class MonitorMessage(
  val version: Int,
  val id: String,
  val kind: MessageKind,
  val typeName: String,
  val payloadJson: String,
  val reason: String,
  val changesState: Boolean,
  val wireJson: String,
  val inbound: InboundPayload = InboundPayload.None
)

data class HelloMessage(val clientName: String, val clientVersion: String, val clientId: String, val hasClientId: Boolean)
data class PairMessage(val code: String, val fingerprint: String)
data class PairOkMessage(val clientId: String, val sessionToken: String)
data class HelloOkMessage(
  val nonce: String,
  val serverName: String,
  val epoch: String,
  val cursor: Long,
  val conversationId: String,
  val projectRoot: String,
  val title: String,
  val hostId: String = ""
)
data class AuthMessage(val clientId: String, val hmac: String)
data class RejectedMessage(val reason: String, val hostVersion: Int, val clientVersion: Int)
data class ByeMessage(val reason: String)
data class ModeMessage(val mode: String, val locked: Boolean)
data class TargetMessage(val kind: String, val display: String, val root: String)
data class NewPlanMessage(val title: String, val hasTitle: Boolean)
data class TaskCommand(val id: String, val note: String)
data class ApprovalDecision(val toolId: String, val allow: Boolean)
data class ApprovalClosed(val toolId: String, val reason: String)
data class ImageGet(val turnIndex: Int, val imageId: String)
data class ImageData(
  val imageId: String,
  val mime: String,
  val width: Int,
  val height: Int,
  val part: Int,
  val partCount: Int,
  val revision: Int,
  val bytesBase64: String
)
data class ImageUnavailable(val imageId: String, val reason: String)
data class ErrorBody(val reason: String, val messageText: String, val refId: String)
data class TicksMessage(val ticks: Long)
data class BodyPart(val part: Int, val partCount: Int, val revision: Int, val text: String)
data class TextEncode(val ok: Boolean, val json: String, val errorJson: String)
data class ImageEncode(val ok: Boolean, val messages: List<String>, val unavailableReason: String)
data class EnvelopeResult(val ok: Boolean, val message: MonitorMessage, val errorText: String)

data class WireImage(
  val id: String,
  val name: String,
  val mime: String,
  val width: Int,
  val height: Int,
  val displayPath: String,
  val missing: Boolean
)

data class WireBlock(
  val kind: String,
  val blockId: String,
  val title: String,
  val toolName: String,
  val toolId: String,
  val body: String,
  val running: Boolean,
  val ok: Boolean,
  val durationMs: Int,
  val images: List<WireImage>,
  val truncated: Boolean = false,
  val part: Int = 1,
  val partCount: Int = 1,
  val revision: Int = 0,
  val appendOffset: Int? = null
)

data class WireView(
  val available: Boolean,
  val busy: Boolean,
  val sending: Boolean,
  val modeLocked: Boolean,
  val planRunning: Boolean,
  val phase: String,
  val statusText: String,
  val model: String,
  val backend: String,
  val signedIn: Boolean,
  val approvalCaption: String,
  val effort: String,
  val skill: String,
  val contextText: String,
  val canSend: Boolean,
  val canSteer: Boolean,
  val canStop: Boolean,
  val canChangeMode: Boolean,
  val remoteApproval: Boolean,
  val errorText: String,
  val elapsedMs: Int = 0,
  val mode: String = "",
  val targetKind: String = "",
  val targetDisplay: String = "",
  val targetRoot: String = "",
  val planPath: String = "",
  val planTitle: String = ""
)

data class WireTurn(
  val turnIndex: Int,
  val id: String,
  val mode: String,
  val createdAt: String,
  val promptPreview: String,
  val errorText: String,
  val prompt: String = "",
  val thinking: String = "",
  val response: String = "",
  val durationMs: Int = 0,
  val live: Boolean = false,
  val blocks: List<WireBlock> = emptyList(),
  val images: List<WireImage> = emptyList()
)

data class PlanRow(
  val index: Int,
  val level: Int,
  val title: String,
  val parentTitle: String,
  val status: String,
  val actionable: Boolean
)

data class TaskRow(
  val id: String,
  val title: String,
  val summary: String,
  val mode: String,
  val kind: String,
  val scope: String,
  val compileFirst: Boolean,
  val enabled: Boolean,
  val needsNote: Boolean
)

data class ApprovalNotice(
  val active: Boolean,
  val toolId: String,
  val toolName: String,
  val summary: String,
  val modeCaption: String,
  val decisionsAccepted: Boolean
)

data class PlanChoice(val path: String, val caption: String)

data class TargetChoice(val path: String, val caption: String)

data class TargetsMessage(val current: String, val choices: List<TargetChoice>)

data class ConversationChoice(val id: String, val title: String, val current: Boolean)

data class ConversationsMessage(val current: String, val choices: List<ConversationChoice>, val truncated: Boolean)

data class ModelChoice(val id: String, val caption: String)

data class ModelsMessage(val current: String, val backend: String, val choices: List<ModelChoice>, val note: String)

data class ReasoningChoice(val id: String, val caption: String)

data class ReasoningMessage(val current: String, val choices: List<ReasoningChoice>, val note: String)

data class PermissionChoice(val id: String, val caption: String)

data class PermissionsMessage(
  val current: String,
  val backend: String,
  val choices: List<PermissionChoice>,
  val note: String
)

data class PlanMessage(val path: String, val title: String, val running: Boolean, val rows: List<PlanRow>, val choices: List<PlanChoice>? = null)

data class WireSnapshot(
  val view: WireView,
  val storedTurns: List<WireTurn>,
  val live: WireTurn?,
  val planPath: String,
  val planTitle: String,
  val planRunning: Boolean,
  val planRows: List<PlanRow>,
  val taskRows: List<TaskRow>,
  val approval: ApprovalNotice
)

data class WireResume(val epoch: String, val cursor: Long)

data class WirePatch(
  val epoch: String,
  val cursor: Long,
  val turnIndex: Int,
  val turnId: String,
  val blocks: List<WireBlock>,
  val busy: Boolean,
  val sending: Boolean,
  val planRunning: Boolean,
  val phase: String,
  val canSend: Boolean,
  val canSteer: Boolean,
  val canStop: Boolean,
  val elapsedMs: Int,
  val part: Int = 1,
  val partCount: Int = 1,
  val hasView: Boolean = false,
  val model: String = "",
  val signedIn: Boolean = false,
  val statusText: String = ""
)

data class WireCatchup(
  val mode: String,
  val epoch: String,
  val cursor: Long,
  val conversationId: String,
  val projectRoot: String,
  val title: String,
  val snapshot: WireSnapshot?,
  val patches: List<WirePatch>
)

data class WireConversationClosed(
  val epoch: String,
  val cursor: Long,
  val conversationId: String,
  val title: String
)

data class WireTranscript(
  val turnIndex: Int,
  val revision: Int,
  val phase: String,
  val statusText: String,
  val blocks: List<WireBlock>,
  val part: Int = 1,
  val partCount: Int = 1,
  val durationMs: Int = 0
)

fun modeIsKnown(mode: String): Boolean = mode in ModeNames

fun rejectedReasonIsKnown(reason: String): Boolean = reason in RejectedReasons

fun approvalCloseReasonIsKnown(reason: String): Boolean = reason in ApprovalCloseReasons

fun imageUnavailableReasonIsKnown(reason: String): Boolean = reason in ImageUnavailableReasons

private fun blankMessage(): MonitorMessage {
  return MonitorMessage(0, "", MessageKind.Unknown, "", "", "", false, "")
}

fun encodeEnvelope(kind: MessageKind, id: String, payload: JsonValue.Obj?): String {
  if (kind == MessageKind.Unknown || !messageIdIsSafe(id)) return ""
  val root = JsonObjectBuilder()
  root.add("v", MonitorLimits.CatalogueVersion)
  root.add("id", id)
  root.add("type", kind.wireName)
  root.add("payload", payload ?: JsonValue.Obj(emptyList()))
  val text = root.build().toFpJson()
  if (utf8Length(text) > MonitorLimits.MaxPayloadBytes) return ""
  return text
}

private fun encodeOneString(kind: MessageKind, id: String, field: String, value: String): String {
  val payload = JsonObjectBuilder()
  payload.add(field, value)
  return encodeEnvelope(kind, id, payload.build())
}

fun encodeError(id: String, reason: String, messageText: String, refId: String): String {
  val payload = JsonObjectBuilder()
  payload.add("reason", reason)
  payload.add("message", messageText)
  payload.add("ref", refId)
  return encodeEnvelope(MessageKind.Error, id, payload.build())
}

private fun shownTypeName(typeName: String): String {
  val bytes = strictUtf8Bytes(typeName) ?: return ""
  if (bytes.size <= MonitorLimits.MaxMessageIdChars) return typeName
  var end = MonitorLimits.MaxMessageIdChars
  while (end > 0 && (bytes[end].toInt() and 0xC0) == 0x80) end--
  if (end < 1) end = 1
  return bytes.copyOf(end).toString(Charsets.UTF_8)
}

fun unknownTypeError(refId: String, typeName: String): String {
  val shown = shownTypeName(typeName)
  return encodeError(refId, UnknownTypeReason, "Unknown message type $shown.", refId)
}

fun decodeError(payloadJson: String): ErrorBody? {
  val obj = parseObject(payloadJson) ?: return null
  return decodeError(obj)
}

fun decodeError(obj: JsonValue.Obj): ErrorBody? {
  val reason = obj.readString("reason", true)
  val messageText = obj.readString("message", true)
  val refId = obj.readString("ref", true)
  if (!reason.ok || !messageText.ok || !refId.ok) return null
  return ErrorBody(reason.value, messageText.value, refId.value)
}

private fun applyTextLimit(message: MonitorMessage): MonitorMessage {
  if (message.kind != MessageKind.Send && message.kind != MessageKind.Steer) return message
  val text = when (val body = message.inbound) {
    is InboundPayload.Text -> body.text
    else -> {
      val obj = parseObject(message.payloadJson) ?: return message
      val read = obj.readString("text", false)
      if (!read.ok) return message
      read.value
    }
  }
  if (utf8Length(text) <= MonitorLimits.MaxSendChars) return message
  val wire = encodeError(message.id, PayloadTooLargeReason, PayloadTooLargeMessage, message.id)
  return message.copy(
    kind = MessageKind.Error,
    typeName = "error",
    reason = PayloadTooLargeReason,
    changesState = false,
    wireJson = wire
  )
}

fun tryDecodeEnvelope(frame: MonitorFrame): EnvelopeResult {
  val root = frame.parsed ?: return tryDecodeEnvelope(frame.json)
  return decodeEnvelope(root, frame.json)
}

fun tryDecodeEnvelope(json: String): EnvelopeResult {
  val parsed = parseJson(json)
  if (parsed == null) {
    return EnvelopeResult(false, blankMessage(), "A monitor message must be a JSON object.")
  }
  val root = parsed as? JsonValue.Obj
    ?: return EnvelopeResult(false, blankMessage(), "A monitor message must be a JSON object.")
  return decodeEnvelope(root, json)
}

private fun decodeEnvelope(root: JsonValue.Obj, wireJson: String): EnvelopeResult {
  val checked = checkEnvelope(root)
  if (!checked.ok) return EnvelopeResult(false, blankMessage(), checked.errorText)
  val payload = checked.payload
  val payloadJson = checked.payloadJson
  val kind = MessageKind.fromWire(checked.typeName)
  val message = if (kind == MessageKind.Unknown) {
    MonitorMessage(
      MonitorLimits.CatalogueVersion,
      checked.id,
      MessageKind.Error,
      checked.typeName,
      payloadJson,
      UnknownTypeReason,
      false,
      unknownTypeError(checked.id, checked.typeName)
    )
  } else {
    val reason = payload.field("reason")
    val reasonText = if (reason is JsonValue.Str) reason.text else ""
    applyTextLimit(MonitorMessage(
      MonitorLimits.CatalogueVersion,
      checked.id,
      kind,
      checked.typeName,
      payloadJson,
      reasonText,
      true,
      wireJson,
      inboundPayload(kind, payload)
    ))
  }
  return EnvelopeResult(true, message, "")
}

fun inboundPayload(kind: MessageKind, payload: JsonValue.Obj): InboundPayload {
  return when (kind) {
    MessageKind.Snapshot -> decodeSnapshot(payload)?.let { InboundPayload.Snapshot(it) } ?: InboundPayload.None
    MessageKind.Transcript -> decodeTranscript(payload)?.let { InboundPayload.TranscriptPart(it) } ?: InboundPayload.None
    MessageKind.ImageData -> decodeImagePart(payload) ?: InboundPayload.None
    MessageKind.TurnData -> turnFromJson(payload, false)?.let { InboundPayload.Turn(it) } ?: InboundPayload.None
    MessageKind.Status -> statusFromJson(payload)?.let { InboundPayload.Status(it) } ?: InboundPayload.None
    MessageKind.Mode -> decodeMode(payload)?.let { InboundPayload.Mode(it) } ?: InboundPayload.None
    MessageKind.Target -> decodeTarget(payload)?.let { InboundPayload.Target(it) } ?: InboundPayload.None
    MessageKind.Targets -> decodeTargets(payload)?.let { InboundPayload.Targets(it) } ?: InboundPayload.None
    MessageKind.Conversations -> decodeConversations(payload)?.let { InboundPayload.Conversations(it) } ?: InboundPayload.None
    MessageKind.Models -> decodeModels(payload)?.let { InboundPayload.Models(it) } ?: InboundPayload.None
    MessageKind.Reasoning -> decodeReasoning(payload)?.let { InboundPayload.Reasoning(it) } ?: InboundPayload.None
    MessageKind.Permissions -> decodePermissions(payload)?.let { InboundPayload.Permissions(it) } ?: InboundPayload.None
    MessageKind.Plan -> decodePlan(payload)?.let { InboundPayload.Plan(it) } ?: InboundPayload.None
    MessageKind.ApprovalRequested -> decodeApprovalRequested(payload)?.let { InboundPayload.ApprovalRequest(it) } ?: InboundPayload.None
    MessageKind.InsertResult -> decodeText(payload)?.let { InboundPayload.Insert(it) } ?: InboundPayload.None
    MessageKind.Error -> decodeError(payload)?.let { InboundPayload.Error(it) } ?: InboundPayload.None
    MessageKind.Rejected -> decodeRejected(payload)?.let { InboundPayload.Rejected(it) } ?: InboundPayload.None
    MessageKind.ImageUnavailable -> decodeImageUnavailable(payload)?.let { InboundPayload.ImageMissing(it) } ?: InboundPayload.None
    MessageKind.PairOk -> decodePairOk(payload)?.let { InboundPayload.PairOk(it) } ?: InboundPayload.None
    MessageKind.HelloOk -> decodeHelloOk(payload)?.let { InboundPayload.HelloOk(it) } ?: InboundPayload.None
    MessageKind.Resume -> decodeResume(payload)?.let { InboundPayload.Resume(it) } ?: InboundPayload.None
    MessageKind.Patch -> decodePatch(payload)?.let { InboundPayload.Patch(it) } ?: InboundPayload.None
    MessageKind.Catchup -> decodeCatchup(payload)?.let { InboundPayload.Catchup(it) } ?: InboundPayload.None
    MessageKind.ConversationClosed -> decodeConversationClosed(payload)?.let { InboundPayload.ConversationClosed(it) }
      ?: InboundPayload.None
    MessageKind.Send, MessageKind.Steer -> {
      val text = payload.readString("text", true)
      if (text.ok) InboundPayload.Text(text.value) else InboundPayload.None
    }
    else -> InboundPayload.None
  }
}

fun encodeHello(id: String, clientName: String, clientVersion: String, clientId: String): String {
  val payload = JsonObjectBuilder()
  payload.add("client_name", clientName)
  payload.add("client_version", clientVersion)
  if (clientId.isNotEmpty()) payload.add("client_id", clientId)
  return encodeEnvelope(MessageKind.Hello, id, payload.build())
}

fun decodeHello(payloadJson: String): HelloMessage? {
  val payload = parseObject(payloadJson) ?: return null
  val hasClientId = payload.has("client_id")
  val name = payload.readString("client_name", true)
  val version = payload.readString("client_version", true)
  if (!name.ok || !version.ok) return null
  if (!hasClientId) return HelloMessage(name.value, version.value, "", false)
  val clientId = payload.readString("client_id", true)
  if (!clientId.ok) return null
  return HelloMessage(name.value, version.value, clientId.value, true)
}

fun encodePair(id: String, code: String, fingerprint: String): String {
  val payload = JsonObjectBuilder()
  payload.add("code", code)
  payload.add("fingerprint", fingerprint)
  return encodeEnvelope(MessageKind.Pair, id, payload.build())
}

fun decodePair(payloadJson: String): PairMessage? {
  val obj = parseObject(payloadJson) ?: return null
  val code = obj.readString("code", true)
  val fingerprint = obj.readString("fingerprint", true)
  if (!code.ok || !fingerprint.ok) return null
  return PairMessage(code.value, fingerprint.value)
}

fun encodePairOk(id: String, clientId: String, sessionToken: String): String {
  val payload = JsonObjectBuilder()
  payload.add("client_id", clientId)
  payload.add("session_token", sessionToken)
  return encodeEnvelope(MessageKind.PairOk, id, payload.build())
}

fun decodePairOk(payloadJson: String): PairOkMessage? {
  val obj = parseObject(payloadJson) ?: return null
  return decodePairOk(obj)
}

fun decodePairOk(obj: JsonValue.Obj): PairOkMessage? {
  val clientId = obj.readString("client_id", true)
  val token = obj.readString("session_token", true)
  if (!clientId.ok || !token.ok) return null
  return PairOkMessage(clientId.value, token.value)
}

fun encodeHelloOk(id: String, hello: HelloOkMessage): String {
  val payload = JsonObjectBuilder()
  payload.add("nonce", hello.nonce)
  payload.add("server_name", hello.serverName)
  payload.add("epoch", hello.epoch)
  payload.add("cursor", hello.cursor)
  payload.add("conversation_id", hello.conversationId)
  payload.add("project_root", hello.projectRoot)
  payload.add("title", hello.title)
  if (hostIdIsValid(hello.hostId)) payload.add("host_id", hello.hostId)
  return encodeEnvelope(MessageKind.HelloOk, id, payload.build())
}

fun decodeHelloOk(payloadJson: String): HelloOkMessage? {
  val obj = parseObject(payloadJson) ?: return null
  return decodeHelloOk(obj)
}

fun decodeHelloOk(obj: JsonValue.Obj): HelloOkMessage? {
  val nonce = obj.readString("nonce", true)
  val serverName = obj.readString("server_name", true)
  val epoch = obj.readString("epoch", true)
  val cursor = obj.readLong("cursor", true)
  val conversationId = obj.readString("conversation_id", true)
  val projectRoot = obj.readString("project_root", true)
  val title = obj.readString("title", true)
  if (!nonce.ok || !serverName.ok || !epoch.ok || !cursor.ok || !conversationId.ok || !projectRoot.ok || !title.ok) {
    return null
  }
  val hostRead = obj.readString("host_id", false)
  val hostId = if (hostRead.ok && hostIdIsValid(hostRead.value)) hostRead.value else ""
  return HelloOkMessage(nonce.value, serverName.value, epoch.value, cursor.value, conversationId.value,
    projectRoot.value, title.value, hostId)
}

fun encodeAuth(id: String, clientId: String, hmac: String): String {
  val payload = JsonObjectBuilder()
  payload.add("client_id", clientId)
  payload.add("hmac", hmac)
  return encodeEnvelope(MessageKind.Auth, id, payload.build())
}

fun decodeAuth(payloadJson: String): AuthMessage? {
  val obj = parseObject(payloadJson) ?: return null
  val clientId = obj.readString("client_id", true)
  val hmac = obj.readString("hmac", true)
  if (!clientId.ok || !hmac.ok) return null
  return AuthMessage(clientId.value, hmac.value)
}

fun encodeRejected(id: String, reason: String, hostVersion: Int, clientVersion: Int): String {
  if (!rejectedReasonIsKnown(reason)) return ""
  val payload = JsonObjectBuilder()
  payload.add("reason", reason)
  payload.add("host_version", hostVersion)
  payload.add("client_version", clientVersion)
  return encodeEnvelope(MessageKind.Rejected, id, payload.build())
}

fun decodeRejected(payloadJson: String): RejectedMessage? {
  val obj = parseObject(payloadJson) ?: return null
  return decodeRejected(obj)
}

fun decodeRejected(obj: JsonValue.Obj): RejectedMessage? {
  val reason = obj.readString("reason", true)
  val hostVersion = obj.readInt("host_version", true)
  val clientVersion = obj.readInt("client_version", true)
  if (!reason.ok || !hostVersion.ok || !clientVersion.ok || !rejectedReasonIsKnown(reason.value)) return null
  return RejectedMessage(reason.value, hostVersion.value, clientVersion.value)
}

fun encodeBye(id: String, reason: String): String = encodeOneString(MessageKind.Bye, id, "reason", reason)

fun decodeBye(payloadJson: String): ByeMessage? {
  val obj = parseObject(payloadJson) ?: return null
  val reason = obj.readString("reason", true)
  if (!reason.ok) return null
  return ByeMessage(reason.value)
}

private fun tryEncodeLimitedText(kind: MessageKind, id: String, text: String): TextEncode {
  if (utf8Length(text) > MonitorLimits.MaxSendChars) {
    return TextEncode(false, "", encodeError(id, PayloadTooLargeReason, PayloadTooLargeMessage, id))
  }
  val json = encodeOneString(kind, id, "text", text)
  return TextEncode(json.isNotEmpty(), json, "")
}

fun tryEncodeSend(id: String, text: String): TextEncode = tryEncodeLimitedText(MessageKind.Send, id, text)

fun tryEncodeSteer(id: String, text: String): TextEncode = tryEncodeLimitedText(MessageKind.Steer, id, text)

fun decodeText(payloadJson: String): String? {
  val obj = parseObject(payloadJson) ?: return null
  return decodeText(obj)
}

fun decodeText(obj: JsonValue.Obj): String? {
  val text = obj.readString("text", true)
  if (!text.ok || utf8Length(text.value) > MonitorLimits.MaxSendChars) return null
  return text.value
}

fun encodeEmpty(kind: MessageKind, id: String): String = encodeEnvelope(kind, id, null)

fun encodeSetMode(id: String, mode: String): String {
  if (!modeIsKnown(mode)) return ""
  return encodeOneString(MessageKind.SetMode, id, "mode", mode)
}

fun decodeSetMode(payloadJson: String): String? {
  val obj = parseObject(payloadJson) ?: return null
  val mode = obj.readString("mode", true)
  if (!mode.ok || !modeIsKnown(mode.value)) return null
  return mode.value
}

fun encodeMode(id: String, mode: String, locked: Boolean): String {
  val payload = JsonObjectBuilder()
  payload.add("mode", mode)
  payload.add("locked", locked)
  return encodeEnvelope(MessageKind.Mode, id, payload.build())
}

fun decodeMode(payloadJson: String): ModeMessage? {
  val obj = parseObject(payloadJson) ?: return null
  return decodeMode(obj)
}

fun decodeMode(obj: JsonValue.Obj): ModeMessage? {
  val mode = obj.readString("mode", true)
  val locked = obj.readBool("locked", true)
  if (!mode.ok || !locked.ok) return null
  return ModeMessage(mode.value, locked.value)
}

/** Request the desktop plan combobox without replacing conversation state. */
fun encodePlanChoices(id: String): String {
  val payload = JsonObjectBuilder()
  payload.add("text", "plan_choices")
  return encodeEnvelope(MessageKind.Refresh, id, payload.build())
}

/** Request the drawer lists when a snapshot follow-up did not arrive. Not a stall probe. */
fun encodeMenuChoices(id: String): String {
  val payload = JsonObjectBuilder()
  payload.add("text", "menu_choices")
  return encodeEnvelope(MessageKind.Refresh, id, payload.build())
}

fun encodeTurnRequest(id: String, turnIndex: Int): String {
  val payload = JsonObjectBuilder()
  payload.add("turn_index", turnIndex)
  return encodeEnvelope(MessageKind.Turn, id, payload.build())
}

fun decodeTurnRequest(payloadJson: String): Int? {
  val obj = parseObject(payloadJson) ?: return null
  val index = obj.readInt("turn_index", true)
  if (!index.ok) return null
  return index.value
}

fun encodeTarget(id: String, kind: String, display: String, root: String): String {
  val payload = JsonObjectBuilder()
  payload.add("kind", kind)
  payload.add("display", display)
  payload.add("root", root)
  return encodeEnvelope(MessageKind.Target, id, payload.build())
}

fun decodeTarget(payloadJson: String): TargetMessage? {
  val obj = parseObject(payloadJson) ?: return null
  return decodeTarget(obj)
}

fun decodeTarget(obj: JsonValue.Obj): TargetMessage? {
  val kind = obj.readString("kind", true)
  val display = obj.readString("display", true)
  val root = obj.readString("root", true)
  if (!kind.ok || !display.ok || !root.ok) return null
  return TargetMessage(kind.value, display.value, root.value)
}

fun encodePath(kind: MessageKind, id: String, path: String): String {
  if (kind != MessageKind.SelectPlan && kind != MessageKind.RemovePlan && kind != MessageKind.SelectTarget) return ""
  return encodeOneString(kind, id, "path", path)
}

fun encodeTargets(id: String, current: String, choices: List<TargetChoice>): String {
  val payload = JsonObjectBuilder()
  payload.add("current", current)
  payload.add("choices", JsonValue.Arr(choices.map { choice ->
    val row = JsonObjectBuilder()
    row.add("path", choice.path)
    row.add("caption", choice.caption)
    row.build()
  }))
  return encodeEnvelope(MessageKind.Targets, id, payload.build())
}

fun decodeTargets(payloadJson: String): TargetsMessage? {
  val obj = parseObject(payloadJson) ?: return null
  return decodeTargets(obj)
}

fun decodeTargets(obj: JsonValue.Obj): TargetsMessage? {
  val current = obj.readString("current", true)
  if (!current.ok) return null
  val choices = rowsFrom(obj.field("choices")) { choice ->
    val path = choice.readString("path", true)
    val caption = choice.readString("caption", true)
    if (!path.ok || !caption.ok) null else TargetChoice(path.value, caption.value)
  } ?: return null
  return TargetsMessage(current.value, choices)
}

fun encodeConversations(id: String, current: String, choices: List<ConversationChoice>, truncated: Boolean): String {
  val payload = JsonObjectBuilder()
  payload.add("current", current)
  payload.add("choices", JsonValue.Arr(choices.map { choice ->
    val row = JsonObjectBuilder()
    row.add("id", choice.id)
    row.add("title", choice.title)
    row.add("current", choice.current)
    row.build()
  }))
  payload.add("truncated", truncated)
  return encodeEnvelope(MessageKind.Conversations, id, payload.build())
}

fun decodeConversations(payloadJson: String): ConversationsMessage? {
  val obj = parseObject(payloadJson) ?: return null
  return decodeConversations(obj)
}

fun decodeConversations(obj: JsonValue.Obj): ConversationsMessage? {
  val current = obj.readString("current", true)
  if (!current.ok) return null
  val truncated = obj.readBool("truncated", true)
  if (!truncated.ok) return null
  val choices = rowsFrom(obj.field("choices")) { choice ->
    val archiveId = choice.readString("id", true)
    val title = choice.readString("title", true)
    val selected = choice.readBool("current", true)
    if (!archiveId.ok || !title.ok || !selected.ok) null else ConversationChoice(archiveId.value, title.value, selected.value)
  } ?: return null
  return ConversationsMessage(current.value, choices, truncated.value)
}

fun encodeSelectConversation(id: String, archiveId: String): String {
  return encodeOneString(MessageKind.SelectConversation, id, "id", archiveId)
}

fun decodeSelectConversation(payloadJson: String): String? {
  val obj = parseObject(payloadJson) ?: return null
  val archiveId = obj.readString("id", true)
  if (!archiveId.ok) return null
  return archiveId.value
}

private fun encodeNamedChoices(
  kind: MessageKind,
  id: String,
  current: String,
  note: String,
  choices: List<Pair<String, String>>,
  extraName: String = "",
  extraValue: String = ""
): String {
  val payload = JsonObjectBuilder()
  payload.add("current", current)
  if (extraName.isNotEmpty()) payload.add(extraName, extraValue)
  payload.add("choices", JsonValue.Arr(choices.map { choice ->
    val row = JsonObjectBuilder()
    row.add("id", choice.first)
    row.add("caption", choice.second)
    row.build()
  }))
  payload.add("note", note)
  return encodeEnvelope(kind, id, payload.build())
}

private fun decodeNamedChoices(obj: JsonValue.Obj, extraName: String = ""): Triple<String, String, List<Pair<String, String>>>? {
  val current = obj.readString("current", true)
  if (!current.ok) return null
  val extra = if (extraName.isEmpty()) null else obj.readString(extraName, true)
  if (extra != null && !extra.ok) return null
  val note = obj.readString("note", true)
  if (!note.ok) return null
  val choices = rowsFrom(obj.field("choices")) { choice ->
    val choiceId = choice.readString("id", true)
    val caption = choice.readString("caption", true)
    if (!choiceId.ok || !caption.ok) null else choiceId.value to caption.value
  } ?: return null
  return Triple(current.value, note.value, choices)
}

fun encodeModels(id: String, current: String, backend: String, note: String, choices: List<ModelChoice>): String {
  return encodeNamedChoices(MessageKind.Models, id, current, note, choices.map { it.id to it.caption }, "backend", backend)
}

fun decodeModels(payloadJson: String): ModelsMessage? {
  val obj = parseObject(payloadJson) ?: return null
  return decodeModels(obj)
}

fun decodeModels(obj: JsonValue.Obj): ModelsMessage? {
  val parsed = decodeNamedChoices(obj, "backend") ?: return null
  val backend = obj.readString("backend", true)
  if (!backend.ok) return null
  return ModelsMessage(parsed.first, backend.value, parsed.third.map { ModelChoice(it.first, it.second) }, parsed.second)
}

fun encodeSetModel(id: String, modelId: String): String {
  return encodeOneString(MessageKind.SetModel, id, "model", modelId)
}

fun decodeSetModel(payloadJson: String): String? {
  val obj = parseObject(payloadJson) ?: return null
  val modelId = obj.readString("model", true)
  if (!modelId.ok) return null
  return modelId.value
}

fun encodeSetReasoning(id: String, level: String): String {
  return encodeOneString(MessageKind.SetReasoning, id, "level", level)
}

fun decodeSetReasoning(payloadJson: String): String? {
  val obj = parseObject(payloadJson) ?: return null
  val level = obj.readString("level", true)
  if (!level.ok) return null
  return level.value
}

fun encodeReasoning(id: String, current: String, note: String, choices: List<ReasoningChoice>): String {
  return encodeNamedChoices(MessageKind.Reasoning, id, current, note, choices.map { it.id to it.caption })
}

fun decodeReasoning(payloadJson: String): ReasoningMessage? {
  val obj = parseObject(payloadJson) ?: return null
  return decodeReasoning(obj)
}

fun decodeReasoning(obj: JsonValue.Obj): ReasoningMessage? {
  val parsed = decodeNamedChoices(obj) ?: return null
  return ReasoningMessage(parsed.first, parsed.third.map { ReasoningChoice(it.first, it.second) }, parsed.second)
}

fun encodePermissions(id: String, current: String, backend: String, note: String, choices: List<PermissionChoice>): String {
  return encodeNamedChoices(MessageKind.Permissions, id, current, note, choices.map { it.id to it.caption }, "backend", backend)
}

fun decodePermissions(payloadJson: String): PermissionsMessage? {
  val obj = parseObject(payloadJson) ?: return null
  return decodePermissions(obj)
}

fun decodePermissions(obj: JsonValue.Obj): PermissionsMessage? {
  val parsed = decodeNamedChoices(obj, "backend") ?: return null
  val backend = obj.readString("backend", true)
  if (!backend.ok) return null
  return PermissionsMessage(parsed.first, backend.value, parsed.third.map { PermissionChoice(it.first, it.second) }, parsed.second)
}

fun encodeSetPermissions(id: String, approval: String): String {
  return encodeOneString(MessageKind.SetPermissions, id, "approval", approval)
}

fun decodeSetPermissions(payloadJson: String): String? {
  val obj = parseObject(payloadJson) ?: return null
  val approval = obj.readString("approval", true)
  if (!approval.ok) return null
  return approval.value
}

fun decodePath(payloadJson: String): String? {
  val obj = parseObject(payloadJson) ?: return null
  val path = obj.readString("path", true)
  if (!path.ok) return null
  return path.value
}

fun encodeNewPlan(id: String, title: String, hasTitle: Boolean): String {
  val payload = JsonObjectBuilder()
  if (hasTitle) payload.add("title", title)
  return encodeEnvelope(MessageKind.NewPlan, id, payload.build())
}

fun decodeNewPlan(payloadJson: String): NewPlanMessage? {
  val obj = parseObject(payloadJson) ?: return null
  if (!obj.has("title")) return NewPlanMessage("", false)
  val title = obj.readString("title", true)
  if (!title.ok) return null
  return NewPlanMessage(title.value, true)
}

fun encodeWorkOnPlan(id: String, index: Int): String {
  val payload = JsonObjectBuilder()
  payload.add("index", index)
  return encodeEnvelope(MessageKind.WorkOnPlan, id, payload.build())
}

fun decodeWorkOnPlan(payloadJson: String): Int? {
  val obj = parseObject(payloadJson) ?: return null
  val index = obj.readInt("index", true)
  if (!index.ok) return null
  return index.value
}

fun encodeTaskCommand(kind: MessageKind, id: String, taskId: String, note: String): String {
  if (kind != MessageKind.RunTask && kind != MessageKind.InsertTask) return ""
  val payload = JsonObjectBuilder()
  payload.add("id", taskId)
  payload.add("note", note)
  return encodeEnvelope(kind, id, payload.build())
}

fun decodeTaskCommand(payloadJson: String): TaskCommand? {
  val obj = parseObject(payloadJson) ?: return null
  val taskId = obj.readString("id", true)
  val note = obj.readString("note", true)
  if (!taskId.ok || !note.ok) return null
  return TaskCommand(taskId.value, note.value)
}

fun encodeInsertResult(id: String, text: String): String = encodeOneString(MessageKind.InsertResult, id, "text", text)

fun encodeTicks(kind: MessageKind, id: String, ticks: Long): String {
  if (kind != MessageKind.Ping && kind != MessageKind.Pong) return ""
  val payload = JsonObjectBuilder()
  payload.add("ticks", ticks)
  return encodeEnvelope(kind, id, payload.build())
}

fun decodeTicks(payloadJson: String): TicksMessage? {
  val obj = parseObject(payloadJson) ?: return null
  val ticks = obj.readLong("ticks", true)
  if (!ticks.ok) return null
  return TicksMessage(ticks.value)
}

fun encodeApprovalRequested(id: String, notice: ApprovalNotice): String {
  val payload = JsonObjectBuilder()
  payload.add("tool_id", notice.toolId)
  payload.add("tool_name", notice.toolName)
  payload.add("summary", notice.summary)
  payload.add("mode_caption", notice.modeCaption)
  payload.add("decisions_accepted", notice.decisionsAccepted)
  return encodeEnvelope(MessageKind.ApprovalRequested, id, payload.build())
}

fun decodeApprovalRequested(payloadJson: String): ApprovalNotice? {
  val obj = parseObject(payloadJson) ?: return null
  return decodeApprovalRequested(obj)
}

fun decodeApprovalRequested(obj: JsonValue.Obj): ApprovalNotice? {
  val toolId = obj.readString("tool_id", true)
  val toolName = obj.readString("tool_name", true)
  val summary = obj.readString("summary", true)
  val caption = obj.readString("mode_caption", true)
  val accepted = obj.readBool("decisions_accepted", true)
  if (!toolId.ok || !toolName.ok || !summary.ok || !caption.ok || !accepted.ok) return null
  return ApprovalNotice(true, toolId.value, toolName.value, summary.value, caption.value, accepted.value)
}

fun encodeApprovalDecision(id: String, toolId: String, allow: Boolean): String {
  val payload = JsonObjectBuilder()
  payload.add("tool_id", toolId)
  payload.add("allow", allow)
  return encodeEnvelope(MessageKind.ApprovalDecision, id, payload.build())
}

fun decodeApprovalDecision(payloadJson: String): ApprovalDecision? {
  val obj = parseObject(payloadJson) ?: return null
  val toolId = obj.readString("tool_id", true)
  val allow = obj.readBool("allow", true)
  if (!toolId.ok || !allow.ok) return null
  return ApprovalDecision(toolId.value, allow.value)
}

fun encodeApprovalClosed(id: String, toolId: String, reason: String): String {
  if (!approvalCloseReasonIsKnown(reason)) return ""
  val payload = JsonObjectBuilder()
  payload.add("tool_id", toolId)
  payload.add("reason", reason)
  return encodeEnvelope(MessageKind.ApprovalClosed, id, payload.build())
}

fun decodeApprovalClosed(payloadJson: String): ApprovalClosed? {
  val obj = parseObject(payloadJson) ?: return null
  val toolId = obj.readString("tool_id", true)
  val reason = obj.readString("reason", true)
  if (!toolId.ok || !reason.ok || !approvalCloseReasonIsKnown(reason.value)) return null
  return ApprovalClosed(toolId.value, reason.value)
}

fun toolBodyForWire(body: String): Pair<String, Boolean> {
  val bytes = strictUtf8Bytes(body) ?: return "" to true
  if (bytes.size <= MonitorLimits.MaxToolBodyChars) return body to false
  var end = MonitorLimits.MaxToolBodyChars
  while (end > 0 && (bytes[end].toInt() and 0xC0) == 0x80) end--
  if (end < 1) end = 1
  return bytes.copyOf(end).toString(Charsets.UTF_8) to true
}

fun splitBody(body: String, revision: Int): List<BodyPart> {
  val bytes = strictUtf8Bytes(body) ?: return listOf(BodyPart(1, 1, revision, ""))
  if (bytes.size <= MonitorLimits.MaxBodyPartBytes) {
    return listOf(BodyPart(1, 1, revision, body))
  }
  val pieces = mutableListOf<String>()
  var start = 0
  while (start < bytes.size) {
    var next = start + MonitorLimits.MaxBodyPartBytes
    if (next >= bytes.size) {
      next = bytes.size
    } else {
      while (next > start && (bytes[next].toInt() and 0xC0) == 0x80) next--
      if (next <= start) next = start + 1
    }
    pieces += bytes.copyOfRange(start, next).toString(Charsets.UTF_8)
    start = next
  }
  return pieces.mapIndexed { index, text -> BodyPart(index + 1, pieces.size, revision, text) }
}

private fun imageToJson(image: WireImage): JsonValue.Obj {
  val obj = JsonObjectBuilder()
  obj.add("id", image.id)
  obj.add("name", image.name)
  obj.add("mime", image.mime)
  obj.add("width", image.width)
  obj.add("height", image.height)
  obj.add("display_path", image.displayPath)
  obj.add("missing", image.missing)
  return obj.build()
}

private fun imageFromJson(obj: JsonValue.Obj): WireImage? {
  val id = obj.readString("id", true)
  val name = obj.readString("name", true)
  val mime = obj.readString("mime", true)
  val width = obj.readInt("width", true)
  val height = obj.readInt("height", true)
  val displayPath = obj.readString("display_path", true)
  val missing = obj.readBool("missing", true)
  if (!id.ok || !name.ok || !mime.ok || !width.ok || !height.ok || !displayPath.ok || !missing.ok) return null
  return WireImage(id.value, name.value, mime.value, width.value, height.value, displayPath.value, missing.value)
}

private fun imagesToJson(images: List<WireImage>): JsonValue.Arr = JsonValue.Arr(images.map { imageToJson(it) })

private fun imagesFromJson(node: JsonValue?): List<WireImage>? {
  if (node == null) return emptyList()
  val array = node as? JsonValue.Arr ?: return null
  return array.items.map { item ->
    val obj = item as? JsonValue.Obj ?: return null
    imageFromJson(obj) ?: return null
  }
}

fun blockToJson(block: WireBlock): JsonValue.Obj {
  val obj = JsonObjectBuilder()
  obj.add("kind", block.kind)
  obj.add("block_id", block.blockId)
  obj.add("title", block.title)
  obj.add("tool_name", block.toolName)
  obj.add("tool_id", block.toolId)
  if (block.kind == "tool") {
    val (body, truncated) = toolBodyForWire(block.body)
    obj.add("body", body)
    if (truncated) obj.add("truncated", true)
  } else {
    obj.add("body", block.body)
  }
  obj.add("running", block.running)
  obj.add("ok", block.ok)
  obj.add("duration_ms", block.durationMs)
  obj.add("images", imagesToJson(block.images))
  if (block.partCount > 1) {
    obj.add("part", block.part)
    obj.add("part_count", block.partCount)
    obj.add("revision", block.revision)
  }
  if (block.appendOffset != null) obj.add("offset", block.appendOffset)
  return obj.build()
}

fun blockFromJson(obj: JsonValue.Obj): WireBlock? {
  val kind = obj.readString("kind", true)
  val blockId = obj.readString("block_id", true)
  val title = obj.readString("title", true)
  val toolName = obj.readString("tool_name", true)
  val toolId = obj.readString("tool_id", true)
  val body = obj.readString("body", true)
  val running = obj.readBool("running", true)
  val ok = obj.readBool("ok", true)
  val duration = obj.readInt("duration_ms", true)
  if (!kind.ok || !blockId.ok || !title.ok || !toolName.ok || !toolId.ok || !body.ok || !running.ok || !ok.ok || !duration.ok) {
    return null
  }
  var truncated = false
  if (kind.value == "tool") {
    val flag = obj.readBool("truncated", false)
    if (!flag.ok) return null
    truncated = flag.value
    if (utf8Length(body.value) > MonitorLimits.MaxToolBodyChars) return null
  }
  val images = imagesFromJson(obj.field("images")) ?: return null
  val part = obj.readInt("part", false)
  val partCount = obj.readInt("part_count", false)
  val revision = obj.readInt("revision", false)
  if (!part.ok || !partCount.ok || !revision.ok) return null
  val offset = obj.readInt("offset", false)
  if (!offset.ok || (obj.field("offset") != null && offset.value < 0)) return null
  return WireBlock(
    kind.value, blockId.value, title.value, toolName.value, toolId.value, body.value,
    running.value, ok.value, duration.value, images, truncated,
    if (part.value < 1) 1 else part.value,
    if (partCount.value < 1) 1 else partCount.value,
    revision.value,
    if (obj.field("offset") == null) null else offset.value
  )
}

private fun addStatusFields(obj: JsonObjectBuilder, view: WireView) {
  obj.add("available", view.available)
  obj.add("busy", view.busy)
  obj.add("sending", view.sending)
  obj.add("mode_locked", view.modeLocked)
  obj.add("plan_running", view.planRunning)
  obj.add("phase", view.phase)
  obj.add("status_text", view.statusText)
  obj.add("elapsed_ms", view.elapsedMs)
  obj.add("model", view.model)
  obj.add("backend", view.backend)
  obj.add("signed_in", view.signedIn)
  obj.add("approval_caption", view.approvalCaption)
  obj.add("effort", view.effort)
  obj.add("skill", view.skill)
  obj.add("context_text", view.contextText)
  obj.add("can_send", view.canSend)
  obj.add("can_steer", view.canSteer)
  obj.add("can_stop", view.canStop)
  obj.add("can_change_mode", view.canChangeMode)
  obj.add("remote_approval", view.remoteApproval)
  obj.add("error_text", view.errorText)
}

private fun readStatusFields(obj: JsonValue.Obj): WireView? {
  val available = obj.readBool("available", true)
  val busy = obj.readBool("busy", true)
  val sending = obj.readBool("sending", true)
  val modeLocked = obj.readBool("mode_locked", true)
  val planRunning = obj.readBool("plan_running", true)
  val phase = obj.readString("phase", true)
  val statusText = obj.readString("status_text", true)
  val model = obj.readString("model", true)
  val backend = obj.readString("backend", true)
  val signedIn = obj.readBool("signed_in", true)
  val approvalCaption = obj.readString("approval_caption", true)
  val effort = obj.readString("effort", true)
  val skill = obj.readString("skill", true)
  val contextText = obj.readString("context_text", true)
  val canSend = obj.readBool("can_send", true)
  val canSteer = obj.readBool("can_steer", true)
  val canStop = obj.readBool("can_stop", true)
  val canChangeMode = obj.readBool("can_change_mode", true)
  val remoteApproval = obj.readBool("remote_approval", true)
  val errorText = obj.readString("error_text", true)
  val elapsedMs = obj.readInt("elapsed_ms", false)
  if (!available.ok || !busy.ok || !sending.ok || !modeLocked.ok || !planRunning.ok || !phase.ok || !statusText.ok ||
    !model.ok || !backend.ok || !signedIn.ok || !approvalCaption.ok || !effort.ok || !skill.ok || !contextText.ok ||
    !canSend.ok || !canSteer.ok || !canStop.ok || !canChangeMode.ok || !remoteApproval.ok || !errorText.ok ||
    !elapsedMs.ok) {
    return null
  }
  return WireView(
    available.value, busy.value, sending.value, modeLocked.value, planRunning.value, phase.value, statusText.value,
    model.value, backend.value, signedIn.value, approvalCaption.value, effort.value, skill.value, contextText.value,
    canSend.value, canSteer.value, canStop.value, canChangeMode.value, remoteApproval.value, errorText.value,
    elapsedMs.value.coerceAtLeast(0)
  )
}

fun statusToJson(view: WireView): JsonValue.Obj {
  val obj = JsonObjectBuilder()
  addStatusFields(obj, view)
  return obj.build()
}

fun statusFromJson(obj: JsonValue.Obj): WireView? = readStatusFields(obj)

fun decodeStatusPayload(payloadJson: String): WireView? {
  val obj = parseObject(payloadJson) ?: return null
  return statusFromJson(obj)
}

fun viewToJson(view: WireView): JsonValue.Obj {
  val obj = JsonObjectBuilder()
  addStatusFields(obj, view)
  obj.add("mode", view.mode)
  obj.add("target_kind", view.targetKind)
  obj.add("target_display", view.targetDisplay)
  obj.add("target_root", view.targetRoot)
  obj.add("plan_path", view.planPath)
  obj.add("plan_title", view.planTitle)
  return obj.build()
}

fun viewFromJson(obj: JsonValue.Obj): WireView? {
  val status = readStatusFields(obj) ?: return null
  val mode = obj.readString("mode", true)
  val targetKind = obj.readString("target_kind", true)
  val targetDisplay = obj.readString("target_display", true)
  val targetRoot = obj.readString("target_root", true)
  val planPath = obj.readString("plan_path", true)
  val planTitle = obj.readString("plan_title", true)
  if (!mode.ok || !targetKind.ok || !targetDisplay.ok || !targetRoot.ok || !planPath.ok || !planTitle.ok) return null
  return status.copy(
    mode = mode.value,
    targetKind = targetKind.value,
    targetDisplay = targetDisplay.value,
    targetRoot = targetRoot.value,
    planPath = planPath.value,
    planTitle = planTitle.value
  )
}

private fun blocksFromJson(node: JsonValue?): List<WireBlock>? {
  if (node == null) return emptyList()
  val array = node as? JsonValue.Arr ?: return null
  return array.items.map { item ->
    val obj = item as? JsonValue.Obj ?: return null
    blockFromJson(obj) ?: return null
  }
}

fun turnToJson(turn: WireTurn, indexOnly: Boolean): JsonValue.Obj {
  val obj = JsonObjectBuilder()
  obj.add("turn_index", turn.turnIndex)
  obj.add("id", turn.id)
  obj.add("mode", turn.mode)
  obj.add("created_at", turn.createdAt)
  obj.add("prompt_preview", turn.promptPreview)
  obj.add("error_text", turn.errorText)
  if (!indexOnly) {
    obj.add("prompt", turn.prompt)
    obj.add("thinking", turn.thinking)
    obj.add("response", turn.response)
    obj.add("duration_ms", turn.durationMs)
    obj.add("live", turn.live)
    obj.add("blocks", JsonValue.Arr(turn.blocks.map { blockToJson(it.copy(part = 1, partCount = 1, revision = 0)) }))
    obj.add("images", imagesToJson(turn.images))
  }
  return obj.build()
}

fun turnFromJson(obj: JsonValue.Obj, indexOnly: Boolean): WireTurn? {
  val turnIndex = obj.readInt("turn_index", true)
  val id = obj.readString("id", true)
  val mode = obj.readString("mode", true)
  val createdAt = obj.readString("created_at", true)
  val preview = obj.readString("prompt_preview", true)
  val errorText = obj.readString("error_text", true)
  if (!turnIndex.ok || !id.ok || !mode.ok || !createdAt.ok || !preview.ok || !errorText.ok) return null
  if (indexOnly) {
    return WireTurn(turnIndex.value, id.value, mode.value, createdAt.value, preview.value, errorText.value)
  }
  val prompt = obj.readString("prompt", true)
  val thinking = obj.readString("thinking", true)
  val response = obj.readString("response", true)
  val duration = obj.readInt("duration_ms", true)
  val live = obj.readBool("live", true)
  if (!prompt.ok || !thinking.ok || !response.ok || !duration.ok || !live.ok) return null
  val blocks = blocksFromJson(obj.field("blocks")) ?: return null
  val images = imagesFromJson(obj.field("images")) ?: return null
  return WireTurn(
    turnIndex.value, id.value, mode.value, createdAt.value, preview.value, errorText.value,
    prompt.value, thinking.value, response.value, duration.value, live.value, blocks, images
  )
}

fun encodeTurnData(id: String, turn: WireTurn): String = encodeEnvelope(MessageKind.TurnData, id, turnToJson(turn, false))

fun decodeTurnData(payloadJson: String): WireTurn? {
  val obj = parseObject(payloadJson) ?: return null
  return turnFromJson(obj, false)
}

private fun planRowToJson(row: PlanRow): JsonValue.Obj {
  val obj = JsonObjectBuilder()
  obj.add("index", row.index)
  obj.add("level", row.level)
  obj.add("title", row.title)
  obj.add("parent_title", row.parentTitle)
  obj.add("status", row.status)
  obj.add("actionable", row.actionable)
  return obj.build()
}

private fun planRowFromJson(obj: JsonValue.Obj): PlanRow? {
  val index = obj.readInt("index", true)
  val level = obj.readInt("level", true)
  val title = obj.readString("title", true)
  val parent = obj.readString("parent_title", true)
  val status = obj.readString("status", true)
  val actionable = obj.readBool("actionable", true)
  if (!index.ok || !level.ok || !title.ok || !parent.ok || !status.ok || !actionable.ok) return null
  return PlanRow(index.value, level.value, title.value, parent.value, status.value, actionable.value)
}

private fun taskRowToJson(row: TaskRow): JsonValue.Obj {
  val obj = JsonObjectBuilder()
  obj.add("id", row.id)
  obj.add("title", row.title)
  obj.add("summary", row.summary)
  obj.add("mode", row.mode)
  obj.add("kind", row.kind)
  obj.add("scope", row.scope)
  obj.add("compile_first", row.compileFirst)
  obj.add("enabled", row.enabled)
  obj.add("needs_note", row.needsNote)
  return obj.build()
}

private fun taskRowFromJson(obj: JsonValue.Obj): TaskRow? {
  val id = obj.readString("id", true)
  val title = obj.readString("title", true)
  val summary = obj.readString("summary", true)
  val mode = obj.readString("mode", true)
  val kind = obj.readString("kind", true)
  val scope = obj.readString("scope", true)
  val compileFirst = obj.readBool("compile_first", true)
  val enabled = obj.readBool("enabled", true)
  val needsNote = obj.readBool("needs_note", true)
  if (!id.ok || !title.ok || !summary.ok || !mode.ok || !kind.ok || !scope.ok || !compileFirst.ok || !enabled.ok || !needsNote.ok) {
    return null
  }
  return TaskRow(id.value, title.value, summary.value, mode.value, kind.value, scope.value, compileFirst.value, enabled.value, needsNote.value)
}

private fun <T> rowsFrom(node: JsonValue?, reader: (JsonValue.Obj) -> T?): List<T>? {
  val array = node as? JsonValue.Arr ?: return null
  return array.items.map { item ->
    val obj = item as? JsonValue.Obj ?: return null
    reader(obj) ?: return null
  }
}

fun encodePlan(id: String, path: String, title: String, running: Boolean, rows: List<PlanRow>): String {
  val payload = JsonObjectBuilder()
  payload.add("path", path)
  payload.add("title", title)
  payload.add("running", running)
  payload.add("rows", JsonValue.Arr(rows.map { planRowToJson(it) }))
  return encodeEnvelope(MessageKind.Plan, id, payload.build())
}

fun decodePlan(payloadJson: String): PlanMessage? {
  val obj = parseObject(payloadJson) ?: return null
  return decodePlan(obj)
}

fun decodePlan(obj: JsonValue.Obj): PlanMessage? {
  val path = obj.readString("path", true)
  val title = obj.readString("title", true)
  val running = obj.readBool("running", true)
  if (!path.ok || !title.ok || !running.ok) return null
  val rows = rowsFrom(obj.field("rows")) { planRowFromJson(it) } ?: return null
  val choices = if (!obj.has("choices")) null else {
    rowsFrom(obj.field("choices")) { choice ->
      val choicePath = choice.readString("path", true)
      val caption = choice.readString("caption", true)
      if (!choicePath.ok || !caption.ok || choicePath.value.isEmpty()) null else PlanChoice(choicePath.value, caption.value)
    } ?: return null
  }
  return PlanMessage(path.value, title.value, running.value, rows, choices)
}

fun encodeTasks(id: String, rows: List<TaskRow>): String {
  val payload = JsonObjectBuilder()
  payload.add("rows", JsonValue.Arr(rows.map { taskRowToJson(it) }))
  return encodeEnvelope(MessageKind.Tasks, id, payload.build())
}

fun decodeTasks(payloadJson: String): List<TaskRow>? {
  val obj = parseObject(payloadJson) ?: return null
  return rowsFrom(obj.field("rows")) { taskRowFromJson(it) }
}

private fun approvalToJson(notice: ApprovalNotice): JsonValue.Obj {
  val obj = JsonObjectBuilder()
  obj.add("active", notice.active)
  obj.add("tool_id", notice.toolId)
  obj.add("tool_name", notice.toolName)
  obj.add("summary", notice.summary)
  obj.add("mode_caption", notice.modeCaption)
  obj.add("decisions_accepted", notice.decisionsAccepted)
  return obj.build()
}

private fun approvalFromJson(obj: JsonValue.Obj): ApprovalNotice? {
  val active = obj.readBool("active", true)
  val toolId = obj.readString("tool_id", true)
  val toolName = obj.readString("tool_name", true)
  val summary = obj.readString("summary", true)
  val caption = obj.readString("mode_caption", true)
  val accepted = obj.readBool("decisions_accepted", true)
  if (!active.ok || !toolId.ok || !toolName.ok || !summary.ok || !caption.ok || !accepted.ok) return null
  return ApprovalNotice(active.value, toolId.value, toolName.value, summary.value, caption.value, accepted.value)
}

fun encodeSnapshot(id: String, snapshot: WireSnapshot): String {
  val kept = snapshot.storedTurns.filter { !it.live }
  val start = if (kept.size > MonitorLimits.SnapshotStoredTurns) kept.size - MonitorLimits.SnapshotStoredTurns else 0
  val payload = JsonObjectBuilder()
  payload.add("view", viewToJson(snapshot.view))
  payload.add("turns", JsonValue.Arr(kept.drop(start).map { turnToJson(it, true) }))
  payload.add("live", if (snapshot.live == null) JsonValue.Null else turnToJson(snapshot.live, false))
  val plan = JsonObjectBuilder()
  plan.add("path", snapshot.planPath)
  plan.add("title", snapshot.planTitle)
  plan.add("running", snapshot.planRunning)
  plan.add("rows", JsonValue.Arr(snapshot.planRows.map { planRowToJson(it) }))
  payload.add("plan", plan.build())
  val tasks = JsonObjectBuilder()
  tasks.add("rows", JsonValue.Arr(snapshot.taskRows.map { taskRowToJson(it) }))
  payload.add("tasks", tasks.build())
  payload.add("approval", approvalToJson(snapshot.approval))
  return encodeEnvelope(MessageKind.Snapshot, id, payload.build())
}

fun decodeSnapshot(payloadJson: String): WireSnapshot? {
  val obj = parseObject(payloadJson) ?: return null
  return decodeSnapshot(obj)
}

fun decodeSnapshot(obj: JsonValue.Obj): WireSnapshot? {
  val viewObj = obj.field("view") as? JsonValue.Obj ?: return null
  val view = viewFromJson(viewObj) ?: return null
  val turnsNode = obj.field("turns") as? JsonValue.Arr ?: return null
  if (turnsNode.items.size > MonitorLimits.SnapshotStoredTurns) return null
  val turns = turnsNode.items.map { item ->
    val row = item as? JsonValue.Obj ?: return null
    turnFromJson(row, true) ?: return null
  }
  val liveNode = obj.field("live")
  val live = when (liveNode) {
    null, JsonValue.Null -> null
    is JsonValue.Obj -> turnFromJson(liveNode, false) ?: return null
    else -> return null
  }
  val plan = obj.field("plan") as? JsonValue.Obj ?: return null
  val planPath = plan.readString("path", true)
  val planTitle = plan.readString("title", true)
  val planRunning = plan.readBool("running", true)
  if (!planPath.ok || !planTitle.ok || !planRunning.ok) return null
  val planRows = rowsFrom(plan.field("rows")) { planRowFromJson(it) } ?: return null
  val tasks = obj.field("tasks") as? JsonValue.Obj ?: return null
  val taskRows = rowsFrom(tasks.field("rows")) { taskRowFromJson(it) } ?: return null
  val approvalObj = obj.field("approval") as? JsonValue.Obj ?: return null
  val approval = approvalFromJson(approvalObj) ?: return null
  return WireSnapshot(
    view, turns, live, planPath.value, planTitle.value, planRunning.value,
    planRows, taskRows, approval
  )
}

data class OfflineCacheDocument(
  val turns: List<WireTurn>,
  val history: List<WireTurn>,
  val live: WireTurn?,
  val planPath: String,
  val planTitle: String,
  val planRows: List<PlanRow>,
  val selectedPlan: Int,
  val draft: String
)

/** Local browse copy. Not a catalogue frame. Stored turns are index rows; history and live keep bodies. */
fun encodeOfflineCache(document: OfflineCacheDocument): String {
  val obj = JsonObjectBuilder()
  obj.add("turns", JsonValue.Arr(document.turns.map { turnToJson(it, true) }))
  obj.add("history", JsonValue.Arr(document.history.map { turnToJson(it, false) }))
  obj.add("live", if (document.live == null) JsonValue.Null else turnToJson(document.live, false))
  obj.add("plan_path", document.planPath)
  obj.add("plan_title", document.planTitle)
  obj.add("plan_rows", JsonValue.Arr(document.planRows.map { planRowToJson(it) }))
  obj.add("selected_plan", document.selectedPlan)
  obj.add("draft", document.draft)
  return obj.build().toFpJson()
}

/** Filed when a conversation closes. The screen JSON is the existing cache document. */
fun encodeClosedScreen(id: String, title: String, document: OfflineCacheDocument): String {
  val screen = parseObject(encodeOfflineCache(document)) ?: return ""
  val obj = JsonObjectBuilder()
  obj.add("id", id)
  obj.add("title", title)
  obj.add("screen", screen)
  return obj.build().toFpJson()
}

/** The filed screen. A raw cache document is accepted so an older writer still loads. */
fun decodeClosedScreen(text: String): OfflineCacheDocument? {
  val obj = parseObject(text) ?: return null
  val screen = obj.field("screen")
  if (screen is JsonValue.Obj) return decodeOfflineCache(screen.toFpJson())
  return decodeOfflineCache(text)
}

fun decodeOfflineCache(text: String): OfflineCacheDocument? {
  val obj = parseObject(text) ?: return null
  val turns = rowsFrom(obj.field("turns")) { turnFromJson(it, true) } ?: return null
  val history = rowsFrom(obj.field("history")) { turnFromJson(it, false) } ?: return null
  val live = when (val liveNode = obj.field("live")) {
    null, JsonValue.Null -> null
    is JsonValue.Obj -> turnFromJson(liveNode, false) ?: return null
    else -> return null
  }
  val planPath = obj.readString("plan_path", true)
  val planTitle = obj.readString("plan_title", true)
  val selected = obj.readInt("selected_plan", true)
  val draft = obj.readString("draft", true)
  if (!planPath.ok || !planTitle.ok || !selected.ok || !draft.ok) return null
  val planRows = rowsFrom(obj.field("plan_rows")) { planRowFromJson(it) } ?: return null
  return OfflineCacheDocument(
    turns, history, live, planPath.value, planTitle.value, planRows, selected.value, draft.value
  )
}

fun splitTranscript(source: WireTranscript): List<WireTranscript> {
  data class Piece(val block: WireBlock, val part: Int, val partCount: Int)
  val pieces = mutableListOf<Piece>()
  var maxParts = 1
  for (block in source.blocks) {
    val parts = if (block.kind == "answer" || block.kind == "thinking") {
      splitBody(block.body, source.revision)
    } else {
      listOf(BodyPart(1, 1, source.revision, block.body))
    }
    if (parts.first().partCount > maxParts) maxParts = parts.first().partCount
    for (part in parts) {
      pieces += Piece(block.copy(body = part.text), part.part, part.partCount)
    }
  }
  if (source.blocks.isEmpty()) maxParts = 1
  val grouped = MutableList(maxParts) { mutableListOf<WireBlock>() }
  for (piece in pieces) {
    val index = piece.part - 1
    if (index < 0 || index >= maxParts) continue
    if (piece.partCount <= 1 && index > 0) continue
    val part = if (piece.part < 1) 1 else piece.part
    val partCount = if (piece.partCount < 1) 1 else piece.partCount
    grouped[index] += piece.block.copy(part = part, partCount = partCount, revision = source.revision)
  }
  return List(maxParts) { index ->
    source.copy(part = index + 1, partCount = maxParts, blocks = grouped[index])
  }
}

fun tryEncodeTranscript(id: String, transcript: WireTranscript): String {
  val payload = JsonObjectBuilder()
  payload.add("turn_index", transcript.turnIndex)
  payload.add("revision", transcript.revision)
  payload.add("part", transcript.part)
  payload.add("part_count", transcript.partCount)
  payload.add("phase", transcript.phase)
  payload.add("status_text", transcript.statusText)
  payload.add("duration_ms", transcript.durationMs)
  payload.add("blocks", JsonValue.Arr(transcript.blocks.map { blockToJson(it) }))
  return encodeEnvelope(MessageKind.Transcript, id, payload.build())
}

fun decodeTranscript(payloadJson: String): WireTranscript? {
  val obj = parseObject(payloadJson) ?: return null
  return decodeTranscript(obj)
}

fun decodeTranscript(obj: JsonValue.Obj): WireTranscript? {
  val turnIndex = obj.readInt("turn_index", true)
  val revision = obj.readInt("revision", true)
  val phase = obj.readString("phase", true)
  val statusText = obj.readString("status_text", true)
  if (!turnIndex.ok || !revision.ok || !phase.ok || !statusText.ok) return null
  val part = obj.readInt("part", false)
  val partCount = obj.readInt("part_count", false)
  val durationMs = obj.readInt("duration_ms", false)
  if (!part.ok || !partCount.ok || !durationMs.ok) return null
  val blocksNode = obj.field("blocks") as? JsonValue.Arr ?: return null
  val blocks = blocksNode.items.map { item ->
    val blockObj = item as? JsonValue.Obj ?: return null
    blockFromJson(blockObj) ?: return null
  }
  return WireTranscript(
    turnIndex.value, revision.value, phase.value, statusText.value, blocks,
    if (part.value < 1) 1 else part.value,
    if (partCount.value < 1) 1 else partCount.value,
    durationMs.value.coerceAtLeast(0)
  )
}

fun limitStoredTurns(turns: List<WireTurn>): List<WireTurn> {
  val kept = turns.filter { !it.live }
  val start = if (kept.size > MonitorLimits.SnapshotStoredTurns) kept.size - MonitorLimits.SnapshotStoredTurns else 0
  return kept.drop(start).map {
    WireTurn(it.turnIndex, it.id, it.mode, it.createdAt, it.promptPreview, it.errorText)
  }
}

fun imageFetchBlocked(missing: Boolean, refused: Boolean, decodedBytes: Long): String? {
  if (missing) return "missing"
  if (refused) return "refused"
  if (decodedBytes > MonitorLimits.MaxImageFetchBytes) return "too_large"
  return null
}

private fun expectedBase64Chars(byteCount: Int): Int = ((byteCount + 2) / 3) * 4

fun tryBuildImageParts(imageId: String, mime: String, width: Int, height: Int, revision: Int, bytes: ByteArray): Pair<List<JsonValue.Obj>?, String> {
  val blocked = imageFetchBlocked(false, false, bytes.size.toLong())
  if (blocked != null) return null to blocked
  val total = bytes.size
  val count = if (total == 0) 1 else (total + MonitorLimits.MaxImagePartBytes - 1) / MonitorLimits.MaxImagePartBytes
  val parts = mutableListOf<JsonValue.Obj>()
  var offset = 0
  for (index in 0 until count) {
    var take = MonitorLimits.MaxImagePartBytes
    if (offset + take > total) take = total - offset
    val raw = bytes.copyOfRange(offset, offset + take)
    val encoded = encodeImageBytes(raw)
    if (encoded.length != expectedBase64Chars(take) || encoded.length > MonitorLimits.ImagePartBase64Chars) {
      return null to "too_large"
    }
    val part = JsonObjectBuilder()
    part.add("image_id", imageId)
    part.add("mime", mime)
    part.add("width", width)
    part.add("height", height)
    part.add("part", index + 1)
    part.add("part_count", count)
    part.add("revision", revision)
    part.add("bytes_base64", encoded)
    val built = part.build()
    if (utf8Length(built.toFpJson()) + MonitorLimits.ImageEnvelopeBytes > MonitorLimits.MaxPayloadBytes) {
      return null to "too_large"
    }
    parts += built
    offset += take
  }
  return parts to ""
}

data class DecodedImage(val image: ImageData, val decodedBytes: Int)

fun decodeImageData(payloadJson: String): DecodedImage? {
  val obj = parseObject(payloadJson) ?: return null
  val part = decodeImagePart(obj) ?: return null
  return DecodedImage(part.image, part.bytes.size)
}

fun decodeImagePart(obj: JsonValue.Obj): InboundPayload.ImagePart? {
  val imageId = obj.readString("image_id", true)
  val mime = obj.readString("mime", true)
  val width = obj.readInt("width", true)
  val height = obj.readInt("height", true)
  val part = obj.readInt("part", true)
  val partCount = obj.readInt("part_count", true)
  val revision = obj.readInt("revision", true)
  val encoded = obj.readString("bytes_base64", true)
  if (!imageId.ok || !mime.ok || !width.ok || !height.ok || !part.ok || !partCount.ok || !revision.ok || !encoded.ok) {
    return null
  }
  val raw = decodeImageBytes(encoded.value) ?: return null
  if (raw.size > MonitorLimits.MaxImagePartBytes || part.value < 1 || partCount.value < part.value) return null
  val image = ImageData(imageId.value, mime.value, width.value, height.value, part.value, partCount.value, revision.value, encoded.value)
  return InboundPayload.ImagePart(image, raw)
}

fun encodeImageUnavailable(id: String, imageId: String, reason: String): String {
  if (!imageUnavailableReasonIsKnown(reason)) return ""
  val payload = JsonObjectBuilder()
  payload.add("image_id", imageId)
  payload.add("reason", reason)
  return encodeEnvelope(MessageKind.ImageUnavailable, id, payload.build())
}

fun decodeImageUnavailable(payloadJson: String): ImageUnavailable? {
  val obj = parseObject(payloadJson) ?: return null
  return decodeImageUnavailable(obj)
}

fun decodeImageUnavailable(obj: JsonValue.Obj): ImageUnavailable? {
  val imageId = obj.readString("image_id", true)
  val reason = obj.readString("reason", true)
  if (!imageId.ok || !reason.ok || !imageUnavailableReasonIsKnown(reason.value)) return null
  return ImageUnavailable(imageId.value, reason.value)
}

fun encodeImageGet(id: String, turnIndex: Int, imageId: String): String {
  val payload = JsonObjectBuilder()
  payload.add("turn_index", turnIndex)
  payload.add("image_id", imageId)
  return encodeEnvelope(MessageKind.ImageGet, id, payload.build())
}

fun encodeAck(id: String, conversationId: String, streamId: String, seq: Long): String {
  val payload = JsonObjectBuilder()
  payload.add("conversation_id", conversationId)
  payload.add("stream_id", streamId)
  payload.add("seq", seq)
  return encodeEnvelope(MessageKind.Ack, id, payload.build())
}

fun encodeBlockGet(id: String, conversationId: String, blockId: String): String {
  val payload = JsonObjectBuilder()
  payload.add("conversation_id", conversationId)
  payload.add("block_id", blockId)
  payload.add("offset", 0)
  return encodeEnvelope(MessageKind.BlockGet, id, payload.build())
}

fun decodeImageGet(payloadJson: String): ImageGet? {
  val obj = parseObject(payloadJson) ?: return null
  val turnIndex = obj.readInt("turn_index", true)
  val imageId = obj.readString("image_id", true)
  if (!turnIndex.ok || !imageId.ok) return null
  return ImageGet(turnIndex.value, imageId.value)
}

fun tryEncodeImageData(
  id: String,
  imageId: String,
  mime: String,
  width: Int,
  height: Int,
  revision: Int,
  bytes: ByteArray,
  missing: Boolean,
  refused: Boolean
): ImageEncode {
  val blocked = imageFetchBlocked(missing, refused, bytes.size.toLong())
  if (blocked != null) return ImageEncode(blocked.isNotEmpty(), emptyList(), blocked)
  val built = tryBuildImageParts(imageId, mime, width, height, revision, bytes)
  if (built.first == null) return ImageEncode(built.second.isNotEmpty(), emptyList(), built.second)
  val messages = mutableListOf<String>()
  for (part in built.first!!) {
    val json = encodeEnvelope(MessageKind.ImageData, id, part)
    if (json.isEmpty()) return ImageEncode(false, emptyList(), "too_large")
    messages += json
  }
  return ImageEncode(true, messages, "")
}

private fun patchPayload(patch: WirePatch): JsonValue.Obj {
  val payload = JsonObjectBuilder()
  payload.add("epoch", patch.epoch)
  payload.add("cursor", patch.cursor)
  payload.add("turn_index", patch.turnIndex)
  payload.add("turn_id", patch.turnId)
  payload.add("part", patch.part)
  payload.add("part_count", patch.partCount)
  payload.add("busy", patch.busy)
  payload.add("sending", patch.sending)
  payload.add("plan_running", patch.planRunning)
  payload.add("phase", patch.phase)
  payload.add("can_send", patch.canSend)
  payload.add("can_steer", patch.canSteer)
  payload.add("can_stop", patch.canStop)
  payload.add("elapsed_ms", patch.elapsedMs)
  if (patch.hasView) {
    payload.add("model", patch.model)
    payload.add("signed_in", patch.signedIn)
    payload.add("status_text", patch.statusText)
  }
  payload.add("blocks", JsonValue.Arr(patch.blocks.map { blockToJson(it) }))
  return payload.build()
}

fun encodeResume(id: String, epoch: String, cursor: Long): String {
  val payload = JsonObjectBuilder()
  payload.add("epoch", epoch)
  payload.add("cursor", cursor)
  return encodeEnvelope(MessageKind.Resume, id, payload.build())
}

fun decodeResume(payloadJson: String): WireResume? {
  val obj = parseObject(payloadJson) ?: return null
  return decodeResume(obj)
}

fun decodeResume(obj: JsonValue.Obj): WireResume? {
  val epoch = obj.readString("epoch", true)
  val cursor = obj.readLong("cursor", true)
  if (!epoch.ok || !cursor.ok) return null
  return WireResume(epoch.value, cursor.value)
}

fun encodePatch(id: String, patch: WirePatch): String {
  return encodeEnvelope(MessageKind.Patch, id, patchPayload(patch))
}

fun decodePatch(payloadJson: String): WirePatch? {
  val obj = parseObject(payloadJson) ?: return null
  return decodePatch(obj)
}

fun decodePatch(obj: JsonValue.Obj): WirePatch? {
  val epoch = obj.readString("epoch", true)
  val cursor = obj.readLong("cursor", true)
  val turnIndex = obj.readInt("turn_index", true)
  val turnId = obj.readString("turn_id", true)
  val part = obj.readInt("part", true)
  val partCount = obj.readInt("part_count", true)
  val busy = obj.readBool("busy", true)
  val sending = obj.readBool("sending", true)
  val planRunning = obj.readBool("plan_running", true)
  val phase = obj.readString("phase", true)
  val canSend = obj.readBool("can_send", true)
  val canSteer = obj.readBool("can_steer", true)
  val canStop = obj.readBool("can_stop", true)
  val elapsed = obj.readInt("elapsed_ms", true)
  if (!epoch.ok || !cursor.ok || !turnIndex.ok || !turnId.ok || !part.ok || !partCount.ok || !busy.ok ||
    !sending.ok || !planRunning.ok || !phase.ok || !canSend.ok || !canSteer.ok || !canStop.ok || !elapsed.ok
  ) {
    return null
  }
  val hasView = obj.field("model") != null || obj.field("signed_in") != null
  val model = obj.readString("model", false)
  val signedIn = obj.readBool("signed_in", false)
  val statusText = obj.readString("status_text", false)
  if (hasView && (!model.ok || !signedIn.ok || !statusText.ok)) return null
  if (part.value < 1 || partCount.value < 1 || part.value > partCount.value) return null
  val blocksNode = obj.field("blocks") as? JsonValue.Arr ?: return null
  val blocks = blocksNode.items.map { item ->
    val row = item as? JsonValue.Obj ?: return null
    blockFromJson(row) ?: return null
  }
  return WirePatch(
    epoch.value, cursor.value, turnIndex.value, turnId.value, blocks, busy.value, sending.value,
    planRunning.value, phase.value, canSend.value, canSteer.value, canStop.value, elapsed.value,
    part.value, partCount.value, hasView, if (model.ok) model.value else "", if (signedIn.ok) signedIn.value else false,
    if (statusText.ok) statusText.value else ""
  )
}

private fun utf8Prefix(text: String, maxBytes: Int): String {
  if (maxBytes < 1 || text.isEmpty()) return ""
  val bytes = text.toByteArray(Charsets.UTF_8)
  if (bytes.size <= maxBytes) return text
  var count = maxBytes
  while (count > 0 && (bytes[count].toInt() and 0xC0) == 0x80) count--
  if (count < 1) count = 1
  return bytes.copyOf(count).toString(Charsets.UTF_8)
}

fun packPatch(id: String, patch: WirePatch): List<String> {
  fun encodeBlocks(blocks: List<WireBlock>, part: Int, partCount: Int): String {
    return encodePatch(id, patch.copy(blocks = blocks, part = part, partCount = partCount))
  }
  fun pieceFits(block: WireBlock): Boolean = encodeBlocks(listOf(block), 1, 1).isNotEmpty()
  fun splitBlock(block: WireBlock): List<WireBlock>? {
    var rest = block.body
    val pieces = mutableListOf<WireBlock>()
    while (true) {
      if (pieceFits(block.copy(body = rest))) {
        pieces += block.copy(body = rest)
        return pieces
      }
      if (rest.isEmpty()) return null
      var low = 1
      var high = rest.length - 1
      var best = 0
      while (low <= high) {
        val mid = (low + high) / 2
        val prefix = utf8Prefix(rest, mid)
        if (pieceFits(block.copy(body = prefix))) {
          best = prefix.length
          low = best + 1
        } else {
          high = mid - 1
        }
      }
      if (best < 1) return null
      pieces += block.copy(body = rest.substring(0, best))
      rest = rest.substring(best)
    }
  }
  val whole = encodePatch(id, patch.copy(part = if (patch.part < 1) 1 else patch.part,
    partCount = if (patch.partCount < 1) 1 else patch.partCount))
  if (whole.isNotEmpty()) return listOf(whole)
  val pieces = mutableListOf<WireBlock>()
  for (block in patch.blocks) {
    val split = splitBlock(block) ?: return emptyList()
    pieces += split
  }
  if (pieces.isEmpty()) return emptyList()
  val starts = mutableListOf<Int>()
  val ends = mutableListOf<Int>()
  var startAt = 0
  while (startAt <= pieces.lastIndex) {
    var lastFit = startAt - 1
    for (index in startAt..pieces.lastIndex) {
      if (encodeBlocks(pieces.subList(startAt, index + 1), 1, 1).isEmpty()) break
      lastFit = index
    }
    if (lastFit < startAt) return emptyList()
    starts += startAt
    ends += lastFit
    startAt = lastFit + 1
  }
  val packed = mutableListOf<String>()
  for (partNo in starts.indices) {
    val json = encodeBlocks(pieces.subList(starts[partNo], ends[partNo] + 1), partNo + 1, starts.size)
    if (json.isEmpty()) return emptyList()
    packed += json
  }
  return packed
}

fun assemblePatch(messages: List<String>): WirePatch? {
  if (messages.isEmpty()) return null
  val decoded = messages.map { json ->
    val envelope = tryDecodeEnvelope(json)
    if (!envelope.ok || envelope.message.kind != MessageKind.Patch) return null
    decodePatch(envelope.message.payloadJson) ?: return null
  }
  val partCount = decoded[0].partCount
  if (partCount < 1 || decoded.size != partCount) return null
  val slots = arrayOfNulls<WirePatch>(partCount)
  for (part in decoded) {
    if (part.partCount != partCount || part.epoch != decoded[0].epoch || part.cursor != decoded[0].cursor) return null
    if (part.part < 1 || part.part > partCount || slots[part.part - 1] != null) return null
    slots[part.part - 1] = part
  }
  if (slots.any { it == null }) return null
  val blocks = mutableListOf<WireBlock>()
  for (slot in slots) {
    for (block in slot!!.blocks) {
      val previous = blocks.lastOrNull()
      if (previous != null && previous.blockId == block.blockId && previous.kind == block.kind) {
        blocks[blocks.lastIndex] = previous.copy(body = previous.body + block.body)
      } else {
        blocks += block
      }
    }
  }
  return slots[0]!!.copy(blocks = blocks, part = 1, partCount = 1)
}

fun encodeCatchup(id: String, catchup: WireCatchup): String {
  if (catchup.mode != "snapshot" && catchup.mode != "events") return ""
  val payload = JsonObjectBuilder()
  payload.add("mode", catchup.mode)
  payload.add("epoch", catchup.epoch)
  payload.add("cursor", catchup.cursor)
  payload.add("conversation_id", catchup.conversationId)
  payload.add("project_root", catchup.projectRoot)
  payload.add("title", catchup.title)
  if (catchup.mode == "snapshot") {
    val snapshot = catchup.snapshot ?: return ""
    val encoded = encodeSnapshot("catchup-snap", snapshot)
    val envelope = tryDecodeEnvelope(encoded)
    if (!envelope.ok) return ""
    val snap = parseObject(envelope.message.payloadJson) ?: return ""
    payload.add("snapshot", snap)
  } else {
    payload.add("patches", JsonValue.Arr(catchup.patches.map { patchPayload(it) }))
  }
  return encodeEnvelope(MessageKind.Catchup, id, payload.build())
}

fun decodeCatchup(payloadJson: String): WireCatchup? {
  val obj = parseObject(payloadJson) ?: return null
  return decodeCatchup(obj)
}

fun decodeCatchup(obj: JsonValue.Obj): WireCatchup? {
  val mode = obj.readString("mode", true)
  val epoch = obj.readString("epoch", true)
  val cursor = obj.readLong("cursor", true)
  val conversationId = obj.readString("conversation_id", true)
  val projectRoot = obj.readString("project_root", true)
  val title = obj.readString("title", true)
  if (!mode.ok || !epoch.ok || !cursor.ok || !conversationId.ok || !projectRoot.ok || !title.ok) return null
  if (mode.value == "snapshot") {
    val snap = obj.field("snapshot") as? JsonValue.Obj ?: return null
    val snapshot = decodeSnapshot(snap) ?: return null
    return WireCatchup(mode.value, epoch.value, cursor.value, conversationId.value, projectRoot.value, title.value,
      snapshot, emptyList())
  }
  if (mode.value != "events") return null
  val rows = obj.field("patches") as? JsonValue.Arr ?: return null
  val patches = rows.items.map { item ->
    val row = item as? JsonValue.Obj ?: return null
    decodePatch(row) ?: return null
  }
  return WireCatchup(mode.value, epoch.value, cursor.value, conversationId.value, projectRoot.value, title.value,
    null, patches)
}

fun encodeConversationClosed(id: String, epoch: String, cursor: Long, conversationId: String, title: String): String {
  val payload = JsonObjectBuilder()
  payload.add("epoch", epoch)
  payload.add("cursor", cursor)
  payload.add("conversation_id", conversationId)
  payload.add("title", title)
  return encodeEnvelope(MessageKind.ConversationClosed, id, payload.build())
}

fun decodeConversationClosed(payloadJson: String): WireConversationClosed? {
  val obj = parseObject(payloadJson) ?: return null
  return decodeConversationClosed(obj)
}

fun decodeConversationClosed(obj: JsonValue.Obj): WireConversationClosed? {
  val epoch = obj.readString("epoch", true)
  val cursor = obj.readLong("cursor", true)
  val conversationId = obj.readString("conversation_id", true)
  val title = obj.readString("title", true)
  if (!epoch.ok || !cursor.ok || !conversationId.ok || !title.ok) return null
  return WireConversationClosed(epoch.value, cursor.value, conversationId.value, title.value)
}
