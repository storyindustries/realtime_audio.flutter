import AVFoundation
import Foundation

#if os(iOS)
  import Flutter
#else
  import FlutterMacOS
#endif

struct ChunkEntry {
  var id: String
  var buffer: AVAudioPCMBuffer
  var offset: UInt32
}
class RealtimeAudio: NSObject {
  let id: String
  let arguments: CreateArguments
  let methodChannel: FlutterMethodChannel
  private let nativeQueue: DispatchQueue

  private let recorderSampleRate: Double
  private let recorderFormat: AVAudioFormat
  private var recorderConverter: AVAudioConverter?
  private let recorderPreferredBus: AVAudioNodeBus = 0
  private var recorderActiveBus: AVAudioNodeBus?
  private var recorderTapInstalled = false
  private var recorderHasPermission: Bool {
    RealtimeAudioPlugin.getRecordPermission() == .granted
  }

  private let playerSampleRate: Double
  private let playerInputFormat: AVAudioFormat
  private var playerOutputFormat: AVAudioFormat!

  private let audioSession = RealtimeAudioSession()
  private let audioEngine = AVAudioEngine()
  private let audioMixerNode = AVAudioMixerNode()
  private var audioPlayerNode: ChunkAudioPlayerNode!
  private var audioBackgroundNode: LoopAudioPlayerNode?
  private var audioCaptureStrategy: IOSAudioCaptureStrategy = .none
  /// Whether this engine has ever turned the shared VoiceProcessingIO unit on.
  /// Gates `AVAudioEngine.inputNode` access, which is only legal while the
  /// session is record-capable — see `IOSVoiceProcessingTransition`.
  private var voiceProcessingIsApplied = false

  private var playerVolumeTimer: DispatchSourceTimer?
  private var playerProgressTimer: DispatchSourceTimer?
  private var state: RealtimeAudioState = .init(
    isPlaying: false,
    isPaused: false,
    duration: 0,
    durationTotal: 0,
    chunkCount: 0,
    renderClockMs: 0,
    isRendering: false
  )

  /// Whether the mic capture path has delivered its first real buffer since the
  /// tap was (re)installed — bubbles' `captureProvenLive`. Read back via
  /// `getEchoCancellationState`. Monotonic false→true within a capture session.
  private var captureProvenLive = false

  /// Bumped every time capture liveness is invalidated. A tap callback that was
  /// already in flight when its tap was torn down carries the old generation,
  /// so it can never resurrect liveness for the capture path that replaced it.
  private var captureGeneration: UInt64 = 0

  /// Mutable override for recorder state — allows dynamic toggling without
  /// disposing the engine. `nil` means use `arguments.recorderEnabled`.
  private var _recorderEnabledOverride: Bool?
  /// Transition-only intent. Native rebuilds can observe the target state
  /// without publishing it as committed until every throwing operation passes.
  private var pendingRecorderEnabled: Bool?
  private var recorderStateIsUnknown = false
  var isRecorderEnabled: Bool {
    pendingRecorderEnabled ?? _recorderEnabledOverride ?? arguments.recorderEnabled
  }

  #if os(iOS)
    /// WebRTC Audio Processing Module for software echo cancellation, noise
    /// suppression, and AGC. Used instead of Apple's voice processing when
    /// the `voiceProcessing` argument is true.
    private var webRtcApm: WebRtcApm?

  #endif

  private var shouldBeStarted = false
  private var shouldBePaused = false
  private var configurationRecoveryIsRunning = false
  private var isDisposed = false
  private var isDeinitialized = false
  private var observersAttached = false

  init(
    id: String,
    arguments: CreateArguments,
    methodChannel: FlutterMethodChannel,
    nativeQueue: DispatchQueue
  ) throws {
    self.id = id
    self.arguments = arguments
    self.methodChannel = methodChannel
    self.nativeQueue = nativeQueue

    self.recorderSampleRate = arguments.recorderSampleRate
    self.recorderFormat = getAudioFormat(.pcmFormatInt16, recorderSampleRate, 1)!

    self.playerSampleRate = arguments.playerSampleRate
    self.playerInputFormat = getAudioFormat(.pcmFormatInt16, playerSampleRate, 1)!

    super.init()

    //

    // Initialize WebRTC APM for noise suppression and AGC only (no AEC).
    // Apple platform audio handles echo cancellation at the hardware level.
    #if os(iOS)
      if arguments.voiceProcessing && isRecorderEnabled {
        initializeApm()
      }
    #endif

    // The route's sample rate is only authoritative after activation. Creating
    // the resampling nodes before this point can lock them to the stale idle
    // route rate and introduce a second conversion boundary on call start.
    try audioSession.configure(
      recorderEnabled: isRecorderEnabled,
      voiceProcessingRequested: arguments.voiceProcessing
    )
    try audioSession.activate()
    audioCaptureStrategy = negotiateAudioCaptureStrategy(recorderEnabled: isRecorderEnabled)
    try createPlayerNodesForCurrentRoute()
    attachObservers()
    audioPlayerNode.setListener(self)
    installMethodCallHandler()
    try attachNodes()

    changeVolume()

    try installTap()
    audioEngine.prepare()
  }

