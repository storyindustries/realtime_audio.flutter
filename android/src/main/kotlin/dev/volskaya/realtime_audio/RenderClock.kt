package dev.volskaya.realtime_audio

/**
 * Pure, side-effect-free render-clock math, factored out so it is trivially
 * correct and unit-testable independent of [android.media.AudioTrack].
 */
object RenderClock {
  /**
   * Reinterpret [AudioTrack.getPlaybackHeadPosition]'s return value as an
   * unsigned frame counter.
   *
   * The platform surfaces the head as a 32-bit value in a signed [Int]; once it
   * passes 2^31 frames (~24.8 h at 24 kHz — far beyond any single TTS stream) it
   * would otherwise flip negative. Masking to 32 unsigned bits keeps the counter
   * monotonic across that sign boundary. It still resets to `0` on flush()/stop(),
   * which is the documented per-segment reset that the lifetime clock folds over.
   */
  fun renderedFrames(rawHead: Int): Long = rawHead.toLong() and 0xFFFFFFFFL

  /**
   * Convert a frame count to milliseconds at [sampleRate] (Hz), as a [Double] so
   * the lifetime fold accumulates without per-segment rounding drift.
   */
  fun framesToMs(frames: Long, sampleRate: Int): Double =
    if (sampleRate <= 0 || frames <= 0L) 0.0 else (frames.toDouble() / sampleRate) * 1000.0

  /** Rendering state belongs to the current playback-head segment. Lifetime
   * scheduled totals include intentionally flushed audio and cannot be used as
   * the current segment's drain target. */
  fun isSegmentRendering(renderedMs: Double, scheduledMs: Double): Boolean = renderedMs < scheduledMs
}
