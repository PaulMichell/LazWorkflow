package computing.michell.monitor.protocol.chaos

/* Scripted TLS host for the chaos fixture (c) 2026 Michell Computing.

   One fixed seed chooses disconnects, short delays, a duplicated frame,
   reordered acks, and a log frame dropped on the wire. The host log still
   holds every event, so the next connection restores the same final model.
   A command id is executed once. */

import computing.michell.monitor.protocol.FrameAssembler
import computing.michell.monitor.protocol.tryDecodeEnvelope
import computing.michell.monitor.protocol.tryEncodeFrame
import java.io.File
import java.net.InetAddress
import java.security.KeyStore
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.Random
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.SSLSocket
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

const val ChaosSeed = 20261029L
const val ChaosIterations = 1000
const val ChaosConversationId = "conv-1"
const val ChaosStreamId = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const val ChaosCommandId = "send-1"
const val ChaosFinalBody = "hello"
const val ChaosFinalSeq = 4L

data class ChaosFaults(
  val disconnectAfter: Int,
  val delayMs: Int,
  val duplicateIndex: Int,
  val reorderAcks: Boolean,
  val dropLogIndex: Int
)

fun chaosFaults(seed: Long, iteration: Int): ChaosFaults {
  val random = Random(seed xor iteration.toLong())
  val disconnect = if (random.nextInt(5) == 0) random.nextInt(3) + 1 else 0
  val duplicate = if (random.nextBoolean()) random.nextInt(4) else -1
  val drop = if (random.nextInt(4) == 0) random.nextInt(4) else -1
  return ChaosFaults(disconnect, random.nextInt(3), duplicate, random.nextBoolean(), drop)
}

fun chaosEventJson(seq: Long): String {
  val data = when (seq) {
    1L -> """{"turn_id":"turn-1","turn_index":1,"mode":"build","prompt":"ask","created_at":"2026-10-29T00:00:00Z"}"""
    2L -> """{"turn_id":"turn-1","block_id":"block-1","ordinal":1,"kind":"answer","title":"Answer"}"""
    3L -> """{"block_id":"block-1","offset":0,"text":"hello"}"""
    else -> """{"block_id":"block-1","state":"ok","duration_ms":1}"""
  }
  val kind = when (seq) {
    1L -> "turn_open"
    2L -> "block_open"
    3L -> "block_append"
    else -> "block_close"
  }
  return """{"conversation_id":"$ChaosConversationId","stream_id":"$ChaosStreamId","seq":$seq,"event":"$kind","data":$data}"""
}

fun chaosEventFrame(seq: Long): ByteArray = framed("""{"v":2,"id":"e$seq","type":"event","payload":${chaosEventJson(seq)}}""")

fun chaosStatusFrame(busy: Boolean): ByteArray {
  val json = """{"v":2,"id":"status","type":"status","payload":{"available":true,"busy":$busy,"sending":false,"mode_locked":false,"plan_running":false,"phase":"idle","status_text":"","model":"","backend":"","signed_in":true,"approval_caption":"","effort":"","skill":"","context_text":"","can_send":true,"can_steer":false,"can_stop":false,"can_change_mode":true,"remote_approval":false,"error_text":"","elapsed_ms":0}}"""
  return framed(json)
}

fun chaosCommandFrame(): ByteArray {
  return framed("""{"v":2,"id":"$ChaosCommandId","type":"send","payload":{"text":"ask"}}""")
}

private fun framed(json: String): ByteArray {
  val encoded = tryEncodeFrame(json)
  if (!encoded.ok) error("frame was rejected")
  return encoded.bytes
}

class ScriptedTlsHost {
  private val server: SSLServerSocket
  private val seenCommands = HashSet<String>()
  var executions = 0
    private set
  var lastAck = 0L
    private set

  val port: Int get() = server.localPort

  init {
    val context = SSLContext.getInstance("TLS")
    context.init(keyManagers(), arrayOf<TrustManager>(trustAll()), SecureRandom())
    server = context.serverSocketFactory.createServerSocket(0, 50, InetAddress.getByName("127.0.0.1")) as SSLServerSocket
    server.soTimeout = 8_000
  }

  fun acceptAndPlay(iteration: Int, fullLog: Boolean) {
    val socket = server.accept() as SSLSocket
    socket.soTimeout = 2_000
    socket.use { play(it, iteration, fullLog) }
  }

  fun close() {
    server.close()
  }

  fun resetCommands() {
    seenCommands.clear()
    executions = 0
    lastAck = 0L
  }

  private fun play(socket: SSLSocket, iteration: Int, fullLog: Boolean) {
    val faults = chaosFaults(ChaosSeed, iteration)
    val frames = ArrayList<ByteArray>()
    for (seq in 1..4) {
      if (!fullLog && seq - 1 == faults.dropLogIndex) continue
      frames += chaosEventFrame(seq.toLong())
    }
    if (!fullLog && faults.duplicateIndex in frames.indices) frames += frames[faults.duplicateIndex]
    if (fullLog || faults.disconnectAfter == 0) {
      frames += chaosStatusFrame(true)
      frames += chaosStatusFrame(false)
    }
    val output = socket.outputStream
    var sent = 0
    for (frame in frames) {
      if (!fullLog && faults.disconnectAfter > 0 && sent == faults.disconnectAfter) return
      if (faults.delayMs > 0) Thread.sleep(faults.delayMs.toLong())
      output.write(frame)
      output.flush()
      sent += 1
    }
    readClient(socket.inputStream, faults.reorderAcks)
  }

  private fun readClient(input: java.io.InputStream, reorderAcks: Boolean) {
    val assembler = FrameAssembler()
    val buffer = ByteArray(4096)
    val acks = ArrayList<Long>()
    val started = System.currentTimeMillis()
    while (System.currentTimeMillis() - started < 1_000 && executions == 0) {
      val count = try {
        input.read(buffer)
      } catch (error: Exception) {
        break
      }
      if (count <= 0) break
      val assembled = assembler.offer(buffer, 0, count, started)
      for (frame in assembled.frames) {
        val message = tryDecodeEnvelope(frame)
        if (!message.ok) continue
        if (message.message.id == ChaosCommandId || message.message.kind.wireName == "send") noteCommand(ChaosCommandId)
        val seq = message.message.payloadJson.substringAfter("\"seq\":", "").takeWhile { it.isDigit() }
        if (seq.isNotEmpty()) acks += seq.toLong()
      }
    }
    val ordered = if (reorderAcks && acks.size >= 2) {
      val swapped = acks.toMutableList()
      val first = swapped[0]
      swapped[0] = swapped[1]
      swapped[1] = first
      swapped
    } else {
      acks
    }
    if (ordered.isNotEmpty()) lastAck = ordered.maxOrNull() ?: 0L
  }

  private fun noteCommand(id: String) {
    if (seenCommands.add(id)) executions += 1
  }
}

fun chaosClientContext(): SSLContext {
  val context = SSLContext.getInstance("TLS")
  context.init(null, arrayOf<TrustManager>(trustAll()), SecureRandom())
  return context
}

private fun keyManagers(): Array<javax.net.ssl.KeyManager> {
  val file = File(System.getProperty("java.io.tmpdir"), "laz-chaos-host.p12")
  if (!file.isFile || file.length() < 100) {
    val keytool = File(System.getProperty("java.home"), "bin/keytool")
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
