import 'package:realtime_audio/src/data/realtime_audio_playback_clock.dart';

enum RealtimeAudioPlaybackAccountingRepairReason {
  repaired,
  noOutstandingBuffers,
  scheduledExtentChanged,
  unknown;

  static RealtimeAudioPlaybackAccountingRepairReason fromWire(String value) {
    return switch (value) {
      'repaired' => repaired,
      'no_outstanding_buffers' => noOutstandingBuffers,
      'scheduled_extent_changed' => scheduledExtentChanged,
      _ => unknown,
    };
  }
}

class RealtimeAudioPlaybackAccountingRepair {
  const RealtimeAudioPlaybackAccountingRepair({
    required this.repaired,
    required this.reason,
    required this.clock,
  });

  factory RealtimeAudioPlaybackAccountingRepair.fromMap(Map<String, dynamic> map) {
    return RealtimeAudioPlaybackAccountingRepair(
      repaired: map['repaired'] as bool? ?? false,
      reason: RealtimeAudioPlaybackAccountingRepairReason.fromWire(map['reason'] as String? ?? ''),
      clock: RealtimeAudioPlaybackClock.fromJson(Map<String, dynamic>.from(map['clock'] as Map)),
    );
  }

  final bool repaired;
  final RealtimeAudioPlaybackAccountingRepairReason reason;
  final RealtimeAudioPlaybackClock clock;
}

class RealtimeAudioPlaybackWedgeRecovery {
  const RealtimeAudioPlaybackWedgeRecovery({
    required this.recovered,
    required this.clock,
    this.message,
  });

  factory RealtimeAudioPlaybackWedgeRecovery.fromMap(Map<String, dynamic> map) {
    return RealtimeAudioPlaybackWedgeRecovery(
      recovered: map['recovered'] as bool? ?? false,
      clock: RealtimeAudioPlaybackClock.fromJson(Map<String, dynamic>.from(map['clock'] as Map)),
      message: map['message'] as String?,
    );
  }

  final bool recovered;
  final RealtimeAudioPlaybackClock clock;
  final String? message;
}
