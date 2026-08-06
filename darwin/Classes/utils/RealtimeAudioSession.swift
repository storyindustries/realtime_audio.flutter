import AVFoundation

#if os(iOS)
  import UIKit
#endif

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
      return outputKind.publicRouteValue
    #else
      return "other"
    #endif
  }

  #if os(iOS)
    var outputKind: IOSAudioOutputKind {
      guard let output = instance.currentRoute.outputs.first else { return .unknown }
      switch output.portType {
      case .builtInSpeaker: return .speaker
      case .builtInReceiver: return .receiver
      case .headphones, .headsetMic, .lineOut, .usbAudio: return .wired
      case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: return .bluetooth
      case .airPlay: return .airPlay
      default: return .other
      }
    }

    var availableOutputKinds: [IOSAudioOutputKind] {
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
    }

    var systemOutputVolume: Float { instance.outputVolume }
  #endif

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

  #if os(iOS)
    func applyRouteOverrideActions(_ actions: [IOSAudioRouteOverrideAction]) throws {
      for action in actions {
        switch action {
        case .clearOverride:
          try instance.overrideOutputAudioPort(.none)
        case .speaker:
          try instance.overrideOutputAudioPort(.speaker)
        }
      }
    }

    /// Applies a user route request. Returns false when the requested external
    /// route is unavailable; thrown AVFoundation failures stay distinguishable
    /// from that stable availability result.
    func setOutput(_ output: IOSAudioOutputKind) throws -> Bool {
      guard
        let actions = IOSAudioOutputPolicy.manualSelectionActions(
          output,
          available: availableOutputKinds
        )
      else { return false }
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
    }

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

    func clearPreferredInput() throws {
      try instance.setPreferredInput(nil)
    }
  #endif
}

/// Owns the user-requested iOS output and applies the pure route policy to the
/// AVAudioSession adapter. Selection failures are returned as stable diagnostic
/// codes; the engine decides how to publish or alert them.
final class IOSAudioOutputController {
  private let session: RealtimeAudioSession

  #if os(iOS)
    private var requestedOutput: IOSAudioOutputKind?
    private var selectionResult = "automatic"
  #endif

  init(session: RealtimeAudioSession) {
    self.session = session
  }

  func stateMap() -> [String: Any] {
    #if os(iOS)
      var available: [String] = []
      for route in session.availableOutputKinds.map(\.publicRouteValue) {
        if !available.contains(route) { available.append(route) }
      }
      return [
        "active": session.outputKind.publicRouteValue,
        "available": available,
        "requested": requestedOutput?.publicRouteValue ?? NSNull(),
        "selectionResult": selectionResult,
        "volumeControlStream": NSNull(),
        "volume": Double(session.systemOutputVolume),
      ]
    #else
      return [
        "active": "other",
        "available": ["other"],
        "requested": NSNull(),
        "selectionResult": "unavailable",
        "volumeControlStream": NSNull(),
        "volume": NSNull(),
      ]
    #endif
  }

  #if os(iOS)
    func applyPostStart(
      voiceProcessingActive: Bool,
      routeSelectionAvailable: Bool
    ) -> String? {
      guard routeSelectionAvailable else {
        if requestedOutput != nil { selectionResult = "unavailable" }
        return nil
      }
      if let requestedOutput { return applyRequestedOutput(requestedOutput) }
      guard voiceProcessingActive else { return nil }
      let actions = IOSAudioOutputPolicy.postStartActions(
        currentOutput: session.outputKind,
        userSelection: nil
      )
      let failure = applyAutomaticActions(actions)
      selectionResult = failure == nil ? "automatic" : "failed"
      return failure
    }

    func handleRouteChange(
      reason: AVAudioSession.RouteChangeReason?,
      voiceProcessingActive: Bool,
      routeSelectionAvailable: Bool,
      engineIsStarted: Bool
    ) -> String? {
      guard engineIsStarted, routeSelectionAvailable else { return nil }
      if let requestedOutput {
        selectionResult =
          IOSAudioOutputPolicy.manualSelectionResult(
            requested: requestedOutput,
            commandAccepted: session.availableOutputKinds.contains(requestedOutput),
            active: session.outputKind
          ).rawValue
      }
      let policyReason = routeChangeReason(reason)
      guard policyReason == .newDeviceAvailable || policyReason == .oldDeviceUnavailable else {
        return nil
      }

      if let requestedOutput {
        let failure = applyRequestedOutput(requestedOutput)
        if selectionResult == "unavailable", voiceProcessingActive {
          let actions = IOSAudioOutputPolicy.routeChangeActions(
            currentOutput: session.outputKind,
            userSelection: nil,
            reason: policyReason
          )
          if let fallbackFailure = applyAutomaticActions(actions) {
            selectionResult = "failed"
            return fallbackFailure
          }
        }
        return failure
      }

      guard voiceProcessingActive else { return nil }
      let actions = IOSAudioOutputPolicy.routeChangeActions(
        currentOutput: session.outputKind,
        userSelection: nil,
        reason: policyReason
      )
      let failure = applyAutomaticActions(actions)
      selectionResult = failure == nil ? "automatic" : "failed"
      return failure
    }

    func setRequestedOutput(
      _ rawValue: String?,
      voiceProcessingActive: Bool,
      routeSelectionAvailable: Bool
    ) -> String? {
      guard let rawValue else {
        requestedOutput = nil
        selectionResult = "automatic"
        guard routeSelectionAvailable else { return nil }
        do {
          try session.clearPreferredInput()
        } catch {
          selectionResult = "failed"
          return "automatic_input_failed"
        }
        let actions =
          voiceProcessingActive
          ? IOSAudioOutputPolicy.postStartActions(
            currentOutput: session.outputKind,
            userSelection: nil
          )
          : []
        let failure = applyAutomaticActions(actions)
        selectionResult = failure == nil ? "automatic" : "failed"
        return failure
      }

      guard let route = IOSAudioOutputKind(rawValue: rawValue), route != .other,
        route != .unknown, route != .airPlay
      else {
        selectionResult = "unavailable"
        return nil
      }
      requestedOutput = route
      guard routeSelectionAvailable else {
        selectionResult = "unavailable"
        return nil
      }
      return applyRequestedOutput(route)
    }

    private func applyRequestedOutput(_ route: IOSAudioOutputKind) -> String? {
      guard session.availableOutputKinds.contains(route) else {
        selectionResult = "unavailable"
        return nil
      }
      do {
        let accepted = try session.setOutput(route)
        selectionResult =
          IOSAudioOutputPolicy.manualSelectionResult(
            requested: route,
            commandAccepted: accepted,
            active: session.outputKind
          ).rawValue
        return nil
      } catch {
        selectionResult = "failed"
        return "requested_route_failed"
      }
    }

    private func applyAutomaticActions(_ actions: [IOSAudioRouteOverrideAction]) -> String? {
      guard !actions.isEmpty else { return nil }
      do {
        try session.applyRouteOverrideActions(actions)
        return nil
      } catch {
        return "automatic_route_failed"
      }
    }

    private func routeChangeReason(
      _ reason: AVAudioSession.RouteChangeReason?
    ) -> IOSAudioRouteChangeReason {
      switch reason {
      case .newDeviceAvailable: return .newDeviceAvailable
      case .oldDeviceUnavailable: return .oldDeviceUnavailable
      case .categoryChange: return .categoryChange
      case .override: return .override
      default: return .other
      }
    }
  #endif
}
