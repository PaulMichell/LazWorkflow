package computing.michell.monitor.connection

/* Outbound dispatch must not wait out the read timeout (c) 2026 Michell Computing.

   Measured 2026-11-11 on JBR 25, 127.0.0.1. Baseline is the previous loop:
   block in read for the 1000 ms socket timeout, then write one frame.
   Command at read entry, 4 samples: p50 1000 ms, p95 1001 ms. Eight such
   frames took 8007 ms. Reader wakes were the timeouts, about 1/s, CPU near 0.
   After the writer split, TLS loopback, command queued while the read was
   blocked, 8 samples: p50 5 ms, p95 5 ms, max 5 ms. Eight commands plus a
   pong took 6 ms. Over a 1.2 s idle window: 1 reader wake, 0 writer wakes,
   outbound pending 0, process CPU 3%. A uniform phase of the old timeout
   would sit near 500/950 ms; the new path does not depend on that phase. */

import computing.michell.monitor.protocol.FrameAssembler
import computing.michell.monitor.protocol.MessageKind
import computing.michell.monitor.protocol.encodeEmpty
import computing.michell.monitor.protocol.encodeTicks
import computing.michell.monitor.protocol.tryDecodeEnvelope
import computing.michell.monitor.protocol.tryEncodeFrame
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.SocketTimeoutException
import java.security.KeyStore
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.ArrayDeque
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager
import kotlin.math.ceil
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class OutboundDispatchTest {
  @Test(timeout = 15_000)
  fun aQueuedCommandIsWrittenWhileTheReadStaysBlocked() {
    val link = GatedLink()
    val session = LanSession(pairedStore("10.0.0.8", 56122), TlsConnector { _, _, _ -> link })
    try {
      session.connect("10.0.0.8", 56122)
      assertTrue(waitFor { link.readBlocked })
      val started = System.nanoTime()
      session.sendCatalogue(encodeEmpty(MessageKind.Stop, "while-blocked"))
      assertTrue(waitFor { link.kinds().contains(MessageKind.Stop) })
      val elapsedMs = (System.nanoTime() - started) / 1_000_000L
      assertTrue("read unblocked before the command was written", link.readBlocked)
      assertTrue("dispatch took ${elapsedMs} ms", elapsedMs < 250L)
    } finally {
      session.close()
    }
  }

  @Test(timeout = 15_000)
  fun aBurstDoesNotStarveTheReadOrAControlFrame() {
    val link = GatedLink(writeDelayMs = 15L)
    val session = LanSession(pairedStore("10.0.0.8", 56122), TlsConnector { _, _, _ -> link })
    try {
      session.connect("10.0.0.8", 56122)
      assertTrue(waitFor { link.readBlocked })
      val started = System.nanoTime()
      repeat(6) { index -> session.sendCatalogue(encodeEmpty(MessageKind.Stop, "burst-$index")) }
      assertTrue(waitFor { link.writeCount() >= 2 })
      link.push(frameOf(encodeTicks(MessageKind.Ping, "ping-burst", 7L)))
      assertTrue(waitFor(3_000) { link.kinds().contains(MessageKind.Pong) && link.kinds().count { it == MessageKind.Stop } >= 6 })
      val elapsedMs = (System.nanoTime() - started) / 1_000_000L
      val kinds = link.kinds()
      val pongAt = kinds.indexOf(MessageKind.Pong)
      val lastStop = kinds.lastIndexOf(MessageKind.Stop)
      assertTrue("pong at $pongAt, last stop at $lastStop in $kinds", pongAt in 0 until lastStop)
      assertTrue("burst took ${elapsedMs} ms", elapsedMs < 250L)
    } finally {
      session.close()
    }
  }

  @Test(timeout = 60_000)
  fun idlePeerAndBurstLatencyOnLoopback() {
    val host = QuietTlsHost()
    val connector = CountingConnector()
    val session = LanSession(pairedStore("127.0.0.1", host.port), connector)
    try {
      val accepted = Thread { host.accept() }
      accepted.isDaemon = true
      accepted.start()
      session.connect("127.0.0.1", host.port)
      assertTrue(waitFor(8_000) { host.kinds().contains(MessageKind.Hello) })
      val idleReads = connector.entered.get()
      val idleWakes = session.outboundWakeCount()
      val cpu = sampleCpu(1_200L)
      val idleReadWakes = connector.entered.get() - idleReads
      val idleWriterWakes = session.outboundWakeCount() - idleWakes
      assertEquals(0, session.outboundPending())
      val idle = mutableListOf<Long>()
      repeat(8) {
        assertTrue(waitFor { connector.blocked() })
        val started = System.nanoTime()
        val id = "idle-$it"
        session.sendCatalogue(encodeEmpty(MessageKind.Stop, id))
        assertTrue(waitFor { host.ids().contains(id) })
        idle += (System.nanoTime() - started) / 1_000_000L
      }
      assertTrue(waitFor { connector.blocked() })
      val burstStart = System.nanoTime()
      val burstIds = (0 until 8).map { "burst-$it" }
      burstIds.forEach { id -> session.sendCatalogue(encodeEmpty(MessageKind.Stop, id)) }
      host.write(frameOf(encodeTicks(MessageKind.Ping, "ping-idle", 9L)))
      assertTrue(waitFor(3_000) { burstIds.all { id -> host.ids().contains(id) } && host.kinds().contains(MessageKind.Pong) })
      val burstMs = (System.nanoTime() - burstStart) / 1_000_000L
      val burstStops = host.kinds().filter { it == MessageKind.Stop }
      println(
        "metric idle_command samples=${idle.size} p50_ms=${percentile(idle, 0.50)} p95_ms=${percentile(idle, 0.95)} " +
          "max_ms=${idle.maxOrNull()} writer_wakes_idle=$idleWriterWakes reader_wakes_idle=$idleReadWakes " +
          "cpu_ms=${cpu.cpuMs} cpu_percent=${cpu.percent}"
      )
      println("metric burst frames=8 total_ms=$burstMs pong_seen=true stops=${burstStops.size}")
      assertTrue("idle p95 ${percentile(idle, 0.95)} ms", percentile(idle, 0.95) < 250L)
      assertTrue("burst ${burstMs} ms", burstMs < 250L)
      assertTrue("idle reader wakes $idleReadWakes", idleReadWakes < 8)
      assertTrue("idle writer wakes $idleWriterWakes", idleWriterWakes <= 1L)
      assertTrue("idle cpu ${cpu.percent}%", cpu.percent < 40.0)
    } finally {
      session.close()
      host.close()
    }
  }

}

