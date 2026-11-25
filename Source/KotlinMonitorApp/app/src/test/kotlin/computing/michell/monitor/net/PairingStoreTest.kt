package computing.michell.monitor.net

/* Endpoint pairing records. The Android file is encrypted; this map is the
   same key layout without a keystore. (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class PairingStoreTest {
  @Test
  fun anUnknownEndpointHasNoToken() {
    val store = PairingStore(MemoryPairingMap())
    val missing = store.lookup("10.1.1.1", 56122)
    assertEquals("", missing.token)
    assertEquals("", missing.pin)
    assertFalse(missing.paired)
    assertEquals("", store.pinFor("10.1.1.1", 56122))
  }
}
