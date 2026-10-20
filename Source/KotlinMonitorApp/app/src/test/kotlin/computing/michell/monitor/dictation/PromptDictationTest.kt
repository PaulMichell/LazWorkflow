package computing.michell.monitor.dictation

/* Prompt splicing without a device (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PromptDictationTest {
  @Test
  fun partialReplacesThePreviousHypothesis() {
    val started = start("", 0)
    val partial = apply(started, DictationEvent.Partial(started.state.sessionId, "Hel"))
    assertEquals("Hel", partial.draft)
    val replaced = apply(partial, DictationEvent.Partial(started.state.sessionId, "Hello"))
    assertEquals("Hello", replaced.draft)
    assertFalse(replaced.draft.contains("HelHello"))
  }

  @Test
  fun finalReplacesTheMiddleAndClearsTheAnchor() {
    val started = start("Keep", 4)
    val id = started.state.sessionId
    val partial = apply(started, DictationEvent.Partial(id, "Hel"))
    assertEquals("Keep Hel", partial.draft)
    assertTrue(partial.state.anchor != null)
    val committed = apply(partial, DictationEvent.Final(id, "Hello"))
    assertEquals("Keep Hello", committed.draft)
    assertFalse(committed.draft.contains("HelHello"))
    assertNull(committed.state.anchor)
    assertEquals("", committed.state.provisional)
    assertEquals(DictationPhase.Idle, committed.state.phase)
  }

  @Test
  fun secondSessionAppendsWithOneSpace() {
    val first = "Explain how PostgreSQL indexes work."
    val second = "Include examples using spatial queries."
    val started = start("", 0)
    val committed = apply(started, DictationEvent.Final(started.state.sessionId, first))
    assertEquals(first, committed.draft)
    val again = apply(committed, DictationEvent.Start(committed.draft.length, committed.draft.length))
    val both = apply(again, DictationEvent.Final(again.state.sessionId, second))
    assertEquals("$first $second", both.draft)
    assertEquals(0, both.draft.indexOf(first))
    assertEquals(first.length + 1, both.draft.indexOf(second))
    assertFalse(both.draft.contains("$first$second"))
  }

  @Test
  fun caretAndSelectionDoNotDoubleSpaces() {
    val beforeSpace = dictate("Hello world", 6, 6, "there")
    assertEquals("Hello there world", beforeSpace.draft)
    assertFalse(beforeSpace.draft.contains("  "))

    val afterSpace = dictate("Hello world", 5, 5, "there")
    assertEquals("Hello there world", afterSpace.draft)
    assertFalse(afterSpace.draft.contains("  "))

    val betweenSpaces = dictate("Hello  world", 6, 6, "there")
    assertEquals("Hello there world", betweenSpaces.draft)
    assertFalse(betweenSpaces.draft.contains("  "))

    val replaced = dictate("Hello big world", 6, 9, "small")
    assertEquals("Hello small world", replaced.draft)
    assertFalse(replaced.draft.contains("  "))
    assertFalse(replaced.draft.contains("big"))
  }

  @Test
  fun emptyStopRestoresTheHiddenSelection() {
    val draft = "Hello brave world"
    val started = start(draft, 6, 11)
    assertEquals("Hello  world", started.draft)
    assertFalse(started.draft.contains("brave"))
    val toggled = apply(started, DictationEvent.ToggleOff(started.state.sessionId))
    assertEquals(draft, toggled.draft)
    val timed = apply(started, DictationEvent.Timeout(started.state.sessionId))
    assertEquals(draft, timed.draft)

    val heard = apply(started, DictationEvent.Partial(started.state.sessionId, "bold"))
    assertEquals("Hello bold world", heard.draft)
    val keptOff = apply(heard, DictationEvent.ToggleOff(heard.state.sessionId))
    assertEquals("Hello bold world", keptOff.draft)
    val keptTimeout = apply(heard, DictationEvent.Timeout(heard.state.sessionId))
    assertEquals("Hello bold world", keptTimeout.draft)
  }

  @Test
  fun failureRestoresCommittedTextAndIgnoresALateFinal() {
    val committed = "Keep this text."
    val started = start(committed, 5, 9)
    assertFalse(started.draft.contains("this"))
    val id = started.state.sessionId
    val failed = apply(started, DictationEvent.Failure(id, "speech recognition failed."))
    assertEquals(committed, failed.draft)
    assertEquals(DictationPhase.Idle, failed.state.phase)
    val late = apply(failed, DictationEvent.Final(id, "other words"))
    assertEquals(committed, late.draft)
    val older = apply(failed, DictationEvent.Final(id - 1, "older words"))
    assertEquals(committed, older.draft)
  }

  @Test
  fun stopAndLeaveKeepTextTypedBeforeTheMicrophone() {
    val typed = "Explain indexes."
    val started = start(typed, typed.length)
    assertEquals(typed, started.draft)
    val id = started.state.sessionId
    val toggled = apply(started, DictationEvent.ToggleOff(id))
    assertEquals(typed, toggled.draft)
    assertFalse(toggled.draft.isEmpty())
    val timed = apply(started, DictationEvent.Timeout(id))
    assertEquals(typed, timed.draft)
    val left = apply(started, DictationEvent.LeaveScreen)
    assertEquals(typed, left.draft)
    assertEquals(DictationPhase.Idle, left.state.phase)
    val late = apply(left, DictationEvent.Final(id, ""))
    assertEquals(typed, late.draft)
  }

  @Test
  fun leaveScreenKeepsTheShownDraft() {
    val started = start("Keep this.", 10)
    val id = started.state.sessionId
    val heard = apply(started, DictationEvent.Partial(id, "Hello"))
    assertEquals("Keep this. Hello", heard.draft)
    val left = apply(heard, DictationEvent.LeaveScreen)
    assertEquals(heard.draft, left.draft)
    assertEquals(DictationPhase.Idle, left.state.phase)
    val lateFinal = apply(left, DictationEvent.Final(id, "Other words"))
    assertEquals(heard.draft, lateFinal.draft)
    val latePartial = apply(left, DictationEvent.Partial(id, "More"))
    assertEquals(heard.draft, latePartial.draft)
  }

  @Test
  fun staleEditKeepsTypedTextAndIgnoresALateFinal() {
    val started = start("Hello world", 6)
    val id = started.state.sessionId
    val edited = apply(started, "Hello there!", DictationEvent.Edited(12, 12))
    assertEquals("Hello there!", edited.draft)
    assertEquals(DictationPhase.Idle, edited.state.phase)
    assertNull(edited.state.anchor)
    val late = apply(edited, DictationEvent.Final(id, "people"))
    assertEquals("Hello there!", late.draft)
  }

  @Test
  fun middleEditAcceptsTheNextPartialAsAReplacement() {
    val started = start("Hello", 5)
    val id = started.state.sessionId
    val heard = apply(started, DictationEvent.Partial(id, "there"))
    assertEquals("Hello there", heard.draft)
    val edited = apply(heard, "Hello friend", DictationEvent.Edited(12, 12))
    assertEquals("Hello friend", edited.draft)
    assertEquals(DictationPhase.Listening, edited.state.phase)
    assertTrue(edited.state.anchor != null)
    val replaced = apply(edited, DictationEvent.Partial(id, "people"))
    assertEquals("Hello people", replaced.draft)
    assertFalse(replaced.draft.contains("friend"))
    assertFalse(replaced.draft.contains("therepeople"))
  }

  @Test
  fun blankPartialAndBlankFinalDoNotClearCommittedText() {
    val committed = "Keep this."
    val started = start(committed, committed.length)
    val id = started.state.sessionId
    val heard = apply(started, DictationEvent.Partial(id, "Hello"))
    assertEquals("Keep this. Hello", heard.draft)
    val blankPartial = apply(heard, DictationEvent.Partial(id, "   "))
    assertEquals("Keep this. Hello", blankPartial.draft)
    assertEquals("Hello", blankPartial.state.provisional)
    val blankFinal = apply(blankPartial, DictationEvent.Final(id, "  "))
    assertEquals(committed, blankFinal.draft)
    assertTrue(blankFinal.draft.contains(committed))
    assertFalse(blankFinal.draft.isEmpty())
  }

  @Test
  fun hypothesisDoesNotGrowADraftAtTheSendLimit() {
    val committed = "a".repeat(DictationDraftLimit)
    val started = start(committed, committed.length)
    val id = started.state.sessionId
    val partial = apply(started, DictationEvent.Partial(id, "more"))
    assertEquals(committed, partial.draft)
    assertEquals(DictationDraftLimit, partial.draft.length)
    assertEquals(DictationTooLongMessage, partial.state.statusMessage)
    assertFalse(partial.state.listening)
    val late = apply(partial, DictationEvent.Final(id, "still more"))
    assertEquals(committed, late.draft)
    assertEquals(DictationDraftLimit, late.draft.length)
  }

  private fun start(draft: String, selectionStart: Int, selectionEnd: Int = selectionStart): DictationStep {
    return reduceDictation(DictationState(), draft, DictationEvent.Start(selectionStart, selectionEnd))
  }

  private fun dictate(draft: String, selectionStart: Int, selectionEnd: Int, text: String): DictationStep {
    val started = start(draft, selectionStart, selectionEnd)
    return apply(started, DictationEvent.Final(started.state.sessionId, text))
  }

  private fun apply(step: DictationStep, event: DictationEvent): DictationStep {
    return reduceDictation(step.state, step.draft, event)
  }

  private fun apply(step: DictationStep, draft: String, event: DictationEvent): DictationStep {
    return reduceDictation(step.state, draft, event)
  }
}
