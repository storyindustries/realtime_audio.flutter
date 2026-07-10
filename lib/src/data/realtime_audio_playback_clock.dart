import 'package:freezed_annotation/freezed_annotation.dart';

part 'realtime_audio_playback_clock.freezed.dart';
part 'realtime_audio_playback_clock.g.dart';

/// A synchronous snapshot of the player's call-lifetime playback counters,
/// returned by [RealtimeAudio.getPlayerPlayedDuration] (and carried on the
/// [RealtimeAudioInstanceResponseClearQueue] returned by `clearQueue`).
///
/// All three counters are **call-lifetime monotonic** — they are NOT reset per
/// stream. The current playing segment is folded into a base before every player
/// stop (the platform playback head resets to `0` on stop), so the values
/// survive `stop`/`clearQueue`/natural drain; a fresh engine is the only reset.
/// The consumer computes a per-stream delta by subtracting a baseline captured
/// at stream start. See the README for the full reset table.
@freezed
abstract class RealtimeAudioPlaybackClock with _$RealtimeAudioPlaybackClock {
  const RealtimeAudioPlaybackClock._();

  const factory RealtimeAudioPlaybackClock({
    /// Completion-INDEPENDENT render clock (ms): the platform playback-head
    /// timeline (iOS `AVAudioPlayerNode.playerTime`, Android
    /// `AudioTrack.playbackHeadPosition`), folded across stops. Keeps advancing
    /// even when per-buffer completion callbacks stall or die — this is the
    /// device-truth "how much actually played out" signal.
    @Default(0) int renderClockMs,

    /// Completion-DRIVEN rendered ms: accumulated only from real playout
    /// completions (iOS `.dataPlayedBack`; flushed buffers never count). On
    /// Android — which has no per-buffer playout callback — this mirrors
    /// [renderClockMs].
    @Default(0) int renderedMs,

    /// Total ms ever scheduled onto the player (monotonic upper bound).
    @Default(0) int scheduledMs,

    /// Whether the device is actively rendering right now: buffers outstanding
    /// (or within the post-drain hangover), and not paused.
    @Default(false) bool isRendering,
  }) = _RealtimeAudioPlaybackClock;

  factory RealtimeAudioPlaybackClock.fromJson(Map<String, dynamic> json) =>
      _$RealtimeAudioPlaybackClockFromJson(json);

  /// [renderClockMs] as a [Duration].
  Duration get renderClock => Duration(milliseconds: renderClockMs);
}
