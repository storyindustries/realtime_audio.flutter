package dev.volskaya.realtime_audio

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Unit tests for the write-time APM render-reference feeder.
 *
 * The JNI bridge (`nativeProcessRender`) processes only whole 10ms frames and
 * silently drops any tail remainder of each call. Feeding it raw
 * `AudioTrack.write` slices (arbitrary sizes) would therefore lose up to one
 * frame of reference audio per write and starve the echo canceller. The feeder
 * carries the remainder across writes so the APM sees a gapless, frame-aligned
 * reference stream.
 */
internal class ApmRenderFeederTest {
  /** 24 kHz mono 16-bit → 10ms frame = 480 bytes. */
  private val frameBytes = 480

  private fun feeder(emitted: MutableList<ByteArray>) = ApmRenderFeeder(frameBytes) { emitted.add(it) }

  private fun bytes(range: IntRange): ByteArray = range.map { (it and 0xFF).toByte() }.toByteArray()

  @Test
  fun emitsOnlyWholeFrames_andCarriesTheRemainder() {
    val emitted = mutableListOf<ByteArray>()
    val f = feeder(emitted)

    // 1200 bytes = 2.5 frames → one emission of 2 frames, 240 bytes carried.
    f.feed(bytes(0 until 1200), 0, 1200)
    assertEquals(1, emitted.size)
    assertEquals(960, emitted[0].size)

    // 240 more bytes complete the carried half-frame exactly.
    f.feed(bytes(1200 until 1440), 0, 240)
    assertEquals(2, emitted.size)
    assertEquals(480, emitted[1].size)

    // The emitted stream is the input stream, byte for byte, in order.
    val all = emitted.flatMap { it.toList() }
    assertEquals(bytes(0 until 1440).toList(), all)
  }

  @Test
  fun respectsOffsetAndLengthWindows() {
    val emitted = mutableListOf<ByteArray>()
    val f = feeder(emitted)

    // Feed the middle 480 bytes of a larger buffer (a partial AudioTrack.write).
    val buffer = bytes(0 until 2000)
    f.feed(buffer, 500, 480)

    assertEquals(1, emitted.size)
    assertEquals(buffer.copyOfRange(500, 980).toList(), emitted[0].toList())
  }

  @Test
  fun shortFeedsAccumulateUntilAFrameCompletes() {
    val emitted = mutableListOf<ByteArray>()
    val f = feeder(emitted)

    // 4 × 100 bytes < 480 → nothing yet; the 5th crosses the frame boundary.
    repeat(4) { f.feed(bytes(it * 100 until (it + 1) * 100), 0, 100) }
    assertTrue(emitted.isEmpty())
    f.feed(bytes(400 until 500), 0, 100)
    assertEquals(1, emitted.size)
    assertEquals(bytes(0 until 480).toList(), emitted[0].toList())
  }

  @Test
  fun resetDropsTheCarriedRemainder() {
    val emitted = mutableListOf<ByteArray>()
    val f = feeder(emitted)

    f.feed(bytes(0 until 700), 0, 700) // one frame out, 220 carried
    assertEquals(1, emitted.size)
    f.reset()

    // After reset the stale remainder must not prefix the next stream.
    f.feed(bytes(1000 until 1480), 0, 480)
    assertEquals(2, emitted.size)
    assertEquals(bytes(1000 until 1480).toList(), emitted[1].toList())
  }

  @Test
  fun neverLosesBytesAcrossManyOddSizedWrites() {
    val emitted = mutableListOf<ByteArray>()
    val f = feeder(emitted)

    // Deterministic odd sizes exercising every remainder path.
    val sizes = listOf(1, 479, 480, 481, 959, 960, 7, 1200, 33, 480)
    var fed = 0
    for (size in sizes) {
      f.feed(bytes(fed until fed + size), 0, size)
      fed += size
    }

    val emittedTotal = emitted.sumOf { it.size }
    assertEquals((fed / frameBytes) * frameBytes, emittedTotal, "everything except the live tail is emitted")
    assertTrue(emitted.all { it.size % frameBytes == 0 }, "every emission is frame-aligned")
    // Byte-exact, in-order reference stream.
    assertEquals(bytes(0 until emittedTotal).toList(), emitted.flatMap { it.toList() })
  }

  @Test
  fun zeroAndNegativeLengthsAreIgnored() {
    val emitted = mutableListOf<ByteArray>()
    val f = feeder(emitted)
    f.feed(bytes(0 until 480), 0, 0)
    f.feed(bytes(0 until 480), 0, -5)
    assertTrue(emitted.isEmpty())
  }

  @Test
  fun degenerateFrameSizeNeverEmits() {
    // A frameBytes of 0 would divide by zero; the feeder must degrade to a no-op.
    val emitted = mutableListOf<ByteArray>()
    val f = ApmRenderFeeder(0) { emitted.add(it) }
    f.feed(bytes(0 until 480), 0, 480)
    assertTrue(emitted.isEmpty())
  }
}
