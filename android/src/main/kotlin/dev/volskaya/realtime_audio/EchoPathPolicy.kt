package dev.volskaya.realtime_audio

/** Which echo-control mechanism the engine is actually driving (read-back truth). */
enum class EchoMechanism(val wire: String) {
  /** Hardware/OEM AcousticEchoCanceler on the platform voice-call path. */
  PLATFORM_AEC("platform_aec"),

  /** Bundled WebRTC APM (software) — AEC3 on the shipped policy. */
  WEBRTC_APM("webrtc_apm"),

  /** No verifiable echo cancellation — the app must hold half-duplex. */
  NONE("none"),
}

/** Abstract capture source names, mapped to MediaRecorder.AudioSource by the engine. */
enum class CaptureSource {
  /** Vendor voice-call preprocessing (feeds the hardware AEC). */
  VOICE_COMMUNICATION,

  /** Unprocessed/linear capture — what a software canceller needs. */
  VOICE_RECOGNITION,

  /** Plain mic (no voice processing requested). */
  MIC,
}

/** Pure decision record for one engine configuration. */
data class EchoPathDecision(
  val mechanism: EchoMechanism,
  /** AudioManager.MODE_IN_COMMUNICATION for the call (else MODE_NORMAL). */
  val communicationMode: Boolean,
  /** USAGE_VOICE_COMMUNICATION/CONTENT_TYPE_SPEECH playback (else media). */
  val voiceCommunicationPlayback: Boolean,
  val captureSource: CaptureSource,
  val attachHardwareAec: Boolean,
  val useApm: Boolean,
  /** AECM (true) vs AEC3 (false). Only meaningful when [useApm]. */
  val apmMobileAec: Boolean = false,
  /** Only meaningful when [useApm]. */
  val apmAgcEnabled: Boolean = false,
)

/**
 * Decides Android's echo-control architecture (2026-07-24 Android echo RCA).
 *
 * iOS is echo-clean because playback + capture share the OS voice unit (VPIO)
 * — the OS holds the far-end reference and the OEM tunes the canceller. The
 * Android analogue is the platform voice-call configuration with the device's
 * hardware AcousticEchoCanceler; the software APM is the fallback, and then
 * as AEC3 over an unprocessed capture source. The March→July stack (AECM +
 * static delay + vendor-preprocessed capture + media-usage playback outside
 * the voice path) is exactly the combination this policy forbids.
 *
 * Pure and total: same inputs → same decision. A runtime hardware-attach
 * failure re-enters with `hardwareAecAvailable = false`.
 */
object EchoPathPolicy {
  fun decide(
    voiceProcessing: Boolean,
    hardwareAecAvailable: Boolean,
    apmLoaded: Boolean,
  ): EchoPathDecision {
    if (!voiceProcessing) {
      return EchoPathDecision(
        mechanism = EchoMechanism.NONE,
        communicationMode = false,
        voiceCommunicationPlayback = false,
        captureSource = CaptureSource.MIC,
        attachHardwareAec = false,
        useApm = false,
      )
    }
    if (hardwareAecAvailable) {
      return EchoPathDecision(
        mechanism = EchoMechanism.PLATFORM_AEC,
        communicationMode = true,
        voiceCommunicationPlayback = true,
        captureSource = CaptureSource.VOICE_COMMUNICATION,
        attachHardwareAec = true,
        // The OEM voice path owns AEC/NS/AGC — a stacked software APM
        // double-processes the signal and mangles the echo path.
        useApm = false,
      )
    }
    if (apmLoaded) {
      return EchoPathDecision(
        mechanism = EchoMechanism.WEBRTC_APM,
        communicationMode = true,
        voiceCommunicationPlayback = true,
        captureSource = CaptureSource.VOICE_RECOGNITION,
        attachHardwareAec = false,
        useApm = true,
        apmMobileAec = false,
        apmAgcEnabled = true,
      )
    }
    return EchoPathDecision(
      mechanism = EchoMechanism.NONE,
      communicationMode = true,
      voiceCommunicationPlayback = true,
      captureSource = CaptureSource.VOICE_COMMUNICATION,
      attachHardwareAec = false,
      useApm = false,
    )
  }
}
