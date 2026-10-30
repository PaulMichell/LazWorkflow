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
  val hostId: String = ""
) {
  val paired: Boolean
    get() = clientId.isNotEmpty() && sessionToken.isNotEmpty()
}

internal interface StringMap {
  fun get(key: String): String?
  fun putAll(values: Map<String, String>)
  fun clear()
}

internal class MemoryStringMap : StringMap {
  val values = linkedMapOf<String, String>()
  override fun get(key: String): String? = values[key]
  override fun putAll(values: Map<String, String>) {
    this.values.putAll(values)
  }
  override fun clear() {
    values.clear()
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

  override fun putAll(values: Map<String, String>) {
    try {
      val editor = preferences.edit()
      for ((key, value) in values) editor.putString(key, value)
      editor.apply()
    } catch (error: Exception) {
      preferences = recoverEncryptedPreferences(appContext)
    }
  }

  override fun clear() {
    try {
      preferences.edit().clear().apply()
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

  fun load(): HostRecord {
    val port = values.get(KeyPort)?.toIntOrNull() ?: MonitorLimits.ListenPort
    return HostRecord(
      values.get(KeyAddress).orEmpty(),
      if (port in 1..65535) port else MonitorLimits.ListenPort,
      values.get(KeyFingerprint).orEmpty(),
      values.get(KeyClientId).orEmpty(),
      values.get(KeySessionToken).orEmpty(),
      values.get(KeyHostId).orEmpty()
    )
  }

  fun save(record: HostRecord) {
    values.putAll(recordFields(record))
  }

  fun savePairing(clientId: String, sessionToken: String) {
    val current = load()
    save(current.copy(clientId = clientId, sessionToken = sessionToken))
  }

  fun saveHostId(hostId: String) {
    val current = load()
    save(current.copy(hostId = hostId))
  }

  /** Forgets the pairing on this phone. Does not revoke the desktop client record. */
  fun clear() {
    values.clear()
  }

  companion object {
    const val PreferenceFile = "computing.michell.monitor.host"
    const val KeyAddress = "host_address"
    const val KeyPort = "port"
    const val KeyFingerprint = "fingerprint"
    const val KeyClientId = "client_id"
    const val KeySessionToken = "session_token"
    const val KeyHostId = "host_id"
    val StoredKeys = setOf(KeyAddress, KeyPort, KeyFingerprint, KeyClientId, KeySessionToken, KeyHostId)
  }
}

private fun recordFields(record: HostRecord): Map<String, String> {
  return mapOf(
    HostStore.KeyAddress to record.address,
    HostStore.KeyPort to record.port.toString(),
    HostStore.KeyFingerprint to record.fingerprint,
    HostStore.KeyClientId to record.clientId,
    HostStore.KeySessionToken to record.sessionToken,
    HostStore.KeyHostId to record.hostId
  )
}
