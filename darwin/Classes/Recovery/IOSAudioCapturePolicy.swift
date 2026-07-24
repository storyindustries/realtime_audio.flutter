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
