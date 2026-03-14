#include <jni.h>
#include <cstring>
#include <cstdlib>
#include "webrtc-audio-processing/webrtc/wrapper/webrtc_apm_wrapper.h"
#include "webrtc-audio-processing/webrtc/modules/audio_processing/include/audio_processing.h"

// Internal handle that stores the APM instance and stream configurations.
struct ApmHandle {
    webrtc::AudioProcessing* apm = nullptr;
    webrtc::StreamConfig capture_config;
    webrtc::StreamConfig render_config;
    int capture_frame_size = 0; // samples per 10ms frame (capture)
    int render_frame_size = 0;  // samples per 10ms frame (render)
};

extern "C" {

JNIEXPORT jlong JNICALL
Java_dev_volskaya_realtime_1audio_WebRtcApm_nativeCreate(
    JNIEnv* env, jobject /* this */,
    jint captureSampleRate, jint renderSampleRate,
    jboolean aecEnabled, jboolean nsEnabled, jboolean agcEnabled) {

    auto* handle = new ApmHandle();
    handle->apm = webrtc::AudioProcessingBuilder().Create();

    handle->capture_config = webrtc::StreamConfig(captureSampleRate, 1);
    handle->render_config = webrtc::StreamConfig(renderSampleRate, 1);
    handle->capture_frame_size = captureSampleRate / 100; // 10ms
    handle->render_frame_size = renderSampleRate / 100;   // 10ms

    auto config = webrtc::AudioProcessing::Config();
    config.echo_canceller.enabled = aecEnabled;
    config.echo_canceller.mobile_mode = true; // lighter CPU for mobile
    config.noise_suppression.enabled = nsEnabled;
    config.noise_suppression.level =
        webrtc::AudioProcessing::Config::NoiseSuppression::kHigh;
    config.high_pass_filter.enabled = true;
    config.gain_controller1.enabled = agcEnabled;
    config.gain_controller1.mode =
        webrtc::AudioProcessing::Config::GainController1::kAdaptiveDigital;

    handle->apm->ApplyConfig(config);

    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT void JNICALL
Java_dev_volskaya_realtime_1audio_WebRtcApm_nativeDestroy(
    JNIEnv* env, jobject /* this */, jlong ptr) {

    auto* handle = reinterpret_cast<ApmHandle*>(ptr);
    if (handle) {
        delete handle->apm;
        delete handle;
    }
}

// Process capture (near-end / microphone) audio through APM.
// Input: int16 PCM mono. Output: int16 PCM mono (echo-cancelled, denoised).
// Processes in 10ms frames internally.
JNIEXPORT jbyteArray JNICALL
Java_dev_volskaya_realtime_1audio_WebRtcApm_nativeProcessCapture(
    JNIEnv* env, jobject /* this */, jlong ptr, jbyteArray audioData) {

    auto* handle = reinterpret_cast<ApmHandle*>(ptr);
    if (!handle || !handle->apm) return audioData;

    jsize dataLen = env->GetArrayLength(audioData);
    if (dataLen == 0) return audioData;

    jbyte* inputBytes = env->GetByteArrayElements(audioData, nullptr);
    auto* inputSamples = reinterpret_cast<int16_t*>(inputBytes);
    int totalSamples = dataLen / 2; // 16-bit samples
    int frameSize = handle->capture_frame_size;

    if (frameSize <= 0) {
        env->ReleaseByteArrayElements(audioData, inputBytes, 0);
        return audioData;
    }

    // Allocate float buffer for one frame.
    auto* floatBuf = new float[frameSize];

    // Process in 10ms frames.
    int offset = 0;
    while (offset + frameSize <= totalSamples) {
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
// Must be called BEFORE processCapture for each corresponding time segment.
JNIEXPORT void JNICALL
Java_dev_volskaya_realtime_1audio_WebRtcApm_nativeProcessRender(
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

} // extern "C"
