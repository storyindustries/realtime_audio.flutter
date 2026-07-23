package dev.volskaya.realtime_audio

/**
 * Frame-aligns the WebRTC APM far-end (render) reference stream.
 *
 * Fed from the AudioTrack writer thread with the exact byte ranges just
 * written (see `ChunkAudioTrack.renderTap`), so the echo reference tracks the
 * speaker within the track's small internal buffer instead of leading it by
 * whole queued chunks — feeding at queue time desynchronized the reference by
 * seconds and made AEC3 cancel nothing (the 2026-07-23 echo-storm RCA).
 *
 * The JNI bridge processes only whole 10ms frames per call and drops any tail,
 * so arbitrary write sizes must be re-framed here: emissions are always a
 * multiple of [frameBytes] and the remainder is carried into the next feed.
 *
 * Thread-safety: [feed] runs on the writer thread while [reset] runs on the
 * engine's calling thread during stop/clear — both are synchronized.
 */
class ApmRenderFeeder(
  private val frameBytes: Int,
  private val emit: (ByteArray) -> Unit,
) {
  private var remainder: ByteArray = ByteArray(0)

  @Synchronized
  fun feed(data: ByteArray, offset: Int, length: Int) {
    if (frameBytes <= 0 || length <= 0) return
    val incoming = data.copyOfRange(offset, offset + length)
    val combined = if (remainder.isEmpty()) incoming else remainder + incoming
    val alignedBytes = (combined.size / frameBytes) * frameBytes
    if (alignedBytes == 0) {
      remainder = combined
      return
    }
    remainder = combined.copyOfRange(alignedBytes, combined.size)
    emit(if (alignedBytes == combined.size) combined else combined.copyOfRange(0, alignedBytes))
  }

  /** Drop the carried tail — the audio it belonged to will never render. */
  @Synchronized
  fun reset() {
    remainder = ByteArray(0)
  }
}
