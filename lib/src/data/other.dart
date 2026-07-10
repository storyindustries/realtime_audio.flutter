enum RealtimeAudioRecordPermission {
  undetermined,
  denied,
  granted,
}

/// Which echo-cancellation mechanism the native engine is actually driving for
/// the current capture path. Reported by read-back, never assumed.
///
/// - [none]: no echo cancellation is active (e.g. recorder disabled, or voice
///   processing failed / was not requested).
/// - [appleVoiceProcessingIO]: Apple's `AVAudioEngine` VoiceProcessingIO unit
///   (hardware AEC) on iOS/macOS.
/// - [webRtcApm]: the bundled WebRTC Audio Processing Module (software AEC) on
///   Android.
/// - [platformVoiceCommunication]: Android is relying on the platform
///   `VOICE_COMMUNICATION` capture source for preprocessing, but the software
///   APM is unavailable so liveness cannot be read back.
enum RealtimeAudioEchoCancellationMechanism {
  none,
  appleVoiceProcessingIO,
  webRtcApm,
  platformVoiceCommunication,
}