  private func createPlayerNodesForCurrentRoute() throws {
    let routeSampleRate = audioSession.sampleRate ?? playerSampleRate
    guard let outputFormat = getAudioFormat(.pcmFormatFloat32, routeSampleRate, 1) else {
      throw TextError("Failed to create player output format.")
    }

    playerOutputFormat = outputFormat
    audioPlayerNode = try ChunkAudioPlayerNode(
      inputFormat: playerInputFormat,
      outputFormat: outputFormat,
      callbackQueue: nativeQueue
    )
    audioBackgroundNode = arguments.backgroundEnabled
      ? try LoopAudioPlayerNode(
        inputFormat: playerInputFormat,
        outputFormat: outputFormat,
        callbackQueue: nativeQueue
      )
      : nil
  }

  #if os(iOS)
    /// Whether the WebRTC APM is active (NS + AGC processing).
    private var webRtcApmActive: Bool { webRtcApm?.isAvailable == true }

    /// Initialize the WebRTC APM for noise suppression and AGC only.
    /// AEC is disabled — the selected Apple platform path handles echo
    /// cancellation at the hardware level with per-device acoustic models.
    private func initializeApm() {
      let apm = WebRtcApm(
        captureSampleRate: Int(recorderSampleRate),
        renderSampleRate: Int(playerSampleRate),
        aecEnabled: false,
        nsEnabled: true,
        agcEnabled: true
      )
      guard apm.isAvailable else { return }
      webRtcApm = apm
      invokeFlutter(
        "echo",
        arguments: "WebRTC APM initialized (NS + AGC only, Apple platform audio handles AEC)"
      )
    }
  #endif

  private func attachNodes() throws {
    // Might need this later.
    let equalizer = AVAudioUnitEQ(numberOfBands: 2)
    equalizer.bypass = true
    audioBackgroundNode?.volume = Float(arguments.backgroundVolume)

    audioEngine.attach(audioMixerNode)
    audioEngine.attach(audioPlayerNode)
    if let audioBackgroundNode { audioEngine.attach(audioBackgroundNode) }
    audioEngine.attach(equalizer)

    audioEngine.connect(audioPlayerNode, to: equalizer, format: playerOutputFormat)
    audioEngine.connect(equalizer, to: audioMixerNode, fromBus: 0, toBus: 0, format: playerOutputFormat)
    if let audioBackgroundNode {
      audioEngine.connect(audioBackgroundNode, to: audioMixerNode, fromBus: 0, toBus: 1, format: playerOutputFormat)
    }

    audioEngine.connect(audioMixerNode, to: audioEngine.mainMixerNode, format: nil)
    audioEngine.connect(audioEngine.mainMixerNode, to: audioEngine.outputNode, format: nil)

    try applyVoiceProcessingStrategy()
  }

  private func applyVoiceProcessingStrategy() throws {
    #if os(iOS)
      let transition = IOSVoiceProcessingPolicy.transition(
        target: audioCaptureStrategy,
        isApplied: voiceProcessingIsApplied
      )
      guard transition != .leaveUntouched else { return }

      let shouldEnable = transition == .enable
      if audioEngine.inputNode.isVoiceProcessingEnabled != shouldEnable {
        // VoiceProcessingIO is one shared I/O unit: enabling either node
        // enables both. Input-only avoids the output-node initialization path
        // that produced silent graphs and main-thread stalls on device.
        try audioEngine.inputNode.setVoiceProcessingEnabled(shouldEnable)
      }
      voiceProcessingIsApplied = shouldEnable
      if shouldEnable {
        audioEngine.inputNode.isVoiceProcessingAGCEnabled = false
      }
    #endif
  }

  private func voiceProcessingTransitionPrecedesSessionReconfiguration() -> Bool {
    #if os(iOS)
      return IOSVoiceProcessingPolicy.transition(
        target: audioCaptureStrategy,
        isApplied: voiceProcessingIsApplied
      ).mustPrecedeSessionReconfiguration
    #else
      return false
    #endif
  }

  private func negotiateAudioCaptureStrategy(recorderEnabled: Bool) -> IOSAudioCaptureStrategy {
    #if os(iOS)
      return IOSAudioCapturePolicy.strategy(
        recorderEnabled: recorderEnabled,
        voiceProcessingRequested: arguments.voiceProcessing
      )
    #else
      return .none
    #endif
  }

