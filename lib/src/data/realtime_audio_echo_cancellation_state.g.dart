// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'realtime_audio_echo_cancellation_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RealtimeAudioEchoCancellationState
_$RealtimeAudioEchoCancellationStateFromJson(Map json) =>
    _RealtimeAudioEchoCancellationState(
      requested: json['requested'] as bool? ?? false,
      nativeEnabled: json['nativeEnabled'] as bool? ?? false,
      mechanism:
          $enumDecodeNullable(
            _$RealtimeAudioEchoCancellationMechanismEnumMap,
            json['mechanism'],
            unknownValue: RealtimeAudioEchoCancellationMechanism.none,
          ) ??
          RealtimeAudioEchoCancellationMechanism.none,
      captureProvenLive: json['captureProvenLive'] as bool? ?? false,
    );

Map<String, dynamic> _$RealtimeAudioEchoCancellationStateToJson(
  _RealtimeAudioEchoCancellationState instance,
) => <String, dynamic>{
  'requested': instance.requested,
  'nativeEnabled': instance.nativeEnabled,
  'mechanism':
      _$RealtimeAudioEchoCancellationMechanismEnumMap[instance.mechanism]!,
  'captureProvenLive': instance.captureProvenLive,
};

const _$RealtimeAudioEchoCancellationMechanismEnumMap = {
  RealtimeAudioEchoCancellationMechanism.none: 'none',
  RealtimeAudioEchoCancellationMechanism.appleVoiceProcessingIO:
      'appleVoiceProcessingIO',
  RealtimeAudioEchoCancellationMechanism.webRtcApm: 'webRtcApm',
  RealtimeAudioEchoCancellationMechanism.platformVoiceCommunication:
      'platformVoiceCommunication',
};
