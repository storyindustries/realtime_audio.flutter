package dev.volskaya.realtime_audio

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Unit tests for the pure render-clock logic backing `getPlayerPlayedDuration`
 * and the player state's `renderedMs` / `isRendering`. The AudioTrack-bound
 * pieces are covered indirectly; the math + latch/reset semantics are factored
 * into [RenderClock] so they are testable without the Android framework.
 */
internal class RealtimeAudioPluginTest {
  @Test
  fun framesToMs_convertsAtSampleRate() {
    // 24000 frames @ 24 kHz == 1000 ms.
    assertEquals(1000, RenderClock.framesToMs(24000L, 24000))
    // 12000 frames @ 24 kHz == 500 ms.
    assertEquals(500, RenderClock.framesToMs(12000L, 24000))
    // 24 frames @ 24 kHz == 1 ms exactly.
    assertEquals(1, RenderClock.framesToMs(24L, 24000))
    // 36 frames @ 24 kHz == 1.5 ms, rounds to nearest (2).
    assertEquals(2, RenderClock.framesToMs(36L, 24000))
  }

  @Test
  fun framesToMs_guardsDegenerateInputs() {
    assertEquals(0, RenderClock.framesToMs(0L, 24000))
    assertEquals(0, RenderClock.framesToMs(-5L, 24000))
    assertEquals(0, RenderClock.framesToMs(24000L, 0))
    assertEquals(0, RenderClock.framesToMs(24000L, -1))
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
    assertEquals(0, RenderClock.framesToMs(afterRaw.toLong(), 24000))
  }

  @Test
  fun resolvePlayedMs_liveHeadWinsAndLatchesWhileActive() {
    val r = RenderClock.resolvePlayedMs(isActive = true, liveMs = 820, latchedMs = 300)
    assertEquals(820, r.renderedMs)
    assertEquals(820, r.latchedMs) // latch tracks the live head during a stream
  }

  @Test
  fun resolvePlayedMs_holdsLatchWhenStopped() {
    // After stop/flush the platform head resets to 0, but the latched device-truth
    // value is held so a post-drain read still reports what was rendered.
    val r = RenderClock.resolvePlayedMs(isActive = false, liveMs = 0, latchedMs = 3820)
    assertEquals(3820, r.renderedMs)
    assertEquals(3820, r.latchedMs)
  }

  @Test
  fun resolvePlayedMs_holdsLatchWhenLiveReadUnavailable() {
    val r = RenderClock.resolvePlayedMs(isActive = true, liveMs = null, latchedMs = 1500)
    assertEquals(1500, r.renderedMs)
    assertEquals(1500, r.latchedMs)
  }

  @Test
  fun resolvePlayedMs_freshStreamReadsFromZeroNotPreviousLatch() {
    // New stream: active again, live head back near 0 → shadows the previous
    // stream's latched value (no leakage between streams).
    val r = RenderClock.resolvePlayedMs(isActive = true, liveMs = 40, latchedMs = 3820)
    assertEquals(40, r.renderedMs)
    assertEquals(40, r.latchedMs)
  }

  @Test
  fun isRenderingPredicate_matchesActiveWithHeadBehindTotal() {
    // Mirrors ChunkAudioTrack.isRenderingPlayback: active AND head < total.
    fun isRendering(active: Boolean, head: Long, total: Long) = active && head < total
    assertTrue(isRendering(active = true, head = 1000, total = 4000))
    assertFalse(isRendering(active = true, head = 4000, total = 4000)) // drained
    assertFalse(isRendering(active = false, head = 1000, total = 4000)) // stopped/paused
  }
}
