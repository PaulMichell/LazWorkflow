package computing.michell.monitor.ui.model

/* Screen state the kept pages render (c) 2026 Michell Computing. */

data class MonitorUi(
  val view: WireView = emptyView(),
  val turns: List<WireTurn> = emptyList(),
  val live: WireTurn? = null,
  val history: Map<Int, WireTurn> = emptyMap(),
  val selectedTurn: Int = -1,
  val planPath: String = "",
  val planTitle: String = "",
  val planRunning: Boolean = false,
  val planRows: List<PlanRow> = emptyList(),
  val selectedPlan: Int = -1,
  val planChoices: List<PlanChoice> = emptyList(),
  val conversationChoices: List<ConversationChoice> = emptyList(),
  val conversationCurrent: String = "",
  val conversationsTruncated: Boolean = false,
  val taskChoices: List<TaskChoice> = emptyList(),
  val taskCurrent: String = "",
  val capabilities: Set<String> = emptySet(),
  val approval: ApprovalNotice? = null,
  val approvalOpen: Boolean = false,
  val saveQuestion: String = "",
  val banner: String = "",
  val draft: String = "",
  val disconnected: Boolean = false,
  val imageReasons: Map<String, String> = emptyMap(),
  val reachedLive: Boolean = false,
  val pairHold: Boolean = false,
  val settingsOpen: Boolean = false,
  val generation: Int = 0,
  val rescueSteer: Boolean = false,
  val showThinking: Boolean = true,
  val showTools: Boolean = true,
  val pendingPrompt: String = "",
  val pendingKind: String = "",
  val pendingCommandId: String = "",
  val pendingPrompts: List<PendingPromptMark> = emptyList(),
  val pendingEpoch: Int = 0,
  val promptBaseline: Set<String> = emptySet(),
  val activityStartedMs: Long = 0,
  val planRunElapsedMs: Long = -1,
  val planRunSampleMs: Long = -1,
  val planRunStartedMs: Long = 0,
  val activityObservedMs: Int = 0,
  val activityAppliedMs: Long = 0,
  val clockToken: Int = 0,
  val hostGeneration: Int = 0,
  val conversationGeneration: Int = 0,
  val connectionGeneration: Int = 0,
  val hostEpoch: String = "",
  val hostCursor: Long = 0,
  val catchingUp: Boolean = false,
  val announcedEpoch: String = "",
  val conversationId: String = "",
  val projectRoot: String = "",
  val conversationTitle: String = "",
  val closedConversationId: String = "",
  val closedTitle: String = "",
  val resumeOnce: Boolean = false,
  val closedPending: Boolean = false,
  val closedQueued: Boolean = false,
  val blockFetchIds: List<String> = emptyList(),
  val undeliveredPrompt: String = "",
  val reviewingOffline: Boolean = false,
  val statusBusy: Boolean = false,
  val openBehind: Boolean = false,
  val pairedElsewhere: Boolean = false,
  val sendWhileOffline: Boolean = false,
  val reconnectable: Boolean = false,
  val linkBanner: String = "",
  val lastSyncMs: Long = 0,
  val syncHead: Long = 0,
  val desktopPoint: Int = 0,
  val planBody: String = "",
  val planRevision: String = "",
  val planReceived: Long = 0,
  val planTotal: Long = 0,
  val planIncomplete: Boolean = false,
  val linkKind: MonitorLink = MonitorLink.Stopped
)

fun emptyView(): WireView {
  return WireView(
    false, false, false, false, false, "", "", "", "", false, "", "", "", "",
    false, false, false, false, false, ""
  )
}

fun shellUi(): MonitorUi {
  return MonitorUi(banner = RebuildBanner, disconnected = true, linkBanner = RebuildBanner)
}

/** One prompt waiting in the outbox, or already sent and not yet on screen. */
data class PendingPromptMark(val id: String, val text: String, val editable: Boolean = false)
