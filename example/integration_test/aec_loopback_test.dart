// On-device AEC loopback acceptance gate (2026-07-24 Android echo RCA).
//
// Plays a synthesized voice-band reference through the engine's speaker while
// recording the microphone — real acoustic coupling, real echo path. The gate
// asserts the echo architecture PROVES itself:
//
//   1. the engine reports a verifiable mechanism (hardware `platform_aec`, or
//      software `webrtc_apm` — never `none`), and
//   2. the speaker signal does not survive into the capture stream: the
//      normalized cross-correlation between the reference and the recorded
//      mic audio stays below [maxTolerableEchoCorrelation] at every probed
//      delay, and
//   3. on the software path, the APM's own measured ERLE reaches the Dart
//      trust threshold once converged.
//
// This is the test that would have caught the dead March→July AEC (a
// queue-time far-end feed + AECM + media-path playback cancel nothing, and
// the correlation assertion fails loudly on that stack).
//
// RUN (physical device, speaker up, quiet-ish room — an emulator's virtual
// mic does not exercise the acoustic path):
//
//   cd example && flutter test integration_test/aec_loopback_test.dart -d <device>
//
// Not part of any JVM/CI suite by construction — it needs hardware.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:realtime_audio/realtime_audio.dart';

const int playerSampleRate = 24000;
const int recorderSampleRate = 48000;

/// Max acceptable normalized cross-correlation between the played reference
/// and the captured mic signal. Uncancelled speaker echo at conversational
/// volume correlates far above this; ambient noise stays well below.
const double maxTolerableEchoCorrelation = 0.25;

/// Synthesized 4s voice-band reference: three AM-modulated tones across the
/// speech band with a shared syllabic (4 Hz) envelope — speech-like enough to
/// exercise the canceller, deterministic enough to correlate against.
Uint8List synthesizeReferencePcm16({required int sampleRate, required int seconds}) {
  final int totalSamples = sampleRate * seconds;
  final Int16List samples = Int16List(totalSamples);
  for (int i = 0; i < totalSamples; i++) {
    final double t = i / sampleRate;
    final double syllabic = 0.55 + 0.45 * math.sin(2 * math.pi * 4 * t);
    final double carrier = math.sin(2 * math.pi * 440 * t) +
        0.6 * math.sin(2 * math.pi * 1130 * t) +
        0.4 * math.sin(2 * math.pi * 2470 * t);
    samples[i] = (carrier / 2.0 * syllabic * 0.6 * 32767).round().clamp(-32768, 32767);
  }
  return samples.buffer.asUint8List();
}

List<double> pcm16ToDoubles(Uint8List bytes) {
  final Int16List s = bytes.buffer.asInt16List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 2);
  return List<double>.generate(s.length, (i) => s[i] / 32768.0);
}

/// Downsample 48k capture to 24k by averaging sample pairs (enough fidelity
/// for a correlation probe; no fractional resampling needed at exactly 2x).
List<double> downsample2x(List<double> input) =>
    List<double>.generate(input.length ~/ 2, (i) => (input[2 * i] + input[2 * i + 1]) / 2.0);

/// Root-mean-square of [samples] — the capture-liveness floor (a muted/denied
/// mic delivering all-zero frames must FAIL the gate, not trivially pass it).
double rms(List<double> samples) {
  if (samples.isEmpty) return 0;
  double sum = 0;
  for (final double s in samples) {
    sum += s * s;
  }
  return math.sqrt(sum / samples.length);
}

