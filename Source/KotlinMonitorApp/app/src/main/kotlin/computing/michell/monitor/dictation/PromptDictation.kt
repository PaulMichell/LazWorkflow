package computing.michell.monitor.dictation

/* Pure prompt dictation splice and reducer. No Android types and no speech error codes (c) 2026 Michell Computing. */

const val DictationDraftLimit = 65536
const val DictationTooLongMessage = "Text is longer than 65536 characters."
const val DictationNoSpeechMessage = "No speech recognised."
const val DictationUnavailableMessage = "Dictation unavailable"
const val DictationListeningMessage = "Listening…"

enum class DictationPhase {
  Idle,
  Listening,
  AwaitingFinal
}

data class DictationAnchor(
  val prefix: String,
  val replaced: String,
  val suffix: String
)

data class DictationState(
  val sessionId: Int = 0,
  val phase: DictationPhase = DictationPhase.Idle,
  val anchor: DictationAnchor? = null,
  val provisional: String = "",
  val selectionStart: Int = 0,
  val selectionEnd: Int = 0,
  val statusMessage: String = ""
) {
  val listening: Boolean
    get() = phase == DictationPhase.Listening

  val sendMustWait: Boolean
    get() = phase != DictationPhase.Idle
}

data class DictationStep(
  val state: DictationState,
  val draft: String
)

// There is no discard event. LeaveScreen keeps the text already shown.
sealed class DictationEvent {
  data class Start(val selectionStart: Int, val selectionEnd: Int) : DictationEvent()
  data class Partial(val sessionId: Int, val text: String) : DictationEvent()
  data class Final(val sessionId: Int, val text: String) : DictationEvent()
  data class ToggleOff(val sessionId: Int) : DictationEvent()
  data class Timeout(val sessionId: Int) : DictationEvent()
  data class Failure(val sessionId: Int, val message: String) : DictationEvent()
  data class Edited(val selectionStart: Int, val selectionEnd: Int) : DictationEvent()
  data object LeaveScreen : DictationEvent()
}

fun captureAnchor(draft: String, selectionStart: Int, selectionEnd: Int): DictationAnchor {
  val bounds = selectionBounds(draft.length, selectionStart, selectionEnd)
  return DictationAnchor(
    prefix = draft.substring(0, bounds.first),
    replaced = draft.substring(bounds.first, bounds.second),
    suffix = draft.substring(bounds.second)
  )
}

fun spacedHypothesis(prefix: String, hypothesis: String, suffix: String): String {
  val trimmed = hypothesis.trim()
  if (trimmed.isEmpty()) return ""
  val lead = prefix.isNotEmpty() && !prefix.last().isWhitespace()
  val trail = suffix.isNotEmpty() && !suffix.first().isWhitespace()
  return buildString {
    if (lead) append(' ')
    append(trimmed)
    if (trail) append(' ')
  }
}

fun applyEditorStep(state: DictationState, draft: String, selectionStart: Int, selectionEnd: Int): DictationStep {
  val bounds = selectionBounds(draft.length, selectionStart, selectionEnd)
  val anchor = state.anchor
  if (state.phase == DictationPhase.Idle || anchor == null) {
    return DictationStep(
      state.copy(
        phase = DictationPhase.Idle,
        anchor = null,
        provisional = "",
        selectionStart = bounds.first,
        selectionEnd = bounds.second
      ),
      draft
    )
  }
  val middle = middleBetween(anchor, draft)
  if (middle == null) {
    return DictationStep(
      state.copy(
        phase = DictationPhase.Idle,
        anchor = null,
        provisional = "",
        selectionStart = bounds.first,
        selectionEnd = bounds.second
      ),
      draft
    )
  }
  // Prefix and suffix still match, so the anchor stays. A caret that remains in the provisional
  // span keeps listening. The next partial replaces this middle. It is not appended.
  return DictationStep(
    state.copy(
      provisional = middle.trim(),
      selectionStart = bounds.first,
      selectionEnd = bounds.second
    ),
    draft
  )
}

