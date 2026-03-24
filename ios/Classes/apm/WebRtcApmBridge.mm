#import "WebRtcApmBridge.h"
#include <TargetConditionals.h>

#if TARGET_OS_SIMULATOR

// Simulator stubs — WebRTC APM static library is device-only (arm64).
// WebRtcApm.isAvailable will return false; all processing methods no-op.
extern "C" {

WebRtcApmHandle webrtc_apm_bridge_create(int captureSampleRate,
                                         int renderSampleRate,
                                         bool aecEnabled,
                                         bool nsEnabled,
                                         bool agcEnabled) {
    return nullptr;
}

void webrtc_apm_bridge_destroy(WebRtcApmHandle handle) {}
void webrtc_apm_bridge_set_stream_delay(WebRtcApmHandle handle, int delayMs) {}
void webrtc_apm_bridge_process_capture(WebRtcApmHandle handle, int8_t* audioData, int dataLen) {}
void webrtc_apm_bridge_process_render(WebRtcApmHandle handle, const int8_t* audioData, int dataLen) {}

} // extern "C"

#else // !TARGET_OS_SIMULATOR

#include "webrtc/modules/audio_processing/include/audio_processing.h"
#include <cstring>
#include <os/log.h>
#include <pthread.h>

static os_log_t apmLog() {
    static os_log_t log = os_log_create("dev.volskaya.realtime_audio", "APM");
    return log;
}

struct ApmHandle {
    webrtc::AudioProcessing* apm = nullptr;
    webrtc::StreamConfig captureConfig;
    webrtc::StreamConfig renderConfig;
    int captureFrameSize = 0; // samples per 10ms frame (capture)
    int renderFrameSize = 0;  // samples per 10ms frame (render)
    int streamDelayMs = 100;  // estimated audio pipeline delay

    // Separate float buffers for capture and render to avoid data races
    // (processCapture and processRender run on different audio threads).
    float* captureFloatBuf = nullptr;
    float* renderFloatBuf = nullptr;

    // Mutex serializing all APM calls. ProcessStream and ProcessReverseStream
    // must not run concurrently per WebRTC documentation.
    pthread_mutex_t mutex;
};

