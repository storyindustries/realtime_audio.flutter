enum AudioEngineConfigurationRecoveryDecision: Equatable {
  case ignoreInactiveEngine
  case ignoreHealthyEngine
  case ignoreRecoveryInProgress
  case restartStoppedEnginePreservingPlayback
}

/// Pure policy for `AVAudioEngineConfigurationChange` notifications.
///
/// Voice-processing I/O posts benign configuration changes while the engine is
/// still running. Restarting that healthy engine calls `AVAudioPlayerNode.stop`
/// and discards scheduled speech. A genuine system-driven engine stop is
/// recoverable, but it must be restarted without stopping or resetting the
/// player so its scheduled buffers survive.
enum AudioEngineConfigurationRecoveryPolicy {
  static func decide(
    shouldBeStarted: Bool,
    shouldBePaused: Bool,
    engineIsRunning: Bool,
    recoveryIsRunning: Bool
  ) -> AudioEngineConfigurationRecoveryDecision {
    guard shouldBeStarted, !shouldBePaused else { return .ignoreInactiveEngine }
    guard !recoveryIsRunning else { return .ignoreRecoveryInProgress }
    guard !engineIsRunning else { return .ignoreHealthyEngine }
    return .restartStoppedEnginePreservingPlayback
  }
}

/// Recovery sequence deliberately has no player/engine stop or reset action.
/// Keeping those operations outside the recovery vocabulary makes queue
/// preservation structural rather than dependent on a caller remembering a
/// flag on a destructive restart helper.
enum AudioEngineConfigurationRecovery {
  static func recoverStoppedEngine(
    reinstallCapture: () throws -> Void,
    startEngine: () throws -> Void,
    removeCaptureAfterFailure: () -> Void,
    resumePreservedPlayback: () -> Void
  ) throws {
    do {
      try reinstallCapture()
      try startEngine()
    } catch {
      removeCaptureAfterFailure()
      throw error
    }
    resumePreservedPlayback()
  }
}

enum PlaybackWedgeRecoveryDecision: Equatable {
  case discardPlayerOnly
  case discardPlayerAndRestartEngine
}

enum PlaybackWedgeRecoveryPolicy {
  static func decide(engineIsRunning: Bool) -> PlaybackWedgeRecoveryDecision {
    engineIsRunning ? .discardPlayerOnly : .discardPlayerAndRestartEngine
  }
}
