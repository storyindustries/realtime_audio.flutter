package dev.volskaya.realtime_audio

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import kotlin.math.ceil

enum class OutputRoute(val wire: String) {
  SPEAKER("speaker"),
  RECEIVER("receiver"),
  WIRED("wired"),
  BLUETOOTH("bluetooth"),
  OTHER("other");

  companion object {
    fun fromWire(value: String?): OutputRoute? = entries.firstOrNull { it.wire == value }
  }
}

enum class OutputRouteSelectionResult(val wire: String) {
  AUTOMATIC("automatic"),
  APPLIED("applied"),
  PENDING("pending"),
  FAILED("failed"),
  UNAVAILABLE("unavailable"),
}

enum class DeviceSelectionStatus { APPLIED, PENDING, FAILED }
enum class RouteEvent { CHANGED, SELECTION_FAILED }

data class CommunicationDevice(val id: Int, val type: Int)
data class ApplicableVolume(val stream: String, val normalized: Double)

data class OutputRouteState(
  val active: OutputRoute?,
  val available: List<OutputRoute>,
  val requested: OutputRoute?,
  val selectionResult: OutputRouteSelectionResult,
  val volume: ApplicableVolume?,
) {
  fun toMap(): Map<String, Any?> = mapOf(
    "active" to active?.wire,
    "available" to available.map { it.wire },
    "requested" to requested?.wire,
    "selectionResult" to selectionResult.wire,
    "volumeControlStream" to volume?.stream,
    "volume" to volume?.normalized,
  )
}

interface CommunicationAudioSystem {
  fun availableDevices(): List<CommunicationDevice>
  fun activeDevice(): CommunicationDevice?
  fun setDevice(device: CommunicationDevice): DeviceSelectionStatus
  fun clearDevice(): Boolean
  fun registerRouteListener(listener: (RouteEvent) -> Unit)
  fun unregisterRouteListener()
  fun scheduleSelectionTimeout(action: () -> Unit): () -> Unit
  fun applicableVolume(): ApplicableVolume?
  fun ensureMinimumVolume(minimum: Double): ApplicableVolume?
}

object OutputRouteActivationPolicy {
  fun shouldActivate(
    recorderEnabled: Boolean,
    voiceProcessingRequested: Boolean,
    communicationMode: Boolean,
  ): Boolean = recorderEnabled && voiceProcessingRequested && communicationMode
}

