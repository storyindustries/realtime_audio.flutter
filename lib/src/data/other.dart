import 'package:freezed_annotation/freezed_annotation.dart';

enum RealtimeAudioRecordPermission {
  undetermined,
  denied,
  granted,
}

abstract final class RealtimeAudioErrorCode {
  /// iOS rejected AVAudioSession activation because another call/app owns a
  /// higher-priority session. Safe for callers to present as recoverable.
  static const String audioSessionInsufficientPriority =
      'audio_session_insufficient_priority';
}

/// Which echo-cancellation mechanism the native engine is actually driving for
/// the current capture path. Reported by read-back, never assumed.
///
/// - [none]: no echo cancellation is active (e.g. recorder disabled, or voice
///   processing failed / was not requested).
/// - [webrtcApm]: the bundled WebRTC Audio Processing Module (software AEC),
///   used on Android.
/// - [platformAec]: a platform echo canceller — input-node VoiceProcessingIO
///   on iOS, or the Android `VOICE_COMMUNICATION` capture source. On Android
///   this path's liveness cannot be read back.
enum RealtimeAudioEchoCancellationMechanism {
  @JsonValue('none')
  none,
  @JsonValue('webrtc_apm')
  webrtcApm,
  @JsonValue('platform_aec')
  platformAec,
}
