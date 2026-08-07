import AVFoundation

#if os(iOS)
  import UIKit
#endif

class RealtimeAudioSession: IOSAudioOutputSession {
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
      return outputKind.publicRouteValue
    #else
      return "other"
    #endif
  }

  var outputKind: IOSAudioOutputKind {
    #if os(iOS)
      guard let output = instance.currentRoute.outputs.first else { return .unknown }
      switch output.portType {
      case .builtInSpeaker: return .speaker
      case .builtInReceiver: return .receiver
      case .headphones, .headsetMic, .lineOut, .usbAudio: return .wired
      case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: return .bluetooth
      case .airPlay: return .airPlay
      default: return .other
      }
    #else
      return .other
    #endif
  }

  var availableOutputKinds: [IOSAudioOutputKind] {
    #if os(iOS)
      var kinds: [IOSAudioOutputKind] = [.speaker]
      if UIDevice.current.userInterfaceIdiom == .phone { kinds.append(.receiver) }
      for input in instance.availableInputs ?? [] {
        let kind: IOSAudioOutputKind?
        switch input.portType {
        case .headsetMic, .lineIn, .usbAudio:
          kind = .wired
        case .bluetoothHFP, .bluetoothLE:
          kind = .bluetooth
        default:
          kind = nil
        }
        if let kind, !kinds.contains(kind) { kinds.append(kind) }
      }
      let active = outputKind
      if !kinds.contains(active) { kinds.append(active) }
      return kinds
    #else
      return []
    #endif
  }

  var systemOutputVolume: Float? {
    #if os(iOS)
      return instance.outputVolume
    #else
      return nil
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
        var options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP, .duckOthers]
        if IOSAudioSessionProfile.usesDefaultToSpeaker(
          recorderEnabled: recorderEnabled,
          voiceProcessingRequested: voiceProcessingRequested
        ) {
          options.insert(.defaultToSpeaker)
        }
        try instance.setCategory(.playAndRecord, mode: mode, options: options)
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

  func applyRouteOverrideActions(_ actions: [IOSAudioRouteOverrideAction]) throws {
    #if os(iOS)
      for action in actions {
        switch action {
        case .clearOverride:
          try instance.overrideOutputAudioPort(.none)
        case .speaker:
          try instance.overrideOutputAudioPort(.speaker)
        }
      }
    #endif
  }

  /// Applies a user route request. Returns false when the requested external
  /// route is unavailable; thrown AVFoundation failures stay distinguishable
  /// from that stable availability result.
  func setOutput(_ output: IOSAudioOutputKind) throws -> Bool {
    #if os(iOS)
      guard
        let actions = IOSAudioOutputPolicy.manualSelectionActions(
          output,
          available: availableOutputKinds
        )
      else { return false }
      return try applyRouteSelectionActions(actions)
    #else
      return false
    #endif
  }

  @discardableResult
  func applyRouteSelectionActions(_ actions: [IOSAudioRouteSelectionAction]) throws -> Bool {
    #if os(iOS)
      for action in actions {
        switch action {
        case .clearPreferredInput:
          try instance.setPreferredInput(nil)
        case .preferInput(let kind):
          guard let input = preferredInput(for: kind) else { return false }
          try instance.setPreferredInput(input)
        case .clearOverride:
          try instance.overrideOutputAudioPort(.none)
        case .speaker:
          try instance.overrideOutputAudioPort(.speaker)
        }
      }
      return true
    #else
      return false
    #endif
  }

  #if os(iOS)
    private func preferredInput(for output: IOSAudioOutputKind) -> AVAudioSessionPortDescription? {
      instance.availableInputs?.first { input in
        switch output {
        case .receiver:
          return input.portType == .builtInMic
        case .wired:
          let wired: [AVAudioSession.Port] = [.headsetMic, .lineIn, .usbAudio]
          if instance.availableInputs?.contains(where: { wired.contains($0.portType) }) == true {
            return wired.contains(input.portType)
          }
          return input.portType == .builtInMic
        case .bluetooth:
          return [.bluetoothHFP, .bluetoothLE].contains(input.portType)
        case .speaker, .airPlay, .other, .unknown:
          return false
        }
      }
    }
  #endif
}
