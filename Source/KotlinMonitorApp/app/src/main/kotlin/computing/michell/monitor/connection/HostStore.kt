package computing.michell.monitor.connection

/* Encrypted pairing store for the monitor phone (c) 2026 Michell Computing.

   The five fields are the host endpoint and the monitor session credential.
   There is no model provider secret in this store. clear() forgets the
   pairing on this phone only. The desktop client record stays until that
   host revokes it. */

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import computing.michell.monitor.protocol.MonitorLimits
import java.security.KeyStore

data class HostRecord(
  val address: String = "",
  val port: Int = MonitorLimits.ListenPort,
  val fingerprint: String = "",
  val clientId: String = "",
  val sessionToken: String = "",
  val hostId: String = "",
  val uncertainPin: Boolean = false
) {
  val paired: Boolean
    get() = clientId.isNotEmpty() && sessionToken.isNotEmpty()
}

internal interface StringMap {
  fun get(key: String): String?
  fun update(values: Map<String, String>, remove: Set<String> = emptySet())
}

internal class MemoryStringMap : StringMap {
  val values = linkedMapOf<String, String>()
  override fun get(key: String): String? = values[key]
  override fun update(values: Map<String, String>, remove: Set<String>) {
    remove.forEach(this.values::remove)
    this.values.putAll(values)
  }
}

private class EncryptedStringMap(context: Context) : StringMap {
  private val appContext = context.applicationContext
  private var preferences: SharedPreferences = encryptedPreferences(appContext)

  override fun get(key: String): String? {
    return try {
      preferences.getString(key, null)
    } catch (error: Exception) {
      // A key the keystore can no longer open must not kill the process on the next launch.
      preferences = recoverEncryptedPreferences(appContext)
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
      preferences = recoverEncryptedPreferences(appContext)
    }
  }

}

private fun encryptedPreferences(context: Context): SharedPreferences {
  return try {
    openEncryptedPreferences(context)
  } catch (error: Exception) {
    recoverEncryptedPreferences(context)
  }
}

/** Drops a store the keystore can no longer open, then creates an empty one. */
private fun recoverEncryptedPreferences(context: Context): SharedPreferences {
  forgetEncryptedHostStore(context)
  return try {
    openEncryptedPreferences(context)
  } catch (error: Exception) {
    context.getSharedPreferences(HostStore.PreferenceFile + ".plain", Context.MODE_PRIVATE)
  }
}

private fun openEncryptedPreferences(context: Context): SharedPreferences {
  val masterKey = MasterKey.Builder(context)
    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
    .build()
  return EncryptedSharedPreferences.create(
    context,
    HostStore.PreferenceFile,
    masterKey,
    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
  )
}

private fun forgetEncryptedHostStore(context: Context) {
  try {
    context.deleteSharedPreferences(HostStore.PreferenceFile)
  } catch (error: Exception) {
    context.getSharedPreferences(HostStore.PreferenceFile, Context.MODE_PRIVATE).edit().clear().commit()
  }
  try {
    val store = KeyStore.getInstance("AndroidKeyStore")
    store.load(null)
    store.deleteEntry(MasterKey.DEFAULT_MASTER_KEY_ALIAS)
  } catch (error: Exception) {
    // The alias may already be gone. Opening must still continue.
  }
}

class HostStore internal constructor(private val values: StringMap) {
  constructor(context: Context) : this(EncryptedStringMap(context.applicationContext))

  init {
    if (values.get(KeySelectedAddress) == null) {
      val legacy = readRecord("", values.get(KeyAddress).orEmpty().trim(),
        values.get(KeyPort)?.toIntOrNull()?.takeIf { it in 1..65535 } ?: MonitorLimits.ListenPort)
      // An old switch kept the previous pin and host ID but cleared both credentials.
      val record = legacy.copy(uncertainPin = legacy.fingerprint.isNotEmpty() && !legacy.paired)
      values.update(fields(record) + selection(record), StoredKeys)
    }
  }

  private fun prefix(address: String, port: Int) = "endpoint/$port/${address.trim()}/"

  private fun readRecord(prefix: String, address: String, port: Int) = HostRecord(
    address, port, values.get(prefix + KeyFingerprint).orEmpty(), values.get(prefix + KeyClientId).orEmpty(),
    values.get(prefix + KeySessionToken).orEmpty(), values.get(prefix + KeyHostId).orEmpty(),
    values.get(prefix + KeyUncertain) == "true"
  )

  private fun selection(record: HostRecord) =
    mapOf(KeySelectedAddress to record.address.trim(), KeySelectedPort to record.port.toString())

  private fun fields(record: HostRecord) = mapOf(
    KeyFingerprint to record.fingerprint, KeyClientId to record.clientId, KeySessionToken to record.sessionToken,
    KeyHostId to record.hostId, KeyUncertain to record.uncertainPin.toString()
  ).mapKeys { prefix(record.address, record.port) + it.key }

  @Synchronized fun lookup(address: String, port: Int) = readRecord(prefix(address, port), address.trim(), port)

  @Synchronized fun load(): HostRecord = lookup(values.get(KeySelectedAddress).orEmpty(),
    values.get(KeySelectedPort)?.toIntOrNull() ?: MonitorLimits.ListenPort)

  @Synchronized fun select(address: String, port: Int) {
    values.update(selection(HostRecord(address, port)))
  }

  @Synchronized fun save(record: HostRecord) {
    values.update(fields(record) + selection(record))
  }

  @Synchronized fun saveEndpoint(record: HostRecord) {
    values.update(fields(record))
  }

  @Synchronized fun clear() {
    values.update(selection(HostRecord()), fields(load()).keys)
  }

  companion object {
    const val PreferenceFile = "computing.michell.monitor.host"
    private const val KeySelectedAddress = "selected_address"
    private const val KeySelectedPort = "selected_port"
    private const val KeyUncertain = "uncertain_pin"
    const val KeyAddress = "host_address"
    const val KeyPort = "port"
    const val KeyFingerprint = "fingerprint"
    const val KeyClientId = "client_id"
    const val KeySessionToken = "session_token"
    const val KeyHostId = "host_id"
    val StoredKeys = setOf(KeyAddress, KeyPort, KeyFingerprint, KeyClientId, KeySessionToken, KeyHostId)
  }
}
