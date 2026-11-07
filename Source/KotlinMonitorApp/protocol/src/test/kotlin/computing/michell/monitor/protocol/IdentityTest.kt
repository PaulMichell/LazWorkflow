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


}
