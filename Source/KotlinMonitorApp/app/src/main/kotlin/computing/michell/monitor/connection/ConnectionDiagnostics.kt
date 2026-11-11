package computing.michell.monitor.connection

/* Compact connection incident. One capture names the posture (c) 2026 Michell Computing.

   The text never includes a session token, pairing code, authentication MAC,
   or prompt. Callers still pass those values to [redactDiagnostic] so a reason
   that echoed one cannot leak it. */

/** Matches the recovery budget. Heartbeats inside this window are not a stall. */
const val HeartbeatWithoutProgressMs = 15_000L

const val PostureIdle = "intentionally idle"
const val PostureAwaitingUser = "awaiting user action"
const val PostureRetrying = "retrying"
const val PostureOpening = "blocked in opening/I/O"
const val PostureHeartbeats = "receiving heartbeats without sync progress"
const val PostureLive = "live"

private val ProgressBanners = setOf(
  "",
  ReconnectingBanner,
  BackgroundBanner,
  WaitingForWifiBanner,
  IdleOfflineBanner
)

private val SecretLabel = Regex("(?i)(sessionToken|pairCode|authMac|hmac)=\\S+|pairing code[=:]\\s*\\S+|prompt[=:][^\\n]*")

data class IncidentSnapshot(
  val loopGeneration: Int = 0,
  val socketGeneration: Int = 0,
  val phase: String = LinkPhase.Idle.name,
  val banner: String = "",
  val transitionReason: String = "",
  val failureReason: String = "",
  val attemptCount: Int = 0,
  val nextRetryAtMs: Long = -1L,
  val nowMs: Long = 0L,
  val monitoringDemand: Boolean = false,
  val networkIdentity: String = "",
  val lastReceivedFrameAgeMs: Long = -1L,
  val lastCommittedProgressAgeMs: Long = -1L,
  val queueBytes: Long = 0L,
  val outboundBytes: Long = 0L,
  val inboundBytes: Long = 0L,
  val workerExit: String = "",
  val terminalKind: String = "",
  val opening: Boolean = false,
  val ioBlocked: Boolean = false,
  val framesArriving: Boolean = false,
  val stopped: Boolean = false,
  val paused: Boolean = false,
  val armed: Boolean = false,
  val reconnectable: Boolean = false,
  val socketAgeMs: Long = -1L
) {
  val posture: String
    get() = incidentPosture(this)

  val retryInMs: Long
    get() = if (nextRetryAtMs < 0L) -1L else (nextRetryAtMs - nowMs).coerceAtLeast(0L)
}

/** Pin, authentication, and revocation stay distinct. Any of them blocks automatic recovery. */
fun terminalKindOf(reason: String): String {
  return when (reason) {
    "auth", "expired", "pair_code", "fingerprint", "revoked", "disabled" -> reason
    else -> ""
  }
}

fun blocksAutomaticRecovery(terminal: Boolean, kind: String): Boolean {
  if (terminal) return true
  return terminalKindOf(kind).isNotEmpty() || kind == "pin"
}

/**
 * A failed transient session can be opened again. Pairing and Room are not touched.
 * A live socket, a user disconnect, and a terminal failure are not this action.
 */
fun transientRestartAllowed(
  stopped: Boolean,
  terminal: Boolean,
  paused: Boolean,
  armed: Boolean,
  address: String,
  phase: LinkPhase
): Boolean {
  if (stopped || terminal || paused || !armed) return false
  if (address.isEmpty() || phase == LinkPhase.Live) return false
  return true
}

/**
 * The retry banner must not erase the failure that caused it.
 * A live session clears it. A generic progress banner keeps the previous reason.
 */
fun nextFailureReason(current: String, phase: LinkPhase, banner: String, error: String): String {
  if (phase == LinkPhase.Live || phase == LinkPhase.Idle) return ""
  val specific = error.ifEmpty { banner }
  if (isSpecificFailure(specific) && specific != banner) return specific
  if (isSpecificFailure(banner) && !isProgressBanner(banner)) return banner
  if (isSpecificFailure(error)) return error
  return current
}

fun isProgressBanner(text: String): Boolean = text in ProgressBanners || text == HostClosedBanner

private fun isSpecificFailure(text: String): Boolean {
  return text.isNotEmpty() && text != ReconnectingBanner && text != HostClosedBanner && !isProgressBanner(text)
}