/** Route policy and read-back contract, independent from Android callbacks. */
class OutputRouteController(
  private val system: CommunicationAudioSystem,
  private val onStateChanged: (OutputRouteState) -> Unit = {},
) {
  private var started = false
  private var requested: OutputRoute? = null
  private var selectionResult = OutputRouteSelectionResult.AUTOMATIC
  private var pendingSelection: PendingSelection? = null
  private var cancelPendingTimeout: (() -> Unit)? = null

  private data class PendingSelection(
    val device: CommunicationDevice,
    val completedResult: OutputRouteSelectionResult,
  )

  fun start(): OutputRouteState {
    if (!started) {
      started = true
      system.registerRouteListener(::onRouteEvent)
    }
    return applyPolicy()
  }

  fun stop() {
    if (!started) return
    started = false
    clearPendingSelection()
    system.unregisterRouteListener()
  }

  fun select(route: OutputRoute?): OutputRouteState {
    requested = route
    clearPendingSelection()
    if (!started) {
      selectionResult = OutputRouteSelectionResult.UNAVAILABLE
      return emitSnapshot()
    }
    return applyPolicy()
  }

  fun ensureMinimumVolume(minimum: Double): OutputRouteState {
    system.ensureMinimumVolume(minimum)
    return emitSnapshot()
  }

  fun snapshot(): OutputRouteState = buildSnapshot()

  private fun onRouteEvent(event: RouteEvent) {
    if (!started) return
    val pending = pendingSelection
    if (event == RouteEvent.SELECTION_FAILED) {
      if (pending != null) {
        clearPendingSelection()
        selectionResult = OutputRouteSelectionResult.FAILED
        emitSnapshot()
      }
      return
    }
    if (pending != null) {
      if (pending.completedResult == OutputRouteSelectionResult.UNAVAILABLE &&
        requestedRouteIsAvailable()
      ) {
        clearPendingSelection()
        applyPolicy()
        return
      }
      val current = system.activeDevice()
      if (devicesMatch(current, pending.device)) {
        clearPendingSelection()
        selectionResult = pending.completedResult
        emitSnapshot()
        return
      }
      val stillAvailable = system.availableDevices().any { devicesMatch(it, pending.device) }
      if (stillAvailable) {
        emitSnapshot()
        return
      }
      clearPendingSelection()
    }
    applyPolicy()
  }

  private fun requestedRouteIsAvailable(): Boolean {
    val route = requested ?: return false
    return system.availableDevices().any { CommRoutePolicy.routeForType(it.type) == route }
  }

  private fun applyPolicy(): OutputRouteState {
    if (!started) {
      selectionResult = OutputRouteSelectionResult.UNAVAILABLE
      return emitSnapshot()
    }
    pendingSelection?.let { return emitSnapshot() }
    val available = system.availableDevices()
    val current = system.activeDevice()
    val types = available.map { it.type }
    val requestedType = CommRoutePolicy.desiredCommunicationDeviceType(requested, current?.type, types)
    val requestedDevice = requestedType?.let { type -> available.firstOrNull { it.type == type } }

    if (requested != null && requestedDevice == null) {
      selectionResult = OutputRouteSelectionResult.UNAVAILABLE
      val fallbackType = CommRoutePolicy.desiredCommunicationDeviceType(null, current?.type, types)
      val fallback = fallbackType?.let { type -> available.firstOrNull { it.type == type } }
      return if (fallback == null || devicesMatch(current, fallback)) {
        emitSnapshot()
      } else {
        beginSelection(fallback, OutputRouteSelectionResult.UNAVAILABLE)
      }
    }

    val desired = requestedDevice ?: run {
      selectionResult = OutputRouteSelectionResult.AUTOMATIC
      return emitSnapshot()
    }
    val completedResult = if (requested == null) {
      OutputRouteSelectionResult.AUTOMATIC
    } else {
      OutputRouteSelectionResult.APPLIED
    }
    if (devicesMatch(current, desired)) {
      selectionResult = completedResult
      return emitSnapshot()
    }
    return beginSelection(desired, completedResult)
  }

  private fun beginSelection(
    desired: CommunicationDevice,
    completedResult: OutputRouteSelectionResult,
  ): OutputRouteState {
    return when (system.setDevice(desired)) {
      DeviceSelectionStatus.FAILED -> {
        selectionResult = OutputRouteSelectionResult.FAILED
        emitSnapshot()
      }
      DeviceSelectionStatus.APPLIED -> {
        selectionResult = if (devicesMatch(system.activeDevice(), desired)) {
          completedResult
        } else {
          OutputRouteSelectionResult.FAILED
        }
        emitSnapshot()
      }
      DeviceSelectionStatus.PENDING -> {
        pendingSelection = PendingSelection(desired, completedResult)
        selectionResult = if (completedResult == OutputRouteSelectionResult.UNAVAILABLE) {
          OutputRouteSelectionResult.UNAVAILABLE
        } else {
          OutputRouteSelectionResult.PENDING
        }
        cancelPendingTimeout = system.scheduleSelectionTimeout(::onSelectionTimeout)
        emitSnapshot()
      }
    }
  }

  private fun onSelectionTimeout() {
    if (!started || pendingSelection == null) return
    clearPendingSelection()
    selectionResult = OutputRouteSelectionResult.FAILED
    emitSnapshot()
  }

  private fun clearPendingSelection() {
    pendingSelection = null
    cancelPendingTimeout?.invoke()
    cancelPendingTimeout = null
  }

  private fun devicesMatch(left: CommunicationDevice?, right: CommunicationDevice): Boolean =
    left?.let { it.id == right.id && it.type == right.type } == true

  private fun emitSnapshot(): OutputRouteState = buildSnapshot().also(onStateChanged)

  private fun buildSnapshot(): OutputRouteState {
    val available = (if (started) system.availableDevices() else emptyList())
      .map { CommRoutePolicy.routeForType(it.type) }
      .distinct()
    return OutputRouteState(
      active = if (started) {
        system.activeDevice()?.let { CommRoutePolicy.routeForType(it.type) }
      } else {
        null
      },
      available = available,
      requested = requested,
      selectionResult = if (started) selectionResult else OutputRouteSelectionResult.UNAVAILABLE,
      volume = system.applicableVolume(),
    )
  }
}

object PlaybackVolumePolicy {
  fun fallbackStreamForUsage(usage: Int): Int = when (usage) {
    AudioAttributes.USAGE_VOICE_COMMUNICATION,
    AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING -> AudioManager.STREAM_VOICE_CALL
    AudioAttributes.USAGE_MEDIA,
    AudioAttributes.USAGE_GAME -> AudioManager.STREAM_MUSIC
    else -> AudioManager.STREAM_SYSTEM
  }

