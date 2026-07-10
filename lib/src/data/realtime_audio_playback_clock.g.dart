// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'realtime_audio_playback_clock.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RealtimeAudioPlaybackClock _$RealtimeAudioPlaybackClockFromJson(Map json) =>
    _RealtimeAudioPlaybackClock(
      renderedMs: (json['renderedMs'] as num?)?.toInt() ?? 0,
      isRendering: json['isRendering'] as bool? ?? false,
      durationTotalMs: (json['durationTotalMs'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$RealtimeAudioPlaybackClockToJson(
  _RealtimeAudioPlaybackClock instance,
) => <String, dynamic>{
  'renderedMs': instance.renderedMs,
  'isRendering': instance.isRendering,
  'durationTotalMs': instance.durationTotalMs,
};
