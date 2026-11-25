package computing.michell.monitor.net

/* Pairings stored by endpoint. The token lives in encrypted preferences.
   (c) 2026 Michell Computing.

   Catalogue 3 pairings are not read. Address and port select the record.
   Each record keeps its own pin, client id and token. */

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import computing.michell.monitor.ui.model.MonitorLimits
import java.security.KeyStore

data class EndpointPairing(
  val address: String = "",
  val port: Int = MonitorLimits.ListenPort,
  val pin: String = "",
  val clientId: String = "",
  val token: String = ""
) {
  val paired: Boolean
    get() = clientId.isNotEmpty() && token.isNotEmpty()
}

/** The pin for one host, read when a call starts and again at the handshake. */
fun interface PinSource {
  fun pinFor(host: String, port: Int): String
}

internal interface PairingMap {
  fun get(key: String): String?
  fun update(values: Map<String, String>, remove: Set<String> = emptySet())
}

internal class MemoryPairingMap : PairingMap {
  val values = linkedMapOf<String, String>()

  override fun get(key: String): String? = values[key]

  override fun update(values: Map<String, String>, remove: Set<String>) {
    remove.forEach(this.values::remove)
    this.values.putAll(values)
  }
}

class PairingStore internal constructor(private val values: PairingMap) : PinSource {
  constructor(context: Context) : this(EncryptedPairingMap(context.applicationContext))

  @Synchronized
  fun lookup(address: String, port: Int): EndpointPairing {
    val host = address.trim()
    val prefix = prefix(host, port)
    return EndpointPairing(
      host,
      port,
      values.get(prefix + KeyPin).orEmpty(),
      values.get(prefix + KeyClientId).orEmpty(),
      values.get(prefix + KeyToken).orEmpty()
    )
  }

  @Synchronized
  fun selected(): EndpointPairing {
    val address = values.get(KeySelectedAddress).orEmpty()
    val port = values.get(KeySelectedPort)?.toIntOrNull() ?: MonitorLimits.ListenPort
    return lookup(address, port)
  }

  @Synchronized
  fun save(pairing: EndpointPairing) {
    val record = pairing.copy(address = pairing.address.trim())
    values.update(fields(record) + selection(record))
  }

  @Synchronized
  fun forget(address: String, port: Int) {
    values.update(emptyMap(), fields(EndpointPairing(address.trim(), port)).keys)
  }

  override fun pinFor(host: String, port: Int): String = lookup(host, port).pin

  private fun prefix(address: String, port: Int) = "endpoint/$port/$address/"

  private fun selection(record: EndpointPairing) = mapOf(
    KeySelectedAddress to record.address,
    KeySelectedPort to record.port.toString()
  )

  private fun fields(record: EndpointPairing) = mapOf(
    KeyPin to record.pin,
    KeyClientId to record.clientId,
    KeyToken to record.token
  ).mapKeys { prefix(record.address, record.port) + it.key }

  companion object {
    const val PreferenceFile = "computing.michell.monitor.pairings"
    private const val KeySelectedAddress = "selected_address"
    private const val KeySelectedPort = "selected_port"
    private const val KeyPin = "pin"
    private const val KeyClientId = "client_id"
    private const val KeyToken = "token"
  }
}

/** The token, pin and client id share this file so the token is never plaintext. */
private class EncryptedPairingMap(context: Context) : PairingMap {
  private val appContext = context.applicationContext
  private var preferences: SharedPreferences = encryptedPreferences(appContext)

  override fun get(key: String): String? {
    return try {
      preferences.getString(key, null)
    } catch (error: Exception) {
      preferences = recover(appContext)
      null
    }
  }

  override fun update(values: Map<String, String>, remove: Set<String>) {
    try {
      val editor = preferences.edit()
      remove.forEach(editor::remove)
      for ((key, value) in values) editor.putString(key, value)
      editor.apply()
    } catch (error: Exception) {
      preferences = recover(appContext)
    }
  }
}

private fun encryptedPreferences(context: Context): SharedPreferences {
  return try {
    openEncryptedPreferences(context)
  } catch (error: Exception) {
    recover(context)
  }
}

private fun recover(context: Context): SharedPreferences {
  forgetEncryptedPairings(context)
  return try {
    openEncryptedPreferences(context)
  } catch (error: Exception) {
    context.getSharedPreferences(PairingStore.PreferenceFile + ".plain", Context.MODE_PRIVATE)
  }
}

private const val PairingKeyAlias = "computing.michell.monitor.pairings.key"

private fun openEncryptedPreferences(context: Context): SharedPreferences {
  val masterKey = MasterKey.Builder(context, PairingKeyAlias)
    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
    .build()
  return EncryptedSharedPreferences.create(
    context,
    PairingStore.PreferenceFile,
    masterKey,
    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
  )
}

private fun forgetEncryptedPairings(context: Context) {
  try {
    context.deleteSharedPreferences(PairingStore.PreferenceFile)
  } catch (error: Exception) {
    context.getSharedPreferences(PairingStore.PreferenceFile, Context.MODE_PRIVATE).edit().clear().commit()
  }
  try {
    val store = KeyStore.getInstance("AndroidKeyStore")
    store.load(null)
    store.deleteEntry(PairingKeyAlias)
  } catch (error: Exception) {
    // The alias may already be gone. Opening must still continue.
  }
}
