package computing.michell.monitor.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class IdentityTest {
  @Test
  fun cursorDoesNotUseTurnIndex() {
    assertEquals(CursorStep.First, cursorStep("", 0, "aa", 0))
    assertEquals(CursorStep.Progress, cursorStep("aa", 4, "aa", 5))
    assertEquals(CursorStep.Duplicate, cursorStep("aa", 4, "aa", 4))
    assertEquals(CursorStep.Duplicate, cursorStep("aa", 4, "aa", 3))
    assertEquals(CursorStep.Gap, cursorStep("aa", 4, "aa", 6))
    assertEquals(CursorStep.NewEpoch, cursorStep("aa", 4, "bb", 1))
  }

  @Test
  fun newEpochKeepsTheScreenUntilCatchup() {
    val shown = MirrorPlace(epoch = "aa", cursor = 4, conversationId = "current", title = "Shown")
    val hello = noteHelloIdentity(shown, "bb", 0, "conversation-20261019T120000000", "/work", "Archived", true)
    assertEquals("aa", hello.epoch)
    assertEquals(4L, hello.cursor)
    assertEquals("Shown", hello.title)
    assertTrue(hello.catchingUp)
    assertEquals("bb", hello.announcedEpoch)
    val patch = notePatchIdentity(hello, "bb", 1)
    assertEquals("aa", patch.epoch)
    assertEquals(4L, patch.cursor)
    val caught = noteCatchupIdentity(hello, "bb", 0, "snapshot")
    assertEquals("bb", caught!!.epoch)
    assertEquals(0L, caught.cursor)
    assertFalse(caught.catchingUp)
  }

  @Test
  fun anEmptyEpochDoesNotAdoptHello() {
    val fresh = noteHelloIdentity(MirrorPlace(), "bb", 4, "current", "/work", "Shown", false)
    assertEquals("", fresh.epoch)
    assertEquals(0L, fresh.cursor)
    assertTrue(fresh.catchingUp)
    assertEquals("bb", fresh.announcedEpoch)
    assertEquals("Shown", fresh.title)
  }

  @Test
  fun duplicateAndGapDoNotAdvance() {
    val place = MirrorPlace(epoch = "aa", cursor = 4)
    assertEquals(place, notePatchIdentity(place, "aa", 4))
    assertEquals(place, notePatchIdentity(place, "aa", 2))
    assertEquals(place, notePatchIdentity(place, "aa", 9))
    assertNull(noteCatchupIdentity(place, "aa", 4, "events"))
    assertNull(noteCatchupIdentity(place, "aa", 9, "events"))
    assertEquals(9L, noteCatchupIdentity(place, "aa", 9, "snapshot")!!.cursor)
  }
}
