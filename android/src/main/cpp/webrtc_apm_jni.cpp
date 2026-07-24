#include <jni.h>
#include <android/log.h>
#include <cstring>
#include <cstdlib>
#include <limits>
#include "webrtc-audio-processing/webrtc/modules/audio_processing/include/audio_processing.h"

#define TAG "WebRtcApm"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)

struct ApmHandle {
    webrtc::AudioProcessing* apm = nullptr;
    webrtc::StreamConfig capture_config;
    webrtc::StreamConfig render_config;
    int capture_frame_size = 0; // samples per 10ms frame (capture)
    int render_frame_size = 0;  // samples per 10ms frame (render)
    int stream_delay_ms = 100;  // estimated audio pipeline delay
};

extern "C" {

JNIEXPORT jlong JNICALL
Java_dev_volskaya_realtime_1audio_WebRtcApmJni_nativeCreate(
    JNIEnv* env, jobject /* this */,
    jint captureSampleRate, jint renderSampleRate,
    jboolean aecEnabled, jboolean nsEnabled, jboolean agcEnabled,
    jboolean mobileAec) {

    auto* handle = new ApmHandle();
    handle->apm = webrtc::AudioProcessingBuilder().Create();

    handle->capture_config = webrtc::StreamConfig(captureSampleRate, 1);
    handle->render_config = webrtc::StreamConfig(renderSampleRate, 1);
    handle->capture_frame_size = captureSampleRate / 100; // 10ms
    handle->render_frame_size = renderSampleRate / 100;   // 10ms

    auto config = webrtc::AudioProcessing::Config();

    // Echo cancellation. mobile_mode=true selects AECM (legacy suppressor,
    // static-delay dependent, band-limited); false selects AEC3, whose
    // adaptive delay estimator + linear filter is what actually converges on
    // Android's variable-latency output paths (2026-07-24 Android echo RCA).
    // The caller picks; see EchoPathPolicy on the Kotlin side.
    config.echo_canceller.enabled = aecEnabled;
    config.echo_canceller.mobile_mode = mobileAec;
    config.echo_canceller.enforce_high_pass_filtering = true;

    // Noise suppression at very high level for voice calls.
    config.noise_suppression.enabled = nsEnabled;
    config.noise_suppression.level =
        webrtc::AudioProcessing::Config::NoiseSuppression::kVeryHigh;

    // High-pass filter removes DC offset and low-frequency rumble.
    config.high_pass_filter.enabled = true;

    // AGC2 (next-gen) with adaptive digital mode — better than AGC1
    // for pure-digital pipelines where we don't control analog gain.
    config.gain_controller1.enabled = false;
    config.gain_controller2.enabled = agcEnabled;
    if (agcEnabled) {
        config.gain_controller2.adaptive_digital.enabled = true;
    }

    handle->apm->ApplyConfig(config);
    handle->apm->Initialize();

    LOGI("APM created: capture=%dHz render=%dHz aec=%d ns=%d agc=%d mobileAec=%d",
         captureSampleRate, renderSampleRate, aecEnabled, nsEnabled, agcEnabled, mobileAec);

    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT void JNICALL
Java_dev_volskaya_realtime_1audio_WebRtcApmJni_nativeDestroy(
    JNIEnv* env, jobject /* this */, jlong ptr) {

    auto* handle = reinterpret_cast<ApmHandle*>(ptr);
    if (handle) {
        LOGI("APM destroyed");
        delete handle->apm;
        delete handle;
    }
}

JNIEXPORT void JNICALL
Java_dev_volskaya_realtime_1audio_WebRtcApmJni_nativeSetStreamDelay(
    JNIEnv* env, jobject /* this */, jlong ptr, jint delayMs) {

    auto* handle = reinterpret_cast<ApmHandle*>(ptr);
    if (handle) {
        handle->stream_delay_ms = delayMs;
    }
}

// Process capture (near-end / microphone) audio through APM.
JNIEXPORT jbyteArray JNICALL
Java_dev_volskaya_realtime_1audio_WebRtcApmJni_nativeProcessCapture(
    JNIEnv* env, jobject /* this */, jlong ptr, jbyteArray audioData) {

    auto* handle = reinterpret_cast<ApmHandle*>(ptr);
    if (!handle || !handle->apm) return audioData;

    jsize dataLen = env->GetArrayLength(audioData);
    if (dataLen == 0) return audioData;

    jbyte* inputBytes = env->GetByteArrayElements(audioData, nullptr);
    auto* inputSamples = reinterpret_cast<int16_t*>(inputBytes);
    int totalSamples = dataLen / 2;
    int frameSize = handle->capture_frame_size;

    if (frameSize <= 0) {
        env->ReleaseByteArrayElements(audioData, inputBytes, 0);
        return audioData;
    }

    auto* floatBuf = new float[frameSize];

    int offset = 0;
    while (offset + frameSize <= totalSamples) {
        // Set the estimated delay before each frame.
        handle->apm->set_stream_delay_ms(handle->stream_delay_ms);

        // Convert int16 to float [-1.0, 1.0].
        for (int i = 0; i < frameSize; i++) {
            floatBuf[i] = static_cast<float>(inputSamples[offset + i]) / 32768.0f;
        }

        float* channelPtr = floatBuf;
        const float* constChannelPtr = floatBuf;
        handle->apm->ProcessStream(
            &constChannelPtr,
            handle->capture_config,
            handle->capture_config,
            &channelPtr);

        // Convert float back to int16.
        for (int i = 0; i < frameSize; i++) {
            float val = floatBuf[i] * 32768.0f;
            if (val > 32767.0f) val = 32767.0f;
            if (val < -32768.0f) val = -32768.0f;
            inputSamples[offset + i] = static_cast<int16_t>(val);
        }

        offset += frameSize;
    }

    delete[] floatBuf;
    env->ReleaseByteArrayElements(audioData, inputBytes, 0);
    return audioData;
}

// Feed render (far-end / speaker playback) audio into APM as echo reference.
JNIEXPORT void JNICALL
Java_dev_volskaya_realtime_1audio_WebRtcApmJni_nativeProcessRender(
    JNIEnv* env, jobject /* this */, jlong ptr, jbyteArray audioData) {

    auto* handle = reinterpret_cast<ApmHandle*>(ptr);
    if (!handle || !handle->apm) return;

    jsize dataLen = env->GetArrayLength(audioData);
    if (dataLen == 0) return;

    jbyte* inputBytes = env->GetByteArrayElements(audioData, nullptr);
    auto* inputSamples = reinterpret_cast<int16_t*>(inputBytes);
    int totalSamples = dataLen / 2;
    int frameSize = handle->render_frame_size;

    if (frameSize <= 0) {
        env->ReleaseByteArrayElements(audioData, inputBytes, JNI_ABORT);
        return;
    }

    auto* floatBuf = new float[frameSize];

    int offset = 0;
    while (offset + frameSize <= totalSamples) {
        for (int i = 0; i < frameSize; i++) {
            floatBuf[i] = static_cast<float>(inputSamples[offset + i]) / 32768.0f;
        }

        float* channelPtr = floatBuf;
        const float* constChannelPtr = floatBuf;
        handle->apm->ProcessReverseStream(
            &constChannelPtr,
            handle->render_config,
            handle->render_config,
            &channelPtr);

        offset += frameSize;
    }

    delete[] floatBuf;
    env->ReleaseByteArrayElements(audioData, inputBytes, JNI_ABORT);
}

// AEC3 echo-return-loss-enhancement (dB) from the APM's own statistics — the
// measured proof the canceller is actually cancelling (not merely running).
// Returns NaN while unreported: AECM never reports it, and AEC3 needs a few
// seconds of far-end + near-end audio before the estimate exists.
JNIEXPORT jdouble JNICALL
Java_dev_volskaya_realtime_1audio_WebRtcApmJni_nativeGetErleDb(
    JNIEnv* env, jobject /* this */, jlong ptr) {

    auto* handle = reinterpret_cast<ApmHandle*>(ptr);
    if (!handle || !handle->apm) return std::numeric_limits<double>::quiet_NaN();

    auto stats = handle->apm->GetStatistics();
    if (!stats.echo_return_loss_enhancement.has_value()) {
        return std::numeric_limits<double>::quiet_NaN();
    }
    return *stats.echo_return_loss_enhancement;
}

} // extern "C"