private fun percentile(samples: List<Long>, fraction: Double): Long {
  val sorted = samples.sorted()
  val rank = ceil(fraction * sorted.size).toInt().coerceIn(1, sorted.size) - 1
  return sorted[rank]
}

private fun waitFor(timeoutMs: Long = 2_000, condition: () -> Boolean): Boolean {
  val start = System.currentTimeMillis()
  while (!condition()) {
    if (System.currentTimeMillis() - start > timeoutMs) return false
    Thread.sleep(5)
  }
  return true
}

private fun frameOf(json: String): ByteArray {
  val encoded = tryEncodeFrame(json)
  check(encoded.ok)
  return encoded.bytes
}

private fun pairedStore(address: String, port: Int): HostStore {
  val store = HostStore(MemoryStringMap())
  store.save(HostRecord(address, port, "", "client-1", "token-1"))
  return store
}

private data class CpuSample(val cpuMs: Long, val percent: Double)

private fun sampleCpu(wallMs: Long): CpuSample {
  val bean = java.lang.management.ManagementFactory.getOperatingSystemMXBean()
  val cpu = bean as? com.sun.management.OperatingSystemMXBean
  val before = cpu?.processCpuTime ?: 0L
  Thread.sleep(wallMs)
  val after = cpu?.processCpuTime ?: before
  val cpuMs = (after - before) / 1_000_000L
  return CpuSample(cpuMs, if (wallMs == 0L) 0.0 else 100.0 * cpuMs / wallMs)
}

private class CountingConnector : TlsConnector {
  val entered = AtomicInteger(0)
  private val returned = AtomicInteger(0)
  fun blocked(): Boolean = entered.get() > returned.get()

  override fun open(address: String, port: Int, fingerprint: String): TlsLink {
    val inner = SslSocketConnector().open(address, port, fingerprint)
    return object : TlsLink {
      override val peerFingerprint: String = inner.peerFingerprint
      override val input: InputStream = object : InputStream() {
        override fun read(): Int {
          val one = ByteArray(1)
          val count = read(one, 0, 1)
          return if (count <= 0) -1 else one[0].toInt() and 0xFF
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
          entered.incrementAndGet()
          try {
            return inner.input.read(buffer, offset, length)
          } finally {
            returned.incrementAndGet()
          }
        }
      }
      override val output: OutputStream = inner.output
      override fun close() = inner.close()
    }
  }
}

private class QuietTlsHost {
  private val server: SSLServerSocket
  private val frames = CopyOnWriteArrayList<Pair<MessageKind, String>>()
  val peerReads = AtomicInteger(0)
  @Volatile var socket: javax.net.ssl.SSLSocket? = null
  val port: Int get() = server.localPort

  init {
    val context = SSLContext.getInstance("TLS")
    context.init(serverKeys(), arrayOf<TrustManager>(trustAll()), SecureRandom())
    server = context.serverSocketFactory.createServerSocket(0, 1, InetAddress.getByName("127.0.0.1")) as SSLServerSocket
    server.soTimeout = 8_000
  }

