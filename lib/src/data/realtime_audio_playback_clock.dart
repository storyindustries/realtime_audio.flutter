import 'package:freezed_annotation/freezed_annotation.dart';

part 'realtime_audio_playback_clock.freezed.dart';
part 'realtime_audio_playback_clock.g.dart';

/// A synchronous snapshot of the player's completion-independent render clock,
/// returned by [RealtimeAudio.getPlayerPlayedDuration].
///
/// [renderedMs] is derived from the platform playback-head clock (iOS
/// `AVAudioPlayerNode.playerTime`, Android `AudioTrack.playbackHeadPosition`),
/// **not** from per-buffer completion callbacks, so it stays truthful even when
/// those callbacks stall or die.
///
/// Reset semantics (see the README for the full table):
/// - Advances monotonically while the device renders queued PCM.
/// - Holds across `pause`/`resume`.
/// - Latches its final value across `stop`/`clearQueue`/natural drain (the
///   playback head is reset by the platform, but the last rendered amount stays
///   readable) so a post-drain read still reports device truth.
/// - Resets to `0` once a new stream begins rendering.
@freezed
abstract class RealtimeAudioPlaybackClock with _$RealtimeAudioPlaybackClock {
  const RealtimeAudioPlaybackClock._();

  const factory RealtimeAudioPlaybackClock({
    /// Milliseconds of the current/last stream the device actually rendered.
    @Default(0) int renderedMs,

    /// Whether the device is actively rendering queued PCM ahead of the head
    /// right now (false when paused, stalled, drained, or stopped).
    @Default(false) bool isRendering,

    /// Total queued milliseconds of the current stream (rendered + pending).
    @Default(0) int durationTotalMs,
  }) = _RealtimeAudioPlaybackClock;

  factory RealtimeAudioPlaybackClock.fromJson(Map<String, dynamic> json) =>
      _$RealtimeAudioPlaybackClockFromJson(json);

  /// [renderedMs] as a [Duration].
  Duration get rendered => Duration(milliseconds: renderedMs);
}
