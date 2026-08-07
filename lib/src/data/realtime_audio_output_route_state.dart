import 'package:flutter/foundation.dart';

/// Coarse output categories. Native device names and identifiers never cross
/// the plugin boundary.
enum RealtimeAudioOutputRoute {
  speaker,
  receiver,
  wired,
  bluetooth,

  /// Readback-only fallback for platform routes without a selectable category.
  other;

  static RealtimeAudioOutputRoute? fromWire(Object? value) => switch (value) {
    'speaker' => speaker,
    'receiver' => receiver,
    'wired' => wired,
    'bluetooth' => bluetooth,
    null => null,
    _ => other,
  };
}

enum RealtimeAudioOutputRouteSelectionResult {
  automatic,
  applied,
  pending,
  failed,
  unavailable;

  static RealtimeAudioOutputRouteSelectionResult fromWire(Object? value) =>
      switch (value) {
        'applied' => applied,
        'pending' => pending,
        'failed' => failed,
        'unavailable' => unavailable,
        _ => automatic,
      };
}

@immutable
class RealtimeAudioOutputRouteState {
  const RealtimeAudioOutputRouteState({
    required this.active,
    required this.available,
    required this.requested,
    required this.selectionResult,
    required this.volumeControlStream,
    required this.volume,
  });

  factory RealtimeAudioOutputRouteState.fromMap(Map<Object?, Object?> map) {
    final available = (map['available'] as List<Object?>? ?? const [])
        .map(RealtimeAudioOutputRoute.fromWire)
        .whereType<RealtimeAudioOutputRoute>()
        .where((route) => route != RealtimeAudioOutputRoute.other)
        .toList(growable: false);
    return RealtimeAudioOutputRouteState(
      active: RealtimeAudioOutputRoute.fromWire(map['active']),
      available: available,
      requested: RealtimeAudioOutputRoute.fromWire(map['requested']),
      selectionResult: RealtimeAudioOutputRouteSelectionResult.fromWire(
        map['selectionResult'],
      ),
      volumeControlStream: map['volumeControlStream'] as String?,
      volume: (map['volume'] as num?)?.toDouble(),
    );
  }

  final RealtimeAudioOutputRoute? active;
  final List<RealtimeAudioOutputRoute> available;
  final RealtimeAudioOutputRoute? requested;
  final RealtimeAudioOutputRouteSelectionResult selectionResult;

  /// Stable, coarse platform stream category such as `voice_call` or `music`.
  final String? volumeControlStream;

  /// Current user-controlled output volume normalized to 0–1.
  final double? volume;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RealtimeAudioOutputRouteState &&
          other.active == active &&
          listEquals(other.available, available) &&
          other.requested == requested &&
          other.selectionResult == selectionResult &&
          other.volumeControlStream == volumeControlStream &&
          other.volume == volume;

  @override
  int get hashCode => Object.hash(
    active,
    Object.hashAll(available),
    requested,
    selectionResult,
    volumeControlStream,
    volume,
  );
}
