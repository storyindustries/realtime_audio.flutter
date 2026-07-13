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