/// Max normalized cross-correlation of [reference] against [capture] over
/// candidate delays [0, maxLagMs], both at [sampleRate]. Window-normalized so
/// the score is amplitude-invariant (acoustic coupling loss doesn't hide
/// echo). The lag range must span playback-START offset + acoustic delay —
/// capture begins at `start()` while the reference is queued afterwards, so
/// the echo can land well over a second into the capture (rev-contract D2);
/// callers scan the whole capture.
double maxNormalizedCorrelation({
  required List<double> reference,
  required List<double> capture,
  required int sampleRate,
  required int maxLagMs,
  int lagStepMs = 10,
}) {
  final int window = math.min(reference.length, sampleRate * 2);
  double refEnergy = 0;
  for (int i = 0; i < window; i++) {
    refEnergy += reference[i] * reference[i];
  }
  if (refEnergy == 0) return 0;

  double best = 0;
  for (int lagMs = 0; lagMs <= maxLagMs; lagMs += lagStepMs) {
    final int lag = sampleRate * lagMs ~/ 1000;
    if (lag + window > capture.length) break;
    double dot = 0;
    double capEnergy = 0;
    for (int i = 0; i < window; i++) {
      final double c = capture[lag + i];
      dot += reference[i] * c;
      capEnergy += c * c;
    }
    if (capEnergy == 0) continue;
    final double corr = dot.abs() / math.sqrt(refEnergy * capEnergy);
    best = math.max(best, corr);
  }
  return best;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('speaker playback must not survive into the mic capture', (tester) async {
    final RealtimeAudio audio = RealtimeAudio(
      recorderEnabled: true,
      voiceProcessing: true,
      recorderSampleRate: recorderSampleRate,
      playerSampleRate: playerSampleRate,
      recorderChunkInterval: 40,
    );
    addTearDown(audio.dispose);
    await audio.isInitialized;

    final List<Uint8List> captured = <Uint8List>[];
    final StreamSubscription<Uint8List> sub = audio.recorderStream.listen(captured.add);
    addTearDown(sub.cancel);

    final RealtimeAudioEchoCancellationState? preState = await audio.getEchoCancellationState();
    // ignore: avoid_print
    print('AEC state at start: $preState');
    expect(
      preState?.mechanism,
      isNot(RealtimeAudioEchoCancellationMechanism.none),
      reason: 'no verifiable echo mechanism — the device would run half-duplex '
          'and this gate has nothing to prove (investigate before waiving)',
    );

    await audio.start();

    final Uint8List reference = synthesizeReferencePcm16(sampleRate: playerSampleRate, seconds: 4);
    // Queue in ~200ms chunks like the real cascade does.
    const int chunkBytes = playerSampleRate * 2 ~/ 5;
    for (int off = 0; off < reference.length; off += chunkBytes) {
      await audio.queueChunk(
        reference.sublist(off, math.min(off + chunkBytes, reference.length)),
        id: 'ref-${off ~/ chunkBytes}',
      );
    }

    // Let playback + capture run to completion (4s signal + margin).
    await Future<void>.delayed(const Duration(seconds: 6));

    final RealtimeAudioEchoCancellationState? postState = await audio.getEchoCancellationState();
    // ignore: avoid_print
    print('AEC state after playback: $postState');

    final List<double> capture48 = pcm16ToDoubles(
      Uint8List.fromList(captured.expand<int>((c) => c).toList()),
    );
    expect(capture48.length, greaterThan(recorderSampleRate * 3), reason: 'capture starved');

    // Liveness floor (rev-contract D1): an all-zero/near-silent capture means
    // the mic never heard the speaker — the gate would otherwise false-pass
    // with zero proof, the exact trap it exists to catch. −60 dBFS floor.
    expect(
      postState?.captureProvenLive,
      isTrue,
      reason: 'capture path never proved live — nothing was measured',
    );
    final double captureRms = rms(capture48);
    // ignore: avoid_print
    print('capture RMS: ${captureRms.toStringAsFixed(5)}');
    expect(
      captureRms,
      greaterThan(0.001),
      reason: 'capture is silent (muted/denied mic?) — the gate measured nothing',
    );

    final List<double> capture24 = downsample2x(capture48);
    final int windowSamples = math.min(playerSampleRate * 2, pcm16ToDoubles(reference).length);
    final double correlation = maxNormalizedCorrelation(
      reference: pcm16ToDoubles(reference),
      capture: capture24,
      sampleRate: playerSampleRate,
      // Scan the WHOLE capture: playback starts an unbounded settle after
      // capture[0] (queue loop, buffer prime, route settle).
      maxLagMs: math.max(0, ((capture24.length - windowSamples) * 1000) ~/ playerSampleRate),
    );
    // ignore: avoid_print
    print('speaker→mic correlation: ${correlation.toStringAsFixed(3)}');

    expect(
      correlation,
      lessThan(maxTolerableEchoCorrelation),
      reason: 'assistant playback leaks into the mic — the echo path is NOT cancelling '
          '(mechanism=${postState?.mechanism}, erleDb=${postState?.erleDb})',
    );

    if (postState?.mechanism == RealtimeAudioEchoCancellationMechanism.webrtcApm) {
      // AEC3 reports ERLE from its first processed block (~0 dB while
      // unconverged), so non-null proves only instantiation — the gate must
      // demand the same convergence evidence production trust does.
      expect(
        postState?.erleDb,
        isNotNull,
        reason: 'AEC3 reported no ERLE after 4s of double-talk-free far-end audio',
      );
      expect(
        postState!.erleDb,
        greaterThanOrEqualTo(RealtimeAudioEchoCancellationState.erleTrustThresholdDb),
        reason: 'AEC3 never converged — production would (correctly) hold half-duplex',
      );
    }
  });
}
