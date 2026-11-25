package computing.michell.monitor.net

/* Image downloads on their own worker (c) 2026 Michell Computing.

   At most two files are fetched at once, on a client that is not the command
   lane, so Stop is not stuck behind a picture. Visible ids run first. An id
   that scrolls away is cancelled. A missing picture keeps the host's reason
   and is not asked for again until that turn's etag changes. Bytes land in
   app storage under the image id, and the image table records the path.
   Decoding stays off the caller thread and inside BitmapBounds. */

import android.graphics.BitmapFactory
import computing.michell.monitor.data.ImageRow
import computing.michell.monitor.data.MonitorDatabase
import computing.michell.monitor.ui.bitmapBoundsPlan
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import okhttp3.Call
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request

const val ImageDownloadSlots = 2

class ImageLoader(
  private val database: MonitorDatabase,
  val images: OkHttpClient,
  private val baseUrl: HttpUrl,
  private val storage: File,
  private val token: String = "",
  private val clock: () -> Long = { System.currentTimeMillis() }
) : AutoCloseable {
  private val dao = database.monitor()
  private val lock = ReentrantLock()
  private val ready = lock.newCondition()
  private val idle = lock.newCondition()
  private val writeLock = ReentrantLock()
  private val pending = LinkedHashMap<String, ImageRequest>()
  private val order = ArrayList<String>()
  private val inflight = HashMap<String, Call>()
  private val reasons = HashMap<String, String>()
  private val missingEtag = HashMap<String, String>()
  private var closed = false
  private var busy = 0

  init {
    images.dispatcher.maxRequests = ImageDownloadSlots
    images.dispatcher.maxRequestsPerHost = ImageDownloadSlots
    storage.mkdirs()
    repeat(ImageDownloadSlots) { index ->
      Thread(::loop, "ImageLoader-$index").apply {
        isDaemon = true
        start()
      }
    }
  }

  /** Visible images, first on screen first. Replaces the previous visible set. */
  fun load(requests: List<ImageRequest>) {
    lock.withLock {
      val ids = requests.map { it.id }
      val keep = ids.toSet()
      val gone = inflight.keys.filter { it !in keep }
      for (id in gone) inflight.remove(id)?.cancel()
      pending.keys.retainAll(keep)
      order.clear()
      for (request in requests) {
        if (request.id.isEmpty() || request.id in order) continue
        order += request.id
        if (request.id in inflight || request.id in pending) continue
        if (!needsFetch(request)) continue
        pending[request.id] = request
      }
      ready.signalAll()
    }
  }

  /** The host message, without the tile's "Image unavailable:" prefix. */
  fun missingReason(id: String): String = lock.withLock { reasons[id].orEmpty() }

  fun awaitIdle(timeoutMs: Long = 5_000): Boolean {
    val deadline = System.currentTimeMillis() + timeoutMs
    lock.withLock {
      while (!closed && (busy > 0 || pending.isNotEmpty() || inflight.isNotEmpty())) {
        val left = deadline - System.currentTimeMillis()
        if (left <= 0L) return false
        idle.await(left, TimeUnit.MILLISECONDS)
      }
      return true
    }
  }

  override fun close() {
    lock.withLock {
      closed = true
      pending.clear()
      for (call in inflight.values) call.cancel()
      inflight.clear()
      ready.signalAll()
      idle.signalAll()
    }
  }

  private fun loop() {
    while (true) {
      val request = lock.withLock {
        if (closed) return
        val next = order.firstOrNull { it in pending }?.let { pending.remove(it) }
        if (next == null) {
          if (busy == 0 && inflight.isEmpty()) idle.signalAll()
          ready.await()
          null
        } else {
          busy += 1
          next
        }
      } ?: continue
      try {
        fetch(request)
      } catch (error: Exception) {
        // A cancel or a dropped connection is not a missing image. The next visible pass can try again.
      } finally {
        lock.withLock {
          busy -= 1
          inflight.remove(request.id)
          idle.signalAll()
        }
      }
    }
  }

  private fun fetch(request: ImageRequest) {
    if (!needsFetch(request)) return
    val url = baseUrl.newBuilder().addPathSegments("v4/images").addPathSegment(request.id).build()
    val builder = Request.Builder().url(url).get()
    if (token.isNotEmpty()) builder.header("Authorization", "Bearer ${token}")
    val call = images.newCall(builder.build())
    val started = lock.withLock {
      if (closed || request.id !in order) {
        call.cancel()
        false
      } else {
        inflight[request.id] = call
        true
      }
    }
    if (!started) return
    call.execute().use { response ->
      if (call.isCanceled()) return
      if (response.code == 404 || response.code == 413) {
        recordMissing(request, missingReasonText(response.body?.string().orEmpty(), response.code))
        return
      }
      if (response.code !in 200..299) return
      val bytes = response.body?.bytes() ?: return
      val file = File(storage, safeImageFile(request.id))
      file.writeBytes(bytes)
      decodeOffCaller(file)
      recordFile(request, file, bytes.size.toLong())
    }
  }

  private fun needsFetch(request: ImageRequest): Boolean {
    val failedAt = lock.withLock { missingEtag[request.id] }
    if (failedAt != null && failedAt == request.turnEtag) return false
    val row = readImage(request.id) ?: return true
    if (row.localPath.isEmpty()) return failedAt == null
    return !File(row.localPath).isFile
  }

  private fun recordMissing(request: ImageRequest, reason: String) {
    lock.withLock {
      reasons[request.id] = reason
      missingEtag[request.id] = request.turnEtag
    }
    writeImage(ImageRow(request.id, request.turnId, request.itemId, request.name, 0L, "", clock()))
  }

  private fun recordFile(request: ImageRequest, file: File, size: Long) {
    lock.withLock {
      reasons.remove(request.id)
      missingEtag.remove(request.id)
    }
    writeImage(ImageRow(request.id, request.turnId, request.itemId, request.name, size, file.absolutePath, clock()))
  }

  private fun readImage(id: String): ImageRow? {
    return writeLock.withLock { dao.image(id) }
  }

  private fun writeImage(row: ImageRow) {
    writeLock.withLock {
      try {
        dao.write { dao.replaceImage(row) }
      } catch (error: Exception) {
        // The turn row is not in Room yet. The file, if any, is already stored.
      }
    }
  }
}

