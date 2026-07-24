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
      erleDb: (json['erleDb'] as num?)?.toDouble(),
      apmMode: json['apmMode'] as String?,
    );

Map<String, dynamic> _$RealtimeAudioEchoCancellationStateToJson(
  _RealtimeAudioEchoCancellationState instance,
) => <String, dynamic>{
  'requested': instance.requested,
  'nativeEnabled': instance.nativeEnabled,
  'mechanism':
      _$RealtimeAudioEchoCancellationMechanismEnumMap[instance.mechanism]!,
  'captureProvenLive': instance.captureProvenLive,
  'erleDb': instance.erleDb,
  'apmMode': instance.apmMode,
};

const _$RealtimeAudioEchoCancellationMechanismEnumMap = {
  RealtimeAudioEchoCancellationMechanism.none: 'none',
  RealtimeAudioEchoCancellationMechanism.webrtcApm: 'webrtc_apm',
  RealtimeAudioEchoCancellationMechanism.platformAec: 'platform_aec',
};
