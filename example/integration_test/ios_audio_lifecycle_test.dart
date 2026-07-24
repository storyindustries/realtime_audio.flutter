// iOS capture-lifecycle acceptance gate.
//
// RUN:
//   cd example
//   flutter test integration_test/ios_audio_lifecycle_test.dart -d <ios-device>
//
// A physical device is authoritative. The simulator is only a compile and
// lifecycle smoke test; it cannot validate AVAudioSession priority or capture.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:realtime_audio/realtime_audio.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '20 create-start-capture-dispose cycles stay live and responsive',
    (final WidgetTester tester) async {
      expect(
        Platform.isIOS,
        isTrue,
        reason: 'this gate exercises AVAudioSession and AVAudioEngine',
      );
      final RealtimeAudioRecordPermission permission =
          await RealtimeAudio.requestRecordPermission();
      expect(permission, RealtimeAudioRecordPermission.granted);

      const MethodChannel heartbeatChannel = MethodChannel(
        'dev.volskaya.RealtimeAudio/main-thread-heartbeat',
      );
      var keepMonitoring = true;
      Duration maximumHeartbeatRoundTrip = Duration.zero;
      final Future<void> heartbeatMonitor = () async {
        while (keepMonitoring) {
          final Stopwatch stopwatch = Stopwatch()..start();
          await heartbeatChannel
              .invokeMethod<void>('ping')
              .timeout(const Duration(seconds: 1));
          stopwatch.stop();
          if (stopwatch.elapsed > maximumHeartbeatRoundTrip) {
            maximumHeartbeatRoundTrip = stopwatch.elapsed;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }();

      try {
        for (int cycle = 0; cycle < 20; cycle++) {
          final RealtimeAudio audio = RealtimeAudio(
            recorderEnabled: true,
            voiceProcessing: true,
            recorderSampleRate: 24000,
            playerSampleRate: 24000,
            recorderChunkInterval: 40,
          );
          final Completer<Uint8List> firstCapture = Completer<Uint8List>();
          StreamSubscription<Uint8List>? captureSubscription;
          try {
            await audio.isInitialized.timeout(const Duration(seconds: 3));
            captureSubscription = audio.recorderStream.listen((
              final Uint8List chunk,
            ) {
              if (chunk.isNotEmpty && !firstCapture.isCompleted) {
                firstCapture.complete(chunk);
              }
            });
            await audio.start().timeout(const Duration(seconds: 3));
            final Uint8List chunk = await firstCapture.future.timeout(
              const Duration(seconds: 2),
            );
            expect(
              chunk,
              isNotEmpty,
              reason: 'capture starved on lifecycle cycle $cycle',
            );
            final RealtimeAudioEchoCancellationState? aec =
                await audio.getEchoCancellationState();
            expect(
              aec?.mechanism,
              RealtimeAudioEchoCancellationMechanism.platformAec,
              reason: 'VoiceProcessingIO was not active on lifecycle cycle $cycle',
            );
            expect(
              aec?.captureProvenLive,
              isTrue,
              reason: 'native capture liveness was not committed on cycle $cycle',
            );
          } finally {
            await captureSubscription?.cancel();
            await audio.dispose().timeout(const Duration(seconds: 3));
          }
        }
      } finally {
        keepMonitoring = false;
        await heartbeatMonitor;
      }

      expect(
        maximumHeartbeatRoundTrip,
        lessThan(const Duration(milliseconds: 250)),
        reason: 'native audio ownership blocked the iOS main runloop',
      );
    },
  );
}
