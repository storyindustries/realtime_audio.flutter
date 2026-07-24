## 0.0.17

* Fix intermittent iOS call startup by removing the incompatible combination
  of `.voiceChat` and the iOS 18.2 session echo-input preference. Voice calls
  now use VoiceProcessingIO exactly once on the input node; the output node is
  never toggled.
* Run every engine instance and dictionary mutation on one serial background
  executor so AVAudioSession setup cannot block Flutter's platform thread and
  teardown cannot race configuration recovery.
* Make recorder toggles transactional and restore the previous native graph
  when reconfiguration fails.
* Report AVAudioSession `!pri` (`561017449`) as the stable, recoverable
  `audio_session_insufficient_priority` platform error, and actually make it
  retryable: a failed `create` is no longer cached, so the next call reaches
  the platform again instead of replaying the stale failure forever.
* Never create a native engine as a side effect of `dispose()`. Disposal now
  awaits an in-flight create but never starts one, so tearing down an unused
  instance cannot acquire the audio session.
* Only touch `AVAudioEngine.inputNode` while the session is record-capable.
  A playback-only engine no longer materialises the shared I/O unit, and the
  VoiceProcessingIO *disable* now runs before the session drops to `.playback`
  rather than after.
* Tag capture liveness with a generation so a tap callback left over from a
  torn-down capture path cannot mark the replacement path as proven live.

## 0.0.16

* Android root-cause echo overhaul (2026-07-24 RCA — the cascade heard
  itself): replace the media-playback + software-AECM architecture with the
  platform voice-call path. When the device offers a hardware
  AcousticEchoCanceler, the engine now runs `MODE_IN_COMMUNICATION`,
  `USAGE_VOICE_COMMUNICATION`/`CONTENT_TYPE_SPEECH` playback and
  `VOICE_COMMUNICATION` capture with the hardware AEC + NoiseSuppressor
  attached (the OEM speakerphone tuning — the iOS-VPIO analogue; software APM
  off). Without hardware AEC it falls back to WebRTC **AEC3**
  (`mobile_mode=false`, adaptive delay estimator) over the unprocessed
  `VOICE_RECOGNITION` source. Speaker is forced as the communication device
  only when no external device is attached; system routing wins otherwise.
* Serialize every APM native-pointer use and destruction behind one monitor:
  `release()` now waits out an in-flight `processCapture`/`processRender`
  (writer-thread render tap + IO-coroutine capture vs main-thread teardown was
  a native use-after-free window), and post-release calls no-op.
* Evidence-based full-duplex trust: the read-back now carries `erleDb` (the
  APM's measured echo-return-loss-enhancement) + `apmMode`, `platform_aec` is
  claimed only for a verifiably-attached hardware canceller, and Dart
  `trustsFullDuplex` on the software path requires `erleDb ≥ 6.0` — a running
  canceller is not a cancelling one.
* Add the on-device AEC loopback acceptance gate
  (`example/integration_test/aec_loopback_test.dart`): speaker plays a
  synthesized voice-band reference while the mic records; asserts the played
  signal does not survive into capture (normalized cross-correlation) and
  that the mechanism/ERLE read-back proves itself. This is the test the dead
  March→July AEC would have failed on day one.

## 0.0.15

* Fix Android echo cancellation: feed the WebRTC APM far-end (render) reference
  at `AudioTrack.write` time from the writer thread instead of at queue time.
  The queue-time feed ran the echo reference ahead of the speaker by whole
  queued chunks, so AEC3 could not converge and the assistant's own playback
  leaked back through the microphone (2026-07-23 echo-storm RCA).
* Add `ApmRenderFeeder`: re-frames arbitrary write sizes into whole 10ms APM
  frames with remainder carry, so the JNI bridge no longer drops tail bytes of
  every feed call.

## 0.0.14

* Preserve scheduled iOS/macOS playback across audio-engine configuration
  changes. Benign notifications no longer restart a running engine; a genuine
  system-driven stop rebuilds capture and restarts without stopping or resetting
  the player queue.
* Add `engineHealthStream` with typed configuration-change recovery outcomes.
* Add generation-safe `repairPlaybackAccounting(expectedScheduledMs:)` for a
  rendered-out stream whose completion callbacks died, without stopping the
  player, plus explicit destructive `recoverWedgedPlayback()` for true wedges.
* Fix Android `isRendering` after a flushed stream by comparing the current
  playback-head segment with its own scheduled extent instead of lifetime totals.
* Android chunk completion and natural drain now follow exact `AudioTrack`
  playback-head markers. `write()` buffer acceptance no longer stops and flushes
  PCM that the device has not rendered yet; partial writes survive pause/resume.

## 0.0.13

* Add a player **render clock** with three call-lifetime counters:
  `getPlayerPlayedDuration()` returns `{ renderClockMs, renderedMs, scheduledMs,
  isRendering }`. `renderClockMs` is completion-INDEPENDENT (the platform
  playback-head timeline — iOS `AVAudioPlayerNode.playerTime`, Android
  `AudioTrack.playbackHeadPosition`), so it stays truthful when per-buffer
  completions stall/die. All counters are call-lifetime monotonic: the live
  segment is **folded** into a base before every player stop, so they survive
  stop/clearQueue/drain (a fresh engine is the only reset). Mirrored on the state
  stream as `RealtimeAudioState.renderClockMs` / `isRendering`, and the folded
  clock is returned from `clearQueue()` on
  `RealtimeAudioInstanceResponseClearQueue.clock`.
* iOS now schedules playback buffers with `.dataPlayedBack` completion so
  `renderedMs` reflects true playout (flushed buffers are disowned via a
  generation guard and never counted). Android has no per-buffer playout
  callback, so `renderedMs` mirrors the head-based `renderClockMs`.
* `isRendering` includes a 0.2 s post-drain hangover (speaker ring-out) and is
  `false` while paused.
* Add **AEC live read-back**: `getEchoCancellationState()` returns
  `{ requested, nativeEnabled, mechanism (webrtcApm|platformAec|none),
  captureProvenLive, trustsFullDuplex }` so consumers can decide whether
  full-duplex can be trusted (never assumed).
* Export `RealtimeAudioInstanceResponse` / `RealtimeAudioInstanceResponseClearQueue`
  (+ `RealtimeAudioClearQueueChunkData`) from the package barrel so consumers can
  type `clearQueue()`'s response and read `.clock` without an implementation import.
* Wire a JUnit 5 engine so the Android unit tests run under `useJUnitPlatform()`.

## 0.0.12

* Update build dependencies

## 0.0.11

* Update dependencies

## 0.0.1

* Initial release
