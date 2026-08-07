import 'package:freezed_annotation/freezed_annotation.dart';

part 'realtime_audio_state.freezed.dart';
part 'realtime_audio_state.g.dart';

@freezed
abstract class RealtimeAudioState with _$RealtimeAudioState {
  const factory RealtimeAudioState({
    @Default(false) bool isPlaying,
    @Default(false) bool isPaused,
    //
    @Default(0) int duration,
    @Default(0) int durationTotal,
    //
    @Default(0) int chunkCount,
    //
    /// Completion-independent, **call-lifetime** render clock (ms) — the device
    /// playback-head timeline, folded across stops (see
    /// [RealtimeAudioPlaybackClock.renderClockMs]). Unlike [duration] (the live
    /// per-segment head, which resets to `0` at stop), this survives
    /// stop/clearQueue/drain, so the terminal `isPlaying: false` state still
    /// reports the device-truth position. The consumer subtracts a baseline
    /// captured at stream start.
    @Default(0) int renderClockMs,

    /// Whether the device is actively rendering right now (buffers outstanding
    /// or within the post-drain hangover, and not paused).
    @Default(false) bool isRendering,
  }) = _RealtimeAudioState;

  factory RealtimeAudioState.fromJson(Map<String, dynamic> json) =>
      _$RealtimeAudioStateFromJson(json);
}
