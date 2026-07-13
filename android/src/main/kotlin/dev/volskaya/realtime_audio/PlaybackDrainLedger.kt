package dev.volskaya.realtime_audio

data class PlaybackHeadAdvance(
  val playedChunkIds: List<String>,
  val nextMarkerFrame: Long?,
  val drained: Boolean,
)

enum class PlaybackDrainSignalAction {
  WAIT_FOR_MARKER,
  RECONCILE_ASYNC,
  POLL_EXACT_HEAD,
}

/** Chooses the race-safe follow-up after arming an exact playback marker. */
object PlaybackDrainSignal {
  fun decide(
    markerArmed: Boolean,
    headAfterArm: Long,
    markerFrame: Long,
  ): PlaybackDrainSignalAction = when {
    headAfterArm >= markerFrame -> PlaybackDrainSignalAction.RECONCILE_ASYNC
    markerArmed -> PlaybackDrainSignalAction.WAIT_FOR_MARKER
    else -> PlaybackDrainSignalAction.POLL_EXACT_HEAD
  }
}

enum class PlaybackHeadPollAction {
  POLL_AGAIN,
  RECONCILE,
  EXHAUSTED,
  CANCELLED,
}

/**
 * Bounded fallback for devices that reject playback markers. Decisions use
 * only the hardware playback head; wall-clock time never implies rendering.
 */
class PlaybackHeadFallbackPoll(
  val generation: Long,
  val markerFrame: Long,
  maxAttempts: Int,
) {
  private var attemptsRemaining = maxAttempts

  init {
    require(maxAttempts > 0)
  }

  fun observe(
    generation: Long,
    renderedFrame: Long,
  ): PlaybackHeadPollAction {
    if (generation != this.generation) return PlaybackHeadPollAction.CANCELLED
    if (renderedFrame >= markerFrame) return PlaybackHeadPollAction.RECONCILE

    attemptsRemaining -= 1
    return if (attemptsRemaining > 0) {
      PlaybackHeadPollAction.POLL_AGAIN
    } else {
      PlaybackHeadPollAction.EXHAUSTED
    }
  }
}

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