  fun streamFor(attributes: AudioAttributes): Int {
    val derived = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      attributes.volumeControlStream
    } else {
      null
    }
    return resolveStream(attributes.usage, derived)
  }

  fun resolveStream(usage: Int, derivedStream: Int?): Int =
    derivedStream?.takeUnless { it == AudioManager.USE_DEFAULT_STREAM_TYPE }
      ?: fallbackStreamForUsage(usage)

  fun levelWithFloor(current: Int, maximum: Int, minimum: Double): Int =
    maxOf(current, ceil(maximum * minimum.coerceIn(0.0, 1.0)).toInt())
}

object LegacyRouteInventory {
  fun availableTypes(connectedOutputTypes: List<Int>): List<Int> {
    val wiredConnected = connectedOutputTypes.any {
      CommRoutePolicy.routeForType(it) == OutputRoute.WIRED
    }
    return connectedOutputTypes
      .filterNot { it == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP }
      .filterNot { wiredConnected && it == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }
      .distinct()
  }
}

object LegacyScoRouteEvent {
  fun fromState(state: Int): RouteEvent? = when (state) {
    AudioManager.SCO_AUDIO_STATE_CONNECTED -> RouteEvent.CHANGED
    AudioManager.SCO_AUDIO_STATE_DISCONNECTED,
    AudioManager.SCO_AUDIO_STATE_ERROR -> RouteEvent.SELECTION_FAILED
    else -> null
  }
}

