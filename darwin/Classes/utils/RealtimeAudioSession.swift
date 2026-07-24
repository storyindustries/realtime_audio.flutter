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

  /// Coarse hardware route only. It is safe for operational telemetry and
  /// deliberately excludes device names and identifiers.
  var outputRouteClass: String {
    #if os(iOS)
      guard let output = instance.currentRoute.outputs.first else { return "unknown" }
      switch output.portType {
      case .builtInSpeaker: return "speaker"
      case .builtInReceiver: return "receiver"
      case .headphones, .headsetMic, .lineOut, .usbAudio: return "wired"
      case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: return "bluetooth"
      case .airPlay: return "airplay"
      default: return "other"
      }
    #else
      return "unknown"
    #endif
  }

  func configure(recorderEnabled: Bool, voiceProcessingRequested: Bool) throws {
    #if os(iOS)
      if !recorderEnabled {
        try instance.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try instance.setPreferredInputOrientation(.portrait)
      } else {
        // VoiceProcessingIO supplies AEC for voice calls. Do not also request
        // session echo-cancelled input: that preference is valid only in
        // `.default`, while this graph requires `.voiceChat`.
        let mode: AVAudioSession.Mode =
          voiceProcessingRequested
          ? .voiceChat
          : .default
        try instance.setCategory(
          .playAndRecord, mode: mode, options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers])
        try instance.setPreferredInputOrientation(.portrait)
        try instance.setAllowHapticsAndSystemSoundsDuringRecording(false)
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
