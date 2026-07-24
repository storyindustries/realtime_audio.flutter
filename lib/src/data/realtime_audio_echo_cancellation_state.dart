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
abstract class RealtimeAudioEchoCancellationState
    with _$RealtimeAudioEchoCancellationState {
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

    /// The software APM's measured echo-return-loss-enhancement (dB), when it
    /// reports one. Null on the platform mechanism and on AECM; AEC3 reports
    /// from its first processed block (~0 dB while unconverged), so presence
    /// alone is instantiation evidence — the trust predicate demands the
    /// converged threshold.
    double? erleDb,

    /// `aec3` | `aecm` while the software APM runs; null otherwise.
    String? apmMode,
  }) = _RealtimeAudioEchoCancellationState;

  factory RealtimeAudioEchoCancellationState.fromJson(
    Map<String, dynamic> json,
  ) => _$RealtimeAudioEchoCancellationStateFromJson(json);

  /// ERLE at/above which the software canceller is considered converged.
  /// Conservative: a converged AEC3 typically reports well above this.
  static const double erleTrustThresholdDb = 6.0;

  /// The "trust full-duplex" predicate: AEC was requested, the platform
  /// confirmed it is enabled, and real mic capture has started — PLUS, for
  /// the software APM, measured cancellation evidence. A RUNNING canceller is
  /// not a CANCELLING one (2026-07-24 Android echo RCA: liveness-based trust
  /// ran full duplex over a dead APM); the platform mechanism (iOS VPIO /
  /// Android hardware AEC) is OEM-attested and reports no ERLE.
  bool get trustsFullDuplex {
    if (!requested || !nativeEnabled || !captureProvenLive) {
      return false;
    }
    if (mechanism == RealtimeAudioEchoCancellationMechanism.webrtcApm) {
      final double? erle = erleDb;
      return erle != null && erle >= erleTrustThresholdDb;
    }
    return mechanism == RealtimeAudioEchoCancellationMechanism.platformAec;
  }
}
