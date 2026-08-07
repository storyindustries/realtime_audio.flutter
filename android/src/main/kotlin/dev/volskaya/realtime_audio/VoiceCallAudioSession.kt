package dev.volskaya.realtime_audio

import android.media.AudioAttributes
import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
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
  fun routeForType(type: Int): OutputRoute = when (type) {
    AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> OutputRoute.SPEAKER
    AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> OutputRoute.RECEIVER
    AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
    AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
    AudioDeviceInfo.TYPE_BLE_HEADSET,
    AudioDeviceInfo.TYPE_BLE_SPEAKER,
    AudioDeviceInfo.TYPE_HEARING_AID -> OutputRoute.BLUETOOTH
    AudioDeviceInfo.TYPE_WIRED_HEADSET,
    AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
    AudioDeviceInfo.TYPE_USB_HEADSET,
    AudioDeviceInfo.TYPE_USB_DEVICE -> OutputRoute.WIRED
    else -> OutputRoute.OTHER
  }

  fun desiredCommunicationDeviceType(
    requested: OutputRoute?,
    activeType: Int?,
    availableTypes: List<Int>,
  ): Int? {
    if (requested != null) {
      return availableTypes.firstOrNull { routeForType(it) == requested }
    }
    if (activeType != null && activeType in availableTypes &&
      (activeType in EXTERNAL_TYPES || routeForType(activeType) == OutputRoute.OTHER)
    ) {
      return activeType
    }
    return availableTypes.firstOrNull { routeForType(it) == OutputRoute.BLUETOOTH }
      ?: availableTypes.firstOrNull { routeForType(it) == OutputRoute.WIRED }
      ?: AudioDeviceInfo.TYPE_BUILTIN_SPEAKER.takeIf { it in availableTypes }
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
 * MODE_IN_COMMUNICATION + audio focus for the
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
  context: Context,
  private val audioManager: AudioManager,
  private val ledger: CommSessionLedger = sharedLedger,
  handler: Handler = Handler(Looper.getMainLooper()),
  private val onOutputStateChanged: (OutputRouteState) -> Unit = {},
  private val sharedOutputRoutes: SharedOutputRouteController = processOutputRoutes,
) {
  private val audioSystem = AndroidCommunicationAudioSystem(context, audioManager, handler)
  private var active = false
  private var outputRouteLease: SharedOutputRouteController.Lease? = null
  private var retainedOutputRoute: OutputRoute? = null
  private var lastOutputRouteState = inactiveOutputRouteState()

  /** Whether the process-global comm configuration was applied successfully. */
  var configurationApplied = false
    private set

  fun enter(): Boolean {
    if (active) return configurationApplied
    active = true
    if (!ledger.acquire()) {
      // Another engine already configured the process-global state.
      configurationApplied = true
      acquireOutputRoutes()
      return true
    }
    configurationApplied = runCatching {
      audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
      requestFocus()
      acquireOutputRoutes()
      true
    }.onFailure { e ->
      runCatching { Log.e(TAG, "voice-call session enter failed: ${e.message}") }
    }.getOrDefault(false)
    return configurationApplied
  }

  fun exit() {
    if (!active) return
    active = false
    retainedOutputRoute = lastOutputRouteState.requested
    outputRouteLease?.let(sharedOutputRoutes::release)
    outputRouteLease = null
    lastOutputRouteState = inactiveOutputRouteState(retainedOutputRoute)
    onOutputStateChanged(lastOutputRouteState)
    val restore = ledger.release()
    configurationApplied = false
    if (!restore) return
    runCatching {
      abandonFocus()
      audioSystem.clearDevice()
      audioManager.mode = AudioManager.MODE_NORMAL
    }.onFailure { e -> runCatching { Log.w(TAG, "voice-call session exit failed: ${e.message}") } }
  }

  fun setPlaybackAttributes(attributes: AudioAttributes) {
    audioSystem.setPlaybackAttributes(attributes)
  }

  fun outputRouteState(): OutputRouteState = if (active && outputRouteLease != null) {
    sharedOutputRoutes.snapshot()
  } else {
    lastOutputRouteState
  }

  fun selectOutputRoute(route: OutputRoute?): OutputRouteState {
    retainedOutputRoute = route
    if (!active || outputRouteLease == null) {
      lastOutputRouteState = inactiveOutputRouteState(route)
      onOutputStateChanged(lastOutputRouteState)
      return lastOutputRouteState
    }
    return sharedOutputRoutes.select(route)
  }

  fun ensureMinimumPlaybackVolume(minimum: Double): OutputRouteState = if (active && outputRouteLease != null) {
    sharedOutputRoutes.ensureMinimumVolume(minimum)
  } else {
    lastOutputRouteState
  }

  private fun acquireOutputRoutes() {
    val acquisition = sharedOutputRoutes.acquire(audioSystem, ::handleOutputRouteState)
    outputRouteLease = acquisition.lease
    lastOutputRouteState = acquisition.state
    if (acquisition.isFirst && retainedOutputRoute != null) {
      sharedOutputRoutes.select(retainedOutputRoute)
    }
  }

  private fun handleOutputRouteState(state: OutputRouteState) {
    lastOutputRouteState = state
    retainedOutputRoute = state.requested
    onOutputStateChanged(state)
  }

  private fun inactiveOutputRouteState(requested: OutputRoute? = retainedOutputRoute): OutputRouteState =
    OutputRouteState(
      active = null,
      available = emptyList(),
      requested = requested,
      selectionResult = OutputRouteSelectionResult.UNAVAILABLE,
      volume = null,
    )

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
      processFocusRequest = request
      audioManager.requestAudioFocus(request)
    } else {
      @Suppress("DEPRECATION")
      audioManager.requestAudioFocus(null, AudioManager.STREAM_VOICE_CALL, AudioManager.AUDIOFOCUS_GAIN)
    }
  }

  private fun abandonFocus() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      processFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
      processFocusRequest = null
    } else {
      @Suppress("DEPRECATION")
      audioManager.abandonAudioFocus(null)
    }
  }

  private companion object {
    const val TAG = "RealtimeAudio"

    /** One process-global ledger — the state it guards is process-global. */
    val sharedLedger = CommSessionLedger()

    /** Communication routing is process-global for the same reason. */
    val processOutputRoutes = SharedOutputRouteController()

    /** The final holder must abandon the request created by the first holder. */
    var processFocusRequest: AudioFocusRequest? = null
  }
}
