package dev.volskaya.realtime_audio

import android.util.Log

class WebRtcApm(
    captureSampleRate: Int,
    renderSampleRate: Int,
    aecEnabled: Boolean = true,
    nsEnabled: Boolean = true,
    agcEnabled: Boolean = true,
) {
    private var nativePtr: Long = 0L

    init {
        try {
            System.loadLibrary("webrtc_apm_jni")
            nativePtr = nativeCreate(
                captureSampleRate, renderSampleRate,
                aecEnabled, nsEnabled, agcEnabled
            )
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "Failed to load webrtc_apm_jni: ${e.message}")
        }
    }

    val isAvailable: Boolean get() = nativePtr != 0L

    fun processCapture(audioData: ByteArray): ByteArray {
        if (nativePtr == 0L) return audioData
        return nativeProcessCapture(nativePtr, audioData)
    }

    fun processRender(audioData: ByteArray) {
        if (nativePtr == 0L) return
        nativeProcessRender(nativePtr, audioData)
    }

    fun release() {
        if (nativePtr != 0L) {
            nativeDestroy(nativePtr)
            nativePtr = 0L
        }
    }

    private external fun nativeCreate(
        captureSampleRate: Int, renderSampleRate: Int,
        aecEnabled: Boolean, nsEnabled: Boolean, agcEnabled: Boolean
    ): Long

    private external fun nativeDestroy(ptr: Long)
    private external fun nativeProcessCapture(ptr: Long, audioData: ByteArray): ByteArray
    private external fun nativeProcessRender(ptr: Long, audioData: ByteArray)

    companion object {
        private const val TAG = "WebRtcApm"
    }
}
