import Foundation

/// Pure, side-effect-free render-clock math, factored out so it is trivially
/// correct and unit-testable independent of AVAudioEngine.
enum RenderClock {
  /// Convert a playback-head sample position to milliseconds.
  ///
  /// Guards against non-positive sample rates / negative sample times (which
  /// `AVAudioPlayerNode.playerTime` can transiently report before the first
  /// render) by clamping to `0`.
  static func framesToMs(sampleTime: Int64, sampleRate: Double) -> Int {
    guard sampleRate > 0, sampleTime > 0 else { return 0 }
    return Int((Double(sampleTime) / sampleRate * 1000.0).rounded())
  }
}
