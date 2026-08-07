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

  func testAutomaticResetClearsBothManualRoutingControls() {
    XCTAssertEqual(
      IOSAudioOutputPolicy.automaticResetActions,
      [.clearPreferredInput, .clearOverride]
    )
  }

  func testUnavailableRetainedRequestFallsBackOnlyForVoiceProcessing() {
    XCTAssertEqual(
      IOSAudioOutputPolicy.unavailableRequestFallbackActions(
        currentOutput: .receiver,
        voiceProcessingActive: true
      ),
      [.speaker]
    )
    XCTAssertEqual(
      IOSAudioOutputPolicy.unavailableRequestFallbackActions(
        currentOutput: .bluetooth,
        voiceProcessingActive: true
      ),
      []
    )
    XCTAssertEqual(
      IOSAudioOutputPolicy.unavailableRequestFallbackActions(
        currentOutput: .receiver,
        voiceProcessingActive: false
      ),
      []
    )
  }

  func testAvailableRoutesContainOnlyCurrentlySelectableOutputs() {
    XCTAssertEqual(
      IOSAudioOutputPolicy.selectableOutputs(
        from: [.speaker, .receiver, .wired, .bluetooth, .airPlay, .other, .unknown],
        routeSelectionAvailable: true
      ),
      [.speaker, .receiver, .wired, .bluetooth]
    )
    XCTAssertEqual(
      IOSAudioOutputPolicy.selectableOutputs(
        from: [.speaker, .receiver, .bluetooth],
        routeSelectionAvailable: false
      ),
      []
    )
  }

  func testAcceptedManualSelectionStaysPendingUntilRouteChangeReadback() {
    XCTAssertEqual(
      IOSAudioOutputPolicy.manualSelectionResult(
        requested: .speaker,
        commandAccepted: true,
        active: .receiver,
        routeChangeObserved: false
      ),
      .pending
    )
    XCTAssertEqual(
      IOSAudioOutputPolicy.manualSelectionResult(
        requested: .speaker,
        commandAccepted: true,
        active: .speaker,
        routeChangeObserved: false
      ),
      .applied
    )
  }

  func testRouteChangeReadbackFinalizesManualSelection() {
    XCTAssertEqual(
      IOSAudioOutputPolicy.manualSelectionResult(
        requested: .speaker,
        commandAccepted: true,
        active: .receiver,
        routeChangeObserved: true
      ),
      .failed
    )
    XCTAssertEqual(
      IOSAudioOutputPolicy.manualSelectionResult(
        requested: .speaker,
        commandAccepted: true,
        active: .speaker,
        routeChangeObserved: true
      ),
      .applied
    )
    XCTAssertEqual(
      IOSAudioOutputPolicy.manualSelectionResult(
        requested: .bluetooth,
        commandAccepted: false,
        active: .speaker,
        routeChangeObserved: true
      ),
      .unavailable
    )
  }

  func testControllerFinalizesDelayedManualSelectionFromRouteReadback() {
    let session = FakeIOSAudioOutputSession(
      output: .speaker,
      available: [.speaker, .receiver, .bluetooth]
    )
    session.appliesSelectionImmediately = false
    var timeout: (() -> Void)?
    let controller = IOSAudioOutputController(
      session: session,
      scheduleTimeout: { _, action in
        timeout = action
        return { timeout = nil }
      }
    )

    XCTAssertNil(
      controller.setRequestedOutput(
        "bluetooth",
        voiceProcessingActive: true,
        routeSelectionAvailable: true
      )
    )
    XCTAssertEqual(
      controller.stateMap(routeSelectionAvailable: true)["selectionResult"] as? String, "pending")
    XCTAssertNotNil(timeout)

    XCTAssertNil(
      controller.handleRouteChange(
        reason: .override,
        voiceProcessingActive: true,
        routeSelectionAvailable: true,
        engineIsStarted: true
      )
    )
    XCTAssertEqual(
      controller.stateMap(routeSelectionAvailable: true)["selectionResult"] as? String, "pending")
    XCTAssertNotNil(timeout)

    session.outputKind = .bluetooth
    XCTAssertNil(
      controller.handleRouteChange(
        reason: .override,
        voiceProcessingActive: true,
        routeSelectionAvailable: true,
        engineIsStarted: true
      )
    )
    XCTAssertEqual(
      controller.stateMap(routeSelectionAvailable: true)["selectionResult"] as? String, "applied")
    XCTAssertNil(timeout)
  }

  func testControllerBoundsManualSelectionAndReportsTimeoutFailure() {
    let session = FakeIOSAudioOutputSession(
      output: .speaker,
      available: [.speaker, .receiver, .bluetooth]
    )
    session.appliesSelectionImmediately = false
    var timeout: (() -> Void)?
    var updates: [String?] = []
    let controller = IOSAudioOutputController(
      session: session,
      scheduleTimeout: { _, action in
        timeout = action
        return {}
      },
      onAsyncUpdate: { updates.append($0) }
    )

    _ = controller.setRequestedOutput(
      "bluetooth",
      voiceProcessingActive: true,
      routeSelectionAvailable: true
    )
    timeout?()

    XCTAssertEqual(
      controller.stateMap(routeSelectionAvailable: true)["selectionResult"] as? String, "failed")
    XCTAssertEqual(updates, ["requested_route_timeout"])
  }

  func testControllerAutomaticResetWaitsForAndPreservesExternalRoute() {
    let session = FakeIOSAudioOutputSession(
      output: .speaker,
      available: [.speaker, .receiver, .bluetooth]
    )
    var timeout: (() -> Void)?
    let controller = IOSAudioOutputController(
      session: session,
      scheduleTimeout: { _, action in
        timeout = action
        return { timeout = nil }
      }
    )

    _ = controller.setRequestedOutput(
      nil,
      voiceProcessingActive: true,
      routeSelectionAvailable: true
    )
    XCTAssertEqual(session.selectionActions, [IOSAudioOutputPolicy.automaticResetActions])
    XCTAssertEqual(
      controller.stateMap(routeSelectionAvailable: true)["selectionResult"] as? String, "pending")

    _ = controller.handleRouteChange(
      reason: .override,
      voiceProcessingActive: true,
      routeSelectionAvailable: true,
      engineIsStarted: true
    )

    XCTAssertEqual(session.overrideActions, [])
    XCTAssertEqual(
      controller.stateMap(routeSelectionAvailable: true)["selectionResult"] as? String, "pending")
    XCTAssertNotNil(timeout)

    session.outputKind = .bluetooth
    _ = controller.handleRouteChange(
      reason: .override,
      voiceProcessingActive: true,
      routeSelectionAvailable: true,
      engineIsStarted: true
    )

    XCTAssertEqual(session.overrideActions, [])
    XCTAssertEqual(
      controller.stateMap(routeSelectionAvailable: true)["selectionResult"] as? String, "automatic")
    XCTAssertNil(timeout)
  }

  func testControllerFallsBackWhenRetainedRouteIsUnavailableAtPostStart() {
    let session = FakeIOSAudioOutputSession(
      output: .bluetooth,
      available: [.speaker, .receiver, .bluetooth]
    )
    let controller = IOSAudioOutputController(session: session)
    _ = controller.setRequestedOutput(
      "bluetooth",
      voiceProcessingActive: true,
      routeSelectionAvailable: true
    )

    session.outputKind = .receiver
    session.availableOutputKinds = [.speaker, .receiver]
    XCTAssertNil(
      controller.applyPostStart(
        voiceProcessingActive: true,
        routeSelectionAvailable: true
      )
    )

    let state = controller.stateMap(routeSelectionAvailable: true)
    XCTAssertEqual(state["active"] as? String, "speaker")
    XCTAssertEqual(state["requested"] as? String, "bluetooth")
    XCTAssertEqual(state["selectionResult"] as? String, "unavailable")
  }

  func testControllerDeactivationAndOpaqueReadbackNeverAdvertiseSelection() {
    let session = FakeIOSAudioOutputSession(
      output: .other,
      available: [.speaker, .receiver, .other]
    )
    let controller = IOSAudioOutputController(session: session)
    controller.deactivate()

    let state = controller.stateMap(routeSelectionAvailable: false)
    XCTAssertEqual(state["active"] as? String, "other")
    XCTAssertEqual(state["available"] as? [String], [])
    XCTAssertEqual(state["selectionResult"] as? String, "unavailable")
  }

  func testControllerRetainsReadbackOnlyRequestWithoutApplyingIt() {
    let session = FakeIOSAudioOutputSession(
      output: .speaker,
      available: [.speaker, .receiver, .other]
    )
    let controller = IOSAudioOutputController(session: session)

    XCTAssertNil(
      controller.setRequestedOutput(
        "other",
        voiceProcessingActive: true,
        routeSelectionAvailable: true
      )
    )

    let state = controller.stateMap(routeSelectionAvailable: true)
    XCTAssertEqual(state["requested"] as? String, "other")
    XCTAssertEqual(state["selectionResult"] as? String, "unavailable")
    XCTAssertEqual(session.selectionActions, [])
    XCTAssertEqual(session.overrideActions, [])
  }
}

private final class FakeIOSAudioOutputSession: IOSAudioOutputSession {
  var outputKind: IOSAudioOutputKind
  var availableOutputKinds: [IOSAudioOutputKind]
  var systemOutputVolume: Float? = 0.5
  var acceptsSelection = true
  var appliesSelectionImmediately = true
  var selectionActions: [[IOSAudioRouteSelectionAction]] = []
  var overrideActions: [[IOSAudioRouteOverrideAction]] = []

  init(output: IOSAudioOutputKind, available: [IOSAudioOutputKind]) {
    outputKind = output
    availableOutputKinds = available
  }

  func setOutput(_ output: IOSAudioOutputKind) throws -> Bool {
    if acceptsSelection, appliesSelectionImmediately { outputKind = output }
    return acceptsSelection
  }

  func applyRouteSelectionActions(_ actions: [IOSAudioRouteSelectionAction]) throws -> Bool {
    selectionActions.append(actions)
    return true
  }

  func applyRouteOverrideActions(_ actions: [IOSAudioRouteOverrideAction]) throws {
    overrideActions.append(actions)
    if actions.contains(.speaker) { outputKind = .speaker }
  }
}
