#ifndef WebRtcApmBridge_h
#define WebRtcApmBridge_h

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle to a WebRTC Audio Processing Module instance.
typedef void* WebRtcApmHandle;

/// Create an APM instance configured for echo cancellation, noise suppression,
/// and automatic gain control.
///
/// @param captureSampleRate  Mic capture sample rate in Hz (e.g., 48000).
/// @param renderSampleRate   Speaker playback sample rate in Hz (e.g., 24000).
/// @param aecEnabled         Enable acoustic echo cancellation (AECM mobile mode).
/// @param nsEnabled          Enable noise suppression (very high level).
/// @param agcEnabled         Enable automatic gain control (AGC2 adaptive digital).
/// @return Opaque handle, or NULL on failure.
WebRtcApmHandle webrtc_apm_bridge_create(int captureSampleRate,
                                         int renderSampleRate,
                                         bool aecEnabled,
                                         bool nsEnabled,
                                         bool agcEnabled);

/// Destroy an APM instance and release all resources.
void webrtc_apm_bridge_destroy(WebRtcApmHandle handle);

/// Set the estimated audio pipeline delay in milliseconds.
/// This helps AEC correlate the playback and capture signals.
void webrtc_apm_bridge_set_stream_delay(WebRtcApmHandle handle, int delayMs);

/// Process captured (near-end / microphone) audio through APM.
///
/// Audio is processed in-place in 10ms frames. The buffer must contain
/// PCM int16 LE samples at the capture sample rate.
///
/// @param handle    APM handle.
/// @param audioData Pointer to int16 PCM audio bytes (modified in-place).
/// @param dataLen   Length of audioData in bytes.
void webrtc_apm_bridge_process_capture(WebRtcApmHandle handle,
                                       int8_t* audioData,
                                       int dataLen);

/// Feed render (far-end / speaker playback) audio into APM as echo reference.
///
/// The buffer is read but not modified. Must contain PCM int16 LE samples
/// at the render sample rate.
///
/// @param handle    APM handle.
/// @param audioData Pointer to int16 PCM audio bytes (read-only).
/// @param dataLen   Length of audioData in bytes.
void webrtc_apm_bridge_process_render(WebRtcApmHandle handle,
                                      const int8_t* audioData,
                                      int dataLen);

#ifdef __cplusplus
}
#endif

#endif /* WebRtcApmBridge_h */
