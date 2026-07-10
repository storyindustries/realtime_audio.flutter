package dev.volskaya.realtime_audio

enum class RealtimeAudioRecorderPermission {
  undetermined,
  denied,
  granted
}

data class RealtimeAudioState(
  var isPlaying: Boolean,
  var isPaused: Boolean,

  var duration: Int,
  var durationTotal: Int,

  var chunkCount: Int,

  // Device-truth ms rendered for the current stream. Latches across
  // stop/clearQueue/drain (see ChunkAudioTrack.playedMs).
  var renderedMs: Int = 0,
  // Whether the device is actively rendering queued PCM ahead of the head.
  var isRendering: Boolean = false
) {
  fun toMap(): Map<String, Any> {
    return mapOf(
      "isPlaying" to isPlaying,
      "isPaused" to isPaused,
      "duration" to duration,
      "durationTotal" to durationTotal,
      "chunkCount" to chunkCount,
      "renderedMs" to renderedMs,
      "isRendering" to isRendering
    )
  }
}