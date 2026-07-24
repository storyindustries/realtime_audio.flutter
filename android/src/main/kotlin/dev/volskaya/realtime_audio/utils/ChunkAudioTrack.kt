package dev.volskaya.realtime_audio.utils

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.AudioTrack.OnPlaybackPositionUpdateListener
import android.os.Handler
import android.os.Looper
import android.util.Log
import dev.volskaya.realtime_audio.PlaybackDrainLedger
import dev.volskaya.realtime_audio.PlaybackDrainSignal
import dev.volskaya.realtime_audio.PlaybackDrainSignalAction
import dev.volskaya.realtime_audio.PlaybackHeadFallbackPoll
import dev.volskaya.realtime_audio.PlaybackHeadPollAction
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
), OnPlaybackPositionUpdateListener {
  private data class WriteCursor(
    val chunk: QueuedChunk,
    var byteOffset: Int = 0,
  )

  private val lock = Any()
  private var thread: Thread? = null
  private var writesEnabled = false
  private val mainLooperHandler = Handler(Looper.getMainLooper())
  private val eventListener = WeakReference(chunkAudioEventListener)
  private var isChunkQueueStartedNeeded = true
  private val chunks = mutableListOf<QueuedChunk>()
  private val pendingWrites = ArrayDeque<WriteCursor>()
  private val drainLedger = PlaybackDrainLedger()
  private var segmentDataSize = 0
  private var playbackGeneration = 0L
  private var armedMarkerGeneration: Long? = null
  private var postedReconcileGeneration: Long? = null
  private var fallbackPoll: PlaybackHeadFallbackPoll? = null

  /// Write-time render tap: invoked on the writer thread with the exact byte
  /// range just accepted by `AudioTrack.write`, i.e. within one track buffer of
  /// the speaker. Feeds the WebRTC APM far-end reference (see ApmRenderFeeder);
  /// a queue-time feed would lead actual playout by whole chunks and break AEC.
  var renderTap: ((data: ByteArray, offset: Int, length: Int) -> Unit)? = null

  val queue: List<QueuedChunk> get() = synchronized(lock) { chunks.toList() }
  val totalDataSize: Int get() = synchronized(lock) { segmentDataSize }
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
  private var segmentScheduledMs = 0.0
  private var lastPlaybackEndedAtNs: Long? = null

  init {
    setPlaybackPositionUpdateListener(this, mainLooperHandler)
  }

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
      if (isPlaybackActive && RenderClock.isSegmentRendering(currentSegmentMs(), segmentScheduledMs)) return true
      val ended = lastPlaybackEndedAtNs ?: return false
      return (System.nanoTime() - ended) < RENDER_HANGOVER_NS
    }

  fun queue(id: String, data: ByteArray) {
    if (data.isEmpty()) return

    synchronized(lock) {
      val queuedChunkEntry = QueuedChunk(
        id = id,
        data = data,
        offset = segmentDataSize,
      )
      val frameCount = data.size / bitRatio
      segmentDataSize += data.size
      scheduledMsAccum += RenderClock.framesToMs(frameCount.toLong(), sampleRate)
      segmentScheduledMs += RenderClock.framesToMs(frameCount.toLong(), sampleRate)
      chunks.add(queuedChunkEntry)
      pendingWrites.addLast(WriteCursor(queuedChunkEntry))
      drainLedger.enqueue(id, frameCount)
    }
    eventListener.get()?.onChunkQueued(id)
    startWriterIfNeeded()
  }

  override fun play() {
    synchronized(lock) {
      if (isChunkQueueStartedNeeded && chunks.isNotEmpty()) {
        chunks.firstOrNull()?.let {
          isChunkQueueStartedNeeded = false
          eventListener.get()?.onChunkQueueStarted(it.id)
        }
      }
      isPlaybackActive = true
      writesEnabled = true
    }
    super.play()
    startWriterIfNeeded()
  }

  private fun startWriterIfNeeded() {
    val writer = synchronized(lock) {
      if (!writesEnabled || pendingWrites.isEmpty() || thread?.isAlive == true) return
      Thread(::writePendingChunks, "realtime-audio-writer").also { thread = it }
    }
    writer.start()
  }

  private fun writePendingChunks() {
    val currentThread = Thread.currentThread()
    var writeFailed = false
    try {
      while (!currentThread.isInterrupted) {
        val cursor = synchronized(lock) {
          if (thread !== currentThread || !writesEnabled) return
          pendingWrites.firstOrNull() ?: return
        }
        val remaining = cursor.chunk.data.size - cursor.byteOffset
        val written = write(cursor.chunk.data, cursor.byteOffset, remaining, WRITE_BLOCKING)
        if (written <= 0) {
          writeFailed = true
          eventListener.get()?.onPlaybackDrainError("AudioTrack.write failed with code $written")
          return
        }
        renderTap?.invoke(cursor.chunk.data, cursor.byteOffset, written)

        val reconcileGeneration = synchronized(lock) {
          if (thread !== currentThread) return
          cursor.byteOffset += written
          if (cursor.byteOffset < cursor.chunk.data.size) return@synchronized null
          pendingWrites.removeFirst()
          drainLedger.markWritten(cursor.chunk.id)
          playbackGeneration
        }
        reconcileGeneration?.let(::schedulePlaybackHeadReconciliation)
      }
    } finally {
      val restart = synchronized(lock) {
        if (thread !== currentThread) return@synchronized false
        thread = null
        !writeFailed && writesEnabled && pendingWrites.isNotEmpty()
      }
      if (restart) startWriterIfNeeded()
    }
  }

  private fun armPlaybackMarker(frame: Long, generation: Long) {
    val result = synchronized(lock) {
      if (generation != playbackGeneration) return
      setNotificationMarkerPosition(frame.toInt()).also {
        armedMarkerGeneration = if (it == SUCCESS) generation else null
        if (it == SUCCESS) fallbackPoll = null
      }
    }
    val markerArmed = result == SUCCESS
    if (!markerArmed) {
      reportPlaybackDrainError("AudioTrack marker setup failed with code $result at frame $frame")
    }

    when (PlaybackDrainSignal.decide(markerArmed, renderedFramesNow, frame)) {
      PlaybackDrainSignalAction.WAIT_FOR_MARKER -> Unit
      PlaybackDrainSignalAction.RECONCILE_ASYNC -> schedulePlaybackHeadReconciliation(generation)
      PlaybackDrainSignalAction.POLL_EXACT_HEAD -> startPlaybackHeadFallbackPoll(generation, frame)
    }
  }

  override fun onMarkerReached(track: AudioTrack?) {
    if (track !== this) return
    val generation = synchronized(lock) { armedMarkerGeneration } ?: return
    schedulePlaybackHeadReconciliation(generation)
  }

  private fun schedulePlaybackHeadReconciliation(generation: Long) {
    val shouldPost = synchronized(lock) {
      if (generation != playbackGeneration || postedReconcileGeneration == generation) {
        false
      } else {
        postedReconcileGeneration = generation
        true
      }
    }
    if (!shouldPost) return

    mainLooperHandler.post {
      val isCurrent = synchronized(lock) {
        if (postedReconcileGeneration == generation) postedReconcileGeneration = null
        generation == playbackGeneration
      }
      if (isCurrent) reconcilePlaybackHead(generation)
    }
  }

  private fun reconcilePlaybackHead(generation: Long) {
    val advance = synchronized(lock) {
      if (generation != playbackGeneration) return
      armedMarkerGeneration = null
      fallbackPoll = null
      val result = drainLedger.advancePlaybackHead(renderedFramesNow)
      if (result.playedChunkIds.isNotEmpty()) {
        val played = result.playedChunkIds.toSet()
        chunks.removeAll { it.id in played }
      }
      result
    }

    advance.playedChunkIds.forEach(::handleChunkPlayed)
    advance.nextMarkerFrame?.let { armPlaybackMarker(it, generation) }
    if (advance.drained) handleQueueEnded()
  }

  private fun startPlaybackHeadFallbackPoll(generation: Long, markerFrame: Long) {
    val poll = synchronized(lock) {
      if (generation != playbackGeneration) return
      fallbackPoll
        ?.takeIf { it.generation == generation && it.markerFrame == markerFrame }
        ?: PlaybackHeadFallbackPoll(
          generation = generation,
          markerFrame = markerFrame,
          maxAttempts = PLAYBACK_HEAD_POLL_MAX_ATTEMPTS,
        ).also { fallbackPoll = it }
    }
    schedulePlaybackHeadFallbackPoll(poll)
  }

  private fun schedulePlaybackHeadFallbackPoll(poll: PlaybackHeadFallbackPoll) {
    mainLooperHandler.postDelayed({
      val action = synchronized(lock) {
        if (fallbackPoll !== poll) return@postDelayed
        poll.observe(playbackGeneration, renderedFramesNow)
      }
      when (action) {
        PlaybackHeadPollAction.POLL_AGAIN -> schedulePlaybackHeadFallbackPoll(poll)
        PlaybackHeadPollAction.RECONCILE -> schedulePlaybackHeadReconciliation(poll.generation)
        PlaybackHeadPollAction.CANCELLED -> Unit
        PlaybackHeadPollAction.EXHAUSTED -> {
          synchronized(lock) {
            if (fallbackPoll === poll) fallbackPoll = null
          }
          reportPlaybackDrainError(
            "AudioTrack playback head did not reach marker ${poll.markerFrame} " +
              "after $PLAYBACK_HEAD_POLL_MAX_ATTEMPTS exact-head checks"
          )
        }
      }
    }, PLAYBACK_HEAD_POLL_INTERVAL_MS)
  }

  private fun reportPlaybackDrainError(message: String) {
    Log.e("RealtimeAudio", message)
    eventListener.get()?.onPlaybackDrainError(message)
  }

  override fun onPeriodicNotification(track: AudioTrack?) {
    // Exact chunk-end markers own drain; no elapsed-time approximation.
  }

  override fun pause() {
    synchronized(lock) {
      writesEnabled = false
      thread?.interrupt()
    }
    super.pause()
  }

  override fun stop() {
    foldRenderClock()
    if (isPlaybackActive) lastPlaybackEndedAtNs = System.nanoTime()
    isPlaybackActive = false

    val discarded = synchronized(lock) {
      playbackGeneration += 1
      writesEnabled = false
      thread?.interrupt()
      thread = null
      isChunkQueueStartedNeeded = true
      val values = chunks.toList()
      chunks.clear()
      pendingWrites.clear()
      drainLedger.reset()
      armedMarkerGeneration = null
      postedReconcileGeneration = null
      fallbackPoll = null
      segmentDataSize = 0
      values
    }
    super.stop()
    segmentScheduledMs = 0.0

    discarded.forEach { eventListener.get()?.onChunkPlayed(it.id) }
  }

  private fun handleChunkPlayed(id: String) {
    // Marker callbacks are delivered on [mainLooperHandler], so retire Dart
    // ownership synchronously before the terminal drain transition.
    eventListener.get()?.onChunkPlayed(id)
  }

  private fun handleQueueEnded() {
    synchronized(lock) {
      thread?.interrupt()
      thread = null
    }
    // Synchronous on the marker callback's main looper: a later server chunk
    // starts a fresh player segment instead of racing a deferred stale drain.
    eventListener.get()?.onChunkQueueEnded()
  }

  fun getCurrentChunkProps(): Map<String, Any>? {
    val sampleTime = playbackHeadPosition
    val sampleTimeTotal = totalSampleTime
    val chunk = synchronized(lock) { chunks.firstOrNull() } ?: return null
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

  private companion object {
    /// Post-drain hangover: keep reporting "rendering" briefly after the last
    /// buffer drains, covering speaker ring-out / output pipeline latency.
    private const val RENDER_HANGOVER_NS = 200_000_000L
    private const val PLAYBACK_HEAD_POLL_INTERVAL_MS = 10L
    private const val PLAYBACK_HEAD_POLL_MAX_ATTEMPTS = 200
  }

}