// Draft is the field text, including an edit not yet reduced. The result draft is what updateDraft stores.
fun reduceDictation(state: DictationState, draft: String, event: DictationEvent): DictationStep {
  return when (event) {
    is DictationEvent.Start -> reduceStart(state, draft, event)
    is DictationEvent.Partial -> reducePartial(state, draft, event)
    is DictationEvent.Final -> reduceFinal(state, draft, event)
    is DictationEvent.ToggleOff -> reduceStop(state, draft, event.sessionId)
    is DictationEvent.Timeout -> reduceStop(state, draft, event.sessionId)
    is DictationEvent.Failure -> reduceFailure(state, draft, event)
    is DictationEvent.Edited -> applyEditorStep(state, draft, event.selectionStart, event.selectionEnd)
    is DictationEvent.LeaveScreen -> reduceLeave(state, draft)
  }
}

private fun reduceStart(state: DictationState, draft: String, event: DictationEvent.Start): DictationStep {
  if (state.phase != DictationPhase.Idle) return unchanged(state, draft)
  val anchor = captureAnchor(draft, event.selectionStart, event.selectionEnd)
  val caret = anchor.prefix.length
  return DictationStep(
    state.copy(
      sessionId = state.sessionId + 1,
      phase = DictationPhase.Listening,
      anchor = anchor,
      provisional = "",
      selectionStart = caret,
      selectionEnd = caret,
      statusMessage = ""
    ),
    anchor.prefix + anchor.suffix
  )
}

private fun reducePartial(state: DictationState, draft: String, event: DictationEvent.Partial): DictationStep {
  val anchor = state.anchor
  if (!openSession(state, event.sessionId) || anchor == null) return unchanged(state, draft)
  val recognised = event.text.trim()
  if (recognised.isEmpty()) return unchanged(state, draft)
  return applyRecognised(state, anchor, recognised, false)
}

private fun reduceFinal(state: DictationState, draft: String, event: DictationEvent.Final): DictationStep {
  val anchor = state.anchor
  if (!openSession(state, event.sessionId) || anchor == null) return unchanged(state, draft)
  val recognised = event.text.trim()
  if (recognised.isEmpty()) return noSpeech(state, anchor)
  return applyRecognised(state, anchor, recognised, true)
}

private fun reduceStop(state: DictationState, draft: String, sessionId: Int): DictationStep {
  val anchor = state.anchor
  if (state.phase != DictationPhase.Listening || !openSession(state, sessionId) || anchor == null) {
    return unchanged(state, draft)
  }
  if (state.provisional.isEmpty()) {
    val restored = committedDraft(anchor)
    val caret = anchor.prefix.length + anchor.replaced.length
    return DictationStep(
      state.copy(phase = DictationPhase.AwaitingFinal, selectionStart = caret, selectionEnd = caret),
      restored
    )
  }
  val kept = draftWithProvisional(draft, anchor, state.provisional)
  val bounds = selectionBounds(kept.length, state.selectionStart, state.selectionEnd)
  return DictationStep(
    state.copy(phase = DictationPhase.AwaitingFinal, selectionStart = bounds.first, selectionEnd = bounds.second),
    kept
  )
}

private fun reduceFailure(state: DictationState, draft: String, event: DictationEvent.Failure): DictationStep {
  val anchor = state.anchor
  if (!openSession(state, event.sessionId) || anchor == null) return unchanged(state, draft)
  if (state.provisional.isEmpty()) {
    val restored = committedDraft(anchor)
    val caret = anchor.prefix.length + anchor.replaced.length
    val message = event.message.trim().ifEmpty { DictationNoSpeechMessage }
    return closeSession(state, restored, caret, message)
  }
  val kept = draftWithProvisional(draft, anchor, state.provisional)
  return closeSession(state, kept, endOfMiddle(anchor, kept), event.message.trim())
}

