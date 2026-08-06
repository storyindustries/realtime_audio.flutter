import Foundation

enum IOSAudioCaptureStrategy: Equatable {
  case none
  case inputVoiceProcessing
}

/// Selects one mutually-exclusive iOS echo-cancellation path.
///
/// VoiceProcessingIO already provides echo cancellation for voice sessions.
/// The separate session echo-input preference is therefore neither needed nor
/// valid with `.voiceChat`; requesting both produced startup failures.
enum IOSAudioCapturePolicy {
  static func strategy(
    recorderEnabled: Bool,
    voiceProcessingRequested: Bool
  ) -> IOSAudioCaptureStrategy {
    guard recorderEnabled, voiceProcessingRequested else { return .none }
    return .inputVoiceProcessing
  }
}

/// What has to happen to the shared VoiceProcessingIO unit for a target
/// capture strategy.
enum IOSVoiceProcessingTransition: Equatable {
  /// The unit was never turned on and is not wanted. `AVAudioEngine.inputNode`
  /// must not even be materialised: with the recorder off the session is
  /// `.playback`, where the input hardware format is invalid.
  case leaveUntouched
  case enable
  case disable

  /// Whether the toggle has to run BEFORE the audio session is reconfigured.
  ///
  /// Disabling reconfigures the I/O unit in place, so it needs the still
  /// record-capable session; enabling needs the new record-capable session to
  /// already be active.
  var mustPrecedeSessionReconfiguration: Bool { self == .disable }
}

enum IOSVoiceProcessingPolicy {
  static func transition(
    target: IOSAudioCaptureStrategy,
    isApplied: Bool
  ) -> IOSVoiceProcessingTransition {
    switch target {
    case .inputVoiceProcessing:
      // Always re-assert: the engine reads the unit's real state back, so a
      // unit the system silently dropped is turned on again.
      return .enable
    case .none:
      return isApplied ? .disable : .leaveUntouched
    }
  }
}

enum RealtimeAudioPlatformErrorCode: String, Equatable {
  case insufficientPriority = "audio_session_insufficient_priority"
  case internalFailure = "INTERNAL"
}

enum IOSAudioErrorClassifier {
  static let insufficientPriorityOSStatus = 561_017_449 // '!pri'

  static func code(domain: String, osStatus: Int) -> RealtimeAudioPlatformErrorCode {
    domain == NSOSStatusErrorDomain && osStatus == insufficientPriorityOSStatus
      ? .insufficientPriority
      : .internalFailure
  }
}

/// Keeps observable recorder state truthful when native reconfiguration fails.
struct RecorderStateRollbackError: LocalizedError {
  let transitionDescription: String
  let rollbackDescription: String

  init(transitionError: Error, rollbackError: Error) {
    transitionDescription = String(describing: transitionError)
    rollbackDescription = String(describing: rollbackError)
  }

  var errorDescription: String? {
    "Recorder transition failed (\(transitionDescription)); "
      + "restoring the previous native state also failed (\(rollbackDescription))."
  }
}

enum RecorderStateTransition {
  static func apply(
    targetEnabled: Bool,
    performNativeTransition: () throws -> Void,
    rollbackNativeTransition: () throws -> Void,
    commit: (Bool) -> Void
  ) throws {
    do {
      try performNativeTransition()
    } catch {
      let transitionError = error
      do {
        try rollbackNativeTransition()
      } catch {
        throw RecorderStateRollbackError(
          transitionError: transitionError,
          rollbackError: error
        )
      }
      throw transitionError
    }
    commit(targetEnabled)
  }
}

enum IOSAudioOutputKind: String, Equatable {
  case speaker
  case receiver
  case wired
  case bluetooth
  case airPlay
  case other
  case unknown

  var isExternal: Bool {
    switch self {
    // Unknown output port types may be car or display routes. Preserve them;
    // forcing speaker is safe only for known built-in outputs.
    case .wired, .bluetooth, .airPlay, .other:
      return true
    case .speaker, .receiver, .unknown:
      return false
    }
  }

  var publicRouteValue: String {
    switch self {
    case .speaker, .receiver, .wired, .bluetooth:
      return rawValue
    case .airPlay, .other, .unknown:
      return "other"
    }
  }
}

enum IOSAudioRouteOverrideAction: Equatable {
  case clearOverride
  case speaker
}

enum IOSAudioRouteSelectionAction: Equatable {
  case clearPreferredInput
  case preferInput(IOSAudioOutputKind)
  case clearOverride
  case speaker
}

enum IOSAudioOutputSelectionResult: String, Equatable {
  case automatic
  case applied
  case failed
  case unavailable
}

enum IOSAudioRouteChangeReason: Equatable {
  case newDeviceAvailable
  case oldDeviceUnavailable
  case categoryChange
  case override
  case other
}

/// The system output volume is already applied by the hardware route. The
/// engine mixer stays at unity so the same user-owned gain is never multiplied
/// into the signal a second time.
enum IOSPlaybackGainPolicy {
  static func mainMixerGain(systemOutputVolume: Float) -> Float {
    _ = systemOutputVolume
    return 1
  }
}

/// Pure audio-session shape shared by the AVFoundation adapter and tests.
enum IOSAudioSessionProfile {
  static func usesDefaultToSpeaker(
    recorderEnabled: Bool,
    voiceProcessingRequested: Bool
  ) -> Bool {
    recorderEnabled && !voiceProcessingRequested
  }
}

/// Pure route policy. Hardware-specific code maps these finite actions to
/// `overrideOutputAudioPort`, keeping notification handling deterministic.
enum IOSAudioOutputPolicy {
  static func manualSelectionResult(
    requested: IOSAudioOutputKind,
    commandAccepted: Bool,
    active: IOSAudioOutputKind
  ) -> IOSAudioOutputSelectionResult {
    guard commandAccepted else { return .unavailable }
    return active == requested ? .applied : .failed
  }

  static func manualSelectionActions(
    _ output: IOSAudioOutputKind,
    available: [IOSAudioOutputKind]
  ) -> [IOSAudioRouteSelectionAction]? {
    guard available.contains(output) else { return nil }
    switch output {
    case .speaker:
      return [.clearPreferredInput, .speaker]
    case .receiver:
      return [.preferInput(.receiver), .clearOverride]
    case .wired, .bluetooth:
      return [.clearOverride, .preferInput(output)]
    case .airPlay, .other, .unknown:
      return nil
    }
  }

  static func postStartActions(
    currentOutput: IOSAudioOutputKind,
    userSelection: IOSAudioOutputKind?
  ) -> [IOSAudioRouteOverrideAction] {
    guard userSelection == nil, !currentOutput.isExternal else { return [] }
    return [.clearOverride, .speaker]
  }

  static func routeChangeActions(
    currentOutput: IOSAudioOutputKind,
    userSelection: IOSAudioOutputKind?,
    reason: IOSAudioRouteChangeReason
  ) -> [IOSAudioRouteOverrideAction] {
    guard reason == .newDeviceAvailable || reason == .oldDeviceUnavailable else {
      return []
    }
    guard userSelection == nil, !currentOutput.isExternal else { return [] }
    return [.speaker]
  }
}
