package computing.michell.monitor.net

/* Pinned HTTPS lanes. MockWebServer speaks TLS. The image lane is the
   openLane the image client will use; it is not the command dispatcher.
   (c) 2026 Michell Computing. */

import java.net.InetSocketAddress
import java.net.Proxy
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.SocketFactory
import okhttp3.Call
import okhttp3.EventListener
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class MonitorHttpTest {
  @Test
  fun aGoodPinConnects() {
    withHttps { server, pin, http ->
      http.pins.set(server.hostName, server.port, pin)
      server.enqueue(MockResponse().setBody("hello"))
      val response = http.client.reads.newCall(get(server, "/v4/hello")).execute()
      response.use { assertEquals(200, it.code) }
      assertEquals(1, server.requestCount)
    }
  }

  @Test
  fun aWrongPinFailsWithANameTheUiCanUse() {
    withHttps { server, pin, http ->
      http.pins.set(server.hostName, server.port, "ab".repeat(32))
      server.enqueue(MockResponse().setBody("hello"))
      try {
        http.client.reads.newCall(get(server, "/v4/hello")).execute().close()
        fail("wrong pin connected")
      } catch (error: Exception) {
        assertEquals(PinMismatchName, namedPinError(error))
        assertTrue(pin != "ab".repeat(32))
      }
    }
  }

  @Test
  fun anEmptyPinTrustsTheEndpoint() {
    withHttps { server, _, http ->
      http.pins.set(server.hostName, server.port, "")
      server.enqueue(MockResponse().setBody("open"))
      val response = http.client.reads.newCall(get(server, "/v4/hello")).execute()
      response.use { assertEquals(200, it.code) }
    }
  }

  @Test
  fun aMalformedPinIsRefusedBeforeConnecting() {
    withHttps { server, _, http ->
      http.pins.set(server.hostName, server.port, "zz")
      val connected = AtomicBoolean(false)
      val watched = http.client.commands.newBuilder().eventListener(object : EventListener() {
        override fun connectStart(call: Call, inetSocketAddress: InetSocketAddress, proxy: Proxy) {
          connected.set(true)
        }
      }).build()
      try {
        watched.newCall(get(server, "/v4/hello")).execute().close()
        fail("malformed pin connected")
      } catch (error: Exception) {
        assertEquals(MalformedPinName, namedPinError(error))
      }
      assertFalse(connected.get())
      assertEquals(0, server.requestCount)
      watched.dispatcher.executorService.shutdown()
    }
  }

  @Test(timeout = 20_000)
  fun aCommandCompletesWhileAnImageResponseIsInFlight() {
    withHttps { server, pin, http ->
      http.pins.set(server.hostName, server.port, pin)
      val imageSeen = CountDownLatch(1)
      server.dispatcher = object : Dispatcher() {
        override fun dispatch(request: RecordedRequest): MockResponse {
          if (request.path?.startsWith("/v4/images/") == true) {
            imageSeen.countDown()
            return MockResponse().setHeadersDelay(5, TimeUnit.SECONDS).setBody("image")
          }
          return MockResponse().setBody("done")
        }
      }
      val images = http.client.openLane()
      images.dispatcher.maxRequests = 1
      images.dispatcher.maxRequestsPerHost = 1
      assertNotSame(images.dispatcher, http.client.commands.dispatcher)
      val imageCall = Thread {
        try {
          images.newCall(get(server, "/v4/images/1")).execute().close()
        } catch (ignored: Exception) {
        }
      }
      imageCall.isDaemon = true
      imageCall.start()
      assertTrue(imageSeen.await(2, TimeUnit.SECONDS))
      val started = System.nanoTime()
      val body = "{}".toRequestBody("application/json".toMediaType())
      val request = Request.Builder().url(server.url("/v4/commands")).post(body).build()
      val response = http.client.commands.newCall(request).execute()
      val elapsedMs = (System.nanoTime() - started) / 1_000_000
      response.use { assertEquals(200, it.code) }
      assertTrue("command took ${elapsedMs}ms", elapsedMs < 200)
      images.dispatcher.executorService.shutdownNow()
    }
  }

  @Test
  fun theThreeLanesShareThePinAndTheSocketFactory() {
    val http = MonitorHttp(MapPins(), SocketFactory.getDefault())
    try {
      assertSame(http.sockets, http.pulse.socketFactory)
      assertSame(http.sockets, http.reads.socketFactory)
      assertSame(http.sockets, http.commands.socketFactory)
      assertSame(http.ssl, http.pulse.sslSocketFactory)
      assertSame(http.ssl, http.commands.sslSocketFactory)
      assertSame(http.trust, http.reads.x509TrustManager)
      assertNotSame(http.pulse.dispatcher, http.reads.dispatcher)
      assertNotSame(http.reads.dispatcher, http.commands.dispatcher)
      assertNotSame(http.pulse.dispatcher, http.commands.dispatcher)
    } finally {
      release(http)
    }
  }

  @Test
  fun theWifiFactorySamplesOnEverySocket() {
    var samples = 0
    val factory = WifiSocketFactory { samples += 1 }
    factory.createSocket().close()
    factory.createSocket().close()
    assertEquals(2, samples)
    assertEquals(-1, selectWifiIndex(listOf(RouteFacts(wifi = false, vpn = false))))
    assertEquals(-1, selectWifiIndex(listOf(RouteFacts(wifi = true, vpn = true))))
    assertEquals(1, selectWifiIndex(listOf(
      RouteFacts(wifi = true, vpn = true),
      RouteFacts(wifi = true, vpn = false)
    )))
  }

  @Test
  fun pairingsAreStoredByEndpoint() {
    val store = PairingStore(MemoryPairingMap())
    store.save(EndpointPairing("10.0.0.8", 56122, pin = "ab".repeat(32), clientId = "phone-a", token = "token-a"))
    store.save(EndpointPairing("10.0.0.9", 56123, pin = "cd".repeat(32), clientId = "phone-b", token = "token-b"))
    val first = store.lookup("10.0.0.8", 56122)
    val second = store.lookup("10.0.0.9", 56123)
    assertEquals("token-a", first.token)
    assertEquals("token-b", second.token)
    assertEquals("ab".repeat(32), store.pinFor("10.0.0.8", 56122))
    assertEquals("cd".repeat(32), second.pin)
    assertTrue(first.paired)
    assertEquals("10.0.0.9", store.selected().address)
    store.forget("10.0.0.9", 56123)
    assertEquals("", store.lookup("10.0.0.9", 56123).token)
    assertEquals("token-a", store.lookup("10.0.0.8", 56122).token)
  }

  @Test
  fun aPinThatIsNot64HexIsMalformed() {
    assertNull(namedPinError(IllegalStateException("other")))
    try {
      refuseMalformedPin("not-a-pin")
      fail("malformed pin was accepted")
    } catch (error: PinMalformedException) {
      assertEquals(MalformedPinName, namedPinError(error))
    }
    refuseMalformedPin("")
    refuseMalformedPin("ab".repeat(32))
  }
}

