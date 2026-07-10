enum RealtimeAudioRecordPermission: String, Codable {
  case undetermined
  case denied
  case granted
}

/// Which echo-cancellation mechanism the engine is driving. Raw values must
/// match the Dart `RealtimeAudioEchoCancellationMechanism` enum names.
enum RealtimeAudioEchoCancellationMechanism: String {
  case none
  case appleVoiceProcessingIO
  case webRtcApm
  case platformVoiceCommunication
}

struct RealtimeAudioState: Codable {
  var isPlaying: Bool
  var isPaused: Bool

  var duration: Int
  var durationTotal: Int

  var chunkCount: Int

  /// Device-truth ms rendered for the current stream. Latches across
  /// stop/clearQueue/drain (see `ChunkAudioPlayerNode.playedMs`).
  var renderedMs: Int
  /// Whether the device is actively rendering queued PCM ahead of the head.
  var isRendering: Bool
}