  private func attachObservers() {
    guard !observersAttached else { return }
    observersAttached = true
    #if os(iOS)
      audioSession.instance.addObserver(self, forKeyPath: "outputVolume", options: .new, context: nil)
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleAudioRouteChange),
        name: AVAudioSession.routeChangeNotification,
        object: audioSession.instance
      )
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleAudioSessionInterruption),
        name: AVAudioSession.interruptionNotification,
        object: audioSession.instance
      )
    #endif
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioEngineConfigurationChange),
      name: .AVAudioEngineConfigurationChange,
      object: audioEngine
    )
  }

  private func detachObservers() {
    guard observersAttached else { return }
    observersAttached = false
    NotificationCenter.default.removeObserver(self)
    #if os(iOS)
      audioSession.instance.removeObserver(self, forKeyPath: "outputVolume")
    #endif
  }

  /// Flutter's binary messenger owns handler registration on the platform
  /// task runner even when engine construction itself runs on a background
  /// task queue.
  private func installMethodCallHandler() {
    let install = { [self] in
      methodChannel.setMethodCallHandler { [weak self] call, result in
        guard let self else {
          result(FlutterError(code: "INTERNAL", message: "Audio engine disposed.", details: nil))
          return
        }
        let resultOnPlatformThread: FlutterResult = { value in
          if Thread.isMainThread {
            result(value)
          } else {
            DispatchQueue.main.async {
              result(value)
            }
          }
        }
        nativeQueue.async { [weak self] in
          guard let self, !isDisposed else {
            resultOnPlatformThread(
              FlutterError(code: "INTERNAL", message: "Audio engine disposed.", details: nil)
            )
            return
          }
          handleFlutterMethod(call: call, result: resultOnPlatformThread)
        }
      }
    }
    if Thread.isMainThread {
      install()
    } else {
      DispatchQueue.main.sync(execute: install)
    }
  }

  private func clearMethodCallHandler() {
    let clear = { [methodChannel] in
      methodChannel.setMethodCallHandler(nil)
    }
    if Thread.isMainThread {
      clear()
    } else {
      DispatchQueue.main.sync(execute: clear)
    }
  }

  @objc private func handleAudioEngineConfigurationChange(notification: NSNotification) {
    nativeQueue.async { [weak self] in
      self?.recoverAfterAudioConfigurationChange()
    }
  }

  #if os(iOS)
    @objc private func handleAudioRouteChange(notification: NSNotification) {
      nativeQueue.async { [weak self] in
        guard let self, !isDisposed else { return }
        audioCaptureStrategy = negotiateAudioCaptureStrategy(recorderEnabled: isRecorderEnabled)
      }
    }

    @objc private func handleAudioSessionInterruption(notification: NSNotification) {
      guard
        let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
        AVAudioSession.InterruptionType(rawValue: rawType) == .ended
      else {
        return
      }
      nativeQueue.async { [weak self] in
        guard let self, !isDisposed else { return }
        do {
          try audioSession.activate()
          recoverAfterAudioConfigurationChange()
        } catch {
          notifyEngineHealth(
            type: "interruption_recovery_failed",
            engineWasRunning: audioEngine.isRunning,
            message: "session_activation_failed"
          )
        }
      }
    }
  #endif

  private func recoverAfterAudioConfigurationChange() {
    guard !isDisposed else { return }
    audioCaptureStrategy = negotiateAudioCaptureStrategy(recorderEnabled: isRecorderEnabled)
    let engineWasRunning = audioEngine.isRunning
    let decision = AudioEngineConfigurationRecoveryPolicy.decide(
      shouldBeStarted: shouldBeStarted,
      shouldBePaused: shouldBePaused,
      engineIsRunning: engineWasRunning,
      recoveryIsRunning: configurationRecoveryIsRunning
    )

    switch decision {
    case .ignoreInactiveEngine, .ignoreRecoveryInProgress:
      return
    case .ignoreHealthyEngine:
      notifyEngineHealth(
        type: "configuration_change_ignored_healthy",
        engineWasRunning: engineWasRunning
      )
    case .restartStoppedEnginePreservingPlayback:
      configurationRecoveryIsRunning = true
      notifyEngineHealth(
        type: "configuration_change_recovery_started",
        engineWasRunning: engineWasRunning
      )
      defer { configurationRecoveryIsRunning = false }

      do {
        try recoverStoppedEnginePreservingPlayback()
        notifyEngineHealth(
          type: "configuration_change_recovered",
          engineWasRunning: engineWasRunning
        )
      } catch {
        notifyEngineHealth(
          type: "configuration_change_recovery_failed",
          engineWasRunning: engineWasRunning,
          message: "recovery_failed"
        )
      }
    }
  }

  private func notifyEngineHealth(
    type: String,
    engineWasRunning: Bool,
    message: String? = nil,
    outputRoute: String? = nil,
    outputSampleRate: Int? = nil
  ) {
    var event: [String: Any] = [
      "type": type,
      "engineWasRunning": engineWasRunning,
      "queuedChunkCount": audioPlayerNode.queue.count,
    ]
    if let message { event["message"] = message }
    if let outputRoute { event["outputRoute"] = outputRoute }
    if let outputSampleRate { event["outputSampleRate"] = outputSampleRate }
    invokeFlutter("audioEngineHealth", arguments: event)
  }

  /// Rebuild only the capture tap after a system-driven engine stop. Calling
  /// `stop()` or `reset()` here would discard `AVAudioPlayerNode`'s scheduled
  /// buffers and cut the current utterance.
  private func recoverStoppedEnginePreservingPlayback() throws {
    try AudioEngineConfigurationRecovery.recoverStoppedEngine(
      reinstallCapture: { try installTap() },
      startEngine: { try audioEngine.start() },
      removeCaptureAfterFailure: {
        removeRecorderTap()
      },
      resumePreservedPlayback: {
        playBackground()
        AudioEngineConfigurationRecovery.resumePreservedPlayback(
          shouldRestart: true,
          shouldBePaused: shouldBePaused,
          hasQueuedAudio: !audioPlayerNode.queue.isEmpty,
          play: {
            changeVolume()
            audioPlayerNode.play()
            attachTimers()
            notifyPlayerState(isPaused: false)
          }
        )
      }
    )
  }

  private func changeVolume() {
    if !isRecorderEnabled { return }
    #if os(iOS)
      audioEngine.mainMixerNode.outputVolume = audioSession.instance.outputVolume
    #endif
  }

  deinit {
    isDeinitialized = true
    guard !isDisposed else { return }

    detachObservers()
    #if os(iOS)
      removeRecorderTap()
      webRtcApm?.release()
      webRtcApm = nil
    #endif

    clearMethodCallHandler()
    detachTimers()
    recorderConverter?.reset()
    recorderConverter = nil
    // Initialization can fail at AVAudioSession activation (notably `!pri`)
    // before player nodes exist. Never dereference the IUO during partial-init
    // cleanup; only the bare engine and session need releasing on that path.
    if audioPlayerNode != nil {
      try? stop()
    } else {
      audioEngine.stop()
    }
    try? audioSession.deactivate()
  }

  func dispose() throws {
    guard !isDisposed else { return }
    isDisposed = true
    detachObservers()

    clearMethodCallHandler()
    detachTimers()
    // Stop render callbacks before releasing their capture processor. Removing
    // a live tap first forces a second graph reconfiguration and can wedge
    // simulator/device teardown behind CoreAudio's reconfiguration timeout.
    try stop()
    removeRecorderTap()
    #if os(iOS)
      webRtcApm?.release()
      webRtcApm = nil
    #endif
    try audioSession.deactivate()
  }

  override func observeValue(
    forKeyPath keyPath: String?,
    of object: Any?,
    change: [NSKeyValueChangeKey: Any]?,
    context: UnsafeMutableRawPointer?
  ) {
    guard keyPath == "outputVolume" else { return }
    nativeQueue.async { [weak self] in
      guard let self, !isDisposed else { return }
      #if os(iOS)
        if audioEngine.mainMixerNode.outputVolume != audioSession.instance.outputVolume {
          changeVolume()
          invokeFlutter(
            "echo",
            arguments: "Volume changing to \(audioSession.instance.outputVolume)"
          )
        }
      #endif
    }
  }

  private func getRecorderConverter(_ from: AVAudioFormat, _ to: AVAudioFormat) throws -> AVAudioConverter {
    guard let converter = AVAudioConverter(from: from, to: to) else {
      throw TextError("Failed to create an AVAudioConverter.")
    }
    converter.sampleRateConverterQuality = .max
    recorderConverter = converter
    return converter
  }

  private func attachTimers() {
    if playerProgressTimer == nil {
      let timer = DispatchSource.makeTimerSource(queue: nativeQueue)
      timer.schedule(
        deadline: .now() + .milliseconds(arguments.playerProgressInterval),
        repeating: .milliseconds(arguments.playerProgressInterval)
      )
      timer.setEventHandler { [weak self] in self?.notifyPlayerProgress() }
      playerProgressTimer = timer
      timer.resume()
    }

    if playerVolumeTimer == nil {
      let timer = DispatchSource.makeTimerSource(queue: nativeQueue)
      timer.schedule(
        deadline: .now() + .milliseconds(arguments.playerVolumeInterval),
        repeating: .milliseconds(arguments.playerVolumeInterval)
      )
      timer.setEventHandler { [weak self] in self?.notifyPlayerVolume() }
      playerVolumeTimer = timer
      timer.resume()
    }
  }

  private func detachTimers() {
    playerVolumeTimer?.setEventHandler {}
    playerVolumeTimer?.cancel()
    playerVolumeTimer = nil
    playerProgressTimer?.setEventHandler {}
    playerProgressTimer?.cancel()
    playerProgressTimer = nil
  }

  private func notifyState() {
    if isDisposed || isDeinitialized { return }
    guard let json = try? state.toJsonMap() else { return }
    invokeFlutter("state", arguments: json)
  }

  private func notifyPlayerProgress() {
    if isDisposed || isDeinitialized { return }

    var duration: Int = 0
    var durationTotal: Int = 0

    if let lastTime = audioPlayerNode.lastRenderTime,
      let time = audioPlayerNode.playerTime(forNodeTime: lastTime)
    {
      let sampleTimeDouble = Double(time.sampleTime)
      let secondsTotal = Double(audioPlayerNode.totalSampleTime) / time.sampleRate
      let seconds = sampleTimeDouble / time.sampleRate

      duration = max(0, Int((seconds * 1000).rounded()))
      durationTotal = max(0, Int((secondsTotal * 1000).rounded()))
    }

    let renderClockMs = audioPlayerNode.lifetimeRenderClockMs
    let isRendering = effectiveIsRendering()

    state.duration = duration
    state.durationTotal = durationTotal
    state.renderClockMs = renderClockMs
    state.isRendering = isRendering
    notifyState()
  }

  private func notifyPlayerState(
    isPaused: Bool?
  ) {
    if isDisposed || isDeinitialized { return }
    state.chunkCount = audioPlayerNode.queue.count
    state.isPlaying = audioPlayerNode.isPlaying
    if let isPaused { state.isPaused = isPaused }
    state.renderClockMs = audioPlayerNode.lifetimeRenderClockMs
    state.isRendering = effectiveIsRendering()
    notifyState()
  }

  private func notifyPlayerVolume() {
    if isDisposed || isDeinitialized { return }

    var volume: Float = -96.0

    if let lastTime = audioPlayerNode.lastRenderTime,
      let time = audioPlayerNode.playerTime(forNodeTime: lastTime)
    {
      let sampleTime = Int(time.sampleTime)
      let dbfs = audioPlayerNode.queue.getDbfs(sampleTime, Int(time.sampleRate * 0.3))

      if let dbfs { volume = dbfs }
    }

    invokeFlutter("playerVolume", arguments: volume)
  }

  func notifyRecorderVolume(_ volume: Float? = nil) {
    invokeFlutter("recorderVolume", arguments: volume ?? -96.0)
  }

  private func invokeFlutter(_ method: String, arguments: Any? = nil) {
    guard !isDisposed, !isDeinitialized else { return }
    DispatchQueue.main.async { [methodChannel] in
      methodChannel.invokeMethod(method, arguments: arguments)
    }
  }

  /// Effective render state: the raw node signal (outstanding buffers or
  /// hangover) gated by the engine's paused state (a paused engine is silent).
  private func effectiveIsRendering() -> Bool {
    !state.isPaused && audioPlayerNode.isRenderingPlaybackRaw
  }

  /// Snapshot of the three call-lifetime playback counters + render state — see
  /// `ChunkAudioPlayerNode`.
  private func playbackClockMap() -> [String: Any] {
    return [
      "renderClockMs": audioPlayerNode.lifetimeRenderClockMs,
      "renderedMs": audioPlayerNode.lifetimeRenderedMs,
      "scheduledMs": audioPlayerNode.lifetimeScheduledMs,
      "isRendering": effectiveIsRendering(),
    ]
  }

  /// Live read-back of the selected AEC path.
  private func echoCancellationStateMap() -> [String: Any] {
    var nativeEnabled = false
    var mechanism = RealtimeAudioEchoCancellationMechanism.none

    #if os(iOS)
      if isRecorderEnabled && arguments.voiceProcessing {
        switch audioCaptureStrategy {
        case .inputVoiceProcessing:
          nativeEnabled = audioEngine.inputNode.isVoiceProcessingEnabled
        case .none:
          nativeEnabled = false
        }
        if nativeEnabled {
          mechanism = .platformAec
        }
      }
    #endif

    return [
      "requested": arguments.voiceProcessing,
      "nativeEnabled": nativeEnabled,
      "mechanism": mechanism.rawValue,
      "captureProvenLive": captureProvenLive,
    ]
  }
}

