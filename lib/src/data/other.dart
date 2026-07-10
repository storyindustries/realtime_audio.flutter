import 'package:freezed_annotation/freezed_annotation.dart';

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
/// - [webrtcApm]: the bundled WebRTC Audio Processing Module (software AEC),
///   used on Android.
/// - [platformAec]: a platform echo canceller — Apple's `AVAudioEngine`
///   VoiceProcessingIO on iOS/macOS, or the Android `VOICE_COMMUNICATION`
///   capture source. On Android this path's liveness cannot be read back.
enum RealtimeAudioEchoCancellationMechanism {
  @JsonValue('none')
  none,
  @JsonValue('webrtc_apm')
  webrtcApm,
  @JsonValue('platform_aec')
  platformAec,
}
