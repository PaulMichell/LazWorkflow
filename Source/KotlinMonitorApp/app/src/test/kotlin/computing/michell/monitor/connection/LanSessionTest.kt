package computing.michell.monitor.connection

/* TLS session rules without a device or a cleartext socket (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.MonitorLimits
import computing.michell.monitor.protocol.MonitorMessage
import computing.michell.monitor.protocol.authMac
import computing.michell.monitor.protocol.decodeAuth
import computing.michell.monitor.protocol.decodeBye
import computing.michell.monitor.protocol.decodeHello
import computing.michell.monitor.protocol.decodePair
import computing.michell.monitor.protocol.encodeBye
import computing.michell.monitor.protocol.encodeError
import computing.michell.monitor.protocol.encodeRejected
import computing.michell.monitor.protocol.encodeTicks
import computing.michell.monitor.protocol.HelloOkMessage
import computing.michell.monitor.protocol.encodeHelloOk
import computing.michell.monitor.protocol.tryDecodeEnvelope
import computing.michell.monitor.protocol.tryDecodeFrame
import computing.michell.monitor.protocol.tryEncodeFrame
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.ConnectException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
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
  fun lanBackoffIsCappedAtTenSecondsWithJitter() {
    val full = ReconnectPolicy { 999 }
    assertEquals(1_000L, full.nextDelayMs())
    assertEquals(2_000L, full.nextDelayMs())
    assertEquals(4_000L, full.nextDelayMs())
    assertEquals(8_000L, full.nextDelayMs())
    assertEquals(LanBackoffCapMs, full.nextDelayMs())
    assertEquals(LanBackoffCapMs, full.nextDelayMs())
    full.resume()
    assertEquals(1_000L, full.nextDelayMs())
    val half = ReconnectPolicy { 0 }
    assertEquals(500L, half.nextDelayMs())
    assertEquals(1_000L, half.nextDelayMs())
    assertEquals(2_000L, half.nextDelayMs())
    assertEquals(4_000L, half.nextDelayMs())
    assertEquals(5_000L, half.nextDelayMs())
    assertEquals(5_000L, half.nextDelayMs())
    for (roll in -3..1004) {
      val delay = jitteredLanDelayMs(30_000L, roll)
      assertTrue(delay in 5_000L..LanBackoffCapMs)
    }
    assertEquals(8_000L, jitteredLanDelayMs(8_000L, 999))
    assertEquals(4_000L, jitteredLanDelayMs(8_000L, 0))
  }

  @Test
  fun refusedConnectPausesUntilTheUserResumes() {
    val policy = ReconnectPolicy { 999 }
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
    assertEquals("", loaded.fingerprint)
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
    session.connect("10.0.0.8", 56122)
    waitUntil { session.status.value.banner == "TLS pin mismatch." }
    Thread.sleep(400)
    assertEquals(1, opens.get())
    assertEquals("client-1", store.load().clientId)
    assertEquals("token-1", store.load().sessionToken)
    assertEquals("unsent prompt", session.promptDraft)
    session.close()
  }

  @Test
  fun connectionRefusedKeepsTheDraftAndRetriesWithoutATap() {
    val store = pairedStore()
    val pin = store.load().fingerprint
    val opens = AtomicInteger(0)
    val session = LanSession(store, TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      throw ConnectException("Connection refused")
    })
    try {
      session.updateDraft("draft")
      session.connect("10.0.0.8", 56122)
      waitUntil { opens.get() == 1 }
      Thread.sleep(400)
      assertEquals(1, opens.get())
      assertFalse(session.reconnectPaused)
      assertEquals(ConnectionRefusedBanner, session.status.value.banner)
      assertEquals("draft", session.promptDraft)
      assertEquals(pin, store.load().fingerprint)
      // Equal jitter keeps the first retry between 500 ms and 1 s.
      waitUntil(2_000) { opens.get() >= 2 }
      assertEquals("draft", session.promptDraft)
      assertEquals(pin, store.load().fingerprint)
    } finally {
      session.close()
    }
  }

  @Test
  fun wifiLossWaitsAndAvailableReconnectsWithoutClearingThePin() {
    val store = pairedStore()
    val pin = store.load().fingerprint
    val opens = AtomicInteger(0)
    val session = LanSession(store, TlsConnector { _, _, fingerprint ->
      assertEquals(pin, fingerprint)
      opens.incrementAndGet()
      throw ConnectException("Connection refused")
    })
    try {
      session.onWifiLost()
      session.connect("10.0.0.8", 56122)
      Thread.sleep(400)
      assertEquals(0, opens.get())
      assertEquals(WaitingForWifiBanner, session.status.value.banner)
      assertEquals(pin, store.load().fingerprint)
      val started = System.currentTimeMillis()
      session.onWifiAvailable()
      waitUntil { opens.get() >= 1 }
      assertTrue(System.currentTimeMillis() - started < 400)
      assertEquals(pin, store.load().fingerprint)
    } finally {
      session.close()
    }
  }

  @Test
  fun wifiAvailableDuringBackoffReconnectsAtOnce() {
    val store = pairedStore()
    val pin = store.load().fingerprint
    val opens = AtomicInteger(0)
    val session = LanSession(store, TlsConnector { _, _, _ ->
      val count = opens.incrementAndGet()
      if (count == 1) throw ConnectException("Connection refused")
      ScriptedLink()
    })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { opens.get() == 1 }
      val started = System.currentTimeMillis()
      session.onWifiAvailable()
      waitUntil { opens.get() >= 2 }
      assertTrue(System.currentTimeMillis() - started < 400)
      assertEquals(pin, store.load().fingerprint)
    } finally {
      session.close()
    }
  }

  @Test
  fun backgroundSendsByeAndForegroundResumesWithoutClearingThePin() {
    val store = pairedStore()
    val pin = store.load().fingerprint
    val link = ScriptedLink()
    val opens = AtomicInteger(0)
    val session = LanSession(store, TlsConnector { _, _, fingerprint ->
      assertEquals(pin, fingerprint)
      opens.incrementAndGet()
      link
    })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { link.frames().isNotEmpty() }
      session.leaveForeground()
      waitUntil {
        link.frames().any { frame -> envelope(frame).kind == MessageKind.Bye }
      }
      val bye = link.frames().map { envelope(it) }.last { it.kind == MessageKind.Bye }
      assertEquals(ByeBackground, decodeBye(bye.payloadJson)!!.reason)
      waitUntil { link.closed }
      Thread.sleep(400)
      assertEquals(1, opens.get())
      assertEquals(pin, store.load().fingerprint)
      session.enterForeground()
      waitUntil { opens.get() >= 2 }
      assertEquals(pin, store.load().fingerprint)
    } finally {
      session.close()
    }
  }

  @Test
  fun wifiDoesNotResumeADisabledHost() {
    val store = pairedStore()
    val pin = store.load().fingerprint
    val link = ScriptedLink()
    val opens = AtomicInteger(0)
    val session = LanSession(store, TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      link
    })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { link.frames().isNotEmpty() }
      link.push(frameOf(encodeBye("host-bye", "disabled")))
      waitUntil { session.reconnectPaused }
      session.onWifiAvailable()
      session.enterForeground()
      Thread.sleep(400)
      assertEquals(1, opens.get())
      assertTrue(session.reconnectPaused)
      assertEquals(pin, store.load().fingerprint)
    } finally {
      session.close()
    }
  }

  @Test
  fun hostPingIsAnsweredWithPong() {
    val store = pairedStore()
    val link = ScriptedLink()
    val session = LanSession(store, TlsConnector { _, _, _ -> link })
    session.connect("10.0.0.8", 56122)
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
  fun reconnectSendsAuthAndKeepsTheDraft() {
    val store = pairedStore()
    val link = ScriptedLink()
    val session = LanSession(store, TlsConnector { _, _, _ -> link })
    session.updateDraft("keep me")
    session.connect("10.0.0.8", 56122)
    waitUntil { link.frames().size >= 1 }
    val hello = envelope(link.frames()[0])
    assertEquals(MessageKind.Hello, hello.kind)
    assertEquals("client-1", decodeHello(hello.payloadJson)!!.clientId)
    link.push(frameOf(encodeHelloOk("host-1", HelloOkMessage(
      "00112233445566778899aabbccddeeff", "LazAssistantMonitor", "", 0, "", "", ""
    ))))
    waitUntil { link.frames().size >= 2 }
    val auth = envelope(link.frames()[1])
    assertEquals(MessageKind.Auth, auth.kind)
    assertFalse(link.frames().any { frame -> envelope(frame).kind == MessageKind.Refresh })
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
    session.connect("10.0.0.8", 56122)
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

  @Test
  fun twoArgumentConnectKeepsTheSavedPin() {
    val store = HostStore(MemoryStringMap())
    val pin = "ab".repeat(32)
    store.save(HostRecord("10.0.0.8", 56122, pin, "client-1", "token-1"))
    val connector = RecordingConnector()
    val session = LanSession(store, connector)
    try {
      session.connect("10.0.0.8", 56122)
      assertEquals(pin, store.load().fingerprint)
      assertEquals("client-1", store.load().clientId)
      assertEquals("token-1", store.load().sessionToken)
      waitUntil { connector.fingerprints().isNotEmpty() }
      assertEquals(listOf(pin), connector.fingerprints())
    } finally {
      session.close()
    }
  }

  @Test
  fun replaceFingerprintRejectsGarbageAndShortHex() {
    val store = HostStore(MemoryStringMap())
    val pin = "ab".repeat(32)
    val saved = HostRecord("10.0.0.8", 56122, pin, "client-1", "token-1")
    store.save(saved)
    val connector = RecordingConnector()
    val session = LanSession(store, connector)
    try {
      session.replaceFingerprint("zzzz")
      assertEquals(saved, store.load())
      assertEquals(0, connector.fingerprints().size)
      assertEquals("TLS pin mismatch.", session.status.value.banner)
      session.replaceFingerprint("abcd")
      assertEquals(saved, store.load())
      assertEquals(0, connector.fingerprints().size)
      assertEquals("TLS pin mismatch.", session.status.value.banner)
      val grouped = "cd".repeat(32).chunked(2).joinToString(" ")
      session.replaceFingerprint(grouped)
      assertEquals(grouped, store.load().fingerprint)
      assertEquals("client-1", store.load().clientId)
      assertEquals(0, connector.fingerprints().size)
    } finally {
      session.close()
    }
  }

  @Test
  fun storedGarbagePinDoesNotOpenWithTrustAll() {
    val store = HostStore(MemoryStringMap())
    store.save(HostRecord("10.0.0.8", 56122, "zzzz", "client-1", "token-1"))
    val connector = RecordingConnector()
    val session = LanSession(store, connector)
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { session.status.value.banner == "TLS pin mismatch." }
      assertTrue(connector.fingerprints().isEmpty())
      assertEquals("zzzz", store.load().fingerprint)
      assertEquals("client-1", store.load().clientId)
    } finally {
      session.close()
    }
  }

  @Test
  fun changedHostKeepsThePinAndClearsTheCredential() {
    val store = HostStore(MemoryStringMap())
    val pin = "cd".repeat(32)
    store.save(HostRecord("10.0.0.8", 56122, pin, "client-1", "token-1"))
    val connector = RecordingConnector()
    val session = LanSession(store, connector)
    try {
      session.connect("10.0.0.9", 56123, "new-code")
      val loaded = store.load()
      assertEquals("10.0.0.9", loaded.address)
      assertEquals(56123, loaded.port)
      assertEquals(pin, loaded.fingerprint)
      assertEquals("", loaded.clientId)
      assertEquals("", loaded.sessionToken)
      waitUntil { connector.fingerprints().isNotEmpty() }
      assertEquals(listOf(pin), connector.fingerprints())
    } finally {
      session.close()
    }
  }

  @Test
  fun clearFingerprintDropsThePinWithoutConnecting() {
    val store = HostStore(MemoryStringMap())
    val pin = "ab".repeat(32)
    store.save(HostRecord("10.0.0.8", 56122, pin, "client-1", "token-1"))
    val connector = RecordingConnector()
    val session = LanSession(store, connector)
    try {
      session.clearFingerprint()
      val loaded = store.load()
      assertEquals("", loaded.fingerprint)
      assertEquals("10.0.0.8", loaded.address)
      assertEquals(56122, loaded.port)
      assertEquals("client-1", loaded.clientId)
      assertEquals("token-1", loaded.sessionToken)
      assertEquals(0, connector.fingerprints().size)
    } finally {
      session.close()
    }
  }

  @Test
  fun nonemptyInvalidPinDoesNotSelectTrustAll() {
    assertTrue(trustManagerForFingerprint("") is TrustAllManager)
    assertTrue(trustManagerForFingerprint("ab".repeat(32)) is PinnedTrustManager)
    assertTrue(trustManagerForFingerprint("ab".repeat(32).chunked(2).joinToString(":")) is PinnedTrustManager)
    var refused = false
    try {
      trustManagerForFingerprint("zzzz")
    } catch (error: PinMismatchException) {
      refused = true
    }
    assertTrue(refused)
    refused = false
    try {
      trustManagerForFingerprint("abcd")
    } catch (error: PinMismatchException) {
      refused = true
    }
    assertTrue(refused)
  }

  @Test
  fun heldCollectorDeliversEveryNonCoalescedEvent() = runBlocking {
    val delivery = InboundDelivery(SteppableClock())
    val received = mutableListOf<String>()
    val hold = CompletableDeferred<Unit>()
    val started = CompletableDeferred<Unit>()
    val collector = launch {
      delivery.messages.collect { message ->
        received += message.id
        if (received.size == 1) {
          started.complete(Unit)
          hold.await()
        }
      }
    }
    try {
      assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.Error, "m0")))
      started.await()
      for (index in 1..64) {
        assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.Error, "m$index")))
      }
      assertFalse(delivery.isWaiting())
      hold.complete(Unit)
      withTimeout(5_000) {
        while (received.size < 65) yield()
      }
      assertEquals((0..64).map { "m$it" }, received.toList())
    } finally {
      hold.complete(Unit)
      collector.cancel()
    }
  }

  @Test
  fun statusBurstKeepsTheLatestStatusAndTheApproval() = runBlocking {
    val delivery = InboundDelivery(SteppableClock())
    val received = mutableListOf<String>()
    val hold = CompletableDeferred<Unit>()
    val started = CompletableDeferred<Unit>()
    val collector = launch {
      delivery.messages.collect { message ->
        received += message.id
        if (received.size == 1) {
          started.complete(Unit)
          hold.await()
        }
      }
    }
    try {
      assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.Ping, "held")))
      started.await()
      assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.Status, "status-1")))
      assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.Snapshot, "snap-1")))
      assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.ApprovalRequested, "approval")))
      assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.Status, "status-2")))
      assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.Snapshot, "snap-2")))
      assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.Status, "status-3")))
      hold.complete(Unit)
      withTimeout(5_000) {
        while (received.size < 4) yield()
      }
      assertEquals(listOf("held", "status-3", "snap-2", "approval"), received.toList())
    } finally {
      hold.complete(Unit)
      collector.cancel()
    }
  }

  @Test
  fun aFullCreditWindowFailsWithoutWaiting() = runBlocking {
    val delivery = InboundDelivery(SteppableClock(), byteBudget = 3)
    assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.Error, "held")))
    assertEquals(DeliveryResult.Failed, delivery.publish(inboundMessage(MessageKind.Error, "overflow")))
    assertFalse(delivery.isWaiting())
  }

  @Test
  fun aHeldCollectorDoesNotCloseTheLink() {
    val clock = SteppableClock()
    val link = ScriptedLink()
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ -> link }, clock)
    val hold = CompletableDeferred<Unit>()
    val got = CompletableDeferred<Unit>()
    val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    val collector = scope.launch {
      session.messages.collect {
        if (!got.isCompleted) got.complete(Unit)
        hold.await()
      }
    }
    try {
      session.connect("10.0.0.8", 56122)
      link.push(frameOf(encodeError("e0", "x", "held", "e0")))
      waitUntil { got.isCompleted }
      for (index in 1..8) link.push(frameOf(encodeError("e$index", "x", "queued", "e$index")))
      clock.advanceMs(1_000L)
      assertFalse(link.closed)
      assertFalse(session.inbound.isWaiting())
    } finally {
      hold.complete(Unit)
      collector.cancel()
      scope.cancel()
      session.close()
    }
  }

  @Test
  fun silentPeerEndsAtTheDeadline() {
    val clock = SteppableClock()
    val link = ScriptedLink()
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ -> link }, clock)
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { link.readEntries.get() > 0 }
      clock.advanceMs(MonitorLimits.DeadSessionMs)
      waitUntil(2_000) { link.closed && session.status.value.banner == ReconnectingBanner }
      assertTrue(link.closed)
      assertEquals(ReconnectingBanner, session.status.value.banner)
      assertFalse(session.reconnectPaused)
    } finally {
      session.close()
    }
  }

  @Test
  fun rejectedPeerEndsWithoutWaitingForEof() {
    val link = ScriptedLink()
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ -> link })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { link.frames().isNotEmpty() }
      // busy used to set the continue sentinel, so an open input never released the loop.
      link.push(frameOf(encodeRejected("host-busy", "busy", 1, 1)))
      waitUntil(2_000) { link.closed }
      assertTrue(link.closed)
      assertEquals(ReconnectingBanner, session.status.value.banner)
      assertFalse(session.reconnectPaused)
    } finally {
      session.close()
    }
  }

  @Test
  fun failedPongWriteEndsTheLoopAndClosesTheSocket() {
    val link = ScriptedLink { bytes ->
      if (String(bytes, Charsets.ISO_8859_1).contains("\"type\" : \"pong\"")) throw IOException("pong write failed")
    }
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ -> link })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { link.frames().isNotEmpty() }
      link.push(frameOf(encodeTicks(MessageKind.Ping, "host-ping", 42)))
      waitUntil(2_000) { link.closed && session.status.value.banner == ReconnectingBanner }
      assertTrue(link.closed)
      assertEquals(ReconnectingBanner, session.status.value.banner)
      assertFalse(session.reconnectPaused)
    } finally {
      session.close()
    }
  }

  @Test
  fun timeoutReadDoesNotResetTheDeadline() {
    val clock = SteppableClock()
    val link = ScriptedLink()
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ -> link }, clock)
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { link.readEntries.get() > 0 }
      clock.advanceMs(MonitorLimits.DeadSessionMs - 1)
      val seen = link.readEntries.get()
      link.releaseTimeout()
      waitUntil { link.readEntries.get() > seen }
      clock.advanceMs(MonitorLimits.DeadSessionMs - 1)
      waitUntil(2_000) { link.closed && session.status.value.banner == ReconnectingBanner }
      assertFalse(session.reconnectPaused)
    } finally {
      session.close()
    }
  }

  @Test
  fun peerThatAnswersWithinTheDeadlineStaysUp() {
    val clock = SteppableClock()
    val link = ScriptedLink()
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ -> link }, clock)
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { link.readEntries.get() > 0 }
      clock.advanceMs(MonitorLimits.DeadSessionMs - 1)
      val seen = link.readEntries.get()
      link.push(frameOf(encodeTicks(MessageKind.Pong, "host-pong", 9)))
      waitUntil { link.readEntries.get() > seen }
      clock.advanceMs(MonitorLimits.DeadSessionMs - 1)
      assertFalse(link.closed)
      assertFalse(session.reconnectPaused)
      clock.advanceMs(1)
      waitUntil(2_000) { link.closed && session.status.value.banner == ReconnectingBanner }
    } finally {
      session.close()
    }
  }
}

private fun inboundMessage(kind: MessageKind, id: String): MonitorMessage {
  return MonitorMessage(1, id, kind, kind.wireName, "{}", "", true, "{}")
}

private class RecordingConnector : TlsConnector {
  private val seen = mutableListOf<String>()

  override fun open(address: String, port: Int, fingerprint: String): TlsLink {
    synchronized(seen) { seen += fingerprint }
    throw PinMismatchException(fingerprint)
  }

  fun fingerprints(): List<String> = synchronized(seen) { seen.toList() }
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

private class ScriptedLink(private val rejectWrite: (ByteArray) -> Unit = {}) : TlsLink {
  private val chunks = mutableListOf<ByteArray>()
  private val inbound = QueueStream()
  val readEntries = AtomicInteger(0)
  override val input: InputStream = object : InputStream() {
    override fun read(): Int = inbound.read()

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
      readEntries.incrementAndGet()
      return inbound.read(buffer, offset, length)
    }
  }
  override val output: OutputStream = object : OutputStream() {
    override fun write(value: Int) {
      val slice = byteArrayOf(value.toByte())
      rejectWrite(slice)
      synchronized(chunks) { chunks += slice }
    }

    override fun write(buffer: ByteArray, offset: Int, length: Int) {
      val slice = buffer.copyOfRange(offset, offset + length)
      rejectWrite(slice)
      synchronized(chunks) { chunks += slice }
    }
  }

  fun frames(): List<ByteArray> {
    synchronized(chunks) { return chunks.toList() }
  }

  fun push(bytes: ByteArray) {
    inbound.push(bytes)
  }

  fun releaseTimeout() {
    inbound.releaseTimeout()
  }

  fun closeInput() {
    inbound.closeStream()
  }

  var closed = false
    private set

  override fun close() {
    closed = true
    closeInput()
  }
}

private class QueueStream : InputStream() {
  private val queue = ArrayDeque<Byte>()
  private var closed = false
  private var timeouts = 0

  fun push(bytes: ByteArray) {
    synchronized(queue) {
      for (byte in bytes) queue.addLast(byte)
      (queue as Object).notifyAll()
    }
  }

  fun releaseTimeout() {
    synchronized(queue) {
      timeouts += 1
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
    val buffer = ByteArray(1)
    val count = read(buffer, 0, 1)
    if (count <= 0) return -1
    return buffer[0].toInt() and 0xFF
  }

  override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
    if (length == 0) return 0
    synchronized(queue) {
      while (queue.isEmpty() && !closed && timeouts == 0) (queue as Object).wait(50)
      if (queue.isNotEmpty()) {
        var count = 0
        while (count < length && queue.isNotEmpty()) {
          buffer[offset + count] = queue.removeFirst()
          count += 1
        }
        return count
      }
      if (timeouts > 0 && !closed) {
        timeouts -= 1
        return 0
      }
      return -1
    }
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

