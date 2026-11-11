package computing.michell.monitor

/* Screen-off hold follows monitoring demand (c) 2026 Michell Computing.

   The service start is a result, not an assumption. A refused hold is not an
   authentication or host failure. Demand ending, disconnect, or a new process
   releases it. No CPU wake lock is taken here. */

/** Android did not keep the process and radio awake. Not a desktop or sign-in failure. */
const val HoldNotGrantedNotice = "Android did not keep the screen-off hold. This is not a desktop or sign-in failure."

enum class HoldActivation {
  Inactive,
  Starting,
  Active,
  Failed
}

data class HoldDecision(
  val activation: HoldActivation,
  val notice: String,
  /** onStop already passed and the platform then refused the hold. Send bye. */
  val closeLink: Boolean
)

/**
 * Orders screen-off, onStop, and the platform result. A successful screen-off
 * hold is not undone by the onStop that Android delivers next. A failed start
 * is recorded and does not pretend the socket is being held.
 */
class ScreenHold(
  private val start: () -> Boolean,
  private val stop: () -> Unit
) {
  var activation: HoldActivation = HoldActivation.Inactive
    private set
  private var screenOff = false
  private var stopped = false
  private var requested = false
  private var launched = false

  fun onScreenOff(demand: Boolean): HoldDecision {
    screenOff = true
    if (!demand) return snapshot(false)
    return request()
  }

  fun onStop(): HoldDecision {
    stopped = true
    if (screenOff && (activation == HoldActivation.Active || activation == HoldActivation.Starting)) return snapshot(false)
    if (!screenOff) release()
    return snapshot(false)
  }

  fun onScreenOn(): HoldDecision {
    screenOff = false
    stopped = false
    release()
    return snapshot(false)
  }

  /** Demand ended. A running plan or turn is no longer asking for the hold. */
  fun onDemandEnded(): HoldDecision {
    release()
    return snapshot(false)
  }

  fun onDisconnect(): HoldDecision {
    screenOff = false
    release()
    return snapshot(false)
  }

  /** A new process does not inherit a hold the previous process may have lost. */
  fun recreated(): HoldDecision {
    activation = HoldActivation.Inactive
    screenOff = false
    stopped = false
    requested = false
    launched = false
    return snapshot(false)
  }

  /** The service reached foreground, or Android refused it after the launch returned. */
  fun onPlatformResult(active: Boolean): HoldDecision {
    if (!requested) {
      if (active && launched) stop()
      launched = false
      activation = HoldActivation.Inactive
      return snapshot(false)
    }
    if (active) {
      activation = HoldActivation.Active
      return snapshot(false)
    }
    val close = stopped
    requested = false
    launched = false
    activation = HoldActivation.Failed
    return snapshot(close)
  }

  private fun request(): HoldDecision {
    requested = true
    val launchedNow = try {
      start()
    } catch (error: Exception) {
      false
    }
    if (!launchedNow) {
      requested = false
      launched = false
      activation = HoldActivation.Failed
      return snapshot(stopped)
    }
    launched = true
    activation = HoldActivation.Starting
    return snapshot(false)
  }

  private fun release() {
    requested = false
    if (launched) stop()
    launched = false
    activation = HoldActivation.Inactive
  }

  private fun snapshot(closeLink: Boolean): HoldDecision {
    val notice = if (activation == HoldActivation.Failed) HoldNotGrantedNotice else ""
    return HoldDecision(activation, notice, closeLink)
  }
}
