import Foundation

/// Owns the user-requested iOS output and resolves asynchronous route changes
/// against coarse, privacy-safe device classes.
final class IOSAudioOutputController {
  typealias TimeoutScheduler = (TimeInterval, @escaping () -> Void) -> (() -> Void)

  private enum PendingSelection {
    case manual(IOSAudioOutputKind, voiceProcessingActive: Bool)
    case automaticReset
  }

  private let session: IOSAudioOutputSession
  private let scheduleTimeout: TimeoutScheduler
  private let onAsyncUpdate: (String?) -> Void
  private var requestedOutput: IOSAudioOutputKind?
  private var selectionResult = IOSAudioOutputSelectionResult.automatic
  private var pendingSelection: PendingSelection?
  private var cancelPendingTimeout: (() -> Void)?

  init(
    session: IOSAudioOutputSession,
    scheduleTimeout: @escaping TimeoutScheduler = { _, _ in {} },
    onAsyncUpdate: @escaping (String?) -> Void = { _ in }
  ) {
    self.session = session
    self.scheduleTimeout = scheduleTimeout
    self.onAsyncUpdate = onAsyncUpdate
  }

  func stateMap(routeSelectionAvailable: Bool) -> [String: Any] {
    var available: [String] = []
    let selectable = IOSAudioOutputPolicy.selectableOutputs(
      from: session.availableOutputKinds,
      routeSelectionAvailable: routeSelectionAvailable
    )
    for route in selectable.map(\.publicRouteValue) {
      if !available.contains(route) { available.append(route) }
    }
    let volume: Any = session.systemOutputVolume.map { Double($0) } ?? NSNull()
    return [
      "active": session.outputKind.publicRouteValue,
      "available": available,
      "requested": requestedOutput?.publicRouteValue ?? NSNull(),
      "selectionResult": routeSelectionAvailable
        ? selectionResult.rawValue
        : IOSAudioOutputSelectionResult.unavailable.rawValue,
      "volumeControlStream": NSNull(),
      "volume": volume,
    ]
  }

  func deactivate() {
    clearPendingSelection()
    selectionResult = .unavailable
  }

  func activate() {
    if requestedOutput == nil, selectionResult == .unavailable {
      selectionResult = .automatic
    }
  }

  func applyPostStart(
    voiceProcessingActive: Bool,
    routeSelectionAvailable: Bool
  ) -> String? {
    guard routeSelectionAvailable else {
      deactivate()
      return nil
    }
    if let requestedOutput {
      let failure = applyRequestedOutput(
        requestedOutput,
        voiceProcessingActive: voiceProcessingActive
      )
      guard selectionResult == .unavailable else { return failure }
      return applyUnavailableRequestFallback(voiceProcessingActive: voiceProcessingActive)
        ?? failure
    }
    guard voiceProcessingActive else {
      selectionResult = .automatic
      return nil
    }
    let actions = IOSAudioOutputPolicy.postStartActions(
      currentOutput: session.outputKind,
      userSelection: nil
    )
    let failure = applyAutomaticActions(actions)
    selectionResult = failure == nil ? .automatic : .failed
    return failure
  }

  func handleRouteChange(
    reason: IOSAudioRouteChangeReason,
    voiceProcessingActive: Bool,
    routeSelectionAvailable: Bool,
    engineIsStarted: Bool
  ) -> String? {
    guard routeSelectionAvailable else {
      deactivate()
      return nil
    }

    if let pendingSelection {
      switch pendingSelection {
      case .manual(let route, _):
        if session.outputKind == route {
          clearPendingSelection()
          selectionResult = .applied
          return nil
        }
        guard session.availableOutputKinds.contains(route) else {
          clearPendingSelection()
          selectionResult = .unavailable
          return applyUnavailableRequestFallback(voiceProcessingActive: voiceProcessingActive)
        }
        return nil
      case .automaticReset:
        if session.outputKind.isExternal {
          clearPendingSelection()
          selectionResult = .automatic
          return nil
        }
        guard !hasAvailableExternalOutput else { return nil }
        return completeAutomaticReset(voiceProcessingActive: voiceProcessingActive)
      }
    }

    if let requestedOutput {
      selectionResult = IOSAudioOutputPolicy.manualSelectionResult(
        requested: requestedOutput,
        commandAccepted: session.availableOutputKinds.contains(requestedOutput),
        active: session.outputKind,
        routeChangeObserved: true
      )
    }

    guard engineIsStarted else { return nil }
    guard reason == .newDeviceAvailable || reason == .oldDeviceUnavailable else {
      return nil
    }

    if let requestedOutput {
      let failure = applyRequestedOutput(
        requestedOutput,
        voiceProcessingActive: voiceProcessingActive
      )
      if selectionResult == .unavailable {
        return applyUnavailableRequestFallback(voiceProcessingActive: voiceProcessingActive)
          ?? failure
      }
      return failure
    }

    guard voiceProcessingActive else { return nil }
    let actions = IOSAudioOutputPolicy.routeChangeActions(
      currentOutput: session.outputKind,
      userSelection: nil,
      reason: reason
    )
    let failure = applyAutomaticActions(actions)
    selectionResult = failure == nil ? .automatic : .failed
    return failure
  }

