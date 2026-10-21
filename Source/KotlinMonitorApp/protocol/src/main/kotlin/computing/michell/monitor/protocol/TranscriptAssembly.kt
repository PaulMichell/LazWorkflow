package computing.michell.monitor.protocol

/* Join transcript fragments into display blocks (c) 2026 Michell Computing. */

/** Frames are walked in the order given. A block stays where its id first appeared. */
fun assembleTranscriptBlocks(frames: List<List<WireBlock>>): List<WireBlock> {
  val order = mutableListOf<String>()
  val grouped = mutableMapOf<String, MutableList<WireBlock>>()
  var loose = 0
  for (frame in frames) {
    for (block in frame) {
      val key = if (block.blockId.isEmpty()) {
        loose += 1
        "\u0000" + loose.toString()
      } else {
        block.blockId
      }
      if (key !in grouped) {
        order += key
        grouped[key] = mutableListOf()
      }
      grouped.getValue(key).add(block)
    }
  }
  val assembled = mutableListOf<WireBlock>()
  for (key in order) {
    val joined = joinTranscriptBlock(grouped.getValue(key)) ?: continue
    assembled += joined
  }
  return assembled
}

private fun joinTranscriptBlock(fragments: List<WireBlock>): WireBlock? {
  val revision = fragments.maxOf { it.revision }
  val selected = fragments.filter { it.revision == revision }
  if (!partCountAgrees(selected)) return null
  val byPart = linkedMapOf<Int, WireBlock>()
  for (fragment in selected) {
    if (fragment.part !in byPart) byPart[fragment.part] = fragment
  }
  val prefix = mutableListOf<WireBlock>()
  var expected = 1
  while (byPart.containsKey(expected)) {
    prefix += byPart.getValue(expected)
    expected += 1
  }
  if (prefix.isEmpty()) return null
  val body = StringBuilder()
  for (fragment in prefix) body.append(fragment.body)
  val first = prefix.first()
  val last = prefix.last()
  return first.copy(
    body = body.toString(),
    title = last.title.ifEmpty { first.title },
    toolName = last.toolName.ifEmpty { first.toolName },
    toolId = last.toolId.ifEmpty { first.toolId },
    running = last.running,
    ok = last.ok,
    durationMs = if (last.durationMs > 0) last.durationMs else first.durationMs,
    images = first.images,
    truncated = prefix.any { it.truncated },
    part = 1,
    partCount = 1,
    revision = revision
  )
}

private fun partCountAgrees(fragments: List<WireBlock>): Boolean {
  val partCount = fragments.first().partCount
  if (partCount < 1) return false
  return fragments.all { fragment ->
    fragment.partCount == partCount && fragment.part in 1..partCount
  }
}
