package computing.michell.monitor.net

/* Leaf-certificate pin rules from the old LAN session (c) 2026 Michell Computing.

   An empty pin trusts the endpoint, so a phone can pair by address alone.
   A nonempty pin that does not normalise to 64 hex characters is refused
   before a socket is opened. A 64-hex pin must equal the SHA-256 of the
   leaf certificate DER. Pins and tokens are not logged. */

import android.annotation.SuppressLint
import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.ArrayDeque
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509ExtendedTrustManager
import javax.net.ssl.X509TrustManager

const val PinMismatchName = "pin_mismatch"
const val MalformedPinName = "malformed_pin"
const val PinMismatchMessage = "TLS pin mismatch."
const val MalformedPinMessage = "The certificate pin is not 64 hex characters."

private const val HexDigits = "0123456789abcdef"

/** The UI names a pin failure by this code. Other failures return null. */
fun namedPinError(error: Throwable): String? {
  val seen = HashSet<Throwable>()
  val pending = ArrayDeque<Throwable>()
  pending.add(error)
  while (pending.isNotEmpty()) {
    val current = pending.removeFirst()
    if (!seen.add(current)) continue
    when (current) {
      is PinMismatchException -> return PinMismatchName
      is PinMalformedException -> return MalformedPinName
    }
    current.cause?.let(pending::add)
    current.suppressed.forEach(pending::add)
  }
  return null
}

fun normalizeFingerprint(text: String): String {
  return text.lowercase().filter { it in '0'..'9' || it in 'a'..'f' }
}

fun sha256Hex(bytes: ByteArray): String {
  val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
  val out = StringBuilder(digest.size * 2)
  for (byte in digest) {
    val value = byte.toInt() and 0xFF
    out.append(HexDigits[value shr 4])
    out.append(HexDigits[value and 0x0F])
  }
  return out.toString()
}

/** Empty is allowed. Anything else must normalise to 64 hex characters. */
fun refuseMalformedPin(pin: String) {
  if (pin.isNotEmpty() && normalizeFingerprint(pin).length != 64) throw PinMalformedException(pin)
}

class PinMismatchException(val presented: String) : CertificateException(PinMismatchMessage)

class PinMalformedException(val pin: String) : CertificateException(MalformedPinMessage)

/** The pin armed for the socket that is about to handshake. */
class ArmedPins {
  private val bySocket = java.util.concurrent.ConcurrentHashMap<java.net.Socket, String>()
  private val byThread = ThreadLocal<String>()

  fun arm(socket: java.net.Socket, raw: java.net.Socket, pin: String) {
    bySocket[socket] = pin
    bySocket[raw] = pin
    byThread.set(pin)
  }

  fun of(socket: java.net.Socket?): String? {
    if (socket != null) bySocket[socket]?.let { return it }
    return byThread.get()
  }
}

/**
 * One trust manager for every lane. An empty armed pin trusts the leaf.
 * A 64-hex pin must match that leaf. The pin is read from the socket that
 * is handshaking, not from a value cached when the client was built.
 */
@SuppressLint("CustomX509TrustManager", "TrustAllX509TrustManager")
internal class EndpointTrust(private val armed: ArmedPins) : X509ExtendedTrustManager() {
  override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {
    throw CertificateException("Client certificates are not used.")
  }

  override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, socket: java.net.Socket?) {
    throw CertificateException("Client certificates are not used.")
  }

  override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, engine: SSLEngine?) {
    throw CertificateException("Client certificates are not used.")
  }

  override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
    checkLeaf(chain, null)
  }

  override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?, socket: java.net.Socket?) {
    checkLeaf(chain, socket)
  }

  override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?, engine: SSLEngine?) {
    checkLeaf(chain, null)
  }

  override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()

  private fun checkLeaf(chain: Array<out X509Certificate>?, socket: java.net.Socket?) {
    val leaf = chain?.firstOrNull() ?: throw CertificateException("No server certificate.")
    val pin = armed.of(socket) ?: throw CertificateException("No pin was armed for this socket.")
    if (pin.isEmpty()) return
    val expected = normalizeFingerprint(pin)
    if (expected.length != 64) throw PinMalformedException(pin)
    val presented = sha256Hex(leaf.encoded)
    if (presented != expected) throw PinMismatchException(presented)
  }
}

