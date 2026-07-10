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

  private let recorderSampleRate: Double
  private let recorderFormat: AVAudioFormat
  private var recorderConverter: AVAudioConverter?
  private let recorderPreferredBus: AVAudioNodeBus = 0
  private var recorderActiveBus: AVAudioNodeBus?
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

  private var playerVolumeTimer: Timer?
  private var playerProgressTimer: Timer?
  private var state: RealtimeAudioState = .init(
    isPlaying: false,
    isPaused: false,
    duration: 0,
    durationTotal: 0,
    chunkCount: 0,
    renderedMs: 0,
    isRendering: false
  )

  /// Whether the mic capture path has delivered its first real buffer since the
  /// tap was (re)installed — bubbles' `captureProvenLive`. Read back via
  /// `getEchoCancellationState`. Monotonic false→true within a capture session.
  private var captureProvenLive = false

  /// Mutable override for recorder state — allows dynamic toggling without
  /// disposing the engine. `nil` means use `arguments.recorderEnabled`.
  private var _recorderEnabledOverride: Bool?
  var isRecorderEnabled: Bool { _recorderEnabledOverride ?? arguments.recorderEnabled }

  private func createPlayerNodesForCurrentRoute() throws {
    let routeSampleRate = audioSession.sampleRate ?? playerSampleRate
    guard let outputFormat = getAudioFormat(.pcmFormatFloat32, routeSampleRate, 1) else {
      throw TextError("Failed to create player output format.")
    }
    playerOutputFormat = outputFormat
    audioPlayerNode = try ChunkAudioPlayerNode(inputFormat: playerInputFormat, outputFormat: outputFormat)
    audioBackgroundNode = arguments.backgroundEnabled
      ? try LoopAudioPlayerNode(inputFormat: playerInputFormat, outputFormat: outputFormat)
      : nil
  }

  #if os(iOS)
    /// WebRTC Audio Processing Module for software echo cancellation, noise
    /// suppression, and AGC. Used instead of Apple's voice processing when
    /// the `voiceProcessing` argument is true.
    private var webRtcApm: WebRtcApm?

  #endif

  private var shouldBeStarted = false
  private var shouldBePaused = false
  private var isDisposed = false
  private var isDeinitialized = false

  init(
    id: String,
    arguments: CreateArguments,
    methodChannel: FlutterMethodChannel
  ) throws {
    self.id = id
    self.arguments = arguments
    self.methodChannel = methodChannel

    self.recorderSampleRate = arguments.recorderSampleRate
    self.recorderFormat = getAudioFormat(.pcmFormatInt16, recorderSampleRate, 1)!

    self.playerSampleRate = arguments.playerSampleRate
    self.playerInputFormat = getAudioFormat(.pcmFormatInt16, playerSampleRate, 1)!

    super.init()

    //

    // Initialize WebRTC APM for noise suppression and AGC only (no AEC).
    // Apple's VoiceProcessingIO handles echo cancellation at the hardware level.
    #if os(iOS)
      if arguments.voiceProcessing && isRecorderEnabled {
        initializeApm()
      }
    #endif

    // The route's sample rate is authoritative only after activation.
    try audioSession.configure(recorderEnabled: isRecorderEnabled)
    try audioSession.activate()
    try createPlayerNodesForCurrentRoute()
    attachObservers()
    audioPlayerNode.setListener(self)
    methodChannel.setMethodCallHandler(handleFlutterMethod)
    try attachNodes()

    changeVolume()

    try installTap()
    audioEngine.prepare()
  }

  #if os(iOS)
    /// Whether the WebRTC APM is active (NS + AGC processing).
    private var webRtcApmActive: Bool { webRtcApm?.isAvailable == true }

    /// Initialize the WebRTC APM for noise suppression and AGC only.
    /// AEC is disabled — Apple's VoiceProcessingIO handles echo cancellation
    /// at the hardware level with per-device acoustic models.
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
      methodChannel.invokeMethod("echo", arguments: "WebRTC APM initialized (NS + AGC only, Apple VP handles AEC)")
    }
  #endif

  private func attachNodes() throws {
    #if os(iOS)
      if isRecorderEnabled {
        // Apple's VoiceProcessingIO handles AEC at the hardware level.
        try audioEngine.outputNode.setVoiceProcessingEnabled(true)
        try audioEngine.inputNode.setVoiceProcessingEnabled(true)
        audioEngine.inputNode.isVoiceProcessingAGCEnabled = false
      }
    #endif

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
  }

  private func attachObservers() {
    #if os(iOS)
      audioSession.instance.addObserver(self, forKeyPath: "outputVolume", options: .new, context: nil)
    #endif
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioEngineConfigurationChange),
      name: .AVAudioEngineConfigurationChange,
      object: nil
    )
  }

  @objc private func handleAudioEngineConfigurationChange(notification: NSNotification) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      methodChannel.invokeMethod(
        "echo", arguments: "Audio engine configuration changed, need to restart. \(shouldBeStarted)")
      do {
        try restart()
      } catch {
        print("Failed to restart after configuration change.")
        print(error)
      }
    }
  }

  private func changeVolume() {
    if !isRecorderEnabled { return }
    #if os(iOS)
      audioEngine.mainMixerNode.outputVolume = audioSession.instance.outputVolume
    #endif
  }

  deinit {
    isDeinitialized = true

    #if os(iOS)
      audioSession.instance.removeObserver(self, forKeyPath: "outputVolume")
      audioEngine.inputNode.removeTap(onBus: recorderPreferredBus)
      webRtcApm?.release()
      webRtcApm = nil
    #endif

    methodChannel.setMethodCallHandler(nil)
    detachTimers()
    recorderConverter?.reset()
    recorderConverter = nil
    try? stop()
    try? audioSession.deactivate()
  }

  func dispose() throws {
    isDisposed = true

    // Remove tap BEFORE releasing APM to prevent use-after-free.
    audioEngine.inputNode.removeTap(onBus: recorderPreferredBus)

    #if os(iOS)
      webRtcApm?.release()
      webRtcApm = nil
    #endif

    methodChannel.setMethodCallHandler(nil)
    detachTimers()
    try stop()
    try audioSession.deactivate()
  }

  override func observeValue(
    forKeyPath keyPath: String?,
    of object: Any?,
    change: [NSKeyValueChangeKey: Any]?,
    context: UnsafeMutableRawPointer?
  ) {
    switch keyPath {
    case "outputVolume":
      #if os(iOS)
        if audioEngine.mainMixerNode.outputVolume != audioSession.instance.outputVolume {
          changeVolume()
          assert(Thread.isMainThread)
          methodChannel.invokeMethod("echo", arguments: "Volume changing to \(audioSession.instance.outputVolume)")
        }
      #endif
      break
    default:
      break  // Do nothing
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
    let progressInterval: TimeInterval = arguments.playerProgressInterval.fromMsToTimeInterval()
    let volumeInterval: TimeInterval = arguments.playerVolumeInterval.fromMsToTimeInterval()

    playerProgressTimer =
      self.playerProgressTimer
      ?? Timer.scheduledTimer(withTimeInterval: progressInterval, repeats: true) { [weak self] timer in
        if let self { self.notifyPlayerProgress() } else { timer.invalidate() }
      }

    playerVolumeTimer =
      self.playerVolumeTimer
      ?? Timer.scheduledTimer(withTimeInterval: volumeInterval, repeats: true) { [weak self] timer in
        if let self { self.notifyPlayerVolume() } else { timer.invalidate() }
      }
  }

  private func detachTimers() {
    playerVolumeTimer?.invalidate()
    playerVolumeTimer = nil
    playerProgressTimer?.invalidate()
    playerProgressTimer = nil
  }

  private func notifyState() {
    if isDisposed || isDeinitialized { return }

    DispatchQueue.main.async { [weak self] in
      guard let self, let json = try? self.state.toJsonMap() else { return }
      assert(Thread.isMainThread)
      self.methodChannel.invokeMethod("state", arguments: json)
    }
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

    let renderedMs = audioPlayerNode.playedMs
    let isRendering = audioPlayerNode.isRenderingPlayback

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }

      self.state.duration = duration
      self.state.durationTotal = durationTotal
      self.state.renderedMs = renderedMs
      self.state.isRendering = isRendering
      self.notifyState()
    }
  }

  private func notifyPlayerState(
    isPaused: Bool?
  ) {
    if isDisposed || isDeinitialized { return }
    state.chunkCount = audioPlayerNode.queue.count
    state.isPlaying = audioPlayerNode.isPlaying
    if let isPaused { state.isPaused = isPaused }
    state.renderedMs = audioPlayerNode.playedMs
    state.isRendering = audioPlayerNode.isRenderingPlayback
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

    DispatchQueue.main.async { [weak self] in
      self?.methodChannel.invokeMethod("playerVolume", arguments: volume)
    }
  }

  func notifyRecorderVolume(_ volume: Float? = nil) {
    methodChannel.invokeMethod("recorderVolume", arguments: volume ?? -96.0)
  }

  /// Total queued milliseconds of the current stream, from the player node's
  /// scheduled sample count (output sample rate).
  private func totalQueuedMs() -> Int {
    RenderClock.framesToMs(
      sampleTime: Int64(audioPlayerNode.totalSampleTime),
      sampleRate: playerOutputFormat.sampleRate
    )
  }

  /// Snapshot of the completion-independent render clock — see
  /// `ChunkAudioPlayerNode.playedMs`.
  private func playbackClockMap() -> [String: Any] {
    return [
      "renderedMs": audioPlayerNode.playedMs,
      "isRendering": audioPlayerNode.isRenderingPlayback,
      "durationTotalMs": totalQueuedMs(),
    ]
  }

  /// Live read-back of the AEC path. On iOS/macOS, AEC is handled by Apple's
  /// VoiceProcessingIO — enabled only when recording with `voiceProcessing`.
  /// `nativeEnabled` reads the real state back rather than assuming it.
  private func echoCancellationStateMap() -> [String: Any] {
    var nativeEnabled = false
    var mechanism = RealtimeAudioEchoCancellationMechanism.none

    #if os(iOS)
      if isRecorderEnabled && arguments.voiceProcessing {
        mechanism = .appleVoiceProcessingIO
        nativeEnabled = audioEngine.inputNode.isVoiceProcessingEnabled
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
      let flutterError = FlutterError(
        code: "INTERNAL",
        message: (error as? TextError)?.message ?? error.localizedDescription,
        details: nil
      )

      result(flutterError)
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
      value = ["chunk": audioPlayerNode.getCurrentChunkProps()]
      stopAudio()
      break
    case "getPlayerPlayedDuration":
      value = playbackClockMap()
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

// Player extension.
extension RealtimeAudio: ChunkAudioEventListener {
  func onChunkQueued(_ id: String) { methodChannel.invokeMethod("chunkQueued", arguments: id) }
  func onChunkPlayed(_ id: String) { methodChannel.invokeMethod("chunkPlayed", arguments: id) }
  func onChunkQueueStarted(_ id: String) { methodChannel.invokeMethod("chunkQueueStarted", arguments: id) }
  func onChunkQueueEnded() { stopAudio() }

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
    captureProvenLive = false
    audioEngine.inputNode.removeTap(onBus: recorderPreferredBus)

    let input = audioEngine.inputNode
    let inputFormat = input.inputFormat(forBus: recorderPreferredBus)
    let ratio: Float = Float(inputFormat.sampleRate) / Float(recorderFormat.sampleRate)
    let converter = try getRecorderConverter(inputFormat, recorderFormat)
    let bufferSize = AVAudioFrameCount(inputFormat.sampleRate * Double(arguments.recorderChunkInterval) / 1000)

    input.installTap(
      onBus: recorderPreferredBus,
      bufferSize: bufferSize,
      format: inputFormat
    ) { [weak self] (buffer, time) -> Void in
      guard let self else { return }
      if self.shouldBePaused { return }

      // First real capture buffer proves the mic path is live (captureProvenLive).
      if buffer.frameLength > 0 { self.captureProvenLive = true }

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
  }

  // No output tap needed — APM handles NS + AGC only, not AEC.
  // Apple's VoiceProcessingIO handles echo cancellation at the hardware level.

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
      assert(Thread.isMainThread)
      self?.methodChannel.invokeMethod("recorderData", arguments: flutterData)
      self?.notifyRecorderVolume(volume)
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
    shouldBeStarted = true
    try audioEngine.start()
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
    shouldBePaused = false
    try audioEngine.start()
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
    if enabled == isRecorderEnabled { return }
    _recorderEnabledOverride = enabled

    #if os(iOS)
      if enabled && arguments.voiceProcessing && webRtcApm == nil {
        initializeApm()
      } else if !enabled {
        captureProvenLive = false
        webRtcApm?.release()
        webRtcApm = nil
      }
    #endif

    try audioSession.configure(recorderEnabled: enabled)
    try audioSession.activate()
    try restart()
  }

  private func restart() throws {
    if !shouldBeStarted { return }
    stopBackground(isRestart: true)
    stopAudio()
    audioEngine.stop()
    audioEngine.reset()
    try attachNodes()
    try installTap()
    try start()
  }
}
