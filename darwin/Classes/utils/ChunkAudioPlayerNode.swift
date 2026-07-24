import AVFoundation

class ChunkAudioPlayerNode: AVAudioPlayerNode {
  private var inputFormat: AVAudioFormat
  private var outputFormat: AVAudioFormat
  private let callbackQueue: DispatchQueue

  var queue: [ChunkEntry] = []
  var totalSampleTime: UInt32 { queueTimeline.totalFrames }

  private var isChunkQueueStartedNeeded = true
  private let converter: PCMStreamConverter
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
  private var accounting = PlaybackBufferAccounting()
  private var queueTimeline = PlaybackQueueTimeline()

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
  var lifetimeRenderedMs: Int { accounting.renderedMs }
  /// Lifetime ms scheduled onto the player (monotonic upper bound).
  var lifetimeScheduledMs: Int { accounting.scheduledMs }

  /// Whether the device is actively rendering: buffers outstanding, or within
  /// the post-drain hangover window. Pause gating is applied by the engine
  /// (which owns the paused state).
  var isRenderingPlaybackRaw: Bool {
    if accounting.outstandingBuffers > 0 { return true }
    if let ended = accounting.lastPlaybackEndedAt {
      return (ProcessInfo.processInfo.systemUptime - ended) < Self.renderHangover
    }
    return false
  }

  init(
    inputFormat: AVAudioFormat,
    outputFormat: AVAudioFormat,
    callbackQueue: DispatchQueue = .main
  ) throws {
    self.inputFormat = inputFormat
    self.outputFormat = outputFormat
    self.callbackQueue = callbackQueue
    self.converter = try PCMStreamConverter(inputFormat: inputFormat, outputFormat: outputFormat)
  }

  func queue(_ id: String, _ data: [UInt8]) throws {
    if data.isEmpty { return }

    let buffer = try converter.convert(data)
    let entry = ChunkEntry(
      id: id,
      buffer: buffer,
      offset: queueTimeline.reserve(frameCount: buffer.frameLength)
    )

    // Scheduled-ms upper bound + outstanding accounting, tagged with the current
    // generation so a later flush can disown this buffer's completion.
    let bufferMs = Double(entry.buffer.frameLength) / outputFormat.sampleRate * 1000.0
    let scheduledGeneration = accounting.schedule(bufferMs: bufferMs)

    queue.append(entry)
    listener?.onChunkQueued(id)
    // `.dataPlayedBack` fires when the buffer has actually been played out (not
    // merely consumed), so completionRenderedMs tracks true playout.
    scheduleBuffer(entry.buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      self?.callbackQueue.async { [weak self] in
        guard let self else { return }

        // Count toward completion-driven rendered ms only if this buffer wasn't
        // flushed (its generation still current).
        self.accounting.complete(
          generation: scheduledGeneration,
          bufferMs: bufferMs,
          now: ProcessInfo.processInfo.systemUptime
        )

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
    accounting.discardOutstanding(now: ProcessInfo.processInfo.systemUptime)

    isChunkQueueStartedNeeded = true
    super.stop()
    converter.resetForDiscontinuity()
    queueTimeline.resetAfterPlayerStop()

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

  /// Repair completion accounting after the independent render clock proves
  /// the snapshotted scheduled extent rendered out. This never calls `stop()`
  /// and never touches the player's scheduled buffers.
  func repairPlaybackAccounting(expectedScheduledMs: Int) -> PlaybackAccountingRepairOutcome {
    let outcome = accounting.repairRenderedOut(
      expectedScheduledMs: expectedScheduledMs,
      now: ProcessInfo.processInfo.systemUptime
    )
    guard outcome == .repaired else { return outcome }

    // The completion callbacks that normally retire these entries are the
    // failed signal being repaired. Retire their Dart queue ownership without
    // emitting `queueEnded`, whose listener intentionally stops the player.
    let repairedEntries = queue
    queue.removeAll()
    isChunkQueueStartedNeeded = true
    for entry in repairedEntries { listener?.onChunkPlayed(entry.id) }
    return outcome
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
