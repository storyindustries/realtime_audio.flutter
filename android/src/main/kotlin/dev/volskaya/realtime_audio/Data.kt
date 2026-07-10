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

  // Completion-independent, call-lifetime render clock (ms). Folds across
  // stop/clearQueue/drain (see ChunkAudioTrack.lifetimeRenderClockMs).
  var renderClockMs: Int = 0,
  // Whether the device is actively rendering (head behind scheduled or hangover).
  var isRendering: Boolean = false
) {
  fun toMap(): Map<String, Any> {
    return mapOf(
      "isPlaying" to isPlaying,
      "isPaused" to isPaused,
      "duration" to duration,
      "durationTotal" to durationTotal,
      "chunkCount" to chunkCount,
      "renderClockMs" to renderClockMs,
      "isRendering" to isRendering
    )
  }
}