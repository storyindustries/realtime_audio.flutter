package dev.volskaya.realtime_audio

import android.util.Log

/**
 * Lifecycle-owning wrapper over the WebRTC APM native bridge.
 *
 * Callers span three threads: the AudioTrack writer thread feeds the far-end
 * reference ([processRender] via ChunkAudioTrack.renderTap), capture processing
 * runs on a Dispatchers.IO coroutine ([processCapture]), and [release] runs on
 * the main thread from recorder recovery or dispose. Every native-pointer
 * check/use and the destruction are serialized on this instance's monitor
 * (`@Synchronized`): release() waits out any in-flight native call, and a
 * post-release call is a no-op — never a use-after-free (codex review of
 * biograph PR #674). Contract locked by WebRtcApmConcurrencyTest.
 */
class WebRtcApm(
    captureSampleRate: Int,
    renderSampleRate: Int,
    aecEnabled: Boolean = true,
    nsEnabled: Boolean = true,
    agcEnabled: Boolean = true,
    mobileAec: Boolean = true,
    private val bridge: ApmNativeBridge? = if (WebRtcApmJni.loaded) WebRtcApmJni else null,
) {
    private var nativePtr: Long = 0L

    init {
        if (bridge != null) {
            nativePtr = bridge.create(
                captureSampleRate, renderSampleRate,
                aecEnabled, nsEnabled, agcEnabled, mobileAec,
            )
            if (nativePtr != 0L) {
                // runCatching: android.util.Log is unmocked on the JVM (unit tests).
                runCatching {
                    Log.i(TAG, "WebRTC APM initialized (capture=${captureSampleRate}Hz, render=${renderSampleRate}Hz, mobileAec=$mobileAec)")
                }
            }
        }
    }

    val isAvailable: Boolean @Synchronized get() = nativePtr != 0L

    @Synchronized
    fun setStreamDelay(delayMs: Int) {
        if (nativePtr != 0L) {
            bridge?.setStreamDelay(nativePtr, delayMs)
        }
    }

    @Synchronized
    fun processCapture(audioData: ByteArray): ByteArray {
        if (nativePtr == 0L) return audioData
        return bridge?.processCapture(nativePtr, audioData) ?: audioData
    }

    @Synchronized
    fun processRender(audioData: ByteArray) {
        if (nativePtr == 0L) return
        bridge?.processRender(nativePtr, audioData)
    }

    @Synchronized
    fun echoReturnLossEnhancementDb(): Double? {
        if (nativePtr == 0L) return null
        return bridge?.echoReturnLossEnhancementDb(nativePtr)
    }

    @Synchronized
    fun release() {
        if (nativePtr != 0L) {
            bridge?.destroy(nativePtr)
            nativePtr = 0L
        }
    }

    companion object {
        private const val TAG = "WebRtcApm"
    }
}
