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
    /// Device-truth milliseconds the player has actually rendered for the
    /// current stream. Unlike [duration] (the live playback head, which resets
    /// to `0` at stop), this **latches** its final value across
    /// stop/clearQueue/drain, so the terminal `isPlaying: false` state still
    /// reports how much was rendered. Resets to `0` when a new stream begins.
    @Default(0) int renderedMs,

    /// Whether the device is actively rendering queued PCM ahead of the head
    /// (false when paused, stalled, drained, or stopped).
    @Default(false) bool isRendering,
  }) = _RealtimeAudioState;

  factory RealtimeAudioState.fromJson(Map<String, dynamic> json) => _$RealtimeAudioStateFromJson(json);
}
