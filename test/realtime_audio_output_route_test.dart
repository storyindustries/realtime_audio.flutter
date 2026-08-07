import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_audio/realtime_audio.dart';

const _pluginChannel = MethodChannel('dev.volskaya.RealtimeAudio/plugin');
const _engineChannel = MethodChannel(
  'dev.volskaya.RealtimeAudio/engines/route-engine',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('route state decodes only coarse public values', () {
    final state = RealtimeAudioOutputRouteState.fromMap(const {
      'active': 'speaker',
      'available': ['receiver', 'speaker', 'bluetooth', 'future-route'],
      'requested': 'bluetooth',
      'selectionResult': 'applied',
      'volumeControlStream': 'voice_call',
      'volume': 0.75,
    });

    expect(state.active, RealtimeAudioOutputRoute.speaker);
    expect(state.available, [
      RealtimeAudioOutputRoute.receiver,
      RealtimeAudioOutputRoute.speaker,
      RealtimeAudioOutputRoute.bluetooth,
    ]);
    expect(state.requested, RealtimeAudioOutputRoute.bluetooth);
    expect(
      state.selectionResult,
      RealtimeAudioOutputRouteSelectionResult.applied,
    );
    expect(state.volumeControlStream, 'voice_call');
    expect(state.volume, 0.75);

    final pending = RealtimeAudioOutputRouteState.fromMap(const {
      'selectionResult': 'pending',
    });
    expect(
      pending.selectionResult,
      RealtimeAudioOutputRouteSelectionResult.pending,
    );
  });

  test(
    'route selection, readback, volume floor, and stream are typed',
    () async {
      messenger.setMockMethodCallHandler(_pluginChannel, (call) async {
        if (call.method == 'create') return {'id': 'route-engine'};
        if (call.method == 'destroy') return <String, dynamic>{};
        return null;
      });

      var state = <String, dynamic>{
        'active': 'receiver',
        'available': ['receiver', 'speaker'],
        'requested': null,
        'selectionResult': 'automatic',
        'volumeControlStream': 'voice_call',
        'volume': 0.2,
      };
      messenger.setMockMethodCallHandler(_engineChannel, (call) async {
        switch (call.method) {
          case 'getOutputRouteState':
            return state;
          case 'setOutputRoute':
            expect(call.arguments, {'route': 'speaker'});
            state = {...state, 'active': 'speaker', 'requested': 'speaker'};
            return state;
          case 'ensureMinimumPlaybackVolume':
            expect(call.arguments, {'minimum': 0.6});
            state = {...state, 'volume': 0.6};
            return state;
        }
        return null;
      });

      final audio = RealtimeAudio();
      addTearDown(() async {
        await audio.dispose();
        messenger.setMockMethodCallHandler(_engineChannel, null);
        messenger.setMockMethodCallHandler(_pluginChannel, null);
      });

      final initial = await audio.getOutputRouteState();
      expect(initial?.active, RealtimeAudioOutputRoute.receiver);
      expect(audio.outputRouteState, initial);

      final emitted = expectLater(
        audio.outputRouteStateStream,
        emits(
          isA<RealtimeAudioOutputRouteState>().having(
            (value) => value.active,
            'active',
            RealtimeAudioOutputRoute.bluetooth,
          ),
        ),
      );
      await messenger.handlePlatformMessage(
        _engineChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('outputRouteState', <String, dynamic>{
            'active': 'bluetooth',
            'available': ['receiver', 'speaker', 'bluetooth'],
            'requested': null,
            'selectionResult': 'automatic',
            'volumeControlStream': 'voice_call',
            'volume': 0.2,
          }),
        ),
        (_) {},
      );
      await emitted;

      final selected = await audio.setOutputRoute(
        RealtimeAudioOutputRoute.speaker,
      );
      expect(selected?.requested, RealtimeAudioOutputRoute.speaker);

      final raised = await audio.ensureMinimumPlaybackVolume(0.6);
      expect(raised?.volume, 0.6);
    },
  );

  test('initialization reads back and emits the initial route', () async {
    const initialEngineChannel = MethodChannel(
      'dev.volskaya.RealtimeAudio/engines/initial-route-engine',
    );
    messenger.setMockMethodCallHandler(_pluginChannel, (call) async {
      if (call.method == 'create') return {'id': 'initial-route-engine'};
      if (call.method == 'destroy') return <String, dynamic>{};
      return null;
    });
    messenger.setMockMethodCallHandler(initialEngineChannel, (call) async {
      if (call.method == 'getOutputRouteState') {
        return <String, dynamic>{
          'active': 'speaker',
          'available': ['receiver', 'speaker'],
          'requested': null,
          'selectionResult': 'automatic',
          'volumeControlStream': 'voice_call',
          'volume': 0.6,
        };
      }
      return null;
    });
    final audio = RealtimeAudio();
    addTearDown(() async {
      await audio.dispose();
      messenger.setMockMethodCallHandler(initialEngineChannel, null);
      messenger.setMockMethodCallHandler(_pluginChannel, null);
    });

    final initial = expectLater(
      audio.outputRouteStateStream,
      emits(
        isA<RealtimeAudioOutputRouteState>().having(
          (value) => value.active,
          'active',
          RealtimeAudioOutputRoute.speaker,
        ),
      ),
    );
    await audio.start();
    await initial;
    expect(audio.outputRouteState?.volumeControlStream, 'voice_call');
  });
}
