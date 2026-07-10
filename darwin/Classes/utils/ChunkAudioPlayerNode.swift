import AVFoundation

class ChunkAudioPlayerNode: AVAudioPlayerNode {
  private var inputFormat: AVAudioFormat
  private var outputFormat: AVAudioFormat

  var queue: [ChunkEntry] = []
  var totalSampleTime: UInt32 { (queue.last?.offset ?? 0) + (queue.last?.buffer.frameLength ?? 0) }

  private var isChunkQueueStartedNeeded = true
  private let converter: PCMStreamConverter
  private weak var listener: ChunkAudioEventListener? = nil

  /// True between `play()` and `stop()` — i.e. the node is rendering or paused
  /// (holding position), false once stopped/flushed. Gates whether the render
  /// clock reads the live playback head or the latched value.
  private(set) var isPlaybackActive = false

  /// Last device-truth rendered milliseconds, latched so it survives the
  /// playback-head reset that `stop()` performs.
  private var latchedPlayedMs = 0

  /// Live playback-head position in ms, or nil if the node isn't currently
  /// mapping node time (e.g. stopped). Derived from `playerTime` — the platform
  /// render clock — so it is independent of per-buffer completion callbacks.
  private func liveHeadMs() -> Int? {
    guard let lastTime = lastRenderTime, let time = playerTime(forNodeTime: lastTime) else { return nil }
    return RenderClock.framesToMs(sampleTime: time.sampleTime, sampleRate: time.sampleRate)
  }

  /// Device-truth milliseconds rendered for the current/last stream. Advances
  /// while rendering, holds while paused, and latches across stop/flush so a
  /// post-drain read still reports what the device actually played.
  var playedMs: Int {
    if isPlaybackActive, let ms = liveHeadMs() {
      latchedPlayedMs = ms
      return ms
    }
    return latchedPlayedMs
  }

  /// Whether the device is actively rendering queued PCM ahead of the head
  /// (false when paused, stalled, drained, or stopped).
  var isRenderingPlayback: Bool {
    guard isPlaybackActive, let lastTime = lastRenderTime, let time = playerTime(forNodeTime: lastTime) else {
      return false
    }
    return time.sampleTime < Int64(totalSampleTime)
  }

  init(
    inputFormat: AVAudioFormat,
    outputFormat: AVAudioFormat
  ) throws {
    self.inputFormat = inputFormat
    self.outputFormat = outputFormat
    self.converter = try PCMStreamConverter(inputFormat: inputFormat, outputFormat: outputFormat)
  }

  func queue(_ id: String, _ data: [UInt8]) throws {
    if data.isEmpty { return }

    let buffer = try converter.convert(data)
    let entry = ChunkEntry(
      id: id,
      buffer: buffer,
      offset: totalSampleTime
    )

    queue.append(entry)
    listener?.onChunkQueued(id)
    scheduleBuffer(entry.buffer) { [weak self] in
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }

        let chunkQueueCountBefore = self.queue.count
        self.queue.removeAll { $0.id == entry.id }
        let didRemove = self.queue.count < chunkQueueCountBefore

        if didRemove {
          self.handleChunkPlayed(id)
          if queue.count == 0 { self.handleQueueEnded() }
        }
      }
    }
  }

  override func play() {
    if isChunkQueueStartedNeeded, let firstChunkId = queue.first?.id {
      isChunkQueueStartedNeeded = false
      listener?.onChunkQueueStarted(firstChunkId)
    }

    isPlaybackActive = true
    super.play()
  }

  override func stop() {
    // Latch the device-truth rendered position BEFORE super.stop() resets the
    // node's playback head, so a post-stop / post-drain read still reports it.
    if isPlaybackActive, let ms = liveHeadMs() { latchedPlayedMs = ms }
    isPlaybackActive = false

    isChunkQueueStartedNeeded = true
    super.stop()
    converter.resetForDiscontinuity()

    // AVAudioPlayerNode.scheduleBuffer calls its played callback anyway, when
    // the audio has been stopped and the scheduled buffers are cleared. This
    // is just a redundancy, just in case something changes.
    //
    // Flutter code will check if the chunk is still queued, before handling
    // its removal.
    while !queue.isEmpty {
      let chunk = queue.removeFirst()
      listener?.onChunkPlayed(chunk.id)
    }
  }

  private func handleChunkPlayed(_ id: String) {
    listener?.onChunkPlayed(id)
  }

  private func handleQueueEnded() {
    listener?.onChunkQueueEnded()
  }

  func setListener(_ value: ChunkAudioEventListener) {
    listener = value
  }

  func removeListener(_ value: ChunkAudioEventListener) {
    if listener === value { listener = nil }
  }

  func getCurrentChunkProps() -> [String: Any]? {
    guard
      let lastTime = lastRenderTime,
      let time = playerTime(forNodeTime: lastTime),
      let chunk = queue.first
    else {
      return nil
    }

    let sampleTime = Int(time.sampleTime)
    let offset = Int(chunk.offset)
    let chunkSampleTime = sampleTime - offset

    return [
      "id": chunk.id,
      "sampleRate": time.sampleRate,
      "sampleTime": sampleTime,
      "sampleTimeTotal": totalSampleTime,
      "chunkSampleTime": chunkSampleTime,
      "chunkSampleTimeTotal": chunk.buffer.frameLength,
    ]
  }
}