class AndroidCommunicationAudioSystem(
  private val context: Context,
  private val audioManager: AudioManager,
  private val handler: Handler,
) : CommunicationAudioSystem {
  private var playbackAttributes: AudioAttributes? = null
  private var routeListener: ((RouteEvent) -> Unit)? = null
  private var communicationListener: AudioManager.OnCommunicationDeviceChangedListener? = null
  private var deviceCallback: AudioDeviceCallback? = null
  private var scoReceiver: BroadcastReceiver? = null
  private var legacyScoConnected = false

  fun setPlaybackAttributes(attributes: AudioAttributes) {
    playbackAttributes = attributes
  }

  override fun availableDevices(): List<CommunicationDevice> =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      audioManager.availableCommunicationDevices.map { CommunicationDevice(it.id, it.type) }
    } else {
      val connected = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
      val availableTypes = LegacyRouteInventory.availableTypes(connected.map { it.type })
      connected
        .filter { it.type in availableTypes }
        .distinctBy { CommRoutePolicy.routeForType(it.type) }
        .map { CommunicationDevice(it.id, it.type) }
    }

  override fun activeDevice(): CommunicationDevice? {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      return audioManager.communicationDevice?.let { CommunicationDevice(it.id, it.type) }
    }
    @Suppress("DEPRECATION")
    val activeRoute = when {
      legacyScoConnected || audioManager.isBluetoothScoOn -> OutputRoute.BLUETOOTH
      audioManager.isWiredHeadsetOn -> OutputRoute.WIRED
      audioManager.isSpeakerphoneOn -> OutputRoute.SPEAKER
      else -> OutputRoute.RECEIVER
    }
    return availableDevices().firstOrNull {
      CommRoutePolicy.routeForType(it.type) == activeRoute
    }
  }

  override fun setDevice(device: CommunicationDevice): DeviceSelectionStatus {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      val platformDevice = audioManager.availableCommunicationDevices
        .firstOrNull { it.id == device.id && it.type == device.type }
        ?: return DeviceSelectionStatus.FAILED
      val accepted = runCatching { audioManager.setCommunicationDevice(platformDevice) }.getOrDefault(false)
      return if (accepted) DeviceSelectionStatus.PENDING else DeviceSelectionStatus.FAILED
    }
    return runCatching {
      @Suppress("DEPRECATION")
      when (CommRoutePolicy.routeForType(device.type)) {
        OutputRoute.BLUETOOTH -> {
          if (!audioManager.isBluetoothScoAvailableOffCall) return DeviceSelectionStatus.FAILED
          legacyScoConnected = false
          audioManager.isSpeakerphoneOn = false
          audioManager.startBluetoothSco()
          DeviceSelectionStatus.PENDING
        }
        OutputRoute.SPEAKER -> {
          stopLegacySco()
          audioManager.isSpeakerphoneOn = true
          DeviceSelectionStatus.APPLIED
        }
        OutputRoute.RECEIVER, OutputRoute.WIRED, OutputRoute.OTHER -> {
          stopLegacySco()
          audioManager.isSpeakerphoneOn = false
          DeviceSelectionStatus.APPLIED
        }
      }
    }.getOrDefault(DeviceSelectionStatus.FAILED)
  }

  override fun clearDevice(): Boolean {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      audioManager.clearCommunicationDevice()
      return true
    }
    @Suppress("DEPRECATION")
    audioManager.isSpeakerphoneOn = false
    stopLegacySco()
    return true
  }

  override fun registerRouteListener(listener: (RouteEvent) -> Unit) {
    if (routeListener != null) return
    routeListener = listener
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      val selectedListener = AudioManager.OnCommunicationDeviceChangedListener {
        listener(RouteEvent.CHANGED)
      }
      communicationListener = selectedListener
      audioManager.addOnCommunicationDeviceChangedListener(
        { command -> handler.post(command) },
        selectedListener,
      )
    } else {
      val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
          val state = intent?.getIntExtra(
            AudioManager.EXTRA_SCO_AUDIO_STATE,
            AudioManager.SCO_AUDIO_STATE_ERROR,
          ) ?: return
          when (state) {
            AudioManager.SCO_AUDIO_STATE_CONNECTED -> {
              legacyScoConnected = true
              @Suppress("DEPRECATION")
              runCatching { audioManager.isBluetoothScoOn = true }
            }
            AudioManager.SCO_AUDIO_STATE_DISCONNECTED,
            AudioManager.SCO_AUDIO_STATE_ERROR -> legacyScoConnected = false
          }
          LegacyScoRouteEvent.fromState(state)?.let(listener)
        }
      }
      scoReceiver = receiver
      val filter = IntentFilter(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
      } else {
        @Suppress("DEPRECATION")
        context.registerReceiver(receiver, filter)
      }
    }
    val callback = object : AudioDeviceCallback() {
      override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) =
        listener(RouteEvent.CHANGED)
      override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) =
        listener(RouteEvent.CHANGED)
    }
    deviceCallback = callback
    audioManager.registerAudioDeviceCallback(callback, handler)
  }

  override fun unregisterRouteListener() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      communicationListener?.let(audioManager::removeOnCommunicationDeviceChangedListener)
    }
    communicationListener = null
    scoReceiver?.let { runCatching { context.unregisterReceiver(it) } }
    scoReceiver = null
    deviceCallback?.let(audioManager::unregisterAudioDeviceCallback)
    deviceCallback = null
    routeListener = null
  }

  override fun scheduleSelectionTimeout(action: () -> Unit): () -> Unit {
    val runnable = Runnable(action)
    handler.postDelayed(runnable, SELECTION_TIMEOUT_MS)
    return { handler.removeCallbacks(runnable) }
  }

  override fun applicableVolume(): ApplicableVolume? {
    val attributes = playbackAttributes ?: return null
    val stream = PlaybackVolumePolicy.streamFor(attributes)
    val max = audioManager.getStreamMaxVolume(stream)
    if (max <= 0) return null
    return ApplicableVolume(streamWire(stream), audioManager.getStreamVolume(stream).toDouble() / max)
  }

  override fun ensureMinimumVolume(minimum: Double): ApplicableVolume? {
    val attributes = playbackAttributes ?: return null
    val stream = PlaybackVolumePolicy.streamFor(attributes)
    val max = audioManager.getStreamMaxVolume(stream)
    if (max <= 0) return null
    val current = audioManager.getStreamVolume(stream)
    val target = PlaybackVolumePolicy.levelWithFloor(current, max, minimum)
    if (current < target) {
      audioManager.setStreamVolume(stream, target, AudioManager.FLAG_SHOW_UI)
    }
    return applicableVolume()
  }

  @Suppress("DEPRECATION")
  private fun stopLegacySco() {
    if (legacyScoConnected || audioManager.isBluetoothScoOn) {
      audioManager.stopBluetoothSco()
      audioManager.isBluetoothScoOn = false
    }
    legacyScoConnected = false
  }

  private fun streamWire(stream: Int): String = when (stream) {
    AudioManager.STREAM_VOICE_CALL -> "voice_call"
    AudioManager.STREAM_MUSIC -> "music"
    AudioManager.STREAM_SYSTEM -> "system"
    else -> "other"
  }
  private companion object {
    const val SELECTION_TIMEOUT_MS = 4_000L
  }
}
