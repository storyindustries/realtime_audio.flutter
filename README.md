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
trustworthy (they can stall or die), so the plugin exposes a
**completion-independent render clock** derived from the platform playback head
(iOS `AVAudioPlayerNode.playerTime`, Android `AudioTrack.playbackHeadPosition`).

```dart
final clock = await audio.getPlayerPlayedDuration();
// clock.renderedMs      — device-truth ms rendered for the current/last stream
// clock.isRendering     — is the device actively rendering queued PCM right now
// clock.durationTotalMs — total queued ms (rendered + pending)
```

The same values are mirrored on `stateStream` as
`RealtimeAudioState.renderedMs` / `RealtimeAudioState.isRendering`, so the
terminal `isPlaying: false` state already carries the device-truth `renderedMs`
(handy for reporting `playedMs` on every playback stop, including natural drain).

`renderedMs` is distinct from the existing `duration` field: `duration` is the
**live** playback head (resets to `0` at stop), whereas `renderedMs` **latches**
its final value across a reset so it stays readable after the stream ends.

### Reset semantics

| Transition | `renderedMs` | `duration` (live head) |
|---|---|---|
| `queueChunk` → first render | starts at `0`, advances monotonically | advances |
| `pause` / `resume` | **holds**, then continues | holds, then continues |
| `clearQueue` (flush) | **latches** the pre-flush value | resets to `0` |
| natural drain (queue empties) | **latches** the pre-drain value | resets to `0` |
| `stop` | **latches** the pre-stop value | resets to `0` |
| next stream's first render | resets to `0` | resets to `0` |
| `dispose` | gone (engine destroyed) | gone |

The consumer computes a per-stream `playedMs` by subtracting a baseline captured
at stream start (which is `0` after a reset). `renderedMs` is monotonic between
resets, so `playedMs = renderedMs - baseline`.

## 🎧 Full-duplex trust (AEC read-back)

Echo cancellation is **never assumed to be active** just because it was
requested. Read the real state back before trusting full-duplex (talk-over):

```dart
final aec = await audio.getEchoCancellationState();
// aec.requested         — voiceProcessing was requested for this engine
// aec.nativeEnabled      — the platform confirmed AEC is enabled (read-back)
// aec.mechanism          — appleVoiceProcessingIO | webRtcApm | platformVoiceCommunication | none
// aec.captureProvenLive  — the mic path has delivered its first real buffer
// aec.trustsFullDuplex   — requested && nativeEnabled && captureProvenLive
```

- **iOS / macOS**: AEC is Apple's `AVAudioEngine` VoiceProcessingIO; `nativeEnabled`
  reads back `AVAudioInputNode.isVoiceProcessingEnabled` after enabling it.
- **Android**: AEC is the bundled WebRTC APM when available; otherwise the engine
  relies on the platform `VOICE_COMMUNICATION` capture source, whose liveness
  cannot be read back (`nativeEnabled` is then `false`).
