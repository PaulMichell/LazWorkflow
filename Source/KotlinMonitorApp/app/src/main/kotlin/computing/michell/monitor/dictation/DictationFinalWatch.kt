package computing.michell.monitor.dictation

/* Cancellable wait for one dictation session's final result (c) 2026 Michell Computing. */

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class DictationFinalWatch(
  private val scope: CoroutineScope,
  private val deadlineMs: Long = DictationFinalDeadlineMs,
  private val onExpired: (Int) -> Unit
) {
  private var wait: Job? = null
  private var armedSession = 0

  fun arm(sessionId: Int) {
    cancel()
    if (sessionId <= 0) return
    armedSession = sessionId
    val expected = sessionId
    wait = scope.launch {
      delay(deadlineMs)
      if (!isActive || armedSession != expected) return@launch
      armedSession = 0
      wait = null
      onExpired(expected)
    }
  }

  fun cancel() {
    armedSession = 0
    val running = wait
    wait = null
    running?.cancel()
  }
}
