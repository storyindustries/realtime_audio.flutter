import XCTest

@testable import RealtimeAudioRecovery

final class IOSAudioOutputPolicyTests: XCTestCase {
  func testSystemVolumeNeverAttenuatesTheEngineMixer() {
    for systemVolume: Float in [0, 0.2, 0.6, 1] {
      XCTAssertEqual(
        IOSPlaybackGainPolicy.mainMixerGain(systemOutputVolume: systemVolume),
        1,
        "the user-owned system volume must not be multiplied by a second software gain"
      )
    }
  }

  func testVoiceProcessingProfileOmitsPersistentDefaultSpeakerOption() {
    XCTAssertFalse(
      IOSAudioSessionProfile.usesDefaultToSpeaker(
        recorderEnabled: true,
        voiceProcessingRequested: true
      )
    )
    XCTAssertTrue(
      IOSAudioSessionProfile.usesDefaultToSpeaker(
        recorderEnabled: true,
        voiceProcessingRequested: false
      )
    )
  }

  func testPostStartBouncesToSpeakerWhenAutomaticPolicyHasNoExternalRoute() {
    XCTAssertEqual(
      IOSAudioOutputPolicy.postStartActions(
        currentOutput: .receiver,
        userSelection: nil
      ),
      [.clearOverride, .speaker]
    )
  }

  func testPostStartPreservesAnExternalRoute() {
    for output: IOSAudioOutputKind in [.wired, .bluetooth, .airPlay, .other] {
      XCTAssertEqual(
        IOSAudioOutputPolicy.postStartActions(
          currentOutput: output,
          userSelection: nil
        ),
        []
      )
    }
  }

  func testPostStartPreservesEveryManualSelection() {
    for selection: IOSAudioOutputKind in [.speaker, .receiver, .wired, .bluetooth, .airPlay] {
      XCTAssertEqual(
        IOSAudioOutputPolicy.postStartActions(
          currentOutput: .receiver,
          userSelection: selection
        ),
        []
      )
    }
  }

  func testExternalRouteChangeReassertsAutomaticSpeakerPolicy() {
    XCTAssertEqual(
      IOSAudioOutputPolicy.routeChangeActions(
        currentOutput: .receiver,
        userSelection: nil,
        reason: .oldDeviceUnavailable
      ),
      [.speaker]
    )
  }

  func testRouteChangesPreserveExternalAndManualRoutes() {
    XCTAssertEqual(
      IOSAudioOutputPolicy.routeChangeActions(
        currentOutput: .bluetooth,
        userSelection: nil,
        reason: .newDeviceAvailable
      ),
      []
    )
    XCTAssertEqual(
      IOSAudioOutputPolicy.routeChangeActions(
        currentOutput: .receiver,
        userSelection: .receiver,
        reason: .oldDeviceUnavailable
      ),
      []
    )
  }

  func testSelfInducedRouteChangesNeverReenterPolicy() {
    for reason: IOSAudioRouteChangeReason in [.categoryChange, .override, .other] {
      XCTAssertEqual(
        IOSAudioOutputPolicy.routeChangeActions(
          currentOutput: .receiver,
          userSelection: nil,
          reason: reason
        ),
        []
      )
    }
  }

  func testManualSpeakerAndReceiverCommandsUseDeterministicOverrideOrder() {
    XCTAssertEqual(
      IOSAudioOutputPolicy.manualSelectionActions(
        .speaker,
        available: [.speaker, .receiver]
      ),
      [.clearPreferredInput, .speaker]
    )
    XCTAssertEqual(
      IOSAudioOutputPolicy.manualSelectionActions(
        .receiver,
        available: [.speaker, .receiver]
      ),
      [.preferInput(.receiver), .clearOverride]
    )
  }

  func testManualExternalCommandsClearSpeakerBeforePreferringTheDevice() {
    XCTAssertEqual(
      IOSAudioOutputPolicy.manualSelectionActions(
        .bluetooth,
        available: [.speaker, .receiver, .bluetooth]
      ),
      [.clearOverride, .preferInput(.bluetooth)]
    )
    XCTAssertEqual(
      IOSAudioOutputPolicy.manualSelectionActions(
        .wired,
        available: [.speaker, .receiver, .wired]
      ),
      [.clearOverride, .preferInput(.wired)]
    )
  }

  func testManualSelectionRejectsUnavailableAndNonselectableRoutes() {
    XCTAssertNil(
      IOSAudioOutputPolicy.manualSelectionActions(
        .bluetooth,
        available: [.speaker, .receiver]
      )
    )
    for route: IOSAudioOutputKind in [.airPlay, .other, .unknown] {
      XCTAssertNil(
        IOSAudioOutputPolicy.manualSelectionActions(
          route,
          available: [.speaker, .receiver, route]
        )
      )
    }
  }

  func testManualSelectionIsAppliedOnlyAfterActualRouteReadbackMatches() {
    XCTAssertEqual(
      IOSAudioOutputPolicy.manualSelectionResult(
        requested: .speaker,
        commandAccepted: true,
        active: .receiver
      ),
      .failed
    )
    XCTAssertEqual(
      IOSAudioOutputPolicy.manualSelectionResult(
        requested: .speaker,
        commandAccepted: true,
        active: .speaker
      ),
      .applied
    )
    XCTAssertEqual(
      IOSAudioOutputPolicy.manualSelectionResult(
        requested: .bluetooth,
        commandAccepted: false,
        active: .speaker
      ),
      .unavailable
    )
  }
}
