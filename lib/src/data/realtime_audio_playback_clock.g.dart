// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'realtime_audio_playback_clock.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RealtimeAudioPlaybackClock _$RealtimeAudioPlaybackClockFromJson(Map json) =>
    _RealtimeAudioPlaybackClock(
      renderClockMs: (json['renderClockMs'] as num?)?.toInt() ?? 0,
      renderedMs: (json['renderedMs'] as num?)?.toInt() ?? 0,
      scheduledMs: (json['scheduledMs'] as num?)?.toInt() ?? 0,
      isRendering: json['isRendering'] as bool? ?? false,
    );

Map<String, dynamic> _$RealtimeAudioPlaybackClockToJson(
  _RealtimeAudioPlaybackClock instance,
) => <String, dynamic>{
  'renderClockMs': instance.renderClockMs,
  'renderedMs': instance.renderedMs,
  'scheduledMs': instance.scheduledMs,
  'isRendering': instance.isRendering,
};
