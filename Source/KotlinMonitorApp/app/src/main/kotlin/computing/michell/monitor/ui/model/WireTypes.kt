package computing.michell.monitor.ui.model

/* Screen value types. Catalogue 3 protocol types were removed (c) 2026 Michell Computing.

   Field lists are unchanged. The package name is the only change. */

const val SaveBeforeTurnQuestion = "Do you want to save all edits and continue?"
const val NoSessionMessage = "The Project Assistant window is not open."

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
  val appendOffset: Int? = null,
  val deferred: Boolean = false
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
  val planTitle: String = "",
  val usageCaption: String = "",
  val usageHint: String = ""
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

data class ApprovalNotice(
  val active: Boolean,
  val toolId: String,
  val toolName: String,
  val summary: String,
  val modeCaption: String,
  val decisionsAccepted: Boolean
)

data class PlanChoice(val path: String, val caption: String)

data class ConversationChoice(val id: String, val title: String, val current: Boolean)

data class TaskChoice(val id: String, val caption: String)

/** Local browse copy. Not a wire frame. */
data class OfflineCacheDocument(
  val turns: List<WireTurn>,
  val history: List<WireTurn>,
  val live: WireTurn?,
  val planPath: String,
  val planTitle: String,
  val planRows: List<PlanRow>,
  val selectedPlan: Int,
  val draft: String,
  val planBody: String = ""
)

/** Constants the screens still read. The frame codec was removed. */
object MonitorLimits {
  const val ListenPort = 56122
  const val MaxSendChars = 65536
}

/** `current` is a file slot, not a conversation. */
fun conversationIdIsIdentity(text: String): Boolean {
  return text.isNotEmpty() && text != "current"
}
