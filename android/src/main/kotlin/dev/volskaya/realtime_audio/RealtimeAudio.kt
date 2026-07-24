package dev.volskaya.realtime_audio

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioRecord.OnRecordPositionUpdateListener
import android.media.AudioTrack
import android.media.AudioTrack.OnPlaybackPositionUpdateListener
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.util.Log
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import dev.volskaya.realtime_audio.utils.ChunkAudioTrack
import dev.volskaya.realtime_audio.utils.ChunkAudioEventListener
import dev.volskaya.realtime_audio.utils.LoopAudioTrack
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Timer
import kotlin.math.roundToInt

data class QueuedChunk(
  val id: String,
  val data: ByteArray,
  val offset: Int,
  val pauseOffset: Int? = null,
) {
  override fun equals(other: Any?): Boolean {
    if (this === other) return true
    if (javaClass != other?.javaClass) return false

    other as QueuedChunk

    return id == other.id
  }

  override fun hashCode(): Int {
    return id.hashCode()
  }
}

class RealtimeAudio(
  private val id: String,
  private val arguments: CreateArguments,
  private val context: Context,
  private val methodChannel: MethodChannel,
) : MethodChannel.MethodCallHandler, OnPlaybackPositionUpdateListener, OnRecordPositionUpdateListener,
  ChunkAudioEventListener {

  private val mainLooperHandler = Handler(Looper.getMainLooper())

  private val recorderFormat = AudioFormat.Builder()
    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
    .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
    .setSampleRate(arguments.recorderSampleRate)
    .build()

  private val playerOutputFormat = AudioFormat.Builder()
    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
    .setSampleRate(arguments.playerSampleRate)
    .build()

  private var recorderData: ShortArray? = null
  private var recorder: AudioRecord?
  private var isRecorderEnabled: Boolean = arguments.recorderEnabled
  private val audioTrack: ChunkAudioTrack
  private val audioBackgroundTrack: LoopAudioTrack?
  private val audioManager: AudioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

  private var webRtcApm: WebRtcApm? = null

  /// Frame-aligns the write-time far-end feed into [webRtcApm] (null when no APM).
  private var renderFeeder: ApmRenderFeeder? = null

  /// The echo-control architecture this engine is running (2026-07-24 Android
  /// echo RCA): platform voice-call path with hardware AEC when the device
  /// offers it, software AEC3 fallback otherwise. See [EchoPathPolicy].
  private var echoDecision: EchoPathDecision = EchoPathPolicy.decide(
    voiceProcessing = false,
    hardwareAecAvailable = false,
    apmLoaded = false,
  )
  private var hardwareAec: AcousticEchoCanceler? = null
  private var hardwareNs: NoiseSuppressor? = null
  private val voiceCallSession = VoiceCallAudioSession(
    context.getSystemService(Context.AUDIO_SERVICE) as AudioManager,
  )

  private var isRunning = false
  private var isDisposed = false
  private var shouldBeRunning = false
  private var shouldBePaused = false

  /// Whether the mic capture path has delivered its first real buffer since
  /// recording (re)started — bubbles' `captureProvenLive`. Read back via
  /// `getEchoCancellationState`. Monotonic false→true within a capture session.
  @Volatile
  private var captureProvenLive = false

  private var playerProgressTimer: Timer? = null
  private var playerVolumeTimer: Timer? = null
  private var state: RealtimeAudioState = RealtimeAudioState(
    isPlaying = false,
    isPaused = false,
    duration = 0,
    durationTotal = 0,
    chunkCount = 0
  )

  init {
    val audioSessionId = audioManager.generateAudioSessionId()

    //setPerformanceMode

    echoDecision = decideEchoPath(recorderEnabled = arguments.recorderEnabled)
    if (arguments.recorderEnabled && echoDecision.communicationMode) {
      voiceCallSession.enter()
    }
    recorder = if (arguments.recorderEnabled) getRecorder(echoDecision.captureSource) else null
    if (arguments.recorderEnabled) {
      setupEchoControl()
    }
    // NOTE: playback attributes are bound to the echo decision at engine
    // creation. Every voice-call consumer creates the engine with the
    // recorder already enabled, so a later setRecorderEnabled(true) does not
    // re-create the track.
    audioTrack = getAudioTrack(audioSessionId)
    audioBackgroundTrack = if (arguments.backgroundEnabled) getBackgroundTrack(audioSessionId) else null
    attachRenderTapIfNeeded()

    methodChannel.setMethodCallHandler(this)

    audioBackgroundTrack?.setVolume(arguments.backgroundVolume.toFloat())
  }

  /// Probe hardware AEC + APM availability and decide the echo architecture.
  private fun decideEchoPath(recorderEnabled: Boolean, hardwareAecAvailable: Boolean = AcousticEchoCanceler.isAvailable()): EchoPathDecision =
    EchoPathPolicy.decide(
      voiceProcessing = arguments.voiceProcessing && recorderEnabled,
      hardwareAecAvailable = hardwareAecAvailable,
      apmLoaded = WebRtcApmJni.loaded,
    )

  /// Attach the decided echo control to the CURRENT recorder: the hardware
  /// AcousticEchoCanceler (platform voice-call path), or the software APM.
  /// A runtime hardware-attach failure (isAvailable() lied — vendor stub)
  /// re-decides onto the software path, which needs the unprocessed capture
  /// source, so the recorder is recreated.
  private fun setupEchoControl() {
    val rec = recorder ?: return
    var decision = echoDecision
    if (decision.attachHardwareAec) {
      val aec = runCatching {
        AcousticEchoCanceler.create(rec.audioSessionId)?.also { it.enabled = true }
      }.getOrNull()
      if (aec != null) {
        hardwareAec = aec
        hardwareNs = runCatching {
          NoiseSuppressor.create(rec.audioSessionId)?.also { it.enabled = true }
        }.getOrNull()
        Log.i("RealtimeAudio", "Hardware AEC attached (session ${rec.audioSessionId}, NS=${hardwareNs != null})")
      } else {
        decision = decideEchoPath(recorderEnabled = true, hardwareAecAvailable = false)
        echoDecision = decision
        Log.w("RealtimeAudio", "Hardware AEC create failed — falling back to ${decision.mechanism.wire}")
        runCatching {
          rec.release()
          recorder = getRecorder(decision.captureSource)
        }.onFailure {
          Log.w("RealtimeAudio", "Recorder recreate for software echo path failed: ${it.message}")
        }
      }
    }
    if (decision.useApm) {
      webRtcApm = runCatching {
        WebRtcApm(
          captureSampleRate = arguments.recorderSampleRate,
          renderSampleRate = arguments.playerSampleRate,
          aecEnabled = true,
          nsEnabled = true,
          agcEnabled = decision.apmAgcEnabled,
          mobileAec = decision.apmMobileAec,
        ).also { apm ->
          val totalDelayMs = estimatePipelineDelayMs()
          apm.setStreamDelay(totalDelayMs)
          Log.i("RealtimeAudio", "APM stream delay: ${totalDelayMs}ms")
        }
      }.onFailure {
        Log.w("RealtimeAudio", "WebRTC APM unavailable, falling back to raw audio: ${it.message}")
      }.getOrNull()?.takeIf { it.isAvailable }
    }
  }

  /// Static AudioTrack+AudioRecord buffer estimate — the AEC3 delay
  /// estimator's starting hint (AECM would depend on it entirely).
  private fun estimatePipelineDelayMs(): Int {
    val playbackLatencyMs = (playerOutputFormat.getMinBufferSizeTrack().toLong() * 1000) /
      (arguments.playerSampleRate * playerOutputFormat.getBitRatio())
    val captureLatencyMs = (recorderFormat.getMinBufferSizeRecord().toLong() * 1000) /
      (arguments.recorderSampleRate * recorderFormat.getBitRatio())
    return (playbackLatencyMs + captureLatencyMs).toInt().coerceIn(50, 300)
  }

  /// Release hardware audio effects attached to the capture session.
  private fun releaseHardwareEffects() {
    runCatching { hardwareAec?.release() }
    hardwareAec = null
    runCatching { hardwareNs?.release() }
    hardwareNs = null
  }

  /// Feed the APM's far-end reference from the writer thread (write-time, one
  /// track buffer ahead of the speaker) instead of queue time (whole chunks
  /// ahead). ApmRenderFeeder re-frames arbitrary write sizes to whole 10ms
  /// frames so the JNI bridge never drops tail bytes.
  private fun attachRenderTapIfNeeded() {
    val apm = webRtcApm
    if (apm == null) {
      renderFeeder = null
      audioTrack.renderTap = null
      return
    }
    val feeder = ApmRenderFeeder(
      frameBytes = (arguments.playerSampleRate / 100) * playerOutputFormat.getBitRatio(),
    ) { frames -> webRtcApm?.processRender(frames) }
    renderFeeder = feeder
    audioTrack.renderTap = { data, offset, length -> feeder.feed(data, offset, length) }
  }

  fun dispose() {
    isDisposed = true
    detachPlayerTimers()
    stopBackground()
    stopAudio()
    stopRecording()
    audioTrack.renderTap = null
    renderFeeder = null
    releaseHardwareEffects()
    webRtcApm?.release()
    webRtcApm = null
    audioBackgroundTrack?.release()
    audioTrack.release()
    recorder?.release()
    voiceCallSession.exit()
  }


  private fun attachPlayerTimers() {
    playerProgressTimer?.cancel()
    playerProgressTimer = Timer().schedule(arguments.playerProgressInterval) {
      mainLooperHandler.post { notifyPlayerProgress() }
    }

    playerVolumeTimer?.cancel()
    playerVolumeTimer = Timer().schedule(arguments.playerVolumeInterval) {
      mainLooperHandler.post { notifyPlayerVolume() }
    }
  }

  private fun detachPlayerTimers() {
    playerProgressTimer?.cancel()
    playerProgressTimer = null
    playerVolumeTimer?.cancel()
    playerVolumeTimer = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    runCatching { handleMethodCallSafe(call, result) }
      .onFailure {
        result.error(
          "INTERNAL",
          it.localizedMessage ?: "Undefined message.",
          it.stackTraceToString()
        )
      }
  }

  private fun handleMethodCallSafe(call: MethodCall, result: MethodChannel.Result) {
    var value: Any? = true

    when (call.method) {
      "queue" -> {
        val id = call.argument<String>("id") ?: throw Error("Missing id for ${call.method}.")
        val data = call.argument<ByteArray>("data") ?: throw Error("Missing data for ${call.method}.")

        queueAudio(id, data)
      }

      "clearQueue" -> {
        // Read the chunk cut position BEFORE stopping; stopAudio() then folds the
        // render clock, so the returned `clock` carries the folded lifetime values.
        val chunk = audioTrack.getCurrentChunkProps()
        stopAudio()
        value = mapOf("chunk" to chunk, "clock" to playbackClockMap())
      }

      "getPlayerPlayedDuration" -> value = playbackClockMap()
      "repairPlaybackAccounting" -> {
        val expectedScheduledMs = call.argument<Int>("expectedScheduledMs")
          ?: throw Error("Missing expectedScheduledMs for ${call.method}.")
        val reason = if (expectedScheduledMs == audioTrack.lifetimeScheduledMs) {
          "no_outstanding_buffers"
        } else {
          "scheduled_extent_changed"
        }
        value = mapOf(
          "repaired" to false,
          "reason" to reason,
          "clock" to playbackClockMap(),
        )
      }
      "recoverWedgedPlayback" -> {
        if (!shouldBeRunning || shouldBePaused) {
          value = mapOf(
            "recovered" to false,
            "message" to "Audio engine is not actively started.",
            "clock" to playbackClockMap(),
          )
        } else {
          stopAudio()
          value = mapOf(
            "recovered" to true,
            "clock" to playbackClockMap(),
          )
        }
      }
      "getEchoCancellationState" -> value = echoCancellationStateMap()

      "start" -> start()
      "pause" -> pause()
      "resume" -> resume()
      "stop" -> stop()

      "setRecorderEnabled" -> {
        val enabled = call.argument<Boolean>("enabled") ?: throw Error("Missing 'enabled' for ${call.method}.")
        setRecorderEnabled(enabled)
      }

      "stopBackground" -> stopBackground()
      "playBackground" -> {
        val id = call.argument<String>("id") ?: throw Error("Missing id for ${call.method}.")
        val data = call.argument<ByteArray>("data") ?: throw Error("Missing data for ${call.method}.")
        val loop = call.argument<Boolean>("loop") ?: throw Error("Missing loop for ${call.method}.")

        queueBackground(id, data, loop)
      }

      else -> value = null
    }

    value?.let { result.success(it) } ?: run { result.notImplemented() }
  }

  //

  private fun notifyState() {
    if (isDisposed) return
    methodChannel.invokeMethod("state", state.toMap())
  }

  private fun notifyPlayerProgress() {
    if (isDisposed) return

    var secondsTotal = 0.0
    var seconds = 0.0

    runCatching {
      secondsTotal = audioTrack.totalSampleTime.toDouble() / audioTrack.sampleRate
      seconds = audioTrack.playbackHeadPosition.toDouble() / audioTrack.sampleRate
    }

    state.duration = (seconds * 1000).roundToInt()
    state.durationTotal = (secondsTotal * 1000).roundToInt()
    state.renderClockMs = audioTrack.lifetimeRenderClockMs
    state.isRendering = effectiveIsRendering()

    notifyState()
  }

  private fun notifyPlayerState() {
    if (isDisposed) return

    state.chunkCount = audioTrack.queue.size
    state.isPaused = audioTrack.playState == AudioTrack.PLAYSTATE_PAUSED
    state.isPlaying =
      audioTrack.playState == AudioTrack.PLAYSTATE_PAUSED || audioTrack.playState == AudioTrack.PLAYSTATE_PLAYING
    state.renderClockMs = audioTrack.lifetimeRenderClockMs
    state.isRendering = effectiveIsRendering()

    notifyState()
  }

  /// Effective render state: the raw track signal (head behind scheduled or
  /// hangover) gated by the paused state (a paused track is silent).
  private fun effectiveIsRendering(): Boolean =
    audioTrack.playState != AudioTrack.PLAYSTATE_PAUSED && audioTrack.isRenderingPlaybackRaw

  private fun notifyPlayerVolume() {
    if (isDisposed) return

    val dbfs = runCatching {
      getDbfsFromChunks(
        audioTrack.queue,
        audioTrack.dataPlaybackHeadPosition,
        (audioTrack.dataSampleRate * 0.3).toInt()
      )
    }.getOrNull() ?: -96.0

    methodChannel.invokeMethod("playerVolume", dbfs)
  }

  private fun notifyRecorderVolume(volume: Double? = null) {
    methodChannel.invokeMethod("recorderVolume", volume ?: -96.0)
  }

  /// Snapshot of the three call-lifetime playback counters + render state — see
  /// [ChunkAudioTrack].
  private fun playbackClockMap(): Map<String, Any> = mapOf(
    "renderClockMs" to audioTrack.lifetimeRenderClockMs,
    "renderedMs" to audioTrack.lifetimeRenderedMs,
    "scheduledMs" to audioTrack.lifetimeScheduledMs,
    "isRendering" to effectiveIsRendering(),
  )

  /// Live read-back of the AEC path. `platform_aec` is claimed ONLY for a
  /// successfully-attached hardware AcousticEchoCanceler (the old read-back
  /// reported it for the bare VOICE_COMMUNICATION source, an unverifiable
  /// ghost); `webrtc_apm` for a live software APM (AEC3 on the shipped
  /// policy), with the APM's measured ERLE riding along so consumers can
  /// trust full duplex on cancellation EVIDENCE, not liveness.
  private fun echoCancellationStateMap(): Map<String, Any?> {
    val apmLive = webRtcApm?.isAvailable == true
    val hwLive = hardwareAec != null
    val mechanism = when {
      hwLive -> EchoMechanism.PLATFORM_AEC
      apmLive -> EchoMechanism.WEBRTC_APM
      else -> EchoMechanism.NONE
    }

    return mapOf(
      "requested" to arguments.voiceProcessing,
      "nativeEnabled" to (hwLive || apmLive),
      "mechanism" to mechanism.wire,
      "captureProvenLive" to captureProvenLive,
      "erleDb" to webRtcApm?.echoReturnLossEnhancementDb(),
      "apmMode" to if (apmLive) (if (echoDecision.apmMobileAec) "aecm" else "aec3") else null,
    )
  }

  //

  private fun getAudioTrack(audioSessionId: Int? = null) =
    ChunkAudioTrack(
      if (echoDecision.voiceCommunicationPlayback) {
        // The platform voice-call path: voice-usage playback routes through
        // the primary (low-latency) output AND lands in the HAL AEC's far-end
        // reference — a media-usage track on many OEMs does neither
        // (2026-07-24 Android echo RCA).
        AudioAttributes.Builder()
          .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
          .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
          .build()
      } else {
        AudioAttributes.Builder()
          .setLegacyStreamType(AudioManager.STREAM_MUSIC)
          .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
          .setUsage(AudioAttributes.USAGE_MEDIA)
          .build()
      },
      playerOutputFormat,
      playerOutputFormat.getMinBufferSizeTrack(),
      AudioTrack.MODE_STREAM,
      audioSessionId ?: AudioManager.AUDIO_SESSION_ID_GENERATE,
      this
    )

  private fun getBackgroundTrack(audioSessionId: Int? = null) =
    LoopAudioTrack(
      AudioAttributes.Builder()
        .setLegacyStreamType(AudioManager.STREAM_MUSIC)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .build(),
      playerOutputFormat,
      playerOutputFormat.getMinBufferSizeTrack(),
      AudioTrack.MODE_STREAM,
      audioSessionId ?: AudioManager.AUDIO_SESSION_ID_GENERATE,
    )

  private fun getRecorder(source: CaptureSource): AudioRecord {
    val permission = ActivityCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
    val isPermissionGranted = permission == PackageManager.PERMISSION_GRANTED

    if (!isPermissionGranted) {
      throw Error("No permission to record.")
    }

    val recorderChunkBufferSize =
      (recorderFormat.sampleRate.toDouble() * (arguments.recorderChunkInterval.toDouble() / 1000)).roundToInt()

    assert(recorderFormat.encoding == AudioFormat.ENCODING_PCM_16BIT)
    assert(recorderFormat.encoding == playerOutputFormat.encoding)

    val minBufferSize = recorderFormat.getMinBufferSizeRecord()
    val bufferSize = minBufferSize * recorderFormat.getBitRatio()

    val audioSource = when (source) {
      // Vendor voice-call preprocessing — feeds the hardware AEC.
      CaptureSource.VOICE_COMMUNICATION -> MediaRecorder.AudioSource.VOICE_COMMUNICATION
      // Unprocessed/linear capture — what the software canceller needs
      // (vendor preprocessing is nonlinear and defeats it).
      CaptureSource.VOICE_RECOGNITION -> MediaRecorder.AudioSource.VOICE_RECOGNITION
      CaptureSource.MIC -> MediaRecorder.AudioSource.MIC
    }

    return AudioRecord(
      audioSource,
      recorderFormat.sampleRate,
      recorderFormat.channelMask,
      recorderFormat.encoding,
      bufferSize,
    ).also {
      if (it.state != AudioRecord.STATE_INITIALIZED) {
        it.release()
        throw Error("AudioRecord failed to initialize (state=${it.state}). " +
          "The device may not support $audioSource while audio playback is active.")
      }
      recorderData = ShortArray(recorderChunkBufferSize)
      it.positionNotificationPeriod = recorderChunkBufferSize
      it.setRecordPositionUpdateListener(this)
    }
  }

  //

  override fun onChunkQueued(id: String) = methodChannel.invokeMethod("chunkQueued", id)
  override fun onChunkPlayed(id: String) = methodChannel.invokeMethod("chunkPlayed", id)
  override fun onChunkQueueStarted(id: String) = methodChannel.invokeMethod("chunkQueueStarted", id)
  override fun onChunkQueueEnded() = stopAudio()
  override fun onPlaybackDrainError(message: String) {
    mainLooperHandler.post {
      methodChannel.invokeMethod(
        "audioEngineHealth",
        mapOf(
          "type" to "playback_drain_signal_failed",
          "engineWasRunning" to isRunning,
          "queuedChunkCount" to audioTrack.queue.size,
          "message" to message,
        )
      )
    }
  }

  //

  private fun queueAudio(id: String, data: ByteArray) {
    if (data.isEmpty()) return

    // Far-end APM feed happens at WRITE time via audioTrack.renderTap — a
    // queue-time feed here ran the echo reference seconds ahead of the speaker.
    audioTrack.queue(id, data)
    if (audioTrack.playState != AudioTrack.PLAYSTATE_PAUSED) {
      playAudio()
    }
  }

  private fun playAudio() {
    if (!shouldBeRunning || shouldBePaused) return
    if (audioTrack.queue.isEmpty()) return
    if (audioTrack.playState == AudioTrack.PLAYSTATE_PLAYING) return

    audioTrack.play()
    attachPlayerTimers()
    notifyPlayerState()
  }

  private fun pauseAudio() {
    if (audioTrack.playState != AudioTrack.PLAYSTATE_PLAYING) return
    if (audioTrack.playState == AudioTrack.PLAYSTATE_PAUSED) return

    detachPlayerTimers()
    audioTrack.pause()
    notifyPlayerState()
  }

  private fun stopAudio() {
    if (audioTrack.playState == AudioTrack.PLAYSTATE_STOPPED) return

    detachPlayerTimers()
    runCatching {
      audioTrack.stop()
      audioTrack.flush()
    }
    // The carried sub-frame tail belongs to audio that will never render.
    renderFeeder?.reset()

    notifyPlayerState()
    notifyPlayerProgress()
    notifyPlayerVolume()
  }

  //

  private fun startRecording() {
    val rec = recorder ?: return
    if (rec.recordingState == AudioRecord.RECORDSTATE_RECORDING) return
    // New capture session — liveness is unproven until the first buffer arrives.
    captureProvenLive = false
    rec.startRecording()
    onPeriodicNotification(rec)
  }

  private fun stopRecording() {
    val rec = recorder ?: return
    if (rec.recordingState == AudioRecord.RECORDSTATE_STOPPED) return

    rec.stop()
    notifyRecorderVolume()
  }

  private fun handleRecorderData(buffer: ByteArray, dbfs: Double? = null) {
    methodChannel.invokeMethod("recorderData", buffer)
    notifyRecorderVolume(dbfs)
  }

  //

  override fun onMarkerReached(track: AudioTrack?) {}
  override fun onPeriodicNotification(track: AudioTrack?) {}

  override fun onMarkerReached(recorder: AudioRecord?) {
    runCatching { recorderData?.let { recorder?.read(it, 0, it.size) } }
  }

  private val recorderScope: CoroutineScope = CoroutineScope(Dispatchers.IO)
  private val recorderScopeMutex = Mutex()

  override fun onPeriodicNotification(recorder: AudioRecord?) {
    recorderScope.launch {
      recorderScopeMutex.withLock {
        if (recorder?.recordingState != AudioRecord.RECORDSTATE_RECORDING) return@withLock

        val bytes = runCatching<ByteBuffer> {
          val chunkSize = recorderData
            ?.let { recorder.read(it, 0, it.size) }
            ?.also { if (it < 0) return@also } ?: return@withLock

          return@runCatching ByteBuffer.allocate(chunkSize * recorderFormat.getBitRatio()).also {
            it.order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().put(recorderData)
          }
        }

        bytes.getOrNull()?.array()?.let { buffer ->
          // First real capture buffer proves the mic path is live.
          captureProvenLive = true
          val processed = webRtcApm?.processCapture(buffer) ?: buffer
          val dbfs = getDbfsFromByteArrays(listOf(processed), 0, processed.size)
          scope.launch {
            handleRecorderData(processed, dbfs)
          }
        }
      }
    }
  }

  //

  private fun queueBackground(id: String, data: ByteArray, loop: Boolean) {
    audioBackgroundTrack ?: return
    audioBackgroundTrack.queue(id, data, loop)
    playBackground()
  }

  private fun playBackground() {
    audioBackgroundTrack ?: return

    if (!isRunning) return
    if (audioBackgroundTrack.playState == AudioTrack.PLAYSTATE_PLAYING) return
    if (audioBackgroundTrack.bytes?.isNotEmpty() != true) return

    audioBackgroundTrack.play()
  }

  private fun pauseBackground() {
    audioBackgroundTrack ?: return
    audioBackgroundTrack.pause()
  }


  private fun stopBackground() {
    runCatching {
      audioBackgroundTrack ?: return
      audioBackgroundTrack.stop()
      audioBackgroundTrack.flush()
    }
  }

  //

  /// Dynamically toggle the recorder (and WebRTC APM / AEC) without
  /// disposing the entire engine. Creates or releases the AudioRecord
  /// and WebRtcApm as needed.
  private fun setRecorderEnabled(enabled: Boolean) {
    if (enabled == isRecorderEnabled) return
    isRecorderEnabled = enabled

    if (enabled) {
      // Create recorder + APM
      echoDecision = decideEchoPath(recorderEnabled = true)
      if (echoDecision.communicationMode) voiceCallSession.enter()
      recorder = getRecorder(echoDecision.captureSource)
      setupEchoControl()
      attachRenderTapIfNeeded()
      if (isRunning) startRecording()
    } else {
      // Release recorder + hardware effects + APM, leave the voice-call
      // audio-manager state (a playback tail may still be draining and the
      // recorder can come right back — recoverRecorder(); dispose() exits it).
      stopRecording()
      recorder?.release()
      recorder = null
      recorderData = null
      captureProvenLive = false
      audioTrack.renderTap = null
      renderFeeder = null
      releaseHardwareEffects()
      webRtcApm?.release()
      webRtcApm = null
    }

    Log.i("RealtimeAudio", "Recorder ${if (enabled) "enabled" else "disabled"} dynamically")
  }

  private fun start() {
    shouldBeRunning = true
    isRunning = true
    startRecording()
    playAudio()
  }

  private fun pause() {
    shouldBePaused = true
    pauseBackground()
    pauseAudio()
    stopRecording()
    isRunning = false
  }

  private fun resume() {
    shouldBePaused = false
    isRunning = true
    playBackground()
    playAudio()
    startRecording()
  }

  private fun stop() {
    shouldBeRunning = false
    stopBackground()
    stopAudio()
    stopRecording()
    isRunning = false
  }
}
