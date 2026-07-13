package dev.volskaya.realtime_audio

import kotlin.math.roundToInt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Unit tests for the pure render-clock math backing `getPlayerPlayedDuration`
 * and the player state's `renderClockMs` / `isRendering`. The AudioTrack-bound
 * fold/hangover pieces live in [dev.volskaya.realtime_audio.utils.ChunkAudioTrack];
 * the frame/ms math + the fold arithmetic are factored into [RenderClock] so they
 * are testable without the Android framework.
 */
internal class RealtimeAudioPluginTest {
  @Test
  fun framesToMs_convertsAtSampleRate() {
    // 24000 frames @ 24 kHz == 1000 ms.
    assertEquals(1000.0, RenderClock.framesToMs(24000L, 24000))
    // 12000 frames @ 24 kHz == 500 ms.
    assertEquals(500.0, RenderClock.framesToMs(12000L, 24000))
    // Double precision (no per-segment rounding): 36 frames @ 24 kHz == 1.5 ms.
    assertEquals(1.5, RenderClock.framesToMs(36L, 24000))
  }

  @Test
  fun framesToMs_guardsDegenerateInputs() {
    assertEquals(0.0, RenderClock.framesToMs(0L, 24000))
    assertEquals(0.0, RenderClock.framesToMs(-5L, 24000))
    assertEquals(0.0, RenderClock.framesToMs(24000L, 0))
    assertEquals(0.0, RenderClock.framesToMs(24000L, -1))
  }

  @Test
  fun renderedFrames_reinterpretsSignedHeadAsUnsigned() {
    // Normal, in-range head positions pass through unchanged.
    assertEquals(0L, RenderClock.renderedFrames(0))
    assertEquals(1_000_000L, RenderClock.renderedFrames(1_000_000))
    assertEquals(Int.MAX_VALUE.toLong(), RenderClock.renderedFrames(Int.MAX_VALUE))

    // Past 2^31 frames the platform head flips negative; unsigned reinterpretation
    // keeps it monotonic instead of jumping backwards.
    assertEquals(0xFFFFFFFFL, RenderClock.renderedFrames(-1)) // 4_294_967_295
    assertEquals(2_147_483_648L, RenderClock.renderedFrames(Int.MIN_VALUE))
  }

  @Test
  fun renderedFrames_thenFramesToMs_staysMonotoneAcrossWrap() {
    // Straddle the 2^31 boundary: the raw signed head flips from +MAX to -MIN,
    // but the true frame count keeps increasing by 48000 (2000 ms @ 24 kHz).
    val beforeRaw = Int.MAX_VALUE - 24000
    val afterRaw = Int.MIN_VALUE + 24000

    val beforeWrap = RenderClock.framesToMs(RenderClock.renderedFrames(beforeRaw), 24000)
    val afterWrap = RenderClock.framesToMs(RenderClock.renderedFrames(afterRaw), 24000)
    assertTrue(afterWrap > beforeWrap, "unsigned head must keep advancing across the sign boundary")

    // Without the unsigned reinterpretation the negative raw head would clamp to
    // 0 — a huge backwards jump. This is the bug renderedFrames() prevents.
    assertEquals(0.0, RenderClock.framesToMs(afterRaw.toLong(), 24000))
  }

  @Test
  fun fold_accumulatesSegmentsIntoMonotonicLifetimeClock() {
    // Mirror ChunkAudioTrack's fold: base += currentSegment before each stop, and
    // the lifetime clock = base + currentSegment. Two rendered segments (1000 ms
    // then 500 ms) fold to a monotonic 1500 ms — the per-segment head reset to 0
    // between them must NOT lose the earlier segment.
    var baseMs = 0.0

    // Segment A: head reaches 24000 frames (1000 ms), then stop folds it in.
    val segmentAMs = RenderClock.framesToMs(RenderClock.renderedFrames(24000), 24000)
    val lifetimeDuringA = (baseMs + segmentAMs).roundToInt()
    baseMs += segmentAMs // fold on stop
    val lifetimeAfterAStop = (baseMs + 0.0).roundToInt() // head reset to 0 post-stop

    // Segment B: fresh head from 0 reaches 12000 frames (500 ms), then folds.
    val segmentBMs = RenderClock.framesToMs(RenderClock.renderedFrames(12000), 24000)
    val lifetimeDuringB = (baseMs + segmentBMs).roundToInt()
    baseMs += segmentBMs // fold on stop

    assertEquals(1000, lifetimeDuringA)
    assertEquals(1000, lifetimeAfterAStop) // survives the head reset
    assertEquals(1500, lifetimeDuringB)
    assertEquals(1500, baseMs.roundToInt())
    assertTrue(lifetimeDuringB > lifetimeAfterAStop, "lifetime clock must be monotonic across the fold")
  }

  @Test
  fun isSegmentRendering_ignoresScheduledDebtFromPreviouslyFlushedAudio() {
    // Lifetime scheduled can remain ahead after a flush, but rendering state is
    // local to the current AudioTrack segment. A fully rendered current segment
    // must drain even when older lifetime audio was intentionally discarded.
    assertTrue(RenderClock.isSegmentRendering(renderedMs = 3_999.0, scheduledMs = 4_000.0))
    assertEquals(false, RenderClock.isSegmentRendering(renderedMs = 4_000.0, scheduledMs = 4_000.0))
  }
}
