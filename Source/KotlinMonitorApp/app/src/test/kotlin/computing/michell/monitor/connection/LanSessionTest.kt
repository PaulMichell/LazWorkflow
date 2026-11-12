package computing.michell.monitor.connection

/* TLS session rules without a device or a cleartext socket (c) 2026 Michell Computing. */

import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.MonitorLimits
import computing.michell.monitor.protocol.MonitorMessage
import computing.michell.monitor.protocol.authMac
import computing.michell.monitor.protocol.decodeAuth
import computing.michell.monitor.protocol.decodeBye
import computing.michell.monitor.protocol.decodeResume
import computing.michell.monitor.protocol.decodeHello
import computing.michell.monitor.protocol.decodePair
import computing.michell.monitor.protocol.encodeBye
import computing.michell.monitor.protocol.encodeEmpty
import computing.michell.monitor.protocol.encodeError
import computing.michell.monitor.protocol.encodeRejected
import computing.michell.monitor.protocol.encodeTicks
import computing.michell.monitor.protocol.HelloOkMessage
import computing.michell.monitor.protocol.encodeCommandStates
import computing.michell.monitor.protocol.encodeHelloOk
import computing.michell.monitor.protocol.tryEncodeSend
import computing.michell.monitor.protocol.CommandStateMessage
import computing.michell.monitor.protocol.tryDecodeEnvelope
import computing.michell.monitor.protocol.tryDecodeFrame
import computing.michell.monitor.protocol.tryEncodeFrame
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.ConnectException
import java.util.concurrent.Executors
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.withContext
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
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import javax.security.auth.x500.X500Principal
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LanSessionTest {
  @Test
  fun lanBackoffRampsWithJitterThenRetriesEveryThirtySeconds() {
    val full = ReconnectPolicy { 999 }
    assertEquals(1_000L, full.nextDelayMs())
    assertEquals(2_000L, full.nextDelayMs())
    assertEquals(4_000L, full.nextDelayMs())
    assertEquals(8_000L, full.nextDelayMs())
    assertEquals(LanSlowRetryMs, full.nextDelayMs())
    assertEquals(LanSlowRetryMs, full.nextDelayMs())
    full.resume()
    assertEquals(1_000L, full.nextDelayMs())
    val half = ReconnectPolicy { 0 }
    assertEquals(500L, half.nextDelayMs())
    assertEquals(1_000L, half.nextDelayMs())
    assertEquals(2_000L, half.nextDelayMs())
    assertEquals(4_000L, half.nextDelayMs())
    // The slow retry is not jittered.
    assertEquals(30_000L, half.nextDelayMs())
    assertEquals(30_000L, half.nextDelayMs())
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
  fun touchRetriesWhenLanAvailableIsFalseWithoutOnAvailable() {
    val store = pairedStore()
    val clock = SteppableClock()
    val opens = AtomicInteger(0)
    val session = LanSession(store, TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      throw ConnectException("Connection refused")
    }, clock)
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { opens.get() == 1 }
      clock.advanceMs(LanActiveWindowMs)
      waitUntil { session.status.value.banner == IdleOfflineBanner }
      session.onWifiLost()
      Thread.sleep(200)
      assertEquals(1, opens.get())
      val started = System.currentTimeMillis()
      session.noteActivity()
      waitUntil { opens.get() >= 2 }
      assertTrue(System.currentTimeMillis() - started < 400)
    } finally {
      session.close()
    }
  }

  @Test
  fun failedConnectStillRetriesWhenWifiHintIsFalse() {
    val store = pairedStore()
    val opens = AtomicInteger(0)
    val session = LanSession(store, TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      throw ConnectException("Connection refused")
    })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { opens.get() == 1 }
      session.onWifiLost()
      waitUntil(3_000) { opens.get() >= 2 }
      waitUntil { session.status.value.banner == WaitingForWifiBanner }
    } finally {
      session.close()
    }
  }

  @Test
  fun idleStopsRetryingAndATouchTriesAtOnce() {
    val store = pairedStore()
    val clock = SteppableClock()
    val opens = AtomicInteger(0)
    val session = LanSession(store, TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      throw ConnectException("Connection refused")
    }, clock)
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { opens.get() == 1 }
      // Two minutes with no touch, key or return to the foreground.
      clock.advanceMs(LanActiveWindowMs)
      waitUntil { session.status.value.banner == IdleOfflineBanner }
      // The ramp would have tried again within a second. Idle does not.
      Thread.sleep(1_500)
      assertEquals(1, opens.get())
      assertTrue(session.reconnectable)
      val started = System.currentTimeMillis()
      session.noteActivity()
      waitUntil { opens.get() >= 2 }
      assertTrue(System.currentTimeMillis() - started < 400)
      // Typing straight after does not start one attempt per key. The ramp's next try is at least 500 ms away.
      session.noteActivity()
      session.noteActivity()
      Thread.sleep(200)
      assertEquals(2, opens.get())
    } finally {
      session.close()
    }
  }

  @Test
  fun monitoringDemandSticksUntilAResynchronisedIdlePicture() {
    assertFalse(nextMonitoringDemand(false, false, false, false, false))
    assertTrue(nextMonitoringDemand(false, true, false, false, false))
    assertTrue(nextMonitoringDemand(false, false, true, false, false))
    assertTrue(nextMonitoringDemand(false, false, false, true, true))
    assertTrue(nextMonitoringDemand(true, false, false, false, false))
    assertFalse(nextMonitoringDemand(true, false, false, false, true))
  }

  @Test
  fun aRunningPlanRetriesAfterTwoMinutesWithoutATouch() {
    val store = pairedStore()
    val clock = SteppableClock()
    val opens = AtomicInteger(0)
    val links = java.util.Collections.synchronizedList(mutableListOf<ScriptedLink>())
    val session = LanSession(store, TlsConnector { _, _, _ ->
      ScriptedLink().also {
        links.add(it)
        opens.incrementAndGet()
      }
    }, clock)
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { links.isNotEmpty() && links[0].readEntries.get() > 0 }
      session.noteMonitoring(planRunning = true, turnRunning = false, screenHold = false, resynchronised = false)
      // Chrome cleared by the drop is not a resynchronised picture.
      session.noteMonitoring(planRunning = false, turnRunning = false, screenHold = false, resynchronised = false)
      clock.advanceMs(LanActiveWindowMs + 1)
      links[0].closeInput()
      waitUntil { opens.get() >= 2 }
      assertTrue(session.status.value.banner != IdleOfflineBanner)
    } finally {
      session.close()
    }
  }

  @Test
  fun screenOffHoldRetriesAfterTwoMinutesWithoutATouch() {
    val store = pairedStore()
    val clock = SteppableClock()
    val opens = AtomicInteger(0)
    val links = java.util.Collections.synchronizedList(mutableListOf<ScriptedLink>())
    val session = LanSession(store, TlsConnector { _, _, _ ->
      ScriptedLink().also {
        links.add(it)
        opens.incrementAndGet()
      }
    }, clock)
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { links.isNotEmpty() && links[0].readEntries.get() > 0 }
      session.leaveForeground(screenOff = true, holdLink = true)
      assertTrue(session.holdingAcrossSleep)
      clock.advanceMs(LanActiveWindowMs + 1)
      links[0].closeInput()
      waitUntil { opens.get() >= 2 }
      assertTrue(session.holdingAcrossSleep)
      assertTrue(session.status.value.banner != IdleOfflineBanner)
    } finally {
      session.close()
    }
  }

  @Test
  fun demandedSessionRetriesWhenTheWifiHintIsDown() {
    val store = pairedStore()
    val clock = SteppableClock()
    val opens = AtomicInteger(0)
    lateinit var session: LanSession
    session = LanSession(store, TlsConnector { _, _, _ ->
      val count = opens.incrementAndGet()
      if (count == 1) {
        // Age the touch clock and report loss before the loop chooses to park.
        session.onWifiLost()
        clock.advanceMs(LanActiveWindowMs + 1)
        throw ConnectException("Connection refused")
      }
      ScriptedLink()
    }, clock)
    try {
      session.noteMonitoring(planRunning = false, turnRunning = true, screenHold = false, resynchronised = false)
      session.connect("10.0.0.8", 56122)
      waitUntil { opens.get() >= 2 }
      assertTrue(session.status.value.banner != IdleOfflineBanner)
    } finally {
      session.close()
    }
  }

  @Test
  fun resynchronisedIdleParksAgain() {
    val store = pairedStore()
    val clock = SteppableClock()
    val opens = AtomicInteger(0)
    lateinit var session: LanSession
    session = LanSession(store, TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      session.noteMonitoring(planRunning = false, turnRunning = false, screenHold = false, resynchronised = true)
      clock.advanceMs(LanActiveWindowMs)
      throw ConnectException("Connection refused")
    }, clock)
    try {
      session.noteMonitoring(planRunning = true, turnRunning = false, screenHold = false, resynchronised = false)
      session.connect("10.0.0.8", 56122)
      waitUntil { session.status.value.banner == IdleOfflineBanner }
      Thread.sleep(1_500)
      assertEquals(1, opens.get())
    } finally {
      session.close()
    }
  }

  @Test
  fun explicitDisconnectStaysDownWhileAPlanIsDemanded() {
    val store = pairedStore()
    val clock = SteppableClock()
    val opens = AtomicInteger(0)
    val session = LanSession(store, TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      ScriptedLink()
    }, clock)
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { opens.get() == 1 }
      session.noteMonitoring(planRunning = true, turnRunning = true, screenHold = true, resynchronised = false)
      session.disconnect()
      clock.advanceMs(LanActiveWindowMs + 1)
      Thread.sleep(1_500)
      assertEquals(1, opens.get())
      assertFalse(session.reconnectable)
    } finally {
      session.close()
    }
  }

  @Test
  fun monitoringDemandDoesNotOverrideBackground() {
    val store = pairedStore()
    val opens = AtomicInteger(0)
    val session = LanSession(store, TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      ScriptedLink()
    })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { opens.get() == 1 }
      session.noteMonitoring(planRunning = true, turnRunning = false, screenHold = false, resynchronised = false)
      session.leaveForeground()
      Thread.sleep(1_500)
      assertEquals(1, opens.get())
      session.enterForeground()
      waitUntil { opens.get() >= 2 }
    } finally {
      session.close()
    }
  }

  @Test
  fun aPausedOrUnarmedSessionIsNotReconnectable() {
    val store = pairedStore()
    val session = LanSession(store, TlsConnector { _, _, _ -> throw ConnectException("Connection refused") })
    try {
      assertFalse(session.reconnectable)
      session.connect("10.0.0.8", 56122)
      assertTrue(session.reconnectable)
      session.disconnect()
      assertFalse(session.reconnectable)
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
  fun screenOffDuringAPlanKeepsTheSocketAndOnStopStillSendsBye() {
    assertTrue(holdLinkAcrossScreenOff(planRunning = true, turnRunning = false, taskResumed = false))
    assertTrue(holdLinkAcrossScreenOff(planRunning = false, turnRunning = true, taskResumed = false))
    assertTrue(holdLinkAcrossScreenOff(planRunning = false, turnRunning = false, taskResumed = true))
    assertFalse(holdLinkAcrossScreenOff(planRunning = false, turnRunning = false, taskResumed = false))
    val store = pairedStore()
    val link = ScriptedLink()
    val session = LanSession(store, TlsConnector { _, _, _ -> link })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { link.frames().isNotEmpty() }
      val before = link.frames().size
      session.leaveForeground(screenOff = true, holdLink = true)
      Thread.sleep(300)
      assertTrue(session.holdingAcrossSleep)
      assertFalse(link.closed)
      assertEquals(before, link.frames().size)
      assertFalse(link.frames().any { frame -> envelope(frame).kind == MessageKind.Bye })
      session.leaveForeground()
      waitUntil { link.frames().any { frame -> envelope(frame).kind == MessageKind.Bye } }
      val bye = link.frames().map { envelope(it) }.last { it.kind == MessageKind.Bye }
      assertEquals(ByeBackground, decodeBye(bye.payloadJson)!!.reason)
      waitUntil { link.closed }
      assertFalse(session.holdingAcrossSleep)
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
  fun foregroundReturnDropsAForgottenWifiBindAndReconnects() {
    val store = pairedStore()
    val opens = AtomicInteger(0)
    val seen = AtomicReference<LanRoute?>(LanRoute("unset"))
    val session = LanSession(store, object : TlsConnector {
      override fun open(address: String, port: Int, fingerprint: String): TlsLink =
        open(address, port, fingerprint, null)

      override fun open(address: String, port: Int, fingerprint: String, route: LanRoute?): TlsLink {
        seen.set(route)
        if (route?.identity == "forgotten") throw LanRouteUnavailable()
        opens.incrementAndGet()
        return ScriptedLink()
      }
    })
    session.refreshLanRoute = { session.onWifiRouteLost(LanRoute("forgotten")) }
    try {
      session.onWifiRoute(LanRoute("forgotten"))
      session.connect("10.0.0.8", 56122)
      waitUntil { opens.get() >= 1 }
      assertNull(seen.get())
      assertFalse(session.status.value.banner.contains("no longer available"))
      session.leaveForeground()
      Thread.sleep(200)
      session.onWifiRoute(LanRoute("forgotten"))
      session.enterForeground()
      waitUntil { opens.get() >= 2 }
      assertNull(session.currentLanRoute())
      assertNull(seen.get())
      assertFalse(session.status.value.banner.contains("no longer available"))
    } finally {
      session.close()
    }
  }

  @Test
  fun screenReturnReconnectsAfterAStaleWifiLoss() {
    val store = pairedStore()
    val opens = AtomicInteger(0)
    val session = LanSession(store, TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      ScriptedLink()
    })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { opens.get() == 1 }
      session.onWifiLost()
      session.leaveForeground()
      Thread.sleep(200)
      session.enterForeground()
      waitUntil { opens.get() >= 2 }
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
  fun alreadyForegroundOnALiveLinkSendsNoResume() {
    val store = pairedStore()
    val link = ScriptedLink()
    val session = LanSession(store, TlsConnector { _, _, _ -> link })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { link.frames().isNotEmpty() }
      val before = link.frames().size
      assertFalse(session.enterForeground())
      session.requestLiveSync()
      Thread.sleep(200)
      assertEquals(before, link.frames().size)
      assertFalse(link.frames().any { frame -> envelope(frame).kind == MessageKind.Resume })
    } finally {
      session.close()
    }
  }

  @Test
  fun resumeFromRoomRefusesTheSameTripleWhileTheSocketIsLive() {
    val store = pairedStore()
    val link = ScriptedLink()
    val session = LanSession(store, TlsConnector { _, _, _ -> link })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { link.frames().isNotEmpty() }
      link.push(frameOf(encodeHelloOk("host-1", HelloOkMessage(
        "00112233445566778899aabbccddeeff", "LazAssistantMonitor", "", 0, "", "", ""
      ))))
      waitUntil { link.frames().any { frame -> envelope(frame).kind == MessageKind.Auth } }
      assertTrue(session.resumeFromRoom("conversation-1", "stream-9", 50L))
      waitUntil { link.frames().any { frame -> envelope(frame).kind == MessageKind.Resume } }
      val before = link.frames().size
      assertFalse(session.resumeFromRoom("conversation-1", "stream-9", 50L))
      Thread.sleep(200)
      assertEquals(before, link.frames().size)
      assertTrue(session.resumeFromRoom("conversation-1", "stream-9", 60L))
      waitUntil { link.frames().map { envelope(it) }.count { it.kind == MessageKind.Resume } >= 2 }
      assertTrue(session.resumeFromRoom("conversation-1", "stream-9", 40L))
      waitUntil { link.frames().map { envelope(it) }.count { it.kind == MessageKind.Resume } >= 3 }
      val cursors = link.frames().map { envelope(it) }.filter { it.kind == MessageKind.Resume }.map { decodeResume(it.payloadJson)!!.cursor }
      assertEquals(listOf(50L, 60L, 40L), cursors)
    } finally {
      session.close()
    }
  }

  @Test
  fun helloCollectorResumesAfterAuthAndKeepsTheRequestedConversation() = runBlocking {
    val store = pairedStore()
    val ledger = MemoryCommandLedger()
    ledger.remember(encodeEmpty(MessageKind.Stop, "stop-pending"))
    val link = ScriptedLink()
    val session = LanSession(store, TlsConnector { _, _, _ -> link }, ledger = ledger)
    val collector = launch(Dispatchers.Unconfined) {
      session.messages.collect { message ->
        if (message.kind == MessageKind.HelloOk) {
          session.resumeFromRoom("conversation-selected", "stream-selected", 42L)
        }
      }
    }
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { link.frames().isNotEmpty() }
      link.push(frameOf(encodeHelloOk("host-hello", HelloOkMessage(
        "00112233445566778899aabbccddeeff", "LazAssistantMonitor", "", 0, "", "", ""
      ))))
      waitUntil { link.frames().any { envelope(it).kind == MessageKind.Resume } }
      val sent = link.frames().map { envelope(it) }
      assertTrue(sent.indexOfFirst { it.kind == MessageKind.Auth } in 0 until
        sent.indexOfFirst { it.kind == MessageKind.Resume })
      val payload = sent.single { it.kind == MessageKind.Resume }.payloadJson
      assertTrue(payload.contains("conversation-selected"))
      assertTrue(payload.contains("stream-selected"))
      assertTrue(payload.contains("stop-pending"))
      assertEquals(42L, computing.michell.monitor.protocol.decodeResume(payload)!!.cursor)
    } finally {
      collector.cancel()
      session.close()
    }
  }

  @Test
  fun unknownCommandIsResentAndAHeldPromptIsOffered() {
    val store = pairedStore()
    val pin = store.load().fingerprint
    val ledger = MemoryCommandLedger()
    val send = tryEncodeSend("send-1", "keep this")
    val stop = encodeEmpty(MessageKind.Stop, "stop-1")
    runBlocking {
      ledger.remember(send.json)
      ledger.remember(stop)
      ledger.applyHost(listOf(HostCommandState("send-1", OutboxQueued, "")))
    }
    val link = ScriptedLink()
    val session = LanSession(store, TlsConnector { _, _, fingerprint ->
      assertEquals(pin, fingerprint)
      link
    }, ledger = ledger)
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { link.frames().isNotEmpty() }
      link.push(frameOf(encodeHelloOk("host-1", HelloOkMessage(
        "00112233445566778899aabbccddeeff", "LazAssistantMonitor", "", 0, "", "", ""
      ))))
      waitUntil { link.frames().any { frame -> envelope(frame).kind == MessageKind.Auth } }
      // The screen asks the session to resume. Open commands are attached on the way out.
      assertTrue(session.resumeFromRoom("conversation-1", "stream-1", 0L))
      waitUntil { link.frames().any { frame -> envelope(frame).kind == MessageKind.Resume } }
      val resume = link.frames().map { envelope(it) }.last { it.kind == MessageKind.Resume }
      assertTrue(resume.payloadJson.contains("send-1"))
      assertTrue(resume.payloadJson.contains("stop-1"))
      link.push(frameOf(encodeCommandStates("h1", listOf(
        CommandStateMessage("send-1", "unknown", ""),
        CommandStateMessage("stop-1", "unknown", "")
      ))))
      waitUntil { link.frames().any { frame -> envelope(frame).kind == MessageKind.Stop } }
      assertFalse(link.frames().any { frame -> envelope(frame).kind == MessageKind.Send })
      waitUntil { session.undeliveredPrompt.value == "keep this" }
      assertEquals(pin, store.load().fingerprint)
    } finally {
      session.close()
    }
  }

  @Test
  fun commandStateSurvivesADispatcherHopAndCloseClearsTheWriter() {
    val store = pairedStore()
    val inner = MemoryCommandLedger()
    val hopper = Executors.newSingleThreadExecutor()
    val dispatcher = hopper.asCoroutineDispatcher()
    val migrated = AtomicBoolean(false)
    val inside = CountDownLatch(1)
    val release = CountDownLatch(1)
    val ledger = object : CommandLedger {
      override fun openIds(): List<String> = inner.openIds()
      override suspend fun remember(json: String) = inner.remember(json)
      override suspend fun applyHost(states: List<HostCommandState>): ReplayPlan {
        val caller = Thread.currentThread()
        withContext(dispatcher) {
          if (Thread.currentThread() != caller) migrated.set(true)
          inside.countDown()
          assertTrue(release.await(2, TimeUnit.SECONDS))
        }
        return inner.applyHost(states)
      }
    }
    val stop = encodeEmpty(MessageKind.Stop, "stop-1")
    runBlocking { inner.remember(stop) }
    val link = ScriptedLink()
    val session = LanSession(store, TlsConnector { _, _, _ -> link }, ledger = ledger)
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { link.frames().isNotEmpty() }
      link.push(frameOf(encodeCommandStates("h1", listOf(CommandStateMessage("stop-1", "unknown", "")))))
      assertTrue(inside.await(2, TimeUnit.SECONDS))
      session.sendCatalogue(encodeEmpty(MessageKind.Ping, "ping-during-hop"))
      release.countDown()
      waitUntil { link.frames().any { frame -> envelope(frame).kind == MessageKind.Stop } }
      waitUntil { link.frames().any { frame -> envelope(frame).kind == MessageKind.Ping } }
      assertTrue(migrated.get())
      assertFalse(link.overlapped)
      assertFalse(link.closed)
      val written = link.frames().size
      session.close()
      session.sendCatalogue(encodeEmpty(MessageKind.Stop, "after-close"))
      Thread.sleep(200)
      assertEquals(written, link.frames().size)
      assertTrue(link.closed)
    } finally {
      release.countDown()
      session.close()
      dispatcher.close()
      hopper.shutdown()
    }
  }

  @Test
  fun childFailureClosesTheSocketAndRetries() {
    val store = pairedStore()
    val opens = AtomicInteger(0)
    val links = java.util.Collections.synchronizedList(mutableListOf<ScriptedLink>())
    val session = LanSession(store, TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      ScriptedLink().also { links.add(it) }
    })
    try {
      session.frameProbe = { throw IllegalStateException("decoder") }
      session.connect("10.0.0.8", 56122)
      waitUntil { links.isNotEmpty() && links[0].readEntries.get() > 0 }
      links[0].push(frameOf(encodeTicks(MessageKind.Ping, "probe", 1)))
      waitUntil { opens.get() >= 2 && links[0].closed }
      assertTrue(session.reconnectable)
      assertFalse(session.reconnectPaused)
      val status = session.status.value
      assertTrue(status.phase != LinkPhase.Disconnected || status.banner == ReconnectingBanner ||
        status.banner == ConnectionRefusedBanner || status.banner == HostClosedBanner)
    } finally {
      session.close()
    }
  }

  @Test
  fun ledgerFailureClosesTheSocketAndRetries() {
    val store = pairedStore()
    val opens = AtomicInteger(0)
    val links = java.util.Collections.synchronizedList(mutableListOf<ScriptedLink>())
    val session = LanSession(store, TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      ScriptedLink().also { links.add(it) }
    }, ledger = object : CommandLedger {
      override fun openIds(): List<String> = emptyList()
      override suspend fun remember(json: String) {}
      override suspend fun applyHost(states: List<HostCommandState>): ReplayPlan {
        throw IllegalStateException("ledger")
      }
    })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { links.isNotEmpty() && links[0].readEntries.get() > 0 }
      links[0].push(frameOf(encodeCommandStates("h1", listOf(CommandStateMessage("stop-1", "unknown", "")))))
      waitUntil { links[0].closed && opens.get() >= 2 }
      assertTrue(session.reconnectable)
      assertFalse(session.reconnectPaused)
    } finally {
      session.close()
    }
  }

  @Test
  fun applierFailureClosesTheSocketAndRetries() {
    val store = pairedStore()
    val opens = AtomicInteger(0)
    val link = ScriptedLink()
    val session = LanSession(store, TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      link
    })
    session.attachLinkApplier(object : LinkApplier {
      override suspend fun offer(event: computing.michell.monitor.protocol.MonitorEvent, generation: Int) {}
      override suspend fun offerFrame(frame: computing.michell.monitor.protocol.SyncFrame, generation: Int) {
        throw IllegalStateException("applier")
      }
      override suspend fun noteRefused(event: computing.michell.monitor.protocol.MonitorEvent, generation: Int) {}
    })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { link.readEntries.get() > 0 }
      link.push(frameOf(
        """{"v":3,"type":"resume_ok","payload":{"conversation_id":"c","stream_id":"s","from_seq":1}}"""
      ))
      waitUntil { link.closed }
      assertTrue(session.reconnectable)
      assertFalse(session.reconnectPaused)
      val status = session.status.value
      assertTrue(status.phase == LinkPhase.Connecting || status.banner == ReconnectingBanner ||
        status.banner == ConnectionRefusedBanner || status.banner == HostClosedBanner)
    } finally {
      session.close()
    }
  }

  @Test
  fun reconnectDoesNotWaitForAStuckOpenAndCancelClosesTheSocket() {
    val store = pairedStore()
    val opens = AtomicInteger(0)
    val closes = AtomicInteger(0)
    val release = CountDownLatch(1)
    val entered = CountDownLatch(1)
    val session = LanSession(store, TlsConnector { _, _, _ ->
      val count = opens.incrementAndGet()
      if (count == 1) {
        entered.countDown()
        assertTrue(release.await(5, TimeUnit.SECONDS))
      }
      val inner = ScriptedLink()
      val once = AtomicBoolean(false)
      object : TlsLink {
        override val input: InputStream get() = inner.input
        override val output: OutputStream get() = inner.output
        override fun close() {
          if (once.compareAndSet(false, true)) closes.incrementAndGet()
          inner.close()
        }
      }
    })
    try {
      session.connect("10.0.0.8", 56122)
      assertTrue(entered.await(2, TimeUnit.SECONDS))
      session.connect("10.0.0.8", 56122)
      waitUntil(4_000) { opens.get() >= 2 }
      release.countDown()
      waitUntil { closes.get() >= 1 }
      repeat(4) {
        session.disconnect()
        session.connect("10.0.0.8", 56122)
        waitUntil { opens.get() >= closes.get() + 1 }
        session.disconnect()
        waitUntil { closes.get() == opens.get() }
      }
      assertEquals(opens.get(), closes.get())
    } finally {
      release.countDown()
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
  fun firstPairUsesPresentedCertificateAndPinsOnlyAfterSuccess() {
    val store = HostStore(MemoryStringMap())
    val presented = "ab".repeat(32)
    val link = ScriptedLink(peerFingerprint = presented)
    val session = LanSession(store, TlsConnector { _, _, fingerprint ->
      assertEquals("", fingerprint)
      link
    })
    try {
      session.connect("10.0.0.8", 56122, "123456")
      waitUntil { link.frames().size >= 2 }
      val pair = decodePair(envelope(link.frames()[1]).payloadJson)!!
      assertEquals("123456", pair.code)
      assertEquals(presented, pair.fingerprint)
      assertEquals("", store.load().fingerprint)
      link.push(frameOf(computing.michell.monitor.protocol.encodePairOk("paired", "client-1", "token-1")))
      waitUntil { store.load().paired && store.load().fingerprint == presented }
      assertEquals("token-1", store.load().sessionToken)
    } finally {
      session.close()
    }
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
      assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.Mode, "snap-1")))
      assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.ApprovalRequested, "approval")))
      assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.Status, "status-2")))
      assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.Mode, "snap-2")))
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
  fun aPlanFrameIsDeliveredBeforeQueuedPages() = runBlocking {
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
      assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.SnapshotPage, "page")))
      assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.ImageData, "image")))
      assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.Plan, "plan")))
      assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.Status, "status")))
      hold.complete(Unit)
      withTimeout(5_000) {
        while (received.size < 5) yield()
      }
      assertEquals(listOf("held", "plan", "page", "image", "status"), received.toList())
    } finally {
      hold.complete(Unit)
      collector.cancel()
    }
  }

  @Test
  fun unicodeBytesAndAnEssentialFrameStayWithinTheBudget() = runBlocking {
    val accented = "é"
    assertEquals(1, accented.length)
    assertEquals(2, computing.michell.monitor.protocol.utf8Length(accented))
    val delivery = InboundDelivery(SteppableClock(), byteBudget = 3)
    assertEquals(DeliveryResult.Dropped, delivery.publish(inboundMessage(MessageKind.Error, "wide", accented + accented)))
    assertEquals(0L, delivery.queuedBytes())
    assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.Error, "bulk", "{}")))
    assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.HelloOk, "hello", "{}")))
    assertEquals(2L, delivery.queuedBytes())
    val received = mutableListOf<String>()
    val collector = launch { delivery.messages.collect { received += it.id } }
    try {
      withTimeout(2_000) { while (received.isEmpty()) yield() }
      assertEquals(listOf("hello"), received.toList())
    } finally {
      collector.cancel()
    }
  }

  @Test
  fun aCoalescedReplacementDoesNotGrowPastTheBudget() = runBlocking {
    val delivery = InboundDelivery(SteppableClock(), byteBudget = 8)
    assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.Status, "small", "{}")))
    assertEquals(DeliveryResult.Dropped, delivery.publish(inboundMessage(MessageKind.Status, "wide", "ééééé")))
    assertEquals(2L, delivery.queuedBytes())
    val received = mutableListOf<String>()
    val collector = launch { delivery.messages.collect { received += it.id } }
    try {
      withTimeout(2_000) { while (received.isEmpty()) yield() }
      assertEquals(listOf("small"), received.toList())
    } finally {
      collector.cancel()
    }
  }

  @Test
  fun aFullCreditWindowFailsWithoutWaiting() = runBlocking {
    val delivery = InboundDelivery(SteppableClock(), byteBudget = 3)
    assertEquals(DeliveryResult.Queued, delivery.publish(inboundMessage(MessageKind.Error, "held")))
    assertEquals(DeliveryResult.Dropped, delivery.publish(inboundMessage(MessageKind.Error, "overflow")))
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
  fun aWriteThatWaitsForAReadStillAnswersPing() {
    val readAttempted = AtomicBoolean(false)
    val ping = frameOf(encodeTicks(MessageKind.Ping, "host-ping", 42))
    val inbound = ArrayDeque<Byte>()
    for (byte in ping) inbound.addLast(byte)
    val written = mutableListOf<ByteArray>()
    val link = object : TlsLink {
      override val peerFingerprint = ""
      override val input = object : InputStream() {
        override fun read(): Int {
          val buffer = ByteArray(1)
          val count = read(buffer, 0, 1)
          if (count <= 0) return -1
          return buffer[0].toInt() and 0xFF
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
          readAttempted.set(true)
          synchronized(inbound) {
            if (inbound.isEmpty()) return 0
            var count = 0
            while (count < length && inbound.isNotEmpty()) {
              buffer[offset + count] = inbound.removeFirst()
              count += 1
            }
            return count
          }
        }
      }
      override val output = object : OutputStream() {
        override fun write(value: Int) {
          write(byteArrayOf(value.toByte()))
        }

        override fun write(buffer: ByteArray, offset: Int, length: Int) {
          val start = System.currentTimeMillis()
          while (!readAttempted.get()) {
            if (System.currentTimeMillis() - start > 2_000) throw IOException("read was not attempted")
            Thread.sleep(1)
          }
          synchronized(written) { written += buffer.copyOfRange(offset, offset + length) }
        }
      }
      override fun close() {}
    }
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ -> link })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil {
        synchronized(written) {
          written.any { bytes -> String(bytes, Charsets.ISO_8859_1).contains("pong") }
        }
      }
      assertTrue(readAttempted.get())
    } finally {
      session.close()
    }
  }

  @Test
  fun aWriteThatOutlivesTheDeadSessionClosesTheSocket() {
    val clock = SteppableClock()
    val writeEntered = CountDownLatch(1)
    val link = object : TlsLink {
      @Volatile var closed = false
      override val peerFingerprint = ""
      override val input = object : InputStream() {
        override fun read(): Int = 0
        override fun read(buffer: ByteArray, offset: Int, length: Int): Int = 0
      }
      override val output = object : OutputStream() {
        override fun write(value: Int) {
          write(byteArrayOf(value.toByte()))
        }

        override fun write(buffer: ByteArray, offset: Int, length: Int) {
          writeEntered.countDown()
          while (!closed) Thread.sleep(5)
          throw IOException("closed during write")
        }
      }
      override fun close() {
        closed = true
      }
    }
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ -> link }, clock)
    try {
      session.connect("10.0.0.8", 56122)
      assertTrue(writeEntered.await(2, TimeUnit.SECONDS))
      clock.advanceMs(MonitorLimits.DeadSessionMs)
      waitUntil(2_000) { link.closed }
      assertTrue(link.closed)
    } finally {
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
  fun userActionRejectKeepsCredentialsAndDoesNotRetry() {
    for (reason in listOf("revoked", "disabled", "fingerprint", "pair_code")) {
      val store = pairedStore()
      val original = store.load()
      val link = ScriptedLink()
      val opens = AtomicInteger()
      val session = LanSession(store, TlsConnector { _, _, _ -> opens.incrementAndGet(); link })
      try {
        session.connect("10.0.0.8", 56122)
        waitUntil { link.frames().isNotEmpty() }
        link.push(frameOf(encodeRejected("host-rejected", reason, 1, 1)))
        waitUntil(2_000) { link.closed && session.status.value.phase == LinkPhase.Paused }
        Thread.sleep(300)
        assertEquals(original, store.load())
        assertEquals(reason, session.status.value.lastError)
        assertEquals(1, opens.get())
        assertTrue(session.reconnectPaused)
        assertFalse(link.frames().any { envelope(it).kind == MessageKind.Pair })
      } finally {
        session.close()
      }
    }
  }

  @Test
  fun pairedTransientRejectRetriesWithoutResumeOrANewProcess() {
    for (reason in listOf("auth", "expired", "protocol")) {
      assertTransientRejectRetries(reason, frameOf(encodeRejected("host-rejected", reason, 1, 1)))
    }
    // A truncated close has no reason. It must not be stored as an authentication failure.
    val truncated = """{"v":3,"id":"host-truncated","type":"rejected","payload":{"host_version":1,"client_version":1}}"""
    assertTransientRejectRetries("", frameOf(truncated))
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
  fun partialFrameIgnoresAWallStepAndExpiresOnTheMonotonicClock() {
    val clock = SteppableClock()
    val link = ScriptedLink()
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ -> link }, clock)
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { link.readEntries.get() > 0 }
      // A stamp of 0 is ambiguous with "no partial". Start after that sentinel.
      clock.advanceMs(1_000L)
      clock.advanceWallMs(1_000_000L)
      val seen = link.readEntries.get()
      link.push(byteArrayOf(0x4C, 0x41, 0x4D, 0x31))
      waitUntil { link.readEntries.get() > seen }
      Thread.sleep(100)
      clock.advanceWallMs(-120_000L)
      clock.advanceWallMs(MonitorLimits.PartialFrameMs + 240_000L)
      Thread.sleep(200)
      assertFalse(link.closed)
      clock.advanceMs(MonitorLimits.PartialFrameMs)
      waitUntil(2_000) { link.closed && session.status.value.banner == ReconnectingBanner }
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

  @Test
  fun aResumeIsNotRememberedUntilTheWriterAcceptsIt() {
    val link = ScriptedLink()
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ -> link })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { link.readEntries.get() > 0 }
      session.resumeQueued = { false }
      assertFalse(session.resumeFromRoom("c1", "stream-a", 4L))
      Thread.sleep(150)
      assertFalse(link.frames().any { frame -> envelope(frame).kind == MessageKind.Resume })
      session.resumeQueued = null
      assertTrue(session.resumeFromRoom("c1", "stream-a", 4L))
      waitUntil { link.frames().any { frame -> envelope(frame).kind == MessageKind.Resume } }
      assertFalse(session.resumeFromRoom("c1", "stream-a", 4L))
    } finally {
      session.resumeQueued = null
      session.close()
    }
  }

  @Test
  fun pongsDoNotBlockForcedRecovery() {
    val opens = AtomicInteger(0)
    val links = java.util.Collections.synchronizedList(mutableListOf<ScriptedLink>())
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      ScriptedLink().also { links.add(it) }
    })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { links.isNotEmpty() && links[0].readEntries.get() > 0 }
      links[0].push(frameOf(encodeHelloOk("host-1", HelloOkMessage(
        "00112233445566778899aabbccddeeff", "LazAssistantMonitor", "", 0, "", "", ""
      ))))
      waitUntil { links[0].frames().any { frame -> envelope(frame).kind == MessageKind.Auth } }
      links[0].push(frameOf(eventJson(1L, "Live")))
      waitUntil { session.status.value.phase == LinkPhase.Live }
      val seen = links[0].readEntries.get()
      links[0].push(frameOf(encodeTicks(MessageKind.Pong, "host-pong", 1)))
      waitUntil { links[0].readEntries.get() > seen }
      assertTrue(session.framesArriving())
      session.reconnect()
      Thread.sleep(250)
      assertEquals(1, opens.get())
      session.forceReconnect()
      waitUntil(8_000) { opens.get() >= 2 && links[1].readEntries.get() > 0 }
      assertTrue(session.resumeFromRoom("c1", "stream-a", 4L))
      waitUntil { links[1].frames().any { frame -> envelope(frame).kind == MessageKind.Resume } }
      val payload = links[1].frames().map { envelope(it) }.last { it.kind == MessageKind.Resume }.payloadJson
      assertEquals(4L, decodeResume(payload)!!.cursor)
    } finally {
      session.close()
    }
  }

  @Test
  fun aCreditPauseDoesNotCloseOnHeartbeatSilence() {
    val small = eventJson(1L, "A")
    val second = eventJson(2L, "B")
    val opens = AtomicInteger(0)
    val links = java.util.Collections.synchronizedList(mutableListOf<ScriptedLink>())
    val clock = SteppableClock()
    val seen = AtomicInteger(0)
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      ScriptedLink().also { links.add(it) }
    }, clock = clock, eventBudget = small.length + 20L)
    session.frameProbe = { seen.incrementAndGet() }
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { links.isNotEmpty() && links[0].readEntries.get() > 0 }
      links[0].push(frameOf(small))
      links[0].push(frameOf(second))
      waitUntil { seen.get() >= 2 }
      clock.advanceMs(MonitorLimits.DeadSessionMs)
      Thread.sleep(200)
      assertFalse(links[0].closed)
      assertEquals(1, opens.get())
    } finally {
      session.close()
    }
  }

  @Test
  fun anOversizedEventIsRefusedWithoutReplacingTheSocket() {
    val huge = eventJson(9L, "x".repeat(400))
    val opens = AtomicInteger(0)
    val links = java.util.Collections.synchronizedList(mutableListOf<ScriptedLink>())
    val refused = CountDownLatch(1)
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      ScriptedLink().also { links.add(it) }
    }, eventBudget = 80L)
    session.attachLinkApplier(object : LinkApplier {
      override suspend fun offer(event: computing.michell.monitor.protocol.MonitorEvent, generation: Int) {}
      override suspend fun offerFrame(frame: computing.michell.monitor.protocol.SyncFrame, generation: Int) {}
      override suspend fun noteRefused(event: computing.michell.monitor.protocol.MonitorEvent, generation: Int) {
        if (event.seq == 9L) refused.countDown()
      }
    })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { links.isNotEmpty() && links[0].readEntries.get() > 0 }
      links[0].push(frameOf(huge))
      assertTrue(refused.await(3, TimeUnit.SECONDS))
      Thread.sleep(200)
      assertEquals(1, opens.get())
      assertFalse(links[0].closed)
    } finally {
      session.close()
    }
  }

  @Test
  fun aCommandAcceptedOnOneGenerationIsStaleOnTheNext() {
    val socket = Any()
    val accepted = beginCatalogue("""{"v":3,"id":"stop-1","type":"stop","payload":{}}""", 1, socket)
    val moved = stepCatalogue(accepted, 2, socket)
    assertTrue(moved is CatalogueStep.Done)
    assertEquals(CatalogueWrite.Stale, (moved as CatalogueStep.Done).result.outcome)
    val replaced = stepCatalogue(accepted, 1, Any())
    assertTrue(replaced is CatalogueStep.Done)
    assertEquals(CatalogueWrite.Stale, (replaced as CatalogueStep.Done).result.outcome)
    assertTrue(stepCatalogue(accepted, 1, socket) is CatalogueStep.Write)
  }

  @Test
  fun automaticReconnectUsesANewGeneration() {
    val opens = AtomicInteger(0)
    val links = java.util.Collections.synchronizedList(mutableListOf<ScriptedLink>())
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      ScriptedLink().also { links.add(it) }
    })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { links.isNotEmpty() && links[0].readEntries.get() > 0 }
      val first = session.linkEpoch
      assertTrue(first > 0)
      links[0].closeInput()
      session.onWifiAvailable()
      waitUntil(8_000) { opens.get() >= 2 && session.linkEpoch > first }
      assertTrue(session.reconnectable)
      assertFalse(session.reconnectPaused)
      assertTrue(links[0].closed)
    } finally {
      session.close()
    }
  }

  @Test
  fun aPartialChunkDoesNotCompleteOnTheNextSocket() {
    val opens = AtomicInteger(0)
    val links = java.util.Collections.synchronizedList(mutableListOf<ScriptedLink>())
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      ScriptedLink().also { links.add(it) }
    })
    val seen = java.util.Collections.synchronizedList(mutableListOf<String>())
    val collector = CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
      session.messages.collect { seen += it.id }
    }
    val ping = encodeTicks(MessageKind.Ping, "assembled-ping", 7)
    val cut = ping.length / 2
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { links.isNotEmpty() && links[0].readEntries.get() > 0 }
      val before = links[0].readEntries.get()
      links[0].push(frameOf(chunkJson("item-1", 1, 2, ping.substring(0, cut))))
      waitUntil { links[0].readEntries.get() > before }
      links[0].closeInput()
      session.onWifiAvailable()
      waitUntil(8_000) { opens.get() >= 2 && links[1].readEntries.get() > 0 }
      links[1].push(frameOf(chunkJson("item-1", 2, 2, ping.substring(cut))))
      val after = links[1].readEntries.get()
      links[1].push(frameOf(encodeTicks(MessageKind.Pong, "live-pong", 1)))
      waitUntil { links[1].readEntries.get() > after }
      waitUntil { seen.contains("live-pong") }
      assertFalse(seen.contains("assembled-ping"))
    } finally {
      collector.cancel()
      session.close()
    }
  }

  @Test
  fun queuedWorkDoesNotReachTheNextSocket() {
    val opens = AtomicInteger(0)
    val links = java.util.Collections.synchronizedList(mutableListOf<ScriptedLink>())
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      ScriptedLink().also { links.add(it) }
    })
    val entered = CountDownLatch(1)
    val release = CountDownLatch(1)
    val seen = java.util.Collections.synchronizedList(mutableListOf<Pair<Int, Long>>())
    session.attachLinkApplier(object : LinkApplier {
      override suspend fun offer(event: computing.michell.monitor.protocol.MonitorEvent, generation: Int) {
        seen += generation to event.seq
        if (event.seq == 1L) {
          entered.countDown()
          assertTrue(release.await(3, TimeUnit.SECONDS))
        }
      }
      override suspend fun offerFrame(frame: computing.michell.monitor.protocol.SyncFrame, generation: Int) {}
      override suspend fun noteRefused(event: computing.michell.monitor.protocol.MonitorEvent, generation: Int) {}
    })
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { links.isNotEmpty() && links[0].readEntries.get() > 0 }
      val first = session.linkEpoch
      links[0].push(frameOf(eventJson(1L, "Held")))
      assertTrue(entered.await(2, TimeUnit.SECONDS))
      val queued = links[0].readEntries.get()
      links[0].push(frameOf(eventJson(2L, "Queued")))
      waitUntil { links[0].readEntries.get() > queued }
      links[0].closeInput()
      Thread.sleep(250)
      assertEquals(1, opens.get())
      release.countDown()
      session.onWifiAvailable()
      waitUntil(8_000) { opens.get() >= 2 && session.linkEpoch > first && links[1].readEntries.get() > 0 }
      links[1].push(frameOf(eventJson(3L, "New")))
      waitUntil { synchronized(seen) { seen.any { it.second == 3L } } }
      assertTrue(synchronized(seen) { seen.none { it.second == 2L } })
      assertTrue(synchronized(seen) { seen.none { it.second == 1L && it.first == session.linkEpoch } })
      assertTrue(synchronized(seen) { seen.any { it.second == 3L && it.first == session.linkEpoch } })
    } finally {
      release.countDown()
      session.close()
    }
  }

  @Test
  fun aPartialBaselineIsNotCommittedAfterAutomaticReconnect() {
    val opens = AtomicInteger(0)
    val links = java.util.Collections.synchronizedList(mutableListOf<ScriptedLink>())
    val commits = AtomicInteger(0)
    val ready = AtomicInteger(0)
    val store = object : computing.michell.monitor.data.SyncStore {
      override suspend fun apply(
        hostId: String,
        events: List<computing.michell.monitor.protocol.MonitorEvent>,
        nowMs: Long
      ): computing.michell.monitor.data.SyncApplyResult {
        return computing.michell.monitor.data.SyncApplyResult(emptyList(), emptyList(), emptyList())
      }

      override suspend fun commitBaseline(
        hostId: String,
        commit: computing.michell.monitor.data.BaselineCommit,
        nowMs: Long
      ): computing.michell.monitor.data.BaselinePlan? {
        commits.incrementAndGet()
        return null
      }
    }
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      ScriptedLink().also { links.add(it) }
    })
    session.attachApplier(computing.michell.monitor.data.SyncApplier("host-1", store, { 0L }, {
      if (it == computing.michell.monitor.data.SyncEffect.CacheReady) ready.incrementAndGet()
    }))
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { links.isNotEmpty() && links[0].readEntries.get() > 0 }
      val first = session.linkEpoch
      val before = ready.get()
      links[0].push(frameOf(snapshotBeginJson("c1", "s1", "Old")))
      waitUntil { ready.get() > before }
      links[0].closeInput()
      session.onWifiAvailable()
      waitUntil(8_000) { opens.get() >= 2 && session.linkEpoch > first && links[1].readEntries.get() > 0 }
      val after = ready.get()
      links[1].push(frameOf(snapshotEndJson("c1", "s1")))
      waitUntil { ready.get() > after }
      assertEquals(0, commits.get())
      val again = ready.get()
      links[1].push(frameOf(snapshotBeginJson("c2", "s2", "New")))
      links[1].push(frameOf(snapshotEndJson("c2", "s2")))
      waitUntil { commits.get() == 1 || ready.get() > again + 1 }
      assertEquals(1, commits.get())
    } finally {
      session.close()
    }
  }

  @Test
  fun aDelayedCommandResultIsNotWrittenOnTheNextSocket() {
    val opens = AtomicInteger(0)
    val links = java.util.Collections.synchronizedList(mutableListOf<ScriptedLink>())
    val entered = CountDownLatch(1)
    val release = CountDownLatch(1)
    val ledger = object : CommandLedger {
      private val inner = MemoryCommandLedger()
      override fun openIds(): List<String> = inner.openIds()
      override suspend fun remember(json: String) {
        entered.countDown()
        assertTrue(release.await(3, TimeUnit.SECONDS))
        inner.remember(json)
      }
      override suspend fun noteWritten(commandId: String) = inner.noteWritten(commandId)
      override suspend fun applyHost(states: List<HostCommandState>): ReplayPlan = inner.applyHost(states)
    }
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      ScriptedLink().also { links.add(it) }
    }, ledger = ledger)
    val results = java.util.Collections.synchronizedList(mutableListOf<CatalogueResult>())
    val collector = CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
      session.commandResults.collect { results += it }
    }
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { links.isNotEmpty() && links[0].readEntries.get() > 0 }
      val first = session.linkEpoch
      session.sendCatalogue(encodeEmpty(MessageKind.Stop, "stop-late"))
      assertTrue(entered.await(2, TimeUnit.SECONDS))
      links[0].closeInput()
      session.onWifiAvailable()
      waitUntil(8_000) { opens.get() >= 2 && session.linkEpoch > first }
      release.countDown()
      waitUntil { results.isNotEmpty() }
      assertEquals(CatalogueWrite.Stale, results.single().outcome)
      assertEquals(first, results.single().linkEpoch)
      assertFalse(links[1].frames().any { frame -> envelope(frame).kind == MessageKind.Stop })
    } finally {
      release.countDown()
      collector.cancel()
      session.close()
    }
  }

  @Test
  fun anAcceptedCommandIsNotReplayedOnTheNextSocket() {
    val opens = AtomicInteger(0)
    val links = java.util.Collections.synchronizedList(mutableListOf<ScriptedLink>())
    val inner = MemoryCommandLedger()
    val accepted = CountDownLatch(1)
    val ledger = object : CommandLedger {
      override fun openIds(): List<String> = inner.openIds()
      override suspend fun remember(json: String) = inner.remember(json)
      override suspend fun noteWritten(commandId: String) = inner.noteWritten(commandId)
      override suspend fun applyHost(states: List<HostCommandState>): ReplayPlan {
        val plan = inner.applyHost(states)
        if (states.any { it.ref == "stop-kept" && it.state == OutboxAccepted }) accepted.countDown()
        return plan
      }
    }
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      ScriptedLink().also { links.add(it) }
    }, ledger = ledger)
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { links.isNotEmpty() && links[0].readEntries.get() > 0 }
      session.sendCatalogue(encodeEmpty(MessageKind.Stop, "stop-kept"))
      waitUntil { links[0].frames().any { frame -> envelope(frame).kind == MessageKind.Stop } }
      links[0].push(frameOf(encodeCommandStates("h1", listOf(CommandStateMessage("stop-kept", "accepted", "")))))
      assertTrue(accepted.await(2, TimeUnit.SECONDS))
      val first = session.linkEpoch
      links[0].closeInput()
      session.onWifiAvailable()
      waitUntil(8_000) { opens.get() >= 2 && session.linkEpoch > first && links[1].readEntries.get() > 0 }
      assertTrue(session.resumeFromRoom("c1", "s1", 0L))
      waitUntil { links[1].frames().any { frame -> envelope(frame).kind == MessageKind.Resume } }
      assertFalse(links[1].frames().any { frame -> envelope(frame).kind == MessageKind.Stop })
      val resume = links[1].frames().map { envelope(it) }.last { it.kind == MessageKind.Resume }
      assertTrue(resume.payloadJson.contains("stop-kept"))
      assertTrue(ledger.openIds().contains("stop-kept"))
    } finally {
      session.close()
    }
  }

  @Test
  fun recoverablePauseRestartsOnReturnTouchAndReconnect() {
    val frame = frameOf(
      """{"v":3,"id":"host-later","type":"rejected","payload":{"reason":"later","host_version":1,"client_version":1}}"""
    )
    assertRecoverablePauseRetries(frame) { session -> session.enterForeground() }
    assertRecoverablePauseRetries(frame) { session -> session.noteActivity() }
    assertRecoverablePauseRetries(frame) { session -> assertTrue(session.restartTransient()) }
    // An unpaired auth reject is the transient pause item 2.1 still keeps.
    val unpaired = HostStore(MemoryStringMap())
    unpaired.save(HostRecord("10.0.0.8", 56122, "ab".repeat(32), "", ""))
    assertRecoverablePauseRetries(frameOf(encodeRejected("host-auth", "auth", 1, 1)), unpaired) { session ->
      session.enterForeground()
    }
  }

  @Test
  fun disconnectAndRevocationIgnoreReturnTouchAndReconnect() {
    val actions = listOf<(LanSession) -> Unit>(
      { session -> session.enterForeground() },
      { session -> session.noteActivity() },
      { session -> assertFalse(session.restartTransient()) }
    )
    for (action in actions) {
      assertStopIgnores(action, disconnect = true)
      assertStopIgnores(action, disconnect = false)
    }
  }

  @Test
  fun restartTransientRefusesPinAndRevocationWithoutClearingPairing() {
    val store = pairedStore()
    val opens = AtomicInteger(0)
    val pinned = LanSession(store, TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      throw PinMismatchException("aa")
    })
    try {
      pinned.connect("10.0.0.8", 56122)
      waitUntil { pinned.status.value.banner == "TLS pin mismatch." }
      assertFalse(pinned.restartTransient())
      pinned.forceReconnect()
      Thread.sleep(300)
      assertEquals(1, opens.get())
      assertEquals("client-1", store.load().clientId)
      assertEquals("token-1", store.load().sessionToken)
    } finally {
      pinned.close()
    }
    for (reason in listOf("revoked")) {
      val link = ScriptedLink()
      val again = AtomicInteger(0)
      val session = LanSession(store, TlsConnector { _, _, _ ->
        again.incrementAndGet()
        link
      })
      try {
        session.connect("10.0.0.8", 56122)
        waitUntil { link.frames().isNotEmpty() }
        link.push(frameOf(encodeRejected("host-rejected", reason, 1, 1)))
        waitUntil(2_000) { link.closed && session.status.value.phase == LinkPhase.Paused }
        assertFalse(session.restartTransient())
        session.forceReconnect()
        Thread.sleep(300)
        assertEquals(1, again.get())
        assertEquals(reason, session.status.value.failureReason)
        assertEquals("token-1", store.load().sessionToken)
        assertEquals("client-1", store.load().clientId)
      } finally {
        session.close()
      }
    }
  }

  @Test
  fun restartTransientRetriesARefusedPortWithoutClearingPairing() {
    val store = pairedStore()
    val pin = store.load().fingerprint
    val opens = AtomicInteger(0)
    val session = LanSession(store, TlsConnector { _, _, _ ->
      opens.incrementAndGet()
      throw ConnectException("Connection refused")
    })
    try {
      session.updateDraft("do not log this prompt body")
      session.connect("10.0.0.8", 56122)
      waitUntil { opens.get() == 1 }
      assertTrue(session.restartTransient())
      waitUntil(2_000) { opens.get() >= 2 }
      assertEquals(pin, store.load().fingerprint)
      assertEquals("token-1", store.load().sessionToken)
      assertEquals("client-1", store.load().clientId)
      waitUntil { session.status.value.banner == ReconnectingBanner || session.status.value.failureReason.isNotEmpty() }
      assertTrue(session.status.value.failureReason.isNotEmpty())
      assertFalse(session.status.value.failureReason == ReconnectingBanner)
      val exported = session.exportIncident()
      assertTrue(exported.contains("posture="))
      assertFalse(exported.contains("token-1"))
      assertFalse(exported.contains("do not log this prompt body"))
    } finally {
      session.close()
    }
  }

  @Test
  fun sendCatalogueNamesQueueAdmissionBeforeTheSocketWrite() {
    val link = ScriptedLink()
    val wrote = AtomicInteger(0)
    val ledger = object : CommandLedger {
      private val inner = MemoryCommandLedger()
      override fun openIds(): List<String> = inner.openIds()
      override suspend fun remember(json: String) = inner.remember(json)
      override suspend fun noteWritten(commandId: String) {
        assertTrue(link.frames().any { frame -> envelope(frame).kind == MessageKind.Stop })
        wrote.incrementAndGet()
        inner.noteWritten(commandId)
      }
      override suspend fun applyHost(states: List<HostCommandState>): ReplayPlan = inner.applyHost(states)
    }
    val session = LanSession(pairedStore(), TlsConnector { _, _, _ -> link }, ledger = ledger)
    val results = java.util.Collections.synchronizedList(mutableListOf<CatalogueResult>())
    val collector = CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
      session.commandResults.collect { results += it }
    }
    try {
      session.connect("10.0.0.8", 56122)
      waitUntil { link.readEntries.get() > 0 }
      session.sendCatalogue(encodeEmpty(MessageKind.Stop, "stop-stage"))
      waitUntil { results.any { it.outcome == CatalogueWrite.Written } }
      val outcomes = results.map { it.outcome }
      assertEquals(CatalogueWrite.Queued, outcomes.first())
      assertTrue(outcomes.indexOf(CatalogueWrite.Queued) < outcomes.indexOf(CatalogueWrite.Written))
      waitUntil { wrote.get() == 1 }
      assertEquals(1, wrote.get())
    } finally {
      collector.cancel()
      session.close()
    }
  }
}

