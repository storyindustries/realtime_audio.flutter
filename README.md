# 🎵 Realtime Audio

`RealtimeAudio` is a Flutter package that handles audio recording and playback of data chunks from real-time sources, like OpenAI Realtime, ElevenLabs or HumeAI Voice.

## ✨ Features

- 🎤 Audio recording with variable chunk length in milliseconds.
- 🔊 Audio playback of data chunks.
- ⏱️ Duration tracking of audio chunks.
- ⏸️ Pause support.
- 📊 Volume tracking in dBFS.
- 🎛️ Voice isolation and other processing on iOS.
- 📱 iOS audio session handling for max volume.
- 🤖🍏🍎 Android, iOS, and macOS support.
- ✂️ Audio response truncation support.
- 🎵 Background audio track support.

## 📖 Usage

To use this package, add `realtime_audio` as a [dependency in your pubspec.yaml file](https://flutter.dev/docs/development/packages-and-plugins/using-packages).

After initializing the `RealtimeAudio` object, you can start recording and playing audio chunks by calling `start()`.

Audio will be played back in real-time, as soon as the first chunk is queued with `queueChunk()`.

See the example project for a complete example.

## 🔒 Permissions

### 🤖 Android

- **Add Permissions to `AndroidManifest.xml`**:

  ```xml
  <uses-permission android:name="android.permission.RECORD_AUDIO"/>
  ```

### 🍏 iOS

- **Add Permissions to `Info.plist`**:
  Open your `Info.plist` file and add the following keys:

  ```xml
  <key>NSMicrophoneUsageDescription</key>
  <string>We need access to the microphone to record audio.</string>
  ```

### 🍎 macOS

- **Add Permissions to `Info.plist`**:
  Open your `Info.plist` file and add the following keys:

  ```xml
  <key>NSMicrophoneUsageDescription</key>
  <string>We need access to the microphone to record audio.</string>
  ```

- **Add Entitlements to release and debug `macos/*.entitlements`**:
  Open your `macos/*.entitlements` file and add the following:

  ```xml
  <key>com.apple.security.device.audio-input</key>
  <true/>
  ```

  Can also do this through XCode by selecting the target, then `Signing & Capabilities`, then checking `Audio Input`.

## ⏱️ Render clock (device-truth `playedMs`)

When you drive server-paced TTS PCM through the player, you often need to know
**how much of the current stream the device actually rendered** — for example to
gate barge-in / talk-over on the server. Completion callbacks alone are not
trustworthy (they can stall or die), so the plugin exposes **three call-lifetime
playback counters**:

```dart
final clock = await audio.getPlayerPlayedDuration();
// clock.renderClockMs  — completion-INDEPENDENT device playback-head timeline
// clock.renderedMs     — completion-DRIVEN played-out ms (iOS .dataPlayedBack)
// clock.scheduledMs    — total ms scheduled onto the player (upper bound)
// clock.isRendering    — is the device actively rendering right now
```

`renderClockMs` is the device-truth "how much actually played out" signal — it is
derived from the platform playback head (iOS `AVAudioPlayerNode.playerTime`,
Android `AudioTrack.playbackHeadPosition`), so it keeps advancing even when
per-buffer completion callbacks stall or die.

`renderClockMs` and `isRendering` are also mirrored on `stateStream` as
`RealtimeAudioState.renderClockMs` / `RealtimeAudioState.isRendering`, and the
folded lifetime clock is returned from `clearQueue()` on
`RealtimeAudioInstanceResponseClearQueue.clock` (the barge cut position).

### Lifetime & reset semantics

All three counters are **call-lifetime monotonic** — they are NOT reset per
stream. The platform playback head resets to `0` on every player stop, so the
current segment is **folded** into a base *before* each stop; the counters
therefore survive `stop` / `clearQueue` / natural drain. A fresh engine
(`dispose` + recreate) is the only full reset.

| Transition | `renderClockMs` (lifetime) | `duration` (live per-segment head) |
|---|---|---|
| `queueChunk` → first render | advances | advances from `0` |
| `pause` / `resume` | holds, then continues | holds, then continues |
| `clearQueue` (flush) | **folds** segment in, then holds | resets to `0` |
| natural drain (queue empties) | **folds** segment in, then holds | resets to `0` |
| `stop` | **folds** segment in, then holds | resets to `0` |
| next stream's first render | continues from the folded base | resets to `0` |
| `dispose` (fresh engine) | resets to `0` | resets to `0` |

The consumer captures a **baseline at stream start** (`audio_start`) and
subtracts it, e.g. on natural drain `playedMs = renderClockMs − baseline`; on
barge/supersede/teardown `playedMs = clamp(max(renderedΔ, renderClockΔ),
scheduledΔ)`. Flushed buffers never count toward `renderedMs` (a generation guard
disowns their late completions).

`isRendering` is `true` while buffers are outstanding or within a 0.2 s
post-drain hangover (speaker ring-out), and `false` while paused.

### Rendered-out accounting vs. a true wedge

If `.dataPlayedBack` callbacks die, compare per-stream deltas from the three
counters. When the independent render clock reached the scheduled extent, clear
only the stranded completion accounting:

```dart
final result = await audio.repairPlaybackAccounting(
  expectedScheduledMs: clock.scheduledMs,
);
// A new chunk changes scheduledMs, so a stale repair is rejected atomically.
```

This repair bumps the completion generation and retires the rendered chunks
without stopping the player; late callbacks from the repaired generation are
ignored. If both the render clock and completion counter are frozen instead,
the player is genuinely wedged and can be destructively recovered:

```dart
final result = await audio.recoverWedgedPlayback();
```

That API intentionally discards the player queue. It restarts the audio engine
only when the engine is actually stopped; a healthy graph is left running.

**Platform notes.** iOS counts real playout via `.dataPlayedBack` completions, so
`renderedMs` is independent of `renderClockMs` (enabling wedge-vs-rendered-out
discrimination). Android has no per-buffer playout callback, so `renderedMs`
mirrors the head-based `renderClockMs`; `isRendering` compares the current
playback-head segment with its own scheduled extent so an older flushed stream
cannot leave permanent lifetime-scheduled debt. Android chunk completion and
natural drain are emitted only when the hardware playback head reaches exact
chunk-end markers—`AudioTrack.write()` acceptance is never treated as playout.

## 🎧 Full-duplex trust (AEC read-back)

Echo cancellation is **never assumed to be active** just because it was
requested. Read the real state back before trusting full-duplex (talk-over):

```dart
final aec = await audio.getEchoCancellationState();
// aec.requested         — voiceProcessing was requested for this engine
// aec.nativeEnabled      — the platform confirmed AEC is enabled (read-back)
// aec.mechanism          — webrtcApm | platformAec | none
// aec.captureProvenLive  — the mic path has delivered its first real buffer
// aec.trustsFullDuplex   — requested && nativeEnabled && captureProvenLive
```

- **iOS**: input-node VoiceProcessingIO supplies AEC and its enabled state is
  read back from `AVAudioInputNode.isVoiceProcessingEnabled`. The output node
  is never toggled, and the separate iOS 18.2 session echo-input preference is
  not requested because it is invalid with `.voiceChat`. The bundled WebRTC
  APM does NS+AGC only here.
- **macOS**: no platform AEC path is currently claimed; consumers receive the
  conservative no-AEC read-back.
- **Android**: AEC is the bundled WebRTC APM (`webrtcApm`) when available;
  otherwise the engine relies on the platform `VOICE_COMMUNICATION` capture
  source (`platformAec`), whose liveness cannot be read back (`nativeEnabled` is
  then `false`).

## 🩺 Audio-engine health

On iOS, `audio_session_insufficient_priority` is a stable, recoverable platform
error: another call or app currently owns a higher-priority audio session.
Retry after the interruption ends; do not present it as a network failure.

The repeated iOS lifecycle gate exercises 20 create → start → first live mic
frame → dispose cycles and bounds main-runloop stalls:

```sh
cd example
flutter test integration_test/ios_audio_lifecycle_test.dart -d <ios-device>
```

A physical iOS device is authoritative for AVAudioSession priority, routes, and
live microphone frames. A simulator run is only a compile, lifecycle, and
main-runloop smoke test.

iOS and macOS can stop an audio engine after a real route or format change. The
plugin restarts that stopped engine without stopping the player, preserving any
scheduled speech. Benign configuration notifications received while the engine
is still running do not trigger recovery.

Subscribe to structured outcomes when the host application needs telemetry or
user-visible recovery handling:

```dart
audio.engineHealthStream.listen((event) {
  // event.type — ignored healthy notification, recovery start/success/failure
  // event.engineWasRunning — native state when the notification was handled
  // event.queuedChunkCount — scheduled chunks owned by the player
  // event.message — native failure detail, when recovery failed
});
```
