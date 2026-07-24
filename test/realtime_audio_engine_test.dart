import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_audio/realtime_audio.dart';

const _pluginChannel = MethodChannel('dev.volskaya.RealtimeAudio/plugin');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('data model decoding', () {
    test('insufficient-priority platform error code is stable', () {
      expect(
        RealtimeAudioErrorCode.audioSessionInsufficientPriority,
        'audio_session_insufficient_priority',
      );
    });

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

    test(
      'barrel exposes RealtimeAudioInstanceResponseClearQueue with the folded clock',
      () {
        // Named directly from the package barrel — consumers must be able to type
        // clearQueue()'s response (and its .clock) without an implementation import.
        final RealtimeAudioInstanceResponseClearQueue response =
            RealtimeAudioInstanceResponseClearQueue.fromJson(const {
              'chunk': {
                'id': 'chunk-1',
                'sampleRate': 24000.0,
                'sampleTime': 2400,
                'sampleTimeTotal': 4800,
                'chunkSampleTime': 1200,
                'chunkSampleTimeTotal': 2400,
              },
              'clock': {
                'renderClockMs': 1900,
                'renderedMs': 1850,
                'scheduledMs': 4000,
                'isRendering': false,
              },
            });

        final RealtimeAudioClearQueueChunkData? chunk = response.chunk;
        final RealtimeAudioPlaybackClock? clock = response.clock;
        expect(chunk?.id, 'chunk-1');
        expect(clock?.renderClockMs, 1900);
        expect(clock?.scheduledMs, 4000);
      },
    );

    test(
      'RealtimeAudioEchoCancellationState trust predicate follows bubbles',
      () {
        RealtimeAudioEchoCancellationState decode(Map<String, dynamic> json) =>
            RealtimeAudioEchoCancellationState.fromJson(json);

        final trusted = decode(const {
          'requested': true,
          'nativeEnabled': true,
          'mechanism': 'platform_aec',
          'captureProvenLive': true,
        });
        expect(
          trusted.mechanism,
          RealtimeAudioEchoCancellationMechanism.platformAec,
        );
        expect(trusted.trustsFullDuplex, true);

        // Requested + mechanism present, but the device never confirmed enable →
        // NOT trusted (never assume).
        final notReadBack = decode(const {
          'requested': true,
          'nativeEnabled': false,
          'mechanism': 'webrtc_apm',
          'captureProvenLive': true,
        });
        expect(
          notReadBack.mechanism,
          RealtimeAudioEchoCancellationMechanism.webrtcApm,
        );
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
        expect(
          unknownMechanism.mechanism,
          RealtimeAudioEchoCancellationMechanism.none,
        );
        expect(unknownMechanism.trustsFullDuplex, false);
      },
    );

    test('software AEC trusts full duplex only on measured ERLE evidence', () {
      RealtimeAudioEchoCancellationState decode(Map<String, dynamic> json) =>
          RealtimeAudioEchoCancellationState.fromJson(json);

      // A RUNNING software APM is not a CANCELLING one — the 2026-07-24
      // Android echo RCA: liveness-based trust ran full duplex over a dead
      // canceller. webrtc_apm may claim full-duplex trust only once the APM's
      // own echo-return-loss-enhancement proves convergence.
      final runningButUnproven = decode(const {
        'requested': true,
        'nativeEnabled': true,
        'mechanism': 'webrtc_apm',
        'captureProvenLive': true,
      });
      expect(runningButUnproven.erleDb, isNull);
      expect(runningButUnproven.trustsFullDuplex, false);

      final weakErle = decode(const {
        'requested': true,
        'nativeEnabled': true,
        'mechanism': 'webrtc_apm',
        'captureProvenLive': true,
        'erleDb': 2.5,
        'apmMode': 'aec3',
      });
      expect(weakErle.trustsFullDuplex, false);

      final converged = decode(const {
        'requested': true,
        'nativeEnabled': true,
        'mechanism': 'webrtc_apm',
        'captureProvenLive': true,
        'erleDb': 9.0,
        'apmMode': 'aec3',
      });
      expect(converged.erleDb, 9.0);
      expect(converged.apmMode, 'aec3');
      expect(converged.trustsFullDuplex, true);

      // Pin the boundary itself: the threshold is inclusive (≥), and a value
      // epsilon below must not trust — a >=→> regression stays visible.
      final atThreshold = decode(const {
        'requested': true,
        'nativeEnabled': true,
        'mechanism': 'webrtc_apm',
        'captureProvenLive': true,
        'erleDb': RealtimeAudioEchoCancellationState.erleTrustThresholdDb,
      });
      expect(atThreshold.trustsFullDuplex, true);

      final justBelow = decode(const {
        'requested': true,
        'nativeEnabled': true,
        'mechanism': 'webrtc_apm',
        'captureProvenLive': true,
        'erleDb':
            RealtimeAudioEchoCancellationState.erleTrustThresholdDb - 0.001,
      });
      expect(justBelow.trustsFullDuplex, false);

      // The platform mechanism (iOS VPIO / Android hardware AEC) is
      // OEM-attested — no ERLE requirement (none is reported there).
      final platform = decode(const {
        'requested': true,
        'nativeEnabled': true,
        'mechanism': 'platform_aec',
        'captureProvenLive': true,
      });
      expect(platform.trustsFullDuplex, true);
    });

    test(
      'RealtimeAudioEngineHealthEvent decodes structured recovery outcomes',
      () {
        final event = RealtimeAudioEngineHealthEvent.fromMap(const {
          'type': 'configuration_change_recovery_failed',
          'engineWasRunning': false,
          'queuedChunkCount': 3,
          'message': 'audio input unavailable',
        });

        expect(
          event.type,
          RealtimeAudioEngineHealthEventType.configurationChangeRecoveryFailed,
        );
        expect(event.engineWasRunning, false);
        expect(event.queuedChunkCount, 3);
        expect(event.message, 'audio input unavailable');

        final drainFailure = RealtimeAudioEngineHealthEvent.fromMap(const {
          'type': 'playback_drain_signal_failed',
          'engineWasRunning': true,
          'queuedChunkCount': 1,
        });
        expect(
          drainFailure.type,
          RealtimeAudioEngineHealthEventType.playbackDrainSignalFailed,
        );

        final drained = RealtimeAudioEngineHealthEvent.fromMap(const {
          'type': 'playback_queue_drained',
          'engineWasRunning': true,
          'queuedChunkCount': 0,
          'outputRoute': 'bluetooth',
          'outputSampleRate': 48_000,
        });
        expect(
          drained.type,
          RealtimeAudioEngineHealthEventType.playbackQueueDrained,
        );
        expect(drained.outputRoute, 'bluetooth');
        expect(drained.outputSampleRate, 48_000);
      },
    );

    test('playback recovery results decode typed reasons and clocks', () {
      final repair = RealtimeAudioPlaybackAccountingRepair.fromMap(const {
        'repaired': false,
        'reason': 'scheduled_extent_changed',
        'clock': {
          'renderClockMs': 200,
          'renderedMs': 0,
          'scheduledMs': 280,
          'isRendering': true,
        },
      });
      final wedge = RealtimeAudioPlaybackWedgeRecovery.fromMap(const {
        'recovered': false,
        'message': 'engine restart failed',
        'clock': {
          'renderClockMs': 200,
          'renderedMs': 0,
          'scheduledMs': 280,
          'isRendering': false,
        },
      });

      expect(
        repair.reason,
        RealtimeAudioPlaybackAccountingRepairReason.scheduledExtentChanged,
      );
      expect(repair.clock.scheduledMs, 280);
      expect(wedge.recovered, false);
      expect(wedge.message, 'engine restart failed');
    });
  });

  test('start preserves a typed native create failure', () async {
    messenger.setMockMethodCallHandler(_pluginChannel, (call) async {
      if (call.method == 'create') {
        throw PlatformException(
          code: RealtimeAudioErrorCode.audioSessionInsufficientPriority,
          message: 'Another call owns audio',
        );
      }
      return null;
    });
    final audio = RealtimeAudio(recorderEnabled: true);
    addTearDown(() async {
      await audio.dispose();
      messenger.setMockMethodCallHandler(_pluginChannel, null);
    });

    await expectLater(
      audio.start(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          RealtimeAudioErrorCode.audioSessionInsufficientPriority,
        ),
      ),
    );
  });

  test('a failed create is retried instead of being cached forever', () async {
    var creates = 0;
    messenger.setMockMethodCallHandler(_pluginChannel, (call) async {
      switch (call.method) {
        case 'create':
          creates++;
          if (creates == 1) {
            throw PlatformException(
              code: RealtimeAudioErrorCode.audioSessionInsufficientPriority,
              message: 'Another call owns audio',
            );
          }
          return <String, dynamic>{'id': 'retried-engine'};
        case 'destroy':
          return <String, dynamic>{};
      }
      return null;
    });
    const retriedEngineChannel = MethodChannel(
      'dev.volskaya.RealtimeAudio/engines/retried-engine',
    );
    messenger.setMockMethodCallHandler(retriedEngineChannel, (_) async => null);
    final audio = RealtimeAudio(recorderEnabled: true);
    addTearDown(() async {
      await audio.dispose();
      messenger.setMockMethodCallHandler(retriedEngineChannel, null);
      messenger.setMockMethodCallHandler(_pluginChannel, null);
    });

    await expectLater(audio.start(), throwsA(isA<PlatformException>()));

    // `audio_session_insufficient_priority` is transient — another app owned
    // the session at that instant — so the next call must reach the platform.
    await audio.start();
    expect(creates, 2);
  });

  test('disposing an unused engine never creates a native one', () async {
    final invoked = <String>[];
    messenger.setMockMethodCallHandler(_pluginChannel, (call) async {
      invoked.add(call.method);
      if (call.method == 'create') {
        return <String, dynamic>{'id': 'never-created'};
      }
      return <String, dynamic>{};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_pluginChannel, null));

    await RealtimeAudio(recorderEnabled: true).dispose();

    expect(invoked, isEmpty);
  });

  test('a disposed engine does not re-create itself', () async {
    final invoked = <String>[];
    messenger.setMockMethodCallHandler(_pluginChannel, (call) async {
      invoked.add(call.method);
      if (call.method == 'create') {
        return <String, dynamic>{'id': 'disposed-engine'};
      }
      return <String, dynamic>{};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_pluginChannel, null));

    final audio = RealtimeAudio(recorderEnabled: true);
    await audio.isInitialized;
    await audio.dispose();
    invoked.clear();

    await audio.start();

    expect(invoked, isEmpty);
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
      engineChannel = const MethodChannel(
        'dev.volskaya.RealtimeAudio/engines/test-engine',
      );
    });

    tearDown(() async {
      messenger.setMockMethodCallHandler(engineChannel!, null);
      messenger.setMockMethodCallHandler(_pluginChannel, null);
    });

    test(
      'getPlayerPlayedDuration invokes the engine channel and types the result',
      () async {
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
      },
    );

    test(
      'clearQueue returns the folded lifetime clock alongside the chunk',
      () async {
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
      },
    );

    test(
      'getEchoCancellationState invokes the engine channel and types the result',
      () async {
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
        expect(
          aec.mechanism,
          RealtimeAudioEchoCancellationMechanism.platformAec,
        );
        expect(aec.captureProvenLive, true);
        expect(aec.trustsFullDuplex, true);
      },
    );

    test(
      'audioEngineHealth native callback is exposed as a typed stream',
      () async {
        final eventFuture = audio.engineHealthStream.first;

        await messenger.handlePlatformMessage(
          engineChannel!.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('audioEngineHealth', <String, dynamic>{
              'type': 'configuration_change_recovered',
              'engineWasRunning': false,
              'queuedChunkCount': 2,
            }),
          ),
          (_) {},
        );

        final event = await eventFuture;
        expect(
          event.type,
          RealtimeAudioEngineHealthEventType.configurationChangeRecovered,
        );
        expect(event.queuedChunkCount, 2);
      },
    );

    test('repairPlaybackAccounting sends the expected extent CAS', () async {
      Object? sentArguments;
      messenger.setMockMethodCallHandler(engineChannel!, (call) async {
        if (call.method == 'repairPlaybackAccounting') {
          sentArguments = call.arguments;
          return <String, dynamic>{
            'repaired': true,
            'reason': 'repaired',
            'clock': <String, dynamic>{
              'renderClockMs': 4000,
              'renderedMs': 0,
              'scheduledMs': 4000,
              'isRendering': false,
            },
          };
        }
        return null;
      });

      final result = await audio.repairPlaybackAccounting(
        expectedScheduledMs: 4000,
      );

      expect(sentArguments, <String, dynamic>{'expectedScheduledMs': 4000});
      expect(result?.repaired, true);
      expect(result?.clock.isRendering, false);
    });

    test(
      'recoverWedgedPlayback exposes destructive recovery outcome',
      () async {
        messenger.setMockMethodCallHandler(engineChannel!, (call) async {
          if (call.method == 'recoverWedgedPlayback') {
            return <String, dynamic>{
              'recovered': true,
              'clock': <String, dynamic>{
                'renderClockMs': 1200,
                'renderedMs': 1000,
                'scheduledMs': 4000,
                'isRendering': false,
              },
            };
          }
          return null;
        });

        final result = await audio.recoverWedgedPlayback();

        expect(result?.recovered, true);
        expect(result?.clock.renderClockMs, 1200);
      },
    );
  });
}
