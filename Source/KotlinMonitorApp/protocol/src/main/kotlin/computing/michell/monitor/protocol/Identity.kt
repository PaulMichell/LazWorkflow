package computing.michell.monitor.protocol

/* Epoch and cursor continuity. Turn index and liveRevision are not the key (c) 2026 Michell Computing. */

enum class CursorStep {
  First,
  Progress,
  Duplicate,
  Gap,
  NewEpoch
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

/** A new epoch does not replace the screen. Catchup does that. */
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
  if (place.epoch.isEmpty() && !hasScreen) {
    return place.copy(
      epoch = epoch,
      cursor = 0,
      catchingUp = false,
      announcedEpoch = "",
      conversationId = conversationId,
      projectRoot = projectRoot,
      title = title
    )
  }
  if (place.epoch.isNotEmpty() && epoch == place.epoch) return place
  return place.copy(catchingUp = true, announcedEpoch = epoch)
}

/** Same epoch and a higher next cursor is progress. A lower or equal cursor is ignored. */
fun notePatchIdentity(place: MirrorPlace, epoch: String, cursor: Long): MirrorPlace {
  if (place.catchingUp) return place
  return when (cursorStep(place.epoch, place.cursor, epoch, cursor)) {
    CursorStep.Progress -> place.copy(epoch = epoch, cursor = cursor)
    CursorStep.First -> place.copy(epoch = epoch, cursor = cursor)
    CursorStep.NewEpoch -> place.copy(catchingUp = true, announcedEpoch = epoch)
    CursorStep.Duplicate, CursorStep.Gap -> place
  }
}

/**
 * Null means do not apply the body and do not move the cursor.
 * A snapshot may jump a same-epoch gap. Events may not.
 */
fun noteCatchupIdentity(place: MirrorPlace, epoch: String, cursor: Long, mode: String): MirrorPlace? {
  if (epoch.isEmpty()) return null
  val arriving = place.catchingUp && (place.announcedEpoch.isEmpty() || epoch == place.announcedEpoch)
  val step = cursorStep(place.epoch, place.cursor, epoch, cursor)
  if (arriving || place.epoch.isEmpty() || step == CursorStep.NewEpoch) {
    return place.copy(epoch = epoch, cursor = cursor, catchingUp = false, announcedEpoch = "")
  }
  if (step == CursorStep.Duplicate) return null
  if (step == CursorStep.Gap && mode != "snapshot") return null
  return place.copy(epoch = epoch, cursor = cursor, catchingUp = false, announcedEpoch = "")
}
