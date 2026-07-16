enum RealtimeAudioEngineHealthEventType {
  configurationChangeIgnoredHealthy,
  configurationChangeRecoveryStarted,
  configurationChangeRecovered,
  configurationChangeRecoveryFailed,
  playbackDrainSignalFailed,
  playbackQueueDrained,
  unknown;

  static RealtimeAudioEngineHealthEventType fromWire(String value) {
    return switch (value) {
      'configuration_change_ignored_healthy' =>
        configurationChangeIgnoredHealthy,
      'configuration_change_recovery_started' =>
        configurationChangeRecoveryStarted,
      'configuration_change_recovered' => configurationChangeRecovered,
      'configuration_change_recovery_failed' =>
        configurationChangeRecoveryFailed,
      'playback_drain_signal_failed' => playbackDrainSignalFailed,
      'playback_queue_drained' => playbackQueueDrained,
      _ => unknown,
    };
  }
}

/// Structured native audio-engine lifecycle signal.
///
/// Configuration-change recovery is separate from recorder conversion errors:
/// callers need to distinguish a benign notification from a failed graph
/// restart without parsing debug strings.
class RealtimeAudioEngineHealthEvent {
  const RealtimeAudioEngineHealthEvent({
    required this.type,
    required this.engineWasRunning,
    required this.queuedChunkCount,
    this.message,
    this.outputRoute,
    this.outputSampleRate,
  });

  factory RealtimeAudioEngineHealthEvent.fromMap(Map<String, dynamic> map) {
    return RealtimeAudioEngineHealthEvent(
      type: RealtimeAudioEngineHealthEventType.fromWire(
        map['type'] as String? ?? '',
      ),
      engineWasRunning: map['engineWasRunning'] as bool? ?? false,
      queuedChunkCount: map['queuedChunkCount'] as int? ?? 0,
      message: map['message'] as String?,
      outputRoute: map['outputRoute'] as String?,
      outputSampleRate: map['outputSampleRate'] as int?,
    );
  }

  final RealtimeAudioEngineHealthEventType type;
  final bool engineWasRunning;
  final int queuedChunkCount;
  final String? message;

  /// Coarse route class only; never a device name or identifier.
  final String? outputRoute;
  final int? outputSampleRate;
}