extension RealtimeAudio {
  private func handleFlutterMethod(call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      try handleFlutterMethodSafe(call: call, result: result)
    } catch {
      result(realtimeAudioFlutterError(error))
    }
  }

  private func handleFlutterMethodSafe(call: FlutterMethodCall, result: @escaping FlutterResult) throws {
    var value: Any? = true

    switch call.method {
    case "queue":
      guard let arguments = call.arguments as? [String: Any] else {
        throw TextError("Missing arguments for \(call.method)")
      }
      guard let id = arguments["id"] as? String else { throw TextError("Missing id for: \(call.method).") }
      guard let data = arguments["data"] as? FlutterStandardTypedData else {
        throw TextError("Missing data for: \(call.method).")
      }

      try queueAudio(id, [UInt8](data.data))
      break
    case "clearQueue":
      // Read the chunk cut position BEFORE stopping; stopAudio() then folds the
      // render clock, so the returned `clock` carries the folded lifetime values
      // (device truth up to the barge cut).
      let chunk = audioPlayerNode.getCurrentChunkProps()
      stopAudio()
      value = ["chunk": chunk as Any, "clock": playbackClockMap()]
      break
    case "getPlayerPlayedDuration":
      value = playbackClockMap()
      break
    case "repairPlaybackAccounting":
      guard let arguments = call.arguments as? [String: Any] else {
        throw TextError("Missing arguments for \(call.method)")
      }
      guard let expectedScheduledMs = arguments["expectedScheduledMs"] as? Int else {
        throw TextError("Missing expectedScheduledMs for: \(call.method).")
      }
      let outcome = audioPlayerNode.repairPlaybackAccounting(expectedScheduledMs: expectedScheduledMs)
      notifyPlayerState(isPaused: nil)
      value = [
        "repaired": outcome == .repaired,
        "reason": outcome.rawValue,
        "clock": playbackClockMap(),
      ]
      break
    case "recoverWedgedPlayback":
      value = recoverWedgedPlaybackMap()
      break
    case "getEchoCancellationState":
      value = echoCancellationStateMap()
      break
    //
    case "start":
      try start()
      break
    case "pause":
      try pause()
      break
    case "resume":
      try resume()
      break
    case "stop":
      try stop()
      break
    //
    case "playBackground":
      guard let arguments = call.arguments as? [String: Any] else {
        throw TextError("Missing arguments for \(call.method)")
      }

      guard let id = arguments["id"] as? String else { throw TextError("Missing id for: \(call.method).") }
      guard let loop = (arguments["loop"] as? Bool) else { throw TextError("Missing loop for: \(call.method).") }
      guard let data = arguments["data"] as? FlutterStandardTypedData else {
        throw TextError("Missing data for: \(call.method).")
      }

      try queueBackground(id, [UInt8](data.data), loop: loop)
      break
    case "stopBackground":
      stopBackground()
      break
    //
    case "setRecorderEnabled":
      guard let arguments = call.arguments as? [String: Any] else {
        throw TextError("Missing arguments for \(call.method)")
      }
      guard let enabled = arguments["enabled"] as? Bool else {
        throw TextError("Missing 'enabled' for: \(call.method).")
      }
      try setRecorderEnabled(enabled)
      break
    //
    default:
      value = nil
      break  // Do nothing
    }

    if let value {
      result(value)
    } else {
      result(FlutterMethodNotImplemented)
    }
  }
}