fun incidentPosture(snapshot: IncidentSnapshot): String {
  if (snapshot.stopped || snapshot.phase == LinkPhase.Idle.name || snapshot.banner == IdleOfflineBanner ||
    snapshot.banner == BackgroundBanner) {
    return PostureIdle
  }
  if (snapshot.terminalKind.isNotEmpty() || snapshot.paused || snapshot.phase == LinkPhase.Paused.name) {
    return PostureAwaitingUser
  }
  if (snapshot.banner == WaitingForWifiBanner && !snapshot.monitoringDemand) return PostureAwaitingUser
  if (!snapshot.armed && snapshot.phase != LinkPhase.Connecting.name && snapshot.phase != LinkPhase.Live.name) {
    return PostureIdle
  }
  if (snapshot.opening || snapshot.ioBlocked) return PostureOpening
  if (snapshot.phase == LinkPhase.Live.name && snapshot.framesArriving && progressStalled(snapshot)) {
    return PostureHeartbeats
  }
  if (snapshot.phase == LinkPhase.Live.name) return PostureLive
  if (snapshot.reconnectable || snapshot.phase == LinkPhase.Connecting.name || snapshot.banner == ReconnectingBanner ||
    snapshot.nextRetryAtMs >= 0L) {
    return PostureRetrying
  }
  return PostureIdle
}

private fun progressStalled(snapshot: IncidentSnapshot): Boolean {
  if (snapshot.lastCommittedProgressAgeMs >= HeartbeatWithoutProgressMs) return true
  return snapshot.lastCommittedProgressAgeMs < 0L && snapshot.socketAgeMs >= HeartbeatWithoutProgressMs
}

fun formatIncident(snapshot: IncidentSnapshot): String {
  val retry = if (snapshot.retryInMs < 0L) "none" else snapshot.retryInMs.toString()
  val network = snapshot.networkIdentity.ifEmpty { "none" }
  val exit = snapshot.workerExit.ifEmpty { "none" }
  val terminal = snapshot.terminalKind.ifEmpty { "none" }
  val failure = snapshot.failureReason.ifEmpty { "none" }
  val reason = snapshot.transitionReason.ifEmpty { "none" }
  return "posture=${snapshot.posture} phase=${snapshot.phase} reason=$reason failure=$failure\n" +
    "loop=${snapshot.loopGeneration} socket=${snapshot.socketGeneration} attempts=${snapshot.attemptCount} " +
    "retryMs=$retry demand=${snapshot.monitoringDemand}\n" +
    "network=$network frameAge=${ageText(snapshot.lastReceivedFrameAgeMs)} " +
    "progressAge=${ageText(snapshot.lastCommittedProgressAgeMs)} queue=${snapshot.queueBytes} " +
    "outbound=${snapshot.outboundBytes} inbound=${snapshot.inboundBytes} exit=$exit terminal=$terminal"
}

fun ageText(ageMs: Long): String = if (ageMs < 0L) "none" else ageMs.toString()

/** Drops known secrets and any labelled token, code, MAC, or prompt that leaked into a reason. */
fun redactDiagnostic(text: String, secrets: List<String> = emptyList()): String {
  var clean = text
  for (secret in secrets) {
    if (secret.length < 8) continue
    clean = clean.replace(secret, "[redacted]")
  }
  return SecretLabel.replace(clean) { match -> match.groupValues[1] + "=[redacted]" }
}

/** Queue admission is not a socket write and not a host acknowledgement. */
fun catalogueFromAdmission(accepted: AcceptedCatalogue, admitted: Boolean): CatalogueResult {
  val outcome = if (admitted) CatalogueWrite.Queued else CatalogueWrite.Failed
  return CatalogueResult(accepted.commandId, accepted.linkEpoch, outcome)
}

/** The owned socket accepted the bytes. The host has not acknowledged the command. */
fun catalogueFromSocketWrite(accepted: AcceptedCatalogue, wrote: Boolean): CatalogueResult {
  val outcome = if (wrote) CatalogueWrite.Written else CatalogueWrite.Failed
  return CatalogueResult(accepted.commandId, accepted.linkEpoch, outcome)
}

fun isDurableHostAcknowledgement(state: String): Boolean {
  return state == OutboxQueued || state == OutboxAccepted || state == OutboxDone || state == OutboxRejected
}

fun catalogueFromHostState(commandId: String, linkEpoch: Int, state: String): CatalogueResult? {
  if (commandId.isEmpty() || !isDurableHostAcknowledgement(state)) return null
  return CatalogueResult(commandId, linkEpoch, CatalogueWrite.Acknowledged)
}