private class MapPins : PinSource {
  private val pins = HashMap<String, String>()

  fun set(host: String, port: Int, pin: String) {
    pins["$host:$port"] = pin
  }

  override fun pinFor(host: String, port: Int): String = pins["$host:$port"].orEmpty()
}

private class Fixture(
  val pins: MapPins,
  val client: MonitorHttp
)

private fun get(server: MockWebServer, path: String): Request {
  return Request.Builder().url(server.url(path)).build()
}

private fun release(http: MonitorHttp) {
  listOf(http.pulse, http.reads, http.commands).forEach { client ->
    client.dispatcher.executorService.shutdownNow()
    client.connectionPool.evictAll()
  }
}

private fun withHttps(body: (MockWebServer, String, Fixture) -> Unit) {
  val held = HeldCertificate.Builder()
    .commonName("localhost")
    .addSubjectAlternativeName("localhost")
    .build()
  val handshake = HandshakeCertificates.Builder().heldCertificate(held).build()
  val server = MockWebServer()
  server.useHttps(handshake.sslSocketFactory(), false)
  val pins = MapPins()
  val http = MonitorHttp(pins, SocketFactory.getDefault())
  server.start()
  try {
    body(server, sha256Hex(held.certificate.encoded), Fixture(pins, http))
  } finally {
    server.shutdown()
    release(http)
  }
}
