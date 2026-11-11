package computing.michell.monitor.connection

/* Wi-Fi route identity and opening deadlines (c) 2026 Michell Computing. */

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.net.ConnectException
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

class LanRouteTest {
  @Test
  fun wifiWithoutInternetBeatsAVpnWithInternet() {
    val selected = selectLanRoute(listOf(
      RouteFacts("vpn", wifi = false, vpn = true, internet = true),
      RouteFacts("wifi", wifi = true, vpn = false, internet = false),
      RouteFacts("cell", wifi = false, vpn = false, internet = true)
    ))
    assertEquals(LanRoute("wifi"), selected)
  }

  @Test
  fun aVpnIsNotALanRoute() {
    assertNull(selectLanRoute(listOf(RouteFacts("vpn", wifi = false, vpn = true, internet = true))))
    assertNull(selectLanRoute(listOf(RouteFacts("wifi-vpn", wifi = true, vpn = true, internet = true))))
    assertNull(selectLanRoute(emptyList()))
  }

  @Test
  fun theConnectorBindsTheWifiIdentityNotTheVpn() {
    val bound = mutableListOf<String>()
    val book = LanRouteBook()
    book.remember("wifi") { bound += "wifi" }
    book.remember("vpn") { bound += "vpn" }
    val socket = Socket()
    try {
      book.bind(socket, selectLanRoute(listOf(
        RouteFacts("vpn", wifi = false, vpn = true, internet = true),
        RouteFacts("wifi", wifi = true, vpn = false, internet = false)
      )))
      assertEquals(listOf("wifi"), bound)
    } finally {
      socket.close()
    }
  }

  @Test
  fun aForgottenBindIsNotAHostFailure() {
    val book = LanRouteBook()
    book.remember("wifi") { }
    book.forget("wifi")
    val socket = Socket()
    try {
      book.bind(socket, LanRoute("wifi"))
      fail("a forgotten bind must not pretend the socket was bound")
    } catch (error: LanRouteUnavailable) {
      assertEquals("The Wi-Fi network is no longer available.", error.message)
    } finally {
      socket.close()
    }
  }

  @Test
  fun aLostIdentityDoesNotClearAReplacement() {
    var state: LanRoute? = LanRoute("wifi-a")
    state = applyRouteUp(state, LanRoute("wifi-b")).first
    state = applyRouteLost(state, LanRoute("wifi-a"))
    assertEquals(LanRoute("wifi-b"), state)
    state = applyRouteLost(state, LanRoute("stale"))
    assertEquals(LanRoute("wifi-b"), state)
    assertNull(applyRouteLost(state, LanRoute("wifi-b")))
  }

  @Test
  fun aHandshakeBeyondOneSecondUsesTheHandshakeBudget() {
    val handshakeTimeout = AtomicInteger(0)
    val restored = AtomicInteger(0)
    openWithDeadlines(
      connect = { timeout -> assertEquals(ConnectTimeoutMs, timeout) },
      handshake = { timeout ->
        handshakeTimeout.set(timeout)
        assertTrue(timeout > ReadTimeoutMs)
        Thread.sleep(1_200)
      },
      restore = { timeout -> restored.set(timeout) }
    )
    assertEquals(HandshakeTimeoutMs, handshakeTimeout.get())
    assertEquals(ReadTimeoutMs, restored.get())
  }

  @Test
  fun aStalledHandshakeFailsAndClosesInsteadOfWaitingForever() {
    var closed = false
    try {
      openWithDeadlines(
        handshake = { timeout ->
          assertTrue(timeout > ReadTimeoutMs)
          throw SocketTimeoutException("handshake stalled")
        },
        close = { closed = true }
      )
      fail("a stalled handshake must not return a socket")
    } catch (error: SocketTimeoutException) {
      assertTrue(closed)
      assertTrue(error.message?.contains("stalled") == true)
    }
  }

  @Test
  fun stopClearsTrackedStateAndAStaleCallbackDoesNotReportLoss() {
    var down = 0
    var absent = 0
    var scheduled: (() -> Unit)? = null
    val gate = WifiLossGate(
      onUp = {},
      onDown = { down += 1 },
      onAbsent = { absent += 1 },
      wifiPresent = { false },
      confirmLater = { scheduled = it }
    )
    gate.activate()
    gate.onAvailable("wifi-a")
    gate.deactivate()
    gate.onLost("wifi-a")
    scheduled?.invoke()
    assertEquals(0, down)
    gate.activate()
    gate.onAvailable("wifi-b")
    gate.onLost("wifi-a")
    scheduled?.invoke()
    assertEquals(0, down)
    assertEquals(0, absent)
    gate.onLost("wifi-b")
    scheduled!!()
    assertEquals(1, down)
  }

  @Test
  fun aRoamKeepsTheLinkUpUntilTheOldIdentityIsTheLastOne() {
    var down = 0
    val gate = WifiLossGate(
      onUp = {},
      onDown = { down += 1 },
      onAbsent = {},
      wifiPresent = { false },
      confirmLater = { it() }
    )
    gate.activate()
    gate.onAvailable("ap-a")
    gate.onAvailable("ap-b")
    gate.onLost("ap-a")
    assertEquals(0, down)
    gate.onLost("ap-b")
    assertEquals(1, down)
  }

  @Test
  fun theSessionPassesTheCurrentRouteAndIgnoresAStaleLoss() {
    val seen = AtomicReference<LanRoute?>()
    val opens = AtomicInteger(0)
    val connector = object : TlsConnector {
      override fun open(address: String, port: Int, fingerprint: String): TlsLink =
        open(address, port, fingerprint, null)

      override fun open(address: String, port: Int, fingerprint: String, route: LanRoute?): TlsLink {
        seen.set(route)
        opens.incrementAndGet()
        throw ConnectException("refused")
      }
    }
    val store = HostStore(MemoryStringMap())
    store.save(HostRecord("10.0.0.8", 56122, "ab".repeat(32), "client-1", "token-1"))
    val session = LanSession(store, connector)
    try {
      session.onWifiRoute(LanRoute("wifi-a"))
      session.onWifiRouteLost(LanRoute("stale"))
      assertEquals(LanRoute("wifi-a"), session.currentLanRoute())
      session.connect("10.0.0.8", 56122)
      waitUntil { opens.get() >= 1 }
      assertEquals(LanRoute("wifi-a"), seen.get())
      session.onWifiRouteLost(LanRoute("wifi-a"))
      assertNull(session.currentLanRoute())
    } finally {
      session.close()
    }
  }
}

private fun applyRouteUp(current: LanRoute?, route: LanRoute): Pair<LanRoute, Boolean> {
  return route to (current != null && current != route)
}

private fun applyRouteLost(current: LanRoute?, route: LanRoute): LanRoute? {
  if (current != route) return current
  return null
}

private fun waitUntil(timeoutMs: Long = 2_000, condition: () -> Boolean) {
  val deadline = System.currentTimeMillis() + timeoutMs
  while (System.currentTimeMillis() < deadline) {
    if (condition()) return
    Thread.sleep(20)
  }
  assertTrue(condition())
}
