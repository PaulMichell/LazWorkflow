package computing.michell.monitor.protocol

/* UTF-8 length without copying the body (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class Utf8LengthTest {
  @Test
  fun lengthMatchesTheCodecForEmptyBmpEmojiAndALargeBody() {
    assertMatches("")
    assertMatches("café — 文字")
    assertMatches("A plan thought \uD83D\uDE00")
    val large = StringBuilder(100 * 1024 + 8)
    var index = 0
    while (large.length < 100 * 1024 + 1) {
      large.append(if (index % 64 == 0) "é" else "x")
      index += 1
    }
    assertMatches(large.toString())
  }

  @Test
  fun anUnpairedSurrogateFailsTheSameWayAsTheCodec() {
    val broken = "thought\uD800"
    assertNull(strictUtf8Bytes(broken))
    assertEquals(Int.MAX_VALUE, utf8Length(broken))
  }

  private fun assertMatches(text: String) {
    val bytes = strictUtf8Bytes(text)
    assertEquals(bytes?.size, utf8Length(text))
  }
}
