package computing.michell.monitor.net

/* Image loader against a fake host. Two downloads at a time, a cache hit is
   quiet, a missing file keeps its reason, and a command is not stuck behind
   a picture. (c) 2026 Michell Computing. */

import computing.michell.monitor.data.ImageRow
import computing.michell.monitor.data.conversation
import computing.michell.monitor.data.host
import computing.michell.monitor.data.openTestDatabase
import computing.michell.monitor.data.turn
import computing.michell.monitor.ui.imageTileLabel
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertTrue
import org.junit.Test

class ImageLoaderTest {
  @Test
  fun tenQueuedImagesNeverExceedTwoConcurrentRequests() {
    val started = AtomicInteger()
    val inFlight = AtomicInteger()
    val maxInFlight = AtomicInteger()
    withLoader(dispatcher = object : Dispatcher() {
      override fun dispatch(request: RecordedRequest): MockResponse {
        if (request.path.orEmpty().contains("/v4/images/")) {
          val now = inFlight.incrementAndGet()
          maxInFlight.updateAndGet { current -> maxOf(current, now) }
          started.incrementAndGet()
          return MockResponse().setHeadersDelay(5, TimeUnit.SECONDS).setBody("img")
        }
        return MockResponse().setBody("ok")
      }
    }) { loader, _, _ ->
      loader.load((1..10).map { index -> want("pic-$index") })
      awaitCount(started, 2)
      Thread.sleep(400)
      assertEquals(2, started.get())
      assertTrue(maxInFlight.get() <= 2)
      assertTrue(inFlight.get() <= 2)
    }
  }

  @Test
  fun aCachedIdMakesNoRequest() {
    withLoader { loader, server, database ->
      val file = File.createTempFile("pic-cached", ".bin")
      file.writeBytes(byteArrayOf(1, 2, 3))
      database.monitor().replaceImage(ImageRow("pic-cached", "t1", "item", "cached.png", 3, file.absolutePath, 1))
      loader.load(listOf(want("pic-cached")))
      assertTrue(loader.awaitIdle())
      assertEquals(0, server.requestCount)
    }
  }

  @Test
  fun a404RecordsTheMissingReason() {
    val body = """{"reason":"not_found","message":"That image is not in the store."}"""
    withLoader(dispatcher = object : Dispatcher() {
      override fun dispatch(request: RecordedRequest): MockResponse {
        return MockResponse().setResponseCode(404).setBody(body)
      }
    }) { loader, server, database ->
      loader.load(listOf(want("missing")))
      assertTrue(loader.awaitIdle())
      assertEquals("That image is not in the store.", loader.missingReason("missing"))
      assertEquals(
        "Image unavailable: That image is not in the store.",
        imageTileLabel(false, loader.missingReason("missing"), false, true)
      )
      assertEquals("", database.monitor().image("missing")?.localPath)
      val fetched = server.requestCount
      loader.load(listOf(want("missing")))
      assertTrue(loader.awaitIdle())
      assertEquals(fetched, server.requestCount)
    }
  }

  @Test(timeout = 20_000)
  fun aCommandPostedDuringASlowImageDownloadCompletesAtOnce() {
    val seen = CountDownLatch(1)
    val commands = OkHttpClient.Builder().build()
    try {
      withLoader(images = OkHttpClient.Builder().build(), dispatcher = object : Dispatcher() {
        override fun dispatch(request: RecordedRequest): MockResponse {
          if (request.path.orEmpty().contains("/v4/images/")) {
            seen.countDown()
            return MockResponse().setHeadersDelay(5, TimeUnit.SECONDS).setBody("img")
          }
          return MockResponse().setBody("done")
        }
      }) { loader, server, _ ->
        assertNotSame(loader.images.dispatcher, commands.dispatcher)
        loader.load(listOf(want("slow")))
        assertTrue(seen.await(2, TimeUnit.SECONDS))
        val started = System.nanoTime()
        val request = Request.Builder()
          .url(server.url("/v4/commands"))
          .post("{}".toRequestBody("application/json".toMediaType()))
          .build()
        val response = commands.newCall(request).execute()
        val elapsedMs = (System.nanoTime() - started) / 1_000_000
        response.use { assertEquals(200, it.code) }
        assertTrue("command took ${elapsedMs}ms", elapsedMs < 200)
      }
    } finally {
      commands.dispatcher.executorService.shutdownNow()
    }
  }
}

private fun want(id: String): ImageRequest {
  return ImageRequest(id, turnId = "t1", itemId = "item", name = "$id.png", turnEtag = "etag-1")
}

private fun withLoader(
  images: OkHttpClient = OkHttpClient.Builder().build(),
  dispatcher: Dispatcher? = null,
  body: (ImageLoader, MockWebServer, computing.michell.monitor.data.MonitorDatabase) -> Unit
) {
  val database = openTestDatabase()
  val server = MockWebServer()
  val storage = File.createTempFile("monitor-images-", "")
  storage.delete()
  storage.mkdirs()
  val dao = database.monitor()
  dao.replaceHost(host("10.0.0.8:56122"))
  dao.replaceConversation(conversation("c1", 1, "Chat"))
  dao.replaceTurn(turn("t1", 0, "prompt", "c1"))
  if (dispatcher != null) server.dispatcher = dispatcher
  server.start()
  val loader = ImageLoader(database, images, server.url("/"), storage, clock = { 1_000L })
  try {
    body(loader, server, database)
  } finally {
    loader.close()
    server.shutdown()
    images.dispatcher.executorService.shutdownNow()
    storage.deleteRecursively()
    database.close()
  }
}

private fun awaitCount(counter: AtomicInteger, target: Int) {
  val deadline = System.currentTimeMillis() + 5_000
  while (counter.get() < target && System.currentTimeMillis() < deadline) Thread.sleep(10)
  assertTrue("saw ${counter.get()} of $target", counter.get() >= target)
}
