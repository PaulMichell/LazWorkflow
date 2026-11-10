package computing.michell.monitor.ui

/* Incremental screen watch (c) 2026 Michell Computing.

   Room still emits the whole block list. Only a turn whose rows changed is a
   new instance. An image is decoded when its id or file length changes, and
   a decode already in flight for that id is cancelled when the file is replaced. */

import computing.michell.monitor.data.BlockRecord
import computing.michell.monitor.data.BlockRepairRecord
import computing.michell.monitor.data.ConversationRecord
import computing.michell.monitor.data.ImageRecord
import computing.michell.monitor.data.TurnRecord
import computing.michell.monitor.data.documentFromRows
import computing.michell.monitor.protocol.WireTurn
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import java.io.File

/** File length the decode gate compares. A missing file is not a decoded length. */
fun imageFileLength(image: ImageRecord): Long {
  if (image.filePath.isEmpty()) return -1L
  val file = File(image.filePath)
  if (!file.isFile) return -1L
  return file.length()
}

/** Same id and same rows keep the instance the screen already holds. */
fun reuseUnchangedTurns(previous: List<WireTurn>, next: List<WireTurn>): List<WireTurn> {
  if (previous.isEmpty() || next.isEmpty()) return next
  val kept = HashMap<String, WireTurn>(previous.size)
  for (turn in previous) if (turn.id.isNotEmpty()) kept[turn.id] = turn
  return next.map { turn ->
    val prior = kept[turn.id]
    if (prior != null && prior == turn) prior else turn
  }
}

private class ImageFlight(val job: Job, val length: Long)

class ScreenAssembler {
  private var shown = emptyList<WireTurn>()
  private val decodedLength = HashMap<String, Long>()
  private val flights = HashMap<String, ImageFlight>()

  fun board(
    host: String,
    conversationId: String,
    turns: List<TurnRecord>,
    blocks: List<BlockRecord>,
    repairs: List<BlockRepairRecord>,
    images: List<ImageRecord>
  ): BoardContent {
    val document = documentFromRows(turns, blocks, repairs, images)
    val flat = reuseUnchangedTurns(shown, document.turns)
    shown = flat
    val live = flat.lastOrNull { turn -> turn.live }
    val stored = if (live == null) flat else flat.filter { turn -> turn.id != live.id }
    return BoardContent(host, conversationId, stored, live)
  }

  /**
   * Starts a decode only for an id whose file length is new. A length change
   * cancels the decode already running for that id. Gone ids are cancelled too.
   */
  fun offerImages(
    scope: CoroutineScope,
    images: List<ImageRecord>,
    lengthOf: (ImageRecord) -> Long,
    decode: suspend (ImageRecord) -> Unit
  ) {
    val present = HashSet<String>()
    for (image in images) {
      if (image.id.isEmpty()) continue
      val length = lengthOf(image)
      if (length < 0L) continue
      present += image.id
      val flight = flights[image.id]
      if (flight != null && flight.length == length && flight.job.isActive) continue
      if (decodedLength[image.id] == length && (flight == null || !flight.job.isActive)) continue
      flight?.job?.cancel()
      val job = scope.launch {
        try {
          decode(image)
          val current = flights[image.id]
          if (current != null && current.job === coroutineContext[Job]) decodedLength[image.id] = length
        } catch (error: CancellationException) {
          throw error
        } catch (error: Exception) {
          // A bad file must not stop the screen watch.
        } finally {
          val current = flights[image.id]
          if (current != null && current.job === coroutineContext[Job]) flights.remove(image.id)
        }
      }
      flights[image.id] = ImageFlight(job, length)
    }
    for (id in flights.keys.toList()) {
      if (id in present) continue
      flights.remove(id)?.job?.cancel()
      decodedLength.remove(id)
    }
  }
}

/** Collects the store on [Dispatchers.IO]. Cancelling the job cancels in-flight decodes. */
fun watchStoredScreen(
  scope: CoroutineScope,
  turns: Flow<List<TurnRecord>>,
  blocks: Flow<List<BlockRecord>>,
  images: Flow<List<ImageRecord>>,
  repairs: Flow<List<BlockRepairRecord>>,
  row: Flow<ConversationRecord?>,
  host: String,
  conversationId: String,
  lengthOf: (ImageRecord) -> Long,
  onBoard: suspend (BoardContent, ConversationRecord?) -> Unit,
  decode: suspend (ImageRecord) -> Unit
): Job {
  return scope.launch(Dispatchers.IO) {
    val assembler = ScreenAssembler()
    combine(turns, blocks, images, repairs, row) { turnRows, blockRows, imageRows, repairRows, conversation ->
      ScreenSnapshot(turnRows, blockRows, imageRows, repairRows, conversation)
    }.collect { snapshot ->
      val board = assembler.board(
        host, conversationId, snapshot.turns, snapshot.blocks, snapshot.repairs, snapshot.images
      )
      onBoard(board, snapshot.row)
      assembler.offerImages(this, snapshot.images, lengthOf, decode)
    }
  }
}

private data class ScreenSnapshot(
  val turns: List<TurnRecord>,
  val blocks: List<BlockRecord>,
  val images: List<ImageRecord>,
  val repairs: List<BlockRepairRecord>,
  val row: ConversationRecord?
)
