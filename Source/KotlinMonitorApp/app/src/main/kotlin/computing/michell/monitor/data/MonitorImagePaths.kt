package computing.michell.monitor.data

/* Local monitor image paths (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.normalizeFingerprint
import java.io.File

const val MonitorImageDirectoryName = "monitor-images"

fun hostKey(text: String): String {
  val normalized = normalizeFingerprint(text)
  if (normalized.length == 64) return normalized
  return text.trim()
}

fun monitorImageFile(imageRoot: File, host: String, conversationId: String, imageId: String): File? {
  val hostName = safePathToken(host) ?: return null
  val conversationName = safePathToken(conversationId) ?: return null
  val imageName = safePathToken(imageId) ?: return null
  return File(File(File(imageRoot, hostName), conversationName), imageName)
}

private fun safePathToken(text: String): String? {
  if (text.isEmpty() || text.length > 80 || text == "." || text == "..") return null
  for (ch in text) {
    val ok = ch.isLetterOrDigit() || ch == '-' || ch == '_' || ch == '.'
    if (!ok) return null
  }
  return text
}