data class ImageRequest(
  val id: String,
  val turnId: String,
  val itemId: String,
  val name: String,
  val turnEtag: String
)

/** Host message for the existing "Image unavailable:" tile. */
internal fun missingReasonText(body: String, code: Int): String {
  val parsed = parseJson(body)
  val message = parsed?.text("message").orEmpty()
  if (message.isNotEmpty()) return message
  val reason = parsed?.text("reason").orEmpty()
  if (reason.isNotEmpty()) return reason
  return if (code == 404) "missing" else "not available"
}

private fun safeImageFile(id: String): String {
  val cleaned = id.filter { it.isLetterOrDigit() || it == '-' || it == '_' }
  return cleaned.ifEmpty { "image" }
}

/** Bounds are checked before the pixel buffer is allocated. Failures stay off the caller. */
private fun decodeOffCaller(file: File) {
  try {
    val bounds = BitmapFactory.Options()
    bounds.inJustDecodeBounds = true
    BitmapFactory.decodeFile(file.absolutePath, bounds)
    val plan = bitmapBoundsPlan(bounds.outWidth, bounds.outHeight)
    if (!plan.allocate) return
    val pixels = BitmapFactory.Options()
    pixels.inSampleSize = plan.sampleSize
    BitmapFactory.decodeFile(file.absolutePath, pixels)
  } catch (error: Throwable) {
    // A desktop unit test has no bitmap decoder. The file is already in storage.
  }
}
