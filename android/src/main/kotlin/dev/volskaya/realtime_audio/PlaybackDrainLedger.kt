package dev.volskaya.realtime_audio

data class PlaybackHeadAdvance(
  val playedChunkIds: List<String>,
  val nextMarkerFrame: Long?,
  val drained: Boolean,
)

/**
 * Pure device-playout ledger. Submitting bytes to `AudioTrack.write()` only
 * marks a chunk writable; ownership ends after the playback head reaches the
 * chunk's exact end-frame marker.
 */
class PlaybackDrainLedger {
  private data class Entry(
    val id: String,
    val endFrame: Long,
    var fullyWritten: Boolean = false,
  )

  private val entries = ArrayDeque<Entry>()
  private var nextFrameOffset = 0L

  val isEmpty: Boolean get() = entries.isEmpty()

  fun enqueue(id: String, frameCount: Int): Long {
    require(frameCount >= 0)
    nextFrameOffset += frameCount
    entries.addLast(Entry(id = id, endFrame = nextFrameOffset))
    return nextFrameOffset - frameCount
  }

  /** Returns the earliest exact marker that can advance device ownership. */
  fun markWritten(id: String): Long? {
    entries.firstOrNull { it.id == id }?.fullyWritten = true
    return nextMarkerFrame()
  }

  fun advancePlaybackHead(renderedFrame: Long): PlaybackHeadAdvance {
    val playedIds = mutableListOf<String>()
    while (true) {
      val next = entries.firstOrNull() ?: break
      if (!next.fullyWritten || renderedFrame < next.endFrame) break
      entries.removeFirst()
      playedIds.add(next.id)
    }

    return PlaybackHeadAdvance(
      playedChunkIds = playedIds,
      nextMarkerFrame = nextMarkerFrame(),
      drained = playedIds.isNotEmpty() && entries.isEmpty(),
    )
  }

  fun reset() {
    entries.clear()
    nextFrameOffset = 0
  }

  private fun nextMarkerFrame(): Long? = entries.firstOrNull()?.takeIf { it.fullyWritten }?.endFrame
}
