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
        'renderClockMs': 3820,
        'isRendering': false,
      });

      // `duration` (live per-segment head) resets to 0 at stop, but the
      // call-lifetime `renderClockMs` survives the reset (folded).
      expect(state.duration, 0);
      expect(state.renderClockMs, 3820);
      expect(state.isRendering, false);
    });

    test('RealtimeAudioState defaults the new fields when absent', () {
      final state = RealtimeAudioState.fromJson(const {'isPlaying': true});
      expect(state.renderClockMs, 0);
      expect(state.isRendering, false);
    });

    test('RealtimeAudioPlaybackClock decodes the three lifetime counters', () {
      final clock = RealtimeAudioPlaybackClock.fromJson(const {
        'renderClockMs': 3820,
        'renderedMs': 3800,
        'scheduledMs': 4000,
        'isRendering': true,
      });

      expect(clock.renderClockMs, 3820);
      expect(clock.renderedMs, 3800);
      expect(clock.scheduledMs, 4000);
      expect(clock.isRendering, true);
      expect(clock.renderClock, const Duration(milliseconds: 3820));
    });

    test('RealtimeAudioEchoCancellationState trust predicate follows bubbles', () {
      RealtimeAudioEchoCancellationState decode(Map<String, dynamic> json) =>
          RealtimeAudioEchoCancellationState.fromJson(json);

      final trusted = decode(const {
        'requested': true,
        'nativeEnabled': true,
        'mechanism': 'platform_aec',
        'captureProvenLive': true,
      });
      expect(trusted.mechanism, RealtimeAudioEchoCancellationMechanism.platformAec);
      expect(trusted.trustsFullDuplex, true);

      // Requested + mechanism present, but the device never confirmed enable →
      // NOT trusted (never assume).
      final notReadBack = decode(const {
        'requested': true,
        'nativeEnabled': false,
        'mechanism': 'webrtc_apm',
        'captureProvenLive': true,
      });
      expect(notReadBack.mechanism, RealtimeAudioEchoCancellationMechanism.webrtcApm);
      expect(notReadBack.trustsFullDuplex, false);

      final noCapture = decode(const {
        'requested': true,
        'nativeEnabled': true,
        'mechanism': 'webrtc_apm',
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
            'renderClockMs': 3820,
            'renderedMs': 3800,
            'scheduledMs': 4000,
            'isRendering': false,
          };
        }
        return null;
      });

      final clock = await audio.getPlayerPlayedDuration();

      expect(invoked, contains('getPlayerPlayedDuration'));
      expect(clock, isNotNull);
      expect(clock!.renderClockMs, 3820);
      expect(clock.renderedMs, 3800);
      expect(clock.scheduledMs, 4000);
      expect(clock.isRendering, false);
    });

    test('clearQueue returns the folded lifetime clock alongside the chunk', () async {
      messenger.setMockMethodCallHandler(engineChannel!, (call) async {
        if (call.method == 'clearQueue') {
          return <String, dynamic>{
            'chunk': <String, dynamic>{
              'id': 'chunk-1',
              'sampleRate': 24000.0,
              'sampleTime': 2400,
              'sampleTimeTotal': 4800,
              'chunkSampleTime': 1200,
              'chunkSampleTimeTotal': 2400,
            },
            'clock': <String, dynamic>{
              'renderClockMs': 1900,
              'renderedMs': 1850,
              'scheduledMs': 4000,
              'isRendering': false,
            },
          };
        }
        return null;
      });

      final response = await audio.clearQueue();

      expect(response, isNotNull);
      expect(response!.chunk?.id, 'chunk-1');
      // The barge cut position, device-truth, comes from the folded render clock.
      expect(response.clock?.renderClockMs, 1900);
      expect(response.clock?.scheduledMs, 4000);
    });

    test('getEchoCancellationState invokes the engine channel and types the result', () async {
      final invoked = <String>[];
      messenger.setMockMethodCallHandler(engineChannel!, (call) async {
        invoked.add(call.method);
        if (call.method == 'getEchoCancellationState') {
          return <String, dynamic>{
            'requested': true,
            'nativeEnabled': true,
            'mechanism': 'platform_aec',
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
      expect(aec.mechanism, RealtimeAudioEchoCancellationMechanism.platformAec);
      expect(aec.captureProvenLive, true);
      expect(aec.trustsFullDuplex, true);
    });
  });
}