private fun chunkJson(itemId: String, part: Int, partCount: Int, data: String): String {
  val encoded = data.replace("\\", "\\\\").replace("\"", "\\\"")
  return """{"v":3,"id":"chunk-$itemId-$part","type":"chunk","payload":{"item_type":"message","item_id":"$itemId","part":$part,"part_count":$partCount,"data":"$encoded"}}"""
}

private fun eventJson(seq: Long, title: String): String {
  return """{"v":3,"id":"e$seq","type":"event","payload":{"conversation_id":"c1","stream_id":"s1","seq":$seq,"event":"title_changed","data":{"title":"$title"}}}"""
}

private fun snapshotBeginJson(conversationId: String, streamId: String, title: String): String {
  return """{"v":3,"id":"begin-$conversationId","type":"snapshot_begin","payload":{"conversation_id":"$conversationId","stream_id":"$streamId","seq":1,"page_count":0,"title":"$title","turns":[{"turn_id":"t-$conversationId","turn_index":0,"prompt_preview":"$title","blocks":[]}],"state":{"status":{"phase":"idle"}}}}"""
}

private fun snapshotEndJson(conversationId: String, streamId: String): String {
  return """{"v":3,"id":"end-$conversationId","type":"snapshot_end","payload":{"conversation_id":"$conversationId","stream_id":"$streamId","seq":1}}"""
}