extension RealtimeAudio {
  private func recoverWedgedPlaybackMap() -> [String: Any] {
    guard shouldBeStarted, !shouldBePaused else {
      return [
        "recovered": false,
        "message": "Audio engine is not actively started.",
        "clock": playbackClockMap(),
      ]
    }

    // A true wedge is destructive by definition: the independent render clock
    // is frozen and scheduled audio cannot progress. Fold the clock and discard
    // the stranded player queue before restoring readiness.
    let recoveryDecision = PlaybackWedgeRecoveryPolicy.decide(engineIsRunning: audioEngine.isRunning)
    stopAudio()
    if recoveryDecision == .discardPlayerAndRestartEngine {
      audioEngine.prepare()
      do {
        try audioEngine.start()
      } catch {
        return [
          "recovered": false,
          "message": error.localizedDescription,
          "clock": playbackClockMap(),
        ]
      }
    }

    return [
      "recovered": audioEngine.isRunning,
      "clock": playbackClockMap(),
    ]
  }
}

// Player extension.
extension RealtimeAudio: ChunkAudioEventListener {
  func onChunkQueued(_ id: String) { invokeFlutter("chunkQueued", arguments: id) }
  func onChunkPlayed(_ id: String) { invokeFlutter("chunkPlayed", arguments: id) }
  func onChunkQueueStarted(_ id: String) { invokeFlutter("chunkQueueStarted", arguments: id) }
  func onChunkQueueEnded() {
    notifyEngineHealth(
      type: "playback_queue_drained",
      engineWasRunning: audioEngine.isRunning,
      outputRoute: audioSession.outputRouteClass,
      outputSampleRate: Int((audioSession.sampleRate ?? playerSampleRate).rounded())
    )
    stopAudio()
  }

