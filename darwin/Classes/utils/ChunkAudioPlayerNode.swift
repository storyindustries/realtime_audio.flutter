import AVFoundation

class ChunkAudioPlayerNode: AVAudioPlayerNode {
  private var inputFormat: AVAudioFormat
  private var outputFormat: AVAudioFormat

  var queue: [ChunkEntry] = []
  var totalSampleTime: UInt32 { (queue.last?.offset ?? 0) + (queue.last?.buffer.frameLength ?? 0) }

  private var isChunkQueueStartedNeeded = true
  private let converter: PCMStreamConverter
  private weak var listener: ChunkAudioEventListener? = nil

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

    super.play()
  }

  override func stop() {
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
