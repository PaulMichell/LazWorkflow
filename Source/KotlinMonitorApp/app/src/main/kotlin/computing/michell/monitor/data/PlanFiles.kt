package computing.michell.monitor.data

/* One plan file per host and path (c) 2026 Michell Computing.

   Pieces append at the stored length when the revision matches. A drop keeps
   that prefix and labels it incomplete. The file is the review copy only
   after the last piece and the length agree. */

import java.io.File

const val PlanIncompleteLabel = "Plan file incomplete"

data class PlanFileState(
  val path: String,
  val revision: String,
  val received: Long,
  val total: Long,
  val complete: Boolean,
  val incomplete: Boolean
)

class PlanFiles(private val root: File) {
  fun state(host: String, path: String): PlanFileState? {
    val meta = metaFile(host, path)
    if (!meta.isFile) return null
    return readMeta(meta, path)
  }

  fun append(host: String, path: String, revision: String, offset: Long, text: String, total: Long, last: Boolean): PlanFileState? {
    if (host.isEmpty() || path.isEmpty() || offset < 0) return null
    val body = bodyFile(host, path)
    val current = state(host, path)
    if (current != null && current.revision != revision) {
      if (offset != 0L) return current.copy(complete = false, incomplete = true)
      body.writeBytes(ByteArray(0))
    }
    val received = if (body.isFile) body.length() else 0L
    if (offset != received) return current
    val bytes = text.toByteArray(Charsets.UTF_8)
    body.parentFile?.mkdirs()
    body.appendBytes(bytes)
    val next = body.length()
    val done = last && total >= 0 && next == total
    val written = PlanFileState(path, revision, next, total, done, !done)
    writeMeta(metaFile(host, path), written)
    return written
  }

  fun noteDrop(host: String, path: String): PlanFileState? {
    val current = state(host, path) ?: return null
    if (current.complete) return current
    val dropped = current.copy(complete = false, incomplete = true)
    writeMeta(metaFile(host, path), dropped)
    return dropped
  }

  fun readReview(host: String, path: String, limit: Int): String {
    val body = bodyFile(host, path)
    if (!body.isFile) return ""
    val bytes = body.readBytes()
    val kept = if (bytes.size <= limit) bytes else bytes.copyOf(limit)
    return kept.toString(Charsets.UTF_8)
  }

  private fun bodyFile(host: String, path: String): File = File(folder(host), fileName(path) + ".txt")

  private fun metaFile(host: String, path: String): File = File(folder(host), fileName(path) + ".meta")

  private fun folder(host: String): File = File(root, safe(host))

  private fun fileName(path: String): String = safe(path).take(80).ifEmpty { "plan" }

  private fun safe(text: String): String {
    val cleaned = text.map { ch -> if (ch.isLetterOrDigit() || ch == '-' || ch == '_') ch else '_' }.joinToString("")
    return cleaned.ifEmpty { "plan" }
  }

  private fun writeMeta(file: File, state: PlanFileState) {
    file.parentFile?.mkdirs()
    file.writeText(listOf(state.revision, state.received.toString(), state.total.toString(), state.complete.toString(), state.incomplete.toString()).joinToString("\n"))
  }

  private fun readMeta(file: File, path: String): PlanFileState? {
    val lines = file.readLines()
    if (lines.size < 5) return null
    return PlanFileState(
      path,
      lines[0],
      lines[1].toLongOrNull() ?: 0L,
      lines[2].toLongOrNull() ?: 0L,
      lines[3] == "true",
      lines[4] == "true"
    )
  }
}