  private func queueAudio(_ id: String, _ data: [UInt8]) throws {
    if data.isEmpty { return }

    // No processRender — APM handles NS + AGC only, Apple VP handles AEC.

    try audioPlayerNode.queue(id, data)
    if !state.isPaused { playAudio() }
  }

  private func playAudio() {
    if shouldBePaused { return }
    if !audioEngine.isRunning { return }
    if audioPlayerNode.queue.isEmpty { return }
    if !audioPlayerNode.isPlaying {
      changeVolume()
      audioPlayerNode.play()
      attachTimers()
      notifyPlayerState(isPaused: false)
    }
  }

  private func pauseAudio() {
    if !audioEngine.isRunning { return }
    if !audioPlayerNode.isPlaying { return }
    audioPlayerNode.pause()
    detachTimers()
    notifyPlayerState(isPaused: true)
  }

  private func stopAudio() {
    detachTimers()
    audioPlayerNode.stop()

    notifyPlayerState(isPaused: false)
    notifyPlayerProgress()
    notifyPlayerVolume()
  }
}

// Recorder extension.
extension RealtimeAudio {
  private func installTap() throws {
    if !isRecorderEnabled { return }

    // New capture session — capture liveness is unproven until the first buffer.
    let generation = invalidateCaptureLiveness()
    removeRecorderTap()

    let input = audioEngine.inputNode
    let inputFormat = input.inputFormat(forBus: recorderPreferredBus)
    let ratio: Float = Float(inputFormat.sampleRate) / Float(recorderFormat.sampleRate)
    let converter = try getRecorderConverter(inputFormat, recorderFormat)
    let bufferSize = AVAudioFrameCount(inputFormat.sampleRate * Double(arguments.recorderChunkInterval) / 1000)
    var hasReportedLiveBuffer = false

    input.installTap(
      onBus: recorderPreferredBus,
      bufferSize: bufferSize,
      format: inputFormat
    ) { [weak self] (buffer, time) -> Void in
      guard let self else { return }
      if self.shouldBePaused { return }

      // Keep engine state confined to nativeQueue. AVAudioEngine invokes this
      // closure on its realtime render thread.
      if buffer.frameLength > 0, !hasReportedLiveBuffer {
        hasReportedLiveBuffer = true
        self.nativeQueue.async { [weak self] in
          guard let self, !isDisposed, generation == captureGeneration else { return }
          captureProvenLive = true
        }
      }

      let inputCallback: AVAudioConverterInputBlock = { inNumPackets, outStatus in
        outStatus.pointee = .haveData
        return buffer
      }

      let buffer = AVAudioPCMBuffer(
        pcmFormat: self.recorderFormat,
        frameCapacity: UInt32(Float(buffer.frameCapacity) / ratio)
      )!

      var error: NSError?
      let status = converter.convert(to: buffer, error: &error, withInputFrom: inputCallback)

      if let error {
        DispatchQueue.main.async {
          self.methodChannel.invokeMethod("recorderError", arguments: error.localizedDescription)
        }
      }

      if self.recorderFormat.commonFormat == AVAudioCommonFormat.pcmFormatInt16 && status == .haveData {
        self.handleRecorderData(buffer)
      }
    }
    recorderTapInstalled = true
  }

