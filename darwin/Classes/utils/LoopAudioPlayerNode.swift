import AVFoundation

class LoopAudioPlayerNode: AVAudioPlayerNode {
  private var inputFormat: AVAudioFormat
  private var outputFormat: AVAudioFormat
  private let callbackQueue: DispatchQueue

  private let converter: PCMStreamConverter

  private var loopingId: String?
  private var loopingData: [UInt8]?
  private var loopingDataLoop: Bool = false

  var data: [UInt8]? { loopingData }

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

  func queue(_ id: String, _ data: [UInt8], loop: Bool = false) throws {
    stop()

    if data.isEmpty { return }

    let buffer = try converter.convert(data)

    loopingId = id
    loopingData = data
    loopingDataLoop = loop
    scheduleBuffer(buffer) { [weak self] in
      self?.callbackQueue.async { [weak self] in
        guard let self else { return }
        if loopingId != id || !loop { return }

        try? queue(id, data, loop: loop)
        play()
      }
    }
  }

  func stop(isRestart: Bool = false) {
    if !isRestart {
      loopingId = nil
      loopingData = nil
    }
    super.stop()
    converter.resetForDiscontinuity()
  }
}
