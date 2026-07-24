package dev.volskaya.realtime_audio

import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
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
 * Process-global refcount for the communication audio session.
 * `AudioManager.mode` / communication routing are process-global while engines
 * are per-instance — without this ledger a second engine's exit() clobbers the
 * first engine's in-call voice route (last-exit-wins). Only the FIRST hold
 * configures; only the LAST release restores. Unit-tested.
 */
class CommSessionLedger {
  private var holders = 0

  /** True when this hold is the first — the caller should configure. */
  @Synchronized
  fun acquire(): Boolean = ++holders == 1

  /** True when this release drops the last hold — the caller should restore. */
  @Synchronized
  fun release(): Boolean {
    if (holders == 0) return false
    return --holders == 0
  }
}

/**
 * Owns the AudioManager voice-call state for the platform echo path
 * (2026-07-24 Android echo RCA): MODE_IN_COMMUNICATION + audio focus for the
 * call's duration, speaker as the communication device when no external device
 * is attached (comm mode defaults to the earpiece on phones), legacy Bluetooth
 * SCO on pre-31 (voice audio does not auto-route to BT there), all restored on
 * exit. Per-instance idempotent; process-global state is refcounted through
 * [CommSessionLedger] so overlapping engine lifetimes cannot clobber a live
 * call's route.
 *
 * [enter] returns whether the process-global configuration is ACTIVE (mode
 * switch applied, or already held). A false return means the voice-call
 * context could not be established (e.g. missing MODIFY_AUDIO_SETTINGS in a
 * consumer that stripped the plugin's manifest permission) — the caller must
 * NOT claim the hardware echo path on top of it, because a hardware AEC
 * without voice-call routing has no far-end reference and cancels nothing.
 */
class VoiceCallAudioSession(
  private val audioManager: AudioManager,
  private val ledger: CommSessionLedger = sharedLedger,
) {
  private var active = false
  private var focusRequest: AudioFocusRequest? = null

  /** Whether the process-global comm configuration was applied successfully. */
  var configurationApplied = false
    private set

  fun enter(): Boolean {
    if (active) return configurationApplied
    active = true
    if (!ledger.acquire()) {
      // Another engine already configured the process-global state.
      configurationApplied = true
      return true
    }
    configurationApplied = runCatching {
      audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
      requestFocus()
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val available = audioManager.availableCommunicationDevices
        val forcedType = CommRoutePolicy.forcedCommunicationDeviceType(available.map { it.type })
        if (forcedType != null) {
          available.firstOrNull { it.type == forcedType }?.let { audioManager.setCommunicationDevice(it) }
        }
      } else {
        @Suppress("DEPRECATION")
        val externalPresent =
          audioManager.isWiredHeadsetOn || audioManager.isBluetoothScoOn || audioManager.isBluetoothA2dpOn
        if (externalPresent) {
          // Pre-31 voice audio does not auto-route to Bluetooth: SCO must be
          // started explicitly (best-effort; connection completes async).
          @Suppress("DEPRECATION")
          if (audioManager.isBluetoothScoAvailableOffCall) {
            @Suppress("DEPRECATION")
            audioManager.startBluetoothSco()
            audioManager.isBluetoothScoOn = true
          }
        } else {
          @Suppress("DEPRECATION")
          audioManager.isSpeakerphoneOn = true
        }
      }
      true
    }.onFailure { e ->
      runCatching { Log.e(TAG, "voice-call session enter failed: ${e.message}") }
    }.getOrDefault(false)
    return configurationApplied
  }

  fun exit() {
    if (!active) return
    active = false
    val restore = ledger.release()
    configurationApplied = false
    if (!restore) return
    runCatching {
      abandonFocus()
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        audioManager.clearCommunicationDevice()
      } else {
        @Suppress("DEPRECATION")
        if (audioManager.isBluetoothScoOn) {
          @Suppress("DEPRECATION")
          audioManager.stopBluetoothSco()
          audioManager.isBluetoothScoOn = false
        }
        @Suppress("DEPRECATION")
        audioManager.isSpeakerphoneOn = false
      }
      audioManager.mode = AudioManager.MODE_NORMAL
    }.onFailure { e -> runCatching { Log.w(TAG, "voice-call session exit failed: ${e.message}") } }
  }

  /// A voice call owns audio focus: other apps' media pauses/ducks (an
  /// uncancellable echo source otherwise) and the OS tells them we're live.
  private fun requestFocus() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
        .setAudioAttributes(
          AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build(),
        )
        .build()
      focusRequest = request
      audioManager.requestAudioFocus(request)
    } else {
      @Suppress("DEPRECATION")
      audioManager.requestAudioFocus(null, AudioManager.STREAM_VOICE_CALL, AudioManager.AUDIOFOCUS_GAIN)
    }
  }

  private fun abandonFocus() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
      focusRequest = null
    } else {
      @Suppress("DEPRECATION")
      audioManager.abandonAudioFocus(null)
    }
  }

  private companion object {
    const val TAG = "RealtimeAudio"

    /** One process-global ledger — the state it guards is process-global. */
    val sharedLedger = CommSessionLedger()
  }
}