  func setRequestedOutput(
    _ rawValue: String?,
    voiceProcessingActive: Bool,
    routeSelectionAvailable: Bool
  ) -> String? {
    guard let rawValue else {
      requestedOutput = nil
      clearPendingSelection()
      guard routeSelectionAvailable else {
        selectionResult = .unavailable
        return nil
      }
      do {
        _ = try session.applyRouteSelectionActions(IOSAudioOutputPolicy.automaticResetActions)
      } catch {
        selectionResult = .failed
        return "automatic_route_failed"
      }

      guard voiceProcessingActive else {
        selectionResult = .automatic
        return nil
      }
      if session.outputKind.isExternal {
        selectionResult = .automatic
        return nil
      }
      if hasAvailableExternalOutput {
        beginPendingSelection(.automaticReset, timeout: 1)
        return nil
      }
      return completeAutomaticReset(voiceProcessingActive: voiceProcessingActive)
    }

    clearPendingSelection()
    guard let route = IOSAudioOutputKind(rawValue: rawValue) else {
      selectionResult = .unavailable
      return nil
    }
    requestedOutput = route
    guard route != .other, route != .unknown, route != .airPlay else {
      selectionResult = .unavailable
      return nil
    }
    guard routeSelectionAvailable else {
      selectionResult = .unavailable
      return nil
    }
    return applyRequestedOutput(route, voiceProcessingActive: voiceProcessingActive)
  }

  private func applyRequestedOutput(
    _ route: IOSAudioOutputKind,
    voiceProcessingActive: Bool
  ) -> String? {
    guard session.availableOutputKinds.contains(route) else {
      clearPendingSelection()
      selectionResult = .unavailable
      return nil
    }
    do {
      let accepted = try session.setOutput(route)
      selectionResult = IOSAudioOutputPolicy.manualSelectionResult(
        requested: route,
        commandAccepted: accepted,
        active: session.outputKind,
        routeChangeObserved: false
      )
      if selectionResult == .pending {
        beginPendingSelection(
          .manual(route, voiceProcessingActive: voiceProcessingActive),
          timeout: 4
        )
      }
      return nil
    } catch {
      clearPendingSelection()
      selectionResult = .failed
      return "requested_route_failed"
    }
  }

  private var hasAvailableExternalOutput: Bool {
    session.availableOutputKinds.contains(where: \.isExternal)
  }

  private func applyUnavailableRequestFallback(voiceProcessingActive: Bool) -> String? {
    let actions = IOSAudioOutputPolicy.unavailableRequestFallbackActions(
      currentOutput: session.outputKind,
      voiceProcessingActive: voiceProcessingActive
    )
    guard let failure = applyAutomaticActions(actions) else { return nil }
    selectionResult = .failed
    return failure
  }

  private func completeAutomaticReset(voiceProcessingActive: Bool) -> String? {
    clearPendingSelection()
    let actions = IOSAudioOutputPolicy.unavailableRequestFallbackActions(
      currentOutput: session.outputKind,
      voiceProcessingActive: voiceProcessingActive
    )
    let failure = applyAutomaticActions(actions)
    selectionResult = failure == nil ? .automatic : .failed
    return failure
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

  private func beginPendingSelection(_ pending: PendingSelection, timeout: TimeInterval) {
    clearPendingSelection()
    pendingSelection = pending
    selectionResult = .pending
    cancelPendingTimeout = scheduleTimeout(timeout) { [weak self] in
      self?.handlePendingTimeout()
    }
  }

  private func handlePendingTimeout() {
    guard let pendingSelection else { return }
    clearPendingSelection()
    let failure: String?
    switch pendingSelection {
    case .manual(let route, let voiceProcessingActive):
      selectionResult = IOSAudioOutputPolicy.manualSelectionResult(
        requested: route,
        commandAccepted: session.availableOutputKinds.contains(route),
        active: session.outputKind,
        routeChangeObserved: true
      )
      if selectionResult == .unavailable {
        failure = applyUnavailableRequestFallback(
          voiceProcessingActive: voiceProcessingActive
        )
      } else {
        failure = selectionResult == .failed ? "requested_route_timeout" : nil
      }
    case .automaticReset:
      failure = completeAutomaticReset(voiceProcessingActive: true)
    }
    onAsyncUpdate(failure)
  }

  private func clearPendingSelection() {
    pendingSelection = nil
    cancelPendingTimeout?()
    cancelPendingTimeout = nil
  }
}
