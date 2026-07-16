import AVFoundation

/// Converts PCM buffers while retaining the resampler's phase between adjacent
/// packets. Reset only when the source stream is explicitly discontinuous.
final class PCMStreamConverter {
  private let converter: AVAudioConverter
  private let inputFormat: AVAudioFormat
  private let outputFormat: AVAudioFormat

  convenience init(inputSampleRate: Double, outputSampleRate: Double) throws {
    guard
      let inputFormat = getAudioFormat(.pcmFormatInt16, inputSampleRate, 1),
      let outputFormat = getAudioFormat(.pcmFormatFloat32, outputSampleRate, 1)
    else {
      throw TextError("Failed to create PCM stream formats.")
    }
    try self.init(inputFormat: inputFormat, outputFormat: outputFormat)
  }

  init(inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) throws {
    guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
      throw TextError("Failed to create an AVAudioConverter.")
    }
    self.converter = converter
    self.inputFormat = inputFormat
    self.outputFormat = outputFormat
  }

  func convert(_ data: [UInt8]) throws -> AVAudioPCMBuffer {
    let bytesPerFrame = Int(inputFormat.streamDescription.pointee.mBytesPerFrame)
    guard bytesPerFrame > 0, data.count.isMultiple(of: bytesPerFrame) else {
      throw TextError("PCM data does not contain complete input frames.")
    }

    let inputFrameCount = AVAudioFrameCount(data.count / bytesPerFrame)
    guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inputFrameCount) else {
      throw TextError("Failed to allocate input PCM buffer.")
    }
    inputBuffer.frameLength = inputFrameCount

    guard let inputChannel = inputBuffer.int16ChannelData?[0] else {
      throw TextError("Expected interleaved Int16 PCM input.")
    }
    data.withUnsafeBytes { source in
      inputChannel.initialize(
        from: source.bindMemory(to: Int16.self).baseAddress!,
        count: Int(inputFrameCount)
      )
    }

    // AVAudioConverter can need a small extra frame at a non-integer rate
    // ratio. The padding avoids clipping the tail of an otherwise continuous
    // stream while preserving its internal resampler state.
    let outputCapacity = AVAudioFrameCount(
      ceil(Double(inputFrameCount) * outputFormat.sampleRate / inputFormat.sampleRate) + 32
    )
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
      throw TextError("Failed to allocate output PCM buffer.")
    }

    var inputWasProvided = false
    var error: NSError?
    converter.convert(to: outputBuffer, error: &error) { _, status in
      guard !inputWasProvided else {
        status.pointee = .noDataNow
        return nil
      }
      inputWasProvided = true
      status.pointee = .haveData
      return inputBuffer
    }

    if let error { throw TextError(error.localizedDescription) }
    return outputBuffer
  }

  func resetForDiscontinuity() {
    converter.reset()
  }
}
