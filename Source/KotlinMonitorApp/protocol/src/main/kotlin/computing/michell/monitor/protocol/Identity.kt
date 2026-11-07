package computing.michell.monitor.protocol

/* Epoch and cursor continuity. Turn index and liveRevision are not the key (c) 2026 Michell Computing. */

enum class CursorStep {
  First,
  Progress,
  Duplicate,
  Gap,
  NewEpoch
}

/** 32 lowercase hex. This is the hostFingerprint of plan item 5.2, not the TLS certificate. */
fun hostIdIsValid(text: String): Boolean {
  if (text.length != 32) return false
  for (ch in text) {
    if (ch !in '0'..'9' && ch !in 'a'..'f') return false
  }
  return true
}

/** `current` is a file slot, not a conversation. */
fun conversationIdIsIdentity(text: String): Boolean {
  return text.isNotEmpty() && text != "current"
}

data class MirrorPlace(
  val epoch: String = "",
  val cursor: Long = 0,
  val catchingUp: Boolean = false,
  val announcedEpoch: String = "",
  val conversationId: String = "",
  val projectRoot: String = "",
  val title: String = ""
)

fun cursorStep(committedEpoch: String, committedCursor: Long, epoch: String, cursor: Long): CursorStep {
  if (epoch.isEmpty()) return CursorStep.Duplicate
  if (committedEpoch.isEmpty()) return CursorStep.First
  if (epoch != committedEpoch) return CursorStep.NewEpoch
  if (cursor <= committedCursor) return CursorStep.Duplicate
  if (cursor == committedCursor + 1L) return CursorStep.Progress
  return CursorStep.Gap
}

/** A new epoch does not replace the screen. Catchup does that.
 *  An empty committed epoch must not adopt the host epoch. Resume of that adopted epoch at cursor 0
 *  is an empty events list, and the phone never receives the model or the signed-in flag.
 *  hasScreen does not change that: a cached screen still waits for catchup. cursor is the host tip, not the phone's. */
@Suppress("UNUSED_PARAMETER")
fun noteHelloIdentity(
  place: MirrorPlace,
  epoch: String,
  cursor: Long,
  conversationId: String,
  projectRoot: String,
  title: String,
  hasScreen: Boolean
): MirrorPlace {
  if (epoch.isEmpty()) return place
  if (place.epoch.isEmpty()) {
    return place.copy(
      catchingUp = true,
      announcedEpoch = epoch,
      conversationId = if (conversationId.isNotEmpty()) conversationId else place.conversationId,
      projectRoot = if (projectRoot.isNotEmpty()) projectRoot else place.projectRoot,
      title = if (title.isNotEmpty()) title else place.title
    )
  }
  if (epoch == place.epoch) return place
  return place.copy(catchingUp = true, announcedEpoch = epoch)
}
