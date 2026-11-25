package computing.michell.monitor.net

/* Follow the running item at an adaptive rate (c) 2026 Michell Computing.

   While the conversation screen is visible and the reader is at the head, a
   new item rev is fetched at once, but never more often than followMs. That
   gap starts at 250 ms and doubles, up to 2 seconds, when a fetch takes more
   than half the gap or the app reports memory or battery pressure. A quick
   fetch with no pressure returns the gap to 250 ms. The pulse interval
   follows the same value. Screen off, background, or scrolled away asks for
   a 5 second pulse and fetches no item text, except one final fetch when an
   item stops running and one when the turn finishes. */

const val FollowMinMs = 250L
const val FollowMaxMs = 2_000L
const val FollowAwayIntervalMs = 5_000L

class ItemFollower(
  private val clock: PulseClock = SystemPulseClock(),
  private val onTail: (String) -> Unit = {},
  private val onItemFinal: (String) -> Unit = {},
  private val onTurnFinal: (String) -> Unit = {}
) {
  var followMs: Long = FollowMinMs
    private set

  val intervalMs: Long
    get() = if (following) followMs else FollowAwayIntervalMs

  val following: Boolean
    get() = screenOn && foreground && followingHead

  private var screenOn = true
  private var foreground = true
  private var followingHead = true
  private var pressure = false
  private var lastTailAt = Long.MIN_VALUE / 4
  private var tailOpen = false
  private var tailStartedAt = 0L
  private var fetchedItemId = ""
  private var fetchedRev = -1L
  private var liveTurnId: String? = null
  private var liveItemId: String? = null
  private val itemState = HashMap<String, String>()
  private val closedItems = HashSet<String>()
  private val closedTurns = HashSet<String>()
  private var loop: PulseLoop? = null
  private var engine: SyncEngine? = null
  private var lastJson: String? = null

  /** Screen on, in the foreground, and the reader is at the head. */
  fun watching(screenOn: Boolean, foreground: Boolean, followingHead: Boolean) {
    this.screenOn = screenOn
    this.foreground = foreground
    this.followingHead = followingHead
    publish()
  }

  fun scrollAway() = watching(screenOn, foreground, false)

  fun followHead() = watching(screenOn, foreground, true)

  fun background() = watching(screenOn, false, followingHead)

  fun screenOff() = watching(false, foreground, followingHead)

  /** Memory or battery pressure doubles the gap once, and holds it there. */
  fun pressure(memory: Boolean = false, battery: Boolean = false) {
    val on = memory || battery
    if (on && !pressure) followMs = (followMs * 2).coerceAtMost(FollowMaxMs)
    pressure = on
    if (!on && !tailOpen) followMs = FollowMinMs
    publish()
  }

  fun onPulse(turnId: String?, itemId: String?, itemRev: Long, itemState: String) {
    val now = clock.now()
    closeReplaced(turnId, itemId)
    if (itemId != null) noteState(itemId, itemState)
    if (turnId != null) liveTurnId = turnId
    if (following && itemId != null && itemState == "running" && newRev(itemId, itemRev) && tailDue(now)) {
      fetchedItemId = itemId
      fetchedRev = itemRev
      lastTailAt = now
      tailStartedAt = now
      tailOpen = true
      onTail(itemId)
      lastJson?.let { engine?.pullItem(it) }
    }
    liveItemId = itemId
    publish()
  }

  fun onPulse(json: String) {
    val pulse = parsePulse(json) ?: return
    lastJson = json
    publish()
    onPulse(pulse.liveTurnId, pulse.liveItemId, pulse.liveItemRev, pulse.liveItemState)
    engine?.onPulse(json)
  }

  /** The open tail finished. A slow one doubles the gap; a quick one restores 250 ms. */
  fun noteFetchCompleted() {
    if (!tailOpen) return
    val elapsed = clock.now() - tailStartedAt
    tailOpen = false
    if (elapsed > followMs / 2) followMs = (followMs * 2).coerceAtMost(FollowMaxMs)
    else if (!pressure) followMs = FollowMinMs
    publish()
  }

  fun attach(loop: PulseLoop, engine: SyncEngine) {
    this.loop = loop
    this.engine = engine
    engine.followHead = false
    publish()
  }

  private fun newRev(itemId: String, itemRev: Long): Boolean {
    return itemId != fetchedItemId || itemRev != fetchedRev
  }

  private fun tailDue(now: Long): Boolean = now - lastTailAt >= followMs

  private fun noteState(itemId: String, state: String) {
    val previous = itemState[itemId]
    itemState[itemId] = state
    if (previous == "running" && state != "running") closeItem(itemId)
  }

  private fun closeReplaced(turnId: String?, itemId: String?) {
    val previousTurn = liveTurnId
    if (previousTurn != null && previousTurn != turnId) closeTurn(previousTurn)
    val previousItem = liveItemId
    if (previousItem != null && previousItem != itemId && itemState[previousItem] == "running") closeItem(previousItem)
    if (turnId == null) liveTurnId = null
  }

  private fun closeItem(itemId: String) {
    if (!closedItems.add(itemId)) return
    itemState[itemId] = "done"
    onItemFinal(itemId)
    lastJson?.let { engine?.pullItem(it, closing = true) }
  }

  private fun closeTurn(turnId: String) {
    if (!closedTurns.add(turnId)) return
    onTurnFinal(turnId)
  }

  private fun publish() {
    loop?.intervalMs = intervalMs
    engine?.followMs = followMs
    engine?.followHead = false
  }
}
