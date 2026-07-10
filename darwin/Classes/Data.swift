enum RealtimeAudioRecordPermission: String, Codable {
  case undetermined
  case denied
  case granted
}

/// Which echo-cancellation mechanism the engine is driving. Raw values are the
/// wire form and must match the Dart `RealtimeAudioEchoCancellationMechanism`
/// `@JsonValue`s.
enum RealtimeAudioEchoCancellationMechanism: String {
  case none
  case webRtcApm = "webrtc_apm"
  case platformAec = "platform_aec"
}

struct RealtimeAudioState: Codable {
  var isPlaying: Bool
  var isPaused: Bool

  var duration: Int
  var durationTotal: Int

  var chunkCount: Int

  /// Completion-independent, call-lifetime render clock (ms). Folds across
  /// stop/clearQueue/drain (see `ChunkAudioPlayerNode.lifetimeRenderClockMs`).
  var renderClockMs: Int
  /// Whether the device is actively rendering (outstanding buffers or hangover).
  var isRendering: Bool
}
