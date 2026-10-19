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

data class HostRecord(
  val address: String = "",
  val port: Int = MonitorLimits.ListenPort,
  val fingerprint: String = "",
  val clientId: String = "",
  val sessionToken: String = ""
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
  private val preferences: SharedPreferences = encryptedPreferences(context)

  override fun get(key: String): String? = preferences.getString(key, null)

  override fun putAll(values: Map<String, String>) {
    val editor = preferences.edit()
    for ((key, value) in values) editor.putString(key, value)
    editor.apply()
  }

  override fun clear() {
    preferences.edit().clear().apply()
  }
}

private fun encryptedPreferences(context: Context): SharedPreferences {
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

class HostStore internal constructor(private val values: StringMap) {
  constructor(context: Context) : this(EncryptedStringMap(context.applicationContext))

  fun load(): HostRecord {
    val port = values.get(KeyPort)?.toIntOrNull() ?: MonitorLimits.ListenPort
    return HostRecord(
      values.get(KeyAddress).orEmpty(),
      if (port in 1..65535) port else MonitorLimits.ListenPort,
      values.get(KeyFingerprint).orEmpty(),
      values.get(KeyClientId).orEmpty(),
      values.get(KeySessionToken).orEmpty()
    )
  }

  fun save(record: HostRecord) {
    values.putAll(recordFields(record))
  }

  fun saveEndpoint(address: String, port: Int, fingerprint: String) {
    val current = load()
    save(current.copy(address = address, port = port, fingerprint = fingerprint))
  }

  fun savePairing(clientId: String, sessionToken: String) {
    val current = load()
    save(current.copy(clientId = clientId, sessionToken = sessionToken))
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
    val StoredKeys = setOf(KeyAddress, KeyPort, KeyFingerprint, KeyClientId, KeySessionToken)
  }
}

private fun recordFields(record: HostRecord): Map<String, String> {
  return mapOf(
    HostStore.KeyAddress to record.address,
    HostStore.KeyPort to record.port.toString(),
    HostStore.KeyFingerprint to record.fingerprint,
    HostStore.KeyClientId to record.clientId,
    HostStore.KeySessionToken to record.sessionToken
  )
}