  fun accept() {
    val accepted = server.accept() as javax.net.ssl.SSLSocket
    accepted.tcpNoDelay = true
    accepted.soTimeout = 5_000
    socket = accepted
    val assembler = FrameAssembler()
    val buffer = ByteArray(8192)
    val input = accepted.inputStream
    while (!accepted.isClosed) {
      val count = try {
        peerReads.incrementAndGet()
        input.read(buffer)
      } catch (error: SocketTimeoutException) {
        0
      } catch (error: Exception) {
        break
      }
      if (count < 0) break
      if (count == 0) continue
      val batch = assembler.offer(buffer, 0, count, System.currentTimeMillis())
      for (frame in batch.frames) {
        val decoded = tryDecodeEnvelope(frame.json)
        if (!decoded.ok) continue
        frames += decoded.message.kind to decoded.message.id
      }
    }
  }

  fun write(bytes: ByteArray) {
    val output = socket?.outputStream ?: return
    output.write(bytes)
    output.flush()
  }

  fun kinds(): List<MessageKind> = frames.map { it.first }

  fun ids(): List<String> = frames.map { it.second }

  fun close() {
    try {
      socket?.close()
    } catch (error: Exception) {
    }
    try {
      server.close()
    } catch (error: Exception) {
    }
  }
}

private class GatedLink(private val writeDelayMs: Long = 0L) : TlsLink {
  private val inbound = GatedInput()
  private val chunks = ArrayDeque<ByteArray>()
  val readBlocked: Boolean get() = inbound.blocked

  override val input: InputStream = inbound
  override val output: OutputStream = object : OutputStream() {
    override fun write(value: Int) = write(byteArrayOf(value.toByte()))

    override fun write(buffer: ByteArray, offset: Int, length: Int) {
      if (writeDelayMs > 0L) Thread.sleep(writeDelayMs)
      val slice = buffer.copyOfRange(offset, offset + length)
      synchronized(chunks) { chunks.addLast(slice) }
    }
  }

  fun push(bytes: ByteArray) = inbound.push(bytes)

  fun writeCount(): Int = synchronized(chunks) { chunks.size }

  fun kinds(): List<MessageKind> {
    val assembler = FrameAssembler()
    val found = mutableListOf<MessageKind>()
    val copies = synchronized(chunks) { chunks.toList() }
    for (chunk in copies) {
      val batch = assembler.offer(chunk, 0, chunk.size, 0L)
      for (frame in batch.frames) {
        val decoded = tryDecodeEnvelope(frame.json)
        if (decoded.ok) found += decoded.message.kind
      }
    }
    return found
  }

  override fun close() = inbound.closeStream()
}

private class GatedInput : InputStream() {
  private val lock = Object()
  private val queue = ArrayDeque<Byte>()
  private var closed = false
  @Volatile var blocked = false

  fun push(bytes: ByteArray) {
    synchronized(lock) {
      for (byte in bytes) queue.addLast(byte)
      lock.notifyAll()
    }
  }

  fun closeStream() {
    synchronized(lock) {
      closed = true
      lock.notifyAll()
    }
  }

  override fun read(): Int {
    val one = ByteArray(1)
    val count = read(one, 0, 1)
    return if (count <= 0) -1 else one[0].toInt() and 0xFF
  }

  override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
    if (length == 0) return 0
    synchronized(lock) {
      while (queue.isEmpty() && !closed) {
        blocked = true
        try {
          lock.wait()
        } catch (error: InterruptedException) {
          closed = true
        } finally {
          blocked = false
        }
      }
      if (queue.isEmpty()) return -1
      var count = 0
      while (count < length && queue.isNotEmpty()) {
        buffer[offset + count] = queue.removeFirst()
        count += 1
      }
      return count
    }
  }
}

private fun serverKeys(): Array<javax.net.ssl.KeyManager> {
  val file = java.io.File(System.getProperty("java.io.tmpdir"), "laz-chaos-host.p12")
  if (!file.isFile || file.length() < 100) {
    val keytool = java.io.File(System.getProperty("java.home"), "bin/keytool")
    val program = if (keytool.isFile) keytool.absolutePath else "keytool"
    val process = ProcessBuilder(
      program, "-genkeypair", "-alias", "host", "-keyalg", "RSA", "-keysize", "2048",
      "-validity", "3650", "-storetype", "PKCS12", "-keystore", file.absolutePath,
      "-storepass", "changeit", "-keypass", "changeit", "-dname", "CN=localhost", "-noprompt"
    ).redirectErrorStream(true).start()
    val log = process.inputStream.readBytes().toString(Charsets.UTF_8)
    if (process.waitFor() != 0) error(log)
  }
  val store = KeyStore.getInstance("PKCS12")
  file.inputStream().use { store.load(it, "changeit".toCharArray()) }
  val factory = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
  factory.init(store, "changeit".toCharArray())
  return factory.keyManagers
}

private fun trustAll(): X509TrustManager {
  return object : X509TrustManager {
    override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {}
    override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {}
    override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
  }
}
