import AVFoundation

class RealtimeAudioSession {
  #if os(iOS)
    let instance = AVAudioSession.sharedInstance()
  #endif

  var sampleRate: Double? {
    #if os(iOS)
      return instance.sampleRate
    #else
      return nil
    #endif
  }

  /// Configure the audio session.
  ///
  /// - Parameters:
  ///   - recorderEnabled: Whether mic recording is active.
  ///   - useWebRtcApm: When true, avoids `.voiceChat` mode and system-level
  ///     echo cancellation to prevent double-processing with WebRTC APM.
  func configure(recorderEnabled: Bool, useWebRtcApm: Bool = false) throws {
    #if os(iOS)
      if !recorderEnabled {
        try instance.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try instance.setPreferredInputOrientation(.portrait)
      } else if useWebRtcApm {
        // WebRTC APM handles AEC/NS/AGC — use .default mode to avoid
        // system-level voice processing that would conflict.
        try instance.setCategory(
          .playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
        try instance.setPreferredInputOrientation(.portrait)
        try instance.setAllowHapticsAndSystemSoundsDuringRecording(false)
      } else {
        try instance.setCategory(
          .playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
        try instance.setPreferredInputOrientation(.portrait)
        try instance.setAllowHapticsAndSystemSoundsDuringRecording(false)
        if #available(iOS 18.2, *) {
          try instance.setPrefersEchoCancelledInput(true)
        }
      }
    #endif
  }

  func activate() throws {
    #if os(iOS)
      try instance.setActive(true, options: [.notifyOthersOnDeactivation])
    #endif
  }

  func deactivate() throws {
    #if os(iOS)
      try instance.setActive(false)
    #endif
  }
}
