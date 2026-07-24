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
