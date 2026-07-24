package dev.volskaya.realtime_audio

import android.util.Log

/**
 * Seam over the WebRTC APM JNI surface so [WebRtcApm]'s lifecycle serialization
 * is deterministically testable on the JVM (see WebRtcApmConcurrencyTest) —
 * the real implementation is [WebRtcApmJni].
 */
interface ApmNativeBridge {
  fun create(
    captureSampleRate: Int,
    renderSampleRate: Int,
    aecEnabled: Boolean,
    nsEnabled: Boolean,
    agcEnabled: Boolean,
    mobileAec: Boolean,
  ): Long

  fun destroy(ptr: Long)

  fun setStreamDelay(ptr: Long, delayMs: Int)

  fun processCapture(ptr: Long, audioData: ByteArray): ByteArray

  fun processRender(ptr: Long, audioData: ByteArray)

  /** AEC3-only echo-return-loss-enhancement metric; null while unreported. */
  fun echoReturnLossEnhancementDb(ptr: Long): Double?
}

/**
 * The JNI-backed bridge. JNI symbol names are bound to this object's
 * fully-qualified name (`Java_dev_volskaya_realtime_1audio_WebRtcApmJni_*`,
 * see android/src/main/cpp/webrtc_apm_jni.cpp) — keep them in lockstep.
 */
object WebRtcApmJni : ApmNativeBridge {
  private const val TAG = "WebRtcApm"

  val loaded: Boolean =
    runCatching { System.loadLibrary("webrtc_apm_jni") }
      // Inner runCatching: android.util.Log is unmocked on the JVM (unit tests).
      .onFailure { e -> runCatching { Log.e(TAG, "Failed to load webrtc_apm_jni: ${e.message}") } }
      .isSuccess

  override fun create(
    captureSampleRate: Int,
    renderSampleRate: Int,
    aecEnabled: Boolean,
    nsEnabled: Boolean,
    agcEnabled: Boolean,
    mobileAec: Boolean,
  ): Long =
    if (loaded) {
      nativeCreate(captureSampleRate, renderSampleRate, aecEnabled, nsEnabled, agcEnabled, mobileAec)
    } else {
      0L
    }

  override fun destroy(ptr: Long) = nativeDestroy(ptr)

  override fun setStreamDelay(ptr: Long, delayMs: Int) = nativeSetStreamDelay(ptr, delayMs)

  override fun processCapture(ptr: Long, audioData: ByteArray): ByteArray =
    nativeProcessCapture(ptr, audioData)

  override fun processRender(ptr: Long, audioData: ByteArray) = nativeProcessRender(ptr, audioData)

  override fun echoReturnLossEnhancementDb(ptr: Long): Double? =
    nativeGetErleDb(ptr).takeIf { !it.isNaN() }

  private external fun nativeCreate(
    captureSampleRate: Int,
    renderSampleRate: Int,
    aecEnabled: Boolean,
    nsEnabled: Boolean,
    agcEnabled: Boolean,
    mobileAec: Boolean,
  ): Long

  private external fun nativeDestroy(ptr: Long)

  private external fun nativeSetStreamDelay(ptr: Long, delayMs: Int)

  private external fun nativeProcessCapture(ptr: Long, audioData: ByteArray): ByteArray

  private external fun nativeProcessRender(ptr: Long, audioData: ByteArray)

  /** Returns NaN while the APM has no ERLE report (AECM, or too early). */
  private external fun nativeGetErleDb(ptr: Long): Double
}
