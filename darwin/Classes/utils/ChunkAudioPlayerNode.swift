import AVFoundation

class ChunkAudioPlayerNode: AVAudioPlayerNode {
  private var inputFormat: AVAudioFormat
  private var outputFormat: AVAudioFormat

  var queue: [ChunkEntry] = []
  var totalSampleTime: UInt32 { (queue.last?.offset ?? 0) + (queue.last?.buffer.frameLength ?? 0) }

  private var isChunkQueueStartedNeeded = true
  private var converter: AVAudioConverter? = nil
  private weak var listener: ChunkAudioEventListener? = nil

  // MARK: - Render clock (call-lifetime; completion-independent + completion-driven)
  //
  // Three lifetime counters, monotonic for the node's lifetime. They are NOT
  // reset per stream — the live segment is FOLDED into a base before every stop
  // (AVAudioPlayerNode.playerTime resets to 0 on stop), so the values survive
  // stop/clearQueue/drain. A fresh node (engine teardown) is the only full
  // reset. The consumer subtracts a baseline captured at stream start.

  /// Folded base of the completion-INDEPENDENT render clock (ms). The live
  /// segment (`playerTime`) is added on top; before every stop the current
  /// segment is folded in so the value survives the head reset.
  private var renderClockBaseMs: Double = 0
  /// Completion-DRIVEN rendered ms — accumulated only from `.dataPlayedBack`
  /// completions of buffers that were NOT flushed (generation-guarded).
  private var completionRenderedMs: Double = 0
  /// Total ms ever scheduled onto the player (monotonic upper bound).
  private var scheduledMsAccum: Double = 0
  /// Bumped whenever queued buffers are dropped (stop/flush) so late completions
  /// of flushed buffers are ignored and never counted as rendered.
  private var generation: Int = 0
  /// Buffers scheduled but not yet completed (or dropped).
  private var outstandingBuffers: Int = 0
  /// Monotonic host time (s) when playback last reached zero outstanding
  /// buffers — drives the render hangover.
  private var lastPlaybackEndedAt: TimeInterval?

  /// Post-drain hangover: keep reporting "rendering" briefly after the last
  /// buffer drains, covering speaker ring-out / output pipeline latency.
  private static let renderHangover: TimeInterval = 0.2

  /// Live segment position in ms since the current `play()` (0 when stopped /
  /// head reset). Completion-independent — read straight off the render timeline.
  private func currentSegmentMs() -> Double {
    guard let lastTime = lastRenderTime, let time = playerTime(forNodeTime: lastTime), time.sampleTime > 0 else {
      return 0
    }
    return Double(time.sampleTime) / time.sampleRate * 1000.0
  }

  /// Fold the current segment into the base BEFORE a stop resets the head.
  private func foldRenderClock() {
    renderClockBaseMs += currentSegmentMs()
  }

  /// Completion-INDEPENDENT lifetime render clock (ms). Survives dead per-buffer
  /// completions (derived from the render timeline) and player stops (folded).
  var lifetimeRenderClockMs: Int { Int((renderClockBaseMs + currentSegmentMs()).rounded()) }
  /// Completion-DRIVEN lifetime rendered ms (`.dataPlayedBack`, flush-excluded).
  var lifetimeRenderedMs: Int { Int(completionRenderedMs.rounded()) }
  /// Lifetime ms scheduled onto the player (monotonic upper bound).
  var lifetimeScheduledMs: Int { Int(scheduledMsAccum.rounded()) }

  /// Whether the device is actively rendering: buffers outstanding, or within
  /// the post-drain hangover window. Pause gating is applied by the engine
  /// (which owns the paused state).
  var isRenderingPlaybackRaw: Bool {
    if outstandingBuffers > 0 { return true }
    if let ended = lastPlaybackEndedAt { return (ProcessInfo.processInfo.systemUptime - ended) < Self.renderHangover }
    return false
  }

  init(
    inputFormat: AVAudioFormat,
    outputFormat: AVAudioFormat
  ) {
    self.inputFormat = inputFormat
    self.outputFormat = outputFormat
  }

  private func getPlayerConverter(_ from: AVAudioFormat, _ to: AVAudioFormat) throws -> AVAudioConverter {
    if let converter { return converter }
    guard let newConverter = AVAudioConverter(from: from, to: to) else {
      throw TextError("Failed to create an AVAudioConverter.")
    }
    converter = newConverter
    return newConverter
  }

  func queue(_ id: String, _ data: [UInt8]) throws {
    if data.isEmpty { return }

    let converter = try getPlayerConverter(inputFormat, outputFormat)
    let buffer = try converter.convert(data)
    let entry = ChunkEntry(
      id: id,
      buffer: buffer,
      offset: totalSampleTime
    )

    // Scheduled-ms upper bound + outstanding accounting, tagged with the current
    // generation so a later flush can disown this buffer's completion.
    let bufferMs = Double(entry.buffer.frameLength) / outputFormat.sampleRate * 1000.0
    let scheduledGeneration = generation
    scheduledMsAccum += bufferMs
    outstandingBuffers += 1

    queue.append(entry)
    listener?.onChunkQueued(id)
    // `.dataPlayedBack` fires when the buffer has actually been played out (not
    // merely consumed), so completionRenderedMs tracks true playout.
    scheduleBuffer(entry.buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }

        // Count toward completion-driven rendered ms only if this buffer wasn't
        // flushed (its generation still current).
        if scheduledGeneration == self.generation {
          self.completionRenderedMs += bufferMs
          self.outstandingBuffers = max(0, self.outstandingBuffers - 1)
          if self.outstandingBuffers == 0 { self.lastPlaybackEndedAt = ProcessInfo.processInfo.systemUptime }
        }

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

    super.play()
  }

  override func stop() {
    // Fold the live segment into the base BEFORE super.stop() resets the head,
    // so the lifetime render clock stays monotonic across the stop.
    foldRenderClock()
    // Disown any queued/flushed buffers so their completions never count as
    // rendered (flushed frames must NEVER be reported as played).
    generation += 1
    if outstandingBuffers > 0 { lastPlaybackEndedAt = ProcessInfo.processInfo.systemUptime }
    outstandingBuffers = 0

    isChunkQueueStartedNeeded = true
    super.stop()

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

extension AVAudioConverter {
  fileprivate func convert(_ data: [UInt8]) throws -> AVAudioPCMBuffer {
    let frameLength = UInt32(data.count) / inputFormat.streamDescription.pointee.mBytesPerFrame
    let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameLength)!
    buffer.frameLength = frameLength

    let dstLeft = buffer.int16ChannelData![0]
    data.withUnsafeBufferPointer {
      let src = UnsafeRawPointer($0.baseAddress!).bindMemory(to: Int16.self, capacity: Int(frameLength))
      dstLeft.initialize(from: src, count: Int(frameLength))
    }

    let ratio: Float = Float(inputFormat.sampleRate) / Float(outputFormat.sampleRate)
    let frameCapacity: Float = Float(buffer.frameCapacity) / ratio
    let bufferConverted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: UInt32(frameCapacity))!

    var error: NSError? = nil
    convert(to: bufferConverted, error: &error) { inNumPackets, outStatus in
      outStatus.pointee = .haveData
      return buffer
    }
    reset()

    if let error {
      throw TextError(error.localizedDescription)
    }

    return bufferConverted
  }
}