  /// Reset capture liveness and return the token that identifies the new
  /// capture path. Only a callback carrying this token may prove it live.
  @discardableResult
  private func invalidateCaptureLiveness() -> UInt64 {
    captureProvenLive = false
    captureGeneration &+= 1
    return captureGeneration
  }

  private func removeRecorderTap() {
    guard recorderTapInstalled else { return }
    audioEngine.inputNode.removeTap(onBus: recorderPreferredBus)
    recorderTapInstalled = false
  }

  // No output tap needed — APM handles NS + AGC only, not AEC.
  // The selected Apple platform path handles echo cancellation at the hardware level.

  private func handleRecorderData(_ buffer: AVAudioPCMBuffer) {
    // Convert buffer to UInt8 list.
    let srcLeft = buffer.int16ChannelData![0]
    let bytesPerFrame = buffer.format.streamDescription.pointee.mBytesPerFrame
    let numBytes = Int(bytesPerFrame * buffer.frameLength)

    var data = [UInt8](repeating: 0, count: numBytes)

    srcLeft.withMemoryRebound(to: UInt8.self, capacity: numBytes) { srcByteData in
      data.withUnsafeMutableBufferPointer {
        $0.baseAddress!.initialize(from: srcByteData, count: numBytes)
      }
    }

    // Process captured audio through WebRTC APM (noise suppression + AGC).
    #if os(iOS)
      if let apm = webRtcApm {
        data.withUnsafeMutableBufferPointer { ptr in
          ptr.baseAddress!.withMemoryRebound(to: Int8.self, capacity: numBytes) { int8Ptr in
            apm.processCapture(int8Ptr, length: numBytes)
          }
        }
      }
    #endif

    // Send the list to Flutter.
    let flutterData = FlutterStandardTypedData(bytes: NSData(bytes: data, length: data.count) as Data)
    let volume = [buffer].getDbfs(0, Int(buffer.frameLength))

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      methodChannel.invokeMethod("recorderData", arguments: flutterData)
      methodChannel.invokeMethod("recorderVolume", arguments: volume)
    }
  }
}

