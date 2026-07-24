import XCTest
@testable import RealtimeAudioRecovery

final class IOSAudioCapturePolicyTests: XCTestCase {
  func testVoiceProcessingUsesInputNodeVPIO() {
    XCTAssertEqual(
      IOSAudioCapturePolicy.strategy(
        recorderEnabled: true,
        voiceProcessingRequested: true
      ),
      .inputVoiceProcessing
    )
  }

  func testDisabledRecorderDoesNotEnableVoiceProcessing() {
    XCTAssertEqual(
      IOSAudioCapturePolicy.strategy(
        recorderEnabled: false,
        voiceProcessingRequested: true
      ),
      .none
    )
  }

  func testUnrequestedVoiceProcessingStaysDisabled() {
    XCTAssertEqual(
      IOSAudioCapturePolicy.strategy(
        recorderEnabled: true,
        voiceProcessingRequested: false
      ),
      .none
    )
  }

  func testVoiceProcessingIsLeftUntouchedWhenItWasNeverEnabled() {
    // `AVAudioEngine.inputNode` may only be materialised while the session is
    // record-capable. A playback-only engine never requests voice processing,
    // so it must not instantiate the shared I/O unit at all.
    XCTAssertEqual(
      IOSVoiceProcessingPolicy.transition(target: .none, isApplied: false),
      .leaveUntouched
    )
  }

  func testVoiceProcessingIsDisabledOnlyAfterItWasApplied() {
    XCTAssertEqual(
      IOSVoiceProcessingPolicy.transition(target: .none, isApplied: true),
      .disable
    )
  }

  func testVoiceProcessingIsReassertedEvenWhenAlreadyApplied() {
    // The read-back in the engine is authoritative; the policy must keep asking
    // so a unit the system silently dropped is turned back on.
    XCTAssertEqual(
      IOSVoiceProcessingPolicy.transition(target: .inputVoiceProcessing, isApplied: false),
      .enable
    )
    XCTAssertEqual(
      IOSVoiceProcessingPolicy.transition(target: .inputVoiceProcessing, isApplied: true),
      .enable
    )
  }

  func testDisablingVoiceProcessingPrecedesThePlaybackOnlySession() {
    // Turning the shared I/O unit off reconfigures it in place, so it has to
    // happen while the session still exposes a valid input format. Turning it
    // on requires the record-capable session to already be active.
    XCTAssertTrue(IOSVoiceProcessingTransition.disable.mustPrecedeSessionReconfiguration)
    XCTAssertFalse(IOSVoiceProcessingTransition.enable.mustPrecedeSessionReconfiguration)
    XCTAssertFalse(IOSVoiceProcessingTransition.leaveUntouched.mustPrecedeSessionReconfiguration)
  }

  func testRecorderTransitionCommitsOnlyAfterNativeApplySucceeds() throws {
    var actions: [String] = []

    XCTAssertThrowsError(
      try RecorderStateTransition.apply(
        targetEnabled: true,
        performNativeTransition: {
          actions.append("transition")
          throw TestFailure.native
        },
        rollbackNativeTransition: { actions.append("rollback") },
        commit: { _ in actions.append("commit") }
      )
    )

    XCTAssertEqual(actions, ["transition", "rollback"])

    try RecorderStateTransition.apply(
      targetEnabled: true,
      performNativeTransition: { actions.append("transition-success") },
      rollbackNativeTransition: { actions.append("unexpected-rollback") },
      commit: { enabled in actions.append("commit-\(enabled)") }
    )
    XCTAssertEqual(
      actions,
      ["transition", "rollback", "transition-success", "commit-true"]
    )
  }

  func testRecorderTransitionSurfacesRollbackFailure() {
    XCTAssertThrowsError(
      try RecorderStateTransition.apply(
        targetEnabled: false,
        performNativeTransition: { throw TestFailure.native },
        rollbackNativeTransition: { throw TestFailure.rollback },
        commit: { _ in XCTFail("failed transition must not commit") }
      )
    ) { error in
      guard let failure = error as? RecorderStateRollbackError else {
        return XCTFail("unexpected error: \(error)")
      }
      XCTAssertEqual(failure.transitionDescription, "native")
      XCTAssertEqual(failure.rollbackDescription, "rollback")
    }
  }

  func testInsufficientPriorityOSStatusHasTypedErrorCode() {
    XCTAssertEqual(
      IOSAudioErrorClassifier.code(
        domain: NSOSStatusErrorDomain,
        osStatus: 561_017_449
      ),
      .insufficientPriority
    )
    XCTAssertEqual(
      IOSAudioErrorClassifier.code(
        domain: "other-domain",
        osStatus: 561_017_449
      ),
      .internalFailure
    )
    XCTAssertEqual(
      IOSAudioErrorClassifier.code(domain: NSOSStatusErrorDomain, osStatus: -50),
      .internalFailure
    )
  }

  private enum TestFailure: Error {
    case native
    case rollback
  }
}
