import AVFoundation
import Flutter
import XCTest
@testable import realtime_audio

class RunnerTests: XCTestCase {
  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

  func testContinuousConverterPreservesWaveformAcrossCascadeSizedChunks() throws {
    let source = pcm16Sine(sampleRate: 24_000, frequency: 440, sampleCount: 9_600)
    let expected = try PCMStreamConverter(inputSampleRate: 24_000, outputSampleRate: 44_100).convert(source)

    let chunkedConverter = try PCMStreamConverter(inputSampleRate: 24_000, outputSampleRate: 44_100)
    let chunkSizes = [480, 960, 2_400] // 20 ms, 40 ms, 100 ms at the cascade's 24 kHz wire rate.
    var chunked: [Float] = []
    var offset = 0
    var chunkIndex = 0
    while offset < source.count {
      let byteCount = min(chunkSizes[chunkIndex % chunkSizes.count] * MemoryLayout<Int16>.size, source.count - offset)
      let converted = try chunkedConverter.convert(Array(source[offset..<(offset + byteCount)]))
      chunked.append(contentsOf: samples(from: converted))
      offset += byteCount
      chunkIndex += 1
    }

    let whole = samples(from: expected)
    XCTAssertEqual(chunked.count, whole.count)
    XCTAssertLessThan(maximumAbsoluteDifference(chunked, whole), 0.001)
  }

  func testDiscontinuityResetMakesTheNextSegmentMatchAFreshConverter() throws {
    let first = pcm16Sine(sampleRate: 24_000, frequency: 440, sampleCount: 480)
    let second = pcm16Sine(sampleRate: 24_000, frequency: 440, sampleCount: 960, phaseOffset: 480)
    let converter = try PCMStreamConverter(inputSampleRate: 24_000, outputSampleRate: 44_100)

    _ = try converter.convert(first)
    converter.resetForDiscontinuity()
    let afterReset = samples(from: try converter.convert(second))
    let fresh = samples(
      from: try PCMStreamConverter(inputSampleRate: 24_000, outputSampleRate: 44_100).convert(second)
    )

    XCTAssertEqual(afterReset.count, fresh.count)
    XCTAssertLessThan(maximumAbsoluteDifference(afterReset, fresh), 0.000_001)
  }

  private func pcm16Sine(
    sampleRate: Double,
    frequency: Double,
    sampleCount: Int,
    phaseOffset: Int = 0
  ) -> [UInt8] {
    let samples = (0..<sampleCount).map { index -> Int16 in
      let phase = 2 * Double.pi * frequency * Double(index + phaseOffset) / sampleRate
      return Int16((sin(phase) * Double(Int16.max) * 0.8).rounded())
    }
    return samples.withUnsafeBytes(Array.init)
  }

  private func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
    Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
  }

  private func maximumAbsoluteDifference(_ lhs: [Float], _ rhs: [Float]) -> Float {
    zip(lhs, rhs).map { abs($0 - $1) }.max() ?? 0
  }

}
