package computing.michell.monitor

/* The one pulse loop the watch service may touch (c) 2026 Michell Computing.

   The service never builds a client. It only slows this loop while the screen
   is off, and reads the pulses the session already collects. */

import computing.michell.monitor.net.PulseIntervalDefaultMs
import computing.michell.monitor.net.PulseLoop
import java.util.concurrent.CopyOnWriteArrayList

object WatchBridge {
  @Volatile var loop: PulseLoop? = null
    private set

  @Volatile var active: Boolean = false
    private set

  private val listeners = CopyOnWriteArrayList<(String) -> Unit>()

  fun attach(next: PulseLoop) {
    loop = next
    if (active) next.intervalMs = WatchIntervalMs
  }

  fun detach(current: PulseLoop?) {
    if (current != null && loop != null && loop != current) return
    loop = null
    publish("")
  }

  fun publish(json: String) {
    val copy = listeners.toList()
    for (listener in copy) listener(json)
  }

  fun listen(listener: (String) -> Unit) {
    listeners.add(listener)
  }

  fun unlisten(listener: (String) -> Unit) {
    listeners.remove(listener)
  }

  fun setWatching(next: Boolean) {
    active = next
    loop?.intervalMs = if (next) WatchIntervalMs else PulseIntervalDefaultMs
  }
}
