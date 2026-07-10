package dev.volskaya.realtime_audio

import kotlin.math.roundToInt

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
   * which is the documented per-stream reset.
   */
  fun renderedFrames(rawHead: Int): Long = rawHead.toLong() and 0xFFFFFFFFL

  /** Convert a frame count to milliseconds at [sampleRate] (Hz). */
  fun framesToMs(frames: Long, sampleRate: Int): Int =
    if (sampleRate <= 0 || frames <= 0L) 0 else ((frames.toDouble() / sampleRate) * 1000.0).roundToInt()

  /** The resolved played-ms plus the value to store back into the latch. */
  data class PlayedResolution(val renderedMs: Int, val latchedMs: Int)

  /**
   * Apply the render-clock latch rule (pure, so the reset semantics are
   * testable without an [android.media.AudioTrack]):
   *
   * - While active with a live head reading, the live value wins **and** updates
   *   the latch (monotone advance during a stream).
   * - Once inactive (stopped/flushed) — or if the live read is unavailable — the
   *   previously latched value is held, so a post-stop / post-drain read still
   *   reports what the device rendered.
   */
  fun resolvePlayedMs(isActive: Boolean, liveMs: Int?, latchedMs: Int): PlayedResolution =
    if (isActive && liveMs != null) PlayedResolution(liveMs, liveMs)
    else PlayedResolution(latchedMs, latchedMs)
}
