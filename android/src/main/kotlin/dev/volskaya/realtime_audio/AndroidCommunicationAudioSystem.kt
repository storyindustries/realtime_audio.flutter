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
  private val SELECTABLE_TYPES = setOf(
    AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
    AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
    AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
    AudioDeviceInfo.TYPE_WIRED_HEADSET,
    AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
    AudioDeviceInfo.TYPE_USB_HEADSET,
    AudioDeviceInfo.TYPE_USB_DEVICE,
  )

  fun availableTypes(connectedOutputTypes: List<Int>): List<Int> {
    val selectableTypes = connectedOutputTypes.filter { it in SELECTABLE_TYPES }
    val wiredConnected = selectableTypes.any {
      CommRoutePolicy.routeForType(it) == OutputRoute.WIRED
    }
    return selectableTypes
      .filterNot { wiredConnected && it == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }
      .distinct()
  }
}

object LegacyActiveRoutePolicy {
  fun resolve(
    bluetoothScoActive: Boolean,
    speakerphoneOn: Boolean,
    wiredConnected: Boolean,
  ): OutputRoute = when {
    bluetoothScoActive -> OutputRoute.BLUETOOTH
    speakerphoneOn -> OutputRoute.SPEAKER
    wiredConnected -> OutputRoute.WIRED
    else -> OutputRoute.RECEIVER
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
    val activeRoute = LegacyActiveRoutePolicy.resolve(
      bluetoothScoActive = legacyScoConnected || audioManager.isBluetoothScoOn,
      speakerphoneOn = audioManager.isSpeakerphoneOn,
      wiredConnected = audioManager.isWiredHeadsetOn,
    )
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
