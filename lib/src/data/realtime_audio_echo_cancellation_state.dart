import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:realtime_audio/src/data/other.dart';

part 'realtime_audio_echo_cancellation_state.freezed.dart';
part 'realtime_audio_echo_cancellation_state.g.dart';

/// Live read-back of the acoustic echo cancellation (AEC) path, returned by
/// [RealtimeAudio.getEchoCancellationState].
///
/// AEC is never assumed to be active just because it was requested — the native
/// engine reads the real state back from the platform (iOS
/// `AVAudioInputNode.isVoiceProcessingEnabled`, Android WebRTC APM availability)
/// and reports whether the mic capture path has actually delivered a buffer.
@freezed
abstract class RealtimeAudioEchoCancellationState with _$RealtimeAudioEchoCancellationState {
  const RealtimeAudioEchoCancellationState._();

  const factory RealtimeAudioEchoCancellationState({
    /// Whether voice processing / AEC was requested for this engine.
    @Default(false) bool requested,

    /// Whether the platform confirmed (by read-back) that AEC is enabled.
    @Default(false) bool nativeEnabled,

    /// Which mechanism the engine is driving. Unknown values decode to
    /// [RealtimeAudioEchoCancellationMechanism.none].
    @JsonKey(unknownEnumValue: RealtimeAudioEchoCancellationMechanism.none)
    @Default(RealtimeAudioEchoCancellationMechanism.none)
    RealtimeAudioEchoCancellationMechanism mechanism,

    /// Whether the mic capture path has delivered its first real buffer.
    @Default(false) bool captureProvenLive,
  }) = _RealtimeAudioEchoCancellationState;

  factory RealtimeAudioEchoCancellationState.fromJson(Map<String, dynamic> json) =>
      _$RealtimeAudioEchoCancellationStateFromJson(json);

  /// The "trust full-duplex" predicate: AEC was requested, the platform
  /// confirmed it is enabled, and real mic capture has started. Mirrors the
  /// bubbles client's `trustsFullDuplex`.
  bool get trustsFullDuplex => requested && nativeEnabled && captureProvenLive;
}
