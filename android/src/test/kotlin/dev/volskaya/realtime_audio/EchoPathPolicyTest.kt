package dev.volskaya.realtime_audio

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * The Android echo-control architecture decision (2026-07-24 Android echo RCA).
 *
 * iOS works because playback + capture share the OS voice-processing unit
 * (VPIO). Android must mirror that: when the device offers a hardware
 * AcousticEchoCanceler, run the platform voice-call configuration
 * (MODE_IN_COMMUNICATION, USAGE_VOICE_COMMUNICATION playback,
 * VOICE_COMMUNICATION capture, hw AEC attached — the OEM speakerphone tuning,
 * software APM off). Only when hardware AEC is absent fall back to the
 * software APM — and then as AEC3 (adaptive delay estimator) over an
 * UNPROCESSED capture source, never AECM-over-vendor-preprocessed audio,
 * which is the stack that shipped March→July and cancelled nothing.
 */
class EchoPathPolicyTest {

  @Test
  fun `no voice processing keeps the plain media path`() {
    val d = EchoPathPolicy.decide(voiceProcessing = false, hardwareAecAvailable = true, apmLoaded = true)
    assertEquals(EchoMechanism.NONE, d.mechanism)
    assertFalse(d.communicationMode)
    assertFalse(d.voiceCommunicationPlayback)
    assertEquals(CaptureSource.MIC, d.captureSource)
    assertFalse(d.attachHardwareAec)
    assertFalse(d.useApm)
  }

  @Test
  fun `hardware aec available drives the platform voice-call path`() {
    val d = EchoPathPolicy.decide(voiceProcessing = true, hardwareAecAvailable = true, apmLoaded = true)
    assertEquals(EchoMechanism.PLATFORM_AEC, d.mechanism)
    assertTrue(d.communicationMode)
    assertTrue(d.voiceCommunicationPlayback)
    assertEquals(CaptureSource.VOICE_COMMUNICATION, d.captureSource)
    assertTrue(d.attachHardwareAec)
    // The OEM voice path owns AEC/NS/AGC — stacking the software APM on top
    // double-processes and mangles the echo path.
    assertFalse(d.useApm)
  }

  @Test
  fun `no hardware aec falls back to software aec3 over unprocessed capture`() {
    val d = EchoPathPolicy.decide(voiceProcessing = true, hardwareAecAvailable = false, apmLoaded = true)
    assertEquals(EchoMechanism.WEBRTC_APM, d.mechanism)
    // Voice-call routing still applies (latency + comm-device routing)…
    assertTrue(d.communicationMode)
    assertTrue(d.voiceCommunicationPlayback)
    // …but capture must be linear/unprocessed for a software canceller:
    // vendor VOICE_COMMUNICATION preprocessing is nonlinear and defeats it.
    assertEquals(CaptureSource.VOICE_RECOGNITION, d.captureSource)
    assertFalse(d.attachHardwareAec)
    assertTrue(d.useApm)
    // AEC3, never AECM: the adaptive delay estimator is the point.
    assertFalse(d.apmMobileAec)
    // Raw capture needs software gain control.
    assertTrue(d.apmAgcEnabled)
  }

  @Test
  fun `neither hardware nor apm reports an honest none`() {
    val d = EchoPathPolicy.decide(voiceProcessing = true, hardwareAecAvailable = false, apmLoaded = false)
    assertEquals(EchoMechanism.NONE, d.mechanism)
    // Voice-comm source recovers whatever best-effort vendor processing
    // exists, but the read-back must NOT claim a mechanism it cannot verify —
    // the app then holds the half-duplex posture instead of trusting a ghost.
    assertTrue(d.communicationMode)
    assertEquals(CaptureSource.VOICE_COMMUNICATION, d.captureSource)
    assertFalse(d.attachHardwareAec)
    assertFalse(d.useApm)
  }

  @Test
  fun `hardware attach failure re-decides onto the software path`() {
    val first = EchoPathPolicy.decide(voiceProcessing = true, hardwareAecAvailable = true, apmLoaded = true)
    assertTrue(first.attachHardwareAec)
    // Runtime AcousticEchoCanceler.create() returning null re-enters decide
    // with hardwareAecAvailable=false — same inputs, same outputs, pure.
    val fallback = EchoPathPolicy.decide(voiceProcessing = true, hardwareAecAvailable = false, apmLoaded = true)
    assertEquals(EchoMechanism.WEBRTC_APM, fallback.mechanism)
    assertTrue(fallback.useApm)
    assertFalse(fallback.apmMobileAec)
  }
}