private fun reduceLeave(state: DictationState, draft: String): DictationStep {
  if (state.phase == DictationPhase.Idle) return unchanged(state, draft)
  val bounds = selectionBounds(draft.length, state.selectionStart, state.selectionEnd)
  return DictationStep(
    state.copy(
      phase = DictationPhase.Idle,
      anchor = null,
      provisional = "",
      selectionStart = bounds.first,
      selectionEnd = bounds.second
    ),
    draft
  )
}

private fun applyRecognised(
  state: DictationState,
  anchor: DictationAnchor,
  recognised: String,
  commit: Boolean
): DictationStep {
  val middle = spacedHypothesis(anchor.prefix, recognised, anchor.suffix)
  val composed = anchor.prefix + middle + anchor.suffix
  if (composed.length > DictationDraftLimit) return overLimit(state, anchor)
  val caret = anchor.prefix.length + middle.length
  return DictationStep(
    state.copy(
      phase = if (commit) DictationPhase.Idle else state.phase,
      anchor = if (commit) null else anchor,
      provisional = if (commit) "" else recognised,
      selectionStart = caret,
      selectionEnd = caret,
      statusMessage = if (commit) "" else state.statusMessage
    ),
    composed
  )
}

private fun overLimit(state: DictationState, anchor: DictationAnchor): DictationStep {
  val kept = anchor.prefix + anchor.suffix
  return closeSession(state, kept, anchor.prefix.length.coerceAtMost(kept.length), DictationTooLongMessage)
}

private fun noSpeech(state: DictationState, anchor: DictationAnchor): DictationStep {
  val restored = committedDraft(anchor)
  return closeSession(state, restored, anchor.prefix.length + anchor.replaced.length, DictationNoSpeechMessage)
}

private fun closeSession(state: DictationState, draft: String, caret: Int, statusMessage: String): DictationStep {
  val at = caret.coerceIn(0, draft.length)
  return DictationStep(
    state.copy(
      phase = DictationPhase.Idle,
      anchor = null,
      provisional = "",
      selectionStart = at,
      selectionEnd = at,
      statusMessage = statusMessage
    ),
    draft
  )
}

private fun draftWithProvisional(draft: String, anchor: DictationAnchor, provisional: String): String {
  val shown = shownDraft(anchor, provisional)
  if (draft == shown) return draft
  val middle = middleBetween(anchor, draft)
  if (middle != null && middle.trim() == provisional) return draft
  return shown
}

private fun shownDraft(anchor: DictationAnchor, provisional: String): String {
  return anchor.prefix + spacedHypothesis(anchor.prefix, provisional, anchor.suffix) + anchor.suffix
}

private fun committedDraft(anchor: DictationAnchor): String {
  return anchor.prefix + anchor.replaced + anchor.suffix
}

private fun endOfMiddle(anchor: DictationAnchor, text: String): Int {
  val middle = middleBetween(anchor, text)
  if (middle != null) return anchor.prefix.length + middle.length
  return text.length
}

private fun middleBetween(anchor: DictationAnchor, text: String): String? {
  val prefix = anchor.prefix
  val suffix = anchor.suffix
  if (prefix.length + suffix.length > text.length) return null
  if (!text.startsWith(prefix) || !text.endsWith(suffix)) return null
  return text.substring(prefix.length, text.length - suffix.length)
}

private fun openSession(state: DictationState, sessionId: Int): Boolean {
  return state.anchor != null && state.phase != DictationPhase.Idle && sessionId > 0 && sessionId == state.sessionId
}

private fun selectionBounds(length: Int, selectionStart: Int, selectionEnd: Int): Pair<Int, Int> {
  val start = selectionStart.coerceIn(0, length)
  val end = selectionEnd.coerceIn(0, length)
  return if (start <= end) start to end else end to start
}

private fun unchanged(state: DictationState, draft: String): DictationStep = DictationStep(state, draft)