extension RealtimeAudio {
  private func queueBackground(_ id: String, _ data: [UInt8], loop: Bool) throws {
    guard let audioBackgroundNode else { return }
    try audioBackgroundNode.queue(id, data, loop: loop)
    playBackground()
  }

  private func playBackground() {
    guard let audioBackgroundNode else { return }
    if !audioEngine.isRunning { return }
    if audioBackgroundNode.data?.isEmpty != false { return }
    changeVolume()
    audioBackgroundNode.play()
  }

  private func pauseBackground() {
    guard let audioBackgroundNode else { return }
    audioBackgroundNode.pause()
  }

  private func stopBackground(isRestart: Bool = false) {
    guard let audioBackgroundNode else { return }
    audioBackgroundNode.stop(isRestart: isRestart)
  }
}

extension RealtimeAudio {
  private func start() throws {
    try audioEngine.start()
    shouldBeStarted = true
    playBackground()
    playAudio()
  }

  private func pause() throws {
    shouldBePaused = true
    pauseBackground()
    pauseAudio()
    audioEngine.pause()
  }

  private func resume() throws {
    try audioEngine.start()
    shouldBePaused = false
    playBackground()
    playAudio()
  }

  private func stop() throws {
    shouldBeStarted = false
    stopBackground()
    stopAudio()
    notifyRecorderVolume()
    audioEngine.stop()
  }

  /// Dynamically toggle the recorder (and voice processing) without
  /// disposing the engine. Triggers an internal restart to reconfigure the
  /// audio session and engine nodes.
  func setRecorderEnabled(_ enabled: Bool) throws {
    guard !recorderStateIsUnknown else {
      throw TextError("Recorder state is unavailable after a failed rollback; recreate the engine.")
    }
    if enabled == isRecorderEnabled { return }
    let previousOverride = _recorderEnabledOverride
    let previousEnabled = isRecorderEnabled
    let previousStrategy = audioCaptureStrategy
    do {
      try RecorderStateTransition.apply(
        targetEnabled: enabled,
        performNativeTransition: {
          pendingRecorderEnabled = enabled
          try applyNativeRecorderState(enabled: enabled)
        },
        rollbackNativeTransition: {
          pendingRecorderEnabled = previousEnabled
          try applyNativeRecorderState(
            enabled: previousEnabled,
            strategy: previousStrategy
          )
        },
        commit: {
          _recorderEnabledOverride = $0
          pendingRecorderEnabled = nil
        }
      )
    } catch {
      pendingRecorderEnabled = nil
      if error is RecorderStateRollbackError {
        recorderStateIsUnknown = true
      } else {
        _recorderEnabledOverride = previousOverride
        audioCaptureStrategy = previousStrategy
      }
      throw error
    }
  }

  private func applyNativeRecorderState(
    enabled: Bool,
    strategy: IOSAudioCaptureStrategy? = nil
  ) throws {
    let restartEngine = shouldBeStarted
    if restartEngine {
      stopBackground(isRestart: true)
      stopAudio()
      audioEngine.stop()
      audioEngine.reset()
    }
    removeRecorderTap()

    let targetStrategy =
      strategy ?? negotiateAudioCaptureStrategy(recorderEnabled: enabled)
    audioCaptureStrategy = targetStrategy

    // Turning VoiceProcessingIO off has to happen while the session is still
    // record-capable; the `.playback` session this transition is heading for
    // has no valid input format to reconfigure the shared I/O unit against.
    if voiceProcessingTransitionPrecedesSessionReconfiguration() {
      try applyVoiceProcessingStrategy()
    }

    try audioSession.configure(
      recorderEnabled: enabled,
      voiceProcessingRequested: arguments.voiceProcessing
    )
    try audioSession.activate()

    #if os(iOS)
      if enabled && arguments.voiceProcessing && webRtcApm == nil {
        initializeApm()
      } else if !enabled {
        invalidateCaptureLiveness()
        webRtcApm?.release()
        webRtcApm = nil
      }
    #endif

    try applyVoiceProcessingStrategy()
    try installTap()
    audioEngine.prepare()
    if restartEngine {
      try start()
    }
  }
}