private fun inboundMessage(kind: MessageKind, id: String, wire: String = "{}"): MonitorMessage {
  return MonitorMessage(1, id, kind, kind.wireName, wire, "", true, wire)
}

private class RecordingConnector : TlsConnector {
  private val seen = mutableListOf<String>()

  override fun open(address: String, port: Int, fingerprint: String): TlsLink {
    synchronized(seen) { seen += fingerprint }
    throw PinMismatchException(fingerprint)
  }

  fun fingerprints(): List<String> = synchronized(seen) { seen.toList() }
}

private fun assertRecoverablePauseRetries(
  frame: ByteArray,
  store: HostStore = pairedStore(),
  action: (LanSession) -> Unit
) {
  val original = store.load()
  val opens = AtomicInteger()
  val links = java.util.Collections.synchronizedList(mutableListOf<ScriptedLink>())
  val session = LanSession(store, TlsConnector { _, _, _ ->
    opens.incrementAndGet()
    ScriptedLink().also { links.add(it) }
  })
  try {
    session.connect(original.address, original.port)
    waitUntil { links.isNotEmpty() && links[0].frames().isNotEmpty() }
    links[0].push(frame)
    waitUntil(2_000) { session.reconnectPaused }
    assertEquals(1, opens.get())
    action(session)
    waitUntil(8_000) { opens.get() >= 2 }
    assertEquals(original, store.load())
  } finally {
    session.close()
  }
}

