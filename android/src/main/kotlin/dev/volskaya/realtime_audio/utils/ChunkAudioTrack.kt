package dev.volskaya.realtime_audio.utils

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import dev.volskaya.realtime_audio.QueuedChunk
import dev.volskaya.realtime_audio.RenderClock
import dev.volskaya.realtime_audio.getBitRatio
import java.lang.ref.WeakReference
import kotlin.math.roundToInt

class ChunkAudioTrack(
  attributes: AudioAttributes,
  format: AudioFormat,
  bufferSizeInBytes: Int,
  mode: Int,
  sessionId: Int,
  chunkAudioEventListener: ChunkAudioEventListener
) : AudioTrack(
  attributes,
  format,
  bufferSizeInBytes,
  mode,
  sessionId
) {
  private var thread: Thread? = null
  private val mainLooperHandler = Handler(Looper.getMainLooper())
  private val eventListener = WeakReference(chunkAudioEventListener)
  private var isChunkQueueStartedNeeded = true

  val queue: MutableList<QueuedChunk> = mutableListOf()
  val totalDataSize: Int get() = queue.lastOrNull()?.let { it.offset + it.data.size } ?: 0
  val totalSampleTime: Int get() = totalDataSize / bitRatio

  val bitRatio: Int get() = format.getBitRatio()
  val dataPlaybackHeadPosition: Int get() = playbackHeadPosition * bitRatio
  val dataSampleRate: Int get() = sampleRate * bitRatio

  // --- Render clock (call-lifetime; folded across stops) ------------------
  //
  // Monotonic for the track's lifetime — NOT reset per stream. The live segment
  // is folded into a base before every stop (playbackHeadPosition resets to 0 on
  // flush()/stop()), so the values survive stop/clearQueue/drain. A fresh track
  // (engine teardown) is the only full reset. Consumer subtracts a baseline.
  //
  // Note: Android has no per-buffer PLAYED-OUT callback (the write loop reports
  // buffer-fill, ahead of the head), so the completion-driven counter mirrors the
  // head-based render clock — the head is the only playout truth on this platform.

  /// True while a segment is playing/paused (head meaningful), false once stopped
  /// — [playbackHeadPosition] holds its last value until flush(), so this flag
  /// (not the raw head) tells the clock when the segment has ended.
  var isPlaybackActive = false
    private set

  private var renderClockBaseMs = 0.0
  private var scheduledMsAccum = 0.0
  private var lastPlaybackEndedAtNs: Long? = null

  /// Wrap-safe playback-head position in frames (see [RenderClock.renderedFrames]).
  val renderedFramesNow: Long get() = RenderClock.renderedFrames(playbackHeadPosition)

  /// Live segment position in ms since the current play() (0 once stopped, so the
  /// pre-flush head value is not double-counted after a fold).
  private fun currentSegmentMs(): Double =
    if (isPlaybackActive) RenderClock.framesToMs(renderedFramesNow, sampleRate) else 0.0

  /// Fold the current segment into the base BEFORE a stop resets the head.
  private fun foldRenderClock() {
    renderClockBaseMs += currentSegmentMs()
  }

  /// Completion-independent, call-lifetime render clock (ms). Derived from the
  /// playback head; folds across stops.
  val lifetimeRenderClockMs: Int get() = (renderClockBaseMs + currentSegmentMs()).roundToInt()

  /// Completion-driven lifetime rendered ms. Android has no playout callback, so
  /// this mirrors the head-based render clock (kept <= the head, never ahead).
  val lifetimeRenderedMs: Int get() = lifetimeRenderClockMs

  /// Lifetime ms scheduled onto the track (monotonic upper bound).
  val lifetimeScheduledMs: Int get() = scheduledMsAccum.roundToInt()

  /// Whether the device is actively rendering: the head hasn't caught up to the
  /// scheduled total, or we're within the post-drain hangover window. Pause
  /// gating is applied by the engine (which owns the paused state).
  val isRenderingPlaybackRaw: Boolean
    get() {
      if (isPlaybackActive && lifetimeRenderClockMs < lifetimeScheduledMs) return true
      val ended = lastPlaybackEndedAtNs ?: return false
      return (System.nanoTime() - ended) < RENDER_HANGOVER_NS
    }

  fun queue(id: String, data: ByteArray) {
    if (data.isEmpty()) return

    val queuedChunkEntry = QueuedChunk(
      id = id,
      data = data,
      offset = totalDataSize,
    )

    // Scheduled-ms upper bound: bytes -> frames -> ms at the output rate.
    scheduledMsAccum += RenderClock.framesToMs((data.size / bitRatio).toLong(), sampleRate)

    queue.add(queuedChunkEntry)
    eventListener.get()?.onChunkQueued(id)
  }

  override fun play() {
    if (isChunkQueueStartedNeeded && queue.isNotEmpty()) {
      queue.firstOrNull()?.let {
        isChunkQueueStartedNeeded = false
        eventListener.get()?.onChunkQueueStarted(it.id)
      }
    }

    isPlaybackActive = true
    super.play()
    thread = thread ?: Thread {
      val currentThread = Thread.currentThread()
      var resumeOffset: Int? = dataPlaybackHeadPosition - (queue.firstOrNull()?.offset ?: 0)

      while (thread == currentThread && !currentThread.isInterrupted && queue.isNotEmpty()) {
        val chunk = queue.first()
        val data = runCatching {
          val pauseOffset = resumeOffset?.also { resumeOffset = null } ?: 0
          return@runCatching if (pauseOffset > 0) chunk.data.copyOfRange(
            pauseOffset,
            chunk.data.size
          ) else chunk.data
        }.getOrNull() ?: chunk.data

        write(data, 0, data.size)

        if (thread != currentThread || currentThread.isInterrupted) break

        val didRemove = queue.remove(chunk)
        if (didRemove) {
          handleChunkPlayed(chunk.id)
        }
      }

      if (currentThread == thread && !currentThread.isInterrupted && queue.isEmpty()) {
        handleQueueEnded()
      }
    }.also { it.start() }
  }

  private fun handleChunkPlayed(id: String) {
    mainLooperHandler.post {
      eventListener.get()?.onChunkPlayed(id)
    }
  }

  private fun handleQueueEnded() {
    thread?.interrupt()
    thread = null
    mainLooperHandler.post {
      eventListener.get()?.onChunkQueueEnded()
    }
  }

  override fun pause() {
    thread?.interrupt()
    thread = null
    super.pause()
  }

  override fun stop() {
    // Fold the live segment into the base BEFORE super.stop()/flush() reset the
    // playback head, so the lifetime render clock stays monotonic across the stop.
    foldRenderClock()
    if (isPlaybackActive) lastPlaybackEndedAtNs = System.nanoTime()
    isPlaybackActive = false

    thread?.interrupt()
    thread = null
    isChunkQueueStartedNeeded = true
    super.stop()

    while (queue.isNotEmpty()) {
      queue.removeAt(0).let { eventListener.get()?.onChunkPlayed(it.id) }
    }
  }

  private companion object {
    /// Post-drain hangover: keep reporting "rendering" briefly after the last
    /// buffer drains, covering speaker ring-out / output pipeline latency.
    private const val RENDER_HANGOVER_NS = 200_000_000L
  }

  fun getCurrentChunkProps(): Map<String, Any>? {
    val sampleTime = playbackHeadPosition
    val sampleTimeTotal = totalSampleTime
    val chunk = queue.firstOrNull() ?: return null
    val offset = chunk.offset / bitRatio
    val chunkSampleTime = sampleTime - offset
    val chunkSampleTimeTotal = chunk.data.size / bitRatio

    return mapOf(
      "id" to chunk.id,
      "sampleRate" to sampleRate,
      "sampleTime" to sampleTime,
      "sampleTimeTotal" to sampleTimeTotal,
      "chunkSampleTime" to chunkSampleTime,
      "chunkSampleTimeTotal" to chunkSampleTimeTotal,
    )
  }
}
