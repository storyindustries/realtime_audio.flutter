enum RealtimeAudioEngineHealthEventType {
  configurationChangeIgnoredHealthy,
  configurationChangeRecoveryStarted,
  configurationChangeRecovered,
  configurationChangeRecoveryFailed,
  unknown;

  static RealtimeAudioEngineHealthEventType fromWire(String value) {
    return switch (value) {
      'configuration_change_ignored_healthy' => configurationChangeIgnoredHealthy,
      'configuration_change_recovery_started' => configurationChangeRecoveryStarted,
      'configuration_change_recovered' => configurationChangeRecovered,
      'configuration_change_recovery_failed' => configurationChangeRecoveryFailed,
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
  });

  factory RealtimeAudioEngineHealthEvent.fromMap(Map<String, dynamic> map) {
    return RealtimeAudioEngineHealthEvent(
      type: RealtimeAudioEngineHealthEventType.fromWire(
        map['type'] as String? ?? '',
      ),
      engineWasRunning: map['engineWasRunning'] as bool? ?? false,
      queuedChunkCount: map['queuedChunkCount'] as int? ?? 0,
      message: map['message'] as String?,
    );
  }

  final RealtimeAudioEngineHealthEventType type;
  final bool engineWasRunning;
  final int queuedChunkCount;
  final String? message;
}
