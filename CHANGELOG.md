## 0.0.13

* Add a completion-independent player **render clock**: `getPlayerPlayedDuration()`
  returns device-truth `renderedMs` / `isRendering` / `durationTotalMs`, derived
  from the platform playback head (iOS `AVAudioPlayerNode.playerTime`, Android
  `AudioTrack.playbackHeadPosition`) rather than per-buffer completion callbacks.
  `renderedMs` latches across stop/clearQueue/drain so device-truth `playedMs`
  stays readable after a stream ends. Also mirrored on the state stream as
  `RealtimeAudioState.renderedMs` / `isRendering`.
* Add **AEC live read-back**: `getEchoCancellationState()` returns
  `{ requested, nativeEnabled, mechanism, captureProvenLive, trustsFullDuplex }`
  so consumers can decide whether full-duplex can be trusted (never assumed).
* Wire a JUnit 5 engine so the Android unit tests run under `useJUnitPlatform()`.

## 0.0.12

* Update build dependencies

## 0.0.11

* Update dependencies

## 0.0.1

* Initial release