extern "C" {

WebRtcApmHandle webrtc_apm_bridge_create(int captureSampleRate,
                                         int renderSampleRate,
                                         bool aecEnabled,
                                         bool nsEnabled,
                                         bool agcEnabled) {
    auto* handle = new ApmHandle();

    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_setprotocol(&attr, PTHREAD_PRIO_INHERIT);
    pthread_mutex_init(&handle->mutex, &attr);
    pthread_mutexattr_destroy(&attr);

    handle->apm = webrtc::AudioProcessingBuilder().Create();
    if (!handle->apm) {
        pthread_mutex_destroy(&handle->mutex);
        delete handle;
        return nullptr;
    }

    handle->captureConfig = webrtc::StreamConfig(captureSampleRate, 1);
    handle->renderConfig = webrtc::StreamConfig(renderSampleRate, 1);
    handle->captureFrameSize = captureSampleRate / 100; // 10ms
    handle->renderFrameSize = renderSampleRate / 100;   // 10ms

    // Separate buffers — no shared state between threads.
    handle->captureFloatBuf = new float[handle->captureFrameSize];
    handle->renderFloatBuf = new float[handle->renderFrameSize];

    auto config = webrtc::AudioProcessing::Config();

    // Echo cancellation — AEC3 (full mode) with built-in delay estimator.
    // AEC3 finds the render-to-capture delay itself via matched-filter
    // cross-correlation, eliminating dependence on set_stream_delay_ms.
    config.echo_canceller.enabled = aecEnabled;
    config.echo_canceller.mobile_mode = false;
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

    os_log_info(apmLog(),
                "APM created: capture=%dHz render=%dHz aec=%d ns=%d agc=%d",
                captureSampleRate, renderSampleRate, aecEnabled, nsEnabled, agcEnabled);

    return static_cast<WebRtcApmHandle>(handle);
}

void webrtc_apm_bridge_destroy(WebRtcApmHandle ptr) {
    auto* handle = static_cast<ApmHandle*>(ptr);
    if (!handle) return;

    // Lock to drain any in-flight processCapture/processRender calls.
    pthread_mutex_lock(&handle->mutex);
    delete handle->apm;
    handle->apm = nullptr;
    delete[] handle->captureFloatBuf;
    handle->captureFloatBuf = nullptr;
    delete[] handle->renderFloatBuf;
    handle->renderFloatBuf = nullptr;
    pthread_mutex_unlock(&handle->mutex);

    pthread_mutex_destroy(&handle->mutex);
    delete handle;

    os_log_info(apmLog(), "APM destroyed");
}

void webrtc_apm_bridge_set_stream_delay(WebRtcApmHandle ptr, int delayMs) {
    auto* handle = static_cast<ApmHandle*>(ptr);
    if (handle) {
        handle->streamDelayMs = delayMs;
    }
}

void webrtc_apm_bridge_process_capture(WebRtcApmHandle ptr,
                                       int8_t* audioData,
                                       int dataLen) {
    auto* handle = static_cast<ApmHandle*>(ptr);
    if (!handle || dataLen == 0) return;

    pthread_mutex_lock(&handle->mutex);

    if (!handle->apm || !handle->captureFloatBuf) {
        pthread_mutex_unlock(&handle->mutex);
        return;
    }

    auto* inputSamples = reinterpret_cast<int16_t*>(audioData);
    int totalSamples = dataLen / 2;
    int frameSize = handle->captureFrameSize;
    if (frameSize <= 0) {
        pthread_mutex_unlock(&handle->mutex);
        return;
    }

    float* floatBuf = handle->captureFloatBuf;

    int offset = 0;
    while (offset + frameSize <= totalSamples) {
        // Set the estimated delay before each frame.
        handle->apm->set_stream_delay_ms(handle->streamDelayMs);

        // Convert int16 to float [-1.0, 1.0].
        for (int i = 0; i < frameSize; i++) {
            floatBuf[i] = static_cast<float>(inputSamples[offset + i]) / 32768.0f;
        }

        float* channelPtr = floatBuf;
        const float* constChannelPtr = floatBuf;
        handle->apm->ProcessStream(
            &constChannelPtr,
            handle->captureConfig,
            handle->captureConfig,
            &channelPtr);

        // Convert float back to int16 with clipping.
        for (int i = 0; i < frameSize; i++) {
            float val = floatBuf[i] * 32768.0f;
            if (val > 32767.0f) val = 32767.0f;
            if (val < -32768.0f) val = -32768.0f;
            inputSamples[offset + i] = static_cast<int16_t>(val);
        }

        offset += frameSize;
    }

    pthread_mutex_unlock(&handle->mutex);
}

void webrtc_apm_bridge_process_render(WebRtcApmHandle ptr,
                                      const int8_t* audioData,
                                      int dataLen) {
    auto* handle = static_cast<ApmHandle*>(ptr);
    if (!handle || dataLen == 0) return;

    pthread_mutex_lock(&handle->mutex);

    if (!handle->apm || !handle->renderFloatBuf) {
        pthread_mutex_unlock(&handle->mutex);
        return;
    }

    auto* inputSamples = reinterpret_cast<const int16_t*>(audioData);
    int totalSamples = dataLen / 2;
    int frameSize = handle->renderFrameSize;
    if (frameSize <= 0) {
        pthread_mutex_unlock(&handle->mutex);
        return;
    }

    float* floatBuf = handle->renderFloatBuf;

    int offset = 0;
    while (offset + frameSize <= totalSamples) {
        for (int i = 0; i < frameSize; i++) {
            floatBuf[i] = static_cast<float>(inputSamples[offset + i]) / 32768.0f;
        }

        float* channelPtr = floatBuf;
        const float* constChannelPtr = floatBuf;
        handle->apm->ProcessReverseStream(
            &constChannelPtr,
            handle->renderConfig,
            handle->renderConfig,
            &channelPtr);

        offset += frameSize;
    }

    pthread_mutex_unlock(&handle->mutex);
}

} // extern "C"

#endif // !TARGET_OS_SIMULATOR
