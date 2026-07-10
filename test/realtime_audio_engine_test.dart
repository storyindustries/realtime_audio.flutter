import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_audio/realtime_audio.dart';

const _pluginChannel = MethodChannel('dev.volskaya.RealtimeAudio/plugin');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('data model decoding', () {
    test('RealtimeAudioState decodes the additive render-clock fields', () {
      final state = RealtimeAudioState.fromJson(const {
        'isPlaying': false,
        'isPaused': false,
        'duration': 0,
        'durationTotal': 4000,
        'chunkCount': 0,
        'renderedMs': 3820,
        'isRendering': false,
      });

      // `duration` (live head) resets to 0 at stop, but `renderedMs` latches the
      // device-truth amount actually rendered before the reset.
      expect(state.duration, 0);
      expect(state.renderedMs, 3820);
      expect(state.isRendering, false);
    });

    test('RealtimeAudioState defaults the new fields when absent', () {
      final state = RealtimeAudioState.fromJson(const {'isPlaying': true});
      expect(state.renderedMs, 0);
      expect(state.isRendering, false);
    });

    test('RealtimeAudioPlaybackClock decodes and exposes rendered Duration', () {
      final clock = RealtimeAudioPlaybackClock.fromJson(const {
        'renderedMs': 1234,
        'isRendering': true,
        'durationTotalMs': 5000,
      });

      expect(clock.renderedMs, 1234);
      expect(clock.isRendering, true);
      expect(clock.durationTotalMs, 5000);
      expect(clock.rendered, const Duration(milliseconds: 1234));
    });

    test('RealtimeAudioEchoCancellationState trust predicate follows bubbles', () {
      RealtimeAudioEchoCancellationState decode(Map<String, dynamic> json) =>
          RealtimeAudioEchoCancellationState.fromJson(json);

      final trusted = decode(const {
        'requested': true,
        'nativeEnabled': true,
        'mechanism': 'appleVoiceProcessingIO',
        'captureProvenLive': true,
      });
      expect(trusted.mechanism, RealtimeAudioEchoCancellationMechanism.appleVoiceProcessingIO);
      expect(trusted.trustsFullDuplex, true);

      // Requested + mechanism present, but the device never confirmed enable and
      // no live capture buffer arrived → NOT trusted (never assume).
      final notReadBack = decode(const {
        'requested': true,
        'nativeEnabled': false,
        'mechanism': 'webRtcApm',
        'captureProvenLive': true,
      });
      expect(notReadBack.trustsFullDuplex, false);

      final noCapture = decode(const {
        'requested': true,
        'nativeEnabled': true,
        'mechanism': 'webRtcApm',
        'captureProvenLive': false,
      });
      expect(noCapture.trustsFullDuplex, false);

      final unknownMechanism = decode(const {
        'requested': false,
        'nativeEnabled': false,
        'mechanism': 'something-new',
        'captureProvenLive': false,
      });
      expect(unknownMechanism.mechanism, RealtimeAudioEchoCancellationMechanism.none);
      expect(unknownMechanism.trustsFullDuplex, false);
    });
  });

  group('method channel round-trips', () {
    late RealtimeAudio audio;
    MethodChannel? engineChannel;

    setUp(() async {
      messenger.setMockMethodCallHandler(_pluginChannel, (call) async {
        switch (call.method) {
          case 'create':
            return <String, dynamic>{'id': 'test-engine'};
          case 'destroy':
            return <String, dynamic>{};
        }
        return null;
      });

      audio = RealtimeAudio(recorderEnabled: true);
      await audio.isInitialized;
      engineChannel = const MethodChannel('dev.volskaya.RealtimeAudio/engines/test-engine');
    });

    tearDown(() async {
      messenger.setMockMethodCallHandler(engineChannel!, null);
      messenger.setMockMethodCallHandler(_pluginChannel, null);
    });

    test('getPlayerPlayedDuration invokes the engine channel and types the result', () async {
      final invoked = <String>[];
      messenger.setMockMethodCallHandler(engineChannel!, (call) async {
        invoked.add(call.method);
        if (call.method == 'getPlayerPlayedDuration') {
          return <String, dynamic>{
            'renderedMs': 3820,
            'isRendering': false,
            'durationTotalMs': 4000,
          };
        }
        return null;
      });

      final clock = await audio.getPlayerPlayedDuration();

      expect(invoked, contains('getPlayerPlayedDuration'));
      expect(clock, isNotNull);
      expect(clock!.renderedMs, 3820);
      expect(clock.isRendering, false);
      expect(clock.durationTotalMs, 4000);
    });

    test('getEchoCancellationState invokes the engine channel and types the result', () async {
      final invoked = <String>[];
      messenger.setMockMethodCallHandler(engineChannel!, (call) async {
        invoked.add(call.method);
        if (call.method == 'getEchoCancellationState') {
          return <String, dynamic>{
            'requested': true,
            'nativeEnabled': true,
            'mechanism': 'appleVoiceProcessingIO',
            'captureProvenLive': true,
          };
        }
        return null;
      });

      final aec = await audio.getEchoCancellationState();

      expect(invoked, contains('getEchoCancellationState'));
      expect(aec, isNotNull);
      expect(aec!.requested, true);
      expect(aec.nativeEnabled, true);
      expect(aec.mechanism, RealtimeAudioEchoCancellationMechanism.appleVoiceProcessingIO);
      expect(aec.captureProvenLive, true);
      expect(aec.trustsFullDuplex, true);
    });
  });
}
