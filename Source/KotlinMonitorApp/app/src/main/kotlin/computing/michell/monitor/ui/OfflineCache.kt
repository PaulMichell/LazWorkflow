package computing.michell.monitor.ui

/* Last session kept for offline browsing (c) 2026 Michell Computing. */

import computing.michell.monitor.connection.ReconnectingBanner
import computing.michell.monitor.protocol.OfflineCacheDocument
import computing.michell.monitor.protocol.decodeOfflineCache
import computing.michell.monitor.protocol.encodeOfflineCache
import java.io.File

const val OfflineBanner = "Offline"
const val NoAddressBanner = "Set the desktop address in Settings."

fun bannerIsStatus(banner: String): Boolean {
  return banner == OfflineBanner || banner == NoAddressBanner || banner == ConnectingBanner || banner == ReconnectingBanner
}

fun offlineDocument(ui: MonitorUi): OfflineCacheDocument {
  return OfflineCacheDocument(
    ui.turns,
    ui.history.values.toList(),
    ui.live,
    ui.planPath,
    ui.planTitle,
    ui.planRows,
    ui.selectedPlan,
    ui.draft
  )
}

fun worthCaching(ui: MonitorUi): Boolean {
  return ui.turns.isNotEmpty() || ui.history.isNotEmpty() || ui.live != null || ui.planRows.isNotEmpty() || ui.draft.isNotEmpty()
}

/** Restores browseable rows. Remote actions stay off until a live snapshot arrives. */
fun applyOfflineCache(state: MonitorUi, document: OfflineCacheDocument, hasAddress: Boolean): MonitorUi {
  val hasBrowse = document.turns.isNotEmpty() || document.history.isNotEmpty() || document.live != null || document.planRows.isNotEmpty()
  val banner = when {
    !hasAddress -> NoAddressBanner
    hasBrowse -> OfflineBanner
    else -> ""
  }
  return state.copy(
    turns = document.turns,
    history = document.history.associateBy { it.turnIndex },
    live = document.live,
    planPath = document.planPath,
    planTitle = document.planTitle,
    planRows = document.planRows,
    planRunning = false,
    selectedPlan = document.selectedPlan,
    draft = document.draft,
    disconnected = true,
    reachedLive = false,
    pairHold = false,
    settingsOpen = false,
    approval = null,
    approvalOpen = false,
    banner = banner,
    view = clearRemoteActions(emptyView())
  )
}

class OfflineStore(private val file: File) {
  fun load(): OfflineCacheDocument? {
    if (!file.isFile) return null
    return try {
      decodeOfflineCache(file.readText())
    } catch (error: Exception) {
      null
    }
  }

  fun clear() {
    if (file.isFile) file.delete()
    val directory = file.parentFile ?: return
    File(directory, file.name + ".tmp").delete()
  }

  fun save(text: String) {
    val directory = file.parentFile
    if (directory != null && !directory.isDirectory) directory.mkdirs()
    val temporary = File(directory, file.name + ".tmp")
    temporary.writeText(text)
    if (!temporary.renameTo(file)) {
      file.writeText(text)
      temporary.delete()
    }
  }
}
