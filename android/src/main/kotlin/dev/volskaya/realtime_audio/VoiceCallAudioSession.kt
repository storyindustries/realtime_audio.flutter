package dev.volskaya.realtime_audio

import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.util.Log

/** Pure speaker-forcing decision for the communication route (unit-tested). */
object CommRoutePolicy {
  private val EXTERNAL_TYPES = setOf(
    AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
    AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
    AudioDeviceInfo.TYPE_BLE_HEADSET,
    AudioDeviceInfo.TYPE_BLE_SPEAKER,
    AudioDeviceInfo.TYPE_WIRED_HEADSET,
    AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
    AudioDeviceInfo.TYPE_USB_HEADSET,
    AudioDeviceInfo.TYPE_USB_DEVICE,
    AudioDeviceInfo.TYPE_HEARING_AID,
  )

  /**
   * The device type to force as communication device, or null to keep the
   * system default. Speaker is forced only when no external device is present
   * — an external device (headset/BT/USB/hearing aid) keeps system routing.
   */
  fun forcedCommunicationDeviceType(availableTypes: List<Int>): Int? {
    if (availableTypes.any { it in EXTERNAL_TYPES }) return null
    return AudioDeviceInfo.TYPE_BUILTIN_SPEAKER.takeIf { it in availableTypes }
  }
}

/**
 * Owns the AudioManager voice-call state for the platform echo path
 * (2026-07-24 Android echo RCA): MODE_IN_COMMUNICATION for the call's
 * duration, speaker as the communication device when no external device is
 * attached (comm mode defaults to the earpiece on phones), both restored on
 * exit. Idempotent: enter/exit pairs collapse.
 */
class VoiceCallAudioSession(private val audioManager: AudioManager) {
  private var active = false

  fun enter() {
    if (active) return
    active = true
    runCatching {
      audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val available = audioManager.availableCommunicationDevices
        val forcedType = CommRoutePolicy.forcedCommunicationDeviceType(available.map { it.type })
        if (forcedType != null) {
          available.firstOrNull { it.type == forcedType }?.let { audioManager.setCommunicationDevice(it) }
        }
      } else {
        @Suppress("DEPRECATION")
        if (!audioManager.isWiredHeadsetOn && !audioManager.isBluetoothScoOn && !audioManager.isBluetoothA2dpOn) {
          @Suppress("DEPRECATION")
          audioManager.isSpeakerphoneOn = true
        }
      }
    }.onFailure { e -> runCatching { Log.w(TAG, "voice-call session enter failed: ${e.message}") } }
  }

  fun exit() {
    if (!active) return
    active = false
    runCatching {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        audioManager.clearCommunicationDevice()
      } else {
        @Suppress("DEPRECATION")
        audioManager.isSpeakerphoneOn = false
      }
      audioManager.mode = AudioManager.MODE_NORMAL
    }.onFailure { e -> runCatching { Log.w(TAG, "voice-call session exit failed: ${e.message}") } }
  }

  private companion object {
    const val TAG = "RealtimeAudio"
  }
}