private fun assertStopIgnores(action: (LanSession) -> Unit, disconnect: Boolean) {
  val store = pairedStore()
  val original = store.load()
  val opens = AtomicInteger()
  val links = java.util.Collections.synchronizedList(mutableListOf<ScriptedLink>())
  val session = LanSession(store, TlsConnector { _, _, _ ->
    opens.incrementAndGet()
    ScriptedLink().also { links.add(it) }
  })
  try {
    session.connect("10.0.0.8", 56122)
    waitUntil { links.isNotEmpty() && links[0].frames().isNotEmpty() }
    if (disconnect) {
      session.disconnect()
    } else {
      links[0].push(frameOf(encodeRejected("host-revoked", "revoked", 1, 1)))
      waitUntil(2_000) { session.reconnectPaused }
    }
    val seen = opens.get()
    action(session)
    Thread.sleep(1_500)
    assertEquals(seen, opens.get())
    assertEquals(original, store.load())
  } finally {
    session.close()
  }
}

private fun assertTransientRejectRetries(reason: String, frame: ByteArray) {
  val store = pairedStore()
  val original = store.load()
  val opens = AtomicInteger()
  val links = java.util.Collections.synchronizedList(mutableListOf<ScriptedLink>())
  val session = LanSession(store, TlsConnector { _, _, _ ->
    opens.incrementAndGet()
    ScriptedLink().also { links.add(it) }
  })
  try {
    session.connect("10.0.0.8", 56122)
    waitUntil { links.isNotEmpty() && links[0].frames().isNotEmpty() }
    links[0].push(frame)
    // No resume() and no new process. The same loop opens again.
    waitUntil(8_000) { opens.get() >= 2 }
    assertFalse(session.reconnectPaused)
    assertTrue(session.reconnectable)
    assertEquals(original, store.load())
    if (reason.isEmpty()) assertFalse(session.status.value.failureReason == "auth")
    assertFalse(links.any { link -> link.frames().any { envelope(it).kind == MessageKind.Pair } })
    assertFalse(session.status.value.phase == LinkPhase.Paused)
  } finally {
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

private class ScriptedLink(
  override val peerFingerprint: String = "",
  private val rejectWrite: (ByteArray) -> Unit = {}
) : TlsLink {
  private val chunks = mutableListOf<ByteArray>()
  private val inbound = QueueStream()
  val readEntries = AtomicInteger(0)
  private val writeDepth = AtomicInteger(0)
  var overlapped = false
    private set

  private fun enterWrite() {
    if (writeDepth.incrementAndGet() > 1) overlapped = true
  }

  private fun leaveWrite() {
    writeDepth.decrementAndGet()
  }

  override val input: InputStream = object : InputStream() {
    override fun read(): Int = inbound.read()

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
      readEntries.incrementAndGet()
      return inbound.read(buffer, offset, length)
    }
  }
  override val output: OutputStream = object : OutputStream() {
    override fun write(value: Int) {
      enterWrite()
      try {
        val slice = byteArrayOf(value.toByte())
        rejectWrite(slice)
        synchronized(chunks) { chunks += slice }
      } finally {
        leaveWrite()
      }
    }

    override fun write(buffer: ByteArray, offset: Int, length: Int) {
      enterWrite()
      try {
        val slice = buffer.copyOfRange(offset, offset + length)
        rejectWrite(slice)
        synchronized(chunks) { chunks += slice }
      } finally {
        leaveWrite()
      }
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
      if (queue.isEmpty() && !closed && timeouts == 0) (queue as Object).wait(50)
      if (queue.isNotEmpty()) {
        var count = 0
        while (count < length && queue.isNotEmpty()) {
          buffer[offset + count] = queue.removeFirst()
          count += 1
        }
        return count
      }
      if (closed) return -1
      if (timeouts > 0) timeouts -= 1
      return 0
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
