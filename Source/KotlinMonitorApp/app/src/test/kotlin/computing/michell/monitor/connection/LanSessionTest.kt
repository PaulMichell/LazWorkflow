package computing.michell.monitor.connection

/* TLS session rules without a device or a cleartext socket (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.authMac
import computing.michell.monitor.protocol.decodeAuth
import computing.michell.monitor.protocol.decodeHello
import computing.michell.monitor.protocol.decodePair
import computing.michell.monitor.protocol.encodeBye
import computing.michell.monitor.protocol.encodeTicks
import computing.michell.monitor.protocol.encodeHelloOk
import computing.michell.monitor.protocol.tryDecodeEnvelope
import computing.michell.monitor.protocol.tryDecodeFrame
import computing.michell.monitor.protocol.tryEncodeFrame
import java.io.InputStream
import java.io.OutputStream
import java.net.ConnectException
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.Date
import java.util.concurrent.atomic.AtomicInteger
import javax.security.auth.x500.X500Principal
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LanSessionTest {
  @Test
  fun backoffIsOneTwoFourEightThenThirtySeconds() {
    val policy = ReconnectPolicy()
    assertEquals(1_000L, policy.nextDelayMs())
    assertEquals(2_000L, policy.nextDelayMs())
    assertEquals(4_000L, policy.nextDelayMs())
    assertEquals(8_000L, policy.nextDelayMs())
    assertEquals(30_000L, policy.nextDelayMs())
    assertEquals(30_000L, policy.nextDelayMs())
  }

  @Test
  fun refusedConnectPausesUntilTheUserResumes() {
    val policy = ReconnectPolicy()
    policy.pause()
    assertTrue(policy.paused)
    policy.resume()
    assertFalse(policy.paused)
    assertEquals(1_000L, policy.nextDelayMs())
  }

  @Test
  fun emptyFingerprintTrustsThePresentedCertificate() {
    val manager = TrustAllManager()
    manager.checkServerTrusted(arrayOf(FixedCertificate(byteArrayOf(1, 2, 3))), "RSA")
    var rejected = false
    try {
      manager.checkServerTrusted(emptyArray(), "RSA")
    } catch (error: CertificateException) {
      rejected = true
    }
    assertTrue(rejected)
  }

  @Test
  fun groupedFingerprintMatchesTheCertificateDigest() {
    val der = byteArrayOf(1, 2, 3, 4)
    val digest = sha256Hex(der)
    val grouped = digest.chunked(2).joinToString(" ")
    assertTrue(fingerprintsEqual(grouped, digest))
    assertFalse(fingerprintsEqual(digest, "ab".repeat(32)))
    val manager = PinnedTrustManager(grouped)
    manager.checkServerTrusted(arrayOf(FixedCertificate(der)), "RSA")
    var rejected = false
    try {
      manager.checkServerTrusted(arrayOf(FixedCertificate(byteArrayOf(9))), "RSA")
    } catch (error: PinMismatchException) {
      rejected = true
    }
    assertTrue(rejected)
  }

  @Test
  fun clearForgetsThePhonePairingAndWritesNoProviderSecret() {
    val memory = MemoryStringMap()
    val store = HostStore(memory)
    store.save(HostRecord("10.0.0.8", 56122, "ab".repeat(32), "client-1", "token-1"))
    assertEquals(HostStore.StoredKeys, memory.values.keys)
    store.clear()
    val loaded = store.load()
    assertEquals("", loaded.clientId)
    assertEquals("", loaded.sessionToken)
    assertFalse(loaded.paired)
    assertFalse(memory.values.keys.any { it.contains("api") || it.contains("oauth") || it.contains("model") })
  }

  @Test
  fun pinFailureDoesNotClearThePairingOrOpenAgain() {
    val store = pairedStore()
    val opens = AtomicInteger(0)
    val session = LanSession(store, TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      throw PinMismatchException("aa")
    })
    session.updateDraft("unsent prompt")
    session.connect("10.0.0.8", 56122, "ab".repeat(32), "")
    waitUntil { session.status.value.banner == "TLS pin mismatch." }
    Thread.sleep(400)
    assertEquals(1, opens.get())
    assertEquals("client-1", store.load().clientId)
    assertEquals("token-1", store.load().sessionToken)
    assertEquals("unsent prompt", session.promptDraft)
    session.close()
  }

  @Test
  fun connectionRefusedPausesBackoffUntilResume() {
    val store = pairedStore()
    val opens = AtomicInteger(0)
    val session = LanSession(store, TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      throw ConnectException("Connection refused")
    })
    session.updateDraft("draft")
    session.connect("10.0.0.8", 56122, "ab".repeat(32), "")
    waitUntil { session.reconnectPaused }
    Thread.sleep(400)
    assertEquals(1, opens.get())
    assertEquals(ConnectionRefusedBanner, session.status.value.banner)
    assertEquals("draft", session.promptDraft)
    session.resume()
    waitUntil { opens.get() >= 2 }
    assertEquals("draft", session.promptDraft)
    session.close()
  }

  @Test
  fun hostPingIsAnsweredWithPong() {
    val store = pairedStore()
    val link = ScriptedLink()
    val session = LanSession(store, TlsConnector { _, _, _ -> link })
    session.connect("10.0.0.8", 56122, "ab".repeat(32), "")
    waitUntil { link.frames().isNotEmpty() }
    link.push(frameOf(encodeTicks(MessageKind.Ping, "host-ping", 42)))
    waitUntil { link.frames().size >= 2 }
    val pong = envelope(link.frames().last())
    assertEquals(MessageKind.Pong, pong.kind)
    session.close()
  }

  @Test
  fun openEndpointSendsHelloThenEmptyPair() {
    val store = HostStore(MemoryStringMap())
    val link = ScriptedLink()
    var seenFingerprint = "unset"
    val session = LanSession(store, TlsConnector { _, _, fingerprint ->
      seenFingerprint = fingerprint
      link
    })
    session.connect("10.0.0.8", 56122)
    waitUntil { link.frames().size >= 2 }
    assertEquals("", seenFingerprint)
    val hello = envelope(link.frames()[0])
    val pair = envelope(link.frames()[1])
    assertEquals(MessageKind.Hello, hello.kind)
    assertFalse(decodeHello(hello.payloadJson)!!.hasClientId)
    assertEquals(MessageKind.Pair, pair.kind)
    val decoded = decodePair(pair.payloadJson)
    assertEquals("", decoded!!.code)
    assertEquals("", decoded.fingerprint)
    session.close()
  }

  @Test
  fun reconnectSendsAuthThenRefreshAndKeepsTheDraft() {
    val store = pairedStore()
    val link = ScriptedLink()
    val session = LanSession(store, TlsConnector { _, _, _ -> link })
    session.updateDraft("keep me")
    session.connect("10.0.0.8", 56122, "ab".repeat(32), "")
    waitUntil { link.frames().size >= 1 }
    val hello = envelope(link.frames()[0])
    assertEquals(MessageKind.Hello, hello.kind)
    assertEquals("client-1", decodeHello(hello.payloadJson)!!.clientId)
    link.push(frameOf(encodeHelloOk("host-1", "00112233445566778899aabbccddeeff", "LazAssistantMonitor")))
    waitUntil { link.frames().size >= 3 }
    val auth = envelope(link.frames()[1])
    val refresh = envelope(link.frames()[2])
    assertEquals(MessageKind.Auth, auth.kind)
    assertEquals(MessageKind.Refresh, refresh.kind)
    val decoded = decodeAuth(auth.payloadJson)
    assertEquals("client-1", decoded!!.clientId)
    assertEquals(authMac("token-1", "00112233445566778899aabbccddeeff"), decoded.hmac)
    link.closeInput()
    waitUntil { session.status.value.banner == ReconnectingBanner }
    assertEquals("keep me", session.promptDraft)
    assertEquals("token-1", store.load().sessionToken)
    session.close()
  }

  @Test
  fun disabledByePausesBackoffAndKeepsTheDraft() {
    val store = pairedStore()
    val link = ScriptedLink()
    val opens = AtomicInteger(0)
    val session = LanSession(store, TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      link
    })
    session.updateDraft("keep")
    session.connect("10.0.0.8", 56122, "ab".repeat(32), "")
    waitUntil { link.frames().isNotEmpty() }
    link.push(frameOf(encodeBye("host-bye", "disabled")))
    waitUntil { session.reconnectPaused }
    Thread.sleep(400)
    assertEquals(1, opens.get())
    assertEquals(HostClosedBanner, session.status.value.banner)
    assertEquals("keep", session.promptDraft)
    assertEquals("client-1", store.load().clientId)
    session.close()
  }
}

private fun pairedStore(): HostStore {
  val store = HostStore(MemoryStringMap())
  store.save(HostRecord("10.0.0.8", 56122, "ab".repeat(32), "client-1", "token-1"))
  return store
}

private fun frameOf(json: String): ByteArray {
  val encoded = tryEncodeFrame(json)
  assertTrue(encoded.ok)
  return encoded.bytes
}

private fun envelope(bytes: ByteArray): computing.michell.monitor.protocol.MonitorMessage {
  val frame = tryDecodeFrame(bytes)
  assertTrue(frame.ok)
  val decoded = tryDecodeEnvelope(frame.frame.json)
  assertTrue(decoded.ok)
  return decoded.message
}

private fun waitUntil(timeoutMs: Long = 5_000, condition: () -> Boolean) {
  val start = System.currentTimeMillis()
  while (!condition()) {
    if (System.currentTimeMillis() - start > timeoutMs) throw AssertionError("timed out")
    Thread.sleep(20)
  }
}

private class ScriptedLink : TlsLink {
  private val chunks = mutableListOf<ByteArray>()
  private val inbound = QueueStream()
  override val input: InputStream = inbound
  override val output: OutputStream = object : OutputStream() {
    override fun write(value: Int) {
      synchronized(chunks) { chunks += byteArrayOf(value.toByte()) }
    }

    override fun write(buffer: ByteArray, offset: Int, length: Int) {
      synchronized(chunks) { chunks += buffer.copyOfRange(offset, offset + length) }
    }
  }

  fun frames(): List<ByteArray> {
    synchronized(chunks) { return chunks.toList() }
  }

  fun push(bytes: ByteArray) {
    inbound.push(bytes)
  }

  fun closeInput() {
    inbound.closeStream()
  }

  override fun close() {
    closeInput()
  }
}

private class QueueStream : InputStream() {
  private val queue = ArrayDeque<Byte>()
  private var closed = false

  fun push(bytes: ByteArray) {
    synchronized(queue) {
      for (byte in bytes) queue.addLast(byte)
      (queue as Object).notifyAll()
    }
  }

  fun closeStream() {
    synchronized(queue) {
      closed = true
      (queue as Object).notifyAll()
    }
  }

  override fun read(): Int {
    synchronized(queue) {
      while (queue.isEmpty() && !closed) (queue as Object).wait(50)
      if (queue.isEmpty()) return -1
      return queue.removeFirst().toInt() and 0xFF
    }
  }

  override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
    if (length == 0) return 0
    val first = read()
    if (first < 0) return -1
    buffer[offset] = first.toByte()
    var count = 1
    synchronized(queue) {
      while (count < length && queue.isNotEmpty()) {
        buffer[offset + count] = queue.removeFirst()
        count += 1
      }
    }
    return count
  }
}

private class FixedCertificate(private val der: ByteArray) : X509Certificate() {
  override fun getEncoded(): ByteArray = der
  override fun toString(): String = "FixedCertificate"
  override fun checkValidity() {}
  override fun checkValidity(date: Date?) {}
  override fun getVersion(): Int = 3
  override fun getSerialNumber() = java.math.BigInteger.ONE
  override fun getIssuerDN(): java.security.Principal = X500Principal("CN=monitor")
  override fun getSubjectDN(): java.security.Principal = X500Principal("CN=monitor")
  override fun getNotBefore(): Date = Date(0)
  override fun getNotAfter(): Date = Date(Long.MAX_VALUE)
  override fun getTBSCertificate(): ByteArray = der
  override fun getSignature(): ByteArray = ByteArray(0)
  override fun getSigAlgName(): String = "SHA256withRSA"
  override fun getSigAlgOID(): String = "1.2.840.113549.1.1.11"
  override fun getSigAlgParams(): ByteArray? = null
  override fun getIssuerUniqueID(): BooleanArray? = null
  override fun getSubjectUniqueID(): BooleanArray? = null
  override fun getKeyUsage(): BooleanArray? = null
  override fun getBasicConstraints(): Int = -1
  override fun verify(key: java.security.PublicKey?) {}
  override fun verify(key: java.security.PublicKey?, provider: String?) {}
  override fun getPublicKey(): java.security.PublicKey {
    throw UnsupportedOperationException("unused")
  }
  override fun hasUnsupportedCriticalExtension(): Boolean = false
  override fun getCriticalExtensionOIDs(): Set<String> = emptySet()
  override fun getNonCriticalExtensionOIDs(): Set<String> = emptySet()
  override fun getExtensionValue(oid: String?): ByteArray? = null
}

