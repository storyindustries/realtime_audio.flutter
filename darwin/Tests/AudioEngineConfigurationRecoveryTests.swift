import XCTest
@testable import RealtimeAudioRecovery

final class AudioEngineConfigurationRecoveryTests: XCTestCase {
  private enum Failure: Error { case capture, engine }

  func testRunningEngineIgnoresBenignConfigurationChange() {
    XCTAssertEqual(
      AudioEngineConfigurationRecoveryPolicy.decide(
        shouldBeStarted: true,
        shouldBePaused: false,
        engineIsRunning: true,
        recoveryIsRunning: false
      ),
      .ignoreHealthyEngine
    )
  }

  func testStoppedEngineRestartsWithoutPurgingPlayback() {
    XCTAssertEqual(
      AudioEngineConfigurationRecoveryPolicy.decide(
        shouldBeStarted: true,
        shouldBePaused: false,
        engineIsRunning: false,
        recoveryIsRunning: false
      ),
      .restartStoppedEnginePreservingPlayback
    )
  }

  func testDeliberatelyStoppedEngineDoesNotRestart() {
    XCTAssertEqual(
      AudioEngineConfigurationRecoveryPolicy.decide(
        shouldBeStarted: false,
        shouldBePaused: false,
        engineIsRunning: false,
        recoveryIsRunning: false
      ),
      .ignoreInactiveEngine
    )
  }

  func testPausedEngineDoesNotMistakePauseForConfigurationFailure() {
    XCTAssertEqual(
      AudioEngineConfigurationRecoveryPolicy.decide(
        shouldBeStarted: true,
        shouldBePaused: true,
        engineIsRunning: false,
        recoveryIsRunning: false
      ),
      .ignoreInactiveEngine
    )
  }

  func testRecoveryDoesNotReenter() {
    XCTAssertEqual(
      AudioEngineConfigurationRecoveryPolicy.decide(
        shouldBeStarted: true,
        shouldBePaused: false,
        engineIsRunning: false,
        recoveryIsRunning: true
      ),
      .ignoreRecoveryInProgress
    )
  }

  func testRecoveryRebuildsCaptureThenStartsAndResumesWithoutPurgeStep() throws {
    var actions: [String] = []

    try AudioEngineConfigurationRecovery.recoverStoppedEngine(
      reinstallCapture: { actions.append("capture") },
      startEngine: { actions.append("engine") },
      removeCaptureAfterFailure: { actions.append("cleanup") },
      resumePreservedPlayback: { actions.append("playback") }
    )

    XCTAssertEqual(actions, ["capture", "engine", "playback"])
  }

  func testCaptureFailureLeavesPreservedPlaybackUnchangedAndDoesNotStart() {
    var actions: [String] = []

    XCTAssertThrowsError(
      try AudioEngineConfigurationRecovery.recoverStoppedEngine(
        reinstallCapture: {
          actions.append("capture")
          throw Failure.capture
        },
        startEngine: { actions.append("engine") },
        removeCaptureAfterFailure: { actions.append("cleanup") },
        resumePreservedPlayback: { actions.append("playback") }
      )
    )

    XCTAssertEqual(actions, ["capture", "cleanup"])
  }

  func testEngineStartFailureDoesNotClaimPlaybackResumed() {
    var actions: [String] = []

    XCTAssertThrowsError(
      try AudioEngineConfigurationRecovery.recoverStoppedEngine(
        reinstallCapture: { actions.append("capture") },
        startEngine: {
          actions.append("engine")
          throw Failure.engine
        },
        removeCaptureAfterFailure: { actions.append("cleanup") },
        resumePreservedPlayback: { actions.append("playback") }
      )
    )

    XCTAssertEqual(actions, ["capture", "engine", "cleanup"])
  }

  func testWedgeOnHealthyEngineDiscardsPlayerWithoutEngineRestart() {
    XCTAssertEqual(PlaybackWedgeRecoveryPolicy.decide(engineIsRunning: true), .discardPlayerOnly)
  }

  func testWedgeOnStoppedEngineDiscardsPlayerAndRestartsEngine() {
    XCTAssertEqual(PlaybackWedgeRecoveryPolicy.decide(engineIsRunning: false), .discardPlayerAndRestartEngine)
  }
}
